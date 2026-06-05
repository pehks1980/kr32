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

.EQU PTBR0_VA,     0x00010000
.EQU PTBR1_VA,     0x00020000
.EQU PTBR2_VA,     0x00030000

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
.EQU KERNEL_LIMIT,    0x7FFF
.EQU USER_BASE,       0x00005000
.EQU USER_LIMIT,      0x000FFFFF

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

        ; Enable MMU and interrupts
0x00002038   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
0x00002040           LI R1 tasks
0x00002048           LDW SP [R1 + TASK_KSP]
        ; jump to task0 entry point (0x5000) through the same trap restore
0x0000204C           B trap_restore

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x00002054       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x0000205C       LI R2 trap_entry
0x00002064       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x00002068       LI R2 trap_entry
0x00002070       STW R2 [R1+4]                ; IDT[1]
0x00002074       STW R2 [R1+8]                ; IDT[2]
0x00002078       STW R2 [R1+12]               ; IDT[3]
0x0000207C       STW R2 [R1+24]               ; IDT[6]
0x00002080       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x00002084       SETIDTR R1
0x00002088       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
0x0000208C       PUSH LR

    ; EVERY TASK owns a different PTBR. Kernel pages are mapped into ALL
    ; address spaces as supervisor global entries; user stack/data pages are
    ; mapped per task to prove same-VA, different-PA isolation.
0x00002090       LI R1 TASK0_PTBR            ; task 0 page table pointer (phys address)
0x00002098       BL map_common_kernel        ; map kernel page table for task 0 - a kernel process "idle loop" run in kernel mode
0x000020A0       LI R2 0x00005000            ; page VA -virt addr
0x000020A8       LI R3 TASK0_USTACK_PA       ; page PA -phys addr (.org one)
0x000020B0       LI R4 USER_RW               ; page access matrix stored it page table entry (PTE)
0x000020B8       BL map_page
0x000020C0       LI R2 0x00006000
0x000020C8       LI R3 TASK0_DATA_PA
0x000020D0       LI R4 USER_RW
0x000020D8       BL map_page

0x000020E0       LI R1 TASK1_PTBR             ; USER task 1 page table pointer (phys address)
0x000020E8       BL map_common_kernel
    ; Map user stack/data region: 0x17000-0x19000 for user code and stack space
0x000020F0       LI R2 0x00017000             ;page 1: stack area
0x000020F8       LI R3 0x00007000             ;allocate physical page for stack
0x00002100       LI R4 USER_RW
0x00002108       BL map_page
0x00002110       LI R2 0x00018000             ;page 2: stack area
0x00002118       LI R3 TASK1_DATA_PA          ;physical address
0x00002120       LI R4 USER_RW
0x00002128       BL map_page
0x00002130       LI R2 0x00005000             ;legacy: page used for stack (map for compatibility)
0x00002138       LI R3 TASK1_USTACK_PA        ; physical address
0x00002140       LI R4 USER_RW
0x00002148       BL map_page
0x00002150       LI R2 0x00006000             ;legacy: page used for data (map for compatibility)
0x00002158       LI R3 0x0000E000             ;another physical page
0x00002160       LI R4 USER_RW
0x00002168       BL map_page

0x00002170       LI R1 TASK2_PTBR            ; USER task 2 - same
0x00002178       BL map_common_kernel
    ; Map user stack/data region: 0x17000-0x19000 for user code and stack space
0x00002180       LI R2 0x00017000             ;page 1: stack area
0x00002188       LI R3 0x0000F000             ;allocate physical page for stack
0x00002190       LI R4 USER_RW
0x00002198       BL map_page
0x000021A0       LI R2 0x00018000             ;page 2: stack area
0x000021A8       LI R3 TASK2_DATA_PA          ;physical address
0x000021B0       LI R4 USER_RW
0x000021B8       BL map_page
0x000021C0       LI R2 0x00005000             ;legacy: page used for stack (map for compatibility)
0x000021C8       LI R3 TASK2_USTACK_PA
0x000021D0       LI R4 USER_RW
0x000021D8       BL map_page
0x000021E0       LI R2 0x00006000             ;legacy: page used for data (map for compatibility)
0x000021E8       LI R3 TASK0_DATA_PA          ;shared user literals at 0x6000
0x000021F0       LI R4 USER_RW
0x000021F8       BL map_page

0x00002200       LI R1 TASK0_PTBR
0x00002208       SETPTBR R1
0x0000220C       POP LR
0x00002210       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x00002214       PUSH LR

    ; Boot page, kernel/trap code, kernel stacks, scheduler/task metadata,
    ; and the user text page are identity-mapped into every address space.
0x00002218       LI R2 0x00000000      ;page 0 - boot (0000)
0x00002220       LI R3 0x00000000
0x00002228       LI R4 KERNEL_FLAGS
0x00002230       BL map_page
0x00002238       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x00002240       LI R3 0x00002000
0x00002248       LI R4 KERNEL_FLAGS
0x00002250       BL map_page
0x00002258       LI R2 0x00003000
0x00002260       LI R3 0x00003000
0x00002268       LI R4 KERNEL_FLAGS
0x00002270       BL map_page
0x00002278       LI R2 0x00004000
0x00002280       LI R3 0x00004000
0x00002288       LI R4 KERNEL_FLAGS
0x00002290       BL map_page
0x00002298       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x000022A0       LI R3 0x00007000
0x000022A8       LI R4 KERNEL_FLAGS
0x000022B0       BL map_page
0x000022B8       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x000022C0       LI R3 0x00008000
0x000022C8       LI R4 KERNEL_FLAGS
0x000022D0       BL map_page
0x000022D8       LI R2 0x00009000      ; page 5 text page (program) for user mode process
0x000022E0       LI R3 0x00009000
0x000022E8       LI R4 KERN_USER_RX
0x000022F0       BL map_page
0x000022F8       LI R2 0x00019000      ; page 5 text page (program) for user mode process
0x00002300       LI R3 0x00019000
0x00002308       LI R4 KERN_USER_RX
0x00002310       BL map_page
0x00002318       LI R2 0x0001a000      ; page 5 text page (program) for user mode process
0x00002320       LI R3 0x0001a000
0x00002328       LI R4 KERN_USER_RX
0x00002330       BL map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x00002338       LI R2 0x00001000      ; page for kernel buffers
0x00002340       LI R3 0x00001000
0x00002348       LI R4 KERNEL_FLAGS
0x00002350       BL map_page

    ; Map page table memory pages into kernel address space so the kernel
    ; can read/write page table entries after MMU is enabled
0x00002358       LI R2 0x00010000      ; page table for task 0
0x00002360       LI R3 0x00010000
0x00002368       LI R4 KERNEL_FLAGS
0x00002370       BL map_page

0x00002378       LI R2 0x00020000      ; page table for task 1
0x00002380       LI R3 0x00020000
0x00002388       LI R4 KERNEL_FLAGS
0x00002390       BL map_page

0x00002398       LI R2 0x00030000      ; page table for task 2
0x000023A0       LI R3 0x00030000
0x000023A8       LI R4 KERNEL_FLAGS
0x000023B0       BL map_page

0x000023B8       LI R2 PTBR0_VA
0x000023C0       LI R3 TASK0_PTBR
0x000023C8       LI R4 KERNEL_FLAGS
0x000023D0       BL map_page

0x000023D8       LI R2 PTBR1_VA
0x000023E0       LI R3 TASK1_PTBR
0x000023E8       LI R4 KERNEL_FLAGS
0x000023F0       BL map_page

0x000023F8       LI R2 PTBR2_VA
0x00002400       LI R3 TASK2_PTBR
0x00002408       LI R4 KERNEL_FLAGS
0x00002410       BL map_page

    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x00002418       LI R2 0x00100000      ; UART physical and virtual base
0x00002420       LI R3 0x00100000
0x00002428       LI R4 KERNEL_FLAGS
0x00002430       BL map_page

0x00002438       LI R2 0x00101000      ; PIT physical and virtual base
0x00002440       LI R3 0x00101000
0x00002448       LI R4 KERNEL_FLAGS
0x00002450       BL map_page

0x00002458       LI R2 0x00102000      ; PIC physical and virtual base
0x00002460       LI R3 0x00102000
0x00002468       LI R4 KERNEL_FLAGS
0x00002470       BL map_page

0x00002478       POP LR
0x0000247C       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002480       SHR R5 R2 12               ; VPN
0x00002484       SHL R5 R5 2                ; page-table byte offset
0x00002488       OR R6 R3 R4                ; PTE = PA page base | flags
0x0000248C       STW R6 [R1 + R5]
0x00002490       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x00002494       LI R1 0x00102000
0x0000249C       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x000024A4       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x000024A8       LI R1 0x00101000
0x000024B0       LI R2 2000
0x000024B8       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x000024BC       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000024C4       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x000024C8       LI R1 0x00100000
0x000024D0       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000024D8       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x000024DC       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000024E0       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000024E4       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000024E8       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000024EC       PUSH R1
0x000024F0       PUSH R2
0x000024F4       PUSH R3
0x000024F8       PUSH R4
0x000024FC       PUSH R5
0x00002500       PUSH R6
0x00002504       PUSH R7
0x00002508       PUSH R8
0x0000250C       PUSH R9
0x00002510       PUSH R10
0x00002514       PUSH R11
0x00002518       PUSH R12
0x0000251C       PUSH R14
0x00002520       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x00002524       CSRR R1 SSCRATCH
0x00002528       PUSH R1
0x0000252C       CSRR R1 SEPC
0x00002530       PUSH R1
0x00002534       CSRR R1 SFLAGS
0x00002538       PUSH R1
0x0000253C       CSRR R1 SSTATUS
0x00002540       PUSH R1
0x00002544       CSRR R1 SCAUSE
0x00002548       PUSH R1
0x0000254C       CSRR R1 STVAL
0x00002550       PUSH R1

    ; Dispatch based on scause.
0x00002554       CSRR R1 SCAUSE
0x00002558       CMP R1 0
0x0000255C       BEQ handle_divide_zero

0x00002564       CMP R1 1
0x00002568       BEQ handle_invalid_instr

0x00002570       CMP R1 2
0x00002574       BEQ handle_page_fault

0x0000257C       CMP R1 3
0x00002580       BEQ handle_syscall

0x00002588       CMP R1 6
0x0000258C       BEQ handle_debug

0x00002594       CMP R1 16
0x00002598       BEQ handle_irq

    ; Unknown cause - halt
0x000025A0       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x000025A4       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x000025AC       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x000025B4       HLT

0x000025B8       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x000025C0       CSRR R2 STVAL

0x000025C4       CMP R2 SYS_COUNT
0x000025C8       BGE syscall_unknown

0x000025D0       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000025D8       SHL R4 R2 2
0x000025DC       LDW R5 [R3 + R4]
0x000025E0       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000025E4       LI R1 ERR_NOSYS
0x000025EC       STW R1 [SP + TF_R1]
0x000025F0       B trap_restore

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

0x0000261C       LI R1 0
0x00002624       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00002628       B schedule_and_switch

syscall_exit:
    ;================================================================
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002630   LI R1 CURRENT_TASK
0x00002638   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x0000263C   LI R1 TASK_SIZE
0x00002644   MUL R3 R2 R1
0x00002648   LI R5 tasks
0x00002650   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_DEAD
0x00002654   LI R1 TASK_DEAD
0x0000265C   STW R1 [R5 + TASK_STATE]

0x00002660       LI R1 0
0x00002668       STW R1 [SP + TF_R1]         ; r1=0 - return success
0x0000266C       B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002674   LI R1 CURRENT_TASK
0x0000267C   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002680   LI R1 TASK_SIZE
0x00002688   MUL R3 R2 R1
0x0000268C   LI R5 tasks
0x00002694   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00002698   LDW R1 [R5 + TASK_PID]

0x0000269C       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x000026A0       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x000026A8       LDW R1 [SP + TF_R1]
0x000026AC       STW R1 [SP + TF_R1]

0x000026B0       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x000026B8       LDW R1 [SP + TF_R1]
0x000026BC       LDW R2 [SP + TF_R2]

0x000026C0       MOV R12 R2               ; save flags

0x000026C4       BL copy_path_from_user      ; macro inside destroys R11
0x000026CC       CMP R1 0
0x000026D0       BEQ open_fail_fault

0x000026D8       BL lookup_device
0x000026E0       CMP R1 0
0x000026E4       BEQ open_fail_noent

0x000026EC       MOV R8 R1            ; save device descriptor

0x000026F0       BL file_alloc        ; out: R1 = pointer to FILE object in file_pool
0x000026F8       CMP R1 0
0x000026FC       BEQ open_fail_nfile
0x00002704       MOV R9 R1            ;

    ; initialize file object
0x00002708       MOV R1 R9                ; file*
0x0000270C       MOV R2 R8                ; device*
0x00002710       MOV R3 R12               ; flags
0x00002714       BL file_init             ; ([i].device*)->([i].file*), [i].seek=0, set [i].flags in file_pool

0x0000271C       MOV R1 R9                ; initialised file ptr (ie file instance)
0x00002720       BL fd_alloc              ; fd_table[new_fd] = file* (new_fd - idx in fd_table 4,5,6...)
0x00002728       LI  R2 ERR_MFILE
0x00002730       CMP R1 R2
0x00002734       BEQ open_fail_fd

0x0000273C       STW R1 [SP + TF_R1]

0x00002740       B trap_restore

open_fail_fd:
0x00002748       MOV R1 R9
0x0000274C       BL file_free
0x00002754       LI R1 ERR_MFILE
0x0000275C       STW R1 [SP + TF_R1]

0x00002760       B trap_restore

open_fail_nfile:
0x00002768       LI R1 ERR_NFILE
0x00002770       STW R1 [SP + TF_R1]

0x00002774       B trap_restore

open_fail_noent:
0x0000277C       LI R1 ERR_NOENT
0x00002784       STW R1 [SP + TF_R1]

0x00002788       B trap_restore

open_fail_fault:
0x00002790       LI R1 ERR_FAULT
0x00002798       STW R1 [SP + TF_R1]

0x0000279C       B trap_restore
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
0x000027A4       PUSH LR

0x000027A8       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x000027AC   LI R1 CURRENT_TASK
0x000027B4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000027B8   LI R1 TASK_SIZE
0x000027C0   MUL R3 R4 R1
0x000027C4   LI R5 tasks
0x000027CC   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x000027D0   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x000027D4       PUSH R9                    ; original destination returned on success
0x000027D8       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x000027E0       LI R11 KBUFFER_SIZE
0x000027E8       CMP R10 R11
0x000027EC       BGE copy_path_fail

0x000027F4       PUSH R8
0x000027F8       PUSH R9
0x000027FC       PUSH R10
0x00002800       MOV R1 R8
0x00002804       LI R2 1
0x0000280C       LI R3 0                    ; read access from user source
0x00002814       BL user_buffer_valid_range
0x0000281C       POP R10
0x00002820       POP R9
0x00002824       POP R8
0x00002828       CMP R1 1
0x0000282C       BNE copy_path_fail

0x00002834       LDB R4 [R8]
0x00002838       STB R4 [R9]
0x0000283C       CMP R4 0
0x00002840       BEQ copy_path_done

0x00002848       ADD R8 R8 1
0x0000284C       ADD R9 R9 1
0x00002850       ADD R10 R10 1
0x00002854       B copy_path_loop

copy_path_done:
0x0000285C       POP R1                     ; original kernel path pointer
0x00002860       POP LR
0x00002864       RET

copy_path_fail:
0x00002868       POP R1                     ; discard original kernel path pointer
0x0000286C       LI R1 0
0x00002874       POP LR
0x00002878       RET

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

0x0000287C       PUSH LR

0x00002880       MOV R8 R1                  ; save pathname ptr

0x00002884       LI R7 device_table
0x0000288C       LI R9 DEVICE_COUNT

lookup_loop:
0x00002894       CMP R9 0
0x00002898       BEQ lookup_fail

    ; compare pathname with device name

0x000028A0       MOV R1 R8
0x000028A4       LDW R2 [R7 + DEV_NAME]

0x000028A8       BL strcmp

0x000028B0       CMP R1 1
0x000028B4       BEQ lookup_found

0x000028BC       ADD R7 R7 DEV_SIZE
0x000028C0       SUB R9 R9 1
0x000028C4       B lookup_loop

lookup_found:

0x000028CC       MOV R1 R7                  ; return device descriptor ptr

0x000028D0       POP LR
0x000028D4       RET

lookup_fail:

0x000028D8       LI R1 0

0x000028E0       POP LR
0x000028E4       RET

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
0x000028E8       LDB R3 [R1]
0x000028EC       LDB R4 [R2]

0x000028F0       CMP R3 R4
0x000028F4       BNE str_not_equal

0x000028FC       CMP R3 0
0x00002900       BEQ str_equal

0x00002908       ADD R1 R1 1
0x0000290C       ADD R2 R2 1
0x00002910       B str_loop

str_equal:
0x00002918       LI R1 1
0x00002920       RET

str_not_equal:
0x00002924       LI R1 0
0x0000292C       RET

;====================================================================
; file_init
; in: R1 = file pointer
      ;R2 = device descriptor pointer in file_pool
      ;R3 = open flags
; out:file structure initialized
;====================================================================
file_init:

0x00002930       LDW R4 [R2 + DEV_OPS]
0x00002934       STW R4 [R1 + FILE_OPS]

0x00002938       LDW R4 [R2 + DEV_PRIVATE]
0x0000293C       STW R4 [R1 + FILE_PRIVATE]

0x00002940       LI R4 0
0x00002948       STW R4 [R1 + FILE_OFFSET]

0x0000294C       STW R3 [R1 + FILE_FLAGS]

0x00002950       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x00002954       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x00002958   LI R1 CURRENT_TASK
0x00002960   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002964   LI R1 TASK_SIZE
0x0000296C   MUL R3 R4 R1
0x00002970   LI R4 tasks
0x00002978   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x0000297C   LDW R4 [R4 + TASK_FD_TABLE]

0x00002980       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00002988       CMP R5 MAX_FDS
0x0000298C       BGE fd_alloc_fail

0x00002994       SHL R6 R5 2                ; fd * 4
0x00002998       ADD R7 R4 R6               ; &fd_table[fd]

0x0000299C       LDW R2 [R7]
0x000029A0       CMP R2 0                   ; 0 - empty
0x000029A4       BEQ fd_alloc_found

0x000029AC       ADD R5 R5 1
0x000029B0       B fd_alloc_loop

fd_alloc_found:

0x000029B8       STW R8 [R7]                ; fd_table[fd] = file*

0x000029BC       MOV R1 R5                  ; return fd
0x000029C0       RET

fd_alloc_fail:

0x000029C4       LI R1 ERR_MFILE
0x000029CC       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x000029D0       LDW R1 [SP + TF_R1]

0x000029D4       BL fd_remove    ;in R1-fd out R1-file ptr for this fd

0x000029DC       CMP R1 0
0x000029E0       BEQ close_fail

0x000029E8       BL file_free    ;in R1 file_ptr in file_pool it marks it as free (NULL)

0x000029F0       LI R1 0
0x000029F8       STW R1 [SP + TF_R1]

0x000029FC       B trap_restore

close_fail:
0x00002A04       LI R1 ERR_BADF
0x00002A0C       STW R1 [SP + TF_R1]

0x00002A10       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00002A18       LDW R7 [SP + TF_R1]

0x00002A1C       BL pipe_alloc
0x00002A24       CMP R1 0
0x00002A28       BEQ pipe_fail_nospc

0x00002A30       MOV R8 R1            ; new slot in pipe_pool ( pipe* )

    ; [0] read end          write[1]>--pipe--->read[0]

0x00002A34       BL file_alloc
0x00002A3C       CMP R1 0
0x00002A40       BEQ pipe_fail_pipe_only

0x00002A48       MOV R9 R1           ; new file for read end  in file_pool

0x00002A4C       LI R2 pipe_ops
0x00002A54       STW R2 [R9 + FILE_OPS]      ; store ops (for pipe of read end) in allocated  file struc

0x00002A58       STW R8 [R9 + FILE_PRIVATE]  ; store our slot pipe* in file

0x00002A5C       LI R2 FD_FLAG_READ
0x00002A64       STW R2 [R9 + FILE_FLAGS]    ; set file mode read

0x00002A68       MOV R1 R9
0x00002A6C       BL fd_alloc                 ; insert read file to fd_table of user process

0x00002A74       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002A7C       CMP R1 R2
0x00002A80       BEQ pipe_fail_read_file

0x00002A88       MOV R10 R1           ; get file read fd created to R10

    ; write end

0x00002A8C       BL file_alloc
0x00002A94       CMP R1 0
0x00002A98       BEQ pipe_fail_read_fd

0x00002AA0       MOV R9 R1

0x00002AA4       LI R2 pipe_ops
0x00002AAC       STW R2 [R9 + FILE_OPS]

0x00002AB0       STW R8 [R9 + FILE_PRIVATE]

0x00002AB4       LI R2 FD_FLAG_WRITE                 ;file mode -write
0x00002ABC       STW R2 [R9 + FILE_FLAGS]

0x00002AC0       MOV R1 R9
0x00002AC4       BL fd_alloc

0x00002ACC       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002AD4       CMP R1 R2
0x00002AD8       BEQ pipe_fail_write_file

0x00002AE0       MOV R11 R1           ; R11 write fd R10 read fd

0x00002AE4       MOV R1 R7   ; in &fd[2]
0x00002AE8       LI R2 8     ; len 2
0x00002AF0       LI R3 1     ; mem perm to write cond
0x00002AF8       BL user_buffer_valid_range
0x00002B00       CMP R1 1
0x00002B04       BNE pipe_fail_both_fds

0x00002B0C       STW R10 [R7]    ;fd[0]-rd fd[1]-wr
0x00002B10       STW R11 [R7 + 4]

0x00002B14       LI R1 0
0x00002B1C       STW R1 [SP + TF_R1]

0x00002B20       B trap_restore

pipe_fail:
0x00002B28       LI R1 ERR_IO
0x00002B30       STW R1 [SP + TF_R1]

0x00002B34       B trap_restore

pipe_fail_both_fds:
0x00002B3C       MOV R12 R8
0x00002B40       MOV R1 R11
0x00002B44       BL fd_remove
0x00002B4C       CMP R1 0
0x00002B50       BEQ pipe_fail_both_fds_read
0x00002B58       BL file_free

pipe_fail_both_fds_read:
0x00002B60       MOV R1 R10
0x00002B64       BL fd_remove
0x00002B6C       CMP R1 0
0x00002B70       BEQ pipe_fail_free_pipe_fault
0x00002B78       BL file_free

pipe_fail_free_pipe_fault:
0x00002B80       MOV R1 R12
0x00002B84       BL pipe_free
0x00002B8C       LI R1 ERR_FAULT
0x00002B94       STW R1 [SP + TF_R1]

0x00002B98       B trap_restore

pipe_fail_write_file:
0x00002BA0       MOV R12 R8
0x00002BA4       MOV R1 R9
0x00002BA8       BL file_free
0x00002BB0       MOV R1 R10
0x00002BB4       BL fd_remove
0x00002BBC       CMP R1 0
0x00002BC0       BEQ pipe_fail_free_pipe_mfile
0x00002BC8       BL file_free

pipe_fail_free_pipe_mfile:
0x00002BD0       MOV R1 R12
0x00002BD4       BL pipe_free
0x00002BDC       LI R1 ERR_MFILE
0x00002BE4       STW R1 [SP + TF_R1]

0x00002BE8       B trap_restore

pipe_fail_read_fd:
0x00002BF0       MOV R12 R8
0x00002BF4       MOV R1 R10
0x00002BF8       BL fd_remove
0x00002C00       CMP R1 0
0x00002C04       BEQ pipe_fail_free_pipe_nfile
0x00002C0C       BL file_free

pipe_fail_free_pipe_nfile:
0x00002C14       MOV R1 R12
0x00002C18       BL pipe_free
0x00002C20       LI R1 ERR_NFILE
0x00002C28       STW R1 [SP + TF_R1]

0x00002C2C       B trap_restore

pipe_fail_read_file:
0x00002C34       MOV R12 R8
0x00002C38       MOV R1 R9
0x00002C3C       BL file_free
0x00002C44       MOV R1 R12
0x00002C48       BL pipe_free
0x00002C50       LI R1 ERR_MFILE
0x00002C58       STW R1 [SP + TF_R1]

0x00002C5C       B trap_restore

pipe_fail_pipe_only:
0x00002C64       MOV R1 R8
0x00002C68       BL pipe_free
0x00002C70       LI R1 ERR_NFILE
0x00002C78       STW R1 [SP + TF_R1]

0x00002C7C       B trap_restore

pipe_fail_nospc:
0x00002C84       LI R1 ERR_NOSPC
0x00002C8C       STW R1 [SP + TF_R1]

0x00002C90       B trap_restore

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

0x00002C98       PUSH LR

0x00002C9C       MOV R9 R1              ; file*
0x00002CA0       MOV R7 R2              ; user buffer
0x00002CA4       MOV R6 R3              ; requested len
0x00002CA8       LDW R9 [R9 + FILE_PRIVATE]    ; our instance allocated in pipe_pool pipe*
0x00002CAC       CMP R6 0                ;fast clear from it if len=0
0x00002CB0       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00002CB8       PUSH R7
0x00002CBC       PUSH R6

0x00002CC0       MOV R1 R7
0x00002CC4       MOV R2 R6
0x00002CC8       LI  R3 1               ; write access
0x00002CD0       BL user_buffer_valid_range

0x00002CD8       POP R6
0x00002CDC       POP R7
0x00002CE0       CMP R1 1
0x00002CE4       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00002CEC       LDW R4 [R9 + PIPE_COUNT]
0x00002CF0       CMP R4 0
0x00002CF4       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00002CFC       CMP R6 R4
0x00002D00       BLT pipe_user_len

0x00002D08       MOV R5 R4
0x00002D0C       B pipe_have_amount

pipe_user_len:
0x00002D14       MOV R5 R6

pipe_have_amount:
0x00002D18       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00002D20       CMP R10 R5
0x00002D24       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00002D2C       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00002D30       MOV R12 R9
0x00002D34       ADD R12 R12 PIPE_BUFFER
0x00002D38       ADD R12 R12 R11         ; addr += tail

0x00002D3C       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00002D40       MOV R12 R7
0x00002D44       ADD R12 R12 R10

0x00002D48       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x00002D4C       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00002D50       LI R2 255
0x00002D58       AND R11 R11 R2
0x00002D5C       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00002D60       LDW R12 [R9 + PIPE_COUNT]
0x00002D64       SUB R12 R12 1
0x00002D68       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00002D6C       ADD R10 R10 1
0x00002D70       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00002D78       MOV R1 R9
0x00002D7C       ADD R1 R1 PIPE_WWAIT
0x00002D80       BL waitq_wake_all
0x00002D88       MOV R1 R10          ; read bytes amount
0x00002D8C       POP LR
0x00002D90       RET

pipe_read_badptr:
0x00002D94       LI R1 ERR_FAULT
0x00002D9C       POP LR
0x00002DA0       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00002DA4       MOV R1 R9
0x00002DA8       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00002DAC       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00002DB4       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00002DBC       LDW R4 [R9 + PIPE_COUNT]
0x00002DC0       CMP R4 0
0x00002DC4       BNE pipe_read_retry

0x00002DCC       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00002DD4       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00002DDC       LI R2 0

pipe_loop:
0x00002DE4       LI  R1 MAX_PIPES
0x00002DEC       CMP R2 R1
0x00002DF0       BGE pipe_alloc_fail

0x00002DF8       SHL R3 R2 2

0x00002DFC       LI R4 pipe_used
0x00002E04       ADD R4 R4 R3

0x00002E08       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00002E0C       CMP R5 0                ; 0 -empty
0x00002E10       BEQ pipe_found

0x00002E18       ADD R2 R2 1
0x00002E1C       B pipe_loop

pipe_found:

0x00002E24       LI R5 1
0x00002E2C       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00002E30       LI R4 PIPE_SIZE
0x00002E38       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00002E3C       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00002E44       ADD R1 R1 R6

0x00002E48       LI R7 0                 ; clean it up
0x00002E50       STW R7 [R1 + PIPE_HEAD]
0x00002E54       STW R7 [R1 + PIPE_TAIL]
0x00002E58       STW R7 [R1 + PIPE_COUNT]
0x00002E5C       STW R7 [R1 + PIPE_RWAIT]
0x00002E60       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00002E64       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00002E68       LI R1 0
0x00002E70       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00002E74       LI R2 pipe_pool
0x00002E7C       SUB R3 R1 R2

0x00002E80       LI R4 PIPE_SIZE
0x00002E88       DIV R5 R3 R4

0x00002E8C       SHL R5 R5 2
0x00002E90       LI R6 pipe_used
0x00002E98       ADD R6 R6 R5

0x00002E9C       LI R7 0
0x00002EA4       STW R7 [R6]

0x00002EA8       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00002EAC       PUSH LR

0x00002EB0       MOV R8 R1
0x00002EB4       MOV R7 R2
0x00002EB8       MOV R6 R3

0x00002EBC       LDW R9 [R8 + FILE_PRIVATE]

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00002EC0       PUSH R7
0x00002EC4       PUSH R6

0x00002EC8       MOV R1 R7
0x00002ECC       MOV R2 R6
0x00002ED0       LI  R3 0           ; READ access
0x00002ED8       BL user_buffer_valid_range

0x00002EE0       POP R6
0x00002EE4       POP R7

0x00002EE8       CMP R1 1
0x00002EEC       BNE pipe_write_badptr

0x00002EF4       LI R10 0               ; bytes written
pipe_write_retry:
0x00002EFC       CMP R10 R6
0x00002F00       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00002F08       LDW R11 [R9 + PIPE_COUNT]
0x00002F0C       LI R2 256
0x00002F14       CMP R11 R2
0x00002F18       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00002F20       LDW R12 [R9 + PIPE_HEAD]

0x00002F24       MOV R4 R7
0x00002F28       ADD R4 R4 R10
0x00002F2C       LDB R5 [R4]     ; read byte from user buff addr

0x00002F30       MOV R4 R9
0x00002F34       ADD R4 R4 PIPE_BUFFER
0x00002F38       ADD R4 R4 R12
0x00002F3C       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00002F40       ADD R12 R12 1
0x00002F44       LI R2 255
0x00002F4C       AND R12 R12 R2
0x00002F50       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00002F54       LDW R4 [R9 + PIPE_COUNT]
0x00002F58       ADD R4 R4 1
0x00002F5C       STW R4 [R9 + PIPE_COUNT]

; written++
0x00002F60       ADD R10 R10 1
0x00002F64       B pipe_write_retry

pipe_write_done:
; wake readers
0x00002F6C       MOV R1 R9
0x00002F70       ADD R1 R1 PIPE_RWAIT
0x00002F74       BL waitq_wake_all
0x00002F7C       MOV R1 R10      ;written bytes
0x00002F80       POP LR
0x00002F84       RET

pipe_write_badptr:
0x00002F88       LI R1 ERR_FAULT
0x00002F90       POP LR
0x00002F94       RET

pipe_write_empty:
0x00002F98       LI R1 0
0x00002FA0       POP LR
0x00002FA4       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00002FA8       MOV R1 R9
0x00002FAC       ADD R1 R1 PIPE_WWAIT
0x00002FB0       LI R2 WAIT_PIPE_WRITE
0x00002FB8       BL waitq_prepare_sleep
    ; race check
0x00002FC0       LDW R4 [R9 + PIPE_COUNT]
0x00002FC4       LI R2 256
0x00002FCC       CMP R4 R2
0x00002FD0       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00002FD8       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00002FE0       B pipe_write_retry      ; unblocked! go write!

fd_remove:
 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
0x00002FE8       CMP R1 3
0x00002FEC       BLT fd_remove_invalid

0x00002FF4       CMP R1 MAX_FDS
0x00002FF8       BGE fd_remove_invalid

0x00003000       MOV R8 R1

; macro: GET_CURR_TASK_IDX R4
0x00003004   LI R1 CURRENT_TASK
0x0000300C   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00003010   LI R1 TASK_SIZE
0x00003018   MUL R3 R4 R1
0x0000301C   LI R4 tasks
0x00003024   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x00003028   LDW R4 [R4 + TASK_FD_TABLE]

0x0000302C       SHL R5 R8 2
0x00003030       ADD R6 R4 R5

0x00003034       LDW R1 [R6]
0x00003038       CMP R1 0
0x0000303C       BEQ fd_remove_invalid

0x00003044       LI R7 0
0x0000304C       STW R7 [R6]

0x00003050       RET

fd_remove_invalid:
0x00003054       LI R1 0
0x0000305C       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003060       LDW R1 [SP + TF_R1]
0x00003064       LDW R2 [SP + TF_R2]
0x00003068       LDW R3 [SP + TF_R3]

0x0000306C       MOV R7 R2               ; save user buffer
0x00003070       MOV R6 R3               ; save length
0x00003074       PUSH R7
0x00003078       PUSH R6
0x0000307C       LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
0x00003084       BL fetch_fd_entry
0x0000308C       POP R6
0x00003090       POP R7
0x00003094       CMP R1 0
0x00003098       BEQ bad_fd
0x000030A0       MOV R9 R1               ; file object pointer
0x000030A4       MOV R1 R9
0x000030A8       MOV R2 R7
0x000030AC       MOV R3 R6
0x000030B0       BL file_read
0x000030B8       STW R1 [SP + TF_R1]

0x000030BC       B trap_restore

con_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x000030C4       PUSH LR
0x000030C8       MOV R9 R1
0x000030CC       MOV R7 R2
0x000030D0       MOV R6 R3
0x000030D4       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x000030D8       CMP R6 0
0x000030DC       BEQ read_done

0x000030E4       PUSH R7
0x000030E8       PUSH R6
0x000030EC       PUSH R9
0x000030F0       MOV R1 R7
0x000030F4       MOV R2 R6
0x000030F8       LI R3 1                ; write access for destination buffer
0x00003100       BL user_buffer_valid_range
0x00003108       POP R9
0x0000310C       POP R6
0x00003110       POP R7
0x00003114       CMP R1 1
0x00003118       BNE driver_bad_pointer

read_wait_uart_rx:
0x00003120       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003124       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00003128       AND R5 R5 1                 ; bit 0 = RX_READY
0x0000312C       CMP R5 0
0x00003130       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

0x00003138       PUSH R7

; macro: GET_CURR_TASK_IDX R4
0x0000313C   LI R1 CURRENT_TASK
0x00003144   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003148   LI R1 TASK_SIZE
0x00003150   MUL R3 R4 R1
0x00003154   LI R5 tasks
0x0000315C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003160   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003164       MOV R2 R6
0x00003168       MOV R3 R9
0x0000316C       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)

0x00003174       POP R7

0x00003178       CMP R1 0
0x0000317C       BEQ read_done

0x00003184       MOV R2 R1              ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x00003188   LI R1 CURRENT_TASK
0x00003190   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x00003194   LI R1 TASK_SIZE
0x0000319C   MUL R3 R5 R1
0x000031A0   LI R4 tasks
0x000031A8   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000031AC   LDW R4 [R4 + TASK_KBUF_RD_PTR]

0x000031B0       MOV R1 R7              ; user destination
0x000031B4       BL copy_to_user        ; copy from kernel buffer to user buffer

0x000031BC       POP LR
0x000031C0       RET

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x000031C4       LI R1 uart_rx_waitq
0x000031CC       LI R2 WAIT_UART_RX
0x000031D4       BL waitq_prepare_sleep

0x000031DC       LDW R4 [R9 + UARTDEV_MMIO]
0x000031E0       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x000031E4       AND R10 R10 1
0x000031E8       CMP R10 0
0x000031EC       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x000031F4       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x000031FC       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00003204       LI R1 uart_rx_waitq
0x0000320C       BL waitq_cancel_sleep_current

0x00003214       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x0000321C       LI R1 0
0x00003224       POP LR
0x00003228       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x0000322C       LDW R1 [SP + TF_R1]
0x00003230       LDW R2 [SP + TF_R2]
0x00003234       LDW R3 [SP + TF_R3]
; first fetch file from procs fd_table and check flags for match access WRITE /READ
0x00003238       MOV R7 R2               ; save user buffer
0x0000323C       MOV R6 R3               ; save length
0x00003240       PUSH R7
0x00003244       PUSH R6
0x00003248       LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
0x00003250       BL fetch_fd_entry       ;input R1 fd on exit R1 - file ptr  => r1=fetch_fd_entry(fd=r1)
0x00003258       POP R6
0x0000325C       POP R7
0x00003260       CMP R1 0
0x00003264       BEQ bad_fd              ;if flags file and in r2 dont match
0x0000326C       MOV R9 R1               ; file object pointer
0x00003270       MOV R1 R9
0x00003274       MOV R2 R7
0x00003278       MOV R3 R6
0x0000327C       BL file_write           ; call file write R1 = file ptr, R2 = user buffer, R3 = len
0x00003284       STW R1 [SP + TF_R1]

0x00003288       B trap_restore

con_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00003290       PUSH LR
0x00003294       MOV R9 R1
0x00003298       MOV R7 R2
0x0000329C       MOV R6 R3
0x000032A0       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x000032A4       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x000032AC       CMP R6 0
0x000032B0       BEQ write_done             ;0 bytes

0x000032B8       LI R2 KBUFFER_SIZE
0x000032C0       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x000032C4       BLT write_chunk_small
0x000032CC       LI R2 KBUFFER_SIZE

0x000032D4       B write_chunk

write_chunk_small:
0x000032DC       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x000032E0       PUSH R7
0x000032E4       PUSH R6
0x000032E8       PUSH R9
0x000032EC       PUSH R8
0x000032F0       MOV R1 R7
0x000032F4       MOV R2 R2
0x000032F8       LI R3 0                ; read access for source buffer
0x00003300       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00003308       POP R8
0x0000330C       POP R9
0x00003310       POP R6
0x00003314       POP R7
0x00003318       CMP R1 1
0x0000331C       BNE driver_bad_pointer

0x00003324       PUSH R7
0x00003328       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x0000332C   LI R1 CURRENT_TASK
0x00003334   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003338   LI R1 TASK_SIZE
0x00003340   MUL R3 R4 R1
0x00003344   LI R5 tasks
0x0000334C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00003350   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00003354       MOV R1 R7
0x00003358       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00003360       MOV R10 R1             ; bytes copied
0x00003364       POP R6
0x00003368       POP R7

0x0000336C       PUSH R7
0x00003370       PUSH R9
0x00003374       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x00003378       LDW R1 [R9 + UARTDEV_MMIO]
0x0000337C       LDW R2 [R1 + 4]
0x00003380       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00003384       CMP R2 0
0x00003388       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00003390   LI R1 CURRENT_TASK
0x00003398   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000339C   LI R1 TASK_SIZE
0x000033A4   MUL R3 R4 R1
0x000033A8   LI R5 tasks
0x000033B0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x000033B4   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x000033B8       MOV R2 R10
0x000033BC       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x000033C0       BL device_write
0x000033C8       POP R6
0x000033CC       POP R9
0x000033D0       POP R7

0x000033D4       CMP R1 0        ;nothing is written - go again
0x000033D8       BEQ write_loop

0x000033E0       ADD R8 R8 R1     ;update ptrs
0x000033E4       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x000033E8       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x000033EC       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x000033F4       LI R1 uart_tx_waitq
0x000033FC       LI R2 WAIT_UART_TX
0x00003404       BL waitq_prepare_sleep

0x0000340C       LDW R1 [R9 + UARTDEV_MMIO]
0x00003410       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00003414       AND R2 R2 2
0x00003418       CMP R2 0
0x0000341C       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00003424       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x0000342C       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00003434       LI R1 uart_tx_waitq
0x0000343C       BL waitq_cancel_sleep_current

0x00003444       B write_wait_uart_tx

write_done:
0x0000344C       MOV R1 R8
0x00003450       POP LR
0x00003454       RET

driver_bad_pointer:
0x00003458       LI R1 ERR_FAULT
0x00003460       POP LR
0x00003464       RET

bad_fd:
0x00003468       LI R1 ERR_BADF
0x00003470       STW R1 [SP + TF_R1]

0x00003474       B trap_restore

bad_pointer:
0x0000347C       LI R1 ERR_FAULT
0x00003484       STW R1 [SP + TF_R1]

0x00003488       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00003490       LDW R4 [R1 + FILE_OPS]
0x00003494       LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
0x00003498       JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x0000349C       LDW R4 [R1 + FILE_OPS]
0x000034A0       LDW R4 [R4 + FOPS_WRITE]    ; get write function xdev_write from ops
0x000034A4       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000034A8       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000034B0       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x000034B8       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000034BC       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x000034C4       CMP R5 R2                   ; have we read enough bytes?
0x000034C8       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x000034D0       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000034D4       AND R6 R6 1                 ; bit 0 = RX_READY
0x000034D8       CMP R6 0
0x000034DC       BEQ dr_done                 ; no more buffered input available

0x000034E4       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x000034E8       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x000034EC       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x000034F0       CMP R7 10
0x000034F4       BEQ dr_done

0x000034FC       B dr_loop

dr_done:
0x00003504       MOV R1 R5                   ; return number of bytes actually read
0x00003508       RET

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

0x0000350C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003510       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x00003518       CMP R5 R2                   ; have we written all bytes?
0x0000351C       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00003524       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00003528       AND R6 R6 2                 ; bit 1 = TX_READY
0x0000352C       CMP R6 0
0x00003530       BEQ dcw_done

0x00003538       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x0000353C       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00003540       ADD R5 R5 1
0x00003544       B dcw_loop

dcw_done:
0x0000354C       MOV R1 R5                   ; return number of bytes written
0x00003550       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00003554       LI R1 0
0x0000355C       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00003560       PUSH LR
0x00003564       MOV R6 R3
0x00003568       CMP R6 0
0x0000356C       BEQ null_write_done

0x00003574       PUSH R6
0x00003578       MOV R1 R2
0x0000357C       MOV R2 R6
0x00003580       LI R3 0                    ; read access from user source
0x00003588       BL user_buffer_valid_range
0x00003590       POP R6
0x00003594       CMP R1 1
0x00003598       BNE null_write_badptr

null_write_done:
0x000035A0       MOV R1 R6
0x000035A4       POP LR
0x000035A8       RET

null_write_badptr:
0x000035AC       LI R1 ERR_FAULT
0x000035B4       POP LR
0x000035B8       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, 3)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

0x000035BC       CMP R1 0
0x000035C0       BLT fd_invalid
0x000035C8       CMP R1 MAX_FDS
0x000035CC       BGE fd_invalid

0x000035D4       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x000035D8   LI R1 CURRENT_TASK
0x000035E0   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000035E4   LI R1 TASK_SIZE
0x000035EC   MUL R3 R4 R1
0x000035F0   LI R4 tasks
0x000035F8   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000035FC   LDW R4 [R4 + TASK_FD_TABLE]

0x00003600       SHL R5 R8 2
0x00003604       ADD R4 R4 R5                ;r4=fd*4+FD_TABLE = file entry according to fd
0x00003608       LDW R1 [R4]                 ; R1 = file ptr
0x0000360C       LDW R6 [R1 + FILE_FLAGS]
0x00003610       AND R6 R6 R2
0x00003614       CMP R6 R2                   ;check file flags R2 input R6 from file
0x00003618       BNE fd_invalid

0x00003620       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x00003624       LI R1 0
0x0000362C       RET

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
0x00003630       PUSH R10
0x00003634       PUSH R11
0x00003638       PUSH R12

0x0000363C       LI R4 0
0x00003644       CMP R2 R4
0x00003648       BEQ uv_valid

0x00003650       LI R4 USER_BASE
0x00003658       CMP R1 R4
0x0000365C       BLT uv_invalid

0x00003664       LI R4 USER_LIMIT
0x0000366C       ADD R5 R1 R2
0x00003670       SUB R5 R5 1
0x00003674       CMP R5 R1
0x00003678       BLT uv_invalid
0x00003680       CMP R5 R4
0x00003684       BGT uv_invalid
0x0000368C       MOV R11 R1              ; save start address; task macros clobber R1
0x00003690       MOV R12 R5              ; save end address for page calculation
0x00003694       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x00003698   LI R1 CURRENT_TASK
0x000036A0   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x000036A4   LI R1 TASK_SIZE
0x000036AC   MUL R3 R6 R1
0x000036B0   LI R6 tasks
0x000036B8   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x000036BC   LDW R6 [R6 + TASK_PTBR]
0x000036C0       LI R7 TASK0_PTBR

0x000036C8       CMP R6 R7
0x000036CC       BEQ uv_ptbr0
0x000036D4       LI R7 TASK1_PTBR
0x000036DC       CMP R6 R7
0x000036E0       BEQ uv_ptbr1
0x000036E8       LI R7 TASK2_PTBR
0x000036F0       CMP R6 R7
0x000036F4       BEQ uv_ptbr2
0x000036FC       B uv_invalid

uv_ptbr0:
0x00003704       LI R6 PTBR0_VA
0x0000370C       B uv_check_pages
uv_ptbr1:
0x00003714       LI R6 PTBR1_VA
0x0000371C       B uv_check_pages
uv_ptbr2:
0x00003724       LI R6 PTBR2_VA

uv_check_pages:
0x0000372C       SHR R7 R11 12
0x00003730       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00003734       CMP R7 R8
0x00003738       BGT uv_valid
0x00003740       SHL R9 R7 2
0x00003744       ADD R9 R9 R6
0x00003748       LDW R10 [R9]
0x0000374C       AND R5 R10 PTE_P
0x00003750       CMP R5 0
0x00003754       BEQ uv_invalid
0x0000375C       AND R5 R10 PTE_U
0x00003760       CMP R5 0
0x00003764       BEQ uv_invalid
0x0000376C       CMP R4 0
0x00003770       BEQ uv_check_read
0x00003778       AND R5 R10 PTE_W
0x0000377C       CMP R5 0
0x00003780       BEQ uv_invalid
0x00003788       B uv_next

uv_check_read:
0x00003790       AND R5 R10 PTE_R
0x00003794       CMP R5 0
0x00003798       BEQ uv_invalid

uv_next:
0x000037A0       ADD R7 R7 1
0x000037A4       B uv_loop

uv_valid:
0x000037AC       LI R1 1
0x000037B4       POP R12
0x000037B8       POP R11
0x000037BC       POP R10
0x000037C0       RET

uv_invalid:
0x000037C4       LI R1 0

0x000037CC       POP R12
0x000037D0       POP R11
0x000037D4       POP R10
0x000037D8       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x000037DC       LI R5 0
cfu_head:
0x000037E4       CMP R2 0
0x000037E8       BEQ cfu_done
0x000037F0       OR R6 R1 R4
0x000037F4       AND R6 R6 3
0x000037F8       CMP R6 0
0x000037FC       BEQ cfu_word
0x00003804       LDB R7 [R1]
0x00003808       STB R7 [R4]
0x0000380C       ADD R1 R1 1
0x00003810       ADD R4 R4 1
0x00003814       ADD R5 R5 1
0x00003818       SUB R2 R2 1
0x0000381C       B cfu_head
cfu_word:
0x00003824       CMP R2 4
0x00003828       BLT cfu_tail
0x00003830       LDW R7 [R1]
0x00003834       STW R7 [R4]
0x00003838       ADD R1 R1 4
0x0000383C       ADD R4 R4 4
0x00003840       ADD R5 R5 4
0x00003844       SUB R2 R2 4
0x00003848       B cfu_word
cfu_tail:
0x00003850       CMP R2 0
0x00003854       BEQ cfu_done
0x0000385C       LDB R7 [R1]
0x00003860       STB R7 [R4]
0x00003864       ADD R1 R1 1
0x00003868       ADD R4 R4 1
0x0000386C       ADD R5 R5 1
0x00003870       SUB R2 R2 1
0x00003874       B cfu_tail
cfu_done:
0x0000387C       MOV R1 R5
0x00003880       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003884       LI R5 0
ctu_head:
0x0000388C       CMP R2 0
0x00003890       BEQ ctu_done
0x00003898       OR R6 R1 R4
0x0000389C       AND R6 R6 3
0x000038A0       CMP R6 0
0x000038A4       BEQ ctu_word
0x000038AC       LDB R7 [R4]
0x000038B0       STB R7 [R1]
0x000038B4       ADD R1 R1 1
0x000038B8       ADD R4 R4 1
0x000038BC       ADD R5 R5 1
0x000038C0       SUB R2 R2 1
0x000038C4       B ctu_head
ctu_word:
0x000038CC       CMP R2 4
0x000038D0       BLT ctu_tail
0x000038D8       LDW R7 [R4]
0x000038DC       STW R7 [R1]
0x000038E0       ADD R1 R1 4
0x000038E4       ADD R4 R4 4
0x000038E8       ADD R5 R5 4
0x000038EC       SUB R2 R2 4
0x000038F0       B ctu_word
ctu_tail:
0x000038F8       CMP R2 0
0x000038FC       BEQ ctu_done
0x00003904       LDB R7 [R4]
0x00003908       STB R7 [R1]
0x0000390C       ADD R1 R1 1
0x00003910       ADD R4 R4 1
0x00003914       ADD R5 R5 1
0x00003918       SUB R2 R2 1
0x0000391C       B ctu_tail
ctu_done:
0x00003924       MOV R1 R5
0x00003928       RET

handle_debug:
    ; Debug trap - just return
0x0000392C       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00003934       CSRR R1 STVAL

0x00003938       CMP R1 0
0x0000393C       BEQ handle_timer_irq

0x00003944       CMP R1 1
0x00003948       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00003950       LI R2 0x00102000
0x00003958       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x0000395C       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00003964       LI R2 0x00102000
0x0000396C       LI R3 0
0x00003974       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Yield the CPU (reschedule and switch tasks)
0x00003978       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00003980       LI R2 0x00102000
0x00003988       LI R3 1
0x00003990       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00003994       LI R1 uart_rx_waitq
0x0000399C       BL waitq_wake_all
0x000039A4       LI R1 uart_tx_waitq
0x000039AC       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x000039B4       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x000039BC       POP R1                  ; stval, informational only
0x000039C0       POP R1                  ; scause, informational only
0x000039C4       POP R1
0x000039C8       CSRW SSTATUS R1
0x000039CC       POP R1
0x000039D0       CSRW SFLAGS R1
0x000039D4       POP R1
0x000039D8       CSRW SEPC R1
0x000039DC       POP R1                  ; interrupted task SP
0x000039E0       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x000039E4       POP R15
0x000039E8       POP R14
0x000039EC       POP R12
0x000039F0       POP R11
0x000039F4       POP R10
0x000039F8       POP R9
0x000039FC       POP R8
0x00003A00       POP R7
0x00003A04       POP R6
0x00003A08       POP R5
0x00003A0C       POP R4
0x00003A10       POP R3
0x00003A14       POP R2
0x00003A18       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00003A1C       CSRRW SP SSCRATCH SP
0x00003A20       SRET


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
.EQU TASK_SIZE,   44


; =============================================================
; Task table
; =============================================================

.ORG 0x7000

tasks:
    .SPACE 132             ; 3 tasks * 44 bytes

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

.EQU MAX_FDS, 16

task0_fd_table:
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

0x000078C7       PUSH R9
0x000078CB       PUSH R10

0x000078CF       MOV R9 R1                  ; preserve wait queue pointer
0x000078D3       MOV R10 R2                 ; preserve debug wait reason

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x000078D7   LI R1 CURRENT_TASK
0x000078DF   LDW R2 [R1]

0x000078E3       LI R4 1
0x000078EB       SHL R4 R4 R2               ; R4 = bit for current task
0x000078EF       LDW R5 [R9 + WQ_MASK]
0x000078F3       OR R5 R5 R4
0x000078F7       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x000078FB   LI R1 TASK_SIZE
0x00007903   MUL R3 R2 R1
0x00007907   LI R5 tasks
0x0000790F   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00007913   LI R1 TASK_BLOCKED_IO
0x0000791B   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x0000791F   STW R10 [R5 + TASK_WAIT]

0x00007923       POP R10
0x00007927       POP R9
0x0000792B       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x0000792F       PUSH R9

0x00007933       MOV R9 R1
; macro: GET_CURR_TASK_IDX R2
0x00007937   LI R1 CURRENT_TASK
0x0000793F   LDW R2 [R1]

0x00007943       LDW R4 [R9 + WQ_MASK]
0x00007947       CMP R2 0
0x0000794B       BEQ wq_cancel_task0
0x00007953       CMP R2 1
0x00007957       BEQ wq_cancel_task1

0x0000795F       LI R5 3                    ; clear bit 2, keep bits 0..1
0x00007967       AND R4 R4 R5
0x0000796B       B wq_cancel_store

wq_cancel_task0:
0x00007973       LI R5 6                    ; clear bit 0, keep bits 1..2
0x0000797B       AND R4 R4 R5
0x0000797F       B wq_cancel_store

wq_cancel_task1:
0x00007987       LI R5 5                    ; clear bit 1, keep bits 0 and 2
0x0000798F       AND R4 R4 R5

wq_cancel_store:
0x00007993       STW R4 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00007997   LI R1 TASK_SIZE
0x0000799F   MUL R3 R2 R1
0x000079A3   LI R5 tasks
0x000079AB   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x000079AF   LI R1 TASK_READY
0x000079B7   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x000079BB   LI R1 WAIT_NONE
0x000079C3   STW R1 [R5 + TASK_WAIT]

0x000079C7       POP R9
0x000079CB       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000079CF       PUSH LR
0x000079D3       BL schedule_call
0x000079DB       POP LR
0x000079DF       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x000079E3       PUSH LR

0x000079E7       MOV R9 R1
0x000079EB       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x000079EF       LI R10 0
0x000079F7       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x000079FB       LI R2 0                    ; task index

wq_wake_loop:
0x00007A03       CMP R2 3
0x00007A07       BGE wq_wake_done

0x00007A0F       LI R3 1
0x00007A17       SHL R3 R3 R2               ; R3 = bit for task R2
0x00007A1B       AND R4 R8 R3
0x00007A1F       CMP R4 0
0x00007A23       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00007A2B   LI R1 TASK_SIZE
0x00007A33   MUL R3 R2 R1
0x00007A37   LI R5 tasks
0x00007A3F   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00007A43   LI R1 TASK_READY
0x00007A4B   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00007A4F   LI R1 WAIT_NONE
0x00007A57   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00007A5B       ADD R2 R2 1
0x00007A5F       B wq_wake_loop

wq_wake_done:
0x00007A67       POP LR
0x00007A6B       RET

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

0x00007A6F       LI R2 0                      ; index

fa_loop:
0x00007A77       CMP R2 MAX_FILES
0x00007A7B       BGE fa_fail

0x00007A83       SHL R3 R2 2                  ; index * 4
0x00007A87       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00007A8F       ADD R4 R4 R3

0x00007A93       LDW R5 [R4]
0x00007A97       CMP R5 0
0x00007A9B       BEQ fa_found

0x00007AA3       ADD R2 R2 1
0x00007AA7       B fa_loop

fa_found:
0x00007AAF       LI R5 1
0x00007AB7       STW R5 [R4]                  ; mark slot used

0x00007ABB       LI R4 FILE_SIZE
0x00007AC3       MUL R6 R2 R4

0x00007AC7       LI R1 file_pool
0x00007ACF       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x00007AD3       LI R7 0

0x00007ADB       STW R7 [R1 + FILE_OPS]
0x00007ADF       STW R7 [R1 + FILE_PRIVATE]
0x00007AE3       STW R7 [R1 + FILE_OFFSET]
0x00007AE7       STW R7 [R1 + FILE_FLAGS]

0x00007AEB       RET

fa_fail:
0x00007AEF       LI R1 0
0x00007AF7       RET

;=================================================================
; file_free:
; input:
; R1 = pointer to FILE object
; none output
;=================================================================

file_free:

0x00007AFB       LI R2 file_pool
0x00007B03       SUB R3 R1 R2                 ; offset from pool base

0x00007B07       LI R4 FILE_SIZE
0x00007B0F       DIV R5 R3 R4                 ; slot number

0x00007B13       SHL R5 R5 2                  ; slot * 4

0x00007B17       LI R6 file_used
0x00007B1F       ADD R6 R6 R5

0x00007B23       LI R7 0
0x00007B2B       STW R7 [R6]                  ; mark free

0x00007B2F       RET


; ================================================================
; INIT SCHEDULER
; ================================================================

init_scheduler:
0x00007B33       MOV R12 SP ;important we save kernel sp becuse we form stack frame at tasks SPs

    ; ------------------------------------------------
    ; Task 0
    ; ------------------------------------------------

    ;================================================================
    ; Build the initial trapframe on the task's kernel stack. It has
    ; the same shape as an IRQ-created trapframe, so first dispatch and
    ; later preemptive resumes use the exact same restore path.
    ;================================================================

0x00007B37       LI SP TASK0_KSTACK_TOP

0x00007B3F       LI R1 0
0x00007B47       PUSH R1                  ; R1
0x00007B4B       PUSH R1                  ; R2
0x00007B4F       PUSH R1                  ; R3
0x00007B53       PUSH R1                  ; R4
0x00007B57       PUSH R1                  ; R5
0x00007B5B       PUSH R1                  ; R6
0x00007B5F       PUSH R1                  ; R7
0x00007B63       PUSH R1                  ; R8
0x00007B67       PUSH R1                  ; R9
0x00007B6B       PUSH R1                  ; R10
0x00007B6F       PUSH R1                  ; R11
0x00007B73       PUSH R1                  ; R12
0x00007B77       PUSH R1                  ; R14
0x00007B7B       PUSH R1                  ; R15
0x00007B7F       LI R1 TASK0_USTACK_TOP
0x00007B87       PUSH R1                  ; interrupted task SP restored by CSRRW before SRET
0x00007B8B       LI R1 idle_task
0x00007B93       PUSH R1                  ; sepc - this is new place of PC in trap frame
0x00007B97       LI R1 0
0x00007B9F       PUSH R1                  ; sflags
0x00007BA3       LI R1 0x120
0x00007BAB       PUSH R1                  ; sstatus.SPIE|SPP: idle resumes as supervisor task
0x00007BAF       LI R1 0
0x00007BB7       PUSH R1                  ; scause
0x00007BBB       PUSH R1                  ; stval - other valuable s-data on top (or bottom-)

0x00007BBF       LI R2 tasks
0x00007BC7       MOV R1 SP
; macro: TASK_SET_KSP R2, R1     ; save kernel trapframe SP
0x00007BCB   STW R1 [R2 + TASK_KSP]

0x00007BCF       LI R1 TASK0_USTACK_TOP
; macro: TASK_SET_USP R2, R1     ; save initial task stack SP for debug/metadata
0x00007BD7   STW R1 [R2 + TASK_USP]

0x00007BDB       LI R1 idle_task
; macro: TASK_SET_PC R2, R1      ;start PC of the task
0x00007BE3   STW R1 [R2 + TASK_PC]

; macro: TASK_SET_STATE R2, TASK_READY ;set this task as as ready to run
0x00007BE7   LI R1 TASK_READY
0x00007BEF   STW R1 [R2 + TASK_STATE]

0x00007BF3       LI R1 0
; macro: TASK_SET_PID R2, R1      ;set PID=0 for this task
0x00007BFB   STW R1 [R2 + TASK_PID]

0x00007BFF       LI R1 TASK0_PTBR            ;set page table ptr
; macro: TASK_SET_PTBR R2, R1
0x00007C07   STW R1 [R2 + TASK_PTBR]

0x00007C0B       LI R1 task0_fd_table
; macro: TASK_SET_FD_TABLE R2, R1 ;set fd_table ptr
0x00007C13   STW R1 [R2 + TASK_FD_TABLE]

; macro: TASK_SET_WAIT R2, WAIT_NONE ;set wait reason field
0x00007C17   LI R1 WAIT_NONE
0x00007C1F   STW R1 [R2 + TASK_WAIT]
; macro: TASK_SET_RESUME R2, RESUME_TRAP ;set sleep switch kernel/user depending where it z-z-z
0x00007C23   LI R1 RESUME_TRAP
0x00007C2B   STW R1 [R2 + TASK_RESUME]
; macro: TASK_SET_KBUF_WR R2, KBUFFER_WR_0 ;set this task kernel buffers rd/wr
0x00007C2F   LI R1 KBUFFER_WR_0
0x00007C37   STW R1 [R2 + TASK_KBUF_WR_PTR]
; macro: TASK_SET_KBUF_RD R2, KBUFFER_RD_0
0x00007C3B   LI R1 KBUFFER_RD_0
0x00007C43   STW R1 [R2 + TASK_KBUF_RD_PTR]
    ;when we can alloc and exec and fork
    ;special mem subsystem will init/alloc/dealloc all that automatically

    ; ------------------------------------------------
    ; Task 1 - do the same
    ; ------------------------------------------------

0x00007C47       LI SP TASK1_KSTACK_TOP
0x00007C4F       LI R1 0
0x00007C57       PUSH R1                  ; R1
0x00007C5B       PUSH R1                  ; R2
0x00007C5F       PUSH R1                  ; R3
0x00007C63       PUSH R1                  ; R4
0x00007C67       PUSH R1                  ; R5
0x00007C6B       PUSH R1                  ; R6
0x00007C6F       PUSH R1                  ; R7
0x00007C73       PUSH R1                  ; R8
0x00007C77       PUSH R1                  ; R9
0x00007C7B       PUSH R1                  ; R10
0x00007C7F       PUSH R1                  ; R11
0x00007C83       PUSH R1                  ; R12
0x00007C87       PUSH R1                  ; R14
0x00007C8B       PUSH R1                  ; R15
0x00007C8F       LI R1 TASK1_USTACK_TOP
0x00007C97       PUSH R1                  ; interrupted task SP
0x00007C9B       LI R1 TASK_A_START
0x00007CA3       PUSH R1                  ; sepc
0x00007CA7       LI R1 0
0x00007CAF       PUSH R1                  ; sflags
0x00007CB3       LI R1 0x20
0x00007CBB       PUSH R1                  ; sstatus.SPIE
0x00007CBF       LI R1 0
0x00007CC7       PUSH R1                  ; scause
0x00007CCB       PUSH R1                  ; stval

0x00007CCF       LI R2 tasks
0x00007CD7       ADD R2 R2 TASK_SIZE

0x00007CDB       MOV R1 SP
; macro: TASK_SET_KSP R2, R1
0x00007CDF   STW R1 [R2 + TASK_KSP]

0x00007CE3       LI R1 TASK1_USTACK_TOP
; macro: TASK_SET_USP R2, R1
0x00007CEB   STW R1 [R2 + TASK_USP]

0x00007CEF       LI R1 TASK_A_START
; macro: TASK_SET_PC R2, R1
0x00007CF7   STW R1 [R2 + TASK_PC]

; macro: TASK_SET_STATE R2, TASK_READY
0x00007CFB   LI R1 TASK_READY
0x00007D03   STW R1 [R2 + TASK_STATE]

0x00007D07       LI R1 1
; macro: TASK_SET_PID R2, R1
0x00007D0F   STW R1 [R2 + TASK_PID]

0x00007D13       LI R1 TASK1_PTBR
; macro: TASK_SET_PTBR R2, R1
0x00007D1B   STW R1 [R2 + TASK_PTBR]

0x00007D1F       LI R1 task1_fd_table
; macro: TASK_SET_FD_TABLE R2, R1
0x00007D27   STW R1 [R2 + TASK_FD_TABLE]
; macro: TASK_SET_WAIT R2, WAIT_NONE
0x00007D2B   LI R1 WAIT_NONE
0x00007D33   STW R1 [R2 + TASK_WAIT]
; macro: TASK_SET_RESUME R2, RESUME_TRAP
0x00007D37   LI R1 RESUME_TRAP
0x00007D3F   STW R1 [R2 + TASK_RESUME]
; macro: TASK_SET_KBUF_WR R2, KBUFFER_WR_1
0x00007D43   LI R1 KBUFFER_WR_1
0x00007D4B   STW R1 [R2 + TASK_KBUF_WR_PTR]
; macro: TASK_SET_KBUF_RD R2, KBUFFER_RD_1
0x00007D4F   LI R1 KBUFFER_RD_1
0x00007D57   STW R1 [R2 + TASK_KBUF_RD_PTR]

    ; ------------------------------------------------
    ; Task 2 - same
    ; ------------------------------------------------

0x00007D5B       LI SP TASK2_KSTACK_TOP
0x00007D63       LI R1 0
0x00007D6B       PUSH R1                  ; R1
0x00007D6F       PUSH R1                  ; R2
0x00007D73       PUSH R1                  ; R3
0x00007D77       PUSH R1                  ; R4
0x00007D7B       PUSH R1                  ; R5
0x00007D7F       PUSH R1                  ; R6
0x00007D83       PUSH R1                  ; R7
0x00007D87       PUSH R1                  ; R8
0x00007D8B       PUSH R1                  ; R9
0x00007D8F       PUSH R1                  ; R10
0x00007D93       PUSH R1                  ; R11
0x00007D97       PUSH R1                  ; R12
0x00007D9B       PUSH R1                  ; R14
0x00007D9F       PUSH R1                  ; R15
0x00007DA3       LI R1 TASK2_USTACK_TOP
0x00007DAB       PUSH R1                  ; interrupted task SP
0x00007DAF       LI R1 TASK_B_START
0x00007DB7       PUSH R1                  ; sepc
0x00007DBB       LI R1 0
0x00007DC3       PUSH R1                  ; sflags
0x00007DC7       LI R1 0x20
0x00007DCF       PUSH R1                  ; sstatus.SPIE
0x00007DD3       LI R1 0
0x00007DDB       PUSH R1                  ; scause
0x00007DDF       PUSH R1                  ; stval

0x00007DE3       LI R2 tasks
0x00007DEB       LI R3 TASK_SIZE
0x00007DF3       ADD R2 R2 R3
0x00007DF7       ADD R2 R2 R3

0x00007DFB       MOV R1 SP
; macro: TASK_SET_KSP R2, R1
0x00007DFF   STW R1 [R2 + TASK_KSP]

0x00007E03       LI R1 TASK2_USTACK_TOP
; macro: TASK_SET_USP R2, R1
0x00007E0B   STW R1 [R2 + TASK_USP]

0x00007E0F       LI R1 TASK_B_START
; macro: TASK_SET_PC R2, R1
0x00007E17   STW R1 [R2 + TASK_PC]

; macro: TASK_SET_STATE R2, TASK_READY
0x00007E1B   LI R1 TASK_READY
0x00007E23   STW R1 [R2 + TASK_STATE]

0x00007E27       LI R1 2
; macro: TASK_SET_PID R2, R1
0x00007E2F   STW R1 [R2 + TASK_PID]

0x00007E33       LI R1 TASK2_PTBR
; macro: TASK_SET_PTBR R2, R1
0x00007E3B   STW R1 [R2 + TASK_PTBR]

0x00007E3F       LI R1 task2_fd_table                ;per process fd_table
; macro: TASK_SET_FD_TABLE R2, R1
0x00007E47   STW R1 [R2 + TASK_FD_TABLE]
; macro: TASK_SET_WAIT R2, WAIT_NONE
0x00007E4B   LI R1 WAIT_NONE
0x00007E53   STW R1 [R2 + TASK_WAIT]
; macro: TASK_SET_RESUME R2, RESUME_TRAP
0x00007E57   LI R1 RESUME_TRAP
0x00007E5F   STW R1 [R2 + TASK_RESUME]
; macro: TASK_SET_KBUF_WR R2, KBUFFER_WR_2
0x00007E63   LI R1 KBUFFER_WR_2
0x00007E6B   STW R1 [R2 + TASK_KBUF_WR_PTR]
; macro: TASK_SET_KBUF_RD R2, KBUFFER_RD_2
0x00007E6F   LI R1 KBUFFER_RD_2
0x00007E77   STW R1 [R2 + TASK_KBUF_RD_PTR]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x00007E7B       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x00007E83   LI R1 CURRENT_TASK
0x00007E8B   STW R2 [R1]

0x00007E8F       MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00007E93       RET

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00007E97   LI R1 CURRENT_TASK
0x00007E9F   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x00007EA3       ADD R3 R2 1

wrap_check:

0x00007EA7       CMP R3 3
0x00007EAB       BLT check_task
0x00007EB3       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x00007EBB       LI R4 TASK_SIZE
0x00007EC3       MUL R5 R3 R4
0x00007EC7       LI R6 tasks
0x00007ECF       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00007ED3       LDW R7 [R5 + TASK_STATE]

0x00007ED7       CMP R7 1
0x00007EDB       BEQ do_switch
    ; if not ready go to next task in list
0x00007EE3       ADD R3 R3 1
0x00007EE7       B wrap_check

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
0x00007EEF   LI R1 CURRENT_TASK
0x00007EF7   STW R3 [R1]
0x00007EFB       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x00007EFF   LI R1 TASK_SIZE
0x00007F07   MUL R3 R2 R1
0x00007F0B   LI R5 tasks
0x00007F13   ADD R5 R5 R3
0x00007F17       MOV R3 R8

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x00007F1B       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00007F1F   STW R7 [R5 + TASK_USP]

0x00007F23       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00007F27   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x00007F2B   LI R1 RESUME_TRAP
0x00007F33   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00007F37   LI R1 TASK_SIZE
0x00007F3F   MUL R3 R8 R1
0x00007F43   LI R5 tasks
0x00007F4B   ADD R5 R5 R3
0x00007F4F       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x00007F53   LDW R7 [R5 + TASK_PTBR]
0x00007F57       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x00007F5B   LDW SP [R5 + TASK_KSP]

; macro: TASK_GET_RESUME R7, R5
0x00007F5F   LDW R7 [R5 + TASK_RESUME]
0x00007F63       CMP R7 RESUME_KERNEL
0x00007F67       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x00007F6F       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x00007F77       PUSH R1
0x00007F7B       PUSH R2
0x00007F7F       PUSH R3
0x00007F83       PUSH R4
0x00007F87       PUSH R5
0x00007F8B       PUSH R6
0x00007F8F       PUSH R7
0x00007F93       PUSH R8
0x00007F97       PUSH R9
0x00007F9B       PUSH R10
0x00007F9F       PUSH R11
0x00007FA3       PUSH R12
0x00007FA7       PUSH R14
0x00007FAB       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00007FAF   LI R1 CURRENT_TASK
0x00007FB7   LDW R2 [R1]

0x00007FBB       ADD R3 R2 1

schedule_call_wrap_check:
0x00007FBF       CMP R3 3
0x00007FC3       BLT schedule_call_check_task
0x00007FCB       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00007FD3       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x00007FD7   LI R1 TASK_SIZE
0x00007FDF   MUL R3 R8 R1
0x00007FE3   LI R5 tasks
0x00007FEB   ADD R5 R5 R3
0x00007FEF       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00007FF3   LDW R7 [R5 + TASK_STATE]
0x00007FF7       CMP R7 TASK_READY               ; check it can be run
0x00007FFB       BEQ schedule_call_do_switch

0x00008003       ADD R3 R3 1
0x00008007       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x0000800F   LI R1 CURRENT_TASK
0x00008017   STW R3 [R1]
0x0000801B       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x0000801F   LI R1 TASK_SIZE
0x00008027   MUL R3 R2 R1
0x0000802B   LI R5 tasks
0x00008033   ADD R5 R5 R3
0x00008037       MOV R3 R8

0x0000803B       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x0000803F   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x00008043   LI R1 RESUME_KERNEL
0x0000804B   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x0000804F   LI R1 TASK_SIZE
0x00008057   MUL R3 R8 R1
0x0000805B   LI R5 tasks
0x00008063   ADD R5 R5 R3
0x00008067       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x0000806B   LDW R7 [R5 + TASK_PTBR]
0x0000806F       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x00008073   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x00008077   LDW R7 [R5 + TASK_RESUME]
0x0000807B       CMP R7 RESUME_KERNEL
0x0000807F       BEQ restore_kernel_context

0x00008087       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x0000808F       DISABLEINT                  ; RET does jump by LR(R15)
0x00008093       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x00008097       POP R14                     ; (in kernel)
0x0000809B       POP R12                     ; DI - to avoid int nesting
0x0000809F       POP R11
0x000080A3       POP R10
0x000080A7       POP R9
0x000080AB       POP R8
0x000080AF       POP R7
0x000080B3       POP R6
0x000080B7       POP R5
0x000080BB       POP R4
0x000080BF       POP R3
0x000080C3       POP R2
0x000080C7       POP R1
0x000080CB       RET

; need to define and allocate user stuff at user code
.EQU USER_WRITE_BUF, 0x6000
.EQU USER_READ_BUF,  0x6010
; task2 daee page
.org 0x6000
task_b_console_path:
    .ASCIIZ "/dev/console"

task_b_msg:
    .ASCIIZ "OPEN WRITE CLOSE\r\n"

task_b_msg_len:
    .WORD 18

open_fail_msg:
    .ASCIIZ "OPEN FAIL\r\n"

open_fail_msg_len:
    .WORD 11


; ================================================================
; TASKS
; ================================================================

.ORG 0x9000
; --TASK 0 ----------------------------------------------
idle_task:
0x00009000       ENABLEINT
0x00009004       LI R1 0
idle_loop:
0x0000900C       ADD R1 R1 1
    ;DEBUG 3
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

task_b_loop:

    ;=========================================
    ; fd = open("/dev/console", WRITE)
    ;=========================================

0x0001A000       LI R1 task_b_console_path
0x0001A008       LI R2 FD_FLAG_WRITE
0x0001A010       SVC SYS_OPEN
    ;DEBUG 1
0x0001A014       MOV R8 R1                  ; save fd

    ; open failed?
0x0001A018       CMP R8 0
0x0001A01C       BLT task_b_open_fail

    ;=========================================
    ; write(fd, msg, len)
    ;=========================================

0x0001A024       MOV R1 R8
0x0001A028       LI R2 task_b_msg
0x0001A030       LI R3 18
0x0001A038       SVC SYS_WRITE
    ;DEBUG 2

    ;=========================================
    ; close(fd)
    ;=========================================

0x0001A03C       MOV R1 R8
0x0001A040       SVC SYS_CLOSE
0x0001A044       DEBUG 2
    ;=========================================
    ; yield
    ;=========================================

0x0001A048       SVC SYS_YIELD

0x0001A04C       B task_b_loop

task_b_open_fail:

0x0001A054       LI R1 1
0x0001A05C       LI R2 open_fail_msg
0x0001A064       LI R3 11
0x0001A06C       SVC SYS_WRITE
0x0001A070       DEBUG 2

0x0001A074       SVC SYS_YIELD

0x0001A078       B task_b_loop

0x0001A080       li R1 10
read_write_loop:
0x0001A088       push R1
    ; Perform a read from stdin into a user buffer.
    ;TRACE 1
0x0001A08C       LI R1 0
    ;DEBUG 2
0x0001A094       LI R2 USER_READ_BUF
0x0001A09C       LI R3 CONSOLE_INPUT_LEN
0x0001A0A4       SVC SYS_READ
0x0001A0A8       DEBUG 1

    ;CMP R1 0
    ;BEQ task_b_done

    ; Echo the data back via SYS_WRITE.
0x0001A0AC       MOV R5 R1              ; save length returned by SYS_READ
0x0001A0B0       LI R1 1                ; stdout file descriptor
0x0001A0B8       LI R2 USER_READ_BUF
0x0001A0C0       MOV R3 R5
0x0001A0C4       SVC SYS_WRITE
0x0001A0C8       DEBUG 1
0x0001A0CC       pop R1
0x0001A0D0       sub R1 R1 1
0x0001A0D4       cmp r1 0
0x0001A0D8       BNE read_write_loop
    ;TRACE 0
task_b_done:
    ; Exit after the read/write test.
0x0001A0E0       DEBUG 1
0x0001A0E4       LI R1 SYS_EXIT
0x0001A0EC       SVC SYS_EXIT
[ASM] Built memory.img (106736 bytes)
