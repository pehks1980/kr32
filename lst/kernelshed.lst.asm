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

.EQU PTE_R,       0x0001    ;RD perm
.EQU PTE_W,       0x0002    ;WR perm
.EQU PTE_X,       0x0004    ;EXEC perm
.EQU PTE_U,       0x0008    ;USER mode only
.EQU PTE_P,       0x0010    ;Privileged mode
.EQU PTE_G,       0x0020    ;G bit - PTE is not flushed when switch happens (OS related)

.EQU KERNEL_FLAGS, 0x0037       ; P|R|W|X|G, supervisor-only shared mapping  GP-XWR
.EQU USER_RX,      0x001D       ; P|R|X|U  ;                                 -PUX-R
.EQU USER_RW,      0x001B       ; P|R|W|U  ;                                 -PU-WR ; used for load image to memory in execve
.EQU KERN_USER_RX, 0x003D       ; P|R|X|U|G, shared executable (kernel can   GPUX-R fetch user code); not used
.EQU KERNEL_USER_ALL, 0x001F   ; P|R|W|X|U, per-task user executable mapping -PUXWR ;needed for execve kenrel executes loaded code

.EQU PAGE_SIZE,    0x1000
.EQU PAGE_MASK,    0x0FFF
.EQU MAX_APP_SIZE, 0xFFFF   ;64 for userland app code page

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
0x00001008   CALL nsfs_bmi_demo
0x00001010       ENABLEINT

idle_loop:
0x00001014       ADD R1 R1 1


    ;DEBUG 10
0x00001018       B idle_loop

nsfs_bmi_demo:
0x00001020       PUSH LR
    ;------------------------------------------------------
    ; NSFS/BMI demo sequence from system task 0.
    ; Recreates namespace 0, creates a file, appends bytes, then deletes it.
    ;
    ; R1 = opcode
    ; R2 = payload pointer
    ; R3 = payload length
    ; R4 = namespace

0x00001024       MOV R1 NS_DELETE
0x00001028       LI R2 0x00000000
0x00001030       MOV R3 R2
0x00001034       MOV R4 R2
0x00001038   CALL bmi_call

0x00001040       MOV R1 NS_CREATE
0x00001044       LI R2 0x00000000
0x0000104C       MOV R3 R2
0x00001050       MOV R4 R2
0x00001054   CALL bmi_call

0x0000105C       MOV R1 FILE_CREATE
0x00001060       LI R2 cr_file
0x00001068       LI R3 13
0x00001070       LI R4 0
0x00001078   CALL bmi_call

0x00001080       MOV R1 FILE_APPEND
0x00001084       LI R2 cr_file_append_payload
0x0000108C       LI R3 21
0x00001094       LI R4 0
0x0000109C   CALL bmi_call

   ; MOV R1 FILE_DELETE
   ; LI R2 cr_file
   ; LI R3 13
   ; LI R4 0
   ; CALL bmi_call

0x000010A4       POP LR
0x000010A8       RET

cr_file:
    .asciiz "etc/crash.txt"

cr_file_append_payload:
    .WORD 0x0000000D    ; path length = 13
    .WORD 0x2F637465    ; "etc/"
    .WORD 0x73617263    ; "cras"
    .WORD 0x78742E68    ; "h.tx"
    .WORD 0x43424174    ; "tABC"
    .WORD 0x0000000A    ; "\n"

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

        ; Run the NSFS/BMI demo once during boot so the host log shows it
        ; even when user init starts before the idle task gets scheduled.
0x00002038   CALL nsfs_bmi_demo
0x00002040           LI R1 NSFS_DEFAULT_NS
0x00002048   CALL nsfs_refresh_index

        ;init console mutex
0x00002050   CALL init_console_mutex

        ; Mount the built-in read-only TAR archive and show its index.
0x00002058           LI R1 tarfs_start
0x00002060           LI R2 tarfs_end
0x00002068           SUB R2 R2 R1
0x0000206C   CALL tarfs_init
0x00002074   CALL tarfs_dump_index


        ;test read dirs from tarfs probably needs to be removed later
0x0000207C           LI R1 etc_path
0x00002084   CALL tarfs_readdir1

0x0000208C           LI R1 bin_path
0x00002094   CALL tarfs_readdir1

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
0x0000209C           LI R1 tasks
0x000020A4           LDW R2 [R1 + TASK_PTBR]
0x000020A8           SETPTBR R2
0x000020AC           LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
0x000020B0   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore
0x000020B8           B trap_restore

; ================================================================
; Initialize console mutex at boot time
; ================================================================

init_console_mutex:
0x000020C0       PUSH LR
0x000020C4       LI R1 console_mutex
0x000020CC       BL mutex_init
0x000020D4       POP LR
0x000020D8       RET

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x000020DC       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x000020E4       LI R2 trap_entry
0x000020EC       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x000020F0       LI R2 trap_entry
0x000020F8       STW R2 [R1+4]                ; IDT[1]
0x000020FC       STW R2 [R1+8]                ; IDT[2]
0x00002100       STW R2 [R1+12]               ; IDT[3]
0x00002104       STW R2 [R1+24]               ; IDT[6]
0x00002108       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x0000210C       SETIDTR R1
0x00002110       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables0:
0x00002114       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x00002118       LI R1 page_bitmap
0x00002120       LI R3 16
0x00002128       BL mem_zero

0x00002130       POP LR
0x00002134       RET

init_page_tables:
0x00002138       PUSH LR

    ; Clear the refcount array
0x0000213C       LI R1 page_refcounts
0x00002144       LI R3 MAX_PHYS_PAGES          ; 128 bytes = 128 pages: 1 byte for ea page (4k)
0x0000214C       BL mem_zero                   ; 0 - free, 1 - allocated

    ; Reserve the TAR image page (physical 0xA0000)
    ; index = (0xA0000 - PAGE_ALLOC_BASE) / 4096
    ; PAGE_ALLOC_BASE = 0x50000
    ; (0xA0000 - 0x50000) = 0x50000 = 327680
    ; 327680 / 4096 = 80
0x00002154       LI R2 80
0x0000215C       LI R1 page_refcounts
0x00002164       ADD R1 R1 R2
0x00002168       LI R3 1
0x00002170       STB R3 [R1]     ;1 = allocated (80 pages for tar image

0x00002174       POP LR
0x00002178       RET

; ================================================================
; Map common kernel pages into the given page table (PTBR in R1)
; ================================================================

map_common_kernel:
0x0000217C       PUSH LR
0x00002180       PUSH R12

    ; Boot page, kernel/trap code, static kernel data, and MMIO are
    ; identity-mapped into every address space.
0x00002184       LI R2 0x00000000      ;page 0 - boot (0000)
0x0000218C       LI R3 0x00000000
0x00002194       LI R4 KERNEL_FLAGS
0x0000219C       bl map_page

    ; Kernel-only helpers: copy routines and page-table inspection
0x000021A4       LI R2 0x00001000      ; page for kernel buffers
0x000021AC       LI R3 0x00001000
0x000021B4       LI R4 KERNEL_FLAGS
0x000021BC       BL map_page

0x000021C4       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x000021CC       LI R3 0x00002000
0x000021D4       LI R4 KERNEL_FLAGS
0x000021DC       BL map_page

0x000021E4       LI R2 0x00003000
0x000021EC       LI R3 0x00003000
0x000021F4       LI R4 KERNEL_FLAGS
0x000021FC       BL map_page

0x00002204       LI R2 0x00004000
0x0000220C       LI R3 0x00004000
0x00002214       LI R4 KERNEL_FLAGS
0x0000221C       BL map_page

0x00002224       LI R2 0x00005000
0x0000222C       LI R3 0x00005000
0x00002234       LI R4 KERNEL_FLAGS
0x0000223C       BL map_page

0x00002244       LI R2 0x00006000
0x0000224C       LI R3 0x00006000
0x00002254       LI R4 KERNEL_FLAGS
0x0000225C       BL map_page

0x00002264       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x0000226C       LI R3 0x00007000
0x00002274       LI R4 KERNEL_FLAGS
0x0000227C       BL map_page

0x00002284       LI R2 0x00008000      ; page 4 (number is page table entry one) tasks data
0x0000228C       LI R3 0x00008000
0x00002294       LI R4 KERNEL_FLAGS
0x0000229C       BL map_page

0x000022A4       LI R2 0x00009000      ; add page (number is page table entry one) tasks data
0x000022AC       LI R3 0x00009000
0x000022B4       LI R4 KERNEL_FLAGS
0x000022BC       BL map_page

0x000022C4       LI R2 0x0000A000      ; add page (number is page table entry one) tasks data
0x000022CC       LI R3 0x0000A000
0x000022D4       LI R4 KERNEL_FLAGS
0x000022DC       BL map_page

0x000022E4       LI R2 0x0000B000      ; add page (number is page table entry one) tasks data
0x000022EC       LI R3 0x0000B000
0x000022F4       LI R4 KERNEL_FLAGS
0x000022FC       BL map_page

0x00002304       LI R2 0x0000C000      ; add page (number is page table entry one) tasks data
0x0000230C       LI R3 0x0000C000
0x00002314       LI R4 KERNEL_FLAGS
0x0000231C       BL map_page

0x00002324       LI R2 0x00015000      ; page for BMI buffers for NSFS (write) - 4K each
0x0000232C       LI R3 0x00015000
0x00002334       LI R4 KERNEL_FLAGS
0x0000233C       BL map_page

0x00002344       LI R2 0x00016000      ; page for BMI buffers for NSFS (read) - 4K each
0x0000234C       LI R3 0x00016000
0x00002354       LI R4 KERNEL_FLAGS
0x0000235C       BL map_page

0x00002364       LI R2 0x00017000      ; page for BMI buffers for NSFS (read) - 4K each
0x0000236C       LI R3 0x00017000
0x00002374       LI R4 KERNEL_FLAGS
0x0000237C       BL map_page




    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x00002384       LI R2 0x00100000      ; UART physical and virtual base
0x0000238C       LI R3 0x00100000
0x00002394       LI R4 KERNEL_FLAGS
0x0000239C       BL map_page

0x000023A4       LI R2 0x00101000      ; PIT physical and virtual base
0x000023AC       LI R3 0x00101000
0x000023B4       LI R4 KERNEL_FLAGS
0x000023BC       BL map_page

0x000023C4       LI R2 0x00102000      ; PIC physical and virtual base
0x000023CC       LI R3 0x00102000
0x000023D4       LI R4 KERNEL_FLAGS
0x000023DC       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x000023E4       LI R12 PAGE_ALLOC_BASE
0x000023EC       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x000023F4       CMP R12 R7
0x000023F8       BGE map_common_dynamic_done
0x00002400       MOV R2 R12
0x00002404       MOV R3 R12
0x00002408       LI R4 KERNEL_FLAGS
0x00002410       BL map_page
0x00002418       LI R6 PAGE_SIZE
0x00002420       ADD R12 R12 R6
0x00002424       B map_common_dynamic_loop
map_common_dynamic_done:

0x0000242C       POP R12
0x00002430       POP LR
0x00002434       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R4
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002438       PUSH R5
0x0000243C       PUSH R6
0x00002440       SHR R5 R2 12               ; VPN
0x00002444       SHL R5 R5 2                ; page-table byte offset
0x00002448       OR R6 R3 R4                ; PTE = PA page base | flags
0x0000244C       STW R6 [R1 + R5]
0x00002450       POP R6
0x00002454       POP R5
0x00002458       RET

map_page_rt:
    ; Runtime page-table update. Same ABI as map_page, but also invalidates
    ; the cached translation for R2 so permission changes take effect now.
0x0000245C       PUSH R5
0x00002460       PUSH R6
0x00002464       SHR R5 R2 12               ; VPN
0x00002468       SHL R5 R5 2                ; page-table byte offset
0x0000246C       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002470       STW R6 [R1 + R5]
0x00002474       INVLPG R2
0x00002478       POP R6
0x0000247C       POP R5
0x00002480       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x00002484       LI R1 0x00102000
0x0000248C       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x00002494       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x00002498       LI R1 0x00101000
0x000024A0       LI R2 2000
0x000024A8       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x000024AC       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000024B4       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x000024B8       LI R1 0x00100000
0x000024C0       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x000024C8       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x000024CC       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x000024D0       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000024D4       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000024D8       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000024DC       PUSH R1
0x000024E0       PUSH R2
0x000024E4       PUSH R3
0x000024E8       PUSH R4
0x000024EC       PUSH R5
0x000024F0       PUSH R6
0x000024F4       PUSH R7
0x000024F8       PUSH R8
0x000024FC       PUSH R9
0x00002500       PUSH R10
0x00002504       PUSH R11
0x00002508       PUSH R12
0x0000250C       PUSH R14
0x00002510       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x00002514       CSRR R1 SSCRATCH
0x00002518       PUSH R1
0x0000251C       CSRR R1 SEPC
0x00002520       PUSH R1
0x00002524       CSRR R1 SFLAGS
0x00002528       PUSH R1
0x0000252C       CSRR R1 SSTATUS
0x00002530       PUSH R1
0x00002534       CSRR R1 SCAUSE
0x00002538       PUSH R1
0x0000253C       CSRR R1 STVAL
0x00002540       PUSH R1

    ; Dispatch based on scause.
0x00002544       CSRR R1 SCAUSE
0x00002548       CMP R1 0
0x0000254C       BEQ handle_divide_zero

0x00002554       CMP R1 1
0x00002558       BEQ handle_invalid_instr

0x00002560       CMP R1 2
0x00002564       BEQ handle_page_fault

0x0000256C       CMP R1 3
0x00002570       BEQ handle_syscall

0x00002578       CMP R1 6
0x0000257C       BEQ handle_debug

0x00002584       CMP R1 16
0x00002588       BEQ handle_irq

    ; Unknown cause - halt
0x00002590       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x00002594       DEBUG 1
0x00002598       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x000025A0       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x000025A8       HLT

0x000025AC       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x000025B4       CSRR R2 STVAL

0x000025B8       CMP R2 SYS_COUNT
0x000025BC       BGE syscall_unknown

0x000025C4       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x000025CC       SHL R4 R2 2
0x000025D0       LDW R5 [R3 + R4]
0x000025D4       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000025D8       LI R1 ERR_NOSYS
0x000025E0       STW R1 [SP + TF_R1]
0x000025E4       B trap_restore

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

0x00002630       LDW R8 [SP + TF_R1]        ; user path pointer

0x00002634       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00002638       PUSH R9

0x0000263C       MOV R1 R8
0x00002640       BL copy_path_from_user
0x00002648       CMP R1 0
0x0000264C       BEQ execve_badfault

0x00002654       MOV R12 R1                ; kernel pointer to copied pathname

0x00002658       MOV R1 R12
0x0000265C       BL vfs_lookup             ; lookup inode for the file
0x00002664       CMP R1 0
0x00002668       BEQ execve_noent

0x00002670       MOV R9 R1                 ; inode*
0x00002674       LDW R1 [R9 + INODE_TYPE]
0x00002678       LI R2 INODE_DIR
0x00002680       CMP R1 R2
0x00002684       BEQ execve_noexec           ; if the inode is a directory, we cannot execute it

0x0000268C       LDW R3 [R9 + INODE_SIZE]
0x00002690       LI R4 PAGE_SIZE         ; 4096 bytes
0x00002698       CMP R3 R4
0x0000269C       BGT execve_noexec       ; if the inode size is greater than a page, we cannot execute it

0x000026A4       BL file_alloc
0x000026AC       CMP R1 0
0x000026B0       BEQ execve_nomem         ; if we cannot allocate a file for this inode, return error

0x000026B8       MOV R10 R1                ; file*
0x000026BC       MOV R1 R10
0x000026C0       MOV R2 R9
0x000026C4       LI R3 FD_FLAG_READ
0x000026CC       BL file_init            ; initialize the file structure for reading the executable

0x000026D4       BL page_alloc           ; allocate a new page for the executable code of execve program
0x000026DC       CMP R1 0
0x000026E0       BEQ execve_noexec_file

0x000026E8       MOV R11 R1                ; new code page PA for execve program

; macro: GET_CURR_TASK_IDX R4    ; get current task index
0x000026EC   LI R1 CURRENT_TASK
0x000026F4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000026F8   LI R1 TASK_SIZE
0x00002700   MUL R3 R4 R1
0x00002704   LI R5 tasks
0x0000270C   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12, R5 ; preserve old exec code page PA for rollback / cleanup
0x00002710   LDW R12 [R5 + TASK_CODE_PAGE]
; macro: TASK_GET_PTBR R1, R5       ; R1 = PTBR of current task
0x00002714   LDW R1 [R5 + TASK_PTBR]
0x00002718       LI R2 USER_CODE_VA         ; R2 = code page VA for execve program
0x00002720       MOV R3 R11                 ; R3 = code page PA for execve program
0x00002724       LI R4 USER_RW              ; R4 = temporary RW permissions so we can load the page
0x0000272C       BL map_page_rt             ; runtime map executable page RW at USER_CODE_VA for loading

; macro: TASK_GET_DATA_PAGE R1, R5  ; get data page PA for current task
0x00002734   LDW R1 [R5 + TASK_DATA_PAGE]
0x00002738       CMP R1 0
0x0000273C       BEQ execve_data_ok         ; if the task has no data page, skip clearing it
0x00002744       LI R3 PAGE_SIZE
0x0000274C       BL mem_zero                ; zero the current task data page before execve starts

execve_data_ok:

0x00002754       MOV R1 R10              ; file* of execve program
0x00002758       LI R2 USER_CODE_VA      ; VA of code page for execve program
0x00002760       LI R3 PAGE_SIZE         ; size of code page for execve program
0x00002768       BL file_read            ; load executable into USER_CODE_VA
0x00002770       CMP R1 0
0x00002774       BLT execve_read_fail    ; if read fails, restore old exec code page and return error

0x0000277C       MOV R1 R10              ; file* of execve program
0x00002780       BL file_put             ; release file resources after successful load

; macro: GET_CURR_TASK_IDX R4    ; this was real mistake here! I forgot to retore current task ptr
0x00002788   LI R1 CURRENT_TASK
0x00002790   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4     ; reload task ptr after calls that may clobber caller-saved R5
0x00002794   LI R1 TASK_SIZE
0x0000279C   MUL R3 R4 R1
0x000027A0   LI R5 tasks
0x000027A8   ADD R5 R5 R3
                            ; we also added INVLPG - for good! - history comments
    ; commit new exec state after successful file load
0x000027AC       LI R1 USER_CODE_VA
; macro: TASK_SET_PC R5, R1              ; start execution at USER_CODE_VA
0x000027B4   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5, R11      ; remember physical page backing this user code
0x000027B8   STW R11 [R5 + TASK_CODE_PAGE]
0x000027BC       LI R1 USER_STACK_TOP
; macro: TASK_SET_USP R5, R1             ; reset user stack pointer
0x000027C4   STW R1 [R5 + TASK_USP]
0x000027C8       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5, R1           ; reset program break into the task's data page
0x000027D0   STW R1 [R5 + TASK_BREAK]

    ; Remap the new code page read-only before handing control over
; macro: TASK_GET_PTBR R1, R5            ; get PTBR of current task
0x000027D4   LDW R1 [R5 + TASK_PTBR]
0x000027D8       LI R2 USER_CODE_VA              ; VA of code page for execve program
0x000027E0       MOV R3 R11                      ; PA of code page for execve program
0x000027E4       LI R4 KERNEL_USER_ALL
0x000027EC       BL map_page_rt                  ; switch the new code page from RW to RX

   ; DEBUG 2

0x000027F4       CMP R12 0                       ; R12 = old code page PA for execve program from task metadata
0x000027F8       BEQ execve_commit_done          ; if no previous code page, skip freeing it
0x00002800       MOV R1 R12
0x00002804       BL page_put                    ; free the old exec code page now that the new one is committed

execve_commit_done:
    ; Build a fresh Unix-style initial stack:
    ;   [argc][argv pointers...][NULL][string data...]
    ; The new program can read argc/argv from the stack, and we also mirror
    ; argc/argv into R1/R2 for convenience.

0x0000280C       POP R4                         ; remember argv ptr from start of syscall_execve
0x00002810       LI R6 0                        ; R6 = argc counter

    ; Step 1: Count argc - walk on argv ptrs count argc till  we find NULL check above
0x00002818       MOV R7 R4
execve_argv_count_loop:
0x0000281C       CMP R7 0
0x00002820       BEQ execve_argv_count_done
0x00002828       LDW R8 [R7]
0x0000282C       CMP R8 0
0x00002830       BEQ execve_argv_count_done

0x00002838       CMP R6 16                      ;MAX argc count
0x0000283C       BGE execve_badfault

0x00002844       ADD R6 R6 1
0x00002848       ADD R7 R7 4
0x0000284C       B execve_argv_count_loop

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
0x00002854       LI  R5 USER_STACK_TOP

    ;-------------------------------------------------------------
    ; Temporary kernel array for argv pointers.
    ; argv_tmp[16]
    ;-------------------------------------------------------------
0x0000285C       LI  R11 execve_tmp_argv

    ;-------------------------------------------------------------
    ; Copy strings in reverse order so they naturally pack downward.
    ;-------------------------------------------------------------
0x00002864       MOV R7 R6
0x00002868       SUB R7 R7 1             ; [argc]-1

execve_copy_reverse:        ; R7(i) = (argc-1 ... 0)
0x0000286C       LI  R8 -1
0x00002874       CMP R7 R8
0x00002878       BEQ execve_strings_done

    ; source string = argv[i] starting from last arg string
0x00002880       MOV R8 R7
0x00002884       SHL R8 R8 2             ;R7(i)*4+argv ptr => R9(&argv[i])
0x00002888       ADD R9 R4 R8
0x0000288C       LDW R10 [R9]            ;get string ptr from last argv[argc-1] (in first iteration)

    ;-------------------------------------------------------------
    ; strlen()
    ; R12 = length including terminating NUL
    ;-------------------------------------------------------------
0x00002890       LI R12 0                ;str len ctr - compute this argv string len (+ 0)

execve_strlen:

0x00002898       LDB R2 [R10 + R12]
0x0000289C       ADD R12 R12 1
0x000028A0       CMP R2 0
0x000028A4       BNE execve_strlen

    ; reserve space - on user stack top this argv string destination

0x000028AC       SUB R5 R5 R12               ; R5 dest addres argv string copy to gets updated by lenght of each string
                                ; to be copied to tmp

    ; remember destination pointer
0x000028B0       MOV R8 R7
0x000028B4       SHL R8 R8 2                 ;R7 argv string number in argv array
0x000028B8       ADD R9 R11 R8               ;r9=&temp argv[i]  which is = R7(i)*4+&temp argv[] array storage
0x000028BC       STW R5 [R9]                 ;R5->[R9] string pointer on user stack

    ; memcpy()
0x000028C0       LI R8 0

execve_copy_string:             ; first copy strings ptrs from (argv array) to temp storage
                                ; from last string to first - opposite order
0x000028C8       LDB R2 [R10 + R8]           ; R10 execv argv &string[i]  (last to first)
0x000028CC       STB R2 [R5 + R8]            ; R5 same in tmp

0x000028D0       CMP R2 0
0x000028D4       BEQ execve_copy_done

0x000028DC       ADD R8 R8 1                 ; to next char in string
0x000028E0       B execve_copy_string

execve_copy_done:

0x000028E8       SUB R7 R7 1                 ; to copy next string
0x000028EC       B execve_copy_reverse

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
0x000028F4       MOV R7 R6
0x000028F8       ADD R7 R7 2

0x000028FC       MOV R8 R7
0x00002900       SHL R8 R8 2

0x00002904       SUB R5 R5 R8            ;update R5 by stack words

    ;-------------------------------------------------------------
    ; R5 now becomes initial user stack pointer.
    ;-------------------------------------------------------------

0x00002908       STW R6 [R5]             ; put argc to user stack see picture above (Reserve space for:)

0x0000290C       ADD R9 R5 4             ; R9 - move 'writing head' to next element argv in user stack
                            ; R5 - initial user stack pointer
    ;-------------------------------------------------------------
    ; argv data copied. now - Copy argv pointers
    ;-------------------------------------------------------------
0x00002910       LI R7 0

execve_copy_argv:

0x00002918       CMP R7 R6
0x0000291C       BEQ execve_copy_argv_done

0x00002924       MOV R8 R7
0x00002928       SHL R8 R8 2              ; R7 argv index

0x0000292C       LDW R12 [R11 + R8]       ; we copy stings pointers here (not actual strings!)
                             ; R11 - &execve_tmp_argv
0x00002930       STW R12 [R9 + R8]        ; R9 - write head on user stack

0x00002934       ADD R7 R7 1
0x00002938       B execve_copy_argv

execve_copy_argv_done:

    ; argv[argc] = NULL
0x00002940       MOV R8 R6
0x00002944       SHL R8 R8 2
0x00002948       ADD R10 R9 R8

0x0000294C       LI R12 0
0x00002954       STW R12 [R10]               ; write NuLL - finish form user stack frame (arguments part!)

    ;-------------------------------------------------------------
    ; Prepare trapframe for new process.
    ;-------------------------------------------------------------

0x00002958       STW R6 [SP + TF_R1]      ; argc

0x0000295C       MOV R1 R9
0x00002960       STW R1 [SP + TF_R2]      ; argv

0x00002964       LI R1 0
0x0000296C       STW R1 [SP + TF_R3]      ; envp

0x00002970       STW R5 [SP + TF_USP]     ; initial user SP


    ; Prepare a fresh user register state for the new program.
0x00002974       LI R1 0
0x0000297C       STW R1 [SP + TF_R4]
0x00002980       STW R1 [SP + TF_R5]
0x00002984       STW R1 [SP + TF_R6]
0x00002988       STW R1 [SP + TF_R7]
0x0000298C       STW R1 [SP + TF_R8]
0x00002990       STW R1 [SP + TF_R9]
0x00002994       STW R1 [SP + TF_R10]
0x00002998       STW R1 [SP + TF_R11]
0x0000299C       STW R1 [SP + TF_R12]
0x000029A0       LI R1   USER_CODE_VA               ; user execve program entry point
0x000029A8       STW R1 [SP + TF_SEPC]              ; set SEPC to the new program entry point

0x000029AC       B trap_restore                     ; restore kernel trapframe and start user execution at user_code_va

; as it should be clear
; if fail occured we rollback depending at what stage fail occured and free used resources
; then we exit back to child process with fail exit code
execve_read_fail:
0x000029B4       MOV R1 R11
0x000029B8       BL page_put                    ; put-free the failed new code page

; macro: GET_CURR_TASK_IDX R4
0x000029C0   LI R1 CURRENT_TASK
0x000029C8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4           ; reload task ptr before restoring USER_CODE_VA mapping
0x000029CC   LI R1 TASK_SIZE
0x000029D4   MUL R3 R4 R1
0x000029D8   LI R5 tasks
0x000029E0   ADD R5 R5 R3

0x000029E4       CMP R12 0
0x000029E8       BEQ execve_restore_no_prev
; macro: TASK_GET_PTBR R1, R5
0x000029F0   LDW R1 [R5 + TASK_PTBR]
0x000029F4       LI R2 USER_CODE_VA
0x000029FC       MOV R3 R12
0x00002A00       LI R4 USER_RX
0x00002A08       BL map_page_rt                ; restore previous exec page mapping at USER_CODE_VA
0x00002A10       MOV R1 R12
; macro: TASK_SET_CODE_PAGE R5, R12    ; restore previous exec code page pointer
0x00002A14   STW R12 [R5 + TASK_CODE_PAGE]
0x00002A18       B execve_restore_done

execve_restore_no_prev:
; macro: TASK_GET_PTBR R1, R5
0x00002A20   LDW R1 [R5 + TASK_PTBR]
0x00002A24       LI R2 USER_CODE_VA
0x00002A2C       LI R3 0
0x00002A34       LI R4 0
0x00002A3C       BL map_page_rt                ; unmap USER_CODE_VA if there was no previous code page
0x00002A44       LI R1 0
; macro: TASK_SET_CODE_PAGE R5, R1
0x00002A4C   STW R1 [R5 + TASK_CODE_PAGE]

execve_restore_done:
0x00002A50       MOV R1 R10
0x00002A54       BL file_put

0x00002A5C       POP R1                      ;save stack
0x00002A60       LI R1 ERR_NOEXEC
0x00002A68       STW R1 [SP + TF_R1]
0x00002A6C       B trap_restore

execve_nomem_file:
0x00002A74       MOV R1 R10
0x00002A78       BL file_put

0x00002A80       POP R1
0x00002A84       LI R1 ERR_NOMEM
0x00002A8C       STW R1 [SP + TF_R1]
0x00002A90       B trap_restore

execve_nomem:
0x00002A98       POP R1
0x00002A9C       LI R1 ERR_NOMEM
0x00002AA4       STW R1 [SP + TF_R1]
0x00002AA8       B trap_restore

execve_noexec_file:

0x00002AB0       MOV R1 R10
0x00002AB4       BL file_put
execve_noexec:
0x00002ABC       POP R1
0x00002AC0       LI R1 ERR_NOEXEC
0x00002AC8       STW R1 [SP + TF_R1]
0x00002ACC       B trap_restore

execve_noent:
0x00002AD4       POP R1
0x00002AD8       LI R1 ERR_NOENT
0x00002AE0       STW R1 [SP + TF_R1]
0x00002AE4       B trap_restore

execve_badfault:
0x00002AEC       POP R1
0x00002AF0       LI R1 ERR_FAULT
0x00002AF8       STW R1 [SP + TF_R1]
0x00002AFC       B trap_restore

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
    ; + added multipage code support
    ; overview and why its better then previous what serous obstacles it is able to overcome

0x00003210       LDW R8 [SP + TF_R1]        ; user path pointer
0x00003214       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00003218       MOV R11 R9                 ; save to R11

0x0000321C       LI  R1 exec_path
0x00003224       MOV R2 R8
0x00003228       LI  R3 EXEC_MAX_PATH
0x00003230       BL copy_user_string        ;copy path string to ws
0x00003238       CMP R1 0
0x0000323C       BEQ execve_badfault

    ;init execve ws
0x00003244       LI R1 exec_argc
0x0000324C       LI R2 0
0x00003254       STW R2 [R1]

    ;count argc

0x00003258       MOV R8 R9               ; user argv
0x0000325C       LI  R6 0                ; argc
;count ptrs in array of ptrs argv till 0 -null end
argc_loop:
0x00003264       CMP R8 0                ;if no argv 0-null
0x00003268       BEQ argc_done
0x00003270       LDW R3 [R8]
0x00003274       CMP R3 0                ;if end
0x00003278       BEQ argc_done
0x00003280       CMP R6 EXEC_MAX_ARGS    ;if too much MAX argc count
0x00003284       BGE exec_badfault
0x0000328C       ADD R6 R6 1
0x00003290       ADD R8 R8 4
0x00003294       B argc_loop
argc_done:
0x0000329C       LI R1 exec_argc         ;store it to ws
0x000032A4       STW R6 [R1]

0x000032A8       MOV R9 R6               ;R9 argc R11 user argv pointer
0x000032AC       MOV R8 R11
0x000032B0       BL  copy_argv_strings   ;fill arrays in ws from argvs
0x000032B8       CMP R1 0
0x000032BC       BNE exec_fail

0x000032C4       LI R1 exec_path
    ; load exec image to allocted memory
    ; map_rt pages
0x000032CC       BL exec_load_binary
0x000032D4       CMP R1 0
0x000032D8       BEQ exec_fail

0x000032E0       MOV R11 R1        ; new code page
0x000032E4       MOV R12 R2        ; old code page
0x000032E8       BL exec_build_stack_image
0x000032F0       CMP R1 0
0x000032F4       BNE exec_rollback

0x000032FC       MOV R1 R11
0x00003300       MOV R2 R12

0x00003304       B exec_commit_image

exec_badfault:
0x0000330C       NOP
exec_fail:
0x00003310       NOP
exec_rollback:
0x00003314       LI R1 ERR_FAULT
0x0000331C       STW R1 [SP + TF_R1]
0x00003320       B trap_restore
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

0x00003328       MOV R11 R1              ; new page
0x0000332C       MOV R12 R2              ; old page

; macro: GET_CURR_TASK_IDX R4
0x00003330   LI R1 CURRENT_TASK
0x00003338   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x0000333C   LI R1 TASK_SIZE
0x00003344   MUL R3 R4 R1
0x00003348   LI R5 tasks
0x00003350   ADD R5 R5 R3

0x00003354       LI  R1 exec_stack_used
0x0000335C       LDW R8 [R1]
0x00003360       LI  R9 USER_STACK_TOP
0x00003368       SUB R9 R9 R8            ; final user SP
0x0000336C       MOV R1 R9               ;  R2->R9 len R8 - cpy our image for stack
0x00003370       LI  R2 exec_stack_image
0x00003378       MOV R3 R8
0x0000337C       BL memcpy

0x00003384       LI R1 USER_CODE_VA      ; commit task state:
; macro: TASK_SET_PC R5,R1       ; PC starts to USER_CODE_VA
0x0000338C   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5,R11 ; set new code page (tab+pages)
0x00003390   STW R11 [R5 + TASK_CODE_PAGE]
0x00003394       MOV R1 R9
; macro: TASK_SET_USP R5,R1        ; set USP
0x00003398   STW R1 [R5 + TASK_USP]
0x0000339C       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5,R1      ; set BRK
0x000033A4   STW R1 [R5 + TASK_BREAK]

    ; Make sure the task's fixed user stack page is still mapped RW before
    ; returning to user mode. execve rewrites the stack contents, but the
    ; page-table entry must remain valid even if the task was previously
    ; switched through another path.
; macro: TASK_GET_PTBR R2,R5
0x000033A8   LDW R2 [R5 + TASK_PTBR]
; macro: TASK_GET_USTACK_PAGE R3,R5
0x000033AC   LDW R3 [R5 + TASK_USTACK_PAGE]
0x000033B0       CMP R3 0
0x000033B4       BEQ exec_commit_skip_stack_map
    ; ---- remap new code pages to RW ---- don know why
0x000033BC       MOV R1 R11
0x000033C0       LI R3 USER_CODE_VA
0x000033C8       LI R4 USER_RW
0x000033D0       BL pages_map_table

  ;  LI R2 USER_STACK_VA
  ;  LI R4 USER_RW
  ;  BL map_page_rt

exec_commit_skip_stack_map:

; macro: TASK_GET_PTBR R2,R5
0x000033D8   LDW R2 [R5 + TASK_PTBR]
0x000033DC       MOV R1 R11
0x000033E0       LI R3 USER_CODE_VA
0x000033E8       LI R4 KERNEL_USER_ALL
0x000033F0       BL pages_map_table

;    LI R2 USER_CODE_VA
;    MOV R3 R11
;    LI R4 KERNEL_USER_ALL   ; map code page RX subject to permissions on X (now all X)
;    BL map_page_rt

0x000033F8       CMP R12 0               ; free old pa page (R12) if have
0x000033FC       BEQ no_old_page

0x00003404       MOV R1 R12
0x00003408       BL pages_free_table     ; ---- free old codepage (table and pages) ----

   ; BL page_put             ; free page
no_old_page:

0x00003410       LI  R1 exec_argc
0x00003418       LDW R2 [R1]
0x0000341C       STW R2 [SP+TF_R1]

0x00003420       MOV R1 R9
0x00003424       ADD R1 R1 4
0x00003428       STW R1 [SP+TF_R2]       ; user sp with image on top + 4 so it points to &argv image

0x0000342C       LI R1 0                 ; envp
0x00003434       STW R1 [SP+TF_R3]

0x00003438       STW R9 [SP+TF_USP]      ; user sp

0x0000343C       LI R1 0
0x00003444       STW R1 [SP+TF_R4]
0x00003448       STW R1 [SP+TF_R5]
0x0000344C       STW R1 [SP+TF_R6]
0x00003450       STW R1 [SP+TF_R7]
0x00003454       STW R1 [SP+TF_R8]
0x00003458       STW R1 [SP+TF_R9]
0x0000345C       STW R1 [SP+TF_R10]
0x00003460       STW R1 [SP+TF_R11]
0x00003464       STW R1 [SP+TF_R12]

0x00003468       LI R1 USER_CODE_VA
0x00003470       STW R1 [SP+TF_SEPC]

  ;  POP R12
  ;  POP R11
  ;  POP R10
  ;  POP R9
  ;  POP R8
  ;  POP LR

0x00003474       B trap_restore



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
0x0000347C       PUSH LR
0x00003480       PUSH R8
0x00003484       PUSH R9
0x00003488       PUSH R10
0x0000348C       PUSH R11
0x00003490       PUSH R12

0x00003494       LI   R1 exec_argc   ;argc
0x0000349C       LDW  R6 [R1]

0x000034A0       MOV  R7 R6          ;pointer_bytes = (argc+2)*4
0x000034A4       ADD  R7 R7 2
0x000034A8       SHL  R7 R7 2

0x000034AC       LI   R1 exec_strings_used   ; strings blob len
0x000034B4       LDW  R8 [R1]

    ;----------------------------------------------------------
    ; total = pointer_bytes(len argv ptr array + 4b argc) + string_bytes(len string blobs)
    ;----------------------------------------------------------

0x000034B8       ADD  R9 R7 R8
    ; check for MAX
0x000034BC       LI   R1 EXEC_STACK_SIZE
0x000034C4       CMP  R9 R1
0x000034C8       BGT  exec_stack_nomem

0x000034D0       LI   R1 exec_stack_used     ; save used size
0x000034D8       STW  R9 [R1]

0x000034DC       LI   R10 exec_stack_image   ;stack base for image
    ; building image for stack as on picture
0x000034E4       STW  R6 [R10]   ;argc

    ; copy string blob
0x000034E8       MOV  R1 R10
0x000034EC       ADD  R1 R1 R7   ; skip room for pointer_bytes see picture
0x000034F0       LI   R2 exec_strings
0x000034F8       MOV  R3 R8      ; blob len
0x000034FC       BL   memcpy

    ;----------------------------------------------------------
    ; future user addresses
    ;----------------------------------------------------------

0x00003504       LI   R11 USER_STACK_TOP
0x0000350C       SUB  R11 R11 R9             ; r9 total image len, R11 start address image in the user stack
0x00003510       MOV  R12 R11
0x00003514       ADD  R12 R12 R7             ; r12 pointer bytes ptr in image in stack - start of string blob

    ;----------------------------------------------------------
    ; argv table build
    ;----------------------------------------------------------

0x00003518       ADD  R10 R10 4              ; argv[0] starts after argc
0x0000351C       LI   R4 exec_argv_offsets   ; args offsetss array
0x00003524       LI   R5 0
argv_loop:
0x0000352C       CMP  R5 R6                  ; argc
0x00003530       BEQ  argv_done              ; if finished
0x00003538       MOV  R1 R5
0x0000353C       SHL  R1 R1 2
0x00003540       LDW  R2 [R4+R1]             ; get arg[i] offset
0x00003544       ADD  R2 R2 R12              ; compute R2 - blobs string adress for this arg[i]
0x00003548       STW  R2 [R10+R1]            ; store this address to argv array in image
0x0000354C       ADD  R5 R5 1
0x00003550       B    argv_loop
argv_done:
0x00003558       MOV  R1 R6
0x0000355C       SHL  R1 R1 2

0x00003560       LI   R2 0
0x00003568       STW  R2 [R10+R1]            ; put null here: argv[argc] = NULL
    ;success
0x0000356C       LI   R1 0
0x00003574       POP  R12
0x00003578       POP  R11
0x0000357C       POP  R10
0x00003580       POP  R9
0x00003584       POP  R8
0x00003588       POP  LR
0x0000358C       RET

exec_stack_nomem:
0x00003590       LI   R1 ERR_NOMEM
0x00003598       POP  R12
0x0000359C       POP  R11
0x000035A0       POP  R10
0x000035A4       POP  R9
0x000035A8       POP  R8
0x000035AC       POP  LR
0x000035B0       RET

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
0x000035B4       PUSH LR
0x000035B8       PUSH R7
0x000035BC       PUSH R8
0x000035C0       PUSH R9
0x000035C4       PUSH R10
0x000035C8       PUSH R11
0x000035CC       PUSH R12

0x000035D0       BL vfs_lookup   ; lookup inode for the file
0x000035D8       CMP R1 0
0x000035DC       BEQ load_noent
0x000035E4       MOV R9 R1

0x000035E8       LDW R1 [R9 + INODE_TYPE]    ;check inode type/size
0x000035EC       LI R2 INODE_DIR
0x000035F4       CMP R1 R2
0x000035F8       BEQ load_noexec
0x00003600       LDW R3 [R9 + INODE_SIZE]
0x00003604       LI R4 MAX_APP_SIZE
0x0000360C       CMP R3 R4
0x00003610       BGT load_noexec

0x00003618       BL file_alloc               ;allocate file
0x00003620       CMP R1 0
0x00003624       BEQ load_nomem
0x0000362C       MOV R10 R1                  ; savr file ptr R10
0x00003630       MOV R1 R10
0x00003634       MOV R2 R9
0x00003638       LI R3 FD_FLAG_READ
0x00003640       BL file_init

    ; ---- allocate table and code pages ----
    ; makes table page and few pages up on file size
0x00003648       LDW R1 [R9 + INODE_SIZE]
    ;MOV R1 R6                  ; file size
0x0000364C       BL pages_allocate_table
0x00003654       CMP R1 0
0x00003658       BEQ load_file_fail

0x00003660       MOV R11 R1                 ; new table PA
0x00003664       MOV R12 R2                 ; count (not needed further)

    ; ---- map pages RW ----
; macro: GET_CURR_TASK_IDX R4        ;current task
0x00003668   LI R1 CURRENT_TASK
0x00003670   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x00003674   LI R1 TASK_SIZE
0x0000367C   MUL R3 R4 R1
0x00003680   LI R5 tasks
0x00003688   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12,R5   ; save old pa code page from this task to R12
0x0000368C   LDW R12 [R5 + TASK_CODE_PAGE]

   ; TASK_GET_PTBR R1,R5
   ; LI R2 USER_CODE_VA
   ; MOV R3 R11                 ;new pa code page
   ; LI R4 USER_RW
   ; BL map_page_rt             ;map it for loading to USER_CODE_VA

; macro: TASK_GET_PTBR R2, R5        ; PTBR
0x00003690   LDW R2 [R5 + TASK_PTBR]
0x00003694       LI R3 USER_CODE_VA          ; starting new code page VA
0x0000369C       LI R4 USER_RW               ; mapping flAGS
0x000036A4       MOV R1 R11                  ; new table PA (with pa pages)
0x000036A8       BL pages_map_table

    ; ---- zero data page ----
; macro: TASK_GET_DATA_PAGE R1,R5    ; tasks va data_page
0x000036B0   LDW R1 [R5 + TASK_DATA_PAGE]
0x000036B4       CMP R1 0
0x000036B8       BEQ load_read
0x000036C0       LI R3 PAGE_SIZE
0x000036C8       BL mem_zero                 ; clean task data_page

load_read:
0x000036D0       MOV R1 R10                  ; file* with program
0x000036D4       LI  R2 USER_CODE_VA
0x000036DC       LDW R3 [R9 + INODE_SIZE]    ; file size
0x000036E0       BL file_read
0x000036E8       CMP R1 0
0x000036EC       BLT load_read_fail

0x000036F4       MOV R1 R10                  ;loaded release file*
0x000036F8       BL file_put
    ; all loaedd R1 - new code page pa tab, R2 - old code page pa tab
0x00003700       MOV R1 R11
0x00003704       MOV R2 R12

exec_lb_exit:                   ;common! exit!
0x00003708       POP R12
0x0000370C       POP R11
0x00003710       POP R10
0x00003714       POP R9
0x00003718       POP R8
0x0000371C       POP R7
0x00003720       POP LR
0x00003724       RET
; in error generally depending on state rollback allocated resources
load_read_fail:
    ; in this case release file and pa code page
0x00003728       MOV R1 R10
0x0000372C       BL file_put
0x00003734       MOV R1 R11
0x00003738       BL page_put        ;free page
0x00003740       LI R1 0
0x00003748       LI R2 ERR_IO
0x00003750       B  exec_lb_exit

load_file_fail:
0x00003758       MOV R1 R10
0x0000375C       BL file_put

load_nomem:
0x00003764       LI R1 0
0x0000376C       LI R2 ERR_NOMEM
0x00003774       B  exec_lb_exit

load_noexec:
0x0000377C       MOV R1 R10
0x00003780       CMP R1 0
0x00003784       BEQ noexec_skip
0x0000378C       BL file_put

noexec_skip:
0x00003794       LI R1 0
0x0000379C       LI R2 ERR_NOEXEC
0x000037A4       B  exec_lb_exit

load_noent:
0x000037AC       LI R1 0
0x000037B4       LI R2 ERR_NOENT
0x000037BC       B  exec_lb_exit

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

0x000037C4       PUSH LR
0x000037C8       PUSH R7
0x000037CC       PUSH R8
0x000037D0       PUSH R9
0x000037D4       PUSH R10
0x000037D8       PUSH R11
0x000037DC       PUSH R12
    ;init this at first
0x000037E0       LI R1 exec_strings_used
0x000037E8       LI R2 0
0x000037F0       STW R2 [R1]

0x000037F4       LI   R11 exec_strings      ; destination blob
0x000037FC       LI   R12 0                 ; current offset
0x00003804       LI   R7 0                  ; argv index
                               ;  R8 = user argv[]
                               ;  R9 = argc
exec_capture_next_arg:
    ; finished?
0x0000380C       CMP  R7 R9
0x00003810       BEQ  exec_capture_done     ; if all agvs processed

    ;---------------------------------------------
    ; load argv[i] (ptr to string)
    ;---------------------------------------------
0x00003818       LDW  R10 [R8]

0x0000381C       CMP  R10 0
0x00003820       BEQ  exec_capture_fault     ;if argv[i]==null

    ;---------------------------------------------
    ; save offset
    ;
    ; exec_argv_offsets[i]=current_offset (in R12)
    ;---------------------------------------------
0x00003828       LI   R1 exec_argv_offsets
0x00003830       MOV  R2 R7  ;i
0x00003834       SHL  R2 R2 2
0x00003838       ADD  R1 R1 R2
0x0000383C       STW  R12 [R1]

exec_copy_string:
    ;---------------------------------------------
    ; copy one character r10 argv[i] (ptr to string) R11 ptr to exec strings
    ;---------------------------------------------
0x00003840       LDB  R3 [R10]
0x00003844       STB  R3 [R11]
0x00003848       ADD  R10 R10 1
0x0000384C       ADD  R11 R11 1
0x00003850       ADD  R12 R12 1
    ; blob overflow?
0x00003854       LI   R1 EXEC_MAX_STRINGS
0x0000385C       CMP  R12 R1
0x00003860       BGT  exec_capture_fault
0x00003868       CMP  R3 0
0x0000386C       BNE  exec_copy_string           ; end of string?
0x00003874       ADD  R8 R8 4    ;to next argv[] string
0x00003878       ADD  R7 R7 1    ;i=i+1
0x0000387C       B    exec_capture_next_arg

exec_capture_done:
0x00003884       LI   R1 exec_strings_used
0x0000388C       STW  R12 [R1]           ; current offset after last string
0x00003890       LI  R1 0
0x00003898       POP R12
0x0000389C       POP R11
0x000038A0       POP R10
0x000038A4       POP R9
0x000038A8       POP R8
0x000038AC       POP R7
0x000038B0       POP LR
0x000038B4       RET
exec_capture_fault:
0x000038B8       LI   R1 ERR_FAULT
0x000038C0       POP R12
0x000038C4       POP R11
0x000038C8       POP R10
0x000038CC       POP R9
0x000038D0       POP R8
0x000038D4       POP R7
0x000038D8       POP LR
0x000038DC       RET

syscall_fork:
    ;================================================================
    ; fork()
    ; Returns child PID in the parent and 0 in the child.
    ; This clones the current task, duplicating its address space and
    ; user-writable state while preserving a new independent child thread.
    ;================================================================

0x000038E0       BL task_clone_current
0x000038E8       CMP R1 0
0x000038EC       BEQ fork_fail

    ; We return child PID to the parent via the trapframe.
; macro: TASK_GET_PID R2, R1
0x000038F4   LDW R2 [R1 + TASK_PID]
0x000038F8       STW R2 [SP + TF_R1]
0x000038FC       B trap_restore

fork_fail:
0x00003904       LI R1 ERR_NOMEM
0x0000390C       STW R1 [SP + TF_R1]
0x00003910       B trap_restore

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x00003918       LI R1 0
0x00003920       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00003924       B schedule_and_switch
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
0x0000392C       LDW R8 [SP + TF_R1]        ; R8 = exit code

; macro: GET_CURR_TASK_IDX R2
0x00003930   LI R1 CURRENT_TASK
0x00003938   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x0000393C   LI R1 TASK_SIZE
0x00003944   MUL R3 R2 R1
0x00003948   LI R5 tasks
0x00003950   ADD R5 R5 R3

    ; Store exit code in child task struct for parent to collect in waitforpid
; macro: TASK_SET_EXIT_CODE R5, R8  ; Save exit code
0x00003954   STW R8 [R5 + TASK_EXIT_CODE]

0x00003958       PUSH R5
0x0000395C       MOV R1 R5
0x00003960       BL task_close_fds          ; close all open file descriptors of this task (if any) to free file_pool resources
0x00003968       POP R5

    ; Mark this child as zombie (still exists but not runnable)
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x0000396C   LI R1 TASK_ZOMBIE
0x00003974   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00003978   LI R1 WAIT_NONE
0x00003980   STW R1 [R5 + TASK_WAIT]

    ; Wake parent if it's waiting
; macro: TASK_GET_PPID R6, R5       ; R6 = parent PID
0x00003984   LDW R6 [R5 + TASK_PPID]

    ; find parent task by PPID
0x00003988       MOV R1 R6
0x0000398C       LI R2 0                    ; Search by PID (parent's PID)
0x00003994       BL task_find               ; R1 = found parent task*
0x0000399C       CMP R1 0
0x000039A0       BEQ no_parent_waiting
0x000039A8       MOV R7 R1                  ; R7 = parent task*
0x000039AC       MOV R11 R2                 ; save parent task index for bitmask

    ;Check if parent is waiting for this child
; macro: TASK_GET_WAIT_CHILD R8, R7 ; Child PID that parent R7 ptr is waiting for
0x000039B0   LDW R8 [R7 + TASK_WAIT_CHILD]
; macro: TASK_GET_PID R9, R5        ; This child's R5 ptr PID
0x000039B4   LDW R9 [R5 + TASK_PID]

0x000039B8       LI R10 -1
0x000039C0       CMP R8 R10                 ; if parent is waiting for any child (-1), then wake it up
0x000039C4       BEQ wake_parent            ;

0x000039CC       CMP R8 R9
0x000039D0       BNE no_parent_waiting      ; parent is waiting for a different child, do not wake it up

wake_parent:
    ; Find parent's task index for bitmask
    ; we already have parent task in R11

0x000039D8       LI R9 1
0x000039E0       SHL R9 R9 R11               ; bit for parent task

0x000039E4       LI R1 child_waitq
0x000039EC       MOV R2 R9
0x000039F0       BL waitq_wake_bitmask       ;unblock parent task waiting for this child

no_parent_waiting:
0x000039F8       B schedule_and_switch

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
0x00003A00       LDW R8 [SP + TF_R1]        ; R8 = pid to wait for
0x00003A04       LDW R9 [SP + TF_R2]        ; R9 = status pointer

    ; Validate status pointer
0x00003A08       CMP R9 0
0x00003A0C       BEQ waitpid_validate_done
0x00003A14       MOV R1 R9
0x00003A18       LI R2 4
0x00003A20       LI R3 1
0x00003A28       BL user_buffer_valid_range
0x00003A30       CMP R1 1
0x00003A34       BNE waitpid_badptr

waitpid_validate_done:
; macro: GET_CURR_TASK_IDX R4
0x00003A3C   LI R1 CURRENT_TASK
0x00003A44   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003A48   LI R1 TASK_SIZE
0x00003A50   MUL R3 R4 R1
0x00003A54   LI R5 tasks
0x00003A5C   ADD R5 R5 R3
; macro: TASK_GET_PID R10, R5       ; R10 = current (parent proc) PID
0x00003A60   LDW R10 [R5 + TASK_PID]

    ; if search for any child
0x00003A64       LI  R2 -1
0x00003A6C       CMP R8 R2
0x00003A70       BNE find_child_by_pid
    ; set task_find to search for any child of this parent
0x00003A78       MOV R1 R10                  ; R1 = parent PID (PPID in child task)
0x00003A7C       LI  R2 1                    ; search by PPID
0x00003A84       BL task_find               ; R1 = found child task*
0x00003A8C       CMP R1 0
0x00003A90       BEQ waitpid_no_child        ; No any child with PPID = this parent PID found
    ;R1 child task* found
0x00003A98       B find_any_child_found
find_child_by_pid:
    ; Search for child task by PID
0x00003AA0       MOV R1 R8                  ; R1 = child PID to search for
0x00003AA4       LI R2 0                    ; Search by PID
0x00003AAC       BL task_find               ; R1 = found child task*
0x00003AB4       CMP R1 0
0x00003AB8       BEQ waitpid_no_child        ; No such child

find_any_child_found:

0x00003AC0       MOV R7 R1                   ; R7 = child task*

    ; Verify it's actually our child by its PPID fld
; macro: TASK_GET_PPID R1, R7
0x00003AC4   LDW R1 [R7 + TASK_PPID]
0x00003AC8       CMP R1 R10
0x00003ACC       BNE waitpid_no_child
    ; R7 = child task*
    ; check its state, if ZOMBIE, we can reap it and return its exit code
; macro: TASK_GET_STATE R1, R7
0x00003AD4   LDW R1 [R7 + TASK_STATE]
0x00003AD8       CMP R1 TASK_ZOMBIE
0x00003ADC       BEQ waitpid_reap_child

    ; Child running - block parent
; macro: TASK_GET_PID R1, R7
0x00003AE4   LDW R1 [R7 + TASK_PID]
; macro: TASK_SET_WAIT_CHILD R5, R1
0x00003AE8   STW R1 [R5 + TASK_WAIT_CHILD]

0x00003AEC       LI R1 child_waitq           ; child_waitq ptr
0x00003AF4       LI R2 WAIT_CHILD            ; reason
0x00003AFC       LI R3 TASK_SLEEPING         ; state to set for current task
0x00003B04       BL waitq_prepare_sleep

0x00003B0C       BL waitq_sleep_current     ; freeze the current task

    ; will resume here when child exits and wakes us up

waitpid_reap_child:
    ; Get exit code from child task
; macro: TASK_GET_EXIT_CODE R2, R7
0x00003B14   LDW R2 [R7 + TASK_EXIT_CODE]

    ; If status pointer is not NULL, write exit code to user space
0x00003B18       CMP R9 0
0x00003B1C       BEQ waitpid_reap_done

0x00003B24       MOV R1 R9                  ; R1 = user status pointer
0x00003B28       MOV R4 R2                  ; preserve exit code in kernel source register
0x00003B2C       LI  R2 4                   ; R2 = size of exit code
0x00003B34       BL copy_to_user            ; write exit code to user space

waitpid_reap_done:
; macro: TASK_GET_PID R10, R7       ; get child's PID
0x00003B3C   LDW R10 [R7 + TASK_PID]
0x00003B40       MOV R1 R7                  ; R1 = child task*
0x00003B44       BL task_destroy

0x00003B4C       STW R10 [SP + TF_R1]        ; save child's PID to trapframe for return
0x00003B50       B trap_restore

waitpid_no_child:
0x00003B58       LI R1 ERR_CHILD
0x00003B60       STW R1 [SP + TF_R1]
0x00003B64       B trap_restore

waitpid_badptr:
0x00003B6C       LI R1 ERR_FAULT
0x00003B74       STW R1 [SP + TF_R1]
0x00003B78       B trap_restore


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
0x00003B80       PUSH R5
0x00003B84       PUSH R6
0x00003B88       PUSH R7

0x00003B8C       MOV R5 R2                  ; Save search mode
0x00003B90       MOV R7 R1                  ; Save PID/PPID
0x00003B94       LI R2 0                    ; Task index
task_find_loop:
0x00003B9C       LI R3 MAX_TASKS
0x00003BA4       CMP R2 R3
0x00003BA8       BGE task_find_not_found

; macro: GET_TASK_PTR R4, R2
0x00003BB0   LI R1 TASK_SIZE
0x00003BB8   MUL R3 R2 R1
0x00003BBC   LI R4 tasks
0x00003BC4   ADD R4 R4 R3
; macro: TASK_GET_STATE R6, R4
0x00003BC8   LDW R6 [R4 + TASK_STATE]
0x00003BCC       CMP R6 TASK_DEAD
0x00003BD0       BEQ task_find_next         ; Skip dead tasks

    ; Search based on mode
0x00003BD8       CMP R5 0
0x00003BDC       BEQ task_find_by_pid

    ; Search by PPID
; macro: TASK_GET_PPID R6, R4
0x00003BE4   LDW R6 [R4 + TASK_PPID]
0x00003BE8       CMP R6 R7
0x00003BEC       BEQ task_find_found
0x00003BF4       B task_find_next

task_find_by_pid:
; macro: TASK_GET_PID R6, R4
0x00003BFC   LDW R6 [R4 + TASK_PID]
0x00003C00       CMP R6 R7
0x00003C04       BEQ task_find_found

task_find_next:
0x00003C0C       ADD R2 R2 1
0x00003C10       B task_find_loop

task_find_found:
0x00003C18       MOV R1 R4                  ; Return task pointer
0x00003C1C       MOV R2 R2                  ; Return task index
0x00003C20       POP R7
0x00003C24       POP R6
0x00003C28       POP R5
0x00003C2C       RET

task_find_not_found:
0x00003C30       LI R1 0
0x00003C38       POP R7
0x00003C3C       POP R6
0x00003C40       POP R5
0x00003C44       RET

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00003C48   LI R1 CURRENT_TASK
0x00003C50   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003C54   LI R1 TASK_SIZE
0x00003C5C   MUL R3 R2 R1
0x00003C60   LI R5 tasks
0x00003C68   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00003C6C   LDW R1 [R5 + TASK_PID]

0x00003C70       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00003C74       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00003C7C       LDW R1 [SP + TF_R1]
0x00003C80       STW R1 [SP + TF_R1]

0x00003C84       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00003C8C       LDW R1 [SP + TF_R1]
0x00003C90       LDW R2 [SP + TF_R2]

0x00003C94       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003C9C       CMP R1 0
0x00003CA0       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003CA8   LI R1 CURRENT_TASK
0x00003CB0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003CB4   LI R1 TASK_SIZE
0x00003CBC   MUL R3 R4 R1
0x00003CC0   LI R5 tasks
0x00003CC8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003CCC   LDW R1 [R5 + TASK_KBUF_RD_PTR]

0x00003CD0       BL vfs_open

0x00003CD8       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x00003CDC       B trap_restore

open_fail_fault:
0x00003CE4       LI R1 ERR_FAULT
0x00003CEC       STW R1 [SP + TF_R1]     ;file not opened ERR
0x00003CF0       B trap_restore


syscall_sleep:
    ;================================================================
    ; sleep(ms)
    ; R1 = milliseconds to sleep
    ;
    ; Returns:
    ;   R1 = 0 on success (slept full duration)
    ;   R1 = -1 on error (invalid time)
    ;================================================================

0x00003CF8       LDW R8 [SP + TF_R1]        ; R8 = milliseconds

0x00003CFC       CMP R8 0
0x00003D00       BLE sleep_invalid          ; must be positive

; macro: GET_CURR_TASK_IDX R4
0x00003D08   LI R1 CURRENT_TASK
0x00003D10   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003D14   LI R1 TASK_SIZE
0x00003D1C   MUL R3 R4 R1
0x00003D20   LI R5 tasks
0x00003D28   ADD R5 R5 R3

    ; Calculate wake time in PIT ticks (1 ms per tick).
0x00003D2C       LI R3 timer_ticks
0x00003D34       LDW R6 [R3]                ; current ticks (1ms per tick)

    ; Convert ms to ticks: 1 tick = 1 ms
0x00003D38       MOV R7 R8                  ; R7 = ticks to sleep

0x00003D3C       ADD R6 R6 R7               ; R6 = wake time in ticks

    ; Store wake time in task struct
; macro: TASK_SET_WAKE_TIME R5, R6
0x00003D40   STW R6 [R5 + TASK_WAKE_TIME]

    ; Use existing wait queue infrastructure
0x00003D44       LI R1 sleep_waitq           ; sleep_waitq ptr
0x00003D4C       LI R2 WAIT_SLEEP            ; reason
0x00003D54       LI R3 TASK_SLEEPING         ; new state (if other then blocked_io)
0x00003D5C       BL waitq_prepare_sleep     ; This marks task as TASK_SLEEP and adds it to the sleep_waitq

0x00003D64       BL waitq_sleep_current     ; freeze the current task in kernel side until it is woken up by the timer interrupt handler when the wake time is reached

    ; Return 0 (will be set when woken)
0x00003D6C       LI R1 0
0x00003D74       STW R1 [SP + TF_R1]
0x00003D78       B trap_restore

sleep_invalid:
0x00003D80       LI R1 ERR_FAULT
0x00003D88       STW R1 [SP + TF_R1]
0x00003D8C       B trap_restore


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
0x00003D94       PUSH LR

0x00003D98       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00003D9C   LI R1 CURRENT_TASK
0x00003DA4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003DA8   LI R1 TASK_SIZE
0x00003DB0   MUL R3 R4 R1
0x00003DB4   LI R5 tasks
0x00003DBC   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x00003DC0   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x00003DC4       PUSH R9                    ; original destination returned on success
0x00003DC8       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00003DD0       LI R11 KBUFFER_SIZE
0x00003DD8       CMP R10 R11
0x00003DDC       BGE copy_path_fail

0x00003DE4       PUSH R8
0x00003DE8       PUSH R9
0x00003DEC       PUSH R10
0x00003DF0       MOV R1 R8
0x00003DF4       LI R2 1
0x00003DFC       LI R3 0                    ; read access from user source
0x00003E04       BL user_buffer_valid_range
0x00003E0C       POP R10
0x00003E10       POP R9
0x00003E14       POP R8
0x00003E18       CMP R1 1
0x00003E1C       BNE copy_path_fail

0x00003E24       LDB R4 [R8]
0x00003E28       STB R4 [R9]
0x00003E2C       CMP R4 0
0x00003E30       BEQ copy_path_done

0x00003E38       ADD R8 R8 1
0x00003E3C       ADD R9 R9 1
0x00003E40       ADD R10 R10 1
0x00003E44       B copy_path_loop

copy_path_done:
0x00003E4C       POP R1                     ; original kernel path pointer
0x00003E50       POP LR
0x00003E54       RET

copy_path_fail:
0x00003E58       POP R1                     ; discard original kernel path pointer
0x00003E5C       LI R1 0
0x00003E64       POP LR
0x00003E68       RET

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

0x00003E6C       PUSH LR
0x00003E70       PUSH R8
0x00003E74       PUSH R9
0x00003E78       PUSH R10
0x00003E7C       PUSH R11

0x00003E80       MOV R8 R1          ; kernel dst
0x00003E84       MOV R9 R2          ; user src
0x00003E88       MOV R10 R3         ; max length
0x00003E8C       LI  R11 0          ; bytes copied

copy_user_loop:
    ; reached max?
0x00003E94       CMP R11 R10
0x00003E98       BGE copy_user_fail

    ; validate one byte
0x00003EA0       PUSH R8
0x00003EA4       PUSH R9
0x00003EA8       PUSH R10
0x00003EAC       PUSH R11
0x00003EB0       MOV R1 R9
0x00003EB4       LI  R2 1
0x00003EBC       LI  R3 0           ; read access
0x00003EC4       BL user_buffer_valid_range
0x00003ECC       POP R11
0x00003ED0       POP R10
0x00003ED4       POP R9
0x00003ED8       POP R8
0x00003EDC       CMP R1 1
0x00003EE0       BNE copy_user_fail

    ; copy byte
0x00003EE8       LDB R4 [R9]
0x00003EEC       STB R4 [R8]
    ;cpy ctr
0x00003EF0       ADD R11 R11 1
0x00003EF4       CMP R4 0    ;if string ends (null)
0x00003EF8       BEQ copy_user_done

0x00003F00       ADD R8 R8 1 ;advance
0x00003F04       ADD R9 R9 1
0x00003F08       B copy_user_loop
copy_user_done:
0x00003F10       MOV R1 R11
0x00003F14       POP R11
0x00003F18       POP R10
0x00003F1C       POP R9
0x00003F20       POP R8
0x00003F24       POP LR
0x00003F28       RET
copy_user_fail:
0x00003F2C       LI  R1 0
0x00003F34       POP R11
0x00003F38       POP R10
0x00003F3C       POP R9
0x00003F40       POP R8
0x00003F44       POP LR
0x00003F48       RET

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
0x00003F4C       PUSH LR
0x00003F50       MOV R8 R1                  ; save pathname ptr

0x00003F54       LI R7 device_table
0x00003F5C       LI R9 DEVICE_COUNT

devfs_loop:
0x00003F64       CMP R9 0
0x00003F68       BEQ lookup_fail

    ; compare pathname with device name
0x00003F70       MOV R1 R8
0x00003F74       LDW R2 [R7 + DEV_NAME]
0x00003F78       BL strcmp
0x00003F80       CMP R1 1
0x00003F84       BEQ devfs_found

0x00003F8C       ADD R7 R7 DEV_SIZE
0x00003F90       SUB R9 R9 1
0x00003F94       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x00003F9C       BL inode_alloc
0x00003FA4       CMP R1 0
0x00003FA8       BEQ devfs_fail

0x00003FB0       MOV R10 R1         ; inode
    ; 2 init inode
0x00003FB4       LDW R2 [R7 + DEV_OPS]
0x00003FB8       LDW R3 [R7 + DEV_PRIVATE]
0x00003FBC       LI  R4 INODE_CHAR       ; inode type for dev - char
0x00003FC4       LI  R5 0                ; size =0
0x00003FCC       BL inode_init

0x00003FD4       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x00003FD8       POP LR
0x00003FDC       RET

devfs_fail:
0x00003FE0       LI R1 0
0x00003FE8       POP LR
0x00003FEC       RET

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
0x00003FF0       LI R2 0

nsfs_node_alloc_loop:
0x00003FF8       CMP R2 NSFS_MAX_NODES
0x00003FFC       BGE nsfs_node_alloc_fail

0x00004004       SHL R3 R2 2
0x00004008       LI R4 nsfs_node_used
0x00004010       ADD R4 R4 R3

0x00004014       LDW R5 [R4]
0x00004018       CMP R5 0
0x0000401C       BEQ nsfs_node_alloc_found

0x00004024       ADD R2 R2 1
0x00004028       B nsfs_node_alloc_loop

nsfs_node_alloc_found:
0x00004030       LI R5 1
0x00004038       STW R5 [R4]

0x0000403C       LI R3 NSFS_NODE_SIZEOF
0x00004044       MUL R6 R2 R3
0x00004048       LI R1 nsfs_node_pool
0x00004050       ADD R1 R1 R6
0x00004054       RET

nsfs_node_alloc_fail:
0x00004058       LI R1 0
0x00004060       RET

nsfs_node_free:
0x00004064       LI R2 nsfs_node_pool
0x0000406C       SUB R3 R1 R2

0x00004070       LI R4 NSFS_NODE_SIZEOF
0x00004078       DIV R5 R3 R4

0x0000407C       SHL R5 R5 2
0x00004080       LI R6 nsfs_node_used
0x00004088       ADD R6 R6 R5

0x0000408C       LI R7 0
0x00004094       STW R7 [R6]
0x00004098       RET

; nsfs_refresh_index
; in:  R1 = namespace
; out: R1 = 0 on success, BMI/errno status on failure
nsfs_refresh_index:
0x0000409C       PUSH LR
0x000040A0       PUSH R8
0x000040A4       PUSH R9
0x000040A8       PUSH R10
0x000040AC       PUSH R11
0x000040B0       PUSH R12

0x000040B4       MOV R12 R1

0x000040B8       MOV R1 NSFS_INDEX
0x000040BC       LI R2 0
0x000040C4       LI R3 0
0x000040CC       MOV R4 R12
0x000040D0   CALL bmi_call

0x000040D8       CMP R1 0
0x000040DC       BNE nsfs_refresh_done

0x000040E4       LI R1 nsfs_index_count
0x000040EC       LI R2 0
0x000040F4       STW R2 [R1]
0x000040F8       LI R1 nsfs_index_path_next
0x00004100       LI R2 nsfs_index_path_pool
0x00004108       STW R2 [R1]

0x0000410C       LI R8 BMI_BUF_READ
0x00004114       ADD R8 R8 BMI_HDR_SIZEOF       ; R8 = reply payload cursor
0x00004118       LDW R9 [R8]                    ; R9 = entry_count
0x0000411C       ADD R8 R8 4
0x00004120       LI R10 0                       ; R10 = parsed count

nsfs_refresh_loop:
0x00004128       CMP R10 R9
0x0000412C       BGE nsfs_refresh_success
0x00004134       CMP R10 NSFS_INDEX_MAX_ENTRIES
0x00004138       BGE nsfs_refresh_success

    ; R11 = &nsfs_index_table[R10]
0x00004140       LI R11 NSFS_INDEX_ENTRY_SIZEOF
0x00004148       MUL R11 R10 R11
0x0000414C       LI R6 nsfs_index_table
0x00004154       ADD R11 R6 R11

0x00004158       LDW R1 [R8 + NSFS_WIRE_TYPE]
0x0000415C       STW R1 [R11 + NSFS_INDEX_TYPE]
0x00004160       LDW R1 [R8 + NSFS_WIRE_SIZE]
0x00004164       STW R1 [R11 + NSFS_INDEX_SIZE]
0x00004168       LDW R1 [R8 + NSFS_WIRE_VERSION]
0x0000416C       STW R1 [R11 + NSFS_INDEX_VERSION]
0x00004170       LDW R5 [R8 + NSFS_WIRE_PATH_LEN]
0x00004174       STW R5 [R11 + NSFS_INDEX_PATH_LEN]
0x00004178       ADD R8 R8 NSFS_WIRE_HDR_SIZEOF

    ; Copy path bytes to path pool and append a NUL for strcmp.
0x0000417C       LI R6 nsfs_index_path_next
0x00004184       LDW R1 [R6]
0x00004188       STW R1 [R11 + NSFS_INDEX_PATH]
0x0000418C       MOV R2 R8
0x00004190       MOV R3 R5
0x00004194       BL memcpy
0x0000419C       LI R2 0
0x000041A4       STB R2 [R1]
0x000041A8       ADD R1 R1 1
0x000041AC       LI R6 nsfs_index_path_next
0x000041B4       STW R1 [R6]

    ; Advance wire cursor by path_len rounded up to 4 bytes.
0x000041B8       ADD R8 R8 R5
0x000041BC       ADD R8 R8 3
0x000041C0       LI R6 0xFFFFFFFC
0x000041C8       AND R8 R8 R6

0x000041CC       ADD R10 R10 1
0x000041D0       B nsfs_refresh_loop

nsfs_refresh_success:
0x000041D8       LI R1 nsfs_index_count
0x000041E0       STW R10 [R1]
0x000041E4       LI R1 0

nsfs_refresh_done:
0x000041EC       POP R12
0x000041F0       POP R11
0x000041F4       POP R10
0x000041F8       POP R9
0x000041FC       POP R8
0x00004200       POP LR
0x00004204       RET

; nsfs_lookup
; in:  R1 = pathname
; out: R1 = inode ptr if present in NSFS overlay, or 0 if not found
nsfs_lookup:
0x00004208       PUSH LR
0x0000420C       PUSH R8
0x00004210       PUSH R9
0x00004214       PUSH R10
0x00004218       PUSH R11
0x0000421C       PUSH R12

0x00004220       MOV R8 R1                       ; pathname
0x00004224       LI R9 nsfs_index_table
0x0000422C       LI R10 nsfs_index_count
0x00004234       LDW R10 [R10]

nsfs_lookup_loop:
0x00004238       CMP R10 0
0x0000423C       BEQ nsfs_lookup_not_found

0x00004244       MOV R1 R8
0x00004248       LDW R2 [R9 + NSFS_INDEX_PATH]
0x0000424C       BL strcmp
0x00004254       CMP R1 1
0x00004258       BEQ nsfs_lookup_found

0x00004260       ADD R9 R9 NSFS_INDEX_ENTRY_SIZEOF
0x00004264       SUB R10 R10 1
0x00004268       B nsfs_lookup_loop

nsfs_lookup_found:
0x00004270       BL nsfs_node_alloc
0x00004278       CMP R1 0
0x0000427C       BEQ nsfs_lookup_not_found
0x00004284       MOV R11 R1                      ; nsfs node

0x00004288       LI R1 NSFS_DEFAULT_NS
0x00004290       STW R1 [R11 + NSFS_NODE_NAMESPACE]
0x00004294       LDW R1 [R9 + NSFS_INDEX_PATH]
0x00004298       STW R1 [R11 + NSFS_NODE_PATH]
0x0000429C       LDW R1 [R9 + NSFS_INDEX_TYPE]
0x000042A0       CMP R1 NSFS_TYPE_DIR
0x000042A4       BEQ nsfs_lookup_type_dir
0x000042AC       LI R12 INODE_REG
0x000042B4       B nsfs_lookup_type_done
nsfs_lookup_type_dir:
0x000042BC       LI R12 INODE_DIR
nsfs_lookup_type_done:
0x000042C4       STW R12 [R11 + NSFS_NODE_TYPE]
0x000042C8       LDW R5 [R9 + NSFS_INDEX_SIZE]
0x000042CC       STW R5 [R11 + NSFS_NODE_SIZE]
0x000042D0       LI R1 0
0x000042D8       STW R1 [R11 + NSFS_NODE_FLAGS]

0x000042DC       BL inode_alloc
0x000042E4       CMP R1 0
0x000042E8       BEQ nsfs_lookup_free_node

0x000042F0       MOV R10 R1                      ; inode
0x000042F4       LI R2 nsfs_ops
0x000042FC       MOV R3 R11
0x00004300       MOV R4 R12
    ; R5 already holds file size.
0x00004304       BL inode_init
0x0000430C       MOV R1 R10
0x00004310       B nsfs_lookup_done

nsfs_lookup_free_node:
0x00004318       MOV R1 R11
0x0000431C       BL nsfs_node_free

nsfs_lookup_not_found:
0x00004324       LI R1 0

nsfs_lookup_done:
0x0000432C       POP R12
0x00004330       POP R11
0x00004334       POP R10
0x00004338       POP R9
0x0000433C       POP R8
0x00004340       POP LR
0x00004344       RET

; nsfs_open
; in:  R1 = file ptr
; out: R1 = 0
nsfs_open:
0x00004348       LI R1 0
0x00004350       RET

; nsfs_close
; in:  R1 = file ptr
; out: R1 = 0
nsfs_close:
0x00004354       LI R1 0
0x0000435C       RET

; nsfs_read
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
nsfs_read:
0x00004360       LI R1 ERR_NOENT
0x00004368       RET

; nsfs_write
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes written or errno
nsfs_write:
0x0000436C       LI R1 ERR_NOENT
0x00004374       RET

; nsfs_readdir
; in:  R1 = file ptr, R2 = userspace dirent buffer
; out: R1 = 1 entry, 0 EOF, or errno
nsfs_readdir:
0x00004378       PUSH LR
0x0000437C       PUSH R8
0x00004380       PUSH R9
0x00004384       PUSH R10
0x00004388       PUSH R11
0x0000438C       PUSH R12

0x00004390       MOV R8 R2
0x00004394       PUSH R8
0x00004398       MOV R12 R1

0x0000439C       LI R3 DIRENT_SIZEOF
0x000043A4       MOV R1 R8
0x000043A8       LI R2 DIRENT_SIZEOF
0x000043B0       LI R3 1
0x000043B8       BL user_buffer_valid_range
0x000043C0       CMP R1 1
0x000043C4       BNE nsfs_readdir_fault

0x000043CC       LDW R4 [R12 + FILE_INODE]
0x000043D0       LDW R5 [R4 + INODE_PRIVATE]
0x000043D4       CMP R5 0
0x000043D8       BEQ nsfs_readdir_eof
0x000043E0       LDW R10 [R5 + NSFS_NODE_PATH]   ; directory path, absolute
0x000043E4       LDW R11 [R12 + FILE_OFFSET]     ; index into nsfs_index_table
0x000043E8       MOV R6 R11

nsfs_readdir_scan:
0x000043EC       LI R1 nsfs_index_count
0x000043F4       LDW R1 [R1]
0x000043F8       CMP R6 R1
0x000043FC       BGE nsfs_readdir_eof

0x00004404       LI R7 NSFS_INDEX_ENTRY_SIZEOF
0x0000440C       MUL R7 R6 R7
0x00004410       LI R9 nsfs_index_table
0x00004418       ADD R9 R9 R7

0x0000441C       LDW R1 [R9 + NSFS_INDEX_PATH]
0x00004420       MOV R2 R10
0x00004424       BL str_prefix
0x0000442C       CMP R1 1
0x00004430       BNE nsfs_readdir_next

0x00004438       LDW R1 [R9 + NSFS_INDEX_PATH]
0x0000443C       MOV R2 R10
0x00004440       BL skip_prefix
0x00004448       LDB R2 [R1]
0x0000444C       LI R3 47
0x00004454       CMP R2 R3
0x00004458       BEQ nsfs_readdir_skip_slash
0x00004460       CMP R2 0
0x00004464       BEQ nsfs_readdir_next
0x0000446C       B nsfs_readdir_have_name
nsfs_readdir_skip_slash:
0x00004474       ADD R1 R1 1
nsfs_readdir_have_name:
0x00004478       MOV R8 R1                       ; component name

0x0000447C       BL path_component_len
0x00004484       MOV R7 R1
0x00004488       CMP R7 0
0x0000448C       BEQ nsfs_readdir_next
0x00004494       LI R2 63
0x0000449C       CMP R7 R2
0x000044A0       BLE nsfs_readdir_name_ok
0x000044A8       MOV R7 R2

nsfs_readdir_name_ok:
0x000044AC       MOV R11 R6
; macro: GET_CURR_TASK_IDX R4
0x000044B0   LI R1 CURRENT_TASK
0x000044B8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000044BC   LI R1 TASK_SIZE
0x000044C4   MUL R3 R4 R1
0x000044C8   LI R5 tasks
0x000044D0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x000044D4   LDW R1 [R5 + TASK_KBUF_WR_PTR]

0x000044D8       ADD R3 R11 1
0x000044DC       STW R3 [R1 + DIRENT_INODE]
0x000044E0       LDW R2 [R9 + NSFS_INDEX_SIZE]
0x000044E4       STW R2 [R1 + DIRENT_SIZE]
0x000044E8       LDW R2 [R9 + NSFS_INDEX_TYPE]
0x000044EC       CMP R2 NSFS_TYPE_DIR
0x000044F0       BEQ nsfs_readdir_type_dir
0x000044F8       LI R2 DT_REG
0x00004500       B nsfs_readdir_type_done
nsfs_readdir_type_dir:
0x00004508       LI R2 DT_DIR
nsfs_readdir_type_done:
0x00004510       STW R2 [R1 + DIRENT_TYPE]

0x00004514       ADD R3 R11 1
0x00004518       STW R3 [R12 + FILE_OFFSET]

0x0000451C       MOV R2 R8
0x00004520       ADD R3 R1 DIRENT_NAME
0x00004524       LI R6 0
nsfs_readdir_copy_name:
0x0000452C       CMP R6 R7
0x00004530       BGE nsfs_readdir_copy_done
0x00004538       LDB R10 [R2 + R6]
0x0000453C       STB R10 [R3 + R6]
0x00004540       ADD R6 R6 1
0x00004544       B nsfs_readdir_copy_name
nsfs_readdir_copy_done:
0x0000454C       LI R10 0
0x00004554       STB R10 [R3 + R6]

0x00004558       LI R2 DIRENT_SIZEOF
0x00004560       MOV R4 R1
0x00004564       POP R1
0x00004568       BL copy_to_user
0x00004570       CMP R1 DIRENT_SIZEOF
0x00004574       BNE nsfs_readdir_fault_after_pop
0x0000457C       MOV R1 DIRENT_SIZEOF
0x00004580       POP R12
0x00004584       POP R11
0x00004588       POP R10
0x0000458C       POP R9
0x00004590       POP R8
0x00004594       POP LR
0x00004598       RET

nsfs_readdir_next:
0x0000459C       ADD R6 R6 1
0x000045A0       B nsfs_readdir_scan

nsfs_readdir_eof:
0x000045A8       POP R1
0x000045AC       LI R1 0
0x000045B4       POP R12
0x000045B8       POP R11
0x000045BC       POP R10
0x000045C0       POP R9
0x000045C4       POP R8
0x000045C8       POP LR
0x000045CC       RET

nsfs_readdir_fault:
0x000045D0       POP R1
nsfs_readdir_fault_after_pop:
0x000045D4       LI R1 ERR_FAULT
0x000045DC       POP R12
0x000045E0       POP R11
0x000045E4       POP R10
0x000045E8       POP R9
0x000045EC       POP R8
0x000045F0       POP LR
0x000045F4       RET

; nsfs_create
; in:  R1 = pathname, R2 = mode/type flags
; out: R1 = 0 or errno
nsfs_create:
    ; TODO: FILE_CREATE over BMI, then nsfs_lookup can materialize inode.
0x000045F8       LI R1 ERR_NOENT
0x00004600       RET

; nsfs_unlink
; in:  R1 = pathname
; out: R1 = 0 or errno
nsfs_unlink:
    ; TODO: FILE_DELETE over BMI and create whiteout when shadowing tarfs.
0x00004604       LI R1 ERR_NOENT
0x0000460C       RET

; nsfs_mkdir
; in:  R1 = pathname, R2 = mode
; out: R1 = 0 or errno
nsfs_mkdir:
    ; TODO: DIR_CREATE over BMI.
0x00004610       LI R1 ERR_NOENT
0x00004618       RET

; nsfs_rmdir
; in:  R1 = pathname
; out: R1 = 0 or errno
nsfs_rmdir:
    ; TODO: DIR_DELETE over BMI.
0x0000461C       LI R1 ERR_NOENT
0x00004624       RET

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

0x00004628       PUSH LR

0x0000462C       MOV R8 R1                  ; save pathname ptr

0x00004630       LI R7 device_table
0x00004638       LI R9 DEVICE_COUNT

lookup_loop:
0x00004640       CMP R9 0
0x00004644       BEQ lookup_fail

    ; compare pathname with device name

0x0000464C       MOV R1 R8
0x00004650       LDW R2 [R7 + DEV_NAME]

0x00004654       BL strcmp

0x0000465C       CMP R1 1
0x00004660       BEQ lookup_found

0x00004668       ADD R7 R7 DEV_SIZE
0x0000466C       SUB R9 R9 1
0x00004670       B lookup_loop

lookup_found:

0x00004678       MOV R1 R7                  ; return device descriptor ptr

0x0000467C       POP LR
0x00004680       RET

lookup_fail:

0x00004684       LI R1 0

0x0000468C       POP LR
0x00004690       RET

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
0x00004694       LDB R3 [R1]
0x00004698       LDB R4 [R2]

0x0000469C       CMP R3 R4
0x000046A0       BNE str_not_equal

0x000046A8       CMP R3 0
0x000046AC       BEQ str_equal

0x000046B4       ADD R1 R1 1
0x000046B8       ADD R2 R2 1
0x000046BC       B str_loop

str_equal:
0x000046C4       LI R1 1
0x000046CC       RET

str_not_equal:
0x000046D0       LI R1 0
0x000046D8       RET

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
0x000046DC       PUSH R3
0x000046E0       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x000046E4       LDB R3 [R2]            ; prefix char
0x000046E8       CMP R3 0
0x000046EC       BEQ sp_match           ; reached end of prefix?

0x000046F4       LDB R4 [R1]            ; string char
0x000046F8       CMP R4 R3
0x000046FC       BNE sp_nomatch

0x00004704       ADD R1 R1 1
0x00004708       ADD R2 R2 1
0x0000470C       B sp_loop
sp_match:
0x00004714       LI R1 1                 ;prefix ok
0x0000471C       POP R4
0x00004720       POP R3
0x00004724       RET
sp_nomatch:
0x00004728       LI R1 0                 ; not ok
0x00004730       POP R4
0x00004734       POP R3
0x00004738       RET

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
0x0000473C       PUSH R3
0x00004740       PUSH R4
sk_loop:
0x00004744       LDB R3 [R2]            ; prefix char
0x00004748       CMP R3 0
0x0000474C       BEQ sk_match           ; reached end of prefix
0x00004754       LDB R4 [R1]            ; string char
0x00004758       CMP R4 R3
0x0000475C       BNE sk_nomatch
0x00004764       ADD R1 R1 1
0x00004768       ADD R2 R2 1
0x0000476C       B sk_loop

sk_match:
    ; R1 already points past prefix
0x00004774       POP R4
0x00004778       POP R3
0x0000477C       RET

sk_nomatch:
0x00004780       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x00004788       POP R4
0x0000478C       POP R3
0x00004790       RET

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
0x00004794       PUSH R2
0x00004798       PUSH R3
0x0000479C       LI R2 0                ; length
pcl_loop:
0x000047A4       LDB R3 [R1]
0x000047A8       CMP R3 0
0x000047AC       BEQ pcl_done
0x000047B4       LI R4 47               ; '/'
0x000047BC       CMP R3 R4
0x000047C0       BEQ pcl_done
0x000047C8       ADD R2 R2 1
0x000047CC       ADD R1 R1 1
0x000047D0       B pcl_loop
pcl_done:
0x000047D8       MOV R1 R2
0x000047DC       POP R3
0x000047E0       POP R2
0x000047E4       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x000047E8       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x000047EC       LI R4 0
0x000047F4       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x000047F8       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x000047FC       LI R4 1
0x00004804       STW R4 [R1 + FILE_REFCNT]
0x00004808       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x0000480C       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x00004810   LI R1 CURRENT_TASK
0x00004818   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x0000481C   LI R1 TASK_SIZE
0x00004824   MUL R3 R4 R1
0x00004828   LI R4 tasks
0x00004830   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00004834   LDW R4 [R4 + TASK_FD_TABLE]

0x00004838       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00004840       CMP R5 MAX_FDS
0x00004844       BGE fd_alloc_fail

0x0000484C       SHL R6 R5 2                ; fd * 4
0x00004850       ADD R7 R4 R6               ; &fd_table[fd]

0x00004854       LDW R2 [R7]
0x00004858       CMP R2 0                   ; 0 - empty
0x0000485C       BEQ fd_alloc_found

0x00004864       ADD R5 R5 1
0x00004868       B fd_alloc_loop

fd_alloc_found:

0x00004870       STW R8 [R7]                ; fd_table[fd] = file*

0x00004874       MOV R1 R5                  ; return fd
0x00004878       RET

fd_alloc_fail:

0x0000487C       LI R1 ERR_MFILE
0x00004884       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x00004888       LDW R1 [SP + TF_R1]

0x0000488C       BL vfs_close

0x00004894       LI R1 0
0x0000489C       STW R1 [SP + TF_R1]

0x000048A0       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x000048A8       LDW R7 [SP + TF_R1]

0x000048AC       BL pipe_alloc       ;create new pipe object in pipe_pool
0x000048B4       CMP R1 0
0x000048B8       BEQ pipe_fail_nospc

0x000048C0       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x000048C4       BL file_alloc        ; R1 - created read file ptr for read end
0x000048CC       CMP R1 0
0x000048D0       BEQ pipe_fail_read_fd

0x000048D8       MOV R9 R1           ; new file for read end  in file_pool
0x000048DC       BL inode_alloc      ; get inode for this end file
0x000048E4       CMP R1 0
0x000048E8       BEQ pipe_fail_ia_read_fd
0x000048F0       MOV R10 R1

0x000048F4       LI  R2 pipe_ops         ; pipe_ops table
0x000048FC       MOV R3 R8               ; store our slot pipe*
0x00004900       LI  R4 INODE_PIPE       ; inode type PIPE
0x00004908       LI  R5 0                ; size =0
0x00004910       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x00004918       MOV R1 R9                ; R1 file*
0x0000491C       MOV R2 R10               ; inode*
0x00004920       LI R3  FD_FLAG_READ      ; flags READ end
0x00004928       BL file_init

0x00004930       MOV R1 R9
0x00004934       BL fd_alloc                 ; insert read file to fd_table of user process

0x0000493C       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00004944       CMP R1 R2
0x00004948       BEQ pipe_fail_read_file

0x00004950       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x00004954       BL file_alloc
0x0000495C       CMP R1 0
0x00004960       BEQ pipe_fail_ia_write_fd
0x00004968       MOV R9 R1

0x0000496C       BL inode_alloc      ; get inode for this end file
0x00004974       CMP R1 0
0x00004978       BEQ pipe_fail_ia_write_fd
0x00004980       MOV R10 R1

0x00004984       LI  R2 pipe_ops         ; pipe_ops table
0x0000498C       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x00004990       LI  R4 INODE_PIPE       ; inode type PIPE
0x00004998       LI  R5 0                ; size =0
0x000049A0       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x000049A8       MOV R1 R9                ; R1 file*
0x000049AC       MOV R2 R10               ; inode*
0x000049B0       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x000049B8       BL file_init

0x000049C0       MOV R1 R9
0x000049C4       BL  fd_alloc

0x000049CC       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x000049D4       CMP R1 R2
0x000049D8       BEQ pipe_fail_write_file

0x000049E0       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x000049E4       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x000049E8       LI  R2 8     ; len 2 words (8 bytes)
0x000049F0       LI  R3 1     ; mem perm to write cond
0x000049F8       BL  user_buffer_valid_range
0x00004A00       CMP R1 1
0x00004A04       BNE pipe_fail_both_fds

0x00004A0C       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x00004A10       STW R11 [R7 + 4]

0x00004A14       LI R1 0
0x00004A1C       STW R1 [SP + TF_R1]

0x00004A20       B trap_restore

pipe_fail:
0x00004A28       LI R1 ERR_IO
0x00004A30       STW R1 [SP + TF_R1]

0x00004A34       B trap_restore

pipe_fail_both_fds:
0x00004A3C       MOV R12 R8
0x00004A40       MOV R1 R11
0x00004A44       BL fd_remove
0x00004A4C       CMP R1 0
0x00004A50       BEQ pipe_fail_both_fds_read
0x00004A58       BL file_free

pipe_fail_both_fds_read:
0x00004A60       MOV R1 R10
0x00004A64       BL fd_remove
0x00004A6C       CMP R1 0
0x00004A70       BEQ pipe_fail_free_pipe_fault
0x00004A78       BL file_free

pipe_fail_free_pipe_fault:
0x00004A80       MOV R1 R12
0x00004A84       BL pipe_free
0x00004A8C       LI R1 ERR_FAULT
0x00004A94       STW R1 [SP + TF_R1]

0x00004A98       B trap_restore

pipe_fail_write_file:
0x00004AA0       MOV R12 R8
0x00004AA4       MOV R1 R9
0x00004AA8       BL file_free
0x00004AB0       MOV R1 R10
0x00004AB4       BL fd_remove
0x00004ABC       CMP R1 0
0x00004AC0       BEQ pipe_fail_free_pipe_mfile
0x00004AC8       BL file_free

pipe_fail_free_pipe_mfile:
0x00004AD0       MOV R1 R12
0x00004AD4       BL pipe_free
0x00004ADC       LI R1 ERR_MFILE
0x00004AE4       STW R1 [SP + TF_R1]

0x00004AE8       B trap_restore

pipe_fail_read_fd:
0x00004AF0       MOV R12 R8
0x00004AF4       MOV R1 R10
0x00004AF8       BL fd_remove
0x00004B00       CMP R1 0
0x00004B04       BEQ pipe_fail_free_pipe_nfile
0x00004B0C       BL file_free

pipe_fail_free_pipe_nfile:
0x00004B14       MOV R1 R12
0x00004B18       BL pipe_free
0x00004B20       LI R1 ERR_NFILE
0x00004B28       STW R1 [SP + TF_R1]

0x00004B2C       B trap_restore

pipe_fail_read_file:
0x00004B34       MOV R12 R8
0x00004B38       MOV R1 R9
0x00004B3C       BL file_free
0x00004B44       MOV R1 R10          ; освободить inode read end
0x00004B48       BL inode_free
0x00004B50       MOV R1 R12
0x00004B54       BL pipe_free
0x00004B5C       LI R1 ERR_MFILE
0x00004B64       STW R1 [SP + TF_R1]

0x00004B68       B trap_restore

pipe_fail_pipe_only:
0x00004B70       MOV R1 R8
0x00004B74       BL pipe_free
0x00004B7C       LI R1 ERR_NFILE
0x00004B84       STW R1 [SP + TF_R1]

0x00004B88       B trap_restore

pipe_fail_nospc:
0x00004B90       LI R1 ERR_NOSPC
0x00004B98       STW R1 [SP + TF_R1]

0x00004B9C       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x00004BA4       MOV R1 R9          ; освобождаем file (read end)
0x00004BA8       BL  file_free
0x00004BB0       MOV R1 R8          ; освобождаем pipe
0x00004BB4       BL  pipe_free
0x00004BBC       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x00004BC4       STW R1 [SP + TF_R1]
0x00004BC8       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x00004BD0       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x00004BD4       BL fd_remove
0x00004BDC       CMP R1 0
0x00004BE0       BEQ skip_file_free_read
0x00004BE8       BL file_free
skip_file_free_read:
0x00004BF0       MOV R1 R9          ; освобождаем file (write end)
0x00004BF4       BL file_free
0x00004BFC       MOV R1 R8          ; освобождаем pipe
0x00004C00       BL pipe_free
0x00004C08       LI R1 ERR_NFILE
0x00004C10       STW R1 [SP + TF_R1]
0x00004C14       B trap_restore

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

0x00004C1C       LDW R1 [SP + TF_R1]     ; argument fd

0x00004C20       BL fd_lookup            ; lookup FILE*
0x00004C28       CMP R1 0
0x00004C2C       BEQ dup_badfd
0x00004C34       MOV R8 R1               ; keep FILE*

0x00004C38       BL file_get             ; FILE.ref++

0x00004C40       MOV R1 R8
0x00004C44       BL fd_alloc             ; try to allocate new fd

0x00004C4C       LI R2 ERR_MFILE
0x00004C54       CMP R1 R2
0x00004C58       BEQ dup_fail_fd

0x00004C60       STW R1 [SP + TF_R1] ;R1 - new fd
0x00004C64       B trap_restore

dup_fail_fd:

0x00004C6C       MOV R1 R8
0x00004C70       BL file_put

0x00004C78       LI R1 ERR_MFILE     ;R1 -err + rollback
0x00004C80       STW R1 [SP + TF_R1]
0x00004C84       B trap_restore

dup_badfd:

0x00004C8C       LI R1 ERR_BADF      ;R1 -err + file not found
0x00004C94       STW R1 [SP + TF_R1]

0x00004C98       B trap_restore

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

0x00004CA0       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x00004CA4       MOV R1 R8
0x00004CA8       LI  R2 TIMEVAL_SIZE
0x00004CB0       LI  R3 1                   ; write access
0x00004CB8       BL  user_buffer_valid_range

0x00004CC0       CMP R1 1
0x00004CC4       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x00004CCC       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x00004CD4   LI R1 CURRENT_TASK
0x00004CDC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004CE0   LI R1 TASK_SIZE
0x00004CE8   MUL R3 R4 R1
0x00004CEC   LI R5 tasks
0x00004CF4   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x00004CF8   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x00004CFC       STW R1 [R6 + TIMEVAL_SEC]
0x00004D00       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x00004D04       MOV R1 R8                  ; user destination
0x00004D08       LI  R2 TIMEVAL_SIZE        ; size in bytes (8)
0x00004D10       MOV R4 R6                  ; kernel source

0x00004D14       BL copy_to_user

0x00004D1C       CMP R1 TIMEVAL_SIZE
0x00004D20       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x00004D28       LI R1 0
0x00004D30       STW R1 [SP + TF_R1]

0x00004D34       B trap_restore

gettime_badptr:

0x00004D3C       LI R1 ERR_FAULT
0x00004D44       STW R1 [SP + TF_R1]

0x00004D48       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x00004D50       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x00004D54       LI R2 HEAP_START
0x00004D5C       CMP R8 R2
0x00004D60       BLT brk_invalid            ; if new break is below data page, return error

0x00004D68       LI R2 HEAP_END
0x00004D70       CMP R8 R2
0x00004D74       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00004D7C   LI R1 CURRENT_TASK
0x00004D84   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004D88   LI R1 TASK_SIZE
0x00004D90   MUL R3 R4 R1
0x00004D94   LI R5 tasks
0x00004D9C   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x00004DA0   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x00004DA4       STW R8 [SP + TF_R1]

0x00004DA8       B trap_restore

brk_invalid:
    ; Return -1
0x00004DB0       LI R1 ERR_FAULT
0x00004DB8       STW R1 [SP + TF_R1]

0x00004DBC       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x00004DC4       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00004DC8   LI R1 CURRENT_TASK
0x00004DD0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004DD4   LI R1 TASK_SIZE
0x00004DDC   MUL R3 R4 R1
0x00004DE0   LI R5 tasks
0x00004DE8   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x00004DEC   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x00004DF0       ADD R10 R9 R8

    ; Validate it's within the data page
0x00004DF4       LI R2 HEAP_START
0x00004DFC       CMP R10 R2
0x00004E00       BLT sbrk_invalid

0x00004E08       LI R2 HEAP_END
0x00004E10       CMP R10 R2
0x00004E14       BGT sbrk_invalid

    ; Return old break
0x00004E1C       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x00004E20   STW R10 [R5 + TASK_BREAK]

0x00004E24       B trap_restore

sbrk_invalid:
    ; Return -1
0x00004E2C       LI R1 ERR_FAULT
0x00004E34       STW R1 [SP + TF_R1]
0x00004E38       B trap_restore

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

0x00004E40       LI  R3 timer_ticks
0x00004E48       LDW R4 [R3]                ; tick counter (1 ms per tick)

    ; seconds = ticks / 1000
0x00004E4C       MOV R1 R4
0x00004E50       LI  R5 1000
0x00004E58       DIV R1 R1 R5

    ; usec = (ticks % 1000) * 1000
0x00004E5C       MOD R4 R4 R5
0x00004E60       LI  R5 1000
0x00004E68       MUL R2 R4 R5

0x00004E6C       RET

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

0x00004E70       PUSH LR

0x00004E74       MOV R9 R1              ; file*
0x00004E78       MOV R7 R2              ; user buffer
0x00004E7C       MOV R6 R3              ; requested len

0x00004E80       LDW R9 [R9 + FILE_INODE]
0x00004E84       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x00004E88       CMP R6 0                ;fast clear from it if len=0
0x00004E8C       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x00004E94       PUSH R7
0x00004E98       PUSH R6

0x00004E9C       MOV R1 R7
0x00004EA0       MOV R2 R6
0x00004EA4       LI  R3 1               ; write access
0x00004EAC       BL user_buffer_valid_range

0x00004EB4       POP R6
0x00004EB8       POP R7
0x00004EBC       CMP R1 1
0x00004EC0       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00004EC8       LDW R4 [R9 + PIPE_COUNT]
0x00004ECC       CMP R4 0
0x00004ED0       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x00004ED8       CMP R6 R4
0x00004EDC       BLT pipe_user_len

0x00004EE4       MOV R5 R4
0x00004EE8       B pipe_have_amount

pipe_user_len:
0x00004EF0       MOV R5 R6

pipe_have_amount:
0x00004EF4       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00004EFC       CMP R10 R5
0x00004F00       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00004F08       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00004F0C       MOV R12 R9
0x00004F10       ADD R12 R12 PIPE_BUFFER
0x00004F14       ADD R12 R12 R11         ; addr += tail

0x00004F18       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00004F1C       MOV R12 R7
0x00004F20       ADD R12 R12 R10

0x00004F24       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x00004F28       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00004F2C       LI R2 255
0x00004F34       AND R11 R11 R2
0x00004F38       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00004F3C       LDW R12 [R9 + PIPE_COUNT]
0x00004F40       SUB R12 R12 1
0x00004F44       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00004F48       ADD R10 R10 1
0x00004F4C       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00004F54       MOV R1 R9
0x00004F58       ADD R1 R1 PIPE_WWAIT
0x00004F5C       BL waitq_wake_all
0x00004F64       MOV R1 R10          ; read bytes amount
0x00004F68       POP LR
0x00004F6C       RET

pipe_read_badptr:
0x00004F70       LI R1 ERR_FAULT
0x00004F78       POP LR
0x00004F7C       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00004F80       MOV R1 R9
0x00004F84       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00004F88       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00004F90       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00004F98       LDW R4 [R9 + PIPE_COUNT]
0x00004F9C       CMP R4 0
0x00004FA0       BNE pipe_read_retry

0x00004FA8       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00004FB0       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00004FB8       LI R2 0

pipe_loop:
0x00004FC0       LI  R1 MAX_PIPES
0x00004FC8       CMP R2 R1
0x00004FCC       BGE pipe_alloc_fail

0x00004FD4       SHL R3 R2 2

0x00004FD8       LI R4 pipe_used
0x00004FE0       ADD R4 R4 R3

0x00004FE4       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00004FE8       CMP R5 0                ; 0 -empty
0x00004FEC       BEQ pipe_found

0x00004FF4       ADD R2 R2 1
0x00004FF8       B pipe_loop

pipe_found:

0x00005000       LI R5 1
0x00005008       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x0000500C       LI R4 PIPE_SIZE
0x00005014       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00005018       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x00005020       ADD R1 R1 R6

0x00005024       LI R7 0                 ; clean it up
0x0000502C       STW R7 [R1 + PIPE_HEAD]
0x00005030       STW R7 [R1 + PIPE_TAIL]
0x00005034       STW R7 [R1 + PIPE_COUNT]
0x00005038       STW R7 [R1 + PIPE_RWAIT]
0x0000503C       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00005040       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00005044       LI R1 0
0x0000504C       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00005050       LI R2 pipe_pool
0x00005058       SUB R3 R1 R2

0x0000505C       LI R4 PIPE_SIZE
0x00005064       DIV R5 R3 R4

0x00005068       SHL R5 R5 2
0x0000506C       LI R6 pipe_used
0x00005074       ADD R6 R6 R5

0x00005078       LI R7 0
0x00005080       STW R7 [R6]

0x00005084       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00005088       PUSH LR

0x0000508C       MOV R9 R1
0x00005090       MOV R7 R2
0x00005094       MOV R6 R3

0x00005098       LDW R9 [R9 + FILE_INODE]
0x0000509C       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x000050A0       PUSH R7
0x000050A4       PUSH R6

0x000050A8       MOV R1 R7
0x000050AC       MOV R2 R6
0x000050B0       LI  R3 0           ; READ access
0x000050B8       BL user_buffer_valid_range

0x000050C0       POP R6
0x000050C4       POP R7

0x000050C8       CMP R1 1
0x000050CC       BNE pipe_write_badptr

0x000050D4       LI R10 0               ; bytes written
pipe_write_retry:
0x000050DC       CMP R10 R6
0x000050E0       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x000050E8       LDW R11 [R9 + PIPE_COUNT]
0x000050EC       LI R2 256
0x000050F4       CMP R11 R2
0x000050F8       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x00005100       LDW R12 [R9 + PIPE_HEAD]

0x00005104       MOV R4 R7
0x00005108       ADD R4 R4 R10
0x0000510C       LDB R5 [R4]     ; read byte from user buff addr

0x00005110       MOV R4 R9
0x00005114       ADD R4 R4 PIPE_BUFFER
0x00005118       ADD R4 R4 R12
0x0000511C       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x00005120       ADD R12 R12 1
0x00005124       LI R2 255
0x0000512C       AND R12 R12 R2
0x00005130       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00005134       LDW R4 [R9 + PIPE_COUNT]
0x00005138       ADD R4 R4 1
0x0000513C       STW R4 [R9 + PIPE_COUNT]

; written++
0x00005140       ADD R10 R10 1
0x00005144       B pipe_write_retry

pipe_write_done:
; wake readers
0x0000514C       MOV R1 R9
0x00005150       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x00005154       BL waitq_wake_all
0x0000515C       MOV R1 R10      ;written bytes
0x00005160       POP LR
0x00005164       RET

pipe_write_badptr:
0x00005168       LI R1 ERR_FAULT
0x00005170       POP LR
0x00005174       RET

pipe_write_empty:
0x00005178       LI R1 0
0x00005180       POP LR
0x00005184       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00005188       MOV R1 R9
0x0000518C       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x00005190       LI R2 WAIT_PIPE_WRITE
0x00005198       BL waitq_prepare_sleep
    ; race check
0x000051A0       LDW R4 [R9 + PIPE_COUNT]
0x000051A4       LI R2 256
0x000051AC       CMP R4 R2
0x000051B0       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x000051B8       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x000051C0       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x000051C8       CMP R1 3
0x000051CC       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x000051D4       CMP R1 MAX_FDS
0x000051D8       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x000051E0       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x000051E4   LI R1 CURRENT_TASK
0x000051EC   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000051F0   LI R1 TASK_SIZE
0x000051F8   MUL R3 R4 R1
0x000051FC   LI R4 tasks
0x00005204   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x00005208   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x0000520C       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x00005210       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x00005214       LDW R1 [R6]                 ; R1 = file* из таблицы
0x00005218       CMP R1 0
0x0000521C       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x00005224       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x00005228       RET

fd_lookup_invalid:
0x0000522C       LI R1 0
0x00005234       LI R2 0
0x0000523C       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x00005240       PUSH LR
0x00005244       BL  fd_lookup
0x0000524C       CMP R1 0
0x00005250       BEQ fd_remove_invalid

0x00005258       MOV R8 R1          ; сохраняем file*
0x0000525C       LI R3 0
0x00005264       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x00005268       MOV R1 R8          ; file*
0x0000526C       POP LR
0x00005270       RET

fd_remove_invalid:
0x00005274       LI R1 0
0x0000527C       POP LR
0x00005280       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00005284       LDW R1 [SP + TF_R1]
0x00005288       LDW R2 [SP + TF_R2]
0x0000528C       LDW R3 [SP + TF_R3]

0x00005290       BL vfs_read

0x00005298       STW R1 [SP + TF_R1]
0x0000529C       B trap_restore

; to comply with vfs interface
devfs_open:
0x000052A4       LI R1 0
0x000052AC       RET
devfs_close:
0x000052B0       LI R1 0
0x000052B8       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x000052BC       PUSH LR
0x000052C0       PUSH R8
0x000052C4       PUSH R9
0x000052C8       PUSH R10
0x000052CC       PUSH R11
0x000052D0       PUSH R12
0x000052D4       MOV R9 R1
0x000052D8       MOV R7 R2
0x000052DC       MOV R6 R3
0x000052E0       LI R8 0                    ; total bytes collected
0x000052E8       LDW R9 [R9 + FILE_INODE]
0x000052EC       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x000052F0       CMP R6 0
0x000052F4       BEQ read_done

0x000052FC       PUSH R7
0x00005300       PUSH R6
0x00005304       PUSH R9
0x00005308       MOV R1 R7
0x0000530C       MOV R2 R6
0x00005310       LI R3 1                ; write access for destination buffer
0x00005318       BL user_buffer_valid_range
0x00005320       POP R9
0x00005324       POP R6
0x00005328       POP R7
0x0000532C       CMP R1 1
0x00005330       BNE con_read_fault

read_wait_uart_rx:
0x00005338       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x0000533C       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00005340       AND R5 R5 1                 ; bit 0 = RX_READY
0x00005344       CMP R5 0
0x00005348       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00005350   LI R1 CURRENT_TASK
0x00005358   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000535C   LI R1 TASK_SIZE
0x00005364   MUL R3 R4 R1
0x00005368   LI R5 tasks
0x00005370   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00005374   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00005378       MOV R2 R6
0x0000537C       MOV R3 R9
0x00005380       PUSH R6
0x00005384       PUSH R7
0x00005388       PUSH R8
0x0000538C       PUSH R9
0x00005390       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x00005398       POP R9
0x0000539C       POP R8
0x000053A0       POP R7
0x000053A4       POP R6

0x000053A8       CMP R1 0
0x000053AC       BEQ read_wait_uart_rx

0x000053B4       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x000053B8   LI R1 CURRENT_TASK
0x000053C0   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x000053C4   LI R1 TASK_SIZE
0x000053CC   MUL R3 R5 R1
0x000053D0   LI R4 tasks
0x000053D8   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000053DC   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with CR/LF before copy_to_user
    ; clobbers temporary registers.
0x000053E0       LI R11 0
0x000053E8       SUB R5 R10 1
0x000053EC       ADD R5 R4 R5
0x000053F0       LDB R5 [R5]
0x000053F4       CMP R5 10
0x000053F8       BEQ read_chunk_line_done
0x00005400       CMP R5 13
0x00005404       BNE read_chunk_not_newline
read_chunk_line_done:
0x0000540C       LI R11 1

read_chunk_not_newline:
0x00005414       PUSH R6
0x00005418       PUSH R7
0x0000541C       PUSH R8
0x00005420       PUSH R9
0x00005424       PUSH R10
0x00005428       PUSH R11
0x0000542C       MOV R1 R7              ; user destination
0x00005430       MOV R2 R10
0x00005434       BL copy_to_user        ; copy from kernel buffer to user buffer
0x0000543C       POP R11
0x00005440       POP R10
0x00005444       POP R9
0x00005448       POP R8
0x0000544C       POP R7
0x00005450       POP R6

0x00005454       ADD R7 R7 R10
0x00005458       ADD R8 R8 R10
0x0000545C       SUB R6 R6 R10

0x00005460       CMP R11 1
0x00005464       BEQ read_complete
0x0000546C       CMP R6 0
0x00005470       BGT read_wait_uart_rx

read_complete:
0x00005478       MOV R1 R8
0x0000547C       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00005484       LI R1 uart_rx_waitq
0x0000548C       LI R2 WAIT_UART_RX
0x00005494       BL waitq_prepare_sleep

0x0000549C       LDW R4 [R9 + UARTDEV_MMIO]
0x000054A0       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x000054A4       AND R10 R10 1
0x000054A8       CMP R10 0
0x000054AC       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x000054B4       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x000054BC       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x000054C4       LI R1 uart_rx_waitq
0x000054CC       BL waitq_cancel_sleep_current

0x000054D4       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x000054DC       LI R1 0
0x000054E4       B read_return

con_read_fault:
0x000054EC       LI R1 ERR_FAULT

read_return:
0x000054F4       POP R12
0x000054F8       POP R11
0x000054FC       POP R10
0x00005500       POP R9
0x00005504       POP R8
0x00005508       POP LR
0x0000550C       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00005510       LDW R1 [SP + TF_R1]
0x00005514       LDW R2 [SP + TF_R2]
0x00005518       LDW R3 [SP + TF_R3]

0x0000551C       BL vfs_write

0x00005524       STW R1 [SP + TF_R1]
0x00005528       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00005530       PUSH LR
0x00005534       MOV R9 R1
0x00005538       MOV R7 R2
0x0000553C       MOV R6 R3
0x00005540       LDW R9 [R9 + FILE_INODE]
0x00005544       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00005548       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00005550       CMP R6 0
0x00005554       BEQ write_done             ;0 bytes

0x0000555C       LI R2 KBUFFER_SIZE
0x00005564       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00005568       BLT write_chunk_small
0x00005570       LI R2 KBUFFER_SIZE

0x00005578       B write_chunk

write_chunk_small:
0x00005580       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x00005584       PUSH R7
0x00005588       PUSH R6
0x0000558C       PUSH R9
0x00005590       PUSH R8
0x00005594       MOV R1 R7
0x00005598       MOV R2 R2
0x0000559C       LI R3 0                ; read access for source buffer
0x000055A4       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x000055AC       POP R8
0x000055B0       POP R9
0x000055B4       POP R6
0x000055B8       POP R7
0x000055BC       CMP R1 1
0x000055C0       BNE driver_bad_pointer

0x000055C8       PUSH R7
0x000055CC       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x000055D0   LI R1 CURRENT_TASK
0x000055D8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000055DC   LI R1 TASK_SIZE
0x000055E4   MUL R3 R4 R1
0x000055E8   LI R5 tasks
0x000055F0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x000055F4   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x000055F8       MOV R1 R7
0x000055FC       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00005604       MOV R10 R1             ; bytes copied
0x00005608       POP R6
0x0000560C       POP R7

0x00005610       PUSH R7
0x00005614       PUSH R9
0x00005618       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x0000561C       LDW R1 [R9 + UARTDEV_MMIO]
0x00005620       LDW R2 [R1 + 4]
0x00005624       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00005628       CMP R2 0
0x0000562C       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00005634   LI R1 CURRENT_TASK
0x0000563C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005640   LI R1 TASK_SIZE
0x00005648   MUL R3 R4 R1
0x0000564C   LI R5 tasks
0x00005654   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00005658   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x0000565C       MOV R2 R10
0x00005660       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x00005664       BL device_write
0x0000566C       POP R6
0x00005670       POP R9
0x00005674       POP R7

0x00005678       CMP R1 0        ;nothing is written - go again
0x0000567C       BEQ write_loop

0x00005684       ADD R8 R8 R1     ;update ptrs
0x00005688       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x0000568C       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x00005690       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00005698       LI R1 uart_tx_waitq
0x000056A0       LI R2 WAIT_UART_TX
0x000056A8       BL waitq_prepare_sleep

0x000056B0       LDW R1 [R9 + UARTDEV_MMIO]
0x000056B4       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x000056B8       AND R2 R2 2
0x000056BC       CMP R2 0
0x000056C0       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x000056C8       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x000056D0       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x000056D8       LI R1 uart_tx_waitq
0x000056E0       BL waitq_cancel_sleep_current

0x000056E8       B write_wait_uart_tx

write_done:
0x000056F0       MOV R1 R8
0x000056F4       POP LR
0x000056F8       RET

driver_bad_pointer:
0x000056FC       LI R1 ERR_FAULT
0x00005704       POP LR
0x00005708       RET

bad_fd:
0x0000570C       LI R1 ERR_BADF
0x00005714       STW R1 [SP + TF_R1]

0x00005718       B trap_restore

bad_pointer:
0x00005720       LI R1 ERR_FAULT
0x00005728       STW R1 [SP + TF_R1]

0x0000572C       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x00005734       LDW R4 [R1 + FILE_INODE]
0x00005738       LDW R4 [R4 + INODE_OPS]
0x0000573C       LDW R4 [R4 + FSOPS_READ]
0x00005740       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00005744       LDW R4 [R1 + FILE_INODE]
0x00005748       LDW R4 [R4 + INODE_OPS]
0x0000574C       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x00005750       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00005754       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x0000575C       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when CR or LF is received.
0x00005764       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00005768       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00005770       CMP R5 R2                   ; have we read enough bytes?
0x00005774       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x0000577C       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00005780       AND R6 R6 1                 ; bit 0 = RX_READY
0x00005784       CMP R6 0
0x00005788       BEQ dr_done                 ; no more buffered input available

0x00005790       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x00005794       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00005798       ADD R5 R5 1

    ; If we received a line terminator, stop reading early.
0x0000579C       CMP R7 10
0x000057A0       BEQ dr_done
0x000057A8       CMP R7 13
0x000057AC       BEQ dr_done

0x000057B4       B dr_loop

dr_done:
0x000057BC       MOV R1 R5                   ; return number of bytes actually read
0x000057C0       RET

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
0x000057C4       PUSH LR

    ; mutex for write to console lock
0x000057C8       PUSH R1
0x000057CC       PUSH R2
0x000057D0       PUSH R3

    ; Lock console mutex
0x000057D4       BL console_lock

    ; Write to UART
0x000057DC       POP R3
0x000057E0       POP R2
0x000057E4       POP R1


0x000057E8       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000057EC       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000057F4       CMP R5 R2                   ; have we written all bytes?
0x000057F8       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00005800       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00005804       AND R6 R6 2                 ; bit 1 = TX_READY
0x00005808       CMP R6 0
0x0000580C       BEQ dcw_done

0x00005814       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x00005818       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x0000581C       ADD R5 R5 1
0x00005820       B dcw_loop

dcw_done:
0x00005828       MOV R1 R5                   ; return number of bytes written


 ; Unlock console mutex for exclusive write to uart device
0x0000582C       PUSH R1
0x00005830       BL console_unlock
0x00005838       POP R1


0x0000583C       POP LR
0x00005840       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00005844       LI R1 0
0x0000584C       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00005850       PUSH LR
0x00005854       MOV R6 R3
0x00005858       CMP R6 0
0x0000585C       BEQ null_write_done

0x00005864       PUSH R6
0x00005868       MOV R1 R2
0x0000586C       MOV R2 R6
0x00005870       LI R3 0                    ; read access from user source
0x00005878       BL user_buffer_valid_range
0x00005880       POP R6
0x00005884       CMP R1 1
0x00005888       BNE null_write_badptr

null_write_done:
0x00005890       MOV R1 R6
0x00005894       POP LR
0x00005898       RET

null_write_badptr:
0x0000589C       LI R1 ERR_FAULT
0x000058A4       POP LR
0x000058A8       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = required flags
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================
0x000058AC       PUSH R5
0x000058B0       PUSH R6
0x000058B4       PUSH R8

0x000058B8       CMP R1 0
0x000058BC       BLT fd_invalid
0x000058C4       CMP R1 MAX_FDS
0x000058C8       BGE fd_invalid

0x000058D0       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x000058D4   LI R1 CURRENT_TASK
0x000058DC   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000058E0   LI R1 TASK_SIZE
0x000058E8   MUL R3 R4 R1
0x000058EC   LI R4 tasks
0x000058F4   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x000058F8   LDW R4 [R4 + TASK_FD_TABLE]

0x000058FC       SHL R5 R8 2
0x00005900       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x00005904       LDW R1 [R4]                 ; R1 = file ptr
0x00005908       LDW R6 [R1 + FILE_FLAGS]
0x0000590C       AND R6 R6 R2
0x00005910       CMP R6 R2
0x00005914       BNE fd_invalid

0x0000591C       POP R8
0x00005920       POP R6
0x00005924       POP R5
0x00005928       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x0000592C       POP R8
0x00005930       POP R6
0x00005934       POP R5

0x00005938       LI R1 0
0x00005940       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x00005944       PUSH LR
0x00005948       MOV R7 R2
0x0000594C       MOV R10 R3

0x00005950       LI R2 FD_FLAG_READ
0x00005958       BL fetch_fd_entry   ; macro inside destroys R6

0x00005960       CMP R1 0
0x00005964       BEQ vfs_read_badfd

0x0000596C       MOV R9 R1
0x00005970       MOV R1 R9
0x00005974       MOV R2 R7
0x00005978       MOV R3 R10
0x0000597C       BL file_read
0x00005984       POP LR
0x00005988       RET

vfs_read_badfd:
0x0000598C       LI R1 ERR_BADF
0x00005994       POP LR
0x00005998       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x0000599C       PUSH LR
0x000059A0       MOV R7 R2
0x000059A4       MOV R10 R3

0x000059A8       LI R2 FD_FLAG_WRITE
0x000059B0       BL fetch_fd_entry   ;macro inside desroys R6 (fixed)

0x000059B8       CMP R1 0
0x000059BC       BEQ vfs_write_badfd

0x000059C4       MOV R9 R1
0x000059C8       MOV R1 R9           ; R1 - file* acc to fd
0x000059CC       MOV R2 R7
0x000059D0       MOV R3 R10
0x000059D4       BL file_write
0x000059DC       POP LR
0x000059E0       RET

vfs_write_badfd:
0x000059E4       LI R1 ERR_BADF
0x000059EC       POP LR
0x000059F0       RET






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
0x000059F4       PUSH R5
0x000059F8       PUSH R6
0x000059FC       PUSH R7
0x00005A00       PUSH R8
0x00005A04       PUSH R9
0x00005A08       PUSH R10
0x00005A0C       PUSH R11
0x00005A10       PUSH R12

0x00005A14       LI R4 0
0x00005A1C       CMP R2 R4
0x00005A20       BEQ uv_valid

0x00005A28       LI R4 USER_BASE
0x00005A30       CMP R1 R4
0x00005A34       BLT uv_invalid

0x00005A3C       LI R4 USER_LIMIT
0x00005A44       ADD R5 R1 R2
0x00005A48       SUB R5 R5 1
0x00005A4C       CMP R5 R1
0x00005A50       BLT uv_invalid
0x00005A58       CMP R5 R4
0x00005A5C       BGT uv_invalid
0x00005A64       MOV R11 R1              ; save start address; task macros clobber R1
0x00005A68       MOV R12 R5              ; save end address for page calculation
0x00005A6C       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x00005A70   LI R1 CURRENT_TASK
0x00005A78   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00005A7C   LI R1 TASK_SIZE
0x00005A84   MUL R3 R6 R1
0x00005A88   LI R6 tasks
0x00005A90   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00005A94   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x00005A98       CMP R6 0
0x00005A9C       BEQ uv_invalid

uv_check_pages:
0x00005AA4       SHR R7 R11 12
0x00005AA8       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00005AAC       CMP R7 R8
0x00005AB0       BGT uv_valid
0x00005AB8       SHL R9 R7 2
0x00005ABC       ADD R9 R9 R6
0x00005AC0       LDW R10 [R9]
0x00005AC4       AND R5 R10 PTE_P
0x00005AC8       CMP R5 0
0x00005ACC       BEQ uv_invalid
0x00005AD4       AND R5 R10 PTE_U
0x00005AD8       CMP R5 0
0x00005ADC       BEQ uv_invalid
0x00005AE4       CMP R4 0
0x00005AE8       BEQ uv_check_read
0x00005AF0       AND R5 R10 PTE_W
0x00005AF4       CMP R5 0
0x00005AF8       BEQ uv_invalid
0x00005B00       B uv_next

uv_check_read:
0x00005B08       AND R5 R10 PTE_R
0x00005B0C       CMP R5 0
0x00005B10       BEQ uv_invalid

uv_next:
0x00005B18       ADD R7 R7 1
0x00005B1C       B uv_loop

uv_valid:
0x00005B24       LI R1 1
0x00005B2C       POP R12
0x00005B30       POP R11
0x00005B34       POP R10
0x00005B38       POP R9
0x00005B3C       POP R8
0x00005B40       POP R7
0x00005B44       POP R6
0x00005B48       POP R5
0x00005B4C       RET

uv_invalid:
0x00005B50       LI R1 0

0x00005B58       POP R12
0x00005B5C       POP R11
0x00005B60       POP R10
0x00005B64       POP R9
0x00005B68       POP R8
0x00005B6C       POP R7
0x00005B70       POP R6
0x00005B74       POP R5
0x00005B78       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00005B7C       PUSH R5
0x00005B80       PUSH R6
0x00005B84       PUSH R7
0x00005B88       LI R5 0
cfu_head:
0x00005B90       CMP R2 0
0x00005B94       BEQ cfu_done
0x00005B9C       OR R6 R1 R4
0x00005BA0       AND R6 R6 3
0x00005BA4       CMP R6 0
0x00005BA8       BEQ cfu_word
0x00005BB0       LDB R7 [R1]
0x00005BB4       STB R7 [R4]
0x00005BB8       ADD R1 R1 1
0x00005BBC       ADD R4 R4 1
0x00005BC0       ADD R5 R5 1
0x00005BC4       SUB R2 R2 1
0x00005BC8       B cfu_head
cfu_word:
0x00005BD0       CMP R2 4
0x00005BD4       BLT cfu_tail
0x00005BDC       LDW R7 [R1]
0x00005BE0       STW R7 [R4]
0x00005BE4       ADD R1 R1 4
0x00005BE8       ADD R4 R4 4
0x00005BEC       ADD R5 R5 4
0x00005BF0       SUB R2 R2 4
0x00005BF4       B cfu_word
cfu_tail:
0x00005BFC       CMP R2 0
0x00005C00       BEQ cfu_done
0x00005C08       LDB R7 [R1]
0x00005C0C       STB R7 [R4]
0x00005C10       ADD R1 R1 1
0x00005C14       ADD R4 R4 1
0x00005C18       ADD R5 R5 1
0x00005C1C       SUB R2 R2 1
0x00005C20       B cfu_tail
cfu_done:
0x00005C28       MOV R1 R5
0x00005C2C       POP R7
0x00005C30       POP R6
0x00005C34       POP R5
0x00005C38       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00005C3C       PUSH R5
0x00005C40       PUSH R6
0x00005C44       PUSH R7
0x00005C48       LI R5 0
ctu_head:
0x00005C50       CMP R2 0
0x00005C54       BEQ ctu_done
0x00005C5C       OR R6 R1 R4
0x00005C60       AND R6 R6 3
0x00005C64       CMP R6 0
0x00005C68       BEQ ctu_word
0x00005C70       LDB R7 [R4]
0x00005C74       STB R7 [R1]
0x00005C78       ADD R1 R1 1
0x00005C7C       ADD R4 R4 1
0x00005C80       ADD R5 R5 1
0x00005C84       SUB R2 R2 1
0x00005C88       B ctu_head
ctu_word:
0x00005C90       CMP R2 4
0x00005C94       BLT ctu_tail
0x00005C9C       LDW R7 [R4]
0x00005CA0       STW R7 [R1]
0x00005CA4       ADD R1 R1 4
0x00005CA8       ADD R4 R4 4
0x00005CAC       ADD R5 R5 4
0x00005CB0       SUB R2 R2 4
0x00005CB4       B ctu_word
ctu_tail:
0x00005CBC       CMP R2 0
0x00005CC0       BEQ ctu_done
0x00005CC8       LDB R7 [R4]
0x00005CCC       STB R7 [R1]
0x00005CD0       ADD R1 R1 1
0x00005CD4       ADD R4 R4 1
0x00005CD8       ADD R5 R5 1
0x00005CDC       SUB R2 R2 1
0x00005CE0       B ctu_tail
ctu_done:
0x00005CE8       MOV R1 R5
0x00005CEC       POP R7
0x00005CF0       POP R6
0x00005CF4       POP R5
0x00005CF8       RET

handle_debug:
    ; Debug trap - just return
0x00005CFC       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00005D04       CSRR R1 STVAL

0x00005D08       CMP R1 0
0x00005D0C       BEQ handle_timer_irq

0x00005D14       CMP R1 1
0x00005D18       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00005D20       LI R2 0x00102000
0x00005D28       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x00005D2C       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00005D34       LI R2 0x00102000
0x00005D3C       LI R3 0
0x00005D44       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x00005D48       LI R1 timer_ticks
0x00005D50       LDW R2 [R1]
0x00005D54       ADD R2 R2 1
0x00005D58       STW R2 [R1]

    ;================================================================
    ; Wake sleeping tasks whose time has expired
    ;================================================================

0x00005D5C       LI R1 sleep_waitq
0x00005D64       LDW R8 [R1]                ; R8 = current sleep_waitq mask
0x00005D68       LI R9 0                    ; R9 = tasks to wake bitmask
0x00005D70       LI R3 0                    ; task index

timer_wake_scan:
0x00005D78       CMP R3 MAX_TASKS
0x00005D7C       BGE timer_wake_scan_done

    ; Check if this task is in the sleep wait queue
0x00005D84       LI R6 1
0x00005D8C       SHL R6 R6 R3               ; bit for this task
0x00005D90       AND R7 R8 R6
0x00005D94       CMP R7 0
0x00005D98       BEQ timer_wake_next        ; not in sleep queue

    ; Task is sleeping, check if it's time to wake
; macro: GET_TASK_PTR R5, R3
0x00005DA0   LI R1 TASK_SIZE
0x00005DA8   MUL R3 R3 R1
0x00005DAC   LI R5 tasks
0x00005DB4   ADD R5 R5 R3
; macro: TASK_GET_WAKE_TIME R7, R5
0x00005DB8   LDW R7 [R5 + TASK_WAKE_TIME]
0x00005DBC       CMP R2 R7                  ; current time >= wake time?
0x00005DC0       BLT timer_wake_next

    ; Mark this task for wakeup
0x00005DC8       OR R9 R9 R6                 ; add to wake bitmask bitwize

timer_wake_next:
0x00005DCC       ADD R3 R3 1
0x00005DD0       B timer_wake_scan

timer_wake_scan_done:
    ; If no tasks to wake, skip
0x00005DD8       CMP R9 0
0x00005DDC       BEQ timer_no_wake

    ; Wake the expired tasks using our new function
0x00005DE4       LI R1 sleep_waitq
0x00005DEC       MOV R2 R9
0x00005DF0       BL waitq_wake_bitmask

timer_no_wake:

    ; Yield the CPU (reschedule and switch tasks)
0x00005DF8       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00005E00       LI R2 0x00102000
0x00005E08       LI R3 1
0x00005E10       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00005E14       LI R1 uart_rx_waitq
0x00005E1C       BL waitq_wake_all
0x00005E24       LI R1 uart_tx_waitq
0x00005E2C       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00005E34       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00005E3C       POP R1                  ; stval, informational only
0x00005E40       POP R1                  ; scause, informational only
0x00005E44       POP R1
0x00005E48       CSRW SSTATUS R1
0x00005E4C       POP R1
0x00005E50       CSRW SFLAGS R1
0x00005E54       POP R1
0x00005E58       CSRW SEPC R1
0x00005E5C       POP R1                  ; interrupted task SP
0x00005E60       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00005E64       POP R15
0x00005E68       POP R14
0x00005E6C       POP R12
0x00005E70       POP R11
0x00005E74       POP R10
0x00005E78       POP R9
0x00005E7C       POP R8
0x00005E80       POP R7
0x00005E84       POP R6
0x00005E88       POP R5
0x00005E8C       POP R4
0x00005E90       POP R3
0x00005E94       POP R2
0x00005E98       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00005E9C       CSRRW SP SSCRATCH SP
0x00005EA0       SRET


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
; NSFS data and sructures
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

.EQU NSFS_TYPE_FILE,      1
.EQU NSFS_TYPE_DIR,       2

.EQU NSFS_WIRE_TYPE,      0
.EQU NSFS_WIRE_SIZE,      4
.EQU NSFS_WIRE_VERSION,   8
.EQU NSFS_WIRE_PATH_LEN, 12
.EQU NSFS_WIRE_HDR_SIZEOF, 16

.EQU NSFS_INDEX_TYPE,     0
.EQU NSFS_INDEX_SIZE,     4
.EQU NSFS_INDEX_VERSION,  8
.EQU NSFS_INDEX_PATH,    12
.EQU NSFS_INDEX_PATH_LEN, 16
.EQU NSFS_INDEX_ENTRY_SIZEOF, 20
.EQU NSFS_INDEX_MAX_ENTRIES, 64
.EQU NSFS_INDEX_PATH_POOL_SIZE, 2048

;=========================================================================
;
;
;=========================================================================

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

;=========================================================================
;
;
;=========================================================================

nsfs_root_inode:
    .WORD nsfs_ops          ; INODE_OPS
    .WORD nsfs_root_node    ; INODE_PRIVATE
    .WORD INODE_DIR         ; INODE_TYPE
    .WORD 0                 ; size
    .WORD 1                 ; refcnt

nsfs_root_path:
    .ASCIIZ "/"

;=========================================================================
;
;
;=========================================================================


nsfs_root_node:
    .WORD NSFS_DEFAULT_NS
    .WORD nsfs_root_path
    .WORD INODE_DIR
    .WORD 0
    .WORD 0

;=========================================================================
;
;
;=========================================================================

nsfs_node_pool:
    .SPACE NSFS_MAX_NODES * NSFS_NODE_SIZEOF

nsfs_node_used:
    .SPACE NSFS_MAX_NODES * 4

nsfs_index_count:
    .WORD 0

nsfs_index_table:
    .SPACE NSFS_INDEX_MAX_ENTRIES * NSFS_INDEX_ENTRY_SIZEOF

nsfs_index_path_next:
    .WORD nsfs_index_path_pool

nsfs_index_path_pool:
    .SPACE NSFS_INDEX_PATH_POOL_SIZE

;=========================================================================
;
;
;=========================================================================

uart_rx_queue:
    .WORD 0

uart_tx_queue:
    .WORD 0

;=========================================================================
;
;
;=========================================================================

con_device:
    .WORD uart_rx_queue
    .WORD uart_tx_queue
    .WORD 0x00100000

;=========================================================================
; pipe ops
;
;=========================================================================

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

;=========================================================================
;
;
;=========================================================================

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

;=========================================================================
; pipe struct
;
;=========================================================================

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

;=========================================================================
; VFS inst for tarfs
;
;=========================================================================


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

;=========================================================================
; VFS inode inst for tarfs
;
;=========================================================================

tarfs_inode:
    .WORD tarfs_ops
    .WORD tar_index





; ==================================================
; TARFS - RO initial system (load/start process)
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
0x00008F41       LI R1 0
0x00008F49       RET

tarfs_close:
0x00008F4D       LI R1 0
0x00008F55       RET

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

0x00008F59       PUSH LR
0x00008F5D       PUSH R8
0x00008F61       PUSH R9
0x00008F65       PUSH R10

0x00008F69       MOV R8 R1              ; pathname
0x00008F6D       LDB R2 [R8]
0x00008F71       LI R3 47               ; accept normal absolute paths: "/etc/motd"
0x00008F79       CMP R2 R3
0x00008F7D       BNE lookup_path_ready
0x00008F85       ADD R8 R8 1

lookup_path_ready:

0x00008F89       LI R9 0                ; index

0x00008F91       LI R10 tar_count
0x00008F99       LDW R10 [R10]

tar_lookup_loop:

0x00008F9D       CMP R9 R10
0x00008FA1       BGE tar_lookup_not_found

    ; entry address

0x00008FA9       LI R1 tar_index

0x00008FB1       LI R2 TAR_IDX_SIZEOF
0x00008FB9       MUL R3 R9 R2
0x00008FBD       ADD R1 R1 R3            ;

    ; compare names

0x00008FC1       MOV R2 R8

0x00008FC5       LDW R1 [R1 + TAR_IDX_NAME]

0x00008FC9       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x00008FD1       CMP R1 1
0x00008FD5       BEQ tar_lookup_found

0x00008FDD       ADD R9 R9 1
0x00008FE1       B tar_lookup_loop

tar_lookup_found:

0x00008FE9       LI R1 tar_index
0x00008FF1       LI R2 TAR_IDX_SIZEOF
0x00008FF9       MUL R3 R9 R2
0x00008FFD       ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

0x00009001       BL inode_alloc
0x00009009       CMP R1 0
0x0000900D       BEQ tar_lookup_not_found
0x00009015       MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

0x00009019       MOV R1 R10              ; inode
0x0000901D       LI  R2 tarfs_ops        ; ops table
0x00009025       MOV R3 R11              ; private = tar entry

0x00009029       LDW R4 [R11 + TAR_IDX_TYPE] ; FILE type
0x0000902D       LDW R5 [R11 + TAR_IDX_SIZE] ; file size
0x00009031       BL inode_init

0x00009039       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x0000903D       POP R10
0x00009041       POP R9
0x00009045       POP R8
0x00009049       POP LR
0x0000904D       RET

tar_lookup_not_found:

0x00009051       LI R1 0             ; R1 = NULL

0x00009059       POP R10
0x0000905D       POP R9
0x00009061       POP R8
0x00009065       POP LR
0x00009069       RET


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

0x0000906D       PUSH LR
0x00009071       PUSH R8
0x00009075       PUSH R9
0x00009079       PUSH R10
0x0000907D       PUSH R11
0x00009081       PUSH R12

0x00009085       MOV R8 R1                  ; current tar header
0x00009089       LI R11 tar_limit
0x00009091       ADD R2 R1 R2
0x00009095       STW R2 [R11]               ; exclusive end of archive

0x00009099       LI R9 tar_index            ; current index entry

0x000090A1       LI R10 0                   ; file count

tar_scan_loop:

0x000090A9       CMP R10 MAX_TAR_FILES
0x000090AD       BGE tar_done                ; check before writing the next index entry

0x000090B5       LI R11 tar_limit
0x000090BD       LDW R11 [R11]
0x000090C1       LI R12 TAR_HEADER_SIZE
0x000090C9       ADD R12 R8 R12
0x000090CD       CMP R12 R11
0x000090D1       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x000090D9       LDB R11 [R8 + TAR_NAME_OFF]

0x000090DD       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x000090E1       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x000090E9       MOV R11 R8

0x000090ED       ADD R11 R11 TAR_NAME_OFF

0x000090F1       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x000090F5       MOV R1 R8
0x000090F9       ADD R1 R1 TAR_SIZE_OFF

    ;R1 = ptr to TAR size field

0x000090FD       BL tar_parse_octal         ; parse octal size from tar header field to binary integer

0x00009105       MOV R12 R1                 ; save file resulted binary size

0x00009109       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x0000910D       MOV R11 R8
0x00009111       LI R2 TAR_HEADER_SIZE
0x00009119       ADD R11 R11 R2

0x0000911D       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00009121       LI R2 TAR_TYPE_OFF
0x00009129       ADD R2 R8 R2
0x0000912D       LDB R11 [R2]
0x00009131       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00009135       ADD R10 R10 1               ; othewise go to next file count

0x00009139       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------

0x0000913D       MOV R11 R12

    ; round up to 512 boundary

0x00009141       LI R2 511
0x00009149       ADD R11 R11 R2

0x0000914D       SHR R11 R11 9
0x00009151       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x00009155       LI R2 TAR_HEADER_SIZE
0x0000915D       ADD R8 R8 R2

0x00009161       ADD R8 R8 R11           ; advance to next tar header

0x00009165       LI R12 tar_limit
0x0000916D       LDW R12 [R12]
0x00009171       CMP R8 R12
0x00009175       BGTU tar_done            ; file data/padding extends beyond archive

0x0000917D       B tar_scan_loop

tar_done:

0x00009185       LI R11 tar_count        ; store total file count for this tar archive in global variable

0x0000918D       STW R10 [R11]

0x00009191       POP R12
0x00009195       POP R11
0x00009199       POP R10
0x0000919D       POP R9
0x000091A1       POP R8
0x000091A5       POP LR

0x000091A9       RET

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

0x000091AD       PUSH R2
0x000091B1       PUSH R3
0x000091B5       PUSH R4

0x000091B9       LI   R2 0                  ; result

octal_loop:

0x000091C1       LDB  R3 [R1]

    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32

0x000091C5       CMP  R3 0
0x000091C9       BEQ  octal_done

0x000091D1       LI   R4 32                 ; ' '
0x000091D9       CMP  R3 R4
0x000091DD       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x000091E5       LI   R4 48
0x000091ED       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x000091F1       SHL  R2 R2 3               ; multiply by 8

0x000091F5       ADD  R2 R2 R3              ; add digit

0x000091F9       ADD  R1 R1 1               ; advance to next octal character

0x000091FD       B    octal_loop

octal_done:

0x00009205       MOV  R1 R2                 ; return binary result in R1

0x00009209       POP  R4
0x0000920D       POP  R3
0x00009211       POP  R2
0x00009215       RET

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

0x00009230       PUSH LR
0x00009234       PUSH R8
0x00009238       PUSH R9
0x0000923C       PUSH R10

0x00009240       LI R8 0

0x00009248       LI R10 tar_count
0x00009250       LDW R10 [R10]

0x00009254       LI R1 tarfs_banner
0x0000925C       BL kputs

dump_loop:

0x00009264       CMP R8 R10
0x00009268       BGE dump_done

    ; entry = tar_index + i*sizeof(entry)

0x00009270       LI R1 tar_index

0x00009278       LI R2 TAR_IDX_SIZEOF
0x00009280       MUL R3 R8 R2

0x00009284       ADD R9 R1 R3

    ; filename

0x00009288       LDW R2 [R9 + TAR_IDX_NAME]

    ; print string somehow

0x0000928C       MOV R1 R2
0x00009290       BL kputs

    ; newline

0x00009298       LI R1 newline
0x000092A0       BL kputs

0x000092A8       ADD R8 R8 1
0x000092AC       B dump_loop

dump_done:

0x000092B4       POP R10
0x000092B8       POP R9
0x000092BC       POP R8
0x000092C0       POP LR
0x000092C4       RET

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

0x000092C8       PUSH LR
0x000092CC       PUSH R8
0x000092D0       PUSH R9
0x000092D4       PUSH R10
0x000092D8       PUSH R11
0x000092DC       PUSH R12

0x000092E0       MOV R8 R1
0x000092E4       MOV R9 R2
0x000092E8       MOV R10 R3

0x000092EC       CMP R10 0
0x000092F0       BEQ tarfs_read_eof

0x000092F8       PUSH R8
0x000092FC       PUSH R9
0x00009300       MOV R1 R9
0x00009304       MOV R2 R10
0x00009308       LI R3 1                    ; destination must be user-writable
0x00009310       BL user_buffer_valid_range
0x00009318       POP R9
0x0000931C       POP R8
0x00009320       CMP R1 1
0x00009324       BNE tarfs_read_fault

0x0000932C       LDW R11 [R8 + FILE_INODE]
0x00009330       LDW R5  [R11 + INODE_TYPE]
0x00009334       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x00009338       LI  R2 INODE_DIR
0x00009340       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x00009344       BEQ tarfs_read_dir

0x0000934C       LDW R12 [R8 + FILE_OFFSET]
0x00009350       LDW R4  [R11 + TAR_IDX_SIZE]

0x00009354       CMP R12 R4
0x00009358       BGEU tarfs_read_eof

0x00009360       SUB R4 R4 R12             ; bytes remaining
0x00009364       CMP R10 R4
0x00009368       BLEU tarfs_read_count_ready
0x00009370       MOV R10 R4

tarfs_read_count_ready:
0x00009374       LDW R4 [R11 + TAR_IDX_DATA]
0x00009378       ADD R4 R4 R12             ; kernel source
0x0000937C       MOV R1 R9                 ; user destination
0x00009380       MOV R2 R10
0x00009384       BL copy_to_user

0x0000938C       ADD R12 R12 R1
0x00009390       STW R12 [R8 + FILE_OFFSET]
0x00009394       B tarfs_read_done

tarfs_read_dir:
    ; directory read – call our dir read function
0x0000939C       MOV R1 R8
0x000093A0       MOV R2 R9
0x000093A4       MOV R3 R10
0x000093A8       BL tarfs_readdir
0x000093B0       B tarfs_read_done   ; jump to the common return path

tarfs_read_fault:
0x000093B8       LI R1 ERR_FAULT
0x000093C0       B tarfs_read_done

tarfs_read_eof:
0x000093C8       LI R1 0

tarfs_read_done:
0x000093D0       POP R12
0x000093D4       POP R11
0x000093D8       POP R10
0x000093DC       POP R9
0x000093E0       POP R8
0x000093E4       POP LR
0x000093E8       RET

tarfs_write:
0x000093EC       LI R1 ERR_ACCES
0x000093F4       RET

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
0x000093F8       PUSH LR
0x000093FC       PUSH R8
0x00009400       PUSH R9
0x00009404       PUSH R10
0x00009408       PUSH R11
0x0000940C       PUSH R12

    ; ---- validate user buffer ----
0x00009410       MOV R8 R2                 ; save user buffer + to stack
0x00009414       PUSH R8
0x00009418       MOV R9 R3                 ; save length
0x0000941C       MOV R12 R1                ; save file ptr
0x00009420       CMP R9 DIRENT_SIZEOF
0x00009424       BLT readdir_short         ; not enough space for one entry

    ;PUSH R9
0x0000942C       MOV R1 R8
0x00009430       LI  R2 DIRENT_SIZEOF
0x00009438       LI  R3 1                  ; write access
0x00009440       BL  user_buffer_valid_range
    ;POP R9
0x00009448       CMP R1 1
0x0000944C       BNE readdir_fault

    ; ---- get inode and private data ----
0x00009454       LDW R4 [R12 + FILE_INODE]    ; R4 = inode* r12 -file ptf
0x00009458       LDW R5 [R4 + INODE_PRIVATE] ; R5 = tar index entry for the directory itself
0x0000945C       CMP R5 0
0x00009460       BEQ readdir_eof

    ; get directory prefix from that tar entry (e.g., "etc/")
0x00009468       LDW R10 [R5 + TAR_IDX_NAME] ; R10 = full path of directory (with trailing /)

    ; load current entry index from file offset
0x0000946C       LDW R11 [R12 + FILE_OFFSET] ; R11 = index (number of entries already returned)

    ; ---- scan tar index from this index ----
    ;LI R12 tar_count
    ;LDW R12 [R12]             ; total number of tar entries
0x00009470       MOV R6 R11                ; current scan index

readdir_scan:
0x00009474       LI  R1 tar_count          ;total number entryes in index count
0x0000947C       LDW R1 [R1]
0x00009480       CMP R6 R1
0x00009484       BGE readdir_nsfs_start    ; no more tar entries; append overlay entries

    ; entry = tar_index + R6 * TAR_IDX_SIZEOF
0x0000948C       LI R1 tar_index
0x00009494       LI R2 TAR_IDX_SIZEOF
0x0000949C       MUL R3 R6 R2
0x000094A0       ADD R7 R1 R3              ; R7 = &tar_index[R6]

    ; check if this entry's name starts with the directory prefix
0x000094A4       LDW R1 [R7 + TAR_IDX_NAME]
0x000094A8       MOV R2 R10
0x000094AC       BL str_prefix            ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000094B4       CMP R1 1
0x000094B8       BNE readdir_skip

    ; skip the directory entry itself (exact match)
0x000094C0       LDW R1 [R7 + TAR_IDX_NAME]
0x000094C4       MOV R2 R10
0x000094C8       BL strcmp                ; ie skip if we read 'etc/' == etc/
0x000094D0       CMP R1 1
0x000094D4       BEQ readdir_skip

    ; ---- found a matching file/directory ----
    ; skip the prefix to get the relative component
0x000094DC       LDW R1 [R7 + TAR_IDX_NAME]
0x000094E0       MOV R2 R10
0x000094E4       BL skip_prefix            ; R1 = pointer after prefix omit prefix - just filename 'etc/bin' -> bin
0x000094EC       MOV R9 R1                 ; R9 = component name (e.g., "motd" (file) or "network/ (subdir)")

    ; compute the component length up to next '/'
0x000094F0       MOV R1 R9
0x000094F4       BL path_component_len     ; R1 = component length (L)
0x000094FC       MOV R8 R1                 ; R8 = component name length

    ; clamp to DIRENT_NAME_LEN - 1 to avoid overflow
0x00009500       LI R2 63
0x00009508       CMP R8 R2
0x0000950C       BLE readdir_name_ok
0x00009514       MOV R8 63
readdir_name_ok:
    ; save R6 cureent entry index
0x00009518       MOV R11 R6
    ;get type
0x0000951C       LDW R6  [R7 + TAR_IDX_TYPE]  ;R6  R11 = tar type (0=file, 5=dir)

    ; map tar type to DT_* constants
0x00009520       LI  R1 INODE_DIR     ;adapted 35hex yess
0x00009528       CMP R6 R1
    ;CMP R6 5            ;needs to be adapted 35hex
0x0000952C       BEQ readdir_type_dir
0x00009534       LI R6 DT_REG               ; default type to regular r11 - file
0x0000953C       B readdir_type_done
readdir_type_dir:
0x00009544       LI R6 DT_DIR               ; switch type R11 - dir
readdir_type_done:

    ; ---- build struct dirent in KBUF_WR ----
; macro: GET_CURR_TASK_IDX R4
0x0000954C   LI R1 CURRENT_TASK
0x00009554   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00009558   LI R1 TASK_SIZE
0x00009560   MUL R3 R4 R1
0x00009564   LI R5 tasks
0x0000956C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00009570   LDW R1 [R5 + TASK_KBUF_WR_PTR]


   ; GET_CURR_TASK_IDX R2
   ; GET_TASK_PTR R2, R2
   ; TASK_GET_KBUF_WR R5, R2    ; R5 = kernel write buffer

    ; d_ino = index + 1 (dummy); R1 = kernel write buffer - form dirent stuc with read dir-entry
0x00009574       ADD R3 R11 1
0x00009578       STW R3 [R1 + DIRENT_INODE]
    ; d_type = DT_REG or DT_DIR
0x0000957C       STW R6 [R1 + DIRENT_TYPE]

    ; get size from tar entry
0x00009580       LDW R2  [R7 + TAR_IDX_SIZE]  ; R12 = file size
    ; d_size = file size
0x00009584       STW R2  [R1 + DIRENT_SIZE]

    ; ---- update file offset to next entry ----
    ;ADD R6 R6 1
0x00009588       STW R3 [R12 + FILE_OFFSET] ; store new index R11+1 for next read


    ; d_name = component name (copy up to 64 bytes)
0x0000958C       MOV R2 R9                  ; source name R9 = component name (e.g., "motd" (file) or "network/ (subdir)")
0x00009590       ADD R3 R1 DIRENT_NAME      ; destination dirent struc in KBUF_WR
0x00009594       LI  R6 0                   ; index

readdir_copy_name:
0x0000959C       CMP R6 R8                  ;R8 = component name length
0x000095A0       BGE readdir_copy_name_done
0x000095A8       LDB R10 [R2 + R6]
0x000095AC       STB R10 [R3 + R6]
0x000095B0       ADD R6 R6 1
0x000095B4       B readdir_copy_name

readdir_copy_name_done:
    ; NUL-terminate
0x000095BC       LI R10 0
0x000095C4       STB R10 [R3 + R6]

    ; ---- copy whole dirent (DIRENT_SIZEOF bytes) to user buffer ----

0x000095C8       LI  R2 DIRENT_SIZEOF      ; len dirent
0x000095D0       MOV R4 R1                 ; kernel source (KBUF_WR)
0x000095D4       POP R1                    ; user buffer (original)
    ;MOV R1 R8                 ; user buffer (original)
0x000095D8       BL copy_to_user
0x000095E0       CMP R1 DIRENT_SIZEOF
0x000095E4       BNE readdir_fault

    ; return number of bytes written (DIRENT_SIZEOF)
0x000095EC       MOV R1 DIRENT_SIZEOF
0x000095F0       POP R12
0x000095F4       POP R11
0x000095F8       POP R10
0x000095FC       POP R9
0x00009600       POP R8
0x00009604       POP LR
0x00009608       RET

readdir_skip:
0x0000960C       ADD R6 R6 1
0x00009610       B readdir_scan

readdir_nsfs_start:
0x00009618       LI R1 tar_count
0x00009620       LDW R1 [R1]
0x00009624       SUB R6 R6 R1              ; convert merged file offset to nsfs index

readdir_nsfs_scan:
0x00009628       LI R1 nsfs_index_count
0x00009630       LDW R1 [R1]
0x00009634       CMP R6 R1
0x00009638       BGE readdir_eof

0x00009640       LI R1 NSFS_INDEX_ENTRY_SIZEOF
0x00009648       MUL R3 R6 R1
0x0000964C       LI R7 nsfs_index_table
0x00009654       ADD R7 R7 R3              ; R7 = &nsfs_index_table[R6]

0x00009658       LDW R1 [R7 + NSFS_INDEX_PATH]
0x0000965C       LDB R2 [R1]
0x00009660       LI R3 47                  ; skip leading '/' for comparison with tar prefix
0x00009668       CMP R2 R3
0x0000966C       BNE readdir_nsfs_prefix_ready
0x00009674       ADD R1 R1 1
readdir_nsfs_prefix_ready:
0x00009678       MOV R2 R10
0x0000967C       BL str_prefix
0x00009684       CMP R1 1
0x00009688       BNE readdir_nsfs_skip

0x00009690       LDW R1 [R7 + NSFS_INDEX_PATH]
0x00009694       LDB R2 [R1]
0x00009698       LI R3 47
0x000096A0       CMP R2 R3
0x000096A4       BNE readdir_nsfs_skip_ready
0x000096AC       ADD R1 R1 1
readdir_nsfs_skip_ready:
0x000096B0       MOV R2 R10
0x000096B4       BL skip_prefix
0x000096BC       MOV R9 R1

0x000096C0       LDB R2 [R9]
0x000096C4       CMP R2 0
0x000096C8       BEQ readdir_nsfs_skip

0x000096D0       MOV R1 R9
0x000096D4       BL path_component_len
0x000096DC       MOV R8 R1
0x000096E0       CMP R8 0
0x000096E4       BEQ readdir_nsfs_skip
0x000096EC       LI R2 63
0x000096F4       CMP R8 R2
0x000096F8       BLE readdir_nsfs_name_ok
0x00009700       MOV R8 R2

readdir_nsfs_name_ok:
; macro: GET_CURR_TASK_IDX R4
0x00009704   LI R1 CURRENT_TASK
0x0000970C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00009710   LI R1 TASK_SIZE
0x00009718   MUL R3 R4 R1
0x0000971C   LI R5 tasks
0x00009724   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00009728   LDW R1 [R5 + TASK_KBUF_WR_PTR]

0x0000972C       LI R2 tar_count
0x00009734       LDW R2 [R2]
0x00009738       ADD R3 R2 R6
0x0000973C       ADD R3 R3 1
0x00009740       STW R3 [R1 + DIRENT_INODE]
0x00009744       STW R3 [R12 + FILE_OFFSET]

0x00009748       LDW R2 [R7 + NSFS_INDEX_SIZE]
0x0000974C       STW R2 [R1 + DIRENT_SIZE]
0x00009750       LDW R2 [R7 + NSFS_INDEX_TYPE]
0x00009754       CMP R2 NSFS_TYPE_DIR
0x00009758       BEQ readdir_nsfs_type_dir
0x00009760       LI R2 DT_REG
0x00009768       B readdir_nsfs_type_done
readdir_nsfs_type_dir:
0x00009770       LI R2 DT_DIR
readdir_nsfs_type_done:
0x00009778       STW R2 [R1 + DIRENT_TYPE]

0x0000977C       MOV R2 R9
0x00009780       ADD R3 R1 DIRENT_NAME
0x00009784       LI R6 0
readdir_nsfs_copy_name:
0x0000978C       CMP R6 R8
0x00009790       BGE readdir_nsfs_copy_done
0x00009798       LDB R10 [R2 + R6]
0x0000979C       STB R10 [R3 + R6]
0x000097A0       ADD R6 R6 1
0x000097A4       B readdir_nsfs_copy_name
readdir_nsfs_copy_done:
0x000097AC       LI R10 0
0x000097B4       STB R10 [R3 + R6]

0x000097B8       LI R2 DIRENT_SIZEOF
0x000097C0       MOV R4 R1
0x000097C4       POP R1
0x000097C8       BL copy_to_user
0x000097D0       CMP R1 DIRENT_SIZEOF
0x000097D4       BNE readdir_fault_after_user_pop
0x000097DC       MOV R1 DIRENT_SIZEOF
0x000097E0       POP R12
0x000097E4       POP R11
0x000097E8       POP R10
0x000097EC       POP R9
0x000097F0       POP R8
0x000097F4       POP LR
0x000097F8       RET

readdir_nsfs_skip:
0x000097FC       ADD R6 R6 1
0x00009800       LI R1 tar_count
0x00009808       LDW R1 [R1]
0x0000980C       ADD R2 R1 R6
0x00009810       STW R2 [R12 + FILE_OFFSET]
0x00009814       B readdir_nsfs_scan

readdir_eof:
0x0000981C       Pop R1          ;bc we saved r8 inside loop
0x00009820       LI R1 0
0x00009828       POP R12
0x0000982C       POP R11
0x00009830       POP R10
0x00009834       POP R9
0x00009838       POP R8
0x0000983C       POP LR
0x00009840       RET

readdir_short:
0x00009844       Pop R1
0x00009848       LI R1 ERR_FAULT
0x00009850       POP R12
0x00009854       POP R11
0x00009858       POP R10
0x0000985C       POP R9
0x00009860       POP R8
0x00009864       POP LR
0x00009868       RET

readdir_fault:
0x0000986C       Pop R1
readdir_fault_after_user_pop:
0x00009870       LI R1 ERR_FAULT
0x00009878       POP R12
0x0000987C       POP R11
0x00009880       POP R10
0x00009884       POP R9
0x00009888       POP R8
0x0000988C       POP LR
0x00009890       RET


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

0x00009894       PUSH LR
0x00009898       PUSH R8
0x0000989C       PUSH R9
0x000098A0       PUSH R10
0x000098A4       PUSH R11

0x000098A8       MOV R8 R1              ; save directory path
0x000098AC       LI R9 0                ; index

0x000098B4       LI R10 tar_count
0x000098BC       LDW R10 [R10]
tr_loop:
0x000098C0       CMP R9 R10
0x000098C4       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x000098CC       LI R1 tar_index
0x000098D4       LI R2 TAR_IDX_SIZEOF
0x000098DC       MUL R3 R9 R2
0x000098E0       ADD R11 R1 R3
    ; entry name
0x000098E4       LDW R1 [R11 + TAR_IDX_NAME]
0x000098E8       MOV R2 R8                       ; src dirname "etc/"
0x000098EC       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000098F4       CMP R1 1
0x000098F8       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x00009900       LDW R1 [R11 + TAR_IDX_NAME]
0x00009904       MOV R2 R8                       ; prefix
0x00009908       BL skip_prefix                  ; omit prefix nd print just filename

0x00009910       MOV R12 R1         ; save component ptr
0x00009914       BL path_component_len ; out R1-length
0x0000991C       MOV R2 R1
0x00009920       MOV R1 R12
0x00009924       BL kputsn   ; r1-ptr r2-len of string

0x0000992C       LI R1 newline
0x00009934       BL kputs

tr_next:
0x0000993C       ADD R9 R9 1                     ;to next entry for check
0x00009940       B tr_loop
tr_done:
0x00009948       POP R11
0x0000994C       POP R10
0x00009950       POP R9
0x00009954       POP R8
0x00009958       POP LR
0x0000995C       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:

0x00009960       PUSH LR
0x00009964       PUSH R8
0x00009968       MOV R8 R1

kputs_loop:
0x0000996C       LDB R1 [R8]

0x00009970       CMP R1 0
0x00009974       BEQ kputs_done

0x0000997C       BL uart_putc

0x00009984       ADD R8 R8 1

0x00009988       B kputs_loop

kputs_done:
0x00009990       POP R8
0x00009994       POP LR
0x00009998       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x0000999C       PUSH LR
0x000099A0       PUSH R8
0x000099A4       PUSH R9
0x000099A8       MOV R8 R1
0x000099AC       MOV R9 R2
kputsn_loop:
0x000099B0       CMP R9 0
0x000099B4       BEQ kputsn_done
0x000099BC       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x000099C0       BL uart_putc
0x000099C8       ADD R8 R8 1
0x000099CC       SUB R9 R9 1
0x000099D0       B kputsn_loop
kputsn_done:
0x000099D8       POP R9
0x000099DC       POP R8
0x000099E0       POP LR
0x000099E4       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x000099E8       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x000099F0       LDW R2 [R3 + 4]   ; read UART status register
0x000099F4       AND R2 R2 2       ; check if TX ready (bit 1)
0x000099F8       CMP R2 0
0x000099FC       BEQ poll

0x00009A04       STW R1 [R3 + 0]   ; R1 is the character value
0x00009A08       RET



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
0x00009A0C       PUSH R8
0x00009A10       PUSH R9
0x00009A14       PUSH R10

0x00009A18       MOV R9 R1                  ; preserve wait queue pointer
0x00009A1C       MOV R10 R2                 ; preserve debug wait reason
0x00009A20       MOV R8 R3                  ; preserve task state to set

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x00009A24   LI R1 CURRENT_TASK
0x00009A2C   LDW R2 [R1]

0x00009A30       LI R4 1
0x00009A38       SHL R4 R4 R2               ; R4 = bit for current task
0x00009A3C       LDW R5 [R9 + WQ_MASK]
0x00009A40       OR R5 R5 R4
0x00009A44       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00009A48   LI R1 TASK_SIZE
0x00009A50   MUL R3 R2 R1
0x00009A54   LI R5 tasks
0x00009A5C   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00009A60   LI R1 TASK_BLOCKED_IO
0x00009A68   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00009A6C   STW R10 [R5 + TASK_WAIT]

; addition trick if R3 is set as TASK_SLEEPING then we also set the state to TASK_SLEEPING for syscall sleep/waitpid
0x00009A70       CMP R8 TASK_SLEEPING
0x00009A74       BNE waitq_prepare_done
; macro: TASK_SET_STATE R5, TASK_SLEEPING
0x00009A7C   LI R1 TASK_SLEEPING
0x00009A84   STW R1 [R5 + TASK_STATE]

waitq_prepare_done:
0x00009A88       POP R10
0x00009A8C       POP R9
0x00009A90       POP R8
0x00009A94       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00009A98       PUSH R9

0x00009A9C       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00009AA0   LI R1 CURRENT_TASK
0x00009AA8   LDW R2 [R1]

0x00009AAC       LDW R4 [R9 + WQ_MASK]

0x00009AB0       LI  R5 1
0x00009AB8       SHL R5 R5 R2        ;shift to position of current task bit

0x00009ABC       NOT R5 R5           ; invert to get mask for clearing this bit

0x00009AC0       AND R4 R4 R5        ; clear current task bit

0x00009AC4       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x00009AC8   LI R1 TASK_SIZE
0x00009AD0   MUL R3 R2 R1
0x00009AD4   LI R5 tasks
0x00009ADC   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x00009AE0   LI R1 TASK_READY
0x00009AE8   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x00009AEC   LI R1 WAIT_NONE
0x00009AF4   STW R1 [R5 + TASK_WAIT]

0x00009AF8       POP R9
0x00009AFC       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x00009B00       PUSH LR
0x00009B04       BL schedule_call
0x00009B0C       POP LR
0x00009B10       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x00009B14       PUSH LR

0x00009B18       MOV R9 R1
0x00009B1C       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00009B20       LI R10 0
0x00009B28       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x00009B2C       LI R2 0                    ; task index

wq_wake_loop:
0x00009B34       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x00009B38       BGE wq_wake_done

0x00009B40       LI R3 1
0x00009B48       SHL R3 R3 R2               ; R3 = bit for task R2
0x00009B4C       AND R4 R8 R3
0x00009B50       CMP R4 0
0x00009B54       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00009B5C   LI R1 TASK_SIZE
0x00009B64   MUL R3 R2 R1
0x00009B68   LI R5 tasks
0x00009B70   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00009B74   LI R1 TASK_READY
0x00009B7C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00009B80   LI R1 WAIT_NONE
0x00009B88   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00009B8C       ADD R2 R2 1
0x00009B90       B wq_wake_loop

wq_wake_done:
0x00009B98       POP LR
0x00009B9C       RET

waitq_wake_bitmask:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = bitmask of tasks to wake (1 = wake, 0 = ignore)
    ; Wakes every task currently recorded in the R2 bitmask.
    ;================================================================

0x00009BA0       PUSH LR

0x00009BA4       MOV R9 R1
0x00009BA8       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00009BAC       MOV R10 R2                 ;
0x00009BB0       NOT R10 R10                ; invert bitmask to clear only specified tasks
0x00009BB4       AND R10 R8 R10             ; clear only specified tasks
0x00009BB8       STW R10 [R9 + WQ_MASK]     ; update queue entries to remove (tobe) woken  tasks

0x00009BBC       MOV R8 R2                  ; R8 = bitmask of tasks to wake
0x00009BC0       LI R2 0                    ; task index

wq_wake_b_loop:
0x00009BC8       CMP R2 MAX_TASKS           ; check if we processed all tasks in bitmask
0x00009BCC       BGE wq_wake_b_done

0x00009BD4       LI R3 1
0x00009BDC       SHL R3 R3 R2               ; R3 = bit for task R2
0x00009BE0       AND R4 R8 R3               ; check if this task is in the wake bitmask
0x00009BE4       CMP R4 0
0x00009BE8       BEQ wq_wake_b_next

; macro: GET_TASK_PTR R5, R2        ; wake task R2 if its in the bitmask
0x00009BF0   LI R1 TASK_SIZE
0x00009BF8   MUL R3 R2 R1
0x00009BFC   LI R5 tasks
0x00009C04   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00009C08   LI R1 TASK_READY
0x00009C10   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00009C14   LI R1 WAIT_NONE
0x00009C1C   STW R1 [R5 + TASK_WAIT]

wq_wake_b_next:
0x00009C20       ADD R2 R2 1
0x00009C24       B wq_wake_b_loop

wq_wake_b_done:
0x00009C2C       POP LR
0x00009C30       RET

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
0x0000A234       LI R2 0                      ; index

ia_loop:
0x0000A23C       CMP R2 MAX_INODES
0x0000A240       BGE ia_fail

0x0000A248       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x0000A24C       LI R4 inode_used
0x0000A254       ADD R4 R4 R3                  ; &inode_used[index]

0x0000A258       LDW R5 [R4]                   ; load used marker
0x0000A25C       CMP R5 0
0x0000A260       BEQ ia_found

0x0000A268       ADD R2 R2 1
0x0000A26C       B ia_loop

ia_found:
0x0000A274       LI R5 1
0x0000A27C       STW R5 [R4]                  ; mark used

0x0000A280       LI R3 INODE_SIZEOF
0x0000A288       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x0000A28C       LI R1 inode_pool
0x0000A294       ADD R1 R1 R6                 ; return inode ptr
0x0000A298       RET

ia_fail:
0x0000A29C       LI R1 0
0x0000A2A4       RET

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

0x0000A2A8       LI R2 inode_pool
0x0000A2B0       SUB R3 R1 R2                  ; offset from pool base

0x0000A2B4       LI R4 INODE_SIZEOF
0x0000A2BC       DIV R5 R3 R4                 ; index

0x0000A2C0       SHL R5 R5 2                  ; index * 4 (u32 array)
0x0000A2C4       LI R6 inode_used
0x0000A2CC       ADD R6 R6 R5                 ; &inode_used[index]

0x0000A2D0       LI R7 0
0x0000A2D8       STW R7 [R6]                  ; mark free

0x0000A2DC       RET

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

0x0000A2E0       STW R2 [R1 + INODE_OPS]
0x0000A2E4       STW R3 [R1 + INODE_PRIVATE]
0x0000A2E8       STW R4 [R1 + INODE_TYPE]
0x0000A2EC       STW R5 [R1 + INODE_SIZE]
0x0000A2F0       LI R2 1
0x0000A2F8       STW R2 [R1 + INODE_REFCNT]
0x0000A2FC       RET

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
0x0000A300       LDW R2 [R1 + INODE_REFCNT]
0x0000A304       ADD R2 R2 1
0x0000A308       STW R2 [R1 + INODE_REFCNT]
0x0000A30C       RET

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
0x0000A310       PUSH LR
0x0000A314       LDW R2 [R1 + INODE_REFCNT]
0x0000A318       SUB R2 R2 1
0x0000A31C       STW R2 [R1 + INODE_REFCNT]
0x0000A320       CMP R2 0
0x0000A324       BNE inode_put_done
    ; destroy inode
0x0000A32C       BL inode_free

inode_put_done:
0x0000A334       POP LR
0x0000A338       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x0000A33C       LDW R2 [R1 + FILE_REFCNT]
0x0000A340       ADD R2 R2 1
0x0000A344       STW R2 [R1 + FILE_REFCNT]
0x0000A348       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x0000A34C       PUSH LR
0x0000A350       LDW R2 [R1 + FILE_REFCNT]
0x0000A354       SUB R2 R2 1
0x0000A358       STW R2 [R1 + FILE_REFCNT]
0x0000A35C       CMP R2 0
0x0000A360       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x0000A368       BL file_free

file_put_done:
0x0000A370       POP LR
0x0000A374       RET


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
0x0000A378       PUSH LR
0x0000A37C       MOV R8 R1          ; pathname

0x0000A380       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x0000A388       CMP R1 0
0x0000A38C       BNE vfs_done

0x0000A394       MOV R1 R8
0x0000A398       BL nsfs_lookup     ; 2 writable overlay above tarfs
0x0000A3A0       CMP R1 0
0x0000A3A4       BNE vfs_done

0x0000A3AC       MOV R1 R8

0x0000A3B0       BL tarfs_lookup     ; 3 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x0000A3B8       CMP R1 0
0x0000A3BC       BEQ vfs_not_found

vfs_done:
0x0000A3C4       POP LR          ;3 R1 - return inode
0x0000A3C8       RET

vfs_not_found:
0x0000A3CC       LI R1 0         ;it can be just ret but i added it for result clarity
0x0000A3D4       POP LR          ;or R1 - Nul
0x0000A3D8       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x0000A3DC       PUSH LR
0x0000A3E0       PUSH R8
0x0000A3E4       PUSH R9
0x0000A3E8       PUSH R10
0x0000A3EC       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x0000A3F0       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x0000A3F8       CMP R1 0
0x0000A3FC       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x0000A404       MOV R8 R1            ; save inode ptr

0x0000A408       LDW R2 [R8 + INODE_TYPE]
0x0000A40C       LI R3 INODE_DIR
0x0000A414       CMP R2 R3

    ;BEQ fail_isdir            ; if pathname is a dir -implemented readdir

0x0000A418       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x0000A420       CMP R1 0
0x0000A424       BEQ fail_nfile

0x0000A42C       MOV R9 R1                ; save file*

    ; initialize file object ;
0x0000A430       MOV R1 R9                ; R1 file*
0x0000A434       MOV R2 R8                ; inode*
0x0000A438       MOV R3 R10               ; flags
0x0000A43C       BL file_init

0x0000A444       MOV R1 R9
0x0000A448       BL fd_alloc             ; R1 inited file ptr
0x0000A450       LI R2 ERR_MFILE
0x0000A458       CMP R1 R2
0x0000A45C       BEQ fail_fd
                            ; R1 - holds fd
0x0000A464       POP R10
0x0000A468       POP R9
0x0000A46C       POP R8
0x0000A470       POP LR
0x0000A474       RET

fail_fd:
0x0000A478       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x0000A47C       LDW R2 [R1 + FILE_INODE]

0x0000A480       MOV R1 R2
0x0000A484       BL inode_put             ; close inode refcnt--

0x0000A48C       MOV R1 R9
0x0000A490       BL file_free
0x0000A498       LI R1 ERR_MFILE
0x0000A4A0       B  vfs_exit

fail_noent:
0x0000A4A8       LI R1 ERR_NOENT
0x0000A4B0       B  vfs_exit
fail_nfile:
0x0000A4B8       LI R1 ERR_NFILE
0x0000A4C0       B  vfs_exit
fail_isdir:
0x0000A4C8       LI R1 ERR_ISDIR
0x0000A4D0       B  vfs_exit
fail_acces:
0x0000A4D8       LI R1 ERR_ACCES
vfs_exit:
0x0000A4E0       POP R10
0x0000A4E4       POP R9
0x0000A4E8       POP R8
0x0000A4EC       POP LR
0x0000A4F0       RET

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
0x0000A4F4       PUSH LR
0x0000A4F8       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x0000A500       CMP R1 0
0x0000A504       BEQ badf_fail

0x0000A50C       MOV R8 R1          ; save file*

0x0000A510       MOV R1 R8
0x0000A514       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x0000A51C       LI  R1 0        ; success
0x0000A524       POP LR
0x0000A528       RET

badf_fail:
0x0000A52C       LI R1 ERR_BADF
0x0000A534       POP LR
0x0000A538       RET


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

0x0000A53C       LI R2 0                      ; index

fa_loop:
0x0000A544       CMP R2 MAX_FILES
0x0000A548       BGE fa_fail

0x0000A550       SHL R3 R2 2                  ; index * 4
0x0000A554       LI R4 file_used              ; look in file_used list 0 free 1 used
0x0000A55C       ADD R4 R4 R3

0x0000A560       LDW R5 [R4]
0x0000A564       CMP R5 0
0x0000A568       BEQ fa_found

0x0000A570       ADD R2 R2 1
0x0000A574       B fa_loop

fa_found:
0x0000A57C       LI R5 1
0x0000A584       STW R5 [R4]                  ; mark slot used

0x0000A588       LI R4 FILE_SIZE
0x0000A590       MUL R6 R2 R4

0x0000A594       LI R1 file_pool
0x0000A59C       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x0000A5A0       LI R7 0

0x0000A5A8       STW R7 [R1 + FILE_INODE]
0x0000A5AC       STW R7 [R1 + FILE_OFFSET]
0x0000A5B0       STW R7 [R1 + FILE_FLAGS]

0x0000A5B4       RET

fa_fail:
0x0000A5B8       LI R1 0
0x0000A5C0       RET

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
0x0000A5C4       PUSH LR
0x0000A5C8       PUSH R10
0x0000A5CC       MOV  R10 R1
0x0000A5D0       LDW  R2 [R1 + FILE_INODE]

0x0000A5D4       CMP R2 0
0x0000A5D8       BEQ no_inode

0x0000A5E0       MOV R1 R2
0x0000A5E4       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x0000A5EC       MOV R1 R10
0x0000A5F0       LI  R2 file_pool
0x0000A5F8       SUB R3 R1 R2                 ; offset from pool base

0x0000A5FC       LI  R4 FILE_SIZE
0x0000A604       DIV R5 R3 R4                 ; slot number

0x0000A608       SHL R5 R5 2                  ; slot * 4

0x0000A60C       LI  R6 file_used
0x0000A614       ADD R6 R6 R5                 ; address of slot in file_used

0x0000A618       LI R7 0
0x0000A620       STW R7 [R6]                  ; mark free
0x0000A624       POP R10
0x0000A628       POP LR
0x0000A62C       RET


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

0x0000A630       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x0000A634       LI  R1 tasks
0x0000A63C       LI  R2 TASK_SIZE
0x0000A644       LI  R3 MAX_TASKS
0x0000A64C       MUL R3 R2 R3
0x0000A650       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x0000A658       LI R1 idle_task
0x0000A660       LI R2 0
0x0000A668       LI R3 0
0x0000A670       BL task_create

0x0000A678       CMP R1 0
0x0000A67C       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task_init
    ; ----------------------------------

0x0000A684       LI R1 TASK_INIT_START
0x0000A68C       LI R2 1
0x0000A694       LI R3 0
0x0000A69C       BL task_create

0x0000A6A4       CMP R1 0
0x0000A6A8       BEQ init_scheduler_fail

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
0x0000A6B0       LI R1 task_count
0x0000A6B8       LI R2 2                     ; last task_pid+1 for now (task 0 and task 1) next id is 2
0x0000A6C0       STW R2 [R1]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x0000A6C4       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x0000A6CC   LI R1 CURRENT_TASK
0x0000A6D4   STW R2 [R1]

0x0000A6D8       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x0000A6DC       RET


init_scheduler_fail:

0x0000A6E0       DEBUG 99

halt:
0x0000A6E4       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x0000A6EC   LI R1 CURRENT_TASK
0x0000A6F4   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x0000A6F8       ADD R3 R2 1

wrap_check:

0x0000A6FC       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x0000A700       BLT check_task
0x0000A708       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x0000A710       LI R4 TASK_SIZE
0x0000A718       MUL R5 R3 R4
0x0000A71C       LI R6 tasks
0x0000A724       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x0000A728       LDW R7 [R5 + TASK_STATE]

0x0000A72C       CMP R7 1
0x0000A730       BEQ do_switch
    ; if not ready go to next task in list
0x0000A738       ADD R3 R3 1
0x0000A73C       B wrap_check

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
0x0000A744   LI R1 CURRENT_TASK
0x0000A74C   STW R3 [R1]
0x0000A750       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x0000A754   LI R1 TASK_SIZE
0x0000A75C   MUL R3 R2 R1
0x0000A760   LI R5 tasks
0x0000A768   ADD R5 R5 R3
0x0000A76C       MOV R3 R8
0x0000A770       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x0000A774       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x0000A778   STW R7 [R5 + TASK_USP]

0x0000A77C       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x0000A780   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x0000A784   LI R1 RESUME_TRAP
0x0000A78C   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x0000A790   LI R1 TASK_SIZE
0x0000A798   MUL R3 R8 R1
0x0000A79C   LI R5 tasks
0x0000A7A4   ADD R5 R5 R3
0x0000A7A8       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x0000A7AC   LDW R7 [R5 + TASK_PTBR]
0x0000A7B0       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x0000A7B4   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x0000A7B8   LDW R7 [R9 + TASK_STATE]
0x0000A7BC       CMP R7 TASK_ZOMBIE
0x0000A7C0       BNE switch_old_reaped
0x0000A7C8       PUSH R5
0x0000A7CC       MOV R1 R9
0x0000A7D0       BL task_destroy
0x0000A7D8       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x0000A7DC   LDW R7 [R5 + TASK_RESUME]
0x0000A7E0       CMP R7 RESUME_KERNEL
0x0000A7E4       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x0000A7EC       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x0000A7F4       PUSH R1
0x0000A7F8       PUSH R2
0x0000A7FC       PUSH R3
0x0000A800       PUSH R4
0x0000A804       PUSH R5
0x0000A808       PUSH R6
0x0000A80C       PUSH R7
0x0000A810       PUSH R8
0x0000A814       PUSH R9
0x0000A818       PUSH R10
0x0000A81C       PUSH R11
0x0000A820       PUSH R12
0x0000A824       PUSH R14
0x0000A828       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x0000A82C   LI R1 CURRENT_TASK
0x0000A834   LDW R2 [R1]

0x0000A838       ADD R3 R2 1

schedule_call_wrap_check:
0x0000A83C       CMP R3 MAX_TASKS
0x0000A840       BLT schedule_call_check_task
0x0000A848       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x0000A850       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x0000A854   LI R1 TASK_SIZE
0x0000A85C   MUL R3 R8 R1
0x0000A860   LI R5 tasks
0x0000A868   ADD R5 R5 R3
0x0000A86C       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x0000A870   LDW R7 [R5 + TASK_STATE]
0x0000A874       CMP R7 TASK_READY               ; check it can be run
0x0000A878       BEQ schedule_call_do_switch

0x0000A880       ADD R3 R3 1
0x0000A884       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x0000A88C   LI R1 CURRENT_TASK
0x0000A894   STW R3 [R1]
0x0000A898       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x0000A89C   LI R1 TASK_SIZE
0x0000A8A4   MUL R3 R2 R1
0x0000A8A8   LI R5 tasks
0x0000A8B0   ADD R5 R5 R3
0x0000A8B4       MOV R3 R8

0x0000A8B8       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x0000A8BC   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x0000A8C0   LI R1 RESUME_KERNEL
0x0000A8C8   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x0000A8CC   LI R1 TASK_SIZE
0x0000A8D4   MUL R3 R8 R1
0x0000A8D8   LI R5 tasks
0x0000A8E0   ADD R5 R5 R3
0x0000A8E4       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x0000A8E8   LDW R7 [R5 + TASK_PTBR]
0x0000A8EC       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x0000A8F0   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x0000A8F4   LDW R7 [R5 + TASK_RESUME]
0x0000A8F8       CMP R7 RESUME_KERNEL
0x0000A8FC       BEQ restore_kernel_context

0x0000A904       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x0000A90C       DISABLEINT                  ; RET does jump by LR(R15)
0x0000A910       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x0000A914       POP R14                     ; (in kernel)
0x0000A918       POP R12                     ; DI - to avoid int nesting
0x0000A91C       POP R11
0x0000A920       POP R10
0x0000A924       POP R9
0x0000A928       POP R8
0x0000A92C       POP R7
0x0000A930       POP R6
0x0000A934       POP R5
0x0000A938       POP R4
0x0000A93C       POP R3
0x0000A940       POP R2
0x0000A944       POP R1
0x0000A948       RET
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
0x0000A9DC       PUSH  R5
0x0000A9E0       PUSH  R6
0x0000A9E4       PUSH  R7
0x0000A9E8       PUSH  R8
0x0000A9EC       PUSH  R9

0x0000A9F0       LI R2 0                  ; page index

pa_loop:
0x0000A9F8       LI R1 MAX_PHYS_PAGES

0x0000AA00       CMP R2 R1
0x0000AA04       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x0000AA0C       MOV R3 R2
0x0000AA10       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x0000AA14       MOV R4 R2
0x0000AA18       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x0000AA1C       LI R5 page_bitmap
0x0000AA24       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x0000AA28       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x0000AA2C       LI R7 1
0x0000AA34       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x0000AA38       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x0000AA3C       CMP R8 0
0x0000AA40       BEQ pa_found                ; if bit is 0, page is free

0x0000AA48       ADD R2 R2 1                 ; increment page index and check next page
0x0000AA4C       B pa_loop

pa_found:

    ; mark page allocated

0x0000AA54       OR  R6 R6 R7
0x0000AA58       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x0000AA5C       LI  R9 PAGE_ALLOC_BASE

0x0000AA64       MOV R1 R2
0x0000AA68       SHL R1 R1 12          ; page_index * 4096

0x0000AA6C       ADD R1 R1 R9

0x0000AA70       POP R9
0x0000AA74       POP R8
0x0000AA78       POP R7
0x0000AA7C       POP R6
0x0000AA80       POP R5

0x0000AA84       RET

pa_fail:

0x0000AA88       LI R1 0                     ; no free pages

0x0000AA90       POP R9
0x0000AA94       POP R8
0x0000AA98       POP R7
0x0000AA9C       POP R6
0x0000AAA0       POP R5
0x0000AAA4       RET


;new page allocation routine with refcounts and bitmap for 128 pages of 4KB each (512KB total)

page_alloc:
0x0000AAA8       PUSH R6
0x0000AAAC       PUSH R7
0x0000AAB0       PUSH R8
0x0000AAB4       PUSH R9

0x0000AAB8       LI R2 0                     ; page index

pa1_loop:
0x0000AAC0       LI R1 MAX_PHYS_PAGES
0x0000AAC8       CMP R2 R1
0x0000AACC       BGE pa1_fail

0x0000AAD4       LI R1 page_refcounts
    ;ADD R5 R1 R2               ; address of refcount for this page
0x0000AADC       LDB R6 [R1 + R2]           ; load refcount
0x0000AAE0       CMP R6 0
0x0000AAE4       BEQ pa1_found

0x0000AAEC       ADD R2 R2 1
0x0000AAF0       B pa1_loop

pa1_found:
0x0000AAF8       LI R6 1
0x0000AB00       STB R6 [R1 + R2]          ; set refcount = 1

0x0000AB04       LI R9 PAGE_ALLOC_BASE
0x0000AB0C       MOV R1 R2
0x0000AB10       SHL R1 R1 12                ; index * PAGE_SIZE (4kB)
0x0000AB14       ADD R1 R1 R9                ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x0000AB18       POP R9
0x0000AB1C       POP R8
0x0000AB20       POP R7
0x0000AB24       POP R6                     ; R1 = physical address of allocated page
0x0000AB28       RET

pa1_fail:
0x0000AB2C       LI R1 0                     ; no free pages
0x0000AB34       POP R9
0x0000AB38       POP R8
0x0000AB3C       POP R7
0x0000AB40       POP R6
0x0000AB44       RET

;=================================================================
; page_get - increment refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_get:
    ; R1 = physical address
    ; Returns nothing; ignores invalid addresses
0x0000AB48       CMP R1 0
0x0000AB4C       BEQ page_get_done

    ; Check lower bound
0x0000AB54       LI R2 PAGE_ALLOC_BASE
0x0000AB5C       CMP R1 R2
0x0000AB60       BLT page_get_done

    ; Check upper bound (exclusive)
0x0000AB68       LI R2 PAGE_ALLOC_END
0x0000AB70       CMP R1 R2
0x0000AB74       BGE page_get_done

    ; Calculate index
0x0000AB7C       LI R2 PAGE_ALLOC_BASE
0x0000AB84       SUB R2 R1 R2       ; R1 pa
0x0000AB88       SHR R2 R2 12       ; R2 = page index in refcounts array
0x0000AB8C       LI R3 page_refcounts
0x0000AB94       ADD R3 R3 R2
0x0000AB98       LDB R4 [R3]
0x0000AB9C       ADD R4 R4 1                 ; increment refcount
0x0000ABA0       STB R4 [R3]
page_get_done:
0x0000ABA4       RET

;=================================================================
; page_put - decrement refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_put:
    ; R1 = physical address
0x0000ABA8       CMP R1 0                        ;if address is 0 - ignore
0x0000ABAC       BEQ page_put_done

0x0000ABB4       LI R2 PAGE_ALLOC_BASE           ;check R1 is valid
0x0000ABBC       CMP R1 R2
0x0000ABC0       BLT page_put_done

0x0000ABC8       LI R2 PAGE_ALLOC_END
0x0000ABD0       CMP R1 R2
0x0000ABD4       BGE page_put_done

0x0000ABDC       LI R2 PAGE_ALLOC_BASE
0x0000ABE4       SUB R2 R1 R2
0x0000ABE8       SHR R2 R2 12        ; R2 = page index in refcounts array
0x0000ABEC       LI R3 page_refcounts
0x0000ABF4       ADD R3 R3 R2
0x0000ABF8       LDB R4 [R3]
0x0000ABFC       CMP R4 0
0x0000AC00       BEQ page_put_done               ;if refcount already 0 - ignore it was freed already
0x0000AC08       SUB R4 R4 1                     ;decrement refcount
0x0000AC0C       STB R4 [R3]
    ; If refcount becomes 0, the page is now free (no further action needed)
page_put_done:
0x0000AC10       RET

;==============================================================================
; TABLE-BASED PAGE MANAGEMENT (for multi-page executables)
;==============================================================================

;------------------------------------------------------------------------------
; pages_allocate_table - Allocate a table page and all code pages needed for a file.
;
; IN:   R1 = file size in bytes
;
; OUT:  R1 = physical address of the table page (0 on failure)
;       R2 = number of code pages allocated
;       R3 = 0 on success, ERR_NOMEM on failure
;
; The table page layout:
;   [table + 0]  : count (number of code pages)
;   [table + 4]  : physical address of code page 0
;   [table + 8]  : physical address of code page 1
;   ...
;   [table + 4 + i*4] : physical address of code page i
;
; On failure, all allocated pages are freed automatically.
;------------------------------------------------------------------------------
pages_allocate_table:
0x0000AC14       PUSH LR
0x0000AC18       PUSH R8
0x0000AC1C       PUSH R9
0x0000AC20       PUSH R10
0x0000AC24       PUSH R11
0x0000AC28       PUSH R12

0x0000AC2C       MOV R8 R1                 ; file size
0x0000AC30       LI  R2 PAGE_SIZE
    ; compute num_pages = ceil(size / PAGE_SIZE)
0x0000AC38       ADD R1 R8 R2
0x0000AC3C       SUB R1 R1 1               ; (fsz + 4095) / 4096
0x0000AC40       DIV R1 R1 R2              ; R1 = count
0x0000AC44       MOV R9 R1                 ; save count

    ; ---- allocate table page ----
0x0000AC48       BL page_alloc
0x0000AC50       CMP R1 0
0x0000AC54       BEQ table_alloc_fail
0x0000AC5C       MOV R10 R1                ; table PA
0x0000AC60       LI R3 PAGE_SIZE
0x0000AC68       BL mem_zero               ; zero table
0x0000AC70       STW R9 [R10]              ; store count

    ; ---- allocate code pages and fill table ----
0x0000AC74       LI R11 0                  ; index
0x0000AC7C       LI R12 0                  ; error flag
alloc_table_loop:
0x0000AC84       CMP R11 R9
0x0000AC88       BGE alloc_table_done
0x0000AC90       BL page_alloc             ;get new page
0x0000AC98       CMP R1 0
0x0000AC9C       BEQ alloc_table_fail
0x0000ACA4       SHL R3 R11 2
0x0000ACA8       ADD R4 R10 R3
0x0000ACAC       ADD R4 R4 4
0x0000ACB0       STW R1 [R4]               ; store R1 - new PA at table[4 + i*4]
0x0000ACB4       ADD R11 R11 1
0x0000ACB8       B alloc_table_loop
alloc_table_done:
    ; success
0x0000ACC0       MOV R1 R10                ; table PA
0x0000ACC4       MOV R2 R9                 ; count
0x0000ACC8       LI R3 0                   ; success
0x0000ACD0       POP R12
0x0000ACD4       POP R11
0x0000ACD8       POP R10
0x0000ACDC       POP R9
0x0000ACE0       POP R8
0x0000ACE4       POP LR
0x0000ACE8       RET

alloc_table_fail:
    ; free all already allocated code pages and the table
0x0000ACEC       MOV R12 R11               ; number allocated so far
0x0000ACF0       LI R11 0
rollback_loop:
0x0000ACF8       CMP R11 R12
0x0000ACFC       BGE rollback_done
0x0000AD04       SHL R3 R11 2
0x0000AD08       ADD R4 R10 R3
0x0000AD0C       ADD R4 R4 4
0x0000AD10       LDW R1 [R4]
0x0000AD14       CMP R1 0
0x0000AD18       BEQ rollback_next
0x0000AD20       BL page_put
rollback_next:
0x0000AD28       ADD R11 R11 1
0x0000AD2C       B rollback_loop
rollback_done:
0x0000AD34       MOV R1 R10
0x0000AD38       BL page_put               ; free table
0x0000AD40       LI R1 0
0x0000AD48       LI R2 0
0x0000AD50       LI R3 ERR_NOMEM
0x0000AD58       POP R12
0x0000AD5C       POP R11
0x0000AD60       POP R10
0x0000AD64       POP R9
0x0000AD68       POP R8
0x0000AD6C       POP LR
0x0000AD70       RET

table_alloc_fail:
0x0000AD74       LI R1 0
0x0000AD7C       LI R2 0
0x0000AD84       LI R3 ERR_NOMEM
0x0000AD8C       POP R12
0x0000AD90       POP R11
0x0000AD94       POP R10
0x0000AD98       POP R9
0x0000AD9C       POP R8
0x0000ADA0       POP LR
0x0000ADA4       RET

;------------------------------------------------------------------------------
; pages_free_table - Free a table and all its code pages.
;
; IN:   R1 = physical address of the table page
; OUT:  none
;------------------------------------------------------------------------------
pages_free_table:
0x0000ADA8       PUSH LR
0x0000ADAC       PUSH R8
0x0000ADB0       PUSH R9
0x0000ADB4       PUSH R10

0x0000ADB8       CMP R1 0
0x0000ADBC       BEQ free_table_done
0x0000ADC4       MOV R8 R1                 ; table PA
0x0000ADC8       LDW R9 [R8]               ; count
0x0000ADCC       LI R10 0
free_table_loop:
0x0000ADD4       CMP R10 R9
0x0000ADD8       BGE free_table_done_pages
0x0000ADE0       SHL R3 R10 2
0x0000ADE4       ADD R4 R8 R3
0x0000ADE8       ADD R4 R4 4
0x0000ADEC       LDW R1 [R4]
0x0000ADF0       CMP R1 0
0x0000ADF4       BEQ free_table_next
0x0000ADFC       BL page_put
free_table_next:
0x0000AE04       ADD R10 R10 1
0x0000AE08       B free_table_loop
free_table_done_pages:
0x0000AE10       MOV R1 R8
0x0000AE14       BL page_put               ; free the table page itself
free_table_done:
0x0000AE1C       POP R10
0x0000AE20       POP R9
0x0000AE24       POP R8
0x0000AE28       POP LR
0x0000AE2C       RET

;------------------------------------------------------------------------------
; pages_map_table - Map all code pages from a table to consecutive virtual addresses.
;
; IN:   R1 = table PA
;       R2 = PTBR
;       R3 = starting virtual address (page-aligned)
;       R4 = page flags (e.g., USER_RW, KERNEL_USER_ALL)
;
; OUT:  none (assumes all pages are valid)
;
; Clobbers: R5-R11
;------------------------------------------------------------------------------
pages_map_table:
0x0000AE30       PUSH LR
0x0000AE34       PUSH R5
0x0000AE38       PUSH R6
0x0000AE3C       PUSH R7
0x0000AE40       PUSH R8
0x0000AE44       PUSH R9
0x0000AE48       PUSH R10
0x0000AE4C       PUSH R11

0x0000AE50       MOV R8 R1                 ; table PA
0x0000AE54       MOV R9 R2                 ; PTBR
0x0000AE58       MOV R10 R3                ; VA start
0x0000AE5C       MOV R11 R4                ; flags
0x0000AE60       LDW R6 [R8]               ; count
0x0000AE64       LI R7 0
map_table_loop:
0x0000AE6C       CMP R7 R6
0x0000AE70       BGE map_table_done
0x0000AE78       SHL R3 R7 2
0x0000AE7C       ADD R4 R8 R3
0x0000AE80       ADD R4 R4 4
0x0000AE84       LDW R5 [R4]            ; physical address
0x0000AE88       MOV R1 R9                 ; PTBR
0x0000AE8C       LI  R3 PAGE_SIZE
0x0000AE94       MUL R3 R7 R3              ; offset = index * PAGE_SIZE
0x0000AE98       MOV R2 R10
0x0000AE9C       ADD R2 R2 R3              ; VA for this page
0x0000AEA0       MOV R3 R5                 ; restore physical page after calculating VA offset
0x0000AEA4       MOV R4 R11
0x0000AEA8       BL map_page_rt
0x0000AEB0       ADD R7 R7 1
0x0000AEB4       B map_table_loop
map_table_done:
0x0000AEBC       POP R11
0x0000AEC0       POP R10
0x0000AEC4       POP R9
0x0000AEC8       POP R8
0x0000AECC       POP R7
0x0000AED0       POP R6
0x0000AED4       POP R5
0x0000AED8       POP LR
0x0000AEDC       RET


;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free0:
0x0000AEE0       PUSH  R5
0x0000AEE4       PUSH  R6
0x0000AEE8       PUSH  R7
0x0000AEEC       PUSH  R8
0x0000AEF0       PUSH  R9


0x0000AEF4       LI R2 PAGE_ALLOC_BASE
0x0000AEFC       SUB R3 R1 R2         ; calculate offset from base

0x0000AF00       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x0000AF04       MOV R4 R3
0x0000AF08       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x0000AF0C       MOV R5 R3
0x0000AF10       AND R5 R5 7          ; bit index in byte = page index % 8

0x0000AF14       LI R6 page_bitmap
0x0000AF1C       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x0000AF20       LDB R7 [R6]

0x0000AF24       LI R8 1
0x0000AF2C       SHL R8 R8 R5         ; mask for this page's bit

0x0000AF30       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x0000AF34       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x0000AF38       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000AF3C       POP R9
0x0000AF40       POP R8
0x0000AF44       POP R7
0x0000AF48       POP R6
0x0000AF4C       POP R5
0x0000AF50       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:
0x0000AF54       LI R2 0
pz_loop:
0x0000AF5C       CMP R3 0
0x0000AF60       BEQ pz_done
0x0000AF68       STB R2 [R1]
0x0000AF6C       ADD R1 R1 1
0x0000AF70       SUB R3 R3 1
0x0000AF74       B pz_loop
pz_done:
0x0000AF7C       RET

;=================================================================
; memory copy at the given address (R1)<(R2) R3 = amount
;=================================================================

memcpy:

cpy_loop:
0x0000AF80       CMP R3 0
0x0000AF84       BEQ cpy_done
0x0000AF8C       LDB R4 [R2]
0x0000AF90       STB R4 [R1]
0x0000AF94       ADD R1 R1 1
0x0000AF98       ADD R2 R2 1
0x0000AF9C       SUB R3 R3 1
0x0000AFA0       B cpy_loop
cpy_done:
0x0000AFA8       RET

; ================================================================
; Copy a memory page (or other multiple of 4 bytes) by physical address.
; R1 = source physical address (should be aligned!)
; R2 = destination physical address (aligned!)
; R3 = size in bytes (must be multiple of 4)
; each time it copyes 4 bytes (1 word)
; ================================================================
page_copy:

page_copy_loop:
0x0000AFAC       CMP R3 0
0x0000AFB0       BEQ page_copy_done
0x0000AFB8       LDW R4 [R1]
0x0000AFBC       STW R4 [R2]
0x0000AFC0       ADD R1 R1 4
0x0000AFC4       ADD R2 R2 4
0x0000AFC8       SUB R3 R3 4
0x0000AFCC       B page_copy_loop

page_copy_done:
0x0000AFD4       RET

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

0x0000B4DC       PUSH LR

0x0000B4E0       MOV R8 R1          ; entry
0x0000B4E4       MOV R9 R2          ; pid
0x0000B4E8       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x0000B4F0       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x0000B4F8       CMP R1 0
0x0000B4FC       BEQ task_create_fail

0x0000B504       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x0000B508       MOV R1 R10
0x0000B50C       LI R3 TASK_SIZE
0x0000B514       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x0000B51C   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x0000B520   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x0000B524       BL page_alloc
0x0000B52C       CMP R1 0
0x0000B530       BEQ task_create_fail

0x0000B538       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x0000B53C   STW R1 [R10 + TASK_PTBR]

0x0000B540       MOV R1 R12
0x0000B544       LI  R3 PAGE_SIZE
0x0000B54C       BL  mem_zero                   ; zero out the sensitive new page table

0x0000B554       MOV R1 R12
0x0000B558       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x0000B560   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x0000B564   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x0000B568   LDW R1 [R10 + TASK_PTBR]
0x0000B56C       MOV R2 R8
0x0000B570       LI R3 0xFFFFF000
0x0000B578       AND R2 R2 R3
0x0000B57C       MOV R3 R2
0x0000B580       CMP R9 0
0x0000B584       BEQ task_create_map_kernel_entry
0x0000B58C       LI R4 USER_RX
0x0000B594       B task_create_map_entry
task_create_map_kernel_entry:
0x0000B59C       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x0000B5A4       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x0000B5AC       BL page_alloc
0x0000B5B4       CMP R1 0
0x0000B5B8       BEQ task_create_fail

0x0000B5C0       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x0000B5C4   STW R12 [R10 + TASK_USTACK_PAGE]

0x0000B5C8       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x0000B5D0   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x0000B5D4   LDW R1 [R10 + TASK_PTBR]

0x0000B5D8       LI  R2 USER_STACK_VA
0x0000B5E0       MOV R3 R12
0x0000B5E4       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x0000B5EC       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x0000B5F4       BL page_alloc
0x0000B5FC       CMP R1 0
0x0000B600       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x0000B608   STW R1 [R10 + TASK_KSTACK_PAGE]
0x0000B60C       LI R2 PAGE_SIZE

0x0000B614       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x0000B618       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x0000B61C   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x0000B620   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x0000B624       LI R1 0

0x0000B62C       PUSH R1            ; R1
0x0000B630       PUSH R1            ; R2
0x0000B634       PUSH R1            ; R3
0x0000B638       PUSH R1            ; R4
0x0000B63C       PUSH R1            ; R5
0x0000B640       PUSH R1            ; R6
0x0000B644       PUSH R1            ; R7
0x0000B648       PUSH R1            ; R8
0x0000B64C       PUSH R1            ; R9
0x0000B650       PUSH R1            ; R10
0x0000B654       PUSH R1            ; R11
0x0000B658       PUSH R1            ; R12
0x0000B65C       PUSH R1            ; R14 (FP)
0x0000B660       PUSH R1            ; R15 (LR)

0x0000B664       PUSH R11           ; R11 - user SP top

0x0000B668       MOV R1 R8
0x0000B66C       PUSH R1            ; sepc = entry

0x0000B670       LI R1 0
0x0000B678       PUSH R1            ; sflags

0x0000B67C       CMP R9 0
0x0000B680       BEQ task_create_kernel_status
0x0000B688       LI R1 0x20
0x0000B690       B task_create_status_ready
task_create_kernel_status:
0x0000B698       LI R1 0x120
task_create_status_ready:
0x0000B6A0       PUSH R1            ; sstatus

0x0000B6A4       LI R1 0
0x0000B6AC       PUSH R1            ; scause
0x0000B6B0       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x0000B6B4       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x0000B6B8   STW R1 [R10 + TASK_KSP]

0x0000B6BC       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x0000B6C0   LI R1 WAIT_NONE
0x0000B6C8   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x0000B6CC   LI R1 RESUME_TRAP
0x0000B6D4   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x0000B6D8       BL page_alloc
0x0000B6E0       CMP R1 0
0x0000B6E4       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x0000B6EC       MOV R12 R1

0x0000B6F0       LI  R3 PAGE_SIZE
0x0000B6F8       MOV R1 R12
0x0000B6FC       BL  mem_zero

    ; stdin
0x0000B704       LI  R2 file_stdin
0x0000B70C       STW R2 [R12 + 0]

    ; stdout
0x0000B710       LI  R2 file_stdout
0x0000B718       STW R2 [R12 + 4]

    ; stderr
0x0000B71C       LI  R2 file_stderr
0x0000B724       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x0000B728   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x0000B72C       BL page_alloc
0x0000B734       CMP R1 0
0x0000B738       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x0000B740   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x0000B744       BL page_alloc
0x0000B74C       CMP R1 0
0x0000B750       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x0000B758   STW R1 [R10 + TASK_KBUF_RD_PTR]

    ; ----------------------------------
    ; data page - for user buffers and heap
    ; ----------------------------------

0x0000B75C       BL page_alloc
0x0000B764       CMP R1 0
0x0000B768       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x0000B770   STW R1 [R10 + TASK_DATA_PAGE]

0x0000B774       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x0000B778   LDW R1 [R10 + TASK_PTBR]
0x0000B77C       LI  R2 USER_DATA_VA
0x0000B784       MOV R3 R12
0x0000B788       LI  R4 USER_RW
0x0000B790       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; initialize code page pointer to zero until execve or static code assignment
    ; This means the task currently has no execve-loaded program image.
    ; When execve runs, TASK_CODE_PAGE will be updated to point to the
    ; physical page currently mapped at USER_CODE_VA.
0x0000B798       LI R1 0
; macro: TASK_SET_CODE_PAGE R10, R1
0x0000B7A0   STW R1 [R10 + TASK_CODE_PAGE]

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x0000B7A4   LI R1 TASK_READY
0x0000B7AC   STW R1 [R10 + TASK_STATE]

    ; Initialize program break pointer to HEAP_START in User_Data_VA
0x0000B7B0       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x0000B7B8   STW R1 [R10 + TASK_BREAK]

    ; Initialize parent PID to 0 by default
0x0000B7BC       LI R1 0
; macro: TASK_SET_PPID R10, R1
0x0000B7C4   STW R1 [R10 + TASK_PPID]

0x0000B7C8       MOV R1 R10                              ; return created task pointer

0x0000B7CC       POP LR
0x0000B7D0       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x0000B7D4       CMP R10 0
0x0000B7D8       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x0000B7E0   LDW R1 [R10 + TASK_PTBR]
0x0000B7E4       CMP R1 0
0x0000B7E8       BEQ task_create_free_ustack
0x0000B7F0       BL page_put

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x0000B7F8   LDW R1 [R10 + TASK_USTACK_PAGE]
0x0000B7FC       CMP R1 0
0x0000B800       BEQ task_create_free_kstack
0x0000B808       BL page_put

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x0000B810   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x0000B814       CMP R1 0
0x0000B818       BEQ task_create_free_fd
0x0000B820       BL page_put

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x0000B828   LDW R1 [R10 + TASK_FD_TABLE]
0x0000B82C       CMP R1 0
0x0000B830       BEQ task_create_free_kwr
0x0000B838       BL page_put

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x0000B840   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000B844       CMP R1 0
0x0000B848       BEQ task_create_free_krd
0x0000B850       BL page_put

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x0000B858   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000B85C       CMP R1 0
0x0000B860       BEQ task_create_free_data
0x0000B868       BL page_put

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x0000B870   LDW R1 [R10 + TASK_DATA_PAGE]
0x0000B874       CMP R1 0
0x0000B878       BEQ task_create_clear_slot
0x0000B880       BL page_put

task_create_clear_slot:
0x0000B888       MOV R1 R10
0x0000B88C       LI R3 TASK_SIZE
0x0000B894       BL mem_zero

task_create_fail_return:
0x0000B89C       LI R1 0

0x0000B8A4       POP LR
0x0000B8A8       RET

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
0x0000B8AC       MOV  R8 SP ;save sp to point to task trapframe!
0x0000B8B0       PUSH LR

    ; Get the current task slot and parent task pointer.
; macro: GET_CURR_TASK_IDX R6
0x0000B8B4   LI R1 CURRENT_TASK
0x0000B8BC   LDW R6 [R1]
; macro: GET_TASK_PTR R7, R6           ; R7 = parent task*
0x0000B8C0   LI R1 TASK_SIZE
0x0000B8C8   MUL R3 R6 R1
0x0000B8CC   LI R7 tasks
0x0000B8D4   ADD R7 R7 R3

    ; Allocate a fresh child task slot.
0x0000B8D8       BL task_alloc
0x0000B8E0       CMP R1 0
0x0000B8E4       BEQ clone_fail
0x0000B8EC       MOV R10 R1                    ; R10 = child task*

    ; Clear the new child task slot before use.
0x0000B8F0       MOV R1 R10
0x0000B8F4       LI R3 TASK_SIZE
0x0000B8FC       BL mem_zero

    ; Assign a new PID from the dynamic pid counter.
0x0000B904       LI R1 task_count
0x0000B90C       LDW R2 [R1]

; macro: TASK_SET_PID R10, R2        ; set new child task Pid to child task (current task_count value)
0x0000B910   STW R2 [R10 + TASK_PID]
0x0000B914       ADD R2 R2 1
0x0000B918       STW R2 [R1]                 ; update task_count as we created a new task

    ; Set child parent PID to the current task's PID.
; macro: TASK_GET_PID R2, R7
0x0000B91C   LDW R2 [R7 + TASK_PID]
; macro: TASK_SET_PPID R10, R2       ; pid - new, ppid - parent task's pid (new task)
0x0000B920   STW R2 [R10 + TASK_PPID]

    ; Copy the current task's program break.
; macro: TASK_GET_BREAK R2, R7
0x0000B924   LDW R2 [R7 + TASK_BREAK]
; macro: TASK_SET_BREAK R10, R2
0x0000B928   STW R2 [R10 + TASK_BREAK]

    ; Copy current task PC for debugging/metadata.
; macro: TASK_GET_PC R2, R7
0x0000B92C   LDW R2 [R7 + TASK_PC]
; macro: TASK_SET_PC R10, R2
0x0000B930   STW R2 [R10 + TASK_PC]

    ; Allocate and initialize a fresh page table for the child.
0x0000B934       BL page_alloc
0x0000B93C       CMP R1 0
0x0000B940       BEQ clone_fail
0x0000B948       MOV R11 R1
; macro: TASK_SET_PTBR R10, R11
0x0000B94C   STW R11 [R10 + TASK_PTBR]

    ; Clone the parent's entire page table into the child.
; macro: TASK_GET_PTBR R1, R7
0x0000B950   LDW R1 [R7 + TASK_PTBR]
0x0000B954       MOV R2 R11
0x0000B958       LI R3 PAGE_SIZE
0x0000B960       BL page_copy

    ; child will inherit code page pa (tab+codepages) from parent
; macro: TASK_GET_CODE_PAGE R2, R7   ; R2 = parent's code page PA table
0x0000B968   LDW R2 [R7 + TASK_CODE_PAGE]
0x0000B96C       CMP R2 0
0x0000B970       BEQ skip_code_get
    ; 1) allocate new table page
0x0000B978       BL page_alloc
0x0000B980       CMP R1 0
0x0000B984       BEQ clone_fail
0x0000B98C       MOV R12 R1
    ; 2) copy the table page parnt to child (it contins count and pointers to pa pages)
0x0000B990       MOV R1 R2
0x0000B994       MOV R2 R12
0x0000B998       LI R3 PAGE_SIZE
0x0000B9A0       BL page_copy    ;4k

; increment refcounts for each code page
0x0000B9A8       LDW R8 [R12]               ; count: +0
0x0000B9AC       LI R9 0                    ; page index in tab
clone_inc_loop:
0x0000B9B4       CMP R9 R8
0x0000B9B8       BGE clone_inc_done
0x0000B9C0       SHL R3 R9 2
0x0000B9C4       ADD R4 R12 R3
0x0000B9C8       ADD R4 R4 4
0x0000B9CC       LDW R1 [R4]                ;pa ptr: R4=R12(=+0) + 4+idx*4
0x0000B9D0       CMP R1 0
0x0000B9D4       BEQ clone_inc_next
0x0000B9DC       BL page_get                ; refcount+1
clone_inc_next:
0x0000B9E4       ADD R9 R9 1
0x0000B9E8       B clone_inc_loop
clone_inc_done:

; macro: TASK_SET_CODE_PAGE R10, R12 ;  set child's code page PA (tab+pages)
0x0000B9F0   STW R12 [R10 + TASK_CODE_PAGE]

   ; TASK_SET_CODE_PAGE R10, R2  ; set child's code page PA to parent's code page PA
    ; Now increment refcount for the shared code page (if code page is allocated).
    ;(it is in case when execve was called before fork or when fork-execve, then fork-execve, then fork-execve etc. - all children share the same code page)
   ; MOV R1 R2
   ; BL page_get     ;increment refcount for the shared code page (if code page is allocated)
skip_code_get:

    ; The child has inherited the parent's kernel and code mappings.
    ; We will override the user stack and data mappings below.
    ; Allocate and clone the user stack page.
0x0000B9F4       BL page_alloc
0x0000B9FC       CMP R1 0
0x0000BA00       BEQ clone_fail
0x0000BA08       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12   ; set new page as child user stack page
0x0000BA0C   STW R12 [R10 + TASK_USTACK_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x0000BA10   LDW R1 [R10 + TASK_PTBR]
0x0000BA14       LI R2 USER_STACK_VA
0x0000BA1C       MOV R3 R12
0x0000BA20       LI R4 USER_RW
0x0000BA28       BL map_page             ; map user stack page to child ptbr

; macro: TASK_GET_USTACK_PAGE R1, R7
0x0000BA30   LDW R1 [R7 + TASK_USTACK_PAGE]
0x0000BA34       MOV R2 R12
0x0000BA38       LI R3 PAGE_SIZE
0x0000BA40       BL page_copy            ; copy parent user stack page -> child user stack page

    ; Allocate and clone the user data page.
0x0000BA48       BL page_alloc
0x0000BA50       CMP R1 0
0x0000BA54       BEQ clone_fail
0x0000BA5C       MOV R12 R1
; macro: TASK_SET_DATA_PAGE R10, R12     ; set new page as child user data page
0x0000BA60   STW R12 [R10 + TASK_DATA_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x0000BA64   LDW R1 [R10 + TASK_PTBR]
0x0000BA68       LI R2 USER_DATA_VA
0x0000BA70       MOV R3 R12
0x0000BA74       LI R4 USER_RW
0x0000BA7C       BL map_page                     ; map user data page to child ptbr

; macro: TASK_GET_DATA_PAGE R1, R7
0x0000BA84   LDW R1 [R7 + TASK_DATA_PAGE]
0x0000BA88       MOV R2 R12
0x0000BA8C       LI R3 PAGE_SIZE
0x0000BA94       BL page_copy                    ; copy parent user data page -> child user data page

    ; Clone the fd table and honor open file refcounts.
0x0000BA9C       BL page_alloc
0x0000BAA4       CMP R1 0
0x0000BAA8       BEQ clone_fail

0x0000BAB0       MOV R12 R1

; macro: TASK_SET_FD_TABLE R10, R12       ; set new page as child fd table page
0x0000BAB4   STW R12 [R10 + TASK_FD_TABLE]
0x0000BAB8       LI R3 PAGE_SIZE
0x0000BAC0       MOV R1 R12
0x0000BAC4       BL mem_zero                     ; clear the child fd table page just in case

; macro: TASK_GET_FD_TABLE R1, R7         ; R1 - parent fd table page
0x0000BACC   LDW R1 [R7 + TASK_FD_TABLE]
0x0000BAD0       CMP R1 0
0x0000BAD4       BEQ clone_fd_done                ; if parent has no fd table, skip fd cloning

    ; parent → child copy FIRST
0x0000BADC       MOV R1 R1        ; parent fd page
0x0000BAE0       MOV R2 R12       ; child fd page
0x0000BAE4       LI R3 PAGE_SIZE
0x0000BAEC       BL page_copy

0x0000BAF4       LI R4 3                      ; fd index loop + 3 stdin/out/err refcount=1, so start at 3

clone_fd_loop:
0x0000BAFC       CMP R4 MAX_FDS
0x0000BB00       BGE clone_fd_done

0x0000BB08       SHL R5 R4 2                 ; multiply fd index by 4 to get byte offset
0x0000BB0C       ADD R6 R12 R5               ; R6 = &child_fd_table[i]

0x0000BB10       LDW R7 [R6]                 ; R7 = file* from child fd table
0x0000BB14       CMP R7 0
0x0000BB18       BEQ clone_fd_next           ; if fd slot is empty, skip to next

0x0000BB20       MOV R1 R7                   ; IMPORTANT: isolate argument
0x0000BB24       BL file_get                 ; increment refcount of the file* in child fd table

clone_fd_next:
0x0000BB2C       ADD R4 R4 1
0x0000BB30       B clone_fd_loop

clone_fd_done:
    ; Allocate fresh kernel buffers for the child.
0x0000BB38       BL page_alloc
0x0000BB40       CMP R1 0
0x0000BB44       BEQ clone_fail

; macro: TASK_SET_KBUF_WR R10, R1        ; set new page as child kernel write buffer
0x0000BB4C   STW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000BB50       LI R3 PAGE_SIZE
0x0000BB58       BL mem_zero                     ; zero out the child kernel write buffer

0x0000BB60       BL page_alloc
0x0000BB68       CMP R1 0
0x0000BB6C       BEQ clone_fail
; macro: TASK_SET_KBUF_RD R10, R1        ; set new page as child kernel read buffer
0x0000BB74   STW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000BB78       LI R3 PAGE_SIZE
0x0000BB80       BL mem_zero                     ; zero out the child kernel read buffer

    ; Allocate and initialize the child's kernel stack.
0x0000BB88       BL page_alloc
0x0000BB90       CMP R1 0
0x0000BB94       BEQ clone_fail
0x0000BB9C       MOV R12 R1
; macro: TASK_SET_KSTACK_PAGE R10, R12   ; set new page as child kernel stack page
0x0000BBA0   STW R12 [R10 + TASK_KSTACK_PAGE]
0x0000BBA4       LI R3 PAGE_SIZE
0x0000BBAC       ADD R12 R12 R3                  ; R12 = child kernel stack top


    ; Copy the current kernel trapframe into the child's new kernel stack.
    ; task_clone_current has one saved return address below the trapframe, so
    ; recover the trapframe from the balanced current SP instead of R8, which
    ; was reused for the code-page count above. eto pizdec nado decompose clone.
    ; issue is fixed by friend - it found SP is in balance here
    ; so SP+4 is what was in R8 here
0x0000BBB0       MOV R1 SP
0x0000BBB4       ADD R1 R1 4                   ; R1 = parent trapframe base
0x0000BBB8       MOV R6 R12
0x0000BBBC       LI R5 80                    ; trapframe size in bytes
0x0000BBC4       SUB R6 R6 R5               ; R6 = child trapframe base inside new kernel stack
0x0000BBC8       MOV R2 R6
0x0000BBCC       LI R3 80
0x0000BBD4       BL page_copy                ; so we copy 80 bytes from SP to R12-80 (child trapframe base)

    ; Return 0 in the child syscall result register.
0x0000BBDC       LI R4 0
0x0000BBE4       STW R4 [R6 + TF_R1]


    ; Preserve the user SP for later trap/schedule bookkeeping.
    ; User SP is already in the trapframe we copied
    ; But we also need to set it in the child's task struct
0x0000BBE8       LDW R4 [R6 + TF_USP]
; macro: TASK_SET_USP R10, R4
0x0000BBEC   STW R4 [R10 + TASK_USP]

    ; Save the child kernel trapframe pointer and make it runnable.
; macro: TASK_SET_KSP R10, R6                    ;R6 = child trapframe base inside new kernel stack
0x0000BBF0   STW R6 [R10 + TASK_KSP]
; macro: TASK_SET_RESUME R10, RESUME_TRAP
0x0000BBF4   LI R1 RESUME_TRAP
0x0000BBFC   STW R1 [R10 + TASK_RESUME]
; macro: TASK_SET_WAIT R10, WAIT_NONE
0x0000BC00   LI R1 WAIT_NONE
0x0000BC08   STW R1 [R10 + TASK_WAIT]
; macro: TASK_SET_STATE R10, TASK_READY
0x0000BC0C   LI R1 TASK_READY
0x0000BC14   STW R1 [R10 + TASK_STATE]

0x0000BC18       MOV R1 R10          ; return child task pointer

0x0000BC1C       POP LR
0x0000BC20       RET

clone_fail:
0x0000BC24       CMP R10 0
0x0000BC28       BEQ clone_fail_return
0x0000BC30       MOV R1 R10
0x0000BC34       BL task_destroy
clone_fail_return:
0x0000BC3C       LI R1 0
0x0000BC44       POP LR
0x0000BC48       RET

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

0x0000BC4C       PUSH LR
0x0000BC50       push R12 ; preserve R12 which we use for temporary storage in this function
0x0000BC54       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x0000BC58   LDW R2 [R1 + TASK_PTBR]
0x0000BC5C       CMP R2 0
0x0000BC60       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x0000BC68       MOV R1 R2
0x0000BC6C       BL page_put        ; put-free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x0000BC74   LDW R2 [R12 + TASK_USTACK_PAGE]
0x0000BC78       CMP R2 0
0x0000BC7C       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000BC84       MOV R1 R2
0x0000BC88       BL page_put        ; put-free user stack page

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x0000BC90   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x0000BC94       CMP R2 0
0x0000BC98       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000BCA0       MOV R1 R2
0x0000BCA4       BL page_put        ; put-free kernel stack page

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x0000BCAC   LDW R2 [R12 + TASK_FD_TABLE]
0x0000BCB0       CMP R2 0
0x0000BCB4       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000BCBC       MOV R1 R2
0x0000BCC0       BL page_put        ; put-free fd table page

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x0000BCC8   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x0000BCCC       CMP R2 0
0x0000BCD0       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x0000BCD8       MOV R1 R2
0x0000BCDC       BL page_put       ; put free KBUF_WR Page

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x0000BCE4   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x0000BCE8       CMP R2 0
0x0000BCEC       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x0000BCF4       MOV R1 R2
0x0000BCF8       BL page_put       ; put free KBUF_RD Page

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x0000BD00   LDW R2 [R12 + TASK_DATA_PAGE]
0x0000BD04       CMP R2 0
0x0000BD08       BEQ td_skip_code
0x0000BD10       MOV R1 R2
0x0000BD14       BL page_put        ; put-free user data page

td_skip_code:

; macro: TASK_GET_CODE_PAGE R2, R12
0x0000BD1C   LDW R2 [R12 + TASK_CODE_PAGE]
0x0000BD20       CMP R2 0
0x0000BD24       BEQ td_done

0x0000BD2C       MOV R1 R2
0x0000BD30       BL pages_free_table ;codepage (tab+pages)

    ;BL page_put        ; put-free user code page

td_done:

0x0000BD38       MOV R1 R12
0x0000BD3C       LI  R3 TASK_SIZE
0x0000BD44       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x0000BD4C       POP R12         ; restore R12
0x0000BD50       POP LR
0x0000BD54       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x0000BD58       PUSH LR
0x0000BD5C       PUSH R8
0x0000BD60       PUSH R9
0x0000BD64       PUSH R10
0x0000BD68       PUSH R11
0x0000BD6C       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x0000BD70   LDW R4 [R1 + TASK_FD_TABLE]
0x0000BD74       MOV R12 R4

0x0000BD78       LI R5 3              ; skip stdin/out/err
0x0000BD80       MOV R11 R5

fd_loop:

0x0000BD84       CMP R11 MAX_FDS
0x0000BD88       BGE fd_done         ; if we processed all fd slots, we are done

0x0000BD90       SHL R6 R11 2
0x0000BD94       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x0000BD98       LDW R8 [R10]
0x0000BD9C       CMP R8 0
0x0000BDA0       BEQ fd_next         ; if fd slot is empty, skip to next

0x0000BDA8       MOV R1 R8
0x0000BDAC       BL file_free
0x0000BDB4       LI R9 0
0x0000BDBC       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x0000BDC0       ADD R11 R11 1
0x0000BDC4       B fd_loop

fd_done:
0x0000BDCC       POP R12
0x0000BDD0       POP R11
0x0000BDD4       POP R10
0x0000BDD8       POP R9
0x0000BDDC       POP R8
0x0000BDE0       POP LR
0x0000BDE4       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x0000BDE8       PUSH LR
0x0000BDEC       PUSH R8
0x0000BDF0       PUSH R9
0x0000BDF4       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x0000BDF8   LI R1 CURRENT_TASK
0x0000BE00   LDW R10 [R1]
0x0000BE04       LI R8 0

task_reap_loop:
0x0000BE0C       CMP R8 MAX_TASKS
0x0000BE10       BGE task_reap_done

0x0000BE18       CMP R8 R10
0x0000BE1C       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x0000BE24   LI R1 TASK_SIZE
0x0000BE2C   MUL R3 R8 R1
0x0000BE30   LI R9 tasks
0x0000BE38   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x0000BE3C   LDW R1 [R9 + TASK_STATE]
0x0000BE40       CMP R1 TASK_ZOMBIE
0x0000BE44       BNE task_reap_next

0x0000BE4C       PUSH R8
0x0000BE50       MOV R1 R9
0x0000BE54       BL task_destroy
0x0000BE5C       POP R8

task_reap_next:
0x0000BE60       ADD R8 R8 1
0x0000BE64       B task_reap_loop

task_reap_done:
0x0000BE6C       POP R10
0x0000BE70       POP R9
0x0000BE74       POP R8
0x0000BE78       POP LR
0x0000BE7C       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x0000BE80       LI R1 tasks
0x0000BE88       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x0000BE90   LDW R3 [R1 + TASK_STATE]

0x0000BE94       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000BE98       BEQ task_alloc_found

0x0000BEA0       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x0000BEA4       SUB R2 R2 1
0x0000BEA8       BNE task_alloc_loop

; no free tasks slots

0x0000BEB0       LI R1 0
0x0000BEB8       RET

task_alloc_found:                           ;R1 points to free task slot

0x0000BEBC       RET


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
0x0000BEC8       PUSH R2

0x0000BECC       LI R2 0
0x0000BED4       STW R2 [R1 + MUTEX_OWNER]      ; owner = NULL
0x0000BED8       STW R2 [R1 + MUTEX_WAITQ]      ; waitq = 0 (empty)

0x0000BEDC       POP R2
0x0000BEE0       RET

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

0x0000BEE4       PUSH LR
0x0000BEE8       PUSH R8
0x0000BEEC       PUSH R9
0x0000BEF0       PUSH R10

0x0000BEF4       MOV R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000BEF8   LI R1 CURRENT_TASK
0x0000BF00   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000BF04   LI R1 TASK_SIZE
0x0000BF0C   MUL R3 R9 R1
0x0000BF10   LI R9 tasks
0x0000BF18   ADD R9 R9 R3

mutex_lock_retry:
    ; Check if mutex is already locked
0x0000BF1C       LDW R10 [R8 + MUTEX_OWNER]
0x0000BF20       CMP R10 0
0x0000BF24       BEQ mutex_lock_acquire      ; if unlocked, acquire it

    ; this Mutex is locked by someone else - block
    ; Add current task to mutex wait queue
0x0000BF2C       MOV R1 R8
0x0000BF30       ADD R1 R1 MUTEX_WAITQ

0x0000BF34       LI R2 WAIT_MUTEX
0x0000BF3C       LI R3 TASK_WAIT_MUTEX
0x0000BF44       BL waitq_prepare_sleep

    ; Re-check if mutex became available while preparing sleep
0x0000BF4C       LDW R10 [R8 + MUTEX_OWNER]
0x0000BF50       CMP R10 0
0x0000BF54       BEQ mutex_lock_wake

    ; Still locked - go to sleep
0x0000BF5C       BL waitq_sleep_current

    ; Woken up - try to acquire again
0x0000BF64       B mutex_lock_retry

mutex_lock_wake:
    ; Mutex became available, cancel sleep and acquire
0x0000BF6C       MOV R1 R8
0x0000BF70       ADD R1 R1 MUTEX_WAITQ
0x0000BF74       BL waitq_cancel_sleep_current

0x0000BF7C       B mutex_lock_retry

mutex_lock_acquire:
    ; Disable interrupts to prevent race conditions
0x0000BF84       DISABLEINT

    ; Double-check it's still unlocked
0x0000BF88       LDW R10 [R8 + MUTEX_OWNER]
0x0000BF8C       CMP R10 0
0x0000BF90       BNE mutex_lock_race

    ; Set owner to current task
0x0000BF98       STW R9 [R8 + MUTEX_OWNER]

    ; Re-enable interrupts
0x0000BF9C       ENABLEINT

0x0000BFA0       POP R10
0x0000BFA4       POP R9
0x0000BFA8       POP R8
0x0000BFAC       POP LR
0x0000BFB0       RET

mutex_lock_race:
    ; Someone else acquired it while interrupts were disabled
0x0000BFB4       ENABLEINT
0x0000BFB8       B mutex_lock_retry


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
0x0000BFC0       PUSH LR
0x0000BFC4       PUSH R8
0x0000BFC8       PUSH R9
0x0000BFCC       PUSH R10

0x0000BFD0       MOV  R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000BFD4   LI R1 CURRENT_TASK
0x0000BFDC   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000BFE0   LI R1 TASK_SIZE
0x0000BFE8   MUL R3 R9 R1
0x0000BFEC   LI R9 tasks
0x0000BFF4   ADD R9 R9 R3

    ; Verify ownership
0x0000BFF8       LDW  R10 [R8 + MUTEX_OWNER]
0x0000BFFC       CMP  R10 R9
0x0000C000       BNE  mutex_unlock_error     ; Not owner - error!

    ; Release the mutex
0x0000C008       LI  R10 0
0x0000C010       STW R10 [R8 + MUTEX_OWNER]

    ; Wake one waiting task (if someone is waiting)
    ; waky next one (of any waiting)
0x0000C014       MOV R1 R8
0x0000C018       ADD R1 R1 MUTEX_WAITQ
0x0000C01C       BL waitq_wake_one

mutex_unlock_done:
0x0000C024       POP R10
0x0000C028       POP R9
0x0000C02C       POP R8
0x0000C030       POP LR
0x0000C034       RET

mutex_unlock_error:
    ; Not owner - ignore (or panic)
0x0000C038       POP R10
0x0000C03C       POP R9
0x0000C040       POP R8
0x0000C044       POP LR
0x0000C048       RET

; ================================================================
; waitq_wake_one - Wake exactly one task from the wait queue
; R1 = wait queue pointer
; ================================================================
waitq_wake_one:
0x0000C04C       PUSH LR
0x0000C050       PUSH R8
0x0000C054       PUSH R9
0x0000C058       PUSH R10
0x0000C05C       PUSH R11

0x0000C060       MOV R8 R1                  ; wait queue pointer
0x0000C064       LDW R9 [R8 + WQ_MASK]      ; current wait queue mask

0x0000C068       CMP R9 0
0x0000C06C       BEQ waitq_wake_one_done    ; No waiters

    ; Find the first waiting task
0x0000C074       LI R10 0                   ; task index

waitq_wake_one_find:
0x0000C07C       CMP R10 MAX_TASKS
0x0000C080       BGE waitq_wake_one_done

0x0000C088       LI R11 1
0x0000C090       SHL R11 R11 R10            ; bit for this task
0x0000C094       AND R2 R9 R11
0x0000C098       CMP R2 0
0x0000C09C       BNE waitq_wake_one_found

0x0000C0A4       ADD R10 R10 1
0x0000C0A8       B waitq_wake_one_find

waitq_wake_one_found:
    ; Clear this task's bit from the wait queue
0x0000C0B0       NOT R11 R11
0x0000C0B4       AND R9 R9 R11
0x0000C0B8       STW R9 [R8 + WQ_MASK]

    ; Wake this task
; macro: GET_TASK_PTR R5, R10
0x0000C0BC   LI R1 TASK_SIZE
0x0000C0C4   MUL R3 R10 R1
0x0000C0C8   LI R5 tasks
0x0000C0D0   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000C0D4   LI R1 TASK_READY
0x0000C0DC   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000C0E0   LI R1 WAIT_NONE
0x0000C0E8   STW R1 [R5 + TASK_WAIT]

waitq_wake_one_done:
0x0000C0EC       POP R11
0x0000C0F0       POP R10
0x0000C0F4       POP R9
0x0000C0F8       POP R8
0x0000C0FC       POP LR
0x0000C100       RET

; ================================================================
; CONSOLE MUTEX WRAPPER FUNCTIONS
; ================================================================

console_lock:
0x0000C104       PUSH LR
0x0000C108       LI R1 console_mutex
0x0000C110       BL mutex_lock
0x0000C118       POP LR
0x0000C11C       RET

console_unlock:
0x0000C120       PUSH LR
0x0000C124       LI R1 console_mutex
0x0000C12C       BL mutex_unlock
0x0000C134       POP LR
0x0000C138       RET

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
0x0000C13C       PUSH LR
0x0000C140       PUSH R6
0x0000C144       PUSH R7
0x0000C148       PUSH R8
0x0000C14C       PUSH R9

    ;------------------------------------
    ; Fill BMI packet
    ;------------------------------------
0x0000C150       LI  R6 BMI_BUF_WRITE

0x0000C158       STH R1 [R6 + BMI_HDR_OPCODE]

0x0000C15C       LI  R7 0
0x0000C164       STH R7 [R6 + BMI_HDR_FLAGS]

0x0000C168       STW R4 [R6 + BMI_HDR_NAMESPACE]
0x0000C16C       STW R3 [R6 + BMI_HDR_PAYLOAD_LEN]

    ; Copy payload

0x0000C170       ADD R7 R6 BMI_HDR_SIZEOF

0x0000C174       MOV R1 R7          ; dst
0x0000C178       MOV R2 R2          ; src
0x0000C17C       MOV R3 R3          ; len

0x0000C180       BL memcpy

    ;------------------------------------
    ; Ring doorbell
    ;------------------------------------

0x0000C188       LI  R6 BMI_REG_BASE

0x0000C190       LI  R7 BMI_READY
0x0000C198       STW R7 [R6 + BMI_STATUS]

0x0000C19C       LI  R7 1
0x0000C1A4       STW R7 [R6 + BMI_DOORBELL]

wait_reply:

0x0000C1A8       LDW R7 [R6 + BMI_STATUS]

    ;DEBUG 2

0x0000C1AC       CMP R7 BMI_DONE
0x0000C1B0       BEQ bmi_call_done

0x0000C1B8       CMP R7 BMI_ERROR
0x0000C1BC       BEQ bmi_call_error

0x0000C1C4       B wait_reply

bmi_call_done:

    ;----------------------------------------
    ; Read BMI reply packet
    ;----------------------------------------

0x0000C1CC       LI  R8 BMI_BUF_READ

0x0000C1D4       LDH R1 [R8 + BMI_HDR_OPCODE]
0x0000C1D8       LDH R2 [R8 + BMI_HDR_FLAGS]
0x0000C1DC       LDW R3 [R8 + BMI_HDR_NAMESPACE]
0x0000C1E0       LDW R4 [R8 + BMI_HDR_PAYLOAD_LEN]

    ; R8 + BMI_HDR_SIZEOF points to reply payload


0x0000C1E4       LDW R1 [R6 + BMI_REPLY]

    ; reset state

0x0000C1E8       LI R7 BMI_IDLE
0x0000C1F0       STW R7 [R6 + BMI_STATUS]

0x0000C1F4       POP R9
0x0000C1F8       POP R8
0x0000C1FC       POP R7
0x0000C200       POP R6
0x0000C204       POP LR
0x0000C208       RET

bmi_call_error:
0x0000C20C       LI R1 -1
0x0000C214       LI R7 BMI_IDLE
0x0000C21C       STW R7 [R6 + BMI_STATUS]

0x0000C220       POP R9
0x0000C224       POP R8
0x0000C228       POP R7
0x0000C22C       POP R6
0x0000C230       POP LR

0x0000C234       RET



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
.EQU FILE_APPEND, 0x12
.EQU DIR_CREATE,  0x20
.EQU DIR_DELETE,  0x21
.EQU NSFS_INDEX,  0x30


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

; bin/cat, 4695 bytes
    .ASCIIZ "bin/cat"
    .SPACE 116
    .ASCIIZ "00000011127"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4695 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x0004409E, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FE8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05
    .WORD 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081, 0x07000000, 0x000436FC, 0x04090080, 0x15000000
    .WORD 0x000436FC, 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080
    .WORD 0x07000000, 0x0004372C, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x05000000, 0x000437CC, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B
    .WORD 0x040B0090, 0x06000000, 0x00043758, 0x020707B0, 0x05000000, 0x00043778, 0x04070089, 0x14000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043778, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81
    .WORD 0x02040481, 0x01890600, 0x04090080, 0x07000000, 0x00043734, 0x030A0A81, 0x04040080, 0x06000000
    .WORD 0x000437C0, 0x20020A00, 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x00043798
    .WORD 0x0F020000, 0x00000000, 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000
    .WORD 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000
    .WORD 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080
    .WORD 0x06000000, 0x00043938, 0x02010181, 0x02040481, 0x05000000, 0x00043914, 0x01810300, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000
    .WORD 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439D0, 0x10090000, 0x0F010000, 0x00000008
    .WORD 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000, 0x000439B8, 0x01880100, 0x25090800
    .WORD 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x000439D8, 0x01810900, 0x40070000
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x000439D8, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080
    .WORD 0x06000000, 0x00043A50, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080
    .WORD 0x06000000, 0x00043A60, 0x040100CC, 0x07000000, 0x00043A50, 0x22020804, 0x02020281, 0x25020804
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043A68, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A68
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x04080080, 0x06000000, 0x00043AB4, 0x22010800, 0x40070000, 0x01810800, 0x30000000
    .WORD 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043ABC, 0x0F010000, 0xFFFFFFFF, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AF4, 0x0F020000, 0x00000000, 0x25020104
    .WORD 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B0C, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000
    .WORD 0x00043944, 0x04010080, 0x06000000, 0x00043B4C, 0x01820100, 0x0F010000, 0x00000001, 0x30000000
    .WORD 0x00043A78, 0x05000000, 0x00043B54, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x00043944
    .WORD 0x04010080, 0x06000000, 0x00043C20, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x000439E8
    .WORD 0x04010080, 0x06000000, 0x00043C04, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C20
    .WORD 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043BEC, 0x0F010000
    .WORD 0x00043C3C, 0x30000000, 0x00043098, 0x0F010000, 0x00043C40, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043B90, 0x01810800, 0x30000000, 0x00043A78, 0x0F010000, 0x00000000, 0x05000000, 0x00043C28
    .WORD 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F
    .WORD 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0
    .WORD 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C
    .WORD 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC
    .WORD 0x20010800, 0x04010080, 0x06000000, 0x00043F00, 0x040100A5, 0x07000000, 0x00043D54, 0x02080881
    .WORD 0x20020800, 0x04020080, 0x06000000, 0x00043F00, 0x040200A5, 0x06000000, 0x00043D64, 0x040200F3
    .WORD 0x06000000, 0x00043DF8, 0x040200E4, 0x06000000, 0x00043E14, 0x040200E9, 0x06000000, 0x00043E14
    .WORD 0x040200F8, 0x06000000, 0x00043E44, 0x040200E3, 0x06000000, 0x00043E74, 0x040200E2, 0x06000000
    .WORD 0x00043E94, 0x040200EF, 0x06000000, 0x00043EC4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043EF4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B
    .WORD 0x12000000, 0x00043DE4, 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8
    .WORD 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D7C
    .WORD 0x02090981, 0x30000000, 0x00043F20, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F64, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F84, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D7C, 0x20010100
    .WORD 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FA4, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FC4, 0x05000000, 0x00043EF4, 0x02080881, 0x05000000, 0x00043CA0
    .WORD 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000
    .WORD 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043800, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x0004382C, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043884, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043858, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188
    .WORD 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x402A0700, 0x00000004
    .WORD 0x00010F0A, 0x08810000, 0x08000208, 0x00802002, 0x00000402, 0x40720600, 0x00B00004, 0x00000402
    .WORD 0x40721200, 0x00B90004, 0x00000402, 0x40721400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000
    .WORD 0x09020809, 0x08810209, 0x00000208, 0x402A0500, 0x00810004, 0x0000040A, 0x40860700, 0x09000004
    .WORD 0x09812809, 0x09000209, 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100
    .WORD 0x0000100F, 0x00001006, 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C
    .WORD 0x01000F03, 0x0D030000, 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x420E1200
    .WORD 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x41DA1500, 0x0A000004
    .WORD 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00000F02, 0x00000000, 0x324C3000, 0x01000004
    .WORD 0x0080018B, 0x0000040B, 0x418E1200, 0x0B000004, 0x0C000181, 0x00000182, 0x01000F03, 0x00000000
    .WORD 0x32443000, 0x01000004, 0x00800187, 0x00000407, 0x41761300, 0x00000004, 0x00010F01, 0x0C000000
    .WORD 0x07000182, 0x00000183, 0x323C3000, 0x00000004, 0x412E0500, 0x0B000004, 0x00000181, 0x32543000
    .WORD 0x0A810004, 0x0000020A, 0x40F20500, 0x00000004, 0x42430F01, 0x00000004, 0x30583000, 0x0A000004
    .WORD 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x3FE60F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x40F20500, 0x00000004, 0x01000F02
    .WORD 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x422E0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00010F06, 0x00000000, 0x41DA0500, 0x73750004, 0x3A656761, 0x74616320, 0x6C696620, 0x2E2E2065
    .WORD 0x63000A2E, 0x203A7461, 0x6E6E6163, 0x6F20746F, 0x206E6570, 0x00000A00, 0x00000000, 0x00000000
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

; bin/echo, 4410 bytes
    .ASCIIZ "bin/echo"
    .SPACE 115
    .ASCIIZ "00000010472"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4410 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x0004409E, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FE8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05
    .WORD 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081, 0x07000000, 0x000436FC, 0x04090080, 0x15000000
    .WORD 0x000436FC, 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080
    .WORD 0x07000000, 0x0004372C, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x05000000, 0x000437CC, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B
    .WORD 0x040B0090, 0x06000000, 0x00043758, 0x020707B0, 0x05000000, 0x00043778, 0x04070089, 0x14000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043778, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81
    .WORD 0x02040481, 0x01890600, 0x04090080, 0x07000000, 0x00043734, 0x030A0A81, 0x04040080, 0x06000000
    .WORD 0x000437C0, 0x20020A00, 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x00043798
    .WORD 0x0F020000, 0x00000000, 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000
    .WORD 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000
    .WORD 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080
    .WORD 0x06000000, 0x00043938, 0x02010181, 0x02040481, 0x05000000, 0x00043914, 0x01810300, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000
    .WORD 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439D0, 0x10090000, 0x0F010000, 0x00000008
    .WORD 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000, 0x000439B8, 0x01880100, 0x25090800
    .WORD 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x000439D8, 0x01810900, 0x40070000
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x000439D8, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080
    .WORD 0x06000000, 0x00043A50, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080
    .WORD 0x06000000, 0x00043A60, 0x040100CC, 0x07000000, 0x00043A50, 0x22020804, 0x02020281, 0x25020804
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043A68, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A68
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x04080080, 0x06000000, 0x00043AB4, 0x22010800, 0x40070000, 0x01810800, 0x30000000
    .WORD 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043ABC, 0x0F010000, 0xFFFFFFFF, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AF4, 0x0F020000, 0x00000000, 0x25020104
    .WORD 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B0C, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000
    .WORD 0x00043944, 0x04010080, 0x06000000, 0x00043B4C, 0x01820100, 0x0F010000, 0x00000001, 0x30000000
    .WORD 0x00043A78, 0x05000000, 0x00043B54, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x00043944
    .WORD 0x04010080, 0x06000000, 0x00043C20, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x000439E8
    .WORD 0x04010080, 0x06000000, 0x00043C04, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C20
    .WORD 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043BEC, 0x0F010000
    .WORD 0x00043C3C, 0x30000000, 0x00043098, 0x0F010000, 0x00043C40, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043B90, 0x01810800, 0x30000000, 0x00043A78, 0x0F010000, 0x00000000, 0x05000000, 0x00043C28
    .WORD 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F
    .WORD 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0
    .WORD 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C
    .WORD 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC
    .WORD 0x20010800, 0x04010080, 0x06000000, 0x00043F00, 0x040100A5, 0x07000000, 0x00043D54, 0x02080881
    .WORD 0x20020800, 0x04020080, 0x06000000, 0x00043F00, 0x040200A5, 0x06000000, 0x00043D64, 0x040200F3
    .WORD 0x06000000, 0x00043DF8, 0x040200E4, 0x06000000, 0x00043E14, 0x040200E9, 0x06000000, 0x00043E14
    .WORD 0x040200F8, 0x06000000, 0x00043E44, 0x040200E3, 0x06000000, 0x00043E74, 0x040200E2, 0x06000000
    .WORD 0x00043E94, 0x040200EF, 0x06000000, 0x00043EC4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043EF4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B
    .WORD 0x12000000, 0x00043DE4, 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8
    .WORD 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D7C
    .WORD 0x02090981, 0x30000000, 0x00043F20, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F64, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F84, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D7C, 0x20010100
    .WORD 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FA4, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FC4, 0x05000000, 0x00043EF4, 0x02080881, 0x05000000, 0x00043CA0
    .WORD 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000
    .WORD 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043800, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x0004382C, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043884, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043858, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188
    .WORD 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x402A0700, 0x00000004
    .WORD 0x00010F0A, 0x08810000, 0x08000208, 0x00802002, 0x00000402, 0x40720600, 0x00B00004, 0x00000402
    .WORD 0x40721200, 0x00B90004, 0x00000402, 0x40721400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000
    .WORD 0x09020809, 0x08810209, 0x00000208, 0x402A0500, 0x00810004, 0x0000040A, 0x40860700, 0x09000004
    .WORD 0x09812809, 0x09000209, 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x02000188, 0x00000189, 0x00010F0A
    .WORD 0x09000000, 0x0B84018B, 0x0800020B, 0x0000040A, 0x411E1500, 0x0B000004, 0x00002201, 0x30583000
    .WORD 0x0A810004, 0x0B84020A, 0x0800020B, 0x0000040A, 0x410E1500, 0x00000004, 0x3FE40F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x40CA0500, 0x00000004, 0x3FE60F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00000F01, 0x00000000, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/ls, 4863 bytes
    .ASCIIZ "bin/ls"
    .SPACE 117
    .ASCIIZ "00000011377"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4863 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x0004409E, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FE8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05
    .WORD 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081, 0x07000000, 0x000436FC, 0x04090080, 0x15000000
    .WORD 0x000436FC, 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080
    .WORD 0x07000000, 0x0004372C, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x05000000, 0x000437CC, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B
    .WORD 0x040B0090, 0x06000000, 0x00043758, 0x020707B0, 0x05000000, 0x00043778, 0x04070089, 0x14000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043778, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81
    .WORD 0x02040481, 0x01890600, 0x04090080, 0x07000000, 0x00043734, 0x030A0A81, 0x04040080, 0x06000000
    .WORD 0x000437C0, 0x20020A00, 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x00043798
    .WORD 0x0F020000, 0x00000000, 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000
    .WORD 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000
    .WORD 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080
    .WORD 0x06000000, 0x00043938, 0x02010181, 0x02040481, 0x05000000, 0x00043914, 0x01810300, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000
    .WORD 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439D0, 0x10090000, 0x0F010000, 0x00000008
    .WORD 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000, 0x000439B8, 0x01880100, 0x25090800
    .WORD 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x000439D8, 0x01810900, 0x40070000
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x000439D8, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080
    .WORD 0x06000000, 0x00043A50, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080
    .WORD 0x06000000, 0x00043A60, 0x040100CC, 0x07000000, 0x00043A50, 0x22020804, 0x02020281, 0x25020804
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043A68, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A68
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x04080080, 0x06000000, 0x00043AB4, 0x22010800, 0x40070000, 0x01810800, 0x30000000
    .WORD 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043ABC, 0x0F010000, 0xFFFFFFFF, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AF4, 0x0F020000, 0x00000000, 0x25020104
    .WORD 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B0C, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000
    .WORD 0x00043944, 0x04010080, 0x06000000, 0x00043B4C, 0x01820100, 0x0F010000, 0x00000001, 0x30000000
    .WORD 0x00043A78, 0x05000000, 0x00043B54, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x00043944
    .WORD 0x04010080, 0x06000000, 0x00043C20, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x000439E8
    .WORD 0x04010080, 0x06000000, 0x00043C04, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C20
    .WORD 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043BEC, 0x0F010000
    .WORD 0x00043C3C, 0x30000000, 0x00043098, 0x0F010000, 0x00043C40, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043B90, 0x01810800, 0x30000000, 0x00043A78, 0x0F010000, 0x00000000, 0x05000000, 0x00043C28
    .WORD 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F
    .WORD 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0
    .WORD 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C
    .WORD 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC
    .WORD 0x20010800, 0x04010080, 0x06000000, 0x00043F00, 0x040100A5, 0x07000000, 0x00043D54, 0x02080881
    .WORD 0x20020800, 0x04020080, 0x06000000, 0x00043F00, 0x040200A5, 0x06000000, 0x00043D64, 0x040200F3
    .WORD 0x06000000, 0x00043DF8, 0x040200E4, 0x06000000, 0x00043E14, 0x040200E9, 0x06000000, 0x00043E14
    .WORD 0x040200F8, 0x06000000, 0x00043E44, 0x040200E3, 0x06000000, 0x00043E74, 0x040200E2, 0x06000000
    .WORD 0x00043E94, 0x040200EF, 0x06000000, 0x00043EC4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043EF4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B
    .WORD 0x12000000, 0x00043DE4, 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8
    .WORD 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D7C
    .WORD 0x02090981, 0x30000000, 0x00043F20, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F64, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F84, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D7C, 0x20010100
    .WORD 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FA4, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FC4, 0x05000000, 0x00043EF4, 0x02080881, 0x05000000, 0x00043CA0
    .WORD 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000
    .WORD 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043800, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x0004382C, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043884, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043858, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188
    .WORD 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x402A0700, 0x00000004
    .WORD 0x00010F0A, 0x08810000, 0x08000208, 0x00802002, 0x00000402, 0x40720600, 0x00B00004, 0x00000402
    .WORD 0x40721200, 0x00B90004, 0x00000402, 0x40721400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000
    .WORD 0x09020809, 0x08810209, 0x00000208, 0x402A0500, 0x00810004, 0x0000040A, 0x40860700, 0x09000004
    .WORD 0x09812809, 0x09000209, 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100
    .WORD 0x0000100F, 0x00001006, 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C
    .WORD 0x01000F03, 0x0D030000, 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x429E1200
    .WORD 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x426A1500, 0x0A000004
    .WORD 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00001001, 0x3FE60F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x42E80F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x42F80F01, 0x00000004, 0x30583000, 0x00000004, 0x3FE60F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x00001101, 0x00000F02, 0x00000000, 0x324C3000, 0x01000004
    .WORD 0x0080018B, 0x0000040B, 0x421E1200, 0x0B000004, 0x0C000181, 0x00000182, 0x004C0F03, 0x00000000
    .WORD 0x32443000, 0x01000004, 0x00800187, 0x00000407, 0x42060600, 0x00CC0004, 0x00000407, 0x42060700
    .WORD 0x0C080004, 0x0C8C2005, 0x00000201, 0x30583000, 0x00820004, 0x00000405, 0x41EE0700, 0x00000004
    .WORD 0x42FD0F01, 0x00000004, 0x30583000, 0x00000004, 0x3FE60F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x418E0500, 0x0B000004, 0x00000181, 0x32543000, 0x0A810004, 0x0000020A, 0x40F20500, 0x00000004
    .WORD 0x42D70F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x30583000, 0x00000004, 0x3FE60F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000
    .WORD 0x0000020A, 0x40F20500, 0x00000004, 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C
    .WORD 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100
    .WORD 0x42BE0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x00000000, 0x426A0500, 0x73750004
    .WORD 0x3A656761, 0x20736C20, 0x65726964, 0x726F7463, 0x2E2E2079, 0x6C000A2E, 0x63203A73, 0x6F6E6E61
    .WORD 0x706F2074, 0x00206E65, 0x202D2D2D, 0x65726944, 0x726F7463, 0x00203A79, 0x2D2D2D20, 0x00002F00
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/ls1, 4853 bytes
    .ASCIIZ "bin/ls1"
    .SPACE 116
    .ASCIIZ "00000011365"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4853 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x0004409E, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FE8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05
    .WORD 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081, 0x07000000, 0x000436FC, 0x04090080, 0x15000000
    .WORD 0x000436FC, 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080
    .WORD 0x07000000, 0x0004372C, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x05000000, 0x000437CC, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B
    .WORD 0x040B0090, 0x06000000, 0x00043758, 0x020707B0, 0x05000000, 0x00043778, 0x04070089, 0x14000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043778, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81
    .WORD 0x02040481, 0x01890600, 0x04090080, 0x07000000, 0x00043734, 0x030A0A81, 0x04040080, 0x06000000
    .WORD 0x000437C0, 0x20020A00, 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x00043798
    .WORD 0x0F020000, 0x00000000, 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000
    .WORD 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000
    .WORD 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080
    .WORD 0x06000000, 0x00043938, 0x02010181, 0x02040481, 0x05000000, 0x00043914, 0x01810300, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000
    .WORD 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439D0, 0x10090000, 0x0F010000, 0x00000008
    .WORD 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000, 0x000439B8, 0x01880100, 0x25090800
    .WORD 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x000439D8, 0x01810900, 0x40070000
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x000439D8, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080
    .WORD 0x06000000, 0x00043A50, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080
    .WORD 0x06000000, 0x00043A60, 0x040100CC, 0x07000000, 0x00043A50, 0x22020804, 0x02020281, 0x25020804
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043A68, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A68
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x04080080, 0x06000000, 0x00043AB4, 0x22010800, 0x40070000, 0x01810800, 0x30000000
    .WORD 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043ABC, 0x0F010000, 0xFFFFFFFF, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AF4, 0x0F020000, 0x00000000, 0x25020104
    .WORD 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B0C, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000
    .WORD 0x00043944, 0x04010080, 0x06000000, 0x00043B4C, 0x01820100, 0x0F010000, 0x00000001, 0x30000000
    .WORD 0x00043A78, 0x05000000, 0x00043B54, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x00043944
    .WORD 0x04010080, 0x06000000, 0x00043C20, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x000439E8
    .WORD 0x04010080, 0x06000000, 0x00043C04, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C20
    .WORD 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043BEC, 0x0F010000
    .WORD 0x00043C3C, 0x30000000, 0x00043098, 0x0F010000, 0x00043C40, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043B90, 0x01810800, 0x30000000, 0x00043A78, 0x0F010000, 0x00000000, 0x05000000, 0x00043C28
    .WORD 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F
    .WORD 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0
    .WORD 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C
    .WORD 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC
    .WORD 0x20010800, 0x04010080, 0x06000000, 0x00043F00, 0x040100A5, 0x07000000, 0x00043D54, 0x02080881
    .WORD 0x20020800, 0x04020080, 0x06000000, 0x00043F00, 0x040200A5, 0x06000000, 0x00043D64, 0x040200F3
    .WORD 0x06000000, 0x00043DF8, 0x040200E4, 0x06000000, 0x00043E14, 0x040200E9, 0x06000000, 0x00043E14
    .WORD 0x040200F8, 0x06000000, 0x00043E44, 0x040200E3, 0x06000000, 0x00043E74, 0x040200E2, 0x06000000
    .WORD 0x00043E94, 0x040200EF, 0x06000000, 0x00043EC4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043EF4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B
    .WORD 0x12000000, 0x00043DE4, 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8
    .WORD 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D7C
    .WORD 0x02090981, 0x30000000, 0x00043F20, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F64, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F84, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D7C, 0x20010100
    .WORD 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FA4, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FC4, 0x05000000, 0x00043EF4, 0x02080881, 0x05000000, 0x00043CA0
    .WORD 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000
    .WORD 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043800, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x0004382C, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043884, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043858, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188
    .WORD 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x402A0700, 0x00000004
    .WORD 0x00010F0A, 0x08810000, 0x08000208, 0x00802002, 0x00000402, 0x40720600, 0x00B00004, 0x00000402
    .WORD 0x40721200, 0x00B90004, 0x00000402, 0x40721400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000
    .WORD 0x09020809, 0x08810209, 0x00000208, 0x402A0500, 0x00810004, 0x0000040A, 0x40860700, 0x09000004
    .WORD 0x09812809, 0x09000209, 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100
    .WORD 0x0000100F, 0x00001006, 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C
    .WORD 0x004C0F03, 0x0D030000, 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x42921200
    .WORD 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x425E1500, 0x0A000004
    .WORD 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00001001, 0x3FE60F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x42DC0F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x42EC0F01, 0x00000004, 0x30583000, 0x00000004, 0x3FE60F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x00001101, 0x39443000, 0x01000004, 0x0080018B, 0x0000040B
    .WORD 0x42120600, 0x0B000004, 0x0C000181, 0x00000182, 0x39E83000, 0x00800004, 0x00000401, 0x41FA0600
    .WORD 0x00000004, 0xFFFF0F02, 0x0200FFFF, 0x00000401, 0x41FA0600, 0x0C080004, 0x0C8C2205, 0x00000201
    .WORD 0x30583000, 0x00820004, 0x00000405, 0x41E20700, 0x00000004, 0x42F10F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x3FE60F01, 0x00000004, 0x30583000, 0x00000004, 0x41860500, 0x0B000004, 0x00000181
    .WORD 0x3A783000, 0x0A810004, 0x0000020A, 0x40F20500, 0x00000004, 0x42CB0F01, 0x00000004, 0x30583000
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x42F30F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x40F20500, 0x00000004
    .WORD 0x004C0F03, 0x0D030000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x42B20F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00010F06, 0x00000000, 0x425E0500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964
    .WORD 0x726F7463, 0x2E2E2079, 0x6C000A2E, 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D
    .WORD 0x65726944, 0x726F7463, 0x00203A79, 0x2D2D2D20, 0x0A002F00, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/print, 4530 bytes
    .ASCIIZ "bin/print"
    .SPACE 114
    .ASCIIZ "00000010662"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4530 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x0004409E, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FE8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05
    .WORD 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081, 0x07000000, 0x000436FC, 0x04090080, 0x15000000
    .WORD 0x000436FC, 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080
    .WORD 0x07000000, 0x0004372C, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x05000000, 0x000437CC, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B
    .WORD 0x040B0090, 0x06000000, 0x00043758, 0x020707B0, 0x05000000, 0x00043778, 0x04070089, 0x14000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043778, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81
    .WORD 0x02040481, 0x01890600, 0x04090080, 0x07000000, 0x00043734, 0x030A0A81, 0x04040080, 0x06000000
    .WORD 0x000437C0, 0x20020A00, 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x00043798
    .WORD 0x0F020000, 0x00000000, 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000
    .WORD 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000
    .WORD 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080
    .WORD 0x06000000, 0x00043938, 0x02010181, 0x02040481, 0x05000000, 0x00043914, 0x01810300, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000
    .WORD 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439D0, 0x10090000, 0x0F010000, 0x00000008
    .WORD 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000, 0x000439B8, 0x01880100, 0x25090800
    .WORD 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x000439D8, 0x01810900, 0x40070000
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x000439D8, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080
    .WORD 0x06000000, 0x00043A50, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080
    .WORD 0x06000000, 0x00043A60, 0x040100CC, 0x07000000, 0x00043A50, 0x22020804, 0x02020281, 0x25020804
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043A68, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A68
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x04080080, 0x06000000, 0x00043AB4, 0x22010800, 0x40070000, 0x01810800, 0x30000000
    .WORD 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043ABC, 0x0F010000, 0xFFFFFFFF, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AF4, 0x0F020000, 0x00000000, 0x25020104
    .WORD 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B0C, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000
    .WORD 0x00043944, 0x04010080, 0x06000000, 0x00043B4C, 0x01820100, 0x0F010000, 0x00000001, 0x30000000
    .WORD 0x00043A78, 0x05000000, 0x00043B54, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x00043944
    .WORD 0x04010080, 0x06000000, 0x00043C20, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x000439E8
    .WORD 0x04010080, 0x06000000, 0x00043C04, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C20
    .WORD 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043BEC, 0x0F010000
    .WORD 0x00043C3C, 0x30000000, 0x00043098, 0x0F010000, 0x00043C40, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043B90, 0x01810800, 0x30000000, 0x00043A78, 0x0F010000, 0x00000000, 0x05000000, 0x00043C28
    .WORD 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F
    .WORD 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0
    .WORD 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C
    .WORD 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC
    .WORD 0x20010800, 0x04010080, 0x06000000, 0x00043F00, 0x040100A5, 0x07000000, 0x00043D54, 0x02080881
    .WORD 0x20020800, 0x04020080, 0x06000000, 0x00043F00, 0x040200A5, 0x06000000, 0x00043D64, 0x040200F3
    .WORD 0x06000000, 0x00043DF8, 0x040200E4, 0x06000000, 0x00043E14, 0x040200E9, 0x06000000, 0x00043E14
    .WORD 0x040200F8, 0x06000000, 0x00043E44, 0x040200E3, 0x06000000, 0x00043E74, 0x040200E2, 0x06000000
    .WORD 0x00043E94, 0x040200EF, 0x06000000, 0x00043EC4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043EF4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B
    .WORD 0x12000000, 0x00043DE4, 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8
    .WORD 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D7C
    .WORD 0x02090981, 0x30000000, 0x00043F20, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F64, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F84, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D7C, 0x20010100
    .WORD 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FA4, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FC4, 0x05000000, 0x00043EF4, 0x02080881, 0x05000000, 0x00043CA0
    .WORD 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000
    .WORD 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043800, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x0004382C, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043884, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043858, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188
    .WORD 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x402A0700, 0x00000004
    .WORD 0x00010F0A, 0x08810000, 0x08000208, 0x00802002, 0x00000402, 0x40720600, 0x00B00004, 0x00000402
    .WORD 0x40721200, 0x00B90004, 0x00000402, 0x40721400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000
    .WORD 0x09020809, 0x08810209, 0x00000208, 0x402A0500, 0x00810004, 0x0000040A, 0x40860700, 0x09000004
    .WORD 0x09812809, 0x09000209, 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100
    .WORD 0x0000100F, 0x00001008, 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408
    .WORD 0x41521200, 0x09040004, 0x01002201, 0x0000018A, 0x00000F02, 0x00000000, 0x00000F03, 0x00000000
    .WORD 0x00000F04, 0x09080000, 0x01002201, 0x00830182, 0x00000408, 0x41360600, 0x090C0004, 0x01002201
    .WORD 0x00840183, 0x00000408, 0x41360600, 0x09100004, 0x01002201, 0x00850184, 0x00000408, 0x41360600
    .WORD 0x09140004, 0x01002201, 0x00860185, 0x00000408, 0x41360600, 0x0A000004, 0x00000181, 0x3C443000
    .WORD 0x00000004, 0x00000F01, 0x00000000, 0x416A0500, 0x00000004, 0x41820F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00010F01, 0x00000000, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F
    .WORD 0x73753100, 0x3A656761, 0x69727020, 0x4620746E, 0x414D524F, 0x415B2054, 0x5D314752, 0x52415B20
    .WORD 0x205D3247, 0x4752415B, 0x5B205D33, 0x34475241, 0x0000005D, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; bin/sh, 5947 bytes
    .ASCIIZ "bin/sh"
    .SPACE 117
    .ASCIIZ "00000013473"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (5947 bytes, padded to 6144)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043644, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x0004409E, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FE8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05
    .WORD 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081, 0x07000000, 0x000436FC, 0x04090080, 0x15000000
    .WORD 0x000436FC, 0x0F020000, 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080
    .WORD 0x07000000, 0x0004372C, 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x05000000, 0x000437CC, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B
    .WORD 0x040B0090, 0x06000000, 0x00043758, 0x020707B0, 0x05000000, 0x00043778, 0x04070089, 0x14000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043778, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81
    .WORD 0x02040481, 0x01890600, 0x04090080, 0x07000000, 0x00043734, 0x030A0A81, 0x04040080, 0x06000000
    .WORD 0x000437C0, 0x20020A00, 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x00043798
    .WORD 0x0F020000, 0x00000000, 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000
    .WORD 0x110A0000, 0x11090000, 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000
    .WORD 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000
    .WORD 0x0F050000, 0x00000009, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x00000008, 0x0F040000, 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x00043688, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021
    .WORD 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000A, 0x30000000, 0x00043688, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x00043688
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080
    .WORD 0x06000000, 0x00043938, 0x02010181, 0x02040481, 0x05000000, 0x00043914, 0x01810300, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000
    .WORD 0x40060000, 0x01890100, 0x04010080, 0x12000000, 0x000439D0, 0x10090000, 0x0F010000, 0x00000008
    .WORD 0x30000000, 0x000434C8, 0x11090000, 0x04010080, 0x06000000, 0x000439B8, 0x01880100, 0x25090800
    .WORD 0x0F020000, 0x00000000, 0x25020804, 0x01810800, 0x05000000, 0x000439D8, 0x01810900, 0x40070000
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x000439D8, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080
    .WORD 0x06000000, 0x00043A50, 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080
    .WORD 0x06000000, 0x00043A60, 0x040100CC, 0x07000000, 0x00043A50, 0x22020804, 0x02020281, 0x25020804
    .WORD 0x0F010000, 0x00000001, 0x05000000, 0x00043A68, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A68
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x04080080, 0x06000000, 0x00043AB4, 0x22010800, 0x40070000, 0x01810800, 0x30000000
    .WORD 0x000435D8, 0x0F010000, 0x00000000, 0x05000000, 0x00043ABC, 0x0F010000, 0xFFFFFFFF, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043AF4, 0x0F020000, 0x00000000, 0x25020104
    .WORD 0x100F0000, 0x10080000, 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B0C, 0x22010100, 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000
    .WORD 0x00043944, 0x04010080, 0x06000000, 0x00043B4C, 0x01820100, 0x0F010000, 0x00000001, 0x30000000
    .WORD 0x00043A78, 0x05000000, 0x00043B54, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x00043944
    .WORD 0x04010080, 0x06000000, 0x00043C20, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x000439E8
    .WORD 0x04010080, 0x06000000, 0x00043C04, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C20
    .WORD 0x0201098C, 0x30000000, 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043BEC, 0x0F010000
    .WORD 0x00043C3C, 0x30000000, 0x00043098, 0x0F010000, 0x00043C40, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043B90, 0x01810800, 0x30000000, 0x00043A78, 0x0F010000, 0x00000000, 0x05000000, 0x00043C28
    .WORD 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F
    .WORD 0x0000000A, 0x100F0000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0
    .WORD 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C
    .WORD 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC
    .WORD 0x20010800, 0x04010080, 0x06000000, 0x00043F00, 0x040100A5, 0x07000000, 0x00043D54, 0x02080881
    .WORD 0x20020800, 0x04020080, 0x06000000, 0x00043F00, 0x040200A5, 0x06000000, 0x00043D64, 0x040200F3
    .WORD 0x06000000, 0x00043DF8, 0x040200E4, 0x06000000, 0x00043E14, 0x040200E9, 0x06000000, 0x00043E14
    .WORD 0x040200F8, 0x06000000, 0x00043E44, 0x040200E3, 0x06000000, 0x00043E74, 0x040200E2, 0x06000000
    .WORD 0x00043E94, 0x040200EF, 0x06000000, 0x00043EC4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098
    .WORD 0x01810200, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043EF4, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10030000, 0x30000000, 0x00043DBC, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B
    .WORD 0x12000000, 0x00043DE4, 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8
    .WORD 0x31000000, 0x0F040000, 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D7C
    .WORD 0x02090981, 0x30000000, 0x00043F20, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F64, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F84, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D7C, 0x20010100
    .WORD 0x02090981, 0x30000000, 0x00043098, 0x05000000, 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200
    .WORD 0x30000000, 0x00043FEA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FA4, 0x05000000
    .WORD 0x00043EF4, 0x30000000, 0x00043D9C, 0x01810200, 0x30000000, 0x00043FEA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FC4, 0x05000000, 0x00043EF4, 0x02080881, 0x05000000, 0x00043CA0
    .WORD 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000
    .WORD 0x00000001, 0x01820800, 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043800, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x0004382C, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043884, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x30000000, 0x00043858, 0x01810100, 0x30000000, 0x00043F20, 0x110F0000
    .WORD 0x31000000, 0x000A0020, 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188
    .WORD 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x402A0700, 0x00000004
    .WORD 0x00010F0A, 0x08810000, 0x08000208, 0x00802002, 0x00000402, 0x40720600, 0x00B00004, 0x00000402
    .WORD 0x40721200, 0x00B90004, 0x00000402, 0x40721400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000
    .WORD 0x09020809, 0x08810209, 0x00000208, 0x402A0500, 0x00810004, 0x0000040A, 0x40860700, 0x09000004
    .WORD 0x09812809, 0x09000209, 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100
    .WORD 0x0000100F, 0x00010F01, 0x00000000, 0x46120F02, 0x00000004, 0x00020F03, 0x00000000, 0x323C3000
    .WORD 0x00000004, 0x00000F01, 0x00000000, 0x463B0F02, 0x00000004, 0x007F0F03, 0x00000000, 0x32443000
    .WORD 0x00800004, 0x00000401, 0x42821300, 0x01000004, 0x00000184, 0x463B0F08, 0x00000004, 0x463B0F09
    .WORD 0x00000004, 0x00000F0A, 0x04000000, 0x0000040A, 0x41821500, 0x080A0004, 0x05000205, 0x008A2006
    .WORD 0x00000406, 0x41760600, 0x008D0004, 0x00000406, 0x41760600, 0x00880004, 0x00000406, 0x415E0600
    .WORD 0x00FF0004, 0x00000406, 0x415E0600, 0x09000004, 0x09812306, 0x00000209, 0x41760500, 0x08000004
    .WORD 0x00000409, 0x41761300, 0x09810004, 0x00000309, 0x41760500, 0x0A810004, 0x0000020A, 0x410A0500
    .WORD 0x00000004, 0x00000F06, 0x09000000, 0x00002306, 0x463B0F07, 0x07000004, 0x00802006, 0x00000406
    .WORD 0x40A20600, 0x00000004, 0x428A3000, 0x00000004, 0x463B0F01, 0x00000004, 0x46160F02, 0x00000004
    .WORD 0x31183000, 0x00810004, 0x00000401, 0x42820600, 0x00000004, 0x325C3000, 0x00800004, 0x00000401
    .WORD 0x421A0600, 0x00000004, 0x42521200, 0x00000004, 0xFFFF0F01, 0x0000FFFF, 0x00000F02, 0x00000000
    .WORD 0x326C3000, 0x00800004, 0x00000401, 0x426A1200, 0x00000004, 0x40A20500, 0x00000004, 0x463B0F01
    .WORD 0x00000004, 0x46BB0F02, 0x00000004, 0x00000F03, 0x00000000, 0x32643000, 0x00000004, 0x461B0F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x0000110F, 0x00003100, 0x46270F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x40A20500, 0x00000004, 0x46310F01, 0x00000004, 0x30583000, 0x00000004, 0x40A20500
    .WORD 0x00000004, 0x0000110F, 0x00003100, 0x0000100F, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B
    .WORD 0x0000100C, 0x463B0F08, 0x00000004, 0x463B0F09, 0x00000004, 0x00000F0A, 0x00000000, 0x00000F0C
    .WORD 0x08000000, 0x0080200B, 0x0000040B, 0x44F60600, 0x00A00004, 0x0000040B, 0x42EA0700, 0x08810004
    .WORD 0x00000208, 0x42C20500, 0x00880004, 0x0000040A, 0x44F61500, 0x00000004, 0x46BB0F07, 0x0A000004
    .WORD 0x06820186, 0x07060C06, 0x07000207, 0x0A812509, 0x0000020A, 0x00000F0C, 0x00000000, 0x43220500
    .WORD 0x08000004, 0x0080200B, 0x0000040B, 0x44EA0600, 0x00800004, 0x0000040C, 0x43AA0700, 0x00A00004
    .WORD 0x0000040B, 0x44CE0600, 0x00A20004, 0x0000040B, 0x43820600, 0x00A70004, 0x0000040B, 0x43960600
    .WORD 0x00DC0004, 0x0000040B, 0x43EA0600, 0x09000004, 0x0881230B, 0x09810208, 0x00000209, 0x43220500
    .WORD 0x00000004, 0x00220F0C, 0x08810000, 0x00000208, 0x43220500, 0x00000004, 0x00270F0C, 0x08810000
    .WORD 0x00000208, 0x43220500, 0x0C000004, 0x0000040B, 0x43D60600, 0x00DC0004, 0x0000040B, 0x43EA0600
    .WORD 0x09000004, 0x0881230B, 0x09810208, 0x00000209, 0x43220500, 0x00000004, 0x00000F0C, 0x08810000
    .WORD 0x00000208, 0x43220500, 0x08810004, 0x08000208, 0x0080200B, 0x0000040B, 0x44EA0600, 0x00EE0004
    .WORD 0x0000040B, 0x445A0600, 0x00F20004, 0x0000040B, 0x446A0600, 0x00F40004, 0x0000040B, 0x447A0600
    .WORD 0x00DC0004, 0x0000040B, 0x448A0600, 0x00A20004, 0x0000040B, 0x449A0600, 0x00A70004, 0x0000040B
    .WORD 0x44AA0600, 0x09000004, 0x0881230B, 0x09810208, 0x00000209, 0x43220500, 0x00000004, 0x000A0F0B
    .WORD 0x00000000, 0x44BA0500, 0x00000004, 0x000D0F0B, 0x00000000, 0x44BA0500, 0x00000004, 0x00090F0B
    .WORD 0x00000000, 0x44BA0500, 0x00000004, 0x005C0F0B, 0x00000000, 0x44BA0500, 0x00000004, 0x00220F0B
    .WORD 0x00000000, 0x44BA0500, 0x00000004, 0x00270F0B, 0x00000000, 0x44BA0500, 0x09000004, 0x0881230B
    .WORD 0x09810208, 0x00000209, 0x43220500, 0x00000004, 0x00000F0B, 0x09000000, 0x0981230B, 0x08810209
    .WORD 0x00000208, 0x42C20500, 0x00000004, 0x00000F0B, 0x09000000, 0x0000230B, 0x46BB0F07, 0x0A000004
    .WORD 0x06820186, 0x07060C06, 0x00000207, 0x00000F0B, 0x07000000, 0x0000250B, 0x0000110C, 0x0000110B
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001008, 0x00001009
    .WORD 0x0000100A, 0x0000100B, 0x463B0F08, 0x00000004, 0x46BB0F09, 0x00000004, 0x00000F0A, 0x08000000
    .WORD 0x00A0200B, 0x0000040B, 0x42EA0700, 0x00000004, 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208
    .WORD 0x455E0500, 0x08000004, 0x0080200B, 0x0000040B, 0x44F60600, 0x00880004, 0x0000040A, 0x44F61500
    .WORD 0x09000004, 0x09842508, 0x0A810209, 0x0800020A, 0x0080200B, 0x0000040B, 0x44F60600, 0x00A00004
    .WORD 0x0000040B, 0x45D60600, 0x08810004, 0x00000208, 0x43220500, 0x00000004, 0x00000F0B, 0x08000000
    .WORD 0x0881230B, 0x00000208, 0x42C20500, 0x00000004, 0x00000F0B, 0x09000000, 0x0000250B, 0x0000110B
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x20243100, 0x7571000D, 0x45007469, 0x56434558
    .WORD 0x52452045, 0x46000A52, 0x204B524F, 0x0A525245, 0x49415700, 0x52452054, 0x00000A52, 0x00000000
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

; etc/logo.txt, 769 bytes
    .ASCIIZ "etc/logo.txt"
    .SPACE 111
    .ASCIIZ "00000001401"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (769 bytes, padded to 1024)
    .WORD 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848
    .WORD 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x480A4848, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20480A48, 0x20484820, 0x48482020, 0x48482020, 0x20484848
    .WORD 0x48482020, 0x20203348, 0x32322020, 0x20323232, 0x20202020, 0x202B2020, 0x20202B20, 0x2020202B
    .WORD 0x48202020, 0x2020480A, 0x20204848, 0x20204848, 0x20484820, 0x20484820, 0x20202020, 0x20203333
    .WORD 0x20203232, 0x20323220, 0x20202020, 0x202B2020, 0x202B202B, 0x20202020, 0x0A482020, 0x48202048
    .WORD 0x48484848, 0x20202020, 0x48484848, 0x20202048, 0x33484848, 0x20202033, 0x32202020, 0x20202032
    .WORD 0x2B202020, 0x2B202B20, 0x2B202B20, 0x20202020, 0x480A4820, 0x48482020, 0x48482020, 0x48202020
    .WORD 0x48482048, 0x20202020, 0x33332020, 0x20202020, 0x20203232, 0x20202020, 0x20202020, 0x202B202B
    .WORD 0x2020202B, 0x20202020, 0x20480A48, 0x20484820, 0x48482020, 0x48482020, 0x48482020, 0x48482020
    .WORD 0x20203348, 0x32323220, 0x32323232, 0x20202020, 0x202B2020, 0x20202B20, 0x2020202B, 0x48202020
    .WORD 0x2020480A, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A482020, 0x3D3D3D48, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x4F423D3D, 0x4E49544F, 0x3D3D3D47, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x480A483D, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202048, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20480A48, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x48202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x48202020, 0x2020480A
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x24202020, 0x20202020, 0x20482020, 0x20202020, 0x20202420
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A482020, 0x3D3D3D48, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D483D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x480A483D, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848
    .WORD 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848, 0x48484848
    .WORD 0x00000048, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; lib/libc.inc, 44368 bytes
    .ASCIIZ "lib/libc.inc"
    .SPACE 111
    .ASCIIZ "00000126520"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (44368 bytes, padded to 44544)
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
    .WORD 0x6E697274, 0x6F742067, 0x64747320, 0x0A74756F, 0x4E49203B, 0x5220203A, 0x203D2031, 0x69727473
    .WORD 0x7020676E, 0x746E696F, 0x3B0A7265, 0x54554F20, 0x3152203A, 0x62203D20, 0x73657479, 0x69727720
    .WORD 0x6E657474, 0x20726F20, 0x6F727265, 0x6F632072, 0x3B0A6564, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x700A3D3D, 0x3A737475, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048
    .WORD 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x564F4D20, 0x20385220, 0x20203152, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x65766153, 0x72747320, 0x20676E69, 0x6E696F70, 0x0A726574, 0x20202020
    .WORD 0x73204C42, 0x656C7274, 0x2020206E, 0x20202020, 0x20202020, 0x47203B20, 0x73207465, 0x6E697274
    .WORD 0x656C2067, 0x6874676E, 0x2020200A, 0x564F4D20, 0x20395220, 0x20203152, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x65766153, 0x6E656C20, 0x0A687467, 0x20202020, 0x5220494C, 0x54532031, 0x54554F44
    .WORD 0x0A44465F, 0x20202020, 0x20564F4D, 0x52203252, 0x20202038, 0x20202020, 0x20202020, 0x42203B20
    .WORD 0x65666675, 0x203D2072, 0x69727473, 0x200A676E, 0x4D202020, 0x5220564F, 0x39522033, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6F43203B, 0x20746E75, 0x656C203D, 0x6874676E, 0x2020200A, 0x43565320
    .WORD 0x53595320, 0x4952575F, 0x200A4554, 0x3B202020, 0x2020494C, 0x31203152, 0x20202030, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x6C77654E, 0x20656E69, 0x72616863, 0x65746361, 0x20200A72, 0x423B2020
    .WORD 0x7020204C, 0x68637475, 0x20207261, 0x20202020, 0x20202020, 0x57203B20, 0x65746972, 0x77656E20
    .WORD 0x656E696C, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020
    .WORD 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D
    .WORD 0x74757020, 0x72616863, 0x57202D20, 0x65746972, 0x6E697320, 0x20656C67, 0x72616863, 0x65746361
    .WORD 0x6F742072, 0x64747320, 0x0A74756F, 0x4E49203B, 0x5220203A, 0x203D2031, 0x72616863, 0x65746361
    .WORD 0x203B0A72, 0x3A54554F, 0x20315220, 0x7962203D, 0x20736574, 0x74697277, 0x206E6574, 0x20293128
    .WORD 0x6520726F, 0x726F7272, 0x646F6320, 0x3D3B0A65, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x75700A3D
    .WORD 0x61686374, 0x200A3A72, 0x50202020, 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852
    .WORD 0x4C202020, 0x38522049, 0x5F686320, 0x0A667562, 0x20202020, 0x20425453, 0x5B203152, 0x205D3852
    .WORD 0x20202020, 0x20202020, 0x53203B20, 0x65726F74, 0x61686320, 0x6E692072, 0x61747320, 0x20636974
    .WORD 0x66667562, 0x200A7265, 0x4C202020, 0x31522049, 0x44545320, 0x5F54554F, 0x200A4446, 0x4D202020
    .WORD 0x5220564F, 0x38522032, 0x2020200A, 0x20494C20, 0x31203352, 0x2020200A, 0x43565320, 0x53595320
    .WORD 0x4952575F, 0x200A4554, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A
    .WORD 0x54455220, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x6C727473, 0x2D206E65
    .WORD 0x6C614320, 0x616C7563, 0x73206574, 0x6E697274, 0x656C2067, 0x6874676E, 0x49203B0A, 0x20203A4E
    .WORD 0x3D203152, 0x72747320, 0x20676E69, 0x6E696F70, 0x0A726574, 0x554F203B, 0x52203A54, 0x203D2031
    .WORD 0x676E656C, 0x28206874, 0x6C637865, 0x6E696475, 0x756E2067, 0x74206C6C, 0x696D7265, 0x6F74616E
    .WORD 0x3B0A2972, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x730A3D3D, 0x656C7274, 0x200A3A6E, 0x50202020
    .WORD 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952
    .WORD 0x4D202020, 0x5220564F, 0x31522038, 0x2020200A, 0x20494C20, 0x30203952, 0x7274730A, 0x5F6E656C
    .WORD 0x706F6F6C, 0x20200A3A, 0x444C2020, 0x32522042, 0x38525B20, 0x52202B20, 0x20205D39, 0x3B202020
    .WORD 0x61655220, 0x68632064, 0x63617261, 0x20726574, 0x63207461, 0x65727275, 0x6F20746E, 0x65736666
    .WORD 0x20200A74, 0x4D432020, 0x32522050, 0x200A3020, 0x42202020, 0x73205145, 0x656C7274, 0x6F645F6E
    .WORD 0x200A656E, 0x41202020, 0x52204444, 0x39522039, 0x20203120, 0x20202020, 0x20202020, 0x6E49203B
    .WORD 0x6D657263, 0x20746E65, 0x6E756F63, 0x0A726574, 0x20202020, 0x74732042, 0x6E656C72, 0x6F6F6C5F
    .WORD 0x74730A70, 0x6E656C72, 0x6E6F645F, 0x200A3A65, 0x4D202020, 0x5220564F, 0x39522031, 0x2020200A
    .WORD 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52
    .WORD 0x45522020, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x72747320, 0x20706D63
    .WORD 0x6F43202D, 0x7261706D, 0x77742065, 0x7473206F, 0x676E6972, 0x203B0A73, 0x203A4E49, 0x20315220
    .WORD 0x7473203D, 0x676E6972, 0x52202C31, 0x203D2032, 0x69727473, 0x0A32676E, 0x554F203B, 0x52203A54
    .WORD 0x203D2031, 0x66692031, 0x75716520, 0x202C6C61, 0x66692030, 0x66696420, 0x65726566, 0x3B0A746E
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x730A3D3D, 0x6D637274, 0x200A3A70, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x50202020
    .WORD 0x20485355, 0x0A303152, 0x20202020, 0x20564F4D, 0x52203852, 0x20200A31, 0x4F4D2020, 0x39522056
    .WORD 0x0A325220, 0x63727473, 0x6C5F706D, 0x3A706F6F, 0x2020200A, 0x42444C20, 0x30315220, 0x38525B20
    .WORD 0x2020205D, 0x20202020, 0x203B2020, 0x64616F4C, 0x61686320, 0x72662072, 0x73206D6F, 0x6E697274
    .WORD 0x200A3167, 0x4C202020, 0x52204244, 0x525B2031, 0x20205D39, 0x20202020, 0x20202020, 0x6F4C203B
    .WORD 0x63206461, 0x20726168, 0x6D6F7266, 0x72747320, 0x32676E69, 0x2020200A, 0x504D4320, 0x30315220
    .WORD 0x0A315220, 0x20202020, 0x20454E42, 0x63727473, 0x6E5F706D, 0x20202065, 0x20202020, 0x4D203B20
    .WORD 0x616D7369, 0x20686374, 0x6E756F66, 0x20200A64, 0x4D432020, 0x31522050, 0x0A302030, 0x20202020
    .WORD 0x20514542, 0x63727473, 0x655F706D, 0x20202071, 0x20202020, 0x42203B20, 0x2068746F, 0x69727473
    .WORD 0x2073676E, 0x65646E65, 0x74612064, 0x6D617320, 0x69742065, 0x200A656D, 0x41202020, 0x52204444
    .WORD 0x38522038, 0x20203120, 0x20202020, 0x20202020, 0x6441203B, 0x636E6176, 0x6F622065, 0x70206874
    .WORD 0x746E696F, 0x0A737265, 0x20202020, 0x20444441, 0x52203952, 0x0A312039, 0x20202020, 0x74732042
    .WORD 0x706D6372, 0x6F6F6C5F, 0x74730A70, 0x706D6372, 0x3A71655F, 0x2020200A, 0x20494C20, 0x31203152
    .WORD 0x2020200A, 0x73204220, 0x6D637274, 0x6F645F70, 0x730A656E, 0x6D637274, 0x656E5F70, 0x20200A3A
    .WORD 0x494C2020, 0x20315220, 0x74730A30, 0x706D6372, 0x6E6F645F, 0x200A3A65, 0x50202020, 0x5220504F
    .WORD 0x200A3031, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020
    .WORD 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x6D203B0A
    .WORD 0x70636D65, 0x202D2079, 0x79706F43, 0x6D656D20, 0x2079726F, 0x636F6C62, 0x203B0A6B, 0x203A4E49
    .WORD 0x20315220, 0x6564203D, 0x202C7473, 0x3D203252, 0x63727320, 0x3352202C, 0x63203D20, 0x746E756F
    .WORD 0x4F203B0A, 0x203A5455, 0x3D203152, 0x73656420, 0x65282074, 0x7020646E, 0x7469736F, 0x296E6F69
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x6D656D0A, 0x3A797063, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A
    .WORD 0x53555020, 0x31522048, 0x20200A30, 0x4F4D2020, 0x38522056, 0x0A315220, 0x20202020, 0x20564F4D
    .WORD 0x52203952, 0x20200A32, 0x4F4D2020, 0x31522056, 0x33522030, 0x6D656D0A, 0x5F797063, 0x706F6F6C
    .WORD 0x20200A3A, 0x4D432020, 0x31522050, 0x0A302030, 0x20202020, 0x20514542, 0x636D656D, 0x645F7970
    .WORD 0x0A656E6F, 0x20202020, 0x2042444C, 0x5B203152, 0x205D3952, 0x20202020, 0x20202020, 0x52203B20
    .WORD 0x20646165, 0x65747962, 0x6F726620, 0x6F73206D, 0x65637275, 0x2020200A, 0x42545320, 0x20315220
    .WORD 0x5D38525B, 0x20202020, 0x20202020, 0x203B2020, 0x74697257, 0x79622065, 0x74206574, 0x6564206F
    .WORD 0x6E697473, 0x6F697461, 0x20200A6E, 0x44412020, 0x38522044, 0x20385220, 0x20202031, 0x20202020
    .WORD 0x3B202020, 0x76644120, 0x65636E61, 0x746F6220, 0x6F702068, 0x65746E69, 0x200A7372, 0x41202020
    .WORD 0x52204444, 0x39522039, 0x200A3120, 0x53202020, 0x52204255, 0x52203031, 0x31203031, 0x20202020
    .WORD 0x20202020, 0x6544203B, 0x6D657263, 0x20746E65, 0x6E756F63, 0x0A726574, 0x20202020, 0x656D2042
    .WORD 0x7970636D, 0x6F6F6C5F, 0x656D0A70, 0x7970636D, 0x6E6F645F, 0x200A3A65, 0x4D202020, 0x5220564F
    .WORD 0x38522031, 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020
    .WORD 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x6D656D20, 0x20746573, 0x6946202D, 0x6D206C6C, 0x726F6D65
    .WORD 0x69772079, 0x63206874, 0x74736E6F, 0x20746E61, 0x65747962, 0x49203B0A, 0x20203A4E, 0x3D203152
    .WORD 0x73656420, 0x52202C74, 0x203D2032, 0x756C6176, 0x52202C65, 0x203D2033, 0x6E756F63, 0x203B0A74
    .WORD 0x3A54554F, 0x20315220, 0x6564203D, 0x28207473, 0x20646E65, 0x69736F70, 0x6E6F6974, 0x3D3B0A29
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x656D0A3D, 0x7465736D, 0x20200A3A, 0x55502020, 0x4C204853
    .WORD 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x55502020
    .WORD 0x52204853, 0x200A3031, 0x4D202020, 0x5220564F, 0x31522038, 0x2020200A, 0x564F4D20, 0x20395220
    .WORD 0x200A3252, 0x4D202020, 0x5220564F, 0x52203031, 0x656D0A33, 0x7465736D, 0x6F6F6C5F, 0x200A3A70
    .WORD 0x43202020, 0x5220504D, 0x30203031, 0x2020200A, 0x51454220, 0x6D656D20, 0x5F746573, 0x656E6F64
    .WORD 0x2020200A, 0x42545320, 0x20395220, 0x5D38525B, 0x20202020, 0x20202020, 0x203B2020, 0x726F7453
    .WORD 0x61762065, 0x2065756C, 0x63207461, 0x65727275, 0x7020746E, 0x7469736F, 0x0A6E6F69, 0x20202020
    .WORD 0x20444441, 0x52203852, 0x20312038, 0x20202020, 0x20202020, 0x41203B20, 0x6E617664, 0x70206563
    .WORD 0x746E696F, 0x200A7265, 0x53202020, 0x52204255, 0x52203031, 0x31203031, 0x20202020, 0x20202020
    .WORD 0x6544203B, 0x6D657263, 0x20746E65, 0x6E756F63, 0x0A726574, 0x20202020, 0x656D2042, 0x7465736D
    .WORD 0x6F6F6C5F, 0x656D0A70, 0x7465736D, 0x6E6F645F, 0x200A3A65, 0x4D202020, 0x5220564F, 0x38522031
    .WORD 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50
    .WORD 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x69727720, 0x66286574, 0x62202C64, 0x202C6675, 0x296E656C, 0x3B0A3B0A
    .WORD 0x3A4E4920, 0x20203B0A, 0x20315220, 0x6466203D, 0x20203B0A, 0x20325220, 0x7562203D, 0x72656666
    .WORD 0x20203B0A, 0x20335220, 0x656C203D, 0x6874676E, 0x3B0A3B0A, 0x54554F20, 0x203B0A3A, 0x31522020
    .WORD 0x62203D20, 0x73657479, 0x69727720, 0x6E657474, 0x65202F20, 0x6F6E7272, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x6972770A, 0x0A3A6574, 0x20202020, 0x20435653, 0x5F535953, 0x54495257
    .WORD 0x20200A45, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6572203B
    .WORD 0x66286461, 0x62202C64, 0x202C6675, 0x296E656C, 0x3B0A3B0A, 0x3A4E4920, 0x20203B0A, 0x20315220
    .WORD 0x6466203D, 0x20203B0A, 0x20325220, 0x7562203D, 0x72656666, 0x20203B0A, 0x20335220, 0x656C203D
    .WORD 0x6874676E, 0x3B0A3B0A, 0x54554F20, 0x203B0A3A, 0x31522020, 0x62203D20, 0x73657479, 0x61657220
    .WORD 0x2D3B0A64, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x65720A2D, 0x0A3A6461, 0x20202020, 0x20435653
    .WORD 0x5F535953, 0x44414552, 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x65706F20, 0x6170286E, 0x202C6874, 0x67616C66, 0x3B0A2973, 0x49203B0A, 0x3B0A3A4E
    .WORD 0x52202020, 0x203D2031, 0x68746170, 0x20203B0A, 0x20325220, 0x6C66203D, 0x0A736761, 0x203B0A3B
    .WORD 0x3A54554F, 0x20203B0A, 0x20315220, 0x6466203D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x65706F0A, 0x200A3A6E, 0x53202020, 0x53204356, 0x4F5F5359, 0x0A4E4550, 0x20202020, 0x0A544552
    .WORD 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x736F6C63, 0x64662865, 0x2D3B0A29
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C630A2D, 0x3A65736F, 0x2020200A, 0x43565320, 0x53595320
    .WORD 0x4F4C435F, 0x200A4553, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x66203B0A, 0x286B726F, 0x0A3B0A29, 0x6170203B, 0x746E6572, 0x203B0A3A, 0x31522020, 0x63203D20
    .WORD 0x646C6968, 0x64697020, 0x3B0A3B0A, 0x69686320, 0x0A3A646C, 0x2020203B, 0x3D203152, 0x3B0A3020
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x660A2D2D, 0x3A6B726F, 0x2020200A, 0x43565320, 0x53595320
    .WORD 0x524F465F, 0x20200A4B, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x7865203B, 0x65766365, 0x74617028, 0x61202C68, 0x2C766772, 0x766E6520, 0x3B0A2970, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x650A2D2D, 0x76636578, 0x200A3A65, 0x53202020, 0x53204356, 0x455F5359
    .WORD 0x56434558, 0x20200A45, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x6177203B, 0x69707469, 0x69702864, 0x74732C64, 0x73757461, 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x61770A2D, 0x69707469, 0x200A3A64, 0x53202020, 0x53204356, 0x575F5359, 0x50544941
    .WORD 0x200A4449, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x73203B0A
    .WORD 0x7065656C, 0x6C696D28, 0x6573696C, 0x646E6F63, 0x3B0A2973, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x730A2D2D, 0x7065656C, 0x20200A3A, 0x56532020, 0x59532043, 0x4C535F53, 0x0A504545, 0x20202020
    .WORD 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x74697865, 0x61747328
    .WORD 0x29737574, 0x3B0A3B0A, 0x76656E20, 0x72207265, 0x72757465, 0x3B0A736E, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x650A2D2D, 0x3A746978, 0x2020200A, 0x43565320, 0x53595320, 0x4958455F, 0x650A0A54
    .WORD 0x5F746978, 0x676E6168, 0x20200A3A, 0x20422020, 0x74697865, 0x6E61685F, 0x0A0A0A67, 0x3D3D3D3B
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x454D203B, 0x59524F4D, 0x4E414D20, 0x4D454741, 0x0A544E45
    .WORD 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x56203B0A, 0x20595245, 0x504D4953, 0x4D20454C, 0x524F4D45, 0x4C412059, 0x41434F4C, 0x0A524F54
    .WORD 0x203B0A3B, 0x73696854, 0x20736920, 0x696D2061, 0x616D696E, 0x616D206C, 0x636F6C6C, 0x6572662F
    .WORD 0x6D692065, 0x6D656C70, 0x61746E65, 0x6E6F6974, 0x61687420, 0x3B0A3A74, 0x202E3120, 0x73657355
    .WORD 0x66206120, 0x64657869, 0x72726120, 0x74207961, 0x7274206F, 0x206B6361, 0x6F6D656D, 0x62207972
    .WORD 0x6B636F6C, 0x203B0A73, 0x44202E32, 0x2073656F, 0x20544F4E, 0x6C616F63, 0x65637365, 0x656D2820
    .WORD 0x20656772, 0x616A6461, 0x746E6563, 0x65726620, 0x6C622065, 0x736B636F, 0x203B0A29, 0x44202E33
    .WORD 0x2073656F, 0x20544F4E, 0x696C7073, 0x6C622074, 0x736B636F, 0x73752820, 0x65207365, 0x7269746E
    .WORD 0x6C622065, 0x206B636F, 0x692D7361, 0x3B0A2973, 0x202E3420, 0x73657355, 0x72696620, 0x662D7473
    .WORD 0x73207469, 0x63726165, 0x66282068, 0x73646E69, 0x72696620, 0x62207473, 0x6B636F6C, 0x61687420
    .WORD 0x20732774, 0x20676962, 0x756F6E65, 0x0A296867, 0x2E35203B, 0x65735520, 0x62732073, 0x73206B72
    .WORD 0x61637379, 0x74206C6C, 0x6567206F, 0x6F6D2074, 0x6D206572, 0x726F6D65, 0x72662079, 0x6B206D6F
    .WORD 0x656E7265, 0x0A3B0A6C, 0x7254203B, 0x2D656461, 0x7366666F, 0x203B0A3A, 0x6556202B, 0x73207972
    .WORD 0x6C706D69, 0x6E612065, 0x61652064, 0x74207973, 0x6E75206F, 0x73726564, 0x646E6174, 0x2B203B0A
    .WORD 0x65725020, 0x74636964, 0x656C6261, 0x6D656D20, 0x2079726F, 0x67617375, 0x66282065, 0x64657869
    .WORD 0x62617420, 0x0A29656C, 0x202B203B, 0x63206F4E, 0x6C706D6F, 0x6C207865, 0x656B6E69, 0x696C2064
    .WORD 0x6D207473, 0x67616E61, 0x6E656D65, 0x203B0A74, 0x654D202D, 0x79726F6D, 0x61726620, 0x6E656D67
    .WORD 0x69746174, 0x28206E6F, 0x276E6163, 0x656D2074, 0x20656772, 0x65657266, 0x6F6C6220, 0x29736B63
    .WORD 0x2D203B0A, 0x73615720, 0x20646574, 0x63617073, 0x63282065, 0x74276E61, 0x6C707320, 0x6C207469
    .WORD 0x65677261, 0x6F6C6220, 0x29736B63, 0x2D203B0A, 0x6D694C20, 0x64657469, 0x206F7420, 0x5F58414D
    .WORD 0x434F4C42, 0x6120534B, 0x636F6C6C, 0x6F697461, 0x3B0A736E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A0A2D2D, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x4F43203B, 0x4154534E, 0x0A53544E
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x51452E0A, 0x414D2055, 0x4C425F58, 0x534B434F
    .WORD 0x3834202C, 0x20202020, 0x3B202020, 0x78614D20, 0x6D756D69, 0x6D756E20, 0x20726562, 0x6220666F
    .WORD 0x6B636F6C, 0x65772073, 0x6E616320, 0x61727420, 0x200A6B63, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x28203B20, 0x276E6163, 0x6C612074, 0x61636F6C, 0x6D206574
    .WORD 0x2065726F, 0x6E616874, 0x20323320, 0x656D6974, 0x69772073, 0x756F6874, 0x72662074, 0x6E696565
    .WORD 0x0A0A2967, 0x6C42203B, 0x206B636F, 0x63736564, 0x74706972, 0x6F20726F, 0x65736666, 0x28207374
    .WORD 0x68636165, 0x6F6C6220, 0x6E206B63, 0x73646565, 0x65687420, 0x33206573, 0x6C617620, 0x29736575
    .WORD 0x51452E0A, 0x4C422055, 0x5F4B434F, 0x52444441, 0x3020202C, 0x20202020, 0x3B202020, 0x66664F20
    .WORD 0x3A746573, 0x61747320, 0x6E697472, 0x64612067, 0x73657264, 0x666F2073, 0x65687420, 0x6F6C6220
    .WORD 0x28206B63, 0x79622034, 0x29736574, 0x51452E0A, 0x4C422055, 0x5F4B434F, 0x455A4953, 0x3420202C
    .WORD 0x20202020, 0x3B202020, 0x66664F20, 0x3A746573, 0x7A697320, 0x666F2065, 0x65687420, 0x6F6C6220
    .WORD 0x69206B63, 0x7962206E, 0x20736574, 0x62203428, 0x73657479, 0x0A202029, 0x5551452E, 0x4F4C4220
    .WORD 0x555F4B43, 0x2C444553, 0x20382020, 0x20202020, 0x203B2020, 0x7366664F, 0x203A7465, 0x72663D30
    .WORD 0x202C6565, 0x73753D31, 0x28206465, 0x79622034, 0x29736574, 0x51452E0A, 0x4C422055, 0x5F4B434F
    .WORD 0x43534544, 0x3120202C, 0x20202032, 0x3B202020, 0x746F5420, 0x73206C61, 0x20657A69, 0x6F20666F
    .WORD 0x6220656E, 0x6B636F6C, 0x73656420, 0x70697263, 0x20726F74, 0x77203328, 0x7364726F, 0x31203D20
    .WORD 0x79622032, 0x29736574, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x41544144
    .WORD 0x43455320, 0x4E4F4954, 0x54202D20, 0x62206568, 0x6B636F6C, 0x62617420, 0x0A20656C, 0x6F6E203B
    .WORD 0x6C616D72, 0x6D20796C, 0x726F6D65, 0x6C622079, 0x736B636F, 0x74656720, 0x73657220, 0x76657265
    .WORD 0x66206465, 0x206D6F72, 0x50414548, 0x69687720, 0x69206863, 0x6F6C2073, 0x65746163, 0x74612064
    .WORD 0x74616420, 0x65732061, 0x6E656D67, 0x3B0A2074, 0x67617020, 0x70282065, 0x20656761, 0x72646461
    .WORD 0x20737365, 0x63657073, 0x65696669, 0x73612064, 0x65737520, 0x61645F72, 0x765F6174, 0x0A202961
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6F6C620A, 0x745F6B63, 0x656C6261, 0x20200A3A
    .WORD 0x203B2020, 0x73696854, 0x20736920, 0x61206E61, 0x79617272, 0x20666F20, 0x5F58414D, 0x434F4C42
    .WORD 0x6420534B, 0x72637365, 0x6F747069, 0x0A2E7372, 0x20202020, 0x6145203B, 0x64206863, 0x72637365
    .WORD 0x6F747069, 0x61682072, 0x61203A73, 0x65726464, 0x202C7373, 0x657A6973, 0x7375202C, 0x665F6465
    .WORD 0x0A67616C, 0x20202020, 0x6F54203B, 0x206C6174, 0x657A6973, 0x414D203A, 0x4C425F58, 0x534B434F
    .WORD 0x31202A20, 0x79622032, 0x0A736574, 0x20202020, 0x4150532E, 0x4D204543, 0x425F5841, 0x4B434F4C
    .WORD 0x202A2053, 0x434F4C42, 0x45445F4B, 0x0A0A4353, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x616D203B, 0x636F6C6C, 0x7A697328, 0x3B0A2965, 0x41203B0A, 0x636F6C6C, 0x73657461, 0x6D656D20
    .WORD 0x2079726F, 0x6D6F7266, 0x65687420, 0x61656820, 0x3B0A2E70, 0x48203B0A, 0x6920776F, 0x6F772074
    .WORD 0x3A736B72, 0x31203B0A, 0x6C41202E, 0x206E6769, 0x20656874, 0x75716572, 0x65747365, 0x69732064
    .WORD 0x7420657A, 0x2038206F, 0x65747962, 0x6D282073, 0x73656B61, 0x6D656D20, 0x2079726F, 0x616E616D
    .WORD 0x656D6567, 0x6520746E, 0x65697361, 0x3B0A2972, 0x202E3220, 0x72616553, 0x74206863, 0x62206568
    .WORD 0x6B636F6C, 0x62617420, 0x6620656C, 0x6120726F, 0x65726620, 0x6C622065, 0x206B636F, 0x74616874
    .WORD 0x6C207327, 0x65677261, 0x6F6E6520, 0x0A686775, 0x2E33203B, 0x20664920, 0x6E756F66, 0x6D202C64
    .WORD 0x206B7261, 0x61207469, 0x73752073, 0x61206465, 0x7220646E, 0x72757465, 0x7469206E, 0x64612073
    .WORD 0x73657264, 0x203B0A73, 0x49202E34, 0x6F6E2066, 0x6F662074, 0x2C646E75, 0x6B736120, 0x65687420
    .WORD 0x72656B20, 0x206C656E, 0x20726F66, 0x65726F6D, 0x6D656D20, 0x2079726F, 0x20616976, 0x6B726273
    .WORD 0x73797320, 0x6C6C6163, 0x35203B0A, 0x6441202E, 0x68742064, 0x656E2065, 0x656D2077, 0x79726F6D
    .WORD 0x206F7420, 0x20656874, 0x636F6C62, 0x6174206B, 0x20656C62, 0x20646E61, 0x75746572, 0x69206E72
    .WORD 0x0A3B0A74, 0x6E49203B, 0x3A747570, 0x31522020, 0x73203D20, 0x20657A69, 0x62206E69, 0x73657479
    .WORD 0x2E652820, 0x202C2E67, 0x29303031, 0x4F203B0A, 0x75707475, 0x52203A74, 0x203D2031, 0x6E696F70
    .WORD 0x20726574, 0x61206F74, 0x636F6C6C, 0x64657461, 0x6D656D20, 0x2079726F, 0x20726F28, 0x66692030
    .WORD 0x69616620, 0x2964656C, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C616D0A, 0x3A636F6C
    .WORD 0x2020200A, 0x53203B20, 0x20657661, 0x69676572, 0x72657473, 0x65772073, 0x206C6C27, 0x20657375
    .WORD 0x206F7328, 0x64206577, 0x74276E6F, 0x726F6320, 0x74707572, 0x6C616320, 0x2772656C, 0x61762073
    .WORD 0x7365756C, 0x20200A29, 0x55502020, 0x4C204853, 0x20202052, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6153203B, 0x72206576, 0x72757465, 0x6461206E, 0x73657264, 0x20200A73, 0x200A2020, 0x3B202020
    .WORD 0x65745320, 0x3A312070, 0x696C4120, 0x73206E67, 0x20657A69, 0x6D206F74, 0x69746C75, 0x20656C70
    .WORD 0x3820666F, 0x74796220, 0x200A7365, 0x3B202020, 0x79685720, 0x614D203F, 0x4320796E, 0x20735550
    .WORD 0x6B726F77, 0x73616620, 0x20726574, 0x68746977, 0x696C6120, 0x64656E67, 0x6D656D20, 0x0A79726F
    .WORD 0x20202020, 0x7845203B, 0x6C706D61, 0x73203A65, 0x3D657A69, 0x0A303031, 0x20202020, 0x2020203B
    .WORD 0x20444441, 0x37203152, 0x20202020, 0x31203E2D, 0x200A3730, 0x3B202020, 0x41202020, 0x3020444E
    .WORD 0x46464678, 0x46464646, 0x3E2D2038, 0x34303120, 0x756D2820, 0x7069746C, 0x6F20656C, 0x29382066
    .WORD 0x2020200A, 0x44444120, 0x20315220, 0x37203152, 0x20202020, 0x20202020, 0x3B202020, 0x64644120
    .WORD 0x74203720, 0x6F72206F, 0x20646E75, 0x200A7075, 0x4C202020, 0x52202049, 0x78302032, 0x46464646
    .WORD 0x38464646, 0x20200A20, 0x4E412020, 0x31522044, 0x20315220, 0x20203252, 0x20202020, 0x20202020
    .WORD 0x6C43203B, 0x20726165, 0x65776F6C, 0x20332072, 0x73746962, 0x616D2820, 0x6D20656B, 0x69746C75
    .WORD 0x20656C70, 0x3820666F, 0x20200A29, 0x4F4D2020, 0x35522056, 0x20315220, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x3552203B, 0x61203D20, 0x6E67696C, 0x73206465, 0x20657A69, 0x672E6528, 0x31202C2E
    .WORD 0x0A293430, 0x20202020, 0x2020200A, 0x53203B20, 0x20706574, 0x53203A32, 0x63726165, 0x6F662068
    .WORD 0x20612072, 0x65657266, 0x6F6C6220, 0x69206B63, 0x6874206E, 0x61742065, 0x0A656C62, 0x20202020
    .WORD 0x6557203B, 0x206C6C27, 0x20657375, 0x61203452, 0x6E692073, 0x20786564, 0x6F746E69, 0x6F6C6220
    .WORD 0x745F6B63, 0x656C6261, 0x20302820, 0x4D206F74, 0x425F5841, 0x4B434F4C, 0x29312D53, 0x2020200A
    .WORD 0x20494C20, 0x30203452, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x61745320, 0x61207472
    .WORD 0x69662074, 0x20747372, 0x636F6C62, 0x6928206B, 0x7865646E, 0x0A293020, 0x20202020, 0x6C616D0A
    .WORD 0x5F636F6C, 0x706F6F6C, 0x20200A3A, 0x203B2020, 0x63656843, 0x6669206B, 0x27657720, 0x73206576
    .WORD 0x63726165, 0x20646568, 0x206C6C61, 0x636F6C62, 0x200A736B, 0x43202020, 0x5220504D, 0x414D2034
    .WORD 0x4C425F58, 0x534B434F, 0x20202020, 0x43203B20, 0x61706D6F, 0x69206572, 0x7865646E, 0x74697720
    .WORD 0x616D2068, 0x756D6978, 0x20200A6D, 0x47422020, 0x616D2045, 0x636F6C6C, 0x7262735F, 0x2020206B
    .WORD 0x20202020, 0x6649203B, 0x646E6920, 0x3E207865, 0x414D203D, 0x4C425F58, 0x534B434F, 0x6F6E202C
    .WORD 0x65726620, 0x6C622065, 0x206B636F, 0x6E756F66, 0x20200A64, 0x200A2020, 0x3B202020, 0x6C614320
    .WORD 0x616C7563, 0x61206574, 0x65726464, 0x6F207373, 0x68742066, 0x62207369, 0x6B636F6C, 0x64207327
    .WORD 0x72637365, 0x6F747069, 0x20200A72, 0x203B2020, 0x636F6C62, 0x61745F6B, 0x20656C62, 0x6928202B
    .WORD 0x7865646E, 0x64202A20, 0x72637365, 0x6F747069, 0x69735F72, 0x0A29657A, 0x20202020, 0x5220494C
    .WORD 0x6C622032, 0x5F6B636F, 0x6C626174, 0x20202065, 0x203B2020, 0x3D203252, 0x73616220, 0x64612065
    .WORD 0x73657264, 0x666F2073, 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x2020200A, 0x20494C20, 0x42203352
    .WORD 0x4B434F4C, 0x5345445F, 0x20202043, 0x3B202020, 0x20335220, 0x6973203D, 0x6F20657A, 0x6E6F2066
    .WORD 0x65642065, 0x69726373, 0x726F7470, 0x32312820, 0x74796220, 0x0A297365, 0x20202020, 0x204C554D
    .WORD 0x52203352, 0x33522034, 0x20202020, 0x20202020, 0x203B2020, 0x3D203352, 0x646E6920, 0x2A207865
    .WORD 0x20323120, 0x66666F28, 0x20746573, 0x6F746E69, 0x62617420, 0x0A29656C, 0x20202020, 0x20444441
    .WORD 0x52203252, 0x33522032, 0x20202020, 0x20202020, 0x203B2020, 0x3D203252, 0x6C622620, 0x5B6B636F
    .WORD 0x65646E69, 0x200A5D78, 0x0A202020, 0x20202020, 0x6843203B, 0x206B6365, 0x74206669, 0x20736968
    .WORD 0x636F6C62, 0x7369206B, 0x65726620, 0x55282065, 0x20444553, 0x67616C66, 0x30203D20, 0x20200A29
    .WORD 0x444C2020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4553555F, 0x20205D44, 0x6F4C203B
    .WORD 0x74206461, 0x26206568, 0x636F6C62, 0x6E695B6B, 0x5D786564, 0x6F6C622E, 0x755F6B63, 0x20646573
    .WORD 0x67616C66, 0x2020200A, 0x504D4320, 0x20335220, 0x20202030, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x20734920, 0x30207469, 0x72662820, 0x3F296565, 0x2020200A, 0x454E4220, 0x6C616D20, 0x5F636F6C
    .WORD 0x7478656E, 0x20202020, 0x3B202020, 0x20664920, 0x20746F6E, 0x65657266, 0x73752820, 0x2C296465
    .WORD 0x696B7320, 0x6F742070, 0x78656E20, 0x6C622074, 0x0A6B636F, 0x20202020, 0x2020200A, 0x66203B20
    .WORD 0x2E656572, 0x65684320, 0x69206B63, 0x68742066, 0x62207369, 0x6B636F6C, 0x20736920, 0x6772616C
    .WORD 0x6E652065, 0x6867756F, 0x726F6620, 0x72756F20, 0x71657220, 0x74736575, 0x2020200A, 0x57444C20
    .WORD 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x455A4953, 0x3B20205D, 0x616F4C20, 0x68742064
    .WORD 0x6C622065, 0x206B636F, 0x657A6973, 0x2020200A, 0x504D4320, 0x20335220, 0x20203552, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x20734920, 0x636F6C62, 0x6973206B, 0x3E20657A, 0x6572203D, 0x73657571
    .WORD 0x20646574, 0x657A6973, 0x20200A3F, 0x47422020, 0x616D2045, 0x636F6C6C, 0x756F665F, 0x2020646E
    .WORD 0x20202020, 0x6559203B, 0x57202173, 0x6F662065, 0x20646E75, 0x75732061, 0x62617469, 0x6220656C
    .WORD 0x6B636F6C, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x78656E5F, 0x200A3A74, 0x3B202020, 0x69685420
    .WORD 0x6C622073, 0x206B636F, 0x65207369, 0x65687469, 0x73752072, 0x6F206465, 0x6F742072, 0x6D73206F
    .WORD 0x2C6C6C61, 0x79727420, 0x78656E20, 0x6E6F2074, 0x20200A65, 0x44412020, 0x34522044, 0x20345220
    .WORD 0x20202031, 0x20202020, 0x20202020, 0x6E49203B, 0x6D657263, 0x20746E65, 0x65646E69, 0x6F742078
    .WORD 0x65686320, 0x6E206B63, 0x20747865, 0x636F6C62, 0x20200A6B, 0x20422020, 0x6C6C616D, 0x6C5F636F
    .WORD 0x20706F6F, 0x20202020, 0x20202020, 0x6F47203B, 0x63616220, 0x6F74206B, 0x61747320, 0x6F207472
    .WORD 0x6F6C2066, 0x0A0A706F, 0x6C6C616D, 0x665F636F, 0x646E756F, 0x20200A3A, 0x203B2020, 0x70657453
    .WORD 0x203A3320, 0x66206557, 0x646E756F, 0x66206120, 0x20656572, 0x636F6C62, 0x616C206B, 0x20656772
    .WORD 0x756F6E65, 0x0A216867, 0x20202020, 0x3252203B, 0x70203D20, 0x746E696F, 0x74207265, 0x6874206F
    .WORD 0x6C622065, 0x206B636F, 0x63736564, 0x74706972, 0x200A726F, 0x3B202020, 0x20335220, 0x6C62203D
    .WORD 0x206B636F, 0x657A6973, 0x65772820, 0x6E6F6420, 0x75207427, 0x69206573, 0x6F662074, 0x70732072
    .WORD 0x7474696C, 0x20676E69, 0x74206E69, 0x20736968, 0x706D6973, 0x7620656C, 0x69737265, 0x0A296E6F
    .WORD 0x20202020, 0x2020200A, 0x4D203B20, 0x206B7261, 0x20656874, 0x636F6C62, 0x7361206B, 0x65737520
    .WORD 0x55282064, 0x20444553, 0x67616C66, 0x31203D20, 0x20200A29, 0x494C2020, 0x20335220, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x3352203B, 0x31203D20, 0x73752820, 0x0A296465, 0x20202020
    .WORD 0x20575453, 0x5B203352, 0x2B203252, 0x4F4C4220, 0x555F4B43, 0x5D444553, 0x203B2020, 0x726F7453
    .WORD 0x20312065, 0x74206E69, 0x55206568, 0x20444553, 0x6C656966, 0x20200A64, 0x200A2020, 0x3B202020
    .WORD 0x74654720, 0x65687420, 0x6F6C6220, 0x73276B63, 0x61747320, 0x6E697472, 0x64612067, 0x73657264
    .WORD 0x6E612073, 0x65722064, 0x6E727574, 0x0A746920, 0x20202020, 0x2057444C, 0x5B203152, 0x2B203252
    .WORD 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x203B2020, 0x3D203152, 0x64646120, 0x73736572, 0x20666F20
    .WORD 0x73696874, 0x6F6C6220, 0x200A6B63, 0x42202020, 0x6C616D20, 0x5F636F6C, 0x656E6F64, 0x20202020
    .WORD 0x20202020, 0x4A203B20, 0x20706D75, 0x63206F74, 0x6E61656C, 0x61207075, 0x7220646E, 0x72757465
    .WORD 0x6D0A0A6E, 0x6F6C6C61, 0x62735F63, 0x0A3A6B72, 0x20202020, 0x7453203B, 0x34207065, 0x6F4E203A
    .WORD 0x65726620, 0x6C622065, 0x206B636F, 0x6E756F66, 0x6E692064, 0x62617420, 0x200A656C, 0x3B202020
    .WORD 0x6B734120, 0x65687420, 0x72656B20, 0x206C656E, 0x20726F66, 0x65726F6D, 0x6D656D20, 0x2079726F
    .WORD 0x6E697375, 0x62732067, 0x73206B72, 0x61637379, 0x200A6C6C, 0x0A202020, 0x20202020, 0x3552203B
    .WORD 0x726C6120, 0x79646165, 0x73616820, 0x65687420, 0x696C6120, 0x64656E67, 0x7A697320, 0x65772065
    .WORD 0x65656E20, 0x20200A64, 0x4F4D2020, 0x31522056, 0x20355220, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x3152203B, 0x73203D20, 0x20657A69, 0x61206F74, 0x636F6C6C, 0x0A657461, 0x20202020, 0x20435653
    .WORD 0x5F535953, 0x4B524253, 0x20202020, 0x20202020, 0x203B2020, 0x6C6C6143, 0x72656B20, 0x3A6C656E
    .WORD 0x72627320, 0x6973286B, 0x0A29657A, 0x20202020, 0x2020200A, 0x43203B20, 0x6B636568, 0x20666920
    .WORD 0x6B726273, 0x69616620, 0x2064656C, 0x74657228, 0x736E7275, 0x20312D20, 0x3020726F, 0x206E6F20
    .WORD 0x6F727265, 0x200A2972, 0x43202020, 0x5220504D, 0x20302031, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x44203B20, 0x73206469, 0x206B7262, 0x75746572, 0x30206E72, 0x20726F20, 0x6167656E, 0x65766974
    .WORD 0x20200A3F, 0x4C422020, 0x616D2054, 0x636F6C6C, 0x7272655F, 0x2020726F, 0x20202020, 0x6649203B
    .WORD 0x72726520, 0x202C726F, 0x75746572, 0x4E206E72, 0x0A4C4C55, 0x20202020, 0x2020200A, 0x53203B20
    .WORD 0x20706574, 0x73203A35, 0x206B7262, 0x63637573, 0x65646565, 0x77202C64, 0x61682065, 0x6E206576
    .WORD 0x6D207765, 0x726F6D65, 0x74612079, 0x64646120, 0x73736572, 0x206E6920, 0x200A3152, 0x3B202020
    .WORD 0x776F4E20, 0x20657720, 0x6465656E, 0x206F7420, 0x20646461, 0x73696874, 0x77656E20, 0x6F6C6220
    .WORD 0x74206B63, 0x756F206F, 0x61742072, 0x0A656C62, 0x20202020, 0x2020200A, 0x46203B20, 0x20646E69
    .WORD 0x65206E61, 0x7974706D, 0x6F6C7320, 0x6E692074, 0x65687420, 0x6F6C6220, 0x74206B63, 0x656C6261
    .WORD 0x2020200A, 0x20494C20, 0x30203452, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x61745320
    .WORD 0x61207472, 0x69662074, 0x20747372, 0x636F6C62, 0x20200A6B, 0x6D0A2020, 0x6F6C6C61, 0x64615F63
    .WORD 0x200A3A64, 0x3B202020, 0x65684320, 0x69206B63, 0x65772066, 0x20657627, 0x72616573, 0x64656863
    .WORD 0x6C6C6120, 0x6F6C6220, 0x0A736B63, 0x20202020, 0x20504D43, 0x4D203452, 0x425F5841, 0x4B434F4C
    .WORD 0x20202053, 0x200A2020, 0x42202020, 0x6D204547, 0x6F6C6C61, 0x72655F63, 0x20726F72, 0x20202020
    .WORD 0x4E203B20, 0x6D65206F, 0x20797470, 0x746F6C73, 0x73282021, 0x6C756F68, 0x74276E64, 0x70616820
    .WORD 0x296E6570, 0x2020200A, 0x20200A20, 0x203B2020, 0x20746547, 0x63736564, 0x74706972, 0x6120726F
    .WORD 0x65726464, 0x200A7373, 0x4C202020, 0x32522049, 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x2020200A
    .WORD 0x20494C20, 0x42203352, 0x4B434F4C, 0x5345445F, 0x20200A43, 0x554D2020, 0x3352204C, 0x20345220
    .WORD 0x200A3352, 0x41202020, 0x52204444, 0x32522032, 0x20335220, 0x20202020, 0x3B202020, 0x6C622620
    .WORD 0x5B6B636F, 0x65646E69, 0x5D345278, 0x2020200A, 0x20200A20, 0x203B2020, 0x63656843, 0x6669206B
    .WORD 0x69687420, 0x6C732073, 0x6920746F, 0x72662073, 0x28206565, 0x44455355, 0x616C6620, 0x203D2067
    .WORD 0x200A2930, 0x4C202020, 0x52205744, 0x525B2033, 0x202B2032, 0x434F4C42, 0x53555F4B, 0x0A5D4445
    .WORD 0x20202020, 0x20504D43, 0x30203352, 0x2020200A, 0x51454220, 0x6C616D20, 0x5F636F6C, 0x5F646461
    .WORD 0x6E756F66, 0x3B202064, 0x756F4620, 0x6120646E, 0x6D65206E, 0x20797470, 0x746F6C73, 0x20200A21
    .WORD 0x200A2020, 0x3B202020, 0x6F6C5320, 0x73692074, 0x65737520, 0x74202C64, 0x6E207972, 0x20747865
    .WORD 0x0A656E6F, 0x20202020, 0x20444441, 0x52203452, 0x0A312034, 0x20202020, 0x616D2042, 0x636F6C6C
    .WORD 0x6464615F, 0x616D0A0A, 0x636F6C6C, 0x6464615F, 0x756F665F, 0x0A3A646E, 0x20202020, 0x6557203B
    .WORD 0x756F6620, 0x6120646E, 0x6D65206E, 0x20797470, 0x746F6C73, 0x20746120, 0x200A3252, 0x3B202020
    .WORD 0x6F745320, 0x74206572, 0x6E206568, 0x62207765, 0x6B636F6C, 0x69207327, 0x726F666E, 0x6974616D
    .WORD 0x200A6E6F, 0x0A202020, 0x20202020, 0x7453203B, 0x2065726F, 0x20656874, 0x72646461, 0x20737365
    .WORD 0x20315228, 0x6D6F7266, 0x72627320, 0x200A296B, 0x53202020, 0x52205754, 0x525B2031, 0x202B2032
    .WORD 0x434F4C42, 0x44415F4B, 0x205D5244, 0x203B2020, 0x636F6C62, 0x64612E6B, 0x73657264, 0x203D2073
    .WORD 0x72646461, 0x20737365, 0x6D6F7266, 0x72627320, 0x20200A6B, 0x200A2020, 0x3B202020, 0x6F745320
    .WORD 0x74206572, 0x73206568, 0x20657A69, 0x20355228, 0x6C61203D, 0x656E6769, 0x69732064, 0x0A29657A
    .WORD 0x20202020, 0x20575453, 0x5B203552, 0x2B203252, 0x4F4C4220, 0x535F4B43, 0x5D455A49, 0x3B202020
    .WORD 0x6F6C6220, 0x732E6B63, 0x20657A69, 0x6973203D, 0x200A657A, 0x0A202020, 0x20202020, 0x614D203B
    .WORD 0x61206B72, 0x73752073, 0x28206465, 0x44455355, 0x31203D20, 0x20200A29, 0x494C2020, 0x20335220
    .WORD 0x20200A31, 0x54532020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4553555F, 0x20205D44
    .WORD 0x62203B20, 0x6B636F6C, 0x6573752E, 0x203D2064, 0x20200A31, 0x200A2020, 0x3B202020, 0x20315220
    .WORD 0x65726C61, 0x20796461, 0x20736168, 0x20656874, 0x72646461, 0x20737365, 0x6D6F7266, 0x72627320
    .WORD 0x73202C6B, 0x756A206F, 0x72207473, 0x72757465, 0x7469206E, 0x2020200A, 0x6D204220, 0x6F6C6C61
    .WORD 0x6F645F63, 0x0A0A656E, 0x6C6C616D, 0x655F636F, 0x726F7272, 0x20200A3A, 0x203B2020, 0x656D6F53
    .WORD 0x6E696874, 0x65772067, 0x7720746E, 0x676E6F72, 0x72202D20, 0x72757465, 0x554E206E, 0x28204C4C
    .WORD 0x200A2930, 0x4C202020, 0x31522049, 0x0A0A3020, 0x6C6C616D, 0x645F636F, 0x3A656E6F, 0x2020200A
    .WORD 0x504F5020, 0x20524C20, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x73655220, 0x65726F74
    .WORD 0x74657220, 0x206E7275, 0x72646461, 0x0A737365, 0x20202020, 0x20544552, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x75746552, 0x74206E72, 0x6163206F, 0x72656C6C, 0x74697720
    .WORD 0x31522068, 0x70203D20, 0x746E696F, 0x6F207265, 0x554E2072, 0x0A0A4C4C, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x7266203B, 0x70286565, 0x0A297274, 0x203B0A3B, 0x65657246, 0x72702073
    .WORD 0x6F697665, 0x796C7375, 0x6C6C6120, 0x7461636F, 0x6D206465, 0x726F6D65, 0x3B0A2E79, 0x48203B0A
    .WORD 0x6920776F, 0x6F772074, 0x3A736B72, 0x31203B0A, 0x6946202E, 0x7420646E, 0x62206568, 0x6B636F6C
    .WORD 0x73656420, 0x70697263, 0x20726F74, 0x20726F66, 0x73696874, 0x64646120, 0x73736572, 0x32203B0A
    .WORD 0x614D202E, 0x69206B72, 0x73612074, 0x65726620, 0x55282065, 0x20444553, 0x2930203D, 0x33203B0A
    .WORD 0x654D202E, 0x79726F6D, 0x20736920, 0x20776F6E, 0x69617661, 0x6C62616C, 0x6F662065, 0x75662072
    .WORD 0x65727574, 0x6C616D20, 0x20636F6C, 0x6C6C6163, 0x0A3B0A73, 0x6F4E203B, 0x203A6574, 0x73696854
    .WORD 0x6D697320, 0x20656C70, 0x73726576, 0x206E6F69, 0x73656F64, 0x544F4E20, 0x616F6320, 0x6373656C
    .WORD 0x64612065, 0x6563616A, 0x6620746E, 0x20656572, 0x636F6C62, 0x0A21736B, 0x2020203B, 0x20202020
    .WORD 0x66206F53, 0x6D676172, 0x61746E65, 0x6E6F6974, 0x6E616320, 0x63636F20, 0x6F207275, 0x20726576
    .WORD 0x656D6974, 0x0A3B0A2E, 0x6E49203B, 0x3A747570, 0x31522020, 0x70203D20, 0x746E696F, 0x74207265
    .WORD 0x656D206F, 0x79726F6D, 0x206F7420, 0x65657266, 0x72662820, 0x6D206D6F, 0x6F6C6C61, 0x3B0A2963
    .WORD 0x74754F20, 0x3A747570, 0x746F4E20, 0x676E6968, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6572660A, 0x200A3A65, 0x3B202020, 0x76615320, 0x65722065, 0x74736967, 0x0A737265, 0x20202020
    .WORD 0x48535550, 0x0A524C20, 0x20202020, 0x2020200A, 0x53203B20, 0x20706574, 0x43203A31, 0x6B636568
    .WORD 0x20666920, 0x6E696F70, 0x20726574, 0x4E207369, 0x0A4C4C55, 0x20202020, 0x20504D43, 0x30203152
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x52207349, 0x3D3D2031, 0x0A3F3020, 0x20202020
    .WORD 0x20514542, 0x65657266, 0x6E6F645F, 0x20202065, 0x20202020, 0x203B2020, 0x4E206649, 0x2C4C4C55
    .WORD 0x746F6E20, 0x676E6968, 0x206F7420, 0x65657266, 0x756A202C, 0x72207473, 0x72757465, 0x20200A6E
    .WORD 0x200A2020, 0x3B202020, 0x65745320, 0x3A322070, 0x61655320, 0x20686372, 0x20656874, 0x636F6C62
    .WORD 0x6174206B, 0x20656C62, 0x20726F66, 0x73696874, 0x64646120, 0x73736572, 0x2020200A, 0x20494C20
    .WORD 0x30203452, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x61745320, 0x61207472, 0x69662074
    .WORD 0x20747372, 0x636F6C62, 0x20200A6B, 0x660A2020, 0x5F656572, 0x706F6F6C, 0x20200A3A, 0x203B2020
    .WORD 0x63656843, 0x6669206B, 0x27657720, 0x73206576, 0x63726165, 0x20646568, 0x206C6C61, 0x636F6C62
    .WORD 0x200A736B, 0x43202020, 0x5220504D, 0x414D2034, 0x4C425F58, 0x534B434F, 0x2020200A, 0x45474220
    .WORD 0x65726620, 0x6F645F65, 0x2020656E, 0x20202020, 0x3B202020, 0x746F4E20, 0x756F6620, 0x2D20646E
    .WORD 0x6E676920, 0x2065726F, 0x756F6328, 0x6220646C, 0x6E692065, 0x696C6176, 0x6F702064, 0x65746E69
    .WORD 0x200A2972, 0x0A202020, 0x20202020, 0x6547203B, 0x65642074, 0x69726373, 0x726F7470, 0x64646120
    .WORD 0x73736572, 0x2020200A, 0x20494C20, 0x62203252, 0x6B636F6C, 0x6261745F, 0x200A656C, 0x4C202020
    .WORD 0x33522049, 0x4F4C4220, 0x445F4B43, 0x20435345, 0x20202020, 0x6C203B20, 0x74676E65, 0x666F2068
    .WORD 0x656E6F20, 0x6F6C6220, 0x64206B63, 0x72637365, 0x6F747069, 0x20200A72, 0x554D2020, 0x3352204C
    .WORD 0x20345220, 0x20203352, 0x20202020, 0x20202020, 0x3472203B, 0x6F6C6220, 0x69206B63, 0x200A7864
    .WORD 0x41202020, 0x52204444, 0x32522032, 0x20335220, 0x20202020, 0x20202020, 0x52203B20, 0x203D2032
    .WORD 0x6F6C6226, 0x695B6B63, 0x20200A5D, 0x200A2020, 0x3B202020, 0x65684320, 0x69206B63, 0x68742066
    .WORD 0x62207369, 0x6B636F6C, 0x61207327, 0x65726464, 0x6D207373, 0x68637461, 0x74207365, 0x70206568
    .WORD 0x746E696F, 0x200A7265, 0x4C202020, 0x52205744, 0x525B2033, 0x202B2032, 0x434F4C42, 0x44415F4B
    .WORD 0x205D5244, 0x52203B20, 0x203D2033, 0x6C622620, 0x5B6B636F, 0x622E5D69, 0x6B636F6C, 0x64646120
    .WORD 0x73736572, 0x2020200A, 0x504D4320, 0x20335220, 0x20203152, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x20734920, 0x73696874, 0x72756F20, 0x6F6C6220, 0x0A3F6B63, 0x20202020, 0x20514542, 0x65657266
    .WORD 0x756F665F, 0x2020646E, 0x20202020, 0x203B2020, 0x2C736559, 0x20657720, 0x6E756F66, 0x74692064
    .WORD 0x20200A21, 0x200A2020, 0x3B202020, 0x746F4E20, 0x69687420, 0x6C622073, 0x2C6B636F, 0x79727420
    .WORD 0x78656E20, 0x20200A74, 0x44412020, 0x34522044, 0x20345220, 0x20200A31, 0x20422020, 0x65657266
    .WORD 0x6F6F6C5F, 0x660A0A70, 0x5F656572, 0x6E756F66, 0x200A3A64, 0x3B202020, 0x65745320, 0x3A332070
    .WORD 0x20655720, 0x6E756F66, 0x68742064, 0x6C622065, 0x206B636F, 0x63736564, 0x74706972, 0x6120726F
    .WORD 0x32522074, 0x2020200A, 0x4D203B20, 0x206B7261, 0x61207469, 0x72662073, 0x73206565, 0x616D206F
    .WORD 0x636F6C6C, 0x6E616320, 0x65737520, 0x20746920, 0x69616761, 0x20200A6E, 0x200A2020, 0x4C202020
    .WORD 0x33522049, 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2033, 0x66282030
    .WORD 0x29656572, 0x2020200A, 0x57545320, 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x44455355
    .WORD 0x3B20205D, 0x6C622620, 0x5B6B636F, 0x752E5D69, 0x20646573, 0x0A30203D, 0x20202020, 0x2020200A
    .WORD 0x4E203B20, 0x3A45544F, 0x20655720, 0x4E206F64, 0x6320544F, 0x7261656C, 0x65687420, 0x64646120
    .WORD 0x73736572, 0x20726F20, 0x657A6973, 0x2020200A, 0x54203B20, 0x20796568, 0x79617473, 0x206E6920
    .WORD 0x20656874, 0x6C626174, 0x6E612065, 0x69772064, 0x62206C6C, 0x766F2065, 0x72777265, 0x65747469
    .WORD 0x6877206E, 0x72206E65, 0x65737565, 0x20200A64, 0x660A2020, 0x5F656572, 0x656E6F64, 0x20200A3A
    .WORD 0x203B2020, 0x61656C43, 0x7075206E, 0x646E6120, 0x74657220, 0x0A6E7275, 0x20202020, 0x20504F50
    .WORD 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616D203B
    .WORD 0x636F6C6C, 0x696E695F, 0x202D2074, 0x74696E49, 0x696C6169, 0x7420657A, 0x6D206568, 0x726F6D65
    .WORD 0x6C612079, 0x61636F6C, 0x0A726F74, 0x203B0A3B, 0x61656C43, 0x74207372, 0x65206568, 0x7269746E
    .WORD 0x6C622065, 0x206B636F, 0x6C626174, 0x6F732065, 0x6C6C6120, 0x6F6C6220, 0x20736B63, 0x20657261
    .WORD 0x6B72616D, 0x61206465, 0x72662073, 0x3B0A6565, 0x6F685320, 0x20646C75, 0x63206562, 0x656C6C61
    .WORD 0x6E6F2064, 0x61206563, 0x79732074, 0x6D657473, 0x61747320, 0x70757472, 0x66656220, 0x2065726F
    .WORD 0x6E697375, 0x616D2067, 0x636F6C6C, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C616D0A
    .WORD 0x5F636F6C, 0x74696E69, 0x20200A3A, 0x203B2020, 0x65766153, 0x67657220, 0x65747369, 0x200A7372
    .WORD 0x50202020, 0x20485355, 0x2020524C, 0x20200A20, 0x203B2020, 0x70657453, 0x203A3120, 0x61656C43
    .WORD 0x68742072, 0x6E652065, 0x65726974, 0x6F6C6220, 0x74206B63, 0x656C6261, 0x2020200A, 0x53203B20
    .WORD 0x61207465, 0x62206C6C, 0x73657479, 0x206E6920, 0x636F6C62, 0x61745F6B, 0x20656C62, 0x30206F74
    .WORD 0x2020200A, 0x20494C20, 0x62203152, 0x6B636F6C, 0x6261745F, 0x2020656C, 0x3B202020, 0x20315220
    .WORD 0x7473203D, 0x20747261, 0x72646461, 0x20737365, 0x7420666F, 0x656C6261, 0x2020200A, 0x20494C20
    .WORD 0x4D203352, 0x425F5841, 0x4B434F4C, 0x202A2053, 0x434F4C42, 0x45445F4B, 0x20204353, 0x3352203B
    .WORD 0x74203D20, 0x6C61746F, 0x74796220, 0x74207365, 0x6C63206F, 0x0A726165, 0x20202020, 0x6C616D0A
    .WORD 0x5F636F6C, 0x74696E69, 0x6F6F6C5F, 0x200A3A70, 0x43202020, 0x5220504D, 0x20302033, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x48203B20, 0x20657661, 0x63206577, 0x7261656C, 0x61206465, 0x62206C6C
    .WORD 0x73657479, 0x20200A3F, 0x45422020, 0x616D2051, 0x636F6C6C, 0x696E695F, 0x6F645F74, 0x2020656E
    .WORD 0x6559203B, 0x77202C73, 0x65722765, 0x6E6F6420, 0x20200A65, 0x200A2020, 0x4C202020, 0x32522049
    .WORD 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2032, 0x76282030, 0x65756C61
    .WORD 0x206F7420, 0x74697277, 0x200A2965, 0x53202020, 0x52204254, 0x525B2032, 0x20205D31, 0x20202020
    .WORD 0x20202020, 0x53203B20, 0x65726F74, 0x61203020, 0x75632074, 0x6E657272, 0x64612074, 0x73657264
    .WORD 0x20200A73, 0x44412020, 0x31522044, 0x20315220, 0x20202031, 0x20202020, 0x20202020, 0x6F4D203B
    .WORD 0x74206576, 0x656E206F, 0x62207478, 0x0A657479, 0x20202020, 0x20425553, 0x52203352, 0x20312033
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x72636544, 0x6E656D65, 0x79622074, 0x63206574, 0x746E756F
    .WORD 0x200A7265, 0x42202020, 0x6C616D20, 0x5F636F6C, 0x74696E69, 0x6F6F6C5F, 0x20202070, 0x43203B20
    .WORD 0x69746E6F, 0x0A65756E, 0x20202020, 0x6C616D0A, 0x5F636F6C, 0x74696E69, 0x6E6F645F, 0x200A3A65
    .WORD 0x3B202020, 0x656C4320, 0x75206E61, 0x6E612070, 0x65722064, 0x6E727574, 0x2020200A, 0x504F5020
    .WORD 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D
    .WORD 0x45544E49, 0x4C414E52, 0x4C454820, 0x53524550, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D203B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A3D3D3D, 0x6F43203B, 0x7265766E, 0x6E692074, 0x65676574, 0x6E692072, 0x74206F74, 0x6F706D65
    .WORD 0x79726172, 0x66756220, 0x0A726566, 0x203B0A3B, 0x20203952, 0x7563203D, 0x6E657272, 0x61762074
    .WORD 0x0A65756C, 0x3152203B, 0x203D2030, 0x6E696F70, 0x20726574, 0x6E206F74, 0x20747865, 0x65657266
    .WORD 0x74796220, 0x6E692065, 0x6D657420, 0x61726F70, 0x62207972, 0x65666675, 0x203B0A72, 0x20313152
    .WORD 0x6162203D, 0x28206573, 0x31202C32, 0x6F202C30, 0x36312072, 0x203B0A29, 0x20203452, 0x756E203D
    .WORD 0x7265626D, 0x20666F20, 0x69676964, 0x73207374, 0x65726F74, 0x0A3B0A64, 0x6145203B, 0x64206863
    .WORD 0x73697669, 0x206E6F69, 0x646F7270, 0x73656375, 0x0A3B0A3A, 0x2020203B, 0x746F7571, 0x746E6569
    .WORD 0x203D2020, 0x756C6176, 0x202F2065, 0x65736162, 0x20203B0A, 0x6D657220, 0x646E6961, 0x3D207265
    .WORD 0x6C617620, 0x25206575, 0x73616220, 0x0A3B0A65, 0x6854203B, 0x65722065, 0x6E69616D, 0x20726564
    .WORD 0x74207369, 0x6E206568, 0x20747865, 0x69676964, 0x3B0A2E74, 0x44203B0A, 0x74696769, 0x72612073
    .WORD 0x65672065, 0x6172656E, 0x20646574, 0x6B636162, 0x64726177, 0x66202C73, 0x6520726F, 0x706D6178
    .WORD 0x0A3A656C, 0x203B0A3B, 0x32312020, 0x0A3B0A33, 0x6966203B, 0x20747372, 0x646F7270, 0x73656375
    .WORD 0x0A3B0A3A, 0x2020203B, 0x203B0A33, 0x0A322020, 0x2020203B, 0x0A3B0A31, 0x6F73203B, 0x65687420
    .WORD 0x6D657420, 0x61726F70, 0x62207972, 0x65666675, 0x6F632072, 0x6961746E, 0x0A3A736E, 0x203B0A3B
    .WORD 0x33222020, 0x0A223132, 0x203B0A3B, 0x20656854, 0x79706F63, 0x6F6F6C20, 0x65622070, 0x20776F6C
    .WORD 0x6C6C6977, 0x76657220, 0x65737265, 0x20746920, 0x6F746E69, 0x32312220, 0x0A2E2233, 0x203B0A3B
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x616F7469, 0x726F635F, 0x203B0A65, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B0A7C, 0x20202020, 0x20202020, 0x8C94E220
    .WORD 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x94E28094
    .WORD 0x8094E2B4, 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2
    .WORD 0x3B0A9094, 0x20202020, 0x20202020, 0x94E22020, 0x20202082, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x94E22020, 0x203B0A82, 0x20202020, 0x20395220, 0x6176203D, 0x2065756C, 0x20202020
    .WORD 0x20202020, 0x31522020, 0x203D2030, 0x706D6574, 0x3B0A5D5B, 0x20202020, 0x20202020, 0x94E22020
    .WORD 0x20202082, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x94E22020, 0x203B0A82, 0x20202020
    .WORD 0x20202020, 0x9386E220, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x9386E220
    .WORD 0x20203B0A, 0x20202020, 0x56494420, 0x444F4D2F, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x0A425453, 0x2020203B, 0x20202020, 0xE2202020, 0x20208294, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0xE2202020, 0x3B0A8294, 0x20202020, 0x8C94E220, 0xE28094E2, 0x94E28094, 0x8094E280
    .WORD 0xE2B494E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x20209094, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x94E22020, 0x203B0A82, 0x20202020, 0x209386E2, 0x20202020, 0x20202020, 0x209386E2, 0x20202020
    .WORD 0x20202020, 0x20202020, 0xE2202020, 0x3B0A8294, 0x3D365220, 0x746F7571, 0x746E6569, 0x3D375220
    .WORD 0x616D6572, 0x65646E69, 0x20202072, 0x20202020, 0x0A8294E2, 0x2020203B, 0x94E22020, 0x20202082
    .WORD 0x20202020, 0x94E22020, 0x20202082, 0x20202020, 0x20202020, 0x20202020, 0x8294E220, 0x20203B0A
    .WORD 0xE2202020, 0x20208294, 0x20202020, 0xE2202020, 0x94E29494, 0x8094E280, 0x209286E2, 0x49435341
    .WORD 0x94E22049, 0x8094E280, 0xE28094E2, 0x2D2D8094, 0x0A9894E2, 0x2020203B, 0x94E22020, 0x203B0A82
    .WORD 0x20202020, 0xE29494E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x52209286, 0x6F662039, 0x656E2072
    .WORD 0x6C207478, 0x0A706F6F, 0x2038523B, 0x73656420, 0x616E6974, 0x6E6F6974, 0x696F7020, 0x7265746E
    .WORD 0x39523B0A, 0x75632020, 0x6E657272, 0x6E692074, 0x65676574, 0x61762072, 0x0A65756C, 0x3031523B
    .WORD 0x6D657420, 0x61726F70, 0x622D7972, 0x65666675, 0x6F702072, 0x65746E69, 0x523B0A72, 0x62203131
    .WORD 0x0A657361, 0x3231523B, 0x67697320, 0x6C66206E, 0x3B0A6761, 0x20203452, 0x69676964, 0x6F632074
    .WORD 0x65746E75, 0x523B0A72, 0x71202036, 0x69746F75, 0x0A746E65, 0x2037523B, 0x6D657220, 0x646E6961
    .WORD 0x3B0A7265, 0x20203552, 0x61726373, 0x20686374, 0x6964202F, 0x6F736976, 0x203B0A72, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x74690A0A
    .WORD 0x635F616F, 0x3A65726F, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x35522048
    .WORD 0x2020200A, 0x53555020, 0x36522048, 0x2020200A, 0x53555020, 0x37522048, 0x2020200A, 0x53555020
    .WORD 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x53555020, 0x31522048, 0x20200A30
    .WORD 0x55502020, 0x52204853, 0x200A3131, 0x50202020, 0x20485355, 0x20323152, 0x20200A0A, 0x4F4D2020
    .WORD 0x52202056, 0x52202038, 0x20202031, 0x20202020, 0x3B202020, 0x76615320, 0x65642065, 0x6E697473
    .WORD 0x6F697461, 0x20200A6E, 0x4F4D2020, 0x52202056, 0x52202039, 0x20202032, 0x20202020, 0x3B202020
    .WORD 0x726F5720, 0x676E696B, 0x6C617620, 0x200A6575, 0x4D202020, 0x2020564F, 0x20313152, 0x20203352
    .WORD 0x20202020, 0x20202020, 0x6142203B, 0x200A6573, 0x4D202020, 0x2020564F, 0x20323152, 0x20203452
    .WORD 0x20202020, 0x20202020, 0x6953203B, 0x66206E67, 0x0A67616C, 0x20202020, 0x6C41203B, 0x61636F6C
    .WORD 0x74206574, 0x20706D65, 0x66667562, 0x28207265, 0x657A6973, 0x73617020, 0x20646573, 0x52206E69
    .WORD 0x200A2935, 0x53202020, 0x20204255, 0x53205053, 0x35522050, 0x2020200A, 0x564F4D20, 0x31522020
    .WORD 0x50532030, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220, 0x20726566, 0x6E696F70
    .WORD 0x0A726574, 0x20200A20, 0x55502020, 0x52204853, 0x20202035, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x76617320, 0x35522065, 0x726F6620, 0x61726620, 0x6C20656D, 0x65766165, 0x2020200A, 0x53555020
    .WORD 0x38522048, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x65766173, 0x73657220, 0x20746C75
    .WORD 0x65667562, 0x20200A72, 0x200A2020, 0x3B202020, 0x65684320, 0x66206B63, 0x7320726F, 0x206E6769
    .WORD 0x20666928, 0x6E676973, 0x61206465, 0x6E20646E, 0x74616765, 0x29657669, 0x2020200A, 0x504D4320
    .WORD 0x31522020, 0x0A312032, 0x20202020, 0x20454E42, 0x6F746920, 0x6F635F61, 0x755F6572, 0x6769736E
    .WORD 0x0A64656E, 0x20202020, 0x2020200A, 0x504D4320, 0x39522020, 0x200A3020, 0x42202020, 0x20204547
    .WORD 0x616F7469, 0x726F635F, 0x6E755F65, 0x6E676973, 0x200A6465, 0x0A202020, 0x20202020, 0x654E203B
    .WORD 0x69746167, 0x6E206576, 0x65626D75, 0x202D2072, 0x20646461, 0x756E696D, 0x69732073, 0x200A6E67
    .WORD 0x4C202020, 0x20202049, 0x34203252, 0x20202035, 0x273B2020, 0x200A272D, 0x53202020, 0x20204254
    .WORD 0x5B203252, 0x0A5D3852, 0x20202020, 0x20444441, 0x20385220, 0x31203852, 0x2020200A, 0x544F4E20
    .WORD 0x39522020, 0x0A395220, 0x20202020, 0x20444441, 0x20395220, 0x31203952, 0x2020200A, 0x454E3B20
    .WORD 0x52202047, 0x20202039, 0x20202020, 0x20202020, 0x3B202020, 0x6B614D20, 0x6F702065, 0x69746973
    .WORD 0x200A6576, 0x0A202020, 0x616F7469, 0x726F635F, 0x6E755F65, 0x6E676973, 0x0A3A6465, 0x20202020
    .WORD 0x7053203B, 0x61696365, 0x6163206C, 0x203A6573, 0x6F72657A, 0x2020200A, 0x504D4320, 0x39522020
    .WORD 0x200A3020, 0x42202020, 0x2020454E, 0x616F7469, 0x726F635F, 0x6F635F65, 0x7265766E, 0x20200A74
    .WORD 0x200A2020, 0x4C202020, 0x20202049, 0x34203252, 0x20202038, 0x27203B20, 0x200A2730, 0x53202020
    .WORD 0x20204254, 0x5B203252, 0x0A5D3852, 0x20202020, 0x20444441, 0x20385220, 0x31203852, 0x2020200A
    .WORD 0x20494C20, 0x32522020, 0x200A3020, 0x53202020, 0x20204254, 0x5B203252, 0x0A5D3852, 0x20202020
    .WORD 0x20202042, 0x6F746920, 0x6F635F61, 0x665F6572, 0x73696E69, 0x690A0A68, 0x5F616F74, 0x65726F63
    .WORD 0x6E6F635F, 0x74726576, 0x200A0A3A, 0x4C202020, 0x52202049, 0x20302034, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x52203B20, 0x203D2034, 0x69676964, 0x6F632074, 0x65746E75, 0x690A0A72
    .WORD 0x5F616F74, 0x65726F63, 0x7669645F, 0x706F6F6C, 0x20200A3A, 0x203B2020, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2020200A, 0x44203B20, 0x64697669
    .WORD 0x75632065, 0x6E657272, 0x61762074, 0x2065756C, 0x62207962, 0x0A657361, 0x20202020, 0x20200A3B
    .WORD 0x203B2020, 0x20203952, 0x7563203D, 0x6E657272, 0x61762074, 0x0A65756C, 0x20202020, 0x3152203B
    .WORD 0x203D2031, 0x65736162, 0x2020200A, 0x200A3B20, 0x3B202020, 0x20655720, 0x6465656E, 0x206F7420
    .WORD 0x7065656B, 0x20395220, 0x68636E75, 0x65676E61, 0x6F662064, 0x4F4D2072, 0x73202C44, 0x7375206F
    .WORD 0x35522065, 0x2020200A, 0x61203B20, 0x68742073, 0x49442065, 0x6F732056, 0x65637275, 0x20200A2E
    .WORD 0x203B2020, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2020200A, 0x564F4D20, 0x20355220, 0x200A3952, 0x3B202020, 0x20365220, 0x7571203D, 0x6569746F
    .WORD 0x200A746E, 0x44202020, 0x52205649, 0x35522036, 0x31315220, 0x2020200A, 0x52203B20, 0x203D2037
    .WORD 0x616D6572, 0x65646E69, 0x20200A72, 0x4F4D2020, 0x37522044, 0x20395220, 0x0A313152, 0x20202020
    .WORD 0x2D2D203B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x200A2D2D
    .WORD 0x3B202020, 0x6E6F4320, 0x74726576, 0x6D657220, 0x646E6961, 0x74207265, 0x5341206F, 0x0A494943
    .WORD 0x20202020, 0x20200A3B, 0x203B2020, 0x20726F46, 0x65736162, 0x61203220, 0x3120646E, 0x200A3A30
    .WORD 0x3B202020, 0x20202020, 0x2E2E3020, 0x3E2D2039, 0x27302720, 0x39272E2E, 0x20200A27, 0x0A3B2020
    .WORD 0x20202020, 0x6F46203B, 0x61622072, 0x31206573, 0x200A3A36, 0x3B202020, 0x20202020, 0x2E2E3020
    .WORD 0x2D202039, 0x3027203E, 0x272E2E27, 0x200A2739, 0x3B202020, 0x20202020, 0x2E303120, 0x2035312E
    .WORD 0x27203E2D, 0x2E2E2741, 0x0A274627, 0x20202020, 0x2D2D203B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x200A2D2D, 0x43202020, 0x5220504D, 0x31203131, 0x20200A36
    .WORD 0x45422020, 0x74692051, 0x635F616F, 0x5F65726F, 0x5F786568, 0x69676964, 0x20200A74, 0x203B2020
    .WORD 0x65736142, 0x6F203220, 0x61622072, 0x31206573, 0x20200A30, 0x44412020, 0x37522044, 0x20375220
    .WORD 0x20203834, 0x20202020, 0x20202020, 0x3B202020, 0x27302720, 0x64202B20, 0x74696769, 0x2020200A
    .WORD 0x69204220, 0x5F616F74, 0x65726F63, 0x6F74735F, 0x0A0A6572, 0x616F7469, 0x726F635F, 0x65685F65
    .WORD 0x69645F78, 0x3A746967, 0x2020200A, 0x504D4320, 0x20375220, 0x20200A39, 0x47422020, 0x74692054
    .WORD 0x635F616F, 0x5F65726F, 0x5F786568, 0x7474656C, 0x200A7265, 0x3B202020, 0x2E2E3020, 0x20200A39
    .WORD 0x44412020, 0x37522044, 0x20375220, 0x20203834, 0x20202020, 0x20202020, 0x3B202020, 0x27302720
    .WORD 0x64202B20, 0x74696769, 0x2020200A, 0x69204220, 0x5F616F74, 0x65726F63, 0x6F74735F, 0x0A0A6572
    .WORD 0x616F7469, 0x726F635F, 0x65685F65, 0x656C5F78, 0x72657474, 0x20200A3A, 0x203B2020, 0x2E2E3031
    .WORD 0x200A3531, 0x53202020, 0x52204255, 0x37522037, 0x0A303120, 0x20202020, 0x20444441, 0x52203752
    .WORD 0x35362037, 0x20202020, 0x20202020, 0x20202020, 0x27203B20, 0x2B202741, 0x69642820, 0x20746967
    .WORD 0x3031202D, 0x3B0A0A29, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x726F7453, 0x65672065, 0x6172656E, 0x20646574, 0x69676964
    .WORD 0x203B0A74, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x74690A0A, 0x635F616F, 0x5F65726F, 0x726F7473, 0x200A3A65, 0x0A202020, 0x20202020
    .WORD 0x20425453, 0x5B203752, 0x5D303152, 0x20202020, 0x3031523B, 0x20736920, 0x20656874, 0x706D6574
    .WORD 0x7261726F, 0x75622D79, 0x72656666, 0x696F7020, 0x7265746E, 0x200A0A2E, 0x41202020, 0x52204444
    .WORD 0x52203031, 0x31203031, 0x2020200A, 0x44444120, 0x20345220, 0x31203452, 0x20202020, 0x4F203B20
    .WORD 0x6D20656E, 0x2065726F, 0x69676964, 0x65672074, 0x6172656E, 0x0A646574, 0x2020200A, 0x2D203B20
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x20202020
    .WORD 0x6854203B, 0x75712065, 0x6569746F, 0x6220746E, 0x6D6F6365, 0x74207365, 0x76206568, 0x65756C61
    .WORD 0x726F6620, 0x65687420, 0x78656E20, 0x74692074, 0x74617265, 0x2E6E6F69, 0x2020200A, 0x200A3B20
    .WORD 0x3B202020, 0x61784520, 0x656C706D, 0x20200A3A, 0x0A3B2020, 0x20202020, 0x2020203B, 0x20333231
    .WORD 0x3031202F, 0x31203D20, 0x20200A32, 0x203B2020, 0x31202020, 0x202F2032, 0x3D203031, 0x200A3120
    .WORD 0x3B202020, 0x20202020, 0x2F203120, 0x20303120, 0x0A30203D, 0x20202020, 0x2D2D203B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A0A2D2D, 0x20202020, 0x20564F4D
    .WORD 0x52203952, 0x200A0A36, 0x3B202020, 0x6E6F4320, 0x756E6974, 0x6E752065, 0x206C6974, 0x746F7571
    .WORD 0x746E6569, 0x63656220, 0x73656D6F, 0x72657A20, 0x20200A6F, 0x4D432020, 0x39522050, 0x200A3020
    .WORD 0x42202020, 0x6920454E, 0x5F616F74, 0x65726F63, 0x7669645F, 0x706F6F6C, 0x203B0A0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x44203B0A
    .WORD 0x74696769, 0x72612073, 0x6F6E2065, 0x74732077, 0x6465726F, 0x63616220, 0x7261776B, 0x69207364
    .WORD 0x6574206E, 0x726F706D, 0x20797261, 0x66667562, 0x0A2E7265, 0x6574203B, 0x3D20706D, 0x32332220
    .WORD 0x3B0A2231, 0x52203B0A, 0x70203031, 0x746E696F, 0x756A2073, 0x41207473, 0x52455446, 0x65687420
    .WORD 0x73616C20, 0x69642074, 0x2E746967, 0x3B0A3B0A, 0x766F4D20, 0x61622065, 0x74206B63, 0x6874206F
    .WORD 0x69662065, 0x206C616E, 0x69676964, 0x3B0A3A74, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x200A0A3D, 0x53202020, 0x52204255, 0x52203031
    .WORD 0x31203031, 0x203B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x43203B0A, 0x2079706F, 0x69676964, 0x66207374, 0x206D6F72, 0x706D6574
    .WORD 0x7261726F, 0x75622079, 0x72656666, 0x63616220, 0x7261776B, 0x3B0A7364, 0x3D3D3D20, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x690A0A3D, 0x5F616F74
    .WORD 0x65726F63, 0x706F635F, 0x200A3A79, 0x43202020, 0x5220504D, 0x0A302034, 0x20202020, 0x20514542
    .WORD 0x616F7469, 0x726F635F, 0x6F645F65, 0x200A656E, 0x3B202020, 0x61655220, 0x616C2064, 0x67207473
    .WORD 0x72656E65, 0x64657461, 0x67696420, 0x200A7469, 0x4C202020, 0x52204244, 0x525B2032, 0x0A5D3031
    .WORD 0x20202020, 0x7257203B, 0x20657469, 0x74207469, 0x6564206F, 0x6E697473, 0x6F697461, 0x20200A6E
    .WORD 0x54532020, 0x32522042, 0x38525B20, 0x20200A5D, 0x44412020, 0x38522044, 0x20385220, 0x20200A31
    .WORD 0x203B2020, 0x65766F4D, 0x63616220, 0x7261776B, 0x74207364, 0x756F7268, 0x74206867, 0x6F706D65
    .WORD 0x79726172, 0x66756220, 0x0A726566, 0x20202020, 0x20425553, 0x20303152, 0x20303152, 0x20200A31
    .WORD 0x203B2020, 0x20656E4F, 0x7373656C, 0x67696420, 0x200A7469, 0x53202020, 0x52204255, 0x34522034
    .WORD 0x200A3120, 0x42202020, 0x6F746920, 0x6F635F61, 0x635F6572, 0x0A79706F, 0x6F74690A, 0x6F635F61
    .WORD 0x645F6572, 0x3A656E6F, 0x2020200A, 0x20494C20, 0x32522020, 0x200A3020, 0x53202020, 0x20204254
    .WORD 0x5B203252, 0x205D3852, 0x20202020, 0x20202020, 0x754E203B, 0x74206C6C, 0x696D7265, 0x6574616E
    .WORD 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x696E6966, 0x0A3A6873, 0x20202020, 0x20504F50
    .WORD 0x20315220, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x72757465, 0x726F206E, 0x6E696769
    .WORD 0x70206C61, 0x746E696F, 0x200A7265, 0x50202020, 0x2020504F, 0x200A3552, 0x3B202020, 0x656C4320
    .WORD 0x75206E61, 0x65742070, 0x6220706D, 0x65666675, 0x20200A72, 0x44412020, 0x53202044, 0x50532050
    .WORD 0x0A355220, 0x20202020, 0x2020200A, 0x504F5020, 0x32315220, 0x2020200A, 0x504F5020, 0x31315220
    .WORD 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50
    .WORD 0x200A3852, 0x50202020, 0x5220504F, 0x20200A37, 0x4F502020, 0x36522050, 0x2020200A, 0x504F5020
    .WORD 0x0A355220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920, 0x65645F61, 0x202D2063
    .WORD 0x69636544, 0x206C616D, 0x766E6F63, 0x69737265, 0x77206E6F, 0x70706172, 0x3B0A7265, 0x52203B0A
    .WORD 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x3B0A7265, 0x20325220, 0x6973203D
    .WORD 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152, 0x69726F20
    .WORD 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x6365645F, 0x20200A3A, 0x55502020
    .WORD 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20, 0x20313120, 0x69676964, 0x2B207374
    .WORD 0x67697320, 0x202B206E, 0x6C6C756E, 0x31203D20, 0x79622033, 0x0A736574, 0x20202020, 0x2020494C
    .WORD 0x20335220, 0x20203031, 0x20202020, 0x20202020, 0x42203B20, 0x20657361, 0x200A3031, 0x4C202020
    .WORD 0x20202049, 0x31203452, 0x20202020, 0x20202020, 0x20202020, 0x6953203B, 0x64656E67, 0x2020200A
    .WORD 0x20494C20, 0x35522020, 0x20333120, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220
    .WORD 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020
    .WORD 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x20786568, 0x6548202D
    .WORD 0x65646178, 0x616D6963, 0x6F63206C, 0x7265766E, 0x6E6F6973, 0x61727720, 0x72657070, 0x3B0A3B0A
    .WORD 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032
    .WORD 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152
    .WORD 0x69726F20, 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x7865685F, 0x20200A3A
    .WORD 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20, 0x64203820, 0x74696769
    .WORD 0x202B2073, 0x6C6C756E, 0x39203D20, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x31203352
    .WORD 0x20202036, 0x20202020, 0x20202020, 0x6142203B, 0x31206573, 0x20200A36, 0x494C2020, 0x52202020
    .WORD 0x20302034, 0x20202020, 0x20202020, 0x3B202020, 0x736E5520, 0x656E6769, 0x73282064, 0x73776F68
    .WORD 0x77617220, 0x74696220, 0x200A2973, 0x4C202020, 0x20202049, 0x39203552, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072, 0x200A657A, 0x43202020, 0x204C4C41
    .WORD 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020, 0x2020504F, 0x200A524C, 0x52202020
    .WORD 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x7469203B, 0x6F5F616F, 0x2D207463, 0x74634F20, 0x63206C61, 0x65766E6F, 0x6F697372, 0x7277206E
    .WORD 0x65707061, 0x0A3B0A72, 0x3152203B, 0x64203D20, 0x69747365, 0x6974616E, 0x62206E6F, 0x65666675
    .WORD 0x203B0A72, 0x3D203252, 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x75746552
    .WORD 0x3A736E72, 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072, 0x65746E69
    .WORD 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F74690A
    .WORD 0x636F5F61, 0x200A3A74, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020, 0x20202020, 0x614D203B
    .WORD 0x32312078, 0x67696420, 0x20737469, 0x756E202B, 0x3D206C6C, 0x20333120, 0x65747962, 0x20200A73
    .WORD 0x494C2020, 0x52202020, 0x20382033, 0x20202020, 0x20202020, 0x3B202020, 0x73614220, 0x0A382065
    .WORD 0x20202020, 0x2020494C, 0x20345220, 0x20202030, 0x20202020, 0x20202020, 0x55203B20, 0x6769736E
    .WORD 0x2064656E, 0x6F687328, 0x72207377, 0x62207761, 0x29737469, 0x2020200A, 0x20494C20, 0x35522020
    .WORD 0x20333120, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220, 0x20726566, 0x657A6973
    .WORD 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020, 0x2020200A, 0x504F5020
    .WORD 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x206E6962, 0x6942202D, 0x7972616E, 0x6E6F6320
    .WORD 0x73726576, 0x206E6F69, 0x70617277, 0x0A726570, 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974
    .WORD 0x6E6F6974, 0x66756220, 0x0A726566, 0x3252203B, 0x75203D20, 0x6769736E, 0x2064656E, 0x65746E69
    .WORD 0x0A726567, 0x6552203B, 0x6E727574, 0x52203A73, 0x203D2031, 0x6769726F, 0x6C616E69, 0x66756220
    .WORD 0x20726566, 0x6E696F70, 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x3A6E6962, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x2078614D, 0x62203233, 0x20737469, 0x756E202B, 0x3D206C6C, 0x20333320
    .WORD 0x65747962, 0x20200A73, 0x494C2020, 0x52202020, 0x20322033, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x73614220, 0x0A322065, 0x20202020, 0x2020494C, 0x20345220, 0x20202030, 0x20202020, 0x20202020
    .WORD 0x55203B20, 0x6769736E, 0x2064656E, 0x6F687328, 0x72207377, 0x62207761, 0x29737469, 0x2020200A
    .WORD 0x20494C20, 0x35522020, 0x20333320, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220
    .WORD 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020
    .WORD 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x6E676973, 0x685F6465
    .WORD 0x2D207865, 0x67695320, 0x2064656E, 0x61786568, 0x69636564, 0x206C616D, 0x70617277, 0x0A726570
    .WORD 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566, 0x3252203B
    .WORD 0x73203D20, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x75746552, 0x3A736E72, 0x20315220
    .WORD 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072, 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F74690A, 0x69735F61, 0x64656E67
    .WORD 0x7865685F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20
    .WORD 0x64203820, 0x74696769, 0x202B2073, 0x6E676973, 0x6E202B20, 0x206C6C75, 0x3031203D, 0x74796220
    .WORD 0x200A7365, 0x4C202020, 0x20202049, 0x31203352, 0x20202036, 0x20202020, 0x20202020, 0x6142203B
    .WORD 0x31206573, 0x20200A36, 0x494C2020, 0x52202020, 0x20312034, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x67695320, 0x2064656E, 0x6F687328, 0x73207377, 0x296E6769, 0x2020200A, 0x20494C20, 0x35522020
    .WORD 0x20303120, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220, 0x20726566, 0x657A6973
    .WORD 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020, 0x2020200A, 0x504F5020
    .WORD 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x6E676973, 0x625F6465, 0x2D206E69, 0x67695320
    .WORD 0x2064656E, 0x616E6962, 0x77207972, 0x70706172, 0x3B0A7265, 0x52203B0A, 0x203D2031, 0x74736564
    .WORD 0x74616E69, 0x206E6F69, 0x66667562, 0x3B0A7265, 0x20325220, 0x6973203D, 0x64656E67, 0x746E6920
    .WORD 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152, 0x69726F20, 0x616E6967, 0x7562206C
    .WORD 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x6769735F, 0x5F64656E, 0x3A6E6962, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x2020200A, 0x20200A20, 0x203B2020, 0x2078614D, 0x62203233, 0x20737469, 0x6973202B
    .WORD 0x2B206E67, 0x6C756E20, 0x203D206C, 0x62203433, 0x73657479, 0x2020200A, 0x20494C20, 0x33522020
    .WORD 0x20203220, 0x20202020, 0x20202020, 0x203B2020, 0x65736142, 0x200A3220, 0x4C202020, 0x20202049
    .WORD 0x31203452, 0x20202020, 0x20202020, 0x20202020, 0x6953203B, 0x64656E67, 0x68732820, 0x2073776F
    .WORD 0x6E676973, 0x20200A29, 0x494C2020, 0x52202020, 0x34332035, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020, 0x69204C4C, 0x5F616F74
    .WORD 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52, 0x45522020, 0x3B0A0A54
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72747320, 0x28797063, 0x74736564, 0x7273202C
    .WORD 0x3B0A2963, 0x43203B0A, 0x6569706F, 0x74732073, 0x676E6972, 0x6F726620, 0x7273206D, 0x6F742063
    .WORD 0x73656420, 0x6E692074, 0x64756C63, 0x20676E69, 0x6D726574, 0x74616E69, 0x20676E69, 0x6C6C756E
    .WORD 0x61686320, 0x74636172, 0x3B0A7265, 0x49203B0A, 0x7475706E, 0x203B0A3A, 0x31522020, 0x64203D20
    .WORD 0x69747365, 0x6974616E, 0x70206E6F, 0x746E696F, 0x3B0A7265, 0x52202020, 0x203D2032, 0x72756F73
    .WORD 0x70206563, 0x746E696F, 0x3B0A7265, 0x4F203B0A, 0x75707475, 0x3B0A3A74, 0x52202020, 0x203D2031
    .WORD 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70, 0x20726574, 0x69726F28, 0x616E6967, 0x3B0A296C
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x730A2D2D, 0x70637274, 0x200A3A79, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x4D202020, 0x5220564F, 0x31522033, 0x20202020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x65766153, 0x69726F20, 0x616E6967, 0x6564206C, 0x6E697473, 0x6F697461, 0x6F70206E, 0x65746E69
    .WORD 0x20200A72, 0x4F4D2020, 0x34522056, 0x20325220, 0x20202020, 0x20202020, 0x20202020, 0x53203B20
    .WORD 0x20657661, 0x72756F73, 0x70206563, 0x746E696F, 0x200A7265, 0x0A202020, 0x63727473, 0x6C5F7970
    .WORD 0x3A706F6F, 0x2020200A, 0x42444C20, 0x20325220, 0x5D34525B, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6F4C203B, 0x62206461, 0x20657479, 0x6D6F7266, 0x756F7320, 0x0A656372, 0x20202020, 0x20425453
    .WORD 0x5B203252, 0x205D3152, 0x20202020, 0x20202020, 0x3B202020, 0x6F745320, 0x62206572, 0x20657479
    .WORD 0x64206F74, 0x69747365, 0x6974616E, 0x200A6E6F, 0x0A202020, 0x20202020, 0x20504D43, 0x30203252
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x65684320, 0x69206B63, 0x74692066, 0x6E207327
    .WORD 0x206C6C75, 0x6D726574, 0x74616E69, 0x200A726F, 0x42202020, 0x73205145, 0x70637274, 0x6F645F79
    .WORD 0x2020656E, 0x20202020, 0x203B2020, 0x7A206649, 0x2C6F7265, 0x27657720, 0x64206572, 0x0A656E6F
    .WORD 0x20202020, 0x2020200A, 0x44444120, 0x20315220, 0x31203152, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6441203B, 0x636E6176, 0x65642065, 0x6E697473, 0x6F697461, 0x6F70206E, 0x65746E69, 0x20200A72
    .WORD 0x44412020, 0x34522044, 0x20345220, 0x20202031, 0x20202020, 0x20202020, 0x41203B20, 0x6E617664
    .WORD 0x73206563, 0x6372756F, 0x6F702065, 0x65746E69, 0x20200A72, 0x20422020, 0x63727473, 0x6C5F7970
    .WORD 0x0A706F6F, 0x20202020, 0x7274730A, 0x5F797063, 0x656E6F64, 0x20200A3A, 0x4F4D2020, 0x31522056
    .WORD 0x20335220, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x72757465, 0x726F206E, 0x6E696769
    .WORD 0x64206C61, 0x69747365, 0x6974616E, 0x70206E6F, 0x746E696F, 0x200A7265, 0x50202020, 0x4C20504F
    .WORD 0x20200A52, 0x45522020, 0x0A0A0A54, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x4944203B
    .WORD 0x54434552, 0x2059524F, 0x5245504F, 0x4F495441, 0x2D20534E, 0x74614D20, 0x6E696863, 0x6F792067
    .WORD 0x6B207275, 0x656E7265, 0x2073276C, 0x66726174, 0x65725F73, 0x69646461, 0x3D3B0A72, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A0A3D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72694420
    .WORD 0x6F746365, 0x73207972, 0x63757274, 0x65727574, 0x706F2820, 0x65757161, 0x206F7420, 0x72657375
    .WORD 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x452E0A2D, 0x44205551, 0x465F5249, 0x20202C44
    .WORD 0x20202020, 0x20203020, 0x20202020, 0x46203B20, 0x20656C69, 0x63736564, 0x74706972, 0x2820726F
    .WORD 0x79622034, 0x29736574, 0x51452E0A, 0x49442055, 0x464F5F52, 0x54455346, 0x2020202C, 0x20202034
    .WORD 0x20202020, 0x7543203B, 0x6E657272, 0x6F702074, 0x69746973, 0x69206E6F, 0x6964206E, 0x74636572
    .WORD 0x2079726F, 0x65727473, 0x28206D61, 0x79622034, 0x29736574, 0x2E0A2020, 0x20555145, 0x5F524944
    .WORD 0x455A4953, 0x202C464F, 0x0A382020, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F203B0A
    .WORD 0x646E6570, 0x2D207269, 0x65704F20, 0x2061206E, 0x65726964, 0x726F7463, 0x6F662079, 0x65722072
    .WORD 0x6E696461, 0x0A3B0A67, 0x4E49203B, 0x5220203A, 0x203D2031, 0x68746170, 0x756E2820, 0x742D6C6C
    .WORD 0x696D7265, 0x6574616E, 0x74732064, 0x676E6972, 0x203B0A29, 0x3A54554F, 0x20315220, 0x4944203D
    .WORD 0x28202A52, 0x646E6168, 0x2029656C, 0x3020726F, 0x206E6F20, 0x6F727265, 0x0A3B0A72, 0x704F203B
    .WORD 0x20736E65, 0x69642061, 0x74636572, 0x2079726F, 0x656C6966, 0x646E6120, 0x74657220, 0x736E7275
    .WORD 0x68206120, 0x6C646E61, 0x6F662065, 0x65722072, 0x69646461, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x706F0A2D, 0x69646E65, 0x200A3A72, 0x50202020, 0x20485355, 0x200A524C, 0x50202020
    .WORD 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x0A202020, 0x20202020, 0x20564F4D
    .WORD 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x53203B20, 0x20657661, 0x68746170, 0x2020200A
    .WORD 0x4F203B20, 0x206E6570, 0x65726964, 0x726F7463, 0x69772079, 0x72206874, 0x2D646165, 0x796C6E6F
    .WORD 0x616C6620, 0x28207367, 0x656D6173, 0x20736120, 0x72756F79, 0x2E736C20, 0x296D7361, 0x2020200A
    .WORD 0x564F4D20, 0x20315220, 0x200A3852, 0x4C202020, 0x52202049, 0x5F4F2032, 0x4E4F4452, 0x200A594C
    .WORD 0x53202020, 0x53204356, 0x4F5F5359, 0x0A4E4550, 0x20202020, 0x20564F4D, 0x52203952, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x0A64663B, 0x20202020, 0x20504D43, 0x30203152, 0x2020200A, 0x544C4220
    .WORD 0x65706F20, 0x7269646E, 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020, 0x6C41203B, 0x61636F6C
    .WORD 0x44206574, 0x73205249, 0x63757274, 0x65727574, 0x6D732820, 0x2C6C6C61, 0x73756A20, 0x64662074
    .WORD 0x646E6120, 0x66666F20, 0x29746573, 0x2020200A, 0x53555020, 0x39522048, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x61733B20, 0x52206576, 0x696A2039, 0x20200A63, 0x494C2020, 0x20315220
    .WORD 0x5F524944, 0x455A4953, 0x200A464F, 0x43202020, 0x204C4C41, 0x6C6C616D, 0x200A636F, 0x50202020
    .WORD 0x2020504F, 0x0A0A3952, 0x20202020, 0x20504D43, 0x30203152, 0x2020200A, 0x51454220, 0x65706F20
    .WORD 0x7269646E, 0x7272655F, 0x635F726F, 0x65736F6C, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056
    .WORD 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x49442065, 0x200A2A52, 0x0A202020
    .WORD 0x20202020, 0x6E49203B, 0x61697469, 0x657A696C, 0x52494420, 0x72747320, 0x75746375, 0x200A6572
    .WORD 0x3B202020, 0x20325220, 0x6C697473, 0x6168206C, 0x64662073, 0x6F726620, 0x706F206D, 0x200A6E65
    .WORD 0x53202020, 0x52205754, 0x525B2039, 0x202B2038, 0x5F524944, 0x0A5D4446, 0x20202020, 0x2020494C
    .WORD 0x30203252, 0x2020200A, 0x57545320, 0x20325220, 0x2038525B, 0x4944202B, 0x464F5F52, 0x54455346
    .WORD 0x20200A5D, 0x200A2020, 0x4D202020, 0x5220564F, 0x38522031, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6552203B, 0x6E727574, 0x52494420, 0x20200A2A, 0x20422020, 0x6E65706F, 0x5F726964, 0x656E6F64
    .WORD 0x2020200A, 0x706F0A20, 0x69646E65, 0x72655F72, 0x5F726F72, 0x736F6C63, 0x200A3A65, 0x4D202020
    .WORD 0x5220564F, 0x39522031, 0x20202020, 0x20202020, 0x20202020, 0x6466203B, 0x20736920, 0x52206E69
    .WORD 0x20200A39, 0x56532020, 0x59532043, 0x4C435F53, 0x0A45534F, 0x20202020, 0x5220494C, 0x0A302031
    .WORD 0x20202020, 0x706F2042, 0x69646E65, 0x6F645F72, 0x200A656E, 0x0A202020, 0x6E65706F, 0x5F726964
    .WORD 0x6F727265, 0x200A3A72, 0x4C202020, 0x31522049, 0x200A3020, 0x0A202020, 0x6E65706F, 0x5F726964
    .WORD 0x656E6F64, 0x20200A3A, 0x4F502020, 0x39522050, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020
    .WORD 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x6572203B, 0x69646461, 0x202D2072, 0x64616552, 0x78656E20, 0x69642074, 0x74636572, 0x2079726F
    .WORD 0x72746E65, 0x0A3B0A79, 0x4E49203B, 0x5220203A, 0x203D2031, 0x2A524944, 0x72662820, 0x6F206D6F
    .WORD 0x646E6570, 0x0A297269, 0x2020203B, 0x52202020, 0x203D2032, 0x6E696F70, 0x20726574, 0x73206F74
    .WORD 0x63757274, 0x69642074, 0x746E6572, 0x206F7420, 0x6C6C6966, 0x4F203B0A, 0x203A5455, 0x3D203152
    .WORD 0x69203120, 0x6E652066, 0x20797274, 0x64616572, 0x2030202C, 0x6E206669, 0x6F6D206F, 0x65206572
    .WORD 0x6972746E, 0x202C7365, 0x6F20312D, 0x7265206E, 0x0A726F72, 0x203B0A3B, 0x64616552, 0x68742073
    .WORD 0x656E2065, 0x64207478, 0x63657269, 0x79726F74, 0x746E6520, 0x75207972, 0x676E6973, 0x65687420
    .WORD 0x72656B20, 0x276C656E, 0x65722073, 0x69646461, 0x69762072, 0x59532061, 0x45525F53, 0x3B0A4441
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x720A2D2D, 0x64646165, 0x0A3A7269, 0x20202020, 0x48535550
    .WORD 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x48535550, 0x0A395220, 0x20202020
    .WORD 0x2020200A, 0x564F4D20, 0x20385220, 0x20203152, 0x20202020, 0x20202020, 0x203B2020, 0x2A524944
    .WORD 0x2020200A, 0x564F4D20, 0x20395220, 0x20203252, 0x20202020, 0x20202020, 0x203B2020, 0x72657355
    .WORD 0x64207327, 0x6E657269, 0x75622074, 0x72656666, 0x2020200A, 0x20200A20, 0x203B2020, 0x63656843
    .WORD 0x6669206B, 0x52494420, 0x696F7020, 0x7265746E, 0x20736920, 0x696C6176, 0x20200A64, 0x4D432020
    .WORD 0x38522050, 0x200A3020, 0x42202020, 0x72205145, 0x64646165, 0x655F7269, 0x726F7272, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x64616552, 0x656E6F20, 0x72696420, 0x20746E65, 0x6D6F7266, 0x72696420
    .WORD 0x6F746365, 0x66207972, 0x73752064, 0x20676E69, 0x72727563, 0x20746E65, 0x7366666F, 0x200A7465
    .WORD 0x4C202020, 0x52205744, 0x525B2031, 0x202B2038, 0x5F524944, 0x205D4446, 0x6466203B, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x20657355, 0x20656874, 0x65726964, 0x726F7463, 0x20732779, 0x7366666F
    .WORD 0x2D207465, 0x20657720, 0x6465656E, 0x206F7420, 0x6C706D69, 0x6E656D65, 0x736C2074, 0x206B6565
    .WORD 0x7520726F, 0x200A6573, 0x3B202020, 0x65687420, 0x63616620, 0x68742074, 0x65207461, 0x20686361
    .WORD 0x64616572, 0x74656720, 0x6E6F2073, 0x69642065, 0x746E6572, 0x20746120, 0x69742061, 0x6620656D
    .WORD 0x206D6F72, 0x66726174, 0x20200A73, 0x4F4D2020, 0x32522056, 0x20395220, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x65737520, 0x75622072, 0x72656666, 0x2020200A, 0x20494C20, 0x20335220, 0x45524944
    .WORD 0x535F544E, 0x4F455A49, 0x203B2046, 0x657A6973, 0x20666F20, 0x20656E6F, 0x65726964, 0x200A746E
    .WORD 0x53202020, 0x53204356, 0x525F5359, 0x0A444145, 0x20202020, 0x20504D43, 0x30203152, 0x2020200A
    .WORD 0x51454220, 0x61657220, 0x72696464, 0x646E655F, 0x20202020, 0x203B2020, 0x0A464F45, 0x20202020
    .WORD 0x20504D43, 0x44203152, 0x4E455249, 0x49535F54, 0x464F455A, 0x2020200A, 0x454E4220, 0x61657220
    .WORD 0x72696464, 0x7272655F, 0x2020726F, 0x203B2020, 0x726F6853, 0x65722074, 0x6F206461, 0x72652072
    .WORD 0x0A726F72, 0x20202020, 0x2020200A, 0x45203B20, 0x7972746E, 0x61657220, 0x75732064, 0x73656363
    .WORD 0x6C756673, 0x200A796C, 0x3B202020, 0x64705520, 0x20657461, 0x20656874, 0x7366666F, 0x69207465
    .WORD 0x4944206E, 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x2057444C, 0x5B203252, 0x2B203852
    .WORD 0x52494420, 0x46464F5F, 0x5D544553, 0x2020200A, 0x44444120, 0x20325220, 0x31203252, 0x2020200A
    .WORD 0x57545320, 0x20325220, 0x2038525B, 0x4944202B, 0x464F5F52, 0x54455346, 0x20200A5D, 0x200A2020
    .WORD 0x4C202020, 0x31522049, 0x20203120, 0x20202020, 0x20202020, 0x20202020, 0x6552203B, 0x6E727574
    .WORD 0x63757320, 0x73736563, 0x2020200A, 0x72204220, 0x64646165, 0x645F7269, 0x0A656E6F, 0x20202020
    .WORD 0x6165720A, 0x72696464, 0x7272655F, 0x0A3A726F, 0x20202020, 0x5220494C, 0x312D2031, 0x2020200A
    .WORD 0x72204220, 0x64646165, 0x645F7269, 0x0A656E6F, 0x20202020, 0x6165720A, 0x72696464, 0x646E655F
    .WORD 0x20200A3A, 0x494C2020, 0x20315220, 0x20200A30, 0x720A2020, 0x64646165, 0x645F7269, 0x3A656E6F
    .WORD 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F
    .WORD 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F6C6320
    .WORD 0x69646573, 0x202D2072, 0x736F6C43, 0x69642065, 0x74636572, 0x2079726F, 0x65727473, 0x3B0A6D61
    .WORD 0x49203B0A, 0x20203A4E, 0x3D203152, 0x52494420, 0x203B0A2A, 0x3A54554F, 0x20315220, 0x2030203D
    .WORD 0x73206E6F, 0x65636375, 0x202C7373, 0x6F20312D, 0x7265206E, 0x0A726F72, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x736F6C63, 0x72696465, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52
    .WORD 0x55502020, 0x52204853, 0x20200A38, 0x200A2020, 0x4D202020, 0x5220564F, 0x31522038, 0x2020200A
    .WORD 0x504D4320, 0x20385220, 0x20200A30, 0x45422020, 0x6C632051, 0x6465736F, 0x655F7269, 0x726F7272
    .WORD 0x2020200A, 0x20200A20, 0x203B2020, 0x736F6C43, 0x68742065, 0x69642065, 0x74636572, 0x2079726F
    .WORD 0x200A6466, 0x4C202020, 0x52205744, 0x525B2031, 0x202B2038, 0x5F524944, 0x0A5D4446, 0x20202020
    .WORD 0x20435653, 0x5F535953, 0x534F4C43, 0x20200A45, 0x200A2020, 0x3B202020, 0x65724620, 0x68742065
    .WORD 0x49442065, 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x20564F4D, 0x52203152, 0x20200A38
    .WORD 0x41432020, 0x66204C4C, 0x0A656572, 0x20202020, 0x2020200A, 0x20494C20, 0x30203152, 0x2020200A
    .WORD 0x63204220, 0x65736F6C, 0x5F726964, 0x656E6F64, 0x2020200A, 0x6C630A20, 0x6465736F, 0x655F7269
    .WORD 0x726F7272, 0x20200A3A, 0x494C2020, 0x20315220, 0x200A312D, 0x0A202020, 0x736F6C63, 0x72696465
    .WORD 0x6E6F645F, 0x200A3A65, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A
    .WORD 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x69776572, 0x6964646E
    .WORD 0x202D2072, 0x65736552, 0x69642074, 0x74636572, 0x2079726F, 0x65727473, 0x74206D61, 0x6562206F
    .WORD 0x6E6E6967, 0x0A676E69, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x4944203D, 0x3B0A2A52, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x720A2D2D, 0x6E697765, 0x72696464, 0x20200A3A, 0x4D432020, 0x31522050
    .WORD 0x200A3020, 0x42202020, 0x72205145, 0x6E697765, 0x72696464, 0x6E6F645F, 0x20200A65, 0x200A2020
    .WORD 0x4C202020, 0x32522049, 0x200A3020, 0x53202020, 0x52205754, 0x525B2032, 0x202B2031, 0x5F524944
    .WORD 0x5346464F, 0x0A5D5445, 0x20202020, 0x2020200A, 0x4E203B20, 0x20646565, 0x73206F74, 0x206B6565
    .WORD 0x62206F74, 0x6E696765, 0x676E696E, 0x20666F20, 0x65726964, 0x726F7463, 0x20200A79, 0x203B2020
    .WORD 0x20726F46, 0x66726174, 0x74202C73, 0x20736968, 0x6E61656D, 0x6C632073, 0x6E69736F, 0x6E612067
    .WORD 0x65722064, 0x6E65706F, 0x2C676E69, 0x20726F20, 0x6E697375, 0x736C2067, 0x0A6B6565, 0x20202020
    .WORD 0x6953203B, 0x656C706D, 0x70706120, 0x63616F72, 0x63203A68, 0x65736F6C, 0x646E6120, 0x6F657220
    .WORD 0x0A6E6570, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020
    .WORD 0x2020200A, 0x564F4D20, 0x20385220, 0x200A3152, 0x3B202020, 0x76615320, 0x68742065, 0x61702065
    .WORD 0x2D206874, 0x20657720, 0x276E6F64, 0x61682074, 0x69206576, 0x74732074, 0x6465726F, 0x6F73202C
    .WORD 0x69687420, 0x73692073, 0x69727420, 0x0A796B63, 0x20202020, 0x6E49203B, 0x72206120, 0x206C6165
    .WORD 0x6C706D69, 0x6E656D65, 0x69746174, 0x202C6E6F, 0x726F7473, 0x61702065, 0x69206874, 0x4944206E
    .WORD 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x2020200A, 0x46203B20, 0x6E20726F, 0x202C776F
    .WORD 0x7473756A, 0x73657220, 0x6F207465, 0x65736666, 0x6E612074, 0x65722064, 0x6F20796C, 0x6572206E
    .WORD 0x69646461, 0x20732772, 0x61686562, 0x726F6976, 0x2020200A, 0x20200A20, 0x4F502020, 0x38522050
    .WORD 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x7765720A, 0x64646E69, 0x645F7269, 0x3A656E6F
    .WORD 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x66726964
    .WORD 0x202D2064, 0x20746547, 0x656C6966, 0x73656420, 0x70697263, 0x20726F74, 0x6D6F7266, 0x52494420
    .WORD 0x0A3B0A2A, 0x4E49203B, 0x5220203A, 0x203D2031, 0x2A524944, 0x4F203B0A, 0x203A5455, 0x3D203152
    .WORD 0x6C696620, 0x65642065, 0x69726373, 0x726F7470, 0x726F202C, 0x20312D20, 0x65206E6F, 0x726F7272
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x7269640A, 0x0A3A6466, 0x20202020, 0x20504D43
    .WORD 0x30203152, 0x2020200A, 0x51454220, 0x72696420, 0x655F6466, 0x726F7272, 0x2020200A, 0x20200A20
    .WORD 0x444C2020, 0x31522057, 0x31525B20, 0x44202B20, 0x465F5249, 0x200A5D44, 0x52202020, 0x200A5445
    .WORD 0x0A202020, 0x66726964, 0x72655F64, 0x3A726F72, 0x2020200A, 0x20494C20, 0x2D203152, 0x20200A31
    .WORD 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6C654820, 0x3A726570
    .WORD 0x5F736920, 0x20726964, 0x6843202D, 0x206B6365, 0x61206669, 0x74617020, 0x73692068, 0x64206120
    .WORD 0x63657269, 0x79726F74, 0x3B0A3B0A, 0x3A4E4920, 0x31522020, 0x70203D20, 0x0A687461, 0x554F203B
    .WORD 0x52203A54, 0x203D2031, 0x66692031, 0x72696420, 0x6F746365, 0x202C7972, 0x66692030, 0x746F6E20
    .WORD 0x312D202C, 0x206E6F20, 0x6F727265, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x73690A2D
    .WORD 0x7269645F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x79725420
    .WORD 0x206F7420, 0x6E65706F, 0x20736120, 0x65726964, 0x726F7463, 0x20200A79, 0x41432020, 0x6F204C4C
    .WORD 0x646E6570, 0x200A7269, 0x43202020, 0x5220504D, 0x0A302031, 0x20202020, 0x20514542, 0x645F7369
    .WORD 0x6E5F7269, 0x645F746F, 0x200A7269, 0x0A202020, 0x20202020, 0x7449203B, 0x65706F20, 0x2064656E
    .WORD 0x61207361, 0x72696420, 0x6F746365, 0x200A7972, 0x4D202020, 0x5220564F, 0x31522032, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6153203B, 0x44206576, 0x0A2A5249, 0x20202020, 0x5220494C, 0x20312031
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x72757465, 0x7274206E, 0x200A6575, 0x43202020
    .WORD 0x204C4C41, 0x736F6C63, 0x72696465, 0x20202020, 0x20202020, 0x6C43203B, 0x2065736F, 0x200A7469
    .WORD 0x42202020, 0x5F736920, 0x5F726964, 0x656E6F64, 0x2020200A, 0x73690A20, 0x7269645F, 0x746F6E5F
    .WORD 0x7269645F, 0x20200A3A, 0x494C2020, 0x20315220, 0x20200A30, 0x690A2020, 0x69645F73, 0x6F645F72
    .WORD 0x0A3A656E, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x7845203B, 0x6C706D61, 0x73752065, 0x20656761, 0x636E7566, 0x6E6F6974
    .WORD 0x6C202D20, 0x20747369, 0x65726964, 0x726F7463, 0x6F632079, 0x6E65746E, 0x28207374, 0x656B696C
    .WORD 0x29736C20, 0x54203B0A, 0x20736968, 0x6F6D6564, 0x7274736E, 0x73657461, 0x776F6820, 0x206F7420
    .WORD 0x20657375, 0x6E65706F, 0x2F726964, 0x64616572, 0x2F726964, 0x736F6C63, 0x72696465, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x73696C0A, 0x69645F74, 0x74636572, 0x3A79726F, 0x2020200A
    .WORD 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048
    .WORD 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x74617020, 0x20200A68, 0x200A2020, 0x3B202020, 0x6C6C4120, 0x7461636F, 0x69642065, 0x746E6572
    .WORD 0x206E6F20, 0x63617473, 0x20200A6B, 0x55532020, 0x50532042, 0x20505320, 0x45524944, 0x535F544E
    .WORD 0x4F455A49, 0x20200A46, 0x4F4D2020, 0x39522056, 0x0A505320, 0x20202020, 0x2020200A, 0x4F203B20
    .WORD 0x206E6570, 0x65726964, 0x726F7463, 0x20200A79, 0x4F4D2020, 0x31522056, 0x0A385220, 0x20202020
    .WORD 0x4C4C4143, 0x65706F20, 0x7269646E, 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30, 0x45422020
    .WORD 0x696C2051, 0x645F7473, 0x655F7269, 0x726F7272, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056
    .WORD 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x52494420, 0x20200A2A, 0x6C0A2020, 0x5F747369
    .WORD 0x5F726964, 0x706F6F6C, 0x20200A3A, 0x4F4D2020, 0x31522056, 0x0A385220, 0x20202020, 0x20564F4D
    .WORD 0x52203252, 0x20200A39, 0x41432020, 0x72204C4C, 0x64646165, 0x200A7269, 0x43202020, 0x5220504D
    .WORD 0x0A302031, 0x20202020, 0x20514542, 0x7473696C, 0x7269645F, 0x6F6C635F, 0x200A6573, 0x4C202020
    .WORD 0x52202049, 0x312D2032, 0x2020200A, 0x504D4320, 0x20315220, 0x200A3252, 0x42202020, 0x6C205145
    .WORD 0x5F747369, 0x5F726964, 0x6F727265, 0x20200A72, 0x200A2020, 0x3B202020, 0x69725020, 0x7420746E
    .WORD 0x6E206568, 0x0A656D61, 0x20202020, 0x20444441, 0x52203152, 0x49442039, 0x544E4552, 0x4D414E5F
    .WORD 0x20200A45, 0x41432020, 0x70204C4C, 0x0A737475, 0x20202020, 0x2020200A, 0x49203B20, 0x74692066
    .WORD 0x61207327, 0x72696420, 0x6F746365, 0x202C7972, 0x6E697270, 0x2F272074, 0x20200A27, 0x444C2020
    .WORD 0x32522057, 0x39525B20, 0x44202B20, 0x4E455249, 0x59545F54, 0x0A5D4550, 0x20202020, 0x20504D43
    .WORD 0x44203252, 0x49445F54, 0x20200A52, 0x4E422020, 0x696C2045, 0x645F7473, 0x6E5F7269, 0x645F746F
    .WORD 0x200A7269, 0x0A202020, 0x20202020, 0x5220494C, 0x6C732031, 0x5F687361, 0x72616863, 0x2020200A
    .WORD 0x4C414320, 0x7570204C, 0x61686374, 0x20200A72, 0x6C0A2020, 0x5F747369, 0x5F726964, 0x5F746F6E
    .WORD 0x3A726964, 0x2020200A, 0x20494C20, 0x6E203152, 0x696C7765, 0x635F656E, 0x0A726168, 0x20202020
    .WORD 0x4C4C4143, 0x74757020, 0x72616863, 0x2020200A, 0x20200A20, 0x20422020, 0x7473696C, 0x7269645F
    .WORD 0x6F6F6C5F, 0x20200A70, 0x6C0A2020, 0x5F747369, 0x5F726964, 0x736F6C63, 0x200A3A65, 0x4D202020
    .WORD 0x5220564F, 0x38522031, 0x2020200A, 0x4C414320, 0x6C63204C, 0x6465736F, 0x200A7269, 0x4C202020
    .WORD 0x31522049, 0x200A3020, 0x42202020, 0x73696C20, 0x69645F74, 0x6F645F72, 0x200A656E, 0x0A202020
    .WORD 0x7473696C, 0x7269645F, 0x7272655F, 0x0A3A726F, 0x20202020, 0x5220494C, 0x312D2031, 0x2020200A
    .WORD 0x696C0A20, 0x645F7473, 0x645F7269, 0x3A656E6F, 0x2020200A, 0x44444120, 0x20505320, 0x44205053
    .WORD 0x4E455249, 0x49535F54, 0x464F455A, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50
    .WORD 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x74614420, 0x65532061, 0x6F697463, 0x2D3B0A6E, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6C730A2D, 0x5F687361, 0x72616863, 0x20200A3A, 0x572E2020, 0x2044524F, 0x20203734
    .WORD 0x20202020, 0x272F273B, 0x77656E0A, 0x656E696C, 0x6168635F, 0x200A3A72, 0x2E202020, 0x44524F57
    .WORD 0x0A303120, 0x41203B0A, 0x6D756772, 0x73746E65, 0x65726120, 0x73617020, 0x20646573, 0x52206E69
    .WORD 0x522E2E32, 0x28203231, 0x74207075, 0x3131206F, 0x3B0A2E29, 0x74754F20, 0x20747570, 0x77207369
    .WORD 0x74746972, 0x69206E65, 0x64656D6D, 0x65746169, 0x203B796C, 0x69206F6E, 0x7265746E, 0x206C616E
    .WORD 0x66667562, 0x6E697265, 0x3B0A2E67, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x726F6620, 0x2074616D
    .WORD 0x69727473, 0x3B0A676E, 0x54554F20, 0x3152203A, 0x6E203D20, 0x65626D75, 0x666F2072, 0x61686320
    .WORD 0x74636172, 0x20737265, 0x74697277, 0x206E6574, 0x74706F28, 0x616E6F69, 0x63202C6C, 0x62206E61
    .WORD 0x67692065, 0x65726F6E, 0x3B0A2964, 0x61737520, 0x0A3A6567, 0x2020203B, 0x6E697270, 0x22286674
    .WORD 0x6C6C6548, 0x7325206F, 0x756E202C, 0x7265626D, 0x2C64253D, 0x78656820, 0x2C78253D, 0x61686320
    .WORD 0x63253D72, 0x2C226E5C, 0x6F772220, 0x22646C72, 0x3234202C, 0x3532202C, 0x27202C35, 0x0A292741
    .WORD 0x2020203B, 0x3233524B, 0x203B0A3A, 0x494C2020, 0x20315220, 0x5F746D66, 0x0A727473, 0x2020203B
    .WORD 0x5220494C, 0x32342032, 0x20203B0A, 0x20494C20, 0x68203352, 0x6F6C6C65, 0x7274735F, 0x20203B0A
    .WORD 0x204C4220, 0x6E697270, 0x3B0A6674, 0x0A2E2E2E, 0x746D663B, 0x7274735F, 0x412E203A, 0x49494353
    .WORD 0x4E22205A, 0x65626D75, 0x25203A72, 0x53202C64, 0x6E697274, 0x25203A67, 0x226E5C73, 0x65683B0A
    .WORD 0x5F6F6C6C, 0x3A727473, 0x53412E20, 0x5A494943, 0x6F772220, 0x22646C72, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6E697270
    .WORD 0x2D206674, 0x726F4620, 0x7474616D, 0x6F206465, 0x75707475, 0x6F742074, 0x64747320, 0x0A74756F
    .WORD 0x203B0A3B, 0x70707553, 0x6574726F, 0x6F632064, 0x7265766E, 0x6E6F6973, 0x3B0A3A73, 0x25202020
    .WORD 0x20202025, 0x6C202020, 0x72657469, 0x27206C61, 0x3B0A2725, 0x25202020, 0x20202073, 0x73202020
    .WORD 0x6E697274, 0x63282067, 0x2A726168, 0x203B0A29, 0x64252020, 0x25202F20, 0x69732069, 0x64656E67
    .WORD 0x63656420, 0x6C616D69, 0x20203B0A, 0x20782520, 0x20202020, 0x736E7520, 0x656E6769, 0x65682064
    .WORD 0x65646178, 0x616D6963, 0x6C28206C, 0x7265776F, 0x65736163, 0x203B0A29, 0x63252020, 0x20202020
    .WORD 0x69732020, 0x656C676E, 0x61686320, 0x74636172, 0x3B0A7265, 0x25202020, 0x20202062, 0x75202020
    .WORD 0x6769736E, 0x2064656E, 0x616E6962, 0x3B0A7972, 0x25202020, 0x2020206F, 0x75202020, 0x6769736E
    .WORD 0x2064656E, 0x6174636F, 0x0A3B0A6C, 0x7241203B, 0x656D7567, 0x3A73746E, 0x2E325220, 0x3231522E
    .WORD 0x69662820, 0x20747372, 0x2C293131, 0x65687420, 0x6E6F206E, 0x61747320, 0x28206B63, 0x6C6C6163
    .WORD 0x80E27265, 0x73757091, 0x29646568, 0x2D3B0A2E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72700A2D
    .WORD 0x66746E69, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38
    .WORD 0x55502020, 0x52204853, 0x20200A39, 0x55502020, 0x52204853, 0x200A3031, 0x50202020, 0x20485355
    .WORD 0x0A313152, 0x20202020, 0x48535550, 0x32315220, 0x20200A0A, 0x55532020, 0x50532042, 0x20505320
    .WORD 0x20203038, 0x20202020, 0x20202020, 0x20202020, 0x6F6C203B, 0x206C6163, 0x6D617266, 0x34203A65
    .WORD 0x202B2034, 0x2B203433, 0x64617020, 0x676E6964, 0x20200A0A, 0x203B2020, 0x65766153, 0x2E325220
    .WORD 0x3231522E, 0x206F7420, 0x61636F6C, 0x7261206C, 0x0A796172, 0x20202020, 0x20575453, 0x5B203252
    .WORD 0x2B205053, 0x0A5D3020, 0x20202020, 0x20575453, 0x5B203352, 0x2B205053, 0x0A5D3420, 0x20202020
    .WORD 0x20575453, 0x5B203452, 0x2B205053, 0x0A5D3820, 0x20202020, 0x20575453, 0x5B203552, 0x2B205053
    .WORD 0x5D323120, 0x2020200A, 0x57545320, 0x20365220, 0x2050535B, 0x3631202B, 0x20200A5D, 0x54532020
    .WORD 0x37522057, 0x50535B20, 0x32202B20, 0x200A5D30, 0x53202020, 0x52205754, 0x535B2038, 0x202B2050
    .WORD 0x0A5D3432, 0x20202020, 0x20575453, 0x5B203952, 0x2B205053, 0x5D383220, 0x2020200A, 0x57545320
    .WORD 0x30315220, 0x50535B20, 0x33202B20, 0x200A5D32, 0x53202020, 0x52205754, 0x5B203131, 0x2B205053
    .WORD 0x5D363320, 0x2020200A, 0x57545320, 0x32315220, 0x50535B20, 0x34202B20, 0x0A0A5D30, 0x20202020
    .WORD 0x20564F4D, 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x6D726F66
    .WORD 0x70207461, 0x746E696F, 0x200A7265, 0x4C202020, 0x52202049, 0x20302039, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x61203B20, 0x6D756772, 0x20746E65, 0x65646E69, 0x200A0A78, 0x4D202020
    .WORD 0x5220564F, 0x53203031, 0x20202050, 0x20202020, 0x20202020, 0x20202020, 0x62203B20, 0x20657361
    .WORD 0x7320666F, 0x64657661, 0x67657220, 0x65747369, 0x200A7372, 0x41202020, 0x52204444, 0x53203131
    .WORD 0x34342050, 0x20202020, 0x20202020, 0x20202020, 0x63203B20, 0x65766E6F, 0x6F697372, 0x7562206E
    .WORD 0x72656666, 0x72700A0A, 0x66746E69, 0x6F6F6C5F, 0x200A3A70, 0x4C202020, 0x52204244, 0x525B2031
    .WORD 0x20205D38, 0x3B202020, 0x64616572, 0x746D6620, 0x72747320, 0x20676E69, 0x72616863, 0x2020200A
    .WORD 0x504D4320, 0x20315220, 0x20200A30, 0x45422020, 0x72702051, 0x66746E69, 0x6E6F645F, 0x200A0A65
    .WORD 0x43202020, 0x5220504D, 0x37332031, 0x3B202020, 0x63656863, 0x6F66206B, 0x25272072, 0x20200A27
    .WORD 0x4E422020, 0x72702045, 0x66746E69, 0x726F6E5F, 0x5F6C616D, 0x72616863, 0x20200A0A, 0x44412020
    .WORD 0x38522044, 0x20385220, 0x203B2031, 0x20737469, 0x25272061, 0x6D202C27, 0x2065766F, 0x6E206F74
    .WORD 0x20747865, 0x72616863, 0x726F6620, 0x65707320, 0x69666963, 0x200A7265, 0x4C202020, 0x52204244
    .WORD 0x525B2032, 0x200A5D38, 0x43202020, 0x5220504D, 0x0A302032, 0x20202020, 0x20514542, 0x6E697270
    .WORD 0x645F6674, 0x0A656E6F, 0x2020200A, 0x504D4320, 0x20325220, 0x20203733, 0x63203B20, 0x6B636568
    .WORD 0x726F6620, 0x25252720, 0x20200A27, 0x45422020, 0x72702051, 0x66746E69, 0x7265705F, 0x746E6563
    .WORD 0x2020200A, 0x504D4320, 0x20325220, 0x20353131, 0x63203B20, 0x6B636568, 0x726F6620, 0x73252720
    .WORD 0x20200A27, 0x45422020, 0x72702051, 0x66746E69, 0x7274735F, 0x0A676E69, 0x20202020, 0x20504D43
    .WORD 0x31203252, 0x20203030, 0x6568633B, 0x66206B63, 0x2720726F, 0x0A276425, 0x20202020, 0x20514542
    .WORD 0x6E697270, 0x695F6674, 0x200A746E, 0x43202020, 0x5220504D, 0x30312032, 0x3B202035, 0x63656863
    .WORD 0x6F66206B, 0x25272072, 0x200A2769, 0x42202020, 0x70205145, 0x746E6972, 0x6E695F66, 0x20200A74
    .WORD 0x4D432020, 0x32522050, 0x30323120, 0x633B2020, 0x6B636568, 0x726F6620, 0x78252720, 0x20200A27
    .WORD 0x45422020, 0x72702051, 0x66746E69, 0x7865685F, 0x2020200A, 0x504D4320, 0x20325220, 0x20203939
    .WORD 0x68633B20, 0x206B6365, 0x20726F66, 0x27632527, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E
    .WORD 0x72616863, 0x2020200A, 0x504D4320, 0x20325220, 0x20203839, 0x68633B20, 0x206B6365, 0x20726F66
    .WORD 0x27622527, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E, 0x0A6E6962, 0x20202020, 0x20504D43
    .WORD 0x31203252, 0x20203131, 0x6568633B, 0x66206B63, 0x2720726F, 0x0A276F25, 0x20202020, 0x20514542
    .WORD 0x6E697270, 0x6F5F6674, 0x0A0A7463, 0x20202020, 0x6E75203B, 0x776F6E6B, 0x7073206E, 0x66696365
    .WORD 0x0A726569, 0x20202020, 0x2020494C, 0x33203152, 0x20202037, 0x6B6E753B, 0x6E776F6E, 0x65707320
    .WORD 0x69666963, 0x202C7265, 0x6E697270, 0x25272074, 0x20200A27, 0x41432020, 0x70204C4C, 0x68637475
    .WORD 0x200A7261, 0x4D202020, 0x5220564F, 0x32522031, 0x3B202020, 0x69727020, 0x7420746E, 0x75206568
    .WORD 0x6F6E6B6E, 0x73206E77, 0x69636570, 0x72656966, 0x61686320, 0x20200A72, 0x41432020, 0x70204C4C
    .WORD 0x68637475, 0x200A7261, 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66, 0x6E69746E, 0x0A0A6575
    .WORD 0x6E697270, 0x6E5F6674, 0x616D726F, 0x68635F6C, 0x0A3A7261, 0x20202020, 0x4C4C4143, 0x74757020
    .WORD 0x72616863, 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A
    .WORD 0x66746E69, 0x7265705F, 0x746E6563, 0x20200A3A, 0x494C2020, 0x31522020, 0x20373320, 0x703B2020
    .WORD 0x746E6972, 0x27252720, 0x2020200A, 0x4C414320, 0x7570204C, 0x61686374, 0x20200A72, 0x20422020
    .WORD 0x72702020, 0x66746E69, 0x6E6F635F, 0x756E6974, 0x3B0A0A65, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x67724120, 0x6E656D75, 0x65662074, 0x20686374, 0x706C6568, 0x20737265, 0x6D617328
    .WORD 0x73612065, 0x66656220, 0x2965726F, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x65665F0A
    .WORD 0x5F686374, 0x5F677261, 0x0A3A3172, 0x20202020, 0x48535550, 0x20524C20, 0x2020200A, 0x53555020
    .WORD 0x33522048, 0x2020200A, 0x4C414320, 0x675F204C, 0x615F7465, 0x615F6772, 0x65726464, 0x200A7373
    .WORD 0x4C202020, 0x52205744, 0x525B2031, 0x200A5D33, 0x50202020, 0x5220504F, 0x20200A33, 0x4F502020
    .WORD 0x524C2050, 0x2020200A, 0x54455220, 0x665F0A0A, 0x68637465, 0x6772615F, 0x3A32725F, 0x2020200A
    .WORD 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x33522048, 0x2020200A, 0x4C414320, 0x675F204C
    .WORD 0x615F7465, 0x615F6772, 0x65726464, 0x200A7373, 0x4C202020, 0x52205744, 0x525B2032, 0x200A5D33
    .WORD 0x50202020, 0x5220504F, 0x20200A33, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x675F0A0A
    .WORD 0x615F7465, 0x615F6772, 0x65726464, 0x203A7373, 0x203B2020, 0x63746566, 0x68742068, 0x64612065
    .WORD 0x73657264, 0x666F2073, 0x65687420, 0x78656E20, 0x72612074, 0x656D7567, 0x6220746E, 0x64657361
    .WORD 0x206E6F20, 0x28203952, 0x20677261, 0x65646E69, 0x200A2978, 0x43202020, 0x5220504D, 0x31312039
    .WORD 0x20202020, 0x3B202020, 0x20666920, 0x20677261, 0x65646E69, 0x3D3E2078, 0x2C313120, 0x27746920
    .WORD 0x6E6F2073, 0x65687420, 0x61747320, 0x200A6B63, 0x42202020, 0x5F20544C, 0x5F677261, 0x725F6E69
    .WORD 0x0A736765, 0x20202020, 0x20425553, 0x52203352, 0x31312039, 0x20202020, 0x3352203B, 0x6E203D20
    .WORD 0x65626D75, 0x666F2072, 0x74786520, 0x61206172, 0x20736772, 0x73206E6F, 0x6B636174, 0x2020200A
    .WORD 0x20494C20, 0x20345220, 0x20200A34, 0x554D2020, 0x3352204C, 0x20335220, 0x200A3452, 0x41202020
    .WORD 0x52204444, 0x50532033, 0x20335220, 0x3B202020, 0x20335220, 0x6461203D, 0x73657264, 0x666F2073
    .WORD 0x72696620, 0x65207473, 0x61727478, 0x67726120, 0x206E6F20, 0x63617473, 0x6E28206B, 0x7320746F
    .WORD 0x20657275, 0x74206669, 0x20736968, 0x63207369, 0x6572726F, 0x0A297463, 0x20202020, 0x20444441
    .WORD 0x52203352, 0x30312033, 0x20202034, 0x666F203B, 0x74657366, 0x206F7420, 0x6C6C6163, 0x73277265
    .WORD 0x72696620, 0x65207473, 0x61727478, 0x67726120, 0x34303120, 0x20200A20, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x693B2020, 0x68742073, 0x69732065, 0x6F20657A, 0x68742066, 0x6F6C2065
    .WORD 0x206C6163, 0x6D617266, 0x38282065, 0x2B202930, 0x76617320, 0x72206465, 0x73696765, 0x73726574
    .WORD 0x34342820, 0x20200A29, 0x45522020, 0x5F0A0A54, 0x5F677261, 0x725F6E69, 0x3A736765, 0x20202020
    .WORD 0x3B202020, 0x74656620, 0x61206863, 0x6D756772, 0x20746E65, 0x6D6F7266, 0x2E325220, 0x3231522E
    .WORD 0x73616220, 0x6F206465, 0x3952206E, 0x2020200A, 0x20494C20, 0x20345220, 0x20202034, 0x20202020
    .WORD 0x20200A20, 0x554D2020, 0x3352204C, 0x20395220, 0x20203452, 0x203B2020, 0x3D203952, 0x67726120
    .WORD 0x646E6920, 0x202C7865, 0x20335228, 0x666F203D, 0x74657366, 0x206E6920, 0x65747962, 0x200A2973
    .WORD 0x41202020, 0x52204444, 0x31522033, 0x33522030, 0x3B202020, 0x20335220, 0x6461203D, 0x73657264
    .WORD 0x666F2073, 0x76617320, 0x72206465, 0x73696765, 0x20726574, 0x6C206E69, 0x6C61636F, 0x72726120
    .WORD 0x202C7961, 0x20303152, 0x6162203D, 0x6F206573, 0x61732066, 0x20646576, 0x69676572, 0x72657473
    .WORD 0x20200A73, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x65705320
    .WORD 0x69666963, 0x68207265, 0x6C646E61, 0x0A737265, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x6E697270, 0x735F6674, 0x6E697274, 0x200A3A67, 0x43202020, 0x204C4C41, 0x7465665F, 0x615F6863
    .WORD 0x725F6772, 0x3B202031, 0x20746567, 0x69727473, 0x7020676E, 0x746E696F, 0x66207265, 0x206D6F72
    .WORD 0x200A3152, 0x41202020, 0x52204444, 0x39522039, 0x200A3120, 0x43202020, 0x204C4C41, 0x6972705F
    .WORD 0x735F746E, 0x6E697274, 0x3B202067, 0x6E697270, 0x68742074, 0x74732065, 0x676E6972, 0x2020200A
    .WORD 0x20204220, 0x69727020, 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69, 0x746E695F
    .WORD 0x20200A3A, 0x41432020, 0x5F204C4C, 0x63746566, 0x72615F68, 0x32725F67, 0x673B2020, 0x69207465
    .WORD 0x6765746E, 0x70207265, 0x66207274, 0x206D6F72, 0x200A3252, 0x0A202020, 0x20202020, 0x20564F4D
    .WORD 0x52203152, 0x20202032, 0x20202020, 0x20202020, 0x6E6F633B, 0x74726576, 0x6D756E20, 0x20726562
    .WORD 0x6D6F7266, 0x72747320, 0x20676E69, 0x6D726F66, 0x63207461, 0x7420646D, 0x6E69206F, 0x65676574
    .WORD 0x6D282072, 0x62207961, 0x69732065, 0x6465676E, 0x20200A29, 0x41432020, 0x61204C4C, 0x0A696F74
    .WORD 0x20202020, 0x20564F4D, 0x52203252, 0x200A2031, 0x0A202020, 0x20202020, 0x20444441, 0x52203952
    .WORD 0x0A312039, 0x20202020, 0x20564F4D, 0x52203152, 0x20203131, 0x20202020, 0x20202020, 0x3172203B
    .WORD 0x73692031, 0x65687420, 0x6E6F6320, 0x73726576, 0x206E6F69, 0x66667562, 0x28207265, 0x73206E6F
    .WORD 0x6B636174, 0x20200A29, 0x41432020, 0x5F204C4C, 0x6E697270, 0x756E5F74, 0x7265626D, 0x703B2020
    .WORD 0x746E6972, 0x65687420, 0x746E6920, 0x72656765, 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E
    .WORD 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69, 0x7865685F, 0x20200A3A, 0x41432020, 0x5F204C4C
    .WORD 0x63746566, 0x72615F68, 0x32725F67, 0x20200A0A, 0x4F4D2020, 0x31522056, 0x20325220, 0x20202020
    .WORD 0x20202020, 0x633B2020, 0x65766E6F, 0x6E207472, 0x65626D75, 0x72662072, 0x73206D6F, 0x6E697274
    .WORD 0x6F662067, 0x74616D72, 0x646D6320, 0x206F7420, 0x65746E69, 0x20726567, 0x79616D28, 0x20656220
    .WORD 0x676E6973, 0x0A296465, 0x20202020, 0x4C4C4143, 0x6F746120, 0x20200A69, 0x4F4D2020, 0x32522056
    .WORD 0x0A315220, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x2020200A, 0x564F4D20, 0x20315220
    .WORD 0x20313152, 0x20202020, 0x20202020, 0x72203B20, 0x69203131, 0x68742073, 0x6F632065, 0x7265766E
    .WORD 0x6E6F6973, 0x66756220, 0x20726566, 0x206E6F28, 0x63617473, 0x6120296B, 0x7320646E, 0x6E6F206F
    .WORD 0x726F6620, 0x68746F20, 0x63207265, 0x65766E6F, 0x6F697372, 0x6820736E, 0x65706C65, 0x2E2E7372
    .WORD 0x2020200A, 0x4C414320, 0x705F204C, 0x746E6972, 0x7865685F, 0x2020200A, 0x20204220, 0x69727020
    .WORD 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69, 0x6168635F, 0x200A3A72, 0x43202020
    .WORD 0x204C4C41, 0x7465665F, 0x615F6863, 0x725F6772, 0x20200A31, 0x444C2020, 0x31522062, 0x31525B20
    .WORD 0x2020205D, 0x20202020, 0x673B2020, 0x63207465, 0x20726168, 0x69207962, 0x70207374, 0x200A7274
    .WORD 0x41202020, 0x52204444, 0x39522039, 0x200A3120, 0x43202020, 0x204C4C41, 0x63747570, 0x0A726168
    .WORD 0x20202020, 0x20202042, 0x6E697270, 0x635F6674, 0x69746E6F, 0x0A65756E, 0x6972700A, 0x5F66746E
    .WORD 0x3A6E6962, 0x2020200A, 0x4C414320, 0x665F204C, 0x68637465, 0x6772615F, 0x0A32725F, 0x20202020
    .WORD 0x2020200A, 0x564F4D20, 0x20315220, 0x20203252, 0x20202020, 0x20202020, 0x6F633B20, 0x7265766E
    .WORD 0x756E2074, 0x7265626D, 0x6F726620, 0x7473206D, 0x676E6972, 0x726F6620, 0x2074616D, 0x20646D63
    .WORD 0x69206F74, 0x6765746E, 0x28207265, 0x2079616D, 0x73206562, 0x65676E69, 0x200A2964, 0x43202020
    .WORD 0x204C4C41, 0x696F7461, 0x2020200A, 0x564F4D20, 0x20325220, 0x0A0A3152, 0x20202020, 0x20444441
    .WORD 0x52203952, 0x0A312039, 0x20202020, 0x20564F4D, 0x52203152, 0x200A3131, 0x43202020, 0x204C4C41
    .WORD 0x6972705F, 0x625F746E, 0x200A6E69, 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66, 0x6E69746E
    .WORD 0x0A0A6575, 0x6E697270, 0x6F5F6674, 0x0A3A7463, 0x20202020, 0x4C4C4143, 0x65665F20, 0x5F686374
    .WORD 0x5F677261, 0x0A0A3272, 0x20202020, 0x20564F4D, 0x52203152, 0x20202032, 0x20202020, 0x20202020
    .WORD 0x6E6F633B, 0x74726576, 0x6D756E20, 0x20726562, 0x6D6F7266, 0x72747320, 0x20676E69, 0x6D726F66
    .WORD 0x63207461, 0x7420646D, 0x6E69206F, 0x65676574, 0x6D282072, 0x62207961, 0x69732065, 0x6465676E
    .WORD 0x20200A29, 0x41432020, 0x61204C4C, 0x0A696F74, 0x20202020, 0x20564F4D, 0x52203252, 0x200A0A31
    .WORD 0x41202020, 0x52204444, 0x39522039, 0x200A3120, 0x4D202020, 0x5220564F, 0x31522031, 0x20200A31
    .WORD 0x41432020, 0x5F204C4C, 0x6E697270, 0x636F5F74, 0x20200A74, 0x20422020, 0x72702020, 0x66746E69
    .WORD 0x6E6F635F, 0x756E6974, 0x700A0A65, 0x746E6972, 0x6F635F66, 0x6E69746E, 0x203A6575, 0x3B202020
    .WORD 0x63206F74, 0x69746E6F, 0x2065756E, 0x636F7270, 0x69737365, 0x6620676E, 0x616D726F, 0x74732074
    .WORD 0x676E6972, 0x2020200A, 0x44444120, 0x20385220, 0x31203852, 0x2020200A, 0x20204220, 0x69727020
    .WORD 0x5F66746E, 0x706F6F6C, 0x72700A0A, 0x66746E69, 0x6E6F645F, 0x200A3A65, 0x41202020, 0x53204444
    .WORD 0x50532050, 0x0A303820, 0x20202020, 0x20504F50, 0x0A323152, 0x20202020, 0x20504F50, 0x0A313152
    .WORD 0x20202020, 0x20504F50, 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F
    .WORD 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x203B0A2D, 0x6972705F, 0x735F746E, 0x6E697274, 0x202D2067, 0x74697257, 0x20612065
    .WORD 0x6C6C756E, 0x749180E2, 0x696D7265, 0x6574616E, 0x74732064, 0x676E6972, 0x206F7420, 0x6F647473
    .WORD 0x28207475, 0x6E206F6E, 0x696C7765, 0x0A29656E, 0x203B0A3B, 0x73657355, 0x65687420, 0x62696C20
    .WORD 0x77602063, 0x65746972, 0x72772060, 0x65707061, 0x66282072, 0x62202C64, 0x65666675, 0x6C202C72
    .WORD 0x20296E65, 0x74736E69, 0x20646165, 0x6420666F, 0x63657269, 0x56532074, 0x3B0A2E43, 0x49203B0A
    .WORD 0x20203A4E, 0x3D203152, 0x696F7020, 0x7265746E, 0x206F7420, 0x69727473, 0x3B0A676E, 0x54554F20
    .WORD 0x6F6E203A, 0x3B0A656E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F0A2D2D, 0x6E697270, 0x74735F74
    .WORD 0x676E6972, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38
    .WORD 0x55502020, 0x52204853, 0x20200A39, 0x4F4D2020, 0x38522056, 0x0A315220, 0x20202020, 0x4C4C4143
    .WORD 0x72747320, 0x206E656C, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x3D203152, 0x6E656C20
    .WORD 0x0A687467, 0x20202020, 0x20564F4D, 0x52203952, 0x20200A31, 0x494C2020, 0x31522020, 0x44545320
    .WORD 0x5F54554F, 0x200A4446, 0x4D202020, 0x5220564F, 0x38522032, 0x2020200A, 0x564F4D20, 0x20335220
    .WORD 0x200A3952, 0x43202020, 0x204C4C41, 0x74697277, 0x20202065, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6C203B20, 0x20636269, 0x70617277, 0x2C726570, 0x746F6E20, 0x72696420, 0x20746365, 0x0A435653
    .WORD 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050
    .WORD 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72705F20
    .WORD 0x5F746E69, 0x626D756E, 0x2D207265, 0x726F4620, 0x2074616D, 0x20646E61, 0x6E697270, 0x20612074
    .WORD 0x6E676973, 0x69206465, 0x6765746E, 0x28207265, 0x73657375, 0x6F746920, 0x65645F61, 0x3B0A2963
    .WORD 0x49203B0A, 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x20726566
    .WORD 0x73756D28, 0x65622074, 0xA589E220, 0x62203331, 0x73657479, 0x203B0A29, 0x20202020, 0x20325220
    .WORD 0x6973203D, 0x64656E67, 0x746E6920, 0x72656765, 0x4F203B0A, 0x203A5455, 0x656E6F6E, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A, 0x5F746E69, 0x626D756E, 0x0A3A7265, 0x20202020
    .WORD 0x48535550, 0x0A524C20, 0x20202020, 0x4C4C4143, 0x6F746920, 0x65645F61, 0x20202063, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x73657375, 0x20315220, 0x66756228, 0x29726566, 0x646E6120, 0x20325220
    .WORD 0x6C617628, 0x0A296575, 0x20202020, 0x20564F4D, 0x52203152, 0x20202031, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x73203152, 0x6C6C6974, 0x696F7020, 0x2073746E, 0x62206F74, 0x65666675
    .WORD 0x74732072, 0x0A747261, 0x20202020, 0x4C4C4143, 0x72705F20, 0x5F746E69, 0x69727473, 0x200A676E
    .WORD 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x72705F20, 0x5F746E69, 0x20786568, 0x6F46202D, 0x74616D72, 0x646E6120, 0x69727020
    .WORD 0x6120746E, 0x6E75206E, 0x6E676973, 0x69206465, 0x6765746E, 0x69207265, 0x6568206E, 0x75282078
    .WORD 0x20736573, 0x616F7469, 0x7865685F, 0x0A3B0A29, 0x4E49203B, 0x5220203A, 0x203D2031, 0x74736564
    .WORD 0x74616E69, 0x206E6F69, 0x66667562, 0x28207265, 0x7473756D, 0x20656220, 0x39A589E2, 0x74796220
    .WORD 0x0A297365, 0x2020203B, 0x52202020, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765
    .WORD 0x4F203B0A, 0x203A5455, 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A
    .WORD 0x5F746E69, 0x3A786568, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x4C414320, 0x7469204C
    .WORD 0x685F616F, 0x200A7865, 0x4D202020, 0x5220564F, 0x31522031, 0x2020200A, 0x4C414320, 0x705F204C
    .WORD 0x746E6972, 0x7274735F, 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x705F203B, 0x746E6972, 0x7865685F, 0x46202D20
    .WORD 0x616D726F, 0x6E612074, 0x72702064, 0x20746E69, 0x75206E61, 0x6769736E, 0x2064656E, 0x65746E69
    .WORD 0x20726567, 0x68206E69, 0x28207865, 0x73657375, 0x6F746920, 0x65685F61, 0x3B0A2978, 0x49203B0A
    .WORD 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x20726566, 0x73756D28
    .WORD 0x65622074, 0xA589E220, 0x79622039, 0x29736574, 0x20203B0A, 0x20202020, 0x3D203252, 0x736E7520
    .WORD 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x3A54554F, 0x6E6F6E20, 0x2D3B0A65, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x705F0A2D, 0x746E6972, 0x6E69625F, 0x20200A3A, 0x55502020, 0x4C204853
    .WORD 0x20200A52, 0x41432020, 0x69204C4C, 0x5F616F74, 0x0A6E6962, 0x20202020, 0x20564F4D, 0x52203152
    .WORD 0x20200A31, 0x41432020, 0x5F204C4C, 0x6E697270, 0x74735F74, 0x676E6972, 0x2020200A, 0x504F5020
    .WORD 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F203B0A
    .WORD 0x6E697270, 0x636F5F74, 0x202D2074, 0x6D726F46, 0x61207461, 0x7020646E, 0x746E6972, 0x206E6120
    .WORD 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x206E6920, 0x6174636F, 0x7528206C, 0x20736573
    .WORD 0x616F7469, 0x74636F5F, 0x0A3B0A29, 0x4E49203B, 0x5220203A, 0x203D2031, 0x74736564, 0x74616E69
    .WORD 0x206E6F69, 0x66667562, 0x28207265, 0x7473756D, 0x20656220, 0x39A589E2, 0x74796220, 0x0A297365
    .WORD 0x2020203B, 0x52202020, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x4F203B0A
    .WORD 0x203A5455, 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A, 0x5F746E69
    .WORD 0x3A74636F, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x4C414320, 0x7469204C, 0x6F5F616F
    .WORD 0x200A7463, 0x4D202020, 0x5220564F, 0x31522031, 0x2020200A, 0x4C414320, 0x705F204C, 0x746E6972
    .WORD 0x7274735F, 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x3D3D3D3B
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x6144203B, 0x53206174, 0x69746365, 0x3B0A6E6F, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x730A3D3D, 0x65636170, 0x7274735F, 0x20200A3A, 0x412E2020, 0x49494353
    .WORD 0x2022205A, 0x6E0A0A22, 0x696C7765, 0x735F656E, 0x0A3A7274, 0x20202020, 0x4353412E, 0x205A4949
    .WORD 0x226E5C22, 0x68630A0A, 0x6675625F, 0x20200A3A, 0x412E2020, 0x49494353, 0x5C22205A, 0x0A0A2230
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7461203B, 0x3B0A696F, 0x43203B0A, 0x65766E6F
    .WORD 0x64207472, 0x6D696365, 0x41206C61, 0x49494353, 0x72747320, 0x20676E69, 0x73206F74, 0x656E6769
    .WORD 0x6E692064, 0x65676574, 0x3B0A2E72, 0x49203B0A, 0x3B0A3A4E, 0x52202020, 0x203D2031, 0x69727473
    .WORD 0x7020676E, 0x746E696F, 0x3B0A7265, 0x4F203B0A, 0x0A3A5455, 0x2020203B, 0x3D203152, 0x746E6920
    .WORD 0x72656765, 0x3B0A3B0A, 0x70755320, 0x74726F70, 0x3B0A3A73, 0x22202020, 0x22333231, 0x20203B0A
    .WORD 0x312D2220, 0x0A223332, 0x2020203B, 0x0A223022, 0x203B0A3B, 0x696E694D, 0x206C616D, 0x3233524B
    .WORD 0x706D6920, 0x656D656C, 0x7461746E, 0x2E6E6F69, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x74610A0A, 0x0A3A696F, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220
    .WORD 0x20202020, 0x48535550, 0x0A395220, 0x20202020, 0x48535550, 0x30315220, 0x20200A0A, 0x4F4D2020
    .WORD 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x52203B20, 0x203D2038, 0x69727473, 0x200A676E
    .WORD 0x4C202020, 0x52202049, 0x20302039, 0x20202020, 0x20202020, 0x203B2020, 0x3D203952, 0x73657220
    .WORD 0x0A746C75, 0x20202020, 0x2020494C, 0x20303152, 0x20202030, 0x20202020, 0x3B202020, 0x30315220
    .WORD 0x6E203D20, 0x74616765, 0x20657669, 0x67616C66, 0x20200A0A, 0x203B2020, 0x63656843, 0x2D27206B
    .WORD 0x20200A27, 0x444C2020, 0x32522042, 0x38525B20, 0x20200A5D, 0x4D432020, 0x32522050, 0x20353420
    .WORD 0x20202020, 0x20202020, 0x27203B20, 0x200A272D, 0x42202020, 0x6120454E, 0x5F696F74, 0x706F6F6C
    .WORD 0x2020200A, 0x20494C20, 0x20303152, 0x20200A31, 0x44412020, 0x38522044, 0x20385220, 0x74610A31
    .WORD 0x6C5F696F, 0x3A706F6F, 0x2020200A, 0x42444C20, 0x20325220, 0x5D38525B, 0x2020200A, 0x65203B20
    .WORD 0x6F20646E, 0x74732066, 0x676E6972, 0x2020200A, 0x504D4320, 0x20325220, 0x20200A30, 0x45422020
    .WORD 0x74612051, 0x645F696F, 0x0A656E6F, 0x20202020, 0x6E6F203B, 0x6120796C, 0x70656363, 0x30272074
    .WORD 0x272E2E27, 0x200A2739, 0x43202020, 0x5220504D, 0x38342032, 0x20202020, 0x3B202020, 0x27302720
    .WORD 0x2020200A, 0x544C4220, 0x6F746120, 0x6F645F69, 0x200A656E, 0x43202020, 0x5220504D, 0x37352032
    .WORD 0x20202020, 0x3B202020, 0x27392720, 0x2020200A, 0x54474220, 0x6F746120, 0x6F645F69, 0x0A0A656E
    .WORD 0x20202020, 0x6964203B, 0x20746967, 0x6863203D, 0x2D207261, 0x27302720, 0x2020200A, 0x42555320
    .WORD 0x20325220, 0x34203252, 0x200A0A38, 0x3B202020, 0x73657220, 0x20746C75, 0x6572203D, 0x746C7573
    .WORD 0x31202A20, 0x202B2030, 0x69676964, 0x20200A74, 0x494C2020, 0x33522020, 0x0A303120, 0x20202020
    .WORD 0x204C554D, 0x52203952, 0x33522039, 0x2020200A, 0x44444120, 0x20395220, 0x52203952, 0x20200A32
    .WORD 0x44412020, 0x38522044, 0x20385220, 0x20200A31, 0x20422020, 0x696F7461, 0x6F6F6C5F, 0x74610A70
    .WORD 0x645F696F, 0x3A656E6F, 0x2020200A, 0x504D4320, 0x30315220, 0x200A3120, 0x42202020, 0x6120454E
    .WORD 0x5F696F74, 0x69736F70, 0x65766974, 0x2020200A, 0x6E203B20, 0x74616765, 0x454E2065, 0x293D2047
    .WORD 0x2020200A, 0x544F4E20, 0x20395220, 0x200A3952, 0x41202020, 0x52204444, 0x39522039, 0x610A3120
    .WORD 0x5F696F74, 0x69736F70, 0x65766974, 0x20200A3A, 0x4F4D2020, 0x31522056, 0x0A395220, 0x20202020
    .WORD 0x20504F50, 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38
    .WORD 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

    .SPACE 1024
tarfs_end:
