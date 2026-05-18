"""Debug dump helpers used by the KR32 DEBUG instruction."""

from mmu import PAGE_EXEC, PAGE_GLOBAL, PAGE_PRESENT, PAGE_READ, PAGE_USER, PAGE_WRITE


def format_page_flags(flags):
    """Return compact PTE/TLB flags in KR32 order."""
    out = []
    for bit, name in (
        (PAGE_PRESENT, "P"),
        (PAGE_READ, "R"),
        (PAGE_WRITE, "W"),
        (PAGE_EXEC, "X"),
        (PAGE_USER, "U"),
        (PAGE_GLOBAL, "G"),
    ):
        if flags & bit:
            out.append(name)
    return "".join(out) or "-"

def dump_registers(vm):
    """Dump all 32 registers."""
    print("=== REGISTERS ===")
    for i in range(0, 32, 4):
        regs = []
        for j in range(4):
            if i + j < 32:
                val = vm.r(i + j)
                regs.append(f"R{i+j:2d}:{val:08x}")
        print("  " + "  ".join(regs))
    print()

def dump_flags(vm):
    """Dump CPU flags and control state."""
    print("=== FLAGS & CONTROL ===")
    print(f"  Z:{int(vm.Z)} N:{int(vm.N)} C:{int(vm.C)} V:{int(vm.V)}")
    print(f"  MMU enabled: {vm.mmu.enabled}")
    print(f"  Interrupts enabled: {vm.interrupt_enabled}")
    print(f"  Mode: {str(vm.mode).upper()}")
    print(f"  PC: 0x{vm.pc:08x}")
    print(f"  SP: 0x{vm.get_sp():08x}")
    print(f"  PTBR: 0x{vm.mmu.ptbr_pa:08x}")
    print(f"  STVEC: 0x{vm.stvec:08x}")
    print(f"  SEPC: 0x{vm.sepc:08x}")
    print(f"  SCAUSE: 0x{vm.scause:08x}")
    print(f"  STVAL: 0x{vm.stval:08x}")
    print(f"  SSCRATCH: 0x{vm.sscratch:08x}")
    print(f"  SSTATUS: 0x{vm.sstatus:08x}")
    print()

def dump_stack(vm, size=64):
    """Dump stack memory around current SP."""
    sp = vm.get_sp()
    print(f"=== STACK (SP=0x{sp:08x}) ===")
    start = max(0, sp - size * 4)
    end = min(len(vm.physical_memory), sp + size * 4)
    for addr in range(start, end, 16):
        data = []
        for i in range(0, 16, 4):
            if addr + i + 3 < end:
                try:
                    val = vm.physical_memory[addr + i:addr + i + 4]
                    val = int.from_bytes(val, "little")
                    data.append(f"{val:08x}")
                except:
                    data.append("--------")
            else:
                data.append("--------")
        marker = "<-SP" if addr <= sp < addr + 16 else ""
        print(f"  0x{addr:08x}: {' '.join(data)} {marker}")
    print()

def dump_page_table(vm):
    """Dump only mapped PTEs from the current one-level page table."""
    ptbr = vm.mmu.ptbr_pa
    if ptbr == 0:
        print("=== PAGE TABLE ===")
        print("  PTBR not set")
        print()
        return

    print(f"=== PAGE TABLE (PTBR=0x{ptbr:08x}) ===")
    mapped = 0
    entries = vm.mmu.virtual_size // vm.mmu.page_size
    for vpn in range(entries):
        addr = ptbr + vpn * 4
        if addr + 4 > len(vm.physical_memory):
            break
        pte = int.from_bytes(vm.physical_memory[addr:addr + 4], "little")
        flags = pte & 0xFFF
        if not flags & PAGE_PRESENT:
            continue
        ppn = pte >> 12
        va = vpn * vm.mmu.page_size
        pa = ppn * vm.mmu.page_size
        print(f"  VA 0x{va:08x} -> PA 0x{pa:08x}  PTE=0x{pte:08x} [{format_page_flags(flags)}]")
        mapped += 1
    if not mapped:
        print("  no present entries")
    print()

def dump_idt(vm):
    """Dump the Interrupt Descriptor Table."""
    idtr = vm.idt_base_pa
    if idtr == 0:
        print("=== IDT ===")
        print("  IDTR not set")
        print()
        return

    print(f"=== IDT (IDTR=0x{idtr:08x}) ===")
    vectors = [
        "DIV_ZERO", "INVALID_INSTR", "PAGE_FAULT", "SYSCALL",
        "MISALIGNED", "ILLEGAL_MEM", "DEBUG"
    ]
    for i in range(7):
        addr = idtr + i * 4
        if addr + 3 < len(vm.physical_memory):
            try:
                val = vm.physical_memory[addr:addr + 4]
                val = int.from_bytes(val, "little")
                name = vectors[i] if i < len(vectors) else f"VEC_{i}"
                print(f"  {i}: {name} -> 0x{val:08x}")
            except:
                print(f"  {i}: --------")
        else:
            print(f"  {i}: out of bounds")
    print()

def dump_tlb(vm):
    """Dump the TLB contents."""
    print("=== TLB ===")
    if not vm.mmu.tlb.entries:
        print("  TLB empty")
    else:
        for vpn, (ppn, flags) in sorted(vm.mmu.tlb.entries.items()):
            va = vpn * vm.mmu.page_size
            pa = ppn * vm.mmu.page_size
            print(f"  VA 0x{va:08x} -> PA 0x{pa:08x}  VPN=0x{vpn:05x} PPN=0x{ppn:05x} [{format_page_flags(flags)}]")
    print()

def dump_trap_state(vm):
    """Dump current trap/interrupt state."""
    print("=== TRAP STATE ===")
    print(f"  In trap handler: {vm.in_trap_handler}")
    print(f"  Trap EPC: 0x{vm.trap_epc:08x}")
    print(f"  Trap return PC: 0x{vm.trap_return_pc:08x}")
    print(f"  Trap cause: {vm.trap_cause}")
    print(f"  Trap value: 0x{vm.trap_value:08x}")
    print()


def dump_memory(vm, addr, size):
    """Dump the configured virtual memory range at DEBUG time."""
    print(f"=== MEMORY DUMP (VA=0x{addr:08x}, size={size}) ===")
    try:
        vm.hexdump(addr, size)
    except Exception as exc:
        print(f"  unavailable: {exc}")
    print()

def dump_short(vm):
    """Dump short version: registers and flags."""
    print("\n" + "="*30)
    print("KR32 DEBUG (SHORT)")
    print("="*30)
    dump_registers(vm)
    dump_flags(vm)
    print("="*30 + "\n")

def dump_all(vm):
    """Dump complete VM state."""
    print("\n" + "="*50)
    print("KR32 VM DEBUG DUMP (FULL)")
    print("="*50)
    dump_registers(vm)
    dump_flags(vm)
    dump_trap_state(vm)
    dump_stack(vm)
    dump_page_table(vm)
    dump_idt(vm)
    dump_tlb(vm)
    print("="*50 + "\n")


def dump_debug2(vm, dump_range=None):
    """Dump execution state plus compact MMU views for address-space tests."""
    print("\n" + "="*50)
    print("KR32 VM DEBUG DUMP (MMU)")
    print("="*50)
    dump_registers(vm)
    dump_flags(vm)
    dump_trap_state(vm)
    dump_page_table(vm)
    dump_tlb(vm)
    if dump_range is not None:
        dump_memory(vm, dump_range[0], dump_range[1])
    print("="*50 + "\n")
