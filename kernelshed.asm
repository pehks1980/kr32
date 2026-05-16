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
; KR32 KERNEL - UNIFIED TRAP HANDLER (Linux style)
; ================================================================
.org 0x0000
B KERNEL_START

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

    ; Start first task
    LI R1 idle_task
    JR R1


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
; Initialize Page Tables (identity map first 64KB)
; ================================================================
init_page_tables:
    LI R1 0x00100000           ; PT base
    LI R2 16                   ; 16 entries (64KB)
    LI R3 0                    ; VPN counter

init_loop:
    MOV R4 R3                  ; PPN = VPN
    SHL R4 R4 12               ; Shift to bits[31:12]
    LI R6 0x001F               ; Flags: PRESENT|READ|WRITE|EXEC|USER
    OR R4 R4 R6
    SHL R5 R3 2                ; offset = VPN * 4
    STW R4 [R1+R5]
    
    ADD R3 R3 1
    CMP R3 R2
    BNE init_loop

    LI R1 0x00100000
    SETPTBR R1
    RET


; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
    ENABLEMMU
    ENABLEINT
    DEBUG
    RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps go here)
; ================================================================
trap_entry:
    ; Save all registers (epilogue saves in reverse order)
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
    
    ; R1 already contains cause (scause) set by CPU
    ; R2 already contains stval (fault address or syscall number)
    
    ; Dispatch based on cause value in R1
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
    
    B trap_epilogue

handle_invalid_instr:
    ; TODO: handle invalid instruction
    
    B trap_epilogue

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
    HLT
    
    B trap_epilogue

handle_syscall:
    ; R2 contains syscall number
    
    CMP R2 1
    BEQ syscall_exit:
    
    B trap_epilogue

syscall_exit:
    HLT

handle_debug:
    ; Debug trap - just return
    B trap_epilogue

handle_irq:
    ; Interrupt handler
    ; schedule_and_switch here

    BL schedule_and_switch

    ;B trap_epilogue

trap_epilogue:
    ; Restore all registers in reverse order
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
    
    IRET



; ================================================================
; TASK SCHEDULER (compatible with current KR32 assembler)
; ================================================================

; ------------------------------------------------
; Task structure offsets
; ------------------------------------------------
.EQU TASK_SP,      0
.EQU TASK_PC,      4
.EQU TASK_ACTIVE,  8
.EQU TASK_PID,    12
.EQU TASK_SIZE,   16

; ------------------------------------------------
; Task table
; ------------------------------------------------
.ORG 0x3000

tasks:
    .SPACE 48              ; 3 tasks * 16 bytes

CURRENT_TASK:
    .WORD 0

; ------------------------------------------------
; Stack tops
; ------------------------------------------------
.EQU TASK0_STACK_TOP, 0x4000
.EQU TASK1_STACK_TOP, 0x4200
.EQU TASK2_STACK_TOP, 0x4400

; ================================================================
; INIT SCHEDULER
; ================================================================
init_scheduler:

    ; ------------------------------------------------
    ; Task 0
    ; ------------------------------------------------
    LI R1 TASK0_STACK_TOP
    LI R2 tasks
    STW R1 [R2 + TASK_SP]

    LI R1 idle_task
    STW R1 [R2 + TASK_PC]

    LI R1 1
    STW R1 [R2 + TASK_ACTIVE]

    LI R1 0
    STW R1 [R2 + TASK_PID]

    ; ------------------------------------------------
    ; Task 1
    ; ------------------------------------------------
    LI R2 tasks
    ADD R2 R2 16           ; TASK_SIZE

    LI R1 TASK1_STACK_TOP
    STW R1 [R2 + TASK_SP]

    LI R1 TASK_A_START
    STW R1 [R2 + TASK_PC]

    LI R1 1
    STW R1 [R2 + TASK_ACTIVE]

    LI R1 1
    STW R1 [R2 + TASK_PID]

    ; ------------------------------------------------
    ; Task 2
    ; ------------------------------------------------
    LI R2 tasks
    ADD R2 R2 32           ; TASK_SIZE * 2

    LI R1 TASK2_STACK_TOP
    STW R1 [R2 + TASK_SP]

    LI R1 TASK_B_START
    STW R1 [R2 + TASK_PC]

    LI R1 1
    STW R1 [R2 + TASK_ACTIVE]

    LI R1 2
    STW R1 [R2 + TASK_PID]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0
    ; ------------------------------------------------
    LI R1 CURRENT_TASK
    LI R2 0
    STW R2 [R1]

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

    LI R3 0

    ;R3 next task (1) ;R2 current task (0) for eg

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
; R3 next (+1) typically)
; R1 - pounts to CURRENT_TASK variable (mem)
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
    ; Save old SP
    ; ------------------------------------------------
    ; save current task sp to its place in mem
    MOV R7 SP
    STW R7 [R5 + TASK_SP]

    ; ------------------------------------------------
    ; Save resume PC
    ; ------------------------------------------------
    ; dont understand right now but it literally gets
    ; address of RET and puts it to current task PC field
    LI R7 resume_point
    STW R7 [R5 + TASK_PC]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic
    LI R4 TASK_SIZE
    MUL R5 R3 R4

    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[new]

    ; ------------------------------------------------
    ; Restore SP
    ; ------------------------------------------------
    ; set SP to what is int next task field struc
    LDW SP [R5 + TASK_SP]

    ; ------------------------------------------------
    ; Restore PC
    ; ------------------------------------------------
    ; get PC and jump to new task
    LDW R7 [R5 + TASK_PC]

    JR R7

resume_point:
    RET




; ================================================================
; TASKS
; ================================================================

; --TASK 0 ----------------------------------------------


idle_task:
    ENABLEINT

idle_loop:
    ;DEBUG 1
    B idle_loop

; --TASK 1----------------------------------------------

TASK_A_START:

    LI R1 0

task_a_loop:
    ADD R1 R1 1
    ;DEBUG 1
    B task_a_loop

; ---TASK 2---------------------------------------------

TASK_B_START:

    LI R2 0

task_b_loop:
    ADD R2 R2 1
    ;DEBUG 1
    B task_b_loop

