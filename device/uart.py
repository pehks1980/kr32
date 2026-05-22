import sys
import select

class UARTDevice:
    """Memory Mapped I/O (MMIO) UART Device for KR32.
    
    Exposes a standard serial interface mapped to memory:
      - Offset 0 (UART_DATA): Read to pop RX byte, Write to transmit TX byte.
      - Offset 4 (UART_STATUS): Status bits (Bit 0 = RX Ready, Bit 1 = TX Ready).
      - Offset 8 (UART_CTRL): Control bits (Bit 0 = RX Interrupt Enable).
    """

    def __init__(self):
        # FIFO buffer for received characters
        self.rx_fifo = []
        # Control register: Bit 0 = RX Interrupt Enable
        self.rx_int_enable = 0

    def reset(self):
        """Reset the UART device state."""
        self.rx_fifo = []
        self.rx_int_enable = 0

    def read_reg(self, offset):
        """Read a register from the UART device based on byte offset."""
        if offset == 0:
            # UART_DATA: Read next byte from RX FIFO queue
            if self.rx_fifo:
                val = self.rx_fifo.pop(0)
                # Keep it within 8-bit unsigned boundary
                return val & 0xFF
            return 0
        elif offset == 4:
            # UART_STATUS:
            # Bit 0 (1): RX Ready (FIFO has data)
            # Bit 1 (2): TX Ready (always ready to transmit)
            status = 0
            if self.rx_fifo:
                status |= 1  # RX ready
            status |= 2      # TX is always ready in emulator
            return status
        elif offset == 8:
            # UART_CTRL: Return the current interrupt control mask
            return self.rx_int_enable & 0xFF
        return 0

    def write_reg(self, offset, val):
        """Write a register to the UART device based on byte offset."""
        if offset == 0:
            # UART_DATA: Transmit a byte
            char_val = val & 0xFF
            # Print to stdout/terminal screen
            try:
                sys.stdout.write(chr(char_val))
                sys.stdout.flush()
            except Exception:
                pass
            # For loopback / easy verification, we also append it to our FIFO if it was a loopback write.
            # However, typically write is write-only. If the guest wants loopback, it handles it.
        elif offset == 8:
            # UART_CTRL: Update interrupt mask (Bit 0 enables RX interrupts)
            self.rx_int_enable = val & 0xFF

    def update(self):
        """Non-blockingly poll standard input (sys.stdin) for incoming data.
        
        Returns True if a new character was added to the RX FIFO, triggering an IRQ condition.
        """
        try:
            # Verify stdin is a TTY and has data available to avoid blocking
            if sys.stdin.isatty():
                # select with timeout=0 is completely non-blocking
                r, _, _ = select.select([sys.stdin], [], [], 0)
                if r:
                    char = sys.stdin.read(1)
                    if char:
                        self.rx_fifo.append(ord(char))
                        return True
        except Exception:
            pass
        return False
