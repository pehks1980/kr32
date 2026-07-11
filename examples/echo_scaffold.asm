; Minimal KR32 userland scaffold.
; Assumes execve enters with a Unix-like initial stack:
;   [argc][argv pointers...][NULL][strings...]
;
; This file is intentionally tiny and is meant to become the first real
; user program ("echo") and a base for a small libc.

.EQU SYS_EXIT,  1
.EQU SYS_WRITE, 4

.EQU STDOUT_FD, 1

.org 0x7000

_start:
    LDW R1 [SP]          ; argc
    ADD R2 SP 4          ; argv
    LI R3 0              ; envp (unused for now)
    BL main
    SVC SYS_EXIT

main:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10

    MOV R8 R1            ; argc
    MOV R9 R2            ; argv
    LI R10 1             ; argv[0] is the program name
    MOV R11 R9
    ADD R11 R11 4        ; argv[1]

echo_next_arg:
    CMP R10 R8
    BGE echo_done

    LDW R1 [R11]
    BL puts

    ADD R10 R10 1
    ADD R11 R11 4
    CMP R10 R8
    BGE echo_newline
    LI R1 space_str
    BL puts
    B echo_next_arg

echo_newline:
    LI R1 newline_str
    BL puts

echo_done:
    LI R1 0
    POP R10
    POP R9
    POP R8
    POP LR
    RET

puts:
    PUSH LR
    PUSH R8
    PUSH R9

    MOV R8 R1            ; string pointer
    BL strlen
    MOV R9 R1            ; length

    LI R1 STDOUT_FD
    MOV R2 R8
    MOV R3 R9
    SVC SYS_WRITE

    POP R9
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

space_str:
    .ASCIIZ " "

newline_str:
    .ASCIIZ "\n"
