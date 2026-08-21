.org 0x00043000
; ================================================================
; /bin/sh – Minimal shell (version 0) using libc
; ================================================================

#include "../lib/libc.inc"

.EQU STDIN_FD,  0
.EQU MAX_ARGS,  8

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
;
; Supported syntax:
;   command arg1 arg2
;   command "argument with spaces"
;   command 'argument with spaces'
; Supported escapes inside quoted strings:
;
;   \n   newline
;   \r   carriage return
;   \t   tab
;   \\   backslash
;   \"   double quote
;   \'   single quote
;
; input:
;   input_buf = null-terminated command line
;
; output:
;   argv_buf = NULL-terminated argv[] vector
;
; Important:
;   Parsing is done IN PLACE.
;
;   Example:
;
;       /bin/print "hello world" 123
;
;   becomes internally:
;
;       /bin/print\0hello world\0123\0
;
;   argv_buf contains pointers:
;
;       argv[0] -> "/bin/print"
;       argv[1] -> "hello world"
;       argv[2] -> "123"
;       argv[3] -> NULL
;
; Registers:
;   R8  = source/read pointer
;   R9  = destination/write pointer
;   R10 = argc
;   R11 = current character
;   R12 = quote state
;
; quote state:
;   0 = not inside quotes
;   '"' = inside double quotes
;   "'" = inside single quotes
; ---------------------------------------------------------------

parse_command:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    LI R8 input_buf
    LI R9 input_buf
    LI R10 0
    LI R12 0        ; 0 not in quotes flag

; ---------------------------------------------------------------
; Skip spaces between arguments
; ---------------------------------------------------------------

parse_skip_spaces:
    LDB R11 [R8]
    CMP R11 0
    BEQ parse_done
    CMP R11 32             ; ' '
    BNE parse_token_start
    ADD R8 R8 1
    B parse_skip_spaces
; ---------------------------------------------------------------
; Start a new argument
; ---------------------------------------------------------------
parse_token_start:
    CMP R10 MAX_ARGS             ; maximum 8 arguments
    BGE parse_done
    ; R7 = argv_buf + argc * 4 ptr in argv of this arg
    LI R7 argv_buf
    MOV R6 R10  
    SHL R6 R6 2
    ADD R7 R7 R6
    ; argv[argc] = current output position
    STW R9 [R7]
    ADD R10 R10 1
    ; R12 = quote state = none
    LI R12 0

; ---------------------------------------------------------------
; Read characters belonging to current argument
; ---------------------------------------------------------------
parse_token_body:
    LDB R11 [R8]    ;parse_token_body
    CMP R11 0
    BEQ parse_token_done       ;end of input
    ; -----------------------------------------------------------
    ; Outside quotes
    ; -----------------------------------------------------------
    CMP R12 0               ; flag == 0?
    BNE parse_inside_quotes ; if inside qoutes
    CMP R11 32             ; Space terminates an unquoted argument
    BEQ parse_token_end
    CMP R11 34             ; '"'  Start double quoted string
    BEQ parse_start_double
    CMP R11 39             ; "'"  Start single quoted string
    BEQ parse_start_single
    CMP R11 92             ; '\' Backslash outside quotes
    BEQ parse_escape
    
    STB R11 [R9]           ; Normal character
    ADD R8 R8 1
    ADD R9 R9 1
    B parse_token_body

parse_start_double:
    LI R12 34              ; quote = '"' switch to inside quotes parse
    ADD R8 R8 1
    B parse_token_body

parse_start_single:
    LI R12 39              ; quote = "'" switch to inside quotes parse
    ADD R8 R8 1
    B parse_token_body

; ---------------------------------------------------------------
; Inside quotes
; ---------------------------------------------------------------
parse_inside_quotes:
    CMP R11 R12         ;Closing quote?
    BEQ parse_close_quote
    CMP R11 92          ;Backslash?
    BEQ parse_escape
    ; Normal character inside quotes
    STB R11 [R9]
    ADD R8 R8 1
    ADD R9 R9 1
    B parse_token_body

parse_close_quote:
    LI R12 0    ;Closing quote
    ADD R8 R8 1
    B parse_token_body
; ---------------------------------------------------------------
; Escape sequence
;
; R8 points at '\'
; Move to escaped character.
; ---------------------------------------------------------------
parse_escape:
    ADD R8 R8 1
    LDB R11 [R8]
    CMP R11 0           ;if end
    BEQ parse_token_done
    ;which escape?
    CMP R11 110            ; 'n'
    BEQ parse_escape_n
    CMP R11 114            ; 'r'
    BEQ parse_escape_r
    CMP R11 116            ; 't'
    BEQ parse_escape_t
    CMP R11 92              ; \\
    BEQ parse_escape_backslash
    CMP R11 34              ; \"
    BEQ parse_escape_quote
    CMP R11 39              ; \'
    BEQ parse_escape_single
    ; Unknown escape:
    ; keep the character itself.
    STB R11 [R9]
    ADD R8 R8 1
    ADD R9 R9 1
    B parse_token_body

parse_escape_n:
    LI R11 10
    B parse_token_body_ne
parse_escape_r:
    LI R11 13
    B parse_token_body_ne
parse_escape_t:
    LI R11 9
    B parse_token_body_ne
parse_escape_backslash:
    LI R11 92
    B parse_token_body_ne
parse_escape_quote:
    LI R11 34
    B parse_token_body_ne
parse_escape_single:
    LI R11 39

parse_token_body_ne:
    STB R11 [R9]
    ADD R8 R8 1
    ADD R9 R9 1
    B parse_token_body

; ---------------------------------------------------------------
; Unquoted space = end of argument
; ---------------------------------------------------------------
parse_token_end:
    LI R11 0
    STB R11 [R9]
    ADD R9 R9 1
    ADD R8 R8 1
    B parse_skip_spaces
; ---------------------------------------------------------------
; End of input / token
; ---------------------------------------------------------------
parse_token_done:

    LI R11 0
    STB R11 [R9]
; ---------------------------------------------------------------
; Finish argv[]
; ---------------------------------------------------------------
parse_done:
    LI R7 argv_buf
    MUL R6 R10 4
    ADD R7 R7 R6

    LI R11 0
    STW R11 [R7]

    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET


; ---------------------------------------------------------------
; parse_command() – parse input_buf into argv_buf
; input and output:
;   input_buf: null-terminated string of command line
;   output: all needed for execve (input_buf = pathname, argv_buf = argv) ready
; ---------------------------------------------------------------

parse_command0:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11

    LI R8 input_buf
    LI R9 argv_buf
    LI R10 0

parse_skip_spaces0:
    LDB R11 [R8]
    CMP R11 32      ;" "
    BNE parse_token_start
    LI R11 0        ;replace space with null so input_buf gets str.split(' ') into args strings
    STB R11 [R8]
    ADD R8 R8 1
    B parse_skip_spaces0

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
    .SPACE 128
; ================================================================
; End
; ================================================================
