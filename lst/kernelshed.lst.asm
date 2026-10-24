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
.EQU ERR_EXIST,       -17      ; already exists
.EQU ERR_DONT_EXIST,  -18      ; dont exists
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

;-------------------------------------------------------------
; FILES create etc
;-------------------------------------------------------------

.EQU ERR_NAMETOOLONG, -33    ;supplied pathname is toolong

.org 0x0000
0x00000000   B KERNEL_START

; KERNEL NAME LEVEL - "BitFrosty" (Norse small rainbow bridge - introducing BMI)

.EQU PTE_R,       0x0001    ;RD perm
.EQU PTE_W,       0x0002    ;WR perm
.EQU PTE_X,       0x0004    ;EXEC perm
.EQU PTE_U,       0x0008    ;USER mode only
.EQU PTE_P,       0x0010    ;Privileged mode
.EQU PTE_G,       0x0020    ;G bit - PTE is not flushed when switch happens (OS related)

.EQU KERNEL_FLAGS,     0x0037    ; P|R|W|X|G, supervisor-only shared mapping  GP-XWR
.EQU USER_RX,          0x001D    ; P|R|X|U  ;                                 -PUX-R
.EQU USER_RW,          0x001B    ; P|R|W|U  ;                                 -PU-WR ; used for load image to memory in execve
.EQU KERN_USER_RX,     0x003D    ; P|R|X|U|G, shared executable (kernel can   GPUX-R ; fetch user code); not used
.EQU KERNEL_USER_ALL,  0x001F    ; P|R|W|X|U,per-task user executable mapping -PUXWR ;needed for execve kenrel executes loaded code

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
.EQU KERNEL_BASE,      0x00000000
.EQU KERNEL_LIMIT,     0x0003DFFF
.EQU KERNEL_STACK_TOP, 0x0003E000

.EQU USER_BASE,        0x0003E000
.EQU USER_LIMIT,       0x0005FFFF

.EQU USER_STACK_VA,    0x0003F000
.EQU USER_STACK_TOP,   0x00040000
.EQU USER_DATA_VA,     0x00042000  ; start of user data page for task (process virtual space) 4 KiB per task (form heap memory)
.EQU USER_CODE_VA,     0x00043000  ; fixed user code VA for execve-loaded user image
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
0x00001008       ENABLEINT

idle_loop:
0x0000100C       ADD R1 R1 1


    ;DEBUG 10
0x00001010       B idle_loop

nsfs_bootstrap_ns0:
0x00001018       PUSH LR
    ;------------------------------------------------------
    ; Bootstrap the mutable root layout in namespace 0.
    ; This keeps NS0 usable for runtime data while leaving the
    ; read-only tarfs tree in place.
    ;
    ; R1 = opcode
    ; R2 = payload pointer
    ; R3 = payload length
    ; R4 = namespace

0x0000101C       MOV R1 NS_DELETE
0x00001020       LI R2 0x00000000
0x00001028       MOV R3 R2
0x0000102C       MOV R4 R2
0x00001030   CALL bmi_call

0x00001038       MOV R1 NS_CREATE
0x0000103C       LI R2 0x00000000
0x00001044       MOV R3 R2
0x00001048       MOV R4 R2
0x0000104C   CALL bmi_call

0x00001054       MOV R1 DIR_CREATE
0x00001058       LI R2 nsfs_tmp_dir
0x00001060       LI R3 4
0x00001068       LI R4 0
0x00001070   CALL bmi_call

0x00001078       MOV R1 DIR_CREATE
0x0000107C       LI R2 nsfs_var_dir
0x00001084       LI R3 4
0x0000108C       LI R4 0
0x00001094   CALL bmi_call

0x0000109C       MOV R1 DIR_CREATE
0x000010A0       LI R2 nsfs_var_tmp_dir
0x000010A8       LI R3 8
0x000010B0       LI R4 0
0x000010B8   CALL bmi_call

0x000010C0       MOV R1 DIR_CREATE
0x000010C4       LI R2 nsfs_var_run_dir
0x000010CC       LI R3 8
0x000010D4       LI R4 0
0x000010DC   CALL bmi_call

0x000010E4       MOV R1 DIR_CREATE
0x000010E8       LI R2 nsfs_home_dir
0x000010F0       LI R3 5
0x000010F8       LI R4 0
0x00001100   CALL bmi_call

0x00001108       POP LR
0x0000110C       RET

nsfs_tmp_dir:
    .asciiz "/tmp"

nsfs_var_dir:
    .asciiz "/var"

nsfs_var_tmp_dir:
    .asciiz "/var/tmp"

nsfs_var_run_dir:
    .asciiz "/var/run"

nsfs_home_dir:
    .asciiz "/home"

.org 0x2000

; ================================================================
; KERNEL CODE (starts at 0x2000)
; ================================================================
; Do not use `func` here: its prologue pushes FP before SP is initialized.
KERNEL_START:
0x00002000           LI SP KERNEL_STACK_TOP
0x00002008           MOV FP SP

        ; Initialize unified IDT (all traps go to trap_entry)
0x0000200C   CALL init_idt

        ; Initialize Page Tables
        ; check memory_map.txt for current layout
0x00002014   CALL init_page_tables

        ; Init_task_scheduler (hard-coded)
0x0000201C   CALL init_scheduler

        ; Initialize MMIO devices (PIC, PIT, UART)
0x00002024   CALL init_mmio_devices

        ; Bootstrap the writable namespace root once during boot so the
        ; host log shows the initial NS0 layout before user init starts.
0x0000202C   CALL nsfs_bootstrap_ns0
0x00002034           LI R1 NSFS_DEFAULT_NS
0x0000203C   CALL nsfs_refresh_index

        ;init console mutex
0x00002044   CALL init_console_mutex

        ; Mount the built-in read-only TAR archive and show its index.
0x0000204C           LI R1 tarfs_start
0x00002054           LI R2 tarfs_end
0x0000205C           SUB R2 R2 R1
0x00002060   CALL tarfs_init
0x00002068   CALL tarfs_dump_index
0x00002070   CALL tarfs_dump_dir_index


        ;test read dirs from tarfs probably needs to be removed later
0x00002078           LI R1 etc_path
0x00002080   CALL tarfs_readdir1

0x00002088           LI R1 bin_path
0x00002090   CALL tarfs_readdir1

        ; Activate the first dynamically created address space before
        ; enabling translation and restoring its initial trapframe.
0x00002098           LI R1 tasks
0x000020A0           LDW R2 [R1 + TASK_PTBR]
0x000020A4           SETPTBR R2
0x000020A8           LDW SP [R1 + TASK_KSP]

        ; Enable MMU and interrupts
0x000020AC   CALL enable_vm

        ; Start first task through the same trapframe restore path used
        ; by preemptive switches.
        ; jump to task0 entry point (0x5000) through the same trap restore
0x000020B4           B trap_restore

; ================================================================
; Initialize console mutex at boot time
; ================================================================

init_console_mutex:
0x000020BC       PUSH LR
0x000020C0       LI R1 console_mutex
0x000020C8       BL mutex_init
0x000020D0       POP LR
0x000020D4       RET

; ================================================================
; Initialize IDT - ALL TRAPS GO TO ONE ENTRY
; ================================================================

init_idt:
0x000020D8       LI R1 0x00200000           ; IDT base physical address

    ; Only entry 0 matters - all traps go here
0x000020E0       LI R2 trap_entry
0x000020E8       STW R2 [R1]                ; IDT[0] = trap_entry

    ; Optional: fill other entries with same handler for safety
0x000020EC       LI R2 trap_entry
0x000020F4       STW R2 [R1+4]                ; IDT[1]
0x000020F8       STW R2 [R1+8]                ; IDT[2]
0x000020FC       STW R2 [R1+12]               ; IDT[3]
0x00002100       STW R2 [R1+24]               ; IDT[6]
0x00002104       STW R2 [R1+64]               ; IDT[16]
    ; set IDT root register
0x00002108       SETIDTR R1
0x0000210C       RET


; ================================================================
; Initialize Page Tables
; ================================================================

init_page_tables0:
0x00002110       PUSH LR

    ; Page tables are created by task_create. Boot only initializes the
    ; physical-page allocator before the scheduler starts allocating tasks.
0x00002114       LI R1 page_bitmap
0x0000211C       LI R3 16
0x00002124       BL mem_zero

0x0000212C       POP LR
0x00002130       RET

; ================================================================
; Initialize Page Tables
; used in Memory manager for user space
; ================================================================

init_page_tables:
0x00002134       PUSH LR
    ; Clear the refcount array
0x00002138       LI R1 page_refcounts
0x00002140       LI R3 MAX_PHYS_PAGES          ; 128 bytes = 128 pages: 1 byte for ea page (4k)
0x00002148       BL mem_zero                   ; 0 - free, 1 - allocated
0x00002150       POP LR
0x00002154       RET

; ================================================================
; Map common kernel pages into the given page table
; (PTBR in R1)
; ================================================================

map_common_kernel:
0x00002158       PUSH LR
0x0000215C       PUSH R12

    ;====================================================
    ; Kernel code and static data from boot.
    ;====================================================
0x00002160       LI R12 0x00000000       ;pages 0 - boot (0000)
0x00002168       LI R7  0x00015000       ;till 21 - last kernel (14FFF)

map_common_kernel_loop:
0x00002170       CMP R12 R7
0x00002174       BGE map_common_kernel_done
0x0000217C       MOV R2 R12
0x00002180       MOV R3 R12
0x00002184       LI R4 KERNEL_FLAGS
0x0000218C       BL map_page
0x00002194       LI R6 PAGE_SIZE
0x0000219C       ADD R12 R12 R6
0x000021A0       B map_common_kernel_loop
map_common_kernel_done:

    ;====================================
    ; BMI buffers + reg base
    ;====================================

0x000021A8       LI R2 0x00015000      ; page for BMI buffers for NSFS (write) - 4K each
0x000021B0       LI R3 0x00015000
0x000021B8       LI R4 KERNEL_FLAGS
0x000021C0       BL map_page

0x000021C8       LI R2 0x00016000      ; page for BMI buffers for NSFS (read) - 4K each
0x000021D0       LI R3 0x00016000
0x000021D8       LI R4 KERNEL_FLAGS
0x000021E0       BL map_page

0x000021E8       LI R2 0x00017000      ; page for MMIO BMI_REG_BASE Map for NSFS  - 4K each
0x000021F0       LI R3 0x00017000
0x000021F8       LI R4 KERNEL_FLAGS
0x00002200       BL map_page

    ; Map MMIO pages (UART, Timer/PIT, and PIC) into kernel address space
0x00002208       LI R2 0x00100000      ; UART physical and virtual base
0x00002210       LI R3 0x00100000
0x00002218       LI R4 KERNEL_FLAGS
0x00002220       BL map_page

0x00002228       LI R2 0x00101000      ; PIT physical and virtual base
0x00002230       LI R3 0x00101000
0x00002238       LI R4 KERNEL_FLAGS
0x00002240       BL map_page

0x00002248       LI R2 0x00102000      ; PIC physical and virtual base
0x00002250       LI R3 0x00102000
0x00002258       LI R4 KERNEL_FLAGS
0x00002260       BL map_page

    ; Dynamically allocated page tables, kernel stacks, fd tables and
    ; kernel buffers are addressed by their physical address in kernel
    ; code. Keep the complete allocator pool identity-mapped and
    ; supervisor-only in every address space.
0x00002268       LI R12 PAGE_ALLOC_BASE
0x00002270       LI R7 PAGE_ALLOC_END
map_common_dynamic_loop:
0x00002278       CMP R12 R7
0x0000227C       BGE map_common_dynamic_done
0x00002284       MOV R2 R12
0x00002288       MOV R3 R12
0x0000228C       LI R4 KERNEL_FLAGS
0x00002294       BL map_page
0x0000229C       LI R6 PAGE_SIZE
0x000022A4       ADD R12 R12 R6
0x000022A8       B map_common_dynamic_loop
map_common_dynamic_done:

    ;===================================
    ; map static tarfs image to kernel
    ;===================================

0x000022B0       LI R12 tarfs_start
0x000022B8       LI R7  tarfs_end
map_tarfs_loop:
0x000022C0       CMP R12 R7
0x000022C4       BGE map_tarfs_done
0x000022CC       MOV R2 R12
0x000022D0       MOV R3 R12
0x000022D4       LI R4 KERNEL_FLAGS
0x000022DC       BL map_page
0x000022E4       LI R6 PAGE_SIZE
0x000022EC       ADD R12 R12 R6
0x000022F0       B map_tarfs_loop
map_tarfs_done:

0x000022F8       POP R12
0x000022FC       POP LR
0x00002300       RET

;================================================================
; Map a single page: VA in R2, PA in R3, flags in R4
;================================================================

map_page:
    ; R1=PTBR, R2=VA, R3=PA, R4=flags. The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002304       PUSH R5
0x00002308       PUSH R6
0x0000230C       SHR R5 R2 12               ; VPN
0x00002310       SHL R5 R5 2                ; page-table byte offset
0x00002314       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002318       STW R6 [R1 + R5]           ; store PTE in page-table: ptbr + offset
0x0000231C       POP R6
0x00002320       POP R5
0x00002324       RET

;================================================================
; Map a single page real-time : R1 PTBR, VA in R2, PA in R3, flags in R4
;================================================================

map_page_rt:
    ; Runtime page-table update. Same ABI as map_page, but also invalidates
    ; the cached translation for R2 so permission changes take effect now.
    ; The PTE format stores the physical
    ; page base in bits [31:12] and KR32 permission bits in [11:0].
0x00002328       PUSH R5
0x0000232C       PUSH R6
0x00002330       SHR R5 R2 12               ; VPN
0x00002334       SHL R5 R5 2                ; page-table byte offset
0x00002338       OR R6 R3 R4                ; PTE = PA page base | flags
0x0000233C       STW R6 [R1 + R5]           ; store PTE in page-table: ptbr + offset
0x00002340       INVLPG R2                  ; Invalidate /flush tlb cache
0x00002344       POP R6
0x00002348       POP R5
0x0000234C       RET

; ================================================================
; Initialize MMIO devices (PIC, PIT, UART)
; ================================================================

init_mmio_devices:
    ; ----------------------------------------------------
    ; Setup MMIO PIC: Enable IRQ 0 (timer) and IRQ 1 (uart)
    ; ----------------------------------------------------
0x00002350       LI R1 0x00102000
0x00002358       LI R2 3                 ; IRQ 0 = bit 0, IRQ 1 = bit 1, so mask = 0b11 = 3 to enable both
0x00002360       STW R2 [R1 + 0]         ; PIC_MASK = 3 (INT 0 & 1 enabled)

    ; ----------------------------------------------------
    ; Setup MMIO PIT: Set period to 2000 ms and enable ticks
    ; ----------------------------------------------------
0x00002364       LI R1 0x00101000
0x0000236C       LI R2 2000
0x00002374       STW R2 [R1 + 0]         ; PIT_PERIOD = 2000 ms
0x00002378       LI R2 3                 ; PIT_ENABLE = bit 0, INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x00002380       STW R2 [R1 + 4]         ; PIT_CTRL = 3 (PIT_ENABLE | INT_ENABLE)

    ; ----------------------------------------------------
    ; Setup MMIO UART: Enable RX/TX interrupts
    ; ----------------------------------------------------
0x00002384       LI R1 0x00100000
0x0000238C       LI R2 3                 ; UART_RX_INT_ENABLE = bit 0, UART_TX_INT_ENABLE = bit 1, so mask = 0b11 = 3 to enable both
0x00002394       STW R2 [R1 + 8]         ; UART_CTRL = 3 (RX_INT_ENABLE | TX_INT_ENABLE)

0x00002398       RET

; ================================================================
; Enable MMU and Interrupts
; ================================================================
enable_vm:
0x0000239C       ENABLEMMU               ;enable MMU with current PTBR (set in init_page_tables)
    ; Interrupts are enabled by SRET from the first task trapframe.
    ; Keeping them disabled during boot avoids taking an IRQ before
    ; SSCRATCH contains a valid per-task kernel stack pointer.
    ;ENABLEINT
    ;DEBUG
0x000023A0       RET


; ================================================================
; UNIFIED TRAP ENTRY POINT (all traps and interrupts go here)
; ================================================================
trap_entry:
    ; Switch from interrupted task stack to this task's kernel stack.
    ; Before: SP=user/task stack, SSCRATCH=kernel stack top.
    ; After:  SP=kernel stack, SSCRATCH=interrupted task SP.
    ; so sp = u-sp, sscratch=k-sp => sp=k-sp, scratch=u-sp
    ;
0x000023A4       CSRRW SP SSCRATCH SP

    ; Save interrupted GPR state on the kernel stack. SP itself is
    ; saved explicitly below from SSCRATCH, because SP now points to
    ; the kernel trapframe rather than the interrupted task stack.
0x000023A8       PUSH R1
0x000023AC       PUSH R2
0x000023B0       PUSH R3
0x000023B4       PUSH R4
0x000023B8       PUSH R5
0x000023BC       PUSH R6
0x000023C0       PUSH R7
0x000023C4       PUSH R8
0x000023C8       PUSH R9
0x000023CC       PUSH R10
0x000023D0       PUSH R11
0x000023D4       PUSH R12
0x000023D8       PUSH R14
0x000023DC       PUSH R15

    ; Save interrupted task SP plus privileged trap state.
0x000023E0       CSRR R1 SSCRATCH
0x000023E4       PUSH R1
0x000023E8       CSRR R1 SEPC
0x000023EC       PUSH R1
0x000023F0       CSRR R1 SFLAGS
0x000023F4       PUSH R1
0x000023F8       CSRR R1 SSTATUS
0x000023FC       PUSH R1
0x00002400       CSRR R1 SCAUSE
0x00002404       PUSH R1
0x00002408       CSRR R1 STVAL
0x0000240C       PUSH R1

    ; Dispatch based on scause.
0x00002410       CSRR R1 SCAUSE
0x00002414       CMP R1 0
0x00002418       BEQ handle_divide_zero

0x00002420       CMP R1 1
0x00002424       BEQ handle_invalid_instr

0x0000242C       CMP R1 2
0x00002430       BEQ handle_page_fault

0x00002438       CMP R1 3
0x0000243C       BEQ handle_syscall

0x00002444       CMP R1 6
0x00002448       BEQ handle_debug

0x00002450       CMP R1 16
0x00002454       BEQ handle_irq

    ; Unknown cause - halt
0x0000245C       HLT

handle_divide_zero:
    ; TODO: handle divide by zero

0x00002460       DEBUG 1
0x00002464       B trap_restore

handle_invalid_instr:
    ; TODO: handle invalid instruction

0x0000246C       B trap_restore

handle_page_fault:
    ; R2 contains fault address
    ; TODO: handle page fault
0x00002474       HLT

0x00002478       B trap_restore

handle_syscall:
    ;=================================================================
    ; STVAL contains the SVC immediate. User arguments are saved in the
    ; trapframe at TF_R1..TF_R4, and the return value is written to TF_R1.
    ; so essentially args get passed using stackframe very similar when we do usual bl call
    ; except that here is interrupt logic and special instructions applied
    ; so SVC is a special BL to OS call -)
    ;=================================================================

0x00002480       CSRR R2 STVAL

0x00002484       CMP R2 SYS_COUNT
0x00002488       BGE syscall_unknown

0x00002490       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x00002498       SHL R4 R2 2
0x0000249C       LDW R5 [R3 + R4]
0x000024A0       JR R5

syscall_unknown:
;================================================================
; For unknown syscalls, return an errno in R1 and restore.
;================================================================

0x000024A4       LI R1 ERR_NOSYS
0x000024AC       STW R1 [SP + TF_R1]
0x000024B0       B trap_restore

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
    .WORD syscall_mkdir         ; SVC 17
    .WORD syscall_rmdir         ; SVC 18
    .WORD syscall_unlink        ; SVC 19



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

0x00002508       LDW R8 [SP + TF_R1]        ; user path pointer
0x0000250C       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00002510       PUSH R9

0x00002514       MOV R1 R8
0x00002518       BL copy_path_from_user
0x00002520       CMP R1 0
0x00002524       BEQ execve_badfault

0x0000252C       MOV R12 R1                ; kernel pointer to copied pathname

0x00002530       MOV R1 R12
0x00002534       BL vfs_lookup             ; lookup inode for the file
0x0000253C       CMP R1 0
0x00002540       BEQ execve_noent

0x00002548       MOV R9 R1                 ; inode*
0x0000254C       LDW R1 [R9 + INODE_TYPE]
0x00002550       LI R2 INODE_DIR
0x00002558       CMP R1 R2
0x0000255C       BEQ execve_noexec           ; if the inode is a directory, we cannot execute it

0x00002564       LDW R3 [R9 + INODE_SIZE]
0x00002568       LI R4 PAGE_SIZE         ; 4096 bytes
0x00002570       CMP R3 R4
0x00002574       BGT execve_noexec       ; if the inode size is greater than a page, we cannot execute it

0x0000257C       BL file_alloc
0x00002584       CMP R1 0
0x00002588       BEQ execve_nomem         ; if we cannot allocate a file for this inode, return error

0x00002590       MOV R10 R1                ; file*
0x00002594       MOV R1 R10
0x00002598       MOV R2 R9
0x0000259C       LI R3 FD_FLAG_READ
0x000025A4       BL file_init            ; initialize the file structure for reading the executable

0x000025AC       BL page_alloc           ; allocate a new page for the executable code of execve program
0x000025B4       CMP R1 0
0x000025B8       BEQ execve_noexec_file

0x000025C0       MOV R11 R1                ; new code page PA for execve program

; macro: GET_CURR_TASK_IDX R4    ; get current task index
0x000025C4   LI R1 CURRENT_TASK
0x000025CC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000025D0   LI R1 TASK_SIZE
0x000025D8   MUL R3 R4 R1
0x000025DC   LI R5 tasks
0x000025E4   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12, R5 ; preserve old exec code page PA for rollback / cleanup
0x000025E8   LDW R12 [R5 + TASK_CODE_PAGE]
; macro: TASK_GET_PTBR R1, R5       ; R1 = PTBR of current task
0x000025EC   LDW R1 [R5 + TASK_PTBR]
0x000025F0       LI R2 USER_CODE_VA         ; R2 = code page VA for execve program
0x000025F8       MOV R3 R11                 ; R3 = code page PA for execve program
0x000025FC       LI R4 USER_RW              ; R4 = temporary RW permissions so we can load the page
0x00002604       BL map_page_rt             ; runtime map executable page RW at USER_CODE_VA for loading

; macro: TASK_GET_DATA_PAGE R1, R5  ; get data page PA for current task
0x0000260C   LDW R1 [R5 + TASK_DATA_PAGE]
0x00002610       CMP R1 0
0x00002614       BEQ execve_data_ok         ; if the task has no data page, skip clearing it
0x0000261C       LI R3 PAGE_SIZE
0x00002624       BL mem_zero                ; zero the current task data page before execve starts

execve_data_ok:

0x0000262C       MOV R1 R10              ; file* of execve program
0x00002630       LI R2 USER_CODE_VA      ; VA of code page for execve program
0x00002638       LI R3 PAGE_SIZE         ; size of code page for execve program
0x00002640       BL file_read            ; load executable into USER_CODE_VA
0x00002648       CMP R1 0
0x0000264C       BLT execve_read_fail    ; if read fails, restore old exec code page and return error

0x00002654       MOV R1 R10              ; file* of execve program
0x00002658       BL file_put             ; release file resources after successful load

; macro: GET_CURR_TASK_IDX R4    ; this was real mistake here! I forgot to retore current task ptr
0x00002660   LI R1 CURRENT_TASK
0x00002668   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4     ; reload task ptr after calls that may clobber caller-saved R5
0x0000266C   LI R1 TASK_SIZE
0x00002674   MUL R3 R4 R1
0x00002678   LI R5 tasks
0x00002680   ADD R5 R5 R3
                            ; we also added INVLPG - for good! - history comments
    ; commit new exec state after successful file load
0x00002684       LI R1 USER_CODE_VA
; macro: TASK_SET_PC R5, R1              ; start execution at USER_CODE_VA
0x0000268C   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5, R11      ; remember physical page backing this user code
0x00002690   STW R11 [R5 + TASK_CODE_PAGE]
0x00002694       LI R1 USER_STACK_TOP
; macro: TASK_SET_USP R5, R1             ; reset user stack pointer
0x0000269C   STW R1 [R5 + TASK_USP]
0x000026A0       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5, R1           ; reset program break into the task's data page
0x000026A8   STW R1 [R5 + TASK_BREAK]

    ; Remap the new code page read-only before handing control over
; macro: TASK_GET_PTBR R1, R5            ; get PTBR of current task
0x000026AC   LDW R1 [R5 + TASK_PTBR]
0x000026B0       LI R2 USER_CODE_VA              ; VA of code page for execve program
0x000026B8       MOV R3 R11                      ; PA of code page for execve program
0x000026BC       LI R4 KERNEL_USER_ALL
0x000026C4       BL map_page_rt                  ; switch the new code page from RW to RX

0x000026CC       CMP R12 0                       ; R12 = old code page PA for execve program from task metadata
0x000026D0       BEQ execve_commit_done          ; if no previous code page, skip freeing it
0x000026D8       MOV R1 R12
0x000026DC       BL page_put                    ; free the old exec code page now that the new one is committed

execve_commit_done:
    ; Build a fresh Unix-style initial stack:
    ;   [argc][argv pointers...][NULL][string data...]
    ; The new program can read argc/argv from the stack, and we also mirror
    ; argc/argv into R1/R2 for convenience.

0x000026E4       POP R4                         ; remember argv ptr from start of syscall_execve
0x000026E8       LI R6 0                        ; R6 = argc counter

    ; Step 1: Count argc - walk on argv ptrs count argc till  we find NULL check above
0x000026F0       MOV R7 R4
execve_argv_count_loop:
0x000026F4       CMP R7 0
0x000026F8       BEQ execve_argv_count_done
0x00002700       LDW R8 [R7]
0x00002704       CMP R8 0
0x00002708       BEQ execve_argv_count_done

0x00002710       CMP R6 16                      ;MAX argc count
0x00002714       BGE execve_badfault

0x0000271C       ADD R6 R6 1
0x00002720       ADD R7 R7 4
0x00002724       B execve_argv_count_loop

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
0x0000272C       LI  R5 USER_STACK_TOP

    ;-------------------------------------------------------------
    ; Temporary kernel array for argv pointers.
    ; argv_tmp[16]
    ;-------------------------------------------------------------
0x00002734       LI  R11 execve_tmp_argv

    ;-------------------------------------------------------------
    ; Copy strings in reverse order so they naturally pack downward.
    ;-------------------------------------------------------------
0x0000273C       MOV R7 R6
0x00002740       SUB R7 R7 1             ; [argc]-1

execve_copy_reverse:        ; R7(i) = (argc-1 ... 0)
0x00002744       LI  R8 -1
0x0000274C       CMP R7 R8
0x00002750       BEQ execve_strings_done

    ; source string = argv[i] starting from last arg string
0x00002758       MOV R8 R7
0x0000275C       SHL R8 R8 2             ;R7(i)*4+argv ptr => R9(&argv[i])
0x00002760       ADD R9 R4 R8
0x00002764       LDW R10 [R9]            ;get string ptr from last argv[argc-1] (in first iteration)

    ;-------------------------------------------------------------
    ; strlen()
    ; R12 = length including terminating NUL
    ;-------------------------------------------------------------
0x00002768       LI R12 0                ;str len ctr - compute this argv string len (+ 0)

execve_strlen:

0x00002770       LDB R2 [R10 + R12]
0x00002774       ADD R12 R12 1
0x00002778       CMP R2 0
0x0000277C       BNE execve_strlen

    ; reserve space - on user stack top this argv string destination

0x00002784       SUB R5 R5 R12               ; R5 dest addres argv string copy to gets updated by lenght of each string
                                ; to be copied to tmp

    ; remember destination pointer
0x00002788       MOV R8 R7
0x0000278C       SHL R8 R8 2                 ;R7 argv string number in argv array
0x00002790       ADD R9 R11 R8               ;r9=&temp argv[i]  which is = R7(i)*4+&temp argv[] array storage
0x00002794       STW R5 [R9]                 ;R5->[R9] string pointer on user stack

    ; memcpy()
0x00002798       LI R8 0

execve_copy_string:             ; first copy strings ptrs from (argv array) to temp storage
                                ; from last string to first - opposite order
0x000027A0       LDB R2 [R10 + R8]           ; R10 execv argv &string[i]  (last to first)
0x000027A4       STB R2 [R5 + R8]            ; R5 same in tmp

0x000027A8       CMP R2 0
0x000027AC       BEQ execve_copy_done

0x000027B4       ADD R8 R8 1                 ; to next char in string
0x000027B8       B execve_copy_string

execve_copy_done:

0x000027C0       SUB R7 R7 1                 ; to copy next string
0x000027C4       B execve_copy_reverse

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
0x000027CC       MOV R7 R6
0x000027D0       ADD R7 R7 2

0x000027D4       MOV R8 R7
0x000027D8       SHL R8 R8 2

0x000027DC       SUB R5 R5 R8            ;update R5 by stack words

    ;-------------------------------------------------------------
    ; R5 now becomes initial user stack pointer.
    ;-------------------------------------------------------------

0x000027E0       STW R6 [R5]             ; put argc to user stack see picture above (Reserve space for:)

0x000027E4       ADD R9 R5 4             ; R9 - move 'writing head' to next element argv in user stack
                            ; R5 - initial user stack pointer
    ;-------------------------------------------------------------
    ; argv data copied. now - Copy argv pointers
    ;-------------------------------------------------------------
0x000027E8       LI R7 0

execve_copy_argv:

0x000027F0       CMP R7 R6
0x000027F4       BEQ execve_copy_argv_done

0x000027FC       MOV R8 R7
0x00002800       SHL R8 R8 2              ; R7 argv index

0x00002804       LDW R12 [R11 + R8]       ; we copy stings pointers here (not actual strings!)
                             ; R11 - &execve_tmp_argv
0x00002808       STW R12 [R9 + R8]        ; R9 - write head on user stack

0x0000280C       ADD R7 R7 1
0x00002810       B execve_copy_argv

execve_copy_argv_done:

    ; argv[argc] = NULL
0x00002818       MOV R8 R6
0x0000281C       SHL R8 R8 2
0x00002820       ADD R10 R9 R8

0x00002824       LI R12 0
0x0000282C       STW R12 [R10]               ; write NuLL - finish form user stack frame (arguments part!)

    ;-------------------------------------------------------------
    ; Prepare trapframe for new process.
    ;-------------------------------------------------------------

0x00002830       STW R6 [SP + TF_R1]      ; argc

0x00002834       MOV R1 R9
0x00002838       STW R1 [SP + TF_R2]      ; argv

0x0000283C       LI R1 0
0x00002844       STW R1 [SP + TF_R3]      ; envp

0x00002848       STW R5 [SP + TF_USP]     ; initial user SP

    ; Prepare a fresh user register state for the new program.
0x0000284C       LI R1 0
0x00002854       STW R1 [SP + TF_R4]
0x00002858       STW R1 [SP + TF_R5]
0x0000285C       STW R1 [SP + TF_R6]
0x00002860       STW R1 [SP + TF_R7]
0x00002864       STW R1 [SP + TF_R8]
0x00002868       STW R1 [SP + TF_R9]
0x0000286C       STW R1 [SP + TF_R10]
0x00002870       STW R1 [SP + TF_R11]
0x00002874       STW R1 [SP + TF_R12]
0x00002878       LI R1   USER_CODE_VA               ; user execve program entry point
0x00002880       STW R1 [SP + TF_SEPC]              ; set SEPC to the new program entry point

0x00002884       B trap_restore                     ; restore kernel trapframe and start user execution at user_code_va

; as it should be clear
; if fail occured we rollback depending at what stage fail occured and free used resources
; then we exit back to child process with fail exit code
execve_read_fail:
0x0000288C       MOV R1 R11
0x00002890       BL page_put                    ; put-free the failed new code page

; macro: GET_CURR_TASK_IDX R4
0x00002898   LI R1 CURRENT_TASK
0x000028A0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4           ; reload task ptr before restoring USER_CODE_VA mapping
0x000028A4   LI R1 TASK_SIZE
0x000028AC   MUL R3 R4 R1
0x000028B0   LI R5 tasks
0x000028B8   ADD R5 R5 R3

0x000028BC       CMP R12 0
0x000028C0       BEQ execve_restore_no_prev
; macro: TASK_GET_PTBR R1, R5
0x000028C8   LDW R1 [R5 + TASK_PTBR]
0x000028CC       LI R2 USER_CODE_VA
0x000028D4       MOV R3 R12
0x000028D8       LI R4 USER_RX
0x000028E0       BL map_page_rt                ; restore previous exec page mapping at USER_CODE_VA
0x000028E8       MOV R1 R12
; macro: TASK_SET_CODE_PAGE R5, R12    ; restore previous exec code page pointer
0x000028EC   STW R12 [R5 + TASK_CODE_PAGE]
0x000028F0       B execve_restore_done

execve_restore_no_prev:
; macro: TASK_GET_PTBR R1, R5
0x000028F8   LDW R1 [R5 + TASK_PTBR]
0x000028FC       LI R2 USER_CODE_VA
0x00002904       LI R3 0
0x0000290C       LI R4 0
0x00002914       BL map_page_rt                ; unmap USER_CODE_VA if there was no previous code page
0x0000291C       LI R1 0
; macro: TASK_SET_CODE_PAGE R5, R1
0x00002924   STW R1 [R5 + TASK_CODE_PAGE]

execve_restore_done:
0x00002928       MOV R1 R10
0x0000292C       BL file_put

0x00002934       POP R1                      ;save stack
0x00002938       LI R1 ERR_NOEXEC
0x00002940       STW R1 [SP + TF_R1]
0x00002944       B trap_restore

execve_nomem_file:
0x0000294C       MOV R1 R10
0x00002950       BL file_put

0x00002958       POP R1
0x0000295C       LI R1 ERR_NOMEM
0x00002964       STW R1 [SP + TF_R1]
0x00002968       B trap_restore

execve_nomem:
0x00002970       POP R1
0x00002974       LI R1 ERR_NOMEM
0x0000297C       STW R1 [SP + TF_R1]
0x00002980       B trap_restore

execve_noexec_file:

0x00002988       MOV R1 R10
0x0000298C       BL file_put
execve_noexec:
0x00002994       POP R1
0x00002998       LI R1 ERR_NOEXEC
0x000029A0       STW R1 [SP + TF_R1]
0x000029A4       B trap_restore

execve_noent:
0x000029AC       POP R1
0x000029B0       LI R1 ERR_NOENT
0x000029B8       STW R1 [SP + TF_R1]
0x000029BC       B trap_restore

execve_badfault:
0x000029C4       POP R1
0x000029C8       LI R1 ERR_FAULT
0x000029D0       STW R1 [SP + TF_R1]
0x000029D4       B trap_restore

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

0x000030E8       LDW R8 [SP + TF_R1]        ; user path pointer
0x000030EC       LDW R9 [SP + TF_R2]        ; user argv pointer
0x000030F0       MOV R11 R9                 ; save to R11

0x000030F4       LI  R1 exec_path
0x000030FC       MOV R2 R8
0x00003100       LI  R3 EXEC_MAX_PATH
0x00003108       BL copy_user_string        ;copy path string to ws
0x00003110       CMP R1 0
0x00003114       BEQ execve_badfault

    ;init execve ws
0x0000311C       LI R1 exec_argc
0x00003124       LI R2 0
0x0000312C       STW R2 [R1]

    ;count argc

0x00003130       MOV R8 R9               ; user argv
0x00003134       LI  R6 0                ; argc
;count ptrs in array of ptrs argv till 0 -null end
argc_loop:
0x0000313C       CMP R8 0                ;if no argv 0-null
0x00003140       BEQ argc_done
0x00003148       LDW R3 [R8]
0x0000314C       CMP R3 0                ;if end
0x00003150       BEQ argc_done
0x00003158       CMP R6 EXEC_MAX_ARGS    ;if too much MAX argc count
0x0000315C       BGE exec_badfault
0x00003164       ADD R6 R6 1
0x00003168       ADD R8 R8 4
0x0000316C       B argc_loop
argc_done:
0x00003174       LI R1 exec_argc         ;store it to ws
0x0000317C       STW R6 [R1]

0x00003180       MOV R9 R6               ;R9 argc R11 user argv pointer
0x00003184       MOV R8 R11
0x00003188       BL  copy_argv_strings   ;fill arrays in ws from argvs
0x00003190       CMP R1 0
0x00003194       BNE exec_fail

0x0000319C       LI R1 exec_path
    ; load exec image to allocted memory
    ; map_rt pages
0x000031A4       BL exec_load_binary
0x000031AC       CMP R1 0
0x000031B0       BEQ exec_fail

0x000031B8       MOV R11 R1        ; new code page
0x000031BC       MOV R12 R2        ; old code page
0x000031C0       BL exec_build_stack_image
0x000031C8       CMP R1 0
0x000031CC       BNE exec_rollback

0x000031D4       MOV R1 R11
0x000031D8       MOV R2 R12

0x000031DC       B exec_commit_image

exec_badfault:
0x000031E4       NOP
exec_fail:
0x000031E8       NOP
exec_rollback:
0x000031EC       LI R1 ERR_FAULT
0x000031F4       STW R1 [SP + TF_R1]
0x000031F8       B trap_restore
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

0x00003200       MOV R11 R1              ; new page
0x00003204       MOV R12 R2              ; old page

; macro: GET_CURR_TASK_IDX R4
0x00003208   LI R1 CURRENT_TASK
0x00003210   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x00003214   LI R1 TASK_SIZE
0x0000321C   MUL R3 R4 R1
0x00003220   LI R5 tasks
0x00003228   ADD R5 R5 R3

0x0000322C       LI  R1 exec_stack_used
0x00003234       LDW R8 [R1]
0x00003238       LI  R9 USER_STACK_TOP
0x00003240       SUB R9 R9 R8            ; final user SP
0x00003244       MOV R1 R9               ;  R2->R9 len R8 - cpy our image for stack
0x00003248       LI  R2 exec_stack_image
0x00003250       MOV R3 R8
0x00003254       BL memcpy

0x0000325C       LI R1 USER_CODE_VA      ; commit task state:
; macro: TASK_SET_PC R5,R1       ; PC starts to USER_CODE_VA
0x00003264   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5,R11 ; set new code page (tab+pages)
0x00003268   STW R11 [R5 + TASK_CODE_PAGE]
0x0000326C       MOV R1 R9
; macro: TASK_SET_USP R5,R1        ; set USP
0x00003270   STW R1 [R5 + TASK_USP]
0x00003274       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5,R1      ; set BRK
0x0000327C   STW R1 [R5 + TASK_BREAK]

    ; Make sure the task's fixed user stack page is still mapped RW before
    ; returning to user mode. execve rewrites the stack contents, but the
    ; page-table entry must remain valid even if the task was previously
    ; switched through another path.
; macro: TASK_GET_PTBR R2,R5
0x00003280   LDW R2 [R5 + TASK_PTBR]
; macro: TASK_GET_USTACK_PAGE R3,R5
0x00003284   LDW R3 [R5 + TASK_USTACK_PAGE]
0x00003288       CMP R3 0
0x0000328C       BEQ exec_commit_skip_stack_map
    ; ---- remap new code pages to RW ---- don know why
0x00003294       MOV R1 R11
0x00003298       LI R3 USER_CODE_VA
0x000032A0       LI R4 USER_RW
0x000032A8       BL pages_map_table

  ;  LI R2 USER_STACK_VA
  ;  LI R4 USER_RW
  ;  BL map_page_rt

exec_commit_skip_stack_map:

; macro: TASK_GET_PTBR R2,R5
0x000032B0   LDW R2 [R5 + TASK_PTBR]
0x000032B4       MOV R1 R11
0x000032B8       LI R3 USER_CODE_VA
0x000032C0       LI R4 KERNEL_USER_ALL
0x000032C8       BL pages_map_table

;    LI R2 USER_CODE_VA
;    MOV R3 R11
;    LI R4 KERNEL_USER_ALL   ; map code page RX subject to permissions on X (now all X)
;    BL map_page_rt

0x000032D0       CMP R12 0               ; free old pa page (R12) if have
0x000032D4       BEQ no_old_page

0x000032DC       MOV R1 R12
0x000032E0       BL pages_free_table     ; ---- free old codepage (table and pages) ----

   ; BL page_put             ; free page
no_old_page:

0x000032E8       LI  R1 exec_argc
0x000032F0       LDW R2 [R1]
0x000032F4       STW R2 [SP+TF_R1]

0x000032F8       MOV R1 R9
0x000032FC       ADD R1 R1 4
0x00003300       STW R1 [SP+TF_R2]       ; user sp with image on top + 4 so it points to &argv image

0x00003304       LI R1 0                 ; envp
0x0000330C       STW R1 [SP+TF_R3]

0x00003310       STW R9 [SP+TF_USP]      ; user sp

0x00003314       LI R1 0
0x0000331C       STW R1 [SP+TF_R4]
0x00003320       STW R1 [SP+TF_R5]
0x00003324       STW R1 [SP+TF_R6]
0x00003328       STW R1 [SP+TF_R7]
0x0000332C       STW R1 [SP+TF_R8]
0x00003330       STW R1 [SP+TF_R9]
0x00003334       STW R1 [SP+TF_R10]
0x00003338       STW R1 [SP+TF_R11]
0x0000333C       STW R1 [SP+TF_R12]

0x00003340       LI R1 USER_CODE_VA
0x00003348       STW R1 [SP+TF_SEPC]

0x0000334C       B trap_restore

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
0x00003354       PUSH LR
0x00003358       PUSH R8
0x0000335C       PUSH R9
0x00003360       PUSH R10
0x00003364       PUSH R11
0x00003368       PUSH R12

0x0000336C       LI   R1 exec_argc   ;argc
0x00003374       LDW  R6 [R1]

0x00003378       MOV  R7 R6          ;pointer_bytes = (argc+2)*4
0x0000337C       ADD  R7 R7 2
0x00003380       SHL  R7 R7 2

0x00003384       LI   R1 exec_strings_used   ; strings blob len
0x0000338C       LDW  R8 [R1]

    ;----------------------------------------------------------
    ; total = pointer_bytes(len argv ptr array + 4b argc) + string_bytes(len string blobs)
    ;----------------------------------------------------------

0x00003390       ADD  R9 R7 R8
    ; check for MAX
0x00003394       LI   R1 EXEC_STACK_SIZE
0x0000339C       CMP  R9 R1
0x000033A0       BGT  exec_stack_nomem

0x000033A8       LI   R1 exec_stack_used     ; save used size
0x000033B0       STW  R9 [R1]

0x000033B4       LI   R10 exec_stack_image   ;stack base for image
    ; building image for stack as on picture
0x000033BC       STW  R6 [R10]   ;argc

    ; copy string blob
0x000033C0       MOV  R1 R10
0x000033C4       ADD  R1 R1 R7   ; skip room for pointer_bytes see picture
0x000033C8       LI   R2 exec_strings
0x000033D0       MOV  R3 R8      ; blob len
0x000033D4       BL   memcpy

    ;----------------------------------------------------------
    ; future user addresses
    ;----------------------------------------------------------

0x000033DC       LI   R11 USER_STACK_TOP
0x000033E4       SUB  R11 R11 R9             ; r9 total image len, R11 start address image in the user stack
0x000033E8       MOV  R12 R11
0x000033EC       ADD  R12 R12 R7             ; r12 pointer bytes ptr in image in stack - start of string blob

    ;----------------------------------------------------------
    ; argv table build
    ;----------------------------------------------------------

0x000033F0       ADD  R10 R10 4              ; argv[0] starts after argc
0x000033F4       LI   R4 exec_argv_offsets   ; args offsetss array
0x000033FC       LI   R5 0
argv_loop:
0x00003404       CMP  R5 R6                  ; argc
0x00003408       BEQ  argv_done              ; if finished
0x00003410       MOV  R1 R5
0x00003414       SHL  R1 R1 2
0x00003418       LDW  R2 [R4+R1]             ; get arg[i] offset
0x0000341C       ADD  R2 R2 R12              ; compute R2 - blobs string adress for this arg[i]
0x00003420       STW  R2 [R10+R1]            ; store this address to argv array in image
0x00003424       ADD  R5 R5 1
0x00003428       B    argv_loop
argv_done:
0x00003430       MOV  R1 R6
0x00003434       SHL  R1 R1 2

0x00003438       LI   R2 0
0x00003440       STW  R2 [R10+R1]            ; put null here: argv[argc] = NULL
    ;success
0x00003444       LI   R1 0
0x0000344C       POP  R12
0x00003450       POP  R11
0x00003454       POP  R10
0x00003458       POP  R9
0x0000345C       POP  R8
0x00003460       POP  LR
0x00003464       RET

exec_stack_nomem:
0x00003468       LI   R1 ERR_NOMEM
0x00003470       POP  R12
0x00003474       POP  R11
0x00003478       POP  R10
0x0000347C       POP  R9
0x00003480       POP  R8
0x00003484       POP  LR
0x00003488       RET

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
0x0000348C       PUSH LR
0x00003490       PUSH R7
0x00003494       PUSH R8
0x00003498       PUSH R9
0x0000349C       PUSH R10
0x000034A0       PUSH R11
0x000034A4       PUSH R12

    ; Executables are looked up read-only; R2 otherwise contains argv-copy
    ; scratch data and can accidentally make vfs_lookup skip TARFS.
0x000034A8       LI R2 O_RDONLY
0x000034B0       BL vfs_lookup   ; lookup inode for the file
0x000034B8       CMP R1 0
0x000034BC       BEQ load_noent
0x000034C4       MOV R9 R1

0x000034C8       LDW R1 [R9 + INODE_TYPE]    ;check inode type/size
0x000034CC       LI R2 INODE_DIR
0x000034D4       CMP R1 R2
0x000034D8       BEQ load_noexec
0x000034E0       LDW R3 [R9 + INODE_SIZE]
0x000034E4       LI R4 MAX_APP_SIZE
0x000034EC       CMP R3 R4
0x000034F0       BGT load_noexec

0x000034F8       BL file_alloc               ;allocate file
0x00003500       CMP R1 0
0x00003504       BEQ load_nomem
0x0000350C       MOV R10 R1                  ; savr file ptr R10
0x00003510       MOV R1 R10
0x00003514       MOV R2 R9
0x00003518       LI R3 FD_FLAG_READ
0x00003520       BL file_init

    ; ---- allocate table and code pages ----
    ; makes table page and few pages up on file size
0x00003528       LDW R1 [R9 + INODE_SIZE]
    ;MOV R1 R6                  ; file size
0x0000352C       BL pages_allocate_table
0x00003534       CMP R1 0
0x00003538       BEQ load_file_fail

0x00003540       MOV R11 R1                 ; new table PA
0x00003544       MOV R12 R2                 ; count (not needed further)

    ; ---- map pages RW ----
; macro: GET_CURR_TASK_IDX R4        ;current task
0x00003548   LI R1 CURRENT_TASK
0x00003550   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x00003554   LI R1 TASK_SIZE
0x0000355C   MUL R3 R4 R1
0x00003560   LI R5 tasks
0x00003568   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12,R5   ; save old pa code page from this task to R12
0x0000356C   LDW R12 [R5 + TASK_CODE_PAGE]

   ; TASK_GET_PTBR R1,R5
   ; LI R2 USER_CODE_VA
   ; MOV R3 R11                 ;new pa code page
   ; LI R4 USER_RW
   ; BL map_page_rt             ;map it for loading to USER_CODE_VA

; macro: TASK_GET_PTBR R2, R5        ; PTBR
0x00003570   LDW R2 [R5 + TASK_PTBR]
0x00003574       LI R3 USER_CODE_VA          ; starting new code page VA
0x0000357C       LI R4 USER_RW               ; mapping flAGS
0x00003584       MOV R1 R11                  ; new table PA (with pa pages)
0x00003588       BL pages_map_table

    ; ---- zero data page ----
; macro: TASK_GET_DATA_PAGE R1,R5    ; tasks va data_page
0x00003590   LDW R1 [R5 + TASK_DATA_PAGE]
0x00003594       CMP R1 0
0x00003598       BEQ load_read
0x000035A0       LI R3 PAGE_SIZE
0x000035A8       BL mem_zero                 ; clean task data_page

load_read:
0x000035B0       MOV R1 R10                  ; file* with program
0x000035B4       LI  R2 USER_CODE_VA
0x000035BC       LDW R3 [R9 + INODE_SIZE]    ; file size
0x000035C0       BL file_read
0x000035C8       CMP R1 0
0x000035CC       BLT load_read_fail

0x000035D4       MOV R1 R10                  ;loaded release file*
0x000035D8       BL file_put
    ; all loaedd R1 - new code page pa tab, R2 - old code page pa tab
0x000035E0       MOV R1 R11
0x000035E4       MOV R2 R12

exec_lb_exit:                   ;common! exit!
0x000035E8       POP R12
0x000035EC       POP R11
0x000035F0       POP R10
0x000035F4       POP R9
0x000035F8       POP R8
0x000035FC       POP R7
0x00003600       POP LR
0x00003604       RET
; in error generally depending on state rollback allocated resources
load_read_fail:
    ; in this case release file and pa code page
0x00003608       MOV R1 R10
0x0000360C       BL file_put
0x00003614       MOV R1 R11
0x00003618       BL page_put        ;free page
0x00003620       LI R1 0
0x00003628       LI R2 ERR_IO
0x00003630       B  exec_lb_exit

load_file_fail:
0x00003638       MOV R1 R10
0x0000363C       BL file_put

load_nomem:
0x00003644       LI R1 0
0x0000364C       LI R2 ERR_NOMEM
0x00003654       B  exec_lb_exit

load_noexec:
0x0000365C       MOV R1 R10
0x00003660       CMP R1 0
0x00003664       BEQ noexec_skip
0x0000366C       BL file_put

noexec_skip:
0x00003674       LI R1 0
0x0000367C       LI R2 ERR_NOEXEC
0x00003684       B  exec_lb_exit

load_noent:
0x0000368C       LI R1 0
0x00003694       LI R2 ERR_NOENT
0x0000369C       B  exec_lb_exit

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

0x000036A4       PUSH LR
0x000036A8       PUSH R7
0x000036AC       PUSH R8
0x000036B0       PUSH R9
0x000036B4       PUSH R10
0x000036B8       PUSH R11
0x000036BC       PUSH R12
    ;init this at first
0x000036C0       LI R1 exec_strings_used
0x000036C8       LI R2 0
0x000036D0       STW R2 [R1]

0x000036D4       LI   R11 exec_strings      ; destination blob
0x000036DC       LI   R12 0                 ; current offset
0x000036E4       LI   R7 0                  ; argv index
                               ;  R8 = user argv[]
                               ;  R9 = argc
exec_capture_next_arg:
    ; finished?
0x000036EC       CMP  R7 R9
0x000036F0       BEQ  exec_capture_done     ; if all agvs processed

    ;---------------------------------------------
    ; load argv[i] (ptr to string)
    ;---------------------------------------------
0x000036F8       LDW  R10 [R8]

0x000036FC       CMP  R10 0
0x00003700       BEQ  exec_capture_fault     ;if argv[i]==null

    ;---------------------------------------------
    ; save offset
    ;
    ; exec_argv_offsets[i]=current_offset (in R12)
    ;---------------------------------------------
0x00003708       LI   R1 exec_argv_offsets
0x00003710       MOV  R2 R7  ;i
0x00003714       SHL  R2 R2 2
0x00003718       ADD  R1 R1 R2
0x0000371C       STW  R12 [R1]

exec_copy_string:
    ;---------------------------------------------
    ; copy one character r10 argv[i] (ptr to string) R11 ptr to exec strings
    ;---------------------------------------------
0x00003720       LDB  R3 [R10]
0x00003724       STB  R3 [R11]
0x00003728       ADD  R10 R10 1
0x0000372C       ADD  R11 R11 1
0x00003730       ADD  R12 R12 1
    ; blob overflow?
0x00003734       LI   R1 EXEC_MAX_STRINGS
0x0000373C       CMP  R12 R1
0x00003740       BGT  exec_capture_fault
0x00003748       CMP  R3 0
0x0000374C       BNE  exec_copy_string           ; end of string?
0x00003754       ADD  R8 R8 4    ;to next argv[] string
0x00003758       ADD  R7 R7 1    ;i=i+1
0x0000375C       B    exec_capture_next_arg

exec_capture_done:
0x00003764       LI   R1 exec_strings_used
0x0000376C       STW  R12 [R1]           ; current offset after last string
0x00003770       LI  R1 0
0x00003778       POP R12
0x0000377C       POP R11
0x00003780       POP R10
0x00003784       POP R9
0x00003788       POP R8
0x0000378C       POP R7
0x00003790       POP LR
0x00003794       RET
exec_capture_fault:
0x00003798       LI   R1 ERR_FAULT
0x000037A0       POP R12
0x000037A4       POP R11
0x000037A8       POP R10
0x000037AC       POP R9
0x000037B0       POP R8
0x000037B4       POP R7
0x000037B8       POP LR
0x000037BC       RET

syscall_fork:
    ;================================================================
    ; fork()
    ; Returns child PID in the parent and 0 in the child.
    ; This clones the current task, duplicating its address space and
    ; user-writable state while preserving a new independent child thread.
    ;================================================================

0x000037C0       BL task_clone_current
0x000037C8       CMP R1 0
0x000037CC       BEQ fork_fail

    ; We return child PID to the parent via the trapframe.
; macro: TASK_GET_PID R2, R1
0x000037D4   LDW R2 [R1 + TASK_PID]
0x000037D8       STW R2 [SP + TF_R1]
0x000037DC       B trap_restore

fork_fail:
0x000037E4       LI R1 ERR_NOMEM
0x000037EC       STW R1 [SP + TF_R1]
0x000037F0       B trap_restore

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x000037F8       LI R1 0
0x00003800       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x00003804       B schedule_and_switch
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
0x0000380C       LDW R8 [SP + TF_R1]        ; R8 = exit code

; macro: GET_CURR_TASK_IDX R2
0x00003810   LI R1 CURRENT_TASK
0x00003818   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x0000381C   LI R1 TASK_SIZE
0x00003824   MUL R3 R2 R1
0x00003828   LI R5 tasks
0x00003830   ADD R5 R5 R3

    ; Store exit code in child task struct for parent to collect in waitforpid
; macro: TASK_SET_EXIT_CODE R5, R8  ; Save exit code
0x00003834   STW R8 [R5 + TASK_EXIT_CODE]

0x00003838       PUSH R5
0x0000383C       MOV R1 R5
0x00003840       BL task_close_fds          ; close all open file descriptors of this task (if any) to free file_pool resources
0x00003848       POP R5

    ; Mark this child as zombie (still exists but not runnable)
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x0000384C   LI R1 TASK_ZOMBIE
0x00003854   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00003858   LI R1 WAIT_NONE
0x00003860   STW R1 [R5 + TASK_WAIT]

    ; Wake parent if it's waiting
; macro: TASK_GET_PPID R6, R5       ; R6 = parent PID
0x00003864   LDW R6 [R5 + TASK_PPID]

    ; find parent task by PPID
0x00003868       MOV R1 R6
0x0000386C       LI R2 0                    ; Search by PID (parent's PID)
0x00003874       BL task_find               ; R1 = found parent task*
0x0000387C       CMP R1 0
0x00003880       BEQ no_parent_waiting
0x00003888       MOV R7 R1                  ; R7 = parent task*
0x0000388C       MOV R11 R2                 ; save parent task index for bitmask

    ;Check if parent is waiting for this child
; macro: TASK_GET_WAIT_CHILD R8, R7 ; Child PID that parent R7 ptr is waiting for
0x00003890   LDW R8 [R7 + TASK_WAIT_CHILD]
; macro: TASK_GET_PID R9, R5        ; This child's R5 ptr PID
0x00003894   LDW R9 [R5 + TASK_PID]

0x00003898       LI R10 -1
0x000038A0       CMP R8 R10                 ; if parent is waiting for any child (-1), then wake it up
0x000038A4       BEQ wake_parent            ;

0x000038AC       CMP R8 R9
0x000038B0       BNE no_parent_waiting      ; parent is waiting for a different child, do not wake it up

wake_parent:
    ; Find parent's task index for bitmask
    ; we already have parent task in R11

0x000038B8       LI R9 1
0x000038C0       SHL R9 R9 R11               ; bit for parent task

0x000038C4       LI R1 child_waitq
0x000038CC       MOV R2 R9
0x000038D0       BL waitq_wake_bitmask       ;unblock parent task waiting for this child

no_parent_waiting:
0x000038D8       B schedule_and_switch

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
0x000038E0       LDW R8 [SP + TF_R1]        ; R8 = pid to wait for
0x000038E4       LDW R9 [SP + TF_R2]        ; R9 = status pointer

    ; Validate status pointer
0x000038E8       CMP R9 0
0x000038EC       BEQ waitpid_validate_done
0x000038F4       MOV R1 R9
0x000038F8       LI R2 4
0x00003900       LI R3 1
0x00003908       BL user_buffer_valid_range
0x00003910       CMP R1 1
0x00003914       BNE waitpid_badptr

waitpid_validate_done:
; macro: GET_CURR_TASK_IDX R4
0x0000391C   LI R1 CURRENT_TASK
0x00003924   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003928   LI R1 TASK_SIZE
0x00003930   MUL R3 R4 R1
0x00003934   LI R5 tasks
0x0000393C   ADD R5 R5 R3
; macro: TASK_GET_PID R10, R5       ; R10 = current (parent proc) PID
0x00003940   LDW R10 [R5 + TASK_PID]

    ; if search for any child
0x00003944       LI  R2 -1
0x0000394C       CMP R8 R2
0x00003950       BNE find_child_by_pid
    ; set task_find to search for any child of this parent
0x00003958       MOV R1 R10                  ; R1 = parent PID (PPID in child task)
0x0000395C       LI  R2 1                    ; search by PPID
0x00003964       BL task_find               ; R1 = found child task*
0x0000396C       CMP R1 0
0x00003970       BEQ waitpid_no_child        ; No any child with PPID = this parent PID found
    ;R1 child task* found
0x00003978       B find_any_child_found
find_child_by_pid:
    ; Search for child task by PID
0x00003980       MOV R1 R8                  ; R1 = child PID to search for
0x00003984       LI R2 0                    ; Search by PID
0x0000398C       BL task_find               ; R1 = found child task*
0x00003994       CMP R1 0
0x00003998       BEQ waitpid_no_child        ; No such child

find_any_child_found:

0x000039A0       MOV R7 R1                   ; R7 = child task*

    ; Verify it's actually our child by its PPID fld
; macro: TASK_GET_PPID R1, R7
0x000039A4   LDW R1 [R7 + TASK_PPID]
0x000039A8       CMP R1 R10
0x000039AC       BNE waitpid_no_child
    ; R7 = child task*
    ; check its state, if ZOMBIE, we can reap it and return its exit code
; macro: TASK_GET_STATE R1, R7
0x000039B4   LDW R1 [R7 + TASK_STATE]
0x000039B8       CMP R1 TASK_ZOMBIE
0x000039BC       BEQ waitpid_reap_child

    ; Child running - block parent
; macro: TASK_GET_PID R1, R7
0x000039C4   LDW R1 [R7 + TASK_PID]
; macro: TASK_SET_WAIT_CHILD R5, R1
0x000039C8   STW R1 [R5 + TASK_WAIT_CHILD]

0x000039CC       LI R1 child_waitq           ; child_waitq ptr
0x000039D4       LI R2 WAIT_CHILD            ; reason
0x000039DC       LI R3 TASK_SLEEPING         ; state to set for current task
0x000039E4       BL waitq_prepare_sleep

0x000039EC       BL waitq_sleep_current     ; freeze the current task

    ; will resume here when child exits and wakes us up

waitpid_reap_child:
    ; Get exit code from child task
; macro: TASK_GET_EXIT_CODE R2, R7
0x000039F4   LDW R2 [R7 + TASK_EXIT_CODE]

    ; If status pointer is not NULL, write exit code to user space
0x000039F8       CMP R9 0
0x000039FC       BEQ waitpid_reap_done

0x00003A04       MOV R1 R9                  ; R1 = user status pointer
0x00003A08       MOV R4 R2                  ; preserve exit code in kernel source register
0x00003A0C       LI  R2 4                   ; R2 = size of exit code
0x00003A14       BL copy_to_user            ; write exit code to user space

waitpid_reap_done:
; macro: TASK_GET_PID R10, R7       ; get child's PID
0x00003A1C   LDW R10 [R7 + TASK_PID]
0x00003A20       MOV R1 R7                  ; R1 = child task*
0x00003A24       BL task_destroy

0x00003A2C       STW R10 [SP + TF_R1]        ; save child's PID to trapframe for return
0x00003A30       B trap_restore

waitpid_no_child:
0x00003A38       LI R1 ERR_CHILD
0x00003A40       STW R1 [SP + TF_R1]
0x00003A44       B trap_restore

waitpid_badptr:
0x00003A4C       LI R1 ERR_FAULT
0x00003A54       STW R1 [SP + TF_R1]
0x00003A58       B trap_restore

;============================================
; syscall_mkdir - create dir in a namespace
; in : R1 = path, R2 = namespace
; out : R1 = 0 succes, or error
;============================================

syscall_mkdir:
    ; R1 = user pathname
0x00003A60       LDW R8 [SP + TF_R1]
0x00003A64       LDW R9 [SP + TF_R2]
0x00003A68       MOV R1  R8
0x00003A6C       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003A74       CMP R1 0
0x00003A78       BEQ mkdir_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003A80   LI R1 CURRENT_TASK
0x00003A88   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003A8C   LI R1 TASK_SIZE
0x00003A94   MUL R3 R4 R1
0x00003A98   LI R5 tasks
0x00003AA0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003AA4   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003AA8       MOV R2 R9                  ;NS

0x00003AAC       BL vfs_mkdir

    ; R1 = 0 on success
    ; R1 < 0 on error

    ;B trap_restore

0x00003AB4       STW R1 [SP + TF_R1]     ;mkdir created exit!
0x00003AB8       B trap_restore

mkdir_fail_fault:
0x00003AC0       LI R1 ERR_FAULT
0x00003AC8       STW R1 [SP + TF_R1]     ;mkdir not created ERR todo
0x00003ACC       B trap_restore

;============================================
; syscall_rmdir - rm dir in a namespace
; in : R1 = path, R2 = namespace
; out : R1 = 0 succes, or error
;
;============================================

syscall_rmdir:
    ; R1 = user pathname
0x00003AD4       LDW R8 [SP + TF_R1]
0x00003AD8       LDW R9 [SP + TF_R2]
0x00003ADC       MOV R1  R8
0x00003AE0       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003AE8       CMP R1 0
0x00003AEC       BEQ mkdir_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003AF4   LI R1 CURRENT_TASK
0x00003AFC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003B00   LI R1 TASK_SIZE
0x00003B08   MUL R3 R4 R1
0x00003B0C   LI R5 tasks
0x00003B14   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003B18   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003B1C       MOV R2 R9                  ;NS

0x00003B20       BL vfs_rmdir

    ; R1 = 0 on success
    ; R1 < 0 on error
0x00003B28       STW R1 [SP + TF_R1]     ;mkdir created exit!
0x00003B2C       B trap_restore

rmdir_fail_fault:
0x00003B34       LI R1 ERR_FAULT
0x00003B3C       STW R1 [SP + TF_R1]     ;rmdir  not created ERR todo
0x00003B40       B trap_restore

syscall_unlink:
    ;================================================================
    ; unlink(pathname)
    ; R1 = user pathname
    ; R2 = namespace
    ; Returns:
    ;   R1 = 0       success
    ;   R1 < 0       error
    ;================================================================

0x00003B48       LDW R8 [SP + TF_R1]        ; R8 = user pathname
0x00003B4C       LDW R9 [SP + TF_R2]        ; R9 = namespace

0x00003B50       MOV R1  R8
0x00003B54       BL copy_path_from_user     ; copy pathname to kernel buffer
0x00003B5C       CMP R1 0
0x00003B60       BEQ unlink_fail_fault

; macro: GET_CURR_TASK_IDX R4
0x00003B68   LI R1 CURRENT_TASK
0x00003B70   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003B74   LI R1 TASK_SIZE
0x00003B7C   MUL R3 R4 R1
0x00003B80   LI R5 tasks
0x00003B88   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003B8C   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003B90       MOV R2 R9                  ; NS

0x00003B94       BL vfs_unlink              ; perform unlink operation

0x00003B9C       STW R1 [SP + TF_R1]        ; save result (0 or error) to trapframe
0x00003BA0       B trap_restore

unlink_fail_fault:
0x00003BA8       LI R1 ERR_FAULT
0x00003BB0       STW R1 [SP + TF_R1]     ;unlink  not created ERR todo
0x00003BB4       B trap_restore

;===============================================================
; vfs_mkdir
;
; R1 = pathname R2 = namespace
;
; Returns:
;   R1 = 0       success
;   R1 < 0       error
;===============================================================

vfs_mkdir:
0x00003BBC       PUSH LR
0x00003BC0       PUSH R8
0x00003BC4       PUSH R9

0x00003BC8       MOV R8 R1       ;pathname
0x00003BCC       MOV R9 R2       ;namespace

    ; validate pathname
0x00003BD0       MOV R1 R8
0x00003BD4       BL validate_pathname
0x00003BDC       CMP R1 0
0x00003BE0       BNE mkdir_invalid

    ; First check whether directory already exists
0x00003BE8       MOV R1 R8
0x00003BEC       BL  nsfs_lookup
0x00003BF4       CMP R1 0
0x00003BF8       BNE mkdir_exists

    ; Ask writable filesystem to create directory
0x00003C00       MOV R1 R8
0x00003C04       MOV R2 R9
0x00003C08       BL  nsfs_mkdir
    ; R1 = 0 or error
0x00003C10       cmp R1 0
0x00003C14       BNE mkdir_error

0x00003C1C       B mkdir_exit

mkdir_error:
0x00003C24       LI R1 ERR_IO
0x00003C2C       B mkdir_exit

mkdir_exists:
0x00003C34       LI R1 ERR_EXIST
0x00003C3C       B mkdir_exit

mkdir_invalid:
0x00003C44       LI R1 ERR_INVAL

mkdir_exit:
0x00003C4C       POP R9
0x00003C50       POP R8
0x00003C54       POP LR
0x00003C58       RET

;===============================================================
; vfs_rmdir - remove dir from NS
;
; R1 = pathname R2 = namespace
;
; Returns:
;   R1 = 0       success
;   R1 < 0       error
;===============================================================

vfs_rmdir:
0x00003C5C       PUSH LR
0x00003C60       PUSH R8
0x00003C64       PUSH R9

0x00003C68       MOV R8 R1       ;pathname
0x00003C6C       MOV R9 R2       ;namespace

    ; validate pathname
0x00003C70       MOV R1 R8
0x00003C74       BL validate_pathname
0x00003C7C       CMP R1 0
0x00003C80       BNE rmdir_invalid

    ; First check whether directory already exists
0x00003C88       MOV R1 R8
0x00003C8C       BL nsfs_lookup
0x00003C94       CMP R1 0
0x00003C98       BEQ rmdir_dont_exist

    ; Ask writable filesystem to rm directory
0x00003CA0       MOV R1 R8
0x00003CA4       MOV R2 R9
0x00003CA8       BL nsfs_rmdir
0x00003CB0       cmp R1 0
0x00003CB4       BNE rmdir_error
    ; R1 = 0 or error
0x00003CBC       B rmdir_exit

rmdir_error:
0x00003CC4       LI R1 ERR_IO
0x00003CCC       B rmdir_exit

rmdir_dont_exist:
0x00003CD4       LI R1 ERR_DONT_EXIST
0x00003CDC       B rmdir_exit

rmdir_invalid:
0x00003CE4       LI R1 ERR_INVAL

rmdir_exit:
0x00003CEC       POP R8
0x00003CF0       POP R9
0x00003CF4       POP LR
0x00003CF8       RET

;===============================================================
;   vfs_unlink - remove file from NS
;
;   R1 = pathname R2 = namespace
;
;   Returns:
;     R1 = 0       success
;     R1 < 0       error
;===============================================================
vfs_unlink:
0x00003CFC       PUSH LR
0x00003D00       PUSH R8
0x00003D04       PUSH R9

0x00003D08       MOV R8 R1       ;pathname
0x00003D0C       MOV R9 R2       ;namespace

    ; validate pathname
0x00003D10       MOV R1 R8
0x00003D14       BL validate_pathname
0x00003D1C       CMP R1 0
0x00003D20       BNE unlink_invalid

    ; First check whether file already exists
0x00003D28       MOV R1 R8
0x00003D2C       BL nsfs_lookup
0x00003D34       CMP R1 0
0x00003D38       BEQ unlink_dont_exist

    ; Ask writable filesystem to unlink file
0x00003D40       MOV R1 R8
0x00003D44       MOV R2 R9
0x00003D48       BL nsfs_unlink
0x00003D50       cmp R1 0
0x00003D54       BNE unlink_error
    ; R1 = 0 or error
0x00003D5C       B unlink_exit

unlink_error:
0x00003D64       LI R1 ERR_IO
0x00003D6C       B unlink_exit

unlink_dont_exist:
0x00003D74       LI R1 ERR_DONT_EXIST
0x00003D7C       B unlink_exit

unlink_invalid:
0x00003D84       LI R1 ERR_INVAL

unlink_exit:
0x00003D8C       POP R8
0x00003D90       POP R9
0x00003D94       POP LR
0x00003D98       RET

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
0x00003D9C       PUSH R5
0x00003DA0       PUSH R6
0x00003DA4       PUSH R7

0x00003DA8       MOV R5 R2                  ; Save search mode
0x00003DAC       MOV R7 R1                  ; Save PID/PPID
0x00003DB0       LI R2 0                    ; Task index
task_find_loop:
0x00003DB8       LI R3 MAX_TASKS
0x00003DC0       CMP R2 R3
0x00003DC4       BGE task_find_not_found

; macro: GET_TASK_PTR R4, R2
0x00003DCC   LI R1 TASK_SIZE
0x00003DD4   MUL R3 R2 R1
0x00003DD8   LI R4 tasks
0x00003DE0   ADD R4 R4 R3
; macro: TASK_GET_STATE R6, R4
0x00003DE4   LDW R6 [R4 + TASK_STATE]
0x00003DE8       CMP R6 TASK_DEAD
0x00003DEC       BEQ task_find_next         ; Skip dead tasks

    ; Search based on mode
0x00003DF4       CMP R5 0
0x00003DF8       BEQ task_find_by_pid

    ; Search by PPID
; macro: TASK_GET_PPID R6, R4
0x00003E00   LDW R6 [R4 + TASK_PPID]
0x00003E04       CMP R6 R7
0x00003E08       BEQ task_find_found
0x00003E10       B task_find_next

task_find_by_pid:
; macro: TASK_GET_PID R6, R4
0x00003E18   LDW R6 [R4 + TASK_PID]
0x00003E1C       CMP R6 R7
0x00003E20       BEQ task_find_found

task_find_next:
0x00003E28       ADD R2 R2 1
0x00003E2C       B task_find_loop

task_find_found:
0x00003E34       MOV R1 R4                  ; Return task pointer
0x00003E38       MOV R2 R2                  ; Return task index
0x00003E3C       POP R7
0x00003E40       POP R6
0x00003E44       POP R5
0x00003E48       RET

task_find_not_found:
0x00003E4C       LI R1 0
0x00003E54       POP R7
0x00003E58       POP R6
0x00003E5C       POP R5
0x00003E60       RET

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00003E64   LI R1 CURRENT_TASK
0x00003E6C   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003E70   LI R1 TASK_SIZE
0x00003E78   MUL R3 R2 R1
0x00003E7C   LI R5 tasks
0x00003E84   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00003E88   LDW R1 [R5 + TASK_PID]

0x00003E8C       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00003E90       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00003E98       LDW R1 [SP + TF_R1]
0x00003E9C       STW R1 [SP + TF_R1]

0x00003EA0       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00003EA8       LDW R8 [SP + TF_R1]
0x00003EAC       LDW R9 [SP + TF_R2]
0x00003EB0       MOV R1  R8
0x00003EB4       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003EBC       CMP R1 0
0x00003EC0       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003EC8   LI R1 CURRENT_TASK
0x00003ED0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003ED4   LI R1 TASK_SIZE
0x00003EDC   MUL R3 R4 R1
0x00003EE0   LI R5 tasks
0x00003EE8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003EEC   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003EF0       MOV R2 R9                  ;flags
0x00003EF4       BL vfs_open

0x00003EFC       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x00003F00       B trap_restore

open_fail_fault:
0x00003F08       LI R1 ERR_FAULT
0x00003F10       STW R1 [SP + TF_R1]     ;file not opened ERR
0x00003F14       B trap_restore


syscall_sleep:
    ;================================================================
    ; sleep(ms)
    ; R1 = milliseconds to sleep
    ;
    ; Returns:
    ;   R1 = 0 on success (slept full duration)
    ;   R1 = -1 on error (invalid time)
    ;================================================================

0x00003F1C       LDW R8 [SP + TF_R1]        ; R8 = milliseconds

0x00003F20       CMP R8 0
0x00003F24       BLE sleep_invalid          ; must be positive

; macro: GET_CURR_TASK_IDX R4
0x00003F2C   LI R1 CURRENT_TASK
0x00003F34   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003F38   LI R1 TASK_SIZE
0x00003F40   MUL R3 R4 R1
0x00003F44   LI R5 tasks
0x00003F4C   ADD R5 R5 R3

    ; Calculate wake time in PIT ticks (1 ms per tick).
0x00003F50       LI R3 timer_ticks
0x00003F58       LDW R6 [R3]                ; current ticks (1ms per tick)

    ; Convert ms to ticks: 1 tick = 1 ms
0x00003F5C       MOV R7 R8                  ; R7 = ticks to sleep

0x00003F60       ADD R6 R6 R7               ; R6 = wake time in ticks

    ; Store wake time in task struct
; macro: TASK_SET_WAKE_TIME R5, R6
0x00003F64   STW R6 [R5 + TASK_WAKE_TIME]

    ; Use existing wait queue infrastructure
0x00003F68       LI R1 sleep_waitq           ; sleep_waitq ptr
0x00003F70       LI R2 WAIT_SLEEP            ; reason
0x00003F78       LI R3 TASK_SLEEPING         ; new state (if other then blocked_io)
0x00003F80       BL waitq_prepare_sleep     ; This marks task as TASK_SLEEP and adds it to the sleep_waitq

0x00003F88       BL waitq_sleep_current     ; freeze the current task in kernel side until it is woken up by the timer interrupt handler when the wake time is reached

    ; Return 0 (will be set when woken)
0x00003F90       LI R1 0
0x00003F98       STW R1 [SP + TF_R1]
0x00003F9C       B trap_restore

sleep_invalid:
0x00003FA4       LI R1 ERR_FAULT
0x00003FAC       STW R1 [SP + TF_R1]
0x00003FB0       B trap_restore


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
0x00003FB8       PUSH LR
0x00003FBC       PUSH R5
0x00003FC0       PUSH R8
0x00003FC4       PUSH R9
0x00003FC8       PUSH R10
0x00003FCC       PUSH R11

0x00003FD0       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00003FD4   LI R1 CURRENT_TASK
0x00003FDC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003FE0   LI R1 TASK_SIZE
0x00003FE8   MUL R3 R4 R1
0x00003FEC   LI R5 tasks
0x00003FF4   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x00003FF8   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x00003FFC       PUSH R9                    ; original destination returned on success
0x00004000       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00004008       LI R11 KBUFFER_SIZE
0x00004010       CMP R10 R11
0x00004014       BGE copy_path_fail

0x0000401C       PUSH R8
0x00004020       PUSH R9
0x00004024       PUSH R10
0x00004028       MOV R1 R8
0x0000402C       LI R2 1
0x00004034       LI R3 0                    ; read access from user source
0x0000403C       BL user_buffer_valid_range
0x00004044       POP R10
0x00004048       POP R9
0x0000404C       POP R8
0x00004050       CMP R1 1
0x00004054       BNE copy_path_fail

0x0000405C       LDB R4 [R8]
0x00004060       STB R4 [R9]
0x00004064       CMP R4 0
0x00004068       BEQ copy_path_done

0x00004070       ADD R8 R8 1
0x00004074       ADD R9 R9 1
0x00004078       ADD R10 R10 1
0x0000407C       B copy_path_loop

copy_path_done:
0x00004084       POP R1                     ; original kernel path pointer

0x00004088       POP R11
0x0000408C       POP R10
0x00004090       POP R9
0x00004094       POP R8
0x00004098       POP R5
0x0000409C       POP LR
0x000040A0       RET

copy_path_fail:
0x000040A4       POP R1                     ; discard original kernel path pointer

0x000040A8       POP R11
0x000040AC       POP R10
0x000040B0       POP R9
0x000040B4       POP R8
0x000040B8       POP R5
0x000040BC       LI R1 0
0x000040C4       POP LR
0x000040C8       RET

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

0x000040CC       PUSH LR
0x000040D0       PUSH R8
0x000040D4       PUSH R9
0x000040D8       PUSH R10
0x000040DC       PUSH R11

0x000040E0       MOV R8 R1          ; kernel dst
0x000040E4       MOV R9 R2          ; user src
0x000040E8       MOV R10 R3         ; max length
0x000040EC       LI  R11 0          ; bytes copied

copy_user_loop:
    ; reached max?
0x000040F4       CMP R11 R10
0x000040F8       BGE copy_user_fail

    ; validate one byte
0x00004100       PUSH R8
0x00004104       PUSH R9
0x00004108       PUSH R10
0x0000410C       PUSH R11
0x00004110       MOV R1 R9
0x00004114       LI  R2 1
0x0000411C       LI  R3 0           ; read access
0x00004124       BL user_buffer_valid_range
0x0000412C       POP R11
0x00004130       POP R10
0x00004134       POP R9
0x00004138       POP R8
0x0000413C       CMP R1 1
0x00004140       BNE copy_user_fail

    ; copy byte
0x00004148       LDB R4 [R9]
0x0000414C       STB R4 [R8]
    ;cpy ctr
0x00004150       ADD R11 R11 1
0x00004154       CMP R4 0    ;if string ends (null)
0x00004158       BEQ copy_user_done

0x00004160       ADD R8 R8 1 ;advance
0x00004164       ADD R9 R9 1
0x00004168       B copy_user_loop
copy_user_done:
0x00004170       MOV R1 R11
0x00004174       POP R11
0x00004178       POP R10
0x0000417C       POP R9
0x00004180       POP R8
0x00004184       POP LR
0x00004188       RET
copy_user_fail:
0x0000418C       LI  R1 0
0x00004194       POP R11
0x00004198       POP R10
0x0000419C       POP R9
0x000041A0       POP R8
0x000041A4       POP LR
0x000041A8       RET

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
0x000041AC       PUSH LR
0x000041B0       PUSH R7
0x000041B4       PUSH R8
0x000041B8       PUSH R9
0x000041BC       PUSH R10

0x000041C0       MOV R8 R1                  ; save pathname ptr

0x000041C4       LI R7 device_table
0x000041CC       LI R9 DEVICE_COUNT

devfs_loop:
0x000041D4       CMP R9 0
0x000041D8       BEQ devfs_lookup_fail

    ; compare pathname with device name
0x000041E0       MOV R1 R8
0x000041E4       LDW R2 [R7 + DEV_NAME]
0x000041E8       BL strcmp
0x000041F0       CMP R1 1
0x000041F4       BEQ devfs_found

0x000041FC       ADD R7 R7 DEV_SIZE
0x00004200       SUB R9 R9 1
0x00004204       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x0000420C       BL inode_alloc
0x00004214       CMP R1 0
0x00004218       BEQ devfs_lookup_fail

0x00004220       MOV R10 R1         ; inode
    ; 2 init inode
0x00004224       LDW R2 [R7 + DEV_OPS]
0x00004228       LDW R3 [R7 + DEV_PRIVATE]
0x0000422C       LI  R4 INODE_CHAR       ; inode type for dev - char
0x00004234       LI  R5 0                ; size =0
0x0000423C       BL inode_init

0x00004244       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x00004248       POP R10
0x0000424C       POP R9
0x00004250       POP R8
0x00004254       POP R7
0x00004258       POP LR
0x0000425C       RET

devfs_lookup_fail:
0x00004260       LI R1 0
0x00004268       POP R10
0x0000426C       POP R9
0x00004270       POP R8
0x00004274       POP R7
0x00004278       POP LR
0x0000427C       RET

;====================================================================
; NSFS VFS driver
;
; NSFS is the writable overlay between devfs and tarfs:
;   devfs_lookup -> nsfs_lookup -> tarfs_lookup
;
; These methods define the ABI and struct shape. The real implementation will
; use BMI opcodes to query/create/delete entries in the host JSON KV store.
;====================================================================

;====================================================================
; nsfs_node_alloc - allocate a node from the pool
; short description:
;   This function searches for a free node in the nsfs_node_used idx array and allocates it.
;   It returns a pointer to the allocated node if successful, or 0 if no free nodes are available.
;
; Returns:
;   R1 = pointer to node if successful
;   R1 = 0 if no free nodes available
;====================================================================

nsfs_node_alloc:
0x00004280       LI R2 0                  ; R2 = node index

nsfs_node_alloc_loop:
0x00004288       CMP R2 NSFS_MAX_NODES    ;check if we reached the max number of nodes
0x0000428C       BGE nsfs_node_alloc_fail

0x00004294       SHL R3 R2 2
0x00004298       LI R4 nsfs_node_used     ;this is the base address of the idx array of used nodes
0x000042A0       ADD R4 R4 R3

0x000042A4       LDW R5 [R4]              ;R4 points to the word in the bitmap, R5 = value of that word
0x000042A8       CMP R5 0
0x000042AC       BEQ nsfs_node_alloc_found

0x000042B4       ADD R2 R2 1
0x000042B8       B nsfs_node_alloc_loop

nsfs_node_alloc_found:
0x000042C0       LI R5 1
0x000042C8       STW R5 [R4]              ; Mark the node as used in the bitmap

0x000042CC       LI R3 NSFS_NODE_SIZEOF
0x000042D4       MUL R6 R2 R3
0x000042D8       LI R1 nsfs_node_pool     ; R1 = base address of the node pool
0x000042E0       ADD R1 R1 R6             ; return pointer to the allocated node ptr=base + index * sizeof(node)
0x000042E4       RET

nsfs_node_alloc_fail:
0x000042E8       LI R1 0
0x000042F0       RET

;=====================================================================
;   nsfs_node_free - free a node back to the pool
;
;   Input R1 = idx node to free
;=====================================================================

nsfs_node_free:
0x000042F4       LI R2 nsfs_node_pool
0x000042FC       SUB R3 R1 R2

0x00004300       LI R4 NSFS_NODE_SIZEOF
0x00004308       DIV R5 R3 R4

0x0000430C       SHL R5 R5 2
0x00004310       LI R6 nsfs_node_used
0x00004318       ADD R6 R6 R5

0x0000431C       LI R7 0
0x00004324       STW R7 [R6]
0x00004328       RET

;=====================================================================
; nsfs_refresh_index - refresh the NSFS index from the host JSON KV store
;
; Fetches every namespace and rebuilds the object index and derived directory
; tables from the aggregate BMI reply.
;
; in:  R1 = ignored for compatibility with existing callers
; out: R1 = 0 on success, BMI/errno status on failure
;=====================================================================

nsfs_refresh_index:
0x0000432C       PUSH LR
0x00004330       PUSH R8
0x00004334       PUSH R9
0x00004338       PUSH R10
0x0000433C       PUSH R11
0x00004340       PUSH R12

0x00004344       MOV R12 R1

0x00004348       LI R1 NSFS_INDEX_ALL
0x00004350       LI R2 0
0x00004358       LI R3 0
0x00004360       LI R4 0
0x00004368   CALL bmi_call

0x00004370       CMP R1 0
0x00004374       BNE nsfs_refresh_done
    ; Payload: namespace_count, namespace IDs, entry_count, entries.
0x0000437C       LI R1 nsfs_index_count
0x00004384       LI R2 0
0x0000438C       STW R2 [R1]                     ;init index count to 0
0x00004390       LI R1 nsfs_index_path_next
0x00004398       LI R2 nsfs_index_path_pool
0x000043A0       STW R2 [R1]           ;init path pool next ptr to start of path pool
0x000043A4       LI R1 nsfs_dir_count
0x000043AC       LI R2 0
0x000043B4       STW R2 [R1]
0x000043B8       LI R1 nsfs_dir_index_count
0x000043C0       STW R2 [R1]

0x000043C4       LI R8 BMI_BUF_READ
0x000043CC       ADD R8 R8 BMI_HDR_SIZEOF       ; R8 = reply payload cursor
0x000043D0       LDW R9 [R8]                    ; namespace count
0x000043D4       LI R1 MAX_NSFS_NAMESPACES
0x000043DC       CMP R9 R1
0x000043E0       BGT nsfs_refresh_too_many_namespaces
0x000043E8       LI R1 nsfs_namespace_count
0x000043F0       STW R9 [R1]
0x000043F4       ADD R8 R8 4
0x000043F8       LI R10 0                       ; R10 = parsed count R8 = next is at reply payload

nsfs_refresh_namespace_loop:
0x00004400       CMP R10 R9
0x00004404       BGE nsfs_refresh_namespaces_done
0x0000440C       LI R1 nsfs_namespace_ids
0x00004414       LI R2 4
0x0000441C       MUL R2 R10 R2
0x00004420       ADD R1 R1 R2
0x00004424       LDW R2 [R8]
0x00004428       STW R2 [R1]
0x0000442C       ADD R8 R8 4
0x00004430       ADD R10 R10 1
0x00004434       B nsfs_refresh_namespace_loop

nsfs_refresh_namespaces_done:
0x0000443C       LDW R9 [R8]                    ; total entry count across namespaces
0x00004440       ADD R8 R8 4
0x00004444       LI R10 0

nsfs_refresh_loop:                 ;fill the nsfs_index_table with entries from the reply payload
0x0000444C       CMP R10 R9
0x00004450       BGE nsfs_refresh_success
0x00004458       LI R1 MAX_NSFS_INDEX_ENTRIES
0x00004460       CMP R10 R1
0x00004464       BGE nsfs_refresh_index_full

0x0000446C       LI R11 NSFS_INDEX_ENTRY_SIZEOF
0x00004474       MUL R11 R10 R11
0x00004478       LI R6 nsfs_index_table
0x00004480       ADD R11 R6 R11                 ; R11 = &nsfs_index_table[R10], R8 = &reply_payload[R8]

0x00004484       LDW R1 [R8 + NSFS_WIRE_NS]
0x00004488       STW R1 [R11 + NSFS_INDEX_NS]
0x0000448C       LDW R1 [R8 + NSFS_WIRE_TYPE]    ;copy payload wire entries to index entries elements
0x00004490       STW R1 [R11 + NSFS_INDEX_TYPE]
0x00004494       LDW R1 [R8 + NSFS_WIRE_SIZE]
0x00004498       STW R1 [R11 + NSFS_INDEX_SIZE]
0x0000449C       LDW R1 [R8 + NSFS_WIRE_VERSION]
0x000044A0       STW R1 [R11 + NSFS_INDEX_VERSION]
0x000044A4       LDW R5 [R8 + NSFS_WIRE_PATH_LEN]
0x000044A8       STW R5 [R11 + NSFS_INDEX_PATH_LEN]
0x000044AC       ADD R8 R8 NSFS_WIRE_HDR_SIZEOF  ; move R8 to the start of the path bytes in the wire payload

    ; Copy path bytes to path pool and append a NUL for strcmp.
0x000044B0       LI R6 nsfs_index_path_next    ;get next ptr in path pool blob
0x000044B8       LDW R1 [R6]
0x000044BC       STW R1 [R11 + NSFS_INDEX_PATH]; save path ptr in nsfs_index_table[] entry
0x000044C0       MOV R2 R8                     ; R2(R8) = source path ptr in wire payload
0x000044C4       MOV R3 R5               ; R3(R5) = path_len, R1 = dest path ptr in path pool blob
0x000044C8       BL memcpy               ; save path bytes to path pool blob
0x000044D0       LI R2 0
0x000044D8       STB R2 [R1]             ; append NUL to path in path pool blob
0x000044DC       ADD R1 R1 1
0x000044E0       LI R6 nsfs_index_path_next  ; update next ptr in R1 for path in path pool blob
0x000044E8       STW R1 [R6]

    ; Advance wire cursor by path_len rounded up to 4 bytes.
0x000044EC       ADD R8 R8 R5
0x000044F0       ADD R8 R8 3
0x000044F4       LI R6 0xFFFFFFFC
0x000044FC       AND R8 R8 R6

0x00004500       ADD R10 R10 1
0x00004504       B nsfs_refresh_loop

nsfs_refresh_success:
0x0000450C       LI R1 nsfs_index_count
0x00004514       STW R10 [R1]        ;update index count to parsed count
0x00004518       BL nsfs_build_dir_cache_all
0x00004520       CMP R1 0
0x00004524       BNE nsfs_refresh_done
0x0000452C       LI R1 0
0x00004534       B nsfs_refresh_done

nsfs_refresh_too_many_namespaces:
0x0000453C       LI R1 ERR_NOSPC
0x00004544       B nsfs_refresh_done

nsfs_refresh_index_full:
0x0000454C       LI R1 ERR_NOSPC

nsfs_refresh_done:
0x00004554       POP R12
0x00004558       POP R11
0x0000455C       POP R10
0x00004560       POP R9
0x00004564       POP R8
0x00004568       POP LR
0x0000456C       RET

;=====================================================================
; nsfs_lookup - lookup a pathname in the NSFS index table
; short description:
;   This function searches for a given pathname in the NSFS index table. If found,
; it allocates a new nsfs_node, initializes it with the corresponding index entry data, and then
;    allocates a new inode for the node. The inode is initialized with the nsfs_node and its type.
;
; in:  R1 = pathname
; out: R1 = inode ptr if present in NSFS overlay, or 0 if not found
;=====================================================================

nsfs_lookup:
0x00004570       PUSH LR
0x00004574       PUSH R7
0x00004578       PUSH R8
0x0000457C       PUSH R9
0x00004580       PUSH R10
0x00004584       PUSH R11
0x00004588       PUSH R12

0x0000458C       MOV R8 R1                       ; pathname
0x00004590       LI R9 nsfs_index_table          ; start of index table
0x00004598       LI R10 nsfs_index_count         ; count of items in index table
0x000045A0       LDW R10 [R10]

nsfs_lookup_loop:
0x000045A4       CMP R10 0
0x000045A8       BEQ nsfs_lookup_not_found

0x000045B0       LDW R1 [R9 + NSFS_INDEX_NS]
0x000045B4       CMP R1 NSFS_DEFAULT_NS
0x000045B8       BNE nsfs_lookup_next

0x000045C0       MOV R1 R8
0x000045C4       LDW R2 [R9 + NSFS_INDEX_PATH]
0x000045C8       BL strcmp                      ; compare pathname with index entry path
0x000045D0       CMP R1 1
0x000045D4       BEQ nsfs_lookup_found

nsfs_lookup_next:
0x000045DC       ADD R9 R9 NSFS_INDEX_ENTRY_SIZEOF
0x000045E0       SUB R10 R10 1
0x000045E4       B nsfs_lookup_loop

nsfs_lookup_found:
0x000045EC       BL nsfs_node_alloc              ; allocate a new nsfs node
0x000045F4       CMP R1 0
0x000045F8       BEQ nsfs_lookup_not_found
0x00004600       MOV R11 R1                      ; nsfs node

0x00004604       LDW R1 [R9 + NSFS_INDEX_NS]
0x00004608       STW R1 [R11 + NSFS_NODE_NAMESPACE]
    ; The index path pool is rebuilt by nsfs_refresh_index. Keep open vnode
    ; paths stable by copying each pathname into its node-owned storage.
0x0000460C       LDW R7 [R9 + NSFS_INDEX_PATH]
0x00004610       MOV R1 R7
0x00004614       BL get_path_len
0x0000461C       ADD R3 R1 1
0x00004620       MOV R2 R7
0x00004624       MOV R1 R11
0x00004628       ADD R1 R1 NSFS_NODE_PATH_BUF
0x0000462C       STW R1 [R11 + NSFS_NODE_PATH]
0x00004630       BL memcpy
0x00004638       LDW R1 [R9 + NSFS_INDEX_TYPE]
0x0000463C       CMP R1 NSFS_TYPE_DIR
0x00004640       BEQ nsfs_lookup_type_dir
0x00004648       LI R12 INODE_REG
0x00004650       B nsfs_lookup_type_done
nsfs_lookup_type_dir:
0x00004658       LI R12 INODE_DIR
nsfs_lookup_type_done:
0x00004660       STW R12 [R11 + NSFS_NODE_TYPE]  ;node type DIR or REG
0x00004664       LDW R7  [R9 + NSFS_INDEX_SIZE]
0x00004668       STW R7  [R11 + NSFS_NODE_SIZE]
    ;LDW R1 [R9 + NSFS_INDEX_PATH_LEN]
0x0000466C       LI  R1 O_RDWR ;when created we set here rd/wr should be copied from open flags normally
0x00004674       STW R1 [R11 + NSFS_NODE_FLAGS]

0x00004678       BL inode_alloc
0x00004680       CMP R1 0
0x00004684       BEQ nsfs_lookup_free_node

0x0000468C       MOV R10 R1                      ; inode
0x00004690       LI  R2 nsfs_ops                 ; nsfs ops table
0x00004698       MOV R3 R11                      ; nsfs node as inode_private data
0x0000469C       MOV R4 R12                      ; inode type (DIR or REG)
0x000046A0       MOV R5 R7                       ; file size.
0x000046A4       BL inode_init
0x000046AC       MOV R1 R10
0x000046B0       B nsfs_lookup_done

nsfs_lookup_free_node:
0x000046B8       MOV R1 R11
0x000046BC       BL nsfs_node_free

nsfs_lookup_not_found:
0x000046C4       LI R1 0

nsfs_lookup_done:
0x000046CC       POP R12
0x000046D0       POP R11
0x000046D4       POP R10
0x000046D8       POP R9
0x000046DC       POP R8
0x000046E0       POP R7
0x000046E4       POP LR
0x000046E8       RET
;=====================================================================
; nsfs_open - open a file in the NSFS overlay
; in:  R1 = file ptr
; out: R1 = 0
;=====================================================================

nsfs_open:
0x000046EC       LI R1 0
0x000046F4       RET
;=====================================================================
; nsfs_close
; in:  R1 = file ptr
; out: R1 = 0
;=====================================================================

nsfs_close:
0x000046F8       LI R1 0
0x00004700       RET

;=====================================================================
; nsfs_read
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;=====================================================================

nsfs_read:
0x00004704       PUSH LR
0x00004708       PUSH R8
0x0000470C       PUSH R9
0x00004710       PUSH R10
0x00004714       PUSH R11
0x00004718       PUSH R12

0x0000471C       MOV R8 R1
0x00004720       MOV R9 R2
0x00004724       MOV R10 R3

0x00004728       CMP R10 0
0x0000472C       BEQ nsfs_read_eof

0x00004734       PUSH R8
0x00004738       PUSH R9
0x0000473C       MOV R1 R9
0x00004740       MOV R2 R10
0x00004744       LI R3 1                    ; destination must be user-writable
0x0000474C       BL user_buffer_valid_range
0x00004754       POP R9
0x00004758       POP R8
0x0000475C       CMP R1 1
0x00004760       BNE nsfs_read_fault

0x00004768       LDW R11 [R8 + FILE_INODE]
0x0000476C       LDW R5  [R11 + INODE_TYPE]
0x00004770       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x00004774       LI  R2 INODE_DIR
0x0000477C       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x00004780       BEQ nsfs_read_dir

0x00004788       LDW R12 [R8 + FILE_OFFSET]
0x0000478C       LDW R4  [R11 + NSFS_NODE_SIZE]

0x00004790       CMP R12 R4
0x00004794       BGEU nsfs_read_eof

0x0000479C       SUB R4 R4 R12             ; bytes remaining
0x000047A0       CMP R10 R4
0x000047A4       BLEU nsfs_read_count_ready
0x000047AC       MOV R10 R4

nsfs_read_count_ready:

;read file from nsfs
; call bmi_read_file with the file's index and offset to get the data from the host
0x000047B0       MOV R1 R11                ; NSFS node
0x000047B4       MOV R2 R12                ; file offset
0x000047B8       MOV R3 R10                ; clipped read length
0x000047BC       MOV R4 R9                 ; user destination
0x000047C0       BL  nsfs_bmi_read_file
0x000047C8       CMP R1 0
0x000047CC       BLT nsfs_read_done

0x000047D4       ADD R12 R12 R1
0x000047D8       STW R12 [R8 + FILE_OFFSET]
0x000047DC       B nsfs_read_done

nsfs_read_dir:
    ; directory read – call our dir read function
0x000047E4       MOV R1 R8
0x000047E8       MOV R2 R9
0x000047EC       MOV R3 R10
0x000047F0       BL nsfs_readdir
0x000047F8       B nsfs_read_done   ; jump to the common return path

nsfs_read_fault:
0x00004800       LI R1 ERR_FAULT
0x00004808       B nsfs_read_done

nsfs_read_eof:
0x00004810       LI R1 0

nsfs_read_done:
0x00004818       POP R12
0x0000481C       POP R11
0x00004820       POP R10
0x00004824       POP R9
0x00004828       POP R8
0x0000482C       POP LR
0x00004830       RET

nsfs_bmi_read_file:
    ;=====================================================================
    ; bmi_read_file - read file data from the host via BMI
    ; in:  R1 = nsfs node, R2 = offset, R3 = length, R4 = user destination
    ; out: R1 = bytes read or errno
    ;=====================================================================
0x00004834       PUSH LR
0x00004838       PUSH R8
0x0000483C       PUSH R9
0x00004840       PUSH R10
0x00004844       PUSH R11
0x00004848       PUSH R12

0x0000484C       MOV R8 R1              ; nsfs node
0x00004850       MOV R9 R2              ; offset
0x00004854       MOV R10 R3             ; length
0x00004858       MOV R11 R4             ; current user destination
0x0000485C       LI R12 0               ; total bytes copied

bmi_read_file_loop:
0x00004864       CMP R10 0
0x00004868       BEQ bmi_read_file_done

0x00004870       LI R7 BMI_BUF_WRITE
0x00004878       ADD R7 R7 BMI_HDR_SIZEOF
0x0000487C       LDW R1 [R8 + NSFS_NODE_PATH]
0x00004880       BL get_path_len
0x00004888       MOV R6 R1                          ; path_len
0x0000488C       STW R6 [R7]                        ; u32 path_len
0x00004890       STW R9 [R7 + 4]                    ; u32 offset

0x00004894       LI R5 4084                         ; max BMI reply payload = 4096 - header
0x0000489C       CMP R10 R5
0x000048A0       BLEU bmi_read_file_chunk_ready
0x000048A8       B bmi_read_file_chunk_store
bmi_read_file_chunk_ready:
0x000048B0       MOV R5 R10
bmi_read_file_chunk_store:
0x000048B4       STW R5 [R7 + 8]                    ; u32 requested length

0x000048B8       ADD R1 R7 12
0x000048BC       LDW R2 [R8 + NSFS_NODE_PATH]
0x000048C0       MOV R3 R6
0x000048C4       BL memcpy

0x000048CC       LI R1 BMI_READ_FILE
0x000048D4       MOV R2 R7
0x000048D8       ADD R3 R6 12
0x000048DC       LDW R4 [R8 + NSFS_NODE_NAMESPACE]
0x000048E0   CALL bmi_call
0x000048E8       CMP R1 0
0x000048EC       BNE bmi_read_file_fail

0x000048F4       LI R4 BMI_BUF_READ
0x000048FC       LDW R5 [R4 + BMI_HDR_PAYLOAD_LEN]  ; actual bytes returned
0x00004900       CMP R5 0
0x00004904       BEQ bmi_read_file_done
0x0000490C       ADD R4 R4 BMI_HDR_SIZEOF
0x00004910       MOV R1 R11
0x00004914       MOV R2 R5
0x00004918       BL copy_to_user

0x00004920       ADD R12 R12 R1
0x00004924       ADD R9 R9 R1
0x00004928       ADD R11 R11 R1
0x0000492C       SUB R10 R10 R1
0x00004930       CMP R1 R5
0x00004934       BNE bmi_read_file_done
0x0000493C       B bmi_read_file_loop

bmi_read_file_done:
0x00004944       MOV R1 R12
0x00004948       POP R12
0x0000494C       POP R11
0x00004950       POP R10
0x00004954       POP R9
0x00004958       POP R8
0x0000495C       POP LR
0x00004960       RET

bmi_read_file_fail:
0x00004964       LI  R1 ERR_IO
0x0000496C       POP R12
0x00004970       POP R11
0x00004974       POP R10
0x00004978       POP R9
0x0000497C       POP R8
0x00004980       POP LR
0x00004984       RET
;=====================================================================
; nsfs_write
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes written or errno
;=====================================================================
nsfs_write:
0x00004988       PUSH LR
0x0000498C       PUSH R6
0x00004990       PUSH R7
0x00004994       PUSH R8
0x00004998       PUSH R9
0x0000499C       PUSH R10
0x000049A0       PUSH R11
0x000049A4       PUSH R12

0x000049A8       MOV R8 R1                  ; file*
0x000049AC       MOV R9 R2                  ; current user source
0x000049B0       MOV R10 R3                 ; bytes remaining
0x000049B4       LI R11 0                   ; total bytes written

0x000049BC       CMP R10 0
0x000049C0       BEQ nsfs_write_done

0x000049C8       LDW R12 [R8 + FILE_INODE]
0x000049CC       LDW R1 [R12 + INODE_TYPE]
0x000049D0       LI R2 INODE_DIR
0x000049D8       CMP R1 R2
0x000049DC       BEQ nsfs_write_isdir

0x000049E4       LDW R12 [R12 + INODE_PRIVATE]      ; nsfs node
0x000049E8       CMP R12 0
0x000049EC       BEQ nsfs_write_io

0x000049F4       LDW R1 [R12 + NSFS_NODE_PATH]
0x000049F8       BL get_path_len
0x00004A00       MOV R6 R1                          ; path_len

0x00004A04       LI R2 KBUFFER_SIZE
0x00004A0C       SUB R2 R2 4
0x00004A10       CMP R6 R2
0x00004A14       BGE nsfs_write_inval

nsfs_write_loop:
0x00004A1C       CMP R10 0
0x00004A20       BEQ nsfs_write_done

    ; chunk = min(remaining, KBUFFER_SIZE - 4 - path_len)
0x00004A28       LI R7 KBUFFER_SIZE
0x00004A30       SUB R7 R7 4
0x00004A34       SUB R7 R7 R6
0x00004A38       CMP R10 R7
0x00004A3C       BGT nsfs_write_chunk_ready
0x00004A44       MOV R7 R10
nsfs_write_chunk_ready:

0x00004A48       MOV R1 R9
0x00004A4C       MOV R2 R7
0x00004A50       LI R3 0                            ; read from user source
0x00004A58       BL user_buffer_valid_range
0x00004A60       CMP R1 1
0x00004A64       BNE nsfs_write_fault

; macro: GET_CURR_TASK_IDX R4
0x00004A6C   LI R1 CURRENT_TASK
0x00004A74   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004A78   LI R1 TASK_SIZE
0x00004A80   MUL R3 R4 R1
0x00004A84   LI R5 tasks
0x00004A8C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5            ; payload buffer
0x00004A90   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00004A94       STW R6 [R4]                        ; u32 path_len

0x00004A98       MOV R1 R4
0x00004A9C       ADD R1 R1 4
0x00004AA0       LDW R2 [R12 + NSFS_NODE_PATH]
0x00004AA4       MOV R3 R6
0x00004AA8       BL memcpy

; macro: GET_CURR_TASK_IDX R4
0x00004AB0   LI R1 CURRENT_TASK
0x00004AB8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004ABC   LI R1 TASK_SIZE
0x00004AC4   MUL R3 R4 R1
0x00004AC8   LI R5 tasks
0x00004AD0   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00004AD4   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00004AD8       ADD R4 R4 4
0x00004ADC       ADD R4 R4 R6                       ; data destination
0x00004AE0       MOV R1 R9
0x00004AE4       MOV R2 R7
0x00004AE8       BL copy_from_user
0x00004AF0       CMP R1 R7
0x00004AF4       BNE nsfs_write_fault

; macro: GET_CURR_TASK_IDX R4
0x00004AFC   LI R1 CURRENT_TASK
0x00004B04   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004B08   LI R1 TASK_SIZE
0x00004B10   MUL R3 R4 R1
0x00004B14   LI R5 tasks
0x00004B1C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R2, R5            ; bmi payload source
0x00004B20   LDW R2 [R5 + TASK_KBUF_WR_PTR]
0x00004B24       MOV R1 FILE_APPEND
0x00004B28       ADD R3 R7 R6
0x00004B2C       ADD R3 R3 4
0x00004B30       LDW R4 [R12 + NSFS_NODE_NAMESPACE]
0x00004B34   CALL bmi_call
0x00004B3C       CMP R1 0
0x00004B40       BNE nsfs_write_io

0x00004B48       ADD R11 R11 R7
0x00004B4C       ADD R9 R9 R7
0x00004B50       SUB R10 R10 R7

0x00004B54       LDW R1 [R8 + FILE_OFFSET]
0x00004B58       ADD R1 R1 R7
0x00004B5C       STW R1 [R8 + FILE_OFFSET]
0x00004B60       LDW R1 [R12 + NSFS_NODE_SIZE]
0x00004B64       ADD R1 R1 R7
0x00004B68       STW R1 [R12 + NSFS_NODE_SIZE]

0x00004B6C       B nsfs_write_loop

nsfs_write_done:
0x00004B74       LI R1 NSFS_DEFAULT_NS
0x00004B7C       BL nsfs_refresh_index
0x00004B84       MOV R1 R11
0x00004B88       B nsfs_write_return

nsfs_write_fault:
0x00004B90       LI R1 ERR_FAULT
0x00004B98       B nsfs_write_return

nsfs_write_isdir:
0x00004BA0       LI R1 ERR_ISDIR
0x00004BA8       B nsfs_write_return

nsfs_write_inval:
0x00004BB0       LI R1 ERR_INVAL
0x00004BB8       B nsfs_write_return

nsfs_write_io:
0x00004BC0       LI R1 ERR_IO

nsfs_write_return:
0x00004BC8       POP R12
0x00004BCC       POP R11
0x00004BD0       POP R10
0x00004BD4       POP R9
0x00004BD8       POP R8
0x00004BDC       POP R7
0x00004BE0       POP R6
0x00004BE4       POP LR
0x00004BE8       RET
;=====================================================================
; nsfs_readdir - read next directory entries from NSFS overlay
; in:  R1 = file ptr, R2 = userspace dirent buffer
; out: R1 = 1 entry, 0 EOF, or errno
;=====================================================================
nsfs_readdir:
0x00004BEC       PUSH LR
0x00004BF0       PUSH R8
0x00004BF4       PUSH R9
0x00004BF8       PUSH R10
0x00004BFC       PUSH R11
0x00004C00       PUSH R12

0x00004C04       MOV R8 R2              ; R8 = userspace dirent buffer ptr
0x00004C08       PUSH R8
0x00004C0C       MOV R12 R1             ; R12 = file ptr

0x00004C10       LI R3 DIRENT_SIZEOF
0x00004C18       MOV R1 R8
0x00004C1C       LI R2 DIRENT_SIZEOF
0x00004C24       LI R3 1
0x00004C2C       BL user_buffer_valid_range
0x00004C34       CMP R1 1
0x00004C38       BNE nsfs_readdir_fault

0x00004C40       LDW R4 [R12 + FILE_INODE]
0x00004C44       LDW R5 [R4 + INODE_PRIVATE]
0x00004C48       CMP R5 0
0x00004C4C       BEQ nsfs_readdir_eof_no_node
0x00004C54       LDW R10 [R5 + NSFS_NODE_NAMESPACE]
0x00004C58       LDW R2 [R5 + NSFS_NODE_PATH]
0x00004C5C       MOV R1 R10
0x00004C60       BL nsfs_find_dir_id
0x00004C68       LI R2 -1
0x00004C70       CMP R1 R2
0x00004C74       BEQ nsfs_readdir_invalid_dir
0x00004C7C       MOV R9 R1
0x00004C80       LDW R11 [R12 + FILE_OFFSET]

nsfs_readdir_scan:
0x00004C84       LI R1 nsfs_dir_index_count
0x00004C8C       LDW R1 [R1]
0x00004C90       CMP R11 R1
0x00004C94       BGE nsfs_readdir_eof

0x00004C9C       LI R7 NSFS_DIR_IDX_SIZEOF
0x00004CA4       MUL R7 R11 R7
0x00004CA8       LI R6 nsfs_dir_index
0x00004CB0       ADD R7 R6 R7

0x00004CB4       LDW R1 [R7 + NSFS_DIR_IDX_NS]
0x00004CB8       CMP R1 R10
0x00004CBC       BNE nsfs_readdir_next
0x00004CC4       LDW R1 [R7 + NSFS_DIR_IDX_PARENT]
0x00004CC8       CMP R1 R9
0x00004CCC       BNE nsfs_readdir_next

0x00004CD4       LDW R8 [R7 + NSFS_DIR_IDX_INDEX]

; macro: GET_CURR_TASK_IDX R4
0x00004CD8   LI R1 CURRENT_TASK
0x00004CE0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004CE4   LI R1 TASK_SIZE
0x00004CEC   MUL R3 R4 R1
0x00004CF0   LI R5 tasks
0x00004CF8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00004CFC   LDW R1 [R5 + TASK_KBUF_WR_PTR]

0x00004D00       LI R3 NSFS_INDEX_ENTRY_SIZEOF
0x00004D08       MUL R3 R8 R3
0x00004D0C       LI R6 nsfs_index_table
0x00004D14       ADD R3 R6 R3

0x00004D18       MOV R2 R8
0x00004D1C       ADD R2 R2 1
0x00004D20       STW R2 [R1 + DIRENT_INODE]
0x00004D24       LDW R2 [R3 + NSFS_INDEX_SIZE]
0x00004D28       STW R2 [R1 + DIRENT_SIZE]
0x00004D2C       LDW R2 [R7 + NSFS_DIR_IDX_TYPE]
0x00004D30       CMP R2 NSFS_TYPE_DIR
0x00004D34       BEQ nsfs_readdir_type_dir
0x00004D3C       LI R2 DT_REG
0x00004D44       B nsfs_readdir_type_done
nsfs_readdir_type_dir:
0x00004D4C       LI R2 DT_DIR
nsfs_readdir_type_done:
0x00004D54       STW R2 [R1 + DIRENT_TYPE]

0x00004D58       ADD R2 R11 1
0x00004D5C       STW R2 [R12 + FILE_OFFSET]

0x00004D60       LDW R2 [R7 + NSFS_DIR_IDX_NAME]
0x00004D64       ADD R3 R1 DIRENT_NAME
0x00004D68       LI R6 0
nsfs_readdir_copy_name:
0x00004D70       CMP R6 63
0x00004D74       BGE nsfs_readdir_copy_done
0x00004D7C       LDB R5 [R2 + R6]
0x00004D80       CMP R5 0
0x00004D84       BEQ nsfs_readdir_copy_done
0x00004D8C       CMP R5 47
0x00004D90       BEQ nsfs_readdir_copy_done
0x00004D98       STB R5 [R3 + R6]
0x00004D9C       ADD R6 R6 1
0x00004DA0       B nsfs_readdir_copy_name
nsfs_readdir_copy_done:
0x00004DA8       LI R5 0
0x00004DB0       STB R5 [R3 + R6]

0x00004DB4       LI R2 DIRENT_SIZEOF
0x00004DBC       MOV R4 R1
0x00004DC0       POP R1
0x00004DC4       BL copy_to_user
0x00004DCC       CMP R1 DIRENT_SIZEOF
0x00004DD0       BNE nsfs_readdir_fault_after_pop
0x00004DD8       MOV R1 DIRENT_SIZEOF
0x00004DDC       POP R12
0x00004DE0       POP R11
0x00004DE4       POP R10
0x00004DE8       POP R9
0x00004DEC       POP R8
0x00004DF0       POP LR
0x00004DF4       RET

nsfs_readdir_next:
0x00004DF8       ADD R11 R11 1
0x00004DFC       B nsfs_readdir_scan

nsfs_readdir_eof:
0x00004E04       STW R11 [R12 + FILE_OFFSET]

nsfs_readdir_eof_no_node:
0x00004E08       POP R1
0x00004E0C       LI R1 0
0x00004E14       POP R12
0x00004E18       POP R11
0x00004E1C       POP R10
0x00004E20       POP R9
0x00004E24       POP R8
0x00004E28       POP LR
0x00004E2C       RET

nsfs_readdir_invalid_dir:
0x00004E30       POP R1
0x00004E34       LI R1 ERR_INVAL
0x00004E3C       POP R12
0x00004E40       POP R11
0x00004E44       POP R10
0x00004E48       POP R9
0x00004E4C       POP R8
0x00004E50       POP LR
0x00004E54       RET

nsfs_readdir_fault:
0x00004E58       POP R1
nsfs_readdir_fault_after_pop:
0x00004E5C       LI R1 ERR_FAULT
0x00004E64       POP R12
0x00004E68       POP R11
0x00004E6C       POP R10
0x00004E70       POP R9
0x00004E74       POP R8
0x00004E78       POP LR
0x00004E7C       RET
;=====================================================================
; nsfs_create - create a new file in the NSFS overlay
; in:  R1 = pathname, R2 = mode/type flags, R3 namespace (in future, for now we use default namespace only)
; out: R1 = inode ptr if created, or errno
;=====================================================================
nsfs_create:
0x00004E80       PUSH LR
0x00004E84       PUSH R6
0x00004E88       PUSH R8
0x00004E8C       PUSH R9
0x00004E90       PUSH R10
0x00004E94       MOV  R8  R1
0x00004E98       MOV  R9  R2
0x00004E9C       MOV  R10 R3
0x00004EA0       LI   R10 NSFS_DEFAULT_NS         ; Defaut NS for now
  ;  MOV  R6  R10                      ; namespace
    ; TODO: FILE_CREATE over BMI, then nsfs_lookup can materialize inode.
0x00004EA8       MOV  R2  R8                       ; R2 = pathname
0x00004EAC       BL   get_path_len                 ; get length of the pathname string
0x00004EB4       mov  R3 R1                        ; R3 = length of the pathname string
    ; create a new nsfs_node and add it to the index table, then call nsfs_lookup to get the inode
0x00004EB8       MOV  R1 FILE_CREATE              ;opcode FILE_CREATE
0x00004EBC       MOV  R4 R10                        ; at this time we work with default namespace only
0x00004EC0   CALL bmi_call
    ;check bmi_call return status
0x00004EC8       CMP  R1 0
0x00004ECC       BNE  nsfs_create_fail
    ; refresh the index table
0x00004ED4       MOV R1 R10                        ; at this time we work with default namespace only
0x00004ED8       BL nsfs_refresh_index
0x00004EE0       CMP R1 0
0x00004EE4       BNE nsfs_create_fail
    ;file created, now lookup the new file in the index table to get its inode
0x00004EEC       MOV R1 R8
    ; find file and create inode for the newly created file
0x00004EF0       BL nsfs_lookup
0x00004EF8       cmp R1 0
0x00004EFC       BEQ nsfs_create_fail
    ;inode found, return inode ptr in R1
0x00004F04       POP R10
0x00004F08       POP R9
0x00004F0C       POP R8
0x00004F10       POP R6
0x00004F14       POP LR
0x00004F18       RET

nsfs_create_fail:
0x00004F1C       LI R1 ERR_NOENT
0x00004F24       POP R10
0x00004F28       POP R9
0x00004F2C       POP R8
0x00004F30       POP R6
0x00004F34       POP LR
0x00004F38       RET

;=====================================================================
; get_path_len - get length of a NUL-terminated string
; in:  R1 = pointer to string
; out: R1 = length of string (not including NUL)
;=====================================================================
get_path_len:
0x00004F3C       PUSH LR
0x00004F40       PUSH R2
0x00004F44       PUSH R3
0x00004F48       LI R2 0
get_path_len_loop:
0x00004F50       LDB R3 [R1 + R2]
0x00004F54       CMP R3 0
0x00004F58       BEQ get_path_len_done
0x00004F60       ADD R2 R2 1
0x00004F64       B get_path_len_loop
get_path_len_done:
0x00004F6C       MOV R1 R2
0x00004F70       POP R3
0x00004F74       POP R2
0x00004F78       POP LR
0x00004F7C       RET

;=====================================================================
; nsfs_unlink - remove a file from the NSFS overlay
; in:  R1 = pathname R3 = NS
; out: R1 = 0 or errno
;=====================================================================

nsfs_unlink:
0x00004F80       PUSH LR
0x00004F84       PUSH R6
0x00004F88       PUSH R8
0x00004F8C       PUSH R9
0x00004F90       PUSH R10
0x00004F94       MOV  R8  R1
0x00004F98       MOV  R9  R2
0x00004F9C       MOV  R10 R3
0x00004FA0       LI   R10 NSFS_DEFAULT_NS         ; Defaut NS for now
    ; TODO: FILE_DELETE over BMI and create whiteout when shadowing tarfs.
    ; in future
0x00004FA8       MOV  R2  R8                       ; R2 = pathname
0x00004FAC       BL   get_path_len                 ; get length of the pathname string
0x00004FB4       mov  R3 R1                        ; R3 = length of the pathname string
    ; bmi_call removes the object from the host JSON KV store.
    ; After nsfs_refresh_index, nsfs_lookup will no longer find it.
0x00004FB8       MOV  R1 FILE_DELETE              ;opcode FILE_DELETE
0x00004FBC       MOV  R4 R10                        ; at this time we work with default namespace only
0x00004FC0   CALL bmi_call
    ;check bmi_call return status
0x00004FC8       CMP  R1 0
0x00004FCC       BNE  nsfs_unlink_fail
    ; refresh the index table
0x00004FD4       MOV R1 R10                        ; at this time we work with default namespace only
0x00004FD8       BL nsfs_refresh_index
0x00004FE0       CMP R1 0
0x00004FE4       BNE nsfs_unlink_fail
    ;file deleted we done here now lookup is needed
0x00004FEC       POP R10
0x00004FF0       POP R9
0x00004FF4       POP R8
0x00004FF8       POP R6
0x00004FFC       POP LR
0x00005000       RET

nsfs_unlink_fail:
0x00005004       LI R1 ERR_NOENT
0x0000500C       POP R10
0x00005010       POP R9
0x00005014       POP R8
0x00005018       POP R6
0x0000501C       POP LR
0x00005020       RET

;=====================================================================
; nsfs_mkdir - create a new directory in the NSFS overlay
;
; in:  R1 = pathname
;      R2 = namespace
;
; out: R1 = 0 successful lookup - success, or errno
;=====================================================================

nsfs_mkdir:
0x00005024       PUSH LR
0x00005028       PUSH R6
0x0000502C       PUSH R8
0x00005030       PUSH R9
0x00005034       PUSH R10

0x00005038       MOV R8  R1                  ; pathname
0x0000503C       MOV R10 R2                 ; namespace

0x00005040       LI  R10 NSFS_DEFAULT_NS    ; default namespace for now

0x00005048       MOV R2 R8
0x0000504C       BL  get_path_len

0x00005054       MOV R3 R1
0x00005058       LI  R1 DIR_CREATE
0x00005060       MOV R4 R10
0x00005064   CALL bmi_call
0x0000506C       CMP R1 0
0x00005070       BNE nsfs_mkdir_fail

0x00005078       MOV R1 R10
0x0000507C       BL  nsfs_refresh_index
0x00005084       CMP R1 0
0x00005088       BNE nsfs_mkdir_fail

   ; probably we dont need to search for created dir if bmi_call and refresh are success
   ; MOV R1 R8
   ; BL  nsfs_lookup
   ; CMP R1 0
   ; BEQ nsfs_mkdir_fail

0x00005090       POP R10
0x00005094       POP R9
0x00005098       POP R8
0x0000509C       POP R6
0x000050A0       POP LR
0x000050A4       RET

nsfs_mkdir_fail:
0x000050A8       LI R1 ERR_NOENT
0x000050B0       POP R10
0x000050B4       POP R9
0x000050B8       POP R8
0x000050BC       POP R6
0x000050C0       POP LR
0x000050C4       RET

;=========================================================
; nsfs_rmdir
; in:  R1 = pathname R2 = NS
; out: R1 = 0 or errno
;=========================================================
nsfs_rmdir:
0x000050C8       PUSH LR
0x000050CC       PUSH R6
0x000050D0       PUSH R8
0x000050D4       PUSH R9
0x000050D8       PUSH R10

0x000050DC       MOV R8 R1                  ; pathname
0x000050E0       MOV R10 R2                 ; namespace

0x000050E4       LI  R10 NSFS_DEFAULT_NS    ; default namespace for now

0x000050EC       MOV R2 R8
0x000050F0       BL  get_path_len
0x000050F8       MOV R3 R1

0x000050FC       LI  R1 DIR_DELETE
0x00005104       MOV R4 R10

0x00005108   CALL bmi_call

0x00005110       CMP R1 0
0x00005114       BNE nsfs_rmdir_fail

0x0000511C       MOV R1 R10
0x00005120       BL  nsfs_refresh_index

0x00005128       CMP R1 0
0x0000512C       BNE nsfs_rmdir_fail
    ; R1 = 0 here
    ; we dont need to make extra nsfs_lookup call here
    ;as we just deleted the directory and we dont need
    ;to return inode ptr for it
  ;  MOV R1 R8
  ;  BL  nsfs_lookup

  ;  CMP R1 0
  ;  BNE nsfs_rmdir_fail

0x00005134       POP R10
0x00005138       POP R9
0x0000513C       POP R8
0x00005140       POP R6
0x00005144       POP LR
0x00005148       RET

nsfs_rmdir_fail:
0x0000514C       LI R1 ERR_NOENT
0x00005154       POP R10
0x00005158       POP R9
0x0000515C       POP R8
0x00005160       POP R6
0x00005164       POP LR
0x00005168       RET

;=====================================================================
; nsfs_build_dir_cache_all
;
; Build the derived NSFS directory table and child index from the object
; index. This mirrors the TARFS dir_table/dir_index design: lookup keeps
; using nsfs_index_table, while readdir walks immediate children instead of
; reparsing path strings on every call.
;
; out: R1 = 0
;=====================================================================
nsfs_build_dir_cache_all:
0x0000516C       PUSH LR
0x00005170       PUSH R8
0x00005174       PUSH R9
0x00005178       PUSH R10
0x0000517C       PUSH R11
0x00005180       PUSH R12

    ; Rebuild from scratch so deleted/changed entries cannot leave stale IDs.
    ; Directory IDs are array indices; child entries store those IDs as parents.
0x00005184       LI R1 nsfs_dir_count
0x0000518C       LI R2 0
0x00005194       STW R2 [R1]
0x00005198       LI R1 nsfs_dir_index_count
0x000051A0       LI R2 0
0x000051A8       STW R2 [R1]

    ; Seed the default root even when the namespace has no indexed objects.
    ; The namespace loop below adds one root per reported namespace; the
    ; duplicate default root is ignored by nsfs_add_dir_to_cache.
0x000051AC       LI R1 NSFS_DEFAULT_NS
0x000051B4       LI R2 nsfs_root_path
0x000051BC       BL nsfs_add_dir_to_cache
0x000051C4       LI R2 -1
0x000051CC       CMP R1 R2
0x000051D0       BEQ nsfs_build_dir_cache_full

    ; Add roots first so every namespace has a parent for top-level objects.
0x000051D8       LI R8 0

nsfs_build_root_loop:
0x000051E0       LI R1 nsfs_namespace_count
0x000051E8       LDW R1 [R1]
0x000051EC       CMP R8 R1
0x000051F0       BGE nsfs_build_dir_table_start

    ; R8 is the namespace_ids[] index; each call either finds the existing
    ; root or appends it and returns its directory ID in R1.
0x000051F8       LI R1 nsfs_namespace_ids
0x00005200       LI R2 4
0x00005208       MUL R2 R8 R2
0x0000520C       ADD R1 R1 R2
0x00005210       LDW R1 [R1]
0x00005214       LI R2 nsfs_root_path
0x0000521C       BL nsfs_add_dir_to_cache
0x00005224       LI R2 -1
0x0000522C       CMP R1 R2
0x00005230       BEQ nsfs_build_dir_cache_full
0x00005238       ADD R8 R8 1
0x0000523C       B nsfs_build_root_loop

nsfs_build_dir_table_start:
    ; Add every explicitly indexed directory before building child links.
    ; R8 is the object index and R9 points at nsfs_index_table[R8].
0x00005244       LI R8 0                            ; object index number
0x0000524C       LI R9 nsfs_index_table

nsfs_build_dir_table_loop:
0x00005254       LI R1 nsfs_index_count
0x0000525C       LDW R1 [R1]
0x00005260       CMP R8 R1
0x00005264       BGE nsfs_build_child_index_start

0x0000526C       LDW R1 [R9 + NSFS_INDEX_TYPE]
0x00005270       CMP R1 NSFS_TYPE_DIR
0x00005274       BNE nsfs_build_dir_table_next

0x0000527C       LDW R1 [R9 + NSFS_INDEX_NS]
0x00005280       LDW R2 [R9 + NSFS_INDEX_PATH]
0x00005284       BL nsfs_add_dir_to_cache
0x0000528C       LI R2 -1
0x00005294       CMP R1 R2
0x00005298       BEQ nsfs_build_dir_cache_full

nsfs_build_dir_table_next:
0x000052A0       ADD R9 R9 NSFS_INDEX_ENTRY_SIZEOF
0x000052A4       ADD R8 R8 1
0x000052A8       B nsfs_build_dir_table_loop

nsfs_build_child_index_start:
    ; For each indexed object, resolve its immediate parent and append one
    ; child record. R8 remains the object's index for NSFS_DIR_IDX_INDEX.
0x000052B0       LI R8 0
0x000052B8       LI R9 nsfs_index_table

nsfs_build_child_index_loop:
0x000052C0       LI R1 nsfs_index_count
0x000052C8       LDW R1 [R1]
0x000052CC       CMP R8 R1
0x000052D0       BGE nsfs_build_dir_cache_done

0x000052D8       LDW R1 [R9 + NSFS_INDEX_NS]
0x000052DC       LDW R2 [R9 + NSFS_INDEX_PATH]
0x000052E0       BL nsfs_find_parent_dir

0x000052E8       LI R4 -1
0x000052F0       CMP R1 R4
0x000052F4       BEQ nsfs_build_child_index_next

    ; R1 = parent dir ID, R2 = basename pointer, R3 = NSFS file/dir type.
0x000052FC       MOV R10 R1
0x00005300       LDW R11 [R9 + NSFS_INDEX_NS]
0x00005304       LI R4 nsfs_dir_index_count
0x0000530C       LDW R5 [R4]
0x00005310       LI R1 MAX_NSFS_DIR_ENTRIES
0x00005318       CMP R5 R1
0x0000531C       BGE nsfs_build_dir_cache_full

0x00005324       LI R6 NSFS_DIR_IDX_SIZEOF
0x0000532C       MUL R6 R5 R6
0x00005330       LI R7 nsfs_dir_index
0x00005338       ADD R7 R7 R6
0x0000533C       STW R11 [R7 + NSFS_DIR_IDX_NS]
0x00005340       STW R10 [R7 + NSFS_DIR_IDX_PARENT]
0x00005344       STW R2  [R7 + NSFS_DIR_IDX_NAME]
0x00005348       STW R8  [R7 + NSFS_DIR_IDX_INDEX]
0x0000534C       STW R3  [R7 + NSFS_DIR_IDX_TYPE]
0x00005350       ADD R5 R5 1
0x00005354       STW R5 [R4]

nsfs_build_child_index_next:
0x00005358       ADD R9 R9 NSFS_INDEX_ENTRY_SIZEOF ;current index entry ptr
0x0000535C       ADD R8 R8 1 ;current index entry number
0x00005360       B nsfs_build_child_index_loop

nsfs_build_dir_cache_done:
0x00005368       LI R1 0
0x00005370       B nsfs_build_dir_cache_return

nsfs_build_dir_cache_full:
    ; Do not expose a partially rebuilt cache if either fixed-size table fills.
0x00005378       LI R1 nsfs_dir_count
0x00005380       LI R2 0
0x00005388       STW R2 [R1]
0x0000538C       LI R1 nsfs_dir_index_count
0x00005394       STW R2 [R1]
0x00005398       LI R1 ERR_NOSPC

nsfs_build_dir_cache_return:
0x000053A0       POP R12
0x000053A4       POP R11
0x000053A8       POP R10
0x000053AC       POP R9
0x000053B0       POP R8
0x000053B4       POP LR
0x000053B8       RET


;=====================================================================
; nsfs_add_dir_to_cache: Add a directory to the derived dir_table if not already present
; in:  R1 = namespace, R2 = directory path
; out: R1 = dir id, or -1 if full
;=====================================================================
nsfs_add_dir_to_cache:
0x000053BC       PUSH LR
0x000053C0       PUSH R8
0x000053C4       PUSH R9
0x000053C8       PUSH R10
0x000053CC       PUSH R12

    ; Preserve the key while the lookup helper reuses argument registers.
0x000053D0       MOV R12 R2
0x000053D4       MOV  R8 R1

    ; Reuse an existing namespace/path pair to keep directory IDs unique.
    ; R1 is the existing ID, or -1 when the pair is not in the table.
0x000053D8       BL nsfs_find_dir_id
0x000053E0       LI R2 -1
0x000053E8       CMP R1 R2
0x000053EC       BNE nsfs_add_dir_done

    ; A new ID is the current count, so IDs stay dense from zero upward.
0x000053F4       LI R9 nsfs_dir_count
0x000053FC       LDW R10 [R9]
0x00005400       LI R1 MAX_NSFS_DIRS
0x00005408       CMP R10 R1
0x0000540C       BGE nsfs_add_dir_full

0x00005414       LI R1 NSFS_DIR_SIZEOF
0x0000541C       MUL R1 R10 R1
0x00005420       LI R2 nsfs_dir_table
0x00005428       ADD R2 R2 R1    ; R2 = &nsfs_dir_table[dir_count]

    ; Store namespace and path together; paths may be shared across namespaces.
0x0000542C       STW R8  [R2 + NSFS_DIR_NS]
0x00005430       STW R12 [R2 + NSFS_DIR_PATH]
0x00005434       LI R1 0
0x0000543C       STW R1  [R2 + NSFS_DIR_FLAGS]

0x00005440       MOV R1 R10
0x00005444       ADD R10 R10 1
0x00005448       STW R10 [R9]    ;Dir count incremented
0x0000544C       B nsfs_add_dir_done

nsfs_add_dir_full:
0x00005454       LI R1 -1

nsfs_add_dir_done:
0x0000545C       POP R12
0x00005460       POP R10
0x00005464       POP R9
0x00005468       POP R8
0x0000546C       POP LR
0x00005470       RET

;=====================================================================
; nsfs_find_dir_id: Find the ID of a directory in the cache (derived dir_table)
; in:  R1 = namespace, R2 = directory path
; out: R1 = dir id, or -1
;=====================================================================
nsfs_find_dir_id:
0x00005474       PUSH LR
0x00005478       PUSH R8
0x0000547C       PUSH R9
0x00005480       PUSH R10
0x00005484       PUSH R11

    ; Search by the full composite key (namespace, exact path), not path alone.
    ; R10 is the candidate ID and therefore the dir_table array index.
0x00005488       MOV R8 R1
0x0000548C       MOV R9 R2
0x00005490       LI R10 0

nsfs_find_dir_loop:
0x00005498       LI R11 nsfs_dir_count
0x000054A0       LDW R11 [R11]
0x000054A4       CMP R10 R11
0x000054A8       BGE nsfs_find_dir_not_found

    ; Compute &nsfs_dir_table[R10] and skip entries from other namespaces.
0x000054B0       LI R1 NSFS_DIR_SIZEOF
0x000054B8       MUL R1 R10 R1
0x000054BC       LI R11 nsfs_dir_table
0x000054C4       ADD R11 R11 R1

0x000054C8       LDW R1 [R11 + NSFS_DIR_NS]
0x000054CC       CMP R1 R8
0x000054D0       BNE nsfs_find_dir_next

0x000054D8       MOV R1 R9
0x000054DC       LDW R2 [R11 + NSFS_DIR_PATH]
0x000054E0       BL strcmp
0x000054E8       CMP R1 1
0x000054EC       BEQ nsfs_find_dir_found

nsfs_find_dir_next:
0x000054F4       ADD R10 R10 1
0x000054F8       B nsfs_find_dir_loop

nsfs_find_dir_found:
0x00005500       MOV R1 R10
0x00005504       B nsfs_find_dir_done

nsfs_find_dir_not_found:
0x0000550C       LI R1 -1

nsfs_find_dir_done:
0x00005514       POP R11
0x00005518       POP R10
0x0000551C       POP R9
0x00005520       POP R8
0x00005524       POP LR
0x00005528       RET

;=====================================================================
; nsfs_path_is_child
; in:  R1 = parent path, R2 = object path
; out: R1 = 1 and R2 = child name when the object is an immediate child
;=====================================================================
nsfs_path_is_child:
0x0000552C       PUSH LR
0x00005530       PUSH R8
0x00005534       PUSH R9
0x00005538       PUSH R10
0x0000553C       PUSH R11

    ; Match the parent prefix, then accept only one remaining path component.
    ; The returned R2 points at that component in the original object path.
0x00005540       MOV R8 R1
0x00005544       MOV R9 R2

nsfs_path_child_compare:
0x00005548       LDB R10 [R8]
0x0000554C       LDB R11 [R9]
0x00005550       CMP R10 0
0x00005554       BEQ nsfs_path_child_parent_matched
0x0000555C       CMP R10 R11
0x00005560       BNE nsfs_path_child_no
0x00005568       ADD R8 R8 1
0x0000556C       ADD R9 R9 1
0x00005570       B nsfs_path_child_compare

nsfs_path_child_parent_matched:
    ; An exact parent path is not its own child. For root "/", the previous
    ; character test below recognizes the slash already consumed as the prefix.
0x00005578       CMP R11 0
0x0000557C       BEQ nsfs_path_child_no

0x00005584       SUB R1 R8 1
0x00005588       LDB R1 [R1]
0x0000558C       LI R5 47
0x00005594       CMP R1 R5
0x00005598       BEQ nsfs_path_child_component_start

0x000055A0       CMP R11 R5
0x000055A4       BNE nsfs_path_child_no
0x000055AC       ADD R9 R9 1
0x000055B0       LDB R11 [R9]
0x000055B4       CMP R11 0
0x000055B8       BEQ nsfs_path_child_no

nsfs_path_child_component_start:
0x000055C0       MOV R2 R9

nsfs_path_child_scan:
    ; A single trailing slash is allowed for directory paths; another
    ; component after a slash means this object is not an immediate child.
0x000055C4       LDB R10 [R9]
0x000055C8       CMP R10 0
0x000055CC       BEQ nsfs_path_child_yes
0x000055D4       LI R5 47
0x000055DC       CMP R10 R5
0x000055E0       BNE nsfs_path_child_advance
0x000055E8       ADD R9 R9 1
0x000055EC       LDB R10 [R9]
0x000055F0       CMP R10 0
0x000055F4       BEQ nsfs_path_child_yes
0x000055FC       B nsfs_path_child_no

nsfs_path_child_advance:
0x00005604       ADD R9 R9 1
0x00005608       B nsfs_path_child_scan

nsfs_path_child_yes:
0x00005610       LI R1 1
0x00005618       B nsfs_path_child_done

nsfs_path_child_no:
0x00005620       LI R1 0

nsfs_path_child_done:
0x00005628       POP R11
0x0000562C       POP R10
0x00005630       POP R9
0x00005634       POP R8
0x00005638       POP LR
0x0000563C       RET

;=====================================================================
; nsfs_find_parent_dir
; in:  R1 = namespace, R2 = object path
; out: R1 = parent dir id, R2 = basename ptr, R3 = object type
;=====================================================================
nsfs_find_parent_dir:
0x00005640       PUSH LR
0x00005644       PUSH R8
0x00005648       PUSH R9
0x0000564C       PUSH R10
0x00005650       PUSH R11
0x00005654       PUSH R12

    ; Find a matching parent directory in this namespace, then resolve the
    ; object's own index entry so the result also includes its stored type.
0x00005658       MOV R8 R1                          ; namespace
0x0000565C       MOV R9 R2                          ; object path
0x00005660       LI R10 0

nsfs_find_parent_loop:
0x00005668       LI R11 nsfs_dir_count
0x00005670       LDW R11 [R11]
0x00005674       CMP R10 R11
0x00005678       BGE nsfs_find_parent_fail

    ; R10 is a directory ID; ignore directories belonging to other namespaces.
0x00005680       LI R1 NSFS_DIR_SIZEOF
0x00005688       MUL R1 R10 R1
0x0000568C       LI R11 nsfs_dir_table
0x00005694       ADD R11 R11 R1

0x00005698       LDW R1 [R11 + NSFS_DIR_NS]
0x0000569C       CMP R1 R8
0x000056A0       BNE nsfs_find_parent_next

0x000056A8       LDW R1 [R11 + NSFS_DIR_PATH]
0x000056AC       MOV R2 R9
0x000056B0       BL nsfs_path_is_child
0x000056B8       CMP R1 1
0x000056BC       BEQ nsfs_find_parent_found

nsfs_find_parent_next:
0x000056C4       ADD R10 R10 1
0x000056C8       B nsfs_find_parent_loop

nsfs_find_parent_found:
    ; R2 is the basename pointer from nsfs_path_is_child.
    ; Keep the basename returned by the matcher while doing the exact object
    ; lookup; that lookup supplies the type stored in the child-index record.
0x000056D0       MOV R12 R2
0x000056D4       MOV R1 R8
0x000056D8       MOV R2 R9
0x000056DC       BL nsfs_find_index_by_path
0x000056E4       LI R2 -1
0x000056EC       CMP R1 R2
0x000056F0       BEQ nsfs_find_parent_fail
0x000056F8       MOV R11 R1

0x000056FC       MOV R1 R10
0x00005700       MOV R2 R12
0x00005704       LDW R3 [R11 + NSFS_INDEX_TYPE]
0x00005708       B nsfs_find_parent_done

nsfs_find_parent_fail:
0x00005710       LI R1 -1
0x00005718       LI R2 0
0x00005720       LI R3 0

nsfs_find_parent_done:
0x00005728       POP R12
0x0000572C       POP R11
0x00005730       POP R10
0x00005734       POP R9
0x00005738       POP R8
0x0000573C       POP LR
0x00005740       RET

;=====================================================================
; nsfs_find_index_by_path
; in:  R1 = namespace, R2 = object path
; out: R1 = object index entry ptr, or -1
;=====================================================================
nsfs_find_index_by_path:
0x00005744       PUSH LR
0x00005748       PUSH R8
0x0000574C       PUSH R9
0x00005750       PUSH R10
0x00005754       PUSH R11

    ; Return the address of the exact namespace/path entry, or -1 if absent.
    ; Callers use the pointer to read the entry's type and other metadata.
0x00005758       MOV R8 R1                          ; namespace
0x0000575C       MOV R9 R2                          ; object path
0x00005760       LI R10 0
0x00005768       LI R11 nsfs_index_table

nsfs_find_index_loop:
0x00005770       LI R1 nsfs_index_count
0x00005778       LDW R1 [R1]
0x0000577C       CMP R10 R1
0x00005780       BGE nsfs_find_index_fail

    ; R10 is the object index and R11 points to that entry.
0x00005788       LDW R1 [R11 + NSFS_INDEX_NS]
0x0000578C       CMP R1 R8
0x00005790       BNE nsfs_find_index_next

0x00005798       MOV R1 R9
0x0000579C       LDW R2 [R11 + NSFS_INDEX_PATH]
0x000057A0       BL strcmp
0x000057A8       CMP R1 1
0x000057AC       BEQ nsfs_find_index_found

nsfs_find_index_next:
0x000057B4       ADD R11 R11 NSFS_INDEX_ENTRY_SIZEOF
0x000057B8       ADD R10 R10 1
0x000057BC       B nsfs_find_index_loop

nsfs_find_index_found:
0x000057C4       MOV R1 R11
0x000057C8       B nsfs_find_index_done

nsfs_find_index_fail:
0x000057D0       LI R1 -1

nsfs_find_index_done:
0x000057D8       POP R11
0x000057DC       POP R10
0x000057E0       POP R9
0x000057E4       POP R8
0x000057E8       POP LR
0x000057EC       RET



;====================================================================
; lookup_device in device_table - obsolete replaced by devfs_lookup
;
;input:
; R1 = user pointer to string
;output:
; R1 = device descriptor
; R1 = 0 if not found
;====================================================================
lookup_device:

0x000057F0       PUSH LR

0x000057F4       MOV R8 R1                  ; save pathname ptr

0x000057F8       LI R7 device_table
0x00005800       LI R9 DEVICE_COUNT

lookup_loop:
0x00005808       CMP R9 0
0x0000580C       BEQ lookup_fail

    ; compare pathname with device name

0x00005814       MOV R1 R8
0x00005818       LDW R2 [R7 + DEV_NAME]

0x0000581C       BL strcmp

0x00005824       CMP R1 1
0x00005828       BEQ lookup_found

0x00005830       ADD R7 R7 DEV_SIZE
0x00005834       SUB R9 R9 1
0x00005838       B lookup_loop

lookup_found:

0x00005840       MOV R1 R7                  ; return device descriptor ptr

0x00005844       POP LR
0x00005848       RET

lookup_fail:

0x0000584C       LI R1 0

0x00005854       POP LR
0x00005858       RET

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
0x0000585C       LDB R3 [R1]
0x00005860       LDB R4 [R2]

0x00005864       CMP R3 R4
0x00005868       BNE str_not_equal

0x00005870       CMP R3 0
0x00005874       BEQ str_equal

0x0000587C       ADD R1 R1 1
0x00005880       ADD R2 R2 1
0x00005884       B str_loop

str_equal:
0x0000588C       LI R1 1
0x00005894       RET

str_not_equal:
0x00005898       LI R1 0
0x000058A0       RET

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
0x000058A4       PUSH R3
0x000058A8       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x000058AC       LDB R3 [R2]            ; prefix char
0x000058B0       CMP R3 0
0x000058B4       BEQ sp_match           ; reached end of prefix?

0x000058BC       LDB R4 [R1]            ; string char
0x000058C0       CMP R4 R3
0x000058C4       BNE sp_nomatch

0x000058CC       ADD R1 R1 1
0x000058D0       ADD R2 R2 1
0x000058D4       B sp_loop
sp_match:
0x000058DC       LI R1 1                 ;prefix ok
0x000058E4       POP R4
0x000058E8       POP R3
0x000058EC       RET
sp_nomatch:
0x000058F0       LI R1 0                 ; not ok
0x000058F8       POP R4
0x000058FC       POP R3
0x00005900       RET

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
0x00005904       PUSH R3
0x00005908       PUSH R4
sk_loop:
0x0000590C       LDB R3 [R2]            ; prefix char
0x00005910       CMP R3 0
0x00005914       BEQ sk_match           ; reached end of prefix
0x0000591C       LDB R4 [R1]            ; string char
0x00005920       CMP R4 R3
0x00005924       BNE sk_nomatch
0x0000592C       ADD R1 R1 1
0x00005930       ADD R2 R2 1
0x00005934       B sk_loop

sk_match:
    ; R1 already points past prefix
0x0000593C       POP R4
0x00005940       POP R3
0x00005944       RET

sk_nomatch:
0x00005948       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x00005950       POP R4
0x00005954       POP R3
0x00005958       RET

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
0x0000595C       PUSH R2
0x00005960       PUSH R3
0x00005964       LI R2 0                ; length
pcl_loop:
0x0000596C       LDB R3 [R1]
0x00005970       CMP R3 0
0x00005974       BEQ pcl_done
0x0000597C       LI R4 47               ; '/'
0x00005984       CMP R3 R4
0x00005988       BEQ pcl_done
0x00005990       ADD R2 R2 1
0x00005994       ADD R1 R1 1
0x00005998       B pcl_loop
pcl_done:
0x000059A0       MOV R1 R2
0x000059A4       POP R3
0x000059A8       POP R2
0x000059AC       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x000059B0       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x000059B4       LI R4 0
0x000059BC       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x000059C0       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x000059C4       LI R4 1
0x000059CC       STW R4 [R1 + FILE_REFCNT]
0x000059D0       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x000059D4       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x000059D8   LI R1 CURRENT_TASK
0x000059E0   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000059E4   LI R1 TASK_SIZE
0x000059EC   MUL R3 R4 R1
0x000059F0   LI R4 tasks
0x000059F8   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x000059FC   LDW R4 [R4 + TASK_FD_TABLE]

0x00005A00       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00005A08       CMP R5 MAX_FDS
0x00005A0C       BGE fd_alloc_fail

0x00005A14       SHL R6 R5 2                ; fd * 4
0x00005A18       ADD R7 R4 R6               ; &fd_table[fd]

0x00005A1C       LDW R2 [R7]
0x00005A20       CMP R2 0                   ; 0 - empty
0x00005A24       BEQ fd_alloc_found

0x00005A2C       ADD R5 R5 1
0x00005A30       B fd_alloc_loop

fd_alloc_found:

0x00005A38       STW R8 [R7]                ; fd_table[fd] = file*

0x00005A3C       MOV R1 R5                  ; return fd
0x00005A40       RET

fd_alloc_fail:

0x00005A44       LI R1 ERR_MFILE
0x00005A4C       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x00005A50       LDW R1 [SP + TF_R1]

0x00005A54       BL vfs_close

0x00005A5C       LI R1 0
0x00005A64       STW R1 [SP + TF_R1]

0x00005A68       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00005A70       LDW R7 [SP + TF_R1]

0x00005A74       BL pipe_alloc       ;create new pipe object in pipe_pool
0x00005A7C       CMP R1 0
0x00005A80       BEQ pipe_fail_nospc

0x00005A88       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x00005A8C       BL file_alloc        ; R1 - created read file ptr for read end
0x00005A94       CMP R1 0
0x00005A98       BEQ pipe_fail_read_fd

0x00005AA0       MOV R9 R1           ; new file for read end  in file_pool
0x00005AA4       BL inode_alloc      ; get inode for this end file
0x00005AAC       CMP R1 0
0x00005AB0       BEQ pipe_fail_ia_read_fd
0x00005AB8       MOV R10 R1

0x00005ABC       LI  R2 pipe_ops         ; pipe_ops table
0x00005AC4       MOV R3 R8               ; store our slot pipe*
0x00005AC8       LI  R4 INODE_PIPE       ; inode type PIPE
0x00005AD0       LI  R5 0                ; size =0
0x00005AD8       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x00005AE0       MOV R1 R9                ; R1 file*
0x00005AE4       MOV R2 R10               ; inode*
0x00005AE8       LI R3  FD_FLAG_READ      ; flags READ end
0x00005AF0       BL file_init

0x00005AF8       MOV R1 R9
0x00005AFC       BL fd_alloc                 ; insert read file to fd_table of user process

0x00005B04       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00005B0C       CMP R1 R2
0x00005B10       BEQ pipe_fail_read_file

0x00005B18       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x00005B1C       BL file_alloc
0x00005B24       CMP R1 0
0x00005B28       BEQ pipe_fail_ia_write_fd
0x00005B30       MOV R9 R1

0x00005B34       BL inode_alloc      ; get inode for this end file
0x00005B3C       CMP R1 0
0x00005B40       BEQ pipe_fail_ia_write_fd
0x00005B48       MOV R10 R1

0x00005B4C       LI  R2 pipe_ops         ; pipe_ops table
0x00005B54       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x00005B58       LI  R4 INODE_PIPE       ; inode type PIPE
0x00005B60       LI  R5 0                ; size =0
0x00005B68       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x00005B70       MOV R1 R9                ; R1 file*
0x00005B74       MOV R2 R10               ; inode*
0x00005B78       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x00005B80       BL file_init

0x00005B88       MOV R1 R9
0x00005B8C       BL  fd_alloc

0x00005B94       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x00005B9C       CMP R1 R2
0x00005BA0       BEQ pipe_fail_write_file

0x00005BA8       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x00005BAC       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x00005BB0       LI  R2 8     ; len 2 words (8 bytes)
0x00005BB8       LI  R3 1     ; mem perm to write cond
0x00005BC0       BL  user_buffer_valid_range
0x00005BC8       CMP R1 1
0x00005BCC       BNE pipe_fail_both_fds

0x00005BD4       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x00005BD8       STW R11 [R7 + 4]

0x00005BDC       LI R1 0
0x00005BE4       STW R1 [SP + TF_R1]

0x00005BE8       B trap_restore

pipe_fail:
0x00005BF0       LI R1 ERR_IO
0x00005BF8       STW R1 [SP + TF_R1]

0x00005BFC       B trap_restore

pipe_fail_both_fds:
0x00005C04       MOV R12 R8
0x00005C08       MOV R1 R11
0x00005C0C       BL fd_remove
0x00005C14       CMP R1 0
0x00005C18       BEQ pipe_fail_both_fds_read
0x00005C20       BL file_free

pipe_fail_both_fds_read:
0x00005C28       MOV R1 R10
0x00005C2C       BL fd_remove
0x00005C34       CMP R1 0
0x00005C38       BEQ pipe_fail_free_pipe_fault
0x00005C40       BL file_free

pipe_fail_free_pipe_fault:
0x00005C48       MOV R1 R12
0x00005C4C       BL pipe_free
0x00005C54       LI R1 ERR_FAULT
0x00005C5C       STW R1 [SP + TF_R1]

0x00005C60       B trap_restore

pipe_fail_write_file:
0x00005C68       MOV R12 R8
0x00005C6C       MOV R1 R9
0x00005C70       BL file_free
0x00005C78       MOV R1 R10
0x00005C7C       BL fd_remove
0x00005C84       CMP R1 0
0x00005C88       BEQ pipe_fail_free_pipe_mfile
0x00005C90       BL file_free

pipe_fail_free_pipe_mfile:
0x00005C98       MOV R1 R12
0x00005C9C       BL pipe_free
0x00005CA4       LI R1 ERR_MFILE
0x00005CAC       STW R1 [SP + TF_R1]

0x00005CB0       B trap_restore

pipe_fail_read_fd:
0x00005CB8       MOV R12 R8
0x00005CBC       MOV R1 R10
0x00005CC0       BL fd_remove
0x00005CC8       CMP R1 0
0x00005CCC       BEQ pipe_fail_free_pipe_nfile
0x00005CD4       BL file_free

pipe_fail_free_pipe_nfile:
0x00005CDC       MOV R1 R12
0x00005CE0       BL pipe_free
0x00005CE8       LI R1 ERR_NFILE
0x00005CF0       STW R1 [SP + TF_R1]

0x00005CF4       B trap_restore

pipe_fail_read_file:
0x00005CFC       MOV R12 R8
0x00005D00       MOV R1 R9
0x00005D04       BL file_free
0x00005D0C       MOV R1 R10          ; освободить inode read end
0x00005D10       BL inode_free
0x00005D18       MOV R1 R12
0x00005D1C       BL pipe_free
0x00005D24       LI R1 ERR_MFILE
0x00005D2C       STW R1 [SP + TF_R1]

0x00005D30       B trap_restore

pipe_fail_pipe_only:
0x00005D38       MOV R1 R8
0x00005D3C       BL pipe_free
0x00005D44       LI R1 ERR_NFILE
0x00005D4C       STW R1 [SP + TF_R1]

0x00005D50       B trap_restore

pipe_fail_nospc:
0x00005D58       LI R1 ERR_NOSPC
0x00005D60       STW R1 [SP + TF_R1]

0x00005D64       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x00005D6C       MOV R1 R9          ; освобождаем file (read end)
0x00005D70       BL  file_free
0x00005D78       MOV R1 R8          ; освобождаем pipe
0x00005D7C       BL  pipe_free
0x00005D84       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x00005D8C       STW R1 [SP + TF_R1]
0x00005D90       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x00005D98       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x00005D9C       BL fd_remove
0x00005DA4       CMP R1 0
0x00005DA8       BEQ skip_file_free_read
0x00005DB0       BL file_free
skip_file_free_read:
0x00005DB8       MOV R1 R9          ; освобождаем file (write end)
0x00005DBC       BL file_free
0x00005DC4       MOV R1 R8          ; освобождаем pipe
0x00005DC8       BL pipe_free
0x00005DD0       LI R1 ERR_NFILE
0x00005DD8       STW R1 [SP + TF_R1]
0x00005DDC       B trap_restore

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

0x00005DE4       LDW R1 [SP + TF_R1]     ; argument fd

0x00005DE8       BL fd_lookup            ; lookup FILE*
0x00005DF0       CMP R1 0
0x00005DF4       BEQ dup_badfd
0x00005DFC       MOV R8 R1               ; keep FILE*

0x00005E00       BL file_get             ; FILE.ref++

0x00005E08       MOV R1 R8
0x00005E0C       BL fd_alloc             ; try to allocate new fd

0x00005E14       LI R2 ERR_MFILE
0x00005E1C       CMP R1 R2
0x00005E20       BEQ dup_fail_fd

0x00005E28       STW R1 [SP + TF_R1] ;R1 - new fd
0x00005E2C       B trap_restore

dup_fail_fd:

0x00005E34       MOV R1 R8
0x00005E38       BL file_put

0x00005E40       LI R1 ERR_MFILE     ;R1 -err + rollback
0x00005E48       STW R1 [SP + TF_R1]
0x00005E4C       B trap_restore

dup_badfd:

0x00005E54       LI R1 ERR_BADF      ;R1 -err + file not found
0x00005E5C       STW R1 [SP + TF_R1]

0x00005E60       B trap_restore

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

0x00005E68       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x00005E6C       MOV R1 R8
0x00005E70       LI  R2 TIMEVAL_SIZE
0x00005E78       LI  R3 1                   ; write access
0x00005E80       BL  user_buffer_valid_range

0x00005E88       CMP R1 1
0x00005E8C       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x00005E94       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x00005E9C   LI R1 CURRENT_TASK
0x00005EA4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005EA8   LI R1 TASK_SIZE
0x00005EB0   MUL R3 R4 R1
0x00005EB4   LI R5 tasks
0x00005EBC   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x00005EC0   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x00005EC4       STW R1 [R6 + TIMEVAL_SEC]
0x00005EC8       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x00005ECC       MOV R1 R8                  ; user destination
0x00005ED0       LI  R2 TIMEVAL_SIZE        ; size in bytes (8)
0x00005ED8       MOV R4 R6                  ; kernel source

0x00005EDC       BL copy_to_user

0x00005EE4       CMP R1 TIMEVAL_SIZE
0x00005EE8       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x00005EF0       LI R1 0
0x00005EF8       STW R1 [SP + TF_R1]

0x00005EFC       B trap_restore

gettime_badptr:

0x00005F04       LI R1 ERR_FAULT
0x00005F0C       STW R1 [SP + TF_R1]

0x00005F10       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x00005F18       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x00005F1C       LI R2 HEAP_START
0x00005F24       CMP R8 R2
0x00005F28       BLT brk_invalid            ; if new break is below data page, return error

0x00005F30       LI R2 HEAP_END
0x00005F38       CMP R8 R2
0x00005F3C       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00005F44   LI R1 CURRENT_TASK
0x00005F4C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005F50   LI R1 TASK_SIZE
0x00005F58   MUL R3 R4 R1
0x00005F5C   LI R5 tasks
0x00005F64   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x00005F68   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x00005F6C       STW R8 [SP + TF_R1]

0x00005F70       B trap_restore

brk_invalid:
    ; Return -1
0x00005F78       LI R1 ERR_FAULT
0x00005F80       STW R1 [SP + TF_R1]

0x00005F84       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x00005F8C       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00005F90   LI R1 CURRENT_TASK
0x00005F98   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005F9C   LI R1 TASK_SIZE
0x00005FA4   MUL R3 R4 R1
0x00005FA8   LI R5 tasks
0x00005FB0   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x00005FB4   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x00005FB8       ADD R10 R9 R8

    ; Validate it's within the data page
0x00005FBC       LI R2 HEAP_START
0x00005FC4       CMP R10 R2
0x00005FC8       BLT sbrk_invalid

0x00005FD0       LI R2 HEAP_END
0x00005FD8       CMP R10 R2
0x00005FDC       BGT sbrk_invalid

    ; Return old break
0x00005FE4       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x00005FE8   STW R10 [R5 + TASK_BREAK]

0x00005FEC       B trap_restore

sbrk_invalid:
    ; Return -1
0x00005FF4       LI R1 ERR_FAULT
0x00005FFC       STW R1 [SP + TF_R1]
0x00006000       B trap_restore

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

0x00006008       LI  R3 timer_ticks
0x00006010       LDW R4 [R3]                ; tick counter (1 ms per tick)

    ; seconds = ticks / 1000
0x00006014       MOV R1 R4
0x00006018       LI  R5 1000
0x00006020       DIV R1 R1 R5

    ; usec = (ticks % 1000) * 1000
0x00006024       MOD R4 R4 R5
0x00006028       LI  R5 1000
0x00006030       MUL R2 R4 R5

0x00006034       RET

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

0x00006038       PUSH LR

0x0000603C       MOV R9 R1              ; file*
0x00006040       MOV R7 R2              ; user buffer
0x00006044       MOV R6 R3              ; requested len

0x00006048       LDW R9 [R9 + FILE_INODE]
0x0000604C       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x00006050       CMP R6 0                ;fast clear from it if len=0
0x00006054       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x0000605C       PUSH R7
0x00006060       PUSH R6

0x00006064       MOV R1 R7
0x00006068       MOV R2 R6
0x0000606C       LI  R3 1               ; write access
0x00006074       BL user_buffer_valid_range

0x0000607C       POP R6
0x00006080       POP R7
0x00006084       CMP R1 1
0x00006088       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x00006090       LDW R4 [R9 + PIPE_COUNT]
0x00006094       CMP R4 0
0x00006098       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x000060A0       CMP R6 R4
0x000060A4       BLT pipe_user_len

0x000060AC       MOV R5 R4
0x000060B0       B pipe_have_amount

pipe_user_len:
0x000060B8       MOV R5 R6

pipe_have_amount:
0x000060BC       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x000060C4       CMP R10 R5
0x000060C8       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x000060D0       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x000060D4       MOV R12 R9
0x000060D8       ADD R12 R12 PIPE_BUFFER
0x000060DC       ADD R12 R12 R11         ; addr += tail

0x000060E0       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x000060E4       MOV R12 R7
0x000060E8       ADD R12 R12 R10

0x000060EC       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x000060F0       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x000060F4       LI R2 255
0x000060FC       AND R11 R11 R2
0x00006100       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00006104       LDW R12 [R9 + PIPE_COUNT]
0x00006108       SUB R12 R12 1
0x0000610C       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00006110       ADD R10 R10 1
0x00006114       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x0000611C       MOV R1 R9
0x00006120       ADD R1 R1 PIPE_WWAIT
0x00006124       BL waitq_wake_all
0x0000612C       MOV R1 R10          ; read bytes amount
0x00006130       POP LR
0x00006134       RET

pipe_read_badptr:
0x00006138       LI R1 ERR_FAULT
0x00006140       POP LR
0x00006144       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x00006148       MOV R1 R9
0x0000614C       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x00006150       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x00006158       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x00006160       LDW R4 [R9 + PIPE_COUNT]
0x00006164       CMP R4 0
0x00006168       BNE pipe_read_retry

0x00006170       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x00006178       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x00006180       LI R2 0

pipe_loop:
0x00006188       LI  R1 MAX_PIPES
0x00006190       CMP R2 R1
0x00006194       BGE pipe_alloc_fail

0x0000619C       SHL R3 R2 2

0x000061A0       LI R4 pipe_used
0x000061A8       ADD R4 R4 R3

0x000061AC       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x000061B0       CMP R5 0                ; 0 -empty
0x000061B4       BEQ pipe_found

0x000061BC       ADD R2 R2 1
0x000061C0       B pipe_loop

pipe_found:

0x000061C8       LI R5 1
0x000061D0       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x000061D4       LI R4 PIPE_SIZE
0x000061DC       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x000061E0       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x000061E8       ADD R1 R1 R6

0x000061EC       LI R7 0                 ; clean it up
0x000061F4       STW R7 [R1 + PIPE_HEAD]
0x000061F8       STW R7 [R1 + PIPE_TAIL]
0x000061FC       STW R7 [R1 + PIPE_COUNT]
0x00006200       STW R7 [R1 + PIPE_RWAIT]
0x00006204       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x00006208       RET

pipe_alloc_fail:
    ; R1 = NULL
0x0000620C       LI R1 0
0x00006214       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x00006218       LI R2 pipe_pool
0x00006220       SUB R3 R1 R2

0x00006224       LI R4 PIPE_SIZE
0x0000622C       DIV R5 R3 R4

0x00006230       SHL R5 R5 2
0x00006234       LI R6 pipe_used
0x0000623C       ADD R6 R6 R5

0x00006240       LI R7 0
0x00006248       STW R7 [R6]

0x0000624C       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x00006250       PUSH LR

0x00006254       MOV R9 R1
0x00006258       MOV R7 R2
0x0000625C       MOV R6 R3

0x00006260       LDW R9 [R9 + FILE_INODE]
0x00006264       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x00006268       PUSH R7
0x0000626C       PUSH R6

0x00006270       MOV R1 R7
0x00006274       MOV R2 R6
0x00006278       LI  R3 0           ; READ access
0x00006280       BL user_buffer_valid_range

0x00006288       POP R6
0x0000628C       POP R7

0x00006290       CMP R1 1
0x00006294       BNE pipe_write_badptr

0x0000629C       LI R10 0               ; bytes written
pipe_write_retry:
0x000062A4       CMP R10 R6
0x000062A8       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x000062B0       LDW R11 [R9 + PIPE_COUNT]
0x000062B4       LI R2 256
0x000062BC       CMP R11 R2
0x000062C0       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x000062C8       LDW R12 [R9 + PIPE_HEAD]

0x000062CC       MOV R4 R7
0x000062D0       ADD R4 R4 R10
0x000062D4       LDB R5 [R4]     ; read byte from user buff addr

0x000062D8       MOV R4 R9
0x000062DC       ADD R4 R4 PIPE_BUFFER
0x000062E0       ADD R4 R4 R12
0x000062E4       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x000062E8       ADD R12 R12 1
0x000062EC       LI R2 255
0x000062F4       AND R12 R12 R2
0x000062F8       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x000062FC       LDW R4 [R9 + PIPE_COUNT]
0x00006300       ADD R4 R4 1
0x00006304       STW R4 [R9 + PIPE_COUNT]

; written++
0x00006308       ADD R10 R10 1
0x0000630C       B pipe_write_retry

pipe_write_done:
; wake readers
0x00006314       MOV R1 R9
0x00006318       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x0000631C       BL waitq_wake_all
0x00006324       MOV R1 R10      ;written bytes
0x00006328       POP LR
0x0000632C       RET

pipe_write_badptr:
0x00006330       LI R1 ERR_FAULT
0x00006338       POP LR
0x0000633C       RET

pipe_write_empty:
0x00006340       LI R1 0
0x00006348       POP LR
0x0000634C       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x00006350       MOV R1 R9
0x00006354       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x00006358       LI R2 WAIT_PIPE_WRITE
0x00006360       BL waitq_prepare_sleep
    ; race check
0x00006368       LDW R4 [R9 + PIPE_COUNT]
0x0000636C       LI R2 256
0x00006374       CMP R4 R2
0x00006378       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x00006380       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x00006388       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x00006390       CMP R1 3
0x00006394       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x0000639C       CMP R1 MAX_FDS
0x000063A0       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x000063A8       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x000063AC   LI R1 CURRENT_TASK
0x000063B4   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x000063B8   LI R1 TASK_SIZE
0x000063C0   MUL R3 R4 R1
0x000063C4   LI R4 tasks
0x000063CC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x000063D0   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x000063D4       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x000063D8       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x000063DC       LDW R1 [R6]                 ; R1 = file* из таблицы
0x000063E0       CMP R1 0
0x000063E4       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x000063EC       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x000063F0       RET

fd_lookup_invalid:
0x000063F4       LI R1 0
0x000063FC       LI R2 0
0x00006404       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x00006408       PUSH LR
0x0000640C       BL  fd_lookup
0x00006414       CMP R1 0
0x00006418       BEQ fd_remove_invalid

0x00006420       MOV R8 R1          ; сохраняем file*
0x00006424       LI R3 0
0x0000642C       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x00006430       MOV R1 R8          ; file*
0x00006434       POP LR
0x00006438       RET

fd_remove_invalid:
0x0000643C       LI R1 0
0x00006444       POP LR
0x00006448       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x0000644C       LDW R1 [SP + TF_R1]
0x00006450       LDW R2 [SP + TF_R2]
0x00006454       LDW R3 [SP + TF_R3]

0x00006458       BL vfs_read

0x00006460       STW R1 [SP + TF_R1]
0x00006464       B trap_restore

; to comply with vfs interface
devfs_open:
0x0000646C       LI R1 0
0x00006474       RET
devfs_close:
0x00006478       LI R1 0
0x00006480       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x00006484       PUSH LR
0x00006488       PUSH R8
0x0000648C       PUSH R9
0x00006490       PUSH R10
0x00006494       PUSH R11
0x00006498       PUSH R12
0x0000649C       MOV R9 R1
0x000064A0       MOV R7 R2
0x000064A4       MOV R6 R3
0x000064A8       LI R8 0                    ; total bytes collected
0x000064B0       LDW R9 [R9 + FILE_INODE]
0x000064B4       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x000064B8       CMP R6 0
0x000064BC       BEQ read_done

0x000064C4       PUSH R7
0x000064C8       PUSH R6
0x000064CC       PUSH R9
0x000064D0       MOV R1 R7
0x000064D4       MOV R2 R6
0x000064D8       LI R3 1                ; write access for destination buffer
0x000064E0       BL user_buffer_valid_range
0x000064E8       POP R9
0x000064EC       POP R6
0x000064F0       POP R7
0x000064F4       CMP R1 1
0x000064F8       BNE con_read_fault

read_wait_uart_rx:
0x00006500       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00006504       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x00006508       AND R5 R5 1                 ; bit 0 = RX_READY
0x0000650C       CMP R5 0
0x00006510       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x00006518   LI R1 CURRENT_TASK
0x00006520   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00006524   LI R1 TASK_SIZE
0x0000652C   MUL R3 R4 R1
0x00006530   LI R5 tasks
0x00006538   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x0000653C   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00006540       MOV R2 R6
0x00006544       MOV R3 R9
0x00006548       PUSH R6
0x0000654C       PUSH R7
0x00006550       PUSH R8
0x00006554       PUSH R9
0x00006558       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x00006560       POP R9
0x00006564       POP R8
0x00006568       POP R7
0x0000656C       POP R6

0x00006570       CMP R1 0
0x00006574       BEQ read_wait_uart_rx

0x0000657C       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x00006580   LI R1 CURRENT_TASK
0x00006588   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x0000658C   LI R1 TASK_SIZE
0x00006594   MUL R3 R5 R1
0x00006598   LI R4 tasks
0x000065A0   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000065A4   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with CR/LF before copy_to_user
    ; clobbers temporary registers.
0x000065A8       LI R11 0
0x000065B0       SUB R5 R10 1
0x000065B4       ADD R5 R4 R5
0x000065B8       LDB R5 [R5]
0x000065BC       CMP R5 10
0x000065C0       BEQ read_chunk_line_done
0x000065C8       CMP R5 13
0x000065CC       BNE read_chunk_not_newline
read_chunk_line_done:
0x000065D4       LI R11 1

read_chunk_not_newline:
0x000065DC       PUSH R6
0x000065E0       PUSH R7
0x000065E4       PUSH R8
0x000065E8       PUSH R9
0x000065EC       PUSH R10
0x000065F0       PUSH R11
0x000065F4       MOV R1 R7              ; user destination
0x000065F8       MOV R2 R10
0x000065FC       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00006604       POP R11
0x00006608       POP R10
0x0000660C       POP R9
0x00006610       POP R8
0x00006614       POP R7
0x00006618       POP R6

0x0000661C       ADD R7 R7 R10
0x00006620       ADD R8 R8 R10
0x00006624       SUB R6 R6 R10

0x00006628       CMP R11 1
0x0000662C       BEQ read_complete
0x00006634       CMP R6 0
0x00006638       BGT read_wait_uart_rx

read_complete:
0x00006640       MOV R1 R8
0x00006644       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x0000664C       LI R1 uart_rx_waitq
0x00006654       LI R2 WAIT_UART_RX
0x0000665C       BL waitq_prepare_sleep

0x00006664       LDW R4 [R9 + UARTDEV_MMIO]
0x00006668       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x0000666C       AND R10 R10 1
0x00006670       CMP R10 0
0x00006674       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x0000667C       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x00006684       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x0000668C       LI R1 uart_rx_waitq
0x00006694       BL waitq_cancel_sleep_current

0x0000669C       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x000066A4       LI R1 0
0x000066AC       B read_return

con_read_fault:
0x000066B4       LI R1 ERR_FAULT

read_return:
0x000066BC       POP R12
0x000066C0       POP R11
0x000066C4       POP R10
0x000066C8       POP R9
0x000066CC       POP R8
0x000066D0       POP LR
0x000066D4       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x000066D8       LDW R1 [SP + TF_R1]
0x000066DC       LDW R2 [SP + TF_R2]
0x000066E0       LDW R3 [SP + TF_R3]

0x000066E4       BL vfs_write

0x000066EC       STW R1 [SP + TF_R1]
0x000066F0       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x000066F8       PUSH LR
0x000066FC       MOV R9 R1
0x00006700       MOV R7 R2
0x00006704       MOV R6 R3
0x00006708       LDW R9 [R9 + FILE_INODE]
0x0000670C       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00006710       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00006718       CMP R6 0
0x0000671C       BEQ write_done             ;0 bytes

0x00006724       LI R2 KBUFFER_SIZE
0x0000672C       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00006730       BLT write_chunk_small
0x00006738       LI R2 KBUFFER_SIZE

0x00006740       B write_chunk

write_chunk_small:
0x00006748       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x0000674C       PUSH R7
0x00006750       PUSH R6
0x00006754       PUSH R9
0x00006758       PUSH R8
0x0000675C       MOV R1 R7
0x00006760       MOV R2 R2
0x00006764       LI R3 0                ; read access for source buffer
0x0000676C       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00006774       POP R8
0x00006778       POP R9
0x0000677C       POP R6
0x00006780       POP R7
0x00006784       CMP R1 1
0x00006788       BNE driver_bad_pointer

0x00006790       PUSH R7
0x00006794       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x00006798   LI R1 CURRENT_TASK
0x000067A0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000067A4   LI R1 TASK_SIZE
0x000067AC   MUL R3 R4 R1
0x000067B0   LI R5 tasks
0x000067B8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x000067BC   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x000067C0       MOV R1 R7
0x000067C4       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x000067CC       MOV R10 R1             ; bytes copied
0x000067D0       POP R6
0x000067D4       POP R7

0x000067D8       PUSH R7
0x000067DC       PUSH R9
0x000067E0       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x000067E4       LDW R1 [R9 + UARTDEV_MMIO]
0x000067E8       LDW R2 [R1 + 4]
0x000067EC       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x000067F0       CMP R2 0
0x000067F4       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x000067FC   LI R1 CURRENT_TASK
0x00006804   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00006808   LI R1 TASK_SIZE
0x00006810   MUL R3 R4 R1
0x00006814   LI R5 tasks
0x0000681C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00006820   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x00006824       MOV R2 R10
0x00006828       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x0000682C       BL device_write
0x00006834       POP R6
0x00006838       POP R9
0x0000683C       POP R7

0x00006840       CMP R1 0        ;nothing is written - go again
0x00006844       BEQ write_loop

0x0000684C       ADD R8 R8 R1     ;update ptrs
0x00006850       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x00006854       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x00006858       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00006860       LI R1 uart_tx_waitq
0x00006868       LI R2 WAIT_UART_TX
0x00006870       BL waitq_prepare_sleep

0x00006878       LDW R1 [R9 + UARTDEV_MMIO]
0x0000687C       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00006880       AND R2 R2 2
0x00006884       CMP R2 0
0x00006888       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00006890       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x00006898       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x000068A0       LI R1 uart_tx_waitq
0x000068A8       BL waitq_cancel_sleep_current

0x000068B0       B write_wait_uart_tx

write_done:
0x000068B8       MOV R1 R8
0x000068BC       POP LR
0x000068C0       RET

driver_bad_pointer:
0x000068C4       LI R1 ERR_FAULT
0x000068CC       POP LR
0x000068D0       RET

bad_fd:
0x000068D4       LI R1 ERR_BADF
0x000068DC       STW R1 [SP + TF_R1]

0x000068E0       B trap_restore

bad_pointer:
0x000068E8       LI R1 ERR_FAULT
0x000068F0       STW R1 [SP + TF_R1]

0x000068F4       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x000068FC       LDW R4 [R1 + FILE_INODE]
0x00006900       LDW R4 [R4 + INODE_OPS]
0x00006904       LDW R4 [R4 + FSOPS_READ]
0x00006908       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x0000690C       LDW R4 [R1 + FILE_INODE]
0x00006910       LDW R4 [R4 + INODE_OPS]
0x00006914       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x00006918       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x0000691C       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00006924       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when CR or LF is received.
0x0000692C       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00006930       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00006938       CMP R5 R2                   ; have we read enough bytes?
0x0000693C       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x00006944       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00006948       AND R6 R6 1                 ; bit 0 = RX_READY
0x0000694C       CMP R6 0
0x00006950       BEQ dr_done                 ; no more buffered input available

0x00006958       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x0000695C       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00006960       ADD R5 R5 1

    ; If we received a line terminator, stop reading early.
0x00006964       CMP R7 10
0x00006968       BEQ dr_done
0x00006970       CMP R7 13
0x00006974       BEQ dr_done

0x0000697C       B dr_loop

dr_done:
0x00006984       MOV R1 R5                   ; return number of bytes actually read
0x00006988       RET

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
0x0000698C       PUSH LR

    ; mutex for write to console lock
0x00006990       PUSH R1
0x00006994       PUSH R2
0x00006998       PUSH R3

    ; Lock console mutex
0x0000699C       BL console_lock

    ; Write to UART
0x000069A4       POP R3
0x000069A8       POP R2
0x000069AC       POP R1


0x000069B0       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x000069B4       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x000069BC       CMP R5 R2                   ; have we written all bytes?
0x000069C0       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x000069C8       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x000069CC       AND R6 R6 2                 ; bit 1 = TX_READY
0x000069D0       CMP R6 0
0x000069D4       BEQ dcw_done

0x000069DC       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x000069E0       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x000069E4       ADD R5 R5 1
0x000069E8       B dcw_loop

dcw_done:
0x000069F0       MOV R1 R5                   ; return number of bytes written


 ; Unlock console mutex for exclusive write to uart device
0x000069F4       PUSH R1
0x000069F8       BL console_unlock
0x00006A00       POP R1


0x00006A04       POP LR
0x00006A08       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00006A0C       LI R1 0
0x00006A14       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00006A18       PUSH LR
0x00006A1C       MOV R6 R3
0x00006A20       CMP R6 0
0x00006A24       BEQ null_write_done

0x00006A2C       PUSH R6
0x00006A30       MOV R1 R2
0x00006A34       MOV R2 R6
0x00006A38       LI R3 0                    ; read access from user source
0x00006A40       BL user_buffer_valid_range
0x00006A48       POP R6
0x00006A4C       CMP R1 1
0x00006A50       BNE null_write_badptr

null_write_done:
0x00006A58       MOV R1 R6
0x00006A5C       POP LR
0x00006A60       RET

null_write_badptr:
0x00006A64       LI R1 ERR_FAULT
0x00006A6C       POP LR
0x00006A70       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = func check mode for read or write access
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================
0x00006A74       PUSH R5
0x00006A78       PUSH R6
0x00006A7C       PUSH R8

0x00006A80       CMP R1 0
0x00006A84       BLT fd_invalid
0x00006A8C       CMP R1 MAX_FDS
0x00006A90       BGE fd_invalid

0x00006A98       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x00006A9C   LI R1 CURRENT_TASK
0x00006AA4   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00006AA8   LI R1 TASK_SIZE
0x00006AB0   MUL R3 R4 R1
0x00006AB4   LI R4 tasks
0x00006ABC   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x00006AC0   LDW R4 [R4 + TASK_FD_TABLE]

0x00006AC4       SHL R5 R8 2
0x00006AC8       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x00006ACC       LDW R1 [R4]                 ; R1 = file ptr
0x00006AD0       LDW R6 [R1 + FILE_FLAGS]
0x00006AD4       AND R6 R6 O_ACCMODE
    ;check func mode for Read/Write access
0x00006AD8       CMP R2 FD_FLAG_READ
0x00006ADC       BEQ fd_readaccess
0x00006AE4       CMP R2 FD_FLAG_WRITE
0x00006AE8       BEQ fd_writeaccess

0x00006AF0       B fd_invalid
fd_writeaccess:
0x00006AF8       CMP R6 O_RDONLY
0x00006AFC       BEQ fd_invalid
0x00006B04       B  fd_all_good
fd_readaccess:
0x00006B0C       CMP R6 O_WRONLY
0x00006B10       BEQ fd_invalid

fd_all_good:
0x00006B18       POP R8
0x00006B1C       POP R6
0x00006B20       POP R5
0x00006B24       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x00006B28       POP R8
0x00006B2C       POP R6
0x00006B30       POP R5

0x00006B34       LI R1 0
0x00006B3C       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x00006B40       PUSH LR
0x00006B44       MOV R7 R2
0x00006B48       MOV R10 R3

0x00006B4C       LI R2 FD_FLAG_READ  ; func to validate FD reader access
0x00006B54       BL fetch_fd_entry   ; validate FD and access mode

0x00006B5C       CMP R1 0
0x00006B60       BEQ vfs_read_badfd

0x00006B68       MOV R9 R1
0x00006B6C       MOV R1 R9
0x00006B70       MOV R2 R7
0x00006B74       MOV R3 R10
0x00006B78       BL file_read
0x00006B80       POP LR
0x00006B84       RET

vfs_read_badfd:
0x00006B88       LI R1 ERR_BADF
0x00006B90       POP LR
0x00006B94       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x00006B98       PUSH LR
0x00006B9C       MOV R7 R2
0x00006BA0       MOV R10 R3

0x00006BA4       LI R2 FD_FLAG_WRITE ;func to validate FD writer access
0x00006BAC       BL fetch_fd_entry   ;validate FD and access mode

0x00006BB4       CMP R1 0
0x00006BB8       BEQ vfs_write_badfd

0x00006BC0       MOV R9 R1
0x00006BC4       MOV R1 R9           ; R1 - file* acc to fd
0x00006BC8       MOV R2 R7
0x00006BCC       MOV R3 R10
0x00006BD0       BL file_write
0x00006BD8       POP LR
0x00006BDC       RET

vfs_write_badfd:
0x00006BE0       LI R1 ERR_BADF
0x00006BE8       POP LR
0x00006BEC       RET






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
0x00006BF0       PUSH R5
0x00006BF4       PUSH R6
0x00006BF8       PUSH R7
0x00006BFC       PUSH R8
0x00006C00       PUSH R9
0x00006C04       PUSH R10
0x00006C08       PUSH R11
0x00006C0C       PUSH R12

0x00006C10       LI R4 0
0x00006C18       CMP R2 R4
0x00006C1C       BEQ uv_valid

0x00006C24       LI R4 USER_BASE
0x00006C2C       CMP R1 R4
0x00006C30       BLT uv_invalid

0x00006C38       LI R4 USER_LIMIT
0x00006C40       ADD R5 R1 R2
0x00006C44       SUB R5 R5 1
0x00006C48       CMP R5 R1
0x00006C4C       BLT uv_invalid
0x00006C54       CMP R5 R4
0x00006C58       BGT uv_invalid
0x00006C60       MOV R11 R1              ; save start address; task macros clobber R1
0x00006C64       MOV R12 R5              ; save end address for page calculation
0x00006C68       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x00006C6C   LI R1 CURRENT_TASK
0x00006C74   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x00006C78   LI R1 TASK_SIZE
0x00006C80   MUL R3 R6 R1
0x00006C84   LI R6 tasks
0x00006C8C   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x00006C90   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x00006C94       CMP R6 0
0x00006C98       BEQ uv_invalid

uv_check_pages:
0x00006CA0       SHR R7 R11 12
0x00006CA4       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x00006CA8       CMP R7 R8
0x00006CAC       BGT uv_valid
0x00006CB4       SHL R9 R7 2
0x00006CB8       ADD R9 R9 R6
0x00006CBC       LDW R10 [R9]
0x00006CC0       AND R5 R10 PTE_P
0x00006CC4       CMP R5 0
0x00006CC8       BEQ uv_invalid
0x00006CD0       AND R5 R10 PTE_U
0x00006CD4       CMP R5 0
0x00006CD8       BEQ uv_invalid
0x00006CE0       CMP R4 0
0x00006CE4       BEQ uv_check_read
0x00006CEC       AND R5 R10 PTE_W
0x00006CF0       CMP R5 0
0x00006CF4       BEQ uv_invalid
0x00006CFC       B uv_next

uv_check_read:
0x00006D04       AND R5 R10 PTE_R
0x00006D08       CMP R5 0
0x00006D0C       BEQ uv_invalid

uv_next:
0x00006D14       ADD R7 R7 1
0x00006D18       B uv_loop

uv_valid:
0x00006D20       LI R1 1
0x00006D28       POP R12
0x00006D2C       POP R11
0x00006D30       POP R10
0x00006D34       POP R9
0x00006D38       POP R8
0x00006D3C       POP R7
0x00006D40       POP R6
0x00006D44       POP R5
0x00006D48       RET

uv_invalid:
0x00006D4C       LI R1 0

0x00006D54       POP R12
0x00006D58       POP R11
0x00006D5C       POP R10
0x00006D60       POP R9
0x00006D64       POP R8
0x00006D68       POP R7
0x00006D6C       POP R6
0x00006D70       POP R5
0x00006D74       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00006D78       PUSH R5
0x00006D7C       PUSH R6
0x00006D80       PUSH R7
0x00006D84       LI R5 0
cfu_head:
0x00006D8C       CMP R2 0
0x00006D90       BEQ cfu_done
0x00006D98       OR R6 R1 R4
0x00006D9C       AND R6 R6 3
0x00006DA0       CMP R6 0
0x00006DA4       BEQ cfu_word
0x00006DAC       LDB R7 [R1]
0x00006DB0       STB R7 [R4]
0x00006DB4       ADD R1 R1 1
0x00006DB8       ADD R4 R4 1
0x00006DBC       ADD R5 R5 1
0x00006DC0       SUB R2 R2 1
0x00006DC4       B cfu_head
cfu_word:
0x00006DCC       CMP R2 4
0x00006DD0       BLT cfu_tail
0x00006DD8       LDW R7 [R1]
0x00006DDC       STW R7 [R4]
0x00006DE0       ADD R1 R1 4
0x00006DE4       ADD R4 R4 4
0x00006DE8       ADD R5 R5 4
0x00006DEC       SUB R2 R2 4
0x00006DF0       B cfu_word
cfu_tail:
0x00006DF8       CMP R2 0
0x00006DFC       BEQ cfu_done
0x00006E04       LDB R7 [R1]
0x00006E08       STB R7 [R4]
0x00006E0C       ADD R1 R1 1
0x00006E10       ADD R4 R4 1
0x00006E14       ADD R5 R5 1
0x00006E18       SUB R2 R2 1
0x00006E1C       B cfu_tail
cfu_done:
0x00006E24       MOV R1 R5
0x00006E28       POP R7
0x00006E2C       POP R6
0x00006E30       POP R5
0x00006E34       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x00006E38       PUSH R5
0x00006E3C       PUSH R6
0x00006E40       PUSH R7
0x00006E44       LI R5 0
ctu_head:
0x00006E4C       CMP R2 0
0x00006E50       BEQ ctu_done
0x00006E58       OR R6 R1 R4
0x00006E5C       AND R6 R6 3
0x00006E60       CMP R6 0
0x00006E64       BEQ ctu_word
0x00006E6C       LDB R7 [R4]
0x00006E70       STB R7 [R1]
0x00006E74       ADD R1 R1 1
0x00006E78       ADD R4 R4 1
0x00006E7C       ADD R5 R5 1
0x00006E80       SUB R2 R2 1
0x00006E84       B ctu_head
ctu_word:
0x00006E8C       CMP R2 4
0x00006E90       BLT ctu_tail
0x00006E98       LDW R7 [R4]
0x00006E9C       STW R7 [R1]
0x00006EA0       ADD R1 R1 4
0x00006EA4       ADD R4 R4 4
0x00006EA8       ADD R5 R5 4
0x00006EAC       SUB R2 R2 4
0x00006EB0       B ctu_word
ctu_tail:
0x00006EB8       CMP R2 0
0x00006EBC       BEQ ctu_done
0x00006EC4       LDB R7 [R4]
0x00006EC8       STB R7 [R1]
0x00006ECC       ADD R1 R1 1
0x00006ED0       ADD R4 R4 1
0x00006ED4       ADD R5 R5 1
0x00006ED8       SUB R2 R2 1
0x00006EDC       B ctu_tail
ctu_done:
0x00006EE4       MOV R1 R5
0x00006EE8       POP R7
0x00006EEC       POP R6
0x00006EF0       POP R5
0x00006EF4       RET

handle_debug:
    ; Debug trap - just return
0x00006EF8       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00006F00       CSRR R1 STVAL

0x00006F04       CMP R1 0
0x00006F08       BEQ handle_timer_irq

0x00006F10       CMP R1 1
0x00006F14       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00006F1C       LI R2 0x00102000
0x00006F24       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x00006F28       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00006F30       LI R2 0x00102000
0x00006F38       LI R3 0
0x00006F40       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x00006F44       LI R1 timer_ticks
0x00006F4C       LDW R2 [R1]
0x00006F50       ADD R2 R2 1
0x00006F54       STW R2 [R1]

    ;================================================================
    ; Wake sleeping tasks whose time has expired
    ;================================================================

0x00006F58       LI R1 sleep_waitq
0x00006F60       LDW R8 [R1]                ; R8 = current sleep_waitq mask
0x00006F64       LI R9 0                    ; R9 = tasks to wake bitmask
0x00006F6C       LI R3 0                    ; task index

timer_wake_scan:
0x00006F74       CMP R3 MAX_TASKS
0x00006F78       BGE timer_wake_scan_done

    ; Check if this task is in the sleep wait queue
0x00006F80       LI R6 1
0x00006F88       SHL R6 R6 R3               ; bit for this task
0x00006F8C       AND R7 R8 R6
0x00006F90       CMP R7 0
0x00006F94       BEQ timer_wake_next        ; not in sleep queue

    ; Task is sleeping, check if it's time to wake
; macro: GET_TASK_PTR R5, R3
0x00006F9C   LI R1 TASK_SIZE
0x00006FA4   MUL R3 R3 R1
0x00006FA8   LI R5 tasks
0x00006FB0   ADD R5 R5 R3
; macro: TASK_GET_WAKE_TIME R7, R5
0x00006FB4   LDW R7 [R5 + TASK_WAKE_TIME]
0x00006FB8       CMP R2 R7                  ; current time >= wake time?
0x00006FBC       BLT timer_wake_next

    ; Mark this task for wakeup
0x00006FC4       OR R9 R9 R6                 ; add to wake bitmask bitwize

timer_wake_next:
0x00006FC8       ADD R3 R3 1
0x00006FCC       B timer_wake_scan

timer_wake_scan_done:
    ; If no tasks to wake, skip
0x00006FD4       CMP R9 0
0x00006FD8       BEQ timer_no_wake

    ; Wake the expired tasks using our new function
0x00006FE0       LI R1 sleep_waitq
0x00006FE8       MOV R2 R9
0x00006FEC       BL waitq_wake_bitmask

timer_no_wake:

    ; Yield the CPU (reschedule and switch tasks)
0x00006FF4       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00006FFC       LI R2 0x00102000
0x00007004       LI R3 1
0x0000700C       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00007010       LI R1 uart_rx_waitq
0x00007018       BL waitq_wake_all
0x00007020       LI R1 uart_tx_waitq
0x00007028       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00007030       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x00007038       POP R1                  ; stval, informational only
0x0000703C       POP R1                  ; scause, informational only
0x00007040       POP R1
0x00007044       CSRW SSTATUS R1
0x00007048       POP R1
0x0000704C       CSRW SFLAGS R1
0x00007050       POP R1
0x00007054       CSRW SEPC R1
0x00007058       POP R1                  ; interrupted task SP
0x0000705C       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x00007060       POP R15
0x00007064       POP R14
0x00007068       POP R12
0x0000706C       POP R11
0x00007070       POP R10
0x00007074       POP R9
0x00007078       POP R8
0x0000707C       POP R7
0x00007080       POP R6
0x00007084       POP R5
0x00007088       POP R4
0x0000708C       POP R3
0x00007090       POP R2
0x00007094       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x00007098       CSRRW SP SSCRATCH SP
0x0000709C       SRET


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
.EQU SYS_MKDIR,     17      ; mkdir in overlay fsys
.EQU SYS_RMDIR,     18      ; rmdir in overlay fsys
.EQU SYS_UNLINK,     19     ; unlink in overlay fsys
.EQU SYS_COUNT,     20      ; update count


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

;.ORG 0x7300

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
    .WORD O_RDONLY           ; FILE_FLAGS

file_stdout:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD O_WRONLY           ; FILE_FLAGS

file_stderr:
    .WORD console_inode      ; FILE_INODE
    .WORD 0                  ; FILE_OFFSET
    .WORD O_WRONLY           ; FILE_FLAGS

console_inode:
    .WORD dev_console_ops    ; INODE_OPS
    .WORD con_device         ; INODE_PRIVATE
    .WORD INODE_CHAR         ; INODE_TYPE
    .WORD 0                  ; size
    .WORD 1                  ; refcnt

dev_console_ops:
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

null_ops:
    .WORD devfs_open
    .WORD null_read
    .WORD null_write
    .WORD devfs_close
    .WORD 0
    .WORD devfs_lookup
    .WORD 0
    .WORD 0
    .WORD 0
    .WORD 0

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

;=================================================================
; NSFS private vnode stored behind inode->private.
; Later this can hold a cached path key, namespace id, host handle,
; materialized size/type, dirty flags, and page-cache pointer.
.EQU NSFS_NODE_NAMESPACE, 0
.EQU NSFS_NODE_PATH,      4
.EQU NSFS_NODE_TYPE,      8
.EQU NSFS_NODE_SIZE,     12
.EQU NSFS_NODE_FLAGS,    16
.EQU NSFS_NODE_PATH_BUF, 20
.EQU NSFS_NODE_SIZEOF,   NSFS_NODE_PATH_BUF + EXEC_MAX_PATH
;================================================================

.EQU NSFS_DEFAULT_NS,     0
.EQU NSFS_MAX_NODES,     64

.EQU NSFS_TYPE_FILE,      1
.EQU NSFS_TYPE_DIR,       2

;=========================================================================
; payload wire (reply) format for NSFS index message. made by host and sent to guest.
; used for building the NSFS index table in guest memory.
;
;=========================================================================
.EQU NSFS_WIRE_NS,        0
.EQU NSFS_WIRE_TYPE,      4
.EQU NSFS_WIRE_SIZE,      8
.EQU NSFS_WIRE_VERSION,  12
.EQU NSFS_WIRE_PATH_LEN, 16
.EQU NSFS_WIRE_HDR_SIZEOF, 20

;=========================================================================
; NSFS index table item structure
;=========================================================================
.EQU NSFS_INDEX_NS,       0
.EQU NSFS_INDEX_TYPE,     4
.EQU NSFS_INDEX_SIZE,     8
.EQU NSFS_INDEX_VERSION, 12
.EQU NSFS_INDEX_PATH,    16
.EQU NSFS_INDEX_PATH_LEN,20
.EQU NSFS_INDEX_ENTRY_SIZEOF, 24

.EQU MAX_NSFS_NAMESPACES,    4
.EQU MAX_NSFS_INDEX_ENTRIES, 256
.EQU MAX_NSFS_DIRS,          512
.EQU MAX_NSFS_DIR_ENTRIES,   256


.EQU NSFS_DIR_NS,         0
.EQU NSFS_DIR_PATH,       4
.EQU NSFS_DIR_FLAGS,      8
.EQU NSFS_DIR_SIZEOF,    12

.EQU NSFS_DIR_IDX_NS,       0
.EQU NSFS_DIR_IDX_PARENT,   4
.EQU NSFS_DIR_IDX_NAME,     8
.EQU NSFS_DIR_IDX_INDEX,   12
.EQU NSFS_DIR_IDX_TYPE,    16
.EQU NSFS_DIR_IDX_SIZEOF,  20

.EQU NSFS_INDEX_PATH_POOL_SIZE, 4096

;=========================================================================
;
; nsfs_ops table for root inode and all other inodes.
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
; nsfs root inode and root path string. The root inode is a directory with no size and a refcnt of 1.
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
; nsfs root node. This is the private data for the root inode,
;which is a directory with no size and a refcnt of 1.
;=========================================================================

nsfs_root_node:
    .WORD NSFS_DEFAULT_NS
    .WORD nsfs_root_path
    .WORD INODE_DIR
    .WORD 0
    .WORD 0

;=========================================================================
;
;nsfs NODE pool and used idx array, index count, index table, and path pool for index entries.
;=========================================================================

nsfs_node_pool:
    .SPACE NSFS_MAX_NODES * NSFS_NODE_SIZEOF

nsfs_node_used:
    .SPACE NSFS_MAX_NODES * 4

nsfs_namespace_count:
    .WORD 0

nsfs_namespace_ids:
    .SPACE MAX_NSFS_NAMESPACES * 4

;=========================================================================
; nsfs index table and path pool for index entries.
;=========================================================================
nsfs_index_count:
    .WORD 0

nsfs_index_table:
    .SPACE MAX_NSFS_INDEX_ENTRIES * NSFS_INDEX_ENTRY_SIZEOF

nsfs_index_path_next:
    .WORD 0
; blob of paths for index entries,
; ptr is in NSFS_INDEX_PATH
; each path is a null-terminated string
nsfs_index_path_pool:
    .SPACE NSFS_INDEX_PATH_POOL_SIZE

;=========================================================================
; nsfs dir table and path pool for index entries.
;=========================================================================

; Derived directory table and child index for NSFS, partitioned by namespace.
nsfs_dir_count:
    .WORD 0

nsfs_dir_index_count:
    .WORD 0

nsfs_dir_table:
    .SPACE MAX_NSFS_DIRS * NSFS_DIR_SIZEOF

nsfs_dir_index:
    .SPACE MAX_NSFS_DIR_ENTRIES * NSFS_DIR_IDX_SIZEOF


;=========================================================================
;
;uart device struct and queues for RX/TX
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
; pipe ops (private)
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
    .WORD dev_console_ops
    .WORD con_device

dev_null:
    .WORD dev_null_name
    .WORD null_ops
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

; ==================================================
; dir_index entry
; ==================================================

.EQU DIR_IDX_PARENT, 0       ; parent directory ID
.EQU DIR_IDX_TAR,     4      ; TAR index number
.EQU DIR_IDX_NAME,    8      ; child name pointer
.EQU DIR_IDX_TYPE,   12      ; file/dir
.EQU DIR_IDX_SIZEOF, 16

;=================================================
; dir_table entry
;=================================================

.EQU  DIR_ID_PATH, 0      ; ID for every dirs like "/bin/" etc.

;=================================================

.EQU MAX_TAR_FILES, 64
.EQU MAX_TAR_DIRS, 64

;=============================================================
; TAR index entry layout
;=============================================================

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

; additional struc for dirs
tar_dir_index:      ; holds strucs for directories in the tarfs image,
                    ; set at boot time when the index is populated
    .SPACE DIR_IDX_SIZEOF * MAX_TAR_FILES
; dir ids table
tar_dir_table:      ; holds ptrs to the pathnames of directories in the tarfs image,
                    ; set at boot time when the index is populated
    .SPACE MAX_TAR_DIRS * 4

tar_dir_count:      ; number of directories in the tarfs image,
                    ; set at boot time when the index is populated
    .WORD 0

;==============================================================
; TARFS file header layout and constants
;==============================================================

.EQU TAR_NAME_OFF,      0
.EQU TAR_SIZE_OFF,    124
.EQU TAR_TYPE_OFF,    156

.EQU TAR_HEADER_SIZE, 512


tarfs_open:
0x0000FC51       LI R1 0
0x0000FC59       RET

tarfs_close:
0x0000FC5D       LI R1 0
0x0000FC65       RET

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

0x0000FC69       PUSH LR
0x0000FC6D       PUSH R8
0x0000FC71       PUSH R9
0x0000FC75       PUSH R10

0x0000FC79       MOV R8 R1              ; pathname
0x0000FC7D       LDB R2 [R8]
0x0000FC81       LI R3 47               ; accept normal absolute paths: "/etc/motd"
0x0000FC89       CMP R2 R3
0x0000FC8D       BNE lookup_path_ready
   ; ADD R8 R8 1           ; correction we dont skip leading / all paths for tarfs start from /...

lookup_path_ready:

0x0000FC95       LI R9 0                ; index

0x0000FC9D       LI R10 tar_count
0x0000FCA5       LDW R10 [R10]

tar_lookup_loop:

0x0000FCA9       CMP R9 R10
0x0000FCAD       BGE tar_lookup_not_found

    ; entry address

0x0000FCB5       LI R1 tar_index

0x0000FCBD       LI R2 TAR_IDX_SIZEOF
0x0000FCC5       MUL R3 R9 R2
0x0000FCC9       ADD R1 R1 R3            ;

    ; compare names

0x0000FCCD       MOV R2 R8

0x0000FCD1       LDW R1 [R1 + TAR_IDX_NAME]

0x0000FCD5       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x0000FCDD       CMP R1 1
0x0000FCE1       BEQ tar_lookup_found

0x0000FCE9       ADD R9 R9 1
0x0000FCED       B tar_lookup_loop

tar_lookup_found:

0x0000FCF5       LI R1 tar_index
0x0000FCFD       LI R2 TAR_IDX_SIZEOF
0x0000FD05       MUL R3 R9 R2
0x0000FD09       ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

0x0000FD0D       BL inode_alloc
0x0000FD15       CMP R1 0
0x0000FD19       BEQ tar_lookup_not_found
0x0000FD21       MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

0x0000FD25       MOV R1 R10              ; inode
0x0000FD29       LI  R2 tarfs_ops        ; ops table
0x0000FD31       MOV R3 R11              ; private = tar entry

0x0000FD35       LDW R4 [R11 + TAR_IDX_TYPE] ; FILE type
0x0000FD39       LDW R5 [R11 + TAR_IDX_SIZE] ; file size
0x0000FD3D       BL inode_init

0x0000FD45       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x0000FD49       POP R10
0x0000FD4D       POP R9
0x0000FD51       POP R8
0x0000FD55       POP LR
0x0000FD59       RET

tar_lookup_not_found:

0x0000FD5D       LI R1 0             ; R1 = NULL

0x0000FD65       POP R10
0x0000FD69       POP R9
0x0000FD6D       POP R8
0x0000FD71       POP LR
0x0000FD75       RET


; --------------------------------------------------
; tarfs_init - initialize the tarfs by scanning the tar archive and populating the index
; R1 = pointer to the start of the tar archive
; it also builds the directory table and index for directories for tarfs
; readdir and lookup operations
; --------------------------------------------------

tarfs_init:
0x0000FD79       PUSH LR

0x0000FD7D       BL tar_scan_archive
0x0000FD85       BL tar_build_dir_table
0x0000FD8D       BL tar_build_dir_index

0x0000FD95       POP LR
0x0000FD99       RET

;=-------------------------------------------------=
; tar_build_dir_index - build the directory index for tarfs
; this is used for readdir and lookup operations
; it scans the tar_index and builds a directory index for all directories in the tarfs image
;=-------------------------------------------------=

tar_build_dir_index:
0x0000FD9D       PUSH LR
0x0000FDA1       PUSH R8
0x0000FDA5       PUSH R9
0x0000FDA9       PUSH R10
0x0000FDAD       PUSH R11
0x0000FDB1       PUSH R12

0x0000FDB5       LI R8 tar_index
0x0000FDBD       LI R9 0                  ; TAR index number

dir_index_loop:
0x0000FDC5       LI R1 tar_count
0x0000FDCD       LDW R1 [R1]

0x0000FDD1       CMP R9 R1
0x0000FDD5       BGE dir_index_done

0x0000FDDD       MOV R1 R9
0x0000FDE1       BL tar_find_parent_dir

    ; ------------------------------------------------------------
    ; Did we find a parent?
    ; ------------------------------------------------------------
0x0000FDE9       li R4 -1
0x0000FDF1       CMP R1 R4
0x0000FDF5       BEQ dir_index_next

    ; ------------------------------------------------------------
    ; R1 = parent DIR_ID
    ; R2 = child name
    ; R3 = TAR type
    ;
    ; Add:
    ;
    ;   parent
    ;   tar index
    ;   child name
    ;   type
    ; ------------------------------------------------------------
    ; ------------------------------------------------------------
    ; R8 = pointer to TAR index (R1) entry
    ; ------------------------------------------------------------

0x0000FDFD       LI R4 tar_dir_index ;dir-index base

    ; R4 = R4 + R9 * DIR_IDX_SIZEOF
    ; compute address to struct item in tar_dir_index
0x0000FE05       LI R5 DIR_IDX_SIZEOF
0x0000FE0D       MUL R5 R9 R5
0x0000FE11       ADD R4 R4 R5    ; R4 = &tar_dir_index[R1]

    ; R1 = parent directory ID
    ; R9 = TAR index number
    ; R2 = child name pointer
    ; R3 = TAR type
    ; add entry to tar_dir_index

0x0000FE15       STW R1 [R4 + DIR_IDX_PARENT]
0x0000FE19       STW R9 [R4 + DIR_IDX_TAR]
0x0000FE1D       STW R2 [R4 + DIR_IDX_NAME]
0x0000FE21       STW R3 [R4 + DIR_IDX_TYPE]

dir_index_next:
0x0000FE25       ADD R9 R9 1
0x0000FE29       B dir_index_loop

dir_index_done:

0x0000FE31       POP R12
0x0000FE35       POP R11
0x0000FE39       POP R10
0x0000FE3D       POP R9
0x0000FE41       POP R8
0x0000FE45       POP LR
0x0000FE49       RET

; ================================================================
; tar_find_parent_dir
;
; IN:
;   R1 = TAR index number
;
; OUT:
;   R1 = parent DIR_ID
;   R2 = child name pointer
;   R3 = TAR type
;
; ================================================================

tar_find_parent_dir:
0x0000FE4D       PUSH LR
0x0000FE51       PUSH R8
0x0000FE55       PUSH R9
0x0000FE59       PUSH R10
0x0000FE5D       PUSH R11
0x0000FE61       PUSH R12

    ; ------------------------------------------------------------
    ; R8 = pointer to TAR index (R1) entry
    ; ------------------------------------------------------------

0x0000FE65       LI R8 tar_index

    ; R9 = R1 * TAR_IDX_SIZEOF
0x0000FE6D       LI R9 TAR_IDX_SIZEOF
0x0000FE75       MUL R9 R1 R9
0x0000FE79       ADD R8 R8 R9    ; R8 = &tar_index[R1]

    ; ------------------------------------------------------------
    ; Save information about the TAR object
    ; ------------------------------------------------------------

0x0000FE7D       LDW R10 [R8 + TAR_IDX_NAME]     ; R10 = full pathname
0x0000FE81       LDW R11 [R8 + TAR_IDX_TYPE]     ; R11 = type

    ; ------------------------------------------------------------
    ; R12 = directory ID we are testing
    ; ------------------------------------------------------------

0x0000FE85       LI R12 0

dir_find_table_loop:

    ; Have we checked all directories?

0x0000FE8D       LI R9 tar_dir_count
0x0000FE95       LDW R9 [R9]

0x0000FE99       CMP R12 R9
0x0000FE9D       BGE dir_find_parent_fail

    ; ------------------------------------------------------------
    ; Get directory pathname
    ;
    ; tar_dir_table[DIR_ID]
    ; ------------------------------------------------------------

0x0000FEA5       LI R9 tar_dir_table

0x0000FEAD       SHL R1 R12 2
0x0000FEB1       ADD R9 R9 R1

0x0000FEB5       LDW R9 [R9]                     ; R9 = directory path

    ; ------------------------------------------------------------
    ; Ask:
    ;
    ; Is R10 directly inside R9 ?
    ;
    ; IN:
    ;   R1 = parent path ie  "/bin/"
    ;   R2 = full object path ie  "/bin/cat"
    ;
    ; OUT:
    ;   R1 = 1 if yes
    ;   R2 = child name pointer
    ;
    ; ------------------------------------------------------------

0x0000FEB9       MOV R1 R9                       ; parent path
0x0000FEBD       MOV R2 R10                      ; object path

0x0000FEC1       BL tar_path_is_child    ;check object path is child of parent path

0x0000FEC9       CMP R1 0
0x0000FECD       BNE dir_found_parent

0x0000FED5       ADD R12 R12 1
0x0000FED9       B dir_find_table_loop


dir_found_parent:

    ;=------------------------------------------------------------=
    ; Return:
    ;
    ; R1 = directory ID
    ; R2 = child name
    ; R3 = TAR type
    ;=------------------------------------------------------------=

0x0000FEE1       MOV R1 R12
0x0000FEE5       MOV R3 R11

    ; R2 already returned by tar_path_is_child

0x0000FEE9       B dir_find_parent_done


dir_find_parent_fail:

    ; No parent found.
    ;
    ; For now return -1.
    ;

0x0000FEF1       LI R1 -1
0x0000FEF9       LI R2 0
0x0000FF01       LI R3 0
dir_find_parent_done:
0x0000FF09       POP R12
0x0000FF0D       POP R11
0x0000FF11       POP R10
0x0000FF15       POP R9
0x0000FF19       POP R8
0x0000FF1D       POP LR
0x0000FF21       RET

; ================================================================
; tar_path_is_child
;
; IN:
;   R1 = parent directory path - like "/bin/"
;   R2 = object full path - like "/bin/cat"
;
; OUT:
;   R1 = 1 if object is immediate child ie "/bin/cat" is child of "/bin/"
;   R1 = 0 otherwise
;   R2 = child name pointer when successful
;
; ================================================================


tar_path_is_child:
0x0000FF25       PUSH LR
0x0000FF29       PUSH R8
0x0000FF2D       PUSH R9
0x0000FF31       PUSH R10
0x0000FF35       PUSH R11

0x0000FF39       MOV R8 R1              ; R8 = parent path
0x0000FF3D       MOV R9 R2              ; R9 = object path


; ------------------------------------------------
; Compare parent path with beginning of object path
; ------------------------------------------------

compare_loop:
0x0000FF41       LDB R10 [R8]
0x0000FF45       LDB R11 [R9]
0x0000FF49       CMP R10 0
0x0000FF4D       BEQ parent_finished ;if parent path is empty, we have matched the parent path
0x0000FF55       CMP R10 R11
0x0000FF59       BNE not_child       ;if chars dont match, not a child
0x0000FF61       ADD R8 R8 1
0x0000FF65       ADD R9 R9 1
0x0000FF69       B compare_loop


; ------------------------------------------------
; Parent path matched.
;
; R9 now points at remainder of object path.
;
; Example:
;
; parent = "/bin/"
; object = "/bin/cat"
;
; R9 -> "cat"
; ------------------------------------------------

parent_finished:

    ; Empty remainder?
0x0000FF71       LDB R10 [R9]
0x0000FF75       CMP R10 0
0x0000FF79       BEQ not_child   ;if object path is empty, not a child

    ; Save child-name pointer
0x0000FF81       MOV R2 R9       ;when successful, R2 = child name pointer on return


; ------------------------------------------------
; Scan remainder of the object path for additional '/' characters
;
; We accept exactly ONE path component.
;
; "cat"       -> YES
; "sub/"      -> YES (directory)
; "sub/cat"   -> NO
; ------------------------------------------------

child_loop:

0x0000FF85       LDB R10 [R9]

    ; End of string = one component
0x0000FF89       CMP R10 0
0x0000FF8D       BEQ child_found ; ie "/bin/cat" is an immediate child of "/bin/"

    ; Another '/' means another component
0x0000FF95       LI  R5 47
0x0000FF9D       CMP R10 R5
0x0000FFA1       BEQ child_slash   ; check after slash ie "/bin/sub/cat" "c" - not imm child "null" imm child
0x0000FFA9       ADD R9 R9 1
0x0000FFAD       B child_loop
; ------------------------------------------------
; We found '/'
;
; It can be:
;
; "sub/"       -> trailing slash -> YES
; "sub/cat"    -> another component -> NO
; ------------------------------------------------

child_slash:
0x0000FFB5       ADD R9 R9 1
0x0000FFB9       LDB R10 [R9]
    ; '/' was the last character
    ; therefore this is a directory name
0x0000FFBD       CMP R10 0
0x0000FFC1       BEQ child_found

    ; Something follows '/'
    ; therefore there is another component
0x0000FFC9       B not_child

; ------------------------------------------------
; Success
; ------------------------------------------------
child_found:
0x0000FFD1       LI R1 1
0x0000FFD9       B tar_path_is_child_done
; ------------------------------------------------
; Not an immediate child
; ------------------------------------------------

not_child:
0x0000FFE1       LI R1 0
tar_path_is_child_done:
0x0000FFE9       POP R11
0x0000FFED       POP R10
0x0000FFF1       POP R9
0x0000FFF5       POP R8
0x0000FFF9       POP LR
0x0000FFFD       RET

;--------------------------------------------------
; build_dir_table - build the directory table for tarfs
;
;--------------------------------------------------

tar_build_dir_table:
0x00010001       PUSH LR
0x00010005       PUSH R8
0x00010009       PUSH R9
0x0001000D       PUSH R10
0x00010011       PUSH R11
0x00010015       PUSH R12

    ; root is always directory 0
0x00010019       LI R8 tar_dir_table
0x00010021       LI R9 root_path             ;put root path in dir_table[0]
0x00010029       STW R9 [R8]

0x0001002D       LI R10 1                    ; R10 = next dir id to assign
0x00010035       LI R11 tar_index            ; R11 = &tar_index[0]
0x0001003D       LI R12 0                    ; R12 = tar_count

dir_table_loop:

0x00010045       LI  R1 tar_count
0x0001004D       LDW R1 [R1]
0x00010051       CMP R12 R1
0x00010055       BGE dir_table_done

    ; Is this TAR entry a directory?
0x0001005D       LDW R1 [R11 + TAR_IDX_TYPE]     ;scan index to check if this tar entry is a directory
0x00010061       CMP R1 53                       ; 35 hex = '5' = directory type in tar header
0x00010065       BNE dir_table_next

    ; Add its pathname to tar_dir_table
0x0001006D       LDW R1 [R11 + TAR_IDX_NAME]     ; get pathname of this directory from tar_index

0x00010071       LI R8 tar_dir_table
0x00010079       SHL R9 R10 2
0x0001007D       ADD R8 R8 R9
0x00010081       STW R1 [R8]                     ; put pathname in tar_dir_table[R10]

0x00010085       ADD R10 R10 1

dir_table_next:
0x00010089       ADD R11 R11 TAR_IDX_SIZEOF
0x0001008D       ADD R12 R12 1
0x00010091       B dir_table_loop

dir_table_done:

0x00010099       LI R8 tar_dir_count
0x000100A1       STW R10 [R8]                    ; finish storing total directory count in tar_dir_count

0x000100A5       POP R12
0x000100A9       POP R11
0x000100AD       POP R10
0x000100B1       POP R9
0x000100B5       POP R8
0x000100B9       POP LR
0x000100BD       RET

;tarfs_init0:
; ------------------------------------------------
; tar_scan_archive
;
; Builds:
;   tar_index[]
;   tar_count
;   tar_limit
;
; R1 = TAR start
; ------------------------------------------------
tar_scan_archive:

0x000100C1       PUSH LR
0x000100C5       PUSH R8
0x000100C9       PUSH R9
0x000100CD       PUSH R10
0x000100D1       PUSH R11
0x000100D5       PUSH R12

0x000100D9       MOV R8 R1                  ; current tar header
0x000100DD       LI R11 tar_limit
0x000100E5       ADD R2 R1 R2
0x000100E9       STW R2 [R11]               ; exclusive end of archive
0x000100ED       LI R9 tar_index            ; current index entry
0x000100F5       LI R10 0                   ; file count

tar_scan_loop:
0x000100FD       CMP R10 MAX_TAR_FILES
0x00010101       BGE tar_done                ; check before writing the next index entry

0x00010109       LI R11 tar_limit
0x00010111       LDW R11 [R11]
0x00010115       LI R12 TAR_HEADER_SIZE
0x0001011D       ADD R12 R8 R12
0x00010121       CMP R12 R11
0x00010125       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x0001012D       LDB R11 [R8 + TAR_NAME_OFF]
0x00010131       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x00010135       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x0001013D       MOV R11 R8
0x00010141       ADD R11 R11 TAR_NAME_OFF
0x00010145       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x00010149       MOV R1 R8
0x0001014D       ADD R1 R1 TAR_SIZE_OFF
    ;R1 = ptr to TAR size field
0x00010151       BL tar_parse_octal         ; parse octal size from tar header field to binary integer
0x00010159       MOV R12 R1                 ; save file resulted binary size
0x0001015D       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00010161       MOV R11 R8
0x00010165       LI R2 TAR_HEADER_SIZE
0x0001016D       ADD R11 R11 R2
0x00010171       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x00010175       LI R2 TAR_TYPE_OFF
0x0001017D       ADD R2 R8 R2
0x00010181       LDB R11 [R2]
0x00010185       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00010189       ADD R10 R10 1               ; othewise go to next file count
0x0001018D       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------
0x00010191       MOV R11 R12
    ; round up to 512 boundary

0x00010195       LI R2 511
0x0001019D       ADD R11 R11 R2
0x000101A1       SHR R11 R11 9
0x000101A5       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x000101A9       LI R2 TAR_HEADER_SIZE
0x000101B1       ADD R8 R8 R2
0x000101B5       ADD R8 R8 R11           ; advance to next tar header
0x000101B9       LI R12 tar_limit
0x000101C1       LDW R12 [R12]
0x000101C5       CMP R8 R12
0x000101C9       BGTU tar_done            ; file data/padding extends beyond archive
0x000101D1       B tar_scan_loop

tar_done:

0x000101D9       LI R11 tar_count        ; store total file count for this tar archive in global variable
0x000101E1       STW R10 [R11]

0x000101E5       POP R12
0x000101E9       POP R11
0x000101ED       POP R10
0x000101F1       POP R9
0x000101F5       POP R8
0x000101F9       POP LR

0x000101FD       RET

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

0x00010201       PUSH R2
0x00010205       PUSH R3
0x00010209       PUSH R4
0x0001020D       LI   R2 0                  ; result
octal_loop:
0x00010215       LDB  R3 [R1]
    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32
0x00010219       CMP  R3 0
0x0001021D       BEQ  octal_done
0x00010225       LI   R4 32                 ; ' '
0x0001022D       CMP  R3 R4
0x00010231       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x00010239       LI   R4 48
0x00010241       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x00010245       SHL  R2 R2 3               ; multiply by 8
0x00010249       ADD  R2 R2 R3              ; add digit
0x0001024D       ADD  R1 R1 1               ; advance to next octal character
0x00010251       B    octal_loop
octal_done:
0x00010259       MOV  R1 R2                 ; return binary result in R1

0x0001025D       POP  R4
0x00010261       POP  R3
0x00010265       POP  R2
0x00010269       RET

; for kputs
newline:
    .ASCIIZ "\r\n"

tarfs_banner:
    .ASCIIZ "[TARFS]\r\n"

tarfs_dir_banner:
    .ASCIIZ "[TARFS_DIR]\r\n"

etc_path:
    .ASCIIZ "etc/"

bin_path:
    .ASCIIZ "bin/"

root_path:
    .ASCIIZ "/"

;=-------------------------------------------------------------=
;tar_find_dir_id - find the directory ID for a given pathname in the tar_dir_table
;IN:
;    R1 = directory pathname
;OUT:
;   R1 = DIR_ID or -1 if not found
;=-------------------------------------------------------------=
tar_find_dir_id:
0x00010294       PUSH LR
0x00010298       PUSH R8
0x0001029C       PUSH R9
0x000102A0       PUSH R10

0x000102A4       MOV R8 R1              ; directory pathname
0x000102A8       LI R9 0                ; index

tar_find_dir_loop:

0x000102B0       LI R10 tar_dir_count
0x000102B8       LDW R10 [R10]
0x000102BC       CMP R9 R10
0x000102C0       BGE tar_find_dir_not_found

    ; entry = tar_dir_table + i*sizeof(4)
0x000102C8       LI R1 tar_dir_table
0x000102D0       SHL R2 R9 2
0x000102D4       ADD R1 R1 R2

0x000102D8       LDW R2 [R1]            ; directory pathname from table
0x000102DC       MOV R1 R8              ; input pathname
0x000102E0       BL strcmp              ; compare pathnames
0x000102E8       CMP R1 1               ; strcmp returns 1 if match
0x000102EC       BEQ tar_find_dir_found

0x000102F4       ADD R9 R9 1
0x000102F8       B tar_find_dir_loop

tar_find_dir_found:
0x00010300       MOV R1 R9              ; return DIR_ID
0x00010304       B tar_find_dir_done

tar_find_dir_not_found:
0x0001030C       LI R1 -1               ; not found
tar_find_dir_done:
0x00010314       POP R10
0x00010318       POP R9
0x0001031C       POP R8
0x00010320       POP LR
0x00010324       RET

;==============================================================
; tarfs_dump_index - a simple debug function to print the contents of the tar index
; for each file, it prints the filename and size. This can be called from a debug
; syscall or from the kernel initialization code after tarfs_init to verify the
; index was populated correctly.
;==============================================================
tarfs_dump_index:

0x00010328       PUSH LR
0x0001032C       PUSH R8
0x00010330       PUSH R9
0x00010334       PUSH R10
0x00010338       LI R8 0
0x00010340       LI R10 tar_count
0x00010348       LDW R10 [R10]

0x0001034C       LI R1 tarfs_banner
0x00010354       BL kputs
dump_loop:
0x0001035C       CMP R8 R10
0x00010360       BGE dump_done
    ; entry = tar_index + i*sizeof(entry)
0x00010368       LI R1 tar_index
0x00010370       LI R2 TAR_IDX_SIZEOF
0x00010378       MUL R3 R8 R2
0x0001037C       ADD R9 R1 R3
    ; filename
0x00010380       LDW R2 [R9 + TAR_IDX_NAME]
    ; print string somehow
0x00010384       MOV R1 R2
0x00010388       BL kputs
    ; newline
0x00010390       LI R1 newline
0x00010398       BL kputs
0x000103A0       ADD R8 R8 1
0x000103A4       B dump_loop
dump_done:
0x000103AC       POP R10
0x000103B0       POP R9
0x000103B4       POP R8
0x000103B8       POP LR
0x000103BC       RET

tarfs_dump_dir_index:
0x000103C0       PUSH LR
0x000103C4       PUSH R8
0x000103C8       PUSH R9
0x000103CC       PUSH R10
0x000103D0       LI R8 0
0x000103D8       LI R10 tar_count
0x000103E0       LDW R10 [R10]

0x000103E4       LI R1 tarfs_dir_banner
0x000103EC       BL kputs
dir_dump_loop:
0x000103F4       CMP R8 R10
0x000103F8       BGE dir_dump_done
    ; entry = tar_index + i*sizeof(entry)
0x00010400       LI R1 tar_dir_index
0x00010408       LI R2 DIR_IDX_SIZEOF
0x00010410       MUL R3 R8 R2
0x00010414       ADD R9 R1 R3
    ; filename
0x00010418       LDW R2 [R9 + DIR_IDX_NAME]
    ; print string somehow
0x0001041C       MOV R1 R2
0x00010420       BL kputs
    ; newline
0x00010428       LI R1 newline
0x00010430       BL kputs
0x00010438       ADD R8 R8 1
0x0001043C       B dir_dump_loop
dir_dump_done:
0x00010444       POP R10
0x00010448       POP R9
0x0001044C       POP R8
0x00010450       POP LR
0x00010454       RET


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

0x00010458       PUSH LR
0x0001045C       PUSH R8
0x00010460       PUSH R9
0x00010464       PUSH R10
0x00010468       PUSH R11
0x0001046C       PUSH R12

0x00010470       MOV R8 R1
0x00010474       MOV R9 R2
0x00010478       MOV R10 R3

0x0001047C       CMP R10 0
0x00010480       BEQ tarfs_read_eof

0x00010488       PUSH R8
0x0001048C       PUSH R9
0x00010490       MOV R1 R9
0x00010494       MOV R2 R10
0x00010498       LI R3 1                    ; destination must be user-writable
0x000104A0       BL user_buffer_valid_range
0x000104A8       POP R9
0x000104AC       POP R8
0x000104B0       CMP R1 1
0x000104B4       BNE tarfs_read_fault

0x000104BC       LDW R11 [R8 + FILE_INODE]
0x000104C0       LDW R5  [R11 + INODE_TYPE]
0x000104C4       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x000104C8       LI  R2 INODE_DIR
0x000104D0       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x000104D4       BEQ tarfs_read_dir

0x000104DC       LDW R12 [R8 + FILE_OFFSET]
0x000104E0       LDW R4  [R11 + TAR_IDX_SIZE]

0x000104E4       CMP R12 R4
0x000104E8       BGEU tarfs_read_eof

0x000104F0       SUB R4 R4 R12             ; bytes remaining
0x000104F4       CMP R10 R4
0x000104F8       BLEU tarfs_read_count_ready
0x00010500       MOV R10 R4

tarfs_read_count_ready:
0x00010504       LDW R4 [R11 + TAR_IDX_DATA]
0x00010508       ADD R4 R4 R12             ; kernel source
0x0001050C       MOV R1 R9                 ; user destination
0x00010510       MOV R2 R10
0x00010514       BL copy_to_user

0x0001051C       ADD R12 R12 R1
0x00010520       STW R12 [R8 + FILE_OFFSET]
0x00010524       B tarfs_read_done

tarfs_read_dir:
    ; directory read – call our dir read function
0x0001052C       MOV R1 R8
0x00010530       MOV R2 R9
0x00010534       MOV R3 R10
0x00010538       BL tarfs_readdir
0x00010540       B tarfs_read_done   ; jump to the common return path

tarfs_read_fault:
0x00010548       LI R1 ERR_FAULT
0x00010550       B tarfs_read_done

tarfs_read_eof:
0x00010558       LI R1 0

tarfs_read_done:
0x00010560       POP R12
0x00010564       POP R11
0x00010568       POP R10
0x0001056C       POP R9
0x00010570       POP R8
0x00010574       POP LR
0x00010578       RET

tarfs_write:
0x0001057C       LI R1 ERR_ACCES
0x00010584       RET

;=--------------------------------------------------------------=
; tarfs_readdir
;
; R1 = file*
; R2 = user buffer
; R3 = buffer length
;
; FILE_OFFSET = position in tar_dir_index
;
; inode->private = DIR_ID
;=--------------------------------------------------------------=

tarfs_readdir:

0x00010588       PUSH LR
0x0001058C       PUSH R8
0x00010590       PUSH R9
0x00010594       PUSH R10
0x00010598       PUSH R11
0x0001059C       PUSH R12

    ; ------------------------------------------------------------
    ; Validate user buffer
    ; ------------------------------------------------------------

0x000105A0       MOV R8 R2                  ; save user buffer
0x000105A4       PUSH R8

0x000105A8       MOV R9 R3                  ; save buffer length
0x000105AC       MOV R12 R1                 ; save file*

0x000105B0       CMP R9 DIRENT_SIZEOF
0x000105B4       BLT readdir_short

0x000105BC       MOV R1 R8
0x000105C0       LI  R2 DIRENT_SIZEOF
0x000105C8       LI  R3 1
0x000105D0       BL  user_buffer_valid_range

0x000105D8       CMP R1 1
0x000105DC       BNE readdir_fault

    ; ------------------------------------------------------------
    ; Get directory ID
    ; ------------------------------------------------------------

0x000105E4       LDW R4 [R12 + FILE_INODE]
0x000105E8       LDW R5 [R4 + INODE_PRIVATE]
0x000105EC       CMP R5 0
0x000105F0       BEQ readdir_eof

0x000105F8       LDW R10 [R5 + TAR_IDX_NAME] ; R10 = full path of directory (with trailing /)
0x000105FC       MOV R1 R10
0x00010600       BL tar_find_dir_id
0x00010608       LI  r2 -1
0x00010610       cmp r1 r2
0x00010614       beq readdir_fault
0x0001061C       mov r5 r1
    ; R5 = DIR_ID

    ; ------------------------------------------------------------
    ; Current position
    ;
    ; FILE_OFFSET is now an index into tar_dir_index[]
    ; ------------------------------------------------------------

0x00010620       LDW R11 [R12 + FILE_OFFSET]             ;R11 index

    ; ================================================================
    ; Scan tar_dir_index
    ; ================================================================

readdir_tar_dir_index_scan:

0x00010624       LI R1 tar_count
0x0001062C       LDW R1 [R1]
0x00010630       MOV R6 R11 ; just for this test
    ;we will use R6 to hold the current index in previos readdir(0)
0x00010634       CMP R11 R1
0x00010638       BGE readdir_nsfs_start

    ; ------------------------------------------------------------
    ; R7 = &tar_dir_index[R11]
    ; ------------------------------------------------------------

0x00010640       LI R7 tar_dir_index
0x00010648       LI R1 DIR_IDX_SIZEOF
0x00010650       MUL R3 R11 R1
0x00010654       ADD R7 R7 R3

    ; ------------------------------------------------------------
    ; Is this entry a child of our directory?
    ;
    ; tar_dir_index.parent == DIR_ID
    ; ------------------------------------------------------------

0x00010658       LDW R1 [R7 + DIR_IDX_PARENT]
0x0001065C       CMP R1 R5
0x00010660       BNE readdir_tar_skip

    ; ------------------------------------------------------------
    ; Found directory entry
    ;
    ; R7 = tar_dir_index entry
    ; ------------------------------------------------------------

0x00010668       LDW R9 [R7 + DIR_IDX_NAME]     ; child name

    ; ------------------------------------------------------------
    ; Get TAR entry
    ;
    ; We still need size/type, so use TAR index number.
    ; ------------------------------------------------------------

0x0001066C       LDW R6 [R7 + DIR_IDX_TAR]

0x00010670       LI R1 TAR_IDX_SIZEOF
0x00010678       MUL R3 R6 R1
0x0001067C       LI R1 tar_index
0x00010684       ADD R1 R1 R3
    ; R1 = &tar_index[tar_number]
0x00010688       PUSH R1 ;save tar entry pointer
    ; ------------------------------------------------------------
    ; Build dirent in kernel buffer
    ; ------------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x0001068C   LI R1 CURRENT_TASK
0x00010694   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00010698   LI R1 TASK_SIZE
0x000106A0   MUL R3 R4 R1
0x000106A4   LI R5 tasks
0x000106AC   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R2, R5
0x000106B0   LDW R2 [R5 + TASK_KBUF_WR_PTR]

0x000106B4       POP R1  ;restore tar entry pointer

    ; R2 = kernel write buffer
    ; ------------------------------------------------------------
    ; d_ino
    ;
    ; For now use TAR index + 1
    ; ------------------------------------------------------------

0x000106B8       ADD R3 R6 1
0x000106BC       STW R3 [R2 + DIRENT_INODE]

    ; ------------------------------------------------------------
    ; d_size
    ; ------------------------------------------------------------

0x000106C0       LDW R3 [R1 + TAR_IDX_SIZE]
0x000106C4       STW R3 [R2 + DIRENT_SIZE]

    ; ------------------------------------------------------------
    ; d_type
    ; ------------------------------------------------------------

0x000106C8       LDW R3 [R7 + DIR_IDX_TYPE]
0x000106CC       LI R1 INODE_DIR

0x000106D4       CMP R3 R1
0x000106D8       BEQ readdir_tar_type_dir

0x000106E0       LI R3 DT_REG
0x000106E8       B readdir_tar_type_done

readdir_tar_type_dir:

0x000106F0       LI R3 DT_DIR

readdir_tar_type_done:

0x000106F8       STW R3 [R2 + DIRENT_TYPE]

    ; ------------------------------------------------------------
    ; d_name
    ; ------------------------------------------------------------

0x000106FC       MOV R3 R2
0x00010700       ADD R3 R3 DIRENT_NAME

    ; child name is R9

0x00010704       LI R6 0

readdir_tar_copy_name:

0x0001070C       CMP R6 63
0x00010710       BGE readdir_tar_copy_name_done

0x00010718       LDB R10 [R9 + R6]

0x0001071C       CMP R10 0
0x00010720       BEQ readdir_tar_copy_name_done
0x00010728       LI R1 47
0x00010730       CMP R10 R1
0x00010734       BEQ readdir_tar_copy_name_done

0x0001073C       STB R10 [R3 + R6]

0x00010740       ADD R6 R6 1
0x00010744       B readdir_tar_copy_name

readdir_tar_copy_name_done:

0x0001074C       LI R10 0
0x00010754       STB R10 [R3 + R6]

    ; ------------------------------------------------------------
    ; Advance FILE_OFFSET
    ;
    ; IMPORTANT:
    ; FILE_OFFSET is tar_dir_index position now.
    ; ------------------------------------------------------------

0x00010758       ADD R11 R11 1
0x0001075C       STW R11 [R12 + FILE_OFFSET]
    ;special for this test R2 - kernel buffer pointer
0x00010760       MOV R1 R2
0x00010764       b readdir_ops_go_on

readdir_tar_skip:

0x0001076C       ADD R11 R11 1
0x00010770       B readdir_tar_dir_index_scan

    ; ------------------------------------------------------------
    ; Copy dirent to user
    ; ------------------------------------------------------------

0x00010778       LI R2 DIRENT_SIZEOF
0x00010780       MOV R4 R1              ; <-- careful: R1 currently tar entry
    ; We need kernel buffer instead.

    ; We need to preserve the kernel buffer pointer here.


; --------------------------------------------------
; tarfs_readdir0 - read next directory entry into user buffer
;
; R1 = file* (opened directory)
; R2 = user buffer (struct dirent*)
; R3 = buffer length (should be >= DIRENT_SIZEOF)
;
; returns:
;   R1 = DIRENT_SIZEOF (74) on success, 0 on EOF, negative errno
; --------------------------------------------------

tarfs_readdir0:
0x00010784       PUSH LR
0x00010788       PUSH R8
0x0001078C       PUSH R9
0x00010790       PUSH R10
0x00010794       PUSH R11
0x00010798       PUSH R12

    ; ---- validate user buffer ----
0x0001079C       MOV R8 R2                 ; save user buffer + to stack
0x000107A0       PUSH R8
0x000107A4       MOV R9 R3                 ; save length
0x000107A8       MOV R12 R1                ; save file ptr
0x000107AC       CMP R9 DIRENT_SIZEOF
0x000107B0       BLT readdir_short         ; not enough space for one entry

    ;PUSH R9
0x000107B8       MOV R1 R8
0x000107BC       LI  R2 DIRENT_SIZEOF
0x000107C4       LI  R3 1                  ; write access
0x000107CC       BL  user_buffer_valid_range
    ;POP R9
0x000107D4       CMP R1 1
0x000107D8       BNE readdir_fault

    ; ---- get inode and private data ----
0x000107E0       LDW R4 [R12 + FILE_INODE]    ; R4 = inode* r12 -file ptf
0x000107E4       LDW R5 [R4 + INODE_PRIVATE] ; R5 = tar index entry for the directory itself
0x000107E8       CMP R5 0
0x000107EC       BEQ readdir_eof

    ; get directory prefix from that tar entry (e.g., "etc/")
0x000107F4       LDW R10 [R5 + TAR_IDX_NAME] ; R10 = full path of directory (with trailing /)

    ; load current entry index from file offset
0x000107F8       LDW R11 [R12 + FILE_OFFSET] ; R11 = index (number of entries already returned)

    ; ---- scan tar index from this index ----
    ;LI R12 tar_count
    ;LDW R12 [R12]             ; total number of tar entries
0x000107FC       MOV R6 R11                ; current scan index

readdir_scan:
0x00010800       LI  R1 tar_count          ;total number entryes in index count
0x00010808       LDW R1 [R1]
0x0001080C       CMP R6 R1
0x00010810       BGE readdir_nsfs_start    ; no more tar entries; append overlay entries

    ; entry = tar_index + R6 * TAR_IDX_SIZEOF
0x00010818       LI R1 tar_index
0x00010820       LI R2 TAR_IDX_SIZEOF
0x00010828       MUL R3 R6 R2
0x0001082C       ADD R7 R1 R3              ; R7 = &tar_index[R6]

    ; check if this entry's name starts with the directory prefix
0x00010830       LDW R1 [R7 + TAR_IDX_NAME]
0x00010834       MOV R2 R10
0x00010838       BL str_prefix            ; check if tar_index entry name ie etc/motd matches prefix etc/
0x00010840       CMP R1 1
0x00010844       BNE readdir_skip

    ; skip the directory entry itself (exact match)
0x0001084C       LDW R1 [R7 + TAR_IDX_NAME]
0x00010850       MOV R2 R10
0x00010854       BL strcmp                ; ie skip if we read 'etc/' == etc/
0x0001085C       CMP R1 1
0x00010860       BEQ readdir_skip

    ; ---- found a matching file/directory ----
    ; skip the prefix to get the relative component
0x00010868       LDW R1 [R7 + TAR_IDX_NAME]
0x0001086C       MOV R2 R10
0x00010870       BL skip_prefix            ; R1 = pointer after prefix omit prefix - just filename 'etc/bin' -> bin
0x00010878       MOV R9 R1                 ; R9 = component name (e.g., "motd" (file) or "network/ (subdir)")

    ; compute the component length up to next '/'
0x0001087C       MOV R1 R9
0x00010880       BL path_component_len     ; R1 = component length (L)
0x00010888       MOV R8 R1                 ; R8 = component name length

    ; clamp to DIRENT_NAME_LEN - 1 to avoid overflow
0x0001088C       LI R2 63
0x00010894       CMP R8 R2
0x00010898       BLE readdir_name_ok
0x000108A0       MOV R8 63
readdir_name_ok:
    ; save R6 cureent entry index
0x000108A4       MOV R11 R6
    ;get type
0x000108A8       LDW R6  [R7 + TAR_IDX_TYPE]  ;R6  R11 = tar type (0=file, 5=dir)

    ; map tar type to DT_* constants
0x000108AC       LI  R1 INODE_DIR     ;adapted 35hex yess
0x000108B4       CMP R6 R1
    ;CMP R6 5            ;needs to be adapted 35hex
0x000108B8       BEQ readdir_type_dir
0x000108C0       LI R6 DT_REG               ; default type to regular r11 - file
0x000108C8       B readdir_type_done
readdir_type_dir:
0x000108D0       LI R6 DT_DIR               ; switch type R11 - dir
readdir_type_done:

    ; ---- build struct dirent in KBUF_WR ----
; macro: GET_CURR_TASK_IDX R4
0x000108D8   LI R1 CURRENT_TASK
0x000108E0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000108E4   LI R1 TASK_SIZE
0x000108EC   MUL R3 R4 R1
0x000108F0   LI R5 tasks
0x000108F8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x000108FC   LDW R1 [R5 + TASK_KBUF_WR_PTR]


   ; GET_CURR_TASK_IDX R2
   ; GET_TASK_PTR R2, R2
   ; TASK_GET_KBUF_WR R5, R2    ; R5 = kernel write buffer

    ; d_ino = index + 1 (dummy); R1 = kernel write buffer - form dirent stuc with read dir-entry
0x00010900       ADD R3 R11 1
0x00010904       STW R3 [R1 + DIRENT_INODE]
    ; d_type = DT_REG or DT_DIR
0x00010908       STW R6 [R1 + DIRENT_TYPE]

    ; get size from tar entry
0x0001090C       LDW R2  [R7 + TAR_IDX_SIZE]  ; R12 = file size
    ; d_size = file size
0x00010910       STW R2  [R1 + DIRENT_SIZE]

    ; ---- update file offset to next entry ----
    ;ADD R6 R6 1
0x00010914       STW R3 [R12 + FILE_OFFSET] ; store new index R11+1 for next read


    ; d_name = component name (copy up to 64 bytes)
0x00010918       MOV R2 R9                  ; source name R9 = component name (e.g., "motd" (file) or "network/ (subdir)")
0x0001091C       ADD R3 R1 DIRENT_NAME      ; destination dirent struc in KBUF_WR
0x00010920       LI  R6 0                   ; index

readdir_copy_name:
0x00010928       CMP R6 R8                  ;R8 = component name length
0x0001092C       BGE readdir_copy_name_done
0x00010934       LDB R10 [R2 + R6]
0x00010938       LI R1 47
0x00010940       CMP R10 R1
0x00010944       BEQ readdir_copy_name_done
0x0001094C       STB R10 [R3 + R6]
0x00010950       ADD R6 R6 1
0x00010954       B readdir_copy_name

readdir_copy_name_done:
    ; NUL-terminate
0x0001095C       LI R10 0
0x00010964       STB R10 [R3 + R6]

 ; new readdir func jumps here
readdir_ops_go_on:
    ; ---- copy whole dirent (DIRENT_SIZEOF bytes) to user buffer ----

0x00010968       LI  R2 DIRENT_SIZEOF      ; len dirent
0x00010970       MOV R4 R1                 ; kernel source (KBUF_WR)
0x00010974       POP R1                    ; user buffer (original)
    ;MOV R1 R8                 ; user buffer (original)
0x00010978       BL copy_to_user
0x00010980       CMP R1 DIRENT_SIZEOF
0x00010984       BNE readdir_fault

    ; return number of bytes written (DIRENT_SIZEOF)
0x0001098C       MOV R1 DIRENT_SIZEOF
0x00010990       POP R12
0x00010994       POP R11
0x00010998       POP R10
0x0001099C       POP R9
0x000109A0       POP R8
0x000109A4       POP LR
0x000109A8       RET

readdir_skip:
0x000109AC       ADD R6 R6 1
0x000109B0       B readdir_scan

readdir_nsfs_start:
0x000109B8       LI R1 tar_count
0x000109C0       LDW R1 [R1]
0x000109C4       SUB R6 R6 R1              ; convert merged offset to child-index position

    ; Resolve this directory in the default namespace. The child index stores
    ; parent IDs, so descendants cannot leak into an ancestor's listing.
0x000109C8       LI R1 NSFS_DEFAULT_NS
0x000109D0       MOV R2 R10
0x000109D4       BL nsfs_find_dir_id
0x000109DC       LI R2 -1
0x000109E4       CMP R1 R2
0x000109E8       BEQ readdir_eof
0x000109F0       MOV R5 R1                  ; NSFS parent directory ID

readdir_nsfs_scan:
0x000109F4       LI R1 nsfs_dir_index_count
0x000109FC       LDW R1 [R1]
0x00010A00       CMP R6 R1
0x00010A04       BGE readdir_eof

    ; R6 walks the derived child records, not all object paths.
0x00010A0C       LI R1 NSFS_DIR_IDX_SIZEOF
0x00010A14       MUL R3 R6 R1
0x00010A18       LI R7 nsfs_dir_index
0x00010A20       ADD R7 R7 R3              ; R7 = &nsfs_dir_index[R6]

0x00010A24       LDW R1 [R7 + NSFS_DIR_IDX_NS]
0x00010A28       CMP R1 NSFS_DEFAULT_NS
0x00010A2C       BNE readdir_nsfs_skip

0x00010A34       LDW R1 [R7 + NSFS_DIR_IDX_PARENT]
0x00010A38       CMP R1 R5
0x00010A3C       BNE readdir_nsfs_skip

    ; The matched child record provides its basename and object-table index.
0x00010A44       LDW R8 [R7 + NSFS_DIR_IDX_INDEX]
0x00010A48       MOV R11 R6                 ; retain child-index cursor for FILE_OFFSET

; macro: GET_CURR_TASK_IDX R4
0x00010A4C   LI R1 CURRENT_TASK
0x00010A54   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00010A58   LI R1 TASK_SIZE
0x00010A60   MUL R3 R4 R1
0x00010A64   LI R5 tasks
0x00010A6C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00010A70   LDW R1 [R5 + TASK_KBUF_WR_PTR]

    ; Resolve size from the source object; the child record supplies name/type.
0x00010A74       LI R2 NSFS_INDEX_ENTRY_SIZEOF
0x00010A7C       MUL R2 R8 R2
0x00010A80       LI R4 nsfs_index_table
0x00010A88       ADD R4 R4 R2              ; R4 = matching NSFS object entry
0x00010A8C       MOV R3 R8
0x00010A90       ADD R3 R3 1
0x00010A94       STW R3 [R1 + DIRENT_INODE]

0x00010A98       LDW R2 [R4 + NSFS_INDEX_SIZE]
0x00010A9C       STW R2 [R1 + DIRENT_SIZE]
0x00010AA0       LDW R2 [R7 + NSFS_DIR_IDX_TYPE]
0x00010AA4       CMP R2 NSFS_TYPE_DIR
0x00010AA8       BEQ readdir_nsfs_type_dir
0x00010AB0       LI R2 DT_REG
0x00010AB8       B readdir_nsfs_type_done
readdir_nsfs_type_dir:
0x00010AC0       LI R2 DT_DIR
readdir_nsfs_type_done:
0x00010AC8       STW R2 [R1 + DIRENT_TYPE]

0x00010ACC       LDW R2 [R7 + NSFS_DIR_IDX_NAME]
0x00010AD0       ADD R3 R1 DIRENT_NAME
0x00010AD4       LI R6 0
readdir_nsfs_copy_name:
0x00010ADC       CMP R6 63
0x00010AE0       BGE readdir_nsfs_copy_done
0x00010AE8       LDB R10 [R2 + R6]
0x00010AEC       CMP R10 0
0x00010AF0       BEQ readdir_nsfs_copy_done
0x00010AF8       CMP R10 47
0x00010AFC       BEQ readdir_nsfs_copy_done
0x00010B04       STB R10 [R3 + R6]
0x00010B08       ADD R6 R6 1
0x00010B0C       B readdir_nsfs_copy_name
readdir_nsfs_copy_done:
0x00010B14       LI R10 0
0x00010B1C       STB R10 [R3 + R6]

    ; Persist the next global merged position before copying the dirent out.
0x00010B20       LI R2 tar_count
0x00010B28       LDW R2 [R2]
0x00010B2C       ADD R2 R2 R11
0x00010B30       ADD R2 R2 1
0x00010B34       STW R2 [R12 + FILE_OFFSET]

0x00010B38       B readdir_ops_go_on

readdir_nsfs_skip:
0x00010B40       ADD R6 R6 1
0x00010B44       LI R1 tar_count
0x00010B4C       LDW R1 [R1]
0x00010B50       ADD R2 R1 R6
0x00010B54       STW R2 [R12 + FILE_OFFSET]
0x00010B58       B readdir_nsfs_scan

readdir_eof:
0x00010B60       Pop R1          ;bc we saved r8 inside loop
0x00010B64       LI R1 0
0x00010B6C       POP R12
0x00010B70       POP R11
0x00010B74       POP R10
0x00010B78       POP R9
0x00010B7C       POP R8
0x00010B80       POP LR
0x00010B84       RET

readdir_short:
0x00010B88       Pop R1
0x00010B8C       LI R1 ERR_FAULT
0x00010B94       POP R12
0x00010B98       POP R11
0x00010B9C       POP R10
0x00010BA0       POP R9
0x00010BA4       POP R8
0x00010BA8       POP LR
0x00010BAC       RET

readdir_fault:
0x00010BB0       Pop R1
readdir_fault_after_user_pop:
0x00010BB4       LI R1 ERR_FAULT
0x00010BBC       POP R12
0x00010BC0       POP R11
0x00010BC4       POP R10
0x00010BC8       POP R9
0x00010BCC       POP R8
0x00010BD0       POP LR
0x00010BD4       RET


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

0x00010BD8       PUSH LR
0x00010BDC       PUSH R8
0x00010BE0       PUSH R9
0x00010BE4       PUSH R10
0x00010BE8       PUSH R11

0x00010BEC       MOV R8 R1              ; save directory path
0x00010BF0       LI R9 0                ; index

0x00010BF8       LI R10 tar_count
0x00010C00       LDW R10 [R10]
tr_loop:
0x00010C04       CMP R9 R10
0x00010C08       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x00010C10       LI R1 tar_index
0x00010C18       LI R2 TAR_IDX_SIZEOF
0x00010C20       MUL R3 R9 R2
0x00010C24       ADD R11 R1 R3
    ; entry name
0x00010C28       LDW R1 [R11 + TAR_IDX_NAME]
0x00010C2C       MOV R2 R8                       ; src dirname "etc/"
0x00010C30       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x00010C38       CMP R1 1
0x00010C3C       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x00010C44       LDW R1 [R11 + TAR_IDX_NAME]
0x00010C48       MOV R2 R8                       ; prefix
0x00010C4C       BL skip_prefix                  ; omit prefix nd print just filename

0x00010C54       MOV R12 R1         ; save component ptr
0x00010C58       BL path_component_len ; out R1-length
0x00010C60       MOV R2 R1
0x00010C64       MOV R1 R12
0x00010C68       BL kputsn   ; r1-ptr r2-len of string

0x00010C70       LI R1 newline
0x00010C78       BL kputs

tr_next:
0x00010C80       ADD R9 R9 1                     ;to next entry for check
0x00010C84       B tr_loop
tr_done:
0x00010C8C       POP R11
0x00010C90       POP R10
0x00010C94       POP R9
0x00010C98       POP R8
0x00010C9C       POP LR
0x00010CA0       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:
0x00010CA4       PUSH LR
0x00010CA8       PUSH R8
0x00010CAC       MOV R8 R1

kputs_loop:
0x00010CB0       LDB R1 [R8]

0x00010CB4       CMP R1 0
0x00010CB8       BEQ kputs_done

0x00010CC0       BL uart_putc

0x00010CC8       ADD R8 R8 1

0x00010CCC       B kputs_loop

kputs_done:
0x00010CD4       POP R8
0x00010CD8       POP LR
0x00010CDC       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x00010CE0       PUSH LR
0x00010CE4       PUSH R8
0x00010CE8       PUSH R9
0x00010CEC       MOV R8 R1
0x00010CF0       MOV R9 R2
kputsn_loop:
0x00010CF4       CMP R9 0
0x00010CF8       BEQ kputsn_done
0x00010D00       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x00010D04       BL uart_putc
0x00010D0C       ADD R8 R8 1
0x00010D10       SUB R9 R9 1
0x00010D14       B kputsn_loop
kputsn_done:
0x00010D1C       POP R9
0x00010D20       POP R8
0x00010D24       POP LR
0x00010D28       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x00010D2C       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x00010D34       LDW R2 [R3 + 4]   ; read UART status register
0x00010D38       AND R2 R2 2       ; check if TX ready (bit 1)
0x00010D3C       CMP R2 0
0x00010D40       BEQ poll

0x00010D48       STW R1 [R3 + 0]   ; R1 is the character value
0x00010D4C       RET



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
0x00010D50       PUSH R8
0x00010D54       PUSH R9
0x00010D58       PUSH R10

0x00010D5C       MOV R9 R1                  ; preserve wait queue pointer
0x00010D60       MOV R10 R2                 ; preserve debug wait reason
0x00010D64       MOV R8 R3                  ; preserve task state to set

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x00010D68   LI R1 CURRENT_TASK
0x00010D70   LDW R2 [R1]

0x00010D74       LI R4 1
0x00010D7C       SHL R4 R4 R2               ; R4 = bit for current task
0x00010D80       LDW R5 [R9 + WQ_MASK]
0x00010D84       OR R5 R5 R4
0x00010D88       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00010D8C   LI R1 TASK_SIZE
0x00010D94   MUL R3 R2 R1
0x00010D98   LI R5 tasks
0x00010DA0   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00010DA4   LI R1 TASK_BLOCKED_IO
0x00010DAC   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00010DB0   STW R10 [R5 + TASK_WAIT]

; addition trick if R3 is set as TASK_SLEEPING then we also set the state to TASK_SLEEPING for syscall sleep/waitpid
0x00010DB4       CMP R8 TASK_SLEEPING
0x00010DB8       BNE waitq_prepare_done
; macro: TASK_SET_STATE R5, TASK_SLEEPING
0x00010DC0   LI R1 TASK_SLEEPING
0x00010DC8   STW R1 [R5 + TASK_STATE]

waitq_prepare_done:
0x00010DCC       POP R10
0x00010DD0       POP R9
0x00010DD4       POP R8
0x00010DD8       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00010DDC       PUSH R9

0x00010DE0       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00010DE4   LI R1 CURRENT_TASK
0x00010DEC   LDW R2 [R1]

0x00010DF0       LDW R4 [R9 + WQ_MASK]

0x00010DF4       LI  R5 1
0x00010DFC       SHL R5 R5 R2        ;shift to position of current task bit

0x00010E00       NOT R5 R5           ; invert to get mask for clearing this bit

0x00010E04       AND R4 R4 R5        ; clear current task bit

0x00010E08       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x00010E0C   LI R1 TASK_SIZE
0x00010E14   MUL R3 R2 R1
0x00010E18   LI R5 tasks
0x00010E20   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x00010E24   LI R1 TASK_READY
0x00010E2C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x00010E30   LI R1 WAIT_NONE
0x00010E38   STW R1 [R5 + TASK_WAIT]

0x00010E3C       POP R9
0x00010E40       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x00010E44       PUSH LR
0x00010E48       BL schedule_call
0x00010E50       POP LR
0x00010E54       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x00010E58       PUSH LR

0x00010E5C       MOV R9 R1
0x00010E60       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00010E64       LI R10 0
0x00010E6C       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x00010E70       LI R2 0                    ; task index

wq_wake_loop:
0x00010E78       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x00010E7C       BGE wq_wake_done

0x00010E84       LI R3 1
0x00010E8C       SHL R3 R3 R2               ; R3 = bit for task R2
0x00010E90       AND R4 R8 R3
0x00010E94       CMP R4 0
0x00010E98       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00010EA0   LI R1 TASK_SIZE
0x00010EA8   MUL R3 R2 R1
0x00010EAC   LI R5 tasks
0x00010EB4   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00010EB8   LI R1 TASK_READY
0x00010EC0   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00010EC4   LI R1 WAIT_NONE
0x00010ECC   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00010ED0       ADD R2 R2 1
0x00010ED4       B wq_wake_loop

wq_wake_done:
0x00010EDC       POP LR
0x00010EE0       RET

waitq_wake_bitmask:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = bitmask of tasks to wake (1 = wake, 0 = ignore)
    ; Wakes every task currently recorded in the R2 bitmask.
    ;================================================================

0x00010EE4       PUSH LR

0x00010EE8       MOV R9 R1
0x00010EEC       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00010EF0       MOV R10 R2                 ;
0x00010EF4       NOT R10 R10                ; invert bitmask to clear only specified tasks
0x00010EF8       AND R10 R8 R10             ; clear only specified tasks
0x00010EFC       STW R10 [R9 + WQ_MASK]     ; update queue entries to remove (tobe) woken  tasks

0x00010F00       MOV R8 R2                  ; R8 = bitmask of tasks to wake
0x00010F04       LI R2 0                    ; task index

wq_wake_b_loop:
0x00010F0C       CMP R2 MAX_TASKS           ; check if we processed all tasks in bitmask
0x00010F10       BGE wq_wake_b_done

0x00010F18       LI R3 1
0x00010F20       SHL R3 R3 R2               ; R3 = bit for task R2
0x00010F24       AND R4 R8 R3               ; check if this task is in the wake bitmask
0x00010F28       CMP R4 0
0x00010F2C       BEQ wq_wake_b_next

; macro: GET_TASK_PTR R5, R2        ; wake task R2 if its in the bitmask
0x00010F34   LI R1 TASK_SIZE
0x00010F3C   MUL R3 R2 R1
0x00010F40   LI R5 tasks
0x00010F48   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00010F4C   LI R1 TASK_READY
0x00010F54   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00010F58   LI R1 WAIT_NONE
0x00010F60   STW R1 [R5 + TASK_WAIT]

wq_wake_b_next:
0x00010F64       ADD R2 R2 1
0x00010F68       B wq_wake_b_loop

wq_wake_b_done:
0x00010F70       POP LR
0x00010F74       RET

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
0x00011578       LI R2 0                      ; index

ia_loop:
0x00011580       CMP R2 MAX_INODES
0x00011584       BGE ia_fail

0x0001158C       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x00011590       LI R4 inode_used
0x00011598       ADD R4 R4 R3                  ; &inode_used[index]

0x0001159C       LDW R5 [R4]                   ; load used marker
0x000115A0       CMP R5 0
0x000115A4       BEQ ia_found

0x000115AC       ADD R2 R2 1
0x000115B0       B ia_loop

ia_found:
0x000115B8       LI R5 1
0x000115C0       STW R5 [R4]                  ; mark used

0x000115C4       LI R3 INODE_SIZEOF
0x000115CC       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x000115D0       LI R1 inode_pool
0x000115D8       ADD R1 R1 R6                 ; return inode ptr
0x000115DC       RET

ia_fail:
0x000115E0       LI R1 0
0x000115E8       RET

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

0x000115EC       LI R2 inode_pool
0x000115F4       SUB R3 R1 R2                  ; offset from pool base

0x000115F8       LI R4 INODE_SIZEOF
0x00011600       DIV R5 R3 R4                 ; index

0x00011604       SHL R5 R5 2                  ; index * 4 (u32 array)
0x00011608       LI R6 inode_used
0x00011610       ADD R6 R6 R5                 ; &inode_used[index]

0x00011614       LI R7 0
0x0001161C       STW R7 [R6]                  ; mark free

0x00011620       RET

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

0x00011624       STW R2 [R1 + INODE_OPS]
0x00011628       STW R3 [R1 + INODE_PRIVATE]
0x0001162C       STW R4 [R1 + INODE_TYPE]
0x00011630       STW R5 [R1 + INODE_SIZE]
0x00011634       LI R2 1
0x0001163C       STW R2 [R1 + INODE_REFCNT]
0x00011640       RET

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
0x00011644       LDW R2 [R1 + INODE_REFCNT]
0x00011648       ADD R2 R2 1
0x0001164C       STW R2 [R1 + INODE_REFCNT]
0x00011650       RET

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
0x00011654       PUSH LR
0x00011658       LDW R2 [R1 + INODE_REFCNT]
0x0001165C       SUB R2 R2 1
0x00011660       STW R2 [R1 + INODE_REFCNT]
0x00011664       CMP R2 0
0x00011668       BNE inode_put_done
    ; destroy inode
0x00011670       BL inode_free

inode_put_done:
0x00011678       POP LR
0x0001167C       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x00011680       LDW R2 [R1 + FILE_REFCNT]
0x00011684       ADD R2 R2 1
0x00011688       STW R2 [R1 + FILE_REFCNT]
0x0001168C       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x00011690       PUSH LR
0x00011694       LDW R2 [R1 + FILE_REFCNT]
0x00011698       SUB R2 R2 1
0x0001169C       STW R2 [R1 + FILE_REFCNT]
0x000116A0       CMP R2 0
0x000116A4       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x000116AC       BL file_free

file_put_done:
0x000116B4       POP LR
0x000116B8       RET


; ----------------------------------
; vfs_lookup  - "wrapper fs selector"
;
; R1 = pathname
; R2 = flags O_CREATE | O_EXCL | O_TRUNC | O_APPEND
;
; returns:
;   R1 = inode
;   R1 = 0 not found
; ----------------------------------

vfs_lookup:
0x000116BC       PUSH LR
0x000116C0       PUSH R8
0x000116C4       PUSH R9

0x000116C8       MOV R8 R1          ; pathname
0x000116CC       MOV R9 R2          ; flags

0x000116D0       MOV R3 R2         ; get flags copy

    ;-------------------------------------------------------------
    ; Validate access mode
    ;-------------------------------------------------------------
0x000116D4       AND R3 R3 O_ACCMODE

0x000116D8       CMP R3 O_RDONLY
0x000116DC       BEQ vfs_access_ok

0x000116E4       CMP R3 O_WRONLY
0x000116E8       BEQ vfs_access_ok

0x000116F0       CMP R3 O_RDWR
0x000116F4       BEQ vfs_access_ok
0x000116FC       B vfs_fail_access

vfs_access_ok:

0x00011704       MOV R1 R8           ;check pathname is ok /path/name
0x00011708       BL validate_pathname
0x00011710       CMP R1 0
0x00011714       BNE vfs_bad_pathname

0x0001171C       MOV R1 R8
0x00011720       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x00011728       CMP R1 0
0x0001172C       BNE vfs_done       ;if exists  dev inode ok
    ; check nsfs
0x00011734       MOV R1 R8
0x00011738       MOV R2 R9
0x0001173C       BL nsfs_lookup     ; 2 writable overlay above tarfs
0x00011744       CMP R1 0
0x00011748       BNE vfs_done       ; if exists nsfs inode done
    ; check flags bf tarfs
    ; needs dbl check for rdonly mode here (to do)
0x00011750       MOV R1 R8
0x00011754       MOV R2 R9
0x00011758       AND R3 R2 O_ACCMODE
0x0001175C       cmp R3 O_RDONLY
0x00011760       BNE vfs_nsfs_create_file
0x00011768       BL tarfs_lookup     ; 3 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x00011770       CMP R1 0
0x00011774       BNE vfs_done       ; if exists tarfs inode done
vfs_nsfs_create_file:
    ; so path name valid, and not found in dev nsfs tarfs
    ; so its brand new
    ; try to create file in nsfs
0x0001177C       MOV R1 R8
0x00011780       MOV R2 R9
    ; this is a valid pathname, check flags if need to create file or not
    ;check if no RO mode is set
0x00011784       AND R3 R2 1         ;check CREATE BIT 1
0x00011788       cmp R3 O_CREATE
0x0001178C       BNE vfs_fail_access
    ; create file  if flag is set
0x00011794       BL nsfs_create     ; 2 writable overlay above tarfs it should create inode for the file and return result in R1
0x0001179C       CMP R1 0
0x000117A0       BNE vfs_done     ; if file created inode created - ok
    ;error creating file, return 0
0x000117A8       B vfs_err_create

vfs_done:
0x000117B0       POP R8
0x000117B4       POP R9
0x000117B8       POP LR          ;3 R1 - return inode
0x000117BC       RET

; probably need specify reason not just R1=0 (to do)
vfs_err_create:
vfs_bad_pathname:
   ; MOV R2 R1        ;err code in R2
vfs_fail_access:
vfs_not_found:
0x000117C0       POP R8
0x000117C4       POP R9
0x000117C8       LI R1 0         ;it can be just ret but i added it for result clarity
0x000117D0       POP LR          ;or R1 - Nul
0x000117D4       RET

;=================================================================
; validate_pathname
;
; Validate an absolute KR32 pathname.
;
; IN:
;   R1 = pathname pointer
;
; OUT:
;   R1 = 0            valid
;   R1 = ERR_INVAL    invalid pathname
;   R1 = ERR_NAMETOOLONG
;
; Rules:
;   - must not be empty
;   - must start with '/'
;   - no '//'
;   - no '/./'
;   - no '/../'
;   - no trailing '/.' or '/..'
;   - no control characters
;   - maximum length EXEC_MAX_PATH-1
;
;=================================================================

validate_pathname:
0x000117D8       PUSH LR
0x000117DC       PUSH R8
0x000117E0       PUSH R9
0x000117E4       PUSH R10
0x000117E8       PUSH R11

0x000117EC       MOV R8 R1              ; R8 = pathname
0x000117F0       LI  R9 0               ; R9 = index
0x000117F8       LI  R10 EXEC_MAX_PATH  ; maximum including NUL

    ;-------------------------------------------------------------
    ; pathname[0] must exist
    ;-------------------------------------------------------------

0x00011800       LDB R11 [R8]
0x00011804       CMP R11 0
0x00011808       BEQ validate_invalid

    ;-------------------------------------------------------------
    ; pathname must start with '/'
    ;-------------------------------------------------------------

0x00011810       LI R11 47              ; '/'
0x00011818       LDB R1 [R8]
0x0001181C       CMP R1 R11
0x00011820       BNE validate_invalid

0x00011828       ADD R9 R9 1

validate_loop:

    ;-------------------------------------------------------------
    ; length check
    ;-------------------------------------------------------------

0x0001182C       CMP R9 R10
0x00011830       BGE validate_toolong

0x00011838       LDB R11 [R8 + R9]

    ; end of string
0x0001183C       CMP R11 0
0x00011840       BEQ validate_success
    ;-------------------------------------------------------------
    ; reject control characters
    ;
    ; ASCII < 0x20
    ;-------------------------------------------------------------
0x00011848       LI R1 0x20
0x00011850       CMP R11 R1
0x00011854       BLT validate_invalid
    ;-------------------------------------------------------------
    ; reject "//"
    ;-------------------------------------------------------------
0x0001185C       LI R1 47
0x00011864       CMP R11 R1
0x00011868       BNE validate_next

    ; current char is '/'
    ; check previous char

0x00011870       LI R1 1
0x00011878       CMP R9 R1
0x0001187C       BEQ validate_next       ; first '/' is allowed

0x00011884       SUB R1 R9 1
0x00011888       LDB R1 [R8 + R1]

0x0001188C       LI R2 47
0x00011894       CMP R1 R2
0x00011898       BEQ validate_invalid
validate_next:
0x000118A0       ADD R9 R9 1
0x000118A4       B validate_loop

validate_success:
0x000118AC       LI R1 0
0x000118B4       B validate_done
validate_invalid:
0x000118BC       LI R1 ERR_INVAL
0x000118C4       B validate_done
validate_toolong:
0x000118CC       LI R1 ERR_NAMETOOLONG
validate_done:
0x000118D4       POP R11
0x000118D8       POP R10
0x000118DC       POP R9
0x000118E0       POP R8
0x000118E4       POP LR
0x000118E8       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x000118EC       PUSH LR
0x000118F0       PUSH R8
0x000118F4       PUSH R9
0x000118F8       PUSH R10
0x000118FC       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x00011900       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x00011908       CMP R1 0
0x0001190C       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x00011914       MOV R8 R1            ; save inode ptr

0x00011918       LDW R2 [R8 + INODE_TYPE]
0x0001191C       LI R3 INODE_DIR
0x00011924       CMP R2 R3

    ;BEQ fail_isdir            ; if pathname is a dir -implemented readdir

0x00011928       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x00011930       CMP R1 0
0x00011934       BEQ fail_nfile

0x0001193C       MOV R9 R1                ; save file*

    ; initialize file object ;
0x00011940       MOV R1 R9                ; R1 file*
0x00011944       MOV R2 R8                ; inode*
0x00011948       MOV R3 R10               ; flags
0x0001194C       BL file_init

0x00011954       MOV R1 R9
0x00011958       BL fd_alloc             ; R1 inited file ptr
0x00011960       LI R2 ERR_MFILE
0x00011968       CMP R1 R2
0x0001196C       BEQ fail_fd
                            ; R1 - holds fd
0x00011974       POP R10
0x00011978       POP R9
0x0001197C       POP R8
0x00011980       POP LR
0x00011984       RET

fail_fd:
0x00011988       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x0001198C       LDW R2 [R1 + FILE_INODE]

0x00011990       MOV R1 R2
0x00011994       BL inode_put             ; close inode refcnt--

0x0001199C       MOV R1 R9
0x000119A0       BL file_free
0x000119A8       LI R1 ERR_MFILE
0x000119B0       B  vfs_exit

fail_noent:
0x000119B8       LI R1 ERR_NOENT
0x000119C0       B  vfs_exit
fail_nfile:
0x000119C8       LI R1 ERR_NFILE
0x000119D0       B  vfs_exit
fail_isdir:
0x000119D8       LI R1 ERR_ISDIR
0x000119E0       B  vfs_exit
fail_acces:
0x000119E8       LI R1 ERR_ACCES
vfs_exit:
0x000119F0       POP R10
0x000119F4       POP R9
0x000119F8       POP R8
0x000119FC       POP LR
0x00011A00       RET

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
0x00011A04       PUSH LR
0x00011A08       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x00011A10       CMP R1 0
0x00011A14       BEQ badf_fail

0x00011A1C       MOV R8 R1          ; save file*

0x00011A20       MOV R1 R8
0x00011A24       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x00011A2C       LI  R1 0        ; success
0x00011A34       POP LR
0x00011A38       RET

badf_fail:
0x00011A3C       LI R1 ERR_BADF
0x00011A44       POP LR
0x00011A48       RET


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

0x00011A4C       LI R2 0                      ; index

fa_loop:
0x00011A54       CMP R2 MAX_FILES
0x00011A58       BGE fa_fail

0x00011A60       SHL R3 R2 2                  ; index * 4
0x00011A64       LI R4 file_used              ; look in file_used list 0 free 1 used
0x00011A6C       ADD R4 R4 R3

0x00011A70       LDW R5 [R4]
0x00011A74       CMP R5 0
0x00011A78       BEQ fa_found

0x00011A80       ADD R2 R2 1
0x00011A84       B fa_loop

fa_found:
0x00011A8C       LI R5 1
0x00011A94       STW R5 [R4]                  ; mark slot used

0x00011A98       LI R4 FILE_SIZE
0x00011AA0       MUL R6 R2 R4

0x00011AA4       LI R1 file_pool
0x00011AAC       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x00011AB0       LI R7 0

0x00011AB8       STW R7 [R1 + FILE_INODE]
0x00011ABC       STW R7 [R1 + FILE_OFFSET]
0x00011AC0       STW R7 [R1 + FILE_FLAGS]

0x00011AC4       RET

fa_fail:
0x00011AC8       LI R1 0
0x00011AD0       RET

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
0x00011AD4       PUSH LR
0x00011AD8       PUSH R10
0x00011ADC       MOV  R10 R1
0x00011AE0       LDW  R2 [R1 + FILE_INODE]

0x00011AE4       CMP R2 0
0x00011AE8       BEQ no_inode

0x00011AF0       MOV R1 R2
0x00011AF4       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x00011AFC       MOV R1 R10
0x00011B00       LI  R2 file_pool
0x00011B08       SUB R3 R1 R2                 ; offset from pool base

0x00011B0C       LI  R4 FILE_SIZE
0x00011B14       DIV R5 R3 R4                 ; slot number

0x00011B18       SHL R5 R5 2                  ; slot * 4

0x00011B1C       LI  R6 file_used
0x00011B24       ADD R6 R6 R5                 ; address of slot in file_used

0x00011B28       LI R7 0
0x00011B30       STW R7 [R6]                  ; mark free
0x00011B34       POP R10
0x00011B38       POP LR
0x00011B3C       RET


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

0x00011B40       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x00011B44       LI  R1 tasks
0x00011B4C       LI  R2 TASK_SIZE
0x00011B54       LI  R3 MAX_TASKS
0x00011B5C       MUL R3 R2 R3
0x00011B60       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x00011B68       LI R1 idle_task
0x00011B70       LI R2 0
0x00011B78       LI R3 0
0x00011B80       BL task_create

0x00011B88       CMP R1 0
0x00011B8C       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task_init
    ; ----------------------------------

0x00011B94       LI R1 TASK_INIT_START
0x00011B9C       LI R2 1
0x00011BA4       LI R3 0
0x00011BAC       BL task_create

0x00011BB4       CMP R1 0
0x00011BB8       BEQ init_scheduler_fail

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
0x00011BC0       LI R1 task_count
0x00011BC8       LI R2 2                     ; last task_pid+1 for now (task 0 and task 1) next id is 2
0x00011BD0       STW R2 [R1]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x00011BD4       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x00011BDC   LI R1 CURRENT_TASK
0x00011BE4   STW R2 [R1]

0x00011BE8       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00011BEC       RET


init_scheduler_fail:
0x00011BF0       DEBUG 99
halt:
0x00011BF4       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00011BFC   LI R1 CURRENT_TASK
0x00011C04   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x00011C08       ADD R3 R2 1

wrap_check:

0x00011C0C       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x00011C10       BLT check_task
0x00011C18       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x00011C20       LI R4 TASK_SIZE
0x00011C28       MUL R5 R3 R4
0x00011C2C       LI R6 tasks
0x00011C34       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x00011C38       LDW R7 [R5 + TASK_STATE]

0x00011C3C       CMP R7 1
0x00011C40       BEQ do_switch
    ; if not ready go to next task in list
0x00011C48       ADD R3 R3 1
0x00011C4C       B wrap_check

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
0x00011C54   LI R1 CURRENT_TASK
0x00011C5C   STW R3 [R1]
0x00011C60       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x00011C64   LI R1 TASK_SIZE
0x00011C6C   MUL R3 R2 R1
0x00011C70   LI R5 tasks
0x00011C78   ADD R5 R5 R3
0x00011C7C       MOV R3 R8
0x00011C80       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x00011C84       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x00011C88   STW R7 [R5 + TASK_USP]

0x00011C8C       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x00011C90   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x00011C94   LI R1 RESUME_TRAP
0x00011C9C   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x00011CA0   LI R1 TASK_SIZE
0x00011CA8   MUL R3 R8 R1
0x00011CAC   LI R5 tasks
0x00011CB4   ADD R5 R5 R3
0x00011CB8       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x00011CBC   LDW R7 [R5 + TASK_PTBR]
0x00011CC0       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x00011CC4   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x00011CC8   LDW R7 [R9 + TASK_STATE]
0x00011CCC       CMP R7 TASK_ZOMBIE
0x00011CD0       BNE switch_old_reaped
0x00011CD8       PUSH R5
0x00011CDC       MOV R1 R9
0x00011CE0       BL task_destroy
0x00011CE8       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x00011CEC   LDW R7 [R5 + TASK_RESUME]
0x00011CF0       CMP R7 RESUME_KERNEL
0x00011CF4       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x00011CFC       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x00011D04       PUSH R1
0x00011D08       PUSH R2
0x00011D0C       PUSH R3
0x00011D10       PUSH R4
0x00011D14       PUSH R5
0x00011D18       PUSH R6
0x00011D1C       PUSH R7
0x00011D20       PUSH R8
0x00011D24       PUSH R9
0x00011D28       PUSH R10
0x00011D2C       PUSH R11
0x00011D30       PUSH R12
0x00011D34       PUSH R14
0x00011D38       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x00011D3C   LI R1 CURRENT_TASK
0x00011D44   LDW R2 [R1]

0x00011D48       ADD R3 R2 1

schedule_call_wrap_check:
0x00011D4C       CMP R3 MAX_TASKS
0x00011D50       BLT schedule_call_check_task
0x00011D58       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x00011D60       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x00011D64   LI R1 TASK_SIZE
0x00011D6C   MUL R3 R8 R1
0x00011D70   LI R5 tasks
0x00011D78   ADD R5 R5 R3
0x00011D7C       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x00011D80   LDW R7 [R5 + TASK_STATE]
0x00011D84       CMP R7 TASK_READY               ; check it can be run
0x00011D88       BEQ schedule_call_do_switch

0x00011D90       ADD R3 R3 1
0x00011D94       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x00011D9C   LI R1 CURRENT_TASK
0x00011DA4   STW R3 [R1]
0x00011DA8       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x00011DAC   LI R1 TASK_SIZE
0x00011DB4   MUL R3 R2 R1
0x00011DB8   LI R5 tasks
0x00011DC0   ADD R5 R5 R3
0x00011DC4       MOV R3 R8

0x00011DC8       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x00011DCC   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x00011DD0   LI R1 RESUME_KERNEL
0x00011DD8   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x00011DDC   LI R1 TASK_SIZE
0x00011DE4   MUL R3 R8 R1
0x00011DE8   LI R5 tasks
0x00011DF0   ADD R5 R5 R3
0x00011DF4       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x00011DF8   LDW R7 [R5 + TASK_PTBR]
0x00011DFC       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x00011E00   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x00011E04   LDW R7 [R5 + TASK_RESUME]
0x00011E08       CMP R7 RESUME_KERNEL
0x00011E0C       BEQ restore_kernel_context

0x00011E14       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x00011E1C       DISABLEINT                  ; RET does jump by LR(R15)
0x00011E20       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x00011E24       POP R14                     ; (in kernel)
0x00011E28       POP R12                     ; DI - to avoid int nesting
0x00011E2C       POP R11
0x00011E30       POP R10
0x00011E34       POP R9
0x00011E38       POP R8
0x00011E3C       POP R7
0x00011E40       POP R6
0x00011E44       POP R5
0x00011E48       POP R4
0x00011E4C       POP R3
0x00011E50       POP R2
0x00011E54       POP R1
0x00011E58       RET
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
0x00011EEC       PUSH  R5
0x00011EF0       PUSH  R6
0x00011EF4       PUSH  R7
0x00011EF8       PUSH  R8
0x00011EFC       PUSH  R9

0x00011F00       LI R2 0                  ; page index

pa_loop:
0x00011F08       LI R1 MAX_PHYS_PAGES

0x00011F10       CMP R2 R1
0x00011F14       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x00011F1C       MOV R3 R2
0x00011F20       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x00011F24       MOV R4 R2
0x00011F28       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x00011F2C       LI R5 page_bitmap
0x00011F34       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x00011F38       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x00011F3C       LI R7 1
0x00011F44       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x00011F48       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x00011F4C       CMP R8 0
0x00011F50       BEQ pa_found                ; if bit is 0, page is free

0x00011F58       ADD R2 R2 1                 ; increment page index and check next page
0x00011F5C       B pa_loop

pa_found:

    ; mark page allocated

0x00011F64       OR  R6 R6 R7
0x00011F68       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x00011F6C       LI  R9 PAGE_ALLOC_BASE

0x00011F74       MOV R1 R2
0x00011F78       SHL R1 R1 12          ; page_index * 4096

0x00011F7C       ADD R1 R1 R9

0x00011F80       POP R9
0x00011F84       POP R8
0x00011F88       POP R7
0x00011F8C       POP R6
0x00011F90       POP R5

0x00011F94       RET

pa_fail:

0x00011F98       LI R1 0                     ; no free pages

0x00011FA0       POP R9
0x00011FA4       POP R8
0x00011FA8       POP R7
0x00011FAC       POP R6
0x00011FB0       POP R5
0x00011FB4       RET


;new page allocation routine with refcounts and bitmap for 128 pages of 4KB each (512KB total)

page_alloc:
0x00011FB8       PUSH R6
0x00011FBC       PUSH R7
0x00011FC0       PUSH R8
0x00011FC4       PUSH R9

0x00011FC8       LI R2 0                     ; page index

pa1_loop:
0x00011FD0       LI R1 MAX_PHYS_PAGES
0x00011FD8       CMP R2 R1
0x00011FDC       BGE pa1_fail

0x00011FE4       LI R1 page_refcounts
    ;ADD R5 R1 R2               ; address of refcount for this page
0x00011FEC       LDB R6 [R1 + R2]           ; load refcount
0x00011FF0       CMP R6 0
0x00011FF4       BEQ pa1_found

0x00011FFC       ADD R2 R2 1
0x00012000       B pa1_loop

pa1_found:
0x00012008       LI R6 1
0x00012010       STB R6 [R1 + R2]          ; set refcount = 1

0x00012014       LI R9 PAGE_ALLOC_BASE
0x0001201C       MOV R1 R2
0x00012020       SHL R1 R1 12                ; index * PAGE_SIZE (4kB)
0x00012024       ADD R1 R1 R9                ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x00012028       POP R9
0x0001202C       POP R8
0x00012030       POP R7
0x00012034       POP R6                     ; R1 = physical address of allocated page
0x00012038       RET

pa1_fail:
0x0001203C       LI R1 0                     ; no free pages
0x00012044       POP R9
0x00012048       POP R8
0x0001204C       POP R7
0x00012050       POP R6
0x00012054       RET

;=================================================================
; page_get - increment refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_get:
    ; R1 = physical address
    ; Returns nothing; ignores invalid addresses
0x00012058       CMP R1 0
0x0001205C       BEQ page_get_done

    ; Check lower bound
0x00012064       LI R2 PAGE_ALLOC_BASE
0x0001206C       CMP R1 R2
0x00012070       BLT page_get_done

    ; Check upper bound (exclusive)
0x00012078       LI R2 PAGE_ALLOC_END
0x00012080       CMP R1 R2
0x00012084       BGE page_get_done

    ; Calculate index
0x0001208C       LI R2 PAGE_ALLOC_BASE
0x00012094       SUB R2 R1 R2       ; R1 pa
0x00012098       SHR R2 R2 12       ; R2 = page index in refcounts array
0x0001209C       LI R3 page_refcounts
0x000120A4       ADD R3 R3 R2
0x000120A8       LDB R4 [R3]
0x000120AC       ADD R4 R4 1                 ; increment refcount
0x000120B0       STB R4 [R3]
page_get_done:
0x000120B4       RET

;=================================================================
; page_put - decrement refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_put:
    ; R1 = physical address
0x000120B8       CMP R1 0                        ;if address is 0 - ignore
0x000120BC       BEQ page_put_done

0x000120C4       LI R2 PAGE_ALLOC_BASE           ;check R1 is valid
0x000120CC       CMP R1 R2
0x000120D0       BLT page_put_done

0x000120D8       LI R2 PAGE_ALLOC_END
0x000120E0       CMP R1 R2
0x000120E4       BGE page_put_done

0x000120EC       LI R2 PAGE_ALLOC_BASE
0x000120F4       SUB R2 R1 R2
0x000120F8       SHR R2 R2 12        ; R2 = page index in refcounts array
0x000120FC       LI R3 page_refcounts
0x00012104       ADD R3 R3 R2
0x00012108       LDB R4 [R3]
0x0001210C       CMP R4 0
0x00012110       BEQ page_put_done               ;if refcount already 0 - ignore it was freed already
0x00012118       SUB R4 R4 1                     ;decrement refcount
0x0001211C       STB R4 [R3]
    ; If refcount becomes 0, the page is now free (no further action needed)
page_put_done:
0x00012120       RET

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
0x00012124       PUSH LR
0x00012128       PUSH R8
0x0001212C       PUSH R9
0x00012130       PUSH R10
0x00012134       PUSH R11
0x00012138       PUSH R12

0x0001213C       MOV R8 R1                 ; file size
0x00012140       LI  R2 PAGE_SIZE
    ; compute num_pages = ceil(size / PAGE_SIZE)
0x00012148       ADD R1 R8 R2
0x0001214C       SUB R1 R1 1               ; (fsz + 4095) / 4096
0x00012150       DIV R1 R1 R2              ; R1 = count
0x00012154       MOV R9 R1                 ; save count

    ; ---- allocate table page ----
0x00012158       BL page_alloc
0x00012160       CMP R1 0
0x00012164       BEQ table_alloc_fail
0x0001216C       MOV R10 R1                ; table PA
0x00012170       LI R3 PAGE_SIZE
0x00012178       BL mem_zero               ; zero table
0x00012180       STW R9 [R10]              ; store count

    ; ---- allocate code pages and fill table ----
0x00012184       LI R11 0                  ; index
0x0001218C       LI R12 0                  ; error flag
alloc_table_loop:
0x00012194       CMP R11 R9
0x00012198       BGE alloc_table_done
0x000121A0       BL page_alloc             ;get new page
0x000121A8       CMP R1 0
0x000121AC       BEQ alloc_table_fail
0x000121B4       SHL R3 R11 2
0x000121B8       ADD R4 R10 R3
0x000121BC       ADD R4 R4 4
0x000121C0       STW R1 [R4]               ; store R1 - new PA at table[4 + i*4]
0x000121C4       ADD R11 R11 1
0x000121C8       B alloc_table_loop
alloc_table_done:
    ; success
0x000121D0       MOV R1 R10                ; table PA
0x000121D4       MOV R2 R9                 ; count
0x000121D8       LI R3 0                   ; success
0x000121E0       POP R12
0x000121E4       POP R11
0x000121E8       POP R10
0x000121EC       POP R9
0x000121F0       POP R8
0x000121F4       POP LR
0x000121F8       RET

alloc_table_fail:
    ; free all already allocated code pages and the table
0x000121FC       MOV R12 R11               ; number allocated so far
0x00012200       LI R11 0
rollback_loop:
0x00012208       CMP R11 R12
0x0001220C       BGE rollback_done
0x00012214       SHL R3 R11 2
0x00012218       ADD R4 R10 R3
0x0001221C       ADD R4 R4 4
0x00012220       LDW R1 [R4]
0x00012224       CMP R1 0
0x00012228       BEQ rollback_next
0x00012230       BL page_put
rollback_next:
0x00012238       ADD R11 R11 1
0x0001223C       B rollback_loop
rollback_done:
0x00012244       MOV R1 R10
0x00012248       BL page_put               ; free table
0x00012250       LI R1 0
0x00012258       LI R2 0
0x00012260       LI R3 ERR_NOMEM
0x00012268       POP R12
0x0001226C       POP R11
0x00012270       POP R10
0x00012274       POP R9
0x00012278       POP R8
0x0001227C       POP LR
0x00012280       RET

table_alloc_fail:
0x00012284       LI R1 0
0x0001228C       LI R2 0
0x00012294       LI R3 ERR_NOMEM
0x0001229C       POP R12
0x000122A0       POP R11
0x000122A4       POP R10
0x000122A8       POP R9
0x000122AC       POP R8
0x000122B0       POP LR
0x000122B4       RET

;------------------------------------------------------------------------------
; pages_free_table - Free a table and all its code pages.
;
; IN:   R1 = physical address of the table page
; OUT:  none
;------------------------------------------------------------------------------
pages_free_table:
0x000122B8       PUSH LR
0x000122BC       PUSH R8
0x000122C0       PUSH R9
0x000122C4       PUSH R10

0x000122C8       CMP R1 0
0x000122CC       BEQ free_table_done
0x000122D4       MOV R8 R1                 ; table PA
0x000122D8       LDW R9 [R8]               ; count
0x000122DC       LI R10 0
free_table_loop:
0x000122E4       CMP R10 R9
0x000122E8       BGE free_table_done_pages
0x000122F0       SHL R3 R10 2
0x000122F4       ADD R4 R8 R3
0x000122F8       ADD R4 R4 4
0x000122FC       LDW R1 [R4]
0x00012300       CMP R1 0
0x00012304       BEQ free_table_next
0x0001230C       BL page_put
free_table_next:
0x00012314       ADD R10 R10 1
0x00012318       B free_table_loop
free_table_done_pages:
0x00012320       MOV R1 R8
0x00012324       BL page_put               ; free the table page itself
free_table_done:
0x0001232C       POP R10
0x00012330       POP R9
0x00012334       POP R8
0x00012338       POP LR
0x0001233C       RET

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
0x00012340       PUSH LR
0x00012344       PUSH R5
0x00012348       PUSH R6
0x0001234C       PUSH R7
0x00012350       PUSH R8
0x00012354       PUSH R9
0x00012358       PUSH R10
0x0001235C       PUSH R11

0x00012360       MOV R8 R1                 ; table PA
0x00012364       MOV R9 R2                 ; PTBR
0x00012368       MOV R10 R3                ; VA start
0x0001236C       MOV R11 R4                ; flags
0x00012370       LDW R6 [R8]               ; count
0x00012374       LI R7 0
map_table_loop:
0x0001237C       CMP R7 R6
0x00012380       BGE map_table_done
0x00012388       SHL R3 R7 2
0x0001238C       ADD R4 R8 R3
0x00012390       ADD R4 R4 4
0x00012394       LDW R5 [R4]            ; physical address
0x00012398       MOV R1 R9                 ; PTBR
0x0001239C       LI  R3 PAGE_SIZE
0x000123A4       MUL R3 R7 R3              ; offset = index * PAGE_SIZE
0x000123A8       MOV R2 R10
0x000123AC       ADD R2 R2 R3              ; VA for this page
0x000123B0       MOV R3 R5                 ; restore physical page after calculating VA offset
0x000123B4       MOV R4 R11
0x000123B8       BL map_page_rt
0x000123C0       ADD R7 R7 1
0x000123C4       B map_table_loop
map_table_done:
0x000123CC       POP R11
0x000123D0       POP R10
0x000123D4       POP R9
0x000123D8       POP R8
0x000123DC       POP R7
0x000123E0       POP R6
0x000123E4       POP R5
0x000123E8       POP LR
0x000123EC       RET


;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free0:
0x000123F0       PUSH  R5
0x000123F4       PUSH  R6
0x000123F8       PUSH  R7
0x000123FC       PUSH  R8
0x00012400       PUSH  R9


0x00012404       LI R2 PAGE_ALLOC_BASE
0x0001240C       SUB R3 R1 R2         ; calculate offset from base

0x00012410       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x00012414       MOV R4 R3
0x00012418       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x0001241C       MOV R5 R3
0x00012420       AND R5 R5 7          ; bit index in byte = page index % 8

0x00012424       LI R6 page_bitmap
0x0001242C       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x00012430       LDB R7 [R6]

0x00012434       LI R8 1
0x0001243C       SHL R8 R8 R5         ; mask for this page's bit

0x00012440       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x00012444       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x00012448       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0001244C       POP R9
0x00012450       POP R8
0x00012454       POP R7
0x00012458       POP R6
0x0001245C       POP R5
0x00012460       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:
0x00012464       LI R2 0
pz_loop:
0x0001246C       CMP R3 0
0x00012470       BEQ pz_done
0x00012478       STB R2 [R1]
0x0001247C       ADD R1 R1 1
0x00012480       SUB R3 R3 1
0x00012484       B pz_loop
pz_done:
0x0001248C       RET

;=================================================================
; memory copy at the given address (R1)<(R2) R3 = amount
;=================================================================

memcpy:

cpy_loop:
0x00012490       CMP R3 0
0x00012494       BEQ cpy_done
0x0001249C       LDB R4 [R2]
0x000124A0       STB R4 [R1]
0x000124A4       ADD R1 R1 1
0x000124A8       ADD R2 R2 1
0x000124AC       SUB R3 R3 1
0x000124B0       B cpy_loop
cpy_done:
0x000124B8       RET

; ================================================================
; Copy a memory page (or other multiple of 4 bytes) by physical address.
; R1 = source physical address (should be aligned!)
; R2 = destination physical address (aligned!)
; R3 = size in bytes (must be multiple of 4)
; each time it copyes 4 bytes (1 word)
; ================================================================
page_copy:

page_copy_loop:
0x000124BC       CMP R3 0
0x000124C0       BEQ page_copy_done
0x000124C8       LDW R4 [R1]
0x000124CC       STW R4 [R2]
0x000124D0       ADD R1 R1 4
0x000124D4       ADD R2 R2 4
0x000124D8       SUB R3 R3 4
0x000124DC       B page_copy_loop

page_copy_done:
0x000124E4       RET

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

0x000129EC       PUSH LR

0x000129F0       MOV R8 R1          ; entry
0x000129F4       MOV R9 R2          ; pid
0x000129F8       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x00012A00       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x00012A08       CMP R1 0
0x00012A0C       BEQ task_create_fail

0x00012A14       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x00012A18       MOV R1 R10
0x00012A1C       LI R3 TASK_SIZE
0x00012A24       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x00012A2C   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x00012A30   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x00012A34       BL page_alloc
0x00012A3C       CMP R1 0
0x00012A40       BEQ task_create_fail

0x00012A48       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x00012A4C   STW R1 [R10 + TASK_PTBR]

0x00012A50       MOV R1 R12
0x00012A54       LI  R3 PAGE_SIZE
0x00012A5C       BL  mem_zero                   ; zero out the sensitive new page table

0x00012A64       MOV R1 R12
0x00012A68       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x00012A70   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00012A74   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x00012A78   LDW R1 [R10 + TASK_PTBR]
0x00012A7C       MOV R2 R8
0x00012A80       LI R3 0xFFFFF000
0x00012A88       AND R2 R2 R3
0x00012A8C       MOV R3 R2
0x00012A90       CMP R9 0
0x00012A94       BEQ task_create_map_kernel_entry
0x00012A9C       LI R4 USER_RX
0x00012AA4       B task_create_map_entry
task_create_map_kernel_entry:
0x00012AAC       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x00012AB4       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x00012ABC       BL page_alloc
0x00012AC4       CMP R1 0
0x00012AC8       BEQ task_create_fail

0x00012AD0       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x00012AD4   STW R12 [R10 + TASK_USTACK_PAGE]

0x00012AD8       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x00012AE0   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x00012AE4   LDW R1 [R10 + TASK_PTBR]

0x00012AE8       LI  R2 USER_STACK_VA
0x00012AF0       MOV R3 R12
0x00012AF4       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x00012AFC       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x00012B04       BL page_alloc
0x00012B0C       CMP R1 0
0x00012B10       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x00012B18   STW R1 [R10 + TASK_KSTACK_PAGE]
0x00012B1C       LI R2 PAGE_SIZE

0x00012B24       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x00012B28       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x00012B2C   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x00012B30   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x00012B34       LI R1 0

0x00012B3C       PUSH R1            ; R1
0x00012B40       PUSH R1            ; R2
0x00012B44       PUSH R1            ; R3
0x00012B48       PUSH R1            ; R4
0x00012B4C       PUSH R1            ; R5
0x00012B50       PUSH R1            ; R6
0x00012B54       PUSH R1            ; R7
0x00012B58       PUSH R1            ; R8
0x00012B5C       PUSH R1            ; R9
0x00012B60       PUSH R1            ; R10
0x00012B64       PUSH R1            ; R11
0x00012B68       PUSH R1            ; R12
0x00012B6C       PUSH R1            ; R14 (FP)
0x00012B70       PUSH R1            ; R15 (LR)

0x00012B74       PUSH R11           ; R11 - user SP top

0x00012B78       MOV R1 R8
0x00012B7C       PUSH R1            ; sepc = entry

0x00012B80       LI R1 0
0x00012B88       PUSH R1            ; sflags

0x00012B8C       CMP R9 0
0x00012B90       BEQ task_create_kernel_status
0x00012B98       LI R1 0x20
0x00012BA0       B task_create_status_ready
task_create_kernel_status:
0x00012BA8       LI R1 0x120
task_create_status_ready:
0x00012BB0       PUSH R1            ; sstatus

0x00012BB4       LI R1 0
0x00012BBC       PUSH R1            ; scause
0x00012BC0       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x00012BC4       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x00012BC8   STW R1 [R10 + TASK_KSP]

0x00012BCC       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x00012BD0   LI R1 WAIT_NONE
0x00012BD8   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x00012BDC   LI R1 RESUME_TRAP
0x00012BE4   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x00012BE8       BL page_alloc
0x00012BF0       CMP R1 0
0x00012BF4       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x00012BFC       MOV R12 R1

0x00012C00       LI  R3 PAGE_SIZE
0x00012C08       MOV R1 R12
0x00012C0C       BL  mem_zero

    ; stdin
0x00012C14       LI  R2 file_stdin
0x00012C1C       STW R2 [R12 + 0]

    ; stdout
0x00012C20       LI  R2 file_stdout
0x00012C28       STW R2 [R12 + 4]

    ; stderr
0x00012C2C       LI  R2 file_stderr
0x00012C34       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x00012C38   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x00012C3C       BL page_alloc
0x00012C44       CMP R1 0
0x00012C48       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x00012C50   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x00012C54       BL page_alloc
0x00012C5C       CMP R1 0
0x00012C60       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x00012C68   STW R1 [R10 + TASK_KBUF_RD_PTR]

    ; ----------------------------------
    ; data page - for user buffers and heap
    ; ----------------------------------

0x00012C6C       BL page_alloc
0x00012C74       CMP R1 0
0x00012C78       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x00012C80   STW R1 [R10 + TASK_DATA_PAGE]

0x00012C84       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x00012C88   LDW R1 [R10 + TASK_PTBR]
0x00012C8C       LI  R2 USER_DATA_VA
0x00012C94       MOV R3 R12
0x00012C98       LI  R4 USER_RW
0x00012CA0       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; initialize code page pointer to zero until execve or static code assignment
    ; This means the task currently has no execve-loaded program image.
    ; When execve runs, TASK_CODE_PAGE will be updated to point to the
    ; physical page currently mapped at USER_CODE_VA.
0x00012CA8       LI R1 0
; macro: TASK_SET_CODE_PAGE R10, R1
0x00012CB0   STW R1 [R10 + TASK_CODE_PAGE]

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x00012CB4   LI R1 TASK_READY
0x00012CBC   STW R1 [R10 + TASK_STATE]

    ; Initialize program break pointer to HEAP_START in User_Data_VA
0x00012CC0       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x00012CC8   STW R1 [R10 + TASK_BREAK]

    ; Initialize parent PID to 0 by default
0x00012CCC       LI R1 0
; macro: TASK_SET_PPID R10, R1
0x00012CD4   STW R1 [R10 + TASK_PPID]

0x00012CD8       MOV R1 R10                              ; return created task pointer

0x00012CDC       POP LR
0x00012CE0       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x00012CE4       CMP R10 0
0x00012CE8       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x00012CF0   LDW R1 [R10 + TASK_PTBR]
0x00012CF4       CMP R1 0
0x00012CF8       BEQ task_create_free_ustack
0x00012D00       BL page_put

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x00012D08   LDW R1 [R10 + TASK_USTACK_PAGE]
0x00012D0C       CMP R1 0
0x00012D10       BEQ task_create_free_kstack
0x00012D18       BL page_put

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x00012D20   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x00012D24       CMP R1 0
0x00012D28       BEQ task_create_free_fd
0x00012D30       BL page_put

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x00012D38   LDW R1 [R10 + TASK_FD_TABLE]
0x00012D3C       CMP R1 0
0x00012D40       BEQ task_create_free_kwr
0x00012D48       BL page_put

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x00012D50   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x00012D54       CMP R1 0
0x00012D58       BEQ task_create_free_krd
0x00012D60       BL page_put

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x00012D68   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x00012D6C       CMP R1 0
0x00012D70       BEQ task_create_free_data
0x00012D78       BL page_put

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x00012D80   LDW R1 [R10 + TASK_DATA_PAGE]
0x00012D84       CMP R1 0
0x00012D88       BEQ task_create_clear_slot
0x00012D90       BL page_put

task_create_clear_slot:
0x00012D98       MOV R1 R10
0x00012D9C       LI R3 TASK_SIZE
0x00012DA4       BL mem_zero

task_create_fail_return:
0x00012DAC       LI R1 0

0x00012DB4       POP LR
0x00012DB8       RET

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
0x00012DBC       MOV  R8 SP ;save sp to point to task trapframe!
0x00012DC0       PUSH LR

    ; Get the current task slot and parent task pointer.
; macro: GET_CURR_TASK_IDX R6
0x00012DC4   LI R1 CURRENT_TASK
0x00012DCC   LDW R6 [R1]
; macro: GET_TASK_PTR R7, R6           ; R7 = parent task*
0x00012DD0   LI R1 TASK_SIZE
0x00012DD8   MUL R3 R6 R1
0x00012DDC   LI R7 tasks
0x00012DE4   ADD R7 R7 R3

    ; Allocate a fresh child task slot.
0x00012DE8       BL task_alloc
0x00012DF0       CMP R1 0
0x00012DF4       BEQ clone_fail
0x00012DFC       MOV R10 R1                    ; R10 = child task*

    ; Clear the new child task slot before use.
0x00012E00       MOV R1 R10
0x00012E04       LI R3 TASK_SIZE
0x00012E0C       BL mem_zero

    ; Assign a new PID from the dynamic pid counter.
0x00012E14       LI R1 task_count
0x00012E1C       LDW R2 [R1]

; macro: TASK_SET_PID R10, R2        ; set new child task Pid to child task (current task_count value)
0x00012E20   STW R2 [R10 + TASK_PID]
0x00012E24       ADD R2 R2 1
0x00012E28       STW R2 [R1]                 ; update task_count as we created a new task

    ; Set child parent PID to the current task's PID.
; macro: TASK_GET_PID R2, R7
0x00012E2C   LDW R2 [R7 + TASK_PID]
; macro: TASK_SET_PPID R10, R2       ; pid - new, ppid - parent task's pid (new task)
0x00012E30   STW R2 [R10 + TASK_PPID]

    ; Copy the current task's program break.
; macro: TASK_GET_BREAK R2, R7
0x00012E34   LDW R2 [R7 + TASK_BREAK]
; macro: TASK_SET_BREAK R10, R2
0x00012E38   STW R2 [R10 + TASK_BREAK]

    ; Copy current task PC for debugging/metadata.
; macro: TASK_GET_PC R2, R7
0x00012E3C   LDW R2 [R7 + TASK_PC]
; macro: TASK_SET_PC R10, R2
0x00012E40   STW R2 [R10 + TASK_PC]

    ; Allocate and initialize a fresh page table for the child.
0x00012E44       BL page_alloc
0x00012E4C       CMP R1 0
0x00012E50       BEQ clone_fail
0x00012E58       MOV R11 R1
; macro: TASK_SET_PTBR R10, R11
0x00012E5C   STW R11 [R10 + TASK_PTBR]

    ; Clone the parent's entire page table into the child.
; macro: TASK_GET_PTBR R1, R7
0x00012E60   LDW R1 [R7 + TASK_PTBR]
0x00012E64       MOV R2 R11
0x00012E68       LI R3 PAGE_SIZE
0x00012E70       BL page_copy

    ; child will inherit code page pa (tab+codepages) from parent
; macro: TASK_GET_CODE_PAGE R2, R7   ; R2 = parent's code page PA table
0x00012E78   LDW R2 [R7 + TASK_CODE_PAGE]
0x00012E7C       CMP R2 0
0x00012E80       BEQ skip_code_get
    ; 1) allocate new table page
0x00012E88       BL page_alloc
0x00012E90       CMP R1 0
0x00012E94       BEQ clone_fail
0x00012E9C       MOV R12 R1
    ; 2) copy the table page parnt to child (it contins count and pointers to pa pages)
0x00012EA0       MOV R1 R2
0x00012EA4       MOV R2 R12
0x00012EA8       LI R3 PAGE_SIZE
0x00012EB0       BL page_copy    ;4k

; increment refcounts for each code page
0x00012EB8       LDW R8 [R12]               ; count: +0
0x00012EBC       LI R9 0                    ; page index in tab
clone_inc_loop:
0x00012EC4       CMP R9 R8
0x00012EC8       BGE clone_inc_done
0x00012ED0       SHL R3 R9 2
0x00012ED4       ADD R4 R12 R3
0x00012ED8       ADD R4 R4 4
0x00012EDC       LDW R1 [R4]                ;pa ptr: R4=R12(=+0) + 4+idx*4
0x00012EE0       CMP R1 0
0x00012EE4       BEQ clone_inc_next
0x00012EEC       BL page_get                ; refcount+1
clone_inc_next:
0x00012EF4       ADD R9 R9 1
0x00012EF8       B clone_inc_loop
clone_inc_done:

; macro: TASK_SET_CODE_PAGE R10, R12 ;  set child's code page PA (tab+pages)
0x00012F00   STW R12 [R10 + TASK_CODE_PAGE]

   ; TASK_SET_CODE_PAGE R10, R2  ; set child's code page PA to parent's code page PA
    ; Now increment refcount for the shared code page (if code page is allocated).
    ;(it is in case when execve was called before fork or when fork-execve, then fork-execve, then fork-execve etc. - all children share the same code page)
   ; MOV R1 R2
   ; BL page_get     ;increment refcount for the shared code page (if code page is allocated)
skip_code_get:

    ; The child has inherited the parent's kernel and code mappings.
    ; We will override the user stack and data mappings below.
    ; Allocate and clone the user stack page.
0x00012F04       BL page_alloc
0x00012F0C       CMP R1 0
0x00012F10       BEQ clone_fail
0x00012F18       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12   ; set new page as child user stack page
0x00012F1C   STW R12 [R10 + TASK_USTACK_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x00012F20   LDW R1 [R10 + TASK_PTBR]
0x00012F24       LI R2 USER_STACK_VA
0x00012F2C       MOV R3 R12
0x00012F30       LI R4 USER_RW
0x00012F38       BL map_page             ; map user stack page to child ptbr

; macro: TASK_GET_USTACK_PAGE R1, R7
0x00012F40   LDW R1 [R7 + TASK_USTACK_PAGE]
0x00012F44       MOV R2 R12
0x00012F48       LI R3 PAGE_SIZE
0x00012F50       BL page_copy            ; copy parent user stack page -> child user stack page

    ; Allocate and clone the user data page.
0x00012F58       BL page_alloc
0x00012F60       CMP R1 0
0x00012F64       BEQ clone_fail
0x00012F6C       MOV R12 R1
; macro: TASK_SET_DATA_PAGE R10, R12     ; set new page as child user data page
0x00012F70   STW R12 [R10 + TASK_DATA_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x00012F74   LDW R1 [R10 + TASK_PTBR]
0x00012F78       LI R2 USER_DATA_VA
0x00012F80       MOV R3 R12
0x00012F84       LI R4 USER_RW
0x00012F8C       BL map_page                     ; map user data page to child ptbr

; macro: TASK_GET_DATA_PAGE R1, R7
0x00012F94   LDW R1 [R7 + TASK_DATA_PAGE]
0x00012F98       MOV R2 R12
0x00012F9C       LI R3 PAGE_SIZE
0x00012FA4       BL page_copy                    ; copy parent user data page -> child user data page

    ; Clone the fd table and honor open file refcounts.
0x00012FAC       BL page_alloc
0x00012FB4       CMP R1 0
0x00012FB8       BEQ clone_fail

0x00012FC0       MOV R12 R1

; macro: TASK_SET_FD_TABLE R10, R12       ; set new page as child fd table page
0x00012FC4   STW R12 [R10 + TASK_FD_TABLE]
0x00012FC8       LI R3 PAGE_SIZE
0x00012FD0       MOV R1 R12
0x00012FD4       BL mem_zero                     ; clear the child fd table page just in case

; macro: TASK_GET_FD_TABLE R1, R7         ; R1 - parent fd table page
0x00012FDC   LDW R1 [R7 + TASK_FD_TABLE]
0x00012FE0       CMP R1 0
0x00012FE4       BEQ clone_fd_done                ; if parent has no fd table, skip fd cloning

    ; parent → child copy FIRST
0x00012FEC       MOV R1 R1        ; parent fd page
0x00012FF0       MOV R2 R12       ; child fd page
0x00012FF4       LI R3 PAGE_SIZE
0x00012FFC       BL page_copy

0x00013004       LI R4 3                      ; fd index loop + 3 stdin/out/err refcount=1, so start at 3

clone_fd_loop:
0x0001300C       CMP R4 MAX_FDS
0x00013010       BGE clone_fd_done

0x00013018       SHL R5 R4 2                 ; multiply fd index by 4 to get byte offset
0x0001301C       ADD R6 R12 R5               ; R6 = &child_fd_table[i]

0x00013020       LDW R7 [R6]                 ; R7 = file* from child fd table
0x00013024       CMP R7 0
0x00013028       BEQ clone_fd_next           ; if fd slot is empty, skip to next

0x00013030       MOV R1 R7                   ; IMPORTANT: isolate argument
0x00013034       BL file_get                 ; increment refcount of the file* in child fd table

clone_fd_next:
0x0001303C       ADD R4 R4 1
0x00013040       B clone_fd_loop

clone_fd_done:
    ; Allocate fresh kernel buffers for the child.
0x00013048       BL page_alloc
0x00013050       CMP R1 0
0x00013054       BEQ clone_fail

; macro: TASK_SET_KBUF_WR R10, R1        ; set new page as child kernel write buffer
0x0001305C   STW R1 [R10 + TASK_KBUF_WR_PTR]
0x00013060       LI R3 PAGE_SIZE
0x00013068       BL mem_zero                     ; zero out the child kernel write buffer

0x00013070       BL page_alloc
0x00013078       CMP R1 0
0x0001307C       BEQ clone_fail
; macro: TASK_SET_KBUF_RD R10, R1        ; set new page as child kernel read buffer
0x00013084   STW R1 [R10 + TASK_KBUF_RD_PTR]
0x00013088       LI R3 PAGE_SIZE
0x00013090       BL mem_zero                     ; zero out the child kernel read buffer

    ; Allocate and initialize the child's kernel stack.
0x00013098       BL page_alloc
0x000130A0       CMP R1 0
0x000130A4       BEQ clone_fail
0x000130AC       MOV R12 R1
; macro: TASK_SET_KSTACK_PAGE R10, R12   ; set new page as child kernel stack page
0x000130B0   STW R12 [R10 + TASK_KSTACK_PAGE]
0x000130B4       LI R3 PAGE_SIZE
0x000130BC       ADD R12 R12 R3                  ; R12 = child kernel stack top


    ; Copy the current kernel trapframe into the child's new kernel stack.
    ; task_clone_current has one saved return address below the trapframe, so
    ; recover the trapframe from the balanced current SP instead of R8, which
    ; was reused for the code-page count above. eto pizdec nado decompose clone.
    ; issue is fixed by friend - it found SP is in balance here
    ; so SP+4 is what was in R8 here
0x000130C0       MOV R1 SP
0x000130C4       ADD R1 R1 4                   ; R1 = parent trapframe base
0x000130C8       MOV R6 R12
0x000130CC       LI R5 80                    ; trapframe size in bytes
0x000130D4       SUB R6 R6 R5               ; R6 = child trapframe base inside new kernel stack
0x000130D8       MOV R2 R6
0x000130DC       LI R3 80
0x000130E4       BL page_copy                ; so we copy 80 bytes from SP to R12-80 (child trapframe base)

    ; Return 0 in the child syscall result register.
0x000130EC       LI R4 0
0x000130F4       STW R4 [R6 + TF_R1]


    ; Preserve the user SP for later trap/schedule bookkeeping.
    ; User SP is already in the trapframe we copied
    ; But we also need to set it in the child's task struct
0x000130F8       LDW R4 [R6 + TF_USP]
; macro: TASK_SET_USP R10, R4
0x000130FC   STW R4 [R10 + TASK_USP]

    ; Save the child kernel trapframe pointer and make it runnable.
; macro: TASK_SET_KSP R10, R6                    ;R6 = child trapframe base inside new kernel stack
0x00013100   STW R6 [R10 + TASK_KSP]
; macro: TASK_SET_RESUME R10, RESUME_TRAP
0x00013104   LI R1 RESUME_TRAP
0x0001310C   STW R1 [R10 + TASK_RESUME]
; macro: TASK_SET_WAIT R10, WAIT_NONE
0x00013110   LI R1 WAIT_NONE
0x00013118   STW R1 [R10 + TASK_WAIT]
; macro: TASK_SET_STATE R10, TASK_READY
0x0001311C   LI R1 TASK_READY
0x00013124   STW R1 [R10 + TASK_STATE]

0x00013128       MOV R1 R10          ; return child task pointer

0x0001312C       POP LR
0x00013130       RET

clone_fail:
0x00013134       CMP R10 0
0x00013138       BEQ clone_fail_return
0x00013140       MOV R1 R10
0x00013144       BL task_destroy
clone_fail_return:
0x0001314C       LI R1 0
0x00013154       POP LR
0x00013158       RET

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

0x0001315C       PUSH LR
0x00013160       push R12 ; preserve R12 which we use for temporary storage in this function
0x00013164       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x00013168   LDW R2 [R1 + TASK_PTBR]
0x0001316C       CMP R2 0
0x00013170       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x00013178       MOV R1 R2
0x0001317C       BL page_put        ; put-free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x00013184   LDW R2 [R12 + TASK_USTACK_PAGE]
0x00013188       CMP R2 0
0x0001318C       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x00013194       MOV R1 R2
0x00013198       BL page_put        ; put-free user stack page

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x000131A0   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x000131A4       CMP R2 0
0x000131A8       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x000131B0       MOV R1 R2
0x000131B4       BL page_put        ; put-free kernel stack page

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x000131BC   LDW R2 [R12 + TASK_FD_TABLE]
0x000131C0       CMP R2 0
0x000131C4       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x000131CC       MOV R1 R2
0x000131D0       BL page_put        ; put-free fd table page

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x000131D8   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x000131DC       CMP R2 0
0x000131E0       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x000131E8       MOV R1 R2
0x000131EC       BL page_put       ; put free KBUF_WR Page

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x000131F4   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x000131F8       CMP R2 0
0x000131FC       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x00013204       MOV R1 R2
0x00013208       BL page_put       ; put free KBUF_RD Page

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x00013210   LDW R2 [R12 + TASK_DATA_PAGE]
0x00013214       CMP R2 0
0x00013218       BEQ td_skip_code
0x00013220       MOV R1 R2
0x00013224       BL page_put        ; put-free user data page

td_skip_code:

; macro: TASK_GET_CODE_PAGE R2, R12
0x0001322C   LDW R2 [R12 + TASK_CODE_PAGE]
0x00013230       CMP R2 0
0x00013234       BEQ td_done

0x0001323C       MOV R1 R2
0x00013240       BL pages_free_table ;codepage (tab+pages)

    ;BL page_put        ; put-free user code page

td_done:

0x00013248       MOV R1 R12
0x0001324C       LI  R3 TASK_SIZE
0x00013254       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x0001325C       POP R12         ; restore R12
0x00013260       POP LR
0x00013264       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x00013268       PUSH LR
0x0001326C       PUSH R8
0x00013270       PUSH R9
0x00013274       PUSH R10
0x00013278       PUSH R11
0x0001327C       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x00013280   LDW R4 [R1 + TASK_FD_TABLE]
0x00013284       MOV R12 R4

0x00013288       LI R5 3              ; skip stdin/out/err
0x00013290       MOV R11 R5

fd_loop:

0x00013294       CMP R11 MAX_FDS
0x00013298       BGE fd_done         ; if we processed all fd slots, we are done

0x000132A0       SHL R6 R11 2
0x000132A4       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x000132A8       LDW R8 [R10]
0x000132AC       CMP R8 0
0x000132B0       BEQ fd_next         ; if fd slot is empty, skip to next

0x000132B8       MOV R1 R8
0x000132BC       BL file_free
0x000132C4       LI R9 0
0x000132CC       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x000132D0       ADD R11 R11 1
0x000132D4       B fd_loop

fd_done:
0x000132DC       POP R12
0x000132E0       POP R11
0x000132E4       POP R10
0x000132E8       POP R9
0x000132EC       POP R8
0x000132F0       POP LR
0x000132F4       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x000132F8       PUSH LR
0x000132FC       PUSH R8
0x00013300       PUSH R9
0x00013304       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x00013308   LI R1 CURRENT_TASK
0x00013310   LDW R10 [R1]
0x00013314       LI R8 0

task_reap_loop:
0x0001331C       CMP R8 MAX_TASKS
0x00013320       BGE task_reap_done

0x00013328       CMP R8 R10
0x0001332C       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x00013334   LI R1 TASK_SIZE
0x0001333C   MUL R3 R8 R1
0x00013340   LI R9 tasks
0x00013348   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x0001334C   LDW R1 [R9 + TASK_STATE]
0x00013350       CMP R1 TASK_ZOMBIE
0x00013354       BNE task_reap_next

0x0001335C       PUSH R8
0x00013360       MOV R1 R9
0x00013364       BL task_destroy
0x0001336C       POP R8

task_reap_next:
0x00013370       ADD R8 R8 1
0x00013374       B task_reap_loop

task_reap_done:
0x0001337C       POP R10
0x00013380       POP R9
0x00013384       POP R8
0x00013388       POP LR
0x0001338C       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x00013390       LI R1 tasks
0x00013398       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x000133A0   LDW R3 [R1 + TASK_STATE]

0x000133A4       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x000133A8       BEQ task_alloc_found

0x000133B0       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x000133B4       SUB R2 R2 1
0x000133B8       BNE task_alloc_loop

; no free tasks slots

0x000133C0       LI R1 0
0x000133C8       RET

task_alloc_found:                           ;R1 points to free task slot

0x000133CC       RET


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
0x000133D8       PUSH R2

0x000133DC       LI R2 0
0x000133E4       STW R2 [R1 + MUTEX_OWNER]      ; owner = NULL
0x000133E8       STW R2 [R1 + MUTEX_WAITQ]      ; waitq = 0 (empty)

0x000133EC       POP R2
0x000133F0       RET

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

0x000133F4       PUSH LR
0x000133F8       PUSH R8
0x000133FC       PUSH R9
0x00013400       PUSH R10

0x00013404       MOV R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x00013408   LI R1 CURRENT_TASK
0x00013410   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x00013414   LI R1 TASK_SIZE
0x0001341C   MUL R3 R9 R1
0x00013420   LI R9 tasks
0x00013428   ADD R9 R9 R3

mutex_lock_retry:
    ; Check if mutex is already locked
0x0001342C       LDW R10 [R8 + MUTEX_OWNER]
0x00013430       CMP R10 0
0x00013434       BEQ mutex_lock_acquire      ; if unlocked, acquire it

    ; this Mutex is locked by someone else - block
    ; Add current task to mutex wait queue
0x0001343C       MOV R1 R8
0x00013440       ADD R1 R1 MUTEX_WAITQ

0x00013444       LI R2 WAIT_MUTEX
0x0001344C       LI R3 TASK_WAIT_MUTEX
0x00013454       BL waitq_prepare_sleep

    ; Re-check if mutex became available while preparing sleep
0x0001345C       LDW R10 [R8 + MUTEX_OWNER]
0x00013460       CMP R10 0
0x00013464       BEQ mutex_lock_wake

    ; Still locked - go to sleep
0x0001346C       BL waitq_sleep_current

    ; Woken up - try to acquire again
0x00013474       B mutex_lock_retry

mutex_lock_wake:
    ; Mutex became available, cancel sleep and acquire
0x0001347C       MOV R1 R8
0x00013480       ADD R1 R1 MUTEX_WAITQ
0x00013484       BL waitq_cancel_sleep_current

0x0001348C       B mutex_lock_retry

mutex_lock_acquire:
    ; Disable interrupts to prevent race conditions
0x00013494       DISABLEINT

    ; Double-check it's still unlocked
0x00013498       LDW R10 [R8 + MUTEX_OWNER]
0x0001349C       CMP R10 0
0x000134A0       BNE mutex_lock_race

    ; Set owner to current task
0x000134A8       STW R9 [R8 + MUTEX_OWNER]

    ; Re-enable interrupts
0x000134AC       ENABLEINT

0x000134B0       POP R10
0x000134B4       POP R9
0x000134B8       POP R8
0x000134BC       POP LR
0x000134C0       RET

mutex_lock_race:
    ; Someone else acquired it while interrupts were disabled
0x000134C4       ENABLEINT
0x000134C8       B mutex_lock_retry


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
0x000134D0       PUSH LR
0x000134D4       PUSH R8
0x000134D8       PUSH R9
0x000134DC       PUSH R10

0x000134E0       MOV  R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x000134E4   LI R1 CURRENT_TASK
0x000134EC   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x000134F0   LI R1 TASK_SIZE
0x000134F8   MUL R3 R9 R1
0x000134FC   LI R9 tasks
0x00013504   ADD R9 R9 R3

    ; Verify ownership
0x00013508       LDW  R10 [R8 + MUTEX_OWNER]
0x0001350C       CMP  R10 R9
0x00013510       BNE  mutex_unlock_error     ; Not owner - error!

    ; Release the mutex
0x00013518       LI  R10 0
0x00013520       STW R10 [R8 + MUTEX_OWNER]

    ; Wake one waiting task (if someone is waiting)
    ; waky next one (of any waiting)
0x00013524       MOV R1 R8
0x00013528       ADD R1 R1 MUTEX_WAITQ
0x0001352C       BL waitq_wake_one

mutex_unlock_done:
0x00013534       POP R10
0x00013538       POP R9
0x0001353C       POP R8
0x00013540       POP LR
0x00013544       RET

mutex_unlock_error:
    ; Not owner - ignore (or panic)
0x00013548       POP R10
0x0001354C       POP R9
0x00013550       POP R8
0x00013554       POP LR
0x00013558       RET

; ================================================================
; waitq_wake_one - Wake exactly one task from the wait queue
; R1 = wait queue pointer
; ================================================================
waitq_wake_one:
0x0001355C       PUSH LR
0x00013560       PUSH R8
0x00013564       PUSH R9
0x00013568       PUSH R10
0x0001356C       PUSH R11

0x00013570       MOV R8 R1                  ; wait queue pointer
0x00013574       LDW R9 [R8 + WQ_MASK]      ; current wait queue mask

0x00013578       CMP R9 0
0x0001357C       BEQ waitq_wake_one_done    ; No waiters

    ; Find the first waiting task
0x00013584       LI R10 0                   ; task index

waitq_wake_one_find:
0x0001358C       CMP R10 MAX_TASKS
0x00013590       BGE waitq_wake_one_done

0x00013598       LI R11 1
0x000135A0       SHL R11 R11 R10            ; bit for this task
0x000135A4       AND R2 R9 R11
0x000135A8       CMP R2 0
0x000135AC       BNE waitq_wake_one_found

0x000135B4       ADD R10 R10 1
0x000135B8       B waitq_wake_one_find

waitq_wake_one_found:
    ; Clear this task's bit from the wait queue
0x000135C0       NOT R11 R11
0x000135C4       AND R9 R9 R11
0x000135C8       STW R9 [R8 + WQ_MASK]

    ; Wake this task
; macro: GET_TASK_PTR R5, R10
0x000135CC   LI R1 TASK_SIZE
0x000135D4   MUL R3 R10 R1
0x000135D8   LI R5 tasks
0x000135E0   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x000135E4   LI R1 TASK_READY
0x000135EC   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x000135F0   LI R1 WAIT_NONE
0x000135F8   STW R1 [R5 + TASK_WAIT]

waitq_wake_one_done:
0x000135FC       POP R11
0x00013600       POP R10
0x00013604       POP R9
0x00013608       POP R8
0x0001360C       POP LR
0x00013610       RET

; ================================================================
; CONSOLE MUTEX WRAPPER FUNCTIONS
; ================================================================

console_lock:
0x00013614       PUSH LR
0x00013618       LI R1 console_mutex
0x00013620       BL mutex_lock
0x00013628       POP LR
0x0001362C       RET

console_unlock:
0x00013630       PUSH LR
0x00013634       LI R1 console_mutex
0x0001363C       BL mutex_unlock
0x00013644       POP LR
0x00013648       RET

;=------------------------------------------------------=
; bmi_call
;
; R1 = opcode
; R2 = payload pointer
; R3 = payload length
; R4 = namespace
;
; Returns:
;   R1 = BMI reply code
;=------------------------------------------------------=

bmi_call:
0x0001364C       PUSH LR
0x00013650       PUSH R6
0x00013654       PUSH R7
0x00013658       PUSH R8
0x0001365C       PUSH R9

    ;------------------------------------
    ; Fill BMI packet
    ;------------------------------------
0x00013660       LI  R6 BMI_BUF_WRITE

0x00013668       STH R1 [R6 + BMI_HDR_OPCODE]

0x0001366C       LI  R7 0
0x00013674       STH R7 [R6 + BMI_HDR_FLAGS]

0x00013678       STW R4 [R6 + BMI_HDR_NAMESPACE]
0x0001367C       STW R3 [R6 + BMI_HDR_PAYLOAD_LEN]

    ; Copy payload

0x00013680       ADD R7 R6 BMI_HDR_SIZEOF

0x00013684       MOV R1 R7          ; dst
0x00013688       MOV R2 R2          ; src
0x0001368C       MOV R3 R3          ; len

0x00013690       BL memcpy

    ;------------------------------------
    ; Ring doorbell
    ;------------------------------------

0x00013698       LI  R6 BMI_REG_BASE

0x000136A0       LI  R7 BMI_READY
0x000136A8       STW R7 [R6 + BMI_STATUS]

0x000136AC       LI  R7 1
0x000136B4       STW R7 [R6 + BMI_DOORBELL]

wait_reply:

0x000136B8       LDW R7 [R6 + BMI_STATUS]

    ;DEBUG 2

0x000136BC       CMP R7 BMI_DONE
0x000136C0       BEQ bmi_call_done

0x000136C8       CMP R7 BMI_ERROR
0x000136CC       BEQ bmi_call_error

0x000136D4       B wait_reply

bmi_call_done:

    ;----------------------------------------
    ; Read BMI reply packet
    ;----------------------------------------

0x000136DC       LI  R8 BMI_BUF_READ

0x000136E4       LDH R1 [R8 + BMI_HDR_OPCODE]
0x000136E8       LDH R2 [R8 + BMI_HDR_FLAGS]
0x000136EC       LDW R3 [R8 + BMI_HDR_NAMESPACE]
0x000136F0       LDW R4 [R8 + BMI_HDR_PAYLOAD_LEN]

    ; R8 + BMI_HDR_SIZEOF points to reply payload


0x000136F4       LDW R1 [R6 + BMI_REPLY]

    ; reset state

0x000136F8       LI R7 BMI_IDLE
0x00013700       STW R7 [R6 + BMI_STATUS]

0x00013704       POP R9
0x00013708       POP R8
0x0001370C       POP R7
0x00013710       POP R6
0x00013714       POP LR
0x00013718       RET

bmi_call_error:
0x0001371C       LI R1 -1
0x00013724       LI R7 BMI_IDLE
0x0001372C       STW R7 [R6 + BMI_STATUS]

0x00013730       POP R9
0x00013734       POP R8
0x00013738       POP R7
0x0001373C       POP R6
0x00013740       POP LR

0x00013744       RET



; ==================================================
; TAR index entry
; ==================================================

;.EQU TAR_IDX_NAME,     0      ; ptr to filename
;.EQU TAR_IDX_DATA,     4      ; ptr to file data
;.EQU TAR_IDX_SIZE,     8      ; file size
;.EQU TAR_IDX_TYPE,    12      ; file/dir

;.EQU TAR_IDX_SIZEOF,  16

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
.EQU NSFS_INDEX_ALL, 0x32
.EQU BMI_READ_FILE, 0x31

; ================================================================
; Open flags
; ================================================================

; Access mode mask
.EQU O_ACCMODE, 0x30

; Access modes
.EQU O_RDONLY,  0x00
.EQU O_WRONLY,  0x10
.EQU O_RDWR,    0x20

; File creation / behavior flags
.EQU O_CREATE,  0x01
.EQU O_EXCL,    0x02
.EQU O_TRUNC,   0x04
.EQU O_APPEND,  0x08


;===================================================
;CONSTS for namepath validation used when FILE_CREATE
;===================================================
.EQU PATH_MAX, 256
.EQU NAME_MAX, 64



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
.ORG 0x40000

TASK_A_START:
0x00040000       li R1 25
write_loop1:
0x00040008       push R1
    ;DEBUG 2
    ; Prepare a write string in user memory.
0x0004000C       LI R1 USER_WRITE_BUF
0x00040014       LI R2 0x6C6C6548         ; "Hell"
0x0004001C       STW R2 [R1]
0x00040020       LI R2 0x57202C6F         ; "o, W"
0x00040028       STW R2 [R1 + 4]
0x0004002C       LI R2 0x646C726F         ; "orld"
0x00040034       STW R2 [R1 + 8]
0x00040038       LI R2 0x21
0x00040040       STB R2 [R1 + 12]
0x00040044       LI R2 0x0A
0x0004004C       STB R2 [R1 + 13]

0x00040050       LI R1 1                 ;fd
   ; DEBUG 1
0x00040058       LI R2 USER_WRITE_BUF    ; user buff
0x00040060       LI R3 14                ; len
0x00040068       SVC SYS_WRITE
    ;DEBUG 1
0x0004006C       pop R1
0x00040070       sub R1 R1 1
0x00040074       cmp r1 0
0x00040078       BNE write_loop1
    ; Exit after the write test.
0x00040080       LI R1 SYS_EXIT
0x00040088       SVC SYS_EXIT


; ---TASK 2---------------------------------------------

TASK_B_START:

    ; Read the built-in TARFS message through open/read/close.
0x0004008C       LI R1 task_b_motd_path
0x00040094       LI R2 FD_FLAG_READ
0x0004009C       SVC SYS_OPEN
0x000400A0       MOV R8 R1
0x000400A4       CMP R8 0
0x000400A8       BLT task_b_open_fail

0x000400B0       MOV R1 R8
0x000400B4       LI R2 USER_READ_BUF
0x000400BC       LI R3 32
0x000400C4       SVC SYS_READ
0x000400C8       MOV R9 R1

0x000400CC       LI R1 STDOUT_FD
0x000400D4       LI R2 USER_READ_BUF
0x000400DC       MOV R3 R9
0x000400E0       SVC SYS_WRITE

0x000400E4       MOV R1 R8
0x000400E8       SVC SYS_CLOSE

task_b_loop:

    ;=========================================
    ; fd = open("/dev/console", WRITE)
    ;=========================================

0x000400EC       LI R1 task_b_console_path
0x000400F4       LI R2 FD_FLAG_WRITE
0x000400FC       SVC SYS_OPEN
    ;DEBUG 1
0x00040100       MOV R8 R1                  ; save fd

    ; open failed?
0x00040104       CMP R8 0
0x00040108       BLT task_b_open_fail

    ;=========================================
    ; write(fd, msg, len)
    ;=========================================

0x00040110       MOV R1 R8
0x00040114       LI R2 task_b_msg
0x0004011C       LI R3 27
0x00040124       SVC SYS_WRITE
    ;DEBUG 2

    ;=========================================
    ; close(fd)
    ;=========================================

0x00040128       MOV R1 R8
0x0004012C       SVC SYS_CLOSE

    ; Block until console input is available, then echo exactly the number
    ; of bytes returned by read(). The UART driver stops at newline or after
    ; CONSOLE_INPUT_LEN bytes.
0x00040130       LI R1 STDIN_FD
0x00040138       LI R2 USER_READ_BUF
0x00040140       LI R3 5
0x00040148       SVC SYS_READ
  ;  DEBUG  2
0x0004014C       CMP R1 0
0x00040150       BLE task_b_yield

0x00040158       MOV R5 R1
0x0004015C       LI R1 STDOUT_FD
0x00040164       LI R2 USER_READ_BUF
0x0004016C       MOV R3 R5
0x00040170       SVC SYS_WRITE

task_b_yield:
0x00040174       SVC SYS_YIELD
0x00040178       B task_b_yield

task_b_open_fail:

0x00040180       LI R1 1
0x00040188       LI R2 open_fail_msg
0x00040190       LI R3 11
0x00040198       SVC SYS_WRITE

0x0004019C       SVC SYS_YIELD

0x000401A0       B task_b_loop

; task2 date page
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
0x000401EF       LI R6 USER_WRITE_BUF
0x000401F7       MOV R1 R6
0x000401FB       SVC SYS_GETTIME
0x000401FF       CMP R1 0
0x00040203       BLT gettime_error
0x0004020B       LDW R4 [R6 + TIMEVAL_SEC]   ; Store start seconds in R4

    ; Fork a child process
0x0004020F       SVC SYS_FORK

0x00040213       CMP R1 0
0x00040217       BEQ child_process_c
0x0004021F       BLT fork_error_c
0x00040227       MOV R5 R1          ; Parent keeps child PID

parent_process:
    ; this is to test mutex in debug in mutual printing to vy several process to console
    ; Parent process - keep both tasks active so console writes contend
0x0004022B       LI R6 2
pr_1:
0x00040233       cmp R6 0
0x00040237       Beq pr_fin
0x0004023F       LI R1 STDOUT_FD
0x00040247       LI R2 parent_wait_msg
0x0004024F       LI R3 16
0x00040257       SVC SYS_WRITE
0x0004025B       LI R1 1
0x00040263       SVC SYS_SLEEP
0x00040267       sub R6 R6 1
0x0004026B       B   pr_1
pr_fin:

    ; Wait for child to exit
    ;MOV R1 R5           ; Child PID from fork
0x00040273       LI R1 -1            ; wait for any
0x0004027B       LI R2 0             ; No status pointer needed for this test
0x00040283       SVC SYS_WAITPID

0x00040287       CMP R1 0
0x0004028B       BLT wait_error_c

    ; Child exited normally
0x00040293       LI R1 STDOUT_FD
0x0004029B       LI R2 parent_done_msg
0x000402A3       LI R3 13
0x000402AB       SVC SYS_WRITE

    ; Print newline
0x000402AF       LI R1 STDOUT_FD
0x000402B7       LI R2 newline
0x000402BF       LI R3 1
0x000402C7       SVC SYS_WRITE

0x000402CB       B exit_success

wait_error_c:
0x000402D3       LI R1 STDOUT_FD
0x000402DB       LI R2 wait_error_msg_с
0x000402E3       LI R3 14
0x000402EB       SVC SYS_WRITE
0x000402EF       B exit_failure

child_process_c:
    ; Child process - write in a tight loop so it overlaps with parent

0x000402F7       LI R1 STDOUT_FD
0x000402FF       LI R2 child_start_msg
0x00040307       LI R3 13
0x0004030F       SVC SYS_WRITE


    ;LI R1 echo_path
    ;LI R2 echo_argv
    ;LI R3 0

0x00040313       LI R1 cat_path
0x0004031B       LI R2 cat_argv
0x00040323       LI R3 0

    ;LI R1 ls_path
    ;LI R2 ls_argv
    ;LI R3 0

0x0004032B       SVC SYS_EXECVE
    ; returns if error with execve

0x0004032F       LI R1 STDOUT_FD
0x00040337       LI R2 exec_failed_msg_c
0x0004033F       LI R3 13
0x00040347       SVC SYS_WRITE

0x0004034B       LI R1 1
0x00040353       SVC SYS_SLEEP


    ; Child exits with status 42
    ;LI R1 42
0x00040357       LI R1 0
0x0004035F       SVC SYS_EXIT

sleep_error:
0x00040363       LI R1 STDOUT_FD
0x0004036B       LI R2 sleep_error_msg
0x00040373       LI R3 12
0x0004037B       SVC SYS_WRITE
0x0004037F       LI R1 1              ; Exit with error code
0x00040387       SVC SYS_EXIT

fork_error_c:
0x0004038B       LI R1 STDOUT_FD
0x00040393       LI R2 fork_error_msg_c
0x0004039B       LI R3 11
0x000403A3       SVC SYS_WRITE
0x000403A7       B exit_failure

gettime_error:
0x000403AF       LI R1 STDOUT_FD
0x000403B7       LI R2 gettime_error_msg
0x000403BF       LI R3 14
0x000403C7       SVC SYS_WRITE
0x000403CB       B exit_failure

exit_success:
0x000403D3       LI R1 0
0x000403DB       SVC SYS_EXIT

exit_failure:
0x000403DF       LI R1 1
0x000403E7       SVC SYS_EXIT

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


;|+================================================================+|
; task_init – PID 1 initial process
;|+================================================================+|
; This is the first user‑space process created by the kernel.
; It acts as a simple init:
;   - fork() a child
;   - child execs /bin/sh (the interactive shell)
;   - parent waits for the shell to exit, then restarts it
;|+================================================================+|
TASK_INIT_START:

    ; print a startup message
0x000404FA       LI R1 STDOUT_FD
0x00040502       LI R2 init_start_msg
0x0004050A       LI R3 12
0x00040512       SVC SYS_WRITE

init_loop:
    ; ------------------------------------------------------------
    ; Fork a new child
    ; ------------------------------------------------------------
0x00040516       SVC SYS_FORK
0x0004051A       CMP R1 0
0x0004051E       BEQ child_process
0x00040526       BLT fork_error

    ; ------------------------------------------------------------
    ; Parent process: wait for the child to terminate
    ; ------------------------------------------------------------
0x0004052E       MOV R5 R1                ; Save child PID (not strictly needed)
0x00040532       LI R1 -1                 ; Wait for any child
0x0004053A       LI R2 0                  ; No status pointer needed
0x00040542       SVC SYS_WAITPID
0x00040546       CMP R1 0
0x0004054A       BLT wait_error

    ; Child exited normally – restart the shell
0x00040552       LI R1 STDOUT_FD
0x0004055A       LI R2 restart_msg
0x00040562       LI R3 14
0x0004056A       SVC SYS_WRITE

0x0004056E       B init_loop              ; Forever

    ; ------------------------------------------------------------
    ; Child process: replace itself with /bin/sh
    ; ------------------------------------------------------------
child_process:
0x00040576       LI R1 sh_path
0x0004057E       LI R2 sh_argv
0x00040586       LI R3 0                  ; No environment
0x0004058E       SVC SYS_EXECVE

    ; If execve returns, it failed
0x00040592       LI R1 STDOUT_FD
0x0004059A       LI R2 exec_failed_msg
0x000405A2       LI R3 13
0x000405AA       SVC SYS_WRITE

0x000405AE       LI R1 1                  ; Exit with error
0x000405B6       SVC SYS_EXIT

    ; ------------------------------------------------------------
    ; Error handlers (print and halt)
    ; ------------------------------------------------------------
fork_error:
0x000405BA       LI R1 STDOUT_FD
0x000405C2       LI R2 fork_error_msg
0x000405CA       LI R3 11
0x000405D2       SVC SYS_WRITE
0x000405D6       LI R1 1
0x000405DE       SVC SYS_EXIT

wait_error:
0x000405E2       LI R1 STDOUT_FD
0x000405EA       LI R2 wait_error_msg
0x000405F2       LI R3 14
0x000405FA       SVC SYS_WRITE
    ; Continue looping even on wait error (maybe child vanished)
0x000405FE       B init_loop

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
    .ASCIIZ "/bin/sh"
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

.ORG 0x000D0000
tarfs_start:
; /bin/
    .ASCIIZ "/bin/"
    .SPACE 118
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; /etc/
    .ASCIIZ "/etc/"
    .SPACE 118
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; /lib/
    .ASCIIZ "/lib/"
    .SPACE 118
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; /
    .ASCIIZ "/"
    .SPACE 122
    .ASCIIZ "00000000000"
    .SPACE 20
    .ASCIIZ "5"
    .SPACE 354

; /bin/cat, 4715 bytes
    .ASCIIZ "/bin/cat"
    .SPACE 115
    .ASCIIZ "00000011153"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4715 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000
    .WORD 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x42221200, 0x00000004, 0x00010F0A
    .WORD 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x41EE1500, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x00000102, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x41A21200
    .WORD 0x0B000004, 0x0C000181, 0x00000182, 0x01000F03, 0x00000000, 0x32443000, 0x01000004, 0x00800187
    .WORD 0x00000407, 0x418A1300, 0x00000004, 0x00010F01, 0x0C000000, 0x07000182, 0x00000183, 0x323C3000
    .WORD 0x00000004, 0x41420500, 0x0B000004, 0x00000181, 0x32543000, 0x0A810004, 0x0000020A, 0x410A0500
    .WORD 0x00000004, 0x42570F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x3FFE0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06
    .WORD 0x0A810000, 0x0000020A, 0x410A0500, 0x00000004, 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181
    .WORD 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F
    .WORD 0x00003100, 0x42420F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x00000000, 0x41EE0500
    .WORD 0x73750004, 0x3A656761, 0x74616320, 0x6C696620, 0x2E2E2065, 0x63000A2E, 0x203A7461, 0x6E6E6163
    .WORD 0x6F20746F, 0x206E6570, 0x00000A00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; /bin/cp, 4916 bytes
    .ASCIIZ "/bin/cp"
    .SPACE 116
    .ASCIIZ "00000011464"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4916 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x00800F03, 0x0D030000
    .WORD 0x0D00030D, 0x0100018C, 0x02000188, 0x00000189, 0x00010F06, 0x00000000, 0xFFFF0F0A, 0x0000FFFF
    .WORD 0xFFFF0F0B, 0x0083FFFF, 0x00000408, 0x41C20700, 0x09040004, 0x00002201, 0x00000F02, 0x00000000
    .WORD 0x324C3000, 0x01000004, 0x0080018A, 0x0000040A, 0x41DA1200, 0x09080004, 0x00002201, 0x00110F02
    .WORD 0x00000000, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x420E1200, 0x0A000004, 0x0C000181
    .WORD 0x00000182, 0x00800F03, 0x00000000, 0x32443000, 0x01000004, 0x00800187, 0x00000407, 0x42421200
    .WORD 0x00000004, 0x41B20600, 0x0B000004, 0x0C000181, 0x07000182, 0x00000183, 0x323C3000, 0x07000004
    .WORD 0x00000401, 0x425A0700, 0x00000004, 0x415A0500, 0x00000004, 0x00000F06, 0x00000000, 0x42720500
    .WORD 0x00000004, 0x42D60F01, 0x00000004, 0x30583000, 0x00000004, 0x42720500, 0x00000004, 0x42ED0F01
    .WORD 0x00000004, 0x30583000, 0x09040004, 0x00002201, 0x30583000, 0x00000004, 0x43320F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x42720500, 0x00000004, 0x42FE0F01, 0x00000004, 0x30583000, 0x09080004
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x43320F01, 0x00000004, 0x30583000, 0x00000004, 0x42720500
    .WORD 0x00000004, 0x43110F01, 0x00000004, 0x30583000, 0x00000004, 0x42720500, 0x00000004, 0x43210F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x42720500, 0x00800004, 0x0000040B, 0x428A1200, 0x0B000004
    .WORD 0x00000181, 0x32543000, 0x00800004, 0x0000040A, 0x42A21200, 0x0A000004, 0x00000181, 0x32543000
    .WORD 0x00000004, 0x00800F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x73753100, 0x3A656761, 0x20706320
    .WORD 0x72756F73, 0x64206563, 0x0A747365, 0x3A706300, 0x6E616320, 0x20746F6E, 0x6E65706F, 0x70630020
    .WORD 0x6163203A, 0x746F6E6E, 0x65726320, 0x20657461, 0x3A706300, 0x61657220, 0x72652064, 0x0A726F72
    .WORD 0x3A706300, 0x69727720, 0x65206574, 0x726F7272, 0x000A000A, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/echo, 4434 bytes
    .ASCIIZ "/bin/echo"
    .SPACE 114
    .ASCIIZ "00000010522"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4434 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x02000188, 0x00000189, 0x00010F0A, 0x09000000, 0x0B84018B
    .WORD 0x0800020B, 0x0000040A, 0x41361500, 0x0B000004, 0x00002201, 0x30583000, 0x0A810004, 0x0B84020A
    .WORD 0x0800020B, 0x0000040A, 0x41261500, 0x00000004, 0x3FFC0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x40E20500, 0x00000004, 0x3FFE0F01, 0x00000004, 0x30583000, 0x00000004, 0x00000F01, 0x00000000
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/fc, 4611 bytes
    .ASCIIZ "/bin/fc"
    .SPACE 116
    .ASCIIZ "00000011003"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4611 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408
    .WORD 0x41BA1200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x41961500
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00010F02, 0x00000000, 0x324C3000
    .WORD 0x01000004, 0x0080018B, 0x0000040B, 0x414A1200, 0x0B000004, 0x00000181, 0x32543000, 0x0A810004
    .WORD 0x0000020A, 0x40F60500, 0x00000004, 0x41EE0F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182
    .WORD 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x42010F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x40F60500, 0x06000004, 0x00000181, 0x0000110B
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x41DA0F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x00010F01, 0x00000000, 0x41960500, 0x73750004, 0x3A656761
    .WORD 0x20636620, 0x656C6966, 0x2E2E2E20, 0x6366000A, 0x6163203A, 0x746F6E6E, 0x65726320, 0x20657461
    .WORD 0x00000A00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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

; /bin/ls, 4887 bytes
    .ASCIIZ "/bin/ls"
    .SPACE 116
    .ASCIIZ "00000011427"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4887 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000
    .WORD 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x42B61200, 0x00000004, 0x00010F0A
    .WORD 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x42821500, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x00001001, 0x3FFE0F01, 0x00000004, 0x30583000, 0x00000004, 0x43000F01
    .WORD 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000
    .WORD 0x00000004, 0x43100F01, 0x00000004, 0x30583000, 0x00000004, 0x3FFE0F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00001101, 0x00000F02, 0x00000000, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B
    .WORD 0x42361200, 0x0B000004, 0x0C000181, 0x00000182, 0x004C0F03, 0x00000000, 0x32443000, 0x01000004
    .WORD 0x00800187, 0x00000407, 0x421E0600, 0x00CC0004, 0x00000407, 0x421E0700, 0x0C080004, 0x0C8C2005
    .WORD 0x00000201, 0x30583000, 0x00820004, 0x00000405, 0x42060700, 0x00000004, 0x43150F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x3FFE0F01, 0x00000004, 0x30583000, 0x00000004, 0x41A60500, 0x0B000004
    .WORD 0x00000181, 0x32543000, 0x0A810004, 0x0000020A, 0x410A0500, 0x00000004, 0x42EF0F01, 0x00000004
    .WORD 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004
    .WORD 0x3FFE0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x410A0500
    .WORD 0x00000004, 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x42D60F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x00010F06, 0x00000000, 0x42820500, 0x73750004, 0x3A656761, 0x20736C20
    .WORD 0x65726964, 0x726F7463, 0x2E2E2079, 0x6C000A2E, 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65
    .WORD 0x202D2D2D, 0x65726944, 0x726F7463, 0x00203A79, 0x2D2D2D20, 0x00002F00, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/ls1, 4877 bytes
    .ASCIIZ "/bin/ls1"
    .SPACE 115
    .ASCIIZ "00000011415"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4877 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x004C0F03, 0x0D030000
    .WORD 0x0D00030D, 0x0100018C, 0x02000188, 0x00820189, 0x00000408, 0x42AA1200, 0x00000004, 0x00010F0A
    .WORD 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x42761500, 0x0A000004, 0x02820182, 0x09020C02
    .WORD 0x02000202, 0x00002201, 0x00001001, 0x3FFE0F01, 0x00000004, 0x30583000, 0x00000004, 0x42F40F01
    .WORD 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000
    .WORD 0x00000004, 0x43040F01, 0x00000004, 0x30583000, 0x00000004, 0x3FFE0F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00001101, 0x395C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x422A0600, 0x0B000004
    .WORD 0x0C000181, 0x00000182, 0x3A003000, 0x00800004, 0x00000401, 0x42120600, 0x00000004, 0xFFFF0F02
    .WORD 0x0200FFFF, 0x00000401, 0x42120600, 0x0C080004, 0x0C8C2205, 0x00000201, 0x30583000, 0x00820004
    .WORD 0x00000405, 0x41FA0700, 0x00000004, 0x43090F01, 0x00000004, 0x30583000, 0x00000004, 0x3FFE0F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x419E0500, 0x0B000004, 0x00000181, 0x3A903000, 0x0A810004
    .WORD 0x0000020A, 0x410A0500, 0x00000004, 0x42E30F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182
    .WORD 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x430B0F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x410A0500, 0x00000004, 0x004C0F03, 0x0D030000
    .WORD 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107
    .WORD 0x00001106, 0x0000110F, 0x00003100, 0x42CA0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06
    .WORD 0x00000000, 0x42760500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964, 0x726F7463, 0x2E2E2079
    .WORD 0x6C000A2E, 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D, 0x65726944, 0x726F7463
    .WORD 0x00203A79, 0x2D2D2D20, 0x0A002F00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/mkdir, 4604 bytes
    .ASCIIZ "/bin/mkdir"
    .SPACE 113
    .ASCIIZ "00000010774"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4604 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408
    .WORD 0x41AE1200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x418A1500
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00000F02, 0x00000000, 0x325C3000
    .WORD 0x01000004, 0x0080018B, 0x0000040B, 0x413E1200, 0x0A810004, 0x0000020A, 0x40F60500, 0x00000004
    .WORD 0x41E40F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x30583000, 0x00000004, 0x41FA0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000
    .WORD 0x0000020A, 0x40F60500, 0x06000004, 0x00000181, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x41CE0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00010F01, 0x00000000, 0x418A0500, 0x73750004, 0x3A656761, 0x646B6D20, 0x64207269, 0x2E207269
    .WORD 0x000A2E2E, 0x69646B6D, 0x63203A72, 0x6F6E6E61, 0x72632074, 0x65746165, 0x000A0020, 0x00000000

; /bin/print, 4554 bytes
    .ASCIIZ "/bin/print"
    .SPACE 113
    .ASCIIZ "00000010712"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4554 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001008
    .WORD 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408, 0x416A1200, 0x09040004
    .WORD 0x01002201, 0x0000018A, 0x00000F02, 0x00000000, 0x00000F03, 0x00000000, 0x00000F04, 0x09080000
    .WORD 0x01002201, 0x00830182, 0x00000408, 0x414E0600, 0x090C0004, 0x01002201, 0x00840183, 0x00000408
    .WORD 0x414E0600, 0x09100004, 0x01002201, 0x00850184, 0x00000408, 0x414E0600, 0x09140004, 0x01002201
    .WORD 0x00860185, 0x00000408, 0x414E0600, 0x0A000004, 0x00000181, 0x3C5C3000, 0x00000004, 0x00000F01
    .WORD 0x00000000, 0x41820500, 0x00000004, 0x419A0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F01
    .WORD 0x00000000, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x73753100, 0x3A656761
    .WORD 0x69727020, 0x4620746E, 0x414D524F, 0x415B2054, 0x5D314752, 0x52415B20, 0x205D3247, 0x4752415B
    .WORD 0x5B205D33, 0x34475241, 0x0000005D, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/rm, 4599 bytes
    .ASCIIZ "/bin/rm"
    .SPACE 116
    .ASCIIZ "00000010767"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4599 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408
    .WORD 0x41AE1200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x418A1500
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00000F02, 0x00000000, 0x326C3000
    .WORD 0x01000004, 0x0080018B, 0x0000040B, 0x413E1200, 0x0A810004, 0x0000020A, 0x40F60500, 0x00000004
    .WORD 0x41E20F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x30583000, 0x00000004, 0x41F50F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000
    .WORD 0x0000020A, 0x40F60500, 0x06000004, 0x00000181, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x41CE0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00010F01, 0x00000000, 0x418A0500, 0x73750004, 0x3A656761, 0x206D7220, 0x656C6966, 0x2E2E2E20
    .WORD 0x6D72000A, 0x6163203A, 0x746F6E6E, 0x6D657220, 0x2065766F, 0x00000A00, 0x00000000, 0x00000000

; /bin/rmdir, 4604 bytes
    .ASCIIZ "/bin/rmdir"
    .SPACE 113
    .ASCIIZ "00000010774"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4604 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006
    .WORD 0x00001007, 0x00001008, 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408
    .WORD 0x41AE1200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x418A1500
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x00000F02, 0x00000000, 0x32643000
    .WORD 0x01000004, 0x0080018B, 0x0000040B, 0x413E1200, 0x0A810004, 0x0000020A, 0x40F60500, 0x00000004
    .WORD 0x41E40F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x30583000, 0x00000004, 0x41FA0F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000
    .WORD 0x0000020A, 0x40F60500, 0x06000004, 0x00000181, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x41CE0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00010F01, 0x00000000, 0x418A0500, 0x73750004, 0x3A656761, 0x646D7220, 0x64207269, 0x2E207269
    .WORD 0x000A2E2E, 0x69646D72, 0x63203A72, 0x6F6E6E61, 0x65722074, 0x65766F6D, 0x000A0020, 0x00000000

; /bin/sh, 5971 bytes
    .ASCIIZ "/bin/sh"
    .SPACE 116
    .ASCIIZ "00000013523"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (5971 bytes, padded to 6144)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x0004365C, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440B6, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00044000, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40050000, 0x31000000, 0x40060000, 0x31000000, 0x40070000, 0x31000000, 0x40110000
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x40130000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000
    .WORD 0x31000000, 0x40100000, 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043298
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
    .WORD 0x040400B0, 0x15000000, 0x00043568, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030208, 0x04030080, 0x07000000, 0x00043544, 0x22030204, 0x04030500, 0x15000000
    .WORD 0x00043550, 0x02040481, 0x05000000, 0x00043500, 0x0F030000, 0x00000001, 0x25030208, 0x22010200
    .WORD 0x05000000, 0x000435E8, 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435E0, 0x0F040000
    .WORD 0x00000000, 0x040400B0, 0x15000000, 0x000435E0, 0x0F020000, 0x000432A0, 0x0F030000, 0x0000000C
    .WORD 0x08030403, 0x02020203, 0x22030208, 0x04030080, 0x06000000, 0x000435C4, 0x02040481, 0x05000000
    .WORD 0x00043584, 0x25010200, 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E8
    .WORD 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x00043654
    .WORD 0x0F040000, 0x00000000, 0x040400B0, 0x15000000, 0x00043654, 0x0F020000, 0x000432A0, 0x0F030000
    .WORD 0x0000000C, 0x08030403, 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043648, 0x02040481
    .WORD 0x05000000, 0x00043608, 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F010000, 0x000432A0, 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043698, 0x0F020000
    .WORD 0x00000000, 0x23020100, 0x02010181, 0x03030381, 0x05000000, 0x00043670, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10050000, 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000
    .WORD 0x100C0000, 0x01880100, 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000
    .WORD 0x10080000, 0x040C0081, 0x07000000, 0x00043714, 0x04090080, 0x15000000, 0x00043714, 0x0F020000
    .WORD 0x0000002D, 0x23020800, 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x00043744
    .WORD 0x0F020000, 0x00000030, 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000
    .WORD 0x000437E4, 0x0F040000, 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000
    .WORD 0x00043770, 0x020707B0, 0x05000000, 0x00043790, 0x04070089, 0x14000000, 0x00043788, 0x020707B0
    .WORD 0x05000000, 0x00043790, 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600
    .WORD 0x04090080, 0x07000000, 0x0004374C, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D8, 0x20020A00
    .WORD 0x23020800, 0x02080881, 0x030A0A81, 0x03040481, 0x05000000, 0x000437B0, 0x0F020000, 0x00000000
    .WORD 0x23020800, 0x11010000, 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000
    .WORD 0x11080000, 0x11070000, 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000
    .WORD 0x0000000A, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000
    .WORD 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009
    .WORD 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000
    .WORD 0x00000000, 0x0F050000, 0x0000000D, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000002, 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x000436A0
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000
    .WORD 0x0000000A, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000001, 0x0F050000, 0x00000022, 0x30000000, 0x000436A0, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x01830100, 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043950
    .WORD 0x02010181, 0x02040481, 0x05000000, 0x0004392C, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100
    .WORD 0x04010080, 0x12000000, 0x000439E8, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434E0
    .WORD 0x11090000, 0x04010080, 0x06000000, 0x000439D0, 0x01880100, 0x25090800, 0x0F020000, 0x00000000
    .WORD 0x25020804, 0x01810800, 0x05000000, 0x000439F0, 0x01810900, 0x40070000, 0x0F010000, 0x00000000
    .WORD 0x05000000, 0x000439F0, 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A68
    .WORD 0x22010800, 0x01820900, 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A78
    .WORD 0x040100CC, 0x07000000, 0x00043A68, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001
    .WORD 0x05000000, 0x00043A80, 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A80, 0x0F010000, 0x00000000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080
    .WORD 0x06000000, 0x00043ACC, 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435F0, 0x0F010000
    .WORD 0x00000000, 0x05000000, 0x00043AD4, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000
    .WORD 0x04010080, 0x06000000, 0x00043B0C, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000
    .WORD 0x01880100, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B24, 0x22010100
    .WORD 0x31000000, 0x0F010000, 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x0004395C, 0x04010080
    .WORD 0x06000000, 0x00043B64, 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A90, 0x05000000
    .WORD 0x00043B6C, 0x0F010000, 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x030D0DCC, 0x01890D00, 0x01810800, 0x30000000, 0x0004395C, 0x04010080, 0x06000000
    .WORD 0x00043C38, 0x01880100, 0x01810800, 0x01820900, 0x30000000, 0x00043A00, 0x04010080, 0x06000000
    .WORD 0x00043C1C, 0x0F020000, 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C38, 0x0201098C, 0x30000000
    .WORD 0x00043058, 0x22020908, 0x04020082, 0x07000000, 0x00043C04, 0x0F010000, 0x00043C54, 0x30000000
    .WORD 0x00043098, 0x0F010000, 0x00043C58, 0x30000000, 0x00043098, 0x05000000, 0x00043BA8, 0x01810800
    .WORD 0x30000000, 0x00043A90, 0x0F010000, 0x00000000, 0x05000000, 0x00043C40, 0x0F010000, 0xFFFFFFFF
    .WORD 0x020D0DCC, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000
    .WORD 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04
    .WORD 0x25040D08, 0x25050D0C, 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24
    .WORD 0x250C0D28, 0x01880100, 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080
    .WORD 0x06000000, 0x00043F18, 0x040100A5, 0x07000000, 0x00043D6C, 0x02080881, 0x20020800, 0x04020080
    .WORD 0x06000000, 0x00043F18, 0x040200A5, 0x06000000, 0x00043D7C, 0x040200F3, 0x06000000, 0x00043E10
    .WORD 0x040200E4, 0x06000000, 0x00043E2C, 0x040200E9, 0x06000000, 0x00043E2C, 0x040200F8, 0x06000000
    .WORD 0x00043E5C, 0x040200E3, 0x06000000, 0x00043E8C, 0x040200E2, 0x06000000, 0x00043EAC, 0x040200EF
    .WORD 0x06000000, 0x00043EDC, 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x0F010000
    .WORD 0x00000025, 0x30000000, 0x00043098, 0x05000000, 0x00043F0C, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22010300, 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000
    .WORD 0x00043DD4, 0x22020300, 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DFC
    .WORD 0x0303098B, 0x0F040000, 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000
    .WORD 0x00000004, 0x08030904, 0x02030A03, 0x31000000, 0x30000000, 0x00043D94, 0x02090981, 0x30000000
    .WORD 0x00043F38, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F7C, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043F9C, 0x05000000, 0x00043F0C, 0x30000000, 0x00043D94, 0x20010100, 0x02090981, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F0C, 0x30000000, 0x00043DB4, 0x01810200, 0x30000000, 0x00044002
    .WORD 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FBC, 0x05000000, 0x00043F0C, 0x30000000
    .WORD 0x00043DB4, 0x01810200, 0x30000000, 0x00044002, 0x01820100, 0x02090981, 0x01810B00, 0x30000000
    .WORD 0x00043FDC, 0x05000000, 0x00043F0C, 0x02080881, 0x05000000, 0x00043CB8, 0x020D0DD0, 0x110C0000
    .WORD 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x30000000, 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043818, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043844, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x0004389C, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x30000000, 0x00043870, 0x01810100, 0x30000000, 0x00043F38, 0x110F0000, 0x31000000, 0x000A0020
    .WORD 0x00000000, 0x0000100F, 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000
    .WORD 0x00000F0A, 0x08000000, 0x00AD2002, 0x00000402, 0x40420700, 0x00000004, 0x00010F0A, 0x08810000
    .WORD 0x08000208, 0x00802002, 0x00000402, 0x408A0600, 0x00B00004, 0x00000402, 0x408A1200, 0x00B90004
    .WORD 0x00000402, 0x408A1400, 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209
    .WORD 0x00000208, 0x40420500, 0x00810004, 0x0000040A, 0x409E0700, 0x09000004, 0x09812809, 0x09000209
    .WORD 0x00000181, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00010F01
    .WORD 0x00000000, 0x462A0F02, 0x00000004, 0x00020F03, 0x00000000, 0x323C3000, 0x00000004, 0x00000F01
    .WORD 0x00000000, 0x46530F02, 0x00000004, 0x007F0F03, 0x00000000, 0x32443000, 0x00800004, 0x00000401
    .WORD 0x429A1300, 0x01000004, 0x00000184, 0x46530F08, 0x00000004, 0x46530F09, 0x00000004, 0x00000F0A
    .WORD 0x04000000, 0x0000040A, 0x419A1500, 0x080A0004, 0x05000205, 0x008A2006, 0x00000406, 0x418E0600
    .WORD 0x008D0004, 0x00000406, 0x418E0600, 0x00880004, 0x00000406, 0x41760600, 0x00FF0004, 0x00000406
    .WORD 0x41760600, 0x09000004, 0x09812306, 0x00000209, 0x418E0500, 0x08000004, 0x00000409, 0x418E1300
    .WORD 0x09810004, 0x00000309, 0x418E0500, 0x0A810004, 0x0000020A, 0x41220500, 0x00000004, 0x00000F06
    .WORD 0x09000000, 0x00002306, 0x46530F07, 0x07000004, 0x00802006, 0x00000406, 0x40BA0600, 0x00000004
    .WORD 0x42A23000, 0x00000004, 0x46530F01, 0x00000004, 0x462E0F02, 0x00000004, 0x31183000, 0x00810004
    .WORD 0x00000401, 0x429A0600, 0x00000004, 0x32743000, 0x00800004, 0x00000401, 0x42320600, 0x00000004
    .WORD 0x426A1200, 0x00000004, 0xFFFF0F01, 0x0000FFFF, 0x00000F02, 0x00000000, 0x32843000, 0x00800004
    .WORD 0x00000401, 0x42821200, 0x00000004, 0x40BA0500, 0x00000004, 0x46530F01, 0x00000004, 0x46D30F02
    .WORD 0x00000004, 0x00000F03, 0x00000000, 0x327C3000, 0x00000004, 0x46330F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x0000110F, 0x00003100, 0x463F0F01, 0x00000004, 0x30583000, 0x00000004, 0x40BA0500
    .WORD 0x00000004, 0x46490F01, 0x00000004, 0x30583000, 0x00000004, 0x40BA0500, 0x00000004, 0x0000110F
    .WORD 0x00003100, 0x0000100F, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x46530F08
    .WORD 0x00000004, 0x46530F09, 0x00000004, 0x00000F0A, 0x00000000, 0x00000F0C, 0x08000000, 0x0080200B
    .WORD 0x0000040B, 0x450E0600, 0x00A00004, 0x0000040B, 0x43020700, 0x08810004, 0x00000208, 0x42DA0500
    .WORD 0x00880004, 0x0000040A, 0x450E1500, 0x00000004, 0x46D30F07, 0x0A000004, 0x06820186, 0x07060C06
    .WORD 0x07000207, 0x0A812509, 0x0000020A, 0x00000F0C, 0x00000000, 0x433A0500, 0x08000004, 0x0080200B
    .WORD 0x0000040B, 0x45020600, 0x00800004, 0x0000040C, 0x43C20700, 0x00A00004, 0x0000040B, 0x44E60600
    .WORD 0x00A20004, 0x0000040B, 0x439A0600, 0x00A70004, 0x0000040B, 0x43AE0600, 0x00DC0004, 0x0000040B
    .WORD 0x44020600, 0x09000004, 0x0881230B, 0x09810208, 0x00000209, 0x433A0500, 0x00000004, 0x00220F0C
    .WORD 0x08810000, 0x00000208, 0x433A0500, 0x00000004, 0x00270F0C, 0x08810000, 0x00000208, 0x433A0500
    .WORD 0x0C000004, 0x0000040B, 0x43EE0600, 0x00DC0004, 0x0000040B, 0x44020600, 0x09000004, 0x0881230B
    .WORD 0x09810208, 0x00000209, 0x433A0500, 0x00000004, 0x00000F0C, 0x08810000, 0x00000208, 0x433A0500
    .WORD 0x08810004, 0x08000208, 0x0080200B, 0x0000040B, 0x45020600, 0x00EE0004, 0x0000040B, 0x44720600
    .WORD 0x00F20004, 0x0000040B, 0x44820600, 0x00F40004, 0x0000040B, 0x44920600, 0x00DC0004, 0x0000040B
    .WORD 0x44A20600, 0x00A20004, 0x0000040B, 0x44B20600, 0x00A70004, 0x0000040B, 0x44C20600, 0x09000004
    .WORD 0x0881230B, 0x09810208, 0x00000209, 0x433A0500, 0x00000004, 0x000A0F0B, 0x00000000, 0x44D20500
    .WORD 0x00000004, 0x000D0F0B, 0x00000000, 0x44D20500, 0x00000004, 0x00090F0B, 0x00000000, 0x44D20500
    .WORD 0x00000004, 0x005C0F0B, 0x00000000, 0x44D20500, 0x00000004, 0x00220F0B, 0x00000000, 0x44D20500
    .WORD 0x00000004, 0x00270F0B, 0x00000000, 0x44D20500, 0x09000004, 0x0881230B, 0x09810208, 0x00000209
    .WORD 0x433A0500, 0x00000004, 0x00000F0B, 0x09000000, 0x0981230B, 0x08810209, 0x00000208, 0x42DA0500
    .WORD 0x00000004, 0x00000F0B, 0x09000000, 0x0000230B, 0x46D30F07, 0x0A000004, 0x06820186, 0x07060C06
    .WORD 0x00000207, 0x00000F0B, 0x07000000, 0x0000250B, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B
    .WORD 0x46530F08, 0x00000004, 0x46D30F09, 0x00000004, 0x00000F0A, 0x08000000, 0x00A0200B, 0x0000040B
    .WORD 0x43020700, 0x00000004, 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208, 0x45760500, 0x08000004
    .WORD 0x0080200B, 0x0000040B, 0x450E0600, 0x00880004, 0x0000040A, 0x450E1500, 0x09000004, 0x09842508
    .WORD 0x0A810209, 0x0800020A, 0x0080200B, 0x0000040B, 0x450E0600, 0x00A00004, 0x0000040B, 0x45EE0600
    .WORD 0x08810004, 0x00000208, 0x433A0500, 0x00000004, 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208
    .WORD 0x42DA0500, 0x00000004, 0x00000F0B, 0x09000000, 0x0000250B, 0x0000110B, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x0000110F, 0x20243100, 0x7571000D, 0x45007469, 0x56434558, 0x52452045, 0x46000A52
    .WORD 0x204B524F, 0x0A525245, 0x49415700, 0x52452054, 0x00000A52, 0x00000000, 0x00000000, 0x00000000
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

; /etc/logo.txt, 769 bytes
    .ASCIIZ "/etc/logo.txt"
    .SPACE 110
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
    .WORD 0x3D3D3D3D, 0x3D3D3D48, 0x3D3D3D3D, 0x4F423D3D, 0x4E49544F, 0x3D3D3D47, 0x3D3D3D3D, 0x483D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x480A483D, 0x20202020, 0x20202020, 0x48202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202048, 0x20202020, 0x20202020, 0x20482020, 0x20202020, 0x20202020
    .WORD 0x20204020, 0x3D480A48, 0x3D3D3D3D, 0x3D3D3D3D, 0x20483D3D, 0x20202020, 0x20202020, 0x48202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x3D3D4820, 0x3D3D3D3D, 0x3D3D3D3D, 0x483D3D3D, 0x2020480A
    .WORD 0x20202040, 0x20202020, 0x20204820, 0x20202020, 0x20202024, 0x20482020, 0x20202020, 0x20202420
    .WORD 0x20202020, 0x20202048, 0x20202020, 0x20202020, 0x0A482020, 0x3D3D3D48, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D48, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D483D, 0x3D3D3D3D, 0x3D3D3D3D, 0x483D3D3D, 0x3D3D3D3D
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

; /etc/motd, 16 bytes
    .ASCIIZ "/etc/motd"
    .SPACE 114
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

; /lib/libc.inc, 45409 bytes
    .ASCIIZ "/lib/libc.inc"
    .SPACE 110
    .ASCIIZ "00000130541"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (45409 bytes, padded to 45568)
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
    .WORD 0x575F5359, 0x50544941, 0x202C4449, 0x2E0A3631, 0x20555145, 0x5F535953, 0x49444B4D, 0x20202C52
    .WORD 0x0A373120, 0x5551452E, 0x53595320, 0x444D525F, 0x202C5249, 0x38312020, 0x51452E0A, 0x59532055
    .WORD 0x4E555F53, 0x4B4E494C, 0x3120202C, 0x2E0A0A39, 0x20555145, 0x4F445453, 0x465F5455, 0x31202C44
    .WORD 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x65726944, 0x7320746E, 0x63757274
    .WORD 0x65727574, 0x616D2820, 0x65686374, 0x656B2073, 0x6C656E72, 0x66656420, 0x74696E69, 0x296E6F69
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x51452E0A, 0x54442055, 0x4745525F, 0x2020202C
    .WORD 0x20202020, 0x2E0A3120, 0x20555145, 0x445F5444, 0x202C5249, 0x20202020, 0x32202020, 0x452E0A0A
    .WORD 0x44205551, 0x4E455249, 0x4E495F54, 0x2C45444F, 0x0A302020, 0x5551452E, 0x52494420, 0x5F544E45
    .WORD 0x455A4953, 0x2020202C, 0x452E0A34, 0x44205551, 0x4E455249, 0x59545F54, 0x202C4550, 0x0A382020
    .WORD 0x5551452E, 0x52494420, 0x5F544E45, 0x454D414E, 0x2020202C, 0x2E0A3231, 0x20555145, 0x45524944
    .WORD 0x535F544E, 0x4F455A49, 0x37202C46, 0x3B0A0A36, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x6E65704F, 0x616C6620, 0x3B0A7367
    .WORD 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3B0A0A3D, 0x63634120, 0x20737365, 0x65646F6D, 0x73616D20, 0x452E0A6B, 0x4F205551, 0x4343415F
    .WORD 0x45444F4D, 0x7830202C, 0x0A0A3033, 0x6341203B, 0x73736563, 0x646F6D20, 0x2E0A7365, 0x20555145
    .WORD 0x44525F4F, 0x594C4E4F, 0x3020202C, 0x0A303078, 0x5551452E, 0x575F4F20, 0x4C4E4F52, 0x20202C59
    .WORD 0x30317830, 0x51452E0A, 0x5F4F2055, 0x52574452, 0x2020202C, 0x32783020, 0x3B0A0A30, 0x6C694620
    .WORD 0x72632065, 0x69746165, 0x2F206E6F, 0x68656220, 0x6F697661, 0x6C662072, 0x0A736761, 0x5551452E
    .WORD 0x435F4F20, 0x54414552, 0x20202C45, 0x31307830, 0x51452E0A, 0x5F4F2055, 0x4C435845, 0x2020202C
    .WORD 0x30783020, 0x452E0A32, 0x4F205551, 0x5552545F, 0x202C434E, 0x78302020, 0x2E0A3430, 0x20555145
    .WORD 0x50415F4F, 0x444E4550, 0x3020202C, 0x0A383078, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x203B0A3D, 0x6174735F, 0x2D207472, 0x6F725020, 0x6D617267, 0x746E6520, 0x70207972, 0x746E696F
    .WORD 0x49203B0A, 0x20203A4E, 0x63677261, 0x20746120, 0x5D50535B, 0x7261202C, 0x61207667, 0x535B2074
    .WORD 0x5D342B50, 0x4F203B0A, 0x203A5455, 0x6576654E, 0x65722072, 0x6E727574, 0x202D2073, 0x6C6C6163
    .WORD 0x59532073, 0x58455F53, 0x77205449, 0x20687469, 0x6E69616D, 0x72207327, 0x72757465, 0x6176206E
    .WORD 0x0A65756C, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x6174735F, 0x0A3A7472, 0x20202020
    .WORD 0x2057444C, 0x5B203152, 0x205D5053, 0x20202020, 0x20202020, 0x61203B20, 0x0A636772, 0x20202020
    .WORD 0x20444441, 0x53203252, 0x20342050, 0x20202020, 0x20202020, 0x61203B20, 0x0A766772, 0x20202020
    .WORD 0x5220494C, 0x20302033, 0x20202020, 0x20202020, 0x20202020, 0x65203B20, 0x2070766E, 0x554E203D
    .WORD 0x200A4C4C, 0x50202020, 0x20485355, 0x200A3152, 0x50202020, 0x20485355, 0x200A3252, 0x50202020
    .WORD 0x20485355, 0x200A3352, 0x3B202020, 0x696E4920, 0x6C616974, 0x20657A69, 0x20656874, 0x6F6C6C61
    .WORD 0x6F746163, 0x6D282072, 0x20747375, 0x74206F64, 0x20736968, 0x73726966, 0x0A292174, 0x20202020
    .WORD 0x4C4C4143, 0x6C616D20, 0x5F636F6C, 0x74696E69, 0x2020200A, 0x504F5020, 0x33522020, 0x2020200A
    .WORD 0x504F5020, 0x32522020, 0x2020200A, 0x504F5020, 0x31522020, 0x2020200A, 0x65443B20, 0x20677562
    .WORD 0x20200A32, 0x4C422020, 0x69616D20, 0x2020206E, 0x20202020, 0x20202020, 0x3B202020, 0x6C616320
    .WORD 0x616D206C, 0x6C206E69, 0x20706F6F, 0x736C202D, 0x74616320, 0x68636520, 0x7465206F, 0x20200A63
    .WORD 0x443B2020, 0x67756265, 0x200A3220, 0x4C202020, 0x31522049, 0x200A3020, 0x50202020, 0x20485355
    .WORD 0x20203152, 0x20202020, 0x20202020, 0x20202020, 0x7865203B, 0x30207469, 0x73202D20, 0x65636375
    .WORD 0x31207373, 0x65202D20, 0x726F7272, 0x2020200A, 0x20494C20, 0x31203152, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x20747570, 0x73206F74, 0x7065656C, 0x206F7320, 0x65726170, 0x7720746E
    .WORD 0x70746961, 0x63206469, 0x77206E61, 0x0A6B726F, 0x20202020, 0x20435653, 0x5F535953, 0x45454C53
    .WORD 0x20200A50, 0x443B2020, 0x67756265, 0x200A3220, 0x50202020, 0x2020504F, 0x200A3152, 0x203B2020
    .WORD 0x5220494C, 0x0A312031, 0x20202020, 0x20435653, 0x5F535953, 0x54495845, 0x3D3B0A0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x73747570, 0x57202D20, 0x65746972, 0x6C756E20, 0x65742D6C
    .WORD 0x6E696D72, 0x64657461, 0x72747320, 0x20676E69, 0x73206F74, 0x756F6474, 0x203B0A74, 0x203A4E49
    .WORD 0x20315220, 0x7473203D, 0x676E6972, 0x696F7020, 0x7265746E, 0x4F203B0A, 0x203A5455, 0x3D203152
    .WORD 0x74796220, 0x77207365, 0x74746972, 0x6F206E65, 0x72652072, 0x20726F72, 0x65646F63, 0x3D3D3B0A
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x7475700A, 0x200A3A73, 0x50202020, 0x20485355, 0x200A524C
    .WORD 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x4D202020, 0x5220564F
    .WORD 0x31522038, 0x20202020, 0x20202020, 0x20202020, 0x6153203B, 0x73206576, 0x6E697274, 0x6F702067
    .WORD 0x65746E69, 0x20200A72, 0x4C422020, 0x72747320, 0x206E656C, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x74654720, 0x72747320, 0x20676E69, 0x676E656C, 0x200A6874, 0x4D202020, 0x5220564F, 0x31522039
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x6153203B, 0x6C206576, 0x74676E65, 0x20200A68, 0x494C2020
    .WORD 0x20315220, 0x4F445453, 0x465F5455, 0x20200A44, 0x4F4D2020, 0x32522056, 0x20385220, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x66754220, 0x20726566, 0x7473203D, 0x676E6972, 0x2020200A, 0x564F4D20
    .WORD 0x20335220, 0x20203952, 0x20202020, 0x20202020, 0x203B2020, 0x6E756F43, 0x203D2074, 0x676E656C
    .WORD 0x200A6874, 0x53202020, 0x53204356, 0x575F5359, 0x45544952, 0x2020200A, 0x494C3B20, 0x31522020
    .WORD 0x20303120, 0x20202020, 0x20202020, 0x20202020, 0x654E203B, 0x6E696C77, 0x68632065, 0x63617261
    .WORD 0x0A726574, 0x20202020, 0x204C423B, 0x74757020, 0x72616863, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x69725720, 0x6E206574, 0x696C7765, 0x200A656E, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020
    .WORD 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x70203B0A, 0x68637475, 0x2D207261, 0x69725720, 0x73206574, 0x6C676E69
    .WORD 0x68632065, 0x63617261, 0x20726574, 0x73206F74, 0x756F6474, 0x203B0A74, 0x203A4E49, 0x20315220
    .WORD 0x6863203D, 0x63617261, 0x0A726574, 0x554F203B, 0x52203A54, 0x203D2031, 0x65747962, 0x72772073
    .WORD 0x65747469, 0x3128206E, 0x726F2029, 0x72726520, 0x6320726F, 0x0A65646F, 0x3D3D3D3B, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x0A3D3D3D, 0x63747570, 0x3A726168, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x53555020, 0x38522048, 0x2020200A, 0x20494C20, 0x63203852, 0x75625F68, 0x20200A66, 0x54532020
    .WORD 0x31522042, 0x38525B20, 0x2020205D, 0x20202020, 0x3B202020, 0x6F745320, 0x63206572, 0x20726168
    .WORD 0x73206E69, 0x69746174, 0x75622063, 0x72656666, 0x2020200A, 0x20494C20, 0x53203152, 0x554F4454
    .WORD 0x44465F54, 0x2020200A, 0x564F4D20, 0x20325220, 0x200A3852, 0x4C202020, 0x33522049, 0x200A3120
    .WORD 0x53202020, 0x53204356, 0x575F5359, 0x45544952, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020
    .WORD 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D
    .WORD 0x7473203B, 0x6E656C72, 0x43202D20, 0x75636C61, 0x6574616C, 0x72747320, 0x20676E69, 0x676E656C
    .WORD 0x3B0A6874, 0x3A4E4920, 0x31522020, 0x73203D20, 0x6E697274, 0x6F702067, 0x65746E69, 0x203B0A72
    .WORD 0x3A54554F, 0x20315220, 0x656C203D, 0x6874676E, 0x78652820, 0x64756C63, 0x20676E69, 0x6C6C756E
    .WORD 0x72657420, 0x616E696D, 0x29726F74, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x7274730A
    .WORD 0x3A6E656C, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A
    .WORD 0x53555020, 0x39522048, 0x2020200A, 0x564F4D20, 0x20385220, 0x200A3152, 0x4C202020, 0x39522049
    .WORD 0x730A3020, 0x656C7274, 0x6F6C5F6E, 0x0A3A706F, 0x20202020, 0x2042444C, 0x5B203252, 0x2B203852
    .WORD 0x5D395220, 0x20202020, 0x52203B20, 0x20646165, 0x72616863, 0x65746361, 0x74612072, 0x72756320
    .WORD 0x746E6572, 0x66666F20, 0x0A746573, 0x20202020, 0x20504D43, 0x30203252, 0x2020200A, 0x51454220
    .WORD 0x72747320, 0x5F6E656C, 0x656E6F64, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x72636E49, 0x6E656D65, 0x6F632074, 0x65746E75, 0x20200A72, 0x20422020
    .WORD 0x6C727473, 0x6C5F6E65, 0x0A706F6F, 0x6C727473, 0x645F6E65, 0x3A656E6F, 0x2020200A, 0x564F4D20
    .WORD 0x20315220, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A
    .WORD 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x73203B0A, 0x6D637274, 0x202D2070, 0x706D6F43, 0x20657261, 0x206F7774, 0x69727473, 0x0A73676E
    .WORD 0x4E49203B, 0x5220203A, 0x203D2031, 0x69727473, 0x2C31676E, 0x20325220, 0x7473203D, 0x676E6972
    .WORD 0x203B0A32, 0x3A54554F, 0x20315220, 0x2031203D, 0x65206669, 0x6C617571, 0x2030202C, 0x64206669
    .WORD 0x65666669, 0x746E6572, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x7274730A, 0x3A706D63
    .WORD 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020
    .WORD 0x39522048, 0x2020200A, 0x53555020, 0x31522048, 0x20200A30, 0x4F4D2020, 0x38522056, 0x0A315220
    .WORD 0x20202020, 0x20564F4D, 0x52203952, 0x74730A32, 0x706D6372, 0x6F6F6C5F, 0x200A3A70, 0x4C202020
    .WORD 0x52204244, 0x5B203031, 0x205D3852, 0x20202020, 0x20202020, 0x6F4C203B, 0x63206461, 0x20726168
    .WORD 0x6D6F7266, 0x72747320, 0x31676E69, 0x2020200A, 0x42444C20, 0x20315220, 0x5D39525B, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x64616F4C, 0x61686320, 0x72662072, 0x73206D6F, 0x6E697274, 0x200A3267
    .WORD 0x43202020, 0x5220504D, 0x52203031, 0x20200A31, 0x4E422020, 0x74732045, 0x706D6372, 0x20656E5F
    .WORD 0x20202020, 0x3B202020, 0x73694D20, 0x6374616D, 0x6F662068, 0x0A646E75, 0x20202020, 0x20504D43
    .WORD 0x20303152, 0x20200A30, 0x45422020, 0x74732051, 0x706D6372, 0x2071655F, 0x20202020, 0x3B202020
    .WORD 0x746F4220, 0x74732068, 0x676E6972, 0x6E652073, 0x20646564, 0x73207461, 0x20656D61, 0x656D6974
    .WORD 0x2020200A, 0x44444120, 0x20385220, 0x31203852, 0x20202020, 0x20202020, 0x203B2020, 0x61766441
    .WORD 0x2065636E, 0x68746F62, 0x696F7020, 0x7265746E, 0x20200A73, 0x44412020, 0x39522044, 0x20395220
    .WORD 0x20200A31, 0x20422020, 0x63727473, 0x6C5F706D, 0x0A706F6F, 0x63727473, 0x655F706D, 0x200A3A71
    .WORD 0x4C202020, 0x31522049, 0x200A3120, 0x42202020, 0x72747320, 0x5F706D63, 0x656E6F64, 0x7274730A
    .WORD 0x5F706D63, 0x0A3A656E, 0x20202020, 0x5220494C, 0x0A302031, 0x63727473, 0x645F706D, 0x3A656E6F
    .WORD 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50
    .WORD 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3B0A3D3D, 0x6D656D20, 0x20797063, 0x6F43202D, 0x6D207970, 0x726F6D65, 0x6C622079
    .WORD 0x0A6B636F, 0x4E49203B, 0x5220203A, 0x203D2031, 0x74736564, 0x3252202C, 0x73203D20, 0x202C6372
    .WORD 0x3D203352, 0x756F6320, 0x3B0A746E, 0x54554F20, 0x3152203A, 0x64203D20, 0x20747365, 0x646E6528
    .WORD 0x736F7020, 0x6F697469, 0x3B0A296E, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x6D0A3D3D, 0x70636D65
    .WORD 0x200A3A79, 0x50202020, 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020
    .WORD 0x20485355, 0x200A3952, 0x50202020, 0x20485355, 0x0A303152, 0x20202020, 0x20564F4D, 0x52203852
    .WORD 0x20200A31, 0x4F4D2020, 0x39522056, 0x0A325220, 0x20202020, 0x20564F4D, 0x20303152, 0x6D0A3352
    .WORD 0x70636D65, 0x6F6C5F79, 0x0A3A706F, 0x20202020, 0x20504D43, 0x20303152, 0x20200A30, 0x45422020
    .WORD 0x656D2051, 0x7970636D, 0x6E6F645F, 0x20200A65, 0x444C2020, 0x31522042, 0x39525B20, 0x2020205D
    .WORD 0x20202020, 0x3B202020, 0x61655220, 0x79622064, 0x66206574, 0x206D6F72, 0x72756F73, 0x200A6563
    .WORD 0x53202020, 0x52204254, 0x525B2031, 0x20205D38, 0x20202020, 0x20202020, 0x7257203B, 0x20657469
    .WORD 0x65747962, 0x206F7420, 0x74736564, 0x74616E69, 0x0A6E6F69, 0x20202020, 0x20444441, 0x52203852
    .WORD 0x20312038, 0x20202020, 0x20202020, 0x41203B20, 0x6E617664, 0x62206563, 0x2068746F, 0x6E696F70
    .WORD 0x73726574, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x2020200A, 0x42555320, 0x30315220
    .WORD 0x30315220, 0x20203120, 0x20202020, 0x203B2020, 0x72636544, 0x6E656D65, 0x6F632074, 0x65746E75
    .WORD 0x20200A72, 0x20422020, 0x636D656D, 0x6C5F7970, 0x0A706F6F, 0x636D656D, 0x645F7970, 0x3A656E6F
    .WORD 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3852, 0x50202020, 0x5220504F, 0x200A3031, 0x50202020
    .WORD 0x5220504F, 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020
    .WORD 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x6D203B0A, 0x65736D65, 0x202D2074
    .WORD 0x6C6C6946, 0x6D656D20, 0x2079726F, 0x68746977, 0x6E6F6320, 0x6E617473, 0x79622074, 0x3B0A6574
    .WORD 0x3A4E4920, 0x31522020, 0x64203D20, 0x2C747365, 0x20325220, 0x6176203D, 0x2C65756C, 0x20335220
    .WORD 0x6F63203D, 0x0A746E75, 0x554F203B, 0x52203A54, 0x203D2031, 0x74736564, 0x6E652820, 0x6F702064
    .WORD 0x69746973, 0x0A296E6F, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x736D656D, 0x0A3A7465
    .WORD 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x48535550
    .WORD 0x0A395220, 0x20202020, 0x48535550, 0x30315220, 0x2020200A, 0x564F4D20, 0x20385220, 0x200A3152
    .WORD 0x4D202020, 0x5220564F, 0x32522039, 0x2020200A, 0x564F4D20, 0x30315220, 0x0A335220, 0x736D656D
    .WORD 0x6C5F7465, 0x3A706F6F, 0x2020200A, 0x504D4320, 0x30315220, 0x200A3020, 0x42202020, 0x6D205145
    .WORD 0x65736D65, 0x6F645F74, 0x200A656E, 0x53202020, 0x52204254, 0x525B2039, 0x20205D38, 0x20202020
    .WORD 0x20202020, 0x7453203B, 0x2065726F, 0x756C6176, 0x74612065, 0x72756320, 0x746E6572, 0x736F7020
    .WORD 0x6F697469, 0x20200A6E, 0x44412020, 0x38522044, 0x20385220, 0x20202031, 0x20202020, 0x3B202020
    .WORD 0x76644120, 0x65636E61, 0x696F7020, 0x7265746E, 0x2020200A, 0x42555320, 0x30315220, 0x30315220
    .WORD 0x20203120, 0x20202020, 0x203B2020, 0x72636544, 0x6E656D65, 0x6F632074, 0x65746E75, 0x20200A72
    .WORD 0x20422020, 0x736D656D, 0x6C5F7465, 0x0A706F6F, 0x736D656D, 0x645F7465, 0x3A656E6F, 0x2020200A
    .WORD 0x564F4D20, 0x20315220, 0x200A3852, 0x50202020, 0x5220504F, 0x200A3031, 0x50202020, 0x5220504F
    .WORD 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x77203B0A, 0x65746972, 0x2C646628, 0x66756220
    .WORD 0x656C202C, 0x3B0A296E, 0x49203B0A, 0x3B0A3A4E, 0x52202020, 0x203D2031, 0x3B0A6466, 0x52202020
    .WORD 0x203D2032, 0x66667562, 0x3B0A7265, 0x52202020, 0x203D2033, 0x676E656C, 0x3B0A6874, 0x4F203B0A
    .WORD 0x0A3A5455, 0x2020203B, 0x3D203152, 0x74796220, 0x77207365, 0x74746972, 0x2F206E65, 0x72726520
    .WORD 0x3B0A6F6E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x770A2D2D, 0x65746972, 0x20200A3A, 0x56532020
    .WORD 0x59532043, 0x52575F53, 0x0A455449, 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x203B0A2D, 0x64616572, 0x2C646628, 0x66756220, 0x656C202C, 0x3B0A296E, 0x49203B0A
    .WORD 0x3B0A3A4E, 0x52202020, 0x203D2031, 0x3B0A6466, 0x52202020, 0x203D2032, 0x66667562, 0x3B0A7265
    .WORD 0x52202020, 0x203D2033, 0x676E656C, 0x3B0A6874, 0x4F203B0A, 0x0A3A5455, 0x2020203B, 0x3D203152
    .WORD 0x74796220, 0x72207365, 0x0A646165, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x64616572
    .WORD 0x20200A3A, 0x56532020, 0x59532043, 0x45525F53, 0x200A4441, 0x52202020, 0x0A0A5445, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F203B0A, 0x286E6570, 0x68746170, 0x6C66202C, 0x29736761
    .WORD 0x3B0A3B0A, 0x3A4E4920, 0x20203B0A, 0x20315220, 0x6170203D, 0x3B0A6874, 0x52202020, 0x203D2032
    .WORD 0x67616C66, 0x0A3B0A73, 0x554F203B, 0x3B0A3A54, 0x52202020, 0x203D2031, 0x3B0A6466, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x6F0A2D2D, 0x3A6E6570, 0x2020200A, 0x43565320, 0x53595320, 0x45504F5F
    .WORD 0x20200A4E, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6C63203B
    .WORD 0x2865736F, 0x0A296466, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x736F6C63, 0x200A3A65
    .WORD 0x53202020, 0x53204356, 0x435F5359, 0x45534F4C, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x69646B6D, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6B6D0A2D, 0x3A726964, 0x2020200A, 0x43565320, 0x53595320, 0x444B4D5F, 0x200A5249, 0x52202020
    .WORD 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6D72203B, 0x0A726964, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x69646D72, 0x200A3A72, 0x53202020, 0x53204356, 0x525F5359
    .WORD 0x5249444D, 0x2020200A, 0x54455220, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x75203B0A
    .WORD 0x6E696C6E, 0x6170286B, 0x20296874, 0x2D3B0A20, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6E750A2D
    .WORD 0x6B6E696C, 0x20200A3A, 0x56532020, 0x59532043, 0x4E555F53, 0x4B4E494C, 0x2020200A, 0x54455220
    .WORD 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6B726F66, 0x3B0A2928, 0x70203B0A
    .WORD 0x6E657261, 0x3B0A3A74, 0x52202020, 0x203D2031, 0x6C696863, 0x69702064, 0x0A3B0A64, 0x6863203B
    .WORD 0x3A646C69, 0x20203B0A, 0x20315220, 0x0A30203D, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x6B726F66, 0x20200A3A, 0x56532020, 0x59532043, 0x4F465F53, 0x200A4B52, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x65203B0A, 0x76636578, 0x61702865, 0x202C6874
    .WORD 0x76677261, 0x6E65202C, 0x0A297076, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x63657865
    .WORD 0x0A3A6576, 0x20202020, 0x20435653, 0x5F535953, 0x43455845, 0x200A4556, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x77203B0A, 0x70746961, 0x70286469, 0x732C6469
    .WORD 0x75746174, 0x3B0A2973, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x770A2D2D, 0x70746961, 0x0A3A6469
    .WORD 0x20202020, 0x20435653, 0x5F535953, 0x54494157, 0x0A444950, 0x20202020, 0x0A544552, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x65656C73, 0x696D2870, 0x73696C6C, 0x6E6F6365
    .WORD 0x0A297364, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x65656C73, 0x200A3A70, 0x53202020
    .WORD 0x53204356, 0x535F5359, 0x5045454C, 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x69786520, 0x74732874, 0x73757461, 0x0A3B0A29, 0x656E203B, 0x20726576
    .WORD 0x75746572, 0x0A736E72, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x74697865, 0x20200A3A
    .WORD 0x56532020, 0x59532043, 0x58455F53, 0x0A0A5449, 0x74697865, 0x6E61685F, 0x200A3A67, 0x42202020
    .WORD 0x69786520, 0x61685F74, 0x0A0A676E, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x4D203B0A
    .WORD 0x524F4D45, 0x414D2059, 0x4547414E, 0x544E454D, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x59524556, 0x4D495320, 0x20454C50
    .WORD 0x4F4D454D, 0x41205952, 0x434F4C4C, 0x524F5441, 0x3B0A3B0A, 0x69685420, 0x73692073, 0x6D206120
    .WORD 0x6D696E69, 0x6D206C61, 0x6F6C6C61, 0x72662F63, 0x69206565, 0x656C706D, 0x746E656D, 0x6F697461
    .WORD 0x6874206E, 0x0A3A7461, 0x2E31203B, 0x65735520, 0x20612073, 0x65786966, 0x72612064, 0x20796172
    .WORD 0x74206F74, 0x6B636172, 0x6D656D20, 0x2079726F, 0x636F6C62, 0x3B0A736B, 0x202E3220, 0x73656F44
    .WORD 0x544F4E20, 0x616F6320, 0x6373656C, 0x6D282065, 0x65677265, 0x6A646120, 0x6E656361, 0x72662074
    .WORD 0x62206565, 0x6B636F6C, 0x3B0A2973, 0x202E3320, 0x73656F44, 0x544F4E20, 0x6C707320, 0x62207469
    .WORD 0x6B636F6C, 0x75282073, 0x20736573, 0x69746E65, 0x62206572, 0x6B636F6C, 0x2D736120, 0x0A297369
    .WORD 0x2E34203B, 0x65735520, 0x69662073, 0x2D747372, 0x20746966, 0x72616573, 0x28206863, 0x646E6966
    .WORD 0x69662073, 0x20747372, 0x636F6C62, 0x6874206B, 0x73277461, 0x67696220, 0x6F6E6520, 0x29686775
    .WORD 0x35203B0A, 0x7355202E, 0x73207365, 0x206B7262, 0x63737973, 0x206C6C61, 0x67206F74, 0x6D207465
    .WORD 0x2065726F, 0x6F6D656D, 0x66207972, 0x206D6F72, 0x6E72656B, 0x3B0A6C65, 0x54203B0A, 0x65646172
    .WORD 0x66666F2D, 0x3B0A3A73, 0x56202B20, 0x20797265, 0x706D6973, 0x6120656C, 0x6520646E, 0x20797361
    .WORD 0x75206F74, 0x7265646E, 0x6E617473, 0x203B0A64, 0x7250202B, 0x63696465, 0x6C626174, 0x656D2065
    .WORD 0x79726F6D, 0x61737520, 0x28206567, 0x65786966, 0x61742064, 0x29656C62, 0x2B203B0A, 0x206F4E20
    .WORD 0x706D6F63, 0x2078656C, 0x6B6E696C, 0x6C206465, 0x20747369, 0x616E616D, 0x656D6567, 0x3B0A746E
    .WORD 0x4D202D20, 0x726F6D65, 0x72662079, 0x656D6761, 0x7461746E, 0x206E6F69, 0x6E616328, 0x6D207427
    .WORD 0x65677265, 0x65726620, 0x6C622065, 0x736B636F, 0x203B0A29, 0x6157202D, 0x64657473, 0x61707320
    .WORD 0x28206563, 0x276E6163, 0x70732074, 0x2074696C, 0x6772616C, 0x6C622065, 0x736B636F, 0x203B0A29
    .WORD 0x694C202D, 0x6574696D, 0x6F742064, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x6F6C6C61, 0x69746163
    .WORD 0x0A736E6F, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x43203B0A, 0x54534E4F, 0x53544E41, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x452E0A0A, 0x4D205551, 0x425F5841, 0x4B434F4C, 0x34202C53, 0x20202038, 0x20202020, 0x614D203B
    .WORD 0x756D6978, 0x756E206D, 0x7265626D, 0x20666F20, 0x636F6C62, 0x7720736B, 0x61632065, 0x7274206E
    .WORD 0x0A6B6361, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x6E616328, 0x61207427, 0x636F6C6C, 0x20657461, 0x65726F6D, 0x61687420, 0x3233206E, 0x6D697420
    .WORD 0x77207365, 0x6F687469, 0x66207475, 0x69656572, 0x0A29676E, 0x42203B0A, 0x6B636F6C, 0x73656420
    .WORD 0x70697263, 0x20726F74, 0x7366666F, 0x20737465, 0x63616528, 0x6C622068, 0x206B636F, 0x6465656E
    .WORD 0x68742073, 0x20657365, 0x61762033, 0x7365756C, 0x452E0A29, 0x42205551, 0x4B434F4C, 0x4444415F
    .WORD 0x20202C52, 0x20202030, 0x20202020, 0x664F203B, 0x74657366, 0x7473203A, 0x69747261, 0x6120676E
    .WORD 0x65726464, 0x6F207373, 0x68742066, 0x6C622065, 0x206B636F, 0x62203428, 0x73657479, 0x452E0A29
    .WORD 0x42205551, 0x4B434F4C, 0x5A49535F, 0x20202C45, 0x20202034, 0x20202020, 0x664F203B, 0x74657366
    .WORD 0x6973203A, 0x6F20657A, 0x68742066, 0x6C622065, 0x206B636F, 0x62206E69, 0x73657479, 0x20342820
    .WORD 0x65747962, 0x20202973, 0x51452E0A, 0x4C422055, 0x5F4B434F, 0x44455355, 0x3820202C, 0x20202020
    .WORD 0x3B202020, 0x66664F20, 0x3A746573, 0x663D3020, 0x2C656572, 0x753D3120, 0x20646573, 0x62203428
    .WORD 0x73657479, 0x452E0A29, 0x42205551, 0x4B434F4C, 0x5345445F, 0x20202C43, 0x20203231, 0x20202020
    .WORD 0x6F54203B, 0x206C6174, 0x657A6973, 0x20666F20, 0x20656E6F, 0x636F6C62, 0x6564206B, 0x69726373
    .WORD 0x726F7470, 0x20332820, 0x64726F77, 0x203D2073, 0x62203231, 0x73657479, 0x3B0A0A29, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x54414420, 0x45532041, 0x4F495443, 0x202D204E, 0x20656854
    .WORD 0x636F6C62, 0x6174206B, 0x20656C62, 0x6E203B0A, 0x616D726F, 0x20796C6C, 0x6F6D656D, 0x62207972
    .WORD 0x6B636F6C, 0x65672073, 0x65722074, 0x65726573, 0x20646576, 0x6D6F7266, 0x41454820, 0x68772050
    .WORD 0x20686369, 0x6C207369, 0x7461636F, 0x61206465, 0x61642074, 0x73206174, 0x656D6765, 0x0A20746E
    .WORD 0x6170203B, 0x28206567, 0x65676170, 0x64646120, 0x73736572, 0x65707320, 0x69666963, 0x61206465
    .WORD 0x73752073, 0x645F7265, 0x5F617461, 0x20296176, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6C620A0A, 0x5F6B636F, 0x6C626174, 0x200A3A65, 0x3B202020, 0x69685420, 0x73692073, 0x206E6120
    .WORD 0x61727261, 0x666F2079, 0x58414D20, 0x4F4C425F, 0x20534B43, 0x63736564, 0x74706972, 0x2E73726F
    .WORD 0x2020200A, 0x45203B20, 0x20686361, 0x63736564, 0x74706972, 0x6820726F, 0x203A7361, 0x72646461
    .WORD 0x2C737365, 0x7A697320, 0x75202C65, 0x5F646573, 0x67616C66, 0x2020200A, 0x54203B20, 0x6C61746F
    .WORD 0x7A697320, 0x4D203A65, 0x425F5841, 0x4B434F4C, 0x202A2053, 0x62203231, 0x73657479, 0x2020200A
    .WORD 0x50532E20, 0x20454341, 0x5F58414D, 0x434F4C42, 0x2A20534B, 0x4F4C4220, 0x445F4B43, 0x0A435345
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6D203B0A, 0x6F6C6C61, 0x69732863, 0x0A29657A
    .WORD 0x203B0A3B, 0x6F6C6C41, 0x65746163, 0x656D2073, 0x79726F6D, 0x6F726620, 0x6874206D, 0x65682065
    .WORD 0x0A2E7061, 0x203B0A3B, 0x20776F48, 0x77207469, 0x736B726F, 0x203B0A3A, 0x41202E31, 0x6E67696C
    .WORD 0x65687420, 0x71657220, 0x74736575, 0x73206465, 0x20657A69, 0x38206F74, 0x74796220, 0x28207365
    .WORD 0x656B616D, 0x656D2073, 0x79726F6D, 0x6E616D20, 0x6D656761, 0x20746E65, 0x69736165, 0x0A297265
    .WORD 0x2E32203B, 0x61655320, 0x20686372, 0x20656874, 0x636F6C62, 0x6174206B, 0x20656C62, 0x20726F66
    .WORD 0x72662061, 0x62206565, 0x6B636F6C, 0x61687420, 0x20732774, 0x6772616C, 0x6E652065, 0x6867756F
    .WORD 0x33203B0A, 0x6649202E, 0x756F6620, 0x202C646E, 0x6B72616D, 0x20746920, 0x75207361, 0x20646573
    .WORD 0x20646E61, 0x75746572, 0x69206E72, 0x61207374, 0x65726464, 0x3B0A7373, 0x202E3420, 0x6E206649
    .WORD 0x6620746F, 0x646E756F, 0x7361202C, 0x6874206B, 0x656B2065, 0x6C656E72, 0x726F6620, 0x726F6D20
    .WORD 0x656D2065, 0x79726F6D, 0x61697620, 0x72627320, 0x7973206B, 0x6C616373, 0x203B0A6C, 0x41202E35
    .WORD 0x74206464, 0x6E206568, 0x6D207765, 0x726F6D65, 0x6F742079, 0x65687420, 0x6F6C6220, 0x74206B63
    .WORD 0x656C6261, 0x646E6120, 0x74657220, 0x206E7275, 0x3B0A7469, 0x49203B0A, 0x7475706E, 0x5220203A
    .WORD 0x203D2031, 0x657A6973, 0x206E6920, 0x65747962, 0x65282073, 0x2C2E672E, 0x30303120, 0x203B0A29
    .WORD 0x7074754F, 0x203A7475, 0x3D203152, 0x696F7020, 0x7265746E, 0x206F7420, 0x6F6C6C61, 0x65746163
    .WORD 0x656D2064, 0x79726F6D, 0x726F2820, 0x69203020, 0x61662066, 0x64656C69, 0x2D3B0A29, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x616D0A2D, 0x636F6C6C, 0x20200A3A, 0x203B2020, 0x65766153, 0x67657220
    .WORD 0x65747369, 0x77207372, 0x6C6C2765, 0x65737520, 0x6F732820, 0x20657720, 0x276E6F64, 0x6F632074
    .WORD 0x70757272, 0x61632074, 0x72656C6C, 0x76207327, 0x65756C61, 0x200A2973, 0x50202020, 0x20485355
    .WORD 0x2020524C, 0x20202020, 0x20202020, 0x20202020, 0x53203B20, 0x20657661, 0x75746572, 0x61206E72
    .WORD 0x65726464, 0x200A7373, 0x0A202020, 0x20202020, 0x7453203B, 0x31207065, 0x6C41203A, 0x206E6769
    .WORD 0x657A6973, 0x206F7420, 0x746C756D, 0x656C7069, 0x20666F20, 0x79622038, 0x0A736574, 0x20202020
    .WORD 0x6857203B, 0x4D203F79, 0x20796E61, 0x73555043, 0x726F7720, 0x6166206B, 0x72657473, 0x74697720
    .WORD 0x6C612068, 0x656E6769, 0x656D2064, 0x79726F6D, 0x2020200A, 0x45203B20, 0x706D6178, 0x203A656C
    .WORD 0x657A6973, 0x3030313D, 0x2020200A, 0x20203B20, 0x44444120, 0x20315220, 0x20202037, 0x203E2D20
    .WORD 0x0A373031, 0x20202020, 0x2020203B, 0x20444E41, 0x46467830, 0x46464646, 0x2D203846, 0x3031203E
    .WORD 0x6D282034, 0x69746C75, 0x20656C70, 0x3820666F, 0x20200A29, 0x44412020, 0x31522044, 0x20315220
    .WORD 0x20202037, 0x20202020, 0x20202020, 0x6441203B, 0x20372064, 0x72206F74, 0x646E756F, 0x0A707520
    .WORD 0x20202020, 0x2020494C, 0x30203252, 0x46464678, 0x46464646, 0x200A2038, 0x41202020, 0x5220444E
    .WORD 0x31522031, 0x20325220, 0x20202020, 0x20202020, 0x43203B20, 0x7261656C, 0x776F6C20, 0x33207265
    .WORD 0x74696220, 0x6D282073, 0x20656B61, 0x746C756D, 0x656C7069, 0x20666F20, 0x200A2938, 0x4D202020
    .WORD 0x5220564F, 0x31522035, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2035, 0x67696C61
    .WORD 0x2064656E, 0x657A6973, 0x2E652820, 0x202C2E67, 0x29343031, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x70657453, 0x203A3220, 0x72616553, 0x66206863, 0x6120726F, 0x65726620, 0x6C622065, 0x206B636F
    .WORD 0x74206E69, 0x74206568, 0x656C6261, 0x2020200A, 0x57203B20, 0x6C6C2765, 0x65737520, 0x20345220
    .WORD 0x69207361, 0x7865646E, 0x746E6920, 0x6C62206F, 0x5F6B636F, 0x6C626174, 0x30282065, 0x206F7420
    .WORD 0x5F58414D, 0x434F4C42, 0x312D534B, 0x20200A29, 0x494C2020, 0x20345220, 0x20202030, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x7453203B, 0x20747261, 0x66207461, 0x74737269, 0x6F6C6220, 0x28206B63
    .WORD 0x65646E69, 0x29302078, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x6F6F6C5F, 0x200A3A70, 0x3B202020
    .WORD 0x65684320, 0x69206B63, 0x65772066, 0x20657627, 0x72616573, 0x64656863, 0x6C6C6120, 0x6F6C6220
    .WORD 0x0A736B63, 0x20202020, 0x20504D43, 0x4D203452, 0x425F5841, 0x4B434F4C, 0x20202053, 0x203B2020
    .WORD 0x706D6F43, 0x20657261, 0x65646E69, 0x69772078, 0x6D206874, 0x6D697861, 0x200A6D75, 0x42202020
    .WORD 0x6D204547, 0x6F6C6C61, 0x62735F63, 0x20206B72, 0x20202020, 0x49203B20, 0x6E692066, 0x20786564
    .WORD 0x4D203D3E, 0x425F5841, 0x4B434F4C, 0x6E202C53, 0x7266206F, 0x62206565, 0x6B636F6C, 0x756F6620
    .WORD 0x200A646E, 0x0A202020, 0x20202020, 0x6143203B, 0x6C75636C, 0x20657461, 0x72646461, 0x20737365
    .WORD 0x7420666F, 0x20736968, 0x636F6C62, 0x2073276B, 0x63736564, 0x74706972, 0x200A726F, 0x3B202020
    .WORD 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x28202B20, 0x65646E69, 0x202A2078, 0x63736564, 0x74706972
    .WORD 0x735F726F, 0x29657A69, 0x2020200A, 0x20494C20, 0x62203252, 0x6B636F6C, 0x6261745F, 0x2020656C
    .WORD 0x3B202020, 0x20325220, 0x6162203D, 0x61206573, 0x65726464, 0x6F207373, 0x6C622066, 0x5F6B636F
    .WORD 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x434F4C42, 0x45445F4B, 0x20204353, 0x20202020
    .WORD 0x3352203B, 0x73203D20, 0x20657A69, 0x6F20666F, 0x6420656E, 0x72637365, 0x6F747069, 0x31282072
    .WORD 0x79622032, 0x29736574, 0x2020200A, 0x4C554D20, 0x20335220, 0x52203452, 0x20202033, 0x20202020
    .WORD 0x3B202020, 0x20335220, 0x6E69203D, 0x20786564, 0x3231202A, 0x666F2820, 0x74657366, 0x746E6920
    .WORD 0x6174206F, 0x29656C62, 0x2020200A, 0x44444120, 0x20325220, 0x52203252, 0x20202033, 0x20202020
    .WORD 0x3B202020, 0x20325220, 0x6226203D, 0x6B636F6C, 0x646E695B, 0x0A5D7865, 0x20202020, 0x2020200A
    .WORD 0x43203B20, 0x6B636568, 0x20666920, 0x73696874, 0x6F6C6220, 0x69206B63, 0x72662073, 0x28206565
    .WORD 0x44455355, 0x616C6620, 0x203D2067, 0x200A2930, 0x4C202020, 0x52205744, 0x525B2033, 0x202B2032
    .WORD 0x434F4C42, 0x53555F4B, 0x205D4445, 0x4C203B20, 0x2064616F, 0x20656874, 0x6F6C6226, 0x695B6B63
    .WORD 0x7865646E, 0x6C622E5D, 0x5F6B636F, 0x64657375, 0x616C6620, 0x20200A67, 0x4D432020, 0x33522050
    .WORD 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x7349203B, 0x20746920, 0x66282030, 0x29656572
    .WORD 0x20200A3F, 0x4E422020, 0x616D2045, 0x636F6C6C, 0x78656E5F, 0x20202074, 0x20202020, 0x6649203B
    .WORD 0x746F6E20, 0x65726620, 0x75282065, 0x29646573, 0x6B73202C, 0x74207069, 0x656E206F, 0x62207478
    .WORD 0x6B636F6C, 0x2020200A, 0x20200A20, 0x203B2020, 0x65657266, 0x6843202E, 0x206B6365, 0x74206669
    .WORD 0x20736968, 0x636F6C62, 0x7369206B, 0x72616C20, 0x65206567, 0x67756F6E, 0x6F662068, 0x756F2072
    .WORD 0x65722072, 0x73657571, 0x20200A74, 0x444C2020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C
    .WORD 0x5A49535F, 0x20205D45, 0x6F4C203B, 0x74206461, 0x62206568, 0x6B636F6C, 0x7A697320, 0x20200A65
    .WORD 0x4D432020, 0x33522050, 0x20355220, 0x20202020, 0x20202020, 0x20202020, 0x7349203B, 0x6F6C6220
    .WORD 0x73206B63, 0x20657A69, 0x72203D3E, 0x65757165, 0x64657473, 0x7A697320, 0x200A3F65, 0x42202020
    .WORD 0x6D204547, 0x6F6C6C61, 0x6F665F63, 0x20646E75, 0x20202020, 0x59203B20, 0x20217365, 0x66206557
    .WORD 0x646E756F, 0x73206120, 0x61746975, 0x20656C62, 0x636F6C62, 0x20200A6B, 0x6D0A2020, 0x6F6C6C61
    .WORD 0x656E5F63, 0x0A3A7478, 0x20202020, 0x6854203B, 0x62207369, 0x6B636F6C, 0x20736920, 0x68746965
    .WORD 0x75207265, 0x20646573, 0x7420726F, 0x73206F6F, 0x6C6C616D, 0x7274202C, 0x656E2079, 0x6F207478
    .WORD 0x200A656E, 0x41202020, 0x52204444, 0x34522034, 0x20203120, 0x20202020, 0x20202020, 0x49203B20
    .WORD 0x6572636E, 0x746E656D, 0x646E6920, 0x74207865, 0x6863206F, 0x206B6365, 0x7478656E, 0x6F6C6220
    .WORD 0x200A6B63, 0x42202020, 0x6C616D20, 0x5F636F6C, 0x706F6F6C, 0x20202020, 0x20202020, 0x47203B20
    .WORD 0x6162206F, 0x74206B63, 0x7473206F, 0x20747261, 0x6C20666F, 0x0A706F6F, 0x6C616D0A, 0x5F636F6C
    .WORD 0x6E756F66, 0x200A3A64, 0x3B202020, 0x65745320, 0x3A332070, 0x20655720, 0x6E756F66, 0x20612064
    .WORD 0x65657266, 0x6F6C6220, 0x6C206B63, 0x65677261, 0x6F6E6520, 0x21686775, 0x2020200A, 0x52203B20
    .WORD 0x203D2032, 0x6E696F70, 0x20726574, 0x74206F74, 0x62206568, 0x6B636F6C, 0x73656420, 0x70697263
    .WORD 0x0A726F74, 0x20202020, 0x3352203B, 0x62203D20, 0x6B636F6C, 0x7A697320, 0x77282065, 0x6F642065
    .WORD 0x2074276E, 0x20657375, 0x66207469, 0x7320726F, 0x74696C70, 0x676E6974, 0x206E6920, 0x73696874
    .WORD 0x6D697320, 0x20656C70, 0x73726576, 0x296E6F69, 0x2020200A, 0x20200A20, 0x203B2020, 0x6B72614D
    .WORD 0x65687420, 0x6F6C6220, 0x61206B63, 0x73752073, 0x28206465, 0x44455355, 0x616C6620, 0x203D2067
    .WORD 0x200A2931, 0x4C202020, 0x33522049, 0x20203120, 0x20202020, 0x20202020, 0x20202020, 0x52203B20
    .WORD 0x203D2033, 0x75282031, 0x29646573, 0x2020200A, 0x57545320, 0x20335220, 0x2032525B, 0x4C42202B
    .WORD 0x5F4B434F, 0x44455355, 0x3B20205D, 0x6F745320, 0x31206572, 0x206E6920, 0x20656874, 0x44455355
    .WORD 0x65696620, 0x200A646C, 0x0A202020, 0x20202020, 0x6547203B, 0x68742074, 0x6C622065, 0x276B636F
    .WORD 0x74732073, 0x69747261, 0x6120676E, 0x65726464, 0x61207373, 0x7220646E, 0x72757465, 0x7469206E
    .WORD 0x2020200A, 0x57444C20, 0x20315220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x52444441, 0x3B20205D
    .WORD 0x20315220, 0x6461203D, 0x73657264, 0x666F2073, 0x69687420, 0x6C622073, 0x0A6B636F, 0x20202020
    .WORD 0x616D2042, 0x636F6C6C, 0x6E6F645F, 0x20202065, 0x20202020, 0x203B2020, 0x706D754A, 0x206F7420
    .WORD 0x61656C63, 0x2070756E, 0x20646E61, 0x75746572, 0x0A0A6E72, 0x6C6C616D, 0x735F636F, 0x3A6B7262
    .WORD 0x2020200A, 0x53203B20, 0x20706574, 0x4E203A34, 0x7266206F, 0x62206565, 0x6B636F6C, 0x756F6620
    .WORD 0x6920646E, 0x6174206E, 0x0A656C62, 0x20202020, 0x7341203B, 0x6874206B, 0x656B2065, 0x6C656E72
    .WORD 0x726F6620, 0x726F6D20, 0x656D2065, 0x79726F6D, 0x69737520, 0x7320676E, 0x206B7262, 0x63737973
    .WORD 0x0A6C6C61, 0x20202020, 0x2020200A, 0x52203B20, 0x6C612035, 0x64616572, 0x61682079, 0x68742073
    .WORD 0x6C612065, 0x656E6769, 0x69732064, 0x7720657A, 0x656E2065, 0x200A6465, 0x4D202020, 0x5220564F
    .WORD 0x35522031, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2031, 0x657A6973, 0x206F7420
    .WORD 0x6F6C6C61, 0x65746163, 0x2020200A, 0x43565320, 0x53595320, 0x5242535F, 0x2020204B, 0x20202020
    .WORD 0x3B202020, 0x6C614320, 0x656B206C, 0x6C656E72, 0x6273203A, 0x73286B72, 0x29657A69, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x63656843, 0x6669206B, 0x72627320, 0x6166206B, 0x64656C69, 0x65722820
    .WORD 0x6E727574, 0x312D2073, 0x20726F20, 0x6E6F2030, 0x72726520, 0x0A29726F, 0x20202020, 0x20504D43
    .WORD 0x30203152, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x20646944, 0x6B726273, 0x74657220
    .WORD 0x206E7275, 0x726F2030, 0x67656E20, 0x76697461, 0x200A3F65, 0x42202020, 0x6D20544C, 0x6F6C6C61
    .WORD 0x72655F63, 0x20726F72, 0x20202020, 0x49203B20, 0x72652066, 0x2C726F72, 0x74657220, 0x206E7275
    .WORD 0x4C4C554E, 0x2020200A, 0x20200A20, 0x203B2020, 0x70657453, 0x203A3520, 0x6B726273, 0x63757320
    .WORD 0x64656563, 0x202C6465, 0x68206577, 0x20657661, 0x2077656E, 0x6F6D656D, 0x61207972, 0x64612074
    .WORD 0x73657264, 0x6E692073, 0x0A315220, 0x20202020, 0x6F4E203B, 0x65772077, 0x65656E20, 0x6F742064
    .WORD 0x64646120, 0x69687420, 0x656E2073, 0x6C622077, 0x206B636F, 0x6F206F74, 0x74207275, 0x656C6261
    .WORD 0x2020200A, 0x20200A20, 0x203B2020, 0x646E6946, 0x206E6120, 0x74706D65, 0x6C732079, 0x6920746F
    .WORD 0x6874206E, 0x6C622065, 0x206B636F, 0x6C626174, 0x20200A65, 0x494C2020, 0x20345220, 0x20202030
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x7453203B, 0x20747261, 0x66207461, 0x74737269, 0x6F6C6220
    .WORD 0x200A6B63, 0x0A202020, 0x6C6C616D, 0x615F636F, 0x0A3A6464, 0x20202020, 0x6843203B, 0x206B6365
    .WORD 0x77206669, 0x65762765, 0x61657320, 0x65686372, 0x6C612064, 0x6C62206C, 0x736B636F, 0x2020200A
    .WORD 0x504D4320, 0x20345220, 0x5F58414D, 0x434F4C42, 0x2020534B, 0x0A202020, 0x20202020, 0x20454742
    .WORD 0x6C6C616D, 0x655F636F, 0x726F7272, 0x20202020, 0x203B2020, 0x65206F4E, 0x7974706D, 0x6F6C7320
    .WORD 0x28202174, 0x756F6873, 0x276E646C, 0x61682074, 0x6E657070, 0x20200A29, 0x200A2020, 0x3B202020
    .WORD 0x74654720, 0x73656420, 0x70697263, 0x20726F74, 0x72646461, 0x0A737365, 0x20202020, 0x5220494C
    .WORD 0x6C622032, 0x5F6B636F, 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x434F4C42, 0x45445F4B
    .WORD 0x200A4353, 0x4D202020, 0x52204C55, 0x34522033, 0x0A335220, 0x20202020, 0x20444441, 0x52203252
    .WORD 0x33522032, 0x20202020, 0x20202020, 0x6226203B, 0x6B636F6C, 0x646E695B, 0x34527865, 0x20200A5D
    .WORD 0x200A2020, 0x3B202020, 0x65684320, 0x69206B63, 0x68742066, 0x73207369, 0x20746F6C, 0x66207369
    .WORD 0x20656572, 0x45535528, 0x6C662044, 0x3D206761, 0x0A293020, 0x20202020, 0x2057444C, 0x5B203352
    .WORD 0x2B203252, 0x4F4C4220, 0x555F4B43, 0x5D444553, 0x2020200A, 0x504D4320, 0x20335220, 0x20200A30
    .WORD 0x45422020, 0x616D2051, 0x636F6C6C, 0x6464615F, 0x756F665F, 0x2020646E, 0x6F46203B, 0x20646E75
    .WORD 0x65206E61, 0x7974706D, 0x6F6C7320, 0x200A2174, 0x0A202020, 0x20202020, 0x6C53203B, 0x6920746F
    .WORD 0x73752073, 0x202C6465, 0x20797274, 0x7478656E, 0x656E6F20, 0x2020200A, 0x44444120, 0x20345220
    .WORD 0x31203452, 0x2020200A, 0x6D204220, 0x6F6C6C61, 0x64615F63, 0x6D0A0A64, 0x6F6C6C61, 0x64615F63
    .WORD 0x6F665F64, 0x3A646E75, 0x2020200A, 0x57203B20, 0x6F662065, 0x20646E75, 0x65206E61, 0x7974706D
    .WORD 0x6F6C7320, 0x74612074, 0x0A325220, 0x20202020, 0x7453203B, 0x2065726F, 0x20656874, 0x2077656E
    .WORD 0x636F6C62, 0x2073276B, 0x6F666E69, 0x74616D72, 0x0A6E6F69, 0x20202020, 0x2020200A, 0x53203B20
    .WORD 0x65726F74, 0x65687420, 0x64646120, 0x73736572, 0x31522820, 0x6F726620, 0x6273206D, 0x0A296B72
    .WORD 0x20202020, 0x20575453, 0x5B203152, 0x2B203252, 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x3B202020
    .WORD 0x6F6C6220, 0x612E6B63, 0x65726464, 0x3D207373, 0x64646120, 0x73736572, 0x6F726620, 0x6273206D
    .WORD 0x200A6B72, 0x0A202020, 0x20202020, 0x7453203B, 0x2065726F, 0x20656874, 0x657A6973, 0x35522820
    .WORD 0x61203D20, 0x6E67696C, 0x73206465, 0x29657A69, 0x2020200A, 0x57545320, 0x20355220, 0x2032525B
    .WORD 0x4C42202B, 0x5F4B434F, 0x455A4953, 0x2020205D, 0x6C62203B, 0x2E6B636F, 0x657A6973, 0x73203D20
    .WORD 0x0A657A69, 0x20202020, 0x2020200A, 0x4D203B20, 0x206B7261, 0x75207361, 0x20646573, 0x45535528
    .WORD 0x203D2044, 0x200A2931, 0x4C202020, 0x33522049, 0x200A3120, 0x53202020, 0x52205754, 0x525B2033
    .WORD 0x202B2032, 0x434F4C42, 0x53555F4B, 0x205D4445, 0x203B2020, 0x636F6C62, 0x73752E6B, 0x3D206465
    .WORD 0x200A3120, 0x0A202020, 0x20202020, 0x3152203B, 0x726C6120, 0x79646165, 0x73616820, 0x65687420
    .WORD 0x64646120, 0x73736572, 0x6F726620, 0x6273206D, 0x202C6B72, 0x6A206F73, 0x20747375, 0x75746572
    .WORD 0x69206E72, 0x20200A74, 0x20422020, 0x6C6C616D, 0x645F636F, 0x0A656E6F, 0x6C616D0A, 0x5F636F6C
    .WORD 0x6F727265, 0x200A3A72, 0x3B202020, 0x6D6F5320, 0x69687465, 0x7720676E, 0x20746E65, 0x6E6F7277
    .WORD 0x202D2067, 0x75746572, 0x4E206E72, 0x204C4C55, 0x0A293028, 0x20202020, 0x5220494C, 0x0A302031
    .WORD 0x6C616D0A, 0x5F636F6C, 0x656E6F64, 0x20200A3A, 0x4F502020, 0x524C2050, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6552203B, 0x726F7473, 0x65722065, 0x6E727574, 0x64646120, 0x73736572
    .WORD 0x2020200A, 0x54455220, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x74655220
    .WORD 0x206E7275, 0x63206F74, 0x656C6C61, 0x69772072, 0x52206874, 0x203D2031, 0x6E696F70, 0x20726574
    .WORD 0x4E20726F, 0x0A4C4C55, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x66203B0A, 0x28656572
    .WORD 0x29727470, 0x3B0A3B0A, 0x65724620, 0x70207365, 0x69766572, 0x6C73756F, 0x6C612079, 0x61636F6C
    .WORD 0x20646574, 0x6F6D656D, 0x0A2E7972, 0x203B0A3B, 0x20776F48, 0x77207469, 0x736B726F, 0x203B0A3A
    .WORD 0x46202E31, 0x20646E69, 0x20656874, 0x636F6C62, 0x6564206B, 0x69726373, 0x726F7470, 0x726F6620
    .WORD 0x69687420, 0x64612073, 0x73657264, 0x203B0A73, 0x4D202E32, 0x206B7261, 0x61207469, 0x72662073
    .WORD 0x28206565, 0x44455355, 0x30203D20, 0x203B0A29, 0x4D202E33, 0x726F6D65, 0x73692079, 0x776F6E20
    .WORD 0x61766120, 0x62616C69, 0x6620656C, 0x6620726F, 0x72757475, 0x616D2065, 0x636F6C6C, 0x6C616320
    .WORD 0x3B0A736C, 0x4E203B0A, 0x3A65746F, 0x69685420, 0x69732073, 0x656C706D, 0x72657620, 0x6E6F6973
    .WORD 0x656F6420, 0x4F4E2073, 0x6F632054, 0x73656C61, 0x61206563, 0x63616A64, 0x20746E65, 0x65657266
    .WORD 0x6F6C6220, 0x21736B63, 0x20203B0A, 0x20202020, 0x206F5320, 0x67617266, 0x746E656D, 0x6F697461
    .WORD 0x6163206E, 0x636F206E, 0x20727563, 0x7265766F, 0x6D697420, 0x3B0A2E65, 0x49203B0A, 0x7475706E
    .WORD 0x5220203A, 0x203D2031, 0x6E696F70, 0x20726574, 0x6D206F74, 0x726F6D65, 0x6F742079, 0x65726620
    .WORD 0x66282065, 0x206D6F72, 0x6C6C616D, 0x0A29636F, 0x754F203B, 0x74757074, 0x6F4E203A, 0x6E696874
    .WORD 0x2D3B0A67, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72660A2D, 0x0A3A6565, 0x20202020, 0x6153203B
    .WORD 0x72206576, 0x73696765, 0x73726574, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x70657453, 0x203A3120, 0x63656843, 0x6669206B, 0x696F7020, 0x7265746E, 0x20736920
    .WORD 0x4C4C554E, 0x2020200A, 0x504D4320, 0x20315220, 0x20202030, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x20734920, 0x3D203152, 0x3F30203D, 0x2020200A, 0x51454220, 0x65726620, 0x6F645F65, 0x2020656E
    .WORD 0x20202020, 0x3B202020, 0x20664920, 0x4C4C554E, 0x6F6E202C, 0x6E696874, 0x6F742067, 0x65726620
    .WORD 0x6A202C65, 0x20747375, 0x75746572, 0x200A6E72, 0x0A202020, 0x20202020, 0x7453203B, 0x32207065
    .WORD 0x6553203A, 0x68637261, 0x65687420, 0x6F6C6220, 0x74206B63, 0x656C6261, 0x726F6620, 0x69687420
    .WORD 0x64612073, 0x73657264, 0x20200A73, 0x494C2020, 0x20345220, 0x20202030, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x7453203B, 0x20747261, 0x66207461, 0x74737269, 0x6F6C6220, 0x200A6B63, 0x0A202020
    .WORD 0x65657266, 0x6F6F6C5F, 0x200A3A70, 0x3B202020, 0x65684320, 0x69206B63, 0x65772066, 0x20657627
    .WORD 0x72616573, 0x64656863, 0x6C6C6120, 0x6F6C6220, 0x0A736B63, 0x20202020, 0x20504D43, 0x4D203452
    .WORD 0x425F5841, 0x4B434F4C, 0x20200A53, 0x47422020, 0x72662045, 0x645F6565, 0x20656E6F, 0x20202020
    .WORD 0x20202020, 0x6F4E203B, 0x6F662074, 0x20646E75, 0x6769202D, 0x65726F6E, 0x6F632820, 0x20646C75
    .WORD 0x69206562, 0x6C61766E, 0x70206469, 0x746E696F, 0x0A297265, 0x20202020, 0x2020200A, 0x47203B20
    .WORD 0x64207465, 0x72637365, 0x6F747069, 0x64612072, 0x73657264, 0x20200A73, 0x494C2020, 0x20325220
    .WORD 0x636F6C62, 0x61745F6B, 0x0A656C62, 0x20202020, 0x5220494C, 0x4C422033, 0x5F4B434F, 0x43534544
    .WORD 0x20202020, 0x203B2020, 0x676E656C, 0x6F206874, 0x6E6F2066, 0x6C622065, 0x206B636F, 0x63736564
    .WORD 0x74706972, 0x200A726F, 0x4D202020, 0x52204C55, 0x34522033, 0x20335220, 0x20202020, 0x20202020
    .WORD 0x72203B20, 0x6C622034, 0x206B636F, 0x0A786469, 0x20202020, 0x20444441, 0x52203252, 0x33522032
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x3D203252, 0x6C622620, 0x5B6B636F, 0x200A5D69, 0x0A202020
    .WORD 0x20202020, 0x6843203B, 0x206B6365, 0x74206669, 0x20736968, 0x636F6C62, 0x2073276B, 0x72646461
    .WORD 0x20737365, 0x6374616D, 0x20736568, 0x20656874, 0x6E696F70, 0x0A726574, 0x20202020, 0x2057444C
    .WORD 0x5B203352, 0x2B203252, 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x203B2020, 0x3D203352, 0x62262020
    .WORD 0x6B636F6C, 0x2E5D695B, 0x636F6C62, 0x6461206B, 0x73657264, 0x20200A73, 0x4D432020, 0x33522050
    .WORD 0x20315220, 0x20202020, 0x20202020, 0x20202020, 0x7349203B, 0x69687420, 0x756F2073, 0x6C622072
    .WORD 0x3F6B636F, 0x2020200A, 0x51454220, 0x65726620, 0x6F665F65, 0x20646E75, 0x20202020, 0x3B202020
    .WORD 0x73655920, 0x6577202C, 0x756F6620, 0x6920646E, 0x200A2174, 0x0A202020, 0x20202020, 0x6F4E203B
    .WORD 0x68742074, 0x62207369, 0x6B636F6C, 0x7274202C, 0x656E2079, 0x200A7478, 0x41202020, 0x52204444
    .WORD 0x34522034, 0x200A3120, 0x42202020, 0x65726620, 0x6F6C5F65, 0x0A0A706F, 0x65657266, 0x756F665F
    .WORD 0x0A3A646E, 0x20202020, 0x7453203B, 0x33207065, 0x6557203A, 0x756F6620, 0x7420646E, 0x62206568
    .WORD 0x6B636F6C, 0x73656420, 0x70697263, 0x20726F74, 0x52207461, 0x20200A32, 0x203B2020, 0x6B72614D
    .WORD 0x20746920, 0x66207361, 0x20656572, 0x6D206F73, 0x6F6C6C61, 0x61632063, 0x7375206E, 0x74692065
    .WORD 0x61676120, 0x200A6E69, 0x0A202020, 0x20202020, 0x5220494C, 0x20302033, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x3D203352, 0x28203020, 0x65657266, 0x20200A29, 0x54532020, 0x33522057
    .WORD 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4553555F, 0x20205D44, 0x6226203B, 0x6B636F6C, 0x2E5D695B
    .WORD 0x64657375, 0x30203D20, 0x2020200A, 0x20200A20, 0x203B2020, 0x45544F4E, 0x6557203A, 0x206F6420
    .WORD 0x20544F4E, 0x61656C63, 0x68742072, 0x64612065, 0x73657264, 0x726F2073, 0x7A697320, 0x20200A65
    .WORD 0x203B2020, 0x79656854, 0x61747320, 0x6E692079, 0x65687420, 0x62617420, 0x6120656C, 0x7720646E
    .WORD 0x206C6C69, 0x6F206562, 0x77726576, 0x74746972, 0x77206E65, 0x206E6568, 0x73756572, 0x200A6465
    .WORD 0x0A202020, 0x65657266, 0x6E6F645F, 0x200A3A65, 0x3B202020, 0x656C4320, 0x75206E61, 0x6E612070
    .WORD 0x65722064, 0x6E727574, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6D203B0A, 0x6F6C6C61, 0x6E695F63, 0x2D207469, 0x696E4920
    .WORD 0x6C616974, 0x20657A69, 0x20656874, 0x6F6D656D, 0x61207972, 0x636F6C6C, 0x726F7461, 0x3B0A3B0A
    .WORD 0x656C4320, 0x20737261, 0x20656874, 0x69746E65, 0x62206572, 0x6B636F6C, 0x62617420, 0x7320656C
    .WORD 0x6C61206F, 0x6C62206C, 0x736B636F, 0x65726120, 0x72616D20, 0x2064656B, 0x66207361, 0x0A656572
    .WORD 0x6853203B, 0x646C756F, 0x20656220, 0x6C6C6163, 0x6F206465, 0x2065636E, 0x73207461, 0x65747379
    .WORD 0x7473206D, 0x75747261, 0x65622070, 0x65726F66, 0x69737520, 0x6D20676E, 0x6F6C6C61, 0x2D3B0A63
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x616D0A2D, 0x636F6C6C, 0x696E695F, 0x200A3A74, 0x3B202020
    .WORD 0x76615320, 0x65722065, 0x74736967, 0x0A737265, 0x20202020, 0x48535550, 0x20524C20, 0x200A2020
    .WORD 0x3B202020, 0x65745320, 0x3A312070, 0x656C4320, 0x74207261, 0x65206568, 0x7269746E, 0x6C622065
    .WORD 0x206B636F, 0x6C626174, 0x20200A65, 0x203B2020, 0x20746553, 0x206C6C61, 0x65747962, 0x6E692073
    .WORD 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x206F7420, 0x20200A30, 0x494C2020, 0x20315220, 0x636F6C62
    .WORD 0x61745F6B, 0x20656C62, 0x20202020, 0x3152203B, 0x73203D20, 0x74726174, 0x64646120, 0x73736572
    .WORD 0x20666F20, 0x6C626174, 0x20200A65, 0x494C2020, 0x20335220, 0x5F58414D, 0x434F4C42, 0x2A20534B
    .WORD 0x4F4C4220, 0x445F4B43, 0x20435345, 0x52203B20, 0x203D2033, 0x61746F74, 0x7962206C, 0x20736574
    .WORD 0x63206F74, 0x7261656C, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x696E695F, 0x6F6C5F74, 0x0A3A706F
    .WORD 0x20202020, 0x20504D43, 0x30203352, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x65766148
    .WORD 0x20657720, 0x61656C63, 0x20646572, 0x206C6C61, 0x65747962, 0x200A3F73, 0x42202020, 0x6D205145
    .WORD 0x6F6C6C61, 0x6E695F63, 0x645F7469, 0x20656E6F, 0x59203B20, 0x202C7365, 0x72276577, 0x6F642065
    .WORD 0x200A656E, 0x0A202020, 0x20202020, 0x5220494C, 0x20302032, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x3D203252, 0x28203020, 0x756C6176, 0x6F742065, 0x69727720, 0x0A296574, 0x20202020
    .WORD 0x20425453, 0x5B203252, 0x205D3152, 0x20202020, 0x20202020, 0x203B2020, 0x726F7453, 0x20302065
    .WORD 0x63207461, 0x65727275, 0x6120746E, 0x65726464, 0x200A7373, 0x41202020, 0x52204444, 0x31522031
    .WORD 0x20203120, 0x20202020, 0x20202020, 0x4D203B20, 0x2065766F, 0x6E206F74, 0x20747865, 0x65747962
    .WORD 0x2020200A, 0x42555320, 0x20335220, 0x31203352, 0x20202020, 0x20202020, 0x3B202020, 0x63654420
    .WORD 0x656D6572, 0x6220746E, 0x20657479, 0x6E756F63, 0x0A726574, 0x20202020, 0x616D2042, 0x636F6C6C
    .WORD 0x696E695F, 0x6F6C5F74, 0x2020706F, 0x203B2020, 0x746E6F43, 0x65756E69, 0x2020200A, 0x616D0A20
    .WORD 0x636F6C6C, 0x696E695F, 0x6F645F74, 0x0A3A656E, 0x20202020, 0x6C43203B, 0x206E6165, 0x61207075
    .WORD 0x7220646E, 0x72757465, 0x20200A6E, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x3B0A0A0A
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x544E4920, 0x414E5245, 0x4548204C, 0x5245504C
    .WORD 0x3D3B0A53, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x43203B0A, 0x65766E6F, 0x69207472
    .WORD 0x6765746E, 0x69207265, 0x206F746E, 0x706D6574, 0x7261726F, 0x75622079, 0x72656666, 0x3B0A3B0A
    .WORD 0x20395220, 0x63203D20, 0x65727275, 0x7620746E, 0x65756C61, 0x52203B0A, 0x3D203031, 0x696F7020
    .WORD 0x7265746E, 0x206F7420, 0x7478656E, 0x65726620, 0x79622065, 0x69206574, 0x6574206E, 0x726F706D
    .WORD 0x20797261, 0x66667562, 0x3B0A7265, 0x31315220, 0x62203D20, 0x20657361, 0x202C3228, 0x202C3031
    .WORD 0x3120726F, 0x3B0A2936, 0x20345220, 0x6E203D20, 0x65626D75, 0x666F2072, 0x67696420, 0x20737469
    .WORD 0x726F7473, 0x3B0A6465, 0x45203B0A, 0x20686361, 0x69766964, 0x6E6F6973, 0x6F727020, 0x65637564
    .WORD 0x3B0A3A73, 0x20203B0A, 0x6F757120, 0x6E656974, 0x3D202074, 0x6C617620, 0x2F206575, 0x73616220
    .WORD 0x203B0A65, 0x65722020, 0x6E69616D, 0x20726564, 0x6176203D, 0x2065756C, 0x61622025, 0x3B0A6573
    .WORD 0x54203B0A, 0x72206568, 0x69616D65, 0x7265646E, 0x20736920, 0x20656874, 0x7478656E, 0x67696420
    .WORD 0x0A2E7469, 0x203B0A3B, 0x69676944, 0x61207374, 0x67206572, 0x72656E65, 0x64657461, 0x63616220
    .WORD 0x7261776B, 0x202C7364, 0x20726F66, 0x6D617865, 0x3A656C70, 0x3B0A3B0A, 0x31202020, 0x3B0A3332
    .WORD 0x66203B0A, 0x74737269, 0x6F727020, 0x65637564, 0x3B0A3A73, 0x20203B0A, 0x3B0A3320, 0x32202020
    .WORD 0x20203B0A, 0x3B0A3120, 0x73203B0A, 0x6874206F, 0x65742065, 0x726F706D, 0x20797261, 0x66667562
    .WORD 0x63207265, 0x61746E6F, 0x3A736E69, 0x3B0A3B0A, 0x22202020, 0x22313233, 0x3B0A3B0A, 0x65685420
    .WORD 0x706F6320, 0x6F6C2079, 0x6220706F, 0x776F6C65, 0x6C697720, 0x6572206C, 0x73726576, 0x74692065
    .WORD 0x746E6920, 0x3122206F, 0x2E223332, 0x3B0A3B0A, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6F746920, 0x6F635F61, 0x3B0A6572, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x3B0A7C20, 0x20202020, 0x20202020, 0x94E22020, 0x8094E28C, 0xE28094E2, 0x94E28094, 0x8094E280
    .WORD 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x94E2B494, 0x8094E280, 0xE28094E2, 0x94E28094
    .WORD 0x8094E280, 0xE28094E2, 0x94E28094, 0x8094E280, 0x0A9094E2, 0x2020203B, 0x20202020, 0xE2202020
    .WORD 0x20208294, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0xE2202020, 0x3B0A8294, 0x20202020
    .WORD 0x39522020, 0x76203D20, 0x65756C61, 0x20202020, 0x20202020, 0x52202020, 0x3D203031, 0x6D657420
    .WORD 0x0A5D5B70, 0x2020203B, 0x20202020, 0xE2202020, 0x20208294, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0xE2202020, 0x3B0A8294, 0x20202020, 0x20202020, 0x86E22020, 0x20202093, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x86E22020, 0x203B0A93, 0x20202020, 0x49442020, 0x4F4D2F56
    .WORD 0x20202044, 0x20202020, 0x20202020, 0x20202020, 0x42545320, 0x20203B0A, 0x20202020, 0x20202020
    .WORD 0x208294E2, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A8294E2, 0x2020203B
    .WORD 0x94E22020, 0x8094E28C, 0xE28094E2, 0x94E28094, 0xB494E280, 0xE28094E2, 0x94E28094, 0x8094E280
    .WORD 0x209094E2, 0x20202020, 0x20202020, 0x20202020, 0xE2202020, 0x3B0A8294, 0x20202020, 0x9386E220
    .WORD 0x20202020, 0x20202020, 0x9386E220, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x0A8294E2
    .WORD 0x3652203B, 0x6F75713D, 0x6E656974, 0x37522074, 0x6D65723D, 0x646E6961, 0x20207265, 0x20202020
    .WORD 0x8294E220, 0x20203B0A, 0xE2202020, 0x20208294, 0x20202020, 0xE2202020, 0x20208294, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x94E22020, 0x203B0A82, 0x20202020, 0x208294E2, 0x20202020, 0x20202020
    .WORD 0xE29494E2, 0x94E28094, 0x9286E280, 0x43534120, 0xE2204949, 0x94E28094, 0x8094E280, 0x2D8094E2
    .WORD 0x9894E22D, 0x20203B0A, 0xE2202020, 0x3B0A8294, 0x20202020, 0x9494E220, 0xE28094E2, 0x94E28094
    .WORD 0x8094E280, 0x209286E2, 0x66203952, 0x6E20726F, 0x20747865, 0x706F6F6C, 0x38523B0A, 0x65642020
    .WORD 0x6E697473, 0x6F697461, 0x6F70206E, 0x65746E69, 0x523B0A72, 0x63202039, 0x65727275, 0x6920746E
    .WORD 0x6765746E, 0x76207265, 0x65756C61, 0x31523B0A, 0x65742030, 0x726F706D, 0x2D797261, 0x66667562
    .WORD 0x70207265, 0x746E696F, 0x3B0A7265, 0x20313152, 0x65736162, 0x31523B0A, 0x69732032, 0x66206E67
    .WORD 0x0A67616C, 0x2034523B, 0x67696420, 0x63207469, 0x746E756F, 0x3B0A7265, 0x20203652, 0x746F7571
    .WORD 0x746E6569, 0x37523B0A, 0x65722020, 0x6E69616D, 0x0A726564, 0x2035523B, 0x72637320, 0x68637461
    .WORD 0x64202F20, 0x73697669, 0x3B0A726F, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x690A0A3D, 0x5F616F74, 0x65726F63, 0x20200A3A, 0x55502020
    .WORD 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A35, 0x55502020, 0x52204853, 0x20200A36
    .WORD 0x55502020, 0x52204853, 0x20200A37, 0x55502020, 0x52204853, 0x20200A38, 0x55502020, 0x52204853
    .WORD 0x20200A39, 0x55502020, 0x52204853, 0x200A3031, 0x50202020, 0x20485355, 0x0A313152, 0x20202020
    .WORD 0x48535550, 0x32315220, 0x200A0A20, 0x4D202020, 0x2020564F, 0x20203852, 0x20203152, 0x20202020
    .WORD 0x20202020, 0x6153203B, 0x64206576, 0x69747365, 0x6974616E, 0x200A6E6F, 0x4D202020, 0x2020564F
    .WORD 0x20203952, 0x20203252, 0x20202020, 0x20202020, 0x6F57203B, 0x6E696B72, 0x61762067, 0x0A65756C
    .WORD 0x20202020, 0x20564F4D, 0x31315220, 0x20335220, 0x20202020, 0x20202020, 0x42203B20, 0x0A657361
    .WORD 0x20202020, 0x20564F4D, 0x32315220, 0x20345220, 0x20202020, 0x20202020, 0x53203B20, 0x206E6769
    .WORD 0x67616C66, 0x2020200A, 0x41203B20, 0x636F6C6C, 0x20657461, 0x706D6574, 0x66756220, 0x20726566
    .WORD 0x7A697328, 0x61702065, 0x64657373, 0x206E6920, 0x0A293552, 0x20202020, 0x20425553, 0x20505320
    .WORD 0x52205053, 0x20200A35, 0x4F4D2020, 0x52202056, 0x53203031, 0x20202050, 0x20202020, 0x3B202020
    .WORD 0x6D655420, 0x75622070, 0x72656666, 0x696F7020, 0x7265746E, 0x200A200A, 0x50202020, 0x20485355
    .WORD 0x20203552, 0x20202020, 0x20202020, 0x20202020, 0x6173203B, 0x52206576, 0x6F662035, 0x72662072
    .WORD 0x20656D61, 0x7661656C, 0x20200A65, 0x55502020, 0x52204853, 0x20202038, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x76617320, 0x65722065, 0x746C7573, 0x66756220, 0x200A7265, 0x0A202020, 0x20202020
    .WORD 0x6843203B, 0x206B6365, 0x20726F66, 0x6E676973, 0x66692820, 0x67697320, 0x2064656E, 0x20646E61
    .WORD 0x6167656E, 0x65766974, 0x20200A29, 0x4D432020, 0x52202050, 0x31203231, 0x2020200A, 0x454E4220
    .WORD 0x74692020, 0x635F616F, 0x5F65726F, 0x69736E75, 0x64656E67, 0x2020200A, 0x20200A20, 0x4D432020
    .WORD 0x52202050, 0x0A302039, 0x20202020, 0x20454742, 0x6F746920, 0x6F635F61, 0x755F6572, 0x6769736E
    .WORD 0x0A64656E, 0x20202020, 0x2020200A, 0x4E203B20, 0x74616765, 0x20657669, 0x626D756E, 0x2D207265
    .WORD 0x64646120, 0x6E696D20, 0x73207375, 0x0A6E6769, 0x20202020, 0x2020494C, 0x20325220, 0x20203534
    .WORD 0x3B202020, 0x0A272D27, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B, 0x2020200A, 0x44444120
    .WORD 0x38522020, 0x20385220, 0x20200A31, 0x4F4E2020, 0x52202054, 0x39522039, 0x2020200A, 0x44444120
    .WORD 0x39522020, 0x20395220, 0x20200A31, 0x4E3B2020, 0x20204745, 0x20203952, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x614D203B, 0x7020656B, 0x7469736F, 0x0A657669, 0x20202020, 0x6F74690A, 0x6F635F61
    .WORD 0x755F6572, 0x6769736E, 0x3A64656E, 0x2020200A, 0x53203B20, 0x69636570, 0x63206C61, 0x3A657361
    .WORD 0x72657A20, 0x20200A6F, 0x4D432020, 0x52202050, 0x0A302039, 0x20202020, 0x20454E42, 0x6F746920
    .WORD 0x6F635F61, 0x635F6572, 0x65766E6F, 0x200A7472, 0x0A202020, 0x20202020, 0x2020494C, 0x20325220
    .WORD 0x20203834, 0x203B2020, 0x0A273027, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B, 0x2020200A
    .WORD 0x44444120, 0x38522020, 0x20385220, 0x20200A31, 0x494C2020, 0x52202020, 0x0A302032, 0x20202020
    .WORD 0x20425453, 0x20325220, 0x5D38525B, 0x2020200A, 0x20204220, 0x74692020, 0x635F616F, 0x5F65726F
    .WORD 0x696E6966, 0x0A0A6873, 0x616F7469, 0x726F635F, 0x6F635F65, 0x7265766E, 0x0A0A3A74, 0x20202020
    .WORD 0x2020494C, 0x30203452, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x3D203452
    .WORD 0x67696420, 0x63207469, 0x746E756F, 0x0A0A7265, 0x616F7469, 0x726F635F, 0x69645F65, 0x6F6F6C76
    .WORD 0x200A3A70, 0x3B202020, 0x2D2D2D20, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x20200A2D, 0x203B2020, 0x69766944, 0x63206564, 0x65727275, 0x7620746E, 0x65756C61
    .WORD 0x20796220, 0x65736162, 0x2020200A, 0x200A3B20, 0x3B202020, 0x20395220, 0x63203D20, 0x65727275
    .WORD 0x7620746E, 0x65756C61, 0x2020200A, 0x52203B20, 0x3D203131, 0x73616220, 0x20200A65, 0x0A3B2020
    .WORD 0x20202020, 0x6557203B, 0x65656E20, 0x6F742064, 0x65656B20, 0x39522070, 0x636E7520, 0x676E6168
    .WORD 0x66206465, 0x4D20726F, 0x202C444F, 0x75206F73, 0x52206573, 0x20200A35, 0x203B2020, 0x74207361
    .WORD 0x44206568, 0x73205649, 0x6372756F, 0x200A2E65, 0x3B202020, 0x2D2D2D20, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x20200A2D, 0x4F4D2020, 0x35522056, 0x0A395220
    .WORD 0x20202020, 0x3652203B, 0x71203D20, 0x69746F75, 0x0A746E65, 0x20202020, 0x20564944, 0x52203652
    .WORD 0x31522035, 0x20200A31, 0x203B2020, 0x3D203752, 0x6D657220, 0x646E6961, 0x200A7265, 0x4D202020
    .WORD 0x5220444F, 0x39522037, 0x31315220, 0x2020200A, 0x2D203B20, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x20202020, 0x6F43203B, 0x7265766E, 0x65722074
    .WORD 0x6E69616D, 0x20726564, 0x41206F74, 0x49494353, 0x2020200A, 0x200A3B20, 0x3B202020, 0x726F4620
    .WORD 0x73616220, 0x20322065, 0x20646E61, 0x0A3A3031, 0x20202020, 0x2020203B, 0x2E302020, 0x2D20392E
    .WORD 0x3027203E, 0x272E2E27, 0x200A2739, 0x3B202020, 0x2020200A, 0x46203B20, 0x6220726F, 0x20657361
    .WORD 0x0A3A3631, 0x20202020, 0x2020203B, 0x2E302020, 0x2020392E, 0x27203E2D, 0x2E2E2730, 0x0A273927
    .WORD 0x20202020, 0x2020203B, 0x30312020, 0x35312E2E, 0x203E2D20, 0x2E274127, 0x2746272E, 0x2020200A
    .WORD 0x2D203B20, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x20202020, 0x20504D43, 0x20313152, 0x200A3631, 0x42202020, 0x69205145, 0x5F616F74, 0x65726F63
    .WORD 0x7865685F, 0x6769645F, 0x200A7469, 0x3B202020, 0x73614220, 0x20322065, 0x6220726F, 0x20657361
    .WORD 0x200A3031, 0x41202020, 0x52204444, 0x37522037, 0x20383420, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x3027203B, 0x202B2027, 0x69676964, 0x20200A74, 0x20422020, 0x616F7469, 0x726F635F, 0x74735F65
    .WORD 0x0A65726F, 0x6F74690A, 0x6F635F61, 0x685F6572, 0x645F7865, 0x74696769, 0x20200A3A, 0x4D432020
    .WORD 0x37522050, 0x200A3920, 0x42202020, 0x69205447, 0x5F616F74, 0x65726F63, 0x7865685F, 0x74656C5F
    .WORD 0x0A726574, 0x20202020, 0x2E30203B, 0x200A392E, 0x41202020, 0x52204444, 0x37522037, 0x20383420
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x3027203B, 0x202B2027, 0x69676964, 0x20200A74, 0x20422020
    .WORD 0x616F7469, 0x726F635F, 0x74735F65, 0x0A65726F, 0x6F74690A, 0x6F635F61, 0x685F6572, 0x6C5F7865
    .WORD 0x65747465, 0x200A3A72, 0x3B202020, 0x2E303120, 0x0A35312E, 0x20202020, 0x20425553, 0x52203752
    .WORD 0x30312037, 0x2020200A, 0x44444120, 0x20375220, 0x36203752, 0x20202035, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x20274127, 0x6428202B, 0x74696769, 0x31202D20, 0x0A0A2930, 0x3D3D203B, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x6F745320
    .WORD 0x67206572, 0x72656E65, 0x64657461, 0x67696420, 0x3B0A7469, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x690A0A3D, 0x5F616F74, 0x65726F63
    .WORD 0x6F74735F, 0x0A3A6572, 0x20202020, 0x2020200A, 0x42545320, 0x20375220, 0x3031525B, 0x2020205D
    .WORD 0x31523B20, 0x73692030, 0x65687420, 0x6D657420, 0x61726F70, 0x622D7972, 0x65666675, 0x6F702072
    .WORD 0x65746E69, 0x0A0A2E72, 0x20202020, 0x20444441, 0x20303152, 0x20303152, 0x20200A31, 0x44412020
    .WORD 0x34522044, 0x20345220, 0x20202031, 0x203B2020, 0x20656E4F, 0x65726F6D, 0x67696420, 0x67207469
    .WORD 0x72656E65, 0x64657461, 0x20200A0A, 0x203B2020, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2020200A, 0x54203B20, 0x71206568, 0x69746F75, 0x20746E65
    .WORD 0x6F636562, 0x2073656D, 0x20656874, 0x756C6176, 0x6F662065, 0x68742072, 0x656E2065, 0x69207478
    .WORD 0x61726574, 0x6E6F6974, 0x20200A2E, 0x0A3B2020, 0x20202020, 0x7845203B, 0x6C706D61, 0x200A3A65
    .WORD 0x3B202020, 0x2020200A, 0x20203B20, 0x33323120, 0x31202F20, 0x203D2030, 0x200A3231, 0x3B202020
    .WORD 0x20202020, 0x2F203231, 0x20303120, 0x0A31203D, 0x20202020, 0x2020203B, 0x20312020, 0x3031202F
    .WORD 0x30203D20, 0x2020200A, 0x2D203B20, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x2020200A, 0x564F4D20, 0x20395220, 0x0A0A3652, 0x20202020, 0x6F43203B
    .WORD 0x6E69746E, 0x75206575, 0x6C69746E, 0x6F757120, 0x6E656974, 0x65622074, 0x656D6F63, 0x657A2073
    .WORD 0x200A6F72, 0x43202020, 0x5220504D, 0x0A302039, 0x20202020, 0x20454E42, 0x616F7469, 0x726F635F
    .WORD 0x69645F65, 0x6F6F6C76, 0x3B0A0A70, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x69676944, 0x61207374, 0x6E206572, 0x7320776F
    .WORD 0x65726F74, 0x61622064, 0x61776B63, 0x20736472, 0x74206E69, 0x6F706D65, 0x79726172, 0x66756220
    .WORD 0x2E726566, 0x74203B0A, 0x20706D65, 0x3322203D, 0x0A223132, 0x203B0A3B, 0x20303152, 0x6E696F70
    .WORD 0x6A207374, 0x20747375, 0x45544641, 0x68742052, 0x616C2065, 0x64207473, 0x74696769, 0x0A3B0A2E
    .WORD 0x6F4D203B, 0x62206576, 0x206B6361, 0x74206F74, 0x66206568, 0x6C616E69, 0x67696420, 0x0A3A7469
    .WORD 0x3D3D203B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A0A3D3D, 0x20202020, 0x20425553, 0x20303152, 0x20303152, 0x3B0A0A31, 0x3D3D3D20, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x79706F43
    .WORD 0x67696420, 0x20737469, 0x6D6F7266, 0x6D657420, 0x61726F70, 0x62207972, 0x65666675, 0x61622072
    .WORD 0x61776B63, 0x0A736472, 0x3D3D203B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A0A3D3D, 0x616F7469, 0x726F635F, 0x6F635F65, 0x0A3A7970, 0x20202020
    .WORD 0x20504D43, 0x30203452, 0x2020200A, 0x51454220, 0x6F746920, 0x6F635F61, 0x645F6572, 0x0A656E6F
    .WORD 0x20202020, 0x6552203B, 0x6C206461, 0x20747361, 0x656E6567, 0x65746172, 0x69642064, 0x0A746967
    .WORD 0x20202020, 0x2042444C, 0x5B203252, 0x5D303152, 0x2020200A, 0x57203B20, 0x65746972, 0x20746920
    .WORD 0x64206F74, 0x69747365, 0x6974616E, 0x200A6E6F, 0x53202020, 0x52204254, 0x525B2032, 0x200A5D38
    .WORD 0x41202020, 0x52204444, 0x38522038, 0x200A3120, 0x3B202020, 0x766F4D20, 0x61622065, 0x61776B63
    .WORD 0x20736472, 0x6F726874, 0x20686775, 0x706D6574, 0x7261726F, 0x75622079, 0x72656666, 0x2020200A
    .WORD 0x42555320, 0x30315220, 0x30315220, 0x200A3120, 0x3B202020, 0x656E4F20, 0x73656C20, 0x69642073
    .WORD 0x0A746967, 0x20202020, 0x20425553, 0x52203452, 0x0A312034, 0x20202020, 0x74692042, 0x635F616F
    .WORD 0x5F65726F, 0x79706F63, 0x74690A0A, 0x635F616F, 0x5F65726F, 0x656E6F64, 0x20200A3A, 0x494C2020
    .WORD 0x52202020, 0x0A302032, 0x20202020, 0x20425453, 0x20325220, 0x5D38525B, 0x20202020, 0x20202020
    .WORD 0x4E203B20, 0x206C6C75, 0x6D726574, 0x74616E69, 0x20200A65, 0x690A2020, 0x5F616F74, 0x65726F63
    .WORD 0x6E69665F, 0x3A687369, 0x2020200A, 0x504F5020, 0x31522020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x75746552, 0x6F206E72, 0x69676972, 0x206C616E, 0x6E696F70, 0x0A726574, 0x20202020
    .WORD 0x20504F50, 0x0A355220, 0x20202020, 0x6C43203B, 0x206E6165, 0x74207075, 0x20706D65, 0x66667562
    .WORD 0x200A7265, 0x41202020, 0x20204444, 0x53205053, 0x35522050, 0x2020200A, 0x20200A20, 0x4F502020
    .WORD 0x31522050, 0x20200A32, 0x4F502020, 0x31522050, 0x20200A31, 0x4F502020, 0x31522050, 0x20200A30
    .WORD 0x4F502020, 0x39522050, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A3752
    .WORD 0x50202020, 0x5220504F, 0x20200A36, 0x4F502020, 0x35522050, 0x2020200A, 0x504F5020, 0x0A524C20
    .WORD 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A2D2D2D, 0x7469203B, 0x645F616F, 0x2D206365, 0x63654420, 0x6C616D69, 0x6E6F6320, 0x73726576
    .WORD 0x206E6F69, 0x70617277, 0x0A726570, 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974
    .WORD 0x66756220, 0x0A726566, 0x3252203B, 0x73203D20, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72
    .WORD 0x75746552, 0x3A736E72, 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072
    .WORD 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6F74690A, 0x65645F61, 0x200A3A63, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020, 0x20202020
    .WORD 0x614D203B, 0x31312078, 0x67696420, 0x20737469, 0x6973202B, 0x2B206E67, 0x6C756E20, 0x203D206C
    .WORD 0x62203331, 0x73657479, 0x2020200A, 0x20494C20, 0x33522020, 0x20303120, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x65736142, 0x0A303120, 0x20202020, 0x2020494C, 0x20345220, 0x20202031, 0x20202020
    .WORD 0x20202020, 0x53203B20, 0x656E6769, 0x20200A64, 0x494C2020, 0x52202020, 0x33312035, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020
    .WORD 0x69204C4C, 0x5F616F74, 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52
    .WORD 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x616F7469, 0x7865685F, 0x48202D20, 0x64617865, 0x6D696365, 0x63206C61, 0x65766E6F
    .WORD 0x6F697372, 0x7277206E, 0x65707061, 0x0A3B0A72, 0x3152203B, 0x64203D20, 0x69747365, 0x6974616E
    .WORD 0x62206E6F, 0x65666675, 0x203B0A72, 0x3D203252, 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574
    .WORD 0x203B0A72, 0x75746552, 0x3A736E72, 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675
    .WORD 0x6F702072, 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6F74690A, 0x65685F61, 0x200A3A78, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020
    .WORD 0x20202020, 0x614D203B, 0x20382078, 0x69676964, 0x2B207374, 0x6C756E20, 0x203D206C, 0x79622039
    .WORD 0x0A736574, 0x20202020, 0x2020494C, 0x20335220, 0x20203631, 0x20202020, 0x20202020, 0x42203B20
    .WORD 0x20657361, 0x200A3631, 0x4C202020, 0x20202049, 0x30203452, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6E55203B, 0x6E676973, 0x28206465, 0x776F6873, 0x61722073, 0x69622077, 0x0A297374, 0x20202020
    .WORD 0x2020494C, 0x20355220, 0x20202039, 0x20202020, 0x20202020, 0x54203B20, 0x20706D65, 0x66667562
    .WORD 0x73207265, 0x0A657A69, 0x20202020, 0x4C4C4143, 0x6F746920, 0x6F635F61, 0x200A6572, 0x0A202020
    .WORD 0x20202020, 0x20504F50, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x2074636F, 0x634F202D
    .WORD 0x206C6174, 0x766E6F63, 0x69737265, 0x77206E6F, 0x70706172, 0x3B0A7265, 0x52203B0A, 0x203D2031
    .WORD 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x3B0A7265, 0x20325220, 0x6E75203D, 0x6E676973
    .WORD 0x69206465, 0x6765746E, 0x3B0A7265, 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20, 0x69676972
    .WORD 0x206C616E, 0x66667562, 0x70207265, 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x74690A2D, 0x6F5F616F, 0x0A3A7463, 0x20202020, 0x48535550
    .WORD 0x0A524C20, 0x20202020, 0x2020200A, 0x4D203B20, 0x31207861, 0x69642032, 0x73746967, 0x6E202B20
    .WORD 0x206C6C75, 0x3331203D, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x38203352, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6142203B, 0x38206573, 0x2020200A, 0x20494C20, 0x34522020, 0x20203020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x69736E55, 0x64656E67, 0x68732820, 0x2073776F, 0x20776172
    .WORD 0x73746962, 0x20200A29, 0x494C2020, 0x52202020, 0x33312035, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020, 0x69204C4C, 0x5F616F74
    .WORD 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52, 0x45522020, 0x3B0A0A54
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469
    .WORD 0x6E69625F, 0x42202D20, 0x72616E69, 0x6F632079, 0x7265766E, 0x6E6F6973, 0x61727720, 0x72657070
    .WORD 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A
    .WORD 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E
    .WORD 0x3D203152, 0x69726F20, 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x6E69625F
    .WORD 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20, 0x20323320
    .WORD 0x73746962, 0x6E202B20, 0x206C6C75, 0x3333203D, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049
    .WORD 0x32203352, 0x20202020, 0x20202020, 0x20202020, 0x6142203B, 0x32206573, 0x2020200A, 0x20494C20
    .WORD 0x34522020, 0x20203020, 0x20202020, 0x20202020, 0x203B2020, 0x69736E55, 0x64656E67, 0x68732820
    .WORD 0x2073776F, 0x20776172, 0x73746962, 0x20200A29, 0x494C2020, 0x52202020, 0x33332035, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020
    .WORD 0x69204C4C, 0x5F616F74, 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52
    .WORD 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x616F7469, 0x6769735F, 0x5F64656E, 0x20786568, 0x6953202D, 0x64656E67, 0x78656820
    .WORD 0x63656461, 0x6C616D69, 0x61727720, 0x72657070, 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473
    .WORD 0x6F697461, 0x7562206E, 0x72656666, 0x52203B0A, 0x203D2032, 0x6E676973, 0x69206465, 0x6765746E
    .WORD 0x3B0A7265, 0x74655220, 0x736E7275, 0x3152203A, 0x6F203D20, 0x69676972, 0x206C616E, 0x66667562
    .WORD 0x70207265, 0x746E696F, 0x3B0A7265, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x74690A2D, 0x735F616F, 0x656E6769, 0x65685F64, 0x200A3A78, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x0A202020, 0x20202020, 0x614D203B, 0x20382078, 0x69676964, 0x2B207374, 0x67697320
    .WORD 0x202B206E, 0x6C6C756E, 0x31203D20, 0x79622030, 0x0A736574, 0x20202020, 0x2020494C, 0x20335220
    .WORD 0x20203631, 0x20202020, 0x20202020, 0x42203B20, 0x20657361, 0x200A3631, 0x4C202020, 0x20202049
    .WORD 0x31203452, 0x20202020, 0x20202020, 0x20202020, 0x6953203B, 0x64656E67, 0x68732820, 0x2073776F
    .WORD 0x6E676973, 0x20200A29, 0x494C2020, 0x52202020, 0x30312035, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020, 0x69204C4C, 0x5F616F74
    .WORD 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52, 0x45522020, 0x3B0A0A54
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x616F7469
    .WORD 0x6769735F, 0x5F64656E, 0x206E6962, 0x6953202D, 0x64656E67, 0x6E696220, 0x20797261, 0x70617277
    .WORD 0x0A726570, 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566
    .WORD 0x3252203B, 0x73203D20, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x75746552, 0x3A736E72
    .WORD 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072, 0x65746E69, 0x2D3B0A72
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F74690A, 0x69735F61
    .WORD 0x64656E67, 0x6E69625F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020
    .WORD 0x78614D20, 0x20323320, 0x73746962, 0x73202B20, 0x206E6769, 0x756E202B, 0x3D206C6C, 0x20343320
    .WORD 0x65747962, 0x20200A73, 0x494C2020, 0x52202020, 0x20322033, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x73614220, 0x0A322065, 0x20202020, 0x2020494C, 0x20345220, 0x20202031, 0x20202020, 0x20202020
    .WORD 0x53203B20, 0x656E6769, 0x73282064, 0x73776F68, 0x67697320, 0x200A296E, 0x4C202020, 0x20202049
    .WORD 0x33203552, 0x20202034, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072
    .WORD 0x200A657A, 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020
    .WORD 0x2020504F, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x7473203B, 0x79706372, 0x73656428, 0x73202C74, 0x0A296372, 0x203B0A3B, 0x69706F43, 0x73207365
    .WORD 0x6E697274, 0x72662067, 0x73206D6F, 0x74206372, 0x6564206F, 0x69207473, 0x756C636E, 0x676E6964
    .WORD 0x72657420, 0x616E696D, 0x676E6974, 0x6C756E20, 0x6863206C, 0x63617261, 0x0A726574, 0x203B0A3B
    .WORD 0x75706E49, 0x3B0A3A74, 0x52202020, 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70
    .WORD 0x0A726574, 0x2020203B, 0x3D203252, 0x756F7320, 0x20656372, 0x6E696F70, 0x0A726574, 0x203B0A3B
    .WORD 0x7074754F, 0x0A3A7475, 0x2020203B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x696F7020
    .WORD 0x7265746E, 0x726F2820, 0x6E696769, 0x0A296C61, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x63727473, 0x0A3A7970, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x20564F4D, 0x52203352
    .WORD 0x20202031, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x726F2065, 0x6E696769, 0x64206C61
    .WORD 0x69747365, 0x6974616E, 0x70206E6F, 0x746E696F, 0x200A7265, 0x4D202020, 0x5220564F, 0x32522034
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x65766153, 0x756F7320, 0x20656372, 0x6E696F70
    .WORD 0x0A726574, 0x20202020, 0x7274730A, 0x5F797063, 0x706F6F6C, 0x20200A3A, 0x444C2020, 0x32522042
    .WORD 0x34525B20, 0x2020205D, 0x20202020, 0x20202020, 0x4C203B20, 0x2064616F, 0x65747962, 0x6F726620
    .WORD 0x6F73206D, 0x65637275, 0x2020200A, 0x42545320, 0x20325220, 0x5D31525B, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x7453203B, 0x2065726F, 0x65747962, 0x206F7420, 0x74736564, 0x74616E69, 0x0A6E6F69
    .WORD 0x20202020, 0x2020200A, 0x504D4320, 0x20325220, 0x20202030, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6843203B, 0x206B6365, 0x69206669, 0x20732774, 0x6C6C756E, 0x72657420, 0x616E696D, 0x0A726F74
    .WORD 0x20202020, 0x20514542, 0x63727473, 0x645F7970, 0x20656E6F, 0x20202020, 0x3B202020, 0x20664920
    .WORD 0x6F72657A, 0x6577202C, 0x20657227, 0x656E6F64, 0x2020200A, 0x20200A20, 0x44412020, 0x31522044
    .WORD 0x20315220, 0x20202031, 0x20202020, 0x20202020, 0x41203B20, 0x6E617664, 0x64206563, 0x69747365
    .WORD 0x6974616E, 0x70206E6F, 0x746E696F, 0x200A7265, 0x41202020, 0x52204444, 0x34522034, 0x20203120
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x61766441, 0x2065636E, 0x72756F73, 0x70206563, 0x746E696F
    .WORD 0x200A7265, 0x42202020, 0x72747320, 0x5F797063, 0x706F6F6C, 0x2020200A, 0x74730A20, 0x79706372
    .WORD 0x6E6F645F, 0x200A3A65, 0x4D202020, 0x5220564F, 0x33522031, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x75746552, 0x6F206E72, 0x69676972, 0x206C616E, 0x74736564, 0x74616E69, 0x206E6F69
    .WORD 0x6E696F70, 0x0A726574, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x3D3D3B0A
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x44203B0A, 0x43455249, 0x59524F54, 0x45504F20, 0x49544152
    .WORD 0x20534E4F, 0x614D202D, 0x69686374, 0x7920676E, 0x2072756F, 0x6E72656B, 0x73276C65, 0x72617420
    .WORD 0x725F7366, 0x64646165, 0x3B0A7269, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A0A3D3D, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6944203B, 0x74636572, 0x2079726F, 0x75727473, 0x72757463
    .WORD 0x6F282065, 0x75716170, 0x6F742065, 0x65737520, 0x3B0A2972, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2E0A2D2D, 0x20555145, 0x5F524944, 0x202C4446, 0x20202020, 0x20302020, 0x20202020, 0x203B2020
    .WORD 0x656C6946, 0x73656420, 0x70697263, 0x20726F74, 0x62203428, 0x73657479, 0x452E0A29, 0x44205551
    .WORD 0x4F5F5249, 0x45534646, 0x20202C54, 0x20203420, 0x20202020, 0x43203B20, 0x65727275, 0x7020746E
    .WORD 0x7469736F, 0x206E6F69, 0x64206E69, 0x63657269, 0x79726F74, 0x72747320, 0x206D6165, 0x62203428
    .WORD 0x73657479, 0x0A202029, 0x5551452E, 0x52494420, 0x5A49535F, 0x2C464F45, 0x38202020, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6E65706F, 0x20726964, 0x704F202D, 0x61206E65
    .WORD 0x72696420, 0x6F746365, 0x66207972, 0x7220726F, 0x69646165, 0x3B0A676E, 0x49203B0A, 0x20203A4E
    .WORD 0x3D203152, 0x74617020, 0x6E282068, 0x2D6C6C75, 0x6D726574, 0x74616E69, 0x73206465, 0x6E697274
    .WORD 0x3B0A2967, 0x54554F20, 0x3152203A, 0x44203D20, 0x202A5249, 0x6E616828, 0x29656C64, 0x20726F20
    .WORD 0x6E6F2030, 0x72726520, 0x3B0A726F, 0x4F203B0A, 0x736E6570, 0x64206120, 0x63657269, 0x79726F74
    .WORD 0x6C696620, 0x6E612065, 0x65722064, 0x6E727574, 0x20612073, 0x646E6168, 0x6620656C, 0x7220726F
    .WORD 0x64646165, 0x3B0A7269, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F0A2D2D, 0x646E6570, 0x0A3A7269
    .WORD 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x48535550
    .WORD 0x0A395220, 0x20202020, 0x2020200A, 0x564F4D20, 0x20385220, 0x20203152, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x65766153, 0x74617020, 0x20200A68, 0x203B2020, 0x6E65704F, 0x72696420, 0x6F746365
    .WORD 0x77207972, 0x20687469, 0x64616572, 0x6C6E6F2D, 0x6C662079, 0x20736761, 0x6D617328, 0x73612065
    .WORD 0x756F7920, 0x736C2072, 0x6D73612E, 0x20200A29, 0x4F4D2020, 0x31522056, 0x0A385220, 0x20202020
    .WORD 0x2020494C, 0x4F203252, 0x4F44525F, 0x0A594C4E, 0x20202020, 0x20435653, 0x5F535953, 0x4E45504F
    .WORD 0x2020200A, 0x564F4D20, 0x20395220, 0x20203152, 0x20202020, 0x20202020, 0x64663B20, 0x2020200A
    .WORD 0x504D4320, 0x20315220, 0x20200A30, 0x4C422020, 0x706F2054, 0x69646E65, 0x72655F72, 0x0A726F72
    .WORD 0x20202020, 0x2020200A, 0x41203B20, 0x636F6C6C, 0x20657461, 0x20524944, 0x75727473, 0x72757463
    .WORD 0x73282065, 0x6C6C616D, 0x756A202C, 0x66207473, 0x6E612064, 0x666F2064, 0x74657366, 0x20200A29
    .WORD 0x55502020, 0x52204853, 0x20202039, 0x20202020, 0x20202020, 0x20202020, 0x733B2020, 0x20657661
    .WORD 0x6A203952, 0x200A6369, 0x4C202020, 0x31522049, 0x52494420, 0x5A49535F, 0x0A464F45, 0x20202020
    .WORD 0x4C4C4143, 0x6C616D20, 0x0A636F6C, 0x20202020, 0x20504F50, 0x0A395220, 0x2020200A, 0x504D4320
    .WORD 0x20315220, 0x20200A30, 0x45422020, 0x706F2051, 0x69646E65, 0x72655F72, 0x5F726F72, 0x736F6C63
    .WORD 0x20200A65, 0x200A2020, 0x4D202020, 0x5220564F, 0x31522038, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6153203B, 0x44206576, 0x0A2A5249, 0x20202020, 0x2020200A, 0x49203B20, 0x6974696E, 0x7A696C61
    .WORD 0x49442065, 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x3252203B, 0x69747320, 0x68206C6C
    .WORD 0x66207361, 0x72662064, 0x6F206D6F, 0x0A6E6570, 0x20202020, 0x20575453, 0x5B203952, 0x2B203852
    .WORD 0x52494420, 0x5D44465F, 0x2020200A, 0x20494C20, 0x20325220, 0x20200A30, 0x54532020, 0x32522057
    .WORD 0x38525B20, 0x44202B20, 0x4F5F5249, 0x45534646, 0x200A5D54, 0x0A202020, 0x20202020, 0x20564F4D
    .WORD 0x52203152, 0x20202038, 0x20202020, 0x20202020, 0x52203B20, 0x72757465, 0x4944206E, 0x200A2A52
    .WORD 0x42202020, 0x65706F20, 0x7269646E, 0x6E6F645F, 0x20200A65, 0x6F0A2020, 0x646E6570, 0x655F7269
    .WORD 0x726F7272, 0x6F6C635F, 0x0A3A6573, 0x20202020, 0x20564F4D, 0x52203152, 0x20202039, 0x20202020
    .WORD 0x20202020, 0x66203B20, 0x73692064, 0x206E6920, 0x200A3952, 0x53202020, 0x53204356, 0x435F5359
    .WORD 0x45534F4C, 0x2020200A, 0x20494C20, 0x30203152, 0x2020200A, 0x6F204220, 0x646E6570, 0x645F7269
    .WORD 0x0A656E6F, 0x20202020, 0x65706F0A, 0x7269646E, 0x7272655F, 0x0A3A726F, 0x20202020, 0x5220494C
    .WORD 0x0A302031, 0x20202020, 0x65706F0A, 0x7269646E, 0x6E6F645F, 0x200A3A65, 0x50202020, 0x5220504F
    .WORD 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72203B0A, 0x64646165, 0x2D207269, 0x61655220
    .WORD 0x656E2064, 0x64207478, 0x63657269, 0x79726F74, 0x746E6520, 0x3B0A7972, 0x49203B0A, 0x20203A4E
    .WORD 0x3D203152, 0x52494420, 0x6628202A, 0x206D6F72, 0x6E65706F, 0x29726964, 0x20203B0A, 0x20202020
    .WORD 0x3D203252, 0x696F7020, 0x7265746E, 0x206F7420, 0x75727473, 0x64207463, 0x6E657269, 0x6F742074
    .WORD 0x6C696620, 0x203B0A6C, 0x3A54554F, 0x20315220, 0x2031203D, 0x65206669, 0x7972746E, 0x61657220
    .WORD 0x30202C64, 0x20666920, 0x6D206F6E, 0x2065726F, 0x72746E65, 0x2C736569, 0x20312D20, 0x65206E6F
    .WORD 0x726F7272, 0x3B0A3B0A, 0x61655220, 0x74207364, 0x6E206568, 0x20747865, 0x65726964, 0x726F7463
    .WORD 0x6E652079, 0x20797274, 0x6E697375, 0x68742067, 0x656B2065, 0x6C656E72, 0x72207327, 0x64646165
    .WORD 0x76207269, 0x53206169, 0x525F5359, 0x0A444145, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D
    .WORD 0x64616572, 0x3A726964, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048
    .WORD 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056, 0x20315220
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x52494420, 0x20200A2A, 0x4F4D2020, 0x39522056, 0x20325220
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x65735520, 0x20732772, 0x65726964, 0x6220746E, 0x65666675
    .WORD 0x20200A72, 0x200A2020, 0x3B202020, 0x65684320, 0x69206B63, 0x49442066, 0x6F702052, 0x65746E69
    .WORD 0x73692072, 0x6C617620, 0x200A6469, 0x43202020, 0x5220504D, 0x0A302038, 0x20202020, 0x20514542
    .WORD 0x64616572, 0x5F726964, 0x6F727265, 0x20200A72, 0x200A2020, 0x3B202020, 0x61655220, 0x6E6F2064
    .WORD 0x69642065, 0x746E6572, 0x6F726620, 0x6964206D, 0x74636572, 0x2079726F, 0x75206466, 0x676E6973
    .WORD 0x72756320, 0x746E6572, 0x66666F20, 0x0A746573, 0x20202020, 0x2057444C, 0x5B203152, 0x2B203852
    .WORD 0x52494420, 0x5D44465F, 0x66203B20, 0x20200A64, 0x200A2020, 0x3B202020, 0x65735520, 0x65687420
    .WORD 0x72696420, 0x6F746365, 0x73277972, 0x66666F20, 0x20746573, 0x6577202D, 0x65656E20, 0x6F742064
    .WORD 0x706D6920, 0x656D656C, 0x6C20746E, 0x6B656573, 0x20726F20, 0x0A657375, 0x20202020, 0x6874203B
    .WORD 0x61662065, 0x74207463, 0x20746168, 0x68636165, 0x61657220, 0x65672064, 0x6F207374, 0x6420656E
    .WORD 0x6E657269, 0x74612074, 0x74206120, 0x20656D69, 0x6D6F7266, 0x72617420, 0x200A7366, 0x4D202020
    .WORD 0x5220564F, 0x39522032, 0x20202020, 0x20202020, 0x20202020, 0x7375203B, 0x62207265, 0x65666675
    .WORD 0x20200A72, 0x494C2020, 0x33522020, 0x52494420, 0x5F544E45, 0x455A4953, 0x3B20464F, 0x7A697320
    .WORD 0x666F2065, 0x656E6F20, 0x72696420, 0x0A746E65, 0x20202020, 0x20435653, 0x5F535953, 0x44414552
    .WORD 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30, 0x45422020, 0x65722051, 0x69646461, 0x6E655F72
    .WORD 0x20202064, 0x3B202020, 0x464F4520, 0x2020200A, 0x504D4320, 0x20315220, 0x45524944, 0x535F544E
    .WORD 0x4F455A49, 0x20200A46, 0x4E422020, 0x65722045, 0x69646461, 0x72655F72, 0x20726F72, 0x3B202020
    .WORD 0x6F685320, 0x72207472, 0x20646165, 0x6520726F, 0x726F7272, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x72746E45, 0x65722079, 0x73206461, 0x65636375, 0x75667373, 0x0A796C6C, 0x20202020, 0x7055203B
    .WORD 0x65746164, 0x65687420, 0x66666F20, 0x20746573, 0x44206E69, 0x73205249, 0x63757274, 0x65727574
    .WORD 0x2020200A, 0x57444C20, 0x20325220, 0x2038525B, 0x4944202B, 0x464F5F52, 0x54455346, 0x20200A5D
    .WORD 0x44412020, 0x32522044, 0x20325220, 0x20200A31, 0x54532020, 0x32522057, 0x38525B20, 0x44202B20
    .WORD 0x4F5F5249, 0x45534646, 0x200A5D54, 0x0A202020, 0x20202020, 0x5220494C, 0x20312031, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x52203B20, 0x72757465, 0x7573206E, 0x73656363, 0x20200A73, 0x20422020
    .WORD 0x64616572, 0x5F726964, 0x656E6F64, 0x2020200A, 0x65720A20, 0x69646461, 0x72655F72, 0x3A726F72
    .WORD 0x2020200A, 0x20494C20, 0x2D203152, 0x20200A31, 0x20422020, 0x64616572, 0x5F726964, 0x656E6F64
    .WORD 0x2020200A, 0x65720A20, 0x69646461, 0x6E655F72, 0x200A3A64, 0x4C202020, 0x31522049, 0x200A3020
    .WORD 0x0A202020, 0x64616572, 0x5F726964, 0x656E6F64, 0x20200A3A, 0x4F502020, 0x39522050, 0x2020200A
    .WORD 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6C63203B, 0x6465736F, 0x2D207269, 0x6F6C4320, 0x64206573
    .WORD 0x63657269, 0x79726F74, 0x72747320, 0x0A6D6165, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x4944203D
    .WORD 0x3B0A2A52, 0x54554F20, 0x3152203A, 0x30203D20, 0x206E6F20, 0x63637573, 0x2C737365, 0x20312D20
    .WORD 0x65206E6F, 0x726F7272, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F6C630A, 0x69646573
    .WORD 0x200A3A72, 0x50202020, 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x52203852, 0x20200A31, 0x4D432020, 0x38522050, 0x200A3020, 0x42202020
    .WORD 0x63205145, 0x65736F6C, 0x5F726964, 0x6F727265, 0x20200A72, 0x200A2020, 0x3B202020, 0x6F6C4320
    .WORD 0x74206573, 0x64206568, 0x63657269, 0x79726F74, 0x0A646620, 0x20202020, 0x2057444C, 0x5B203152
    .WORD 0x2B203852, 0x52494420, 0x5D44465F, 0x2020200A, 0x43565320, 0x53595320, 0x4F4C435F, 0x200A4553
    .WORD 0x0A202020, 0x20202020, 0x7246203B, 0x74206565, 0x44206568, 0x73205249, 0x63757274, 0x65727574
    .WORD 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3852, 0x43202020, 0x204C4C41, 0x65657266, 0x2020200A
    .WORD 0x20200A20, 0x494C2020, 0x20315220, 0x20200A30, 0x20422020, 0x736F6C63, 0x72696465, 0x6E6F645F
    .WORD 0x20200A65, 0x630A2020, 0x65736F6C, 0x5F726964, 0x6F727265, 0x200A3A72, 0x4C202020, 0x31522049
    .WORD 0x0A312D20, 0x20202020, 0x6F6C630A, 0x69646573, 0x6F645F72, 0x0A3A656E, 0x20202020, 0x20504F50
    .WORD 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x3B0A2D2D, 0x77657220, 0x64646E69, 0x2D207269, 0x73655220, 0x64207465, 0x63657269
    .WORD 0x79726F74, 0x72747320, 0x206D6165, 0x62206F74, 0x6E696765, 0x676E696E, 0x3B0A3B0A, 0x3A4E4920
    .WORD 0x31522020, 0x44203D20, 0x0A2A5249, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x69776572
    .WORD 0x6964646E, 0x200A3A72, 0x43202020, 0x5220504D, 0x0A302031, 0x20202020, 0x20514542, 0x69776572
    .WORD 0x6964646E, 0x6F645F72, 0x200A656E, 0x0A202020, 0x20202020, 0x5220494C, 0x0A302032, 0x20202020
    .WORD 0x20575453, 0x5B203252, 0x2B203152, 0x52494420, 0x46464F5F, 0x5D544553, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x6465654E, 0x206F7420, 0x6B656573, 0x206F7420, 0x69676562, 0x6E696E6E, 0x666F2067
    .WORD 0x72696420, 0x6F746365, 0x200A7972, 0x3B202020, 0x726F4620, 0x72617420, 0x202C7366, 0x73696874
    .WORD 0x61656D20, 0x6320736E, 0x69736F6C, 0x6120676E, 0x7220646E, 0x65706F65, 0x676E696E, 0x726F202C
    .WORD 0x69737520, 0x6C20676E, 0x6B656573, 0x2020200A, 0x53203B20, 0x6C706D69, 0x70612065, 0x616F7270
    .WORD 0x203A6863, 0x736F6C63, 0x6E612065, 0x65722064, 0x6E65706F, 0x2020200A, 0x53555020, 0x524C2048
    .WORD 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056, 0x0A315220
    .WORD 0x20202020, 0x6153203B, 0x74206576, 0x70206568, 0x20687461, 0x6577202D, 0x6E6F6420, 0x68207427
    .WORD 0x20657661, 0x73207469, 0x65726F74, 0x73202C64, 0x6874206F, 0x69207369, 0x72742073, 0x796B6369
    .WORD 0x2020200A, 0x49203B20, 0x2061206E, 0x6C616572, 0x706D6920, 0x656D656C, 0x7461746E, 0x2C6E6F69
    .WORD 0x6F747320, 0x70206572, 0x20687461, 0x44206E69, 0x73205249, 0x63757274, 0x65727574, 0x2020200A
    .WORD 0x20200A20, 0x203B2020, 0x20726F46, 0x2C776F6E, 0x73756A20, 0x65722074, 0x20746573, 0x7366666F
    .WORD 0x61207465, 0x7220646E, 0x20796C65, 0x72206E6F, 0x64646165, 0x73277269, 0x68656220, 0x6F697661
    .WORD 0x20200A72, 0x200A2020, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A
    .WORD 0x65720A20, 0x646E6977, 0x5F726964, 0x656E6F64, 0x20200A3A, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72696420, 0x2D206466, 0x74654720, 0x6C696620, 0x65642065
    .WORD 0x69726373, 0x726F7470, 0x6F726620, 0x4944206D, 0x3B0A2A52, 0x49203B0A, 0x20203A4E, 0x3D203152
    .WORD 0x52494420, 0x203B0A2A, 0x3A54554F, 0x20315220, 0x6966203D, 0x6420656C, 0x72637365, 0x6F747069
    .WORD 0x6F202C72, 0x312D2072, 0x206E6F20, 0x6F727265, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x69640A2D, 0x3A646672, 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30, 0x45422020, 0x69642051
    .WORD 0x5F646672, 0x6F727265, 0x20200A72, 0x200A2020, 0x4C202020, 0x52205744, 0x525B2031, 0x202B2031
    .WORD 0x5F524944, 0x0A5D4446, 0x20202020, 0x0A544552, 0x20202020, 0x7269640A, 0x655F6466, 0x726F7272
    .WORD 0x20200A3A, 0x494C2020, 0x20315220, 0x200A312D, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x6548203B, 0x7265706C, 0x7369203A, 0x7269645F, 0x43202D20, 0x6B636568
    .WORD 0x20666920, 0x61702061, 0x69206874, 0x20612073, 0x65726964, 0x726F7463, 0x0A3B0A79, 0x4E49203B
    .WORD 0x5220203A, 0x203D2031, 0x68746170, 0x4F203B0A, 0x203A5455, 0x3D203152, 0x69203120, 0x69642066
    .WORD 0x74636572, 0x2C79726F, 0x69203020, 0x6F6E2066, 0x2D202C74, 0x6E6F2031, 0x72726520, 0x3B0A726F
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D, 0x69645F73, 0x200A3A72, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x0A202020, 0x20202020, 0x7254203B, 0x6F742079, 0x65706F20, 0x7361206E, 0x72696420
    .WORD 0x6F746365, 0x200A7972, 0x43202020, 0x204C4C41, 0x6E65706F, 0x0A726964, 0x20202020, 0x20504D43
    .WORD 0x30203152, 0x2020200A, 0x51454220, 0x5F736920, 0x5F726964, 0x5F746F6E, 0x0A726964, 0x20202020
    .WORD 0x2020200A, 0x49203B20, 0x706F2074, 0x64656E65, 0x20736120, 0x69642061, 0x74636572, 0x0A79726F
    .WORD 0x20202020, 0x20564F4D, 0x52203252, 0x20202031, 0x20202020, 0x20202020, 0x53203B20, 0x20657661
    .WORD 0x2A524944, 0x2020200A, 0x20494C20, 0x31203152, 0x20202020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x75746552, 0x74206E72, 0x0A657572, 0x20202020, 0x4C4C4143, 0x6F6C6320, 0x69646573, 0x20202072
    .WORD 0x20202020, 0x43203B20, 0x65736F6C, 0x0A746920, 0x20202020, 0x73692042, 0x7269645F, 0x6E6F645F
    .WORD 0x20200A65, 0x690A2020, 0x69645F73, 0x6F6E5F72, 0x69645F74, 0x200A3A72, 0x4C202020, 0x31522049
    .WORD 0x200A3020, 0x0A202020, 0x645F7369, 0x645F7269, 0x3A656E6F, 0x2020200A, 0x504F5020, 0x0A524C20
    .WORD 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x45203B0A, 0x706D6178
    .WORD 0x7520656C, 0x65676173, 0x6E756620, 0x6F697463, 0x202D206E, 0x7473696C, 0x72696420, 0x6F746365
    .WORD 0x63207972, 0x65746E6F, 0x2073746E, 0x6B696C28, 0x736C2065, 0x203B0A29, 0x73696854, 0x6D656420
    .WORD 0x74736E6F, 0x65746172, 0x6F682073, 0x6F742077, 0x65737520, 0x65706F20, 0x7269646E, 0x6165722F
    .WORD 0x72696464, 0x6F6C632F, 0x69646573, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x696C0A2D
    .WORD 0x645F7473, 0x63657269, 0x79726F74, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020
    .WORD 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x200A2020, 0x4D202020, 0x5220564F
    .WORD 0x31522038, 0x20202020, 0x20202020, 0x20202020, 0x6170203B, 0x200A6874, 0x0A202020, 0x20202020
    .WORD 0x6C41203B, 0x61636F6C, 0x64206574, 0x6E657269, 0x6E6F2074, 0x61747320, 0x200A6B63, 0x53202020
    .WORD 0x53204255, 0x50532050, 0x52494420, 0x5F544E45, 0x455A4953, 0x200A464F, 0x4D202020, 0x5220564F
    .WORD 0x50532039, 0x2020200A, 0x20200A20, 0x203B2020, 0x6E65704F, 0x72696420, 0x6F746365, 0x200A7972
    .WORD 0x4D202020, 0x5220564F, 0x38522031, 0x2020200A, 0x4C414320, 0x706F204C, 0x69646E65, 0x20200A72
    .WORD 0x4D432020, 0x31522050, 0x200A3020, 0x42202020, 0x6C205145, 0x5F747369, 0x5F726964, 0x6F727265
    .WORD 0x20200A72, 0x200A2020, 0x4D202020, 0x5220564F, 0x31522038, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x4944203B, 0x200A2A52, 0x0A202020, 0x7473696C, 0x7269645F, 0x6F6F6C5F, 0x200A3A70, 0x4D202020
    .WORD 0x5220564F, 0x38522031, 0x2020200A, 0x564F4D20, 0x20325220, 0x200A3952, 0x43202020, 0x204C4C41
    .WORD 0x64616572, 0x0A726964, 0x20202020, 0x20504D43, 0x30203152, 0x2020200A, 0x51454220, 0x73696C20
    .WORD 0x69645F74, 0x6C635F72, 0x0A65736F, 0x20202020, 0x2020494C, 0x2D203252, 0x20200A31, 0x4D432020
    .WORD 0x31522050, 0x0A325220, 0x20202020, 0x20514542, 0x7473696C, 0x7269645F, 0x7272655F, 0x200A726F
    .WORD 0x0A202020, 0x20202020, 0x7250203B, 0x20746E69, 0x20656874, 0x656D616E, 0x2020200A, 0x44444120
    .WORD 0x20315220, 0x44203952, 0x4E455249, 0x414E5F54, 0x200A454D, 0x43202020, 0x204C4C41, 0x73747570
    .WORD 0x2020200A, 0x20200A20, 0x203B2020, 0x69206649, 0x20732774, 0x69642061, 0x74636572, 0x2C79726F
    .WORD 0x69727020, 0x2720746E, 0x200A272F, 0x4C202020, 0x52205744, 0x525B2032, 0x202B2039, 0x45524944
    .WORD 0x545F544E, 0x5D455059, 0x2020200A, 0x504D4320, 0x20325220, 0x445F5444, 0x200A5249, 0x42202020
    .WORD 0x6C20454E, 0x5F747369, 0x5F726964, 0x5F746F6E, 0x0A726964, 0x20202020, 0x2020200A, 0x20494C20
    .WORD 0x73203152, 0x6873616C, 0x6168635F, 0x20200A72, 0x41432020, 0x70204C4C, 0x68637475, 0x200A7261
    .WORD 0x0A202020, 0x7473696C, 0x7269645F, 0x746F6E5F, 0x7269645F, 0x20200A3A, 0x494C2020, 0x20315220
    .WORD 0x6C77656E, 0x5F656E69, 0x72616863, 0x2020200A, 0x4C414320, 0x7570204C, 0x61686374, 0x20200A72
    .WORD 0x200A2020, 0x42202020, 0x73696C20, 0x69645F74, 0x6F6C5F72, 0x200A706F, 0x0A202020, 0x7473696C
    .WORD 0x7269645F, 0x6F6C635F, 0x0A3A6573, 0x20202020, 0x20564F4D, 0x52203152, 0x20200A38, 0x41432020
    .WORD 0x63204C4C, 0x65736F6C, 0x0A726964, 0x20202020, 0x5220494C, 0x0A302031, 0x20202020, 0x696C2042
    .WORD 0x645F7473, 0x645F7269, 0x0A656E6F, 0x20202020, 0x73696C0A, 0x69645F74, 0x72655F72, 0x3A726F72
    .WORD 0x2020200A, 0x20494C20, 0x2D203152, 0x20200A31, 0x6C0A2020, 0x5F747369, 0x5F726964, 0x656E6F64
    .WORD 0x20200A3A, 0x44412020, 0x50532044, 0x20505320, 0x45524944, 0x535F544E, 0x4F455A49, 0x20200A46
    .WORD 0x4F502020, 0x39522050, 0x2020200A, 0x504F5020, 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C
    .WORD 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6144203B, 0x53206174
    .WORD 0x69746365, 0x3B0A6E6F, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x730A2D2D, 0x6873616C, 0x6168635F
    .WORD 0x200A3A72, 0x2E202020, 0x44524F57, 0x20373420, 0x20202020, 0x2F273B20, 0x656E0A27, 0x6E696C77
    .WORD 0x68635F65, 0x0A3A7261, 0x20202020, 0x524F572E, 0x30312044, 0x203B0A0A, 0x75677241, 0x746E656D
    .WORD 0x72612073, 0x61702065, 0x64657373, 0x206E6920, 0x2E2E3252, 0x20323152, 0x20707528, 0x31206F74
    .WORD 0x0A2E2931, 0x754F203B, 0x74757074, 0x20736920, 0x74697277, 0x206E6574, 0x656D6D69, 0x74616964
    .WORD 0x3B796C65, 0x206F6E20, 0x65746E69, 0x6C616E72, 0x66756220, 0x69726566, 0x0A2E676E, 0x203B0A3B
    .WORD 0x203A4E49, 0x20315220, 0x6F66203D, 0x74616D72, 0x72747320, 0x0A676E69, 0x554F203B, 0x52203A54
    .WORD 0x203D2031, 0x626D756E, 0x6F207265, 0x68632066, 0x63617261, 0x73726574, 0x69727720, 0x6E657474
    .WORD 0x706F2820, 0x6E6F6974, 0x202C6C61, 0x206E6163, 0x69206562, 0x726F6E67, 0x0A296465, 0x7375203B
    .WORD 0x3A656761, 0x20203B0A, 0x69727020, 0x2866746E, 0x6C654822, 0x25206F6C, 0x6E202C73, 0x65626D75
    .WORD 0x64253D72, 0x6568202C, 0x78253D78, 0x6863202C, 0x253D7261, 0x226E5C63, 0x7722202C, 0x646C726F
    .WORD 0x34202C22, 0x32202C32, 0x202C3535, 0x29274127, 0x20203B0A, 0x33524B20, 0x3B0A3A32, 0x4C202020
    .WORD 0x31522049, 0x746D6620, 0x7274735F, 0x20203B0A, 0x20494C20, 0x34203252, 0x203B0A32, 0x494C2020
    .WORD 0x20335220, 0x6C6C6568, 0x74735F6F, 0x203B0A72, 0x4C422020, 0x69727020, 0x0A66746E, 0x2E2E2E3B
    .WORD 0x6D663B0A, 0x74735F74, 0x2E203A72, 0x49435341, 0x22205A49, 0x626D754E, 0x203A7265, 0x202C6425
    .WORD 0x69727453, 0x203A676E, 0x6E5C7325, 0x683B0A22, 0x6F6C6C65, 0x7274735F, 0x412E203A, 0x49494353
    .WORD 0x7722205A, 0x646C726F, 0x2D3B0A22, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A0A2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x69727020, 0x2066746E, 0x6F46202D, 0x74616D72, 0x20646574
    .WORD 0x7074756F, 0x74207475, 0x7473206F, 0x74756F64, 0x3B0A3B0A, 0x70755320, 0x74726F70, 0x63206465
    .WORD 0x65766E6F, 0x6F697372, 0x0A3A736E, 0x2020203B, 0x20202525, 0x20202020, 0x6574696C, 0x206C6172
    .WORD 0x0A272527, 0x2020203B, 0x20207325, 0x20202020, 0x69727473, 0x2820676E, 0x72616863, 0x3B0A292A
    .WORD 0x25202020, 0x202F2064, 0x73206925, 0x656E6769, 0x65642064, 0x616D6963, 0x203B0A6C, 0x78252020
    .WORD 0x20202020, 0x6E752020, 0x6E676973, 0x68206465, 0x64617865, 0x6D696365, 0x28206C61, 0x65776F6C
    .WORD 0x73616372, 0x3B0A2965, 0x25202020, 0x20202063, 0x73202020, 0x6C676E69, 0x68632065, 0x63617261
    .WORD 0x0A726574, 0x2020203B, 0x20206225, 0x20202020, 0x69736E75, 0x64656E67, 0x6E696220, 0x0A797261
    .WORD 0x2020203B, 0x20206F25, 0x20202020, 0x69736E75, 0x64656E67, 0x74636F20, 0x3B0A6C61, 0x41203B0A
    .WORD 0x6D756772, 0x73746E65, 0x3252203A, 0x31522E2E, 0x66282032, 0x74737269, 0x29313120, 0x6874202C
    .WORD 0x6F206E65, 0x7473206E, 0x206B6361, 0x6C616328, 0xE272656C, 0x75709180, 0x64656873, 0x3B0A2E29
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x700A2D2D, 0x746E6972, 0x200A3A66, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x50202020
    .WORD 0x20485355, 0x0A303152, 0x20202020, 0x48535550, 0x31315220, 0x2020200A, 0x53555020, 0x31522048
    .WORD 0x200A0A32, 0x53202020, 0x53204255, 0x50532050, 0x20303820, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6C203B20, 0x6C61636F, 0x61726620, 0x203A656D, 0x2B203434, 0x20343320, 0x6170202B, 0x6E696464
    .WORD 0x200A0A67, 0x3B202020, 0x76615320, 0x32522065, 0x31522E2E, 0x6F742032, 0x636F6C20, 0x61206C61
    .WORD 0x79617272, 0x2020200A, 0x57545320, 0x20325220, 0x2050535B, 0x5D30202B, 0x2020200A, 0x57545320
    .WORD 0x20335220, 0x2050535B, 0x5D34202B, 0x2020200A, 0x57545320, 0x20345220, 0x2050535B, 0x5D38202B
    .WORD 0x2020200A, 0x57545320, 0x20355220, 0x2050535B, 0x3231202B, 0x20200A5D, 0x54532020, 0x36522057
    .WORD 0x50535B20, 0x31202B20, 0x200A5D36, 0x53202020, 0x52205754, 0x535B2037, 0x202B2050, 0x0A5D3032
    .WORD 0x20202020, 0x20575453, 0x5B203852, 0x2B205053, 0x5D343220, 0x2020200A, 0x57545320, 0x20395220
    .WORD 0x2050535B, 0x3832202B, 0x20200A5D, 0x54532020, 0x31522057, 0x535B2030, 0x202B2050, 0x0A5D3233
    .WORD 0x20202020, 0x20575453, 0x20313152, 0x2050535B, 0x3633202B, 0x20200A5D, 0x54532020, 0x31522057
    .WORD 0x535B2032, 0x202B2050, 0x0A5D3034, 0x2020200A, 0x564F4D20, 0x20385220, 0x20203152, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x726F6620, 0x2074616D, 0x6E696F70, 0x0A726574, 0x20202020
    .WORD 0x2020494C, 0x30203952, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x75677261
    .WORD 0x746E656D, 0x646E6920, 0x0A0A7865, 0x20202020, 0x20564F4D, 0x20303152, 0x20205053, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x203B2020, 0x65736162, 0x20666F20, 0x65766173, 0x65722064, 0x74736967
    .WORD 0x0A737265, 0x20202020, 0x20444441, 0x20313152, 0x34205053, 0x20202034, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x766E6F63, 0x69737265, 0x62206E6F, 0x65666675, 0x700A0A72, 0x746E6972, 0x6F6C5F66
    .WORD 0x0A3A706F, 0x20202020, 0x2042444C, 0x5B203152, 0x205D3852, 0x20202020, 0x6165723B, 0x6D662064
    .WORD 0x74732074, 0x676E6972, 0x61686320, 0x20200A72, 0x4D432020, 0x31522050, 0x200A3020, 0x42202020
    .WORD 0x70205145, 0x746E6972, 0x6F645F66, 0x0A0A656E, 0x20202020, 0x20504D43, 0x33203152, 0x20202037
    .WORD 0x6568633B, 0x66206B63, 0x2720726F, 0x200A2725, 0x42202020, 0x7020454E, 0x746E6972, 0x6F6E5F66
    .WORD 0x6C616D72, 0x6168635F, 0x200A0A72, 0x41202020, 0x52204444, 0x38522038, 0x3B203120, 0x73746920
    .WORD 0x27206120, 0x202C2725, 0x65766F6D, 0x206F7420, 0x7478656E, 0x61686320, 0x6F662072, 0x70732072
    .WORD 0x66696365, 0x0A726569, 0x20202020, 0x2042444C, 0x5B203252, 0x0A5D3852, 0x20202020, 0x20504D43
    .WORD 0x30203252, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E, 0x656E6F64, 0x20200A0A, 0x4D432020
    .WORD 0x32522050, 0x20373320, 0x203B2020, 0x63656863, 0x6F66206B, 0x25272072, 0x200A2725, 0x42202020
    .WORD 0x70205145, 0x746E6972, 0x65705F66, 0x6E656372, 0x20200A74, 0x4D432020, 0x32522050, 0x35313120
    .WORD 0x203B2020, 0x63656863, 0x6F66206B, 0x25272072, 0x200A2773, 0x42202020, 0x70205145, 0x746E6972
    .WORD 0x74735F66, 0x676E6972, 0x2020200A, 0x504D4320, 0x20325220, 0x20303031, 0x68633B20, 0x206B6365
    .WORD 0x20726F66, 0x27642527, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E, 0x0A746E69, 0x20202020
    .WORD 0x20504D43, 0x31203252, 0x20203530, 0x6568633B, 0x66206B63, 0x2720726F, 0x0A276925, 0x20202020
    .WORD 0x20514542, 0x6E697270, 0x695F6674, 0x200A746E, 0x43202020, 0x5220504D, 0x32312032, 0x3B202030
    .WORD 0x63656863, 0x6F66206B, 0x25272072, 0x200A2778, 0x42202020, 0x70205145, 0x746E6972, 0x65685F66
    .WORD 0x20200A78, 0x4D432020, 0x32522050, 0x20393920, 0x633B2020, 0x6B636568, 0x726F6620, 0x63252720
    .WORD 0x20200A27, 0x45422020, 0x72702051, 0x66746E69, 0x6168635F, 0x20200A72, 0x4D432020, 0x32522050
    .WORD 0x20383920, 0x633B2020, 0x6B636568, 0x726F6620, 0x62252720, 0x20200A27, 0x45422020, 0x72702051
    .WORD 0x66746E69, 0x6E69625F, 0x2020200A, 0x504D4320, 0x20325220, 0x20313131, 0x68633B20, 0x206B6365
    .WORD 0x20726F66, 0x276F2527, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E, 0x0A74636F, 0x2020200A
    .WORD 0x75203B20, 0x6F6E6B6E, 0x73206E77, 0x69636570, 0x72656966, 0x2020200A, 0x20494C20, 0x20315220
    .WORD 0x20203733, 0x6E753B20, 0x776F6E6B, 0x7073206E, 0x66696365, 0x2C726569, 0x69727020, 0x2720746E
    .WORD 0x200A2725, 0x43202020, 0x204C4C41, 0x63747570, 0x0A726168, 0x20202020, 0x20564F4D, 0x52203152
    .WORD 0x20202032, 0x7270203B, 0x20746E69, 0x20656874, 0x6E6B6E75, 0x206E776F, 0x63657073, 0x65696669
    .WORD 0x68632072, 0x200A7261, 0x43202020, 0x204C4C41, 0x63747570, 0x0A726168, 0x20202020, 0x20202042
    .WORD 0x6E697270, 0x635F6674, 0x69746E6F, 0x0A65756E, 0x6972700A, 0x5F66746E, 0x6D726F6E, 0x635F6C61
    .WORD 0x3A726168, 0x2020200A, 0x4C414320, 0x7570204C, 0x61686374, 0x20200A72, 0x20422020, 0x72702020
    .WORD 0x66746E69, 0x6E6F635F, 0x756E6974, 0x700A0A65, 0x746E6972, 0x65705F66, 0x6E656372, 0x200A3A74
    .WORD 0x4C202020, 0x52202049, 0x37332031, 0x3B202020, 0x6E697270, 0x25272074, 0x20200A27, 0x41432020
    .WORD 0x70204C4C, 0x68637475, 0x200A7261, 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66, 0x6E69746E
    .WORD 0x0A0A6575, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7241203B, 0x656D7567, 0x6620746E
    .WORD 0x68637465, 0x6C656820, 0x73726570, 0x61732820, 0x6120656D, 0x65622073, 0x65726F66, 0x2D3B0A29
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x665F0A2D, 0x68637465, 0x6772615F, 0x3A31725F, 0x2020200A
    .WORD 0x53555020, 0x524C2048, 0x20200A20, 0x55502020, 0x52204853, 0x20200A33, 0x41432020, 0x5F204C4C
    .WORD 0x5F746567, 0x5F677261, 0x72646461, 0x0A737365, 0x20202020, 0x2057444C, 0x5B203152, 0x0A5D3352
    .WORD 0x20202020, 0x20504F50, 0x200A3352, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x5F0A0A54
    .WORD 0x63746566, 0x72615F68, 0x32725F67, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020
    .WORD 0x52204853, 0x20200A33, 0x41432020, 0x5F204C4C, 0x5F746567, 0x5F677261, 0x72646461, 0x0A737365
    .WORD 0x20202020, 0x2057444C, 0x5B203252, 0x0A5D3352, 0x20202020, 0x20504F50, 0x200A3352, 0x50202020
    .WORD 0x4C20504F, 0x20200A52, 0x45522020, 0x5F0A0A54, 0x5F746567, 0x5F677261, 0x72646461, 0x3A737365
    .WORD 0x3B202020, 0x74656620, 0x74206863, 0x61206568, 0x65726464, 0x6F207373, 0x68742066, 0x656E2065
    .WORD 0x61207478, 0x6D756772, 0x20746E65, 0x65736162, 0x6E6F2064, 0x20395220, 0x67726128, 0x646E6920
    .WORD 0x0A297865, 0x20202020, 0x20504D43, 0x31203952, 0x20202031, 0x20202020, 0x6669203B, 0x67726120
    .WORD 0x646E6920, 0x3E207865, 0x3131203D, 0x7469202C, 0x6F207327, 0x6874206E, 0x74732065, 0x0A6B6361
    .WORD 0x20202020, 0x20544C42, 0x6772615F, 0x5F6E695F, 0x73676572, 0x2020200A, 0x42555320, 0x20335220
    .WORD 0x31203952, 0x20202031, 0x52203B20, 0x203D2033, 0x626D756E, 0x6F207265, 0x78652066, 0x20617274
    .WORD 0x73677261, 0x206E6F20, 0x63617473, 0x20200A6B, 0x494C2020, 0x34522020, 0x200A3420, 0x4D202020
    .WORD 0x52204C55, 0x33522033, 0x0A345220, 0x20202020, 0x20444441, 0x53203352, 0x33522050, 0x20202020
    .WORD 0x3352203B, 0x61203D20, 0x65726464, 0x6F207373, 0x69662066, 0x20747372, 0x72747865, 0x72612061
    .WORD 0x6E6F2067, 0x61747320, 0x28206B63, 0x20746F6E, 0x65727573, 0x20666920, 0x73696874, 0x20736920
    .WORD 0x72726F63, 0x29746365, 0x2020200A, 0x44444120, 0x20335220, 0x31203352, 0x20203430, 0x6F203B20
    .WORD 0x65736666, 0x6F742074, 0x6C616320, 0x2772656C, 0x69662073, 0x20747372, 0x72747865, 0x72612061
    .WORD 0x30312067, 0x200A2034, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x74207369
    .WORD 0x73206568, 0x20657A69, 0x7420666F, 0x6C206568, 0x6C61636F, 0x61726620, 0x2820656D, 0x20293038
    .WORD 0x6173202B, 0x20646576, 0x69676572, 0x72657473, 0x34282073, 0x200A2934, 0x52202020, 0x0A0A5445
    .WORD 0x6772615F, 0x5F6E695F, 0x73676572, 0x2020203A, 0x20202020, 0x6566203B, 0x20686374, 0x75677261
    .WORD 0x746E656D, 0x6F726620, 0x3252206D, 0x31522E2E, 0x61622032, 0x20646573, 0x52206E6F, 0x20200A39
    .WORD 0x494C2020, 0x34522020, 0x20203420, 0x20202020, 0x200A2020, 0x4D202020, 0x52204C55, 0x39522033
    .WORD 0x20345220, 0x3B202020, 0x20395220, 0x7261203D, 0x6E692067, 0x2C786564, 0x33522820, 0x6F203D20
    .WORD 0x65736666, 0x6E692074, 0x74796220, 0x0A297365, 0x20202020, 0x20444441, 0x52203352, 0x52203031
    .WORD 0x20202033, 0x3352203B, 0x61203D20, 0x65726464, 0x6F207373, 0x61732066, 0x20646576, 0x69676572
    .WORD 0x72657473, 0x206E6920, 0x61636F6C, 0x7261206C, 0x2C796172, 0x30315220, 0x62203D20, 0x20657361
    .WORD 0x7320666F, 0x64657661, 0x67657220, 0x65747369, 0x200A7372, 0x52202020, 0x0A0A5445, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7053203B, 0x66696365, 0x20726569, 0x646E6168, 0x7372656C
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6972700A, 0x5F66746E, 0x69727473, 0x0A3A676E
    .WORD 0x20202020, 0x4C4C4143, 0x65665F20, 0x5F686374, 0x5F677261, 0x20203172, 0x7465673B, 0x72747320
    .WORD 0x20676E69, 0x6E696F70, 0x20726574, 0x6D6F7266, 0x0A315220, 0x20202020, 0x20444441, 0x52203952
    .WORD 0x0A312039, 0x20202020, 0x4C4C4143, 0x72705F20, 0x5F746E69, 0x69727473, 0x2020676E, 0x6972703B
    .WORD 0x7420746E, 0x73206568, 0x6E697274, 0x20200A67, 0x20422020, 0x72702020, 0x66746E69, 0x6E6F635F
    .WORD 0x756E6974, 0x700A0A65, 0x746E6972, 0x6E695F66, 0x200A3A74, 0x43202020, 0x204C4C41, 0x7465665F
    .WORD 0x615F6863, 0x725F6772, 0x3B202032, 0x20746567, 0x65746E69, 0x20726567, 0x20727470, 0x6D6F7266
    .WORD 0x0A325220, 0x20202020, 0x2020200A, 0x564F4D20, 0x20315220, 0x20203252, 0x20202020, 0x20202020
    .WORD 0x6F633B20, 0x7265766E, 0x756E2074, 0x7265626D, 0x6F726620, 0x7473206D, 0x676E6972, 0x726F6620
    .WORD 0x2074616D, 0x20646D63, 0x69206F74, 0x6765746E, 0x28207265, 0x2079616D, 0x73206562, 0x65676E69
    .WORD 0x200A2964, 0x43202020, 0x204C4C41, 0x696F7461, 0x2020200A, 0x564F4D20, 0x20325220, 0x0A203152
    .WORD 0x20202020, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x2020200A, 0x564F4D20, 0x20315220
    .WORD 0x20313152, 0x20202020, 0x20202020, 0x72203B20, 0x69203131, 0x68742073, 0x6F632065, 0x7265766E
    .WORD 0x6E6F6973, 0x66756220, 0x20726566, 0x206E6F28, 0x63617473, 0x200A296B, 0x43202020, 0x204C4C41
    .WORD 0x6972705F, 0x6E5F746E, 0x65626D75, 0x3B202072, 0x6E697270, 0x68742074, 0x6E692065, 0x65676574
    .WORD 0x20200A72, 0x20422020, 0x72702020, 0x66746E69, 0x6E6F635F, 0x756E6974, 0x700A0A65, 0x746E6972
    .WORD 0x65685F66, 0x200A3A78, 0x43202020, 0x204C4C41, 0x7465665F, 0x615F6863, 0x725F6772, 0x200A0A32
    .WORD 0x4D202020, 0x5220564F, 0x32522031, 0x20202020, 0x20202020, 0x3B202020, 0x766E6F63, 0x20747265
    .WORD 0x626D756E, 0x66207265, 0x206D6F72, 0x69727473, 0x6620676E, 0x616D726F, 0x6D632074, 0x6F742064
    .WORD 0x746E6920, 0x72656765, 0x616D2820, 0x65622079, 0x6E697320, 0x29646567, 0x2020200A, 0x4C414320
    .WORD 0x7461204C, 0x200A696F, 0x4D202020, 0x5220564F, 0x31522032, 0x20200A0A, 0x44412020, 0x39522044
    .WORD 0x20395220, 0x20200A31, 0x4F4D2020, 0x31522056, 0x31315220, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x20313172, 0x74207369, 0x63206568, 0x65766E6F, 0x6F697372, 0x7562206E, 0x72656666, 0x6E6F2820
    .WORD 0x61747320, 0x20296B63, 0x20646E61, 0x6F206F73, 0x6F66206E, 0x746F2072, 0x20726568, 0x766E6F63
    .WORD 0x69737265, 0x20736E6F, 0x706C6568, 0x2E737265, 0x20200A2E, 0x41432020, 0x5F204C4C, 0x6E697270
    .WORD 0x65685F74, 0x20200A78, 0x20422020, 0x72702020, 0x66746E69, 0x6E6F635F, 0x756E6974, 0x700A0A65
    .WORD 0x746E6972, 0x68635F66, 0x0A3A7261, 0x20202020, 0x4C4C4143, 0x65665F20, 0x5F686374, 0x5F677261
    .WORD 0x200A3172, 0x4C202020, 0x52206244, 0x525B2031, 0x20205D31, 0x20202020, 0x3B202020, 0x20746567
    .WORD 0x72616863, 0x20796220, 0x20737469, 0x0A727470, 0x20202020, 0x20444441, 0x52203952, 0x0A312039
    .WORD 0x20202020, 0x4C4C4143, 0x74757020, 0x72616863, 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E
    .WORD 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69, 0x6E69625F, 0x20200A3A, 0x41432020, 0x5F204C4C
    .WORD 0x63746566, 0x72615F68, 0x32725F67, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x31522056, 0x20325220
    .WORD 0x20202020, 0x20202020, 0x633B2020, 0x65766E6F, 0x6E207472, 0x65626D75, 0x72662072, 0x73206D6F
    .WORD 0x6E697274, 0x6F662067, 0x74616D72, 0x646D6320, 0x206F7420, 0x65746E69, 0x20726567, 0x79616D28
    .WORD 0x20656220, 0x676E6973, 0x0A296465, 0x20202020, 0x4C4C4143, 0x6F746120, 0x20200A69, 0x4F4D2020
    .WORD 0x32522056, 0x0A315220, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x2020200A, 0x564F4D20
    .WORD 0x20315220, 0x0A313152, 0x20202020, 0x4C4C4143, 0x72705F20, 0x5F746E69, 0x0A6E6962, 0x20202020
    .WORD 0x20202042, 0x6E697270, 0x635F6674, 0x69746E6F, 0x0A65756E, 0x6972700A, 0x5F66746E, 0x3A74636F
    .WORD 0x2020200A, 0x4C414320, 0x665F204C, 0x68637465, 0x6772615F, 0x0A32725F, 0x2020200A, 0x564F4D20
    .WORD 0x20315220, 0x20203252, 0x20202020, 0x20202020, 0x6F633B20, 0x7265766E, 0x756E2074, 0x7265626D
    .WORD 0x6F726620, 0x7473206D, 0x676E6972, 0x726F6620, 0x2074616D, 0x20646D63, 0x69206F74, 0x6765746E
    .WORD 0x28207265, 0x2079616D, 0x73206562, 0x65676E69, 0x200A2964, 0x43202020, 0x204C4C41, 0x696F7461
    .WORD 0x2020200A, 0x564F4D20, 0x20325220, 0x0A0A3152, 0x20202020, 0x20444441, 0x52203952, 0x0A312039
    .WORD 0x20202020, 0x20564F4D, 0x52203152, 0x200A3131, 0x43202020, 0x204C4C41, 0x6972705F, 0x6F5F746E
    .WORD 0x200A7463, 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66, 0x6E69746E, 0x0A0A6575, 0x6E697270
    .WORD 0x635F6674, 0x69746E6F, 0x3A65756E, 0x20202020, 0x206F743B, 0x746E6F63, 0x65756E69, 0x6F727020
    .WORD 0x73736563, 0x20676E69, 0x6D726F66, 0x73207461, 0x6E697274, 0x20200A67, 0x44412020, 0x38522044
    .WORD 0x20385220, 0x20200A31, 0x20422020, 0x72702020, 0x66746E69, 0x6F6F6C5F, 0x700A0A70, 0x746E6972
    .WORD 0x6F645F66, 0x0A3A656E, 0x20202020, 0x20444441, 0x53205053, 0x30382050, 0x2020200A, 0x504F5020
    .WORD 0x32315220, 0x2020200A, 0x504F5020, 0x31315220, 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A
    .WORD 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52
    .WORD 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72705F20, 0x5F746E69
    .WORD 0x69727473, 0x2D20676E, 0x69725720, 0x61206574, 0x6C756E20, 0x9180E26C, 0x6D726574, 0x74616E69
    .WORD 0x73206465, 0x6E697274, 0x6F742067, 0x64747320, 0x2074756F, 0x206F6E28, 0x6C77656E, 0x29656E69
    .WORD 0x3B0A3B0A, 0x65735520, 0x68742073, 0x696C2065, 0x60206362, 0x74697277, 0x77206065, 0x70706172
    .WORD 0x28207265, 0x202C6466, 0x66667562, 0x202C7265, 0x296E656C, 0x736E6920, 0x64616574, 0x20666F20
    .WORD 0x65726964, 0x53207463, 0x0A2E4356, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x6F70203D, 0x65746E69
    .WORD 0x6F742072, 0x72747320, 0x0A676E69, 0x554F203B, 0x6E203A54, 0x0A656E6F, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x6972705F, 0x735F746E, 0x6E697274, 0x200A3A67, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x4D202020
    .WORD 0x5220564F, 0x31522038, 0x2020200A, 0x4C414320, 0x7473204C, 0x6E656C72, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x20315220, 0x656C203D, 0x6874676E, 0x2020200A, 0x564F4D20, 0x20395220
    .WORD 0x200A3152, 0x4C202020, 0x52202049, 0x54532031, 0x54554F44, 0x0A44465F, 0x20202020, 0x20564F4D
    .WORD 0x52203252, 0x20200A38, 0x4F4D2020, 0x33522056, 0x0A395220, 0x20202020, 0x4C4C4143, 0x69727720
    .WORD 0x20206574, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x6362696C, 0x61727720, 0x72657070
    .WORD 0x6F6E202C, 0x69642074, 0x74636572, 0x43565320, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020
    .WORD 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x705F203B, 0x746E6972, 0x6D756E5F, 0x20726562, 0x6F46202D
    .WORD 0x74616D72, 0x646E6120, 0x69727020, 0x6120746E, 0x67697320, 0x2064656E, 0x65746E69, 0x20726567
    .WORD 0x65737528, 0x74692073, 0x645F616F, 0x0A296365, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x6564203D
    .WORD 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666, 0x756D2820, 0x62207473, 0x89E22065, 0x203331A5
    .WORD 0x65747962, 0x3B0A2973, 0x20202020, 0x32522020, 0x73203D20, 0x656E6769, 0x6E692064, 0x65676574
    .WORD 0x203B0A72, 0x3A54554F, 0x6E6F6E20, 0x2D3B0A65, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x705F0A2D
    .WORD 0x746E6972, 0x6D756E5F, 0x3A726562, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x4C414320
    .WORD 0x7469204C, 0x645F616F, 0x20206365, 0x20202020, 0x20202020, 0x3B202020, 0x65737520, 0x31522073
    .WORD 0x75622820, 0x72656666, 0x6E612029, 0x32522064, 0x61762820, 0x2965756C, 0x2020200A, 0x564F4D20
    .WORD 0x20315220, 0x20203152, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x20315220, 0x6C697473
    .WORD 0x6F70206C, 0x73746E69, 0x206F7420, 0x66667562, 0x73207265, 0x74726174, 0x2020200A, 0x4C414320
    .WORD 0x705F204C, 0x746E6972, 0x7274735F, 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020
    .WORD 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x705F203B, 0x746E6972, 0x7865685F
    .WORD 0x46202D20, 0x616D726F, 0x6E612074, 0x72702064, 0x20746E69, 0x75206E61, 0x6769736E, 0x2064656E
    .WORD 0x65746E69, 0x20726567, 0x68206E69, 0x28207865, 0x73657375, 0x6F746920, 0x65685F61, 0x3B0A2978
    .WORD 0x49203B0A, 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x20726566
    .WORD 0x73756D28, 0x65622074, 0xA589E220, 0x79622039, 0x29736574, 0x20203B0A, 0x20202020, 0x3D203252
    .WORD 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x3A54554F, 0x6E6F6E20, 0x2D3B0A65
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x705F0A2D, 0x746E6972, 0x7865685F, 0x20200A3A, 0x55502020
    .WORD 0x4C204853, 0x20200A52, 0x41432020, 0x69204C4C, 0x5F616F74, 0x0A786568, 0x20202020, 0x20564F4D
    .WORD 0x52203152, 0x20200A31, 0x41432020, 0x5F204C4C, 0x6E697270, 0x74735F74, 0x676E6972, 0x2020200A
    .WORD 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x5F203B0A, 0x6E697270, 0x65685F74, 0x202D2078, 0x6D726F46, 0x61207461, 0x7020646E, 0x746E6972
    .WORD 0x206E6120, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x206E6920, 0x20786568, 0x65737528
    .WORD 0x74692073, 0x685F616F, 0x0A297865, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x6564203D, 0x6E697473
    .WORD 0x6F697461, 0x7562206E, 0x72656666, 0x756D2820, 0x62207473, 0x89E22065, 0x622039A5, 0x73657479
    .WORD 0x203B0A29, 0x20202020, 0x20325220, 0x6E75203D, 0x6E676973, 0x69206465, 0x6765746E, 0x3B0A7265
    .WORD 0x54554F20, 0x6F6E203A, 0x3B0A656E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F0A2D2D, 0x6E697270
    .WORD 0x69625F74, 0x200A3A6E, 0x50202020, 0x20485355, 0x200A524C, 0x43202020, 0x204C4C41, 0x616F7469
    .WORD 0x6E69625F, 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3152, 0x43202020, 0x204C4C41, 0x6972705F
    .WORD 0x735F746E, 0x6E697274, 0x20200A67, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6972705F, 0x6F5F746E, 0x2D207463, 0x726F4620
    .WORD 0x2074616D, 0x20646E61, 0x6E697270, 0x6E612074, 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574
    .WORD 0x6E692072, 0x74636F20, 0x28206C61, 0x73657375, 0x6F746920, 0x636F5F61, 0x3B0A2974, 0x49203B0A
    .WORD 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x20726566, 0x73756D28
    .WORD 0x65622074, 0xA589E220, 0x79622039, 0x29736574, 0x20203B0A, 0x20202020, 0x3D203252, 0x736E7520
    .WORD 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x3A54554F, 0x6E6F6E20, 0x2D3B0A65, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x705F0A2D, 0x746E6972, 0x74636F5F, 0x20200A3A, 0x55502020, 0x4C204853
    .WORD 0x20200A52, 0x41432020, 0x69204C4C, 0x5F616F74, 0x0A74636F, 0x20202020, 0x20564F4D, 0x52203152
    .WORD 0x20200A31, 0x41432020, 0x5F204C4C, 0x6E697270, 0x74735F74, 0x676E6972, 0x2020200A, 0x504F5020
    .WORD 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x44203B0A
    .WORD 0x20617461, 0x74636553, 0x0A6E6F69, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x63617073
    .WORD 0x74735F65, 0x200A3A72, 0x2E202020, 0x49435341, 0x22205A49, 0x0A0A2220, 0x6C77656E, 0x5F656E69
    .WORD 0x3A727473, 0x2020200A, 0x53412E20, 0x5A494943, 0x6E5C2220, 0x630A0A22, 0x75625F68, 0x200A3A66
    .WORD 0x2E202020, 0x49435341, 0x22205A49, 0x0A22305C, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x61203B0A, 0x0A696F74, 0x203B0A3B, 0x766E6F43, 0x20747265, 0x69636564, 0x206C616D, 0x49435341
    .WORD 0x74732049, 0x676E6972, 0x206F7420, 0x6E676973, 0x69206465, 0x6765746E, 0x0A2E7265, 0x203B0A3B
    .WORD 0x0A3A4E49, 0x2020203B, 0x3D203152, 0x72747320, 0x20676E69, 0x6E696F70, 0x0A726574, 0x203B0A3B
    .WORD 0x3A54554F, 0x20203B0A, 0x20315220, 0x6E69203D, 0x65676574, 0x0A3B0A72, 0x7553203B, 0x726F7070
    .WORD 0x0A3A7374, 0x2020203B, 0x33323122, 0x203B0A22, 0x2D222020, 0x22333231, 0x20203B0A, 0x22302220
    .WORD 0x3B0A3B0A, 0x6E694D20, 0x6C616D69, 0x33524B20, 0x6D692032, 0x6D656C70, 0x61746E65, 0x6E6F6974
    .WORD 0x2D3B0A2E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x610A0A2D, 0x3A696F74, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A
    .WORD 0x53555020, 0x31522048, 0x200A0A30, 0x4D202020, 0x5220564F, 0x31522038, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x3D203852, 0x72747320, 0x0A676E69, 0x20202020, 0x2020494C, 0x30203952, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x20395220, 0x6572203D, 0x746C7573, 0x2020200A, 0x20494C20, 0x30315220
    .WORD 0x20203020, 0x20202020, 0x20202020, 0x3152203B, 0x203D2030, 0x6167656E, 0x65766974, 0x616C6620
    .WORD 0x200A0A67, 0x3B202020, 0x65684320, 0x27206B63, 0x200A272D, 0x4C202020, 0x52204244, 0x525B2032
    .WORD 0x200A5D38, 0x43202020, 0x5220504D, 0x35342032, 0x20202020, 0x20202020, 0x203B2020, 0x0A272D27
    .WORD 0x20202020, 0x20454E42, 0x696F7461, 0x6F6F6C5F, 0x20200A70, 0x494C2020, 0x30315220, 0x200A3120
    .WORD 0x41202020, 0x52204444, 0x38522038, 0x610A3120, 0x5F696F74, 0x706F6F6C, 0x20200A3A, 0x444C2020
    .WORD 0x32522042, 0x38525B20, 0x20200A5D, 0x203B2020, 0x20646E65, 0x7320666F, 0x6E697274, 0x20200A67
    .WORD 0x4D432020, 0x32522050, 0x200A3020, 0x42202020, 0x61205145, 0x5F696F74, 0x656E6F64, 0x2020200A
    .WORD 0x6F203B20, 0x20796C6E, 0x65636361, 0x27207470, 0x2E2E2730, 0x0A273927, 0x20202020, 0x20504D43
    .WORD 0x34203252, 0x20202038, 0x20202020, 0x3027203B, 0x20200A27, 0x4C422020, 0x74612054, 0x645F696F
    .WORD 0x0A656E6F, 0x20202020, 0x20504D43, 0x35203252, 0x20202037, 0x20202020, 0x3927203B, 0x20200A27
    .WORD 0x47422020, 0x74612054, 0x645F696F, 0x0A656E6F, 0x2020200A, 0x64203B20, 0x74696769, 0x63203D20
    .WORD 0x20726168, 0x3027202D, 0x20200A27, 0x55532020, 0x32522042, 0x20325220, 0x0A0A3834, 0x20202020
    .WORD 0x6572203B, 0x746C7573, 0x72203D20, 0x6C757365, 0x202A2074, 0x2B203031, 0x67696420, 0x200A7469
    .WORD 0x4C202020, 0x52202049, 0x30312033, 0x2020200A, 0x4C554D20, 0x20395220, 0x52203952, 0x20200A33
    .WORD 0x44412020, 0x39522044, 0x20395220, 0x200A3252, 0x41202020, 0x52204444, 0x38522038, 0x200A3120
    .WORD 0x42202020, 0x6F746120, 0x6F6C5F69, 0x610A706F, 0x5F696F74, 0x656E6F64, 0x20200A3A, 0x4D432020
    .WORD 0x31522050, 0x0A312030, 0x20202020, 0x20454E42, 0x696F7461, 0x736F705F, 0x76697469, 0x20200A65
    .WORD 0x203B2020, 0x6167656E, 0x4E206574, 0x3D204745, 0x20200A29, 0x4F4E2020, 0x39522054, 0x0A395220
    .WORD 0x20202020, 0x20444441, 0x52203952, 0x0A312039, 0x696F7461, 0x736F705F, 0x76697469, 0x200A3A65
    .WORD 0x4D202020, 0x5220564F, 0x39522031, 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A, 0x504F5020
    .WORD 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020
    .WORD 0x00000054, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

    .SPACE 1024
tarfs_end:
0x000EB600    nop
