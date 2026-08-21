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
0x00043698       PUSH LR
0x0004369C       PUSH R8
0x000436A0       PUSH R9
0x000436A4       PUSH R10
0x000436A8       PUSH R11
0x000436AC       PUSH R12

0x000436B0       MOV  R8  R1          ; Save destination

0x000436B4       MOV  R9  R2          ; Working value
0x000436B8       MOV  R11 R3          ; Base
0x000436BC       MOV  R12 R4          ; Sign flag
    ;MOV  R10 R5          ; Temp buffer size

    ; Allocate temp buffer (size passed in R5)
0x000436C0       SUB  SP SP R5
0x000436C4       MOV  R10 R1          ; Keep original pointer
0x000436C8       MOV  R6  SP          ; Temp buffer pointer
0x000436CC       push R5              ; save R5 for frame leave
0x000436D0       MOV  R7  R6          ; Save start of temp buffer

    ; Check for sign (if signed and negative)
0x000436D4       CMP  R12 1
0x000436D8       BNE  itoa_core_unsigned

0x000436E0       CMP  R9 0
0x000436E4       BGE  itoa_core_unsigned

    ; Negative number - add minus sign
0x000436EC       LI   R2 45     ;'-'
0x000436F4       STB  R2 [R8]
0x000436F8       ADD  R8 R8 1
0x000436FC       NOT  R9 R9
0x00043700       ADD  R9 R9 1
    ;NEG  R9              ; Make positive

itoa_core_unsigned:
    ; Special case: zero
0x00043704       CMP  R9 0
0x00043708       BNE  itoa_core_convert

0x00043710       LI   R2 48    ; '0'
0x00043718       STB  R2 [R8]
0x0004371C       ADD  R8 R8 1
0x00043720       LI   R2 0
0x00043728       STB  R2 [R8]
0x0004372C       B    itoa_core_finish

itoa_core_convert:
0x00043734       LI   R4 0            ; Digit counter

itoa_core_divloop:
0x0004373C       MOV  R5 R9
0x00043740       DIV  R6 R5 R11       ; R6 = quotient, R9 = remainder
0x00043744       MOD  R7 R9 R11       ; R7 = remainder

    ; Convert digit to ASCII based on base
0x00043748       CMP  R11 16
0x0004374C       BEQ  itoa_core_hex_digit

    ; Base 2 or 10: digit 0-9
0x00043754       ADD  R7 R7 48        ; '0' + digit
0x00043758       B    itoa_core_store

itoa_core_hex_digit:
    ; Base 16: digit 0-15
0x00043760       CMP  R7 9
0x00043764       BGT  itoa_core_hex_letter
0x0004376C       ADD  R7 R7 48        ; '0' + digit
0x00043770       B    itoa_core_store

itoa_core_hex_letter:
0x00043778       SUB  R7 R7 10
0x0004377C       ADD  R7 R7 65        ; 'A' + (digit-10)

itoa_core_store:
0x00043780       STB  R7 [R6]         ; Store in temp buffer
0x00043784       ADD  R6 R6 1
0x00043788       ADD  R4 R4 1         ; Increment digit count

0x0004378C       MOV  R9 R5           ; Quotient becomes new value
0x00043790       CMP  R9 0
0x00043794       BNE  itoa_core_divloop

    ; Point to last digit
0x0004379C       SUB  R6 R6 1

itoa_core_copy:
0x000437A0       CMP  R4 0
0x000437A4       BEQ  itoa_core_done

0x000437AC       LDB  R2 [R6]         ; Get digit from temp (reverse order)
0x000437B0       STB  R2 [R8]         ; Store in destination
0x000437B4       ADD  R8 R8 1
0x000437B8       SUB  R6 R6 1
0x000437BC       SUB  R4 R4 1
0x000437C0       B    itoa_core_copy

itoa_core_done:
0x000437C8       LI   R2 0
0x000437D0       STB  R2 [R8]         ; Null terminate

itoa_core_finish:
0x000437D4       POP  R5
    ; Clean up temp buffer
0x000437D8       ADD  SP SP R5

    ; Return original pointer
0x000437DC       MOV  R1 R10

0x000437E0       POP  R12
0x000437E4       POP  R11
0x000437E8       POP  R10
0x000437EC       POP  R9
0x000437F0       POP  R8
0x000437F4       POP  LR
0x000437F8       RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
0x000437FC       PUSH LR

    ; Max 11 digits + sign + null = 13 bytes
0x00043800       LI   R3 10           ; Base 10
0x00043808       LI   R4 1            ; Signed
0x00043810       LI   R5 13           ; Temp buffer size
0x00043818   CALL itoa_core

0x00043820       POP  LR
0x00043824       RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
0x00043828       PUSH LR

    ; Max 8 digits + null = 9 bytes
0x0004382C       LI   R3 16           ; Base 16
0x00043834       LI   R4 0            ; Unsigned (shows raw bits)
0x0004383C       LI   R5 9            ; Temp buffer size
0x00043844   CALL itoa_core

0x0004384C       POP  LR
0x00043850       RET


;---------------------------------------------------------
; itoa_oct - Octal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_oct:
0x00043854       PUSH LR

    ; Max 12 digits + null = 13 bytes
0x00043858       LI   R3 8            ; Base 8
0x00043860       LI   R4 0            ; Unsigned (shows raw bits)
0x00043868       LI   R5 13           ; Temp buffer size
0x00043870   CALL itoa_core

0x00043878       POP  LR
0x0004387C       RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
0x00043880       PUSH LR

    ; Max 32 bits + null = 33 bytes
0x00043884       LI   R3 2            ; Base 2
0x0004388C       LI   R4 0            ; Unsigned (shows raw bits)
0x00043894       LI   R5 33           ; Temp buffer size
0x0004389C   CALL itoa_core

0x000438A4       POP  LR
0x000438A8       RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
0x000438AC       PUSH LR

    ; Max 8 digits + sign + null = 10 bytes
0x000438B0       LI   R3 16           ; Base 16
0x000438B8       LI   R4 1            ; Signed (shows sign)
0x000438C0       LI   R5 10           ; Temp buffer size
0x000438C8   CALL itoa_core

0x000438D0       POP  LR
0x000438D4       RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
0x000438D8       PUSH LR

    ; Max 32 bits + sign + null = 34 bytes
0x000438DC       LI   R3 2            ; Base 2
0x000438E4       LI   R4 1            ; Signed (shows sign)
0x000438EC       LI   R5 34           ; Temp buffer size
0x000438F4   CALL itoa_core

0x000438FC       POP  LR
0x00043900       RET

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
0x00043904       PUSH LR
0x00043908       MOV R3 R1              ; Save original destination pointer
0x0004390C       MOV R4 R2              ; Save source pointer

strcpy_loop:
0x00043910       LDB R2 [R4]            ; Load byte from source
0x00043914       STB R2 [R1]            ; Store byte to destination

0x00043918       CMP R2 0               ; Check if it's null terminator
0x0004391C       BEQ strcpy_done        ; If zero, we're done

0x00043924       ADD R1 R1 1            ; Advance destination pointer
0x00043928       ADD R4 R4 1            ; Advance source pointer
0x0004392C       B strcpy_loop

strcpy_done:
0x00043934       MOV R1 R3              ; Return original destination pointer
0x00043938       POP LR
0x0004393C       RET


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
0x00043940       PUSH LR
0x00043944       PUSH R8
0x00043948       PUSH R9

0x0004394C       MOV R8 R1            ; Save path
    ; Open directory with read-only flags (same as your ls.asm)
0x00043950       MOV R1 R8
0x00043954       LI  R2 O_RDONLY
0x0004395C       SVC SYS_OPEN
0x00043960       MOV R9 R1           ;fd
0x00043964       CMP R1 0
0x00043968       BLT opendir_error

    ; Allocate DIR structure (small, just fd and offset)
0x00043970       PUSH R9                 ;save R9 jic
0x00043974       LI R1 DIR_SIZEOF
0x0004397C   CALL malloc
0x00043984       POP  R9

0x00043988       CMP R1 0
0x0004398C       BEQ opendir_error_close

0x00043994       MOV R8 R1            ; Save DIR*

    ; Initialize DIR structure
    ; R2 still has fd from open
0x00043998       STW R9 [R8 + DIR_FD]
0x0004399C       LI  R2 0
0x000439A4       STW R2 [R8 + DIR_OFFSET]

0x000439A8       MOV R1 R8            ; Return DIR*
0x000439AC       B opendir_done

opendir_error_close:
0x000439B4       MOV R1 R9            ; fd is in R9
0x000439B8       SVC SYS_CLOSE
0x000439BC       LI R1 0
0x000439C4       B opendir_done

opendir_error:
0x000439CC       LI R1 0

opendir_done:
0x000439D4       POP R9
0x000439D8       POP R8
0x000439DC       POP LR
0x000439E0       RET

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
0x000439E4       PUSH LR
0x000439E8       PUSH R8
0x000439EC       PUSH R9

0x000439F0       MOV R8 R1            ; DIR*
0x000439F4       MOV R9 R2            ; User's dirent buffer

    ; Check if DIR pointer is valid
0x000439F8       CMP R8 0
0x000439FC       BEQ readdir_error

    ; Read one dirent from directory fd using current offset
0x00043A04       LDW R1 [R8 + DIR_FD] ; fd

    ; Use the directory's offset - we need to implement lseek or use
    ; the fact that each read gets one dirent at a time from tarfs
0x00043A08       MOV R2 R9            ; user buffer
0x00043A0C       LI  R3 DIRENT_SIZEOF ; size of one dirent
0x00043A14       SVC SYS_READ
0x00043A18       CMP R1 0
0x00043A1C       BEQ readdir_end      ; EOF
0x00043A24       CMP R1 DIRENT_SIZEOF
0x00043A28       BNE readdir_error    ; Short read or error

    ; Entry read successfully
    ; Update the offset in DIR structure
0x00043A30       LDW R2 [R8 + DIR_OFFSET]
0x00043A34       ADD R2 R2 1
0x00043A38       STW R2 [R8 + DIR_OFFSET]

0x00043A3C       LI R1 1              ; Return success
0x00043A44       B readdir_done

readdir_error:
0x00043A4C       LI R1 -1
0x00043A54       B readdir_done

readdir_end:
0x00043A5C       LI R1 0

readdir_done:
0x00043A64       POP R9
0x00043A68       POP R8
0x00043A6C       POP LR
0x00043A70       RET

;------------------------------------------------------------------------------
; closedir - Close directory stream
;
; IN:  R1 = DIR*
; OUT: R1 = 0 on success, -1 on error
;------------------------------------------------------------------------------
closedir:
0x00043A74       PUSH LR
0x00043A78       PUSH R8

0x00043A7C       MOV R8 R1
0x00043A80       CMP R8 0
0x00043A84       BEQ closedir_error

    ; Close the directory fd
0x00043A8C       LDW R1 [R8 + DIR_FD]
0x00043A90       SVC SYS_CLOSE

    ; Free the DIR structure
0x00043A94       MOV R1 R8
0x00043A98   CALL free

0x00043AA0       LI R1 0
0x00043AA8       B closedir_done

closedir_error:
0x00043AB0       LI R1 -1

closedir_done:
0x00043AB8       POP R8
0x00043ABC       POP LR
0x00043AC0       RET

;------------------------------------------------------------------------------
; rewinddir - Reset directory stream to beginning
;
; IN:  R1 = DIR*
;------------------------------------------------------------------------------
rewinddir:
0x00043AC4       CMP R1 0
0x00043AC8       BEQ rewinddir_done

0x00043AD0       LI R2 0
0x00043AD8       STW R2 [R1 + DIR_OFFSET]

    ; Need to seek to beginning of directory
    ; For tarfs, this means closing and reopening, or using lseek
    ; Simple approach: close and reopen
0x00043ADC       PUSH LR
0x00043AE0       PUSH R8

0x00043AE4       MOV R8 R1
    ; Save the path - we don't have it stored, so this is tricky
    ; In a real implementation, store path in DIR structure

    ; For now, just reset offset and rely on readdir's behavior

0x00043AE8       POP R8
0x00043AEC       POP LR

rewinddir_done:
0x00043AF0       RET

;------------------------------------------------------------------------------
; dirfd - Get file descriptor from DIR*
;
; IN:  R1 = DIR*
; OUT: R1 = file descriptor, or -1 on error
;------------------------------------------------------------------------------
dirfd:
0x00043AF4       CMP R1 0
0x00043AF8       BEQ dirfd_error

0x00043B00       LDW R1 [R1 + DIR_FD]
0x00043B04       RET

dirfd_error:
0x00043B08       LI R1 -1
0x00043B10       RET

;------------------------------------------------------------------------------
; Helper: is_dir - Check if a path is a directory
;
; IN:  R1 = path
; OUT: R1 = 1 if directory, 0 if not, -1 on error
;------------------------------------------------------------------------------
is_dir:
0x00043B14       PUSH LR

    ; Try to open as directory
0x00043B18   CALL opendir
0x00043B20       CMP R1 0
0x00043B24       BEQ is_dir_not_dir

    ; It opened as a directory
0x00043B2C       MOV R2 R1            ; Save DIR*
0x00043B30       LI R1 1              ; Return true
0x00043B38   CALL closedir
0x00043B40       B is_dir_done

is_dir_not_dir:
0x00043B48       LI R1 0

is_dir_done:
0x00043B50       POP LR
0x00043B54       RET

;------------------------------------------------------------------------------
; Example usage function - list directory contents (like ls)
; This demonstrates how to use opendir/readdir/closedir
;------------------------------------------------------------------------------
list_directory:
0x00043B58       PUSH LR
0x00043B5C       PUSH R8
0x00043B60       PUSH R9

0x00043B64       MOV R8 R1            ; path

    ; Allocate dirent on stack
0x00043B68       SUB SP SP DIRENT_SIZEOF
0x00043B6C       MOV R9 SP

    ; Open directory
0x00043B70       MOV R1 R8
0x00043B74   CALL opendir
0x00043B7C       CMP R1 0
0x00043B80       BEQ list_dir_error

0x00043B88       MOV R8 R1            ; DIR*

list_dir_loop:
0x00043B8C       MOV R1 R8
0x00043B90       MOV R2 R9
0x00043B94   CALL readdir
0x00043B9C       CMP R1 0
0x00043BA0       BEQ list_dir_close
0x00043BA8       LI  R2 -1
0x00043BB0       CMP R1 R2
0x00043BB4       BEQ list_dir_error

    ; Print the name
0x00043BBC       ADD R1 R9 DIRENT_NAME
0x00043BC0   CALL puts

    ; If it's a directory, print '/'
0x00043BC8       LDW R2 [R9 + DIRENT_TYPE]
0x00043BCC       CMP R2 DT_DIR
0x00043BD0       BNE list_dir_not_dir

0x00043BD8       LI R1 slash_char
0x00043BE0   CALL putchar

list_dir_not_dir:
0x00043BE8       LI R1 newline_char
0x00043BF0   CALL putchar

0x00043BF8       B list_dir_loop

list_dir_close:
0x00043C00       MOV R1 R8
0x00043C04   CALL closedir
0x00043C0C       LI R1 0
0x00043C14       B list_dir_done

list_dir_error:
0x00043C1C       LI R1 -1

list_dir_done:
0x00043C24       ADD SP SP DIRENT_SIZEOF
0x00043C28       POP R9
0x00043C2C       POP R8
0x00043C30       POP LR
0x00043C34       RET

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
0x00043C40       PUSH LR
0x00043C44       PUSH R8
0x00043C48       PUSH R9
0x00043C4C       PUSH R10
0x00043C50       PUSH R11
0x00043C54       PUSH R12

0x00043C58       SUB SP SP 80              ; local frame: 44 + 34 + padding

    ; Save R2..R12 to local array
0x00043C5C       STW R2 [SP + 0]
0x00043C60       STW R3 [SP + 4]
0x00043C64       STW R4 [SP + 8]
0x00043C68       STW R5 [SP + 12]
0x00043C6C       STW R6 [SP + 16]
0x00043C70       STW R7 [SP + 20]
0x00043C74       STW R8 [SP + 24]
0x00043C78       STW R9 [SP + 28]
0x00043C7C       STW R10 [SP + 32]
0x00043C80       STW R11 [SP + 36]
0x00043C84       STW R12 [SP + 40]

0x00043C88       MOV R8 R1                 ; format pointer
0x00043C8C       LI  R9 0                  ; argument index

0x00043C94       MOV R10 SP                ; base of saved registers
0x00043C98       ADD R11 SP 44             ; conversion buffer

printf_loop:
0x00043C9C       LDB R1 [R8]     ;read fmt string char
0x00043CA0       CMP R1 0
0x00043CA4       BEQ printf_done

0x00043CAC       CMP R1 37   ;check for '%'
0x00043CB0       BNE printf_normal_char

0x00043CB8       ADD R8 R8 1 ; its a '%', move to next char for specifier
0x00043CBC       LDB R2 [R8]
0x00043CC0       CMP R2 0
0x00043CC4       BEQ printf_done

0x00043CCC       CMP R2 37   ; check for '%%'
0x00043CD0       BEQ printf_percent
0x00043CD8       CMP R2 115  ; check for '%s'
0x00043CDC       BEQ printf_string
0x00043CE4       CMP R2 100  ;check for '%d'
0x00043CE8       BEQ printf_int
0x00043CF0       CMP R2 105  ;check for '%i'
0x00043CF4       BEQ printf_int
0x00043CFC       CMP R2 120  ;check for '%x'
0x00043D00       BEQ printf_hex
0x00043D08       CMP R2 99   ;check for '%c'
0x00043D0C       BEQ printf_char
0x00043D14       CMP R2 98   ;check for '%b'
0x00043D18       BEQ printf_bin
0x00043D20       CMP R2 111  ;check for '%o'
0x00043D24       BEQ printf_oct

    ; unknown specifier
0x00043D2C       LI  R1 37   ;unknown specifier, print '%'
0x00043D34   CALL putchar
0x00043D3C       MOV R1 R2   ; print the unknown specifier char
0x00043D40   CALL putchar
0x00043D48       B   printf_continue

printf_normal_char:
0x00043D50   CALL putchar
0x00043D58       B   printf_continue

printf_percent:
0x00043D60       LI  R1 37   ;print '%'
0x00043D68   CALL putchar
0x00043D70       B   printf_continue

;------------------------------------------------------------------------------
; Argument fetch helpers (same as before)
;------------------------------------------------------------------------------
_fetch_arg_r1:
0x00043D78       PUSH LR
0x00043D7C       PUSH R3
0x00043D80   CALL _get_arg_address
0x00043D88       LDW R1 [R3]
0x00043D8C       POP R3
0x00043D90       POP LR
0x00043D94       RET

_fetch_arg_r2:
0x00043D98       PUSH LR
0x00043D9C       PUSH R3
0x00043DA0   CALL _get_arg_address
0x00043DA8       LDW R2 [R3]
0x00043DAC       POP R3
0x00043DB0       POP LR
0x00043DB4       RET

_get_arg_address:   ; fetch the address of the next argument based on R9 (arg index)
0x00043DB8       CMP R9 11       ; if arg index >= 11, it's on the stack
0x00043DBC       BLT _arg_in_regs
0x00043DC4       SUB R3 R9 11    ; R3 = number of extra args on stack
0x00043DC8       LI  R4 4
0x00043DD0       MUL R3 R3 R4
0x00043DD4       ADD R3 SP R3    ; R3 = address of first extra arg on stack (not sure if this is correct)
0x00043DD8       ADD R3 R3 104   ; offset to caller's first extra arg 104
                    ;is the size of the local frame (80) + saved registers (44)
0x00043DDC       RET

_arg_in_regs:       ; fetch argument from R2..R12 based on R9
0x00043DE0       LI  R4 4
0x00043DE8       MUL R3 R9 R4    ; R9 = arg index, (R3 = offset in bytes)
0x00043DEC       ADD R3 R10 R3   ; R3 = address of saved register in local array, R10 = base of saved registers
0x00043DF0       RET

;------------------------------------------------------------------------------
; Specifier handlers
;------------------------------------------------------------------------------
printf_string:
0x00043DF4   CALL _fetch_arg_r1
0x00043DFC       ADD R9 R9 1
0x00043E00   CALL _print_string
0x00043E08       B   printf_continue

printf_int:
0x00043E10   CALL _fetch_arg_r2
0x00043E18       ADD R9 R9 1
0x00043E1C       MOV R1 R11          ; r11 is the conversion buffer (on stack)
0x00043E20   CALL _print_number
0x00043E28       B   printf_continue

printf_hex:
0x00043E30   CALL _fetch_arg_r2
0x00043E38       ADD R9 R9 1
0x00043E3C       MOV R1 R11          ; r11 is the conversion buffer (on stack) and so on for other conversions helpers..
0x00043E40   CALL _print_hex
0x00043E48       B   printf_continue

printf_char:
0x00043E50   CALL _fetch_arg_r1
0x00043E58       ADD R9 R9 1
0x00043E5C   CALL putchar
0x00043E64       B   printf_continue

printf_bin:
0x00043E6C   CALL _fetch_arg_r2
0x00043E74       ADD R9 R9 1
0x00043E78       MOV R1 R11
0x00043E7C   CALL _print_bin
0x00043E84       B   printf_continue

printf_oct:
0x00043E8C   CALL _fetch_arg_r2
0x00043E94       ADD R9 R9 1
0x00043E98       MOV R1 R11
0x00043E9C   CALL _print_oct
0x00043EA4       B   printf_continue

printf_continue:    ;to continue processing format string
0x00043EAC       ADD R8 R8 1
0x00043EB0       B   printf_loop

printf_done:
0x00043EB8       ADD SP SP 80
0x00043EBC       POP R12
0x00043EC0       POP R11
0x00043EC4       POP R10
0x00043EC8       POP R9
0x00043ECC       POP R8
0x00043ED0       POP LR
0x00043ED4       RET

;------------------------------------------------------------------------------
; _print_string - Write a null‑terminated string to stdout (no newline)
;
; Uses the libc `write` wrapper (fd, buffer, len) instead of direct SVC.
;
; IN:  R1 = pointer to string
; OUT: none
;------------------------------------------------------------------------------
_print_string:
0x00043ED8       PUSH LR
0x00043EDC       PUSH R8
0x00043EE0       PUSH R9
0x00043EE4       MOV R8 R1
0x00043EE8   CALL strlen
0x00043EF0       MOV R9 R1
0x00043EF4       LI  R1 STDOUT_FD
0x00043EFC       MOV R2 R8
0x00043F00       MOV R3 R9
0x00043F04   CALL write
0x00043F0C       POP R9
0x00043F10       POP R8
0x00043F14       POP LR
0x00043F18       RET


;------------------------------------------------------------------------------
; _print_number - Format and print a signed integer (uses itoa_dec)
;
; IN:  R1 = destination buffer (must be ≥13 bytes)
;      R2 = signed integer
; OUT: none
;------------------------------------------------------------------------------
_print_number:
0x00043F1C       PUSH LR
0x00043F20   CALL itoa_dec
0x00043F28       MOV R1 R1                 ; R1 still points to buffer start
0x00043F2C   CALL _print_string
0x00043F34       POP LR
0x00043F38       RET

;------------------------------------------------------------------------------
; _print_hex - Format and print an unsigned integer in hex (uses itoa_hex)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_hex:
0x00043F3C       PUSH LR
0x00043F40   CALL itoa_hex
0x00043F48       MOV R1 R1
0x00043F4C   CALL _print_string
0x00043F54       POP LR
0x00043F58       RET

;------------------------------------------------------------------------------
; _print_hex - Format and print an unsigned integer in hex (uses itoa_hex)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_bin:
0x00043F5C       PUSH LR
0x00043F60   CALL itoa_bin
0x00043F68       MOV R1 R1
0x00043F6C   CALL _print_string
0x00043F74       POP LR
0x00043F78       RET

;------------------------------------------------------------------------------
; _print_oct - Format and print an unsigned integer in octal (uses itoa_oct)
;
; IN:  R1 = destination buffer (must be ≥9 bytes)
;      R2 = unsigned integer
; OUT: none
;------------------------------------------------------------------------------
_print_oct:
0x00043F7C       PUSH LR
0x00043F80   CALL itoa_oct
0x00043F88       MOV R1 R1
0x00043F8C   CALL _print_string
0x00043F94       POP LR
0x00043F98       RET

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
0x00043FA2       PUSH LR
0x00043FA6       PUSH R8
0x00043FAA       PUSH R9
0x00043FAE       PUSH R10

0x00043FB2       MOV R8 R1          ; R8 = string
0x00043FB6       LI  R9 0           ; R9 = result
0x00043FBE       LI  R10 0          ; R10 = negative flag

    ; Check '-'
0x00043FC6       LDB R2 [R8]
0x00043FCA       CMP R2 45          ; '-'
0x00043FCE       BNE atoi_loop
0x00043FD6       LI R10 1
0x00043FDE       ADD R8 R8 1
atoi_loop:
0x00043FE2       LDB R2 [R8]
    ; end of string
0x00043FE6       CMP R2 0
0x00043FEA       BEQ atoi_done
    ; only accept '0'..'9'
0x00043FF2       CMP R2 48       ; '0'
0x00043FF6       BLT atoi_done
0x00043FFE       CMP R2 57       ; '9'
0x00044002       BGT atoi_done

    ; digit = char - '0'
0x0004400A       SUB R2 R2 48

    ; result = result * 10 + digit
0x0004400E       LI  R3 10
0x00044016       MUL R9 R9 R3
0x0004401A       ADD R9 R9 R2
0x0004401E       ADD R8 R8 1
0x00044022       B atoi_loop
atoi_done:
0x0004402A       CMP R10 1
0x0004402E       BNE atoi_positive
    ; negate NEG =)
0x00044036       NOT R9 R9
0x0004403A       ADD R9 R9 1
atoi_positive:
0x0004403E       MOV R1 R9
0x00044042       POP R10
0x00044046       POP R9
0x0004404A       POP R8
0x0004404E       POP LR
0x00044052       RET

.EQU STDIN_FD,  0

;---------------------------------------------------------------
; main() – shell loop
;---------------------------------------------------------------
main:
0x00044056       PUSH LR

shell_loop:
    ; Print prompt
0x0004405A       LI R1 STDOUT_FD
0x00044062       LI R2 prompt
0x0004406A       LI R3 2
0x00044072   CALL write
    ; Read command
0x0004407A       LI R1 STDIN_FD
0x00044082       LI R2 input_buf
0x0004408A       LI R3 127
0x00044092   CALL read
0x0004409A       CMP R1 0
0x0004409E       BLE exit_shell
0x000440A6       MOV R4 R1           ; R4 = bytes read

    ; ---- Normalize line editing characters before parsing ----
    ; Treat BS/DEL as a backspace in the current command buffer.
0x000440AA       LI R8 input_buf
0x000440B2       LI R9 input_buf
0x000440BA       LI R10 0            ; source index

normalize_input_loop:
0x000440C2       CMP R10 R4
0x000440C6       BGE normalize_input_done

0x000440CE       ADD R5 R8 R10
0x000440D2       LDB R6 [R5]

0x000440D6       CMP R6 10            ; LF
0x000440DA       BEQ normalize_input_next
0x000440E2       CMP R6 13            ; CR
0x000440E6       BEQ normalize_input_next
0x000440EE       CMP R6 8             ; BS
0x000440F2       BEQ normalize_input_backspace
0x000440FA       CMP R6 127           ; DEL
0x000440FE       BEQ normalize_input_backspace

0x00044106       STB R6 [R9]
0x0004410A       ADD R9 R9 1
0x0004410E       B normalize_input_next

normalize_input_backspace:
0x00044116       CMP R9 R8
0x0004411A       BLE normalize_input_next
0x00044122       SUB R9 R9 1
0x00044126       B normalize_input_next

normalize_input_next:
0x0004412E       ADD R10 R10 1
0x00044132       B normalize_input_loop

normalize_input_done:
0x0004413A       LI R6 0
0x00044142       STB R6 [R9]

    ; Skip empty lines
0x00044146       LI R7 input_buf
0x0004414E       LDB R6 [R7]
0x00044152       CMP R6 0
0x00044156       BEQ shell_loop

0x0004415E   CALL parse_command

0x00044166       LI R1 input_buf
0x0004416E       LI R2 quit_cmd
0x00044176   CALL strcmp
0x0004417E       CMP R1 1
0x00044182       BEQ exit_shell  ;if type "quit" exit shell

    ; ---- Fork ----
0x0004418A   CALL fork
0x00044192       CMP R1 0
0x00044196       BEQ child_process
0x0004419E       BLT fork_error

    ;Debug 2
    ;POP LR
    ;RET

    ; ---- Parent: wait for child ----
0x000441A6       LI R1 -1
0x000441AE       LI R2 0
0x000441B6   CALL waitpid
0x000441BE       CMP R1 0
0x000441C2       BLT wait_error

0x000441CA       B shell_loop

    ; ---- Child: execute command ----
child_process:
    ; pathname = input_buf (copied early by kernel, before data page zeroed)
    ; argv = argv_buf
0x000441D2       LI R1 input_buf
0x000441DA       LI R2 argv_buf
0x000441E2       LI R3 0
0x000441EA   CALL execve
0x000441F2       LI R1 exec_failed_msg
0x000441FA   CALL puts

0x00044202       POP LR
0x00044206       RET

fork_error:
0x0004420A       LI R1 fork_error_msg
0x00044212   CALL puts
0x0004421A       B shell_loop

wait_error:
0x00044222       LI R1 wait_error_msg
0x0004422A   CALL puts
0x00044232       B shell_loop

exit_shell:
0x0004423A       POP LR
0x0004423E       RET

; ---------------------------------------------------------------
; parse_command() – parse input_buf into argv_buf
; input and output:
;   input_buf: null-terminated string of command line
;   output: all needed for execve (input_buf = pathname, argv_buf = argv) ready
; ---------------------------------------------------------------

parse_command:
0x00044242       PUSH LR
0x00044246       PUSH R8
0x0004424A       PUSH R9
0x0004424E       PUSH R10
0x00044252       PUSH R11

0x00044256       LI R8 input_buf
0x0004425E       LI R9 argv_buf
0x00044266       LI R10 0

parse_skip_spaces:
0x0004426E       LDB R11 [R8]
0x00044272       CMP R11 32      ;" "
0x00044276       BNE parse_token_start
0x0004427E       LI R11 0        ;replace space with null so input_buf gets str.split(' ') into args strings
0x00044286       STB R11 [R8]
0x0004428A       ADD R8 R8 1
0x0004428E       B parse_skip_spaces

parse_token_start:
0x00044296       LDB R11 [R8]
0x0004429A       CMP R11 0
0x0004429E       BEQ parse_done
0x000442A6       CMP R10 8       ;up to 8 args
0x000442AA       BGE parse_done

0x000442B2       STW R8 [R9]     ;store pointer to token in argv_buf (argv array for execve)
0x000442B6       ADD R9 R9 4
0x000442BA       ADD R10 R10 1   ;argc for execve

parse_token_body:
0x000442BE       LDB R11 [R8]
0x000442C2       CMP R11 0
0x000442C6       BEQ parse_done
0x000442CE       CMP R11 32      ;" "
0x000442D2       BEQ parse_end_token
0x000442DA       ADD R8 R8 1
0x000442DE       B parse_token_body

parse_end_token:
0x000442E6       LI R11 0
0x000442EE       STB R11 [R8]    ; put null terminator at end of token
0x000442F2       ADD R8 R8 1     ; move to next char in input_buf
0x000442F6       B parse_skip_spaces

parse_done:
0x000442FE       LI R11 0
0x00044306       STW R11 [R9]    ; put null terminator at end of argv_buf (argv array for execve)
0x0004430A       POP R11         ; all needed for execve (input_buf = pathname, argv_buf = argv) ready
                    ;  and in format for execve
0x0004430E       POP R10
0x00044312       POP R9
0x00044316       POP R8
0x0004431A       POP LR
0x0004431E       RET

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
    .SPACE 36
; ================================================================
; End
; ================================================================
