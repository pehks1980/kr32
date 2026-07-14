Initial state (after malloc_init):
block_table:
[0] {addr=0, size=0, used=0}  <- free
[1] {addr=0, size=0, used=0}  <- free
[2] {addr=0, size=0, used=0}  <- free
...

Call malloc(100):
1. Align 100 -> 104
2. Search: block[0] is free but size=0 (too small)
3. No free block found -> call sbrk(104)
4. sbrk returns address 0x1000
5. Store in block[0]: {addr=0x1000, size=104, used=1}
6. Return 0x1000

block_table after malloc(100):
[0] {addr=0x1000, size=104, used=1}  <- allocated
[1] {addr=0, size=0, used=0}         <- free
[2] {addr=0, size=0, used=0}         <- free

Call malloc(200):
1. Align 200 -> 208
2. Search: block[0] is used, block[1] is free but size=0
3. No free block -> call sbrk(208)
4. sbrk returns 0x1068 (0x1000 + 104)
5. Store in block[1]: {addr=0x1068, size=208, used=1}
6. Return 0x1068

block_table:
[0] {addr=0x1000, size=104, used=1}  <- allocated
[1] {addr=0x1068, size=208, used=1}  <- allocated
[2] {addr=0, size=0, used=0}         <- free

Call free(0x1000):
1. Find block with addr=0x1000 -> block[0]
2. Mark as free: {addr=0x1000, size=104, used=0}

block_table:
[0] {addr=0x1000, size=104, used=0}  <- free (but still has address/size!)
[1] {addr=0x1068, size=208, used=1}  <- allocated
[2] {addr=0, size=0, used=0}         <- free

Call malloc(50):
1. Align 50 -> 56
2. Search: block[0] is free, size=104 >= 56 -> FOUND!
3. Mark as used: {addr=0x1000, size=104, used=1}
4. Return 0x1000 (reuses the freed memory!)

block_table:
[0] {addr=0x1000, size=104, used=1}  <- reallocated!
[1] {addr=0x1068, size=208, used=1}  <- allocated
[2] {addr=0, size=0, used=0}         <- free

Memory Layout:
┌────────────────────────────────────────────────┐
│ block_table (fixed array in memory)            │
│ ┌──────────────────────────────────────────┐   │
│ │ Block 0: addr, size, used               │   │
│ ├──────────────────────────────────────────┤   │
│ │ Block 1: addr, size, used               │   │
│ ├──────────────────────────────────────────┤   │
│ │ Block 2: addr, size, used               │   │
│ └──────────────────────────────────────────┘   │
├────────────────────────────────────────────────┤
│ Heap (managed by sbrk)                         │
│ ┌──────────────────────────────────────────┐   │
│ │ Block 0: [User Data]  ← malloc returns  │   │
│ ├──────────────────────────────────────────┤   │
│ │ Block 1: [User Data]  ← malloc returns  │   │
│ ├──────────────────────────────────────────┤   │
│ │ Block 2: [Free Space]                   │   │
│ └──────────────────────────────────────────┘   │
└────────────────────────────────────────────────┘

; Example program using malloc
_start:
    ; Initialize the allocator (must do this first!)
    CALL malloc_init
    
    ; Allocate 100 bytes for a string
    LI R1 100
    CALL malloc
    MOV R8 R1              ; Save pointer in R8
    
    ; Check if allocation succeeded
    CMP R8 0
    BEQ error_handler
    
    ; Use the memory
    LI R2 'H'
    STB R2 [R8]            ; Store 'H' at address
    LI R2 'i'
    STB R2 [R8 + 1]        ; Store 'i'
    LI R2 0
    STB R2 [R8 + 2]        ; Null terminate
    
    ; Print the string
    MOV R1 R8
    CALL kputs
    
    ; Free the memory
    MOV R1 R8
    CALL free
    
    ; Allocate more memory (this may reuse the freed block)
    LI R1 50
    CALL malloc
    MOV R9 R1
    
    ; ... use it ...
    
    ; Free again
    MOV R1 R9
    CALL free
    
    HLT

error_handler:
    LI R1 error_msg
    CALL kputs
    HLT

error_msg: .ASCIIZ "Out of memory!\r\n"