; Minimal KR32 userland libc scaffold.
; Intended to be included by user binaries before assembly.

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

_start:
    LDW R1 [SP]          ; argc
    ADD R2 SP 4          ; argv
    LI R3 0              ; envp
    BL main
    SVC SYS_EXIT

puts:
    PUSH LR
    PUSH R8
    PUSH R9
    MOV R8 R1
    BL strlen
    MOV R9 R1
    LI R1 STDOUT_FD
    MOV R2 R8
    MOV R3 R9
    SVC SYS_WRITE
    POP R9
    POP R8
    POP LR
    RET

putchar:
    PUSH LR
    PUSH R8
    LI R8 ch_buf
    STB R1 [R8]
    LI R1 STDOUT_FD
    MOV R2 R8
    LI R3 1
    SVC SYS_WRITE
    POP R8
    POP LR
    RET

strlen:
    PUSH R8
    PUSH R9
    MOV R8 R1
    LI R9 0
strlen_loop:
    LDB R2 [R8 + R9]
    CMP R2 0
    BEQ strlen_done
    ADD R9 R9 1
    B strlen_loop
strlen_done:
    MOV R1 R9
    POP R9
    POP R8
    RET

strcmp:
    PUSH R8
    PUSH R9
    PUSH R10
    MOV R8 R1
    MOV R9 R2
strcmp_loop:
    LDB R10 [R8]
    LDB R1 [R9]
    CMP R10 R1
    BNE strcmp_ne
    CMP R10 0
    BEQ strcmp_eq
    ADD R8 R8 1
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
    LDB R1 [R9]
    STB R1 [R8]
    ADD R8 R8 1
    ADD R9 R9 1
    SUB R10 R10 1
    B memcpy_loop
memcpy_done:
    MOV R1 R8
    POP R10
    POP R9
    POP R8
    RET

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
    STB R9 [R8]
    ADD R8 R8 1
    SUB R10 R10 1
    B memset_loop
memset_done:
    MOV R1 R8
    POP R10
    POP R9
    POP R8
    RET

space_str:
    .ASCIIZ " "

newline_str:
    .ASCIIZ "\n"

ch_buf:
    .ASCIIZ "\0"
