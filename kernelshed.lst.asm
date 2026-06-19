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

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
0x00002038           LI R1 tasks
0x00002040           LDW R2 [R1 + TASK_PTBR]
0x00002044           SETPTBR R2
0x00002048           LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
0x0000204C   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore
0x00002054           B trap_restore

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x0000205C       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x00002064       LI R2 trap_entry
0x0000206C       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x00002070       LI R2 trap_entry
0x00002078       STW R2 [R1+4]                ; IDT[1]
0x0000207C       STW R2 [R1+8]                ; IDT[2]
0x00002080       STW R2 [R1+12]               ; IDT[3]
0x00002084       STW R2 [R1+24]               ; IDT[6]
0x00002088       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x0000208C       SETIDTR R1
0x00002090       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
0x00002094       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x00002098       LI R1 page_bitmap
0x000020A0       LI R3 16
0x000020A8       BL mem_zero

0x000020B0       POP LR
0x000020B4       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x000020B8       PUSH LR
0x000020BC       PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
0x000020C0       LI R2 0x00000000      ;page 0 - boot (0000)
0x000020C8       LI R3 0x00000000
0x000020D0       LI R4 KERNEL_FLAGS
0x000020D8       bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x000020E0       LI R2 0x00001000      ; page for kernel buffers
0x000020E8       LI R3 0x00001000
0x000020F0       LI R4 KERNEL_FLAGS
0x000020F8       BL map_page

0x00002100       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x00002108       LI R3 0x00002000
0x00002110       LI R4 KERNEL_FLAGS
0x00002118       BL map_page

0x00002120       LI R2 0x00003000
0x00002128       LI R3 0x00003000
0x00002130       LI R4 KERNEL_FLAGS
0x00002138       BL map_page

0x00002140       LI R2 0x00004000
0x00002148       LI R3 0x00004000
0x00002150       LI R4 KERNEL_FLAGS
0x00002158       BL map_page

0x00002160       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x00002168       LI R3 0x00007000
0x00002170       LI R4 KERNEL_FLAGS
0x00002178       BL map_page

0x00002180       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x00002188       LI R3 0x00008000
0x00002190       LI R4 KERNEL_FLAGS
0x00002198       BL map_page


    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x000021A0       LI R2 0x00100000      ; UART physical and virtual base
0x000021A8       LI R3 0x00100000
0x000021B0       LI R4 KERNEL_FLAGS
0x000021B8       BL map_page

0x000021C0       LI R2 0x00101000      ; PIT physical and virtual base
0x000021C8       LI R3 0x00101000
0x000021D0       LI R4 KERNEL_FLAGS
0x000021D8       BL map_page

0x000021E0       LI R2 0x00102000      ; PIC physical and virtual base
0x000021E8       LI R3 0x00102000
0x000021F0       LI R4 KERNEL_FLAGS
0x000021F8       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x00002200       LI R12 PAGE_ALLOC_BASE
0x00002208       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x00002210       CMP R12 R7
0x00002214       BGE map_common_dynamic_done
0x0000221C       MOV R2 R12
0x00002220       MOV R3 R12
0x00002224       LI R4 KERNEL_FLAGS
0x0000222C       BL map_page
0x00002234       LI R6 PAGE_SIZE
0x0000223C       ADD R12 R12 R6
0x00002240       B map_common_dynamic_loop
map_common_dynamic_done:

0x00002248       POP R12
0x0000224C       POP LR
0x00002250       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002254       SHR R5 R2 12               ; VPN
0x00002258       SHL R5 R5 2                ; page-table byte offset
0x0000225C       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002260       STW R6 [R1 + R5]
0x00002264       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x00002268       LI R1 0x00102000
0x00002270       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x00002278       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x0000227C       LI R1 0x00101000
0x00002284       LI R2 2000
0x0000228C       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x00002290       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x00002298       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x0000229C       LI R1 0x00100000
0x000022A4       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000022AC       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x000022B0       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000022B4       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000022B8       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000022BC       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000022C0       PUSH R1
0x000022C4       PUSH R2
0x000022C8       PUSH R3
0x000022CC       PUSH R4
0x000022D0       PUSH R5
0x000022D4       PUSH R6
0x000022D8       PUSH R7
0x000022DC       PUSH R8
0x000022E0       PUSH R9
0x000022E4       PUSH R10
0x000022E8       PUSH R11
0x000022EC       PUSH R12
0x000022F0       PUSH R14
0x000022F4       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x000022F8       CSRR R1 SSCRATCH
0x000022FC       PUSH R1
0x00002300       CSRR R1 SEPC
0x00002304       PUSH R1
0x00002308       CSRR R1 SFLAGS
0x0000230C       PUSH R1
0x00002310       CSRR R1 SSTATUS
0x00002314       PUSH R1
0x00002318       CSRR R1 SCAUSE
0x0000231C       PUSH R1
0x00002320       CSRR R1 STVAL
0x00002324       PUSH R1

    ; Dispatch based on scause.
0x00002328       CSRR R1 SCAUSE
0x0000232C       CMP R1 0
0x00002330       BEQ handle_divide_zero

0x00002338       CMP R1 1
0x0000233C       BEQ handle_invalid_instr

0x00002344       CMP R1 2
0x00002348       BEQ handle_page_fault

0x00002350       CMP R1 3
0x00002354       BEQ handle_syscall

0x0000235C       CMP R1 6
0x00002360       BEQ handle_debug

0x00002368       CMP R1 16
0x0000236C       BEQ handle_irq

    ; Unknown cause - halt
0x00002374       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x00002378       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x00002380       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x00002388       HLT

0x0000238C       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x00002394       CSRR R2 STVAL

0x00002398       CMP R2 SYS_COUNT
0x0000239C       BGE syscall_unknown

0x000023A4       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000023AC       SHL R4 R2 2
0x000023B0       LDW R5 [R3 + R4]
0x000023B4       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000023B8       LI R1 ERR_NOSYS
0x000023C0       STW R1 [SP + TF_R1]
0x000023C4       B trap_restore

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

0x000023F0       LI R1 0
0x000023F8       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x000023FC       B schedule_and_switch

syscall_exit:
    ;================================================================
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002404   LI R1 CURRENT_TASK
0x0000240C   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002410   LI R1 TASK_SIZE
0x00002418   MUL R3 R2 R1
0x0000241C   LI R5 tasks
0x00002424   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_DEAD
0x00002428   LI R1 TASK_DEAD
0x00002430   STW R1 [R5 + TASK_STATE]

0x00002434       LI R1 0
0x0000243C       STW R1 [SP + TF_R1]         ; r1=0 - return success
0x00002440       B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002448   LI R1 CURRENT_TASK
0x00002450   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002454   LI R1 TASK_SIZE
0x0000245C   MUL R3 R2 R1
0x00002460   LI R5 tasks
0x00002468   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x0000246C   LDW R1 [R5 + TASK_PID]

0x00002470       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00002474       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x0000247C       LDW R1 [SP + TF_R1]
0x00002480       STW R1 [SP + TF_R1]

0x00002484       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x0000248C       LDW R1 [SP + TF_R1]
0x00002490       LDW R2 [SP + TF_R2]

0x00002494       MOV R12 R2               ; save flags

0x00002498       BL copy_path_from_user      ; macro inside destroys R11
0x000024A0       CMP R1 0
0x000024A4       BEQ open_fail_fault

0x000024AC       BL lookup_device
0x000024B4       CMP R1 0
0x000024B8       BEQ open_fail_noent

0x000024C0       MOV R8 R1            ; save device descriptor

0x000024C4       BL file_alloc        ; out: R1 = pointer to FILE object in file_pool
0x000024CC       CMP R1 0
0x000024D0       BEQ open_fail_nfile
0x000024D8       MOV R9 R1            ;

    ; initialize file object
0x000024DC       MOV R1 R9                ; file*
0x000024E0       MOV R2 R8                ; device*
0x000024E4       MOV R3 R12               ; flags
0x000024E8       BL file_init             ; ([i].device*)->([i].file*), [i].seek=0, set [i].flags in file_pool

0x000024F0       MOV R1 R9                ; initialised file ptr (ie file instance)
0x000024F4       BL fd_alloc              ; fd_table[new_fd] = file* (new_fd - idx in fd_table 4,5,6...)
0x000024FC       LI  R2 ERR_MFILE
0x00002504       CMP R1 R2
0x00002508       BEQ open_fail_fd

0x00002510       STW R1 [SP + TF_R1]

0x00002514       B trap_restore

open_fail_fd:
0x0000251C       MOV R1 R9
0x00002520       BL file_free
0x00002528       LI R1 ERR_MFILE
0x00002530       STW R1 [SP + TF_R1]

0x00002534       B trap_restore

open_fail_nfile:
0x0000253C       LI R1 ERR_NFILE
0x00002544       STW R1 [SP + TF_R1]

0x00002548       B trap_restore

open_fail_noent:
0x00002550       LI R1 ERR_NOENT
0x00002558       STW R1 [SP + TF_R1]

0x0000255C       B trap_restore

open_fail_fault:
0x00002564       LI R1 ERR_FAULT
0x0000256C       STW R1 [SP + TF_R1]

0x00002570       B trap_restore
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
0x00002578       PUSH LR

0x0000257C       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00002580   LI R1 CURRENT_TASK
0x00002588   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000258C   LI R1 TASK_SIZE
0x00002594   MUL R3 R4 R1
0x00002598   LI R5 tasks
0x000025A0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x000025A4   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x000025A8       PUSH R9                    ; original destination returned on success
0x000025AC       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x000025B4       LI R11 KBUFFER_SIZE
0x000025BC       CMP R10 R11
0x000025C0       BGE copy_path_fail

0x000025C8       PUSH R8
0x000025CC       PUSH R9
0x000025D0       PUSH R10
0x000025D4       MOV R1 R8
0x000025D8       LI R2 1
0x000025E0       LI R3 0                    ; read access from user source
0x000025E8       BL user_buffer_valid_range
0x000025F0       POP R10
0x000025F4       POP R9
0x000025F8       POP R8
0x000025FC       CMP R1 1
0x00002600       BNE copy_path_fail

0x00002608       LDB R4 [R8]
0x0000260C       STB R4 [R9]
0x00002610       CMP R4 0
0x00002614       BEQ copy_path_done

0x0000261C       ADD R8 R8 1
0x00002620       ADD R9 R9 1
0x00002624       ADD R10 R10 1
0x00002628       B copy_path_loop

copy_path_done:
0x00002630       POP R1                     ; original kernel path pointer
0x00002634       POP LR
0x00002638       RET

copy_path_fail:
0x0000263C       POP R1                     ; discard original kernel path pointer
0x00002640       LI R1 0
0x00002648       POP LR
0x0000264C       RET

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

0x00002650       PUSH LR

0x00002654       MOV R8 R1                  ; save pathname ptr

0x00002658       LI R7 device_table
0x00002660       LI R9 DEVICE_COUNT

lookup_loop:
0x00002668       CMP R9 0
0x0000266C       BEQ lookup_fail

    ; compare pathname with device name

0x00002674       MOV R1 R8
0x00002678       LDW R2 [R7 + DEV_NAME]

0x0000267C       BL strcmp

0x00002684       CMP R1 1
0x00002688       BEQ lookup_found

0x00002690       ADD R7 R7 DEV_SIZE
0x00002694       SUB R9 R9 1
0x00002698       B lookup_loop

lookup_found:

0x000026A0       MOV R1 R7                  ; return device descriptor ptr

0x000026A4       POP LR
0x000026A8       RET

lookup_fail:

0x000026AC       LI R1 0

0x000026B4       POP LR
0x000026B8       RET

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
0x000026BC       LDB R3 [R1]
0x000026C0       LDB R4 [R2]

0x000026C4       CMP R3 R4
0x000026C8       BNE str_not_equal

0x000026D0       CMP R3 0
0x000026D4       BEQ str_equal

0x000026DC       ADD R1 R1 1
0x000026E0       ADD R2 R2 1
0x000026E4       B str_loop

str_equal:
0x000026EC       LI R1 1
0x000026F4       RET

str_not_equal:
0x000026F8       LI R1 0
0x00002700       RET

;====================================================================
; file_init
; in: R1 = file pointer
      ;R2 = device descriptor pointer in file_pool
      ;R3 = open flags
; out:file structure initialized
;====================================================================
file_init:

0x00002704       LDW R4 [R2 + DEV_OPS]
0x00002708       STW R4 [R1 + FILE_OPS]

0x0000270C       LDW R4 [R2 + DEV_PRIVATE]
0x00002710       STW R4 [R1 + FILE_PRIVATE]

0x00002714       LI R4 0
0x0000271C       STW R4 [R1 + FILE_OFFSET]

0x00002720       STW R3 [R1 + FILE_FLAGS]

0x00002724       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x00002728       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x0000272C   LI R1 CURRENT_TASK
0x00002734   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002738   LI R1 TASK_SIZE
0x00002740   MUL R3 R4 R1
0x00002744   LI R4 tasks
0x0000274C   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00002750   LDW R4 [R4 + TASK_FD_TABLE]

0x00002754       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x0000275C       CMP R5 MAX_FDS
0x00002760       BGE fd_alloc_fail

0x00002768       SHL R6 R5 2                ; fd * 4
0x0000276C       ADD R7 R4 R6               ; &fd_table[fd]

0x00002770       LDW R2 [R7]
0x00002774       CMP R2 0                   ; 0 - empty
0x00002778       BEQ fd_alloc_found

0x00002780       ADD R5 R5 1
0x00002784       B fd_alloc_loop

fd_alloc_found:

0x0000278C       STW R8 [R7]                ; fd_table[fd] = file*

0x00002790       MOV R1 R5                  ; return fd
0x00002794       RET

fd_alloc_fail:

0x00002798       LI R1 ERR_MFILE
0x000027A0       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x000027A4       LDW R1 [SP + TF_R1]

0x000027A8       BL fd_remove    ;in R1-fd out R1-file ptr for this fd

0x000027B0       CMP R1 0
0x000027B4       BEQ close_fail

0x000027BC       BL file_free    ;in R1 file_ptr in file_pool it marks it as free (NULL)

0x000027C4       LI R1 0
0x000027CC       STW R1 [SP + TF_R1]

0x000027D0       B trap_restore

close_fail:
0x000027D8       LI R1 ERR_BADF
0x000027E0       STW R1 [SP + TF_R1]

0x000027E4       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x000027EC       LDW R7 [SP + TF_R1]

0x000027F0       BL pipe_alloc
0x000027F8       CMP R1 0
0x000027FC       BEQ pipe_fail_nospc

0x00002804       MOV R8 R1            ; new slot in pipe_pool ( pipe* )

    ; [0] read end          write[1]>--pipe--->read[0]

0x00002808       BL file_alloc
0x00002810       CMP R1 0
0x00002814       BEQ pipe_fail_pipe_only

0x0000281C       MOV R9 R1           ; new file for read end  in file_pool

0x00002820       LI R2 pipe_ops
0x00002828       STW R2 [R9 + FILE_OPS]      ; store ops (for pipe of read end) in allocated  file struc

0x0000282C       STW R8 [R9 + FILE_PRIVATE]  ; store our slot pipe* in file

0x00002830       LI R2 FD_FLAG_READ
0x00002838       STW R2 [R9 + FILE_FLAGS]    ; set file mode read

0x0000283C       MOV R1 R9
0x00002840       BL fd_alloc                 ; insert read file to fd_table of user process

0x00002848       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00002850       CMP R1 R2
0x00002854       BEQ pipe_fail_read_file

0x0000285C       MOV R10 R1           ; get file read fd created to R10

    ; write end

0x00002860       BL file_alloc
0x00002868       CMP R1 0
0x0000286C       BEQ pipe_fail_read_fd

0x00002874       MOV R9 R1

0x00002878       LI R2 pipe_ops
0x00002880       STW R2 [R9 + FILE_OPS]

0x00002884       STW R8 [R9 + FILE_PRIVATE]

0x00002888       LI R2 FD_FLAG_WRITE                 ;file mode -write
0x00002890       STW R2 [R9 + FILE_FLAGS]

0x00002894       MOV R1 R9
0x00002898       BL fd_alloc

0x000028A0       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x000028A8       CMP R1 R2
0x000028AC       BEQ pipe_fail_write_file

0x000028B4       MOV R11 R1           ; R11 write fd R10 read fd

0x000028B8       MOV R1 R7   ; in &fd[2]
0x000028BC       LI R2 8     ; len 2
0x000028C4       LI R3 1     ; mem perm to write cond
0x000028CC       BL user_buffer_valid_range
0x000028D4       CMP R1 1
0x000028D8       BNE pipe_fail_both_fds

0x000028E0       STW R10 [R7]    ;fd[0]-rd fd[1]-wr
0x000028E4       STW R11 [R7 + 4]

0x000028E8       LI R1 0
0x000028F0       STW R1 [SP + TF_R1]

0x000028F4       B trap_restore

pipe_fail:
0x000028FC       LI R1 ERR_IO
0x00002904       STW R1 [SP + TF_R1]

0x00002908       B trap_restore

pipe_fail_both_fds:
0x00002910       MOV R12 R8
0x00002914       MOV R1 R11
0x00002918       BL fd_remove
0x00002920       CMP R1 0
0x00002924       BEQ pipe_fail_both_fds_read
0x0000292C       BL file_free

pipe_fail_both_fds_read:
0x00002934       MOV R1 R10
0x00002938       BL fd_remove
0x00002940       CMP R1 0
0x00002944       BEQ pipe_fail_free_pipe_fault
0x0000294C       BL file_free

pipe_fail_free_pipe_fault:
0x00002954       MOV R1 R12
0x00002958       BL pipe_free
0x00002960       LI R1 ERR_FAULT
0x00002968       STW R1 [SP + TF_R1]

0x0000296C       B trap_restore

pipe_fail_write_file:
0x00002974       MOV R12 R8
0x00002978       MOV R1 R9
0x0000297C       BL file_free
0x00002984       MOV R1 R10
0x00002988       BL fd_remove
0x00002990       CMP R1 0
0x00002994       BEQ pipe_fail_free_pipe_mfile
0x0000299C       BL file_free

pipe_fail_free_pipe_mfile:
0x000029A4       MOV R1 R12
0x000029A8       BL pipe_free
0x000029B0       LI R1 ERR_MFILE
0x000029B8       STW R1 [SP + TF_R1]

0x000029BC       B trap_restore

pipe_fail_read_fd:
0x000029C4       MOV R12 R8
0x000029C8       MOV R1 R10
0x000029CC       BL fd_remove
0x000029D4       CMP R1 0
0x000029D8       BEQ pipe_fail_free_pipe_nfile
0x000029E0       BL file_free

pipe_fail_free_pipe_nfile:
0x000029E8       MOV R1 R12
0x000029EC       BL pipe_free
0x000029F4       LI R1 ERR_NFILE
0x000029FC       STW R1 [SP + TF_R1]

0x00002A00       B trap_restore

pipe_fail_read_file:
0x00002A08       MOV R12 R8
0x00002A0C       MOV R1 R9
0x00002A10       BL file_free
0x00002A18       MOV R1 R12
0x00002A1C       BL pipe_free
0x00002A24       LI R1 ERR_MFILE
0x00002A2C       STW R1 [SP + TF_R1]

0x00002A30       B trap_restore

pipe_fail_pipe_only:
0x00002A38       MOV R1 R8
0x00002A3C       BL pipe_free
0x00002A44       LI R1 ERR_NFILE
0x00002A4C       STW R1 [SP + TF_R1]

0x00002A50       B trap_restore

pipe_fail_nospc:
0x00002A58       LI R1 ERR_NOSPC
0x00002A60       STW R1 [SP + TF_R1]

0x00002A64       B trap_restore

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

0x00002A6C       PUSH LR

0x00002A70       MOV R9 R1              ; file*
0x00002A74       MOV R7 R2              ; user buffer
0x00002A78       MOV R6 R3              ; requested len
0x00002A7C       LDW R9 [R9 + FILE_PRIVATE]    ; our instance allocated in pipe_pool pipe*
0x00002A80       CMP R6 0                ;fast clear from it if len=0
0x00002A84       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00002A8C       PUSH R7
0x00002A90       PUSH R6

0x00002A94       MOV R1 R7
0x00002A98       MOV R2 R6
0x00002A9C       LI  R3 1               ; write access
0x00002AA4       BL user_buffer_valid_range

0x00002AAC       POP R6
0x00002AB0       POP R7
0x00002AB4       CMP R1 1
0x00002AB8       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00002AC0       LDW R4 [R9 + PIPE_COUNT]
0x00002AC4       CMP R4 0
0x00002AC8       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00002AD0       CMP R6 R4
0x00002AD4       BLT pipe_user_len

0x00002ADC       MOV R5 R4
0x00002AE0       B pipe_have_amount

pipe_user_len:
0x00002AE8       MOV R5 R6

pipe_have_amount:
0x00002AEC       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00002AF4       CMP R10 R5
0x00002AF8       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00002B00       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00002B04       MOV R12 R9
0x00002B08       ADD R12 R12 PIPE_BUFFER
0x00002B0C       ADD R12 R12 R11         ; addr += tail

0x00002B10       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00002B14       MOV R12 R7
0x00002B18       ADD R12 R12 R10

0x00002B1C       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x00002B20       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00002B24       LI R2 255
0x00002B2C       AND R11 R11 R2
0x00002B30       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00002B34       LDW R12 [R9 + PIPE_COUNT]
0x00002B38       SUB R12 R12 1
0x00002B3C       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00002B40       ADD R10 R10 1
0x00002B44       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00002B4C       MOV R1 R9
0x00002B50       ADD R1 R1 PIPE_WWAIT
0x00002B54       BL waitq_wake_all
0x00002B5C       MOV R1 R10          ; read bytes amount
0x00002B60       POP LR
0x00002B64       RET

pipe_read_badptr:
0x00002B68       LI R1 ERR_FAULT
0x00002B70       POP LR
0x00002B74       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00002B78       MOV R1 R9
0x00002B7C       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00002B80       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00002B88       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00002B90       LDW R4 [R9 + PIPE_COUNT]
0x00002B94       CMP R4 0
0x00002B98       BNE pipe_read_retry

0x00002BA0       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00002BA8       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00002BB0       LI R2 0

pipe_loop:
0x00002BB8       LI  R1 MAX_PIPES
0x00002BC0       CMP R2 R1
0x00002BC4       BGE pipe_alloc_fail

0x00002BCC       SHL R3 R2 2

0x00002BD0       LI R4 pipe_used
0x00002BD8       ADD R4 R4 R3

0x00002BDC       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00002BE0       CMP R5 0                ; 0 -empty
0x00002BE4       BEQ pipe_found

0x00002BEC       ADD R2 R2 1
0x00002BF0       B pipe_loop

pipe_found:

0x00002BF8       LI R5 1
0x00002C00       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00002C04       LI R4 PIPE_SIZE
0x00002C0C       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00002C10       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00002C18       ADD R1 R1 R6

0x00002C1C       LI R7 0                 ; clean it up
0x00002C24       STW R7 [R1 + PIPE_HEAD]
0x00002C28       STW R7 [R1 + PIPE_TAIL]
0x00002C2C       STW R7 [R1 + PIPE_COUNT]
0x00002C30       STW R7 [R1 + PIPE_RWAIT]
0x00002C34       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00002C38       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00002C3C       LI R1 0
0x00002C44       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00002C48       LI R2 pipe_pool
0x00002C50       SUB R3 R1 R2

0x00002C54       LI R4 PIPE_SIZE
0x00002C5C       DIV R5 R3 R4

0x00002C60       SHL R5 R5 2
0x00002C64       LI R6 pipe_used
0x00002C6C       ADD R6 R6 R5

0x00002C70       LI R7 0
0x00002C78       STW R7 [R6]

0x00002C7C       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00002C80       PUSH LR

0x00002C84       MOV R8 R1
0x00002C88       MOV R7 R2
0x00002C8C       MOV R6 R3

0x00002C90       LDW R9 [R8 + FILE_PRIVATE]

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00002C94       PUSH R7
0x00002C98       PUSH R6

0x00002C9C       MOV R1 R7
0x00002CA0       MOV R2 R6
0x00002CA4       LI  R3 0           ; READ access
0x00002CAC       BL user_buffer_valid_range

0x00002CB4       POP R6
0x00002CB8       POP R7

0x00002CBC       CMP R1 1
0x00002CC0       BNE pipe_write_badptr

0x00002CC8       LI R10 0               ; bytes written
pipe_write_retry:
0x00002CD0       CMP R10 R6
0x00002CD4       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00002CDC       LDW R11 [R9 + PIPE_COUNT]
0x00002CE0       LI R2 256
0x00002CE8       CMP R11 R2
0x00002CEC       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00002CF4       LDW R12 [R9 + PIPE_HEAD]

0x00002CF8       MOV R4 R7
0x00002CFC       ADD R4 R4 R10
0x00002D00       LDB R5 [R4]     ; read byte from user buff addr

0x00002D04       MOV R4 R9
0x00002D08       ADD R4 R4 PIPE_BUFFER
0x00002D0C       ADD R4 R4 R12
0x00002D10       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00002D14       ADD R12 R12 1
0x00002D18       LI R2 255
0x00002D20       AND R12 R12 R2
0x00002D24       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00002D28       LDW R4 [R9 + PIPE_COUNT]
0x00002D2C       ADD R4 R4 1
0x00002D30       STW R4 [R9 + PIPE_COUNT]

; written++
0x00002D34       ADD R10 R10 1
0x00002D38       B pipe_write_retry

pipe_write_done:
; wake readers
0x00002D40       MOV R1 R9
0x00002D44       ADD R1 R1 PIPE_RWAIT
0x00002D48       BL waitq_wake_all
0x00002D50       MOV R1 R10      ;written bytes
0x00002D54       POP LR
0x00002D58       RET

pipe_write_badptr:
0x00002D5C       LI R1 ERR_FAULT
0x00002D64       POP LR
0x00002D68       RET

pipe_write_empty:
0x00002D6C       LI R1 0
0x00002D74       POP LR
0x00002D78       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00002D7C       MOV R1 R9
0x00002D80       ADD R1 R1 PIPE_WWAIT
0x00002D84       LI R2 WAIT_PIPE_WRITE
0x00002D8C       BL waitq_prepare_sleep
    ; race check
0x00002D94       LDW R4 [R9 + PIPE_COUNT]
0x00002D98       LI R2 256
0x00002DA0       CMP R4 R2
0x00002DA4       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00002DAC       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00002DB4       B pipe_write_retry      ; unblocked! go write!

fd_remove:
 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
0x00002DBC       CMP R1 3
0x00002DC0       BLT fd_remove_invalid

0x00002DC8       CMP R1 MAX_FDS
0x00002DCC       BGE fd_remove_invalid

0x00002DD4       MOV R8 R1

; macro: GET_CURR_TASK_IDX R4
0x00002DD8   LI R1 CURRENT_TASK
0x00002DE0   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002DE4   LI R1 TASK_SIZE
0x00002DEC   MUL R3 R4 R1
0x00002DF0   LI R4 tasks
0x00002DF8   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x00002DFC   LDW R4 [R4 + TASK_FD_TABLE]

0x00002E00       SHL R5 R8 2
0x00002E04       ADD R6 R4 R5

0x00002E08       LDW R1 [R6]
0x00002E0C       CMP R1 0
0x00002E10       BEQ fd_remove_invalid

0x00002E18       LI R7 0
0x00002E20       STW R7 [R6]

0x00002E24       RET

fd_remove_invalid:
0x00002E28       LI R1 0
0x00002E30       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00002E34       LDW R1 [SP + TF_R1]
0x00002E38       LDW R2 [SP + TF_R2]
0x00002E3C       LDW R3 [SP + TF_R3]

0x00002E40       MOV R7 R2               ; save user buffer
0x00002E44       MOV R6 R3               ; save length
0x00002E48       PUSH R7
0x00002E4C       PUSH R6
0x00002E50       LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
0x00002E58       BL fetch_fd_entry
0x00002E60       POP R6
0x00002E64       POP R7
0x00002E68       CMP R1 0
0x00002E6C       BEQ bad_fd
0x00002E74       MOV R9 R1               ; file object pointer
0x00002E78       MOV R1 R9
0x00002E7C       MOV R2 R7
0x00002E80       MOV R3 R6
0x00002E84       BL file_read
0x00002E8C       STW R1 [SP + TF_R1]

0x00002E90       B trap_restore

con_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00002E98       PUSH LR
0x00002E9C       MOV R9 R1
0x00002EA0       MOV R7 R2
0x00002EA4       MOV R6 R3
0x00002EA8       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x00002EAC       CMP R6 0
0x00002EB0       BEQ read_done

0x00002EB8       PUSH R7
0x00002EBC       PUSH R6
0x00002EC0       PUSH R9
0x00002EC4       MOV R1 R7
0x00002EC8       MOV R2 R6
0x00002ECC       LI R3 1                ; write access for destination buffer
0x00002ED4       BL user_buffer_valid_range
0x00002EDC       POP R9
0x00002EE0       POP R6
0x00002EE4       POP R7
0x00002EE8       CMP R1 1
0x00002EEC       BNE driver_bad_pointer

read_wait_uart_rx:
0x00002EF4       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00002EF8       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00002EFC       AND R5 R5 1                 ; bit 0 = RX_READY
0x00002F00       CMP R5 0
0x00002F04       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

0x00002F0C       PUSH R7

; macro: GET_CURR_TASK_IDX R4
0x00002F10   LI R1 CURRENT_TASK
0x00002F18   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002F1C   LI R1 TASK_SIZE
0x00002F24   MUL R3 R4 R1
0x00002F28   LI R5 tasks
0x00002F30   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00002F34   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00002F38       MOV R2 R6
0x00002F3C       MOV R3 R9
0x00002F40       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)

0x00002F48       POP R7

0x00002F4C       CMP R1 0
0x00002F50       BEQ read_done

0x00002F58       MOV R2 R1              ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x00002F5C   LI R1 CURRENT_TASK
0x00002F64   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x00002F68   LI R1 TASK_SIZE
0x00002F70   MUL R3 R5 R1
0x00002F74   LI R4 tasks
0x00002F7C   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x00002F80   LDW R4 [R4 + TASK_KBUF_RD_PTR]

0x00002F84       MOV R1 R7              ; user destination
0x00002F88       BL copy_to_user        ; copy from kernel buffer to user buffer

0x00002F90       POP LR
0x00002F94       RET

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00002F98       LI R1 uart_rx_waitq
0x00002FA0       LI R2 WAIT_UART_RX
0x00002FA8       BL waitq_prepare_sleep

0x00002FB0       LDW R4 [R9 + UARTDEV_MMIO]
0x00002FB4       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x00002FB8       AND R10 R10 1
0x00002FBC       CMP R10 0
0x00002FC0       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x00002FC8       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x00002FD0       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00002FD8       LI R1 uart_rx_waitq
0x00002FE0       BL waitq_cancel_sleep_current

0x00002FE8       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x00002FF0       LI R1 0
0x00002FF8       POP LR
0x00002FFC       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003000       LDW R1 [SP + TF_R1]
0x00003004       LDW R2 [SP + TF_R2]
0x00003008       LDW R3 [SP + TF_R3]
; first fetch file from procs fd_table and check flags for match access WRITE /READ
0x0000300C       MOV R7 R2               ; save user buffer
0x00003010       MOV R6 R3               ; save length
0x00003014       PUSH R7
0x00003018       PUSH R6
0x0000301C       LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
0x00003024       BL fetch_fd_entry       ;input R1 fd on exit R1 - file ptr  => r1=fetch_fd_entry(fd=r1)
0x0000302C       POP R6
0x00003030       POP R7
0x00003034       CMP R1 0
0x00003038       BEQ bad_fd              ;if flags file and in r2 dont match
0x00003040       MOV R9 R1               ; file object pointer
0x00003044       MOV R1 R9
0x00003048       MOV R2 R7
0x0000304C       MOV R3 R6
0x00003050       BL file_write           ; call file write R1 = file ptr, R2 = user buffer, R3 = len
0x00003058       STW R1 [SP + TF_R1]

0x0000305C       B trap_restore

con_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00003064       PUSH LR
0x00003068       MOV R9 R1
0x0000306C       MOV R7 R2
0x00003070       MOV R6 R3
0x00003074       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x00003078       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00003080       CMP R6 0
0x00003084       BEQ write_done             ;0 bytes

0x0000308C       LI R2 KBUFFER_SIZE
0x00003094       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00003098       BLT write_chunk_small
0x000030A0       LI R2 KBUFFER_SIZE

0x000030A8       B write_chunk

write_chunk_small:
0x000030B0       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x000030B4       PUSH R7
0x000030B8       PUSH R6
0x000030BC       PUSH R9
0x000030C0       PUSH R8
0x000030C4       MOV R1 R7
0x000030C8       MOV R2 R2
0x000030CC       LI R3 0                ; read access for source buffer
0x000030D4       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x000030DC       POP R8
0x000030E0       POP R9
0x000030E4       POP R6
0x000030E8       POP R7
0x000030EC       CMP R1 1
0x000030F0       BNE driver_bad_pointer

0x000030F8       PUSH R7
0x000030FC       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x00003100   LI R1 CURRENT_TASK
0x00003108   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000310C   LI R1 TASK_SIZE
0x00003114   MUL R3 R4 R1
0x00003118   LI R5 tasks
0x00003120   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00003124   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00003128       MOV R1 R7
0x0000312C       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00003134       MOV R10 R1             ; bytes copied
0x00003138       POP R6
0x0000313C       POP R7

0x00003140       PUSH R7
0x00003144       PUSH R9
0x00003148       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x0000314C       LDW R1 [R9 + UARTDEV_MMIO]
0x00003150       LDW R2 [R1 + 4]
0x00003154       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00003158       CMP R2 0
0x0000315C       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00003164   LI R1 CURRENT_TASK
0x0000316C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003170   LI R1 TASK_SIZE
0x00003178   MUL R3 R4 R1
0x0000317C   LI R5 tasks
0x00003184   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00003188   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x0000318C       MOV R2 R10
0x00003190       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x00003194       BL device_write
0x0000319C       POP R6
0x000031A0       POP R9
0x000031A4       POP R7

0x000031A8       CMP R1 0        ;nothing is written - go again
0x000031AC       BEQ write_loop

0x000031B4       ADD R8 R8 R1     ;update ptrs
0x000031B8       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x000031BC       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x000031C0       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x000031C8       LI R1 uart_tx_waitq
0x000031D0       LI R2 WAIT_UART_TX
0x000031D8       BL waitq_prepare_sleep

0x000031E0       LDW R1 [R9 + UARTDEV_MMIO]
0x000031E4       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x000031E8       AND R2 R2 2
0x000031EC       CMP R2 0
0x000031F0       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x000031F8       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x00003200       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00003208       LI R1 uart_tx_waitq
0x00003210       BL waitq_cancel_sleep_current

0x00003218       B write_wait_uart_tx

write_done:
0x00003220       MOV R1 R8
0x00003224       POP LR
0x00003228       RET

driver_bad_pointer:
0x0000322C       LI R1 ERR_FAULT
0x00003234       POP LR
0x00003238       RET

bad_fd:
0x0000323C       LI R1 ERR_BADF
0x00003244       STW R1 [SP + TF_R1]

0x00003248       B trap_restore

bad_pointer:
0x00003250       LI R1 ERR_FAULT
0x00003258       STW R1 [SP + TF_R1]

0x0000325C       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00003264       LDW R4 [R1 + FILE_OPS]
0x00003268       LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
0x0000326C       JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00003270       LDW R4 [R1 + FILE_OPS]
0x00003274       LDW R4 [R4 + FOPS_WRITE]    ; get write function xdev_write from ops
0x00003278       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x0000327C       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00003284       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x0000328C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003290       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00003298       CMP R5 R2                   ; have we read enough bytes?
0x0000329C       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x000032A4       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000032A8       AND R6 R6 1                 ; bit 0 = RX_READY
0x000032AC       CMP R6 0
0x000032B0       BEQ dr_done                 ; no more buffered input available

0x000032B8       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x000032BC       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x000032C0       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x000032C4       CMP R7 10
0x000032C8       BEQ dr_done

0x000032D0       B dr_loop

dr_done:
0x000032D8       MOV R1 R5                   ; return number of bytes actually read
0x000032DC       RET

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

0x000032E0       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000032E4       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000032EC       CMP R5 R2                   ; have we written all bytes?
0x000032F0       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x000032F8       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000032FC       AND R6 R6 2                 ; bit 1 = TX_READY
0x00003300       CMP R6 0
0x00003304       BEQ dcw_done

0x0000330C       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x00003310       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00003314       ADD R5 R5 1
0x00003318       B dcw_loop

dcw_done:
0x00003320       MOV R1 R5                   ; return number of bytes written
0x00003324       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00003328       LI R1 0
0x00003330       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00003334       PUSH LR
0x00003338       MOV R6 R3
0x0000333C       CMP R6 0
0x00003340       BEQ null_write_done

0x00003348       PUSH R6
0x0000334C       MOV R1 R2
0x00003350       MOV R2 R6
0x00003354       LI R3 0                    ; read access from user source
0x0000335C       BL user_buffer_valid_range
0x00003364       POP R6
0x00003368       CMP R1 1
0x0000336C       BNE null_write_badptr

null_write_done:
0x00003374       MOV R1 R6
0x00003378       POP LR
0x0000337C       RET

null_write_badptr:
0x00003380       LI R1 ERR_FAULT
0x00003388       POP LR
0x0000338C       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, 3)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

0x00003390       CMP R1 0
0x00003394       BLT fd_invalid
0x0000339C       CMP R1 MAX_FDS
0x000033A0       BGE fd_invalid

0x000033A8       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x000033AC   LI R1 CURRENT_TASK
0x000033B4   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000033B8   LI R1 TASK_SIZE
0x000033C0   MUL R3 R4 R1
0x000033C4   LI R4 tasks
0x000033CC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000033D0   LDW R4 [R4 + TASK_FD_TABLE]

0x000033D4       SHL R5 R8 2
0x000033D8       ADD R4 R4 R5                ;r4=fd*4+FD_TABLE = file entry according to fd
0x000033DC       LDW R1 [R4]                 ; R1 = file ptr
0x000033E0       LDW R6 [R1 + FILE_FLAGS]
0x000033E4       AND R6 R6 R2
0x000033E8       CMP R6 R2                   ;check file flags R2 input R6 from file
0x000033EC       BNE fd_invalid

0x000033F4       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x000033F8       LI R1 0
0x00003400       RET

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
0x00003404       PUSH R10
0x00003408       PUSH R11
0x0000340C       PUSH R12

0x00003410       LI R4 0
0x00003418       CMP R2 R4
0x0000341C       BEQ uv_valid

0x00003424       LI R4 USER_BASE
0x0000342C       CMP R1 R4
0x00003430       BLT uv_invalid

0x00003438       LI R4 USER_LIMIT
0x00003440       ADD R5 R1 R2
0x00003444       SUB R5 R5 1
0x00003448       CMP R5 R1
0x0000344C       BLT uv_invalid
0x00003454       CMP R5 R4
0x00003458       BGT uv_invalid
0x00003460       MOV R11 R1              ; save start address; task macros clobber R1
0x00003464       MOV R12 R5              ; save end address for page calculation
0x00003468       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x0000346C   LI R1 CURRENT_TASK
0x00003474   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00003478   LI R1 TASK_SIZE
0x00003480   MUL R3 R6 R1
0x00003484   LI R6 tasks
0x0000348C   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00003490   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x00003494       CMP R6 0
0x00003498       BEQ uv_invalid

uv_check_pages:
0x000034A0       SHR R7 R11 12
0x000034A4       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x000034A8       CMP R7 R8
0x000034AC       BGT uv_valid
0x000034B4       SHL R9 R7 2
0x000034B8       ADD R9 R9 R6
0x000034BC       LDW R10 [R9]
0x000034C0       AND R5 R10 PTE_P
0x000034C4       CMP R5 0
0x000034C8       BEQ uv_invalid
0x000034D0       AND R5 R10 PTE_U
0x000034D4       CMP R5 0
0x000034D8       BEQ uv_invalid
0x000034E0       CMP R4 0
0x000034E4       BEQ uv_check_read
0x000034EC       AND R5 R10 PTE_W
0x000034F0       CMP R5 0
0x000034F4       BEQ uv_invalid
0x000034FC       B uv_next

uv_check_read:
0x00003504       AND R5 R10 PTE_R
0x00003508       CMP R5 0
0x0000350C       BEQ uv_invalid

uv_next:
0x00003514       ADD R7 R7 1
0x00003518       B uv_loop

uv_valid:
0x00003520       LI R1 1
0x00003528       POP R12
0x0000352C       POP R11
0x00003530       POP R10
0x00003534       RET

uv_invalid:
0x00003538       LI R1 0

0x00003540       POP R12
0x00003544       POP R11
0x00003548       POP R10
0x0000354C       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00003550       LI R5 0
cfu_head:
0x00003558       CMP R2 0
0x0000355C       BEQ cfu_done
0x00003564       OR R6 R1 R4
0x00003568       AND R6 R6 3
0x0000356C       CMP R6 0
0x00003570       BEQ cfu_word
0x00003578       LDB R7 [R1]
0x0000357C       STB R7 [R4]
0x00003580       ADD R1 R1 1
0x00003584       ADD R4 R4 1
0x00003588       ADD R5 R5 1
0x0000358C       SUB R2 R2 1
0x00003590       B cfu_head
cfu_word:
0x00003598       CMP R2 4
0x0000359C       BLT cfu_tail
0x000035A4       LDW R7 [R1]
0x000035A8       STW R7 [R4]
0x000035AC       ADD R1 R1 4
0x000035B0       ADD R4 R4 4
0x000035B4       ADD R5 R5 4
0x000035B8       SUB R2 R2 4
0x000035BC       B cfu_word
cfu_tail:
0x000035C4       CMP R2 0
0x000035C8       BEQ cfu_done
0x000035D0       LDB R7 [R1]
0x000035D4       STB R7 [R4]
0x000035D8       ADD R1 R1 1
0x000035DC       ADD R4 R4 1
0x000035E0       ADD R5 R5 1
0x000035E4       SUB R2 R2 1
0x000035E8       B cfu_tail
cfu_done:
0x000035F0       MOV R1 R5
0x000035F4       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x000035F8       LI R5 0
ctu_head:
0x00003600       CMP R2 0
0x00003604       BEQ ctu_done
0x0000360C       OR R6 R1 R4
0x00003610       AND R6 R6 3
0x00003614       CMP R6 0
0x00003618       BEQ ctu_word
0x00003620       LDB R7 [R4]
0x00003624       STB R7 [R1]
0x00003628       ADD R1 R1 1
0x0000362C       ADD R4 R4 1
0x00003630       ADD R5 R5 1
0x00003634       SUB R2 R2 1
0x00003638       B ctu_head
ctu_word:
0x00003640       CMP R2 4
0x00003644       BLT ctu_tail
0x0000364C       LDW R7 [R4]
0x00003650       STW R7 [R1]
0x00003654       ADD R1 R1 4
0x00003658       ADD R4 R4 4
0x0000365C       ADD R5 R5 4
0x00003660       SUB R2 R2 4
0x00003664       B ctu_word
ctu_tail:
0x0000366C       CMP R2 0
0x00003670       BEQ ctu_done
0x00003678       LDB R7 [R4]
0x0000367C       STB R7 [R1]
0x00003680       ADD R1 R1 1
0x00003684       ADD R4 R4 1
0x00003688       ADD R5 R5 1
0x0000368C       SUB R2 R2 1
0x00003690       B ctu_tail
ctu_done:
0x00003698       MOV R1 R5
0x0000369C       RET

handle_debug:
    ; Debug trap - just return
0x000036A0       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x000036A8       CSRR R1 STVAL

0x000036AC       CMP R1 0
0x000036B0       BEQ handle_timer_irq

0x000036B8       CMP R1 1
0x000036BC       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x000036C4       LI R2 0x00102000
0x000036CC       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x000036D0       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x000036D8       LI R2 0x00102000
0x000036E0       LI R3 0
0x000036E8       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Yield the CPU (reschedule and switch tasks)
0x000036EC       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x000036F4       LI R2 0x00102000
0x000036FC       LI R3 1
0x00003704       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00003708       LI R1 uart_rx_waitq
0x00003710       BL waitq_wake_all
0x00003718       LI R1 uart_tx_waitq
0x00003720       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00003728       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00003730       POP R1                  ; stval, informational only
0x00003734       POP R1                  ; scause, informational only
0x00003738       POP R1
0x0000373C       CSRW SSTATUS R1
0x00003740       POP R1
0x00003744       CSRW SFLAGS R1
0x00003748       POP R1
0x0000374C       CSRW SEPC R1
0x00003750       POP R1                  ; interrupted task SP
0x00003754       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00003758       POP R15
0x0000375C       POP R14
0x00003760       POP R12
0x00003764       POP R11
0x00003768       POP R10
0x0000376C       POP R9
0x00003770       POP R8
0x00003774       POP R7
0x00003778       POP R6
0x0000377C       POP R5
0x00003780       POP R4
0x00003784       POP R3
0x00003788       POP R2
0x0000378C       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00003790       CSRRW SP SSCRATCH SP
0x00003794       SRET


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

0x00007843       PUSH R9
0x00007847       PUSH R10

0x0000784B       MOV R9 R1                  ; preserve wait queue pointer
0x0000784F       MOV R10 R2                 ; preserve debug wait reason

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x00007853   LI R1 CURRENT_TASK
0x0000785B   LDW R2 [R1]

0x0000785F       LI R4 1
0x00007867       SHL R4 R4 R2               ; R4 = bit for current task
0x0000786B       LDW R5 [R9 + WQ_MASK]
0x0000786F       OR R5 R5 R4
0x00007873       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00007877   LI R1 TASK_SIZE
0x0000787F   MUL R3 R2 R1
0x00007883   LI R5 tasks
0x0000788B   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x0000788F   LI R1 TASK_BLOCKED_IO
0x00007897   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x0000789B   STW R10 [R5 + TASK_WAIT]

0x0000789F       POP R10
0x000078A3       POP R9
0x000078A7       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x000078AB       PUSH R9

0x000078AF       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x000078B3   LI R1 CURRENT_TASK
0x000078BB   LDW R2 [R1]

0x000078BF       LDW R4 [R9 + WQ_MASK]

0x000078C3       LI  R5 1
0x000078CB       SHL R5 R5 R2        ;shift to position of current task bit

0x000078CF       NOT R5 R5           ; invert to get mask for clearing this bit

0x000078D3       AND R4 R4 R5        ; clear current task bit

0x000078D7       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x000078DB   LI R1 TASK_SIZE
0x000078E3   MUL R3 R2 R1
0x000078E7   LI R5 tasks
0x000078EF   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x000078F3   LI R1 TASK_READY
0x000078FB   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x000078FF   LI R1 WAIT_NONE
0x00007907   STW R1 [R5 + TASK_WAIT]

0x0000790B       POP R9
0x0000790F       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x00007913       PUSH LR
0x00007917       BL schedule_call
0x0000791F       POP LR
0x00007923       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x00007927       PUSH LR

0x0000792B       MOV R9 R1
0x0000792F       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00007933       LI R10 0
0x0000793B       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x0000793F       LI R2 0                    ; task index

wq_wake_loop:
0x00007947       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x0000794B       BGE wq_wake_done

0x00007953       LI R3 1
0x0000795B       SHL R3 R3 R2               ; R3 = bit for task R2
0x0000795F       AND R4 R8 R3
0x00007963       CMP R4 0
0x00007967       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x0000796F   LI R1 TASK_SIZE
0x00007977   MUL R3 R2 R1
0x0000797B   LI R5 tasks
0x00007983   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00007987   LI R1 TASK_READY
0x0000798F   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00007993   LI R1 WAIT_NONE
0x0000799B   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x0000799F       ADD R2 R2 1
0x000079A3       B wq_wake_loop

wq_wake_done:
0x000079AB       POP LR
0x000079AF       RET

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

0x000079B3       LI R2 0                      ; index

fa_loop:
0x000079BB       CMP R2 MAX_FILES
0x000079BF       BGE fa_fail

0x000079C7       SHL R3 R2 2                  ; index * 4
0x000079CB       LI R4 file_used              ; look in file_used list 0 free 1 used
0x000079D3       ADD R4 R4 R3

0x000079D7       LDW R5 [R4]
0x000079DB       CMP R5 0
0x000079DF       BEQ fa_found

0x000079E7       ADD R2 R2 1
0x000079EB       B fa_loop

fa_found:
0x000079F3       LI R5 1
0x000079FB       STW R5 [R4]                  ; mark slot used

0x000079FF       LI R4 FILE_SIZE
0x00007A07       MUL R6 R2 R4

0x00007A0B       LI R1 file_pool
0x00007A13       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x00007A17       LI R7 0

0x00007A1F       STW R7 [R1 + FILE_OPS]
0x00007A23       STW R7 [R1 + FILE_PRIVATE]
0x00007A27       STW R7 [R1 + FILE_OFFSET]
0x00007A2B       STW R7 [R1 + FILE_FLAGS]

0x00007A2F       RET

fa_fail:
0x00007A33       LI R1 0
0x00007A3B       RET

;=================================================================
; file_free:
; input:
; R1 = pointer to FILE object
; none output
;=================================================================

file_free:

0x00007A3F       LI R2 file_pool
0x00007A47       SUB R3 R1 R2                 ; offset from pool base

0x00007A4B       LI R4 FILE_SIZE
0x00007A53       DIV R5 R3 R4                 ; slot number

0x00007A57       SHL R5 R5 2                  ; slot * 4

0x00007A5B       LI R6 file_used
0x00007A63       ADD R6 R6 R5

0x00007A67       LI R7 0
0x00007A6F       STW R7 [R6]                  ; mark free

0x00007A73       RET


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

0x00007A77       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x00007A7B       LI  R1 tasks
0x00007A83       LI  R2 TASK_SIZE
0x00007A8B       LI  R3 MAX_TASKS
0x00007A93       MUL R3 R2 R3
0x00007A97       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x00007A9F       LI R1 idle_task
0x00007AA7       LI R2 0
0x00007AAF       BL task_create

0x00007AB7       CMP R1 0
0x00007ABB       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task A
    ; ----------------------------------

0x00007AC3       LI R1 TASK_A_START
0x00007ACB       LI R2 1
0x00007AD3       BL task_create

0x00007ADB       CMP R1 0
0x00007ADF       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task B
    ; ----------------------------------

0x00007AE7       LI R1 TASK_B_START
0x00007AEF       LI R2 2
0x00007AF7       BL task_create

0x00007AFF       CMP R1 0
0x00007B03       BEQ init_scheduler_fail

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x00007B0B       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x00007B13   LI R1 CURRENT_TASK
0x00007B1B   STW R2 [R1]

0x00007B1F       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00007B23       RET


init_scheduler_fail:

0x00007B27       DEBUG 99

halt:
0x00007B2B       B halt

;old init scheduler with manual trapframe setup - we can use it for debug and reference when we implement task_create and task_exit and later fork and exec

init_scheduler1:
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

0x00007EA7       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
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
0x00007FBF       CMP R3 MAX_TASKS
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
    .SPACE 16      ; 128 bits = 16 bytes

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

0x000080DF       LI R2 0                  ; page index

pa_loop:
0x000080E7       LI R1 MAX_PHYS_PAGES

0x000080EF       CMP R2 R1
0x000080F3       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x000080FB       MOV R3 R2
0x000080FF       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x00008103       MOV R4 R2
0x00008107       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x0000810B       LI R5 page_bitmap
0x00008113       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x00008117       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x0000811B       LI R7 1
0x00008123       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x00008127       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x0000812B       CMP R8 0
0x0000812F       BEQ pa_found                ; if bit is 0, page is free

0x00008137       ADD R2 R2 1                 ; increment page index and check next page
0x0000813B       B pa_loop

pa_found:

    ; mark page allocated

0x00008143       OR  R6 R6 R7
0x00008147       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x0000814B       LI  R9 PAGE_ALLOC_BASE

0x00008153       MOV R1 R2
0x00008157       SHL R1 R1 12          ; page_index * 4096

0x0000815B       ADD R1 R1 R9

0x0000815F       RET

pa_fail:

0x00008163       LI R1 0                     ; no free pages
0x0000816B       RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:

0x0000816F       LI R2 PAGE_ALLOC_BASE
0x00008177       SUB R3 R1 R2         ; calculate offset from base

0x0000817B       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x0000817F       MOV R4 R3
0x00008183       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x00008187       MOV R5 R3
0x0000818B       AND R5 R5 7          ; bit index in byte = page index % 8

0x0000818F       LI R6 page_bitmap
0x00008197       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x0000819B       LDB R7 [R6]

0x0000819F       LI R8 1
0x000081A7       SHL R8 R8 R5         ; mask for this page's bit

0x000081AB       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x000081AF       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x000081B3       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x000081B7       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

0x000081BB       LI R2 0

pz_loop:

0x000081C3       CMP R3 0
0x000081C7       BEQ pz_done

0x000081CF       STB R2 [R1]

0x000081D3       ADD R1 R1 1
0x000081D7       SUB R3 R3 1

0x000081DB       B pz_loop

pz_done:
0x000081E3       RET

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

0x0000856B       PUSH LR

0x0000856F       MOV R8 R1          ; entry
0x00008573       MOV R9 R2          ; pid
0x00008577       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x0000857F       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x00008587       CMP R1 0
0x0000858B       BEQ task_create_fail

0x00008593       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x00008597       MOV R1 R10
0x0000859B       LI R3 TASK_SIZE
0x000085A3       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x000085AB   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x000085AF   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x000085B3       BL page_alloc
0x000085BB       CMP R1 0
0x000085BF       BEQ task_create_fail

0x000085C7       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x000085CB   STW R1 [R10 + TASK_PTBR]

0x000085CF       MOV R1 R12
0x000085D3       LI  R3 PAGE_SIZE
0x000085DB       BL  mem_zero                   ; zero out the sensitive new page table

0x000085E3       MOV R1 R12
0x000085E7       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x000085EF   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x000085F3   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x000085F7   LDW R1 [R10 + TASK_PTBR]
0x000085FB       MOV R2 R8
0x000085FF       LI R3 0xFFFFF000
0x00008607       AND R2 R2 R3
0x0000860B       MOV R3 R2
0x0000860F       CMP R9 0
0x00008613       BEQ task_create_map_kernel_entry
0x0000861B       LI R4 USER_RX
0x00008623       B task_create_map_entry
task_create_map_kernel_entry:
0x0000862B       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x00008633       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x0000863B       BL page_alloc
0x00008643       CMP R1 0
0x00008647       BEQ task_create_fail

0x0000864F       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x00008653   STW R12 [R10 + TASK_USTACK_PAGE]

0x00008657       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x0000865F   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x00008663   LDW R1 [R10 + TASK_PTBR]

0x00008667       LI  R2 USER_STACK_VA
0x0000866F       MOV R3 R12
0x00008673       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x0000867B       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x00008683       BL page_alloc
0x0000868B       CMP R1 0
0x0000868F       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x00008697   STW R1 [R10 + TASK_KSTACK_PAGE]
0x0000869B       LI R2 PAGE_SIZE

0x000086A3       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x000086A7       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x000086AB   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x000086AF   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x000086B3       LI R1 0

0x000086BB       PUSH R1            ; R1
0x000086BF       PUSH R1            ; R2
0x000086C3       PUSH R1            ; R3
0x000086C7       PUSH R1            ; R4
0x000086CB       PUSH R1            ; R5
0x000086CF       PUSH R1            ; R6
0x000086D3       PUSH R1            ; R7
0x000086D7       PUSH R1            ; R8
0x000086DB       PUSH R1            ; R9
0x000086DF       PUSH R1            ; R10
0x000086E3       PUSH R1            ; R11
0x000086E7       PUSH R1            ; R12
0x000086EB       PUSH R1            ; R14 (FP)
0x000086EF       PUSH R1            ; R15 (LR)

0x000086F3       PUSH R11           ; R11 - user SP top

0x000086F7       MOV R1 R8
0x000086FB       PUSH R1            ; sepc = entry

0x000086FF       LI R1 0
0x00008707       PUSH R1            ; sflags

0x0000870B       CMP R9 0
0x0000870F       BEQ task_create_kernel_status
0x00008717       LI R1 0x20
0x0000871F       B task_create_status_ready
task_create_kernel_status:
0x00008727       LI R1 0x120
task_create_status_ready:
0x0000872F       PUSH R1            ; sstatus

0x00008733       LI R1 0
0x0000873B       PUSH R1            ; scause
0x0000873F       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x00008743       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x00008747   STW R1 [R10 + TASK_KSP]

0x0000874B       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x0000874F   LI R1 WAIT_NONE
0x00008757   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x0000875B   LI R1 RESUME_TRAP
0x00008763   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x00008767       BL page_alloc
0x0000876F       CMP R1 0
0x00008773       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x0000877B       MOV R12 R1

0x0000877F       LI  R3 PAGE_SIZE
0x00008787       MOV R1 R12
0x0000878B       BL  mem_zero

    ; stdin
0x00008793       LI  R2 file_stdin
0x0000879B       STW R2 [R12 + 0]

    ; stdout
0x0000879F       LI  R2 file_stdout
0x000087A7       STW R2 [R12 + 4]

    ; stderr
0x000087AB       LI  R2 file_stderr
0x000087B3       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x000087B7   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x000087BB       BL page_alloc
0x000087C3       CMP R1 0
0x000087C7       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x000087CF   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x000087D3       BL page_alloc
0x000087DB       CMP R1 0
0x000087DF       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x000087E7   STW R1 [R10 + TASK_KBUF_RD_PTR]

0x000087EB       BL page_alloc
0x000087F3       CMP R1 0
0x000087F7       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x000087FF   STW R1 [R10 + TASK_DATA_PAGE]

0x00008803       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x00008807   LDW R1 [R10 + TASK_PTBR]

0x0000880B       LI  R2 USER_DATA_VA
0x00008813       MOV R3 R12
0x00008817       LI  R4 USER_RW
0x0000881F       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x00008827   LI R1 TASK_READY
0x0000882F   STW R1 [R10 + TASK_STATE]

0x00008833       MOV R1 R10                              ; return created task pointer

0x00008837       POP LR
0x0000883B       RET


task_create_fail:

    ; task_alloc can fail before R10 is assigned.
0x0000883F       CMP R10 0
0x00008843       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x0000884B   LDW R1 [R10 + TASK_PTBR]
0x0000884F       CMP R1 0
0x00008853       BEQ task_create_free_ustack
0x0000885B       BL page_free

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00008863   LDW R1 [R10 + TASK_USTACK_PAGE]
0x00008867       CMP R1 0
0x0000886B       BEQ task_create_free_kstack
0x00008873       BL page_free

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x0000887B   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x0000887F       CMP R1 0
0x00008883       BEQ task_create_free_fd
0x0000888B       BL page_free

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00008893   LDW R1 [R10 + TASK_FD_TABLE]
0x00008897       CMP R1 0
0x0000889B       BEQ task_create_free_kwr
0x000088A3       BL page_free

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x000088AB   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x000088AF       CMP R1 0
0x000088B3       BEQ task_create_free_krd
0x000088BB       BL page_free

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x000088C3   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x000088C7       CMP R1 0
0x000088CB       BEQ task_create_free_data
0x000088D3       BL page_free

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x000088DB   LDW R1 [R10 + TASK_DATA_PAGE]
0x000088DF       CMP R1 0
0x000088E3       BEQ task_create_clear_slot
0x000088EB       BL page_free

task_create_clear_slot:
0x000088F3       MOV R1 R10
0x000088F7       LI R3 TASK_SIZE
0x000088FF       BL mem_zero

task_create_fail_return:
0x00008907       LI R1 0

0x0000890F       POP LR
0x00008913       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x00008917       LI R1 tasks
0x0000891F       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x00008927   LDW R3 [R1 + TASK_STATE]

0x0000892B       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000892F       BEQ task_alloc_found

0x00008937       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x0000893B       SUB R2 R2 1
0x0000893F       BNE task_alloc_loop

; no free tasks slots

0x00008947       LI R1 0
0x0000894F       RET

task_alloc_found:                           ;R1 points to free task slot

0x00008953       RET


; need to define and allocate user stuff at user code
.EQU USER_WRITE_BUF, 0x6000
.EQU USER_READ_BUF,  0x6010

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

; task2 date page
.org 0x1A100
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
[ASM] Built memory.img (106804 bytes)
