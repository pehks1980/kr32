#!/usr/bin/env python3
"""Regression test for the kernel's derived NSFS directory indexes."""

from contextlib import redirect_stdout
from io import StringIO
from tempfile import TemporaryDirectory
from pathlib import Path

from device.nsfs import DIR_CREATE, FILE_CREATE, NS_CREATE, NSFSStore
from tools.assembler import Assembler
from tools.preprocess_cmacros import Preprocessor
from vmp import CPU


def read_u32(cpu, address):
    return int.from_bytes(cpu.physical_memory[address:address + 4], "little")


def read_cstr(cpu, address):
    end = address
    while cpu.physical_memory[end]:
        end += 1
    return bytes(cpu.physical_memory[address:end]).decode("utf-8")


def main():
    source = Path(__file__).resolve().parents[1] / "kernelshed.asm"
    processed = Preprocessor(source.parent).process(
        source.read_text(encoding="utf-8").splitlines()
    )
    assembler = Assembler()
    with redirect_stdout(StringIO()):
        assembler.build(processed, write_output=False)

    with TemporaryDirectory() as tmpdir:
        store = NSFSStore(Path(tmpdir) / "nsfs_store.json")
        packets = (
            (NS_CREATE, 7, b""),
            (DIR_CREATE, 7, b"/other"),
            (FILE_CREATE, 7, (12).to_bytes(4, "little") + b"/other/a.txtx"),
        )
        for opcode, namespace, payload in packets:
            status, _ = store.handle_packet({
                "opcode": opcode,
                "namespace": namespace,
                "payload": payload,
                "flags": 0,
            })
            assert status == 0

        image = Path(tmpdir) / "memory.img"
        with redirect_stdout(StringIO()):
            Assembler().build(processed, out=str(image))

        cpu = CPU()
        cpu.bmi.nsfs = store
        cpu.load_image(str(image))
        invalid_traps = []
        raise_trap = cpu.raise_trap

        def record_invalid_trap(vector, value=0, resume_pc=None):
            if vector == 1:
                invalid_traps.append((cpu.current_instr_pc, value))
            raise_trap(vector, value, resume_pc)

        cpu.raise_trap = record_invalid_trap
        with redirect_stdout(StringIO()):
            cpu.run(0, max_steps=300000)
        assert not invalid_traps, invalid_traps

        labels = assembler.labels
        namespace_count = read_u32(cpu, labels["NSFS_NAMESPACE_COUNT"])
        assert namespace_count == 2

        dirs = []
        dir_count = read_u32(cpu, labels["NSFS_DIR_COUNT"])
        for index in range(dir_count):
            entry = labels["NSFS_DIR_TABLE"] + index * 12
            dirs.append((
                read_u32(cpu, entry),
                read_cstr(cpu, read_u32(cpu, entry + 4)),
            ))
        assert (7, "/") in dirs
        assert (7, "/other") in dirs
        other_dir_id = dirs.index((7, "/other"))

        children = []
        child_count = read_u32(cpu, labels["NSFS_DIR_INDEX_COUNT"])
        for index in range(child_count):
            entry = labels["NSFS_DIR_INDEX"] + index * 20
            children.append((
                read_u32(cpu, entry),
                read_u32(cpu, entry + 4),
                read_cstr(cpu, read_u32(cpu, entry + 8)),
            ))
        assert (7, 1, "other") in children
        assert (7, other_dir_id, "a.txt") in children

    print("NSFS directory cache regression test passed")


if __name__ == "__main__":
    main()
