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

KERNEL_START:
    LI SP 0x0000F000
    MOV FP SP

    ; Initialize unified IDT (all traps go to trap_entry)
    BL init_idt

    ; Initialize Page Tables
    BL init_page_tables

    ; Enable MMU and interrupts
    BL enable_vm

    ; Jump to user-mode code
    BL USER_START
    HLT


; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================
init_idt:
    LI R1 0x00200000           ; IDT base physical address
    
    ; Only entry 0 matters - all traps go here
    LI R2 trap_entry
    STW R2 R1 0                ; IDT[0] = trap_entry
    
    ; Optional: fill other entries with same handler for safety
    LI R2 trap_entry
    STW R2 R1 4                ; IDT[1]
    STW R2 R1 8                ; IDT[2]
    STW R2 R1 12               ; IDT[3]
    STW R2 R1 24               ; IDT[6]
    STW R2 R1 64               ; IDT[16]
    
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
    STW R4 R1 R5
    
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
    BEQ .handle_divide_zero
    
    CMP R1 1
    BEQ .handle_invalid_instr
    
    CMP R1 2
    BEQ .handle_page_fault
    
    CMP R1 3
    BEQ .handle_syscall
    
    CMP R1 6
    BEQ .handle_debug
    
    CMP R1 16
    BEQ .handle_irq
    
    ; Unknown cause - halt
    HLT

.handle_divide_zero:
    ; TODO: handle divide by zero
    BL trap_epilogue

.handle_invalid_instr:
    ; TODO: handle invalid instruction
    BL trap_epilogue

.handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
    BL trap_epilogue

.handle_syscall:
    ; R2 contains syscall number
    CMP R2 1
    BEQ .syscall_exit
    BL trap_epilogue

.syscall_exit:
    HLT

.handle_debug:
    ; Debug trap - just return
    BL trap_epilogue

.handle_irq:
    ; Interrupt handler
    ; TODO: actual IRQ handling
    BL trap_epilogue

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