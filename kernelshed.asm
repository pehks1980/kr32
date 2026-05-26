; ================================================================
; KR32 KERNEL - BOOTSTRAP AND TRAP HANDLERS (C-like macros)
; Converted by tools/convert_to_cmacros.py — original saved as kernelshed.asm.orig
; Use tools/preprocess_cmacros.py to expand and generate real assembly.
; Example: python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm
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
.EQU FD_ENTRY_DEVICE, 0
.EQU FD_ENTRY_FLAGS,  4
.EQU FD_ENTRY_SIZE,   8
.EQU FD_FLAG_READ,    1
.EQU FD_FLAG_WRITE,   2
.EQU DEV_OFF_READ,    0
.EQU DEV_OFF_WRITE,   4

.EQU STDIN_FD,       0
.EQU STDOUT_FD,      1
.EQU STDERR_FD,      2
.EQU CONSOLE_INPUT_LEN, 1
.EQU USER_WRITE_BUF, 0x6000
.EQU USER_READ_BUF,  0x6010

; KBUFFER
.org 0x1000
KBUFFER_WR:
        .SPACE 256              ; 256b
KBUFFER_RD:
        .SPACE 256              ; 256b


.org 0x2000

func KERNEL_START
        LI SP 0x0000F000
        MOV FP SP

        ; Initialize unified IDT (all traps go to trap_entry)
    call init_idt

        ; Initialize Page Tables
        ; check memory_map.txt for current layout
    call init_page_tables

        ; Init_task_scheduler (hard-coded)
    call init_scheduler

        ; ----------------------------------------------------
        ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
        ; ----------------------------------------------------
        LI R1 0x00102000
        LI R2 3
        STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

        ; ----------------------------------------------------
        ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
        ; ----------------------------------------------------
        LI R1 0x00101000
        LI R2 2000
        STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
        LI R2 3
        STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

        ; ----------------------------------------------------
        ; Setup MMIO UART: Enable RX/TX interrupts
        ; ----------------------------------------------------
        LI R1 0x00100000
        LI R2 3
        STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

        ; Enable MMU and interrupts
    call enable_vm

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

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

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
    LI R2 0x00019000      ; page 5 text page (program) for user mode process
    LI R3 0x00019000
    LI R4 USER_RX
    BL map_page
    LI R2 0x0001a000      ; page 5 text page (program) for user mode process
    LI R3 0x0001a000
    LI R4 USER_RX
    BL map_page

    ; Kernel-only helpers: copy routines and page-table inspection
    LI R2 0x00001000      ; page for kernel buffers
    LI R3 0x00001000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 PTBR0_VA
    LI R3 TASK0_PTBR
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 PTBR1_VA
    LI R3 TASK1_PTBR
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 PTBR2_VA
    LI R3 TASK2_PTBR
    LI R4 KERNEL_FLAGS
    BL map_page

    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
    LI R2 0x00100000      ; UART physical and virtual base
    LI R3 0x00100000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00101000      ; PIT physical and virtual base
    LI R3 0x00101000
    LI R4 KERNEL_FLAGS
    BL map_page

    LI R2 0x00102000      ; PIC physical and virtual base
    LI R3 0x00102000
    LI R4 KERNEL_FLAGS
    BL map_page

    POP LR
    RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

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
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

    CSRR R2 STVAL

    CMP R2 SYS_COUNT
    BGE syscall_unknown

    LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
    SHL R4 R2 2
    LDW R5 [R3 + R4]
    JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an error code (e.g., 0xFFFFFFFF) in R1 and restore.
;================================================================

    LI R1 0xFFFFFFFF                    ; R1 has error code FFFF
    STW R1 [SP + TF_R1]
    B trap_restore

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

    LI R1 0
    STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

    B schedule_and_switch

syscall_exit:
    ;================================================================               
    ; basically a call from task to remove from scheduler so it wont be executed
    ; Mark the current task inactive and immediately switch to another task.
    ; A later scheduler improvement should detect "no runnable tasks".
    ;================================================================

    LI R1 CURRENT_TASK
    LDW R2 [R1]
    LI R3 TASK_SIZE
    MUL R4 R2 R3
    LI R5 tasks
    ADD R5 R5 R4
    LI R6 0                     ;0 to disable this task (dead)
    STW R6 [R5 + TASK_STATE]

    LI R1 0
    STW R1 [SP + TF_R1]         ; r1=0 - return success
    B schedule_and_switch

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

    LI R1 CURRENT_TASK
    LDW R2 [R1]
    LI R3 TASK_SIZE
    MUL R4 R2 R3
    LI R5 tasks
    ADD R5 R5 R4
    LDW R1 [R5 + TASK_PID]        ; get pid from task scheduler data
    STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
    B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

    LDW R1 [SP + TF_R1]
    STW R1 [SP + TF_R1]
    
    B trap_restore

syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

    LDW R1 [SP + TF_R1]
    LDW R2 [SP + TF_R2]
    LDW R3 [SP + TF_R3]

    MOV R7 R2               ; save user buffer
    MOV R6 R3               ; save length
    PUSH R7
    PUSH R6
    LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
    BL fetch_fd_entry
    POP R6
    POP R7
    CMP R1 0
    BEQ bad_fd
    MOV R9 R1               ; device object pointer /dev/console for example
    CMP R6 0
    BEQ read_done

    PUSH R7
    PUSH R6
    PUSH R9
    MOV R1 R7
    MOV R2 R6
    LI R3 1                ; write access for destination buffer
    BL user_buffer_valid_range
    POP R9
    POP R6
    POP R7
    CMP R1 1
    BNE bad_pointer

read_wait_uart_rx:
    LI R4 0x00100000            ; UART MMIO Base Address
    LDW R5 [R4 + 4]             ; read UART_STATUS register
    AND R5 R5 1                 ; bit 0 = RX_READY
    CMP R5 0
    BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

    PUSH R7
    LI R1 KBUFFER_RD
    MOV R2 R6
    MOV R3 R9
    BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
    POP R7
    CMP R1 0
    BEQ read_done

    MOV R2 R1              ; actual bytes read
    MOV R1 R7              ; user destination
    MOV R4 KBUFFER_RD
    BL copy_to_user        ; copy from kernel buffer to user buffer
    STW R1 [SP + TF_R1]

    B trap_restore

read_block_uart_rx:
    LI R1 CURRENT_TASK
    LDW R2 [R1]                ; R2 = current task index
    LI R3 TASK_SIZE
    MUL R4 R2 R3
    LI R5 tasks
    ADD R5 R5 R4              ; R5 = &tasks[current]

    LI R10 TASK_BLOCKED_IO      ; curr task state set blockedio, reason wait_rx
    STW R10 [R5 + TASK_STATE]
    LI R10 WAIT_UART_RX
    STW R10 [R5 + TASK_WAIT]

    LI R4 0x00100000
    LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
    AND R10 R10 1
    CMP R10 0
    BNE read_unblock_uart_rx     ; if data in rx_queue go unblok

    BL schedule_call             ;save this user task as frozen in kernel space (sleeping inside sys_call)

    B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
    LI R10 TASK_READY
    STW R10 [R5 + TASK_STATE]
    LI R10 WAIT_NONE
    STW R10 [R5 + TASK_WAIT]

    B read_wait_uart_rx          ;go back and read bytes

read_done:
    LI R1 0
    STW R1 [SP + TF_R1]

    B trap_restore

syscall_write:
    ;================================================================
    ; R1 = fd
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

    LDW R1 [SP + TF_R1]
    LDW R2 [SP + TF_R2]
    LDW R3 [SP + TF_R3]

    MOV R7 R2               ; save user buffer
    MOV R6 R3               ; save length
    PUSH R7
    PUSH R6
    LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
    BL fetch_fd_entry
    POP R6
    POP R7
    CMP R1 0
    BEQ bad_fd
    MOV R9 R1               ; device object pointer
    ; R7 and R6 already contain user buffer and length
    LI R8 0                ; total written

write_loop:
    CMP R6 0
    BEQ write_done

    LI R2 KBUFFER_SIZE
    CMP R6 R2
    BLT write_chunk_small
    LI R2 KBUFFER_SIZE
    
    B write_chunk

write_chunk_small:
    MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

    PUSH R7
    PUSH R6
    PUSH R9
    MOV R1 R7
    MOV R2 R2
    LI R3 0                ; read access for source buffer
    BL user_buffer_valid_range
    POP R9
    POP R6
    POP R7
    CMP R1 1
    BNE bad_pointer

    PUSH R7
    PUSH R6
    MOV R1 R7
    MOV R4 KBUFFER_WR
    BL copy_from_user
    MOV R10 R1             ; bytes copied
    POP R6
    POP R7

    PUSH R7
    PUSH R9
    PUSH R6

write_wait_uart_tx:
    LI R1 0x00100000
    LDW R2 [R1 + 4]
    AND R2 R2 2                     ;check bit 1 - TX rdy
    CMP R2 0
    BEQ write_block_uart_tx

    MOV R1 KBUFFER_WR
    MOV R2 R10
    MOV R3 R9
    BL device_write
    POP R6
    POP R9
    POP R7

    CMP R1 0
    BEQ write_loop

    ADD R8 R8 R1
    ADD R7 R7 R1
    SUB R6 R6 R1
    B write_loop

write_block_uart_tx:
    LI R1 CURRENT_TASK
    LDW R2 [R1]                ; R2 = current task index
    LI R3 TASK_SIZE
    MUL R4 R2 R3
    LI R5 tasks
    ADD R5 R5 R4              ; R5 = &tasks[current]

    LI R1 TASK_BLOCKED_IO
    STW R1 [R5 + TASK_STATE]
    LI R1 WAIT_UART_TX
    STW R1 [R5 + TASK_WAIT]

    LI R1 0x00100000
    LDW R2 [R1 + 4]             ; re-check after marking blocked
    AND R2 R2 2
    CMP R2 0
    BNE write_unblock_uart_tx

    BL schedule_call
    B write_wait_uart_tx

write_unblock_uart_tx:
    LI R1 TASK_READY
    STW R1 [R5 + TASK_STATE]
    LI R1 WAIT_NONE
    STW R1 [R5 + TASK_WAIT]
    B write_wait_uart_tx

write_done:
    MOV R1 R8
    STW R1 [SP + TF_R1]

    B trap_restore

bad_fd:
    LI R1 0xFFFF
    STW R1 [SP + TF_R1]

    B trap_restore

bad_pointer:
    LI R1 0xFFFF
    STW R1 [SP + TF_R1]

    B trap_restore

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ;================================================================

    LDW R4 [R3 + DEV_OFF_READ]  ; get device read function pointer
    JR R4                       ; execute it

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ;================================================================

    LDW R4 [R3 + DEV_OFF_WRITE] ; get device write function pointer
    JR R4                       ; execute it

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

con_rd:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
    LI R4 0x00100000            ; UART MMIO Base Address
    LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
    CMP R5 R2                   ; have we read enough bytes?
    BGE dr_done                 ; yes -> return

dr_poll_ready:
    LDW R6 [R4 + 4]             ; read UART_STATUS register
    AND R6 R6 1                 ; bit 0 = RX_READY
    CMP R6 0
    BEQ dr_done                 ; no more buffered input available

    LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
    STB R7 [R1 + R5]            ; store it into the kernel buffer
    ADD R5 R5 1

    ; If we received a newline, stop reading early
    CMP R7 10
    BEQ dr_done

    B dr_loop

dr_done:
    MOV R1 R5                   ; return number of bytes actually read
    RET

;=================================================================
; write /dev/con - to MMIO UART, polling TX_READY before each byte
;================================================================

con_wr:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Transmits R2 bytes from kernel buffer at R1 through the UART.
    ; Polls the UART_STATUS TX_READY bit before sending each byte.
    ; This is a simple synchronous write that blocks until all bytes are sent.
    ;================================================================

    LI R4 0x00100000            ; UART MMIO Base Address
    LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
    CMP R5 R2                   ; have we written all bytes?
    BGE dcw_done                ; yes -> return

dcw_poll_tx:
    LDW R6 [R4 + 4]             ; read UART_STATUS register
    AND R6 R6 2                 ; bit 1 = TX_READY
    CMP R6 0
    BEQ dcw_done

    LDB R7 [R1 + R5]            ; load next byte from kernel buffer
    STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
    ADD R5 R5 1
    B dcw_loop

dcw_done:
    MOV R1 R5                   ; return number of bytes written
    RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, 3)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================

    CMP R1 0
    BLT fd_invalid
    CMP R1 3
    BGE fd_invalid

    LI R4 CURRENT_TASK
    LDW R4 [R4]
    LI R5 TASK_SIZE
    MUL R4 R4 R5
    LI R5 tasks
    ADD R4 R4 R5
    LDW R4 [R4 + TASK_FD_TABLE]

    SHL R5 R1 3
    ADD R4 R4 R5
    LDW R6 [R4 + FD_ENTRY_FLAGS]
    AND R6 R6 R2
    CMP R6 R2
    BNE fd_invalid

    LDW R1 [R4 + FD_ENTRY_DEVICE]
    RET

fd_invalid:
    LI R1 0
    RET

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

    LI R4 0
    CMP R2 R4
    BEQ uv_valid

    LI R4 USER_BASE
    CMP R1 R4
    BLT uv_invalid

    LI R4 USER_LIMIT
    ADD R5 R1 R2
    SUB R5 R5 1
    CMP R5 R1
    BLT uv_invalid
    CMP R5 R4
    BGT uv_invalid
    MOV R12 R5              ; save end address for page calculation

    LI R6 CURRENT_TASK
    LDW R6 [R6]
    LI R7 TASK_SIZE
    MUL R6 R6 R7
    LI R7 tasks
    ADD R6 R6 R7
    LDW R6 [R6 + TASK_PTBR]
    LI R7 TASK0_PTBR
    CMP R6 R7
    BEQ uv_ptbr0
    LI R7 TASK1_PTBR
    CMP R6 R7
    BEQ uv_ptbr1
    LI R7 TASK2_PTBR
    CMP R6 R7
    BEQ uv_ptbr2
    B uv_invalid

uv_ptbr0:
    LI R6 PTBR0_VA
    B uv_check_pages
uv_ptbr1:
    LI R6 PTBR1_VA
    B uv_check_pages
uv_ptbr2:
    LI R6 PTBR2_VA

uv_check_pages:
    SHR R7 R1 12
    SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

    CMP R7 R8
    BGT uv_valid
    SHL R9 R7 2
    ADD R9 R9 R6
    LDW R10 [R9]
    AND R11 R10 PTE_P
    CMP R11 0
    BEQ uv_invalid
    AND R11 R10 PTE_U
    CMP R11 0
    BEQ uv_invalid
    CMP R3 0
    BEQ uv_check_read
    AND R11 R10 PTE_W
    CMP R11 0
    BEQ uv_invalid
    B uv_next

uv_check_read:
    AND R11 R10 PTE_R
    CMP R11 0
    BEQ uv_invalid

uv_next:
    ADD R7 R7 1
    B uv_loop

uv_valid:
    LI R1 1
    RET

uv_invalid:
    LI R1 0
    RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel 
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
    LI R5 0
cfu_head:
    CMP R2 0
    BEQ cfu_done
    OR R6 R1 R4
    AND R6 R6 3
    CMP R6 0
    BEQ cfu_word
    LDB R7 [R1]
    STB R7 [R4]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B cfu_head
cfu_word:
    CMP R2 4
    BLT cfu_tail
    LDW R7 [R1]
    STW R7 [R4]
    ADD R1 R1 4
    ADD R4 R4 4
    ADD R5 R5 4
    SUB R2 R2 4
    B cfu_word
cfu_tail:
    CMP R2 0
    BEQ cfu_done
    LDB R7 [R1]
    STB R7 [R4]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B cfu_tail
cfu_done:
    MOV R1 R5
    RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel 
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
    LI R5 0
ctu_head:
    CMP R2 0
    BEQ ctu_done
    OR R6 R1 R4
    AND R6 R6 3
    CMP R6 0
    BEQ ctu_word
    LDB R7 [R4]
    STB R7 [R1]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B ctu_head
ctu_word:
    CMP R2 4
    BLT ctu_tail
    LDW R7 [R4]
    STW R7 [R1]
    ADD R1 R1 4
    ADD R4 R4 4
    ADD R5 R5 4
    SUB R2 R2 4
    B ctu_word
ctu_tail:
    CMP R2 0
    BEQ ctu_done
    LDB R7 [R4]
    STB R7 [R1]
    ADD R1 R1 1
    ADD R4 R4 1
    ADD R5 R5 1
    SUB R2 R2 1
    B ctu_tail
ctu_done:
    MOV R1 R5
    RET

handle_debug:
    ; Debug trap - just return
    B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL    
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

    CSRR R1 STVAL

    CMP R1 0
    BEQ handle_timer_irq

    CMP R1 1
    BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
    LI R2 0x00102000
    STW R1 [R2 + 8]             ; PIC_ACK = R1
    B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO 
    ;================================================================ 

    LI R2 0x00102000
    LI R3 0
    STW R3 [R2 + 8]             ; PIC_ACK = 0
    
    ; Yield the CPU (reschedule and switch tasks)
    B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX.
    ;================================================================

    LI R2 0x00102000
    LI R3 1
    STW R3 [R2 + 8]             ; PIC_ACK = 1

    LI R1 0                     ; task index

uart_wake_loop:
    CMP R1 3
    BGE uart_wake_done

    LI R2 TASK_SIZE
    MUL R3 R1 R2
    LI R4 tasks
    ADD R4 R4 R3                ; R4 = &tasks[R1]

    LDW R5 [R4 + TASK_STATE]
    CMP R5 TASK_BLOCKED_IO
    BNE uart_wake_next

    LDW R5 [R4 + TASK_WAIT]
    CMP R5 WAIT_UART_RX
    BEQ uart_wake_task
    CMP R5 WAIT_UART_TX
    BNE uart_wake_next

uart_wake_task:
    LI R5 TASK_READY            ; restore them
    STW R5 [R4 + TASK_STATE]
    LI R5 WAIT_NONE
    STW R5 [R4 + TASK_WAIT]

uart_wake_next:
    ADD R1 R1 1
    B uart_wake_loop

uart_wake_done:
    ; Resume the interrupted task immediately
    B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

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
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

    CSRRW SP SSCRATCH SP
    SRET


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
.EQU TASK_SIZE,   36


; =============================================================
; Task table
; =============================================================

.ORG 0x7000

tasks:
    .SPACE 108             ; 3 tasks * 36 bytes

CURRENT_TASK:
    .WORD 0

;==============================================================
; File descriptor table and device objects
;==============================================================

fd_table:
    .WORD con_dev
    .WORD FD_FLAG_READ
    .WORD con_dev
    .WORD FD_FLAG_WRITE
    .WORD con_dev
    .WORD FD_FLAG_WRITE

;==============================================================
; Device con objects
;==============================================================

con_dev:
    .WORD con_rd
    .WORD con_wr

;==============================================================
; Stack tops
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
    MOV R12 SP ;important we save kernel sp becuse we form stack frame at tasks SPs

    ; ------------------------------------------------
    ; Task 0
    ; ------------------------------------------------

    ;================================================================
    ; Build the initial trapframe on the task's kernel stack. It has
    ; the same shape as an IRQ-created trapframe, so first dispatch and
    ; later preemptive resumes use the exact same restore path.
    ;================================================================

    LI SP TASK0_KSTACK_TOP
    
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
    STW R1 [R2 + TASK_STATE] ;set this task as as ready to run

    LI R1 0
    STW R1 [R2 + TASK_PID]   ;set PID=0 for this task

    LI R1 TASK0_PTBR
    STW R1 [R2 + TASK_PTBR]
    LI R1 fd_table
    STW R1 [R2 + TASK_FD_TABLE]

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
    STW R1 [R2 + TASK_STATE]

    LI R1 1
    STW R1 [R2 + TASK_PID]

    LI R1 TASK1_PTBR
    STW R1 [R2 + TASK_PTBR]
    LI R1 fd_table
    STW R1 [R2 + TASK_FD_TABLE]

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
    STW R1 [R2 + TASK_STATE]

    LI R1 2
    STW R1 [R2 + TASK_PID]

    LI R1 TASK2_PTBR
    STW R1 [R2 + TASK_PTBR]
    LI R1 fd_table
    STW R1 [R2 + TASK_FD_TABLE]

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
    ; Check READY state of this task
    ; ------------------------------------------------

    LDW R7 [R5 + TASK_STATE]

    CMP R7 1
    BEQ do_switch
    ; if not ready go to next task in list
    ADD R3 R3 1
    B wrap_check

; R3 next task is ready - switch to it
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
    ; this is used for debugging and also by user_buffer_valid_range 
    ; to find the current page table base for validation of user pointers
    ;      
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

    LI R7 RESUME_TRAP
    STW R7 [R5 + TASK_RESUME]

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

    LDW SP [R5 + TASK_KSP]

    LDW R7 [R5 + TASK_RESUME]
    CMP R7 RESUME_KERNEL
    BEQ restore_kernel_context

    B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
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

    LI R1 CURRENT_TASK
    LDW R2 [R1]                ; R2 = old task index

    ADD R3 R2 1

schedule_call_wrap_check:
    CMP R3 3
    BLT schedule_call_check_task
    LI R3 0

schedule_call_check_task:
    LI R4 TASK_SIZE
    MUL R5 R3 R4
    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[R3]

    LDW R7 [R5 + TASK_STATE]
    CMP R7 TASK_READY
    BEQ schedule_call_do_switch

    ADD R3 R3 1
    B schedule_call_wrap_check

schedule_call_do_switch:
    STW R3 [R1]

    LI R4 TASK_SIZE
    MUL R5 R2 R4
    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[old]

    MOV R7 SP
    STW R7 [R5 + TASK_KSP]
    LI R7 RESUME_KERNEL
    STW R7 [R5 + TASK_RESUME]

    LI R4 TASK_SIZE
    MUL R5 R3 R4
    LI R6 tasks
    ADD R5 R5 R6               ; R5 = &tasks[new]

    LDW R7 [R5 + TASK_PTBR]
    SETPTBR R7

    LDW SP [R5 + TASK_KSP]
    LDW R7 [R5 + TASK_RESUME]
    CMP R7 RESUME_KERNEL
    BEQ restore_kernel_context

    B trap_restore

restore_kernel_context:
    DISABLEINT
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
    RET


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
    ;DEBUG 1 
    B idle_loop

; --TASK 1----------------------------------------------
.ORG 0x19000
TASK_A_START:
    ;DEBUG 2
    ; Prepare a write string in user memory.
    LI R1 USER_WRITE_BUF
    LI R2 0x6C6C6548         ; "Hell"
    STW R2 [R1]
    LI R2 0x57202C6F         ; "o, W"
    STW R2 [R1 + 4]
    LI R2 0x646C726F         ; "orld"
    STW R2 [R1 + 8]
    LI R2 0x21
    STB R2 [R1 + 12]
    LI R2 0x0A
    STB R2 [R1 + 13]

    LI R1 1
   ; DEBUG 1
    LI R2 USER_WRITE_BUF
    LI R3 14
    SVC SYS_WRITE
    ;DEBUG 2
    ; Exit after the write test.
    LI R1 SYS_EXIT
    SVC SYS_EXIT

; ---TASK 2---------------------------------------------

.org 0x1a000
TASK_B_START:
    li R1 10
read_write_loop:
    push R1
    ; Perform a read from stdin into a user buffer.
    ;TRACE 1
    LI R1 0
    ;DEBUG 2
    LI R2 USER_READ_BUF
    LI R3 CONSOLE_INPUT_LEN
    SVC SYS_READ
    ;DEBUG 2
    
    CMP R1 0
    ;BEQ task_b_done

    ; Echo the data back via SYS_WRITE.
    MOV R5 R1              ; save length returned by SYS_READ
    LI R1 1                ; stdout file descriptor
    LI R2 USER_READ_BUF
    MOV R3 R5
    SVC SYS_WRITE

    DEBUG 1
    pop R1
    sub R1 R1 1
    cmp r1 0
    BNE read_write_loop
    ;TRACE 0
task_b_done:
    ; Exit after the read/write test.
    DEBUG 1
    LI R1 SYS_EXIT
    SVC SYS_EXIT
