#!/bin/bash
set -x
python3 tools/build_tarfs.py --root tarfs --output tarfs_generated.inc
python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm
mkdir -p lst
python3 assembler.py --list-file lst/kernelshed.lst.asm -o memory.img kernelshed_pre.asm
