#!/usr/bin/env python3
"""Regression test for the kernel's derived NSFS directory indexes."""

from contextlib import redirect_stdout
from io import StringIO
from tempfile import TemporaryDirectory
from pathlib import Path

from device.nsfs import DIR_CREATE, FILE_CREATE, NS_CREATE, NSFSStore
from tools.assembler import Assembler
from tools.preprocess_cmacros import Preprocessor
from vmp import CPU, MODE_KERNEL


def read_u32(cpu, address):
    return int.from_bytes(cpu.physical_memory[address:address + 4], "little")


def write_u32(cpu, address, value):
    cpu.physical_memory[address:address + 4] = (value & 0xFFFFFFFF).to_bytes(4, "little")


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

        # Exercise the reader itself with descendants that must not appear
        # as duplicate entries in their ancestor directory.
        scratch = labels["BMI_BUF_WRITE"] + 0x800
        names = labels["BMI_BUF_READ"] + 0x200
        user_dirent = labels["BMI_BUF_READ"] + 0x100
        file_ptr = scratch + 0x100
        frame = scratch + 0x200
        sentinel = 0x1F00
        root_path = labels["NSFS_ROOT_PATH"]
        aaa_path = names
        bbb_path = names + 8
        nested_name = names + 16
        def write_cstr(address, text):
            encoded = text.encode("utf-8") + b"\0"
            cpu.physical_memory[address:address + len(encoded)] = encoded

        write_cstr(aaa_path, "aaa")
        write_cstr(bbb_path, "bbb")
        write_cstr(nested_name, "inside.txt")

        write_u32(cpu, labels["NSFS_DIR_COUNT"], 2)
        for index, (path, path_ptr) in enumerate((("/", root_path), ("/aaa/", names + 32))):
            entry = labels["NSFS_DIR_TABLE"] + index * 12
            write_u32(cpu, entry, 0)
            write_u32(cpu, entry + 4, path_ptr)
            write_u32(cpu, entry + 8, 0)
            if path != "/":
                write_cstr(path_ptr, path)

        write_u32(cpu, labels["NSFS_INDEX_COUNT"], 3)
        for index, (entry_type, size) in enumerate(((2, 0), (2, 0), (1, 11))):
            entry = labels["NSFS_INDEX_TABLE"] + index * 24
            write_u32(cpu, entry, 0)
            write_u32(cpu, entry + 4, entry_type)
            write_u32(cpu, entry + 8, size)

        write_u32(cpu, labels["NSFS_DIR_INDEX_COUNT"], 3)
        child_records = (
            (0, aaa_path, 0, 2),
            (0, bbb_path, 1, 2),
            (1, nested_name, 2, 1),
        )
        for index, (parent_id, name_ptr, object_index, entry_type) in enumerate(child_records):
            entry = labels["NSFS_DIR_INDEX"] + index * 20
            write_u32(cpu, entry, 0)
            write_u32(cpu, entry + 4, parent_id)
            write_u32(cpu, entry + 8, name_ptr)
            write_u32(cpu, entry + 12, object_index)
            write_u32(cpu, entry + 16, entry_type)

        write_u32(cpu, file_ptr + 4, 0)
        tar_count = read_u32(cpu, labels["TAR_COUNT"])
        write_u32(cpu, file_ptr + 4, tar_count)
        cpu.quiet = True

        def read_merged_entry():
            frame_values = (user_dirent, file_ptr, 0, root_path, 0, 0, sentinel)
            for word_index, value in enumerate(frame_values):
                write_u32(cpu, frame + word_index * 4, value)
            cpu.set_sp(frame)
            cpu.reg[6] = read_u32(cpu, file_ptr + 4)
            cpu.reg[10] = root_path
            cpu.reg[12] = file_ptr
            cpu.reg[15] = sentinel
            cpu.mode = MODE_KERNEL
            cpu.add_breakpoint(sentinel)
            cpu.run(labels["READDIR_NSFS_START"], max_steps=1000)
            cpu.clear_breakpoint(sentinel)
            return cpu.reg[1], read_cstr(cpu, user_dirent + 12)

        assert read_merged_entry() == (76, "aaa")
        assert read_u32(cpu, file_ptr + 4) == tar_count + 1
        assert read_merged_entry() == (76, "bbb")
        assert read_u32(cpu, file_ptr + 4) == tar_count + 2
        assert read_merged_entry()[0] == 0

    print("NSFS directory cache regression test passed")


if __name__ == "__main__":
    main()
