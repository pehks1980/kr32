; ================================================================
; KR32 KERNEL - BOOTSTRAP AND TRAP HANDLERS
; ================================================================
; This kernel initializes the virtual memory system (MMU + page tables)
; and sets up exception handling via an Interrupt Descriptor Table (IDT).
; All traps and exceptions are delivered through the IDT.
;
; KR32 CALLING CONVENTION:
;   R0        = hardwired ZERO
;   R1-R4     = argument registers (arg0..arg3)
;   R1        = return value register
;   R5-R11    = caller-saved temporaries
;   R12       = callee-saved temporary (optional)
;   R13       = SP (stack pointer)
;   R14       = FP (frame pointer)
;   R15       = LR (return link)
;   Callees must preserve FP/LR/SP and may use R1-R11 freely.
; KR32 KERNEL - UNIFIED TRAP HANDLER (Linux style)
; ================================================================

; ================================================================
; FOR memory map and structs please refer to memory_map.txt
; ================================================================


; ================================================================
; KR32 KERNEL - UNIFIED TRAP HANDLER (Linux style)
; ================================================================


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

.EQU TASK0_PTBR,   0x00400000   ; one 1 MiB one-level table per address space
.EQU TASK1_PTBR,   0x00500000
.EQU TASK2_PTBR,   0x00600000

.EQU TASK0_USTACK_PA, 0x00005000 ; physical memory address stack and data when map pages tasks 0,1,2 in memory image
.EQU TASK1_USTACK_PA, 0x00009000 ; func page init makes map in page table for every task (0) runs in kernel mode
.EQU TASK2_USTACK_PA, 0x0000A000
.EQU TASK0_DATA_PA,   0x00006000
.EQU TASK1_DATA_PA,   0x0000B000
.EQU TASK2_DATA_PA,   0x0000C000

.org 0x2000

KERNEL_START:
    LI SP 0x0000F000
    MOV FP SP

    ; Initialize unified IDT (all traps go to trap_entry)
    BL init_idt

    ; Initialize Page Tables
    BL init_page_tables

    ; Init_task_scheduler (hard-coded)
    BL init_scheduler

    ; Enable MMU and interrupts
    BL enable_vm

    ; Start first task through the same trapframe restore path used
    ; by preemptive switches.
    LI R1 tasks
    LDW SP [R1 + TASK_KSP]
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
    
    SETIDTR R1
    RET


; ================================================================
; Initialize Page Tables
; ================================================================
init_page_tables:
    PUSH LR

    ; EVERY TASK owns a different PTBR. Kernel pages are mapped into ALL
    ; address spaces as supervisor global entries; user stack/data pages are
    ; mapped per task to prove same-VA, different-PA isolation.
    LI R1 TASK0_PTBR            ; task 0 page table pointer (phys address)
    BL map_common_kernel        ; map kernel page table for task 0 - a kernel process "idle loop" run in kernel mode
    LI R2 0x00005000            ; page VA -virt addr
    LI R3 TASK0_USTACK_PA       ; page PA -phys addr (.org one)
    LI R4 USER_RW               ; page access matrix stored it page table entry (PTE)
    BL map_page
    LI R2 0x00006000
    LI R3 TASK0_DATA_PA
    LI R4 USER_RW
    BL map_page

    LI R1 TASK1_PTBR             ; USER task 1 page table pointer (phys address)
    BL map_common_kernel
    LI R2 0x00005000             ;page used for stack
    LI R3 TASK1_USTACK_PA        ; physical address - note! in virtual space virtual address can be the same (like here x05000)
    LI R4 USER_RW                ; so mmu does the trick and with help of tlb fast translates vpn to ppn : offset
    BL map_page
    LI R2 0x00006000             ;page used for data
    LI R3 TASK1_DATA_PA
    LI R4 USER_RW
    BL map_page

    LI R1 TASK2_PTBR            ; USER task 2 - same
    BL map_common_kernel
    LI R2 0x00005000
    LI R3 TASK2_USTACK_PA
    LI R4 USER_RW
    BL map_page
    LI R2 0x00006000
    LI R3 TASK2_DATA_PA
    LI R4 USER_RW
    BL map_page

    LI R1 TASK0_PTBR
    SETPTBR R1
    POP LR
    RET

map_common_kernel:
    PUSH LR

    ; Boot page, kernel/trap code, kernel stacks, scheduler/task metadata,
    ; and the user text page are identity-mapped into every address space.
    LI R2 0x00000000      ;page 0 - boot (0000)
    LI R3 0x00000000
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
    LI R2 0x00008000      ; page 5 text page (program) for user mode process
    LI R3 0x00008000
    LI R4 USER_RX
    BL map_page

    POP LR
    RET

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
    SHR R5 R2 12               ; VPN
    SHL R5 R5 2                ; page-table byte offset
    OR R6 R3 R4                ; PTE = PA page base | flags
    STW R6 [R1 + R5]
    RET


; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
    ENABLEMMU
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
    RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps go here)
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
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    CSRR R2 STVAL

    CMP R2 SYS_COUNT
    BGE syscall_unknown

    LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
    SHL R4 R2 2
    LDW R5 [R3 + R4]
    JR R5

    ;; no return B trap_restore

syscall_unknown:
    LI R1 0xFFFFFFFF                    ; R1 has error code FFFF
    STW R1 [SP + TF_R1]
    B trap_restore

syscall_table:
    .WORD syscall_yield         ; SVC 0
    .WORD syscall_exit          ; SVC 1
    .WORD syscall_getpid        ; SVC 2
    .WORD syscall_debug         ; SVC 3
    .WORD syscall_write_test    ; SVC 4

syscall_yield:
    LI R1 0
    STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.
    ;;BL schedule_and_switch
    ;;RET
    B schedule_and_switch

syscall_exit:               ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    LI R1 CURRENT_TASK
    LDW R2 [R1]
    LI R3 TASK_SIZE
    MUL R4 R2 R3
    LI R5 tasks
    ADD R5 R5 R4
    LI R6 0                     ;0 to disable this task
    STW R6 [R5 + TASK_ACTIVE]
    LI R1 0
    STW R1 [SP + TF_R1]         ; r1=0 - return success
    B schedule_and_switch
    ;;RET

syscall_getpid:
    LI R1 CURRENT_TASK
    LDW R2 [R1]
    LI R3 TASK_SIZE
    MUL R4 R2 R3
    LI R5 tasks
    ADD R5 R5 R4
    LDW R1 [R5 + TASK_PID]        ; get pid from task scheduler data
    STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
    ;;RET                           ; on resume r1 will have pid read after svc call
    B trap_restore

syscall_debug:
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    LDW R1 [SP + TF_R1]
    STW R1 [SP + TF_R1]
    ;;RET
    B trap_restore

syscall_write_test:
    ; Minimal copy-from-current-address-space test:
    ;   R1=user VA, R2=value. Store value to that VA and return 0.
    ; Full copy_from_user validation can be added after page-fault policy.
    LDW R1 [SP + TF_R1]
    LDW R2 [SP + TF_R2]
    STW R2 [R1]
    LI R1 0
    STW R1 [SP + TF_R1]

    ;RET
    B trap_restore

handle_debug:
    ; Debug trap - just return
    B trap_restore

handle_irq:
    ; The CPU delivered IRQ number in STVAL. Acknowledge the PIC from
    ; the kernel, after identifying the interrupt source, instead of
    ; letting VMP auto-ack before the handler runs.
    CSRR R1 STVAL
    EOI R1

   ;;no return! BL schedule_and_switch
    ;; B trap_restore

    B schedule_and_switch

trap_restore:               ; this does a resume of task restores state frame
                            ; and makes SRET - machine runs the task
                            ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
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

    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    CSRRW SP SSCRATCH SP
    SRET



; ================================================================
; TASK SCHEDULER (compatible with current KR32 assembler)
; ================================================================

; ------------------------------------------------
; Task structure offsets
; ------------------------------------------------
.EQU TASK_KSP,     0          ; saved kernel trapframe stack pointer
.EQU TASK_USP,     4          ; last saved interrupted task stack pointer
.EQU TASK_PC,      8          ; debug/metadata: entry or last known PC
.EQU TASK_ACTIVE, 12
.EQU TASK_PID,    16
.EQU TASK_PTBR,   20         ; physical base of this task's page table
.EQU TASK_SIZE,   24

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

.EQU SYS_YIELD,    0
.EQU SYS_EXIT,     1
.EQU SYS_GETPID,   2
.EQU SYS_DEBUG,    3
.EQU SYS_WRITE_TEST, 4
.EQU SYS_COUNT,    5

; ------------------------------------------------
; Task table
; ------------------------------------------------
.ORG 0x7000

tasks:
    .SPACE 72              ; 3 tasks * 24 bytes

CURRENT_TASK:
    .WORD 0

; ------------------------------------------------
; Stack tops
; ------------------------------------------------
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
    MOV R12 SP ;important we save kernel sp becuse we form stack frame at tasks SPs

    ; ------------------------------------------------
    ; Task 0
    ; ------------------------------------------------
    LI SP TASK0_KSTACK_TOP
    ; Build the initial trapframe on the task's kernel stack. It has
    ; the same shape as an IRQ-created trapframe, so first dispatch and
    ; later preemptive resumes use the exact same restore path.
    LI R1 0
    PUSH R1                  ; R1
    PUSH R1                  ; R2
    PUSH R1                  ; R3
    PUSH R1                  ; R4
    PUSH R1                  ; R5
    PUSH R1                  ; R6
    PUSH R1                  ; R7
    PUSH R1                  ; R8
    PUSH R1                  ; R9
    PUSH R1                  ; R10
    PUSH R1                  ; R11
    PUSH R1                  ; R12
    PUSH R1                  ; R14
    PUSH R1                  ; R15
    LI R1 TASK0_USTACK_TOP
    PUSH R1                  ; interrupted task SP restored by CSRRW before SRET
    LI R1 idle_task
    PUSH R1                  ; sepc - this is new place of PC in trap frame
    LI R1 0
    PUSH R1                  ; sflags
    LI R1 0x120
    PUSH R1                  ; sstatus.SPIE|SPP: idle resumes as supervisor task
    LI R1 0
    PUSH R1                  ; scause
    PUSH R1                  ; stval - other valuable s-data on top (or bottom-)

    LI R2 tasks
    MOV R1 SP
    STW R1 [R2 + TASK_KSP]  ; save kernel trapframe SP

    LI R1 TASK0_USTACK_TOP
    STW R1 [R2 + TASK_USP]  ; save initial task stack SP for debug/metadata

    LI R1 idle_task
    STW R1 [R2 + TASK_PC]   ;start PC of the task

    LI R1 1
    STW R1 [R2 + TASK_ACTIVE] ;set this task as as active

    LI R1 0
    STW R1 [R2 + TASK_PID]   ;set PID=0 for this task

    LI R1 TASK0_PTBR
    STW R1 [R2 + TASK_PTBR]

    ; ------------------------------------------------
    ; Task 1 - do the same
    ; ------------------------------------------------
    LI SP TASK1_KSTACK_TOP
    LI R1 0
    PUSH R1                  ; R1
    PUSH R1                  ; R2
    PUSH R1                  ; R3
    PUSH R1                  ; R4
    PUSH R1                  ; R5
    PUSH R1                  ; R6
    PUSH R1                  ; R7
    PUSH R1                  ; R8
    PUSH R1                  ; R9
    PUSH R1                  ; R10
    PUSH R1                  ; R11
    PUSH R1                  ; R12
    PUSH R1                  ; R14
    PUSH R1                  ; R15
    LI R1 TASK1_USTACK_TOP
    PUSH R1                  ; interrupted task SP
    LI R1 TASK_A_START
    PUSH R1                  ; sepc
    LI R1 0
    PUSH R1                  ; sflags
    LI R1 0x20
    PUSH R1                  ; sstatus.SPIE
    LI R1 0
    PUSH R1                  ; scause
    PUSH R1                  ; stval

    LI R2 tasks
    ADD R2 R2 TASK_SIZE

    MOV R1 SP
    STW R1 [R2 + TASK_KSP]

    LI R1 TASK1_USTACK_TOP
    STW R1 [R2 + TASK_USP]

    LI R1 TASK_A_START
    STW R1 [R2 + TASK_PC]

    LI R1 1
    STW R1 [R2 + TASK_ACTIVE]

    LI R1 1
    STW R1 [R2 + TASK_PID]

    LI R1 TASK1_PTBR
    STW R1 [R2 + TASK_PTBR]

    ; ------------------------------------------------
    ; Task 2 - same
    ; ------------------------------------------------
    LI SP TASK2_KSTACK_TOP
    LI R1 0
    PUSH R1                  ; R1
    PUSH R1                  ; R2
    PUSH R1                  ; R3
    PUSH R1                  ; R4
    PUSH R1                  ; R5
    PUSH R1                  ; R6
    PUSH R1                  ; R7
    PUSH R1                  ; R8
    PUSH R1                  ; R9
    PUSH R1                  ; R10
    PUSH R1                  ; R11
    PUSH R1                  ; R12
    PUSH R1                  ; R14
    PUSH R1                  ; R15
    LI R1 TASK2_USTACK_TOP
    PUSH R1                  ; interrupted task SP
    LI R1 TASK_B_START
    PUSH R1                  ; sepc
    LI R1 0
    PUSH R1                  ; sflags
    LI R1 0x20
    PUSH R1                  ; sstatus.SPIE
    LI R1 0
    PUSH R1                  ; scause
    PUSH R1                  ; stval

    LI R2 tasks
    LI R3 TASK_SIZE
    ADD R2 R2 R3
    ADD R2 R2 R3

    MOV R1 SP
    STW R1 [R2 + TASK_KSP]

    LI R1 TASK2_USTACK_TOP
    STW R1 [R2 + TASK_USP]

    LI R1 TASK_B_START
    STW R1 [R2 + TASK_PC]

    LI R1 1
    STW R1 [R2 + TASK_ACTIVE]

    LI R1 2
    STW R1 [R2 + TASK_PID]

    LI R1 TASK2_PTBR
    STW R1 [R2 + TASK_PTBR]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task to shedule first
    ; ------------------------------------------------
    LI R1 CURRENT_TASK
    LI R2 0
    STW R2 [R1]

    MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
    RET

; ================================================================
; SCHEDULE + SWITCH
; ================================================================
schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

    LI R1 CURRENT_TASK
    LDW R2 [R1]                ; R2 = old task index

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

    ADD R3 R2 1

wrap_check:

    CMP R3 3
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
    ; Check ACTIVE
    ; ------------------------------------------------

    LDW R7 [R5 + TASK_ACTIVE]

    CMP R7 1
    BEQ do_switch
    ; if not active go to next task in list
    ADD R3 R3 1
    B wrap_check

; R3 next task is active - switch to it
; R2 current task
; R3 next (+1) typically
; R1 - points to CURRENT_TASK variable (mem)

; ================================================================
; CONTEXT SWITCH
; ================================================================

do_switch:

    ; ------------------------------------------------
    ; Save new current task index
    ; ------------------------------------------------
    ; update current task now is next one (+1)
    STW R3 [R1]

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
    LI R4 TASK_SIZE
    MUL R5 R2 R4

    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[old]

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.
    LDW R7 [SP + TF_USP]
    STW R7 [R5 + TASK_USP]

    MOV R7 SP
    STW R7 [R5 + TASK_KSP]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic
    LI R4 TASK_SIZE
    MUL R5 R3 R4

    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[new]

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------
    LDW R7 [R5 + TASK_PTBR]
    SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

    LDW SP [R5 + TASK_KSP] ; load next task's kernel trapframe
    ; trap_restore will restore SSCRATCH with the saved task SP, then
    ; CSRRW swaps back to that task stack immediately before SRET.

    ;; no return RET
    B trap_restore




; ================================================================
; TASKS
; ================================================================
.ORG 0x8000

; --TASK 0 ----------------------------------------------


idle_task:
    ENABLEINT
    LI R1 0
idle_loop:
    ADD R1 R1 1
    DEBUG 2
    B idle_loop

; --TASK 1----------------------------------------------

TASK_A_START:

    LI R2 0
    LI R4 0x00006000
    LI R5 0xAAAAAAAA

task_a_loop:
    ADD R2 R2 1
    STW R5 [R4]
    SVC SYS_GETPID
    STW R1 [R4 + 4]
    DEBUG 1
    B task_a_loop

; ---TASK 2---------------------------------------------

TASK_B_START:

    LI R3 0
    LI R4 0x00006000
    LI R5 0xBBBBBBBB
task_b_loop:
    ADD R3 R3 1
    STW R5 [R4]
    SVC SYS_GETPID
    STW R1 [R4 + 4]
    DEBUG 1
    CMP R3 3
    BLE task_b_loop
    DEBUG 2
    LI R1 15
    SVC SYS_EXIT
task_b_dead:
    DEBUG 2
    B task_b_dead