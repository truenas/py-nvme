# cython: language_level=3, c_string_type=unicode, c_string_encoding=default
from posix.ioctl cimport ioctl
from posix.fcntl cimport open, O_RDONLY
from posix.stdlib cimport posix_memalign
from posix.unistd cimport close
from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t, uintptr_t
from libc.string cimport memset
from libc.stdlib cimport free

from pxd cimport nvme

NVME_DEFAULT_IOCTL_TIMEOUT_MS = 5000  # 5 seconds


cdef class NvmeDevice(object):

    cdef const char *dev
    cdef int nsid
    cdef int fd

    def __cinit__(self, path):
        self.dev = path
        with nogil:
            # get file descriptor
            self.fd = open(self.dev, O_RDONLY)
            if self.fd == -1:
                raise OSError(f'Failed to open {self.dev!r}')

            # get namespace id
            self.nsid = ioctl(self.fd, nvme.NVME_IOCTL_ID)
            if self.nsid <= 0:
                raise OSError(f'Failed to get namespace ID for {self.dev!r}')

    def __dealloc__(self):
        with nogil:
            if self.fd != -1:
                close(self.fd)

    def __resv_report(self):
        cdef nvme.nvme_passthru_cmd pt
        cdef nvme.nvme_resv_status *status
        cdef int size = 4096
        cdef bint eds = False
        cdef int err = -1

        # where the result is stored
        err = posix_memalign(<void **>&status, nvme.getpagesize(), size)
        if err != 0:
            raise MemoryError('No memory for reading reservation keys')
        memset(status, 0, size)

        # the formatted ioctl command
        memset(&pt, 0, sizeof(pt))
        pt.opcode = nvme.nvme_op_codes.nvme_cmd_resv_report
        pt.nsid = self.nsid
        pt.cdw10 = (size >> 2) - 1
        pt.cdw11 = eds
        pt.addr = <uint64_t><uintptr_t>status
        pt.data_len = size
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        err = ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt)
        if err < 0:
            raise OSError(f'Failed to issue ioctl to {self.dev!r}')

        # registered controllers
        regctl = status.regctl[0] | (status.regctl[1] << 8)

        info = {}
        info['generation'] = f'0x{nvme.le32toh(status.gen):x}'
        info['scopetype'] = status.rtype
        info['number_of_registered_controllers'] = regctl
        info['persist_through_power_loss_state'] = status.ptpls
        info['controllers'] = []
        for i in range(int(min(regctl, (size - 24 / 24)))):
            info['controllers'].append({
                'controller_id': f'0x{nvme.le16toh(status.ctrlr[i].ctrlr_id):x}',
                'resv_status': f'0x{status.ctrlr[i].rcsts:x}',
                'host_id': f'0x{nvme.le64toh(status.ctrlr[i].hostid):x}',
                'key': f'0x{nvme.le64toh(status.ctrlr[i].rkey):x}'
            })

        free(status)
        return info

    def read_keys(self):
        '''
        This function returns:
            1. the number of keys that have been put on the disk (generation)
            2. the specific keys that have been put on the disk (keys)
        '''
        d = self.__resv_report()
        return {'generation': d['generation'], 'keys': [i['key'] for i in d['controllers']]}

    def read_reservation(self):
        '''
        This function returns:
            1. the number of keys that have been put on the disk (generation)
            2. the type of reservation that is being held (scopetype)
            3. the reservation key that reserves the disk (reservation)
        '''
        d = self.__resv_report()
        for i in d['controllers']:
            if i['resv_status'] == '0x1':
                return {'generation': d['generation'], 'scopetype': d['scopetype'], 'reservation': i['key']}

    def update_key(self, cur_key, new_key):
        '''
        Update an existing `cur_key` with a new `new_key`.
        '''
        cdef nvme.nvme_passthru_cmd pt
        cdef uint64_t[2] payload = [nvme.htole64(cur_key), nvme.htole64(new_key)]
        cdef int err = -1

        memset(&pt, 0, sizeof(pt))
        pt.opcode = nvme.nvme_op_codes.nvme_cmd_resv_register
        pt.nsid = self.nsid
        pt.cdw10 = (2 & 0x7)
        pt.addr = <uint64_t><uintptr_t>payload
        pt.data_len = sizeof(payload)
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        err = ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt)
        if err < 0:
            raise OSError(f'Failed to update current key {cur_key!r} with new key {new_key!r} on {self.dev!r}')
        return True

    def register_ignore_key(self, key):
        '''
        Registers a `key` to a disk ignoring any keys that already exist that are owned by this host.
        '''
        cdef nvme.nvme_passthru_cmd pt
        cdef uint64_t[2] payload = [nvme.htole64(0), nvme.htole64(key)]
        cdef int err = -1

        memset(&pt, 0, sizeof(pt))
        pt.opcode = nvme.nvme_op_codes.nvme_cmd_resv_register
        pt.nsid = self.nsid
        pt.cdw10 = 1 | (2 << 30)
        pt.addr = <uint64_t><uintptr_t>payload
        pt.data_len = sizeof(payload)
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        err = ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt)
        if err < 0:
            raise OSError(f'Failed to register key {key!r} on {self.dev!r}')
        return True
    
    def register_new_key(self, key):
        '''
        Registers a new `key` to the disk.
        '''
        cdef nvme.nvme_passthru_cmd pt
        cdef uint64_t[2] payload = [nvme.htole64(0), nvme.htole64(key)]
        cdef int err = -1

        memset(&pt, 0, sizeof(pt))
        pt.opcode = nvme.nvme_op_codes.nvme_cmd_resv_register
        pt.nsid = self.nsid
        pt.cdw10 = 0 | (2 << 30)
        pt.addr = <uint64_t><uintptr_t>payload
        pt.data_len = sizeof(payload)
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        err = ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt)
        if err < 0:
            raise OSError(f'Failed to register new key {key!r} on {self.dev!r}')
        return True
    
    def preempt_key(self, cur_key, new_key):
        '''
        Preempts an existing `cur_key` that is reserving the disk and places a new reservation on the disk
        via `new_key`.
        '''
        cdef nvme.nvme_passthru_cmd pt
        cdef uint64_t[2] payload = [nvme.htole64(cur_key), nvme.htole64(new_key)]
        cdef int err = -1

        memset(&pt, 0, sizeof(pt))
        pt.opcode = nvme.nvme_op_codes.nvme_cmd_resv_acquire
        pt.nsid = self.nsid
        pt.cdw10 = 1 | (1 << 8)
        pt.addr = <uint64_t><uintptr_t>payload
        pt.data_len = sizeof(payload)
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        err = ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt)
        if err < 0:
            raise OSError(f'Failed to preempt current key {cur_key!r} with new key {new_key!r} on {self.dev!r}')
        return True

    def reserve_key(self, key):
        '''
        Place a write exclusive reservation using `key` on the disk.
        '''
        cdef nvme.nvme_passthru_cmd pt
        cdef uint64_t[2] payload = [nvme.htole64(key), nvme.htole64(0)]
        cdef int err = -1

        memset(&pt, 0, sizeof(pt))
        pt.opcode = nvme.nvme_op_codes.nvme_cmd_resv_acquire
        pt.nsid = self.nsid
        pt.cdw10 = 0 | (1 << 8)
        pt.addr = <uint64_t><uintptr_t>payload
        pt.data_len = sizeof(payload)
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        err = ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt)
        if err < 0:
            raise OSError(f'Failed to reserve {self.dev!r} with {key!r}')
        return True
