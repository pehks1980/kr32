from pathlib import Path
import re
import unittest

from codegen import CodeGenerator
from layout import StorageLayout
from lexer import Lexer
from parser import Parser
from semantic import SemanticAnalyzer
from tools.assembler import Assembler
from tools.preprocess_cmacros import Preprocessor


EXAMPLES = Path(__file__).parent / "examples"
PROJECT_ROOT = EXAMPLES.parent.parent


def compile_example(name):
    source = (EXAMPLES / name).read_text(encoding="utf-8")
    ast = Parser(Lexer(source).tokenize()).parse_translation_unit()
    ast = SemanticAnalyzer().analyze(ast)
    ast = StorageLayout().layout(ast)
    return CodeGenerator().generate(ast)


def instructions_without_comments(assembly):
    return [
        line.split(";", 1)[0].rstrip()
        for line in assembly.splitlines()
    ]


class LoopCodegenTests(unittest.TestCase):
    def test_printf_uses_libc_for_format_strings_without_arguments(self):
        assembly = compile_example("hello.c")

        self.assertIn('#include "tarfs/lib/libc.inc"', assembly)
        self.assertNotIn("_start:", assembly)
        self.assertEqual(assembly.count("    BL printf"), 2)
        self.assertIn("    LI R1 printf_string_0", assembly)
        self.assertNotIn("    SVC SYS_WRITE", assembly)

        expanded = Preprocessor(PROJECT_ROOT).process(assembly.splitlines())
        assembler = Assembler()
        assembler.build(expanded, write_output=False)

        self.assertIn("_START", assembler.labels)
        self.assertIn("MAIN", assembler.labels)
        self.assertIn("PRINTF", assembler.labels)

    def test_while_checks_condition_before_body(self):
        lines = instructions_without_comments(compile_example("while.c"))

        start = lines.index("while_start_0:")
        branch_to_body = lines.index("    BLT while_body_1")
        branch_to_end = lines.index("    B while_end_2")
        body = lines.index("while_body_1:")
        back_edge = lines.index("    B while_start_0")
        end = lines.index("while_end_2:")

        self.assertLess(start, branch_to_body)
        self.assertLess(branch_to_body, branch_to_end)
        self.assertLess(branch_to_end, body)
        self.assertLess(body, back_edge)
        self.assertLess(back_edge, end)

    def test_do_while_checks_condition_after_body(self):
        lines = instructions_without_comments(compile_example("do_while.c"))

        body = lines.index("do_body_0:")
        increment = lines.index("    ADD R1 R1 R2")
        compare = lines.index("    CMP R1 R2")
        branch_to_body = lines.index("    BLT do_body_0")
        branch_to_end = lines.index("    B do_end_1")
        end = lines.index("do_end_1:")

        self.assertLess(body, increment)
        self.assertLess(increment, compare)
        self.assertLess(compare, branch_to_body)
        self.assertLess(branch_to_body, branch_to_end)
        self.assertLess(branch_to_end, end)

    def test_nested_while_loops_have_distinct_control_flow_labels(self):
        assembly = compile_example("nested_while.c")
        lines = instructions_without_comments(assembly)
        loop_labels = re.findall(r"^(while_(?:start|body|end)_\d+):$", assembly, re.M)

        self.assertEqual(len(loop_labels), 6)
        self.assertEqual(len(loop_labels), len(set(loop_labels)))
        self.assertEqual(sum(line.startswith("    BLT ") for line in lines), 2)
        self.assertIn("    B while_start_0", lines)
        self.assertIn("    B while_start_3", lines)


if __name__ == "__main__":
    unittest.main()
