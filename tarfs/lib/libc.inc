;==============================================================================
; Minimal KR32 userland libc scaffold
; Intended to be included by user binaries before assembly.
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
    RET

;==============================================================================
; strcmp - Compare two strings
; IN:  R1 = string1, R2 = string2
; OUT: R1 = 1 if equal, 0 if different
;==============================================================================
strcmp:
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
    RET

;==============================================================================
; memcpy - Copy memory block
; IN:  R1 = dest, R2 = src, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memcpy:
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
    RET

;==============================================================================
; memset - Fill memory with constant byte
; IN:  R1 = dest, R2 = value, R3 = count
; OUT: R1 = dest (end position)
;==============================================================================
memset:
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