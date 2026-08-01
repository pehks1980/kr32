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
 ;   LI R1 STDIN_FD
  ;  LI R2 input_buf
  ;  LI R3 12
  ;  CALL read
  ;  CMP R1 0
  ;  BLE exit_shell

  ;  MOV R4 R1           ; R4 = bytes read

   ; ; ---- Strip CR/LF and null-terminate ----
   ; LI R5 input_buf
   ; ADD R5 R5 R4
   ; LI R8 input_buf

;strip_loop:
   ; CMP R5 R8
 ;   BLE strip_done
  ;  SUB R5 R5 1
   ; LDB R6 [R5]
   ; CMP R6 10
   ; BEQ strip_char
   ; CMP R6 13
   ; BEQ strip_char
   ; CMP R6 0
    ;BEQ strip_char
    ;ADD R5 R5 1
    ;LI  R2 0
    ;STB R2 [R5]
    ;B strip_done

;strip_char:
 ;   LI  R2 0
  ;  STB R2 [R5]
   ; B strip_loop

;strip_done:
    ; Skip empty lines
 ;   LI R7 input_buf
  ;  LDB R6 [R7]
   ; CMP R6 0
    ;BEQ shell_loop

    ; ---- Find basename (last slash) ----
    ; We need basename for argv[0], but we'll use input_buf for pathname
    
    ; ---- Fork ----
    CALL fork
    CMP R1 0
    BEQ child_process
    BLT fork_error

    ;Debug 2

    ; ---- Parent: wait for child ----
    LI R1 -1
    LI R2 0
    CALL waitpid
    CMP R1 0
    BLT wait_error

    ;B shell_loop

    ; ---- Child: execute command ----
child_process:
    ; pathname = input_buf (copied early by kernel, before data page zeroed)
    ; argv = R14 (on stack, safe from data page zeroing)
    LI R1 ls1_path
    Li R2 ls1_argv
    LI R3 0
    CALL execve
    Debug 2
    LI R1 exec_failed_msg
    CALL puts
    LI R1 1
    CALL exit

fork_error:
    LI R1 fork_error_msg
    CALL puts
    MOV SP R7
    B shell_loop

wait_error:
    LI R1 wait_error_msg
    CALL puts
    MOV SP R7
    B shell_loop

exit_shell:
    LI R1 0
    CALL exit

    POP LR
    RET

;---------------------------------------------------------------
; Data
;---------------------------------------------------------------
prompt:
    .ASCIIZ "$ "

exec_failed_msg:
    .ASCIIZ "EXECVE ERR\n"
fork_error_msg:
    .ASCIIZ "FORK ERR\n"
wait_error_msg:
    .ASCIIZ "WAIT ERR\n"

input_buf:
    .SPACE 128

ex_path:
    .ASCIIZ "bin/ls"
; argv[0] is the program name
ex_arg0:
    .ASCIIZ "ls"
; argv[0] = "bin/ls"
; argv[1] = NULL (terminator)
ex_argv:
    .WORD ex_path
    .WORD 0

ls1_path:
    .ASCIIZ "bin/ls1"

ls1_arg0:
    .ASCIIZ "ls1"

ls1_arg1:
    .ASCIIZ "etc/"

ls1_arg2:
    .ASCIIZ "lib/"

ls1_argv:
    .WORD ls1_path
    .WORD ls1_arg1
    .WORD ls1_arg2
    .WORD 0
; ================================================================
; End
; ================================================================