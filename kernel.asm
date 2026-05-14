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
; ================================================================

KERNEL_START:
    LI SP 0x0000F000
    MOV FP SP

    ; ================================================================
    ; PHASE 1: Initialize Interrupt Descriptor Table
    ; ================================================================
    BL init_idt

    ; ================================================================
    ; PHASE 2: Initialize Page Tables
    ; ================================================================
    BL init_page_tables

    ; ================================================================
    ; PHASE 3: Enable Interrupts and Virtual Memory
    ; ================================================================
    BL enable_vm

    ; Jump to user-mode code
    BL USER_START
    HLT


; ================================================================
; PROCEDURE: init_idt
; 
; Set up the Interrupt Descriptor Table with exception handlers.
; The IDT is a simple array: each entry at offset N*4 contains
; the handler PC for trap vector N.
; ================================================================
init_idt:
    ; IDT located at 0x200000 (2MB boundary, easily identified)
    LI R1 0x00200000  ; R1 = IDT base

    ; Populate IDT entries with handler addresses
    ; Each entry is 32-bit handler PC, stored at IDT_BASE + vector*4

    ; IDT[0] = TRAP_DIVIDE_BY_ZERO handler
    LI R2 divide_by_zero_handler
    STW R2 R1 0

    ; IDT[1] = TRAP_INVALID_INSTR handler
    LI R2 invalid_instr_handler
    STW R2 R1 4

    ; IDT[2] = TRAP_PAGE_FAULT handler
    LI R2 page_fault_handler
    STW R2 R1 8

    ; IDT[3] = TRAP_SYSCALL handler
    LI R2 syscall_handler
    STW R2 R1 12

    ; IDT[6] = TRAP_DEBUG handler
    LI R2 debug_handler
    STW R2 R1 24

    ; Set IDT base register
    SETIDTR R1
    
    RET


; ================================================================
; PROCEDURE: init_page_tables
; 
; Build 1-level page table in physical memory.
; Kernel will use identity mapping for now.
; ================================================================
init_page_tables:
    ; Page table located at 0x100000 (1MB)
    LI R1 0x00100000  ; PT base (physical address)
    LI R2 16          ; num entries (map 64KB: VPN 0-15)
    LI R3 0           ; vpn counter

init_loop:
    ; Build PTE: PPN in high bits, flags in low bits
    MOV R4 R3         ; PPN = vpn
    SHL R4 R4 12      ; shift PPN to bits[31:12]
    LI R6 0x001F      ; flags: PRESENT|READ|WRITE|EXEC|USER
    OR R4 R4 R6       ; combine PPN + flags
    SHL R5 R3 2       ; offset = vpn * 4
    STW R4 R1 R5      ; store PTE at PT_BASE + vpn*4

    ADD R3 R3 1
    CMP R3 R2
    BNE init_loop

    ; Set page table base register
    LI R1 0x00100000
    SETPTBR R1

    RET


; ================================================================
; PROCEDURE: enable_vm
; 
; Activate MMU and enable interrupt delivery.
; ================================================================
enable_vm:
    ; Enable virtual memory translation
    ENABLEMMU

    ; Enable trap delivery via IDT
    ENABLEINT

    ; Trigger debug dump if VM debug mode is enabled
    DEBUG

    RET


; ================================================================
; TRAP HANDLERS - synchronous exception handlers
; ================================================================

; ================================================================
; Handler: divide_by_zero_handler
; 
; Trap vector 0 - TRAP_DIVIDE_BY_ZERO
; Triggered by DIV/MOD/DIVU/MODU by zero.
; ================================================================
divide_by_zero_handler:
    ; In a real kernel, we would:
    ; - save registers
    ; - log the error
    ; - signal the faulting process
    ; - recover or panic

    ; For now, just return to the next instruction
    IRET


; ================================================================
; Handler: invalid_instr_handler
; 
; Trap vector 1 - TRAP_INVALID_INSTR
; Triggered by unknown/invalid opcode.
; ================================================================
invalid_instr_handler:
    ; Invalid instruction encountered
    IRET


; ================================================================
; Handler: page_fault_handler
; 
; Trap vector 2 - TRAP_PAGE_FAULT
; Triggered by missing or protected page.
; ================================================================
page_fault_handler:
    ; Page fault handling - could implement demand paging here
    ; For now, just return to the next instruction
    IRET


; ================================================================
; Handler: syscall_handler
; 
; Trap vector 3 - TRAP_SYSCALL
; Software trap for system calls (SVC instruction).
; Trap_value in CPU contains the syscall number.
; ================================================================
syscall_handler:
    ; In a real kernel:
    ; - read trap_value (syscall number)
    ; - dispatch to appropriate handler (read, write, exit, etc)
    ; - return result in R0
    ; - IRET to resume caller

    ; In this simplified kernel, the syscall number is delivered in R0.
    CMP R0 1
    BEQ syscall_exit
    IRET

syscall_exit:
    HLT


; ================================================================
; Handler: debug_handler

debug_handler:
    ; Debug trap: enter debugger mode or inspect CPU state.
    IRET
