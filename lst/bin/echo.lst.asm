.org 0x00043000
; from USER_CODE_VA
;==============================================================================
; echo - Print all command line arguments
;==============================================================================
; Simple echo implementation that prints each argument separated by spaces,
; followed by a newline. Uses the shared libc scaffold.
;==============================================================================

;library is here so it dtsrtd _start which calls main
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
.EQU SYS_WAITPID, 16

.EQU STDOUT_FD, 1

;==============================================================================
; Dirent structure (matches kernel definition)
;==============================================================================
.EQU DT_REG,        1
.EQU DT_DIR,        2

.EQU DIRENT_INODE,  0
.EQU DIRENT_SIZE,   4
.EQU DIRENT_TYPE,   8
.EQU DIRENT_NAME,   12
.EQU DIRENT_SIZEOF, 76

.EQU O_RDONLY,      0


;==============================================================================
; _start - Program entry point
; IN:  argc at [SP], argv at [SP+4]
; OUT: Never returns - calls SYS_EXIT with main's return value
;==============================================================================
_start:
0x00043000       LDW R1 [SP]          ; argc
0x00043004       ADD R2 SP 4          ; argv
0x00043008       LI R3 0              ; envp = NULL
0x00043010       PUSH R1
0x00043014       PUSH R2
0x00043018       PUSH R3
    ; Initialize the allocator (must do this first!)
0x0004301C   CALL malloc_init
0x00043024       POP  R3
0x00043028       POP  R2
0x0004302C       POP  R1
    ;Debug 2
0x00043030       BL main              ; call main loop - ls cat echo etc
    ;Debug 2
0x00043038       LI R1 0
0x00043040       PUSH R1              ; exit 0 - success 1 - error
0x00043044       LI R1 1              ; put to sleep so parent waitpid can work
0x0004304C       SVC SYS_SLEEP
    ;Debug 2
0x00043050       POP  R1
   ; LI R1 1
0x00043054       SVC SYS_EXIT

;==============================================================================
; puts - Write null-terminated string to stdout with newline
; IN:  R1 = string pointer
; OUT: R1 = bytes written or error code
;==============================================================================
puts:
0x00043058       PUSH LR
0x0004305C       PUSH R8
0x00043060       PUSH R9
0x00043064       MOV R8 R1            ; Save string pointer
0x00043068       BL strlen            ; Get string length
0x00043070       MOV R9 R1            ; Save length
0x00043074       LI R1 STDOUT_FD
0x0004307C       MOV R2 R8            ; Buffer = string
0x00043080       MOV R3 R9            ; Count = length
0x00043084       SVC SYS_WRITE
0x00043088       LI  R1 10             ; Newline character
0x00043090       BL  putchar           ; Write newline
0x00043098       POP R9
0x0004309C       POP R8
0x000430A0       POP LR
0x000430A4       RET

;==============================================================================
; putchar - Write single character to stdout
; IN:  R1 = character
; OUT: R1 = bytes written (1) or error code
;==============================================================================
putchar:
0x000430A8       PUSH LR
0x000430AC       PUSH R8
0x000430B0       LI R8 ch_buf
0x000430B8       STB R1 [R8]          ; Store char in static buffer
0x000430BC       LI R1 STDOUT_FD
0x000430C4       MOV R2 R8
0x000430C8       LI R3 1
0x000430D0       SVC SYS_WRITE
0x000430D4       POP R8
0x000430D8       POP LR
0x000430DC       RET

;==============================================================================
; strlen - Calculate string length
; IN:  R1 = string pointer
; OUT: R1 = length (excluding null terminator)
;==============================================================================
strlen:
0x000430E0       PUSH LR
0x000430E4       PUSH R8
0x000430E8       PUSH R9
0x000430EC       MOV R8 R1
0x000430F0       LI R9 0
strlen_loop:
0x000430F8       LDB R2 [R8 + R9]     ; Read character at current offset
0x000430FC       CMP R2 0
0x00043100       BEQ strlen_done
0x00043108       ADD R9 R9 1          ; Increment counter
0x0004310C       B strlen_loop
strlen_done:
0x00043114       MOV R1 R9
0x00043118       POP R9
0x0004311C       POP R8
0x00043120       POP LR
0x00043124       RET

;==============================================================================
; strcmp - Compare two strings
; IN:  R1 = string1, R2 = string2
; OUT: R1 = 1 if equal, 0 if different
;==============================================================================
strcmp:
0x00043128       PUSH LR
0x0004312C       PUSH R8
0x00043130       PUSH R9
0x00043134       PUSH R10
0x00043138       MOV R8 R1
0x0004313C       MOV R9 R2
strcmp_loop:
0x00043140       LDB R10 [R8]         ; Load char from string1
0x00043144       LDB R1 [R9]          ; Load char from string2
0x00043148       CMP R10 R1
0x0004314C       BNE strcmp_ne        ; Mismatch found
0x00043154       CMP R10 0
0x00043158       BEQ strcmp_eq        ; Both strings ended at same time
0x00043160       ADD R8 R8 1          ; Advance both pointers
0x00043164       ADD R9 R9 1
0x00043168       B strcmp_loop
strcmp_eq:
0x00043170       LI R1 1
0x00043178       B strcmp_done
strcmp_ne:
0x00043180       LI R1 0
strcmp_done:
0x00043188       POP R10
0x0004318C       POP R9
0x00043190       POP R8
0x00043194       POP LR
0x00043198       RET

;==============================================================================
; memcpy - Copy memory block
; IN:  R1 = dest, R2 = src, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memcpy:
0x0004319C       PUSH LR
0x000431A0       PUSH R8
0x000431A4       PUSH R9
0x000431A8       PUSH R10
0x000431AC       MOV R8 R1
0x000431B0       MOV R9 R2
0x000431B4       MOV R10 R3
memcpy_loop:
0x000431B8       CMP R10 0
0x000431BC       BEQ memcpy_done
0x000431C4       LDB R1 [R9]          ; Read byte from source
0x000431C8       STB R1 [R8]          ; Write byte to destination
0x000431CC       ADD R8 R8 1          ; Advance both pointers
0x000431D0       ADD R9 R9 1
0x000431D4       SUB R10 R10 1        ; Decrement counter
0x000431D8       B memcpy_loop
memcpy_done:
0x000431E0       MOV R1 R8
0x000431E4       POP R10
0x000431E8       POP R9
0x000431EC       POP R8
0x000431F0       POP LR
0x000431F4       RET

;==============================================================================
; memset - Fill memory with constant byte
; IN:  R1 = dest, R2 = value, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memset:
0x000431F8       PUSH LR
0x000431FC       PUSH R8
0x00043200       PUSH R9
0x00043204       PUSH R10
0x00043208       MOV R8 R1
0x0004320C       MOV R9 R2
0x00043210       MOV R10 R3
memset_loop:
0x00043214       CMP R10 0
0x00043218       BEQ memset_done
0x00043220       STB R9 [R8]          ; Store value at current position
0x00043224       ADD R8 R8 1          ; Advance pointer
0x00043228       SUB R10 R10 1        ; Decrement counter
0x0004322C       B memset_loop
memset_done:
0x00043234       MOV R1 R8
0x00043238       POP R10
0x0004323C       POP R9
0x00043240       POP R8
0x00043244       POP LR
0x00043248       RET

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
0x0004324C       SVC SYS_WRITE
0x00043250       RET


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
0x00043254       SVC SYS_READ
0x00043258       RET


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
0x0004325C       SVC SYS_OPEN
0x00043260       RET


;------------------------------------------------------------------------------
; close(fd)
;------------------------------------------------------------------------------
close:
0x00043264       SVC SYS_CLOSE
0x00043268       RET


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
0x0004326C       SVC SYS_FORK
0x00043270       RET


;------------------------------------------------------------------------------
; execve(path, argv, envp)
;------------------------------------------------------------------------------
execve:
0x00043274       SVC SYS_EXECVE
0x00043278       RET


;------------------------------------------------------------------------------
; waitpid(pid,status)
;------------------------------------------------------------------------------
waitpid:
0x0004327C       SVC SYS_WAITPID
0x00043280       RET


;------------------------------------------------------------------------------
; sleep(milliseconds)
;------------------------------------------------------------------------------
sleep:
0x00043284       SVC SYS_SLEEP
0x00043288       RET


;------------------------------------------------------------------------------
; exit(status)
;
; never returns
;------------------------------------------------------------------------------
exit:
0x0004328C       SVC SYS_EXIT

exit_hang:
0x00043290       B exit_hang


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

.EQU MAX_BLOCKS, 48       ; Maximum number of blocks we can track
                          ; (can't allocate more than 32 times without freeing)

; Block descriptor offsets (each block needs these 3 values)
.EQU BLOCK_ADDR,  0       ; Offset: starting address of the block (4 bytes)
.EQU BLOCK_SIZE,  4       ; Offset: size of the block in bytes (4 bytes)
.EQU BLOCK_USED,  8       ; Offset: 0=free, 1=used (4 bytes)
.EQU BLOCK_DESC,  12      ; Total size of one block descriptor (3 words = 12 bytes)

;------------------------------------------------------------------------------
; DATA SECTION - The block table
; normally memory blocks get resereved from HEAP which is located at data segment
; page (page address specified as user_data_va)
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
0x000434D8       PUSH LR               ; Save return address

    ; Step 1: Align size to multiple of 8 bytes
    ; Why? Many CPUs work faster with aligned memory
    ; Example: size=100
    ;   ADD R1 7    -> 107
    ;   AND 0xFFFFFFF8 -> 104 (multiple of 8)
0x000434DC       ADD R1 R1 7           ; Add 7 to round up
0x000434E0       LI  R2 0xFFFFFFF8
0x000434E8       AND R1 R1 R2          ; Clear lower 3 bits (make multiple of 8)
0x000434EC       MOV R5 R1             ; R5 = aligned size (e.g., 104)

    ; Step 2: Search for a free block in the table
    ; We'll use R4 as index into block_table (0 to MAX_BLOCKS-1)
0x000434F0       LI R4 0               ; Start at first block (index 0)

malloc_loop:
    ; Check if we've searched all blocks
0x000434F8       CMP R4 MAX_BLOCKS     ; Compare index with maximum
0x000434FC       BGE malloc_sbrk       ; If index >= MAX_BLOCKS, no free block found

    ; Calculate address of this block's descriptor
    ; block_table + (index * descriptor_size)
0x00043504       LI R2 block_table     ; R2 = base address of block_table
0x0004350C       LI R3 BLOCK_DESC      ; R3 = size of one descriptor (12 bytes)
0x00043514       MUL R3 R4 R3          ; R3 = index * 12 (offset into table)
0x00043518       ADD R2 R2 R3          ; R2 = &block[index]

    ; Check if this block is free (USED flag = 0)
0x0004351C       LDW R3 [R2 + BLOCK_USED]  ; Load the &block[index].block_used flag
0x00043520       CMP R3 0              ; Is it 0 (free)?
0x00043524       BNE malloc_next       ; If not free (used), skip to next block

    ; free. Check if this block is large enough for our request
0x0004352C       LDW R3 [R2 + BLOCK_SIZE]  ; Load the block size
0x00043530       CMP R3 R5             ; Is block size >= requested size?
0x00043534       BGE malloc_found      ; Yes! We found a suitable block

malloc_next:
    ; This block is either used or too small, try next one
0x0004353C       ADD R4 R4 1           ; Increment index to check next block
0x00043540       B malloc_loop         ; Go back to start of loop

malloc_found:
    ; Step 3: We found a free block large enough!
    ; R2 = pointer to the block descriptor
    ; R3 = block size (we don't use it for splitting in this simple version)

    ; Mark the block as used (USED flag = 1)
0x00043548       LI R3 1               ; R3 = 1 (used)
0x00043550       STW R3 [R2 + BLOCK_USED]  ; Store 1 in the USED field

    ; Get the block's starting address and return it
0x00043554       LDW R1 [R2 + BLOCK_ADDR]  ; R1 = address of this block
0x00043558       B malloc_done         ; Jump to cleanup and return

malloc_sbrk:
    ; Step 4: No free block found in table
    ; Ask the kernel for more memory using sbrk syscall

    ; R5 already has the aligned size we need
0x00043560       MOV R1 R5             ; R1 = size to allocate
0x00043564       SVC SYS_SBRK          ; Call kernel: sbrk(size)

    ; Check if sbrk failed (returns -1 or 0 on error)
0x00043568       CMP R1 0              ; Did sbrk return 0 or negative?
0x0004356C       BLT malloc_error      ; If error, return NULL

    ; Step 5: sbrk succeeded, we have new memory at address in R1
    ; Now we need to add this new block to our table

    ; Find an empty slot in the block table
0x00043574       LI R4 0               ; Start at first block

malloc_add:
    ; Check if we've searched all blocks
0x0004357C       CMP R4 MAX_BLOCKS
0x00043580       BGE malloc_error      ; No empty slot! (shouldn't happen)

    ; Get descriptor address
0x00043588       LI R2 block_table
0x00043590       LI R3 BLOCK_DESC
0x00043598       MUL R3 R4 R3
0x0004359C       ADD R2 R2 R3        ; &block[indexR4]

    ; Check if this slot is free (USED flag = 0)
0x000435A0       LDW R3 [R2 + BLOCK_USED]
0x000435A4       CMP R3 0
0x000435A8       BEQ malloc_add_found  ; Found an empty slot!

    ; Slot is used, try next one
0x000435B0       ADD R4 R4 1
0x000435B4       B malloc_add

malloc_add_found:
    ; We found an empty slot at R2
    ; Store the new block's information

    ; Store the address (R1 from sbrk)
0x000435BC       STW R1 [R2 + BLOCK_ADDR]   ; block.address = address from sbrk

    ; Store the size (R5 = aligned size)
0x000435C0       STW R5 [R2 + BLOCK_SIZE]   ; block.size = size

    ; Mark as used (USED = 1)
0x000435C4       LI R3 1
0x000435CC       STW R3 [R2 + BLOCK_USED]   ; block.used = 1

    ; R1 already has the address from sbrk, so just return it
0x000435D0       B malloc_done

malloc_error:
    ; Something went wrong - return NULL (0)
0x000435D8       LI R1 0

malloc_done:
0x000435E0       POP LR                ; Restore return address
0x000435E4       RET                   ; Return to caller with R1 = pointer or NULL

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
0x000435E8       PUSH LR

    ; Step 1: Check if pointer is NULL
0x000435EC       CMP R1 0              ; Is R1 == 0?
0x000435F0       BEQ free_done         ; If NULL, nothing to free, just return

    ; Step 2: Search the block table for this address
0x000435F8       LI R4 0               ; Start at first block

free_loop:
    ; Check if we've searched all blocks
0x00043600       CMP R4 MAX_BLOCKS
0x00043604       BGE free_done         ; Not found - ignore (could be invalid pointer)

    ; Get descriptor address
0x0004360C       LI R2 block_table
0x00043614       LI R3 BLOCK_DESC      ; length of one block descriptor
0x0004361C       MUL R3 R4 R3          ; r4 block idx
0x00043620       ADD R2 R2 R3          ; R2 = &block[i]

    ; Check if this block's address matches the pointer
0x00043624       LDW R3 [R2 + BLOCK_ADDR]  ; R3 =  &block[i].block address
0x00043628       CMP R3 R1             ; Is this our block?
0x0004362C       BEQ free_found        ; Yes, we found it!

    ; Not this block, try next
0x00043634       ADD R4 R4 1
0x00043638       B free_loop

free_found:
    ; Step 3: We found the block descriptor at R2
    ; Mark it as free so malloc can use it again

0x00043640       LI R3 0               ; R3 = 0 (free)
0x00043648       STW R3 [R2 + BLOCK_USED]  ; &block[i].used = 0

    ; NOTE: We do NOT clear the address or size
    ; They stay in the table and will be overwritten when reused

free_done:
    ; Clean up and return
0x0004364C       POP LR
0x00043650       RET

;------------------------------------------------------------------------------
; malloc_init - Initialize the memory allocator
;
; Clears the entire block table so all blocks are marked as free
; Should be called once at system startup before using malloc
;------------------------------------------------------------------------------
malloc_init:
    ; Save registers
0x00043654       PUSH LR
    ; Step 1: Clear the entire block table
    ; Set all bytes in block_table to 0
0x00043658       LI R1 block_table     ; R1 = start address of table
0x00043660       LI R3 MAX_BLOCKS * BLOCK_DESC  ; R3 = total bytes to clear

malloc_init_loop:
0x00043668       CMP R3 0              ; Have we cleared all bytes?
0x0004366C       BEQ malloc_init_done  ; Yes, we're done

0x00043674       LI R2 0               ; R2 = 0 (value to write)
0x0004367C       STB R2 [R1]           ; Store 0 at current address
0x00043680       ADD R1 R1 1           ; Move to next byte
0x00043684       SUB R3 R3 1           ; Decrement byte counter
0x00043688       B malloc_init_loop    ; Continue

malloc_init_done:
    ; Clean up and return
0x00043690       POP LR
0x00043694       RET


;==============================================================================
; INTERNAL HELPERS
;==============================================================================
; ================================================================
; Convert integer into temporary buffer
;
; R9  = current value
; R10 = pointer to next free byte in temporary buffer
; R11 = base (2, 10, or 16)
; R4  = number of digits stored
;
; Each division produces:
;
;   quotient  = value / base
;   remainder = value % base
;
; The remainder is the next digit.
;
; Digits are generated backwards, for example:
;
;   123
;
; first produces:
;
;   3
;   2
;   1
;
; so the temporary buffer contains:
;
;   "321"
;
; The copy loop below will reverse it into "123".
;
;                 itoa_core
;                     |
;          ┌──────────┴──────────┐
;          │                     │
;      R9 = value           R10 = temp[]
;          │                     │
;          ↓                     ↓
;       DIV/MOD                STB
;          │                     │
;     ┌────┴────┐                │
;     ↓         ↓                │
; R6=quotient R7=remainder       │
;     │         │                │
;     │         └──→ ASCII ────--┘
;     │
;     └────→ R9 for next loop
;R8  destination pointer
;R9  current integer value
;R10 temporary-buffer pointer
;R11 base
;R12 sign flag
;R4  digit counter
;R6  quotient
;R7  remainder
;R5  scratch / divisor
; ================================================================

itoa_core:
0x00043698       PUSH LR
0x0004369C       PUSH R5
0x000436A0       PUSH R6
0x000436A4       PUSH R7
0x000436A8       PUSH R8
0x000436AC       PUSH R9
0x000436B0       PUSH R10
0x000436B4       PUSH R11
0x000436B8       PUSH R12

0x000436BC       MOV  R8  R1          ; Save destination
0x000436C0       MOV  R9  R2          ; Working value
0x000436C4       MOV  R11 R3          ; Base
0x000436C8       MOV  R12 R4          ; Sign flag
    ; Allocate temp buffer (size passed in R5)
0x000436CC       SUB  SP SP R5
0x000436D0       MOV  R10 SP          ; Temp buffer pointer

0x000436D4       PUSH R5              ; save R5 for frame leave
0x000436D8       PUSH R8              ; save result bufer

    ; Check for sign (if signed and negative)
0x000436DC       CMP  R12 1
0x000436E0       BNE  itoa_core_unsigned

0x000436E8       CMP  R9 0
0x000436EC       BGE  itoa_core_unsigned

    ; Negative number - add minus sign
0x000436F4       LI   R2 45     ;'-'
0x000436FC       STB  R2 [R8]
0x00043700       ADD  R8 R8 1
0x00043704       NOT  R9 R9
0x00043708       ADD  R9 R9 1
    ;NEG  R9              ; Make positive

itoa_core_unsigned:
    ; Special case: zero
0x0004370C       CMP  R9 0
0x00043710       BNE  itoa_core_convert

0x00043718       LI   R2 48    ; '0'
0x00043720       STB  R2 [R8]
0x00043724       ADD  R8 R8 1
0x00043728       LI   R2 0
0x00043730       STB  R2 [R8]
0x00043734       B    itoa_core_finish

itoa_core_convert:

0x0004373C       LI  R4 0                  ; R4 = digit counter

itoa_core_divloop:
    ; ------------------------------------------------------------
    ; Divide current value by base
    ;
    ; R9  = current value
    ; R11 = base
    ;
    ; We need to keep R9 unchanged for MOD, so use R5
    ; as the DIV source.
    ; ------------------------------------------------------------
0x00043744       MOV R5 R9
    ; R6 = quotient
0x00043748       DIV R6 R5 R11
    ; R7 = remainder
0x0004374C       MOD R7 R9 R11
    ; ------------------------------------------------------------
    ; Convert remainder to ASCII
    ;
    ; For base 2 and 10:
    ;     0..9 -> '0'..'9'
    ;
    ; For base 16:
    ;     0..9  -> '0'..'9'
    ;     10..15 -> 'A'..'F'
    ; ------------------------------------------------------------
0x00043750       CMP R11 16
0x00043754       BEQ itoa_core_hex_digit
    ; Base 2 or base 10
0x0004375C       ADD R7 R7 48             ; '0' + digit
0x00043760       B itoa_core_store

itoa_core_hex_digit:
0x00043768       CMP R7 9
0x0004376C       BGT itoa_core_hex_letter
    ; 0..9
0x00043774       ADD R7 R7 48             ; '0' + digit
0x00043778       B itoa_core_store

itoa_core_hex_letter:
    ; 10..15
0x00043780       SUB R7 R7 10
0x00043784       ADD R7 R7 65             ; 'A' + (digit - 10)

; ================================================================
; Store generated digit
; ================================================================

itoa_core_store:

0x00043788       STB R7 [R10]    ;R10 is the temporary-buffer pointer.

0x0004378C       ADD R10 R10 1
0x00043790       ADD R4 R4 1     ; One more digit generated

    ; ------------------------------------------------------------
    ; The quotient becomes the value for the next iteration.
    ;
    ; Example:
    ;
    ;   123 / 10 = 12
    ;    12 / 10 = 1
    ;     1 / 10 = 0
    ; ------------------------------------------------------------

0x00043794       MOV R9 R6

    ; Continue until quotient becomes zero
0x00043798       CMP R9 0
0x0004379C       BNE itoa_core_divloop

; ================================================================
; Digits are now stored backwards in temporary buffer.
; temp = "321"
;
; R10 points just AFTER the last digit.
;
; Move back to the final digit:
; ================================================================

0x000437A4       SUB R10 R10 1

; ================================================================
; Copy digits from temporary buffer backwards
; ================================================================

itoa_core_copy:
0x000437A8       CMP R4 0
0x000437AC       BEQ itoa_core_done
    ; Read last generated digit
0x000437B4       LDB R2 [R10]
    ; Write it to destination
0x000437B8       STB R2 [R8]
0x000437BC       ADD R8 R8 1
    ; Move backwards through temporary buffer
0x000437C0       SUB R10 R10 1
    ; One less digit
0x000437C4       SUB R4 R4 1
0x000437C8       B itoa_core_copy

itoa_core_done:
0x000437D0       LI   R2 0
0x000437D8       STB  R2 [R8]         ; Null terminate

itoa_core_finish:
0x000437DC       POP  R1              ; Return original pointer
0x000437E0       POP  R5
    ; Clean up temp buffer
0x000437E4       ADD  SP SP R5

0x000437E8       POP R12
0x000437EC       POP R11
0x000437F0       POP R10
0x000437F4       POP R9
0x000437F8       POP R8
0x000437FC       POP R7
0x00043800       POP R6
0x00043804       POP R5
0x00043808       POP LR
0x0004380C       RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
0x00043810       PUSH LR

    ; Max 11 digits + sign + null = 13 bytes
0x00043814       LI   R3 10           ; Base 10
0x0004381C       LI   R4 1            ; Signed
0x00043824       LI   R5 13           ; Temp buffer size
0x0004382C   CALL itoa_core

0x00043834       POP  LR
0x00043838       RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
0x0004383C       PUSH LR

    ; Max 8 digits + null = 9 bytes
0x00043840       LI   R3 16           ; Base 16
0x00043848       LI   R4 0            ; Unsigned (shows raw bits)
0x00043850       LI   R5 9            ; Temp buffer size
0x00043858   CALL itoa_core

0x00043860       POP  LR
0x00043864       RET


;---------------------------------------------------------
; itoa_oct - Octal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_oct:
0x00043868       PUSH LR

    ; Max 12 digits + null = 13 bytes
0x0004386C       LI   R3 8            ; Base 8
0x00043874       LI   R4 0            ; Unsigned (shows raw bits)
0x0004387C       LI   R5 13           ; Temp buffer size
0x00043884   CALL itoa_core

0x0004388C       POP  LR
0x00043890       RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
0x00043894       PUSH LR

    ; Max 32 bits + null = 33 bytes
0x00043898       LI   R3 2            ; Base 2
0x000438A0       LI   R4 0            ; Unsigned (shows raw bits)
0x000438A8       LI   R5 33           ; Temp buffer size
0x000438B0   CALL itoa_core

0x000438B8       POP  LR
0x000438BC       RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
0x000438C0       PUSH LR

    ; Max 8 digits + sign + null = 10 bytes
0x000438C4       LI   R3 16           ; Base 16
0x000438CC       LI   R4 1            ; Signed (shows sign)
0x000438D4       LI   R5 10           ; Temp buffer size
0x000438DC   CALL itoa_core

0x000438E4       POP  LR
0x000438E8       RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
0x000438EC       PUSH LR

    ; Max 32 bits + sign + null = 34 bytes
0x000438F0       LI   R3 2            ; Base 2
0x000438F8       LI   R4 1            ; Signed (shows sign)
0x00043900       LI   R5 34           ; Temp buffer size
0x00043908   CALL itoa_core

0x00043910       POP  LR
0x00043914       RET

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
0x00043918       PUSH LR
0x0004391C       MOV R3 R1              ; Save original destination pointer
0x00043920       MOV R4 R2              ; Save source pointer

strcpy_loop:
0x00043924       LDB R2 [R4]            ; Load byte from source
0x00043928       STB R2 [R1]            ; Store byte to destination

0x0004392C       CMP R2 0               ; Check if it's null terminator
0x00043930       BEQ strcpy_done        ; If zero, we're done

0x00043938       ADD R1 R1 1            ; Advance destination pointer
0x0004393C       ADD R4 R4 1            ; Advance source pointer
0x00043940       B strcpy_loop

strcpy_done:
0x00043948       MOV R1 R3              ; Return original destination pointer
0x0004394C       POP LR
0x00043950       RET


;==============================================================================
; DIRECTORY OPERATIONS - Matching your kernel's tarfs_readdir
;==============================================================================

;------------------------------------------------------------------------------
; Directory structure (opaque to user)
;------------------------------------------------------------------------------
.EQU DIR_FD,       0       ; File descriptor (4 bytes)
.EQU DIR_OFFSET,   4       ; Current position in directory stream (4 bytes)
.EQU DIR_SIZEOF,   8

;------------------------------------------------------------------------------
; opendir - Open a directory for reading
;
; IN:  R1 = path (null-terminated string)
; OUT: R1 = DIR* (handle) or 0 on error
;
; Opens a directory file and returns a handle for readdir
;------------------------------------------------------------------------------
opendir:
0x00043954       PUSH LR
0x00043958       PUSH R8
0x0004395C       PUSH R9

0x00043960       MOV R8 R1            ; Save path
    ; Open directory with read-only flags (same as your ls.asm)
0x00043964       MOV R1 R8
0x00043968       LI  R2 O_RDONLY
0x00043970       SVC SYS_OPEN
0x00043974       MOV R9 R1           ;fd
0x00043978       CMP R1 0
0x0004397C       BLT opendir_error

    ; Allocate DIR structure (small, just fd and offset)
0x00043984       PUSH R9                 ;save R9 jic
0x00043988       LI R1 DIR_SIZEOF
0x00043990   CALL malloc
0x00043998       POP  R9

0x0004399C       CMP R1 0
0x000439A0       BEQ opendir_error_close

0x000439A8       MOV R8 R1            ; Save DIR*

    ; Initialize DIR structure
    ; R2 still has fd from open
0x000439AC       STW R9 [R8 + DIR_FD]
0x000439B0       LI  R2 0
0x000439B8       STW R2 [R8 + DIR_OFFSET]

0x000439BC       MOV R1 R8            ; Return DIR*
0x000439C0       B opendir_done

opendir_error_close:
0x000439C8       MOV R1 R9            ; fd is in R9
0x000439CC       SVC SYS_CLOSE
0x000439D0       LI R1 0
0x000439D8       B opendir_done

opendir_error:
0x000439E0       LI R1 0

opendir_done:
0x000439E8       POP R9
0x000439EC       POP R8
0x000439F0       POP LR
0x000439F4       RET

;------------------------------------------------------------------------------
; readdir - Read next directory entry
;
; IN:  R1 = DIR* (from opendir)
;      R2 = pointer to struct dirent to fill
; OUT: R1 = 1 if entry read, 0 if no more entries, -1 on error
;
; Reads the next directory entry using the kernel's readdir via SYS_READ
;------------------------------------------------------------------------------
readdir:
0x000439F8       PUSH LR
0x000439FC       PUSH R8
0x00043A00       PUSH R9

0x00043A04       MOV R8 R1            ; DIR*
0x00043A08       MOV R9 R2            ; User's dirent buffer

    ; Check if DIR pointer is valid
0x00043A0C       CMP R8 0
0x00043A10       BEQ readdir_error

    ; Read one dirent from directory fd using current offset
0x00043A18       LDW R1 [R8 + DIR_FD] ; fd

    ; Use the directory's offset - we need to implement lseek or use
    ; the fact that each read gets one dirent at a time from tarfs
0x00043A1C       MOV R2 R9            ; user buffer
0x00043A20       LI  R3 DIRENT_SIZEOF ; size of one dirent
0x00043A28       SVC SYS_READ
0x00043A2C       CMP R1 0
0x00043A30       BEQ readdir_end      ; EOF
0x00043A38       CMP R1 DIRENT_SIZEOF
0x00043A3C       BNE readdir_error    ; Short read or error

    ; Entry read successfully
    ; Update the offset in DIR structure
0x00043A44       LDW R2 [R8 + DIR_OFFSET]
0x00043A48       ADD R2 R2 1
0x00043A4C       STW R2 [R8 + DIR_OFFSET]

0x00043A50       LI R1 1              ; Return success
0x00043A58       B readdir_done

readdir_error:
0x00043A60       LI R1 -1
0x00043A68       B readdir_done

readdir_end:
0x00043A70       LI R1 0

readdir_done:
0x00043A78       POP R9
0x00043A7C       POP R8
0x00043A80       POP LR
0x00043A84       RET

;------------------------------------------------------------------------------
; closedir - Close directory stream
;
; IN:  R1 = DIR*
; OUT: R1 = 0 on success, -1 on error
;------------------------------------------------------------------------------
closedir:
0x00043A88       PUSH LR
0x00043A8C       PUSH R8

0x00043A90       MOV R8 R1
0x00043A94       CMP R8 0
0x00043A98       BEQ closedir_error

    ; Close the directory fd
0x00043AA0       LDW R1 [R8 + DIR_FD]
0x00043AA4       SVC SYS_CLOSE

    ; Free the DIR structure
0x00043AA8       MOV R1 R8
0x00043AAC   CALL free

0x00043AB4       LI R1 0
0x00043ABC       B closedir_done

closedir_error:
0x00043AC4       LI R1 -1

closedir_done:
0x00043ACC       POP R8
0x00043AD0       POP LR
0x00043AD4       RET

;------------------------------------------------------------------------------
; rewinddir - Reset directory stream to beginning
;
; IN:  R1 = DIR*
;------------------------------------------------------------------------------
rewinddir:
0x00043AD8       CMP R1 0
0x00043ADC       BEQ rewinddir_done

0x00043AE4       LI R2 0
0x00043AEC       STW R2 [R1 + DIR_OFFSET]

    ; Need to seek to beginning of directory
    ; For tarfs, this means closing and reopening, or using lseek
    ; Simple approach: close and reopen
0x00043AF0       PUSH LR
0x00043AF4       PUSH R8

0x00043AF8       MOV R8 R1
    ; Save the path - we don't have it stored, so this is tricky
    ; In a real implementation, store path in DIR structure

    ; For now, just reset offset and rely on readdir's behavior

0x00043AFC       POP R8
0x00043B00       POP LR

rewinddir_done:
0x00043B04       RET

;------------------------------------------------------------------------------
; dirfd - Get file descriptor from DIR*
;
; IN:  R1 = DIR*
; OUT: R1 = file descriptor, or -1 on error
;------------------------------------------------------------------------------
dirfd:
0x00043B08       CMP R1 0
0x00043B0C       BEQ dirfd_error

0x00043B14       LDW R1 [R1 + DIR_FD]
0x00043B18       RET

dirfd_error:
0x00043B1C       LI R1 -1
0x00043B24       RET

;------------------------------------------------------------------------------
; Helper: is_dir - Check if a path is a directory
;
; IN:  R1 = path
; OUT: R1 = 1 if directory, 0 if not, -1 on error
;------------------------------------------------------------------------------
is_dir:
0x00043B28       PUSH LR

    ; Try to open as directory
0x00043B2C   CALL opendir
0x00043B34       CMP R1 0
0x00043B38       BEQ is_dir_not_dir

    ; It opened as a directory
0x00043B40       MOV R2 R1            ; Save DIR*
0x00043B44       LI R1 1              ; Return true
0x00043B4C   CALL closedir
0x00043B54       B is_dir_done

is_dir_not_dir:
0x00043B5C       LI R1 0

is_dir_done:
0x00043B64       POP LR
0x00043B68       RET

;------------------------------------------------------------------------------
; Example usage function - list directory contents (like ls)
; This demonstrates how to use opendir/readdir/closedir
;------------------------------------------------------------------------------
list_directory:
0x00043B6C       PUSH LR
0x00043B70       PUSH R8
0x00043B74       PUSH R9

0x00043B78       MOV R8 R1            ; path

    ; Allocate dirent on stack
0x00043B7C       SUB SP SP DIRENT_SIZEOF
0x00043B80       MOV R9 SP

    ; Open directory
0x00043B84       MOV R1 R8
0x00043B88   CALL opendir
0x00043B90       CMP R1 0
0x00043B94       BEQ list_dir_error

0x00043B9C       MOV R8 R1            ; DIR*

list_dir_loop:
0x00043BA0       MOV R1 R8
0x00043BA4       MOV R2 R9
0x00043BA8   CALL readdir
0x00043BB0       CMP R1 0
0x00043BB4       BEQ list_dir_close
0x00043BBC       LI  R2 -1
0x00043BC4       CMP R1 R2
0x00043BC8       BEQ list_dir_error

    ; Print the name
0x00043BD0       ADD R1 R9 DIRENT_NAME
0x00043BD4   CALL puts

    ; If it's a directory, print '/'
0x00043BDC       LDW R2 [R9 + DIRENT_TYPE]
0x00043BE0       CMP R2 DT_DIR
0x00043BE4       BNE list_dir_not_dir

0x00043BEC       LI R1 slash_char
0x00043BF4   CALL putchar

list_dir_not_dir:
0x00043BFC       LI R1 newline_char
0x00043C04   CALL putchar

0x00043C0C       B list_dir_loop

list_dir_close:
0x00043C14       MOV R1 R8
0x00043C18   CALL closedir
0x00043C20       LI R1 0
0x00043C28       B list_dir_done

list_dir_error:
0x00043C30       LI R1 -1

list_dir_done:
0x00043C38       ADD SP SP DIRENT_SIZEOF
0x00043C3C       POP R9
0x00043C40       POP R8
0x00043C44       POP LR
0x00043C48       RET

;------------------------------------------------------------------------------
; Data Section
;------------------------------------------------------------------------------
slash_char:
    .WORD 47      ;'/'
newline_char:
    .WORD 10

; Arguments are passed in R2..R12 (up to 11).
; Output is written immediately; no internal buffering.
;
; IN:  R1 = format string
; OUT: R1 = number of characters written (optional, can be ignored)
; usage:
;   printf("Hello %s, number=%d, hex=%x, char=%c\n", "world", 42, 255, 'A')
;   KR32:
;   LI R1 fmt_str
;   LI R2 42
;   LI R3 hello_str
;   BL printf
;...
;fmt_str: .ASCIIZ "Number: %d, String: %s\n"
;hello_str: .ASCIIZ "world"
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; printf - Formatted output to stdout
;
; Supported conversions:
;   %%      literal '%'
;   %s      string (char*)
;   %d / %i signed decimal
;   %x      unsigned hexadecimal (lowercase)
;   %c      single character
;   %b      unsigned binary
;   %o      unsigned octal
;
; Arguments: R2..R12 (first 11), then on stack (caller‑pushed).
;------------------------------------------------------------------------------
printf:
0x00043C54       PUSH LR
0x00043C58       PUSH R8
0x00043C5C       PUSH R9
0x00043C60       PUSH R10
0x00043C64       PUSH R11
0x00043C68       PUSH R12

0x00043C6C       SUB SP SP 80              ; local frame: 44 + 34 + padding

    ; Save R2..R12 to local array
0x00043C70       STW R2 [SP + 0]
0x00043C74       STW R3 [SP + 4]
0x00043C78       STW R4 [SP + 8]
0x00043C7C       STW R5 [SP + 12]
0x00043C80       STW R6 [SP + 16]
0x00043C84       STW R7 [SP + 20]
0x00043C88       STW R8 [SP + 24]
0x00043C8C       STW R9 [SP + 28]
0x00043C90       STW R10 [SP + 32]
0x00043C94       STW R11 [SP + 36]
0x00043C98       STW R12 [SP + 40]

0x00043C9C       MOV R8 R1                 ; format pointer
0x00043CA0       LI  R9 0                  ; argument index

0x00043CA8       MOV R10 SP                ; base of saved registers
0x00043CAC       ADD R11 SP 44             ; conversion buffer

printf_loop:
0x00043CB0       LDB R1 [R8]     ;read fmt string char
0x00043CB4       CMP R1 0
0x00043CB8       BEQ printf_done

0x00043CC0       CMP R1 37   ;check for '%'
0x00043CC4       BNE printf_normal_char

0x00043CCC       ADD R8 R8 1 ; its a '%', move to next char for specifier
0x00043CD0       LDB R2 [R8]
0x00043CD4       CMP R2 0
0x00043CD8       BEQ printf_done

0x00043CE0       CMP R2 37   ; check for '%%'
0x00043CE4       BEQ printf_percent
0x00043CEC       CMP R2 115  ; check for '%s'
0x00043CF0       BEQ printf_string
0x00043CF8       CMP R2 100  ;check for '%d'
0x00043CFC       BEQ printf_int
0x00043D04       CMP R2 105  ;check for '%i'
0x00043D08       BEQ printf_int
0x00043D10       CMP R2 120  ;check for '%x'
0x00043D14       BEQ printf_hex
0x00043D1C       CMP R2 99   ;check for '%c'
0x00043D20       BEQ printf_char
0x00043D28       CMP R2 98   ;check for '%b'
0x00043D2C       BEQ printf_bin
0x00043D34       CMP R2 111  ;check for '%o'
0x00043D38       BEQ printf_oct

    ; unknown specifier
0x00043D40       LI  R1 37   ;unknown specifier, print '%'
0x00043D48   CALL putchar
0x00043D50       MOV R1 R2   ; print the unknown specifier char
0x00043D54   CALL putchar
0x00043D5C       B   printf_continue

printf_normal_char:
0x00043D64   CALL putchar
0x00043D6C       B   printf_continue

printf_percent:
0x00043D74       LI  R1 37   ;print '%'
0x00043D7C   CALL putchar
0x00043D84       B   printf_continue

;------------------------------------------------------------------------------
; Argument fetch helpers (same as before)
;------------------------------------------------------------------------------
_fetch_arg_r1:
0x00043D8C       PUSH LR
0x00043D90       PUSH R3
0x00043D94   CALL _get_arg_address
0x00043D9C       LDW R1 [R3]
0x00043DA0       POP R3
0x00043DA4       POP LR
0x00043DA8       RET

_fetch_arg_r2:
0x00043DAC       PUSH LR
0x00043DB0       PUSH R3
0x00043DB4   CALL _get_arg_address
0x00043DBC       LDW R2 [R3]
0x00043DC0       POP R3
0x00043DC4       POP LR
0x00043DC8       RET

_get_arg_address:   ; fetch the address of the next argument based on R9 (arg index)
0x00043DCC       CMP R9 11       ; if arg index >= 11, it's on the stack
0x00043DD0       BLT _arg_in_regs
0x00043DD8       SUB R3 R9 11    ; R3 = number of extra args on stack
0x00043DDC       LI  R4 4
0x00043DE4       MUL R3 R3 R4
0x00043DE8       ADD R3 SP R3    ; R3 = address of first extra arg on stack (not sure if this is correct)
0x00043DEC       ADD R3 R3 104   ; offset to caller's first extra arg 104
                    ;is the size of the local frame (80) + saved registers (44)
0x00043DF0       RET

_arg_in_regs:       ; fetch argument from R2..R12 based on R9
0x00043DF4       LI  R4 4
0x00043DFC       MUL R3 R9 R4    ; R9 = arg index, (R3 = offset in bytes)
0x00043E00       ADD R3 R10 R3   ; R3 = address of saved register in local array, R10 = base of saved registers
0x00043E04       RET

;------------------------------------------------------------------------------
; Specifier handlers
;------------------------------------------------------------------------------
printf_string:
0x00043E08   CALL _fetch_arg_r1
0x00043E10       ADD R9 R9 1
0x00043E14   CALL _print_string
0x00043E1C       B   printf_continue

printf_int:
0x00043E24   CALL _fetch_arg_r2
0x00043E2C       ADD R9 R9 1
0x00043E30       MOV R1 R11          ; r11 is the conversion buffer (on stack)
0x00043E34   CALL _print_number
0x00043E3C       B   printf_continue

printf_hex:
0x00043E44   CALL _fetch_arg_r2
0x00043E4C       ADD R9 R9 1
0x00043E50       MOV R1 R11          ; r11 is the conversion buffer (on stack) and so on for other conversions helpers..
0x00043E54   CALL _print_hex
0x00043E5C       B   printf_continue

printf_char:
0x00043E64   CALL _fetch_arg_r1
0x00043E6C       ADD R9 R9 1
0x00043E70   CALL putchar
0x00043E78       B   printf_continue

printf_bin:
0x00043E80   CALL _fetch_arg_r2
0x00043E88       ADD R9 R9 1
0x00043E8C       MOV R1 R11
0x00043E90   CALL _print_bin
0x00043E98       B   printf_continue

printf_oct:
0x00043EA0   CALL _fetch_arg_r2
0x00043EA8       ADD R9 R9 1
0x00043EAC       MOV R1 R11
0x00043EB0   CALL _print_oct
0x00043EB8       B   printf_continue

printf_continue:    ;to continue processing format string
0x00043EC0       ADD R8 R8 1
0x00043EC4       B   printf_loop

printf_done:
0x00043ECC       ADD SP SP 80
0x00043ED0       POP R12
0x00043ED4       POP R11
0x00043ED8       POP R10
0x00043EDC       POP R9
0x00043EE0       POP R8
0x00043EE4       POP LR
0x00043EE8       RET

;------------------------------------------------------------------------------
; _print_string - Write a null‑terminated string to stdout (no newline)
;
; Uses the libc `write` wrapper (fd, buffer, len) instead of direct SVC.
;
; IN:  R1 = pointer to string
; OUT: none
;------------------------------------------------------------------------------
_print_string:
0x00043EEC       PUSH LR
0x00043EF0       PUSH R8
0x00043EF4       PUSH R9
0x00043EF8       MOV R8 R1
0x00043EFC   CALL strlen
0x00043F04       MOV R9 R1
0x00043F08       LI  R1 STDOUT_FD
0x00043F10       MOV R2 R8
0x00043F14       MOV R3 R9
0x00043F18   CALL write
0x00043F20       POP R9
0x00043F24       POP R8
0x00043F28       POP LR
0x00043F2C       RET


;------------------------------------------------------------------------------
; _print_number - Format and print a signed integer (uses itoa_dec)
;
; IN:  R1 = destination buffer (must be ≥13 bytes)
;      R2 = signed integer
; OUT: none
;------------------------------------------------------------------------------
_print_number:
0x00043F30       PUSH LR
0x00043F34   CALL itoa_dec
0x00043F3C       MOV R1 R1                 ; R1 still points to buffer start
0x00043F40   CALL _print_string
0x00043F48       POP LR
0x00043F4C       RET

;------------------------------------------------------------------------------
; _print_hex - Format and print an unsigned integer in hex (uses itoa_hex)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_hex:
0x00043F50       PUSH LR
0x00043F54   CALL itoa_hex
0x00043F5C       MOV R1 R1
0x00043F60   CALL _print_string
0x00043F68       POP LR
0x00043F6C       RET

;------------------------------------------------------------------------------
; _print_hex - Format and print an unsigned integer in hex (uses itoa_hex)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_bin:
0x00043F70       PUSH LR
0x00043F74   CALL itoa_bin
0x00043F7C       MOV R1 R1
0x00043F80   CALL _print_string
0x00043F88       POP LR
0x00043F8C       RET

;------------------------------------------------------------------------------
; _print_oct - Format and print an unsigned integer in octal (uses itoa_oct)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_oct:
0x00043F90       PUSH LR
0x00043F94   CALL itoa_oct
0x00043F9C       MOV R1 R1
0x00043FA0   CALL _print_string
0x00043FA8       POP LR
0x00043FAC       RET

;==============================================================================
; Data Section
;==============================================================================
space_str:
    .ASCIIZ " "

newline_str:
    .ASCIIZ "\n"

ch_buf:
    .ASCIIZ "\0"

;------------------------------------------------------------------------------
; atoi
;
; Convert decimal ASCII string to signed integer.
;
; IN:
;   R1 = string pointer
;
; OUT:
;   R1 = integer
;
; Supports:
;   "123"
;   "-123"
;   "0"
;
; Minimal KR32 implementation.
;------------------------------------------------------------------------------

atoi:
0x00043FB6       PUSH LR
0x00043FBA       PUSH R8
0x00043FBE       PUSH R9
0x00043FC2       PUSH R10

0x00043FC6       MOV R8 R1          ; R8 = string
0x00043FCA       LI  R9 0           ; R9 = result
0x00043FD2       LI  R10 0          ; R10 = negative flag

    ; Check '-'
0x00043FDA       LDB R2 [R8]
0x00043FDE       CMP R2 45          ; '-'
0x00043FE2       BNE atoi_loop
0x00043FEA       LI R10 1
0x00043FF2       ADD R8 R8 1
atoi_loop:
0x00043FF6       LDB R2 [R8]
    ; end of string
0x00043FFA       CMP R2 0
0x00043FFE       BEQ atoi_done
    ; only accept '0'..'9'
0x00044006       CMP R2 48       ; '0'
0x0004400A       BLT atoi_done
0x00044012       CMP R2 57       ; '9'
0x00044016       BGT atoi_done

    ; digit = char - '0'
0x0004401E       SUB R2 R2 48

    ; result = result * 10 + digit
0x00044022       LI  R3 10
0x0004402A       MUL R9 R9 R3
0x0004402E       ADD R9 R9 R2
0x00044032       ADD R8 R8 1
0x00044036       B atoi_loop
atoi_done:
0x0004403E       CMP R10 1
0x00044042       BNE atoi_positive
    ; negate NEG =)
0x0004404A       NOT R9 R9
0x0004404E       ADD R9 R9 1
atoi_positive:
0x00044052       MOV R1 R9
0x00044056       POP R10
0x0004405A       POP R9
0x0004405E       POP R8
0x00044062       POP LR
0x00044066       RET

;==============================================================================
; main - Program entry point
; IN:  R1 = argc, R2 = argv
; OUT: R1 = 0 (always succeeds)
;==============================================================================
main:
0x0004406A       NOP

0x0004406E       PUSH LR
0x00044072       PUSH R8              ;
0x00044076       PUSH R9              ;
0x0004407A       PUSH R10             ; Loop counter

0x0004407E       MOV R8 R1            ; R8 = argc
0x00044082       MOV R9 R2            ; R9 = argv
0x00044086       LI R10 1             ; Start from argv[1] (skip program name argv[0])
0x0004408E       MOV R11 R9           ; R11 = current argv pointer
0x00044092       ADD R11 R11 4        ; Skip argv[0] (program name)

echo_next_arg:
0x00044096       CMP R10 R8           ; Check if we've processed all arguments
0x0004409A       BGE echo_done

0x000440A2       LDW R1 [R11]         ; Load current argument string
0x000440A6       BL puts              ; Print the argument-string

0x000440AE       ADD R10 R10 1        ; Increment argument counter
0x000440B2       ADD R11 R11 4        ; Move to next argv entry
0x000440B6       CMP R10 R8           ; Check if this was the last argument
0x000440BA       BGE echo_newline     ; If last, just print newline
0x000440C2       LI R1 space_str      ; Otherwise print space between arguments
0x000440CA       BL puts
0x000440D2       B echo_next_arg

echo_newline:
0x000440DA       LI R1 newline_str    ; Print final newline
0x000440E2       BL puts

echo_done:

0x000440EA       LI R1 0              ; Return success
0x000440F2       POP R10
0x000440F6       POP R9
0x000440FA       POP R8
0x000440FE       POP LR
0x00044102       RET
