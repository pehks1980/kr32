from dataclasses import dataclass

from tlb import TLB


PAGE_READ = 1 << 0
PAGE_WRITE = 1 << 1
PAGE_EXEC = 1 << 2
PAGE_USER = 1 << 3
PAGE_PRESENT = 1 << 4

ACCESS_FLAG = {
    "r": PAGE_READ,
    "w": PAGE_WRITE,
    "x": PAGE_EXEC,
}

MODE_KERNEL = "kernel"
MODE_USER = "user"


class PageFault(Exception):
    def __init__(self, vaddr, access, reason):
        super().__init__(f"PAGE FAULT {access} vaddr=0x{vaddr:08X}: {reason}")
        self.vaddr = vaddr
        self.access = access
        self.reason = reason


@dataclass(frozen=True)
class PageTableEntry:
    ppn: int
    flags: int


class MMU:
    def __init__(self, page_size=4096, virtual_size=1024 * 1024 * 1024, tlb_size=64, physical_memory=None):
        if page_size <= 0 or page_size & (page_size - 1):
            raise ValueError("page_size must be a power of two")
        if virtual_size <= 0:
            raise ValueError("virtual_size must be positive")

        self.page_size = page_size
        self.virtual_size = virtual_size
        self.page_offset_mask = page_size - 1
        self.page_table = {}  # keep for now, but will remove
        self.tlb = TLB(capacity=tlb_size)
        self.enabled = False
        self.ptbr_pa = 0  # page table base physical address
        self.physical_memory = physical_memory

    def vpn(self, vaddr):
        return vaddr // self.page_size

    def offset(self, vaddr):
        return vaddr & self.page_offset_mask

    def map_page(self, vaddr, paddr, flags):
        if vaddr % self.page_size or paddr % self.page_size:
            raise ValueError("map_page addresses must be page-aligned")
        if vaddr < 0 or vaddr >= self.virtual_size:
            raise PageFault(vaddr, "map", "virtual address out of range")

        final_flags = flags | PAGE_PRESENT
        self.page_table[self.vpn(vaddr)] = PageTableEntry(self.vpn(paddr), final_flags)
        self.tlb.flush_vpn(self.vpn(vaddr))

    def map_range(self, vaddr, paddr, size, flags):
        if size < 0:
            raise ValueError("map_range size must be non-negative")
        pages = (size + self.page_size - 1) // self.page_size
        for i in range(pages):
            page_delta = i * self.page_size
            self.map_page(vaddr + page_delta, paddr + page_delta, flags)

    def identity_map(self, start, size, flags):
        self.map_range(start, start, size, flags)

    def unmap_page(self, vaddr):
        vpn = self.vpn(vaddr)
        self.page_table.pop(vpn, None)
        self.tlb.flush_vpn(vpn)

    def flush_tlb(self):
        self.tlb.flush()

    def check_access(self, vaddr, access, mode, flags):
        needed = ACCESS_FLAG[access]
        if not flags & PAGE_PRESENT:
            raise PageFault(vaddr, access, "page not present")
        if not flags & needed:
            raise PageFault(vaddr, access, f"missing {'rwx'[('rwx').index(access)]} permission")
        if mode == MODE_USER and not flags & PAGE_USER:
            raise PageFault(vaddr, access, "user access to kernel page")

    def translate(self, vaddr, access, mode=MODE_KERNEL):
        if access not in ACCESS_FLAG:
            raise ValueError(f"unknown access type: {access}")
        if vaddr < 0 or vaddr >= self.virtual_size:
            raise PageFault(vaddr, access, "virtual address out of range")

        if not self.enabled:
            return vaddr, False

        vpn = self.vpn(vaddr)
        page_offset = self.offset(vaddr)
        cached = self.tlb.lookup(vpn)

        if cached is None:
            # walk 1-level page table in physical memory
            pte_pa = self.ptbr_pa + vpn * 4
            if pte_pa + 4 > len(self.physical_memory):
                raise PageFault(vaddr, access, "page table out of bounds")
            pte_bytes = self.physical_memory[pte_pa:pte_pa+4]
            pte = int.from_bytes(pte_bytes, "little")
            flags = pte & 0xFFF
            ppn = pte >> 12
            if not flags & PAGE_PRESENT:
                raise PageFault(vaddr, access, "unmapped page")
            self.tlb.insert(vpn, ppn, flags)
            tlb = False
        else:
            ppn, flags = cached
            tlb = True

        self.check_access(vaddr, access, mode, flags)
        return ppn * self.page_size + page_offset, tlb
