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

; ============================================================
; KR32 errno definitions
;
; 0  = success
; <0 = error
;
; Inspired by POSIX errno values.
; ============================================================

.EQU ERR_OK,          0

; ------------------------------------------------------------
; Permission / access
; ------------------------------------------------------------

.EQU ERR_PERM,       -1      ; operation not permitted
.EQU ERR_ACCES,     -13      ; permission denied

; ------------------------------------------------------------
; Files / devices
; ------------------------------------------------------------

.EQU ERR_NOENT,      -2      ; no such file/device
.EQU ERR_NODEV,     -19      ; no such device
.EQU ERR_NOTDIR,    -20      ; not a directory
.EQU ERR_ISDIR,     -21      ; is a directory

; ------------------------------------------------------------
; Memory / pointers
; ------------------------------------------------------------

.EQU ERR_NOMEM,     -12      ; out of memory
.EQU ERR_FAULT,     -14      ; invalid user address

; ------------------------------------------------------------
; File descriptor handling
; ------------------------------------------------------------

.EQU ERR_NFILE,     -23      ; system fd table full
.EQU ERR_MFILE,     -24      ; process fd table full
.EQU ERR_BADF,       -9      ; invalid fd

; ------------------------------------------------------------
; Arguments
; ------------------------------------------------------------

.EQU ERR_INVAL,     -22      ; invalid argument
.EQU ERR_NOSYS,     -38      ; syscall not implemented

; ------------------------------------------------------------
; Resource state
; ------------------------------------------------------------

.EQU ERR_BUSY,      -16      ; resource busy
.EQU ERR_EXIST,     -17      ; already exists
.EQU ERR_AGAIN,     -11      ; would block / try again

; ------------------------------------------------------------
; I/O
; ------------------------------------------------------------

.EQU ERR_IO,         -5      ; I/O error
.EQU ERR_NOSPC,     -28      ; no space left on device

; ------------------------------------------------------------
; Pipes
; ------------------------------------------------------------

.EQU ERR_PIPE,      -32      ; broken pipe

.org 0x0000
0x00000000   B KERNEL_START

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
;.EQU TASK0_USTACK_PA, 0x00005000 ; physical memory address stack and data when map pages tasks 0,1,2 in memory image
;.EQU TASK1_USTACK_PA, 0x0000B000 ; func page init makes map in page table for every task (0) runs in kernel mode
;.EQU TASK2_USTACK_PA, 0x0000C000

;memory map used for data validation when make syscalls which transfer data b/w kernel and user
.EQU KERNEL_BASE,     0x0000
.EQU KERNEL_LIMIT,    0x000BFFFF
.EQU USER_BASE,       0x00005000

.EQU USER_STACK_VA,   0x0003F000
.EQU USER_STACK_TOP,  0x00040000
.EQU USER_LIMIT,      0x0003FFFF

.EQU USER_DATA_VA,    0x00006000  ;start of user data page for task (process virtual space) 4 KiB per task
; ================================================================
; Program break management
; ================================================================

; Each task gets a data page at USER_DATA_VA (0x6000)
; We manage a per-task heap within this page

.EQU HEAP_START,    USER_DATA_VA + 0x100   ; Start heap after some reserved space
.EQU HEAP_END,      USER_DATA_VA + 0x1000  ; End of data page


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
.EQU FILE_REFCNT,   12          ;for dup
.EQU FILE_SIZE,     16

; ================================================================
; Time structure for user space
; ================================================================

.EQU TIMEVAL_SEC,   0
.EQU TIMEVAL_USEC,  4
.EQU TIMEVAL_SIZE,  8


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
; --TASK 0 -------System idle task, runs on kernel space with kernel privs, when no other task is ready.
; Should never exit.
idle_task:
0x00001000       ENABLEINT
0x00001004       LI R1 0
idle_loop:
0x0000100C       ADD R1 R1 1
    ;DEBUG 1
0x00001010       B idle_loop

; ================================================================
; PAGE TABLES for each task (1 KiB each, 4 entries x 1024 bytes)
; ================================================================
.org 0x10000
;TASK0_PAGE_TABLE
;TASK0_PTBR:
;        .SPACE 4096             ; 1 KiB page table (1024 entries × 4 bytes)

;.org 0x20000
;TASK1_PAGE_TABLE
;TASK1_PTBR:
;        .SPACE 4096             ; 1 KiB page table

;.org 0x30000
;TASK2_PAGE_TABLE
;TASK2_PTBR:
;q        .SPACE 4096             ; 1 KiB page table


.org 0x2000

; ================================================================
; KERNEL CODE (starts at 0x2000)
; ================================================================
KERNEL_START:
0x00002000   FUNC_ENTER
0x0000200C           LI SP 0x0000F000
0x00002014           MOV FP SP

        ; Initialize unified IDT (all traps go to trap_entry)
0x00002018   CALL init_idt

        ; Initialize Page Tables
        ; check memory_map.txt for current layout
0x00002020   CALL init_page_tables

        ; Init_task_scheduler (hard-coded)
0x00002028   CALL init_scheduler

        ; Initialize MMIO devices (PIC, PIT, UART)
0x00002030   CALL init_mmio_devices

        ; Mount the built-in read-only TAR archive and show its index.
0x00002038           LI R1 tarfs_start
0x00002040           LI R2 tarfs_end
0x00002048           SUB R2 R2 R1
0x0000204C   CALL tarfs_init
0x00002054   CALL tarfs_dump_index

0x0000205C           LI R1 etc_path
0x00002064   CALL tarfs_readdir

0x0000206C           LI R1 bin_path
0x00002074   CALL tarfs_readdir

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
0x0000207C           LI R1 tasks
0x00002084           LDW R2 [R1 + TASK_PTBR]
0x00002088           SETPTBR R2
0x0000208C           LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
0x00002090   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore
0x00002098           B trap_restore

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x000020A0       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x000020A8       LI R2 trap_entry
0x000020B0       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x000020B4       LI R2 trap_entry
0x000020BC       STW R2 [R1+4]                ; IDT[1]
0x000020C0       STW R2 [R1+8]                ; IDT[2]
0x000020C4       STW R2 [R1+12]               ; IDT[3]
0x000020C8       STW R2 [R1+24]               ; IDT[6]
0x000020CC       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x000020D0       SETIDTR R1
0x000020D4       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
0x000020D8       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x000020DC       LI R1 page_bitmap
0x000020E4       LI R3 16
0x000020EC       BL mem_zero

0x000020F4       POP LR
0x000020F8       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x000020FC       PUSH LR
0x00002100       PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
0x00002104       LI R2 0x00000000      ;page 0 - boot (0000)
0x0000210C       LI R3 0x00000000
0x00002114       LI R4 KERNEL_FLAGS
0x0000211C       bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x00002124       LI R2 0x00001000      ; page for kernel buffers
0x0000212C       LI R3 0x00001000
0x00002134       LI R4 KERNEL_FLAGS
0x0000213C       BL map_page

0x00002144       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x0000214C       LI R3 0x00002000
0x00002154       LI R4 KERNEL_FLAGS
0x0000215C       BL map_page

0x00002164       LI R2 0x00003000
0x0000216C       LI R3 0x00003000
0x00002174       LI R4 KERNEL_FLAGS
0x0000217C       BL map_page

0x00002184       LI R2 0x00004000
0x0000218C       LI R3 0x00004000
0x00002194       LI R4 KERNEL_FLAGS
0x0000219C       BL map_page

0x000021A4       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x000021AC       LI R3 0x00007000
0x000021B4       LI R4 KERNEL_FLAGS
0x000021BC       BL map_page

0x000021C4       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x000021CC       LI R3 0x00008000
0x000021D4       LI R4 KERNEL_FLAGS
0x000021DC       BL map_page

0x000021E4       LI R2 0x00009000      ; add page (number is page table entry one) tasks data
0x000021EC       LI R3 0x00009000
0x000021F4       LI R4 KERNEL_FLAGS
0x000021FC       BL map_page

0x00002204       LI R2 0x0000A000      ; add page (number is page table entry one) tasks data
0x0000220C       LI R3 0x0000A000
0x00002214       LI R4 KERNEL_FLAGS
0x0000221C       BL map_page

0x00002224       LI R2 0x0000B000      ; add page (number is page table entry one) tasks data
0x0000222C       LI R3 0x0000B000
0x00002234       LI R4 KERNEL_FLAGS
0x0000223C       BL map_page

    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x00002244       LI R2 0x00100000      ; UART physical and virtual base
0x0000224C       LI R3 0x00100000
0x00002254       LI R4 KERNEL_FLAGS
0x0000225C       BL map_page

0x00002264       LI R2 0x00101000      ; PIT physical and virtual base
0x0000226C       LI R3 0x00101000
0x00002274       LI R4 KERNEL_FLAGS
0x0000227C       BL map_page

0x00002284       LI R2 0x00102000      ; PIC physical and virtual base
0x0000228C       LI R3 0x00102000
0x00002294       LI R4 KERNEL_FLAGS
0x0000229C       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x000022A4       LI R12 PAGE_ALLOC_BASE
0x000022AC       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x000022B4       CMP R12 R7
0x000022B8       BGE map_common_dynamic_done
0x000022C0       MOV R2 R12
0x000022C4       MOV R3 R12
0x000022C8       LI R4 KERNEL_FLAGS
0x000022D0       BL map_page
0x000022D8       LI R6 PAGE_SIZE
0x000022E0       ADD R12 R12 R6
0x000022E4       B map_common_dynamic_loop
map_common_dynamic_done:

0x000022EC       POP R12
0x000022F0       POP LR
0x000022F4       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x000022F8       SHR R5 R2 12               ; VPN
0x000022FC       SHL R5 R5 2                ; page-table byte offset
0x00002300       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002304       STW R6 [R1 + R5]
0x00002308       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x0000230C       LI R1 0x00102000
0x00002314       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x0000231C       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x00002320       LI R1 0x00101000
0x00002328       LI R2 2000
0x00002330       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x00002334       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x0000233C       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x00002340       LI R1 0x00100000
0x00002348       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x00002350       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x00002354       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x00002358       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x0000235C       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x00002360       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x00002364       PUSH R1
0x00002368       PUSH R2
0x0000236C       PUSH R3
0x00002370       PUSH R4
0x00002374       PUSH R5
0x00002378       PUSH R6
0x0000237C       PUSH R7
0x00002380       PUSH R8
0x00002384       PUSH R9
0x00002388       PUSH R10
0x0000238C       PUSH R11
0x00002390       PUSH R12
0x00002394       PUSH R14
0x00002398       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x0000239C       CSRR R1 SSCRATCH
0x000023A0       PUSH R1
0x000023A4       CSRR R1 SEPC
0x000023A8       PUSH R1
0x000023AC       CSRR R1 SFLAGS
0x000023B0       PUSH R1
0x000023B4       CSRR R1 SSTATUS
0x000023B8       PUSH R1
0x000023BC       CSRR R1 SCAUSE
0x000023C0       PUSH R1
0x000023C4       CSRR R1 STVAL
0x000023C8       PUSH R1

    ; Dispatch based on scause.
0x000023CC       CSRR R1 SCAUSE
0x000023D0       CMP R1 0
0x000023D4       BEQ handle_divide_zero

0x000023DC       CMP R1 1
0x000023E0       BEQ handle_invalid_instr

0x000023E8       CMP R1 2
0x000023EC       BEQ handle_page_fault

0x000023F4       CMP R1 3
0x000023F8       BEQ handle_syscall

0x00002400       CMP R1 6
0x00002404       BEQ handle_debug

0x0000240C       CMP R1 16
0x00002410       BEQ handle_irq

    ; Unknown cause - halt
0x00002418       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x0000241C       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x00002424       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x0000242C       HLT

0x00002430       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x00002438       CSRR R2 STVAL

0x0000243C       CMP R2 SYS_COUNT
0x00002440       BGE syscall_unknown

0x00002448       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x00002450       SHL R4 R2 2
0x00002454       LDW R5 [R3 + R4]
0x00002458       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x0000245C       LI R1 ERR_NOSYS
0x00002464       STW R1 [SP + TF_R1]
0x00002468       B trap_restore

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
    .WORD syscall_dup           ; SVC 9
    .WORD syscall_gettime       ; SVC 10
    .WORD syscall_brk           ; SVC 11
    .WORD syscall_sbrk          ; SVC 12

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x000024A4       LI R1 0
0x000024AC       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x000024B0       B schedule_and_switch

syscall_exit:
    ;================================================================
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x000024B8   LI R1 CURRENT_TASK
0x000024C0   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x000024C4   LI R1 TASK_SIZE
0x000024CC   MUL R3 R2 R1
0x000024D0   LI R5 tasks
0x000024D8   ADD R5 R5 R3

0x000024DC       PUSH R5
0x000024E0       MOV R1 R5
0x000024E4       BL task_close_fds      ; close all open file descriptors of this task (if any) to free file_pool resources
0x000024EC       POP R5

    ; Do not destroy the current task here: SP still points into its kernel
    ; stack. Mark it unrecoverable and let idle_task reclaim it later while
    ; running on a different stack.
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x000024F0   LI R1 TASK_ZOMBIE
0x000024F8   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x000024FC   LI R1 WAIT_NONE
0x00002504   STW R1 [R5 + TASK_WAIT]
0x00002508       B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002510   LI R1 CURRENT_TASK
0x00002518   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x0000251C   LI R1 TASK_SIZE
0x00002524   MUL R3 R2 R1
0x00002528   LI R5 tasks
0x00002530   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00002534   LDW R1 [R5 + TASK_PID]

0x00002538       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x0000253C       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00002544       LDW R1 [SP + TF_R1]
0x00002548       STW R1 [SP + TF_R1]

0x0000254C       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00002554       LDW R1 [SP + TF_R1]
0x00002558       LDW R2 [SP + TF_R2]

0x0000255C       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00002564       CMP R1 0
0x00002568       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00002570   LI R1 CURRENT_TASK
0x00002578   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000257C   LI R1 TASK_SIZE
0x00002584   MUL R3 R4 R1
0x00002588   LI R5 tasks
0x00002590   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00002594   LDW R1 [R5 + TASK_KBUF_RD_PTR]

0x00002598       BL vfs_open

0x000025A0       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x000025A4       B trap_restore

open_fail_fault:
0x000025AC       LI R1 ERR_FAULT
0x000025B4       STW R1 [SP + TF_R1]     ;file not opened ERR
0x000025B8       B trap_restore


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
0x000025C0       PUSH LR

0x000025C4       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x000025C8   LI R1 CURRENT_TASK
0x000025D0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000025D4   LI R1 TASK_SIZE
0x000025DC   MUL R3 R4 R1
0x000025E0   LI R5 tasks
0x000025E8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x000025EC   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x000025F0       PUSH R9                    ; original destination returned on success
0x000025F4       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x000025FC       LI R11 KBUFFER_SIZE
0x00002604       CMP R10 R11
0x00002608       BGE copy_path_fail

0x00002610       PUSH R8
0x00002614       PUSH R9
0x00002618       PUSH R10
0x0000261C       MOV R1 R8
0x00002620       LI R2 1
0x00002628       LI R3 0                    ; read access from user source
0x00002630       BL user_buffer_valid_range
0x00002638       POP R10
0x0000263C       POP R9
0x00002640       POP R8
0x00002644       CMP R1 1
0x00002648       BNE copy_path_fail

0x00002650       LDB R4 [R8]
0x00002654       STB R4 [R9]
0x00002658       CMP R4 0
0x0000265C       BEQ copy_path_done

0x00002664       ADD R8 R8 1
0x00002668       ADD R9 R9 1
0x0000266C       ADD R10 R10 1
0x00002670       B copy_path_loop

copy_path_done:
0x00002678       POP R1                     ; original kernel path pointer
0x0000267C       POP LR
0x00002680       RET

copy_path_fail:
0x00002684       POP R1                     ; discard original kernel path pointer
0x00002688       LI R1 0
0x00002690       POP LR
0x00002694       RET

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
0x00002698       PUSH LR
0x0000269C       MOV R8 R1                  ; save pathname ptr

0x000026A0       LI R7 device_table
0x000026A8       LI R9 DEVICE_COUNT

devfs_loop:
0x000026B0       CMP R9 0
0x000026B4       BEQ lookup_fail

    ; compare pathname with device name
0x000026BC       MOV R1 R8
0x000026C0       LDW R2 [R7 + DEV_NAME]
0x000026C4       BL strcmp
0x000026CC       CMP R1 1
0x000026D0       BEQ devfs_found

0x000026D8       ADD R7 R7 DEV_SIZE
0x000026DC       SUB R9 R9 1
0x000026E0       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x000026E8       BL inode_alloc
0x000026F0       CMP R1 0
0x000026F4       BEQ devfs_fail

0x000026FC       MOV R10 R1         ; inode
    ; 2 init inode
0x00002700       LDW R2 [R7 + DEV_OPS]
0x00002704       LDW R3 [R7 + DEV_PRIVATE]
0x00002708       LI  R4 INODE_CHAR       ; inode type for dev - char
0x00002710       LI  R5 0                ; size =0
0x00002718       BL inode_init

0x00002720       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x00002724       POP LR
0x00002728       RET

devfs_fail:
0x0000272C       LI R1 0
0x00002734       POP LR
0x00002738       RET

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

0x0000273C       PUSH LR

0x00002740       MOV R8 R1                  ; save pathname ptr

0x00002744       LI R7 device_table
0x0000274C       LI R9 DEVICE_COUNT

lookup_loop:
0x00002754       CMP R9 0
0x00002758       BEQ lookup_fail

    ; compare pathname with device name

0x00002760       MOV R1 R8
0x00002764       LDW R2 [R7 + DEV_NAME]

0x00002768       BL strcmp

0x00002770       CMP R1 1
0x00002774       BEQ lookup_found

0x0000277C       ADD R7 R7 DEV_SIZE
0x00002780       SUB R9 R9 1
0x00002784       B lookup_loop

lookup_found:

0x0000278C       MOV R1 R7                  ; return device descriptor ptr

0x00002790       POP LR
0x00002794       RET

lookup_fail:

0x00002798       LI R1 0

0x000027A0       POP LR
0x000027A4       RET

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
0x000027A8       LDB R3 [R1]
0x000027AC       LDB R4 [R2]

0x000027B0       CMP R3 R4
0x000027B4       BNE str_not_equal

0x000027BC       CMP R3 0
0x000027C0       BEQ str_equal

0x000027C8       ADD R1 R1 1
0x000027CC       ADD R2 R2 1
0x000027D0       B str_loop

str_equal:
0x000027D8       LI R1 1
0x000027E0       RET

str_not_equal:
0x000027E4       LI R1 0
0x000027EC       RET

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
0x000027F0       PUSH R3
0x000027F4       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x000027F8       LDB R3 [R2]            ; prefix char
0x000027FC       CMP R3 0
0x00002800       BEQ sp_match           ; reached end of prefix?

0x00002808       LDB R4 [R1]            ; string char
0x0000280C       CMP R4 R3
0x00002810       BNE sp_nomatch

0x00002818       ADD R1 R1 1
0x0000281C       ADD R2 R2 1
0x00002820       B sp_loop
sp_match:
0x00002828       LI R1 1                 ;prefix ok
0x00002830       POP R4
0x00002834       POP R3
0x00002838       RET
sp_nomatch:
0x0000283C       LI R1 0                 ; not ok
0x00002844       POP R4
0x00002848       POP R3
0x0000284C       RET

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
0x00002850       PUSH R3
0x00002854       PUSH R4
sk_loop:
0x00002858       LDB R3 [R2]            ; prefix char
0x0000285C       CMP R3 0
0x00002860       BEQ sk_match           ; reached end of prefix
0x00002868       LDB R4 [R1]            ; string char
0x0000286C       CMP R4 R3
0x00002870       BNE sk_nomatch
0x00002878       ADD R1 R1 1
0x0000287C       ADD R2 R2 1
0x00002880       B sk_loop

sk_match:
    ; R1 already points past prefix
0x00002888       POP R4
0x0000288C       POP R3
0x00002890       RET

sk_nomatch:
0x00002894       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x0000289C       POP R4
0x000028A0       POP R3
0x000028A4       RET

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
0x000028A8       PUSH R2
0x000028AC       PUSH R3
0x000028B0       LI R2 0                ; length
pcl_loop:
0x000028B8       LDB R3 [R1]
0x000028BC       CMP R3 0
0x000028C0       BEQ pcl_done
0x000028C8       LI R4 47               ; '/'
0x000028D0       CMP R3 R4
0x000028D4       BEQ pcl_done
0x000028DC       ADD R2 R2 1
0x000028E0       ADD R1 R1 1
0x000028E4       B pcl_loop
pcl_done:
0x000028EC       MOV R1 R2
0x000028F0       POP R3
0x000028F4       POP R2
0x000028F8       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x000028FC       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x00002900       LI R4 0
0x00002908       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x0000290C       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x00002910       LI R4 1
0x00002918       STW R4 [R1 + FILE_REFCNT]
0x0000291C       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x00002920       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x00002924   LI R1 CURRENT_TASK
0x0000292C   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002930   LI R1 TASK_SIZE
0x00002938   MUL R3 R4 R1
0x0000293C   LI R4 tasks
0x00002944   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00002948   LDW R4 [R4 + TASK_FD_TABLE]

0x0000294C       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00002954       CMP R5 MAX_FDS
0x00002958       BGE fd_alloc_fail

0x00002960       SHL R6 R5 2                ; fd * 4
0x00002964       ADD R7 R4 R6               ; &fd_table[fd]

0x00002968       LDW R2 [R7]
0x0000296C       CMP R2 0                   ; 0 - empty
0x00002970       BEQ fd_alloc_found

0x00002978       ADD R5 R5 1
0x0000297C       B fd_alloc_loop

fd_alloc_found:

0x00002984       STW R8 [R7]                ; fd_table[fd] = file*

0x00002988       MOV R1 R5                  ; return fd
0x0000298C       RET

fd_alloc_fail:

0x00002990       LI R1 ERR_MFILE
0x00002998       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x0000299C       LDW R1 [SP + TF_R1]

0x000029A0       BL vfs_close

0x000029A8       LI R1 0
0x000029B0       STW R1 [SP + TF_R1]

0x000029B4       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x000029BC       LDW R7 [SP + TF_R1]

0x000029C0       BL pipe_alloc       ;create new pipe object in pipe_pool
0x000029C8       CMP R1 0
0x000029CC       BEQ pipe_fail_nospc

0x000029D4       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x000029D8       BL file_alloc        ; R1 - created read file ptr for read end
0x000029E0       CMP R1 0
0x000029E4       BEQ pipe_fail_read_fd

0x000029EC       MOV R9 R1           ; new file for read end  in file_pool
0x000029F0       BL inode_alloc      ; get inode for this end file
0x000029F8       CMP R1 0
0x000029FC       BEQ pipe_fail_ia_read_fd
0x00002A04       MOV R10 R1

0x00002A08       LI  R2 pipe_ops         ; pipe_ops table
0x00002A10       MOV R3 R8               ; store our slot pipe*
0x00002A14       LI  R4 INODE_PIPE       ; inode type PIPE
0x00002A1C       LI  R5 0                ; size =0
0x00002A24       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x00002A2C       MOV R1 R9                ; R1 file*
0x00002A30       MOV R2 R10               ; inode*
0x00002A34       LI R3  FD_FLAG_READ      ; flags READ end
0x00002A3C       BL file_init

0x00002A44       MOV R1 R9
0x00002A48       BL fd_alloc                 ; insert read file to fd_table of user process

0x00002A50       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002A58       CMP R1 R2
0x00002A5C       BEQ pipe_fail_read_file

0x00002A64       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x00002A68       BL file_alloc
0x00002A70       CMP R1 0
0x00002A74       BEQ pipe_fail_ia_write_fd
0x00002A7C       MOV R9 R1

0x00002A80       BL inode_alloc      ; get inode for this end file
0x00002A88       CMP R1 0
0x00002A8C       BEQ pipe_fail_ia_write_fd
0x00002A94       MOV R10 R1

0x00002A98       LI  R2 pipe_ops         ; pipe_ops table
0x00002AA0       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x00002AA4       LI  R4 INODE_PIPE       ; inode type PIPE
0x00002AAC       LI  R5 0                ; size =0
0x00002AB4       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x00002ABC       MOV R1 R9                ; R1 file*
0x00002AC0       MOV R2 R10               ; inode*
0x00002AC4       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x00002ACC       BL file_init

0x00002AD4       MOV R1 R9
0x00002AD8       BL  fd_alloc

0x00002AE0       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x00002AE8       CMP R1 R2
0x00002AEC       BEQ pipe_fail_write_file

0x00002AF4       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x00002AF8       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x00002AFC       LI  R2 8     ; len 2 words (8 bytes)
0x00002B04       LI  R3 1     ; mem perm to write cond
0x00002B0C       BL  user_buffer_valid_range
0x00002B14       CMP R1 1
0x00002B18       BNE pipe_fail_both_fds

0x00002B20       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x00002B24       STW R11 [R7 + 4]

0x00002B28       LI R1 0
0x00002B30       STW R1 [SP + TF_R1]

0x00002B34       B trap_restore

pipe_fail:
0x00002B3C       LI R1 ERR_IO
0x00002B44       STW R1 [SP + TF_R1]

0x00002B48       B trap_restore

pipe_fail_both_fds:
0x00002B50       MOV R12 R8
0x00002B54       MOV R1 R11
0x00002B58       BL fd_remove
0x00002B60       CMP R1 0
0x00002B64       BEQ pipe_fail_both_fds_read
0x00002B6C       BL file_free

pipe_fail_both_fds_read:
0x00002B74       MOV R1 R10
0x00002B78       BL fd_remove
0x00002B80       CMP R1 0
0x00002B84       BEQ pipe_fail_free_pipe_fault
0x00002B8C       BL file_free

pipe_fail_free_pipe_fault:
0x00002B94       MOV R1 R12
0x00002B98       BL pipe_free
0x00002BA0       LI R1 ERR_FAULT
0x00002BA8       STW R1 [SP + TF_R1]

0x00002BAC       B trap_restore

pipe_fail_write_file:
0x00002BB4       MOV R12 R8
0x00002BB8       MOV R1 R9
0x00002BBC       BL file_free
0x00002BC4       MOV R1 R10
0x00002BC8       BL fd_remove
0x00002BD0       CMP R1 0
0x00002BD4       BEQ pipe_fail_free_pipe_mfile
0x00002BDC       BL file_free

pipe_fail_free_pipe_mfile:
0x00002BE4       MOV R1 R12
0x00002BE8       BL pipe_free
0x00002BF0       LI R1 ERR_MFILE
0x00002BF8       STW R1 [SP + TF_R1]

0x00002BFC       B trap_restore

pipe_fail_read_fd:
0x00002C04       MOV R12 R8
0x00002C08       MOV R1 R10
0x00002C0C       BL fd_remove
0x00002C14       CMP R1 0
0x00002C18       BEQ pipe_fail_free_pipe_nfile
0x00002C20       BL file_free

pipe_fail_free_pipe_nfile:
0x00002C28       MOV R1 R12
0x00002C2C       BL pipe_free
0x00002C34       LI R1 ERR_NFILE
0x00002C3C       STW R1 [SP + TF_R1]

0x00002C40       B trap_restore

pipe_fail_read_file:
0x00002C48       MOV R12 R8
0x00002C4C       MOV R1 R9
0x00002C50       BL file_free
0x00002C58       MOV R1 R10          ; освободить inode read end
0x00002C5C       BL inode_free
0x00002C64       MOV R1 R12
0x00002C68       BL pipe_free
0x00002C70       LI R1 ERR_MFILE
0x00002C78       STW R1 [SP + TF_R1]

0x00002C7C       B trap_restore

pipe_fail_pipe_only:
0x00002C84       MOV R1 R8
0x00002C88       BL pipe_free
0x00002C90       LI R1 ERR_NFILE
0x00002C98       STW R1 [SP + TF_R1]

0x00002C9C       B trap_restore

pipe_fail_nospc:
0x00002CA4       LI R1 ERR_NOSPC
0x00002CAC       STW R1 [SP + TF_R1]

0x00002CB0       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x00002CB8       MOV R1 R9          ; освобождаем file (read end)
0x00002CBC       BL  file_free
0x00002CC4       MOV R1 R8          ; освобождаем pipe
0x00002CC8       BL  pipe_free
0x00002CD0       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x00002CD8       STW R1 [SP + TF_R1]
0x00002CDC       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x00002CE4       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x00002CE8       BL fd_remove
0x00002CF0       CMP R1 0
0x00002CF4       BEQ skip_file_free_read
0x00002CFC       BL file_free
skip_file_free_read:
0x00002D04       MOV R1 R9          ; освобождаем file (write end)
0x00002D08       BL file_free
0x00002D10       MOV R1 R8          ; освобождаем pipe
0x00002D14       BL pipe_free
0x00002D1C       LI R1 ERR_NFILE
0x00002D24       STW R1 [SP + TF_R1]
0x00002D28       B trap_restore

;===========================================================
; syscall_dup - make another fd for FILE increase refcnt
;
; R1 = old fd
;
; returns:
;   R1 = new fd
;   or R1 = ERR_BADF
;===========================================================

syscall_dup:

0x00002D30       LDW R1 [SP + TF_R1]     ; argument fd

0x00002D34       BL fd_lookup            ; lookup FILE*
0x00002D3C       CMP R1 0
0x00002D40       BEQ dup_badfd
0x00002D48       MOV R8 R1               ; keep FILE*

0x00002D4C       BL file_get             ; FILE.ref++

0x00002D54       MOV R1 R8
0x00002D58       BL fd_alloc             ; try to allocate new fd

0x00002D60       LI R2 ERR_MFILE
0x00002D68       CMP R1 R2
0x00002D6C       BEQ dup_fail_fd

0x00002D74       STW R1 [SP + TF_R1] ;R1 - new fd
0x00002D78       B trap_restore

dup_fail_fd:

0x00002D80       MOV R1 R8
0x00002D84       BL file_put

0x00002D8C       LI R1 ERR_MFILE     ;R1 -err + rollback
0x00002D94       STW R1 [SP + TF_R1]
0x00002D98       B trap_restore

dup_badfd:

0x00002DA0       LI R1 ERR_BADF      ;R1 -err + file not found
0x00002DA8       STW R1 [SP + TF_R1]

0x00002DAC       B trap_restore

;===============================================================
; syscall_gettime
;
; R1 = user pointer to struct timeval
;
; Returns:
;   R1 = 0
;   R1 = ERR_FAULT
;===============================================================

syscall_gettime:

    ;----------------------------------------------------------
    ; Get user pointer
    ;----------------------------------------------------------

0x00002DB4       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x00002DB8       MOV R1 R8
0x00002DBC       LI  R2 TIMEVAL_SIZE
0x00002DC4       LI  R3 1                   ; write access
0x00002DCC       BL  user_buffer_valid_range

0x00002DD4       CMP R1 1
0x00002DD8       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x00002DE0       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x00002DE8   LI R1 CURRENT_TASK
0x00002DF0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002DF4   LI R1 TASK_SIZE
0x00002DFC   MUL R3 R4 R1
0x00002E00   LI R5 tasks
0x00002E08   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x00002E0C   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x00002E10       STW R1 [R6 + TIMEVAL_SEC]
0x00002E14       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x00002E18       MOV R1 R6                  ; kernel source
0x00002E1C       MOV R2 R8                  ; user destination
0x00002E20       LI  R3 TIMEVAL_SIZE        ; size in bytes (8)

0x00002E28       BL copy_to_user

0x00002E30       CMP R1 TIMEVAL_SIZE
0x00002E34       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x00002E3C       LI R1 0
0x00002E44       STW R1 [SP + TF_R1]

0x00002E48       B trap_restore

gettime_badptr:

0x00002E50       LI R1 ERR_FAULT
0x00002E58       STW R1 [SP + TF_R1]

0x00002E5C       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x00002E64       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x00002E68       LI R2 HEAP_START
0x00002E70       CMP R8 R2
0x00002E74       BLT brk_invalid            ; if new break is below data page, return error

0x00002E7C       LI R2 HEAP_END
0x00002E84       CMP R8 R2
0x00002E88       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00002E90   LI R1 CURRENT_TASK
0x00002E98   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002E9C   LI R1 TASK_SIZE
0x00002EA4   MUL R3 R4 R1
0x00002EA8   LI R5 tasks
0x00002EB0   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x00002EB4   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x00002EB8       STW R8 [SP + TF_R1]

0x00002EBC       B trap_restore

brk_invalid:
    ; Return -1
0x00002EC4       LI R1 ERR_FAULT
0x00002ECC       STW R1 [SP + TF_R1]

0x00002ED0       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x00002ED8       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00002EDC   LI R1 CURRENT_TASK
0x00002EE4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002EE8   LI R1 TASK_SIZE
0x00002EF0   MUL R3 R4 R1
0x00002EF4   LI R5 tasks
0x00002EFC   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x00002F00   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x00002F04       ADD R10 R9 R8

    ; Validate it's within the data page
0x00002F08       LI R2 HEAP_START
0x00002F10       CMP R10 R2
0x00002F14       BLT sbrk_invalid

0x00002F1C       LI R2 HEAP_END
0x00002F24       CMP R10 R2
0x00002F28       BGT sbrk_invalid

    ; Return old break
0x00002F30       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x00002F34   STW R10 [R5 + TASK_BREAK]

0x00002F38       B trap_restore

sbrk_invalid:
    ; Return -1
0x00002F40       LI R1 ERR_FAULT
0x00002F48       STW R1 [SP + TF_R1]
0x00002F4C       B trap_restore

;===============================================================
; clock_gettime
;
; Returns current kernel time.
;
; Out:
;   R1 = seconds
;   R2 = microseconds
;===============================================================
clock_gettime:

0x00002F54       LI  R3 timer_ticks
0x00002F5C       LDW R4 [R3]                ; tick counter (2 ms per tick)

    ; seconds = ticks / 500
0x00002F60       MOV R1 R4
0x00002F64       LI  R5 500
0x00002F6C       DIV R1 R1 R5

    ; usec = (ticks % 500) * 2000
0x00002F70       MOD R4 R4 R5
0x00002F74       LI  R5 2000
0x00002F7C       MUL R2 R4 R5

0x00002F80       RET

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

0x00002F84       PUSH LR

0x00002F88       MOV R9 R1              ; file*
0x00002F8C       MOV R7 R2              ; user buffer
0x00002F90       MOV R6 R3              ; requested len

0x00002F94       LDW R9 [R9 + FILE_INODE]
0x00002F98       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x00002F9C       CMP R6 0                ;fast clear from it if len=0
0x00002FA0       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00002FA8       PUSH R7
0x00002FAC       PUSH R6

0x00002FB0       MOV R1 R7
0x00002FB4       MOV R2 R6
0x00002FB8       LI  R3 1               ; write access
0x00002FC0       BL user_buffer_valid_range

0x00002FC8       POP R6
0x00002FCC       POP R7
0x00002FD0       CMP R1 1
0x00002FD4       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00002FDC       LDW R4 [R9 + PIPE_COUNT]
0x00002FE0       CMP R4 0
0x00002FE4       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00002FEC       CMP R6 R4
0x00002FF0       BLT pipe_user_len

0x00002FF8       MOV R5 R4
0x00002FFC       B pipe_have_amount

pipe_user_len:
0x00003004       MOV R5 R6

pipe_have_amount:
0x00003008       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00003010       CMP R10 R5
0x00003014       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x0000301C       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00003020       MOV R12 R9
0x00003024       ADD R12 R12 PIPE_BUFFER
0x00003028       ADD R12 R12 R11         ; addr += tail

0x0000302C       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00003030       MOV R12 R7
0x00003034       ADD R12 R12 R10

0x00003038       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x0000303C       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00003040       LI R2 255
0x00003048       AND R11 R11 R2
0x0000304C       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00003050       LDW R12 [R9 + PIPE_COUNT]
0x00003054       SUB R12 R12 1
0x00003058       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x0000305C       ADD R10 R10 1
0x00003060       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00003068       MOV R1 R9
0x0000306C       ADD R1 R1 PIPE_WWAIT
0x00003070       BL waitq_wake_all
0x00003078       MOV R1 R10          ; read bytes amount
0x0000307C       POP LR
0x00003080       RET

pipe_read_badptr:
0x00003084       LI R1 ERR_FAULT
0x0000308C       POP LR
0x00003090       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00003094       MOV R1 R9
0x00003098       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x0000309C       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x000030A4       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x000030AC       LDW R4 [R9 + PIPE_COUNT]
0x000030B0       CMP R4 0
0x000030B4       BNE pipe_read_retry

0x000030BC       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x000030C4       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x000030CC       LI R2 0

pipe_loop:
0x000030D4       LI  R1 MAX_PIPES
0x000030DC       CMP R2 R1
0x000030E0       BGE pipe_alloc_fail

0x000030E8       SHL R3 R2 2

0x000030EC       LI R4 pipe_used
0x000030F4       ADD R4 R4 R3

0x000030F8       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x000030FC       CMP R5 0                ; 0 -empty
0x00003100       BEQ pipe_found

0x00003108       ADD R2 R2 1
0x0000310C       B pipe_loop

pipe_found:

0x00003114       LI R5 1
0x0000311C       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00003120       LI R4 PIPE_SIZE
0x00003128       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x0000312C       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00003134       ADD R1 R1 R6

0x00003138       LI R7 0                 ; clean it up
0x00003140       STW R7 [R1 + PIPE_HEAD]
0x00003144       STW R7 [R1 + PIPE_TAIL]
0x00003148       STW R7 [R1 + PIPE_COUNT]
0x0000314C       STW R7 [R1 + PIPE_RWAIT]
0x00003150       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00003154       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00003158       LI R1 0
0x00003160       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00003164       LI R2 pipe_pool
0x0000316C       SUB R3 R1 R2

0x00003170       LI R4 PIPE_SIZE
0x00003178       DIV R5 R3 R4

0x0000317C       SHL R5 R5 2
0x00003180       LI R6 pipe_used
0x00003188       ADD R6 R6 R5

0x0000318C       LI R7 0
0x00003194       STW R7 [R6]

0x00003198       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x0000319C       PUSH LR

0x000031A0       MOV R9 R1
0x000031A4       MOV R7 R2
0x000031A8       MOV R6 R3

0x000031AC       LDW R9 [R9 + FILE_INODE]
0x000031B0       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x000031B4       PUSH R7
0x000031B8       PUSH R6

0x000031BC       MOV R1 R7
0x000031C0       MOV R2 R6
0x000031C4       LI  R3 0           ; READ access
0x000031CC       BL user_buffer_valid_range

0x000031D4       POP R6
0x000031D8       POP R7

0x000031DC       CMP R1 1
0x000031E0       BNE pipe_write_badptr

0x000031E8       LI R10 0               ; bytes written
pipe_write_retry:
0x000031F0       CMP R10 R6
0x000031F4       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x000031FC       LDW R11 [R9 + PIPE_COUNT]
0x00003200       LI R2 256
0x00003208       CMP R11 R2
0x0000320C       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00003214       LDW R12 [R9 + PIPE_HEAD]

0x00003218       MOV R4 R7
0x0000321C       ADD R4 R4 R10
0x00003220       LDB R5 [R4]     ; read byte from user buff addr

0x00003224       MOV R4 R9
0x00003228       ADD R4 R4 PIPE_BUFFER
0x0000322C       ADD R4 R4 R12
0x00003230       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00003234       ADD R12 R12 1
0x00003238       LI R2 255
0x00003240       AND R12 R12 R2
0x00003244       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00003248       LDW R4 [R9 + PIPE_COUNT]
0x0000324C       ADD R4 R4 1
0x00003250       STW R4 [R9 + PIPE_COUNT]

; written++
0x00003254       ADD R10 R10 1
0x00003258       B pipe_write_retry

pipe_write_done:
; wake readers
0x00003260       MOV R1 R9
0x00003264       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x00003268       BL waitq_wake_all
0x00003270       MOV R1 R10      ;written bytes
0x00003274       POP LR
0x00003278       RET

pipe_write_badptr:
0x0000327C       LI R1 ERR_FAULT
0x00003284       POP LR
0x00003288       RET

pipe_write_empty:
0x0000328C       LI R1 0
0x00003294       POP LR
0x00003298       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x0000329C       MOV R1 R9
0x000032A0       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x000032A4       LI R2 WAIT_PIPE_WRITE
0x000032AC       BL waitq_prepare_sleep
    ; race check
0x000032B4       LDW R4 [R9 + PIPE_COUNT]
0x000032B8       LI R2 256
0x000032C0       CMP R4 R2
0x000032C4       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x000032CC       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x000032D4       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x000032DC       CMP R1 3
0x000032E0       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x000032E8       CMP R1 MAX_FDS
0x000032EC       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x000032F4       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x000032F8   LI R1 CURRENT_TASK
0x00003300   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00003304   LI R1 TASK_SIZE
0x0000330C   MUL R3 R4 R1
0x00003310   LI R4 tasks
0x00003318   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x0000331C   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x00003320       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x00003324       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x00003328       LDW R1 [R6]                 ; R1 = file* из таблицы
0x0000332C       CMP R1 0
0x00003330       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x00003338       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x0000333C       RET

fd_lookup_invalid:
0x00003340       LI R1 0
0x00003348       LI R2 0
0x00003350       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x00003354       PUSH LR
0x00003358       BL  fd_lookup
0x00003360       CMP R1 0
0x00003364       BEQ fd_remove_invalid

0x0000336C       MOV R8 R1          ; сохраняем file*
0x00003370       LI R3 0
0x00003378       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x0000337C       MOV R1 R8          ; file*
0x00003380       POP LR
0x00003384       RET

fd_remove_invalid:
0x00003388       LI R1 0
0x00003390       POP LR
0x00003394       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003398       LDW R1 [SP + TF_R1]
0x0000339C       LDW R2 [SP + TF_R2]
0x000033A0       LDW R3 [SP + TF_R3]

0x000033A4       BL vfs_read

0x000033AC       STW R1 [SP + TF_R1]
0x000033B0       B trap_restore

; to comply with vfs interface
devfs_open:
0x000033B8       LI R1 0
0x000033C0       RET
devfs_close:
0x000033C4       LI R1 0
0x000033CC       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x000033D0       PUSH LR
0x000033D4       PUSH R8
0x000033D8       PUSH R9
0x000033DC       PUSH R10
0x000033E0       PUSH R11
0x000033E4       PUSH R12
0x000033E8       MOV R9 R1
0x000033EC       MOV R7 R2
0x000033F0       MOV R6 R3
0x000033F4       LI R8 0                    ; total bytes collected
0x000033FC       LDW R9 [R9 + FILE_INODE]
0x00003400       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00003404       CMP R6 0
0x00003408       BEQ read_done

0x00003410       PUSH R7
0x00003414       PUSH R6
0x00003418       PUSH R9
0x0000341C       MOV R1 R7
0x00003420       MOV R2 R6
0x00003424       LI R3 1                ; write access for destination buffer
0x0000342C       BL user_buffer_valid_range
0x00003434       POP R9
0x00003438       POP R6
0x0000343C       POP R7
0x00003440       CMP R1 1
0x00003444       BNE con_read_fault

read_wait_uart_rx:
0x0000344C       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003450       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00003454       AND R5 R5 1                 ; bit 0 = RX_READY
0x00003458       CMP R5 0
0x0000345C       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00003464   LI R1 CURRENT_TASK
0x0000346C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003470   LI R1 TASK_SIZE
0x00003478   MUL R3 R4 R1
0x0000347C   LI R5 tasks
0x00003484   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003488   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x0000348C       MOV R2 R6
0x00003490       MOV R3 R9
0x00003494       PUSH R6
0x00003498       PUSH R7
0x0000349C       PUSH R8
0x000034A0       PUSH R9
0x000034A4       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x000034AC       POP R9
0x000034B0       POP R8
0x000034B4       POP R7
0x000034B8       POP R6

0x000034BC       CMP R1 0
0x000034C0       BEQ read_wait_uart_rx

0x000034C8       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x000034CC   LI R1 CURRENT_TASK
0x000034D4   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x000034D8   LI R1 TASK_SIZE
0x000034E0   MUL R3 R5 R1
0x000034E4   LI R4 tasks
0x000034EC   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000034F0   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with newline before copy_to_user
    ; clobbers temporary registers.
0x000034F4       LI R11 0
0x000034FC       SUB R5 R10 1
0x00003500       ADD R5 R4 R5
0x00003504       LDB R5 [R5]
0x00003508       CMP R5 10
0x0000350C       BNE read_chunk_not_newline
0x00003514       LI R11 1

read_chunk_not_newline:
0x0000351C       PUSH R6
0x00003520       PUSH R7
0x00003524       PUSH R8
0x00003528       PUSH R9
0x0000352C       PUSH R10
0x00003530       PUSH R11
0x00003534       MOV R1 R7              ; user destination
0x00003538       MOV R2 R10
0x0000353C       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00003544       POP R11
0x00003548       POP R10
0x0000354C       POP R9
0x00003550       POP R8
0x00003554       POP R7
0x00003558       POP R6

0x0000355C       ADD R7 R7 R10
0x00003560       ADD R8 R8 R10
0x00003564       SUB R6 R6 R10

0x00003568       CMP R11 1
0x0000356C       BEQ read_complete
0x00003574       CMP R6 0
0x00003578       BGT read_wait_uart_rx

read_complete:
0x00003580       MOV R1 R8
0x00003584       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x0000358C       LI R1 uart_rx_waitq
0x00003594       LI R2 WAIT_UART_RX
0x0000359C       BL waitq_prepare_sleep

0x000035A4       LDW R4 [R9 + UARTDEV_MMIO]
0x000035A8       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x000035AC       AND R10 R10 1
0x000035B0       CMP R10 0
0x000035B4       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x000035BC       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x000035C4       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x000035CC       LI R1 uart_rx_waitq
0x000035D4       BL waitq_cancel_sleep_current

0x000035DC       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x000035E4       LI R1 0
0x000035EC       B read_return

con_read_fault:
0x000035F4       LI R1 ERR_FAULT

read_return:
0x000035FC       POP R12
0x00003600       POP R11
0x00003604       POP R10
0x00003608       POP R9
0x0000360C       POP R8
0x00003610       POP LR
0x00003614       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003618       LDW R1 [SP + TF_R1]
0x0000361C       LDW R2 [SP + TF_R2]
0x00003620       LDW R3 [SP + TF_R3]

0x00003624       BL vfs_write

0x0000362C       STW R1 [SP + TF_R1]
0x00003630       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00003638       PUSH LR
0x0000363C       MOV R9 R1
0x00003640       MOV R7 R2
0x00003644       MOV R6 R3
0x00003648       LDW R9 [R9 + FILE_INODE]
0x0000364C       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00003650       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00003658       CMP R6 0
0x0000365C       BEQ write_done             ;0 bytes

0x00003664       LI R2 KBUFFER_SIZE
0x0000366C       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00003670       BLT write_chunk_small
0x00003678       LI R2 KBUFFER_SIZE

0x00003680       B write_chunk

write_chunk_small:
0x00003688       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x0000368C       PUSH R7
0x00003690       PUSH R6
0x00003694       PUSH R9
0x00003698       PUSH R8
0x0000369C       MOV R1 R7
0x000036A0       MOV R2 R2
0x000036A4       LI R3 0                ; read access for source buffer
0x000036AC       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x000036B4       POP R8
0x000036B8       POP R9
0x000036BC       POP R6
0x000036C0       POP R7
0x000036C4       CMP R1 1
0x000036C8       BNE driver_bad_pointer

0x000036D0       PUSH R7
0x000036D4       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x000036D8   LI R1 CURRENT_TASK
0x000036E0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000036E4   LI R1 TASK_SIZE
0x000036EC   MUL R3 R4 R1
0x000036F0   LI R5 tasks
0x000036F8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x000036FC   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00003700       MOV R1 R7
0x00003704       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x0000370C       MOV R10 R1             ; bytes copied
0x00003710       POP R6
0x00003714       POP R7

0x00003718       PUSH R7
0x0000371C       PUSH R9
0x00003720       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x00003724       LDW R1 [R9 + UARTDEV_MMIO]
0x00003728       LDW R2 [R1 + 4]
0x0000372C       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00003730       CMP R2 0
0x00003734       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x0000373C   LI R1 CURRENT_TASK
0x00003744   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003748   LI R1 TASK_SIZE
0x00003750   MUL R3 R4 R1
0x00003754   LI R5 tasks
0x0000375C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00003760   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x00003764       MOV R2 R10
0x00003768       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x0000376C       BL device_write
0x00003774       POP R6
0x00003778       POP R9
0x0000377C       POP R7

0x00003780       CMP R1 0        ;nothing is written - go again
0x00003784       BEQ write_loop

0x0000378C       ADD R8 R8 R1     ;update ptrs
0x00003790       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x00003794       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x00003798       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x000037A0       LI R1 uart_tx_waitq
0x000037A8       LI R2 WAIT_UART_TX
0x000037B0       BL waitq_prepare_sleep

0x000037B8       LDW R1 [R9 + UARTDEV_MMIO]
0x000037BC       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x000037C0       AND R2 R2 2
0x000037C4       CMP R2 0
0x000037C8       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x000037D0       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x000037D8       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x000037E0       LI R1 uart_tx_waitq
0x000037E8       BL waitq_cancel_sleep_current

0x000037F0       B write_wait_uart_tx

write_done:
0x000037F8       MOV R1 R8
0x000037FC       POP LR
0x00003800       RET

driver_bad_pointer:
0x00003804       LI R1 ERR_FAULT
0x0000380C       POP LR
0x00003810       RET

bad_fd:
0x00003814       LI R1 ERR_BADF
0x0000381C       STW R1 [SP + TF_R1]

0x00003820       B trap_restore

bad_pointer:
0x00003828       LI R1 ERR_FAULT
0x00003830       STW R1 [SP + TF_R1]

0x00003834       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x0000383C       LDW R4 [R1 + FILE_INODE]
0x00003840       LDW R4 [R4 + INODE_OPS]
0x00003844       LDW R4 [R4 + FSOPS_READ]
0x00003848       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x0000384C       LDW R4 [R1 + FILE_INODE]
0x00003850       LDW R4 [R4 + INODE_OPS]
0x00003854       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x00003858       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x0000385C       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00003864       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x0000386C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003870       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00003878       CMP R5 R2                   ; have we read enough bytes?
0x0000387C       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x00003884       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00003888       AND R6 R6 1                 ; bit 0 = RX_READY
0x0000388C       CMP R6 0
0x00003890       BEQ dr_done                 ; no more buffered input available

0x00003898       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x0000389C       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x000038A0       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x000038A4       CMP R7 10
0x000038A8       BEQ dr_done

0x000038B0       B dr_loop

dr_done:
0x000038B8       MOV R1 R5                   ; return number of bytes actually read
0x000038BC       RET

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

0x000038C0       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000038C4       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000038CC       CMP R5 R2                   ; have we written all bytes?
0x000038D0       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x000038D8       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000038DC       AND R6 R6 2                 ; bit 1 = TX_READY
0x000038E0       CMP R6 0
0x000038E4       BEQ dcw_done

0x000038EC       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x000038F0       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x000038F4       ADD R5 R5 1
0x000038F8       B dcw_loop

dcw_done:
0x00003900       MOV R1 R5                   ; return number of bytes written
0x00003904       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00003908       LI R1 0
0x00003910       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00003914       PUSH LR
0x00003918       MOV R6 R3
0x0000391C       CMP R6 0
0x00003920       BEQ null_write_done

0x00003928       PUSH R6
0x0000392C       MOV R1 R2
0x00003930       MOV R2 R6
0x00003934       LI R3 0                    ; read access from user source
0x0000393C       BL user_buffer_valid_range
0x00003944       POP R6
0x00003948       CMP R1 1
0x0000394C       BNE null_write_badptr

null_write_done:
0x00003954       MOV R1 R6
0x00003958       POP LR
0x0000395C       RET

null_write_badptr:
0x00003960       LI R1 ERR_FAULT
0x00003968       POP LR
0x0000396C       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

0x00003970       CMP R1 0
0x00003974       BLT fd_invalid
0x0000397C       CMP R1 MAX_FDS
0x00003980       BGE fd_invalid

0x00003988       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x0000398C   LI R1 CURRENT_TASK
0x00003994   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00003998   LI R1 TASK_SIZE
0x000039A0   MUL R3 R4 R1
0x000039A4   LI R4 tasks
0x000039AC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000039B0   LDW R4 [R4 + TASK_FD_TABLE]

0x000039B4       SHL R5 R8 2
0x000039B8       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x000039BC       LDW R1 [R4]                 ; R1 = file ptr
0x000039C0       LDW R6 [R1 + FILE_FLAGS]
0x000039C4       AND R6 R6 R2
0x000039C8       CMP R6 R2
0x000039CC       BNE fd_invalid

0x000039D4       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x000039D8       LI R1 0
0x000039E0       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x000039E4       PUSH LR
0x000039E8       MOV R7 R2
0x000039EC       MOV R10 R3

0x000039F0       LI R2 FD_FLAG_READ
0x000039F8       BL fetch_fd_entry   ; macro inside destroys R6

0x00003A00       CMP R1 0
0x00003A04       BEQ vfs_read_badfd

0x00003A0C       MOV R9 R1
0x00003A10       MOV R1 R9
0x00003A14       MOV R2 R7
0x00003A18       MOV R3 R10
0x00003A1C       BL file_read
0x00003A24       POP LR
0x00003A28       RET

vfs_read_badfd:
0x00003A2C       LI R1 ERR_BADF
0x00003A34       POP LR
0x00003A38       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x00003A3C       PUSH LR
0x00003A40       MOV R7 R2
0x00003A44       MOV R10 R3

0x00003A48       LI R2 FD_FLAG_WRITE
0x00003A50       BL fetch_fd_entry   ;macro inside desroys R6

0x00003A58       CMP R1 0
0x00003A5C       BEQ vfs_write_badfd

0x00003A64       MOV R9 R1
0x00003A68       MOV R1 R9
0x00003A6C       MOV R2 R7
0x00003A70       MOV R3 R10
0x00003A74       BL file_write
0x00003A7C       POP LR
0x00003A80       RET

vfs_write_badfd:
0x00003A84       LI R1 ERR_BADF
0x00003A8C       POP LR
0x00003A90       RET






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
0x00003A94       PUSH R10
0x00003A98       PUSH R11
0x00003A9C       PUSH R12

0x00003AA0       LI R4 0
0x00003AA8       CMP R2 R4
0x00003AAC       BEQ uv_valid

0x00003AB4       LI R4 USER_BASE
0x00003ABC       CMP R1 R4
0x00003AC0       BLT uv_invalid

0x00003AC8       LI R4 USER_LIMIT
0x00003AD0       ADD R5 R1 R2
0x00003AD4       SUB R5 R5 1
0x00003AD8       CMP R5 R1
0x00003ADC       BLT uv_invalid
0x00003AE4       CMP R5 R4
0x00003AE8       BGT uv_invalid
0x00003AF0       MOV R11 R1              ; save start address; task macros clobber R1
0x00003AF4       MOV R12 R5              ; save end address for page calculation
0x00003AF8       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x00003AFC   LI R1 CURRENT_TASK
0x00003B04   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00003B08   LI R1 TASK_SIZE
0x00003B10   MUL R3 R6 R1
0x00003B14   LI R6 tasks
0x00003B1C   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00003B20   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x00003B24       CMP R6 0
0x00003B28       BEQ uv_invalid

uv_check_pages:
0x00003B30       SHR R7 R11 12
0x00003B34       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00003B38       CMP R7 R8
0x00003B3C       BGT uv_valid
0x00003B44       SHL R9 R7 2
0x00003B48       ADD R9 R9 R6
0x00003B4C       LDW R10 [R9]
0x00003B50       AND R5 R10 PTE_P
0x00003B54       CMP R5 0
0x00003B58       BEQ uv_invalid
0x00003B60       AND R5 R10 PTE_U
0x00003B64       CMP R5 0
0x00003B68       BEQ uv_invalid
0x00003B70       CMP R4 0
0x00003B74       BEQ uv_check_read
0x00003B7C       AND R5 R10 PTE_W
0x00003B80       CMP R5 0
0x00003B84       BEQ uv_invalid
0x00003B8C       B uv_next

uv_check_read:
0x00003B94       AND R5 R10 PTE_R
0x00003B98       CMP R5 0
0x00003B9C       BEQ uv_invalid

uv_next:
0x00003BA4       ADD R7 R7 1
0x00003BA8       B uv_loop

uv_valid:
0x00003BB0       LI R1 1
0x00003BB8       POP R12
0x00003BBC       POP R11
0x00003BC0       POP R10
0x00003BC4       RET

uv_invalid:
0x00003BC8       LI R1 0

0x00003BD0       POP R12
0x00003BD4       POP R11
0x00003BD8       POP R10
0x00003BDC       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003BE0       LI R5 0
cfu_head:
0x00003BE8       CMP R2 0
0x00003BEC       BEQ cfu_done
0x00003BF4       OR R6 R1 R4
0x00003BF8       AND R6 R6 3
0x00003BFC       CMP R6 0
0x00003C00       BEQ cfu_word
0x00003C08       LDB R7 [R1]
0x00003C0C       STB R7 [R4]
0x00003C10       ADD R1 R1 1
0x00003C14       ADD R4 R4 1
0x00003C18       ADD R5 R5 1
0x00003C1C       SUB R2 R2 1
0x00003C20       B cfu_head
cfu_word:
0x00003C28       CMP R2 4
0x00003C2C       BLT cfu_tail
0x00003C34       LDW R7 [R1]
0x00003C38       STW R7 [R4]
0x00003C3C       ADD R1 R1 4
0x00003C40       ADD R4 R4 4
0x00003C44       ADD R5 R5 4
0x00003C48       SUB R2 R2 4
0x00003C4C       B cfu_word
cfu_tail:
0x00003C54       CMP R2 0
0x00003C58       BEQ cfu_done
0x00003C60       LDB R7 [R1]
0x00003C64       STB R7 [R4]
0x00003C68       ADD R1 R1 1
0x00003C6C       ADD R4 R4 1
0x00003C70       ADD R5 R5 1
0x00003C74       SUB R2 R2 1
0x00003C78       B cfu_tail
cfu_done:
0x00003C80       MOV R1 R5
0x00003C84       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003C88       LI R5 0
ctu_head:
0x00003C90       CMP R2 0
0x00003C94       BEQ ctu_done
0x00003C9C       OR R6 R1 R4
0x00003CA0       AND R6 R6 3
0x00003CA4       CMP R6 0
0x00003CA8       BEQ ctu_word
0x00003CB0       LDB R7 [R4]
0x00003CB4       STB R7 [R1]
0x00003CB8       ADD R1 R1 1
0x00003CBC       ADD R4 R4 1
0x00003CC0       ADD R5 R5 1
0x00003CC4       SUB R2 R2 1
0x00003CC8       B ctu_head
ctu_word:
0x00003CD0       CMP R2 4
0x00003CD4       BLT ctu_tail
0x00003CDC       LDW R7 [R4]
0x00003CE0       STW R7 [R1]
0x00003CE4       ADD R1 R1 4
0x00003CE8       ADD R4 R4 4
0x00003CEC       ADD R5 R5 4
0x00003CF0       SUB R2 R2 4
0x00003CF4       B ctu_word
ctu_tail:
0x00003CFC       CMP R2 0
0x00003D00       BEQ ctu_done
0x00003D08       LDB R7 [R4]
0x00003D0C       STB R7 [R1]
0x00003D10       ADD R1 R1 1
0x00003D14       ADD R4 R4 1
0x00003D18       ADD R5 R5 1
0x00003D1C       SUB R2 R2 1
0x00003D20       B ctu_tail
ctu_done:
0x00003D28       MOV R1 R5
0x00003D2C       RET

handle_debug:
    ; Debug trap - just return
0x00003D30       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00003D38       CSRR R1 STVAL

0x00003D3C       CMP R1 0
0x00003D40       BEQ handle_timer_irq

0x00003D48       CMP R1 1
0x00003D4C       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00003D54       LI R2 0x00102000
0x00003D5C       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x00003D60       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00003D68       LI R2 0x00102000
0x00003D70       LI R3 0
0x00003D78       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x00003D7C       LI R1 timer_ticks
0x00003D84       LDW R2 [R1]
0x00003D88       ADD R2 R2 1
0x00003D8C       STW R2 [R1]

    ; Yield the CPU (reschedule and switch tasks)
0x00003D90       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00003D98       LI R2 0x00102000
0x00003DA0       LI R3 1
0x00003DA8       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00003DAC       LI R1 uart_rx_waitq
0x00003DB4       BL waitq_wake_all
0x00003DBC       LI R1 uart_tx_waitq
0x00003DC4       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00003DCC       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00003DD4       POP R1                  ; stval, informational only
0x00003DD8       POP R1                  ; scause, informational only
0x00003DDC       POP R1
0x00003DE0       CSRW SSTATUS R1
0x00003DE4       POP R1
0x00003DE8       CSRW SFLAGS R1
0x00003DEC       POP R1
0x00003DF0       CSRW SEPC R1
0x00003DF4       POP R1                  ; interrupted task SP
0x00003DF8       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00003DFC       POP R15
0x00003E00       POP R14
0x00003E04       POP R12
0x00003E08       POP R11
0x00003E0C       POP R10
0x00003E10       POP R9
0x00003E14       POP R8
0x00003E18       POP R7
0x00003E1C       POP R6
0x00003E20       POP R5
0x00003E24       POP R4
0x00003E28       POP R3
0x00003E2C       POP R2
0x00003E30       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00003E34       CSRRW SP SSCRATCH SP
0x00003E38       SRET


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
.EQU SYS_DUP,      9
.EQU SYS_GETTIME,  10      ; NEW: get time of day - returns seconds since epoch
.EQU SYS_BRK,      11      ; NEW: change program break - memory allocation
.EQU SYS_SBRK,     12      ; NEW: increment program break - memory allocation
.EQU SYS_COUNT,    13      ; count of syscalls

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
.EQU TASK_BREAK,       56     ; current program break ptr
.EQU TASK_SIZE       60



; =============================================================
; important kernel data structures and constants
; =============================================================

.ORG 0x7000

CURRENT_TASK:
    .WORD 0
TIMER_TICKS:
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

;==============================================================
; File objects and console device
;==============================================================

file_stdin:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD FD_FLAG_READ       ; FILE_FLAGS

file_stdout:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD FD_FLAG_WRITE      ; FILE_FLAGS

file_stderr:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD FD_FLAG_WRITE      ; FILE_FLAGS

console_inode:
    .WORD devfs_ops          ; INODE_OPS
    .WORD con_device         ; INODE_PRIVATE
    .WORD INODE_CHAR         ; INODE_TYPE
    .WORD 0                  ; size
    .WORD 1                  ; refcnt

devfs_ops:
    .WORD devfs_open
    .WORD devfs_read
    .WORD devfs_write
    .WORD devfs_close
    .WORD 0
    .WORD devfs_lookup
    .WORD 0
    .WORD 0
    .WORD 0
    .WORD 0

; special con uart related
;con_ops:
;    .WORD con_read
;    .WORD con_write

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
    .WORD devfs_ops
    .WORD con_device

dev_null:
    .WORD dev_null_name
    .WORD devfs_ops
    .WORD null_device

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


tarfs_open:
0x00007BDF       LI R1 0
0x00007BE7       RET

tarfs_close:
0x00007BEB       LI R1 0
0x00007BF3       RET
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

0x00007BF7       PUSH LR
0x00007BFB       PUSH R8
0x00007BFF       PUSH R9
0x00007C03       PUSH R10

0x00007C07       MOV R8 R1              ; pathname
0x00007C0B       LDB R2 [R8]
0x00007C0F       LI R3 47               ; accept normal absolute paths: "/etc/motd"
0x00007C17       CMP R2 R3
0x00007C1B       BNE lookup_path_ready
0x00007C23       ADD R8 R8 1

lookup_path_ready:

0x00007C27       LI R9 0                ; index

0x00007C2F       LI R10 tar_count
0x00007C37       LDW R10 [R10]

tar_lookup_loop:

0x00007C3B       CMP R9 R10
0x00007C3F       BGE tar_lookup_not_found

    ; entry address

0x00007C47       LI R1 tar_index

0x00007C4F       LI R2 TAR_IDX_SIZEOF
0x00007C57       MUL R3 R9 R2
0x00007C5B       ADD R1 R1 R3            ;

    ; compare names

0x00007C5F       MOV R2 R8

0x00007C63       LDW R1 [R1 + TAR_IDX_NAME]

0x00007C67       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x00007C6F       CMP R1 1
0x00007C73       BEQ tar_lookup_found

0x00007C7B       ADD R9 R9 1
0x00007C7F       B tar_lookup_loop

tar_lookup_found:

0x00007C87       LI R1 tar_index
0x00007C8F       LI R2 TAR_IDX_SIZEOF
0x00007C97       MUL R3 R9 R2
0x00007C9B       ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

0x00007C9F       BL inode_alloc
0x00007CA7       CMP R1 0
0x00007CAB       BEQ tar_lookup_not_found
0x00007CB3       MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

0x00007CB7       MOV R1 R10              ; inode
0x00007CBB       LI  R2 tarfs_ops        ; ops table
0x00007CC3       MOV R3 R11              ; private = tar entry
0x00007CC7       LI  R4 INODE_REG        ; FILE type
0x00007CCF       LDW R5 [R11 + TAR_IDX_SIZE] ;file size
0x00007CD3       BL inode_init

0x00007CDB       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x00007CDF       POP R10
0x00007CE3       POP R9
0x00007CE7       POP R8
0x00007CEB       POP LR
0x00007CEF       RET

tar_lookup_not_found:

0x00007CF3       LI R1 0             ; R1 = NULL

0x00007CFB       POP R10
0x00007CFF       POP R9
0x00007D03       POP R8
0x00007D07       POP LR
0x00007D0B       RET


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

0x00007D0F       PUSH LR
0x00007D13       PUSH R8
0x00007D17       PUSH R9
0x00007D1B       PUSH R10
0x00007D1F       PUSH R11
0x00007D23       PUSH R12

0x00007D27       MOV R8 R1                  ; current tar header
0x00007D2B       LI R11 tar_limit
0x00007D33       ADD R2 R1 R2
0x00007D37       STW R2 [R11]               ; exclusive end of archive

0x00007D3B       LI R9 tar_index            ; current index entry

0x00007D43       LI R10 0                   ; file count

tar_scan_loop:

0x00007D4B       CMP R10 MAX_TAR_FILES
0x00007D4F       BGE tar_done                ; check before writing the next index entry

0x00007D57       LI R11 tar_limit
0x00007D5F       LDW R11 [R11]
0x00007D63       LI R12 TAR_HEADER_SIZE
0x00007D6B       ADD R12 R8 R12
0x00007D6F       CMP R12 R11
0x00007D73       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x00007D7B       LDB R11 [R8 + TAR_NAME_OFF]

0x00007D7F       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x00007D83       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x00007D8B       MOV R11 R8

0x00007D8F       ADD R11 R11 TAR_NAME_OFF

0x00007D93       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x00007D97       MOV R1 R8
0x00007D9B       ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

0x00007D9F       BL tar_parse_octal         ; parse octal size from tar header field to binary integer

0x00007DA7       MOV R12 R1                 ; save file resulted binary size

0x00007DAB       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00007DAF       MOV R11 R8
0x00007DB3       LI R2 TAR_HEADER_SIZE
0x00007DBB       ADD R11 R11 R2

0x00007DBF       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00007DC3       LI R2 TAR_TYPE_OFF
0x00007DCB       ADD R2 R8 R2
0x00007DCF       LDB R11 [R2]
0x00007DD3       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00007DD7       ADD R10 R10 1               ; othewise go to next file count

0x00007DDB       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

0x00007DDF       MOV R11 R12

    ; round up to 512 boundary

0x00007DE3       LI R2 511
0x00007DEB       ADD R11 R11 R2

0x00007DEF       SHR R11 R11 9
0x00007DF3       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x00007DF7       LI R2 TAR_HEADER_SIZE
0x00007DFF       ADD R8 R8 R2

0x00007E03       ADD R8 R8 R11           ; advance to next tar header

0x00007E07       LI R12 tar_limit
0x00007E0F       LDW R12 [R12]
0x00007E13       CMP R8 R12
0x00007E17       BGTU tar_done            ; file data/padding extends beyond archive

0x00007E1F       B tar_scan_loop

tar_done:

0x00007E27       LI R11 tar_count        ; store total file count for this tar archive in global variable

0x00007E2F       STW R10 [R11]

0x00007E33       POP R12
0x00007E37       POP R11
0x00007E3B       POP R10
0x00007E3F       POP R9
0x00007E43       POP R8
0x00007E47       POP LR

0x00007E4B       RET

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

0x00007E4F       PUSH R2
0x00007E53       PUSH R3
0x00007E57       PUSH R4

0x00007E5B       LI   R2 0                  ; result

octal_loop:

0x00007E63       LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

0x00007E67       CMP  R3 0
0x00007E6B       BEQ  octal_done

0x00007E73       LI   R4 32                 ; ' '
0x00007E7B       CMP  R3 R4
0x00007E7F       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x00007E87       LI   R4 48
0x00007E8F       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x00007E93       SHL  R2 R2 3               ; multiply by 8

0x00007E97       ADD  R2 R2 R3              ; add digit

0x00007E9B       ADD  R1 R1 1               ; advance to next octal character

0x00007E9F       B    octal_loop

octal_done:

0x00007EA7       MOV  R1 R2                 ; return binary result in R1

0x00007EAB       POP  R4
0x00007EAF       POP  R3
0x00007EB3       POP  R2
0x00007EB7       RET

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

0x00007ED2       PUSH LR
0x00007ED6       PUSH R8
0x00007EDA       PUSH R9
0x00007EDE       PUSH R10

0x00007EE2       LI R8 0

0x00007EEA       LI R10 tar_count
0x00007EF2       LDW R10 [R10]

0x00007EF6       LI R1 tarfs_banner
0x00007EFE       BL kputs

dump_loop:

0x00007F06       CMP R8 R10
0x00007F0A       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00007F12       LI R1 tar_index

0x00007F1A       LI R2 TAR_IDX_SIZEOF
0x00007F22       MUL R3 R8 R2

0x00007F26       ADD R9 R1 R3

    ; filename

0x00007F2A       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x00007F2E       MOV R1 R2
0x00007F32       BL kputs

    ; newline

0x00007F3A       LI R1 newline
0x00007F42       BL kputs

0x00007F4A       ADD R8 R8 1
0x00007F4E       B dump_loop

dump_done:

0x00007F56       POP R10
0x00007F5A       POP R9
0x00007F5E       POP R8
0x00007F62       POP LR
0x00007F66       RET

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

0x00007F6A       PUSH LR
0x00007F6E       PUSH R8
0x00007F72       PUSH R9
0x00007F76       PUSH R10
0x00007F7A       PUSH R11
0x00007F7E       PUSH R12

0x00007F82       MOV R8 R1
0x00007F86       MOV R9 R2
0x00007F8A       MOV R10 R3

0x00007F8E       CMP R10 0
0x00007F92       BEQ tarfs_read_eof

0x00007F9A       PUSH R8
0x00007F9E       PUSH R9
0x00007FA2       MOV R1 R9
0x00007FA6       MOV R2 R10
0x00007FAA       LI R3 1                    ; destination must be user-writable
0x00007FB2       BL user_buffer_valid_range
0x00007FBA       POP R9
0x00007FBE       POP R8
0x00007FC2       CMP R1 1
0x00007FC6       BNE tarfs_read_fault

0x00007FCE       LDW R11 [R8 + FILE_INODE]
0x00007FD2       LDW R11 [R11 + INODE_PRIVATE]

0x00007FD6       LDW R12 [R8 + FILE_OFFSET]
0x00007FDA       LDW R4 [R11 + TAR_IDX_SIZE]

0x00007FDE       CMP R12 R4
0x00007FE2       BGEU tarfs_read_eof

0x00007FEA       SUB R4 R4 R12             ; bytes remaining
0x00007FEE       CMP R10 R4
0x00007FF2       BLEU tarfs_read_count_ready
0x00007FFA       MOV R10 R4

tarfs_read_count_ready:
0x00007FFE       LDW R4 [R11 + TAR_IDX_DATA]
0x00008002       ADD R4 R4 R12             ; kernel source
0x00008006       MOV R1 R9                 ; user destination
0x0000800A       MOV R2 R10
0x0000800E       BL copy_to_user

0x00008016       ADD R12 R12 R1
0x0000801A       STW R12 [R8 + FILE_OFFSET]
0x0000801E       B tarfs_read_done

tarfs_read_fault:
0x00008026       LI R1 ERR_FAULT
0x0000802E       B tarfs_read_done

tarfs_read_eof:
0x00008036       LI R1 0

tarfs_read_done:
0x0000803E       POP R12
0x00008042       POP R11
0x00008046       POP R10
0x0000804A       POP R9
0x0000804E       POP R8
0x00008052       POP LR
0x00008056       RET

tarfs_write:
0x0000805A       LI R1 ERR_ACCES
0x00008062       RET
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

0x00008066       PUSH LR
0x0000806A       PUSH R8
0x0000806E       PUSH R9
0x00008072       PUSH R10
0x00008076       PUSH R11

0x0000807A       MOV R8 R1              ; save directory path
0x0000807E       LI R9 0                ; index

0x00008086       LI R10 tar_count
0x0000808E       LDW R10 [R10]
tr_loop:
0x00008092       CMP R9 R10
0x00008096       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x0000809E       LI R1 tar_index
0x000080A6       LI R2 TAR_IDX_SIZEOF
0x000080AE       MUL R3 R9 R2
0x000080B2       ADD R11 R1 R3
    ; entry name
0x000080B6       LDW R1 [R11 + TAR_IDX_NAME]
0x000080BA       MOV R2 R8                       ; src dirname "etc/"
0x000080BE       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000080C6       CMP R1 1
0x000080CA       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x000080D2       LDW R1 [R11 + TAR_IDX_NAME]
0x000080D6       MOV R2 R8                       ; prefix
0x000080DA       BL skip_prefix                  ; omit prefix nd print just filename

0x000080E2       MOV R12 R1         ; save component ptr
0x000080E6       BL path_component_len ; out R1-length
0x000080EE       MOV R2 R1
0x000080F2       MOV R1 R12
0x000080F6       BL kputsn   ; r1-ptr r2-len of string

0x000080FE       LI R1 newline
0x00008106       BL kputs

tr_next:
0x0000810E       ADD R9 R9 1                     ;to next entry for check
0x00008112       B tr_loop
tr_done:
0x0000811A       POP R11
0x0000811E       POP R10
0x00008122       POP R9
0x00008126       POP R8
0x0000812A       POP LR
0x0000812E       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x00008132       PUSH LR
0x00008136       PUSH R8
0x0000813A       MOV R8 R1

kputs_loop:
0x0000813E       LDB R1 [R8]

0x00008142       CMP R1 0
0x00008146       BEQ kputs_done

0x0000814E       BL uart_putc

0x00008156       ADD R8 R8 1

0x0000815A       B kputs_loop

kputs_done:
0x00008162       POP R8
0x00008166       POP LR
0x0000816A       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x0000816E       PUSH LR
0x00008172       PUSH R8
0x00008176       PUSH R9
0x0000817A       MOV R8 R1
0x0000817E       MOV R9 R2
kputsn_loop:
0x00008182       CMP R9 0
0x00008186       BEQ kputsn_done
0x0000818E       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x00008192       BL uart_putc
0x0000819A       ADD R8 R8 1
0x0000819E       SUB R9 R9 1
0x000081A2       B kputsn_loop
kputsn_done:
0x000081AA       POP R9
0x000081AE       POP R8
0x000081B2       POP LR
0x000081B6       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x000081BA       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x000081C2       LDW R2 [R3 + 4]   ; read UART status register
0x000081C6       AND R2 R2 2       ; check if TX ready (bit 1)
0x000081CA       CMP R2 0
0x000081CE       BEQ poll

0x000081D6       STW R1 [R3 + 0]   ; R1 is the character value
0x000081DA       RET



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

0x000081DE       PUSH R9
0x000081E2       PUSH R10

0x000081E6       MOV R9 R1                  ; preserve wait queue pointer
0x000081EA       MOV R10 R2                 ; preserve debug wait reason

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x000081EE   LI R1 CURRENT_TASK
0x000081F6   LDW R2 [R1]

0x000081FA       LI R4 1
0x00008202       SHL R4 R4 R2               ; R4 = bit for current task
0x00008206       LDW R5 [R9 + WQ_MASK]
0x0000820A       OR R5 R5 R4
0x0000820E       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00008212   LI R1 TASK_SIZE
0x0000821A   MUL R3 R2 R1
0x0000821E   LI R5 tasks
0x00008226   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x0000822A   LI R1 TASK_BLOCKED_IO
0x00008232   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00008236   STW R10 [R5 + TASK_WAIT]

0x0000823A       POP R10
0x0000823E       POP R9
0x00008242       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00008246       PUSH R9

0x0000824A       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x0000824E   LI R1 CURRENT_TASK
0x00008256   LDW R2 [R1]

0x0000825A       LDW R4 [R9 + WQ_MASK]

0x0000825E       LI  R5 1
0x00008266       SHL R5 R5 R2        ;shift to position of current task bit

0x0000826A       NOT R5 R5           ; invert to get mask for clearing this bit

0x0000826E       AND R4 R4 R5        ; clear current task bit

0x00008272       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x00008276   LI R1 TASK_SIZE
0x0000827E   MUL R3 R2 R1
0x00008282   LI R5 tasks
0x0000828A   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x0000828E   LI R1 TASK_READY
0x00008296   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x0000829A   LI R1 WAIT_NONE
0x000082A2   STW R1 [R5 + TASK_WAIT]

0x000082A6       POP R9
0x000082AA       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000082AE       PUSH LR
0x000082B2       BL schedule_call
0x000082BA       POP LR
0x000082BE       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x000082C2       PUSH LR

0x000082C6       MOV R9 R1
0x000082CA       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x000082CE       LI R10 0
0x000082D6       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x000082DA       LI R2 0                    ; task index

wq_wake_loop:
0x000082E2       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x000082E6       BGE wq_wake_done

0x000082EE       LI R3 1
0x000082F6       SHL R3 R3 R2               ; R3 = bit for task R2
0x000082FA       AND R4 R8 R3
0x000082FE       CMP R4 0
0x00008302       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x0000830A   LI R1 TASK_SIZE
0x00008312   MUL R3 R2 R1
0x00008316   LI R5 tasks
0x0000831E   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00008322   LI R1 TASK_READY
0x0000832A   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000832E   LI R1 WAIT_NONE
0x00008336   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x0000833A       ADD R2 R2 1
0x0000833E       B wq_wake_loop

wq_wake_done:
0x00008346       POP LR
0x0000834A       RET

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
0x0000894E       LI R2 0                      ; index

ia_loop:
0x00008956       CMP R2 MAX_INODES
0x0000895A       BGE ia_fail

0x00008962       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x00008966       LI R4 inode_used
0x0000896E       ADD R4 R4 R3                  ; &inode_used[index]

0x00008972       LDW R5 [R4]                   ; load used marker
0x00008976       CMP R5 0
0x0000897A       BEQ ia_found

0x00008982       ADD R2 R2 1
0x00008986       B ia_loop

ia_found:
0x0000898E       LI R5 1
0x00008996       STW R5 [R4]                  ; mark used

0x0000899A       LI R3 INODE_SIZEOF
0x000089A2       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x000089A6       LI R1 inode_pool
0x000089AE       ADD R1 R1 R6                 ; return inode ptr
0x000089B2       RET

ia_fail:
0x000089B6       LI R1 0
0x000089BE       RET

;=================================================================
;
; inode_free
; Exactly like:
; file_free
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

0x000089C2       LI R2 inode_pool
0x000089CA       SUB R3 R1 R2                  ; offset from pool base

0x000089CE       LI R4 INODE_SIZEOF
0x000089D6       DIV R5 R3 R4                 ; index

0x000089DA       SHL R5 R5 2                  ; index * 4 (u32 array)
0x000089DE       LI R6 inode_used
0x000089E6       ADD R6 R6 R5                 ; &inode_used[index]

0x000089EA       LI R7 0
0x000089F2       STW R7 [R6]                  ; mark free

0x000089F6       RET

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

0x000089FA       STW R2 [R1 + INODE_OPS]
0x000089FE       STW R3 [R1 + INODE_PRIVATE]
0x00008A02       STW R4 [R1 + INODE_TYPE]
0x00008A06       STW R5 [R1 + INODE_SIZE]
0x00008A0A       LI R2 1
0x00008A12       STW R2 [R1 + INODE_REFCNT]
0x00008A16       RET

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
0x00008A1A       LDW R2 [R1 + INODE_REFCNT]
0x00008A1E       ADD R2 R2 1
0x00008A22       STW R2 [R1 + INODE_REFCNT]
0x00008A26       RET

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
0x00008A2A       PUSH LR
0x00008A2E       LDW R2 [R1 + INODE_REFCNT]
0x00008A32       SUB R2 R2 1
0x00008A36       STW R2 [R1 + INODE_REFCNT]
0x00008A3A       CMP R2 0
0x00008A3E       BNE inode_put_done
    ; destroy inode
0x00008A46       BL inode_free

inode_put_done:
0x00008A4E       POP LR
0x00008A52       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x00008A56       LDW R2 [R1 + FILE_REFCNT]
0x00008A5A       ADD R2 R2 1
0x00008A5E       STW R2 [R1 + FILE_REFCNT]
0x00008A62       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x00008A66       PUSH LR
0x00008A6A       LDW R2 [R1 + FILE_REFCNT]
0x00008A6E       SUB R2 R2 1
0x00008A72       STW R2 [R1 + FILE_REFCNT]
0x00008A76       CMP R2 0
0x00008A7A       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x00008A82       BL file_free

file_put_done:
0x00008A8A       POP LR
0x00008A8E       RET


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
0x00008A92       PUSH LR
0x00008A96       MOV R8 R1          ; pathname

0x00008A9A       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x00008AA2       CMP R1 0
0x00008AA6       BNE vfs_done

0x00008AAE       MOV R1 R8

0x00008AB2       BL tarfs_lookup     ; 2 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x00008ABA       CMP R1 0
0x00008ABE       BEQ vfs_not_found

vfs_done:
0x00008AC6       POP LR          ;3 R1 - return inode
0x00008ACA       RET

vfs_not_found:
0x00008ACE       LI R1 0         ;it can be just ret but i added it for result clarity
0x00008AD6       POP LR          ;or R1 - Nul
0x00008ADA       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x00008ADE       PUSH LR
0x00008AE2       PUSH R8
0x00008AE6       PUSH R9
0x00008AEA       PUSH R10
0x00008AEE       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x00008AF2       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x00008AFA       CMP R1 0
0x00008AFE       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x00008B06       MOV R8 R1            ; save inode ptr

0x00008B0A       LDW R2 [R8 + INODE_TYPE]
0x00008B0E       LI R3 INODE_DIR
0x00008B16       CMP R2 R3
0x00008B1A       BEQ fail_isdir            ; if pathname is a dir

0x00008B22       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x00008B2A       CMP R1 0
0x00008B2E       BEQ fail_nfile

0x00008B36       MOV R9 R1                ; save file*

    ; initialize file object ;
0x00008B3A       MOV R1 R9                ; R1 file*
0x00008B3E       MOV R2 R8                ; inode*
0x00008B42       MOV R3 R10               ; flags
0x00008B46       BL file_init

0x00008B4E       MOV R1 R9
0x00008B52       BL fd_alloc             ; R1 inited file ptr
0x00008B5A       LI R2 ERR_MFILE
0x00008B62       CMP R1 R2
0x00008B66       BEQ fail_fd
                            ; R1 - holds fd
0x00008B6E       POP R10
0x00008B72       POP R9
0x00008B76       POP R8
0x00008B7A       POP LR
0x00008B7E       RET

fail_fd:
0x00008B82       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x00008B86       LDW R2 [R1 + FILE_INODE]

0x00008B8A       MOV R1 R2
0x00008B8E       BL inode_put             ; close inode refcnt--

0x00008B96       MOV R1 R9
0x00008B9A       BL file_free
0x00008BA2       LI R1 ERR_MFILE
0x00008BAA       B  vfs_exit

fail_noent:
0x00008BB2       LI R1 ERR_NOENT
0x00008BBA       B  vfs_exit
fail_nfile:
0x00008BC2       LI R1 ERR_NFILE
0x00008BCA       B  vfs_exit
fail_isdir:
0x00008BD2       LI R1 ERR_ISDIR
0x00008BDA       B  vfs_exit
fail_acces:
0x00008BE2       LI R1 ERR_ACCES
vfs_exit:
0x00008BEA       POP R10
0x00008BEE       POP R9
0x00008BF2       POP R8
0x00008BF6       POP LR
0x00008BFA       RET

;================================================================
; vfs_close - close opened file
;
; in R1 = fd
; out R1 = 0 / ERR_BADF
;
; for documentation:
;fd_remove() — removes one file descriptor.
;file_put() — removes one FILE reference.
;file_free() — destroys the FILE and releases its inode.
;inode_put() — destroys the inode when the last FILE releases it.
;================================================================
vfs_close:
0x00008BFE       PUSH LR
0x00008C02       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x00008C0A       CMP R1 0
0x00008C0E       BEQ badf_fail

0x00008C16       MOV R8 R1          ; save file*

0x00008C1A       MOV R1 R8
0x00008C1E       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x00008C26       LI  R1 0        ; success
0x00008C2E       POP LR
0x00008C32       RET

badf_fail:
0x00008C36       LI R1 ERR_BADF
0x00008C3E       POP LR
0x00008C42       RET


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

0x00008C46       LI R2 0                      ; index

fa_loop:
0x00008C4E       CMP R2 MAX_FILES
0x00008C52       BGE fa_fail

0x00008C5A       SHL R3 R2 2                  ; index * 4
0x00008C5E       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00008C66       ADD R4 R4 R3

0x00008C6A       LDW R5 [R4]
0x00008C6E       CMP R5 0
0x00008C72       BEQ fa_found

0x00008C7A       ADD R2 R2 1
0x00008C7E       B fa_loop

fa_found:
0x00008C86       LI R5 1
0x00008C8E       STW R5 [R4]                  ; mark slot used

0x00008C92       LI R4 FILE_SIZE
0x00008C9A       MUL R6 R2 R4

0x00008C9E       LI R1 file_pool
0x00008CA6       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x00008CAA       LI R7 0

0x00008CB2       STW R7 [R1 + FILE_INODE]
0x00008CB6       STW R7 [R1 + FILE_OFFSET]
0x00008CBA       STW R7 [R1 + FILE_FLAGS]

0x00008CBE       RET

fa_fail:
0x00008CC2       LI R1 0
0x00008CCA       RET

;=================================================================
; file_free: - destroy file object
; input:
; R1 = pointer to FILE object
; none output
; note it also updates inode if it exists and destroys
; inode if inode.refcnt=0
;=================================================================

file_free:

 ; release inode first
0x00008CCE       PUSH LR
0x00008CD2       PUSH R10
0x00008CD6       MOV  R10 R1
0x00008CDA       LDW  R2 [R1 + FILE_INODE]

0x00008CDE       CMP R2 0
0x00008CE2       BEQ no_inode

0x00008CEA       MOV R1 R2
0x00008CEE       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x00008CF6       MOV R1 R10
0x00008CFA       LI  R2 file_pool
0x00008D02       SUB R3 R1 R2                 ; offset from pool base

0x00008D06       LI  R4 FILE_SIZE
0x00008D0E       DIV R5 R3 R4                 ; slot number

0x00008D12       SHL R5 R5 2                  ; slot * 4

0x00008D16       LI  R6 file_used
0x00008D1E       ADD R6 R6 R5                 ; address of slot in file_used

0x00008D22       LI R7 0
0x00008D2A       STW R7 [R6]                  ; mark free
0x00008D2E       POP R10
0x00008D32       POP LR
0x00008D36       RET


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

0x00008D3A       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x00008D3E       LI  R1 tasks
0x00008D46       LI  R2 TASK_SIZE
0x00008D4E       LI  R3 MAX_TASKS
0x00008D56       MUL R3 R2 R3
0x00008D5A       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x00008D62       LI R1 idle_task
0x00008D6A       LI R2 0
0x00008D72       BL task_create

0x00008D7A       CMP R1 0
0x00008D7E       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task A
    ; ----------------------------------

  ;  LI R1 TASK_A_START
  ;  LI R2 1
  ;  BL task_create

  ;  CMP R1 0
  ;  BEQ init_scheduler_fail

    ; ----------------------------------
    ; task B
    ; ----------------------------------

0x00008D86       LI R1 TASK_B_START
0x00008D8E       LI R2 2
0x00008D96       BL task_create

0x00008D9E       CMP R1 0
0x00008DA2       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task C -check gettime brk,sbrk syscalls
    ; ----------------------------------

0x00008DAA       LI R1 TASK_C_START
0x00008DB2       LI R2 3
0x00008DBA       BL task_create

0x00008DC2       CMP R1 0
0x00008DC6       BEQ init_scheduler_fail

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x00008DCE       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x00008DD6   LI R1 CURRENT_TASK
0x00008DDE   STW R2 [R1]

0x00008DE2       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00008DE6       RET


init_scheduler_fail:

0x00008DEA       DEBUG 99

halt:
0x00008DEE       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00008DF6   LI R1 CURRENT_TASK
0x00008DFE   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x00008E02       ADD R3 R2 1

wrap_check:

0x00008E06       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x00008E0A       BLT check_task
0x00008E12       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x00008E1A       LI R4 TASK_SIZE
0x00008E22       MUL R5 R3 R4
0x00008E26       LI R6 tasks
0x00008E2E       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00008E32       LDW R7 [R5 + TASK_STATE]

0x00008E36       CMP R7 1
0x00008E3A       BEQ do_switch
    ; if not ready go to next task in list
0x00008E42       ADD R3 R3 1
0x00008E46       B wrap_check

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
; macro: SET_CURR_TASK_IDX R3
0x00008E4E   LI R1 CURRENT_TASK
0x00008E56   STW R3 [R1]
0x00008E5A       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x00008E5E   LI R1 TASK_SIZE
0x00008E66   MUL R3 R2 R1
0x00008E6A   LI R5 tasks
0x00008E72   ADD R5 R5 R3
0x00008E76       MOV R3 R8
0x00008E7A       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x00008E7E       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00008E82   STW R7 [R5 + TASK_USP]

0x00008E86       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00008E8A   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x00008E8E   LI R1 RESUME_TRAP
0x00008E96   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00008E9A   LI R1 TASK_SIZE
0x00008EA2   MUL R3 R8 R1
0x00008EA6   LI R5 tasks
0x00008EAE   ADD R5 R5 R3
0x00008EB2       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x00008EB6   LDW R7 [R5 + TASK_PTBR]
0x00008EBA       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x00008EBE   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x00008EC2   LDW R7 [R9 + TASK_STATE]
0x00008EC6       CMP R7 TASK_ZOMBIE
0x00008ECA       BNE switch_old_reaped
0x00008ED2       PUSH R5
0x00008ED6       MOV R1 R9
0x00008EDA       BL task_destroy
0x00008EE2       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x00008EE6   LDW R7 [R5 + TASK_RESUME]
0x00008EEA       CMP R7 RESUME_KERNEL
0x00008EEE       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x00008EF6       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x00008EFE       PUSH R1
0x00008F02       PUSH R2
0x00008F06       PUSH R3
0x00008F0A       PUSH R4
0x00008F0E       PUSH R5
0x00008F12       PUSH R6
0x00008F16       PUSH R7
0x00008F1A       PUSH R8
0x00008F1E       PUSH R9
0x00008F22       PUSH R10
0x00008F26       PUSH R11
0x00008F2A       PUSH R12
0x00008F2E       PUSH R14
0x00008F32       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00008F36   LI R1 CURRENT_TASK
0x00008F3E   LDW R2 [R1]

0x00008F42       ADD R3 R2 1

schedule_call_wrap_check:
0x00008F46       CMP R3 MAX_TASKS
0x00008F4A       BLT schedule_call_check_task
0x00008F52       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00008F5A       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x00008F5E   LI R1 TASK_SIZE
0x00008F66   MUL R3 R8 R1
0x00008F6A   LI R5 tasks
0x00008F72   ADD R5 R5 R3
0x00008F76       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00008F7A   LDW R7 [R5 + TASK_STATE]
0x00008F7E       CMP R7 TASK_READY               ; check it can be run
0x00008F82       BEQ schedule_call_do_switch

0x00008F8A       ADD R3 R3 1
0x00008F8E       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00008F96   LI R1 CURRENT_TASK
0x00008F9E   STW R3 [R1]
0x00008FA2       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00008FA6   LI R1 TASK_SIZE
0x00008FAE   MUL R3 R2 R1
0x00008FB2   LI R5 tasks
0x00008FBA   ADD R5 R5 R3
0x00008FBE       MOV R3 R8

0x00008FC2       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x00008FC6   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x00008FCA   LI R1 RESUME_KERNEL
0x00008FD2   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x00008FD6   LI R1 TASK_SIZE
0x00008FDE   MUL R3 R8 R1
0x00008FE2   LI R5 tasks
0x00008FEA   ADD R5 R5 R3
0x00008FEE       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x00008FF2   LDW R7 [R5 + TASK_PTBR]
0x00008FF6       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x00008FFA   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x00008FFE   LDW R7 [R5 + TASK_RESUME]
0x00009002       CMP R7 RESUME_KERNEL
0x00009006       BEQ restore_kernel_context

0x0000900E       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x00009016       DISABLEINT                  ; RET does jump by LR(R15)
0x0000901A       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x0000901E       POP R14                     ; (in kernel)
0x00009022       POP R12                     ; DI - to avoid int nesting
0x00009026       POP R11
0x0000902A       POP R10
0x0000902E       POP R9
0x00009032       POP R8
0x00009036       POP R7
0x0000903A       POP R6
0x0000903E       POP R5
0x00009042       POP R4
0x00009046       POP R3
0x0000904A       POP R2
0x0000904E       POP R1
0x00009052       RET
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

0x00009066       LI R2 0                  ; page index

pa_loop:
0x0000906E       LI R1 MAX_PHYS_PAGES

0x00009076       CMP R2 R1
0x0000907A       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00009082       MOV R3 R2
0x00009086       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x0000908A       MOV R4 R2
0x0000908E       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00009092       LI R5 page_bitmap
0x0000909A       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x0000909E       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x000090A2       LI R7 1
0x000090AA       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x000090AE       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x000090B2       CMP R8 0
0x000090B6       BEQ pa_found                ; if bit is 0, page is free

0x000090BE       ADD R2 R2 1                 ; increment page index and check next page
0x000090C2       B pa_loop

pa_found:

    ; mark page allocated

0x000090CA       OR  R6 R6 R7
0x000090CE       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x000090D2       LI  R9 PAGE_ALLOC_BASE

0x000090DA       MOV R1 R2
0x000090DE       SHL R1 R1 12          ; page_index * 4096

0x000090E2       ADD R1 R1 R9

0x000090E6       RET

pa_fail:

0x000090EA       LI R1 0                     ; no free pages
0x000090F2       RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:

0x000090F6       LI R2 PAGE_ALLOC_BASE
0x000090FE       SUB R3 R1 R2         ; calculate offset from base

0x00009102       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x00009106       MOV R4 R3
0x0000910A       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x0000910E       MOV R5 R3
0x00009112       AND R5 R5 7          ; bit index in byte = page index % 8

0x00009116       LI R6 page_bitmap
0x0000911E       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x00009122       LDB R7 [R6]

0x00009126       LI R8 1
0x0000912E       SHL R8 R8 R5         ; mask for this page's bit

0x00009132       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00009136       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x0000913A       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000913E       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

0x00009142       LI R2 0

pz_loop:

0x0000914A       CMP R3 0
0x0000914E       BEQ pz_done

0x00009156       STB R2 [R1]

0x0000915A       ADD R1 R1 1
0x0000915E       SUB R3 R3 1

0x00009162       B pz_loop

pz_done:
0x0000916A       RET

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

0x00009532       PUSH LR

0x00009536       MOV R8 R1          ; entry
0x0000953A       MOV R9 R2          ; pid
0x0000953E       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x00009546       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x0000954E       CMP R1 0
0x00009552       BEQ task_create_fail

0x0000955A       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x0000955E       MOV R1 R10
0x00009562       LI R3 TASK_SIZE
0x0000956A       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x00009572   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x00009576   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x0000957A       BL page_alloc
0x00009582       CMP R1 0
0x00009586       BEQ task_create_fail

0x0000958E       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x00009592   STW R1 [R10 + TASK_PTBR]

0x00009596       MOV R1 R12
0x0000959A       LI  R3 PAGE_SIZE
0x000095A2       BL  mem_zero                   ; zero out the sensitive new page table

0x000095AA       MOV R1 R12
0x000095AE       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x000095B6   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x000095BA   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x000095BE   LDW R1 [R10 + TASK_PTBR]
0x000095C2       MOV R2 R8
0x000095C6       LI R3 0xFFFFF000
0x000095CE       AND R2 R2 R3
0x000095D2       MOV R3 R2
0x000095D6       CMP R9 0
0x000095DA       BEQ task_create_map_kernel_entry
0x000095E2       LI R4 USER_RX
0x000095EA       B task_create_map_entry
task_create_map_kernel_entry:
0x000095F2       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x000095FA       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x00009602       BL page_alloc
0x0000960A       CMP R1 0
0x0000960E       BEQ task_create_fail

0x00009616       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x0000961A   STW R12 [R10 + TASK_USTACK_PAGE]

0x0000961E       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x00009626   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x0000962A   LDW R1 [R10 + TASK_PTBR]

0x0000962E       LI  R2 USER_STACK_VA
0x00009636       MOV R3 R12
0x0000963A       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x00009642       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x0000964A       BL page_alloc
0x00009652       CMP R1 0
0x00009656       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x0000965E   STW R1 [R10 + TASK_KSTACK_PAGE]
0x00009662       LI R2 PAGE_SIZE

0x0000966A       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x0000966E       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x00009672   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00009676   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x0000967A       LI R1 0

0x00009682       PUSH R1            ; R1
0x00009686       PUSH R1            ; R2
0x0000968A       PUSH R1            ; R3
0x0000968E       PUSH R1            ; R4
0x00009692       PUSH R1            ; R5
0x00009696       PUSH R1            ; R6
0x0000969A       PUSH R1            ; R7
0x0000969E       PUSH R1            ; R8
0x000096A2       PUSH R1            ; R9
0x000096A6       PUSH R1            ; R10
0x000096AA       PUSH R1            ; R11
0x000096AE       PUSH R1            ; R12
0x000096B2       PUSH R1            ; R14 (FP)
0x000096B6       PUSH R1            ; R15 (LR)

0x000096BA       PUSH R11           ; R11 - user SP top

0x000096BE       MOV R1 R8
0x000096C2       PUSH R1            ; sepc = entry

0x000096C6       LI R1 0
0x000096CE       PUSH R1            ; sflags

0x000096D2       CMP R9 0
0x000096D6       BEQ task_create_kernel_status
0x000096DE       LI R1 0x20
0x000096E6       B task_create_status_ready
task_create_kernel_status:
0x000096EE       LI R1 0x120
task_create_status_ready:
0x000096F6       PUSH R1            ; sstatus

0x000096FA       LI R1 0
0x00009702       PUSH R1            ; scause
0x00009706       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x0000970A       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x0000970E   STW R1 [R10 + TASK_KSP]

0x00009712       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x00009716   LI R1 WAIT_NONE
0x0000971E   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x00009722   LI R1 RESUME_TRAP
0x0000972A   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x0000972E       BL page_alloc
0x00009736       CMP R1 0
0x0000973A       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x00009742       MOV R12 R1

0x00009746       LI  R3 PAGE_SIZE
0x0000974E       MOV R1 R12
0x00009752       BL  mem_zero

    ; stdin
0x0000975A       LI  R2 file_stdin
0x00009762       STW R2 [R12 + 0]

    ; stdout
0x00009766       LI  R2 file_stdout
0x0000976E       STW R2 [R12 + 4]

    ; stderr
0x00009772       LI  R2 file_stderr
0x0000977A       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x0000977E   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x00009782       BL page_alloc
0x0000978A       CMP R1 0
0x0000978E       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x00009796   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x0000979A       BL page_alloc
0x000097A2       CMP R1 0
0x000097A6       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x000097AE   STW R1 [R10 + TASK_KBUF_RD_PTR]

0x000097B2       BL page_alloc
0x000097BA       CMP R1 0
0x000097BE       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x000097C6   STW R1 [R10 + TASK_DATA_PAGE]

0x000097CA       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x000097CE   LDW R1 [R10 + TASK_PTBR]

0x000097D2       LI  R2 USER_DATA_VA
0x000097DA       MOV R3 R12
0x000097DE       LI  R4 USER_RW
0x000097E6       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x000097EE   LI R1 TASK_READY
0x000097F6   STW R1 [R10 + TASK_STATE]

    ; Initialize program break
0x000097FA       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x00009802   STW R1 [R10 + TASK_BREAK]

0x00009806       MOV R1 R10                              ; return created task pointer

0x0000980A       POP LR
0x0000980E       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x00009812       CMP R10 0
0x00009816       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x0000981E   LDW R1 [R10 + TASK_PTBR]
0x00009822       CMP R1 0
0x00009826       BEQ task_create_free_ustack
0x0000982E       BL page_free

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00009836   LDW R1 [R10 + TASK_USTACK_PAGE]
0x0000983A       CMP R1 0
0x0000983E       BEQ task_create_free_kstack
0x00009846       BL page_free

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x0000984E   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x00009852       CMP R1 0
0x00009856       BEQ task_create_free_fd
0x0000985E       BL page_free

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00009866   LDW R1 [R10 + TASK_FD_TABLE]
0x0000986A       CMP R1 0
0x0000986E       BEQ task_create_free_kwr
0x00009876       BL page_free

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x0000987E   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x00009882       CMP R1 0
0x00009886       BEQ task_create_free_krd
0x0000988E       BL page_free

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x00009896   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000989A       CMP R1 0
0x0000989E       BEQ task_create_free_data
0x000098A6       BL page_free

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x000098AE   LDW R1 [R10 + TASK_DATA_PAGE]
0x000098B2       CMP R1 0
0x000098B6       BEQ task_create_clear_slot
0x000098BE       BL page_free

task_create_clear_slot:
0x000098C6       MOV R1 R10
0x000098CA       LI R3 TASK_SIZE
0x000098D2       BL mem_zero

task_create_fail_return:
0x000098DA       LI R1 0

0x000098E2       POP LR
0x000098E6       RET

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

0x000098EA       PUSH LR
0x000098EE       push R12 ; preserve R12 which we use for temporary storage in this function
0x000098F2       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x000098F6   LDW R2 [R1 + TASK_PTBR]
0x000098FA       CMP R2 0
0x000098FE       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x00009906       MOV R1 R2
0x0000990A       BL page_free        ; free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x00009912   LDW R2 [R12 + TASK_USTACK_PAGE]
0x00009916       CMP R2 0
0x0000991A       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00009922       MOV R1 R2
0x00009926       BL page_free

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x0000992E   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x00009932       CMP R2 0
0x00009936       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000993E       MOV R1 R2
0x00009942       BL page_free

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x0000994A   LDW R2 [R12 + TASK_FD_TABLE]
0x0000994E       CMP R2 0
0x00009952       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000995A       MOV R1 R2
0x0000995E       BL page_free

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x00009966   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x0000996A       CMP R2 0
0x0000996E       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x00009976       MOV R1 R2
0x0000997A       BL page_free

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x00009982   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x00009986       CMP R2 0
0x0000998A       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x00009992       MOV R1 R2
0x00009996       BL page_free

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x0000999E   LDW R2 [R12 + TASK_DATA_PAGE]
0x000099A2       CMP R2 0
0x000099A6       BEQ td_done     ; if task has no user data page, it also has no user buffers to free, so skip freeing user buffers and move to clearing slot and returning
0x000099AE       MOV R1 R2
0x000099B2       BL page_free

td_done:

0x000099BA       MOV R1 R12
0x000099BE       LI  R3 TASK_SIZE
0x000099C6       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x000099CE       POP R12         ; restore R12
0x000099D2       POP LR
0x000099D6       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x000099DA       PUSH LR
0x000099DE       PUSH R8
0x000099E2       PUSH R9
0x000099E6       PUSH R10
0x000099EA       PUSH R11
0x000099EE       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x000099F2   LDW R4 [R1 + TASK_FD_TABLE]
0x000099F6       MOV R12 R4

0x000099FA       LI R5 3              ; skip stdin/out/err
0x00009A02       MOV R11 R5

fd_loop:

0x00009A06       CMP R11 MAX_FDS
0x00009A0A       BGE fd_done         ; if we processed all fd slots, we are done

0x00009A12       SHL R6 R11 2
0x00009A16       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x00009A1A       LDW R8 [R10]
0x00009A1E       CMP R8 0
0x00009A22       BEQ fd_next         ; if fd slot is empty, skip to next

0x00009A2A       MOV R1 R8
0x00009A2E       BL file_free
0x00009A36       LI R9 0
0x00009A3E       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x00009A42       ADD R11 R11 1
0x00009A46       B fd_loop

fd_done:
0x00009A4E       POP R12
0x00009A52       POP R11
0x00009A56       POP R10
0x00009A5A       POP R9
0x00009A5E       POP R8
0x00009A62       POP LR
0x00009A66       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x00009A6A       PUSH LR
0x00009A6E       PUSH R8
0x00009A72       PUSH R9
0x00009A76       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x00009A7A   LI R1 CURRENT_TASK
0x00009A82   LDW R10 [R1]
0x00009A86       LI R8 0

task_reap_loop:
0x00009A8E       CMP R8 MAX_TASKS
0x00009A92       BGE task_reap_done

0x00009A9A       CMP R8 R10
0x00009A9E       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x00009AA6   LI R1 TASK_SIZE
0x00009AAE   MUL R3 R8 R1
0x00009AB2   LI R9 tasks
0x00009ABA   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x00009ABE   LDW R1 [R9 + TASK_STATE]
0x00009AC2       CMP R1 TASK_ZOMBIE
0x00009AC6       BNE task_reap_next

0x00009ACE       PUSH R8
0x00009AD2       MOV R1 R9
0x00009AD6       BL task_destroy
0x00009ADE       POP R8

task_reap_next:
0x00009AE2       ADD R8 R8 1
0x00009AE6       B task_reap_loop

task_reap_done:
0x00009AEE       POP R10
0x00009AF2       POP R9
0x00009AF6       POP R8
0x00009AFA       POP LR
0x00009AFE       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x00009B02       LI R1 tasks
0x00009B0A       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x00009B12   LDW R3 [R1 + TASK_STATE]

0x00009B16       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x00009B1A       BEQ task_alloc_found

0x00009B22       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x00009B26       SUB R2 R2 1
0x00009B2A       BNE task_alloc_loop

; no free tasks slots

0x00009B32       LI R1 0
0x00009B3A       RET

task_alloc_found:                           ;R1 points to free task slot

0x00009B3E       RET

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
; USER mode TASKS
; ================================================================


; --TASK 1----------------------------------------------
.ORG 0x19000
TASK_A_START:
0x00019000       li R1 10
write_loop1:
0x00019008       push R1
    ;DEBUG 2
    ; Prepare a write string in user memory.
0x0001900C       LI R1 USER_WRITE_BUF
0x00019014       LI R2 0x6C6C6548         ; "Hell"
0x0001901C       STW R2 [R1]
0x00019020       LI R2 0x57202C6F         ; "o, W"
0x00019028       STW R2 [R1 + 4]
0x0001902C       LI R2 0x646C726F         ; "orld"
0x00019034       STW R2 [R1 + 8]
0x00019038       LI R2 0x21
0x00019040       STB R2 [R1 + 12]
0x00019044       LI R2 0x0A
0x0001904C       STB R2 [R1 + 13]

0x00019050       LI R1 1                 ;fd
   ; DEBUG 1
0x00019058       LI R2 USER_WRITE_BUF    ; user buff
0x00019060       LI R3 14                ; len
0x00019068       SVC SYS_WRITE
0x0001906C       DEBUG 1
0x00019070       pop R1
0x00019074       sub R1 R1 1
0x00019078       cmp r1 0
0x0001907C       BNE write_loop1
    ; Exit after the write test.
0x00019084       LI R1 SYS_EXIT
0x0001908C       SVC SYS_EXIT

; ---TASK 2---------------------------------------------


.org 0x1a000
TASK_B_START:

    ; Read the built-in TARFS message through open/read/close.
0x0001A000       LI R1 task_b_motd_path
0x0001A008       LI R2 FD_FLAG_READ
0x0001A010       SVC SYS_OPEN
0x0001A014       MOV R8 R1
0x0001A018       CMP R8 0
0x0001A01C       BLT task_b_open_fail

0x0001A024       MOV R1 R8
0x0001A028       LI R2 USER_READ_BUF
0x0001A030       LI R3 32
0x0001A038       SVC SYS_READ
0x0001A03C       MOV R9 R1

0x0001A040       LI R1 STDOUT_FD
0x0001A048       LI R2 USER_READ_BUF
0x0001A050       MOV R3 R9
0x0001A054       SVC SYS_WRITE

0x0001A058       MOV R1 R8
0x0001A05C       SVC SYS_CLOSE

task_b_loop:

    ;=========================================
    ; fd = open("/dev/console", WRITE)
    ;=========================================

0x0001A060       LI R1 task_b_console_path
0x0001A068       LI R2 FD_FLAG_WRITE
0x0001A070       SVC SYS_OPEN
    ;DEBUG 1
0x0001A074       MOV R8 R1                  ; save fd

    ; open failed?
0x0001A078       CMP R8 0
0x0001A07C       BLT task_b_open_fail

    ;=========================================
    ; write(fd, msg, len)
    ;=========================================

0x0001A084       MOV R1 R8
0x0001A088       LI R2 task_b_msg
0x0001A090       LI R3 27
0x0001A098       SVC SYS_WRITE
    ;DEBUG 2

    ;=========================================
    ; close(fd)
    ;=========================================

0x0001A09C       MOV R1 R8
0x0001A0A0       SVC SYS_CLOSE

    ; Block until console input is available, then echo exactly the number
    ; of bytes returned by read(). The UART driver stops at newline or after
    ; CONSOLE_INPUT_LEN bytes.
0x0001A0A4       LI R1 STDIN_FD
0x0001A0AC       LI R2 USER_READ_BUF
0x0001A0B4       LI R3 5
0x0001A0BC       SVC SYS_READ
  ;  DEBUG  2
0x0001A0C0       CMP R1 0
0x0001A0C4       BLE task_b_yield

0x0001A0CC       MOV R5 R1
0x0001A0D0       LI R1 STDOUT_FD
0x0001A0D8       LI R2 USER_READ_BUF
0x0001A0E0       MOV R3 R5
0x0001A0E4       SVC SYS_WRITE

task_b_yield:
0x0001A0E8       SVC SYS_YIELD
0x0001A0EC       B task_b_yield

task_b_open_fail:

0x0001A0F4       LI R1 1
0x0001A0FC       LI R2 open_fail_msg
0x0001A104       LI R3 11
0x0001A10C       SVC SYS_WRITE

0x0001A110       SVC SYS_YIELD

0x0001A114       B task_b_loop

; task2 date page
.org 0x1A100
task_b_console_path:
    .ASCIIZ "/dev/console"

task_b_motd_path:
    .ASCIIZ "/etc/motd"

task_b_msg:
    .ASCIIZ "OPEN WRITE CLOSE\r\n input:> "

task_b_msg_len:
    .WORD 18

open_fail_msg:
    .ASCIIZ "OPEN FAIL\r\n"

open_fail_msg_len:
    .WORD 11


; Test program for gettime and brk
.org 0x1B000
TASK_C_START:

    ; ====================================
    ; Test gettimeofday
    ; ====================================

0x0001B000       LI R1 timeval_buffer
0x0001B008       SVC SYS_GETTIME

    ; Print seconds
0x0001B00C       LI R1 STDOUT_FD
0x0001B014       LI R2 time_msg
0x0001B01C       LI R3 12
0x0001B024       SVC SYS_WRITE

    ; Print seconds value (convert to ASCII - simplified)
    ; For now just print the value in hex via debug
0x0001B028       LI R1 timeval_buffer
0x0001B030       LDW R2 [R1 + TIMEVAL_SEC]
0x0001B034       DEBUG 2                    ; R2 will be printed by debug

    ; ====================================
    ; Test brk
    ; ====================================

    ; Get current break
0x0001B038       LI R1 0
0x0001B040       SVC SYS_SBRK

    ; Print old break
0x0001B044       DEBUG 1

    ; Allocate 256 bytes
0x0001B048       LI R1 256
0x0001B050       SVC SYS_SBRK

    ; Print new break
0x0001B054       DEBUG 1

    ; ====================================
    ; Loop forever
    ; ====================================

task_c_loop:
0x0001B058       SVC SYS_YIELD
0x0001B05C       B task_c_loop

time_msg:
    .ASCIIZ "Time: seconds="

timeval_buffer:
    .WORD 0
    .WORD 0

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
[ASM] Built memory.img (658944 bytes)
