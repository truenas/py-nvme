# cython: language_level=3, c_string_type=unicode, c_string_encoding=default
from os import strerror

from posix.ioctl cimport ioctl
from posix.fcntl cimport open, O_RDONLY
from posix.stdlib cimport posix_memalign
from posix.unistd cimport close
from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t, uintptr_t
from libc.string cimport memset
from libc.stdlib cimport free
from libc.errno cimport errno

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
                raise OSError(errno, strerror(errno), self.dev)

            # get namespace id
            self.nsid = ioctl(self.fd, nvme.NVME_IOCTL_ID)
            if self.nsid <= 0:
                raise OSError(errno, strerror(errno), self.dev)

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
            raise OSError('Failed to issue ioctl')

        # registered controllers
        regctl = status.regctl[0] | (status.regctl[1] << 8)

        info = {}
        info['generation'] = nvme.le32toh(status.gen)
        info['scopetype'] = status.rtype
        info['number_of_registered_controllers'] = regctl
        info['persist_through_power_loss_state'] = status.ptpls
        info['controllers'] = []
        for i in range(int(min(regctl, (size - 24 / 24)))):
            info['controllers'].append({
                'controller_id': nvme.le16toh(status.ctrlr[i].ctrlr_id),
                'resv_status': status.ctrlr[i].rcsts,
                'host_id': nvme.le64toh(status.ctrlr[i].hostid),
                'key': nvme.le64toh(status.ctrlr[i].rkey)
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
        return {
            'generation': d['generation'],
            'scopetype': d['scopetype'],
            'reservation': d['controllers'][0]['key'] if d['controllers'] else None,
        }

    def __submit_io(self, cur_key=0, new_key=0, cdw10=0, opcode=nvme.nvme_op_codes.nvme_cmd_resv_register):
        cdef nvme.nvme_passthru_cmd pt
        cdef uint64_t[2] payload = [nvme.htole64(cur_key), nvme.htole64(new_key)]

        memset(&pt, 0, sizeof(pt))
        pt.opcode = opcode
        pt.nsid = self.nsid
        pt.cdw10 = nvme.htole32(<uint32_t>cdw10)
        pt.addr = <uint64_t><uintptr_t>payload
        pt.data_len = sizeof(payload)
        pt.timeout_ms = NVME_DEFAULT_IOCTL_TIMEOUT_MS
        return not bool(ioctl(self.fd, nvme.NVME_IOCTL_IO_CMD, &pt))

    def update_key(self, cur_key, new_key):
        '''
        Update an existing `cur_key` with a new `new_key`.
        '''
        if not self.__submit_io(cur_key=cur_key, new_key=new_key, cdw10=(2 & 0x7)):
            raise OSError(f'Failed to update current key {cur_key!r} with new key {new_key!r}')
        return True

    def register_ignore_key(self, key):
        '''
        Registers a `key` to a disk ignoring any keys that already exist that are owned by this host.
        '''
        reservation_registration_action = (nvme.resv_register_action.register & 0x7)
        ignore_existing_registration_key = (1 << 3)
        change_persist_thru_powerloss = (2 << 30)
        cdw10 = reservation_registration_action | ignore_existing_registration_key | change_persist_thru_powerloss
        if not self.__submit_io(new_key=key, cdw10=cdw10):
            # NVMe reservation related commands have a notion of replace while scsi
            # does not. To make it even more confusing, we have drives that behave
            # differently (some succeed, some do not) when a request is sent to replace
            # and ignore any existing keys on the nvme disk. This is a subtle behavioral
            # difference between scsi and nvme since scsi doesn’t have a notion of “replace”,
            # it just has a “register and ignore”.

            # We sent a traditional "register and ignore" command, which failed. Now let's
            # try a "replace and ignore"
            reservation_registration_action = (nvme.resv_register_action.replace & 0x7)
            cdw10 = reservation_registration_action | ignore_existing_registration_key | change_persist_thru_powerloss
            if not self.__submit_io(new_key=key, cdw10=cdw10):
                raise OSError(f'Failed to register, ignore and register, replace key {key!r}')

        return True

    def register_new_key(self, key):
        '''
        Registers a new `key` to the disk.
        '''
        reservation_registration_action = (nvme.resv_register_action.register & 0x7)
        ignore_existing_registration_key = 0
        change_persist_thru_powerloss = (2 << 30)
        cdw10 = reservation_registration_action | ignore_existing_registration_key | change_persist_thru_powerloss
        if not self.__submit_io(new_key=key, cdw10=cdw10):
            raise OSError(f'Failed to register new key {key!r}')
        return True

    def preempt_key(self, cur_key, pr_key):
        '''
        Preempt the existing `pr_key` with `cur_key`
        '''
        opcode = nvme.nvme_op_codes.nvme_cmd_resv_acquire
        reservation_acquire_action = (nvme.resv_acquire_action.preempt & 0x7)
        reservation_acquire_type = (nvme.resv_type.write_exclusive << 8)
        cdw10 = reservation_acquire_action | reservation_acquire_type
        if not self.__submit_io(cur_key=pr_key, new_key=cur_key, cdw10=cdw10, opcode=opcode):
            raise OSError(f'Failed to preempt current key {pr_key!r} with new key {cur_key!r}')
        return True

    def reserve_key(self, key):
        '''
        Place a write exclusive reservation using `key` on the disk.
        '''
        opcode = nvme.nvme_op_codes.nvme_cmd_resv_acquire
        reservation_acquire_action = (nvme.resv_acquire_action.acquire & 0x7)
        reservation_acquire_type = (nvme.resv_type.write_exclusive << 8)
        cdw10 = reservation_acquire_action | reservation_acquire_type
        if not self.__submit_io(cur_key=key, cdw10=cdw10, opcode=opcode):
            raise OSError(f'Failed to reserve using key {key!r}')
        return True
