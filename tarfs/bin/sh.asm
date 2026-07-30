.org 0x00043000
; from USER_CODE_VA
; ================================================================
; /bin/sh – Minimal shell (version 0) using libc
; ================================================================

#include "../lib/libc.inc"

; Standard file descriptors (libc defines STDOUT_FD only)
.EQU STDIN_FD,  0

;---------------------------------------------------------------
; main() – shell loop
;---------------------------------------------------------------
main:
    ; Save LR (return address) because we call functions
    PUSH LR

shell_loop:
    ; ---- Print prompt "$ " ----
    LI R1 STDOUT_FD
    LI R2 prompt
    LI R3 2
    CALL write          ; write(fd, buf, len)

    ; ---- Read a line ----
    LI R1 STDIN_FD
    LI R2 input_buf
    LI R3 127
    CALL read           ; read(fd, buf, len)
    CMP R1 0
    BLE exit_shell      ; EOF or error -> exit

    MOV R4 R1           ; R4 = number of bytes read

    ; ---- Remove trailing newline ----
    LI R5 input_buf
    ADD R5 R5 R4
    SUB R5 R5 1         ; point to last char
    LDB R6 [R5]
    CMP R6 10           ; '\n'
    BNE no_newline
    STB R0 [R5]         ; overwrite newline with null
    SUB R4 R4 1         ; adjust length (optional)
no_newline:
    ; Null-terminate the string
    LI R5 input_buf
    ADD R5 R5 R4
    STB R0 [R5]         ; store null at end

    ; ---- Skip empty lines ----
    LI  R7 input_buf
    LDB R6 [R7]
    CMP R6 0
    BEQ shell_loop

    ; ---- Fork ----
    CALL fork
    CMP R1 0
    BEQ child_process
    BLT fork_error

    ; ---- Parent: wait for child ----
    LI R1 -1            ; wait for any child
    LI R2 0             ; status pointer (NULL)
    CALL waitpid
    CMP R1 0
    BLT wait_error

    ; Child finished – loop again
    B shell_loop

    ; ---- Child: execute command ----
child_process:
    LI R1 input_buf     ; path to executable
    LI R2 argv          ; argument vector
    LI R3 0             ; environment (NULL)
    CALL execve

    ; If execve returns, it failed
    LI R1 exec_failed_msg
    CALL puts           ; print error with newline
    LI R1 1
    CALL exit

    ; ---- Error handlers ----
fork_error:
    LI R1 fork_error_msg
    CALL puts
    B shell_loop

wait_error:
    LI R1 wait_error_msg
    CALL puts
    B shell_loop

exit_shell:
    LI R1 0
    CALL exit

    ; This point is never reached
    POP LR
    RET

;---------------------------------------------------------------
; Data section
;---------------------------------------------------------------
; (null terminator not needed for write)
prompt:
    .ASCIIZ "$ "

exec_failed_msg:
    .ASCIIZ "EXECVE ERR\n"
fork_error_msg:
    .ASCIIZ "FORK ERR\n"
wait_error_msg:
    .ASCIIZ "WAIT ERR\n"

; command line buffer
input_buf:
    .SPACE 128

; Argument vector for execve:
;   argv[0] = pointer to the command line string
;   argv[1] = NULL
argv:
    .WORD input_buf
    .WORD 0

; ================================================================
; End of shell
; ================================================================