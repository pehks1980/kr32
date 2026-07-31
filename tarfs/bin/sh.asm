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

    ; ---- Strip CR/LF and null-terminate ----
    LI R5 input_buf
    ADD R5 R5 R4
    LI R8 input_buf

strip_loop:
    CMP R5 R8
    BLE strip_done
    SUB R5 R5 1
    LDB R6 [R5]
    CMP R6 10
    BEQ strip_char
    CMP R6 13
    BEQ strip_char
    CMP R6 0
    BEQ strip_char
    ADD R5 R5 1
    STB R0 [R5]
    B strip_done

strip_char:
    STB R0 [R5]
    B strip_loop

strip_done:
    ; Skip empty lines
    LI R7 input_buf
    LDB R6 [R7]
    CMP R6 0
    BEQ shell_loop

    ; ---- Find basename (last slash) ----
    ; We need basename for argv[0], but we'll use input_buf for pathname
    LI R8 input_buf
    LI R9 input_buf     ; R9 = last slash position
    LI R10 0            ; found flag

find_slash:
    LDB R6 [R8]
    CMP R6 0
    BEQ found_slash_done
    CMP R6 47           ; '/'
    BNE not_slash
    MOV R9 R8
    LI R10 1
not_slash:
    ADD R8 R8 1
    B find_slash

found_slash_done:

    ; ---- Build argv on the stack ----
    ; We need to put argv strings in the stack region
    ; because the data page will be zeroed by execve
    
    ; Save current stack pointer
    MOV R7 SP

    ; Get basename pointer
    CMP R10 1
    BNE use_full_path
    
    ; Use basename (after slash)
    ADD R9 R9 1
    MOV R8 R9
    B basename_ready
    
use_full_path:
    LI R8 input_buf
    
basename_ready:
    ; R8 = pointer to basename string in input_buf (will be zeroed!)
    ; So we need to copy it to the stack!
    
    ; Copy basename to stack
    LI R11 0
basename_len:
    LDB R6 [R8 + R11]
    CMP R6 0
    BEQ basename_len_done
    ADD R11 R11 1
    B basename_len
basename_len_done:
    ADD R11 R11 1       ; Include null
    
    SUB SP SP R11       ; Reserve space on stack
    MOV R12 SP          ; R12 = basename on stack
    LI R13 0
copy_basename:
    LDB R6 [R8 + R13]
    STB R6 [R12 + R13]
    CMP R6 0
    BEQ copy_basename_done
    ADD R13 R13 1
    B copy_basename
copy_basename_done:
    ; R12 now points to basename on stack

    ; Build argv array on stack
    SUB SP SP 8         ; Space for 2 pointers
    MOV R14 SP          ; R14 = argv array on stack
    STW R12 [R14]       ; argv[0] = basename on stack
    LI R15 0
    STW R15 [R14 + 4]   ; argv[1] = NULL

    ; ---- Fork ----
    CALL fork
    CMP R1 0
    BEQ child_process
    BLT fork_error

    ; ---- Parent: wait for child ----
    LI R1 -1
    LI R2 0
    CALL waitpid
    CMP R1 0
    BLT wait_error

    ; Restore stack before loop
    MOV SP R7
    B shell_loop

    ; ---- Child: execute command ----
child_process:
    ; pathname = input_buf (copied early by kernel, before data page zeroed)
    ; argv = R14 (on stack, safe from data page zeroing)
    LI R1 input_buf
    MOV R2 R14
    LI R3 0
    CALL execve

    ; If execve returns, it failed
    MOV SP R7
    
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

; ================================================================
; End
; ================================================================