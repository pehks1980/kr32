
from registers import RegisterAllocator, RegisterAllocationError

allocator = RegisterAllocator()

# Allocate three registers.
r1 = allocator.allocate()
r2 = allocator.allocate()
r3 = allocator.allocate()

print("Allocated:", r1, r2, r3)

assert r1 == "R5"
assert r2 == "R6"
assert r3 == "R7"

# Release the middle register.
allocator.release(r2)

# It should become available again.
r4 = allocator.allocate()

assert r4 == "R6"

print("Reallocated:", r4)

# Release everything.
allocator.release(r1)
allocator.release(r3)
allocator.release(r4)

print("Used registers:", allocator.get_used_registers())
print("Currently allocated:", allocator.get_allocated_registers())

assert allocator.get_allocated_registers() == set()
assert allocator.get_used_registers() == ["R5", "R6", "R7"]

print("Register allocator tests passed!")
