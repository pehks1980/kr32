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
.EQU KERNEL_USER_ALL, 0x001F   ; P|R|W|X|U, per-task user executable mapping

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
0x00001000       LI R1 0
    ;------------------------------------------------------
    ; bmi_call
    ;
    ; R1 = opcode
    ; R2 = payload pointer
    ; R3 = payload length
    ; R4 = namespace
0x00001008       MOV R1 NS_CREATE
0x0000100C       LI R2 0x00000000
0x00001014       mov r3 r2
0x00001018       mov r4 r2
0x0000101C   CALL bmi_call

0x00001024       MOV R1 FILE_CREATE
0x00001028       LI R2 cr_file
0x00001030       LI R3 13
0x00001038       LI R4 0
0x00001040   CALL bmi_call

0x00001048       MOV R1 FILE_DELETE
0x0000104C       LI R2 cr_file
0x00001054       LI R3 13
0x0000105C       LI R4 0
0x00001064   CALL bmi_call

0x0000106C       ENABLEINT

idle_loop:
0x00001070       ADD R1 R1 1


   ; DEBUG 1
0x00001074       B idle_loop

cr_file:
    .asciiz "etc/crash.txt"

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

init_page_tables0:
0x000020FC       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x00002100       LI R1 page_bitmap
0x00002108       LI R3 16
0x00002110       BL mem_zero

0x00002118       POP LR
0x0000211C       RET

init_page_tables:
0x00002120       PUSH LR

    ; Clear the refcount array
0x00002124       LI R1 page_refcounts
0x0000212C       LI R3 MAX_PHYS_PAGES          ; 128 bytes = 128 pages: 1 byte for ea page (4k)
0x00002134       BL mem_zero                   ; 0 - free, 1 - allocated

    ; Reserve the TAR image page (physical 0xA0000)
    ; index = (0xA0000 - PAGE_ALLOC_BASE) / 4096
    ; PAGE_ALLOC_BASE = 0x50000
    ; (0xA0000 - 0x50000) = 0x50000 = 327680
    ; 327680 / 4096 = 80
0x0000213C       LI R2 80
0x00002144       LI R1 page_refcounts
0x0000214C       ADD R1 R1 R2
0x00002150       LI R3 1
0x00002158       STB R3 [R1]     ;1 = allocated (80 pages for tar image

0x0000215C       POP LR
0x00002160       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x00002164       PUSH LR
0x00002168       PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
0x0000216C       LI R2 0x00000000      ;page 0 - boot (0000)
0x00002174       LI R3 0x00000000
0x0000217C       LI R4 KERNEL_FLAGS
0x00002184       bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x0000218C       LI R2 0x00001000      ; page for kernel buffers
0x00002194       LI R3 0x00001000
0x0000219C       LI R4 KERNEL_FLAGS
0x000021A4       BL map_page

0x000021AC       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x000021B4       LI R3 0x00002000
0x000021BC       LI R4 KERNEL_FLAGS
0x000021C4       BL map_page

0x000021CC       LI R2 0x00003000
0x000021D4       LI R3 0x00003000
0x000021DC       LI R4 KERNEL_FLAGS
0x000021E4       BL map_page

0x000021EC       LI R2 0x00004000
0x000021F4       LI R3 0x00004000
0x000021FC       LI R4 KERNEL_FLAGS
0x00002204       BL map_page

0x0000220C       LI R2 0x00005000
0x00002214       LI R3 0x00005000
0x0000221C       LI R4 KERNEL_FLAGS
0x00002224       BL map_page

0x0000222C       LI R2 0x00006000
0x00002234       LI R3 0x00006000
0x0000223C       LI R4 KERNEL_FLAGS
0x00002244       BL map_page

0x0000224C       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x00002254       LI R3 0x00007000
0x0000225C       LI R4 KERNEL_FLAGS
0x00002264       BL map_page

0x0000226C       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x00002274       LI R3 0x00008000
0x0000227C       LI R4 KERNEL_FLAGS
0x00002284       BL map_page

0x0000228C       LI R2 0x00009000      ; add page (number is page table entry one) tasks data
0x00002294       LI R3 0x00009000
0x0000229C       LI R4 KERNEL_FLAGS
0x000022A4       BL map_page

0x000022AC       LI R2 0x0000A000      ; add page (number is page table entry one) tasks data
0x000022B4       LI R3 0x0000A000
0x000022BC       LI R4 KERNEL_FLAGS
0x000022C4       BL map_page

0x000022CC       LI R2 0x0000B000      ; add page (number is page table entry one) tasks data
0x000022D4       LI R3 0x0000B000
0x000022DC       LI R4 KERNEL_FLAGS
0x000022E4       BL map_page

0x000022EC       LI R2 0x0000C000      ; add page (number is page table entry one) tasks data
0x000022F4       LI R3 0x0000C000
0x000022FC       LI R4 KERNEL_FLAGS
0x00002304       BL map_page

0x0000230C       LI R2 0x00015000      ; page for BMI buffers for NSFS (write) - 4K each
0x00002314       LI R3 0x00015000
0x0000231C       LI R4 KERNEL_FLAGS
0x00002324       BL map_page

0x0000232C       LI R2 0x00016000      ; page for BMI buffers for NSFS (read) - 4K each
0x00002334       LI R3 0x00016000
0x0000233C       LI R4 KERNEL_FLAGS
0x00002344       BL map_page

0x0000234C       LI R2 0x00017000      ; page for BMI buffers for NSFS (read) - 4K each
0x00002354       LI R3 0x00017000
0x0000235C       LI R4 KERNEL_FLAGS
0x00002364       BL map_page




    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x0000236C       LI R2 0x00100000      ; UART physical and virtual base
0x00002374       LI R3 0x00100000
0x0000237C       LI R4 KERNEL_FLAGS
0x00002384       BL map_page

0x0000238C       LI R2 0x00101000      ; PIT physical and virtual base
0x00002394       LI R3 0x00101000
0x0000239C       LI R4 KERNEL_FLAGS
0x000023A4       BL map_page

0x000023AC       LI R2 0x00102000      ; PIC physical and virtual base
0x000023B4       LI R3 0x00102000
0x000023BC       LI R4 KERNEL_FLAGS
0x000023C4       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x000023CC       LI R12 PAGE_ALLOC_BASE
0x000023D4       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x000023DC       CMP R12 R7
0x000023E0       BGE map_common_dynamic_done
0x000023E8       MOV R2 R12
0x000023EC       MOV R3 R12
0x000023F0       LI R4 KERNEL_FLAGS
0x000023F8       BL map_page
0x00002400       LI R6 PAGE_SIZE
0x00002408       ADD R12 R12 R6
0x0000240C       B map_common_dynamic_loop
map_common_dynamic_done:

0x00002414       POP R12
0x00002418       POP LR
0x0000241C       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R4
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002420       PUSH R5
0x00002424       PUSH R6
0x00002428       SHR R5 R2 12               ; VPN
0x0000242C       SHL R5 R5 2                ; page-table byte offset
0x00002430       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002434       STW R6 [R1 + R5]
0x00002438       POP R6
0x0000243C       POP R5
0x00002440       RET

map_page_rt:
    ; Runtime page-table update. Same ABI as map_page, but also invalidates
    ; the cached translation for R2 so permission changes take effect now.
0x00002444       PUSH R5
0x00002448       PUSH R6
0x0000244C       SHR R5 R2 12               ; VPN
0x00002450       SHL R5 R5 2                ; page-table byte offset
0x00002454       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002458       STW R6 [R1 + R5]
0x0000245C       INVLPG R2
0x00002460       POP R6
0x00002464       POP R5
0x00002468       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x0000246C       LI R1 0x00102000
0x00002474       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x0000247C       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x00002480       LI R1 0x00101000
0x00002488       LI R2 2000
0x00002490       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x00002494       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x0000249C       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x000024A0       LI R1 0x00100000
0x000024A8       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000024B0       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x000024B4       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000024B8       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000024BC       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000024C0       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000024C4       PUSH R1
0x000024C8       PUSH R2
0x000024CC       PUSH R3
0x000024D0       PUSH R4
0x000024D4       PUSH R5
0x000024D8       PUSH R6
0x000024DC       PUSH R7
0x000024E0       PUSH R8
0x000024E4       PUSH R9
0x000024E8       PUSH R10
0x000024EC       PUSH R11
0x000024F0       PUSH R12
0x000024F4       PUSH R14
0x000024F8       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x000024FC       CSRR R1 SSCRATCH
0x00002500       PUSH R1
0x00002504       CSRR R1 SEPC
0x00002508       PUSH R1
0x0000250C       CSRR R1 SFLAGS
0x00002510       PUSH R1
0x00002514       CSRR R1 SSTATUS
0x00002518       PUSH R1
0x0000251C       CSRR R1 SCAUSE
0x00002520       PUSH R1
0x00002524       CSRR R1 STVAL
0x00002528       PUSH R1

    ; Dispatch based on scause.
0x0000252C       CSRR R1 SCAUSE
0x00002530       CMP R1 0
0x00002534       BEQ handle_divide_zero

0x0000253C       CMP R1 1
0x00002540       BEQ handle_invalid_instr

0x00002548       CMP R1 2
0x0000254C       BEQ handle_page_fault

0x00002554       CMP R1 3
0x00002558       BEQ handle_syscall

0x00002560       CMP R1 6
0x00002564       BEQ handle_debug

0x0000256C       CMP R1 16
0x00002570       BEQ handle_irq

    ; Unknown cause - halt
0x00002578       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x0000257C       DEBUG 1
0x00002580       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x00002588       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x00002590       HLT

0x00002594       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x0000259C       CSRR R2 STVAL

0x000025A0       CMP R2 SYS_COUNT
0x000025A4       BGE syscall_unknown

0x000025AC       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000025B4       SHL R4 R2 2
0x000025B8       LDW R5 [R3 + R4]
0x000025BC       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000025C0       LI R1 ERR_NOSYS
0x000025C8       STW R1 [SP + TF_R1]
0x000025CC       B trap_restore

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

0x00002618       LDW R8 [SP + TF_R1]        ; user path pointer

0x0000261C       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00002620       PUSH R9

0x00002624       MOV R1 R8
0x00002628       BL copy_path_from_user
0x00002630       CMP R1 0
0x00002634       BEQ execve_badfault

0x0000263C       MOV R12 R1                ; kernel pointer to copied pathname

0x00002640       MOV R1 R12
0x00002644       BL vfs_lookup             ; lookup inode for the file
0x0000264C       CMP R1 0
0x00002650       BEQ execve_noent

0x00002658       MOV R9 R1                 ; inode*
0x0000265C       LDW R1 [R9 + INODE_TYPE]
0x00002660       LI R2 INODE_DIR
0x00002668       CMP R1 R2
0x0000266C       BEQ execve_noexec           ; if the inode is a directory, we cannot execute it

0x00002674       LDW R3 [R9 + INODE_SIZE]
0x00002678       LI R4 PAGE_SIZE         ; 4096 bytes
0x00002680       CMP R3 R4
0x00002684       BGT execve_noexec       ; if the inode size is greater than a page, we cannot execute it

0x0000268C       BL file_alloc
0x00002694       CMP R1 0
0x00002698       BEQ execve_nomem         ; if we cannot allocate a file for this inode, return error

0x000026A0       MOV R10 R1                ; file*
0x000026A4       MOV R1 R10
0x000026A8       MOV R2 R9
0x000026AC       LI R3 FD_FLAG_READ
0x000026B4       BL file_init            ; initialize the file structure for reading the executable

0x000026BC       BL page_alloc           ; allocate a new page for the executable code of execve program
0x000026C4       CMP R1 0
0x000026C8       BEQ execve_noexec_file

0x000026D0       MOV R11 R1                ; new code page PA for execve program

; macro: GET_CURR_TASK_IDX R4    ; get current task index
0x000026D4   LI R1 CURRENT_TASK
0x000026DC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000026E0   LI R1 TASK_SIZE
0x000026E8   MUL R3 R4 R1
0x000026EC   LI R5 tasks
0x000026F4   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12, R5 ; preserve old exec code page PA for rollback / cleanup
0x000026F8   LDW R12 [R5 + TASK_CODE_PAGE]
; macro: TASK_GET_PTBR R1, R5       ; R1 = PTBR of current task
0x000026FC   LDW R1 [R5 + TASK_PTBR]
0x00002700       LI R2 USER_CODE_VA         ; R2 = code page VA for execve program
0x00002708       MOV R3 R11                 ; R3 = code page PA for execve program
0x0000270C       LI R4 USER_RW              ; R4 = temporary RW permissions so we can load the page
0x00002714       BL map_page_rt             ; runtime map executable page RW at USER_CODE_VA for loading

; macro: TASK_GET_DATA_PAGE R1, R5  ; get data page PA for current task
0x0000271C   LDW R1 [R5 + TASK_DATA_PAGE]
0x00002720       CMP R1 0
0x00002724       BEQ execve_data_ok         ; if the task has no data page, skip clearing it
0x0000272C       LI R3 PAGE_SIZE
0x00002734       BL mem_zero                ; zero the current task data page before execve starts

execve_data_ok:

0x0000273C       MOV R1 R10              ; file* of execve program
0x00002740       LI R2 USER_CODE_VA      ; VA of code page for execve program
0x00002748       LI R3 PAGE_SIZE         ; size of code page for execve program
0x00002750       BL file_read            ; load executable into USER_CODE_VA
0x00002758       CMP R1 0
0x0000275C       BLT execve_read_fail    ; if read fails, restore old exec code page and return error

0x00002764       MOV R1 R10              ; file* of execve program
0x00002768       BL file_put             ; release file resources after successful load

; macro: GET_CURR_TASK_IDX R4    ; this was real mistake here! I forgot to retore current task ptr
0x00002770   LI R1 CURRENT_TASK
0x00002778   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4     ; reload task ptr after calls that may clobber caller-saved R5
0x0000277C   LI R1 TASK_SIZE
0x00002784   MUL R3 R4 R1
0x00002788   LI R5 tasks
0x00002790   ADD R5 R5 R3
                            ; we also added INVLPG - for good! - history comments
    ; commit new exec state after successful file load
0x00002794       LI R1 USER_CODE_VA
; macro: TASK_SET_PC R5, R1              ; start execution at USER_CODE_VA
0x0000279C   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5, R11      ; remember physical page backing this user code
0x000027A0   STW R11 [R5 + TASK_CODE_PAGE]
0x000027A4       LI R1 USER_STACK_TOP
; macro: TASK_SET_USP R5, R1             ; reset user stack pointer
0x000027AC   STW R1 [R5 + TASK_USP]
0x000027B0       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5, R1           ; reset program break into the task's data page
0x000027B8   STW R1 [R5 + TASK_BREAK]

    ; Remap the new code page read-only before handing control over
; macro: TASK_GET_PTBR R1, R5            ; get PTBR of current task
0x000027BC   LDW R1 [R5 + TASK_PTBR]
0x000027C0       LI R2 USER_CODE_VA              ; VA of code page for execve program
0x000027C8       MOV R3 R11                      ; PA of code page for execve program
0x000027CC       LI R4 KERNEL_USER_ALL
0x000027D4       BL map_page_rt                  ; switch the new code page from RW to RX

   ; DEBUG 2

0x000027DC       CMP R12 0                       ; R12 = old code page PA for execve program from task metadata
0x000027E0       BEQ execve_commit_done          ; if no previous code page, skip freeing it
0x000027E8       MOV R1 R12
0x000027EC       BL page_put                    ; free the old exec code page now that the new one is committed

execve_commit_done:
    ; Build a fresh Unix-style initial stack:
    ;   [argc][argv pointers...][NULL][string data...]
    ; The new program can read argc/argv from the stack, and we also mirror
    ; argc/argv into R1/R2 for convenience.

0x000027F4       POP R4                         ; remember argv ptr from start of syscall_execve
0x000027F8       LI R6 0                        ; R6 = argc counter

    ; Step 1: Count argc - walk on argv ptrs count argc till  we find NULL check above
0x00002800       MOV R7 R4
execve_argv_count_loop:
0x00002804       CMP R7 0
0x00002808       BEQ execve_argv_count_done
0x00002810       LDW R8 [R7]
0x00002814       CMP R8 0
0x00002818       BEQ execve_argv_count_done

0x00002820       CMP R6 16                      ;MAX argc count
0x00002824       BGE execve_badfault

0x0000282C       ADD R6 R6 1
0x00002830       ADD R7 R7 4
0x00002834       B execve_argv_count_loop

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
0x0000283C       LI  R5 USER_STACK_TOP

    ;-------------------------------------------------------------
    ; Temporary kernel array for argv pointers.
    ; argv_tmp[16]
    ;-------------------------------------------------------------
0x00002844       LI  R11 execve_tmp_argv

    ;-------------------------------------------------------------
    ; Copy strings in reverse order so they naturally pack downward.
    ;-------------------------------------------------------------
0x0000284C       MOV R7 R6
0x00002850       SUB R7 R7 1             ; [argc]-1

execve_copy_reverse:        ; R7(i) = (argc-1 ... 0)
0x00002854       LI  R8 -1
0x0000285C       CMP R7 R8
0x00002860       BEQ execve_strings_done

    ; source string = argv[i] starting from last arg string
0x00002868       MOV R8 R7
0x0000286C       SHL R8 R8 2             ;R7(i)*4+argv ptr => R9(&argv[i])
0x00002870       ADD R9 R4 R8
0x00002874       LDW R10 [R9]            ;get string ptr from last argv[argc-1] (in first iteration)

    ;-------------------------------------------------------------
    ; strlen()
    ; R12 = length including terminating NUL
    ;-------------------------------------------------------------
0x00002878       LI R12 0                ;str len ctr - compute this argv string len (+ 0)

execve_strlen:

0x00002880       LDB R2 [R10 + R12]
0x00002884       ADD R12 R12 1
0x00002888       CMP R2 0
0x0000288C       BNE execve_strlen

    ; reserve space - on user stack top this argv string destination

0x00002894       SUB R5 R5 R12               ; R5 dest addres argv string copy to gets updated by lenght of each string
                                ; to be copied to tmp

    ; remember destination pointer
0x00002898       MOV R8 R7
0x0000289C       SHL R8 R8 2                 ;R7 argv string number in argv array
0x000028A0       ADD R9 R11 R8               ;r9=&temp argv[i]  which is = R7(i)*4+&temp argv[] array storage
0x000028A4       STW R5 [R9]                 ;R5->[R9] string pointer on user stack

    ; memcpy()
0x000028A8       LI R8 0

execve_copy_string:             ; first copy strings ptrs from (argv array) to temp storage
                                ; from last string to first - opposite order
0x000028B0       LDB R2 [R10 + R8]           ; R10 execv argv &string[i]  (last to first)
0x000028B4       STB R2 [R5 + R8]            ; R5 same in tmp

0x000028B8       CMP R2 0
0x000028BC       BEQ execve_copy_done

0x000028C4       ADD R8 R8 1                 ; to next char in string
0x000028C8       B execve_copy_string

execve_copy_done:

0x000028D0       SUB R7 R7 1                 ; to copy next string
0x000028D4       B execve_copy_reverse

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
0x000028DC       MOV R7 R6
0x000028E0       ADD R7 R7 2

0x000028E4       MOV R8 R7
0x000028E8       SHL R8 R8 2

0x000028EC       SUB R5 R5 R8            ;update R5 by stack words

    ;-------------------------------------------------------------
    ; R5 now becomes initial user stack pointer.
    ;-------------------------------------------------------------

0x000028F0       STW R6 [R5]             ; put argc to user stack see picture above (Reserve space for:)

0x000028F4       ADD R9 R5 4             ; R9 - move 'writing head' to next element argv in user stack
                            ; R5 - initial user stack pointer
    ;-------------------------------------------------------------
    ; argv data copied. now - Copy argv pointers
    ;-------------------------------------------------------------
0x000028F8       LI R7 0

execve_copy_argv:

0x00002900       CMP R7 R6
0x00002904       BEQ execve_copy_argv_done

0x0000290C       MOV R8 R7
0x00002910       SHL R8 R8 2              ; R7 argv index

0x00002914       LDW R12 [R11 + R8]       ; we copy stings pointers here (not actual strings!)
                             ; R11 - &execve_tmp_argv
0x00002918       STW R12 [R9 + R8]        ; R9 - write head on user stack

0x0000291C       ADD R7 R7 1
0x00002920       B execve_copy_argv

execve_copy_argv_done:

    ; argv[argc] = NULL
0x00002928       MOV R8 R6
0x0000292C       SHL R8 R8 2
0x00002930       ADD R10 R9 R8

0x00002934       LI R12 0
0x0000293C       STW R12 [R10]               ; write NuLL - finish form user stack frame (arguments part!)

    ;-------------------------------------------------------------
    ; Prepare trapframe for new process.
    ;-------------------------------------------------------------

0x00002940       STW R6 [SP + TF_R1]      ; argc

0x00002944       MOV R1 R9
0x00002948       STW R1 [SP + TF_R2]      ; argv

0x0000294C       LI R1 0
0x00002954       STW R1 [SP + TF_R3]      ; envp

0x00002958       STW R5 [SP + TF_USP]     ; initial user SP


    ; Prepare a fresh user register state for the new program.
0x0000295C       LI R1 0
0x00002964       STW R1 [SP + TF_R4]
0x00002968       STW R1 [SP + TF_R5]
0x0000296C       STW R1 [SP + TF_R6]
0x00002970       STW R1 [SP + TF_R7]
0x00002974       STW R1 [SP + TF_R8]
0x00002978       STW R1 [SP + TF_R9]
0x0000297C       STW R1 [SP + TF_R10]
0x00002980       STW R1 [SP + TF_R11]
0x00002984       STW R1 [SP + TF_R12]
0x00002988       LI R1   USER_CODE_VA               ; user execve program entry point
0x00002990       STW R1 [SP + TF_SEPC]              ; set SEPC to the new program entry point

0x00002994       B trap_restore                     ; restore kernel trapframe and start user execution at user_code_va

; as it should be clear
; if fail occured we rollback depending at what stage fail occured and free used resources
; then we exit back to child process with fail exit code
execve_read_fail:
0x0000299C       MOV R1 R11
0x000029A0       BL page_put                    ; put-free the failed new code page

; macro: GET_CURR_TASK_IDX R4
0x000029A8   LI R1 CURRENT_TASK
0x000029B0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4           ; reload task ptr before restoring USER_CODE_VA mapping
0x000029B4   LI R1 TASK_SIZE
0x000029BC   MUL R3 R4 R1
0x000029C0   LI R5 tasks
0x000029C8   ADD R5 R5 R3

0x000029CC       CMP R12 0
0x000029D0       BEQ execve_restore_no_prev
; macro: TASK_GET_PTBR R1, R5
0x000029D8   LDW R1 [R5 + TASK_PTBR]
0x000029DC       LI R2 USER_CODE_VA
0x000029E4       MOV R3 R12
0x000029E8       LI R4 USER_RX
0x000029F0       BL map_page_rt                ; restore previous exec page mapping at USER_CODE_VA
0x000029F8       MOV R1 R12
; macro: TASK_SET_CODE_PAGE R5, R12    ; restore previous exec code page pointer
0x000029FC   STW R12 [R5 + TASK_CODE_PAGE]
0x00002A00       B execve_restore_done

execve_restore_no_prev:
; macro: TASK_GET_PTBR R1, R5
0x00002A08   LDW R1 [R5 + TASK_PTBR]
0x00002A0C       LI R2 USER_CODE_VA
0x00002A14       LI R3 0
0x00002A1C       LI R4 0
0x00002A24       BL map_page_rt                ; unmap USER_CODE_VA if there was no previous code page
0x00002A2C       LI R1 0
; macro: TASK_SET_CODE_PAGE R5, R1
0x00002A34   STW R1 [R5 + TASK_CODE_PAGE]

execve_restore_done:
0x00002A38       MOV R1 R10
0x00002A3C       BL file_put

0x00002A44       POP R1                      ;save stack
0x00002A48       LI R1 ERR_NOEXEC
0x00002A50       STW R1 [SP + TF_R1]
0x00002A54       B trap_restore

execve_nomem_file:
0x00002A5C       MOV R1 R10
0x00002A60       BL file_put

0x00002A68       POP R1
0x00002A6C       LI R1 ERR_NOMEM
0x00002A74       STW R1 [SP + TF_R1]
0x00002A78       B trap_restore

execve_nomem:
0x00002A80       POP R1
0x00002A84       LI R1 ERR_NOMEM
0x00002A8C       STW R1 [SP + TF_R1]
0x00002A90       B trap_restore

execve_noexec_file:

0x00002A98       MOV R1 R10
0x00002A9C       BL file_put
execve_noexec:
0x00002AA4       POP R1
0x00002AA8       LI R1 ERR_NOEXEC
0x00002AB0       STW R1 [SP + TF_R1]
0x00002AB4       B trap_restore

execve_noent:
0x00002ABC       POP R1
0x00002AC0       LI R1 ERR_NOENT
0x00002AC8       STW R1 [SP + TF_R1]
0x00002ACC       B trap_restore

execve_badfault:
0x00002AD4       POP R1
0x00002AD8       LI R1 ERR_FAULT
0x00002AE0       STW R1 [SP + TF_R1]
0x00002AE4       B trap_restore

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

0x000031F8       LDW R8 [SP + TF_R1]        ; user path pointer
0x000031FC       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00003200       MOV R11 R9                 ; save to R11

0x00003204       LI  R1 exec_path
0x0000320C       MOV R2 R8
0x00003210       LI  R3 EXEC_MAX_PATH
0x00003218       BL copy_user_string        ;copy path string to ws
0x00003220       CMP R1 0
0x00003224       BEQ execve_badfault

    ;init execve ws
0x0000322C       LI R1 exec_argc
0x00003234       LI R2 0
0x0000323C       STW R2 [R1]

    ;count argc

0x00003240       MOV R8 R9               ; user argv
0x00003244       LI  R6 0                ; argc
;count ptrs in array of ptrs argv till 0 -null end
argc_loop:
0x0000324C       CMP R8 0                ;if no argv 0-null
0x00003250       BEQ argc_done
0x00003258       LDW R3 [R8]
0x0000325C       CMP R3 0                ;if end
0x00003260       BEQ argc_done
0x00003268       CMP R6 EXEC_MAX_ARGS    ;if too much MAX argc count
0x0000326C       BGE exec_badfault
0x00003274       ADD R6 R6 1
0x00003278       ADD R8 R8 4
0x0000327C       B argc_loop
argc_done:
0x00003284       LI R1 exec_argc         ;store it to ws
0x0000328C       STW R6 [R1]

0x00003290       MOV R9 R6               ;R9 argc R11 user argv pointer
0x00003294       MOV R8 R11
0x00003298       BL  copy_argv_strings   ;fill arrays in ws from argvs
0x000032A0       CMP R1 0
0x000032A4       BNE exec_fail

0x000032AC       LI R1 exec_path
0x000032B4       BL exec_load_binary
0x000032BC       CMP R1 0
0x000032C0       BEQ exec_fail

0x000032C8       MOV R11 R1        ; new code page
0x000032CC       MOV R12 R2        ; old code page
0x000032D0       BL exec_build_stack_image
0x000032D8       CMP R1 0
0x000032DC       BNE exec_rollback

0x000032E4       MOV R1 R11
0x000032E8       MOV R2 R12

0x000032EC       B exec_commit_image

exec_badfault:
0x000032F4       NOP
exec_fail:
0x000032F8       NOP
exec_rollback:
0x000032FC       LI R1 ERR_FAULT
0x00003304       STW R1 [SP + TF_R1]
0x00003308       B trap_restore
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

0x00003310       MOV R11 R1              ; new page
0x00003314       MOV R12 R2              ; old page

; macro: GET_CURR_TASK_IDX R4
0x00003318   LI R1 CURRENT_TASK
0x00003320   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x00003324   LI R1 TASK_SIZE
0x0000332C   MUL R3 R4 R1
0x00003330   LI R5 tasks
0x00003338   ADD R5 R5 R3

0x0000333C       LI  R1 exec_stack_used
0x00003344       LDW R8 [R1]
0x00003348       LI  R9 USER_STACK_TOP
0x00003350       SUB R9 R9 R8            ; final user SP
0x00003354       MOV R1 R9               ;  R2->R9 len R8 - cpy our image for stack
0x00003358       LI  R2 exec_stack_image
0x00003360       MOV R3 R8
0x00003364       BL memcpy

0x0000336C       LI R1 USER_CODE_VA      ; commit task state
; macro: TASK_SET_PC R5,R1
0x00003374   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5,R11
0x00003378   STW R11 [R5 + TASK_CODE_PAGE]
0x0000337C       MOV R1 R9
; macro: TASK_SET_USP R5,R1
0x00003380   STW R1 [R5 + TASK_USP]
0x00003384       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5,R1
0x0000338C   STW R1 [R5 + TASK_BREAK]

    ; Make sure the task's fixed user stack page is still mapped RW before
    ; returning to user mode. execve rewrites the stack contents, but the
    ; page-table entry must remain valid even if the task was previously
    ; switched through another path.
; macro: TASK_GET_PTBR R1,R5
0x00003390   LDW R1 [R5 + TASK_PTBR]
; macro: TASK_GET_USTACK_PAGE R3,R5
0x00003394   LDW R3 [R5 + TASK_USTACK_PAGE]
0x00003398       CMP R3 0
0x0000339C       BEQ exec_commit_skip_stack_map
0x000033A4       LI R2 USER_STACK_VA
0x000033AC       LI R4 USER_RW
0x000033B4       BL map_page_rt

exec_commit_skip_stack_map:
; macro: TASK_GET_PTBR R1,R5
0x000033BC   LDW R1 [R5 + TASK_PTBR]
0x000033C0       LI R2 USER_CODE_VA
0x000033C8       MOV R3 R11
0x000033CC       LI R4 KERNEL_USER_ALL   ; map code page RX subject to permissions on X (now all X)
0x000033D4       BL map_page_rt

0x000033DC       CMP R12 0               ; free old pa page (R12) if have
0x000033E0       BEQ no_old_page
0x000033E8       MOV R1 R12
0x000033EC       BL page_put             ; free page
no_old_page:

0x000033F4       LI  R1 exec_argc
0x000033FC       LDW R2 [R1]
0x00003400       STW R2 [SP+TF_R1]

0x00003404       MOV R1 R9
0x00003408       ADD R1 R1 4
0x0000340C       STW R1 [SP+TF_R2]       ; user sp with image on top + 4 so it points to &argv image

0x00003410       LI R1 0                 ; envp
0x00003418       STW R1 [SP+TF_R3]

0x0000341C       STW R9 [SP+TF_USP]      ; user sp

0x00003420       LI R1 0
0x00003428       STW R1 [SP+TF_R4]
0x0000342C       STW R1 [SP+TF_R5]
0x00003430       STW R1 [SP+TF_R6]
0x00003434       STW R1 [SP+TF_R7]
0x00003438       STW R1 [SP+TF_R8]
0x0000343C       STW R1 [SP+TF_R9]
0x00003440       STW R1 [SP+TF_R10]
0x00003444       STW R1 [SP+TF_R11]
0x00003448       STW R1 [SP+TF_R12]

0x0000344C       LI R1 USER_CODE_VA
0x00003454       STW R1 [SP+TF_SEPC]

  ;  POP R12
  ;  POP R11
  ;  POP R10
  ;  POP R9
  ;  POP R8
  ;  POP LR

0x00003458       B trap_restore



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
0x00003460       PUSH LR
0x00003464       PUSH R8
0x00003468       PUSH R9
0x0000346C       PUSH R10
0x00003470       PUSH R11
0x00003474       PUSH R12

0x00003478       LI   R1 exec_argc   ;argc
0x00003480       LDW  R6 [R1]

0x00003484       MOV  R7 R6          ;pointer_bytes = (argc+2)*4
0x00003488       ADD  R7 R7 2
0x0000348C       SHL  R7 R7 2

0x00003490       LI   R1 exec_strings_used   ; strings blob len
0x00003498       LDW  R8 [R1]

    ;----------------------------------------------------------
    ; total = pointer_bytes(len argv ptr array + 4b argc) + string_bytes(len string blobs)
    ;----------------------------------------------------------

0x0000349C       ADD  R9 R7 R8
    ; check for MAX
0x000034A0       LI   R1 EXEC_STACK_SIZE
0x000034A8       CMP  R9 R1
0x000034AC       BGT  exec_stack_nomem

0x000034B4       LI   R1 exec_stack_used     ; save used size
0x000034BC       STW  R9 [R1]

0x000034C0       LI   R10 exec_stack_image   ;stack base for image
    ; building image for stack as on picture
0x000034C8       STW  R6 [R10]   ;argc

    ; copy string blob
0x000034CC       MOV  R1 R10
0x000034D0       ADD  R1 R1 R7   ; skip room for pointer_bytes see picture
0x000034D4       LI   R2 exec_strings
0x000034DC       MOV  R3 R8      ; blob len
0x000034E0       BL   memcpy

    ;----------------------------------------------------------
    ; future user addresses
    ;----------------------------------------------------------

0x000034E8       LI   R11 USER_STACK_TOP
0x000034F0       SUB  R11 R11 R9             ; r9 total image len, R11 start address image in the user stack
0x000034F4       MOV  R12 R11
0x000034F8       ADD  R12 R12 R7             ; r12 pointer bytes ptr in image in stack - start of string blob

    ;----------------------------------------------------------
    ; argv table build
    ;----------------------------------------------------------

0x000034FC       ADD  R10 R10 4              ; argv[0] starts after argc
0x00003500       LI   R4 exec_argv_offsets   ; args offsetss array
0x00003508       LI   R5 0
argv_loop:
0x00003510       CMP  R5 R6                  ; argc
0x00003514       BEQ  argv_done              ; if finished
0x0000351C       MOV  R1 R5
0x00003520       SHL  R1 R1 2
0x00003524       LDW  R2 [R4+R1]             ; get arg[i] offset
0x00003528       ADD  R2 R2 R12              ; compute R2 - blobs string adress for this arg[i]
0x0000352C       STW  R2 [R10+R1]            ; store this address to argv array in image
0x00003530       ADD  R5 R5 1
0x00003534       B    argv_loop
argv_done:
0x0000353C       MOV  R1 R6
0x00003540       SHL  R1 R1 2

0x00003544       LI   R2 0
0x0000354C       STW  R2 [R10+R1]            ; put null here: argv[argc] = NULL
    ;success
0x00003550       LI   R1 0
0x00003558       POP  R12
0x0000355C       POP  R11
0x00003560       POP  R10
0x00003564       POP  R9
0x00003568       POP  R8
0x0000356C       POP  LR
0x00003570       RET

exec_stack_nomem:
0x00003574       LI   R1 ERR_NOMEM
0x0000357C       POP  R12
0x00003580       POP  R11
0x00003584       POP  R10
0x00003588       POP  R9
0x0000358C       POP  R8
0x00003590       POP  LR
0x00003594       RET

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
0x00003598       PUSH LR
0x0000359C       PUSH R7
0x000035A0       PUSH R8
0x000035A4       PUSH R9
0x000035A8       PUSH R10
0x000035AC       PUSH R11
0x000035B0       PUSH R12

0x000035B4       BL vfs_lookup   ; lookup inode for the file
0x000035BC       CMP R1 0
0x000035C0       BEQ load_noent
0x000035C8       MOV R9 R1

0x000035CC       LDW R1 [R9 + INODE_TYPE]    ;check inode type/size
0x000035D0       LI R2 INODE_DIR
0x000035D8       CMP R1 R2
0x000035DC       BEQ load_noexec
0x000035E4       LDW R3 [R9 + INODE_SIZE]
0x000035E8       LI R4 PAGE_SIZE
0x000035F0       CMP R3 R4
0x000035F4       BGT load_noexec

0x000035FC       BL file_alloc               ;allocate file
0x00003604       CMP R1 0
0x00003608       BEQ load_nomem
0x00003610       MOV R10 R1                  ; savr file ptr R10
0x00003614       MOV R1 R10
0x00003618       MOV R2 R9
0x0000361C       LI R3 FD_FLAG_READ
0x00003624       BL file_init

0x0000362C       BL page_alloc               ; pa page for code
0x00003634       CMP R1 0
0x00003638       BEQ load_file_fail

0x00003640       MOV R11 R1                  ;new pa page code

; macro: GET_CURR_TASK_IDX R4        ;current task
0x00003644   LI R1 CURRENT_TASK
0x0000364C   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x00003650   LI R1 TASK_SIZE
0x00003658   MUL R3 R4 R1
0x0000365C   LI R5 tasks
0x00003664   ADD R5 R5 R3
; macro: TASK_GET_CODE_PAGE R12,R5   ; save old pa code page from this task to R12
0x00003668   LDW R12 [R5 + TASK_CODE_PAGE]

; macro: TASK_GET_PTBR R1,R5
0x0000366C   LDW R1 [R5 + TASK_PTBR]
0x00003670       LI R2 USER_CODE_VA
0x00003678       MOV R3 R11                  ;new pa code page
0x0000367C       LI R4 USER_RW
0x00003684       BL map_page_rt              ;map it for loading to USER_CODE_VA

; macro: TASK_GET_DATA_PAGE R1,R5    ; tasks va data_page
0x0000368C   LDW R1 [R5 + TASK_DATA_PAGE]
0x00003690       CMP R1 0
0x00003694       BEQ load_read
0x0000369C       LI R3 PAGE_SIZE
0x000036A4       BL mem_zero                 ; clean task data_page

load_read:
0x000036AC       MOV R1 R10                  ; file* with program
0x000036B0       LI R2 USER_CODE_VA
0x000036B8       LI R3 PAGE_SIZE
0x000036C0       BL file_read
0x000036C8       CMP R1 0
0x000036CC       BLT load_read_fail
0x000036D4       MOV R1 R10                  ; release file*
0x000036D8       BL file_put
    ; all loaedd R1 - new code page pa R2 - old code page pa
0x000036E0       MOV R1 R11
0x000036E4       MOV R2 R12

exec_lb_exit:                   ;common! exit!
0x000036E8       POP R12
0x000036EC       POP R11
0x000036F0       POP R10
0x000036F4       POP R9
0x000036F8       POP R8
0x000036FC       POP R7
0x00003700       POP LR
0x00003704       RET
; in error generally depending on state rollback allocated resources
load_read_fail:
    ; in this case release file and pa code page
0x00003708       MOV R1 R10
0x0000370C       BL file_put
0x00003714       MOV R1 R11
0x00003718       BL page_put        ;free page
0x00003720       LI R1 0
0x00003728       LI R2 ERR_IO
0x00003730       B  exec_lb_exit

load_file_fail:
0x00003738       MOV R1 R10
0x0000373C       BL file_put

load_nomem:
0x00003744       LI R1 0
0x0000374C       LI R2 ERR_NOMEM
0x00003754       B  exec_lb_exit

load_noexec:
0x0000375C       MOV R1 R10
0x00003760       CMP R1 0
0x00003764       BEQ noexec_skip
0x0000376C       BL file_put

noexec_skip:
0x00003774       LI R1 0
0x0000377C       LI R2 ERR_NOEXEC
0x00003784       B  exec_lb_exit

load_noent:
0x0000378C       LI R1 0
0x00003794       LI R2 ERR_NOENT
0x0000379C       B  exec_lb_exit


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

0x000037A4       PUSH LR
0x000037A8       PUSH R7
0x000037AC       PUSH R8
0x000037B0       PUSH R9
0x000037B4       PUSH R10
0x000037B8       PUSH R11
0x000037BC       PUSH R12
    ;init this at first
0x000037C0       LI R1 exec_strings_used
0x000037C8       LI R2 0
0x000037D0       STW R2 [R1]

0x000037D4       LI   R11 exec_strings      ; destination blob
0x000037DC       LI   R12 0                 ; current offset
0x000037E4       LI   R7 0                  ; argv index
                               ;  R8 = user argv[]
                               ;  R9 = argc
exec_capture_next_arg:
    ; finished?
0x000037EC       CMP  R7 R9
0x000037F0       BEQ  exec_capture_done     ; if all agvs processed

    ;---------------------------------------------
    ; load argv[i] (ptr to string)
    ;---------------------------------------------
0x000037F8       LDW  R10 [R8]

0x000037FC       CMP  R10 0
0x00003800       BEQ  exec_capture_fault     ;if argv[i]==null

    ;---------------------------------------------
    ; save offset
    ;
    ; exec_argv_offsets[i]=current_offset (in R12)
    ;---------------------------------------------
0x00003808       LI   R1 exec_argv_offsets
0x00003810       MOV  R2 R7  ;i
0x00003814       SHL  R2 R2 2
0x00003818       ADD  R1 R1 R2
0x0000381C       STW  R12 [R1]

exec_copy_string:
    ;---------------------------------------------
    ; copy one character r10 argv[i] (ptr to string) R11 ptr to exec strings
    ;---------------------------------------------
0x00003820       LDB  R3 [R10]
0x00003824       STB  R3 [R11]
0x00003828       ADD  R10 R10 1
0x0000382C       ADD  R11 R11 1
0x00003830       ADD  R12 R12 1
    ; blob overflow?
0x00003834       LI   R1 EXEC_MAX_STRINGS
0x0000383C       CMP  R12 R1
0x00003840       BGT  exec_capture_fault
0x00003848       CMP  R3 0
0x0000384C       BNE  exec_copy_string           ; end of string?
0x00003854       ADD  R8 R8 4    ;to next argv[] string
0x00003858       ADD  R7 R7 1    ;i=i+1
0x0000385C       B    exec_capture_next_arg

exec_capture_done:
0x00003864       LI   R1 exec_strings_used
0x0000386C       STW  R12 [R1]           ; current offset after last string
0x00003870       LI  R1 0
0x00003878       POP R12
0x0000387C       POP R11
0x00003880       POP R10
0x00003884       POP R9
0x00003888       POP R8
0x0000388C       POP R7
0x00003890       POP LR
0x00003894       RET
exec_capture_fault:
0x00003898       LI   R1 ERR_FAULT
0x000038A0       POP R12
0x000038A4       POP R11
0x000038A8       POP R10
0x000038AC       POP R9
0x000038B0       POP R8
0x000038B4       POP R7
0x000038B8       POP LR
0x000038BC       RET

syscall_fork:
    ;================================================================
    ; fork()
    ; Returns child PID in the parent and 0 in the child.
    ; This clones the current task, duplicating its address space and
    ; user-writable state while preserving a new independent child thread.
    ;================================================================

0x000038C0       BL task_clone_current
0x000038C8       CMP R1 0
0x000038CC       BEQ fork_fail

    ; We return child PID to the parent via the trapframe.
; macro: TASK_GET_PID R2, R1
0x000038D4   LDW R2 [R1 + TASK_PID]
0x000038D8       STW R2 [SP + TF_R1]
0x000038DC       B trap_restore

fork_fail:
0x000038E4       LI R1 ERR_NOMEM
0x000038EC       STW R1 [SP + TF_R1]
0x000038F0       B trap_restore

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x000038F8       LI R1 0
0x00003900       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00003904       B schedule_and_switch
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
0x0000390C       LDW R8 [SP + TF_R1]        ; R8 = exit code

; macro: GET_CURR_TASK_IDX R2
0x00003910   LI R1 CURRENT_TASK
0x00003918   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x0000391C   LI R1 TASK_SIZE
0x00003924   MUL R3 R2 R1
0x00003928   LI R5 tasks
0x00003930   ADD R5 R5 R3

    ; Store exit code in child task struct for parent to collect in waitforpid
; macro: TASK_SET_EXIT_CODE R5, R8  ; Save exit code
0x00003934   STW R8 [R5 + TASK_EXIT_CODE]

0x00003938       PUSH R5
0x0000393C       MOV R1 R5
0x00003940       BL task_close_fds          ; close all open file descriptors of this task (if any) to free file_pool resources
0x00003948       POP R5

    ; Mark this child as zombie (still exists but not runnable)
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x0000394C   LI R1 TASK_ZOMBIE
0x00003954   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00003958   LI R1 WAIT_NONE
0x00003960   STW R1 [R5 + TASK_WAIT]

    ; Wake parent if it's waiting
; macro: TASK_GET_PPID R6, R5       ; R6 = parent PID
0x00003964   LDW R6 [R5 + TASK_PPID]

    ; find parent task by PPID
0x00003968       MOV R1 R6
0x0000396C       LI R2 0                    ; Search by PID (parent's PID)
0x00003974       BL task_find               ; R1 = found parent task*
0x0000397C       CMP R1 0
0x00003980       BEQ no_parent_waiting
0x00003988       MOV R7 R1                  ; R7 = parent task*
0x0000398C       MOV R11 R2                 ; save parent task index for bitmask

    ;Check if parent is waiting for this child
; macro: TASK_GET_WAIT_CHILD R8, R7 ; Child PID that parent R7 ptr is waiting for
0x00003990   LDW R8 [R7 + TASK_WAIT_CHILD]
; macro: TASK_GET_PID R9, R5        ; This child's R5 ptr PID
0x00003994   LDW R9 [R5 + TASK_PID]

0x00003998       LI R10 -1
0x000039A0       CMP R8 R10                 ; if parent is waiting for any child (-1), then wake it up
0x000039A4       BEQ wake_parent            ;

0x000039AC       CMP R8 R9
0x000039B0       BNE no_parent_waiting      ; parent is waiting for a different child, do not wake it up

wake_parent:
    ; Find parent's task index for bitmask
    ; we already have parent task in R11

0x000039B8       LI R9 1
0x000039C0       SHL R9 R9 R11               ; bit for parent task

0x000039C4       LI R1 child_waitq
0x000039CC       MOV R2 R9
0x000039D0       BL waitq_wake_bitmask       ;unblock parent task waiting for this child

no_parent_waiting:
0x000039D8       B schedule_and_switch

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
0x000039E0       LDW R8 [SP + TF_R1]        ; R8 = pid to wait for
0x000039E4       LDW R9 [SP + TF_R2]        ; R9 = status pointer

    ; Validate status pointer
0x000039E8       CMP R9 0
0x000039EC       BEQ waitpid_validate_done
0x000039F4       MOV R1 R9
0x000039F8       LI R2 4
0x00003A00       LI R3 1
0x00003A08       BL user_buffer_valid_range
0x00003A10       CMP R1 1
0x00003A14       BNE waitpid_badptr

waitpid_validate_done:
; macro: GET_CURR_TASK_IDX R4
0x00003A1C   LI R1 CURRENT_TASK
0x00003A24   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003A28   LI R1 TASK_SIZE
0x00003A30   MUL R3 R4 R1
0x00003A34   LI R5 tasks
0x00003A3C   ADD R5 R5 R3
; macro: TASK_GET_PID R10, R5       ; R10 = current (parent proc) PID
0x00003A40   LDW R10 [R5 + TASK_PID]

    ; if search for any child
0x00003A44       LI  R2 -1
0x00003A4C       CMP R8 R2
0x00003A50       BNE find_child_by_pid
    ; set task_find to search for any child of this parent
0x00003A58       MOV R1 R10                  ; R1 = parent PID (PPID in child task)
0x00003A5C       LI  R2 1                    ; search by PPID
0x00003A64       BL task_find               ; R1 = found child task*
0x00003A6C       CMP R1 0
0x00003A70       BEQ waitpid_no_child        ; No any child with PPID = this parent PID found
    ;R1 child task* found
0x00003A78       B find_any_child_found
find_child_by_pid:
    ; Search for child task by PID
0x00003A80       MOV R1 R8                  ; R1 = child PID to search for
0x00003A84       LI R2 0                    ; Search by PID
0x00003A8C       BL task_find               ; R1 = found child task*
0x00003A94       CMP R1 0
0x00003A98       BEQ waitpid_no_child        ; No such child

find_any_child_found:

0x00003AA0       MOV R7 R1                   ; R7 = child task*

    ; Verify it's actually our child by its PPID fld
; macro: TASK_GET_PPID R1, R7
0x00003AA4   LDW R1 [R7 + TASK_PPID]
0x00003AA8       CMP R1 R10
0x00003AAC       BNE waitpid_no_child
    ; R7 = child task*
    ; check its state, if ZOMBIE, we can reap it and return its exit code
; macro: TASK_GET_STATE R1, R7
0x00003AB4   LDW R1 [R7 + TASK_STATE]
0x00003AB8       CMP R1 TASK_ZOMBIE
0x00003ABC       BEQ waitpid_reap_child

    ; Child running - block parent
; macro: TASK_GET_PID R1, R7
0x00003AC4   LDW R1 [R7 + TASK_PID]
; macro: TASK_SET_WAIT_CHILD R5, R1
0x00003AC8   STW R1 [R5 + TASK_WAIT_CHILD]

0x00003ACC       LI R1 child_waitq           ; child_waitq ptr
0x00003AD4       LI R2 WAIT_CHILD            ; reason
0x00003ADC       LI R3 TASK_SLEEPING         ; state to set for current task
0x00003AE4       BL waitq_prepare_sleep

0x00003AEC       BL waitq_sleep_current     ; freeze the current task

    ; will resume here when child exits and wakes us up

waitpid_reap_child:
    ; Get exit code from child task
; macro: TASK_GET_EXIT_CODE R2, R7
0x00003AF4   LDW R2 [R7 + TASK_EXIT_CODE]

    ; If status pointer is not NULL, write exit code to user space
0x00003AF8       CMP R9 0
0x00003AFC       BEQ waitpid_reap_done

0x00003B04       MOV R1 R9                  ; R1 = user status pointer
0x00003B08       MOV R4 R2                  ; preserve exit code in kernel source register
0x00003B0C       LI  R2 4                   ; R2 = size of exit code
0x00003B14       BL copy_to_user            ; write exit code to user space

waitpid_reap_done:
; macro: TASK_GET_PID R10, R7       ; get child's PID
0x00003B1C   LDW R10 [R7 + TASK_PID]
0x00003B20       MOV R1 R7                  ; R1 = child task*
0x00003B24       BL task_destroy

0x00003B2C       STW R10 [SP + TF_R1]        ; save child's PID to trapframe for return
0x00003B30       B trap_restore

waitpid_no_child:
0x00003B38       LI R1 ERR_CHILD
0x00003B40       STW R1 [SP + TF_R1]
0x00003B44       B trap_restore

waitpid_badptr:
0x00003B4C       LI R1 ERR_FAULT
0x00003B54       STW R1 [SP + TF_R1]
0x00003B58       B trap_restore


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
0x00003B60       PUSH R5
0x00003B64       PUSH R6
0x00003B68       PUSH R7

0x00003B6C       MOV R5 R2                  ; Save search mode
0x00003B70       MOV R7 R1                  ; Save PID/PPID
0x00003B74       LI R2 0                    ; Task index
task_find_loop:
0x00003B7C       LI R3 MAX_TASKS
0x00003B84       CMP R2 R3
0x00003B88       BGE task_find_not_found

; macro: GET_TASK_PTR R4, R2
0x00003B90   LI R1 TASK_SIZE
0x00003B98   MUL R3 R2 R1
0x00003B9C   LI R4 tasks
0x00003BA4   ADD R4 R4 R3
; macro: TASK_GET_STATE R6, R4
0x00003BA8   LDW R6 [R4 + TASK_STATE]
0x00003BAC       CMP R6 TASK_DEAD
0x00003BB0       BEQ task_find_next         ; Skip dead tasks

    ; Search based on mode
0x00003BB8       CMP R5 0
0x00003BBC       BEQ task_find_by_pid

    ; Search by PPID
; macro: TASK_GET_PPID R6, R4
0x00003BC4   LDW R6 [R4 + TASK_PPID]
0x00003BC8       CMP R6 R7
0x00003BCC       BEQ task_find_found
0x00003BD4       B task_find_next

task_find_by_pid:
; macro: TASK_GET_PID R6, R4
0x00003BDC   LDW R6 [R4 + TASK_PID]
0x00003BE0       CMP R6 R7
0x00003BE4       BEQ task_find_found

task_find_next:
0x00003BEC       ADD R2 R2 1
0x00003BF0       B task_find_loop

task_find_found:
0x00003BF8       MOV R1 R4                  ; Return task pointer
0x00003BFC       MOV R2 R2                  ; Return task index
0x00003C00       POP R7
0x00003C04       POP R6
0x00003C08       POP R5
0x00003C0C       RET

task_find_not_found:
0x00003C10       LI R1 0
0x00003C18       POP R7
0x00003C1C       POP R6
0x00003C20       POP R5
0x00003C24       RET

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00003C28   LI R1 CURRENT_TASK
0x00003C30   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003C34   LI R1 TASK_SIZE
0x00003C3C   MUL R3 R2 R1
0x00003C40   LI R5 tasks
0x00003C48   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00003C4C   LDW R1 [R5 + TASK_PID]

0x00003C50       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00003C54       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00003C5C       LDW R1 [SP + TF_R1]
0x00003C60       STW R1 [SP + TF_R1]

0x00003C64       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00003C6C       LDW R1 [SP + TF_R1]
0x00003C70       LDW R2 [SP + TF_R2]

0x00003C74       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003C7C       CMP R1 0
0x00003C80       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003C88   LI R1 CURRENT_TASK
0x00003C90   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003C94   LI R1 TASK_SIZE
0x00003C9C   MUL R3 R4 R1
0x00003CA0   LI R5 tasks
0x00003CA8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003CAC   LDW R1 [R5 + TASK_KBUF_RD_PTR]

0x00003CB0       BL vfs_open

0x00003CB8       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x00003CBC       B trap_restore

open_fail_fault:
0x00003CC4       LI R1 ERR_FAULT
0x00003CCC       STW R1 [SP + TF_R1]     ;file not opened ERR
0x00003CD0       B trap_restore


syscall_sleep:
    ;================================================================
    ; sleep(ms)
    ; R1 = milliseconds to sleep
    ;
    ; Returns:
    ;   R1 = 0 on success (slept full duration)
    ;   R1 = -1 on error (invalid time)
    ;================================================================

0x00003CD8       LDW R8 [SP + TF_R1]        ; R8 = milliseconds

0x00003CDC       CMP R8 0
0x00003CE0       BLE sleep_invalid          ; must be positive

; macro: GET_CURR_TASK_IDX R4
0x00003CE8   LI R1 CURRENT_TASK
0x00003CF0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003CF4   LI R1 TASK_SIZE
0x00003CFC   MUL R3 R4 R1
0x00003D00   LI R5 tasks
0x00003D08   ADD R5 R5 R3

    ; Calculate wake time in PIT ticks (1 ms per tick).
0x00003D0C       LI R3 timer_ticks
0x00003D14       LDW R6 [R3]                ; current ticks (1ms per tick)

    ; Convert ms to ticks: 1 tick = 1 ms
0x00003D18       MOV R7 R8                  ; R7 = ticks to sleep

0x00003D1C       ADD R6 R6 R7               ; R6 = wake time in ticks

    ; Store wake time in task struct
; macro: TASK_SET_WAKE_TIME R5, R6
0x00003D20   STW R6 [R5 + TASK_WAKE_TIME]

    ; Use existing wait queue infrastructure
0x00003D24       LI R1 sleep_waitq           ; sleep_waitq ptr
0x00003D2C       LI R2 WAIT_SLEEP            ; reason
0x00003D34       LI R3 TASK_SLEEPING         ; new state (if other then blocked_io)
0x00003D3C       BL waitq_prepare_sleep     ; This marks task as TASK_SLEEP and adds it to the sleep_waitq

0x00003D44       BL waitq_sleep_current     ; freeze the current task in kernel side until it is woken up by the timer interrupt handler when the wake time is reached

    ; Return 0 (will be set when woken)
0x00003D4C       LI R1 0
0x00003D54       STW R1 [SP + TF_R1]
0x00003D58       B trap_restore

sleep_invalid:
0x00003D60       LI R1 ERR_FAULT
0x00003D68       STW R1 [SP + TF_R1]
0x00003D6C       B trap_restore


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
0x00003D74       PUSH LR

0x00003D78       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00003D7C   LI R1 CURRENT_TASK
0x00003D84   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003D88   LI R1 TASK_SIZE
0x00003D90   MUL R3 R4 R1
0x00003D94   LI R5 tasks
0x00003D9C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x00003DA0   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x00003DA4       PUSH R9                    ; original destination returned on success
0x00003DA8       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00003DB0       LI R11 KBUFFER_SIZE
0x00003DB8       CMP R10 R11
0x00003DBC       BGE copy_path_fail

0x00003DC4       PUSH R8
0x00003DC8       PUSH R9
0x00003DCC       PUSH R10
0x00003DD0       MOV R1 R8
0x00003DD4       LI R2 1
0x00003DDC       LI R3 0                    ; read access from user source
0x00003DE4       BL user_buffer_valid_range
0x00003DEC       POP R10
0x00003DF0       POP R9
0x00003DF4       POP R8
0x00003DF8       CMP R1 1
0x00003DFC       BNE copy_path_fail

0x00003E04       LDB R4 [R8]
0x00003E08       STB R4 [R9]
0x00003E0C       CMP R4 0
0x00003E10       BEQ copy_path_done

0x00003E18       ADD R8 R8 1
0x00003E1C       ADD R9 R9 1
0x00003E20       ADD R10 R10 1
0x00003E24       B copy_path_loop

copy_path_done:
0x00003E2C       POP R1                     ; original kernel path pointer
0x00003E30       POP LR
0x00003E34       RET

copy_path_fail:
0x00003E38       POP R1                     ; discard original kernel path pointer
0x00003E3C       LI R1 0
0x00003E44       POP LR
0x00003E48       RET

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

0x00003E4C       PUSH LR
0x00003E50       PUSH R8
0x00003E54       PUSH R9
0x00003E58       PUSH R10
0x00003E5C       PUSH R11

0x00003E60       MOV R8 R1          ; kernel dst
0x00003E64       MOV R9 R2          ; user src
0x00003E68       MOV R10 R3         ; max length
0x00003E6C       LI  R11 0          ; bytes copied

copy_user_loop:
    ; reached max?
0x00003E74       CMP R11 R10
0x00003E78       BGE copy_user_fail

    ; validate one byte
0x00003E80       PUSH R8
0x00003E84       PUSH R9
0x00003E88       PUSH R10
0x00003E8C       PUSH R11
0x00003E90       MOV R1 R9
0x00003E94       LI  R2 1
0x00003E9C       LI  R3 0           ; read access
0x00003EA4       BL user_buffer_valid_range
0x00003EAC       POP R11
0x00003EB0       POP R10
0x00003EB4       POP R9
0x00003EB8       POP R8
0x00003EBC       CMP R1 1
0x00003EC0       BNE copy_user_fail

    ; copy byte
0x00003EC8       LDB R4 [R9]
0x00003ECC       STB R4 [R8]
    ;cpy ctr
0x00003ED0       ADD R11 R11 1
0x00003ED4       CMP R4 0    ;if string ends (null)
0x00003ED8       BEQ copy_user_done

0x00003EE0       ADD R8 R8 1 ;advance
0x00003EE4       ADD R9 R9 1
0x00003EE8       B copy_user_loop
copy_user_done:
0x00003EF0       MOV R1 R11
0x00003EF4       POP R11
0x00003EF8       POP R10
0x00003EFC       POP R9
0x00003F00       POP R8
0x00003F04       POP LR
0x00003F08       RET
copy_user_fail:
0x00003F0C       LI  R1 0
0x00003F14       POP R11
0x00003F18       POP R10
0x00003F1C       POP R9
0x00003F20       POP R8
0x00003F24       POP LR
0x00003F28       RET

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
0x00003F2C       PUSH LR
0x00003F30       MOV R8 R1                  ; save pathname ptr

0x00003F34       LI R7 device_table
0x00003F3C       LI R9 DEVICE_COUNT

devfs_loop:
0x00003F44       CMP R9 0
0x00003F48       BEQ lookup_fail

    ; compare pathname with device name
0x00003F50       MOV R1 R8
0x00003F54       LDW R2 [R7 + DEV_NAME]
0x00003F58       BL strcmp
0x00003F60       CMP R1 1
0x00003F64       BEQ devfs_found

0x00003F6C       ADD R7 R7 DEV_SIZE
0x00003F70       SUB R9 R9 1
0x00003F74       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x00003F7C       BL inode_alloc
0x00003F84       CMP R1 0
0x00003F88       BEQ devfs_fail

0x00003F90       MOV R10 R1         ; inode
    ; 2 init inode
0x00003F94       LDW R2 [R7 + DEV_OPS]
0x00003F98       LDW R3 [R7 + DEV_PRIVATE]
0x00003F9C       LI  R4 INODE_CHAR       ; inode type for dev - char
0x00003FA4       LI  R5 0                ; size =0
0x00003FAC       BL inode_init

0x00003FB4       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x00003FB8       POP LR
0x00003FBC       RET

devfs_fail:
0x00003FC0       LI R1 0
0x00003FC8       POP LR
0x00003FCC       RET

;====================================================================
; NSFS VFS driver skeleton
;
; NSFS is the writable overlay between devfs and tarfs:
;   devfs_lookup -> nsfs_lookup -> tarfs_lookup
;
; These stubs define the ABI and struct shape. The real implementation will
; use BMI opcodes to query/create/delete entries in the host JSON KV store.
;====================================================================

nsfs_node_alloc:
0x00003FD0       LI R2 0

nsfs_node_alloc_loop:
0x00003FD8       CMP R2 NSFS_MAX_NODES
0x00003FDC       BGE nsfs_node_alloc_fail

0x00003FE4       SHL R3 R2 2
0x00003FE8       LI R4 nsfs_node_used
0x00003FF0       ADD R4 R4 R3

0x00003FF4       LDW R5 [R4]
0x00003FF8       CMP R5 0
0x00003FFC       BEQ nsfs_node_alloc_found

0x00004004       ADD R2 R2 1
0x00004008       B nsfs_node_alloc_loop

nsfs_node_alloc_found:
0x00004010       LI R5 1
0x00004018       STW R5 [R4]

0x0000401C       LI R3 NSFS_NODE_SIZEOF
0x00004024       MUL R6 R2 R3
0x00004028       LI R1 nsfs_node_pool
0x00004030       ADD R1 R1 R6
0x00004034       RET

nsfs_node_alloc_fail:
0x00004038       LI R1 0
0x00004040       RET

nsfs_node_free:
0x00004044       LI R2 nsfs_node_pool
0x0000404C       SUB R3 R1 R2

0x00004050       LI R4 NSFS_NODE_SIZEOF
0x00004058       DIV R5 R3 R4

0x0000405C       SHL R5 R5 2
0x00004060       LI R6 nsfs_node_used
0x00004068       ADD R6 R6 R5

0x0000406C       LI R7 0
0x00004074       STW R7 [R6]
0x00004078       RET

; nsfs_lookup
; in:  R1 = pathname
; out: R1 = inode ptr if present in NSFS overlay, or 0 if not found
nsfs_lookup:
    ; TODO:
    ; 1. BMI lookup/read metadata for ns:<default_ns>:path:<pathname>.
    ; 2. Allocate nsfs_node and copy/cache path metadata.
    ; 3. Allocate inode and init with nsfs_ops, nsfs_node, type, size.
0x0000407C       LI R1 0
0x00004084       RET

; nsfs_open
; in:  R1 = file ptr
; out: R1 = 0
nsfs_open:
0x00004088       LI R1 0
0x00004090       RET

; nsfs_close
; in:  R1 = file ptr
; out: R1 = 0
nsfs_close:
0x00004094       LI R1 0
0x0000409C       RET

; nsfs_read
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
nsfs_read:
0x000040A0       LI R1 ERR_NOENT
0x000040A8       RET

; nsfs_write
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes written or errno
nsfs_write:
0x000040AC       LI R1 ERR_NOENT
0x000040B4       RET

; nsfs_readdir
; in:  R1 = file ptr, R2 = userspace dirent buffer
; out: R1 = 1 entry, 0 EOF, or errno
nsfs_readdir:
0x000040B8       LI R1 0
0x000040C0       RET

; nsfs_create
; in:  R1 = pathname, R2 = mode/type flags
; out: R1 = 0 or errno
nsfs_create:
    ; TODO: FILE_CREATE over BMI, then nsfs_lookup can materialize inode.
0x000040C4       LI R1 ERR_NOENT
0x000040CC       RET

; nsfs_unlink
; in:  R1 = pathname
; out: R1 = 0 or errno
nsfs_unlink:
    ; TODO: FILE_DELETE over BMI and create whiteout when shadowing tarfs.
0x000040D0       LI R1 ERR_NOENT
0x000040D8       RET

; nsfs_mkdir
; in:  R1 = pathname, R2 = mode
; out: R1 = 0 or errno
nsfs_mkdir:
    ; TODO: DIR_CREATE over BMI.
0x000040DC       LI R1 ERR_NOENT
0x000040E4       RET

; nsfs_rmdir
; in:  R1 = pathname
; out: R1 = 0 or errno
nsfs_rmdir:
    ; TODO: DIR_DELETE over BMI.
0x000040E8       LI R1 ERR_NOENT
0x000040F0       RET

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

0x000040F4       PUSH LR

0x000040F8       MOV R8 R1                  ; save pathname ptr

0x000040FC       LI R7 device_table
0x00004104       LI R9 DEVICE_COUNT

lookup_loop:
0x0000410C       CMP R9 0
0x00004110       BEQ lookup_fail

    ; compare pathname with device name

0x00004118       MOV R1 R8
0x0000411C       LDW R2 [R7 + DEV_NAME]

0x00004120       BL strcmp

0x00004128       CMP R1 1
0x0000412C       BEQ lookup_found

0x00004134       ADD R7 R7 DEV_SIZE
0x00004138       SUB R9 R9 1
0x0000413C       B lookup_loop

lookup_found:

0x00004144       MOV R1 R7                  ; return device descriptor ptr

0x00004148       POP LR
0x0000414C       RET

lookup_fail:

0x00004150       LI R1 0

0x00004158       POP LR
0x0000415C       RET

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
0x00004160       LDB R3 [R1]
0x00004164       LDB R4 [R2]

0x00004168       CMP R3 R4
0x0000416C       BNE str_not_equal

0x00004174       CMP R3 0
0x00004178       BEQ str_equal

0x00004180       ADD R1 R1 1
0x00004184       ADD R2 R2 1
0x00004188       B str_loop

str_equal:
0x00004190       LI R1 1
0x00004198       RET

str_not_equal:
0x0000419C       LI R1 0
0x000041A4       RET

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
0x000041A8       PUSH R3
0x000041AC       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x000041B0       LDB R3 [R2]            ; prefix char
0x000041B4       CMP R3 0
0x000041B8       BEQ sp_match           ; reached end of prefix?

0x000041C0       LDB R4 [R1]            ; string char
0x000041C4       CMP R4 R3
0x000041C8       BNE sp_nomatch

0x000041D0       ADD R1 R1 1
0x000041D4       ADD R2 R2 1
0x000041D8       B sp_loop
sp_match:
0x000041E0       LI R1 1                 ;prefix ok
0x000041E8       POP R4
0x000041EC       POP R3
0x000041F0       RET
sp_nomatch:
0x000041F4       LI R1 0                 ; not ok
0x000041FC       POP R4
0x00004200       POP R3
0x00004204       RET

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
0x00004208       PUSH R3
0x0000420C       PUSH R4
sk_loop:
0x00004210       LDB R3 [R2]            ; prefix char
0x00004214       CMP R3 0
0x00004218       BEQ sk_match           ; reached end of prefix
0x00004220       LDB R4 [R1]            ; string char
0x00004224       CMP R4 R3
0x00004228       BNE sk_nomatch
0x00004230       ADD R1 R1 1
0x00004234       ADD R2 R2 1
0x00004238       B sk_loop

sk_match:
    ; R1 already points past prefix
0x00004240       POP R4
0x00004244       POP R3
0x00004248       RET

sk_nomatch:
0x0000424C       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x00004254       POP R4
0x00004258       POP R3
0x0000425C       RET

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
0x00004260       PUSH R2
0x00004264       PUSH R3
0x00004268       LI R2 0                ; length
pcl_loop:
0x00004270       LDB R3 [R1]
0x00004274       CMP R3 0
0x00004278       BEQ pcl_done
0x00004280       LI R4 47               ; '/'
0x00004288       CMP R3 R4
0x0000428C       BEQ pcl_done
0x00004294       ADD R2 R2 1
0x00004298       ADD R1 R1 1
0x0000429C       B pcl_loop
pcl_done:
0x000042A4       MOV R1 R2
0x000042A8       POP R3
0x000042AC       POP R2
0x000042B0       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x000042B4       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x000042B8       LI R4 0
0x000042C0       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x000042C4       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x000042C8       LI R4 1
0x000042D0       STW R4 [R1 + FILE_REFCNT]
0x000042D4       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x000042D8       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x000042DC   LI R1 CURRENT_TASK
0x000042E4   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000042E8   LI R1 TASK_SIZE
0x000042F0   MUL R3 R4 R1
0x000042F4   LI R4 tasks
0x000042FC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00004300   LDW R4 [R4 + TASK_FD_TABLE]

0x00004304       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x0000430C       CMP R5 MAX_FDS
0x00004310       BGE fd_alloc_fail

0x00004318       SHL R6 R5 2                ; fd * 4
0x0000431C       ADD R7 R4 R6               ; &fd_table[fd]

0x00004320       LDW R2 [R7]
0x00004324       CMP R2 0                   ; 0 - empty
0x00004328       BEQ fd_alloc_found

0x00004330       ADD R5 R5 1
0x00004334       B fd_alloc_loop

fd_alloc_found:

0x0000433C       STW R8 [R7]                ; fd_table[fd] = file*

0x00004340       MOV R1 R5                  ; return fd
0x00004344       RET

fd_alloc_fail:

0x00004348       LI R1 ERR_MFILE
0x00004350       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x00004354       LDW R1 [SP + TF_R1]

0x00004358       BL vfs_close

0x00004360       LI R1 0
0x00004368       STW R1 [SP + TF_R1]

0x0000436C       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00004374       LDW R7 [SP + TF_R1]

0x00004378       BL pipe_alloc       ;create new pipe object in pipe_pool
0x00004380       CMP R1 0
0x00004384       BEQ pipe_fail_nospc

0x0000438C       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x00004390       BL file_alloc        ; R1 - created read file ptr for read end
0x00004398       CMP R1 0
0x0000439C       BEQ pipe_fail_read_fd

0x000043A4       MOV R9 R1           ; new file for read end  in file_pool
0x000043A8       BL inode_alloc      ; get inode for this end file
0x000043B0       CMP R1 0
0x000043B4       BEQ pipe_fail_ia_read_fd
0x000043BC       MOV R10 R1

0x000043C0       LI  R2 pipe_ops         ; pipe_ops table
0x000043C8       MOV R3 R8               ; store our slot pipe*
0x000043CC       LI  R4 INODE_PIPE       ; inode type PIPE
0x000043D4       LI  R5 0                ; size =0
0x000043DC       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x000043E4       MOV R1 R9                ; R1 file*
0x000043E8       MOV R2 R10               ; inode*
0x000043EC       LI R3  FD_FLAG_READ      ; flags READ end
0x000043F4       BL file_init

0x000043FC       MOV R1 R9
0x00004400       BL fd_alloc                 ; insert read file to fd_table of user process

0x00004408       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00004410       CMP R1 R2
0x00004414       BEQ pipe_fail_read_file

0x0000441C       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x00004420       BL file_alloc
0x00004428       CMP R1 0
0x0000442C       BEQ pipe_fail_ia_write_fd
0x00004434       MOV R9 R1

0x00004438       BL inode_alloc      ; get inode for this end file
0x00004440       CMP R1 0
0x00004444       BEQ pipe_fail_ia_write_fd
0x0000444C       MOV R10 R1

0x00004450       LI  R2 pipe_ops         ; pipe_ops table
0x00004458       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x0000445C       LI  R4 INODE_PIPE       ; inode type PIPE
0x00004464       LI  R5 0                ; size =0
0x0000446C       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x00004474       MOV R1 R9                ; R1 file*
0x00004478       MOV R2 R10               ; inode*
0x0000447C       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x00004484       BL file_init

0x0000448C       MOV R1 R9
0x00004490       BL  fd_alloc

0x00004498       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x000044A0       CMP R1 R2
0x000044A4       BEQ pipe_fail_write_file

0x000044AC       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x000044B0       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x000044B4       LI  R2 8     ; len 2 words (8 bytes)
0x000044BC       LI  R3 1     ; mem perm to write cond
0x000044C4       BL  user_buffer_valid_range
0x000044CC       CMP R1 1
0x000044D0       BNE pipe_fail_both_fds

0x000044D8       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x000044DC       STW R11 [R7 + 4]

0x000044E0       LI R1 0
0x000044E8       STW R1 [SP + TF_R1]

0x000044EC       B trap_restore

pipe_fail:
0x000044F4       LI R1 ERR_IO
0x000044FC       STW R1 [SP + TF_R1]

0x00004500       B trap_restore

pipe_fail_both_fds:
0x00004508       MOV R12 R8
0x0000450C       MOV R1 R11
0x00004510       BL fd_remove
0x00004518       CMP R1 0
0x0000451C       BEQ pipe_fail_both_fds_read
0x00004524       BL file_free

pipe_fail_both_fds_read:
0x0000452C       MOV R1 R10
0x00004530       BL fd_remove
0x00004538       CMP R1 0
0x0000453C       BEQ pipe_fail_free_pipe_fault
0x00004544       BL file_free

pipe_fail_free_pipe_fault:
0x0000454C       MOV R1 R12
0x00004550       BL pipe_free
0x00004558       LI R1 ERR_FAULT
0x00004560       STW R1 [SP + TF_R1]

0x00004564       B trap_restore

pipe_fail_write_file:
0x0000456C       MOV R12 R8
0x00004570       MOV R1 R9
0x00004574       BL file_free
0x0000457C       MOV R1 R10
0x00004580       BL fd_remove
0x00004588       CMP R1 0
0x0000458C       BEQ pipe_fail_free_pipe_mfile
0x00004594       BL file_free

pipe_fail_free_pipe_mfile:
0x0000459C       MOV R1 R12
0x000045A0       BL pipe_free
0x000045A8       LI R1 ERR_MFILE
0x000045B0       STW R1 [SP + TF_R1]

0x000045B4       B trap_restore

pipe_fail_read_fd:
0x000045BC       MOV R12 R8
0x000045C0       MOV R1 R10
0x000045C4       BL fd_remove
0x000045CC       CMP R1 0
0x000045D0       BEQ pipe_fail_free_pipe_nfile
0x000045D8       BL file_free

pipe_fail_free_pipe_nfile:
0x000045E0       MOV R1 R12
0x000045E4       BL pipe_free
0x000045EC       LI R1 ERR_NFILE
0x000045F4       STW R1 [SP + TF_R1]

0x000045F8       B trap_restore

pipe_fail_read_file:
0x00004600       MOV R12 R8
0x00004604       MOV R1 R9
0x00004608       BL file_free
0x00004610       MOV R1 R10          ; освободить inode read end
0x00004614       BL inode_free
0x0000461C       MOV R1 R12
0x00004620       BL pipe_free
0x00004628       LI R1 ERR_MFILE
0x00004630       STW R1 [SP + TF_R1]

0x00004634       B trap_restore

pipe_fail_pipe_only:
0x0000463C       MOV R1 R8
0x00004640       BL pipe_free
0x00004648       LI R1 ERR_NFILE
0x00004650       STW R1 [SP + TF_R1]

0x00004654       B trap_restore

pipe_fail_nospc:
0x0000465C       LI R1 ERR_NOSPC
0x00004664       STW R1 [SP + TF_R1]

0x00004668       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x00004670       MOV R1 R9          ; освобождаем file (read end)
0x00004674       BL  file_free
0x0000467C       MOV R1 R8          ; освобождаем pipe
0x00004680       BL  pipe_free
0x00004688       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x00004690       STW R1 [SP + TF_R1]
0x00004694       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x0000469C       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x000046A0       BL fd_remove
0x000046A8       CMP R1 0
0x000046AC       BEQ skip_file_free_read
0x000046B4       BL file_free
skip_file_free_read:
0x000046BC       MOV R1 R9          ; освобождаем file (write end)
0x000046C0       BL file_free
0x000046C8       MOV R1 R8          ; освобождаем pipe
0x000046CC       BL pipe_free
0x000046D4       LI R1 ERR_NFILE
0x000046DC       STW R1 [SP + TF_R1]
0x000046E0       B trap_restore

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

0x000046E8       LDW R1 [SP + TF_R1]     ; argument fd

0x000046EC       BL fd_lookup            ; lookup FILE*
0x000046F4       CMP R1 0
0x000046F8       BEQ dup_badfd
0x00004700       MOV R8 R1               ; keep FILE*

0x00004704       BL file_get             ; FILE.ref++

0x0000470C       MOV R1 R8
0x00004710       BL fd_alloc             ; try to allocate new fd

0x00004718       LI R2 ERR_MFILE
0x00004720       CMP R1 R2
0x00004724       BEQ dup_fail_fd

0x0000472C       STW R1 [SP + TF_R1] ;R1 - new fd
0x00004730       B trap_restore

dup_fail_fd:

0x00004738       MOV R1 R8
0x0000473C       BL file_put

0x00004744       LI R1 ERR_MFILE     ;R1 -err + rollback
0x0000474C       STW R1 [SP + TF_R1]
0x00004750       B trap_restore

dup_badfd:

0x00004758       LI R1 ERR_BADF      ;R1 -err + file not found
0x00004760       STW R1 [SP + TF_R1]

0x00004764       B trap_restore

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

0x0000476C       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x00004770       MOV R1 R8
0x00004774       LI  R2 TIMEVAL_SIZE
0x0000477C       LI  R3 1                   ; write access
0x00004784       BL  user_buffer_valid_range

0x0000478C       CMP R1 1
0x00004790       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x00004798       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x000047A0   LI R1 CURRENT_TASK
0x000047A8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000047AC   LI R1 TASK_SIZE
0x000047B4   MUL R3 R4 R1
0x000047B8   LI R5 tasks
0x000047C0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x000047C4   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x000047C8       STW R1 [R6 + TIMEVAL_SEC]
0x000047CC       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x000047D0       MOV R1 R8                  ; user destination
0x000047D4       LI  R2 TIMEVAL_SIZE        ; size in bytes (8)
0x000047DC       MOV R4 R6                  ; kernel source

0x000047E0       BL copy_to_user

0x000047E8       CMP R1 TIMEVAL_SIZE
0x000047EC       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x000047F4       LI R1 0
0x000047FC       STW R1 [SP + TF_R1]

0x00004800       B trap_restore

gettime_badptr:

0x00004808       LI R1 ERR_FAULT
0x00004810       STW R1 [SP + TF_R1]

0x00004814       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x0000481C       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x00004820       LI R2 HEAP_START
0x00004828       CMP R8 R2
0x0000482C       BLT brk_invalid            ; if new break is below data page, return error

0x00004834       LI R2 HEAP_END
0x0000483C       CMP R8 R2
0x00004840       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00004848   LI R1 CURRENT_TASK
0x00004850   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004854   LI R1 TASK_SIZE
0x0000485C   MUL R3 R4 R1
0x00004860   LI R5 tasks
0x00004868   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x0000486C   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x00004870       STW R8 [SP + TF_R1]

0x00004874       B trap_restore

brk_invalid:
    ; Return -1
0x0000487C       LI R1 ERR_FAULT
0x00004884       STW R1 [SP + TF_R1]

0x00004888       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x00004890       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00004894   LI R1 CURRENT_TASK
0x0000489C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000048A0   LI R1 TASK_SIZE
0x000048A8   MUL R3 R4 R1
0x000048AC   LI R5 tasks
0x000048B4   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x000048B8   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x000048BC       ADD R10 R9 R8

    ; Validate it's within the data page
0x000048C0       LI R2 HEAP_START
0x000048C8       CMP R10 R2
0x000048CC       BLT sbrk_invalid

0x000048D4       LI R2 HEAP_END
0x000048DC       CMP R10 R2
0x000048E0       BGT sbrk_invalid

    ; Return old break
0x000048E8       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x000048EC   STW R10 [R5 + TASK_BREAK]

0x000048F0       B trap_restore

sbrk_invalid:
    ; Return -1
0x000048F8       LI R1 ERR_FAULT
0x00004900       STW R1 [SP + TF_R1]
0x00004904       B trap_restore

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

0x0000490C       LI  R3 timer_ticks
0x00004914       LDW R4 [R3]                ; tick counter (1 ms per tick)

    ; seconds = ticks / 1000
0x00004918       MOV R1 R4
0x0000491C       LI  R5 1000
0x00004924       DIV R1 R1 R5

    ; usec = (ticks % 1000) * 1000
0x00004928       MOD R4 R4 R5
0x0000492C       LI  R5 1000
0x00004934       MUL R2 R4 R5

0x00004938       RET

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

0x0000493C       PUSH LR

0x00004940       MOV R9 R1              ; file*
0x00004944       MOV R7 R2              ; user buffer
0x00004948       MOV R6 R3              ; requested len

0x0000494C       LDW R9 [R9 + FILE_INODE]
0x00004950       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x00004954       CMP R6 0                ;fast clear from it if len=0
0x00004958       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00004960       PUSH R7
0x00004964       PUSH R6

0x00004968       MOV R1 R7
0x0000496C       MOV R2 R6
0x00004970       LI  R3 1               ; write access
0x00004978       BL user_buffer_valid_range

0x00004980       POP R6
0x00004984       POP R7
0x00004988       CMP R1 1
0x0000498C       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00004994       LDW R4 [R9 + PIPE_COUNT]
0x00004998       CMP R4 0
0x0000499C       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x000049A4       CMP R6 R4
0x000049A8       BLT pipe_user_len

0x000049B0       MOV R5 R4
0x000049B4       B pipe_have_amount

pipe_user_len:
0x000049BC       MOV R5 R6

pipe_have_amount:
0x000049C0       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x000049C8       CMP R10 R5
0x000049CC       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x000049D4       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x000049D8       MOV R12 R9
0x000049DC       ADD R12 R12 PIPE_BUFFER
0x000049E0       ADD R12 R12 R11         ; addr += tail

0x000049E4       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x000049E8       MOV R12 R7
0x000049EC       ADD R12 R12 R10

0x000049F0       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x000049F4       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x000049F8       LI R2 255
0x00004A00       AND R11 R11 R2
0x00004A04       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00004A08       LDW R12 [R9 + PIPE_COUNT]
0x00004A0C       SUB R12 R12 1
0x00004A10       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00004A14       ADD R10 R10 1
0x00004A18       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00004A20       MOV R1 R9
0x00004A24       ADD R1 R1 PIPE_WWAIT
0x00004A28       BL waitq_wake_all
0x00004A30       MOV R1 R10          ; read bytes amount
0x00004A34       POP LR
0x00004A38       RET

pipe_read_badptr:
0x00004A3C       LI R1 ERR_FAULT
0x00004A44       POP LR
0x00004A48       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00004A4C       MOV R1 R9
0x00004A50       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00004A54       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00004A5C       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00004A64       LDW R4 [R9 + PIPE_COUNT]
0x00004A68       CMP R4 0
0x00004A6C       BNE pipe_read_retry

0x00004A74       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00004A7C       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00004A84       LI R2 0

pipe_loop:
0x00004A8C       LI  R1 MAX_PIPES
0x00004A94       CMP R2 R1
0x00004A98       BGE pipe_alloc_fail

0x00004AA0       SHL R3 R2 2

0x00004AA4       LI R4 pipe_used
0x00004AAC       ADD R4 R4 R3

0x00004AB0       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00004AB4       CMP R5 0                ; 0 -empty
0x00004AB8       BEQ pipe_found

0x00004AC0       ADD R2 R2 1
0x00004AC4       B pipe_loop

pipe_found:

0x00004ACC       LI R5 1
0x00004AD4       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00004AD8       LI R4 PIPE_SIZE
0x00004AE0       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00004AE4       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00004AEC       ADD R1 R1 R6

0x00004AF0       LI R7 0                 ; clean it up
0x00004AF8       STW R7 [R1 + PIPE_HEAD]
0x00004AFC       STW R7 [R1 + PIPE_TAIL]
0x00004B00       STW R7 [R1 + PIPE_COUNT]
0x00004B04       STW R7 [R1 + PIPE_RWAIT]
0x00004B08       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00004B0C       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00004B10       LI R1 0
0x00004B18       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00004B1C       LI R2 pipe_pool
0x00004B24       SUB R3 R1 R2

0x00004B28       LI R4 PIPE_SIZE
0x00004B30       DIV R5 R3 R4

0x00004B34       SHL R5 R5 2
0x00004B38       LI R6 pipe_used
0x00004B40       ADD R6 R6 R5

0x00004B44       LI R7 0
0x00004B4C       STW R7 [R6]

0x00004B50       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00004B54       PUSH LR

0x00004B58       MOV R9 R1
0x00004B5C       MOV R7 R2
0x00004B60       MOV R6 R3

0x00004B64       LDW R9 [R9 + FILE_INODE]
0x00004B68       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00004B6C       PUSH R7
0x00004B70       PUSH R6

0x00004B74       MOV R1 R7
0x00004B78       MOV R2 R6
0x00004B7C       LI  R3 0           ; READ access
0x00004B84       BL user_buffer_valid_range

0x00004B8C       POP R6
0x00004B90       POP R7

0x00004B94       CMP R1 1
0x00004B98       BNE pipe_write_badptr

0x00004BA0       LI R10 0               ; bytes written
pipe_write_retry:
0x00004BA8       CMP R10 R6
0x00004BAC       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00004BB4       LDW R11 [R9 + PIPE_COUNT]
0x00004BB8       LI R2 256
0x00004BC0       CMP R11 R2
0x00004BC4       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00004BCC       LDW R12 [R9 + PIPE_HEAD]

0x00004BD0       MOV R4 R7
0x00004BD4       ADD R4 R4 R10
0x00004BD8       LDB R5 [R4]     ; read byte from user buff addr

0x00004BDC       MOV R4 R9
0x00004BE0       ADD R4 R4 PIPE_BUFFER
0x00004BE4       ADD R4 R4 R12
0x00004BE8       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00004BEC       ADD R12 R12 1
0x00004BF0       LI R2 255
0x00004BF8       AND R12 R12 R2
0x00004BFC       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00004C00       LDW R4 [R9 + PIPE_COUNT]
0x00004C04       ADD R4 R4 1
0x00004C08       STW R4 [R9 + PIPE_COUNT]

; written++
0x00004C0C       ADD R10 R10 1
0x00004C10       B pipe_write_retry

pipe_write_done:
; wake readers
0x00004C18       MOV R1 R9
0x00004C1C       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x00004C20       BL waitq_wake_all
0x00004C28       MOV R1 R10      ;written bytes
0x00004C2C       POP LR
0x00004C30       RET

pipe_write_badptr:
0x00004C34       LI R1 ERR_FAULT
0x00004C3C       POP LR
0x00004C40       RET

pipe_write_empty:
0x00004C44       LI R1 0
0x00004C4C       POP LR
0x00004C50       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00004C54       MOV R1 R9
0x00004C58       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x00004C5C       LI R2 WAIT_PIPE_WRITE
0x00004C64       BL waitq_prepare_sleep
    ; race check
0x00004C6C       LDW R4 [R9 + PIPE_COUNT]
0x00004C70       LI R2 256
0x00004C78       CMP R4 R2
0x00004C7C       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00004C84       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00004C8C       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x00004C94       CMP R1 3
0x00004C98       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x00004CA0       CMP R1 MAX_FDS
0x00004CA4       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x00004CAC       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x00004CB0   LI R1 CURRENT_TASK
0x00004CB8   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00004CBC   LI R1 TASK_SIZE
0x00004CC4   MUL R3 R4 R1
0x00004CC8   LI R4 tasks
0x00004CD0   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x00004CD4   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x00004CD8       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x00004CDC       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x00004CE0       LDW R1 [R6]                 ; R1 = file* из таблицы
0x00004CE4       CMP R1 0
0x00004CE8       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x00004CF0       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x00004CF4       RET

fd_lookup_invalid:
0x00004CF8       LI R1 0
0x00004D00       LI R2 0
0x00004D08       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x00004D0C       PUSH LR
0x00004D10       BL  fd_lookup
0x00004D18       CMP R1 0
0x00004D1C       BEQ fd_remove_invalid

0x00004D24       MOV R8 R1          ; сохраняем file*
0x00004D28       LI R3 0
0x00004D30       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x00004D34       MOV R1 R8          ; file*
0x00004D38       POP LR
0x00004D3C       RET

fd_remove_invalid:
0x00004D40       LI R1 0
0x00004D48       POP LR
0x00004D4C       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00004D50       LDW R1 [SP + TF_R1]
0x00004D54       LDW R2 [SP + TF_R2]
0x00004D58       LDW R3 [SP + TF_R3]

0x00004D5C       BL vfs_read

0x00004D64       STW R1 [SP + TF_R1]
0x00004D68       B trap_restore

; to comply with vfs interface
devfs_open:
0x00004D70       LI R1 0
0x00004D78       RET
devfs_close:
0x00004D7C       LI R1 0
0x00004D84       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00004D88       PUSH LR
0x00004D8C       PUSH R8
0x00004D90       PUSH R9
0x00004D94       PUSH R10
0x00004D98       PUSH R11
0x00004D9C       PUSH R12
0x00004DA0       MOV R9 R1
0x00004DA4       MOV R7 R2
0x00004DA8       MOV R6 R3
0x00004DAC       LI R8 0                    ; total bytes collected
0x00004DB4       LDW R9 [R9 + FILE_INODE]
0x00004DB8       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00004DBC       CMP R6 0
0x00004DC0       BEQ read_done

0x00004DC8       PUSH R7
0x00004DCC       PUSH R6
0x00004DD0       PUSH R9
0x00004DD4       MOV R1 R7
0x00004DD8       MOV R2 R6
0x00004DDC       LI R3 1                ; write access for destination buffer
0x00004DE4       BL user_buffer_valid_range
0x00004DEC       POP R9
0x00004DF0       POP R6
0x00004DF4       POP R7
0x00004DF8       CMP R1 1
0x00004DFC       BNE con_read_fault

read_wait_uart_rx:
0x00004E04       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00004E08       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00004E0C       AND R5 R5 1                 ; bit 0 = RX_READY
0x00004E10       CMP R5 0
0x00004E14       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00004E1C   LI R1 CURRENT_TASK
0x00004E24   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004E28   LI R1 TASK_SIZE
0x00004E30   MUL R3 R4 R1
0x00004E34   LI R5 tasks
0x00004E3C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00004E40   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00004E44       MOV R2 R6
0x00004E48       MOV R3 R9
0x00004E4C       PUSH R6
0x00004E50       PUSH R7
0x00004E54       PUSH R8
0x00004E58       PUSH R9
0x00004E5C       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x00004E64       POP R9
0x00004E68       POP R8
0x00004E6C       POP R7
0x00004E70       POP R6

0x00004E74       CMP R1 0
0x00004E78       BEQ read_wait_uart_rx

0x00004E80       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x00004E84   LI R1 CURRENT_TASK
0x00004E8C   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x00004E90   LI R1 TASK_SIZE
0x00004E98   MUL R3 R5 R1
0x00004E9C   LI R4 tasks
0x00004EA4   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x00004EA8   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with CR/LF before copy_to_user
    ; clobbers temporary registers.
0x00004EAC       LI R11 0
0x00004EB4       SUB R5 R10 1
0x00004EB8       ADD R5 R4 R5
0x00004EBC       LDB R5 [R5]
0x00004EC0       CMP R5 10
0x00004EC4       BEQ read_chunk_line_done
0x00004ECC       CMP R5 13
0x00004ED0       BNE read_chunk_not_newline
read_chunk_line_done:
0x00004ED8       LI R11 1

read_chunk_not_newline:
0x00004EE0       PUSH R6
0x00004EE4       PUSH R7
0x00004EE8       PUSH R8
0x00004EEC       PUSH R9
0x00004EF0       PUSH R10
0x00004EF4       PUSH R11
0x00004EF8       MOV R1 R7              ; user destination
0x00004EFC       MOV R2 R10
0x00004F00       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00004F08       POP R11
0x00004F0C       POP R10
0x00004F10       POP R9
0x00004F14       POP R8
0x00004F18       POP R7
0x00004F1C       POP R6

0x00004F20       ADD R7 R7 R10
0x00004F24       ADD R8 R8 R10
0x00004F28       SUB R6 R6 R10

0x00004F2C       CMP R11 1
0x00004F30       BEQ read_complete
0x00004F38       CMP R6 0
0x00004F3C       BGT read_wait_uart_rx

read_complete:
0x00004F44       MOV R1 R8
0x00004F48       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00004F50       LI R1 uart_rx_waitq
0x00004F58       LI R2 WAIT_UART_RX
0x00004F60       BL waitq_prepare_sleep

0x00004F68       LDW R4 [R9 + UARTDEV_MMIO]
0x00004F6C       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x00004F70       AND R10 R10 1
0x00004F74       CMP R10 0
0x00004F78       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x00004F80       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x00004F88       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00004F90       LI R1 uart_rx_waitq
0x00004F98       BL waitq_cancel_sleep_current

0x00004FA0       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x00004FA8       LI R1 0
0x00004FB0       B read_return

con_read_fault:
0x00004FB8       LI R1 ERR_FAULT

read_return:
0x00004FC0       POP R12
0x00004FC4       POP R11
0x00004FC8       POP R10
0x00004FCC       POP R9
0x00004FD0       POP R8
0x00004FD4       POP LR
0x00004FD8       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00004FDC       LDW R1 [SP + TF_R1]
0x00004FE0       LDW R2 [SP + TF_R2]
0x00004FE4       LDW R3 [SP + TF_R3]

0x00004FE8       BL vfs_write

0x00004FF0       STW R1 [SP + TF_R1]
0x00004FF4       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00004FFC       PUSH LR
0x00005000       MOV R9 R1
0x00005004       MOV R7 R2
0x00005008       MOV R6 R3
0x0000500C       LDW R9 [R9 + FILE_INODE]
0x00005010       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00005014       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x0000501C       CMP R6 0
0x00005020       BEQ write_done             ;0 bytes

0x00005028       LI R2 KBUFFER_SIZE
0x00005030       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00005034       BLT write_chunk_small
0x0000503C       LI R2 KBUFFER_SIZE

0x00005044       B write_chunk

write_chunk_small:
0x0000504C       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x00005050       PUSH R7
0x00005054       PUSH R6
0x00005058       PUSH R9
0x0000505C       PUSH R8
0x00005060       MOV R1 R7
0x00005064       MOV R2 R2
0x00005068       LI R3 0                ; read access for source buffer
0x00005070       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00005078       POP R8
0x0000507C       POP R9
0x00005080       POP R6
0x00005084       POP R7
0x00005088       CMP R1 1
0x0000508C       BNE driver_bad_pointer

0x00005094       PUSH R7
0x00005098       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x0000509C   LI R1 CURRENT_TASK
0x000050A4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000050A8   LI R1 TASK_SIZE
0x000050B0   MUL R3 R4 R1
0x000050B4   LI R5 tasks
0x000050BC   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x000050C0   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x000050C4       MOV R1 R7
0x000050C8       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x000050D0       MOV R10 R1             ; bytes copied
0x000050D4       POP R6
0x000050D8       POP R7

0x000050DC       PUSH R7
0x000050E0       PUSH R9
0x000050E4       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x000050E8       LDW R1 [R9 + UARTDEV_MMIO]
0x000050EC       LDW R2 [R1 + 4]
0x000050F0       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x000050F4       CMP R2 0
0x000050F8       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00005100   LI R1 CURRENT_TASK
0x00005108   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000510C   LI R1 TASK_SIZE
0x00005114   MUL R3 R4 R1
0x00005118   LI R5 tasks
0x00005120   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00005124   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x00005128       MOV R2 R10
0x0000512C       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x00005130       BL device_write
0x00005138       POP R6
0x0000513C       POP R9
0x00005140       POP R7

0x00005144       CMP R1 0        ;nothing is written - go again
0x00005148       BEQ write_loop

0x00005150       ADD R8 R8 R1     ;update ptrs
0x00005154       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x00005158       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x0000515C       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00005164       LI R1 uart_tx_waitq
0x0000516C       LI R2 WAIT_UART_TX
0x00005174       BL waitq_prepare_sleep

0x0000517C       LDW R1 [R9 + UARTDEV_MMIO]
0x00005180       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00005184       AND R2 R2 2
0x00005188       CMP R2 0
0x0000518C       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00005194       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x0000519C       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x000051A4       LI R1 uart_tx_waitq
0x000051AC       BL waitq_cancel_sleep_current

0x000051B4       B write_wait_uart_tx

write_done:
0x000051BC       MOV R1 R8
0x000051C0       POP LR
0x000051C4       RET

driver_bad_pointer:
0x000051C8       LI R1 ERR_FAULT
0x000051D0       POP LR
0x000051D4       RET

bad_fd:
0x000051D8       LI R1 ERR_BADF
0x000051E0       STW R1 [SP + TF_R1]

0x000051E4       B trap_restore

bad_pointer:
0x000051EC       LI R1 ERR_FAULT
0x000051F4       STW R1 [SP + TF_R1]

0x000051F8       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x00005200       LDW R4 [R1 + FILE_INODE]
0x00005204       LDW R4 [R4 + INODE_OPS]
0x00005208       LDW R4 [R4 + FSOPS_READ]
0x0000520C       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00005210       LDW R4 [R1 + FILE_INODE]
0x00005214       LDW R4 [R4 + INODE_OPS]
0x00005218       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x0000521C       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00005220       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00005228       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when CR or LF is received.
0x00005230       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00005234       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x0000523C       CMP R5 R2                   ; have we read enough bytes?
0x00005240       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x00005248       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x0000524C       AND R6 R6 1                 ; bit 0 = RX_READY
0x00005250       CMP R6 0
0x00005254       BEQ dr_done                 ; no more buffered input available

0x0000525C       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x00005260       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00005264       ADD R5 R5 1

    ; If we received a line terminator, stop reading early.
0x00005268       CMP R7 10
0x0000526C       BEQ dr_done
0x00005274       CMP R7 13
0x00005278       BEQ dr_done

0x00005280       B dr_loop

dr_done:
0x00005288       MOV R1 R5                   ; return number of bytes actually read
0x0000528C       RET

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
0x00005290       PUSH LR

    ; mutex for write to console lock
0x00005294       PUSH R1
0x00005298       PUSH R2
0x0000529C       PUSH R3

    ; Lock console mutex
0x000052A0       BL console_lock

    ; Write to UART
0x000052A8       POP R3
0x000052AC       POP R2
0x000052B0       POP R1


0x000052B4       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000052B8       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000052C0       CMP R5 R2                   ; have we written all bytes?
0x000052C4       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x000052CC       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000052D0       AND R6 R6 2                 ; bit 1 = TX_READY
0x000052D4       CMP R6 0
0x000052D8       BEQ dcw_done

0x000052E0       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x000052E4       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x000052E8       ADD R5 R5 1
0x000052EC       B dcw_loop

dcw_done:
0x000052F4       MOV R1 R5                   ; return number of bytes written


 ; Unlock console mutex for exclusive write to uart device
0x000052F8       PUSH R1
0x000052FC       BL console_unlock
0x00005304       POP R1


0x00005308       POP LR
0x0000530C       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00005310       LI R1 0
0x00005318       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x0000531C       PUSH LR
0x00005320       MOV R6 R3
0x00005324       CMP R6 0
0x00005328       BEQ null_write_done

0x00005330       PUSH R6
0x00005334       MOV R1 R2
0x00005338       MOV R2 R6
0x0000533C       LI R3 0                    ; read access from user source
0x00005344       BL user_buffer_valid_range
0x0000534C       POP R6
0x00005350       CMP R1 1
0x00005354       BNE null_write_badptr

null_write_done:
0x0000535C       MOV R1 R6
0x00005360       POP LR
0x00005364       RET

null_write_badptr:
0x00005368       LI R1 ERR_FAULT
0x00005370       POP LR
0x00005374       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================
0x00005378       PUSH R5
0x0000537C       PUSH R6
0x00005380       PUSH R8

0x00005384       CMP R1 0
0x00005388       BLT fd_invalid
0x00005390       CMP R1 MAX_FDS
0x00005394       BGE fd_invalid

0x0000539C       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x000053A0   LI R1 CURRENT_TASK
0x000053A8   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000053AC   LI R1 TASK_SIZE
0x000053B4   MUL R3 R4 R1
0x000053B8   LI R4 tasks
0x000053C0   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000053C4   LDW R4 [R4 + TASK_FD_TABLE]

0x000053C8       SHL R5 R8 2
0x000053CC       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x000053D0       LDW R1 [R4]                 ; R1 = file ptr
0x000053D4       LDW R6 [R1 + FILE_FLAGS]
0x000053D8       AND R6 R6 R2
0x000053DC       CMP R6 R2
0x000053E0       BNE fd_invalid

0x000053E8       POP R8
0x000053EC       POP R6
0x000053F0       POP R5
0x000053F4       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x000053F8       POP R8
0x000053FC       POP R6
0x00005400       POP R5

0x00005404       LI R1 0
0x0000540C       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x00005410       PUSH LR
0x00005414       MOV R7 R2
0x00005418       MOV R10 R3

0x0000541C       LI R2 FD_FLAG_READ
0x00005424       BL fetch_fd_entry   ; macro inside destroys R6

0x0000542C       CMP R1 0
0x00005430       BEQ vfs_read_badfd

0x00005438       MOV R9 R1
0x0000543C       MOV R1 R9
0x00005440       MOV R2 R7
0x00005444       MOV R3 R10
0x00005448       BL file_read
0x00005450       POP LR
0x00005454       RET

vfs_read_badfd:
0x00005458       LI R1 ERR_BADF
0x00005460       POP LR
0x00005464       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x00005468       PUSH LR
0x0000546C       MOV R7 R2
0x00005470       MOV R10 R3

0x00005474       LI R2 FD_FLAG_WRITE
0x0000547C       BL fetch_fd_entry   ;macro inside desroys R6 (fixed)

0x00005484       CMP R1 0
0x00005488       BEQ vfs_write_badfd

0x00005490       MOV R9 R1
0x00005494       MOV R1 R9           ; R1 - file* acc to fd
0x00005498       MOV R2 R7
0x0000549C       MOV R3 R10
0x000054A0       BL file_write
0x000054A8       POP LR
0x000054AC       RET

vfs_write_badfd:
0x000054B0       LI R1 ERR_BADF
0x000054B8       POP LR
0x000054BC       RET






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
0x000054C0       PUSH R5
0x000054C4       PUSH R6
0x000054C8       PUSH R7
0x000054CC       PUSH R8
0x000054D0       PUSH R9
0x000054D4       PUSH R10
0x000054D8       PUSH R11
0x000054DC       PUSH R12

0x000054E0       LI R4 0
0x000054E8       CMP R2 R4
0x000054EC       BEQ uv_valid

0x000054F4       LI R4 USER_BASE
0x000054FC       CMP R1 R4
0x00005500       BLT uv_invalid

0x00005508       LI R4 USER_LIMIT
0x00005510       ADD R5 R1 R2
0x00005514       SUB R5 R5 1
0x00005518       CMP R5 R1
0x0000551C       BLT uv_invalid
0x00005524       CMP R5 R4
0x00005528       BGT uv_invalid
0x00005530       MOV R11 R1              ; save start address; task macros clobber R1
0x00005534       MOV R12 R5              ; save end address for page calculation
0x00005538       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x0000553C   LI R1 CURRENT_TASK
0x00005544   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00005548   LI R1 TASK_SIZE
0x00005550   MUL R3 R6 R1
0x00005554   LI R6 tasks
0x0000555C   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00005560   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x00005564       CMP R6 0
0x00005568       BEQ uv_invalid

uv_check_pages:
0x00005570       SHR R7 R11 12
0x00005574       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00005578       CMP R7 R8
0x0000557C       BGT uv_valid
0x00005584       SHL R9 R7 2
0x00005588       ADD R9 R9 R6
0x0000558C       LDW R10 [R9]
0x00005590       AND R5 R10 PTE_P
0x00005594       CMP R5 0
0x00005598       BEQ uv_invalid
0x000055A0       AND R5 R10 PTE_U
0x000055A4       CMP R5 0
0x000055A8       BEQ uv_invalid
0x000055B0       CMP R4 0
0x000055B4       BEQ uv_check_read
0x000055BC       AND R5 R10 PTE_W
0x000055C0       CMP R5 0
0x000055C4       BEQ uv_invalid
0x000055CC       B uv_next

uv_check_read:
0x000055D4       AND R5 R10 PTE_R
0x000055D8       CMP R5 0
0x000055DC       BEQ uv_invalid

uv_next:
0x000055E4       ADD R7 R7 1
0x000055E8       B uv_loop

uv_valid:
0x000055F0       LI R1 1
0x000055F8       POP R12
0x000055FC       POP R11
0x00005600       POP R10
0x00005604       POP R9
0x00005608       POP R8
0x0000560C       POP R7
0x00005610       POP R6
0x00005614       POP R5
0x00005618       RET

uv_invalid:
0x0000561C       LI R1 0

0x00005624       POP R12
0x00005628       POP R11
0x0000562C       POP R10
0x00005630       POP R9
0x00005634       POP R8
0x00005638       POP R7
0x0000563C       POP R6
0x00005640       POP R5
0x00005644       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00005648       PUSH R5
0x0000564C       PUSH R6
0x00005650       PUSH R7
0x00005654       LI R5 0
cfu_head:
0x0000565C       CMP R2 0
0x00005660       BEQ cfu_done
0x00005668       OR R6 R1 R4
0x0000566C       AND R6 R6 3
0x00005670       CMP R6 0
0x00005674       BEQ cfu_word
0x0000567C       LDB R7 [R1]
0x00005680       STB R7 [R4]
0x00005684       ADD R1 R1 1
0x00005688       ADD R4 R4 1
0x0000568C       ADD R5 R5 1
0x00005690       SUB R2 R2 1
0x00005694       B cfu_head
cfu_word:
0x0000569C       CMP R2 4
0x000056A0       BLT cfu_tail
0x000056A8       LDW R7 [R1]
0x000056AC       STW R7 [R4]
0x000056B0       ADD R1 R1 4
0x000056B4       ADD R4 R4 4
0x000056B8       ADD R5 R5 4
0x000056BC       SUB R2 R2 4
0x000056C0       B cfu_word
cfu_tail:
0x000056C8       CMP R2 0
0x000056CC       BEQ cfu_done
0x000056D4       LDB R7 [R1]
0x000056D8       STB R7 [R4]
0x000056DC       ADD R1 R1 1
0x000056E0       ADD R4 R4 1
0x000056E4       ADD R5 R5 1
0x000056E8       SUB R2 R2 1
0x000056EC       B cfu_tail
cfu_done:
0x000056F4       MOV R1 R5
0x000056F8       POP R7
0x000056FC       POP R6
0x00005700       POP R5
0x00005704       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00005708       PUSH R5
0x0000570C       PUSH R6
0x00005710       PUSH R7
0x00005714       LI R5 0
ctu_head:
0x0000571C       CMP R2 0
0x00005720       BEQ ctu_done
0x00005728       OR R6 R1 R4
0x0000572C       AND R6 R6 3
0x00005730       CMP R6 0
0x00005734       BEQ ctu_word
0x0000573C       LDB R7 [R4]
0x00005740       STB R7 [R1]
0x00005744       ADD R1 R1 1
0x00005748       ADD R4 R4 1
0x0000574C       ADD R5 R5 1
0x00005750       SUB R2 R2 1
0x00005754       B ctu_head
ctu_word:
0x0000575C       CMP R2 4
0x00005760       BLT ctu_tail
0x00005768       LDW R7 [R4]
0x0000576C       STW R7 [R1]
0x00005770       ADD R1 R1 4
0x00005774       ADD R4 R4 4
0x00005778       ADD R5 R5 4
0x0000577C       SUB R2 R2 4
0x00005780       B ctu_word
ctu_tail:
0x00005788       CMP R2 0
0x0000578C       BEQ ctu_done
0x00005794       LDB R7 [R4]
0x00005798       STB R7 [R1]
0x0000579C       ADD R1 R1 1
0x000057A0       ADD R4 R4 1
0x000057A4       ADD R5 R5 1
0x000057A8       SUB R2 R2 1
0x000057AC       B ctu_tail
ctu_done:
0x000057B4       MOV R1 R5
0x000057B8       POP R7
0x000057BC       POP R6
0x000057C0       POP R5
0x000057C4       RET

handle_debug:
    ; Debug trap - just return
0x000057C8       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x000057D0       CSRR R1 STVAL

0x000057D4       CMP R1 0
0x000057D8       BEQ handle_timer_irq

0x000057E0       CMP R1 1
0x000057E4       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x000057EC       LI R2 0x00102000
0x000057F4       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x000057F8       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00005800       LI R2 0x00102000
0x00005808       LI R3 0
0x00005810       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x00005814       LI R1 timer_ticks
0x0000581C       LDW R2 [R1]
0x00005820       ADD R2 R2 1
0x00005824       STW R2 [R1]

    ;================================================================
    ; Wake sleeping tasks whose time has expired
    ;================================================================

0x00005828       LI R1 sleep_waitq
0x00005830       LDW R8 [R1]                ; R8 = current sleep_waitq mask
0x00005834       LI R9 0                    ; R9 = tasks to wake bitmask
0x0000583C       LI R3 0                    ; task index

timer_wake_scan:
0x00005844       CMP R3 MAX_TASKS
0x00005848       BGE timer_wake_scan_done

    ; Check if this task is in the sleep wait queue
0x00005850       LI R6 1
0x00005858       SHL R6 R6 R3               ; bit for this task
0x0000585C       AND R7 R8 R6
0x00005860       CMP R7 0
0x00005864       BEQ timer_wake_next        ; not in sleep queue

    ; Task is sleeping, check if it's time to wake
; macro: GET_TASK_PTR R5, R3
0x0000586C   LI R1 TASK_SIZE
0x00005874   MUL R3 R3 R1
0x00005878   LI R5 tasks
0x00005880   ADD R5 R5 R3
; macro: TASK_GET_WAKE_TIME R7, R5
0x00005884   LDW R7 [R5 + TASK_WAKE_TIME]
0x00005888       CMP R2 R7                  ; current time >= wake time?
0x0000588C       BLT timer_wake_next

    ; Mark this task for wakeup
0x00005894       OR R9 R9 R6                 ; add to wake bitmask bitwize

timer_wake_next:
0x00005898       ADD R3 R3 1
0x0000589C       B timer_wake_scan

timer_wake_scan_done:
    ; If no tasks to wake, skip
0x000058A4       CMP R9 0
0x000058A8       BEQ timer_no_wake

    ; Wake the expired tasks using our new function
0x000058B0       LI R1 sleep_waitq
0x000058B8       MOV R2 R9
0x000058BC       BL waitq_wake_bitmask

timer_no_wake:

    ; Yield the CPU (reschedule and switch tasks)
0x000058C4       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x000058CC       LI R2 0x00102000
0x000058D4       LI R3 1
0x000058DC       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x000058E0       LI R1 uart_rx_waitq
0x000058E8       BL waitq_wake_all
0x000058F0       LI R1 uart_tx_waitq
0x000058F8       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00005900       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00005908       POP R1                  ; stval, informational only
0x0000590C       POP R1                  ; scause, informational only
0x00005910       POP R1
0x00005914       CSRW SSTATUS R1
0x00005918       POP R1
0x0000591C       CSRW SFLAGS R1
0x00005920       POP R1
0x00005924       CSRW SEPC R1
0x00005928       POP R1                  ; interrupted task SP
0x0000592C       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00005930       POP R15
0x00005934       POP R14
0x00005938       POP R12
0x0000593C       POP R11
0x00005940       POP R10
0x00005944       POP R9
0x00005948       POP R8
0x0000594C       POP R7
0x00005950       POP R6
0x00005954       POP R5
0x00005958       POP R4
0x0000595C       POP R3
0x00005960       POP R2
0x00005964       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00005968       CSRRW SP SSCRATCH SP
0x0000596C       SRET


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

;==============================================================
; NSFS skeleton
;==============================================================

; NSFS private vnode stored behind inode->private.
; Later this can hold a cached path key, namespace id, host handle,
; materialized size/type, dirty flags, and page-cache pointer.
.EQU NSFS_NODE_NAMESPACE, 0
.EQU NSFS_NODE_PATH,      4
.EQU NSFS_NODE_TYPE,      8
.EQU NSFS_NODE_SIZE,     12
.EQU NSFS_NODE_FLAGS,    16
.EQU NSFS_NODE_SIZEOF,   20

.EQU NSFS_DEFAULT_NS,     0
.EQU NSFS_MAX_NODES,     64

nsfs_ops:
    .WORD nsfs_open
    .WORD nsfs_read
    .WORD nsfs_write
    .WORD nsfs_close
    .WORD nsfs_readdir
    .WORD nsfs_lookup
    .WORD nsfs_create
    .WORD nsfs_unlink
    .WORD nsfs_mkdir
    .WORD nsfs_rmdir

nsfs_root_inode:
    .WORD nsfs_ops          ; INODE_OPS
    .WORD nsfs_root_node    ; INODE_PRIVATE
    .WORD INODE_DIR         ; INODE_TYPE
    .WORD 0                 ; size
    .WORD 1                 ; refcnt

nsfs_root_path:
    .ASCIIZ "/"

nsfs_root_node:
    .WORD NSFS_DEFAULT_NS
    .WORD nsfs_root_path
    .WORD INODE_DIR
    .WORD 0
    .WORD 0

nsfs_node_pool:
    .SPACE NSFS_MAX_NODES * NSFS_NODE_SIZEOF

nsfs_node_used:
    .SPACE NSFS_MAX_NODES * 4

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
    .WORD 0
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
0x00008239       LI R1 0
0x00008241       RET

tarfs_close:
0x00008245       LI R1 0
0x0000824D       RET
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

0x00008251       PUSH LR
0x00008255       PUSH R8
0x00008259       PUSH R9
0x0000825D       PUSH R10

0x00008261       MOV R8 R1              ; pathname
0x00008265       LDB R2 [R8]
0x00008269       LI R3 47               ; accept normal absolute paths: "/etc/motd"
0x00008271       CMP R2 R3
0x00008275       BNE lookup_path_ready
0x0000827D       ADD R8 R8 1

lookup_path_ready:

0x00008281       LI R9 0                ; index

0x00008289       LI R10 tar_count
0x00008291       LDW R10 [R10]

tar_lookup_loop:

0x00008295       CMP R9 R10
0x00008299       BGE tar_lookup_not_found

    ; entry address

0x000082A1       LI R1 tar_index

0x000082A9       LI R2 TAR_IDX_SIZEOF
0x000082B1       MUL R3 R9 R2
0x000082B5       ADD R1 R1 R3            ;

    ; compare names

0x000082B9       MOV R2 R8

0x000082BD       LDW R1 [R1 + TAR_IDX_NAME]

0x000082C1       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x000082C9       CMP R1 1
0x000082CD       BEQ tar_lookup_found

0x000082D5       ADD R9 R9 1
0x000082D9       B tar_lookup_loop

tar_lookup_found:

0x000082E1       LI R1 tar_index
0x000082E9       LI R2 TAR_IDX_SIZEOF
0x000082F1       MUL R3 R9 R2
0x000082F5       ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

0x000082F9       BL inode_alloc
0x00008301       CMP R1 0
0x00008305       BEQ tar_lookup_not_found
0x0000830D       MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

0x00008311       MOV R1 R10              ; inode
0x00008315       LI  R2 tarfs_ops        ; ops table
0x0000831D       MOV R3 R11              ; private = tar entry

0x00008321       LDW R4 [R11 + TAR_IDX_TYPE] ; FILE type
0x00008325       LDW R5 [R11 + TAR_IDX_SIZE] ; file size
0x00008329       BL inode_init

0x00008331       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x00008335       POP R10
0x00008339       POP R9
0x0000833D       POP R8
0x00008341       POP LR
0x00008345       RET

tar_lookup_not_found:

0x00008349       LI R1 0             ; R1 = NULL

0x00008351       POP R10
0x00008355       POP R9
0x00008359       POP R8
0x0000835D       POP LR
0x00008361       RET


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

0x00008365       PUSH LR
0x00008369       PUSH R8
0x0000836D       PUSH R9
0x00008371       PUSH R10
0x00008375       PUSH R11
0x00008379       PUSH R12

0x0000837D       MOV R8 R1                  ; current tar header
0x00008381       LI R11 tar_limit
0x00008389       ADD R2 R1 R2
0x0000838D       STW R2 [R11]               ; exclusive end of archive

0x00008391       LI R9 tar_index            ; current index entry

0x00008399       LI R10 0                   ; file count

tar_scan_loop:

0x000083A1       CMP R10 MAX_TAR_FILES
0x000083A5       BGE tar_done                ; check before writing the next index entry

0x000083AD       LI R11 tar_limit
0x000083B5       LDW R11 [R11]
0x000083B9       LI R12 TAR_HEADER_SIZE
0x000083C1       ADD R12 R8 R12
0x000083C5       CMP R12 R11
0x000083C9       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x000083D1       LDB R11 [R8 + TAR_NAME_OFF]

0x000083D5       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x000083D9       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x000083E1       MOV R11 R8

0x000083E5       ADD R11 R11 TAR_NAME_OFF

0x000083E9       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x000083ED       MOV R1 R8
0x000083F1       ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

0x000083F5       BL tar_parse_octal         ; parse octal size from tar header field to binary integer

0x000083FD       MOV R12 R1                 ; save file resulted binary size

0x00008401       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00008405       MOV R11 R8
0x00008409       LI R2 TAR_HEADER_SIZE
0x00008411       ADD R11 R11 R2

0x00008415       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00008419       LI R2 TAR_TYPE_OFF
0x00008421       ADD R2 R8 R2
0x00008425       LDB R11 [R2]
0x00008429       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x0000842D       ADD R10 R10 1               ; othewise go to next file count

0x00008431       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

0x00008435       MOV R11 R12

    ; round up to 512 boundary

0x00008439       LI R2 511
0x00008441       ADD R11 R11 R2

0x00008445       SHR R11 R11 9
0x00008449       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x0000844D       LI R2 TAR_HEADER_SIZE
0x00008455       ADD R8 R8 R2

0x00008459       ADD R8 R8 R11           ; advance to next tar header

0x0000845D       LI R12 tar_limit
0x00008465       LDW R12 [R12]
0x00008469       CMP R8 R12
0x0000846D       BGTU tar_done            ; file data/padding extends beyond archive

0x00008475       B tar_scan_loop

tar_done:

0x0000847D       LI R11 tar_count        ; store total file count for this tar archive in global variable

0x00008485       STW R10 [R11]

0x00008489       POP R12
0x0000848D       POP R11
0x00008491       POP R10
0x00008495       POP R9
0x00008499       POP R8
0x0000849D       POP LR

0x000084A1       RET

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

0x000084A5       PUSH R2
0x000084A9       PUSH R3
0x000084AD       PUSH R4

0x000084B1       LI   R2 0                  ; result

octal_loop:

0x000084B9       LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

0x000084BD       CMP  R3 0
0x000084C1       BEQ  octal_done

0x000084C9       LI   R4 32                 ; ' '
0x000084D1       CMP  R3 R4
0x000084D5       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x000084DD       LI   R4 48
0x000084E5       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x000084E9       SHL  R2 R2 3               ; multiply by 8

0x000084ED       ADD  R2 R2 R3              ; add digit

0x000084F1       ADD  R1 R1 1               ; advance to next octal character

0x000084F5       B    octal_loop

octal_done:

0x000084FD       MOV  R1 R2                 ; return binary result in R1

0x00008501       POP  R4
0x00008505       POP  R3
0x00008509       POP  R2
0x0000850D       RET

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

0x00008528       PUSH LR
0x0000852C       PUSH R8
0x00008530       PUSH R9
0x00008534       PUSH R10

0x00008538       LI R8 0

0x00008540       LI R10 tar_count
0x00008548       LDW R10 [R10]

0x0000854C       LI R1 tarfs_banner
0x00008554       BL kputs

dump_loop:

0x0000855C       CMP R8 R10
0x00008560       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00008568       LI R1 tar_index

0x00008570       LI R2 TAR_IDX_SIZEOF
0x00008578       MUL R3 R8 R2

0x0000857C       ADD R9 R1 R3

    ; filename

0x00008580       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x00008584       MOV R1 R2
0x00008588       BL kputs

    ; newline

0x00008590       LI R1 newline
0x00008598       BL kputs

0x000085A0       ADD R8 R8 1
0x000085A4       B dump_loop

dump_done:

0x000085AC       POP R10
0x000085B0       POP R9
0x000085B4       POP R8
0x000085B8       POP LR
0x000085BC       RET

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

0x000085C0       PUSH LR
0x000085C4       PUSH R8
0x000085C8       PUSH R9
0x000085CC       PUSH R10
0x000085D0       PUSH R11
0x000085D4       PUSH R12

0x000085D8       MOV R8 R1
0x000085DC       MOV R9 R2
0x000085E0       MOV R10 R3

0x000085E4       CMP R10 0
0x000085E8       BEQ tarfs_read_eof

0x000085F0       PUSH R8
0x000085F4       PUSH R9
0x000085F8       MOV R1 R9
0x000085FC       MOV R2 R10
0x00008600       LI R3 1                    ; destination must be user-writable
0x00008608       BL user_buffer_valid_range
0x00008610       POP R9
0x00008614       POP R8
0x00008618       CMP R1 1
0x0000861C       BNE tarfs_read_fault

0x00008624       LDW R11 [R8 + FILE_INODE]
0x00008628       LDW R5  [R11 + INODE_TYPE]
0x0000862C       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x00008630       LI  R2 INODE_DIR
0x00008638       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x0000863C       BEQ tarfs_read_dir

0x00008644       LDW R12 [R8 + FILE_OFFSET]
0x00008648       LDW R4  [R11 + TAR_IDX_SIZE]

0x0000864C       CMP R12 R4
0x00008650       BGEU tarfs_read_eof

0x00008658       SUB R4 R4 R12             ; bytes remaining
0x0000865C       CMP R10 R4
0x00008660       BLEU tarfs_read_count_ready
0x00008668       MOV R10 R4

tarfs_read_count_ready:
0x0000866C       LDW R4 [R11 + TAR_IDX_DATA]
0x00008670       ADD R4 R4 R12             ; kernel source
0x00008674       MOV R1 R9                 ; user destination
0x00008678       MOV R2 R10
0x0000867C       BL copy_to_user

0x00008684       ADD R12 R12 R1
0x00008688       STW R12 [R8 + FILE_OFFSET]
0x0000868C       B tarfs_read_done

tarfs_read_dir:
    ; directory read – call our dir read function
0x00008694       MOV R1 R8
0x00008698       MOV R2 R9
0x0000869C       MOV R3 R10
0x000086A0       BL tarfs_readdir
0x000086A8       B tarfs_read_done   ; jump to the common return path

tarfs_read_fault:
0x000086B0       LI R1 ERR_FAULT
0x000086B8       B tarfs_read_done

tarfs_read_eof:
0x000086C0       LI R1 0

tarfs_read_done:
0x000086C8       POP R12
0x000086CC       POP R11
0x000086D0       POP R10
0x000086D4       POP R9
0x000086D8       POP R8
0x000086DC       POP LR
0x000086E0       RET

tarfs_write:
0x000086E4       LI R1 ERR_ACCES
0x000086EC       RET

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
0x000086F0       PUSH LR
0x000086F4       PUSH R8
0x000086F8       PUSH R9
0x000086FC       PUSH R10
0x00008700       PUSH R11
0x00008704       PUSH R12

    ; ---- validate user buffer ----
0x00008708       MOV R8 R2                 ; save user buffer + to stack
0x0000870C       PUSH R8
0x00008710       MOV R9 R3                 ; save length
0x00008714       MOV R12 R1                ; save file ptr
0x00008718       CMP R9 DIRENT_SIZEOF
0x0000871C       BLT readdir_short         ; not enough space for one entry

    ;PUSH R9
0x00008724       MOV R1 R8
0x00008728       LI  R2 DIRENT_SIZEOF
0x00008730       LI  R3 1                  ; write access
0x00008738       BL  user_buffer_valid_range
    ;POP R9
0x00008740       CMP R1 1
0x00008744       BNE readdir_fault

    ; ---- get inode and private data ----
0x0000874C       LDW R4 [R12 + FILE_INODE]    ; R4 = inode* r12 -file ptf
0x00008750       LDW R5 [R4 + INODE_PRIVATE] ; R5 = tar index entry for the directory itself
0x00008754       CMP R5 0
0x00008758       BEQ readdir_eof

    ; get directory prefix from that tar entry (e.g., "etc/")
0x00008760       LDW R10 [R5 + TAR_IDX_NAME] ; R10 = full path of directory (with trailing /)

    ; load current entry index from file offset
0x00008764       LDW R11 [R12 + FILE_OFFSET] ; R11 = index (number of entries already returned)

    ; ---- scan tar index from this index ----
    ;LI R12 tar_count
    ;LDW R12 [R12]             ; total number of tar entries
0x00008768       MOV R6 R11                ; current scan index

readdir_scan:
0x0000876C       LI  R1 tar_count          ;total number entryes in index count
0x00008774       LDW R1 [R1]
0x00008778       CMP R6 R1
0x0000877C       BGE readdir_eof           ; no more entries

    ; entry = tar_index + R6 * TAR_IDX_SIZEOF
0x00008784       LI R1 tar_index
0x0000878C       LI R2 TAR_IDX_SIZEOF
0x00008794       MUL R3 R6 R2
0x00008798       ADD R7 R1 R3              ; R7 = &tar_index[R6]

    ; check if this entry's name starts with the directory prefix
0x0000879C       LDW R1 [R7 + TAR_IDX_NAME]
0x000087A0       MOV R2 R10
0x000087A4       BL str_prefix            ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000087AC       CMP R1 1
0x000087B0       BNE readdir_skip

    ; skip the directory entry itself (exact match)
0x000087B8       LDW R1 [R7 + TAR_IDX_NAME]
0x000087BC       MOV R2 R10
0x000087C0       BL strcmp                ; ie skip if we read 'etc/' == etc/
0x000087C8       CMP R1 1
0x000087CC       BEQ readdir_skip

    ; ---- found a matching file/directory ----
    ; skip the prefix to get the relative component
0x000087D4       LDW R1 [R7 + TAR_IDX_NAME]
0x000087D8       MOV R2 R10
0x000087DC       BL skip_prefix            ; R1 = pointer after prefix omit prefix - just filename 'etc/bin' -> bin
0x000087E4       MOV R9 R1                 ; R9 = component name (e.g., "motd" (file) or "network/ (subdir)")

    ; compute the component length up to next '/'
0x000087E8       MOV R1 R9
0x000087EC       BL path_component_len     ; R1 = component length (L)
0x000087F4       MOV R8 R1                 ; R8 = component name length

    ; clamp to DIRENT_NAME_LEN - 1 to avoid overflow
0x000087F8       LI R2 63
0x00008800       CMP R8 R2
0x00008804       BLE readdir_name_ok
0x0000880C       MOV R8 63
readdir_name_ok:
    ; save R6 cureent entry index
0x00008810       MOV R11 R6
    ;get type
0x00008814       LDW R6  [R7 + TAR_IDX_TYPE]  ;R6  R11 = tar type (0=file, 5=dir)

    ; map tar type to DT_* constants
0x00008818       LI  R1 INODE_DIR     ;adapted 35hex yess
0x00008820       CMP R6 R1
    ;CMP R6 5            ;needs to be adapted 35hex
0x00008824       BEQ readdir_type_dir
0x0000882C       LI R6 DT_REG               ; default type to regular r11 - file
0x00008834       B readdir_type_done
readdir_type_dir:
0x0000883C       LI R6 DT_DIR               ; switch type R11 - dir
readdir_type_done:

    ; ---- build struct dirent in KBUF_WR ----
; macro: GET_CURR_TASK_IDX R4
0x00008844   LI R1 CURRENT_TASK
0x0000884C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00008850   LI R1 TASK_SIZE
0x00008858   MUL R3 R4 R1
0x0000885C   LI R5 tasks
0x00008864   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00008868   LDW R1 [R5 + TASK_KBUF_WR_PTR]


   ; GET_CURR_TASK_IDX R2
   ; GET_TASK_PTR R2, R2
   ; TASK_GET_KBUF_WR R5, R2    ; R5 = kernel write buffer

    ; d_ino = index + 1 (dummy); R1 = kernel write buffer - form dirent stuc with read dir-entry
0x0000886C       ADD R3 R11 1
0x00008870       STW R3 [R1 + DIRENT_INODE]
    ; d_type = DT_REG or DT_DIR
0x00008874       STW R6 [R1 + DIRENT_TYPE]

    ; get size from tar entry
0x00008878       LDW R2  [R7 + TAR_IDX_SIZE]  ; R12 = file size
    ; d_size = file size
0x0000887C       STW R2  [R1 + DIRENT_SIZE]

    ; ---- update file offset to next entry ----
    ;ADD R6 R6 1
0x00008880       STW R3 [R12 + FILE_OFFSET] ; store new index R11+1 for next read


    ; d_name = component name (copy up to 64 bytes)
0x00008884       MOV R2 R9                  ; source name R9 = component name (e.g., "motd" (file) or "network/ (subdir)")
0x00008888       ADD R3 R1 DIRENT_NAME      ; destination dirent struc in KBUF_WR
0x0000888C       LI  R6 0                   ; index

readdir_copy_name:
0x00008894       CMP R6 R8                  ;R8 = component name length
0x00008898       BGE readdir_copy_name_done
0x000088A0       LDB R10 [R2 + R6]
0x000088A4       STB R10 [R3 + R6]
0x000088A8       ADD R6 R6 1
0x000088AC       B readdir_copy_name

readdir_copy_name_done:
    ; NUL-terminate
0x000088B4       LI R10 0
0x000088BC       STB R10 [R3 + R6]

    ; ---- copy whole dirent (DIRENT_SIZEOF bytes) to user buffer ----

0x000088C0       LI  R2 DIRENT_SIZEOF      ; len dirent
0x000088C8       MOV R4 R1                 ; kernel source (KBUF_WR)
0x000088CC       POP R1                    ; user buffer (original)
    ;MOV R1 R8                 ; user buffer (original)
0x000088D0       BL copy_to_user
0x000088D8       CMP R1 DIRENT_SIZEOF
0x000088DC       BNE readdir_fault

    ; return number of bytes written (DIRENT_SIZEOF)
0x000088E4       MOV R1 DIRENT_SIZEOF
0x000088E8       POP R12
0x000088EC       POP R11
0x000088F0       POP R10
0x000088F4       POP R9
0x000088F8       POP R8
0x000088FC       POP LR
0x00008900       RET

readdir_skip:
0x00008904       ADD R6 R6 1
0x00008908       B readdir_scan

readdir_eof:
0x00008910       Pop R1          ;bc we saved r8 inside loop
0x00008914       LI R1 0
0x0000891C       POP R12
0x00008920       POP R11
0x00008924       POP R10
0x00008928       POP R9
0x0000892C       POP R8
0x00008930       POP LR
0x00008934       RET

readdir_short:
0x00008938       Pop R1
0x0000893C       LI R1 ERR_FAULT
0x00008944       POP R12
0x00008948       POP R11
0x0000894C       POP R10
0x00008950       POP R9
0x00008954       POP R8
0x00008958       POP LR
0x0000895C       RET

readdir_fault:
0x00008960       Pop R1
0x00008964       LI R1 ERR_FAULT
0x0000896C       POP R12
0x00008970       POP R11
0x00008974       POP R10
0x00008978       POP R9
0x0000897C       POP R8
0x00008980       POP LR
0x00008984       RET


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

0x00008988       PUSH LR
0x0000898C       PUSH R8
0x00008990       PUSH R9
0x00008994       PUSH R10
0x00008998       PUSH R11

0x0000899C       MOV R8 R1              ; save directory path
0x000089A0       LI R9 0                ; index

0x000089A8       LI R10 tar_count
0x000089B0       LDW R10 [R10]
tr_loop:
0x000089B4       CMP R9 R10
0x000089B8       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x000089C0       LI R1 tar_index
0x000089C8       LI R2 TAR_IDX_SIZEOF
0x000089D0       MUL R3 R9 R2
0x000089D4       ADD R11 R1 R3
    ; entry name
0x000089D8       LDW R1 [R11 + TAR_IDX_NAME]
0x000089DC       MOV R2 R8                       ; src dirname "etc/"
0x000089E0       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000089E8       CMP R1 1
0x000089EC       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x000089F4       LDW R1 [R11 + TAR_IDX_NAME]
0x000089F8       MOV R2 R8                       ; prefix
0x000089FC       BL skip_prefix                  ; omit prefix nd print just filename

0x00008A04       MOV R12 R1         ; save component ptr
0x00008A08       BL path_component_len ; out R1-length
0x00008A10       MOV R2 R1
0x00008A14       MOV R1 R12
0x00008A18       BL kputsn   ; r1-ptr r2-len of string

0x00008A20       LI R1 newline
0x00008A28       BL kputs

tr_next:
0x00008A30       ADD R9 R9 1                     ;to next entry for check
0x00008A34       B tr_loop
tr_done:
0x00008A3C       POP R11
0x00008A40       POP R10
0x00008A44       POP R9
0x00008A48       POP R8
0x00008A4C       POP LR
0x00008A50       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x00008A54       PUSH LR
0x00008A58       PUSH R8
0x00008A5C       MOV R8 R1

kputs_loop:
0x00008A60       LDB R1 [R8]

0x00008A64       CMP R1 0
0x00008A68       BEQ kputs_done

0x00008A70       BL uart_putc

0x00008A78       ADD R8 R8 1

0x00008A7C       B kputs_loop

kputs_done:
0x00008A84       POP R8
0x00008A88       POP LR
0x00008A8C       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x00008A90       PUSH LR
0x00008A94       PUSH R8
0x00008A98       PUSH R9
0x00008A9C       MOV R8 R1
0x00008AA0       MOV R9 R2
kputsn_loop:
0x00008AA4       CMP R9 0
0x00008AA8       BEQ kputsn_done
0x00008AB0       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x00008AB4       BL uart_putc
0x00008ABC       ADD R8 R8 1
0x00008AC0       SUB R9 R9 1
0x00008AC4       B kputsn_loop
kputsn_done:
0x00008ACC       POP R9
0x00008AD0       POP R8
0x00008AD4       POP LR
0x00008AD8       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x00008ADC       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x00008AE4       LDW R2 [R3 + 4]   ; read UART status register
0x00008AE8       AND R2 R2 2       ; check if TX ready (bit 1)
0x00008AEC       CMP R2 0
0x00008AF0       BEQ poll

0x00008AF8       STW R1 [R3 + 0]   ; R1 is the character value
0x00008AFC       RET



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
0x00008B00       PUSH R8
0x00008B04       PUSH R9
0x00008B08       PUSH R10

0x00008B0C       MOV R9 R1                  ; preserve wait queue pointer
0x00008B10       MOV R10 R2                 ; preserve debug wait reason
0x00008B14       MOV R8 R3                  ; preserve task state to set

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x00008B18   LI R1 CURRENT_TASK
0x00008B20   LDW R2 [R1]

0x00008B24       LI R4 1
0x00008B2C       SHL R4 R4 R2               ; R4 = bit for current task
0x00008B30       LDW R5 [R9 + WQ_MASK]
0x00008B34       OR R5 R5 R4
0x00008B38       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00008B3C   LI R1 TASK_SIZE
0x00008B44   MUL R3 R2 R1
0x00008B48   LI R5 tasks
0x00008B50   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00008B54   LI R1 TASK_BLOCKED_IO
0x00008B5C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00008B60   STW R10 [R5 + TASK_WAIT]

; addition trick if R3 is set as TASK_SLEEPING then we also set the state to TASK_SLEEPING for syscall sleep/waitpid
0x00008B64       CMP R8 TASK_SLEEPING
0x00008B68       BNE waitq_prepare_done
; macro: TASK_SET_STATE R5, TASK_SLEEPING
0x00008B70   LI R1 TASK_SLEEPING
0x00008B78   STW R1 [R5 + TASK_STATE]

waitq_prepare_done:
0x00008B7C       POP R10
0x00008B80       POP R9
0x00008B84       POP R8
0x00008B88       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00008B8C       PUSH R9

0x00008B90       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00008B94   LI R1 CURRENT_TASK
0x00008B9C   LDW R2 [R1]

0x00008BA0       LDW R4 [R9 + WQ_MASK]

0x00008BA4       LI  R5 1
0x00008BAC       SHL R5 R5 R2        ;shift to position of current task bit

0x00008BB0       NOT R5 R5           ; invert to get mask for clearing this bit

0x00008BB4       AND R4 R4 R5        ; clear current task bit

0x00008BB8       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x00008BBC   LI R1 TASK_SIZE
0x00008BC4   MUL R3 R2 R1
0x00008BC8   LI R5 tasks
0x00008BD0   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x00008BD4   LI R1 TASK_READY
0x00008BDC   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x00008BE0   LI R1 WAIT_NONE
0x00008BE8   STW R1 [R5 + TASK_WAIT]

0x00008BEC       POP R9
0x00008BF0       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x00008BF4       PUSH LR
0x00008BF8       BL schedule_call
0x00008C00       POP LR
0x00008C04       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x00008C08       PUSH LR

0x00008C0C       MOV R9 R1
0x00008C10       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00008C14       LI R10 0
0x00008C1C       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x00008C20       LI R2 0                    ; task index

wq_wake_loop:
0x00008C28       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x00008C2C       BGE wq_wake_done

0x00008C34       LI R3 1
0x00008C3C       SHL R3 R3 R2               ; R3 = bit for task R2
0x00008C40       AND R4 R8 R3
0x00008C44       CMP R4 0
0x00008C48       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00008C50   LI R1 TASK_SIZE
0x00008C58   MUL R3 R2 R1
0x00008C5C   LI R5 tasks
0x00008C64   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00008C68   LI R1 TASK_READY
0x00008C70   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00008C74   LI R1 WAIT_NONE
0x00008C7C   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00008C80       ADD R2 R2 1
0x00008C84       B wq_wake_loop

wq_wake_done:
0x00008C8C       POP LR
0x00008C90       RET

waitq_wake_bitmask:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = bitmask of tasks to wake (1 = wake, 0 = ignore)
    ; Wakes every task currently recorded in the R2 bitmask.
    ;================================================================

0x00008C94       PUSH LR

0x00008C98       MOV R9 R1
0x00008C9C       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00008CA0       MOV R10 R2                 ;
0x00008CA4       NOT R10 R10                ; invert bitmask to clear only specified tasks
0x00008CA8       AND R10 R8 R10             ; clear only specified tasks
0x00008CAC       STW R10 [R9 + WQ_MASK]     ; update queue entries to remove (tobe) woken  tasks

0x00008CB0       MOV R8 R2                  ; R8 = bitmask of tasks to wake
0x00008CB4       LI R2 0                    ; task index

wq_wake_b_loop:
0x00008CBC       CMP R2 MAX_TASKS           ; check if we processed all tasks in bitmask
0x00008CC0       BGE wq_wake_b_done

0x00008CC8       LI R3 1
0x00008CD0       SHL R3 R3 R2               ; R3 = bit for task R2
0x00008CD4       AND R4 R8 R3               ; check if this task is in the wake bitmask
0x00008CD8       CMP R4 0
0x00008CDC       BEQ wq_wake_b_next

; macro: GET_TASK_PTR R5, R2        ; wake task R2 if its in the bitmask
0x00008CE4   LI R1 TASK_SIZE
0x00008CEC   MUL R3 R2 R1
0x00008CF0   LI R5 tasks
0x00008CF8   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00008CFC   LI R1 TASK_READY
0x00008D04   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00008D08   LI R1 WAIT_NONE
0x00008D10   STW R1 [R5 + TASK_WAIT]

wq_wake_b_next:
0x00008D14       ADD R2 R2 1
0x00008D18       B wq_wake_b_loop

wq_wake_b_done:
0x00008D20       POP LR
0x00008D24       RET

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
0x00009328       LI R2 0                      ; index

ia_loop:
0x00009330       CMP R2 MAX_INODES
0x00009334       BGE ia_fail

0x0000933C       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x00009340       LI R4 inode_used
0x00009348       ADD R4 R4 R3                  ; &inode_used[index]

0x0000934C       LDW R5 [R4]                   ; load used marker
0x00009350       CMP R5 0
0x00009354       BEQ ia_found

0x0000935C       ADD R2 R2 1
0x00009360       B ia_loop

ia_found:
0x00009368       LI R5 1
0x00009370       STW R5 [R4]                  ; mark used

0x00009374       LI R3 INODE_SIZEOF
0x0000937C       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x00009380       LI R1 inode_pool
0x00009388       ADD R1 R1 R6                 ; return inode ptr
0x0000938C       RET

ia_fail:
0x00009390       LI R1 0
0x00009398       RET

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

0x0000939C       LI R2 inode_pool
0x000093A4       SUB R3 R1 R2                  ; offset from pool base

0x000093A8       LI R4 INODE_SIZEOF
0x000093B0       DIV R5 R3 R4                 ; index

0x000093B4       SHL R5 R5 2                  ; index * 4 (u32 array)
0x000093B8       LI R6 inode_used
0x000093C0       ADD R6 R6 R5                 ; &inode_used[index]

0x000093C4       LI R7 0
0x000093CC       STW R7 [R6]                  ; mark free

0x000093D0       RET

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

0x000093D4       STW R2 [R1 + INODE_OPS]
0x000093D8       STW R3 [R1 + INODE_PRIVATE]
0x000093DC       STW R4 [R1 + INODE_TYPE]
0x000093E0       STW R5 [R1 + INODE_SIZE]
0x000093E4       LI R2 1
0x000093EC       STW R2 [R1 + INODE_REFCNT]
0x000093F0       RET

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
0x000093F4       LDW R2 [R1 + INODE_REFCNT]
0x000093F8       ADD R2 R2 1
0x000093FC       STW R2 [R1 + INODE_REFCNT]
0x00009400       RET

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
0x00009404       PUSH LR
0x00009408       LDW R2 [R1 + INODE_REFCNT]
0x0000940C       SUB R2 R2 1
0x00009410       STW R2 [R1 + INODE_REFCNT]
0x00009414       CMP R2 0
0x00009418       BNE inode_put_done
    ; destroy inode
0x00009420       BL inode_free

inode_put_done:
0x00009428       POP LR
0x0000942C       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x00009430       LDW R2 [R1 + FILE_REFCNT]
0x00009434       ADD R2 R2 1
0x00009438       STW R2 [R1 + FILE_REFCNT]
0x0000943C       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x00009440       PUSH LR
0x00009444       LDW R2 [R1 + FILE_REFCNT]
0x00009448       SUB R2 R2 1
0x0000944C       STW R2 [R1 + FILE_REFCNT]
0x00009450       CMP R2 0
0x00009454       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x0000945C       BL file_free

file_put_done:
0x00009464       POP LR
0x00009468       RET


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
0x0000946C       PUSH LR
0x00009470       MOV R8 R1          ; pathname

0x00009474       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x0000947C       CMP R1 0
0x00009480       BNE vfs_done

0x00009488       MOV R1 R8
0x0000948C       BL nsfs_lookup     ; 2 writable overlay above tarfs
0x00009494       CMP R1 0
0x00009498       BNE vfs_done

0x000094A0       MOV R1 R8

0x000094A4       BL tarfs_lookup     ; 3 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x000094AC       CMP R1 0
0x000094B0       BEQ vfs_not_found

vfs_done:
0x000094B8       POP LR          ;3 R1 - return inode
0x000094BC       RET

vfs_not_found:
0x000094C0       LI R1 0         ;it can be just ret but i added it for result clarity
0x000094C8       POP LR          ;or R1 - Nul
0x000094CC       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x000094D0       PUSH LR
0x000094D4       PUSH R8
0x000094D8       PUSH R9
0x000094DC       PUSH R10
0x000094E0       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x000094E4       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x000094EC       CMP R1 0
0x000094F0       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x000094F8       MOV R8 R1            ; save inode ptr

0x000094FC       LDW R2 [R8 + INODE_TYPE]
0x00009500       LI R3 INODE_DIR
0x00009508       CMP R2 R3

    ;BEQ fail_isdir            ; if pathname is a dir -implemented readdir

0x0000950C       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x00009514       CMP R1 0
0x00009518       BEQ fail_nfile

0x00009520       MOV R9 R1                ; save file*

    ; initialize file object ;
0x00009524       MOV R1 R9                ; R1 file*
0x00009528       MOV R2 R8                ; inode*
0x0000952C       MOV R3 R10               ; flags
0x00009530       BL file_init

0x00009538       MOV R1 R9
0x0000953C       BL fd_alloc             ; R1 inited file ptr
0x00009544       LI R2 ERR_MFILE
0x0000954C       CMP R1 R2
0x00009550       BEQ fail_fd
                            ; R1 - holds fd
0x00009558       POP R10
0x0000955C       POP R9
0x00009560       POP R8
0x00009564       POP LR
0x00009568       RET

fail_fd:
0x0000956C       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x00009570       LDW R2 [R1 + FILE_INODE]

0x00009574       MOV R1 R2
0x00009578       BL inode_put             ; close inode refcnt--

0x00009580       MOV R1 R9
0x00009584       BL file_free
0x0000958C       LI R1 ERR_MFILE
0x00009594       B  vfs_exit

fail_noent:
0x0000959C       LI R1 ERR_NOENT
0x000095A4       B  vfs_exit
fail_nfile:
0x000095AC       LI R1 ERR_NFILE
0x000095B4       B  vfs_exit
fail_isdir:
0x000095BC       LI R1 ERR_ISDIR
0x000095C4       B  vfs_exit
fail_acces:
0x000095CC       LI R1 ERR_ACCES
vfs_exit:
0x000095D4       POP R10
0x000095D8       POP R9
0x000095DC       POP R8
0x000095E0       POP LR
0x000095E4       RET

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
0x000095E8       PUSH LR
0x000095EC       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x000095F4       CMP R1 0
0x000095F8       BEQ badf_fail

0x00009600       MOV R8 R1          ; save file*

0x00009604       MOV R1 R8
0x00009608       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x00009610       LI  R1 0        ; success
0x00009618       POP LR
0x0000961C       RET

badf_fail:
0x00009620       LI R1 ERR_BADF
0x00009628       POP LR
0x0000962C       RET


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

0x00009630       LI R2 0                      ; index

fa_loop:
0x00009638       CMP R2 MAX_FILES
0x0000963C       BGE fa_fail

0x00009644       SHL R3 R2 2                  ; index * 4
0x00009648       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00009650       ADD R4 R4 R3

0x00009654       LDW R5 [R4]
0x00009658       CMP R5 0
0x0000965C       BEQ fa_found

0x00009664       ADD R2 R2 1
0x00009668       B fa_loop

fa_found:
0x00009670       LI R5 1
0x00009678       STW R5 [R4]                  ; mark slot used

0x0000967C       LI R4 FILE_SIZE
0x00009684       MUL R6 R2 R4

0x00009688       LI R1 file_pool
0x00009690       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x00009694       LI R7 0

0x0000969C       STW R7 [R1 + FILE_INODE]
0x000096A0       STW R7 [R1 + FILE_OFFSET]
0x000096A4       STW R7 [R1 + FILE_FLAGS]

0x000096A8       RET

fa_fail:
0x000096AC       LI R1 0
0x000096B4       RET

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
0x000096B8       PUSH LR
0x000096BC       PUSH R10
0x000096C0       MOV  R10 R1
0x000096C4       LDW  R2 [R1 + FILE_INODE]

0x000096C8       CMP R2 0
0x000096CC       BEQ no_inode

0x000096D4       MOV R1 R2
0x000096D8       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x000096E0       MOV R1 R10
0x000096E4       LI  R2 file_pool
0x000096EC       SUB R3 R1 R2                 ; offset from pool base

0x000096F0       LI  R4 FILE_SIZE
0x000096F8       DIV R5 R3 R4                 ; slot number

0x000096FC       SHL R5 R5 2                  ; slot * 4

0x00009700       LI  R6 file_used
0x00009708       ADD R6 R6 R5                 ; address of slot in file_used

0x0000970C       LI R7 0
0x00009714       STW R7 [R6]                  ; mark free
0x00009718       POP R10
0x0000971C       POP LR
0x00009720       RET


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

0x00009724       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x00009728       LI  R1 tasks
0x00009730       LI  R2 TASK_SIZE
0x00009738       LI  R3 MAX_TASKS
0x00009740       MUL R3 R2 R3
0x00009744       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x0000974C       LI R1 idle_task
0x00009754       LI R2 0
0x0000975C       LI R3 0
0x00009764       BL task_create

0x0000976C       CMP R1 0
0x00009770       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task_init
    ; ----------------------------------

0x00009778       LI R1 TASK_INIT_START
0x00009780       LI R2 1
0x00009788       LI R3 0
0x00009790       BL task_create

0x00009798       CMP R1 0
0x0000979C       BEQ init_scheduler_fail

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
0x000097A4       LI R1 task_count
0x000097AC       LI R2 2                     ; last task_pid+1 for now (task 0 and task 1) next id is 2
0x000097B4       STW R2 [R1]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x000097B8       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x000097C0   LI R1 CURRENT_TASK
0x000097C8   STW R2 [R1]

0x000097CC       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x000097D0       RET


init_scheduler_fail:

0x000097D4       DEBUG 99

halt:
0x000097D8       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x000097E0   LI R1 CURRENT_TASK
0x000097E8   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x000097EC       ADD R3 R2 1

wrap_check:

0x000097F0       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x000097F4       BLT check_task
0x000097FC       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x00009804       LI R4 TASK_SIZE
0x0000980C       MUL R5 R3 R4
0x00009810       LI R6 tasks
0x00009818       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x0000981C       LDW R7 [R5 + TASK_STATE]

0x00009820       CMP R7 1
0x00009824       BEQ do_switch
    ; if not ready go to next task in list
0x0000982C       ADD R3 R3 1
0x00009830       B wrap_check

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
0x00009838   LI R1 CURRENT_TASK
0x00009840   STW R3 [R1]
0x00009844       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x00009848   LI R1 TASK_SIZE
0x00009850   MUL R3 R2 R1
0x00009854   LI R5 tasks
0x0000985C   ADD R5 R5 R3
0x00009860       MOV R3 R8
0x00009864       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x00009868       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x0000986C   STW R7 [R5 + TASK_USP]

0x00009870       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00009874   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x00009878   LI R1 RESUME_TRAP
0x00009880   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00009884   LI R1 TASK_SIZE
0x0000988C   MUL R3 R8 R1
0x00009890   LI R5 tasks
0x00009898   ADD R5 R5 R3
0x0000989C       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x000098A0   LDW R7 [R5 + TASK_PTBR]
0x000098A4       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x000098A8   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x000098AC   LDW R7 [R9 + TASK_STATE]
0x000098B0       CMP R7 TASK_ZOMBIE
0x000098B4       BNE switch_old_reaped
0x000098BC       PUSH R5
0x000098C0       MOV R1 R9
0x000098C4       BL task_destroy
0x000098CC       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x000098D0   LDW R7 [R5 + TASK_RESUME]
0x000098D4       CMP R7 RESUME_KERNEL
0x000098D8       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x000098E0       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x000098E8       PUSH R1
0x000098EC       PUSH R2
0x000098F0       PUSH R3
0x000098F4       PUSH R4
0x000098F8       PUSH R5
0x000098FC       PUSH R6
0x00009900       PUSH R7
0x00009904       PUSH R8
0x00009908       PUSH R9
0x0000990C       PUSH R10
0x00009910       PUSH R11
0x00009914       PUSH R12
0x00009918       PUSH R14
0x0000991C       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00009920   LI R1 CURRENT_TASK
0x00009928   LDW R2 [R1]

0x0000992C       ADD R3 R2 1

schedule_call_wrap_check:
0x00009930       CMP R3 MAX_TASKS
0x00009934       BLT schedule_call_check_task
0x0000993C       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00009944       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x00009948   LI R1 TASK_SIZE
0x00009950   MUL R3 R8 R1
0x00009954   LI R5 tasks
0x0000995C   ADD R5 R5 R3
0x00009960       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00009964   LDW R7 [R5 + TASK_STATE]
0x00009968       CMP R7 TASK_READY               ; check it can be run
0x0000996C       BEQ schedule_call_do_switch

0x00009974       ADD R3 R3 1
0x00009978       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00009980   LI R1 CURRENT_TASK
0x00009988   STW R3 [R1]
0x0000998C       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00009990   LI R1 TASK_SIZE
0x00009998   MUL R3 R2 R1
0x0000999C   LI R5 tasks
0x000099A4   ADD R5 R5 R3
0x000099A8       MOV R3 R8

0x000099AC       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x000099B0   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x000099B4   LI R1 RESUME_KERNEL
0x000099BC   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x000099C0   LI R1 TASK_SIZE
0x000099C8   MUL R3 R8 R1
0x000099CC   LI R5 tasks
0x000099D4   ADD R5 R5 R3
0x000099D8       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x000099DC   LDW R7 [R5 + TASK_PTBR]
0x000099E0       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x000099E4   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x000099E8   LDW R7 [R5 + TASK_RESUME]
0x000099EC       CMP R7 RESUME_KERNEL
0x000099F0       BEQ restore_kernel_context

0x000099F8       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x00009A00       DISABLEINT                  ; RET does jump by LR(R15)
0x00009A04       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x00009A08       POP R14                     ; (in kernel)
0x00009A0C       POP R12                     ; DI - to avoid int nesting
0x00009A10       POP R11
0x00009A14       POP R10
0x00009A18       POP R9
0x00009A1C       POP R8
0x00009A20       POP R7
0x00009A24       POP R6
0x00009A28       POP R5
0x00009A2C       POP R4
0x00009A30       POP R3
0x00009A34       POP R2
0x00009A38       POP R1
0x00009A3C       RET
; ================================================================
; Memory and user space layout
; ================================================================

.EQU PAGE_SIZE      4096
.EQU PAGE_SHIFT     12

.EQU PAGE_ALLOC_BASE 0x00050000

.EQU MAX_PHYS_PAGES 128
.EQU PAGE_ALLOC_END  0x000D0000

; new page allocation data with refcounts and bitmap for 128 pages of 4KB each (512KB total)
page_refcounts:
    .SPACE MAX_PHYS_PAGES        ; one byte per page, initialized to 0

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

page_alloc0:
0x00009AD0       PUSH  R5
0x00009AD4       PUSH  R6
0x00009AD8       PUSH  R7
0x00009ADC       PUSH  R8
0x00009AE0       PUSH  R9

0x00009AE4       LI R2 0                  ; page index

pa_loop:
0x00009AEC       LI R1 MAX_PHYS_PAGES

0x00009AF4       CMP R2 R1
0x00009AF8       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00009B00       MOV R3 R2
0x00009B04       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x00009B08       MOV R4 R2
0x00009B0C       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00009B10       LI R5 page_bitmap
0x00009B18       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x00009B1C       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x00009B20       LI R7 1
0x00009B28       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x00009B2C       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x00009B30       CMP R8 0
0x00009B34       BEQ pa_found                ; if bit is 0, page is free

0x00009B3C       ADD R2 R2 1                 ; increment page index and check next page
0x00009B40       B pa_loop

pa_found:

    ; mark page allocated

0x00009B48       OR  R6 R6 R7
0x00009B4C       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x00009B50       LI  R9 PAGE_ALLOC_BASE

0x00009B58       MOV R1 R2
0x00009B5C       SHL R1 R1 12          ; page_index * 4096

0x00009B60       ADD R1 R1 R9

0x00009B64       POP R9
0x00009B68       POP R8
0x00009B6C       POP R7
0x00009B70       POP R6
0x00009B74       POP R5

0x00009B78       RET

pa_fail:

0x00009B7C       LI R1 0                     ; no free pages

0x00009B84       POP R9
0x00009B88       POP R8
0x00009B8C       POP R7
0x00009B90       POP R6
0x00009B94       POP R5
0x00009B98       RET


;new page allocation routine with refcounts and bitmap for 128 pages of 4KB each (512KB total)

page_alloc:
0x00009B9C       PUSH R6
0x00009BA0       PUSH R7
0x00009BA4       PUSH R8
0x00009BA8       PUSH R9

0x00009BAC       LI R2 0                     ; page index

pa1_loop:
0x00009BB4       LI R1 MAX_PHYS_PAGES
0x00009BBC       CMP R2 R1
0x00009BC0       BGE pa1_fail

0x00009BC8       LI R1 page_refcounts
    ;ADD R5 R1 R2               ; address of refcount for this page
0x00009BD0       LDB R6 [R1 + R2]           ; load refcount
0x00009BD4       CMP R6 0
0x00009BD8       BEQ pa1_found

0x00009BE0       ADD R2 R2 1
0x00009BE4       B pa1_loop

pa1_found:
0x00009BEC       LI R6 1
0x00009BF4       STB R6 [R1 + R2]          ; set refcount = 1

0x00009BF8       LI R9 PAGE_ALLOC_BASE
0x00009C00       MOV R1 R2
0x00009C04       SHL R1 R1 12                ; index * PAGE_SIZE (4kB)
0x00009C08       ADD R1 R1 R9                ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x00009C0C       POP R9
0x00009C10       POP R8
0x00009C14       POP R7
0x00009C18       POP R6                     ; R1 = physical address of allocated page
0x00009C1C       RET

pa1_fail:
0x00009C20       LI R1 0                     ; no free pages
0x00009C28       POP R9
0x00009C2C       POP R8
0x00009C30       POP R7
0x00009C34       POP R6
0x00009C38       RET

;=================================================================
; page_get - increment refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_get:
    ; R1 = physical address
    ; Returns nothing; ignores invalid addresses
0x00009C3C       CMP R1 0
0x00009C40       BEQ page_get_done

    ; Check lower bound
0x00009C48       LI R2 PAGE_ALLOC_BASE
0x00009C50       CMP R1 R2
0x00009C54       BLT page_get_done

    ; Check upper bound (exclusive)
0x00009C5C       LI R2 PAGE_ALLOC_END
0x00009C64       CMP R1 R2
0x00009C68       BGE page_get_done

    ; Calculate index
0x00009C70       LI R2 PAGE_ALLOC_BASE
0x00009C78       SUB R2 R1 R2       ; R1 pa
0x00009C7C       SHR R2 R2 12       ; R2 = page index in refcounts array
0x00009C80       LI R3 page_refcounts
0x00009C88       ADD R3 R3 R2
0x00009C8C       LDB R4 [R3]
0x00009C90       ADD R4 R4 1                 ; increment refcount
0x00009C94       STB R4 [R3]
page_get_done:
0x00009C98       RET

;=================================================================
; page_put - decrement refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_put:
    ; R1 = physical address
0x00009C9C       CMP R1 0                        ;if address is 0 - ignore
0x00009CA0       BEQ page_put_done

0x00009CA8       LI R2 PAGE_ALLOC_BASE           ;check R1 is valid
0x00009CB0       CMP R1 R2
0x00009CB4       BLT page_put_done

0x00009CBC       LI R2 PAGE_ALLOC_END
0x00009CC4       CMP R1 R2
0x00009CC8       BGE page_put_done

0x00009CD0       LI R2 PAGE_ALLOC_BASE
0x00009CD8       SUB R2 R1 R2
0x00009CDC       SHR R2 R2 12        ; R2 = page index in refcounts array
0x00009CE0       LI R3 page_refcounts
0x00009CE8       ADD R3 R3 R2
0x00009CEC       LDB R4 [R3]
0x00009CF0       CMP R4 0
0x00009CF4       BEQ page_put_done               ;if refcount already 0 - ignore it was freed already
0x00009CFC       SUB R4 R4 1                     ;decrement refcount
0x00009D00       STB R4 [R3]
    ; If refcount becomes 0, the page is now free (no further action needed)
page_put_done:
0x00009D04       RET


;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free0:
0x00009D08       PUSH  R5
0x00009D0C       PUSH  R6
0x00009D10       PUSH  R7
0x00009D14       PUSH  R8
0x00009D18       PUSH  R9


0x00009D1C       LI R2 PAGE_ALLOC_BASE
0x00009D24       SUB R3 R1 R2         ; calculate offset from base

0x00009D28       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x00009D2C       MOV R4 R3
0x00009D30       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x00009D34       MOV R5 R3
0x00009D38       AND R5 R5 7          ; bit index in byte = page index % 8

0x00009D3C       LI R6 page_bitmap
0x00009D44       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x00009D48       LDB R7 [R6]

0x00009D4C       LI R8 1
0x00009D54       SHL R8 R8 R5         ; mask for this page's bit

0x00009D58       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00009D5C       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x00009D60       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x00009D64       POP R9
0x00009D68       POP R8
0x00009D6C       POP R7
0x00009D70       POP R6
0x00009D74       POP R5
0x00009D78       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:
0x00009D7C       LI R2 0
pz_loop:
0x00009D84       CMP R3 0
0x00009D88       BEQ pz_done
0x00009D90       STB R2 [R1]
0x00009D94       ADD R1 R1 1
0x00009D98       SUB R3 R3 1
0x00009D9C       B pz_loop
pz_done:
0x00009DA4       RET

;=================================================================
; memory copy at the given address (R1)<(R2) R3 = amount
;=================================================================

memcpy:

cpy_loop:
0x00009DA8       CMP R3 0
0x00009DAC       BEQ cpy_done
0x00009DB4       LDB R4 [R2]
0x00009DB8       STB R4 [R1]
0x00009DBC       ADD R1 R1 1
0x00009DC0       ADD R2 R2 1
0x00009DC4       SUB R3 R3 1
0x00009DC8       B cpy_loop
cpy_done:
0x00009DD0       RET

; ================================================================
; Copy a memory page (or other multiple of 4 bytes) by physical address.
; R1 = source physical address (should be aligned!)
; R2 = destination physical address (aligned!)
; R3 = size in bytes (must be multiple of 4)
; each time it copyes 4 bytes (1 word)
; ================================================================
page_copy:

page_copy_loop:
0x00009DD4       CMP R3 0
0x00009DD8       BEQ page_copy_done
0x00009DE0       LDW R4 [R1]
0x00009DE4       STW R4 [R2]
0x00009DE8       ADD R1 R1 4
0x00009DEC       ADD R2 R2 4
0x00009DF0       SUB R3 R3 4
0x00009DF4       B page_copy_loop

page_copy_done:
0x00009DFC       RET

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

0x0000A304       PUSH LR

0x0000A308       MOV R8 R1          ; entry
0x0000A30C       MOV R9 R2          ; pid
0x0000A310       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x0000A318       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x0000A320       CMP R1 0
0x0000A324       BEQ task_create_fail

0x0000A32C       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x0000A330       MOV R1 R10
0x0000A334       LI R3 TASK_SIZE
0x0000A33C       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x0000A344   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x0000A348   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x0000A34C       BL page_alloc
0x0000A354       CMP R1 0
0x0000A358       BEQ task_create_fail

0x0000A360       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x0000A364   STW R1 [R10 + TASK_PTBR]

0x0000A368       MOV R1 R12
0x0000A36C       LI  R3 PAGE_SIZE
0x0000A374       BL  mem_zero                   ; zero out the sensitive new page table

0x0000A37C       MOV R1 R12
0x0000A380       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x0000A388   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x0000A38C   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x0000A390   LDW R1 [R10 + TASK_PTBR]
0x0000A394       MOV R2 R8
0x0000A398       LI R3 0xFFFFF000
0x0000A3A0       AND R2 R2 R3
0x0000A3A4       MOV R3 R2
0x0000A3A8       CMP R9 0
0x0000A3AC       BEQ task_create_map_kernel_entry
0x0000A3B4       LI R4 USER_RX
0x0000A3BC       B task_create_map_entry
task_create_map_kernel_entry:
0x0000A3C4       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x0000A3CC       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x0000A3D4       BL page_alloc
0x0000A3DC       CMP R1 0
0x0000A3E0       BEQ task_create_fail

0x0000A3E8       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x0000A3EC   STW R12 [R10 + TASK_USTACK_PAGE]

0x0000A3F0       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x0000A3F8   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x0000A3FC   LDW R1 [R10 + TASK_PTBR]

0x0000A400       LI  R2 USER_STACK_VA
0x0000A408       MOV R3 R12
0x0000A40C       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x0000A414       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x0000A41C       BL page_alloc
0x0000A424       CMP R1 0
0x0000A428       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x0000A430   STW R1 [R10 + TASK_KSTACK_PAGE]
0x0000A434       LI R2 PAGE_SIZE

0x0000A43C       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x0000A440       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x0000A444   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x0000A448   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x0000A44C       LI R1 0

0x0000A454       PUSH R1            ; R1
0x0000A458       PUSH R1            ; R2
0x0000A45C       PUSH R1            ; R3
0x0000A460       PUSH R1            ; R4
0x0000A464       PUSH R1            ; R5
0x0000A468       PUSH R1            ; R6
0x0000A46C       PUSH R1            ; R7
0x0000A470       PUSH R1            ; R8
0x0000A474       PUSH R1            ; R9
0x0000A478       PUSH R1            ; R10
0x0000A47C       PUSH R1            ; R11
0x0000A480       PUSH R1            ; R12
0x0000A484       PUSH R1            ; R14 (FP)
0x0000A488       PUSH R1            ; R15 (LR)

0x0000A48C       PUSH R11           ; R11 - user SP top

0x0000A490       MOV R1 R8
0x0000A494       PUSH R1            ; sepc = entry

0x0000A498       LI R1 0
0x0000A4A0       PUSH R1            ; sflags

0x0000A4A4       CMP R9 0
0x0000A4A8       BEQ task_create_kernel_status
0x0000A4B0       LI R1 0x20
0x0000A4B8       B task_create_status_ready
task_create_kernel_status:
0x0000A4C0       LI R1 0x120
task_create_status_ready:
0x0000A4C8       PUSH R1            ; sstatus

0x0000A4CC       LI R1 0
0x0000A4D4       PUSH R1            ; scause
0x0000A4D8       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x0000A4DC       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x0000A4E0   STW R1 [R10 + TASK_KSP]

0x0000A4E4       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x0000A4E8   LI R1 WAIT_NONE
0x0000A4F0   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x0000A4F4   LI R1 RESUME_TRAP
0x0000A4FC   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x0000A500       BL page_alloc
0x0000A508       CMP R1 0
0x0000A50C       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x0000A514       MOV R12 R1

0x0000A518       LI  R3 PAGE_SIZE
0x0000A520       MOV R1 R12
0x0000A524       BL  mem_zero

    ; stdin
0x0000A52C       LI  R2 file_stdin
0x0000A534       STW R2 [R12 + 0]

    ; stdout
0x0000A538       LI  R2 file_stdout
0x0000A540       STW R2 [R12 + 4]

    ; stderr
0x0000A544       LI  R2 file_stderr
0x0000A54C       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x0000A550   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x0000A554       BL page_alloc
0x0000A55C       CMP R1 0
0x0000A560       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x0000A568   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x0000A56C       BL page_alloc
0x0000A574       CMP R1 0
0x0000A578       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x0000A580   STW R1 [R10 + TASK_KBUF_RD_PTR]

    ; ----------------------------------
    ; data page - for user buffers and heap
    ; ----------------------------------

0x0000A584       BL page_alloc
0x0000A58C       CMP R1 0
0x0000A590       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x0000A598   STW R1 [R10 + TASK_DATA_PAGE]

0x0000A59C       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x0000A5A0   LDW R1 [R10 + TASK_PTBR]
0x0000A5A4       LI  R2 USER_DATA_VA
0x0000A5AC       MOV R3 R12
0x0000A5B0       LI  R4 USER_RW
0x0000A5B8       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; initialize code page pointer to zero until execve or static code assignment
    ; This means the task currently has no execve-loaded program image.
    ; When execve runs, TASK_CODE_PAGE will be updated to point to the
    ; physical page currently mapped at USER_CODE_VA.
0x0000A5C0       LI R1 0
; macro: TASK_SET_CODE_PAGE R10, R1
0x0000A5C8   STW R1 [R10 + TASK_CODE_PAGE]

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x0000A5CC   LI R1 TASK_READY
0x0000A5D4   STW R1 [R10 + TASK_STATE]

    ; Initialize program break pointer to HEAP_START in User_Data_VA
0x0000A5D8       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x0000A5E0   STW R1 [R10 + TASK_BREAK]

    ; Initialize parent PID to 0 by default
0x0000A5E4       LI R1 0
; macro: TASK_SET_PPID R10, R1
0x0000A5EC   STW R1 [R10 + TASK_PPID]

0x0000A5F0       MOV R1 R10                              ; return created task pointer

0x0000A5F4       POP LR
0x0000A5F8       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x0000A5FC       CMP R10 0
0x0000A600       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x0000A608   LDW R1 [R10 + TASK_PTBR]
0x0000A60C       CMP R1 0
0x0000A610       BEQ task_create_free_ustack
0x0000A618       BL page_put

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x0000A620   LDW R1 [R10 + TASK_USTACK_PAGE]
0x0000A624       CMP R1 0
0x0000A628       BEQ task_create_free_kstack
0x0000A630       BL page_put

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x0000A638   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x0000A63C       CMP R1 0
0x0000A640       BEQ task_create_free_fd
0x0000A648       BL page_put

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x0000A650   LDW R1 [R10 + TASK_FD_TABLE]
0x0000A654       CMP R1 0
0x0000A658       BEQ task_create_free_kwr
0x0000A660       BL page_put

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x0000A668   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000A66C       CMP R1 0
0x0000A670       BEQ task_create_free_krd
0x0000A678       BL page_put

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x0000A680   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000A684       CMP R1 0
0x0000A688       BEQ task_create_free_data
0x0000A690       BL page_put

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x0000A698   LDW R1 [R10 + TASK_DATA_PAGE]
0x0000A69C       CMP R1 0
0x0000A6A0       BEQ task_create_clear_slot
0x0000A6A8       BL page_put

task_create_clear_slot:
0x0000A6B0       MOV R1 R10
0x0000A6B4       LI R3 TASK_SIZE
0x0000A6BC       BL mem_zero

task_create_fail_return:
0x0000A6C4       LI R1 0

0x0000A6CC       POP LR
0x0000A6D0       RET

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
0x0000A6D4       MOV  R8 SP ;save sp to point to task trapframe!
0x0000A6D8       PUSH LR

    ; Get the current task slot and parent task pointer.
; macro: GET_CURR_TASK_IDX R6
0x0000A6DC   LI R1 CURRENT_TASK
0x0000A6E4   LDW R6 [R1]
; macro: GET_TASK_PTR R7, R6           ; R7 = parent task*
0x0000A6E8   LI R1 TASK_SIZE
0x0000A6F0   MUL R3 R6 R1
0x0000A6F4   LI R7 tasks
0x0000A6FC   ADD R7 R7 R3

    ; Allocate a fresh child task slot.
0x0000A700       BL task_alloc
0x0000A708       CMP R1 0
0x0000A70C       BEQ clone_fail
0x0000A714       MOV R10 R1                    ; R10 = child task*

    ; Clear the new child task slot before use.
0x0000A718       MOV R1 R10
0x0000A71C       LI R3 TASK_SIZE
0x0000A724       BL mem_zero

    ; Assign a new PID from the dynamic pid counter.
0x0000A72C       LI R1 task_count
0x0000A734       LDW R2 [R1]

; macro: TASK_SET_PID R10, R2        ; set new child task Pid to child task (current task_count value)
0x0000A738   STW R2 [R10 + TASK_PID]
0x0000A73C       ADD R2 R2 1
0x0000A740       STW R2 [R1]                 ; update task_count as we created a new task

    ; Set child parent PID to the current task's PID.
; macro: TASK_GET_PID R2, R7
0x0000A744   LDW R2 [R7 + TASK_PID]
; macro: TASK_SET_PPID R10, R2       ; pid - new, ppid - parent task's pid (new task)
0x0000A748   STW R2 [R10 + TASK_PPID]

    ; Copy the current task's program break.
; macro: TASK_GET_BREAK R2, R7
0x0000A74C   LDW R2 [R7 + TASK_BREAK]
; macro: TASK_SET_BREAK R10, R2
0x0000A750   STW R2 [R10 + TASK_BREAK]

    ; Copy current task PC for debugging/metadata.
; macro: TASK_GET_PC R2, R7
0x0000A754   LDW R2 [R7 + TASK_PC]
; macro: TASK_SET_PC R10, R2
0x0000A758   STW R2 [R10 + TASK_PC]

    ; Allocate and initialize a fresh page table for the child.
0x0000A75C       BL page_alloc
0x0000A764       CMP R1 0
0x0000A768       BEQ clone_fail
0x0000A770       MOV R11 R1
; macro: TASK_SET_PTBR R10, R11
0x0000A774   STW R11 [R10 + TASK_PTBR]

    ; Clone the parent's entire page table into the child.
; macro: TASK_GET_PTBR R1, R7
0x0000A778   LDW R1 [R7 + TASK_PTBR]
0x0000A77C       MOV R2 R11
0x0000A780       LI R3 PAGE_SIZE
0x0000A788       BL page_copy

    ; child will inherit code page pa from parent
; macro: TASK_GET_CODE_PAGE R2, R7   ; R2 = parent's code page PA
0x0000A790   LDW R2 [R7 + TASK_CODE_PAGE]
; macro: TASK_SET_CODE_PAGE R10, R2  ; set child's code page PA to parent's code page PA
0x0000A794   STW R2 [R10 + TASK_CODE_PAGE]
    ; Now increment refcount for the shared code page (if code page is allocated).
    ;(it is in case when execve was called before fork or when fork-execve, then fork-execve, then fork-execve etc. - all children share the same code page)
0x0000A798       CMP R2 0
0x0000A79C       BEQ skip_code_get
0x0000A7A4       MOV R1 R2
0x0000A7A8       BL page_get     ;increment refcount for the shared code page (if code page is allocated)
skip_code_get:

    ; The child has inherited the parent's kernel and code mappings.
    ; We will override the user stack and data mappings below.
    ; Allocate and clone the user stack page.
0x0000A7B0       BL page_alloc
0x0000A7B8       CMP R1 0
0x0000A7BC       BEQ clone_fail
0x0000A7C4       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12   ; set new page as child user stack page
0x0000A7C8   STW R12 [R10 + TASK_USTACK_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x0000A7CC   LDW R1 [R10 + TASK_PTBR]
0x0000A7D0       LI R2 USER_STACK_VA
0x0000A7D8       MOV R3 R12
0x0000A7DC       LI R4 USER_RW
0x0000A7E4       BL map_page             ; map user stack page to child ptbr

; macro: TASK_GET_USTACK_PAGE R1, R7
0x0000A7EC   LDW R1 [R7 + TASK_USTACK_PAGE]
0x0000A7F0       MOV R2 R12
0x0000A7F4       LI R3 PAGE_SIZE
0x0000A7FC       BL page_copy            ; copy parent user stack page -> child user stack page

    ; Allocate and clone the user data page.
0x0000A804       BL page_alloc
0x0000A80C       CMP R1 0
0x0000A810       BEQ clone_fail
0x0000A818       MOV R12 R1
; macro: TASK_SET_DATA_PAGE R10, R12     ; set new page as child user data page
0x0000A81C   STW R12 [R10 + TASK_DATA_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x0000A820   LDW R1 [R10 + TASK_PTBR]
0x0000A824       LI R2 USER_DATA_VA
0x0000A82C       MOV R3 R12
0x0000A830       LI R4 USER_RW
0x0000A838       BL map_page                     ; map user data page to child ptbr

; macro: TASK_GET_DATA_PAGE R1, R7
0x0000A840   LDW R1 [R7 + TASK_DATA_PAGE]
0x0000A844       MOV R2 R12
0x0000A848       LI R3 PAGE_SIZE
0x0000A850       BL page_copy                    ; copy parent user data page -> child user data page

    ; Clone the fd table and honor open file refcounts.
0x0000A858       BL page_alloc
0x0000A860       CMP R1 0
0x0000A864       BEQ clone_fail

0x0000A86C       MOV R12 R1

; macro: TASK_SET_FD_TABLE R10, R12       ; set new page as child fd table page
0x0000A870   STW R12 [R10 + TASK_FD_TABLE]
0x0000A874       LI R3 PAGE_SIZE
0x0000A87C       MOV R1 R12
0x0000A880       BL mem_zero                     ; clear the child fd table page just in case

; macro: TASK_GET_FD_TABLE R1, R7         ; R1 - parent fd table page
0x0000A888   LDW R1 [R7 + TASK_FD_TABLE]
0x0000A88C       CMP R1 0
0x0000A890       BEQ clone_fd_done                ; if parent has no fd table, skip fd cloning

    ; parent → child copy FIRST
0x0000A898       MOV R1 R1        ; parent fd page
0x0000A89C       MOV R2 R12       ; child fd page
0x0000A8A0       LI R3 PAGE_SIZE
0x0000A8A8       BL page_copy

0x0000A8B0       LI R4 3                      ; fd index loop + 3 stdin/out/err refcount=1, so start at 3

clone_fd_loop:
0x0000A8B8       CMP R4 MAX_FDS
0x0000A8BC       BGE clone_fd_done

0x0000A8C4       SHL R5 R4 2                 ; multiply fd index by 4 to get byte offset
0x0000A8C8       ADD R6 R12 R5               ; R6 = &child_fd_table[i]

0x0000A8CC       LDW R7 [R6]                 ; R7 = file* from child fd table
0x0000A8D0       CMP R7 0
0x0000A8D4       BEQ clone_fd_next           ; if fd slot is empty, skip to next

0x0000A8DC       MOV R1 R7                   ; IMPORTANT: isolate argument
0x0000A8E0       BL file_get                 ; increment refcount of the file* in child fd table

clone_fd_next:
0x0000A8E8       ADD R4 R4 1
0x0000A8EC       B clone_fd_loop

clone_fd_done:
    ; Allocate fresh kernel buffers for the child.
0x0000A8F4       BL page_alloc
0x0000A8FC       CMP R1 0
0x0000A900       BEQ clone_fail

; macro: TASK_SET_KBUF_WR R10, R1        ; set new page as child kernel write buffer
0x0000A908   STW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000A90C       LI R3 PAGE_SIZE
0x0000A914       BL mem_zero                     ; zero out the child kernel write buffer

0x0000A91C       BL page_alloc
0x0000A924       CMP R1 0
0x0000A928       BEQ clone_fail
; macro: TASK_SET_KBUF_RD R10, R1        ; set new page as child kernel read buffer
0x0000A930   STW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000A934       LI R3 PAGE_SIZE
0x0000A93C       BL mem_zero                     ; zero out the child kernel read buffer

    ; Allocate and initialize the child's kernel stack.
0x0000A944       BL page_alloc
0x0000A94C       CMP R1 0
0x0000A950       BEQ clone_fail
0x0000A958       MOV R12 R1
; macro: TASK_SET_KSTACK_PAGE R10, R12   ; set new page as child kernel stack page
0x0000A95C   STW R12 [R10 + TASK_KSTACK_PAGE]
0x0000A960       LI R3 PAGE_SIZE
0x0000A968       ADD R12 R12 R3                  ; R12 = child kernel stack top


    ; Copy the current kernel trapframe into the child's new kernel stack.
    ; The trapframe is at SP + 24 (after 6 pushes of 4 bytes each)
    ; Child trapframe goes at the top of child's stack (R12 - 80)
0x0000A96C       MOV R1 R8                     ; R1 = parent trapframe BASE saved in the beginiig of func
0x0000A970       MOV R6 R12
0x0000A974       LI R5 80                    ; trapframe size in bytes
0x0000A97C       SUB R6 R6 R5               ; R6 = child trapframe base inside new kernel stack
0x0000A980       MOV R2 R6
0x0000A984       LI R3 80
0x0000A98C       BL page_copy                ; so we copy 80 bytes from SP to R12-80 (child trapframe base)

    ; Return 0 in the child syscall result register.
0x0000A994       LI R4 0
0x0000A99C       STW R4 [R6 + TF_R1]


    ; Preserve the user SP for later trap/schedule bookkeeping.
    ; User SP is already in the trapframe we copied
    ; But we also need to set it in the child's task struct
0x0000A9A0       LDW R4 [R6 + TF_USP]
; macro: TASK_SET_USP R10, R4
0x0000A9A4   STW R4 [R10 + TASK_USP]

    ; Save the child kernel trapframe pointer and make it runnable.
; macro: TASK_SET_KSP R10, R6                    ;R6 = child trapframe base inside new kernel stack
0x0000A9A8   STW R6 [R10 + TASK_KSP]
; macro: TASK_SET_RESUME R10, RESUME_TRAP
0x0000A9AC   LI R1 RESUME_TRAP
0x0000A9B4   STW R1 [R10 + TASK_RESUME]
; macro: TASK_SET_WAIT R10, WAIT_NONE
0x0000A9B8   LI R1 WAIT_NONE
0x0000A9C0   STW R1 [R10 + TASK_WAIT]
; macro: TASK_SET_STATE R10, TASK_READY
0x0000A9C4   LI R1 TASK_READY
0x0000A9CC   STW R1 [R10 + TASK_STATE]

0x0000A9D0       MOV R1 R10          ; return child task pointer

0x0000A9D4       POP LR
0x0000A9D8       RET

clone_fail:
0x0000A9DC       CMP R10 0
0x0000A9E0       BEQ clone_fail_return
0x0000A9E8       MOV R1 R10
0x0000A9EC       BL task_destroy
clone_fail_return:
0x0000A9F4       LI R1 0
0x0000A9FC       POP LR
0x0000AA00       RET

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

0x0000AA04       PUSH LR
0x0000AA08       push R12 ; preserve R12 which we use for temporary storage in this function
0x0000AA0C       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x0000AA10   LDW R2 [R1 + TASK_PTBR]
0x0000AA14       CMP R2 0
0x0000AA18       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x0000AA20       MOV R1 R2
0x0000AA24       BL page_put        ; put-free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x0000AA2C   LDW R2 [R12 + TASK_USTACK_PAGE]
0x0000AA30       CMP R2 0
0x0000AA34       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000AA3C       MOV R1 R2
0x0000AA40       BL page_put        ; put-free user stack page

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x0000AA48   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x0000AA4C       CMP R2 0
0x0000AA50       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000AA58       MOV R1 R2
0x0000AA5C       BL page_put        ; put-free kernel stack page

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x0000AA64   LDW R2 [R12 + TASK_FD_TABLE]
0x0000AA68       CMP R2 0
0x0000AA6C       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000AA74       MOV R1 R2
0x0000AA78       BL page_put        ; put-free fd table page

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x0000AA80   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x0000AA84       CMP R2 0
0x0000AA88       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x0000AA90       MOV R1 R2
0x0000AA94       BL page_put       ; put free KBUF_WR Page

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x0000AA9C   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x0000AAA0       CMP R2 0
0x0000AAA4       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x0000AAAC       MOV R1 R2
0x0000AAB0       BL page_put       ; put free KBUF_RD Page

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x0000AAB8   LDW R2 [R12 + TASK_DATA_PAGE]
0x0000AABC       CMP R2 0
0x0000AAC0       BEQ td_skip_code
0x0000AAC8       MOV R1 R2
0x0000AACC       BL page_put        ; put-free user data page

td_skip_code:

; macro: TASK_GET_CODE_PAGE R2, R12
0x0000AAD4   LDW R2 [R12 + TASK_CODE_PAGE]
0x0000AAD8       CMP R2 0
0x0000AADC       BEQ td_done
0x0000AAE4       MOV R1 R2
0x0000AAE8       BL page_put        ; put-free user code page

td_done:

0x0000AAF0       MOV R1 R12
0x0000AAF4       LI  R3 TASK_SIZE
0x0000AAFC       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x0000AB04       POP R12         ; restore R12
0x0000AB08       POP LR
0x0000AB0C       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x0000AB10       PUSH LR
0x0000AB14       PUSH R8
0x0000AB18       PUSH R9
0x0000AB1C       PUSH R10
0x0000AB20       PUSH R11
0x0000AB24       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x0000AB28   LDW R4 [R1 + TASK_FD_TABLE]
0x0000AB2C       MOV R12 R4

0x0000AB30       LI R5 3              ; skip stdin/out/err
0x0000AB38       MOV R11 R5

fd_loop:

0x0000AB3C       CMP R11 MAX_FDS
0x0000AB40       BGE fd_done         ; if we processed all fd slots, we are done

0x0000AB48       SHL R6 R11 2
0x0000AB4C       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x0000AB50       LDW R8 [R10]
0x0000AB54       CMP R8 0
0x0000AB58       BEQ fd_next         ; if fd slot is empty, skip to next

0x0000AB60       MOV R1 R8
0x0000AB64       BL file_free
0x0000AB6C       LI R9 0
0x0000AB74       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x0000AB78       ADD R11 R11 1
0x0000AB7C       B fd_loop

fd_done:
0x0000AB84       POP R12
0x0000AB88       POP R11
0x0000AB8C       POP R10
0x0000AB90       POP R9
0x0000AB94       POP R8
0x0000AB98       POP LR
0x0000AB9C       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x0000ABA0       PUSH LR
0x0000ABA4       PUSH R8
0x0000ABA8       PUSH R9
0x0000ABAC       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x0000ABB0   LI R1 CURRENT_TASK
0x0000ABB8   LDW R10 [R1]
0x0000ABBC       LI R8 0

task_reap_loop:
0x0000ABC4       CMP R8 MAX_TASKS
0x0000ABC8       BGE task_reap_done

0x0000ABD0       CMP R8 R10
0x0000ABD4       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x0000ABDC   LI R1 TASK_SIZE
0x0000ABE4   MUL R3 R8 R1
0x0000ABE8   LI R9 tasks
0x0000ABF0   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x0000ABF4   LDW R1 [R9 + TASK_STATE]
0x0000ABF8       CMP R1 TASK_ZOMBIE
0x0000ABFC       BNE task_reap_next

0x0000AC04       PUSH R8
0x0000AC08       MOV R1 R9
0x0000AC0C       BL task_destroy
0x0000AC14       POP R8

task_reap_next:
0x0000AC18       ADD R8 R8 1
0x0000AC1C       B task_reap_loop

task_reap_done:
0x0000AC24       POP R10
0x0000AC28       POP R9
0x0000AC2C       POP R8
0x0000AC30       POP LR
0x0000AC34       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x0000AC38       LI R1 tasks
0x0000AC40       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x0000AC48   LDW R3 [R1 + TASK_STATE]

0x0000AC4C       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000AC50       BEQ task_alloc_found

0x0000AC58       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x0000AC5C       SUB R2 R2 1
0x0000AC60       BNE task_alloc_loop

; no free tasks slots

0x0000AC68       LI R1 0
0x0000AC70       RET

task_alloc_found:                           ;R1 points to free task slot

0x0000AC74       RET


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
0x0000AC80       PUSH R2

0x0000AC84       LI R2 0
0x0000AC8C       STW R2 [R1 + MUTEX_OWNER]      ; owner = NULL
0x0000AC90       STW R2 [R1 + MUTEX_WAITQ]      ; waitq = 0 (empty)

0x0000AC94       POP R2
0x0000AC98       RET

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

0x0000AC9C       PUSH LR
0x0000ACA0       PUSH R8
0x0000ACA4       PUSH R9
0x0000ACA8       PUSH R10

0x0000ACAC       MOV R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000ACB0   LI R1 CURRENT_TASK
0x0000ACB8   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000ACBC   LI R1 TASK_SIZE
0x0000ACC4   MUL R3 R9 R1
0x0000ACC8   LI R9 tasks
0x0000ACD0   ADD R9 R9 R3

mutex_lock_retry:
    ; Check if mutex is already locked
0x0000ACD4       LDW R10 [R8 + MUTEX_OWNER]
0x0000ACD8       CMP R10 0
0x0000ACDC       BEQ mutex_lock_acquire      ; if unlocked, acquire it

    ; this Mutex is locked by someone else - block
    ; Add current task to mutex wait queue
0x0000ACE4       MOV R1 R8
0x0000ACE8       ADD R1 R1 MUTEX_WAITQ

0x0000ACEC       LI R2 WAIT_MUTEX
0x0000ACF4       LI R3 TASK_WAIT_MUTEX
0x0000ACFC       BL waitq_prepare_sleep

    ; Re-check if mutex became available while preparing sleep
0x0000AD04       LDW R10 [R8 + MUTEX_OWNER]
0x0000AD08       CMP R10 0
0x0000AD0C       BEQ mutex_lock_wake

    ; Still locked - go to sleep
0x0000AD14       BL waitq_sleep_current

    ; Woken up - try to acquire again
0x0000AD1C       B mutex_lock_retry

mutex_lock_wake:
    ; Mutex became available, cancel sleep and acquire
0x0000AD24       MOV R1 R8
0x0000AD28       ADD R1 R1 MUTEX_WAITQ
0x0000AD2C       BL waitq_cancel_sleep_current

0x0000AD34       B mutex_lock_retry

mutex_lock_acquire:
    ; Disable interrupts to prevent race conditions
0x0000AD3C       DISABLEINT

    ; Double-check it's still unlocked
0x0000AD40       LDW R10 [R8 + MUTEX_OWNER]
0x0000AD44       CMP R10 0
0x0000AD48       BNE mutex_lock_race

    ; Set owner to current task
0x0000AD50       STW R9 [R8 + MUTEX_OWNER]

    ; Re-enable interrupts
0x0000AD54       ENABLEINT

0x0000AD58       POP R10
0x0000AD5C       POP R9
0x0000AD60       POP R8
0x0000AD64       POP LR
0x0000AD68       RET

mutex_lock_race:
    ; Someone else acquired it while interrupts were disabled
0x0000AD6C       ENABLEINT
0x0000AD70       B mutex_lock_retry


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
0x0000AD78       PUSH LR
0x0000AD7C       PUSH R8
0x0000AD80       PUSH R9
0x0000AD84       PUSH R10

0x0000AD88       MOV  R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000AD8C   LI R1 CURRENT_TASK
0x0000AD94   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000AD98   LI R1 TASK_SIZE
0x0000ADA0   MUL R3 R9 R1
0x0000ADA4   LI R9 tasks
0x0000ADAC   ADD R9 R9 R3

    ; Verify ownership
0x0000ADB0       LDW  R10 [R8 + MUTEX_OWNER]
0x0000ADB4       CMP  R10 R9
0x0000ADB8       BNE  mutex_unlock_error     ; Not owner - error!

    ; Release the mutex
0x0000ADC0       LI  R10 0
0x0000ADC8       STW R10 [R8 + MUTEX_OWNER]

    ; Wake one waiting task (if someone is waiting)
    ; waky next one (of any waiting)
0x0000ADCC       MOV R1 R8
0x0000ADD0       ADD R1 R1 MUTEX_WAITQ
0x0000ADD4       BL waitq_wake_one

mutex_unlock_done:
0x0000ADDC       POP R10
0x0000ADE0       POP R9
0x0000ADE4       POP R8
0x0000ADE8       POP LR
0x0000ADEC       RET

mutex_unlock_error:
    ; Not owner - ignore (or panic)
0x0000ADF0       POP R10
0x0000ADF4       POP R9
0x0000ADF8       POP R8
0x0000ADFC       POP LR
0x0000AE00       RET

; ================================================================
; waitq_wake_one - Wake exactly one task from the wait queue
; R1 = wait queue pointer
; ================================================================
waitq_wake_one:
0x0000AE04       PUSH LR
0x0000AE08       PUSH R8
0x0000AE0C       PUSH R9
0x0000AE10       PUSH R10
0x0000AE14       PUSH R11

0x0000AE18       MOV R8 R1                  ; wait queue pointer
0x0000AE1C       LDW R9 [R8 + WQ_MASK]      ; current wait queue mask

0x0000AE20       CMP R9 0
0x0000AE24       BEQ waitq_wake_one_done    ; No waiters

    ; Find the first waiting task
0x0000AE2C       LI R10 0                   ; task index

waitq_wake_one_find:
0x0000AE34       CMP R10 MAX_TASKS
0x0000AE38       BGE waitq_wake_one_done

0x0000AE40       LI R11 1
0x0000AE48       SHL R11 R11 R10            ; bit for this task
0x0000AE4C       AND R2 R9 R11
0x0000AE50       CMP R2 0
0x0000AE54       BNE waitq_wake_one_found

0x0000AE5C       ADD R10 R10 1
0x0000AE60       B waitq_wake_one_find

waitq_wake_one_found:
    ; Clear this task's bit from the wait queue
0x0000AE68       NOT R11 R11
0x0000AE6C       AND R9 R9 R11
0x0000AE70       STW R9 [R8 + WQ_MASK]

    ; Wake this task
; macro: GET_TASK_PTR R5, R10
0x0000AE74   LI R1 TASK_SIZE
0x0000AE7C   MUL R3 R10 R1
0x0000AE80   LI R5 tasks
0x0000AE88   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000AE8C   LI R1 TASK_READY
0x0000AE94   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000AE98   LI R1 WAIT_NONE
0x0000AEA0   STW R1 [R5 + TASK_WAIT]

waitq_wake_one_done:
0x0000AEA4       POP R11
0x0000AEA8       POP R10
0x0000AEAC       POP R9
0x0000AEB0       POP R8
0x0000AEB4       POP LR
0x0000AEB8       RET

; ================================================================
; CONSOLE MUTEX WRAPPER FUNCTIONS
; ================================================================

console_lock:
0x0000AEBC       PUSH LR
0x0000AEC0       LI R1 console_mutex
0x0000AEC8       BL mutex_lock
0x0000AED0       POP LR
0x0000AED4       RET

console_unlock:
0x0000AED8       PUSH LR
0x0000AEDC       LI R1 console_mutex
0x0000AEE4       BL mutex_unlock
0x0000AEEC       POP LR
0x0000AEF0       RET

;------------------------------------------------------
; bmi_call
;
; R1 = opcode
; R2 = payload pointer
; R3 = payload length
; R4 = namespace
;
; Returns:
;   R1 = BMI reply code
;------------------------------------------------------

bmi_call:
0x0000AEF4       PUSH LR
0x0000AEF8       PUSH R6
0x0000AEFC       PUSH R7
0x0000AF00       PUSH R8
0x0000AF04       PUSH R9

    ;------------------------------------
    ; Fill BMI packet
    ;------------------------------------
0x0000AF08       LI  R6 BMI_BUF_WRITE

0x0000AF10       STH R1 [R6 + BMI_HDR_OPCODE]

0x0000AF14       LI  R7 0
0x0000AF1C       STH R7 [R6 + BMI_HDR_FLAGS]

0x0000AF20       STW R4 [R6 + BMI_HDR_NAMESPACE]
0x0000AF24       STW R3 [R6 + BMI_HDR_PAYLOAD_LEN]

    ; Copy payload

0x0000AF28       ADD R7 R6 BMI_HDR_SIZEOF

0x0000AF2C       MOV R1 R7          ; dst
0x0000AF30       MOV R2 R2          ; src
0x0000AF34       MOV R3 R3          ; len

0x0000AF38       BL memcpy

    ;------------------------------------
    ; Ring doorbell
    ;------------------------------------

0x0000AF40       LI  R6 BMI_REG_BASE

0x0000AF48       LI  R7 BMI_READY
0x0000AF50       STW R7 [R6 + BMI_STATUS]

0x0000AF54       LI  R7 1
0x0000AF5C       STW R7 [R6 + BMI_DOORBELL]

wait_reply:

0x0000AF60       LDW R7 [R6 + BMI_STATUS]

    ;DEBUG 2

0x0000AF64       CMP R7 BMI_DONE
0x0000AF68       BEQ bmi_call_done

0x0000AF70       CMP R7 BMI_ERROR
0x0000AF74       BEQ bmi_call_error

0x0000AF7C       B wait_reply

bmi_call_done:

    ;----------------------------------------
    ; Read BMI reply packet
    ;----------------------------------------

0x0000AF84       LI  R8 BMI_BUF_READ

0x0000AF8C       LDH R1 [R8 + BMI_HDR_OPCODE]
0x0000AF90       LDH R2 [R8 + BMI_HDR_FLAGS]
0x0000AF94       LDW R3 [R8 + BMI_HDR_NAMESPACE]
0x0000AF98       LDW R4 [R8 + BMI_HDR_PAYLOAD_LEN]

    ; R8 + BMI_HDR_SIZEOF points to reply payload


0x0000AF9C       LDW R1 [R6 + BMI_REPLY]

    ; reset state

0x0000AFA0       LI R7 BMI_IDLE
0x0000AFA8       STW R7 [R6 + BMI_STATUS]

0x0000AFAC       POP R9
0x0000AFB0       POP R8
0x0000AFB4       POP R7
0x0000AFB8       POP R6
0x0000AFBC       POP LR
0x0000AFC0       RET

bmi_call_error:
0x0000AFC4       LI R1 -1
0x0000AFCC       LI R7 BMI_IDLE
0x0000AFD4       STW R7 [R6 + BMI_STATUS]

0x0000AFD8       POP R9
0x0000AFDC       POP R8
0x0000AFE0       POP R7
0x0000AFE4       POP R6
0x0000AFE8       POP LR

0x0000AFEC       RET



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

; ==================================================
; BMI module
; ==================================================

.EQU BMI_HDR_OPCODE, 0
.EQU BMI_HDR_FLAGS,  2
.EQU BMI_HDR_NAMESPACE, 4
.EQU BMI_HDR_PAYLOAD_LEN, 8
.EQU BMI_HDR_SIZEOF, 12
.EQU BMI_PAYLOAD, 12

; ==================================================
; BMI OPCODES for NSFS
; ==================================================

.EQU NS_CREATE,   0x01
.EQU NS_DELETE,   0x02
.EQU FILE_CREATE, 0x10
.EQU FILE_DELETE, 0x11
.EQU DIR_CREATE,  0x20
.EQU DIR_DELETE,  0x21


; ==================================================
; BMI buffers for NSFS should be alligned to 4K page boundaries and be at least 4K in size
; ==================================================
.ORG 0x15000
BMI_BUF_WRITE:
    .SPACE 4096
.ORG 0x16000
BMI_BUF_READ:
    .SPACE 4096
.ORG 0x17000
BMI_REG_BASE:
    .SPACE 4096

.EQU BMI_STATUS,    0
.EQU BMI_DOORBELL,  4
.EQU BMI_REPLY,     8

.EQU BMI_IDLE,      0
.EQU BMI_READY,     1
.EQU BMI_BUSY,      2
.EQU BMI_DONE,      3
.EQU BMI_ERROR,     4




; ================================================================
; USER SPACE !!!! mode TASKS
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

;==========
ls1_path:
    .ASCIIZ "bin/ls1"

ls1_arg0:
    .ASCIIZ "ls1"

ls1_arg1:
    .ASCIIZ "etc/"

ls1_arg2:
    .ASCIIZ "lib/"

ls1_argv:
    .WORD ls1_path
    .WORD ls1_arg1
    .WORD ls1_arg2
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

; bin/cat, 4427 bytes
    .ASCIIZ "bin/cat"
    .SPACE 116
    .ASCIIZ "00000010513"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4427 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x00043F92, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043F90, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
    .WORD 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x00043104, 0x02090981, 0x05000000
    .WORD 0x000430E8, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000
    .WORD 0x00043170, 0x040A0080, 0x06000000, 0x00043160, 0x02080881, 0x02090981, 0x05000000, 0x00043130
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043178, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431D0, 0x20010900, 0x23010800, 0x02080881
    .WORD 0x02090981, 0x030A0A81, 0x05000000, 0x000431A8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200
    .WORD 0x018A0300, 0x040A0080, 0x06000000, 0x00043224, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000
    .WORD 0x00043204, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000
    .WORD 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000
    .WORD 0x05000000, 0x00043280, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043550, 0x0F020000, 0x00043288, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x0004352C, 0x22030204
    .WORD 0x04030500, 0x15000000, 0x00043538, 0x02040481, 0x05000000, 0x000434E8, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x22010200, 0x05000000, 0x000435D0, 0x01810500, 0x400C0000, 0x04010080, 0x12000000
    .WORD 0x000435C8, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435C8, 0x0F020000, 0x00043288
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435AC
    .WORD 0x02040481, 0x05000000, 0x0004356C, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208
    .WORD 0x05000000, 0x000435D0, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080
    .WORD 0x06000000, 0x0004363C, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x0004363C, 0x0F020000
    .WORD 0x00043288, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000
    .WORD 0x00043630, 0x02040481, 0x05000000, 0x000435F0, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F010000, 0x00043288, 0x0F030000, 0x00000030, 0x04030080, 0x06000000
    .WORD 0x00043680, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043658
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000
    .WORD 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000
    .WORD 0x01870600, 0x040C0081, 0x07000000, 0x000436F4, 0x04090080, 0x15000000, 0x000436F4, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043724
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437C4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043750, 0x020707B0, 0x05000000, 0x00043770, 0x04070089, 0x14000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043770, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500
    .WORD 0x04090080, 0x07000000, 0x0004372C, 0x03060681, 0x04040080, 0x06000000, 0x000437B8, 0x20020600
    .WORD 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043790, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x00000022, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200
    .WORD 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043924, 0x02010181, 0x02040481, 0x05000000
    .WORD 0x00043900, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439BC
    .WORD 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000
    .WORD 0x000439A4, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000
    .WORD 0x000439C4, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439C4, 0x0F010000
    .WORD 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A3C, 0x22010800, 0x01820900, 0x0F030000
    .WORD 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A4C, 0x040100CC, 0x07000000, 0x00043A3C
    .WORD 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A54, 0x0F010000
    .WORD 0xFFFFFFFF, 0x05000000, 0x00043A54, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AA0, 0x22010800
    .WORD 0x40070000, 0x01810800, 0x30000000, 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043AA8
    .WORD 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AE0
    .WORD 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x04010080, 0x06000000, 0x00043AF8, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043B38, 0x01820100
    .WORD 0x0F010000, 0x00000001, 0x30000000, 0x00043A64, 0x05000000, 0x00043B40, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00
    .WORD 0x01810800, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043C0C, 0x01880100, 0x01810800
    .WORD 0x01820900, 0x30000000, 0x000439D4, 0x04010080, 0x06000000, 0x00043BF0, 0x0F020000, 0xFFFFFFFF
    .WORD 0x04010200, 0x06000000, 0x00043C0C, 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082
    .WORD 0x07000000, 0x00043BD8, 0x0F010000, 0x00043C28, 0x30000000, 0x00043098, 0x0F010000, 0x00043C2C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043B7C, 0x01810800, 0x30000000, 0x00043A64, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043C14, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x100B0000, 0x100C0000, 0x030D0DD0, 0x01880100, 0x0F090000, 0x00000000, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043EA8, 0x040100A5
    .WORD 0x07000000, 0x00043D40, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043EA8, 0x040200A5
    .WORD 0x06000000, 0x00043D50, 0x040200F3, 0x06000000, 0x00043DE4, 0x040200E4, 0x06000000, 0x00043E00
    .WORD 0x040200E9, 0x06000000, 0x00043E00, 0x040200F8, 0x06000000, 0x00043E20, 0x040200E3, 0x06000000
    .WORD 0x00043E40, 0x040200E2, 0x06000000, 0x00043E5C, 0x040200EF, 0x06000000, 0x00043E7C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x05000000, 0x00043E9C, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22010300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22020300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DD0, 0x0303098B, 0x0F040000, 0x00000004
    .WORD 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03
    .WORD 0x31000000, 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043EC8, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F0C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F2C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F4C, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F6C, 0x05000000, 0x00043E9C, 0x02080881
    .WORD 0x05000000, 0x00043C8C, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0
    .WORD 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x000437EC, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043818, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043870, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043844, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001006, 0x00001007
    .WORD 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000, 0x0D00030D
    .WORD 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x41021200, 0x00000004, 0x00010F0A, 0x00000000
    .WORD 0x00000F06, 0x08000000, 0x0000040A, 0x40CE1500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x00000F02, 0x00000000, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x40821200
    .WORD 0x0B000004, 0x0C000181, 0x00000182, 0x01000F03, 0x00000000, 0x32443000, 0x01000004, 0x00800187
    .WORD 0x00000407, 0x406A1300, 0x00000004, 0x00010F01, 0x0C000000, 0x07000182, 0x00000183, 0x323C3000
    .WORD 0x00000004, 0x40220500, 0x0B000004, 0x00000181, 0x32543000, 0x0A810004, 0x0000020A, 0x3FE60500
    .WORD 0x00000004, 0x41370F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06
    .WORD 0x0A810000, 0x0000020A, 0x3FE60500, 0x00000004, 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181
    .WORD 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F
    .WORD 0x00003100, 0x41220F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x00000000, 0x40CE0500
    .WORD 0x73750004, 0x3A656761, 0x74616320, 0x6C696620, 0x2E2E2065, 0x63000A2E, 0x203A7461, 0x6E6E6163
    .WORD 0x6F20746F, 0x206E6570, 0x00000A00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/echo, 4142 bytes
    .ASCIIZ "bin/echo"
    .SPACE 115
    .ASCIIZ "00000010056"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4142 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x00043F92, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043F90, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
    .WORD 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x00043104, 0x02090981, 0x05000000
    .WORD 0x000430E8, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000
    .WORD 0x00043170, 0x040A0080, 0x06000000, 0x00043160, 0x02080881, 0x02090981, 0x05000000, 0x00043130
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043178, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431D0, 0x20010900, 0x23010800, 0x02080881
    .WORD 0x02090981, 0x030A0A81, 0x05000000, 0x000431A8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200
    .WORD 0x018A0300, 0x040A0080, 0x06000000, 0x00043224, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000
    .WORD 0x00043204, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000
    .WORD 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000
    .WORD 0x05000000, 0x00043280, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043550, 0x0F020000, 0x00043288, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x0004352C, 0x22030204
    .WORD 0x04030500, 0x15000000, 0x00043538, 0x02040481, 0x05000000, 0x000434E8, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x22010200, 0x05000000, 0x000435D0, 0x01810500, 0x400C0000, 0x04010080, 0x12000000
    .WORD 0x000435C8, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435C8, 0x0F020000, 0x00043288
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435AC
    .WORD 0x02040481, 0x05000000, 0x0004356C, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208
    .WORD 0x05000000, 0x000435D0, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080
    .WORD 0x06000000, 0x0004363C, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x0004363C, 0x0F020000
    .WORD 0x00043288, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000
    .WORD 0x00043630, 0x02040481, 0x05000000, 0x000435F0, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F010000, 0x00043288, 0x0F030000, 0x00000030, 0x04030080, 0x06000000
    .WORD 0x00043680, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043658
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000
    .WORD 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000
    .WORD 0x01870600, 0x040C0081, 0x07000000, 0x000436F4, 0x04090080, 0x15000000, 0x000436F4, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043724
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437C4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043750, 0x020707B0, 0x05000000, 0x00043770, 0x04070089, 0x14000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043770, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500
    .WORD 0x04090080, 0x07000000, 0x0004372C, 0x03060681, 0x04040080, 0x06000000, 0x000437B8, 0x20020600
    .WORD 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043790, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x00000022, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200
    .WORD 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043924, 0x02010181, 0x02040481, 0x05000000
    .WORD 0x00043900, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439BC
    .WORD 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000
    .WORD 0x000439A4, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000
    .WORD 0x000439C4, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439C4, 0x0F010000
    .WORD 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A3C, 0x22010800, 0x01820900, 0x0F030000
    .WORD 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A4C, 0x040100CC, 0x07000000, 0x00043A3C
    .WORD 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A54, 0x0F010000
    .WORD 0xFFFFFFFF, 0x05000000, 0x00043A54, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AA0, 0x22010800
    .WORD 0x40070000, 0x01810800, 0x30000000, 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043AA8
    .WORD 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AE0
    .WORD 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x04010080, 0x06000000, 0x00043AF8, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043B38, 0x01820100
    .WORD 0x0F010000, 0x00000001, 0x30000000, 0x00043A64, 0x05000000, 0x00043B40, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00
    .WORD 0x01810800, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043C0C, 0x01880100, 0x01810800
    .WORD 0x01820900, 0x30000000, 0x000439D4, 0x04010080, 0x06000000, 0x00043BF0, 0x0F020000, 0xFFFFFFFF
    .WORD 0x04010200, 0x06000000, 0x00043C0C, 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082
    .WORD 0x07000000, 0x00043BD8, 0x0F010000, 0x00043C28, 0x30000000, 0x00043098, 0x0F010000, 0x00043C2C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043B7C, 0x01810800, 0x30000000, 0x00043A64, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043C14, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x100B0000, 0x100C0000, 0x030D0DD0, 0x01880100, 0x0F090000, 0x00000000, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043EA8, 0x040100A5
    .WORD 0x07000000, 0x00043D40, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043EA8, 0x040200A5
    .WORD 0x06000000, 0x00043D50, 0x040200F3, 0x06000000, 0x00043DE4, 0x040200E4, 0x06000000, 0x00043E00
    .WORD 0x040200E9, 0x06000000, 0x00043E00, 0x040200F8, 0x06000000, 0x00043E20, 0x040200E3, 0x06000000
    .WORD 0x00043E40, 0x040200E2, 0x06000000, 0x00043E5C, 0x040200EF, 0x06000000, 0x00043E7C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x05000000, 0x00043E9C, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22010300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22020300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DD0, 0x0303098B, 0x0F040000, 0x00000004
    .WORD 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03
    .WORD 0x31000000, 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043EC8, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F0C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F2C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F4C, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F6C, 0x05000000, 0x00043E9C, 0x02080881
    .WORD 0x05000000, 0x00043C8C, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0
    .WORD 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x000437EC, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043818, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043870, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043844, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x00000000, 0x0000100F, 0x00001008
    .WORD 0x00001009, 0x0100100A, 0x02000188, 0x00000189, 0x00010F0A, 0x09000000, 0x0B84018B, 0x0800020B
    .WORD 0x0000040A, 0x40121500, 0x0B000004, 0x00002201, 0x30583000, 0x0A810004, 0x0B84020A, 0x0800020B
    .WORD 0x0000040A, 0x40021500, 0x00000004, 0x3F8C0F01, 0x00000004, 0x30583000, 0x00000004, 0x3FBE0500
    .WORD 0x00000004, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004, 0x00000F01, 0x00000000, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; bin/ls, 4595 bytes
    .ASCIIZ "bin/ls"
    .SPACE 117
    .ASCIIZ "00000010763"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4595 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x00043F92, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043F90, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
    .WORD 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x00043104, 0x02090981, 0x05000000
    .WORD 0x000430E8, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000
    .WORD 0x00043170, 0x040A0080, 0x06000000, 0x00043160, 0x02080881, 0x02090981, 0x05000000, 0x00043130
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043178, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431D0, 0x20010900, 0x23010800, 0x02080881
    .WORD 0x02090981, 0x030A0A81, 0x05000000, 0x000431A8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200
    .WORD 0x018A0300, 0x040A0080, 0x06000000, 0x00043224, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000
    .WORD 0x00043204, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000
    .WORD 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000
    .WORD 0x05000000, 0x00043280, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043550, 0x0F020000, 0x00043288, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x0004352C, 0x22030204
    .WORD 0x04030500, 0x15000000, 0x00043538, 0x02040481, 0x05000000, 0x000434E8, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x22010200, 0x05000000, 0x000435D0, 0x01810500, 0x400C0000, 0x04010080, 0x12000000
    .WORD 0x000435C8, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435C8, 0x0F020000, 0x00043288
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435AC
    .WORD 0x02040481, 0x05000000, 0x0004356C, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208
    .WORD 0x05000000, 0x000435D0, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080
    .WORD 0x06000000, 0x0004363C, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x0004363C, 0x0F020000
    .WORD 0x00043288, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000
    .WORD 0x00043630, 0x02040481, 0x05000000, 0x000435F0, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F010000, 0x00043288, 0x0F030000, 0x00000030, 0x04030080, 0x06000000
    .WORD 0x00043680, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043658
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000
    .WORD 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000
    .WORD 0x01870600, 0x040C0081, 0x07000000, 0x000436F4, 0x04090080, 0x15000000, 0x000436F4, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043724
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437C4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043750, 0x020707B0, 0x05000000, 0x00043770, 0x04070089, 0x14000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043770, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500
    .WORD 0x04090080, 0x07000000, 0x0004372C, 0x03060681, 0x04040080, 0x06000000, 0x000437B8, 0x20020600
    .WORD 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043790, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x00000022, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200
    .WORD 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043924, 0x02010181, 0x02040481, 0x05000000
    .WORD 0x00043900, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439BC
    .WORD 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000
    .WORD 0x000439A4, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000
    .WORD 0x000439C4, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439C4, 0x0F010000
    .WORD 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A3C, 0x22010800, 0x01820900, 0x0F030000
    .WORD 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A4C, 0x040100CC, 0x07000000, 0x00043A3C
    .WORD 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A54, 0x0F010000
    .WORD 0xFFFFFFFF, 0x05000000, 0x00043A54, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AA0, 0x22010800
    .WORD 0x40070000, 0x01810800, 0x30000000, 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043AA8
    .WORD 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AE0
    .WORD 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x04010080, 0x06000000, 0x00043AF8, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043B38, 0x01820100
    .WORD 0x0F010000, 0x00000001, 0x30000000, 0x00043A64, 0x05000000, 0x00043B40, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00
    .WORD 0x01810800, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043C0C, 0x01880100, 0x01810800
    .WORD 0x01820900, 0x30000000, 0x000439D4, 0x04010080, 0x06000000, 0x00043BF0, 0x0F020000, 0xFFFFFFFF
    .WORD 0x04010200, 0x06000000, 0x00043C0C, 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082
    .WORD 0x07000000, 0x00043BD8, 0x0F010000, 0x00043C28, 0x30000000, 0x00043098, 0x0F010000, 0x00043C2C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043B7C, 0x01810800, 0x30000000, 0x00043A64, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043C14, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x100B0000, 0x100C0000, 0x030D0DD0, 0x01880100, 0x0F090000, 0x00000000, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043EA8, 0x040100A5
    .WORD 0x07000000, 0x00043D40, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043EA8, 0x040200A5
    .WORD 0x06000000, 0x00043D50, 0x040200F3, 0x06000000, 0x00043DE4, 0x040200E4, 0x06000000, 0x00043E00
    .WORD 0x040200E9, 0x06000000, 0x00043E00, 0x040200F8, 0x06000000, 0x00043E20, 0x040200E3, 0x06000000
    .WORD 0x00043E40, 0x040200E2, 0x06000000, 0x00043E5C, 0x040200EF, 0x06000000, 0x00043E7C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x05000000, 0x00043E9C, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22010300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22020300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DD0, 0x0303098B, 0x0F040000, 0x00000004
    .WORD 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03
    .WORD 0x31000000, 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043EC8, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F0C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F2C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F4C, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F6C, 0x05000000, 0x00043E9C, 0x02080881
    .WORD 0x05000000, 0x00043C8C, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0
    .WORD 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x000437EC, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043818, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043870, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043844, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001006, 0x00001007
    .WORD 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000, 0x0D00030D
    .WORD 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x41921200, 0x00000004, 0x00010F0A, 0x00000000
    .WORD 0x00000F06, 0x08000000, 0x0000040A, 0x415E1500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x00001001, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004, 0x41DC0F01, 0x00000004
    .WORD 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004
    .WORD 0x41EC0F01, 0x00000004, 0x30583000, 0x00000004, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00001101, 0x00000F02, 0x00000000, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x41121200
    .WORD 0x0B000004, 0x0C000181, 0x00000182, 0x004C0F03, 0x00000000, 0x32443000, 0x01000004, 0x00800187
    .WORD 0x00000407, 0x40FA0600, 0x00CC0004, 0x00000407, 0x40FA0700, 0x0C080004, 0x0C8C2005, 0x00000201
    .WORD 0x30583000, 0x00820004, 0x00000405, 0x40E20700, 0x00000004, 0x41F10F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004, 0x40820500, 0x0B000004, 0x00000181
    .WORD 0x32543000, 0x0A810004, 0x0000020A, 0x3FE60500, 0x00000004, 0x41CB0F01, 0x00000004, 0x30583000
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x3F8E0F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x3FE60500, 0x00000004
    .WORD 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x41B20F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00010F06, 0x00000000, 0x415E0500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964
    .WORD 0x726F7463, 0x2E2E2079, 0x6C000A2E, 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D
    .WORD 0x65726944, 0x726F7463, 0x00203A79, 0x2D2D2D20, 0x00002F00, 0x00000000, 0x00000000, 0x00000000

; bin/ls1, 4585 bytes
    .ASCIIZ "bin/ls1"
    .SPACE 116
    .ASCIIZ "00000010751"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4585 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x00043F92, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043F90, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
    .WORD 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x00043104, 0x02090981, 0x05000000
    .WORD 0x000430E8, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000
    .WORD 0x00043170, 0x040A0080, 0x06000000, 0x00043160, 0x02080881, 0x02090981, 0x05000000, 0x00043130
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043178, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431D0, 0x20010900, 0x23010800, 0x02080881
    .WORD 0x02090981, 0x030A0A81, 0x05000000, 0x000431A8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200
    .WORD 0x018A0300, 0x040A0080, 0x06000000, 0x00043224, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000
    .WORD 0x00043204, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000
    .WORD 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000
    .WORD 0x05000000, 0x00043280, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043550, 0x0F020000, 0x00043288, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x0004352C, 0x22030204
    .WORD 0x04030500, 0x15000000, 0x00043538, 0x02040481, 0x05000000, 0x000434E8, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x22010200, 0x05000000, 0x000435D0, 0x01810500, 0x400C0000, 0x04010080, 0x12000000
    .WORD 0x000435C8, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435C8, 0x0F020000, 0x00043288
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435AC
    .WORD 0x02040481, 0x05000000, 0x0004356C, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208
    .WORD 0x05000000, 0x000435D0, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080
    .WORD 0x06000000, 0x0004363C, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x0004363C, 0x0F020000
    .WORD 0x00043288, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000
    .WORD 0x00043630, 0x02040481, 0x05000000, 0x000435F0, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F010000, 0x00043288, 0x0F030000, 0x00000030, 0x04030080, 0x06000000
    .WORD 0x00043680, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043658
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000
    .WORD 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000
    .WORD 0x01870600, 0x040C0081, 0x07000000, 0x000436F4, 0x04090080, 0x15000000, 0x000436F4, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043724
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437C4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043750, 0x020707B0, 0x05000000, 0x00043770, 0x04070089, 0x14000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043770, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500
    .WORD 0x04090080, 0x07000000, 0x0004372C, 0x03060681, 0x04040080, 0x06000000, 0x000437B8, 0x20020600
    .WORD 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043790, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x00000022, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200
    .WORD 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043924, 0x02010181, 0x02040481, 0x05000000
    .WORD 0x00043900, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439BC
    .WORD 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000
    .WORD 0x000439A4, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000
    .WORD 0x000439C4, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439C4, 0x0F010000
    .WORD 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A3C, 0x22010800, 0x01820900, 0x0F030000
    .WORD 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A4C, 0x040100CC, 0x07000000, 0x00043A3C
    .WORD 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A54, 0x0F010000
    .WORD 0xFFFFFFFF, 0x05000000, 0x00043A54, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AA0, 0x22010800
    .WORD 0x40070000, 0x01810800, 0x30000000, 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043AA8
    .WORD 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AE0
    .WORD 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x04010080, 0x06000000, 0x00043AF8, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043B38, 0x01820100
    .WORD 0x0F010000, 0x00000001, 0x30000000, 0x00043A64, 0x05000000, 0x00043B40, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00
    .WORD 0x01810800, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043C0C, 0x01880100, 0x01810800
    .WORD 0x01820900, 0x30000000, 0x000439D4, 0x04010080, 0x06000000, 0x00043BF0, 0x0F020000, 0xFFFFFFFF
    .WORD 0x04010200, 0x06000000, 0x00043C0C, 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082
    .WORD 0x07000000, 0x00043BD8, 0x0F010000, 0x00043C28, 0x30000000, 0x00043098, 0x0F010000, 0x00043C2C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043B7C, 0x01810800, 0x30000000, 0x00043A64, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043C14, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x100B0000, 0x100C0000, 0x030D0DD0, 0x01880100, 0x0F090000, 0x00000000, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043EA8, 0x040100A5
    .WORD 0x07000000, 0x00043D40, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043EA8, 0x040200A5
    .WORD 0x06000000, 0x00043D50, 0x040200F3, 0x06000000, 0x00043DE4, 0x040200E4, 0x06000000, 0x00043E00
    .WORD 0x040200E9, 0x06000000, 0x00043E00, 0x040200F8, 0x06000000, 0x00043E20, 0x040200E3, 0x06000000
    .WORD 0x00043E40, 0x040200E2, 0x06000000, 0x00043E5C, 0x040200EF, 0x06000000, 0x00043E7C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x05000000, 0x00043E9C, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22010300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22020300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DD0, 0x0303098B, 0x0F040000, 0x00000004
    .WORD 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03
    .WORD 0x31000000, 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043EC8, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F0C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F2C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F4C, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F6C, 0x05000000, 0x00043E9C, 0x02080881
    .WORD 0x05000000, 0x00043C8C, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0
    .WORD 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x000437EC, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043818, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043870, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043844, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001006, 0x00001007
    .WORD 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x004C0F03, 0x0D030000, 0x0D00030D
    .WORD 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x41861200, 0x00000004, 0x00010F0A, 0x00000000
    .WORD 0x00000F06, 0x08000000, 0x0000040A, 0x41521500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x00001001, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004, 0x41D00F01, 0x00000004
    .WORD 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004
    .WORD 0x41E00F01, 0x00000004, 0x30583000, 0x00000004, 0x3F8E0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00001101, 0x39303000, 0x01000004, 0x0080018B, 0x0000040B, 0x41060600, 0x0B000004, 0x0C000181
    .WORD 0x00000182, 0x39D43000, 0x00800004, 0x00000401, 0x40EE0600, 0x00000004, 0xFFFF0F02, 0x0200FFFF
    .WORD 0x00000401, 0x40EE0600, 0x0C080004, 0x0C8C2205, 0x00000201, 0x30583000, 0x00820004, 0x00000405
    .WORD 0x40D60700, 0x00000004, 0x41E50F01, 0x00000004, 0x30583000, 0x00000004, 0x3F8E0F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x407A0500, 0x0B000004, 0x00000181, 0x3A643000, 0x0A810004, 0x0000020A
    .WORD 0x3FE60500, 0x00000004, 0x41BF0F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x41E70F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00010F06, 0x0A810000, 0x0000020A, 0x3FE60500, 0x00000004, 0x004C0F03, 0x0D030000, 0x0600020D
    .WORD 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106
    .WORD 0x0000110F, 0x00003100, 0x41A60F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x00000000
    .WORD 0x41520500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964, 0x726F7463, 0x2E2E2079, 0x6C000A2E
    .WORD 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D, 0x65726944, 0x726F7463, 0x00203A79
    .WORD 0x2D2D2D20, 0x0A002F00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/sh, 4911 bytes
    .ASCIIZ "bin/sh"
    .SPACE 117
    .ASCIIZ "00000011457"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4911 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x00043F92, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043F90, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
    .WORD 0x40040000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x20020889, 0x04020080, 0x06000000, 0x00043104, 0x02090981, 0x05000000
    .WORD 0x000430E8, 0x01810900, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x100A0000, 0x01880100, 0x01890200, 0x200A0800, 0x20010900, 0x040A0100, 0x07000000
    .WORD 0x00043170, 0x040A0080, 0x06000000, 0x00043160, 0x02080881, 0x02090981, 0x05000000, 0x00043130
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043178, 0x0F010000, 0x00000000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100
    .WORD 0x01890200, 0x018A0300, 0x040A0080, 0x06000000, 0x000431D0, 0x20010900, 0x23010800, 0x02080881
    .WORD 0x02090981, 0x030A0A81, 0x05000000, 0x000431A8, 0x01810800, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x01880100, 0x01890200
    .WORD 0x018A0300, 0x040A0080, 0x06000000, 0x00043224, 0x23090800, 0x02080881, 0x030A0A81, 0x05000000
    .WORD 0x00043204, 0x01810800, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x40040000
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x400E0000
    .WORD 0x31000000, 0x400D0000, 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000
    .WORD 0x05000000, 0x00043280, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
    .WORD 0x00000000, 0x00000000, 0x100F0000, 0x02010187, 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043550, 0x0F020000, 0x00043288, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x0004352C, 0x22030204
    .WORD 0x04030500, 0x15000000, 0x00043538, 0x02040481, 0x05000000, 0x000434E8, 0x0F030000, 0x00000001
    .WORD 0x25030208, 0x22010200, 0x05000000, 0x000435D0, 0x01810500, 0x400C0000, 0x04010080, 0x12000000
    .WORD 0x000435C8, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x000435C8, 0x0F020000, 0x00043288
    .WORD 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435AC
    .WORD 0x02040481, 0x05000000, 0x0004356C, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208
    .WORD 0x05000000, 0x000435D0, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080
    .WORD 0x06000000, 0x0004363C, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x0004363C, 0x0F020000
    .WORD 0x00043288, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000
    .WORD 0x00043630, 0x02040481, 0x05000000, 0x000435F0, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F010000, 0x00043288, 0x0F030000, 0x00000030, 0x04030080, 0x06000000
    .WORD 0x00043680, 0x0F020000, 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043658
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000
    .WORD 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0100, 0x01860D00, 0x10050000
    .WORD 0x01870600, 0x040C0081, 0x07000000, 0x000436F4, 0x04090080, 0x15000000, 0x000436F4, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043724
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437C4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043750, 0x020707B0, 0x05000000, 0x00043770, 0x04070089, 0x14000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043770, 0x0307078A, 0x020707C1, 0x23070600, 0x02060681, 0x02040481, 0x01890500
    .WORD 0x04090080, 0x07000000, 0x0004372C, 0x03060681, 0x04040080, 0x06000000, 0x000437B8, 0x20020600
    .WORD 0x23020800, 0x02080881, 0x03060681, 0x03040481, 0x05000000, 0x00043790, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11050000, 0x020D0D05, 0x01810A00, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x00000022, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200
    .WORD 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043924, 0x02010181, 0x02040481, 0x05000000
    .WORD 0x00043900, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439BC
    .WORD 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000
    .WORD 0x000439A4, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000
    .WORD 0x000439C4, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439C4, 0x0F010000
    .WORD 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A3C, 0x22010800, 0x01820900, 0x0F030000
    .WORD 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A4C, 0x040100CC, 0x07000000, 0x00043A3C
    .WORD 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A54, 0x0F010000
    .WORD 0xFFFFFFFF, 0x05000000, 0x00043A54, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AA0, 0x22010800
    .WORD 0x40070000, 0x01810800, 0x30000000, 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043AA8
    .WORD 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AE0
    .WORD 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x04010080, 0x06000000, 0x00043AF8, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043B38, 0x01820100
    .WORD 0x0F010000, 0x00000001, 0x30000000, 0x00043A64, 0x05000000, 0x00043B40, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00
    .WORD 0x01810800, 0x30000000, 0x00043930, 0x04010080, 0x06000000, 0x00043C0C, 0x01880100, 0x01810800
    .WORD 0x01820900, 0x30000000, 0x000439D4, 0x04010080, 0x06000000, 0x00043BF0, 0x0F020000, 0xFFFFFFFF
    .WORD 0x04010200, 0x06000000, 0x00043C0C, 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082
    .WORD 0x07000000, 0x00043BD8, 0x0F010000, 0x00043C28, 0x30000000, 0x00043098, 0x0F010000, 0x00043C2C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043B7C, 0x01810800, 0x30000000, 0x00043A64, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043C14, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000
    .WORD 0x100B0000, 0x100C0000, 0x030D0DD0, 0x01880100, 0x0F090000, 0x00000000, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043EA8, 0x040100A5
    .WORD 0x07000000, 0x00043D40, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043EA8, 0x040200A5
    .WORD 0x06000000, 0x00043D50, 0x040200F3, 0x06000000, 0x00043DE4, 0x040200E4, 0x06000000, 0x00043E00
    .WORD 0x040200E9, 0x06000000, 0x00043E00, 0x040200F8, 0x06000000, 0x00043E20, 0x040200E3, 0x06000000
    .WORD 0x00043E40, 0x040200E2, 0x06000000, 0x00043E5C, 0x040200EF, 0x06000000, 0x00043E7C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x05000000, 0x00043E9C, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22010300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DA8, 0x22020300, 0x11030000
    .WORD 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DD0, 0x0303098B, 0x0F040000, 0x00000004
    .WORD 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03
    .WORD 0x31000000, 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043EC8, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F0C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F2C, 0x05000000, 0x00043E9C
    .WORD 0x30000000, 0x00043D68, 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F4C, 0x05000000, 0x00043E9C, 0x30000000
    .WORD 0x00043D88, 0x02090981, 0x01810B00, 0x30000000, 0x00043F6C, 0x05000000, 0x00043E9C, 0x02080881
    .WORD 0x05000000, 0x00043C8C, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0
    .WORD 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x000437EC, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043818, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043870, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043844, 0x01810100, 0x30000000
    .WORD 0x00043EC8, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00010F01, 0x00000000
    .WORD 0x42620F02, 0x00000004, 0x00020F03, 0x00000000, 0x323C3000, 0x00000004, 0x00000F01, 0x00000000
    .WORD 0x428B0F02, 0x00000004, 0x007F0F03, 0x00000000, 0x32443000, 0x00020004, 0x00805600, 0x00000401
    .WORD 0x417A1300, 0x01000004, 0x00000184, 0x428B0F08, 0x00000004, 0x428B0F09, 0x00000004, 0x00000F0A
    .WORD 0x04000000, 0x0000040A, 0x407A1500, 0x080A0004, 0x05000205, 0x008A2006, 0x00000406, 0x406E0600
    .WORD 0x008D0004, 0x00000406, 0x406E0600, 0x00880004, 0x00000406, 0x40560600, 0x00FF0004, 0x00000406
    .WORD 0x40560600, 0x09000004, 0x09812306, 0x00000209, 0x406E0500, 0x08000004, 0x00000409, 0x406E1300
    .WORD 0x09810004, 0x00000309, 0x406E0500, 0x0A810004, 0x0000020A, 0x40020500, 0x00000004, 0x00000F06
    .WORD 0x09000000, 0x00002306, 0x428B0F07, 0x07000004, 0x00802006, 0x00000406, 0x3F960600, 0x00000004
    .WORD 0x41823000, 0x00000004, 0x428B0F01, 0x00000004, 0x42660F02, 0x00000004, 0x31183000, 0x00810004
    .WORD 0x00000401, 0x417A0600, 0x00000004, 0x325C3000, 0x00800004, 0x00000401, 0x41120600, 0x00000004
    .WORD 0x414A1200, 0x00000004, 0xFFFF0F01, 0x0000FFFF, 0x00000F02, 0x00000000, 0x326C3000, 0x00800004
    .WORD 0x00000401, 0x41621200, 0x00000004, 0x3F960500, 0x00000004, 0x428B0F01, 0x00000004, 0x430B0F02
    .WORD 0x00000004, 0x00000F03, 0x00000000, 0x32643000, 0x00000004, 0x426B0F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x0000110F, 0x00003100, 0x42770F01, 0x00000004, 0x30583000, 0x00000004, 0x3F960500
    .WORD 0x00000004, 0x42810F01, 0x00000004, 0x30583000, 0x00000004, 0x3F960500, 0x00000004, 0x0000110F
    .WORD 0x00003100, 0x0000100F, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x428B0F08, 0x00000004
    .WORD 0x430B0F09, 0x00000004, 0x00000F0A, 0x08000000, 0x00A0200B, 0x0000040B, 0x41D60700, 0x00000004
    .WORD 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208, 0x41AE0500, 0x08000004, 0x0080200B, 0x0000040B
    .WORD 0x423E0600, 0x00880004, 0x0000040A, 0x423E1500, 0x09000004, 0x09842508, 0x0A810209, 0x0800020A
    .WORD 0x0080200B, 0x0000040B, 0x423E0600, 0x00A00004, 0x0000040B, 0x42260600, 0x08810004, 0x00000208
    .WORD 0x41FE0500, 0x00000004, 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208, 0x41AE0500, 0x00000004
    .WORD 0x00000F0B, 0x09000000, 0x0000250B, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F
    .WORD 0x20243100, 0x7571000D, 0x45007469, 0x56434558, 0x52452045, 0x46000A52, 0x204B524F, 0x0A525245
    .WORD 0x49415700, 0x52452054, 0x00000A52, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; etc/logo.txt, 867 bytes
    .ASCIIZ "etc/logo.txt"
    .SPACE 111
    .ASCIIZ "00000001543"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (867 bytes, padded to 1024)
    .WORD 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848
    .WORD 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x20480A48
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A482020, 0x48202048
    .WORD 0x20202048, 0x20204848, 0x48484848, 0x20202048, 0x33484848, 0x20202033, 0x32323232, 0x20202032
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20480A48, 0x20484820
    .WORD 0x20484820, 0x48482020, 0x48482020, 0x20202020, 0x20333320, 0x20323220, 0x32322020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A482020, 0x48202048, 0x48484848
    .WORD 0x20202020, 0x48484848, 0x20202048, 0x33484848, 0x20202033, 0x32202020, 0x20202032, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20480A48, 0x20484820, 0x20484820
    .WORD 0x48482020, 0x20484820, 0x20202020, 0x20333320, 0x20202020, 0x20203232, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A482020, 0x48202048, 0x20202048, 0x20204848
    .WORD 0x20204848, 0x48204848, 0x33334848, 0x20202020, 0x32323232, 0x20203232, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20480A48, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x0A482020, 0x3D3D3D48, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x4F423D3D, 0x4E49544F, 0x3D3D3D47, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x20480A48, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20482020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x0A482020, 0x20202048, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202048, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20480A48, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202024
    .WORD 0x20482020, 0x20202020, 0x20202420, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x0A482020, 0x3D3D3D48, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D48, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x48480A48, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848
    .WORD 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848
    .WORD 0x00484848, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; lib/libc.inc, 40090 bytes
    .ASCIIZ "lib/libc.inc"
    .SPACE 111
    .ASCIIZ "00000116232"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (40090 bytes, padded to 40448)
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
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x766E6520, 0x203D2070, 0x4C4C554E, 0x2020200A, 0x53555020
    .WORD 0x31522048, 0x2020200A, 0x53555020, 0x32522048, 0x2020200A, 0x53555020, 0x33522048, 0x2020200A
    .WORD 0x49203B20, 0x6974696E, 0x7A696C61, 0x68742065, 0x6C612065, 0x61636F6C, 0x20726F74, 0x73756D28
    .WORD 0x6F642074, 0x69687420, 0x69662073, 0x21747372, 0x20200A29, 0x41432020, 0x6D204C4C, 0x6F6C6C61
    .WORD 0x6E695F63, 0x200A7469, 0x50202020, 0x2020504F, 0x200A3352, 0x50202020, 0x2020504F, 0x200A3252
    .WORD 0x50202020, 0x2020504F, 0x200A3152, 0x3B202020, 0x75626544, 0x0A322067, 0x20202020, 0x6D204C42
    .WORD 0x206E6961, 0x20202020, 0x20202020, 0x20202020, 0x63203B20, 0x206C6C61, 0x6E69616D, 0x6F6F6C20
    .WORD 0x202D2070, 0x6320736C, 0x65207461, 0x206F6863, 0x0A637465, 0x20202020, 0x6265443B, 0x32206775
    .WORD 0x2020200A, 0x20494C20, 0x30203152, 0x2020200A, 0x53555020, 0x31522048, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x74697865, 0x2D203020, 0x63757320, 0x73736563, 0x2D203120, 0x72726520
    .WORD 0x200A726F, 0x4C202020, 0x31522049, 0x20203120, 0x20202020, 0x20202020, 0x20202020, 0x7570203B
    .WORD 0x6F742074, 0x656C7320, 0x73207065, 0x6170206F, 0x746E6572, 0x69617720, 0x64697074, 0x6E616320
    .WORD 0x726F7720, 0x20200A6B, 0x56532020, 0x59532043, 0x4C535F53, 0x0A504545, 0x20202020, 0x6265443B
    .WORD 0x32206775, 0x2020200A, 0x504F5020, 0x31522020, 0x2020200A, 0x494C203B, 0x20315220, 0x20200A31
    .WORD 0x56532020, 0x59532043, 0x58455F53, 0x0A0A5449, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D
    .WORD 0x7570203B, 0x2D207374, 0x69725720, 0x6E206574, 0x2D6C6C75, 0x6D726574, 0x74616E69, 0x73206465
    .WORD 0x6E697274, 0x6F742067, 0x64747320, 0x2074756F, 0x68746977, 0x77656E20, 0x656E696C, 0x49203B0A
    .WORD 0x20203A4E, 0x3D203152, 0x72747320, 0x20676E69, 0x6E696F70, 0x0A726574, 0x554F203B, 0x52203A54
    .WORD 0x203D2031, 0x65747962, 0x72772073, 0x65747469, 0x726F206E, 0x72726520, 0x6320726F, 0x0A65646F
    .WORD 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x73747570, 0x20200A3A, 0x55502020, 0x4C204853
    .WORD 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x4F4D2020
    .WORD 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x74732065, 0x676E6972
    .WORD 0x696F7020, 0x7265746E, 0x2020200A, 0x204C4220, 0x6C727473, 0x20206E65, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x20746547, 0x69727473, 0x6C20676E, 0x74676E65, 0x20200A68, 0x4F4D2020, 0x39522056
    .WORD 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x656C2065, 0x6874676E, 0x2020200A
    .WORD 0x20494C20, 0x53203152, 0x554F4454, 0x44465F54, 0x2020200A, 0x564F4D20, 0x20325220, 0x20203852
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x66667542, 0x3D207265, 0x72747320, 0x0A676E69, 0x20202020
    .WORD 0x20564F4D, 0x52203352, 0x20202039, 0x20202020, 0x20202020, 0x43203B20, 0x746E756F, 0x6C203D20
    .WORD 0x74676E65, 0x20200A68, 0x56532020, 0x59532043, 0x52575F53, 0x0A455449, 0x20202020, 0x20504F50
    .WORD 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220
    .WORD 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x63747570, 0x20726168, 0x7257202D
    .WORD 0x20657469, 0x676E6973, 0x6320656C, 0x61726168, 0x72657463, 0x206F7420, 0x6F647473, 0x3B0A7475
    .WORD 0x3A4E4920, 0x31522020, 0x63203D20, 0x61726168, 0x72657463, 0x4F203B0A, 0x203A5455, 0x3D203152
    .WORD 0x74796220, 0x77207365, 0x74746972, 0x28206E65, 0x6F202931, 0x72652072, 0x20726F72, 0x65646F63
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x7475700A, 0x72616863, 0x20200A3A, 0x55502020
    .WORD 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x494C2020, 0x20385220, 0x625F6863
    .WORD 0x200A6675, 0x53202020, 0x52204254, 0x525B2031, 0x20205D38, 0x20202020, 0x20202020, 0x7453203B
    .WORD 0x2065726F, 0x72616863, 0x206E6920, 0x74617473, 0x62206369, 0x65666675, 0x20200A72, 0x494C2020
    .WORD 0x20315220, 0x4F445453, 0x465F5455, 0x20200A44, 0x4F4D2020, 0x32522056, 0x0A385220, 0x20202020
    .WORD 0x5220494C, 0x0A312033, 0x20202020, 0x20435653, 0x5F535953, 0x54495257, 0x20200A45, 0x4F502020
    .WORD 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x73203B0A, 0x656C7274, 0x202D206E, 0x636C6143, 0x74616C75, 0x74732065
    .WORD 0x676E6972, 0x6E656C20, 0x0A687467, 0x4E49203B, 0x5220203A, 0x203D2031, 0x69727473, 0x7020676E
    .WORD 0x746E696F, 0x3B0A7265, 0x54554F20, 0x3152203A, 0x6C203D20, 0x74676E65, 0x65282068, 0x756C6378
    .WORD 0x676E6964, 0x6C756E20, 0x6574206C, 0x6E696D72, 0x726F7461, 0x3D3B0A29, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x74730A3D, 0x6E656C72, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020
    .WORD 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x4F4D2020, 0x38522056, 0x0A315220
    .WORD 0x20202020, 0x5220494C, 0x0A302039, 0x6C727473, 0x6C5F6E65, 0x3A706F6F, 0x2020200A, 0x42444C20
    .WORD 0x20325220, 0x2038525B, 0x3952202B, 0x2020205D, 0x203B2020, 0x64616552, 0x61686320, 0x74636172
    .WORD 0x61207265, 0x75632074, 0x6E657272, 0x666F2074, 0x74657366, 0x2020200A, 0x504D4320, 0x20325220
    .WORD 0x20200A30, 0x45422020, 0x74732051, 0x6E656C72, 0x6E6F645F, 0x20200A65, 0x44412020, 0x39522044
    .WORD 0x20395220, 0x20202031, 0x20202020, 0x3B202020, 0x636E4920, 0x656D6572, 0x6320746E, 0x746E756F
    .WORD 0x200A7265, 0x42202020, 0x72747320, 0x5F6E656C, 0x706F6F6C, 0x7274730A, 0x5F6E656C, 0x656E6F64
    .WORD 0x20200A3A, 0x4F4D2020, 0x31522056, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020
    .WORD 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x3D3B0A0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x63727473, 0x2D20706D, 0x6D6F4320, 0x65726170, 0x6F777420
    .WORD 0x72747320, 0x73676E69, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x72747320, 0x31676E69, 0x3252202C
    .WORD 0x73203D20, 0x6E697274, 0x3B0A3267, 0x54554F20, 0x3152203A, 0x31203D20, 0x20666920, 0x61757165
    .WORD 0x30202C6C, 0x20666920, 0x66666964, 0x6E657265, 0x3D3B0A74, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x74730A3D, 0x706D6372, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853
    .WORD 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x55502020, 0x52204853, 0x200A3031, 0x4D202020
    .WORD 0x5220564F, 0x31522038, 0x2020200A, 0x564F4D20, 0x20395220, 0x730A3252, 0x6D637274, 0x6F6C5F70
    .WORD 0x0A3A706F, 0x20202020, 0x2042444C, 0x20303152, 0x5D38525B, 0x20202020, 0x20202020, 0x4C203B20
    .WORD 0x2064616F, 0x72616863, 0x6F726620, 0x7473206D, 0x676E6972, 0x20200A31, 0x444C2020, 0x31522042
    .WORD 0x39525B20, 0x2020205D, 0x20202020, 0x3B202020, 0x616F4C20, 0x68632064, 0x66207261, 0x206D6F72
    .WORD 0x69727473, 0x0A32676E, 0x20202020, 0x20504D43, 0x20303152, 0x200A3152, 0x42202020, 0x7320454E
    .WORD 0x6D637274, 0x656E5F70, 0x20202020, 0x20202020, 0x694D203B, 0x74616D73, 0x66206863, 0x646E756F
    .WORD 0x2020200A, 0x504D4320, 0x30315220, 0x200A3020, 0x42202020, 0x73205145, 0x6D637274, 0x71655F70
    .WORD 0x20202020, 0x20202020, 0x6F42203B, 0x73206874, 0x6E697274, 0x65207367, 0x6465646E, 0x20746120
    .WORD 0x656D6173, 0x6D697420, 0x20200A65, 0x44412020, 0x38522044, 0x20385220, 0x20202031, 0x20202020
    .WORD 0x3B202020, 0x76644120, 0x65636E61, 0x746F6220, 0x6F702068, 0x65746E69, 0x200A7372, 0x41202020
    .WORD 0x52204444, 0x39522039, 0x200A3120, 0x42202020, 0x72747320, 0x5F706D63, 0x706F6F6C, 0x7274730A
    .WORD 0x5F706D63, 0x0A3A7165, 0x20202020, 0x5220494C, 0x0A312031, 0x20202020, 0x74732042, 0x706D6372
    .WORD 0x6E6F645F, 0x74730A65, 0x706D6372, 0x3A656E5F, 0x2020200A, 0x20494C20, 0x30203152, 0x7274730A
    .WORD 0x5F706D63, 0x656E6F64, 0x20200A3A, 0x4F502020, 0x31522050, 0x20200A30, 0x4F502020, 0x39522050
    .WORD 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x656D203B, 0x7970636D, 0x43202D20, 0x2079706F
    .WORD 0x6F6D656D, 0x62207972, 0x6B636F6C, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x73656420, 0x52202C74
    .WORD 0x203D2032, 0x2C637273, 0x20335220, 0x6F63203D, 0x0A746E75, 0x554F203B, 0x52203A54, 0x203D2031
    .WORD 0x74736564, 0x6E652820, 0x6F702064, 0x69746973, 0x0A296E6F, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A3D3D3D, 0x636D656D, 0x0A3A7970, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550
    .WORD 0x0A385220, 0x20202020, 0x48535550, 0x0A395220, 0x20202020, 0x48535550, 0x30315220, 0x2020200A
    .WORD 0x564F4D20, 0x20385220, 0x200A3152, 0x4D202020, 0x5220564F, 0x32522039, 0x2020200A, 0x564F4D20
    .WORD 0x30315220, 0x0A335220, 0x636D656D, 0x6C5F7970, 0x3A706F6F, 0x2020200A, 0x504D4320, 0x30315220
    .WORD 0x200A3020, 0x42202020, 0x6D205145, 0x70636D65, 0x6F645F79, 0x200A656E, 0x4C202020, 0x52204244
    .WORD 0x525B2031, 0x20205D39, 0x20202020, 0x20202020, 0x6552203B, 0x62206461, 0x20657479, 0x6D6F7266
    .WORD 0x756F7320, 0x0A656372, 0x20202020, 0x20425453, 0x5B203152, 0x205D3852, 0x20202020, 0x20202020
    .WORD 0x57203B20, 0x65746972, 0x74796220, 0x6F742065, 0x73656420, 0x616E6974, 0x6E6F6974, 0x2020200A
    .WORD 0x44444120, 0x20385220, 0x31203852, 0x20202020, 0x20202020, 0x203B2020, 0x61766441, 0x2065636E
    .WORD 0x68746F62, 0x696F7020, 0x7265746E, 0x20200A73, 0x44412020, 0x39522044, 0x20395220, 0x20200A31
    .WORD 0x55532020, 0x31522042, 0x31522030, 0x20312030, 0x20202020, 0x3B202020, 0x63654420, 0x656D6572
    .WORD 0x6320746E, 0x746E756F, 0x200A7265, 0x42202020, 0x6D656D20, 0x5F797063, 0x706F6F6C, 0x6D656D0A
    .WORD 0x5F797063, 0x656E6F64, 0x20200A3A, 0x4F4D2020, 0x31522056, 0x0A385220, 0x20202020, 0x20504F50
    .WORD 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020
    .WORD 0x524C2050, 0x2020200A, 0x54455220, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D
    .WORD 0x736D656D, 0x2D207465, 0x6C694620, 0x656D206C, 0x79726F6D, 0x74697720, 0x6F632068, 0x6174736E
    .WORD 0x6220746E, 0x0A657479, 0x4E49203B, 0x5220203A, 0x203D2031, 0x74736564, 0x3252202C, 0x76203D20
    .WORD 0x65756C61, 0x3352202C, 0x63203D20, 0x746E756F, 0x4F203B0A, 0x203A5455, 0x3D203152, 0x73656420
    .WORD 0x65282074, 0x7020646E, 0x7469736F, 0x296E6F69, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x6D656D0A, 0x3A746573, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048
    .WORD 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x53555020, 0x31522048, 0x20200A30, 0x4F4D2020
    .WORD 0x38522056, 0x0A315220, 0x20202020, 0x20564F4D, 0x52203952, 0x20200A32, 0x4F4D2020, 0x31522056
    .WORD 0x33522030, 0x6D656D0A, 0x5F746573, 0x706F6F6C, 0x20200A3A, 0x4D432020, 0x31522050, 0x0A302030
    .WORD 0x20202020, 0x20514542, 0x736D656D, 0x645F7465, 0x0A656E6F, 0x20202020, 0x20425453, 0x5B203952
    .WORD 0x205D3852, 0x20202020, 0x20202020, 0x53203B20, 0x65726F74, 0x6C617620, 0x61206575, 0x75632074
    .WORD 0x6E657272, 0x6F702074, 0x69746973, 0x200A6E6F, 0x41202020, 0x52204444, 0x38522038, 0x20203120
    .WORD 0x20202020, 0x20202020, 0x6441203B, 0x636E6176, 0x6F702065, 0x65746E69, 0x20200A72, 0x55532020
    .WORD 0x31522042, 0x31522030, 0x20312030, 0x20202020, 0x3B202020, 0x63654420, 0x656D6572, 0x6320746E
    .WORD 0x746E756F, 0x200A7265, 0x42202020, 0x6D656D20, 0x5F746573, 0x706F6F6C, 0x6D656D0A, 0x5F746573
    .WORD 0x656E6F64, 0x20200A3A, 0x4F4D2020, 0x31522056, 0x0A385220, 0x20202020, 0x20504F50, 0x0A303152
    .WORD 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050
    .WORD 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x74697277
    .WORD 0x64662865, 0x7562202C, 0x6C202C66, 0x0A296E65, 0x203B0A3B, 0x0A3A4E49, 0x2020203B, 0x3D203152
    .WORD 0x0A646620, 0x2020203B, 0x3D203252, 0x66756220, 0x0A726566, 0x2020203B, 0x3D203352, 0x6E656C20
    .WORD 0x0A687467, 0x203B0A3B, 0x3A54554F, 0x20203B0A, 0x20315220, 0x7962203D, 0x20736574, 0x74697277
    .WORD 0x206E6574, 0x7265202F, 0x0A6F6E72, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x74697277
    .WORD 0x200A3A65, 0x53202020, 0x53204356, 0x575F5359, 0x45544952, 0x2020200A, 0x54455220, 0x3B0A0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x61657220, 0x64662864, 0x7562202C, 0x6C202C66
    .WORD 0x0A296E65, 0x203B0A3B, 0x0A3A4E49, 0x2020203B, 0x3D203152, 0x0A646620, 0x2020203B, 0x3D203252
    .WORD 0x66756220, 0x0A726566, 0x2020203B, 0x3D203352, 0x6E656C20, 0x0A687467, 0x203B0A3B, 0x3A54554F
    .WORD 0x20203B0A, 0x20315220, 0x7962203D, 0x20736574, 0x64616572, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6165720A, 0x200A3A64, 0x53202020, 0x53204356, 0x525F5359, 0x0A444145, 0x20202020
    .WORD 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6E65706F, 0x74617028
    .WORD 0x66202C68, 0x7367616C, 0x0A3B0A29, 0x4E49203B, 0x203B0A3A, 0x31522020, 0x70203D20, 0x0A687461
    .WORD 0x2020203B, 0x3D203252, 0x616C6620, 0x3B0A7367, 0x4F203B0A, 0x0A3A5455, 0x2020203B, 0x3D203152
    .WORD 0x0A646620, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6E65706F, 0x20200A3A, 0x56532020
    .WORD 0x59532043, 0x504F5F53, 0x200A4E45, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x63203B0A, 0x65736F6C, 0x29646628, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6F6C630A, 0x0A3A6573, 0x20202020, 0x20435653, 0x5F535953, 0x534F4C43, 0x20200A45, 0x45522020
    .WORD 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6F66203B, 0x29286B72, 0x3B0A3B0A
    .WORD 0x72617020, 0x3A746E65, 0x20203B0A, 0x20315220, 0x6863203D, 0x20646C69, 0x0A646970, 0x203B0A3B
    .WORD 0x6C696863, 0x3B0A3A64, 0x52202020, 0x203D2031, 0x2D3B0A30, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6F660A2D, 0x0A3A6B72, 0x20202020, 0x20435653, 0x5F535953, 0x4B524F46, 0x2020200A, 0x54455220
    .WORD 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x65786520, 0x28657663, 0x68746170
    .WORD 0x7261202C, 0x202C7667, 0x70766E65, 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x78650A2D
    .WORD 0x65766365, 0x20200A3A, 0x56532020, 0x59532043, 0x58455F53, 0x45564345, 0x2020200A, 0x54455220
    .WORD 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x69617720, 0x64697074, 0x64697028
    .WORD 0x6174732C, 0x29737574, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6961770A, 0x64697074
    .WORD 0x20200A3A, 0x56532020, 0x59532043, 0x41575F53, 0x49505449, 0x20200A44, 0x45522020, 0x0A0A0A54
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6C73203B, 0x28706565, 0x6C6C696D, 0x63657369
    .WORD 0x73646E6F, 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C730A2D, 0x3A706565, 0x2020200A
    .WORD 0x43565320, 0x53595320, 0x454C535F, 0x200A5045, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x65203B0A, 0x28746978, 0x74617473, 0x0A297375, 0x203B0A3B, 0x6576656E
    .WORD 0x65722072, 0x6E727574, 0x2D3B0A73, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x78650A2D, 0x0A3A7469
    .WORD 0x20202020, 0x20435653, 0x5F535953, 0x54495845, 0x78650A0A, 0x685F7469, 0x3A676E61, 0x2020200A
    .WORD 0x65204220, 0x5F746978, 0x676E6168, 0x3B0A0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D
    .WORD 0x4D454D20, 0x2059524F, 0x414E414D, 0x454D4547, 0x3B0A544E, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A0A3D3D, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x4556203B, 0x53205952, 0x4C504D49
    .WORD 0x454D2045, 0x59524F4D, 0x4C4C4120, 0x5441434F, 0x3B0A524F, 0x54203B0A, 0x20736968, 0x61207369
    .WORD 0x6E696D20, 0x6C616D69, 0x6C616D20, 0x2F636F6C, 0x65657266, 0x706D6920, 0x656D656C, 0x7461746E
    .WORD 0x206E6F69, 0x74616874, 0x203B0A3A, 0x55202E31, 0x20736573, 0x69662061, 0x20646578, 0x61727261
    .WORD 0x6F742079, 0x61727420, 0x6D206B63, 0x726F6D65, 0x6C622079, 0x736B636F, 0x32203B0A, 0x6F44202E
    .WORD 0x4E207365, 0x6320544F, 0x656C616F, 0x20656373, 0x72656D28, 0x61206567, 0x63616A64, 0x20746E65
    .WORD 0x65657266, 0x6F6C6220, 0x29736B63, 0x33203B0A, 0x6F44202E, 0x4E207365, 0x7320544F, 0x74696C70
    .WORD 0x6F6C6220, 0x20736B63, 0x65737528, 0x6E652073, 0x65726974, 0x6F6C6220, 0x61206B63, 0x73692D73
    .WORD 0x203B0A29, 0x55202E34, 0x20736573, 0x73726966, 0x69662D74, 0x65732074, 0x68637261, 0x69662820
    .WORD 0x2073646E, 0x73726966, 0x6C622074, 0x206B636F, 0x74616874, 0x62207327, 0x65206769, 0x67756F6E
    .WORD 0x3B0A2968, 0x202E3520, 0x73657355, 0x72627320, 0x7973206B, 0x6C616373, 0x6F74206C, 0x74656720
    .WORD 0x726F6D20, 0x656D2065, 0x79726F6D, 0x6F726620, 0x656B206D, 0x6C656E72, 0x3B0A3B0A, 0x61725420
    .WORD 0x6F2D6564, 0x3A736666, 0x2B203B0A, 0x72655620, 0x69732079, 0x656C706D, 0x646E6120, 0x73616520
    .WORD 0x6F742079, 0x646E7520, 0x74737265, 0x0A646E61, 0x202B203B, 0x64657250, 0x61746369, 0x20656C62
    .WORD 0x6F6D656D, 0x75207972, 0x65676173, 0x69662820, 0x20646578, 0x6C626174, 0x3B0A2965, 0x4E202B20
    .WORD 0x6F63206F, 0x656C706D, 0x696C2078, 0x64656B6E, 0x73696C20, 0x616D2074, 0x6567616E, 0x746E656D
    .WORD 0x2D203B0A, 0x6D654D20, 0x2079726F, 0x67617266, 0x746E656D, 0x6F697461, 0x6328206E, 0x74276E61
    .WORD 0x72656D20, 0x66206567, 0x20656572, 0x636F6C62, 0x0A29736B, 0x202D203B, 0x74736157, 0x73206465
    .WORD 0x65636170, 0x61632820, 0x2074276E, 0x696C7073, 0x616C2074, 0x20656772, 0x636F6C62, 0x0A29736B
    .WORD 0x202D203B, 0x696D694C, 0x20646574, 0x4D206F74, 0x425F5841, 0x4B434F4C, 0x6C612053, 0x61636F6C
    .WORD 0x6E6F6974, 0x2D3B0A73, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A0A2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x4E4F4320, 0x4E415453, 0x3B0A5354, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A0A2D2D, 0x5551452E, 0x58414D20, 0x4F4C425F, 0x2C534B43, 0x20383420, 0x20202020, 0x203B2020
    .WORD 0x6978614D, 0x206D756D, 0x626D756E, 0x6F207265, 0x6C622066, 0x736B636F, 0x20657720, 0x206E6163
    .WORD 0x63617274, 0x20200A6B, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6328203B, 0x74276E61, 0x6C6C6120, 0x7461636F, 0x6F6D2065, 0x74206572, 0x206E6168, 0x74203233
    .WORD 0x73656D69, 0x74697720, 0x74756F68, 0x65726620, 0x676E6965, 0x3B0A0A29, 0x6F6C4220, 0x64206B63
    .WORD 0x72637365, 0x6F747069, 0x666F2072, 0x74657366, 0x65282073, 0x20686361, 0x636F6C62, 0x656E206B
    .WORD 0x20736465, 0x73656874, 0x20332065, 0x756C6176, 0x0A297365, 0x5551452E, 0x4F4C4220, 0x415F4B43
    .WORD 0x2C524444, 0x20302020, 0x20202020, 0x203B2020, 0x7366664F, 0x203A7465, 0x72617473, 0x676E6974
    .WORD 0x64646120, 0x73736572, 0x20666F20, 0x20656874, 0x636F6C62, 0x3428206B, 0x74796220, 0x0A297365
    .WORD 0x5551452E, 0x4F4C4220, 0x535F4B43, 0x2C455A49, 0x20342020, 0x20202020, 0x203B2020, 0x7366664F
    .WORD 0x203A7465, 0x657A6973, 0x20666F20, 0x20656874, 0x636F6C62, 0x6E69206B, 0x74796220, 0x28207365
    .WORD 0x79622034, 0x29736574, 0x2E0A2020, 0x20555145, 0x434F4C42, 0x53555F4B, 0x202C4445, 0x20203820
    .WORD 0x20202020, 0x4F203B20, 0x65736666, 0x30203A74, 0x6572663D, 0x31202C65, 0x6573753D, 0x34282064
    .WORD 0x74796220, 0x0A297365, 0x5551452E, 0x4F4C4220, 0x445F4B43, 0x2C435345, 0x32312020, 0x20202020
    .WORD 0x203B2020, 0x61746F54, 0x6973206C, 0x6F20657A, 0x6E6F2066, 0x6C622065, 0x206B636F, 0x63736564
    .WORD 0x74706972, 0x2820726F, 0x6F772033, 0x20736472, 0x3231203D, 0x74796220, 0x0A297365, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x44203B0A, 0x20415441, 0x54434553, 0x204E4F49, 0x6854202D
    .WORD 0x6C622065, 0x206B636F, 0x6C626174, 0x3B0A2065, 0x726F6E20, 0x6C6C616D, 0x656D2079, 0x79726F6D
    .WORD 0x6F6C6220, 0x20736B63, 0x20746567, 0x65736572, 0x65766572, 0x72662064, 0x48206D6F, 0x20504145
    .WORD 0x63696877, 0x73692068, 0x636F6C20, 0x64657461, 0x20746120, 0x61746164, 0x67657320, 0x746E656D
    .WORD 0x203B0A20, 0x65676170, 0x61702820, 0x61206567, 0x65726464, 0x73207373, 0x69636570, 0x64656966
    .WORD 0x20736120, 0x72657375, 0x7461645F, 0x61765F61, 0x3B0A2029, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A0A2D2D, 0x636F6C62, 0x61745F6B, 0x3A656C62, 0x2020200A, 0x54203B20, 0x20736968, 0x61207369
    .WORD 0x7261206E, 0x20796172, 0x4D20666F, 0x425F5841, 0x4B434F4C, 0x65642053, 0x69726373, 0x726F7470
    .WORD 0x200A2E73, 0x3B202020, 0x63614520, 0x65642068, 0x69726373, 0x726F7470, 0x73616820, 0x6461203A
    .WORD 0x73657264, 0x73202C73, 0x2C657A69, 0x65737520, 0x6C665F64, 0x200A6761, 0x3B202020, 0x746F5420
    .WORD 0x73206C61, 0x3A657A69, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x3231202A, 0x74796220, 0x200A7365
    .WORD 0x2E202020, 0x43415053, 0x414D2045, 0x4C425F58, 0x534B434F, 0x42202A20, 0x4B434F4C, 0x5345445F
    .WORD 0x3B0A0A43, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6C616D20, 0x28636F6C, 0x657A6973
    .WORD 0x0A3B0A29, 0x6C41203B, 0x61636F6C, 0x20736574, 0x6F6D656D, 0x66207972, 0x206D6F72, 0x20656874
    .WORD 0x70616568, 0x0A3B0A2E, 0x6F48203B, 0x74692077, 0x726F7720, 0x0A3A736B, 0x2E31203B, 0x696C4120
    .WORD 0x74206E67, 0x72206568, 0x65757165, 0x64657473, 0x7A697320, 0x6F742065, 0x62203820, 0x73657479
    .WORD 0x616D2820, 0x2073656B, 0x6F6D656D, 0x6D207972, 0x67616E61, 0x6E656D65, 0x61652074, 0x72656973
    .WORD 0x203B0A29, 0x53202E32, 0x63726165, 0x68742068, 0x6C622065, 0x206B636F, 0x6C626174, 0x6F662065
    .WORD 0x20612072, 0x65657266, 0x6F6C6220, 0x74206B63, 0x27746168, 0x616C2073, 0x20656772, 0x756F6E65
    .WORD 0x3B0A6867, 0x202E3320, 0x66206649, 0x646E756F, 0x616D202C, 0x69206B72, 0x73612074, 0x65737520
    .WORD 0x6E612064, 0x65722064, 0x6E727574, 0x73746920, 0x64646120, 0x73736572, 0x34203B0A, 0x6649202E
    .WORD 0x746F6E20, 0x756F6620, 0x202C646E, 0x206B7361, 0x20656874, 0x6E72656B, 0x66206C65, 0x6D20726F
    .WORD 0x2065726F, 0x6F6D656D, 0x76207972, 0x73206169, 0x206B7262, 0x63737973, 0x0A6C6C61, 0x2E35203B
    .WORD 0x64644120, 0x65687420, 0x77656E20, 0x6D656D20, 0x2079726F, 0x74206F74, 0x62206568, 0x6B636F6C
    .WORD 0x62617420, 0x6120656C, 0x7220646E, 0x72757465, 0x7469206E, 0x3B0A3B0A, 0x706E4920, 0x203A7475
    .WORD 0x20315220, 0x6973203D, 0x6920657A, 0x7962206E, 0x20736574, 0x672E6528, 0x31202C2E, 0x0A293030
    .WORD 0x754F203B, 0x74757074, 0x3152203A, 0x70203D20, 0x746E696F, 0x74207265, 0x6C61206F, 0x61636F6C
    .WORD 0x20646574, 0x6F6D656D, 0x28207972, 0x3020726F, 0x20666920, 0x6C696166, 0x0A296465, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6C6C616D, 0x0A3A636F, 0x20202020, 0x6153203B, 0x72206576
    .WORD 0x73696765, 0x73726574, 0x27657720, 0x75206C6C, 0x28206573, 0x77206F73, 0x6F642065, 0x2074276E
    .WORD 0x72726F63, 0x20747075, 0x6C6C6163, 0x73277265, 0x6C617620, 0x29736575, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x65722065, 0x6E727574
    .WORD 0x64646120, 0x73736572, 0x2020200A, 0x20200A20, 0x203B2020, 0x70657453, 0x203A3120, 0x67696C41
    .WORD 0x6973206E, 0x7420657A, 0x756D206F, 0x7069746C, 0x6F20656C, 0x20382066, 0x65747962, 0x20200A73
    .WORD 0x203B2020, 0x3F796857, 0x6E614D20, 0x50432079, 0x77207355, 0x206B726F, 0x74736166, 0x77207265
    .WORD 0x20687469, 0x67696C61, 0x2064656E, 0x6F6D656D, 0x200A7972, 0x3B202020, 0x61784520, 0x656C706D
    .WORD 0x6973203A, 0x313D657A, 0x200A3030, 0x3B202020, 0x41202020, 0x52204444, 0x20372031, 0x2D202020
    .WORD 0x3031203E, 0x20200A37, 0x203B2020, 0x4E412020, 0x78302044, 0x46464646, 0x38464646, 0x203E2D20
    .WORD 0x20343031, 0x6C756D28, 0x6C706974, 0x666F2065, 0x0A293820, 0x20202020, 0x20444441, 0x52203152
    .WORD 0x20372031, 0x20202020, 0x20202020, 0x203B2020, 0x20646441, 0x6F742037, 0x756F7220, 0x7520646E
    .WORD 0x20200A70, 0x494C2020, 0x32522020, 0x46783020, 0x46464646, 0x20384646, 0x2020200A, 0x444E4120
    .WORD 0x20315220, 0x52203152, 0x20202032, 0x20202020, 0x3B202020, 0x656C4320, 0x6C207261, 0x7265776F
    .WORD 0x62203320, 0x20737469, 0x6B616D28, 0x756D2065, 0x7069746C, 0x6F20656C, 0x29382066, 0x2020200A
    .WORD 0x564F4D20, 0x20355220, 0x20203152, 0x20202020, 0x20202020, 0x3B202020, 0x20355220, 0x6C61203D
    .WORD 0x656E6769, 0x69732064, 0x2820657A, 0x2E672E65, 0x3031202C, 0x200A2934, 0x0A202020, 0x20202020
    .WORD 0x7453203B, 0x32207065, 0x6553203A, 0x68637261, 0x726F6620, 0x66206120, 0x20656572, 0x636F6C62
    .WORD 0x6E69206B, 0x65687420, 0x62617420, 0x200A656C, 0x3B202020, 0x27655720, 0x75206C6C, 0x52206573
    .WORD 0x73612034, 0x646E6920, 0x69207865, 0x206F746E, 0x636F6C62, 0x61745F6B, 0x20656C62, 0x74203028
    .WORD 0x414D206F, 0x4C425F58, 0x534B434F, 0x0A29312D, 0x20202020, 0x5220494C, 0x20302034, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x72617453, 0x74612074, 0x72696620, 0x62207473, 0x6B636F6C
    .WORD 0x6E692820, 0x20786564, 0x200A2930, 0x0A202020, 0x6C6C616D, 0x6C5F636F, 0x3A706F6F, 0x2020200A
    .WORD 0x43203B20, 0x6B636568, 0x20666920, 0x76276577, 0x65732065, 0x68637261, 0x61206465, 0x62206C6C
    .WORD 0x6B636F6C, 0x20200A73, 0x4D432020, 0x34522050, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x20202020
    .WORD 0x6F43203B, 0x7261706D, 0x6E692065, 0x20786564, 0x68746977, 0x78616D20, 0x6D756D69, 0x2020200A
    .WORD 0x45474220, 0x6C616D20, 0x5F636F6C, 0x6B726273, 0x20202020, 0x3B202020, 0x20664920, 0x65646E69
    .WORD 0x3D3E2078, 0x58414D20, 0x4F4C425F, 0x2C534B43, 0x206F6E20, 0x65657266, 0x6F6C6220, 0x66206B63
    .WORD 0x646E756F, 0x2020200A, 0x20200A20, 0x203B2020, 0x636C6143, 0x74616C75, 0x64612065, 0x73657264
    .WORD 0x666F2073, 0x69687420, 0x6C622073, 0x276B636F, 0x65642073, 0x69726373, 0x726F7470, 0x2020200A
    .WORD 0x62203B20, 0x6B636F6C, 0x6261745F, 0x2B20656C, 0x6E692820, 0x20786564, 0x6564202A, 0x69726373
    .WORD 0x726F7470, 0x7A69735F, 0x200A2965, 0x4C202020, 0x32522049, 0x6F6C6220, 0x745F6B63, 0x656C6261
    .WORD 0x20202020, 0x52203B20, 0x203D2032, 0x65736162, 0x64646120, 0x73736572, 0x20666F20, 0x636F6C62
    .WORD 0x61745F6B, 0x0A656C62, 0x20202020, 0x5220494C, 0x4C422033, 0x5F4B434F, 0x43534544, 0x20202020
    .WORD 0x203B2020, 0x3D203352, 0x7A697320, 0x666F2065, 0x656E6F20, 0x73656420, 0x70697263, 0x20726F74
    .WORD 0x20323128, 0x65747962, 0x200A2973, 0x4D202020, 0x52204C55, 0x34522033, 0x20335220, 0x20202020
    .WORD 0x20202020, 0x52203B20, 0x203D2033, 0x65646E69, 0x202A2078, 0x28203231, 0x7366666F, 0x69207465
    .WORD 0x206F746E, 0x6C626174, 0x200A2965, 0x41202020, 0x52204444, 0x32522032, 0x20335220, 0x20202020
    .WORD 0x20202020, 0x52203B20, 0x203D2032, 0x6F6C6226, 0x695B6B63, 0x7865646E, 0x20200A5D, 0x200A2020
    .WORD 0x3B202020, 0x65684320, 0x69206B63, 0x68742066, 0x62207369, 0x6B636F6C, 0x20736920, 0x65657266
    .WORD 0x53552820, 0x66204445, 0x2067616C, 0x2930203D, 0x2020200A, 0x57444C20, 0x20335220, 0x2032525B
    .WORD 0x4C42202B, 0x5F4B434F, 0x44455355, 0x3B20205D, 0x616F4C20, 0x68742064, 0x62262065, 0x6B636F6C
    .WORD 0x646E695B, 0x2E5D7865, 0x636F6C62, 0x73755F6B, 0x66206465, 0x0A67616C, 0x20202020, 0x20504D43
    .WORD 0x30203352, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x69207349, 0x20302074, 0x65726628
    .WORD 0x0A3F2965, 0x20202020, 0x20454E42, 0x6C6C616D, 0x6E5F636F, 0x20747865, 0x20202020, 0x203B2020
    .WORD 0x6E206649, 0x6620746F, 0x20656572, 0x65737528, 0x202C2964, 0x70696B73, 0x206F7420, 0x7478656E
    .WORD 0x6F6C6220, 0x200A6B63, 0x0A202020, 0x20202020, 0x7266203B, 0x202E6565, 0x63656843, 0x6669206B
    .WORD 0x69687420, 0x6C622073, 0x206B636F, 0x6C207369, 0x65677261, 0x6F6E6520, 0x20686775, 0x20726F66
    .WORD 0x2072756F, 0x75716572, 0x0A747365, 0x20202020, 0x2057444C, 0x5B203352, 0x2B203252, 0x4F4C4220
    .WORD 0x535F4B43, 0x5D455A49, 0x203B2020, 0x64616F4C, 0x65687420, 0x6F6C6220, 0x73206B63, 0x0A657A69
    .WORD 0x20202020, 0x20504D43, 0x52203352, 0x20202035, 0x20202020, 0x20202020, 0x203B2020, 0x62207349
    .WORD 0x6B636F6C, 0x7A697320, 0x3D3E2065, 0x71657220, 0x74736575, 0x73206465, 0x3F657A69, 0x2020200A
    .WORD 0x45474220, 0x6C616D20, 0x5F636F6C, 0x6E756F66, 0x20202064, 0x3B202020, 0x73655920, 0x65572021
    .WORD 0x756F6620, 0x6120646E, 0x69757320, 0x6C626174, 0x6C622065, 0x0A6B636F, 0x20202020, 0x6C616D0A
    .WORD 0x5F636F6C, 0x7478656E, 0x20200A3A, 0x203B2020, 0x73696854, 0x6F6C6220, 0x69206B63, 0x69652073
    .WORD 0x72656874, 0x65737520, 0x726F2064, 0x6F6F7420, 0x616D7320, 0x202C6C6C, 0x20797274, 0x7478656E
    .WORD 0x656E6F20, 0x2020200A, 0x44444120, 0x20345220, 0x31203452, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x636E4920, 0x656D6572, 0x6920746E, 0x7865646E, 0x206F7420, 0x63656863, 0x656E206B, 0x62207478
    .WORD 0x6B636F6C, 0x2020200A, 0x6D204220, 0x6F6C6C61, 0x6F6C5F63, 0x2020706F, 0x20202020, 0x3B202020
    .WORD 0x206F4720, 0x6B636162, 0x206F7420, 0x72617473, 0x666F2074, 0x6F6F6C20, 0x6D0A0A70, 0x6F6C6C61
    .WORD 0x6F665F63, 0x3A646E75, 0x2020200A, 0x53203B20, 0x20706574, 0x57203A33, 0x6F662065, 0x20646E75
    .WORD 0x72662061, 0x62206565, 0x6B636F6C, 0x72616C20, 0x65206567, 0x67756F6E, 0x200A2168, 0x3B202020
    .WORD 0x20325220, 0x6F70203D, 0x65746E69, 0x6F742072, 0x65687420, 0x6F6C6220, 0x64206B63, 0x72637365
    .WORD 0x6F747069, 0x20200A72, 0x203B2020, 0x3D203352, 0x6F6C6220, 0x73206B63, 0x20657A69, 0x20657728
    .WORD 0x276E6F64, 0x73752074, 0x74692065, 0x726F6620, 0x6C707320, 0x69747469, 0x6920676E, 0x6874206E
    .WORD 0x73207369, 0x6C706D69, 0x65762065, 0x6F697372, 0x200A296E, 0x0A202020, 0x20202020, 0x614D203B
    .WORD 0x74206B72, 0x62206568, 0x6B636F6C, 0x20736120, 0x64657375, 0x53552820, 0x66204445, 0x2067616C
    .WORD 0x2931203D, 0x2020200A, 0x20494C20, 0x31203352, 0x20202020, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x20335220, 0x2031203D, 0x65737528, 0x200A2964, 0x53202020, 0x52205754, 0x525B2033, 0x202B2032
    .WORD 0x434F4C42, 0x53555F4B, 0x205D4445, 0x53203B20, 0x65726F74, 0x69203120, 0x6874206E, 0x53552065
    .WORD 0x66204445, 0x646C6569, 0x2020200A, 0x20200A20, 0x203B2020, 0x20746547, 0x20656874, 0x636F6C62
    .WORD 0x2073276B, 0x72617473, 0x676E6974, 0x64646120, 0x73736572, 0x646E6120, 0x74657220, 0x206E7275
    .WORD 0x200A7469, 0x4C202020, 0x52205744, 0x525B2031, 0x202B2032, 0x434F4C42, 0x44415F4B, 0x205D5244
    .WORD 0x52203B20, 0x203D2031, 0x72646461, 0x20737365, 0x7420666F, 0x20736968, 0x636F6C62, 0x20200A6B
    .WORD 0x20422020, 0x6C6C616D, 0x645F636F, 0x20656E6F, 0x20202020, 0x20202020, 0x754A203B, 0x7420706D
    .WORD 0x6C63206F, 0x756E6165, 0x6E612070, 0x65722064, 0x6E727574, 0x616D0A0A, 0x636F6C6C, 0x7262735F
    .WORD 0x200A3A6B, 0x3B202020, 0x65745320, 0x3A342070, 0x206F4E20, 0x65657266, 0x6F6C6220, 0x66206B63
    .WORD 0x646E756F, 0x206E6920, 0x6C626174, 0x20200A65, 0x203B2020, 0x206B7341, 0x20656874, 0x6E72656B
    .WORD 0x66206C65, 0x6D20726F, 0x2065726F, 0x6F6D656D, 0x75207972, 0x676E6973, 0x72627320, 0x7973206B
    .WORD 0x6C616373, 0x20200A6C, 0x200A2020, 0x3B202020, 0x20355220, 0x65726C61, 0x20796461, 0x20736168
    .WORD 0x20656874, 0x67696C61, 0x2064656E, 0x657A6973, 0x20657720, 0x6465656E, 0x2020200A, 0x564F4D20
    .WORD 0x20315220, 0x20203552, 0x20202020, 0x20202020, 0x3B202020, 0x20315220, 0x6973203D, 0x7420657A
    .WORD 0x6C61206F, 0x61636F6C, 0x200A6574, 0x53202020, 0x53204356, 0x535F5359, 0x204B5242, 0x20202020
    .WORD 0x20202020, 0x43203B20, 0x206C6C61, 0x6E72656B, 0x203A6C65, 0x6B726273, 0x7A697328, 0x200A2965
    .WORD 0x0A202020, 0x20202020, 0x6843203B, 0x206B6365, 0x73206669, 0x206B7262, 0x6C696166, 0x28206465
    .WORD 0x75746572, 0x20736E72, 0x6F20312D, 0x20302072, 0x65206E6F, 0x726F7272, 0x20200A29, 0x4D432020
    .WORD 0x31522050, 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x6944203B, 0x62732064, 0x72206B72
    .WORD 0x72757465, 0x2030206E, 0x6E20726F, 0x74616765, 0x3F657669, 0x2020200A, 0x544C4220, 0x6C616D20
    .WORD 0x5F636F6C, 0x6F727265, 0x20202072, 0x3B202020, 0x20664920, 0x6F727265, 0x72202C72, 0x72757465
    .WORD 0x554E206E, 0x200A4C4C, 0x0A202020, 0x20202020, 0x7453203B, 0x35207065, 0x6273203A, 0x73206B72
    .WORD 0x65636375, 0x64656465, 0x6577202C, 0x76616820, 0x656E2065, 0x656D2077, 0x79726F6D, 0x20746120
    .WORD 0x72646461, 0x20737365, 0x52206E69, 0x20200A31, 0x203B2020, 0x20776F4E, 0x6E206577, 0x20646565
    .WORD 0x61206F74, 0x74206464, 0x20736968, 0x2077656E, 0x636F6C62, 0x6F74206B, 0x72756F20, 0x62617420
    .WORD 0x200A656C, 0x0A202020, 0x20202020, 0x6946203B, 0x6120646E, 0x6D65206E, 0x20797470, 0x746F6C73
    .WORD 0x206E6920, 0x20656874, 0x636F6C62, 0x6174206B, 0x0A656C62, 0x20202020, 0x5220494C, 0x20302034
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x72617453, 0x74612074, 0x72696620, 0x62207473
    .WORD 0x6B636F6C, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x6464615F, 0x20200A3A, 0x203B2020, 0x63656843
    .WORD 0x6669206B, 0x27657720, 0x73206576, 0x63726165, 0x20646568, 0x206C6C61, 0x636F6C62, 0x200A736B
    .WORD 0x43202020, 0x5220504D, 0x414D2034, 0x4C425F58, 0x534B434F, 0x20202020, 0x20200A20, 0x47422020
    .WORD 0x616D2045, 0x636F6C6C, 0x7272655F, 0x2020726F, 0x20202020, 0x6F4E203B, 0x706D6520, 0x73207974
    .WORD 0x21746F6C, 0x68732820, 0x646C756F, 0x2074276E, 0x70706168, 0x0A296E65, 0x20202020, 0x2020200A
    .WORD 0x47203B20, 0x64207465, 0x72637365, 0x6F747069, 0x64612072, 0x73657264, 0x20200A73, 0x494C2020
    .WORD 0x20325220, 0x636F6C62, 0x61745F6B, 0x0A656C62, 0x20202020, 0x5220494C, 0x4C422033, 0x5F4B434F
    .WORD 0x43534544, 0x2020200A, 0x4C554D20, 0x20335220, 0x52203452, 0x20200A33, 0x44412020, 0x32522044
    .WORD 0x20325220, 0x20203352, 0x20202020, 0x203B2020, 0x6F6C6226, 0x695B6B63, 0x7865646E, 0x0A5D3452
    .WORD 0x20202020, 0x2020200A, 0x43203B20, 0x6B636568, 0x20666920, 0x73696874, 0x6F6C7320, 0x73692074
    .WORD 0x65726620, 0x55282065, 0x20444553, 0x67616C66, 0x30203D20, 0x20200A29, 0x444C2020, 0x33522057
    .WORD 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4553555F, 0x200A5D44, 0x43202020, 0x5220504D, 0x0A302033
    .WORD 0x20202020, 0x20514542, 0x6C6C616D, 0x615F636F, 0x665F6464, 0x646E756F, 0x203B2020, 0x6E756F46
    .WORD 0x6E612064, 0x706D6520, 0x73207974, 0x21746F6C, 0x2020200A, 0x20200A20, 0x203B2020, 0x746F6C53
    .WORD 0x20736920, 0x64657375, 0x7274202C, 0x656E2079, 0x6F207478, 0x200A656E, 0x41202020, 0x52204444
    .WORD 0x34522034, 0x200A3120, 0x42202020, 0x6C616D20, 0x5F636F6C, 0x0A646461, 0x6C616D0A, 0x5F636F6C
    .WORD 0x5F646461, 0x6E756F66, 0x200A3A64, 0x3B202020, 0x20655720, 0x6E756F66, 0x6E612064, 0x706D6520
    .WORD 0x73207974, 0x20746F6C, 0x52207461, 0x20200A32, 0x203B2020, 0x726F7453, 0x68742065, 0x656E2065
    .WORD 0x6C622077, 0x276B636F, 0x6E692073, 0x6D726F66, 0x6F697461, 0x20200A6E, 0x200A2020, 0x3B202020
    .WORD 0x6F745320, 0x74206572, 0x61206568, 0x65726464, 0x28207373, 0x66203152, 0x206D6F72, 0x6B726273
    .WORD 0x20200A29, 0x54532020, 0x31522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4444415F, 0x20205D52
    .WORD 0x62203B20, 0x6B636F6C, 0x6464612E, 0x73736572, 0x61203D20, 0x65726464, 0x66207373, 0x206D6F72
    .WORD 0x6B726273, 0x2020200A, 0x20200A20, 0x203B2020, 0x726F7453, 0x68742065, 0x69732065, 0x2820657A
    .WORD 0x3D203552, 0x696C6120, 0x64656E67, 0x7A697320, 0x200A2965, 0x53202020, 0x52205754, 0x525B2035
    .WORD 0x202B2032, 0x434F4C42, 0x49535F4B, 0x205D455A, 0x203B2020, 0x636F6C62, 0x69732E6B, 0x3D20657A
    .WORD 0x7A697320, 0x20200A65, 0x200A2020, 0x3B202020, 0x72614D20, 0x7361206B, 0x65737520, 0x55282064
    .WORD 0x20444553, 0x2931203D, 0x2020200A, 0x20494C20, 0x31203352, 0x2020200A, 0x57545320, 0x20335220
    .WORD 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x44455355, 0x2020205D, 0x6C62203B, 0x2E6B636F, 0x64657375
    .WORD 0x31203D20, 0x2020200A, 0x20200A20, 0x203B2020, 0x61203152, 0x6165726C, 0x68207964, 0x74207361
    .WORD 0x61206568, 0x65726464, 0x66207373, 0x206D6F72, 0x6B726273, 0x6F73202C, 0x73756A20, 0x65722074
    .WORD 0x6E727574, 0x0A746920, 0x20202020, 0x616D2042, 0x636F6C6C, 0x6E6F645F, 0x6D0A0A65, 0x6F6C6C61
    .WORD 0x72655F63, 0x3A726F72, 0x2020200A, 0x53203B20, 0x74656D6F, 0x676E6968, 0x6E657720, 0x72772074
    .WORD 0x20676E6F, 0x6572202D, 0x6E727574, 0x4C554E20, 0x3028204C, 0x20200A29, 0x494C2020, 0x20315220
    .WORD 0x6D0A0A30, 0x6F6C6C61, 0x6F645F63, 0x0A3A656E, 0x20202020, 0x20504F50, 0x2020524C, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x74736552, 0x2065726F, 0x75746572, 0x61206E72, 0x65726464
    .WORD 0x200A7373, 0x52202020, 0x20205445, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x52203B20
    .WORD 0x72757465, 0x6F74206E, 0x6C616320, 0x2072656C, 0x68746977, 0x20315220, 0x6F70203D, 0x65746E69
    .WORD 0x726F2072, 0x4C554E20, 0x3B0A0A4C, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x65726620
    .WORD 0x74702865, 0x3B0A2972, 0x46203B0A, 0x73656572, 0x65727020, 0x756F6976, 0x20796C73, 0x6F6C6C61
    .WORD 0x65746163, 0x656D2064, 0x79726F6D, 0x0A3B0A2E, 0x6F48203B, 0x74692077, 0x726F7720, 0x0A3A736B
    .WORD 0x2E31203B, 0x6E694620, 0x68742064, 0x6C622065, 0x206B636F, 0x63736564, 0x74706972, 0x6620726F
    .WORD 0x7420726F, 0x20736968, 0x72646461, 0x0A737365, 0x2E32203B, 0x72614D20, 0x7469206B, 0x20736120
    .WORD 0x65657266, 0x53552820, 0x3D204445, 0x0A293020, 0x2E33203B, 0x6D654D20, 0x2079726F, 0x6E207369
    .WORD 0x6120776F, 0x6C696176, 0x656C6261, 0x726F6620, 0x74756620, 0x20657275, 0x6C6C616D, 0x6320636F
    .WORD 0x736C6C61, 0x3B0A3B0A, 0x746F4E20, 0x54203A65, 0x20736968, 0x706D6973, 0x7620656C, 0x69737265
    .WORD 0x64206E6F, 0x2073656F, 0x20544F4E, 0x6C616F63, 0x65637365, 0x6A646120, 0x6E656361, 0x72662074
    .WORD 0x62206565, 0x6B636F6C, 0x3B0A2173, 0x20202020, 0x53202020, 0x7266206F, 0x656D6761, 0x7461746E
    .WORD 0x206E6F69, 0x206E6163, 0x7563636F, 0x766F2072, 0x74207265, 0x2E656D69, 0x3B0A3B0A, 0x706E4920
    .WORD 0x203A7475, 0x20315220, 0x6F70203D, 0x65746E69, 0x6F742072, 0x6D656D20, 0x2079726F, 0x66206F74
    .WORD 0x20656572, 0x6F726628, 0x616D206D, 0x636F6C6C, 0x203B0A29, 0x7074754F, 0x203A7475, 0x68746F4E
    .WORD 0x0A676E69, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x65657266, 0x20200A3A, 0x203B2020
    .WORD 0x65766153, 0x67657220, 0x65747369, 0x200A7372, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020
    .WORD 0x20202020, 0x7453203B, 0x31207065, 0x6843203A, 0x206B6365, 0x70206669, 0x746E696F, 0x69207265
    .WORD 0x554E2073, 0x200A4C4C, 0x43202020, 0x5220504D, 0x20302031, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x49203B20, 0x31522073, 0x203D3D20, 0x200A3F30, 0x42202020, 0x66205145, 0x5F656572, 0x656E6F64
    .WORD 0x20202020, 0x20202020, 0x49203B20, 0x554E2066, 0x202C4C4C, 0x68746F6E, 0x20676E69, 0x66206F74
    .WORD 0x2C656572, 0x73756A20, 0x65722074, 0x6E727574, 0x2020200A, 0x20200A20, 0x203B2020, 0x70657453
    .WORD 0x203A3220, 0x72616553, 0x74206863, 0x62206568, 0x6B636F6C, 0x62617420, 0x6620656C, 0x7420726F
    .WORD 0x20736968, 0x72646461, 0x0A737365, 0x20202020, 0x5220494C, 0x20302034, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x72617453, 0x74612074, 0x72696620, 0x62207473, 0x6B636F6C, 0x2020200A
    .WORD 0x72660A20, 0x6C5F6565, 0x3A706F6F, 0x2020200A, 0x43203B20, 0x6B636568, 0x20666920, 0x76276577
    .WORD 0x65732065, 0x68637261, 0x61206465, 0x62206C6C, 0x6B636F6C, 0x20200A73, 0x4D432020, 0x34522050
    .WORD 0x58414D20, 0x4F4C425F, 0x0A534B43, 0x20202020, 0x20454742, 0x65657266, 0x6E6F645F, 0x20202065
    .WORD 0x20202020, 0x203B2020, 0x20746F4E, 0x6E756F66, 0x202D2064, 0x6F6E6769, 0x28206572, 0x6C756F63
    .WORD 0x65622064, 0x766E6920, 0x64696C61, 0x696F7020, 0x7265746E, 0x20200A29, 0x200A2020, 0x3B202020
    .WORD 0x74654720, 0x73656420, 0x70697263, 0x20726F74, 0x72646461, 0x0A737365, 0x20202020, 0x5220494C
    .WORD 0x6C622032, 0x5F6B636F, 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x434F4C42, 0x45445F4B
    .WORD 0x20204353, 0x20202020, 0x656C203B, 0x6874676E, 0x20666F20, 0x20656E6F, 0x636F6C62, 0x6564206B
    .WORD 0x69726373, 0x726F7470, 0x2020200A, 0x4C554D20, 0x20335220, 0x52203452, 0x20202033, 0x20202020
    .WORD 0x3B202020, 0x20347220, 0x636F6C62, 0x6469206B, 0x20200A78, 0x44412020, 0x32522044, 0x20325220
    .WORD 0x20203352, 0x20202020, 0x20202020, 0x3252203B, 0x26203D20, 0x636F6C62, 0x5D695B6B, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x63656843, 0x6669206B, 0x69687420, 0x6C622073, 0x276B636F, 0x64612073
    .WORD 0x73657264, 0x616D2073, 0x65686374, 0x68742073, 0x6F702065, 0x65746E69, 0x20200A72, 0x444C2020
    .WORD 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4444415F, 0x20205D52, 0x3352203B, 0x20203D20
    .WORD 0x6F6C6226, 0x695B6B63, 0x6C622E5D, 0x206B636F, 0x72646461, 0x0A737365, 0x20202020, 0x20504D43
    .WORD 0x52203352, 0x20202031, 0x20202020, 0x20202020, 0x203B2020, 0x74207349, 0x20736968, 0x2072756F
    .WORD 0x636F6C62, 0x200A3F6B, 0x42202020, 0x66205145, 0x5F656572, 0x6E756F66, 0x20202064, 0x20202020
    .WORD 0x59203B20, 0x202C7365, 0x66206577, 0x646E756F, 0x21746920, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x20746F4E, 0x73696874, 0x6F6C6220, 0x202C6B63, 0x20797274, 0x7478656E, 0x2020200A, 0x44444120
    .WORD 0x20345220, 0x31203452, 0x2020200A, 0x66204220, 0x5F656572, 0x706F6F6C, 0x72660A0A, 0x665F6565
    .WORD 0x646E756F, 0x20200A3A, 0x203B2020, 0x70657453, 0x203A3320, 0x66206557, 0x646E756F, 0x65687420
    .WORD 0x6F6C6220, 0x64206B63, 0x72637365, 0x6F747069, 0x74612072, 0x0A325220, 0x20202020, 0x614D203B
    .WORD 0x69206B72, 0x73612074, 0x65726620, 0x6F732065, 0x6C616D20, 0x20636F6C, 0x206E6163, 0x20657375
    .WORD 0x61207469, 0x6E696167, 0x2020200A, 0x20200A20, 0x494C2020, 0x20335220, 0x20202030, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x3352203B, 0x30203D20, 0x72662820, 0x0A296565, 0x20202020, 0x20575453
    .WORD 0x5B203352, 0x2B203252, 0x4F4C4220, 0x555F4B43, 0x5D444553, 0x203B2020, 0x6F6C6226, 0x695B6B63
    .WORD 0x73752E5D, 0x3D206465, 0x200A3020, 0x0A202020, 0x20202020, 0x4F4E203B, 0x203A4554, 0x64206557
    .WORD 0x4F4E206F, 0x6C632054, 0x20726165, 0x20656874, 0x72646461, 0x20737365, 0x7320726F, 0x0A657A69
    .WORD 0x20202020, 0x6854203B, 0x73207965, 0x20796174, 0x74206E69, 0x74206568, 0x656C6261, 0x646E6120
    .WORD 0x6C697720, 0x6562206C, 0x65766F20, 0x69727772, 0x6E657474, 0x65687720, 0x6572206E, 0x64657375
    .WORD 0x2020200A, 0x72660A20, 0x645F6565, 0x3A656E6F, 0x2020200A, 0x43203B20, 0x6E61656C, 0x20707520
    .WORD 0x20646E61, 0x75746572, 0x200A6E72, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6C616D20, 0x5F636F6C, 0x74696E69, 0x49202D20
    .WORD 0x6974696E, 0x7A696C61, 0x68742065, 0x656D2065, 0x79726F6D, 0x6C6C6120, 0x7461636F, 0x3B0A726F
    .WORD 0x43203B0A, 0x7261656C, 0x68742073, 0x6E652065, 0x65726974, 0x6F6C6220, 0x74206B63, 0x656C6261
    .WORD 0x206F7320, 0x206C6C61, 0x636F6C62, 0x6120736B, 0x6D206572, 0x656B7261, 0x73612064, 0x65726620
    .WORD 0x203B0A65, 0x756F6853, 0x6220646C, 0x61632065, 0x64656C6C, 0x636E6F20, 0x74612065, 0x73797320
    .WORD 0x206D6574, 0x72617473, 0x20707574, 0x6F666562, 0x75206572, 0x676E6973, 0x6C616D20, 0x0A636F6C
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6C6C616D, 0x695F636F, 0x3A74696E, 0x2020200A
    .WORD 0x53203B20, 0x20657661, 0x69676572, 0x72657473, 0x20200A73, 0x55502020, 0x4C204853, 0x20202052
    .WORD 0x2020200A, 0x53203B20, 0x20706574, 0x43203A31, 0x7261656C, 0x65687420, 0x746E6520, 0x20657269
    .WORD 0x636F6C62, 0x6174206B, 0x0A656C62, 0x20202020, 0x6553203B, 0x6C612074, 0x7962206C, 0x20736574
    .WORD 0x62206E69, 0x6B636F6C, 0x6261745F, 0x7420656C, 0x0A30206F, 0x20202020, 0x5220494C, 0x6C622031
    .WORD 0x5F6B636F, 0x6C626174, 0x20202065, 0x203B2020, 0x3D203152, 0x61747320, 0x61207472, 0x65726464
    .WORD 0x6F207373, 0x61742066, 0x0A656C62, 0x20202020, 0x5220494C, 0x414D2033, 0x4C425F58, 0x534B434F
    .WORD 0x42202A20, 0x4B434F4C, 0x5345445F, 0x3B202043, 0x20335220, 0x6F74203D, 0x206C6174, 0x65747962
    .WORD 0x6F742073, 0x656C6320, 0x200A7261, 0x0A202020, 0x6C6C616D, 0x695F636F, 0x5F74696E, 0x706F6F6C
    .WORD 0x20200A3A, 0x4D432020, 0x33522050, 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x6148203B
    .WORD 0x77206576, 0x6C632065, 0x65726165, 0x6C612064, 0x7962206C, 0x3F736574, 0x2020200A, 0x51454220
    .WORD 0x6C616D20, 0x5F636F6C, 0x74696E69, 0x6E6F645F, 0x3B202065, 0x73655920, 0x6577202C, 0x20657227
    .WORD 0x656E6F64, 0x2020200A, 0x20200A20, 0x494C2020, 0x20325220, 0x20202030, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x3252203B, 0x30203D20, 0x61762820, 0x2065756C, 0x77206F74, 0x65746972, 0x20200A29
    .WORD 0x54532020, 0x32522042, 0x31525B20, 0x2020205D, 0x20202020, 0x20202020, 0x7453203B, 0x2065726F
    .WORD 0x74612030, 0x72756320, 0x746E6572, 0x64646120, 0x73736572, 0x2020200A, 0x44444120, 0x20315220
    .WORD 0x31203152, 0x20202020, 0x20202020, 0x3B202020, 0x766F4D20, 0x6F742065, 0x78656E20, 0x79622074
    .WORD 0x200A6574, 0x53202020, 0x52204255, 0x33522033, 0x20203120, 0x20202020, 0x20202020, 0x44203B20
    .WORD 0x65726365, 0x746E656D, 0x74796220, 0x6F632065, 0x65746E75, 0x20200A72, 0x20422020, 0x6C6C616D
    .WORD 0x695F636F, 0x5F74696E, 0x706F6F6C, 0x20202020, 0x6F43203B, 0x6E69746E, 0x200A6575, 0x0A202020
    .WORD 0x6C6C616D, 0x695F636F, 0x5F74696E, 0x656E6F64, 0x20200A3A, 0x203B2020, 0x61656C43, 0x7075206E
    .WORD 0x646E6120, 0x74657220, 0x0A6E7275, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x49203B0A, 0x5245544E, 0x204C414E, 0x504C4548
    .WORD 0x0A535245, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7469203B, 0x635F616F, 0x2065726F, 0x6E55202D
    .WORD 0x72657669, 0x206C6173, 0x65746E69, 0x20726567, 0x73206F74, 0x6E697274, 0x6F632067, 0x7265766E
    .WORD 0x0A726574, 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566
    .WORD 0x3252203B, 0x69203D20, 0x6765746E, 0x74207265, 0x6F63206F, 0x7265766E, 0x203B0A74, 0x3D203352
    .WORD 0x73616220, 0x32282065, 0x3031202C, 0x726F202C, 0x29363120, 0x52203B0A, 0x203D2034, 0x6E676973
    .WORD 0x616C6620, 0x31282067, 0x73203D20, 0x656E6769, 0x30202C64, 0x75203D20, 0x6769736E, 0x2964656E
    .WORD 0x52203B0A, 0x203D2035, 0x706D6574, 0x66756220, 0x20726566, 0x657A6973, 0x65656E20, 0x0A646564
    .WORD 0x203B0A3B, 0x75746552, 0x3A736E72, 0x20203B0A, 0x20315220, 0x726F203D, 0x6E696769, 0x64206C61
    .WORD 0x69747365, 0x6974616E, 0x70206E6F, 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x74690A2D, 0x635F616F, 0x3A65726F, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A
    .WORD 0x53555020, 0x31522048, 0x20200A30, 0x55502020, 0x52204853, 0x200A3131, 0x50202020, 0x20485355
    .WORD 0x0A323152, 0x2020200A, 0x564F4D20, 0x38522020, 0x31522020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x65766153, 0x73656420, 0x616E6974, 0x6E6F6974, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x52202056
    .WORD 0x52202039, 0x20202032, 0x20202020, 0x3B202020, 0x726F5720, 0x676E696B, 0x6C617620, 0x200A6575
    .WORD 0x4D202020, 0x2020564F, 0x20313152, 0x20203352, 0x20202020, 0x20202020, 0x6142203B, 0x200A6573
    .WORD 0x4D202020, 0x2020564F, 0x20323152, 0x20203452, 0x20202020, 0x20202020, 0x6953203B, 0x66206E67
    .WORD 0x0A67616C, 0x20202020, 0x564F4D3B, 0x31522020, 0x35522030, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x706D6554, 0x66756220, 0x20726566, 0x657A6973, 0x2020200A, 0x20200A20, 0x203B2020, 0x6F6C6C41
    .WORD 0x65746163, 0x6D657420, 0x75622070, 0x72656666, 0x69732820, 0x7020657A, 0x65737361, 0x6E692064
    .WORD 0x29355220, 0x2020200A, 0x42555320, 0x50532020, 0x20505320, 0x200A3552, 0x4D202020, 0x2020564F
    .WORD 0x20303152, 0x20203152, 0x20202020, 0x20202020, 0x654B203B, 0x6F207065, 0x69676972, 0x206C616E
    .WORD 0x6E696F70, 0x0A726574, 0x20202020, 0x20564F4D, 0x20365220, 0x20505320, 0x20202020, 0x20202020
    .WORD 0x54203B20, 0x20706D65, 0x66667562, 0x70207265, 0x746E696F, 0x200A7265, 0x70202020, 0x20687375
    .WORD 0x20203552, 0x20202020, 0x20202020, 0x20202020, 0x6173203B, 0x52206576, 0x6F662035, 0x72662072
    .WORD 0x20656D61, 0x7661656C, 0x20200A65, 0x4F4D2020, 0x52202056, 0x52202037, 0x20202036, 0x20202020
    .WORD 0x3B202020, 0x76615320, 0x74732065, 0x20747261, 0x7420666F, 0x20706D65, 0x66667562, 0x200A7265
    .WORD 0x0A202020, 0x20202020, 0x6843203B, 0x206B6365, 0x20726F66, 0x6E676973, 0x66692820, 0x67697320
    .WORD 0x2064656E, 0x20646E61, 0x6167656E, 0x65766974, 0x20200A29, 0x4D432020, 0x52202050, 0x31203231
    .WORD 0x2020200A, 0x454E4220, 0x74692020, 0x635F616F, 0x5F65726F, 0x69736E75, 0x64656E67, 0x2020200A
    .WORD 0x20200A20, 0x4D432020, 0x52202050, 0x0A302039, 0x20202020, 0x20454742, 0x6F746920, 0x6F635F61
    .WORD 0x755F6572, 0x6769736E, 0x0A64656E, 0x20202020, 0x2020200A, 0x4E203B20, 0x74616765, 0x20657669
    .WORD 0x626D756E, 0x2D207265, 0x64646120, 0x6E696D20, 0x73207375, 0x0A6E6769, 0x20202020, 0x2020494C
    .WORD 0x20325220, 0x20203534, 0x3B202020, 0x0A272D27, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B
    .WORD 0x2020200A, 0x44444120, 0x38522020, 0x20385220, 0x20200A31, 0x4F4E2020, 0x52202054, 0x39522039
    .WORD 0x2020200A, 0x44444120, 0x39522020, 0x20395220, 0x20200A31, 0x4E3B2020, 0x20204745, 0x20203952
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x614D203B, 0x7020656B, 0x7469736F, 0x0A657669, 0x20202020
    .WORD 0x6F74690A, 0x6F635F61, 0x755F6572, 0x6769736E, 0x3A64656E, 0x2020200A, 0x53203B20, 0x69636570
    .WORD 0x63206C61, 0x3A657361, 0x72657A20, 0x20200A6F, 0x4D432020, 0x52202050, 0x0A302039, 0x20202020
    .WORD 0x20454E42, 0x6F746920, 0x6F635F61, 0x635F6572, 0x65766E6F, 0x200A7472, 0x0A202020, 0x20202020
    .WORD 0x2020494C, 0x20325220, 0x20203834, 0x203B2020, 0x0A273027, 0x20202020, 0x20425453, 0x20325220
    .WORD 0x5D38525B, 0x2020200A, 0x44444120, 0x38522020, 0x20385220, 0x20200A31, 0x494C2020, 0x52202020
    .WORD 0x0A302032, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B, 0x2020200A, 0x20204220, 0x74692020
    .WORD 0x635F616F, 0x5F65726F, 0x696E6966, 0x200A6873, 0x0A202020, 0x616F7469, 0x726F635F, 0x6F635F65
    .WORD 0x7265766E, 0x200A3A74, 0x4C202020, 0x20202049, 0x30203452, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6944203B, 0x20746967, 0x6E756F63, 0x0A726574, 0x20202020, 0x6F74690A, 0x6F635F61, 0x645F6572
    .WORD 0x6F6C7669, 0x0A3A706F, 0x20202020, 0x20564F4D, 0x20355220, 0x200A3952, 0x44202020, 0x20205649
    .WORD 0x52203652, 0x31522035, 0x20202031, 0x20202020, 0x3652203B, 0x71203D20, 0x69746F75, 0x2C746E65
    .WORD 0x20395220, 0x6572203D, 0x6E69616D, 0x0A726564, 0x20202020, 0x20444F4D, 0x20375220, 0x52203952
    .WORD 0x20203131, 0x20202020, 0x52203B20, 0x203D2037, 0x616D6572, 0x65646E69, 0x20200A72, 0x200A2020
    .WORD 0x3B202020, 0x6E6F4320, 0x74726576, 0x67696420, 0x74207469, 0x5341206F, 0x20494943, 0x65736162
    .WORD 0x6E6F2064, 0x73616220, 0x20200A65, 0x4D432020, 0x52202050, 0x31203131, 0x20200A36, 0x45422020
    .WORD 0x69202051, 0x5F616F74, 0x65726F63, 0x7865685F, 0x6769645F, 0x200A7469, 0x0A202020, 0x20202020
    .WORD 0x6142203B, 0x32206573, 0x20726F20, 0x203A3031, 0x69676964, 0x2D302074, 0x20200A39, 0x44412020
    .WORD 0x52202044, 0x37522037, 0x20383420, 0x20202020, 0x3B202020, 0x27302720, 0x64202B20, 0x74696769
    .WORD 0x2020200A, 0x20204220, 0x74692020, 0x635F616F, 0x5F65726F, 0x726F7473, 0x20200A65, 0x690A2020
    .WORD 0x5F616F74, 0x65726F63, 0x7865685F, 0x6769645F, 0x0A3A7469, 0x20202020, 0x6142203B, 0x31206573
    .WORD 0x64203A36, 0x74696769, 0x312D3020, 0x20200A35, 0x4D432020, 0x52202050, 0x0A392037, 0x20202020
    .WORD 0x20544742, 0x6F746920, 0x6F635F61, 0x685F6572, 0x6C5F7865, 0x65747465, 0x20200A72, 0x44412020
    .WORD 0x52202044, 0x37522037, 0x20383420, 0x20202020, 0x3B202020, 0x27302720, 0x64202B20, 0x74696769
    .WORD 0x2020200A, 0x20204220, 0x74692020, 0x635F616F, 0x5F65726F, 0x726F7473, 0x20200A65, 0x690A2020
    .WORD 0x5F616F74, 0x65726F63, 0x7865685F, 0x74656C5F, 0x3A726574, 0x2020200A, 0x42555320, 0x37522020
    .WORD 0x20375220, 0x200A3031, 0x41202020, 0x20204444, 0x52203752, 0x35362037, 0x20202020, 0x20202020
    .WORD 0x4127203B, 0x202B2027, 0x67696428, 0x312D7469, 0x200A2930, 0x0A202020, 0x616F7469, 0x726F635F
    .WORD 0x74735F65, 0x3A65726F, 0x2020200A, 0x42545320, 0x37522020, 0x36525B20, 0x2020205D, 0x20202020
    .WORD 0x203B2020, 0x726F7453, 0x6E692065, 0x6D657420, 0x75622070, 0x72656666, 0x2020200A, 0x44444120
    .WORD 0x36522020, 0x20365220, 0x20200A31, 0x44412020, 0x52202044, 0x34522034, 0x20203120, 0x20202020
    .WORD 0x3B202020, 0x636E4920, 0x656D6572, 0x6420746E, 0x74696769, 0x756F6320, 0x200A746E, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x20395220, 0x20203552, 0x20202020, 0x20202020, 0x51203B20, 0x69746F75
    .WORD 0x20746E65, 0x6F636562, 0x2073656D, 0x2077656E, 0x756C6176, 0x20200A65, 0x4D432020, 0x52202050
    .WORD 0x0A302039, 0x20202020, 0x20454E42, 0x6F746920, 0x6F635F61, 0x645F6572, 0x6F6C7669, 0x200A706F
    .WORD 0x0A202020, 0x20202020, 0x6F50203B, 0x20746E69, 0x6C206F74, 0x20747361, 0x69676964, 0x20200A74
    .WORD 0x55532020, 0x52202042, 0x36522036, 0x200A3120, 0x0A202020, 0x616F7469, 0x726F635F, 0x6F635F65
    .WORD 0x0A3A7970, 0x20202020, 0x20504D43, 0x20345220, 0x20200A30, 0x45422020, 0x69202051, 0x5F616F74
    .WORD 0x65726F63, 0x6E6F645F, 0x20200A65, 0x200A2020, 0x4C202020, 0x20204244, 0x5B203252, 0x205D3652
    .WORD 0x20202020, 0x20202020, 0x6547203B, 0x69642074, 0x20746967, 0x6D6F7266, 0x6D657420, 0x72282070
    .WORD 0x72657665, 0x6F206573, 0x72656472, 0x20200A29, 0x54532020, 0x52202042, 0x525B2032, 0x20205D38
    .WORD 0x20202020, 0x3B202020, 0x6F745320, 0x69206572, 0x6564206E, 0x6E697473, 0x6F697461, 0x20200A6E
    .WORD 0x44412020, 0x52202044, 0x38522038, 0x200A3120, 0x53202020, 0x20204255, 0x52203652, 0x0A312036
    .WORD 0x20202020, 0x20425553, 0x20345220, 0x31203452, 0x2020200A, 0x20204220, 0x74692020, 0x635F616F
    .WORD 0x5F65726F, 0x79706F63, 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x656E6F64, 0x20200A3A
    .WORD 0x494C2020, 0x52202020, 0x0A302032, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B, 0x20202020
    .WORD 0x20202020, 0x4E203B20, 0x206C6C75, 0x6D726574, 0x74616E69, 0x20200A65, 0x690A2020, 0x5F616F74
    .WORD 0x65726F63, 0x6E69665F, 0x3A687369, 0x2020200A, 0x504F5020, 0x35522020, 0x2020200A, 0x43203B20
    .WORD 0x6E61656C, 0x20707520, 0x706D6574, 0x66756220, 0x0A726566, 0x20202020, 0x20444441, 0x20505320
    .WORD 0x52205053, 0x20200A35, 0x200A2020, 0x3B202020, 0x74655220, 0x206E7275, 0x6769726F, 0x6C616E69
    .WORD 0x696F7020, 0x7265746E, 0x2020200A, 0x564F4D20, 0x31522020, 0x30315220, 0x2020200A, 0x20200A20
    .WORD 0x4F502020, 0x52202050, 0x200A3231, 0x50202020, 0x2020504F, 0x0A313152, 0x20202020, 0x20504F50
    .WORD 0x30315220, 0x2020200A, 0x504F5020, 0x39522020, 0x2020200A, 0x504F5020, 0x38522020, 0x2020200A
    .WORD 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x20636564, 0x6544202D, 0x616D6963
    .WORD 0x6F63206C, 0x7265766E, 0x6E6F6973, 0x61727720, 0x72657070, 0x3B0A3B0A, 0x20315220, 0x6564203D
    .WORD 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032, 0x6E676973, 0x69206465
    .WORD 0x6765746E, 0x3B0A7265, 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20, 0x69676972, 0x206C616E
    .WORD 0x66667562, 0x70207265, 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x74690A2D, 0x645F616F, 0x0A3A6365, 0x20202020, 0x48535550, 0x0A524C20
    .WORD 0x20202020, 0x2020200A, 0x4D203B20, 0x31207861, 0x69642031, 0x73746967, 0x73202B20, 0x206E6769
    .WORD 0x756E202B, 0x3D206C6C, 0x20333120, 0x65747962, 0x20200A73, 0x494C2020, 0x52202020, 0x30312033
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x73614220, 0x30312065, 0x2020200A, 0x20494C20, 0x34522020
    .WORD 0x20203120, 0x20202020, 0x20202020, 0x203B2020, 0x6E676953, 0x200A6465, 0x4C202020, 0x20202049
    .WORD 0x31203552, 0x20202033, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072
    .WORD 0x200A657A, 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020
    .WORD 0x2020504F, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920, 0x65685F61, 0x202D2078, 0x61786548, 0x69636564
    .WORD 0x206C616D, 0x766E6F63, 0x69737265, 0x77206E6F, 0x70706172, 0x3B0A7265, 0x52203B0A, 0x203D2031
    .WORD 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x3B0A7265, 0x20325220, 0x6E75203D, 0x6E676973
    .WORD 0x69206465, 0x6765746E, 0x3B0A7265, 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20, 0x69676972
    .WORD 0x206C616E, 0x66667562, 0x70207265, 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x74690A2D, 0x685F616F, 0x0A3A7865, 0x20202020, 0x48535550
    .WORD 0x0A524C20, 0x20202020, 0x2020200A, 0x4D203B20, 0x38207861, 0x67696420, 0x20737469, 0x756E202B
    .WORD 0x3D206C6C, 0x62203920, 0x73657479, 0x2020200A, 0x20494C20, 0x33522020, 0x20363120, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x65736142, 0x0A363120, 0x20202020, 0x2020494C, 0x20345220, 0x20202030
    .WORD 0x20202020, 0x20202020, 0x55203B20, 0x6769736E, 0x2064656E, 0x6F687328, 0x72207377, 0x62207761
    .WORD 0x29737469, 0x2020200A, 0x20494C20, 0x35522020, 0x20203920, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x706D6554, 0x66756220, 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F
    .WORD 0x0A65726F, 0x20202020, 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x3B0A0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469
    .WORD 0x74636F5F, 0x4F202D20, 0x6C617463, 0x6E6F6320, 0x73726576, 0x206E6F69, 0x70617277, 0x0A726570
    .WORD 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566, 0x3252203B
    .WORD 0x75203D20, 0x6769736E, 0x2064656E, 0x65746E69, 0x0A726567, 0x6552203B, 0x6E727574, 0x52203A73
    .WORD 0x203D2031, 0x6769726F, 0x6C616E69, 0x66756220, 0x20726566, 0x6E696F70, 0x0A726574, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x3A74636F
    .WORD 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x20200A20, 0x203B2020, 0x2078614D, 0x64203231
    .WORD 0x74696769, 0x202B2073, 0x6C6C756E, 0x31203D20, 0x79622033, 0x0A736574, 0x20202020, 0x2020494C
    .WORD 0x20335220, 0x20202038, 0x20202020, 0x20202020, 0x42203B20, 0x20657361, 0x20200A38, 0x494C2020
    .WORD 0x52202020, 0x20302034, 0x20202020, 0x20202020, 0x3B202020, 0x736E5520, 0x656E6769, 0x73282064
    .WORD 0x73776F68, 0x77617220, 0x74696220, 0x200A2973, 0x4C202020, 0x20202049, 0x31203552, 0x20202033
    .WORD 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072, 0x200A657A, 0x43202020
    .WORD 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020, 0x2020504F, 0x200A524C
    .WORD 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x6F746920, 0x69625F61, 0x202D206E, 0x616E6942, 0x63207972, 0x65766E6F, 0x6F697372
    .WORD 0x7277206E, 0x65707061, 0x0A3B0A72, 0x3152203B, 0x64203D20, 0x69747365, 0x6974616E, 0x62206E6F
    .WORD 0x65666675, 0x203B0A72, 0x3D203252, 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72
    .WORD 0x75746552, 0x3A736E72, 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072
    .WORD 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6F74690A, 0x69625F61, 0x200A3A6E, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020, 0x20202020
    .WORD 0x614D203B, 0x32332078, 0x74696220, 0x202B2073, 0x6C6C756E, 0x33203D20, 0x79622033, 0x0A736574
    .WORD 0x20202020, 0x2020494C, 0x20335220, 0x20202032, 0x20202020, 0x20202020, 0x42203B20, 0x20657361
    .WORD 0x20200A32, 0x494C2020, 0x52202020, 0x20302034, 0x20202020, 0x20202020, 0x3B202020, 0x736E5520
    .WORD 0x656E6769, 0x73282064, 0x73776F68, 0x77617220, 0x74696220, 0x200A2973, 0x4C202020, 0x20202049
    .WORD 0x33203552, 0x20202033, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072
    .WORD 0x200A657A, 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020
    .WORD 0x2020504F, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920, 0x69735F61, 0x64656E67, 0x7865685F, 0x53202D20
    .WORD 0x656E6769, 0x65682064, 0x65646178, 0x616D6963, 0x7277206C, 0x65707061, 0x0A3B0A72, 0x3152203B
    .WORD 0x64203D20, 0x69747365, 0x6974616E, 0x62206E6F, 0x65666675, 0x203B0A72, 0x3D203252, 0x67697320
    .WORD 0x2064656E, 0x65746E69, 0x0A726567, 0x6552203B, 0x6E727574, 0x52203A73, 0x203D2031, 0x6769726F
    .WORD 0x6C616E69, 0x66756220, 0x20726566, 0x6E696F70, 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x6E676973, 0x685F6465, 0x0A3A7865
    .WORD 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x2020200A, 0x4D203B20, 0x38207861, 0x67696420
    .WORD 0x20737469, 0x6973202B, 0x2B206E67, 0x6C756E20, 0x203D206C, 0x62203031, 0x73657479, 0x2020200A
    .WORD 0x20494C20, 0x33522020, 0x20363120, 0x20202020, 0x20202020, 0x203B2020, 0x65736142, 0x0A363120
    .WORD 0x20202020, 0x2020494C, 0x20345220, 0x20202031, 0x20202020, 0x20202020, 0x53203B20, 0x656E6769
    .WORD 0x73282064, 0x73776F68, 0x67697320, 0x200A296E, 0x4C202020, 0x20202049, 0x31203552, 0x20202030
    .WORD 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072, 0x200A657A, 0x43202020
    .WORD 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020, 0x2020504F, 0x200A524C
    .WORD 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x6F746920, 0x69735F61, 0x64656E67, 0x6E69625F, 0x53202D20, 0x656E6769, 0x69622064
    .WORD 0x7972616E, 0x61727720, 0x72657070, 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461
    .WORD 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032, 0x6E676973, 0x69206465, 0x6765746E, 0x3B0A7265
    .WORD 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20, 0x69676972, 0x206C616E, 0x66667562, 0x70207265
    .WORD 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x74690A2D, 0x735F616F, 0x656E6769, 0x69625F64, 0x200A3A6E, 0x50202020, 0x20485355, 0x200A524C
    .WORD 0x0A202020, 0x20202020, 0x614D203B, 0x32332078, 0x74696220, 0x202B2073, 0x6E676973, 0x6E202B20
    .WORD 0x206C6C75, 0x3433203D, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x32203352, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6142203B, 0x32206573, 0x2020200A, 0x20494C20, 0x34522020, 0x20203120
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x6E676953, 0x28206465, 0x776F6873, 0x69732073, 0x0A296E67
    .WORD 0x20202020, 0x2020494C, 0x20355220, 0x20203433, 0x20202020, 0x20202020, 0x54203B20, 0x20706D65
    .WORD 0x66667562, 0x73207265, 0x0A657A69, 0x20202020, 0x4C4C4143, 0x6F746920, 0x6F635F61, 0x200A6572
    .WORD 0x0A202020, 0x20202020, 0x20504F50, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x73203B0A, 0x70637274, 0x65642879, 0x202C7473, 0x29637273, 0x3B0A3B0A
    .WORD 0x706F4320, 0x20736569, 0x69727473, 0x6620676E, 0x206D6F72, 0x20637273, 0x64206F74, 0x20747365
    .WORD 0x6C636E69, 0x6E696475, 0x65742067, 0x6E696D72, 0x6E697461, 0x756E2067, 0x63206C6C, 0x61726168
    .WORD 0x72657463, 0x3B0A3B0A, 0x706E4920, 0x0A3A7475, 0x2020203B, 0x3D203152, 0x73656420, 0x616E6974
    .WORD 0x6E6F6974, 0x696F7020, 0x7265746E, 0x20203B0A, 0x20325220, 0x6F73203D, 0x65637275, 0x696F7020
    .WORD 0x7265746E, 0x3B0A3B0A, 0x74754F20, 0x3A747570, 0x20203B0A, 0x20315220, 0x6564203D, 0x6E697473
    .WORD 0x6F697461, 0x6F70206E, 0x65746E69, 0x6F282072, 0x69676972, 0x296C616E, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x7274730A, 0x3A797063, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x564F4D20, 0x20335220, 0x20203152, 0x20202020, 0x20202020, 0x20202020, 0x6153203B, 0x6F206576
    .WORD 0x69676972, 0x206C616E, 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70, 0x0A726574, 0x20202020
    .WORD 0x20564F4D, 0x52203452, 0x20202032, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x6F732065
    .WORD 0x65637275, 0x696F7020, 0x7265746E, 0x2020200A, 0x74730A20, 0x79706372, 0x6F6F6C5F, 0x200A3A70
    .WORD 0x4C202020, 0x52204244, 0x525B2032, 0x20205D34, 0x20202020, 0x20202020, 0x203B2020, 0x64616F4C
    .WORD 0x74796220, 0x72662065, 0x73206D6F, 0x6372756F, 0x20200A65, 0x54532020, 0x32522042, 0x31525B20
    .WORD 0x2020205D, 0x20202020, 0x20202020, 0x53203B20, 0x65726F74, 0x74796220, 0x6F742065, 0x73656420
    .WORD 0x616E6974, 0x6E6F6974, 0x2020200A, 0x20200A20, 0x4D432020, 0x32522050, 0x20203020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x43203B20, 0x6B636568, 0x20666920, 0x73277469, 0x6C756E20, 0x6574206C
    .WORD 0x6E696D72, 0x726F7461, 0x2020200A, 0x51454220, 0x72747320, 0x5F797063, 0x656E6F64, 0x20202020
    .WORD 0x20202020, 0x6649203B, 0x72657A20, 0x77202C6F, 0x65722765, 0x6E6F6420, 0x20200A65, 0x200A2020
    .WORD 0x41202020, 0x52204444, 0x31522031, 0x20203120, 0x20202020, 0x20202020, 0x203B2020, 0x61766441
    .WORD 0x2065636E, 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70, 0x0A726574, 0x20202020, 0x20444441
    .WORD 0x52203452, 0x20312034, 0x20202020, 0x20202020, 0x3B202020, 0x76644120, 0x65636E61, 0x756F7320
    .WORD 0x20656372, 0x6E696F70, 0x0A726574, 0x20202020, 0x74732042, 0x79706372, 0x6F6F6C5F, 0x20200A70
    .WORD 0x730A2020, 0x70637274, 0x6F645F79, 0x0A3A656E, 0x20202020, 0x20564F4D, 0x52203152, 0x20202033
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x74655220, 0x206E7275, 0x6769726F, 0x6C616E69, 0x73656420
    .WORD 0x616E6974, 0x6E6F6974, 0x696F7020, 0x7265746E, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020
    .WORD 0x0A544552, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x45524944, 0x524F5443
    .WORD 0x504F2059, 0x54415245, 0x534E4F49, 0x4D202D20, 0x68637461, 0x20676E69, 0x72756F79, 0x72656B20
    .WORD 0x276C656E, 0x61742073, 0x5F736672, 0x64616572, 0x0A726964, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A3D3D3D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x44203B0A, 0x63657269, 0x79726F74
    .WORD 0x72747320, 0x75746375, 0x28206572, 0x7161706F, 0x74206575, 0x7375206F, 0x0A297265, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x5551452E, 0x52494420, 0x2C44465F, 0x20202020, 0x30202020
    .WORD 0x20202020, 0x3B202020, 0x6C694620, 0x65642065, 0x69726373, 0x726F7470, 0x20342820, 0x65747962
    .WORD 0x2E0A2973, 0x20555145, 0x5F524944, 0x5346464F, 0x202C5445, 0x20342020, 0x20202020, 0x203B2020
    .WORD 0x72727543, 0x20746E65, 0x69736F70, 0x6E6F6974, 0x206E6920, 0x65726964, 0x726F7463, 0x74732079
    .WORD 0x6D616572, 0x20342820, 0x65747962, 0x20202973, 0x51452E0A, 0x49442055, 0x49535F52, 0x464F455A
    .WORD 0x2020202C, 0x3B0A0A38, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x65706F20, 0x7269646E
    .WORD 0x4F202D20, 0x206E6570, 0x69642061, 0x74636572, 0x2079726F, 0x20726F66, 0x64616572, 0x0A676E69
    .WORD 0x203B0A3B, 0x203A4E49, 0x20315220, 0x6170203D, 0x28206874, 0x6C6C756E, 0x7265742D, 0x616E696D
    .WORD 0x20646574, 0x69727473, 0x0A29676E, 0x554F203B, 0x52203A54, 0x203D2031, 0x2A524944, 0x61682820
    .WORD 0x656C646E, 0x726F2029, 0x6F203020, 0x7265206E, 0x0A726F72, 0x203B0A3B, 0x6E65704F, 0x20612073
    .WORD 0x65726964, 0x726F7463, 0x69662079, 0x6120656C, 0x7220646E, 0x72757465, 0x6120736E, 0x6E616820
    .WORD 0x20656C64, 0x20726F66, 0x64616572, 0x0A726964, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x6E65706F, 0x3A726964, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048
    .WORD 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056, 0x20315220
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x61702065, 0x200A6874, 0x3B202020, 0x65704F20
    .WORD 0x6964206E, 0x74636572, 0x2079726F, 0x68746977, 0x61657220, 0x6E6F2D64, 0x6620796C, 0x7367616C
    .WORD 0x61732820, 0x6120656D, 0x6F792073, 0x6C207275, 0x73612E73, 0x200A296D, 0x4D202020, 0x5220564F
    .WORD 0x38522031, 0x2020200A, 0x20494C20, 0x20325220, 0x44525F4F, 0x594C4E4F, 0x2020200A, 0x43565320
    .WORD 0x53595320, 0x45504F5F, 0x20200A4E, 0x4F4D2020, 0x39522056, 0x20315220, 0x20202020, 0x20202020
    .WORD 0x663B2020, 0x20200A64, 0x4D432020, 0x31522050, 0x200A3020, 0x42202020, 0x6F20544C, 0x646E6570
    .WORD 0x655F7269, 0x726F7272, 0x2020200A, 0x20200A20, 0x203B2020, 0x6F6C6C41, 0x65746163, 0x52494420
    .WORD 0x72747320, 0x75746375, 0x28206572, 0x6C616D73, 0x6A202C6C, 0x20747375, 0x61206466, 0x6F20646E
    .WORD 0x65736666, 0x200A2974, 0x50202020, 0x20485355, 0x20203952, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x65766173, 0x20395220, 0x0A63696A, 0x20202020, 0x5220494C, 0x49442031, 0x49535F52
    .WORD 0x464F455A, 0x2020200A, 0x4C414320, 0x616D204C, 0x636F6C6C, 0x2020200A, 0x504F5020, 0x39522020
    .WORD 0x20200A0A, 0x4D432020, 0x31522050, 0x200A3020, 0x42202020, 0x6F205145, 0x646E6570, 0x655F7269
    .WORD 0x726F7272, 0x6F6C635F, 0x200A6573, 0x0A202020, 0x20202020, 0x20564F4D, 0x52203852, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x53203B20, 0x20657661, 0x2A524944, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x74696E49, 0x696C6169, 0x4420657A, 0x73205249, 0x63757274, 0x65727574, 0x2020200A, 0x52203B20
    .WORD 0x74732032, 0x206C6C69, 0x20736168, 0x66206466, 0x206D6F72, 0x6E65706F, 0x2020200A, 0x57545320
    .WORD 0x20395220, 0x2038525B, 0x4944202B, 0x44465F52, 0x20200A5D, 0x494C2020, 0x32522020, 0x200A3020
    .WORD 0x53202020, 0x52205754, 0x525B2032, 0x202B2038, 0x5F524944, 0x5346464F, 0x0A5D5445, 0x20202020
    .WORD 0x2020200A, 0x564F4D20, 0x20315220, 0x20203852, 0x20202020, 0x20202020, 0x203B2020, 0x75746552
    .WORD 0x44206E72, 0x0A2A5249, 0x20202020, 0x706F2042, 0x69646E65, 0x6F645F72, 0x200A656E, 0x0A202020
    .WORD 0x6E65706F, 0x5F726964, 0x6F727265, 0x6C635F72, 0x3A65736F, 0x2020200A, 0x564F4D20, 0x20315220
    .WORD 0x20203952, 0x20202020, 0x20202020, 0x203B2020, 0x69206466, 0x6E692073, 0x0A395220, 0x20202020
    .WORD 0x20435653, 0x5F535953, 0x534F4C43, 0x20200A45, 0x494C2020, 0x20315220, 0x20200A30, 0x20422020
    .WORD 0x6E65706F, 0x5F726964, 0x656E6F64, 0x2020200A, 0x706F0A20, 0x69646E65, 0x72655F72, 0x3A726F72
    .WORD 0x2020200A, 0x20494C20, 0x30203152, 0x2020200A, 0x706F0A20, 0x69646E65, 0x6F645F72, 0x0A3A656E
    .WORD 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050
    .WORD 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x64616572
    .WORD 0x20726964, 0x6552202D, 0x6E206461, 0x20747865, 0x65726964, 0x726F7463, 0x6E652079, 0x0A797274
    .WORD 0x203B0A3B, 0x203A4E49, 0x20315220, 0x4944203D, 0x28202A52, 0x6D6F7266, 0x65706F20, 0x7269646E
    .WORD 0x203B0A29, 0x20202020, 0x20325220, 0x6F70203D, 0x65746E69, 0x6F742072, 0x72747320, 0x20746375
    .WORD 0x65726964, 0x7420746E, 0x6966206F, 0x3B0A6C6C, 0x54554F20, 0x3152203A, 0x31203D20, 0x20666920
    .WORD 0x72746E65, 0x65722079, 0x202C6461, 0x66692030, 0x206F6E20, 0x65726F6D, 0x746E6520, 0x73656972
    .WORD 0x312D202C, 0x206E6F20, 0x6F727265, 0x0A3B0A72, 0x6552203B, 0x20736461, 0x20656874, 0x7478656E
    .WORD 0x72696420, 0x6F746365, 0x65207972, 0x7972746E, 0x69737520, 0x7420676E, 0x6B206568, 0x656E7265
    .WORD 0x2073276C, 0x64616572, 0x20726964, 0x20616976, 0x5F535953, 0x44414552, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x6165720A, 0x72696464, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52
    .WORD 0x55502020, 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x200A2020, 0x4D202020
    .WORD 0x5220564F, 0x31522038, 0x20202020, 0x20202020, 0x20202020, 0x4944203B, 0x200A2A52, 0x4D202020
    .WORD 0x5220564F, 0x32522039, 0x20202020, 0x20202020, 0x20202020, 0x7355203B, 0x73277265, 0x72696420
    .WORD 0x20746E65, 0x66667562, 0x200A7265, 0x0A202020, 0x20202020, 0x6843203B, 0x206B6365, 0x44206669
    .WORD 0x70205249, 0x746E696F, 0x69207265, 0x61762073, 0x0A64696C, 0x20202020, 0x20504D43, 0x30203852
    .WORD 0x2020200A, 0x51454220, 0x61657220, 0x72696464, 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020
    .WORD 0x6552203B, 0x6F206461, 0x6420656E, 0x6E657269, 0x72662074, 0x64206D6F, 0x63657269, 0x79726F74
    .WORD 0x20646620, 0x6E697375, 0x75632067, 0x6E657272, 0x666F2074, 0x74657366, 0x2020200A, 0x57444C20
    .WORD 0x20315220, 0x2038525B, 0x4944202B, 0x44465F52, 0x203B205D, 0x200A6466, 0x0A202020, 0x20202020
    .WORD 0x7355203B, 0x68742065, 0x69642065, 0x74636572, 0x2779726F, 0x666F2073, 0x74657366, 0x77202D20
    .WORD 0x656E2065, 0x74206465, 0x6D69206F, 0x6D656C70, 0x20746E65, 0x6565736C, 0x726F206B, 0x65737520
    .WORD 0x2020200A, 0x74203B20, 0x66206568, 0x20746361, 0x74616874, 0x63616520, 0x65722068, 0x67206461
    .WORD 0x20737465, 0x20656E6F, 0x65726964, 0x6120746E, 0x20612074, 0x656D6974, 0x6F726620, 0x6174206D
    .WORD 0x0A736672, 0x20202020, 0x20564F4D, 0x52203252, 0x20202039, 0x20202020, 0x20202020, 0x75203B20
    .WORD 0x20726573, 0x66667562, 0x200A7265, 0x4C202020, 0x52202049, 0x49442033, 0x544E4552, 0x5A49535F
    .WORD 0x20464F45, 0x6973203B, 0x6F20657A, 0x6E6F2066, 0x69642065, 0x746E6572, 0x2020200A, 0x43565320
    .WORD 0x53595320, 0x4145525F, 0x20200A44, 0x4D432020, 0x31522050, 0x200A3020, 0x42202020, 0x72205145
    .WORD 0x64646165, 0x655F7269, 0x2020646E, 0x20202020, 0x4F45203B, 0x20200A46, 0x4D432020, 0x31522050
    .WORD 0x52494420, 0x5F544E45, 0x455A4953, 0x200A464F, 0x42202020, 0x7220454E, 0x64646165, 0x655F7269
    .WORD 0x726F7272, 0x20202020, 0x6853203B, 0x2074726F, 0x64616572, 0x20726F20, 0x6F727265, 0x20200A72
    .WORD 0x200A2020, 0x3B202020, 0x746E4520, 0x72207972, 0x20646165, 0x63637573, 0x66737365, 0x796C6C75
    .WORD 0x2020200A, 0x55203B20, 0x74616470, 0x68742065, 0x666F2065, 0x74657366, 0x206E6920, 0x20524944
    .WORD 0x75727473, 0x72757463, 0x20200A65, 0x444C2020, 0x32522057, 0x38525B20, 0x44202B20, 0x4F5F5249
    .WORD 0x45534646, 0x200A5D54, 0x41202020, 0x52204444, 0x32522032, 0x200A3120, 0x53202020, 0x52205754
    .WORD 0x525B2032, 0x202B2038, 0x5F524944, 0x5346464F, 0x0A5D5445, 0x20202020, 0x2020200A, 0x20494C20
    .WORD 0x31203152, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x75746552, 0x73206E72, 0x65636375
    .WORD 0x200A7373, 0x42202020, 0x61657220, 0x72696464, 0x6E6F645F, 0x20200A65, 0x720A2020, 0x64646165
    .WORD 0x655F7269, 0x726F7272, 0x20200A3A, 0x494C2020, 0x20315220, 0x200A312D, 0x42202020, 0x61657220
    .WORD 0x72696464, 0x6E6F645F, 0x20200A65, 0x720A2020, 0x64646165, 0x655F7269, 0x0A3A646E, 0x20202020
    .WORD 0x5220494C, 0x0A302031, 0x20202020, 0x6165720A, 0x72696464, 0x6E6F645F, 0x200A3A65, 0x50202020
    .WORD 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020
    .WORD 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x63203B0A, 0x65736F6C, 0x20726964
    .WORD 0x6C43202D, 0x2065736F, 0x65726964, 0x726F7463, 0x74732079, 0x6D616572, 0x3B0A3B0A, 0x3A4E4920
    .WORD 0x31522020, 0x44203D20, 0x0A2A5249, 0x554F203B, 0x52203A54, 0x203D2031, 0x6E6F2030, 0x63757320
    .WORD 0x73736563, 0x312D202C, 0x206E6F20, 0x6F727265, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6C630A2D, 0x6465736F, 0x0A3A7269, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550
    .WORD 0x0A385220, 0x20202020, 0x2020200A, 0x564F4D20, 0x20385220, 0x200A3152, 0x43202020, 0x5220504D
    .WORD 0x0A302038, 0x20202020, 0x20514542, 0x736F6C63, 0x72696465, 0x7272655F, 0x200A726F, 0x0A202020
    .WORD 0x20202020, 0x6C43203B, 0x2065736F, 0x20656874, 0x65726964, 0x726F7463, 0x64662079, 0x2020200A
    .WORD 0x57444C20, 0x20315220, 0x2038525B, 0x4944202B, 0x44465F52, 0x20200A5D, 0x56532020, 0x59532043
    .WORD 0x4C435F53, 0x0A45534F, 0x20202020, 0x2020200A, 0x46203B20, 0x20656572, 0x20656874, 0x20524944
    .WORD 0x75727473, 0x72757463, 0x20200A65, 0x4F4D2020, 0x31522056, 0x0A385220, 0x20202020, 0x4C4C4143
    .WORD 0x65726620, 0x20200A65, 0x200A2020, 0x4C202020, 0x31522049, 0x200A3020, 0x42202020, 0x6F6C6320
    .WORD 0x69646573, 0x6F645F72, 0x200A656E, 0x0A202020, 0x736F6C63, 0x72696465, 0x7272655F, 0x0A3A726F
    .WORD 0x20202020, 0x5220494C, 0x312D2031, 0x2020200A, 0x6C630A20, 0x6465736F, 0x645F7269, 0x3A656E6F
    .WORD 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6572203B, 0x646E6977, 0x20726964, 0x6552202D
    .WORD 0x20746573, 0x65726964, 0x726F7463, 0x74732079, 0x6D616572, 0x206F7420, 0x69676562, 0x6E696E6E
    .WORD 0x0A3B0A67, 0x4E49203B, 0x5220203A, 0x203D2031, 0x2A524944, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x7765720A, 0x64646E69, 0x0A3A7269, 0x20202020, 0x20504D43, 0x30203152, 0x2020200A
    .WORD 0x51454220, 0x77657220, 0x64646E69, 0x645F7269, 0x0A656E6F, 0x20202020, 0x2020200A, 0x20494C20
    .WORD 0x30203252, 0x2020200A, 0x57545320, 0x20325220, 0x2031525B, 0x4944202B, 0x464F5F52, 0x54455346
    .WORD 0x20200A5D, 0x200A2020, 0x3B202020, 0x65654E20, 0x6F742064, 0x65657320, 0x6F74206B, 0x67656220
    .WORD 0x696E6E69, 0x6F20676E, 0x69642066, 0x74636572, 0x0A79726F, 0x20202020, 0x6F46203B, 0x61742072
    .WORD 0x2C736672, 0x69687420, 0x656D2073, 0x20736E61, 0x736F6C63, 0x20676E69, 0x20646E61, 0x706F6572
    .WORD 0x6E696E65, 0x6F202C67, 0x73752072, 0x20676E69, 0x6565736C, 0x20200A6B, 0x203B2020, 0x706D6953
    .WORD 0x6120656C, 0x6F727070, 0x3A686361, 0x6F6C6320, 0x61206573, 0x7220646E, 0x65706F65, 0x20200A6E
    .WORD 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x200A2020, 0x4D202020
    .WORD 0x5220564F, 0x31522038, 0x2020200A, 0x53203B20, 0x20657661, 0x20656874, 0x68746170, 0x77202D20
    .WORD 0x6F642065, 0x2074276E, 0x65766168, 0x20746920, 0x726F7473, 0x202C6465, 0x74206F73, 0x20736968
    .WORD 0x74207369, 0x6B636972, 0x20200A79, 0x203B2020, 0x61206E49, 0x61657220, 0x6D69206C, 0x6D656C70
    .WORD 0x61746E65, 0x6E6F6974, 0x7473202C, 0x2065726F, 0x68746170, 0x206E6920, 0x20524944, 0x75727473
    .WORD 0x72757463, 0x20200A65, 0x200A2020, 0x3B202020, 0x726F4620, 0x776F6E20, 0x756A202C, 0x72207473
    .WORD 0x74657365, 0x66666F20, 0x20746573, 0x20646E61, 0x796C6572, 0x206E6F20, 0x64616572, 0x27726964
    .WORD 0x65622073, 0x69766168, 0x200A726F, 0x0A202020, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020
    .WORD 0x4C20504F, 0x20200A52, 0x720A2020, 0x6E697765, 0x72696464, 0x6E6F645F, 0x200A3A65, 0x52202020
    .WORD 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6964203B, 0x20646672, 0x6547202D
    .WORD 0x69662074, 0x6420656C, 0x72637365, 0x6F747069, 0x72662072, 0x44206D6F, 0x0A2A5249, 0x203B0A3B
    .WORD 0x203A4E49, 0x20315220, 0x4944203D, 0x3B0A2A52, 0x54554F20, 0x3152203A, 0x66203D20, 0x20656C69
    .WORD 0x63736564, 0x74706972, 0x202C726F, 0x2D20726F, 0x6E6F2031, 0x72726520, 0x3B0A726F, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x640A2D2D, 0x64667269, 0x20200A3A, 0x4D432020, 0x31522050, 0x200A3020
    .WORD 0x42202020, 0x64205145, 0x64667269, 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020, 0x2057444C
    .WORD 0x5B203152, 0x2B203152, 0x52494420, 0x5D44465F, 0x2020200A, 0x54455220, 0x2020200A, 0x69640A20
    .WORD 0x5F646672, 0x6F727265, 0x200A3A72, 0x4C202020, 0x31522049, 0x0A312D20, 0x20202020, 0x0A544552
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x48203B0A, 0x65706C65, 0x69203A72, 0x69645F73
    .WORD 0x202D2072, 0x63656843, 0x6669206B, 0x70206120, 0x20687461, 0x61207369, 0x72696420, 0x6F746365
    .WORD 0x3B0A7972, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x74617020, 0x203B0A68, 0x3A54554F, 0x20315220
    .WORD 0x2031203D, 0x64206669, 0x63657269, 0x79726F74, 0x2030202C, 0x6E206669, 0x202C746F, 0x6F20312D
    .WORD 0x7265206E, 0x0A726F72, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x645F7369, 0x0A3A7269
    .WORD 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x2020200A, 0x54203B20, 0x74207972, 0x706F206F
    .WORD 0x61206E65, 0x69642073, 0x74636572, 0x0A79726F, 0x20202020, 0x4C4C4143, 0x65706F20, 0x7269646E
    .WORD 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30, 0x45422020, 0x73692051, 0x7269645F, 0x746F6E5F
    .WORD 0x7269645F, 0x2020200A, 0x20200A20, 0x203B2020, 0x6F207449, 0x656E6570, 0x73612064, 0x64206120
    .WORD 0x63657269, 0x79726F74, 0x2020200A, 0x564F4D20, 0x20325220, 0x20203152, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x65766153, 0x52494420, 0x20200A2A, 0x494C2020, 0x20315220, 0x20202031, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x74655220, 0x206E7275, 0x65757274, 0x2020200A, 0x4C414320, 0x6C63204C
    .WORD 0x6465736F, 0x20207269, 0x20202020, 0x203B2020, 0x736F6C43, 0x74692065, 0x2020200A, 0x69204220
    .WORD 0x69645F73, 0x6F645F72, 0x200A656E, 0x0A202020, 0x645F7369, 0x6E5F7269, 0x645F746F, 0x0A3A7269
    .WORD 0x20202020, 0x5220494C, 0x0A302031, 0x20202020, 0x5F73690A, 0x5F726964, 0x656E6F64, 0x20200A3A
    .WORD 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x6D617845, 0x20656C70, 0x67617375, 0x75662065, 0x6974636E, 0x2D206E6F, 0x73696C20
    .WORD 0x69642074, 0x74636572, 0x2079726F, 0x746E6F63, 0x73746E65, 0x696C2820, 0x6C20656B, 0x3B0A2973
    .WORD 0x69685420, 0x65642073, 0x736E6F6D, 0x74617274, 0x68207365, 0x7420776F, 0x7375206F, 0x706F2065
    .WORD 0x69646E65, 0x65722F72, 0x69646461, 0x6C632F72, 0x6465736F, 0x3B0A7269, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6C0A2D2D, 0x5F747369, 0x65726964, 0x726F7463, 0x200A3A79, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x70203B20, 0x0A687461
    .WORD 0x20202020, 0x2020200A, 0x41203B20, 0x636F6C6C, 0x20657461, 0x65726964, 0x6F20746E, 0x7473206E
    .WORD 0x0A6B6361, 0x20202020, 0x20425553, 0x53205053, 0x49442050, 0x544E4552, 0x5A49535F, 0x0A464F45
    .WORD 0x20202020, 0x20564F4D, 0x53203952, 0x20200A50, 0x200A2020, 0x3B202020, 0x65704F20, 0x6964206E
    .WORD 0x74636572, 0x0A79726F, 0x20202020, 0x20564F4D, 0x52203152, 0x20200A38, 0x41432020, 0x6F204C4C
    .WORD 0x646E6570, 0x200A7269, 0x43202020, 0x5220504D, 0x0A302031, 0x20202020, 0x20514542, 0x7473696C
    .WORD 0x7269645F, 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020, 0x20564F4D, 0x52203852, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x44203B20, 0x0A2A5249, 0x20202020, 0x73696C0A, 0x69645F74, 0x6F6C5F72
    .WORD 0x0A3A706F, 0x20202020, 0x20564F4D, 0x52203152, 0x20200A38, 0x4F4D2020, 0x32522056, 0x0A395220
    .WORD 0x20202020, 0x4C4C4143, 0x61657220, 0x72696464, 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30
    .WORD 0x45422020, 0x696C2051, 0x645F7473, 0x635F7269, 0x65736F6C, 0x2020200A, 0x20494C20, 0x20325220
    .WORD 0x200A312D, 0x43202020, 0x5220504D, 0x32522031, 0x2020200A, 0x51454220, 0x73696C20, 0x69645F74
    .WORD 0x72655F72, 0x0A726F72, 0x20202020, 0x2020200A, 0x50203B20, 0x746E6972, 0x65687420, 0x6D616E20
    .WORD 0x20200A65, 0x44412020, 0x31522044, 0x20395220, 0x45524944, 0x4E5F544E, 0x0A454D41, 0x20202020
    .WORD 0x4C4C4143, 0x74757020, 0x20200A73, 0x200A2020, 0x3B202020, 0x20664920, 0x73277469, 0x64206120
    .WORD 0x63657269, 0x79726F74, 0x7270202C, 0x20746E69, 0x0A272F27, 0x20202020, 0x2057444C, 0x5B203252
    .WORD 0x2B203952, 0x52494420, 0x5F544E45, 0x45505954, 0x20200A5D, 0x4D432020, 0x32522050, 0x5F544420
    .WORD 0x0A524944, 0x20202020, 0x20454E42, 0x7473696C, 0x7269645F, 0x746F6E5F, 0x7269645F, 0x2020200A
    .WORD 0x20200A20, 0x494C2020, 0x20315220, 0x73616C73, 0x68635F68, 0x200A7261, 0x43202020, 0x204C4C41
    .WORD 0x63747570, 0x0A726168, 0x20202020, 0x73696C0A, 0x69645F74, 0x6F6E5F72, 0x69645F74, 0x200A3A72
    .WORD 0x4C202020, 0x31522049, 0x77656E20, 0x656E696C, 0x6168635F, 0x20200A72, 0x41432020, 0x70204C4C
    .WORD 0x68637475, 0x200A7261, 0x0A202020, 0x20202020, 0x696C2042, 0x645F7473, 0x6C5F7269, 0x0A706F6F
    .WORD 0x20202020, 0x73696C0A, 0x69645F74, 0x6C635F72, 0x3A65736F, 0x2020200A, 0x564F4D20, 0x20315220
    .WORD 0x200A3852, 0x43202020, 0x204C4C41, 0x736F6C63, 0x72696465, 0x2020200A, 0x20494C20, 0x30203152
    .WORD 0x2020200A, 0x6C204220, 0x5F747369, 0x5F726964, 0x656E6F64, 0x2020200A, 0x696C0A20, 0x645F7473
    .WORD 0x655F7269, 0x726F7272, 0x20200A3A, 0x494C2020, 0x20315220, 0x200A312D, 0x0A202020, 0x7473696C
    .WORD 0x7269645F, 0x6E6F645F, 0x200A3A65, 0x41202020, 0x53204444, 0x50532050, 0x52494420, 0x5F544E45
    .WORD 0x455A4953, 0x200A464F, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A
    .WORD 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x44203B0A, 0x20617461, 0x74636553, 0x0A6E6F69, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x73616C73, 0x68635F68, 0x0A3A7261, 0x20202020, 0x524F572E, 0x37342044, 0x20202020, 0x273B2020
    .WORD 0x6E0A272F, 0x696C7765, 0x635F656E, 0x3A726168, 0x2020200A, 0x4F572E20, 0x31204452, 0x3B0A0A30
    .WORD 0x67724120, 0x6E656D75, 0x61207374, 0x70206572, 0x65737361, 0x6E692064, 0x2E325220, 0x3231522E
    .WORD 0x70752820, 0x206F7420, 0x2E293131, 0x4F203B0A, 0x75707475, 0x73692074, 0x69727720, 0x6E657474
    .WORD 0x6D6D6920, 0x61696465, 0x796C6574, 0x6F6E203B, 0x746E6920, 0x616E7265, 0x7562206C, 0x72656666
    .WORD 0x2E676E69, 0x3B0A3B0A, 0x3A4E4920, 0x31522020, 0x66203D20, 0x616D726F, 0x74732074, 0x676E6972
    .WORD 0x4F203B0A, 0x203A5455, 0x3D203152, 0x6D756E20, 0x20726562, 0x6320666F, 0x61726168, 0x72657463
    .WORD 0x72772073, 0x65747469, 0x6F28206E, 0x6F697470, 0x2C6C616E, 0x6E616320, 0x20656220, 0x6F6E6769
    .WORD 0x29646572, 0x75203B0A, 0x65676173, 0x203B0A3A, 0x72702020, 0x66746E69, 0x65482228, 0x206F6C6C
    .WORD 0x202C7325, 0x626D756E, 0x253D7265, 0x68202C64, 0x253D7865, 0x63202C78, 0x3D726168, 0x6E5C6325
    .WORD 0x22202C22, 0x6C726F77, 0x202C2264, 0x202C3234, 0x2C353532, 0x27412720, 0x203B0A29, 0x524B2020
    .WORD 0x0A3A3233, 0x2020203B, 0x5220494C, 0x6D662031, 0x74735F74, 0x203B0A72, 0x494C2020, 0x20325220
    .WORD 0x3B0A3234, 0x4C202020, 0x33522049, 0x6C656820, 0x735F6F6C, 0x3B0A7274, 0x42202020, 0x7270204C
    .WORD 0x66746E69, 0x2E2E3B0A, 0x663B0A2E, 0x735F746D, 0x203A7274, 0x4353412E, 0x205A4949, 0x6D754E22
    .WORD 0x3A726562, 0x2C642520, 0x72745320, 0x3A676E69, 0x5C732520, 0x3B0A226E, 0x6C6C6568, 0x74735F6F
    .WORD 0x2E203A72, 0x49435341, 0x22205A49, 0x6C726F77, 0x3B0A2264, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A0A2D2D, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7270203B, 0x66746E69, 0x46202D20
    .WORD 0x616D726F, 0x64657474, 0x74756F20, 0x20747570, 0x73206F74, 0x756F6474, 0x0A3B0A74, 0x7553203B
    .WORD 0x726F7070, 0x20646574, 0x766E6F63, 0x69737265, 0x3A736E6F, 0x20203B0A, 0x20252520, 0x20202020
    .WORD 0x74696C20, 0x6C617265, 0x27252720, 0x20203B0A, 0x20732520, 0x20202020, 0x72747320, 0x20676E69
    .WORD 0x61686328, 0x0A292A72, 0x2020203B, 0x2F206425, 0x20692520, 0x6E676973, 0x64206465, 0x6D696365
    .WORD 0x3B0A6C61, 0x25202020, 0x20202078, 0x75202020, 0x6769736E, 0x2064656E, 0x61786568, 0x69636564
    .WORD 0x206C616D, 0x776F6C28, 0x61637265, 0x0A296573, 0x2020203B, 0x20206325, 0x20202020, 0x676E6973
    .WORD 0x6320656C, 0x61726168, 0x72657463, 0x20203B0A, 0x20622520, 0x20202020, 0x736E7520, 0x656E6769
    .WORD 0x69622064, 0x7972616E, 0x20203B0A, 0x206F2520, 0x20202020, 0x736E7520, 0x656E6769, 0x636F2064
    .WORD 0x0A6C6174, 0x203B0A3B, 0x75677241, 0x746E656D, 0x52203A73, 0x522E2E32, 0x28203231, 0x73726966
    .WORD 0x31312074, 0x74202C29, 0x206E6568, 0x73206E6F, 0x6B636174, 0x61632820, 0x72656C6C, 0x709180E2
    .WORD 0x65687375, 0x0A2E2964, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6E697270, 0x0A3A6674
    .WORD 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x48535550
    .WORD 0x0A395220, 0x20202020, 0x48535550, 0x30315220, 0x2020200A, 0x53555020, 0x31522048, 0x20200A31
    .WORD 0x55502020, 0x52204853, 0x0A0A3231, 0x20202020, 0x20425553, 0x53205053, 0x30382050, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x61636F6C, 0x7266206C, 0x3A656D61, 0x20343420, 0x3433202B
    .WORD 0x70202B20, 0x69646461, 0x0A0A676E, 0x20202020, 0x20564F4D, 0x52203852, 0x20202031, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x6D726F66, 0x70207461, 0x746E696F, 0x200A7265, 0x4C202020
    .WORD 0x52202049, 0x20302039, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x61203B20, 0x6D756772
    .WORD 0x20746E65, 0x65646E69, 0x200A0A78, 0x3B202020, 0x76615320, 0x32522065, 0x31522E2E, 0x6F742032
    .WORD 0x636F6C20, 0x61206C61, 0x79617272, 0x2020200A, 0x57545320, 0x20325220, 0x2050535B, 0x5D30202B
    .WORD 0x2020200A, 0x57545320, 0x20335220, 0x2050535B, 0x5D34202B, 0x2020200A, 0x57545320, 0x20345220
    .WORD 0x2050535B, 0x5D38202B, 0x2020200A, 0x57545320, 0x20355220, 0x2050535B, 0x3231202B, 0x20200A5D
    .WORD 0x54532020, 0x36522057, 0x50535B20, 0x31202B20, 0x200A5D36, 0x53202020, 0x52205754, 0x535B2037
    .WORD 0x202B2050, 0x0A5D3032, 0x20202020, 0x20575453, 0x5B203852, 0x2B205053, 0x5D343220, 0x2020200A
    .WORD 0x57545320, 0x20395220, 0x2050535B, 0x3832202B, 0x20200A5D, 0x54532020, 0x31522057, 0x535B2030
    .WORD 0x202B2050, 0x0A5D3233, 0x20202020, 0x20575453, 0x20313152, 0x2050535B, 0x3633202B, 0x20200A5D
    .WORD 0x54532020, 0x31522057, 0x535B2032, 0x202B2050, 0x0A5D3034, 0x2020200A, 0x564F4D20, 0x30315220
    .WORD 0x20505320, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x73616220, 0x666F2065, 0x76617320
    .WORD 0x72206465, 0x73696765, 0x73726574, 0x2020200A, 0x44444120, 0x31315220, 0x20505320, 0x20203434
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x6E6F6320, 0x73726576, 0x206E6F69, 0x66667562, 0x0A0A7265
    .WORD 0x6E697270, 0x6C5F6674, 0x3A706F6F, 0x2020200A, 0x42444C20, 0x20315220, 0x5D38525B, 0x20202020
    .WORD 0x65723B20, 0x66206461, 0x7320746D, 0x6E697274, 0x68632067, 0x200A7261, 0x43202020, 0x5220504D
    .WORD 0x0A302031, 0x20202020, 0x20514542, 0x6E697270, 0x645F6674, 0x0A656E6F, 0x2020200A, 0x504D4320
    .WORD 0x20315220, 0x20203733, 0x68633B20, 0x206B6365, 0x20726F66, 0x0A272527, 0x20202020, 0x20454E42
    .WORD 0x6E697270, 0x6E5F6674, 0x616D726F, 0x68635F6C, 0x0A0A7261, 0x20202020, 0x20444441, 0x52203852
    .WORD 0x20312038, 0x7469203B, 0x20612073, 0x2C272527, 0x766F6D20, 0x6F742065, 0x78656E20, 0x68632074
    .WORD 0x66207261, 0x7320726F, 0x69636570, 0x72656966, 0x2020200A, 0x42444C20, 0x20325220, 0x5D38525B
    .WORD 0x2020200A, 0x504D4320, 0x20325220, 0x20200A30, 0x45422020, 0x72702051, 0x66746E69, 0x6E6F645F
    .WORD 0x200A0A65, 0x43202020, 0x5220504D, 0x37332032, 0x3B202020, 0x65686320, 0x66206B63, 0x2720726F
    .WORD 0x0A272525, 0x20202020, 0x20514542, 0x6E697270, 0x705F6674, 0x65637265, 0x200A746E, 0x43202020
    .WORD 0x5220504D, 0x31312032, 0x3B202035, 0x65686320, 0x66206B63, 0x2720726F, 0x0A277325, 0x20202020
    .WORD 0x20514542, 0x6E697270, 0x735F6674, 0x6E697274, 0x20200A67, 0x4D432020, 0x32522050, 0x30303120
    .WORD 0x633B2020, 0x6B636568, 0x726F6620, 0x64252720, 0x20200A27, 0x45422020, 0x72702051, 0x66746E69
    .WORD 0x746E695F, 0x2020200A, 0x504D4320, 0x20325220, 0x20353031, 0x68633B20, 0x206B6365, 0x20726F66
    .WORD 0x27692527, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E, 0x0A746E69, 0x20202020, 0x20504D43
    .WORD 0x31203252, 0x20203032, 0x6568633B, 0x66206B63, 0x2720726F, 0x0A277825, 0x20202020, 0x20514542
    .WORD 0x6E697270, 0x685F6674, 0x200A7865, 0x43202020, 0x5220504D, 0x39392032, 0x3B202020, 0x63656863
    .WORD 0x6F66206B, 0x25272072, 0x200A2763, 0x42202020, 0x70205145, 0x746E6972, 0x68635F66, 0x200A7261
    .WORD 0x43202020, 0x5220504D, 0x38392032, 0x3B202020, 0x63656863, 0x6F66206B, 0x25272072, 0x200A2762
    .WORD 0x42202020, 0x70205145, 0x746E6972, 0x69625F66, 0x20200A6E, 0x4D432020, 0x32522050, 0x31313120
    .WORD 0x633B2020, 0x6B636568, 0x726F6620, 0x6F252720, 0x20200A27, 0x45422020, 0x72702051, 0x66746E69
    .WORD 0x74636F5F, 0x20200A0A, 0x203B2020, 0x6E6B6E75, 0x206E776F, 0x63657073, 0x65696669, 0x20200A72
    .WORD 0x494C2020, 0x31522020, 0x20373320, 0x753B2020, 0x6F6E6B6E, 0x73206E77, 0x69636570, 0x72656966
    .WORD 0x7270202C, 0x20746E69, 0x0A272527, 0x20202020, 0x4C4C4143, 0x74757020, 0x72616863, 0x2020200A
    .WORD 0x564F4D20, 0x20315220, 0x20203252, 0x70203B20, 0x746E6972, 0x65687420, 0x6B6E7520, 0x6E776F6E
    .WORD 0x65707320, 0x69666963, 0x63207265, 0x0A726168, 0x20202020, 0x4C4C4143, 0x74757020, 0x72616863
    .WORD 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69
    .WORD 0x726F6E5F, 0x5F6C616D, 0x72616863, 0x20200A3A, 0x41432020, 0x70204C4C, 0x68637475, 0x200A7261
    .WORD 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66, 0x6E69746E, 0x0A0A6575, 0x6E697270, 0x705F6674
    .WORD 0x65637265, 0x0A3A746E, 0x20202020, 0x2020494C, 0x33203152, 0x20202037, 0x6972703B, 0x2720746E
    .WORD 0x200A2725, 0x43202020, 0x204C4C41, 0x63747570, 0x0A726168, 0x20202020, 0x20202042, 0x6E697270
    .WORD 0x635F6674, 0x69746E6F, 0x0A65756E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x41203B0A
    .WORD 0x6D756772, 0x20746E65, 0x63746566, 0x65682068, 0x7265706C, 0x73282073, 0x20656D61, 0x62207361
    .WORD 0x726F6665, 0x3B0A2965, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F0A2D2D, 0x63746566, 0x72615F68
    .WORD 0x31725F67, 0x20200A3A, 0x55502020, 0x4C204853, 0x200A2052, 0x50202020, 0x20485355, 0x200A3352
    .WORD 0x43202020, 0x204C4C41, 0x7465675F, 0x6772615F, 0x6464615F, 0x73736572, 0x2020200A, 0x57444C20
    .WORD 0x20315220, 0x5D33525B, 0x2020200A, 0x504F5020, 0x0A335220, 0x20202020, 0x20504F50, 0x200A524C
    .WORD 0x52202020, 0x0A0A5445, 0x7465665F, 0x615F6863, 0x725F6772, 0x200A3A32, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x50202020, 0x20485355, 0x200A3352, 0x43202020, 0x204C4C41, 0x7465675F, 0x6772615F
    .WORD 0x6464615F, 0x73736572, 0x2020200A, 0x57444C20, 0x20325220, 0x5D33525B, 0x2020200A, 0x504F5020
    .WORD 0x0A335220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x7465675F, 0x6772615F
    .WORD 0x6464615F, 0x73736572, 0x2020203A, 0x6566203B, 0x20686374, 0x20656874, 0x72646461, 0x20737365
    .WORD 0x7420666F, 0x6E206568, 0x20747865, 0x75677261, 0x746E656D, 0x73616220, 0x6F206465, 0x3952206E
    .WORD 0x72612820, 0x6E692067, 0x29786564, 0x2020200A, 0x504D4320, 0x20395220, 0x20203131, 0x20202020
    .WORD 0x69203B20, 0x72612066, 0x6E692067, 0x20786564, 0x31203D3E, 0x69202C31, 0x20732774, 0x74206E6F
    .WORD 0x73206568, 0x6B636174, 0x2020200A, 0x544C4220, 0x72615F20, 0x6E695F67, 0x6765725F, 0x20200A73
    .WORD 0x55532020, 0x33522042, 0x20395220, 0x20203131, 0x203B2020, 0x3D203352, 0x6D756E20, 0x20726562
    .WORD 0x6520666F, 0x61727478, 0x67726120, 0x6E6F2073, 0x61747320, 0x200A6B63, 0x4C202020, 0x52202049
    .WORD 0x0A342034, 0x20202020, 0x204C554D, 0x52203352, 0x34522033, 0x2020200A, 0x44444120, 0x20335220
    .WORD 0x52205053, 0x20202033, 0x52203B20, 0x203D2033, 0x72646461, 0x20737365, 0x6620666F, 0x74737269
    .WORD 0x74786520, 0x61206172, 0x6F206772, 0x7473206E, 0x206B6361, 0x746F6E28, 0x72757320, 0x66692065
    .WORD 0x69687420, 0x73692073, 0x726F6320, 0x74636572, 0x20200A29, 0x44412020, 0x33522044, 0x20335220
    .WORD 0x20343031, 0x203B2020, 0x7366666F, 0x74207465, 0x6163206F, 0x72656C6C, 0x66207327, 0x74737269
    .WORD 0x74786520, 0x61206172, 0x31206772, 0x0A203430, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x2073693B, 0x20656874, 0x657A6973, 0x20666F20, 0x20656874, 0x61636F6C, 0x7266206C
    .WORD 0x20656D61, 0x29303828, 0x73202B20, 0x64657661, 0x67657220, 0x65747369, 0x28207372, 0x0A293434
    .WORD 0x20202020, 0x0A544552, 0x72615F0A, 0x6E695F67, 0x6765725F, 0x20203A73, 0x20202020, 0x66203B20
    .WORD 0x68637465, 0x67726120, 0x6E656D75, 0x72662074, 0x52206D6F, 0x522E2E32, 0x62203231, 0x64657361
    .WORD 0x206E6F20, 0x200A3952, 0x4C202020, 0x52202049, 0x20342034, 0x20202020, 0x0A202020, 0x20202020
    .WORD 0x204C554D, 0x52203352, 0x34522039, 0x20202020, 0x3952203B, 0x61203D20, 0x69206772, 0x7865646E
    .WORD 0x5228202C, 0x203D2033, 0x7366666F, 0x69207465, 0x7962206E, 0x29736574, 0x2020200A, 0x44444120
    .WORD 0x20335220, 0x20303152, 0x20203352, 0x52203B20, 0x203D2033, 0x72646461, 0x20737365, 0x7320666F
    .WORD 0x64657661, 0x67657220, 0x65747369, 0x6E692072, 0x636F6C20, 0x61206C61, 0x79617272, 0x3152202C
    .WORD 0x203D2030, 0x65736162, 0x20666F20, 0x65766173, 0x65722064, 0x74736967, 0x0A737265, 0x20202020
    .WORD 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x53203B0A, 0x69636570, 0x72656966
    .WORD 0x6E616820, 0x72656C64, 0x2D3B0A73, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72700A2D, 0x66746E69
    .WORD 0x7274735F, 0x3A676E69, 0x2020200A, 0x4C414320, 0x665F204C, 0x68637465, 0x6772615F, 0x2031725F
    .WORD 0x65673B20, 0x74732074, 0x676E6972, 0x696F7020, 0x7265746E, 0x6F726620, 0x3152206D, 0x2020200A
    .WORD 0x44444120, 0x20395220, 0x31203952, 0x2020200A, 0x4C414320, 0x705F204C, 0x746E6972, 0x7274735F
    .WORD 0x20676E69, 0x72703B20, 0x20746E69, 0x20656874, 0x69727473, 0x200A676E, 0x42202020, 0x70202020
    .WORD 0x746E6972, 0x6F635F66, 0x6E69746E, 0x0A0A6575, 0x6E697270, 0x695F6674, 0x0A3A746E, 0x20202020
    .WORD 0x4C4C4143, 0x65665F20, 0x5F686374, 0x5F677261, 0x20203272, 0x7465673B, 0x746E6920, 0x72656765
    .WORD 0x6F726620, 0x3252206D, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x2020200A, 0x564F4D20
    .WORD 0x20315220, 0x20313152, 0x20202020, 0x20202020, 0x72203B20, 0x69203131, 0x68742073, 0x6F632065
    .WORD 0x7265766E, 0x6E6F6973, 0x66756220, 0x20726566, 0x206E6F28, 0x63617473, 0x200A296B, 0x43202020
    .WORD 0x204C4C41, 0x6972705F, 0x6E5F746E, 0x65626D75, 0x3B202072, 0x6E697270, 0x68742074, 0x6E692065
    .WORD 0x65676574, 0x20200A72, 0x20422020, 0x72702020, 0x66746E69, 0x6E6F635F, 0x756E6974, 0x700A0A65
    .WORD 0x746E6972, 0x65685F66, 0x200A3A78, 0x43202020, 0x204C4C41, 0x7465665F, 0x615F6863, 0x725F6772
    .WORD 0x20200A32, 0x44412020, 0x39522044, 0x20395220, 0x20200A31, 0x4F4D2020, 0x31522056, 0x31315220
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x20313172, 0x74207369, 0x63206568, 0x65766E6F, 0x6F697372
    .WORD 0x7562206E, 0x72656666, 0x6E6F2820, 0x61747320, 0x20296B63, 0x20646E61, 0x6F206F73, 0x6F66206E
    .WORD 0x746F2072, 0x20726568, 0x766E6F63, 0x69737265, 0x20736E6F, 0x706C6568, 0x2E737265, 0x20200A2E
    .WORD 0x41432020, 0x5F204C4C, 0x6E697270, 0x65685F74, 0x20200A78, 0x20422020, 0x72702020, 0x66746E69
    .WORD 0x6E6F635F, 0x756E6974, 0x700A0A65, 0x746E6972, 0x68635F66, 0x0A3A7261, 0x20202020, 0x4C4C4143
    .WORD 0x65665F20, 0x5F686374, 0x5F677261, 0x200A3172, 0x41202020, 0x52204444, 0x39522039, 0x200A3120
    .WORD 0x43202020, 0x204C4C41, 0x63747570, 0x0A726168, 0x20202020, 0x20202042, 0x6E697270, 0x635F6674
    .WORD 0x69746E6F, 0x0A65756E, 0x6972700A, 0x5F66746E, 0x3A6E6962, 0x2020200A, 0x4C414320, 0x665F204C
    .WORD 0x68637465, 0x6772615F, 0x0A32725F, 0x20202020, 0x20444441, 0x52203952, 0x0A312039, 0x20202020
    .WORD 0x20564F4D, 0x52203152, 0x200A3131, 0x43202020, 0x204C4C41, 0x6972705F, 0x625F746E, 0x200A6E69
    .WORD 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66, 0x6E69746E, 0x0A0A6575, 0x6E697270, 0x6F5F6674
    .WORD 0x0A3A7463, 0x20202020, 0x4C4C4143, 0x65665F20, 0x5F686374, 0x5F677261, 0x200A3272, 0x41202020
    .WORD 0x52204444, 0x39522039, 0x200A3120, 0x4D202020, 0x5220564F, 0x31522031, 0x20200A31, 0x41432020
    .WORD 0x5F204C4C, 0x6E697270, 0x636F5F74, 0x20200A74, 0x20422020, 0x72702020, 0x66746E69, 0x6E6F635F
    .WORD 0x756E6974, 0x700A0A65, 0x746E6972, 0x6F635F66, 0x6E69746E, 0x203A6575, 0x3B202020, 0x63206F74
    .WORD 0x69746E6F, 0x2065756E, 0x636F7270, 0x69737365, 0x6620676E, 0x616D726F, 0x74732074, 0x676E6972
    .WORD 0x2020200A, 0x44444120, 0x20385220, 0x31203852, 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E
    .WORD 0x706F6F6C, 0x72700A0A, 0x66746E69, 0x6E6F645F, 0x200A3A65, 0x41202020, 0x53204444, 0x50532050
    .WORD 0x0A303820, 0x20202020, 0x20504F50, 0x0A323152, 0x20202020, 0x20504F50, 0x0A313152, 0x20202020
    .WORD 0x20504F50, 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38
    .WORD 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x6972705F, 0x735F746E, 0x6E697274, 0x202D2067, 0x74697257, 0x20612065, 0x6C6C756E
    .WORD 0x749180E2, 0x696D7265, 0x6574616E, 0x74732064, 0x676E6972, 0x206F7420, 0x6F647473, 0x28207475
    .WORD 0x6E206F6E, 0x696C7765, 0x0A29656E, 0x203B0A3B, 0x73657355, 0x65687420, 0x62696C20, 0x77602063
    .WORD 0x65746972, 0x72772060, 0x65707061, 0x66282072, 0x62202C64, 0x65666675, 0x6C202C72, 0x20296E65
    .WORD 0x74736E69, 0x20646165, 0x6420666F, 0x63657269, 0x56532074, 0x3B0A2E43, 0x49203B0A, 0x20203A4E
    .WORD 0x3D203152, 0x696F7020, 0x7265746E, 0x206F7420, 0x69727473, 0x3B0A676E, 0x54554F20, 0x6F6E203A
    .WORD 0x3B0A656E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F0A2D2D, 0x6E697270, 0x74735F74, 0x676E6972
    .WORD 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x55502020
    .WORD 0x52204853, 0x20200A39, 0x4F4D2020, 0x38522056, 0x0A315220, 0x20202020, 0x4C4C4143, 0x72747320
    .WORD 0x206E656C, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x3D203152, 0x6E656C20, 0x0A687467
    .WORD 0x20202020, 0x20564F4D, 0x52203952, 0x20200A31, 0x494C2020, 0x31522020, 0x44545320, 0x5F54554F
    .WORD 0x200A4446, 0x4D202020, 0x5220564F, 0x38522032, 0x2020200A, 0x564F4D20, 0x20335220, 0x200A3952
    .WORD 0x43202020, 0x204C4C41, 0x74697277, 0x20202065, 0x20202020, 0x20202020, 0x20202020, 0x6C203B20
    .WORD 0x20636269, 0x70617277, 0x2C726570, 0x746F6E20, 0x72696420, 0x20746365, 0x0A435653, 0x20202020
    .WORD 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A
    .WORD 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72705F20, 0x5F746E69
    .WORD 0x626D756E, 0x2D207265, 0x726F4620, 0x2074616D, 0x20646E61, 0x6E697270, 0x20612074, 0x6E676973
    .WORD 0x69206465, 0x6765746E, 0x28207265, 0x73657375, 0x6F746920, 0x65645F61, 0x3B0A2963, 0x49203B0A
    .WORD 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x20726566, 0x73756D28
    .WORD 0x65622074, 0xA589E220, 0x62203331, 0x73657479, 0x203B0A29, 0x20202020, 0x20325220, 0x6973203D
    .WORD 0x64656E67, 0x746E6920, 0x72656765, 0x4F203B0A, 0x203A5455, 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A, 0x5F746E69, 0x626D756E, 0x0A3A7265, 0x20202020, 0x48535550
    .WORD 0x0A524C20, 0x20202020, 0x4C4C4143, 0x6F746920, 0x65645F61, 0x20202063, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x73657375, 0x20315220, 0x66756228, 0x29726566, 0x646E6120, 0x20325220, 0x6C617628
    .WORD 0x0A296575, 0x20202020, 0x20564F4D, 0x52203152, 0x20202031, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x73203152, 0x6C6C6974, 0x696F7020, 0x2073746E, 0x62206F74, 0x65666675, 0x74732072
    .WORD 0x0A747261, 0x20202020, 0x4C4C4143, 0x72705F20, 0x5F746E69, 0x69727473, 0x200A676E, 0x50202020
    .WORD 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D
    .WORD 0x72705F20, 0x5F746E69, 0x20786568, 0x6F46202D, 0x74616D72, 0x646E6120, 0x69727020, 0x6120746E
    .WORD 0x6E75206E, 0x6E676973, 0x69206465, 0x6765746E, 0x69207265, 0x6568206E, 0x75282078, 0x20736573
    .WORD 0x616F7469, 0x7865685F, 0x0A3B0A29, 0x4E49203B, 0x5220203A, 0x203D2031, 0x74736564, 0x74616E69
    .WORD 0x206E6F69, 0x66667562, 0x28207265, 0x7473756D, 0x20656220, 0x39A589E2, 0x74796220, 0x0A297365
    .WORD 0x2020203B, 0x52202020, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x4F203B0A
    .WORD 0x203A5455, 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A, 0x5F746E69
    .WORD 0x3A786568, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x4C414320, 0x7469204C, 0x685F616F
    .WORD 0x200A7865, 0x4D202020, 0x5220564F, 0x31522031, 0x2020200A, 0x4C414320, 0x705F204C, 0x746E6972
    .WORD 0x7274735F, 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x705F203B, 0x746E6972, 0x7865685F, 0x46202D20, 0x616D726F
    .WORD 0x6E612074, 0x72702064, 0x20746E69, 0x75206E61, 0x6769736E, 0x2064656E, 0x65746E69, 0x20726567
    .WORD 0x68206E69, 0x28207865, 0x73657375, 0x6F746920, 0x65685F61, 0x3B0A2978, 0x49203B0A, 0x20203A4E
    .WORD 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x20726566, 0x73756D28, 0x65622074
    .WORD 0xA589E220, 0x79622039, 0x29736574, 0x20203B0A, 0x20202020, 0x3D203252, 0x736E7520, 0x656E6769
    .WORD 0x6E692064, 0x65676574, 0x203B0A72, 0x3A54554F, 0x6E6F6E20, 0x2D3B0A65, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x705F0A2D, 0x746E6972, 0x6E69625F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52
    .WORD 0x41432020, 0x69204C4C, 0x5F616F74, 0x0A6E6962, 0x20202020, 0x20564F4D, 0x52203152, 0x20200A31
    .WORD 0x41432020, 0x5F204C4C, 0x6E697270, 0x74735F74, 0x676E6972, 0x2020200A, 0x504F5020, 0x0A524C20
    .WORD 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F203B0A, 0x6E697270
    .WORD 0x636F5F74, 0x202D2074, 0x6D726F46, 0x61207461, 0x7020646E, 0x746E6972, 0x206E6120, 0x69736E75
    .WORD 0x64656E67, 0x746E6920, 0x72656765, 0x206E6920, 0x6174636F, 0x7528206C, 0x20736573, 0x616F7469
    .WORD 0x74636F5F, 0x0A3B0A29, 0x4E49203B, 0x5220203A, 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69
    .WORD 0x66667562, 0x28207265, 0x7473756D, 0x20656220, 0x39A589E2, 0x74796220, 0x0A297365, 0x2020203B
    .WORD 0x52202020, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x4F203B0A, 0x203A5455
    .WORD 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A, 0x5F746E69, 0x3A74636F
    .WORD 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x4C414320, 0x7469204C, 0x6F5F616F, 0x200A7463
    .WORD 0x4D202020, 0x5220564F, 0x31522031, 0x2020200A, 0x4C414320, 0x705F204C, 0x746E6972, 0x7274735F
    .WORD 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x3D3D3D3B, 0x3D3D3D3D
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
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
