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
 ;   PUSH R1
 ;   PUSH R2
 ;   PUSH R3
    ; Initialize the allocator (must do this first!)
 ;   CALL malloc_init
 ;   POP  R3
 ;   POP  R2
 ;   POP  R1
0x00043010       Debug 2
0x00043014       BL main              ; call main loop - ls cat echo etc
0x0004301C       Debug 2
0x00043020       LI R1 0
0x00043028       PUSH R1              ; exit 0 - success 1 - error
0x0004302C       LI R1 1              ; put to sleep so parent waitpid can work
0x00043034       SVC SYS_SLEEP
0x00043038       Debug 2
0x0004303C       POP  R1
  ;  LI R1 42
0x00043040       SVC SYS_EXIT

;==============================================================================
; puts - Write null-terminated string to stdout with newline
; IN:  R1 = string pointer
; OUT: R1 = bytes written or error code
;==============================================================================
puts:
0x00043044       PUSH LR
0x00043048       PUSH R8
0x0004304C       PUSH R9
0x00043050       MOV R8 R1            ; Save string pointer
0x00043054       BL strlen            ; Get string length
0x0004305C       MOV R9 R1            ; Save length
0x00043060       LI R1 STDOUT_FD
0x00043068       MOV R2 R8            ; Buffer = string
0x0004306C       MOV R3 R9            ; Count = length
0x00043070       SVC SYS_WRITE
0x00043074       POP R9
0x00043078       POP R8
0x0004307C       POP LR
0x00043080       RET

;==============================================================================
; putchar - Write single character to stdout
; IN:  R1 = character
; OUT: R1 = bytes written (1) or error code
;==============================================================================
putchar:
0x00043084       PUSH LR
0x00043088       PUSH R8
0x0004308C       LI R8 ch_buf
0x00043094       STB R1 [R8]          ; Store char in static buffer
0x00043098       LI R1 STDOUT_FD
0x000430A0       MOV R2 R8
0x000430A4       LI R3 1
0x000430AC       SVC SYS_WRITE
0x000430B0       POP R8
0x000430B4       POP LR
0x000430B8       RET

;==============================================================================
; strlen - Calculate string length
; IN:  R1 = string pointer
; OUT: R1 = length (excluding null terminator)
;==============================================================================
strlen:
0x000430BC       PUSH LR
0x000430C0       PUSH R8
0x000430C4       PUSH R9
0x000430C8       MOV R8 R1
0x000430CC       LI R9 0
strlen_loop:
0x000430D4       LDB R2 [R8 + R9]     ; Read character at current offset
0x000430D8       CMP R2 0
0x000430DC       BEQ strlen_done
0x000430E4       ADD R9 R9 1          ; Increment counter
0x000430E8       B strlen_loop
strlen_done:
0x000430F0       MOV R1 R9
0x000430F4       POP R9
0x000430F8       POP R8
0x000430FC       POP LR
0x00043100       RET

;==============================================================================
; strcmp - Compare two strings
; IN:  R1 = string1, R2 = string2
; OUT: R1 = 1 if equal, 0 if different
;==============================================================================
strcmp:
0x00043104       PUSH LR
0x00043108       PUSH R8
0x0004310C       PUSH R9
0x00043110       PUSH R10
0x00043114       MOV R8 R1
0x00043118       MOV R9 R2
strcmp_loop:
0x0004311C       LDB R10 [R8]         ; Load char from string1
0x00043120       LDB R1 [R9]          ; Load char from string2
0x00043124       CMP R10 R1
0x00043128       BNE strcmp_ne        ; Mismatch found
0x00043130       CMP R10 0
0x00043134       BEQ strcmp_eq        ; Both strings ended at same time
0x0004313C       ADD R8 R8 1          ; Advance both pointers
0x00043140       ADD R9 R9 1
0x00043144       B strcmp_loop
strcmp_eq:
0x0004314C       LI R1 1
0x00043154       B strcmp_done
strcmp_ne:
0x0004315C       LI R1 0
strcmp_done:
0x00043164       POP R10
0x00043168       POP R9
0x0004316C       POP R8
0x00043170       POP LR
0x00043174       RET

;==============================================================================
; memcpy - Copy memory block
; IN:  R1 = dest, R2 = src, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memcpy:
0x00043178       PUSH LR
0x0004317C       PUSH R8
0x00043180       PUSH R9
0x00043184       PUSH R10
0x00043188       MOV R8 R1
0x0004318C       MOV R9 R2
0x00043190       MOV R10 R3
memcpy_loop:
0x00043194       CMP R10 0
0x00043198       BEQ memcpy_done
0x000431A0       LDB R1 [R9]          ; Read byte from source
0x000431A4       STB R1 [R8]          ; Write byte to destination
0x000431A8       ADD R8 R8 1          ; Advance both pointers
0x000431AC       ADD R9 R9 1
0x000431B0       SUB R10 R10 1        ; Decrement counter
0x000431B4       B memcpy_loop
memcpy_done:
0x000431BC       MOV R1 R8
0x000431C0       POP R10
0x000431C4       POP R9
0x000431C8       POP R8
0x000431CC       POP LR
0x000431D0       RET

;==============================================================================
; memset - Fill memory with constant byte
; IN:  R1 = dest, R2 = value, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memset:
0x000431D4       PUSH LR
0x000431D8       PUSH R8
0x000431DC       PUSH R9
0x000431E0       PUSH R10
0x000431E4       MOV R8 R1
0x000431E8       MOV R9 R2
0x000431EC       MOV R10 R3
memset_loop:
0x000431F0       CMP R10 0
0x000431F4       BEQ memset_done
0x000431FC       STB R9 [R8]          ; Store value at current position
0x00043200       ADD R8 R8 1          ; Advance pointer
0x00043204       SUB R10 R10 1        ; Decrement counter
0x00043208       B memset_loop
memset_done:
0x00043210       MOV R1 R8
0x00043214       POP R10
0x00043218       POP R9
0x0004321C       POP R8
0x00043220       POP LR
0x00043224       RET

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
0x00043228       SVC SYS_WRITE
0x0004322C       RET


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
0x00043230       SVC SYS_READ
0x00043234       RET


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
0x00043238       SVC SYS_OPEN
0x0004323C       RET


;------------------------------------------------------------------------------
; close(fd)
;------------------------------------------------------------------------------
close:
0x00043240       SVC SYS_CLOSE
0x00043244       RET


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
0x00043248       SVC SYS_FORK
0x0004324C       RET


;------------------------------------------------------------------------------
; execve(path, argv, envp)
;------------------------------------------------------------------------------
execve:
0x00043250       SVC SYS_EXECVE
0x00043254       RET


;------------------------------------------------------------------------------
; waitpid(pid,status)
;------------------------------------------------------------------------------
waitpid:
0x00043258       SVC SYS_WAITPID
0x0004325C       RET


;------------------------------------------------------------------------------
; sleep(milliseconds)
;------------------------------------------------------------------------------
sleep:
0x00043260       SVC SYS_SLEEP
0x00043264       RET


;------------------------------------------------------------------------------
; exit(status)
;
; never returns
;------------------------------------------------------------------------------
exit:
0x00043268       SVC SYS_EXIT

exit_hang:
0x0004326C       B exit_hang


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
0x000434B4       PUSH LR               ; Save return address

    ; Step 1: Align size to multiple of 8 bytes
    ; Why? Many CPUs work faster with aligned memory
    ; Example: size=100
    ;   ADD R1 7    -> 107
    ;   AND 0xFFFFFFF8 -> 104 (multiple of 8)
0x000434B8       ADD R1 R1 7           ; Add 7 to round up
0x000434BC       LI  R2 0xFFFFFFF8
0x000434C4       AND R1 R1 R2          ; Clear lower 3 bits (make multiple of 8)
0x000434C8       MOV R5 R1             ; R5 = aligned size (e.g., 104)

    ; Step 2: Search for a free block in the table
    ; We'll use R4 as index into block_table (0 to MAX_BLOCKS-1)
0x000434CC       LI R4 0               ; Start at first block (index 0)

malloc_loop:
    ; Check if we've searched all blocks
0x000434D4       CMP R4 MAX_BLOCKS     ; Compare index with maximum
0x000434D8       BGE malloc_sbrk       ; If index >= MAX_BLOCKS, no free block found

    ; Calculate address of this block's descriptor
    ; block_table + (index * descriptor_size)
0x000434E0       LI R2 block_table     ; R2 = base address of block_table
0x000434E8       LI R3 BLOCK_DESC      ; R3 = size of one descriptor (12 bytes)
0x000434F0       MUL R3 R4 R3          ; R3 = index * 12 (offset into table)
0x000434F4       ADD R2 R2 R3          ; R2 = &block[index]

    ; Check if this block is free (USED flag = 0)
0x000434F8       LDW R3 [R2 + BLOCK_USED]  ; Load the &block[index].block_used flag
0x000434FC       CMP R3 0              ; Is it 0 (free)?
0x00043500       BNE malloc_next       ; If not free (used), skip to next block

    ; free. Check if this block is large enough for our request
0x00043508       LDW R3 [R2 + BLOCK_SIZE]  ; Load the block size
0x0004350C       CMP R3 R5             ; Is block size >= requested size?
0x00043510       BGE malloc_found      ; Yes! We found a suitable block

malloc_next:
    ; This block is either used or too small, try next one
0x00043518       ADD R4 R4 1           ; Increment index to check next block
0x0004351C       B malloc_loop         ; Go back to start of loop

malloc_found:
    ; Step 3: We found a free block large enough!
    ; R2 = pointer to the block descriptor
    ; R3 = block size (we don't use it for splitting in this simple version)

    ; Mark the block as used (USED flag = 1)
0x00043524       LI R3 1               ; R3 = 1 (used)
0x0004352C       STW R3 [R2 + BLOCK_USED]  ; Store 1 in the USED field

    ; Get the block's starting address and return it
0x00043530       LDW R1 [R2 + BLOCK_ADDR]  ; R1 = address of this block
0x00043534       B malloc_done         ; Jump to cleanup and return

malloc_sbrk:
    ; Step 4: No free block found in table
    ; Ask the kernel for more memory using sbrk syscall

    ; R5 already has the aligned size we need
0x0004353C       MOV R1 R5             ; R1 = size to allocate
0x00043540       SVC SYS_SBRK          ; Call kernel: sbrk(size)

    ; Check if sbrk failed (returns -1 or 0 on error)
0x00043544       CMP R1 0              ; Did sbrk return 0 or negative?
0x00043548       BLT malloc_error      ; If error, return NULL

    ; Step 5: sbrk succeeded, we have new memory at address in R1
    ; Now we need to add this new block to our table

    ; Find an empty slot in the block table
0x00043550       LI R4 0               ; Start at first block

malloc_add:
    ; Check if we've searched all blocks
0x00043558       CMP R4 MAX_BLOCKS
0x0004355C       BGE malloc_error      ; No empty slot! (shouldn't happen)

    ; Get descriptor address
0x00043564       LI R2 block_table
0x0004356C       LI R3 BLOCK_DESC
0x00043574       MUL R3 R4 R3
0x00043578       ADD R2 R2 R3        ; &block[indexR4]

    ; Check if this slot is free (USED flag = 0)
0x0004357C       LDW R3 [R2 + BLOCK_USED]
0x00043580       CMP R3 0
0x00043584       BEQ malloc_add_found  ; Found an empty slot!

    ; Slot is used, try next one
0x0004358C       ADD R4 R4 1
0x00043590       B malloc_add

malloc_add_found:
    ; We found an empty slot at R2
    ; Store the new block's information

    ; Store the address (R1 from sbrk)
0x00043598       STW R1 [R2 + BLOCK_ADDR]   ; block.address = address from sbrk

    ; Store the size (R5 = aligned size)
0x0004359C       STW R5 [R2 + BLOCK_SIZE]   ; block.size = size

    ; Mark as used (USED = 1)
0x000435A0       LI R3 1
0x000435A8       STW R3 [R2 + BLOCK_USED]   ; block.used = 1

    ; R1 already has the address from sbrk, so just return it
0x000435AC       B malloc_done

malloc_error:
    ; Something went wrong - return NULL (0)
0x000435B4       LI R1 0

malloc_done:
0x000435BC       POP LR                ; Restore return address
0x000435C0       RET                   ; Return to caller with R1 = pointer or NULL

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
0x000435C4       PUSH LR

    ; Step 1: Check if pointer is NULL
0x000435C8       CMP R1 0              ; Is R1 == 0?
0x000435CC       BEQ free_done         ; If NULL, nothing to free, just return

    ; Step 2: Search the block table for this address
0x000435D4       LI R4 0               ; Start at first block

free_loop:
    ; Check if we've searched all blocks
0x000435DC       CMP R4 MAX_BLOCKS
0x000435E0       BGE free_done         ; Not found - ignore (could be invalid pointer)

    ; Get descriptor address
0x000435E8       LI R2 block_table
0x000435F0       LI R3 BLOCK_DESC      ; length of one block descriptor
0x000435F8       MUL R3 R4 R3          ; r4 block idx
0x000435FC       ADD R2 R2 R3          ; R2 = &block[i]

    ; Check if this block's address matches the pointer
0x00043600       LDW R3 [R2 + BLOCK_ADDR]  ; R3 =  &block[i].block address
0x00043604       CMP R3 R1             ; Is this our block?
0x00043608       BEQ free_found        ; Yes, we found it!

    ; Not this block, try next
0x00043610       ADD R4 R4 1
0x00043614       B free_loop

free_found:
    ; Step 3: We found the block descriptor at R2
    ; Mark it as free so malloc can use it again

0x0004361C       LI R3 0               ; R3 = 0 (free)
0x00043624       STW R3 [R2 + BLOCK_USED]  ; &block[i].used = 0

    ; NOTE: We do NOT clear the address or size
    ; They stay in the table and will be overwritten when reused

free_done:
    ; Clean up and return
0x00043628       POP LR
0x0004362C       RET

;------------------------------------------------------------------------------
; malloc_init - Initialize the memory allocator
;
; Clears the entire block table so all blocks are marked as free
; Should be called once at system startup before using malloc
;------------------------------------------------------------------------------
malloc_init:
    ; Save registers
0x00043630       PUSH LR
    ; Step 1: Clear the entire block table
    ; Set all bytes in block_table to 0
0x00043634       LI R1 block_table     ; R1 = start address of table
0x0004363C       LI R3 MAX_BLOCKS * BLOCK_DESC  ; R3 = total bytes to clear

malloc_init_loop:
0x00043644       CMP R3 0              ; Have we cleared all bytes?
0x00043648       BEQ malloc_init_done  ; Yes, we're done

0x00043650       LI R2 0               ; R2 = 0 (value to write)
0x00043658       STB R2 [R1]           ; Store 0 at current address
0x0004365C       ADD R1 R1 1           ; Move to next byte
0x00043660       SUB R3 R3 1           ; Decrement byte counter
0x00043664       B malloc_init_loop    ; Continue

malloc_init_done:
    ; Clean up and return
0x0004366C       POP LR
0x00043670       RET


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
0x00043674       PUSH LR
0x00043678       PUSH R8
0x0004367C       PUSH R9
0x00043680       PUSH R10
0x00043684       PUSH R11
0x00043688       PUSH R12

0x0004368C       MOV  R8  R1          ; Save destination

0x00043690       MOV  R9  R2          ; Working value
0x00043694       MOV  R11 R3          ; Base
0x00043698       MOV  R12 R4          ; Sign flag
    ;MOV  R10 R5          ; Temp buffer size

    ; Allocate temp buffer (size passed in R5)
0x0004369C       SUB  SP SP R5
0x000436A0       MOV  R10 R1          ; Keep original pointer
0x000436A4       MOV  R6  SP          ; Temp buffer pointer
0x000436A8       push R5              ; save R5 for frame leave
0x000436AC       MOV  R7  R6          ; Save start of temp buffer

    ; Check for sign (if signed and negative)
0x000436B0       CMP  R12 1
0x000436B4       BNE  itoa_core_unsigned

0x000436BC       CMP  R9 0
0x000436C0       BGE  itoa_core_unsigned

    ; Negative number - add minus sign
0x000436C8       LI   R2 45     ;'-'
0x000436D0       STB  R2 [R8]
0x000436D4       ADD  R8 R8 1
0x000436D8       NOT  R9 R9
0x000436DC       ADD  R9 R9 1
    ;NEG  R9              ; Make positive

itoa_core_unsigned:
    ; Special case: zero
0x000436E0       CMP  R9 0
0x000436E4       BNE  itoa_core_convert

0x000436EC       LI   R2 48    ; '0'
0x000436F4       STB  R2 [R8]
0x000436F8       ADD  R8 R8 1
0x000436FC       LI   R2 0
0x00043704       STB  R2 [R8]
0x00043708       B    itoa_core_finish

itoa_core_convert:
0x00043710       LI   R4 0            ; Digit counter

itoa_core_divloop:
0x00043718       MOV  R5 R9
0x0004371C       DIV  R6 R5 R11       ; R6 = quotient, R9 = remainder
0x00043720       MOD  R7 R9 R11       ; R7 = remainder

    ; Convert digit to ASCII based on base
0x00043724       CMP  R11 16
0x00043728       BEQ  itoa_core_hex_digit

    ; Base 2 or 10: digit 0-9
0x00043730       ADD  R7 R7 48        ; '0' + digit
0x00043734       B    itoa_core_store

itoa_core_hex_digit:
    ; Base 16: digit 0-15
0x0004373C       CMP  R7 9
0x00043740       BGT  itoa_core_hex_letter
0x00043748       ADD  R7 R7 48        ; '0' + digit
0x0004374C       B    itoa_core_store

itoa_core_hex_letter:
0x00043754       SUB  R7 R7 10
0x00043758       ADD  R7 R7 65        ; 'A' + (digit-10)

itoa_core_store:
0x0004375C       STB  R7 [R6]         ; Store in temp buffer
0x00043760       ADD  R6 R6 1
0x00043764       ADD  R4 R4 1         ; Increment digit count

0x00043768       MOV  R9 R5           ; Quotient becomes new value
0x0004376C       CMP  R9 0
0x00043770       BNE  itoa_core_divloop

    ; Point to last digit
0x00043778       SUB  R6 R6 1

itoa_core_copy:
0x0004377C       CMP  R4 0
0x00043780       BEQ  itoa_core_done

0x00043788       LDB  R2 [R6]         ; Get digit from temp (reverse order)
0x0004378C       STB  R2 [R8]         ; Store in destination
0x00043790       ADD  R8 R8 1
0x00043794       SUB  R6 R6 1
0x00043798       SUB  R4 R4 1
0x0004379C       B    itoa_core_copy

itoa_core_done:
0x000437A4       LI   R2 0
0x000437AC       STB  R2 [R8]         ; Null terminate

itoa_core_finish:
0x000437B0       POP  R5
    ; Clean up temp buffer
0x000437B4       ADD  SP SP R5

    ; Return original pointer
0x000437B8       MOV  R1 R10

0x000437BC       POP  R12
0x000437C0       POP  R11
0x000437C4       POP  R10
0x000437C8       POP  R9
0x000437CC       POP  R8
0x000437D0       POP  LR
0x000437D4       RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
0x000437D8       PUSH LR

    ; Max 11 digits + sign + null = 13 bytes
0x000437DC       LI   R3 10           ; Base 10
0x000437E4       LI   R4 1            ; Signed
0x000437EC       LI   R5 13           ; Temp buffer size
0x000437F4   CALL itoa_core

0x000437FC       POP  LR
0x00043800       RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
0x00043804       PUSH LR

    ; Max 8 digits + null = 9 bytes
0x00043808       LI   R3 16           ; Base 16
0x00043810       LI   R4 0            ; Unsigned (shows raw bits)
0x00043818       LI   R5 9            ; Temp buffer size
0x00043820   CALL itoa_core

0x00043828       POP  LR
0x0004382C       RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
0x00043830       PUSH LR

    ; Max 32 bits + null = 33 bytes
0x00043834       LI   R3 2            ; Base 2
0x0004383C       LI   R4 0            ; Unsigned (shows raw bits)
0x00043844       LI   R5 33           ; Temp buffer size
0x0004384C   CALL itoa_core

0x00043854       POP  LR
0x00043858       RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
0x0004385C       PUSH LR

    ; Max 8 digits + sign + null = 10 bytes
0x00043860       LI   R3 16           ; Base 16
0x00043868       LI   R4 1            ; Signed (shows sign)
0x00043870       LI   R5 10           ; Temp buffer size
0x00043878   CALL itoa_core

0x00043880       POP  LR
0x00043884       RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
0x00043888       PUSH LR

    ; Max 32 bits + sign + null = 34 bytes
0x0004388C       LI   R3 2            ; Base 2
0x00043894       LI   R4 1            ; Signed (shows sign)
0x0004389C       LI   R5 34           ; Temp buffer size
0x000438A4   CALL itoa_core

0x000438AC       POP  LR
0x000438B0       RET

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
0x000438B4       PUSH LR
0x000438B8       MOV R3 R1              ; Save original destination pointer
0x000438BC       MOV R4 R2              ; Save source pointer

strcpy_loop:
0x000438C0       LDB R2 [R4]            ; Load byte from source
0x000438C4       STB R2 [R1]            ; Store byte to destination

0x000438C8       CMP R2 0               ; Check if it's null terminator
0x000438CC       BEQ strcpy_done        ; If zero, we're done

0x000438D4       ADD R1 R1 1            ; Advance destination pointer
0x000438D8       ADD R4 R4 1            ; Advance source pointer
0x000438DC       B strcpy_loop

strcpy_done:
0x000438E4       MOV R1 R3              ; Return original destination pointer
0x000438E8       POP LR
0x000438EC       RET


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
0x000438F0       PUSH LR
0x000438F4       PUSH R8
0x000438F8       PUSH R9

0x000438FC       MOV R8 R1            ; Save path
    ; Open directory with read-only flags (same as your ls.asm)
0x00043900       MOV R1 R8
0x00043904       LI  R2 O_RDONLY
0x0004390C       SVC SYS_OPEN
0x00043910       MOV R9 R1           ;fd
0x00043914       CMP R1 0
0x00043918       BLT opendir_error

    ; Allocate DIR structure (small, just fd and offset)
0x00043920       PUSH R9                 ;save R9 jic
0x00043924       LI R1 DIR_SIZEOF
0x0004392C   CALL malloc
0x00043934       POP  R9

0x00043938       CMP R1 0
0x0004393C       BEQ opendir_error_close

0x00043944       MOV R8 R1            ; Save DIR*

    ; Initialize DIR structure
    ; R2 still has fd from open
0x00043948       STW R9 [R8 + DIR_FD]
0x0004394C       LI  R2 0
0x00043954       STW R2 [R8 + DIR_OFFSET]

0x00043958       MOV R1 R8            ; Return DIR*
0x0004395C       B opendir_done

opendir_error_close:
0x00043964       MOV R1 R9            ; fd is in R9
0x00043968       SVC SYS_CLOSE
0x0004396C       LI R1 0
0x00043974       B opendir_done

opendir_error:
0x0004397C       LI R1 0

opendir_done:
0x00043984       POP R9
0x00043988       POP R8
0x0004398C       POP LR
0x00043990       RET

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
0x00043994       PUSH LR
0x00043998       PUSH R8
0x0004399C       PUSH R9

0x000439A0       MOV R8 R1            ; DIR*
0x000439A4       MOV R9 R2            ; User's dirent buffer

    ; Check if DIR pointer is valid
0x000439A8       CMP R8 0
0x000439AC       BEQ readdir_error

    ; Read one dirent from directory fd using current offset
0x000439B4       LDW R1 [R8 + DIR_FD] ; fd

    ; Use the directory's offset - we need to implement lseek or use
    ; the fact that each read gets one dirent at a time from tarfs
0x000439B8       MOV R2 R9            ; user buffer
0x000439BC       LI  R3 DIRENT_SIZEOF ; size of one dirent
0x000439C4       SVC SYS_READ
0x000439C8       CMP R1 0
0x000439CC       BEQ readdir_end      ; EOF
0x000439D4       CMP R1 DIRENT_SIZEOF
0x000439D8       BNE readdir_error    ; Short read or error

    ; Entry read successfully
    ; Update the offset in DIR structure
0x000439E0       LDW R2 [R8 + DIR_OFFSET]
0x000439E4       ADD R2 R2 1
0x000439E8       STW R2 [R8 + DIR_OFFSET]

0x000439EC       LI R1 1              ; Return success
0x000439F4       B readdir_done

readdir_error:
0x000439FC       LI R1 -1
0x00043A04       B readdir_done

readdir_end:
0x00043A0C       LI R1 0

readdir_done:
0x00043A14       POP R9
0x00043A18       POP R8
0x00043A1C       POP LR
0x00043A20       RET

;------------------------------------------------------------------------------
; closedir - Close directory stream
;
; IN:  R1 = DIR*
; OUT: R1 = 0 on success, -1 on error
;------------------------------------------------------------------------------
closedir:
0x00043A24       PUSH LR
0x00043A28       PUSH R8

0x00043A2C       MOV R8 R1
0x00043A30       CMP R8 0
0x00043A34       BEQ closedir_error

    ; Close the directory fd
0x00043A3C       LDW R1 [R8 + DIR_FD]
0x00043A40       SVC SYS_CLOSE

    ; Free the DIR structure
0x00043A44       MOV R1 R8
0x00043A48   CALL free

0x00043A50       LI R1 0
0x00043A58       B closedir_done

closedir_error:
0x00043A60       LI R1 -1

closedir_done:
0x00043A68       POP R8
0x00043A6C       POP LR
0x00043A70       RET

;------------------------------------------------------------------------------
; rewinddir - Reset directory stream to beginning
;
; IN:  R1 = DIR*
;------------------------------------------------------------------------------
rewinddir:
0x00043A74       CMP R1 0
0x00043A78       BEQ rewinddir_done

0x00043A80       LI R2 0
0x00043A88       STW R2 [R1 + DIR_OFFSET]

    ; Need to seek to beginning of directory
    ; For tarfs, this means closing and reopening, or using lseek
    ; Simple approach: close and reopen
0x00043A8C       PUSH LR
0x00043A90       PUSH R8

0x00043A94       MOV R8 R1
    ; Save the path - we don't have it stored, so this is tricky
    ; In a real implementation, store path in DIR structure

    ; For now, just reset offset and rely on readdir's behavior

0x00043A98       POP R8
0x00043A9C       POP LR

rewinddir_done:
0x00043AA0       RET

;------------------------------------------------------------------------------
; dirfd - Get file descriptor from DIR*
;
; IN:  R1 = DIR*
; OUT: R1 = file descriptor, or -1 on error
;------------------------------------------------------------------------------
dirfd:
0x00043AA4       CMP R1 0
0x00043AA8       BEQ dirfd_error

0x00043AB0       LDW R1 [R1 + DIR_FD]
0x00043AB4       RET

dirfd_error:
0x00043AB8       LI R1 -1
0x00043AC0       RET

;------------------------------------------------------------------------------
; Helper: is_dir - Check if a path is a directory
;
; IN:  R1 = path
; OUT: R1 = 1 if directory, 0 if not, -1 on error
;------------------------------------------------------------------------------
is_dir:
0x00043AC4       PUSH LR

    ; Try to open as directory
0x00043AC8   CALL opendir
0x00043AD0       CMP R1 0
0x00043AD4       BEQ is_dir_not_dir

    ; It opened as a directory
0x00043ADC       MOV R2 R1            ; Save DIR*
0x00043AE0       LI R1 1              ; Return true
0x00043AE8   CALL closedir
0x00043AF0       B is_dir_done

is_dir_not_dir:
0x00043AF8       LI R1 0

is_dir_done:
0x00043B00       POP LR
0x00043B04       RET

;------------------------------------------------------------------------------
; Example usage function - list directory contents (like ls)
; This demonstrates how to use opendir/readdir/closedir
;------------------------------------------------------------------------------
list_directory:
0x00043B08       PUSH LR
0x00043B0C       PUSH R8
0x00043B10       PUSH R9

0x00043B14       MOV R8 R1            ; path

    ; Allocate dirent on stack
0x00043B18       SUB SP SP DIRENT_SIZEOF
0x00043B1C       MOV R9 SP

    ; Open directory
0x00043B20       MOV R1 R8
0x00043B24   CALL opendir
0x00043B2C       CMP R1 0
0x00043B30       BEQ list_dir_error

0x00043B38       MOV R8 R1            ; DIR*

list_dir_loop:
0x00043B3C       MOV R1 R8
0x00043B40       MOV R2 R9
0x00043B44   CALL readdir
0x00043B4C       CMP R1 0
0x00043B50       BEQ list_dir_close
0x00043B58       LI  R2 -1
0x00043B60       CMP R1 R2
0x00043B64       BEQ list_dir_error

    ; Print the name
0x00043B6C       ADD R1 R9 DIRENT_NAME
0x00043B70   CALL puts

    ; If it's a directory, print '/'
0x00043B78       LDW R2 [R9 + DIRENT_TYPE]
0x00043B7C       CMP R2 DT_DIR
0x00043B80       BNE list_dir_not_dir

0x00043B88       LI R1 slash_char
0x00043B90   CALL putchar

list_dir_not_dir:
0x00043B98       LI R1 newline_char
0x00043BA0   CALL putchar

0x00043BA8       B list_dir_loop

list_dir_close:
0x00043BB0       MOV R1 R8
0x00043BB4   CALL closedir
0x00043BBC       LI R1 0
0x00043BC4       B list_dir_done

list_dir_error:
0x00043BCC       LI R1 -1

list_dir_done:
0x00043BD4       ADD SP SP DIRENT_SIZEOF
0x00043BD8       POP R9
0x00043BDC       POP R8
0x00043BE0       POP LR
0x00043BE4       RET

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

0x00043BF0       RET



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
; main - Program entry point
; IN:  R1 = argc, R2 = argv
; OUT: R1 = 0 (always succeeds)
;==============================================================================
main:
0x00043BFA       NOP
0x00043BFE       DEBUG 2     ;testing INVLPG and tlb cache

0x00043C02       PUSH LR
0x00043C06       PUSH R8              ;
0x00043C0A       PUSH R9              ;
0x00043C0E       PUSH R10             ; Loop counter

0x00043C12       MOV R8 R1            ; R8 = argc
0x00043C16       MOV R9 R2            ; R9 = argv
0x00043C1A       LI R10 1             ; Start from argv[1] (skip program name argv[0])
0x00043C22       MOV R11 R9           ; R11 = current argv pointer
0x00043C26       ADD R11 R11 4        ; Skip argv[0] (program name)

echo_next_arg:
0x00043C2A       CMP R10 R8           ; Check if we've processed all arguments
0x00043C2E       BGE echo_done

0x00043C36       LDW R1 [R11]         ; Load current argument string
0x00043C3A       BL puts              ; Print the argument-string

0x00043C42       ADD R10 R10 1        ; Increment argument counter
0x00043C46       ADD R11 R11 4        ; Move to next argv entry
0x00043C4A       CMP R10 R8           ; Check if this was the last argument
0x00043C4E       BGE echo_newline     ; If last, just print newline
0x00043C56       LI R1 space_str      ; Otherwise print space between arguments
0x00043C5E       BL puts
0x00043C66       B echo_next_arg

echo_newline:
0x00043C6E       LI R1 newline_str    ; Print final newline
0x00043C76       BL puts

echo_done:

0x00043C7E       LI R1 0              ; Return success
0x00043C86       POP R10
0x00043C8A       POP R9
0x00043C8E       POP R8
0x00043C92       POP LR
0x00043C96       RET
