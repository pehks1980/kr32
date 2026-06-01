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

.EQU PAGE_SIZE,    0x1000
.EQU PAGE_MASK,    0x0FFF
.EQU PTBR0_VA,     0x00009000
.EQU PTBR1_VA,     0x0000A000
.EQU PTBR2_VA,     0x0000B000

.EQU TASK0_PTBR,   0x00400000   ; one 1 MiB one-level table per address space
.EQU TASK1_PTBR,   0x00500000
.EQU TASK2_PTBR,   0x00600000

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
.EQU CONSOLE_INPUT_LEN, 1
.EQU USER_WRITE_BUF, 0x6000
.EQU USER_READ_BUF,  0x6010

; KBUFFER
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


.org 0x2000

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

        ; ----------------------------------------------------
        ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
        ; ----------------------------------------------------
0x00002030           LI R1 0x00102000
0x00002038           LI R2 3
0x00002040           STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

        ; ----------------------------------------------------
        ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
        ; ----------------------------------------------------
0x00002044           LI R1 0x00101000
0x0000204C           LI R2 2000
0x00002054           STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x00002058           LI R2 3
0x00002060           STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

        ; ----------------------------------------------------
        ; Setup MMIO UART: Enable RX/TX interrupts
        ; ----------------------------------------------------
0x00002064           LI R1 0x00100000
0x0000206C           LI R2 3
0x00002074           STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

        ; Enable MMU and interrupts
0x00002078   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
0x00002080           LI R1 tasks
0x00002088           LDW SP [R1 + TASK_KSP]
0x0000208C           B trap_restore

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x00002094       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x0000209C       LI R2 trap_entry
0x000020A4       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x000020A8       LI R2 trap_entry
0x000020B0       STW R2 [R1+4]                ; IDT[1]
0x000020B4       STW R2 [R1+8]                ; IDT[2]
0x000020B8       STW R2 [R1+12]               ; IDT[3]
0x000020BC       STW R2 [R1+24]               ; IDT[6]
0x000020C0       STW R2 [R1+64]               ; IDT[16]

0x000020C4       SETIDTR R1
0x000020C8       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
0x000020CC       PUSH LR

    ; EVERY TASK owns a different PTBR. Kernel pages are mapped into ALL
    ; address spaces as supervisor global entries; user stack/data pages are
    ; mapped per task to prove same-VA, different-PA isolation.
0x000020D0       LI R1 TASK0_PTBR            ; task 0 page table pointer (phys address)
0x000020D8       BL map_common_kernel        ; map kernel page table for task 0 - a kernel process "idle loop" run in kernel mode
0x000020E0       LI R2 0x00005000            ; page VA -virt addr
0x000020E8       LI R3 TASK0_USTACK_PA       ; page PA -phys addr (.org one)
0x000020F0       LI R4 USER_RW               ; page access matrix stored it page table entry (PTE)
0x000020F8       BL map_page
0x00002100       LI R2 0x00006000
0x00002108       LI R3 TASK0_DATA_PA
0x00002110       LI R4 USER_RW
0x00002118       BL map_page

0x00002120       LI R1 TASK1_PTBR             ; USER task 1 page table pointer (phys address)
0x00002128       BL map_common_kernel
0x00002130       LI R2 0x00005000             ;page used for stack
0x00002138       LI R3 TASK1_USTACK_PA        ; physical address - note! in virtual space virtual address can be the same (like here x05000)
0x00002140       LI R4 USER_RW                ; so mmu does the trick and with help of tlb fast translates vpn to ppn : offset
0x00002148       BL map_page
0x00002150       LI R2 0x00006000             ;page used for data
0x00002158       LI R3 TASK1_DATA_PA
0x00002160       LI R4 USER_RW
0x00002168       BL map_page

0x00002170       LI R1 TASK2_PTBR            ; USER task 2 - same
0x00002178       BL map_common_kernel
0x00002180       LI R2 0x00005000
0x00002188       LI R3 TASK2_USTACK_PA
0x00002190       LI R4 USER_RW
0x00002198       BL map_page
0x000021A0       LI R2 0x00006000
0x000021A8       LI R3 TASK2_DATA_PA
0x000021B0       LI R4 USER_RW
0x000021B8       BL map_page

0x000021C0       LI R1 TASK0_PTBR
0x000021C8       SETPTBR R1
0x000021CC       POP LR
0x000021D0       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x000021D4       PUSH LR

    ; Boot page, kernel/trap code, kernel stacks, scheduler/task metadata,
    ; and the user text page are identity-mapped into every address space.
0x000021D8       LI R2 0x00000000      ;page 0 - boot (0000)
0x000021E0       LI R3 0x00000000
0x000021E8       LI R4 KERNEL_FLAGS
0x000021F0       BL map_page
0x000021F8       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x00002200       LI R3 0x00002000
0x00002208       LI R4 KERNEL_FLAGS
0x00002210       BL map_page
0x00002218       LI R2 0x00003000
0x00002220       LI R3 0x00003000
0x00002228       LI R4 KERNEL_FLAGS
0x00002230       BL map_page
0x00002238       LI R2 0x00004000
0x00002240       LI R3 0x00004000
0x00002248       LI R4 KERNEL_FLAGS
0x00002250       BL map_page
0x00002258       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x00002260       LI R3 0x00007000
0x00002268       LI R4 KERNEL_FLAGS
0x00002270       BL map_page
0x00002278       LI R2 0x00008000      ; page 5 text page (program) for user mode process
0x00002280       LI R3 0x00008000
0x00002288       LI R4 USER_RX
0x00002290       BL map_page
0x00002298       LI R2 0x00019000      ; page 5 text page (program) for user mode process
0x000022A0       LI R3 0x00019000
0x000022A8       LI R4 USER_RX
0x000022B0       BL map_page
0x000022B8       LI R2 0x0001a000      ; page 5 text page (program) for user mode process
0x000022C0       LI R3 0x0001a000
0x000022C8       LI R4 USER_RX
0x000022D0       BL map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x000022D8       LI R2 0x00001000      ; page for kernel buffers
0x000022E0       LI R3 0x00001000
0x000022E8       LI R4 KERNEL_FLAGS
0x000022F0       BL map_page

0x000022F8       LI R2 PTBR0_VA
0x00002300       LI R3 TASK0_PTBR
0x00002308       LI R4 KERNEL_FLAGS
0x00002310       BL map_page

0x00002318       LI R2 PTBR1_VA
0x00002320       LI R3 TASK1_PTBR
0x00002328       LI R4 KERNEL_FLAGS
0x00002330       BL map_page

0x00002338       LI R2 PTBR2_VA
0x00002340       LI R3 TASK2_PTBR
0x00002348       LI R4 KERNEL_FLAGS
0x00002350       BL map_page

    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x00002358       LI R2 0x00100000      ; UART physical and virtual base
0x00002360       LI R3 0x00100000
0x00002368       LI R4 KERNEL_FLAGS
0x00002370       BL map_page

0x00002378       LI R2 0x00101000      ; PIT physical and virtual base
0x00002380       LI R3 0x00101000
0x00002388       LI R4 KERNEL_FLAGS
0x00002390       BL map_page

0x00002398       LI R2 0x00102000      ; PIC physical and virtual base
0x000023A0       LI R3 0x00102000
0x000023A8       LI R4 KERNEL_FLAGS
0x000023B0       BL map_page

0x000023B8       POP LR
0x000023BC       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x000023C0       SHR R5 R2 12               ; VPN
0x000023C4       SHL R5 R5 2                ; page-table byte offset
0x000023C8       OR R6 R3 R4                ; PTE = PA page base | flags
0x000023CC       STW R6 [R1 + R5]
0x000023D0       RET


; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000023D4       ENABLEMMU
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000023D8       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000023DC       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000023E0       PUSH R1
0x000023E4       PUSH R2
0x000023E8       PUSH R3
0x000023EC       PUSH R4
0x000023F0       PUSH R5
0x000023F4       PUSH R6
0x000023F8       PUSH R7
0x000023FC       PUSH R8
0x00002400       PUSH R9
0x00002404       PUSH R10
0x00002408       PUSH R11
0x0000240C       PUSH R12
0x00002410       PUSH R14
0x00002414       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x00002418       CSRR R1 SSCRATCH
0x0000241C       PUSH R1
0x00002420       CSRR R1 SEPC
0x00002424       PUSH R1
0x00002428       CSRR R1 SFLAGS
0x0000242C       PUSH R1
0x00002430       CSRR R1 SSTATUS
0x00002434       PUSH R1
0x00002438       CSRR R1 SCAUSE
0x0000243C       PUSH R1
0x00002440       CSRR R1 STVAL
0x00002444       PUSH R1

    ; Dispatch based on scause.
0x00002448       CSRR R1 SCAUSE
0x0000244C       CMP R1 0
0x00002450       BEQ handle_divide_zero

0x00002458       CMP R1 1
0x0000245C       BEQ handle_invalid_instr

0x00002464       CMP R1 2
0x00002468       BEQ handle_page_fault

0x00002470       CMP R1 3
0x00002474       BEQ handle_syscall

0x0000247C       CMP R1 6
0x00002480       BEQ handle_debug

0x00002488       CMP R1 16
0x0000248C       BEQ handle_irq

    ; Unknown cause - halt
0x00002494       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x00002498       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x000024A0       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x000024A8       HLT

0x000024AC       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x000024B4       CSRR R2 STVAL

0x000024B8       CMP R2 SYS_COUNT
0x000024BC       BGE syscall_unknown

0x000024C4       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000024CC       SHL R4 R2 2
0x000024D0       LDW R5 [R3 + R4]
0x000024D4       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an error code (e.g., 0xFFFFFFFF) in R1 and restore.
;================================================================

0x000024D8       LI R1 0xFFFFFFFF                    ; R1 has error code FFFF
0x000024E0       STW R1 [SP + TF_R1]
0x000024E4       B trap_restore

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

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x00002504       LI R1 0
0x0000250C       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00002510       B schedule_and_switch

syscall_exit:
    ;================================================================
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002518   LI R1 CURRENT_TASK
0x00002520   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002524   LI R1 TASK_SIZE
0x0000252C   MUL R3 R2 R1
0x00002530   LI R5 tasks
0x00002538   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_DEAD
0x0000253C   LI R1 TASK_DEAD
0x00002544   STW R1 [R5 + TASK_STATE]

0x00002548       LI R1 0
0x00002550       STW R1 [SP + TF_R1]         ; r1=0 - return success
0x00002554       B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x0000255C   LI R1 CURRENT_TASK
0x00002564   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002568   LI R1 TASK_SIZE
0x00002570   MUL R3 R2 R1
0x00002574   LI R5 tasks
0x0000257C   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00002580   LDW R1 [R5 + TASK_PID]

0x00002584       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00002588       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00002590       LDW R1 [SP + TF_R1]
0x00002594       STW R1 [SP + TF_R1]

0x00002598       B trap_restore

syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x000025A0       LDW R1 [SP + TF_R1]
0x000025A4       LDW R2 [SP + TF_R2]
0x000025A8       LDW R3 [SP + TF_R3]

0x000025AC       MOV R7 R2               ; save user buffer
0x000025B0       MOV R6 R3               ; save length
0x000025B4       PUSH R7
0x000025B8       PUSH R6
0x000025BC       LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
0x000025C4       BL fetch_fd_entry
0x000025CC       POP R6
0x000025D0       POP R7
0x000025D4       CMP R1 0
0x000025D8       BEQ bad_fd
0x000025E0       MOV R9 R1               ; file object pointer
0x000025E4       MOV R1 R9
0x000025E8       MOV R2 R7
0x000025EC       MOV R3 R6
0x000025F0       BL file_read
0x000025F8       STW R1 [SP + TF_R1]

0x000025FC       B trap_restore

con_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00002604       PUSH LR
0x00002608       MOV R9 R1
0x0000260C       MOV R7 R2
0x00002610       MOV R6 R3
0x00002614       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x00002618       CMP R6 0
0x0000261C       BEQ read_done

0x00002624       PUSH R7
0x00002628       PUSH R6
0x0000262C       PUSH R9
0x00002630       MOV R1 R7
0x00002634       MOV R2 R6
0x00002638       LI R3 1                ; write access for destination buffer
0x00002640       BL user_buffer_valid_range
0x00002648       POP R9
0x0000264C       POP R6
0x00002650       POP R7
0x00002654       CMP R1 1
0x00002658       BNE driver_bad_pointer

read_wait_uart_rx:
0x00002660       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00002664       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00002668       AND R5 R5 1                 ; bit 0 = RX_READY
0x0000266C       CMP R5 0
0x00002670       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

0x00002678       PUSH R7

; macro: GET_CURR_TASK_IDX R4
0x0000267C   LI R1 CURRENT_TASK
0x00002684   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002688   LI R1 TASK_SIZE
0x00002690   MUL R3 R4 R1
0x00002694   LI R5 tasks
0x0000269C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x000026A0   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x000026A4       MOV R2 R6
0x000026A8       MOV R3 R9
0x000026AC       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)

0x000026B4       POP R7

0x000026B8       CMP R1 0
0x000026BC       BEQ read_done

0x000026C4       MOV R2 R1              ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x000026C8   LI R1 CURRENT_TASK
0x000026D0   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x000026D4   LI R1 TASK_SIZE
0x000026DC   MUL R3 R5 R1
0x000026E0   LI R4 tasks
0x000026E8   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000026EC   LDW R4 [R4 + TASK_KBUF_RD_PTR]

0x000026F0       MOV R1 R7              ; user destination
0x000026F4       BL copy_to_user        ; copy from kernel buffer to user buffer

0x000026FC       POP LR
0x00002700       RET

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00002704       LI R1 uart_rx_waitq
0x0000270C       LI R2 WAIT_UART_RX
0x00002714       BL waitq_prepare_sleep

0x0000271C       LDW R4 [R9 + UARTDEV_MMIO]
0x00002720       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x00002724       AND R10 R10 1
0x00002728       CMP R10 0
0x0000272C       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x00002734       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x0000273C       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00002744       LI R1 uart_rx_waitq
0x0000274C       BL waitq_cancel_sleep_current

0x00002754       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x0000275C       LI R1 0
0x00002764       POP LR
0x00002768       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x0000276C       LDW R1 [SP + TF_R1]
0x00002770       LDW R2 [SP + TF_R2]
0x00002774       LDW R3 [SP + TF_R3]
; first fetch file from procs fd_table and check flags for match access WRITE /READ
0x00002778       MOV R7 R2               ; save user buffer
0x0000277C       MOV R6 R3               ; save length
0x00002780       PUSH R7
0x00002784       PUSH R6
0x00002788       LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
0x00002790       BL fetch_fd_entry       ;input R1 fd on exit R1 - file ptr  => r1=fetch_fd_entry(fd=r1)
0x00002798       POP R6
0x0000279C       POP R7
0x000027A0       CMP R1 0
0x000027A4       BEQ bad_fd              ;if flags file and in r2 dont match
0x000027AC       MOV R9 R1               ; file object pointer
0x000027B0       MOV R1 R9
0x000027B4       MOV R2 R7
0x000027B8       MOV R3 R6
0x000027BC       BL file_write           ; call file write R1 = file ptr, R2 = user buffer, R3 = len
0x000027C4       STW R1 [SP + TF_R1]

0x000027C8       B trap_restore

con_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x000027D0       PUSH LR
0x000027D4       MOV R9 R1
0x000027D8       MOV R7 R2
0x000027DC       MOV R6 R3
0x000027E0       LDW R9 [R9 + FILE_PRIVATE] ; console device pointer
0x000027E4       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x000027EC       CMP R6 0
0x000027F0       BEQ write_done             ;0 bytes

0x000027F8       LI R2 KBUFFER_SIZE
0x00002800       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00002804       BLT write_chunk_small
0x0000280C       LI R2 KBUFFER_SIZE

0x00002814       B write_chunk

write_chunk_small:
0x0000281C       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x00002820       PUSH R7
0x00002824       PUSH R6
0x00002828       PUSH R9
0x0000282C       PUSH R8
0x00002830       MOV R1 R7
0x00002834       MOV R2 R2
0x00002838       LI R3 0                ; read access for source buffer
0x00002840       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00002848       POP R8
0x0000284C       POP R9
0x00002850       POP R6
0x00002854       POP R7
0x00002858       CMP R1 1
0x0000285C       BNE driver_bad_pointer

0x00002864       PUSH R7
0x00002868       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x0000286C   LI R1 CURRENT_TASK
0x00002874   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002878   LI R1 TASK_SIZE
0x00002880   MUL R3 R4 R1
0x00002884   LI R5 tasks
0x0000288C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00002890   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00002894       MOV R1 R7
0x00002898       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x000028A0       MOV R10 R1             ; bytes copied
0x000028A4       POP R6
0x000028A8       POP R7

0x000028AC       PUSH R7
0x000028B0       PUSH R9
0x000028B4       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x000028B8       LDW R1 [R9 + UARTDEV_MMIO]
0x000028BC       LDW R2 [R1 + 4]
0x000028C0       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x000028C4       CMP R2 0
0x000028C8       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x000028D0   LI R1 CURRENT_TASK
0x000028D8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000028DC   LI R1 TASK_SIZE
0x000028E4   MUL R3 R4 R1
0x000028E8   LI R5 tasks
0x000028F0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x000028F4   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x000028F8       MOV R2 R10
0x000028FC       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x00002900       BL device_write
0x00002908       POP R6
0x0000290C       POP R9
0x00002910       POP R7

0x00002914       CMP R1 0        ;nothing is written - go again
0x00002918       BEQ write_loop

0x00002920       ADD R8 R8 R1     ;update ptrs
0x00002924       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x00002928       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x0000292C       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00002934       LI R1 uart_tx_waitq
0x0000293C       LI R2 WAIT_UART_TX
0x00002944       BL waitq_prepare_sleep

0x0000294C       LDW R1 [R9 + UARTDEV_MMIO]
0x00002950       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00002954       AND R2 R2 2
0x00002958       CMP R2 0
0x0000295C       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00002964       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x0000296C       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00002974       LI R1 uart_tx_waitq
0x0000297C       BL waitq_cancel_sleep_current

0x00002984       B write_wait_uart_tx

write_done:
0x0000298C       MOV R1 R8
0x00002990       POP LR
0x00002994       RET

driver_bad_pointer:
0x00002998       LI R1 0xFFF0
0x000029A0       POP LR
0x000029A4       RET

bad_fd:
0x000029A8       LI R1 0xFFF1
0x000029B0       STW R1 [SP + TF_R1]

0x000029B4       B trap_restore

bad_pointer:
0x000029BC       LI R1 0xFFF2
0x000029C4       STW R1 [SP + TF_R1]

0x000029C8       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x000029D0       LDW R4 [R1 + FILE_OPS]
0x000029D4       LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
0x000029D8       JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x000029DC       LDW R4 [R1 + FILE_OPS]
0x000029E0       LDW R4 [R4 + FOPS_WRITE]    ; get write function xdev_write from ops
0x000029E4       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000029E8       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000029F0       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x000029F8       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000029FC       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00002A04       CMP R5 R2                   ; have we read enough bytes?
0x00002A08       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x00002A10       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00002A14       AND R6 R6 1                 ; bit 0 = RX_READY
0x00002A18       CMP R6 0
0x00002A1C       BEQ dr_done                 ; no more buffered input available

0x00002A24       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x00002A28       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00002A2C       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x00002A30       CMP R7 10
0x00002A34       BEQ dr_done

0x00002A3C       B dr_loop

dr_done:
0x00002A44       MOV R1 R5                   ; return number of bytes actually read
0x00002A48       RET

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

0x00002A4C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00002A50       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x00002A58       CMP R5 R2                   ; have we written all bytes?
0x00002A5C       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00002A64       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00002A68       AND R6 R6 2                 ; bit 1 = TX_READY
0x00002A6C       CMP R6 0
0x00002A70       BEQ dcw_done

0x00002A78       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x00002A7C       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00002A80       ADD R5 R5 1
0x00002A84       B dcw_loop

dcw_done:
0x00002A8C       MOV R1 R5                   ; return number of bytes written
0x00002A90       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, 3)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

0x00002A94       CMP R1 0
0x00002A98       BLT fd_invalid
0x00002AA0       CMP R1 3
0x00002AA4       BGE fd_invalid

0x00002AAC       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x00002AB0   LI R1 CURRENT_TASK
0x00002AB8   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00002ABC   LI R1 TASK_SIZE
0x00002AC4   MUL R3 R4 R1
0x00002AC8   LI R4 tasks
0x00002AD0   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x00002AD4   LDW R4 [R4 + TASK_FD_TABLE]

0x00002AD8       SHL R5 R8 2
0x00002ADC       ADD R4 R4 R5                ;r4=fd*4+FD_TABLE = file entry according to fd
0x00002AE0       LDW R1 [R4]                 ; R1 = file ptr
0x00002AE4       LDW R6 [R1 + FILE_FLAGS]
0x00002AE8       AND R6 R6 R2
0x00002AEC       CMP R6 R2                   ;check file flags R2 input R6 from file
0x00002AF0       BNE fd_invalid

0x00002AF8       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x00002AFC       LI R1 0
0x00002B04       RET

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

0x00002B08       LI R4 0
0x00002B10       CMP R2 R4
0x00002B14       BEQ uv_valid

0x00002B1C       LI R4 USER_BASE
0x00002B24       CMP R1 R4
0x00002B28       BLT uv_invalid

0x00002B30       LI R4 USER_LIMIT
0x00002B38       ADD R5 R1 R2
0x00002B3C       SUB R5 R5 1
0x00002B40       CMP R5 R1
0x00002B44       BLT uv_invalid
0x00002B4C       CMP R5 R4
0x00002B50       BGT uv_invalid
0x00002B58       MOV R11 R1              ; save start address; task macros clobber R1
0x00002B5C       MOV R12 R5              ; save end address for page calculation
0x00002B60       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x00002B64   LI R1 CURRENT_TASK
0x00002B6C   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00002B70   LI R1 TASK_SIZE
0x00002B78   MUL R3 R6 R1
0x00002B7C   LI R6 tasks
0x00002B84   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00002B88   LDW R6 [R6 + TASK_PTBR]
0x00002B8C       LI R7 TASK0_PTBR

0x00002B94       CMP R6 R7
0x00002B98       BEQ uv_ptbr0
0x00002BA0       LI R7 TASK1_PTBR
0x00002BA8       CMP R6 R7
0x00002BAC       BEQ uv_ptbr1
0x00002BB4       LI R7 TASK2_PTBR
0x00002BBC       CMP R6 R7
0x00002BC0       BEQ uv_ptbr2
0x00002BC8       B uv_invalid

uv_ptbr0:
0x00002BD0       LI R6 PTBR0_VA
0x00002BD8       B uv_check_pages
uv_ptbr1:
0x00002BE0       LI R6 PTBR1_VA
0x00002BE8       B uv_check_pages
uv_ptbr2:
0x00002BF0       LI R6 PTBR2_VA

uv_check_pages:
0x00002BF8       SHR R7 R11 12
0x00002BFC       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00002C00       CMP R7 R8
0x00002C04       BGT uv_valid
0x00002C0C       SHL R9 R7 2
0x00002C10       ADD R9 R9 R6
0x00002C14       LDW R10 [R9]
0x00002C18       AND R5 R10 PTE_P
0x00002C1C       CMP R5 0
0x00002C20       BEQ uv_invalid
0x00002C28       AND R5 R10 PTE_U
0x00002C2C       CMP R5 0
0x00002C30       BEQ uv_invalid
0x00002C38       CMP R4 0
0x00002C3C       BEQ uv_check_read
0x00002C44       AND R5 R10 PTE_W
0x00002C48       CMP R5 0
0x00002C4C       BEQ uv_invalid
0x00002C54       B uv_next

uv_check_read:
0x00002C5C       AND R5 R10 PTE_R
0x00002C60       CMP R5 0
0x00002C64       BEQ uv_invalid

uv_next:
0x00002C6C       ADD R7 R7 1
0x00002C70       B uv_loop

uv_valid:
0x00002C78       LI R1 1
0x00002C80       RET

uv_invalid:
0x00002C84       LI R1 0
0x00002C8C       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00002C90       LI R5 0
cfu_head:
0x00002C98       CMP R2 0
0x00002C9C       BEQ cfu_done
0x00002CA4       OR R6 R1 R4
0x00002CA8       AND R6 R6 3
0x00002CAC       CMP R6 0
0x00002CB0       BEQ cfu_word
0x00002CB8       LDB R7 [R1]
0x00002CBC       STB R7 [R4]
0x00002CC0       ADD R1 R1 1
0x00002CC4       ADD R4 R4 1
0x00002CC8       ADD R5 R5 1
0x00002CCC       SUB R2 R2 1
0x00002CD0       B cfu_head
cfu_word:
0x00002CD8       CMP R2 4
0x00002CDC       BLT cfu_tail
0x00002CE4       LDW R7 [R1]
0x00002CE8       STW R7 [R4]
0x00002CEC       ADD R1 R1 4
0x00002CF0       ADD R4 R4 4
0x00002CF4       ADD R5 R5 4
0x00002CF8       SUB R2 R2 4
0x00002CFC       B cfu_word
cfu_tail:
0x00002D04       CMP R2 0
0x00002D08       BEQ cfu_done
0x00002D10       LDB R7 [R1]
0x00002D14       STB R7 [R4]
0x00002D18       ADD R1 R1 1
0x00002D1C       ADD R4 R4 1
0x00002D20       ADD R5 R5 1
0x00002D24       SUB R2 R2 1
0x00002D28       B cfu_tail
cfu_done:
0x00002D30       MOV R1 R5
0x00002D34       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00002D38       LI R5 0
ctu_head:
0x00002D40       CMP R2 0
0x00002D44       BEQ ctu_done
0x00002D4C       OR R6 R1 R4
0x00002D50       AND R6 R6 3
0x00002D54       CMP R6 0
0x00002D58       BEQ ctu_word
0x00002D60       LDB R7 [R4]
0x00002D64       STB R7 [R1]
0x00002D68       ADD R1 R1 1
0x00002D6C       ADD R4 R4 1
0x00002D70       ADD R5 R5 1
0x00002D74       SUB R2 R2 1
0x00002D78       B ctu_head
ctu_word:
0x00002D80       CMP R2 4
0x00002D84       BLT ctu_tail
0x00002D8C       LDW R7 [R4]
0x00002D90       STW R7 [R1]
0x00002D94       ADD R1 R1 4
0x00002D98       ADD R4 R4 4
0x00002D9C       ADD R5 R5 4
0x00002DA0       SUB R2 R2 4
0x00002DA4       B ctu_word
ctu_tail:
0x00002DAC       CMP R2 0
0x00002DB0       BEQ ctu_done
0x00002DB8       LDB R7 [R4]
0x00002DBC       STB R7 [R1]
0x00002DC0       ADD R1 R1 1
0x00002DC4       ADD R4 R4 1
0x00002DC8       ADD R5 R5 1
0x00002DCC       SUB R2 R2 1
0x00002DD0       B ctu_tail
ctu_done:
0x00002DD8       MOV R1 R5
0x00002DDC       RET

handle_debug:
    ; Debug trap - just return
0x00002DE0       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00002DE8       CSRR R1 STVAL

0x00002DEC       CMP R1 0
0x00002DF0       BEQ handle_timer_irq

0x00002DF8       CMP R1 1
0x00002DFC       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00002E04       LI R2 0x00102000
0x00002E0C       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x00002E10       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00002E18       LI R2 0x00102000
0x00002E20       LI R3 0
0x00002E28       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Yield the CPU (reschedule and switch tasks)
0x00002E2C       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00002E34       LI R2 0x00102000
0x00002E3C       LI R3 1
0x00002E44       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00002E48       LI R1 uart_rx_waitq
0x00002E50       BL waitq_wake_all
0x00002E58       LI R1 uart_tx_waitq
0x00002E60       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00002E68       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00002E70       POP R1                  ; stval, informational only
0x00002E74       POP R1                  ; scause, informational only
0x00002E78       POP R1
0x00002E7C       CSRW SSTATUS R1
0x00002E80       POP R1
0x00002E84       CSRW SFLAGS R1
0x00002E88       POP R1
0x00002E8C       CSRW SEPC R1
0x00002E90       POP R1                  ; interrupted task SP
0x00002E94       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00002E98       POP R15
0x00002E9C       POP R14
0x00002EA0       POP R12
0x00002EA4       POP R11
0x00002EA8       POP R10
0x00002EAC       POP R9
0x00002EB0       POP R8
0x00002EB4       POP R7
0x00002EB8       POP R6
0x00002EBC       POP R5
0x00002EC0       POP R4
0x00002EC4       POP R3
0x00002EC8       POP R2
0x00002ECC       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00002ED0       CSRRW SP SSCRATCH SP
0x00002ED4       SRET


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
.EQU SYS_COUNT,    6

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
; File descriptor table and device objects
;==============================================================

fd_table:
    .WORD file_stdin
    .WORD file_stdout
    .WORD file_stderr

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

0x000070E8       PUSH R9
0x000070EC       PUSH R10

0x000070F0       MOV R9 R1                  ; preserve wait queue pointer
0x000070F4       MOV R10 R2                 ; preserve debug wait reason

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x000070F8   LI R1 CURRENT_TASK
0x00007100   LDW R2 [R1]

0x00007104       LI R4 1
0x0000710C       SHL R4 R4 R2               ; R4 = bit for current task
0x00007110       LDW R5 [R9 + WQ_MASK]
0x00007114       OR R5 R5 R4
0x00007118       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x0000711C   LI R1 TASK_SIZE
0x00007124   MUL R3 R2 R1
0x00007128   LI R5 tasks
0x00007130   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00007134   LI R1 TASK_BLOCKED_IO
0x0000713C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00007140   STW R10 [R5 + TASK_WAIT]

0x00007144       POP R10
0x00007148       POP R9
0x0000714C       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00007150       PUSH R9

0x00007154       MOV R9 R1
; macro: GET_CURR_TASK_IDX R2
0x00007158   LI R1 CURRENT_TASK
0x00007160   LDW R2 [R1]

0x00007164       LDW R4 [R9 + WQ_MASK]
0x00007168       CMP R2 0
0x0000716C       BEQ wq_cancel_task0
0x00007174       CMP R2 1
0x00007178       BEQ wq_cancel_task1

0x00007180       LI R5 3                    ; clear bit 2, keep bits 0..1
0x00007188       AND R4 R4 R5
0x0000718C       B wq_cancel_store

wq_cancel_task0:
0x00007194       LI R5 6                    ; clear bit 0, keep bits 1..2
0x0000719C       AND R4 R4 R5
0x000071A0       B wq_cancel_store

wq_cancel_task1:
0x000071A8       LI R5 5                    ; clear bit 1, keep bits 0 and 2
0x000071B0       AND R4 R4 R5

wq_cancel_store:
0x000071B4       STW R4 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x000071B8   LI R1 TASK_SIZE
0x000071C0   MUL R3 R2 R1
0x000071C4   LI R5 tasks
0x000071CC   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x000071D0   LI R1 TASK_READY
0x000071D8   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x000071DC   LI R1 WAIT_NONE
0x000071E4   STW R1 [R5 + TASK_WAIT]

0x000071E8       POP R9
0x000071EC       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000071F0       PUSH LR
0x000071F4       BL schedule_call
0x000071FC       POP LR
0x00007200       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x00007204       PUSH LR

0x00007208       MOV R9 R1
0x0000720C       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00007210       LI R10 0
0x00007218       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x0000721C       LI R2 0                    ; task index

wq_wake_loop:
0x00007224       CMP R2 3
0x00007228       BGE wq_wake_done

0x00007230       LI R3 1
0x00007238       SHL R3 R3 R2               ; R3 = bit for task R2
0x0000723C       AND R4 R8 R3
0x00007240       CMP R4 0
0x00007244       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x0000724C   LI R1 TASK_SIZE
0x00007254   MUL R3 R2 R1
0x00007258   LI R5 tasks
0x00007260   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00007264   LI R1 TASK_READY
0x0000726C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00007270   LI R1 WAIT_NONE
0x00007278   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x0000727C       ADD R2 R2 1
0x00007280       B wq_wake_loop

wq_wake_done:
0x00007288       POP LR
0x0000728C       RET

; just for info ref here actual .equ in the beginning
; flags def
;EQU FD_FLAG_READ,    1
;EQU FD_FLAG_WRITE,   2

; file
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

; ================================================================
; INIT SCHEDULER
; ================================================================

init_scheduler:
0x00007290       MOV R12 SP ;important we save kernel sp becuse we form stack frame at tasks SPs

    ; ------------------------------------------------
    ; Task 0
    ; ------------------------------------------------

    ;================================================================
    ; Build the initial trapframe on the task's kernel stack. It has
    ; the same shape as an IRQ-created trapframe, so first dispatch and
    ; later preemptive resumes use the exact same restore path.
    ;================================================================

0x00007294       LI SP TASK0_KSTACK_TOP

0x0000729C       LI R1 0
0x000072A4       PUSH R1                  ; R1
0x000072A8       PUSH R1                  ; R2
0x000072AC       PUSH R1                  ; R3
0x000072B0       PUSH R1                  ; R4
0x000072B4       PUSH R1                  ; R5
0x000072B8       PUSH R1                  ; R6
0x000072BC       PUSH R1                  ; R7
0x000072C0       PUSH R1                  ; R8
0x000072C4       PUSH R1                  ; R9
0x000072C8       PUSH R1                  ; R10
0x000072CC       PUSH R1                  ; R11
0x000072D0       PUSH R1                  ; R12
0x000072D4       PUSH R1                  ; R14
0x000072D8       PUSH R1                  ; R15
0x000072DC       LI R1 TASK0_USTACK_TOP
0x000072E4       PUSH R1                  ; interrupted task SP restored by CSRRW before SRET
0x000072E8       LI R1 idle_task
0x000072F0       PUSH R1                  ; sepc - this is new place of PC in trap frame
0x000072F4       LI R1 0
0x000072FC       PUSH R1                  ; sflags
0x00007300       LI R1 0x120
0x00007308       PUSH R1                  ; sstatus.SPIE|SPP: idle resumes as supervisor task
0x0000730C       LI R1 0
0x00007314       PUSH R1                  ; scause
0x00007318       PUSH R1                  ; stval - other valuable s-data on top (or bottom-)

0x0000731C       LI R2 tasks
0x00007324       MOV R1 SP
; macro: TASK_SET_KSP R2, R1     ; save kernel trapframe SP
0x00007328   STW R1 [R2 + TASK_KSP]

0x0000732C       LI R1 TASK0_USTACK_TOP
; macro: TASK_SET_USP R2, R1     ; save initial task stack SP for debug/metadata
0x00007334   STW R1 [R2 + TASK_USP]

0x00007338       LI R1 idle_task
; macro: TASK_SET_PC R2, R1      ;start PC of the task
0x00007340   STW R1 [R2 + TASK_PC]

; macro: TASK_SET_STATE R2, TASK_READY ;set this task as as ready to run
0x00007344   LI R1 TASK_READY
0x0000734C   STW R1 [R2 + TASK_STATE]

0x00007350       LI R1 0
; macro: TASK_SET_PID R2, R1      ;set PID=0 for this task
0x00007358   STW R1 [R2 + TASK_PID]

0x0000735C       LI R1 TASK0_PTBR            ;set page table ptr
; macro: TASK_SET_PTBR R2, R1
0x00007364   STW R1 [R2 + TASK_PTBR]

0x00007368       LI R1 fd_table
; macro: TASK_SET_FD_TABLE R2, R1 ;set fd_table ptr
0x00007370   STW R1 [R2 + TASK_FD_TABLE]

; macro: TASK_SET_WAIT R2, WAIT_NONE ;set wait reason field
0x00007374   LI R1 WAIT_NONE
0x0000737C   STW R1 [R2 + TASK_WAIT]
; macro: TASK_SET_RESUME R2, RESUME_TRAP ;set sleep switch kernel/user depending where it z-z-z
0x00007380   LI R1 RESUME_TRAP
0x00007388   STW R1 [R2 + TASK_RESUME]
; macro: TASK_SET_KBUF_WR R2, KBUFFER_WR_0 ;set this task kernel buffers rd/wr
0x0000738C   LI R1 KBUFFER_WR_0
0x00007394   STW R1 [R2 + TASK_KBUF_WR_PTR]
; macro: TASK_SET_KBUF_RD R2, KBUFFER_RD_0
0x00007398   LI R1 KBUFFER_RD_0
0x000073A0   STW R1 [R2 + TASK_KBUF_RD_PTR]
    ;when we can alloc and exec and fork
    ;special mem subsystem will init/alloc/dealloc all that automatically

    ; ------------------------------------------------
    ; Task 1 - do the same
    ; ------------------------------------------------

0x000073A4       LI SP TASK1_KSTACK_TOP
0x000073AC       LI R1 0
0x000073B4       PUSH R1                  ; R1
0x000073B8       PUSH R1                  ; R2
0x000073BC       PUSH R1                  ; R3
0x000073C0       PUSH R1                  ; R4
0x000073C4       PUSH R1                  ; R5
0x000073C8       PUSH R1                  ; R6
0x000073CC       PUSH R1                  ; R7
0x000073D0       PUSH R1                  ; R8
0x000073D4       PUSH R1                  ; R9
0x000073D8       PUSH R1                  ; R10
0x000073DC       PUSH R1                  ; R11
0x000073E0       PUSH R1                  ; R12
0x000073E4       PUSH R1                  ; R14
0x000073E8       PUSH R1                  ; R15
0x000073EC       LI R1 TASK1_USTACK_TOP
0x000073F4       PUSH R1                  ; interrupted task SP
0x000073F8       LI R1 TASK_A_START
0x00007400       PUSH R1                  ; sepc
0x00007404       LI R1 0
0x0000740C       PUSH R1                  ; sflags
0x00007410       LI R1 0x20
0x00007418       PUSH R1                  ; sstatus.SPIE
0x0000741C       LI R1 0
0x00007424       PUSH R1                  ; scause
0x00007428       PUSH R1                  ; stval

0x0000742C       LI R2 tasks
0x00007434       ADD R2 R2 TASK_SIZE

0x00007438       MOV R1 SP
; macro: TASK_SET_KSP R2, R1
0x0000743C   STW R1 [R2 + TASK_KSP]

0x00007440       LI R1 TASK1_USTACK_TOP
; macro: TASK_SET_USP R2, R1
0x00007448   STW R1 [R2 + TASK_USP]

0x0000744C       LI R1 TASK_A_START
; macro: TASK_SET_PC R2, R1
0x00007454   STW R1 [R2 + TASK_PC]

; macro: TASK_SET_STATE R2, TASK_READY
0x00007458   LI R1 TASK_READY
0x00007460   STW R1 [R2 + TASK_STATE]

0x00007464       LI R1 1
; macro: TASK_SET_PID R2, R1
0x0000746C   STW R1 [R2 + TASK_PID]

0x00007470       LI R1 TASK1_PTBR
; macro: TASK_SET_PTBR R2, R1
0x00007478   STW R1 [R2 + TASK_PTBR]
0x0000747C       LI R1 fd_table
; macro: TASK_SET_FD_TABLE R2, R1
0x00007484   STW R1 [R2 + TASK_FD_TABLE]
; macro: TASK_SET_WAIT R2, WAIT_NONE
0x00007488   LI R1 WAIT_NONE
0x00007490   STW R1 [R2 + TASK_WAIT]
; macro: TASK_SET_RESUME R2, RESUME_TRAP
0x00007494   LI R1 RESUME_TRAP
0x0000749C   STW R1 [R2 + TASK_RESUME]
; macro: TASK_SET_KBUF_WR R2, KBUFFER_WR_1
0x000074A0   LI R1 KBUFFER_WR_1
0x000074A8   STW R1 [R2 + TASK_KBUF_WR_PTR]
; macro: TASK_SET_KBUF_RD R2, KBUFFER_RD_1
0x000074AC   LI R1 KBUFFER_RD_1
0x000074B4   STW R1 [R2 + TASK_KBUF_RD_PTR]

    ; ------------------------------------------------
    ; Task 2 - same
    ; ------------------------------------------------

0x000074B8       LI SP TASK2_KSTACK_TOP
0x000074C0       LI R1 0
0x000074C8       PUSH R1                  ; R1
0x000074CC       PUSH R1                  ; R2
0x000074D0       PUSH R1                  ; R3
0x000074D4       PUSH R1                  ; R4
0x000074D8       PUSH R1                  ; R5
0x000074DC       PUSH R1                  ; R6
0x000074E0       PUSH R1                  ; R7
0x000074E4       PUSH R1                  ; R8
0x000074E8       PUSH R1                  ; R9
0x000074EC       PUSH R1                  ; R10
0x000074F0       PUSH R1                  ; R11
0x000074F4       PUSH R1                  ; R12
0x000074F8       PUSH R1                  ; R14
0x000074FC       PUSH R1                  ; R15
0x00007500       LI R1 TASK2_USTACK_TOP
0x00007508       PUSH R1                  ; interrupted task SP
0x0000750C       LI R1 TASK_B_START
0x00007514       PUSH R1                  ; sepc
0x00007518       LI R1 0
0x00007520       PUSH R1                  ; sflags
0x00007524       LI R1 0x20
0x0000752C       PUSH R1                  ; sstatus.SPIE
0x00007530       LI R1 0
0x00007538       PUSH R1                  ; scause
0x0000753C       PUSH R1                  ; stval

0x00007540       LI R2 tasks
0x00007548       LI R3 TASK_SIZE
0x00007550       ADD R2 R2 R3
0x00007554       ADD R2 R2 R3

0x00007558       MOV R1 SP
; macro: TASK_SET_KSP R2, R1
0x0000755C   STW R1 [R2 + TASK_KSP]

0x00007560       LI R1 TASK2_USTACK_TOP
; macro: TASK_SET_USP R2, R1
0x00007568   STW R1 [R2 + TASK_USP]

0x0000756C       LI R1 TASK_B_START
; macro: TASK_SET_PC R2, R1
0x00007574   STW R1 [R2 + TASK_PC]

; macro: TASK_SET_STATE R2, TASK_READY
0x00007578   LI R1 TASK_READY
0x00007580   STW R1 [R2 + TASK_STATE]

0x00007584       LI R1 2
; macro: TASK_SET_PID R2, R1
0x0000758C   STW R1 [R2 + TASK_PID]

0x00007590       LI R1 TASK2_PTBR
; macro: TASK_SET_PTBR R2, R1
0x00007598   STW R1 [R2 + TASK_PTBR]
0x0000759C       LI R1 fd_table
; macro: TASK_SET_FD_TABLE R2, R1
0x000075A4   STW R1 [R2 + TASK_FD_TABLE]
; macro: TASK_SET_WAIT R2, WAIT_NONE
0x000075A8   LI R1 WAIT_NONE
0x000075B0   STW R1 [R2 + TASK_WAIT]
; macro: TASK_SET_RESUME R2, RESUME_TRAP
0x000075B4   LI R1 RESUME_TRAP
0x000075BC   STW R1 [R2 + TASK_RESUME]
; macro: TASK_SET_KBUF_WR R2, KBUFFER_WR_2
0x000075C0   LI R1 KBUFFER_WR_2
0x000075C8   STW R1 [R2 + TASK_KBUF_WR_PTR]
; macro: TASK_SET_KBUF_RD R2, KBUFFER_RD_2
0x000075CC   LI R1 KBUFFER_RD_2
0x000075D4   STW R1 [R2 + TASK_KBUF_RD_PTR]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x000075D8       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x000075E0   LI R1 CURRENT_TASK
0x000075E8   STW R2 [R1]

0x000075EC       MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x000075F0       RET

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x000075F4   LI R1 CURRENT_TASK
0x000075FC   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x00007600       ADD R3 R2 1

wrap_check:

0x00007604       CMP R3 3
0x00007608       BLT check_task
0x00007610       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x00007618       LI R4 TASK_SIZE
0x00007620       MUL R5 R3 R4
0x00007624       LI R6 tasks
0x0000762C       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00007630       LDW R7 [R5 + TASK_STATE]

0x00007634       CMP R7 1
0x00007638       BEQ do_switch
    ; if not ready go to next task in list
0x00007640       ADD R3 R3 1
0x00007644       B wrap_check

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
0x0000764C   LI R1 CURRENT_TASK
0x00007654   STW R3 [R1]
0x00007658       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x0000765C   LI R1 TASK_SIZE
0x00007664   MUL R3 R2 R1
0x00007668   LI R5 tasks
0x00007670   ADD R5 R5 R3
0x00007674       MOV R3 R8

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x00007678       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x0000767C   STW R7 [R5 + TASK_USP]

0x00007680       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00007684   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x00007688   LI R1 RESUME_TRAP
0x00007690   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00007694   LI R1 TASK_SIZE
0x0000769C   MUL R3 R8 R1
0x000076A0   LI R5 tasks
0x000076A8   ADD R5 R5 R3
0x000076AC       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x000076B0   LDW R7 [R5 + TASK_PTBR]
0x000076B4       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x000076B8   LDW SP [R5 + TASK_KSP]

; macro: TASK_GET_RESUME R7, R5
0x000076BC   LDW R7 [R5 + TASK_RESUME]
0x000076C0       CMP R7 RESUME_KERNEL
0x000076C4       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x000076CC       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x000076D4       PUSH R1
0x000076D8       PUSH R2
0x000076DC       PUSH R3
0x000076E0       PUSH R4
0x000076E4       PUSH R5
0x000076E8       PUSH R6
0x000076EC       PUSH R7
0x000076F0       PUSH R8
0x000076F4       PUSH R9
0x000076F8       PUSH R10
0x000076FC       PUSH R11
0x00007700       PUSH R12
0x00007704       PUSH R14
0x00007708       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x0000770C   LI R1 CURRENT_TASK
0x00007714   LDW R2 [R1]

0x00007718       ADD R3 R2 1

schedule_call_wrap_check:
0x0000771C       CMP R3 3
0x00007720       BLT schedule_call_check_task
0x00007728       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00007730       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x00007734   LI R1 TASK_SIZE
0x0000773C   MUL R3 R8 R1
0x00007740   LI R5 tasks
0x00007748   ADD R5 R5 R3
0x0000774C       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00007750   LDW R7 [R5 + TASK_STATE]
0x00007754       CMP R7 TASK_READY               ; check it can be run
0x00007758       BEQ schedule_call_do_switch

0x00007760       ADD R3 R3 1
0x00007764       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x0000776C   LI R1 CURRENT_TASK
0x00007774   STW R3 [R1]
0x00007778       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x0000777C   LI R1 TASK_SIZE
0x00007784   MUL R3 R2 R1
0x00007788   LI R5 tasks
0x00007790   ADD R5 R5 R3
0x00007794       MOV R3 R8

0x00007798       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x0000779C   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x000077A0   LI R1 RESUME_KERNEL
0x000077A8   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x000077AC   LI R1 TASK_SIZE
0x000077B4   MUL R3 R8 R1
0x000077B8   LI R5 tasks
0x000077C0   ADD R5 R5 R3
0x000077C4       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x000077C8   LDW R7 [R5 + TASK_PTBR]
0x000077CC       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x000077D0   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x000077D4   LDW R7 [R5 + TASK_RESUME]
0x000077D8       CMP R7 RESUME_KERNEL
0x000077DC       BEQ restore_kernel_context

0x000077E4       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x000077EC       DISABLEINT                  ; RET does jump by LR(R15)
0x000077F0       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x000077F4       POP R14                     ; (in kernel)
0x000077F8       POP R12                     ; DI - to avoid int nesting
0x000077FC       POP R11
0x00007800       POP R10
0x00007804       POP R9
0x00007808       POP R8
0x0000780C       POP R7
0x00007810       POP R6
0x00007814       POP R5
0x00007818       POP R4
0x0000781C       POP R3
0x00007820       POP R2
0x00007824       POP R1
0x00007828       RET


; ================================================================
; TASKS
; ================================================================

.ORG 0x8000

; --TASK 0 ----------------------------------------------


idle_task:
0x00008000       ENABLEINT
0x00008004       LI R1 0
idle_loop:
0x0000800C       ADD R1 R1 1
0x00008010       DEBUG 1
    ;trace anti-clutter sequence-)
0x00008014       LI R1 SYS_EXIT
0x0000801C       SVC SYS_EXIT
0x00008020       B idle_loop

; --TASK 1----------------------------------------------
.ORG 0x19000
TASK_A_START:
    ;DEBUG 2
    ; Prepare a write string in user memory.
0x00019000       LI R1 USER_WRITE_BUF
0x00019008       LI R2 0x6C6C6548         ; "Hell"
0x00019010       STW R2 [R1]
0x00019014       LI R2 0x57202C6F         ; "o, W"
0x0001901C       STW R2 [R1 + 4]
0x00019020       LI R2 0x646C726F         ; "orld"
0x00019028       STW R2 [R1 + 8]
0x0001902C       LI R2 0x21
0x00019034       STB R2 [R1 + 12]
0x00019038       LI R2 0x0A
0x00019040       STB R2 [R1 + 13]

0x00019044       LI R1 1                 ;fd
   ; DEBUG 1
0x0001904C       LI R2 USER_WRITE_BUF    ; user buff
0x00019054       LI R3 14                ; len
0x0001905C       SVC SYS_WRITE
0x00019060       DEBUG 1
    ; Exit after the write test.
0x00019064       LI R1 SYS_EXIT
0x0001906C       SVC SYS_EXIT

; ---TASK 2---------------------------------------------

.org 0x1a000
TASK_B_START:
0x0001A000       li R1 10
read_write_loop:
0x0001A008       push R1
    ; Perform a read from stdin into a user buffer.
    ;TRACE 1
0x0001A00C       LI R1 0
    ;DEBUG 2
0x0001A014       LI R2 USER_READ_BUF
0x0001A01C       LI R3 CONSOLE_INPUT_LEN
0x0001A024       SVC SYS_READ
0x0001A028       DEBUG 1

    ;CMP R1 0
    ;BEQ task_b_done

    ; Echo the data back via SYS_WRITE.
0x0001A02C       MOV R5 R1              ; save length returned by SYS_READ
0x0001A030       LI R1 1                ; stdout file descriptor
0x0001A038       LI R2 USER_READ_BUF
0x0001A040       MOV R3 R5
0x0001A044       SVC SYS_WRITE
0x0001A048       DEBUG 1
0x0001A04C       pop R1
0x0001A050       sub R1 R1 1
0x0001A054       cmp r1 0
0x0001A058       BNE read_write_loop
    ;TRACE 0
task_b_done:
    ; Exit after the read/write test.
0x0001A060       DEBUG 1
0x0001A064       LI R1 SYS_EXIT
0x0001A06C       SVC SYS_EXIT
[ASM] Built memory.img (106608 bytes)
