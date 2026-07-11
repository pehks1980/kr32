.org 0x7000

; echo binary using the shared userland libc scaffold.
#include "../lib/libc.inc"

main:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10

    MOV R8 R1
    MOV R9 R2
    LI R10 1
    MOV R11 R9
    ADD R11 R11 4

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
