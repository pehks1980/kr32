#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path

SYSROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SYSROOT))

from assembler import Assembler


ROOT = Path(__file__).resolve().parent.parent
TARFS_ROOT = ROOT / "tarfs"
OUT = ROOT / "tarfs_generated.inc"


def octal_size(length):
    return format(length, "011o")

def chunk_words(data):
    """
    Convert bytes into .WORDs.

    TAR requires file payloads to be padded to 512-byte boundaries.
    .WORD output additionally requires multiples of 4 bytes.
    """

    # TAR payload padding
    tar_padded = (len(data) + 511) & ~511

    # (512 is divisible by 4, so this is mostly for safety)
    word_padded = (tar_padded + 3) & ~3

    padded_data = data.ljust(word_padded, b"\x00")

    words = []

    for i in range(0, len(padded_data), 4):
        words.append(int.from_bytes(padded_data[i:i+4], "little"))

    return words, tar_padded


def chunk_words_old(data):
    padded = (len(data) + 3) // 4 * 4
    padded_data = data.ljust(padded, b"\x00")
    words = [int.from_bytes(padded_data[i : i + 4], "little") for i in range(0, len(padded_data), 4)]
    return words, padded


def normalize_path(path: Path):
    rel = path.resolve().relative_to(TARFS_ROOT.resolve()).as_posix()
    if rel.endswith(".asm"):
        rel = rel[:-4]
    return rel.lstrip("/")


def read_source_bytes(path: Path):
    if path.suffix == ".asm":
        src = subprocess.run(
            ["python3", str(ROOT / "tools" / "preprocess_cmacros.py"), str(path)],
            check=True,
            capture_output=True,
            text=True,
            cwd=str(ROOT),
        ).stdout.splitlines(True)
        asm = Assembler()
        lines = src
        asm.build(lines, out="/tmp/tarfs_build.img", write_output=False)
        start = 0x043000
        end = asm.pc
        return bytes(asm.memory[start:end])
    return path.read_bytes()

def emit_dir(path: str):
    name = path.rstrip("/") + "/"

    name_bytes = name.encode("ascii")
    if len(name_bytes) >= 124:
        raise ValueError(f"tar path too long: {name}")

    return [
        f"; {name}",
        f'    .ASCIIZ "{name}"',
        f"    .SPACE {124 - len(name_bytes) - 1}",
        '    .ASCIIZ "00000000000"',   # size = 0
        "    .SPACE 20",
        '    .ASCIIZ "5"',             # TAR directory
        "    .SPACE 354",
        "",
    ]


def emit_entry(path: str, data: bytes):
    name_bytes = path.encode("ascii")
    if len(name_bytes) >= 124:
        raise ValueError(f"tar path too long: {path}")

    lines = []
    lines.append(f"; {path}, {len(data)} bytes")
    lines.append(f'    .ASCIIZ "{path}"')
    lines.append(f"    .SPACE {124 - len(name_bytes) - 1}")
    lines.append(f'    .ASCIIZ "{octal_size(len(data))}"')
    lines.append("    .SPACE 20")
    lines.append('    .ASCIIZ "0"')
    lines.append("    .SPACE 354")

    words, padded_len = chunk_words(data)
    lines.append(f"    ; file data ({len(data)} bytes, padded to {padded_len})")
    for idx in range(0, len(words), 8):
        chunk = words[idx : idx + 8]
        lines.append("    .WORD " + ", ".join(f"0x{word:08X}" for word in chunk))
    if len(words) * 4 < padded_len:
        lines.append(f"    .SPACE {padded_len - len(words) * 4}")
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(TARFS_ROOT))
    parser.add_argument("--output", default=str(OUT))
    args = parser.parse_args()

    root = Path(args.root).resolve()

    dirs = sorted(
        p for p in root.rglob("*")
        if p.is_dir()
    )

    files = sorted(
        p for p in root.rglob("*")
        if p.is_file()
    )

    lines = [".ORG 0xA0000", "tarfs_start:"]

    for d in dirs:
        lines.extend(emit_dir(normalize_path(d)))

    for f in files:
        data = read_source_bytes(f)
        lines.extend(emit_entry(normalize_path(f), data))
        lines.append("")

    lines.append("    .SPACE 1024")
    lines.append("tarfs_end:")
    lines.append("")

    Path(args.output).write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {args.output} from {len(files)} file(s)")


if __name__ == "__main__":
    main()
