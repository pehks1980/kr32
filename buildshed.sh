#!/bin/bash
python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm
python3 assembler.py --list -o memory.img kernelshed_pre.asm > kernelshed.lst.asm