#!/usr/bin/env python3
"""Regression test for BMI host mailbox handling."""

from tempfile import TemporaryDirectory

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
    BMIDevice,
)
from device.nsfs import NS_CREATE, NSFSStore


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


def mmio_write_u32(cpu, paddr, value):
    cpu.physical_write_u8(paddr + 0, value & 0xFF)
    cpu.physical_write_u8(paddr + 1, (value >> 8) & 0xFF)
    cpu.physical_write_u8(paddr + 2, (value >> 16) & 0xFF)
    cpu.physical_write_u8(paddr + 3, (value >> 24) & 0xFF)


def mmio_read_u32(cpu, paddr):
    return (
        cpu.physical_read_u8(paddr)
        | (cpu.physical_read_u8(paddr + 1) << 8)
        | (cpu.physical_read_u8(paddr + 2) << 16)
        | (cpu.physical_read_u8(paddr + 3) << 24)
    )


def main():
    tmpdir = TemporaryDirectory()
    cpu = CPU()
    cpu.bmi = BMIDevice(cpu=cpu, nsfs=NSFSStore(f"{tmpdir.name}/nsfs_store.json"))

    request_opcode = NS_CREATE
    request_flags = 0x0000
    request_namespace = 0
    request_payload = b""
    request_length = len(request_payload)

    base = BMI_BUF_WRITE
    write_u32(cpu, base + BMI_HDR_OPCODE, request_opcode & 0xFFFF)
    write_u32(cpu, base + BMI_HDR_FLAGS, request_flags & 0xFFFF)
    write_u32(cpu, base + BMI_HDR_NAMESPACE, request_namespace)
    write_u32(cpu, base + BMI_HDR_PAYLOAD_LEN, request_length)
    for i, b in enumerate(request_payload):
        cpu.physical_write_u8(base + BMI_HDR_SIZEOF + i, b)

    # Ring doorbell through the same byte-wise MMIO route used by STW.
    mmio_write_u32(cpu, BMI_STATUS, BMI_READY)
    mmio_write_u32(cpu, BMI_DOORBELL, 1)

    # The device should process on update().
    cpu.bmi.update()

    status = mmio_read_u32(cpu, BMI_STATUS)
    doorbell = mmio_read_u32(cpu, BMI_DOORBELL)
    reply_code = mmio_read_u32(cpu, BMI_REPLY)
    reply_opcode = read_u32(cpu, BMI_BUF_READ + BMI_HDR_OPCODE)
    reply_flags = read_u32(cpu, BMI_BUF_READ + BMI_HDR_FLAGS)
    reply_namespace = read_u32(cpu, BMI_BUF_READ + BMI_HDR_NAMESPACE)
    reply_length = read_u32(cpu, BMI_BUF_READ + BMI_HDR_PAYLOAD_LEN)

    assert status == BMI_DONE, f"expected status DONE, got {status}"
    assert doorbell == 0, f"expected doorbell cleared, got {doorbell}"
    assert reply_code == 0, f"expected reply code 0, got {reply_code}"
    assert reply_opcode == 0, f"expected reply opcode 0, got {reply_opcode}"
    assert reply_flags == 0, f"expected reply flags 0, got {reply_flags}"
    assert reply_namespace == 0, f"expected reply namespace 0, got {reply_namespace}"
    assert reply_length == 0, f"expected reply length 0, got {reply_length}"
    assert cpu.bmi.nsfs.namespace_exists(0), "expected namespace 0 to be created"

    print("BMI regression test passed")
    tmpdir.cleanup()


if __name__ == '__main__':
    main()
