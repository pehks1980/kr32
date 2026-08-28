.org 0x00043000
; ================================================================
; /bin/sh – Minimal shell (version 0) using libc
; ================================================================

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
; puts - Write null-terminated string to stdout
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
    ;LI  R1 10             ; Newline character
    ;BL  putchar           ; Write newline
0x00043088       POP R9
0x0004308C       POP R8
0x00043090       POP LR
0x00043094       RET

;==============================================================================
; putchar - Write single character to stdout
; IN:  R1 = character
; OUT: R1 = bytes written (1) or error code
;==============================================================================
putchar:
0x00043098       PUSH LR
0x0004309C       PUSH R8
0x000430A0       LI R8 ch_buf
0x000430A8       STB R1 [R8]          ; Store char in static buffer
0x000430AC       LI R1 STDOUT_FD
0x000430B4       MOV R2 R8
0x000430B8       LI R3 1
0x000430C0       SVC SYS_WRITE
0x000430C4       POP R8
0x000430C8       POP LR
0x000430CC       RET

;==============================================================================
; strlen - Calculate string length
; IN:  R1 = string pointer
; OUT: R1 = length (excluding null terminator)
;==============================================================================
strlen:
0x000430D0       PUSH LR
0x000430D4       PUSH R8
0x000430D8       PUSH R9
0x000430DC       MOV R8 R1
0x000430E0       LI R9 0
strlen_loop:
0x000430E8       LDB R2 [R8 + R9]     ; Read character at current offset
0x000430EC       CMP R2 0
0x000430F0       BEQ strlen_done
0x000430F8       ADD R9 R9 1          ; Increment counter
0x000430FC       B strlen_loop
strlen_done:
0x00043104       MOV R1 R9
0x00043108       POP R9
0x0004310C       POP R8
0x00043110       POP LR
0x00043114       RET

;==============================================================================
; strcmp - Compare two strings
; IN:  R1 = string1, R2 = string2
; OUT: R1 = 1 if equal, 0 if different
;==============================================================================
strcmp:
0x00043118       PUSH LR
0x0004311C       PUSH R8
0x00043120       PUSH R9
0x00043124       PUSH R10
0x00043128       MOV R8 R1
0x0004312C       MOV R9 R2
strcmp_loop:
0x00043130       LDB R10 [R8]         ; Load char from string1
0x00043134       LDB R1 [R9]          ; Load char from string2
0x00043138       CMP R10 R1
0x0004313C       BNE strcmp_ne        ; Mismatch found
0x00043144       CMP R10 0
0x00043148       BEQ strcmp_eq        ; Both strings ended at same time
0x00043150       ADD R8 R8 1          ; Advance both pointers
0x00043154       ADD R9 R9 1
0x00043158       B strcmp_loop
strcmp_eq:
0x00043160       LI R1 1
0x00043168       B strcmp_done
strcmp_ne:
0x00043170       LI R1 0
strcmp_done:
0x00043178       POP R10
0x0004317C       POP R9
0x00043180       POP R8
0x00043184       POP LR
0x00043188       RET

;==============================================================================
; memcpy - Copy memory block
; IN:  R1 = dest, R2 = src, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memcpy:
0x0004318C       PUSH LR
0x00043190       PUSH R8
0x00043194       PUSH R9
0x00043198       PUSH R10
0x0004319C       MOV R8 R1
0x000431A0       MOV R9 R2
0x000431A4       MOV R10 R3
memcpy_loop:
0x000431A8       CMP R10 0
0x000431AC       BEQ memcpy_done
0x000431B4       LDB R1 [R9]          ; Read byte from source
0x000431B8       STB R1 [R8]          ; Write byte to destination
0x000431BC       ADD R8 R8 1          ; Advance both pointers
0x000431C0       ADD R9 R9 1
0x000431C4       SUB R10 R10 1        ; Decrement counter
0x000431C8       B memcpy_loop
memcpy_done:
0x000431D0       MOV R1 R8
0x000431D4       POP R10
0x000431D8       POP R9
0x000431DC       POP R8
0x000431E0       POP LR
0x000431E4       RET

;==============================================================================
; memset - Fill memory with constant byte
; IN:  R1 = dest, R2 = value, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memset:
0x000431E8       PUSH LR
0x000431EC       PUSH R8
0x000431F0       PUSH R9
0x000431F4       PUSH R10
0x000431F8       MOV R8 R1
0x000431FC       MOV R9 R2
0x00043200       MOV R10 R3
memset_loop:
0x00043204       CMP R10 0
0x00043208       BEQ memset_done
0x00043210       STB R9 [R8]          ; Store value at current position
0x00043214       ADD R8 R8 1          ; Advance pointer
0x00043218       SUB R10 R10 1        ; Decrement counter
0x0004321C       B memset_loop
memset_done:
0x00043224       MOV R1 R8
0x00043228       POP R10
0x0004322C       POP R9
0x00043230       POP R8
0x00043234       POP LR
0x00043238       RET

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
0x0004323C       SVC SYS_WRITE
0x00043240       RET


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
0x00043244       SVC SYS_READ
0x00043248       RET


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
0x0004324C       SVC SYS_OPEN
0x00043250       RET


;------------------------------------------------------------------------------
; close(fd)
;------------------------------------------------------------------------------
close:
0x00043254       SVC SYS_CLOSE
0x00043258       RET


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
0x0004325C       SVC SYS_FORK
0x00043260       RET


;------------------------------------------------------------------------------
; execve(path, argv, envp)
;------------------------------------------------------------------------------
execve:
0x00043264       SVC SYS_EXECVE
0x00043268       RET


;------------------------------------------------------------------------------
; waitpid(pid,status)
;------------------------------------------------------------------------------
waitpid:
0x0004326C       SVC SYS_WAITPID
0x00043270       RET


;------------------------------------------------------------------------------
; sleep(milliseconds)
;------------------------------------------------------------------------------
sleep:
0x00043274       SVC SYS_SLEEP
0x00043278       RET


;------------------------------------------------------------------------------
; exit(status)
;
; never returns
;------------------------------------------------------------------------------
exit:
0x0004327C       SVC SYS_EXIT

exit_hang:
0x00043280       B exit_hang


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
0x000434C8       PUSH LR               ; Save return address

    ; Step 1: Align size to multiple of 8 bytes
    ; Why? Many CPUs work faster with aligned memory
    ; Example: size=100
    ;   ADD R1 7    -> 107
    ;   AND 0xFFFFFFF8 -> 104 (multiple of 8)
0x000434CC       ADD R1 R1 7           ; Add 7 to round up
0x000434D0       LI  R2 0xFFFFFFF8
0x000434D8       AND R1 R1 R2          ; Clear lower 3 bits (make multiple of 8)
0x000434DC       MOV R5 R1             ; R5 = aligned size (e.g., 104)

    ; Step 2: Search for a free block in the table
    ; We'll use R4 as index into block_table (0 to MAX_BLOCKS-1)
0x000434E0       LI R4 0               ; Start at first block (index 0)

malloc_loop:
    ; Check if we've searched all blocks
0x000434E8       CMP R4 MAX_BLOCKS     ; Compare index with maximum
0x000434EC       BGE malloc_sbrk       ; If index >= MAX_BLOCKS, no free block found

    ; Calculate address of this block's descriptor
    ; block_table + (index * descriptor_size)
0x000434F4       LI R2 block_table     ; R2 = base address of block_table
0x000434FC       LI R3 BLOCK_DESC      ; R3 = size of one descriptor (12 bytes)
0x00043504       MUL R3 R4 R3          ; R3 = index * 12 (offset into table)
0x00043508       ADD R2 R2 R3          ; R2 = &block[index]

    ; Check if this block is free (USED flag = 0)
0x0004350C       LDW R3 [R2 + BLOCK_USED]  ; Load the &block[index].block_used flag
0x00043510       CMP R3 0              ; Is it 0 (free)?
0x00043514       BNE malloc_next       ; If not free (used), skip to next block

    ; free. Check if this block is large enough for our request
0x0004351C       LDW R3 [R2 + BLOCK_SIZE]  ; Load the block size
0x00043520       CMP R3 R5             ; Is block size >= requested size?
0x00043524       BGE malloc_found      ; Yes! We found a suitable block

malloc_next:
    ; This block is either used or too small, try next one
0x0004352C       ADD R4 R4 1           ; Increment index to check next block
0x00043530       B malloc_loop         ; Go back to start of loop

malloc_found:
    ; Step 3: We found a free block large enough!
    ; R2 = pointer to the block descriptor
    ; R3 = block size (we don't use it for splitting in this simple version)

    ; Mark the block as used (USED flag = 1)
0x00043538       LI R3 1               ; R3 = 1 (used)
0x00043540       STW R3 [R2 + BLOCK_USED]  ; Store 1 in the USED field

    ; Get the block's starting address and return it
0x00043544       LDW R1 [R2 + BLOCK_ADDR]  ; R1 = address of this block
0x00043548       B malloc_done         ; Jump to cleanup and return

malloc_sbrk:
    ; Step 4: No free block found in table
    ; Ask the kernel for more memory using sbrk syscall

    ; R5 already has the aligned size we need
0x00043550       MOV R1 R5             ; R1 = size to allocate
0x00043554       SVC SYS_SBRK          ; Call kernel: sbrk(size)

    ; Check if sbrk failed (returns -1 or 0 on error)
0x00043558       CMP R1 0              ; Did sbrk return 0 or negative?
0x0004355C       BLT malloc_error      ; If error, return NULL

    ; Step 5: sbrk succeeded, we have new memory at address in R1
    ; Now we need to add this new block to our table

    ; Find an empty slot in the block table
0x00043564       LI R4 0               ; Start at first block

malloc_add:
    ; Check if we've searched all blocks
0x0004356C       CMP R4 MAX_BLOCKS
0x00043570       BGE malloc_error      ; No empty slot! (shouldn't happen)

    ; Get descriptor address
0x00043578       LI R2 block_table
0x00043580       LI R3 BLOCK_DESC
0x00043588       MUL R3 R4 R3
0x0004358C       ADD R2 R2 R3        ; &block[indexR4]

    ; Check if this slot is free (USED flag = 0)
0x00043590       LDW R3 [R2 + BLOCK_USED]
0x00043594       CMP R3 0
0x00043598       BEQ malloc_add_found  ; Found an empty slot!

    ; Slot is used, try next one
0x000435A0       ADD R4 R4 1
0x000435A4       B malloc_add

malloc_add_found:
    ; We found an empty slot at R2
    ; Store the new block's information

    ; Store the address (R1 from sbrk)
0x000435AC       STW R1 [R2 + BLOCK_ADDR]   ; block.address = address from sbrk

    ; Store the size (R5 = aligned size)
0x000435B0       STW R5 [R2 + BLOCK_SIZE]   ; block.size = size

    ; Mark as used (USED = 1)
0x000435B4       LI R3 1
0x000435BC       STW R3 [R2 + BLOCK_USED]   ; block.used = 1

    ; R1 already has the address from sbrk, so just return it
0x000435C0       B malloc_done

malloc_error:
    ; Something went wrong - return NULL (0)
0x000435C8       LI R1 0

malloc_done:
0x000435D0       POP LR                ; Restore return address
0x000435D4       RET                   ; Return to caller with R1 = pointer or NULL

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
0x000435D8       PUSH LR

    ; Step 1: Check if pointer is NULL
0x000435DC       CMP R1 0              ; Is R1 == 0?
0x000435E0       BEQ free_done         ; If NULL, nothing to free, just return

    ; Step 2: Search the block table for this address
0x000435E8       LI R4 0               ; Start at first block

free_loop:
    ; Check if we've searched all blocks
0x000435F0       CMP R4 MAX_BLOCKS
0x000435F4       BGE free_done         ; Not found - ignore (could be invalid pointer)

    ; Get descriptor address
0x000435FC       LI R2 block_table
0x00043604       LI R3 BLOCK_DESC      ; length of one block descriptor
0x0004360C       MUL R3 R4 R3          ; r4 block idx
0x00043610       ADD R2 R2 R3          ; R2 = &block[i]

    ; Check if this block's address matches the pointer
0x00043614       LDW R3 [R2 + BLOCK_ADDR]  ; R3 =  &block[i].block address
0x00043618       CMP R3 R1             ; Is this our block?
0x0004361C       BEQ free_found        ; Yes, we found it!

    ; Not this block, try next
0x00043624       ADD R4 R4 1
0x00043628       B free_loop

free_found:
    ; Step 3: We found the block descriptor at R2
    ; Mark it as free so malloc can use it again

0x00043630       LI R3 0               ; R3 = 0 (free)
0x00043638       STW R3 [R2 + BLOCK_USED]  ; &block[i].used = 0

    ; NOTE: We do NOT clear the address or size
    ; They stay in the table and will be overwritten when reused

free_done:
    ; Clean up and return
0x0004363C       POP LR
0x00043640       RET

;------------------------------------------------------------------------------
; malloc_init - Initialize the memory allocator
;
; Clears the entire block table so all blocks are marked as free
; Should be called once at system startup before using malloc
;------------------------------------------------------------------------------
malloc_init:
    ; Save registers
0x00043644       PUSH LR
    ; Step 1: Clear the entire block table
    ; Set all bytes in block_table to 0
0x00043648       LI R1 block_table     ; R1 = start address of table
0x00043650       LI R3 MAX_BLOCKS * BLOCK_DESC  ; R3 = total bytes to clear

malloc_init_loop:
0x00043658       CMP R3 0              ; Have we cleared all bytes?
0x0004365C       BEQ malloc_init_done  ; Yes, we're done

0x00043664       LI R2 0               ; R2 = 0 (value to write)
0x0004366C       STB R2 [R1]           ; Store 0 at current address
0x00043670       ADD R1 R1 1           ; Move to next byte
0x00043674       SUB R3 R3 1           ; Decrement byte counter
0x00043678       B malloc_init_loop    ; Continue

malloc_init_done:
    ; Clean up and return
0x00043680       POP LR
0x00043684       RET


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
0x00043688       PUSH LR
0x0004368C       PUSH R5
0x00043690       PUSH R6
0x00043694       PUSH R7
0x00043698       PUSH R8
0x0004369C       PUSH R9
0x000436A0       PUSH R10
0x000436A4       PUSH R11
0x000436A8       PUSH R12

0x000436AC       MOV  R8  R1          ; Save destination
0x000436B0       MOV  R9  R2          ; Working value
0x000436B4       MOV  R11 R3          ; Base
0x000436B8       MOV  R12 R4          ; Sign flag
    ; Allocate temp buffer (size passed in R5)
0x000436BC       SUB  SP SP R5
0x000436C0       MOV  R10 SP          ; Temp buffer pointer

0x000436C4       PUSH R5              ; save R5 for frame leave
0x000436C8       PUSH R8              ; save result bufer

    ; Check for sign (if signed and negative)
0x000436CC       CMP  R12 1
0x000436D0       BNE  itoa_core_unsigned

0x000436D8       CMP  R9 0
0x000436DC       BGE  itoa_core_unsigned

    ; Negative number - add minus sign
0x000436E4       LI   R2 45     ;'-'
0x000436EC       STB  R2 [R8]
0x000436F0       ADD  R8 R8 1
0x000436F4       NOT  R9 R9
0x000436F8       ADD  R9 R9 1
    ;NEG  R9              ; Make positive

itoa_core_unsigned:
    ; Special case: zero
0x000436FC       CMP  R9 0
0x00043700       BNE  itoa_core_convert

0x00043708       LI   R2 48    ; '0'
0x00043710       STB  R2 [R8]
0x00043714       ADD  R8 R8 1
0x00043718       LI   R2 0
0x00043720       STB  R2 [R8]
0x00043724       B    itoa_core_finish

itoa_core_convert:

0x0004372C       LI  R4 0                  ; R4 = digit counter

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
0x00043734       MOV R5 R9
    ; R6 = quotient
0x00043738       DIV R6 R5 R11
    ; R7 = remainder
0x0004373C       MOD R7 R9 R11
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
0x00043740       CMP R11 16
0x00043744       BEQ itoa_core_hex_digit
    ; Base 2 or base 10
0x0004374C       ADD R7 R7 48             ; '0' + digit
0x00043750       B itoa_core_store

itoa_core_hex_digit:
0x00043758       CMP R7 9
0x0004375C       BGT itoa_core_hex_letter
    ; 0..9
0x00043764       ADD R7 R7 48             ; '0' + digit
0x00043768       B itoa_core_store

itoa_core_hex_letter:
    ; 10..15
0x00043770       SUB R7 R7 10
0x00043774       ADD R7 R7 65             ; 'A' + (digit - 10)

; ================================================================
; Store generated digit
; ================================================================

itoa_core_store:

0x00043778       STB R7 [R10]    ;R10 is the temporary-buffer pointer.

0x0004377C       ADD R10 R10 1
0x00043780       ADD R4 R4 1     ; One more digit generated

    ; ------------------------------------------------------------
    ; The quotient becomes the value for the next iteration.
    ;
    ; Example:
    ;
    ;   123 / 10 = 12
    ;    12 / 10 = 1
    ;     1 / 10 = 0
    ; ------------------------------------------------------------

0x00043784       MOV R9 R6

    ; Continue until quotient becomes zero
0x00043788       CMP R9 0
0x0004378C       BNE itoa_core_divloop

; ================================================================
; Digits are now stored backwards in temporary buffer.
; temp = "321"
;
; R10 points just AFTER the last digit.
;
; Move back to the final digit:
; ================================================================

0x00043794       SUB R10 R10 1

; ================================================================
; Copy digits from temporary buffer backwards
; ================================================================

itoa_core_copy:
0x00043798       CMP R4 0
0x0004379C       BEQ itoa_core_done
    ; Read last generated digit
0x000437A4       LDB R2 [R10]
    ; Write it to destination
0x000437A8       STB R2 [R8]
0x000437AC       ADD R8 R8 1
    ; Move backwards through temporary buffer
0x000437B0       SUB R10 R10 1
    ; One less digit
0x000437B4       SUB R4 R4 1
0x000437B8       B itoa_core_copy

itoa_core_done:
0x000437C0       LI   R2 0
0x000437C8       STB  R2 [R8]         ; Null terminate

itoa_core_finish:
0x000437CC       POP  R1              ; Return original pointer
0x000437D0       POP  R5
    ; Clean up temp buffer
0x000437D4       ADD  SP SP R5

0x000437D8       POP R12
0x000437DC       POP R11
0x000437E0       POP R10
0x000437E4       POP R9
0x000437E8       POP R8
0x000437EC       POP R7
0x000437F0       POP R6
0x000437F4       POP R5
0x000437F8       POP LR
0x000437FC       RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
0x00043800       PUSH LR

    ; Max 11 digits + sign + null = 13 bytes
0x00043804       LI   R3 10           ; Base 10
0x0004380C       LI   R4 1            ; Signed
0x00043814       LI   R5 13           ; Temp buffer size
0x0004381C   CALL itoa_core

0x00043824       POP  LR
0x00043828       RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
0x0004382C       PUSH LR

    ; Max 8 digits + null = 9 bytes
0x00043830       LI   R3 16           ; Base 16
0x00043838       LI   R4 0            ; Unsigned (shows raw bits)
0x00043840       LI   R5 9            ; Temp buffer size
0x00043848   CALL itoa_core

0x00043850       POP  LR
0x00043854       RET


;---------------------------------------------------------
; itoa_oct - Octal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_oct:
0x00043858       PUSH LR

    ; Max 12 digits + null = 13 bytes
0x0004385C       LI   R3 8            ; Base 8
0x00043864       LI   R4 0            ; Unsigned (shows raw bits)
0x0004386C       LI   R5 13           ; Temp buffer size
0x00043874   CALL itoa_core

0x0004387C       POP  LR
0x00043880       RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
0x00043884       PUSH LR

    ; Max 32 bits + null = 33 bytes
0x00043888       LI   R3 2            ; Base 2
0x00043890       LI   R4 0            ; Unsigned (shows raw bits)
0x00043898       LI   R5 33           ; Temp buffer size
0x000438A0   CALL itoa_core

0x000438A8       POP  LR
0x000438AC       RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
0x000438B0       PUSH LR

    ; Max 8 digits + sign + null = 10 bytes
0x000438B4       LI   R3 16           ; Base 16
0x000438BC       LI   R4 1            ; Signed (shows sign)
0x000438C4       LI   R5 10           ; Temp buffer size
0x000438CC   CALL itoa_core

0x000438D4       POP  LR
0x000438D8       RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
0x000438DC       PUSH LR

    ; Max 32 bits + sign + null = 34 bytes
0x000438E0       LI   R3 2            ; Base 2
0x000438E8       LI   R4 1            ; Signed (shows sign)
0x000438F0       LI   R5 34           ; Temp buffer size
0x000438F8   CALL itoa_core

0x00043900       POP  LR
0x00043904       RET

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
0x00043908       PUSH LR
0x0004390C       MOV R3 R1              ; Save original destination pointer
0x00043910       MOV R4 R2              ; Save source pointer

strcpy_loop:
0x00043914       LDB R2 [R4]            ; Load byte from source
0x00043918       STB R2 [R1]            ; Store byte to destination

0x0004391C       CMP R2 0               ; Check if it's null terminator
0x00043920       BEQ strcpy_done        ; If zero, we're done

0x00043928       ADD R1 R1 1            ; Advance destination pointer
0x0004392C       ADD R4 R4 1            ; Advance source pointer
0x00043930       B strcpy_loop

strcpy_done:
0x00043938       MOV R1 R3              ; Return original destination pointer
0x0004393C       POP LR
0x00043940       RET


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
0x00043944       PUSH LR
0x00043948       PUSH R8
0x0004394C       PUSH R9

0x00043950       MOV R8 R1            ; Save path
    ; Open directory with read-only flags (same as your ls.asm)
0x00043954       MOV R1 R8
0x00043958       LI  R2 O_RDONLY
0x00043960       SVC SYS_OPEN
0x00043964       MOV R9 R1           ;fd
0x00043968       CMP R1 0
0x0004396C       BLT opendir_error

    ; Allocate DIR structure (small, just fd and offset)
0x00043974       PUSH R9                 ;save R9 jic
0x00043978       LI R1 DIR_SIZEOF
0x00043980   CALL malloc
0x00043988       POP  R9

0x0004398C       CMP R1 0
0x00043990       BEQ opendir_error_close

0x00043998       MOV R8 R1            ; Save DIR*

    ; Initialize DIR structure
    ; R2 still has fd from open
0x0004399C       STW R9 [R8 + DIR_FD]
0x000439A0       LI  R2 0
0x000439A8       STW R2 [R8 + DIR_OFFSET]

0x000439AC       MOV R1 R8            ; Return DIR*
0x000439B0       B opendir_done

opendir_error_close:
0x000439B8       MOV R1 R9            ; fd is in R9
0x000439BC       SVC SYS_CLOSE
0x000439C0       LI R1 0
0x000439C8       B opendir_done

opendir_error:
0x000439D0       LI R1 0

opendir_done:
0x000439D8       POP R9
0x000439DC       POP R8
0x000439E0       POP LR
0x000439E4       RET

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
0x000439E8       PUSH LR
0x000439EC       PUSH R8
0x000439F0       PUSH R9

0x000439F4       MOV R8 R1            ; DIR*
0x000439F8       MOV R9 R2            ; User's dirent buffer

    ; Check if DIR pointer is valid
0x000439FC       CMP R8 0
0x00043A00       BEQ readdir_error

    ; Read one dirent from directory fd using current offset
0x00043A08       LDW R1 [R8 + DIR_FD] ; fd

    ; Use the directory's offset - we need to implement lseek or use
    ; the fact that each read gets one dirent at a time from tarfs
0x00043A0C       MOV R2 R9            ; user buffer
0x00043A10       LI  R3 DIRENT_SIZEOF ; size of one dirent
0x00043A18       SVC SYS_READ
0x00043A1C       CMP R1 0
0x00043A20       BEQ readdir_end      ; EOF
0x00043A28       CMP R1 DIRENT_SIZEOF
0x00043A2C       BNE readdir_error    ; Short read or error

    ; Entry read successfully
    ; Update the offset in DIR structure
0x00043A34       LDW R2 [R8 + DIR_OFFSET]
0x00043A38       ADD R2 R2 1
0x00043A3C       STW R2 [R8 + DIR_OFFSET]

0x00043A40       LI R1 1              ; Return success
0x00043A48       B readdir_done

readdir_error:
0x00043A50       LI R1 -1
0x00043A58       B readdir_done

readdir_end:
0x00043A60       LI R1 0

readdir_done:
0x00043A68       POP R9
0x00043A6C       POP R8
0x00043A70       POP LR
0x00043A74       RET

;------------------------------------------------------------------------------
; closedir - Close directory stream
;
; IN:  R1 = DIR*
; OUT: R1 = 0 on success, -1 on error
;------------------------------------------------------------------------------
closedir:
0x00043A78       PUSH LR
0x00043A7C       PUSH R8

0x00043A80       MOV R8 R1
0x00043A84       CMP R8 0
0x00043A88       BEQ closedir_error

    ; Close the directory fd
0x00043A90       LDW R1 [R8 + DIR_FD]
0x00043A94       SVC SYS_CLOSE

    ; Free the DIR structure
0x00043A98       MOV R1 R8
0x00043A9C   CALL free

0x00043AA4       LI R1 0
0x00043AAC       B closedir_done

closedir_error:
0x00043AB4       LI R1 -1

closedir_done:
0x00043ABC       POP R8
0x00043AC0       POP LR
0x00043AC4       RET

;------------------------------------------------------------------------------
; rewinddir - Reset directory stream to beginning
;
; IN:  R1 = DIR*
;------------------------------------------------------------------------------
rewinddir:
0x00043AC8       CMP R1 0
0x00043ACC       BEQ rewinddir_done

0x00043AD4       LI R2 0
0x00043ADC       STW R2 [R1 + DIR_OFFSET]

    ; Need to seek to beginning of directory
    ; For tarfs, this means closing and reopening, or using lseek
    ; Simple approach: close and reopen
0x00043AE0       PUSH LR
0x00043AE4       PUSH R8

0x00043AE8       MOV R8 R1
    ; Save the path - we don't have it stored, so this is tricky
    ; In a real implementation, store path in DIR structure

    ; For now, just reset offset and rely on readdir's behavior

0x00043AEC       POP R8
0x00043AF0       POP LR

rewinddir_done:
0x00043AF4       RET

;------------------------------------------------------------------------------
; dirfd - Get file descriptor from DIR*
;
; IN:  R1 = DIR*
; OUT: R1 = file descriptor, or -1 on error
;------------------------------------------------------------------------------
dirfd:
0x00043AF8       CMP R1 0
0x00043AFC       BEQ dirfd_error

0x00043B04       LDW R1 [R1 + DIR_FD]
0x00043B08       RET

dirfd_error:
0x00043B0C       LI R1 -1
0x00043B14       RET

;------------------------------------------------------------------------------
; Helper: is_dir - Check if a path is a directory
;
; IN:  R1 = path
; OUT: R1 = 1 if directory, 0 if not, -1 on error
;------------------------------------------------------------------------------
is_dir:
0x00043B18       PUSH LR

    ; Try to open as directory
0x00043B1C   CALL opendir
0x00043B24       CMP R1 0
0x00043B28       BEQ is_dir_not_dir

    ; It opened as a directory
0x00043B30       MOV R2 R1            ; Save DIR*
0x00043B34       LI R1 1              ; Return true
0x00043B3C   CALL closedir
0x00043B44       B is_dir_done

is_dir_not_dir:
0x00043B4C       LI R1 0

is_dir_done:
0x00043B54       POP LR
0x00043B58       RET

;------------------------------------------------------------------------------
; Example usage function - list directory contents (like ls)
; This demonstrates how to use opendir/readdir/closedir
;------------------------------------------------------------------------------
list_directory:
0x00043B5C       PUSH LR
0x00043B60       PUSH R8
0x00043B64       PUSH R9

0x00043B68       MOV R8 R1            ; path

    ; Allocate dirent on stack
0x00043B6C       SUB SP SP DIRENT_SIZEOF
0x00043B70       MOV R9 SP

    ; Open directory
0x00043B74       MOV R1 R8
0x00043B78   CALL opendir
0x00043B80       CMP R1 0
0x00043B84       BEQ list_dir_error

0x00043B8C       MOV R8 R1            ; DIR*

list_dir_loop:
0x00043B90       MOV R1 R8
0x00043B94       MOV R2 R9
0x00043B98   CALL readdir
0x00043BA0       CMP R1 0
0x00043BA4       BEQ list_dir_close
0x00043BAC       LI  R2 -1
0x00043BB4       CMP R1 R2
0x00043BB8       BEQ list_dir_error

    ; Print the name
0x00043BC0       ADD R1 R9 DIRENT_NAME
0x00043BC4   CALL puts

    ; If it's a directory, print '/'
0x00043BCC       LDW R2 [R9 + DIRENT_TYPE]
0x00043BD0       CMP R2 DT_DIR
0x00043BD4       BNE list_dir_not_dir

0x00043BDC       LI R1 slash_char
0x00043BE4   CALL putchar

list_dir_not_dir:
0x00043BEC       LI R1 newline_char
0x00043BF4   CALL putchar

0x00043BFC       B list_dir_loop

list_dir_close:
0x00043C04       MOV R1 R8
0x00043C08   CALL closedir
0x00043C10       LI R1 0
0x00043C18       B list_dir_done

list_dir_error:
0x00043C20       LI R1 -1

list_dir_done:
0x00043C28       ADD SP SP DIRENT_SIZEOF
0x00043C2C       POP R9
0x00043C30       POP R8
0x00043C34       POP LR
0x00043C38       RET

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
0x00043C44       PUSH LR
0x00043C48       PUSH R8
0x00043C4C       PUSH R9
0x00043C50       PUSH R10
0x00043C54       PUSH R11
0x00043C58       PUSH R12

0x00043C5C       SUB SP SP 80              ; local frame: 44 + 34 + padding

    ; Save R2..R12 to local array
0x00043C60       STW R2 [SP + 0]
0x00043C64       STW R3 [SP + 4]
0x00043C68       STW R4 [SP + 8]
0x00043C6C       STW R5 [SP + 12]
0x00043C70       STW R6 [SP + 16]
0x00043C74       STW R7 [SP + 20]
0x00043C78       STW R8 [SP + 24]
0x00043C7C       STW R9 [SP + 28]
0x00043C80       STW R10 [SP + 32]
0x00043C84       STW R11 [SP + 36]
0x00043C88       STW R12 [SP + 40]

0x00043C8C       MOV R8 R1                 ; format pointer
0x00043C90       LI  R9 0                  ; argument index

0x00043C98       MOV R10 SP                ; base of saved registers
0x00043C9C       ADD R11 SP 44             ; conversion buffer

printf_loop:
0x00043CA0       LDB R1 [R8]     ;read fmt string char
0x00043CA4       CMP R1 0
0x00043CA8       BEQ printf_done

0x00043CB0       CMP R1 37   ;check for '%'
0x00043CB4       BNE printf_normal_char

0x00043CBC       ADD R8 R8 1 ; its a '%', move to next char for specifier
0x00043CC0       LDB R2 [R8]
0x00043CC4       CMP R2 0
0x00043CC8       BEQ printf_done

0x00043CD0       CMP R2 37   ; check for '%%'
0x00043CD4       BEQ printf_percent
0x00043CDC       CMP R2 115  ; check for '%s'
0x00043CE0       BEQ printf_string
0x00043CE8       CMP R2 100  ;check for '%d'
0x00043CEC       BEQ printf_int
0x00043CF4       CMP R2 105  ;check for '%i'
0x00043CF8       BEQ printf_int
0x00043D00       CMP R2 120  ;check for '%x'
0x00043D04       BEQ printf_hex
0x00043D0C       CMP R2 99   ;check for '%c'
0x00043D10       BEQ printf_char
0x00043D18       CMP R2 98   ;check for '%b'
0x00043D1C       BEQ printf_bin
0x00043D24       CMP R2 111  ;check for '%o'
0x00043D28       BEQ printf_oct

    ; unknown specifier
0x00043D30       LI  R1 37   ;unknown specifier, print '%'
0x00043D38   CALL putchar
0x00043D40       MOV R1 R2   ; print the unknown specifier char
0x00043D44   CALL putchar
0x00043D4C       B   printf_continue

printf_normal_char:
0x00043D54   CALL putchar
0x00043D5C       B   printf_continue

printf_percent:
0x00043D64       LI  R1 37   ;print '%'
0x00043D6C   CALL putchar
0x00043D74       B   printf_continue

;------------------------------------------------------------------------------
; Argument fetch helpers (same as before)
;------------------------------------------------------------------------------
_fetch_arg_r1:
0x00043D7C       PUSH LR
0x00043D80       PUSH R3
0x00043D84   CALL _get_arg_address
0x00043D8C       LDW R1 [R3]
0x00043D90       POP R3
0x00043D94       POP LR
0x00043D98       RET

_fetch_arg_r2:
0x00043D9C       PUSH LR
0x00043DA0       PUSH R3
0x00043DA4   CALL _get_arg_address
0x00043DAC       LDW R2 [R3]
0x00043DB0       POP R3
0x00043DB4       POP LR
0x00043DB8       RET

_get_arg_address:   ; fetch the address of the next argument based on R9 (arg index)
0x00043DBC       CMP R9 11       ; if arg index >= 11, it's on the stack
0x00043DC0       BLT _arg_in_regs
0x00043DC8       SUB R3 R9 11    ; R3 = number of extra args on stack
0x00043DCC       LI  R4 4
0x00043DD4       MUL R3 R3 R4
0x00043DD8       ADD R3 SP R3    ; R3 = address of first extra arg on stack (not sure if this is correct)
0x00043DDC       ADD R3 R3 104   ; offset to caller's first extra arg 104
                    ;is the size of the local frame (80) + saved registers (44)
0x00043DE0       RET

_arg_in_regs:       ; fetch argument from R2..R12 based on R9
0x00043DE4       LI  R4 4
0x00043DEC       MUL R3 R9 R4    ; R9 = arg index, (R3 = offset in bytes)
0x00043DF0       ADD R3 R10 R3   ; R3 = address of saved register in local array, R10 = base of saved registers
0x00043DF4       RET

;------------------------------------------------------------------------------
; Specifier handlers
;------------------------------------------------------------------------------
printf_string:
0x00043DF8   CALL _fetch_arg_r1
0x00043E00       ADD R9 R9 1
0x00043E04   CALL _print_string
0x00043E0C       B   printf_continue

printf_int:
0x00043E14   CALL _fetch_arg_r2

0x00043E1C       MOV R1 R2           ;convert number from string format cmd to integer (may be singed)
0x00043E20   CALL atoi
0x00043E28       MOV R2 R1

0x00043E2C       ADD R9 R9 1
0x00043E30       MOV R1 R11          ; r11 is the conversion buffer (on stack)
0x00043E34   CALL _print_number
0x00043E3C       B   printf_continue

printf_hex:
0x00043E44   CALL _fetch_arg_r2

0x00043E4C       MOV R1 R2           ;convert number from string format cmd to integer (may be singed)
0x00043E50   CALL atoi
0x00043E58       MOV R2 R1

0x00043E5C       ADD R9 R9 1
0x00043E60       MOV R1 R11          ; r11 is the conversion buffer (on stack) and so on for other conversions helpers..
0x00043E64   CALL _print_hex
0x00043E6C       B   printf_continue

printf_char:
0x00043E74   CALL _fetch_arg_r1
0x00043E7C       LDb R1 [R1]         ;get char by its ptr
0x00043E80       ADD R9 R9 1
0x00043E84   CALL putchar
0x00043E8C       B   printf_continue

printf_bin:
0x00043E94   CALL _fetch_arg_r2

0x00043E9C       MOV R1 R2           ;convert number from string format cmd to integer (may be singed)
0x00043EA0   CALL atoi
0x00043EA8       MOV R2 R1

0x00043EAC       ADD R9 R9 1
0x00043EB0       MOV R1 R11
0x00043EB4   CALL _print_bin
0x00043EBC       B   printf_continue

printf_oct:
0x00043EC4   CALL _fetch_arg_r2

0x00043ECC       MOV R1 R2           ;convert number from string format cmd to integer (may be singed)
0x00043ED0   CALL atoi
0x00043ED8       MOV R2 R1

0x00043EDC       ADD R9 R9 1
0x00043EE0       MOV R1 R11
0x00043EE4   CALL _print_oct
0x00043EEC       B   printf_continue

printf_continue:    ;to continue processing format string
0x00043EF4       ADD R8 R8 1
0x00043EF8       B   printf_loop

printf_done:
0x00043F00       ADD SP SP 80
0x00043F04       POP R12
0x00043F08       POP R11
0x00043F0C       POP R10
0x00043F10       POP R9
0x00043F14       POP R8
0x00043F18       POP LR
0x00043F1C       RET

;------------------------------------------------------------------------------
; _print_string - Write a null‑terminated string to stdout (no newline)
;
; Uses the libc `write` wrapper (fd, buffer, len) instead of direct SVC.
;
; IN:  R1 = pointer to string
; OUT: none
;------------------------------------------------------------------------------
_print_string:
0x00043F20       PUSH LR
0x00043F24       PUSH R8
0x00043F28       PUSH R9
0x00043F2C       MOV R8 R1
0x00043F30   CALL strlen
0x00043F38       MOV R9 R1
0x00043F3C       LI  R1 STDOUT_FD
0x00043F44       MOV R2 R8
0x00043F48       MOV R3 R9
0x00043F4C   CALL write
0x00043F54       POP R9
0x00043F58       POP R8
0x00043F5C       POP LR
0x00043F60       RET


;------------------------------------------------------------------------------
; _print_number - Format and print a signed integer (uses itoa_dec)
;
; IN:  R1 = destination buffer (must be ≥13 bytes)
;      R2 = signed integer
; OUT: none
;------------------------------------------------------------------------------
_print_number:
0x00043F64       PUSH LR
0x00043F68   CALL itoa_dec
0x00043F70       MOV R1 R1                 ; R1 still points to buffer start
0x00043F74   CALL _print_string
0x00043F7C       POP LR
0x00043F80       RET

;------------------------------------------------------------------------------
; _print_hex - Format and print an unsigned integer in hex (uses itoa_hex)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_hex:
0x00043F84       PUSH LR
0x00043F88   CALL itoa_hex
0x00043F90       MOV R1 R1
0x00043F94   CALL _print_string
0x00043F9C       POP LR
0x00043FA0       RET

;------------------------------------------------------------------------------
; _print_hex - Format and print an unsigned integer in hex (uses itoa_hex)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_bin:
0x00043FA4       PUSH LR
0x00043FA8   CALL itoa_bin
0x00043FB0       MOV R1 R1
0x00043FB4   CALL _print_string
0x00043FBC       POP LR
0x00043FC0       RET

;------------------------------------------------------------------------------
; _print_oct - Format and print an unsigned integer in octal (uses itoa_oct)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_oct:
0x00043FC4       PUSH LR
0x00043FC8   CALL itoa_oct
0x00043FD0       MOV R1 R1
0x00043FD4   CALL _print_string
0x00043FDC       POP LR
0x00043FE0       RET

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
0x00043FEA       PUSH LR
0x00043FEE       PUSH R8
0x00043FF2       PUSH R9
0x00043FF6       PUSH R10

0x00043FFA       MOV R8 R1          ; R8 = string
0x00043FFE       LI  R9 0           ; R9 = result
0x00044006       LI  R10 0          ; R10 = negative flag

    ; Check '-'
0x0004400E       LDB R2 [R8]
0x00044012       CMP R2 45          ; '-'
0x00044016       BNE atoi_loop
0x0004401E       LI R10 1
0x00044026       ADD R8 R8 1
atoi_loop:
0x0004402A       LDB R2 [R8]
    ; end of string
0x0004402E       CMP R2 0
0x00044032       BEQ atoi_done
    ; only accept '0'..'9'
0x0004403A       CMP R2 48       ; '0'
0x0004403E       BLT atoi_done
0x00044046       CMP R2 57       ; '9'
0x0004404A       BGT atoi_done

    ; digit = char - '0'
0x00044052       SUB R2 R2 48

    ; result = result * 10 + digit
0x00044056       LI  R3 10
0x0004405E       MUL R9 R9 R3
0x00044062       ADD R9 R9 R2
0x00044066       ADD R8 R8 1
0x0004406A       B atoi_loop
atoi_done:
0x00044072       CMP R10 1
0x00044076       BNE atoi_positive
    ; negate NEG =)
0x0004407E       NOT R9 R9
0x00044082       ADD R9 R9 1
atoi_positive:
0x00044086       MOV R1 R9
0x0004408A       POP R10
0x0004408E       POP R9
0x00044092       POP R8
0x00044096       POP LR
0x0004409A       RET

.EQU STDIN_FD,  0
.EQU MAX_ARGS,  8

;---------------------------------------------------------------
; main() – shell loop
;---------------------------------------------------------------
main:
0x0004409E       PUSH LR

shell_loop:
    ; Print prompt
0x000440A2       LI R1 STDOUT_FD
0x000440AA       LI R2 prompt
0x000440B2       LI R3 2
0x000440BA   CALL write
    ; Read command
0x000440C2       LI R1 STDIN_FD
0x000440CA       LI R2 input_buf
0x000440D2       LI R3 127
0x000440DA   CALL read
0x000440E2       CMP R1 0
0x000440E6       BLE exit_shell
0x000440EE       MOV R4 R1           ; R4 = bytes read

    ; ---- Normalize line editing characters before parsing ----
    ; Treat BS/DEL as a backspace in the current command buffer.
0x000440F2       LI R8 input_buf
0x000440FA       LI R9 input_buf
0x00044102       LI R10 0            ; source index

normalize_input_loop:
0x0004410A       CMP R10 R4
0x0004410E       BGE normalize_input_done

0x00044116       ADD R5 R8 R10
0x0004411A       LDB R6 [R5]

0x0004411E       CMP R6 10            ; LF
0x00044122       BEQ normalize_input_next
0x0004412A       CMP R6 13            ; CR
0x0004412E       BEQ normalize_input_next
0x00044136       CMP R6 8             ; BS
0x0004413A       BEQ normalize_input_backspace
0x00044142       CMP R6 127           ; DEL
0x00044146       BEQ normalize_input_backspace

0x0004414E       STB R6 [R9]
0x00044152       ADD R9 R9 1
0x00044156       B normalize_input_next

normalize_input_backspace:
0x0004415E       CMP R9 R8
0x00044162       BLE normalize_input_next
0x0004416A       SUB R9 R9 1
0x0004416E       B normalize_input_next

normalize_input_next:
0x00044176       ADD R10 R10 1
0x0004417A       B normalize_input_loop

normalize_input_done:
0x00044182       LI R6 0
0x0004418A       STB R6 [R9]

    ; Skip empty lines
0x0004418E       LI R7 input_buf
0x00044196       LDB R6 [R7]
0x0004419A       CMP R6 0
0x0004419E       BEQ shell_loop

0x000441A6   CALL parse_command

0x000441AE       LI R1 input_buf
0x000441B6       LI R2 quit_cmd
0x000441BE   CALL strcmp
0x000441C6       CMP R1 1
0x000441CA       BEQ exit_shell  ;if type "quit" exit shell

    ; ---- Fork ----
0x000441D2   CALL fork
0x000441DA       CMP R1 0
0x000441DE       BEQ child_process
0x000441E6       BLT fork_error

    ;Debug 2
    ;POP LR
    ;RET

    ; ---- Parent: wait for child ----
0x000441EE       LI R1 -1
0x000441F6       LI R2 0
0x000441FE   CALL waitpid
0x00044206       CMP R1 0
0x0004420A       BLT wait_error

0x00044212       B shell_loop

    ; ---- Child: execute command ----
child_process:
    ; pathname = input_buf (copied early by kernel, before data page zeroed)
    ; argv = argv_buf
0x0004421A       LI R1 input_buf
0x00044222       LI R2 argv_buf
0x0004422A       LI R3 0
0x00044232   CALL execve
0x0004423A       LI R1 exec_failed_msg
0x00044242   CALL puts

0x0004424A       POP LR
0x0004424E       RET

fork_error:
0x00044252       LI R1 fork_error_msg
0x0004425A   CALL puts
0x00044262       B shell_loop

wait_error:
0x0004426A       LI R1 wait_error_msg
0x00044272   CALL puts
0x0004427A       B shell_loop

exit_shell:
0x00044282       POP LR
0x00044286       RET

; ---------------------------------------------------------------
; parse_command() – parse input_buf into argv_buf
;
; Supported syntax:
;   command arg1 arg2
;   command "argument with spaces"
;   command 'argument with spaces'
; Supported escapes inside quoted strings:
;
;   \n   newline
;   \r   carriage return
;   \t   tab
;   \\   backslash
;   \"   double quote
;   \'   single quote
;
; input:
;   input_buf = null-terminated command line
;
; output:
;   argv_buf = NULL-terminated argv[] vector
;
; Important:
;   Parsing is done IN PLACE.
;
;   Example:
;
;       /bin/print "hello world" 123
;
;   becomes internally:
;
;       /bin/print\0hello world\0123\0
;
;   argv_buf contains pointers:
;
;       argv[0] -> "/bin/print"
;       argv[1] -> "hello world"
;       argv[2] -> "123"
;       argv[3] -> NULL
;
; Registers:
;   R8  = source/read pointer
;   R9  = destination/write pointer
;   R10 = argc
;   R11 = current character
;   R12 = quote state
;
; quote state:
;   0 = not inside quotes
;   '"' = inside double quotes
;   "'" = inside single quotes
; ---------------------------------------------------------------
; ---------------------------------------------------------------
; parse_command()
;
; Parse input_buf in-place and build argv_buf.
;
; Supports:
;
;   command arg1 arg2
;   command "argument with spaces"
;   command 'argument with spaces'
;
; Escapes:
;
;   \n  -> LF
;   \r  -> CR
;   \t  -> TAB
;   \\  -> \
;   \"  -> "
;   \'  -> '
;
; R8  = input/read pointer
; R9  = output/write pointer
; R10 = argc
; R11 = current character
; R12 = quote state
;
; R12:
;   0  = outside quotes
;   34 = inside double quotes
;   39 = inside single quotes
;
; Maximum 8 arguments.
; argv_buf = 8 pointers + NULL = 36 bytes.
; ---------------------------------------------------------------

parse_command:

0x0004428A       PUSH LR
0x0004428E       PUSH R8
0x00044292       PUSH R9
0x00044296       PUSH R10
0x0004429A       PUSH R11
0x0004429E       PUSH R12

0x000442A2       LI R8 input_buf
0x000442AA       LI R9 input_buf

0x000442B2       LI R10 0              ; argc
0x000442BA       LI R12 0              ; quote state


; ===============================================================
; Find beginning of next argument
; ===============================================================

parse_skip_spaces:

0x000442C2       LDB R11 [R8]

0x000442C6       CMP R11 0
0x000442CA       BEQ parse_done

0x000442D2       CMP R11 32            ; space
0x000442D6       BNE parse_token_start

0x000442DE       ADD R8 R8 1
0x000442E2       B parse_skip_spaces


; ===============================================================
; Start new argument
; ===============================================================

parse_token_start:

0x000442EA       CMP R10 MAX_ARGS
0x000442EE       BGE parse_done

    ; ------------------------------------------------------------
    ; argv[argc] = current output pointer
    ; ------------------------------------------------------------

0x000442F6       LI R7 argv_buf

0x000442FE       MOV R6 R10
0x00044302       shl R6 R6 2
0x00044306       ADD R7 R7 R6

0x0004430A       STW R9 [R7]

0x0004430E       ADD R10 R10 1

0x00044312       LI R12 0              ; outside quotes

0x0004431A       B parse_token_body


; ===============================================================
; Process characters of current argument
; ===============================================================

parse_token_body:

0x00044322       LDB R11 [R8]

    ; End of command
0x00044326       CMP R11 0
0x0004432A       BEQ parse_token_done


    ; ------------------------------------------------------------
    ; Outside quotes
    ; ------------------------------------------------------------

0x00044332       CMP R12 0
0x00044336       BNE parse_inside_quotes


    ; Space terminates argument
0x0004433E       CMP R11 32
0x00044342       BEQ parse_token_end


    ; Double quote
0x0004434A       CMP R11 34
0x0004434E       BEQ parse_start_double


    ; Single quote
0x00044356       CMP R11 39
0x0004435A       BEQ parse_start_single


    ; Backslash
0x00044362       CMP R11 92
0x00044366       BEQ parse_escape


    ; Normal character
0x0004436E       STB R11 [R9]

0x00044372       ADD R8 R8 1
0x00044376       ADD R9 R9 1

0x0004437A       B parse_token_body


; ===============================================================
; Start double quote
; ===============================================================

parse_start_double:

0x00044382       LI R12 34

0x0004438A       ADD R8 R8 1

0x0004438E       B parse_token_body


; ===============================================================
; Start single quote
; ===============================================================

parse_start_single:

0x00044396       LI R12 39

0x0004439E       ADD R8 R8 1

0x000443A2       B parse_token_body


; ===============================================================
; Inside quotes
; ===============================================================

parse_inside_quotes:

    ; Closing quote?
0x000443AA       CMP R11 R12
0x000443AE       BEQ parse_close_quote


    ; Backslash
0x000443B6       CMP R11 92
0x000443BA       BEQ parse_escape


    ; Normal character
0x000443C2       STB R11 [R9]

0x000443C6       ADD R8 R8 1
0x000443CA       ADD R9 R9 1

0x000443CE       B parse_token_body


; ===============================================================
; Close quote
; ===============================================================

parse_close_quote:

0x000443D6       LI R12 0

0x000443DE       ADD R8 R8 1

0x000443E2       B parse_token_body


; ===============================================================
; Escape sequence
;
; R8 points at '\'
; Move to character after it.
; ===============================================================

parse_escape:

0x000443EA       ADD R8 R8 1

0x000443EE       LDB R11 [R8]

    ; Backslash was last character
0x000443F2       CMP R11 0
0x000443F6       BEQ parse_token_done


    ; ------------------------------------------------------------
    ; \n
    ; ------------------------------------------------------------

0x000443FE       CMP R11 110           ; 'n'
0x00044402       BEQ parse_escape_n


    ; ------------------------------------------------------------
    ; \r
    ; ------------------------------------------------------------

0x0004440A       CMP R11 114           ; 'r'
0x0004440E       BEQ parse_escape_r


    ; ------------------------------------------------------------
    ; \t
    ; ------------------------------------------------------------

0x00044416       CMP R11 116           ; 't'
0x0004441A       BEQ parse_escape_t


    ; ------------------------------------------------------------
    ; \\
    ; ------------------------------------------------------------

0x00044422       CMP R11 92
0x00044426       BEQ parse_escape_backslash


    ; ------------------------------------------------------------
    ; \"
    ; ------------------------------------------------------------

0x0004442E       CMP R11 34
0x00044432       BEQ parse_escape_quote


    ; ------------------------------------------------------------
    ; \'
    ; ------------------------------------------------------------

0x0004443A       CMP R11 39
0x0004443E       BEQ parse_escape_single


    ; ------------------------------------------------------------
    ; Unknown escape
    ;
    ; \x -> x
    ; ------------------------------------------------------------

0x00044446       STB R11 [R9]

0x0004444A       ADD R8 R8 1
0x0004444E       ADD R9 R9 1

0x00044452       B parse_token_body


; ===============================================================
; Escape handlers
; ===============================================================

parse_escape_n:

0x0004445A       LI R11 10
0x00044462       B parse_escape_store


parse_escape_r:

0x0004446A       LI R11 13
0x00044472       B parse_escape_store


parse_escape_t:

0x0004447A       LI R11 9
0x00044482       B parse_escape_store


parse_escape_backslash:

0x0004448A       LI R11 92
0x00044492       B parse_escape_store


parse_escape_quote:

0x0004449A       LI R11 34
0x000444A2       B parse_escape_store


parse_escape_single:

0x000444AA       LI R11 39
0x000444B2       B parse_escape_store


; ===============================================================
; Store translated escape
; ===============================================================

parse_escape_store:

0x000444BA       STB R11 [R9]

0x000444BE       ADD R8 R8 1
0x000444C2       ADD R9 R9 1

0x000444C6       B parse_token_body


; ===============================================================
; End argument because of space
; ===============================================================

parse_token_end:

    ; terminate output string
0x000444CE       LI R11 0
0x000444D6       STB R11 [R9]

0x000444DA       ADD R9 R9 1
0x000444DE       ADD R8 R8 1

0x000444E2       B parse_skip_spaces


; ===============================================================
; End of input
; ===============================================================

parse_token_done:

    ; terminate current string
0x000444EA       LI R11 0
0x000444F2       STB R11 [R9]


; ===============================================================
; Finish argv[]
; ===============================================================

parse_done:

    ; R7 = argv_buf + argc * 4

0x000444F6       LI R7 argv_buf

0x000444FE       MOV R6 R10
0x00044502       SHL R6 R6 2
0x00044506       ADD R7 R7 R6

    ; argv[argc] = NULL

0x0004450A       LI R11 0
0x00044512       STW R11 [R7]


0x00044516       POP R12
0x0004451A       POP R11
0x0004451E       POP R10
0x00044522       POP R9
0x00044526       POP R8
0x0004452A       POP LR

0x0004452E       RET

; ---------------------------------------------------------------
; parse_command() – parse input_buf into argv_buf
; input and output:
;   input_buf: null-terminated string of command line
;   output: all needed for execve (input_buf = pathname, argv_buf = argv) ready
; ---------------------------------------------------------------

parse_command0:
0x00044532       PUSH LR
0x00044536       PUSH R8
0x0004453A       PUSH R9
0x0004453E       PUSH R10
0x00044542       PUSH R11

0x00044546       LI R8 input_buf
0x0004454E       LI R9 argv_buf
0x00044556       LI R10 0

parse_skip_spaces0:
0x0004455E       LDB R11 [R8]
0x00044562       CMP R11 32      ;" "
0x00044566       BNE parse_token_start
0x0004456E       LI R11 0        ;replace space with null so input_buf gets str.split(' ') into args strings
0x00044576       STB R11 [R8]
0x0004457A       ADD R8 R8 1
0x0004457E       B parse_skip_spaces0

parse_token_start0:
0x00044586       LDB R11 [R8]
0x0004458A       CMP R11 0
0x0004458E       BEQ parse_done
0x00044596       CMP R10 8       ;up to 8 args
0x0004459A       BGE parse_done

0x000445A2       STW R8 [R9]     ;store pointer to token in argv_buf (argv array for execve)
0x000445A6       ADD R9 R9 4
0x000445AA       ADD R10 R10 1   ;argc for execve

parse_token_body0:
0x000445AE       LDB R11 [R8]
0x000445B2       CMP R11 0
0x000445B6       BEQ parse_done
0x000445BE       CMP R11 32      ;" "
0x000445C2       BEQ parse_end_token
0x000445CA       ADD R8 R8 1
0x000445CE       B parse_token_body

parse_end_token:
0x000445D6       LI R11 0
0x000445DE       STB R11 [R8]    ; put null terminator at end of token
0x000445E2       ADD R8 R8 1     ; move to next char in input_buf
0x000445E6       B parse_skip_spaces

parse_done0:
0x000445EE       LI R11 0
0x000445F6       STW R11 [R9]    ; put null terminator at end of argv_buf (argv array for execve)
0x000445FA       POP R11         ; all needed for execve (input_buf = pathname, argv_buf = argv) ready
                    ;  and in format for execve
0x000445FE       POP R10
0x00044602       POP R9
0x00044606       POP R8
0x0004460A       POP LR
0x0004460E       RET

;---------------------------------------------------------------
; Data
;---------------------------------------------------------------
prompt:
    .ASCIIZ "$ \r"

quit_cmd:
    .ASCIIZ "quit"

exec_failed_msg:
    .ASCIIZ "EXECVE ERR\n"
fork_error_msg:
    .ASCIIZ "FORK ERR\n"
wait_error_msg:
    .ASCIIZ "WAIT ERR\n"

input_buf:
    .SPACE 128

argv_buf:
    .SPACE 128
; ================================================================
; End
; ================================================================
