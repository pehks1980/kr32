.org 0x00043000
;==============================================================================
; ls - List directory contents using opendir/readdir/closedir wrappers
;==============================================================================
; Simple ls implementation that reads each directory specified on the command
; line and prints the contents (file/dir names) to stdout.
; If a filename is a directory, it appends a '/' to the name.
;==============================================================================

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
0x00043688       PUSH LR
0x0004368C       PUSH R8
0x00043690       PUSH R9
0x00043694       PUSH R10
0x00043698       PUSH R11
0x0004369C       PUSH R12

0x000436A0       MOV  R8  R1          ; Save destination

0x000436A4       MOV  R9  R2          ; Working value
0x000436A8       MOV  R11 R3          ; Base
0x000436AC       MOV  R12 R4          ; Sign flag
    ;MOV  R10 R5          ; Temp buffer size

    ; Allocate temp buffer (size passed in R5)
0x000436B0       SUB  SP SP R5
0x000436B4       MOV  R10 R1          ; Keep original pointer
0x000436B8       MOV  R6  SP          ; Temp buffer pointer
0x000436BC       push R5              ; save R5 for frame leave
0x000436C0       MOV  R7  R6          ; Save start of temp buffer

    ; Check for sign (if signed and negative)
0x000436C4       CMP  R12 1
0x000436C8       BNE  itoa_core_unsigned

0x000436D0       CMP  R9 0
0x000436D4       BGE  itoa_core_unsigned

    ; Negative number - add minus sign
0x000436DC       LI   R2 45     ;'-'
0x000436E4       STB  R2 [R8]
0x000436E8       ADD  R8 R8 1
0x000436EC       NOT  R9 R9
0x000436F0       ADD  R9 R9 1
    ;NEG  R9              ; Make positive

itoa_core_unsigned:
    ; Special case: zero
0x000436F4       CMP  R9 0
0x000436F8       BNE  itoa_core_convert

0x00043700       LI   R2 48    ; '0'
0x00043708       STB  R2 [R8]
0x0004370C       ADD  R8 R8 1
0x00043710       LI   R2 0
0x00043718       STB  R2 [R8]
0x0004371C       B    itoa_core_finish

itoa_core_convert:
0x00043724       LI   R4 0            ; Digit counter

itoa_core_divloop:
0x0004372C       MOV  R5 R9
0x00043730       DIV  R6 R5 R11       ; R6 = quotient, R9 = remainder
0x00043734       MOD  R7 R9 R11       ; R7 = remainder

    ; Convert digit to ASCII based on base
0x00043738       CMP  R11 16
0x0004373C       BEQ  itoa_core_hex_digit

    ; Base 2 or 10: digit 0-9
0x00043744       ADD  R7 R7 48        ; '0' + digit
0x00043748       B    itoa_core_store

itoa_core_hex_digit:
    ; Base 16: digit 0-15
0x00043750       CMP  R7 9
0x00043754       BGT  itoa_core_hex_letter
0x0004375C       ADD  R7 R7 48        ; '0' + digit
0x00043760       B    itoa_core_store

itoa_core_hex_letter:
0x00043768       SUB  R7 R7 10
0x0004376C       ADD  R7 R7 65        ; 'A' + (digit-10)

itoa_core_store:
0x00043770       STB  R7 [R6]         ; Store in temp buffer
0x00043774       ADD  R6 R6 1
0x00043778       ADD  R4 R4 1         ; Increment digit count

0x0004377C       MOV  R9 R5           ; Quotient becomes new value
0x00043780       CMP  R9 0
0x00043784       BNE  itoa_core_divloop

    ; Point to last digit
0x0004378C       SUB  R6 R6 1

itoa_core_copy:
0x00043790       CMP  R4 0
0x00043794       BEQ  itoa_core_done

0x0004379C       LDB  R2 [R6]         ; Get digit from temp (reverse order)
0x000437A0       STB  R2 [R8]         ; Store in destination
0x000437A4       ADD  R8 R8 1
0x000437A8       SUB  R6 R6 1
0x000437AC       SUB  R4 R4 1
0x000437B0       B    itoa_core_copy

itoa_core_done:
0x000437B8       LI   R2 0
0x000437C0       STB  R2 [R8]         ; Null terminate

itoa_core_finish:
0x000437C4       POP  R5
    ; Clean up temp buffer
0x000437C8       ADD  SP SP R5

    ; Return original pointer
0x000437CC       MOV  R1 R10

0x000437D0       POP  R12
0x000437D4       POP  R11
0x000437D8       POP  R10
0x000437DC       POP  R9
0x000437E0       POP  R8
0x000437E4       POP  LR
0x000437E8       RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
0x000437EC       PUSH LR

    ; Max 11 digits + sign + null = 13 bytes
0x000437F0       LI   R3 10           ; Base 10
0x000437F8       LI   R4 1            ; Signed
0x00043800       LI   R5 13           ; Temp buffer size
0x00043808   CALL itoa_core

0x00043810       POP  LR
0x00043814       RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
0x00043818       PUSH LR

    ; Max 8 digits + null = 9 bytes
0x0004381C       LI   R3 16           ; Base 16
0x00043824       LI   R4 0            ; Unsigned (shows raw bits)
0x0004382C       LI   R5 9            ; Temp buffer size
0x00043834   CALL itoa_core

0x0004383C       POP  LR
0x00043840       RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
0x00043844       PUSH LR

    ; Max 32 bits + null = 33 bytes
0x00043848       LI   R3 2            ; Base 2
0x00043850       LI   R4 0            ; Unsigned (shows raw bits)
0x00043858       LI   R5 33           ; Temp buffer size
0x00043860   CALL itoa_core

0x00043868       POP  LR
0x0004386C       RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
0x00043870       PUSH LR

    ; Max 8 digits + sign + null = 10 bytes
0x00043874       LI   R3 16           ; Base 16
0x0004387C       LI   R4 1            ; Signed (shows sign)
0x00043884       LI   R5 10           ; Temp buffer size
0x0004388C   CALL itoa_core

0x00043894       POP  LR
0x00043898       RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
0x0004389C       PUSH LR

    ; Max 32 bits + sign + null = 34 bytes
0x000438A0       LI   R3 2            ; Base 2
0x000438A8       LI   R4 1            ; Signed (shows sign)
0x000438B0       LI   R5 34           ; Temp buffer size
0x000438B8   CALL itoa_core

0x000438C0       POP  LR
0x000438C4       RET

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
0x000438C8       PUSH LR
0x000438CC       MOV R3 R1              ; Save original destination pointer
0x000438D0       MOV R4 R2              ; Save source pointer

strcpy_loop:
0x000438D4       LDB R2 [R4]            ; Load byte from source
0x000438D8       STB R2 [R1]            ; Store byte to destination

0x000438DC       CMP R2 0               ; Check if it's null terminator
0x000438E0       BEQ strcpy_done        ; If zero, we're done

0x000438E8       ADD R1 R1 1            ; Advance destination pointer
0x000438EC       ADD R4 R4 1            ; Advance source pointer
0x000438F0       B strcpy_loop

strcpy_done:
0x000438F8       MOV R1 R3              ; Return original destination pointer
0x000438FC       POP LR
0x00043900       RET


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
0x00043904       PUSH LR
0x00043908       PUSH R8
0x0004390C       PUSH R9

0x00043910       MOV R8 R1            ; Save path
    ; Open directory with read-only flags (same as your ls.asm)
0x00043914       MOV R1 R8
0x00043918       LI  R2 O_RDONLY
0x00043920       SVC SYS_OPEN
0x00043924       MOV R9 R1           ;fd
0x00043928       CMP R1 0
0x0004392C       BLT opendir_error

    ; Allocate DIR structure (small, just fd and offset)
0x00043934       PUSH R9                 ;save R9 jic
0x00043938       LI R1 DIR_SIZEOF
0x00043940   CALL malloc
0x00043948       POP  R9

0x0004394C       CMP R1 0
0x00043950       BEQ opendir_error_close

0x00043958       MOV R8 R1            ; Save DIR*

    ; Initialize DIR structure
    ; R2 still has fd from open
0x0004395C       STW R9 [R8 + DIR_FD]
0x00043960       LI  R2 0
0x00043968       STW R2 [R8 + DIR_OFFSET]

0x0004396C       MOV R1 R8            ; Return DIR*
0x00043970       B opendir_done

opendir_error_close:
0x00043978       MOV R1 R9            ; fd is in R9
0x0004397C       SVC SYS_CLOSE
0x00043980       LI R1 0
0x00043988       B opendir_done

opendir_error:
0x00043990       LI R1 0

opendir_done:
0x00043998       POP R9
0x0004399C       POP R8
0x000439A0       POP LR
0x000439A4       RET

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
0x000439A8       PUSH LR
0x000439AC       PUSH R8
0x000439B0       PUSH R9

0x000439B4       MOV R8 R1            ; DIR*
0x000439B8       MOV R9 R2            ; User's dirent buffer

    ; Check if DIR pointer is valid
0x000439BC       CMP R8 0
0x000439C0       BEQ readdir_error

    ; Read one dirent from directory fd using current offset
0x000439C8       LDW R1 [R8 + DIR_FD] ; fd

    ; Use the directory's offset - we need to implement lseek or use
    ; the fact that each read gets one dirent at a time from tarfs
0x000439CC       MOV R2 R9            ; user buffer
0x000439D0       LI  R3 DIRENT_SIZEOF ; size of one dirent
0x000439D8       SVC SYS_READ
0x000439DC       CMP R1 0
0x000439E0       BEQ readdir_end      ; EOF
0x000439E8       CMP R1 DIRENT_SIZEOF
0x000439EC       BNE readdir_error    ; Short read or error

    ; Entry read successfully
    ; Update the offset in DIR structure
0x000439F4       LDW R2 [R8 + DIR_OFFSET]
0x000439F8       ADD R2 R2 1
0x000439FC       STW R2 [R8 + DIR_OFFSET]

0x00043A00       LI R1 1              ; Return success
0x00043A08       B readdir_done

readdir_error:
0x00043A10       LI R1 -1
0x00043A18       B readdir_done

readdir_end:
0x00043A20       LI R1 0

readdir_done:
0x00043A28       POP R9
0x00043A2C       POP R8
0x00043A30       POP LR
0x00043A34       RET

;------------------------------------------------------------------------------
; closedir - Close directory stream
;
; IN:  R1 = DIR*
; OUT: R1 = 0 on success, -1 on error
;------------------------------------------------------------------------------
closedir:
0x00043A38       PUSH LR
0x00043A3C       PUSH R8

0x00043A40       MOV R8 R1
0x00043A44       CMP R8 0
0x00043A48       BEQ closedir_error

    ; Close the directory fd
0x00043A50       LDW R1 [R8 + DIR_FD]
0x00043A54       SVC SYS_CLOSE

    ; Free the DIR structure
0x00043A58       MOV R1 R8
0x00043A5C   CALL free

0x00043A64       LI R1 0
0x00043A6C       B closedir_done

closedir_error:
0x00043A74       LI R1 -1

closedir_done:
0x00043A7C       POP R8
0x00043A80       POP LR
0x00043A84       RET

;------------------------------------------------------------------------------
; rewinddir - Reset directory stream to beginning
;
; IN:  R1 = DIR*
;------------------------------------------------------------------------------
rewinddir:
0x00043A88       CMP R1 0
0x00043A8C       BEQ rewinddir_done

0x00043A94       LI R2 0
0x00043A9C       STW R2 [R1 + DIR_OFFSET]

    ; Need to seek to beginning of directory
    ; For tarfs, this means closing and reopening, or using lseek
    ; Simple approach: close and reopen
0x00043AA0       PUSH LR
0x00043AA4       PUSH R8

0x00043AA8       MOV R8 R1
    ; Save the path - we don't have it stored, so this is tricky
    ; In a real implementation, store path in DIR structure

    ; For now, just reset offset and rely on readdir's behavior

0x00043AAC       POP R8
0x00043AB0       POP LR

rewinddir_done:
0x00043AB4       RET

;------------------------------------------------------------------------------
; dirfd - Get file descriptor from DIR*
;
; IN:  R1 = DIR*
; OUT: R1 = file descriptor, or -1 on error
;------------------------------------------------------------------------------
dirfd:
0x00043AB8       CMP R1 0
0x00043ABC       BEQ dirfd_error

0x00043AC4       LDW R1 [R1 + DIR_FD]
0x00043AC8       RET

dirfd_error:
0x00043ACC       LI R1 -1
0x00043AD4       RET

;------------------------------------------------------------------------------
; Helper: is_dir - Check if a path is a directory
;
; IN:  R1 = path
; OUT: R1 = 1 if directory, 0 if not, -1 on error
;------------------------------------------------------------------------------
is_dir:
0x00043AD8       PUSH LR

    ; Try to open as directory
0x00043ADC   CALL opendir
0x00043AE4       CMP R1 0
0x00043AE8       BEQ is_dir_not_dir

    ; It opened as a directory
0x00043AF0       MOV R2 R1            ; Save DIR*
0x00043AF4       LI R1 1              ; Return true
0x00043AFC   CALL closedir
0x00043B04       B is_dir_done

is_dir_not_dir:
0x00043B0C       LI R1 0

is_dir_done:
0x00043B14       POP LR
0x00043B18       RET

;------------------------------------------------------------------------------
; Example usage function - list directory contents (like ls)
; This demonstrates how to use opendir/readdir/closedir
;------------------------------------------------------------------------------
list_directory:
0x00043B1C       PUSH LR
0x00043B20       PUSH R8
0x00043B24       PUSH R9

0x00043B28       MOV R8 R1            ; path

    ; Allocate dirent on stack
0x00043B2C       SUB SP SP DIRENT_SIZEOF
0x00043B30       MOV R9 SP

    ; Open directory
0x00043B34       MOV R1 R8
0x00043B38   CALL opendir
0x00043B40       CMP R1 0
0x00043B44       BEQ list_dir_error

0x00043B4C       MOV R8 R1            ; DIR*

list_dir_loop:
0x00043B50       MOV R1 R8
0x00043B54       MOV R2 R9
0x00043B58   CALL readdir
0x00043B60       CMP R1 0
0x00043B64       BEQ list_dir_close
0x00043B6C       LI  R2 -1
0x00043B74       CMP R1 R2
0x00043B78       BEQ list_dir_error

    ; Print the name
0x00043B80       ADD R1 R9 DIRENT_NAME
0x00043B84   CALL puts

    ; If it's a directory, print '/'
0x00043B8C       LDW R2 [R9 + DIRENT_TYPE]
0x00043B90       CMP R2 DT_DIR
0x00043B94       BNE list_dir_not_dir

0x00043B9C       LI R1 slash_char
0x00043BA4   CALL putchar

list_dir_not_dir:
0x00043BAC       LI R1 newline_char
0x00043BB4   CALL putchar

0x00043BBC       B list_dir_loop

list_dir_close:
0x00043BC4       MOV R1 R8
0x00043BC8   CALL closedir
0x00043BD0       LI R1 0
0x00043BD8       B list_dir_done

list_dir_error:
0x00043BE0       LI R1 -1

list_dir_done:
0x00043BE8       ADD SP SP DIRENT_SIZEOF
0x00043BEC       POP R9
0x00043BF0       POP R8
0x00043BF4       POP LR
0x00043BF8       RET

;------------------------------------------------------------------------------
; Data Section
;------------------------------------------------------------------------------
slash_char:
    .WORD 47      ;'/'
newline_char:
    .WORD 10


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

0x00043C04       RET



;==============================================================================
; Data Section
;==============================================================================
space_str:
    .ASCIIZ " "

newline_str:
    .ASCIIZ "\n"

ch_buf:
    .ASCIIZ "\0"

;==============================================================================
; Constants (already defined in libc.inc, but redefined here for clarity)
;==============================================================================
.EQU O_RDONLY,      0

;==============================================================================
; main - Program entry point
; IN:  R1 = argc, R2 = argv
; OUT: R1 = 0 on success, 1 if any directory could not be opened
;==============================================================================
main:
0x00043C0E       PUSH LR
0x00043C12       PUSH R6
0x00043C16       PUSH R7
0x00043C1A       PUSH R8
0x00043C1E       PUSH R9
0x00043C22       PUSH R10
0x00043C26       PUSH R11
0x00043C2A       PUSH R12

    ; allocate 76-byte buffer on stack for directory entry
0x00043C2E       LI  R3 DIRENT_SIZEOF
0x00043C36       SUB SP SP R3
0x00043C3A       MOV R12 SP              ; R12 = pointer to struct dirent buffer

0x00043C3E       MOV R8 R1               ; R8 = argc
0x00043C42       MOV R9 R2               ; R9 = argv

0x00043C46       CMP R8 2                ; Need at least one argument (argv[1])
0x00043C4A       BLT usage



0x00043C52       LI R10 1                ; R10 = current argument index (argv[1])
0x00043C5A       LI R6 0                 ; R6 = return code (0 = success)

dir_loop:
0x00043C62       CMP R10 R8              ; if index >= argc, done
0x00043C66       BGE dir_done

    ; Get the path string from argv[index]
0x00043C6E       MOV R2 R10
0x00043C72       SHL R2 R2 2
0x00043C76       ADD R2 R9 R2
0x00043C7A       LDW R1 [R2]             ; R1 = directory path (e.g., "etc/")
0x00043C7E       PUSH R1

    ; Print header: "\n--- Directory: path ---\n"
0x00043C82       LI R1 newline_str
0x00043C8A   CALL puts
0x00043C92       LI R1 dir_header_prefix
0x00043C9A   CALL puts
    ; print the directory name
0x00043CA2       MOV R2 R10
0x00043CA6       SHL R2 R2 2
0x00043CAA       ADD R2 R9 R2
0x00043CAE       LDW R1 [R2]
0x00043CB2   CALL puts
0x00043CBA       LI R1 dir_header_suffix
0x00043CC2   CALL puts
0x00043CCA       LI R1 newline_str
0x00043CD2   CALL puts

    ; open directory using opendir wrapper
0x00043CDA       POP R1                  ; path
0x00043CDE   CALL opendir

0x00043CE6       MOV R11 R1              ; R11 = DIR* handle

0x00043CEA       CMP R11 0
0x00043CEE       BEQ open_failed         ; opendir returns 0 on error

read_dir_loop:
    ; Read next directory entry
0x00043CF6       MOV R1 R11              ; DIR*
0x00043CFA       MOV R2 R12              ; pointer to dirent buffer
0x00043CFE   CALL readdir
0x00043D06       CMP R1 0
0x00043D0A       BEQ read_done           ; EOF
0x00043D12       LI  R2 -1
0x00043D1A       CMP R1 R2
0x00043D1E       BEQ read_done           ; error

    ; parse the directory entry
0x00043D26       LDW R5 [R12 + DIRENT_TYPE]   ; R5 = d_type (DT_REG or DT_DIR)

    ; print filename (null-terminated at R12 + DIRENT_NAME)
0x00043D2A       ADD R1 R12 DIRENT_NAME
0x00043D2E   CALL puts

    ; if directory, print '/'
0x00043D36       CMP R5 DT_DIR
0x00043D3A       BNE not_dir_entry
0x00043D42       LI R1 slash_str
0x00043D4A   CALL puts
not_dir_entry:

    ; print newline
0x00043D52       LI R1 newline_str
0x00043D5A   CALL puts

0x00043D62       B read_dir_loop

read_done:
    ; close directory using closedir wrapper
0x00043D6A       MOV R1 R11
0x00043D6E   CALL closedir

0x00043D76       ADD R10 R10 1           ; next directory
0x00043D7A       B dir_loop

open_failed:
    ; print error message for this directory
0x00043D82       LI R1 error_prefix
0x00043D8A   CALL puts
    ; print the directory name
0x00043D92       MOV R2 R10
0x00043D96       SHL R2 R2 2
0x00043D9A       ADD R2 R9 R2
0x00043D9E       LDW R1 [R2]
0x00043DA2   CALL puts
0x00043DAA       LI R1 ls_newline_str
0x00043DB2   CALL puts

0x00043DBA       LI R6 1                 ; set return code to error
0x00043DC2       ADD R10 R10 1           ; next directory
0x00043DC6       B dir_loop

dir_done:
    ; free buffer
0x00043DCE       LI  R3 DIRENT_SIZEOF
0x00043DD6       ADD SP SP R3

0x00043DDA       MOV R1 R6               ; return code
0x00043DDE       POP R12
0x00043DE2       POP R11
0x00043DE6       POP R10
0x00043DEA       POP R9
0x00043DEE       POP R8
0x00043DF2       POP R7
0x00043DF6       POP R6
0x00043DFA       POP LR
0x00043DFE       RET

;==============================================================================
; usage - Print usage message and exit
;==============================================================================
usage:
0x00043E02       LI R1 usage_str
0x00043E0A   CALL puts
0x00043E12       LI R6 1                 ; error
0x00043E1A       B dir_done

;==============================================================================
; Data Section
;==============================================================================
usage_str:
    .ASCIIZ "usage: ls directory ...\n"
error_prefix:
    .ASCIIZ "ls: cannot open "
dir_header_prefix:
    .ASCIIZ "--- Directory: "
dir_header_suffix:
    .ASCIIZ " ---"
slash_str:
    .ASCIIZ "/"
ls_newline_str:
    .ASCIIZ "\n"

;==============================================================================
; Include the standard libc scaffold
;==============================================================================
; ... (rest of libc.inc goes here, including opendir/readdir/closedir)
