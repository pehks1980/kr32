.org 0x00043000
;==============================================================================
; ls - List directory contents using opendir/readdir/closedir wrappers
;==============================================================================
; Simple ls implementation that reads each directory specified on the command
; line and prints the contents (file/dir names) to stdout.
; If a filename is a directory, it appends a '/' to the name.
;==============================================================================

#include "../lib/libc.inc"

;==============================================================================
; Constants (already defined in libc.inc, but redefined here for clarity)
;==============================================================================
.EQU O_RDONLY,      0

;==============================================================================
; main - Program entry point
; IN:  R1 = argc, R2 = argv
; OUT: R1 = 0 on success, 1 if any directory could not be opened
;==============================================================================
main:
    PUSH LR
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    ; allocate 76-byte buffer on stack for directory entry
    LI  R3 DIRENT_SIZEOF
    SUB SP SP R3
    MOV R12 SP              ; R12 = pointer to struct dirent buffer

    MOV R8 R1               ; R8 = argc
    MOV R9 R2               ; R9 = argv

    CMP R8 2                ; Need at least one argument (argv[1])
    BLT usage

    ; Initialize the allocator (must do this first!)
    CALL malloc_init

    LI R10 1                ; R10 = current argument index (argv[1])
    LI R6 0                 ; R6 = return code (0 = success)

dir_loop:
    CMP R10 R8              ; if index >= argc, done
    BGE dir_done

    ; Get the path string from argv[index]
    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2
    LDW R1 [R2]             ; R1 = directory path (e.g., "etc/")
    PUSH R1

    ; Print header: "\n--- Directory: path ---\n"
    LI R1 newline_str
    CALL puts
    LI R1 dir_header_prefix
    CALL puts
    ; print the directory name
    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2
    LDW R1 [R2]
    CALL puts
    LI R1 dir_header_suffix
    CALL puts
    LI R1 newline_str
    CALL puts

    ; open directory using opendir wrapper
    POP R1                  ; path
    CALL opendir
    
    MOV R11 R1              ; R11 = DIR* handle

    CMP R11 0
    BEQ open_failed         ; opendir returns 0 on error

read_dir_loop:
    ; Read next directory entry
    MOV R1 R11              ; DIR*
    MOV R2 R12              ; pointer to dirent buffer
    CALL readdir
    CMP R1 0
    BEQ read_done           ; EOF
    LI  R2 -1
    CMP R1 R2
    BEQ read_done           ; error

    ; parse the directory entry
    LDW R5 [R12 + DIRENT_TYPE]   ; R5 = d_type (DT_REG or DT_DIR)

    ; print filename (null-terminated at R12 + DIRENT_NAME)
    ADD R1 R12 DIRENT_NAME
    CALL puts                  ; prints the name (libc puts writes string, no newline)

    ; if directory, print '/'
    CMP R5 DT_DIR
    BNE not_dir_entry
    LI R1 slash_str
    CALL puts
not_dir_entry:

    ; print newline
    LI R1 newline_str
    CALL puts

    B read_dir_loop

read_done:
    ; close directory using closedir wrapper
    MOV R1 R11
    CALL closedir

    ADD R10 R10 1           ; next directory
    B dir_loop

open_failed:
    ; print error message for this directory
    LI R1 error_prefix
    CALL puts
    ; print the directory name
    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2
    LDW R1 [R2]
    CALL puts
    LI R1 ls_newline_str
    CALL puts

    LI R6 1                 ; set return code to error
    ADD R10 R10 1           ; next directory
    B dir_loop

dir_done:
    ; free buffer
    LI  R3 DIRENT_SIZEOF
    ADD SP SP R3

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

;==============================================================================
; usage - Print usage message and exit
;==============================================================================
usage:
    LI R1 usage_str
    CALL puts
    LI R6 1                 ; error
    B dir_done

;==============================================================================
; Data Section
;==============================================================================
usage_str:
    .ASCIIZ "usage: ls directory ...\n"
error_prefix:
    .ASCIIZ "ls: cannot open "
dir_header_prefix:
    .ASCIIZ "--- Directory: "
dir_header_suffix:
    .ASCIIZ " ---"
slash_str:
    .ASCIIZ "/"
ls_newline_str:
    .ASCIIZ "\n"

;==============================================================================
; Include the standard libc scaffold
;==============================================================================
; ... (rest of libc.inc goes here, including opendir/readdir/closedir)