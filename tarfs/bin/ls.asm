.org 0x00043000
;==============================================================================
; ls - List directory contents
;==============================================================================
; Simple ls implementation that reads each directory specified on the command
; line and prints the contents (file/dir names) to stdout.
; If a filename is a directory, it appends a '/' to the name.
;==============================================================================

#include "../lib/libc.inc"

;==============================================================================
; Dirent structure (matches kernel definition)
;==============================================================================
.EQU DT_REG,        1
.EQU DT_DIR,        2

.EQU DIRENT_INODE,  0
.EQU DIRENT_SIZE,   4
.EQU DIRENT_TYPE,   8
.EQU DIRENT_NAME,   12
.EQU DIRENT_SIZEOF, 76

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

    ; allocate 256-byte buffer on stack for reading directory entries
    LI  R3 256
    SUB SP SP R3
    MOV R12 SP              ; R12 = buffer pointer

    MOV R8 R1               ; R8 = argc
    MOV R9 R2               ; R9 = argv

    CMP R8 2                ; Need at least one argument (argv[1])
    BLT usage

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
    BL puts
    LI R1 dir_header_prefix
    BL puts
    ; print the directory name
    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2
    LDW R1 [R2]
    BL puts
    LI R1 dir_header_suffix
    BL puts
    LI R1 newline_str
    BL puts

    ; open directory
    ; R1 already has the path
    POP R1
    LI  R2 O_RDONLY
    BL open
    MOV R11 R1              ; R11 = fd

    CMP R11 0
    BLT open_failed

read_dir_loop:
    ; read(fd, buf, DIRENT_SIZEOF)
    MOV R1 R11
    MOV R2 R12
    LI  R3 DIRENT_SIZEOF
    BL read
    MOV R7 R1               ; R7 = bytes read (or -1 on error)

    CMP R7 0
    BEQ read_done           ; EOF
    CMP R7 DIRENT_SIZEOF
    BNE read_done           ; error or short read

    ; parse the directory entry
    LDB R5 [R12 + DIRENT_TYPE]   ; R5 = d_type (DT_REG or DT_DIR)

    ; print filename (null-terminated at R12 + DIRENT_NAME)
    ADD R1 R12 DIRENT_NAME
    BL puts                  ; prints the name (libc puts writes string, no newline)

    ; if directory, print '/'
    CMP R5 DT_DIR
    BNE not_dir_entry
    LI R1 slash_str
    BL puts
not_dir_entry:

    ; print newline
    LI R1 newline_str
    BL puts

    B read_dir_loop

read_done:
    ; close(fd)
    MOV R1 R11
    BL close

    ADD R10 R10 1           ; next directory
    B dir_loop

open_failed:
    ; print error message for this directory
    LI R1 error_prefix
    BL puts
    ; print the directory name
    MOV R2 R10
    SHL R2 R2 2
    ADD R2 R9 R2
    LDW R1 [R2]
    BL puts
    LI R1 newline_str
    BL puts

    LI R6 1                 ; set return code to error
    ADD R10 R10 1           ; next directory
    B dir_loop

dir_done:
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

;==============================================================================
; usage - Print usage message and exit
;==============================================================================
usage:
    LI R1 usage_str
    BL puts
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

;==============================================================================
; Include the standard libc scaffold
;==============================================================================
