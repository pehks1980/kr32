;==============================================================================
; KR32 print
;
; Usage:
;
;   print FORMAT ARG1 ARG2 ARG3
;
; Example:
;
;   print "a=%d b=%d c=%d\n" 10 20 30
;
; The first argument after the program name is the format string.
; Up to three following arguments are converted from decimal strings.
;
; Missing arguments are treated as zero.
;==============================================================================

.org 0x00043000
; from USER_CODE_VA

#include "../lib/libc.inc"

main:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11

    MOV R8 R1            ; argc
    MOV R9 R2            ; argv

    ;--------------------------------------------------
    ; Need at least:
    ;
    ; argv[0] = "print"
    ; argv[1] = format
    ;--------------------------------------------------

    CMP R8 2
    BLT print_usage

    ;--------------------------------------------------
    ; R2 = argv[1] = format
    ;--------------------------------------------------

    LDW R1 [R9 + 4]
    MOV R10 R1           ; R10 = format string

    ;--------------------------------------------------
    ; Default parameters = 0
    ;--------------------------------------------------

    LI R2 0
    LI R3 0
    LI R4 0

    ;--------------------------------------------------
    ; argv[2]
    ;--------------------------------------------------

    CMP R8 3
    BLT print_arg2_done

    LDW R1 [R9 + 8]
    BL atoi             ;that is only in this first version assume args are numbers!
    MOV R2 R1

print_arg2_done:

    ;--------------------------------------------------
    ; argv[3]
    ;--------------------------------------------------

    CMP R8 4
    BLT print_arg3_done

    LDW R1 [R9 + 12]
    BL atoi
    MOV R3 R1

print_arg3_done:

    ;--------------------------------------------------
    ; argv[4]
    ;--------------------------------------------------

    CMP R8 5
    BLT print_arg4_done

    LDW R1 [R9 + 16]
    BL atoi
    MOV R4 R1

print_arg4_done:

    ;--------------------------------------------------
    ; printf(format, arg1, arg2, arg3)
    ;
    ; R1 = format
    ; R2 = arg1
    ; R3 = arg2
    ; R4 = arg3
    ;--------------------------------------------------

    MOV R1 R10
    BL printf

    LI R1 0
    B print_done


print_usage:

    LI R1 usage_msg
    BL puts

    LI R1 1


print_done:

    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET


;==============================================================================
; Data
;==============================================================================

usage_msg:
    .ASCIIZ "usage: print FORMAT [ARG1] [ARG2] [ARG3]"