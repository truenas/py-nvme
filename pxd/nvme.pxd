# cython: language_level=3, c_string_type=unicode, c_string_encoding=default

from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t

# NVMe SPEC: https://nvmexpress.org/wp-content/uploads/NVMe-NVM-Express-2.0a-2021.07.26-Ratified.pdf

# See 7.2, Figure 392 Reservation Acquire - Command Dword 10 (Bits 02:00)
cdef enum resv_acquire_action:
    acquire = 0x00
    preempt = 0x01
    preempt_and_abort = 0x02

# See 7.3, Figure 396: Reservation Register – Command Dword 10 (Bits 02:00)
cdef enum resv_register_action:
    register = 0x00
    unregister = 0x01
    replace = 0x02

# See 7.4, Figure 394 Reservation Type Encoding
ctypedef enum resv_type:
    write_exclusive = 0x01
    exclusive_access = 0x02
    write_exclusive_registrants_only = 0x03
    exclusive_access_registrants_only = 0x04
    write_exclusive_all_registrants = 0x05
    exclusive_access_all_registrants = 0x06

cdef extern from "endian.h":
    uint16_t le16toh(uint16_t)
    uint32_t le32toh(uint32_t)
    uint64_t le64toh(uint64_t)
    uint32_t htole32(uint32_t)
    uint64_t htole64(uint64_t)

cdef extern from "unistd.h":
    int getpagesize()

cdef extern from "linux/nvme_ioctl.h":
    struct nvme_passthru_cmd:
        uint8_t opcode
        uint8_t flags
        uint16_t rsvd1
        uint32_t nsid
        uint32_t cdw2
        uint32_t cdw3
        uint64_t metadata
        uint64_t addr
        uint32_t metadata_len
        uint32_t data_len
        uint32_t cdw10
        uint32_t cdw11
        uint32_t cdw12
        uint32_t cdw13
        uint32_t cdw14
        uint32_t cdw15
        uint32_t timeout_ms
        uint32_t result

    enum:
        NVME_IOCTL_IO_CMD
        NVME_IOCTL_ADMIN_CMD
        NVME_IOCTL_ID

ctypedef enum nvme_op_codes:
    nvme_admin_identify = 0x06
    nvme_cmd_resv_register = 0x0d
    nvme_cmd_resv_report = 0x0e
    nvme_cmd_resv_acquire = 0x11
    nvme_cmd_resv_release = 0x15

# CNS values for Identify command
cdef enum nvme_id_cns:
    NVME_ID_CNS_NS = 0x00      # Identify Namespace
    NVME_ID_CNS_CTRL = 0x01    # Identify Controller
    NVME_ID_CNS_NS_ACTIVE = 0x02  # Active Namespace ID list
    NVME_ID_CNS_NS_DESC = 0x03    # Namespace Identification Descriptor list

# include/linux/nvme.h
ctypedef struct nvme_registered_ctrl:
    uint16_t ctrlr_id
    uint8_t rcsts
    uint8_t rsvd3[5]
    uint64_t hostid
    uint64_t rkey

ctypedef struct nvme_reservation_status:
    uint32_t gen
    uint8_t rtype
    uint8_t regctl[2]
    uint8_t resv5[2]
    uint8_t ptpls
    uint8_t resv10[14]
    nvme_registered_ctrl ctrlr[0]

# Extended controller structure for 128-bit host IDs (when EDS=1)
ctypedef struct nvme_registered_ctrl_ext:
    uint16_t ctrlr_id
    uint8_t rcsts
    uint8_t rsvd3[5]
    uint64_t rkey
    uint8_t hostid[16]
    uint8_t rsvd32[32]

ctypedef struct nvme_reservation_status_ext:
    uint32_t gen
    uint8_t rtype
    uint8_t regctl[2]
    uint8_t resv5[2]
    uint8_t ptpls
    uint8_t resv10[14]
    uint8_t rsvd24[40];
    nvme_registered_ctrl_ext ctrlr[0]


# Power state descriptor
ctypedef struct nvme_id_power_state:
    uint16_t max_power
    uint8_t rsvd2
    uint8_t flags
    uint32_t entry_lat
    uint32_t exit_lat
    uint8_t read_tput
    uint8_t read_lat
    uint8_t write_tput
    uint8_t write_lat
    uint16_t idle_power
    uint8_t idle_scale
    uint8_t rsvd19
    uint16_t active_power
    uint8_t active_work_scale
    uint8_t rsvd23[9]

# Controller identify structure (include/linux/nvme.h)
ctypedef struct nvme_id_ctrl:
    uint16_t vid
    uint16_t ssvid
    char sn[20]
    char mn[40]
    char fr[8]
    uint8_t rab
    uint8_t ieee[3]
    uint8_t cmic
    uint8_t mdts
    uint16_t cntlid
    uint32_t ver
    uint32_t rtd3r
    uint32_t rtd3e
    uint32_t oaes
    uint32_t ctratt
    uint8_t rsvd100[11]
    uint8_t cntrltype
    uint8_t fguid[16]
    uint16_t crdt1
    uint16_t crdt2
    uint16_t crdt3
    uint8_t rsvd134[122]
    uint16_t oacs
    uint8_t acl
    uint8_t aerl
    uint8_t frmw
    uint8_t lpa
    uint8_t elpe
    uint8_t npss
    uint8_t avscc
    uint8_t apsta
    uint16_t wctemp
    uint16_t cctemp
    uint16_t mtfa
    uint32_t hmpre
    uint32_t hmmin
    uint8_t tnvmcap[16]
    uint8_t unvmcap[16]
    uint32_t rpmbs
    uint16_t edstt
    uint8_t dsto
    uint8_t fwug
    uint16_t kas
    uint16_t hctma
    uint16_t mntmt
    uint16_t mxtmt
    uint32_t sanicap
    uint32_t hmminds
    uint16_t hmmaxd
    uint8_t rsvd338[4]
    uint8_t anatt
    uint8_t anacap
    uint32_t anagrpmax
    uint32_t nanagrpid
    uint8_t rsvd352[160]
    uint8_t sqes
    uint8_t cqes
    uint16_t maxcmd
    uint32_t nn
    uint16_t oncs
    uint16_t fuses
    uint8_t fna
    uint8_t vwc
    uint16_t awun
    uint16_t awupf
    uint8_t nvscc
    uint8_t nwpc
    uint16_t acwu
    uint8_t rsvd534[2]
    uint32_t sgls
    uint32_t mnan
    uint8_t rsvd544[224]
    char subnqn[256]
    uint8_t rsvd1024[768]
    uint32_t ioccsz
    uint32_t iorcsz
    uint16_t icdoff
    uint8_t ctrattr
    uint8_t msdbd
    uint8_t rsvd1804[2]
    uint8_t dctype
    uint8_t rsvd1807[241]
    nvme_id_power_state psd[32]
    uint8_t vs[1024]
