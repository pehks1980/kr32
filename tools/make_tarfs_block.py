#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path

SYSROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SYSROOT))

from assembler import Assembler


def parse_args():
    parser = argparse.ArgumentParser(
        description="Assemble a user task at ORG 0x7000 and generate a TARFS inline block."
    )
    parser.add_argument("input", help="Input assembly source file")
    parser.add_argument("--path", required=True, help="Target path inside TARFS (e.g. /bin/exec_test)")
    parser.add_argument("--output", default="tarfs_block.txt", help="Output text file to write")
    parser.add_argument("--org", default="0x7000", help="ORG address to force into the assembled input")
    parser.add_argument("--force-org", action="store_true", help="Force .ORG to the requested value even if input contains another .ORG")
    return parser.parse_args()


DEFAULT_DEFS = [
    ".EQU SYS_YIELD 0",
    ".EQU SYS_EXIT 1",
    ".EQU SYS_GETPID 2",
    ".EQU SYS_DEBUG 3",
    ".EQU SYS_WRITE 4",
    ".EQU SYS_READ 5",
    ".EQU SYS_OPEN 6",
    ".EQU SYS_CLOSE 7",
    ".EQU SYS_PIPE 8",
    ".EQU SYS_DUP 9",
    ".EQU SYS_GETTIME 10",
    ".EQU SYS_BRK 11",
    ".EQU SYS_SBRK 12",
    ".EQU SYS_EXECVE 13",
    ".EQU FD_FLAG_READ 1",
    ".EQU FD_FLAG_WRITE 2",
]


def ensure_org(lines, org_value, force=False):
    trimmed = [line.strip() for line in lines if line.strip() and not line.lstrip().startswith(";")]
    if not trimmed:
        return lines

    first_non_comment = trimmed[0]
    if first_non_comment.upper().startswith(".ORG"):
        if force:
            # replace first .ORG in original lines
            for idx, line in enumerate(lines):
                if line.strip() and not line.lstrip().startswith(";"):
                    if line.strip().upper().startswith(".ORG"):
                        lines[idx] = f".ORG {org_value}\n"
                    break
        return DEFAULT_DEFS + lines

    # no .ORG found in first non-comment statements, inject one before content
    return DEFAULT_DEFS + [f".ORG {org_value}\n"] + lines


def format_octal_size(length):
    octal = format(length, "011o")
    return octal


def chunk_words(data):
    words = []
    padded = (len(data) + 3) // 4 * 4
    padded_data = data.ljust(padded, b"\x00")
    for i in range(0, len(padded_data), 4):
        word = int.from_bytes(padded_data[i : i + 4], "little")
        words.append(word)
    return words, padded

def build_tar_block(path, data):
    name = path.lstrip("/")
    name_bytes = name.encode("ascii")

    if len(name_bytes) >= 124:
        raise ValueError("Path too long")

    size_octal = format(len(data), "011o")

    #
    # TAR header (512 bytes)
    #
    header = []

    header.append(f"; {path}, {len(data)} bytes")
    header.append(f'    .ASCIIZ "{name}"')
    header.append(f"    .SPACE {124 - len(name_bytes) - 1}")
    header.append(f'    .ASCIIZ "{size_octal}"')
    header.append("    .SPACE 20")
    header.append('    .ASCIIZ "0"')
    header.append("    .SPACE 354")

    #
    # File data
    #

    payload = []

    word_padded = (len(data) + 3) & ~3
    padded_data = data.ljust(word_padded, b"\x00")

    payload.append(f"    ; file data ({len(data)} bytes)")

    for i in range(0, word_padded, 32):          # 8 words per line
        words = []
        for j in range(i, min(i + 32, word_padded), 4):
            w = int.from_bytes(padded_data[j:j+4], "little")
            words.append(f"0x{w:08X}")

        payload.append("    .WORD " + ", ".join(words))

    #
    # TAR block padding
    #

    tar_padded = (len(data) + 511) & ~511
    pad = tar_padded - word_padded

    if pad:
        payload.append(f"    .SPACE {pad}    ; pad to next TAR block")

    return header + payload

def main():
    args = parse_args()
    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    with input_path.open("r", encoding="utf-8") as f:
        lines = f.readlines()

    org_value = args.org
    lines = ensure_org(lines, org_value, force=args.force_org)

    asm = Assembler()
    asm.build(lines, out=str(Path("/tmp/tarfs_block_tmp.img")), write_output=False)
    org_addr = int(org_value, 0)
    if asm.pc <= org_addr:
        raise RuntimeError(f"Assembled binary end {asm.pc:#x} is before ORG {org_addr:#x}")
    binary = asm.memory[org_addr : asm.pc]

    if len(binary) == 0:
        raise RuntimeError("Assembled binary is empty")

    block_lines = build_tar_block(args.path, binary)

    with open(args.output, "w", encoding="utf-8") as out:
        out.write("\n".join(block_lines) + "\n")

    print(f"Wrote TARFS block to {args.output}")
    print(f"Assembled {args.input} to {len(binary)} bytes at ORG {org_value}")


if __name__ == "__main__":
    main()
