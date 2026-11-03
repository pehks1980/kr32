import contextlib
import io
import unittest

from tools.assembler import Assembler
from vmp import CPU


class MemoryFormatTests(unittest.TestCase):
    def assemble(self, *lines):
        assembler = Assembler()
        with contextlib.redirect_stdout(io.StringIO()):
            assembler.build(lines, write_output=False)
        return assembler

    def test_immediate_offsets_use_m_format_for_all_memory_ops(self):
        instructions = (
            ("LDB R1 [FP + 32767]", 0x61, 0x1E, 0x7FFF),
            ("LDH R2 [R3 - 32767]", 0x62, 0x23, 0x8001),
            ("LDW R4 [R5 + 0]", 0x63, 0x45, 0x0000),
            ("STB R6 [R7 + 1]", 0x64, 0x67, 0x0001),
            ("STH R8 [R9 - 1]", 0x65, 0x89, 0xFFFF),
            ("STW R10 [R11 + 16]", 0x66, 0xAB, 0x0010),
            ("LDBS R12 [SP - 8]", 0x67, 0xCD, 0xFFF8),
            ("LDHS R15 [LR + -16]", 0x68, 0xFF, 0xFFF0),
        )

        for source, expected_op, expected_regs, expected_offset in instructions:
            with self.subTest(source=source):
                word = int.from_bytes(self.assemble(source).memory[:4], "little")
                self.assertEqual((word >> 24) & 0xFF, expected_op)
                self.assertEqual((word >> 16) & 0xFF, expected_regs)
                self.assertEqual(word & 0xFFFF, expected_offset)

    def test_m_format_registers_are_limited_to_r0_through_r15(self):
        for source in ("LDB R16 [R1 + 4]", "STW R1 [R16 + 4]"):
            with self.subTest(source=source), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    self.assemble(source)

    def test_register_offsets_keep_the_original_r_format(self):
        word = int.from_bytes(
            self.assemble("LDB R16 [R20 + R31]").memory[:4], "little"
        )

        self.assertEqual((word >> 24) & 0xFF, 0x20)
        self.assertEqual((word >> 16) & 0xFF, 16)
        self.assertEqual((word >> 8) & 0xFF, 20)
        self.assertEqual(word & 0xFF, 0x9F)

    def test_vm_executes_signed_m_format_loads_and_stores(self):
        load_cases = (
            ("LDB R1 [FP - 1]", 0x1FFF, 0x80, 0x80, 1),
            ("LDH R2 [FP - 2]", 0x1FFE, 0x8001, 0x8001, 2),
            ("LDW R3 [FP - 4]", 0x1FFC, 0x12345678, 0x12345678, 3),
            ("LDBS R4 [FP - 1]", 0x1FFF, 0x80, 0xFFFFFF80, 4),
            ("LDHS R5 [FP - 2]", 0x1FFE, 0x8001, 0xFFFF8001, 5),
        )

        for source, addr, payload, expected, reg in load_cases:
            with self.subTest(source=source):
                assembler = self.assemble(source)
                cpu = CPU()
                cpu.trace_output = False
                cpu.physical_memory[:assembler.pc] = assembler.memory[:assembler.pc]
                cpu.setr(cpu.FP_REG, 0x2000)
                if "LDH" in source or "LDHS" in source:
                    cpu.mem_write_u16(addr, payload & 0xFFFF)
                elif "LDW" in source:
                    cpu.mem_write_u32(addr, payload)
                else:
                    cpu.mem_write_u8(addr, payload & 0xFF)

                cpu._execute_instruction()
                self.assertEqual(cpu.r(reg), expected)

        store_cases = (
            ("STB R6 [FP + 1]", 0x2001, 0xAB, 6, "u8"),
            ("STH R7 [FP + 2]", 0x2002, 0x1234, 7, "u16"),
            ("STW R8 [FP + 4]", 0x2004, 0x89ABCDEF, 8, "u32"),
        )

        for source, addr, value, reg, width in store_cases:
            with self.subTest(source=source):
                assembler = self.assemble(source)
                cpu = CPU()
                cpu.trace_output = False
                cpu.physical_memory[:assembler.pc] = assembler.memory[:assembler.pc]
                cpu.setr(cpu.FP_REG, 0x2000)
                cpu.setr(reg, value)

                cpu._execute_instruction()
                if width == "u8":
                    self.assertEqual(cpu.mem_read_u8(addr), value & 0xFF)
                elif width == "u16":
                    self.assertEqual(cpu.mem_read_u16(addr), value & 0xFFFF)
                else:
                    self.assertEqual(cpu.mem_read_u32(addr), value)

        self.assertEqual(cpu.disasm(0x61, 0x1E, 0xFF, 0xFC), "LDB R1, [FP - 4]")


if __name__ == "__main__":
    unittest.main()
