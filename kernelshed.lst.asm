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
.EQU FD_FLAG_READ,    1
.EQU FD_FLAG_WRITE,   2

.EQU FILE_OPS,      0
.EQU FILE_PRIVATE,  4
.EQU FILE_OFFSET,   8
.EQU FILE_FLAGS,    12
.EQU FILE_SIZE,     16

.EQU FOPS_READ,     0
.EQU FOPS_WRITE,    4
.EQU FOPS_SIZE,     8

.EQU UARTDEV_RX_QUEUE, 0
.EQU UARTDEV_TX_QUEUE, 4
.EQU UARTDEV_MMIO,     8
.EQU UARTDEV_SIZE,     12

.EQU STDIN_FD,       0
.EQU STDOUT_FD,      1
.EQU STDERR_FD,      2
.EQU CONSOLE_INPUT_LEN, 5



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

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
0x0000205C           LI R1 tasks
0x00002064           LDW R2 [R1 + TASK_PTBR]
0x00002068           SETPTBR R2
0x0000206C           LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
0x00002070   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore
0x00002078           B trap_restore

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x00002080       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x00002088       LI R2 trap_entry
0x00002090       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x00002094       LI R2 trap_entry
0x0000209C       STW R2 [R1+4]                ; IDT[1]
0x000020A0       STW R2 [R1+8]                ; IDT[2]
0x000020A4       STW R2 [R1+12]               ; IDT[3]
0x000020A8       STW R2 [R1+24]               ; IDT[6]
0x000020AC       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x000020B0       SETIDTR R1
0x000020B4       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
0x000020B8       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x000020BC       LI R1 page_bitmap
0x000020C4       LI R3 16
0x000020CC       BL mem_zero

0x000020D4       POP LR
0x000020D8       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x000020DC       PUSH LR
0x000020E0       PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
0x000020E4       LI R2 0x00000000      ;page 0 - boot (0000)
0x000020EC       LI R3 0x00000000
0x000020F4       LI R4 KERNEL_FLAGS
0x000020FC       bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x00002104       LI R2 0x00001000      ; page for kernel buffers
0x0000210C       LI R3 0x00001000
0x00002114       LI R4 KERNEL_FLAGS
0x0000211C       BL map_page

0x00002124       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x0000212C       LI R3 0x00002000
0x00002134       LI R4 KERNEL_FLAGS
0x0000213C       BL map_page

0x00002144       LI R2 0x00003000
0x0000214C       LI R3 0x00003000
0x00002154       LI R4 KERNEL_FLAGS
0x0000215C       BL map_page

0x00002164       LI R2 0x00004000
0x0000216C       LI R3 0x00004000
0x00002174       LI R4 KERNEL_FLAGS
0x0000217C       BL map_page

0x00002184       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x0000218C       LI R3 0x00007000
0x00002194       LI R4 KERNEL_FLAGS
0x0000219C       BL map_page

0x000021A4       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x000021AC       LI R3 0x00008000
0x000021B4       LI R4 KERNEL_FLAGS
0x000021BC       BL map_page


    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x000021C4       LI R2 0x00100000      ; UART physical and virtual base
0x000021CC       LI R3 0x00100000
0x000021D4       LI R4 KERNEL_FLAGS
0x000021DC       BL map_page

0x000021E4       LI R2 0x00101000      ; PIT physical and virtual base
0x000021EC       LI R3 0x00101000
0x000021F4       LI R4 KERNEL_FLAGS
0x000021FC       BL map_page

0x00002204       LI R2 0x00102000      ; PIC physical and virtual base
0x0000220C       LI R3 0x00102000
0x00002214       LI R4 KERNEL_FLAGS
0x0000221C       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x00002224       LI R12 PAGE_ALLOC_BASE
0x0000222C       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x00002234       CMP R12 R7
0x00002238       BGE map_common_dynamic_done
0x00002240       MOV R2 R12
0x00002244       MOV R3 R12
0x00002248       LI R4 KERNEL_FLAGS
0x00002250       BL map_page
0x00002258       LI R6 PAGE_SIZE
0x00002260       ADD R12 R12 R6
0x00002264       B map_common_dynamic_loop
map_common_dynamic_done:

0x0000226C       POP R12
0x00002270       POP LR
0x00002274       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002278       SHR R5 R2 12               ; VPN
0x0000227C       SHL R5 R5 2                ; page-table byte offset
0x00002280       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002284       STW R6 [R1 + R5]
0x00002288       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x0000228C       LI R1 0x00102000
0x00002294       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x0000229C       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x000022A0       LI R1 0x00101000
0x000022A8       LI R2 2000
0x000022B0       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x000022B4       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000022BC       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x000022C0       LI R1 0x00100000
0x000022C8       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000022D0       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x000022D4       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000022D8       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000022DC       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000022E0       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000022E4       PUSH R1
0x000022E8       PUSH R2
0x000022EC       PUSH R3
0x000022F0       PUSH R4
0x000022F4       PUSH R5
0x000022F8       PUSH R6
0x000022FC       PUSH R7
0x00002300       PUSH R8
0x00002304       PUSH R9
0x00002308       PUSH R10
0x0000230C       PUSH R11
0x00002310       PUSH R12
0x00002314       PUSH R14
0x00002318       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x0000231C       CSRR R1 SSCRATCH
0x00002320       PUSH R1
0x00002324       CSRR R1 SEPC
0x00002328       PUSH R1
0x0000232C       CSRR R1 SFLAGS
0x00002330       PUSH R1
0x00002334       CSRR R1 SSTATUS
0x00002338       PUSH R1
0x0000233C       CSRR R1 SCAUSE
0x00002340       PUSH R1
0x00002344       CSRR R1 STVAL
0x00002348       PUSH R1

    ; Dispatch based on scause.
0x0000234C       CSRR R1 SCAUSE
0x00002350       CMP R1 0
0x00002354       BEQ handle_divide_zero

0x0000235C       CMP R1 1
0x00002360       BEQ handle_invalid_instr

0x00002368       CMP R1 2
0x0000236C       BEQ handle_page_fault

0x00002374       CMP R1 3
0x00002378       BEQ handle_syscall

0x00002380       CMP R1 6
0x00002384       BEQ handle_debug

0x0000238C       CMP R1 16
0x00002390       BEQ handle_irq

    ; Unknown cause - halt
0x00002398       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x0000239C       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x000023A4       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x000023AC       HLT

0x000023B0       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x000023B8       CSRR R2 STVAL

0x000023BC       CMP R2 SYS_COUNT
0x000023C0       BGE syscall_unknown

0x000023C8       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000023D0       SHL R4 R2 2
0x000023D4       LDW R5 [R3 + R4]
0x000023D8       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000023DC       LI R1 ERR_NOSYS
0x000023E4       STW R1 [SP + TF_R1]
0x000023E8       B trap_restore

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

0x00002414       LI R1 0
0x0000241C       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00002420       B schedule_and_switch

syscall_exit:
    ;================================================================
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002428   LI R1 CURRENT_TASK
0x00002430   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002434   LI R1 TASK_SIZE
0x0000243C   MUL R3 R2 R1
0x00002440   LI R5 tasks
0x00002448   ADD R5 R5 R3

0x0000244C       PUSH R5
0x00002450       MOV R1 R5
0x00002454       BL task_close_fds      ; close all open file descriptors of this task (if any) to free file_pool resources
0x0000245C       POP R5

    ; Do not destroy the current task here: SP still points into its kernel
    ; stack. Mark it unrecoverable and let idle_task reclaim it later while
    ; running on a different stack.
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x00002460   LI R1 TASK_ZOMBIE
0x00002468   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000246C   LI R1 WAIT_NONE
0x00002474   STW R1 [R5 + TASK_WAIT]
0x00002478       B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002480   LI R1 CURRENT_TASK
0x00002488   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x0000248C   LI R1 TASK_SIZE
0x00002494   MUL R3 R2 R1
0x00002498   LI R5 tasks
0x000024A0   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x000024A4   LDW R1 [R5 + TASK_PID]

0x000024A8       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x000024AC       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x000024B4       LDW R1 [SP + TF_R1]
0x000024B8       STW R1 [SP + TF_R1]

0x000024BC       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x000024C4       LDW R1 [SP + TF_R1]
0x000024C8       LDW R2 [SP + TF_R2]

0x000024CC       MOV R12 R2               ; save flags

0x000024D0       BL copy_path_from_user      ; macro inside destroys R11
0x000024D8       CMP R1 0
0x000024DC       BEQ open_fail_fault

0x000024E4       BL lookup_device
0x000024EC       CMP R1 0
0x000024F0       BEQ open_try_tarfs

0x000024F8       MOV R8 R1            ; save device descriptor

0x000024FC       BL file_alloc        ; out: R1 = pointer to FILE object in file_pool
0x00002504       CMP R1 0
0x00002508       BEQ open_fail_nfile
0x00002510       MOV R9 R1            ;

    ; initialize file object
0x00002514       MOV R1 R9                ; file*
0x00002518       MOV R2 R8                ; device*
0x0000251C       MOV R3 R12               ; flags
0x00002520       BL file_init             ; ([i].device*)->([i].file*), [i].seek=0, set [i].flags in file_pool

0x00002528       MOV R1 R9                ; initialised file ptr (ie file instance)
0x0000252C       BL fd_alloc              ; fd_table[new_fd] = file* (new_fd - idx in fd_table 4,5,6...)
0x00002534       LI  R2 ERR_MFILE
0x0000253C       CMP R1 R2
0x00002540       BEQ open_fail_fd

0x00002548       STW R1 [SP + TF_R1]

0x0000254C       B trap_restore

open_try_tarfs:
    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00002554   LI R1 CURRENT_TASK
0x0000255C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002560   LI R1 TASK_SIZE
0x00002568   MUL R3 R4 R1
0x0000256C   LI R5 tasks
0x00002574   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00002578   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x0000257C       BL tarfs_lookup
0x00002584       CMP R1 0
0x00002588       BEQ open_fail_noent

    ; TARFS is read-only and directories cannot be opened as byte streams.
0x00002590       MOV R8 R1
0x00002594       AND R2 R12 FD_FLAG_WRITE
0x00002598       CMP R2 0
0x0000259C       BNE open_fail_acces

0x000025A4       LDW R2 [R8 + TAR_IDX_TYPE]
0x000025A8       LI R3 53                         ; ASCII '5' = directory
0x000025B0       CMP R2 R3
0x000025B4       BEQ open_fail_isdir

0x000025BC       BL file_alloc
0x000025C4       CMP R1 0
0x000025C8       BEQ open_fail_nfile
0x000025D0       MOV R9 R1

0x000025D4       LI R2 tarfs_ops
0x000025DC       STW R2 [R9 + FILE_OPS]
0x000025E0       STW R8 [R9 + FILE_PRIVATE]
0x000025E4       LI R2 0
0x000025EC       STW R2 [R9 + FILE_OFFSET]
0x000025F0       LI R2 FD_FLAG_READ
0x000025F8       STW R2 [R9 + FILE_FLAGS]

0x000025FC       MOV R1 R9
0x00002600       BL fd_alloc
0x00002608       LI R2 ERR_MFILE
0x00002610       CMP R1 R2
0x00002614       BEQ open_fail_fd

0x0000261C       STW R1 [SP + TF_R1]
0x00002620       B trap_restore

open_fail_acces:
0x00002628       LI R1 ERR_ACCES
0x00002630       STW R1 [SP + TF_R1]
0x00002634       B trap_restore

open_fail_isdir:
0x0000263C       LI R1 ERR_ISDIR
0x00002644       STW R1 [SP + TF_R1]
0x00002648       B trap_restore

open_fail_fd:
0x00002650       MOV R1 R9
0x00002654       BL file_free
0x0000265C       LI R1 ERR_MFILE
0x00002664       STW R1 [SP + TF_R1]

0x00002668       B trap_restore

open_fail_nfile:
0x00002670       LI R1 ERR_NFILE
0x00002678       STW R1 [SP + TF_R1]

0x0000267C       B trap_restore

open_fail_noent:
0x00002684       LI R1 ERR_NOENT
0x0000268C       STW R1 [SP + TF_R1]

0x00002690       B trap_restore

open_fail_fault:
0x00002698       LI R1 ERR_FAULT
0x000026A0       STW R1 [SP + TF_R1]

0x000026A4       B trap_restore
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
0x000026AC       PUSH LR

0x000026B0       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x000026B4   LI R1 CURRENT_TASK
0x000026BC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000026C0   LI R1 TASK_SIZE
0x000026C8   MUL R3 R4 R1
0x000026CC   LI R5 tasks
0x000026D4   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x000026D8   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x000026DC       PUSH R9                    ; original destination returned on success
0x000026E0       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x000026E8       LI R11 KBUFFER_SIZE
0x000026F0       CMP R10 R11
0x000026F4       BGE copy_path_fail

0x000026FC       PUSH R8
0x00002700       PUSH R9
0x00002704       PUSH R10
0x00002708       MOV R1 R8
0x0000270C       LI R2 1
0x00002714       LI R3 0                    ; read access from user source
0x0000271C       BL user_buffer_valid_range
0x00002724       POP R10
0x00002728       POP R9
0x0000272C       POP R8
0x00002730       CMP R1 1
0x00002734       BNE copy_path_fail

0x0000273C       LDB R4 [R8]
0x00002740       STB R4 [R9]
0x00002744       CMP R4 0
0x00002748       BEQ copy_path_done

0x00002750       ADD R8 R8 1
0x00002754       ADD R9 R9 1
0x00002758       ADD R10 R10 1
0x0000275C       B copy_path_loop

copy_path_done:
0x00002764       POP R1                     ; original kernel path pointer
0x00002768       POP LR
0x0000276C       RET

copy_path_fail:
0x00002770       POP R1                     ; discard original kernel path pointer
0x00002774       LI R1 0
0x0000277C       POP LR
0x00002780       RET

;====================================================================
; lookup_device in device_table
;
;input:
; R1 = user pointer to string
;output:
; R1 = device descriptor
 ;R1 = 0 if not found
;====================================================================
lookup_device:

0x00002784       PUSH LR

0x00002788       MOV R8 R1                  ; save pathname ptr

0x0000278C       LI R7 device_table
0x00002794       LI R9 DEVICE_COUNT

lookup_loop:
0x0000279C       CMP R9 0
0x000027A0       BEQ lookup_fail

    ; compare pathname with device name

0x000027A8       MOV R1 R8
0x000027AC       LDW R2 [R7 + DEV_NAME]

0x000027B0       BL strcmp

0x000027B8       CMP R1 1
0x000027BC       BEQ lookup_found

0x000027C4       ADD R7 R7 DEV_SIZE
0x000027C8       SUB R9 R9 1
0x000027CC       B lookup_loop

lookup_found:

0x000027D4       MOV R1 R7                  ; return device descriptor ptr

0x000027D8       POP LR
0x000027DC       RET

lookup_fail:

0x000027E0       LI R1 0

0x000027E8       POP LR
0x000027EC       RET

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
0x000027F0       LDB R3 [R1]
0x000027F4       LDB R4 [R2]

0x000027F8       CMP R3 R4
0x000027FC       BNE str_not_equal

0x00002804       CMP R3 0
0x00002808       BEQ str_equal

0x00002810       ADD R1 R1 1
0x00002814       ADD R2 R2 1
0x00002818       B str_loop

str_equal:
0x00002820       LI R1 1
0x00002828       RET

str_not_equal:
0x0000282C       LI R1 0
0x00002834       RET

;====================================================================
; file_init
; in: R1 = file pointer
      ;R2 = device descriptor pointer in file_pool
      ;R3 = open flags
; out:file structure initialized
;====================================================================
file_init:

0x00002838       LDW R4 [R2 + DEV_OPS]
0x0000283C       STW R4 [R1 + FILE_OPS]

0x00002840       LDW R4 [R2 + DEV_PRIVATE]
0x00002844       STW R4 [R1 + FILE_PRIVATE]

0x00002848       LI R4 0
0x00002850       STW R4 [R1 + FILE_OFFSET]

0x00002854       STW R3 [R1 + FILE_FLAGS]

0x00002858       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x0000285C       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x00002860   LI R1 CURRENT_TASK
0x00002868   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x0000286C   LI R1 TASK_SIZE
0x00002874   MUL R3 R4 R1
0x00002878   LI R4 tasks
0x00002880   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00002884   LDW R4 [R4 + TASK_FD_TABLE]

0x00002888       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00002890       CMP R5 MAX_FDS
0x00002894       BGE fd_alloc_fail

0x0000289C       SHL R6 R5 2                ; fd * 4
0x000028A0       ADD R7 R4 R6               ; &fd_table[fd]

0x000028A4       LDW R2 [R7]
0x000028A8       CMP R2 0                   ; 0 - empty
0x000028AC       BEQ fd_alloc_found

0x000028B4       ADD R5 R5 1
0x000028B8       B fd_alloc_loop

fd_alloc_found:

0x000028C0       STW R8 [R7]                ; fd_table[fd] = file*

0x000028C4       MOV R1 R5                  ; return fd
0x000028C8       RET

fd_alloc_fail:

0x000028CC       LI R1 ERR_MFILE
0x000028D4       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x000028D8       LDW R1 [SP + TF_R1]

0x000028DC       BL fd_remove    ;in R1-fd out R1-file ptr for this fd

0x000028E4       CMP R1 0
0x000028E8       BEQ close_fail

0x000028F0       BL file_free    ;in R1 file_ptr in file_pool it marks it as free (NULL)

0x000028F8       LI R1 0
0x00002900       STW R1 [SP + TF_R1]

0x00002904       B trap_restore

close_fail:
0x0000290C       LI R1 ERR_BADF
0x00002914       STW R1 [SP + TF_R1]

0x00002918       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00002920       LDW R7 [SP + TF_R1]

0x00002924       BL pipe_alloc
0x0000292C       CMP R1 0
0x00002930       BEQ pipe_fail_nospc

0x00002938       MOV R8 R1            ; new slot in pipe_pool ( pipe* )

    ; [0] read end          write[1]>--pipe--->read[0]

0x0000293C       BL file_alloc
0x00002944       CMP R1 0
0x00002948       BEQ pipe_fail_pipe_only

0x00002950       MOV R9 R1           ; new file for read end  in file_pool

0x00002954       LI R2 pipe_ops
0x0000295C       STW R2 [R9 + FILE_OPS]      ; store ops (for pipe of read end) in allocated  file struc

0x00002960       STW R8 [R9 + FILE_PRIVATE]  ; store our slot pipe* in file

0x00002964       LI R2 FD_FLAG_READ
0x0000296C       STW R2 [R9 + FILE_FLAGS]    ; set file mode read

0x00002970       MOV R1 R9
0x00002974       BL fd_alloc                 ; insert read file to fd_table of user process

0x0000297C       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002984       CMP R1 R2
0x00002988       BEQ pipe_fail_read_file

0x00002990       MOV R10 R1           ; get file read fd created to R10

    ; write end

0x00002994       BL file_alloc
0x0000299C       CMP R1 0
0x000029A0       BEQ pipe_fail_read_fd

0x000029A8       MOV R9 R1

0x000029AC       LI R2 pipe_ops
0x000029B4       STW R2 [R9 + FILE_OPS]

0x000029B8       STW R8 [R9 + FILE_PRIVATE]

0x000029BC       LI R2 FD_FLAG_WRITE                 ;file mode -write
0x000029C4       STW R2 [R9 + FILE_FLAGS]

0x000029C8       MOV R1 R9
0x000029CC       BL fd_alloc

0x000029D4       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x000029DC       CMP R1 R2
0x000029E0       BEQ pipe_fail_write_file

0x000029E8       MOV R11 R1           ; R11 write fd R10 read fd

0x000029EC       MOV R1 R7   ; in &fd[2]
0x000029F0       LI R2 8     ; len 2
0x000029F8       LI R3 1     ; mem perm to write cond
0x00002A00       BL user_buffer_valid_range
0x00002A08       CMP R1 1
0x00002A0C       BNE pipe_fail_both_fds

0x00002A14       STW R10 [R7]    ;fd[0]-rd fd[1]-wr
0x00002A18       STW R11 [R7 + 4]

0x00002A1C       LI R1 0
0x00002A24       STW R1 [SP + TF_R1]

0x00002A28       B trap_restore

pipe_fail:
0x00002A30       LI R1 ERR_IO
0x00002A38       STW R1 [SP + TF_R1]

0x00002A3C       B trap_restore

pipe_fail_both_fds:
0x00002A44       MOV R12 R8
0x00002A48       MOV R1 R11
0x00002A4C       BL fd_remove
0x00002A54       CMP R1 0
0x00002A58       BEQ pipe_fail_both_fds_read
0x00002A60       BL file_free

pipe_fail_both_fds_read:
0x00002A68       MOV R1 R10
0x00002A6C       BL fd_remove
0x00002A74       CMP R1 0
0x00002A78       BEQ pipe_fail_free_pipe_fault
0x00002A80       BL file_free

pipe_fail_free_pipe_fault:
0x00002A88       MOV R1 R12
0x00002A8C       BL pipe_free
0x00002A94       LI R1 ERR_FAULT
0x00002A9C       STW R1 [SP + TF_R1]

0x00002AA0       B trap_restore

pipe_fail_write_file:
0x00002AA8       MOV R12 R8
0x00002AAC       MOV R1 R9
0x00002AB0       BL file_free
0x00002AB8       MOV R1 R10
0x00002ABC       BL fd_remove
0x00002AC4       CMP R1 0
0x00002AC8       BEQ pipe_fail_free_pipe_mfile
0x00002AD0       BL file_free

pipe_fail_free_pipe_mfile:
0x00002AD8       MOV R1 R12
0x00002ADC       BL pipe_free
0x00002AE4       LI R1 ERR_MFILE
0x00002AEC       STW R1 [SP + TF_R1]

0x00002AF0       B trap_restore

pipe_fail_read_fd:
0x00002AF8       MOV R12 R8
0x00002AFC       MOV R1 R10
0x00002B00       BL fd_remove
0x00002B08       CMP R1 0
0x00002B0C       BEQ pipe_fail_free_pipe_nfile
0x00002B14       BL file_free

pipe_fail_free_pipe_nfile:
0x00002B1C       MOV R1 R12
0x00002B20       BL pipe_free
0x00002B28       LI R1 ERR_NFILE
0x00002B30       STW R1 [SP + TF_R1]

0x00002B34       B trap_restore

pipe_fail_read_file:
0x00002B3C       MOV R12 R8
0x00002B40       MOV R1 R9
0x00002B44       BL file_free
0x00002B4C       MOV R1 R12
0x00002B50       BL pipe_free
0x00002B58       LI R1 ERR_MFILE
0x00002B60       STW R1 [SP + TF_R1]

0x00002B64       B trap_restore

pipe_fail_pipe_only:
0x00002B6C       MOV R1 R8
0x00002B70       BL pipe_free
0x00002B78       LI R1 ERR_NFILE
0x00002B80       STW R1 [SP + TF_R1]

0x00002B84       B trap_restore

pipe_fail_nospc:
0x00002B8C       LI R1 ERR_NOSPC
0x00002B94       STW R1 [SP + TF_R1]

0x00002B98       B trap_restore

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

0x00002BA0       PUSH LR

0x00002BA4       MOV R9 R1              ; file*
0x00002BA8       MOV R7 R2              ; user buffer
0x00002BAC       MOV R6 R3              ; requested len
0x00002BB0       LDW R9 [R9 + FILE_PRIVATE]    ; our instance allocated in pipe_pool pipe*
0x00002BB4       CMP R6 0                ;fast clear from it if len=0
0x00002BB8       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00002BC0       PUSH R7
0x00002BC4       PUSH R6

0x00002BC8       MOV R1 R7
0x00002BCC       MOV R2 R6
0x00002BD0       LI  R3 1               ; write access
0x00002BD8       BL user_buffer_valid_range

0x00002BE0       POP R6
0x00002BE4       POP R7
0x00002BE8       CMP R1 1
0x00002BEC       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00002BF4       LDW R4 [R9 + PIPE_COUNT]
0x00002BF8       CMP R4 0
0x00002BFC       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00002C04       CMP R6 R4
0x00002C08       BLT pipe_user_len

0x00002C10       MOV R5 R4
0x00002C14       B pipe_have_amount

pipe_user_len:
0x00002C1C       MOV R5 R6

pipe_have_amount:
0x00002C20       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00002C28       CMP R10 R5
0x00002C2C       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00002C34       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00002C38       MOV R12 R9
0x00002C3C       ADD R12 R12 PIPE_BUFFER
0x00002C40       ADD R12 R12 R11         ; addr += tail

0x00002C44       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00002C48       MOV R12 R7
0x00002C4C       ADD R12 R12 R10

0x00002C50       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x00002C54       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00002C58       LI R2 255
0x00002C60       AND R11 R11 R2
0x00002C64       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00002C68       LDW R12 [R9 + PIPE_COUNT]
0x00002C6C       SUB R12 R12 1
0x00002C70       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00002C74       ADD R10 R10 1
0x00002C78       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00002C80       MOV R1 R9
0x00002C84       ADD R1 R1 PIPE_WWAIT
0x00002C88       BL waitq_wake_all
0x00002C90       MOV R1 R10          ; read bytes amount
0x00002C94       POP LR
0x00002C98       RET

pipe_read_badptr:
0x00002C9C       LI R1 ERR_FAULT
0x00002CA4       POP LR
0x00002CA8       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00002CAC       MOV R1 R9
0x00002CB0       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00002CB4       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00002CBC       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00002CC4       LDW R4 [R9 + PIPE_COUNT]
0x00002CC8       CMP R4 0
0x00002CCC       BNE pipe_read_retry

0x00002CD4       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00002CDC       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00002CE4       LI R2 0

pipe_loop:
0x00002CEC       LI  R1 MAX_PIPES
0x00002CF4       CMP R2 R1
0x00002CF8       BGE pipe_alloc_fail

0x00002D00       SHL R3 R2 2

0x00002D04       LI R4 pipe_used
0x00002D0C       ADD R4 R4 R3

0x00002D10       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00002D14       CMP R5 0                ; 0 -empty
0x00002D18       BEQ pipe_found

0x00002D20       ADD R2 R2 1
0x00002D24       B pipe_loop

pipe_found:

0x00002D2C       LI R5 1
0x00002D34       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00002D38       LI R4 PIPE_SIZE
0x00002D40       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00002D44       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00002D4C       ADD R1 R1 R6

0x00002D50       LI R7 0                 ; clean it up
0x00002D58       STW R7 [R1 + PIPE_HEAD]
0x00002D5C       STW R7 [R1 + PIPE_TAIL]
0x00002D60       STW R7 [R1 + PIPE_COUNT]
0x00002D64       STW R7 [R1 + PIPE_RWAIT]
0x00002D68       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00002D6C       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00002D70       LI R1 0
0x00002D78       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00002D7C       LI R2 pipe_pool
0x00002D84       SUB R3 R1 R2

0x00002D88       LI R4 PIPE_SIZE
0x00002D90       DIV R5 R3 R4

0x00002D94       SHL R5 R5 2
0x00002D98       LI R6 pipe_used
0x00002DA0       ADD R6 R6 R5

0x00002DA4       LI R7 0
0x00002DAC       STW R7 [R6]

0x00002DB0       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00002DB4       PUSH LR

0x00002DB8       MOV R8 R1
0x00002DBC       MOV R7 R2
0x00002DC0       MOV R6 R3

0x00002DC4       LDW R9 [R8 + FILE_PRIVATE]

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00002DC8       PUSH R7
0x00002DCC       PUSH R6

0x00002DD0       MOV R1 R7
0x00002DD4       MOV R2 R6
0x00002DD8       LI  R3 0           ; READ access
0x00002DE0       BL user_buffer_valid_range

0x00002DE8       POP R6
0x00002DEC       POP R7

0x00002DF0       CMP R1 1
0x00002DF4       BNE pipe_write_badptr

0x00002DFC       LI R10 0               ; bytes written
pipe_write_retry:
0x00002E04       CMP R10 R6
0x00002E08       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00002E10       LDW R11 [R9 + PIPE_COUNT]
0x00002E14       LI R2 256
0x00002E1C       CMP R11 R2
0x00002E20       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00002E28       LDW R12 [R9 + PIPE_HEAD]

0x00002E2C       MOV R4 R7
0x00002E30       ADD R4 R4 R10
0x00002E34       LDB R5 [R4]     ; read byte from user buff addr

0x00002E38       MOV R4 R9
0x00002E3C       ADD R4 R4 PIPE_BUFFER
0x00002E40       ADD R4 R4 R12
0x00002E44       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00002E48       ADD R12 R12 1
0x00002E4C       LI R2 255
0x00002E54       AND R12 R12 R2
0x00002E58       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00002E5C       LDW R4 [R9 + PIPE_COUNT]
0x00002E60       ADD R4 R4 1
0x00002E64       STW R4 [R9 + PIPE_COUNT]

; written++
0x00002E68       ADD R10 R10 1
0x00002E6C       B pipe_write_retry

pipe_write_done:
; wake readers
0x00002E74       MOV R1 R9
0x00002E78       ADD R1 R1 PIPE_RWAIT
0x00002E7C       BL waitq_wake_all
0x00002E84       MOV R1 R10      ;written bytes
0x00002E88       POP LR
0x00002E8C       RET

pipe_write_badptr:
0x00002E90       LI R1 ERR_FAULT
0x00002E98       POP LR
0x00002E9C       RET

pipe_write_empty:
0x00002EA0       LI R1 0
0x00002EA8       POP LR
0x00002EAC       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00002EB0       MOV R1 R9
0x00002EB4       ADD R1 R1 PIPE_WWAIT
0x00002EB8       LI R2 WAIT_PIPE_WRITE
0x00002EC0       BL waitq_prepare_sleep
    ; race check
0x00002EC8       LDW R4 [R9 + PIPE_COUNT]
0x00002ECC       LI R2 256
0x00002ED4       CMP R4 R2
0x00002ED8       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00002EE0       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00002EE8       B pipe_write_retry      ; unblocked! go write!

fd_remove:
 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
0x00002EF0       CMP R1 3
0x00002EF4       BLT fd_remove_invalid       ; fd 0-1-2 are stdio, not closeable by user

0x00002EFC       CMP R1 MAX_FDS
0x00002F00       BGE fd_remove_invalid       ; fd is out of bounds

0x00002F08       MOV R8 R1

; macro: GET_CURR_TASK_IDX R4
0x00002F0C   LI R1 CURRENT_TASK
0x00002F14   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002F18   LI R1 TASK_SIZE
0x00002F20   MUL R3 R4 R1
0x00002F24   LI R4 tasks
0x00002F2C   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = fd table ptr of current task
0x00002F30   LDW R4 [R4 + TASK_FD_TABLE]

0x00002F34       SHL R5 R8 2
0x00002F38       ADD R6 R4 R5                ; &fd_table[fd]

0x00002F3C       LDW R1 [R6]
0x00002F40       CMP R1 0
0x00002F44       BEQ fd_remove_invalid       ; if fd_table[fd] is null, invalid fd

0x00002F4C       LI R7 0
0x00002F54       STW R7 [R6]                 ; fd_table[fd] = null

0x00002F58       RET                     ; return file* in R1 for file_free

fd_remove_invalid:
0x00002F5C       LI R1 0
0x00002F64       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00002F68       LDW R1 [SP + TF_R1]
0x00002F6C       LDW R2 [SP + TF_R2]
0x00002F70       LDW R3 [SP + TF_R3]

0x00002F74       MOV R7 R2               ; save user buffer
0x00002F78       MOV R6 R3               ; save length
0x00002F7C       PUSH R7
0x00002F80       PUSH R6
0x00002F84       LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
0x00002F8C       BL fetch_fd_entry
0x00002F94       POP R6
0x00002F98       POP R7
0x00002F9C       CMP R1 0
0x00002FA0       BEQ bad_fd
0x00002FA8       MOV R9 R1               ; file object pointer
0x00002FAC       MOV R1 R9
0x00002FB0       MOV R2 R7
0x00002FB4       MOV R3 R6
0x00002FB8       BL file_read
0x00002FC0       STW R1 [SP + TF_R1]

0x00002FC4       B trap_restore

con_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00002FCC       PUSH LR
0x00002FD0       PUSH R8
0x00002FD4       PUSH R9
0x00002FD8       PUSH R10
0x00002FDC       PUSH R11
0x00002FE0       PUSH R12
0x00002FE4       MOV R9 R1
0x00002FE8       MOV R7 R2
0x00002FEC       MOV R6 R3
0x00002FF0       LI R8 0                    ; total bytes collected
0x00002FF8       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x00002FFC       CMP R6 0
0x00003000       BEQ read_done

0x00003008       PUSH R7
0x0000300C       PUSH R6
0x00003010       PUSH R9
0x00003014       MOV R1 R7
0x00003018       MOV R2 R6
0x0000301C       LI R3 1                ; write access for destination buffer
0x00003024       BL user_buffer_valid_range
0x0000302C       POP R9
0x00003030       POP R6
0x00003034       POP R7
0x00003038       CMP R1 1
0x0000303C       BNE con_read_fault

read_wait_uart_rx:
0x00003044       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003048       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x0000304C       AND R5 R5 1                 ; bit 0 = RX_READY
0x00003050       CMP R5 0
0x00003054       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x0000305C   LI R1 CURRENT_TASK
0x00003064   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003068   LI R1 TASK_SIZE
0x00003070   MUL R3 R4 R1
0x00003074   LI R5 tasks
0x0000307C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003080   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003084       MOV R2 R6
0x00003088       MOV R3 R9
0x0000308C       PUSH R6
0x00003090       PUSH R7
0x00003094       PUSH R8
0x00003098       PUSH R9
0x0000309C       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x000030A4       POP R9
0x000030A8       POP R8
0x000030AC       POP R7
0x000030B0       POP R6

0x000030B4       CMP R1 0
0x000030B8       BEQ read_wait_uart_rx

0x000030C0       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x000030C4   LI R1 CURRENT_TASK
0x000030CC   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x000030D0   LI R1 TASK_SIZE
0x000030D8   MUL R3 R5 R1
0x000030DC   LI R4 tasks
0x000030E4   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000030E8   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with newline before copy_to_user
    ; clobbers temporary registers.
0x000030EC       LI R11 0
0x000030F4       SUB R5 R10 1
0x000030F8       ADD R5 R4 R5
0x000030FC       LDB R5 [R5]
0x00003100       CMP R5 10
0x00003104       BNE read_chunk_not_newline
0x0000310C       LI R11 1

read_chunk_not_newline:
0x00003114       PUSH R6
0x00003118       PUSH R7
0x0000311C       PUSH R8
0x00003120       PUSH R9
0x00003124       PUSH R10
0x00003128       PUSH R11
0x0000312C       MOV R1 R7              ; user destination
0x00003130       MOV R2 R10
0x00003134       BL copy_to_user        ; copy from kernel buffer to user buffer
0x0000313C       POP R11
0x00003140       POP R10
0x00003144       POP R9
0x00003148       POP R8
0x0000314C       POP R7
0x00003150       POP R6

0x00003154       ADD R7 R7 R10
0x00003158       ADD R8 R8 R10
0x0000315C       SUB R6 R6 R10

0x00003160       CMP R11 1
0x00003164       BEQ read_complete
0x0000316C       CMP R6 0
0x00003170       BGT read_wait_uart_rx

read_complete:
0x00003178       MOV R1 R8
0x0000317C       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00003184       LI R1 uart_rx_waitq
0x0000318C       LI R2 WAIT_UART_RX
0x00003194       BL waitq_prepare_sleep

0x0000319C       LDW R4 [R9 + UARTDEV_MMIO]
0x000031A0       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x000031A4       AND R10 R10 1
0x000031A8       CMP R10 0
0x000031AC       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x000031B4       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x000031BC       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x000031C4       LI R1 uart_rx_waitq
0x000031CC       BL waitq_cancel_sleep_current

0x000031D4       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x000031DC       LI R1 0
0x000031E4       B read_return

con_read_fault:
0x000031EC       LI R1 ERR_FAULT

read_return:
0x000031F4       POP R12
0x000031F8       POP R11
0x000031FC       POP R10
0x00003200       POP R9
0x00003204       POP R8
0x00003208       POP LR
0x0000320C       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003210       LDW R1 [SP + TF_R1]
0x00003214       LDW R2 [SP + TF_R2]
0x00003218       LDW R3 [SP + TF_R3]
; first fetch file from procs fd_table and check flags for match access WRITE /READ
0x0000321C       MOV R7 R2               ; save user buffer
0x00003220       MOV R6 R3               ; save length
0x00003224       PUSH R7
0x00003228       PUSH R6
0x0000322C       LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
0x00003234       BL fetch_fd_entry       ;input R1 fd on exit R1 - file ptr  => r1=fetch_fd_entry(fd=r1)
0x0000323C       POP R6
0x00003240       POP R7
0x00003244       CMP R1 0
0x00003248       BEQ bad_fd              ;if flags file and in r2 dont match
0x00003250       MOV R9 R1               ; file object pointer
0x00003254       MOV R1 R9
0x00003258       MOV R2 R7
0x0000325C       MOV R3 R6
0x00003260       BL file_write           ; call file write R1 = file ptr, R2 = user buffer, R3 = len
0x00003268       STW R1 [SP + TF_R1]

0x0000326C       B trap_restore

con_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00003274       PUSH LR
0x00003278       MOV R9 R1
0x0000327C       MOV R7 R2
0x00003280       MOV R6 R3
0x00003284       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x00003288       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00003290       CMP R6 0
0x00003294       BEQ write_done             ;0 bytes

0x0000329C       LI R2 KBUFFER_SIZE
0x000032A4       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x000032A8       BLT write_chunk_small
0x000032B0       LI R2 KBUFFER_SIZE

0x000032B8       B write_chunk

write_chunk_small:
0x000032C0       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x000032C4       PUSH R7
0x000032C8       PUSH R6
0x000032CC       PUSH R9
0x000032D0       PUSH R8
0x000032D4       MOV R1 R7
0x000032D8       MOV R2 R2
0x000032DC       LI R3 0                ; read access for source buffer
0x000032E4       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x000032EC       POP R8
0x000032F0       POP R9
0x000032F4       POP R6
0x000032F8       POP R7
0x000032FC       CMP R1 1
0x00003300       BNE driver_bad_pointer

0x00003308       PUSH R7
0x0000330C       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x00003310   LI R1 CURRENT_TASK
0x00003318   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000331C   LI R1 TASK_SIZE
0x00003324   MUL R3 R4 R1
0x00003328   LI R5 tasks
0x00003330   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00003334   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00003338       MOV R1 R7
0x0000333C       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00003344       MOV R10 R1             ; bytes copied
0x00003348       POP R6
0x0000334C       POP R7

0x00003350       PUSH R7
0x00003354       PUSH R9
0x00003358       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x0000335C       LDW R1 [R9 + UARTDEV_MMIO]
0x00003360       LDW R2 [R1 + 4]
0x00003364       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00003368       CMP R2 0
0x0000336C       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00003374   LI R1 CURRENT_TASK
0x0000337C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003380   LI R1 TASK_SIZE
0x00003388   MUL R3 R4 R1
0x0000338C   LI R5 tasks
0x00003394   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00003398   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x0000339C       MOV R2 R10
0x000033A0       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x000033A4       BL device_write
0x000033AC       POP R6
0x000033B0       POP R9
0x000033B4       POP R7

0x000033B8       CMP R1 0        ;nothing is written - go again
0x000033BC       BEQ write_loop

0x000033C4       ADD R8 R8 R1     ;update ptrs
0x000033C8       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x000033CC       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x000033D0       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x000033D8       LI R1 uart_tx_waitq
0x000033E0       LI R2 WAIT_UART_TX
0x000033E8       BL waitq_prepare_sleep

0x000033F0       LDW R1 [R9 + UARTDEV_MMIO]
0x000033F4       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x000033F8       AND R2 R2 2
0x000033FC       CMP R2 0
0x00003400       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00003408       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x00003410       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00003418       LI R1 uart_tx_waitq
0x00003420       BL waitq_cancel_sleep_current

0x00003428       B write_wait_uart_tx

write_done:
0x00003430       MOV R1 R8
0x00003434       POP LR
0x00003438       RET

driver_bad_pointer:
0x0000343C       LI R1 ERR_FAULT
0x00003444       POP LR
0x00003448       RET

bad_fd:
0x0000344C       LI R1 ERR_BADF
0x00003454       STW R1 [SP + TF_R1]

0x00003458       B trap_restore

bad_pointer:
0x00003460       LI R1 ERR_FAULT
0x00003468       STW R1 [SP + TF_R1]

0x0000346C       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00003474       LDW R4 [R1 + FILE_OPS]
0x00003478       LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
0x0000347C       JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00003480       LDW R4 [R1 + FILE_OPS]
0x00003484       LDW R4 [R4 + FOPS_WRITE]    ; get write function xdev_write from ops
0x00003488       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x0000348C       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00003494       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x0000349C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000034A0       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x000034A8       CMP R5 R2                   ; have we read enough bytes?
0x000034AC       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x000034B4       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000034B8       AND R6 R6 1                 ; bit 0 = RX_READY
0x000034BC       CMP R6 0
0x000034C0       BEQ dr_done                 ; no more buffered input available

0x000034C8       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x000034CC       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x000034D0       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x000034D4       CMP R7 10
0x000034D8       BEQ dr_done

0x000034E0       B dr_loop

dr_done:
0x000034E8       MOV R1 R5                   ; return number of bytes actually read
0x000034EC       RET

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

0x000034F0       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000034F4       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000034FC       CMP R5 R2                   ; have we written all bytes?
0x00003500       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00003508       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x0000350C       AND R6 R6 2                 ; bit 1 = TX_READY
0x00003510       CMP R6 0
0x00003514       BEQ dcw_done

0x0000351C       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x00003520       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00003524       ADD R5 R5 1
0x00003528       B dcw_loop

dcw_done:
0x00003530       MOV R1 R5                   ; return number of bytes written
0x00003534       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00003538       LI R1 0
0x00003540       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00003544       PUSH LR
0x00003548       MOV R6 R3
0x0000354C       CMP R6 0
0x00003550       BEQ null_write_done

0x00003558       PUSH R6
0x0000355C       MOV R1 R2
0x00003560       MOV R2 R6
0x00003564       LI R3 0                    ; read access from user source
0x0000356C       BL user_buffer_valid_range
0x00003574       POP R6
0x00003578       CMP R1 1
0x0000357C       BNE null_write_badptr

null_write_done:
0x00003584       MOV R1 R6
0x00003588       POP LR
0x0000358C       RET

null_write_badptr:
0x00003590       LI R1 ERR_FAULT
0x00003598       POP LR
0x0000359C       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, 3)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

0x000035A0       CMP R1 0
0x000035A4       BLT fd_invalid
0x000035AC       CMP R1 MAX_FDS
0x000035B0       BGE fd_invalid

0x000035B8       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x000035BC   LI R1 CURRENT_TASK
0x000035C4   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000035C8   LI R1 TASK_SIZE
0x000035D0   MUL R3 R4 R1
0x000035D4   LI R4 tasks
0x000035DC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000035E0   LDW R4 [R4 + TASK_FD_TABLE]

0x000035E4       SHL R5 R8 2
0x000035E8       ADD R4 R4 R5                ;r4=fd*4+FD_TABLE = file entry according to fd
0x000035EC       LDW R1 [R4]                 ; R1 = file ptr
0x000035F0       LDW R6 [R1 + FILE_FLAGS]
0x000035F4       AND R6 R6 R2
0x000035F8       CMP R6 R2                   ;check file flags R2 input R6 from file
0x000035FC       BNE fd_invalid

0x00003604       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x00003608       LI R1 0
0x00003610       RET

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
0x00003614       PUSH R10
0x00003618       PUSH R11
0x0000361C       PUSH R12

0x00003620       LI R4 0
0x00003628       CMP R2 R4
0x0000362C       BEQ uv_valid

0x00003634       LI R4 USER_BASE
0x0000363C       CMP R1 R4
0x00003640       BLT uv_invalid

0x00003648       LI R4 USER_LIMIT
0x00003650       ADD R5 R1 R2
0x00003654       SUB R5 R5 1
0x00003658       CMP R5 R1
0x0000365C       BLT uv_invalid
0x00003664       CMP R5 R4
0x00003668       BGT uv_invalid
0x00003670       MOV R11 R1              ; save start address; task macros clobber R1
0x00003674       MOV R12 R5              ; save end address for page calculation
0x00003678       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x0000367C   LI R1 CURRENT_TASK
0x00003684   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00003688   LI R1 TASK_SIZE
0x00003690   MUL R3 R6 R1
0x00003694   LI R6 tasks
0x0000369C   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x000036A0   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x000036A4       CMP R6 0
0x000036A8       BEQ uv_invalid

uv_check_pages:
0x000036B0       SHR R7 R11 12
0x000036B4       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x000036B8       CMP R7 R8
0x000036BC       BGT uv_valid
0x000036C4       SHL R9 R7 2
0x000036C8       ADD R9 R9 R6
0x000036CC       LDW R10 [R9]
0x000036D0       AND R5 R10 PTE_P
0x000036D4       CMP R5 0
0x000036D8       BEQ uv_invalid
0x000036E0       AND R5 R10 PTE_U
0x000036E4       CMP R5 0
0x000036E8       BEQ uv_invalid
0x000036F0       CMP R4 0
0x000036F4       BEQ uv_check_read
0x000036FC       AND R5 R10 PTE_W
0x00003700       CMP R5 0
0x00003704       BEQ uv_invalid
0x0000370C       B uv_next

uv_check_read:
0x00003714       AND R5 R10 PTE_R
0x00003718       CMP R5 0
0x0000371C       BEQ uv_invalid

uv_next:
0x00003724       ADD R7 R7 1
0x00003728       B uv_loop

uv_valid:
0x00003730       LI R1 1
0x00003738       POP R12
0x0000373C       POP R11
0x00003740       POP R10
0x00003744       RET

uv_invalid:
0x00003748       LI R1 0

0x00003750       POP R12
0x00003754       POP R11
0x00003758       POP R10
0x0000375C       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003760       LI R5 0
cfu_head:
0x00003768       CMP R2 0
0x0000376C       BEQ cfu_done
0x00003774       OR R6 R1 R4
0x00003778       AND R6 R6 3
0x0000377C       CMP R6 0
0x00003780       BEQ cfu_word
0x00003788       LDB R7 [R1]
0x0000378C       STB R7 [R4]
0x00003790       ADD R1 R1 1
0x00003794       ADD R4 R4 1
0x00003798       ADD R5 R5 1
0x0000379C       SUB R2 R2 1
0x000037A0       B cfu_head
cfu_word:
0x000037A8       CMP R2 4
0x000037AC       BLT cfu_tail
0x000037B4       LDW R7 [R1]
0x000037B8       STW R7 [R4]
0x000037BC       ADD R1 R1 4
0x000037C0       ADD R4 R4 4
0x000037C4       ADD R5 R5 4
0x000037C8       SUB R2 R2 4
0x000037CC       B cfu_word
cfu_tail:
0x000037D4       CMP R2 0
0x000037D8       BEQ cfu_done
0x000037E0       LDB R7 [R1]
0x000037E4       STB R7 [R4]
0x000037E8       ADD R1 R1 1
0x000037EC       ADD R4 R4 1
0x000037F0       ADD R5 R5 1
0x000037F4       SUB R2 R2 1
0x000037F8       B cfu_tail
cfu_done:
0x00003800       MOV R1 R5
0x00003804       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003808       LI R5 0
ctu_head:
0x00003810       CMP R2 0
0x00003814       BEQ ctu_done
0x0000381C       OR R6 R1 R4
0x00003820       AND R6 R6 3
0x00003824       CMP R6 0
0x00003828       BEQ ctu_word
0x00003830       LDB R7 [R4]
0x00003834       STB R7 [R1]
0x00003838       ADD R1 R1 1
0x0000383C       ADD R4 R4 1
0x00003840       ADD R5 R5 1
0x00003844       SUB R2 R2 1
0x00003848       B ctu_head
ctu_word:
0x00003850       CMP R2 4
0x00003854       BLT ctu_tail
0x0000385C       LDW R7 [R4]
0x00003860       STW R7 [R1]
0x00003864       ADD R1 R1 4
0x00003868       ADD R4 R4 4
0x0000386C       ADD R5 R5 4
0x00003870       SUB R2 R2 4
0x00003874       B ctu_word
ctu_tail:
0x0000387C       CMP R2 0
0x00003880       BEQ ctu_done
0x00003888       LDB R7 [R4]
0x0000388C       STB R7 [R1]
0x00003890       ADD R1 R1 1
0x00003894       ADD R4 R4 1
0x00003898       ADD R5 R5 1
0x0000389C       SUB R2 R2 1
0x000038A0       B ctu_tail
ctu_done:
0x000038A8       MOV R1 R5
0x000038AC       RET

handle_debug:
    ; Debug trap - just return
0x000038B0       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x000038B8       CSRR R1 STVAL

0x000038BC       CMP R1 0
0x000038C0       BEQ handle_timer_irq

0x000038C8       CMP R1 1
0x000038CC       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x000038D4       LI R2 0x00102000
0x000038DC       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x000038E0       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x000038E8       LI R2 0x00102000
0x000038F0       LI R3 0
0x000038F8       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Yield the CPU (reschedule and switch tasks)
0x000038FC       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00003904       LI R2 0x00102000
0x0000390C       LI R3 1
0x00003914       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00003918       LI R1 uart_rx_waitq
0x00003920       BL waitq_wake_all
0x00003928       LI R1 uart_tx_waitq
0x00003930       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00003938       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00003940       POP R1                  ; stval, informational only
0x00003944       POP R1                  ; scause, informational only
0x00003948       POP R1
0x0000394C       CSRW SSTATUS R1
0x00003950       POP R1
0x00003954       CSRW SFLAGS R1
0x00003958       POP R1
0x0000395C       CSRW SEPC R1
0x00003960       POP R1                  ; interrupted task SP
0x00003964       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00003968       POP R15
0x0000396C       POP R14
0x00003970       POP R12
0x00003974       POP R11
0x00003978       POP R10
0x0000397C       POP R9
0x00003980       POP R8
0x00003984       POP R7
0x00003988       POP R6
0x0000398C       POP R5
0x00003990       POP R4
0x00003994       POP R3
0x00003998       POP R2
0x0000399C       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x000039A0       CSRRW SP SSCRATCH SP
0x000039A4       SRET


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
;   R1 = tar_index entry
;   R1 = 0 if not found
; --------------------------------------------------

tarfs_lookup:

0x00007C4B       PUSH LR
0x00007C4F       PUSH R8
0x00007C53       PUSH R9
0x00007C57       PUSH R10

0x00007C5B       MOV R8 R1              ; pathname
0x00007C5F       LDB R2 [R8]
0x00007C63       LI R3 47               ; accept normal absolute paths: "/etc/motd"
0x00007C6B       CMP R2 R3
0x00007C6F       BNE lookup_path_ready
0x00007C77       ADD R8 R8 1

lookup_path_ready:

0x00007C7B       LI R9 0                ; index

0x00007C83       LI R10 tar_count
0x00007C8B       LDW R10 [R10]

tar_lookup_loop:

0x00007C8F       CMP R9 R10
0x00007C93       BGE tar_lookup_not_found

    ; entry address

0x00007C9B       LI R1 tar_index

0x00007CA3       LI R2 TAR_IDX_SIZEOF
0x00007CAB       MUL R3 R9 R2

0x00007CAF       ADD R1 R1 R3

    ; compare names

0x00007CB3       MOV R2 R8

0x00007CB7       LDW R1 [R1 + TAR_IDX_NAME]

0x00007CBB       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x00007CC3       CMP R1 1
0x00007CC7       BEQ tar_lookup_found

0x00007CCF       ADD R9 R9 1
0x00007CD3       B tar_lookup_loop

tar_lookup_found:

0x00007CDB       LI R1 tar_index

0x00007CE3       LI R2 TAR_IDX_SIZEOF
0x00007CEB       MUL R3 R9 R2

0x00007CEF       ADD R1 R1 R3        ; R1 = &tar_index[R9]

0x00007CF3       POP R10
0x00007CF7       POP R9
0x00007CFB       POP R8
0x00007CFF       POP LR
0x00007D03       RET

tar_lookup_not_found:

0x00007D07       LI R1 0             ; R1 = NULL

0x00007D0F       POP R10
0x00007D13       POP R9
0x00007D17       POP R8
0x00007D1B       POP LR
0x00007D1F       RET


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

0x00007D23       PUSH LR
0x00007D27       PUSH R8
0x00007D2B       PUSH R9
0x00007D2F       PUSH R10
0x00007D33       PUSH R11
0x00007D37       PUSH R12

0x00007D3B       MOV R8 R1                  ; current tar header
0x00007D3F       LI R11 tar_limit
0x00007D47       ADD R2 R1 R2
0x00007D4B       STW R2 [R11]               ; exclusive end of archive

0x00007D4F       LI R9 tar_index            ; current index entry

0x00007D57       LI R10 0                   ; file count

tar_scan_loop:

0x00007D5F       CMP R10 MAX_TAR_FILES
0x00007D63       BGE tar_done                ; check before writing the next index entry

0x00007D6B       LI R11 tar_limit
0x00007D73       LDW R11 [R11]
0x00007D77       LI R12 TAR_HEADER_SIZE
0x00007D7F       ADD R12 R8 R12
0x00007D83       CMP R12 R11
0x00007D87       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x00007D8F       LDB R11 [R8 + TAR_NAME_OFF]

0x00007D93       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x00007D97       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x00007D9F       MOV R11 R8

0x00007DA3       ADD R11 R11 TAR_NAME_OFF

0x00007DA7       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x00007DAB       MOV R1 R8
0x00007DAF       ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

0x00007DB3       BL tar_parse_octal         ; parse octal size from tar header field to binary integer

0x00007DBB       MOV R12 R1                 ; save file resulted binary size

0x00007DBF       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00007DC3       MOV R11 R8
0x00007DC7       LI R2 TAR_HEADER_SIZE
0x00007DCF       ADD R11 R11 R2

0x00007DD3       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00007DD7       LI R2 TAR_TYPE_OFF
0x00007DDF       ADD R2 R8 R2
0x00007DE3       LDB R11 [R2]
0x00007DE7       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00007DEB       ADD R10 R10 1               ; othewise go to next file count

0x00007DEF       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

0x00007DF3       MOV R11 R12

    ; round up to 512 boundary

0x00007DF7       LI R2 511
0x00007DFF       ADD R11 R11 R2

0x00007E03       SHR R11 R11 9
0x00007E07       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x00007E0B       LI R2 TAR_HEADER_SIZE
0x00007E13       ADD R8 R8 R2

0x00007E17       ADD R8 R8 R11           ; advance to next tar header

0x00007E1B       LI R12 tar_limit
0x00007E23       LDW R12 [R12]
0x00007E27       CMP R8 R12
0x00007E2B       BGTU tar_done            ; file data/padding extends beyond archive

0x00007E33       B tar_scan_loop

tar_done:

0x00007E3B       LI R11 tar_count        ; store total file count for this tar archive in global variable

0x00007E43       STW R10 [R11]

0x00007E47       POP R12
0x00007E4B       POP R11
0x00007E4F       POP R10
0x00007E53       POP R9
0x00007E57       POP R8
0x00007E5B       POP LR

0x00007E5F       RET

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

0x00007E63       PUSH R2
0x00007E67       PUSH R3
0x00007E6B       PUSH R4

0x00007E6F       LI   R2 0                  ; result

octal_loop:

0x00007E77       LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

0x00007E7B       CMP  R3 0
0x00007E7F       BEQ  octal_done

0x00007E87       LI   R4 32                 ; ' '
0x00007E8F       CMP  R3 R4
0x00007E93       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x00007E9B       LI   R4 48
0x00007EA3       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x00007EA7       SHL  R2 R2 3               ; multiply by 8

0x00007EAB       ADD  R2 R2 R3              ; add digit

0x00007EAF       ADD  R1 R1 1               ; advance to next octal character

0x00007EB3       B    octal_loop

octal_done:

0x00007EBB       MOV  R1 R2                 ; return binary result in R1

0x00007EBF       POP  R4
0x00007EC3       POP  R3
0x00007EC7       POP  R2
0x00007ECB       RET

; for kputs
newline:
    .ASCIIZ "\r\n"

tarfs_banner:
    .ASCIIZ "[TARFS]\r\n"

;==============================================================
; tarfs_dump_index - a simple debug function to print the contents of the tar index
; for each file, it prints the filename and size. This can be called from a debug
; syscall or from the kernel initialization code after tarfs_init to verify the
; index was populated correctly.
;==============================================================
tarfs_dump_index:

0x00007EDC       PUSH LR
0x00007EE0       PUSH R8
0x00007EE4       PUSH R9
0x00007EE8       PUSH R10

0x00007EEC       LI R8 0

0x00007EF4       LI R10 tar_count
0x00007EFC       LDW R10 [R10]

0x00007F00       LI R1 tarfs_banner
0x00007F08       BL kputs

dump_loop:

0x00007F10       CMP R8 R10
0x00007F14       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00007F1C       LI R1 tar_index

0x00007F24       LI R2 TAR_IDX_SIZEOF
0x00007F2C       MUL R3 R8 R2

0x00007F30       ADD R9 R1 R3

    ; filename

0x00007F34       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x00007F38       MOV R1 R2
0x00007F3C       BL kputs

    ; newline

0x00007F44       LI R1 newline
0x00007F4C       BL kputs

0x00007F54       ADD R8 R8 1
0x00007F58       B dump_loop

dump_done:

0x00007F60       POP R10
0x00007F64       POP R9
0x00007F68       POP R8
0x00007F6C       POP LR
0x00007F70       RET

;==============================================================
; TARFS file operations
;==============================================================

tarfs_ops:
    .WORD tarfs_read
    .WORD tarfs_write

tarfs_read:
    ; R1=file*, R2=user destination, R3=requested length
0x00007F7C       PUSH LR
0x00007F80       PUSH R8
0x00007F84       PUSH R9
0x00007F88       PUSH R10
0x00007F8C       PUSH R11
0x00007F90       PUSH R12

0x00007F94       MOV R8 R1
0x00007F98       MOV R9 R2
0x00007F9C       MOV R10 R3

0x00007FA0       CMP R10 0
0x00007FA4       BEQ tarfs_read_eof

0x00007FAC       PUSH R8
0x00007FB0       PUSH R9
0x00007FB4       MOV R1 R9
0x00007FB8       MOV R2 R10
0x00007FBC       LI R3 1                    ; destination must be user-writable
0x00007FC4       BL user_buffer_valid_range
0x00007FCC       POP R9
0x00007FD0       POP R8
0x00007FD4       CMP R1 1
0x00007FD8       BNE tarfs_read_fault

0x00007FE0       LDW R11 [R8 + FILE_PRIVATE]
0x00007FE4       LDW R12 [R8 + FILE_OFFSET]
0x00007FE8       LDW R4 [R11 + TAR_IDX_SIZE]

0x00007FEC       CMP R12 R4
0x00007FF0       BGEU tarfs_read_eof

0x00007FF8       SUB R4 R4 R12             ; bytes remaining
0x00007FFC       CMP R10 R4
0x00008000       BLEU tarfs_read_count_ready
0x00008008       MOV R10 R4

tarfs_read_count_ready:
0x0000800C       LDW R4 [R11 + TAR_IDX_DATA]
0x00008010       ADD R4 R4 R12             ; kernel source
0x00008014       MOV R1 R9                 ; user destination
0x00008018       MOV R2 R10
0x0000801C       BL copy_to_user

0x00008024       ADD R12 R12 R1
0x00008028       STW R12 [R8 + FILE_OFFSET]
0x0000802C       B tarfs_read_done

tarfs_read_fault:
0x00008034       LI R1 ERR_FAULT
0x0000803C       B tarfs_read_done

tarfs_read_eof:
0x00008044       LI R1 0

tarfs_read_done:
0x0000804C       POP R12
0x00008050       POP R11
0x00008054       POP R10
0x00008058       POP R9
0x0000805C       POP R8
0x00008060       POP LR
0x00008064       RET

tarfs_write:
0x00008068       LI R1 ERR_ACCES
0x00008070       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x00008074       PUSH LR
0x00008078       PUSH R8
0x0000807C       MOV R8 R1

kputs_loop:
0x00008080       LDB R1 [R8]

0x00008084       CMP R1 0
0x00008088       BEQ kputs_done

0x00008090       BL uart_putc

0x00008098       ADD R8 R8 1

0x0000809C       B kputs_loop

kputs_done:
0x000080A4       POP R8
0x000080A8       POP LR
0x000080AC       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x000080B0       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x000080B8       LDW R2 [R3 + 4]   ; read UART status register
0x000080BC       AND R2 R2 2       ; check if TX ready (bit 1)
0x000080C0       CMP R2 0
0x000080C4       BEQ poll

0x000080CC       STW R1 [R3 + 0]   ; R1 is the character value
0x000080D0       RET



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

0x000080D4       PUSH R9
0x000080D8       PUSH R10

0x000080DC       MOV R9 R1                  ; preserve wait queue pointer
0x000080E0       MOV R10 R2                 ; preserve debug wait reason

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x000080E4   LI R1 CURRENT_TASK
0x000080EC   LDW R2 [R1]

0x000080F0       LI R4 1
0x000080F8       SHL R4 R4 R2               ; R4 = bit for current task
0x000080FC       LDW R5 [R9 + WQ_MASK]
0x00008100       OR R5 R5 R4
0x00008104       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00008108   LI R1 TASK_SIZE
0x00008110   MUL R3 R2 R1
0x00008114   LI R5 tasks
0x0000811C   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00008120   LI R1 TASK_BLOCKED_IO
0x00008128   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x0000812C   STW R10 [R5 + TASK_WAIT]

0x00008130       POP R10
0x00008134       POP R9
0x00008138       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x0000813C       PUSH R9

0x00008140       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00008144   LI R1 CURRENT_TASK
0x0000814C   LDW R2 [R1]

0x00008150       LDW R4 [R9 + WQ_MASK]

0x00008154       LI  R5 1
0x0000815C       SHL R5 R5 R2        ;shift to position of current task bit

0x00008160       NOT R5 R5           ; invert to get mask for clearing this bit

0x00008164       AND R4 R4 R5        ; clear current task bit

0x00008168       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x0000816C   LI R1 TASK_SIZE
0x00008174   MUL R3 R2 R1
0x00008178   LI R5 tasks
0x00008180   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x00008184   LI R1 TASK_READY
0x0000818C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x00008190   LI R1 WAIT_NONE
0x00008198   STW R1 [R5 + TASK_WAIT]

0x0000819C       POP R9
0x000081A0       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000081A4       PUSH LR
0x000081A8       BL schedule_call
0x000081B0       POP LR
0x000081B4       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x000081B8       PUSH LR

0x000081BC       MOV R9 R1
0x000081C0       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x000081C4       LI R10 0
0x000081CC       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x000081D0       LI R2 0                    ; task index

wq_wake_loop:
0x000081D8       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x000081DC       BGE wq_wake_done

0x000081E4       LI R3 1
0x000081EC       SHL R3 R3 R2               ; R3 = bit for task R2
0x000081F0       AND R4 R8 R3
0x000081F4       CMP R4 0
0x000081F8       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00008200   LI R1 TASK_SIZE
0x00008208   MUL R3 R2 R1
0x0000820C   LI R5 tasks
0x00008214   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00008218   LI R1 TASK_READY
0x00008220   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00008224   LI R1 WAIT_NONE
0x0000822C   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00008230       ADD R2 R2 1
0x00008234       B wq_wake_loop

wq_wake_done:
0x0000823C       POP LR
0x00008240       RET

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

0x00008244       LI R2 0                      ; index

fa_loop:
0x0000824C       CMP R2 MAX_FILES
0x00008250       BGE fa_fail

0x00008258       SHL R3 R2 2                  ; index * 4
0x0000825C       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00008264       ADD R4 R4 R3

0x00008268       LDW R5 [R4]
0x0000826C       CMP R5 0
0x00008270       BEQ fa_found

0x00008278       ADD R2 R2 1
0x0000827C       B fa_loop

fa_found:
0x00008284       LI R5 1
0x0000828C       STW R5 [R4]                  ; mark slot used

0x00008290       LI R4 FILE_SIZE
0x00008298       MUL R6 R2 R4

0x0000829C       LI R1 file_pool
0x000082A4       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x000082A8       LI R7 0

0x000082B0       STW R7 [R1 + FILE_OPS]
0x000082B4       STW R7 [R1 + FILE_PRIVATE]
0x000082B8       STW R7 [R1 + FILE_OFFSET]
0x000082BC       STW R7 [R1 + FILE_FLAGS]

0x000082C0       RET

fa_fail:
0x000082C4       LI R1 0
0x000082CC       RET

;=================================================================
; file_free:
; input:
; R1 = pointer to FILE object
; none output
;=================================================================

file_free:

0x000082D0       LI R2 file_pool
0x000082D8       SUB R3 R1 R2                 ; offset from pool base

0x000082DC       LI R4 FILE_SIZE
0x000082E4       DIV R5 R3 R4                 ; slot number

0x000082E8       SHL R5 R5 2                  ; slot * 4

0x000082EC       LI R6 file_used
0x000082F4       ADD R6 R6 R5                 ; address of slot in file_used

0x000082F8       LI R7 0
0x00008300       STW R7 [R6]                  ; mark free

0x00008304       RET


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

0x00008308       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x0000830C       LI  R1 tasks
0x00008314       LI  R2 TASK_SIZE
0x0000831C       LI  R3 MAX_TASKS
0x00008324       MUL R3 R2 R3
0x00008328       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x00008330       LI R1 idle_task
0x00008338       LI R2 0
0x00008340       BL task_create

0x00008348       CMP R1 0
0x0000834C       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task A
    ; ----------------------------------

0x00008354       LI R1 TASK_A_START
0x0000835C       LI R2 1
0x00008364       BL task_create

0x0000836C       CMP R1 0
0x00008370       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task B
    ; ----------------------------------

0x00008378       LI R1 TASK_B_START
0x00008380       LI R2 2
0x00008388       BL task_create

0x00008390       CMP R1 0
0x00008394       BEQ init_scheduler_fail

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x0000839C       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x000083A4   LI R1 CURRENT_TASK
0x000083AC   STW R2 [R1]

0x000083B0       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x000083B4       RET


init_scheduler_fail:

0x000083B8       DEBUG 99

halt:
0x000083BC       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x000083C4   LI R1 CURRENT_TASK
0x000083CC   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x000083D0       ADD R3 R2 1

wrap_check:

0x000083D4       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x000083D8       BLT check_task
0x000083E0       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x000083E8       LI R4 TASK_SIZE
0x000083F0       MUL R5 R3 R4
0x000083F4       LI R6 tasks
0x000083FC       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00008400       LDW R7 [R5 + TASK_STATE]

0x00008404       CMP R7 1
0x00008408       BEQ do_switch
    ; if not ready go to next task in list
0x00008410       ADD R3 R3 1
0x00008414       B wrap_check

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
0x0000841C   LI R1 CURRENT_TASK
0x00008424   STW R3 [R1]
0x00008428       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x0000842C   LI R1 TASK_SIZE
0x00008434   MUL R3 R2 R1
0x00008438   LI R5 tasks
0x00008440   ADD R5 R5 R3
0x00008444       MOV R3 R8
0x00008448       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x0000844C       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00008450   STW R7 [R5 + TASK_USP]

0x00008454       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00008458   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x0000845C   LI R1 RESUME_TRAP
0x00008464   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00008468   LI R1 TASK_SIZE
0x00008470   MUL R3 R8 R1
0x00008474   LI R5 tasks
0x0000847C   ADD R5 R5 R3
0x00008480       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x00008484   LDW R7 [R5 + TASK_PTBR]
0x00008488       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x0000848C   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x00008490   LDW R7 [R9 + TASK_STATE]
0x00008494       CMP R7 TASK_ZOMBIE
0x00008498       BNE switch_old_reaped
0x000084A0       PUSH R5
0x000084A4       MOV R1 R9
0x000084A8       BL task_destroy
0x000084B0       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x000084B4   LDW R7 [R5 + TASK_RESUME]
0x000084B8       CMP R7 RESUME_KERNEL
0x000084BC       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x000084C4       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x000084CC       PUSH R1
0x000084D0       PUSH R2
0x000084D4       PUSH R3
0x000084D8       PUSH R4
0x000084DC       PUSH R5
0x000084E0       PUSH R6
0x000084E4       PUSH R7
0x000084E8       PUSH R8
0x000084EC       PUSH R9
0x000084F0       PUSH R10
0x000084F4       PUSH R11
0x000084F8       PUSH R12
0x000084FC       PUSH R14
0x00008500       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00008504   LI R1 CURRENT_TASK
0x0000850C   LDW R2 [R1]

0x00008510       ADD R3 R2 1

schedule_call_wrap_check:
0x00008514       CMP R3 MAX_TASKS
0x00008518       BLT schedule_call_check_task
0x00008520       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00008528       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x0000852C   LI R1 TASK_SIZE
0x00008534   MUL R3 R8 R1
0x00008538   LI R5 tasks
0x00008540   ADD R5 R5 R3
0x00008544       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00008548   LDW R7 [R5 + TASK_STATE]
0x0000854C       CMP R7 TASK_READY               ; check it can be run
0x00008550       BEQ schedule_call_do_switch

0x00008558       ADD R3 R3 1
0x0000855C       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00008564   LI R1 CURRENT_TASK
0x0000856C   STW R3 [R1]
0x00008570       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00008574   LI R1 TASK_SIZE
0x0000857C   MUL R3 R2 R1
0x00008580   LI R5 tasks
0x00008588   ADD R5 R5 R3
0x0000858C       MOV R3 R8

0x00008590       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x00008594   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x00008598   LI R1 RESUME_KERNEL
0x000085A0   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x000085A4   LI R1 TASK_SIZE
0x000085AC   MUL R3 R8 R1
0x000085B0   LI R5 tasks
0x000085B8   ADD R5 R5 R3
0x000085BC       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x000085C0   LDW R7 [R5 + TASK_PTBR]
0x000085C4       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x000085C8   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x000085CC   LDW R7 [R5 + TASK_RESUME]
0x000085D0       CMP R7 RESUME_KERNEL
0x000085D4       BEQ restore_kernel_context

0x000085DC       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x000085E4       DISABLEINT                  ; RET does jump by LR(R15)
0x000085E8       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x000085EC       POP R14                     ; (in kernel)
0x000085F0       POP R12                     ; DI - to avoid int nesting
0x000085F4       POP R11
0x000085F8       POP R10
0x000085FC       POP R9
0x00008600       POP R8
0x00008604       POP R7
0x00008608       POP R6
0x0000860C       POP R5
0x00008610       POP R4
0x00008614       POP R3
0x00008618       POP R2
0x0000861C       POP R1
0x00008620       RET
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

0x00008634       LI R2 0                  ; page index

pa_loop:
0x0000863C       LI R1 MAX_PHYS_PAGES

0x00008644       CMP R2 R1
0x00008648       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00008650       MOV R3 R2
0x00008654       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x00008658       MOV R4 R2
0x0000865C       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00008660       LI R5 page_bitmap
0x00008668       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x0000866C       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x00008670       LI R7 1
0x00008678       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x0000867C       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x00008680       CMP R8 0
0x00008684       BEQ pa_found                ; if bit is 0, page is free

0x0000868C       ADD R2 R2 1                 ; increment page index and check next page
0x00008690       B pa_loop

pa_found:

    ; mark page allocated

0x00008698       OR  R6 R6 R7
0x0000869C       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x000086A0       LI  R9 PAGE_ALLOC_BASE

0x000086A8       MOV R1 R2
0x000086AC       SHL R1 R1 12          ; page_index * 4096

0x000086B0       ADD R1 R1 R9

0x000086B4       RET

pa_fail:

0x000086B8       LI R1 0                     ; no free pages
0x000086C0       RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:

0x000086C4       LI R2 PAGE_ALLOC_BASE
0x000086CC       SUB R3 R1 R2         ; calculate offset from base

0x000086D0       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x000086D4       MOV R4 R3
0x000086D8       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x000086DC       MOV R5 R3
0x000086E0       AND R5 R5 7          ; bit index in byte = page index % 8

0x000086E4       LI R6 page_bitmap
0x000086EC       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x000086F0       LDB R7 [R6]

0x000086F4       LI R8 1
0x000086FC       SHL R8 R8 R5         ; mask for this page's bit

0x00008700       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00008704       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x00008708       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000870C       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

0x00008710       LI R2 0

pz_loop:

0x00008718       CMP R3 0
0x0000871C       BEQ pz_done

0x00008724       STB R2 [R1]

0x00008728       ADD R1 R1 1
0x0000872C       SUB R3 R3 1

0x00008730       B pz_loop

pz_done:
0x00008738       RET

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

0x00008AC0       PUSH LR

0x00008AC4       MOV R8 R1          ; entry
0x00008AC8       MOV R9 R2          ; pid
0x00008ACC       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x00008AD4       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x00008ADC       CMP R1 0
0x00008AE0       BEQ task_create_fail

0x00008AE8       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x00008AEC       MOV R1 R10
0x00008AF0       LI R3 TASK_SIZE
0x00008AF8       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x00008B00   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x00008B04   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x00008B08       BL page_alloc
0x00008B10       CMP R1 0
0x00008B14       BEQ task_create_fail

0x00008B1C       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x00008B20   STW R1 [R10 + TASK_PTBR]

0x00008B24       MOV R1 R12
0x00008B28       LI  R3 PAGE_SIZE
0x00008B30       BL  mem_zero                   ; zero out the sensitive new page table

0x00008B38       MOV R1 R12
0x00008B3C       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x00008B44   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00008B48   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x00008B4C   LDW R1 [R10 + TASK_PTBR]
0x00008B50       MOV R2 R8
0x00008B54       LI R3 0xFFFFF000
0x00008B5C       AND R2 R2 R3
0x00008B60       MOV R3 R2
0x00008B64       CMP R9 0
0x00008B68       BEQ task_create_map_kernel_entry
0x00008B70       LI R4 USER_RX
0x00008B78       B task_create_map_entry
task_create_map_kernel_entry:
0x00008B80       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x00008B88       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x00008B90       BL page_alloc
0x00008B98       CMP R1 0
0x00008B9C       BEQ task_create_fail

0x00008BA4       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x00008BA8   STW R12 [R10 + TASK_USTACK_PAGE]

0x00008BAC       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x00008BB4   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x00008BB8   LDW R1 [R10 + TASK_PTBR]

0x00008BBC       LI  R2 USER_STACK_VA
0x00008BC4       MOV R3 R12
0x00008BC8       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x00008BD0       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x00008BD8       BL page_alloc
0x00008BE0       CMP R1 0
0x00008BE4       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x00008BEC   STW R1 [R10 + TASK_KSTACK_PAGE]
0x00008BF0       LI R2 PAGE_SIZE

0x00008BF8       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x00008BFC       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x00008C00   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00008C04   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x00008C08       LI R1 0

0x00008C10       PUSH R1            ; R1
0x00008C14       PUSH R1            ; R2
0x00008C18       PUSH R1            ; R3
0x00008C1C       PUSH R1            ; R4
0x00008C20       PUSH R1            ; R5
0x00008C24       PUSH R1            ; R6
0x00008C28       PUSH R1            ; R7
0x00008C2C       PUSH R1            ; R8
0x00008C30       PUSH R1            ; R9
0x00008C34       PUSH R1            ; R10
0x00008C38       PUSH R1            ; R11
0x00008C3C       PUSH R1            ; R12
0x00008C40       PUSH R1            ; R14 (FP)
0x00008C44       PUSH R1            ; R15 (LR)

0x00008C48       PUSH R11           ; R11 - user SP top

0x00008C4C       MOV R1 R8
0x00008C50       PUSH R1            ; sepc = entry

0x00008C54       LI R1 0
0x00008C5C       PUSH R1            ; sflags

0x00008C60       CMP R9 0
0x00008C64       BEQ task_create_kernel_status
0x00008C6C       LI R1 0x20
0x00008C74       B task_create_status_ready
task_create_kernel_status:
0x00008C7C       LI R1 0x120
task_create_status_ready:
0x00008C84       PUSH R1            ; sstatus

0x00008C88       LI R1 0
0x00008C90       PUSH R1            ; scause
0x00008C94       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x00008C98       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x00008C9C   STW R1 [R10 + TASK_KSP]

0x00008CA0       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x00008CA4   LI R1 WAIT_NONE
0x00008CAC   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x00008CB0   LI R1 RESUME_TRAP
0x00008CB8   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x00008CBC       BL page_alloc
0x00008CC4       CMP R1 0
0x00008CC8       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x00008CD0       MOV R12 R1

0x00008CD4       LI  R3 PAGE_SIZE
0x00008CDC       MOV R1 R12
0x00008CE0       BL  mem_zero

    ; stdin
0x00008CE8       LI  R2 file_stdin
0x00008CF0       STW R2 [R12 + 0]

    ; stdout
0x00008CF4       LI  R2 file_stdout
0x00008CFC       STW R2 [R12 + 4]

    ; stderr
0x00008D00       LI  R2 file_stderr
0x00008D08       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x00008D0C   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x00008D10       BL page_alloc
0x00008D18       CMP R1 0
0x00008D1C       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x00008D24   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x00008D28       BL page_alloc
0x00008D30       CMP R1 0
0x00008D34       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x00008D3C   STW R1 [R10 + TASK_KBUF_RD_PTR]

0x00008D40       BL page_alloc
0x00008D48       CMP R1 0
0x00008D4C       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x00008D54   STW R1 [R10 + TASK_DATA_PAGE]

0x00008D58       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x00008D5C   LDW R1 [R10 + TASK_PTBR]

0x00008D60       LI  R2 USER_DATA_VA
0x00008D68       MOV R3 R12
0x00008D6C       LI  R4 USER_RW
0x00008D74       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x00008D7C   LI R1 TASK_READY
0x00008D84   STW R1 [R10 + TASK_STATE]

0x00008D88       MOV R1 R10                              ; return created task pointer

0x00008D8C       POP LR
0x00008D90       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x00008D94       CMP R10 0
0x00008D98       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x00008DA0   LDW R1 [R10 + TASK_PTBR]
0x00008DA4       CMP R1 0
0x00008DA8       BEQ task_create_free_ustack
0x00008DB0       BL page_free

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00008DB8   LDW R1 [R10 + TASK_USTACK_PAGE]
0x00008DBC       CMP R1 0
0x00008DC0       BEQ task_create_free_kstack
0x00008DC8       BL page_free

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x00008DD0   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x00008DD4       CMP R1 0
0x00008DD8       BEQ task_create_free_fd
0x00008DE0       BL page_free

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00008DE8   LDW R1 [R10 + TASK_FD_TABLE]
0x00008DEC       CMP R1 0
0x00008DF0       BEQ task_create_free_kwr
0x00008DF8       BL page_free

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x00008E00   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x00008E04       CMP R1 0
0x00008E08       BEQ task_create_free_krd
0x00008E10       BL page_free

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x00008E18   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x00008E1C       CMP R1 0
0x00008E20       BEQ task_create_free_data
0x00008E28       BL page_free

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x00008E30   LDW R1 [R10 + TASK_DATA_PAGE]
0x00008E34       CMP R1 0
0x00008E38       BEQ task_create_clear_slot
0x00008E40       BL page_free

task_create_clear_slot:
0x00008E48       MOV R1 R10
0x00008E4C       LI R3 TASK_SIZE
0x00008E54       BL mem_zero

task_create_fail_return:
0x00008E5C       LI R1 0

0x00008E64       POP LR
0x00008E68       RET

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

0x00008E6C       PUSH LR
0x00008E70       push R12 ; preserve R12 which we use for temporary storage in this function
0x00008E74       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x00008E78   LDW R2 [R1 + TASK_PTBR]
0x00008E7C       CMP R2 0
0x00008E80       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x00008E88       MOV R1 R2
0x00008E8C       BL page_free        ; free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x00008E94   LDW R2 [R12 + TASK_USTACK_PAGE]
0x00008E98       CMP R2 0
0x00008E9C       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00008EA4       MOV R1 R2
0x00008EA8       BL page_free

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x00008EB0   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x00008EB4       CMP R2 0
0x00008EB8       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00008EC0       MOV R1 R2
0x00008EC4       BL page_free

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x00008ECC   LDW R2 [R12 + TASK_FD_TABLE]
0x00008ED0       CMP R2 0
0x00008ED4       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00008EDC       MOV R1 R2
0x00008EE0       BL page_free

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x00008EE8   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x00008EEC       CMP R2 0
0x00008EF0       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x00008EF8       MOV R1 R2
0x00008EFC       BL page_free

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x00008F04   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x00008F08       CMP R2 0
0x00008F0C       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x00008F14       MOV R1 R2
0x00008F18       BL page_free

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x00008F20   LDW R2 [R12 + TASK_DATA_PAGE]
0x00008F24       CMP R2 0
0x00008F28       BEQ td_done     ; if task has no user data page, it also has no user buffers to free, so skip freeing user buffers and move to clearing slot and returning
0x00008F30       MOV R1 R2
0x00008F34       BL page_free

td_done:

0x00008F3C       MOV R1 R12
0x00008F40       LI  R3 TASK_SIZE
0x00008F48       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x00008F50       POP R12         ; restore R12
0x00008F54       POP LR
0x00008F58       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x00008F5C       PUSH LR
0x00008F60       PUSH R8
0x00008F64       PUSH R9
0x00008F68       PUSH R10
0x00008F6C       PUSH R11
0x00008F70       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x00008F74   LDW R4 [R1 + TASK_FD_TABLE]
0x00008F78       MOV R12 R4

0x00008F7C       LI R5 3              ; skip stdin/out/err
0x00008F84       MOV R11 R5

fd_loop:

0x00008F88       CMP R11 MAX_FDS
0x00008F8C       BGE fd_done         ; if we processed all fd slots, we are done

0x00008F94       SHL R6 R11 2
0x00008F98       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x00008F9C       LDW R8 [R10]
0x00008FA0       CMP R8 0
0x00008FA4       BEQ fd_next         ; if fd slot is empty, skip to next

0x00008FAC       MOV R1 R8
0x00008FB0       BL file_free
0x00008FB8       LI R9 0
0x00008FC0       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x00008FC4       ADD R11 R11 1
0x00008FC8       B fd_loop

fd_done:
0x00008FD0       POP R12
0x00008FD4       POP R11
0x00008FD8       POP R10
0x00008FDC       POP R9
0x00008FE0       POP R8
0x00008FE4       POP LR
0x00008FE8       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x00008FEC       PUSH LR
0x00008FF0       PUSH R8
0x00008FF4       PUSH R9
0x00008FF8       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x00008FFC   LI R1 CURRENT_TASK
0x00009004   LDW R10 [R1]
0x00009008       LI R8 0

task_reap_loop:
0x00009010       CMP R8 MAX_TASKS
0x00009014       BGE task_reap_done

0x0000901C       CMP R8 R10
0x00009020       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x00009028   LI R1 TASK_SIZE
0x00009030   MUL R3 R8 R1
0x00009034   LI R9 tasks
0x0000903C   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x00009040   LDW R1 [R9 + TASK_STATE]
0x00009044       CMP R1 TASK_ZOMBIE
0x00009048       BNE task_reap_next

0x00009050       PUSH R8
0x00009054       MOV R1 R9
0x00009058       BL task_destroy
0x00009060       POP R8

task_reap_next:
0x00009064       ADD R8 R8 1
0x00009068       B task_reap_loop

task_reap_done:
0x00009070       POP R10
0x00009074       POP R9
0x00009078       POP R8
0x0000907C       POP LR
0x00009080       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x00009084       LI R1 tasks
0x0000908C       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x00009094   LDW R3 [R1 + TASK_STATE]

0x00009098       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000909C       BEQ task_alloc_found

0x000090A4       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x000090A8       SUB R2 R2 1
0x000090AC       BNE task_alloc_loop

; no free tasks slots

0x000090B4       LI R1 0
0x000090BC       RET

task_alloc_found:                           ;R1 points to free task slot

0x000090C0       RET

; ==================================================
; TAR index entry
; ==================================================

.EQU TAR_IDX_NAME,     0      ; ptr to filename
.EQU TAR_IDX_DATA,     4      ; ptr to file data
.EQU TAR_IDX_SIZE,     8      ; file size
.EQU TAR_IDX_TYPE,    12      ; file/dir

.EQU TAR_IDX_SIZEOF,  16




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
0x00009000       ENABLEINT
0x00009004       LI R1 0
idle_loop:
0x0000900C       ADD R1 R1 1
    ;DEBUG 2
    ;LI R1 SYS_EXIT
    ;SVC SYS_EXIT
0x00009010       B idle_loop

; --TASK 1----------------------------------------------
.ORG 0x19000
TASK_A_START:
0x00019000       li R1 1
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
    ;DEBUG 1
0x0001906C       pop R1
0x00019070       sub R1 R1 1
0x00019074       cmp r1 0
0x00019078       BNE write_loop1
    ; Exit after the write test.
0x00019080       LI R1 SYS_EXIT
0x00019088       SVC SYS_EXIT

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
0x0001A090       LI R3 18
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
0x0001A0B4       LI R3 CONSOLE_INPUT_LEN
0x0001A0BC       SVC SYS_READ
0x0001A0C0       CMP R1 0
0x0001A0C4       BLE task_b_yield

0x0001A0CC       MOV R5 R1
0x0001A0D0       LI R1 STDOUT_FD
0x0001A0D8       LI R2 USER_READ_BUF
0x0001A0E0       MOV R3 R5
0x0001A0E4       SVC SYS_WRITE

task_b_yield:
0x0001A0E8       SVC SYS_YIELD
0x0001A0EC       B task_b_loop

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

.ORG 0xA0000
tarfs_start:

; etc/motd, 16 bytes
    .ASCIIZ "etc/motd"
    .SPACE 115
    .ASCIIZ "00000000020"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    .ASCIIZ "Welcome to KR32\n"
    .SPACE 495

; bin/sh, 10 bytes
    .ASCIIZ "bin/sh"
    .SPACE 117
    .ASCIIZ "00000000012"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    .ASCIIZ "#!/bin/sh\n"
    .SPACE 501

; bin/ls, empty placeholder executable
    .ASCIIZ "bin/ls"
    .SPACE 117
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354

; TAR end marker: two zero headers
    .SPACE 1024

tarfs_end:
[ASM] Built memory.img (658944 bytes)
