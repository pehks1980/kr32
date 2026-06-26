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


    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x000021E4       LI R2 0x00100000      ; UART physical and virtual base
0x000021EC       LI R3 0x00100000
0x000021F4       LI R4 KERNEL_FLAGS
0x000021FC       BL map_page

0x00002204       LI R2 0x00101000      ; PIT physical and virtual base
0x0000220C       LI R3 0x00101000
0x00002214       LI R4 KERNEL_FLAGS
0x0000221C       BL map_page

0x00002224       LI R2 0x00102000      ; PIC physical and virtual base
0x0000222C       LI R3 0x00102000
0x00002234       LI R4 KERNEL_FLAGS
0x0000223C       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x00002244       LI R12 PAGE_ALLOC_BASE
0x0000224C       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x00002254       CMP R12 R7
0x00002258       BGE map_common_dynamic_done
0x00002260       MOV R2 R12
0x00002264       MOV R3 R12
0x00002268       LI R4 KERNEL_FLAGS
0x00002270       BL map_page
0x00002278       LI R6 PAGE_SIZE
0x00002280       ADD R12 R12 R6
0x00002284       B map_common_dynamic_loop
map_common_dynamic_done:

0x0000228C       POP R12
0x00002290       POP LR
0x00002294       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002298       SHR R5 R2 12               ; VPN
0x0000229C       SHL R5 R5 2                ; page-table byte offset
0x000022A0       OR R6 R3 R4                ; PTE = PA page base | flags
0x000022A4       STW R6 [R1 + R5]
0x000022A8       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x000022AC       LI R1 0x00102000
0x000022B4       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x000022BC       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x000022C0       LI R1 0x00101000
0x000022C8       LI R2 2000
0x000022D0       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x000022D4       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000022DC       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x000022E0       LI R1 0x00100000
0x000022E8       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000022F0       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x000022F4       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000022F8       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000022FC       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x00002300       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x00002304       PUSH R1
0x00002308       PUSH R2
0x0000230C       PUSH R3
0x00002310       PUSH R4
0x00002314       PUSH R5
0x00002318       PUSH R6
0x0000231C       PUSH R7
0x00002320       PUSH R8
0x00002324       PUSH R9
0x00002328       PUSH R10
0x0000232C       PUSH R11
0x00002330       PUSH R12
0x00002334       PUSH R14
0x00002338       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x0000233C       CSRR R1 SSCRATCH
0x00002340       PUSH R1
0x00002344       CSRR R1 SEPC
0x00002348       PUSH R1
0x0000234C       CSRR R1 SFLAGS
0x00002350       PUSH R1
0x00002354       CSRR R1 SSTATUS
0x00002358       PUSH R1
0x0000235C       CSRR R1 SCAUSE
0x00002360       PUSH R1
0x00002364       CSRR R1 STVAL
0x00002368       PUSH R1

    ; Dispatch based on scause.
0x0000236C       CSRR R1 SCAUSE
0x00002370       CMP R1 0
0x00002374       BEQ handle_divide_zero

0x0000237C       CMP R1 1
0x00002380       BEQ handle_invalid_instr

0x00002388       CMP R1 2
0x0000238C       BEQ handle_page_fault

0x00002394       CMP R1 3
0x00002398       BEQ handle_syscall

0x000023A0       CMP R1 6
0x000023A4       BEQ handle_debug

0x000023AC       CMP R1 16
0x000023B0       BEQ handle_irq

    ; Unknown cause - halt
0x000023B8       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x000023BC       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x000023C4       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x000023CC       HLT

0x000023D0       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x000023D8       CSRR R2 STVAL

0x000023DC       CMP R2 SYS_COUNT
0x000023E0       BGE syscall_unknown

0x000023E8       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000023F0       SHL R4 R2 2
0x000023F4       LDW R5 [R3 + R4]
0x000023F8       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000023FC       LI R1 ERR_NOSYS
0x00002404       STW R1 [SP + TF_R1]
0x00002408       B trap_restore

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

0x00002434       LI R1 0
0x0000243C       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00002440       B schedule_and_switch

syscall_exit:
    ;================================================================
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002448   LI R1 CURRENT_TASK
0x00002450   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002454   LI R1 TASK_SIZE
0x0000245C   MUL R3 R2 R1
0x00002460   LI R5 tasks
0x00002468   ADD R5 R5 R3

0x0000246C       PUSH R5
0x00002470       MOV R1 R5
0x00002474       BL task_close_fds      ; close all open file descriptors of this task (if any) to free file_pool resources
0x0000247C       POP R5

    ; Do not destroy the current task here: SP still points into its kernel
    ; stack. Mark it unrecoverable and let idle_task reclaim it later while
    ; running on a different stack.
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x00002480   LI R1 TASK_ZOMBIE
0x00002488   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000248C   LI R1 WAIT_NONE
0x00002494   STW R1 [R5 + TASK_WAIT]
0x00002498       B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x000024A0   LI R1 CURRENT_TASK
0x000024A8   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x000024AC   LI R1 TASK_SIZE
0x000024B4   MUL R3 R2 R1
0x000024B8   LI R5 tasks
0x000024C0   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x000024C4   LDW R1 [R5 + TASK_PID]

0x000024C8       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x000024CC       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x000024D4       LDW R1 [SP + TF_R1]
0x000024D8       STW R1 [SP + TF_R1]

0x000024DC       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x000024E4       LDW R1 [SP + TF_R1]
0x000024E8       LDW R2 [SP + TF_R2]

0x000024EC       MOV R12 R2               ; save flags

0x000024F0       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x000024F8       CMP R1 0
0x000024FC       BEQ open_fail_fault
    ; R1 - str pathname in kbuf_rd checking if this is device? in dev registry table(has /dev/....)
0x00002504       BL lookup_device
0x0000250C       CMP R1 0
0x00002510       BEQ open_try_tarfs   ; lookup in TARFS if R1=0 - fails to find device in device table

0x00002518       MOV R8 R1            ; save device descriptor

0x0000251C       BL file_alloc        ; out: R1 = pointer to FILE object in file_pool
0x00002524       CMP R1 0
0x00002528       BEQ open_fail_nfile
0x00002530       MOV R9 R1            ;

    ; initialize file object
0x00002534       MOV R1 R9                ; file*
0x00002538       MOV R2 R8                ; device*
0x0000253C       MOV R3 R12               ; flags
0x00002540       BL file_init             ; ([i].device*)->([i].file*), [i].seek=0, set [i].flags in file_pool

0x00002548       MOV R1 R9                ; initialised file ptr (ie file instance)
0x0000254C       BL fd_alloc              ; fd_table[new_fd] = file* (new_fd - idx in fd_table 4,5,6...)
0x00002554       LI  R2 ERR_MFILE
0x0000255C       CMP R1 R2
0x00002560       BEQ open_fail_fd

0x00002568       STW R1 [SP + TF_R1]

0x0000256C       B trap_restore

open_try_tarfs:
    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00002574   LI R1 CURRENT_TASK
0x0000257C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002580   LI R1 TASK_SIZE
0x00002588   MUL R3 R4 R1
0x0000258C   LI R5 tasks
0x00002594   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00002598   LDW R1 [R5 + TASK_KBUF_RD_PTR]
    ;check file in TARFS R1=pathname ptr
0x0000259C       BL tarfs_lookup
0x000025A4       CMP R1 0
0x000025A8       BEQ open_fail_noent

    ; TARFS is read-only and directories cannot be opened as byte streams.
    ; found pathname: R1 = tar_index entry
0x000025B0       MOV R8 R1
0x000025B4       AND R2 R12 FD_FLAG_WRITE
0x000025B8       CMP R2 0
0x000025BC       BNE open_fail_acces              ; RW - not

0x000025C4       LDW R2 [R8 + TAR_IDX_TYPE]
0x000025C8       LI R3 53                         ; ASCII '5' = directory
0x000025D0       CMP R2 R3
0x000025D4       BEQ open_fail_isdir              ; DIR - not

    ; do file in file_pool

0x000025DC       BL file_alloc
0x000025E4       CMP R1 0
0x000025E8       BEQ open_fail_nfile
0x000025F0       MOV R9 R1

0x000025F4       LI R2 tarfs_ops
0x000025FC       STW R2 [R9 + FILE_OPS]
0x00002600       STW R8 [R9 + FILE_PRIVATE]
0x00002604       LI R2 0
0x0000260C       STW R2 [R9 + FILE_OFFSET]
0x00002610       LI R2 FD_FLAG_READ
0x00002618       STW R2 [R9 + FILE_FLAGS]

0x0000261C       MOV R1 R9
0x00002620       BL fd_alloc
0x00002628       LI R2 ERR_MFILE
0x00002630       CMP R1 R2
0x00002634       BEQ open_fail_fd

0x0000263C       STW R1 [SP + TF_R1]             ;file opened if fd on exit!
0x00002640       B trap_restore

open_fail_acces:
0x00002648       LI R1 ERR_ACCES
0x00002650       STW R1 [SP + TF_R1]
0x00002654       B trap_restore

open_fail_isdir:
0x0000265C       LI R1 ERR_ISDIR
0x00002664       STW R1 [SP + TF_R1]
0x00002668       B trap_restore

open_fail_fd:
0x00002670       MOV R1 R9
0x00002674       BL file_free
0x0000267C       LI R1 ERR_MFILE
0x00002684       STW R1 [SP + TF_R1]

0x00002688       B trap_restore

open_fail_nfile:
0x00002690       LI R1 ERR_NFILE
0x00002698       STW R1 [SP + TF_R1]

0x0000269C       B trap_restore

open_fail_noent:
0x000026A4       LI R1 ERR_NOENT
0x000026AC       STW R1 [SP + TF_R1]

0x000026B0       B trap_restore

open_fail_fault:
0x000026B8       LI R1 ERR_FAULT
0x000026C0       STW R1 [SP + TF_R1]

0x000026C4       B trap_restore
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
0x000026CC       PUSH LR

0x000026D0       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x000026D4   LI R1 CURRENT_TASK
0x000026DC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000026E0   LI R1 TASK_SIZE
0x000026E8   MUL R3 R4 R1
0x000026EC   LI R5 tasks
0x000026F4   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x000026F8   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x000026FC       PUSH R9                    ; original destination returned on success
0x00002700       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00002708       LI R11 KBUFFER_SIZE
0x00002710       CMP R10 R11
0x00002714       BGE copy_path_fail

0x0000271C       PUSH R8
0x00002720       PUSH R9
0x00002724       PUSH R10
0x00002728       MOV R1 R8
0x0000272C       LI R2 1
0x00002734       LI R3 0                    ; read access from user source
0x0000273C       BL user_buffer_valid_range
0x00002744       POP R10
0x00002748       POP R9
0x0000274C       POP R8
0x00002750       CMP R1 1
0x00002754       BNE copy_path_fail

0x0000275C       LDB R4 [R8]
0x00002760       STB R4 [R9]
0x00002764       CMP R4 0
0x00002768       BEQ copy_path_done

0x00002770       ADD R8 R8 1
0x00002774       ADD R9 R9 1
0x00002778       ADD R10 R10 1
0x0000277C       B copy_path_loop

copy_path_done:
0x00002784       POP R1                     ; original kernel path pointer
0x00002788       POP LR
0x0000278C       RET

copy_path_fail:
0x00002790       POP R1                     ; discard original kernel path pointer
0x00002794       LI R1 0
0x0000279C       POP LR
0x000027A0       RET

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

0x000027A4       PUSH LR

0x000027A8       MOV R8 R1                  ; save pathname ptr

0x000027AC       LI R7 device_table
0x000027B4       LI R9 DEVICE_COUNT

lookup_loop:
0x000027BC       CMP R9 0
0x000027C0       BEQ lookup_fail

    ; compare pathname with device name

0x000027C8       MOV R1 R8
0x000027CC       LDW R2 [R7 + DEV_NAME]

0x000027D0       BL strcmp

0x000027D8       CMP R1 1
0x000027DC       BEQ lookup_found

0x000027E4       ADD R7 R7 DEV_SIZE
0x000027E8       SUB R9 R9 1
0x000027EC       B lookup_loop

lookup_found:

0x000027F4       MOV R1 R7                  ; return device descriptor ptr

0x000027F8       POP LR
0x000027FC       RET

lookup_fail:

0x00002800       LI R1 0

0x00002808       POP LR
0x0000280C       RET

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
0x00002810       LDB R3 [R1]
0x00002814       LDB R4 [R2]

0x00002818       CMP R3 R4
0x0000281C       BNE str_not_equal

0x00002824       CMP R3 0
0x00002828       BEQ str_equal

0x00002830       ADD R1 R1 1
0x00002834       ADD R2 R2 1
0x00002838       B str_loop

str_equal:
0x00002840       LI R1 1
0x00002848       RET

str_not_equal:
0x0000284C       LI R1 0
0x00002854       RET

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
0x00002858       PUSH R3
0x0000285C       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x00002860       LDB R3 [R2]            ; prefix char
0x00002864       CMP R3 0
0x00002868       BEQ sp_match           ; reached end of prefix?

0x00002870       LDB R4 [R1]            ; string char
0x00002874       CMP R4 R3
0x00002878       BNE sp_nomatch

0x00002880       ADD R1 R1 1
0x00002884       ADD R2 R2 1
0x00002888       B sp_loop
sp_match:
0x00002890       LI R1 1                 ;prefix ok
0x00002898       POP R4
0x0000289C       POP R3
0x000028A0       RET
sp_nomatch:
0x000028A4       LI R1 0                 ; not ok
0x000028AC       POP R4
0x000028B0       POP R3
0x000028B4       RET

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
0x000028B8       PUSH R3
0x000028BC       PUSH R4
sk_loop:
0x000028C0       LDB R3 [R2]            ; prefix char
0x000028C4       CMP R3 0
0x000028C8       BEQ sk_match           ; reached end of prefix
0x000028D0       LDB R4 [R1]            ; string char
0x000028D4       CMP R4 R3
0x000028D8       BNE sk_nomatch
0x000028E0       ADD R1 R1 1
0x000028E4       ADD R2 R2 1
0x000028E8       B sk_loop

sk_match:
    ; R1 already points past prefix
0x000028F0       POP R4
0x000028F4       POP R3
0x000028F8       RET

sk_nomatch:
0x000028FC       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x00002904       POP R4
0x00002908       POP R3
0x0000290C       RET

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
0x00002910       PUSH R2
0x00002914       PUSH R3
0x00002918       LI R2 0                ; length
pcl_loop:
0x00002920       LDB R3 [R1]
0x00002924       CMP R3 0
0x00002928       BEQ pcl_done
0x00002930       LI R4 47               ; '/'
0x00002938       CMP R3 R4
0x0000293C       BEQ pcl_done
0x00002944       ADD R2 R2 1
0x00002948       ADD R1 R1 1
0x0000294C       B pcl_loop
pcl_done:
0x00002954       MOV R1 R2
0x00002958       POP R3
0x0000295C       POP R2
0x00002960       RET

;====================================================================
; file_init
; in: R1 = file pointer
      ;R2 = device descriptor pointer in file_pool
      ;R3 = open flags
; out:file structure initialized
;====================================================================
file_init:

0x00002964       LDW R4 [R2 + DEV_OPS]
0x00002968       STW R4 [R1 + FILE_OPS]

0x0000296C       LDW R4 [R2 + DEV_PRIVATE]
0x00002970       STW R4 [R1 + FILE_PRIVATE]

0x00002974       LI R4 0
0x0000297C       STW R4 [R1 + FILE_OFFSET]

0x00002980       STW R3 [R1 + FILE_FLAGS]

0x00002984       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x00002988       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x0000298C   LI R1 CURRENT_TASK
0x00002994   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002998   LI R1 TASK_SIZE
0x000029A0   MUL R3 R4 R1
0x000029A4   LI R4 tasks
0x000029AC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x000029B0   LDW R4 [R4 + TASK_FD_TABLE]

0x000029B4       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x000029BC       CMP R5 MAX_FDS
0x000029C0       BGE fd_alloc_fail

0x000029C8       SHL R6 R5 2                ; fd * 4
0x000029CC       ADD R7 R4 R6               ; &fd_table[fd]

0x000029D0       LDW R2 [R7]
0x000029D4       CMP R2 0                   ; 0 - empty
0x000029D8       BEQ fd_alloc_found

0x000029E0       ADD R5 R5 1
0x000029E4       B fd_alloc_loop

fd_alloc_found:

0x000029EC       STW R8 [R7]                ; fd_table[fd] = file*

0x000029F0       MOV R1 R5                  ; return fd
0x000029F4       RET

fd_alloc_fail:

0x000029F8       LI R1 ERR_MFILE
0x00002A00       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x00002A04       LDW R1 [SP + TF_R1]

0x00002A08       BL fd_remove    ;in R1-fd out R1-file ptr for this fd

0x00002A10       CMP R1 0
0x00002A14       BEQ close_fail

0x00002A1C       BL file_free    ;in R1 file_ptr in file_pool it marks it as free (NULL)

0x00002A24       LI R1 0
0x00002A2C       STW R1 [SP + TF_R1]

0x00002A30       B trap_restore

close_fail:
0x00002A38       LI R1 ERR_BADF
0x00002A40       STW R1 [SP + TF_R1]

0x00002A44       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00002A4C       LDW R7 [SP + TF_R1]

0x00002A50       BL pipe_alloc
0x00002A58       CMP R1 0
0x00002A5C       BEQ pipe_fail_nospc

0x00002A64       MOV R8 R1            ; new slot in pipe_pool ( pipe* )

    ; [0] read end          write[1]>--pipe--->read[0]

0x00002A68       BL file_alloc
0x00002A70       CMP R1 0
0x00002A74       BEQ pipe_fail_pipe_only

0x00002A7C       MOV R9 R1           ; new file for read end  in file_pool

0x00002A80       LI R2 pipe_ops
0x00002A88       STW R2 [R9 + FILE_OPS]      ; store ops (for pipe of read end) in allocated  file struc

0x00002A8C       STW R8 [R9 + FILE_PRIVATE]  ; store our slot pipe* in file

0x00002A90       LI R2 FD_FLAG_READ
0x00002A98       STW R2 [R9 + FILE_FLAGS]    ; set file mode read

0x00002A9C       MOV R1 R9
0x00002AA0       BL fd_alloc                 ; insert read file to fd_table of user process

0x00002AA8       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002AB0       CMP R1 R2
0x00002AB4       BEQ pipe_fail_read_file

0x00002ABC       MOV R10 R1           ; get file read fd created to R10

    ; write end

0x00002AC0       BL file_alloc
0x00002AC8       CMP R1 0
0x00002ACC       BEQ pipe_fail_read_fd

0x00002AD4       MOV R9 R1

0x00002AD8       LI R2 pipe_ops
0x00002AE0       STW R2 [R9 + FILE_OPS]

0x00002AE4       STW R8 [R9 + FILE_PRIVATE]

0x00002AE8       LI R2 FD_FLAG_WRITE                 ;file mode -write
0x00002AF0       STW R2 [R9 + FILE_FLAGS]

0x00002AF4       MOV R1 R9
0x00002AF8       BL fd_alloc

0x00002B00       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002B08       CMP R1 R2
0x00002B0C       BEQ pipe_fail_write_file

0x00002B14       MOV R11 R1           ; R11 write fd R10 read fd

0x00002B18       MOV R1 R7   ; in &fd[2]
0x00002B1C       LI R2 8     ; len 2
0x00002B24       LI R3 1     ; mem perm to write cond
0x00002B2C       BL user_buffer_valid_range
0x00002B34       CMP R1 1
0x00002B38       BNE pipe_fail_both_fds

0x00002B40       STW R10 [R7]    ;fd[0]-rd fd[1]-wr
0x00002B44       STW R11 [R7 + 4]

0x00002B48       LI R1 0
0x00002B50       STW R1 [SP + TF_R1]

0x00002B54       B trap_restore

pipe_fail:
0x00002B5C       LI R1 ERR_IO
0x00002B64       STW R1 [SP + TF_R1]

0x00002B68       B trap_restore

pipe_fail_both_fds:
0x00002B70       MOV R12 R8
0x00002B74       MOV R1 R11
0x00002B78       BL fd_remove
0x00002B80       CMP R1 0
0x00002B84       BEQ pipe_fail_both_fds_read
0x00002B8C       BL file_free

pipe_fail_both_fds_read:
0x00002B94       MOV R1 R10
0x00002B98       BL fd_remove
0x00002BA0       CMP R1 0
0x00002BA4       BEQ pipe_fail_free_pipe_fault
0x00002BAC       BL file_free

pipe_fail_free_pipe_fault:
0x00002BB4       MOV R1 R12
0x00002BB8       BL pipe_free
0x00002BC0       LI R1 ERR_FAULT
0x00002BC8       STW R1 [SP + TF_R1]

0x00002BCC       B trap_restore

pipe_fail_write_file:
0x00002BD4       MOV R12 R8
0x00002BD8       MOV R1 R9
0x00002BDC       BL file_free
0x00002BE4       MOV R1 R10
0x00002BE8       BL fd_remove
0x00002BF0       CMP R1 0
0x00002BF4       BEQ pipe_fail_free_pipe_mfile
0x00002BFC       BL file_free

pipe_fail_free_pipe_mfile:
0x00002C04       MOV R1 R12
0x00002C08       BL pipe_free
0x00002C10       LI R1 ERR_MFILE
0x00002C18       STW R1 [SP + TF_R1]

0x00002C1C       B trap_restore

pipe_fail_read_fd:
0x00002C24       MOV R12 R8
0x00002C28       MOV R1 R10
0x00002C2C       BL fd_remove
0x00002C34       CMP R1 0
0x00002C38       BEQ pipe_fail_free_pipe_nfile
0x00002C40       BL file_free

pipe_fail_free_pipe_nfile:
0x00002C48       MOV R1 R12
0x00002C4C       BL pipe_free
0x00002C54       LI R1 ERR_NFILE
0x00002C5C       STW R1 [SP + TF_R1]

0x00002C60       B trap_restore

pipe_fail_read_file:
0x00002C68       MOV R12 R8
0x00002C6C       MOV R1 R9
0x00002C70       BL file_free
0x00002C78       MOV R1 R12
0x00002C7C       BL pipe_free
0x00002C84       LI R1 ERR_MFILE
0x00002C8C       STW R1 [SP + TF_R1]

0x00002C90       B trap_restore

pipe_fail_pipe_only:
0x00002C98       MOV R1 R8
0x00002C9C       BL pipe_free
0x00002CA4       LI R1 ERR_NFILE
0x00002CAC       STW R1 [SP + TF_R1]

0x00002CB0       B trap_restore

pipe_fail_nospc:
0x00002CB8       LI R1 ERR_NOSPC
0x00002CC0       STW R1 [SP + TF_R1]

0x00002CC4       B trap_restore

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

0x00002CCC       PUSH LR

0x00002CD0       MOV R9 R1              ; file*
0x00002CD4       MOV R7 R2              ; user buffer
0x00002CD8       MOV R6 R3              ; requested len
0x00002CDC       LDW R9 [R9 + FILE_PRIVATE]    ; our instance allocated in pipe_pool pipe*
0x00002CE0       CMP R6 0                ;fast clear from it if len=0
0x00002CE4       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00002CEC       PUSH R7
0x00002CF0       PUSH R6

0x00002CF4       MOV R1 R7
0x00002CF8       MOV R2 R6
0x00002CFC       LI  R3 1               ; write access
0x00002D04       BL user_buffer_valid_range

0x00002D0C       POP R6
0x00002D10       POP R7
0x00002D14       CMP R1 1
0x00002D18       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00002D20       LDW R4 [R9 + PIPE_COUNT]
0x00002D24       CMP R4 0
0x00002D28       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00002D30       CMP R6 R4
0x00002D34       BLT pipe_user_len

0x00002D3C       MOV R5 R4
0x00002D40       B pipe_have_amount

pipe_user_len:
0x00002D48       MOV R5 R6

pipe_have_amount:
0x00002D4C       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00002D54       CMP R10 R5
0x00002D58       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00002D60       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00002D64       MOV R12 R9
0x00002D68       ADD R12 R12 PIPE_BUFFER
0x00002D6C       ADD R12 R12 R11         ; addr += tail

0x00002D70       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00002D74       MOV R12 R7
0x00002D78       ADD R12 R12 R10

0x00002D7C       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x00002D80       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00002D84       LI R2 255
0x00002D8C       AND R11 R11 R2
0x00002D90       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00002D94       LDW R12 [R9 + PIPE_COUNT]
0x00002D98       SUB R12 R12 1
0x00002D9C       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00002DA0       ADD R10 R10 1
0x00002DA4       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00002DAC       MOV R1 R9
0x00002DB0       ADD R1 R1 PIPE_WWAIT
0x00002DB4       BL waitq_wake_all
0x00002DBC       MOV R1 R10          ; read bytes amount
0x00002DC0       POP LR
0x00002DC4       RET

pipe_read_badptr:
0x00002DC8       LI R1 ERR_FAULT
0x00002DD0       POP LR
0x00002DD4       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00002DD8       MOV R1 R9
0x00002DDC       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00002DE0       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00002DE8       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00002DF0       LDW R4 [R9 + PIPE_COUNT]
0x00002DF4       CMP R4 0
0x00002DF8       BNE pipe_read_retry

0x00002E00       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00002E08       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00002E10       LI R2 0

pipe_loop:
0x00002E18       LI  R1 MAX_PIPES
0x00002E20       CMP R2 R1
0x00002E24       BGE pipe_alloc_fail

0x00002E2C       SHL R3 R2 2

0x00002E30       LI R4 pipe_used
0x00002E38       ADD R4 R4 R3

0x00002E3C       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00002E40       CMP R5 0                ; 0 -empty
0x00002E44       BEQ pipe_found

0x00002E4C       ADD R2 R2 1
0x00002E50       B pipe_loop

pipe_found:

0x00002E58       LI R5 1
0x00002E60       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00002E64       LI R4 PIPE_SIZE
0x00002E6C       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00002E70       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00002E78       ADD R1 R1 R6

0x00002E7C       LI R7 0                 ; clean it up
0x00002E84       STW R7 [R1 + PIPE_HEAD]
0x00002E88       STW R7 [R1 + PIPE_TAIL]
0x00002E8C       STW R7 [R1 + PIPE_COUNT]
0x00002E90       STW R7 [R1 + PIPE_RWAIT]
0x00002E94       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00002E98       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00002E9C       LI R1 0
0x00002EA4       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00002EA8       LI R2 pipe_pool
0x00002EB0       SUB R3 R1 R2

0x00002EB4       LI R4 PIPE_SIZE
0x00002EBC       DIV R5 R3 R4

0x00002EC0       SHL R5 R5 2
0x00002EC4       LI R6 pipe_used
0x00002ECC       ADD R6 R6 R5

0x00002ED0       LI R7 0
0x00002ED8       STW R7 [R6]

0x00002EDC       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00002EE0       PUSH LR

0x00002EE4       MOV R8 R1
0x00002EE8       MOV R7 R2
0x00002EEC       MOV R6 R3

0x00002EF0       LDW R9 [R8 + FILE_PRIVATE]

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00002EF4       PUSH R7
0x00002EF8       PUSH R6

0x00002EFC       MOV R1 R7
0x00002F00       MOV R2 R6
0x00002F04       LI  R3 0           ; READ access
0x00002F0C       BL user_buffer_valid_range

0x00002F14       POP R6
0x00002F18       POP R7

0x00002F1C       CMP R1 1
0x00002F20       BNE pipe_write_badptr

0x00002F28       LI R10 0               ; bytes written
pipe_write_retry:
0x00002F30       CMP R10 R6
0x00002F34       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00002F3C       LDW R11 [R9 + PIPE_COUNT]
0x00002F40       LI R2 256
0x00002F48       CMP R11 R2
0x00002F4C       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00002F54       LDW R12 [R9 + PIPE_HEAD]

0x00002F58       MOV R4 R7
0x00002F5C       ADD R4 R4 R10
0x00002F60       LDB R5 [R4]     ; read byte from user buff addr

0x00002F64       MOV R4 R9
0x00002F68       ADD R4 R4 PIPE_BUFFER
0x00002F6C       ADD R4 R4 R12
0x00002F70       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00002F74       ADD R12 R12 1
0x00002F78       LI R2 255
0x00002F80       AND R12 R12 R2
0x00002F84       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00002F88       LDW R4 [R9 + PIPE_COUNT]
0x00002F8C       ADD R4 R4 1
0x00002F90       STW R4 [R9 + PIPE_COUNT]

; written++
0x00002F94       ADD R10 R10 1
0x00002F98       B pipe_write_retry

pipe_write_done:
; wake readers
0x00002FA0       MOV R1 R9
0x00002FA4       ADD R1 R1 PIPE_RWAIT
0x00002FA8       BL waitq_wake_all
0x00002FB0       MOV R1 R10      ;written bytes
0x00002FB4       POP LR
0x00002FB8       RET

pipe_write_badptr:
0x00002FBC       LI R1 ERR_FAULT
0x00002FC4       POP LR
0x00002FC8       RET

pipe_write_empty:
0x00002FCC       LI R1 0
0x00002FD4       POP LR
0x00002FD8       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00002FDC       MOV R1 R9
0x00002FE0       ADD R1 R1 PIPE_WWAIT
0x00002FE4       LI R2 WAIT_PIPE_WRITE
0x00002FEC       BL waitq_prepare_sleep
    ; race check
0x00002FF4       LDW R4 [R9 + PIPE_COUNT]
0x00002FF8       LI R2 256
0x00003000       CMP R4 R2
0x00003004       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x0000300C       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00003014       B pipe_write_retry      ; unblocked! go write!

fd_remove:
 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
0x0000301C       CMP R1 3
0x00003020       BLT fd_remove_invalid       ; fd 0-1-2 are stdio, not closeable by user

0x00003028       CMP R1 MAX_FDS
0x0000302C       BGE fd_remove_invalid       ; fd is out of bounds

0x00003034       MOV R8 R1

; macro: GET_CURR_TASK_IDX R4
0x00003038   LI R1 CURRENT_TASK
0x00003040   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00003044   LI R1 TASK_SIZE
0x0000304C   MUL R3 R4 R1
0x00003050   LI R4 tasks
0x00003058   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = fd table ptr of current task
0x0000305C   LDW R4 [R4 + TASK_FD_TABLE]

0x00003060       SHL R5 R8 2
0x00003064       ADD R6 R4 R5                ; &fd_table[fd]

0x00003068       LDW R1 [R6]
0x0000306C       CMP R1 0
0x00003070       BEQ fd_remove_invalid       ; if fd_table[fd] is null, invalid fd

0x00003078       LI R7 0
0x00003080       STW R7 [R6]                 ; fd_table[fd] = null

0x00003084       RET                     ; return file* in R1 for file_free

fd_remove_invalid:
0x00003088       LI R1 0
0x00003090       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003094       LDW R1 [SP + TF_R1]
0x00003098       LDW R2 [SP + TF_R2]
0x0000309C       LDW R3 [SP + TF_R3]

0x000030A0       MOV R7 R2               ; save user buffer
0x000030A4       MOV R6 R3               ; save length
0x000030A8       PUSH R7
0x000030AC       PUSH R6
0x000030B0       LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
0x000030B8       BL fetch_fd_entry
0x000030C0       POP R6
0x000030C4       POP R7
0x000030C8       CMP R1 0
0x000030CC       BEQ bad_fd
0x000030D4       MOV R9 R1               ; file object pointer
0x000030D8       MOV R1 R9
0x000030DC       MOV R2 R7
0x000030E0       MOV R3 R6
0x000030E4       BL file_read
0x000030EC       STW R1 [SP + TF_R1]

0x000030F0       B trap_restore

con_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x000030F8       PUSH LR
0x000030FC       PUSH R8
0x00003100       PUSH R9
0x00003104       PUSH R10
0x00003108       PUSH R11
0x0000310C       PUSH R12
0x00003110       MOV R9 R1
0x00003114       MOV R7 R2
0x00003118       MOV R6 R3
0x0000311C       LI R8 0                    ; total bytes collected
0x00003124       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x00003128       CMP R6 0
0x0000312C       BEQ read_done

0x00003134       PUSH R7
0x00003138       PUSH R6
0x0000313C       PUSH R9
0x00003140       MOV R1 R7
0x00003144       MOV R2 R6
0x00003148       LI R3 1                ; write access for destination buffer
0x00003150       BL user_buffer_valid_range
0x00003158       POP R9
0x0000315C       POP R6
0x00003160       POP R7
0x00003164       CMP R1 1
0x00003168       BNE con_read_fault

read_wait_uart_rx:
0x00003170       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003174       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00003178       AND R5 R5 1                 ; bit 0 = RX_READY
0x0000317C       CMP R5 0
0x00003180       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00003188   LI R1 CURRENT_TASK
0x00003190   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003194   LI R1 TASK_SIZE
0x0000319C   MUL R3 R4 R1
0x000031A0   LI R5 tasks
0x000031A8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x000031AC   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x000031B0       MOV R2 R6
0x000031B4       MOV R3 R9
0x000031B8       PUSH R6
0x000031BC       PUSH R7
0x000031C0       PUSH R8
0x000031C4       PUSH R9
0x000031C8       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x000031D0       POP R9
0x000031D4       POP R8
0x000031D8       POP R7
0x000031DC       POP R6

0x000031E0       CMP R1 0
0x000031E4       BEQ read_wait_uart_rx

0x000031EC       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x000031F0   LI R1 CURRENT_TASK
0x000031F8   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x000031FC   LI R1 TASK_SIZE
0x00003204   MUL R3 R5 R1
0x00003208   LI R4 tasks
0x00003210   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x00003214   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with newline before copy_to_user
    ; clobbers temporary registers.
0x00003218       LI R11 0
0x00003220       SUB R5 R10 1
0x00003224       ADD R5 R4 R5
0x00003228       LDB R5 [R5]
0x0000322C       CMP R5 10
0x00003230       BNE read_chunk_not_newline
0x00003238       LI R11 1

read_chunk_not_newline:
0x00003240       PUSH R6
0x00003244       PUSH R7
0x00003248       PUSH R8
0x0000324C       PUSH R9
0x00003250       PUSH R10
0x00003254       PUSH R11
0x00003258       MOV R1 R7              ; user destination
0x0000325C       MOV R2 R10
0x00003260       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00003268       POP R11
0x0000326C       POP R10
0x00003270       POP R9
0x00003274       POP R8
0x00003278       POP R7
0x0000327C       POP R6

0x00003280       ADD R7 R7 R10
0x00003284       ADD R8 R8 R10
0x00003288       SUB R6 R6 R10

0x0000328C       CMP R11 1
0x00003290       BEQ read_complete
0x00003298       CMP R6 0
0x0000329C       BGT read_wait_uart_rx

read_complete:
0x000032A4       MOV R1 R8
0x000032A8       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x000032B0       LI R1 uart_rx_waitq
0x000032B8       LI R2 WAIT_UART_RX
0x000032C0       BL waitq_prepare_sleep

0x000032C8       LDW R4 [R9 + UARTDEV_MMIO]
0x000032CC       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x000032D0       AND R10 R10 1
0x000032D4       CMP R10 0
0x000032D8       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x000032E0       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x000032E8       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x000032F0       LI R1 uart_rx_waitq
0x000032F8       BL waitq_cancel_sleep_current

0x00003300       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x00003308       LI R1 0
0x00003310       B read_return

con_read_fault:
0x00003318       LI R1 ERR_FAULT

read_return:
0x00003320       POP R12
0x00003324       POP R11
0x00003328       POP R10
0x0000332C       POP R9
0x00003330       POP R8
0x00003334       POP LR
0x00003338       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x0000333C       LDW R1 [SP + TF_R1]
0x00003340       LDW R2 [SP + TF_R2]
0x00003344       LDW R3 [SP + TF_R3]
; first fetch file from procs fd_table and check flags for match access WRITE /READ
0x00003348       MOV R7 R2               ; save user buffer
0x0000334C       MOV R6 R3               ; save length
0x00003350       PUSH R7
0x00003354       PUSH R6
0x00003358       LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
0x00003360       BL fetch_fd_entry       ;input R1 fd on exit R1 - file ptr  => r1=fetch_fd_entry(fd=r1)
0x00003368       POP R6
0x0000336C       POP R7
0x00003370       CMP R1 0
0x00003374       BEQ bad_fd              ;if flags file and in r2 dont match
0x0000337C       MOV R9 R1               ; file object pointer
0x00003380       MOV R1 R9
0x00003384       MOV R2 R7
0x00003388       MOV R3 R6
0x0000338C       BL file_write           ; call file write R1 = file ptr, R2 = user buffer, R3 = len
0x00003394       STW R1 [SP + TF_R1]

0x00003398       B trap_restore

con_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x000033A0       PUSH LR
0x000033A4       MOV R9 R1
0x000033A8       MOV R7 R2
0x000033AC       MOV R6 R3
0x000033B0       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x000033B4       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x000033BC       CMP R6 0
0x000033C0       BEQ write_done             ;0 bytes

0x000033C8       LI R2 KBUFFER_SIZE
0x000033D0       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x000033D4       BLT write_chunk_small
0x000033DC       LI R2 KBUFFER_SIZE

0x000033E4       B write_chunk

write_chunk_small:
0x000033EC       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x000033F0       PUSH R7
0x000033F4       PUSH R6
0x000033F8       PUSH R9
0x000033FC       PUSH R8
0x00003400       MOV R1 R7
0x00003404       MOV R2 R2
0x00003408       LI R3 0                ; read access for source buffer
0x00003410       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00003418       POP R8
0x0000341C       POP R9
0x00003420       POP R6
0x00003424       POP R7
0x00003428       CMP R1 1
0x0000342C       BNE driver_bad_pointer

0x00003434       PUSH R7
0x00003438       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x0000343C   LI R1 CURRENT_TASK
0x00003444   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003448   LI R1 TASK_SIZE
0x00003450   MUL R3 R4 R1
0x00003454   LI R5 tasks
0x0000345C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00003460   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00003464       MOV R1 R7
0x00003468       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00003470       MOV R10 R1             ; bytes copied
0x00003474       POP R6
0x00003478       POP R7

0x0000347C       PUSH R7
0x00003480       PUSH R9
0x00003484       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x00003488       LDW R1 [R9 + UARTDEV_MMIO]
0x0000348C       LDW R2 [R1 + 4]
0x00003490       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00003494       CMP R2 0
0x00003498       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x000034A0   LI R1 CURRENT_TASK
0x000034A8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000034AC   LI R1 TASK_SIZE
0x000034B4   MUL R3 R4 R1
0x000034B8   LI R5 tasks
0x000034C0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x000034C4   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x000034C8       MOV R2 R10
0x000034CC       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x000034D0       BL device_write
0x000034D8       POP R6
0x000034DC       POP R9
0x000034E0       POP R7

0x000034E4       CMP R1 0        ;nothing is written - go again
0x000034E8       BEQ write_loop

0x000034F0       ADD R8 R8 R1     ;update ptrs
0x000034F4       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x000034F8       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x000034FC       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00003504       LI R1 uart_tx_waitq
0x0000350C       LI R2 WAIT_UART_TX
0x00003514       BL waitq_prepare_sleep

0x0000351C       LDW R1 [R9 + UARTDEV_MMIO]
0x00003520       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00003524       AND R2 R2 2
0x00003528       CMP R2 0
0x0000352C       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00003534       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x0000353C       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00003544       LI R1 uart_tx_waitq
0x0000354C       BL waitq_cancel_sleep_current

0x00003554       B write_wait_uart_tx

write_done:
0x0000355C       MOV R1 R8
0x00003560       POP LR
0x00003564       RET

driver_bad_pointer:
0x00003568       LI R1 ERR_FAULT
0x00003570       POP LR
0x00003574       RET

bad_fd:
0x00003578       LI R1 ERR_BADF
0x00003580       STW R1 [SP + TF_R1]

0x00003584       B trap_restore

bad_pointer:
0x0000358C       LI R1 ERR_FAULT
0x00003594       STW R1 [SP + TF_R1]

0x00003598       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x000035A0       LDW R4 [R1 + FILE_OPS]
0x000035A4       LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
0x000035A8       JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x000035AC       LDW R4 [R1 + FILE_OPS]
0x000035B0       LDW R4 [R4 + FOPS_WRITE]    ; get write function xdev_write from ops
0x000035B4       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000035B8       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000035C0       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x000035C8       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000035CC       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x000035D4       CMP R5 R2                   ; have we read enough bytes?
0x000035D8       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x000035E0       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000035E4       AND R6 R6 1                 ; bit 0 = RX_READY
0x000035E8       CMP R6 0
0x000035EC       BEQ dr_done                 ; no more buffered input available

0x000035F4       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x000035F8       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x000035FC       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x00003600       CMP R7 10
0x00003604       BEQ dr_done

0x0000360C       B dr_loop

dr_done:
0x00003614       MOV R1 R5                   ; return number of bytes actually read
0x00003618       RET

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

0x0000361C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003620       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x00003628       CMP R5 R2                   ; have we written all bytes?
0x0000362C       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00003634       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00003638       AND R6 R6 2                 ; bit 1 = TX_READY
0x0000363C       CMP R6 0
0x00003640       BEQ dcw_done

0x00003648       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x0000364C       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00003650       ADD R5 R5 1
0x00003654       B dcw_loop

dcw_done:
0x0000365C       MOV R1 R5                   ; return number of bytes written
0x00003660       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00003664       LI R1 0
0x0000366C       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00003670       PUSH LR
0x00003674       MOV R6 R3
0x00003678       CMP R6 0
0x0000367C       BEQ null_write_done

0x00003684       PUSH R6
0x00003688       MOV R1 R2
0x0000368C       MOV R2 R6
0x00003690       LI R3 0                    ; read access from user source
0x00003698       BL user_buffer_valid_range
0x000036A0       POP R6
0x000036A4       CMP R1 1
0x000036A8       BNE null_write_badptr

null_write_done:
0x000036B0       MOV R1 R6
0x000036B4       POP LR
0x000036B8       RET

null_write_badptr:
0x000036BC       LI R1 ERR_FAULT
0x000036C4       POP LR
0x000036C8       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, 3)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

0x000036CC       CMP R1 0
0x000036D0       BLT fd_invalid
0x000036D8       CMP R1 MAX_FDS
0x000036DC       BGE fd_invalid

0x000036E4       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x000036E8   LI R1 CURRENT_TASK
0x000036F0   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000036F4   LI R1 TASK_SIZE
0x000036FC   MUL R3 R4 R1
0x00003700   LI R4 tasks
0x00003708   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x0000370C   LDW R4 [R4 + TASK_FD_TABLE]

0x00003710       SHL R5 R8 2
0x00003714       ADD R4 R4 R5                ;r4=fd*4+FD_TABLE = file entry according to fd
0x00003718       LDW R1 [R4]                 ; R1 = file ptr
0x0000371C       LDW R6 [R1 + FILE_FLAGS]
0x00003720       AND R6 R6 R2
0x00003724       CMP R6 R2                   ;check file flags R2 input R6 from file
0x00003728       BNE fd_invalid

0x00003730       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x00003734       LI R1 0
0x0000373C       RET

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
0x00003740       PUSH R10
0x00003744       PUSH R11
0x00003748       PUSH R12

0x0000374C       LI R4 0
0x00003754       CMP R2 R4
0x00003758       BEQ uv_valid

0x00003760       LI R4 USER_BASE
0x00003768       CMP R1 R4
0x0000376C       BLT uv_invalid

0x00003774       LI R4 USER_LIMIT
0x0000377C       ADD R5 R1 R2
0x00003780       SUB R5 R5 1
0x00003784       CMP R5 R1
0x00003788       BLT uv_invalid
0x00003790       CMP R5 R4
0x00003794       BGT uv_invalid
0x0000379C       MOV R11 R1              ; save start address; task macros clobber R1
0x000037A0       MOV R12 R5              ; save end address for page calculation
0x000037A4       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x000037A8   LI R1 CURRENT_TASK
0x000037B0   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x000037B4   LI R1 TASK_SIZE
0x000037BC   MUL R3 R6 R1
0x000037C0   LI R6 tasks
0x000037C8   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x000037CC   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x000037D0       CMP R6 0
0x000037D4       BEQ uv_invalid

uv_check_pages:
0x000037DC       SHR R7 R11 12
0x000037E0       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x000037E4       CMP R7 R8
0x000037E8       BGT uv_valid
0x000037F0       SHL R9 R7 2
0x000037F4       ADD R9 R9 R6
0x000037F8       LDW R10 [R9]
0x000037FC       AND R5 R10 PTE_P
0x00003800       CMP R5 0
0x00003804       BEQ uv_invalid
0x0000380C       AND R5 R10 PTE_U
0x00003810       CMP R5 0
0x00003814       BEQ uv_invalid
0x0000381C       CMP R4 0
0x00003820       BEQ uv_check_read
0x00003828       AND R5 R10 PTE_W
0x0000382C       CMP R5 0
0x00003830       BEQ uv_invalid
0x00003838       B uv_next

uv_check_read:
0x00003840       AND R5 R10 PTE_R
0x00003844       CMP R5 0
0x00003848       BEQ uv_invalid

uv_next:
0x00003850       ADD R7 R7 1
0x00003854       B uv_loop

uv_valid:
0x0000385C       LI R1 1
0x00003864       POP R12
0x00003868       POP R11
0x0000386C       POP R10
0x00003870       RET

uv_invalid:
0x00003874       LI R1 0

0x0000387C       POP R12
0x00003880       POP R11
0x00003884       POP R10
0x00003888       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x0000388C       LI R5 0
cfu_head:
0x00003894       CMP R2 0
0x00003898       BEQ cfu_done
0x000038A0       OR R6 R1 R4
0x000038A4       AND R6 R6 3
0x000038A8       CMP R6 0
0x000038AC       BEQ cfu_word
0x000038B4       LDB R7 [R1]
0x000038B8       STB R7 [R4]
0x000038BC       ADD R1 R1 1
0x000038C0       ADD R4 R4 1
0x000038C4       ADD R5 R5 1
0x000038C8       SUB R2 R2 1
0x000038CC       B cfu_head
cfu_word:
0x000038D4       CMP R2 4
0x000038D8       BLT cfu_tail
0x000038E0       LDW R7 [R1]
0x000038E4       STW R7 [R4]
0x000038E8       ADD R1 R1 4
0x000038EC       ADD R4 R4 4
0x000038F0       ADD R5 R5 4
0x000038F4       SUB R2 R2 4
0x000038F8       B cfu_word
cfu_tail:
0x00003900       CMP R2 0
0x00003904       BEQ cfu_done
0x0000390C       LDB R7 [R1]
0x00003910       STB R7 [R4]
0x00003914       ADD R1 R1 1
0x00003918       ADD R4 R4 1
0x0000391C       ADD R5 R5 1
0x00003920       SUB R2 R2 1
0x00003924       B cfu_tail
cfu_done:
0x0000392C       MOV R1 R5
0x00003930       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003934       LI R5 0
ctu_head:
0x0000393C       CMP R2 0
0x00003940       BEQ ctu_done
0x00003948       OR R6 R1 R4
0x0000394C       AND R6 R6 3
0x00003950       CMP R6 0
0x00003954       BEQ ctu_word
0x0000395C       LDB R7 [R4]
0x00003960       STB R7 [R1]
0x00003964       ADD R1 R1 1
0x00003968       ADD R4 R4 1
0x0000396C       ADD R5 R5 1
0x00003970       SUB R2 R2 1
0x00003974       B ctu_head
ctu_word:
0x0000397C       CMP R2 4
0x00003980       BLT ctu_tail
0x00003988       LDW R7 [R4]
0x0000398C       STW R7 [R1]
0x00003990       ADD R1 R1 4
0x00003994       ADD R4 R4 4
0x00003998       ADD R5 R5 4
0x0000399C       SUB R2 R2 4
0x000039A0       B ctu_word
ctu_tail:
0x000039A8       CMP R2 0
0x000039AC       BEQ ctu_done
0x000039B4       LDB R7 [R4]
0x000039B8       STB R7 [R1]
0x000039BC       ADD R1 R1 1
0x000039C0       ADD R4 R4 1
0x000039C4       ADD R5 R5 1
0x000039C8       SUB R2 R2 1
0x000039CC       B ctu_tail
ctu_done:
0x000039D4       MOV R1 R5
0x000039D8       RET

handle_debug:
    ; Debug trap - just return
0x000039DC       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x000039E4       CSRR R1 STVAL

0x000039E8       CMP R1 0
0x000039EC       BEQ handle_timer_irq

0x000039F4       CMP R1 1
0x000039F8       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00003A00       LI R2 0x00102000
0x00003A08       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x00003A0C       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00003A14       LI R2 0x00102000
0x00003A1C       LI R3 0
0x00003A24       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Yield the CPU (reschedule and switch tasks)
0x00003A28       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00003A30       LI R2 0x00102000
0x00003A38       LI R3 1
0x00003A40       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00003A44       LI R1 uart_rx_waitq
0x00003A4C       BL waitq_wake_all
0x00003A54       LI R1 uart_tx_waitq
0x00003A5C       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00003A64       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00003A6C       POP R1                  ; stval, informational only
0x00003A70       POP R1                  ; scause, informational only
0x00003A74       POP R1
0x00003A78       CSRW SSTATUS R1
0x00003A7C       POP R1
0x00003A80       CSRW SFLAGS R1
0x00003A84       POP R1
0x00003A88       CSRW SEPC R1
0x00003A8C       POP R1                  ; interrupted task SP
0x00003A90       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00003A94       POP R15
0x00003A98       POP R14
0x00003A9C       POP R12
0x00003AA0       POP R11
0x00003AA4       POP R10
0x00003AA8       POP R9
0x00003AAC       POP R8
0x00003AB0       POP R7
0x00003AB4       POP R6
0x00003AB8       POP R5
0x00003ABC       POP R4
0x00003AC0       POP R3
0x00003AC4       POP R2
0x00003AC8       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00003ACC       CSRRW SP SSCRATCH SP
0x00003AD0       SRET


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

0x00007EE6       PUSH LR
0x00007EEA       PUSH R8
0x00007EEE       PUSH R9
0x00007EF2       PUSH R10

0x00007EF6       LI R8 0

0x00007EFE       LI R10 tar_count
0x00007F06       LDW R10 [R10]

0x00007F0A       LI R1 tarfs_banner
0x00007F12       BL kputs

dump_loop:

0x00007F1A       CMP R8 R10
0x00007F1E       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00007F26       LI R1 tar_index

0x00007F2E       LI R2 TAR_IDX_SIZEOF
0x00007F36       MUL R3 R8 R2

0x00007F3A       ADD R9 R1 R3

    ; filename

0x00007F3E       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x00007F42       MOV R1 R2
0x00007F46       BL kputs

    ; newline

0x00007F4E       LI R1 newline
0x00007F56       BL kputs

0x00007F5E       ADD R8 R8 1
0x00007F62       B dump_loop

dump_done:

0x00007F6A       POP R10
0x00007F6E       POP R9
0x00007F72       POP R8
0x00007F76       POP LR
0x00007F7A       RET

;==============================================================
; TARFS file operations
;==============================================================

tarfs_ops:
    .WORD tarfs_read
    .WORD tarfs_write

;==============================================================
; TARFS tarfs_read:
; R1=file*, R2=user destination, R3=requested length
;==============================================================

tarfs_read:

0x00007F86       PUSH LR
0x00007F8A       PUSH R8
0x00007F8E       PUSH R9
0x00007F92       PUSH R10
0x00007F96       PUSH R11
0x00007F9A       PUSH R12

0x00007F9E       MOV R8 R1
0x00007FA2       MOV R9 R2
0x00007FA6       MOV R10 R3

0x00007FAA       CMP R10 0
0x00007FAE       BEQ tarfs_read_eof

0x00007FB6       PUSH R8
0x00007FBA       PUSH R9
0x00007FBE       MOV R1 R9
0x00007FC2       MOV R2 R10
0x00007FC6       LI R3 1                    ; destination must be user-writable
0x00007FCE       BL user_buffer_valid_range
0x00007FD6       POP R9
0x00007FDA       POP R8
0x00007FDE       CMP R1 1
0x00007FE2       BNE tarfs_read_fault

0x00007FEA       LDW R11 [R8 + FILE_PRIVATE]
0x00007FEE       LDW R12 [R8 + FILE_OFFSET]
0x00007FF2       LDW R4 [R11 + TAR_IDX_SIZE]

0x00007FF6       CMP R12 R4
0x00007FFA       BGEU tarfs_read_eof

0x00008002       SUB R4 R4 R12             ; bytes remaining
0x00008006       CMP R10 R4
0x0000800A       BLEU tarfs_read_count_ready
0x00008012       MOV R10 R4

tarfs_read_count_ready:
0x00008016       LDW R4 [R11 + TAR_IDX_DATA]
0x0000801A       ADD R4 R4 R12             ; kernel source
0x0000801E       MOV R1 R9                 ; user destination
0x00008022       MOV R2 R10
0x00008026       BL copy_to_user

0x0000802E       ADD R12 R12 R1
0x00008032       STW R12 [R8 + FILE_OFFSET]
0x00008036       B tarfs_read_done

tarfs_read_fault:
0x0000803E       LI R1 ERR_FAULT
0x00008046       B tarfs_read_done

tarfs_read_eof:
0x0000804E       LI R1 0

tarfs_read_done:
0x00008056       POP R12
0x0000805A       POP R11
0x0000805E       POP R10
0x00008062       POP R9
0x00008066       POP R8
0x0000806A       POP LR
0x0000806E       RET

tarfs_write:
0x00008072       LI R1 ERR_ACCES
0x0000807A       RET
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

0x0000807E       PUSH LR
0x00008082       PUSH R8
0x00008086       PUSH R9
0x0000808A       PUSH R10
0x0000808E       PUSH R11

0x00008092       MOV R8 R1              ; save directory path
0x00008096       LI R9 0                ; index

0x0000809E       LI R10 tar_count
0x000080A6       LDW R10 [R10]
tr_loop:
0x000080AA       CMP R9 R10
0x000080AE       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x000080B6       LI R1 tar_index
0x000080BE       LI R2 TAR_IDX_SIZEOF
0x000080C6       MUL R3 R9 R2
0x000080CA       ADD R11 R1 R3
    ; entry name
0x000080CE       LDW R1 [R11 + TAR_IDX_NAME]
0x000080D2       MOV R2 R8                       ; src dirname "etc/"
0x000080D6       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000080DE       CMP R1 1
0x000080E2       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x000080EA       LDW R1 [R11 + TAR_IDX_NAME]
0x000080EE       MOV R2 R8                       ; prefix
0x000080F2       BL skip_prefix                  ; omit prefix nd print just filename

0x000080FA       MOV R12 R1         ; save component ptr
0x000080FE       BL path_component_len ; out R1-length
0x00008106       MOV R2 R1
0x0000810A       MOV R1 R12
0x0000810E       BL kputsn   ; r1-ptr r2-len of string

0x00008116       LI R1 newline
0x0000811E       BL kputs

tr_next:
0x00008126       ADD R9 R9 1                     ;to next entry for check
0x0000812A       B tr_loop
tr_done:
0x00008132       POP R11
0x00008136       POP R10
0x0000813A       POP R9
0x0000813E       POP R8
0x00008142       POP LR
0x00008146       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x0000814A       PUSH LR
0x0000814E       PUSH R8
0x00008152       MOV R8 R1

kputs_loop:
0x00008156       LDB R1 [R8]

0x0000815A       CMP R1 0
0x0000815E       BEQ kputs_done

0x00008166       BL uart_putc

0x0000816E       ADD R8 R8 1

0x00008172       B kputs_loop

kputs_done:
0x0000817A       POP R8
0x0000817E       POP LR
0x00008182       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x00008186       PUSH LR
0x0000818A       PUSH R8
0x0000818E       PUSH R9
0x00008192       MOV R8 R1
0x00008196       MOV R9 R2
kputsn_loop:
0x0000819A       CMP R9 0
0x0000819E       BEQ kputsn_done
0x000081A6       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x000081AA       BL uart_putc
0x000081B2       ADD R8 R8 1
0x000081B6       SUB R9 R9 1
0x000081BA       B kputsn_loop
kputsn_done:
0x000081C2       POP R9
0x000081C6       POP R8
0x000081CA       POP LR
0x000081CE       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x000081D2       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x000081DA       LDW R2 [R3 + 4]   ; read UART status register
0x000081DE       AND R2 R2 2       ; check if TX ready (bit 1)
0x000081E2       CMP R2 0
0x000081E6       BEQ poll

0x000081EE       STW R1 [R3 + 0]   ; R1 is the character value
0x000081F2       RET



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

0x000081F6       PUSH R9
0x000081FA       PUSH R10

0x000081FE       MOV R9 R1                  ; preserve wait queue pointer
0x00008202       MOV R10 R2                 ; preserve debug wait reason

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x00008206   LI R1 CURRENT_TASK
0x0000820E   LDW R2 [R1]

0x00008212       LI R4 1
0x0000821A       SHL R4 R4 R2               ; R4 = bit for current task
0x0000821E       LDW R5 [R9 + WQ_MASK]
0x00008222       OR R5 R5 R4
0x00008226       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x0000822A   LI R1 TASK_SIZE
0x00008232   MUL R3 R2 R1
0x00008236   LI R5 tasks
0x0000823E   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00008242   LI R1 TASK_BLOCKED_IO
0x0000824A   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x0000824E   STW R10 [R5 + TASK_WAIT]

0x00008252       POP R10
0x00008256       POP R9
0x0000825A       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x0000825E       PUSH R9

0x00008262       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00008266   LI R1 CURRENT_TASK
0x0000826E   LDW R2 [R1]

0x00008272       LDW R4 [R9 + WQ_MASK]

0x00008276       LI  R5 1
0x0000827E       SHL R5 R5 R2        ;shift to position of current task bit

0x00008282       NOT R5 R5           ; invert to get mask for clearing this bit

0x00008286       AND R4 R4 R5        ; clear current task bit

0x0000828A       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x0000828E   LI R1 TASK_SIZE
0x00008296   MUL R3 R2 R1
0x0000829A   LI R5 tasks
0x000082A2   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x000082A6   LI R1 TASK_READY
0x000082AE   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x000082B2   LI R1 WAIT_NONE
0x000082BA   STW R1 [R5 + TASK_WAIT]

0x000082BE       POP R9
0x000082C2       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000082C6       PUSH LR
0x000082CA       BL schedule_call
0x000082D2       POP LR
0x000082D6       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x000082DA       PUSH LR

0x000082DE       MOV R9 R1
0x000082E2       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x000082E6       LI R10 0
0x000082EE       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x000082F2       LI R2 0                    ; task index

wq_wake_loop:
0x000082FA       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x000082FE       BGE wq_wake_done

0x00008306       LI R3 1
0x0000830E       SHL R3 R3 R2               ; R3 = bit for task R2
0x00008312       AND R4 R8 R3
0x00008316       CMP R4 0
0x0000831A       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00008322   LI R1 TASK_SIZE
0x0000832A   MUL R3 R2 R1
0x0000832E   LI R5 tasks
0x00008336   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000833A   LI R1 TASK_READY
0x00008342   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00008346   LI R1 WAIT_NONE
0x0000834E   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00008352       ADD R2 R2 1
0x00008356       B wq_wake_loop

wq_wake_done:
0x0000835E       POP LR
0x00008362       RET

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

0x00008366       LI R2 0                      ; index

fa_loop:
0x0000836E       CMP R2 MAX_FILES
0x00008372       BGE fa_fail

0x0000837A       SHL R3 R2 2                  ; index * 4
0x0000837E       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00008386       ADD R4 R4 R3

0x0000838A       LDW R5 [R4]
0x0000838E       CMP R5 0
0x00008392       BEQ fa_found

0x0000839A       ADD R2 R2 1
0x0000839E       B fa_loop

fa_found:
0x000083A6       LI R5 1
0x000083AE       STW R5 [R4]                  ; mark slot used

0x000083B2       LI R4 FILE_SIZE
0x000083BA       MUL R6 R2 R4

0x000083BE       LI R1 file_pool
0x000083C6       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x000083CA       LI R7 0

0x000083D2       STW R7 [R1 + FILE_OPS]
0x000083D6       STW R7 [R1 + FILE_PRIVATE]
0x000083DA       STW R7 [R1 + FILE_OFFSET]
0x000083DE       STW R7 [R1 + FILE_FLAGS]

0x000083E2       RET

fa_fail:
0x000083E6       LI R1 0
0x000083EE       RET

;=================================================================
; file_free:
; input:
; R1 = pointer to FILE object
; none output
;=================================================================

file_free:

0x000083F2       LI R2 file_pool
0x000083FA       SUB R3 R1 R2                 ; offset from pool base

0x000083FE       LI R4 FILE_SIZE
0x00008406       DIV R5 R3 R4                 ; slot number

0x0000840A       SHL R5 R5 2                  ; slot * 4

0x0000840E       LI R6 file_used
0x00008416       ADD R6 R6 R5                 ; address of slot in file_used

0x0000841A       LI R7 0
0x00008422       STW R7 [R6]                  ; mark free

0x00008426       RET


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

0x0000842A       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x0000842E       LI  R1 tasks
0x00008436       LI  R2 TASK_SIZE
0x0000843E       LI  R3 MAX_TASKS
0x00008446       MUL R3 R2 R3
0x0000844A       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x00008452       LI R1 idle_task
0x0000845A       LI R2 0
0x00008462       BL task_create

0x0000846A       CMP R1 0
0x0000846E       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task A
    ; ----------------------------------

0x00008476       LI R1 TASK_A_START
0x0000847E       LI R2 1
0x00008486       BL task_create

0x0000848E       CMP R1 0
0x00008492       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task B
    ; ----------------------------------

0x0000849A       LI R1 TASK_B_START
0x000084A2       LI R2 2
0x000084AA       BL task_create

0x000084B2       CMP R1 0
0x000084B6       BEQ init_scheduler_fail

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x000084BE       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x000084C6   LI R1 CURRENT_TASK
0x000084CE   STW R2 [R1]

0x000084D2       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x000084D6       RET


init_scheduler_fail:

0x000084DA       DEBUG 99

halt:
0x000084DE       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x000084E6   LI R1 CURRENT_TASK
0x000084EE   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x000084F2       ADD R3 R2 1

wrap_check:

0x000084F6       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x000084FA       BLT check_task
0x00008502       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x0000850A       LI R4 TASK_SIZE
0x00008512       MUL R5 R3 R4
0x00008516       LI R6 tasks
0x0000851E       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00008522       LDW R7 [R5 + TASK_STATE]

0x00008526       CMP R7 1
0x0000852A       BEQ do_switch
    ; if not ready go to next task in list
0x00008532       ADD R3 R3 1
0x00008536       B wrap_check

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
0x0000853E   LI R1 CURRENT_TASK
0x00008546   STW R3 [R1]
0x0000854A       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x0000854E   LI R1 TASK_SIZE
0x00008556   MUL R3 R2 R1
0x0000855A   LI R5 tasks
0x00008562   ADD R5 R5 R3
0x00008566       MOV R3 R8
0x0000856A       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x0000856E       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00008572   STW R7 [R5 + TASK_USP]

0x00008576       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x0000857A   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x0000857E   LI R1 RESUME_TRAP
0x00008586   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x0000858A   LI R1 TASK_SIZE
0x00008592   MUL R3 R8 R1
0x00008596   LI R5 tasks
0x0000859E   ADD R5 R5 R3
0x000085A2       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x000085A6   LDW R7 [R5 + TASK_PTBR]
0x000085AA       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x000085AE   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x000085B2   LDW R7 [R9 + TASK_STATE]
0x000085B6       CMP R7 TASK_ZOMBIE
0x000085BA       BNE switch_old_reaped
0x000085C2       PUSH R5
0x000085C6       MOV R1 R9
0x000085CA       BL task_destroy
0x000085D2       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x000085D6   LDW R7 [R5 + TASK_RESUME]
0x000085DA       CMP R7 RESUME_KERNEL
0x000085DE       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x000085E6       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x000085EE       PUSH R1
0x000085F2       PUSH R2
0x000085F6       PUSH R3
0x000085FA       PUSH R4
0x000085FE       PUSH R5
0x00008602       PUSH R6
0x00008606       PUSH R7
0x0000860A       PUSH R8
0x0000860E       PUSH R9
0x00008612       PUSH R10
0x00008616       PUSH R11
0x0000861A       PUSH R12
0x0000861E       PUSH R14
0x00008622       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00008626   LI R1 CURRENT_TASK
0x0000862E   LDW R2 [R1]

0x00008632       ADD R3 R2 1

schedule_call_wrap_check:
0x00008636       CMP R3 MAX_TASKS
0x0000863A       BLT schedule_call_check_task
0x00008642       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x0000864A       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x0000864E   LI R1 TASK_SIZE
0x00008656   MUL R3 R8 R1
0x0000865A   LI R5 tasks
0x00008662   ADD R5 R5 R3
0x00008666       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x0000866A   LDW R7 [R5 + TASK_STATE]
0x0000866E       CMP R7 TASK_READY               ; check it can be run
0x00008672       BEQ schedule_call_do_switch

0x0000867A       ADD R3 R3 1
0x0000867E       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00008686   LI R1 CURRENT_TASK
0x0000868E   STW R3 [R1]
0x00008692       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00008696   LI R1 TASK_SIZE
0x0000869E   MUL R3 R2 R1
0x000086A2   LI R5 tasks
0x000086AA   ADD R5 R5 R3
0x000086AE       MOV R3 R8

0x000086B2       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x000086B6   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x000086BA   LI R1 RESUME_KERNEL
0x000086C2   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x000086C6   LI R1 TASK_SIZE
0x000086CE   MUL R3 R8 R1
0x000086D2   LI R5 tasks
0x000086DA   ADD R5 R5 R3
0x000086DE       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x000086E2   LDW R7 [R5 + TASK_PTBR]
0x000086E6       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x000086EA   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x000086EE   LDW R7 [R5 + TASK_RESUME]
0x000086F2       CMP R7 RESUME_KERNEL
0x000086F6       BEQ restore_kernel_context

0x000086FE       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x00008706       DISABLEINT                  ; RET does jump by LR(R15)
0x0000870A       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x0000870E       POP R14                     ; (in kernel)
0x00008712       POP R12                     ; DI - to avoid int nesting
0x00008716       POP R11
0x0000871A       POP R10
0x0000871E       POP R9
0x00008722       POP R8
0x00008726       POP R7
0x0000872A       POP R6
0x0000872E       POP R5
0x00008732       POP R4
0x00008736       POP R3
0x0000873A       POP R2
0x0000873E       POP R1
0x00008742       RET
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

0x00008756       LI R2 0                  ; page index

pa_loop:
0x0000875E       LI R1 MAX_PHYS_PAGES

0x00008766       CMP R2 R1
0x0000876A       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00008772       MOV R3 R2
0x00008776       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x0000877A       MOV R4 R2
0x0000877E       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00008782       LI R5 page_bitmap
0x0000878A       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x0000878E       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x00008792       LI R7 1
0x0000879A       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x0000879E       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x000087A2       CMP R8 0
0x000087A6       BEQ pa_found                ; if bit is 0, page is free

0x000087AE       ADD R2 R2 1                 ; increment page index and check next page
0x000087B2       B pa_loop

pa_found:

    ; mark page allocated

0x000087BA       OR  R6 R6 R7
0x000087BE       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x000087C2       LI  R9 PAGE_ALLOC_BASE

0x000087CA       MOV R1 R2
0x000087CE       SHL R1 R1 12          ; page_index * 4096

0x000087D2       ADD R1 R1 R9

0x000087D6       RET

pa_fail:

0x000087DA       LI R1 0                     ; no free pages
0x000087E2       RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:

0x000087E6       LI R2 PAGE_ALLOC_BASE
0x000087EE       SUB R3 R1 R2         ; calculate offset from base

0x000087F2       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x000087F6       MOV R4 R3
0x000087FA       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x000087FE       MOV R5 R3
0x00008802       AND R5 R5 7          ; bit index in byte = page index % 8

0x00008806       LI R6 page_bitmap
0x0000880E       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x00008812       LDB R7 [R6]

0x00008816       LI R8 1
0x0000881E       SHL R8 R8 R5         ; mask for this page's bit

0x00008822       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00008826       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x0000882A       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000882E       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

0x00008832       LI R2 0

pz_loop:

0x0000883A       CMP R3 0
0x0000883E       BEQ pz_done

0x00008846       STB R2 [R1]

0x0000884A       ADD R1 R1 1
0x0000884E       SUB R3 R3 1

0x00008852       B pz_loop

pz_done:
0x0000885A       RET

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

0x00008BE2       PUSH LR

0x00008BE6       MOV R8 R1          ; entry
0x00008BEA       MOV R9 R2          ; pid
0x00008BEE       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x00008BF6       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x00008BFE       CMP R1 0
0x00008C02       BEQ task_create_fail

0x00008C0A       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x00008C0E       MOV R1 R10
0x00008C12       LI R3 TASK_SIZE
0x00008C1A       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x00008C22   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x00008C26   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x00008C2A       BL page_alloc
0x00008C32       CMP R1 0
0x00008C36       BEQ task_create_fail

0x00008C3E       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x00008C42   STW R1 [R10 + TASK_PTBR]

0x00008C46       MOV R1 R12
0x00008C4A       LI  R3 PAGE_SIZE
0x00008C52       BL  mem_zero                   ; zero out the sensitive new page table

0x00008C5A       MOV R1 R12
0x00008C5E       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x00008C66   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00008C6A   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x00008C6E   LDW R1 [R10 + TASK_PTBR]
0x00008C72       MOV R2 R8
0x00008C76       LI R3 0xFFFFF000
0x00008C7E       AND R2 R2 R3
0x00008C82       MOV R3 R2
0x00008C86       CMP R9 0
0x00008C8A       BEQ task_create_map_kernel_entry
0x00008C92       LI R4 USER_RX
0x00008C9A       B task_create_map_entry
task_create_map_kernel_entry:
0x00008CA2       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x00008CAA       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x00008CB2       BL page_alloc
0x00008CBA       CMP R1 0
0x00008CBE       BEQ task_create_fail

0x00008CC6       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x00008CCA   STW R12 [R10 + TASK_USTACK_PAGE]

0x00008CCE       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x00008CD6   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x00008CDA   LDW R1 [R10 + TASK_PTBR]

0x00008CDE       LI  R2 USER_STACK_VA
0x00008CE6       MOV R3 R12
0x00008CEA       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x00008CF2       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x00008CFA       BL page_alloc
0x00008D02       CMP R1 0
0x00008D06       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x00008D0E   STW R1 [R10 + TASK_KSTACK_PAGE]
0x00008D12       LI R2 PAGE_SIZE

0x00008D1A       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x00008D1E       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x00008D22   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00008D26   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x00008D2A       LI R1 0

0x00008D32       PUSH R1            ; R1
0x00008D36       PUSH R1            ; R2
0x00008D3A       PUSH R1            ; R3
0x00008D3E       PUSH R1            ; R4
0x00008D42       PUSH R1            ; R5
0x00008D46       PUSH R1            ; R6
0x00008D4A       PUSH R1            ; R7
0x00008D4E       PUSH R1            ; R8
0x00008D52       PUSH R1            ; R9
0x00008D56       PUSH R1            ; R10
0x00008D5A       PUSH R1            ; R11
0x00008D5E       PUSH R1            ; R12
0x00008D62       PUSH R1            ; R14 (FP)
0x00008D66       PUSH R1            ; R15 (LR)

0x00008D6A       PUSH R11           ; R11 - user SP top

0x00008D6E       MOV R1 R8
0x00008D72       PUSH R1            ; sepc = entry

0x00008D76       LI R1 0
0x00008D7E       PUSH R1            ; sflags

0x00008D82       CMP R9 0
0x00008D86       BEQ task_create_kernel_status
0x00008D8E       LI R1 0x20
0x00008D96       B task_create_status_ready
task_create_kernel_status:
0x00008D9E       LI R1 0x120
task_create_status_ready:
0x00008DA6       PUSH R1            ; sstatus

0x00008DAA       LI R1 0
0x00008DB2       PUSH R1            ; scause
0x00008DB6       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x00008DBA       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x00008DBE   STW R1 [R10 + TASK_KSP]

0x00008DC2       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x00008DC6   LI R1 WAIT_NONE
0x00008DCE   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x00008DD2   LI R1 RESUME_TRAP
0x00008DDA   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x00008DDE       BL page_alloc
0x00008DE6       CMP R1 0
0x00008DEA       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x00008DF2       MOV R12 R1

0x00008DF6       LI  R3 PAGE_SIZE
0x00008DFE       MOV R1 R12
0x00008E02       BL  mem_zero

    ; stdin
0x00008E0A       LI  R2 file_stdin
0x00008E12       STW R2 [R12 + 0]

    ; stdout
0x00008E16       LI  R2 file_stdout
0x00008E1E       STW R2 [R12 + 4]

    ; stderr
0x00008E22       LI  R2 file_stderr
0x00008E2A       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x00008E2E   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x00008E32       BL page_alloc
0x00008E3A       CMP R1 0
0x00008E3E       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x00008E46   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x00008E4A       BL page_alloc
0x00008E52       CMP R1 0
0x00008E56       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x00008E5E   STW R1 [R10 + TASK_KBUF_RD_PTR]

0x00008E62       BL page_alloc
0x00008E6A       CMP R1 0
0x00008E6E       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x00008E76   STW R1 [R10 + TASK_DATA_PAGE]

0x00008E7A       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x00008E7E   LDW R1 [R10 + TASK_PTBR]

0x00008E82       LI  R2 USER_DATA_VA
0x00008E8A       MOV R3 R12
0x00008E8E       LI  R4 USER_RW
0x00008E96       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x00008E9E   LI R1 TASK_READY
0x00008EA6   STW R1 [R10 + TASK_STATE]

0x00008EAA       MOV R1 R10                              ; return created task pointer

0x00008EAE       POP LR
0x00008EB2       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x00008EB6       CMP R10 0
0x00008EBA       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x00008EC2   LDW R1 [R10 + TASK_PTBR]
0x00008EC6       CMP R1 0
0x00008ECA       BEQ task_create_free_ustack
0x00008ED2       BL page_free

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00008EDA   LDW R1 [R10 + TASK_USTACK_PAGE]
0x00008EDE       CMP R1 0
0x00008EE2       BEQ task_create_free_kstack
0x00008EEA       BL page_free

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x00008EF2   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x00008EF6       CMP R1 0
0x00008EFA       BEQ task_create_free_fd
0x00008F02       BL page_free

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00008F0A   LDW R1 [R10 + TASK_FD_TABLE]
0x00008F0E       CMP R1 0
0x00008F12       BEQ task_create_free_kwr
0x00008F1A       BL page_free

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x00008F22   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x00008F26       CMP R1 0
0x00008F2A       BEQ task_create_free_krd
0x00008F32       BL page_free

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x00008F3A   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x00008F3E       CMP R1 0
0x00008F42       BEQ task_create_free_data
0x00008F4A       BL page_free

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x00008F52   LDW R1 [R10 + TASK_DATA_PAGE]
0x00008F56       CMP R1 0
0x00008F5A       BEQ task_create_clear_slot
0x00008F62       BL page_free

task_create_clear_slot:
0x00008F6A       MOV R1 R10
0x00008F6E       LI R3 TASK_SIZE
0x00008F76       BL mem_zero

task_create_fail_return:
0x00008F7E       LI R1 0

0x00008F86       POP LR
0x00008F8A       RET

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

0x00008F8E       PUSH LR
0x00008F92       push R12 ; preserve R12 which we use for temporary storage in this function
0x00008F96       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x00008F9A   LDW R2 [R1 + TASK_PTBR]
0x00008F9E       CMP R2 0
0x00008FA2       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x00008FAA       MOV R1 R2
0x00008FAE       BL page_free        ; free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x00008FB6   LDW R2 [R12 + TASK_USTACK_PAGE]
0x00008FBA       CMP R2 0
0x00008FBE       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00008FC6       MOV R1 R2
0x00008FCA       BL page_free

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x00008FD2   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x00008FD6       CMP R2 0
0x00008FDA       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00008FE2       MOV R1 R2
0x00008FE6       BL page_free

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x00008FEE   LDW R2 [R12 + TASK_FD_TABLE]
0x00008FF2       CMP R2 0
0x00008FF6       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00008FFE       MOV R1 R2
0x00009002       BL page_free

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x0000900A   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x0000900E       CMP R2 0
0x00009012       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x0000901A       MOV R1 R2
0x0000901E       BL page_free

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x00009026   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x0000902A       CMP R2 0
0x0000902E       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x00009036       MOV R1 R2
0x0000903A       BL page_free

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x00009042   LDW R2 [R12 + TASK_DATA_PAGE]
0x00009046       CMP R2 0
0x0000904A       BEQ td_done     ; if task has no user data page, it also has no user buffers to free, so skip freeing user buffers and move to clearing slot and returning
0x00009052       MOV R1 R2
0x00009056       BL page_free

td_done:

0x0000905E       MOV R1 R12
0x00009062       LI  R3 TASK_SIZE
0x0000906A       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x00009072       POP R12         ; restore R12
0x00009076       POP LR
0x0000907A       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x0000907E       PUSH LR
0x00009082       PUSH R8
0x00009086       PUSH R9
0x0000908A       PUSH R10
0x0000908E       PUSH R11
0x00009092       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x00009096   LDW R4 [R1 + TASK_FD_TABLE]
0x0000909A       MOV R12 R4

0x0000909E       LI R5 3              ; skip stdin/out/err
0x000090A6       MOV R11 R5

fd_loop:

0x000090AA       CMP R11 MAX_FDS
0x000090AE       BGE fd_done         ; if we processed all fd slots, we are done

0x000090B6       SHL R6 R11 2
0x000090BA       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x000090BE       LDW R8 [R10]
0x000090C2       CMP R8 0
0x000090C6       BEQ fd_next         ; if fd slot is empty, skip to next

0x000090CE       MOV R1 R8
0x000090D2       BL file_free
0x000090DA       LI R9 0
0x000090E2       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x000090E6       ADD R11 R11 1
0x000090EA       B fd_loop

fd_done:
0x000090F2       POP R12
0x000090F6       POP R11
0x000090FA       POP R10
0x000090FE       POP R9
0x00009102       POP R8
0x00009106       POP LR
0x0000910A       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x0000910E       PUSH LR
0x00009112       PUSH R8
0x00009116       PUSH R9
0x0000911A       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x0000911E   LI R1 CURRENT_TASK
0x00009126   LDW R10 [R1]
0x0000912A       LI R8 0

task_reap_loop:
0x00009132       CMP R8 MAX_TASKS
0x00009136       BGE task_reap_done

0x0000913E       CMP R8 R10
0x00009142       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x0000914A   LI R1 TASK_SIZE
0x00009152   MUL R3 R8 R1
0x00009156   LI R9 tasks
0x0000915E   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x00009162   LDW R1 [R9 + TASK_STATE]
0x00009166       CMP R1 TASK_ZOMBIE
0x0000916A       BNE task_reap_next

0x00009172       PUSH R8
0x00009176       MOV R1 R9
0x0000917A       BL task_destroy
0x00009182       POP R8

task_reap_next:
0x00009186       ADD R8 R8 1
0x0000918A       B task_reap_loop

task_reap_done:
0x00009192       POP R10
0x00009196       POP R9
0x0000919A       POP R8
0x0000919E       POP LR
0x000091A2       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x000091A6       LI R1 tasks
0x000091AE       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x000091B6   LDW R3 [R1 + TASK_STATE]

0x000091BA       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x000091BE       BEQ task_alloc_found

0x000091C6       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x000091CA       SUB R2 R2 1
0x000091CE       BNE task_alloc_loop

; no free tasks slots

0x000091D6       LI R1 0
0x000091DE       RET

task_alloc_found:                           ;R1 points to free task slot

0x000091E2       RET

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
0x00009010       DEBUG 1
    ;LI R1 SYS_EXIT
    ;SVC SYS_EXIT
0x00009014       B idle_loop

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
