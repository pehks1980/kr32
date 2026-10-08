.org 0x00043000

;==============================================================================
; rm - Remove files
; Usage:
;   rm file ...
;
; Remove each pathname(file) supplied on the command line.
;
; main:
;   IN:  R1 = argc
;        R2 = argv
;
;   OUT: R1 = 0 on success
;        R1 = 1 if any file could not be removed
;
;==============================================================================

#include "../lib/libc.inc"


;==============================================================================
; main
;==============================================================================

main:
    PUSH LR
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11

    MOV R8 R1                  ; R8 = argc
    MOV R9 R2                  ; R9 = argv

    ; Need at least one pathname
    CMP R8 2
    BLT usage

    LI R10 1                   ; R10 = current argv index
    LI R6 0                    ; R6 = return code
                               ; 0 = all successful
                               ; 1 = at least one failure

;==============================================================================
; Process next pathname
;==============================================================================

unlink_loop:

    CMP R10 R8
    BGE unlink_done

    ;----------------------------------------------------------
    ; Get argv[R10]
    ;
    ; R2 = &argv[index]
    ; R1 = argv[index] = pathname
    ;----------------------------------------------------------

    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2

    LDW R1 [R2]                ; R1 = pathname
    li  R2 0                   ; NS=0


    ;----------------------------------------------------------
    ; unlink(pathname)
    ;----------------------------------------------------------

    BL unlink

    MOV R11 R1                ; R11 = return value

    ; negative = failure
    CMP R11 0
    BLT remove_failed

    ADD R10 R10 1
    B unlink_loop


;==============================================================================
; Creation failed
;==============================================================================

remove_failed:

    ; Print:
    ;   rm: cannot remove <pathname>

    LI R1 error_prefix
    BL puts

    ; argv[R10]

    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2

    LDW R1 [R2]
    BL puts

    LI R1 newline_str_unlink
    BL puts

    LI R6 1                    ; remember failure

    ADD R10 R10 1
    B unlink_loop


;==============================================================================
; Done
;==============================================================================

unlink_done:

    MOV R1 R6                  ; return status

    POP R11
    POP R10
    POP R9
    POP R8
    POP R7
    POP R6
    POP LR

    RET


;==============================================================================
; Usage
;==============================================================================

usage:

    LI R1 unlink_usage_str
    BL puts

    LI R1 1
    B unlink_done


;==============================================================================
; Data
;==============================================================================

unlink_usage_str:
    .ASCIIZ "usage: rm file ...\n"

error_prefix:
    .ASCIIZ "rm: cannot remove "

newline_str_unlink:
    .ASCIIZ "\n"