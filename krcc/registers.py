
# registers.py

class RegisterAllocationError(Exception):
    """Raised when no temporary register is available."""
    pass


class RegisterAllocator:
    """
    Simple KR32 temporary register allocator.

    R5-R12 are callee-saved general-purpose registers.

    The allocator manages their temporary use during
    expression code generation.
    """

    GENERAL_REGISTERS = (
        "R5",
        "R6",
        "R7",
        "R8",
        "R9",
        "R10",
        "R11",
        "R12",
    )

    def __init__(self):
        self.reset()

    def reset(self):
        """
        Reset allocation state for a new function.

        Registers are allocated in deterministic order:
        R5, R6, R7 ... R12.
        """

        self.available = list(self.GENERAL_REGISTERS)
        self.allocated = set()

        # Track every register allocated during this function,
        # even if it has subsequently been released.
        self.used = set()

    def allocate(self):
        """
        Allocate one temporary register.

        Returns:
            Register name, e.g. "R5".
        """

        if not self.available:
            raise RegisterAllocationError(
                "No free temporary registers available"
            )

        register = self.available.pop(0)

        self.allocated.add(register)
        self.used.add(register)

        return register

    def release(self, register):
        """
        Release a previously allocated register.

        A released register becomes available for reuse.
        Available registers are kept in deterministic order.
        """

        if register not in self.allocated:
            raise RegisterAllocationError(
                f"Register {register} is not currently allocated"
            )

        self.allocated.remove(register)
        self.available.append(register)

        # Restore the original register allocation order.
        self.available.sort(
            key=self.GENERAL_REGISTERS.index
        )


    def get_used_registers(self):
        """
        Return registers used during the current function.
        """

        return [
            register
            for register in self.GENERAL_REGISTERS
            if register in self.used
        ]

    def get_allocated_registers(self):
        """
        Return registers that are still live.
        """

        return set(self.allocated)
