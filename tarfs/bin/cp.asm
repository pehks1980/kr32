.org 0x00043000

;==============================================================================
; cp - Copy one file to another
;
; Usage:
;   cp source dest
;
; Copies source to dest using read/write syscalls. The destination is created in
; the writable NSFS overlay when it does not already exist.
;==============================================================================

#include "../lib/libc.inc"

main:
    PUSH LR
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    ; 128 bytes keeps nsfs FILE_APPEND payloads inside the 256-byte kernel buffer.
    LI R3 128
    SUB SP SP R3
    MOV R12 SP

    MOV R8 R1                  ; argc
    MOV R9 R2                  ; argv
    LI R6 1                    ; default return code = failure
    LI R10 -1                  ; source fd
    LI R11 -1                  ; destination fd

    CMP R8 3
    BNE usage

    ; src = argv[1]
    LDW R1 [R9 + 4]
    LI R2 O_RDONLY
    BL open
    MOV R10 R1
    CMP R10 0
    BLT open_src_failed

    ; dest = argv[2], O_CREATE | O_WRONLY
    LDW R1 [R9 + 8]
    LI R2 0x11
    BL open
    MOV R11 R1
    CMP R11 0
    BLT open_dst_failed

copy_loop:
    MOV R1 R10
    MOV R2 R12
    LI R3 128
    BL read
    MOV R7 R1

    CMP R7 0
    BLT read_failed
    BEQ copy_success

    MOV R1 R11
    MOV R2 R12
    MOV R3 R7
    BL write
    CMP R1 R7
    BNE write_failed

    B copy_loop

copy_success:
    LI R6 0
    B cleanup

usage:
    LI R1 cp_usage_str
    BL puts
    B cleanup

open_src_failed:
    LI R1 cp_cannot_open
    BL puts
    LDW R1 [R9 + 4]
    BL puts
    LI R1 cp_newline
    BL puts
    B cleanup

open_dst_failed:
    LI R1 cp_cannot_create
    BL puts
    LDW R1 [R9 + 8]
    BL puts
    LI R1 cp_newline
    BL puts
    B cleanup

read_failed:
    LI R1 cp_read_error
    BL puts
    B cleanup

write_failed:
    LI R1 cp_write_error
    BL puts
    B cleanup

cleanup:
    CMP R11 0
    BLT cleanup_src
    MOV R1 R11
    BL close

cleanup_src:
    CMP R10 0
    BLT cleanup_done
    MOV R1 R10
    BL close

cleanup_done:
    LI R2 128
    ADD SP SP R2
    MOV R1 R6
    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP R7
    POP R6
    POP LR
    RET

cp_usage_str:
    .ASCIIZ "usage: cp source dest\n"

cp_cannot_open:
    .ASCIIZ "cp: cannot open "

cp_cannot_create:
    .ASCIIZ "cp: cannot create "

cp_read_error:
    .ASCIIZ "cp: read error\n"

cp_write_error:
    .ASCIIZ "cp: write error\n"

cp_newline:
    .ASCIIZ "\n"
