; ================================================================
; KR32 KERNEL - BOOTSTRAP AND TRAP HANDLERS (C-like macros)
; Converted by tools/convert_to_cmacros.py — original saved as kernelshed.asm.orig
; Use tools/preprocess_cmacros.py to expand and generate real assembly.
; Example: python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm
; ================================================================

; KR32 CALLING CONVENTION:
;   R0        = hardwired ZERO
;   R1-R4     = argument registers (arg0..arg3)
;   R1        = return value register
;   R5-R11    = caller-saved temporaries
;   R12       = callee-saved temporary (optional)
;   R13       = SP (stack pointer)
;   R14       = FP (frame pointer)
;   R15       = LR (return link)

#include "errno.inc"

.org 0x0000
B KERNEL_START

.EQU PTE_R,       0x0001
.EQU PTE_W,       0x0002
.EQU PTE_X,       0x0004
.EQU PTE_U,       0x0008
.EQU PTE_P,       0x0010
.EQU PTE_G,       0x0020

.EQU KERNEL_FLAGS, 0x0037       ; P|R|W|X|G, supervisor-only shared mapping
.EQU USER_RX,      0x001D       ; P|R|X|U
.EQU USER_RW,      0x001B       ; P|R|W|U
.EQU KERN_USER_RX, 0x003D       ; P|R|X|U|G, shared executable (kernel can fetch user code)

.EQU PAGE_SIZE,    0x1000
.EQU PAGE_MASK,    0x0FFF

;.EQU TASK0_PTBR,   0x00010000   ; page table at 64KB (one 1 MiB one-level table per address space)
;.EQU TASK1_PTBR,   0x00020000   ; page table at 128KB
;done via alloc down .EQU TASK2_PTBR,   0x00030000   ; page table at 192KB

;need to do via alloc 
.EQU TASK0_USTACK_PA, 0x00005000 ; physical memory address stack and data when map pages tasks 0,1,2 in memory image
.EQU TASK1_USTACK_PA, 0x0000B000 ; func page init makes map in page table for every task (0) runs in kernel mode
.EQU TASK2_USTACK_PA, 0x0000C000

.EQU TASK0_DATA_PA,   0x00006000
.EQU TASK1_DATA_PA,   0x0000D000
.EQU TASK2_DATA_PA,   0x0000E000

;memory map used for data validation when make syscalls which transfer data b/w kernel and user
.EQU KERNEL_BASE,     0x0000
.EQU KERNEL_LIMIT,    0x000BFFFF
.EQU USER_BASE,       0x00005000
.EQU USER_DATA_VA,    0x00006000
.EQU USER_STACK_VA,   0x0003F000
.EQU USER_STACK_TOP,  0x00040000
.EQU USER_LIMIT,      0x0003FFFF

.EQU KBUFFER_SIZE,   256

.EQU UARTDEV_RX_QUEUE, 0
.EQU UARTDEV_TX_QUEUE, 4
.EQU UARTDEV_MMIO,     8
.EQU UARTDEV_SIZE,     12

.EQU STDIN_FD,       0
.EQU STDOUT_FD,      1
.EQU STDERR_FD,      2
.EQU CONSOLE_INPUT_LEN, 5

; =============================================================
; FILE struc - current with inodes
; =============================================================

.EQU FD_FLAG_READ,    1
.EQU FD_FLAG_WRITE,   2

;FILE struc uses inode
.EQU FILE_INODE,    0
.EQU FILE_OFFSET,   4
.EQU FILE_FLAGS,    8
.EQU FILE_SIZE,    12

.EQU FOPS_READ,     0
.EQU FOPS_WRITE,    4
.EQU FOPS_SIZE,     8

; ==================================================
; VFS inode table struc
; ==================================================

; ==================================================
; inode struc
; ==================================================

.EQU INODE_OPS,      0
.EQU INODE_PRIVATE,  4
.EQU INODE_TYPE,     8
.EQU INODE_SIZE,    12
.EQU INODE_REFCNT,  16

.EQU INODE_SIZEOF,  20



; KBUFFER for kernel<->user data transfer, one per task, mapped into each address space at 0x1000-0x1FFF 
; for easy access by copy routines and device drivers. Each task has a separate KBUFFER_WR and KBUFFER_RD
; to avoid shared state and synchronization issues.      

.org 0x1000
;KBUFFER_WR:
KBUFFER_WR_0:
        .SPACE 256              ; 256b
;KBUFFER_RD:
KBUFFER_RD_0:
        .SPACE 256              ; 256b
KBUFFER_WR_1:
        .SPACE 256              ; 256b
KBUFFER_RD_1:
        .SPACE 256              ; 256b
KBUFFER_WR_2:
        .SPACE 256              ; 256b
KBUFFER_RD_2:
        .SPACE 256              ; 256b

; ================================================================
; PAGE TABLES for each task (1 KiB each, 4 entries x 1024 bytes)
; ================================================================
.org 0x10000
;TASK0_PAGE_TABLE
TASK0_PTBR:
        .SPACE 4096             ; 1 KiB page table (1024 entries × 4 bytes)

.org 0x20000
;TASK1_PAGE_TABLE
TASK1_PTBR:
        .SPACE 4096             ; 1 KiB page table

.org 0x30000
;TASK2_PAGE_TABLE
TASK2_PTBR:
        .SPACE 4096             ; 1 KiB page table


.org 0x2000

; ================================================================
; KERNEL CODE (starts at 0x2000)
; ================================================================
func KERNEL_START
        LI SP 0x0000F000
        MOV FP SP

        ; Initialize unified IDT (all traps go to trap_entry)
        call init_idt

        ; Initialize Page Tables
        ; check memory_map.txt for current layout
        call init_page_tables

        ; Init_task_scheduler (hard-coded)
        call init_scheduler

        ; Initialize MMIO devices (PIC, PIT, UART)
        call init_mmio_devices

        ; Mount the built-in read-only TAR archive and show its index.
        LI R1 tarfs_start
        LI R2 tarfs_end
        SUB R2 R2 R1
        call tarfs_init
        call tarfs_dump_index

        LI R1 etc_path
        call tarfs_readdir

        LI R1 bin_path
        call tarfs_readdir

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
        LI R1 tasks
        LDW R2 [R1 + TASK_PTBR]
        SETPTBR R2
        LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
        call enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore 
        B trap_restore

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
    LI R1 0x00200000           ; IDT base physical address
    
    ; Only entry 0 matters - all traps go here
    LI R2 trap_entry
    STW R2 [R1]                ; IDT[0] = trap_entry
    
    ; Optional: fill other entries with same handler for safety
    LI R2 trap_entry
    STW R2 [R1+4]                ; IDT[1]
    STW R2 [R1+8]                ; IDT[2]
    STW R2 [R1+12]               ; IDT[3]
    STW R2 [R1+24]               ; IDT[6]
    STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register 
    SETIDTR R1
    RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
    PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
    LI R1 page_bitmap
    LI R3 16
    BL mem_zero

    POP LR
    RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
    PUSH LR
    PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
    LI R2 0x00000000      ;page 0 - boot (0000)
    LI R3 0x00000000
    LI R4 KERNEL_FLAGS
    bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
    LI R2 0x00001000      ; page for kernel buffers
    LI R3 0x00001000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
    LI R3 0x00002000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00003000
    LI R3 0x00003000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00004000
    LI R3 0x00004000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
    LI R3 0x00007000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
    LI R3 0x00008000
    LI R4 KERNEL_FLAGS
    BL map_page


    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
    LI R2 0x00100000      ; UART physical and virtual base
    LI R3 0x00100000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00101000      ; PIT physical and virtual base
    LI R3 0x00101000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00102000      ; PIC physical and virtual base
    LI R3 0x00102000
    LI R4 KERNEL_FLAGS
    BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
    LI R12 PAGE_ALLOC_BASE
    LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
    CMP R12 R7
    BGE map_common_dynamic_done
    MOV R2 R12
    MOV R3 R12
    LI R4 KERNEL_FLAGS
    BL map_page
    LI R6 PAGE_SIZE
    ADD R12 R12 R6
    B map_common_dynamic_loop
map_common_dynamic_done:

    POP R12
    POP LR
    RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
    SHR R5 R2 12               ; VPN
    SHL R5 R5 2                ; page-table byte offset
    OR R6 R3 R4                ; PTE = PA page base | flags
    STW R6 [R1 + R5]
    RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
    LI R1 0x00102000
    LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
    STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
    LI R1 0x00101000
    LI R2 2000
    STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
    LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both 
    STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
    LI R1 0x00100000
    LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
    STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

    RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
    ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
    RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
    CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12
    PUSH R14
    PUSH R15

    ; Save interrupted task SP plus privileged trap state.
    CSRR R1 SSCRATCH
    PUSH R1
    CSRR R1 SEPC
    PUSH R1
    CSRR R1 SFLAGS
    PUSH R1
    CSRR R1 SSTATUS
    PUSH R1
    CSRR R1 SCAUSE
    PUSH R1
    CSRR R1 STVAL
    PUSH R1

    ; Dispatch based on scause.
    CSRR R1 SCAUSE
    CMP R1 0
    BEQ handle_divide_zero
    
    CMP R1 1
    BEQ handle_invalid_instr
    
    CMP R1 2
    BEQ handle_page_fault
    
    CMP R1 3
    BEQ handle_syscall
    
    CMP R1 6
    BEQ handle_debug
    
    CMP R1 16
    BEQ handle_irq
    
    ; Unknown cause - halt
    HLT

handle_divide_zero:
    ; TODO: handle divide by zero
    
    B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction
    
    B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
    HLT
    
    B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

    CSRR R2 STVAL

    CMP R2 SYS_COUNT
    BGE syscall_unknown

    LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
    SHL R4 R2 2
    LDW R5 [R3 + R4]
    JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

    LI R1 ERR_NOSYS
    STW R1 [SP + TF_R1]
    B trap_restore

;================================================================
; SYSCALL HANDLERS  
;================================================================

syscall_table:
    .WORD syscall_yield         ; SVC 0
    .WORD syscall_exit          ; SVC 1
    .WORD syscall_getpid        ; SVC 2
    .WORD syscall_debug         ; SVC 3
    .WORD syscall_write         ; SVC 4
    .WORD syscall_read          ; SVC 5
    .WORD syscall_open          ; SVC 6
    .WORD syscall_close         ; SVC 7
    .WORD syscall_pipe          ; SVC 8


syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

    LI R1 0
    STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

    B schedule_and_switch

syscall_exit:
    ;================================================================               
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

    GET_CURR_TASK_IDX R2
    GET_TASK_PTR R5, R2

    PUSH R5
    MOV R1 R5
    BL task_close_fds      ; close all open file descriptors of this task (if any) to free file_pool resources
    POP R5

    ; Do not destroy the current task here: SP still points into its kernel
    ; stack. Mark it unrecoverable and let idle_task reclaim it later while
    ; running on a different stack.
    TASK_SET_STATE R5, TASK_ZOMBIE
    TASK_SET_WAIT R5, WAIT_NONE
    B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

    GET_CURR_TASK_IDX R2
    GET_TASK_PTR R5, R2
    TASK_GET_PID R1, R5            ; get pid from task scheduler data
    
    STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
    B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

    LDW R1 [SP + TF_R1]
    STW R1 [SP + TF_R1]
    
    B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

    LDW R1 [SP + TF_R1]
    LDW R2 [SP + TF_R2]

    BL copy_path_from_user     ; macro inside destroys R11, copy pathname 
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
    CMP R1 0
    BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R5, R4
    TASK_GET_KBUF_RD R1, R5

    BL vfs_open

    STW R1 [SP + TF_R1]     ;file opened if fd on exit!
    B trap_restore

open_fail_fault:
    LI R1 ERR_FAULT
    STW R1 [SP + TF_R1]     ;file not opened ERR
    B trap_restore


;====================================================================
; syscall_open helpers
;====================================================================

;====================================================================
; copy_path_from_user
;
;input:
; R1 = user pointer
;output:
;R1 = kernel pointer to copied NUL-terminated path
;R1 = 0 fail
;====================================================================
copy_path_from_user:
    PUSH LR

    MOV R8 R1                  ; current user source byte

    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R5, R4
    TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer

    PUSH R9                    ; original destination returned on success
    LI R10 0                   ; bytes copied before NUL

copy_path_loop:
    LI R11 KBUFFER_SIZE
    CMP R10 R11
    BGE copy_path_fail

    PUSH R8
    PUSH R9
    PUSH R10
    MOV R1 R8
    LI R2 1
    LI R3 0                    ; read access from user source
    BL user_buffer_valid_range
    POP R10
    POP R9
    POP R8
    CMP R1 1
    BNE copy_path_fail

    LDB R4 [R8]
    STB R4 [R9]
    CMP R4 0
    BEQ copy_path_done

    ADD R8 R8 1
    ADD R9 R9 1
    ADD R10 R10 1
    B copy_path_loop

copy_path_done:
    POP R1                     ; original kernel path pointer
    POP LR
    RET

copy_path_fail:
    POP R1                     ; discard original kernel path pointer
    LI R1 0
    POP LR
    RET

;====================================================================
; devfs_lookup - lookup device files registry
;
; input:
;   R1 = pathname /dev/....
;
; output:
;   R1 = inode for the device 
;   R1 = 0 if not found
;====================================================================

devfs_lookup:
    PUSH LR
    MOV R8 R1                  ; save pathname ptr

    LI R7 device_table
    LI R9 DEVICE_COUNT

devfs_loop:
    CMP R9 0
    BEQ lookup_fail

    ; compare pathname with device name
    MOV R1 R8
    LDW R2 [R7 + DEV_NAME]
    BL strcmp
    CMP R1 1
    BEQ devfs_found

    ADD R7 R7 DEV_SIZE
    SUB R9 R9 1
    B devfs_loop

devfs_found:
    ; 1 allocate inode
    BL inode_alloc
    CMP R1 0
    BEQ devfs_fail

    MOV R10 R1         ; inode
    ; 2 init inode
    LDW R2 [R7 + DEV_OPS]
    LDW R3 [R7 + DEV_PRIVATE]
    LI  R4 INODE_CHAR       ; inode type for dev - char
    LI  R5 0                ; size =0
    BL inode_init

    MOV R1 R10         ; 3 return new inited inode ptr for this dev
    POP LR
    RET

devfs_fail:
    LI R1 0
    POP LR
    RET

;====================================================================
; lookup_device in device_table - obsolete replaced by devfs_lookup
;
;input:
; R1 = user pointer to string
;output:
; R1 = device descriptor
 ;R1 = 0 if not found
;====================================================================
lookup_device:

    PUSH LR

    MOV R8 R1                  ; save pathname ptr

    LI R7 device_table
    LI R9 DEVICE_COUNT

lookup_loop:
    CMP R9 0
    BEQ lookup_fail

    ; compare pathname with device name

    MOV R1 R8
    LDW R2 [R7 + DEV_NAME]

    BL strcmp

    CMP R1 1
    BEQ lookup_found

    ADD R7 R7 DEV_SIZE
    SUB R9 R9 1
    B lookup_loop

lookup_found:

    MOV R1 R7                  ; return device descriptor ptr

    POP LR
    RET

lookup_fail:

    LI R1 0

    POP LR
    RET

;================
; string helpers lib
;================

;====================================================================
; strcmp
; in: R1 = str1 "dfdff"0
;     R2 = str2
;
; out:R1 = 1 equal
;     R1 = 0 not equal
;====================================================================
strcmp:

str_loop:
    LDB R3 [R1]
    LDB R4 [R2]

    CMP R3 R4
    BNE str_not_equal

    CMP R3 0
    BEQ str_equal

    ADD R1 R1 1
    ADD R2 R2 1
    B str_loop

str_equal:
    LI R1 1
    RET

str_not_equal:
    LI R1 0
    RET

; --------------------------------------------------
; str_prefix
;
; R1 = string
; R2 = prefix
;
; returns:
;   R1 = 1  prefix matches
;   R1 = 0  no match
; examples:
;  R1 = "etc/motd"0
;  R2 = "etc/"0
; out R1=1
; --------------------------------------------------

str_prefix:
    PUSH R3
    PUSH R4 
    ;assume match ! unless first unequal
sp_loop:
    LDB R3 [R2]            ; prefix char
    CMP R3 0
    BEQ sp_match           ; reached end of prefix?

    LDB R4 [R1]            ; string char
    CMP R4 R3
    BNE sp_nomatch

    ADD R1 R1 1
    ADD R2 R2 1
    B sp_loop
sp_match:
    LI R1 1                 ;prefix ok
    POP R4
    POP R3
    RET
sp_nomatch:
    LI R1 0                 ; not ok
    POP R4
    POP R3
    RET

; --------------------------------------------------
; skip_prefix
;
; R1 = string
; R2 = prefix
;
; returns:
;   R1 = pointer after prefix (etc/motd) ptr->motd (no etc/)
;   R1 = 0 if prefix does not match
; --------------------------------------------------

skip_prefix:
    PUSH R3
    PUSH R4
sk_loop:
    LDB R3 [R2]            ; prefix char
    CMP R3 0
    BEQ sk_match           ; reached end of prefix
    LDB R4 [R1]            ; string char
    CMP R4 R3
    BNE sk_nomatch
    ADD R1 R1 1
    ADD R2 R2 1
    B sk_loop

sk_match:
    ; R1 already points past prefix
    POP R4
    POP R3
    RET

sk_nomatch:
    LI R1 0                 ; no prefix/or prefix not matching with that in src string
    POP R4
    POP R3
    RET

; --------------------------------------------------
; path_component_len
;
; R1 = path component string ie in etc/motd its len of motd0 or etc/network/interfaces its len of "network"/
;
; returns:
;   R1 = length until '/' or until NUL (0)
;   note no max length! need to do
; --------------------------------------------------

path_component_len:
    PUSH R2
    PUSH R3
    LI R2 0                ; length
pcl_loop:
    LDB R3 [R1]
    CMP R3 0
    BEQ pcl_done
    LI R4 47               ; '/'
    CMP R3 R4
    BEQ pcl_done
    ADD R2 R2 1
    ADD R1 R1 1
    B pcl_loop
pcl_done:
    MOV R1 R2
    POP R3
    POP R2
    RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
    STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
    LI R4 0
    STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
    STW R3 [R1 + FILE_FLAGS]
    RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

    MOV R8 R1                  ; save file pointer

    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R4, R4
    TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr

    LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

    CMP R5 MAX_FDS
    BGE fd_alloc_fail

    SHL R6 R5 2                ; fd * 4
    ADD R7 R4 R6               ; &fd_table[fd]

    LDW R2 [R7]
    CMP R2 0                   ; 0 - empty
    BEQ fd_alloc_found

    ADD R5 R5 1
    B fd_alloc_loop

fd_alloc_found:

    STW R8 [R7]                ; fd_table[fd] = file*

    MOV R1 R5                  ; return fd
    RET

fd_alloc_fail:

    LI R1 ERR_MFILE
    RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
    LDW R1 [SP + TF_R1]

    BL vfs_close

    LI R1 0
    STW R1 [SP + TF_R1]

    B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
    LDW R7 [SP + TF_R1]

    BL pipe_alloc
    CMP R1 0
    BEQ pipe_fail_nospc

    MOV R8 R1            ; new slot in pipe_pool ( pipe* )

    ; [0] read end          write[1]>--pipe--->read[0]

    BL file_alloc
    CMP R1 0
    BEQ pipe_fail_pipe_only

    MOV R9 R1           ; new file for read end  in file_pool

    LI R2 pipe_ops
  ;  STW R2 [R9 + FILE_OPS]      ; store ops (for pipe of read end) in allocated  file struc needs to be adapted for inode

  ;  STW R8 [R9 + FILE_PRIVATE]  ; store our slot pipe* in file

    LI R2 FD_FLAG_READ
    STW R2 [R9 + FILE_FLAGS]    ; set file mode read

    MOV R1 R9
    BL fd_alloc                 ; insert read file to fd_table of user process

    LI R2 ERR_MFILE             ; check if fd_alloc problem
    CMP R1 R2
    BEQ pipe_fail_read_file

    MOV R10 R1           ; get file read fd created to R10

    ; write end

    BL file_alloc
    CMP R1 0
    BEQ pipe_fail_read_fd

    MOV R9 R1

    LI R2 pipe_ops
  ;  STW R2 [R9 + FILE_OPS]

  ;  STW R8 [R9 + FILE_PRIVATE]

    LI R2 FD_FLAG_WRITE                 ;file mode -write
    STW R2 [R9 + FILE_FLAGS]

    MOV R1 R9
    BL fd_alloc

    LI R2 ERR_MFILE             ; check if fd_alloc problem
    CMP R1 R2
    BEQ pipe_fail_write_file

    MOV R11 R1           ; R11 write fd R10 read fd

    MOV R1 R7   ; in &fd[2]
    LI R2 8     ; len 2
    LI R3 1     ; mem perm to write cond
    BL user_buffer_valid_range
    CMP R1 1
    BNE pipe_fail_both_fds

    STW R10 [R7]    ;fd[0]-rd fd[1]-wr
    STW R11 [R7 + 4]

    LI R1 0
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail:
    LI R1 ERR_IO
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail_both_fds:
    MOV R12 R8
    MOV R1 R11
    BL fd_remove
    CMP R1 0
    BEQ pipe_fail_both_fds_read
    BL file_free

pipe_fail_both_fds_read:
    MOV R1 R10
    BL fd_remove
    CMP R1 0
    BEQ pipe_fail_free_pipe_fault
    BL file_free

pipe_fail_free_pipe_fault:
    MOV R1 R12
    BL pipe_free
    LI R1 ERR_FAULT
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail_write_file:
    MOV R12 R8
    MOV R1 R9
    BL file_free
    MOV R1 R10
    BL fd_remove
    CMP R1 0
    BEQ pipe_fail_free_pipe_mfile
    BL file_free

pipe_fail_free_pipe_mfile:
    MOV R1 R12
    BL pipe_free
    LI R1 ERR_MFILE
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail_read_fd:
    MOV R12 R8
    MOV R1 R10
    BL fd_remove
    CMP R1 0
    BEQ pipe_fail_free_pipe_nfile
    BL file_free

pipe_fail_free_pipe_nfile:
    MOV R1 R12
    BL pipe_free
    LI R1 ERR_NFILE
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail_read_file:
    MOV R12 R8
    MOV R1 R9
    BL file_free
    MOV R1 R12
    BL pipe_free
    LI R1 ERR_MFILE
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail_pipe_only:
    MOV R1 R8
    BL pipe_free
    LI R1 ERR_NFILE
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_fail_nospc:
    LI R1 ERR_NOSPC
    STW R1 [SP + TF_R1]

    B trap_restore

pipe_read:
;=========================================================
; R1 = file*
; R2 = user buffer
; R3 = requested length
;
; returns:
;   R1 = bytes read
; this is specific pipe device read loop!
;=========================================================

    PUSH LR

    MOV R9 R1              ; file*
    MOV R7 R2              ; user buffer
    MOV R6 R3              ; requested len
   ;  LDW R9 [R9 + FILE_PRIVATE]    ; our instance allocated in pipe_pool pipe* needs to be adapted for inode
    CMP R6 0                ;fast clear from it if len=0
    BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
    PUSH R7
    PUSH R6

    MOV R1 R7
    MOV R2 R6
    LI  R3 1               ; write access
    BL user_buffer_valid_range

    POP R6
    POP R7
    CMP R1 1
    BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
    LDW R4 [R9 + PIPE_COUNT]
    CMP R4 0
    BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
    CMP R6 R4
    BLT pipe_user_len

    MOV R5 R4
    B pipe_have_amount

pipe_user_len:
    MOV R5 R6

pipe_have_amount:
    LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
    CMP R10 R5
    BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
    LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
    MOV R12 R9
    ADD R12 R12 PIPE_BUFFER
    ADD R12 R12 R11         ; addr += tail

    LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
    MOV R12 R7
    ADD R12 R12 R10

    STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
    ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
    LI R2 255
    AND R11 R11 R2
    STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
    LDW R12 [R9 + PIPE_COUNT]
    SUB R12 R12 1
    STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
    ADD R10 R10 1
    B pipe_read_loop

pipe_read_done:
; wake blocked writers
    MOV R1 R9
    ADD R1 R1 PIPE_WWAIT
    BL waitq_wake_all
    MOV R1 R10          ; read bytes amount
    POP LR
    RET

pipe_read_badptr:
    LI R1 ERR_FAULT
    POP LR
    RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
    MOV R1 R9
    ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
    LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
    BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
    LDW R4 [R9 + PIPE_COUNT]
    CMP R4 0
    BNE pipe_read_retry

    BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
    B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

    LI R2 0

pipe_loop:
    LI  R1 MAX_PIPES
    CMP R2 R1
    BGE pipe_alloc_fail

    SHL R3 R2 2

    LI R4 pipe_used
    ADD R4 R4 R3

    LDW R5 [R4]             ;R4 address in PIPE_USED LIST

    CMP R5 0                ; 0 -empty
    BEQ pipe_found

    ADD R2 R2 1
    B pipe_loop

pipe_found:

    LI R5 1
    STW R5 [R4]             ; set it in PIPE_USED =1 as used

    LI R4 PIPE_SIZE
    MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

    LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
    ADD R1 R1 R6

    LI R7 0                 ; clean it up
    STW R7 [R1 + PIPE_HEAD]
    STW R7 [R1 + PIPE_TAIL]
    STW R7 [R1 + PIPE_COUNT]
    STW R7 [R1 + PIPE_RWAIT]
    STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
    RET

pipe_alloc_fail:
    ; R1 = NULL
    LI R1 0
    RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

    LI R2 pipe_pool
    SUB R3 R1 R2

    LI R4 PIPE_SIZE
    DIV R5 R3 R4

    SHL R5 R5 2
    LI R6 pipe_used
    ADD R6 R6 R5

    LI R7 0
    STW R7 [R6]

    RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
    PUSH LR

    MOV R8 R1
    MOV R7 R2
    MOV R6 R3

  ;  LDW R9 [R8 + FILE_PRIVATE]

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

    PUSH R7
    PUSH R6

    MOV R1 R7
    MOV R2 R6
    LI  R3 0           ; READ access
    BL user_buffer_valid_range

    POP R6
    POP R7

    CMP R1 1
    BNE pipe_write_badptr

    LI R10 0               ; bytes written
pipe_write_retry:
    CMP R10 R6
    BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
    LDW R11 [R9 + PIPE_COUNT]
    LI R2 256
    CMP R11 R2
    BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
    LDW R12 [R9 + PIPE_HEAD]

    MOV R4 R7
    ADD R4 R4 R10
    LDB R5 [R4]     ; read byte from user buff addr

    MOV R4 R9
    ADD R4 R4 PIPE_BUFFER
    ADD R4 R4 R12
    STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
    ADD R12 R12 1
    LI R2 255
    AND R12 R12 R2
    STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
    LDW R4 [R9 + PIPE_COUNT]
    ADD R4 R4 1
    STW R4 [R9 + PIPE_COUNT]

; written++
    ADD R10 R10 1
    B pipe_write_retry

pipe_write_done:
; wake readers
    MOV R1 R9
    ADD R1 R1 PIPE_RWAIT
    BL waitq_wake_all
    MOV R1 R10      ;written bytes
    POP LR
    RET

pipe_write_badptr:
    LI R1 ERR_FAULT
    POP LR
    RET

pipe_write_empty:
    LI R1 0
    POP LR
    RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
    MOV R1 R9
    ADD R1 R1 PIPE_WWAIT
    LI R2 WAIT_PIPE_WRITE
    BL waitq_prepare_sleep
    ; race check
    LDW R4 [R9 + PIPE_COUNT]
    LI R2 256
    CMP R4 R2
    BLT pipe_write_retry    ;if not full dont block/frezze go write

    BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

    B pipe_write_retry      ; unblocked! go write!

fd_remove:
 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
    CMP R1 3
    BLT fd_remove_invalid       ; fd 0-1-2 are stdio, not closeable by user

    CMP R1 MAX_FDS
    BGE fd_remove_invalid       ; fd is out of bounds

    MOV R8 R1

    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R4, R4
    TASK_GET_FD_TABLE R4, R4    ; R4 = fd table ptr of current task

    SHL R5 R8 2
    ADD R6 R4 R5                ; &fd_table[fd]

    LDW R1 [R6]
    CMP R1 0
    BEQ fd_remove_invalid       ; if fd_table[fd] is null, invalid fd

    LI R7 0
    STW R7 [R6]                 ; fd_table[fd] = null

    RET                     ; return file* in R1 for file_free

fd_remove_invalid:
    LI R1 0
    RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

    LDW R1 [SP + TF_R1]
    LDW R2 [SP + TF_R2]
    LDW R3 [SP + TF_R3]

    BL vfs_read

    STW R1 [SP + TF_R1]
    B trap_restore


con_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12
    MOV R9 R1
    MOV R7 R2
    MOV R6 R3
    LI R8 0                    ; total bytes collected
    LDW R9 [R9 + FILE_INODE]
    LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
    CMP R6 0
    BEQ read_done

    PUSH R7
    PUSH R6
    PUSH R9
    MOV R1 R7
    MOV R2 R6
    LI R3 1                ; write access for destination buffer
    BL user_buffer_valid_range
    POP R9
    POP R6
    POP R7
    CMP R1 1
    BNE con_read_fault

read_wait_uart_rx:
    LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
    LDW R5 [R4 + 4]             ; read UART_STATUS register
    AND R5 R5 1                 ; bit 0 = RX_READY
    CMP R5 0
    BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R5, R4
    TASK_GET_KBUF_RD R1, R5
    MOV R2 R6
    MOV R3 R9
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
    POP R9
    POP R8
    POP R7
    POP R6

    CMP R1 0
    BEQ read_wait_uart_rx

    MOV R10 R1             ; actual bytes read

    GET_CURR_TASK_IDX R5
    GET_TASK_PTR R4, R5
    TASK_GET_KBUF_RD R4, R4

    ; Remember whether this chunk ended with newline before copy_to_user
    ; clobbers temporary registers.
    LI R11 0
    SUB R5 R10 1
    ADD R5 R4 R5
    LDB R5 [R5]
    CMP R5 10
    BNE read_chunk_not_newline
    LI R11 1

read_chunk_not_newline:
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    MOV R1 R7              ; user destination
    MOV R2 R10
    BL copy_to_user        ; copy from kernel buffer to user buffer
    POP R11
    POP R10
    POP R9
    POP R8
    POP R7
    POP R6

    ADD R7 R7 R10
    ADD R8 R8 R10
    SUB R6 R6 R10

    CMP R11 1
    BEQ read_complete
    CMP R6 0
    BGT read_wait_uart_rx

read_complete:
    MOV R1 R8
    B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
    LI R1 uart_rx_waitq
    LI R2 WAIT_UART_RX
    BL waitq_prepare_sleep

    LDW R4 [R9 + UARTDEV_MMIO]
    LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
    AND R10 R10 1
    CMP R10 0
    BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

    BL waitq_sleep_current       ; save this user task as frozen in kernel space

    B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
    LI R1 uart_rx_waitq
    BL waitq_cancel_sleep_current

    B read_wait_uart_rx          ;go back and read bytes

read_done:
    LI R1 0
    B read_return

con_read_fault:
    LI R1 ERR_FAULT

read_return:
    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

    LDW R1 [SP + TF_R1]
    LDW R2 [SP + TF_R2]
    LDW R3 [SP + TF_R3]

    BL vfs_write

    STW R1 [SP + TF_R1]
    B trap_restore


con_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

    PUSH LR
    MOV R9 R1
    MOV R7 R2
    MOV R6 R3
    LDW R9 [R9 + FILE_INODE]
    LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
    LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
    CMP R6 0
    BEQ write_done             ;0 bytes

    LI R2 KBUFFER_SIZE
    CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
    BLT write_chunk_small
    LI R2 KBUFFER_SIZE
    
    B write_chunk

write_chunk_small:
    MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

    PUSH R7
    PUSH R6
    PUSH R9
    PUSH R8
    MOV R1 R7
    MOV R2 R2
    LI R3 0                ; read access for source buffer
    BL user_buffer_valid_range ;Validate user buffer and length for this chunk
    POP R8
    POP R9
    POP R6
    POP R7
    CMP R1 1
    BNE driver_bad_pointer

    PUSH R7
    PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R5, R4
    TASK_GET_KBUF_WR R4, R5
    MOV R1 R7
    BL copy_from_user      ; copy chunk to tasks kbuffer_wr
    MOV R10 R1             ; bytes copied
    POP R6
    POP R7

    PUSH R7
    PUSH R9
    PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
    LDW R1 [R9 + UARTDEV_MMIO]
    LDW R2 [R1 + 4]
    AND R2 R2 2                     ;check bit 1 - UART_TX rdy
    CMP R2 0
    BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R5, R4
    TASK_GET_KBUF_WR R1, R5
    MOV R2 R10
    MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

    BL device_write
    POP R6
    POP R9
    POP R7

    CMP R1 0        ;nothing is written - go again
    BEQ write_loop

    ADD R8 R8 R1     ;update ptrs
    ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
    SUB R6 R6 R1     ;decrease amounts for next chunk to send
    B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
    LI R1 uart_tx_waitq
    LI R2 WAIT_UART_TX
    BL waitq_prepare_sleep

    LDW R1 [R9 + UARTDEV_MMIO]
    LDW R2 [R1 + 4]             ; re-check after marking blocked
    AND R2 R2 2
    CMP R2 0
    BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

    BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
    B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
    LI R1 uart_tx_waitq
    BL waitq_cancel_sleep_current

    B write_wait_uart_tx

write_done:
    MOV R1 R8
    POP LR
    RET

driver_bad_pointer:
    LI R1 ERR_FAULT
    POP LR
    RET

bad_fd:
    LI R1 ERR_BADF
    STW R1 [SP + TF_R1]

    B trap_restore

bad_pointer:
    LI R1 ERR_FAULT
    STW R1 [SP + TF_R1]

    B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
    LDW R4 [R1 + FILE_INODE]
    LDW R4 [R4 + INODE_OPS]
    LDW R4 [R4 + FSOPS_READ]
    JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

    LDW R4 [R1 + FILE_INODE]
    LDW R4 [R4 + INODE_OPS]
    LDW R4 [R4 + FOPS_WRITE]    ; get write function xdev_write from ops
    JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

    B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

    B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
    LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
    LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
    CMP R5 R2                   ; have we read enough bytes?
    BGE dr_done                 ; yes -> return

dr_poll_ready:
    LDW R6 [R4 + 4]             ; read UART_STATUS register
    AND R6 R6 1                 ; bit 0 = RX_READY
    CMP R6 0
    BEQ dr_done                 ; no more buffered input available

    LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
    STB R7 [R1 + R5]            ; store it into the kernel buffer
    ADD R5 R5 1

    ; If we received a newline, stop reading early
    CMP R7 10
    BEQ dr_done

    B dr_loop

dr_done:
    MOV R1 R5                   ; return number of bytes actually read
    RET

;=================================================================
; write /dev/con - to MMIO UART, polling TX_READY before each byte
;================================================================

uart_write_kernel:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Transmits R2 bytes from kernel buffer at R1 through the UART.
    ; Polls the UART_STATUS TX_READY bit before sending each byte.
    ; This is a simple synchronous write that blocks until all bytes are sent.
    ;================================================================

    LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
    LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
    CMP R5 R2                   ; have we written all bytes?
    BGE dcw_done                ; yes -> return

dcw_poll_tx:
    LDW R6 [R4 + 4]             ; read UART_STATUS register
    AND R6 R6 2                 ; bit 1 = TX_READY
    CMP R6 0
    BEQ dcw_done

    LDB R7 [R1 + R5]            ; load next byte from kernel buffer
    STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
    ADD R5 R5 1
    B dcw_loop

dcw_done:
    MOV R1 R5                   ; return number of bytes written
    RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

    LI R1 0
    RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

    PUSH LR
    MOV R6 R3
    CMP R6 0
    BEQ null_write_done

    PUSH R6
    MOV R1 R2
    MOV R2 R6
    LI R3 0                    ; read access from user source
    BL user_buffer_valid_range
    POP R6
    CMP R1 1
    BNE null_write_badptr

null_write_done:
    MOV R1 R6
    POP LR
    RET

null_write_badptr:
    LI R1 ERR_FAULT
    POP LR
    RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

    CMP R1 0
    BLT fd_invalid
    CMP R1 MAX_FDS
    BGE fd_invalid

    MOV R8 R1                   ; preserve fd across task lookup macros
    GET_CURR_TASK_IDX R4
    GET_TASK_PTR R4, R4
    TASK_GET_FD_TABLE R4, R4

    SHL R5 R8 2
    ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
    LDW R1 [R4]                 ; R1 = file ptr
    LDW R6 [R1 + FILE_FLAGS]
    AND R6 R6 R2
    CMP R6 R2
    BNE fd_invalid

    RET                         ;on exit R1 - has file ptr

fd_invalid:
    LI R1 0
    RET

vfs_read:

    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes read or errno
    ;================================================================

    PUSH LR
    MOV R7 R2
    MOV R6 R3

    LI R2 FD_FLAG_READ
    BL fetch_fd_entry

    CMP R1 0
    BEQ vfs_read_badfd

    MOV R9 R1
    MOV R1 R9
    MOV R2 R7
    MOV R3 R6
    BL file_read
    POP LR
    RET

vfs_read_badfd:
    LI R1 ERR_BADF
    POP LR
    RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

    PUSH LR
    MOV R7 R2
    MOV R6 R3

    LI R2 FD_FLAG_WRITE
    BL fetch_fd_entry

    CMP R1 0
    BEQ vfs_write_badfd

    MOV R9 R1
    MOV R1 R9
    MOV R2 R7
    MOV R3 R6
    BL file_write
    POP LR
    RET

vfs_write_badfd:
    LI R1 ERR_BADF
    POP LR
    RET






user_buffer_valid_range:
    ;================================================================
    ; R1 = user ptr, R2 = length, R3 = access type (0=read,1=write)
    ; Returns 1 if the entire user buffer is valid and accessible with
    ; the requested permissions, or 0 if any byte is invalid.
    ; Validation checks:
    ; - length must be > 0
    ; - user pointer must be >= USER_BASE and the end of the buffer must be <= USER_LIMIT
    ; - each page spanned by the buffer must be present (P) and user-accessible (U) in the page table
    ; - if access type is write, pages must also have the writable (W) bit set
    ;================================================================
    PUSH R10
    PUSH R11
    PUSH R12

    LI R4 0
    CMP R2 R4
    BEQ uv_valid

    LI R4 USER_BASE
    CMP R1 R4
    BLT uv_invalid

    LI R4 USER_LIMIT
    ADD R5 R1 R2
    SUB R5 R5 1
    CMP R5 R1
    BLT uv_invalid
    CMP R5 R4
    BGT uv_invalid
    MOV R11 R1              ; save start address; task macros clobber R1
    MOV R12 R5              ; save end address for page calculation
    MOV R4 R3               ; save access type; task macros clobber R3

    GET_CURR_TASK_IDX R6
    GET_TASK_PTR R6, R6
    TASK_GET_PTBR R6, R6
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
    CMP R6 0
    BEQ uv_invalid

uv_check_pages:
    SHR R7 R11 12
    SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

    CMP R7 R8
    BGT uv_valid
    SHL R9 R7 2
    ADD R9 R9 R6
    LDW R10 [R9]
    AND R5 R10 PTE_P
    CMP R5 0
    BEQ uv_invalid
    AND R5 R10 PTE_U
    CMP R5 0
    BEQ uv_invalid
    CMP R4 0
    BEQ uv_check_read
    AND R5 R10 PTE_W
    CMP R5 0
    BEQ uv_invalid
    B uv_next

uv_check_read:
    AND R5 R10 PTE_R
    CMP R5 0
    BEQ uv_invalid

uv_next:
    ADD R7 R7 1
    B uv_loop

uv_valid:
    LI R1 1
    POP R12
    POP R11
    POP R10
    RET

uv_invalid:
    LI R1 0

    POP R12
    POP R11
    POP R10
    RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel 
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
    LI R5 0
cfu_head:
    CMP R2 0
    BEQ cfu_done
    OR R6 R1 R4
    AND R6 R6 3
    CMP R6 0
    BEQ cfu_word
    LDB R7 [R1]
    STB R7 [R4]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B cfu_head
cfu_word:
    CMP R2 4
    BLT cfu_tail
    LDW R7 [R1]
    STW R7 [R4]
    ADD R1 R1 4
    ADD R4 R4 4
    ADD R5 R5 4
    SUB R2 R2 4
    B cfu_word
cfu_tail:
    CMP R2 0
    BEQ cfu_done
    LDB R7 [R1]
    STB R7 [R4]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B cfu_tail
cfu_done:
    MOV R1 R5
    RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel 
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
    LI R5 0
ctu_head:
    CMP R2 0
    BEQ ctu_done
    OR R6 R1 R4
    AND R6 R6 3
    CMP R6 0
    BEQ ctu_word
    LDB R7 [R4]
    STB R7 [R1]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B ctu_head
ctu_word:
    CMP R2 4
    BLT ctu_tail
    LDW R7 [R4]
    STW R7 [R1]
    ADD R1 R1 4
    ADD R4 R4 4
    ADD R5 R5 4
    SUB R2 R2 4
    B ctu_word
ctu_tail:
    CMP R2 0
    BEQ ctu_done
    LDB R7 [R4]
    STB R7 [R1]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B ctu_tail
ctu_done:
    MOV R1 R5
    RET

handle_debug:
    ; Debug trap - just return
    B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL    
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

    CSRR R1 STVAL

    CMP R1 0
    BEQ handle_timer_irq

    CMP R1 1
    BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
    LI R2 0x00102000
    STW R1 [R2 + 8]             ; PIC_ACK = R1
    B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO 
    ;================================================================ 

    LI R2 0x00102000
    LI R3 0
    STW R3 [R2 + 8]             ; PIC_ACK = 0
    
    ; Yield the CPU (reschedule and switch tasks)
    B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

    LI R2 0x00102000
    LI R3 1
    STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
    LI R1 uart_rx_waitq
    BL waitq_wake_all
    LI R1 uart_tx_waitq
    BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
    B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

    POP R1                  ; stval, informational only
    POP R1                  ; scause, informational only
    POP R1
    CSRW SSTATUS R1
    POP R1
    CSRW SFLAGS R1
    POP R1
    CSRW SEPC R1
    POP R1                  ; interrupted task SP
    CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
    POP R15
    POP R14
    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP R7
    POP R6
    POP R5
    POP R4
    POP R3
    POP R2
    POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

    CSRRW SP SSCRATCH SP
    SRET


; ================================================================
; TASK SCHEDULER (compatible with current KR32 assembler)
; ================================================================


;=================================================================
; Trapframe layout on kernel stack (matching trap_entry push order)
;=================================================================


.EQU TF_STVAL,     0          ; trapframe privileged state saved by trap_entry
.EQU TF_SCAUSE,    4
.EQU TF_SSTATUS,   8
.EQU TF_SFLAGS,   12
.EQU TF_SEPC,     16
.EQU TF_USP,      20          ; saved interrupted task SP
.EQU TF_R15,      24          ; saved GPRs, matching trap_restore pop order
.EQU TF_R14,      28
.EQU TF_R12,      32
.EQU TF_R11,      36
.EQU TF_R10,      40
.EQU TF_R9,       44
.EQU TF_R8,       48
.EQU TF_R7,       52
.EQU TF_R6,       56
.EQU TF_R5,       60
.EQU TF_R4,       64
.EQU TF_R3,       68
.EQU TF_R2,       72
.EQU TF_R1,       76

;=============================================================
; System Call Numbers
;=============================================================

.EQU SYS_YIELD,    0
.EQU SYS_EXIT,     1
.EQU SYS_GETPID,   2
.EQU SYS_DEBUG,    3
.EQU SYS_WRITE,    4
.EQU SYS_READ,     5
.EQU SYS_OPEN,     6
.EQU SYS_CLOSE,    7
.EQU SYS_PIPE,     8
.EQU SYS_COUNT,    9

;=============================================================
; Task States
;=============================================================

.EQU TASK_DEAD,        0    ; not runnable, can be recycled for new task
.EQU TASK_READY,       1    ; ready to run
.EQU TASK_RUNNING,     2    ; currently running
.EQU TASK_BLOCKED_IO,  3    ; blocked on I/O operation
.EQU TASK_SLEEPING,    4    ; sleeping/waiting
.EQU TASK_ZOMBIE,      5    ; terminated but not yet reaped

;=============================================================
; Task wait reasons
;=============================================================

.EQU WAIT_NONE,        0
.EQU WAIT_UART_RX,     1
.EQU WAIT_UART_TX,     2
.EQU WAIT_PIPE_READ,   3
.EQU WAIT_PIPE_WRITE,  4

;=============================================================
; Task resume modes
;=============================================================

.EQU RESUME_TRAP,      0
.EQU RESUME_KERNEL,    1

;=============================================================
; Wait queue layout
;=============================================================

; A wait queue is currently a fixed-task bitmask. Bit N means task N is
; waiting on this resource. This is intentionally simple while the kernel
; has a fixed small task table; it can later become a linked list without
; changing device code much.
.EQU WQ_MASK,          0
.EQU WQ_SIZE,          4

; =============================================================
; Task structure offsets
; =============================================================

.EQU TASK_KSP,     0          ; saved kernel trapframe stack pointer
.EQU TASK_USP,     4          ; last saved interrupted task stack pointer
.EQU TASK_PC,      8          ; debug/metadata: entry or last known PC
.EQU TASK_STATE,  12          ; TASK_READY, TASK_RUNNING, etc.
.EQU TASK_PID,    16          ; task ID for debugging/metadata
.EQU TASK_PTBR,   20          ; physical base of this task's page table
.EQU TASK_FD_TABLE, 24        ; pointer to task file descriptor table
.EQU TASK_WAIT,   28          ; WAIT_* reason when task is blocked
.EQU TASK_RESUME, 32          ; RESUME_* mode for TASK_KSP
.EQU TASK_KBUF_WR_PTR, 36     ; pointer to this task's kernel write buffer
.EQU TASK_KBUF_RD_PTR, 40     ; pointer to this task's kernel read buffer
.EQU TASK_DATA_PAGE, 44       ; pointer to this task's data page (for exec/args)
.EQU TASK_USTACK_PAGE, 48     ; physical page backing fixed USER_STACK_VA
.EQU TASK_KSTACK_PAGE, 52     ; identity-mapped physical kernel stack page
.EQU TASK_SIZE       56



; =============================================================
; Task table
; =============================================================

.ORG 0x7000

CURRENT_TASK:
    .WORD 0

;==============================================================
; kernel file pool for 32 openings open can be made for the same fd
; FILE_SIZE = file struct size
; holds list of file structs
;==============================================================

.EQU MAX_FILES, 32    ;max files can be opened

file_pool:
    .SPACE MAX_FILES * FILE_SIZE

file_used:
    .SPACE MAX_FILES * 4

;==============================================================
; File descriptor table per task and device objects
;==============================================================

.EQU MAX_FDS, 120   ;up to a page of 4k for fd tables per task, each entry is 4 bytes (file ptr) so 512 entries

task0_fd_table: ; absolete minimum for stdin/stdout/stderr, can be extended with more files if needed
    .WORD file_stdin
    .WORD file_stdout
    .WORD file_stderr
    .SPACE 13*4 ;MAX_FDS-3

task1_fd_table:
    .WORD file_stdin
    .WORD file_stdout
    .WORD file_stderr
    .SPACE 13*4

task2_fd_table:
    .WORD file_stdin
    .WORD file_stdout
    .WORD file_stderr
    .SPACE 13*4


;==============================================================
; File objects and console device
;==============================================================

file_stdin:
    .WORD con_ops
    .WORD con_device
    .WORD 0
    .WORD FD_FLAG_READ

file_stdout:
    .WORD con_ops
    .WORD con_device
    .WORD 0
    .WORD FD_FLAG_WRITE

file_stderr:
    .WORD con_ops
    .WORD con_device
    .WORD 0
    .WORD FD_FLAG_WRITE

; special con uart related
con_ops:
    .WORD con_read
    .WORD con_write

uart_rx_queue:
    .WORD 0

uart_tx_queue:
    .WORD 0

con_device:
    .WORD uart_rx_queue
    .WORD uart_tx_queue
    .WORD 0x00100000

;pipe ops
pipe_ops:
    .WORD pipe_read
    .WORD pipe_write


;==============================================================
; device registry
; used for open lookups
;==============================================================

dev_console_name:
    .ASCIIZ "/dev/console"

dev_null_name:
    .ASCIIZ "/dev/null"

.EQU DEV_NAME,    0
.EQU DEV_OPS,     4
.EQU DEV_PRIVATE, 8
.EQU DEV_SIZE,    12

.EQU DEVICE_COUNT, 2

device_table:

dev_console:
    .WORD dev_console_name
    .WORD con_ops
    .WORD con_device

dev_null:
    .WORD dev_null_name
    .WORD null_ops
    .WORD null_device

; null device
null_ops:
    .WORD null_read
    .WORD null_write

null_device:
    .WORD 0
    .WORD 0
    .WORD 0

; pipe struct
.EQU MAX_PIPES     4
.EQU PIPE_HEAD     0        ;used for wr to pipe
.EQU PIPE_TAIL     4        ;for rd
.EQU PIPE_COUNT    8        ;amount of wr/rd cycle
.EQU PIPE_RWAIT   12        ;rd waitq - processes waiting read (blocked) like uart_rx_waitq (by bits) task 0 - 1 bit and so on
.EQU PIPE_WWAIT   16        ;wr waitq - current procs waiting for write (blocked)
.EQU PIPE_BUFFER  20        ; curcular pipe buffer of 256 bytes if head or tail get 256 it resets this idx to zero
.EQU PIPE_SIZE    276       ; plus 256 bytes - actual pipes buffer is in here start (ptr+20)

pipe_pool:
    .SPACE MAX_PIPES * PIPE_SIZE

pipe_used:
    .SPACE MAX_PIPES * 4

;==============================================================
; Wait queues owned by the UART console device
;==============================================================

; Separate queues are used for separate blocking conditions. A single UART
; device can wake readers when RX data arrives and writers when TX becomes
; ready, so it owns one queue for each condition.
uart_rx_waitq:
    .WORD 0                    ; WQ_MASK: tasks waiting for RX_READY

uart_tx_waitq:
    .WORD 0                    ; WQ_MASK: tasks waiting for TX_READY

; ==================================================
; VFS ops table struc
; ==================================================
; for TARFS in RO
.EQU FSOPS_OPEN,       0
.EQU FSOPS_READ,       4
.EQU FSOPS_WRITE,      8
.EQU FSOPS_CLOSE,     12
.EQU FSOPS_READDIR,   16
.EQU FSOPS_LOOKUP,    20
; for R/W ops
.EQU FSOPS_CREATE,    24
.EQU FSOPS_UNLINK,    28
.EQU FSOPS_MKDIR,     32
.EQU FSOPS_RMDIR,     36

.EQU FSOPS_SIZE,      40

;VFS inst for tarfs
tarfs_ops:
    .WORD tarfs_open
    .WORD tarfs_read
    .WORD tarfs_write      
    .WORD tarfs_close
    .WORD tarfs_readdir
    .WORD tarfs_lookup
    .WORD 0 ;to do
    .WORD 0
    .WORD 0
    .WORD 0



;VFS inode inst for tarfs
tarfs_inode:
    .WORD tarfs_ops
    .WORD tar_index





; ==================================================
; TARFS - first fs 
; ==================================================

.EQU MAX_TAR_FILES, 64

; TAR index entry layout
.EQU TAR_IDX_NAME,   0     ; ptr to filename string
.EQU TAR_IDX_DATA,   4     ; ptr to file data
.EQU TAR_IDX_SIZE,   8     ; file size
.EQU TAR_IDX_TYPE,  12     ; file or directory
.EQU TAR_IDX_SIZEOF, 16

tar_index:          ; the tar index is a simple array of fixed-size entries, 
                    ; each containing the file name, size, and offset in the tarfs image. 
                    ; The index is populated at boot time by scanning the tarfs image 
                    ; and extracting this metadata for each file. 
                    ; This allows for O(n) lookups by name without 
                    ; parsing the entire tar header on each access.

    .SPACE TAR_IDX_SIZEOF * MAX_TAR_FILES

tar_count:          ; number of files in the tarfs image, 
                    ; set at boot time when the index is populated

    .WORD 0

tar_limit:
    .WORD 0

;==============================================================
; TARFS file header layout and constants
;==============================================================

.EQU TAR_NAME_OFF,      0
.EQU TAR_SIZE_OFF,    124
.EQU TAR_TYPE_OFF,    156

.EQU TAR_HEADER_SIZE, 512

; --------------------------------------------------
; tarfs_lookup - lookup a file in the tar index by name, for open and read operations
;
; in R1 = pathname input (e.g. "/file.txt")
;
; returns:
;   ;R1 = new inode ptr inited for file found in lookup
;   ;R1 = 0 if not found
; --------------------------------------------------

tarfs_lookup:

    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10

    MOV R8 R1              ; pathname
    LDB R2 [R8]
    LI R3 47               ; accept normal absolute paths: "/etc/motd"
    CMP R2 R3
    BNE lookup_path_ready
    ADD R8 R8 1

lookup_path_ready:

    LI R9 0                ; index

    LI R10 tar_count
    LDW R10 [R10]

tar_lookup_loop:

    CMP R9 R10
    BGE tar_lookup_not_found

    ; entry address

    LI R1 tar_index

    LI R2 TAR_IDX_SIZEOF
    MUL R3 R9 R2
    ADD R1 R1 R3            ; 

    ; compare names

    MOV R2 R8

    LDW R1 [R1 + TAR_IDX_NAME]

    BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

    CMP R1 1
    BEQ tar_lookup_found

    ADD R9 R9 1
    B tar_lookup_loop

tar_lookup_found:

    LI R1 tar_index
    LI R2 TAR_IDX_SIZEOF
    MUL R3 R9 R2
    ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

    BL inode_alloc
    CMP R1 0
    BEQ lookup_not_found
    MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

    MOV R1 R10              ; inode
    LI  R2 tarfs_ops        ; ops table
    MOV R3 R11              ; private = tar entry
    LI  R4 INODE_REG        ; FILE type
    LDW R5 [R11 + TAR_IDX_SIZE] ;file size 
    BL inode_init

    MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

    POP R10
    POP R9
    POP R8
    POP LR                  
    RET

tar_lookup_not_found:

    LI R1 0             ; R1 = NULL

    POP R10
    POP R9
    POP R8
    POP LR
    RET


; --------------------------------------------------
; tarfs_init - initialize the tarfs by scanning the tar archive and populating the index
;
; in R1 = tar archive base
; outputs:
; global structs and variables:
;   tar_index - populated with file metadata for lookups
;   tar_count - set to number of files in the archive
; --------------------------------------------------

tarfs_init:

    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    MOV R8 R1                  ; current tar header
    LI R11 tar_limit
    ADD R2 R1 R2
    STW R2 [R11]               ; exclusive end of archive

    LI R9 tar_index            ; current index entry

    LI R10 0                   ; file count

tar_scan_loop:

    CMP R10 MAX_TAR_FILES
    BGE tar_done                ; check before writing the next index entry

    LI R11 tar_limit
    LDW R11 [R11]
    LI R12 TAR_HEADER_SIZE
    ADD R12 R8 R12
    CMP R12 R11
    BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

    LDB R11 [R8 + TAR_NAME_OFF]

    CMP R11 0                   ; if name[0] == 0, this is the end of the archive 
                                ; (two consecutive zero 512-byte blocks)
    BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

    MOV R11 R8

    ADD R11 R11 TAR_NAME_OFF

    STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

    MOV R1 R8
    ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

    BL tar_parse_octal         ; parse octal size from tar header field to binary integer

    MOV R12 R1                 ; save file resulted binary size

    STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

    MOV R11 R8
    LI R2 TAR_HEADER_SIZE
    ADD R11 R11 R2

    STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

    LI R2 TAR_TYPE_OFF
    ADD R2 R8 R2
    LDB R11 [R2]
    STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

    ADD R10 R10 1               ; othewise go to next file count

    ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

    MOV R11 R12

    ; round up to 512 boundary

    LI R2 511
    ADD R11 R11 R2

    SHR R11 R11 9
    SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

    LI R2 TAR_HEADER_SIZE
    ADD R8 R8 R2

    ADD R8 R8 R11           ; advance to next tar header

    LI R12 tar_limit
    LDW R12 [R12]
    CMP R8 R12
    BGTU tar_done            ; file data/padding extends beyond archive

    B tar_scan_loop

tar_done:

    LI R11 tar_count        ; store total file count for this tar archive in global variable

    STW R10 [R11]

    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR

    RET

; --------------------------------------------------
; tar_parse_octal - a history of bit of unix code now in our kenrel!
;
; R1 = ptr to TAR size field
;
; TAR stores size as ASCII octal:
;
;   "144" -> 100 decimal
;
; returns:
;   R1 = binary value (converted from octal string)
; --------------------------------------------------

tar_parse_octal:

    PUSH R2
    PUSH R3
    PUSH R4

    LI   R2 0                  ; result

octal_loop:

    LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

    CMP  R3 0
    BEQ  octal_done

    LI   R4 32                 ; ' '
    CMP  R3 R4
    BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

    LI   R4 48
    SUB  R3 R3 R4

    ; result = result * 8 + digit

    SHL  R2 R2 3               ; multiply by 8

    ADD  R2 R2 R3              ; add digit

    ADD  R1 R1 1               ; advance to next octal character

    B    octal_loop

octal_done:

    MOV  R1 R2                 ; return binary result in R1

    POP  R4
    POP  R3
    POP  R2
    RET
    
; for kputs
newline:
    .ASCIIZ "\r\n"

tarfs_banner:
    .ASCIIZ "[TARFS]\r\n"

etc_path:
    .ASCIIZ "etc/"

bin_path:
    .ASCIIZ "bin/"

;==============================================================
; tarfs_dump_index - a simple debug function to print the contents of the tar index
; for each file, it prints the filename and size. This can be called from a debug
; syscall or from the kernel initialization code after tarfs_init to verify the 
; index was populated correctly.
;==============================================================
tarfs_dump_index:

    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10

    LI R8 0

    LI R10 tar_count
    LDW R10 [R10]

    LI R1 tarfs_banner
    BL kputs

dump_loop:

    CMP R8 R10
    BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

    LI R1 tar_index

    LI R2 TAR_IDX_SIZEOF
    MUL R3 R8 R2

    ADD R9 R1 R3

    ; filename

    LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

    MOV R1 R2
    BL kputs

    ; newline

    LI R1 newline
    BL kputs

    ADD R8 R8 1
    B dump_loop

dump_done:

    POP R10
    POP R9
    POP R8
    POP LR
    RET    

;==============================================================
; TARFS file operations
;==============================================================

;tarfs_ops:
;    .WORD tarfs_read
;    .WORD tarfs_write

;==============================================================
; TARFS tarfs_read:
; R1=file*, R2=user destination, R3=requested length
;==============================================================

tarfs_read:
    
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    MOV R8 R1
    MOV R9 R2
    MOV R10 R3

    CMP R10 0
    BEQ tarfs_read_eof

    PUSH R8
    PUSH R9
    MOV R1 R9
    MOV R2 R10
    LI R3 1                    ; destination must be user-writable
    BL user_buffer_valid_range
    POP R9
    POP R8
    CMP R1 1
    BNE tarfs_read_fault

    LDW R11 [R8 + FILE_PRIVATE]
    LDW R12 [R8 + FILE_OFFSET]
    LDW R4 [R11 + TAR_IDX_SIZE]

    CMP R12 R4
    BGEU tarfs_read_eof

    SUB R4 R4 R12             ; bytes remaining
    CMP R10 R4
    BLEU tarfs_read_count_ready
    MOV R10 R4

tarfs_read_count_ready:
    LDW R4 [R11 + TAR_IDX_DATA]
    ADD R4 R4 R12             ; kernel source
    MOV R1 R9                 ; user destination
    MOV R2 R10
    BL copy_to_user

    ADD R12 R12 R1
    STW R12 [R8 + FILE_OFFSET]
    B tarfs_read_done

tarfs_read_fault:
    LI R1 ERR_FAULT
    B tarfs_read_done

tarfs_read_eof:
    LI R1 0

tarfs_read_done:
    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET

tarfs_write:
    LI R1 ERR_ACCES
    RET
;==========================================================================
;tarfs_readdir - scans tar index reads files in a dir and prints output
; --------------------------------------------------
; tarfs_readdir
;
; R1 = directory prefix
;
; example:
;   "etc/"
;   "bin/"
;
; prints matching entries
; --------------------------------------------------

tarfs_readdir:

    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11

    MOV R8 R1              ; save directory path
    LI R9 0                ; index

    LI R10 tar_count
    LDW R10 [R10]
tr_loop:
    CMP R9 R10
    BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
    LI R1 tar_index
    LI R2 TAR_IDX_SIZEOF
    MUL R3 R9 R2
    ADD R11 R1 R3
    ; entry name
    LDW R1 [R11 + TAR_IDX_NAME]
    MOV R2 R8                       ; src dirname "etc/"
    BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
    CMP R1 1
    BNE tr_next                     ;r1=0 no match

    ; print matching name
    LDW R1 [R11 + TAR_IDX_NAME]
    MOV R2 R8                       ; prefix
    BL skip_prefix                  ; omit prefix nd print just filename

    MOV R12 R1         ; save component ptr
    BL path_component_len ; out R1-length
    MOV R2 R1
    MOV R1 R12
    BL kputsn   ; r1-ptr r2-len of string

    LI R1 newline
    BL kputs

tr_next:
    ADD R9 R9 1                     ;to next entry for check
    B tr_loop
tr_done:
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string 
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

    PUSH LR
    PUSH R8
    MOV R8 R1

kputs_loop:
    LDB R1 [R8]

    CMP R1 0
    BEQ kputs_done

    BL uart_putc

    ADD R8 R8 1

    B kputs_loop

kputs_done:
    POP R8
    POP LR
    RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string 
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
    PUSH LR
    PUSH R8
    PUSH R9
    MOV R8 R1
    MOV R9 R2
kputsn_loop:
    CMP R9 0
    BEQ kputsn_done
    LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
    BL uart_putc
    ADD R8 R8 1
    SUB R9 R9 1
    B kputsn_loop
kputsn_done:
    POP R9
    POP R8
    POP LR
    RET

;=====================================    
; debug put char to uart from kernel
;=====================================
uart_putc:

    LI R3 0x00100000  ; UART MMIO Base Address
poll:
    LDW R2 [R3 + 4]   ; read UART status register
    AND R2 R2 2       ; check if TX ready (bit 1)
    CMP R2 0
    BEQ poll

    STW R1 [R3 + 0]   ; R1 is the character value
    RET



;==============================================================
; Wait queue helpers
;==============================================================

waitq_prepare_sleep:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = WAIT_* reason for debug/task dumps
    ;
    ; Adds the current task to the queue bitmask and marks it blocked.
    ; Device code must re-check hardware readiness after this call. If
    ; the condition is already true, call waitq_cancel_sleep_current.
    ;================================================================

    PUSH R9
    PUSH R10

    MOV R9 R1                  ; preserve wait queue pointer
    MOV R10 R2                 ; preserve debug wait reason

    GET_CURR_TASK_IDX R2       ; R2 = current task index

    LI R4 1
    SHL R4 R4 R2               ; R4 = bit for current task
    LDW R5 [R9 + WQ_MASK]
    OR R5 R5 R4
    STW R5 [R9 + WQ_MASK]

    GET_TASK_PTR R5, R2
    TASK_SET_STATE R5, TASK_BLOCKED_IO
    TASK_SET_WAIT R5, R10

    POP R10
    POP R9
    RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

    PUSH R9

    MOV R9 R1

    GET_CURR_TASK_IDX R2

    LDW R4 [R9 + WQ_MASK]

    LI  R5 1
    SHL R5 R5 R2        ;shift to position of current task bit

    NOT R5 R5           ; invert to get mask for clearing this bit

    AND R4 R4 R5        ; clear current task bit

    STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

    GET_TASK_PTR R5, R2

    TASK_SET_STATE R5, TASK_READY   ;update task state to ready
    TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason

    POP R9
    RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

    PUSH LR
    BL schedule_call
    POP LR
    RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

    PUSH LR

    MOV R9 R1
    LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
    LI R10 0
    STW R10 [R9 + WQ_MASK]     ; consume all queue entries

    LI R2 0                    ; task index

wq_wake_loop:
    CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
    BGE wq_wake_done

    LI R3 1 
    SHL R3 R3 R2               ; R3 = bit for task R2
    AND R4 R8 R3
    CMP R4 0
    BEQ wq_wake_next

    GET_TASK_PTR R5, R2
    TASK_SET_STATE R5, TASK_READY
    TASK_SET_WAIT R5, WAIT_NONE

wq_wake_next:
    ADD R2 R2 1
    B wq_wake_loop

wq_wake_done:
    POP LR
    RET

; just for info ref here actual .equ in the beginning
; flags def
;EQU FD_FLAG_READ,    1
;EQU FD_FLAG_WRITE,   2

; file struc
;EQU FILE_OPS,      0
;EQU FILE_PRIVATE,  4
;EQU FILE_OFFSET,   8
;EQU FILE_FLAGS,    12
;EQU FILE_SIZE,     16

; ops
;EQU FOPS_READ,     0
;EQU FOPS_WRITE,    4
;EQU FOPS_SIZE,     8

; private con_device
;EQU UARTDEV_RX_QUEUE, 0
;EQU UARTDEV_TX_QUEUE, 4
;EQU UARTDEV_MMIO,     8
;EQU UARTDEV_SIZE,     12

; fd
;EQU STDIN_FD,       0
;EQU STDOUT_FD,      1
;EQU STDERR_FD,      2

;==============================================================
; Stack tops
; each task has 2 SP:K-when it runs in kernel space U-when in user space
;==============================================================

.EQU TASK0_KSTACK_TOP, 0x4000
.EQU TASK1_KSTACK_TOP, 0x4200
.EQU TASK2_KSTACK_TOP, 0x4400

.EQU TASK0_USTACK_TOP, 0x6000
.EQU TASK1_USTACK_TOP, 0x6000
.EQU TASK2_USTACK_TOP, 0x6000

; INODE_TYPE
.EQU INODE_REG,   1
.EQU INODE_DIR,   2
.EQU INODE_CHAR,  3
.EQU INODE_PIPE,  4

;eg:
;/etc/motd       REG
;/etc            DIR
;/dev/console    CHAR
;pipe            PIPE

;=================================================================
;INODE POOL
;=================================================================

.EQU MAX_INODES, 64

inode_pool:

    .SPACE INODE_SIZEOF * MAX_INODES

inode_used:

    .SPACE MAX_INODES * 4

;=================================================================
;INODE HELPERS
;=================================================================

;=================================================================
; inode_alloc
; Exactly same pattern as file_alloc:
;
; scan inode_used[]
; find free slot
; mark used
; return &inode_pool[i]
;
; out: R1 = inode ptr
;      R1 = 0 if none
;=================================================================
inode_alloc:
    LI R2 0                      ; index

ia_loop:
    CMP R2 MAX_INODES
    BGE ia_fail

    SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
    LI R4 inode_used
    ADD R4 R4 R3                  ; &inode_used[index]

    LDW R5 [R4]                   ; load used marker
    CMP R5 0
    BEQ ia_found

    ADD R2 R2 1
    B ia_loop

ia_found:
    LI R5 1
    STW R5 [R4]                  ; mark used

    LI R3 INODE_SIZEOF
    MUL R6 R2 R3                 ; offset bytes into inode_pool

    LI R1 inode_pool
    ADD R1 R1 R6                 ; return inode ptr
    RET

ia_fail:
    LI R1 0
    RET

;=================================================================
;
; inode_free
; Exactly like:
;
; file_free:
; 
; Determine slot number from pointer.
; 
;inode ptr
;  ↓
;offset from inode_pool
;  ↓
;index
;  ↓
; inode_used[index]=0
; in: R1-inode ptr
;
;=================================================================
inode_free:
    ; in R1 = inode ptr

    LI R2 inode_pool
    SUB R3 R1 R2                  ; offset from pool base

    LI R4 INODE_SIZEOF
    DIV R5 R3 R4                 ; index

    SHL R5 R5 2                  ; index * 4 (u32 array)
    LI R6 inode_used
    ADD R6 R6 R5                 ; &inode_used[index]

    LI R7 0
    STW R7 [R6]                  ; mark free

    RET

;=================================================================
; inode_init
; 
; Prototype:
;
;  R1 = inode ptr
;  R2 = fs ops ptr
;  R3 = private ptr
;  R4 = inode type
;  R5 = size
;
;=================================================================
inode_init:

    STW R2 [R1 + INODE_OPS]
    STW R3 [R1 + INODE_PRIVATE]
    STW R4 [R1 + INODE_TYPE]
    STW R5 [R1 + INODE_SIZE]
    LI R2 1
    STW R2 [R1 + INODE_REFCNT]
    RET

;=================================================================
; inode_get
;
; Open file:
;
; open("/etc/motd")
;
; another fd references same inode.
; 
; Increment refcount: in R1 - inode ptr
;=================================================================

inode_get:
    LDW R2 [R1 + INODE_REFCNT]
    ADD R2 R2 1
    STW R2 [R1 + INODE_REFCNT]
    RET

;=================================================================
; inode_put
;
; Close file:
; close(fd)
;
; decrement refcount. in R1 - inode ptr
; free inode if no ref
;=================================================================

inode_put:
    PUSH LR
    LDW R2 [R1 + INODE_REFCNT]
    SUB R2 R2 1
    STW R2 [R1 + INODE_REFCNT]
    CMP R2 0
    BNE inode_put_done
    ; destroy inode
    BL inode_free
inode_put_done:
    POP LR
    RET

; ----------------------------------
; vfs_lookup  - "wrapper fs selector"
;
; R1 = pathname
;
; returns:
;   R1 = inode
;   R1 = 0 not found
; ----------------------------------

vfs_lookup:
    PUSH LR
    MOV R8 R1          ; pathname

    BL devfs_lookup    ; 1 check among /dev/.. "files"
    CMP R1 0
    BNE vfs_done

    MOV R1 R8

    BL tarfs_lookup     ; 2 check in rootfs-tarfs /... (both funcs in R1-pathname)
    CMP R1 0
    BEQ vfs_not_found   

vfs_done:
    POP LR          ;3 R1 - return inode
    RET

vfs_not_found:
    LI R1 0         ;it can be just ret but i added it for result clarity
    POP LR          ;or R1 - Nul
    RET

;=================================================================
; vfs_open - open pathname file 
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
    PUSH R8
    PUSH R9
    PUSH R10
    MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
    BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
    CMP R1 0
    BEQ fail_noent
    ;out: R1 new inited inode ptr
    MOV R8 R1            ; save inode ptr

    LDW R2 [R8 + INODE_TYPE]
    LI R3 INODE_DIR
    CMP R2 R3
    BEQ fail_isdir            ; if pathname is a dir

    BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
    CMP R1 0
    BEQ fail_nfile

    MOV R9 R1                ; save file*

    ; initialize file object ; 
    MOV R1 R9                ; R1 file*
    MOV R2 R8                ; inode*
    MOV R3 R10               ; flags
    BL file_init
    
    MOV R1 R9
    BL fd_alloc             ; R1 inited file ptr 
    LI R2 ERR_MFILE
    CMP R1 R2
    BEQ fail_fd
                            ; R1 - holds fd
    POP R10
    POP R9
    POP R8
    RET

fail_fd:
    MOV R1 R9
    ; FILE_GET_INODE R2, R1    ; 
    ; R2 = [R1 file->inode] = inode
    LDW R2 [R1 + FILE_INODE]

    MOV R1 R2
    BL inode_put             ; close inode refcnt--

    MOV R1 R9
    BL file_free
    LI R1 ERR_MFILE
    B  vfs_exit

fail_noent:
    LI R1 ERR_NOENT
    B  vfs_exit
fail_nfile:
    LI R1 ERR_NFILE
    B  vfs_exit
fail_isdir:
    LI R1 ERR_ISDIR
    B  vfs_exit
fail_acces:
    LI R1 ERR_ACCES
vfs_exit:
    POP R10
    POP R9
    POP R8
    RET

;================================================================
; vfs_close - close opened file
; in R1 = fd
; out R1 = 0 / ERR_BADF
;================================================================
vfs_close:
    PUSH LR   
    BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

    CMP R1 0
    BEQ badf_fail

    MOV R8 R1          ; save file*

    LDW R1 [R8 + FILE_INODE]
    BL inode_put       ;decrement refcnt (release inode automatically if refcnt=0)

    MOV R1 R8
    BL file_free    ;in R1 file_ptr in file_pool it marks it as free (NULL)
    POP LR
    RET
badf_fail:
    LI R1 ERR_BADF
    POP LR
    RET


;=================================================================
;FILE HELPERS
;=================================================================

;=================================================================
; file_alloc:
; input none
; output:
; R1 = pointer to FILE object in file_pool
; R1 = 0 if no free slots
;=================================================================

file_alloc:

    LI R2 0                      ; index

fa_loop:
    CMP R2 MAX_FILES
    BGE fa_fail

    SHL R3 R2 2                  ; index * 4
    LI R4 file_used              ; look in file_used list 0 free 1 used
    ADD R4 R4 R3

    LDW R5 [R4]
    CMP R5 0
    BEQ fa_found

    ADD R2 R2 1
    B fa_loop

fa_found:
    LI R5 1
    STW R5 [R4]                  ; mark slot used

    LI R4 FILE_SIZE
    MUL R6 R2 R4

    LI R1 file_pool
    ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
    LI R7 0

    STW R7 [R1 + FILE_OPS]
    STW R7 [R1 + FILE_PRIVATE]
    STW R7 [R1 + FILE_OFFSET]
    STW R7 [R1 + FILE_FLAGS]

    RET

fa_fail:
    LI R1 0
    RET

;=================================================================
; file_free:
; input:
; R1 = pointer to FILE object
; none output
;=================================================================

file_free:

    LI R2 file_pool
    SUB R3 R1 R2                 ; offset from pool base

    LI R4 FILE_SIZE
    DIV R5 R3 R4                 ; slot number

    SHL R5 R5 2                  ; slot * 4

    LI R6 file_used
    ADD R6 R6 R5                 ; address of slot in file_used

    LI R7 0
    STW R7 [R6]                  ; mark free

    RET


; ================================================================
; INIT SCHEDULER
; ================================================================

; --------------------------------------------------
; init_scheduler
; cleans task table,
; Creates:
;   PID 0 = idle
;   PID 1 = task A
;   PID 2 = task B
; Sets CURRENT_TASK=0 to start with the idle task.
; --------------------------------------------------

init_scheduler:

    ;MOV R12 SP ;important we save kernel sp becuse we form stack frame at tasks SPs

    PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------
    
    LI  R1 tasks
    LI  R2 TASK_SIZE
    LI  R3 MAX_TASKS
    MUL R3 R2 R3
    BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

    LI R1 idle_task
    LI R2 0
    BL task_create

    CMP R1 0
    BEQ init_scheduler_fail

    ; ----------------------------------
    ; task A
    ; ----------------------------------

    LI R1 TASK_A_START
    LI R2 1
    BL task_create

    CMP R1 0
    BEQ init_scheduler_fail

    ; ----------------------------------
    ; task B
    ; ----------------------------------

    LI R1 TASK_B_START
    LI R2 2
    BL task_create

    CMP R1 0
    BEQ init_scheduler_fail

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

    LI R2 0
    SET_CURR_TASK_IDX R2

    POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
    RET


init_scheduler_fail:

    DEBUG 99

halt:
    B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

    GET_CURR_TASK_IDX R2       ; R2 = old task index

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

    ADD R3 R2 1

wrap_check:

    CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
    BLT check_task
    LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
    LI R4 TASK_SIZE
    MUL R5 R3 R4
    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

    LDW R7 [R5 + TASK_STATE]

    CMP R7 1
    BEQ do_switch
    ; if not ready go to next task in list
    ADD R3 R3 1
    B wrap_check

; R3 next task is ready - switch to it
; R2 current task
; R3 next (+1) typically

; ================================================================
; CONTEXT SWITCH
; ================================================================

do_switch:

    ; ------------------------------------------------
    ; Save new current task index
    ; ------------------------------------------------
    ; update current task now is next one (+1)
    ; this is used for debugging and also by user_buffer_valid_range 
    ; to find the current page table base for validation of user pointers
    ;      
    SET_CURR_TASK_IDX R3
    MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
    GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
    MOV R3 R8
    MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

    LDW R7 [SP + TF_USP]
    TASK_SET_USP R5, R7

    MOV R7 SP
    TASK_SET_KSP R5, R7

    TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

    GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
    MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

    TASK_GET_PTBR R7, R5
    SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

    TASK_GET_KSP SP, R5

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
    TASK_GET_STATE R7, R9
    CMP R7 TASK_ZOMBIE
    BNE switch_old_reaped
    PUSH R5
    MOV R1 R9
    BL task_destroy
    POP R5

switch_old_reaped:
    TASK_GET_RESUME R7, R5
    CMP R7 RESUME_KERNEL
    BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

    B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12
    PUSH R14
    PUSH R15

    GET_CURR_TASK_IDX R2       ; R2 = old task index

    ADD R3 R2 1

schedule_call_wrap_check:
    CMP R3 MAX_TASKS
    BLT schedule_call_check_task
    LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
    MOV R8 R3
    GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
    MOV R3 R8

    TASK_GET_STATE R7, R5
    CMP R7 TASK_READY               ; check it can be run
    BEQ schedule_call_do_switch

    ADD R3 R3 1
    B schedule_call_wrap_check

schedule_call_do_switch:
    SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
    MOV R8 R3

    GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
    MOV R3 R8

    MOV R7 SP
    TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
    TASK_SET_RESUME R5, RESUME_KERNEL

    GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
    MOV R3 R8

    TASK_GET_PTBR R7, R5       ; load new task's page table
    SETPTBR R7

    TASK_GET_KSP SP, R5        ;restore new task KSP
    TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
    CMP R7 RESUME_KERNEL
    BEQ restore_kernel_context

    B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
    DISABLEINT                  ; RET does jump by LR(R15)
    POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
    POP R14                     ; (in kernel)
    POP R12                     ; DI - to avoid int nesting
    POP R11
    POP R10
    POP R9
    POP R8
    POP R7
    POP R6
    POP R5
    POP R4
    POP R3
    POP R2
    POP R1
    RET
; ================================================================
; Memory and user space layout  
; ================================================================

.EQU PAGE_SIZE      4096
.EQU PAGE_SHIFT     12

.EQU PAGE_ALLOC_BASE 0x00040000

.EQU MAX_PHYS_PAGES 128
.EQU PAGE_ALLOC_END  0x000C0000


; 0 = free
; 1 = allocated

page_bitmap:
    .SPACE 12
    .WORD 1        ; reserve physical page 0xA0000 for the built-in TAR image

;================================================================
; Page allocation routines
; This loop implements a linear search through a bitmap to find a free memory page:

; Initialization: Start checking from page 0 (R2 = 0)

;Bounds check: Stop if we've checked all 128 pages

;Bitmap calculation: For each page index, compute:

;Which byte contains the page's status (divide by 8)

;Which bit within that byte represents the page (modulo 8)

;Status test: Extract the bit to see if it's 0 (free) or 1 (allocated)

;Found condition: When a free page is found (bit = 0):

;Set the bit to 1 (mark as allocated)

;Calculate and return the physical address

;Continue: If page is allocated, increment index and repeat

;The loop will continue until it either finds a free page or exhausts all 128 pages.


;================================================================

page_alloc:

    LI R2 0                  ; page index

pa_loop:
    LI R1 MAX_PHYS_PAGES

    CMP R2 R1
    BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

    MOV R3 R2
    SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

    MOV R4 R2
    AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

    LI R5 page_bitmap
    ADD R5 R5 R3                ; r3 is byte index, add to bitmap base 
                                ; to get address of byte containing this page's bit

    LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

    LI R7 1
    SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

    AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free), 
                                ; non-zero if allocated
    CMP R8 0
    BEQ pa_found                ; if bit is 0, page is free

    ADD R2 R2 1                 ; increment page index and check next page
    B pa_loop

pa_found:

    ; mark page allocated

    OR  R6 R6 R7
    STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

    LI  R9 PAGE_ALLOC_BASE

    MOV R1 R2
    SHL R1 R1 12          ; page_index * 4096

    ADD R1 R1 R9

    RET

pa_fail:

    LI R1 0                     ; no free pages
    RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:

    LI R2 PAGE_ALLOC_BASE
    SUB R3 R1 R2         ; calculate offset from base

    SHR R3 R3 12         ; page index = (addr - BASE)/4096

    MOV R4 R3
    SHR R4 R4 3          ; byte index in bitmap = page index / 8

    MOV R5 R3
    AND R5 R5 7          ; bit index in byte = page index % 8

    LI R6 page_bitmap
    ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

    LDB R7 [R6]

    LI R8 1
    SHL R8 R8 R5         ; mask for this page's bit

    NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

    AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask 
                         ; which has a 0 in the position of the page's bit


    STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

    RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

    LI R2 0

pz_loop:

    CMP R3 0
    BEQ pz_done

    STB R2 [R1]

    ADD R1 R1 1
    SUB R3 R3 1

    B pz_loop

pz_done:
    RET

; ================================================================
; Task management
; ================================================================

.EQU MAX_TASKS 16

tasks:
    .SPACE TASK_SIZE * MAX_TASKS

task_count:
    .WORD 0
; --------------------------------------------------
; task_create
;
; R1 = entry point
; R2 = pid
;
; returns:
;   R1 = task*
;   R1 = 0 on failure
; --------------------------------------------------

task_create:

    PUSH LR

    MOV R8 R1          ; entry
    MOV R9 R2          ; pid
    LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

    BL task_alloc       ; R1 = task pointer or 0 if no free slots

    CMP R1 0
    BEQ task_create_fail

    MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
    MOV R1 R10
    LI R3 TASK_SIZE
    BL mem_zero
    TASK_SET_PC R10, R8
    TASK_SET_PID R10, R9

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail
    
    MOV R12 R1

    TASK_SET_PTBR R10, R1          ; set task page table base

    MOV R1 R12
    LI  R3 PAGE_SIZE
    BL  mem_zero                   ; zero out the sensitive new page table  

    MOV R1 R12
    BL map_common_kernel        ; map kernel space into new page table so task can run in it 
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
    TASK_GET_PC R8, R10
    TASK_GET_PID R9, R10
    TASK_GET_PTBR R1, R10
    MOV R2 R8
    LI R3 0xFFFFF000
    AND R2 R2 R3
    MOV R3 R2
    CMP R9 0
    BEQ task_create_map_kernel_entry
    LI R4 USER_RX
    B task_create_map_entry
task_create_map_kernel_entry:
    LI R4 KERNEL_FLAGS
task_create_map_entry:
    BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail

    MOV R12 R1
    TASK_SET_USTACK_PAGE R10, R12

    LI R11 USER_STACK_TOP
    TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top

    TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it

    LI  R2 USER_STACK_VA
    MOV R3 R12
    LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
    BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail

    TASK_SET_KSTACK_PAGE R10, R1
    LI R2 PAGE_SIZE

    MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

    ADD SP R1 R2           ; last address of the new allocated physical 
                           ; page for kernel stack top

    TASK_GET_PC R8, R10
    TASK_GET_PID R9, R10

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page 
    ; ----------------------------------

    LI R1 0

    PUSH R1            ; R1
    PUSH R1            ; R2
    PUSH R1            ; R3
    PUSH R1            ; R4
    PUSH R1            ; R5
    PUSH R1            ; R6
    PUSH R1            ; R7
    PUSH R1            ; R8
    PUSH R1            ; R9
    PUSH R1            ; R10
    PUSH R1            ; R11
    PUSH R1            ; R12
    PUSH R1            ; R14 (FP)
    PUSH R1            ; R15 (LR)

    PUSH R11           ; R11 - user SP top

    MOV R1 R8
    PUSH R1            ; sepc = entry

    LI R1 0
    PUSH R1            ; sflags

    CMP R9 0
    BEQ task_create_kernel_status
    LI R1 0x20
    B task_create_status_ready
task_create_kernel_status:
    LI R1 0x120
task_create_status_ready:
    PUSH R1            ; sstatus

    LI R1 0
    PUSH R1            ; scause
    PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------
    
    MOV R1 SP
    TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct

    MOV SP R12         ; restore kernel SP after stack frame setup

    TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)

    TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means 
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

    MOV R12 R1

    LI  R3 PAGE_SIZE
    MOV R1 R12
    BL  mem_zero

    ; stdin
    LI  R2 file_stdin
    STW R2 [R12 + 0]

    ; stdout
    LI  R2 file_stdout
    STW R2 [R12 + 4]

    ; stderr
    LI  R2 file_stderr
    STW R2 [R12 + 8]

    TASK_SET_FD_TABLE R10, R12

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail

    TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail

    TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer

    BL page_alloc
    CMP R1 0
    BEQ task_create_fail

    TASK_SET_DATA_PAGE R10, R1              ; set task data page

    MOV R12 R1

    TASK_GET_PTBR R1, R10

    LI  R2 USER_DATA_VA
    MOV R3 R12
    LI  R4 USER_RW
    BL map_page                 ; map task data page into task page table with RW permissions for user

    ; Publish the task only after every required resource and mapping exists.
    TASK_SET_STATE R10, TASK_READY

    MOV R1 R10                              ; return created task pointer

    POP LR
    RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated 
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
    CMP R10 0
    BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
    TASK_GET_PTBR R1, R10
    CMP R1 0
    BEQ task_create_free_ustack
    BL page_free

task_create_free_ustack:
    TASK_GET_USTACK_PAGE R1, R10
    CMP R1 0
    BEQ task_create_free_kstack
    BL page_free

task_create_free_kstack:
    TASK_GET_KSTACK_PAGE R1, R10
    CMP R1 0
    BEQ task_create_free_fd
    BL page_free

task_create_free_fd:
    TASK_GET_FD_TABLE R1, R10
    CMP R1 0
    BEQ task_create_free_kwr
    BL page_free

task_create_free_kwr:
    TASK_GET_KBUF_WR R1, R10
    CMP R1 0
    BEQ task_create_free_krd
    BL page_free

task_create_free_krd:
    TASK_GET_KBUF_RD R1, R10
    CMP R1 0
    BEQ task_create_free_data
    BL page_free

task_create_free_data:
    TASK_GET_DATA_PAGE R1, R10
    CMP R1 0
    BEQ task_create_clear_slot
    BL page_free

task_create_clear_slot:
    MOV R1 R10
    LI R3 TASK_SIZE
    BL mem_zero

task_create_fail_return:
    LI R1 0

    POP LR
    RET

;================================================================
; task_destroy - free all resources of a task and clear its slot in task table
; in R1 = task*
; output none
; note it zeroes the whole slot at the end of func 
; in task table at the end to make sure scheduler won't schedule 
; this task anymore and also to make sure task_create can reuse 
; this slot for a new task in the future
;================================================================
task_destroy:

    PUSH LR
    push R12 ; preserve R12 which we use for temporary storage in this function
    mov  R12 R1 ; R12 = task pointer

    TASK_GET_PTBR R2, R1
    CMP R2 0
    BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning
    
    MOV R1 R2
    BL page_free        ; free process page table 

td_skip_ptbr:

    TASK_GET_USTACK_PAGE R2, R12
    CMP R2 0
    BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
    MOV R1 R2
    BL page_free

td_skip_ustack:

    TASK_GET_KSTACK_PAGE R2, R12
    CMP R2 0
    BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
    MOV R1 R2
    BL page_free

td_skip_kstack:

    TASK_GET_FD_TABLE R2, R12
    CMP R2 0
    BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning   
    MOV R1 R2
    BL page_free

td_skip_fd:

    TASK_GET_KBUF_WR R2, R12
    CMP R2 0
    BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
    MOV R1 R2
    BL page_free

td_skip_kwr:

    TASK_GET_KBUF_RD R2, R12
    CMP R2 0
    BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
    MOV R1 R2
    BL page_free

td_skip_krd:

    TASK_GET_DATA_PAGE R2, R12
    CMP R2 0
    BEQ td_done     ; if task has no user data page, it also has no user buffers to free, so skip freeing user buffers and move to clearing slot and returning
    MOV R1 R2
    BL page_free

td_done:

    MOV R1 R12
    LI  R3 TASK_SIZE
    BL  mem_zero    ; clear the whole task slot for clean slate, 
                    ;this also clears the state to TASK_DEAD which 
                    ; is important to make sure scheduler won't schedule 
                    ; this slot anymore and also to make sure task_create 
                    ; can reuse this slot for a new task in the future
    
    POP R12         ; restore R12
    POP LR
    RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none    
;================================================================

task_close_fds:

    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12

    TASK_GET_FD_TABLE R4, R1
    MOV R12 R4

    LI R5 3              ; skip stdin/out/err
    MOV R11 R5

fd_loop:

    CMP R11 MAX_FDS
    BGE fd_done         ; if we processed all fd slots, we are done

    SHL R6 R11 2
    ADD R10 R12 R6      ; R10 = &fd_table[fd]

    LDW R8 [R10]
    CMP R8 0
    BEQ fd_next         ; if fd slot is empty, skip to next

    MOV R1 R8
    BL file_free
    LI R9 0
    STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
    ADD R11 R11 1
    B fd_loop

fd_done:
    POP R12
    POP R11
    POP R10
    POP R9
    POP R8
    POP LR
    RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
    PUSH LR
    PUSH R8
    PUSH R9
    PUSH R10

    GET_CURR_TASK_IDX R10
    LI R8 0

task_reap_loop:
    CMP R8 MAX_TASKS
    BGE task_reap_done

    CMP R8 R10
    BEQ task_reap_next

    GET_TASK_PTR R9, R8
    TASK_GET_STATE R1, R9
    CMP R1 TASK_ZOMBIE
    BNE task_reap_next

    PUSH R8
    MOV R1 R9
    BL task_destroy
    POP R8

task_reap_next:
    ADD R8 R8 1
    B task_reap_loop

task_reap_done:
    POP R10
    POP R9
    POP R8
    POP LR
    RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

    LI R1 tasks
    LI R2 MAX_TASKS

task_alloc_loop:

    TASK_GET_STATE R3, R1                   ; load task state into R3

    CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
    BEQ task_alloc_found

    ADD R1 R1 TASK_SIZE                     ; move to next task slot

    SUB R2 R2 1
    BNE task_alloc_loop

; no free tasks slots

    LI R1 0
    RET

task_alloc_found:                           ;R1 points to free task slot

    RET

; ==================================================
; TAR index entry
; ==================================================

.EQU TAR_IDX_NAME,     0      ; ptr to filename
.EQU TAR_IDX_DATA,     4      ; ptr to file data
.EQU TAR_IDX_SIZE,     8      ; file size
.EQU TAR_IDX_TYPE,    12      ; file/dir

.EQU TAR_IDX_SIZEOF,  16

; ==================================================
; VFS module
; ==================================================










; need to define and allocate user stuff at user code
.EQU USER_WRITE_BUF, 0x6000
.EQU USER_READ_BUF,  0x6010

; ================================================================
; TASKS
; ================================================================

.ORG 0x9000
; --TASK 0 -------System idle task, runs on kernel space with kernel privs, when no other task is ready. 
; Should never exit.
idle_task:
    ENABLEINT
    LI R1 0
idle_loop:
    ADD R1 R1 1
    DEBUG 1
    ;LI R1 SYS_EXIT
    ;SVC SYS_EXIT
    B idle_loop

; --TASK 1----------------------------------------------
.ORG 0x19000
TASK_A_START:
    li R1 10
write_loop1:
    push R1
    ;DEBUG 2
    ; Prepare a write string in user memory.
    LI R1 USER_WRITE_BUF
    LI R2 0x6C6C6548         ; "Hell"
    STW R2 [R1]
    LI R2 0x57202C6F         ; "o, W"
    STW R2 [R1 + 4]
    LI R2 0x646C726F         ; "orld"
    STW R2 [R1 + 8]
    LI R2 0x21
    STB R2 [R1 + 12]
    LI R2 0x0A
    STB R2 [R1 + 13]

    LI R1 1                 ;fd
   ; DEBUG 1
    LI R2 USER_WRITE_BUF    ; user buff
    LI R3 14                ; len
    SVC SYS_WRITE
    DEBUG 1
    pop R1
    sub R1 R1 1
    cmp r1 0
    BNE write_loop1
    ; Exit after the write test.
    LI R1 SYS_EXIT
    SVC SYS_EXIT

; ---TASK 2---------------------------------------------


.org 0x1a000
TASK_B_START:

    ; Read the built-in TARFS message through open/read/close.
    LI R1 task_b_motd_path
    LI R2 FD_FLAG_READ
    SVC SYS_OPEN
    MOV R8 R1
    CMP R8 0
    BLT task_b_open_fail

    MOV R1 R8
    LI R2 USER_READ_BUF
    LI R3 32
    SVC SYS_READ
    MOV R9 R1

    LI R1 STDOUT_FD
    LI R2 USER_READ_BUF
    MOV R3 R9
    SVC SYS_WRITE

    MOV R1 R8
    SVC SYS_CLOSE

task_b_loop:

    ;=========================================
    ; fd = open("/dev/console", WRITE)
    ;=========================================

    LI R1 task_b_console_path
    LI R2 FD_FLAG_WRITE
    SVC SYS_OPEN
    ;DEBUG 1
    MOV R8 R1                  ; save fd

    ; open failed?
    CMP R8 0
    BLT task_b_open_fail

    ;=========================================
    ; write(fd, msg, len)
    ;=========================================

    MOV R1 R8
    LI R2 task_b_msg
    LI R3 18
    SVC SYS_WRITE
    ;DEBUG 2

    ;=========================================
    ; close(fd)
    ;=========================================

    MOV R1 R8
    SVC SYS_CLOSE

    ; Block until console input is available, then echo exactly the number
    ; of bytes returned by read(). The UART driver stops at newline or after
    ; CONSOLE_INPUT_LEN bytes.
    LI R1 STDIN_FD
    LI R2 USER_READ_BUF
    LI R3 CONSOLE_INPUT_LEN
    SVC SYS_READ
    CMP R1 0
    BLE task_b_yield

    MOV R5 R1
    LI R1 STDOUT_FD
    LI R2 USER_READ_BUF
    MOV R3 R5
    SVC SYS_WRITE

task_b_yield:
    SVC SYS_YIELD
    B task_b_loop

task_b_open_fail:

    LI R1 1
    LI R2 open_fail_msg
    LI R3 11
    SVC SYS_WRITE

    SVC SYS_YIELD

    B task_b_loop

; task2 date page
.org 0x1A100
task_b_console_path:
    .ASCIIZ "/dev/console"

task_b_motd_path:
    .ASCIIZ "/etc/motd"

task_b_msg:
    .ASCIIZ "OPEN WRITE CLOSE\r\n"

task_b_msg_len:
    .WORD 18

open_fail_msg:
    .ASCIIZ "OPEN FAIL\r\n"

open_fail_msg_len:
    .WORD 11

; ================================================================
; Built-in read-only TARFS image
;
; The current TAR scanner only needs the POSIX name, size, and type
; fields. These test headers intentionally leave checksum/owner fields
; zero until the build grows a general binary-asset inclusion step.
; ================================================================
; in 512-byte header:
;TAR_NAME_OFF = 0
;TAR_SIZE_OFF = 124
;TAR_TYPE_OFF = 156
;TAR_HEADER_SIZE = 512

;+-------------------+
;| 512-byte header   |
;+-------------------+
;| file data         |
;+-------------------+
;| padding to 512    |
;+-------------------+
;| next header       |
;+-------------------+

.ORG 0xA0000
tarfs_start:
; etc/motd, 16 bytes         ; filename (offset 0)
    .ASCIIZ "etc/motd"     
    .SPACE 115              ; max filename is 124-1 bytes (0)
    ; at offset 124  - size in octal text format
    .ASCIIZ "00000000020"   
    .SPACE 20               ; unused
    ; at offset 156 type '0' for file
    .ASCIIZ "0"             
    .SPACE 354              ; header remainder till 512
    ; file data 513th byte and so on.... file datain bytes (data starts  - header + 512)
    ; to do = need to check why asciiz dont like comments!  ASM] pass1 error line 4889 addr 0x000A007C: invalid syntax
    .ASCIIZ "Welcome to KR32\n" 
    .SPACE 495              ;padding till 512 - data comes in block chunks of 512 bytes each so if data is less then 512 last small remainder chunk padds till 512 block

; bin/sh, 10 bytes
    .ASCIIZ "bin/sh"
    .SPACE 117
    .ASCIIZ "00000000012"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    .ASCIIZ "#!/bin/sh\n"
    .SPACE 501

; bin/network/if-up, empty placeholder executable
    .ASCIIZ "bin/network/if-up"
    .SPACE 106
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354

; TAR end marker: two zero headers by the tar file standart if tape head reads 2 zero blocks here then its the end of tar archive!
    .SPACE 1024

tarfs_end:
