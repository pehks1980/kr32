;==============================================================================
; Minimal KR32 userland libc scaffold
; Intended to be included by user binaries before assembly.
; fruity loops of our userland programs-)
;==============================================================================

;==============================================================================
; System Call Numbers
;==============================================================================
.EQU SYS_YIELD,  0
.EQU SYS_EXIT,   1
.EQU SYS_GETPID, 2
.EQU SYS_DEBUG,  3
.EQU SYS_WRITE,  4
.EQU SYS_READ,   5
.EQU SYS_OPEN,   6
.EQU SYS_CLOSE,  7
.EQU SYS_PIPE,   8
.EQU SYS_DUP,    9
.EQU SYS_GETTIME, 10
.EQU SYS_BRK,    11
.EQU SYS_SBRK,   12
.EQU SYS_EXECVE, 13
.EQU SYS_FORK,   14
.EQU SYS_SLEEP,  15

.EQU STDOUT_FD, 1

;==============================================================================
; _start - Program entry point
; IN:  argc at [SP], argv at [SP+4]
; OUT: Never returns - calls SYS_EXIT with main's return value
;==============================================================================
_start:
    LDW R1 [SP]          ; argc
    ADD R2 SP 4          ; argv
    LI R3 0              ; envp = NULL
    BL main
    SVC SYS_EXIT

;==============================================================================
; puts - Write null-terminated string to stdout with newline
; IN:  R1 = string pointer
; OUT: R1 = bytes written or error code
;==============================================================================
puts:
    PUSH LR
    PUSH R8
    PUSH R9
    MOV R8 R1            ; Save string pointer
    BL strlen            ; Get string length
    MOV R9 R1            ; Save length
    LI R1 STDOUT_FD
    MOV R2 R8            ; Buffer = string
    MOV R3 R9            ; Count = length
    SVC SYS_WRITE
    POP R9
    POP R8
    POP LR
    RET

;==============================================================================
; putchar - Write single character to stdout
; IN:  R1 = character
; OUT: R1 = bytes written (1) or error code
;==============================================================================
putchar:
    PUSH LR
    PUSH R8
    LI R8 ch_buf
    STB R1 [R8]          ; Store char in static buffer
    LI R1 STDOUT_FD
    MOV R2 R8
    LI R3 1
    SVC SYS_WRITE
    POP R8
    POP LR
    RET

;==============================================================================
; strlen - Calculate string length
; IN:  R1 = string pointer
; OUT: R1 = length (excluding null terminator)
;==============================================================================
strlen:
    PUSH LR
    PUSH R8
    PUSH R9
    MOV R8 R1
    LI R9 0
strlen_loop:
    LDB R2 [R8 + R9]     ; Read character at current offset
    CMP R2 0
    BEQ strlen_done
    ADD R9 R9 1          ; Increment counter
    B strlen_loop
strlen_done:
    MOV R1 R9
    POP R9
    POP R8
    POP LR
    RET

;==============================================================================
; strcmp - Compare two strings
; IN:  R1 = string1, R2 = string2
; OUT: R1 = 1 if equal, 0 if different
;==============================================================================
strcmp:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    MOV R8 R1
    MOV R9 R2
strcmp_loop:
    LDB R10 [R8]         ; Load char from string1
    LDB R1 [R9]          ; Load char from string2
    CMP R10 R1
    BNE strcmp_ne        ; Mismatch found
    CMP R10 0
    BEQ strcmp_eq        ; Both strings ended at same time
    ADD R8 R8 1          ; Advance both pointers
    ADD R9 R9 1
    B strcmp_loop
strcmp_eq:
    LI R1 1
    B strcmp_done
strcmp_ne:
    LI R1 0
strcmp_done:
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;==============================================================================
; memcpy - Copy memory block
; IN:  R1 = dest, R2 = src, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memcpy:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    MOV R8 R1
    MOV R9 R2
    MOV R10 R3
memcpy_loop:
    CMP R10 0
    BEQ memcpy_done
    LDB R1 [R9]          ; Read byte from source
    STB R1 [R8]          ; Write byte to destination
    ADD R8 R8 1          ; Advance both pointers
    ADD R9 R9 1
    SUB R10 R10 1        ; Decrement counter
    B memcpy_loop
memcpy_done:
    MOV R1 R8
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;==============================================================================
; memset - Fill memory with constant byte
; IN:  R1 = dest, R2 = value, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memset:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    MOV R8 R1
    MOV R9 R2
    MOV R10 R3
memset_loop:
    CMP R10 0
    BEQ memset_done
    STB R9 [R8]          ; Store value at current position
    ADD R8 R8 1          ; Advance pointer
    SUB R10 R10 1        ; Decrement counter
    B memset_loop
memset_done:
    MOV R1 R8
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;------------------------------------------------------------------------------
; write(fd, buf, len)
;
; IN:
;   R1 = fd
;   R2 = buffer
;   R3 = length
;
; OUT:
;   R1 = bytes written / errno
;------------------------------------------------------------------------------
write:
    SVC SYS_WRITE
    RET


;------------------------------------------------------------------------------
; read(fd, buf, len)
;
; IN:
;   R1 = fd
;   R2 = buffer
;   R3 = length
;
; OUT:
;   R1 = bytes read
;------------------------------------------------------------------------------
read:
    SVC SYS_READ
    RET


;------------------------------------------------------------------------------
; open(path, flags)
;
; IN:
;   R1 = path
;   R2 = flags
;
; OUT:
;   R1 = fd
;------------------------------------------------------------------------------
open:
    SVC SYS_OPEN
    RET


;------------------------------------------------------------------------------
; close(fd)
;------------------------------------------------------------------------------
close:
    SVC SYS_CLOSE
    RET


;------------------------------------------------------------------------------
; fork()
;
; parent:
;   R1 = child pid
;
; child:
;   R1 = 0
;------------------------------------------------------------------------------
fork:
    SVC SYS_FORK
    RET

;------------------------------------------------------------------------------
; fork()
;
; parent:
;   R1 = child pid
;
; child:
;   R1 = 0
;------------------------------------------------------------------------------
fork:
    SVC SYS_FORK
    RET


;------------------------------------------------------------------------------
; execve(path, argv, envp)
;------------------------------------------------------------------------------
execve:
    SVC SYS_EXECVE
    RET


;------------------------------------------------------------------------------
; waitpid(pid,status)
;------------------------------------------------------------------------------
waitpid:
    SVC SYS_WAITPID
    RET


;------------------------------------------------------------------------------
; sleep(milliseconds)
;------------------------------------------------------------------------------
sleep:
    SVC SYS_SLEEP
    RET


;------------------------------------------------------------------------------
; exit(status)
;
; never returns
;------------------------------------------------------------------------------
exit:
    SVC SYS_EXIT

exit_hang:
    B exit_hang


;==============================================================================
; MEMORY MANAGEMENT
;==============================================================================

;------------------------------------------------------------------------------
; VERY SIMPLE MEMORY ALLOCATOR
;
; This is a minimal malloc/free implementation that:
; 1. Uses a fixed array to track memory blocks
; 2. Does NOT coalesce (merge adjacent free blocks)
; 3. Does NOT split blocks (uses entire block as-is)
; 4. Uses first-fit search (finds first block that's big enough)
; 5. Uses sbrk syscall to get more memory from kernel
;
; Trade-offs:
; + Very simple and easy to understand
; + Predictable memory usage (fixed table)
; + No complex linked list management
; - Memory fragmentation (can't merge free blocks)
; - Wasted space (can't split large blocks)
; - Limited to MAX_BLOCKS allocations
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; CONSTANTS
;------------------------------------------------------------------------------

.EQU MAX_BLOCKS, 32       ; Maximum number of blocks we can track
                          ; (can't allocate more than 32 times without freeing)

; Block descriptor offsets (each block needs these 3 values)
.EQU BLOCK_ADDR,  0       ; Offset: starting address of the block (4 bytes)
.EQU BLOCK_SIZE,  4       ; Offset: size of the block in bytes (4 bytes)  
.EQU BLOCK_USED,  8       ; Offset: 0=free, 1=used (4 bytes)
.EQU BLOCK_DESC,  12      ; Total size of one block descriptor (3 words = 12 bytes)

;------------------------------------------------------------------------------
; DATA SECTION - The block table
;------------------------------------------------------------------------------

block_table:
    ; This is an array of MAX_BLOCKS descriptors.
    ; Each descriptor has: address, size, used_flag
    ; Total size: MAX_BLOCKS * 12 bytes
    .SPACE MAX_BLOCKS * BLOCK_DESC

;------------------------------------------------------------------------------
; malloc(size)
;
; Allocates memory from the heap.
;
; How it works:
; 1. Align the requested size to 8 bytes (makes memory management easier)
; 2. Search the block table for a free block that's large enough
; 3. If found, mark it as used and return its address
; 4. If not found, ask the kernel for more memory via sbrk syscall
; 5. Add the new memory to the block table and return it
;
; Input:  R1 = size in bytes (e.g., 100)
; Output: R1 = pointer to allocated memory (or 0 if failed)
;------------------------------------------------------------------------------
malloc:
    ; Save registers we'll use (so we don't corrupt caller's values)
    PUSH LR               ; Save return address
    
    ; Step 1: Align size to multiple of 8 bytes
    ; Why? Many CPUs work faster with aligned memory
    ; Example: size=100
    ;   ADD R1 7    -> 107
    ;   AND 0xFFFFFFF8 -> 104 (multiple of 8)
    ADD R1 R1 7           ; Add 7 to round up
    AND R1 R1 0xFFFFFFF8  ; Clear lower 3 bits (make multiple of 8)
    MOV R5 R1             ; R5 = aligned size (e.g., 104)
    
    ; Step 2: Search for a free block in the table
    ; We'll use R4 as index into block_table (0 to MAX_BLOCKS-1)
    LI R4 0               ; Start at first block (index 0)
    
malloc_loop:
    ; Check if we've searched all blocks
    CMP R4 MAX_BLOCKS     ; Compare index with maximum
    BGE malloc_sbrk       ; If index >= MAX_BLOCKS, no free block found
    
    ; Calculate address of this block's descriptor
    ; block_table + (index * descriptor_size)
    LI R2 block_table     ; R2 = base address of block_table
    LI R3 BLOCK_DESC      ; R3 = size of one descriptor (12 bytes)
    MUL R3 R4 R3          ; R3 = index * 12 (offset into table)
    ADD R2 R2 R3          ; R2 = address of block_table[index]
    
    ; Check if this block is free (USED flag = 0)
    LDW R3 [R2 + BLOCK_USED]  ; Load the USED flag
    CMP R3 0              ; Is it 0 (free)?
    BNE malloc_next       ; If not free (used), skip to next block
    
    ; Check if this block is large enough for our request
    LDW R3 [R2 + BLOCK_SIZE]  ; Load the block size
    CMP R3 R5             ; Is block size >= requested size?
    BGE malloc_found      ; Yes! We found a suitable block
    
malloc_next:
    ; This block is either used or too small, try next one
    ADD R4 R4 1           ; Increment index to check next block
    B malloc_loop         ; Go back to start of loop

malloc_found:
    ; Step 3: We found a free block large enough!
    ; R2 = pointer to the block descriptor
    ; R3 = block size (we don't use it for splitting in this simple version)
    
    ; Mark the block as used (USED flag = 1)
    LI R3 1               ; R3 = 1 (used)
    STW R3 [R2 + BLOCK_USED]  ; Store 1 in the USED field
    
    ; Get the block's starting address and return it
    LDW R1 [R2 + BLOCK_ADDR]  ; R1 = address of this block
    B malloc_done         ; Jump to cleanup and return

malloc_sbrk:
    ; Step 4: No free block found in table
    ; Ask the kernel for more memory using sbrk syscall
    
    ; R5 already has the aligned size we need
    MOV R1 R5             ; R1 = size to allocate
    LI R2 12              ; R2 = SYS_SBRK syscall number
    SVC R2                ; Call kernel: sbrk(size)
    
    ; Check if sbrk failed (returns -1 or 0 on error)
    CMP R1 0              ; Did sbrk return 0 or negative?
    BLT malloc_error      ; If error, return NULL
    
    ; Step 5: sbrk succeeded, we have new memory at address in R1
    ; Now we need to add this new block to our table
    
    ; Find an empty slot in the block table
    LI R4 0               ; Start at first block
    
malloc_add:
    ; Check if we've searched all blocks
    CMP R4 MAX_BLOCKS     
    BGE malloc_error      ; No empty slot! (shouldn't happen)
    
    ; Get descriptor address
    LI R2 block_table
    LI R3 BLOCK_DESC
    MUL R3 R4 R3
    ADD R2 R2 R3
    
    ; Check if this slot is free (USED flag = 0)
    LDW R3 [R2 + BLOCK_USED]
    CMP R3 0
    BEQ malloc_add_found  ; Found an empty slot!
    
    ; Slot is used, try next one
    ADD R4 R4 1
    B malloc_add

malloc_add_found:
    ; We found an empty slot at R2
    ; Store the new block's information
    
    ; Store the address (R1 from sbrk)
    STW R1 [R2 + BLOCK_ADDR]   ; block.address = address from sbrk
    
    ; Store the size (R5 = aligned size)
    STW R5 [R2 + BLOCK_SIZE]   ; block.size = size
    
    ; Mark as used (USED = 1)
    LI R3 1
    STW R3 [R2 + BLOCK_USED]   ; block.used = 1
    
    ; R1 already has the address from sbrk, so just return it
    B malloc_done

malloc_error:
    ; Something went wrong - return NULL (0)
    LI R1 0

malloc_done:
    POP LR                ; Restore return address
    RET                   ; Return to caller with R1 = pointer or NULL

;------------------------------------------------------------------------------
; free(ptr)
;
; Frees previously allocated memory.
;
; How it works:
; 1. Find the block descriptor for this address
; 2. Mark it as free (USED = 0)
; 3. Memory is now available for future malloc calls
;
; Note: This simple version does NOT coalesce adjacent free blocks!
;       So fragmentation can occur over time.
;
; Input:  R1 = pointer to memory to free (from malloc)
; Output: Nothing
;------------------------------------------------------------------------------
free:
    ; Save registers
    PUSH LR
    
    ; Step 1: Check if pointer is NULL
    CMP R1 0              ; Is R1 == 0?
    BEQ free_done         ; If NULL, nothing to free, just return
    
    ; Step 2: Search the block table for this address
    LI R4 0               ; Start at first block
    
free_loop:
    ; Check if we've searched all blocks
    CMP R4 MAX_BLOCKS
    BGE free_done         ; Not found - ignore (could be invalid pointer)
    
    ; Get descriptor address
    LI R2 block_table
    LI R3 BLOCK_DESC
    MUL R3 R4 R3
    ADD R2 R2 R3
    
    ; Check if this block's address matches the pointer
    LDW R3 [R2 + BLOCK_ADDR]  ; R3 = block address
    CMP R3 R1             ; Is this our block?
    BEQ free_found        ; Yes, we found it!
    
    ; Not this block, try next
    ADD R4 R4 1
    B free_loop

free_found:
    ; Step 3: We found the block descriptor at R2
    ; Mark it as free so malloc can use it again
    
    LI R3 0               ; R3 = 0 (free)
    STW R3 [R2 + BLOCK_USED]  ; block.used = 0
    
    ; NOTE: We do NOT clear the address or size
    ; They stay in the table and will be overwritten when reused
    
free_done:
    ; Clean up and return
    POP LR
    RET

;------------------------------------------------------------------------------
; malloc_init - Initialize the memory allocator
;
; Clears the entire block table so all blocks are marked as free
; Should be called once at system startup before using malloc
;------------------------------------------------------------------------------
malloc_init:
    ; Save registers
    PUSH LR   
    ; Step 1: Clear the entire block table
    ; Set all bytes in block_table to 0
    LI R1 block_table     ; R1 = start address of table
    LI R3 MAX_BLOCKS * BLOCK_DESC  ; R3 = total bytes to clear
    
malloc_init_loop:
    CMP R3 0              ; Have we cleared all bytes?
    BEQ malloc_init_done  ; Yes, we're done
    
    LI R2 0               ; R2 = 0 (value to write)
    STB R2 [R1]           ; Store 0 at current address
    ADD R1 R1 1           ; Move to next byte
    SUB R3 R3 1           ; Decrement byte counter
    B malloc_init_loop    ; Continue
    
malloc_init_done:
    ; Clean up and return
    POP LR
    RET


;==============================================================================
; INTERNAL HELPERS
;==============================================================================

;---------------------------------------------------------
; itoa_core - Universal integer to string converter
;
; R1 = destination buffer
; R2 = integer to convert
; R3 = base (2, 10, or 16)
; R4 = sign flag (1 = signed, 0 = unsigned)
; R5 = temp buffer size needed
;
; Returns:
;   R1 = original destination pointer
;---------------------------------------------------------
itoa_core:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    MOV  R8  R1          ; Save destination
    
    MOV  R9  R2          ; Working value
    MOV  R11 R3          ; Base
    MOV  R12 R4          ; Sign flag
    ;MOV  R10 R5          ; Temp buffer size
    
    ; Allocate temp buffer (size passed in R5)
    SUB  SP SP R5
    MOV  R10 R1          ; Keep original pointer
    MOV  R6  SP          ; Temp buffer pointer
    push R5              ; save R5 for frame leave
    MOV  R7  R6          ; Save start of temp buffer
    
    ; Check for sign (if signed and negative)
    CMP  R12 1
    BNE  itoa_core_unsigned
    
    CMP  R9 0
    BGE  itoa_core_unsigned
    
    ; Negative number - add minus sign
    LI   R2 45     ;'-'
    STB  R2 [R8]
    ADD  R8 R8 1
    NOT  R9 R9
    ADD  R9 R9 1
    ;NEG  R9              ; Make positive
    
itoa_core_unsigned:
    ; Special case: zero
    CMP  R9 0
    BNE  itoa_core_convert
    
    LI   R2 48    ; '0'
    STB  R2 [R8]
    ADD  R8 R8 1
    LI   R2 0
    STB  R2 [R8]
    B    itoa_core_finish
    
itoa_core_convert:
    LI   R4 0            ; Digit counter
    
itoa_core_divloop:
    MOV  R5 R9
    DIV  R6 R5 R11       ; R6 = quotient, R9 = remainder
    MOD  R7 R9 R11       ; R7 = remainder
    
    ; Convert digit to ASCII based on base
    CMP  R11 16
    BEQ  itoa_core_hex_digit
    
    ; Base 2 or 10: digit 0-9
    ADD  R7 R7 48        ; '0' + digit
    B    itoa_core_store
    
itoa_core_hex_digit:
    ; Base 16: digit 0-15
    CMP  R7 9
    BGT  itoa_core_hex_letter
    ADD  R7 R7 48        ; '0' + digit
    B    itoa_core_store
    
itoa_core_hex_letter:
    SUB  R7 R7 10
    ADD  R7 R7 65        ; 'A' + (digit-10)
    
itoa_core_store:
    STB  R7 [R6]         ; Store in temp buffer
    ADD  R6 R6 1
    ADD  R4 R4 1         ; Increment digit count
    
    MOV  R9 R5           ; Quotient becomes new value
    CMP  R9 0
    BNE  itoa_core_divloop
    
    ; Point to last digit
    SUB  R6 R6 1
    
itoa_core_copy:
    CMP  R4 0
    BEQ  itoa_core_done
    
    LDB  R2 [R6]         ; Get digit from temp (reverse order)
    STB  R2 [R8]         ; Store in destination
    ADD  R8 R8 1
    SUB  R6 R6 1
    SUB  R4 R4 1
    B    itoa_core_copy
    
itoa_core_done:
    LI   R2 0
    STB  R2 [R8]         ; Null terminate
    
itoa_core_finish:
    POP  R5
    ; Clean up temp buffer
    ADD  SP SP R5
    
    ; Return original pointer
    MOV  R1 R10
    
    POP  R12
    POP  R11
    POP  R10
    POP  R9
    POP  R8
    POP  LR
    RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
    PUSH LR
    
    ; Max 11 digits + sign + null = 13 bytes
    LI   R3 10           ; Base 10
    LI   R4 1            ; Signed
    LI   R5 13           ; Temp buffer size
    CALL itoa_core
    
    POP  LR
    RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
    PUSH LR
    
    ; Max 8 digits + null = 9 bytes
    LI   R3 16           ; Base 16
    LI   R4 0            ; Unsigned (shows raw bits)
    LI   R5 9            ; Temp buffer size
    CALL itoa_core
    
    POP  LR
    RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
    PUSH LR
    
    ; Max 32 bits + null = 33 bytes
    LI   R3 2            ; Base 2
    LI   R4 0            ; Unsigned (shows raw bits)
    LI   R5 33           ; Temp buffer size
    CALL itoa_core
    
    POP  LR
    RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
    PUSH LR
    
    ; Max 8 digits + sign + null = 10 bytes
    LI   R3 16           ; Base 16
    LI   R4 1            ; Signed (shows sign)
    LI   R5 10           ; Temp buffer size
    CALL itoa_core
    
    POP  LR
    RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
    PUSH LR
    
    ; Max 32 bits + sign + null = 34 bytes
    LI   R3 2            ; Base 2
    LI   R4 1            ; Signed (shows sign)
    LI   R5 34           ; Temp buffer size
    CALL itoa_core
    
    POP  LR
    RET

;------------------------------------------------------------------------------
; strcpy(dest, src)
;
; Copies string from src to dest including terminating null character
;
; Input:
;   R1 = destination pointer
;   R2 = source pointer
;
; Output:
;   R1 = destination pointer (original)
;------------------------------------------------------------------------------
strcpy:
    PUSH LR
    MOV R3 R1              ; Save original destination pointer
    MOV R4 R2              ; Save source pointer
    
strcpy_loop:
    LDB R2 [R4]            ; Load byte from source
    STB R2 [R1]            ; Store byte to destination
    
    CMP R2 0               ; Check if it's null terminator
    BEQ strcpy_done        ; If zero, we're done
    
    ADD R1 R1 1            ; Advance destination pointer
    ADD R4 R4 1            ; Advance source pointer
    B strcpy_loop
    
strcpy_done:
    MOV R1 R3              ; Return original destination pointer
    POP LR
    RET


;------------------------------------------------------------------------------
; printf() - note (echo, cat, sh, ps dont need it yet can be made with putchar)
;
; Tiny implementation only.
;
; Supported:
;
;   %%      percent
;   %s
;   %d
;   %x
;   %c
;
; No width.
; No precision.
; No floating point.
;
; Later split into:
;
; printf()
; vprintf()
; vsnprintf()
;------------------------------------------------------------------------------
printf:

    ; TODO
    ;
    ; scan format string
    ; copy normal chars
    ; decode %
    ; dispatch formatter
    ;
    ; %s
    ; %d
    ; %x
    ; %c

    RET



;==============================================================================
; Data Section
;==============================================================================
space_str:
    .ASCIIZ " "

newline_str:
    .ASCIIZ "\n"

ch_buf:
    .ASCIIZ "\0"