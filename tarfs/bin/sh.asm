.org 0x00043000
; ================================================================
; /bin/sh – Minimal shell (version 0) using libc
; ================================================================

#include "../lib/libc.inc"

.EQU STDIN_FD,  0

;---------------------------------------------------------------
; main() – shell loop
;---------------------------------------------------------------
main:
    PUSH LR

shell_loop:
    ; Print prompt
    LI R1 STDOUT_FD
    LI R2 prompt
    LI R3 2
    CALL write
    ; Read command
    LI R1 STDIN_FD
    LI R2 input_buf
    LI R3 127
    CALL read
    debug 2
    CMP R1 0
    BLE exit_shell
    MOV R4 R1           ; R4 = bytes read

    ; ---- Normalize line editing characters before parsing ----
    ; Treat BS/DEL as a backspace in the current command buffer.
    LI R8 input_buf
    LI R9 input_buf
    LI R10 0            ; source index

normalize_input_loop:
    CMP R10 R4
    BGE normalize_input_done

    ADD R5 R8 R10
    LDB R6 [R5]

    CMP R6 10            ; LF
    BEQ normalize_input_next
    CMP R6 13            ; CR
    BEQ normalize_input_next
    CMP R6 8             ; BS
    BEQ normalize_input_backspace
    CMP R6 127           ; DEL
    BEQ normalize_input_backspace

    STB R6 [R9]
    ADD R9 R9 1
    B normalize_input_next

normalize_input_backspace:
    CMP R9 R8
    BLE normalize_input_next
    SUB R9 R9 1
    B normalize_input_next

normalize_input_next:
    ADD R10 R10 1
    B normalize_input_loop

normalize_input_done:
    LI R6 0
    STB R6 [R9]

    ; Skip empty lines
    LI R7 input_buf
    LDB R6 [R7]
    CMP R6 0
    BEQ shell_loop

    CALL parse_command

    LI R1 input_buf
    LI R2 quit_cmd
    CALL strcmp
    CMP R1 1
    BEQ exit_shell  ;if type "quit" exit shell
    
    ; ---- Fork ----
    CALL fork
    CMP R1 0
    BEQ child_process
    BLT fork_error

    ;Debug 2
    ;POP LR
    ;RET

    ; ---- Parent: wait for child ----
    LI R1 -1
    LI R2 0
    CALL waitpid
    CMP R1 0
    BLT wait_error

    B shell_loop

    ; ---- Child: execute command ----
child_process:
    ; pathname = input_buf (copied early by kernel, before data page zeroed)
    ; argv = argv_buf
    LI R1 input_buf
    LI R2 argv_buf
    LI R3 0
    CALL execve
    LI R1 exec_failed_msg
    CALL puts

    POP LR
    RET

fork_error:
    LI R1 fork_error_msg
    CALL puts
    B shell_loop

wait_error:
    LI R1 wait_error_msg
    CALL puts
    B shell_loop

exit_shell:
    POP LR
    RET

; ---------------------------------------------------------------
; parse_command() – parse input_buf into argv_buf
; input and output:
;   input_buf: null-terminated string of command line
;   output: all needed for execve (input_buf = pathname, argv_buf = argv) ready
; ---------------------------------------------------------------

parse_command:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11

    LI R8 input_buf
    LI R9 argv_buf
    LI R10 0

parse_skip_spaces:
    LDB R11 [R8]
    CMP R11 32      ;" "
    BNE parse_token_start
    LI R11 0        ;replace space with null so input_buf gets str.split(' ') into args strings
    STB R11 [R8]
    ADD R8 R8 1
    B parse_skip_spaces

parse_token_start:
    LDB R11 [R8]
    CMP R11 0
    BEQ parse_done
    CMP R10 8       ;up to 8 args
    BGE parse_done

    STW R8 [R9]     ;store pointer to token in argv_buf (argv array for execve)
    ADD R9 R9 4
    ADD R10 R10 1   ;argc for execve

parse_token_body:
    LDB R11 [R8]
    CMP R11 0
    BEQ parse_done
    CMP R11 32      ;" "
    BEQ parse_end_token
    ADD R8 R8 1
    B parse_token_body

parse_end_token:
    LI R11 0
    STB R11 [R8]    ; put null terminator at end of token
    ADD R8 R8 1     ; move to next char in input_buf
    B parse_skip_spaces

parse_done:
    LI R11 0
    STW R11 [R9]    ; put null terminator at end of argv_buf (argv array for execve)
    POP R11         ; all needed for execve (input_buf = pathname, argv_buf = argv) ready 
                    ;  and in format for execve
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;---------------------------------------------------------------
; Data
;---------------------------------------------------------------
prompt:
    .ASCIIZ "$ \r"

quit_cmd:
    .ASCIIZ "quit"

exec_failed_msg:
    .ASCIIZ "EXECVE ERR\n"
fork_error_msg:
    .ASCIIZ "FORK ERR\n"
wait_error_msg:
    .ASCIIZ "WAIT ERR\n"

input_buf:
    .SPACE 128

argv_buf:
    .SPACE 36
; ================================================================
; End
; ================================================================
