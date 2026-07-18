.org 0x00043000
; from USER_CODE_VA
;==============================================================================
; cat - Concatenate and print files
;==============================================================================
; Simple cat implementation that reads each file specified on the command line
; and writes its contents to stdout. If multiple files are given, they are
; concatenated in order. Uses the shared libc scaffold.
;==============================================================================

#include "../lib/libc.inc"

;==============================================================================
; main - Program entry point
; IN:  R1 = argc, R2 = argv
; OUT: R1 = 0 on success, 1 if any file could not be opened
;==============================================================================
main:
    ;NOP
    ;DEBUG 2                 ; testing INVLPG and tlb cache

    PUSH LR
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    ; allocate 256-byte buffer on stack
    LI R3 256
    SUB SP SP R3
    MOV R12 SP              ; R12 = buffer pointer

    MOV R8 R1               ; R8 = argc
    MOV R9 R2               ; R9 = argv

    CMP R8 2                ; Need at least one argument (argv[1])
    BLT usage

    LI R10 1                ; R10 = current argument index (argv[1])
    LI R6 0                 ; R6 = return code (0 = success)

file_loop:
    CMP R10 R8              ; if index >= argc, done
    BGE file_done

    ; open(argv[index], O_RDONLY)
    MOV R2 R10               ; R2 = index * 4 (since argv is an array of pointers)
    SHL R2 R2 2
    ADD R2 R9 R2            ; R2 = address of argv[index]
    LDW R1 [R2]             ; R1 = filename
    LI R2 0                 ; O_RDONLY
    BL open
    MOV R11 R1              ; R11 = fd

    CMP R11 0               ; if fd < 0, error
    BLT open_failed

read_loop:
    ; read(fd, buf, 256)
    MOV R1 R11
    MOV R2 R12
    LI R3 256
    BL read
    MOV R7 R1               ; R7 = bytes read (or -1 on error)

    CMP R7 0
    BLE read_done           ; if <= 0, done (EOF or error)

    ; write(1, buf, n)
    LI R1 1                 ; stdout
    MOV R2 R12
    MOV R3 R7
    BL write

    B read_loop

read_done:
    ; close(fd)
    MOV R1 R11
    BL close

    ADD R10 R10 1           ; next file
    B file_loop

open_failed:
    ; print error message for this file
    LI R1 error_prefix
    BL puts
    ; print the filename
    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2
    LDW R1 [R2]
    BL puts
    LI R1 newline_str
    BL puts

    LI R6 1                 ; set return code to error
    ADD R10 R10 1           ; next file
    B file_loop

file_done:
    ; free buffer
    LI  R2 256
    ADD SP SP R2

    MOV R1 R6               ; return code
    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP R7
    POP R6
    POP LR
    RET

usage:
    LI R1 cat_usage_str
    BL puts
    LI R6 1                 ; error
    B file_done

;==============================================================================
; Data Section
;==============================================================================
cat_usage_str:
    .ASCIIZ "usage: cat file ...\n"
error_prefix:
    .ASCIIZ "cat: cannot open "
newline_str_cat:
    .ASCIIZ "\n"