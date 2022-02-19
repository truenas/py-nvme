# cython: language_level=3, c_string_type=unicode, c_string_encoding=default

from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t

cdef extern from "endian.h":
    uint16_t le16toh(uint16_t)
    uint32_t le32toh(uint32_t)
    uint64_t le64toh(uint64_t)
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
        NVME_IOCTL_ID

ctypedef enum nvme_op_codes:
    nvme_cmd_resv_register = 0x0d
    nvme_cmd_resv_report = 0x0e
    nvme_cmd_resv_acquire = 0x11
    nvme_cmd_resv_release = 0x15

ctypedef struct nvme_resv_reg_ctrlr:
    uint16_t ctrlr_id
    uint8_t rcsts
    uint8_t resv3[5]
    uint64_t hostid
    uint64_t rkey

ctypedef struct nvme_resv_status:
    uint32_t gen
    uint8_t rtype
    uint8_t regctl[2]
    uint8_t resv5[2]
    uint8_t ptpls
    uint8_t resv10[13]
    nvme_resv_reg_ctrlr ctrlr[0]
