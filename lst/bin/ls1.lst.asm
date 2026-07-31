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
 ;   PUSH R1
 ;   PUSH R2
 ;   PUSH R3
    ; Initialize the allocator (must do this first!)
 ;   CALL malloc_init
 ;   POP  R3
 ;   POP  R2
 ;   POP  R1
0x00043010       BL main              ; call main loop - ls cat echo etc
  ;  LI R1 1
  ;  PUSH R1              ; exit 0 - success 1 - error
  ;  LI R1 1              ; put to sleep so parent waitpid can work
  ;  SVC SYS_SLEEP
  ;  POP  R1
0x00043018       LI R1 42
0x00043020       SVC SYS_EXIT

;==============================================================================
; puts - Write null-terminated string to stdout with newline
; IN:  R1 = string pointer
; OUT: R1 = bytes written or error code
;==============================================================================
puts:
0x00043024       PUSH LR
0x00043028       PUSH R8
0x0004302C       PUSH R9
0x00043030       MOV R8 R1            ; Save string pointer
0x00043034       BL strlen            ; Get string length
0x0004303C       MOV R9 R1            ; Save length
0x00043040       LI R1 STDOUT_FD
0x00043048       MOV R2 R8            ; Buffer = string
0x0004304C       MOV R3 R9            ; Count = length
0x00043050       SVC SYS_WRITE
0x00043054       POP R9
0x00043058       POP R8
0x0004305C       POP LR
0x00043060       RET

;==============================================================================
; putchar - Write single character to stdout
; IN:  R1 = character
; OUT: R1 = bytes written (1) or error code
;==============================================================================
putchar:
0x00043064       PUSH LR
0x00043068       PUSH R8
0x0004306C       LI R8 ch_buf
0x00043074       STB R1 [R8]          ; Store char in static buffer
0x00043078       LI R1 STDOUT_FD
0x00043080       MOV R2 R8
0x00043084       LI R3 1
0x0004308C       SVC SYS_WRITE
0x00043090       POP R8
0x00043094       POP LR
0x00043098       RET

;==============================================================================
; strlen - Calculate string length
; IN:  R1 = string pointer
; OUT: R1 = length (excluding null terminator)
;==============================================================================
strlen:
0x0004309C       PUSH LR
0x000430A0       PUSH R8
0x000430A4       PUSH R9
0x000430A8       MOV R8 R1
0x000430AC       LI R9 0
strlen_loop:
0x000430B4       LDB R2 [R8 + R9]     ; Read character at current offset
0x000430B8       CMP R2 0
0x000430BC       BEQ strlen_done
0x000430C4       ADD R9 R9 1          ; Increment counter
0x000430C8       B strlen_loop
strlen_done:
0x000430D0       MOV R1 R9
0x000430D4       POP R9
0x000430D8       POP R8
0x000430DC       POP LR
0x000430E0       RET

;==============================================================================
; strcmp - Compare two strings
; IN:  R1 = string1, R2 = string2
; OUT: R1 = 1 if equal, 0 if different
;==============================================================================
strcmp:
0x000430E4       PUSH LR
0x000430E8       PUSH R8
0x000430EC       PUSH R9
0x000430F0       PUSH R10
0x000430F4       MOV R8 R1
0x000430F8       MOV R9 R2
strcmp_loop:
0x000430FC       LDB R10 [R8]         ; Load char from string1
0x00043100       LDB R1 [R9]          ; Load char from string2
0x00043104       CMP R10 R1
0x00043108       BNE strcmp_ne        ; Mismatch found
0x00043110       CMP R10 0
0x00043114       BEQ strcmp_eq        ; Both strings ended at same time
0x0004311C       ADD R8 R8 1          ; Advance both pointers
0x00043120       ADD R9 R9 1
0x00043124       B strcmp_loop
strcmp_eq:
0x0004312C       LI R1 1
0x00043134       B strcmp_done
strcmp_ne:
0x0004313C       LI R1 0
strcmp_done:
0x00043144       POP R10
0x00043148       POP R9
0x0004314C       POP R8
0x00043150       POP LR
0x00043154       RET

;==============================================================================
; memcpy - Copy memory block
; IN:  R1 = dest, R2 = src, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memcpy:
0x00043158       PUSH LR
0x0004315C       PUSH R8
0x00043160       PUSH R9
0x00043164       PUSH R10
0x00043168       MOV R8 R1
0x0004316C       MOV R9 R2
0x00043170       MOV R10 R3
memcpy_loop:
0x00043174       CMP R10 0
0x00043178       BEQ memcpy_done
0x00043180       LDB R1 [R9]          ; Read byte from source
0x00043184       STB R1 [R8]          ; Write byte to destination
0x00043188       ADD R8 R8 1          ; Advance both pointers
0x0004318C       ADD R9 R9 1
0x00043190       SUB R10 R10 1        ; Decrement counter
0x00043194       B memcpy_loop
memcpy_done:
0x0004319C       MOV R1 R8
0x000431A0       POP R10
0x000431A4       POP R9
0x000431A8       POP R8
0x000431AC       POP LR
0x000431B0       RET

;==============================================================================
; memset - Fill memory with constant byte
; IN:  R1 = dest, R2 = value, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memset:
0x000431B4       PUSH LR
0x000431B8       PUSH R8
0x000431BC       PUSH R9
0x000431C0       PUSH R10
0x000431C4       MOV R8 R1
0x000431C8       MOV R9 R2
0x000431CC       MOV R10 R3
memset_loop:
0x000431D0       CMP R10 0
0x000431D4       BEQ memset_done
0x000431DC       STB R9 [R8]          ; Store value at current position
0x000431E0       ADD R8 R8 1          ; Advance pointer
0x000431E4       SUB R10 R10 1        ; Decrement counter
0x000431E8       B memset_loop
memset_done:
0x000431F0       MOV R1 R8
0x000431F4       POP R10
0x000431F8       POP R9
0x000431FC       POP R8
0x00043200       POP LR
0x00043204       RET

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
0x00043208       SVC SYS_WRITE
0x0004320C       RET


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
0x00043210       SVC SYS_READ
0x00043214       RET


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
0x00043218       SVC SYS_OPEN
0x0004321C       RET


;------------------------------------------------------------------------------
; close(fd)
;------------------------------------------------------------------------------
close:
0x00043220       SVC SYS_CLOSE
0x00043224       RET


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
0x00043228       SVC SYS_FORK
0x0004322C       RET


;------------------------------------------------------------------------------
; execve(path, argv, envp)
;------------------------------------------------------------------------------
execve:
0x00043230       SVC SYS_EXECVE
0x00043234       RET


;------------------------------------------------------------------------------
; waitpid(pid,status)
;------------------------------------------------------------------------------
waitpid:
0x00043238       SVC SYS_WAITPID
0x0004323C       RET


;------------------------------------------------------------------------------
; sleep(milliseconds)
;------------------------------------------------------------------------------
sleep:
0x00043240       SVC SYS_SLEEP
0x00043244       RET


;------------------------------------------------------------------------------
; exit(status)
;
; never returns
;------------------------------------------------------------------------------
exit:
0x00043248       SVC SYS_EXIT

exit_hang:
0x0004324C       B exit_hang


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
0x00043494       PUSH LR               ; Save return address

    ; Step 1: Align size to multiple of 8 bytes
    ; Why? Many CPUs work faster with aligned memory
    ; Example: size=100
    ;   ADD R1 7    -> 107
    ;   AND 0xFFFFFFF8 -> 104 (multiple of 8)
0x00043498       ADD R1 R1 7           ; Add 7 to round up
0x0004349C       LI  R2 0xFFFFFFF8
0x000434A4       AND R1 R1 R2          ; Clear lower 3 bits (make multiple of 8)
0x000434A8       MOV R5 R1             ; R5 = aligned size (e.g., 104)

    ; Step 2: Search for a free block in the table
    ; We'll use R4 as index into block_table (0 to MAX_BLOCKS-1)
0x000434AC       LI R4 0               ; Start at first block (index 0)

malloc_loop:
    ; Check if we've searched all blocks
0x000434B4       CMP R4 MAX_BLOCKS     ; Compare index with maximum
0x000434B8       BGE malloc_sbrk       ; If index >= MAX_BLOCKS, no free block found

    ; Calculate address of this block's descriptor
    ; block_table + (index * descriptor_size)
0x000434C0       LI R2 block_table     ; R2 = base address of block_table
0x000434C8       LI R3 BLOCK_DESC      ; R3 = size of one descriptor (12 bytes)
0x000434D0       MUL R3 R4 R3          ; R3 = index * 12 (offset into table)
0x000434D4       ADD R2 R2 R3          ; R2 = &block[index]

    ; Check if this block is free (USED flag = 0)
0x000434D8       LDW R3 [R2 + BLOCK_USED]  ; Load the &block[index].block_used flag
0x000434DC       CMP R3 0              ; Is it 0 (free)?
0x000434E0       BNE malloc_next       ; If not free (used), skip to next block

    ; free. Check if this block is large enough for our request
0x000434E8       LDW R3 [R2 + BLOCK_SIZE]  ; Load the block size
0x000434EC       CMP R3 R5             ; Is block size >= requested size?
0x000434F0       BGE malloc_found      ; Yes! We found a suitable block

malloc_next:
    ; This block is either used or too small, try next one
0x000434F8       ADD R4 R4 1           ; Increment index to check next block
0x000434FC       B malloc_loop         ; Go back to start of loop

malloc_found:
    ; Step 3: We found a free block large enough!
    ; R2 = pointer to the block descriptor
    ; R3 = block size (we don't use it for splitting in this simple version)

    ; Mark the block as used (USED flag = 1)
0x00043504       LI R3 1               ; R3 = 1 (used)
0x0004350C       STW R3 [R2 + BLOCK_USED]  ; Store 1 in the USED field

    ; Get the block's starting address and return it
0x00043510       LDW R1 [R2 + BLOCK_ADDR]  ; R1 = address of this block
0x00043514       B malloc_done         ; Jump to cleanup and return

malloc_sbrk:
    ; Step 4: No free block found in table
    ; Ask the kernel for more memory using sbrk syscall

    ; R5 already has the aligned size we need
0x0004351C       MOV R1 R5             ; R1 = size to allocate
0x00043520       SVC SYS_SBRK          ; Call kernel: sbrk(size)

    ; Check if sbrk failed (returns -1 or 0 on error)
0x00043524       CMP R1 0              ; Did sbrk return 0 or negative?
0x00043528       BLT malloc_error      ; If error, return NULL

    ; Step 5: sbrk succeeded, we have new memory at address in R1
    ; Now we need to add this new block to our table

    ; Find an empty slot in the block table
0x00043530       LI R4 0               ; Start at first block

malloc_add:
    ; Check if we've searched all blocks
0x00043538       CMP R4 MAX_BLOCKS
0x0004353C       BGE malloc_error      ; No empty slot! (shouldn't happen)

    ; Get descriptor address
0x00043544       LI R2 block_table
0x0004354C       LI R3 BLOCK_DESC
0x00043554       MUL R3 R4 R3
0x00043558       ADD R2 R2 R3        ; &block[indexR4]

    ; Check if this slot is free (USED flag = 0)
0x0004355C       LDW R3 [R2 + BLOCK_USED]
0x00043560       CMP R3 0
0x00043564       BEQ malloc_add_found  ; Found an empty slot!

    ; Slot is used, try next one
0x0004356C       ADD R4 R4 1
0x00043570       B malloc_add

malloc_add_found:
    ; We found an empty slot at R2
    ; Store the new block's information

    ; Store the address (R1 from sbrk)
0x00043578       STW R1 [R2 + BLOCK_ADDR]   ; block.address = address from sbrk

    ; Store the size (R5 = aligned size)
0x0004357C       STW R5 [R2 + BLOCK_SIZE]   ; block.size = size

    ; Mark as used (USED = 1)
0x00043580       LI R3 1
0x00043588       STW R3 [R2 + BLOCK_USED]   ; block.used = 1

    ; R1 already has the address from sbrk, so just return it
0x0004358C       B malloc_done

malloc_error:
    ; Something went wrong - return NULL (0)
0x00043594       LI R1 0

malloc_done:
0x0004359C       POP LR                ; Restore return address
0x000435A0       RET                   ; Return to caller with R1 = pointer or NULL

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
0x000435A4       PUSH LR

    ; Step 1: Check if pointer is NULL
0x000435A8       CMP R1 0              ; Is R1 == 0?
0x000435AC       BEQ free_done         ; If NULL, nothing to free, just return

    ; Step 2: Search the block table for this address
0x000435B4       LI R4 0               ; Start at first block

free_loop:
    ; Check if we've searched all blocks
0x000435BC       CMP R4 MAX_BLOCKS
0x000435C0       BGE free_done         ; Not found - ignore (could be invalid pointer)

    ; Get descriptor address
0x000435C8       LI R2 block_table
0x000435D0       LI R3 BLOCK_DESC      ; length of one block descriptor
0x000435D8       MUL R3 R4 R3          ; r4 block idx
0x000435DC       ADD R2 R2 R3          ; R2 = &block[i]

    ; Check if this block's address matches the pointer
0x000435E0       LDW R3 [R2 + BLOCK_ADDR]  ; R3 =  &block[i].block address
0x000435E4       CMP R3 R1             ; Is this our block?
0x000435E8       BEQ free_found        ; Yes, we found it!

    ; Not this block, try next
0x000435F0       ADD R4 R4 1
0x000435F4       B free_loop

free_found:
    ; Step 3: We found the block descriptor at R2
    ; Mark it as free so malloc can use it again

0x000435FC       LI R3 0               ; R3 = 0 (free)
0x00043604       STW R3 [R2 + BLOCK_USED]  ; &block[i].used = 0

    ; NOTE: We do NOT clear the address or size
    ; They stay in the table and will be overwritten when reused

free_done:
    ; Clean up and return
0x00043608       POP LR
0x0004360C       RET

;------------------------------------------------------------------------------
; malloc_init - Initialize the memory allocator
;
; Clears the entire block table so all blocks are marked as free
; Should be called once at system startup before using malloc
;------------------------------------------------------------------------------
malloc_init:
    ; Save registers
0x00043610       PUSH LR
    ; Step 1: Clear the entire block table
    ; Set all bytes in block_table to 0
0x00043614       LI R1 block_table     ; R1 = start address of table
0x0004361C       LI R3 MAX_BLOCKS * BLOCK_DESC  ; R3 = total bytes to clear

malloc_init_loop:
0x00043624       CMP R3 0              ; Have we cleared all bytes?
0x00043628       BEQ malloc_init_done  ; Yes, we're done

0x00043630       LI R2 0               ; R2 = 0 (value to write)
0x00043638       STB R2 [R1]           ; Store 0 at current address
0x0004363C       ADD R1 R1 1           ; Move to next byte
0x00043640       SUB R3 R3 1           ; Decrement byte counter
0x00043644       B malloc_init_loop    ; Continue

malloc_init_done:
    ; Clean up and return
0x0004364C       POP LR
0x00043650       RET


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
0x00043654       PUSH LR
0x00043658       PUSH R8
0x0004365C       PUSH R9
0x00043660       PUSH R10
0x00043664       PUSH R11
0x00043668       PUSH R12

0x0004366C       MOV  R8  R1          ; Save destination

0x00043670       MOV  R9  R2          ; Working value
0x00043674       MOV  R11 R3          ; Base
0x00043678       MOV  R12 R4          ; Sign flag
    ;MOV  R10 R5          ; Temp buffer size

    ; Allocate temp buffer (size passed in R5)
0x0004367C       SUB  SP SP R5
0x00043680       MOV  R10 R1          ; Keep original pointer
0x00043684       MOV  R6  SP          ; Temp buffer pointer
0x00043688       push R5              ; save R5 for frame leave
0x0004368C       MOV  R7  R6          ; Save start of temp buffer

    ; Check for sign (if signed and negative)
0x00043690       CMP  R12 1
0x00043694       BNE  itoa_core_unsigned

0x0004369C       CMP  R9 0
0x000436A0       BGE  itoa_core_unsigned

    ; Negative number - add minus sign
0x000436A8       LI   R2 45     ;'-'
0x000436B0       STB  R2 [R8]
0x000436B4       ADD  R8 R8 1
0x000436B8       NOT  R9 R9
0x000436BC       ADD  R9 R9 1
    ;NEG  R9              ; Make positive

itoa_core_unsigned:
    ; Special case: zero
0x000436C0       CMP  R9 0
0x000436C4       BNE  itoa_core_convert

0x000436CC       LI   R2 48    ; '0'
0x000436D4       STB  R2 [R8]
0x000436D8       ADD  R8 R8 1
0x000436DC       LI   R2 0
0x000436E4       STB  R2 [R8]
0x000436E8       B    itoa_core_finish

itoa_core_convert:
0x000436F0       LI   R4 0            ; Digit counter

itoa_core_divloop:
0x000436F8       MOV  R5 R9
0x000436FC       DIV  R6 R5 R11       ; R6 = quotient, R9 = remainder
0x00043700       MOD  R7 R9 R11       ; R7 = remainder

    ; Convert digit to ASCII based on base
0x00043704       CMP  R11 16
0x00043708       BEQ  itoa_core_hex_digit

    ; Base 2 or 10: digit 0-9
0x00043710       ADD  R7 R7 48        ; '0' + digit
0x00043714       B    itoa_core_store

itoa_core_hex_digit:
    ; Base 16: digit 0-15
0x0004371C       CMP  R7 9
0x00043720       BGT  itoa_core_hex_letter
0x00043728       ADD  R7 R7 48        ; '0' + digit
0x0004372C       B    itoa_core_store

itoa_core_hex_letter:
0x00043734       SUB  R7 R7 10
0x00043738       ADD  R7 R7 65        ; 'A' + (digit-10)

itoa_core_store:
0x0004373C       STB  R7 [R6]         ; Store in temp buffer
0x00043740       ADD  R6 R6 1
0x00043744       ADD  R4 R4 1         ; Increment digit count

0x00043748       MOV  R9 R5           ; Quotient becomes new value
0x0004374C       CMP  R9 0
0x00043750       BNE  itoa_core_divloop

    ; Point to last digit
0x00043758       SUB  R6 R6 1

itoa_core_copy:
0x0004375C       CMP  R4 0
0x00043760       BEQ  itoa_core_done

0x00043768       LDB  R2 [R6]         ; Get digit from temp (reverse order)
0x0004376C       STB  R2 [R8]         ; Store in destination
0x00043770       ADD  R8 R8 1
0x00043774       SUB  R6 R6 1
0x00043778       SUB  R4 R4 1
0x0004377C       B    itoa_core_copy

itoa_core_done:
0x00043784       LI   R2 0
0x0004378C       STB  R2 [R8]         ; Null terminate

itoa_core_finish:
0x00043790       POP  R5
    ; Clean up temp buffer
0x00043794       ADD  SP SP R5

    ; Return original pointer
0x00043798       MOV  R1 R10

0x0004379C       POP  R12
0x000437A0       POP  R11
0x000437A4       POP  R10
0x000437A8       POP  R9
0x000437AC       POP  R8
0x000437B0       POP  LR
0x000437B4       RET

;---------------------------------------------------------
; itoa_dec - Decimal conversion wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_dec:
0x000437B8       PUSH LR

    ; Max 11 digits + sign + null = 13 bytes
0x000437BC       LI   R3 10           ; Base 10
0x000437C4       LI   R4 1            ; Signed
0x000437CC       LI   R5 13           ; Temp buffer size
0x000437D4   CALL itoa_core

0x000437DC       POP  LR
0x000437E0       RET

;---------------------------------------------------------
; itoa_hex - Hexadecimal conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_hex:
0x000437E4       PUSH LR

    ; Max 8 digits + null = 9 bytes
0x000437E8       LI   R3 16           ; Base 16
0x000437F0       LI   R4 0            ; Unsigned (shows raw bits)
0x000437F8       LI   R5 9            ; Temp buffer size
0x00043800   CALL itoa_core

0x00043808       POP  LR
0x0004380C       RET

;---------------------------------------------------------
; itoa_bin - Binary conversion wrapper
;
; R1 = destination buffer
; R2 = unsigned integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_bin:
0x00043810       PUSH LR

    ; Max 32 bits + null = 33 bytes
0x00043814       LI   R3 2            ; Base 2
0x0004381C       LI   R4 0            ; Unsigned (shows raw bits)
0x00043824       LI   R5 33           ; Temp buffer size
0x0004382C   CALL itoa_core

0x00043834       POP  LR
0x00043838       RET

;---------------------------------------------------------
; itoa_signed_hex - Signed hexadecimal wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_hex:
0x0004383C       PUSH LR

    ; Max 8 digits + sign + null = 10 bytes
0x00043840       LI   R3 16           ; Base 16
0x00043848       LI   R4 1            ; Signed (shows sign)
0x00043850       LI   R5 10           ; Temp buffer size
0x00043858   CALL itoa_core

0x00043860       POP  LR
0x00043864       RET

;---------------------------------------------------------
; itoa_signed_bin - Signed binary wrapper
;
; R1 = destination buffer
; R2 = signed integer
; Returns: R1 = original buffer pointer
;---------------------------------------------------------
itoa_signed_bin:
0x00043868       PUSH LR

    ; Max 32 bits + sign + null = 34 bytes
0x0004386C       LI   R3 2            ; Base 2
0x00043874       LI   R4 1            ; Signed (shows sign)
0x0004387C       LI   R5 34           ; Temp buffer size
0x00043884   CALL itoa_core

0x0004388C       POP  LR
0x00043890       RET

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
0x00043894       PUSH LR
0x00043898       MOV R3 R1              ; Save original destination pointer
0x0004389C       MOV R4 R2              ; Save source pointer

strcpy_loop:
0x000438A0       LDB R2 [R4]            ; Load byte from source
0x000438A4       STB R2 [R1]            ; Store byte to destination

0x000438A8       CMP R2 0               ; Check if it's null terminator
0x000438AC       BEQ strcpy_done        ; If zero, we're done

0x000438B4       ADD R1 R1 1            ; Advance destination pointer
0x000438B8       ADD R4 R4 1            ; Advance source pointer
0x000438BC       B strcpy_loop

strcpy_done:
0x000438C4       MOV R1 R3              ; Return original destination pointer
0x000438C8       POP LR
0x000438CC       RET


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
0x000438D0       PUSH LR
0x000438D4       PUSH R8
0x000438D8       PUSH R9

0x000438DC       MOV R8 R1            ; Save path
    ; Open directory with read-only flags (same as your ls.asm)
0x000438E0       MOV R1 R8
0x000438E4       LI  R2 O_RDONLY
0x000438EC       SVC SYS_OPEN
0x000438F0       MOV R9 R1           ;fd
0x000438F4       CMP R1 0
0x000438F8       BLT opendir_error

    ; Allocate DIR structure (small, just fd and offset)
0x00043900       PUSH R9                 ;save R9 jic
0x00043904       LI R1 DIR_SIZEOF
0x0004390C   CALL malloc
0x00043914       POP  R9

0x00043918       CMP R1 0
0x0004391C       BEQ opendir_error_close

0x00043924       MOV R8 R1            ; Save DIR*

    ; Initialize DIR structure
    ; R2 still has fd from open
0x00043928       STW R9 [R8 + DIR_FD]
0x0004392C       LI  R2 0
0x00043934       STW R2 [R8 + DIR_OFFSET]

0x00043938       MOV R1 R8            ; Return DIR*
0x0004393C       B opendir_done

opendir_error_close:
0x00043944       MOV R1 R9            ; fd is in R9
0x00043948       SVC SYS_CLOSE
0x0004394C       LI R1 0
0x00043954       B opendir_done

opendir_error:
0x0004395C       LI R1 0

opendir_done:
0x00043964       POP R9
0x00043968       POP R8
0x0004396C       POP LR
0x00043970       RET

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
0x00043974       PUSH LR
0x00043978       PUSH R8
0x0004397C       PUSH R9

0x00043980       MOV R8 R1            ; DIR*
0x00043984       MOV R9 R2            ; User's dirent buffer

    ; Check if DIR pointer is valid
0x00043988       CMP R8 0
0x0004398C       BEQ readdir_error

    ; Read one dirent from directory fd using current offset
0x00043994       LDW R1 [R8 + DIR_FD] ; fd

    ; Use the directory's offset - we need to implement lseek or use
    ; the fact that each read gets one dirent at a time from tarfs
0x00043998       MOV R2 R9            ; user buffer
0x0004399C       LI  R3 DIRENT_SIZEOF ; size of one dirent
0x000439A4       SVC SYS_READ
0x000439A8       CMP R1 0
0x000439AC       BEQ readdir_end      ; EOF
0x000439B4       CMP R1 DIRENT_SIZEOF
0x000439B8       BNE readdir_error    ; Short read or error

    ; Entry read successfully
    ; Update the offset in DIR structure
0x000439C0       LDW R2 [R8 + DIR_OFFSET]
0x000439C4       ADD R2 R2 1
0x000439C8       STW R2 [R8 + DIR_OFFSET]

0x000439CC       LI R1 1              ; Return success
0x000439D4       B readdir_done

readdir_error:
0x000439DC       LI R1 -1
0x000439E4       B readdir_done

readdir_end:
0x000439EC       LI R1 0

readdir_done:
0x000439F4       POP R9
0x000439F8       POP R8
0x000439FC       POP LR
0x00043A00       RET

;------------------------------------------------------------------------------
; closedir - Close directory stream
;
; IN:  R1 = DIR*
; OUT: R1 = 0 on success, -1 on error
;------------------------------------------------------------------------------
closedir:
0x00043A04       PUSH LR
0x00043A08       PUSH R8

0x00043A0C       MOV R8 R1
0x00043A10       CMP R8 0
0x00043A14       BEQ closedir_error

    ; Close the directory fd
0x00043A1C       LDW R1 [R8 + DIR_FD]
0x00043A20       SVC SYS_CLOSE

    ; Free the DIR structure
0x00043A24       MOV R1 R8
0x00043A28   CALL free

0x00043A30       LI R1 0
0x00043A38       B closedir_done

closedir_error:
0x00043A40       LI R1 -1

closedir_done:
0x00043A48       POP R8
0x00043A4C       POP LR
0x00043A50       RET

;------------------------------------------------------------------------------
; rewinddir - Reset directory stream to beginning
;
; IN:  R1 = DIR*
;------------------------------------------------------------------------------
rewinddir:
0x00043A54       CMP R1 0
0x00043A58       BEQ rewinddir_done

0x00043A60       LI R2 0
0x00043A68       STW R2 [R1 + DIR_OFFSET]

    ; Need to seek to beginning of directory
    ; For tarfs, this means closing and reopening, or using lseek
    ; Simple approach: close and reopen
0x00043A6C       PUSH LR
0x00043A70       PUSH R8

0x00043A74       MOV R8 R1
    ; Save the path - we don't have it stored, so this is tricky
    ; In a real implementation, store path in DIR structure

    ; For now, just reset offset and rely on readdir's behavior

0x00043A78       POP R8
0x00043A7C       POP LR

rewinddir_done:
0x00043A80       RET

;------------------------------------------------------------------------------
; dirfd - Get file descriptor from DIR*
;
; IN:  R1 = DIR*
; OUT: R1 = file descriptor, or -1 on error
;------------------------------------------------------------------------------
dirfd:
0x00043A84       CMP R1 0
0x00043A88       BEQ dirfd_error

0x00043A90       LDW R1 [R1 + DIR_FD]
0x00043A94       RET

dirfd_error:
0x00043A98       LI R1 -1
0x00043AA0       RET

;------------------------------------------------------------------------------
; Helper: is_dir - Check if a path is a directory
;
; IN:  R1 = path
; OUT: R1 = 1 if directory, 0 if not, -1 on error
;------------------------------------------------------------------------------
is_dir:
0x00043AA4       PUSH LR

    ; Try to open as directory
0x00043AA8   CALL opendir
0x00043AB0       CMP R1 0
0x00043AB4       BEQ is_dir_not_dir

    ; It opened as a directory
0x00043ABC       MOV R2 R1            ; Save DIR*
0x00043AC0       LI R1 1              ; Return true
0x00043AC8   CALL closedir
0x00043AD0       B is_dir_done

is_dir_not_dir:
0x00043AD8       LI R1 0

is_dir_done:
0x00043AE0       POP LR
0x00043AE4       RET

;------------------------------------------------------------------------------
; Example usage function - list directory contents (like ls)
; This demonstrates how to use opendir/readdir/closedir
;------------------------------------------------------------------------------
list_directory:
0x00043AE8       PUSH LR
0x00043AEC       PUSH R8
0x00043AF0       PUSH R9

0x00043AF4       MOV R8 R1            ; path

    ; Allocate dirent on stack
0x00043AF8       SUB SP SP DIRENT_SIZEOF
0x00043AFC       MOV R9 SP

    ; Open directory
0x00043B00       MOV R1 R8
0x00043B04   CALL opendir
0x00043B0C       CMP R1 0
0x00043B10       BEQ list_dir_error

0x00043B18       MOV R8 R1            ; DIR*

list_dir_loop:
0x00043B1C       MOV R1 R8
0x00043B20       MOV R2 R9
0x00043B24   CALL readdir
0x00043B2C       CMP R1 0
0x00043B30       BEQ list_dir_close
0x00043B38       LI  R2 -1
0x00043B40       CMP R1 R2
0x00043B44       BEQ list_dir_error

    ; Print the name
0x00043B4C       ADD R1 R9 DIRENT_NAME
0x00043B50   CALL puts

    ; If it's a directory, print '/'
0x00043B58       LDW R2 [R9 + DIRENT_TYPE]
0x00043B5C       CMP R2 DT_DIR
0x00043B60       BNE list_dir_not_dir

0x00043B68       LI R1 slash_char
0x00043B70   CALL putchar

list_dir_not_dir:
0x00043B78       LI R1 newline_char
0x00043B80   CALL putchar

0x00043B88       B list_dir_loop

list_dir_close:
0x00043B90       MOV R1 R8
0x00043B94   CALL closedir
0x00043B9C       LI R1 0
0x00043BA4       B list_dir_done

list_dir_error:
0x00043BAC       LI R1 -1

list_dir_done:
0x00043BB4       ADD SP SP DIRENT_SIZEOF
0x00043BB8       POP R9
0x00043BBC       POP R8
0x00043BC0       POP LR
0x00043BC4       RET

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

0x00043BD0       RET



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
0x00043BDA       PUSH LR
0x00043BDE       PUSH R6
0x00043BE2       PUSH R7
0x00043BE6       PUSH R8
0x00043BEA       PUSH R9
0x00043BEE       PUSH R10
0x00043BF2       PUSH R11
0x00043BF6       PUSH R12

    ; allocate 76-byte buffer on stack for directory entry
0x00043BFA       LI  R3 DIRENT_SIZEOF
0x00043C02       SUB SP SP R3
0x00043C06       MOV R12 SP              ; R12 = pointer to struct dirent buffer

0x00043C0A       MOV R8 R1               ; R8 = argc
0x00043C0E       MOV R9 R2               ; R9 = argv

0x00043C12       CMP R8 2                ; Need at least one argument (argv[1])
0x00043C16       BLT usage



0x00043C1E       LI R10 1                ; R10 = current argument index (argv[1])
0x00043C26       LI R6 0                 ; R6 = return code (0 = success)

dir_loop:
0x00043C2E       CMP R10 R8              ; if index >= argc, done
0x00043C32       BGE dir_done

    ; Get the path string from argv[index]
0x00043C3A       MOV R2 R10
0x00043C3E       SHL R2 R2 2
0x00043C42       ADD R2 R9 R2
0x00043C46       LDW R1 [R2]             ; R1 = directory path (e.g., "etc/")
0x00043C4A       PUSH R1

    ; Print header: "\n--- Directory: path ---\n"
0x00043C4E       LI R1 newline_str
0x00043C56   CALL puts
0x00043C5E       LI R1 dir_header_prefix
0x00043C66   CALL puts
    ; print the directory name
0x00043C6E       MOV R2 R10
0x00043C72       SHL R2 R2 2
0x00043C76       ADD R2 R9 R2
0x00043C7A       LDW R1 [R2]
0x00043C7E   CALL puts
0x00043C86       LI R1 dir_header_suffix
0x00043C8E   CALL puts
0x00043C96       LI R1 newline_str
0x00043C9E   CALL puts

    ; open directory using opendir wrapper
0x00043CA6       POP R1                  ; path
0x00043CAA   CALL opendir

0x00043CB2       MOV R11 R1              ; R11 = DIR* handle

0x00043CB6       CMP R11 0
0x00043CBA       BEQ open_failed         ; opendir returns 0 on error

read_dir_loop:
    ; Read next directory entry
0x00043CC2       MOV R1 R11              ; DIR*
0x00043CC6       MOV R2 R12              ; pointer to dirent buffer
0x00043CCA   CALL readdir
0x00043CD2       CMP R1 0
0x00043CD6       BEQ read_done           ; EOF
0x00043CDE       LI  R2 -1
0x00043CE6       CMP R1 R2
0x00043CEA       BEQ read_done           ; error

    ; parse the directory entry
0x00043CF2       LDW R5 [R12 + DIRENT_TYPE]   ; R5 = d_type (DT_REG or DT_DIR)

    ; print filename (null-terminated at R12 + DIRENT_NAME)
0x00043CF6       ADD R1 R12 DIRENT_NAME
0x00043CFA   CALL puts

    ; if directory, print '/'
0x00043D02       CMP R5 DT_DIR
0x00043D06       BNE not_dir_entry
0x00043D0E       LI R1 slash_str
0x00043D16   CALL puts
not_dir_entry:

    ; print newline
0x00043D1E       LI R1 newline_str
0x00043D26   CALL puts

0x00043D2E       B read_dir_loop

read_done:
    ; close directory using closedir wrapper
0x00043D36       MOV R1 R11
0x00043D3A   CALL closedir

0x00043D42       ADD R10 R10 1           ; next directory
0x00043D46       B dir_loop

open_failed:
    ; print error message for this directory
0x00043D4E       LI R1 error_prefix
0x00043D56   CALL puts
    ; print the directory name
0x00043D5E       MOV R2 R10
0x00043D62       SHL R2 R2 2
0x00043D66       ADD R2 R9 R2
0x00043D6A       LDW R1 [R2]
0x00043D6E   CALL puts
0x00043D76       LI R1 ls_newline_str
0x00043D7E   CALL puts

0x00043D86       LI R6 1                 ; set return code to error
0x00043D8E       ADD R10 R10 1           ; next directory
0x00043D92       B dir_loop

dir_done:
    ; free buffer
0x00043D9A       LI  R3 DIRENT_SIZEOF
0x00043DA2       ADD SP SP R3

0x00043DA6       MOV R1 R6               ; return code
0x00043DAA       POP R12
0x00043DAE       POP R11
0x00043DB2       POP R10
0x00043DB6       POP R9
0x00043DBA       POP R8
0x00043DBE       POP R7
0x00043DC2       POP R6
0x00043DC6       POP LR
0x00043DCA       RET

;==============================================================================
; usage - Print usage message and exit
;==============================================================================
usage:
0x00043DCE       LI R1 usage_str
0x00043DD6   CALL puts
0x00043DDE       LI R6 1                 ; error
0x00043DE6       B dir_done

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
