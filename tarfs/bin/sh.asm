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
    CMP R1 0
    BLE exit_shell
    MOV R4 R1           ; R4 = bytes read
   ; ; ---- Strip CR/LF and null-terminate ----
   LI R5 input_buf
   ADD R5 R5 R4
   LI R8 input_buf  ; R8 start R5 - end

strip_loop:
   CMP R5 R8
   BLE strip_done
   SUB R5 R5 1      ; move end r5 to r8
   LDB R6 [R5]
   CMP R6 10        ; if x0a
   BEQ strip_char
   CMP R6 13        ; x0d
   BEQ strip_char
   ADD R5 R5 1
   LI  R2 0
   STB R2 [R5]
   B strip_done

strip_char:
   LI  R2 0
   STB R2 [R5]
   B strip_loop

strip_done:
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
    BEQ exit_shell
    
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
    CMP R11 32
    BNE parse_token_start
    LI R11 0
    STB R11 [R8]
    ADD R8 R8 1
    B parse_skip_spaces

parse_token_start:
    LDB R11 [R8]
    CMP R11 0
    BEQ parse_done
    CMP R10 8
    BGE parse_done

    STW R8 [R9]
    ADD R9 R9 4
    ADD R10 R10 1

parse_token_body:
    LDB R11 [R8]
    CMP R11 0
    BEQ parse_done
    CMP R11 32
    BEQ parse_end_token
    ADD R8 R8 1
    B parse_token_body

parse_end_token:
    LI R11 0
    STB R11 [R8]
    ADD R8 R8 1
    B parse_skip_spaces

parse_done:
    LI R11 0
    STW R11 [R9]
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;---------------------------------------------------------------
; Data
;---------------------------------------------------------------
prompt:
    .ASCIIZ "$ "

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

ex_path:
    .ASCIIZ "bin/ls5"
; argv[0] is the program name
ex_arg0:
    .ASCIIZ "ls"
; argv[0] = "bin/ls"
; argv[1] = NULL (terminator)
ex_argv:
    .WORD ex_path
    .WORD 0

ls_path:
    .ASCIIZ "bin/ls"

ls_arg0:
    .ASCIIZ "ls"

ls_arg1:
    .ASCIIZ "etc/"

ls_arg2:
    .ASCIIZ "lib/"

ls_argv:
    .WORD ls_path
    .WORD ls_arg1
    .WORD ls_arg2
    .WORD 0
; ================================================================
; End
; ================================================================
