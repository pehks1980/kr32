import time

class PIT:
    """Memory Mapped I/O (MMIO) Programmable Interval Timer (PIT) for KR32.
    
    Exposes timer control mapped to memory:
      - Offset 0 (PIT_PERIOD): Tick period in milliseconds (R/W).
      - Offset 4 (PIT_CTRL): Control flags (Bit 0 = Interrupt Enable, Bit 1 = Timer Enable) (R/W).
      - Offset 8 (PIT_COUNT): Elapsed tick count since boot or reset (R).
    """
    def __init__(self, period_ms=1):
        self.period_ms = period_ms
        self.last_tick = time.time()
        # Control flags: Bit 0 = Interrupt Enable (1), Bit 1 = Timer Enable (2)
        # By default, PIT is enabled and interrupt-enabled to preserve compatibility
        self.pit_enable = True
        self.int_enable = True
        self.tick_count = 0
        
    def tick(self):
        """Perform a tick check.
        
        Returns True if a period has elapsed, the timer is enabled, and interrupts are enabled.
        """
        if not self.pit_enable:
            return False

        now = time.time()
        if (now - self.last_tick) * 1000 >= self.period_ms:
            self.last_tick = now
            self.tick_count += 1
            # Return True to indicate a tick occurred (interruption depends on int_enable)
            return self.int_enable
        return False
        
    def reset(self):
        """Reset the timer state."""
        self.last_tick = time.time()
        self.tick_count = 0
        self.pit_enable = True
        self.int_enable = True
        
    def set_frequency(self, freq):
        """Set timer period (for compatibility)."""
        self.period_ms = freq
        self.last_tick = time.time()

    def read_reg(self, offset):
        """Read a register from the PIT device based on byte offset."""
        if offset == 0:
            # PIT_PERIOD
            return self.period_ms & 0xFFFFFFFF
        elif offset == 4:
            # PIT_CTRL
            ctrl = 0
            if self.int_enable:
                ctrl |= 1
            if self.pit_enable:
                ctrl |= 2
            return ctrl
        elif offset == 8:
            # PIT_COUNT
            return self.tick_count & 0xFFFFFFFF
        return 0

    def write_reg(self, offset, val):
        """Write a register to the PIT device based on byte offset."""
        if offset == 0:
            # PIT_PERIOD: Update tick period
            self.period_ms = max(1, val)  # avoid division by zero or negative periods
            self.last_tick = time.time()
        elif offset == 4:
            # PIT_CTRL: Update control bits
            self.int_enable = bool(val & 1)
            self.pit_enable = bool(val & 2)
            if self.pit_enable:
                self.last_tick = time.time()