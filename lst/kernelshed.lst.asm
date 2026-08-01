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
;   Map check  - Last Adress: 0x0000A64E  Last OS page 0x0000C000

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

; ================================================================
; Dirent structure for readdir (matches userspace)
; ================================================================
.EQU DT_REG,        1          ; regular file
.EQU DT_DIR,        2          ; directory

.EQU DIRENT_INODE,  0          ; uint32_t d_ino  (dummy inode)
.EQU DIRENT_SIZE,   4          ; uint32_t d_size (file size in bytes)
.EQU DIRENT_TYPE,   8          ; uint32_t d_type (DT_REG, DT_DIR)
.EQU DIRENT_NAME,   12         ; char     d_name[64]
.EQU DIRENT_NAME_LEN, 64
.EQU DIRENT_SIZEOF, 76



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
0x00001010       DEBUG 1
0x00001014       B idle_loop



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


        ;test read dirs from tarfs probably needs to be removed later
0x00002064           LI R1 etc_path
0x0000206C   CALL tarfs_readdir1

0x00002074           LI R1 bin_path
0x0000207C   CALL tarfs_readdir1

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

syscall_execve1:
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
    ; 4) zero the task's data page and load the file content into the code page (USER_CODE_VA 0x43000)
    ; 5) commit the new task state: PC=user_code_va, USP=USER_STACK_TOP, program break reset
    ; 6) remap the code page read-only map page to code page and free any previous exec page
    ; 7) process argc argv by copy em out of order so they fit perfectly on top of user stack frame
    ; of the new task
    ; 8) restore the trapframe to begin executing the new program
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

0x0000274C       POP R4                         ; remember argv ptr from start of syscall_execve
0x00002750       LI R6 0                        ; R6 = argc counter

    ; Step 1: Count argc - walk on argv ptrs count argc till  we find NULL check above
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

execve_copy_reverse:        ; R7(i) = (argc-1 ... 0)
0x000027AC       LI  R8 -1
0x000027B4       CMP R7 R8
0x000027B8       BEQ execve_strings_done

    ; source string = argv[i] starting from last arg string
0x000027C0       MOV R8 R7
0x000027C4       SHL R8 R8 2             ;R7(i)*4+argv ptr => R9(&argv[i])
0x000027C8       ADD R9 R4 R8
0x000027CC       LDW R10 [R9]            ;get string ptr from last argv[argc-1] (in first iteration)

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
0x000027F8       ADD R9 R11 R8               ;r9=&temp argv[i]  which is = R7(i)*4+&temp argv[] array storage
0x000027FC       STW R5 [R9]                 ;R5->[R9] string pointer on user stack

    ; memcpy()
0x00002800       LI R8 0

execve_copy_string:             ; first copy strings ptrs from (argv array) to temp storage
                                ; from last string to first - opposite order
0x00002808       LDB R2 [R10 + R8]           ; R10 execv argv &string[i]  (last to first)
0x0000280C       STB R2 [R5 + R8]            ; R5 same in tmp

0x00002810       CMP R2 0
0x00002814       BEQ execve_copy_done

0x0000281C       ADD R8 R8 1                 ; to next char in string
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
    ; argv data copied. now - Copy argv pointers
    ;-------------------------------------------------------------
0x00002850       LI R7 0

execve_copy_argv:

0x00002858       CMP R7 R6
0x0000285C       BEQ execve_copy_argv_done

0x00002864       MOV R8 R7
0x00002868       SHL R8 R8 2              ; R7 argv index

0x0000286C       LDW R12 [R11 + R8]       ; we copy stings pointers here (not actual strings!)
                             ; R11 - &execve_tmp_argv
0x00002870       STW R12 [R9 + R8]        ; R9 - write head on user stack

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

; as it should be clear
; if fail occured we rollback depending at what stage fail occured and free used resources
; then we exit back to child process with fail exit code
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
    .SPACE 64        ; up to 16 × 4-byte argv pointers

;=============================================================
; exec temporary workspace
;=============================================================

.EQU EXEC_MAX_ARGS,      16
.EQU EXEC_MAX_PATH,           128
.EQU EXEC_MAX_STRINGS,        512
;store pathname
exec_path:
    .SPACE EXEC_MAX_PATH
;store arg count
exec_argc:
    .WORD 0
;store offsets in exec_strings - starting string indexes (not ptrs)
exec_argv_offsets:          ; eg 0,8
    .SPACE EXEC_MAX_ARGS * 4
;offset after last string - length (bytes) of blob exec_string
exec_strings_used:  ; eg 13
    .WORD 0
;strings\0args\0
exec_strings:
    .SPACE EXEC_MAX_STRINGS

;=============================================================
; exec stack image workspace
;=============================================================
;exec_stack_image->
;+----------------+
;| argc           |
;| argv[0]        |
;| argv[1]        |
;| ...            |
;| NULL           |
;| strings...     |
;+----------------+
;exec_stack_used (len)

;max stack image
.EQU EXEC_STACK_SIZE,    1024

exec_stack_image:
    .SPACE EXEC_STACK_SIZE

exec_stack_used:
    .WORD 0

;============================================
; better execve
;============================================

syscall_execve:
    ;================================================================
    ; execve(path, argv, envp)
    ; R1 = user path
    ; R2 = user argv (NULL-terminated vector of user string pointers)
    ; R3 = user envp (ignored for now)
    ;
    ; overview and why its better then previous what serous obstacles it is able to overcome

0x00003150       LDW R8 [SP + TF_R1]        ; user path pointer
0x00003154       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00003158       MOV R11 R9                 ; save to R11

0x0000315C       LI  R1 exec_path
0x00003164       MOV R2 R8
0x00003168       LI  R3 EXEC_MAX_PATH
0x00003170       BL copy_user_string        ;copy path string to ws
0x00003178       CMP R1 0
0x0000317C       BEQ execve_badfault

    ;init execve ws
0x00003184       LI R1 exec_argc
0x0000318C       LI R2 0
0x00003194       STW R2 [R1]

    ;count argc

0x00003198       MOV R8 R9               ; user argv
0x0000319C       LI  R6 0                ; argc
;count ptrs in array of ptrs argv till 0 -null end
argc_loop:
0x000031A4       CMP R8 0                ;if no argv 0-null
0x000031A8       BEQ argc_done
0x000031B0       LDW R3 [R8]
0x000031B4       CMP R3 0                ;if end
0x000031B8       BEQ argc_done
0x000031C0       CMP R6 EXEC_MAX_ARGS    ;if too much MAX argc count
0x000031C4       BGE exec_badfault
0x000031CC       ADD R6 R6 1
0x000031D0       ADD R8 R8 4
0x000031D4       B argc_loop
argc_done:
0x000031DC       LI R1 exec_argc         ;store it to ws
0x000031E4       STW R6 [R1]

0x000031E8       MOV R9 R6               ;R9 argc R11 user argv pointer
0x000031EC       MOV R8 R11
0x000031F0       BL  copy_argv_strings   ;fill arrays in ws from argvs
0x000031F8       CMP R1 0
0x000031FC       BNE exec_fail

0x00003204       LI R1 exec_path
0x0000320C       BL exec_load_binary
0x00003214       CMP R1 0
0x00003218       BEQ exec_fail

0x00003220       MOV R11 R1        ; new code page
0x00003224       MOV R12 R2        ; old code page
0x00003228       BL exec_build_stack_image
0x00003230       CMP R1 0
0x00003234       BNE exec_rollback

0x0000323C       MOV R1 R11
0x00003240       MOV R2 R12

0x00003244       B exec_commit_image

exec_badfault:
0x0000324C       NOP
exec_fail:
0x00003250       NOP
exec_rollback:
0x00003254       LI R1 ERR_FAULT
0x0000325C       STW R1 [SP + TF_R1]
0x00003260       B trap_restore
;=============================================================
; exec_commit_image
;
; Commit a successfully loaded executable.
;
; IN:
;   R1 = new code page PA
;   R2 = old code page PA (0 if none)
;
; Uses:
;   exec_stack_image
;   exec_stack_used
;   exec_argc
;
; Does not return on success.
;=============================================================

exec_commit_image:

  ;  PUSH LR
  ;  PUSH R8
  ;  PUSH R9
  ;  PUSH R10
  ;  PUSH R11
  ;  PUSH R12

0x00003268       MOV R11 R1              ; new page
0x0000326C       MOV R12 R2              ; old page

; macro: GET_CURR_TASK_IDX R4
0x00003270   LI R1 CURRENT_TASK
0x00003278   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x0000327C   LI R1 TASK_SIZE
0x00003284   MUL R3 R4 R1
0x00003288   LI R5 tasks
0x00003290   ADD R5 R5 R3

0x00003294       LI  R1 exec_stack_used
0x0000329C       LDW R8 [R1]
0x000032A0       LI  R9 USER_STACK_TOP
0x000032A8       SUB R9 R9 R8            ; final user SP
0x000032AC       MOV R1 R9               ;  R2->R9 len R8 - cpy our image for stack
0x000032B0       LI  R2 exec_stack_image
0x000032B8       MOV R3 R8
0x000032BC       BL memcpy

0x000032C4       LI R1 USER_CODE_VA      ; commit task state
; macro: TASK_SET_PC R5,R1
0x000032CC   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5,R11
0x000032D0   STW R11 [R5 + TASK_CODE_PAGE]
0x000032D4       MOV R1 R9
; macro: TASK_SET_USP R5,R1
0x000032D8   STW R1 [R5 + TASK_USP]
0x000032DC       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5,R1
0x000032E4   STW R1 [R5 + TASK_BREAK]

; macro: TASK_GET_PTBR R1,R5
0x000032E8   LDW R1 [R5 + TASK_PTBR]
0x000032EC       LI R2 USER_CODE_VA
0x000032F4       MOV R3 R11
0x000032F8       LI R4 KERNEL_USER_ALL   ; map code page RX subject to permissions on X (now all X)
0x00003300       BL map_page_rt

0x00003308       CMP R12 0               ; free old pa page (R12) if have
0x0000330C       BEQ no_old_page
0x00003314       MOV R1 R12
0x00003318       BL page_free
no_old_page:

0x00003320       LI  R1 exec_argc
0x00003328       LDW R2 [R1]
0x0000332C       STW R2 [SP+TF_R1]

0x00003330       MOV R1 R9
0x00003334       ADD R1 R1 4
0x00003338       STW R1 [SP+TF_R2]       ; user sp with image on top + 4 so it points to &argv image

0x0000333C       LI R1 0                 ; envp
0x00003344       STW R1 [SP+TF_R3]

0x00003348       STW R9 [SP+TF_USP]      ; user sp

0x0000334C       LI R1 0
0x00003354       STW R1 [SP+TF_R4]
0x00003358       STW R1 [SP+TF_R5]
0x0000335C       STW R1 [SP+TF_R6]
0x00003360       STW R1 [SP+TF_R7]
0x00003364       STW R1 [SP+TF_R8]
0x00003368       STW R1 [SP+TF_R9]
0x0000336C       STW R1 [SP+TF_R10]
0x00003370       STW R1 [SP+TF_R11]
0x00003374       STW R1 [SP+TF_R12]

0x00003378       LI R1 USER_CODE_VA
0x00003380       STW R1 [SP+TF_SEPC]

  ;  POP R12
  ;  POP R11
  ;  POP R10
  ;  POP R9
  ;  POP R8
  ;  POP LR

0x00003384       B trap_restore



;====================================================================
; exec_build_stack_image
;
; Build initial process stack entirely in kernel memory.
;
; Stack layout:
;
;   +----------------------------+
;   | argc                       |
;   | argv[0]                    |
;   | argv[1]                    |
;   | ...                        |
;   | argv[argc] = NULL          |
;   | string blob                |
;   +----------------------------+
;
; INPUT:
;   exec_argc
;   exec_strings
;   exec_strings_used
;   exec_argv_offsets[]
;
; OUTPUT:
;   exec_stack_image
;   exec_stack_used
;
; RETURNS:
;   R1 = 0 success
;   R1 = ERR_NOMEM
;====================================================================

exec_build_stack_image:
0x0000338C       PUSH LR
0x00003390       PUSH R8
0x00003394       PUSH R9
0x00003398       PUSH R10
0x0000339C       PUSH R11
0x000033A0       PUSH R12

0x000033A4       LI   R1 exec_argc   ;argc
0x000033AC       LDW  R6 [R1]

0x000033B0       MOV  R7 R6          ;pointer_bytes = (argc+2)*4
0x000033B4       ADD  R7 R7 2
0x000033B8       SHL  R7 R7 2

0x000033BC       LI   R1 exec_strings_used   ; strings blob len
0x000033C4       LDW  R8 [R1]

    ;----------------------------------------------------------
    ; total = pointer_bytes(len argv ptr array + 4b argc) + string_bytes(len string blobs)
    ;----------------------------------------------------------

0x000033C8       ADD  R9 R7 R8
    ; check for MAX
0x000033CC       LI   R1 EXEC_STACK_SIZE
0x000033D4       CMP  R9 R1
0x000033D8       BGT  exec_stack_nomem

0x000033E0       LI   R1 exec_stack_used     ; save used size
0x000033E8       STW  R9 [R1]

0x000033EC       LI   R10 exec_stack_image   ;stack base for image
    ; building image for stack as on picture
0x000033F4       STW  R6 [R10]   ;argc

    ; copy string blob
0x000033F8       MOV  R1 R10
0x000033FC       ADD  R1 R1 R7   ; skip room for pointer_bytes see picture
0x00003400       LI   R2 exec_strings
0x00003408       MOV  R3 R8      ; blob len
0x0000340C       BL   memcpy

    ;----------------------------------------------------------
    ; future user addresses
    ;----------------------------------------------------------

0x00003414       LI   R11 USER_STACK_TOP
0x0000341C       SUB  R11 R11 R9             ; r9 total image len, R11 start address image in the user stack
0x00003420       MOV  R12 R11
0x00003424       ADD  R12 R12 R7             ; r12 pointer bytes ptr in image in stack - start of string blob

    ;----------------------------------------------------------
    ; argv table build
    ;----------------------------------------------------------

0x00003428       ADD  R10 R10 4              ; argv[0] starts after argc
0x0000342C       LI   R4 exec_argv_offsets   ; args offsetss array
0x00003434       LI   R5 0
argv_loop:
0x0000343C       CMP  R5 R6                  ; argc
0x00003440       BEQ  argv_done              ; if finished
0x00003448       MOV  R1 R5
0x0000344C       SHL  R1 R1 2
0x00003450       LDW  R2 [R4+R1]             ; get arg[i] offset
0x00003454       ADD  R2 R2 R12              ; compute R2 - blobs string adress for this arg[i]
0x00003458       STW  R2 [R10+R1]            ; store this address to argv array in image
0x0000345C       ADD  R5 R5 1
0x00003460       B    argv_loop
argv_done:
0x00003468       MOV  R1 R6
0x0000346C       SHL  R1 R1 2

0x00003470       LI   R2 0
0x00003478       STW  R2 [R10+R1]            ; put null here: argv[argc] = NULL
    ;success
0x0000347C       LI   R1 0
0x00003484       POP  R12
0x00003488       POP  R11
0x0000348C       POP  R10
0x00003490       POP  R9
0x00003494       POP  R8
0x00003498       POP  LR
0x0000349C       RET

exec_stack_nomem:
0x000034A0       LI   R1 ERR_NOMEM
0x000034A8       POP  R12
0x000034AC       POP  R11
0x000034B0       POP  R10
0x000034B4       POP  R9
0x000034B8       POP  R8
0x000034BC       POP  LR
0x000034C0       RET

;=============================================================
; exec_load_binary
;
; Load executable into USER_CODE_VA.
;
; IN:
;   R1 = kernel pathname
;
; OUT:
;   R1 = new code page PA
;   R2 = old code page PA
;
;   R1 = 0 on failure
;   R2 = errno
;
;=============================================================
exec_load_binary:
0x000034C4       PUSH LR
0x000034C8       PUSH R7
0x000034CC       PUSH R8
0x000034D0       PUSH R9
0x000034D4       PUSH R10
0x000034D8       PUSH R11
0x000034DC       PUSH R12

0x000034E0       BL vfs_lookup   ; lookup inode for the file
0x000034E8       CMP R1 0
0x000034EC       BEQ load_noent
0x000034F4       MOV R9 R1

0x000034F8       LDW R1 [R9 + INODE_TYPE]    ;check inode type/size
0x000034FC       LI R2 INODE_DIR
0x00003504       CMP R1 R2
0x00003508       BEQ load_noexec
0x00003510       LDW R3 [R9 + INODE_SIZE]
0x00003514       LI R4 PAGE_SIZE
0x0000351C       CMP R3 R4
0x00003520       BGT load_noexec

0x00003528       BL file_alloc               ;allocate file
0x00003530       CMP R1 0
0x00003534       BEQ load_nomem
0x0000353C       MOV R10 R1                  ; savr file ptr R10
0x00003540       MOV R1 R10
0x00003544       MOV R2 R9
0x00003548       LI R3 FD_FLAG_READ
0x00003550       BL file_init

0x00003558       BL page_alloc               ; pa page for code
0x00003560       CMP R1 0
0x00003564       BEQ load_file_fail

0x0000356C       MOV R11 R1                  ;new pa page code

; macro: GET_CURR_TASK_IDX R4        ;current task
0x00003570   LI R1 CURRENT_TASK
0x00003578   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x0000357C   LI R1 TASK_SIZE
0x00003584   MUL R3 R4 R1
0x00003588   LI R5 tasks
0x00003590   ADD R5 R5 R3
; macro: TASK_GET_CODE_PAGE R12,R5   ; save old pa code page from this task to R12
0x00003594   LDW R12 [R5 + TASK_CODE_PAGE]

; macro: TASK_GET_PTBR R1,R5
0x00003598   LDW R1 [R5 + TASK_PTBR]
0x0000359C       LI R2 USER_CODE_VA
0x000035A4       MOV R3 R11                  ;new pa code page
0x000035A8       LI R4 USER_RW
0x000035B0       BL map_page_rt              ;map it for loading to USER_CODE_VA

; macro: TASK_GET_DATA_PAGE R1,R5    ; tasks va data_page
0x000035B8   LDW R1 [R5 + TASK_DATA_PAGE]
0x000035BC       CMP R1 0
0x000035C0       BEQ load_read
0x000035C8       LI R3 PAGE_SIZE
0x000035D0       BL mem_zero                 ; clean task data_page

load_read:
0x000035D8       MOV R1 R10                  ; file* with program
0x000035DC       LI R2 USER_CODE_VA
0x000035E4       LI R3 PAGE_SIZE
0x000035EC       BL file_read
0x000035F4       CMP R1 0
0x000035F8       BLT load_read_fail
0x00003600       MOV R1 R10                  ; release file*
0x00003604       BL file_put
    ; all loaedd R1 - new code page pa R2 - old code page pa
0x0000360C       MOV R1 R11
0x00003610       MOV R2 R12

exec_lb_exit:                   ;common! exit!
0x00003614       POP R12
0x00003618       POP R11
0x0000361C       POP R10
0x00003620       POP R9
0x00003624       POP R8
0x00003628       POP R7
0x0000362C       POP LR
0x00003630       RET
; in error generally depending on state rollback allocated resources
load_read_fail:
    ; in this case release file and pa code page
0x00003634       MOV R1 R10
0x00003638       BL file_put
0x00003640       MOV R1 R11
0x00003644       BL page_free
0x0000364C       LI R1 0
0x00003654       LI R2 ERR_IO
0x0000365C       B  exec_lb_exit

load_file_fail:
0x00003664       MOV R1 R10
0x00003668       BL file_put

load_nomem:
0x00003670       LI R1 0
0x00003678       LI R2 ERR_NOMEM
0x00003680       B  exec_lb_exit

load_noexec:
0x00003688       MOV R1 R10
0x0000368C       CMP R1 0
0x00003690       BEQ noexec_skip
0x00003698       BL file_put

noexec_skip:
0x000036A0       LI R1 0
0x000036A8       LI R2 ERR_NOEXEC
0x000036B0       B  exec_lb_exit

load_noent:
0x000036B8       LI R1 0
0x000036C0       LI R2 ERR_NOENT
0x000036C8       B  exec_lb_exit


;=============================================================
; Copy argv strings into kernel workspace
;
; IN:
;   R8 = user argv[]
;   R9 = argc
;
; OUT:
;   exec_strings
;   exec_argv_offsets[]
;   exec_strings_used
;
; destroys:
;   R7-R12
;=============================================================
copy_argv_strings:

0x000036D0       PUSH LR
0x000036D4       PUSH R7
0x000036D8       PUSH R8
0x000036DC       PUSH R9
0x000036E0       PUSH R10
0x000036E4       PUSH R11
0x000036E8       PUSH R12
    ;init this at first
0x000036EC       LI R1 exec_strings_used
0x000036F4       LI R2 0
0x000036FC       STW R2 [R1]

0x00003700       LI   R11 exec_strings      ; destination blob
0x00003708       LI   R12 0                 ; current offset
0x00003710       LI   R7 0                  ; argv index
                               ;  R8 = user argv[]
                               ;  R9 = argc
exec_capture_next_arg:
    ; finished?
0x00003718       CMP  R7 R9
0x0000371C       BEQ  exec_capture_done     ; if all agvs processed

    ;---------------------------------------------
    ; load argv[i] (ptr to string)
    ;---------------------------------------------
0x00003724       LDW  R10 [R8]

0x00003728       CMP  R10 0
0x0000372C       BEQ  exec_capture_fault     ;if argv[i]==null

    ;---------------------------------------------
    ; save offset
    ;
    ; exec_argv_offsets[i]=current_offset (in R12)
    ;---------------------------------------------
0x00003734       LI   R1 exec_argv_offsets
0x0000373C       MOV  R2 R7  ;i
0x00003740       SHL  R2 R2 2
0x00003744       ADD  R1 R1 R2
0x00003748       STW  R12 [R1]

exec_copy_string:
    ;---------------------------------------------
    ; copy one character r10 argv[i] (ptr to string) R11 ptr to exec strings
    ;---------------------------------------------
0x0000374C       LDB  R3 [R10]
0x00003750       STB  R3 [R11]
0x00003754       ADD  R10 R10 1
0x00003758       ADD  R11 R11 1
0x0000375C       ADD  R12 R12 1
    ; blob overflow?
0x00003760       LI   R1 EXEC_MAX_STRINGS
0x00003768       CMP  R12 R1
0x0000376C       BGT  exec_capture_fault
0x00003774       CMP  R3 0
0x00003778       BNE  exec_copy_string           ; end of string?
0x00003780       ADD  R8 R8 4    ;to next argv[] string
0x00003784       ADD  R7 R7 1    ;i=i+1
0x00003788       B    exec_capture_next_arg

exec_capture_done:
0x00003790       LI   R1 exec_strings_used
0x00003798       STW  R12 [R1]           ; current offset after last string
0x0000379C       LI  R1 0
0x000037A4       POP R12
0x000037A8       POP R11
0x000037AC       POP R10
0x000037B0       POP R9
0x000037B4       POP R8
0x000037B8       POP R7
0x000037BC       POP LR
0x000037C0       RET
exec_capture_fault:
0x000037C4       LI   R1 ERR_FAULT
0x000037CC       POP R12
0x000037D0       POP R11
0x000037D4       POP R10
0x000037D8       POP R9
0x000037DC       POP R8
0x000037E0       POP R7
0x000037E4       POP LR
0x000037E8       RET

syscall_fork:
    ;================================================================
    ; fork()
    ; Returns child PID in the parent and 0 in the child.
    ; This clones the current task, duplicating its address space and
    ; user-writable state while preserving a new independent child thread.
    ;================================================================

0x000037EC       BL task_clone_current
0x000037F4       CMP R1 0
0x000037F8       BEQ fork_fail

    ; We return child PID to the parent via the trapframe.
; macro: TASK_GET_PID R2, R1
0x00003800   LDW R2 [R1 + TASK_PID]
0x00003804       STW R2 [SP + TF_R1]
0x00003808       B trap_restore

fork_fail:
0x00003810       LI R1 ERR_NOMEM
0x00003818       STW R1 [SP + TF_R1]
0x0000381C       B trap_restore

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x00003824       LI R1 0
0x0000382C       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00003830       B schedule_and_switch
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
0x00003838       LDW R8 [SP + TF_R1]        ; R8 = exit code

; macro: GET_CURR_TASK_IDX R2
0x0000383C   LI R1 CURRENT_TASK
0x00003844   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003848   LI R1 TASK_SIZE
0x00003850   MUL R3 R2 R1
0x00003854   LI R5 tasks
0x0000385C   ADD R5 R5 R3

    ; Store exit code in child task struct for parent to collect in waitforpid
; macro: TASK_SET_EXIT_CODE R5, R8  ; Save exit code
0x00003860   STW R8 [R5 + TASK_EXIT_CODE]

0x00003864       PUSH R5
0x00003868       MOV R1 R5
0x0000386C       BL task_close_fds          ; close all open file descriptors of this task (if any) to free file_pool resources
0x00003874       POP R5

    ; Mark this child as zombie (still exists but not runnable)
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x00003878   LI R1 TASK_ZOMBIE
0x00003880   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00003884   LI R1 WAIT_NONE
0x0000388C   STW R1 [R5 + TASK_WAIT]

    ; Wake parent if it's waiting
; macro: TASK_GET_PPID R6, R5       ; R6 = parent PID
0x00003890   LDW R6 [R5 + TASK_PPID]

    ; find parent task by PPID
0x00003894       MOV R1 R6
0x00003898       LI R2 0                    ; Search by PID (parent's PID)
0x000038A0       BL task_find               ; R1 = found parent task*
0x000038A8       CMP R1 0
0x000038AC       BEQ no_parent_waiting
0x000038B4       MOV R7 R1                  ; R7 = parent task*
0x000038B8       MOV R11 R2                 ; save parent task index for bitmask

    ;Check if parent is waiting for this child
; macro: TASK_GET_WAIT_CHILD R8, R7 ; Child PID that parent R7 ptr is waiting for
0x000038BC   LDW R8 [R7 + TASK_WAIT_CHILD]
; macro: TASK_GET_PID R9, R5        ; This child's R5 ptr PID
0x000038C0   LDW R9 [R5 + TASK_PID]

0x000038C4       LI R10 -1
0x000038CC       CMP R8 R10                 ; if parent is waiting for any child (-1), then wake it up
0x000038D0       BEQ wake_parent            ;

0x000038D8       CMP R8 R9
0x000038DC       BNE no_parent_waiting      ; parent is waiting for a different child, do not wake it up

wake_parent:
    ; Find parent's task index for bitmask
    ; we already have parent task in R11

0x000038E4       LI R9 1
0x000038EC       SHL R9 R9 R11               ; bit for parent task

0x000038F0       LI R1 child_waitq
0x000038F8       MOV R2 R9
0x000038FC       BL waitq_wake_bitmask       ;unblock parent task waiting for this child

no_parent_waiting:
0x00003904       B schedule_and_switch

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
0x0000390C       LDW R8 [SP + TF_R1]        ; R8 = pid to wait for
0x00003910       LDW R9 [SP + TF_R2]        ; R9 = status pointer

    ; Validate status pointer
0x00003914       CMP R9 0
0x00003918       BEQ waitpid_validate_done
0x00003920       MOV R1 R9
0x00003924       LI R2 4
0x0000392C       LI R3 1
0x00003934       BL user_buffer_valid_range
0x0000393C       CMP R1 1
0x00003940       BNE waitpid_badptr

waitpid_validate_done:
; macro: GET_CURR_TASK_IDX R4
0x00003948   LI R1 CURRENT_TASK
0x00003950   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003954   LI R1 TASK_SIZE
0x0000395C   MUL R3 R4 R1
0x00003960   LI R5 tasks
0x00003968   ADD R5 R5 R3
; macro: TASK_GET_PID R10, R5       ; R10 = current (parent proc) PID
0x0000396C   LDW R10 [R5 + TASK_PID]

    ; if search for any child
0x00003970       LI  R2 -1
0x00003978       CMP R8 R2
0x0000397C       BNE find_child_by_pid
    ; set task_find to search for any child of this parent
0x00003984       MOV R1 R10                  ; R1 = parent PID (PPID in child task)
0x00003988       LI  R2 1                    ; search by PPID
0x00003990       BL task_find               ; R1 = found child task*
0x00003998       CMP R1 0
0x0000399C       BEQ waitpid_no_child        ; No any child with PPID = this parent PID found
    ;R1 child task* found
0x000039A4       B find_any_child_found
find_child_by_pid:
    ; Search for child task by PID
0x000039AC       MOV R1 R8                  ; R1 = child PID to search for
0x000039B0       LI R2 0                    ; Search by PID
0x000039B8       BL task_find               ; R1 = found child task*
0x000039C0       CMP R1 0
0x000039C4       BEQ waitpid_no_child        ; No such child

find_any_child_found:

0x000039CC       MOV R7 R1                   ; R7 = child task*

    ; Verify it's actually our child by its PPID fld
; macro: TASK_GET_PPID R1, R7
0x000039D0   LDW R1 [R7 + TASK_PPID]
0x000039D4       CMP R1 R10
0x000039D8       BNE waitpid_no_child
    ; R7 = child task*
    ; check its state, if ZOMBIE, we can reap it and return its exit code
; macro: TASK_GET_STATE R1, R7
0x000039E0   LDW R1 [R7 + TASK_STATE]
0x000039E4       CMP R1 TASK_ZOMBIE
0x000039E8       BEQ waitpid_reap_child

    ; Child running - block parent
; macro: TASK_GET_PID R1, R7
0x000039F0   LDW R1 [R7 + TASK_PID]
; macro: TASK_SET_WAIT_CHILD R5, R1
0x000039F4   STW R1 [R5 + TASK_WAIT_CHILD]

0x000039F8       LI R1 child_waitq           ; child_waitq ptr
0x00003A00       LI R2 WAIT_CHILD            ; reason
0x00003A08       LI R3 TASK_SLEEPING         ; state to set for current task
0x00003A10       BL waitq_prepare_sleep

0x00003A18       BL waitq_sleep_current     ; freeze the current task

    ; will resume here when child exits and wakes us up

waitpid_reap_child:
    ; Get exit code from child task
; macro: TASK_GET_EXIT_CODE R2, R7
0x00003A20   LDW R2 [R7 + TASK_EXIT_CODE]

    ; If status pointer is not NULL, write exit code to user space
0x00003A24       CMP R9 0
0x00003A28       BEQ waitpid_reap_done

0x00003A30       MOV R1 R9                  ; R1 = user status pointer
0x00003A34       MOV R4 R2                  ; preserve exit code in kernel source register
0x00003A38       LI  R2 4                   ; R2 = size of exit code
0x00003A40       BL copy_to_user            ; write exit code to user space

waitpid_reap_done:
; macro: TASK_GET_PID R10, R7       ; get child's PID
0x00003A48   LDW R10 [R7 + TASK_PID]
0x00003A4C       MOV R1 R7                  ; R1 = child task*
0x00003A50       BL task_destroy

0x00003A58       STW R10 [SP + TF_R1]        ; save child's PID to trapframe for return
0x00003A5C       B trap_restore

waitpid_no_child:
0x00003A64       LI R1 ERR_CHILD
0x00003A6C       STW R1 [SP + TF_R1]
0x00003A70       B trap_restore

waitpid_badptr:
0x00003A78       LI R1 ERR_FAULT
0x00003A80       STW R1 [SP + TF_R1]
0x00003A84       B trap_restore


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
0x00003A8C       PUSH R5
0x00003A90       PUSH R6
0x00003A94       PUSH R7

0x00003A98       MOV R5 R2                  ; Save search mode
0x00003A9C       MOV R7 R1                  ; Save PID/PPID
0x00003AA0       LI R2 0                    ; Task index
task_find_loop:
0x00003AA8       LI R3 MAX_TASKS
0x00003AB0       CMP R2 R3
0x00003AB4       BGE task_find_not_found

; macro: GET_TASK_PTR R4, R2
0x00003ABC   LI R1 TASK_SIZE
0x00003AC4   MUL R3 R2 R1
0x00003AC8   LI R4 tasks
0x00003AD0   ADD R4 R4 R3
; macro: TASK_GET_STATE R6, R4
0x00003AD4   LDW R6 [R4 + TASK_STATE]
0x00003AD8       CMP R6 TASK_DEAD
0x00003ADC       BEQ task_find_next         ; Skip dead tasks

    ; Search based on mode
0x00003AE4       CMP R5 0
0x00003AE8       BEQ task_find_by_pid

    ; Search by PPID
; macro: TASK_GET_PPID R6, R4
0x00003AF0   LDW R6 [R4 + TASK_PPID]
0x00003AF4       CMP R6 R7
0x00003AF8       BEQ task_find_found
0x00003B00       B task_find_next

task_find_by_pid:
; macro: TASK_GET_PID R6, R4
0x00003B08   LDW R6 [R4 + TASK_PID]
0x00003B0C       CMP R6 R7
0x00003B10       BEQ task_find_found

task_find_next:
0x00003B18       ADD R2 R2 1
0x00003B1C       B task_find_loop

task_find_found:
0x00003B24       MOV R1 R4                  ; Return task pointer
0x00003B28       MOV R2 R2                  ; Return task index
0x00003B2C       POP R7
0x00003B30       POP R6
0x00003B34       POP R5
0x00003B38       RET

task_find_not_found:
0x00003B3C       LI R1 0
0x00003B44       POP R7
0x00003B48       POP R6
0x00003B4C       POP R5
0x00003B50       RET

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00003B54   LI R1 CURRENT_TASK
0x00003B5C   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003B60   LI R1 TASK_SIZE
0x00003B68   MUL R3 R2 R1
0x00003B6C   LI R5 tasks
0x00003B74   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00003B78   LDW R1 [R5 + TASK_PID]

0x00003B7C       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00003B80       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00003B88       LDW R1 [SP + TF_R1]
0x00003B8C       STW R1 [SP + TF_R1]

0x00003B90       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00003B98       LDW R1 [SP + TF_R1]
0x00003B9C       LDW R2 [SP + TF_R2]

0x00003BA0       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003BA8       CMP R1 0
0x00003BAC       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003BB4   LI R1 CURRENT_TASK
0x00003BBC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003BC0   LI R1 TASK_SIZE
0x00003BC8   MUL R3 R4 R1
0x00003BCC   LI R5 tasks
0x00003BD4   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003BD8   LDW R1 [R5 + TASK_KBUF_RD_PTR]

0x00003BDC       BL vfs_open

0x00003BE4       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x00003BE8       B trap_restore

open_fail_fault:
0x00003BF0       LI R1 ERR_FAULT
0x00003BF8       STW R1 [SP + TF_R1]     ;file not opened ERR
0x00003BFC       B trap_restore


syscall_sleep:
    ;================================================================
    ; sleep(ms)
    ; R1 = milliseconds to sleep
    ;
    ; Returns:
    ;   R1 = 0 on success (slept full duration)
    ;   R1 = -1 on error (invalid time)
    ;================================================================

0x00003C04       LDW R8 [SP + TF_R1]        ; R8 = milliseconds

0x00003C08       CMP R8 0
0x00003C0C       BLE sleep_invalid          ; must be positive

; macro: GET_CURR_TASK_IDX R4
0x00003C14   LI R1 CURRENT_TASK
0x00003C1C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003C20   LI R1 TASK_SIZE
0x00003C28   MUL R3 R4 R1
0x00003C2C   LI R5 tasks
0x00003C34   ADD R5 R5 R3

    ; Calculate wake time in PIT ticks (1 ms per tick).
0x00003C38       LI R3 timer_ticks
0x00003C40       LDW R6 [R3]                ; current ticks (1ms per tick)

    ; Convert ms to ticks: 1 tick = 1 ms
0x00003C44       MOV R7 R8                  ; R7 = ticks to sleep

0x00003C48       ADD R6 R6 R7               ; R6 = wake time in ticks

    ; Store wake time in task struct
; macro: TASK_SET_WAKE_TIME R5, R6
0x00003C4C   STW R6 [R5 + TASK_WAKE_TIME]

    ; Use existing wait queue infrastructure
0x00003C50       LI R1 sleep_waitq           ; sleep_waitq ptr
0x00003C58       LI R2 WAIT_SLEEP            ; reason
0x00003C60       LI R3 TASK_SLEEPING         ; new state (if other then blocked_io)
0x00003C68       BL waitq_prepare_sleep     ; This marks task as TASK_SLEEP and adds it to the sleep_waitq

0x00003C70       BL waitq_sleep_current     ; freeze the current task in kernel side until it is woken up by the timer interrupt handler when the wake time is reached

    ; Return 0 (will be set when woken)
0x00003C78       LI R1 0
0x00003C80       STW R1 [SP + TF_R1]
0x00003C84       B trap_restore

sleep_invalid:
0x00003C8C       LI R1 ERR_FAULT
0x00003C94       STW R1 [SP + TF_R1]
0x00003C98       B trap_restore


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
0x00003CA0       PUSH LR

0x00003CA4       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00003CA8   LI R1 CURRENT_TASK
0x00003CB0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003CB4   LI R1 TASK_SIZE
0x00003CBC   MUL R3 R4 R1
0x00003CC0   LI R5 tasks
0x00003CC8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x00003CCC   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x00003CD0       PUSH R9                    ; original destination returned on success
0x00003CD4       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00003CDC       LI R11 KBUFFER_SIZE
0x00003CE4       CMP R10 R11
0x00003CE8       BGE copy_path_fail

0x00003CF0       PUSH R8
0x00003CF4       PUSH R9
0x00003CF8       PUSH R10
0x00003CFC       MOV R1 R8
0x00003D00       LI R2 1
0x00003D08       LI R3 0                    ; read access from user source
0x00003D10       BL user_buffer_valid_range
0x00003D18       POP R10
0x00003D1C       POP R9
0x00003D20       POP R8
0x00003D24       CMP R1 1
0x00003D28       BNE copy_path_fail

0x00003D30       LDB R4 [R8]
0x00003D34       STB R4 [R9]
0x00003D38       CMP R4 0
0x00003D3C       BEQ copy_path_done

0x00003D44       ADD R8 R8 1
0x00003D48       ADD R9 R9 1
0x00003D4C       ADD R10 R10 1
0x00003D50       B copy_path_loop

copy_path_done:
0x00003D58       POP R1                     ; original kernel path pointer
0x00003D5C       POP LR
0x00003D60       RET

copy_path_fail:
0x00003D64       POP R1                     ; discard original kernel path pointer
0x00003D68       LI R1 0
0x00003D70       POP LR
0x00003D74       RET

;====================================================================
; copy_user_string
;
; Copy NUL-terminated string from user memory into kernel buffer.
;
; IN:
;   R1 = kernel destination
;   R2 = user source
;   R3 = maximum bytes (including terminating NUL)
;
; OUT:
;   R1 = bytes copied (including terminating NUL)
;   R1 = 0 on failure
;
; Clobbers:
;   R4-R11
;====================================================================

copy_user_string:

0x00003D78       PUSH LR
0x00003D7C       PUSH R8
0x00003D80       PUSH R9
0x00003D84       PUSH R10
0x00003D88       PUSH R11

0x00003D8C       MOV R8 R1          ; kernel dst
0x00003D90       MOV R9 R2          ; user src
0x00003D94       MOV R10 R3         ; max length
0x00003D98       LI  R11 0          ; bytes copied

copy_user_loop:
    ; reached max?
0x00003DA0       CMP R11 R10
0x00003DA4       BGE copy_user_fail

    ; validate one byte
0x00003DAC       PUSH R8
0x00003DB0       PUSH R9
0x00003DB4       PUSH R10
0x00003DB8       PUSH R11
0x00003DBC       MOV R1 R9
0x00003DC0       LI  R2 1
0x00003DC8       LI  R3 0           ; read access
0x00003DD0       BL user_buffer_valid_range
0x00003DD8       POP R11
0x00003DDC       POP R10
0x00003DE0       POP R9
0x00003DE4       POP R8
0x00003DE8       CMP R1 1
0x00003DEC       BNE copy_user_fail

    ; copy byte
0x00003DF4       LDB R4 [R9]
0x00003DF8       STB R4 [R8]
    ;cpy ctr
0x00003DFC       ADD R11 R11 1
0x00003E00       CMP R4 0    ;if string ends (null)
0x00003E04       BEQ copy_user_done

0x00003E0C       ADD R8 R8 1 ;advance
0x00003E10       ADD R9 R9 1
0x00003E14       B copy_user_loop
copy_user_done:
0x00003E1C       MOV R1 R11
0x00003E20       POP R11
0x00003E24       POP R10
0x00003E28       POP R9
0x00003E2C       POP R8
0x00003E30       POP LR
0x00003E34       RET
copy_user_fail:
0x00003E38       LI  R1 0
0x00003E40       POP R11
0x00003E44       POP R10
0x00003E48       POP R9
0x00003E4C       POP R8
0x00003E50       POP LR
0x00003E54       RET

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
0x00003E58       PUSH LR
0x00003E5C       MOV R8 R1                  ; save pathname ptr

0x00003E60       LI R7 device_table
0x00003E68       LI R9 DEVICE_COUNT

devfs_loop:
0x00003E70       CMP R9 0
0x00003E74       BEQ lookup_fail

    ; compare pathname with device name
0x00003E7C       MOV R1 R8
0x00003E80       LDW R2 [R7 + DEV_NAME]
0x00003E84       BL strcmp
0x00003E8C       CMP R1 1
0x00003E90       BEQ devfs_found

0x00003E98       ADD R7 R7 DEV_SIZE
0x00003E9C       SUB R9 R9 1
0x00003EA0       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x00003EA8       BL inode_alloc
0x00003EB0       CMP R1 0
0x00003EB4       BEQ devfs_fail

0x00003EBC       MOV R10 R1         ; inode
    ; 2 init inode
0x00003EC0       LDW R2 [R7 + DEV_OPS]
0x00003EC4       LDW R3 [R7 + DEV_PRIVATE]
0x00003EC8       LI  R4 INODE_CHAR       ; inode type for dev - char
0x00003ED0       LI  R5 0                ; size =0
0x00003ED8       BL inode_init

0x00003EE0       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x00003EE4       POP LR
0x00003EE8       RET

devfs_fail:
0x00003EEC       LI R1 0
0x00003EF4       POP LR
0x00003EF8       RET

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

0x00003EFC       PUSH LR

0x00003F00       MOV R8 R1                  ; save pathname ptr

0x00003F04       LI R7 device_table
0x00003F0C       LI R9 DEVICE_COUNT

lookup_loop:
0x00003F14       CMP R9 0
0x00003F18       BEQ lookup_fail

    ; compare pathname with device name

0x00003F20       MOV R1 R8
0x00003F24       LDW R2 [R7 + DEV_NAME]

0x00003F28       BL strcmp

0x00003F30       CMP R1 1
0x00003F34       BEQ lookup_found

0x00003F3C       ADD R7 R7 DEV_SIZE
0x00003F40       SUB R9 R9 1
0x00003F44       B lookup_loop

lookup_found:

0x00003F4C       MOV R1 R7                  ; return device descriptor ptr

0x00003F50       POP LR
0x00003F54       RET

lookup_fail:

0x00003F58       LI R1 0

0x00003F60       POP LR
0x00003F64       RET

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
0x00003F68       LDB R3 [R1]
0x00003F6C       LDB R4 [R2]

0x00003F70       CMP R3 R4
0x00003F74       BNE str_not_equal

0x00003F7C       CMP R3 0
0x00003F80       BEQ str_equal

0x00003F88       ADD R1 R1 1
0x00003F8C       ADD R2 R2 1
0x00003F90       B str_loop

str_equal:
0x00003F98       LI R1 1
0x00003FA0       RET

str_not_equal:
0x00003FA4       LI R1 0
0x00003FAC       RET

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
0x00003FB0       PUSH R3
0x00003FB4       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x00003FB8       LDB R3 [R2]            ; prefix char
0x00003FBC       CMP R3 0
0x00003FC0       BEQ sp_match           ; reached end of prefix?

0x00003FC8       LDB R4 [R1]            ; string char
0x00003FCC       CMP R4 R3
0x00003FD0       BNE sp_nomatch

0x00003FD8       ADD R1 R1 1
0x00003FDC       ADD R2 R2 1
0x00003FE0       B sp_loop
sp_match:
0x00003FE8       LI R1 1                 ;prefix ok
0x00003FF0       POP R4
0x00003FF4       POP R3
0x00003FF8       RET
sp_nomatch:
0x00003FFC       LI R1 0                 ; not ok
0x00004004       POP R4
0x00004008       POP R3
0x0000400C       RET

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
0x00004010       PUSH R3
0x00004014       PUSH R4
sk_loop:
0x00004018       LDB R3 [R2]            ; prefix char
0x0000401C       CMP R3 0
0x00004020       BEQ sk_match           ; reached end of prefix
0x00004028       LDB R4 [R1]            ; string char
0x0000402C       CMP R4 R3
0x00004030       BNE sk_nomatch
0x00004038       ADD R1 R1 1
0x0000403C       ADD R2 R2 1
0x00004040       B sk_loop

sk_match:
    ; R1 already points past prefix
0x00004048       POP R4
0x0000404C       POP R3
0x00004050       RET

sk_nomatch:
0x00004054       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x0000405C       POP R4
0x00004060       POP R3
0x00004064       RET

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
0x00004068       PUSH R2
0x0000406C       PUSH R3
0x00004070       LI R2 0                ; length
pcl_loop:
0x00004078       LDB R3 [R1]
0x0000407C       CMP R3 0
0x00004080       BEQ pcl_done
0x00004088       LI R4 47               ; '/'
0x00004090       CMP R3 R4
0x00004094       BEQ pcl_done
0x0000409C       ADD R2 R2 1
0x000040A0       ADD R1 R1 1
0x000040A4       B pcl_loop
pcl_done:
0x000040AC       MOV R1 R2
0x000040B0       POP R3
0x000040B4       POP R2
0x000040B8       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x000040BC       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x000040C0       LI R4 0
0x000040C8       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x000040CC       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x000040D0       LI R4 1
0x000040D8       STW R4 [R1 + FILE_REFCNT]
0x000040DC       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x000040E0       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x000040E4   LI R1 CURRENT_TASK
0x000040EC   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000040F0   LI R1 TASK_SIZE
0x000040F8   MUL R3 R4 R1
0x000040FC   LI R4 tasks
0x00004104   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00004108   LDW R4 [R4 + TASK_FD_TABLE]

0x0000410C       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00004114       CMP R5 MAX_FDS
0x00004118       BGE fd_alloc_fail

0x00004120       SHL R6 R5 2                ; fd * 4
0x00004124       ADD R7 R4 R6               ; &fd_table[fd]

0x00004128       LDW R2 [R7]
0x0000412C       CMP R2 0                   ; 0 - empty
0x00004130       BEQ fd_alloc_found

0x00004138       ADD R5 R5 1
0x0000413C       B fd_alloc_loop

fd_alloc_found:

0x00004144       STW R8 [R7]                ; fd_table[fd] = file*

0x00004148       MOV R1 R5                  ; return fd
0x0000414C       RET

fd_alloc_fail:

0x00004150       LI R1 ERR_MFILE
0x00004158       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x0000415C       LDW R1 [SP + TF_R1]

0x00004160       BL vfs_close

0x00004168       LI R1 0
0x00004170       STW R1 [SP + TF_R1]

0x00004174       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x0000417C       LDW R7 [SP + TF_R1]

0x00004180       BL pipe_alloc       ;create new pipe object in pipe_pool
0x00004188       CMP R1 0
0x0000418C       BEQ pipe_fail_nospc

0x00004194       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x00004198       BL file_alloc        ; R1 - created read file ptr for read end
0x000041A0       CMP R1 0
0x000041A4       BEQ pipe_fail_read_fd

0x000041AC       MOV R9 R1           ; new file for read end  in file_pool
0x000041B0       BL inode_alloc      ; get inode for this end file
0x000041B8       CMP R1 0
0x000041BC       BEQ pipe_fail_ia_read_fd
0x000041C4       MOV R10 R1

0x000041C8       LI  R2 pipe_ops         ; pipe_ops table
0x000041D0       MOV R3 R8               ; store our slot pipe*
0x000041D4       LI  R4 INODE_PIPE       ; inode type PIPE
0x000041DC       LI  R5 0                ; size =0
0x000041E4       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x000041EC       MOV R1 R9                ; R1 file*
0x000041F0       MOV R2 R10               ; inode*
0x000041F4       LI R3  FD_FLAG_READ      ; flags READ end
0x000041FC       BL file_init

0x00004204       MOV R1 R9
0x00004208       BL fd_alloc                 ; insert read file to fd_table of user process

0x00004210       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00004218       CMP R1 R2
0x0000421C       BEQ pipe_fail_read_file

0x00004224       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x00004228       BL file_alloc
0x00004230       CMP R1 0
0x00004234       BEQ pipe_fail_ia_write_fd
0x0000423C       MOV R9 R1

0x00004240       BL inode_alloc      ; get inode for this end file
0x00004248       CMP R1 0
0x0000424C       BEQ pipe_fail_ia_write_fd
0x00004254       MOV R10 R1

0x00004258       LI  R2 pipe_ops         ; pipe_ops table
0x00004260       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x00004264       LI  R4 INODE_PIPE       ; inode type PIPE
0x0000426C       LI  R5 0                ; size =0
0x00004274       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x0000427C       MOV R1 R9                ; R1 file*
0x00004280       MOV R2 R10               ; inode*
0x00004284       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x0000428C       BL file_init

0x00004294       MOV R1 R9
0x00004298       BL  fd_alloc

0x000042A0       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x000042A8       CMP R1 R2
0x000042AC       BEQ pipe_fail_write_file

0x000042B4       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x000042B8       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x000042BC       LI  R2 8     ; len 2 words (8 bytes)
0x000042C4       LI  R3 1     ; mem perm to write cond
0x000042CC       BL  user_buffer_valid_range
0x000042D4       CMP R1 1
0x000042D8       BNE pipe_fail_both_fds

0x000042E0       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x000042E4       STW R11 [R7 + 4]

0x000042E8       LI R1 0
0x000042F0       STW R1 [SP + TF_R1]

0x000042F4       B trap_restore

pipe_fail:
0x000042FC       LI R1 ERR_IO
0x00004304       STW R1 [SP + TF_R1]

0x00004308       B trap_restore

pipe_fail_both_fds:
0x00004310       MOV R12 R8
0x00004314       MOV R1 R11
0x00004318       BL fd_remove
0x00004320       CMP R1 0
0x00004324       BEQ pipe_fail_both_fds_read
0x0000432C       BL file_free

pipe_fail_both_fds_read:
0x00004334       MOV R1 R10
0x00004338       BL fd_remove
0x00004340       CMP R1 0
0x00004344       BEQ pipe_fail_free_pipe_fault
0x0000434C       BL file_free

pipe_fail_free_pipe_fault:
0x00004354       MOV R1 R12
0x00004358       BL pipe_free
0x00004360       LI R1 ERR_FAULT
0x00004368       STW R1 [SP + TF_R1]

0x0000436C       B trap_restore

pipe_fail_write_file:
0x00004374       MOV R12 R8
0x00004378       MOV R1 R9
0x0000437C       BL file_free
0x00004384       MOV R1 R10
0x00004388       BL fd_remove
0x00004390       CMP R1 0
0x00004394       BEQ pipe_fail_free_pipe_mfile
0x0000439C       BL file_free

pipe_fail_free_pipe_mfile:
0x000043A4       MOV R1 R12
0x000043A8       BL pipe_free
0x000043B0       LI R1 ERR_MFILE
0x000043B8       STW R1 [SP + TF_R1]

0x000043BC       B trap_restore

pipe_fail_read_fd:
0x000043C4       MOV R12 R8
0x000043C8       MOV R1 R10
0x000043CC       BL fd_remove
0x000043D4       CMP R1 0
0x000043D8       BEQ pipe_fail_free_pipe_nfile
0x000043E0       BL file_free

pipe_fail_free_pipe_nfile:
0x000043E8       MOV R1 R12
0x000043EC       BL pipe_free
0x000043F4       LI R1 ERR_NFILE
0x000043FC       STW R1 [SP + TF_R1]

0x00004400       B trap_restore

pipe_fail_read_file:
0x00004408       MOV R12 R8
0x0000440C       MOV R1 R9
0x00004410       BL file_free
0x00004418       MOV R1 R10          ; освободить inode read end
0x0000441C       BL inode_free
0x00004424       MOV R1 R12
0x00004428       BL pipe_free
0x00004430       LI R1 ERR_MFILE
0x00004438       STW R1 [SP + TF_R1]

0x0000443C       B trap_restore

pipe_fail_pipe_only:
0x00004444       MOV R1 R8
0x00004448       BL pipe_free
0x00004450       LI R1 ERR_NFILE
0x00004458       STW R1 [SP + TF_R1]

0x0000445C       B trap_restore

pipe_fail_nospc:
0x00004464       LI R1 ERR_NOSPC
0x0000446C       STW R1 [SP + TF_R1]

0x00004470       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x00004478       MOV R1 R9          ; освобождаем file (read end)
0x0000447C       BL  file_free
0x00004484       MOV R1 R8          ; освобождаем pipe
0x00004488       BL  pipe_free
0x00004490       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x00004498       STW R1 [SP + TF_R1]
0x0000449C       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x000044A4       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x000044A8       BL fd_remove
0x000044B0       CMP R1 0
0x000044B4       BEQ skip_file_free_read
0x000044BC       BL file_free
skip_file_free_read:
0x000044C4       MOV R1 R9          ; освобождаем file (write end)
0x000044C8       BL file_free
0x000044D0       MOV R1 R8          ; освобождаем pipe
0x000044D4       BL pipe_free
0x000044DC       LI R1 ERR_NFILE
0x000044E4       STW R1 [SP + TF_R1]
0x000044E8       B trap_restore

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

0x000044F0       LDW R1 [SP + TF_R1]     ; argument fd

0x000044F4       BL fd_lookup            ; lookup FILE*
0x000044FC       CMP R1 0
0x00004500       BEQ dup_badfd
0x00004508       MOV R8 R1               ; keep FILE*

0x0000450C       BL file_get             ; FILE.ref++

0x00004514       MOV R1 R8
0x00004518       BL fd_alloc             ; try to allocate new fd

0x00004520       LI R2 ERR_MFILE
0x00004528       CMP R1 R2
0x0000452C       BEQ dup_fail_fd

0x00004534       STW R1 [SP + TF_R1] ;R1 - new fd
0x00004538       B trap_restore

dup_fail_fd:

0x00004540       MOV R1 R8
0x00004544       BL file_put

0x0000454C       LI R1 ERR_MFILE     ;R1 -err + rollback
0x00004554       STW R1 [SP + TF_R1]
0x00004558       B trap_restore

dup_badfd:

0x00004560       LI R1 ERR_BADF      ;R1 -err + file not found
0x00004568       STW R1 [SP + TF_R1]

0x0000456C       B trap_restore

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

0x00004574       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x00004578       MOV R1 R8
0x0000457C       LI  R2 TIMEVAL_SIZE
0x00004584       LI  R3 1                   ; write access
0x0000458C       BL  user_buffer_valid_range

0x00004594       CMP R1 1
0x00004598       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x000045A0       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x000045A8   LI R1 CURRENT_TASK
0x000045B0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000045B4   LI R1 TASK_SIZE
0x000045BC   MUL R3 R4 R1
0x000045C0   LI R5 tasks
0x000045C8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x000045CC   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x000045D0       STW R1 [R6 + TIMEVAL_SEC]
0x000045D4       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x000045D8       MOV R1 R8                  ; user destination
0x000045DC       LI  R2 TIMEVAL_SIZE        ; size in bytes (8)
0x000045E4       MOV R4 R6                  ; kernel source

0x000045E8       BL copy_to_user

0x000045F0       CMP R1 TIMEVAL_SIZE
0x000045F4       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x000045FC       LI R1 0
0x00004604       STW R1 [SP + TF_R1]

0x00004608       B trap_restore

gettime_badptr:

0x00004610       LI R1 ERR_FAULT
0x00004618       STW R1 [SP + TF_R1]

0x0000461C       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x00004624       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x00004628       LI R2 HEAP_START
0x00004630       CMP R8 R2
0x00004634       BLT brk_invalid            ; if new break is below data page, return error

0x0000463C       LI R2 HEAP_END
0x00004644       CMP R8 R2
0x00004648       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00004650   LI R1 CURRENT_TASK
0x00004658   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000465C   LI R1 TASK_SIZE
0x00004664   MUL R3 R4 R1
0x00004668   LI R5 tasks
0x00004670   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x00004674   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x00004678       STW R8 [SP + TF_R1]

0x0000467C       B trap_restore

brk_invalid:
    ; Return -1
0x00004684       LI R1 ERR_FAULT
0x0000468C       STW R1 [SP + TF_R1]

0x00004690       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x00004698       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x0000469C   LI R1 CURRENT_TASK
0x000046A4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000046A8   LI R1 TASK_SIZE
0x000046B0   MUL R3 R4 R1
0x000046B4   LI R5 tasks
0x000046BC   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x000046C0   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x000046C4       ADD R10 R9 R8

    ; Validate it's within the data page
0x000046C8       LI R2 HEAP_START
0x000046D0       CMP R10 R2
0x000046D4       BLT sbrk_invalid

0x000046DC       LI R2 HEAP_END
0x000046E4       CMP R10 R2
0x000046E8       BGT sbrk_invalid

    ; Return old break
0x000046F0       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x000046F4   STW R10 [R5 + TASK_BREAK]

0x000046F8       B trap_restore

sbrk_invalid:
    ; Return -1
0x00004700       LI R1 ERR_FAULT
0x00004708       STW R1 [SP + TF_R1]
0x0000470C       B trap_restore

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

0x00004714       LI  R3 timer_ticks
0x0000471C       LDW R4 [R3]                ; tick counter (1 ms per tick)

    ; seconds = ticks / 1000
0x00004720       MOV R1 R4
0x00004724       LI  R5 1000
0x0000472C       DIV R1 R1 R5

    ; usec = (ticks % 1000) * 1000
0x00004730       MOD R4 R4 R5
0x00004734       LI  R5 1000
0x0000473C       MUL R2 R4 R5

0x00004740       RET

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

0x00004744       PUSH LR

0x00004748       MOV R9 R1              ; file*
0x0000474C       MOV R7 R2              ; user buffer
0x00004750       MOV R6 R3              ; requested len

0x00004754       LDW R9 [R9 + FILE_INODE]
0x00004758       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x0000475C       CMP R6 0                ;fast clear from it if len=0
0x00004760       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00004768       PUSH R7
0x0000476C       PUSH R6

0x00004770       MOV R1 R7
0x00004774       MOV R2 R6
0x00004778       LI  R3 1               ; write access
0x00004780       BL user_buffer_valid_range

0x00004788       POP R6
0x0000478C       POP R7
0x00004790       CMP R1 1
0x00004794       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x0000479C       LDW R4 [R9 + PIPE_COUNT]
0x000047A0       CMP R4 0
0x000047A4       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x000047AC       CMP R6 R4
0x000047B0       BLT pipe_user_len

0x000047B8       MOV R5 R4
0x000047BC       B pipe_have_amount

pipe_user_len:
0x000047C4       MOV R5 R6

pipe_have_amount:
0x000047C8       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x000047D0       CMP R10 R5
0x000047D4       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x000047DC       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x000047E0       MOV R12 R9
0x000047E4       ADD R12 R12 PIPE_BUFFER
0x000047E8       ADD R12 R12 R11         ; addr += tail

0x000047EC       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x000047F0       MOV R12 R7
0x000047F4       ADD R12 R12 R10

0x000047F8       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x000047FC       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00004800       LI R2 255
0x00004808       AND R11 R11 R2
0x0000480C       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00004810       LDW R12 [R9 + PIPE_COUNT]
0x00004814       SUB R12 R12 1
0x00004818       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x0000481C       ADD R10 R10 1
0x00004820       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00004828       MOV R1 R9
0x0000482C       ADD R1 R1 PIPE_WWAIT
0x00004830       BL waitq_wake_all
0x00004838       MOV R1 R10          ; read bytes amount
0x0000483C       POP LR
0x00004840       RET

pipe_read_badptr:
0x00004844       LI R1 ERR_FAULT
0x0000484C       POP LR
0x00004850       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00004854       MOV R1 R9
0x00004858       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x0000485C       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00004864       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x0000486C       LDW R4 [R9 + PIPE_COUNT]
0x00004870       CMP R4 0
0x00004874       BNE pipe_read_retry

0x0000487C       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00004884       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x0000488C       LI R2 0

pipe_loop:
0x00004894       LI  R1 MAX_PIPES
0x0000489C       CMP R2 R1
0x000048A0       BGE pipe_alloc_fail

0x000048A8       SHL R3 R2 2

0x000048AC       LI R4 pipe_used
0x000048B4       ADD R4 R4 R3

0x000048B8       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x000048BC       CMP R5 0                ; 0 -empty
0x000048C0       BEQ pipe_found

0x000048C8       ADD R2 R2 1
0x000048CC       B pipe_loop

pipe_found:

0x000048D4       LI R5 1
0x000048DC       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x000048E0       LI R4 PIPE_SIZE
0x000048E8       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x000048EC       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x000048F4       ADD R1 R1 R6

0x000048F8       LI R7 0                 ; clean it up
0x00004900       STW R7 [R1 + PIPE_HEAD]
0x00004904       STW R7 [R1 + PIPE_TAIL]
0x00004908       STW R7 [R1 + PIPE_COUNT]
0x0000490C       STW R7 [R1 + PIPE_RWAIT]
0x00004910       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00004914       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00004918       LI R1 0
0x00004920       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00004924       LI R2 pipe_pool
0x0000492C       SUB R3 R1 R2

0x00004930       LI R4 PIPE_SIZE
0x00004938       DIV R5 R3 R4

0x0000493C       SHL R5 R5 2
0x00004940       LI R6 pipe_used
0x00004948       ADD R6 R6 R5

0x0000494C       LI R7 0
0x00004954       STW R7 [R6]

0x00004958       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x0000495C       PUSH LR

0x00004960       MOV R9 R1
0x00004964       MOV R7 R2
0x00004968       MOV R6 R3

0x0000496C       LDW R9 [R9 + FILE_INODE]
0x00004970       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00004974       PUSH R7
0x00004978       PUSH R6

0x0000497C       MOV R1 R7
0x00004980       MOV R2 R6
0x00004984       LI  R3 0           ; READ access
0x0000498C       BL user_buffer_valid_range

0x00004994       POP R6
0x00004998       POP R7

0x0000499C       CMP R1 1
0x000049A0       BNE pipe_write_badptr

0x000049A8       LI R10 0               ; bytes written
pipe_write_retry:
0x000049B0       CMP R10 R6
0x000049B4       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x000049BC       LDW R11 [R9 + PIPE_COUNT]
0x000049C0       LI R2 256
0x000049C8       CMP R11 R2
0x000049CC       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x000049D4       LDW R12 [R9 + PIPE_HEAD]

0x000049D8       MOV R4 R7
0x000049DC       ADD R4 R4 R10
0x000049E0       LDB R5 [R4]     ; read byte from user buff addr

0x000049E4       MOV R4 R9
0x000049E8       ADD R4 R4 PIPE_BUFFER
0x000049EC       ADD R4 R4 R12
0x000049F0       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x000049F4       ADD R12 R12 1
0x000049F8       LI R2 255
0x00004A00       AND R12 R12 R2
0x00004A04       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00004A08       LDW R4 [R9 + PIPE_COUNT]
0x00004A0C       ADD R4 R4 1
0x00004A10       STW R4 [R9 + PIPE_COUNT]

; written++
0x00004A14       ADD R10 R10 1
0x00004A18       B pipe_write_retry

pipe_write_done:
; wake readers
0x00004A20       MOV R1 R9
0x00004A24       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x00004A28       BL waitq_wake_all
0x00004A30       MOV R1 R10      ;written bytes
0x00004A34       POP LR
0x00004A38       RET

pipe_write_badptr:
0x00004A3C       LI R1 ERR_FAULT
0x00004A44       POP LR
0x00004A48       RET

pipe_write_empty:
0x00004A4C       LI R1 0
0x00004A54       POP LR
0x00004A58       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00004A5C       MOV R1 R9
0x00004A60       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x00004A64       LI R2 WAIT_PIPE_WRITE
0x00004A6C       BL waitq_prepare_sleep
    ; race check
0x00004A74       LDW R4 [R9 + PIPE_COUNT]
0x00004A78       LI R2 256
0x00004A80       CMP R4 R2
0x00004A84       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00004A8C       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00004A94       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x00004A9C       CMP R1 3
0x00004AA0       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x00004AA8       CMP R1 MAX_FDS
0x00004AAC       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x00004AB4       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x00004AB8   LI R1 CURRENT_TASK
0x00004AC0   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00004AC4   LI R1 TASK_SIZE
0x00004ACC   MUL R3 R4 R1
0x00004AD0   LI R4 tasks
0x00004AD8   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x00004ADC   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x00004AE0       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x00004AE4       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x00004AE8       LDW R1 [R6]                 ; R1 = file* из таблицы
0x00004AEC       CMP R1 0
0x00004AF0       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x00004AF8       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x00004AFC       RET

fd_lookup_invalid:
0x00004B00       LI R1 0
0x00004B08       LI R2 0
0x00004B10       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x00004B14       PUSH LR
0x00004B18       BL  fd_lookup
0x00004B20       CMP R1 0
0x00004B24       BEQ fd_remove_invalid

0x00004B2C       MOV R8 R1          ; сохраняем file*
0x00004B30       LI R3 0
0x00004B38       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x00004B3C       MOV R1 R8          ; file*
0x00004B40       POP LR
0x00004B44       RET

fd_remove_invalid:
0x00004B48       LI R1 0
0x00004B50       POP LR
0x00004B54       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00004B58       LDW R1 [SP + TF_R1]
0x00004B5C       LDW R2 [SP + TF_R2]
0x00004B60       LDW R3 [SP + TF_R3]

0x00004B64       BL vfs_read

0x00004B6C       STW R1 [SP + TF_R1]
0x00004B70       B trap_restore

; to comply with vfs interface
devfs_open:
0x00004B78       LI R1 0
0x00004B80       RET
devfs_close:
0x00004B84       LI R1 0
0x00004B8C       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00004B90       PUSH LR
0x00004B94       PUSH R8
0x00004B98       PUSH R9
0x00004B9C       PUSH R10
0x00004BA0       PUSH R11
0x00004BA4       PUSH R12
0x00004BA8       MOV R9 R1
0x00004BAC       MOV R7 R2
0x00004BB0       MOV R6 R3
0x00004BB4       LI R8 0                    ; total bytes collected
0x00004BBC       LDW R9 [R9 + FILE_INODE]
0x00004BC0       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00004BC4       CMP R6 0
0x00004BC8       BEQ read_done

0x00004BD0       PUSH R7
0x00004BD4       PUSH R6
0x00004BD8       PUSH R9
0x00004BDC       MOV R1 R7
0x00004BE0       MOV R2 R6
0x00004BE4       LI R3 1                ; write access for destination buffer
0x00004BEC       BL user_buffer_valid_range
0x00004BF4       POP R9
0x00004BF8       POP R6
0x00004BFC       POP R7
0x00004C00       CMP R1 1
0x00004C04       BNE con_read_fault

read_wait_uart_rx:
0x00004C0C       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00004C10       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00004C14       AND R5 R5 1                 ; bit 0 = RX_READY
0x00004C18       CMP R5 0
0x00004C1C       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00004C24   LI R1 CURRENT_TASK
0x00004C2C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004C30   LI R1 TASK_SIZE
0x00004C38   MUL R3 R4 R1
0x00004C3C   LI R5 tasks
0x00004C44   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00004C48   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00004C4C       MOV R2 R6
0x00004C50       MOV R3 R9
0x00004C54       PUSH R6
0x00004C58       PUSH R7
0x00004C5C       PUSH R8
0x00004C60       PUSH R9
0x00004C64       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x00004C6C       POP R9
0x00004C70       POP R8
0x00004C74       POP R7
0x00004C78       POP R6

0x00004C7C       CMP R1 0
0x00004C80       BEQ read_wait_uart_rx

0x00004C88       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x00004C8C   LI R1 CURRENT_TASK
0x00004C94   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x00004C98   LI R1 TASK_SIZE
0x00004CA0   MUL R3 R5 R1
0x00004CA4   LI R4 tasks
0x00004CAC   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x00004CB0   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with newline before copy_to_user
    ; clobbers temporary registers.
0x00004CB4       LI R11 0
0x00004CBC       SUB R5 R10 1
0x00004CC0       ADD R5 R4 R5
0x00004CC4       LDB R5 [R5]
0x00004CC8       CMP R5 10
0x00004CCC       BNE read_chunk_not_newline
0x00004CD4       LI R11 1

read_chunk_not_newline:
0x00004CDC       PUSH R6
0x00004CE0       PUSH R7
0x00004CE4       PUSH R8
0x00004CE8       PUSH R9
0x00004CEC       PUSH R10
0x00004CF0       PUSH R11
0x00004CF4       MOV R1 R7              ; user destination
0x00004CF8       MOV R2 R10
0x00004CFC       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00004D04       POP R11
0x00004D08       POP R10
0x00004D0C       POP R9
0x00004D10       POP R8
0x00004D14       POP R7
0x00004D18       POP R6

0x00004D1C       ADD R7 R7 R10
0x00004D20       ADD R8 R8 R10
0x00004D24       SUB R6 R6 R10

0x00004D28       CMP R11 1
0x00004D2C       BEQ read_complete
0x00004D34       CMP R6 0
0x00004D38       BGT read_wait_uart_rx

read_complete:
0x00004D40       MOV R1 R8
0x00004D44       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00004D4C       LI R1 uart_rx_waitq
0x00004D54       LI R2 WAIT_UART_RX
0x00004D5C       BL waitq_prepare_sleep

0x00004D64       LDW R4 [R9 + UARTDEV_MMIO]
0x00004D68       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x00004D6C       AND R10 R10 1
0x00004D70       CMP R10 0
0x00004D74       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x00004D7C       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x00004D84       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00004D8C       LI R1 uart_rx_waitq
0x00004D94       BL waitq_cancel_sleep_current

0x00004D9C       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x00004DA4       LI R1 0
0x00004DAC       B read_return

con_read_fault:
0x00004DB4       LI R1 ERR_FAULT

read_return:
0x00004DBC       POP R12
0x00004DC0       POP R11
0x00004DC4       POP R10
0x00004DC8       POP R9
0x00004DCC       POP R8
0x00004DD0       POP LR
0x00004DD4       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00004DD8       LDW R1 [SP + TF_R1]
0x00004DDC       LDW R2 [SP + TF_R2]
0x00004DE0       LDW R3 [SP + TF_R3]

0x00004DE4       BL vfs_write

0x00004DEC       STW R1 [SP + TF_R1]
0x00004DF0       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00004DF8       PUSH LR
0x00004DFC       MOV R9 R1
0x00004E00       MOV R7 R2
0x00004E04       MOV R6 R3
0x00004E08       LDW R9 [R9 + FILE_INODE]
0x00004E0C       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00004E10       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00004E18       CMP R6 0
0x00004E1C       BEQ write_done             ;0 bytes

0x00004E24       LI R2 KBUFFER_SIZE
0x00004E2C       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00004E30       BLT write_chunk_small
0x00004E38       LI R2 KBUFFER_SIZE

0x00004E40       B write_chunk

write_chunk_small:
0x00004E48       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x00004E4C       PUSH R7
0x00004E50       PUSH R6
0x00004E54       PUSH R9
0x00004E58       PUSH R8
0x00004E5C       MOV R1 R7
0x00004E60       MOV R2 R2
0x00004E64       LI R3 0                ; read access for source buffer
0x00004E6C       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00004E74       POP R8
0x00004E78       POP R9
0x00004E7C       POP R6
0x00004E80       POP R7
0x00004E84       CMP R1 1
0x00004E88       BNE driver_bad_pointer

0x00004E90       PUSH R7
0x00004E94       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x00004E98   LI R1 CURRENT_TASK
0x00004EA0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004EA4   LI R1 TASK_SIZE
0x00004EAC   MUL R3 R4 R1
0x00004EB0   LI R5 tasks
0x00004EB8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00004EBC   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00004EC0       MOV R1 R7
0x00004EC4       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00004ECC       MOV R10 R1             ; bytes copied
0x00004ED0       POP R6
0x00004ED4       POP R7

0x00004ED8       PUSH R7
0x00004EDC       PUSH R9
0x00004EE0       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x00004EE4       LDW R1 [R9 + UARTDEV_MMIO]
0x00004EE8       LDW R2 [R1 + 4]
0x00004EEC       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00004EF0       CMP R2 0
0x00004EF4       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00004EFC   LI R1 CURRENT_TASK
0x00004F04   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004F08   LI R1 TASK_SIZE
0x00004F10   MUL R3 R4 R1
0x00004F14   LI R5 tasks
0x00004F1C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00004F20   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x00004F24       MOV R2 R10
0x00004F28       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x00004F2C       BL device_write
0x00004F34       POP R6
0x00004F38       POP R9
0x00004F3C       POP R7

0x00004F40       CMP R1 0        ;nothing is written - go again
0x00004F44       BEQ write_loop

0x00004F4C       ADD R8 R8 R1     ;update ptrs
0x00004F50       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x00004F54       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x00004F58       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00004F60       LI R1 uart_tx_waitq
0x00004F68       LI R2 WAIT_UART_TX
0x00004F70       BL waitq_prepare_sleep

0x00004F78       LDW R1 [R9 + UARTDEV_MMIO]
0x00004F7C       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00004F80       AND R2 R2 2
0x00004F84       CMP R2 0
0x00004F88       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00004F90       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x00004F98       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00004FA0       LI R1 uart_tx_waitq
0x00004FA8       BL waitq_cancel_sleep_current

0x00004FB0       B write_wait_uart_tx

write_done:
0x00004FB8       MOV R1 R8
0x00004FBC       POP LR
0x00004FC0       RET

driver_bad_pointer:
0x00004FC4       LI R1 ERR_FAULT
0x00004FCC       POP LR
0x00004FD0       RET

bad_fd:
0x00004FD4       LI R1 ERR_BADF
0x00004FDC       STW R1 [SP + TF_R1]

0x00004FE0       B trap_restore

bad_pointer:
0x00004FE8       LI R1 ERR_FAULT
0x00004FF0       STW R1 [SP + TF_R1]

0x00004FF4       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x00004FFC       LDW R4 [R1 + FILE_INODE]
0x00005000       LDW R4 [R4 + INODE_OPS]
0x00005004       LDW R4 [R4 + FSOPS_READ]
0x00005008       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x0000500C       LDW R4 [R1 + FILE_INODE]
0x00005010       LDW R4 [R4 + INODE_OPS]
0x00005014       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x00005018       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x0000501C       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00005024       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when a newline '\n' (ASCII 10) is received.
0x0000502C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00005030       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00005038       CMP R5 R2                   ; have we read enough bytes?
0x0000503C       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x00005044       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00005048       AND R6 R6 1                 ; bit 0 = RX_READY
0x0000504C       CMP R6 0
0x00005050       BEQ dr_done                 ; no more buffered input available

0x00005058       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x0000505C       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00005060       ADD R5 R5 1

    ; If we received a newline, stop reading early
0x00005064       CMP R7 10
0x00005068       BEQ dr_done

0x00005070       B dr_loop

dr_done:
0x00005078       MOV R1 R5                   ; return number of bytes actually read
0x0000507C       RET

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
0x00005080       PUSH LR

    ; mutex for write to console lock
0x00005084       PUSH R1
0x00005088       PUSH R2
0x0000508C       PUSH R3

    ; Lock console mutex
0x00005090       BL console_lock

    ; Write to UART
0x00005098       POP R3
0x0000509C       POP R2
0x000050A0       POP R1


0x000050A4       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000050A8       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000050B0       CMP R5 R2                   ; have we written all bytes?
0x000050B4       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x000050BC       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000050C0       AND R6 R6 2                 ; bit 1 = TX_READY
0x000050C4       CMP R6 0
0x000050C8       BEQ dcw_done

0x000050D0       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x000050D4       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x000050D8       ADD R5 R5 1
0x000050DC       B dcw_loop

dcw_done:
0x000050E4       MOV R1 R5                   ; return number of bytes written


 ; Unlock console mutex for exclusive write to uart device
0x000050E8       PUSH R1
0x000050EC       BL console_unlock
0x000050F4       POP R1


0x000050F8       POP LR
0x000050FC       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00005100       LI R1 0
0x00005108       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x0000510C       PUSH LR
0x00005110       MOV R6 R3
0x00005114       CMP R6 0
0x00005118       BEQ null_write_done

0x00005120       PUSH R6
0x00005124       MOV R1 R2
0x00005128       MOV R2 R6
0x0000512C       LI R3 0                    ; read access from user source
0x00005134       BL user_buffer_valid_range
0x0000513C       POP R6
0x00005140       CMP R1 1
0x00005144       BNE null_write_badptr

null_write_done:
0x0000514C       MOV R1 R6
0x00005150       POP LR
0x00005154       RET

null_write_badptr:
0x00005158       LI R1 ERR_FAULT
0x00005160       POP LR
0x00005164       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================
0x00005168       PUSH R5
0x0000516C       PUSH R6
0x00005170       PUSH R8

0x00005174       CMP R1 0
0x00005178       BLT fd_invalid
0x00005180       CMP R1 MAX_FDS
0x00005184       BGE fd_invalid

0x0000518C       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x00005190   LI R1 CURRENT_TASK
0x00005198   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x0000519C   LI R1 TASK_SIZE
0x000051A4   MUL R3 R4 R1
0x000051A8   LI R4 tasks
0x000051B0   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000051B4   LDW R4 [R4 + TASK_FD_TABLE]

0x000051B8       SHL R5 R8 2
0x000051BC       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x000051C0       LDW R1 [R4]                 ; R1 = file ptr
0x000051C4       LDW R6 [R1 + FILE_FLAGS]
0x000051C8       AND R6 R6 R2
0x000051CC       CMP R6 R2
0x000051D0       BNE fd_invalid

0x000051D8       POP R8
0x000051DC       POP R6
0x000051E0       POP R5
0x000051E4       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x000051E8       POP R8
0x000051EC       POP R6
0x000051F0       POP R5

0x000051F4       LI R1 0
0x000051FC       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x00005200       PUSH LR
0x00005204       MOV R7 R2
0x00005208       MOV R10 R3

0x0000520C       LI R2 FD_FLAG_READ
0x00005214       BL fetch_fd_entry   ; macro inside destroys R6

0x0000521C       CMP R1 0
0x00005220       BEQ vfs_read_badfd

0x00005228       MOV R9 R1
0x0000522C       MOV R1 R9
0x00005230       MOV R2 R7
0x00005234       MOV R3 R10
0x00005238       BL file_read
0x00005240       POP LR
0x00005244       RET

vfs_read_badfd:
0x00005248       LI R1 ERR_BADF
0x00005250       POP LR
0x00005254       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x00005258       PUSH LR
0x0000525C       MOV R7 R2
0x00005260       MOV R10 R3

0x00005264       LI R2 FD_FLAG_WRITE
0x0000526C       BL fetch_fd_entry   ;macro inside desroys R6 (fixed)

0x00005274       CMP R1 0
0x00005278       BEQ vfs_write_badfd

0x00005280       MOV R9 R1
0x00005284       MOV R1 R9           ; R1 - file* acc to fd
0x00005288       MOV R2 R7
0x0000528C       MOV R3 R10
0x00005290       BL file_write
0x00005298       POP LR
0x0000529C       RET

vfs_write_badfd:
0x000052A0       LI R1 ERR_BADF
0x000052A8       POP LR
0x000052AC       RET






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
0x000052B0       PUSH R5
0x000052B4       PUSH R6
0x000052B8       PUSH R7
0x000052BC       PUSH R8
0x000052C0       PUSH R9
0x000052C4       PUSH R10
0x000052C8       PUSH R11
0x000052CC       PUSH R12

0x000052D0       LI R4 0
0x000052D8       CMP R2 R4
0x000052DC       BEQ uv_valid

0x000052E4       LI R4 USER_BASE
0x000052EC       CMP R1 R4
0x000052F0       BLT uv_invalid

0x000052F8       LI R4 USER_LIMIT
0x00005300       ADD R5 R1 R2
0x00005304       SUB R5 R5 1
0x00005308       CMP R5 R1
0x0000530C       BLT uv_invalid
0x00005314       CMP R5 R4
0x00005318       BGT uv_invalid
0x00005320       MOV R11 R1              ; save start address; task macros clobber R1
0x00005324       MOV R12 R5              ; save end address for page calculation
0x00005328       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x0000532C   LI R1 CURRENT_TASK
0x00005334   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00005338   LI R1 TASK_SIZE
0x00005340   MUL R3 R6 R1
0x00005344   LI R6 tasks
0x0000534C   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00005350   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x00005354       CMP R6 0
0x00005358       BEQ uv_invalid

uv_check_pages:
0x00005360       SHR R7 R11 12
0x00005364       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00005368       CMP R7 R8
0x0000536C       BGT uv_valid
0x00005374       SHL R9 R7 2
0x00005378       ADD R9 R9 R6
0x0000537C       LDW R10 [R9]
0x00005380       AND R5 R10 PTE_P
0x00005384       CMP R5 0
0x00005388       BEQ uv_invalid
0x00005390       AND R5 R10 PTE_U
0x00005394       CMP R5 0
0x00005398       BEQ uv_invalid
0x000053A0       CMP R4 0
0x000053A4       BEQ uv_check_read
0x000053AC       AND R5 R10 PTE_W
0x000053B0       CMP R5 0
0x000053B4       BEQ uv_invalid
0x000053BC       B uv_next

uv_check_read:
0x000053C4       AND R5 R10 PTE_R
0x000053C8       CMP R5 0
0x000053CC       BEQ uv_invalid

uv_next:
0x000053D4       ADD R7 R7 1
0x000053D8       B uv_loop

uv_valid:
0x000053E0       LI R1 1
0x000053E8       POP R12
0x000053EC       POP R11
0x000053F0       POP R10
0x000053F4       POP R9
0x000053F8       POP R8
0x000053FC       POP R7
0x00005400       POP R6
0x00005404       POP R5
0x00005408       RET

uv_invalid:
0x0000540C       LI R1 0

0x00005414       POP R12
0x00005418       POP R11
0x0000541C       POP R10
0x00005420       POP R9
0x00005424       POP R8
0x00005428       POP R7
0x0000542C       POP R6
0x00005430       POP R5
0x00005434       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00005438       PUSH R5
0x0000543C       PUSH R6
0x00005440       PUSH R7
0x00005444       LI R5 0
cfu_head:
0x0000544C       CMP R2 0
0x00005450       BEQ cfu_done
0x00005458       OR R6 R1 R4
0x0000545C       AND R6 R6 3
0x00005460       CMP R6 0
0x00005464       BEQ cfu_word
0x0000546C       LDB R7 [R1]
0x00005470       STB R7 [R4]
0x00005474       ADD R1 R1 1
0x00005478       ADD R4 R4 1
0x0000547C       ADD R5 R5 1
0x00005480       SUB R2 R2 1
0x00005484       B cfu_head
cfu_word:
0x0000548C       CMP R2 4
0x00005490       BLT cfu_tail
0x00005498       LDW R7 [R1]
0x0000549C       STW R7 [R4]
0x000054A0       ADD R1 R1 4
0x000054A4       ADD R4 R4 4
0x000054A8       ADD R5 R5 4
0x000054AC       SUB R2 R2 4
0x000054B0       B cfu_word
cfu_tail:
0x000054B8       CMP R2 0
0x000054BC       BEQ cfu_done
0x000054C4       LDB R7 [R1]
0x000054C8       STB R7 [R4]
0x000054CC       ADD R1 R1 1
0x000054D0       ADD R4 R4 1
0x000054D4       ADD R5 R5 1
0x000054D8       SUB R2 R2 1
0x000054DC       B cfu_tail
cfu_done:
0x000054E4       MOV R1 R5
0x000054E8       POP R7
0x000054EC       POP R6
0x000054F0       POP R5
0x000054F4       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x000054F8       PUSH R5
0x000054FC       PUSH R6
0x00005500       PUSH R7
0x00005504       LI R5 0
ctu_head:
0x0000550C       CMP R2 0
0x00005510       BEQ ctu_done
0x00005518       OR R6 R1 R4
0x0000551C       AND R6 R6 3
0x00005520       CMP R6 0
0x00005524       BEQ ctu_word
0x0000552C       LDB R7 [R4]
0x00005530       STB R7 [R1]
0x00005534       ADD R1 R1 1
0x00005538       ADD R4 R4 1
0x0000553C       ADD R5 R5 1
0x00005540       SUB R2 R2 1
0x00005544       B ctu_head
ctu_word:
0x0000554C       CMP R2 4
0x00005550       BLT ctu_tail
0x00005558       LDW R7 [R4]
0x0000555C       STW R7 [R1]
0x00005560       ADD R1 R1 4
0x00005564       ADD R4 R4 4
0x00005568       ADD R5 R5 4
0x0000556C       SUB R2 R2 4
0x00005570       B ctu_word
ctu_tail:
0x00005578       CMP R2 0
0x0000557C       BEQ ctu_done
0x00005584       LDB R7 [R4]
0x00005588       STB R7 [R1]
0x0000558C       ADD R1 R1 1
0x00005590       ADD R4 R4 1
0x00005594       ADD R5 R5 1
0x00005598       SUB R2 R2 1
0x0000559C       B ctu_tail
ctu_done:
0x000055A4       MOV R1 R5
0x000055A8       POP R7
0x000055AC       POP R6
0x000055B0       POP R5
0x000055B4       RET

handle_debug:
    ; Debug trap - just return
0x000055B8       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x000055C0       CSRR R1 STVAL

0x000055C4       CMP R1 0
0x000055C8       BEQ handle_timer_irq

0x000055D0       CMP R1 1
0x000055D4       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x000055DC       LI R2 0x00102000
0x000055E4       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x000055E8       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x000055F0       LI R2 0x00102000
0x000055F8       LI R3 0
0x00005600       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x00005604       LI R1 timer_ticks
0x0000560C       LDW R2 [R1]
0x00005610       ADD R2 R2 1
0x00005614       STW R2 [R1]

    ;================================================================
    ; Wake sleeping tasks whose time has expired
    ;================================================================

0x00005618       LI R1 sleep_waitq
0x00005620       LDW R8 [R1]                ; R8 = current sleep_waitq mask
0x00005624       LI R9 0                    ; R9 = tasks to wake bitmask
0x0000562C       LI R3 0                    ; task index

timer_wake_scan:
0x00005634       CMP R3 MAX_TASKS
0x00005638       BGE timer_wake_scan_done

    ; Check if this task is in the sleep wait queue
0x00005640       LI R6 1
0x00005648       SHL R6 R6 R3               ; bit for this task
0x0000564C       AND R7 R8 R6
0x00005650       CMP R7 0
0x00005654       BEQ timer_wake_next        ; not in sleep queue

    ; Task is sleeping, check if it's time to wake
; macro: GET_TASK_PTR R5, R3
0x0000565C   LI R1 TASK_SIZE
0x00005664   MUL R3 R3 R1
0x00005668   LI R5 tasks
0x00005670   ADD R5 R5 R3
; macro: TASK_GET_WAKE_TIME R7, R5
0x00005674   LDW R7 [R5 + TASK_WAKE_TIME]
0x00005678       CMP R2 R7                  ; current time >= wake time?
0x0000567C       BLT timer_wake_next

    ; Mark this task for wakeup
0x00005684       OR R9 R9 R6                 ; add to wake bitmask bitwize

timer_wake_next:
0x00005688       ADD R3 R3 1
0x0000568C       B timer_wake_scan

timer_wake_scan_done:
    ; If no tasks to wake, skip
0x00005694       CMP R9 0
0x00005698       BEQ timer_no_wake

    ; Wake the expired tasks using our new function
0x000056A0       LI R1 sleep_waitq
0x000056A8       MOV R2 R9
0x000056AC       BL waitq_wake_bitmask

timer_no_wake:

    ; Yield the CPU (reschedule and switch tasks)
0x000056B4       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x000056BC       LI R2 0x00102000
0x000056C4       LI R3 1
0x000056CC       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x000056D0       LI R1 uart_rx_waitq
0x000056D8       BL waitq_wake_all
0x000056E0       LI R1 uart_tx_waitq
0x000056E8       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x000056F0       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x000056F8       POP R1                  ; stval, informational only
0x000056FC       POP R1                  ; scause, informational only
0x00005700       POP R1
0x00005704       CSRW SSTATUS R1
0x00005708       POP R1
0x0000570C       CSRW SFLAGS R1
0x00005710       POP R1
0x00005714       CSRW SEPC R1
0x00005718       POP R1                  ; interrupted task SP
0x0000571C       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00005720       POP R15
0x00005724       POP R14
0x00005728       POP R12
0x0000572C       POP R11
0x00005730       POP R10
0x00005734       POP R9
0x00005738       POP R8
0x0000573C       POP R7
0x00005740       POP R6
0x00005744       POP R5
0x00005748       POP R4
0x0000574C       POP R3
0x00005750       POP R2
0x00005754       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00005758       CSRRW SP SSCRATCH SP
0x0000575C       SRET


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

0x00007CCF       LDW R4 [R11 + TAR_IDX_TYPE] ; FILE type
0x00007CD3       LDW R5 [R11 + TAR_IDX_SIZE] ; file size
0x00007CD7       BL inode_init

0x00007CDF       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x00007CE3       POP R10
0x00007CE7       POP R9
0x00007CEB       POP R8
0x00007CEF       POP LR
0x00007CF3       RET

tar_lookup_not_found:

0x00007CF7       LI R1 0             ; R1 = NULL

0x00007CFF       POP R10
0x00007D03       POP R9
0x00007D07       POP R8
0x00007D0B       POP LR
0x00007D0F       RET


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

0x00007D13       PUSH LR
0x00007D17       PUSH R8
0x00007D1B       PUSH R9
0x00007D1F       PUSH R10
0x00007D23       PUSH R11
0x00007D27       PUSH R12

0x00007D2B       MOV R8 R1                  ; current tar header
0x00007D2F       LI R11 tar_limit
0x00007D37       ADD R2 R1 R2
0x00007D3B       STW R2 [R11]               ; exclusive end of archive

0x00007D3F       LI R9 tar_index            ; current index entry

0x00007D47       LI R10 0                   ; file count

tar_scan_loop:

0x00007D4F       CMP R10 MAX_TAR_FILES
0x00007D53       BGE tar_done                ; check before writing the next index entry

0x00007D5B       LI R11 tar_limit
0x00007D63       LDW R11 [R11]
0x00007D67       LI R12 TAR_HEADER_SIZE
0x00007D6F       ADD R12 R8 R12
0x00007D73       CMP R12 R11
0x00007D77       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x00007D7F       LDB R11 [R8 + TAR_NAME_OFF]

0x00007D83       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x00007D87       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x00007D8F       MOV R11 R8

0x00007D93       ADD R11 R11 TAR_NAME_OFF

0x00007D97       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x00007D9B       MOV R1 R8
0x00007D9F       ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

0x00007DA3       BL tar_parse_octal         ; parse octal size from tar header field to binary integer

0x00007DAB       MOV R12 R1                 ; save file resulted binary size

0x00007DAF       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00007DB3       MOV R11 R8
0x00007DB7       LI R2 TAR_HEADER_SIZE
0x00007DBF       ADD R11 R11 R2

0x00007DC3       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00007DC7       LI R2 TAR_TYPE_OFF
0x00007DCF       ADD R2 R8 R2
0x00007DD3       LDB R11 [R2]
0x00007DD7       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00007DDB       ADD R10 R10 1               ; othewise go to next file count

0x00007DDF       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

0x00007DE3       MOV R11 R12

    ; round up to 512 boundary

0x00007DE7       LI R2 511
0x00007DEF       ADD R11 R11 R2

0x00007DF3       SHR R11 R11 9
0x00007DF7       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x00007DFB       LI R2 TAR_HEADER_SIZE
0x00007E03       ADD R8 R8 R2

0x00007E07       ADD R8 R8 R11           ; advance to next tar header

0x00007E0B       LI R12 tar_limit
0x00007E13       LDW R12 [R12]
0x00007E17       CMP R8 R12
0x00007E1B       BGTU tar_done            ; file data/padding extends beyond archive

0x00007E23       B tar_scan_loop

tar_done:

0x00007E2B       LI R11 tar_count        ; store total file count for this tar archive in global variable

0x00007E33       STW R10 [R11]

0x00007E37       POP R12
0x00007E3B       POP R11
0x00007E3F       POP R10
0x00007E43       POP R9
0x00007E47       POP R8
0x00007E4B       POP LR

0x00007E4F       RET

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

0x00007E53       PUSH R2
0x00007E57       PUSH R3
0x00007E5B       PUSH R4

0x00007E5F       LI   R2 0                  ; result

octal_loop:

0x00007E67       LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

0x00007E6B       CMP  R3 0
0x00007E6F       BEQ  octal_done

0x00007E77       LI   R4 32                 ; ' '
0x00007E7F       CMP  R3 R4
0x00007E83       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x00007E8B       LI   R4 48
0x00007E93       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x00007E97       SHL  R2 R2 3               ; multiply by 8

0x00007E9B       ADD  R2 R2 R3              ; add digit

0x00007E9F       ADD  R1 R1 1               ; advance to next octal character

0x00007EA3       B    octal_loop

octal_done:

0x00007EAB       MOV  R1 R2                 ; return binary result in R1

0x00007EAF       POP  R4
0x00007EB3       POP  R3
0x00007EB7       POP  R2
0x00007EBB       RET

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

0x00007ED6       PUSH LR
0x00007EDA       PUSH R8
0x00007EDE       PUSH R9
0x00007EE2       PUSH R10

0x00007EE6       LI R8 0

0x00007EEE       LI R10 tar_count
0x00007EF6       LDW R10 [R10]

0x00007EFA       LI R1 tarfs_banner
0x00007F02       BL kputs

dump_loop:

0x00007F0A       CMP R8 R10
0x00007F0E       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00007F16       LI R1 tar_index

0x00007F1E       LI R2 TAR_IDX_SIZEOF
0x00007F26       MUL R3 R8 R2

0x00007F2A       ADD R9 R1 R3

    ; filename

0x00007F2E       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x00007F32       MOV R1 R2
0x00007F36       BL kputs

    ; newline

0x00007F3E       LI R1 newline
0x00007F46       BL kputs

0x00007F4E       ADD R8 R8 1
0x00007F52       B dump_loop

dump_done:

0x00007F5A       POP R10
0x00007F5E       POP R9
0x00007F62       POP R8
0x00007F66       POP LR
0x00007F6A       RET

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

0x00007F6E       PUSH LR
0x00007F72       PUSH R8
0x00007F76       PUSH R9
0x00007F7A       PUSH R10
0x00007F7E       PUSH R11
0x00007F82       PUSH R12

0x00007F86       MOV R8 R1
0x00007F8A       MOV R9 R2
0x00007F8E       MOV R10 R3

0x00007F92       CMP R10 0
0x00007F96       BEQ tarfs_read_eof

0x00007F9E       PUSH R8
0x00007FA2       PUSH R9
0x00007FA6       MOV R1 R9
0x00007FAA       MOV R2 R10
0x00007FAE       LI R3 1                    ; destination must be user-writable
0x00007FB6       BL user_buffer_valid_range
0x00007FBE       POP R9
0x00007FC2       POP R8
0x00007FC6       CMP R1 1
0x00007FCA       BNE tarfs_read_fault

0x00007FD2       LDW R11 [R8 + FILE_INODE]
0x00007FD6       LDW R5  [R11 + INODE_TYPE]
0x00007FDA       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x00007FDE       LI  R2 INODE_DIR
0x00007FE6       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x00007FEA       BEQ tarfs_read_dir

0x00007FF2       LDW R12 [R8 + FILE_OFFSET]
0x00007FF6       LDW R4  [R11 + TAR_IDX_SIZE]

0x00007FFA       CMP R12 R4
0x00007FFE       BGEU tarfs_read_eof

0x00008006       SUB R4 R4 R12             ; bytes remaining
0x0000800A       CMP R10 R4
0x0000800E       BLEU tarfs_read_count_ready
0x00008016       MOV R10 R4

tarfs_read_count_ready:
0x0000801A       LDW R4 [R11 + TAR_IDX_DATA]
0x0000801E       ADD R4 R4 R12             ; kernel source
0x00008022       MOV R1 R9                 ; user destination
0x00008026       MOV R2 R10
0x0000802A       BL copy_to_user

0x00008032       ADD R12 R12 R1
0x00008036       STW R12 [R8 + FILE_OFFSET]
0x0000803A       B tarfs_read_done

tarfs_read_dir:
    ; directory read – call our dir read function
0x00008042       MOV R1 R8
0x00008046       MOV R2 R9
0x0000804A       MOV R3 R10
0x0000804E       BL tarfs_readdir
0x00008056       B tarfs_read_done   ; jump to the common return path

tarfs_read_fault:
0x0000805E       LI R1 ERR_FAULT
0x00008066       B tarfs_read_done

tarfs_read_eof:
0x0000806E       LI R1 0

tarfs_read_done:
0x00008076       POP R12
0x0000807A       POP R11
0x0000807E       POP R10
0x00008082       POP R9
0x00008086       POP R8
0x0000808A       POP LR
0x0000808E       RET

tarfs_write:
0x00008092       LI R1 ERR_ACCES
0x0000809A       RET

; --------------------------------------------------
; tarfs_readdir - read next directory entry into user buffer
;
; R1 = file* (opened directory)
; R2 = user buffer (struct dirent*)
; R3 = buffer length (should be >= DIRENT_SIZEOF)
;
; returns:
;   R1 = DIRENT_SIZEOF (74) on success, 0 on EOF, negative errno
; --------------------------------------------------
tarfs_readdir:
0x0000809E       PUSH LR
0x000080A2       PUSH R8
0x000080A6       PUSH R9
0x000080AA       PUSH R10
0x000080AE       PUSH R11
0x000080B2       PUSH R12

    ; ---- validate user buffer ----
0x000080B6       MOV R8 R2                 ; save user buffer + to stack
0x000080BA       PUSH R8
0x000080BE       MOV R9 R3                 ; save length
0x000080C2       MOV R12 R1                ; save file ptr
0x000080C6       CMP R9 DIRENT_SIZEOF
0x000080CA       BLT readdir_short         ; not enough space for one entry

    ;PUSH R9
0x000080D2       MOV R1 R8
0x000080D6       LI  R2 DIRENT_SIZEOF
0x000080DE       LI  R3 1                  ; write access
0x000080E6       BL  user_buffer_valid_range
    ;POP R9
0x000080EE       CMP R1 1
0x000080F2       BNE readdir_fault

    ; ---- get inode and private data ----
0x000080FA       LDW R4 [R12 + FILE_INODE]    ; R4 = inode* r12 -file ptf
0x000080FE       LDW R5 [R4 + INODE_PRIVATE] ; R5 = tar index entry for the directory itself
0x00008102       CMP R5 0
0x00008106       BEQ readdir_eof

    ; get directory prefix from that tar entry (e.g., "etc/")
0x0000810E       LDW R10 [R5 + TAR_IDX_NAME] ; R10 = full path of directory (with trailing /)

    ; load current entry index from file offset
0x00008112       LDW R11 [R12 + FILE_OFFSET] ; R11 = index (number of entries already returned)

    ; ---- scan tar index from this index ----
    ;LI R12 tar_count
    ;LDW R12 [R12]             ; total number of tar entries
0x00008116       MOV R6 R11                ; current scan index

readdir_scan:
0x0000811A       LI  R1 tar_count          ;total number entryes in index count
0x00008122       LDW R1 [R1]
0x00008126       CMP R6 R1
0x0000812A       BGE readdir_eof           ; no more entries

    ; entry = tar_index + R6 * TAR_IDX_SIZEOF
0x00008132       LI R1 tar_index
0x0000813A       LI R2 TAR_IDX_SIZEOF
0x00008142       MUL R3 R6 R2
0x00008146       ADD R7 R1 R3              ; R7 = &tar_index[R6]

    ; check if this entry's name starts with the directory prefix
0x0000814A       LDW R1 [R7 + TAR_IDX_NAME]
0x0000814E       MOV R2 R10
0x00008152       BL str_prefix            ; check if tar_index entry name ie etc/motd matches prefix etc/
0x0000815A       CMP R1 1
0x0000815E       BNE readdir_skip

    ; skip the directory entry itself (exact match)
0x00008166       LDW R1 [R7 + TAR_IDX_NAME]
0x0000816A       MOV R2 R10
0x0000816E       BL strcmp                ; ie skip if we read 'etc/' == etc/
0x00008176       CMP R1 1
0x0000817A       BEQ readdir_skip

    ; ---- found a matching file/directory ----
    ; skip the prefix to get the relative component
0x00008182       LDW R1 [R7 + TAR_IDX_NAME]
0x00008186       MOV R2 R10
0x0000818A       BL skip_prefix            ; R1 = pointer after prefix omit prefix - just filename 'etc/bin' -> bin
0x00008192       MOV R9 R1                 ; R9 = component name (e.g., "motd" (file) or "network/ (subdir)")

    ; compute the component length up to next '/'
0x00008196       MOV R1 R9
0x0000819A       BL path_component_len     ; R1 = component length (L)
0x000081A2       MOV R8 R1                 ; R8 = component name length

    ; clamp to DIRENT_NAME_LEN - 1 to avoid overflow
0x000081A6       LI R2 63
0x000081AE       CMP R8 R2
0x000081B2       BLE readdir_name_ok
0x000081BA       MOV R8 63
readdir_name_ok:
    ; save R6 cureent entry index
0x000081BE       MOV R11 R6
    ;get type
0x000081C2       LDW R6  [R7 + TAR_IDX_TYPE]  ;R6  R11 = tar type (0=file, 5=dir)

    ; map tar type to DT_* constants
0x000081C6       LI  R1 INODE_DIR     ;adapted 35hex yess
0x000081CE       CMP R6 R1
    ;CMP R6 5            ;needs to be adapted 35hex
0x000081D2       BEQ readdir_type_dir
0x000081DA       LI R6 DT_REG               ; default type to regular r11 - file
0x000081E2       B readdir_type_done
readdir_type_dir:
0x000081EA       LI R6 DT_DIR               ; switch type R11 - dir
readdir_type_done:

    ; ---- build struct dirent in KBUF_WR ----
; macro: GET_CURR_TASK_IDX R4
0x000081F2   LI R1 CURRENT_TASK
0x000081FA   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000081FE   LI R1 TASK_SIZE
0x00008206   MUL R3 R4 R1
0x0000820A   LI R5 tasks
0x00008212   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00008216   LDW R1 [R5 + TASK_KBUF_WR_PTR]


   ; GET_CURR_TASK_IDX R2
   ; GET_TASK_PTR R2, R2
   ; TASK_GET_KBUF_WR R5, R2    ; R5 = kernel write buffer

    ; d_ino = index + 1 (dummy); R1 = kernel write buffer - form dirent stuc with read dir-entry
0x0000821A       ADD R3 R11 1
0x0000821E       STW R3 [R1 + DIRENT_INODE]
    ; d_type = DT_REG or DT_DIR
0x00008222       STW R6 [R1 + DIRENT_TYPE]

    ; get size from tar entry
0x00008226       LDW R2  [R7 + TAR_IDX_SIZE]  ; R12 = file size
    ; d_size = file size
0x0000822A       STW R2  [R1 + DIRENT_SIZE]

    ; ---- update file offset to next entry ----
    ;ADD R6 R6 1
0x0000822E       STW R3 [R12 + FILE_OFFSET] ; store new index R11+1 for next read


    ; d_name = component name (copy up to 64 bytes)
0x00008232       MOV R2 R9                  ; source name R9 = component name (e.g., "motd" (file) or "network/ (subdir)")
0x00008236       ADD R3 R1 DIRENT_NAME      ; destination dirent struc in KBUF_WR
0x0000823A       LI  R6 0                   ; index

readdir_copy_name:
0x00008242       CMP R6 R8                  ;R8 = component name length
0x00008246       BGE readdir_copy_name_done
0x0000824E       LDB R10 [R2 + R6]
0x00008252       STB R10 [R3 + R6]
0x00008256       ADD R6 R6 1
0x0000825A       B readdir_copy_name

readdir_copy_name_done:
    ; NUL-terminate
0x00008262       LI R10 0
0x0000826A       STB R10 [R3 + R6]

    ; ---- copy whole dirent (DIRENT_SIZEOF bytes) to user buffer ----

0x0000826E       LI  R2 DIRENT_SIZEOF      ; len dirent
0x00008276       MOV R4 R1                 ; kernel source (KBUF_WR)
0x0000827A       POP R1                    ; user buffer (original)
    ;MOV R1 R8                 ; user buffer (original)
0x0000827E       BL copy_to_user
0x00008286       CMP R1 DIRENT_SIZEOF
0x0000828A       BNE readdir_fault

    ; return number of bytes written (DIRENT_SIZEOF)
0x00008292       MOV R1 DIRENT_SIZEOF
0x00008296       POP R12
0x0000829A       POP R11
0x0000829E       POP R10
0x000082A2       POP R9
0x000082A6       POP R8
0x000082AA       POP LR
0x000082AE       RET

readdir_skip:
0x000082B2       ADD R6 R6 1
0x000082B6       B readdir_scan

readdir_eof:
0x000082BE       Pop R1          ;bc we saved r8 inside loop
0x000082C2       LI R1 0
0x000082CA       POP R12
0x000082CE       POP R11
0x000082D2       POP R10
0x000082D6       POP R9
0x000082DA       POP R8
0x000082DE       POP LR
0x000082E2       RET

readdir_short:
0x000082E6       Pop R1
0x000082EA       LI R1 ERR_FAULT
0x000082F2       POP R12
0x000082F6       POP R11
0x000082FA       POP R10
0x000082FE       POP R9
0x00008302       POP R8
0x00008306       POP LR
0x0000830A       RET

readdir_fault:
0x0000830E       Pop R1
0x00008312       LI R1 ERR_FAULT
0x0000831A       POP R12
0x0000831E       POP R11
0x00008322       POP R10
0x00008326       POP R9
0x0000832A       POP R8
0x0000832E       POP LR
0x00008332       RET


;==========================================================================
;tarfs_readdir1 - scans tar index reads files in a dir and prints output
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

tarfs_readdir1:

0x00008336       PUSH LR
0x0000833A       PUSH R8
0x0000833E       PUSH R9
0x00008342       PUSH R10
0x00008346       PUSH R11

0x0000834A       MOV R8 R1              ; save directory path
0x0000834E       LI R9 0                ; index

0x00008356       LI R10 tar_count
0x0000835E       LDW R10 [R10]
tr_loop:
0x00008362       CMP R9 R10
0x00008366       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x0000836E       LI R1 tar_index
0x00008376       LI R2 TAR_IDX_SIZEOF
0x0000837E       MUL R3 R9 R2
0x00008382       ADD R11 R1 R3
    ; entry name
0x00008386       LDW R1 [R11 + TAR_IDX_NAME]
0x0000838A       MOV R2 R8                       ; src dirname "etc/"
0x0000838E       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x00008396       CMP R1 1
0x0000839A       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x000083A2       LDW R1 [R11 + TAR_IDX_NAME]
0x000083A6       MOV R2 R8                       ; prefix
0x000083AA       BL skip_prefix                  ; omit prefix nd print just filename

0x000083B2       MOV R12 R1         ; save component ptr
0x000083B6       BL path_component_len ; out R1-length
0x000083BE       MOV R2 R1
0x000083C2       MOV R1 R12
0x000083C6       BL kputsn   ; r1-ptr r2-len of string

0x000083CE       LI R1 newline
0x000083D6       BL kputs

tr_next:
0x000083DE       ADD R9 R9 1                     ;to next entry for check
0x000083E2       B tr_loop
tr_done:
0x000083EA       POP R11
0x000083EE       POP R10
0x000083F2       POP R9
0x000083F6       POP R8
0x000083FA       POP LR
0x000083FE       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x00008402       PUSH LR
0x00008406       PUSH R8
0x0000840A       MOV R8 R1

kputs_loop:
0x0000840E       LDB R1 [R8]

0x00008412       CMP R1 0
0x00008416       BEQ kputs_done

0x0000841E       BL uart_putc

0x00008426       ADD R8 R8 1

0x0000842A       B kputs_loop

kputs_done:
0x00008432       POP R8
0x00008436       POP LR
0x0000843A       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x0000843E       PUSH LR
0x00008442       PUSH R8
0x00008446       PUSH R9
0x0000844A       MOV R8 R1
0x0000844E       MOV R9 R2
kputsn_loop:
0x00008452       CMP R9 0
0x00008456       BEQ kputsn_done
0x0000845E       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x00008462       BL uart_putc
0x0000846A       ADD R8 R8 1
0x0000846E       SUB R9 R9 1
0x00008472       B kputsn_loop
kputsn_done:
0x0000847A       POP R9
0x0000847E       POP R8
0x00008482       POP LR
0x00008486       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x0000848A       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x00008492       LDW R2 [R3 + 4]   ; read UART status register
0x00008496       AND R2 R2 2       ; check if TX ready (bit 1)
0x0000849A       CMP R2 0
0x0000849E       BEQ poll

0x000084A6       STW R1 [R3 + 0]   ; R1 is the character value
0x000084AA       RET



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
0x000084AE       PUSH R8
0x000084B2       PUSH R9
0x000084B6       PUSH R10

0x000084BA       MOV R9 R1                  ; preserve wait queue pointer
0x000084BE       MOV R10 R2                 ; preserve debug wait reason
0x000084C2       MOV R8 R3                  ; preserve task state to set

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x000084C6   LI R1 CURRENT_TASK
0x000084CE   LDW R2 [R1]

0x000084D2       LI R4 1
0x000084DA       SHL R4 R4 R2               ; R4 = bit for current task
0x000084DE       LDW R5 [R9 + WQ_MASK]
0x000084E2       OR R5 R5 R4
0x000084E6       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x000084EA   LI R1 TASK_SIZE
0x000084F2   MUL R3 R2 R1
0x000084F6   LI R5 tasks
0x000084FE   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00008502   LI R1 TASK_BLOCKED_IO
0x0000850A   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x0000850E   STW R10 [R5 + TASK_WAIT]

; addition trick if R3 is set as TASK_SLEEPING then we also set the state to TASK_SLEEPING for syscall sleep/waitpid
0x00008512       CMP R8 TASK_SLEEPING
0x00008516       BNE waitq_prepare_done
; macro: TASK_SET_STATE R5, TASK_SLEEPING
0x0000851E   LI R1 TASK_SLEEPING
0x00008526   STW R1 [R5 + TASK_STATE]

waitq_prepare_done:
0x0000852A       POP R10
0x0000852E       POP R9
0x00008532       POP R8
0x00008536       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x0000853A       PUSH R9

0x0000853E       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00008542   LI R1 CURRENT_TASK
0x0000854A   LDW R2 [R1]

0x0000854E       LDW R4 [R9 + WQ_MASK]

0x00008552       LI  R5 1
0x0000855A       SHL R5 R5 R2        ;shift to position of current task bit

0x0000855E       NOT R5 R5           ; invert to get mask for clearing this bit

0x00008562       AND R4 R4 R5        ; clear current task bit

0x00008566       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x0000856A   LI R1 TASK_SIZE
0x00008572   MUL R3 R2 R1
0x00008576   LI R5 tasks
0x0000857E   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x00008582   LI R1 TASK_READY
0x0000858A   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x0000858E   LI R1 WAIT_NONE
0x00008596   STW R1 [R5 + TASK_WAIT]

0x0000859A       POP R9
0x0000859E       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x000085A2       PUSH LR
0x000085A6       BL schedule_call
0x000085AE       POP LR
0x000085B2       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x000085B6       PUSH LR

0x000085BA       MOV R9 R1
0x000085BE       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x000085C2       LI R10 0
0x000085CA       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x000085CE       LI R2 0                    ; task index

wq_wake_loop:
0x000085D6       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x000085DA       BGE wq_wake_done

0x000085E2       LI R3 1
0x000085EA       SHL R3 R3 R2               ; R3 = bit for task R2
0x000085EE       AND R4 R8 R3
0x000085F2       CMP R4 0
0x000085F6       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x000085FE   LI R1 TASK_SIZE
0x00008606   MUL R3 R2 R1
0x0000860A   LI R5 tasks
0x00008612   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00008616   LI R1 TASK_READY
0x0000861E   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00008622   LI R1 WAIT_NONE
0x0000862A   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x0000862E       ADD R2 R2 1
0x00008632       B wq_wake_loop

wq_wake_done:
0x0000863A       POP LR
0x0000863E       RET

waitq_wake_bitmask:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = bitmask of tasks to wake (1 = wake, 0 = ignore)
    ; Wakes every task currently recorded in the R2 bitmask.
    ;================================================================

0x00008642       PUSH LR

0x00008646       MOV R9 R1
0x0000864A       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x0000864E       MOV R10 R2                 ;
0x00008652       NOT R10 R10                ; invert bitmask to clear only specified tasks
0x00008656       AND R10 R8 R10             ; clear only specified tasks
0x0000865A       STW R10 [R9 + WQ_MASK]     ; update queue entries to remove (tobe) woken  tasks

0x0000865E       MOV R8 R2                  ; R8 = bitmask of tasks to wake
0x00008662       LI R2 0                    ; task index

wq_wake_b_loop:
0x0000866A       CMP R2 MAX_TASKS           ; check if we processed all tasks in bitmask
0x0000866E       BGE wq_wake_b_done

0x00008676       LI R3 1
0x0000867E       SHL R3 R3 R2               ; R3 = bit for task R2
0x00008682       AND R4 R8 R3               ; check if this task is in the wake bitmask
0x00008686       CMP R4 0
0x0000868A       BEQ wq_wake_b_next

; macro: GET_TASK_PTR R5, R2        ; wake task R2 if its in the bitmask
0x00008692   LI R1 TASK_SIZE
0x0000869A   MUL R3 R2 R1
0x0000869E   LI R5 tasks
0x000086A6   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x000086AA   LI R1 TASK_READY
0x000086B2   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x000086B6   LI R1 WAIT_NONE
0x000086BE   STW R1 [R5 + TASK_WAIT]

wq_wake_b_next:
0x000086C2       ADD R2 R2 1
0x000086C6       B wq_wake_b_loop

wq_wake_b_done:
0x000086CE       POP LR
0x000086D2       RET

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
.EQU INODE_DIR,   53   ;'5' -taken from tarfs needs to be fixed!
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
0x00008CD6       LI R2 0                      ; index

ia_loop:
0x00008CDE       CMP R2 MAX_INODES
0x00008CE2       BGE ia_fail

0x00008CEA       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x00008CEE       LI R4 inode_used
0x00008CF6       ADD R4 R4 R3                  ; &inode_used[index]

0x00008CFA       LDW R5 [R4]                   ; load used marker
0x00008CFE       CMP R5 0
0x00008D02       BEQ ia_found

0x00008D0A       ADD R2 R2 1
0x00008D0E       B ia_loop

ia_found:
0x00008D16       LI R5 1
0x00008D1E       STW R5 [R4]                  ; mark used

0x00008D22       LI R3 INODE_SIZEOF
0x00008D2A       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x00008D2E       LI R1 inode_pool
0x00008D36       ADD R1 R1 R6                 ; return inode ptr
0x00008D3A       RET

ia_fail:
0x00008D3E       LI R1 0
0x00008D46       RET

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

0x00008D4A       LI R2 inode_pool
0x00008D52       SUB R3 R1 R2                  ; offset from pool base

0x00008D56       LI R4 INODE_SIZEOF
0x00008D5E       DIV R5 R3 R4                 ; index

0x00008D62       SHL R5 R5 2                  ; index * 4 (u32 array)
0x00008D66       LI R6 inode_used
0x00008D6E       ADD R6 R6 R5                 ; &inode_used[index]

0x00008D72       LI R7 0
0x00008D7A       STW R7 [R6]                  ; mark free

0x00008D7E       RET

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

0x00008D82       STW R2 [R1 + INODE_OPS]
0x00008D86       STW R3 [R1 + INODE_PRIVATE]
0x00008D8A       STW R4 [R1 + INODE_TYPE]
0x00008D8E       STW R5 [R1 + INODE_SIZE]
0x00008D92       LI R2 1
0x00008D9A       STW R2 [R1 + INODE_REFCNT]
0x00008D9E       RET

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
0x00008DA2       LDW R2 [R1 + INODE_REFCNT]
0x00008DA6       ADD R2 R2 1
0x00008DAA       STW R2 [R1 + INODE_REFCNT]
0x00008DAE       RET

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
0x00008DB2       PUSH LR
0x00008DB6       LDW R2 [R1 + INODE_REFCNT]
0x00008DBA       SUB R2 R2 1
0x00008DBE       STW R2 [R1 + INODE_REFCNT]
0x00008DC2       CMP R2 0
0x00008DC6       BNE inode_put_done
    ; destroy inode
0x00008DCE       BL inode_free

inode_put_done:
0x00008DD6       POP LR
0x00008DDA       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x00008DDE       LDW R2 [R1 + FILE_REFCNT]
0x00008DE2       ADD R2 R2 1
0x00008DE6       STW R2 [R1 + FILE_REFCNT]
0x00008DEA       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x00008DEE       PUSH LR
0x00008DF2       LDW R2 [R1 + FILE_REFCNT]
0x00008DF6       SUB R2 R2 1
0x00008DFA       STW R2 [R1 + FILE_REFCNT]
0x00008DFE       CMP R2 0
0x00008E02       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x00008E0A       BL file_free

file_put_done:
0x00008E12       POP LR
0x00008E16       RET


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
0x00008E1A       PUSH LR
0x00008E1E       MOV R8 R1          ; pathname

0x00008E22       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x00008E2A       CMP R1 0
0x00008E2E       BNE vfs_done

0x00008E36       MOV R1 R8

0x00008E3A       BL tarfs_lookup     ; 2 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x00008E42       CMP R1 0
0x00008E46       BEQ vfs_not_found

vfs_done:
0x00008E4E       POP LR          ;3 R1 - return inode
0x00008E52       RET

vfs_not_found:
0x00008E56       LI R1 0         ;it can be just ret but i added it for result clarity
0x00008E5E       POP LR          ;or R1 - Nul
0x00008E62       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x00008E66       PUSH LR
0x00008E6A       PUSH R8
0x00008E6E       PUSH R9
0x00008E72       PUSH R10
0x00008E76       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x00008E7A       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x00008E82       CMP R1 0
0x00008E86       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x00008E8E       MOV R8 R1            ; save inode ptr

0x00008E92       LDW R2 [R8 + INODE_TYPE]
0x00008E96       LI R3 INODE_DIR
0x00008E9E       CMP R2 R3

    ;BEQ fail_isdir            ; if pathname is a dir -implemented readdir

0x00008EA2       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x00008EAA       CMP R1 0
0x00008EAE       BEQ fail_nfile

0x00008EB6       MOV R9 R1                ; save file*

    ; initialize file object ;
0x00008EBA       MOV R1 R9                ; R1 file*
0x00008EBE       MOV R2 R8                ; inode*
0x00008EC2       MOV R3 R10               ; flags
0x00008EC6       BL file_init

0x00008ECE       MOV R1 R9
0x00008ED2       BL fd_alloc             ; R1 inited file ptr
0x00008EDA       LI R2 ERR_MFILE
0x00008EE2       CMP R1 R2
0x00008EE6       BEQ fail_fd
                            ; R1 - holds fd
0x00008EEE       POP R10
0x00008EF2       POP R9
0x00008EF6       POP R8
0x00008EFA       POP LR
0x00008EFE       RET

fail_fd:
0x00008F02       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x00008F06       LDW R2 [R1 + FILE_INODE]

0x00008F0A       MOV R1 R2
0x00008F0E       BL inode_put             ; close inode refcnt--

0x00008F16       MOV R1 R9
0x00008F1A       BL file_free
0x00008F22       LI R1 ERR_MFILE
0x00008F2A       B  vfs_exit

fail_noent:
0x00008F32       LI R1 ERR_NOENT
0x00008F3A       B  vfs_exit
fail_nfile:
0x00008F42       LI R1 ERR_NFILE
0x00008F4A       B  vfs_exit
fail_isdir:
0x00008F52       LI R1 ERR_ISDIR
0x00008F5A       B  vfs_exit
fail_acces:
0x00008F62       LI R1 ERR_ACCES
vfs_exit:
0x00008F6A       POP R10
0x00008F6E       POP R9
0x00008F72       POP R8
0x00008F76       POP LR
0x00008F7A       RET

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
0x00008F7E       PUSH LR
0x00008F82       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x00008F8A       CMP R1 0
0x00008F8E       BEQ badf_fail

0x00008F96       MOV R8 R1          ; save file*

0x00008F9A       MOV R1 R8
0x00008F9E       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x00008FA6       LI  R1 0        ; success
0x00008FAE       POP LR
0x00008FB2       RET

badf_fail:
0x00008FB6       LI R1 ERR_BADF
0x00008FBE       POP LR
0x00008FC2       RET


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

0x00008FC6       LI R2 0                      ; index

fa_loop:
0x00008FCE       CMP R2 MAX_FILES
0x00008FD2       BGE fa_fail

0x00008FDA       SHL R3 R2 2                  ; index * 4
0x00008FDE       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00008FE6       ADD R4 R4 R3

0x00008FEA       LDW R5 [R4]
0x00008FEE       CMP R5 0
0x00008FF2       BEQ fa_found

0x00008FFA       ADD R2 R2 1
0x00008FFE       B fa_loop

fa_found:
0x00009006       LI R5 1
0x0000900E       STW R5 [R4]                  ; mark slot used

0x00009012       LI R4 FILE_SIZE
0x0000901A       MUL R6 R2 R4

0x0000901E       LI R1 file_pool
0x00009026       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x0000902A       LI R7 0

0x00009032       STW R7 [R1 + FILE_INODE]
0x00009036       STW R7 [R1 + FILE_OFFSET]
0x0000903A       STW R7 [R1 + FILE_FLAGS]

0x0000903E       RET

fa_fail:
0x00009042       LI R1 0
0x0000904A       RET

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
0x0000904E       PUSH LR
0x00009052       PUSH R10
0x00009056       MOV  R10 R1
0x0000905A       LDW  R2 [R1 + FILE_INODE]

0x0000905E       CMP R2 0
0x00009062       BEQ no_inode

0x0000906A       MOV R1 R2
0x0000906E       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x00009076       MOV R1 R10
0x0000907A       LI  R2 file_pool
0x00009082       SUB R3 R1 R2                 ; offset from pool base

0x00009086       LI  R4 FILE_SIZE
0x0000908E       DIV R5 R3 R4                 ; slot number

0x00009092       SHL R5 R5 2                  ; slot * 4

0x00009096       LI  R6 file_used
0x0000909E       ADD R6 R6 R5                 ; address of slot in file_used

0x000090A2       LI R7 0
0x000090AA       STW R7 [R6]                  ; mark free
0x000090AE       POP R10
0x000090B2       POP LR
0x000090B6       RET


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

0x000090BA       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x000090BE       LI  R1 tasks
0x000090C6       LI  R2 TASK_SIZE
0x000090CE       LI  R3 MAX_TASKS
0x000090D6       MUL R3 R2 R3
0x000090DA       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x000090E2       LI R1 idle_task
0x000090EA       LI R2 0
0x000090F2       LI R3 0
0x000090FA       BL task_create

0x00009102       CMP R1 0
0x00009106       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task_init
    ; ----------------------------------

0x0000910E       LI R1 TASK_INIT_START
0x00009116       LI R2 1
0x0000911E       LI R3 0
0x00009126       BL task_create

0x0000912E       CMP R1 0
0x00009132       BEQ init_scheduler_fail

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

    ;LI R1 TASK_B_START
    ;LI R2 2
    ;LI R3 0
    ;BL task_create

    ;CMP R1 0
    ;BEQ init_scheduler_fail

    ; ----------------------------------
    ; task C -check gettime brk,sbrk syscalls
    ; ----------------------------------

  ;  LI R1 TASK_C_START
   ; LI R2 2
    ;LI R3 0
    ;BL task_create

    ;CMP R1 0
    ;BEQ init_scheduler_fail

    ; Initialize the dynamic fork PID allocator after bootstrap tasks.
0x0000913A       LI R1 task_count
0x00009142       LI R2 2                     ; last task_pid+1 for now (task 0 and task 1) next id is 2
0x0000914A       STW R2 [R1]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x0000914E       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x00009156   LI R1 CURRENT_TASK
0x0000915E   STW R2 [R1]

0x00009162       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00009166       RET


init_scheduler_fail:

0x0000916A       DEBUG 99

halt:
0x0000916E       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00009176   LI R1 CURRENT_TASK
0x0000917E   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x00009182       ADD R3 R2 1

wrap_check:

0x00009186       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x0000918A       BLT check_task
0x00009192       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x0000919A       LI R4 TASK_SIZE
0x000091A2       MUL R5 R3 R4
0x000091A6       LI R6 tasks
0x000091AE       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x000091B2       LDW R7 [R5 + TASK_STATE]

0x000091B6       CMP R7 1
0x000091BA       BEQ do_switch
    ; if not ready go to next task in list
0x000091C2       ADD R3 R3 1
0x000091C6       B wrap_check

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
0x000091CE   LI R1 CURRENT_TASK
0x000091D6   STW R3 [R1]
0x000091DA       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x000091DE   LI R1 TASK_SIZE
0x000091E6   MUL R3 R2 R1
0x000091EA   LI R5 tasks
0x000091F2   ADD R5 R5 R3
0x000091F6       MOV R3 R8
0x000091FA       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x000091FE       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00009202   STW R7 [R5 + TASK_USP]

0x00009206       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x0000920A   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x0000920E   LI R1 RESUME_TRAP
0x00009216   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x0000921A   LI R1 TASK_SIZE
0x00009222   MUL R3 R8 R1
0x00009226   LI R5 tasks
0x0000922E   ADD R5 R5 R3
0x00009232       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x00009236   LDW R7 [R5 + TASK_PTBR]
0x0000923A       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x0000923E   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x00009242   LDW R7 [R9 + TASK_STATE]
0x00009246       CMP R7 TASK_ZOMBIE
0x0000924A       BNE switch_old_reaped
0x00009252       PUSH R5
0x00009256       MOV R1 R9
0x0000925A       BL task_destroy
0x00009262       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x00009266   LDW R7 [R5 + TASK_RESUME]
0x0000926A       CMP R7 RESUME_KERNEL
0x0000926E       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x00009276       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x0000927E       PUSH R1
0x00009282       PUSH R2
0x00009286       PUSH R3
0x0000928A       PUSH R4
0x0000928E       PUSH R5
0x00009292       PUSH R6
0x00009296       PUSH R7
0x0000929A       PUSH R8
0x0000929E       PUSH R9
0x000092A2       PUSH R10
0x000092A6       PUSH R11
0x000092AA       PUSH R12
0x000092AE       PUSH R14
0x000092B2       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x000092B6   LI R1 CURRENT_TASK
0x000092BE   LDW R2 [R1]

0x000092C2       ADD R3 R2 1

schedule_call_wrap_check:
0x000092C6       CMP R3 MAX_TASKS
0x000092CA       BLT schedule_call_check_task
0x000092D2       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x000092DA       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x000092DE   LI R1 TASK_SIZE
0x000092E6   MUL R3 R8 R1
0x000092EA   LI R5 tasks
0x000092F2   ADD R5 R5 R3
0x000092F6       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x000092FA   LDW R7 [R5 + TASK_STATE]
0x000092FE       CMP R7 TASK_READY               ; check it can be run
0x00009302       BEQ schedule_call_do_switch

0x0000930A       ADD R3 R3 1
0x0000930E       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00009316   LI R1 CURRENT_TASK
0x0000931E   STW R3 [R1]
0x00009322       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00009326   LI R1 TASK_SIZE
0x0000932E   MUL R3 R2 R1
0x00009332   LI R5 tasks
0x0000933A   ADD R5 R5 R3
0x0000933E       MOV R3 R8

0x00009342       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x00009346   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x0000934A   LI R1 RESUME_KERNEL
0x00009352   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x00009356   LI R1 TASK_SIZE
0x0000935E   MUL R3 R8 R1
0x00009362   LI R5 tasks
0x0000936A   ADD R5 R5 R3
0x0000936E       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x00009372   LDW R7 [R5 + TASK_PTBR]
0x00009376       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x0000937A   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x0000937E   LDW R7 [R5 + TASK_RESUME]
0x00009382       CMP R7 RESUME_KERNEL
0x00009386       BEQ restore_kernel_context

0x0000938E       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x00009396       DISABLEINT                  ; RET does jump by LR(R15)
0x0000939A       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x0000939E       POP R14                     ; (in kernel)
0x000093A2       POP R12                     ; DI - to avoid int nesting
0x000093A6       POP R11
0x000093AA       POP R10
0x000093AE       POP R9
0x000093B2       POP R8
0x000093B6       POP R7
0x000093BA       POP R6
0x000093BE       POP R5
0x000093C2       POP R4
0x000093C6       POP R3
0x000093CA       POP R2
0x000093CE       POP R1
0x000093D2       RET
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
0x000093E6       PUSH  R5
0x000093EA       PUSH  R6
0x000093EE       PUSH  R7
0x000093F2       PUSH  R8
0x000093F6       PUSH  R9

0x000093FA       LI R2 0                  ; page index

pa_loop:
0x00009402       LI R1 MAX_PHYS_PAGES

0x0000940A       CMP R2 R1
0x0000940E       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00009416       MOV R3 R2
0x0000941A       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x0000941E       MOV R4 R2
0x00009422       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00009426       LI R5 page_bitmap
0x0000942E       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x00009432       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x00009436       LI R7 1
0x0000943E       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x00009442       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x00009446       CMP R8 0
0x0000944A       BEQ pa_found                ; if bit is 0, page is free

0x00009452       ADD R2 R2 1                 ; increment page index and check next page
0x00009456       B pa_loop

pa_found:

    ; mark page allocated

0x0000945E       OR  R6 R6 R7
0x00009462       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x00009466       LI  R9 PAGE_ALLOC_BASE

0x0000946E       MOV R1 R2
0x00009472       SHL R1 R1 12          ; page_index * 4096

0x00009476       ADD R1 R1 R9

0x0000947A       POP R9
0x0000947E       POP R8
0x00009482       POP R7
0x00009486       POP R6
0x0000948A       POP R5

0x0000948E       RET

pa_fail:

0x00009492       LI R1 0                     ; no free pages

0x0000949A       POP R9
0x0000949E       POP R8
0x000094A2       POP R7
0x000094A6       POP R6
0x000094AA       POP R5
0x000094AE       RET

;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free:
0x000094B2       PUSH  R5
0x000094B6       PUSH  R6
0x000094BA       PUSH  R7
0x000094BE       PUSH  R8
0x000094C2       PUSH  R9


0x000094C6       LI R2 PAGE_ALLOC_BASE
0x000094CE       SUB R3 R1 R2         ; calculate offset from base

0x000094D2       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x000094D6       MOV R4 R3
0x000094DA       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x000094DE       MOV R5 R3
0x000094E2       AND R5 R5 7          ; bit index in byte = page index % 8

0x000094E6       LI R6 page_bitmap
0x000094EE       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x000094F2       LDB R7 [R6]

0x000094F6       LI R8 1
0x000094FE       SHL R8 R8 R5         ; mask for this page's bit

0x00009502       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00009506       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x0000950A       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000950E       POP R9
0x00009512       POP R8
0x00009516       POP R7
0x0000951A       POP R6
0x0000951E       POP R5
0x00009522       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:

0x00009526       LI R2 0

pz_loop:

0x0000952E       CMP R3 0
0x00009532       BEQ pz_done

0x0000953A       STB R2 [R1]

0x0000953E       ADD R1 R1 1
0x00009542       SUB R3 R3 1

0x00009546       B pz_loop

pz_done:
0x0000954E       RET

;=================================================================
; memory copy at the given address (R1)<(R2) R3 = amount
;=================================================================

memcpy:

cpy_loop:
0x00009552       CMP R3 0
0x00009556       BEQ cpy_done
0x0000955E       LDB R4 [R2]
0x00009562       STB R4 [R1]
0x00009566       ADD R1 R1 1
0x0000956A       ADD R2 R2 1
0x0000956E       SUB R3 R3 1
0x00009572       B cpy_loop

cpy_done:
0x0000957A       RET

; ================================================================
; Copy a memory page (or other multiple of 4 bytes) by physical address.
; R1 = source physical address (should be aligned!)
; R2 = destination physical address (aligned!)
; R3 = size in bytes (must be multiple of 4)
; each time it copyes 4 bytes (1 word)
; ================================================================
page_copy:

page_copy_loop:
0x0000957E       CMP R3 0
0x00009582       BEQ page_copy_done
0x0000958A       LDW R4 [R1]
0x0000958E       STW R4 [R2]
0x00009592       ADD R1 R1 4
0x00009596       ADD R2 R2 4
0x0000959A       SUB R3 R3 4
0x0000959E       B page_copy_loop

page_copy_done:
0x000095A6       RET

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

0x00009AAE       PUSH LR

0x00009AB2       MOV R8 R1          ; entry
0x00009AB6       MOV R9 R2          ; pid
0x00009ABA       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x00009AC2       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x00009ACA       CMP R1 0
0x00009ACE       BEQ task_create_fail

0x00009AD6       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x00009ADA       MOV R1 R10
0x00009ADE       LI R3 TASK_SIZE
0x00009AE6       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x00009AEE   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x00009AF2   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x00009AF6       BL page_alloc
0x00009AFE       CMP R1 0
0x00009B02       BEQ task_create_fail

0x00009B0A       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x00009B0E   STW R1 [R10 + TASK_PTBR]

0x00009B12       MOV R1 R12
0x00009B16       LI  R3 PAGE_SIZE
0x00009B1E       BL  mem_zero                   ; zero out the sensitive new page table

0x00009B26       MOV R1 R12
0x00009B2A       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x00009B32   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00009B36   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x00009B3A   LDW R1 [R10 + TASK_PTBR]
0x00009B3E       MOV R2 R8
0x00009B42       LI R3 0xFFFFF000
0x00009B4A       AND R2 R2 R3
0x00009B4E       MOV R3 R2
0x00009B52       CMP R9 0
0x00009B56       BEQ task_create_map_kernel_entry
0x00009B5E       LI R4 USER_RX
0x00009B66       B task_create_map_entry
task_create_map_kernel_entry:
0x00009B6E       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x00009B76       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x00009B7E       BL page_alloc
0x00009B86       CMP R1 0
0x00009B8A       BEQ task_create_fail

0x00009B92       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x00009B96   STW R12 [R10 + TASK_USTACK_PAGE]

0x00009B9A       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x00009BA2   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x00009BA6   LDW R1 [R10 + TASK_PTBR]

0x00009BAA       LI  R2 USER_STACK_VA
0x00009BB2       MOV R3 R12
0x00009BB6       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x00009BBE       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x00009BC6       BL page_alloc
0x00009BCE       CMP R1 0
0x00009BD2       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x00009BDA   STW R1 [R10 + TASK_KSTACK_PAGE]
0x00009BDE       LI R2 PAGE_SIZE

0x00009BE6       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x00009BEA       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x00009BEE   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00009BF2   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x00009BF6       LI R1 0

0x00009BFE       PUSH R1            ; R1
0x00009C02       PUSH R1            ; R2
0x00009C06       PUSH R1            ; R3
0x00009C0A       PUSH R1            ; R4
0x00009C0E       PUSH R1            ; R5
0x00009C12       PUSH R1            ; R6
0x00009C16       PUSH R1            ; R7
0x00009C1A       PUSH R1            ; R8
0x00009C1E       PUSH R1            ; R9
0x00009C22       PUSH R1            ; R10
0x00009C26       PUSH R1            ; R11
0x00009C2A       PUSH R1            ; R12
0x00009C2E       PUSH R1            ; R14 (FP)
0x00009C32       PUSH R1            ; R15 (LR)

0x00009C36       PUSH R11           ; R11 - user SP top

0x00009C3A       MOV R1 R8
0x00009C3E       PUSH R1            ; sepc = entry

0x00009C42       LI R1 0
0x00009C4A       PUSH R1            ; sflags

0x00009C4E       CMP R9 0
0x00009C52       BEQ task_create_kernel_status
0x00009C5A       LI R1 0x20
0x00009C62       B task_create_status_ready
task_create_kernel_status:
0x00009C6A       LI R1 0x120
task_create_status_ready:
0x00009C72       PUSH R1            ; sstatus

0x00009C76       LI R1 0
0x00009C7E       PUSH R1            ; scause
0x00009C82       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x00009C86       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x00009C8A   STW R1 [R10 + TASK_KSP]

0x00009C8E       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x00009C92   LI R1 WAIT_NONE
0x00009C9A   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x00009C9E   LI R1 RESUME_TRAP
0x00009CA6   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x00009CAA       BL page_alloc
0x00009CB2       CMP R1 0
0x00009CB6       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x00009CBE       MOV R12 R1

0x00009CC2       LI  R3 PAGE_SIZE
0x00009CCA       MOV R1 R12
0x00009CCE       BL  mem_zero

    ; stdin
0x00009CD6       LI  R2 file_stdin
0x00009CDE       STW R2 [R12 + 0]

    ; stdout
0x00009CE2       LI  R2 file_stdout
0x00009CEA       STW R2 [R12 + 4]

    ; stderr
0x00009CEE       LI  R2 file_stderr
0x00009CF6       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x00009CFA   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x00009CFE       BL page_alloc
0x00009D06       CMP R1 0
0x00009D0A       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x00009D12   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x00009D16       BL page_alloc
0x00009D1E       CMP R1 0
0x00009D22       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x00009D2A   STW R1 [R10 + TASK_KBUF_RD_PTR]

    ; ----------------------------------
    ; data page - for user buffers and heap
    ; ----------------------------------

0x00009D2E       BL page_alloc
0x00009D36       CMP R1 0
0x00009D3A       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x00009D42   STW R1 [R10 + TASK_DATA_PAGE]

0x00009D46       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x00009D4A   LDW R1 [R10 + TASK_PTBR]
0x00009D4E       LI  R2 USER_DATA_VA
0x00009D56       MOV R3 R12
0x00009D5A       LI  R4 USER_RW
0x00009D62       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; initialize code page pointer to zero until execve or static code assignment
    ; This means the task currently has no execve-loaded program image.
    ; When execve runs, TASK_CODE_PAGE will be updated to point to the
    ; physical page currently mapped at USER_CODE_VA.
0x00009D6A       LI R1 0
; macro: TASK_SET_CODE_PAGE R10, R1
0x00009D72   STW R1 [R10 + TASK_CODE_PAGE]

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x00009D76   LI R1 TASK_READY
0x00009D7E   STW R1 [R10 + TASK_STATE]

    ; Initialize program break pointer to HEAP_START in User_Data_VA
0x00009D82       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x00009D8A   STW R1 [R10 + TASK_BREAK]

    ; Initialize parent PID to 0 by default
0x00009D8E       LI R1 0
; macro: TASK_SET_PPID R10, R1
0x00009D96   STW R1 [R10 + TASK_PPID]

0x00009D9A       MOV R1 R10                              ; return created task pointer

0x00009D9E       POP LR
0x00009DA2       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x00009DA6       CMP R10 0
0x00009DAA       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x00009DB2   LDW R1 [R10 + TASK_PTBR]
0x00009DB6       CMP R1 0
0x00009DBA       BEQ task_create_free_ustack
0x00009DC2       BL page_free

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00009DCA   LDW R1 [R10 + TASK_USTACK_PAGE]
0x00009DCE       CMP R1 0
0x00009DD2       BEQ task_create_free_kstack
0x00009DDA       BL page_free

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x00009DE2   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x00009DE6       CMP R1 0
0x00009DEA       BEQ task_create_free_fd
0x00009DF2       BL page_free

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00009DFA   LDW R1 [R10 + TASK_FD_TABLE]
0x00009DFE       CMP R1 0
0x00009E02       BEQ task_create_free_kwr
0x00009E0A       BL page_free

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x00009E12   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x00009E16       CMP R1 0
0x00009E1A       BEQ task_create_free_krd
0x00009E22       BL page_free

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x00009E2A   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x00009E2E       CMP R1 0
0x00009E32       BEQ task_create_free_data
0x00009E3A       BL page_free

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x00009E42   LDW R1 [R10 + TASK_DATA_PAGE]
0x00009E46       CMP R1 0
0x00009E4A       BEQ task_create_clear_slot
0x00009E52       BL page_free

task_create_clear_slot:
0x00009E5A       MOV R1 R10
0x00009E5E       LI R3 TASK_SIZE
0x00009E66       BL mem_zero

task_create_fail_return:
0x00009E6E       LI R1 0

0x00009E76       POP LR
0x00009E7A       RET

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
0x00009E7E       MOV  R8 SP ;save sp to point to task trapframe!
0x00009E82       PUSH LR

    ; Get the current task slot and parent task pointer.
; macro: GET_CURR_TASK_IDX R6
0x00009E86   LI R1 CURRENT_TASK
0x00009E8E   LDW R6 [R1]
; macro: GET_TASK_PTR R7, R6           ; R7 = parent task*
0x00009E92   LI R1 TASK_SIZE
0x00009E9A   MUL R3 R6 R1
0x00009E9E   LI R7 tasks
0x00009EA6   ADD R7 R7 R3

    ; Allocate a fresh child task slot.
0x00009EAA       BL task_alloc
0x00009EB2       CMP R1 0
0x00009EB6       BEQ clone_fail
0x00009EBE       MOV R10 R1                    ; R10 = child task*

    ; Clear the new child task slot before use.
0x00009EC2       MOV R1 R10
0x00009EC6       LI R3 TASK_SIZE
0x00009ECE       BL mem_zero

    ; Assign a new PID from the dynamic pid counter.
0x00009ED6       LI R1 task_count
0x00009EDE       LDW R2 [R1]

; macro: TASK_SET_PID R10, R2        ; set new child task Pid to child task (current task_count value)
0x00009EE2   STW R2 [R10 + TASK_PID]
0x00009EE6       ADD R2 R2 1
0x00009EEA       STW R2 [R1]                 ; update task_count as we created a new task

    ; Set child parent PID to the current task's PID.
; macro: TASK_GET_PID R2, R7
0x00009EEE   LDW R2 [R7 + TASK_PID]
; macro: TASK_SET_PPID R10, R2       ; pid - new, ppid - parent task's pid (new task)
0x00009EF2   STW R2 [R10 + TASK_PPID]

    ; Copy the current task's program break.
; macro: TASK_GET_BREAK R2, R7
0x00009EF6   LDW R2 [R7 + TASK_BREAK]
; macro: TASK_SET_BREAK R10, R2
0x00009EFA   STW R2 [R10 + TASK_BREAK]

    ; Copy current task PC for debugging/metadata.
; macro: TASK_GET_PC R2, R7
0x00009EFE   LDW R2 [R7 + TASK_PC]
; macro: TASK_SET_PC R10, R2
0x00009F02   STW R2 [R10 + TASK_PC]

    ; Allocate and initialize a fresh page table for the child.
0x00009F06       BL page_alloc
0x00009F0E       CMP R1 0
0x00009F12       BEQ clone_fail
0x00009F1A       MOV R11 R1
; macro: TASK_SET_PTBR R10, R11
0x00009F1E   STW R11 [R10 + TASK_PTBR]

    ; Clone the parent's entire page table into the child.
; macro: TASK_GET_PTBR R1, R7
0x00009F22   LDW R1 [R7 + TASK_PTBR]
0x00009F26       MOV R2 R11
0x00009F2A       LI R3 PAGE_SIZE
0x00009F32       BL page_copy

    ; Preserve the current exec code page pointer if the parent uses execve.
; macro: TASK_GET_CODE_PAGE R2, R7
0x00009F3A   LDW R2 [R7 + TASK_CODE_PAGE]
; macro: TASK_SET_CODE_PAGE R10, R2
0x00009F3E   STW R2 [R10 + TASK_CODE_PAGE]

    ; The child has inherited the parent's kernel and code mappings.
    ; We will override the user stack and data mappings below.
    ; Allocate and clone the user stack page.
0x00009F42       BL page_alloc
0x00009F4A       CMP R1 0
0x00009F4E       BEQ clone_fail
0x00009F56       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12   ; set new page as child user stack page
0x00009F5A   STW R12 [R10 + TASK_USTACK_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x00009F5E   LDW R1 [R10 + TASK_PTBR]
0x00009F62       LI R2 USER_STACK_VA
0x00009F6A       MOV R3 R12
0x00009F6E       LI R4 USER_RW
0x00009F76       BL map_page             ; map user stack page to child ptbr

; macro: TASK_GET_USTACK_PAGE R1, R7
0x00009F7E   LDW R1 [R7 + TASK_USTACK_PAGE]
0x00009F82       MOV R2 R12
0x00009F86       LI R3 PAGE_SIZE
0x00009F8E       BL page_copy            ; copy parent user stack page -> child user stack page

    ; Allocate and clone the user data page.
0x00009F96       BL page_alloc
0x00009F9E       CMP R1 0
0x00009FA2       BEQ clone_fail
0x00009FAA       MOV R12 R1
; macro: TASK_SET_DATA_PAGE R10, R12     ; set new page as child user data page
0x00009FAE   STW R12 [R10 + TASK_DATA_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x00009FB2   LDW R1 [R10 + TASK_PTBR]
0x00009FB6       LI R2 USER_DATA_VA
0x00009FBE       MOV R3 R12
0x00009FC2       LI R4 USER_RW
0x00009FCA       BL map_page                     ; map user data page to child ptbr

; macro: TASK_GET_DATA_PAGE R1, R7
0x00009FD2   LDW R1 [R7 + TASK_DATA_PAGE]
0x00009FD6       MOV R2 R12
0x00009FDA       LI R3 PAGE_SIZE
0x00009FE2       BL page_copy                    ; copy parent user data page -> child user data page

    ; Clone the fd table and honor open file refcounts.
0x00009FEA       BL page_alloc
0x00009FF2       CMP R1 0
0x00009FF6       BEQ clone_fail

0x00009FFE       MOV R12 R1

; macro: TASK_SET_FD_TABLE R10, R12       ; set new page as child fd table page
0x0000A002   STW R12 [R10 + TASK_FD_TABLE]
0x0000A006       LI R3 PAGE_SIZE
0x0000A00E       MOV R1 R12
0x0000A012       BL mem_zero                     ; clear the child fd table page just in case

; macro: TASK_GET_FD_TABLE R1, R7         ; R1 - parent fd table page
0x0000A01A   LDW R1 [R7 + TASK_FD_TABLE]
0x0000A01E       CMP R1 0
0x0000A022       BEQ clone_fd_done                ; if parent has no fd table, skip fd cloning

    ; parent → child copy FIRST
0x0000A02A       MOV R1 R1        ; parent fd page
0x0000A02E       MOV R2 R12       ; child fd page
0x0000A032       LI R3 PAGE_SIZE
0x0000A03A       BL page_copy

0x0000A042       LI R4 3                      ; fd index loop + 3 stdin/out/err refcount=1, so start at 3

clone_fd_loop:
0x0000A04A       CMP R4 MAX_FDS
0x0000A04E       BGE clone_fd_done

0x0000A056       SHL R5 R4 2                 ; multiply fd index by 4 to get byte offset
0x0000A05A       ADD R6 R12 R5               ; R6 = &child_fd_table[i]

0x0000A05E       LDW R7 [R6]                 ; R7 = file* from child fd table
0x0000A062       CMP R7 0
0x0000A066       BEQ clone_fd_next           ; if fd slot is empty, skip to next

0x0000A06E       MOV R1 R7                   ; IMPORTANT: isolate argument
0x0000A072       BL file_get                 ; increment refcount of the file* in child fd table

clone_fd_next:
0x0000A07A       ADD R4 R4 1
0x0000A07E       B clone_fd_loop

clone_fd_done:
    ; Allocate fresh kernel buffers for the child.
0x0000A086       BL page_alloc
0x0000A08E       CMP R1 0
0x0000A092       BEQ clone_fail

; macro: TASK_SET_KBUF_WR R10, R1        ; set new page as child kernel write buffer
0x0000A09A   STW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000A09E       LI R3 PAGE_SIZE
0x0000A0A6       BL mem_zero                     ; zero out the child kernel write buffer

0x0000A0AE       BL page_alloc
0x0000A0B6       CMP R1 0
0x0000A0BA       BEQ clone_fail
; macro: TASK_SET_KBUF_RD R10, R1        ; set new page as child kernel read buffer
0x0000A0C2   STW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000A0C6       LI R3 PAGE_SIZE
0x0000A0CE       BL mem_zero                     ; zero out the child kernel read buffer

    ; Allocate and initialize the child's kernel stack.
0x0000A0D6       BL page_alloc
0x0000A0DE       CMP R1 0
0x0000A0E2       BEQ clone_fail
0x0000A0EA       MOV R12 R1
; macro: TASK_SET_KSTACK_PAGE R10, R12   ; set new page as child kernel stack page
0x0000A0EE   STW R12 [R10 + TASK_KSTACK_PAGE]
0x0000A0F2       LI R3 PAGE_SIZE
0x0000A0FA       ADD R12 R12 R3                  ; R12 = child kernel stack top


    ; Copy the current kernel trapframe into the child's new kernel stack.
    ; The trapframe is at SP + 24 (after 6 pushes of 4 bytes each)
    ; Child trapframe goes at the top of child's stack (R12 - 80)
0x0000A0FE       MOV R1 R8                     ; R1 = parent trapframe BASE saved in the beginiig of func
0x0000A102       MOV R6 R12
0x0000A106       LI R5 80                    ; trapframe size in bytes
0x0000A10E       SUB R6 R6 R5               ; R6 = child trapframe base inside new kernel stack
0x0000A112       MOV R2 R6
0x0000A116       LI R3 80
0x0000A11E       BL page_copy                ; so we copy 80 bytes from SP to R12-80 (child trapframe base)

    ; Return 0 in the child syscall result register.
0x0000A126       LI R4 0
0x0000A12E       STW R4 [R6 + TF_R1]


    ; Preserve the user SP for later trap/schedule bookkeeping.
    ; User SP is already in the trapframe we copied
    ; But we also need to set it in the child's task struct
0x0000A132       LDW R4 [R6 + TF_USP]
; macro: TASK_SET_USP R10, R4
0x0000A136   STW R4 [R10 + TASK_USP]

    ; Save the child kernel trapframe pointer and make it runnable.
; macro: TASK_SET_KSP R10, R6                    ;R6 = child trapframe base inside new kernel stack
0x0000A13A   STW R6 [R10 + TASK_KSP]
; macro: TASK_SET_RESUME R10, RESUME_TRAP
0x0000A13E   LI R1 RESUME_TRAP
0x0000A146   STW R1 [R10 + TASK_RESUME]
; macro: TASK_SET_WAIT R10, WAIT_NONE
0x0000A14A   LI R1 WAIT_NONE
0x0000A152   STW R1 [R10 + TASK_WAIT]
; macro: TASK_SET_STATE R10, TASK_READY
0x0000A156   LI R1 TASK_READY
0x0000A15E   STW R1 [R10 + TASK_STATE]

0x0000A162       MOV R1 R10          ; return child task pointer

0x0000A166       POP LR
0x0000A16A       RET

clone_fail:
0x0000A16E       CMP R10 0
0x0000A172       BEQ clone_fail_return
0x0000A17A       MOV R1 R10
0x0000A17E       BL task_destroy
clone_fail_return:
0x0000A186       LI R1 0
0x0000A18E       POP LR
0x0000A192       RET

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

0x0000A196       PUSH LR
0x0000A19A       push R12 ; preserve R12 which we use for temporary storage in this function
0x0000A19E       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x0000A1A2   LDW R2 [R1 + TASK_PTBR]
0x0000A1A6       CMP R2 0
0x0000A1AA       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x0000A1B2       MOV R1 R2
0x0000A1B6       BL page_free        ; free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x0000A1BE   LDW R2 [R12 + TASK_USTACK_PAGE]
0x0000A1C2       CMP R2 0
0x0000A1C6       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000A1CE       MOV R1 R2
0x0000A1D2       BL page_free

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x0000A1DA   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x0000A1DE       CMP R2 0
0x0000A1E2       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000A1EA       MOV R1 R2
0x0000A1EE       BL page_free

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x0000A1F6   LDW R2 [R12 + TASK_FD_TABLE]
0x0000A1FA       CMP R2 0
0x0000A1FE       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000A206       MOV R1 R2
0x0000A20A       BL page_free

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x0000A212   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x0000A216       CMP R2 0
0x0000A21A       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x0000A222       MOV R1 R2
0x0000A226       BL page_free

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x0000A22E   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x0000A232       CMP R2 0
0x0000A236       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x0000A23E       MOV R1 R2
0x0000A242       BL page_free

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x0000A24A   LDW R2 [R12 + TASK_DATA_PAGE]
0x0000A24E       CMP R2 0
0x0000A252       BEQ td_skip_code
0x0000A25A       MOV R1 R2
0x0000A25E       BL page_free

td_skip_code:

; macro: TASK_GET_CODE_PAGE R2, R12
0x0000A266   LDW R2 [R12 + TASK_CODE_PAGE]
0x0000A26A       CMP R2 0
0x0000A26E       BEQ td_done
0x0000A276       MOV R1 R2
0x0000A27A       BL page_free

td_done:

0x0000A282       MOV R1 R12
0x0000A286       LI  R3 TASK_SIZE
0x0000A28E       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x0000A296       POP R12         ; restore R12
0x0000A29A       POP LR
0x0000A29E       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x0000A2A2       PUSH LR
0x0000A2A6       PUSH R8
0x0000A2AA       PUSH R9
0x0000A2AE       PUSH R10
0x0000A2B2       PUSH R11
0x0000A2B6       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x0000A2BA   LDW R4 [R1 + TASK_FD_TABLE]
0x0000A2BE       MOV R12 R4

0x0000A2C2       LI R5 3              ; skip stdin/out/err
0x0000A2CA       MOV R11 R5

fd_loop:

0x0000A2CE       CMP R11 MAX_FDS
0x0000A2D2       BGE fd_done         ; if we processed all fd slots, we are done

0x0000A2DA       SHL R6 R11 2
0x0000A2DE       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x0000A2E2       LDW R8 [R10]
0x0000A2E6       CMP R8 0
0x0000A2EA       BEQ fd_next         ; if fd slot is empty, skip to next

0x0000A2F2       MOV R1 R8
0x0000A2F6       BL file_free
0x0000A2FE       LI R9 0
0x0000A306       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x0000A30A       ADD R11 R11 1
0x0000A30E       B fd_loop

fd_done:
0x0000A316       POP R12
0x0000A31A       POP R11
0x0000A31E       POP R10
0x0000A322       POP R9
0x0000A326       POP R8
0x0000A32A       POP LR
0x0000A32E       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x0000A332       PUSH LR
0x0000A336       PUSH R8
0x0000A33A       PUSH R9
0x0000A33E       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x0000A342   LI R1 CURRENT_TASK
0x0000A34A   LDW R10 [R1]
0x0000A34E       LI R8 0

task_reap_loop:
0x0000A356       CMP R8 MAX_TASKS
0x0000A35A       BGE task_reap_done

0x0000A362       CMP R8 R10
0x0000A366       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x0000A36E   LI R1 TASK_SIZE
0x0000A376   MUL R3 R8 R1
0x0000A37A   LI R9 tasks
0x0000A382   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x0000A386   LDW R1 [R9 + TASK_STATE]
0x0000A38A       CMP R1 TASK_ZOMBIE
0x0000A38E       BNE task_reap_next

0x0000A396       PUSH R8
0x0000A39A       MOV R1 R9
0x0000A39E       BL task_destroy
0x0000A3A6       POP R8

task_reap_next:
0x0000A3AA       ADD R8 R8 1
0x0000A3AE       B task_reap_loop

task_reap_done:
0x0000A3B6       POP R10
0x0000A3BA       POP R9
0x0000A3BE       POP R8
0x0000A3C2       POP LR
0x0000A3C6       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x0000A3CA       LI R1 tasks
0x0000A3D2       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x0000A3DA   LDW R3 [R1 + TASK_STATE]

0x0000A3DE       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000A3E2       BEQ task_alloc_found

0x0000A3EA       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x0000A3EE       SUB R2 R2 1
0x0000A3F2       BNE task_alloc_loop

; no free tasks slots

0x0000A3FA       LI R1 0
0x0000A402       RET

task_alloc_found:                           ;R1 points to free task slot

0x0000A406       RET


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
0x0000A412       PUSH R2

0x0000A416       LI R2 0
0x0000A41E       STW R2 [R1 + MUTEX_OWNER]      ; owner = NULL
0x0000A422       STW R2 [R1 + MUTEX_WAITQ]      ; waitq = 0 (empty)

0x0000A426       POP R2
0x0000A42A       RET

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

0x0000A42E       PUSH LR
0x0000A432       PUSH R8
0x0000A436       PUSH R9
0x0000A43A       PUSH R10

0x0000A43E       MOV R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000A442   LI R1 CURRENT_TASK
0x0000A44A   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000A44E   LI R1 TASK_SIZE
0x0000A456   MUL R3 R9 R1
0x0000A45A   LI R9 tasks
0x0000A462   ADD R9 R9 R3

mutex_lock_retry:
    ; Check if mutex is already locked
0x0000A466       LDW R10 [R8 + MUTEX_OWNER]
0x0000A46A       CMP R10 0
0x0000A46E       BEQ mutex_lock_acquire      ; if unlocked, acquire it

    ; this Mutex is locked by someone else - block
    ; Add current task to mutex wait queue
0x0000A476       MOV R1 R8
0x0000A47A       ADD R1 R1 MUTEX_WAITQ

0x0000A47E       LI R2 WAIT_MUTEX
0x0000A486       LI R3 TASK_WAIT_MUTEX
0x0000A48E       BL waitq_prepare_sleep

    ; Re-check if mutex became available while preparing sleep
0x0000A496       LDW R10 [R8 + MUTEX_OWNER]
0x0000A49A       CMP R10 0
0x0000A49E       BEQ mutex_lock_wake

    ; Still locked - go to sleep
0x0000A4A6       BL waitq_sleep_current

    ; Woken up - try to acquire again
0x0000A4AE       B mutex_lock_retry

mutex_lock_wake:
    ; Mutex became available, cancel sleep and acquire
0x0000A4B6       MOV R1 R8
0x0000A4BA       ADD R1 R1 MUTEX_WAITQ
0x0000A4BE       BL waitq_cancel_sleep_current

0x0000A4C6       B mutex_lock_retry

mutex_lock_acquire:
    ; Disable interrupts to prevent race conditions
0x0000A4CE       DISABLEINT

    ; Double-check it's still unlocked
0x0000A4D2       LDW R10 [R8 + MUTEX_OWNER]
0x0000A4D6       CMP R10 0
0x0000A4DA       BNE mutex_lock_race

    ; Set owner to current task
0x0000A4E2       STW R9 [R8 + MUTEX_OWNER]

    ; Re-enable interrupts
0x0000A4E6       ENABLEINT

0x0000A4EA       POP R10
0x0000A4EE       POP R9
0x0000A4F2       POP R8
0x0000A4F6       POP LR
0x0000A4FA       RET

mutex_lock_race:
    ; Someone else acquired it while interrupts were disabled
0x0000A4FE       ENABLEINT
0x0000A502       B mutex_lock_retry


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
0x0000A50A       PUSH LR
0x0000A50E       PUSH R8
0x0000A512       PUSH R9
0x0000A516       PUSH R10

0x0000A51A       MOV  R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000A51E   LI R1 CURRENT_TASK
0x0000A526   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000A52A   LI R1 TASK_SIZE
0x0000A532   MUL R3 R9 R1
0x0000A536   LI R9 tasks
0x0000A53E   ADD R9 R9 R3

    ; Verify ownership
0x0000A542       LDW  R10 [R8 + MUTEX_OWNER]
0x0000A546       CMP  R10 R9
0x0000A54A       BNE  mutex_unlock_error     ; Not owner - error!

    ; Release the mutex
0x0000A552       LI  R10 0
0x0000A55A       STW R10 [R8 + MUTEX_OWNER]

    ; Wake one waiting task (if someone is waiting)
    ; waky next one (of any waiting)
0x0000A55E       MOV R1 R8
0x0000A562       ADD R1 R1 MUTEX_WAITQ
0x0000A566       BL waitq_wake_one

mutex_unlock_done:
0x0000A56E       POP R10
0x0000A572       POP R9
0x0000A576       POP R8
0x0000A57A       POP LR
0x0000A57E       RET

mutex_unlock_error:
    ; Not owner - ignore (or panic)
0x0000A582       POP R10
0x0000A586       POP R9
0x0000A58A       POP R8
0x0000A58E       POP LR
0x0000A592       RET

; ================================================================
; waitq_wake_one - Wake exactly one task from the wait queue
; R1 = wait queue pointer
; ================================================================
waitq_wake_one:
0x0000A596       PUSH LR
0x0000A59A       PUSH R8
0x0000A59E       PUSH R9
0x0000A5A2       PUSH R10
0x0000A5A6       PUSH R11

0x0000A5AA       MOV R8 R1                  ; wait queue pointer
0x0000A5AE       LDW R9 [R8 + WQ_MASK]      ; current wait queue mask

0x0000A5B2       CMP R9 0
0x0000A5B6       BEQ waitq_wake_one_done    ; No waiters

    ; Find the first waiting task
0x0000A5BE       LI R10 0                   ; task index

waitq_wake_one_find:
0x0000A5C6       CMP R10 MAX_TASKS
0x0000A5CA       BGE waitq_wake_one_done

0x0000A5D2       LI R11 1
0x0000A5DA       SHL R11 R11 R10            ; bit for this task
0x0000A5DE       AND R2 R9 R11
0x0000A5E2       CMP R2 0
0x0000A5E6       BNE waitq_wake_one_found

0x0000A5EE       ADD R10 R10 1
0x0000A5F2       B waitq_wake_one_find

waitq_wake_one_found:
    ; Clear this task's bit from the wait queue
0x0000A5FA       NOT R11 R11
0x0000A5FE       AND R9 R9 R11
0x0000A602       STW R9 [R8 + WQ_MASK]

    ; Wake this task
; macro: GET_TASK_PTR R5, R10
0x0000A606   LI R1 TASK_SIZE
0x0000A60E   MUL R3 R10 R1
0x0000A612   LI R5 tasks
0x0000A61A   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000A61E   LI R1 TASK_READY
0x0000A626   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000A62A   LI R1 WAIT_NONE
0x0000A632   STW R1 [R5 + TASK_WAIT]

waitq_wake_one_done:
0x0000A636       POP R11
0x0000A63A       POP R10
0x0000A63E       POP R9
0x0000A642       POP R8
0x0000A646       POP LR
0x0000A64A       RET

; ================================================================
; CONSOLE MUTEX WRAPPER FUNCTIONS
; ================================================================

console_lock:
0x0000A64E       PUSH LR
0x0000A652       LI R1 console_mutex
0x0000A65A       BL mutex_lock
0x0000A662       POP LR
0x0000A666       RET

console_unlock:
0x0000A66A       PUSH LR
0x0000A66E       LI R1 console_mutex
0x0000A676       BL mutex_unlock
0x0000A67E       POP LR
0x0000A682       RET



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
0x0001B028       BEQ child_process_c
0x0001B030       BLT fork_error_c
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
0x0001B09C       BLT wait_error_c

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

wait_error_c:
0x0001B0E4       LI R1 STDOUT_FD
0x0001B0EC       LI R2 wait_error_msg_с
0x0001B0F4       LI R3 14
0x0001B0FC       SVC SYS_WRITE
0x0001B100       B exit_failure

child_process_c:
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

    ;LI R1 ls_path
    ;LI R2 ls_argv
    ;LI R3 0

0x0001B13C       SVC SYS_EXECVE
    ; returns if error with execve

0x0001B140       LI R1 STDOUT_FD
0x0001B148       LI R2 exec_failed_msg_c
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

fork_error_c:
0x0001B19C       LI R1 STDOUT_FD
0x0001B1A4       LI R2 fork_error_msg_c
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

wait_error_msg_с:
    .ASCIIZ "WAITPID FAIL\r\n"

child_start_msg:
    .ASCIIZ "CHILD START\r\n"

child_end_msg:
    .ASCIIZ "CHILD DONE\r\n"

sleep_error_msg:
    .ASCIIZ "SLEEP FAIL\r\n"
exec_failed_msg_c:
    .ASCIIZ "EXECV FAIL\r\n"
fork_error_msg_c:
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
    .WORD 0
    .WORD 0

   ; .WORD cat_path
   ; .WORD cat_arg1
   ; .WORD cat_arg2
    .WORD 0

;==========
;ls
;==========
ls_path:
    .ASCIIZ "bin/ls1"

ls_arg0:
    .ASCIIZ "ls1"

ls_arg1:
    .ASCIIZ "etc/"

ls_arg2:
    .ASCIIZ "lib/"

ls_argv:
    .WORD ls_path
    .WORD ls_arg1
    .WORD ls_arg2
    .WORD 0


; ================================================================
; task_init – PID 1 initial process
; ================================================================
; This is the first user‑space process created by the kernel.
; It acts as a simple init:
;   - fork() a child
;   - child execs /bin/sh (the interactive shell)
;   - parent waits for the shell to exit, then restarts it
; ================================================================

.org 0x1C000
TASK_INIT_START:

    ; Optional: print a startup message
0x0001C000       LI R1 STDOUT_FD
0x0001C008       LI R2 init_start_msg
0x0001C010       LI R3 12
0x0001C018       SVC SYS_WRITE

init_loop:
    ; ------------------------------------------------------------
    ; Fork a new child
    ; ------------------------------------------------------------
0x0001C01C       SVC SYS_FORK
0x0001C020       CMP R1 0
0x0001C024       BEQ child_process
0x0001C02C       BLT fork_error

    ; ------------------------------------------------------------
    ; Parent process: wait for the child to terminate
    ; ------------------------------------------------------------
0x0001C034       MOV R5 R1                ; Save child PID (not strictly needed)
0x0001C038       LI R1 -1                 ; Wait for any child
0x0001C040       LI R2 0                  ; No status pointer needed
0x0001C048       SVC SYS_WAITPID
0x0001C04C       CMP R1 0
0x0001C050       BLT wait_error

    ; Child exited normally – restart the shell
0x0001C058       LI R1 STDOUT_FD
0x0001C060       LI R2 restart_msg
0x0001C068       LI R3 14
0x0001C070       SVC SYS_WRITE

0x0001C074       B init_loop              ; Forever

    ; ------------------------------------------------------------
    ; Child process: replace itself with /bin/sh
    ; ------------------------------------------------------------
child_process:
0x0001C07C       LI R1 sh_path
0x0001C084       LI R2 sh_argv
0x0001C08C       LI R3 0                  ; No environment
0x0001C094       SVC SYS_EXECVE

    ; If execve returns, it failed
0x0001C098       LI R1 STDOUT_FD
0x0001C0A0       LI R2 exec_failed_msg
0x0001C0A8       LI R3 13
0x0001C0B0       SVC SYS_WRITE

0x0001C0B4       LI R1 1                  ; Exit with error
0x0001C0BC       SVC SYS_EXIT

    ; ------------------------------------------------------------
    ; Error handlers (simple: print and halt)
    ; ------------------------------------------------------------
fork_error:
0x0001C0C0       LI R1 STDOUT_FD
0x0001C0C8       LI R2 fork_error_msg
0x0001C0D0       LI R3 11
0x0001C0D8       SVC SYS_WRITE
0x0001C0DC       LI R1 1
0x0001C0E4       SVC SYS_EXIT

wait_error:
0x0001C0E8       LI R1 STDOUT_FD
0x0001C0F0       LI R2 wait_error_msg
0x0001C0F8       LI R3 14
0x0001C100       SVC SYS_WRITE
    ; Continue looping even on wait error (maybe child vanished)
0x0001C104       B init_loop

    ; ------------------------------------------------------------
    ; Data section
    ; ------------------------------------------------------------
init_start_msg:
    .ASCIIZ "INIT START\r\n"

restart_msg:
    .ASCIIZ "RESTART SHELL\r\n"

exec_failed_msg:
    .ASCIIZ "EXECVE FAIL\r\n"

fork_error_msg:
    .ASCIIZ "FORK FAIL\r\n"

wait_error_msg:
    .ASCIIZ "WAITPID ERR\r\n"

; Path and argument vector for /bin/sh
; Assumes root filesystem has /bin/sh
sh_path:
    .ASCIIZ "bin/sh"
; argv[0] is the program name
sh_arg0:
    .ASCIIZ "sh"
; argv[0] = "bin/sh"
; argv[1] = NULL (terminator)
sh_argv:
    .WORD sh_path
    .WORD 0

.ORG 0xA0000
tarfs_start:
; bin/
    .ASCIIZ "bin/"
    .SPACE 119
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; etc/
    .ASCIIZ "etc/"
    .SPACE 119
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; lib/
    .ASCIIZ "lib/"
    .SPACE 119
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; bin/cat, 3515 bytes
    .ASCIIZ "bin/cat"
    .SPACE 116
    .ASCIIZ "00000006673"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (3515 bytes, padded to 3584)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x00043BF2, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x56000002, 0x11010000, 0x40010000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430B4, 0x01890100, 0x0F010000, 0x00000001
    .WORD 0x01820800, 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x0F080000, 0x00043BF0, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000
    .WORD 0x00000001, 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x000430E8, 0x02090981
    .WORD 0x05000000, 0x000430CC, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100
    .WORD 0x07000000, 0x00043154, 0x040A0080, 0x06000000, 0x00043144, 0x02080881, 0x02090981, 0x05000000
    .WORD 0x00043114, 0x0F010000, 0x00000001, 0x05000000, 0x0004315C, 0x0F010000, 0x00000000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431B4, 0x20010900, 0x23010800
    .WORD 0x02080881, 0x02090981, 0x030A0A81, 0x05000000, 0x0004318C, 0x01810800, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x00043208, 0x23090800, 0x02080881, 0x030A0A81
    .WORD 0x05000000, 0x000431E8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x40040000, 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000
    .WORD 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000
    .WORD 0x40010000, 0x05000000, 0x00043264, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102
    .WORD 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043534, 0x0F020000, 0x0004326C
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043510
    .WORD 0x22030204, 0x04030500, 0x15000000, 0x0004351C, 0x02040481, 0x05000000, 0x000434CC, 0x0F030000
    .WORD 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435B4, 0x01810500, 0x400C0000, 0x04010080
    .WORD 0x12000000, 0x000435AC, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435AC, 0x0F020000
    .WORD 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000
    .WORD 0x00043590, 0x02040481, 0x05000000, 0x00043550, 0x25010200, 0x25050204, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x05000000, 0x000435B4, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x04010080, 0x06000000, 0x00043620, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043620
    .WORD 0x0F020000, 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100
    .WORD 0x06000000, 0x00043614, 0x02040481, 0x05000000, 0x000435D4, 0x0F030000, 0x00000000, 0x25030208
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x0004326C, 0x0F030000, 0x00000030, 0x04030080
    .WORD 0x06000000, 0x00043664, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000
    .WORD 0x0004363C, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00
    .WORD 0x10050000, 0x01870600, 0x040C0081, 0x07000000, 0x000436D8, 0x04090080, 0x15000000, 0x000436D8
    .WORD 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000
    .WORD 0x00043708, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800
    .WORD 0x05000000, 0x000437A8, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090
    .WORD 0x06000000, 0x00043734, 0x020707B0, 0x05000000, 0x00043754, 0x04070089, 0x14000000, 0x0004374C
    .WORD 0x020707B0, 0x05000000, 0x00043754, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481
    .WORD 0x01890500, 0x04090080, 0x07000000, 0x00043710, 0x03060681, 0x04040080, 0x06000000, 0x0004379C
    .WORD 0x20020600, 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043774, 0x0F020000
    .WORD 0x00000000, 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x0004366C
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x00000021, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000
    .WORD 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100
    .WORD 0x04020080, 0x06000000, 0x000438DC, 0x02010181, 0x02040481, 0x05000000, 0x000438B8, 0x01810300
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000
    .WORD 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x00043974, 0x10090000, 0x0F010000
    .WORD 0x00000008, 0x30000000, 0x000434AC, 0x11090000, 0x04010080, 0x06000000, 0x0004395C, 0x01880100
    .WORD 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x0004397C, 0x01810900
    .WORD 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x0004397C, 0x0F010000, 0x00000000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200
    .WORD 0x04080080, 0x06000000, 0x000439F4, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000
    .WORD 0x04010080, 0x06000000, 0x00043A04, 0x040100CC, 0x07000000, 0x000439F4, 0x22020804, 0x02020281
    .WORD 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A0C, 0x0F010000, 0xFFFFFFFF, 0x05000000
    .WORD 0x00043A0C, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043A58, 0x22010800, 0x40070000, 0x01810800
    .WORD 0x30000000, 0x000435BC, 0x0F010000, 0x00000000, 0x05000000, 0x00043A60, 0x0F010000, 0xFFFFFFFF
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043A98, 0x0F020000, 0x00000000
    .WORD 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080
    .WORD 0x06000000, 0x00043AB0, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x000438E8, 0x04010080, 0x06000000, 0x00043AF0, 0x01820100, 0x0F010000, 0x00000001
    .WORD 0x30000000, 0x00043A1C, 0x05000000, 0x00043AF8, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000
    .WORD 0x000438E8, 0x04010080, 0x06000000, 0x00043BC4, 0x01880100, 0x01810800, 0x01820900, 0x30000000
    .WORD 0x0004398C, 0x04010080, 0x06000000, 0x00043BA8, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000
    .WORD 0x00043BC4, 0x0201098C, 0x30000000, 0x0004303C, 0x22020908, 0x04020082, 0x07000000, 0x00043B90
    .WORD 0x0F010000, 0x00043BE0, 0x30000000, 0x0004307C, 0x0F010000, 0x00043BE4, 0x30000000, 0x0004307C
    .WORD 0x05000000, 0x00043B34, 0x01810800, 0x30000000, 0x00043A1C, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043BCC, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x0000002F, 0x0000000A, 0x31000000, 0x000A0020, 0x00000000, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000
    .WORD 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x3D6E1200, 0x00000004, 0x00010F0A
    .WORD 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x3D321500, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x00000F02, 0x00000000, 0x32303000, 0x01000004, 0x0080018B, 0x0000040B
    .WORD 0x3CE61200, 0x0B000004, 0x0C000181, 0x00000182, 0x01000F03, 0x00000000, 0x32283000, 0x01000004
    .WORD 0x00800187, 0x00000407, 0x3CCE1300, 0x00000004, 0x00010F01, 0x0C000000, 0x07000182, 0x00000183
    .WORD 0x32203000, 0x00000004, 0x3C860500, 0x0B000004, 0x00000181, 0x32383000, 0x0A810004, 0x0000020A
    .WORD 0x3C4A0500, 0x00000004, 0x3DA70F01, 0x00000004, 0x303C3000, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x303C3000, 0x00000004, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004
    .WORD 0x00010F06, 0x0A810000, 0x0000020A, 0x3C4A0500, 0x00020004, 0x00005600, 0x01000F02, 0x0D020000
    .WORD 0x0002020D, 0x06005600, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x00001107, 0x00001106, 0x0000110F, 0x00023100, 0x00005600, 0x3D920F01, 0x00000004, 0x303C3000
    .WORD 0x00000004, 0x00010F06, 0x00000000, 0x3D320500, 0x73750004, 0x3A656761, 0x74616320, 0x6C696620
    .WORD 0x2E2E2065, 0x63000A2E, 0x203A7461, 0x6E6E6163, 0x6F20746F, 0x206E6570, 0x00000A00, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/echo, 3218 bytes
    .ASCIIZ "bin/echo"
    .SPACE 115
    .ASCIIZ "00000006222"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (3218 bytes, padded to 3584)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x00043BF2, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x56000002, 0x11010000, 0x40010000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430B4, 0x01890100, 0x0F010000, 0x00000001
    .WORD 0x01820800, 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x0F080000, 0x00043BF0, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000
    .WORD 0x00000001, 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x000430E8, 0x02090981
    .WORD 0x05000000, 0x000430CC, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100
    .WORD 0x07000000, 0x00043154, 0x040A0080, 0x06000000, 0x00043144, 0x02080881, 0x02090981, 0x05000000
    .WORD 0x00043114, 0x0F010000, 0x00000001, 0x05000000, 0x0004315C, 0x0F010000, 0x00000000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431B4, 0x20010900, 0x23010800
    .WORD 0x02080881, 0x02090981, 0x030A0A81, 0x05000000, 0x0004318C, 0x01810800, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x00043208, 0x23090800, 0x02080881, 0x030A0A81
    .WORD 0x05000000, 0x000431E8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x40040000, 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000
    .WORD 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000
    .WORD 0x40010000, 0x05000000, 0x00043264, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102
    .WORD 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043534, 0x0F020000, 0x0004326C
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043510
    .WORD 0x22030204, 0x04030500, 0x15000000, 0x0004351C, 0x02040481, 0x05000000, 0x000434CC, 0x0F030000
    .WORD 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435B4, 0x01810500, 0x400C0000, 0x04010080
    .WORD 0x12000000, 0x000435AC, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435AC, 0x0F020000
    .WORD 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000
    .WORD 0x00043590, 0x02040481, 0x05000000, 0x00043550, 0x25010200, 0x25050204, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x05000000, 0x000435B4, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x04010080, 0x06000000, 0x00043620, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043620
    .WORD 0x0F020000, 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100
    .WORD 0x06000000, 0x00043614, 0x02040481, 0x05000000, 0x000435D4, 0x0F030000, 0x00000000, 0x25030208
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x0004326C, 0x0F030000, 0x00000030, 0x04030080
    .WORD 0x06000000, 0x00043664, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000
    .WORD 0x0004363C, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00
    .WORD 0x10050000, 0x01870600, 0x040C0081, 0x07000000, 0x000436D8, 0x04090080, 0x15000000, 0x000436D8
    .WORD 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000
    .WORD 0x00043708, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800
    .WORD 0x05000000, 0x000437A8, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090
    .WORD 0x06000000, 0x00043734, 0x020707B0, 0x05000000, 0x00043754, 0x04070089, 0x14000000, 0x0004374C
    .WORD 0x020707B0, 0x05000000, 0x00043754, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481
    .WORD 0x01890500, 0x04090080, 0x07000000, 0x00043710, 0x03060681, 0x04040080, 0x06000000, 0x0004379C
    .WORD 0x20020600, 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043774, 0x0F020000
    .WORD 0x00000000, 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x0004366C
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x00000021, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000
    .WORD 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100
    .WORD 0x04020080, 0x06000000, 0x000438DC, 0x02010181, 0x02040481, 0x05000000, 0x000438B8, 0x01810300
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000
    .WORD 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x00043974, 0x10090000, 0x0F010000
    .WORD 0x00000008, 0x30000000, 0x000434AC, 0x11090000, 0x04010080, 0x06000000, 0x0004395C, 0x01880100
    .WORD 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x0004397C, 0x01810900
    .WORD 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x0004397C, 0x0F010000, 0x00000000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200
    .WORD 0x04080080, 0x06000000, 0x000439F4, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000
    .WORD 0x04010080, 0x06000000, 0x00043A04, 0x040100CC, 0x07000000, 0x000439F4, 0x22020804, 0x02020281
    .WORD 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A0C, 0x0F010000, 0xFFFFFFFF, 0x05000000
    .WORD 0x00043A0C, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043A58, 0x22010800, 0x40070000, 0x01810800
    .WORD 0x30000000, 0x000435BC, 0x0F010000, 0x00000000, 0x05000000, 0x00043A60, 0x0F010000, 0xFFFFFFFF
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043A98, 0x0F020000, 0x00000000
    .WORD 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080
    .WORD 0x06000000, 0x00043AB0, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x000438E8, 0x04010080, 0x06000000, 0x00043AF0, 0x01820100, 0x0F010000, 0x00000001
    .WORD 0x30000000, 0x00043A1C, 0x05000000, 0x00043AF8, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000
    .WORD 0x000438E8, 0x04010080, 0x06000000, 0x00043BC4, 0x01880100, 0x01810800, 0x01820900, 0x30000000
    .WORD 0x0004398C, 0x04010080, 0x06000000, 0x00043BA8, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000
    .WORD 0x00043BC4, 0x0201098C, 0x30000000, 0x0004303C, 0x22020908, 0x04020082, 0x07000000, 0x00043B90
    .WORD 0x0F010000, 0x00043BE0, 0x30000000, 0x0004307C, 0x0F010000, 0x00043BE4, 0x30000000, 0x0004307C
    .WORD 0x05000000, 0x00043B34, 0x01810800, 0x30000000, 0x00043A1C, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043BCC, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x0000002F, 0x0000000A, 0x31000000, 0x000A0020, 0x00000000, 0x00020000, 0x00005600, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x02000188, 0x00000189, 0x00010F0A, 0x09000000, 0x0B84018B
    .WORD 0x0800020B, 0x0000040A, 0x3C761500, 0x0B000004, 0x00002201, 0x303C3000, 0x0A810004, 0x0B84020A
    .WORD 0x0800020B, 0x0000040A, 0x3C661500, 0x00000004, 0x3BEC0F01, 0x00000004, 0x303C3000, 0x00000004
    .WORD 0x3C220500, 0x00000004, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004, 0x00000F01, 0x00000000
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x00000000, 0x00000000, 0x00000000
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

; bin/ls, 3667 bytes
    .ASCIIZ "bin/ls"
    .SPACE 117
    .ASCIIZ "00000007123"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (3667 bytes, padded to 4096)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x00043BF2, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x56000002, 0x11010000, 0x40010000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430B4, 0x01890100, 0x0F010000, 0x00000001
    .WORD 0x01820800, 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x0F080000, 0x00043BF0, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000
    .WORD 0x00000001, 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x000430E8, 0x02090981
    .WORD 0x05000000, 0x000430CC, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100
    .WORD 0x07000000, 0x00043154, 0x040A0080, 0x06000000, 0x00043144, 0x02080881, 0x02090981, 0x05000000
    .WORD 0x00043114, 0x0F010000, 0x00000001, 0x05000000, 0x0004315C, 0x0F010000, 0x00000000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431B4, 0x20010900, 0x23010800
    .WORD 0x02080881, 0x02090981, 0x030A0A81, 0x05000000, 0x0004318C, 0x01810800, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x00043208, 0x23090800, 0x02080881, 0x030A0A81
    .WORD 0x05000000, 0x000431E8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x40040000, 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000
    .WORD 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000
    .WORD 0x40010000, 0x05000000, 0x00043264, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102
    .WORD 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043534, 0x0F020000, 0x0004326C
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043510
    .WORD 0x22030204, 0x04030500, 0x15000000, 0x0004351C, 0x02040481, 0x05000000, 0x000434CC, 0x0F030000
    .WORD 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435B4, 0x01810500, 0x400C0000, 0x04010080
    .WORD 0x12000000, 0x000435AC, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435AC, 0x0F020000
    .WORD 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000
    .WORD 0x00043590, 0x02040481, 0x05000000, 0x00043550, 0x25010200, 0x25050204, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x05000000, 0x000435B4, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x04010080, 0x06000000, 0x00043620, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043620
    .WORD 0x0F020000, 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100
    .WORD 0x06000000, 0x00043614, 0x02040481, 0x05000000, 0x000435D4, 0x0F030000, 0x00000000, 0x25030208
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x0004326C, 0x0F030000, 0x00000030, 0x04030080
    .WORD 0x06000000, 0x00043664, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000
    .WORD 0x0004363C, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00
    .WORD 0x10050000, 0x01870600, 0x040C0081, 0x07000000, 0x000436D8, 0x04090080, 0x15000000, 0x000436D8
    .WORD 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000
    .WORD 0x00043708, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800
    .WORD 0x05000000, 0x000437A8, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090
    .WORD 0x06000000, 0x00043734, 0x020707B0, 0x05000000, 0x00043754, 0x04070089, 0x14000000, 0x0004374C
    .WORD 0x020707B0, 0x05000000, 0x00043754, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481
    .WORD 0x01890500, 0x04090080, 0x07000000, 0x00043710, 0x03060681, 0x04040080, 0x06000000, 0x0004379C
    .WORD 0x20020600, 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043774, 0x0F020000
    .WORD 0x00000000, 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x0004366C
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x00000021, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000
    .WORD 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100
    .WORD 0x04020080, 0x06000000, 0x000438DC, 0x02010181, 0x02040481, 0x05000000, 0x000438B8, 0x01810300
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000
    .WORD 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x00043974, 0x10090000, 0x0F010000
    .WORD 0x00000008, 0x30000000, 0x000434AC, 0x11090000, 0x04010080, 0x06000000, 0x0004395C, 0x01880100
    .WORD 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x0004397C, 0x01810900
    .WORD 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x0004397C, 0x0F010000, 0x00000000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200
    .WORD 0x04080080, 0x06000000, 0x000439F4, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000
    .WORD 0x04010080, 0x06000000, 0x00043A04, 0x040100CC, 0x07000000, 0x000439F4, 0x22020804, 0x02020281
    .WORD 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A0C, 0x0F010000, 0xFFFFFFFF, 0x05000000
    .WORD 0x00043A0C, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043A58, 0x22010800, 0x40070000, 0x01810800
    .WORD 0x30000000, 0x000435BC, 0x0F010000, 0x00000000, 0x05000000, 0x00043A60, 0x0F010000, 0xFFFFFFFF
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043A98, 0x0F020000, 0x00000000
    .WORD 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080
    .WORD 0x06000000, 0x00043AB0, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x000438E8, 0x04010080, 0x06000000, 0x00043AF0, 0x01820100, 0x0F010000, 0x00000001
    .WORD 0x30000000, 0x00043A1C, 0x05000000, 0x00043AF8, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000
    .WORD 0x000438E8, 0x04010080, 0x06000000, 0x00043BC4, 0x01880100, 0x01810800, 0x01820900, 0x30000000
    .WORD 0x0004398C, 0x04010080, 0x06000000, 0x00043BA8, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000
    .WORD 0x00043BC4, 0x0201098C, 0x30000000, 0x0004303C, 0x22020908, 0x04020082, 0x07000000, 0x00043B90
    .WORD 0x0F010000, 0x00043BE0, 0x30000000, 0x0004307C, 0x0F010000, 0x00043BE4, 0x30000000, 0x0004307C
    .WORD 0x05000000, 0x00043B34, 0x01810800, 0x30000000, 0x00043A1C, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043BCC, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x0000002F, 0x0000000A, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001006, 0x00001007
    .WORD 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000, 0x0D00030D
    .WORD 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x3DF21200, 0x00000004, 0x00010F0A, 0x00000000
    .WORD 0x00000F06, 0x08000000, 0x0000040A, 0x3DBE1500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x00001001, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004, 0x3E3C0F01, 0x00000004
    .WORD 0x303C3000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x303C3000, 0x00000004
    .WORD 0x3E4C0F01, 0x00000004, 0x303C3000, 0x00000004, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004
    .WORD 0x00001101, 0x00000F02, 0x00000000, 0x32303000, 0x01000004, 0x0080018B, 0x0000040B, 0x3D721200
    .WORD 0x0B000004, 0x0C000181, 0x00000182, 0x004C0F03, 0x00000000, 0x32283000, 0x01000004, 0x00800187
    .WORD 0x00000407, 0x3D5A0600, 0x00CC0004, 0x00000407, 0x3D5A0700, 0x0C080004, 0x0C8C2005, 0x00000201
    .WORD 0x303C3000, 0x00820004, 0x00000405, 0x3D420700, 0x00000004, 0x3E510F01, 0x00000004, 0x303C3000
    .WORD 0x00000004, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004, 0x3CE20500, 0x0B000004, 0x00000181
    .WORD 0x32383000, 0x0A810004, 0x0000020A, 0x3C460500, 0x00000004, 0x3E2B0F01, 0x00000004, 0x303C3000
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x303C3000, 0x00000004, 0x3BEE0F01
    .WORD 0x00000004, 0x303C3000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x3C460500, 0x00000004
    .WORD 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x3E120F01, 0x00000004, 0x303C3000
    .WORD 0x00000004, 0x00010F06, 0x00000000, 0x3DBE0500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964
    .WORD 0x726F7463, 0x2E2E2079, 0x6C000A2E, 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D
    .WORD 0x65726944, 0x726F7463, 0x00203A79, 0x2D2D2D20, 0x00002F00, 0x00000000, 0x00000000, 0x00000000
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

; bin/ls1, 3657 bytes
    .ASCIIZ "bin/ls1"
    .SPACE 116
    .ASCIIZ "00000007111"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (3657 bytes, padded to 4096)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x00043BF2, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x56000002, 0x11010000, 0x40010000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430B4, 0x01890100, 0x0F010000, 0x00000001
    .WORD 0x01820800, 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x0F080000, 0x00043BF0, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000
    .WORD 0x00000001, 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x000430E8, 0x02090981
    .WORD 0x05000000, 0x000430CC, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100
    .WORD 0x07000000, 0x00043154, 0x040A0080, 0x06000000, 0x00043144, 0x02080881, 0x02090981, 0x05000000
    .WORD 0x00043114, 0x0F010000, 0x00000001, 0x05000000, 0x0004315C, 0x0F010000, 0x00000000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431B4, 0x20010900, 0x23010800
    .WORD 0x02080881, 0x02090981, 0x030A0A81, 0x05000000, 0x0004318C, 0x01810800, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x00043208, 0x23090800, 0x02080881, 0x030A0A81
    .WORD 0x05000000, 0x000431E8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x40040000, 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000
    .WORD 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000
    .WORD 0x40010000, 0x05000000, 0x00043264, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102
    .WORD 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043534, 0x0F020000, 0x0004326C
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043510
    .WORD 0x22030204, 0x04030500, 0x15000000, 0x0004351C, 0x02040481, 0x05000000, 0x000434CC, 0x0F030000
    .WORD 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435B4, 0x01810500, 0x400C0000, 0x04010080
    .WORD 0x12000000, 0x000435AC, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435AC, 0x0F020000
    .WORD 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000
    .WORD 0x00043590, 0x02040481, 0x05000000, 0x00043550, 0x25010200, 0x25050204, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x05000000, 0x000435B4, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x04010080, 0x06000000, 0x00043620, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043620
    .WORD 0x0F020000, 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100
    .WORD 0x06000000, 0x00043614, 0x02040481, 0x05000000, 0x000435D4, 0x0F030000, 0x00000000, 0x25030208
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x0004326C, 0x0F030000, 0x00000030, 0x04030080
    .WORD 0x06000000, 0x00043664, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000
    .WORD 0x0004363C, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00
    .WORD 0x10050000, 0x01870600, 0x040C0081, 0x07000000, 0x000436D8, 0x04090080, 0x15000000, 0x000436D8
    .WORD 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000
    .WORD 0x00043708, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800
    .WORD 0x05000000, 0x000437A8, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090
    .WORD 0x06000000, 0x00043734, 0x020707B0, 0x05000000, 0x00043754, 0x04070089, 0x14000000, 0x0004374C
    .WORD 0x020707B0, 0x05000000, 0x00043754, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481
    .WORD 0x01890500, 0x04090080, 0x07000000, 0x00043710, 0x03060681, 0x04040080, 0x06000000, 0x0004379C
    .WORD 0x20020600, 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043774, 0x0F020000
    .WORD 0x00000000, 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x0004366C
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x00000021, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000
    .WORD 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100
    .WORD 0x04020080, 0x06000000, 0x000438DC, 0x02010181, 0x02040481, 0x05000000, 0x000438B8, 0x01810300
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000
    .WORD 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x00043974, 0x10090000, 0x0F010000
    .WORD 0x00000008, 0x30000000, 0x000434AC, 0x11090000, 0x04010080, 0x06000000, 0x0004395C, 0x01880100
    .WORD 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x0004397C, 0x01810900
    .WORD 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x0004397C, 0x0F010000, 0x00000000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200
    .WORD 0x04080080, 0x06000000, 0x000439F4, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000
    .WORD 0x04010080, 0x06000000, 0x00043A04, 0x040100CC, 0x07000000, 0x000439F4, 0x22020804, 0x02020281
    .WORD 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A0C, 0x0F010000, 0xFFFFFFFF, 0x05000000
    .WORD 0x00043A0C, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043A58, 0x22010800, 0x40070000, 0x01810800
    .WORD 0x30000000, 0x000435BC, 0x0F010000, 0x00000000, 0x05000000, 0x00043A60, 0x0F010000, 0xFFFFFFFF
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043A98, 0x0F020000, 0x00000000
    .WORD 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080
    .WORD 0x06000000, 0x00043AB0, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x000438E8, 0x04010080, 0x06000000, 0x00043AF0, 0x01820100, 0x0F010000, 0x00000001
    .WORD 0x30000000, 0x00043A1C, 0x05000000, 0x00043AF8, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000
    .WORD 0x000438E8, 0x04010080, 0x06000000, 0x00043BC4, 0x01880100, 0x01810800, 0x01820900, 0x30000000
    .WORD 0x0004398C, 0x04010080, 0x06000000, 0x00043BA8, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000
    .WORD 0x00043BC4, 0x0201098C, 0x30000000, 0x0004303C, 0x22020908, 0x04020082, 0x07000000, 0x00043B90
    .WORD 0x0F010000, 0x00043BE0, 0x30000000, 0x0004307C, 0x0F010000, 0x00043BE4, 0x30000000, 0x0004307C
    .WORD 0x05000000, 0x00043B34, 0x01810800, 0x30000000, 0x00043A1C, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043BCC, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x0000002F, 0x0000000A, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001006, 0x00001007
    .WORD 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x004C0F03, 0x0D030000, 0x0D00030D
    .WORD 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x3DE61200, 0x00000004, 0x00010F0A, 0x00000000
    .WORD 0x00000F06, 0x08000000, 0x0000040A, 0x3DB21500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x00001001, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004, 0x3E300F01, 0x00000004
    .WORD 0x303C3000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x303C3000, 0x00000004
    .WORD 0x3E400F01, 0x00000004, 0x303C3000, 0x00000004, 0x3BEE0F01, 0x00000004, 0x303C3000, 0x00000004
    .WORD 0x00001101, 0x38E83000, 0x01000004, 0x0080018B, 0x0000040B, 0x3D660600, 0x0B000004, 0x0C000181
    .WORD 0x00000182, 0x398C3000, 0x00800004, 0x00000401, 0x3D4E0600, 0x00000004, 0xFFFF0F02, 0x0200FFFF
    .WORD 0x00000401, 0x3D4E0600, 0x0C080004, 0x0C8C2205, 0x00000201, 0x303C3000, 0x00820004, 0x00000405
    .WORD 0x3D360700, 0x00000004, 0x3E450F01, 0x00000004, 0x303C3000, 0x00000004, 0x3BEE0F01, 0x00000004
    .WORD 0x303C3000, 0x00000004, 0x3CDA0500, 0x0B000004, 0x00000181, 0x3A1C3000, 0x0A810004, 0x0000020A
    .WORD 0x3C460500, 0x00000004, 0x3E1F0F01, 0x00000004, 0x303C3000, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x303C3000, 0x00000004, 0x3E470F01, 0x00000004, 0x303C3000, 0x00000004
    .WORD 0x00010F06, 0x0A810000, 0x0000020A, 0x3C460500, 0x00000004, 0x004C0F03, 0x0D030000, 0x0600020D
    .WORD 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106
    .WORD 0x0000110F, 0x00003100, 0x3E060F01, 0x00000004, 0x303C3000, 0x00000004, 0x00010F06, 0x00000000
    .WORD 0x3DB20500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964, 0x726F7463, 0x2E2E2079, 0x6C000A2E
    .WORD 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D, 0x65726944, 0x726F7463, 0x00203A79
    .WORD 0x2D2D2D20, 0x0A002F00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; bin/sh, 3687 bytes
    .ASCIIZ "bin/sh"
    .SPACE 117
    .ASCIIZ "00000007147"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (3687 bytes, padded to 4096)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x30000000, 0x00043BF2, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x56000002, 0x11010000, 0x40010000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430B4, 0x01890100, 0x0F010000, 0x00000001
    .WORD 0x01820800, 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x0F080000, 0x00043BF0, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000
    .WORD 0x00000001, 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x000430E8, 0x02090981
    .WORD 0x05000000, 0x000430CC, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100
    .WORD 0x07000000, 0x00043154, 0x040A0080, 0x06000000, 0x00043144, 0x02080881, 0x02090981, 0x05000000
    .WORD 0x00043114, 0x0F010000, 0x00000001, 0x05000000, 0x0004315C, 0x0F010000, 0x00000000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x01880100, 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431B4, 0x20010900, 0x23010800
    .WORD 0x02080881, 0x02090981, 0x030A0A81, 0x05000000, 0x0004318C, 0x01810800, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x00043208, 0x23090800, 0x02080881, 0x030A0A81
    .WORD 0x05000000, 0x000431E8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x40040000, 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000
    .WORD 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000
    .WORD 0x40010000, 0x05000000, 0x00043264, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102
    .WORD 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043534, 0x0F020000, 0x0004326C
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043510
    .WORD 0x22030204, 0x04030500, 0x15000000, 0x0004351C, 0x02040481, 0x05000000, 0x000434CC, 0x0F030000
    .WORD 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435B4, 0x01810500, 0x400C0000, 0x04010080
    .WORD 0x12000000, 0x000435AC, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435AC, 0x0F020000
    .WORD 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000
    .WORD 0x00043590, 0x02040481, 0x05000000, 0x00043550, 0x25010200, 0x25050204, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x05000000, 0x000435B4, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x04010080, 0x06000000, 0x00043620, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043620
    .WORD 0x0F020000, 0x0004326C, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100
    .WORD 0x06000000, 0x00043614, 0x02040481, 0x05000000, 0x000435D4, 0x0F030000, 0x00000000, 0x25030208
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x0004326C, 0x0F030000, 0x00000030, 0x04030080
    .WORD 0x06000000, 0x00043664, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000
    .WORD 0x0004363C, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00
    .WORD 0x10050000, 0x01870600, 0x040C0081, 0x07000000, 0x000436D8, 0x04090080, 0x15000000, 0x000436D8
    .WORD 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000
    .WORD 0x00043708, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800
    .WORD 0x05000000, 0x000437A8, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090
    .WORD 0x06000000, 0x00043734, 0x020707B0, 0x05000000, 0x00043754, 0x04070089, 0x14000000, 0x0004374C
    .WORD 0x020707B0, 0x05000000, 0x00043754, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481
    .WORD 0x01890500, 0x04090080, 0x07000000, 0x00043710, 0x03060681, 0x04040080, 0x06000000, 0x0004379C
    .WORD 0x20020600, 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043774, 0x0F020000
    .WORD 0x00000000, 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x0004366C
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x00000021, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x0004366C, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000
    .WORD 0x0004366C, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100
    .WORD 0x04020080, 0x06000000, 0x000438DC, 0x02010181, 0x02040481, 0x05000000, 0x000438B8, 0x01810300
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000
    .WORD 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x00043974, 0x10090000, 0x0F010000
    .WORD 0x00000008, 0x30000000, 0x000434AC, 0x11090000, 0x04010080, 0x06000000, 0x0004395C, 0x01880100
    .WORD 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x0004397C, 0x01810900
    .WORD 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x0004397C, 0x0F010000, 0x00000000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200
    .WORD 0x04080080, 0x06000000, 0x000439F4, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000
    .WORD 0x04010080, 0x06000000, 0x00043A04, 0x040100CC, 0x07000000, 0x000439F4, 0x22020804, 0x02020281
    .WORD 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A0C, 0x0F010000, 0xFFFFFFFF, 0x05000000
    .WORD 0x00043A0C, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043A58, 0x22010800, 0x40070000, 0x01810800
    .WORD 0x30000000, 0x000435BC, 0x0F010000, 0x00000000, 0x05000000, 0x00043A60, 0x0F010000, 0xFFFFFFFF
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043A98, 0x0F020000, 0x00000000
    .WORD 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080
    .WORD 0x06000000, 0x00043AB0, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x000438E8, 0x04010080, 0x06000000, 0x00043AF0, 0x01820100, 0x0F010000, 0x00000001
    .WORD 0x30000000, 0x00043A1C, 0x05000000, 0x00043AF8, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000
    .WORD 0x000438E8, 0x04010080, 0x06000000, 0x00043BC4, 0x01880100, 0x01810800, 0x01820900, 0x30000000
    .WORD 0x0004398C, 0x04010080, 0x06000000, 0x00043BA8, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000
    .WORD 0x00043BC4, 0x0201098C, 0x30000000, 0x0004303C, 0x22020908, 0x04020082, 0x07000000, 0x00043B90
    .WORD 0x0F010000, 0x00043BE0, 0x30000000, 0x0004307C, 0x0F010000, 0x00043BE4, 0x30000000, 0x0004307C
    .WORD 0x05000000, 0x00043B34, 0x01810800, 0x30000000, 0x00043A1C, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043BCC, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x0000002F, 0x0000000A, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00010F01, 0x00000000
    .WORD 0x3DB20F02, 0x00000004, 0x00020F03, 0x00000000, 0x32203000, 0x00000004, 0x00000F01, 0x00000000
    .WORD 0x3DD50F02, 0x00000004, 0x000C0F03, 0x00000000, 0x32283000, 0x00800004, 0x00000401, 0x3D9A1300
    .WORD 0x01000004, 0x00000184, 0x3DD50F05, 0x05040004, 0x00000205, 0x3DD50F08, 0x08000004, 0x00000405
    .WORD 0x3CBE1300, 0x05810004, 0x05000305, 0x008A2006, 0x00000406, 0x3CAA0600, 0x008D0004, 0x00000406
    .WORD 0x3CAA0600, 0x00800004, 0x00000406, 0x3CAA0600, 0x05810004, 0x00000205, 0x00000F02, 0x05000000
    .WORD 0x00002302, 0x3CBE0500, 0x00000004, 0x00000F02, 0x05000000, 0x00002302, 0x3C5A0500, 0x00000004
    .WORD 0x3DD50F07, 0x07000004, 0x00802006, 0x00000406, 0x3BF60600, 0x00000004, 0x32403000, 0x00800004
    .WORD 0x00000401, 0x3D220600, 0x00000004, 0x3D621200, 0x00020004, 0x00005600, 0xFFFF0F01, 0x0000FFFF
    .WORD 0x00000F02, 0x00000000, 0x32503000, 0x00800004, 0x00000401, 0x3D7E1200, 0x00000004, 0x3BF60500
    .WORD 0x00000004, 0x3E550F01, 0x00000004, 0x3E5F0F02, 0x00000004, 0x00000F03, 0x00000000, 0x32483000
    .WORD 0x00000004, 0x3DB50F01, 0x00000004, 0x303C3000, 0x00000004, 0x00010F01, 0x00000000, 0x32603000
    .WORD 0x00000004, 0x3DC10F01, 0x00000004, 0x303C3000, 0x07000004, 0x0000018D, 0x3BF60500, 0x00000004
    .WORD 0x3DCB0F01, 0x00000004, 0x303C3000, 0x07000004, 0x0000018D, 0x3BF60500, 0x00000004, 0x00000F01
    .WORD 0x00000000, 0x32603000, 0x00000004, 0x0000110F, 0x20243100, 0x45584500, 0x20455643, 0x0A525245
    .WORD 0x524F4600, 0x5245204B, 0x57000A52, 0x20544941, 0x0A525245, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x6E696200, 0x00736C2F, 0x5500736C
    .WORD 0x0000043E, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; lib/libc.inc, 32698 bytes
    .ASCIIZ "lib/libc.inc"
    .SPACE 111
    .ASCIIZ "00000077672"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (32698 bytes, padded to 32768)
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
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x72694420, 0x20746E65, 0x75727473
    .WORD 0x72757463, 0x6D282065, 0x68637461, 0x6B207365, 0x656E7265, 0x6564206C, 0x696E6966, 0x6E6F6974
    .WORD 0x3D3B0A29, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x452E0A3D, 0x44205551, 0x45525F54, 0x20202C47
    .WORD 0x20202020, 0x0A312020, 0x5551452E, 0x5F544420, 0x2C524944, 0x20202020, 0x20202020, 0x2E0A0A32
    .WORD 0x20555145, 0x45524944, 0x495F544E, 0x45444F4E, 0x3020202C, 0x51452E0A, 0x49442055, 0x544E4552
    .WORD 0x5A49535F, 0x20202C45, 0x2E0A3420, 0x20555145, 0x45524944, 0x545F544E, 0x2C455059, 0x38202020
    .WORD 0x51452E0A, 0x49442055, 0x544E4552, 0x4D414E5F, 0x20202C45, 0x0A323120, 0x5551452E, 0x52494420
    .WORD 0x5F544E45, 0x455A4953, 0x202C464F, 0x0A0A3637, 0x5551452E, 0x525F4F20, 0x4C4E4F44, 0x20202C59
    .WORD 0x20202020, 0x0A0A0A30, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x735F203B, 0x74726174
    .WORD 0x50202D20, 0x72676F72, 0x65206D61, 0x7972746E, 0x696F7020, 0x3B0A746E, 0x3A4E4920, 0x72612020
    .WORD 0x61206367, 0x535B2074, 0x202C5D50, 0x76677261, 0x20746120, 0x2B50535B, 0x3B0A5D34, 0x54554F20
    .WORD 0x654E203A, 0x20726576, 0x75746572, 0x20736E72, 0x6163202D, 0x20736C6C, 0x5F535953, 0x54495845
    .WORD 0x74697720, 0x616D2068, 0x73276E69, 0x74657220, 0x206E7275, 0x756C6176, 0x3D3B0A65, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x735F0A3D, 0x74726174, 0x20200A3A, 0x444C2020, 0x31522057, 0x50535B20
    .WORD 0x2020205D, 0x20202020, 0x3B202020, 0x67726120, 0x20200A63, 0x44412020, 0x32522044, 0x20505320
    .WORD 0x20202034, 0x20202020, 0x3B202020, 0x67726120, 0x20200A76, 0x494C2020, 0x20335220, 0x20202030
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x766E6520, 0x203D2070, 0x4C4C554E, 0x203B200A, 0x55502020
    .WORD 0x52204853, 0x3B200A31, 0x50202020, 0x20485355, 0x200A3252, 0x2020203B, 0x48535550, 0x0A335220
    .WORD 0x20202020, 0x6E49203B, 0x61697469, 0x657A696C, 0x65687420, 0x6C6C6120, 0x7461636F, 0x2820726F
    .WORD 0x7473756D, 0x206F6420, 0x73696874, 0x72696620, 0x29217473, 0x203B200A, 0x41432020, 0x6D204C4C
    .WORD 0x6F6C6C61, 0x6E695F63, 0x200A7469, 0x2020203B, 0x20504F50, 0x0A335220, 0x20203B20, 0x504F5020
    .WORD 0x32522020, 0x203B200A, 0x4F502020, 0x52202050, 0x20200A31, 0x4C422020, 0x69616D20, 0x2020206E
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x6C616320, 0x616D206C, 0x6C206E69, 0x20706F6F, 0x736C202D
    .WORD 0x74616320, 0x68636520, 0x7465206F, 0x20200A63, 0x443B2020, 0x67756265, 0x200A3220, 0x4C202020
    .WORD 0x31522049, 0x200A3020, 0x50202020, 0x20485355, 0x20203152, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x7865203B, 0x30207469, 0x73202D20, 0x65636375, 0x31207373, 0x65202D20, 0x726F7272, 0x2020200A
    .WORD 0x20494C20, 0x31203152, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x20747570, 0x73206F74
    .WORD 0x7065656C, 0x206F7320, 0x65726170, 0x7720746E, 0x70746961, 0x63206469, 0x77206E61, 0x0A6B726F
    .WORD 0x20202020, 0x20435653, 0x5F535953, 0x45454C53, 0x20200A50, 0x65442020, 0x20677562, 0x20200A32
    .WORD 0x4F502020, 0x52202050, 0x20200A31, 0x4C20203B, 0x31522049, 0x0A323420, 0x20202020, 0x20435653
    .WORD 0x5F535953, 0x54495845, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x73747570
    .WORD 0x57202D20, 0x65746972, 0x6C756E20, 0x65742D6C, 0x6E696D72, 0x64657461, 0x72747320, 0x20676E69
    .WORD 0x73206F74, 0x756F6474, 0x69772074, 0x6E206874, 0x696C7765, 0x3B0A656E, 0x3A4E4920, 0x31522020
    .WORD 0x73203D20, 0x6E697274, 0x6F702067, 0x65746E69, 0x203B0A72, 0x3A54554F, 0x20315220, 0x7962203D
    .WORD 0x20736574, 0x74697277, 0x206E6574, 0x6520726F, 0x726F7272, 0x646F6320, 0x3D3B0A65, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x75700A3D, 0x0A3A7374, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020
    .WORD 0x48535550, 0x0A385220, 0x20202020, 0x48535550, 0x0A395220, 0x20202020, 0x20564F4D, 0x52203852
    .WORD 0x20202031, 0x20202020, 0x20202020, 0x53203B20, 0x20657661, 0x69727473, 0x7020676E, 0x746E696F
    .WORD 0x200A7265, 0x42202020, 0x7473204C, 0x6E656C72, 0x20202020, 0x20202020, 0x20202020, 0x6547203B
    .WORD 0x74732074, 0x676E6972, 0x6E656C20, 0x0A687467, 0x20202020, 0x20564F4D, 0x52203952, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x53203B20, 0x20657661, 0x676E656C, 0x200A6874, 0x4C202020, 0x31522049
    .WORD 0x44545320, 0x5F54554F, 0x200A4446, 0x4D202020, 0x5220564F, 0x38522032, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x7542203B, 0x72656666, 0x73203D20, 0x6E697274, 0x20200A67, 0x4F4D2020, 0x33522056
    .WORD 0x20395220, 0x20202020, 0x20202020, 0x3B202020, 0x756F4320, 0x3D20746E, 0x6E656C20, 0x0A687467
    .WORD 0x20202020, 0x20435653, 0x5F535953, 0x54495257, 0x20200A45, 0x4F502020, 0x39522050, 0x2020200A
    .WORD 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x3D3D3D3B
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x7570203B, 0x61686374, 0x202D2072, 0x74697257, 0x69732065
    .WORD 0x656C676E, 0x61686320, 0x74636172, 0x74207265, 0x7473206F, 0x74756F64, 0x49203B0A, 0x20203A4E
    .WORD 0x3D203152, 0x61686320, 0x74636172, 0x3B0A7265, 0x54554F20, 0x3152203A, 0x62203D20, 0x73657479
    .WORD 0x69727720, 0x6E657474, 0x29312820, 0x20726F20, 0x6F727265, 0x6F632072, 0x3B0A6564, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x700A3D3D, 0x68637475, 0x0A3A7261, 0x20202020, 0x48535550, 0x0A524C20
    .WORD 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x5220494C, 0x68632038, 0x6675625F, 0x2020200A
    .WORD 0x42545320, 0x20315220, 0x5D38525B, 0x20202020, 0x20202020, 0x203B2020, 0x726F7453, 0x68632065
    .WORD 0x69207261, 0x7473206E, 0x63697461, 0x66756220, 0x0A726566, 0x20202020, 0x5220494C, 0x54532031
    .WORD 0x54554F44, 0x0A44465F, 0x20202020, 0x20564F4D, 0x52203252, 0x20200A38, 0x494C2020, 0x20335220
    .WORD 0x20200A31, 0x56532020, 0x59532043, 0x52575F53, 0x0A455449, 0x20202020, 0x20504F50, 0x200A3852
    .WORD 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3B0A3D3D, 0x72747320, 0x206E656C, 0x6143202D, 0x6C75636C, 0x20657461, 0x69727473, 0x6C20676E
    .WORD 0x74676E65, 0x203B0A68, 0x203A4E49, 0x20315220, 0x7473203D, 0x676E6972, 0x696F7020, 0x7265746E
    .WORD 0x4F203B0A, 0x203A5455, 0x3D203152, 0x6E656C20, 0x20687467, 0x63786528, 0x6964756C, 0x6E20676E
    .WORD 0x206C6C75, 0x6D726574, 0x74616E69, 0x0A29726F, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D
    .WORD 0x6C727473, 0x0A3A6E65, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220
    .WORD 0x20202020, 0x48535550, 0x0A395220, 0x20202020, 0x20564F4D, 0x52203852, 0x20200A31, 0x494C2020
    .WORD 0x20395220, 0x74730A30, 0x6E656C72, 0x6F6F6C5F, 0x200A3A70, 0x4C202020, 0x52204244, 0x525B2032
    .WORD 0x202B2038, 0x205D3952, 0x20202020, 0x6552203B, 0x63206461, 0x61726168, 0x72657463, 0x20746120
    .WORD 0x72727563, 0x20746E65, 0x7366666F, 0x200A7465, 0x43202020, 0x5220504D, 0x0A302032, 0x20202020
    .WORD 0x20514542, 0x6C727473, 0x645F6E65, 0x0A656E6F, 0x20202020, 0x20444441, 0x52203952, 0x20312039
    .WORD 0x20202020, 0x20202020, 0x49203B20, 0x6572636E, 0x746E656D, 0x756F6320, 0x7265746E, 0x2020200A
    .WORD 0x73204220, 0x656C7274, 0x6F6C5F6E, 0x730A706F, 0x656C7274, 0x6F645F6E, 0x0A3A656E, 0x20202020
    .WORD 0x20564F4D, 0x52203152, 0x20200A39, 0x4F502020, 0x39522050, 0x2020200A, 0x504F5020, 0x0A385220
    .WORD 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A3D3D3D, 0x7473203B, 0x706D6372, 0x43202D20, 0x61706D6F, 0x74206572, 0x73206F77, 0x6E697274
    .WORD 0x3B0A7367, 0x3A4E4920, 0x31522020, 0x73203D20, 0x6E697274, 0x202C3167, 0x3D203252, 0x72747320
    .WORD 0x32676E69, 0x4F203B0A, 0x203A5455, 0x3D203152, 0x69203120, 0x71652066, 0x2C6C6175, 0x69203020
    .WORD 0x69642066, 0x72656666, 0x0A746E65, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x63727473
    .WORD 0x0A3A706D, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020
    .WORD 0x48535550, 0x0A395220, 0x20202020, 0x48535550, 0x30315220, 0x2020200A, 0x564F4D20, 0x20385220
    .WORD 0x200A3152, 0x4D202020, 0x5220564F, 0x32522039, 0x7274730A, 0x5F706D63, 0x706F6F6C, 0x20200A3A
    .WORD 0x444C2020, 0x31522042, 0x525B2030, 0x20205D38, 0x20202020, 0x3B202020, 0x616F4C20, 0x68632064
    .WORD 0x66207261, 0x206D6F72, 0x69727473, 0x0A31676E, 0x20202020, 0x2042444C, 0x5B203152, 0x205D3952
    .WORD 0x20202020, 0x20202020, 0x4C203B20, 0x2064616F, 0x72616863, 0x6F726620, 0x7473206D, 0x676E6972
    .WORD 0x20200A32, 0x4D432020, 0x31522050, 0x31522030, 0x2020200A, 0x454E4220, 0x72747320, 0x5F706D63
    .WORD 0x2020656E, 0x20202020, 0x203B2020, 0x6D73694D, 0x68637461, 0x756F6620, 0x200A646E, 0x43202020
    .WORD 0x5220504D, 0x30203031, 0x2020200A, 0x51454220, 0x72747320, 0x5F706D63, 0x20207165, 0x20202020
    .WORD 0x203B2020, 0x68746F42, 0x72747320, 0x73676E69, 0x646E6520, 0x61206465, 0x61732074, 0x7420656D
    .WORD 0x0A656D69, 0x20202020, 0x20444441, 0x52203852, 0x20312038, 0x20202020, 0x20202020, 0x41203B20
    .WORD 0x6E617664, 0x62206563, 0x2068746F, 0x6E696F70, 0x73726574, 0x2020200A, 0x44444120, 0x20395220
    .WORD 0x31203952, 0x2020200A, 0x73204220, 0x6D637274, 0x6F6C5F70, 0x730A706F, 0x6D637274, 0x71655F70
    .WORD 0x20200A3A, 0x494C2020, 0x20315220, 0x20200A31, 0x20422020, 0x63727473, 0x645F706D, 0x0A656E6F
    .WORD 0x63727473, 0x6E5F706D, 0x200A3A65, 0x4C202020, 0x31522049, 0x730A3020, 0x6D637274, 0x6F645F70
    .WORD 0x0A3A656E, 0x20202020, 0x20504F50, 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020
    .WORD 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x3D3B0A0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x636D656D, 0x2D207970, 0x706F4320, 0x656D2079, 0x79726F6D
    .WORD 0x6F6C6220, 0x3B0A6B63, 0x3A4E4920, 0x31522020, 0x64203D20, 0x2C747365, 0x20325220, 0x7273203D
    .WORD 0x52202C63, 0x203D2033, 0x6E756F63, 0x203B0A74, 0x3A54554F, 0x20315220, 0x6564203D, 0x28207473
    .WORD 0x20646E65, 0x69736F70, 0x6E6F6974, 0x3D3B0A29, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x656D0A3D
    .WORD 0x7970636D, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38
    .WORD 0x55502020, 0x52204853, 0x20200A39, 0x55502020, 0x52204853, 0x200A3031, 0x4D202020, 0x5220564F
    .WORD 0x31522038, 0x2020200A, 0x564F4D20, 0x20395220, 0x200A3252, 0x4D202020, 0x5220564F, 0x52203031
    .WORD 0x656D0A33, 0x7970636D, 0x6F6F6C5F, 0x200A3A70, 0x43202020, 0x5220504D, 0x30203031, 0x2020200A
    .WORD 0x51454220, 0x6D656D20, 0x5F797063, 0x656E6F64, 0x2020200A, 0x42444C20, 0x20315220, 0x5D39525B
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x64616552, 0x74796220, 0x72662065, 0x73206D6F, 0x6372756F
    .WORD 0x20200A65, 0x54532020, 0x31522042, 0x38525B20, 0x2020205D, 0x20202020, 0x3B202020, 0x69725720
    .WORD 0x62206574, 0x20657479, 0x64206F74, 0x69747365, 0x6974616E, 0x200A6E6F, 0x41202020, 0x52204444
    .WORD 0x38522038, 0x20203120, 0x20202020, 0x20202020, 0x6441203B, 0x636E6176, 0x6F622065, 0x70206874
    .WORD 0x746E696F, 0x0A737265, 0x20202020, 0x20444441, 0x52203952, 0x0A312039, 0x20202020, 0x20425553
    .WORD 0x20303152, 0x20303152, 0x20202031, 0x20202020, 0x44203B20, 0x65726365, 0x746E656D, 0x756F6320
    .WORD 0x7265746E, 0x2020200A, 0x6D204220, 0x70636D65, 0x6F6C5F79, 0x6D0A706F, 0x70636D65, 0x6F645F79
    .WORD 0x0A3A656E, 0x20202020, 0x20564F4D, 0x52203152, 0x20200A38, 0x4F502020, 0x31522050, 0x20200A30
    .WORD 0x4F502020, 0x39522050, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C
    .WORD 0x52202020, 0x0A0A5445, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x656D203B, 0x7465736D
    .WORD 0x46202D20, 0x206C6C69, 0x6F6D656D, 0x77207972, 0x20687469, 0x736E6F63, 0x746E6174, 0x74796220
    .WORD 0x203B0A65, 0x203A4E49, 0x20315220, 0x6564203D, 0x202C7473, 0x3D203252, 0x6C617620, 0x202C6575
    .WORD 0x3D203352, 0x756F6320, 0x3B0A746E, 0x54554F20, 0x3152203A, 0x64203D20, 0x20747365, 0x646E6528
    .WORD 0x736F7020, 0x6F697469, 0x3B0A296E, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x6D0A3D3D, 0x65736D65
    .WORD 0x200A3A74, 0x50202020, 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020
    .WORD 0x20485355, 0x200A3952, 0x50202020, 0x20485355, 0x0A303152, 0x20202020, 0x20564F4D, 0x52203852
    .WORD 0x20200A31, 0x4F4D2020, 0x39522056, 0x0A325220, 0x20202020, 0x20564F4D, 0x20303152, 0x6D0A3352
    .WORD 0x65736D65, 0x6F6C5F74, 0x0A3A706F, 0x20202020, 0x20504D43, 0x20303152, 0x20200A30, 0x45422020
    .WORD 0x656D2051, 0x7465736D, 0x6E6F645F, 0x20200A65, 0x54532020, 0x39522042, 0x38525B20, 0x2020205D
    .WORD 0x20202020, 0x3B202020, 0x6F745320, 0x76206572, 0x65756C61, 0x20746120, 0x72727563, 0x20746E65
    .WORD 0x69736F70, 0x6E6F6974, 0x2020200A, 0x44444120, 0x20385220, 0x31203852, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x61766441, 0x2065636E, 0x6E696F70, 0x0A726574, 0x20202020, 0x20425553, 0x20303152
    .WORD 0x20303152, 0x20202031, 0x20202020, 0x44203B20, 0x65726365, 0x746E656D, 0x756F6320, 0x7265746E
    .WORD 0x2020200A, 0x6D204220, 0x65736D65, 0x6F6C5F74, 0x6D0A706F, 0x65736D65, 0x6F645F74, 0x0A3A656E
    .WORD 0x20202020, 0x20564F4D, 0x52203152, 0x20200A38, 0x4F502020, 0x31522050, 0x20200A30, 0x4F502020
    .WORD 0x39522050, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020
    .WORD 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7277203B, 0x28657469, 0x202C6466
    .WORD 0x2C667562, 0x6E656C20, 0x0A3B0A29, 0x4E49203B, 0x203B0A3A, 0x31522020, 0x66203D20, 0x203B0A64
    .WORD 0x32522020, 0x62203D20, 0x65666675, 0x203B0A72, 0x33522020, 0x6C203D20, 0x74676E65, 0x0A3B0A68
    .WORD 0x554F203B, 0x3B0A3A54, 0x52202020, 0x203D2031, 0x65747962, 0x72772073, 0x65747469, 0x202F206E
    .WORD 0x6E727265, 0x2D3B0A6F, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72770A2D, 0x3A657469, 0x2020200A
    .WORD 0x43565320, 0x53595320, 0x4952575F, 0x200A4554, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x72203B0A, 0x28646165, 0x202C6466, 0x2C667562, 0x6E656C20, 0x0A3B0A29
    .WORD 0x4E49203B, 0x203B0A3A, 0x31522020, 0x66203D20, 0x203B0A64, 0x32522020, 0x62203D20, 0x65666675
    .WORD 0x203B0A72, 0x33522020, 0x6C203D20, 0x74676E65, 0x0A3B0A68, 0x554F203B, 0x3B0A3A54, 0x52202020
    .WORD 0x203D2031, 0x65747962, 0x65722073, 0x3B0A6461, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x720A2D2D
    .WORD 0x3A646165, 0x2020200A, 0x43565320, 0x53595320, 0x4145525F, 0x20200A44, 0x45522020, 0x0A0A0A54
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x706F203B, 0x70286E65, 0x2C687461, 0x616C6620
    .WORD 0x0A297367, 0x203B0A3B, 0x0A3A4E49, 0x2020203B, 0x3D203152, 0x74617020, 0x203B0A68, 0x32522020
    .WORD 0x66203D20, 0x7367616C, 0x3B0A3B0A, 0x54554F20, 0x203B0A3A, 0x31522020, 0x66203D20, 0x2D3B0A64
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x706F0A2D, 0x0A3A6E65, 0x20202020, 0x20435653, 0x5F535953
    .WORD 0x4E45504F, 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D
    .WORD 0x6F6C6320, 0x66286573, 0x3B0A2964, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x630A2D2D, 0x65736F6C
    .WORD 0x20200A3A, 0x56532020, 0x59532043, 0x4C435F53, 0x0A45534F, 0x20202020, 0x0A544552, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6B726F66, 0x3B0A2928, 0x70203B0A, 0x6E657261
    .WORD 0x3B0A3A74, 0x52202020, 0x203D2031, 0x6C696863, 0x69702064, 0x0A3B0A64, 0x6863203B, 0x3A646C69
    .WORD 0x20203B0A, 0x20315220, 0x0A30203D, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6B726F66
    .WORD 0x20200A3A, 0x56532020, 0x59532043, 0x4F465F53, 0x200A4B52, 0x52202020, 0x0A0A5445, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x65203B0A, 0x76636578, 0x61702865, 0x202C6874, 0x76677261
    .WORD 0x6E65202C, 0x0A297076, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x63657865, 0x0A3A6576
    .WORD 0x20202020, 0x20435653, 0x5F535953, 0x43455845, 0x200A4556, 0x52202020, 0x0A0A5445, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x77203B0A, 0x70746961, 0x70286469, 0x732C6469, 0x75746174
    .WORD 0x3B0A2973, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x770A2D2D, 0x70746961, 0x0A3A6469, 0x20202020
    .WORD 0x20435653, 0x5F535953, 0x54494157, 0x0A444950, 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x65656C73, 0x696D2870, 0x73696C6C, 0x6E6F6365, 0x0A297364
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x65656C73, 0x200A3A70, 0x53202020, 0x53204356
    .WORD 0x535F5359, 0x5045454C, 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x69786520, 0x74732874, 0x73757461, 0x0A3B0A29, 0x656E203B, 0x20726576, 0x75746572
    .WORD 0x0A736E72, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x74697865, 0x20200A3A, 0x56532020
    .WORD 0x59532043, 0x58455F53, 0x0A0A5449, 0x74697865, 0x6E61685F, 0x200A3A67, 0x42202020, 0x69786520
    .WORD 0x61685F74, 0x0A0A676E, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x4D203B0A, 0x524F4D45
    .WORD 0x414D2059, 0x4547414E, 0x544E454D, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x59524556, 0x4D495320, 0x20454C50, 0x4F4D454D
    .WORD 0x41205952, 0x434F4C4C, 0x524F5441, 0x3B0A3B0A, 0x69685420, 0x73692073, 0x6D206120, 0x6D696E69
    .WORD 0x6D206C61, 0x6F6C6C61, 0x72662F63, 0x69206565, 0x656C706D, 0x746E656D, 0x6F697461, 0x6874206E
    .WORD 0x0A3A7461, 0x2E31203B, 0x65735520, 0x20612073, 0x65786966, 0x72612064, 0x20796172, 0x74206F74
    .WORD 0x6B636172, 0x6D656D20, 0x2079726F, 0x636F6C62, 0x3B0A736B, 0x202E3220, 0x73656F44, 0x544F4E20
    .WORD 0x616F6320, 0x6373656C, 0x6D282065, 0x65677265, 0x6A646120, 0x6E656361, 0x72662074, 0x62206565
    .WORD 0x6B636F6C, 0x3B0A2973, 0x202E3320, 0x73656F44, 0x544F4E20, 0x6C707320, 0x62207469, 0x6B636F6C
    .WORD 0x75282073, 0x20736573, 0x69746E65, 0x62206572, 0x6B636F6C, 0x2D736120, 0x0A297369, 0x2E34203B
    .WORD 0x65735520, 0x69662073, 0x2D747372, 0x20746966, 0x72616573, 0x28206863, 0x646E6966, 0x69662073
    .WORD 0x20747372, 0x636F6C62, 0x6874206B, 0x73277461, 0x67696220, 0x6F6E6520, 0x29686775, 0x35203B0A
    .WORD 0x7355202E, 0x73207365, 0x206B7262, 0x63737973, 0x206C6C61, 0x67206F74, 0x6D207465, 0x2065726F
    .WORD 0x6F6D656D, 0x66207972, 0x206D6F72, 0x6E72656B, 0x3B0A6C65, 0x54203B0A, 0x65646172, 0x66666F2D
    .WORD 0x3B0A3A73, 0x56202B20, 0x20797265, 0x706D6973, 0x6120656C, 0x6520646E, 0x20797361, 0x75206F74
    .WORD 0x7265646E, 0x6E617473, 0x203B0A64, 0x7250202B, 0x63696465, 0x6C626174, 0x656D2065, 0x79726F6D
    .WORD 0x61737520, 0x28206567, 0x65786966, 0x61742064, 0x29656C62, 0x2B203B0A, 0x206F4E20, 0x706D6F63
    .WORD 0x2078656C, 0x6B6E696C, 0x6C206465, 0x20747369, 0x616E616D, 0x656D6567, 0x3B0A746E, 0x4D202D20
    .WORD 0x726F6D65, 0x72662079, 0x656D6761, 0x7461746E, 0x206E6F69, 0x6E616328, 0x6D207427, 0x65677265
    .WORD 0x65726620, 0x6C622065, 0x736B636F, 0x203B0A29, 0x6157202D, 0x64657473, 0x61707320, 0x28206563
    .WORD 0x276E6163, 0x70732074, 0x2074696C, 0x6772616C, 0x6C622065, 0x736B636F, 0x203B0A29, 0x694C202D
    .WORD 0x6574696D, 0x6F742064, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x6F6C6C61, 0x69746163, 0x0A736E6F
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x43203B0A, 0x54534E4F, 0x53544E41, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x452E0A0A
    .WORD 0x4D205551, 0x425F5841, 0x4B434F4C, 0x34202C53, 0x20202038, 0x20202020, 0x614D203B, 0x756D6978
    .WORD 0x756E206D, 0x7265626D, 0x20666F20, 0x636F6C62, 0x7720736B, 0x61632065, 0x7274206E, 0x0A6B6361
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x6E616328
    .WORD 0x61207427, 0x636F6C6C, 0x20657461, 0x65726F6D, 0x61687420, 0x3233206E, 0x6D697420, 0x77207365
    .WORD 0x6F687469, 0x66207475, 0x69656572, 0x0A29676E, 0x42203B0A, 0x6B636F6C, 0x73656420, 0x70697263
    .WORD 0x20726F74, 0x7366666F, 0x20737465, 0x63616528, 0x6C622068, 0x206B636F, 0x6465656E, 0x68742073
    .WORD 0x20657365, 0x61762033, 0x7365756C, 0x452E0A29, 0x42205551, 0x4B434F4C, 0x4444415F, 0x20202C52
    .WORD 0x20202030, 0x20202020, 0x664F203B, 0x74657366, 0x7473203A, 0x69747261, 0x6120676E, 0x65726464
    .WORD 0x6F207373, 0x68742066, 0x6C622065, 0x206B636F, 0x62203428, 0x73657479, 0x452E0A29, 0x42205551
    .WORD 0x4B434F4C, 0x5A49535F, 0x20202C45, 0x20202034, 0x20202020, 0x664F203B, 0x74657366, 0x6973203A
    .WORD 0x6F20657A, 0x68742066, 0x6C622065, 0x206B636F, 0x62206E69, 0x73657479, 0x20342820, 0x65747962
    .WORD 0x20202973, 0x51452E0A, 0x4C422055, 0x5F4B434F, 0x44455355, 0x3820202C, 0x20202020, 0x3B202020
    .WORD 0x66664F20, 0x3A746573, 0x663D3020, 0x2C656572, 0x753D3120, 0x20646573, 0x62203428, 0x73657479
    .WORD 0x452E0A29, 0x42205551, 0x4B434F4C, 0x5345445F, 0x20202C43, 0x20203231, 0x20202020, 0x6F54203B
    .WORD 0x206C6174, 0x657A6973, 0x20666F20, 0x20656E6F, 0x636F6C62, 0x6564206B, 0x69726373, 0x726F7470
    .WORD 0x20332820, 0x64726F77, 0x203D2073, 0x62203231, 0x73657479, 0x3B0A0A29, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x54414420, 0x45532041, 0x4F495443, 0x202D204E, 0x20656854, 0x636F6C62
    .WORD 0x6174206B, 0x20656C62, 0x6E203B0A, 0x616D726F, 0x20796C6C, 0x6F6D656D, 0x62207972, 0x6B636F6C
    .WORD 0x65672073, 0x65722074, 0x65726573, 0x20646576, 0x6D6F7266, 0x41454820, 0x68772050, 0x20686369
    .WORD 0x6C207369, 0x7461636F, 0x61206465, 0x61642074, 0x73206174, 0x656D6765, 0x0A20746E, 0x6170203B
    .WORD 0x28206567, 0x65676170, 0x64646120, 0x73736572, 0x65707320, 0x69666963, 0x61206465, 0x73752073
    .WORD 0x645F7265, 0x5F617461, 0x20296176, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C620A0A
    .WORD 0x5F6B636F, 0x6C626174, 0x200A3A65, 0x3B202020, 0x69685420, 0x73692073, 0x206E6120, 0x61727261
    .WORD 0x666F2079, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x63736564, 0x74706972, 0x2E73726F, 0x2020200A
    .WORD 0x45203B20, 0x20686361, 0x63736564, 0x74706972, 0x6820726F, 0x203A7361, 0x72646461, 0x2C737365
    .WORD 0x7A697320, 0x75202C65, 0x5F646573, 0x67616C66, 0x2020200A, 0x54203B20, 0x6C61746F, 0x7A697320
    .WORD 0x4D203A65, 0x425F5841, 0x4B434F4C, 0x202A2053, 0x62203231, 0x73657479, 0x2020200A, 0x50532E20
    .WORD 0x20454341, 0x5F58414D, 0x434F4C42, 0x2A20534B, 0x4F4C4220, 0x445F4B43, 0x0A435345, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6D203B0A, 0x6F6C6C61, 0x69732863, 0x0A29657A, 0x203B0A3B
    .WORD 0x6F6C6C41, 0x65746163, 0x656D2073, 0x79726F6D, 0x6F726620, 0x6874206D, 0x65682065, 0x0A2E7061
    .WORD 0x203B0A3B, 0x20776F48, 0x77207469, 0x736B726F, 0x203B0A3A, 0x41202E31, 0x6E67696C, 0x65687420
    .WORD 0x71657220, 0x74736575, 0x73206465, 0x20657A69, 0x38206F74, 0x74796220, 0x28207365, 0x656B616D
    .WORD 0x656D2073, 0x79726F6D, 0x6E616D20, 0x6D656761, 0x20746E65, 0x69736165, 0x0A297265, 0x2E32203B
    .WORD 0x61655320, 0x20686372, 0x20656874, 0x636F6C62, 0x6174206B, 0x20656C62, 0x20726F66, 0x72662061
    .WORD 0x62206565, 0x6B636F6C, 0x61687420, 0x20732774, 0x6772616C, 0x6E652065, 0x6867756F, 0x33203B0A
    .WORD 0x6649202E, 0x756F6620, 0x202C646E, 0x6B72616D, 0x20746920, 0x75207361, 0x20646573, 0x20646E61
    .WORD 0x75746572, 0x69206E72, 0x61207374, 0x65726464, 0x3B0A7373, 0x202E3420, 0x6E206649, 0x6620746F
    .WORD 0x646E756F, 0x7361202C, 0x6874206B, 0x656B2065, 0x6C656E72, 0x726F6620, 0x726F6D20, 0x656D2065
    .WORD 0x79726F6D, 0x61697620, 0x72627320, 0x7973206B, 0x6C616373, 0x203B0A6C, 0x41202E35, 0x74206464
    .WORD 0x6E206568, 0x6D207765, 0x726F6D65, 0x6F742079, 0x65687420, 0x6F6C6220, 0x74206B63, 0x656C6261
    .WORD 0x646E6120, 0x74657220, 0x206E7275, 0x3B0A7469, 0x49203B0A, 0x7475706E, 0x5220203A, 0x203D2031
    .WORD 0x657A6973, 0x206E6920, 0x65747962, 0x65282073, 0x2C2E672E, 0x30303120, 0x203B0A29, 0x7074754F
    .WORD 0x203A7475, 0x3D203152, 0x696F7020, 0x7265746E, 0x206F7420, 0x6F6C6C61, 0x65746163, 0x656D2064
    .WORD 0x79726F6D, 0x726F2820, 0x69203020, 0x61662066, 0x64656C69, 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x616D0A2D, 0x636F6C6C, 0x20200A3A, 0x203B2020, 0x65766153, 0x67657220, 0x65747369
    .WORD 0x77207372, 0x6C6C2765, 0x65737520, 0x6F732820, 0x20657720, 0x276E6F64, 0x6F632074, 0x70757272
    .WORD 0x61632074, 0x72656C6C, 0x76207327, 0x65756C61, 0x200A2973, 0x50202020, 0x20485355, 0x2020524C
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x53203B20, 0x20657661, 0x75746572, 0x61206E72, 0x65726464
    .WORD 0x200A7373, 0x0A202020, 0x20202020, 0x7453203B, 0x31207065, 0x6C41203A, 0x206E6769, 0x657A6973
    .WORD 0x206F7420, 0x746C756D, 0x656C7069, 0x20666F20, 0x79622038, 0x0A736574, 0x20202020, 0x6857203B
    .WORD 0x4D203F79, 0x20796E61, 0x73555043, 0x726F7720, 0x6166206B, 0x72657473, 0x74697720, 0x6C612068
    .WORD 0x656E6769, 0x656D2064, 0x79726F6D, 0x2020200A, 0x45203B20, 0x706D6178, 0x203A656C, 0x657A6973
    .WORD 0x3030313D, 0x2020200A, 0x20203B20, 0x44444120, 0x20315220, 0x20202037, 0x203E2D20, 0x0A373031
    .WORD 0x20202020, 0x2020203B, 0x20444E41, 0x46467830, 0x46464646, 0x2D203846, 0x3031203E, 0x6D282034
    .WORD 0x69746C75, 0x20656C70, 0x3820666F, 0x20200A29, 0x44412020, 0x31522044, 0x20315220, 0x20202037
    .WORD 0x20202020, 0x20202020, 0x6441203B, 0x20372064, 0x72206F74, 0x646E756F, 0x0A707520, 0x20202020
    .WORD 0x2020494C, 0x30203252, 0x46464678, 0x46464646, 0x200A2038, 0x41202020, 0x5220444E, 0x31522031
    .WORD 0x20325220, 0x20202020, 0x20202020, 0x43203B20, 0x7261656C, 0x776F6C20, 0x33207265, 0x74696220
    .WORD 0x6D282073, 0x20656B61, 0x746C756D, 0x656C7069, 0x20666F20, 0x200A2938, 0x4D202020, 0x5220564F
    .WORD 0x31522035, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2035, 0x67696C61, 0x2064656E
    .WORD 0x657A6973, 0x2E652820, 0x202C2E67, 0x29343031, 0x2020200A, 0x20200A20, 0x203B2020, 0x70657453
    .WORD 0x203A3220, 0x72616553, 0x66206863, 0x6120726F, 0x65726620, 0x6C622065, 0x206B636F, 0x74206E69
    .WORD 0x74206568, 0x656C6261, 0x2020200A, 0x57203B20, 0x6C6C2765, 0x65737520, 0x20345220, 0x69207361
    .WORD 0x7865646E, 0x746E6920, 0x6C62206F, 0x5F6B636F, 0x6C626174, 0x30282065, 0x206F7420, 0x5F58414D
    .WORD 0x434F4C42, 0x312D534B, 0x20200A29, 0x494C2020, 0x20345220, 0x20202030, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x7453203B, 0x20747261, 0x66207461, 0x74737269, 0x6F6C6220, 0x28206B63, 0x65646E69
    .WORD 0x29302078, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x6F6F6C5F, 0x200A3A70, 0x3B202020, 0x65684320
    .WORD 0x69206B63, 0x65772066, 0x20657627, 0x72616573, 0x64656863, 0x6C6C6120, 0x6F6C6220, 0x0A736B63
    .WORD 0x20202020, 0x20504D43, 0x4D203452, 0x425F5841, 0x4B434F4C, 0x20202053, 0x203B2020, 0x706D6F43
    .WORD 0x20657261, 0x65646E69, 0x69772078, 0x6D206874, 0x6D697861, 0x200A6D75, 0x42202020, 0x6D204547
    .WORD 0x6F6C6C61, 0x62735F63, 0x20206B72, 0x20202020, 0x49203B20, 0x6E692066, 0x20786564, 0x4D203D3E
    .WORD 0x425F5841, 0x4B434F4C, 0x6E202C53, 0x7266206F, 0x62206565, 0x6B636F6C, 0x756F6620, 0x200A646E
    .WORD 0x0A202020, 0x20202020, 0x6143203B, 0x6C75636C, 0x20657461, 0x72646461, 0x20737365, 0x7420666F
    .WORD 0x20736968, 0x636F6C62, 0x2073276B, 0x63736564, 0x74706972, 0x200A726F, 0x3B202020, 0x6F6C6220
    .WORD 0x745F6B63, 0x656C6261, 0x28202B20, 0x65646E69, 0x202A2078, 0x63736564, 0x74706972, 0x735F726F
    .WORD 0x29657A69, 0x2020200A, 0x20494C20, 0x62203252, 0x6B636F6C, 0x6261745F, 0x2020656C, 0x3B202020
    .WORD 0x20325220, 0x6162203D, 0x61206573, 0x65726464, 0x6F207373, 0x6C622066, 0x5F6B636F, 0x6C626174
    .WORD 0x20200A65, 0x494C2020, 0x20335220, 0x434F4C42, 0x45445F4B, 0x20204353, 0x20202020, 0x3352203B
    .WORD 0x73203D20, 0x20657A69, 0x6F20666F, 0x6420656E, 0x72637365, 0x6F747069, 0x31282072, 0x79622032
    .WORD 0x29736574, 0x2020200A, 0x4C554D20, 0x20335220, 0x52203452, 0x20202033, 0x20202020, 0x3B202020
    .WORD 0x20335220, 0x6E69203D, 0x20786564, 0x3231202A, 0x666F2820, 0x74657366, 0x746E6920, 0x6174206F
    .WORD 0x29656C62, 0x2020200A, 0x44444120, 0x20325220, 0x52203252, 0x20202033, 0x20202020, 0x3B202020
    .WORD 0x20325220, 0x6226203D, 0x6B636F6C, 0x646E695B, 0x0A5D7865, 0x20202020, 0x2020200A, 0x43203B20
    .WORD 0x6B636568, 0x20666920, 0x73696874, 0x6F6C6220, 0x69206B63, 0x72662073, 0x28206565, 0x44455355
    .WORD 0x616C6620, 0x203D2067, 0x200A2930, 0x4C202020, 0x52205744, 0x525B2033, 0x202B2032, 0x434F4C42
    .WORD 0x53555F4B, 0x205D4445, 0x4C203B20, 0x2064616F, 0x20656874, 0x6F6C6226, 0x695B6B63, 0x7865646E
    .WORD 0x6C622E5D, 0x5F6B636F, 0x64657375, 0x616C6620, 0x20200A67, 0x4D432020, 0x33522050, 0x20203020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x7349203B, 0x20746920, 0x66282030, 0x29656572, 0x20200A3F
    .WORD 0x4E422020, 0x616D2045, 0x636F6C6C, 0x78656E5F, 0x20202074, 0x20202020, 0x6649203B, 0x746F6E20
    .WORD 0x65726620, 0x75282065, 0x29646573, 0x6B73202C, 0x74207069, 0x656E206F, 0x62207478, 0x6B636F6C
    .WORD 0x2020200A, 0x20200A20, 0x203B2020, 0x65657266, 0x6843202E, 0x206B6365, 0x74206669, 0x20736968
    .WORD 0x636F6C62, 0x7369206B, 0x72616C20, 0x65206567, 0x67756F6E, 0x6F662068, 0x756F2072, 0x65722072
    .WORD 0x73657571, 0x20200A74, 0x444C2020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x5A49535F
    .WORD 0x20205D45, 0x6F4C203B, 0x74206461, 0x62206568, 0x6B636F6C, 0x7A697320, 0x20200A65, 0x4D432020
    .WORD 0x33522050, 0x20355220, 0x20202020, 0x20202020, 0x20202020, 0x7349203B, 0x6F6C6220, 0x73206B63
    .WORD 0x20657A69, 0x72203D3E, 0x65757165, 0x64657473, 0x7A697320, 0x200A3F65, 0x42202020, 0x6D204547
    .WORD 0x6F6C6C61, 0x6F665F63, 0x20646E75, 0x20202020, 0x59203B20, 0x20217365, 0x66206557, 0x646E756F
    .WORD 0x73206120, 0x61746975, 0x20656C62, 0x636F6C62, 0x20200A6B, 0x6D0A2020, 0x6F6C6C61, 0x656E5F63
    .WORD 0x0A3A7478, 0x20202020, 0x6854203B, 0x62207369, 0x6B636F6C, 0x20736920, 0x68746965, 0x75207265
    .WORD 0x20646573, 0x7420726F, 0x73206F6F, 0x6C6C616D, 0x7274202C, 0x656E2079, 0x6F207478, 0x200A656E
    .WORD 0x41202020, 0x52204444, 0x34522034, 0x20203120, 0x20202020, 0x20202020, 0x49203B20, 0x6572636E
    .WORD 0x746E656D, 0x646E6920, 0x74207865, 0x6863206F, 0x206B6365, 0x7478656E, 0x6F6C6220, 0x200A6B63
    .WORD 0x42202020, 0x6C616D20, 0x5F636F6C, 0x706F6F6C, 0x20202020, 0x20202020, 0x47203B20, 0x6162206F
    .WORD 0x74206B63, 0x7473206F, 0x20747261, 0x6C20666F, 0x0A706F6F, 0x6C616D0A, 0x5F636F6C, 0x6E756F66
    .WORD 0x200A3A64, 0x3B202020, 0x65745320, 0x3A332070, 0x20655720, 0x6E756F66, 0x20612064, 0x65657266
    .WORD 0x6F6C6220, 0x6C206B63, 0x65677261, 0x6F6E6520, 0x21686775, 0x2020200A, 0x52203B20, 0x203D2032
    .WORD 0x6E696F70, 0x20726574, 0x74206F74, 0x62206568, 0x6B636F6C, 0x73656420, 0x70697263, 0x0A726F74
    .WORD 0x20202020, 0x3352203B, 0x62203D20, 0x6B636F6C, 0x7A697320, 0x77282065, 0x6F642065, 0x2074276E
    .WORD 0x20657375, 0x66207469, 0x7320726F, 0x74696C70, 0x676E6974, 0x206E6920, 0x73696874, 0x6D697320
    .WORD 0x20656C70, 0x73726576, 0x296E6F69, 0x2020200A, 0x20200A20, 0x203B2020, 0x6B72614D, 0x65687420
    .WORD 0x6F6C6220, 0x61206B63, 0x73752073, 0x28206465, 0x44455355, 0x616C6620, 0x203D2067, 0x200A2931
    .WORD 0x4C202020, 0x33522049, 0x20203120, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2033
    .WORD 0x75282031, 0x29646573, 0x2020200A, 0x57545320, 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F
    .WORD 0x44455355, 0x3B20205D, 0x6F745320, 0x31206572, 0x206E6920, 0x20656874, 0x44455355, 0x65696620
    .WORD 0x200A646C, 0x0A202020, 0x20202020, 0x6547203B, 0x68742074, 0x6C622065, 0x276B636F, 0x74732073
    .WORD 0x69747261, 0x6120676E, 0x65726464, 0x61207373, 0x7220646E, 0x72757465, 0x7469206E, 0x2020200A
    .WORD 0x57444C20, 0x20315220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x52444441, 0x3B20205D, 0x20315220
    .WORD 0x6461203D, 0x73657264, 0x666F2073, 0x69687420, 0x6C622073, 0x0A6B636F, 0x20202020, 0x616D2042
    .WORD 0x636F6C6C, 0x6E6F645F, 0x20202065, 0x20202020, 0x203B2020, 0x706D754A, 0x206F7420, 0x61656C63
    .WORD 0x2070756E, 0x20646E61, 0x75746572, 0x0A0A6E72, 0x6C6C616D, 0x735F636F, 0x3A6B7262, 0x2020200A
    .WORD 0x53203B20, 0x20706574, 0x4E203A34, 0x7266206F, 0x62206565, 0x6B636F6C, 0x756F6620, 0x6920646E
    .WORD 0x6174206E, 0x0A656C62, 0x20202020, 0x7341203B, 0x6874206B, 0x656B2065, 0x6C656E72, 0x726F6620
    .WORD 0x726F6D20, 0x656D2065, 0x79726F6D, 0x69737520, 0x7320676E, 0x206B7262, 0x63737973, 0x0A6C6C61
    .WORD 0x20202020, 0x2020200A, 0x52203B20, 0x6C612035, 0x64616572, 0x61682079, 0x68742073, 0x6C612065
    .WORD 0x656E6769, 0x69732064, 0x7720657A, 0x656E2065, 0x200A6465, 0x4D202020, 0x5220564F, 0x35522031
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2031, 0x657A6973, 0x206F7420, 0x6F6C6C61
    .WORD 0x65746163, 0x2020200A, 0x43565320, 0x53595320, 0x5242535F, 0x2020204B, 0x20202020, 0x3B202020
    .WORD 0x6C614320, 0x656B206C, 0x6C656E72, 0x6273203A, 0x73286B72, 0x29657A69, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x63656843, 0x6669206B, 0x72627320, 0x6166206B, 0x64656C69, 0x65722820, 0x6E727574
    .WORD 0x312D2073, 0x20726F20, 0x6E6F2030, 0x72726520, 0x0A29726F, 0x20202020, 0x20504D43, 0x30203152
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x20646944, 0x6B726273, 0x74657220, 0x206E7275
    .WORD 0x726F2030, 0x67656E20, 0x76697461, 0x200A3F65, 0x42202020, 0x6D20544C, 0x6F6C6C61, 0x72655F63
    .WORD 0x20726F72, 0x20202020, 0x49203B20, 0x72652066, 0x2C726F72, 0x74657220, 0x206E7275, 0x4C4C554E
    .WORD 0x2020200A, 0x20200A20, 0x203B2020, 0x70657453, 0x203A3520, 0x6B726273, 0x63757320, 0x64656563
    .WORD 0x202C6465, 0x68206577, 0x20657661, 0x2077656E, 0x6F6D656D, 0x61207972, 0x64612074, 0x73657264
    .WORD 0x6E692073, 0x0A315220, 0x20202020, 0x6F4E203B, 0x65772077, 0x65656E20, 0x6F742064, 0x64646120
    .WORD 0x69687420, 0x656E2073, 0x6C622077, 0x206B636F, 0x6F206F74, 0x74207275, 0x656C6261, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x646E6946, 0x206E6120, 0x74706D65, 0x6C732079, 0x6920746F, 0x6874206E
    .WORD 0x6C622065, 0x206B636F, 0x6C626174, 0x20200A65, 0x494C2020, 0x20345220, 0x20202030, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x7453203B, 0x20747261, 0x66207461, 0x74737269, 0x6F6C6220, 0x200A6B63
    .WORD 0x0A202020, 0x6C6C616D, 0x615F636F, 0x0A3A6464, 0x20202020, 0x6843203B, 0x206B6365, 0x77206669
    .WORD 0x65762765, 0x61657320, 0x65686372, 0x6C612064, 0x6C62206C, 0x736B636F, 0x2020200A, 0x504D4320
    .WORD 0x20345220, 0x5F58414D, 0x434F4C42, 0x2020534B, 0x0A202020, 0x20202020, 0x20454742, 0x6C6C616D
    .WORD 0x655F636F, 0x726F7272, 0x20202020, 0x203B2020, 0x65206F4E, 0x7974706D, 0x6F6C7320, 0x28202174
    .WORD 0x756F6873, 0x276E646C, 0x61682074, 0x6E657070, 0x20200A29, 0x200A2020, 0x3B202020, 0x74654720
    .WORD 0x73656420, 0x70697263, 0x20726F74, 0x72646461, 0x0A737365, 0x20202020, 0x5220494C, 0x6C622032
    .WORD 0x5F6B636F, 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x434F4C42, 0x45445F4B, 0x200A4353
    .WORD 0x4D202020, 0x52204C55, 0x34522033, 0x0A335220, 0x20202020, 0x20444441, 0x52203252, 0x33522032
    .WORD 0x20202020, 0x20202020, 0x6226203B, 0x6B636F6C, 0x646E695B, 0x34527865, 0x20200A5D, 0x200A2020
    .WORD 0x3B202020, 0x65684320, 0x69206B63, 0x68742066, 0x73207369, 0x20746F6C, 0x66207369, 0x20656572
    .WORD 0x45535528, 0x6C662044, 0x3D206761, 0x0A293020, 0x20202020, 0x2057444C, 0x5B203352, 0x2B203252
    .WORD 0x4F4C4220, 0x555F4B43, 0x5D444553, 0x2020200A, 0x504D4320, 0x20335220, 0x20200A30, 0x45422020
    .WORD 0x616D2051, 0x636F6C6C, 0x6464615F, 0x756F665F, 0x2020646E, 0x6F46203B, 0x20646E75, 0x65206E61
    .WORD 0x7974706D, 0x6F6C7320, 0x200A2174, 0x0A202020, 0x20202020, 0x6C53203B, 0x6920746F, 0x73752073
    .WORD 0x202C6465, 0x20797274, 0x7478656E, 0x656E6F20, 0x2020200A, 0x44444120, 0x20345220, 0x31203452
    .WORD 0x2020200A, 0x6D204220, 0x6F6C6C61, 0x64615F63, 0x6D0A0A64, 0x6F6C6C61, 0x64615F63, 0x6F665F64
    .WORD 0x3A646E75, 0x2020200A, 0x57203B20, 0x6F662065, 0x20646E75, 0x65206E61, 0x7974706D, 0x6F6C7320
    .WORD 0x74612074, 0x0A325220, 0x20202020, 0x7453203B, 0x2065726F, 0x20656874, 0x2077656E, 0x636F6C62
    .WORD 0x2073276B, 0x6F666E69, 0x74616D72, 0x0A6E6F69, 0x20202020, 0x2020200A, 0x53203B20, 0x65726F74
    .WORD 0x65687420, 0x64646120, 0x73736572, 0x31522820, 0x6F726620, 0x6273206D, 0x0A296B72, 0x20202020
    .WORD 0x20575453, 0x5B203152, 0x2B203252, 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x3B202020, 0x6F6C6220
    .WORD 0x612E6B63, 0x65726464, 0x3D207373, 0x64646120, 0x73736572, 0x6F726620, 0x6273206D, 0x200A6B72
    .WORD 0x0A202020, 0x20202020, 0x7453203B, 0x2065726F, 0x20656874, 0x657A6973, 0x35522820, 0x61203D20
    .WORD 0x6E67696C, 0x73206465, 0x29657A69, 0x2020200A, 0x57545320, 0x20355220, 0x2032525B, 0x4C42202B
    .WORD 0x5F4B434F, 0x455A4953, 0x2020205D, 0x6C62203B, 0x2E6B636F, 0x657A6973, 0x73203D20, 0x0A657A69
    .WORD 0x20202020, 0x2020200A, 0x4D203B20, 0x206B7261, 0x75207361, 0x20646573, 0x45535528, 0x203D2044
    .WORD 0x200A2931, 0x4C202020, 0x33522049, 0x200A3120, 0x53202020, 0x52205754, 0x525B2033, 0x202B2032
    .WORD 0x434F4C42, 0x53555F4B, 0x205D4445, 0x203B2020, 0x636F6C62, 0x73752E6B, 0x3D206465, 0x200A3120
    .WORD 0x0A202020, 0x20202020, 0x3152203B, 0x726C6120, 0x79646165, 0x73616820, 0x65687420, 0x64646120
    .WORD 0x73736572, 0x6F726620, 0x6273206D, 0x202C6B72, 0x6A206F73, 0x20747375, 0x75746572, 0x69206E72
    .WORD 0x20200A74, 0x20422020, 0x6C6C616D, 0x645F636F, 0x0A656E6F, 0x6C616D0A, 0x5F636F6C, 0x6F727265
    .WORD 0x200A3A72, 0x3B202020, 0x6D6F5320, 0x69687465, 0x7720676E, 0x20746E65, 0x6E6F7277, 0x202D2067
    .WORD 0x75746572, 0x4E206E72, 0x204C4C55, 0x0A293028, 0x20202020, 0x5220494C, 0x0A302031, 0x6C616D0A
    .WORD 0x5F636F6C, 0x656E6F64, 0x20200A3A, 0x4F502020, 0x524C2050, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x6552203B, 0x726F7473, 0x65722065, 0x6E727574, 0x64646120, 0x73736572, 0x2020200A
    .WORD 0x54455220, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x74655220, 0x206E7275
    .WORD 0x63206F74, 0x656C6C61, 0x69772072, 0x52206874, 0x203D2031, 0x6E696F70, 0x20726574, 0x4E20726F
    .WORD 0x0A4C4C55, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x66203B0A, 0x28656572, 0x29727470
    .WORD 0x3B0A3B0A, 0x65724620, 0x70207365, 0x69766572, 0x6C73756F, 0x6C612079, 0x61636F6C, 0x20646574
    .WORD 0x6F6D656D, 0x0A2E7972, 0x203B0A3B, 0x20776F48, 0x77207469, 0x736B726F, 0x203B0A3A, 0x46202E31
    .WORD 0x20646E69, 0x20656874, 0x636F6C62, 0x6564206B, 0x69726373, 0x726F7470, 0x726F6620, 0x69687420
    .WORD 0x64612073, 0x73657264, 0x203B0A73, 0x4D202E32, 0x206B7261, 0x61207469, 0x72662073, 0x28206565
    .WORD 0x44455355, 0x30203D20, 0x203B0A29, 0x4D202E33, 0x726F6D65, 0x73692079, 0x776F6E20, 0x61766120
    .WORD 0x62616C69, 0x6620656C, 0x6620726F, 0x72757475, 0x616D2065, 0x636F6C6C, 0x6C616320, 0x3B0A736C
    .WORD 0x4E203B0A, 0x3A65746F, 0x69685420, 0x69732073, 0x656C706D, 0x72657620, 0x6E6F6973, 0x656F6420
    .WORD 0x4F4E2073, 0x6F632054, 0x73656C61, 0x61206563, 0x63616A64, 0x20746E65, 0x65657266, 0x6F6C6220
    .WORD 0x21736B63, 0x20203B0A, 0x20202020, 0x206F5320, 0x67617266, 0x746E656D, 0x6F697461, 0x6163206E
    .WORD 0x636F206E, 0x20727563, 0x7265766F, 0x6D697420, 0x3B0A2E65, 0x49203B0A, 0x7475706E, 0x5220203A
    .WORD 0x203D2031, 0x6E696F70, 0x20726574, 0x6D206F74, 0x726F6D65, 0x6F742079, 0x65726620, 0x66282065
    .WORD 0x206D6F72, 0x6C6C616D, 0x0A29636F, 0x754F203B, 0x74757074, 0x6F4E203A, 0x6E696874, 0x2D3B0A67
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72660A2D, 0x0A3A6565, 0x20202020, 0x6153203B, 0x72206576
    .WORD 0x73696765, 0x73726574, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x70657453, 0x203A3120, 0x63656843, 0x6669206B, 0x696F7020, 0x7265746E, 0x20736920, 0x4C4C554E
    .WORD 0x2020200A, 0x504D4320, 0x20315220, 0x20202030, 0x20202020, 0x20202020, 0x3B202020, 0x20734920
    .WORD 0x3D203152, 0x3F30203D, 0x2020200A, 0x51454220, 0x65726620, 0x6F645F65, 0x2020656E, 0x20202020
    .WORD 0x3B202020, 0x20664920, 0x4C4C554E, 0x6F6E202C, 0x6E696874, 0x6F742067, 0x65726620, 0x6A202C65
    .WORD 0x20747375, 0x75746572, 0x200A6E72, 0x0A202020, 0x20202020, 0x7453203B, 0x32207065, 0x6553203A
    .WORD 0x68637261, 0x65687420, 0x6F6C6220, 0x74206B63, 0x656C6261, 0x726F6620, 0x69687420, 0x64612073
    .WORD 0x73657264, 0x20200A73, 0x494C2020, 0x20345220, 0x20202030, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x7453203B, 0x20747261, 0x66207461, 0x74737269, 0x6F6C6220, 0x200A6B63, 0x0A202020, 0x65657266
    .WORD 0x6F6F6C5F, 0x200A3A70, 0x3B202020, 0x65684320, 0x69206B63, 0x65772066, 0x20657627, 0x72616573
    .WORD 0x64656863, 0x6C6C6120, 0x6F6C6220, 0x0A736B63, 0x20202020, 0x20504D43, 0x4D203452, 0x425F5841
    .WORD 0x4B434F4C, 0x20200A53, 0x47422020, 0x72662045, 0x645F6565, 0x20656E6F, 0x20202020, 0x20202020
    .WORD 0x6F4E203B, 0x6F662074, 0x20646E75, 0x6769202D, 0x65726F6E, 0x6F632820, 0x20646C75, 0x69206562
    .WORD 0x6C61766E, 0x70206469, 0x746E696F, 0x0A297265, 0x20202020, 0x2020200A, 0x47203B20, 0x64207465
    .WORD 0x72637365, 0x6F747069, 0x64612072, 0x73657264, 0x20200A73, 0x494C2020, 0x20325220, 0x636F6C62
    .WORD 0x61745F6B, 0x0A656C62, 0x20202020, 0x5220494C, 0x4C422033, 0x5F4B434F, 0x43534544, 0x20202020
    .WORD 0x203B2020, 0x676E656C, 0x6F206874, 0x6E6F2066, 0x6C622065, 0x206B636F, 0x63736564, 0x74706972
    .WORD 0x200A726F, 0x4D202020, 0x52204C55, 0x34522033, 0x20335220, 0x20202020, 0x20202020, 0x72203B20
    .WORD 0x6C622034, 0x206B636F, 0x0A786469, 0x20202020, 0x20444441, 0x52203252, 0x33522032, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x3D203252, 0x6C622620, 0x5B6B636F, 0x200A5D69, 0x0A202020, 0x20202020
    .WORD 0x6843203B, 0x206B6365, 0x74206669, 0x20736968, 0x636F6C62, 0x2073276B, 0x72646461, 0x20737365
    .WORD 0x6374616D, 0x20736568, 0x20656874, 0x6E696F70, 0x0A726574, 0x20202020, 0x2057444C, 0x5B203352
    .WORD 0x2B203252, 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x203B2020, 0x3D203352, 0x62262020, 0x6B636F6C
    .WORD 0x2E5D695B, 0x636F6C62, 0x6461206B, 0x73657264, 0x20200A73, 0x4D432020, 0x33522050, 0x20315220
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x7349203B, 0x69687420, 0x756F2073, 0x6C622072, 0x3F6B636F
    .WORD 0x2020200A, 0x51454220, 0x65726620, 0x6F665F65, 0x20646E75, 0x20202020, 0x3B202020, 0x73655920
    .WORD 0x6577202C, 0x756F6620, 0x6920646E, 0x200A2174, 0x0A202020, 0x20202020, 0x6F4E203B, 0x68742074
    .WORD 0x62207369, 0x6B636F6C, 0x7274202C, 0x656E2079, 0x200A7478, 0x41202020, 0x52204444, 0x34522034
    .WORD 0x200A3120, 0x42202020, 0x65726620, 0x6F6C5F65, 0x0A0A706F, 0x65657266, 0x756F665F, 0x0A3A646E
    .WORD 0x20202020, 0x7453203B, 0x33207065, 0x6557203A, 0x756F6620, 0x7420646E, 0x62206568, 0x6B636F6C
    .WORD 0x73656420, 0x70697263, 0x20726F74, 0x52207461, 0x20200A32, 0x203B2020, 0x6B72614D, 0x20746920
    .WORD 0x66207361, 0x20656572, 0x6D206F73, 0x6F6C6C61, 0x61632063, 0x7375206E, 0x74692065, 0x61676120
    .WORD 0x200A6E69, 0x0A202020, 0x20202020, 0x5220494C, 0x20302033, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x3D203352, 0x28203020, 0x65657266, 0x20200A29, 0x54532020, 0x33522057, 0x32525B20
    .WORD 0x42202B20, 0x4B434F4C, 0x4553555F, 0x20205D44, 0x6226203B, 0x6B636F6C, 0x2E5D695B, 0x64657375
    .WORD 0x30203D20, 0x2020200A, 0x20200A20, 0x203B2020, 0x45544F4E, 0x6557203A, 0x206F6420, 0x20544F4E
    .WORD 0x61656C63, 0x68742072, 0x64612065, 0x73657264, 0x726F2073, 0x7A697320, 0x20200A65, 0x203B2020
    .WORD 0x79656854, 0x61747320, 0x6E692079, 0x65687420, 0x62617420, 0x6120656C, 0x7720646E, 0x206C6C69
    .WORD 0x6F206562, 0x77726576, 0x74746972, 0x77206E65, 0x206E6568, 0x73756572, 0x200A6465, 0x0A202020
    .WORD 0x65657266, 0x6E6F645F, 0x200A3A65, 0x3B202020, 0x656C4320, 0x75206E61, 0x6E612070, 0x65722064
    .WORD 0x6E727574, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x6D203B0A, 0x6F6C6C61, 0x6E695F63, 0x2D207469, 0x696E4920, 0x6C616974
    .WORD 0x20657A69, 0x20656874, 0x6F6D656D, 0x61207972, 0x636F6C6C, 0x726F7461, 0x3B0A3B0A, 0x656C4320
    .WORD 0x20737261, 0x20656874, 0x69746E65, 0x62206572, 0x6B636F6C, 0x62617420, 0x7320656C, 0x6C61206F
    .WORD 0x6C62206C, 0x736B636F, 0x65726120, 0x72616D20, 0x2064656B, 0x66207361, 0x0A656572, 0x6853203B
    .WORD 0x646C756F, 0x20656220, 0x6C6C6163, 0x6F206465, 0x2065636E, 0x73207461, 0x65747379, 0x7473206D
    .WORD 0x75747261, 0x65622070, 0x65726F66, 0x69737520, 0x6D20676E, 0x6F6C6C61, 0x2D3B0A63, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x616D0A2D, 0x636F6C6C, 0x696E695F, 0x200A3A74, 0x3B202020, 0x76615320
    .WORD 0x65722065, 0x74736967, 0x0A737265, 0x20202020, 0x48535550, 0x20524C20, 0x200A2020, 0x3B202020
    .WORD 0x65745320, 0x3A312070, 0x656C4320, 0x74207261, 0x65206568, 0x7269746E, 0x6C622065, 0x206B636F
    .WORD 0x6C626174, 0x20200A65, 0x203B2020, 0x20746553, 0x206C6C61, 0x65747962, 0x6E692073, 0x6F6C6220
    .WORD 0x745F6B63, 0x656C6261, 0x206F7420, 0x20200A30, 0x494C2020, 0x20315220, 0x636F6C62, 0x61745F6B
    .WORD 0x20656C62, 0x20202020, 0x3152203B, 0x73203D20, 0x74726174, 0x64646120, 0x73736572, 0x20666F20
    .WORD 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x5F58414D, 0x434F4C42, 0x2A20534B, 0x4F4C4220
    .WORD 0x445F4B43, 0x20435345, 0x52203B20, 0x203D2033, 0x61746F74, 0x7962206C, 0x20736574, 0x63206F74
    .WORD 0x7261656C, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x696E695F, 0x6F6C5F74, 0x0A3A706F, 0x20202020
    .WORD 0x20504D43, 0x30203352, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x65766148, 0x20657720
    .WORD 0x61656C63, 0x20646572, 0x206C6C61, 0x65747962, 0x200A3F73, 0x42202020, 0x6D205145, 0x6F6C6C61
    .WORD 0x6E695F63, 0x645F7469, 0x20656E6F, 0x59203B20, 0x202C7365, 0x72276577, 0x6F642065, 0x200A656E
    .WORD 0x0A202020, 0x20202020, 0x5220494C, 0x20302032, 0x20202020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x3D203252, 0x28203020, 0x756C6176, 0x6F742065, 0x69727720, 0x0A296574, 0x20202020, 0x20425453
    .WORD 0x5B203252, 0x205D3152, 0x20202020, 0x20202020, 0x203B2020, 0x726F7453, 0x20302065, 0x63207461
    .WORD 0x65727275, 0x6120746E, 0x65726464, 0x200A7373, 0x41202020, 0x52204444, 0x31522031, 0x20203120
    .WORD 0x20202020, 0x20202020, 0x4D203B20, 0x2065766F, 0x6E206F74, 0x20747865, 0x65747962, 0x2020200A
    .WORD 0x42555320, 0x20335220, 0x31203352, 0x20202020, 0x20202020, 0x3B202020, 0x63654420, 0x656D6572
    .WORD 0x6220746E, 0x20657479, 0x6E756F63, 0x0A726574, 0x20202020, 0x616D2042, 0x636F6C6C, 0x696E695F
    .WORD 0x6F6C5F74, 0x2020706F, 0x203B2020, 0x746E6F43, 0x65756E69, 0x2020200A, 0x616D0A20, 0x636F6C6C
    .WORD 0x696E695F, 0x6F645F74, 0x0A3A656E, 0x20202020, 0x6C43203B, 0x206E6165, 0x61207075, 0x7220646E
    .WORD 0x72757465, 0x20200A6E, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x544E4920, 0x414E5245, 0x4548204C, 0x5245504C, 0x3D3B0A53
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A0A3D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469, 0x726F635F, 0x202D2065, 0x76696E55, 0x61737265
    .WORD 0x6E69206C, 0x65676574, 0x6F742072, 0x72747320, 0x20676E69, 0x766E6F63, 0x65747265, 0x0A3B0A72
    .WORD 0x3152203B, 0x64203D20, 0x69747365, 0x6974616E, 0x62206E6F, 0x65666675, 0x203B0A72, 0x3D203252
    .WORD 0x746E6920, 0x72656765, 0x206F7420, 0x766E6F63, 0x0A747265, 0x3352203B, 0x62203D20, 0x20657361
    .WORD 0x202C3228, 0x202C3031, 0x3120726F, 0x3B0A2936, 0x20345220, 0x6973203D, 0x66206E67, 0x2067616C
    .WORD 0x3D203128, 0x67697320, 0x2C64656E, 0x3D203020, 0x736E7520, 0x656E6769, 0x3B0A2964, 0x20355220
    .WORD 0x6574203D, 0x6220706D, 0x65666675, 0x69732072, 0x6E20657A, 0x65646565, 0x0A3B0A64, 0x6552203B
    .WORD 0x6E727574, 0x3B0A3A73, 0x52202020, 0x203D2031, 0x6769726F, 0x6C616E69, 0x73656420, 0x616E6974
    .WORD 0x6E6F6974, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x726F635F, 0x200A3A65, 0x50202020, 0x20485355, 0x200A524C
    .WORD 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x50202020, 0x20485355
    .WORD 0x0A303152, 0x20202020, 0x48535550, 0x31315220, 0x2020200A, 0x53555020, 0x31522048, 0x200A0A32
    .WORD 0x4D202020, 0x2020564F, 0x20203852, 0x20203152, 0x20202020, 0x20202020, 0x6153203B, 0x64206576
    .WORD 0x69747365, 0x6974616E, 0x200A6E6F, 0x0A202020, 0x20202020, 0x20564F4D, 0x20395220, 0x20325220
    .WORD 0x20202020, 0x20202020, 0x57203B20, 0x696B726F, 0x7620676E, 0x65756C61, 0x2020200A, 0x564F4D20
    .WORD 0x31522020, 0x33522031, 0x20202020, 0x20202020, 0x203B2020, 0x65736142, 0x2020200A, 0x564F4D20
    .WORD 0x31522020, 0x34522032, 0x20202020, 0x20202020, 0x203B2020, 0x6E676953, 0x616C6620, 0x20200A67
    .WORD 0x4D3B2020, 0x2020564F, 0x20303152, 0x20203552, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D
    .WORD 0x65666675, 0x69732072, 0x200A657A, 0x0A202020, 0x20202020, 0x6C41203B, 0x61636F6C, 0x74206574
    .WORD 0x20706D65, 0x66667562, 0x28207265, 0x657A6973, 0x73617020, 0x20646573, 0x52206E69, 0x200A2935
    .WORD 0x53202020, 0x20204255, 0x53205053, 0x35522050, 0x2020200A, 0x564F4D20, 0x31522020, 0x31522030
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x7065654B, 0x69726F20, 0x616E6967, 0x6F70206C, 0x65746E69
    .WORD 0x20200A72, 0x4F4D2020, 0x52202056, 0x53202036, 0x20202050, 0x20202020, 0x3B202020, 0x6D655420
    .WORD 0x75622070, 0x72656666, 0x696F7020, 0x7265746E, 0x2020200A, 0x73757020, 0x35522068, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x65766173, 0x20355220, 0x20726F66, 0x6D617266, 0x656C2065
    .WORD 0x0A657661, 0x20202020, 0x20564F4D, 0x20375220, 0x20365220, 0x20202020, 0x20202020, 0x53203B20
    .WORD 0x20657661, 0x72617473, 0x666F2074, 0x6D657420, 0x75622070, 0x72656666, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x63656843, 0x6F66206B, 0x69732072, 0x28206E67, 0x73206669, 0x656E6769, 0x6E612064
    .WORD 0x656E2064, 0x69746167, 0x0A296576, 0x20202020, 0x20504D43, 0x32315220, 0x200A3120, 0x42202020
    .WORD 0x2020454E, 0x616F7469, 0x726F635F, 0x6E755F65, 0x6E676973, 0x200A6465, 0x0A202020, 0x20202020
    .WORD 0x20504D43, 0x20395220, 0x20200A30, 0x47422020, 0x69202045, 0x5F616F74, 0x65726F63, 0x736E755F
    .WORD 0x656E6769, 0x20200A64, 0x200A2020, 0x3B202020, 0x67654E20, 0x76697461, 0x756E2065, 0x7265626D
    .WORD 0x61202D20, 0x6D206464, 0x73756E69, 0x67697320, 0x20200A6E, 0x494C2020, 0x52202020, 0x35342032
    .WORD 0x20202020, 0x2D273B20, 0x20200A27, 0x54532020, 0x52202042, 0x525B2032, 0x200A5D38, 0x41202020
    .WORD 0x20204444, 0x52203852, 0x0A312038, 0x20202020, 0x20544F4E, 0x20395220, 0x200A3952, 0x41202020
    .WORD 0x20204444, 0x52203952, 0x0A312039, 0x20202020, 0x47454E3B, 0x39522020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x656B614D, 0x736F7020, 0x76697469, 0x20200A65, 0x690A2020, 0x5F616F74
    .WORD 0x65726F63, 0x736E755F, 0x656E6769, 0x200A3A64, 0x3B202020, 0x65705320, 0x6C616963, 0x73616320
    .WORD 0x7A203A65, 0x0A6F7265, 0x20202020, 0x20504D43, 0x20395220, 0x20200A30, 0x4E422020, 0x69202045
    .WORD 0x5F616F74, 0x65726F63, 0x6E6F635F, 0x74726576, 0x2020200A, 0x20200A20, 0x494C2020, 0x52202020
    .WORD 0x38342032, 0x20202020, 0x3027203B, 0x20200A27, 0x54532020, 0x52202042, 0x525B2032, 0x200A5D38
    .WORD 0x41202020, 0x20204444, 0x52203852, 0x0A312038, 0x20202020, 0x2020494C, 0x20325220, 0x20200A30
    .WORD 0x54532020, 0x52202042, 0x525B2032, 0x200A5D38, 0x42202020, 0x20202020, 0x616F7469, 0x726F635F
    .WORD 0x69665F65, 0x6873696E, 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x766E6F63, 0x3A747265
    .WORD 0x2020200A, 0x20494C20, 0x34522020, 0x20203020, 0x20202020, 0x20202020, 0x203B2020, 0x69676944
    .WORD 0x6F632074, 0x65746E75, 0x20200A72, 0x690A2020, 0x5F616F74, 0x65726F63, 0x7669645F, 0x706F6F6C
    .WORD 0x20200A3A, 0x4F4D2020, 0x52202056, 0x39522035, 0x2020200A, 0x56494420, 0x36522020, 0x20355220
    .WORD 0x20313152, 0x20202020, 0x203B2020, 0x3D203652, 0x6F757120, 0x6E656974, 0x52202C74, 0x203D2039
    .WORD 0x616D6572, 0x65646E69, 0x20200A72, 0x4F4D2020, 0x52202044, 0x39522037, 0x31315220, 0x20202020
    .WORD 0x3B202020, 0x20375220, 0x6572203D, 0x6E69616D, 0x0A726564, 0x20202020, 0x2020200A, 0x43203B20
    .WORD 0x65766E6F, 0x64207472, 0x74696769, 0x206F7420, 0x49435341, 0x61622049, 0x20646573, 0x62206E6F
    .WORD 0x0A657361, 0x20202020, 0x20504D43, 0x31315220, 0x0A363120, 0x20202020, 0x20514542, 0x6F746920
    .WORD 0x6F635F61, 0x685F6572, 0x645F7865, 0x74696769, 0x2020200A, 0x20200A20, 0x203B2020, 0x65736142
    .WORD 0x6F203220, 0x30312072, 0x6964203A, 0x20746967, 0x0A392D30, 0x20202020, 0x20444441, 0x20375220
    .WORD 0x34203752, 0x20202038, 0x20202020, 0x27203B20, 0x2B202730, 0x67696420, 0x200A7469, 0x42202020
    .WORD 0x20202020, 0x616F7469, 0x726F635F, 0x74735F65, 0x0A65726F, 0x20202020, 0x6F74690A, 0x6F635F61
    .WORD 0x685F6572, 0x645F7865, 0x74696769, 0x20200A3A, 0x203B2020, 0x65736142, 0x3A363120, 0x67696420
    .WORD 0x30207469, 0x0A35312D, 0x20202020, 0x20504D43, 0x20375220, 0x20200A39, 0x47422020, 0x69202054
    .WORD 0x5F616F74, 0x65726F63, 0x7865685F, 0x74656C5F, 0x0A726574, 0x20202020, 0x20444441, 0x20375220
    .WORD 0x34203752, 0x20202038, 0x20202020, 0x27203B20, 0x2B202730, 0x67696420, 0x200A7469, 0x42202020
    .WORD 0x20202020, 0x616F7469, 0x726F635F, 0x74735F65, 0x0A65726F, 0x20202020, 0x6F74690A, 0x6F635F61
    .WORD 0x685F6572, 0x6C5F7865, 0x65747465, 0x200A3A72, 0x53202020, 0x20204255, 0x52203752, 0x30312037
    .WORD 0x2020200A, 0x44444120, 0x37522020, 0x20375220, 0x20203536, 0x20202020, 0x203B2020, 0x20274127
    .WORD 0x6428202B, 0x74696769, 0x2930312D, 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x726F7473
    .WORD 0x200A3A65, 0x53202020, 0x20204254, 0x5B203752, 0x205D3652, 0x20202020, 0x20202020, 0x7453203B
    .WORD 0x2065726F, 0x74206E69, 0x20706D65, 0x66667562, 0x200A7265, 0x41202020, 0x20204444, 0x52203652
    .WORD 0x0A312036, 0x20202020, 0x20444441, 0x20345220, 0x31203452, 0x20202020, 0x20202020, 0x49203B20
    .WORD 0x6572636E, 0x746E656D, 0x67696420, 0x63207469, 0x746E756F, 0x2020200A, 0x20200A20, 0x4F4D2020
    .WORD 0x52202056, 0x35522039, 0x20202020, 0x20202020, 0x3B202020, 0x6F755120, 0x6E656974, 0x65622074
    .WORD 0x656D6F63, 0x656E2073, 0x61762077, 0x0A65756C, 0x20202020, 0x20504D43, 0x20395220, 0x20200A30
    .WORD 0x4E422020, 0x69202045, 0x5F616F74, 0x65726F63, 0x7669645F, 0x706F6F6C, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x6E696F50, 0x6F742074, 0x73616C20, 0x69642074, 0x0A746967, 0x20202020, 0x20425553
    .WORD 0x20365220, 0x31203652, 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x79706F63, 0x20200A3A
    .WORD 0x4D432020, 0x52202050, 0x0A302034, 0x20202020, 0x20514542, 0x6F746920, 0x6F635F61, 0x645F6572
    .WORD 0x0A656E6F, 0x20202020, 0x2020200A, 0x42444C20, 0x32522020, 0x36525B20, 0x2020205D, 0x20202020
    .WORD 0x203B2020, 0x20746547, 0x69676964, 0x72662074, 0x74206D6F, 0x20706D65, 0x76657228, 0x65737265
    .WORD 0x64726F20, 0x0A297265, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B, 0x20202020, 0x20202020
    .WORD 0x53203B20, 0x65726F74, 0x206E6920, 0x74736564, 0x74616E69, 0x0A6E6F69, 0x20202020, 0x20444441
    .WORD 0x20385220, 0x31203852, 0x2020200A, 0x42555320, 0x36522020, 0x20365220, 0x20200A31, 0x55532020
    .WORD 0x52202042, 0x34522034, 0x200A3120, 0x42202020, 0x20202020, 0x616F7469, 0x726F635F, 0x6F635F65
    .WORD 0x200A7970, 0x0A202020, 0x616F7469, 0x726F635F, 0x6F645F65, 0x0A3A656E, 0x20202020, 0x2020494C
    .WORD 0x20325220, 0x20200A30, 0x54532020, 0x52202042, 0x525B2032, 0x20205D38, 0x20202020, 0x3B202020
    .WORD 0x6C754E20, 0x6574206C, 0x6E696D72, 0x0A657461, 0x20202020, 0x6F74690A, 0x6F635F61, 0x665F6572
    .WORD 0x73696E69, 0x200A3A68, 0x50202020, 0x2020504F, 0x200A3552, 0x3B202020, 0x656C4320, 0x75206E61
    .WORD 0x65742070, 0x6220706D, 0x65666675, 0x20200A72, 0x44412020, 0x53202044, 0x50532050, 0x0A355220
    .WORD 0x20202020, 0x2020200A, 0x52203B20, 0x72757465, 0x726F206E, 0x6E696769, 0x70206C61, 0x746E696F
    .WORD 0x200A7265, 0x4D202020, 0x2020564F, 0x52203152, 0x200A3031, 0x0A202020, 0x20202020, 0x20504F50
    .WORD 0x32315220, 0x2020200A, 0x504F5020, 0x31522020, 0x20200A31, 0x4F502020, 0x52202050, 0x200A3031
    .WORD 0x50202020, 0x2020504F, 0x200A3952, 0x50202020, 0x2020504F, 0x200A3852, 0x50202020, 0x2020504F
    .WORD 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920, 0x65645F61, 0x202D2063, 0x69636544, 0x206C616D, 0x766E6F63
    .WORD 0x69737265, 0x77206E6F, 0x70706172, 0x3B0A7265, 0x52203B0A, 0x203D2031, 0x74736564, 0x74616E69
    .WORD 0x206E6F69, 0x66667562, 0x3B0A7265, 0x20325220, 0x6973203D, 0x64656E67, 0x746E6920, 0x72656765
    .WORD 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152, 0x69726F20, 0x616E6967, 0x7562206C, 0x72656666
    .WORD 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A2D2D2D, 0x616F7469, 0x6365645F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020
    .WORD 0x3B202020, 0x78614D20, 0x20313120, 0x69676964, 0x2B207374, 0x67697320, 0x202B206E, 0x6C6C756E
    .WORD 0x31203D20, 0x79622033, 0x0A736574, 0x20202020, 0x2020494C, 0x20335220, 0x20203031, 0x20202020
    .WORD 0x20202020, 0x42203B20, 0x20657361, 0x200A3031, 0x4C202020, 0x20202049, 0x31203452, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6953203B, 0x64656E67, 0x2020200A, 0x20494C20, 0x35522020, 0x20333120
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220, 0x20726566, 0x657A6973, 0x2020200A
    .WORD 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020, 0x2020200A, 0x504F5020, 0x524C2020
    .WORD 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x20786568, 0x6548202D, 0x65646178, 0x616D6963, 0x6F63206C
    .WORD 0x7265766E, 0x6E6F6973, 0x61727720, 0x72657070, 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473
    .WORD 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920
    .WORD 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152, 0x69726F20, 0x616E6967, 0x7562206C
    .WORD 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x7865685F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52
    .WORD 0x200A2020, 0x3B202020, 0x78614D20, 0x64203820, 0x74696769, 0x202B2073, 0x6C6C756E, 0x39203D20
    .WORD 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x31203352, 0x20202036, 0x20202020, 0x20202020
    .WORD 0x6142203B, 0x31206573, 0x20200A36, 0x494C2020, 0x52202020, 0x20302034, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x736E5520, 0x656E6769, 0x73282064, 0x73776F68, 0x77617220, 0x74696220, 0x200A2973
    .WORD 0x4C202020, 0x20202049, 0x39203552, 0x20202020, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D
    .WORD 0x65666675, 0x69732072, 0x200A657A, 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65
    .WORD 0x200A2020, 0x50202020, 0x2020504F, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920, 0x69625F61, 0x202D206E
    .WORD 0x616E6942, 0x63207972, 0x65766E6F, 0x6F697372, 0x7277206E, 0x65707061, 0x0A3B0A72, 0x3152203B
    .WORD 0x64203D20, 0x69747365, 0x6974616E, 0x62206E6F, 0x65666675, 0x203B0A72, 0x3D203252, 0x736E7520
    .WORD 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x75746552, 0x3A736E72, 0x20315220, 0x726F203D
    .WORD 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072, 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F74690A, 0x69625F61, 0x200A3A6E, 0x50202020
    .WORD 0x20485355, 0x200A524C, 0x0A202020, 0x20202020, 0x614D203B, 0x32332078, 0x74696220, 0x202B2073
    .WORD 0x6C6C756E, 0x33203D20, 0x79622033, 0x0A736574, 0x20202020, 0x2020494C, 0x20335220, 0x20202032
    .WORD 0x20202020, 0x20202020, 0x42203B20, 0x20657361, 0x20200A32, 0x494C2020, 0x52202020, 0x20302034
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x736E5520, 0x656E6769, 0x73282064, 0x73776F68, 0x77617220
    .WORD 0x74696220, 0x200A2973, 0x4C202020, 0x20202049, 0x33203552, 0x20202033, 0x20202020, 0x20202020
    .WORD 0x6554203B, 0x6220706D, 0x65666675, 0x69732072, 0x200A657A, 0x43202020, 0x204C4C41, 0x616F7469
    .WORD 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020, 0x2020504F, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920
    .WORD 0x69735F61, 0x64656E67, 0x7865685F, 0x53202D20, 0x656E6769, 0x65682064, 0x65646178, 0x616D6963
    .WORD 0x7277206C, 0x65707061, 0x0A3B0A72, 0x3152203B, 0x64203D20, 0x69747365, 0x6974616E, 0x62206E6F
    .WORD 0x65666675, 0x203B0A72, 0x3D203252, 0x67697320, 0x2064656E, 0x65746E69, 0x0A726567, 0x6552203B
    .WORD 0x6E727574, 0x52203A73, 0x203D2031, 0x6769726F, 0x6C616E69, 0x66756220, 0x20726566, 0x6E696F70
    .WORD 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D
    .WORD 0x5F616F74, 0x6E676973, 0x685F6465, 0x0A3A7865, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020
    .WORD 0x2020200A, 0x4D203B20, 0x38207861, 0x67696420, 0x20737469, 0x6973202B, 0x2B206E67, 0x6C756E20
    .WORD 0x203D206C, 0x62203031, 0x73657479, 0x2020200A, 0x20494C20, 0x33522020, 0x20363120, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x65736142, 0x0A363120, 0x20202020, 0x2020494C, 0x20345220, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x53203B20, 0x656E6769, 0x73282064, 0x73776F68, 0x67697320, 0x200A296E
    .WORD 0x4C202020, 0x20202049, 0x31203552, 0x20202030, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D
    .WORD 0x65666675, 0x69732072, 0x200A657A, 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65
    .WORD 0x200A2020, 0x50202020, 0x2020504F, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920, 0x69735F61, 0x64656E67
    .WORD 0x6E69625F, 0x53202D20, 0x656E6769, 0x69622064, 0x7972616E, 0x61727720, 0x72657070, 0x3B0A3B0A
    .WORD 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032
    .WORD 0x6E676973, 0x69206465, 0x6765746E, 0x3B0A7265, 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20
    .WORD 0x69676972, 0x206C616E, 0x66667562, 0x70207265, 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x74690A2D, 0x735F616F, 0x656E6769, 0x69625F64
    .WORD 0x200A3A6E, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020, 0x20202020, 0x614D203B, 0x32332078
    .WORD 0x74696220, 0x202B2073, 0x6E676973, 0x6E202B20, 0x206C6C75, 0x3433203D, 0x74796220, 0x200A7365
    .WORD 0x4C202020, 0x20202049, 0x32203352, 0x20202020, 0x20202020, 0x20202020, 0x6142203B, 0x32206573
    .WORD 0x2020200A, 0x20494C20, 0x34522020, 0x20203120, 0x20202020, 0x20202020, 0x203B2020, 0x6E676953
    .WORD 0x28206465, 0x776F6873, 0x69732073, 0x0A296E67, 0x20202020, 0x2020494C, 0x20355220, 0x20203433
    .WORD 0x20202020, 0x20202020, 0x54203B20, 0x20706D65, 0x66667562, 0x73207265, 0x0A657A69, 0x20202020
    .WORD 0x4C4C4143, 0x6F746920, 0x6F635F61, 0x200A6572, 0x0A202020, 0x20202020, 0x20504F50, 0x0A524C20
    .WORD 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x73203B0A, 0x70637274
    .WORD 0x65642879, 0x202C7473, 0x29637273, 0x3B0A3B0A, 0x706F4320, 0x20736569, 0x69727473, 0x6620676E
    .WORD 0x206D6F72, 0x20637273, 0x64206F74, 0x20747365, 0x6C636E69, 0x6E696475, 0x65742067, 0x6E696D72
    .WORD 0x6E697461, 0x756E2067, 0x63206C6C, 0x61726168, 0x72657463, 0x3B0A3B0A, 0x706E4920, 0x0A3A7475
    .WORD 0x2020203B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x696F7020, 0x7265746E, 0x20203B0A
    .WORD 0x20325220, 0x6F73203D, 0x65637275, 0x696F7020, 0x7265746E, 0x3B0A3B0A, 0x74754F20, 0x3A747570
    .WORD 0x20203B0A, 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x6F70206E, 0x65746E69, 0x6F282072
    .WORD 0x69676972, 0x296C616E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x7274730A, 0x3A797063
    .WORD 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x564F4D20, 0x20335220, 0x20203152, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6153203B, 0x6F206576, 0x69676972, 0x206C616E, 0x74736564, 0x74616E69
    .WORD 0x206E6F69, 0x6E696F70, 0x0A726574, 0x20202020, 0x20564F4D, 0x52203452, 0x20202032, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x76615320, 0x6F732065, 0x65637275, 0x696F7020, 0x7265746E, 0x2020200A
    .WORD 0x74730A20, 0x79706372, 0x6F6F6C5F, 0x200A3A70, 0x4C202020, 0x52204244, 0x525B2032, 0x20205D34
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x64616F4C, 0x74796220, 0x72662065, 0x73206D6F, 0x6372756F
    .WORD 0x20200A65, 0x54532020, 0x32522042, 0x31525B20, 0x2020205D, 0x20202020, 0x20202020, 0x53203B20
    .WORD 0x65726F74, 0x74796220, 0x6F742065, 0x73656420, 0x616E6974, 0x6E6F6974, 0x2020200A, 0x20200A20
    .WORD 0x4D432020, 0x32522050, 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x43203B20, 0x6B636568
    .WORD 0x20666920, 0x73277469, 0x6C756E20, 0x6574206C, 0x6E696D72, 0x726F7461, 0x2020200A, 0x51454220
    .WORD 0x72747320, 0x5F797063, 0x656E6F64, 0x20202020, 0x20202020, 0x6649203B, 0x72657A20, 0x77202C6F
    .WORD 0x65722765, 0x6E6F6420, 0x20200A65, 0x200A2020, 0x41202020, 0x52204444, 0x31522031, 0x20203120
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x61766441, 0x2065636E, 0x74736564, 0x74616E69, 0x206E6F69
    .WORD 0x6E696F70, 0x0A726574, 0x20202020, 0x20444441, 0x52203452, 0x20312034, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x76644120, 0x65636E61, 0x756F7320, 0x20656372, 0x6E696F70, 0x0A726574, 0x20202020
    .WORD 0x74732042, 0x79706372, 0x6F6F6C5F, 0x20200A70, 0x730A2020, 0x70637274, 0x6F645F79, 0x0A3A656E
    .WORD 0x20202020, 0x20564F4D, 0x52203152, 0x20202033, 0x20202020, 0x20202020, 0x3B202020, 0x74655220
    .WORD 0x206E7275, 0x6769726F, 0x6C616E69, 0x73656420, 0x616E6974, 0x6E6F6974, 0x696F7020, 0x7265746E
    .WORD 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x203B0A3D, 0x45524944, 0x524F5443, 0x504F2059, 0x54415245, 0x534E4F49, 0x4D202D20
    .WORD 0x68637461, 0x20676E69, 0x72756F79, 0x72656B20, 0x276C656E, 0x61742073, 0x5F736672, 0x64616572
    .WORD 0x0A726964, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x44203B0A, 0x63657269, 0x79726F74, 0x72747320, 0x75746375, 0x28206572, 0x7161706F
    .WORD 0x74206575, 0x7375206F, 0x0A297265, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x5551452E
    .WORD 0x52494420, 0x2C44465F, 0x20202020, 0x30202020, 0x20202020, 0x3B202020, 0x6C694620, 0x65642065
    .WORD 0x69726373, 0x726F7470, 0x20342820, 0x65747962, 0x2E0A2973, 0x20555145, 0x5F524944, 0x5346464F
    .WORD 0x202C5445, 0x20342020, 0x20202020, 0x203B2020, 0x72727543, 0x20746E65, 0x69736F70, 0x6E6F6974
    .WORD 0x206E6920, 0x65726964, 0x726F7463, 0x74732079, 0x6D616572, 0x20342820, 0x65747962, 0x20202973
    .WORD 0x51452E0A, 0x49442055, 0x49535F52, 0x464F455A, 0x2020202C, 0x3B0A0A38, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x65706F20, 0x7269646E, 0x4F202D20, 0x206E6570, 0x69642061, 0x74636572
    .WORD 0x2079726F, 0x20726F66, 0x64616572, 0x0A676E69, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x6170203D
    .WORD 0x28206874, 0x6C6C756E, 0x7265742D, 0x616E696D, 0x20646574, 0x69727473, 0x0A29676E, 0x554F203B
    .WORD 0x52203A54, 0x203D2031, 0x2A524944, 0x61682820, 0x656C646E, 0x726F2029, 0x6F203020, 0x7265206E
    .WORD 0x0A726F72, 0x203B0A3B, 0x6E65704F, 0x20612073, 0x65726964, 0x726F7463, 0x69662079, 0x6120656C
    .WORD 0x7220646E, 0x72757465, 0x6120736E, 0x6E616820, 0x20656C64, 0x20726F66, 0x64616572, 0x0A726964
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6E65706F, 0x3A726964, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A
    .WORD 0x20200A20, 0x4F4D2020, 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x76615320
    .WORD 0x61702065, 0x200A6874, 0x3B202020, 0x65704F20, 0x6964206E, 0x74636572, 0x2079726F, 0x68746977
    .WORD 0x61657220, 0x6E6F2D64, 0x6620796C, 0x7367616C, 0x61732820, 0x6120656D, 0x6F792073, 0x6C207275
    .WORD 0x73612E73, 0x200A296D, 0x4D202020, 0x5220564F, 0x38522031, 0x2020200A, 0x20494C20, 0x20325220
    .WORD 0x44525F4F, 0x594C4E4F, 0x2020200A, 0x43565320, 0x53595320, 0x45504F5F, 0x20200A4E, 0x4F4D2020
    .WORD 0x39522056, 0x20315220, 0x20202020, 0x20202020, 0x663B2020, 0x20200A64, 0x4D432020, 0x31522050
    .WORD 0x200A3020, 0x42202020, 0x6F20544C, 0x646E6570, 0x655F7269, 0x726F7272, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x6F6C6C41, 0x65746163, 0x52494420, 0x72747320, 0x75746375, 0x28206572, 0x6C616D73
    .WORD 0x6A202C6C, 0x20747375, 0x61206466, 0x6F20646E, 0x65736666, 0x200A2974, 0x50202020, 0x20485355
    .WORD 0x20203952, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x65766173, 0x20395220, 0x0A63696A
    .WORD 0x20202020, 0x5220494C, 0x49442031, 0x49535F52, 0x464F455A, 0x2020200A, 0x4C414320, 0x616D204C
    .WORD 0x636F6C6C, 0x2020200A, 0x504F5020, 0x39522020, 0x20200A0A, 0x4D432020, 0x31522050, 0x200A3020
    .WORD 0x42202020, 0x6F205145, 0x646E6570, 0x655F7269, 0x726F7272, 0x6F6C635F, 0x200A6573, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x53203B20, 0x20657661
    .WORD 0x2A524944, 0x2020200A, 0x20200A20, 0x203B2020, 0x74696E49, 0x696C6169, 0x4420657A, 0x73205249
    .WORD 0x63757274, 0x65727574, 0x2020200A, 0x52203B20, 0x74732032, 0x206C6C69, 0x20736168, 0x66206466
    .WORD 0x206D6F72, 0x6E65706F, 0x2020200A, 0x57545320, 0x20395220, 0x2038525B, 0x4944202B, 0x44465F52
    .WORD 0x20200A5D, 0x494C2020, 0x32522020, 0x200A3020, 0x53202020, 0x52205754, 0x525B2032, 0x202B2038
    .WORD 0x5F524944, 0x5346464F, 0x0A5D5445, 0x20202020, 0x2020200A, 0x564F4D20, 0x20315220, 0x20203852
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x75746552, 0x44206E72, 0x0A2A5249, 0x20202020, 0x706F2042
    .WORD 0x69646E65, 0x6F645F72, 0x200A656E, 0x0A202020, 0x6E65706F, 0x5F726964, 0x6F727265, 0x6C635F72
    .WORD 0x3A65736F, 0x2020200A, 0x564F4D20, 0x20315220, 0x20203952, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x69206466, 0x6E692073, 0x0A395220, 0x20202020, 0x20435653, 0x5F535953, 0x534F4C43, 0x20200A45
    .WORD 0x494C2020, 0x20315220, 0x20200A30, 0x20422020, 0x6E65706F, 0x5F726964, 0x656E6F64, 0x2020200A
    .WORD 0x706F0A20, 0x69646E65, 0x72655F72, 0x3A726F72, 0x2020200A, 0x20494C20, 0x30203152, 0x2020200A
    .WORD 0x706F0A20, 0x69646E65, 0x6F645F72, 0x0A3A656E, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020
    .WORD 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x64616572, 0x20726964, 0x6552202D, 0x6E206461, 0x20747865
    .WORD 0x65726964, 0x726F7463, 0x6E652079, 0x0A797274, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x4944203D
    .WORD 0x28202A52, 0x6D6F7266, 0x65706F20, 0x7269646E, 0x203B0A29, 0x20202020, 0x20325220, 0x6F70203D
    .WORD 0x65746E69, 0x6F742072, 0x72747320, 0x20746375, 0x65726964, 0x7420746E, 0x6966206F, 0x3B0A6C6C
    .WORD 0x54554F20, 0x3152203A, 0x31203D20, 0x20666920, 0x72746E65, 0x65722079, 0x202C6461, 0x66692030
    .WORD 0x206F6E20, 0x65726F6D, 0x746E6520, 0x73656972, 0x312D202C, 0x206E6F20, 0x6F727265, 0x0A3B0A72
    .WORD 0x6552203B, 0x20736461, 0x20656874, 0x7478656E, 0x72696420, 0x6F746365, 0x65207972, 0x7972746E
    .WORD 0x69737520, 0x7420676E, 0x6B206568, 0x656E7265, 0x2073276C, 0x64616572, 0x20726964, 0x20616976
    .WORD 0x5F535953, 0x44414552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6165720A, 0x72696464
    .WORD 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x55502020
    .WORD 0x52204853, 0x20200A39, 0x200A2020, 0x4D202020, 0x5220564F, 0x31522038, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x4944203B, 0x200A2A52, 0x4D202020, 0x5220564F, 0x32522039, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x7355203B, 0x73277265, 0x72696420, 0x20746E65, 0x66667562, 0x200A7265, 0x0A202020
    .WORD 0x20202020, 0x6843203B, 0x206B6365, 0x44206669, 0x70205249, 0x746E696F, 0x69207265, 0x61762073
    .WORD 0x0A64696C, 0x20202020, 0x20504D43, 0x30203852, 0x2020200A, 0x51454220, 0x61657220, 0x72696464
    .WORD 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020, 0x6552203B, 0x6F206461, 0x6420656E, 0x6E657269
    .WORD 0x72662074, 0x64206D6F, 0x63657269, 0x79726F74, 0x20646620, 0x6E697375, 0x75632067, 0x6E657272
    .WORD 0x666F2074, 0x74657366, 0x2020200A, 0x57444C20, 0x20315220, 0x2038525B, 0x4944202B, 0x44465F52
    .WORD 0x203B205D, 0x200A6466, 0x0A202020, 0x20202020, 0x7355203B, 0x68742065, 0x69642065, 0x74636572
    .WORD 0x2779726F, 0x666F2073, 0x74657366, 0x77202D20, 0x656E2065, 0x74206465, 0x6D69206F, 0x6D656C70
    .WORD 0x20746E65, 0x6565736C, 0x726F206B, 0x65737520, 0x2020200A, 0x74203B20, 0x66206568, 0x20746361
    .WORD 0x74616874, 0x63616520, 0x65722068, 0x67206461, 0x20737465, 0x20656E6F, 0x65726964, 0x6120746E
    .WORD 0x20612074, 0x656D6974, 0x6F726620, 0x6174206D, 0x0A736672, 0x20202020, 0x20564F4D, 0x52203252
    .WORD 0x20202039, 0x20202020, 0x20202020, 0x75203B20, 0x20726573, 0x66667562, 0x200A7265, 0x4C202020
    .WORD 0x52202049, 0x49442033, 0x544E4552, 0x5A49535F, 0x20464F45, 0x6973203B, 0x6F20657A, 0x6E6F2066
    .WORD 0x69642065, 0x746E6572, 0x2020200A, 0x43565320, 0x53595320, 0x4145525F, 0x20200A44, 0x4D432020
    .WORD 0x31522050, 0x200A3020, 0x42202020, 0x72205145, 0x64646165, 0x655F7269, 0x2020646E, 0x20202020
    .WORD 0x4F45203B, 0x20200A46, 0x4D432020, 0x31522050, 0x52494420, 0x5F544E45, 0x455A4953, 0x200A464F
    .WORD 0x42202020, 0x7220454E, 0x64646165, 0x655F7269, 0x726F7272, 0x20202020, 0x6853203B, 0x2074726F
    .WORD 0x64616572, 0x20726F20, 0x6F727265, 0x20200A72, 0x200A2020, 0x3B202020, 0x746E4520, 0x72207972
    .WORD 0x20646165, 0x63637573, 0x66737365, 0x796C6C75, 0x2020200A, 0x55203B20, 0x74616470, 0x68742065
    .WORD 0x666F2065, 0x74657366, 0x206E6920, 0x20524944, 0x75727473, 0x72757463, 0x20200A65, 0x444C2020
    .WORD 0x32522057, 0x38525B20, 0x44202B20, 0x4F5F5249, 0x45534646, 0x200A5D54, 0x41202020, 0x52204444
    .WORD 0x32522032, 0x200A3120, 0x53202020, 0x52205754, 0x525B2032, 0x202B2038, 0x5F524944, 0x5346464F
    .WORD 0x0A5D5445, 0x20202020, 0x2020200A, 0x20494C20, 0x31203152, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x75746552, 0x73206E72, 0x65636375, 0x200A7373, 0x42202020, 0x61657220, 0x72696464
    .WORD 0x6E6F645F, 0x20200A65, 0x720A2020, 0x64646165, 0x655F7269, 0x726F7272, 0x20200A3A, 0x494C2020
    .WORD 0x20315220, 0x200A312D, 0x42202020, 0x61657220, 0x72696464, 0x6E6F645F, 0x20200A65, 0x720A2020
    .WORD 0x64646165, 0x655F7269, 0x0A3A646E, 0x20202020, 0x5220494C, 0x0A302031, 0x20202020, 0x6165720A
    .WORD 0x72696464, 0x6E6F645F, 0x200A3A65, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050
    .WORD 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x63203B0A, 0x65736F6C, 0x20726964, 0x6C43202D, 0x2065736F, 0x65726964, 0x726F7463
    .WORD 0x74732079, 0x6D616572, 0x3B0A3B0A, 0x3A4E4920, 0x31522020, 0x44203D20, 0x0A2A5249, 0x554F203B
    .WORD 0x52203A54, 0x203D2031, 0x6E6F2030, 0x63757320, 0x73736563, 0x312D202C, 0x206E6F20, 0x6F727265
    .WORD 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C630A2D, 0x6465736F, 0x0A3A7269, 0x20202020
    .WORD 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x2020200A, 0x564F4D20
    .WORD 0x20385220, 0x200A3152, 0x43202020, 0x5220504D, 0x0A302038, 0x20202020, 0x20514542, 0x736F6C63
    .WORD 0x72696465, 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020, 0x6C43203B, 0x2065736F, 0x20656874
    .WORD 0x65726964, 0x726F7463, 0x64662079, 0x2020200A, 0x57444C20, 0x20315220, 0x2038525B, 0x4944202B
    .WORD 0x44465F52, 0x20200A5D, 0x56532020, 0x59532043, 0x4C435F53, 0x0A45534F, 0x20202020, 0x2020200A
    .WORD 0x46203B20, 0x20656572, 0x20656874, 0x20524944, 0x75727473, 0x72757463, 0x20200A65, 0x4F4D2020
    .WORD 0x31522056, 0x0A385220, 0x20202020, 0x4C4C4143, 0x65726620, 0x20200A65, 0x200A2020, 0x4C202020
    .WORD 0x31522049, 0x200A3020, 0x42202020, 0x6F6C6320, 0x69646573, 0x6F645F72, 0x200A656E, 0x0A202020
    .WORD 0x736F6C63, 0x72696465, 0x7272655F, 0x0A3A726F, 0x20202020, 0x5220494C, 0x312D2031, 0x2020200A
    .WORD 0x6C630A20, 0x6465736F, 0x645F7269, 0x3A656E6F, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020
    .WORD 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x6572203B, 0x646E6977, 0x20726964, 0x6552202D, 0x20746573, 0x65726964, 0x726F7463, 0x74732079
    .WORD 0x6D616572, 0x206F7420, 0x69676562, 0x6E696E6E, 0x0A3B0A67, 0x4E49203B, 0x5220203A, 0x203D2031
    .WORD 0x2A524944, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x7765720A, 0x64646E69, 0x0A3A7269
    .WORD 0x20202020, 0x20504D43, 0x30203152, 0x2020200A, 0x51454220, 0x77657220, 0x64646E69, 0x645F7269
    .WORD 0x0A656E6F, 0x20202020, 0x2020200A, 0x20494C20, 0x30203252, 0x2020200A, 0x57545320, 0x20325220
    .WORD 0x2031525B, 0x4944202B, 0x464F5F52, 0x54455346, 0x20200A5D, 0x200A2020, 0x3B202020, 0x65654E20
    .WORD 0x6F742064, 0x65657320, 0x6F74206B, 0x67656220, 0x696E6E69, 0x6F20676E, 0x69642066, 0x74636572
    .WORD 0x0A79726F, 0x20202020, 0x6F46203B, 0x61742072, 0x2C736672, 0x69687420, 0x656D2073, 0x20736E61
    .WORD 0x736F6C63, 0x20676E69, 0x20646E61, 0x706F6572, 0x6E696E65, 0x6F202C67, 0x73752072, 0x20676E69
    .WORD 0x6565736C, 0x20200A6B, 0x203B2020, 0x706D6953, 0x6120656C, 0x6F727070, 0x3A686361, 0x6F6C6320
    .WORD 0x61206573, 0x7220646E, 0x65706F65, 0x20200A6E, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020
    .WORD 0x52204853, 0x20200A38, 0x200A2020, 0x4D202020, 0x5220564F, 0x31522038, 0x2020200A, 0x53203B20
    .WORD 0x20657661, 0x20656874, 0x68746170, 0x77202D20, 0x6F642065, 0x2074276E, 0x65766168, 0x20746920
    .WORD 0x726F7473, 0x202C6465, 0x74206F73, 0x20736968, 0x74207369, 0x6B636972, 0x20200A79, 0x203B2020
    .WORD 0x61206E49, 0x61657220, 0x6D69206C, 0x6D656C70, 0x61746E65, 0x6E6F6974, 0x7473202C, 0x2065726F
    .WORD 0x68746170, 0x206E6920, 0x20524944, 0x75727473, 0x72757463, 0x20200A65, 0x200A2020, 0x3B202020
    .WORD 0x726F4620, 0x776F6E20, 0x756A202C, 0x72207473, 0x74657365, 0x66666F20, 0x20746573, 0x20646E61
    .WORD 0x796C6572, 0x206E6F20, 0x64616572, 0x27726964, 0x65622073, 0x69766168, 0x200A726F, 0x0A202020
    .WORD 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x720A2020, 0x6E697765
    .WORD 0x72696464, 0x6E6F645F, 0x200A3A65, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A2D2D2D, 0x6964203B, 0x20646672, 0x6547202D, 0x69662074, 0x6420656C, 0x72637365, 0x6F747069
    .WORD 0x72662072, 0x44206D6F, 0x0A2A5249, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x4944203D, 0x3B0A2A52
    .WORD 0x54554F20, 0x3152203A, 0x66203D20, 0x20656C69, 0x63736564, 0x74706972, 0x202C726F, 0x2D20726F
    .WORD 0x6E6F2031, 0x72726520, 0x3B0A726F, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x640A2D2D, 0x64667269
    .WORD 0x20200A3A, 0x4D432020, 0x31522050, 0x200A3020, 0x42202020, 0x64205145, 0x64667269, 0x7272655F
    .WORD 0x200A726F, 0x0A202020, 0x20202020, 0x2057444C, 0x5B203152, 0x2B203152, 0x52494420, 0x5D44465F
    .WORD 0x2020200A, 0x54455220, 0x2020200A, 0x69640A20, 0x5F646672, 0x6F727265, 0x200A3A72, 0x4C202020
    .WORD 0x31522049, 0x0A312D20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x48203B0A, 0x65706C65, 0x69203A72, 0x69645F73, 0x202D2072, 0x63656843, 0x6669206B, 0x70206120
    .WORD 0x20687461, 0x61207369, 0x72696420, 0x6F746365, 0x3B0A7972, 0x49203B0A, 0x20203A4E, 0x3D203152
    .WORD 0x74617020, 0x203B0A68, 0x3A54554F, 0x20315220, 0x2031203D, 0x64206669, 0x63657269, 0x79726F74
    .WORD 0x2030202C, 0x6E206669, 0x202C746F, 0x6F20312D, 0x7265206E, 0x0A726F72, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x645F7369, 0x0A3A7269, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020
    .WORD 0x2020200A, 0x54203B20, 0x74207972, 0x706F206F, 0x61206E65, 0x69642073, 0x74636572, 0x0A79726F
    .WORD 0x20202020, 0x4C4C4143, 0x65706F20, 0x7269646E, 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30
    .WORD 0x45422020, 0x73692051, 0x7269645F, 0x746F6E5F, 0x7269645F, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x6F207449, 0x656E6570, 0x73612064, 0x64206120, 0x63657269, 0x79726F74, 0x2020200A, 0x564F4D20
    .WORD 0x20325220, 0x20203152, 0x20202020, 0x20202020, 0x203B2020, 0x65766153, 0x52494420, 0x20200A2A
    .WORD 0x494C2020, 0x20315220, 0x20202031, 0x20202020, 0x20202020, 0x3B202020, 0x74655220, 0x206E7275
    .WORD 0x65757274, 0x2020200A, 0x4C414320, 0x6C63204C, 0x6465736F, 0x20207269, 0x20202020, 0x203B2020
    .WORD 0x736F6C43, 0x74692065, 0x2020200A, 0x69204220, 0x69645F73, 0x6F645F72, 0x200A656E, 0x0A202020
    .WORD 0x645F7369, 0x6E5F7269, 0x645F746F, 0x0A3A7269, 0x20202020, 0x5220494C, 0x0A302031, 0x20202020
    .WORD 0x5F73690A, 0x5F726964, 0x656E6F64, 0x20200A3A, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220
    .WORD 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6D617845, 0x20656C70, 0x67617375
    .WORD 0x75662065, 0x6974636E, 0x2D206E6F, 0x73696C20, 0x69642074, 0x74636572, 0x2079726F, 0x746E6F63
    .WORD 0x73746E65, 0x696C2820, 0x6C20656B, 0x3B0A2973, 0x69685420, 0x65642073, 0x736E6F6D, 0x74617274
    .WORD 0x68207365, 0x7420776F, 0x7375206F, 0x706F2065, 0x69646E65, 0x65722F72, 0x69646461, 0x6C632F72
    .WORD 0x6465736F, 0x3B0A7269, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C0A2D2D, 0x5F747369, 0x65726964
    .WORD 0x726F7463, 0x200A3A79, 0x50202020, 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852
    .WORD 0x50202020, 0x20485355, 0x200A3952, 0x0A202020, 0x20202020, 0x20564F4D, 0x52203852, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x70203B20, 0x0A687461, 0x20202020, 0x2020200A, 0x41203B20, 0x636F6C6C
    .WORD 0x20657461, 0x65726964, 0x6F20746E, 0x7473206E, 0x0A6B6361, 0x20202020, 0x20425553, 0x53205053
    .WORD 0x49442050, 0x544E4552, 0x5A49535F, 0x0A464F45, 0x20202020, 0x20564F4D, 0x53203952, 0x20200A50
    .WORD 0x200A2020, 0x3B202020, 0x65704F20, 0x6964206E, 0x74636572, 0x0A79726F, 0x20202020, 0x20564F4D
    .WORD 0x52203152, 0x20200A38, 0x41432020, 0x6F204C4C, 0x646E6570, 0x200A7269, 0x43202020, 0x5220504D
    .WORD 0x0A302031, 0x20202020, 0x20514542, 0x7473696C, 0x7269645F, 0x7272655F, 0x200A726F, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x44203B20, 0x0A2A5249
    .WORD 0x20202020, 0x73696C0A, 0x69645F74, 0x6F6C5F72, 0x0A3A706F, 0x20202020, 0x20564F4D, 0x52203152
    .WORD 0x20200A38, 0x4F4D2020, 0x32522056, 0x0A395220, 0x20202020, 0x4C4C4143, 0x61657220, 0x72696464
    .WORD 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30, 0x45422020, 0x696C2051, 0x645F7473, 0x635F7269
    .WORD 0x65736F6C, 0x2020200A, 0x20494C20, 0x20325220, 0x200A312D, 0x43202020, 0x5220504D, 0x32522031
    .WORD 0x2020200A, 0x51454220, 0x73696C20, 0x69645F74, 0x72655F72, 0x0A726F72, 0x20202020, 0x2020200A
    .WORD 0x50203B20, 0x746E6972, 0x65687420, 0x6D616E20, 0x20200A65, 0x44412020, 0x31522044, 0x20395220
    .WORD 0x45524944, 0x4E5F544E, 0x0A454D41, 0x20202020, 0x4C4C4143, 0x74757020, 0x20200A73, 0x200A2020
    .WORD 0x3B202020, 0x20664920, 0x73277469, 0x64206120, 0x63657269, 0x79726F74, 0x7270202C, 0x20746E69
    .WORD 0x0A272F27, 0x20202020, 0x2057444C, 0x5B203252, 0x2B203952, 0x52494420, 0x5F544E45, 0x45505954
    .WORD 0x20200A5D, 0x4D432020, 0x32522050, 0x5F544420, 0x0A524944, 0x20202020, 0x20454E42, 0x7473696C
    .WORD 0x7269645F, 0x746F6E5F, 0x7269645F, 0x2020200A, 0x20200A20, 0x494C2020, 0x20315220, 0x73616C73
    .WORD 0x68635F68, 0x200A7261, 0x43202020, 0x204C4C41, 0x63747570, 0x0A726168, 0x20202020, 0x73696C0A
    .WORD 0x69645F74, 0x6F6E5F72, 0x69645F74, 0x200A3A72, 0x4C202020, 0x31522049, 0x77656E20, 0x656E696C
    .WORD 0x6168635F, 0x20200A72, 0x41432020, 0x70204C4C, 0x68637475, 0x200A7261, 0x0A202020, 0x20202020
    .WORD 0x696C2042, 0x645F7473, 0x6C5F7269, 0x0A706F6F, 0x20202020, 0x73696C0A, 0x69645F74, 0x6C635F72
    .WORD 0x3A65736F, 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3852, 0x43202020, 0x204C4C41, 0x736F6C63
    .WORD 0x72696465, 0x2020200A, 0x20494C20, 0x30203152, 0x2020200A, 0x6C204220, 0x5F747369, 0x5F726964
    .WORD 0x656E6F64, 0x2020200A, 0x696C0A20, 0x645F7473, 0x655F7269, 0x726F7272, 0x20200A3A, 0x494C2020
    .WORD 0x20315220, 0x200A312D, 0x0A202020, 0x7473696C, 0x7269645F, 0x6E6F645F, 0x200A3A65, 0x41202020
    .WORD 0x53204444, 0x50532050, 0x52494420, 0x5F544E45, 0x455A4953, 0x200A464F, 0x50202020, 0x5220504F
    .WORD 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x44203B0A, 0x20617461, 0x74636553, 0x0A6E6F69
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x73616C73, 0x68635F68, 0x0A3A7261, 0x20202020
    .WORD 0x524F572E, 0x37342044, 0x20202020, 0x273B2020, 0x6E0A272F, 0x696C7765, 0x635F656E, 0x3A726168
    .WORD 0x2020200A, 0x4F572E20, 0x31204452, 0x0A0A0A30, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x7270203B, 0x66746E69, 0x2D202928, 0x746F6E20, 0x65282065, 0x2C6F6863, 0x74616320, 0x6873202C
    .WORD 0x7370202C, 0x6E6F6420, 0x656E2074, 0x69206465, 0x65792074, 0x61632074, 0x6562206E, 0x64616D20
    .WORD 0x69772065, 0x70206874, 0x68637475, 0x0A297261, 0x203B0A3B, 0x796E6954, 0x706D6920, 0x656D656C
    .WORD 0x7461746E, 0x206E6F69, 0x796C6E6F, 0x0A3B0A2E, 0x7553203B, 0x726F7070, 0x3A646574, 0x3B0A3B0A
    .WORD 0x25202020, 0x20202025, 0x70202020, 0x65637265, 0x3B0A746E, 0x25202020, 0x203B0A73, 0x64252020
    .WORD 0x20203B0A, 0x0A782520, 0x2020203B, 0x3B0A6325, 0x4E203B0A, 0x6977206F, 0x2E687464, 0x4E203B0A
    .WORD 0x7270206F, 0x73696365, 0x2E6E6F69, 0x4E203B0A, 0x6C66206F, 0x6974616F, 0x7020676E, 0x746E696F
    .WORD 0x0A3B0A2E, 0x614C203B, 0x20726574, 0x696C7073, 0x6E692074, 0x0A3A6F74, 0x203B0A3B, 0x6E697270
    .WORD 0x29286674, 0x76203B0A, 0x6E697270, 0x29286674, 0x76203B0A, 0x72706E73, 0x66746E69, 0x3B0A2928
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x700A2D2D, 0x746E6972, 0x0A0A3A66, 0x20202020, 0x4F54203B
    .WORD 0x200A4F44, 0x3B202020, 0x2020200A, 0x73203B20, 0x206E6163, 0x6D726F66, 0x73207461, 0x6E697274
    .WORD 0x20200A67, 0x203B2020, 0x79706F63, 0x726F6E20, 0x206C616D, 0x72616863, 0x20200A73, 0x203B2020
    .WORD 0x6F636564, 0x25206564, 0x2020200A, 0x64203B20, 0x61707369, 0x20686374, 0x6D726F66, 0x65747461
    .WORD 0x20200A72, 0x0A3B2020, 0x20202020, 0x7325203B, 0x2020200A, 0x25203B20, 0x20200A64, 0x203B2020
    .WORD 0x200A7825, 0x3B202020, 0x0A632520, 0x2020200A, 0x54455220, 0x0A0A0A0A, 0x3D3D3D3B, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x0A3D3D3D, 0x6144203B, 0x53206174, 0x69746365, 0x3B0A6E6F, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x730A3D3D, 0x65636170, 0x7274735F, 0x20200A3A, 0x412E2020, 0x49494353, 0x2022205A
    .WORD 0x6E0A0A22, 0x696C7765, 0x735F656E, 0x0A3A7274, 0x20202020, 0x4353412E, 0x205A4949, 0x226E5C22
    .WORD 0x68630A0A, 0x6675625F, 0x20200A3A, 0x412E2020, 0x49494353, 0x5C22205A, 0x00002230, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

    .SPACE 1024
tarfs_end:
