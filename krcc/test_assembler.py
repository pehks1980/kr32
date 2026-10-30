import argparse
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from codegen import CodeGenerator
from lexer import Lexer
from parser import Parser
from tools.assembler import Assembler


def compile_source(source_path, output_path):
    source = source_path.read_text(encoding="utf-8")

    tokens = Lexer(source).tokenize()
    ast = Parser(tokens).parse_translation_unit()
    assembly = CodeGenerator().generate(ast)

    assembler = Assembler()
    assembler.build(assembly.splitlines(), write_output=False)

    entry = assembler.labels.get("PROGRAM_START")
    if entry is None or assembler.pc <= entry:
        raise RuntimeError("Compiler produced an empty or invalid executable")

    binary = bytes(assembler.memory[entry:assembler.pc])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(binary)
    print(f"Compiled {source_path} -> {output_path} ({len(binary)} bytes)")


def main():
    parser = argparse.ArgumentParser(
        description="Compile a supported C source file to a KR32 executable."
    )
    parser.add_argument("source", type=Path, help="C source file to compile")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="output executable (default: tarfs/c/<source-name>.bin)",
    )
    args = parser.parse_args()

    source_path = args.source.resolve()
    output_path = args.output
    if output_path is None:
        output_path = PROJECT_ROOT / "tarfs" / "c" / f"{source_path.stem}.bin"
    elif not output_path.is_absolute():
        output_path = Path.cwd() / output_path

    compile_source(source_path, output_path)


if __name__ == "__main__":
    main()
