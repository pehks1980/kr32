.org 0x00043000
; from USER_CODE_VA
;==============================================================================
; echo - Print all command line arguments
;==============================================================================
; Simple echo implementation that prints each argument separated by spaces,
; followed by a newline. Uses the shared libc scaffold.
;==============================================================================

;library is here so it dtsrtd _start which calls main
#include "../lib/libc.inc"

;==============================================================================
; main - Program entry point
; IN:  R1 = argc, R2 = argv
; OUT: R1 = 0 (always succeeds)
;==============================================================================
main:
    PUSH LR
    PUSH R8              ; 
    PUSH R9              ; 
    PUSH R10             ; Loop counter

    MOV R8 R1            ; R8 = argc
    MOV R9 R2            ; R9 = argv
    LI R10 1             ; Start from argv[1] (skip program name argv[0])
    MOV R11 R9           ; R11 = current argv pointer
    ADD R11 R11 4        ; Skip argv[0] (program name)

echo_next_arg:
    CMP R10 R8           ; Check if we've processed all arguments
    BGE echo_done

    LDW R1 [R11]         ; Load current argument string
    BL puts              ; Print the argument-string

    ADD R10 R10 1        ; Increment argument counter
    ADD R11 R11 4        ; Move to next argv entry
    CMP R10 R8           ; Check if this was the last argument
    BGE echo_newline     ; If last, just print newline
    LI R1 space_str      ; Otherwise print space between arguments
    BL puts
    B echo_next_arg

echo_newline:
    LI R1 newline_str    ; Print final newline
    BL puts

echo_done:

    LI R1 0              ; Return success
    POP R10
    POP R9
    POP R8
    POP LR
    RET