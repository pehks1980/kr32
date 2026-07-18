; ================================================================
; KR32 KERNEL - BOOTSTRAP AND TRAP HANDLERS (C-like macros)
; Converted by tools/convert_to_cmacros.py — original saved as kernelshed.asm.orig
; Use tools/preprocess_cmacros.py to expand and generate real assembly.
; Example: python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm
; ================================================================

; KR32 CALLING CONVENTION:
;   R0        = hardwired ZERO
;   R1-R4     = argument registers (arg0..arg3)
;   R1        = return valutask_clone_currente register
;   R5-R11    = caller-saved temporaries
;   R12       = callee-saved temporary (optional)
;   R13       = SP (stack pointer)
;   R14       = FP (frame pointer)
;   R15       = LR (return link)
;   Map check  - Last Adress: 0x0000A146  Last OS page 0x0000B000

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
.EQU ERR_NOEXEC,     -8      ; executable file format error

; ------------------------------------------------------------
; File descriptor handling
; ------------------------------------------------------------

.EQU ERR_NFILE,     -23      ; system fd table full
.EQU ERR_MFILE,     -24      ; process fd table full
.EQU ERR_BADF,       -9      ; invalid fd

; ------------------------------------------------------------
; Process / scheduling
; ------------------------------------------------------------

.EQU ERR_CHILD,     -10      ; no child processes (waitpid)

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
.EQU KERNEL_USER_ALL, 0x003F       ; G|P|U|X|W|R, shared executable writable full access

.EQU PAGE_SIZE,    0x1000
.EQU PAGE_MASK,    0x0FFF

;.EQU TASK0_PTBR,   0x00010000   ; page table at 64KB (one 1 MiB one-level table per address space)
;.EQU TASK1_PTBR,   0x00020000   ; page table at 128KB
;done via alloc down .EQU TASK2_PTBR,   0x00030000   ; page table at 192KB

;need to do via alloc
;.EQU TASK0_USTACK_PA, 0x00005000 ; physical memory address stack and data when map pages tasks 0,1,2 in memory image
;.EQU TASK1_USTACK_PA, 0x0000B000 ; func page init makes map in page table for every task (0) runs in kernel mode
;.EQU TASK2_USTACK_PA, 0x0000C000

;memory map used for data validation when make syscalls which transfer data b/w kernel and user
.EQU KERNEL_BASE,     0x00000000
.EQU KERNEL_LIMIT,    0x0003EFFF

.EQU USER_BASE,       0x00019000
.EQU USER_LIMIT,      0x0005FFFF

.EQU USER_STACK_VA,   0x0003F000
.EQU USER_STACK_TOP,  0x00040000
.EQU USER_DATA_VA,    0x00042000  ; start of user data page for task (process virtual space) 4 KiB per task (form heap memory)
.EQU USER_CODE_VA,    0x00043000  ; fixed user code VA for execve-loaded user image
; USER_CODE_VA is the per-task user-space entry page for execve programs.
; Each task's active executable is always mapped here when a program is loaded.
; ================================================================
; Program break management
; ================================================================

; Each task gets a data page at USER_DATA_VA (0x6000)
; We manage a per-task heap within this page

.EQU HEAP_START,    USER_DATA_VA + 0x100   ; Start heap after some reserved space
.EQU HEAP_END,      USER_DATA_VA + 0x1000  ; End of data page


.EQU KBUFFER_SIZE,   256

.EQU UARTDEV_RX_QUEUE, 0
.EQU UARTDEV_TX_QUEUE, 4
.EQU UARTDEV_MMIO,     8
.EQU UARTDEV_SIZE,     12

.EQU STDIN_FD,       0
.EQU STDOUT_FD,      1
.EQU STDERR_FD,      2


.EQU CONSOLE_INPUT_LEN, 5

; =============================================================
; FILE struc - current with inodes
; =============================================================

.EQU FD_FLAG_READ,    1
.EQU FD_FLAG_WRITE,   2

;FILE struc uses inode
.EQU FILE_INODE,    0
.EQU FILE_OFFSET,   4
.EQU FILE_FLAGS,    8
.EQU FILE_REFCNT,   12          ;for dup
.EQU FILE_SIZE,     16

; ================================================================
; Time structure for user space
; ================================================================

.EQU TIMEVAL_SEC,   0
.EQU TIMEVAL_USEC,  4
.EQU TIMEVAL_SIZE,  8


; ==================================================
; VFS inode table struc
; ==================================================

; ==================================================
; inode struc
; ==================================================

.EQU INODE_OPS,      0
.EQU INODE_PRIVATE,  4
.EQU INODE_TYPE,     8
.EQU INODE_SIZE,    12
.EQU INODE_REFCNT,  16

.EQU INODE_SIZEOF,  20



; KBUFFER for kernel<->user data transfer, one per task, mapped into each address space at 0x1000-0x1FFF
; for easy access by copy routines and device drivers. Each task has a separate KBUFFER_WR and KBUFFER_RD
; to avoid shared state and synchronization issues.

.org 0x1000
;======================================================================================================
;
; --TASK 0 -------System idle task, runs on kernel space with kernel privs, when no other task is ready.
; Should never exit.
;
;======================================================================================================
idle_task:
0x00001000       ENABLEINT
0x00001004       LI R1 0
idle_loop:
0x0000100C       ADD R1 R1 1
    ;DEBUG 1
0x00001010       B idle_loop



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

        ;init console mutex
0x00002038   CALL init_console_mutex

        ; Mount the built-in read-only TAR archive and show its index.
0x00002040           LI R1 tarfs_start
0x00002048           LI R2 tarfs_end
0x00002050           SUB R2 R2 R1
0x00002054   CALL tarfs_init
0x0000205C   CALL tarfs_dump_index

0x00002064           LI R1 etc_path
0x0000206C   CALL tarfs_readdir

0x00002074           LI R1 bin_path
0x0000207C   CALL tarfs_readdir

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
0x00002084           LI R1 tasks
0x0000208C           LDW R2 [R1 + TASK_PTBR]
0x00002090           SETPTBR R2
0x00002094           LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
0x00002098   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore
0x000020A0           B trap_restore

; ================================================================
; Initialize console mutex at boot time
; ================================================================

init_console_mutex:
0x000020A8       PUSH LR
0x000020AC       LI R1 console_mutex
0x000020B4       BL mutex_init
0x000020BC       POP LR
0x000020C0       RET

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x000020C4       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x000020CC       LI R2 trap_entry
0x000020D4       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x000020D8       LI R2 trap_entry
0x000020E0       STW R2 [R1+4]                ; IDT[1]
0x000020E4       STW R2 [R1+8]                ; IDT[2]
0x000020E8       STW R2 [R1+12]               ; IDT[3]
0x000020EC       STW R2 [R1+24]               ; IDT[6]
0x000020F0       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x000020F4       SETIDTR R1
0x000020F8       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables:
0x000020FC       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x00002100       LI R1 page_bitmap
0x00002108       LI R3 16
0x00002110       BL mem_zero

0x00002118       POP LR
0x0000211C       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x00002120       PUSH LR
0x00002124       PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
0x00002128       LI R2 0x00000000      ;page 0 - boot (0000)
0x00002130       LI R3 0x00000000
0x00002138       LI R4 KERNEL_FLAGS
0x00002140       bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x00002148       LI R2 0x00001000      ; page for kernel buffers
0x00002150       LI R3 0x00001000
0x00002158       LI R4 KERNEL_FLAGS
0x00002160       BL map_page

0x00002168       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x00002170       LI R3 0x00002000
0x00002178       LI R4 KERNEL_FLAGS
0x00002180       BL map_page

0x00002188       LI R2 0x00003000
0x00002190       LI R3 0x00003000
0x00002198       LI R4 KERNEL_FLAGS
0x000021A0       BL map_page

0x000021A8       LI R2 0x00004000
0x000021B0       LI R3 0x00004000
0x000021B8       LI R4 KERNEL_FLAGS
0x000021C0       BL map_page

0x000021C8       LI R2 0x00005000
0x000021D0       LI R3 0x00005000
0x000021D8       LI R4 KERNEL_FLAGS
0x000021E0       BL map_page

0x000021E8       LI R2 0x00006000
0x000021F0       LI R3 0x00006000
0x000021F8       LI R4 KERNEL_FLAGS
0x00002200       BL map_page

0x00002208       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x00002210       LI R3 0x00007000
0x00002218       LI R4 KERNEL_FLAGS
0x00002220       BL map_page

0x00002228       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x00002230       LI R3 0x00008000
0x00002238       LI R4 KERNEL_FLAGS
0x00002240       BL map_page

0x00002248       LI R2 0x00009000      ; add page (number is page table entry one) tasks data
0x00002250       LI R3 0x00009000
0x00002258       LI R4 KERNEL_FLAGS
0x00002260       BL map_page

0x00002268       LI R2 0x0000A000      ; add page (number is page table entry one) tasks data
0x00002270       LI R3 0x0000A000
0x00002278       LI R4 KERNEL_FLAGS
0x00002280       BL map_page

0x00002288       LI R2 0x0000B000      ; add page (number is page table entry one) tasks data
0x00002290       LI R3 0x0000B000
0x00002298       LI R4 KERNEL_FLAGS
0x000022A0       BL map_page

0x000022A8       LI R2 0x0000C000      ; add page (number is page table entry one) tasks data
0x000022B0       LI R3 0x0000C000
0x000022B8       LI R4 KERNEL_FLAGS
0x000022C0       BL map_page



    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x000022C8       LI R2 0x00100000      ; UART physical and virtual base
0x000022D0       LI R3 0x00100000
0x000022D8       LI R4 KERNEL_FLAGS
0x000022E0       BL map_page

0x000022E8       LI R2 0x00101000      ; PIT physical and virtual base
0x000022F0       LI R3 0x00101000
0x000022F8       LI R4 KERNEL_FLAGS
0x00002300       BL map_page

0x00002308       LI R2 0x00102000      ; PIC physical and virtual base
0x00002310       LI R3 0x00102000
0x00002318       LI R4 KERNEL_FLAGS
0x00002320       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x00002328       LI R12 PAGE_ALLOC_BASE
0x00002330       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x00002338       CMP R12 R7
0x0000233C       BGE map_common_dynamic_done
0x00002344       MOV R2 R12
0x00002348       MOV R3 R12
0x0000234C       LI R4 KERNEL_FLAGS
0x00002354       BL map_page
0x0000235C       LI R6 PAGE_SIZE
0x00002364       ADD R12 R12 R6
0x00002368       B map_common_dynamic_loop
map_common_dynamic_done:

0x00002370       POP R12
0x00002374       POP LR
0x00002378       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x0000237C       PUSH R5
0x00002380       PUSH R6
0x00002384       SHR R5 R2 12               ; VPN
0x00002388       SHL R5 R5 2                ; page-table byte offset
0x0000238C       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002390       STW R6 [R1 + R5]
0x00002394       POP R6
0x00002398       POP R5
0x0000239C       RET

map_page_rt:
    ; Runtime page-table update. Same ABI as map_page, but also invalidates
    ; the cached translation for R2 so permission changes take effect now.
0x000023A0       PUSH R5
0x000023A4       PUSH R6
0x000023A8       SHR R5 R2 12               ; VPN
0x000023AC       SHL R5 R5 2                ; page-table byte offset
0x000023B0       OR R6 R3 R4                ; PTE = PA page base | flags
0x000023B4       STW R6 [R1 + R5]
0x000023B8       INVLPG R2
0x000023BC       POP R6
0x000023C0       POP R5
0x000023C4       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x000023C8       LI R1 0x00102000
0x000023D0       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x000023D8       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x000023DC       LI R1 0x00101000
0x000023E4       LI R2 2000
0x000023EC       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x000023F0       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000023F8       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x000023FC       LI R1 0x00100000
0x00002404       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x0000240C       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x00002410       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x00002414       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x00002418       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x0000241C       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x00002420       PUSH R1
0x00002424       PUSH R2
0x00002428       PUSH R3
0x0000242C       PUSH R4
0x00002430       PUSH R5
0x00002434       PUSH R6
0x00002438       PUSH R7
0x0000243C       PUSH R8
0x00002440       PUSH R9
0x00002444       PUSH R10
0x00002448       PUSH R11
0x0000244C       PUSH R12
0x00002450       PUSH R14
0x00002454       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x00002458       CSRR R1 SSCRATCH
0x0000245C       PUSH R1
0x00002460       CSRR R1 SEPC
0x00002464       PUSH R1
0x00002468       CSRR R1 SFLAGS
0x0000246C       PUSH R1
0x00002470       CSRR R1 SSTATUS
0x00002474       PUSH R1
0x00002478       CSRR R1 SCAUSE
0x0000247C       PUSH R1
0x00002480       CSRR R1 STVAL
0x00002484       PUSH R1

    ; Dispatch based on scause.
0x00002488       CSRR R1 SCAUSE
0x0000248C       CMP R1 0
0x00002490       BEQ handle_divide_zero

0x00002498       CMP R1 1
0x0000249C       BEQ handle_invalid_instr

0x000024A4       CMP R1 2
0x000024A8       BEQ handle_page_fault

0x000024B0       CMP R1 3
0x000024B4       BEQ handle_syscall

0x000024BC       CMP R1 6
0x000024C0       BEQ handle_debug

0x000024C8       CMP R1 16
0x000024CC       BEQ handle_irq

    ; Unknown cause - halt
0x000024D4       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x000024D8       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x000024E0       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x000024E8       HLT

0x000024EC       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x000024F4       CSRR R2 STVAL

0x000024F8       CMP R2 SYS_COUNT
0x000024FC       BGE syscall_unknown

0x00002504       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x0000250C       SHL R4 R2 2
0x00002510       LDW R5 [R3 + R4]
0x00002514       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x00002518       LI R1 ERR_NOSYS
0x00002520       STW R1 [SP + TF_R1]
0x00002524       B trap_restore

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
    .WORD syscall_dup           ; SVC 9
    .WORD syscall_gettime       ; SVC 10
    .WORD syscall_brk           ; SVC 11
    .WORD syscall_sbrk          ; SVC 12
    .WORD syscall_execve        ; SVC 13
    .WORD syscall_fork          ; SVC 14
    .WORD syscall_sleep         ; SVC 15
    .WORD syscall_waitpid       ; SVC 16

syscall_execve:
    ;================================================================
    ; execve(path, argv, envp)
    ; R1 = user path
    ; R2 = user argv (NULL-terminated vector of user string pointers)
    ; R3 = user envp (ignored for now)
    ;
    ; Overview:
    ; 1) copy pathname from user space into kernel buffer
    ; 2) lookup the file in TARFS/VFS and verify it is an executable file
    ; 3) allocate a new code page and map it RW at USER_CODE_VA
    ; 4) zero the task's data page and load the file content into the code page
    ; 5) commit the new task state: PC=user_code_va, USP=USER_STACK_TOP, program break reset
    ; 6) remap the code page read-only and free any previous exec page
    ; 7) restore the trapframe to begin executing the new program
    ;
    ; On success this does not return to the caller; the current task continues
    ; with a freshly-loaded user image at USER_CODE_VA. On failure it returns
    ; errno in R1 through the normal trap_restore path.
    ;================================================================

0x00002570       LDW R8 [SP + TF_R1]        ; user path pointer

0x00002574       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00002578       PUSH R9

0x0000257C       MOV R1 R8
0x00002580       BL copy_path_from_user
0x00002588       CMP R1 0
0x0000258C       BEQ execve_badfault

0x00002594       MOV R12 R1                ; kernel pointer to copied pathname

0x00002598       MOV R1 R12
0x0000259C       BL vfs_lookup             ; lookup inode for the file
0x000025A4       CMP R1 0
0x000025A8       BEQ execve_noent

0x000025B0       MOV R9 R1                 ; inode*
0x000025B4       LDW R1 [R9 + INODE_TYPE]
0x000025B8       LI R2 INODE_DIR
0x000025C0       CMP R1 R2
0x000025C4       BEQ execve_noexec           ; if the inode is a directory, we cannot execute it

0x000025CC       LDW R3 [R9 + INODE_SIZE]
0x000025D0       LI R4 PAGE_SIZE         ; 4096 bytes
0x000025D8       CMP R3 R4
0x000025DC       BGT execve_noexec       ; if the inode size is greater than a page, we cannot execute it

0x000025E4       BL file_alloc
0x000025EC       CMP R1 0
0x000025F0       BEQ execve_nomem         ; if we cannot allocate a file for this inode, return error

0x000025F8       MOV R10 R1                ; file*
0x000025FC       MOV R1 R10
0x00002600       MOV R2 R9
0x00002604       LI R3 FD_FLAG_READ
0x0000260C       BL file_init            ; initialize the file structure for reading the executable

0x00002614       BL page_alloc           ; allocate a new page for the executable code of execve program
0x0000261C       CMP R1 0
0x00002620       BEQ execve_noexec_file

0x00002628       MOV R11 R1                ; new code page PA for execve program

; macro: GET_CURR_TASK_IDX R4    ; get current task index
0x0000262C   LI R1 CURRENT_TASK
0x00002634   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002638   LI R1 TASK_SIZE
0x00002640   MUL R3 R4 R1
0x00002644   LI R5 tasks
0x0000264C   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12, R5 ; preserve old exec code page PA for rollback / cleanup
0x00002650   LDW R12 [R5 + TASK_CODE_PAGE]
; macro: TASK_GET_PTBR R1, R5       ; R1 = PTBR of current task
0x00002654   LDW R1 [R5 + TASK_PTBR]
0x00002658       LI R2 USER_CODE_VA         ; R2 = code page VA for execve program
0x00002660       MOV R3 R11                 ; R3 = code page PA for execve program
0x00002664       LI R4 USER_RW              ; R4 = temporary RW permissions so we can load the page
0x0000266C       BL map_page_rt             ; runtime map executable page RW at USER_CODE_VA for loading

; macro: TASK_GET_DATA_PAGE R1, R5  ; get data page PA for current task
0x00002674   LDW R1 [R5 + TASK_DATA_PAGE]
0x00002678       CMP R1 0
0x0000267C       BEQ execve_data_ok         ; if the task has no data page, skip clearing it
0x00002684       LI R3 PAGE_SIZE
0x0000268C       BL mem_zero                ; zero the current task data page before execve starts

execve_data_ok:

0x00002694       MOV R1 R10              ; file* of execve program
0x00002698       LI R2 USER_CODE_VA      ; VA of code page for execve program
0x000026A0       LI R3 PAGE_SIZE         ; size of code page for execve program
0x000026A8       BL file_read            ; load executable into USER_CODE_VA
0x000026B0       CMP R1 0
0x000026B4       BLT execve_read_fail    ; if read fails, restore old exec code page and return error

0x000026BC       MOV R1 R10              ; file* of execve program
0x000026C0       BL file_put             ; release file resources after successful load

; macro: GET_CURR_TASK_IDX R4    ; this was real mistake here! I forgot to retore current task ptr
0x000026C8   LI R1 CURRENT_TASK
0x000026D0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4     ; reload task ptr after calls that may clobber caller-saved R5
0x000026D4   LI R1 TASK_SIZE
0x000026DC   MUL R3 R4 R1
0x000026E0   LI R5 tasks
0x000026E8   ADD R5 R5 R3
                            ; we also added INVLPG - for good! - history comments
    ; commit new exec state after successful file load
0x000026EC       LI R1 USER_CODE_VA
; macro: TASK_SET_PC R5, R1              ; start execution at USER_CODE_VA
0x000026F4   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5, R11      ; remember physical page backing this user code
0x000026F8   STW R11 [R5 + TASK_CODE_PAGE]
0x000026FC       LI R1 USER_STACK_TOP
; macro: TASK_SET_USP R5, R1             ; reset user stack pointer
0x00002704   STW R1 [R5 + TASK_USP]
0x00002708       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5, R1           ; reset program break into the task's data page
0x00002710   STW R1 [R5 + TASK_BREAK]

    ; Remap the new code page read-only before handing control over
; macro: TASK_GET_PTBR R1, R5            ; get PTBR of current task
0x00002714   LDW R1 [R5 + TASK_PTBR]
0x00002718       LI R2 USER_CODE_VA              ; VA of code page for execve program
0x00002720       MOV R3 R11                      ; PA of code page for execve program
0x00002724       LI R4 KERNEL_USER_ALL
0x0000272C       BL map_page_rt                  ; switch the new code page from RW to RX

   ; DEBUG 2

0x00002734       CMP R12 0                       ; R12 = old code page PA for execve program from task metadata
0x00002738       BEQ execve_commit_done          ; if no previous code page, skip freeing it
0x00002740       MOV R1 R12
0x00002744       BL page_free                    ; free the old exec code page now that the new one is committed

execve_commit_done:
    ; Build a fresh Unix-style initial stack:
    ;   [argc][argv pointers...][NULL][string data...]
    ; The new program can read argc/argv from the stack, and we also mirror
    ; argc/argv into R1/R2 for convenience.

0x0000274C       POP R4                         ; remember argv ptr from start of syscall
0x00002750       LI R6 0                        ; R6 = argc counter

    ; Step 1: Count argc
0x00002758       MOV R7 R4
execve_argv_count_loop:
0x0000275C       CMP R7 0
0x00002760       BEQ execve_argv_count_done
0x00002768       LDW R8 [R7]
0x0000276C       CMP R8 0
0x00002770       BEQ execve_argv_count_done

0x00002778       CMP R6 16                      ;MAX argc count
0x0000277C       BGE execve_badfault

0x00002784       ADD R6 R6 1
0x00002788       ADD R7 R7 4
0x0000278C       B execve_argv_count_loop

execve_argv_count_done:
    ; Now we know argc = R6, argv = R4

    ;=============================================================
    ; Build initial user stack
    ;
    ; Stack layout after exec:
    ;
    ;   USER_STACK_TOP
    ;        |
    ;        |  copied strings ptrs!!! we dont toch actual strings et-al and ptrs!!!
    ;        |
    ;        |  argv[argc] = NULL
    ;        |  argv[argc-1]
    ;        |  ...
    ;        |  argv[0]
    ;        |  argc
    ;        +---------------------> initial user SP
    ;
    ; On entry:
    ;   R4 = source argv[]
    ;   R6 = argc
    ;
    ; On exit:
    ;   R1 = argc
    ;   R2 = argv
    ;   USP points at argc
    ;=============================================================

    ;-------------------------------------------------------------
    ; Start copying strings from top of user stack downward.
    ; R5 = current string cursor
    ;-------------------------------------------------------------
0x00002794       LI  R5 USER_STACK_TOP

    ;-------------------------------------------------------------
    ; Temporary kernel array for argv pointers.
    ; argv_tmp[16]
    ;-------------------------------------------------------------
0x0000279C       LI  R11 execve_tmp_argv

    ;-------------------------------------------------------------
    ; Copy strings in reverse order so they naturally pack downward.
    ;-------------------------------------------------------------
0x000027A4       MOV R7 R6
0x000027A8       SUB R7 R7 1             ; [argc]-1

execve_copy_reverse:
0x000027AC       LI  R8 -1
0x000027B4       CMP R7 R8
0x000027B8       BEQ execve_strings_done

    ; source string = argv[i] starting from last arg string
    ;MUL R8 R7 4
0x000027C0       MOV R8 R7
0x000027C4       SHL R8 R8 2             ;*4+ptr
0x000027C8       ADD R9 R4 R8
0x000027CC       LDW R10 [R9]            ;last argv string ptr

    ;-------------------------------------------------------------
    ; strlen()
    ; R12 = length including terminating NUL
    ;-------------------------------------------------------------
0x000027D0       LI R12 0                ;str len ctr - compute this argv string len (+ 0)

execve_strlen:

0x000027D8       LDB R2 [R10 + R12]
0x000027DC       ADD R12 R12 1
0x000027E0       CMP R2 0
0x000027E4       BNE execve_strlen

    ; reserve space - on user stack top this argv string destination

0x000027EC       SUB R5 R5 R12               ; R5 dest addres argv string copy to gets updated by lenght of each string
                                ; to be copied to tmp

    ; remember destination pointer
0x000027F0       MOV R8 R7
0x000027F4       SHL R8 R8 2                 ;R7 argv string number in argv array
0x000027F8       ADD R9 R11 R8
0x000027FC       STW R5 [R9]                 ;R5(R11) points to temp storage

    ; memcpy()

0x00002800       LI R8 0

execve_copy_string:             ; first copy strings ptrs from (argv array) to temp stogare strings
                                ; from last string to first - opposite order
0x00002808       LDB R2 [R10 + R8]           ; R10 execv argv &string[i]  (last to first)
0x0000280C       STB R2 [R5 + R8]            ; R5 same in tmp

0x00002810       CMP R2 0
0x00002814       BEQ execve_copy_done

0x0000281C       ADD R8 R8 1
0x00002820       B execve_copy_string

execve_copy_done:

0x00002828       SUB R7 R7 1                 ; to copy next string
0x0000282C       B execve_copy_reverse

execve_strings_done:            ;copy argv strings array to temp storage in opposite order is done

    ;-------------------------------------------------------------
    ; Reserve space for:
    ;
    ; argc
    ; argv[0..argc-1] - already updated R5 while copy str + argc(word)+null(word)
    ; NULL
    ;
    ; stack_words = argc + 2
    ;-------------------------------------------------------------
0x00002834       MOV R7 R6
0x00002838       ADD R7 R7 2

0x0000283C       MOV R8 R7
0x00002840       SHL R8 R8 2

0x00002844       SUB R5 R5 R8            ;update R5 by stack words

    ;-------------------------------------------------------------
    ; R5 now becomes initial user stack pointer.
    ;-------------------------------------------------------------

0x00002848       STW R6 [R5]             ; put argc to user stack see picture above (Reserve space for:)

0x0000284C       ADD R9 R5 4             ; R9 - move 'writing head' to next element argv in user stack
                            ; R5 - initial user stack pointer
    ;-------------------------------------------------------------
    ; Copy argv pointers
    ;-------------------------------------------------------------
0x00002850       LI R7 0

execve_copy_argv:

0x00002858       CMP R7 R6
0x0000285C       BEQ execve_copy_argv_done

0x00002864       MOV R8 R7
0x00002868       SHL R8 R8 2

0x0000286C       LDW R12 [R11 + R8]       ;we copy stings pointers here not actual strings!

0x00002870       STW R12 [R9 + R8]

0x00002874       ADD R7 R7 1
0x00002878       B execve_copy_argv

execve_copy_argv_done:

    ; argv[argc] = NULL
0x00002880       MOV R8 R6
0x00002884       SHL R8 R8 2
0x00002888       ADD R10 R9 R8

0x0000288C       LI R12 0
0x00002894       STW R12 [R10]               ; write NuLL - finish form user stack frame (arguments part!)

    ;-------------------------------------------------------------
    ; Prepare trapframe for new process.
    ;-------------------------------------------------------------

0x00002898       STW R6 [SP + TF_R1]      ; argc

0x0000289C       MOV R1 R9
0x000028A0       STW R1 [SP + TF_R2]      ; argv

0x000028A4       LI R1 0
0x000028AC       STW R1 [SP + TF_R3]      ; envp

0x000028B0       STW R5 [SP + TF_USP]     ; initial user SP


    ; Prepare a fresh user register state for the new program.
0x000028B4       LI R1 0
0x000028BC       STW R1 [SP + TF_R4]
0x000028C0       STW R1 [SP + TF_R5]
0x000028C4       STW R1 [SP + TF_R6]
0x000028C8       STW R1 [SP + TF_R7]
0x000028CC       STW R1 [SP + TF_R8]
0x000028D0       STW R1 [SP + TF_R9]
0x000028D4       STW R1 [SP + TF_R10]
0x000028D8       STW R1 [SP + TF_R11]
0x000028DC       STW R1 [SP + TF_R12]
0x000028E0       LI R1   USER_CODE_VA               ; user execve program entry point
0x000028E8       STW R1 [SP + TF_SEPC]              ; set SEPC to the new program entry point

0x000028EC       B trap_restore                     ; restore kernel trapframe and start user execution at user_code_va

execve_read_fail:
0x000028F4       MOV R1 R11
0x000028F8       BL page_free                  ; free the failed new code page

; macro: GET_CURR_TASK_IDX R4
0x00002900   LI R1 CURRENT_TASK
0x00002908   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4           ; reload task ptr before restoring USER_CODE_VA mapping
0x0000290C   LI R1 TASK_SIZE
0x00002914   MUL R3 R4 R1
0x00002918   LI R5 tasks
0x00002920   ADD R5 R5 R3

0x00002924       CMP R12 0
0x00002928       BEQ execve_restore_no_prev
; macro: TASK_GET_PTBR R1, R5
0x00002930   LDW R1 [R5 + TASK_PTBR]
0x00002934       LI R2 USER_CODE_VA
0x0000293C       MOV R3 R12
0x00002940       LI R4 USER_RX
0x00002948       BL map_page_rt                ; restore previous exec page mapping at USER_CODE_VA
0x00002950       MOV R1 R12
; macro: TASK_SET_CODE_PAGE R5, R12    ; restore previous exec code page pointer
0x00002954   STW R12 [R5 + TASK_CODE_PAGE]
0x00002958       B execve_restore_done

execve_restore_no_prev:
; macro: TASK_GET_PTBR R1, R5
0x00002960   LDW R1 [R5 + TASK_PTBR]
0x00002964       LI R2 USER_CODE_VA
0x0000296C       LI R3 0
0x00002974       LI R4 0
0x0000297C       BL map_page_rt                ; unmap USER_CODE_VA if there was no previous code page
0x00002984       LI R1 0
; macro: TASK_SET_CODE_PAGE R5, R1
0x0000298C   STW R1 [R5 + TASK_CODE_PAGE]

execve_restore_done:
0x00002990       MOV R1 R10
0x00002994       BL file_put

0x0000299C       POP R1                      ;save stack
0x000029A0       LI R1 ERR_NOEXEC
0x000029A8       STW R1 [SP + TF_R1]
0x000029AC       B trap_restore

execve_nomem_file:
0x000029B4       MOV R1 R10
0x000029B8       BL file_put

0x000029C0       POP R1
0x000029C4       LI R1 ERR_NOMEM
0x000029CC       STW R1 [SP + TF_R1]
0x000029D0       B trap_restore

execve_nomem:
0x000029D8       POP R1
0x000029DC       LI R1 ERR_NOMEM
0x000029E4       STW R1 [SP + TF_R1]
0x000029E8       B trap_restore

execve_noexec_file:

0x000029F0       MOV R1 R10
0x000029F4       BL file_put
execve_noexec:
0x000029FC       POP R1
0x00002A00       LI R1 ERR_NOEXEC
0x00002A08       STW R1 [SP + TF_R1]
0x00002A0C       B trap_restore

execve_noent:
0x00002A14       POP R1
0x00002A18       LI R1 ERR_NOENT
0x00002A20       STW R1 [SP + TF_R1]
0x00002A24       B trap_restore

execve_badfault:
0x00002A2C       POP R1
0x00002A30       LI R1 ERR_FAULT
0x00002A38       STW R1 [SP + TF_R1]
0x00002A3C       B trap_restore

;-------------------------------------------------------------
; Temporary argv pointer storage during execve
; Supports up to 16 arguments.
;-------------------------------------------------------------
execve_tmp_argv:
    .SPACE 64        ; 16 × 4-byte pointers

syscall_fork:
    ;================================================================
    ; fork()
    ; Returns child PID in the parent and 0 in the child.
    ; This clones the current task, duplicating its address space and
    ; user-writable state while preserving a new independent child thread.
    ;================================================================

0x00002A84       BL task_clone_current
0x00002A8C       CMP R1 0
0x00002A90       BEQ fork_fail

    ; We return child PID to the parent via the trapframe.
; macro: TASK_GET_PID R2, R1
0x00002A98   LDW R2 [R1 + TASK_PID]
0x00002A9C       STW R2 [SP + TF_R1]
0x00002AA0       B trap_restore

fork_fail:
0x00002AA8       LI R1 ERR_NOMEM
0x00002AB0       STW R1 [SP + TF_R1]
0x00002AB4       B trap_restore

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x00002ABC       LI R1 0
0x00002AC4       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00002AC8       B schedule_and_switch
;================================================================
; syscall_exit: - finish user process
; in R1 - exit code
;
;1. Child calls exit()
;2. exit() stores exit code in TASK_EXIT_CODE for parent task to collect
;3. exit() marks child as ZOMBIE
;4. exit() finds parent task
;5. exit() checks if parent is waiting for this child
;6. If yes, exit() calls waitq_wake_bitmask on child_waitq
;7. waitq_wake_bitmask:
;   - Removes parent from child_waitq
;   - Marks parent as TASK_READY
;8. exit() calls schedule_and_switch
;9. Scheduler picks parent (now READY)
;10. Parent resumes right after BL schedule_call (in its waitforpid)
;11. Parent re-checks if child is ZOMBIE
;12. Parent reaps the child and returns
;================================================================
syscall_exit:
    ; Get exit code from R1
0x00002AD0       LDW R8 [SP + TF_R1]        ; R8 = exit code

; macro: GET_CURR_TASK_IDX R2
0x00002AD4   LI R1 CURRENT_TASK
0x00002ADC   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002AE0   LI R1 TASK_SIZE
0x00002AE8   MUL R3 R2 R1
0x00002AEC   LI R5 tasks
0x00002AF4   ADD R5 R5 R3

    ; Store exit code in child task struct for parent to collect in waitforpid
; macro: TASK_SET_EXIT_CODE R5, R8  ; Save exit code
0x00002AF8   STW R8 [R5 + TASK_EXIT_CODE]

0x00002AFC       PUSH R5
0x00002B00       MOV R1 R5
0x00002B04       BL task_close_fds          ; close all open file descriptors of this task (if any) to free file_pool resources
0x00002B0C       POP R5

    ; Mark this child as zombie (still exists but not runnable)
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x00002B10   LI R1 TASK_ZOMBIE
0x00002B18   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00002B1C   LI R1 WAIT_NONE
0x00002B24   STW R1 [R5 + TASK_WAIT]

    ; Wake parent if it's waiting
; macro: TASK_GET_PPID R6, R5       ; R6 = parent PID
0x00002B28   LDW R6 [R5 + TASK_PPID]

    ; find parent task by PPID
0x00002B2C       MOV R1 R6
0x00002B30       LI R2 0                    ; Search by PID (parent's PID)
0x00002B38       BL task_find               ; R1 = found parent task*
0x00002B40       CMP R1 0
0x00002B44       BEQ no_parent_waiting
0x00002B4C       MOV R7 R1                  ; R7 = parent task*
0x00002B50       MOV R11 R2                 ; save parent task index for bitmask

    ;Check if parent is waiting for this child
; macro: TASK_GET_WAIT_CHILD R8, R7 ; Child PID that parent R7 ptr is waiting for
0x00002B54   LDW R8 [R7 + TASK_WAIT_CHILD]
; macro: TASK_GET_PID R9, R5        ; This child's R5 ptr PID
0x00002B58   LDW R9 [R5 + TASK_PID]

0x00002B5C       LI R10 -1
0x00002B64       CMP R8 R10                 ; if parent is waiting for any child (-1), then wake it up
0x00002B68       BEQ wake_parent            ;

0x00002B70       CMP R8 R9
0x00002B74       BNE no_parent_waiting      ; parent is waiting for a different child, do not wake it up

wake_parent:
    ; Find parent's task index for bitmask
    ; we already have parent task in R11

0x00002B7C       LI R9 1
0x00002B84       SHL R9 R9 R11               ; bit for parent task

0x00002B88       LI R1 child_waitq
0x00002B90       MOV R2 R9
0x00002B94       BL waitq_wake_bitmask       ;unblock parent task waiting for this child

no_parent_waiting:
0x00002B9C       B schedule_and_switch

;=================================================================
; syscall_waitpid - wait for a child process
;
; Input: R1 = PID of child to wait for (or -1 for any child)
;        R2 = pointer to status variable (user space)
;
; Returns: R1 = PID of child that exited, or -1 on error,
; pointer to status variable is updated with exit code if not NULL
;=================================================================

syscall_waitpid:
0x00002BA4       LDW R8 [SP + TF_R1]        ; R8 = pid to wait for
0x00002BA8       LDW R9 [SP + TF_R2]        ; R9 = status pointer

    ; Validate status pointer
0x00002BAC       CMP R9 0
0x00002BB0       BEQ waitpid_validate_done
0x00002BB8       MOV R1 R9
0x00002BBC       LI R2 4
0x00002BC4       LI R3 1
0x00002BCC       BL user_buffer_valid_range
0x00002BD4       CMP R1 1
0x00002BD8       BNE waitpid_badptr

waitpid_validate_done:
; macro: GET_CURR_TASK_IDX R4
0x00002BE0   LI R1 CURRENT_TASK
0x00002BE8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002BEC   LI R1 TASK_SIZE
0x00002BF4   MUL R3 R4 R1
0x00002BF8   LI R5 tasks
0x00002C00   ADD R5 R5 R3
; macro: TASK_GET_PID R10, R5       ; R10 = current (parent proc) PID
0x00002C04   LDW R10 [R5 + TASK_PID]

    ; if search for any child
0x00002C08       LI  R2 -1
0x00002C10       CMP R8 R2
0x00002C14       BNE find_child_by_pid
    ; set task_find to search for any child of this parent
0x00002C1C       MOV R1 R10                  ; R1 = parent PID (PPID in child task)
0x00002C20       LI  R2 1                    ; search by PPID
0x00002C28       BL task_find               ; R1 = found child task*
0x00002C30       CMP R1 0
0x00002C34       BEQ waitpid_no_child        ; No any child with PPID = this parent PID found
    ;R1 child task* found
0x00002C3C       B find_any_child_found
find_child_by_pid:
    ; Search for child task by PID
0x00002C44       MOV R1 R8                  ; R1 = child PID to search for
0x00002C48       LI R2 0                    ; Search by PID
0x00002C50       BL task_find               ; R1 = found child task*
0x00002C58       CMP R1 0
0x00002C5C       BEQ waitpid_no_child        ; No such child

find_any_child_found:

0x00002C64       MOV R7 R1                   ; R7 = child task*

    ; Verify it's actually our child by its PPID fld
; macro: TASK_GET_PPID R1, R7
0x00002C68   LDW R1 [R7 + TASK_PPID]
0x00002C6C       CMP R1 R10
0x00002C70       BNE waitpid_no_child
    ; R7 = child task*
    ; check its state, if ZOMBIE, we can reap it and return its exit code
; macro: TASK_GET_STATE R1, R7
0x00002C78   LDW R1 [R7 + TASK_STATE]
0x00002C7C       CMP R1 TASK_ZOMBIE
0x00002C80       BEQ waitpid_reap_child

    ; Child running - block parent
; macro: TASK_GET_PID R1, R7
0x00002C88   LDW R1 [R7 + TASK_PID]
; macro: TASK_SET_WAIT_CHILD R5, R1
0x00002C8C   STW R1 [R5 + TASK_WAIT_CHILD]

0x00002C90       LI R1 child_waitq           ; child_waitq ptr
0x00002C98       LI R2 WAIT_CHILD            ; reason
0x00002CA0       LI R3 TASK_SLEEPING         ; state to set for current task
0x00002CA8       BL waitq_prepare_sleep

0x00002CB0       BL waitq_sleep_current     ; freeze the current task

    ; will resume here when child exits and wakes us up

waitpid_reap_child:
    ; Get exit code from child task
; macro: TASK_GET_EXIT_CODE R2, R7
0x00002CB8   LDW R2 [R7 + TASK_EXIT_CODE]

    ; If status pointer is not NULL, write exit code to user space
0x00002CBC       CMP R9 0
0x00002CC0       BEQ waitpid_reap_done

0x00002CC8       MOV R1 R9                  ; R1 = user status pointer
0x00002CCC       MOV R4 R2                  ; preserve exit code in kernel source register
0x00002CD0       LI  R2 4                   ; R2 = size of exit code
0x00002CD8       BL copy_to_user            ; write exit code to user space

waitpid_reap_done:
; macro: TASK_GET_PID R10, R7       ; get child's PID
0x00002CE0   LDW R10 [R7 + TASK_PID]
0x00002CE4       MOV R1 R7                  ; R1 = child task*
0x00002CE8       BL task_destroy

0x00002CF0       STW R10 [SP + TF_R1]        ; save child's PID to trapframe for return
0x00002CF4       B trap_restore

waitpid_no_child:
0x00002CFC       LI R1 ERR_CHILD
0x00002D04       STW R1 [SP + TF_R1]
0x00002D08       B trap_restore

waitpid_badptr:
0x00002D10       LI R1 ERR_FAULT
0x00002D18       STW R1 [SP + TF_R1]
0x00002D1C       B trap_restore


;================================================================
; task_find - find a task by PID or PPID
;
; Input:
;   R1 = PID or PPID to search for
;   R2 = search mode:
;        0 = search by PID
;        1 = search by PPID
;
; Returns:
;   R1 = task* if found and R2 = task index
;   R1 = 0 if not found
;================================================================
task_find:
0x00002D24       PUSH R5
0x00002D28       PUSH R6
0x00002D2C       PUSH R7

0x00002D30       MOV R5 R2                  ; Save search mode
0x00002D34       MOV R7 R1                  ; Save PID/PPID
0x00002D38       LI R2 0                    ; Task index
task_find_loop:
0x00002D40       LI R3 MAX_TASKS
0x00002D48       CMP R2 R3
0x00002D4C       BGE task_find_not_found

; macro: GET_TASK_PTR R4, R2
0x00002D54   LI R1 TASK_SIZE
0x00002D5C   MUL R3 R2 R1
0x00002D60   LI R4 tasks
0x00002D68   ADD R4 R4 R3
; macro: TASK_GET_STATE R6, R4
0x00002D6C   LDW R6 [R4 + TASK_STATE]
0x00002D70       CMP R6 TASK_DEAD
0x00002D74       BEQ task_find_next         ; Skip dead tasks

    ; Search based on mode
0x00002D7C       CMP R5 0
0x00002D80       BEQ task_find_by_pid

    ; Search by PPID
; macro: TASK_GET_PPID R6, R4
0x00002D88   LDW R6 [R4 + TASK_PPID]
0x00002D8C       CMP R6 R7
0x00002D90       BEQ task_find_found
0x00002D98       B task_find_next

task_find_by_pid:
; macro: TASK_GET_PID R6, R4
0x00002DA0   LDW R6 [R4 + TASK_PID]
0x00002DA4       CMP R6 R7
0x00002DA8       BEQ task_find_found

task_find_next:
0x00002DB0       ADD R2 R2 1
0x00002DB4       B task_find_loop

task_find_found:
0x00002DBC       MOV R1 R4                  ; Return task pointer
0x00002DC0       MOV R2 R2                  ; Return task index
0x00002DC4       POP R7
0x00002DC8       POP R6
0x00002DCC       POP R5
0x00002DD0       RET

task_find_not_found:
0x00002DD4       LI R1 0
0x00002DDC       POP R7
0x00002DE0       POP R6
0x00002DE4       POP R5
0x00002DE8       RET

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00002DEC   LI R1 CURRENT_TASK
0x00002DF4   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00002DF8   LI R1 TASK_SIZE
0x00002E00   MUL R3 R2 R1
0x00002E04   LI R5 tasks
0x00002E0C   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00002E10   LDW R1 [R5 + TASK_PID]

0x00002E14       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00002E18       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00002E20       LDW R1 [SP + TF_R1]
0x00002E24       STW R1 [SP + TF_R1]

0x00002E28       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00002E30       LDW R1 [SP + TF_R1]
0x00002E34       LDW R2 [SP + TF_R2]

0x00002E38       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00002E40       CMP R1 0
0x00002E44       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00002E4C   LI R1 CURRENT_TASK
0x00002E54   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002E58   LI R1 TASK_SIZE
0x00002E60   MUL R3 R4 R1
0x00002E64   LI R5 tasks
0x00002E6C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00002E70   LDW R1 [R5 + TASK_KBUF_RD_PTR]

0x00002E74       BL vfs_open

0x00002E7C       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x00002E80       B trap_restore

open_fail_fault:
0x00002E88       LI R1 ERR_FAULT
0x00002E90       STW R1 [SP + TF_R1]     ;file not opened ERR
0x00002E94       B trap_restore


syscall_sleep:
    ;================================================================
    ; sleep(ms)
    ; R1 = milliseconds to sleep
    ;
    ; Returns:
    ;   R1 = 0 on success (slept full duration)
    ;   R1 = -1 on error (invalid time)
    ;================================================================

0x00002E9C       LDW R8 [SP + TF_R1]        ; R8 = milliseconds

0x00002EA0       CMP R8 0
0x00002EA4       BLE sleep_invalid          ; must be positive

; macro: GET_CURR_TASK_IDX R4
0x00002EAC   LI R1 CURRENT_TASK
0x00002EB4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002EB8   LI R1 TASK_SIZE
0x00002EC0   MUL R3 R4 R1
0x00002EC4   LI R5 tasks
0x00002ECC   ADD R5 R5 R3

    ; Calculate wake time in PIT ticks (1 ms per tick).
0x00002ED0       LI R3 timer_ticks
0x00002ED8       LDW R6 [R3]                ; current ticks (1ms per tick)

    ; Convert ms to ticks: 1 tick = 1 ms
0x00002EDC       MOV R7 R8                  ; R7 = ticks to sleep

0x00002EE0       ADD R6 R6 R7               ; R6 = wake time in ticks

    ; Store wake time in task struct
; macro: TASK_SET_WAKE_TIME R5, R6
0x00002EE4   STW R6 [R5 + TASK_WAKE_TIME]

    ; Use existing wait queue infrastructure
0x00002EE8       LI R1 sleep_waitq           ; sleep_waitq ptr
0x00002EF0       LI R2 WAIT_SLEEP            ; reason
0x00002EF8       LI R3 TASK_SLEEPING         ; new state (if other then blocked_io)
0x00002F00       BL waitq_prepare_sleep     ; This marks task as TASK_SLEEP and adds it to the sleep_waitq

0x00002F08       BL waitq_sleep_current     ; freeze the current task in kernel side until it is woken up by the timer interrupt handler when the wake time is reached

    ; Return 0 (will be set when woken)
0x00002F10       LI R1 0
0x00002F18       STW R1 [SP + TF_R1]
0x00002F1C       B trap_restore

sleep_invalid:
0x00002F24       LI R1 ERR_FAULT
0x00002F2C       STW R1 [SP + TF_R1]
0x00002F30       B trap_restore


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
0x00002F38       PUSH LR

0x00002F3C       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00002F40   LI R1 CURRENT_TASK
0x00002F48   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002F4C   LI R1 TASK_SIZE
0x00002F54   MUL R3 R4 R1
0x00002F58   LI R5 tasks
0x00002F60   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x00002F64   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x00002F68       PUSH R9                    ; original destination returned on success
0x00002F6C       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00002F74       LI R11 KBUFFER_SIZE
0x00002F7C       CMP R10 R11
0x00002F80       BGE copy_path_fail

0x00002F88       PUSH R8
0x00002F8C       PUSH R9
0x00002F90       PUSH R10
0x00002F94       MOV R1 R8
0x00002F98       LI R2 1
0x00002FA0       LI R3 0                    ; read access from user source
0x00002FA8       BL user_buffer_valid_range
0x00002FB0       POP R10
0x00002FB4       POP R9
0x00002FB8       POP R8
0x00002FBC       CMP R1 1
0x00002FC0       BNE copy_path_fail

0x00002FC8       LDB R4 [R8]
0x00002FCC       STB R4 [R9]
0x00002FD0       CMP R4 0
0x00002FD4       BEQ copy_path_done

0x00002FDC       ADD R8 R8 1
0x00002FE0       ADD R9 R9 1
0x00002FE4       ADD R10 R10 1
0x00002FE8       B copy_path_loop

copy_path_done:
0x00002FF0       POP R1                     ; original kernel path pointer
0x00002FF4       POP LR
0x00002FF8       RET

copy_path_fail:
0x00002FFC       POP R1                     ; discard original kernel path pointer
0x00003000       LI R1 0
0x00003008       POP LR
0x0000300C       RET

;====================================================================
; devfs_lookup - lookup device files registry
;
; input:
;   R1 = pathname /dev/....
;
; output:
;   R1 = inode for the device
;   R1 = 0 if not found
;====================================================================

devfs_lookup:
0x00003010       PUSH LR
0x00003014       MOV R8 R1                  ; save pathname ptr

0x00003018       LI R7 device_table
0x00003020       LI R9 DEVICE_COUNT

devfs_loop:
0x00003028       CMP R9 0
0x0000302C       BEQ lookup_fail

    ; compare pathname with device name
0x00003034       MOV R1 R8
0x00003038       LDW R2 [R7 + DEV_NAME]
0x0000303C       BL strcmp
0x00003044       CMP R1 1
0x00003048       BEQ devfs_found

0x00003050       ADD R7 R7 DEV_SIZE
0x00003054       SUB R9 R9 1
0x00003058       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x00003060       BL inode_alloc
0x00003068       CMP R1 0
0x0000306C       BEQ devfs_fail

0x00003074       MOV R10 R1         ; inode
    ; 2 init inode
0x00003078       LDW R2 [R7 + DEV_OPS]
0x0000307C       LDW R3 [R7 + DEV_PRIVATE]
0x00003080       LI  R4 INODE_CHAR       ; inode type for dev - char
0x00003088       LI  R5 0                ; size =0
0x00003090       BL inode_init

0x00003098       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x0000309C       POP LR
0x000030A0       RET

devfs_fail:
0x000030A4       LI R1 0
0x000030AC       POP LR
0x000030B0       RET

;====================================================================
; lookup_device in device_table - obsolete replaced by devfs_lookup
;
;input:
; R1 = user pointer to string
;output:
; R1 = device descriptor
 ;R1 = 0 if not found
;====================================================================
lookup_device:

0x000030B4       PUSH LR

0x000030B8       MOV R8 R1                  ; save pathname ptr

0x000030BC       LI R7 device_table
0x000030C4       LI R9 DEVICE_COUNT

lookup_loop:
0x000030CC       CMP R9 0
0x000030D0       BEQ lookup_fail

    ; compare pathname with device name

0x000030D8       MOV R1 R8
0x000030DC       LDW R2 [R7 + DEV_NAME]

0x000030E0       BL strcmp

0x000030E8       CMP R1 1
0x000030EC       BEQ lookup_found

0x000030F4       ADD R7 R7 DEV_SIZE
0x000030F8       SUB R9 R9 1
0x000030FC       B lookup_loop

lookup_found:

0x00003104       MOV R1 R7                  ; return device descriptor ptr

0x00003108       POP LR
0x0000310C       RET

lookup_fail:

0x00003110       LI R1 0

0x00003118       POP LR
0x0000311C       RET

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
0x00003120       LDB R3 [R1]
0x00003124       LDB R4 [R2]

0x00003128       CMP R3 R4
0x0000312C       BNE str_not_equal

0x00003134       CMP R3 0
0x00003138       BEQ str_equal

0x00003140       ADD R1 R1 1
0x00003144       ADD R2 R2 1
0x00003148       B str_loop

str_equal:
0x00003150       LI R1 1
0x00003158       RET

str_not_equal:
0x0000315C       LI R1 0
0x00003164       RET

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
0x00003168       PUSH R3
0x0000316C       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x00003170       LDB R3 [R2]            ; prefix char
0x00003174       CMP R3 0
0x00003178       BEQ sp_match           ; reached end of prefix?

0x00003180       LDB R4 [R1]            ; string char
0x00003184       CMP R4 R3
0x00003188       BNE sp_nomatch

0x00003190       ADD R1 R1 1
0x00003194       ADD R2 R2 1
0x00003198       B sp_loop
sp_match:
0x000031A0       LI R1 1                 ;prefix ok
0x000031A8       POP R4
0x000031AC       POP R3
0x000031B0       RET
sp_nomatch:
0x000031B4       LI R1 0                 ; not ok
0x000031BC       POP R4
0x000031C0       POP R3
0x000031C4       RET

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
0x000031C8       PUSH R3
0x000031CC       PUSH R4
sk_loop:
0x000031D0       LDB R3 [R2]            ; prefix char
0x000031D4       CMP R3 0
0x000031D8       BEQ sk_match           ; reached end of prefix
0x000031E0       LDB R4 [R1]            ; string char
0x000031E4       CMP R4 R3
0x000031E8       BNE sk_nomatch
0x000031F0       ADD R1 R1 1
0x000031F4       ADD R2 R2 1
0x000031F8       B sk_loop

sk_match:
    ; R1 already points past prefix
0x00003200       POP R4
0x00003204       POP R3
0x00003208       RET

sk_nomatch:
0x0000320C       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x00003214       POP R4
0x00003218       POP R3
0x0000321C       RET

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
0x00003220       PUSH R2
0x00003224       PUSH R3
0x00003228       LI R2 0                ; length
pcl_loop:
0x00003230       LDB R3 [R1]
0x00003234       CMP R3 0
0x00003238       BEQ pcl_done
0x00003240       LI R4 47               ; '/'
0x00003248       CMP R3 R4
0x0000324C       BEQ pcl_done
0x00003254       ADD R2 R2 1
0x00003258       ADD R1 R1 1
0x0000325C       B pcl_loop
pcl_done:
0x00003264       MOV R1 R2
0x00003268       POP R3
0x0000326C       POP R2
0x00003270       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x00003274       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x00003278       LI R4 0
0x00003280       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x00003284       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x00003288       LI R4 1
0x00003290       STW R4 [R1 + FILE_REFCNT]
0x00003294       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x00003298       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x0000329C   LI R1 CURRENT_TASK
0x000032A4   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000032A8   LI R1 TASK_SIZE
0x000032B0   MUL R3 R4 R1
0x000032B4   LI R4 tasks
0x000032BC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x000032C0   LDW R4 [R4 + TASK_FD_TABLE]

0x000032C4       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x000032CC       CMP R5 MAX_FDS
0x000032D0       BGE fd_alloc_fail

0x000032D8       SHL R6 R5 2                ; fd * 4
0x000032DC       ADD R7 R4 R6               ; &fd_table[fd]

0x000032E0       LDW R2 [R7]
0x000032E4       CMP R2 0                   ; 0 - empty
0x000032E8       BEQ fd_alloc_found

0x000032F0       ADD R5 R5 1
0x000032F4       B fd_alloc_loop

fd_alloc_found:

0x000032FC       STW R8 [R7]                ; fd_table[fd] = file*

0x00003300       MOV R1 R5                  ; return fd
0x00003304       RET

fd_alloc_fail:

0x00003308       LI R1 ERR_MFILE
0x00003310       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x00003314       LDW R1 [SP + TF_R1]

0x00003318       BL vfs_close

0x00003320       LI R1 0
0x00003328       STW R1 [SP + TF_R1]

0x0000332C       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00003334       LDW R7 [SP + TF_R1]

0x00003338       BL pipe_alloc       ;create new pipe object in pipe_pool
0x00003340       CMP R1 0
0x00003344       BEQ pipe_fail_nospc

0x0000334C       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x00003350       BL file_alloc        ; R1 - created read file ptr for read end
0x00003358       CMP R1 0
0x0000335C       BEQ pipe_fail_read_fd

0x00003364       MOV R9 R1           ; new file for read end  in file_pool
0x00003368       BL inode_alloc      ; get inode for this end file
0x00003370       CMP R1 0
0x00003374       BEQ pipe_fail_ia_read_fd
0x0000337C       MOV R10 R1

0x00003380       LI  R2 pipe_ops         ; pipe_ops table
0x00003388       MOV R3 R8               ; store our slot pipe*
0x0000338C       LI  R4 INODE_PIPE       ; inode type PIPE
0x00003394       LI  R5 0                ; size =0
0x0000339C       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x000033A4       MOV R1 R9                ; R1 file*
0x000033A8       MOV R2 R10               ; inode*
0x000033AC       LI R3  FD_FLAG_READ      ; flags READ end
0x000033B4       BL file_init

0x000033BC       MOV R1 R9
0x000033C0       BL fd_alloc                 ; insert read file to fd_table of user process

0x000033C8       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x000033D0       CMP R1 R2
0x000033D4       BEQ pipe_fail_read_file

0x000033DC       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x000033E0       BL file_alloc
0x000033E8       CMP R1 0
0x000033EC       BEQ pipe_fail_ia_write_fd
0x000033F4       MOV R9 R1

0x000033F8       BL inode_alloc      ; get inode for this end file
0x00003400       CMP R1 0
0x00003404       BEQ pipe_fail_ia_write_fd
0x0000340C       MOV R10 R1

0x00003410       LI  R2 pipe_ops         ; pipe_ops table
0x00003418       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x0000341C       LI  R4 INODE_PIPE       ; inode type PIPE
0x00003424       LI  R5 0                ; size =0
0x0000342C       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x00003434       MOV R1 R9                ; R1 file*
0x00003438       MOV R2 R10               ; inode*
0x0000343C       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x00003444       BL file_init

0x0000344C       MOV R1 R9
0x00003450       BL  fd_alloc

0x00003458       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x00003460       CMP R1 R2
0x00003464       BEQ pipe_fail_write_file

0x0000346C       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x00003470       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x00003474       LI  R2 8     ; len 2 words (8 bytes)
0x0000347C       LI  R3 1     ; mem perm to write cond
0x00003484       BL  user_buffer_valid_range
0x0000348C       CMP R1 1
0x00003490       BNE pipe_fail_both_fds

0x00003498       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x0000349C       STW R11 [R7 + 4]

0x000034A0       LI R1 0
0x000034A8       STW R1 [SP + TF_R1]

0x000034AC       B trap_restore

pipe_fail:
0x000034B4       LI R1 ERR_IO
0x000034BC       STW R1 [SP + TF_R1]

0x000034C0       B trap_restore

pipe_fail_both_fds:
0x000034C8       MOV R12 R8
0x000034CC       MOV R1 R11
0x000034D0       BL fd_remove
0x000034D8       CMP R1 0
0x000034DC       BEQ pipe_fail_both_fds_read
0x000034E4       BL file_free

pipe_fail_both_fds_read:
0x000034EC       MOV R1 R10
0x000034F0       BL fd_remove
0x000034F8       CMP R1 0
0x000034FC       BEQ pipe_fail_free_pipe_fault
0x00003504       BL file_free

pipe_fail_free_pipe_fault:
0x0000350C       MOV R1 R12
0x00003510       BL pipe_free
0x00003518       LI R1 ERR_FAULT
0x00003520       STW R1 [SP + TF_R1]

0x00003524       B trap_restore

pipe_fail_write_file:
0x0000352C       MOV R12 R8
0x00003530       MOV R1 R9
0x00003534       BL file_free
0x0000353C       MOV R1 R10
0x00003540       BL fd_remove
0x00003548       CMP R1 0
0x0000354C       BEQ pipe_fail_free_pipe_mfile
0x00003554       BL file_free

pipe_fail_free_pipe_mfile:
0x0000355C       MOV R1 R12
0x00003560       BL pipe_free
0x00003568       LI R1 ERR_MFILE
0x00003570       STW R1 [SP + TF_R1]

0x00003574       B trap_restore

pipe_fail_read_fd:
0x0000357C       MOV R12 R8
0x00003580       MOV R1 R10
0x00003584       BL fd_remove
0x0000358C       CMP R1 0
0x00003590       BEQ pipe_fail_free_pipe_nfile
0x00003598       BL file_free

pipe_fail_free_pipe_nfile:
0x000035A0       MOV R1 R12
0x000035A4       BL pipe_free
0x000035AC       LI R1 ERR_NFILE
0x000035B4       STW R1 [SP + TF_R1]

0x000035B8       B trap_restore

pipe_fail_read_file:
0x000035C0       MOV R12 R8
0x000035C4       MOV R1 R9
0x000035C8       BL file_free
0x000035D0       MOV R1 R10          ; освободить inode read end
0x000035D4       BL inode_free
0x000035DC       MOV R1 R12
0x000035E0       BL pipe_free
0x000035E8       LI R1 ERR_MFILE
0x000035F0       STW R1 [SP + TF_R1]

0x000035F4       B trap_restore

pipe_fail_pipe_only:
0x000035FC       MOV R1 R8
0x00003600       BL pipe_free
0x00003608       LI R1 ERR_NFILE
0x00003610       STW R1 [SP + TF_R1]

0x00003614       B trap_restore

pipe_fail_nospc:
0x0000361C       LI R1 ERR_NOSPC
0x00003624       STW R1 [SP + TF_R1]

0x00003628       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x00003630       MOV R1 R9          ; освобождаем file (read end)
0x00003634       BL  file_free
0x0000363C       MOV R1 R8          ; освобождаем pipe
0x00003640       BL  pipe_free
0x00003648       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x00003650       STW R1 [SP + TF_R1]
0x00003654       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x0000365C       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x00003660       BL fd_remove
0x00003668       CMP R1 0
0x0000366C       BEQ skip_file_free_read
0x00003674       BL file_free
skip_file_free_read:
0x0000367C       MOV R1 R9          ; освобождаем file (write end)
0x00003680       BL file_free
0x00003688       MOV R1 R8          ; освобождаем pipe
0x0000368C       BL pipe_free
0x00003694       LI R1 ERR_NFILE
0x0000369C       STW R1 [SP + TF_R1]
0x000036A0       B trap_restore

;===========================================================
; syscall_dup - make another fd for FILE increase refcnt
;
; R1 = old fd
;
; returns:
;   R1 = new fd
;   or R1 = ERR_BADF
;===========================================================

syscall_dup:

0x000036A8       LDW R1 [SP + TF_R1]     ; argument fd

0x000036AC       BL fd_lookup            ; lookup FILE*
0x000036B4       CMP R1 0
0x000036B8       BEQ dup_badfd
0x000036C0       MOV R8 R1               ; keep FILE*

0x000036C4       BL file_get             ; FILE.ref++

0x000036CC       MOV R1 R8
0x000036D0       BL fd_alloc             ; try to allocate new fd

0x000036D8       LI R2 ERR_MFILE
0x000036E0       CMP R1 R2
0x000036E4       BEQ dup_fail_fd

0x000036EC       STW R1 [SP + TF_R1] ;R1 - new fd
0x000036F0       B trap_restore

dup_fail_fd:

0x000036F8       MOV R1 R8
0x000036FC       BL file_put

0x00003704       LI R1 ERR_MFILE     ;R1 -err + rollback
0x0000370C       STW R1 [SP + TF_R1]
0x00003710       B trap_restore

dup_badfd:

0x00003718       LI R1 ERR_BADF      ;R1 -err + file not found
0x00003720       STW R1 [SP + TF_R1]

0x00003724       B trap_restore

;===============================================================
; syscall_gettime
;
; R1 = user pointer to struct timeval
;
; Returns:
;   R1 = 0
;   R1 = ERR_FAULT
;===============================================================

syscall_gettime:

    ;----------------------------------------------------------
    ; Get user pointer
    ;----------------------------------------------------------

0x0000372C       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x00003730       MOV R1 R8
0x00003734       LI  R2 TIMEVAL_SIZE
0x0000373C       LI  R3 1                   ; write access
0x00003744       BL  user_buffer_valid_range

0x0000374C       CMP R1 1
0x00003750       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x00003758       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x00003760   LI R1 CURRENT_TASK
0x00003768   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000376C   LI R1 TASK_SIZE
0x00003774   MUL R3 R4 R1
0x00003778   LI R5 tasks
0x00003780   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x00003784   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x00003788       STW R1 [R6 + TIMEVAL_SEC]
0x0000378C       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x00003790       MOV R1 R8                  ; user destination
0x00003794       LI  R2 TIMEVAL_SIZE        ; size in bytes (8)
0x0000379C       MOV R4 R6                  ; kernel source

0x000037A0       BL copy_to_user

0x000037A8       CMP R1 TIMEVAL_SIZE
0x000037AC       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x000037B4       LI R1 0
0x000037BC       STW R1 [SP + TF_R1]

0x000037C0       B trap_restore

gettime_badptr:

0x000037C8       LI R1 ERR_FAULT
0x000037D0       STW R1 [SP + TF_R1]

0x000037D4       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x000037DC       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x000037E0       LI R2 HEAP_START
0x000037E8       CMP R8 R2
0x000037EC       BLT brk_invalid            ; if new break is below data page, return error

0x000037F4       LI R2 HEAP_END
0x000037FC       CMP R8 R2
0x00003800       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00003808   LI R1 CURRENT_TASK
0x00003810   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003814   LI R1 TASK_SIZE
0x0000381C   MUL R3 R4 R1
0x00003820   LI R5 tasks
0x00003828   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x0000382C   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x00003830       STW R8 [SP + TF_R1]

0x00003834       B trap_restore

brk_invalid:
    ; Return -1
0x0000383C       LI R1 ERR_FAULT
0x00003844       STW R1 [SP + TF_R1]

0x00003848       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x00003850       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00003854   LI R1 CURRENT_TASK
0x0000385C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003860   LI R1 TASK_SIZE
0x00003868   MUL R3 R4 R1
0x0000386C   LI R5 tasks
0x00003874   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x00003878   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x0000387C       ADD R10 R9 R8

    ; Validate it's within the data page
0x00003880       LI R2 HEAP_START
0x00003888       CMP R10 R2
0x0000388C       BLT sbrk_invalid

0x00003894       LI R2 HEAP_END
0x0000389C       CMP R10 R2
0x000038A0       BGT sbrk_invalid

    ; Return old break
0x000038A8       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x000038AC   STW R10 [R5 + TASK_BREAK]

0x000038B0       B trap_restore

sbrk_invalid:
    ; Return -1
0x000038B8       LI R1 ERR_FAULT
0x000038C0       STW R1 [SP + TF_R1]
0x000038C4       B trap_restore

;===============================================================
; clock_gettime
;
; Returns current kernel time.
;
; Out:
;   R1 = seconds
;   R2 = microseconds
;===============================================================
clock_gettime:

0x000038CC       LI  R3 timer_ticks
0x000038D4       LDW R4 [R3]                ; tick counter (1 ms per tick)

    ; seconds = ticks / 1000
0x000038D8       MOV R1 R4
0x000038DC       LI  R5 1000
0x000038E4       DIV R1 R1 R5

    ; usec = (ticks % 1000) * 1000
0x000038E8       MOD R4 R4 R5
0x000038EC       LI  R5 1000
0x000038F4       MUL R2 R4 R5

0x000038F8       RET

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

0x000038FC       PUSH LR

0x00003900       MOV R9 R1              ; file*
0x00003904       MOV R7 R2              ; user buffer
0x00003908       MOV R6 R3              ; requested len

0x0000390C       LDW R9 [R9 + FILE_INODE]
0x00003910       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x00003914       CMP R6 0                ;fast clear from it if len=0
0x00003918       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00003920       PUSH R7
0x00003924       PUSH R6

0x00003928       MOV R1 R7
0x0000392C       MOV R2 R6
0x00003930       LI  R3 1               ; write access
0x00003938       BL user_buffer_valid_range

0x00003940       POP R6
0x00003944       POP R7
0x00003948       CMP R1 1
0x0000394C       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00003954       LDW R4 [R9 + PIPE_COUNT]
0x00003958       CMP R4 0
0x0000395C       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00003964       CMP R6 R4
0x00003968       BLT pipe_user_len

0x00003970       MOV R5 R4
0x00003974       B pipe_have_amount

pipe_user_len:
0x0000397C       MOV R5 R6

pipe_have_amount:
0x00003980       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00003988       CMP R10 R5
0x0000398C       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00003994       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00003998       MOV R12 R9
0x0000399C       ADD R12 R12 PIPE_BUFFER
0x000039A0       ADD R12 R12 R11         ; addr += tail

0x000039A4       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x000039A8       MOV R12 R7
0x000039AC       ADD R12 R12 R10

0x000039B0       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x000039B4       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x000039B8       LI R2 255
0x000039C0       AND R11 R11 R2
0x000039C4       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x000039C8       LDW R12 [R9 + PIPE_COUNT]
0x000039CC       SUB R12 R12 1
0x000039D0       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x000039D4       ADD R10 R10 1
0x000039D8       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x000039E0       MOV R1 R9
0x000039E4       ADD R1 R1 PIPE_WWAIT
0x000039E8       BL waitq_wake_all
0x000039F0       MOV R1 R10          ; read bytes amount
0x000039F4       POP LR
0x000039F8       RET

pipe_read_badptr:
0x000039FC       LI R1 ERR_FAULT
0x00003A04       POP LR
0x00003A08       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00003A0C       MOV R1 R9
0x00003A10       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00003A14       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00003A1C       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00003A24       LDW R4 [R9 + PIPE_COUNT]
0x00003A28       CMP R4 0
0x00003A2C       BNE pipe_read_retry

0x00003A34       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00003A3C       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00003A44       LI R2 0

pipe_loop:
0x00003A4C       LI  R1 MAX_PIPES
0x00003A54       CMP R2 R1
0x00003A58       BGE pipe_alloc_fail

0x00003A60       SHL R3 R2 2

0x00003A64       LI R4 pipe_used
0x00003A6C       ADD R4 R4 R3

0x00003A70       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00003A74       CMP R5 0                ; 0 -empty
0x00003A78       BEQ pipe_found

0x00003A80       ADD R2 R2 1
0x00003A84       B pipe_loop

pipe_found:

0x00003A8C       LI R5 1
0x00003A94       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00003A98       LI R4 PIPE_SIZE
0x00003AA0       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00003AA4       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00003AAC       ADD R1 R1 R6

0x00003AB0       LI R7 0                 ; clean it up
0x00003AB8       STW R7 [R1 + PIPE_HEAD]
0x00003ABC       STW R7 [R1 + PIPE_TAIL]
0x00003AC0       STW R7 [R1 + PIPE_COUNT]
0x00003AC4       STW R7 [R1 + PIPE_RWAIT]
0x00003AC8       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00003ACC       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00003AD0       LI R1 0
0x00003AD8       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00003ADC       LI R2 pipe_pool
0x00003AE4       SUB R3 R1 R2

0x00003AE8       LI R4 PIPE_SIZE
0x00003AF0       DIV R5 R3 R4

0x00003AF4       SHL R5 R5 2
0x00003AF8       LI R6 pipe_used
0x00003B00       ADD R6 R6 R5

0x00003B04       LI R7 0
0x00003B0C       STW R7 [R6]

0x00003B10       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00003B14       PUSH LR

0x00003B18       MOV R9 R1
0x00003B1C       MOV R7 R2
0x00003B20       MOV R6 R3

0x00003B24       LDW R9 [R9 + FILE_INODE]
0x00003B28       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00003B2C       PUSH R7
0x00003B30       PUSH R6

0x00003B34       MOV R1 R7
0x00003B38       MOV R2 R6
0x00003B3C       LI  R3 0           ; READ access
0x00003B44       BL user_buffer_valid_range

0x00003B4C       POP R6
0x00003B50       POP R7

0x00003B54       CMP R1 1
0x00003B58       BNE pipe_write_badptr

0x00003B60       LI R10 0               ; bytes written
pipe_write_retry:
0x00003B68       CMP R10 R6
0x00003B6C       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00003B74       LDW R11 [R9 + PIPE_COUNT]
0x00003B78       LI R2 256
0x00003B80       CMP R11 R2
0x00003B84       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00003B8C       LDW R12 [R9 + PIPE_HEAD]

0x00003B90       MOV R4 R7
0x00003B94       ADD R4 R4 R10
0x00003B98       LDB R5 [R4]     ; read byte from user buff addr

0x00003B9C       MOV R4 R9
0x00003BA0       ADD R4 R4 PIPE_BUFFER
0x00003BA4       ADD R4 R4 R12
0x00003BA8       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00003BAC       ADD R12 R12 1
0x00003BB0       LI R2 255
0x00003BB8       AND R12 R12 R2
0x00003BBC       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00003BC0       LDW R4 [R9 + PIPE_COUNT]
0x00003BC4       ADD R4 R4 1
0x00003BC8       STW R4 [R9 + PIPE_COUNT]

; written++
0x00003BCC       ADD R10 R10 1
0x00003BD0       B pipe_write_retry

pipe_write_done:
; wake readers
0x00003BD8       MOV R1 R9
0x00003BDC       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x00003BE0       BL waitq_wake_all
0x00003BE8       MOV R1 R10      ;written bytes
0x00003BEC       POP LR
0x00003BF0       RET

pipe_write_badptr:
0x00003BF4       LI R1 ERR_FAULT
0x00003BFC       POP LR
0x00003C00       RET

pipe_write_empty:
0x00003C04       LI R1 0
0x00003C0C       POP LR
0x00003C10       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00003C14       MOV R1 R9
0x00003C18       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x00003C1C       LI R2 WAIT_PIPE_WRITE
0x00003C24       BL waitq_prepare_sleep
    ; race check
0x00003C2C       LDW R4 [R9 + PIPE_COUNT]
0x00003C30       LI R2 256
0x00003C38       CMP R4 R2
0x00003C3C       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00003C44       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00003C4C       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x00003C54       CMP R1 3
0x00003C58       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x00003C60       CMP R1 MAX_FDS
0x00003C64       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x00003C6C       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x00003C70   LI R1 CURRENT_TASK
0x00003C78   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00003C7C   LI R1 TASK_SIZE
0x00003C84   MUL R3 R4 R1
0x00003C88   LI R4 tasks
0x00003C90   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x00003C94   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x00003C98       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x00003C9C       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x00003CA0       LDW R1 [R6]                 ; R1 = file* из таблицы
0x00003CA4       CMP R1 0
0x00003CA8       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x00003CB0       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x00003CB4       RET

fd_lookup_invalid:
0x00003CB8       LI R1 0
0x00003CC0       LI R2 0
0x00003CC8       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x00003CCC       PUSH LR
0x00003CD0       BL  fd_lookup
0x00003CD8       CMP R1 0
0x00003CDC       BEQ fd_remove_invalid

0x00003CE4       MOV R8 R1          ; сохраняем file*
0x00003CE8       LI R3 0
0x00003CF0       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x00003CF4       MOV R1 R8          ; file*
0x00003CF8       POP LR
0x00003CFC       RET

fd_remove_invalid:
0x00003D00       LI R1 0
0x00003D08       POP LR
0x00003D0C       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003D10       LDW R1 [SP + TF_R1]
0x00003D14       LDW R2 [SP + TF_R2]
0x00003D18       LDW R3 [SP + TF_R3]

0x00003D1C       BL vfs_read

0x00003D24       STW R1 [SP + TF_R1]
0x00003D28       B trap_restore

; to comply with vfs interface
devfs_open:
0x00003D30       LI R1 0
0x00003D38       RET
devfs_close:
0x00003D3C       LI R1 0
0x00003D44       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00003D48       PUSH LR
0x00003D4C       PUSH R8
0x00003D50       PUSH R9
0x00003D54       PUSH R10
0x00003D58       PUSH R11
0x00003D5C       PUSH R12
0x00003D60       MOV R9 R1
0x00003D64       MOV R7 R2
0x00003D68       MOV R6 R3
0x00003D6C       LI R8 0                    ; total bytes collected
0x00003D74       LDW R9 [R9 + FILE_INODE]
0x00003D78       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00003D7C       CMP R6 0
0x00003D80       BEQ read_done

0x00003D88       PUSH R7
0x00003D8C       PUSH R6
0x00003D90       PUSH R9
0x00003D94       MOV R1 R7
0x00003D98       MOV R2 R6
0x00003D9C       LI R3 1                ; write access for destination buffer
0x00003DA4       BL user_buffer_valid_range
0x00003DAC       POP R9
0x00003DB0       POP R6
0x00003DB4       POP R7
0x00003DB8       CMP R1 1
0x00003DBC       BNE con_read_fault

read_wait_uart_rx:
0x00003DC4       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00003DC8       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00003DCC       AND R5 R5 1                 ; bit 0 = RX_READY
0x00003DD0       CMP R5 0
0x00003DD4       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00003DDC   LI R1 CURRENT_TASK
0x00003DE4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003DE8   LI R1 TASK_SIZE
0x00003DF0   MUL R3 R4 R1
0x00003DF4   LI R5 tasks
0x00003DFC   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003E00   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003E04       MOV R2 R6
0x00003E08       MOV R3 R9
0x00003E0C       PUSH R6
0x00003E10       PUSH R7
0x00003E14       PUSH R8
0x00003E18       PUSH R9
0x00003E1C       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x00003E24       POP R9
0x00003E28       POP R8
0x00003E2C       POP R7
0x00003E30       POP R6

0x00003E34       CMP R1 0
0x00003E38       BEQ read_wait_uart_rx

0x00003E40       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x00003E44   LI R1 CURRENT_TASK
0x00003E4C   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x00003E50   LI R1 TASK_SIZE
0x00003E58   MUL R3 R5 R1
0x00003E5C   LI R4 tasks
0x00003E64   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x00003E68   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with newline before copy_to_user
    ; clobbers temporary registers.
0x00003E6C       LI R11 0
0x00003E74       SUB R5 R10 1
0x00003E78       ADD R5 R4 R5
0x00003E7C       LDB R5 [R5]
0x00003E80       CMP R5 10
0x00003E84       BNE read_chunk_not_newline
0x00003E8C       LI R11 1

read_chunk_not_newline:
0x00003E94       PUSH R6
0x00003E98       PUSH R7
0x00003E9C       PUSH R8
0x00003EA0       PUSH R9
0x00003EA4       PUSH R10
0x00003EA8       PUSH R11
0x00003EAC       MOV R1 R7              ; user destination
0x00003EB0       MOV R2 R10
0x00003EB4       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00003EBC       POP R11
0x00003EC0       POP R10
0x00003EC4       POP R9
0x00003EC8       POP R8
0x00003ECC       POP R7
0x00003ED0       POP R6

0x00003ED4       ADD R7 R7 R10
0x00003ED8       ADD R8 R8 R10
0x00003EDC       SUB R6 R6 R10

0x00003EE0       CMP R11 1
0x00003EE4       BEQ read_complete
0x00003EEC       CMP R6 0
0x00003EF0       BGT read_wait_uart_rx

read_complete:
0x00003EF8       MOV R1 R8
0x00003EFC       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00003F04       LI R1 uart_rx_waitq
0x00003F0C       LI R2 WAIT_UART_RX
0x00003F14       BL waitq_prepare_sleep

0x00003F1C       LDW R4 [R9 + UARTDEV_MMIO]
0x00003F20       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x00003F24       AND R10 R10 1
0x00003F28       CMP R10 0
0x00003F2C       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x00003F34       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x00003F3C       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00003F44       LI R1 uart_rx_waitq
0x00003F4C       BL waitq_cancel_sleep_current

0x00003F54       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x00003F5C       LI R1 0
0x00003F64       B read_return

con_read_fault:
0x00003F6C       LI R1 ERR_FAULT

read_return:
0x00003F74       POP R12
0x00003F78       POP R11
0x00003F7C       POP R10
0x00003F80       POP R9
0x00003F84       POP R8
0x00003F88       POP LR
0x00003F8C       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00003F90       LDW R1 [SP + TF_R1]
0x00003F94       LDW R2 [SP + TF_R2]
0x00003F98       LDW R3 [SP + TF_R3]

0x00003F9C       BL vfs_write

0x00003FA4       STW R1 [SP + TF_R1]
0x00003FA8       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00003FB0       PUSH LR
0x00003FB4       MOV R9 R1
0x00003FB8       MOV R7 R2
0x00003FBC       MOV R6 R3
0x00003FC0       LDW R9 [R9 + FILE_INODE]
0x00003FC4       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00003FC8       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00003FD0       CMP R6 0
0x00003FD4       BEQ write_done             ;0 bytes

0x00003FDC       LI R2 KBUFFER_SIZE
0x00003FE4       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00003FE8       BLT write_chunk_small
0x00003FF0       LI R2 KBUFFER_SIZE

0x00003FF8       B write_chunk

write_chunk_small:
0x00004000       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x00004004       PUSH R7
0x00004008       PUSH R6
0x0000400C       PUSH R9
0x00004010       PUSH R8
0x00004014       MOV R1 R7
0x00004018       MOV R2 R2
0x0000401C       LI R3 0                ; read access for source buffer
0x00004024       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x0000402C       POP R8
0x00004030       POP R9
0x00004034       POP R6
0x00004038       POP R7
0x0000403C       CMP R1 1
0x00004040       BNE driver_bad_pointer

0x00004048       PUSH R7
0x0000404C       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x00004050   LI R1 CURRENT_TASK
0x00004058   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000405C   LI R1 TASK_SIZE
0x00004064   MUL R3 R4 R1
0x00004068   LI R5 tasks
0x00004070   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00004074   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00004078       MOV R1 R7
0x0000407C       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00004084       MOV R10 R1             ; bytes copied
0x00004088       POP R6
0x0000408C       POP R7

0x00004090       PUSH R7
0x00004094       PUSH R9
0x00004098       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x0000409C       LDW R1 [R9 + UARTDEV_MMIO]
0x000040A0       LDW R2 [R1 + 4]
0x000040A4       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x000040A8       CMP R2 0
0x000040AC       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x000040B4   LI R1 CURRENT_TASK
0x000040BC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000040C0   LI R1 TASK_SIZE
0x000040C8   MUL R3 R4 R1
0x000040CC   LI R5 tasks
0x000040D4   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x000040D8   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x000040DC       MOV R2 R10
0x000040E0       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x000040E4       BL device_write
0x000040EC       POP R6
0x000040F0       POP R9
0x000040F4       POP R7

0x000040F8       CMP R1 0        ;nothing is written - go again
0x000040FC       BEQ write_loop

0x00004104       ADD R8 R8 R1     ;update ptrs
0x00004108       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x0000410C       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x00004110       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00004118       LI R1 uart_tx_waitq
0x00004120       LI R2 WAIT_UART_TX
0x00004128       BL waitq_prepare_sleep

0x00004130       LDW R1 [R9 + UARTDEV_MMIO]
0x00004134       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00004138       AND R2 R2 2
0x0000413C       CMP R2 0
0x00004140       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00004148       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x00004150       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00004158       LI R1 uart_tx_waitq
0x00004160       BL waitq_cancel_sleep_current

0x00004168       B write_wait_uart_tx

write_done:
0x00004170       MOV R1 R8
0x00004174       POP LR
0x00004178       RET

driver_bad_pointer:
0x0000417C       LI R1 ERR_FAULT
0x00004184       POP LR
0x00004188       RET

bad_fd:
0x0000418C       LI R1 ERR_BADF
0x00004194       STW R1 [SP + TF_R1]

0x00004198       B trap_restore

bad_pointer:
0x000041A0       LI R1 ERR_FAULT
0x000041A8       STW R1 [SP + TF_R1]

0x000041AC       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x000041B4       LDW R4 [R1 + FILE_INODE]
0x000041B8       LDW R4 [R4 + INODE_OPS]
0x000041BC       LDW R4 [R4 + FSOPS_READ]
0x000041C0       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x000041C4       LDW R4 [R1 + FILE_INODE]
0x000041C8       LDW R4 [R4 + INODE_OPS]
0x000041CC       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x000041D0       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000041D4       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x000041DC       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x000041E4       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000041E8       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x000041F0       CMP R5 R2                   ; have we read enough bytes?
0x000041F4       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x000041FC       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00004200       AND R6 R6 1                 ; bit 0 = RX_READY
0x00004204       CMP R6 0
0x00004208       BEQ dr_done                 ; no more buffered input available

0x00004210       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x00004214       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00004218       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x0000421C       CMP R7 10
0x00004220       BEQ dr_done

0x00004228       B dr_loop

dr_done:
0x00004230       MOV R1 R5                   ; return number of bytes actually read
0x00004234       RET

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
0x00004238       PUSH LR

    ; mutex for write to console lock
0x0000423C       PUSH R1
0x00004240       PUSH R2
0x00004244       PUSH R3

    ; Lock console mutex
0x00004248       BL console_lock

    ; Write to UART
0x00004250       POP R3
0x00004254       POP R2
0x00004258       POP R1


0x0000425C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00004260       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x00004268       CMP R5 R2                   ; have we written all bytes?
0x0000426C       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00004274       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00004278       AND R6 R6 2                 ; bit 1 = TX_READY
0x0000427C       CMP R6 0
0x00004280       BEQ dcw_done

0x00004288       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x0000428C       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00004290       ADD R5 R5 1
0x00004294       B dcw_loop

dcw_done:
0x0000429C       MOV R1 R5                   ; return number of bytes written


 ; Unlock console mutex for exclusive write to uart device
0x000042A0       PUSH R1
0x000042A4       BL console_unlock
0x000042AC       POP R1


0x000042B0       POP LR
0x000042B4       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x000042B8       LI R1 0
0x000042C0       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x000042C4       PUSH LR
0x000042C8       MOV R6 R3
0x000042CC       CMP R6 0
0x000042D0       BEQ null_write_done

0x000042D8       PUSH R6
0x000042DC       MOV R1 R2
0x000042E0       MOV R2 R6
0x000042E4       LI R3 0                    ; read access from user source
0x000042EC       BL user_buffer_valid_range
0x000042F4       POP R6
0x000042F8       CMP R1 1
0x000042FC       BNE null_write_badptr

null_write_done:
0x00004304       MOV R1 R6
0x00004308       POP LR
0x0000430C       RET

null_write_badptr:
0x00004310       LI R1 ERR_FAULT
0x00004318       POP LR
0x0000431C       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================
0x00004320       PUSH R5
0x00004324       PUSH R6
0x00004328       PUSH R8

0x0000432C       CMP R1 0
0x00004330       BLT fd_invalid
0x00004338       CMP R1 MAX_FDS
0x0000433C       BGE fd_invalid

0x00004344       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x00004348   LI R1 CURRENT_TASK
0x00004350   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00004354   LI R1 TASK_SIZE
0x0000435C   MUL R3 R4 R1
0x00004360   LI R4 tasks
0x00004368   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x0000436C   LDW R4 [R4 + TASK_FD_TABLE]

0x00004370       SHL R5 R8 2
0x00004374       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x00004378       LDW R1 [R4]                 ; R1 = file ptr
0x0000437C       LDW R6 [R1 + FILE_FLAGS]
0x00004380       AND R6 R6 R2
0x00004384       CMP R6 R2
0x00004388       BNE fd_invalid

0x00004390       POP R8
0x00004394       POP R6
0x00004398       POP R5
0x0000439C       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x000043A0       POP R8
0x000043A4       POP R6
0x000043A8       POP R5

0x000043AC       LI R1 0
0x000043B4       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x000043B8       PUSH LR
0x000043BC       MOV R7 R2
0x000043C0       MOV R10 R3

0x000043C4       LI R2 FD_FLAG_READ
0x000043CC       BL fetch_fd_entry   ; macro inside destroys R6

0x000043D4       CMP R1 0
0x000043D8       BEQ vfs_read_badfd

0x000043E0       MOV R9 R1
0x000043E4       MOV R1 R9
0x000043E8       MOV R2 R7
0x000043EC       MOV R3 R10
0x000043F0       BL file_read
0x000043F8       POP LR
0x000043FC       RET

vfs_read_badfd:
0x00004400       LI R1 ERR_BADF
0x00004408       POP LR
0x0000440C       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x00004410       PUSH LR
0x00004414       MOV R7 R2
0x00004418       MOV R10 R3

0x0000441C       LI R2 FD_FLAG_WRITE
0x00004424       BL fetch_fd_entry   ;macro inside desroys R6 (fixed)

0x0000442C       CMP R1 0
0x00004430       BEQ vfs_write_badfd

0x00004438       MOV R9 R1
0x0000443C       MOV R1 R9           ; R1 - file* acc to fd
0x00004440       MOV R2 R7
0x00004444       MOV R3 R10
0x00004448       BL file_write
0x00004450       POP LR
0x00004454       RET

vfs_write_badfd:
0x00004458       LI R1 ERR_BADF
0x00004460       POP LR
0x00004464       RET






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
0x00004468       PUSH R5
0x0000446C       PUSH R6
0x00004470       PUSH R7
0x00004474       PUSH R8
0x00004478       PUSH R9
0x0000447C       PUSH R10
0x00004480       PUSH R11
0x00004484       PUSH R12

0x00004488       LI R4 0
0x00004490       CMP R2 R4
0x00004494       BEQ uv_valid

0x0000449C       LI R4 USER_BASE
0x000044A4       CMP R1 R4
0x000044A8       BLT uv_invalid

0x000044B0       LI R4 USER_LIMIT
0x000044B8       ADD R5 R1 R2
0x000044BC       SUB R5 R5 1
0x000044C0       CMP R5 R1
0x000044C4       BLT uv_invalid
0x000044CC       CMP R5 R4
0x000044D0       BGT uv_invalid
0x000044D8       MOV R11 R1              ; save start address; task macros clobber R1
0x000044DC       MOV R12 R5              ; save end address for page calculation
0x000044E0       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x000044E4   LI R1 CURRENT_TASK
0x000044EC   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x000044F0   LI R1 TASK_SIZE
0x000044F8   MUL R3 R6 R1
0x000044FC   LI R6 tasks
0x00004504   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00004508   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x0000450C       CMP R6 0
0x00004510       BEQ uv_invalid

uv_check_pages:
0x00004518       SHR R7 R11 12
0x0000451C       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00004520       CMP R7 R8
0x00004524       BGT uv_valid
0x0000452C       SHL R9 R7 2
0x00004530       ADD R9 R9 R6
0x00004534       LDW R10 [R9]
0x00004538       AND R5 R10 PTE_P
0x0000453C       CMP R5 0
0x00004540       BEQ uv_invalid
0x00004548       AND R5 R10 PTE_U
0x0000454C       CMP R5 0
0x00004550       BEQ uv_invalid
0x00004558       CMP R4 0
0x0000455C       BEQ uv_check_read
0x00004564       AND R5 R10 PTE_W
0x00004568       CMP R5 0
0x0000456C       BEQ uv_invalid
0x00004574       B uv_next

uv_check_read:
0x0000457C       AND R5 R10 PTE_R
0x00004580       CMP R5 0
0x00004584       BEQ uv_invalid

uv_next:
0x0000458C       ADD R7 R7 1
0x00004590       B uv_loop

uv_valid:
0x00004598       LI R1 1
0x000045A0       POP R12
0x000045A4       POP R11
0x000045A8       POP R10
0x000045AC       POP R9
0x000045B0       POP R8
0x000045B4       POP R7
0x000045B8       POP R6
0x000045BC       POP R5
0x000045C0       RET

uv_invalid:
0x000045C4       LI R1 0

0x000045CC       POP R12
0x000045D0       POP R11
0x000045D4       POP R10
0x000045D8       POP R9
0x000045DC       POP R8
0x000045E0       POP R7
0x000045E4       POP R6
0x000045E8       POP R5
0x000045EC       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x000045F0       PUSH R5
0x000045F4       PUSH R6
0x000045F8       PUSH R7
0x000045FC       LI R5 0
cfu_head:
0x00004604       CMP R2 0
0x00004608       BEQ cfu_done
0x00004610       OR R6 R1 R4
0x00004614       AND R6 R6 3
0x00004618       CMP R6 0
0x0000461C       BEQ cfu_word
0x00004624       LDB R7 [R1]
0x00004628       STB R7 [R4]
0x0000462C       ADD R1 R1 1
0x00004630       ADD R4 R4 1
0x00004634       ADD R5 R5 1
0x00004638       SUB R2 R2 1
0x0000463C       B cfu_head
cfu_word:
0x00004644       CMP R2 4
0x00004648       BLT cfu_tail
0x00004650       LDW R7 [R1]
0x00004654       STW R7 [R4]
0x00004658       ADD R1 R1 4
0x0000465C       ADD R4 R4 4
0x00004660       ADD R5 R5 4
0x00004664       SUB R2 R2 4
0x00004668       B cfu_word
cfu_tail:
0x00004670       CMP R2 0
0x00004674       BEQ cfu_done
0x0000467C       LDB R7 [R1]
0x00004680       STB R7 [R4]
0x00004684       ADD R1 R1 1
0x00004688       ADD R4 R4 1
0x0000468C       ADD R5 R5 1
0x00004690       SUB R2 R2 1
0x00004694       B cfu_tail
cfu_done:
0x0000469C       MOV R1 R5
0x000046A0       POP R7
0x000046A4       POP R6
0x000046A8       POP R5
0x000046AC       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x000046B0       PUSH R5
0x000046B4       PUSH R6
0x000046B8       PUSH R7
0x000046BC       LI R5 0
ctu_head:
0x000046C4       CMP R2 0
0x000046C8       BEQ ctu_done
0x000046D0       OR R6 R1 R4
0x000046D4       AND R6 R6 3
0x000046D8       CMP R6 0
0x000046DC       BEQ ctu_word
0x000046E4       LDB R7 [R4]
0x000046E8       STB R7 [R1]
0x000046EC       ADD R1 R1 1
0x000046F0       ADD R4 R4 1
0x000046F4       ADD R5 R5 1
0x000046F8       SUB R2 R2 1
0x000046FC       B ctu_head
ctu_word:
0x00004704       CMP R2 4
0x00004708       BLT ctu_tail
0x00004710       LDW R7 [R4]
0x00004714       STW R7 [R1]
0x00004718       ADD R1 R1 4
0x0000471C       ADD R4 R4 4
0x00004720       ADD R5 R5 4
0x00004724       SUB R2 R2 4
0x00004728       B ctu_word
ctu_tail:
0x00004730       CMP R2 0
0x00004734       BEQ ctu_done
0x0000473C       LDB R7 [R4]
0x00004740       STB R7 [R1]
0x00004744       ADD R1 R1 1
0x00004748       ADD R4 R4 1
0x0000474C       ADD R5 R5 1
0x00004750       SUB R2 R2 1
0x00004754       B ctu_tail
ctu_done:
0x0000475C       MOV R1 R5
0x00004760       POP R7
0x00004764       POP R6
0x00004768       POP R5
0x0000476C       RET

handle_debug:
    ; Debug trap - just return
0x00004770       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00004778       CSRR R1 STVAL

0x0000477C       CMP R1 0
0x00004780       BEQ handle_timer_irq

0x00004788       CMP R1 1
0x0000478C       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00004794       LI R2 0x00102000
0x0000479C       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x000047A0       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x000047A8       LI R2 0x00102000
0x000047B0       LI R3 0
0x000047B8       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x000047BC       LI R1 timer_ticks
0x000047C4       LDW R2 [R1]
0x000047C8       ADD R2 R2 1
0x000047CC       STW R2 [R1]

    ;================================================================
    ; Wake sleeping tasks whose time has expired
    ;================================================================

0x000047D0       LI R1 sleep_waitq
0x000047D8       LDW R8 [R1]                ; R8 = current sleep_waitq mask
0x000047DC       LI R9 0                    ; R9 = tasks to wake bitmask
0x000047E4       LI R3 0                    ; task index

timer_wake_scan:
0x000047EC       CMP R3 MAX_TASKS
0x000047F0       BGE timer_wake_scan_done

    ; Check if this task is in the sleep wait queue
0x000047F8       LI R6 1
0x00004800       SHL R6 R6 R3               ; bit for this task
0x00004804       AND R7 R8 R6
0x00004808       CMP R7 0
0x0000480C       BEQ timer_wake_next        ; not in sleep queue

    ; Task is sleeping, check if it's time to wake
; macro: GET_TASK_PTR R5, R3
0x00004814   LI R1 TASK_SIZE
0x0000481C   MUL R3 R3 R1
0x00004820   LI R5 tasks
0x00004828   ADD R5 R5 R3
; macro: TASK_GET_WAKE_TIME R7, R5
0x0000482C   LDW R7 [R5 + TASK_WAKE_TIME]
0x00004830       CMP R2 R7                  ; current time >= wake time?
0x00004834       BLT timer_wake_next

    ; Mark this task for wakeup
0x0000483C       OR R9 R9 R6                 ; add to wake bitmask bitwize

timer_wake_next:
0x00004840       ADD R3 R3 1
0x00004844       B timer_wake_scan

timer_wake_scan_done:
    ; If no tasks to wake, skip
0x0000484C       CMP R9 0
0x00004850       BEQ timer_no_wake

    ; Wake the expired tasks using our new function
0x00004858       LI R1 sleep_waitq
0x00004860       MOV R2 R9
0x00004864       BL waitq_wake_bitmask

timer_no_wake:

    ; Yield the CPU (reschedule and switch tasks)
0x0000486C       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00004874       LI R2 0x00102000
0x0000487C       LI R3 1
0x00004884       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00004888       LI R1 uart_rx_waitq
0x00004890       BL waitq_wake_all
0x00004898       LI R1 uart_tx_waitq
0x000048A0       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x000048A8       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x000048B0       POP R1                  ; stval, informational only
0x000048B4       POP R1                  ; scause, informational only
0x000048B8       POP R1
0x000048BC       CSRW SSTATUS R1
0x000048C0       POP R1
0x000048C4       CSRW SFLAGS R1
0x000048C8       POP R1
0x000048CC       CSRW SEPC R1
0x000048D0       POP R1                  ; interrupted task SP
0x000048D4       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x000048D8       POP R15
0x000048DC       POP R14
0x000048E0       POP R12
0x000048E4       POP R11
0x000048E8       POP R10
0x000048EC       POP R9
0x000048F0       POP R8
0x000048F4       POP R7
0x000048F8       POP R6
0x000048FC       POP R5
0x00004900       POP R4
0x00004904       POP R3
0x00004908       POP R2
0x0000490C       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00004910       CSRRW SP SSCRATCH SP
0x00004914       SRET


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
.EQU SYS_DUP,      9
.EQU SYS_GETTIME,  10      ; NEW: get time of day - returns seconds since epoch
.EQU SYS_BRK,      11      ; NEW: change program break - memory allocation
.EQU SYS_SBRK,     12      ; NEW: increment program break - memory allocation
.EQU SYS_EXECVE,   13      ; NEW: execute a new program
.EQU SYS_FORK,     14      ; NEW: clone the current task
.EQU SYS_SLEEP,     15      ; sleep for specified milliseconds
.EQU SYS_WAITPID,   16      ; wait for child process to change state
.EQU SYS_COUNT,     17      ; update count


;=============================================================
; Task States
;=============================================================

.EQU TASK_DEAD,        0    ; not runnable, can be recycled for new task
.EQU TASK_READY,       1    ; ready to run
.EQU TASK_RUNNING,     2    ; currently running
.EQU TASK_BLOCKED_IO,  3    ; blocked on I/O operation
.EQU TASK_SLEEPING,    4    ; sleeping/waiting
.EQU TASK_ZOMBIE,      5    ; terminated but not yet reaped
.EQU TASK_WAIT_MUTEX,  6    ; waiting for mutex
;=============================================================
; Task wait reasons
;=============================================================

.EQU WAIT_NONE,        0
.EQU WAIT_UART_RX,     1
.EQU WAIT_UART_TX,     2
.EQU WAIT_PIPE_READ,   3
.EQU WAIT_PIPE_WRITE,  4
.EQU WAIT_SLEEP,       5    ; sleeping on timer
.EQU WAIT_CHILD,       6    ; waiting for child to exit
.EQU WAIT_MUTEX,       7    ; wait for mutex
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
.EQU TASK_DATA_PAGE, 44       ; pointer to this task's data page (user heap, exec/args, stack scratch)
.EQU TASK_CODE_PAGE, 48       ; physical page backing the current execve-loaded user image
    ; TASK_CODE_PAGE tracks the physical page mapped at USER_CODE_VA.
    ; When execve replaces a process image, the new page is allocated,
    ; mapped at USER_CODE_VA, and stored here. The previous page is freed.
.EQU TASK_USTACK_PAGE, 52     ; physical page backing fixed USER_STACK_VA
.EQU TASK_KSTACK_PAGE, 56     ; identity-mapped physical kernel stack page
.EQU TASK_PPID,        60     ; parent process ID for execve / inherited by children
.EQU TASK_BREAK,       64     ; current program break ptr
.EQU TASK_WAKE_TIME,  68     ; absolute time when sleep expires
.EQU TASK_EXIT_CODE,  72     ; exit code of terminated task
.EQU TASK_WAIT_CHILD, 76     ; PID of child being waited for
.EQU TASK_SIZE,       80     ; current task struc size



; =============================================================
; important kernel data structures and constants
; =============================================================

.ORG 0x7000

CURRENT_TASK:
    .WORD 0
TIMER_TICKS:
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

;==============================================================
; File objects and console device
;==============================================================

file_stdin:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD FD_FLAG_READ       ; FILE_FLAGS

file_stdout:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD FD_FLAG_WRITE      ; FILE_FLAGS

file_stderr:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD FD_FLAG_WRITE      ; FILE_FLAGS

console_inode:
    .WORD devfs_ops          ; INODE_OPS
    .WORD con_device         ; INODE_PRIVATE
    .WORD INODE_CHAR         ; INODE_TYPE
    .WORD 0                  ; size
    .WORD 1                  ; refcnt

devfs_ops:
    .WORD devfs_open
    .WORD devfs_read
    .WORD devfs_write
    .WORD devfs_close
    .WORD 0
    .WORD devfs_lookup
    .WORD 0
    .WORD 0
    .WORD 0
    .WORD 0

; special con uart related
;con_ops:
;    .WORD con_read
;    .WORD con_write

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
    .WORD devfs_ops
    .WORD con_device

dev_null:
    .WORD dev_null_name
    .WORD devfs_ops
    .WORD null_device

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
; Wait queues for: UART console device / sleeping / waitpid
;==============================================================

; Separate queues are used for separate blocking conditions. A single UART
; device can wake readers when RX data arrives and writers when TX becomes
; ready, so it owns one queue for each condition.
uart_rx_waitq:
    .WORD 0                    ; WQ_MASK: tasks waiting for RX_READY

uart_tx_waitq:
    .WORD 0                    ; WQ_MASK: tasks waiting for TX_READY

; Wait queue for sleeping tasks (woken by timer interrupt)
sleep_waitq:
    .WORD 0                    ; WQ_MASK: tasks sleeping on timer

; Wait queue for parent tasks waiting for children to exit
child_waitq:
    .WORD 0                    ; WQ_MASK: parents waiting for children

; ==================================================
; VFS ops table struc
; ==================================================
; for TARFS in RO
.EQU FSOPS_OPEN,       0
.EQU FSOPS_READ,       4
.EQU FSOPS_WRITE,      8
.EQU FSOPS_CLOSE,     12
.EQU FSOPS_READDIR,   16
.EQU FSOPS_LOOKUP,    20
; for R/W ops
.EQU FSOPS_CREATE,    24
.EQU FSOPS_UNLINK,    28
.EQU FSOPS_MKDIR,     32
.EQU FSOPS_RMDIR,     36

.EQU FSOPS_SIZE,      40

;VFS inst for tarfs
tarfs_ops:
    .WORD tarfs_open
    .WORD tarfs_read
    .WORD tarfs_write
    .WORD tarfs_close
    .WORD tarfs_readdir
    .WORD tarfs_lookup
    .WORD 0 ;to do
    .WORD 0
    .WORD 0
    .WORD 0

;VFS inode inst for tarfs
tarfs_inode:
    .WORD tarfs_ops
    .WORD tar_index





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


tarfs_open:
0x00007BE7       LI R1 0
0x00007BEF       RET

tarfs_close:
0x00007BF3       LI R1 0
0x00007BFB       RET
; --------------------------------------------------
; tarfs_lookup - lookup a file in the tar index by name, for open and read operations
;
; in R1 = pathname input (e.g. "/file.txt")
;
; returns:
;   ;R1 = new inode ptr inited for file found in lookup
;   ;R1 = 0 if not found
; --------------------------------------------------

tarfs_lookup:

0x00007BFF       PUSH LR
0x00007C03       PUSH R8
0x00007C07       PUSH R9
0x00007C0B       PUSH R10

0x00007C0F       MOV R8 R1              ; pathname
0x00007C13       LDB R2 [R8]
0x00007C17       LI R3 47               ; accept normal absolute paths: "/etc/motd"
0x00007C1F       CMP R2 R3
0x00007C23       BNE lookup_path_ready
0x00007C2B       ADD R8 R8 1

lookup_path_ready:

0x00007C2F       LI R9 0                ; index

0x00007C37       LI R10 tar_count
0x00007C3F       LDW R10 [R10]

tar_lookup_loop:

0x00007C43       CMP R9 R10
0x00007C47       BGE tar_lookup_not_found

    ; entry address

0x00007C4F       LI R1 tar_index

0x00007C57       LI R2 TAR_IDX_SIZEOF
0x00007C5F       MUL R3 R9 R2
0x00007C63       ADD R1 R1 R3            ;

    ; compare names

0x00007C67       MOV R2 R8

0x00007C6B       LDW R1 [R1 + TAR_IDX_NAME]

0x00007C6F       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x00007C77       CMP R1 1
0x00007C7B       BEQ tar_lookup_found

0x00007C83       ADD R9 R9 1
0x00007C87       B tar_lookup_loop

tar_lookup_found:

0x00007C8F       LI R1 tar_index
0x00007C97       LI R2 TAR_IDX_SIZEOF
0x00007C9F       MUL R3 R9 R2
0x00007CA3       ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

0x00007CA7       BL inode_alloc
0x00007CAF       CMP R1 0
0x00007CB3       BEQ tar_lookup_not_found
0x00007CBB       MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

0x00007CBF       MOV R1 R10              ; inode
0x00007CC3       LI  R2 tarfs_ops        ; ops table
0x00007CCB       MOV R3 R11              ; private = tar entry
0x00007CCF       LI  R4 INODE_REG        ; FILE type
0x00007CD7       LDW R5 [R11 + TAR_IDX_SIZE] ;file size
0x00007CDB       BL inode_init

0x00007CE3       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x00007CE7       POP R10
0x00007CEB       POP R9
0x00007CEF       POP R8
0x00007CF3       POP LR
0x00007CF7       RET

tar_lookup_not_found:

0x00007CFB       LI R1 0             ; R1 = NULL

0x00007D03       POP R10
0x00007D07       POP R9
0x00007D0B       POP R8
0x00007D0F       POP LR
0x00007D13       RET


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

0x00007D17       PUSH LR
0x00007D1B       PUSH R8
0x00007D1F       PUSH R9
0x00007D23       PUSH R10
0x00007D27       PUSH R11
0x00007D2B       PUSH R12

0x00007D2F       MOV R8 R1                  ; current tar header
0x00007D33       LI R11 tar_limit
0x00007D3B       ADD R2 R1 R2
0x00007D3F       STW R2 [R11]               ; exclusive end of archive

0x00007D43       LI R9 tar_index            ; current index entry

0x00007D4B       LI R10 0                   ; file count

tar_scan_loop:

0x00007D53       CMP R10 MAX_TAR_FILES
0x00007D57       BGE tar_done                ; check before writing the next index entry

0x00007D5F       LI R11 tar_limit
0x00007D67       LDW R11 [R11]
0x00007D6B       LI R12 TAR_HEADER_SIZE
0x00007D73       ADD R12 R8 R12
0x00007D77       CMP R12 R11
0x00007D7B       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x00007D83       LDB R11 [R8 + TAR_NAME_OFF]

0x00007D87       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x00007D8B       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x00007D93       MOV R11 R8

0x00007D97       ADD R11 R11 TAR_NAME_OFF

0x00007D9B       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x00007D9F       MOV R1 R8
0x00007DA3       ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

0x00007DA7       BL tar_parse_octal         ; parse octal size from tar header field to binary integer

0x00007DAF       MOV R12 R1                 ; save file resulted binary size

0x00007DB3       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00007DB7       MOV R11 R8
0x00007DBB       LI R2 TAR_HEADER_SIZE
0x00007DC3       ADD R11 R11 R2

0x00007DC7       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00007DCB       LI R2 TAR_TYPE_OFF
0x00007DD3       ADD R2 R8 R2
0x00007DD7       LDB R11 [R2]
0x00007DDB       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00007DDF       ADD R10 R10 1               ; othewise go to next file count

0x00007DE3       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

0x00007DE7       MOV R11 R12

    ; round up to 512 boundary

0x00007DEB       LI R2 511
0x00007DF3       ADD R11 R11 R2

0x00007DF7       SHR R11 R11 9
0x00007DFB       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x00007DFF       LI R2 TAR_HEADER_SIZE
0x00007E07       ADD R8 R8 R2

0x00007E0B       ADD R8 R8 R11           ; advance to next tar header

0x00007E0F       LI R12 tar_limit
0x00007E17       LDW R12 [R12]
0x00007E1B       CMP R8 R12
0x00007E1F       BGTU tar_done            ; file data/padding extends beyond archive

0x00007E27       B tar_scan_loop

tar_done:

0x00007E2F       LI R11 tar_count        ; store total file count for this tar archive in global variable

0x00007E37       STW R10 [R11]

0x00007E3B       POP R12
0x00007E3F       POP R11
0x00007E43       POP R10
0x00007E47       POP R9
0x00007E4B       POP R8
0x00007E4F       POP LR

0x00007E53       RET

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

0x00007E57       PUSH R2
0x00007E5B       PUSH R3
0x00007E5F       PUSH R4

0x00007E63       LI   R2 0                  ; result

octal_loop:

0x00007E6B       LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

0x00007E6F       CMP  R3 0
0x00007E73       BEQ  octal_done

0x00007E7B       LI   R4 32                 ; ' '
0x00007E83       CMP  R3 R4
0x00007E87       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x00007E8F       LI   R4 48
0x00007E97       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x00007E9B       SHL  R2 R2 3               ; multiply by 8

0x00007E9F       ADD  R2 R2 R3              ; add digit

0x00007EA3       ADD  R1 R1 1               ; advance to next octal character

0x00007EA7       B    octal_loop

octal_done:

0x00007EAF       MOV  R1 R2                 ; return binary result in R1

0x00007EB3       POP  R4
0x00007EB7       POP  R3
0x00007EBB       POP  R2
0x00007EBF       RET

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

0x00007EDA       PUSH LR
0x00007EDE       PUSH R8
0x00007EE2       PUSH R9
0x00007EE6       PUSH R10

0x00007EEA       LI R8 0

0x00007EF2       LI R10 tar_count
0x00007EFA       LDW R10 [R10]

0x00007EFE       LI R1 tarfs_banner
0x00007F06       BL kputs

dump_loop:

0x00007F0E       CMP R8 R10
0x00007F12       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00007F1A       LI R1 tar_index

0x00007F22       LI R2 TAR_IDX_SIZEOF
0x00007F2A       MUL R3 R8 R2

0x00007F2E       ADD R9 R1 R3

    ; filename

0x00007F32       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x00007F36       MOV R1 R2
0x00007F3A       BL kputs

    ; newline

0x00007F42       LI R1 newline
0x00007F4A       BL kputs

0x00007F52       ADD R8 R8 1
0x00007F56       B dump_loop

dump_done:

0x00007F5E       POP R10
0x00007F62       POP R9
0x00007F66       POP R8
0x00007F6A       POP LR
0x00007F6E       RET

;==============================================================
; TARFS file operations
;==============================================================

;tarfs_ops:
;    .WORD tarfs_read
;    .WORD tarfs_write

;==============================================================
; TARFS tarfs_read:
; R1=file*, R2=user destination, R3=requested length
;==============================================================

tarfs_read:

0x00007F72       PUSH LR
0x00007F76       PUSH R8
0x00007F7A       PUSH R9
0x00007F7E       PUSH R10
0x00007F82       PUSH R11
0x00007F86       PUSH R12

0x00007F8A       MOV R8 R1
0x00007F8E       MOV R9 R2
0x00007F92       MOV R10 R3

0x00007F96       CMP R10 0
0x00007F9A       BEQ tarfs_read_eof

0x00007FA2       PUSH R8
0x00007FA6       PUSH R9
0x00007FAA       MOV R1 R9
0x00007FAE       MOV R2 R10
0x00007FB2       LI R3 1                    ; destination must be user-writable
0x00007FBA       BL user_buffer_valid_range
0x00007FC2       POP R9
0x00007FC6       POP R8
0x00007FCA       CMP R1 1
0x00007FCE       BNE tarfs_read_fault

0x00007FD6       LDW R11 [R8 + FILE_INODE]
0x00007FDA       LDW R11 [R11 + INODE_PRIVATE]

0x00007FDE       LDW R12 [R8 + FILE_OFFSET]
0x00007FE2       LDW R4 [R11 + TAR_IDX_SIZE]

0x00007FE6       CMP R12 R4
0x00007FEA       BGEU tarfs_read_eof

0x00007FF2       SUB R4 R4 R12             ; bytes remaining
0x00007FF6       CMP R10 R4
0x00007FFA       BLEU tarfs_read_count_ready
0x00008002       MOV R10 R4

tarfs_read_count_ready:
0x00008006       LDW R4 [R11 + TAR_IDX_DATA]
0x0000800A       ADD R4 R4 R12             ; kernel source
0x0000800E       MOV R1 R9                 ; user destination
0x00008012       MOV R2 R10
0x00008016       BL copy_to_user

0x0000801E       ADD R12 R12 R1
0x00008022       STW R12 [R8 + FILE_OFFSET]
0x00008026       B tarfs_read_done

tarfs_read_fault:
0x0000802E       LI R1 ERR_FAULT
0x00008036       B tarfs_read_done

tarfs_read_eof:
0x0000803E       LI R1 0

tarfs_read_done:
0x00008046       POP R12
0x0000804A       POP R11
0x0000804E       POP R10
0x00008052       POP R9
0x00008056       POP R8
0x0000805A       POP LR
0x0000805E       RET

tarfs_write:
0x00008062       LI R1 ERR_ACCES
0x0000806A       RET
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

0x0000806E       PUSH LR
0x00008072       PUSH R8
0x00008076       PUSH R9
0x0000807A       PUSH R10
0x0000807E       PUSH R11

0x00008082       MOV R8 R1              ; save directory path
0x00008086       LI R9 0                ; index

0x0000808E       LI R10 tar_count
0x00008096       LDW R10 [R10]
tr_loop:
0x0000809A       CMP R9 R10
0x0000809E       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x000080A6       LI R1 tar_index
0x000080AE       LI R2 TAR_IDX_SIZEOF
0x000080B6       MUL R3 R9 R2
0x000080BA       ADD R11 R1 R3
    ; entry name
0x000080BE       LDW R1 [R11 + TAR_IDX_NAME]
0x000080C2       MOV R2 R8                       ; src dirname "etc/"
0x000080C6       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000080CE       CMP R1 1
0x000080D2       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x000080DA       LDW R1 [R11 + TAR_IDX_NAME]
0x000080DE       MOV R2 R8                       ; prefix
0x000080E2       BL skip_prefix                  ; omit prefix nd print just filename

0x000080EA       MOV R12 R1         ; save component ptr
0x000080EE       BL path_component_len ; out R1-length
0x000080F6       MOV R2 R1
0x000080FA       MOV R1 R12
0x000080FE       BL kputsn   ; r1-ptr r2-len of string

0x00008106       LI R1 newline
0x0000810E       BL kputs

tr_next:
0x00008116       ADD R9 R9 1                     ;to next entry for check
0x0000811A       B tr_loop
tr_done:
0x00008122       POP R11
0x00008126       POP R10
0x0000812A       POP R9
0x0000812E       POP R8
0x00008132       POP LR
0x00008136       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x0000813A       PUSH LR
0x0000813E       PUSH R8
0x00008142       MOV R8 R1

kputs_loop:
0x00008146       LDB R1 [R8]

0x0000814A       CMP R1 0
0x0000814E       BEQ kputs_done

0x00008156       BL uart_putc

0x0000815E       ADD R8 R8 1

0x00008162       B kputs_loop

kputs_done:
0x0000816A       POP R8
0x0000816E       POP LR
0x00008172       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x00008176       PUSH LR
0x0000817A       PUSH R8
0x0000817E       PUSH R9
0x00008182       MOV R8 R1
0x00008186       MOV R9 R2
kputsn_loop:
0x0000818A       CMP R9 0
0x0000818E       BEQ kputsn_done
0x00008196       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x0000819A       BL uart_putc
0x000081A2       ADD R8 R8 1
0x000081A6       SUB R9 R9 1
0x000081AA       B kputsn_loop
kputsn_done:
0x000081B2       POP R9
0x000081B6       POP R8
0x000081BA       POP LR
0x000081BE       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x000081C2       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x000081CA       LDW R2 [R3 + 4]   ; read UART status register
0x000081CE       AND R2 R2 2       ; check if TX ready (bit 1)
0x000081D2       CMP R2 0
0x000081D6       BEQ poll

0x000081DE       STW R1 [R3 + 0]   ; R1 is the character value
0x000081E2       RET



;==============================================================
; Wait queue helpers
;==============================================================

waitq_prepare_sleep:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = WAIT_* reason for debug/task dumps
    ; R3 = optional for sleep TASK_* state to set for this task (usually TASK_BLOCKED_IO)
    ;
    ; Adds the current task to the queue bitmask and marks it blocked.
    ; Device code must re-check hardware readiness after this call. If
    ; the condition is already true, call waitq_cancel_sleep_current.
    ;================================================================
0x000081E6       PUSH R8
0x000081EA       PUSH R9
0x000081EE       PUSH R10

0x000081F2       MOV R9 R1                  ; preserve wait queue pointer
0x000081F6       MOV R10 R2                 ; preserve debug wait reason
0x000081FA       MOV R8 R3                  ; preserve task state to set

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x000081FE   LI R1 CURRENT_TASK
0x00008206   LDW R2 [R1]

0x0000820A       LI R4 1
0x00008212       SHL R4 R4 R2               ; R4 = bit for current task
0x00008216       LDW R5 [R9 + WQ_MASK]
0x0000821A       OR R5 R5 R4
0x0000821E       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00008222   LI R1 TASK_SIZE
0x0000822A   MUL R3 R2 R1
0x0000822E   LI R5 tasks
0x00008236   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x0000823A   LI R1 TASK_BLOCKED_IO
0x00008242   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00008246   STW R10 [R5 + TASK_WAIT]

; addition trick if R3 is set as TASK_SLEEPING then we also set the state to TASK_SLEEPING for syscall sleep/waitpid
0x0000824A       CMP R8 TASK_SLEEPING
0x0000824E       BNE waitq_prepare_done
; macro: TASK_SET_STATE R5, TASK_SLEEPING
0x00008256   LI R1 TASK_SLEEPING
0x0000825E   STW R1 [R5 + TASK_STATE]

waitq_prepare_done:
0x00008262       POP R10
0x00008266       POP R9
0x0000826A       POP R8
0x0000826E       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00008272       PUSH R9

0x00008276       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x0000827A   LI R1 CURRENT_TASK
0x00008282   LDW R2 [R1]

0x00008286       LDW R4 [R9 + WQ_MASK]

0x0000828A       LI  R5 1
0x00008292       SHL R5 R5 R2        ;shift to position of current task bit

0x00008296       NOT R5 R5           ; invert to get mask for clearing this bit

0x0000829A       AND R4 R4 R5        ; clear current task bit

0x0000829E       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x000082A2   LI R1 TASK_SIZE
0x000082AA   MUL R3 R2 R1
0x000082AE   LI R5 tasks
0x000082B6   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x000082BA   LI R1 TASK_READY
0x000082C2   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x000082C6   LI R1 WAIT_NONE
0x000082CE   STW R1 [R5 + TASK_WAIT]

0x000082D2       POP R9
0x000082D6       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000082DA       PUSH LR
0x000082DE       BL schedule_call
0x000082E6       POP LR
0x000082EA       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x000082EE       PUSH LR

0x000082F2       MOV R9 R1
0x000082F6       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x000082FA       LI R10 0
0x00008302       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x00008306       LI R2 0                    ; task index

wq_wake_loop:
0x0000830E       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x00008312       BGE wq_wake_done

0x0000831A       LI R3 1
0x00008322       SHL R3 R3 R2               ; R3 = bit for task R2
0x00008326       AND R4 R8 R3
0x0000832A       CMP R4 0
0x0000832E       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00008336   LI R1 TASK_SIZE
0x0000833E   MUL R3 R2 R1
0x00008342   LI R5 tasks
0x0000834A   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000834E   LI R1 TASK_READY
0x00008356   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000835A   LI R1 WAIT_NONE
0x00008362   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00008366       ADD R2 R2 1
0x0000836A       B wq_wake_loop

wq_wake_done:
0x00008372       POP LR
0x00008376       RET

waitq_wake_bitmask:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = bitmask of tasks to wake (1 = wake, 0 = ignore)
    ; Wakes every task currently recorded in the R2 bitmask.
    ;================================================================

0x0000837A       PUSH LR

0x0000837E       MOV R9 R1
0x00008382       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00008386       MOV R10 R2                 ;
0x0000838A       NOT R10 R10                ; invert bitmask to clear only specified tasks
0x0000838E       AND R10 R8 R10             ; clear only specified tasks
0x00008392       STW R10 [R9 + WQ_MASK]     ; update queue entries to remove (tobe) woken  tasks

0x00008396       MOV R8 R2                  ; R8 = bitmask of tasks to wake
0x0000839A       LI R2 0                    ; task index

wq_wake_b_loop:
0x000083A2       CMP R2 MAX_TASKS           ; check if we processed all tasks in bitmask
0x000083A6       BGE wq_wake_b_done

0x000083AE       LI R3 1
0x000083B6       SHL R3 R3 R2               ; R3 = bit for task R2
0x000083BA       AND R4 R8 R3               ; check if this task is in the wake bitmask
0x000083BE       CMP R4 0
0x000083C2       BEQ wq_wake_b_next

; macro: GET_TASK_PTR R5, R2        ; wake task R2 if its in the bitmask
0x000083CA   LI R1 TASK_SIZE
0x000083D2   MUL R3 R2 R1
0x000083D6   LI R5 tasks
0x000083DE   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x000083E2   LI R1 TASK_READY
0x000083EA   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x000083EE   LI R1 WAIT_NONE
0x000083F6   STW R1 [R5 + TASK_WAIT]

wq_wake_b_next:
0x000083FA       ADD R2 R2 1
0x000083FE       B wq_wake_b_loop

wq_wake_b_done:
0x00008406       POP LR
0x0000840A       RET

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

; INODE_TYPE
.EQU INODE_REG,   1
.EQU INODE_DIR,   2
.EQU INODE_CHAR,  3
.EQU INODE_PIPE,  4

;eg:
;/etc/motd       REG
;/etc            DIR
;/dev/console    CHAR
;pipe            PIPE

;=================================================================
;INODE POOL
;=================================================================

.EQU MAX_INODES, 64

inode_pool:

    .SPACE INODE_SIZEOF * MAX_INODES

inode_used:

    .SPACE MAX_INODES * 4

;=================================================================
;INODE HELPERS
;=================================================================

;=================================================================
; inode_alloc
; Exactly same pattern as file_alloc:
;
; scan inode_used[]
; find free slot
; mark used
; return &inode_pool[i]
;
; out: R1 = inode ptr
;      R1 = 0 if none
;=================================================================
inode_alloc:
0x00008A0E       LI R2 0                      ; index

ia_loop:
0x00008A16       CMP R2 MAX_INODES
0x00008A1A       BGE ia_fail

0x00008A22       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x00008A26       LI R4 inode_used
0x00008A2E       ADD R4 R4 R3                  ; &inode_used[index]

0x00008A32       LDW R5 [R4]                   ; load used marker
0x00008A36       CMP R5 0
0x00008A3A       BEQ ia_found

0x00008A42       ADD R2 R2 1
0x00008A46       B ia_loop

ia_found:
0x00008A4E       LI R5 1
0x00008A56       STW R5 [R4]                  ; mark used

0x00008A5A       LI R3 INODE_SIZEOF
0x00008A62       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x00008A66       LI R1 inode_pool
0x00008A6E       ADD R1 R1 R6                 ; return inode ptr
0x00008A72       RET

ia_fail:
0x00008A76       LI R1 0
0x00008A7E       RET

;=================================================================
;
; inode_free
; Exactly like:
; file_free
;
; Determine slot number from pointer.
;
;inode ptr
;  ↓
;offset from inode_pool
;  ↓
;index
;  ↓
; inode_used[index]=0
; in: R1-inode ptr
;
;=================================================================
inode_free:
    ; in R1 = inode ptr

0x00008A82       LI R2 inode_pool
0x00008A8A       SUB R3 R1 R2                  ; offset from pool base

0x00008A8E       LI R4 INODE_SIZEOF
0x00008A96       DIV R5 R3 R4                 ; index

0x00008A9A       SHL R5 R5 2                  ; index * 4 (u32 array)
0x00008A9E       LI R6 inode_used
0x00008AA6       ADD R6 R6 R5                 ; &inode_used[index]

0x00008AAA       LI R7 0
0x00008AB2       STW R7 [R6]                  ; mark free

0x00008AB6       RET

;=================================================================
; inode_init
;
; Prototype:
;
;  R1 = inode ptr
;  R2 = fs ops ptr
;  R3 = private ptr
;  R4 = inode type
;  R5 = size
;
;=================================================================
inode_init:

0x00008ABA       STW R2 [R1 + INODE_OPS]
0x00008ABE       STW R3 [R1 + INODE_PRIVATE]
0x00008AC2       STW R4 [R1 + INODE_TYPE]
0x00008AC6       STW R5 [R1 + INODE_SIZE]
0x00008ACA       LI R2 1
0x00008AD2       STW R2 [R1 + INODE_REFCNT]
0x00008AD6       RET

;=================================================================
; inode_get
;
; Open file:
;
; open("/etc/motd")
;
; another fd references same inode.
;
; Increment refcount: in R1 - inode ptr
;=================================================================

inode_get:
0x00008ADA       LDW R2 [R1 + INODE_REFCNT]
0x00008ADE       ADD R2 R2 1
0x00008AE2       STW R2 [R1 + INODE_REFCNT]
0x00008AE6       RET

;=================================================================
; inode_put
;
; Close file:
; close(fd)
;
; decrement refcount. in R1 - inode ptr
; free inode if no ref
;=================================================================

inode_put:
0x00008AEA       PUSH LR
0x00008AEE       LDW R2 [R1 + INODE_REFCNT]
0x00008AF2       SUB R2 R2 1
0x00008AF6       STW R2 [R1 + INODE_REFCNT]
0x00008AFA       CMP R2 0
0x00008AFE       BNE inode_put_done
    ; destroy inode
0x00008B06       BL inode_free

inode_put_done:
0x00008B0E       POP LR
0x00008B12       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x00008B16       LDW R2 [R1 + FILE_REFCNT]
0x00008B1A       ADD R2 R2 1
0x00008B1E       STW R2 [R1 + FILE_REFCNT]
0x00008B22       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x00008B26       PUSH LR
0x00008B2A       LDW R2 [R1 + FILE_REFCNT]
0x00008B2E       SUB R2 R2 1
0x00008B32       STW R2 [R1 + FILE_REFCNT]
0x00008B36       CMP R2 0
0x00008B3A       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x00008B42       BL file_free

file_put_done:
0x00008B4A       POP LR
0x00008B4E       RET


; ----------------------------------
; vfs_lookup  - "wrapper fs selector"
;
; R1 = pathname
;
; returns:
;   R1 = inode
;   R1 = 0 not found
; ----------------------------------

vfs_lookup:
0x00008B52       PUSH LR
0x00008B56       MOV R8 R1          ; pathname

0x00008B5A       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x00008B62       CMP R1 0
0x00008B66       BNE vfs_done

0x00008B6E       MOV R1 R8

0x00008B72       BL tarfs_lookup     ; 2 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x00008B7A       CMP R1 0
0x00008B7E       BEQ vfs_not_found

vfs_done:
0x00008B86       POP LR          ;3 R1 - return inode
0x00008B8A       RET

vfs_not_found:
0x00008B8E       LI R1 0         ;it can be just ret but i added it for result clarity
0x00008B96       POP LR          ;or R1 - Nul
0x00008B9A       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x00008B9E       PUSH LR
0x00008BA2       PUSH R8
0x00008BA6       PUSH R9
0x00008BAA       PUSH R10
0x00008BAE       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x00008BB2       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x00008BBA       CMP R1 0
0x00008BBE       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x00008BC6       MOV R8 R1            ; save inode ptr

0x00008BCA       LDW R2 [R8 + INODE_TYPE]
0x00008BCE       LI R3 INODE_DIR
0x00008BD6       CMP R2 R3
0x00008BDA       BEQ fail_isdir            ; if pathname is a dir

0x00008BE2       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x00008BEA       CMP R1 0
0x00008BEE       BEQ fail_nfile

0x00008BF6       MOV R9 R1                ; save file*

    ; initialize file object ;
0x00008BFA       MOV R1 R9                ; R1 file*
0x00008BFE       MOV R2 R8                ; inode*
0x00008C02       MOV R3 R10               ; flags
0x00008C06       BL file_init

0x00008C0E       MOV R1 R9
0x00008C12       BL fd_alloc             ; R1 inited file ptr
0x00008C1A       LI R2 ERR_MFILE
0x00008C22       CMP R1 R2
0x00008C26       BEQ fail_fd
                            ; R1 - holds fd
0x00008C2E       POP R10
0x00008C32       POP R9
0x00008C36       POP R8
0x00008C3A       POP LR
0x00008C3E       RET

fail_fd:
0x00008C42       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x00008C46       LDW R2 [R1 + FILE_INODE]

0x00008C4A       MOV R1 R2
0x00008C4E       BL inode_put             ; close inode refcnt--

0x00008C56       MOV R1 R9
0x00008C5A       BL file_free
0x00008C62       LI R1 ERR_MFILE
0x00008C6A       B  vfs_exit

fail_noent:
0x00008C72       LI R1 ERR_NOENT
0x00008C7A       B  vfs_exit
fail_nfile:
0x00008C82       LI R1 ERR_NFILE
0x00008C8A       B  vfs_exit
fail_isdir:
0x00008C92       LI R1 ERR_ISDIR
0x00008C9A       B  vfs_exit
fail_acces:
0x00008CA2       LI R1 ERR_ACCES
vfs_exit:
0x00008CAA       POP R10
0x00008CAE       POP R9
0x00008CB2       POP R8
0x00008CB6       POP LR
0x00008CBA       RET

;================================================================
; vfs_close - close opened file
;
; in R1 = fd
; out R1 = 0 / ERR_BADF
;
; for documentation:
;fd_remove() — removes one file descriptor.
;file_put() — removes one FILE reference.
;file_free() — destroys the FILE and releases its inode.
;inode_put() — destroys the inode when the last FILE releases it.
;================================================================
vfs_close:
0x00008CBE       PUSH LR
0x00008CC2       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x00008CCA       CMP R1 0
0x00008CCE       BEQ badf_fail

0x00008CD6       MOV R8 R1          ; save file*

0x00008CDA       MOV R1 R8
0x00008CDE       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x00008CE6       LI  R1 0        ; success
0x00008CEE       POP LR
0x00008CF2       RET

badf_fail:
0x00008CF6       LI R1 ERR_BADF
0x00008CFE       POP LR
0x00008D02       RET


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

0x00008D06       LI R2 0                      ; index

fa_loop:
0x00008D0E       CMP R2 MAX_FILES
0x00008D12       BGE fa_fail

0x00008D1A       SHL R3 R2 2                  ; index * 4
0x00008D1E       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00008D26       ADD R4 R4 R3

0x00008D2A       LDW R5 [R4]
0x00008D2E       CMP R5 0
0x00008D32       BEQ fa_found

0x00008D3A       ADD R2 R2 1
0x00008D3E       B fa_loop

fa_found:
0x00008D46       LI R5 1
0x00008D4E       STW R5 [R4]                  ; mark slot used

0x00008D52       LI R4 FILE_SIZE
0x00008D5A       MUL R6 R2 R4

0x00008D5E       LI R1 file_pool
0x00008D66       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x00008D6A       LI R7 0

0x00008D72       STW R7 [R1 + FILE_INODE]
0x00008D76       STW R7 [R1 + FILE_OFFSET]
0x00008D7A       STW R7 [R1 + FILE_FLAGS]

0x00008D7E       RET

fa_fail:
0x00008D82       LI R1 0
0x00008D8A       RET

;=================================================================
; file_free: - destroy file object
; input:
; R1 = pointer to FILE object
; none output
; note it also updates inode if it exists and destroys
; inode if inode.refcnt=0
;=================================================================

file_free:

 ; release inode first
0x00008D8E       PUSH LR
0x00008D92       PUSH R10
0x00008D96       MOV  R10 R1
0x00008D9A       LDW  R2 [R1 + FILE_INODE]

0x00008D9E       CMP R2 0
0x00008DA2       BEQ no_inode

0x00008DAA       MOV R1 R2
0x00008DAE       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x00008DB6       MOV R1 R10
0x00008DBA       LI  R2 file_pool
0x00008DC2       SUB R3 R1 R2                 ; offset from pool base

0x00008DC6       LI  R4 FILE_SIZE
0x00008DCE       DIV R5 R3 R4                 ; slot number

0x00008DD2       SHL R5 R5 2                  ; slot * 4

0x00008DD6       LI  R6 file_used
0x00008DDE       ADD R6 R6 R5                 ; address of slot in file_used

0x00008DE2       LI R7 0
0x00008DEA       STW R7 [R6]                  ; mark free
0x00008DEE       POP R10
0x00008DF2       POP LR
0x00008DF6       RET


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

0x00008DFA       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x00008DFE       LI  R1 tasks
0x00008E06       LI  R2 TASK_SIZE
0x00008E0E       LI  R3 MAX_TASKS
0x00008E16       MUL R3 R2 R3
0x00008E1A       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x00008E22       LI R1 idle_task
0x00008E2A       LI R2 0
0x00008E32       LI R3 0
0x00008E3A       BL task_create

0x00008E42       CMP R1 0
0x00008E46       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task A
    ; ----------------------------------

   ;  LI R1 TASK_A_START
   ;  LI R2 1
   ;  LI R3 0
   ;  BL task_create

   ;  CMP R1 0
   ;  BEQ init_scheduler_fail

    ; ----------------------------------
    ; task B
    ; ----------------------------------

0x00008E4E       LI R1 TASK_B_START
0x00008E56       LI R2 2
0x00008E5E       LI R3 0
0x00008E66       BL task_create

0x00008E6E       CMP R1 0
0x00008E72       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task C -check gettime brk,sbrk syscalls
    ; ----------------------------------

0x00008E7A       LI R1 TASK_C_START
0x00008E82       LI R2 3
0x00008E8A       LI R3 0
0x00008E92       BL task_create

0x00008E9A       CMP R1 0
0x00008E9E       BEQ init_scheduler_fail

    ; Initialize the dynamic fork PID allocator after bootstrap tasks.
0x00008EA6       LI R1 task_count
0x00008EAE       LI R2 4                     ; last task+1 for now
0x00008EB6       STW R2 [R1]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x00008EBA       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x00008EC2   LI R1 CURRENT_TASK
0x00008ECA   STW R2 [R1]

0x00008ECE       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00008ED2       RET


init_scheduler_fail:

0x00008ED6       DEBUG 99

halt:
0x00008EDA       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00008EE2   LI R1 CURRENT_TASK
0x00008EEA   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x00008EEE       ADD R3 R2 1

wrap_check:

0x00008EF2       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x00008EF6       BLT check_task
0x00008EFE       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x00008F06       LI R4 TASK_SIZE
0x00008F0E       MUL R5 R3 R4
0x00008F12       LI R6 tasks
0x00008F1A       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00008F1E       LDW R7 [R5 + TASK_STATE]

0x00008F22       CMP R7 1
0x00008F26       BEQ do_switch
    ; if not ready go to next task in list
0x00008F2E       ADD R3 R3 1
0x00008F32       B wrap_check

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
0x00008F3A   LI R1 CURRENT_TASK
0x00008F42   STW R3 [R1]
0x00008F46       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x00008F4A   LI R1 TASK_SIZE
0x00008F52   MUL R3 R2 R1
0x00008F56   LI R5 tasks
0x00008F5E   ADD R5 R5 R3
0x00008F62       MOV R3 R8
0x00008F66       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x00008F6A       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00008F6E   STW R7 [R5 + TASK_USP]

0x00008F72       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00008F76   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x00008F7A   LI R1 RESUME_TRAP
0x00008F82   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00008F86   LI R1 TASK_SIZE
0x00008F8E   MUL R3 R8 R1
0x00008F92   LI R5 tasks
0x00008F9A   ADD R5 R5 R3
0x00008F9E       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x00008FA2   LDW R7 [R5 + TASK_PTBR]
0x00008FA6       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x00008FAA   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x00008FAE   LDW R7 [R9 + TASK_STATE]
0x00008FB2       CMP R7 TASK_ZOMBIE
0x00008FB6       BNE switch_old_reaped
0x00008FBE       PUSH R5
0x00008FC2       MOV R1 R9
0x00008FC6       BL task_destroy
0x00008FCE       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x00008FD2   LDW R7 [R5 + TASK_RESUME]
0x00008FD6       CMP R7 RESUME_KERNEL
0x00008FDA       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x00008FE2       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x00008FEA       PUSH R1
0x00008FEE       PUSH R2
0x00008FF2       PUSH R3
0x00008FF6       PUSH R4
0x00008FFA       PUSH R5
0x00008FFE       PUSH R6
0x00009002       PUSH R7
0x00009006       PUSH R8
0x0000900A       PUSH R9
0x0000900E       PUSH R10
0x00009012       PUSH R11
0x00009016       PUSH R12
0x0000901A       PUSH R14
0x0000901E       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00009022   LI R1 CURRENT_TASK
0x0000902A   LDW R2 [R1]

0x0000902E       ADD R3 R2 1

schedule_call_wrap_check:
0x00009032       CMP R3 MAX_TASKS
0x00009036       BLT schedule_call_check_task
0x0000903E       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00009046       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x0000904A   LI R1 TASK_SIZE
0x00009052   MUL R3 R8 R1
0x00009056   LI R5 tasks
0x0000905E   ADD R5 R5 R3
0x00009062       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00009066   LDW R7 [R5 + TASK_STATE]
0x0000906A       CMP R7 TASK_READY               ; check it can be run
0x0000906E       BEQ schedule_call_do_switch

0x00009076       ADD R3 R3 1
0x0000907A       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00009082   LI R1 CURRENT_TASK
0x0000908A   STW R3 [R1]
0x0000908E       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00009092   LI R1 TASK_SIZE
0x0000909A   MUL R3 R2 R1
0x0000909E   LI R5 tasks
0x000090A6   ADD R5 R5 R3
0x000090AA       MOV R3 R8

0x000090AE       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x000090B2   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x000090B6   LI R1 RESUME_KERNEL
0x000090BE   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x000090C2   LI R1 TASK_SIZE
0x000090CA   MUL R3 R8 R1
0x000090CE   LI R5 tasks
0x000090D6   ADD R5 R5 R3
0x000090DA       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x000090DE   LDW R7 [R5 + TASK_PTBR]
0x000090E2       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x000090E6   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x000090EA   LDW R7 [R5 + TASK_RESUME]
0x000090EE       CMP R7 RESUME_KERNEL
0x000090F2       BEQ restore_kernel_context

0x000090FA       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x00009102       DISABLEINT                  ; RET does jump by LR(R15)
0x00009106       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x0000910A       POP R14                     ; (in kernel)
0x0000910E       POP R12                     ; DI - to avoid int nesting
0x00009112       POP R11
0x00009116       POP R10
0x0000911A       POP R9
0x0000911E       POP R8
0x00009122       POP R7
0x00009126       POP R6
0x0000912A       POP R5
0x0000912E       POP R4
0x00009132       POP R3
0x00009136       POP R2
0x0000913A       POP R1
0x0000913E       RET
; ================================================================
; Memory and user space layout
; ================================================================

.EQU PAGE_SIZE      4096
.EQU PAGE_SHIFT     12

.EQU PAGE_ALLOC_BASE 0x00050000

.EQU MAX_PHYS_PAGES 128
.EQU PAGE_ALLOC_END  0x000D0000


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
0x00009152       PUSH  R5
0x00009156       PUSH  R6
0x0000915A       PUSH  R7
0x0000915E       PUSH  R8
0x00009162       PUSH  R9

0x00009166       LI R2 0                  ; page index

pa_loop:
0x0000916E       LI R1 MAX_PHYS_PAGES

0x00009176       CMP R2 R1
0x0000917A       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00009182       MOV R3 R2
0x00009186       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x0000918A       MOV R4 R2
0x0000918E       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00009192       LI R5 page_bitmap
0x0000919A       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x0000919E       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x000091A2       LI R7 1
0x000091AA       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x000091AE       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x000091B2       CMP R8 0
0x000091B6       BEQ pa_found                ; if bit is 0, page is free

0x000091BE       ADD R2 R2 1                 ; increment page index and check next page
0x000091C2       B pa_loop

pa_found:

    ; mark page allocated

0x000091CA       OR  R6 R6 R7
0x000091CE       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x000091D2       LI  R9 PAGE_ALLOC_BASE

0x000091DA       MOV R1 R2
0x000091DE       SHL R1 R1 12          ; page_index * 4096

0x000091E2       ADD R1 R1 R9

0x000091E6       POP R9
0x000091EA       POP R8
0x000091EE       POP R7
0x000091F2       POP R6
0x000091F6       POP R5

0x000091FA       RET

pa_fail:

0x000091FE       LI R1 0                     ; no free pages

0x00009206       POP R9
0x0000920A       POP R8
0x0000920E       POP R7
0x00009212       POP R6
0x00009216       POP R5
0x0000921A       RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:
0x0000921E       PUSH  R5
0x00009222       PUSH  R6
0x00009226       PUSH  R7
0x0000922A       PUSH  R8
0x0000922E       PUSH  R9


0x00009232       LI R2 PAGE_ALLOC_BASE
0x0000923A       SUB R3 R1 R2         ; calculate offset from base

0x0000923E       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x00009242       MOV R4 R3
0x00009246       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x0000924A       MOV R5 R3
0x0000924E       AND R5 R5 7          ; bit index in byte = page index % 8

0x00009252       LI R6 page_bitmap
0x0000925A       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x0000925E       LDB R7 [R6]

0x00009262       LI R8 1
0x0000926A       SHL R8 R8 R5         ; mask for this page's bit

0x0000926E       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00009272       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x00009276       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000927A       POP R9
0x0000927E       POP R8
0x00009282       POP R7
0x00009286       POP R6
0x0000928A       POP R5
0x0000928E       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

0x00009292       LI R2 0

pz_loop:

0x0000929A       CMP R3 0
0x0000929E       BEQ pz_done

0x000092A6       STB R2 [R1]

0x000092AA       ADD R1 R1 1
0x000092AE       SUB R3 R3 1

0x000092B2       B pz_loop

pz_done:
0x000092BA       RET

; ================================================================
; Copy a memory page (or other multiple of 4 bytes) by physical address.
; R1 = source physical address (should be aligned!)
; R2 = destination physical address (aligned!)
; R3 = size in bytes (must be multiple of 4)
; each time it copyes 4 bytes (1 word)
; ================================================================
page_copy:

page_copy_loop:
0x000092BE       CMP R3 0
0x000092C2       BEQ page_copy_done
0x000092CA       LDW R4 [R1]
0x000092CE       STW R4 [R2]
0x000092D2       ADD R1 R1 4
0x000092D6       ADD R2 R2 4
0x000092DA       SUB R3 R3 4
0x000092DE       B page_copy_loop

page_copy_done:
0x000092E6       RET

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

0x000097EE       PUSH LR

0x000097F2       MOV R8 R1          ; entry
0x000097F6       MOV R9 R2          ; pid
0x000097FA       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x00009802       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x0000980A       CMP R1 0
0x0000980E       BEQ task_create_fail

0x00009816       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x0000981A       MOV R1 R10
0x0000981E       LI R3 TASK_SIZE
0x00009826       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x0000982E   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x00009832   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x00009836       BL page_alloc
0x0000983E       CMP R1 0
0x00009842       BEQ task_create_fail

0x0000984A       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x0000984E   STW R1 [R10 + TASK_PTBR]

0x00009852       MOV R1 R12
0x00009856       LI  R3 PAGE_SIZE
0x0000985E       BL  mem_zero                   ; zero out the sensitive new page table

0x00009866       MOV R1 R12
0x0000986A       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x00009872   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00009876   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x0000987A   LDW R1 [R10 + TASK_PTBR]
0x0000987E       MOV R2 R8
0x00009882       LI R3 0xFFFFF000
0x0000988A       AND R2 R2 R3
0x0000988E       MOV R3 R2
0x00009892       CMP R9 0
0x00009896       BEQ task_create_map_kernel_entry
0x0000989E       LI R4 USER_RX
0x000098A6       B task_create_map_entry
task_create_map_kernel_entry:
0x000098AE       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x000098B6       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x000098BE       BL page_alloc
0x000098C6       CMP R1 0
0x000098CA       BEQ task_create_fail

0x000098D2       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x000098D6   STW R12 [R10 + TASK_USTACK_PAGE]

0x000098DA       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x000098E2   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x000098E6   LDW R1 [R10 + TASK_PTBR]

0x000098EA       LI  R2 USER_STACK_VA
0x000098F2       MOV R3 R12
0x000098F6       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x000098FE       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x00009906       BL page_alloc
0x0000990E       CMP R1 0
0x00009912       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x0000991A   STW R1 [R10 + TASK_KSTACK_PAGE]
0x0000991E       LI R2 PAGE_SIZE

0x00009926       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x0000992A       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x0000992E   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00009932   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x00009936       LI R1 0

0x0000993E       PUSH R1            ; R1
0x00009942       PUSH R1            ; R2
0x00009946       PUSH R1            ; R3
0x0000994A       PUSH R1            ; R4
0x0000994E       PUSH R1            ; R5
0x00009952       PUSH R1            ; R6
0x00009956       PUSH R1            ; R7
0x0000995A       PUSH R1            ; R8
0x0000995E       PUSH R1            ; R9
0x00009962       PUSH R1            ; R10
0x00009966       PUSH R1            ; R11
0x0000996A       PUSH R1            ; R12
0x0000996E       PUSH R1            ; R14 (FP)
0x00009972       PUSH R1            ; R15 (LR)

0x00009976       PUSH R11           ; R11 - user SP top

0x0000997A       MOV R1 R8
0x0000997E       PUSH R1            ; sepc = entry

0x00009982       LI R1 0
0x0000998A       PUSH R1            ; sflags

0x0000998E       CMP R9 0
0x00009992       BEQ task_create_kernel_status
0x0000999A       LI R1 0x20
0x000099A2       B task_create_status_ready
task_create_kernel_status:
0x000099AA       LI R1 0x120
task_create_status_ready:
0x000099B2       PUSH R1            ; sstatus

0x000099B6       LI R1 0
0x000099BE       PUSH R1            ; scause
0x000099C2       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x000099C6       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x000099CA   STW R1 [R10 + TASK_KSP]

0x000099CE       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x000099D2   LI R1 WAIT_NONE
0x000099DA   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x000099DE   LI R1 RESUME_TRAP
0x000099E6   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x000099EA       BL page_alloc
0x000099F2       CMP R1 0
0x000099F6       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x000099FE       MOV R12 R1

0x00009A02       LI  R3 PAGE_SIZE
0x00009A0A       MOV R1 R12
0x00009A0E       BL  mem_zero

    ; stdin
0x00009A16       LI  R2 file_stdin
0x00009A1E       STW R2 [R12 + 0]

    ; stdout
0x00009A22       LI  R2 file_stdout
0x00009A2A       STW R2 [R12 + 4]

    ; stderr
0x00009A2E       LI  R2 file_stderr
0x00009A36       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x00009A3A   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x00009A3E       BL page_alloc
0x00009A46       CMP R1 0
0x00009A4A       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x00009A52   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x00009A56       BL page_alloc
0x00009A5E       CMP R1 0
0x00009A62       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x00009A6A   STW R1 [R10 + TASK_KBUF_RD_PTR]

    ; ----------------------------------
    ; data page - for user buffers and heap
    ; ----------------------------------

0x00009A6E       BL page_alloc
0x00009A76       CMP R1 0
0x00009A7A       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x00009A82   STW R1 [R10 + TASK_DATA_PAGE]

0x00009A86       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x00009A8A   LDW R1 [R10 + TASK_PTBR]
0x00009A8E       LI  R2 USER_DATA_VA
0x00009A96       MOV R3 R12
0x00009A9A       LI  R4 USER_RW
0x00009AA2       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; initialize code page pointer to zero until execve or static code assignment
    ; This means the task currently has no execve-loaded program image.
    ; When execve runs, TASK_CODE_PAGE will be updated to point to the
    ; physical page currently mapped at USER_CODE_VA.
0x00009AAA       LI R1 0
; macro: TASK_SET_CODE_PAGE R10, R1
0x00009AB2   STW R1 [R10 + TASK_CODE_PAGE]

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x00009AB6   LI R1 TASK_READY
0x00009ABE   STW R1 [R10 + TASK_STATE]

    ; Initialize program break
0x00009AC2       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x00009ACA   STW R1 [R10 + TASK_BREAK]

    ; Initialize parent PID to 0 by default
0x00009ACE       LI R1 0
; macro: TASK_SET_PPID R10, R1
0x00009AD6   STW R1 [R10 + TASK_PPID]

0x00009ADA       MOV R1 R10                              ; return created task pointer

0x00009ADE       POP LR
0x00009AE2       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x00009AE6       CMP R10 0
0x00009AEA       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x00009AF2   LDW R1 [R10 + TASK_PTBR]
0x00009AF6       CMP R1 0
0x00009AFA       BEQ task_create_free_ustack
0x00009B02       BL page_free

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00009B0A   LDW R1 [R10 + TASK_USTACK_PAGE]
0x00009B0E       CMP R1 0
0x00009B12       BEQ task_create_free_kstack
0x00009B1A       BL page_free

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x00009B22   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x00009B26       CMP R1 0
0x00009B2A       BEQ task_create_free_fd
0x00009B32       BL page_free

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00009B3A   LDW R1 [R10 + TASK_FD_TABLE]
0x00009B3E       CMP R1 0
0x00009B42       BEQ task_create_free_kwr
0x00009B4A       BL page_free

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x00009B52   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x00009B56       CMP R1 0
0x00009B5A       BEQ task_create_free_krd
0x00009B62       BL page_free

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x00009B6A   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x00009B6E       CMP R1 0
0x00009B72       BEQ task_create_free_data
0x00009B7A       BL page_free

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x00009B82   LDW R1 [R10 + TASK_DATA_PAGE]
0x00009B86       CMP R1 0
0x00009B8A       BEQ task_create_clear_slot
0x00009B92       BL page_free

task_create_clear_slot:
0x00009B9A       MOV R1 R10
0x00009B9E       LI R3 TASK_SIZE
0x00009BA6       BL mem_zero

task_create_fail_return:
0x00009BAE       LI R1 0

0x00009BB6       POP LR
0x00009BBA       RET

;================================================================
; task_clone_current - clone the currently running task for fork
; returns:
;   R1 = child task* on success
;   R1 = 0 on failure
;
; This performs a shallow process clone for the current task:
; - allocate a new task slot and page table
; - copy the current user stack, data page, and code page
; - allocate fresh kernel stacks, kernel buffers, and fd table page
; - copy the parent fd table and increment open file refcounts
; - preserve the current trapframe and return 0 in the child
;================================================================
task_clone_current:
0x00009BBE       MOV  R8 SP ;save sp to point to task trapframe!
0x00009BC2       PUSH LR

    ; Get the current task slot and parent task pointer.
; macro: GET_CURR_TASK_IDX R6
0x00009BC6   LI R1 CURRENT_TASK
0x00009BCE   LDW R6 [R1]
; macro: GET_TASK_PTR R7, R6           ; R7 = parent task*
0x00009BD2   LI R1 TASK_SIZE
0x00009BDA   MUL R3 R6 R1
0x00009BDE   LI R7 tasks
0x00009BE6   ADD R7 R7 R3

    ; Allocate a fresh child task slot.
0x00009BEA       BL task_alloc
0x00009BF2       CMP R1 0
0x00009BF6       BEQ clone_fail
0x00009BFE       MOV R10 R1                    ; R10 = child task*

    ; Clear the new child task slot before use.
0x00009C02       MOV R1 R10
0x00009C06       LI R3 TASK_SIZE
0x00009C0E       BL mem_zero

    ; Assign a new PID from the dynamic pid counter.
0x00009C16       LI R1 task_count
0x00009C1E       LDW R2 [R1]

; macro: TASK_SET_PID R10, R2        ; set new child task Pid to child task (current task_count value)
0x00009C22   STW R2 [R10 + TASK_PID]
0x00009C26       ADD R2 R2 1
0x00009C2A       STW R2 [R1]                 ; update task_count as we created a new task

    ; Set child parent PID to the current task's PID.
; macro: TASK_GET_PID R2, R7
0x00009C2E   LDW R2 [R7 + TASK_PID]
; macro: TASK_SET_PPID R10, R2       ; pid - new, ppid - parent task's pid (new task)
0x00009C32   STW R2 [R10 + TASK_PPID]

    ; Copy the current task's program break.
; macro: TASK_GET_BREAK R2, R7
0x00009C36   LDW R2 [R7 + TASK_BREAK]
; macro: TASK_SET_BREAK R10, R2
0x00009C3A   STW R2 [R10 + TASK_BREAK]

    ; Copy current task PC for debugging/metadata.
; macro: TASK_GET_PC R2, R7
0x00009C3E   LDW R2 [R7 + TASK_PC]
; macro: TASK_SET_PC R10, R2
0x00009C42   STW R2 [R10 + TASK_PC]

    ; Allocate and initialize a fresh page table for the child.
0x00009C46       BL page_alloc
0x00009C4E       CMP R1 0
0x00009C52       BEQ clone_fail
0x00009C5A       MOV R11 R1
; macro: TASK_SET_PTBR R10, R11
0x00009C5E   STW R11 [R10 + TASK_PTBR]

    ; Clone the parent's entire page table into the child.
; macro: TASK_GET_PTBR R1, R7
0x00009C62   LDW R1 [R7 + TASK_PTBR]
0x00009C66       MOV R2 R11
0x00009C6A       LI R3 PAGE_SIZE
0x00009C72       BL page_copy

    ; Preserve the current exec code page pointer if the parent uses execve.
; macro: TASK_GET_CODE_PAGE R2, R7
0x00009C7A   LDW R2 [R7 + TASK_CODE_PAGE]
; macro: TASK_SET_CODE_PAGE R10, R2
0x00009C7E   STW R2 [R10 + TASK_CODE_PAGE]

    ; The child has inherited the parent's kernel and code mappings.
    ; We will override the user stack and data mappings below.
    ; Allocate and clone the user stack page.
0x00009C82       BL page_alloc
0x00009C8A       CMP R1 0
0x00009C8E       BEQ clone_fail
0x00009C96       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12   ; set new page as child user stack page
0x00009C9A   STW R12 [R10 + TASK_USTACK_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x00009C9E   LDW R1 [R10 + TASK_PTBR]
0x00009CA2       LI R2 USER_STACK_VA
0x00009CAA       MOV R3 R12
0x00009CAE       LI R4 USER_RW
0x00009CB6       BL map_page             ; map user stack page to child ptbr

; macro: TASK_GET_USTACK_PAGE R1, R7
0x00009CBE   LDW R1 [R7 + TASK_USTACK_PAGE]
0x00009CC2       MOV R2 R12
0x00009CC6       LI R3 PAGE_SIZE
0x00009CCE       BL page_copy            ; copy parent user stack page -> child user stack page

    ; Allocate and clone the user data page.
0x00009CD6       BL page_alloc
0x00009CDE       CMP R1 0
0x00009CE2       BEQ clone_fail
0x00009CEA       MOV R12 R1
; macro: TASK_SET_DATA_PAGE R10, R12     ; set new page as child user data page
0x00009CEE   STW R12 [R10 + TASK_DATA_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x00009CF2   LDW R1 [R10 + TASK_PTBR]
0x00009CF6       LI R2 USER_DATA_VA
0x00009CFE       MOV R3 R12
0x00009D02       LI R4 USER_RW
0x00009D0A       BL map_page                     ; map user data page to child ptbr

; macro: TASK_GET_DATA_PAGE R1, R7
0x00009D12   LDW R1 [R7 + TASK_DATA_PAGE]
0x00009D16       MOV R2 R12
0x00009D1A       LI R3 PAGE_SIZE
0x00009D22       BL page_copy                    ; copy parent user data page -> child user data page

    ; Clone the fd table and honor open file refcounts.
0x00009D2A       BL page_alloc
0x00009D32       CMP R1 0
0x00009D36       BEQ clone_fail

0x00009D3E       MOV R12 R1

; macro: TASK_SET_FD_TABLE R10, R12       ; set new page as child fd table page
0x00009D42   STW R12 [R10 + TASK_FD_TABLE]
0x00009D46       LI R3 PAGE_SIZE
0x00009D4E       MOV R1 R12
0x00009D52       BL mem_zero                     ; clear the child fd table page just in case

; macro: TASK_GET_FD_TABLE R1, R7         ; R1 - parent fd table page
0x00009D5A   LDW R1 [R7 + TASK_FD_TABLE]
0x00009D5E       CMP R1 0
0x00009D62       BEQ clone_fd_done                ; if parent has no fd table, skip fd cloning

    ; parent → child copy FIRST
0x00009D6A       MOV R1 R1        ; parent fd page
0x00009D6E       MOV R2 R12       ; child fd page
0x00009D72       LI R3 PAGE_SIZE
0x00009D7A       BL page_copy

0x00009D82       LI R4 3                      ; fd index loop + 3 stdin/out/err refcount=1, so start at 3

clone_fd_loop:
0x00009D8A       CMP R4 MAX_FDS
0x00009D8E       BGE clone_fd_done

0x00009D96       SHL R5 R4 2                 ; multiply fd index by 4 to get byte offset
0x00009D9A       ADD R6 R12 R5               ; R6 = &child_fd_table[i]

0x00009D9E       LDW R7 [R6]                 ; R7 = file* from child fd table
0x00009DA2       CMP R7 0
0x00009DA6       BEQ clone_fd_next           ; if fd slot is empty, skip to next

0x00009DAE       MOV R1 R7                   ; IMPORTANT: isolate argument
0x00009DB2       BL file_get                 ; increment refcount of the file* in child fd table

clone_fd_next:
0x00009DBA       ADD R4 R4 1
0x00009DBE       B clone_fd_loop

clone_fd_done:
    ; Allocate fresh kernel buffers for the child.
0x00009DC6       BL page_alloc
0x00009DCE       CMP R1 0
0x00009DD2       BEQ clone_fail

; macro: TASK_SET_KBUF_WR R10, R1        ; set new page as child kernel write buffer
0x00009DDA   STW R1 [R10 + TASK_KBUF_WR_PTR]
0x00009DDE       LI R3 PAGE_SIZE
0x00009DE6       BL mem_zero                     ; zero out the child kernel write buffer

0x00009DEE       BL page_alloc
0x00009DF6       CMP R1 0
0x00009DFA       BEQ clone_fail
; macro: TASK_SET_KBUF_RD R10, R1        ; set new page as child kernel read buffer
0x00009E02   STW R1 [R10 + TASK_KBUF_RD_PTR]
0x00009E06       LI R3 PAGE_SIZE
0x00009E0E       BL mem_zero                     ; zero out the child kernel read buffer

    ; Allocate and initialize the child's kernel stack.
0x00009E16       BL page_alloc
0x00009E1E       CMP R1 0
0x00009E22       BEQ clone_fail
0x00009E2A       MOV R12 R1
; macro: TASK_SET_KSTACK_PAGE R10, R12   ; set new page as child kernel stack page
0x00009E2E   STW R12 [R10 + TASK_KSTACK_PAGE]
0x00009E32       LI R3 PAGE_SIZE
0x00009E3A       ADD R12 R12 R3                  ; R12 = child kernel stack top


    ; Copy the current kernel trapframe into the child's new kernel stack.
    ; The trapframe is at SP + 24 (after 6 pushes of 4 bytes each)
    ; Child trapframe goes at the top of child's stack (R12 - 80)
0x00009E3E       MOV R1 R8                     ; R1 = parent trapframe BASE saved in the beginiig of func
0x00009E42       MOV R6 R12
0x00009E46       LI R5 80                    ; trapframe size in bytes
0x00009E4E       SUB R6 R6 R5               ; R6 = child trapframe base inside new kernel stack
0x00009E52       MOV R2 R6
0x00009E56       LI R3 80
0x00009E5E       BL page_copy                ; so we copy 80 bytes from SP to R12-80 (child trapframe base)

    ; Return 0 in the child syscall result register.
0x00009E66       LI R4 0
0x00009E6E       STW R4 [R6 + TF_R1]


    ; Preserve the user SP for later trap/schedule bookkeeping.
    ; User SP is already in the trapframe we copied
    ; But we also need to set it in the child's task struct
0x00009E72       LDW R4 [R6 + TF_USP]
; macro: TASK_SET_USP R10, R4
0x00009E76   STW R4 [R10 + TASK_USP]

    ; Save the child kernel trapframe pointer and make it runnable.
; macro: TASK_SET_KSP R10, R6                    ;R6 = child trapframe base inside new kernel stack
0x00009E7A   STW R6 [R10 + TASK_KSP]
; macro: TASK_SET_RESUME R10, RESUME_TRAP
0x00009E7E   LI R1 RESUME_TRAP
0x00009E86   STW R1 [R10 + TASK_RESUME]
; macro: TASK_SET_WAIT R10, WAIT_NONE
0x00009E8A   LI R1 WAIT_NONE
0x00009E92   STW R1 [R10 + TASK_WAIT]
; macro: TASK_SET_STATE R10, TASK_READY
0x00009E96   LI R1 TASK_READY
0x00009E9E   STW R1 [R10 + TASK_STATE]

0x00009EA2       MOV R1 R10          ; return child task pointer

0x00009EA6       POP LR
0x00009EAA       RET

clone_fail:
0x00009EAE       CMP R10 0
0x00009EB2       BEQ clone_fail_return
0x00009EBA       MOV R1 R10
0x00009EBE       BL task_destroy
clone_fail_return:
0x00009EC6       LI R1 0
0x00009ECE       POP LR
0x00009ED2       RET

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

0x00009ED6       PUSH LR
0x00009EDA       push R12 ; preserve R12 which we use for temporary storage in this function
0x00009EDE       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x00009EE2   LDW R2 [R1 + TASK_PTBR]
0x00009EE6       CMP R2 0
0x00009EEA       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x00009EF2       MOV R1 R2
0x00009EF6       BL page_free        ; free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x00009EFE   LDW R2 [R12 + TASK_USTACK_PAGE]
0x00009F02       CMP R2 0
0x00009F06       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00009F0E       MOV R1 R2
0x00009F12       BL page_free

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x00009F1A   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x00009F1E       CMP R2 0
0x00009F22       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00009F2A       MOV R1 R2
0x00009F2E       BL page_free

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x00009F36   LDW R2 [R12 + TASK_FD_TABLE]
0x00009F3A       CMP R2 0
0x00009F3E       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00009F46       MOV R1 R2
0x00009F4A       BL page_free

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x00009F52   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x00009F56       CMP R2 0
0x00009F5A       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x00009F62       MOV R1 R2
0x00009F66       BL page_free

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x00009F6E   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x00009F72       CMP R2 0
0x00009F76       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x00009F7E       MOV R1 R2
0x00009F82       BL page_free

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x00009F8A   LDW R2 [R12 + TASK_DATA_PAGE]
0x00009F8E       CMP R2 0
0x00009F92       BEQ td_skip_code
0x00009F9A       MOV R1 R2
0x00009F9E       BL page_free

td_skip_code:

; macro: TASK_GET_CODE_PAGE R2, R12
0x00009FA6   LDW R2 [R12 + TASK_CODE_PAGE]
0x00009FAA       CMP R2 0
0x00009FAE       BEQ td_done
0x00009FB6       MOV R1 R2
0x00009FBA       BL page_free

td_done:

0x00009FC2       MOV R1 R12
0x00009FC6       LI  R3 TASK_SIZE
0x00009FCE       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x00009FD6       POP R12         ; restore R12
0x00009FDA       POP LR
0x00009FDE       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x00009FE2       PUSH LR
0x00009FE6       PUSH R8
0x00009FEA       PUSH R9
0x00009FEE       PUSH R10
0x00009FF2       PUSH R11
0x00009FF6       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x00009FFA   LDW R4 [R1 + TASK_FD_TABLE]
0x00009FFE       MOV R12 R4

0x0000A002       LI R5 3              ; skip stdin/out/err
0x0000A00A       MOV R11 R5

fd_loop:

0x0000A00E       CMP R11 MAX_FDS
0x0000A012       BGE fd_done         ; if we processed all fd slots, we are done

0x0000A01A       SHL R6 R11 2
0x0000A01E       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x0000A022       LDW R8 [R10]
0x0000A026       CMP R8 0
0x0000A02A       BEQ fd_next         ; if fd slot is empty, skip to next

0x0000A032       MOV R1 R8
0x0000A036       BL file_free
0x0000A03E       LI R9 0
0x0000A046       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x0000A04A       ADD R11 R11 1
0x0000A04E       B fd_loop

fd_done:
0x0000A056       POP R12
0x0000A05A       POP R11
0x0000A05E       POP R10
0x0000A062       POP R9
0x0000A066       POP R8
0x0000A06A       POP LR
0x0000A06E       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x0000A072       PUSH LR
0x0000A076       PUSH R8
0x0000A07A       PUSH R9
0x0000A07E       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x0000A082   LI R1 CURRENT_TASK
0x0000A08A   LDW R10 [R1]
0x0000A08E       LI R8 0

task_reap_loop:
0x0000A096       CMP R8 MAX_TASKS
0x0000A09A       BGE task_reap_done

0x0000A0A2       CMP R8 R10
0x0000A0A6       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x0000A0AE   LI R1 TASK_SIZE
0x0000A0B6   MUL R3 R8 R1
0x0000A0BA   LI R9 tasks
0x0000A0C2   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x0000A0C6   LDW R1 [R9 + TASK_STATE]
0x0000A0CA       CMP R1 TASK_ZOMBIE
0x0000A0CE       BNE task_reap_next

0x0000A0D6       PUSH R8
0x0000A0DA       MOV R1 R9
0x0000A0DE       BL task_destroy
0x0000A0E6       POP R8

task_reap_next:
0x0000A0EA       ADD R8 R8 1
0x0000A0EE       B task_reap_loop

task_reap_done:
0x0000A0F6       POP R10
0x0000A0FA       POP R9
0x0000A0FE       POP R8
0x0000A102       POP LR
0x0000A106       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x0000A10A       LI R1 tasks
0x0000A112       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x0000A11A   LDW R3 [R1 + TASK_STATE]

0x0000A11E       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000A122       BEQ task_alloc_found

0x0000A12A       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x0000A12E       SUB R2 R2 1
0x0000A132       BNE task_alloc_loop

; no free tasks slots

0x0000A13A       LI R1 0
0x0000A142       RET

task_alloc_found:                           ;R1 points to free task slot

0x0000A146       RET


; ================================================================
; SIMPLE MUTEX IMPLEMENTATION
; ================================================================

; Mutex structure offsets
.EQU MUTEX_OWNER,     0    ; task* of current owner (0 if unlocked)
.EQU MUTEX_WAITQ,     4    ; wait queue of tasks waiting for this mutex
.EQU MUTEX_SIZE,      8

; ================================================================
; Console mutex instance
; ================================================================

console_mutex:
    .WORD 0              ; owner (0 = unlocked)
    .WORD 0              ; wait queue (bitmask of waiting tasks)

; ================================================================
; mutex_init - Initialize a mutex
; R1 = mutex pointer
; ================================================================
mutex_init:
0x0000A152       PUSH R2

0x0000A156       LI R2 0
0x0000A15E       STW R2 [R1 + MUTEX_OWNER]      ; owner = NULL
0x0000A162       STW R2 [R1 + MUTEX_WAITQ]      ; waitq = 0 (empty)

0x0000A166       POP R2
0x0000A16A       RET

; ================================================================
; mutex_lock - Acquire a mutex (blocks if already locked)
; R1 = mutex pointer
;
;If (no one has the key):
;    Take the key (become owner)
;    Enter the room
;Else:
;    Get in line (add to wait queue)
;    Go to sleep (scheduler runs other tasks)
;    Wake up when key is available
;    Try to take the key again
; ================================================================

mutex_lock:

0x0000A16E       PUSH LR
0x0000A172       PUSH R8
0x0000A176       PUSH R9
0x0000A17A       PUSH R10

0x0000A17E       MOV R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000A182   LI R1 CURRENT_TASK
0x0000A18A   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000A18E   LI R1 TASK_SIZE
0x0000A196   MUL R3 R9 R1
0x0000A19A   LI R9 tasks
0x0000A1A2   ADD R9 R9 R3

mutex_lock_retry:
    ; Check if mutex is already locked
0x0000A1A6       LDW R10 [R8 + MUTEX_OWNER]
0x0000A1AA       CMP R10 0
0x0000A1AE       BEQ mutex_lock_acquire      ; if unlocked, acquire it

    ; this Mutex is locked by someone else - block
    ; Add current task to mutex wait queue
0x0000A1B6       MOV R1 R8
0x0000A1BA       ADD R1 R1 MUTEX_WAITQ

0x0000A1BE       LI R2 WAIT_MUTEX
0x0000A1C6       LI R3 TASK_WAIT_MUTEX
0x0000A1CE       BL waitq_prepare_sleep

    ; Re-check if mutex became available while preparing sleep
0x0000A1D6       LDW R10 [R8 + MUTEX_OWNER]
0x0000A1DA       CMP R10 0
0x0000A1DE       BEQ mutex_lock_wake

    ; Still locked - go to sleep
0x0000A1E6       BL waitq_sleep_current

    ; Woken up - try to acquire again
0x0000A1EE       B mutex_lock_retry

mutex_lock_wake:
    ; Mutex became available, cancel sleep and acquire
0x0000A1F6       MOV R1 R8
0x0000A1FA       ADD R1 R1 MUTEX_WAITQ
0x0000A1FE       BL waitq_cancel_sleep_current

0x0000A206       B mutex_lock_retry

mutex_lock_acquire:
    ; Disable interrupts to prevent race conditions
0x0000A20E       DISABLEINT

    ; Double-check it's still unlocked
0x0000A212       LDW R10 [R8 + MUTEX_OWNER]
0x0000A216       CMP R10 0
0x0000A21A       BNE mutex_lock_race

    ; Set owner to current task
0x0000A222       STW R9 [R8 + MUTEX_OWNER]

    ; Re-enable interrupts
0x0000A226       ENABLEINT

0x0000A22A       POP R10
0x0000A22E       POP R9
0x0000A232       POP R8
0x0000A236       POP LR
0x0000A23A       RET

mutex_lock_race:
    ; Someone else acquired it while interrupts were disabled
0x0000A23E       ENABLEINT
0x0000A242       B mutex_lock_retry


; ================================================================
; mutex_unlock - Release a mutex
; R1 = mutex pointer
; If (I am the owner):
;    Give up the key (owner = NULL)
;     If (someone is waiting):
;        Wake up the first person in line
;        They will try to take the key
; ================================================================
mutex_unlock:
0x0000A24A       PUSH LR
0x0000A24E       PUSH R8
0x0000A252       PUSH R9
0x0000A256       PUSH R10

0x0000A25A       MOV  R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000A25E   LI R1 CURRENT_TASK
0x0000A266   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000A26A   LI R1 TASK_SIZE
0x0000A272   MUL R3 R9 R1
0x0000A276   LI R9 tasks
0x0000A27E   ADD R9 R9 R3

    ; Verify ownership
0x0000A282       LDW  R10 [R8 + MUTEX_OWNER]
0x0000A286       CMP  R10 R9
0x0000A28A       BNE  mutex_unlock_error     ; Not owner - error!

    ; Release the mutex
0x0000A292       LI  R10 0
0x0000A29A       STW R10 [R8 + MUTEX_OWNER]

    ; Wake one waiting task (if someone is waiting)
    ; waky next one (of any waiting)
0x0000A29E       MOV R1 R8
0x0000A2A2       ADD R1 R1 MUTEX_WAITQ
0x0000A2A6       BL waitq_wake_one

mutex_unlock_done:
0x0000A2AE       POP R10
0x0000A2B2       POP R9
0x0000A2B6       POP R8
0x0000A2BA       POP LR
0x0000A2BE       RET

mutex_unlock_error:
    ; Not owner - ignore (or panic)
0x0000A2C2       POP R10
0x0000A2C6       POP R9
0x0000A2CA       POP R8
0x0000A2CE       POP LR
0x0000A2D2       RET

; ================================================================
; waitq_wake_one - Wake exactly one task from the wait queue
; R1 = wait queue pointer
; ================================================================
waitq_wake_one:
0x0000A2D6       PUSH LR
0x0000A2DA       PUSH R8
0x0000A2DE       PUSH R9
0x0000A2E2       PUSH R10
0x0000A2E6       PUSH R11

0x0000A2EA       MOV R8 R1                  ; wait queue pointer
0x0000A2EE       LDW R9 [R8 + WQ_MASK]      ; current wait queue mask

0x0000A2F2       CMP R9 0
0x0000A2F6       BEQ waitq_wake_one_done    ; No waiters

    ; Find the first waiting task
0x0000A2FE       LI R10 0                   ; task index

waitq_wake_one_find:
0x0000A306       CMP R10 MAX_TASKS
0x0000A30A       BGE waitq_wake_one_done

0x0000A312       LI R11 1
0x0000A31A       SHL R11 R11 R10            ; bit for this task
0x0000A31E       AND R2 R9 R11
0x0000A322       CMP R2 0
0x0000A326       BNE waitq_wake_one_found

0x0000A32E       ADD R10 R10 1
0x0000A332       B waitq_wake_one_find

waitq_wake_one_found:
    ; Clear this task's bit from the wait queue
0x0000A33A       NOT R11 R11
0x0000A33E       AND R9 R9 R11
0x0000A342       STW R9 [R8 + WQ_MASK]

    ; Wake this task
; macro: GET_TASK_PTR R5, R10
0x0000A346   LI R1 TASK_SIZE
0x0000A34E   MUL R3 R10 R1
0x0000A352   LI R5 tasks
0x0000A35A   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000A35E   LI R1 TASK_READY
0x0000A366   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000A36A   LI R1 WAIT_NONE
0x0000A372   STW R1 [R5 + TASK_WAIT]

waitq_wake_one_done:
0x0000A376       POP R11
0x0000A37A       POP R10
0x0000A37E       POP R9
0x0000A382       POP R8
0x0000A386       POP LR
0x0000A38A       RET

; ================================================================
; CONSOLE MUTEX WRAPPER FUNCTIONS
; ================================================================

console_lock:
0x0000A38E       PUSH LR
0x0000A392       LI R1 console_mutex
0x0000A39A       BL mutex_lock
0x0000A3A2       POP LR
0x0000A3A6       RET

console_unlock:
0x0000A3AA       PUSH LR
0x0000A3AE       LI R1 console_mutex
0x0000A3B6       BL mutex_unlock
0x0000A3BE       POP LR
0x0000A3C2       RET



; ==================================================
; TAR index entry
; ==================================================

.EQU TAR_IDX_NAME,     0      ; ptr to filename
.EQU TAR_IDX_DATA,     4      ; ptr to file data
.EQU TAR_IDX_SIZE,     8      ; file size
.EQU TAR_IDX_TYPE,    12      ; file/dir

.EQU TAR_IDX_SIZEOF,  16

; ==================================================
; VFS module
; ==================================================

; common va address in data segment of a process
.EQU USER_READ_BUF,  0x00042000
.EQU USER_WRITE_BUF, 0x00042100



; ================================================================
; USER mode TASKS
; ================================================================


; --TASK 1----------------------------------------------
.ORG 0x19000
TASK_A_START:
0x00019000       li R1 25
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
0x0001A090       LI R3 27
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
0x0001A0B4       LI R3 5
0x0001A0BC       SVC SYS_READ
  ;  DEBUG  2
0x0001A0C0       CMP R1 0
0x0001A0C4       BLE task_b_yield

0x0001A0CC       MOV R5 R1
0x0001A0D0       LI R1 STDOUT_FD
0x0001A0D8       LI R2 USER_READ_BUF
0x0001A0E0       MOV R3 R5
0x0001A0E4       SVC SYS_WRITE

task_b_yield:
0x0001A0E8       SVC SYS_YIELD
0x0001A0EC       B task_b_yield

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
    .ASCIIZ "OPEN WRITE CLOSE\r\n input:> "

task_b_msg_len:
    .WORD 18

open_fail_msg:
    .ASCIIZ "OPEN FAIL\r\n"

open_fail_msg_len:
    .WORD 11


; Test program for gettime and brk
.org 0x1B000
TASK_C_START:

    ; ====================================
    ; Fork, Waitpid, and Sleep test
    ; ====================================
    ; This program demonstrates:
    ; 1. fork() - create child process
    ; 2. waitpid() - parent waits for child
    ; 3. sleep() - suspend execution for specified time
    ;
    ; Expected behavior:
    ; - Parent forks a child
    ; - Child sleeps for 2 seconds then exits
    ; - Parent waits for child and prints status
    ; - Both processes print timing information
    ; ====================================

    ; Get current time for timing.
    ; SYS_GETTIME expects R1 = user pointer to struct timeval.
0x0001B000       LI R6 USER_WRITE_BUF
0x0001B008       MOV R1 R6
0x0001B00C       SVC SYS_GETTIME
0x0001B010       CMP R1 0
0x0001B014       BLT gettime_error
0x0001B01C       LDW R4 [R6 + TIMEVAL_SEC]   ; Store start seconds in R4

    ; Fork a child process
0x0001B020       SVC SYS_FORK

0x0001B024       CMP R1 0
0x0001B028       BEQ child_process
0x0001B030       BLT fork_error
0x0001B038       MOV R5 R1          ; Parent keeps child PID

parent_process:
    ; this is to test mutex in debug in mutual printing to vy several process to console
    ; Parent process - keep both tasks active so console writes contend
0x0001B03C       LI R6 2
pr_1:
0x0001B044       cmp R6 0
0x0001B048       Beq pr_fin
0x0001B050       LI R1 STDOUT_FD
0x0001B058       LI R2 parent_wait_msg
0x0001B060       LI R3 16
0x0001B068       SVC SYS_WRITE
0x0001B06C       LI R1 1
0x0001B074       SVC SYS_SLEEP
0x0001B078       sub R6 R6 1
0x0001B07C       B   pr_1
pr_fin:

    ; Wait for child to exit
    ;MOV R1 R5           ; Child PID from fork
0x0001B084       LI R1 -1            ; wait for any
0x0001B08C       LI R2 0             ; No status pointer needed for this test
0x0001B094       SVC SYS_WAITPID

0x0001B098       CMP R1 0
0x0001B09C       BLT wait_error

    ; Child exited normally
0x0001B0A4       LI R1 STDOUT_FD
0x0001B0AC       LI R2 parent_done_msg
0x0001B0B4       LI R3 13
0x0001B0BC       SVC SYS_WRITE

    ; Print newline
0x0001B0C0       LI R1 STDOUT_FD
0x0001B0C8       LI R2 newline
0x0001B0D0       LI R3 1
0x0001B0D8       SVC SYS_WRITE

0x0001B0DC       B exit_success

wait_error:
0x0001B0E4       LI R1 STDOUT_FD
0x0001B0EC       LI R2 wait_error_msg
0x0001B0F4       LI R3 14
0x0001B0FC       SVC SYS_WRITE
0x0001B100       B exit_failure

child_process:
    ; Child process - write in a tight loop so it overlaps with parent

0x0001B108       LI R1 STDOUT_FD
0x0001B110       LI R2 child_start_msg
0x0001B118       LI R3 13
0x0001B120       SVC SYS_WRITE


    ;LI R1 echo_path
    ;LI R2 echo_argv
    ;LI R3 0

0x0001B124       LI R1 cat_path
0x0001B12C       LI R2 cat_argv
0x0001B134       LI R3 0

0x0001B13C       SVC SYS_EXECVE
    ; returns if error with execve

0x0001B140       LI R1 STDOUT_FD
0x0001B148       LI R2 exec_failed_msg
0x0001B150       LI R3 13
0x0001B158       SVC SYS_WRITE

0x0001B15C       LI R1 1
0x0001B164       SVC SYS_SLEEP


    ; Child exits with status 42
    ;LI R1 42
0x0001B168       LI R1 0
0x0001B170       SVC SYS_EXIT

sleep_error:
0x0001B174       LI R1 STDOUT_FD
0x0001B17C       LI R2 sleep_error_msg
0x0001B184       LI R3 12
0x0001B18C       SVC SYS_WRITE
0x0001B190       LI R1 1              ; Exit with error code
0x0001B198       SVC SYS_EXIT

fork_error:
0x0001B19C       LI R1 STDOUT_FD
0x0001B1A4       LI R2 fork_error_msg
0x0001B1AC       LI R3 11
0x0001B1B4       SVC SYS_WRITE
0x0001B1B8       B exit_failure

gettime_error:
0x0001B1C0       LI R1 STDOUT_FD
0x0001B1C8       LI R2 gettime_error_msg
0x0001B1D0       LI R3 14
0x0001B1D8       SVC SYS_WRITE
0x0001B1DC       B exit_failure

exit_success:
0x0001B1E4       LI R1 0
0x0001B1EC       SVC SYS_EXIT

exit_failure:
0x0001B1F0       LI R1 1
0x0001B1F8       SVC SYS_EXIT

gettime_error_msg:
    .ASCIIZ "GETTIME FAIL\r\n"

parent_wait_msg:
    .ASCIIZ "PARENT WAITING\r\n"

parent_done_msg:
    .ASCIIZ "PARENT DONE\r\n"

wait_error_msg:
    .ASCIIZ "WAITPID FAIL\r\n"

child_start_msg:
    .ASCIIZ "CHILD START\r\n"

child_end_msg:
    .ASCIIZ "CHILD DONE\r\n"

sleep_error_msg:
    .ASCIIZ "SLEEP FAIL\r\n"
exec_failed_msg:
    .ASCIIZ "EXECV FAIL\r\n"
fork_error_msg:
    .ASCIIZ "FORK FAIL\r\n"
;no first slash yet!
;==========
;cat
;==========
echo_path:
    .ASCIIZ "bin/echo"

echo_arg0:
    .ASCIIZ "echo"

echo_arg1:
    .ASCIIZ "Hello from execve!"

echo_arg2:
    .ASCIIZ "second arg!"

echo_argv:
    .WORD echo_path
    .WORD echo_arg1
    .WORD echo_arg2
    .WORD 0

;==========
;cat
;==========
cat_path:
    .ASCIIZ "bin/cat"

cat_arg0:
    .ASCIIZ "cat"

cat_arg1:
    .ASCIIZ "etc/motd"

cat_arg2:
    .ASCIIZ "lib/libc.inc"

cat_argv:
    .WORD cat_path
    .WORD cat_arg1
    .WORD cat_arg2
    .WORD 0


.ORG 0xA0000
tarfs_start:
; bin/cat, 2719 bytes
    .ASCIIZ "bin/cat"
    .SPACE 116
    .ASCIIZ "00000005237"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (2719 bytes, padded to 3072)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x000438E6, 0x10010000, 0x0F010000
    .WORD 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430A8, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x40040000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x0F080000, 0x000438E4
    .WORD 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001, 0x40040000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x0F090000, 0x00000000
    .WORD 0x20020889, 0x04020080, 0x06000000, 0x000430DC, 0x02090981, 0x05000000, 0x000430C0, 0x01810900
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000, 0x00043148, 0x040A0080
    .WORD 0x06000000, 0x00043138, 0x02080881, 0x02090981, 0x05000000, 0x00043108, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043150, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x018A0300
    .WORD 0x040A0080, 0x06000000, 0x000431A8, 0x20010900, 0x23010800, 0x02080881, 0x02090981, 0x030A0A81
    .WORD 0x05000000, 0x00043180, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x018A0300, 0x040A0080
    .WORD 0x06000000, 0x000431FC, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000, 0x000431DC, 0x01810800
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000, 0x31000000, 0x40050000
    .WORD 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043258
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x00043528, 0x0F020000, 0x00043260, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043504, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043510, 0x02040481, 0x05000000, 0x000434C0, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435A8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435A0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435A0, 0x0F020000, 0x00043260, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x00043584, 0x02040481, 0x05000000
    .WORD 0x00043544, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435A8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043614
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043614, 0x0F020000, 0x00043260, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043608, 0x02040481
    .WORD 0x05000000, 0x000435C8, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x00043260, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043658, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043630, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200
    .WORD 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000, 0x01870600, 0x040C0081
    .WORD 0x07000000, 0x000436CC, 0x04090080, 0x15000000, 0x000436CC, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x000436FC, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x0004379C, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043728, 0x020707B0
    .WORD 0x05000000, 0x00043748, 0x04070089, 0x14000000, 0x00043740, 0x020707B0, 0x05000000, 0x00043748
    .WORD 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500, 0x04090080, 0x07000000
    .WORD 0x00043704, 0x03060681, 0x04040080, 0x06000000, 0x00043790, 0x20020600, 0x23020800, 0x02080881
    .WORD 0x03060681, 0x03040481, 0x05000000, 0x00043768, 0x0F020000, 0x00000000, 0x23020800, 0x11050000
    .WORD 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043660, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043660, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043660
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x00043660, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043660, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x000438D0
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x000438AC, 0x01810300, 0x110F0000, 0x31000000, 0x31000000
    .WORD 0x000A0020, 0x00000000, 0x0000100F, 0x00001006, 0x00001007, 0x00001008, 0x00001009, 0x0000100A
    .WORD 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000, 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189
    .WORD 0x00000408, 0x3A561200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A
    .WORD 0x3A221500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00000F02, 0x00000000
    .WORD 0x32243000, 0x01000004, 0x0080018B, 0x0000040B, 0x39D61200, 0x0B000004, 0x0C000181, 0x00000182
    .WORD 0x01000F03, 0x00000000, 0x321C3000, 0x01000004, 0x00800187, 0x00000407, 0x39BE1300, 0x00000004
    .WORD 0x00010F01, 0x0C000000, 0x07000182, 0x00000183, 0x32143000, 0x00000004, 0x39760500, 0x0B000004
    .WORD 0x00000181, 0x322C3000, 0x0A810004, 0x0000020A, 0x393A0500, 0x00000004, 0x3A8B0F01, 0x00000004
    .WORD 0x30303000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30303000, 0x00000004
    .WORD 0x38E20F01, 0x00000004, 0x30303000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x393A0500
    .WORD 0x00000004, 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x3A760F01, 0x00000004
    .WORD 0x30303000, 0x00000004, 0x00010F06, 0x00000000, 0x3A220500, 0x73750004, 0x3A656761, 0x74616320
    .WORD 0x6C696620, 0x2E2E2065, 0x63000A2E, 0x203A7461, 0x6E6E6163, 0x6F20746F, 0x206E6570, 0x00000A00
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/echo, 2438 bytes
    .ASCIIZ "bin/echo"
    .SPACE 115
    .ASCIIZ "00000004606"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (2438 bytes, padded to 2560)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x000438E6, 0x10010000, 0x0F010000
    .WORD 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430A8, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x40040000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x0F080000, 0x000438E4
    .WORD 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001, 0x40040000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x0F090000, 0x00000000
    .WORD 0x20020889, 0x04020080, 0x06000000, 0x000430DC, 0x02090981, 0x05000000, 0x000430C0, 0x01810900
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000, 0x00043148, 0x040A0080
    .WORD 0x06000000, 0x00043138, 0x02080881, 0x02090981, 0x05000000, 0x00043108, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043150, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x018A0300
    .WORD 0x040A0080, 0x06000000, 0x000431A8, 0x20010900, 0x23010800, 0x02080881, 0x02090981, 0x030A0A81
    .WORD 0x05000000, 0x00043180, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x018A0300, 0x040A0080
    .WORD 0x06000000, 0x000431FC, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000, 0x000431DC, 0x01810800
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000, 0x31000000, 0x40050000
    .WORD 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043258
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x00043528, 0x0F020000, 0x00043260, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043504, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043510, 0x02040481, 0x05000000, 0x000434C0, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435A8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435A0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435A0, 0x0F020000, 0x00043260, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x00043584, 0x02040481, 0x05000000
    .WORD 0x00043544, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435A8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043614
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043614, 0x0F020000, 0x00043260, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043608, 0x02040481
    .WORD 0x05000000, 0x000435C8, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x00043260, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043658, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043630, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200
    .WORD 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000, 0x01870600, 0x040C0081
    .WORD 0x07000000, 0x000436CC, 0x04090080, 0x15000000, 0x000436CC, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x000436FC, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x0004379C, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043728, 0x020707B0
    .WORD 0x05000000, 0x00043748, 0x04070089, 0x14000000, 0x00043740, 0x020707B0, 0x05000000, 0x00043748
    .WORD 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500, 0x04090080, 0x07000000
    .WORD 0x00043704, 0x03060681, 0x04040080, 0x06000000, 0x00043790, 0x20020600, 0x23020800, 0x02080881
    .WORD 0x03060681, 0x03040481, 0x05000000, 0x00043768, 0x0F020000, 0x00000000, 0x23020800, 0x11050000
    .WORD 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043660, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043660, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043660
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x00043660, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043660, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x000438D0
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x000438AC, 0x01810300, 0x110F0000, 0x31000000, 0x31000000
    .WORD 0x000A0020, 0x00000000, 0x00020000, 0x00005600, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A
    .WORD 0x02000188, 0x00000189, 0x00010F0A, 0x09000000, 0x0B84018B, 0x0800020B, 0x0000040A, 0x396A1500
    .WORD 0x0B000004, 0x00002201, 0x30303000, 0x0A810004, 0x0B84020A, 0x0800020B, 0x0000040A, 0x395A1500
    .WORD 0x00000004, 0x38E00F01, 0x00000004, 0x30303000, 0x00000004, 0x39160500, 0x00000004, 0x38E20F01
    .WORD 0x00000004, 0x30303000, 0x00000004, 0x00000F01, 0x00000000, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x0000110F, 0x00003100, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; etc/motd, 16 bytes
    .ASCIIZ "etc/motd"
    .SPACE 115
    .ASCIIZ "00000000020"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (16 bytes, padded to 512)
    .WORD 0x636C6557, 0x20656D6F, 0x4B206F74, 0x0A323352, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; lib/libc.inc, 24803 bytes
    .ASCIIZ "lib/libc.inc"
    .SPACE 111
    .ASCIIZ "00000060343"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (24803 bytes, padded to 25088)
    .WORD 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x694D203B, 0x616D696E, 0x524B206C, 0x75203233
    .WORD 0x6C726573, 0x20646E61, 0x6362696C, 0x61637320, 0x6C6F6666, 0x203B0A64, 0x65746E49, 0x6465646E
    .WORD 0x206F7420, 0x69206562, 0x756C636E, 0x20646564, 0x75207962, 0x20726573, 0x616E6962, 0x73656972
    .WORD 0x66656220, 0x2065726F, 0x65737361, 0x796C626D, 0x203B0A2E, 0x69757266, 0x6C207974, 0x73706F6F
    .WORD 0x20666F20, 0x2072756F, 0x72657375, 0x646E616C, 0x6F727020, 0x6D617267, 0x0A292D73, 0x3D3D3D3B
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x53203B0A
    .WORD 0x65747379, 0x6143206D, 0x4E206C6C, 0x65626D75, 0x3B0A7372, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x2E0A3D3D, 0x20555145, 0x5F535953, 0x4C454959, 0x20202C44, 0x452E0A30, 0x53205551, 0x455F5359
    .WORD 0x2C544958, 0x31202020, 0x51452E0A, 0x59532055, 0x45475F53, 0x44495054, 0x0A32202C, 0x5551452E
    .WORD 0x53595320, 0x4245445F, 0x202C4755, 0x2E0A3320, 0x20555145, 0x5F535953, 0x54495257, 0x20202C45
    .WORD 0x452E0A34, 0x53205551, 0x525F5359, 0x2C444145, 0x35202020, 0x51452E0A, 0x59532055, 0x504F5F53
    .WORD 0x202C4E45, 0x0A362020, 0x5551452E, 0x53595320, 0x4F4C435F, 0x202C4553, 0x2E0A3720, 0x20555145
    .WORD 0x5F535953, 0x45504950, 0x2020202C, 0x452E0A38, 0x53205551, 0x445F5359, 0x202C5055, 0x39202020
    .WORD 0x51452E0A, 0x59532055, 0x45475F53, 0x4D495454, 0x31202C45, 0x452E0A30, 0x53205551, 0x425F5359
    .WORD 0x202C4B52, 0x31202020, 0x452E0A31, 0x53205551, 0x535F5359, 0x2C4B5242, 0x31202020, 0x452E0A32
    .WORD 0x53205551, 0x455F5359, 0x56434558, 0x31202C45, 0x452E0A33, 0x53205551, 0x465F5359, 0x2C4B524F
    .WORD 0x31202020, 0x452E0A34, 0x53205551, 0x535F5359, 0x5045454C, 0x3120202C, 0x452E0A35, 0x53205551
    .WORD 0x575F5359, 0x50544941, 0x202C4449, 0x0A0A3631, 0x5551452E, 0x44545320, 0x5F54554F, 0x202C4446
    .WORD 0x3B0A0A31, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x74735F20, 0x20747261, 0x7250202D
    .WORD 0x6172676F, 0x6E65206D, 0x20797274, 0x6E696F70, 0x203B0A74, 0x203A4E49, 0x67726120, 0x74612063
    .WORD 0x50535B20, 0x61202C5D, 0x20766772, 0x5B207461, 0x342B5053, 0x203B0A5D, 0x3A54554F, 0x76654E20
    .WORD 0x72207265, 0x72757465, 0x2D20736E, 0x6C616320, 0x5320736C, 0x455F5359, 0x20544958, 0x68746977
    .WORD 0x69616D20, 0x2073276E, 0x75746572, 0x76206E72, 0x65756C61, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x74735F0A, 0x3A747261, 0x2020200A, 0x57444C20, 0x20315220, 0x5D50535B, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x63677261, 0x2020200A, 0x44444120, 0x20325220, 0x34205053, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x76677261, 0x2020200A, 0x20494C20, 0x30203352, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x70766E65, 0x4E203D20, 0x0A4C4C55, 0x20202020, 0x6D204C42, 0x0A6E6961
    .WORD 0x20202020, 0x48535550, 0x20315220, 0x20202020, 0x20202020, 0x20202020, 0x65203B20, 0x20746978
    .WORD 0x202D2030, 0x63637573, 0x20737365, 0x202D2031, 0x6F727265, 0x20200A72, 0x494C2020, 0x20315220
    .WORD 0x20202031, 0x20202020, 0x20202020, 0x3B202020, 0x74757020, 0x206F7420, 0x65656C73, 0x6F732070
    .WORD 0x72617020, 0x20746E65, 0x74696177, 0x20646970, 0x206E6163, 0x6B726F77, 0x2020200A, 0x43565320
    .WORD 0x53595320, 0x454C535F, 0x200A5045, 0x50202020, 0x2020504F, 0x200A3152, 0x3B202020, 0x5220494C
    .WORD 0x32342031, 0x2020200A, 0x43565320, 0x53595320, 0x4958455F, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3B0A3D3D, 0x74757020, 0x202D2073, 0x74697257, 0x756E2065, 0x742D6C6C, 0x696D7265
    .WORD 0x6574616E, 0x74732064, 0x676E6972, 0x206F7420, 0x6F647473, 0x77207475, 0x20687469, 0x6C77656E
    .WORD 0x0A656E69, 0x4E49203B, 0x5220203A, 0x203D2031, 0x69727473, 0x7020676E, 0x746E696F, 0x3B0A7265
    .WORD 0x54554F20, 0x3152203A, 0x62203D20, 0x73657479, 0x69727720, 0x6E657474, 0x20726F20, 0x6F727265
    .WORD 0x6F632072, 0x3B0A6564, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x700A3D3D, 0x3A737475, 0x2020200A
    .WORD 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048
    .WORD 0x2020200A, 0x564F4D20, 0x20385220, 0x20203152, 0x20202020, 0x20202020, 0x203B2020, 0x65766153
    .WORD 0x72747320, 0x20676E69, 0x6E696F70, 0x0A726574, 0x20202020, 0x73204C42, 0x656C7274, 0x2020206E
    .WORD 0x20202020, 0x20202020, 0x47203B20, 0x73207465, 0x6E697274, 0x656C2067, 0x6874676E, 0x2020200A
    .WORD 0x564F4D20, 0x20395220, 0x20203152, 0x20202020, 0x20202020, 0x203B2020, 0x65766153, 0x6E656C20
    .WORD 0x0A687467, 0x20202020, 0x5220494C, 0x54532031, 0x54554F44, 0x0A44465F, 0x20202020, 0x20564F4D
    .WORD 0x52203252, 0x20202038, 0x20202020, 0x20202020, 0x42203B20, 0x65666675, 0x203D2072, 0x69727473
    .WORD 0x200A676E, 0x4D202020, 0x5220564F, 0x39522033, 0x20202020, 0x20202020, 0x20202020, 0x6F43203B
    .WORD 0x20746E75, 0x656C203D, 0x6874676E, 0x2020200A, 0x43565320, 0x53595320, 0x4952575F, 0x200A4554
    .WORD 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20
    .WORD 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x70203B0A, 0x68637475
    .WORD 0x2D207261, 0x69725720, 0x73206574, 0x6C676E69, 0x68632065, 0x63617261, 0x20726574, 0x73206F74
    .WORD 0x756F6474, 0x203B0A74, 0x203A4E49, 0x20315220, 0x6863203D, 0x63617261, 0x0A726574, 0x554F203B
    .WORD 0x52203A54, 0x203D2031, 0x65747962, 0x72772073, 0x65747469, 0x3128206E, 0x726F2029, 0x72726520
    .WORD 0x6320726F, 0x0A65646F, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x63747570, 0x3A726168
    .WORD 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x20494C20
    .WORD 0x63203852, 0x75625F68, 0x20200A66, 0x54532020, 0x31522042, 0x38525B20, 0x2020205D, 0x20202020
    .WORD 0x3B202020, 0x6F745320, 0x63206572, 0x20726168, 0x73206E69, 0x69746174, 0x75622063, 0x72656666
    .WORD 0x2020200A, 0x20494C20, 0x53203152, 0x554F4454, 0x44465F54, 0x2020200A, 0x564F4D20, 0x20325220
    .WORD 0x200A3852, 0x4C202020, 0x33522049, 0x200A3120, 0x53202020, 0x53204356, 0x575F5359, 0x45544952
    .WORD 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x7473203B, 0x6E656C72, 0x43202D20, 0x75636C61
    .WORD 0x6574616C, 0x72747320, 0x20676E69, 0x676E656C, 0x3B0A6874, 0x3A4E4920, 0x31522020, 0x73203D20
    .WORD 0x6E697274, 0x6F702067, 0x65746E69, 0x203B0A72, 0x3A54554F, 0x20315220, 0x656C203D, 0x6874676E
    .WORD 0x78652820, 0x64756C63, 0x20676E69, 0x6C6C756E, 0x72657420, 0x616E696D, 0x29726F74, 0x3D3D3B0A
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x7274730A, 0x3A6E656C, 0x2020200A, 0x53555020, 0x524C2048
    .WORD 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x564F4D20
    .WORD 0x20385220, 0x200A3152, 0x4C202020, 0x39522049, 0x730A3020, 0x656C7274, 0x6F6C5F6E, 0x0A3A706F
    .WORD 0x20202020, 0x2042444C, 0x5B203252, 0x2B203852, 0x5D395220, 0x20202020, 0x52203B20, 0x20646165
    .WORD 0x72616863, 0x65746361, 0x74612072, 0x72756320, 0x746E6572, 0x66666F20, 0x0A746573, 0x20202020
    .WORD 0x20504D43, 0x30203252, 0x2020200A, 0x51454220, 0x72747320, 0x5F6E656C, 0x656E6F64, 0x2020200A
    .WORD 0x44444120, 0x20395220, 0x31203952, 0x20202020, 0x20202020, 0x203B2020, 0x72636E49, 0x6E656D65
    .WORD 0x6F632074, 0x65746E75, 0x20200A72, 0x20422020, 0x6C727473, 0x6C5F6E65, 0x0A706F6F, 0x6C727473
    .WORD 0x645F6E65, 0x3A656E6F, 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3952, 0x50202020, 0x5220504F
    .WORD 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x73203B0A, 0x6D637274, 0x202D2070, 0x706D6F43
    .WORD 0x20657261, 0x206F7774, 0x69727473, 0x0A73676E, 0x4E49203B, 0x5220203A, 0x203D2031, 0x69727473
    .WORD 0x2C31676E, 0x20325220, 0x7473203D, 0x676E6972, 0x203B0A32, 0x3A54554F, 0x20315220, 0x2031203D
    .WORD 0x65206669, 0x6C617571, 0x2030202C, 0x64206669, 0x65666669, 0x746E6572, 0x3D3D3B0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x7274730A, 0x3A706D63, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x53555020, 0x31522048
    .WORD 0x20200A30, 0x4F4D2020, 0x38522056, 0x0A315220, 0x20202020, 0x20564F4D, 0x52203952, 0x74730A32
    .WORD 0x706D6372, 0x6F6F6C5F, 0x200A3A70, 0x4C202020, 0x52204244, 0x5B203031, 0x205D3852, 0x20202020
    .WORD 0x20202020, 0x6F4C203B, 0x63206461, 0x20726168, 0x6D6F7266, 0x72747320, 0x31676E69, 0x2020200A
    .WORD 0x42444C20, 0x20315220, 0x5D39525B, 0x20202020, 0x20202020, 0x203B2020, 0x64616F4C, 0x61686320
    .WORD 0x72662072, 0x73206D6F, 0x6E697274, 0x200A3267, 0x43202020, 0x5220504D, 0x52203031, 0x20200A31
    .WORD 0x4E422020, 0x74732045, 0x706D6372, 0x20656E5F, 0x20202020, 0x3B202020, 0x73694D20, 0x6374616D
    .WORD 0x6F662068, 0x0A646E75, 0x20202020, 0x20504D43, 0x20303152, 0x20200A30, 0x45422020, 0x74732051
    .WORD 0x706D6372, 0x2071655F, 0x20202020, 0x3B202020, 0x746F4220, 0x74732068, 0x676E6972, 0x6E652073
    .WORD 0x20646564, 0x73207461, 0x20656D61, 0x656D6974, 0x2020200A, 0x44444120, 0x20385220, 0x31203852
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x61766441, 0x2065636E, 0x68746F62, 0x696F7020, 0x7265746E
    .WORD 0x20200A73, 0x44412020, 0x39522044, 0x20395220, 0x20200A31, 0x20422020, 0x63727473, 0x6C5F706D
    .WORD 0x0A706F6F, 0x63727473, 0x655F706D, 0x200A3A71, 0x4C202020, 0x31522049, 0x200A3120, 0x42202020
    .WORD 0x72747320, 0x5F706D63, 0x656E6F64, 0x7274730A, 0x5F706D63, 0x0A3A656E, 0x20202020, 0x5220494C
    .WORD 0x0A302031, 0x63727473, 0x645F706D, 0x3A656E6F, 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A
    .WORD 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52
    .WORD 0x45522020, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x6D656D20, 0x20797063
    .WORD 0x6F43202D, 0x6D207970, 0x726F6D65, 0x6C622079, 0x0A6B636F, 0x4E49203B, 0x5220203A, 0x203D2031
    .WORD 0x74736564, 0x3252202C, 0x73203D20, 0x202C6372, 0x3D203352, 0x756F6320, 0x3B0A746E, 0x54554F20
    .WORD 0x3152203A, 0x64203D20, 0x20747365, 0x646E6528, 0x736F7020, 0x6F697469, 0x3B0A296E, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x6D0A3D3D, 0x70636D65, 0x200A3A79, 0x50202020, 0x20485355, 0x200A524C
    .WORD 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x50202020, 0x20485355
    .WORD 0x0A303152, 0x20202020, 0x20564F4D, 0x52203852, 0x20200A31, 0x4F4D2020, 0x39522056, 0x0A325220
    .WORD 0x20202020, 0x20564F4D, 0x20303152, 0x6D0A3352, 0x70636D65, 0x6F6C5F79, 0x0A3A706F, 0x20202020
    .WORD 0x20504D43, 0x20303152, 0x20200A30, 0x45422020, 0x656D2051, 0x7970636D, 0x6E6F645F, 0x20200A65
    .WORD 0x444C2020, 0x31522042, 0x39525B20, 0x2020205D, 0x20202020, 0x3B202020, 0x61655220, 0x79622064
    .WORD 0x66206574, 0x206D6F72, 0x72756F73, 0x200A6563, 0x53202020, 0x52204254, 0x525B2031, 0x20205D38
    .WORD 0x20202020, 0x20202020, 0x7257203B, 0x20657469, 0x65747962, 0x206F7420, 0x74736564, 0x74616E69
    .WORD 0x0A6E6F69, 0x20202020, 0x20444441, 0x52203852, 0x20312038, 0x20202020, 0x20202020, 0x41203B20
    .WORD 0x6E617664, 0x62206563, 0x2068746F, 0x6E696F70, 0x73726574, 0x2020200A, 0x44444120, 0x20395220
    .WORD 0x31203952, 0x2020200A, 0x42555320, 0x30315220, 0x30315220, 0x20203120, 0x20202020, 0x203B2020
    .WORD 0x72636544, 0x6E656D65, 0x6F632074, 0x65746E75, 0x20200A72, 0x20422020, 0x636D656D, 0x6C5F7970
    .WORD 0x0A706F6F, 0x636D656D, 0x645F7970, 0x3A656E6F, 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3852
    .WORD 0x50202020, 0x5220504F, 0x200A3031, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050
    .WORD 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x6D203B0A, 0x65736D65, 0x202D2074, 0x6C6C6946, 0x6D656D20, 0x2079726F, 0x68746977
    .WORD 0x6E6F6320, 0x6E617473, 0x79622074, 0x3B0A6574, 0x3A4E4920, 0x31522020, 0x64203D20, 0x2C747365
    .WORD 0x20325220, 0x6176203D, 0x2C65756C, 0x20335220, 0x6F63203D, 0x0A746E75, 0x554F203B, 0x52203A54
    .WORD 0x203D2031, 0x74736564, 0x6E652820, 0x6F702064, 0x69746973, 0x0A296E6F, 0x3D3D3D3B, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x0A3D3D3D, 0x736D656D, 0x0A3A7465, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020
    .WORD 0x48535550, 0x0A385220, 0x20202020, 0x48535550, 0x0A395220, 0x20202020, 0x48535550, 0x30315220
    .WORD 0x2020200A, 0x564F4D20, 0x20385220, 0x200A3152, 0x4D202020, 0x5220564F, 0x32522039, 0x2020200A
    .WORD 0x564F4D20, 0x30315220, 0x0A335220, 0x736D656D, 0x6C5F7465, 0x3A706F6F, 0x2020200A, 0x504D4320
    .WORD 0x30315220, 0x200A3020, 0x42202020, 0x6D205145, 0x65736D65, 0x6F645F74, 0x200A656E, 0x53202020
    .WORD 0x52204254, 0x525B2039, 0x20205D38, 0x20202020, 0x20202020, 0x7453203B, 0x2065726F, 0x756C6176
    .WORD 0x74612065, 0x72756320, 0x746E6572, 0x736F7020, 0x6F697469, 0x20200A6E, 0x44412020, 0x38522044
    .WORD 0x20385220, 0x20202031, 0x20202020, 0x3B202020, 0x76644120, 0x65636E61, 0x696F7020, 0x7265746E
    .WORD 0x2020200A, 0x42555320, 0x30315220, 0x30315220, 0x20203120, 0x20202020, 0x203B2020, 0x72636544
    .WORD 0x6E656D65, 0x6F632074, 0x65746E75, 0x20200A72, 0x20422020, 0x736D656D, 0x6C5F7465, 0x0A706F6F
    .WORD 0x736D656D, 0x645F7465, 0x3A656E6F, 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3852, 0x50202020
    .WORD 0x5220504F, 0x200A3031, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A
    .WORD 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x77203B0A, 0x65746972, 0x2C646628, 0x66756220, 0x656C202C, 0x3B0A296E, 0x49203B0A, 0x3B0A3A4E
    .WORD 0x52202020, 0x203D2031, 0x3B0A6466, 0x52202020, 0x203D2032, 0x66667562, 0x3B0A7265, 0x52202020
    .WORD 0x203D2033, 0x676E656C, 0x3B0A6874, 0x4F203B0A, 0x0A3A5455, 0x2020203B, 0x3D203152, 0x74796220
    .WORD 0x77207365, 0x74746972, 0x2F206E65, 0x72726520, 0x3B0A6F6E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x770A2D2D, 0x65746972, 0x20200A3A, 0x56532020, 0x59532043, 0x52575F53, 0x0A455449, 0x20202020
    .WORD 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x64616572, 0x2C646628
    .WORD 0x66756220, 0x656C202C, 0x3B0A296E, 0x49203B0A, 0x3B0A3A4E, 0x52202020, 0x203D2031, 0x3B0A6466
    .WORD 0x52202020, 0x203D2032, 0x66667562, 0x3B0A7265, 0x52202020, 0x203D2033, 0x676E656C, 0x3B0A6874
    .WORD 0x4F203B0A, 0x0A3A5455, 0x2020203B, 0x3D203152, 0x74796220, 0x72207365, 0x0A646165, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x64616572, 0x20200A3A, 0x56532020, 0x59532043, 0x45525F53
    .WORD 0x200A4441, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F203B0A
    .WORD 0x286E6570, 0x68746170, 0x6C66202C, 0x29736761, 0x3B0A3B0A, 0x3A4E4920, 0x20203B0A, 0x20315220
    .WORD 0x6170203D, 0x3B0A6874, 0x52202020, 0x203D2032, 0x67616C66, 0x0A3B0A73, 0x554F203B, 0x3B0A3A54
    .WORD 0x52202020, 0x203D2031, 0x3B0A6466, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F0A2D2D, 0x3A6E6570
    .WORD 0x2020200A, 0x43565320, 0x53595320, 0x45504F5F, 0x20200A4E, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6C63203B, 0x2865736F, 0x0A296466, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x736F6C63, 0x200A3A65, 0x53202020, 0x53204356, 0x435F5359, 0x45534F4C
    .WORD 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x726F6620
    .WORD 0x0A29286B, 0x203B0A3B, 0x65726170, 0x0A3A746E, 0x2020203B, 0x3D203152, 0x69686320, 0x7020646C
    .WORD 0x3B0A6469, 0x63203B0A, 0x646C6968, 0x203B0A3A, 0x31522020, 0x30203D20, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x726F660A, 0x200A3A6B, 0x53202020, 0x53204356, 0x465F5359, 0x0A4B524F
    .WORD 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x63657865
    .WORD 0x70286576, 0x2C687461, 0x67726120, 0x65202C76, 0x2970766E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6578650A, 0x3A657663, 0x2020200A, 0x43565320, 0x53595320, 0x4558455F, 0x0A455643
    .WORD 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x74696177
    .WORD 0x28646970, 0x2C646970, 0x74617473, 0x0A297375, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x74696177, 0x3A646970, 0x2020200A, 0x43565320, 0x53595320, 0x4941575F, 0x44495054, 0x2020200A
    .WORD 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x656C7320, 0x6D287065
    .WORD 0x696C6C69, 0x6F636573, 0x2973646E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x656C730A
    .WORD 0x0A3A7065, 0x20202020, 0x20435653, 0x5F535953, 0x45454C53, 0x20200A50, 0x45522020, 0x0A0A0A54
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7865203B, 0x73287469, 0x75746174, 0x3B0A2973
    .WORD 0x6E203B0A, 0x72657665, 0x74657220, 0x736E7275, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6978650A, 0x200A3A74, 0x53202020, 0x53204356, 0x455F5359, 0x0A544958, 0x6978650A, 0x61685F74
    .WORD 0x0A3A676E, 0x20202020, 0x78652042, 0x685F7469, 0x0A676E61, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x203B0A3D, 0x4F4D454D, 0x4D205952, 0x47414E41, 0x4E454D45, 0x3D3B0A54, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A0A3D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x52455620
    .WORD 0x49532059, 0x454C504D, 0x4D454D20, 0x2059524F, 0x4F4C4C41, 0x4F544143, 0x0A3B0A52, 0x6854203B
    .WORD 0x69207369, 0x20612073, 0x696E696D, 0x206C616D, 0x6C6C616D, 0x662F636F, 0x20656572, 0x6C706D69
    .WORD 0x6E656D65, 0x69746174, 0x74206E6F, 0x3A746168, 0x31203B0A, 0x7355202E, 0x61207365, 0x78696620
    .WORD 0x61206465, 0x79617272, 0x206F7420, 0x63617274, 0x656D206B, 0x79726F6D, 0x6F6C6220, 0x0A736B63
    .WORD 0x2E32203B, 0x656F4420, 0x4F4E2073, 0x6F632054, 0x73656C61, 0x28206563, 0x6772656D, 0x64612065
    .WORD 0x6563616A, 0x6620746E, 0x20656572, 0x636F6C62, 0x0A29736B, 0x2E33203B, 0x656F4420, 0x4F4E2073
    .WORD 0x70732054, 0x2074696C, 0x636F6C62, 0x2820736B, 0x73657375, 0x746E6520, 0x20657269, 0x636F6C62
    .WORD 0x7361206B, 0x2973692D, 0x34203B0A, 0x7355202E, 0x66207365, 0x74737269, 0x7469662D, 0x61657320
    .WORD 0x20686372, 0x6E696628, 0x66207364, 0x74737269, 0x6F6C6220, 0x74206B63, 0x27746168, 0x69622073
    .WORD 0x6E652067, 0x6867756F, 0x203B0A29, 0x55202E35, 0x20736573, 0x6B726273, 0x73797320, 0x6C6C6163
    .WORD 0x206F7420, 0x20746567, 0x65726F6D, 0x6D656D20, 0x2079726F, 0x6D6F7266, 0x72656B20, 0x0A6C656E
    .WORD 0x203B0A3B, 0x64617254, 0x666F2D65, 0x0A3A7366, 0x202B203B, 0x79726556, 0x6D697320, 0x20656C70
    .WORD 0x20646E61, 0x79736165, 0x206F7420, 0x65646E75, 0x61747372, 0x3B0A646E, 0x50202B20, 0x69646572
    .WORD 0x62617463, 0x6D20656C, 0x726F6D65, 0x73752079, 0x20656761, 0x78696628, 0x74206465, 0x656C6261
    .WORD 0x203B0A29, 0x6F4E202B, 0x6D6F6320, 0x78656C70, 0x6E696C20, 0x2064656B, 0x7473696C, 0x6E616D20
    .WORD 0x6D656761, 0x0A746E65, 0x202D203B, 0x6F6D654D, 0x66207972, 0x6D676172, 0x61746E65, 0x6E6F6974
    .WORD 0x61632820, 0x2074276E, 0x6772656D, 0x72662065, 0x62206565, 0x6B636F6C, 0x3B0A2973, 0x57202D20
    .WORD 0x65747361, 0x70732064, 0x20656361, 0x6E616328, 0x73207427, 0x74696C70, 0x72616C20, 0x62206567
    .WORD 0x6B636F6C, 0x3B0A2973, 0x4C202D20, 0x74696D69, 0x74206465, 0x414D206F, 0x4C425F58, 0x534B434F
    .WORD 0x6C6C6120, 0x7461636F, 0x736E6F69, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x534E4F43, 0x544E4154, 0x2D3B0A53, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2E0A0A2D, 0x20555145, 0x5F58414D, 0x434F4C42, 0x202C534B, 0x20203834
    .WORD 0x20202020, 0x4D203B20, 0x6D697861, 0x6E206D75, 0x65626D75, 0x666F2072, 0x6F6C6220, 0x20736B63
    .WORD 0x63206577, 0x74206E61, 0x6B636172, 0x2020200A, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x61632820, 0x2074276E, 0x6F6C6C61, 0x65746163, 0x726F6D20, 0x68742065
    .WORD 0x33206E61, 0x69742032, 0x2073656D, 0x68746977, 0x2074756F, 0x65657266, 0x29676E69, 0x203B0A0A
    .WORD 0x636F6C42, 0x6564206B, 0x69726373, 0x726F7470, 0x66666F20, 0x73746573, 0x61652820, 0x62206863
    .WORD 0x6B636F6C, 0x65656E20, 0x74207364, 0x65736568, 0x76203320, 0x65756C61, 0x2E0A2973, 0x20555145
    .WORD 0x434F4C42, 0x44415F4B, 0x202C5244, 0x20203020, 0x20202020, 0x4F203B20, 0x65736666, 0x73203A74
    .WORD 0x74726174, 0x20676E69, 0x72646461, 0x20737365, 0x7420666F, 0x62206568, 0x6B636F6C, 0x20342820
    .WORD 0x65747962, 0x2E0A2973, 0x20555145, 0x434F4C42, 0x49535F4B, 0x202C455A, 0x20203420, 0x20202020
    .WORD 0x4F203B20, 0x65736666, 0x73203A74, 0x20657A69, 0x7420666F, 0x62206568, 0x6B636F6C, 0x206E6920
    .WORD 0x65747962, 0x34282073, 0x74796220, 0x20297365, 0x452E0A20, 0x42205551, 0x4B434F4C, 0x4553555F
    .WORD 0x20202C44, 0x20202038, 0x20202020, 0x664F203B, 0x74657366, 0x3D30203A, 0x65657266, 0x3D31202C
    .WORD 0x64657375, 0x20342820, 0x65747962, 0x2E0A2973, 0x20555145, 0x434F4C42, 0x45445F4B, 0x202C4353
    .WORD 0x20323120, 0x20202020, 0x54203B20, 0x6C61746F, 0x7A697320, 0x666F2065, 0x656E6F20, 0x6F6C6220
    .WORD 0x64206B63, 0x72637365, 0x6F747069, 0x33282072, 0x726F7720, 0x3D207364, 0x20323120, 0x65747962
    .WORD 0x0A0A2973, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x4144203B, 0x53204154, 0x49544345
    .WORD 0x2D204E4F, 0x65685420, 0x6F6C6220, 0x74206B63, 0x656C6261, 0x203B0A20, 0x6D726F6E, 0x796C6C61
    .WORD 0x6D656D20, 0x2079726F, 0x636F6C62, 0x6720736B, 0x72207465, 0x72657365, 0x64657665, 0x6F726620
    .WORD 0x4548206D, 0x77205041, 0x68636968, 0x20736920, 0x61636F6C, 0x20646574, 0x64207461, 0x20617461
    .WORD 0x6D676573, 0x20746E65, 0x70203B0A, 0x20656761, 0x67617028, 0x64612065, 0x73657264, 0x70732073
    .WORD 0x66696365, 0x20646569, 0x75207361, 0x5F726573, 0x61746164, 0x2961765F, 0x2D3B0A20, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x620A0A2D, 0x6B636F6C, 0x6261745F, 0x0A3A656C, 0x20202020, 0x6854203B
    .WORD 0x69207369, 0x6E612073, 0x72726120, 0x6F207961, 0x414D2066, 0x4C425F58, 0x534B434F, 0x73656420
    .WORD 0x70697263, 0x73726F74, 0x20200A2E, 0x203B2020, 0x68636145, 0x73656420, 0x70697263, 0x20726F74
    .WORD 0x3A736168, 0x64646120, 0x73736572, 0x6973202C, 0x202C657A, 0x64657375, 0x616C665F, 0x20200A67
    .WORD 0x203B2020, 0x61746F54, 0x6973206C, 0x203A657A, 0x5F58414D, 0x434F4C42, 0x2A20534B, 0x20323120
    .WORD 0x65747962, 0x20200A73, 0x532E2020, 0x45434150, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x4C42202A
    .WORD 0x5F4B434F, 0x43534544, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6C6C616D
    .WORD 0x7328636F, 0x29657A69, 0x3B0A3B0A, 0x6C6C4120, 0x7461636F, 0x6D207365, 0x726F6D65, 0x72662079
    .WORD 0x74206D6F, 0x68206568, 0x2E706165, 0x3B0A3B0A, 0x776F4820, 0x20746920, 0x6B726F77, 0x3B0A3A73
    .WORD 0x202E3120, 0x67696C41, 0x6874206E, 0x65722065, 0x73657571, 0x20646574, 0x657A6973, 0x206F7420
    .WORD 0x79622038, 0x20736574, 0x6B616D28, 0x6D207365, 0x726F6D65, 0x616D2079, 0x6567616E, 0x746E656D
    .WORD 0x73616520, 0x29726569, 0x32203B0A, 0x6553202E, 0x68637261, 0x65687420, 0x6F6C6220, 0x74206B63
    .WORD 0x656C6261, 0x726F6620, 0x66206120, 0x20656572, 0x636F6C62, 0x6874206B, 0x73277461, 0x72616C20
    .WORD 0x65206567, 0x67756F6E, 0x203B0A68, 0x49202E33, 0x6F662066, 0x2C646E75, 0x72616D20, 0x7469206B
    .WORD 0x20736120, 0x64657375, 0x646E6120, 0x74657220, 0x206E7275, 0x20737469, 0x72646461, 0x0A737365
    .WORD 0x2E34203B, 0x20664920, 0x20746F6E, 0x6E756F66, 0x61202C64, 0x74206B73, 0x6B206568, 0x656E7265
    .WORD 0x6F66206C, 0x6F6D2072, 0x6D206572, 0x726F6D65, 0x69762079, 0x62732061, 0x73206B72, 0x61637379
    .WORD 0x3B0A6C6C, 0x202E3520, 0x20646441, 0x20656874, 0x2077656E, 0x6F6D656D, 0x74207972, 0x6874206F
    .WORD 0x6C622065, 0x206B636F, 0x6C626174, 0x6E612065, 0x65722064, 0x6E727574, 0x0A746920, 0x203B0A3B
    .WORD 0x75706E49, 0x20203A74, 0x3D203152, 0x7A697320, 0x6E692065, 0x74796220, 0x28207365, 0x2E672E65
    .WORD 0x3031202C, 0x3B0A2930, 0x74754F20, 0x3A747570, 0x20315220, 0x6F70203D, 0x65746E69, 0x6F742072
    .WORD 0x6C6C6120, 0x7461636F, 0x6D206465, 0x726F6D65, 0x6F282079, 0x20302072, 0x66206669, 0x656C6961
    .WORD 0x3B0A2964, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6D0A2D2D, 0x6F6C6C61, 0x200A3A63, 0x3B202020
    .WORD 0x76615320, 0x65722065, 0x74736967, 0x20737265, 0x6C276577, 0x7375206C, 0x73282065, 0x6577206F
    .WORD 0x6E6F6420, 0x63207427, 0x7572726F, 0x63207470, 0x656C6C61, 0x20732772, 0x756C6176, 0x0A297365
    .WORD 0x20202020, 0x48535550, 0x20524C20, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x65766153
    .WORD 0x74657220, 0x206E7275, 0x72646461, 0x0A737365, 0x20202020, 0x2020200A, 0x53203B20, 0x20706574
    .WORD 0x41203A31, 0x6E67696C, 0x7A697320, 0x6F742065, 0x6C756D20, 0x6C706974, 0x666F2065, 0x62203820
    .WORD 0x73657479, 0x2020200A, 0x57203B20, 0x203F7968, 0x796E614D, 0x55504320, 0x6F772073, 0x66206B72
    .WORD 0x65747361, 0x69772072, 0x61206874, 0x6E67696C, 0x6D206465, 0x726F6D65, 0x20200A79, 0x203B2020
    .WORD 0x6D617845, 0x3A656C70, 0x7A697320, 0x30313D65, 0x20200A30, 0x203B2020, 0x44412020, 0x31522044
    .WORD 0x20203720, 0x3E2D2020, 0x37303120, 0x2020200A, 0x20203B20, 0x444E4120, 0x46783020, 0x46464646
    .WORD 0x20384646, 0x31203E2D, 0x28203430, 0x746C756D, 0x656C7069, 0x20666F20, 0x200A2938, 0x41202020
    .WORD 0x52204444, 0x31522031, 0x20203720, 0x20202020, 0x20202020, 0x41203B20, 0x37206464, 0x206F7420
    .WORD 0x6E756F72, 0x70752064, 0x2020200A, 0x20494C20, 0x20325220, 0x46467830, 0x46464646, 0x0A203846
    .WORD 0x20202020, 0x20444E41, 0x52203152, 0x32522031, 0x20202020, 0x20202020, 0x203B2020, 0x61656C43
    .WORD 0x6F6C2072, 0x20726577, 0x69622033, 0x28207374, 0x656B616D, 0x6C756D20, 0x6C706974, 0x666F2065
    .WORD 0x0A293820, 0x20202020, 0x20564F4D, 0x52203552, 0x20202031, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x3D203552, 0x696C6120, 0x64656E67, 0x7A697320, 0x65282065, 0x2C2E672E, 0x34303120, 0x20200A29
    .WORD 0x200A2020, 0x3B202020, 0x65745320, 0x3A322070, 0x61655320, 0x20686372, 0x20726F66, 0x72662061
    .WORD 0x62206565, 0x6B636F6C, 0x206E6920, 0x20656874, 0x6C626174, 0x20200A65, 0x203B2020, 0x6C276557
    .WORD 0x7375206C, 0x34522065, 0x20736120, 0x65646E69, 0x6E692078, 0x62206F74, 0x6B636F6C, 0x6261745F
    .WORD 0x2820656C, 0x6F742030, 0x58414D20, 0x4F4C425F, 0x2D534B43, 0x200A2931, 0x4C202020, 0x34522049
    .WORD 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x53203B20, 0x74726174, 0x20746120, 0x73726966
    .WORD 0x6C622074, 0x206B636F, 0x646E6928, 0x30207865, 0x20200A29, 0x6D0A2020, 0x6F6C6C61, 0x6F6C5F63
    .WORD 0x0A3A706F, 0x20202020, 0x6843203B, 0x206B6365, 0x77206669, 0x65762765, 0x61657320, 0x65686372
    .WORD 0x6C612064, 0x6C62206C, 0x736B636F, 0x2020200A, 0x504D4320, 0x20345220, 0x5F58414D, 0x434F4C42
    .WORD 0x2020534B, 0x3B202020, 0x6D6F4320, 0x65726170, 0x646E6920, 0x77207865, 0x20687469, 0x6978616D
    .WORD 0x0A6D756D, 0x20202020, 0x20454742, 0x6C6C616D, 0x735F636F, 0x206B7262, 0x20202020, 0x203B2020
    .WORD 0x69206649, 0x7865646E, 0x203D3E20, 0x5F58414D, 0x434F4C42, 0x202C534B, 0x66206F6E, 0x20656572
    .WORD 0x636F6C62, 0x6F66206B, 0x0A646E75, 0x20202020, 0x2020200A, 0x43203B20, 0x75636C61, 0x6574616C
    .WORD 0x64646120, 0x73736572, 0x20666F20, 0x73696874, 0x6F6C6220, 0x73276B63, 0x73656420, 0x70697263
    .WORD 0x0A726F74, 0x20202020, 0x6C62203B, 0x5F6B636F, 0x6C626174, 0x202B2065, 0x646E6928, 0x2A207865
    .WORD 0x73656420, 0x70697263, 0x5F726F74, 0x657A6973, 0x20200A29, 0x494C2020, 0x20325220, 0x636F6C62
    .WORD 0x61745F6B, 0x20656C62, 0x20202020, 0x3252203B, 0x62203D20, 0x20657361, 0x72646461, 0x20737365
    .WORD 0x6220666F, 0x6B636F6C, 0x6261745F, 0x200A656C, 0x4C202020, 0x33522049, 0x4F4C4220, 0x445F4B43
    .WORD 0x20435345, 0x20202020, 0x52203B20, 0x203D2033, 0x657A6973, 0x20666F20, 0x20656E6F, 0x63736564
    .WORD 0x74706972, 0x2820726F, 0x62203231, 0x73657479, 0x20200A29, 0x554D2020, 0x3352204C, 0x20345220
    .WORD 0x20203352, 0x20202020, 0x20202020, 0x3352203B, 0x69203D20, 0x7865646E, 0x31202A20, 0x6F282032
    .WORD 0x65736666, 0x6E692074, 0x74206F74, 0x656C6261, 0x20200A29, 0x44412020, 0x32522044, 0x20325220
    .WORD 0x20203352, 0x20202020, 0x20202020, 0x3252203B, 0x61203D20, 0x65726464, 0x6F207373, 0x6C622066
    .WORD 0x5F6B636F, 0x6C626174, 0x6E695B65, 0x5D786564, 0x2020200A, 0x20200A20, 0x203B2020, 0x63656843
    .WORD 0x6669206B, 0x69687420, 0x6C622073, 0x206B636F, 0x66207369, 0x20656572, 0x45535528, 0x6C662044
    .WORD 0x3D206761, 0x0A293020, 0x20202020, 0x2057444C, 0x5B203352, 0x2B203252, 0x4F4C4220, 0x555F4B43
    .WORD 0x5D444553, 0x203B2020, 0x64616F4C, 0x65687420, 0x45535520, 0x6C662044, 0x200A6761, 0x43202020
    .WORD 0x5220504D, 0x20302033, 0x20202020, 0x20202020, 0x20202020, 0x49203B20, 0x74692073, 0x28203020
    .WORD 0x65657266, 0x200A3F29, 0x42202020, 0x6D20454E, 0x6F6C6C61, 0x656E5F63, 0x20207478, 0x20202020
    .WORD 0x49203B20, 0x6F6E2066, 0x72662074, 0x28206565, 0x64657375, 0x73202C29, 0x2070696B, 0x6E206F74
    .WORD 0x20747865, 0x636F6C62, 0x20200A6B, 0x200A2020, 0x3B202020, 0x65684320, 0x69206B63, 0x68742066
    .WORD 0x62207369, 0x6B636F6C, 0x20736920, 0x6772616C, 0x6E652065, 0x6867756F, 0x726F6620, 0x72756F20
    .WORD 0x71657220, 0x74736575, 0x2020200A, 0x57444C20, 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F
    .WORD 0x455A4953, 0x3B20205D, 0x616F4C20, 0x68742064, 0x6C622065, 0x206B636F, 0x657A6973, 0x2020200A
    .WORD 0x504D4320, 0x20335220, 0x20203552, 0x20202020, 0x20202020, 0x3B202020, 0x20734920, 0x636F6C62
    .WORD 0x6973206B, 0x3E20657A, 0x6572203D, 0x73657571, 0x20646574, 0x657A6973, 0x20200A3F, 0x47422020
    .WORD 0x616D2045, 0x636F6C6C, 0x756F665F, 0x2020646E, 0x20202020, 0x6559203B, 0x57202173, 0x6F662065
    .WORD 0x20646E75, 0x75732061, 0x62617469, 0x6220656C, 0x6B636F6C, 0x2020200A, 0x616D0A20, 0x636F6C6C
    .WORD 0x78656E5F, 0x200A3A74, 0x3B202020, 0x69685420, 0x6C622073, 0x206B636F, 0x65207369, 0x65687469
    .WORD 0x73752072, 0x6F206465, 0x6F742072, 0x6D73206F, 0x2C6C6C61, 0x79727420, 0x78656E20, 0x6E6F2074
    .WORD 0x20200A65, 0x44412020, 0x34522044, 0x20345220, 0x20202031, 0x20202020, 0x20202020, 0x6E49203B
    .WORD 0x6D657263, 0x20746E65, 0x65646E69, 0x6F742078, 0x65686320, 0x6E206B63, 0x20747865, 0x636F6C62
    .WORD 0x20200A6B, 0x20422020, 0x6C6C616D, 0x6C5F636F, 0x20706F6F, 0x20202020, 0x20202020, 0x6F47203B
    .WORD 0x63616220, 0x6F74206B, 0x61747320, 0x6F207472, 0x6F6C2066, 0x0A0A706F, 0x6C6C616D, 0x665F636F
    .WORD 0x646E756F, 0x20200A3A, 0x203B2020, 0x70657453, 0x203A3320, 0x66206557, 0x646E756F, 0x66206120
    .WORD 0x20656572, 0x636F6C62, 0x616C206B, 0x20656772, 0x756F6E65, 0x0A216867, 0x20202020, 0x3252203B
    .WORD 0x70203D20, 0x746E696F, 0x74207265, 0x6874206F, 0x6C622065, 0x206B636F, 0x63736564, 0x74706972
    .WORD 0x200A726F, 0x3B202020, 0x20335220, 0x6C62203D, 0x206B636F, 0x657A6973, 0x65772820, 0x6E6F6420
    .WORD 0x75207427, 0x69206573, 0x6F662074, 0x70732072, 0x7474696C, 0x20676E69, 0x74206E69, 0x20736968
    .WORD 0x706D6973, 0x7620656C, 0x69737265, 0x0A296E6F, 0x20202020, 0x2020200A, 0x4D203B20, 0x206B7261
    .WORD 0x20656874, 0x636F6C62, 0x7361206B, 0x65737520, 0x55282064, 0x20444553, 0x67616C66, 0x31203D20
    .WORD 0x20200A29, 0x494C2020, 0x20335220, 0x20202031, 0x20202020, 0x20202020, 0x20202020, 0x3352203B
    .WORD 0x31203D20, 0x73752820, 0x0A296465, 0x20202020, 0x20575453, 0x5B203352, 0x2B203252, 0x4F4C4220
    .WORD 0x555F4B43, 0x5D444553, 0x203B2020, 0x726F7453, 0x20312065, 0x74206E69, 0x55206568, 0x20444553
    .WORD 0x6C656966, 0x20200A64, 0x200A2020, 0x3B202020, 0x74654720, 0x65687420, 0x6F6C6220, 0x73276B63
    .WORD 0x61747320, 0x6E697472, 0x64612067, 0x73657264, 0x6E612073, 0x65722064, 0x6E727574, 0x0A746920
    .WORD 0x20202020, 0x2057444C, 0x5B203152, 0x2B203252, 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x203B2020
    .WORD 0x3D203152, 0x64646120, 0x73736572, 0x20666F20, 0x73696874, 0x6F6C6220, 0x200A6B63, 0x42202020
    .WORD 0x6C616D20, 0x5F636F6C, 0x656E6F64, 0x20202020, 0x20202020, 0x4A203B20, 0x20706D75, 0x63206F74
    .WORD 0x6E61656C, 0x61207075, 0x7220646E, 0x72757465, 0x6D0A0A6E, 0x6F6C6C61, 0x62735F63, 0x0A3A6B72
    .WORD 0x20202020, 0x7453203B, 0x34207065, 0x6F4E203A, 0x65726620, 0x6C622065, 0x206B636F, 0x6E756F66
    .WORD 0x6E692064, 0x62617420, 0x200A656C, 0x3B202020, 0x6B734120, 0x65687420, 0x72656B20, 0x206C656E
    .WORD 0x20726F66, 0x65726F6D, 0x6D656D20, 0x2079726F, 0x6E697375, 0x62732067, 0x73206B72, 0x61637379
    .WORD 0x200A6C6C, 0x0A202020, 0x20202020, 0x3552203B, 0x726C6120, 0x79646165, 0x73616820, 0x65687420
    .WORD 0x696C6120, 0x64656E67, 0x7A697320, 0x65772065, 0x65656E20, 0x20200A64, 0x4F4D2020, 0x31522056
    .WORD 0x20355220, 0x20202020, 0x20202020, 0x20202020, 0x3152203B, 0x73203D20, 0x20657A69, 0x61206F74
    .WORD 0x636F6C6C, 0x0A657461, 0x20202020, 0x20435653, 0x5F535953, 0x4B524253, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x6C6C6143, 0x72656B20, 0x3A6C656E, 0x72627320, 0x6973286B, 0x0A29657A, 0x20202020
    .WORD 0x2020200A, 0x43203B20, 0x6B636568, 0x20666920, 0x6B726273, 0x69616620, 0x2064656C, 0x74657228
    .WORD 0x736E7275, 0x20312D20, 0x3020726F, 0x206E6F20, 0x6F727265, 0x200A2972, 0x43202020, 0x5220504D
    .WORD 0x20302031, 0x20202020, 0x20202020, 0x20202020, 0x44203B20, 0x73206469, 0x206B7262, 0x75746572
    .WORD 0x30206E72, 0x20726F20, 0x6167656E, 0x65766974, 0x20200A3F, 0x4C422020, 0x616D2054, 0x636F6C6C
    .WORD 0x7272655F, 0x2020726F, 0x20202020, 0x6649203B, 0x72726520, 0x202C726F, 0x75746572, 0x4E206E72
    .WORD 0x0A4C4C55, 0x20202020, 0x2020200A, 0x53203B20, 0x20706574, 0x73203A35, 0x206B7262, 0x63637573
    .WORD 0x65646565, 0x77202C64, 0x61682065, 0x6E206576, 0x6D207765, 0x726F6D65, 0x74612079, 0x64646120
    .WORD 0x73736572, 0x206E6920, 0x200A3152, 0x3B202020, 0x776F4E20, 0x20657720, 0x6465656E, 0x206F7420
    .WORD 0x20646461, 0x73696874, 0x77656E20, 0x6F6C6220, 0x74206B63, 0x756F206F, 0x61742072, 0x0A656C62
    .WORD 0x20202020, 0x2020200A, 0x46203B20, 0x20646E69, 0x65206E61, 0x7974706D, 0x6F6C7320, 0x6E692074
    .WORD 0x65687420, 0x6F6C6220, 0x74206B63, 0x656C6261, 0x2020200A, 0x20494C20, 0x30203452, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x61745320, 0x61207472, 0x69662074, 0x20747372, 0x636F6C62
    .WORD 0x20200A6B, 0x6D0A2020, 0x6F6C6C61, 0x64615F63, 0x200A3A64, 0x3B202020, 0x65684320, 0x69206B63
    .WORD 0x65772066, 0x20657627, 0x72616573, 0x64656863, 0x6C6C6120, 0x6F6C6220, 0x0A736B63, 0x20202020
    .WORD 0x20504D43, 0x4D203452, 0x425F5841, 0x4B434F4C, 0x20202053, 0x200A2020, 0x42202020, 0x6D204547
    .WORD 0x6F6C6C61, 0x72655F63, 0x20726F72, 0x20202020, 0x4E203B20, 0x6D65206F, 0x20797470, 0x746F6C73
    .WORD 0x73282021, 0x6C756F68, 0x74276E64, 0x70616820, 0x296E6570, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x20746547, 0x63736564, 0x74706972, 0x6120726F, 0x65726464, 0x200A7373, 0x4C202020, 0x32522049
    .WORD 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x2020200A, 0x20494C20, 0x42203352, 0x4B434F4C, 0x5345445F
    .WORD 0x20200A43, 0x554D2020, 0x3352204C, 0x20345220, 0x200A3352, 0x41202020, 0x52204444, 0x32522032
    .WORD 0x0A335220, 0x20202020, 0x2020200A, 0x43203B20, 0x6B636568, 0x20666920, 0x73696874, 0x6F6C7320
    .WORD 0x73692074, 0x65726620, 0x55282065, 0x20444553, 0x67616C66, 0x30203D20, 0x20200A29, 0x444C2020
    .WORD 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4553555F, 0x200A5D44, 0x43202020, 0x5220504D
    .WORD 0x0A302033, 0x20202020, 0x20514542, 0x6C6C616D, 0x615F636F, 0x665F6464, 0x646E756F, 0x203B2020
    .WORD 0x6E756F46, 0x6E612064, 0x706D6520, 0x73207974, 0x21746F6C, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x746F6C53, 0x20736920, 0x64657375, 0x7274202C, 0x656E2079, 0x6F207478, 0x200A656E, 0x41202020
    .WORD 0x52204444, 0x34522034, 0x200A3120, 0x42202020, 0x6C616D20, 0x5F636F6C, 0x0A646461, 0x6C616D0A
    .WORD 0x5F636F6C, 0x5F646461, 0x6E756F66, 0x200A3A64, 0x3B202020, 0x20655720, 0x6E756F66, 0x6E612064
    .WORD 0x706D6520, 0x73207974, 0x20746F6C, 0x52207461, 0x20200A32, 0x203B2020, 0x726F7453, 0x68742065
    .WORD 0x656E2065, 0x6C622077, 0x276B636F, 0x6E692073, 0x6D726F66, 0x6F697461, 0x20200A6E, 0x200A2020
    .WORD 0x3B202020, 0x6F745320, 0x74206572, 0x61206568, 0x65726464, 0x28207373, 0x66203152, 0x206D6F72
    .WORD 0x6B726273, 0x20200A29, 0x54532020, 0x31522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4444415F
    .WORD 0x20205D52, 0x62203B20, 0x6B636F6C, 0x6464612E, 0x73736572, 0x61203D20, 0x65726464, 0x66207373
    .WORD 0x206D6F72, 0x6B726273, 0x2020200A, 0x20200A20, 0x203B2020, 0x726F7453, 0x68742065, 0x69732065
    .WORD 0x2820657A, 0x3D203552, 0x696C6120, 0x64656E67, 0x7A697320, 0x200A2965, 0x53202020, 0x52205754
    .WORD 0x525B2035, 0x202B2032, 0x434F4C42, 0x49535F4B, 0x205D455A, 0x203B2020, 0x636F6C62, 0x69732E6B
    .WORD 0x3D20657A, 0x7A697320, 0x20200A65, 0x200A2020, 0x3B202020, 0x72614D20, 0x7361206B, 0x65737520
    .WORD 0x55282064, 0x20444553, 0x2931203D, 0x2020200A, 0x20494C20, 0x31203352, 0x2020200A, 0x57545320
    .WORD 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x44455355, 0x2020205D, 0x6C62203B, 0x2E6B636F
    .WORD 0x64657375, 0x31203D20, 0x2020200A, 0x20200A20, 0x203B2020, 0x61203152, 0x6165726C, 0x68207964
    .WORD 0x74207361, 0x61206568, 0x65726464, 0x66207373, 0x206D6F72, 0x6B726273, 0x6F73202C, 0x73756A20
    .WORD 0x65722074, 0x6E727574, 0x0A746920, 0x20202020, 0x616D2042, 0x636F6C6C, 0x6E6F645F, 0x6D0A0A65
    .WORD 0x6F6C6C61, 0x72655F63, 0x3A726F72, 0x2020200A, 0x53203B20, 0x74656D6F, 0x676E6968, 0x6E657720
    .WORD 0x72772074, 0x20676E6F, 0x6572202D, 0x6E727574, 0x4C554E20, 0x3028204C, 0x20200A29, 0x494C2020
    .WORD 0x20315220, 0x6D0A0A30, 0x6F6C6C61, 0x6F645F63, 0x0A3A656E, 0x20202020, 0x20504F50, 0x2020524C
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x74736552, 0x2065726F, 0x75746572, 0x61206E72
    .WORD 0x65726464, 0x200A7373, 0x52202020, 0x20205445, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x52203B20, 0x72757465, 0x6F74206E, 0x6C616320, 0x2072656C, 0x68746977, 0x20315220, 0x6F70203D
    .WORD 0x65746E69, 0x726F2072, 0x4C554E20, 0x3B0A0A4C, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D
    .WORD 0x65726620, 0x74702865, 0x3B0A2972, 0x46203B0A, 0x73656572, 0x65727020, 0x756F6976, 0x20796C73
    .WORD 0x6F6C6C61, 0x65746163, 0x656D2064, 0x79726F6D, 0x0A3B0A2E, 0x6F48203B, 0x74692077, 0x726F7720
    .WORD 0x0A3A736B, 0x2E31203B, 0x6E694620, 0x68742064, 0x6C622065, 0x206B636F, 0x63736564, 0x74706972
    .WORD 0x6620726F, 0x7420726F, 0x20736968, 0x72646461, 0x0A737365, 0x2E32203B, 0x72614D20, 0x7469206B
    .WORD 0x20736120, 0x65657266, 0x53552820, 0x3D204445, 0x0A293020, 0x2E33203B, 0x6D654D20, 0x2079726F
    .WORD 0x6E207369, 0x6120776F, 0x6C696176, 0x656C6261, 0x726F6620, 0x74756620, 0x20657275, 0x6C6C616D
    .WORD 0x6320636F, 0x736C6C61, 0x3B0A3B0A, 0x746F4E20, 0x54203A65, 0x20736968, 0x706D6973, 0x7620656C
    .WORD 0x69737265, 0x64206E6F, 0x2073656F, 0x20544F4E, 0x6C616F63, 0x65637365, 0x6A646120, 0x6E656361
    .WORD 0x72662074, 0x62206565, 0x6B636F6C, 0x3B0A2173, 0x20202020, 0x53202020, 0x7266206F, 0x656D6761
    .WORD 0x7461746E, 0x206E6F69, 0x206E6163, 0x7563636F, 0x766F2072, 0x74207265, 0x2E656D69, 0x3B0A3B0A
    .WORD 0x706E4920, 0x203A7475, 0x20315220, 0x6F70203D, 0x65746E69, 0x6F742072, 0x6D656D20, 0x2079726F
    .WORD 0x66206F74, 0x20656572, 0x6F726628, 0x616D206D, 0x636F6C6C, 0x203B0A29, 0x7074754F, 0x203A7475
    .WORD 0x68746F4E, 0x0A676E69, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x65657266, 0x20200A3A
    .WORD 0x203B2020, 0x65766153, 0x67657220, 0x65747369, 0x200A7372, 0x50202020, 0x20485355, 0x200A524C
    .WORD 0x0A202020, 0x20202020, 0x7453203B, 0x31207065, 0x6843203A, 0x206B6365, 0x70206669, 0x746E696F
    .WORD 0x69207265, 0x554E2073, 0x200A4C4C, 0x43202020, 0x5220504D, 0x20302031, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x49203B20, 0x31522073, 0x203D3D20, 0x200A3F30, 0x42202020, 0x66205145, 0x5F656572
    .WORD 0x656E6F64, 0x20202020, 0x20202020, 0x49203B20, 0x554E2066, 0x202C4C4C, 0x68746F6E, 0x20676E69
    .WORD 0x66206F74, 0x2C656572, 0x73756A20, 0x65722074, 0x6E727574, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x70657453, 0x203A3220, 0x72616553, 0x74206863, 0x62206568, 0x6B636F6C, 0x62617420, 0x6620656C
    .WORD 0x7420726F, 0x20736968, 0x72646461, 0x0A737365, 0x20202020, 0x5220494C, 0x20302034, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x72617453, 0x74612074, 0x72696620, 0x62207473, 0x6B636F6C
    .WORD 0x2020200A, 0x72660A20, 0x6C5F6565, 0x3A706F6F, 0x2020200A, 0x43203B20, 0x6B636568, 0x20666920
    .WORD 0x76276577, 0x65732065, 0x68637261, 0x61206465, 0x62206C6C, 0x6B636F6C, 0x20200A73, 0x4D432020
    .WORD 0x34522050, 0x58414D20, 0x4F4C425F, 0x0A534B43, 0x20202020, 0x20454742, 0x65657266, 0x6E6F645F
    .WORD 0x20202065, 0x20202020, 0x203B2020, 0x20746F4E, 0x6E756F66, 0x202D2064, 0x6F6E6769, 0x28206572
    .WORD 0x6C756F63, 0x65622064, 0x766E6920, 0x64696C61, 0x696F7020, 0x7265746E, 0x20200A29, 0x200A2020
    .WORD 0x3B202020, 0x74654720, 0x73656420, 0x70697263, 0x20726F74, 0x72646461, 0x0A737365, 0x20202020
    .WORD 0x5220494C, 0x6C622032, 0x5F6B636F, 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x434F4C42
    .WORD 0x45445F4B, 0x200A4353, 0x4D202020, 0x52204C55, 0x34522033, 0x0A335220, 0x20202020, 0x20444441
    .WORD 0x52203252, 0x33522032, 0x2020200A, 0x20200A20, 0x203B2020, 0x63656843, 0x6669206B, 0x69687420
    .WORD 0x6C622073, 0x276B636F, 0x64612073, 0x73657264, 0x616D2073, 0x65686374, 0x68742073, 0x6F702065
    .WORD 0x65746E69, 0x20200A72, 0x444C2020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4444415F
    .WORD 0x20205D52, 0x3352203B, 0x62203D20, 0x6B636F6C, 0x64646120, 0x73736572, 0x2020200A, 0x504D4320
    .WORD 0x20335220, 0x20203152, 0x20202020, 0x20202020, 0x3B202020, 0x20734920, 0x73696874, 0x72756F20
    .WORD 0x6F6C6220, 0x0A3F6B63, 0x20202020, 0x20514542, 0x65657266, 0x756F665F, 0x2020646E, 0x20202020
    .WORD 0x203B2020, 0x2C736559, 0x20657720, 0x6E756F66, 0x74692064, 0x20200A21, 0x200A2020, 0x3B202020
    .WORD 0x746F4E20, 0x69687420, 0x6C622073, 0x2C6B636F, 0x79727420, 0x78656E20, 0x20200A74, 0x44412020
    .WORD 0x34522044, 0x20345220, 0x20200A31, 0x20422020, 0x65657266, 0x6F6F6C5F, 0x660A0A70, 0x5F656572
    .WORD 0x6E756F66, 0x200A3A64, 0x3B202020, 0x65745320, 0x3A332070, 0x20655720, 0x6E756F66, 0x68742064
    .WORD 0x6C622065, 0x206B636F, 0x63736564, 0x74706972, 0x6120726F, 0x32522074, 0x2020200A, 0x4D203B20
    .WORD 0x206B7261, 0x61207469, 0x72662073, 0x73206565, 0x616D206F, 0x636F6C6C, 0x6E616320, 0x65737520
    .WORD 0x20746920, 0x69616761, 0x20200A6E, 0x200A2020, 0x4C202020, 0x33522049, 0x20203020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x52203B20, 0x203D2033, 0x66282030, 0x29656572, 0x2020200A, 0x57545320
    .WORD 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x44455355, 0x3B20205D, 0x6F6C6220, 0x752E6B63
    .WORD 0x20646573, 0x0A30203D, 0x20202020, 0x2020200A, 0x4E203B20, 0x3A45544F, 0x20655720, 0x4E206F64
    .WORD 0x6320544F, 0x7261656C, 0x65687420, 0x64646120, 0x73736572, 0x20726F20, 0x657A6973, 0x2020200A
    .WORD 0x54203B20, 0x20796568, 0x79617473, 0x206E6920, 0x20656874, 0x6C626174, 0x6E612065, 0x69772064
    .WORD 0x62206C6C, 0x766F2065, 0x72777265, 0x65747469, 0x6877206E, 0x72206E65, 0x65737565, 0x20200A64
    .WORD 0x660A2020, 0x5F656572, 0x656E6F64, 0x20200A3A, 0x203B2020, 0x61656C43, 0x7075206E, 0x646E6120
    .WORD 0x74657220, 0x0A6E7275, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616D203B, 0x636F6C6C, 0x696E695F, 0x202D2074, 0x74696E49
    .WORD 0x696C6169, 0x7420657A, 0x6D206568, 0x726F6D65, 0x6C612079, 0x61636F6C, 0x0A726F74, 0x203B0A3B
    .WORD 0x61656C43, 0x74207372, 0x65206568, 0x7269746E, 0x6C622065, 0x206B636F, 0x6C626174, 0x6F732065
    .WORD 0x6C6C6120, 0x6F6C6220, 0x20736B63, 0x20657261, 0x6B72616D, 0x61206465, 0x72662073, 0x3B0A6565
    .WORD 0x6F685320, 0x20646C75, 0x63206562, 0x656C6C61, 0x6E6F2064, 0x61206563, 0x79732074, 0x6D657473
    .WORD 0x61747320, 0x70757472, 0x66656220, 0x2065726F, 0x6E697375, 0x616D2067, 0x636F6C6C, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C616D0A, 0x5F636F6C, 0x74696E69, 0x20200A3A, 0x203B2020
    .WORD 0x65766153, 0x67657220, 0x65747369, 0x200A7372, 0x50202020, 0x20485355, 0x2020524C, 0x20200A20
    .WORD 0x203B2020, 0x70657453, 0x203A3120, 0x61656C43, 0x68742072, 0x6E652065, 0x65726974, 0x6F6C6220
    .WORD 0x74206B63, 0x656C6261, 0x2020200A, 0x53203B20, 0x61207465, 0x62206C6C, 0x73657479, 0x206E6920
    .WORD 0x636F6C62, 0x61745F6B, 0x20656C62, 0x30206F74, 0x2020200A, 0x20494C20, 0x62203152, 0x6B636F6C
    .WORD 0x6261745F, 0x2020656C, 0x3B202020, 0x20315220, 0x7473203D, 0x20747261, 0x72646461, 0x20737365
    .WORD 0x7420666F, 0x656C6261, 0x2020200A, 0x20494C20, 0x4D203352, 0x425F5841, 0x4B434F4C, 0x202A2053
    .WORD 0x434F4C42, 0x45445F4B, 0x20204353, 0x3352203B, 0x74203D20, 0x6C61746F, 0x74796220, 0x74207365
    .WORD 0x6C63206F, 0x0A726165, 0x20202020, 0x6C616D0A, 0x5F636F6C, 0x74696E69, 0x6F6F6C5F, 0x200A3A70
    .WORD 0x43202020, 0x5220504D, 0x20302033, 0x20202020, 0x20202020, 0x20202020, 0x48203B20, 0x20657661
    .WORD 0x63206577, 0x7261656C, 0x61206465, 0x62206C6C, 0x73657479, 0x20200A3F, 0x45422020, 0x616D2051
    .WORD 0x636F6C6C, 0x696E695F, 0x6F645F74, 0x2020656E, 0x6559203B, 0x77202C73, 0x65722765, 0x6E6F6420
    .WORD 0x20200A65, 0x200A2020, 0x4C202020, 0x32522049, 0x20203020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x52203B20, 0x203D2032, 0x76282030, 0x65756C61, 0x206F7420, 0x74697277, 0x200A2965, 0x53202020
    .WORD 0x52204254, 0x525B2032, 0x20205D31, 0x20202020, 0x20202020, 0x53203B20, 0x65726F74, 0x61203020
    .WORD 0x75632074, 0x6E657272, 0x64612074, 0x73657264, 0x20200A73, 0x44412020, 0x31522044, 0x20315220
    .WORD 0x20202031, 0x20202020, 0x20202020, 0x6F4D203B, 0x74206576, 0x656E206F, 0x62207478, 0x0A657479
    .WORD 0x20202020, 0x20425553, 0x52203352, 0x20312033, 0x20202020, 0x20202020, 0x203B2020, 0x72636544
    .WORD 0x6E656D65, 0x79622074, 0x63206574, 0x746E756F, 0x200A7265, 0x42202020, 0x6C616D20, 0x5F636F6C
    .WORD 0x74696E69, 0x6F6F6C5F, 0x20202070, 0x43203B20, 0x69746E6F, 0x0A65756E, 0x20202020, 0x6C616D0A
    .WORD 0x5F636F6C, 0x74696E69, 0x6E6F645F, 0x200A3A65, 0x3B202020, 0x656C4320, 0x75206E61, 0x6E612070
    .WORD 0x65722064, 0x6E727574, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3B0A0A
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x45544E49, 0x4C414E52, 0x4C454820, 0x53524550
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x65726F63, 0x55202D20, 0x6576696E
    .WORD 0x6C617372, 0x746E6920, 0x72656765, 0x206F7420, 0x69727473, 0x6320676E, 0x65766E6F, 0x72657472
    .WORD 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A
    .WORD 0x203D2032, 0x65746E69, 0x20726567, 0x63206F74, 0x65766E6F, 0x3B0A7472, 0x20335220, 0x6162203D
    .WORD 0x28206573, 0x31202C32, 0x6F202C30, 0x36312072, 0x203B0A29, 0x3D203452, 0x67697320, 0x6C66206E
    .WORD 0x28206761, 0x203D2031, 0x6E676973, 0x202C6465, 0x203D2030, 0x69736E75, 0x64656E67, 0x203B0A29
    .WORD 0x3D203552, 0x6D657420, 0x75622070, 0x72656666, 0x7A697320, 0x656E2065, 0x64656465, 0x3B0A3B0A
    .WORD 0x74655220, 0x736E7275, 0x203B0A3A, 0x31522020, 0x6F203D20, 0x69676972, 0x206C616E, 0x74736564
    .WORD 0x74616E69, 0x206E6F69, 0x6E696F70, 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x65726F63, 0x20200A3A, 0x55502020, 0x4C204853
    .WORD 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x55502020
    .WORD 0x52204853, 0x200A3031, 0x50202020, 0x20485355, 0x0A313152, 0x20202020, 0x48535550, 0x32315220
    .WORD 0x20200A0A, 0x4F4D2020, 0x52202056, 0x52202038, 0x20202031, 0x20202020, 0x3B202020, 0x76615320
    .WORD 0x65642065, 0x6E697473, 0x6F697461, 0x20200A6E, 0x200A2020, 0x4D202020, 0x2020564F, 0x20203952
    .WORD 0x20203252, 0x20202020, 0x20202020, 0x6F57203B, 0x6E696B72, 0x61762067, 0x0A65756C, 0x20202020
    .WORD 0x20564F4D, 0x31315220, 0x20335220, 0x20202020, 0x20202020, 0x42203B20, 0x0A657361, 0x20202020
    .WORD 0x20564F4D, 0x32315220, 0x20345220, 0x20202020, 0x20202020, 0x53203B20, 0x206E6769, 0x67616C66
    .WORD 0x2020200A, 0x4F4D3B20, 0x52202056, 0x52203031, 0x20202035, 0x20202020, 0x3B202020, 0x6D655420
    .WORD 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x200A2020, 0x3B202020, 0x6C6C4120, 0x7461636F
    .WORD 0x65742065, 0x6220706D, 0x65666675, 0x73282072, 0x20657A69, 0x73736170, 0x69206465, 0x3552206E
    .WORD 0x20200A29, 0x55532020, 0x53202042, 0x50532050, 0x0A355220, 0x20202020, 0x20564F4D, 0x30315220
    .WORD 0x20315220, 0x20202020, 0x20202020, 0x4B203B20, 0x20706565, 0x6769726F, 0x6C616E69, 0x696F7020
    .WORD 0x7265746E, 0x2020200A, 0x564F4D20, 0x36522020, 0x50532020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x706D6554, 0x66756220, 0x20726566, 0x6E696F70, 0x0A726574, 0x20202020, 0x68737570, 0x20355220
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x73203B20, 0x20657661, 0x66203552, 0x6620726F, 0x656D6172
    .WORD 0x61656C20, 0x200A6576, 0x4D202020, 0x2020564F, 0x20203752, 0x20203652, 0x20202020, 0x20202020
    .WORD 0x6153203B, 0x73206576, 0x74726174, 0x20666F20, 0x706D6574, 0x66756220, 0x0A726566, 0x20202020
    .WORD 0x2020200A, 0x43203B20, 0x6B636568, 0x726F6620, 0x67697320, 0x6928206E, 0x69732066, 0x64656E67
    .WORD 0x646E6120, 0x67656E20, 0x76697461, 0x200A2965, 0x43202020, 0x2020504D, 0x20323152, 0x20200A31
    .WORD 0x4E422020, 0x69202045, 0x5F616F74, 0x65726F63, 0x736E755F, 0x656E6769, 0x20200A64, 0x200A2020
    .WORD 0x43202020, 0x2020504D, 0x30203952, 0x2020200A, 0x45474220, 0x74692020, 0x635F616F, 0x5F65726F
    .WORD 0x69736E75, 0x64656E67, 0x2020200A, 0x20200A20, 0x203B2020, 0x6167654E, 0x65766974, 0x6D756E20
    .WORD 0x20726562, 0x6461202D, 0x696D2064, 0x2073756E, 0x6E676973, 0x2020200A, 0x20494C20, 0x32522020
    .WORD 0x20353420, 0x20202020, 0x272D273B, 0x2020200A, 0x42545320, 0x32522020, 0x38525B20, 0x20200A5D
    .WORD 0x44412020, 0x52202044, 0x38522038, 0x200A3120, 0x4E202020, 0x2020544F, 0x52203952, 0x20200A39
    .WORD 0x44412020, 0x52202044, 0x39522039, 0x200A3120, 0x3B202020, 0x2047454E, 0x20395220, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x4D203B20, 0x20656B61, 0x69736F70, 0x65766974, 0x2020200A, 0x74690A20
    .WORD 0x635F616F, 0x5F65726F, 0x69736E75, 0x64656E67, 0x20200A3A, 0x203B2020, 0x63657053, 0x206C6169
    .WORD 0x65736163, 0x657A203A, 0x200A6F72, 0x43202020, 0x2020504D, 0x30203952, 0x2020200A, 0x454E4220
    .WORD 0x74692020, 0x635F616F, 0x5F65726F, 0x766E6F63, 0x0A747265, 0x20202020, 0x2020200A, 0x20494C20
    .WORD 0x32522020, 0x20383420, 0x3B202020, 0x27302720, 0x2020200A, 0x42545320, 0x32522020, 0x38525B20
    .WORD 0x20200A5D, 0x44412020, 0x52202044, 0x38522038, 0x200A3120, 0x4C202020, 0x20202049, 0x30203252
    .WORD 0x2020200A, 0x42545320, 0x32522020, 0x38525B20, 0x20200A5D, 0x20422020, 0x69202020, 0x5F616F74
    .WORD 0x65726F63, 0x6E69665F, 0x0A687369, 0x20202020, 0x6F74690A, 0x6F635F61, 0x635F6572, 0x65766E6F
    .WORD 0x0A3A7472, 0x20202020, 0x2020494C, 0x20345220, 0x20202030, 0x20202020, 0x20202020, 0x44203B20
    .WORD 0x74696769, 0x756F6320, 0x7265746E, 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x6C766964
    .WORD 0x3A706F6F, 0x2020200A, 0x564F4D20, 0x35522020, 0x0A395220, 0x20202020, 0x20564944, 0x20365220
    .WORD 0x52203552, 0x20203131, 0x20202020, 0x52203B20, 0x203D2036, 0x746F7571, 0x746E6569, 0x3952202C
    .WORD 0x72203D20, 0x69616D65, 0x7265646E, 0x2020200A, 0x444F4D20, 0x37522020, 0x20395220, 0x20313152
    .WORD 0x20202020, 0x203B2020, 0x3D203752, 0x6D657220, 0x646E6961, 0x200A7265, 0x0A202020, 0x20202020
    .WORD 0x6F43203B, 0x7265766E, 0x69642074, 0x20746967, 0x41206F74, 0x49494353, 0x73616220, 0x6F206465
    .WORD 0x6162206E, 0x200A6573, 0x43202020, 0x2020504D, 0x20313152, 0x200A3631, 0x42202020, 0x20205145
    .WORD 0x616F7469, 0x726F635F, 0x65685F65, 0x69645F78, 0x0A746967, 0x20202020, 0x2020200A, 0x42203B20
    .WORD 0x20657361, 0x726F2032, 0x3A303120, 0x67696420, 0x30207469, 0x200A392D, 0x41202020, 0x20204444
    .WORD 0x52203752, 0x38342037, 0x20202020, 0x20202020, 0x3027203B, 0x202B2027, 0x69676964, 0x20200A74
    .WORD 0x20422020, 0x69202020, 0x5F616F74, 0x65726F63, 0x6F74735F, 0x200A6572, 0x0A202020, 0x616F7469
    .WORD 0x726F635F, 0x65685F65, 0x69645F78, 0x3A746967, 0x2020200A, 0x42203B20, 0x20657361, 0x203A3631
    .WORD 0x69676964, 0x2D302074, 0x200A3531, 0x43202020, 0x2020504D, 0x39203752, 0x2020200A, 0x54474220
    .WORD 0x74692020, 0x635F616F, 0x5F65726F, 0x5F786568, 0x7474656C, 0x200A7265, 0x41202020, 0x20204444
    .WORD 0x52203752, 0x38342037, 0x20202020, 0x20202020, 0x3027203B, 0x202B2027, 0x69676964, 0x20200A74
    .WORD 0x20422020, 0x69202020, 0x5F616F74, 0x65726F63, 0x6F74735F, 0x200A6572, 0x0A202020, 0x616F7469
    .WORD 0x726F635F, 0x65685F65, 0x656C5F78, 0x72657474, 0x20200A3A, 0x55532020, 0x52202042, 0x37522037
    .WORD 0x0A303120, 0x20202020, 0x20444441, 0x20375220, 0x36203752, 0x20202035, 0x20202020, 0x27203B20
    .WORD 0x2B202741, 0x69642820, 0x2D746967, 0x0A293031, 0x20202020, 0x6F74690A, 0x6F635F61, 0x735F6572
    .WORD 0x65726F74, 0x20200A3A, 0x54532020, 0x52202042, 0x525B2037, 0x20205D36, 0x20202020, 0x3B202020
    .WORD 0x6F745320, 0x69206572, 0x6574206E, 0x6220706D, 0x65666675, 0x20200A72, 0x44412020, 0x52202044
    .WORD 0x36522036, 0x200A3120, 0x41202020, 0x20204444, 0x52203452, 0x20312034, 0x20202020, 0x20202020
    .WORD 0x6E49203B, 0x6D657263, 0x20746E65, 0x69676964, 0x6F632074, 0x0A746E75, 0x20202020, 0x2020200A
    .WORD 0x564F4D20, 0x39522020, 0x20355220, 0x20202020, 0x20202020, 0x203B2020, 0x746F7551, 0x746E6569
    .WORD 0x63656220, 0x73656D6F, 0x77656E20, 0x6C617620, 0x200A6575, 0x43202020, 0x2020504D, 0x30203952
    .WORD 0x2020200A, 0x454E4220, 0x74692020, 0x635F616F, 0x5F65726F, 0x6C766964, 0x0A706F6F, 0x20202020
    .WORD 0x2020200A, 0x50203B20, 0x746E696F, 0x206F7420, 0x7473616C, 0x67696420, 0x200A7469, 0x53202020
    .WORD 0x20204255, 0x52203652, 0x0A312036, 0x20202020, 0x6F74690A, 0x6F635F61, 0x635F6572, 0x3A79706F
    .WORD 0x2020200A, 0x504D4320, 0x34522020, 0x200A3020, 0x42202020, 0x20205145, 0x616F7469, 0x726F635F
    .WORD 0x6F645F65, 0x200A656E, 0x0A202020, 0x20202020, 0x2042444C, 0x20325220, 0x5D36525B, 0x20202020
    .WORD 0x20202020, 0x47203B20, 0x64207465, 0x74696769, 0x6F726620, 0x6574206D, 0x2820706D, 0x65766572
    .WORD 0x20657372, 0x6564726F, 0x200A2972, 0x53202020, 0x20204254, 0x5B203252, 0x205D3852, 0x20202020
    .WORD 0x20202020, 0x7453203B, 0x2065726F, 0x64206E69, 0x69747365, 0x6974616E, 0x200A6E6F, 0x41202020
    .WORD 0x20204444, 0x52203852, 0x0A312038, 0x20202020, 0x20425553, 0x20365220, 0x31203652, 0x2020200A
    .WORD 0x42555320, 0x34522020, 0x20345220, 0x20200A31, 0x20422020, 0x69202020, 0x5F616F74, 0x65726F63
    .WORD 0x706F635F, 0x20200A79, 0x690A2020, 0x5F616F74, 0x65726F63, 0x6E6F645F, 0x200A3A65, 0x4C202020
    .WORD 0x20202049, 0x30203252, 0x2020200A, 0x42545320, 0x32522020, 0x38525B20, 0x2020205D, 0x20202020
    .WORD 0x203B2020, 0x6C6C754E, 0x72657420, 0x616E696D, 0x200A6574, 0x0A202020, 0x616F7469, 0x726F635F
    .WORD 0x69665F65, 0x6873696E, 0x20200A3A, 0x4F502020, 0x52202050, 0x20200A35, 0x203B2020, 0x61656C43
    .WORD 0x7075206E, 0x6D657420, 0x75622070, 0x72656666, 0x2020200A, 0x44444120, 0x50532020, 0x20505320
    .WORD 0x200A3552, 0x0A202020, 0x20202020, 0x6552203B, 0x6E727574, 0x69726F20, 0x616E6967, 0x6F70206C
    .WORD 0x65746E69, 0x20200A72, 0x4F4D2020, 0x52202056, 0x31522031, 0x20200A30, 0x200A2020, 0x50202020
    .WORD 0x2020504F, 0x0A323152, 0x20202020, 0x20504F50, 0x31315220, 0x2020200A, 0x504F5020, 0x31522020
    .WORD 0x20200A30, 0x4F502020, 0x52202050, 0x20200A39, 0x4F502020, 0x52202050, 0x20200A38, 0x4F502020
    .WORD 0x4C202050, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469, 0x6365645F, 0x44202D20, 0x6D696365, 0x63206C61
    .WORD 0x65766E6F, 0x6F697372, 0x7277206E, 0x65707061, 0x0A3B0A72, 0x3152203B, 0x64203D20, 0x69747365
    .WORD 0x6974616E, 0x62206E6F, 0x65666675, 0x203B0A72, 0x3D203252, 0x67697320, 0x2064656E, 0x65746E69
    .WORD 0x0A726567, 0x6552203B, 0x6E727574, 0x52203A73, 0x203D2031, 0x6769726F, 0x6C616E69, 0x66756220
    .WORD 0x20726566, 0x6E696F70, 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x3A636564, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x2078614D, 0x64203131, 0x74696769, 0x202B2073, 0x6E676973, 0x6E202B20
    .WORD 0x206C6C75, 0x3331203D, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x31203352, 0x20202030
    .WORD 0x20202020, 0x20202020, 0x6142203B, 0x31206573, 0x20200A30, 0x494C2020, 0x52202020, 0x20312034
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x67695320, 0x0A64656E, 0x20202020, 0x2020494C, 0x20355220
    .WORD 0x20203331, 0x20202020, 0x20202020, 0x54203B20, 0x20706D65, 0x66667562, 0x73207265, 0x0A657A69
    .WORD 0x20202020, 0x4C4C4143, 0x6F746920, 0x6F635F61, 0x200A6572, 0x0A202020, 0x20202020, 0x20504F50
    .WORD 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x7469203B, 0x685F616F, 0x2D207865, 0x78654820, 0x63656461, 0x6C616D69
    .WORD 0x6E6F6320, 0x73726576, 0x206E6F69, 0x70617277, 0x0A726570, 0x203B0A3B, 0x3D203152, 0x73656420
    .WORD 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566, 0x3252203B, 0x75203D20, 0x6769736E, 0x2064656E
    .WORD 0x65746E69, 0x0A726567, 0x6552203B, 0x6E727574, 0x52203A73, 0x203D2031, 0x6769726F, 0x6C616E69
    .WORD 0x66756220, 0x20726566, 0x6E696F70, 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x3A786568, 0x2020200A, 0x53555020, 0x524C2048
    .WORD 0x2020200A, 0x20200A20, 0x203B2020, 0x2078614D, 0x69642038, 0x73746967, 0x6E202B20, 0x206C6C75
    .WORD 0x2039203D, 0x65747962, 0x20200A73, 0x494C2020, 0x52202020, 0x36312033, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x73614220, 0x36312065, 0x2020200A, 0x20494C20, 0x34522020, 0x20203020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x69736E55, 0x64656E67, 0x68732820, 0x2073776F, 0x20776172, 0x73746962
    .WORD 0x20200A29, 0x494C2020, 0x52202020, 0x20392035, 0x20202020, 0x20202020, 0x3B202020, 0x6D655420
    .WORD 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020, 0x69204C4C, 0x5F616F74, 0x65726F63
    .WORD 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469, 0x6E69625F
    .WORD 0x42202D20, 0x72616E69, 0x6F632079, 0x7265766E, 0x6E6F6973, 0x61727720, 0x72657070, 0x3B0A3B0A
    .WORD 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032
    .WORD 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152
    .WORD 0x69726F20, 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x6E69625F, 0x20200A3A
    .WORD 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20, 0x20323320, 0x73746962
    .WORD 0x6E202B20, 0x206C6C75, 0x3333203D, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x32203352
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x6142203B, 0x32206573, 0x2020200A, 0x20494C20, 0x34522020
    .WORD 0x20203020, 0x20202020, 0x20202020, 0x203B2020, 0x69736E55, 0x64656E67, 0x68732820, 0x2073776F
    .WORD 0x20776172, 0x73746962, 0x20200A29, 0x494C2020, 0x52202020, 0x33332035, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020, 0x69204C4C
    .WORD 0x5F616F74, 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52, 0x45522020
    .WORD 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D
    .WORD 0x616F7469, 0x6769735F, 0x5F64656E, 0x20786568, 0x6953202D, 0x64656E67, 0x78656820, 0x63656461
    .WORD 0x6C616D69, 0x61727720, 0x72657070, 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461
    .WORD 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032, 0x6E676973, 0x69206465, 0x6765746E, 0x3B0A7265
    .WORD 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20, 0x69676972, 0x206C616E, 0x66667562, 0x70207265
    .WORD 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x74690A2D, 0x735F616F, 0x656E6769, 0x65685F64, 0x200A3A78, 0x50202020, 0x20485355, 0x200A524C
    .WORD 0x0A202020, 0x20202020, 0x614D203B, 0x20382078, 0x69676964, 0x2B207374, 0x67697320, 0x202B206E
    .WORD 0x6C6C756E, 0x31203D20, 0x79622030, 0x0A736574, 0x20202020, 0x2020494C, 0x20335220, 0x20203631
    .WORD 0x20202020, 0x20202020, 0x42203B20, 0x20657361, 0x200A3631, 0x4C202020, 0x20202049, 0x31203452
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x6953203B, 0x64656E67, 0x68732820, 0x2073776F, 0x6E676973
    .WORD 0x20200A29, 0x494C2020, 0x52202020, 0x30312035, 0x20202020, 0x20202020, 0x3B202020, 0x6D655420
    .WORD 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020, 0x69204C4C, 0x5F616F74, 0x65726F63
    .WORD 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469, 0x6769735F
    .WORD 0x5F64656E, 0x206E6962, 0x6953202D, 0x64656E67, 0x6E696220, 0x20797261, 0x70617277, 0x0A726570
    .WORD 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566, 0x3252203B
    .WORD 0x73203D20, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x75746552, 0x3A736E72, 0x20315220
    .WORD 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072, 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F74690A, 0x69735F61, 0x64656E67
    .WORD 0x6E69625F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20
    .WORD 0x20323320, 0x73746962, 0x73202B20, 0x206E6769, 0x756E202B, 0x3D206C6C, 0x20343320, 0x65747962
    .WORD 0x20200A73, 0x494C2020, 0x52202020, 0x20322033, 0x20202020, 0x20202020, 0x3B202020, 0x73614220
    .WORD 0x0A322065, 0x20202020, 0x2020494C, 0x20345220, 0x20202031, 0x20202020, 0x20202020, 0x53203B20
    .WORD 0x656E6769, 0x73282064, 0x73776F68, 0x67697320, 0x200A296E, 0x4C202020, 0x20202049, 0x33203552
    .WORD 0x20202034, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072, 0x200A657A
    .WORD 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020, 0x2020504F
    .WORD 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7473203B
    .WORD 0x79706372, 0x73656428, 0x73202C74, 0x0A296372, 0x203B0A3B, 0x69706F43, 0x73207365, 0x6E697274
    .WORD 0x72662067, 0x73206D6F, 0x74206372, 0x6564206F, 0x69207473, 0x756C636E, 0x676E6964, 0x72657420
    .WORD 0x616E696D, 0x676E6974, 0x6C756E20, 0x6863206C, 0x63617261, 0x0A726574, 0x203B0A3B, 0x75706E49
    .WORD 0x3B0A3A74, 0x52202020, 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70, 0x0A726574
    .WORD 0x2020203B, 0x3D203252, 0x756F7320, 0x20656372, 0x6E696F70, 0x0A726574, 0x203B0A3B, 0x7074754F
    .WORD 0x0A3A7475, 0x2020203B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x696F7020, 0x7265746E
    .WORD 0x726F2820, 0x6E696769, 0x0A296C61, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x63727473
    .WORD 0x0A3A7970, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x20564F4D, 0x52203352, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x726F2065, 0x6E696769, 0x64206C61, 0x69747365
    .WORD 0x6974616E, 0x70206E6F, 0x746E696F, 0x200A7265, 0x4D202020, 0x5220564F, 0x32522034, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x65766153, 0x756F7320, 0x20656372, 0x6E696F70, 0x0A726574
    .WORD 0x20202020, 0x7274730A, 0x5F797063, 0x706F6F6C, 0x20200A3A, 0x444C2020, 0x32522042, 0x34525B20
    .WORD 0x2020205D, 0x20202020, 0x20202020, 0x4C203B20, 0x2064616F, 0x65747962, 0x6F726620, 0x6F73206D
    .WORD 0x65637275, 0x2020200A, 0x42545320, 0x20325220, 0x5D31525B, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x7453203B, 0x2065726F, 0x65747962, 0x206F7420, 0x74736564, 0x74616E69, 0x0A6E6F69, 0x20202020
    .WORD 0x2020200A, 0x504D4320, 0x20325220, 0x20202030, 0x20202020, 0x20202020, 0x20202020, 0x6843203B
    .WORD 0x206B6365, 0x69206669, 0x20732774, 0x6C6C756E, 0x72657420, 0x616E696D, 0x0A726F74, 0x20202020
    .WORD 0x20514542, 0x63727473, 0x645F7970, 0x20656E6F, 0x20202020, 0x3B202020, 0x20664920, 0x6F72657A
    .WORD 0x6577202C, 0x20657227, 0x656E6F64, 0x2020200A, 0x20200A20, 0x44412020, 0x31522044, 0x20315220
    .WORD 0x20202031, 0x20202020, 0x20202020, 0x41203B20, 0x6E617664, 0x64206563, 0x69747365, 0x6974616E
    .WORD 0x70206E6F, 0x746E696F, 0x200A7265, 0x41202020, 0x52204444, 0x34522034, 0x20203120, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x61766441, 0x2065636E, 0x72756F73, 0x70206563, 0x746E696F, 0x200A7265
    .WORD 0x42202020, 0x72747320, 0x5F797063, 0x706F6F6C, 0x2020200A, 0x74730A20, 0x79706372, 0x6E6F645F
    .WORD 0x200A3A65, 0x4D202020, 0x5220564F, 0x33522031, 0x20202020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x75746552, 0x6F206E72, 0x69676972, 0x206C616E, 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70
    .WORD 0x0A726574, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x70203B0A, 0x746E6972, 0x20292866, 0x6F6E202D, 0x28206574, 0x6F686365
    .WORD 0x6163202C, 0x73202C74, 0x70202C68, 0x6F642073, 0x6E20746E, 0x20646565, 0x79207469, 0x63207465
    .WORD 0x62206E61, 0x616D2065, 0x77206564, 0x20687469, 0x63747570, 0x29726168, 0x3B0A3B0A, 0x6E695420
    .WORD 0x6D692079, 0x6D656C70, 0x61746E65, 0x6E6F6974, 0x6C6E6F20, 0x3B0A2E79, 0x53203B0A, 0x6F707075
    .WORD 0x64657472, 0x0A3B0A3A, 0x2020203B, 0x20202525, 0x20202020, 0x63726570, 0x0A746E65, 0x2020203B
    .WORD 0x3B0A7325, 0x25202020, 0x203B0A64, 0x78252020, 0x20203B0A, 0x0A632520, 0x203B0A3B, 0x77206F4E
    .WORD 0x68746469, 0x203B0A2E, 0x70206F4E, 0x69636572, 0x6E6F6973, 0x203B0A2E, 0x66206F4E, 0x74616F6C
    .WORD 0x20676E69, 0x6E696F70, 0x3B0A2E74, 0x4C203B0A, 0x72657461, 0x6C707320, 0x69207469, 0x3A6F746E
    .WORD 0x3B0A3B0A, 0x69727020, 0x2866746E, 0x203B0A29, 0x69727076, 0x2866746E, 0x203B0A29, 0x706E7376
    .WORD 0x746E6972, 0x0A292866, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6E697270, 0x0A3A6674
    .WORD 0x2020200A, 0x54203B20, 0x0A4F444F, 0x20202020, 0x20200A3B, 0x203B2020, 0x6E616373, 0x726F6620
    .WORD 0x2074616D, 0x69727473, 0x200A676E, 0x3B202020, 0x706F6320, 0x6F6E2079, 0x6C616D72, 0x61686320
    .WORD 0x200A7372, 0x3B202020, 0x63656420, 0x2065646F, 0x20200A25, 0x203B2020, 0x70736964, 0x68637461
    .WORD 0x726F6620, 0x7474616D, 0x200A7265, 0x3B202020, 0x2020200A, 0x25203B20, 0x20200A73, 0x203B2020
    .WORD 0x200A6425, 0x3B202020, 0x0A782520, 0x20202020, 0x6325203B, 0x20200A0A, 0x45522020, 0x0A0A0A54
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x44203B0A, 0x20617461, 0x74636553, 0x0A6E6F69
    .WORD 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x63617073, 0x74735F65, 0x200A3A72, 0x2E202020
    .WORD 0x49435341, 0x22205A49, 0x0A0A2220, 0x6C77656E, 0x5F656E69, 0x3A727473, 0x2020200A, 0x53412E20
    .WORD 0x5A494943, 0x6E5C2220, 0x630A0A22, 0x75625F68, 0x200A3A66, 0x2E202020, 0x49435341, 0x22205A49
    .WORD 0x0022305C, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

    .SPACE 1024
tarfs_end:
[ASM] Built memory.img (689664 bytes)
