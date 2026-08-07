#!/usr/bin/env python3
"""Regression test for BMI host mailbox handling."""

from vmp import CPU
from device.bmi import (
    BMI_REG_BASE,
    BMI_STATUS,
    BMI_DOORBELL,
    BMI_REPLY,
    BMI_BUF_WRITE,
    BMI_BUF_READ,
    BMI_HDR_OPCODE,
    BMI_HDR_FLAGS,
    BMI_HDR_NAMESPACE,
    BMI_HDR_PAYLOAD_LEN,
    BMI_HDR_SIZEOF,
    BMI_READY,
    BMI_DONE,
)


def write_u32(cpu, paddr, value):
    cpu.physical_write_u8(paddr + 0, value & 0xFF)
    cpu.physical_write_u8(paddr + 1, (value >> 8) & 0xFF)
    cpu.physical_write_u8(paddr + 2, (value >> 16) & 0xFF)
    cpu.physical_write_u8(paddr + 3, (value >> 24) & 0xFF)


def read_u32(cpu, paddr):
    return (
        cpu.physical_read_u8(paddr)
        | (cpu.physical_read_u8(paddr + 1) << 8)
        | (cpu.physical_read_u8(paddr + 2) << 16)
        | (cpu.physical_read_u8(paddr + 3) << 24)
    )


def main():
    cpu = CPU()

    request_opcode = 0x10
    request_flags = 0x0000
    request_namespace = 0x12345678
    request_payload = b"test"
    request_length = len(request_payload)

    base = BMI_BUF_WRITE
    write_u32(cpu, base + BMI_HDR_OPCODE, request_opcode & 0xFFFF)
    write_u32(cpu, base + BMI_HDR_FLAGS, request_flags & 0xFFFF)
    write_u32(cpu, base + BMI_HDR_NAMESPACE, request_namespace)
    write_u32(cpu, base + BMI_HDR_PAYLOAD_LEN, request_length)
    for i, b in enumerate(request_payload):
        cpu.physical_write_u8(base + BMI_HDR_SIZEOF + i, b)

    # Ring doorbell through MMIO route.
    cpu.physical_write_u8(BMI_STATUS, BMI_READY)
    cpu.physical_write_u8(BMI_DOORBELL, 1)

    # The device should process on update().
    cpu.bmi.update()

    status = cpu.bmi.read_reg(0)
    doorbell = cpu.bmi.read_reg(4)
    reply_opcode = read_u32(cpu, BMI_BUF_READ + BMI_HDR_OPCODE)
    reply_flags = read_u32(cpu, BMI_BUF_READ + BMI_HDR_FLAGS)
    reply_namespace = read_u32(cpu, BMI_BUF_READ + BMI_HDR_NAMESPACE)
    reply_length = read_u32(cpu, BMI_BUF_READ + BMI_HDR_PAYLOAD_LEN)

    assert status == BMI_DONE, f"expected status DONE, got {status}"
    assert doorbell == 0, f"expected doorbell cleared, got {doorbell}"
    assert reply_opcode == 0, f"expected reply opcode 0, got {reply_opcode}"
    assert reply_flags == 0, f"expected reply flags 0, got {reply_flags}"
    assert reply_namespace == 0, f"expected reply namespace 0, got {reply_namespace}"
    assert reply_length == 0, f"expected reply length 0, got {reply_length}"

    print("BMI regression test passed")


if __name__ == '__main__':
    main()
