#!/bin/bash
set -e

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <source.c> [compiler options]" >&2
    exit 2
fi

python3 "$PROJECT_ROOT/krcc/test_assembler.py" "$@"
(cd "$PROJECT_ROOT" && bash ./buildshed.sh)
