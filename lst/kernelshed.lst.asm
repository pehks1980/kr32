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
0x00001008       ENABLEINT

idle_loop:
0x0000100C       ADD R1 R1 1


    ;DEBUG 10
0x00001010       B idle_loop

nsfs_bmi_demo:
0x00001018       PUSH LR
    ;------------------------------------------------------
    ; NSFS/BMI demo sequence from system task 0.
    ; Recreates namespace 0, creates a file, appends bytes, then deletes it.
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

0x00001054       MOV R1 FILE_CREATE
0x00001058       LI R2 cr_file
0x00001060       LI R3 13
0x00001068       LI R4 0
0x00001070   CALL bmi_call

0x00001078       MOV R1 FILE_APPEND
0x0000107C       LI R2 cr_file_append_payload
0x00001084       LI R3 21
0x0000108C       LI R4 0
0x00001094   CALL bmi_call

0x0000109C       MOV R1 FILE_APPEND
0x000010A0       LI R2 cr_file_append_payload1
0x000010A8       LI R3 21
0x000010B0       LI R4 0
0x000010B8   CALL bmi_call

   ; MOV R1 FILE_DELETE
   ; LI R2 cr_file
   ; LI R3 13
   ; LI R4 0
   ; CALL bmi_call

0x000010C0       POP LR
0x000010C4       RET

cr_file:
    .asciiz "etc/crash.txt"

cr_file_append_payload:
    .WORD 0x0000000D    ; path length = 13
    .WORD 0x2F637465    ; "etc/"
    .WORD 0x73617263    ; "cras"
    .WORD 0x78742E68    ; "h.tx"
    .WORD 0x43424174    ; "tABC"
    .WORD 0x0000000A    ; "\n"

cr_file_append_payload1:
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
    .WORD syscall_mkdir         ; SVC 17
    .WORD syscall_rmdir         ; SVC 18



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

0x00002638       LDW R8 [SP + TF_R1]        ; user path pointer

0x0000263C       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00002640       PUSH R9

0x00002644       MOV R1 R8
0x00002648       BL copy_path_from_user
0x00002650       CMP R1 0
0x00002654       BEQ execve_badfault

0x0000265C       MOV R12 R1                ; kernel pointer to copied pathname

0x00002660       MOV R1 R12
0x00002664       BL vfs_lookup             ; lookup inode for the file
0x0000266C       CMP R1 0
0x00002670       BEQ execve_noent

0x00002678       MOV R9 R1                 ; inode*
0x0000267C       LDW R1 [R9 + INODE_TYPE]
0x00002680       LI R2 INODE_DIR
0x00002688       CMP R1 R2
0x0000268C       BEQ execve_noexec           ; if the inode is a directory, we cannot execute it

0x00002694       LDW R3 [R9 + INODE_SIZE]
0x00002698       LI R4 PAGE_SIZE         ; 4096 bytes
0x000026A0       CMP R3 R4
0x000026A4       BGT execve_noexec       ; if the inode size is greater than a page, we cannot execute it

0x000026AC       BL file_alloc
0x000026B4       CMP R1 0
0x000026B8       BEQ execve_nomem         ; if we cannot allocate a file for this inode, return error

0x000026C0       MOV R10 R1                ; file*
0x000026C4       MOV R1 R10
0x000026C8       MOV R2 R9
0x000026CC       LI R3 FD_FLAG_READ
0x000026D4       BL file_init            ; initialize the file structure for reading the executable

0x000026DC       BL page_alloc           ; allocate a new page for the executable code of execve program
0x000026E4       CMP R1 0
0x000026E8       BEQ execve_noexec_file

0x000026F0       MOV R11 R1                ; new code page PA for execve program

; macro: GET_CURR_TASK_IDX R4    ; get current task index
0x000026F4   LI R1 CURRENT_TASK
0x000026FC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00002700   LI R1 TASK_SIZE
0x00002708   MUL R3 R4 R1
0x0000270C   LI R5 tasks
0x00002714   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12, R5 ; preserve old exec code page PA for rollback / cleanup
0x00002718   LDW R12 [R5 + TASK_CODE_PAGE]
; macro: TASK_GET_PTBR R1, R5       ; R1 = PTBR of current task
0x0000271C   LDW R1 [R5 + TASK_PTBR]
0x00002720       LI R2 USER_CODE_VA         ; R2 = code page VA for execve program
0x00002728       MOV R3 R11                 ; R3 = code page PA for execve program
0x0000272C       LI R4 USER_RW              ; R4 = temporary RW permissions so we can load the page
0x00002734       BL map_page_rt             ; runtime map executable page RW at USER_CODE_VA for loading

; macro: TASK_GET_DATA_PAGE R1, R5  ; get data page PA for current task
0x0000273C   LDW R1 [R5 + TASK_DATA_PAGE]
0x00002740       CMP R1 0
0x00002744       BEQ execve_data_ok         ; if the task has no data page, skip clearing it
0x0000274C       LI R3 PAGE_SIZE
0x00002754       BL mem_zero                ; zero the current task data page before execve starts

execve_data_ok:

0x0000275C       MOV R1 R10              ; file* of execve program
0x00002760       LI R2 USER_CODE_VA      ; VA of code page for execve program
0x00002768       LI R3 PAGE_SIZE         ; size of code page for execve program
0x00002770       BL file_read            ; load executable into USER_CODE_VA
0x00002778       CMP R1 0
0x0000277C       BLT execve_read_fail    ; if read fails, restore old exec code page and return error

0x00002784       MOV R1 R10              ; file* of execve program
0x00002788       BL file_put             ; release file resources after successful load

; macro: GET_CURR_TASK_IDX R4    ; this was real mistake here! I forgot to retore current task ptr
0x00002790   LI R1 CURRENT_TASK
0x00002798   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4     ; reload task ptr after calls that may clobber caller-saved R5
0x0000279C   LI R1 TASK_SIZE
0x000027A4   MUL R3 R4 R1
0x000027A8   LI R5 tasks
0x000027B0   ADD R5 R5 R3
                            ; we also added INVLPG - for good! - history comments
    ; commit new exec state after successful file load
0x000027B4       LI R1 USER_CODE_VA
; macro: TASK_SET_PC R5, R1              ; start execution at USER_CODE_VA
0x000027BC   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5, R11      ; remember physical page backing this user code
0x000027C0   STW R11 [R5 + TASK_CODE_PAGE]
0x000027C4       LI R1 USER_STACK_TOP
; macro: TASK_SET_USP R5, R1             ; reset user stack pointer
0x000027CC   STW R1 [R5 + TASK_USP]
0x000027D0       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5, R1           ; reset program break into the task's data page
0x000027D8   STW R1 [R5 + TASK_BREAK]

    ; Remap the new code page read-only before handing control over
; macro: TASK_GET_PTBR R1, R5            ; get PTBR of current task
0x000027DC   LDW R1 [R5 + TASK_PTBR]
0x000027E0       LI R2 USER_CODE_VA              ; VA of code page for execve program
0x000027E8       MOV R3 R11                      ; PA of code page for execve program
0x000027EC       LI R4 KERNEL_USER_ALL
0x000027F4       BL map_page_rt                  ; switch the new code page from RW to RX

   ; DEBUG 2

0x000027FC       CMP R12 0                       ; R12 = old code page PA for execve program from task metadata
0x00002800       BEQ execve_commit_done          ; if no previous code page, skip freeing it
0x00002808       MOV R1 R12
0x0000280C       BL page_put                    ; free the old exec code page now that the new one is committed

execve_commit_done:
    ; Build a fresh Unix-style initial stack:
    ;   [argc][argv pointers...][NULL][string data...]
    ; The new program can read argc/argv from the stack, and we also mirror
    ; argc/argv into R1/R2 for convenience.

0x00002814       POP R4                         ; remember argv ptr from start of syscall_execve
0x00002818       LI R6 0                        ; R6 = argc counter

    ; Step 1: Count argc - walk on argv ptrs count argc till  we find NULL check above
0x00002820       MOV R7 R4
execve_argv_count_loop:
0x00002824       CMP R7 0
0x00002828       BEQ execve_argv_count_done
0x00002830       LDW R8 [R7]
0x00002834       CMP R8 0
0x00002838       BEQ execve_argv_count_done

0x00002840       CMP R6 16                      ;MAX argc count
0x00002844       BGE execve_badfault

0x0000284C       ADD R6 R6 1
0x00002850       ADD R7 R7 4
0x00002854       B execve_argv_count_loop

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
0x0000285C       LI  R5 USER_STACK_TOP

    ;-------------------------------------------------------------
    ; Temporary kernel array for argv pointers.
    ; argv_tmp[16]
    ;-------------------------------------------------------------
0x00002864       LI  R11 execve_tmp_argv

    ;-------------------------------------------------------------
    ; Copy strings in reverse order so they naturally pack downward.
    ;-------------------------------------------------------------
0x0000286C       MOV R7 R6
0x00002870       SUB R7 R7 1             ; [argc]-1

execve_copy_reverse:        ; R7(i) = (argc-1 ... 0)
0x00002874       LI  R8 -1
0x0000287C       CMP R7 R8
0x00002880       BEQ execve_strings_done

    ; source string = argv[i] starting from last arg string
0x00002888       MOV R8 R7
0x0000288C       SHL R8 R8 2             ;R7(i)*4+argv ptr => R9(&argv[i])
0x00002890       ADD R9 R4 R8
0x00002894       LDW R10 [R9]            ;get string ptr from last argv[argc-1] (in first iteration)

    ;-------------------------------------------------------------
    ; strlen()
    ; R12 = length including terminating NUL
    ;-------------------------------------------------------------
0x00002898       LI R12 0                ;str len ctr - compute this argv string len (+ 0)

execve_strlen:

0x000028A0       LDB R2 [R10 + R12]
0x000028A4       ADD R12 R12 1
0x000028A8       CMP R2 0
0x000028AC       BNE execve_strlen

    ; reserve space - on user stack top this argv string destination

0x000028B4       SUB R5 R5 R12               ; R5 dest addres argv string copy to gets updated by lenght of each string
                                ; to be copied to tmp

    ; remember destination pointer
0x000028B8       MOV R8 R7
0x000028BC       SHL R8 R8 2                 ;R7 argv string number in argv array
0x000028C0       ADD R9 R11 R8               ;r9=&temp argv[i]  which is = R7(i)*4+&temp argv[] array storage
0x000028C4       STW R5 [R9]                 ;R5->[R9] string pointer on user stack

    ; memcpy()
0x000028C8       LI R8 0

execve_copy_string:             ; first copy strings ptrs from (argv array) to temp storage
                                ; from last string to first - opposite order
0x000028D0       LDB R2 [R10 + R8]           ; R10 execv argv &string[i]  (last to first)
0x000028D4       STB R2 [R5 + R8]            ; R5 same in tmp

0x000028D8       CMP R2 0
0x000028DC       BEQ execve_copy_done

0x000028E4       ADD R8 R8 1                 ; to next char in string
0x000028E8       B execve_copy_string

execve_copy_done:

0x000028F0       SUB R7 R7 1                 ; to copy next string
0x000028F4       B execve_copy_reverse

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
0x000028FC       MOV R7 R6
0x00002900       ADD R7 R7 2

0x00002904       MOV R8 R7
0x00002908       SHL R8 R8 2

0x0000290C       SUB R5 R5 R8            ;update R5 by stack words

    ;-------------------------------------------------------------
    ; R5 now becomes initial user stack pointer.
    ;-------------------------------------------------------------

0x00002910       STW R6 [R5]             ; put argc to user stack see picture above (Reserve space for:)

0x00002914       ADD R9 R5 4             ; R9 - move 'writing head' to next element argv in user stack
                            ; R5 - initial user stack pointer
    ;-------------------------------------------------------------
    ; argv data copied. now - Copy argv pointers
    ;-------------------------------------------------------------
0x00002918       LI R7 0

execve_copy_argv:

0x00002920       CMP R7 R6
0x00002924       BEQ execve_copy_argv_done

0x0000292C       MOV R8 R7
0x00002930       SHL R8 R8 2              ; R7 argv index

0x00002934       LDW R12 [R11 + R8]       ; we copy stings pointers here (not actual strings!)
                             ; R11 - &execve_tmp_argv
0x00002938       STW R12 [R9 + R8]        ; R9 - write head on user stack

0x0000293C       ADD R7 R7 1
0x00002940       B execve_copy_argv

execve_copy_argv_done:

    ; argv[argc] = NULL
0x00002948       MOV R8 R6
0x0000294C       SHL R8 R8 2
0x00002950       ADD R10 R9 R8

0x00002954       LI R12 0
0x0000295C       STW R12 [R10]               ; write NuLL - finish form user stack frame (arguments part!)

    ;-------------------------------------------------------------
    ; Prepare trapframe for new process.
    ;-------------------------------------------------------------

0x00002960       STW R6 [SP + TF_R1]      ; argc

0x00002964       MOV R1 R9
0x00002968       STW R1 [SP + TF_R2]      ; argv

0x0000296C       LI R1 0
0x00002974       STW R1 [SP + TF_R3]      ; envp

0x00002978       STW R5 [SP + TF_USP]     ; initial user SP


    ; Prepare a fresh user register state for the new program.
0x0000297C       LI R1 0
0x00002984       STW R1 [SP + TF_R4]
0x00002988       STW R1 [SP + TF_R5]
0x0000298C       STW R1 [SP + TF_R6]
0x00002990       STW R1 [SP + TF_R7]
0x00002994       STW R1 [SP + TF_R8]
0x00002998       STW R1 [SP + TF_R9]
0x0000299C       STW R1 [SP + TF_R10]
0x000029A0       STW R1 [SP + TF_R11]
0x000029A4       STW R1 [SP + TF_R12]
0x000029A8       LI R1   USER_CODE_VA               ; user execve program entry point
0x000029B0       STW R1 [SP + TF_SEPC]              ; set SEPC to the new program entry point

0x000029B4       B trap_restore                     ; restore kernel trapframe and start user execution at user_code_va

; as it should be clear
; if fail occured we rollback depending at what stage fail occured and free used resources
; then we exit back to child process with fail exit code
execve_read_fail:
0x000029BC       MOV R1 R11
0x000029C0       BL page_put                    ; put-free the failed new code page

; macro: GET_CURR_TASK_IDX R4
0x000029C8   LI R1 CURRENT_TASK
0x000029D0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4           ; reload task ptr before restoring USER_CODE_VA mapping
0x000029D4   LI R1 TASK_SIZE
0x000029DC   MUL R3 R4 R1
0x000029E0   LI R5 tasks
0x000029E8   ADD R5 R5 R3

0x000029EC       CMP R12 0
0x000029F0       BEQ execve_restore_no_prev
; macro: TASK_GET_PTBR R1, R5
0x000029F8   LDW R1 [R5 + TASK_PTBR]
0x000029FC       LI R2 USER_CODE_VA
0x00002A04       MOV R3 R12
0x00002A08       LI R4 USER_RX
0x00002A10       BL map_page_rt                ; restore previous exec page mapping at USER_CODE_VA
0x00002A18       MOV R1 R12
; macro: TASK_SET_CODE_PAGE R5, R12    ; restore previous exec code page pointer
0x00002A1C   STW R12 [R5 + TASK_CODE_PAGE]
0x00002A20       B execve_restore_done

execve_restore_no_prev:
; macro: TASK_GET_PTBR R1, R5
0x00002A28   LDW R1 [R5 + TASK_PTBR]
0x00002A2C       LI R2 USER_CODE_VA
0x00002A34       LI R3 0
0x00002A3C       LI R4 0
0x00002A44       BL map_page_rt                ; unmap USER_CODE_VA if there was no previous code page
0x00002A4C       LI R1 0
; macro: TASK_SET_CODE_PAGE R5, R1
0x00002A54   STW R1 [R5 + TASK_CODE_PAGE]

execve_restore_done:
0x00002A58       MOV R1 R10
0x00002A5C       BL file_put

0x00002A64       POP R1                      ;save stack
0x00002A68       LI R1 ERR_NOEXEC
0x00002A70       STW R1 [SP + TF_R1]
0x00002A74       B trap_restore

execve_nomem_file:
0x00002A7C       MOV R1 R10
0x00002A80       BL file_put

0x00002A88       POP R1
0x00002A8C       LI R1 ERR_NOMEM
0x00002A94       STW R1 [SP + TF_R1]
0x00002A98       B trap_restore

execve_nomem:
0x00002AA0       POP R1
0x00002AA4       LI R1 ERR_NOMEM
0x00002AAC       STW R1 [SP + TF_R1]
0x00002AB0       B trap_restore

execve_noexec_file:

0x00002AB8       MOV R1 R10
0x00002ABC       BL file_put
execve_noexec:
0x00002AC4       POP R1
0x00002AC8       LI R1 ERR_NOEXEC
0x00002AD0       STW R1 [SP + TF_R1]
0x00002AD4       B trap_restore

execve_noent:
0x00002ADC       POP R1
0x00002AE0       LI R1 ERR_NOENT
0x00002AE8       STW R1 [SP + TF_R1]
0x00002AEC       B trap_restore

execve_badfault:
0x00002AF4       POP R1
0x00002AF8       LI R1 ERR_FAULT
0x00002B00       STW R1 [SP + TF_R1]
0x00002B04       B trap_restore

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

0x00003218       LDW R8 [SP + TF_R1]        ; user path pointer
0x0000321C       LDW R9 [SP + TF_R2]        ; user argv pointer
0x00003220       MOV R11 R9                 ; save to R11

0x00003224       LI  R1 exec_path
0x0000322C       MOV R2 R8
0x00003230       LI  R3 EXEC_MAX_PATH
0x00003238       BL copy_user_string        ;copy path string to ws
0x00003240       CMP R1 0
0x00003244       BEQ execve_badfault

    ;init execve ws
0x0000324C       LI R1 exec_argc
0x00003254       LI R2 0
0x0000325C       STW R2 [R1]

    ;count argc

0x00003260       MOV R8 R9               ; user argv
0x00003264       LI  R6 0                ; argc
;count ptrs in array of ptrs argv till 0 -null end
argc_loop:
0x0000326C       CMP R8 0                ;if no argv 0-null
0x00003270       BEQ argc_done
0x00003278       LDW R3 [R8]
0x0000327C       CMP R3 0                ;if end
0x00003280       BEQ argc_done
0x00003288       CMP R6 EXEC_MAX_ARGS    ;if too much MAX argc count
0x0000328C       BGE exec_badfault
0x00003294       ADD R6 R6 1
0x00003298       ADD R8 R8 4
0x0000329C       B argc_loop
argc_done:
0x000032A4       LI R1 exec_argc         ;store it to ws
0x000032AC       STW R6 [R1]

0x000032B0       MOV R9 R6               ;R9 argc R11 user argv pointer
0x000032B4       MOV R8 R11
0x000032B8       BL  copy_argv_strings   ;fill arrays in ws from argvs
0x000032C0       CMP R1 0
0x000032C4       BNE exec_fail

0x000032CC       LI R1 exec_path
    ; load exec image to allocted memory
    ; map_rt pages
0x000032D4       BL exec_load_binary
0x000032DC       CMP R1 0
0x000032E0       BEQ exec_fail

0x000032E8       MOV R11 R1        ; new code page
0x000032EC       MOV R12 R2        ; old code page
0x000032F0       BL exec_build_stack_image
0x000032F8       CMP R1 0
0x000032FC       BNE exec_rollback

0x00003304       MOV R1 R11
0x00003308       MOV R2 R12

0x0000330C       B exec_commit_image

exec_badfault:
0x00003314       NOP
exec_fail:
0x00003318       NOP
exec_rollback:
0x0000331C       LI R1 ERR_FAULT
0x00003324       STW R1 [SP + TF_R1]
0x00003328       B trap_restore
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

0x00003330       MOV R11 R1              ; new page
0x00003334       MOV R12 R2              ; old page

; macro: GET_CURR_TASK_IDX R4
0x00003338   LI R1 CURRENT_TASK
0x00003340   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x00003344   LI R1 TASK_SIZE
0x0000334C   MUL R3 R4 R1
0x00003350   LI R5 tasks
0x00003358   ADD R5 R5 R3

0x0000335C       LI  R1 exec_stack_used
0x00003364       LDW R8 [R1]
0x00003368       LI  R9 USER_STACK_TOP
0x00003370       SUB R9 R9 R8            ; final user SP
0x00003374       MOV R1 R9               ;  R2->R9 len R8 - cpy our image for stack
0x00003378       LI  R2 exec_stack_image
0x00003380       MOV R3 R8
0x00003384       BL memcpy

0x0000338C       LI R1 USER_CODE_VA      ; commit task state:
; macro: TASK_SET_PC R5,R1       ; PC starts to USER_CODE_VA
0x00003394   STW R1 [R5 + TASK_PC]
; macro: TASK_SET_CODE_PAGE R5,R11 ; set new code page (tab+pages)
0x00003398   STW R11 [R5 + TASK_CODE_PAGE]
0x0000339C       MOV R1 R9
; macro: TASK_SET_USP R5,R1        ; set USP
0x000033A0   STW R1 [R5 + TASK_USP]
0x000033A4       LI R1 HEAP_START
; macro: TASK_SET_BREAK R5,R1      ; set BRK
0x000033AC   STW R1 [R5 + TASK_BREAK]

    ; Make sure the task's fixed user stack page is still mapped RW before
    ; returning to user mode. execve rewrites the stack contents, but the
    ; page-table entry must remain valid even if the task was previously
    ; switched through another path.
; macro: TASK_GET_PTBR R2,R5
0x000033B0   LDW R2 [R5 + TASK_PTBR]
; macro: TASK_GET_USTACK_PAGE R3,R5
0x000033B4   LDW R3 [R5 + TASK_USTACK_PAGE]
0x000033B8       CMP R3 0
0x000033BC       BEQ exec_commit_skip_stack_map
    ; ---- remap new code pages to RW ---- don know why
0x000033C4       MOV R1 R11
0x000033C8       LI R3 USER_CODE_VA
0x000033D0       LI R4 USER_RW
0x000033D8       BL pages_map_table

  ;  LI R2 USER_STACK_VA
  ;  LI R4 USER_RW
  ;  BL map_page_rt

exec_commit_skip_stack_map:

; macro: TASK_GET_PTBR R2,R5
0x000033E0   LDW R2 [R5 + TASK_PTBR]
0x000033E4       MOV R1 R11
0x000033E8       LI R3 USER_CODE_VA
0x000033F0       LI R4 KERNEL_USER_ALL
0x000033F8       BL pages_map_table

;    LI R2 USER_CODE_VA
;    MOV R3 R11
;    LI R4 KERNEL_USER_ALL   ; map code page RX subject to permissions on X (now all X)
;    BL map_page_rt

0x00003400       CMP R12 0               ; free old pa page (R12) if have
0x00003404       BEQ no_old_page

0x0000340C       MOV R1 R12
0x00003410       BL pages_free_table     ; ---- free old codepage (table and pages) ----

   ; BL page_put             ; free page
no_old_page:

0x00003418       LI  R1 exec_argc
0x00003420       LDW R2 [R1]
0x00003424       STW R2 [SP+TF_R1]

0x00003428       MOV R1 R9
0x0000342C       ADD R1 R1 4
0x00003430       STW R1 [SP+TF_R2]       ; user sp with image on top + 4 so it points to &argv image

0x00003434       LI R1 0                 ; envp
0x0000343C       STW R1 [SP+TF_R3]

0x00003440       STW R9 [SP+TF_USP]      ; user sp

0x00003444       LI R1 0
0x0000344C       STW R1 [SP+TF_R4]
0x00003450       STW R1 [SP+TF_R5]
0x00003454       STW R1 [SP+TF_R6]
0x00003458       STW R1 [SP+TF_R7]
0x0000345C       STW R1 [SP+TF_R8]
0x00003460       STW R1 [SP+TF_R9]
0x00003464       STW R1 [SP+TF_R10]
0x00003468       STW R1 [SP+TF_R11]
0x0000346C       STW R1 [SP+TF_R12]

0x00003470       LI R1 USER_CODE_VA
0x00003478       STW R1 [SP+TF_SEPC]

  ;  POP R12
  ;  POP R11
  ;  POP R10
  ;  POP R9
  ;  POP R8
  ;  POP LR

0x0000347C       B trap_restore



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
0x00003484       PUSH LR
0x00003488       PUSH R8
0x0000348C       PUSH R9
0x00003490       PUSH R10
0x00003494       PUSH R11
0x00003498       PUSH R12

0x0000349C       LI   R1 exec_argc   ;argc
0x000034A4       LDW  R6 [R1]

0x000034A8       MOV  R7 R6          ;pointer_bytes = (argc+2)*4
0x000034AC       ADD  R7 R7 2
0x000034B0       SHL  R7 R7 2

0x000034B4       LI   R1 exec_strings_used   ; strings blob len
0x000034BC       LDW  R8 [R1]

    ;----------------------------------------------------------
    ; total = pointer_bytes(len argv ptr array + 4b argc) + string_bytes(len string blobs)
    ;----------------------------------------------------------

0x000034C0       ADD  R9 R7 R8
    ; check for MAX
0x000034C4       LI   R1 EXEC_STACK_SIZE
0x000034CC       CMP  R9 R1
0x000034D0       BGT  exec_stack_nomem

0x000034D8       LI   R1 exec_stack_used     ; save used size
0x000034E0       STW  R9 [R1]

0x000034E4       LI   R10 exec_stack_image   ;stack base for image
    ; building image for stack as on picture
0x000034EC       STW  R6 [R10]   ;argc

    ; copy string blob
0x000034F0       MOV  R1 R10
0x000034F4       ADD  R1 R1 R7   ; skip room for pointer_bytes see picture
0x000034F8       LI   R2 exec_strings
0x00003500       MOV  R3 R8      ; blob len
0x00003504       BL   memcpy

    ;----------------------------------------------------------
    ; future user addresses
    ;----------------------------------------------------------

0x0000350C       LI   R11 USER_STACK_TOP
0x00003514       SUB  R11 R11 R9             ; r9 total image len, R11 start address image in the user stack
0x00003518       MOV  R12 R11
0x0000351C       ADD  R12 R12 R7             ; r12 pointer bytes ptr in image in stack - start of string blob

    ;----------------------------------------------------------
    ; argv table build
    ;----------------------------------------------------------

0x00003520       ADD  R10 R10 4              ; argv[0] starts after argc
0x00003524       LI   R4 exec_argv_offsets   ; args offsetss array
0x0000352C       LI   R5 0
argv_loop:
0x00003534       CMP  R5 R6                  ; argc
0x00003538       BEQ  argv_done              ; if finished
0x00003540       MOV  R1 R5
0x00003544       SHL  R1 R1 2
0x00003548       LDW  R2 [R4+R1]             ; get arg[i] offset
0x0000354C       ADD  R2 R2 R12              ; compute R2 - blobs string adress for this arg[i]
0x00003550       STW  R2 [R10+R1]            ; store this address to argv array in image
0x00003554       ADD  R5 R5 1
0x00003558       B    argv_loop
argv_done:
0x00003560       MOV  R1 R6
0x00003564       SHL  R1 R1 2

0x00003568       LI   R2 0
0x00003570       STW  R2 [R10+R1]            ; put null here: argv[argc] = NULL
    ;success
0x00003574       LI   R1 0
0x0000357C       POP  R12
0x00003580       POP  R11
0x00003584       POP  R10
0x00003588       POP  R9
0x0000358C       POP  R8
0x00003590       POP  LR
0x00003594       RET

exec_stack_nomem:
0x00003598       LI   R1 ERR_NOMEM
0x000035A0       POP  R12
0x000035A4       POP  R11
0x000035A8       POP  R10
0x000035AC       POP  R9
0x000035B0       POP  R8
0x000035B4       POP  LR
0x000035B8       RET

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
0x000035BC       PUSH LR
0x000035C0       PUSH R7
0x000035C4       PUSH R8
0x000035C8       PUSH R9
0x000035CC       PUSH R10
0x000035D0       PUSH R11
0x000035D4       PUSH R12

0x000035D8       BL vfs_lookup   ; lookup inode for the file
0x000035E0       CMP R1 0
0x000035E4       BEQ load_noent
0x000035EC       MOV R9 R1

0x000035F0       LDW R1 [R9 + INODE_TYPE]    ;check inode type/size
0x000035F4       LI R2 INODE_DIR
0x000035FC       CMP R1 R2
0x00003600       BEQ load_noexec
0x00003608       LDW R3 [R9 + INODE_SIZE]
0x0000360C       LI R4 MAX_APP_SIZE
0x00003614       CMP R3 R4
0x00003618       BGT load_noexec

0x00003620       BL file_alloc               ;allocate file
0x00003628       CMP R1 0
0x0000362C       BEQ load_nomem
0x00003634       MOV R10 R1                  ; savr file ptr R10
0x00003638       MOV R1 R10
0x0000363C       MOV R2 R9
0x00003640       LI R3 FD_FLAG_READ
0x00003648       BL file_init

    ; ---- allocate table and code pages ----
    ; makes table page and few pages up on file size
0x00003650       LDW R1 [R9 + INODE_SIZE]
    ;MOV R1 R6                  ; file size
0x00003654       BL pages_allocate_table
0x0000365C       CMP R1 0
0x00003660       BEQ load_file_fail

0x00003668       MOV R11 R1                 ; new table PA
0x0000366C       MOV R12 R2                 ; count (not needed further)

    ; ---- map pages RW ----
; macro: GET_CURR_TASK_IDX R4        ;current task
0x00003670   LI R1 CURRENT_TASK
0x00003678   LDW R4 [R1]
; macro: GET_TASK_PTR R5,R4
0x0000367C   LI R1 TASK_SIZE
0x00003684   MUL R3 R4 R1
0x00003688   LI R5 tasks
0x00003690   ADD R5 R5 R3

; macro: TASK_GET_CODE_PAGE R12,R5   ; save old pa code page from this task to R12
0x00003694   LDW R12 [R5 + TASK_CODE_PAGE]

   ; TASK_GET_PTBR R1,R5
   ; LI R2 USER_CODE_VA
   ; MOV R3 R11                 ;new pa code page
   ; LI R4 USER_RW
   ; BL map_page_rt             ;map it for loading to USER_CODE_VA

; macro: TASK_GET_PTBR R2, R5        ; PTBR
0x00003698   LDW R2 [R5 + TASK_PTBR]
0x0000369C       LI R3 USER_CODE_VA          ; starting new code page VA
0x000036A4       LI R4 USER_RW               ; mapping flAGS
0x000036AC       MOV R1 R11                  ; new table PA (with pa pages)
0x000036B0       BL pages_map_table

    ; ---- zero data page ----
; macro: TASK_GET_DATA_PAGE R1,R5    ; tasks va data_page
0x000036B8   LDW R1 [R5 + TASK_DATA_PAGE]
0x000036BC       CMP R1 0
0x000036C0       BEQ load_read
0x000036C8       LI R3 PAGE_SIZE
0x000036D0       BL mem_zero                 ; clean task data_page

load_read:
0x000036D8       MOV R1 R10                  ; file* with program
0x000036DC       LI  R2 USER_CODE_VA
0x000036E4       LDW R3 [R9 + INODE_SIZE]    ; file size
0x000036E8       BL file_read
0x000036F0       CMP R1 0
0x000036F4       BLT load_read_fail

0x000036FC       MOV R1 R10                  ;loaded release file*
0x00003700       BL file_put
    ; all loaedd R1 - new code page pa tab, R2 - old code page pa tab
0x00003708       MOV R1 R11
0x0000370C       MOV R2 R12

exec_lb_exit:                   ;common! exit!
0x00003710       POP R12
0x00003714       POP R11
0x00003718       POP R10
0x0000371C       POP R9
0x00003720       POP R8
0x00003724       POP R7
0x00003728       POP LR
0x0000372C       RET
; in error generally depending on state rollback allocated resources
load_read_fail:
    ; in this case release file and pa code page
0x00003730       MOV R1 R10
0x00003734       BL file_put
0x0000373C       MOV R1 R11
0x00003740       BL page_put        ;free page
0x00003748       LI R1 0
0x00003750       LI R2 ERR_IO
0x00003758       B  exec_lb_exit

load_file_fail:
0x00003760       MOV R1 R10
0x00003764       BL file_put

load_nomem:
0x0000376C       LI R1 0
0x00003774       LI R2 ERR_NOMEM
0x0000377C       B  exec_lb_exit

load_noexec:
0x00003784       MOV R1 R10
0x00003788       CMP R1 0
0x0000378C       BEQ noexec_skip
0x00003794       BL file_put

noexec_skip:
0x0000379C       LI R1 0
0x000037A4       LI R2 ERR_NOEXEC
0x000037AC       B  exec_lb_exit

load_noent:
0x000037B4       LI R1 0
0x000037BC       LI R2 ERR_NOENT
0x000037C4       B  exec_lb_exit

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

0x000037CC       PUSH LR
0x000037D0       PUSH R7
0x000037D4       PUSH R8
0x000037D8       PUSH R9
0x000037DC       PUSH R10
0x000037E0       PUSH R11
0x000037E4       PUSH R12
    ;init this at first
0x000037E8       LI R1 exec_strings_used
0x000037F0       LI R2 0
0x000037F8       STW R2 [R1]

0x000037FC       LI   R11 exec_strings      ; destination blob
0x00003804       LI   R12 0                 ; current offset
0x0000380C       LI   R7 0                  ; argv index
                               ;  R8 = user argv[]
                               ;  R9 = argc
exec_capture_next_arg:
    ; finished?
0x00003814       CMP  R7 R9
0x00003818       BEQ  exec_capture_done     ; if all agvs processed

    ;---------------------------------------------
    ; load argv[i] (ptr to string)
    ;---------------------------------------------
0x00003820       LDW  R10 [R8]

0x00003824       CMP  R10 0
0x00003828       BEQ  exec_capture_fault     ;if argv[i]==null

    ;---------------------------------------------
    ; save offset
    ;
    ; exec_argv_offsets[i]=current_offset (in R12)
    ;---------------------------------------------
0x00003830       LI   R1 exec_argv_offsets
0x00003838       MOV  R2 R7  ;i
0x0000383C       SHL  R2 R2 2
0x00003840       ADD  R1 R1 R2
0x00003844       STW  R12 [R1]

exec_copy_string:
    ;---------------------------------------------
    ; copy one character r10 argv[i] (ptr to string) R11 ptr to exec strings
    ;---------------------------------------------
0x00003848       LDB  R3 [R10]
0x0000384C       STB  R3 [R11]
0x00003850       ADD  R10 R10 1
0x00003854       ADD  R11 R11 1
0x00003858       ADD  R12 R12 1
    ; blob overflow?
0x0000385C       LI   R1 EXEC_MAX_STRINGS
0x00003864       CMP  R12 R1
0x00003868       BGT  exec_capture_fault
0x00003870       CMP  R3 0
0x00003874       BNE  exec_copy_string           ; end of string?
0x0000387C       ADD  R8 R8 4    ;to next argv[] string
0x00003880       ADD  R7 R7 1    ;i=i+1
0x00003884       B    exec_capture_next_arg

exec_capture_done:
0x0000388C       LI   R1 exec_strings_used
0x00003894       STW  R12 [R1]           ; current offset after last string
0x00003898       LI  R1 0
0x000038A0       POP R12
0x000038A4       POP R11
0x000038A8       POP R10
0x000038AC       POP R9
0x000038B0       POP R8
0x000038B4       POP R7
0x000038B8       POP LR
0x000038BC       RET
exec_capture_fault:
0x000038C0       LI   R1 ERR_FAULT
0x000038C8       POP R12
0x000038CC       POP R11
0x000038D0       POP R10
0x000038D4       POP R9
0x000038D8       POP R8
0x000038DC       POP R7
0x000038E0       POP LR
0x000038E4       RET

syscall_fork:
    ;================================================================
    ; fork()
    ; Returns child PID in the parent and 0 in the child.
    ; This clones the current task, duplicating its address space and
    ; user-writable state while preserving a new independent child thread.
    ;================================================================

0x000038E8       BL task_clone_current
0x000038F0       CMP R1 0
0x000038F4       BEQ fork_fail

    ; We return child PID to the parent via the trapframe.
; macro: TASK_GET_PID R2, R1
0x000038FC   LDW R2 [R1 + TASK_PID]
0x00003900       STW R2 [SP + TF_R1]
0x00003904       B trap_restore

fork_fail:
0x0000390C       LI R1 ERR_NOMEM
0x00003914       STW R1 [SP + TF_R1]
0x00003918       B trap_restore

syscall_yield:
;================================================================
; Yield the CPU to allow other tasks to run. This is a voluntary context switch.
; The scheduler will pick the next runnable task and switch to it.
;================================================================

0x00003920       LI R1 0
0x00003928       STW R1 [SP + TF_R1]         ; r1=0 - success
    ; Voluntary reschedule. The return value must be written before
    ; switching, while SP still points at the yielding task's trapframe.

0x0000392C       B schedule_and_switch
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
0x00003934       LDW R8 [SP + TF_R1]        ; R8 = exit code

; macro: GET_CURR_TASK_IDX R2
0x00003938   LI R1 CURRENT_TASK
0x00003940   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003944   LI R1 TASK_SIZE
0x0000394C   MUL R3 R2 R1
0x00003950   LI R5 tasks
0x00003958   ADD R5 R5 R3

    ; Store exit code in child task struct for parent to collect in waitforpid
; macro: TASK_SET_EXIT_CODE R5, R8  ; Save exit code
0x0000395C   STW R8 [R5 + TASK_EXIT_CODE]

0x00003960       PUSH R5
0x00003964       MOV R1 R5
0x00003968       BL task_close_fds          ; close all open file descriptors of this task (if any) to free file_pool resources
0x00003970       POP R5

    ; Mark this child as zombie (still exists but not runnable)
; macro: TASK_SET_STATE R5, TASK_ZOMBIE
0x00003974   LI R1 TASK_ZOMBIE
0x0000397C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00003980   LI R1 WAIT_NONE
0x00003988   STW R1 [R5 + TASK_WAIT]

    ; Wake parent if it's waiting
; macro: TASK_GET_PPID R6, R5       ; R6 = parent PID
0x0000398C   LDW R6 [R5 + TASK_PPID]

    ; find parent task by PPID
0x00003990       MOV R1 R6
0x00003994       LI R2 0                    ; Search by PID (parent's PID)
0x0000399C       BL task_find               ; R1 = found parent task*
0x000039A4       CMP R1 0
0x000039A8       BEQ no_parent_waiting
0x000039B0       MOV R7 R1                  ; R7 = parent task*
0x000039B4       MOV R11 R2                 ; save parent task index for bitmask

    ;Check if parent is waiting for this child
; macro: TASK_GET_WAIT_CHILD R8, R7 ; Child PID that parent R7 ptr is waiting for
0x000039B8   LDW R8 [R7 + TASK_WAIT_CHILD]
; macro: TASK_GET_PID R9, R5        ; This child's R5 ptr PID
0x000039BC   LDW R9 [R5 + TASK_PID]

0x000039C0       LI R10 -1
0x000039C8       CMP R8 R10                 ; if parent is waiting for any child (-1), then wake it up
0x000039CC       BEQ wake_parent            ;

0x000039D4       CMP R8 R9
0x000039D8       BNE no_parent_waiting      ; parent is waiting for a different child, do not wake it up

wake_parent:
    ; Find parent's task index for bitmask
    ; we already have parent task in R11

0x000039E0       LI R9 1
0x000039E8       SHL R9 R9 R11               ; bit for parent task

0x000039EC       LI R1 child_waitq
0x000039F4       MOV R2 R9
0x000039F8       BL waitq_wake_bitmask       ;unblock parent task waiting for this child

no_parent_waiting:
0x00003A00       B schedule_and_switch

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
0x00003A08       LDW R8 [SP + TF_R1]        ; R8 = pid to wait for
0x00003A0C       LDW R9 [SP + TF_R2]        ; R9 = status pointer

    ; Validate status pointer
0x00003A10       CMP R9 0
0x00003A14       BEQ waitpid_validate_done
0x00003A1C       MOV R1 R9
0x00003A20       LI R2 4
0x00003A28       LI R3 1
0x00003A30       BL user_buffer_valid_range
0x00003A38       CMP R1 1
0x00003A3C       BNE waitpid_badptr

waitpid_validate_done:
; macro: GET_CURR_TASK_IDX R4
0x00003A44   LI R1 CURRENT_TASK
0x00003A4C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003A50   LI R1 TASK_SIZE
0x00003A58   MUL R3 R4 R1
0x00003A5C   LI R5 tasks
0x00003A64   ADD R5 R5 R3
; macro: TASK_GET_PID R10, R5       ; R10 = current (parent proc) PID
0x00003A68   LDW R10 [R5 + TASK_PID]

    ; if search for any child
0x00003A6C       LI  R2 -1
0x00003A74       CMP R8 R2
0x00003A78       BNE find_child_by_pid
    ; set task_find to search for any child of this parent
0x00003A80       MOV R1 R10                  ; R1 = parent PID (PPID in child task)
0x00003A84       LI  R2 1                    ; search by PPID
0x00003A8C       BL task_find               ; R1 = found child task*
0x00003A94       CMP R1 0
0x00003A98       BEQ waitpid_no_child        ; No any child with PPID = this parent PID found
    ;R1 child task* found
0x00003AA0       B find_any_child_found
find_child_by_pid:
    ; Search for child task by PID
0x00003AA8       MOV R1 R8                  ; R1 = child PID to search for
0x00003AAC       LI R2 0                    ; Search by PID
0x00003AB4       BL task_find               ; R1 = found child task*
0x00003ABC       CMP R1 0
0x00003AC0       BEQ waitpid_no_child        ; No such child

find_any_child_found:

0x00003AC8       MOV R7 R1                   ; R7 = child task*

    ; Verify it's actually our child by its PPID fld
; macro: TASK_GET_PPID R1, R7
0x00003ACC   LDW R1 [R7 + TASK_PPID]
0x00003AD0       CMP R1 R10
0x00003AD4       BNE waitpid_no_child
    ; R7 = child task*
    ; check its state, if ZOMBIE, we can reap it and return its exit code
; macro: TASK_GET_STATE R1, R7
0x00003ADC   LDW R1 [R7 + TASK_STATE]
0x00003AE0       CMP R1 TASK_ZOMBIE
0x00003AE4       BEQ waitpid_reap_child

    ; Child running - block parent
; macro: TASK_GET_PID R1, R7
0x00003AEC   LDW R1 [R7 + TASK_PID]
; macro: TASK_SET_WAIT_CHILD R5, R1
0x00003AF0   STW R1 [R5 + TASK_WAIT_CHILD]

0x00003AF4       LI R1 child_waitq           ; child_waitq ptr
0x00003AFC       LI R2 WAIT_CHILD            ; reason
0x00003B04       LI R3 TASK_SLEEPING         ; state to set for current task
0x00003B0C       BL waitq_prepare_sleep

0x00003B14       BL waitq_sleep_current     ; freeze the current task

    ; will resume here when child exits and wakes us up

waitpid_reap_child:
    ; Get exit code from child task
; macro: TASK_GET_EXIT_CODE R2, R7
0x00003B1C   LDW R2 [R7 + TASK_EXIT_CODE]

    ; If status pointer is not NULL, write exit code to user space
0x00003B20       CMP R9 0
0x00003B24       BEQ waitpid_reap_done

0x00003B2C       MOV R1 R9                  ; R1 = user status pointer
0x00003B30       MOV R4 R2                  ; preserve exit code in kernel source register
0x00003B34       LI  R2 4                   ; R2 = size of exit code
0x00003B3C       BL copy_to_user            ; write exit code to user space

waitpid_reap_done:
; macro: TASK_GET_PID R10, R7       ; get child's PID
0x00003B44   LDW R10 [R7 + TASK_PID]
0x00003B48       MOV R1 R7                  ; R1 = child task*
0x00003B4C       BL task_destroy

0x00003B54       STW R10 [SP + TF_R1]        ; save child's PID to trapframe for return
0x00003B58       B trap_restore

waitpid_no_child:
0x00003B60       LI R1 ERR_CHILD
0x00003B68       STW R1 [SP + TF_R1]
0x00003B6C       B trap_restore

waitpid_badptr:
0x00003B74       LI R1 ERR_FAULT
0x00003B7C       STW R1 [SP + TF_R1]
0x00003B80       B trap_restore

;============================================
; syscall_mkdir - create dir in a namespace
; in : R1 = path, R2 = namespace
; out : R1 = 0 succes, or error
;============================================

syscall_mkdir:
    ; R1 = user pathname
0x00003B88       LDW R8 [SP + TF_R1]
0x00003B8C       LDW R9 [SP + TF_R2]
0x00003B90       MOV R1  R8
0x00003B94       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003B9C       CMP R1 0
0x00003BA0       BEQ mkdir_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003BA8   LI R1 CURRENT_TASK
0x00003BB0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003BB4   LI R1 TASK_SIZE
0x00003BBC   MUL R3 R4 R1
0x00003BC0   LI R5 tasks
0x00003BC8   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003BCC   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003BD0       MOV R2 R9                  ;NS

0x00003BD4       BL vfs_mkdir

    ; R1 = 0 on success
    ; R1 < 0 on error

0x00003BDC       B trap_restore

0x00003BE4       STW R1 [SP + TF_R1]     ;mkdir created exit!
0x00003BE8       B trap_restore

mkdir_fail_fault:
0x00003BF0       LI R1 ERR_FAULT
0x00003BF8       STW R1 [SP + TF_R1]     ;mkdir not created ERR todo
0x00003BFC       B trap_restore

;============================================
; syscall_rmdir - rm dir in a namespace
; in : R1 = path, R2 = namespace
; out : R1 = 0 succes, or error
;
;============================================

syscall_rmdir:
    ; R1 = user pathname

    ; validate/copy pathname from user space
    ; ...

0x00003C04       BL vfs_rmdir

    ; R1 = 0 on success
    ; R1 < 0 on error

0x00003C0C       B trap_restore

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
0x00003C14       PUSH LR
0x00003C18       PUSH R8

0x00003C1C       MOV R8 R1       ;pathname
0x00003C20       MOV R9 R2       ;namespace

    ; validate pathname
0x00003C24       MOV R1 R8
0x00003C28       BL validate_pathname
0x00003C30       CMP R1 0
0x00003C34       BNE mkdir_invalid

    ; First check whether directory already exists
0x00003C3C       MOV R1 R8
0x00003C40       BL nsfs_lookup
0x00003C48       CMP R1 0
0x00003C4C       BNE mkdir_exists

    ; Ask writable filesystem to create directory
0x00003C54       MOV R1 R8
0x00003C58       MOV R2 R9
0x00003C5C       BL nsfs_mkdir

    ; R1 = 0 or error
0x00003C64       B mkdir_exit

mkdir_exists:
0x00003C6C       LI R1 ERR_EXIST
0x00003C74       B mkdir_exit

mkdir_invalid:
0x00003C7C       LI R1 ERR_INVAL

mkdir_exit:
0x00003C84       POP R8
0x00003C88       POP LR
0x00003C8C       RET

;===============================================================
; vfs_rmdir
;
; R1 = pathname R2 = namespace
;
; Returns:
;   R1 = 0       success
;   R1 < 0       error
;===============================================================

vfs_rmdir:
0x00003C90       PUSH LR
0x00003C94       PUSH R8

0x00003C98       MOV R8 R1       ;pathname
0x00003C9C       MOV R9 R2       ;namespace

    ; validate pathname
0x00003CA0       MOV R1 R8
0x00003CA4       BL validate_pathname
0x00003CAC       CMP R1 0
0x00003CB0       BNE rmdir_invalid

    ; First check whether directory already exists
0x00003CB8       MOV R1 R8
0x00003CBC       BL nsfs_lookup
0x00003CC4       CMP R1 0
0x00003CC8       BNE rmdir_exists

    ; Ask writable filesystem to create directory
0x00003CD0       MOV R1 R8
0x00003CD4       MOV R2 R9
0x00003CD8       BL nsfs_rmdir

    ; R1 = 0 or error
0x00003CE0       B rmdir_exit

rmdir_exists:
0x00003CE8       LI R1 ERR_EXIST
0x00003CF0       B rmdir_exit

rmdir_invalid:
0x00003CF8       LI R1 ERR_INVAL

rmdir_exit:
0x00003D00       POP R8
0x00003D04       POP LR
0x00003D08       RET

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
0x00003D0C       PUSH R5
0x00003D10       PUSH R6
0x00003D14       PUSH R7

0x00003D18       MOV R5 R2                  ; Save search mode
0x00003D1C       MOV R7 R1                  ; Save PID/PPID
0x00003D20       LI R2 0                    ; Task index
task_find_loop:
0x00003D28       LI R3 MAX_TASKS
0x00003D30       CMP R2 R3
0x00003D34       BGE task_find_not_found

; macro: GET_TASK_PTR R4, R2
0x00003D3C   LI R1 TASK_SIZE
0x00003D44   MUL R3 R2 R1
0x00003D48   LI R4 tasks
0x00003D50   ADD R4 R4 R3
; macro: TASK_GET_STATE R6, R4
0x00003D54   LDW R6 [R4 + TASK_STATE]
0x00003D58       CMP R6 TASK_DEAD
0x00003D5C       BEQ task_find_next         ; Skip dead tasks

    ; Search based on mode
0x00003D64       CMP R5 0
0x00003D68       BEQ task_find_by_pid

    ; Search by PPID
; macro: TASK_GET_PPID R6, R4
0x00003D70   LDW R6 [R4 + TASK_PPID]
0x00003D74       CMP R6 R7
0x00003D78       BEQ task_find_found
0x00003D80       B task_find_next

task_find_by_pid:
; macro: TASK_GET_PID R6, R4
0x00003D88   LDW R6 [R4 + TASK_PID]
0x00003D8C       CMP R6 R7
0x00003D90       BEQ task_find_found

task_find_next:
0x00003D98       ADD R2 R2 1
0x00003D9C       B task_find_loop

task_find_found:
0x00003DA4       MOV R1 R4                  ; Return task pointer
0x00003DA8       MOV R2 R2                  ; Return task index
0x00003DAC       POP R7
0x00003DB0       POP R6
0x00003DB4       POP R5
0x00003DB8       RET

task_find_not_found:
0x00003DBC       LI R1 0
0x00003DC4       POP R7
0x00003DC8       POP R6
0x00003DCC       POP R5
0x00003DD0       RET

syscall_getpid:
    ;================================================================
    ; Return the current task's PID. This proves that the task can read its own PID.
    ;================================================================

; macro: GET_CURR_TASK_IDX R2
0x00003DD4   LI R1 CURRENT_TASK
0x00003DDC   LDW R2 [R1]
; macro: GET_TASK_PTR R5, R2
0x00003DE0   LI R1 TASK_SIZE
0x00003DE8   MUL R3 R2 R1
0x00003DEC   LI R5 tasks
0x00003DF4   ADD R5 R5 R3
; macro: TASK_GET_PID R1, R5            ; get pid from task scheduler data
0x00003DF8   LDW R1 [R5 + TASK_PID]

0x00003DFC       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
                                  ; on resume r1 will have pid read after svc call
0x00003E00       B trap_restore

syscall_debug:
    ;================================================================
    ; Placeholder debug syscall: return the first user argument unchanged.
    ; This proves argument and return-value plumbing without nested traps.
    ;================================================================

0x00003E08       LDW R1 [SP + TF_R1]
0x00003E0C       STW R1 [SP + TF_R1]

0x00003E10       B trap_restore


syscall_open:

    ;================================================================
    ; in: R1=user pathname (user space)
    ;     R2=flags
    ; out: R1 = fd / err -1
    ;================================================================

0x00003E18       LDW R8 [SP + TF_R1]
0x00003E1C       LDW R9 [SP + TF_R2]
0x00003E20       MOV R1  R8
0x00003E24       BL copy_path_from_user     ; macro inside destroys R11, copy pathname
                               ; to tasks Kbuf_RD buffer
                               ; R1 - pathname str ptr in the bufer
0x00003E2C       CMP R1 0
0x00003E30       BEQ open_fail_fault

    ; copy_path_from_user returned the current task's kernel read buffer.
; macro: GET_CURR_TASK_IDX R4
0x00003E38   LI R1 CURRENT_TASK
0x00003E40   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003E44   LI R1 TASK_SIZE
0x00003E4C   MUL R3 R4 R1
0x00003E50   LI R5 tasks
0x00003E58   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00003E5C   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00003E60       MOV R2 R9                  ;flags
0x00003E64       BL vfs_open

0x00003E6C       STW R1 [SP + TF_R1]     ;file opened if fd on exit!
0x00003E70       B trap_restore

open_fail_fault:
0x00003E78       LI R1 ERR_FAULT
0x00003E80       STW R1 [SP + TF_R1]     ;file not opened ERR
0x00003E84       B trap_restore


syscall_sleep:
    ;================================================================
    ; sleep(ms)
    ; R1 = milliseconds to sleep
    ;
    ; Returns:
    ;   R1 = 0 on success (slept full duration)
    ;   R1 = -1 on error (invalid time)
    ;================================================================

0x00003E8C       LDW R8 [SP + TF_R1]        ; R8 = milliseconds

0x00003E90       CMP R8 0
0x00003E94       BLE sleep_invalid          ; must be positive

; macro: GET_CURR_TASK_IDX R4
0x00003E9C   LI R1 CURRENT_TASK
0x00003EA4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003EA8   LI R1 TASK_SIZE
0x00003EB0   MUL R3 R4 R1
0x00003EB4   LI R5 tasks
0x00003EBC   ADD R5 R5 R3

    ; Calculate wake time in PIT ticks (1 ms per tick).
0x00003EC0       LI R3 timer_ticks
0x00003EC8       LDW R6 [R3]                ; current ticks (1ms per tick)

    ; Convert ms to ticks: 1 tick = 1 ms
0x00003ECC       MOV R7 R8                  ; R7 = ticks to sleep

0x00003ED0       ADD R6 R6 R7               ; R6 = wake time in ticks

    ; Store wake time in task struct
; macro: TASK_SET_WAKE_TIME R5, R6
0x00003ED4   STW R6 [R5 + TASK_WAKE_TIME]

    ; Use existing wait queue infrastructure
0x00003ED8       LI R1 sleep_waitq           ; sleep_waitq ptr
0x00003EE0       LI R2 WAIT_SLEEP            ; reason
0x00003EE8       LI R3 TASK_SLEEPING         ; new state (if other then blocked_io)
0x00003EF0       BL waitq_prepare_sleep     ; This marks task as TASK_SLEEP and adds it to the sleep_waitq

0x00003EF8       BL waitq_sleep_current     ; freeze the current task in kernel side until it is woken up by the timer interrupt handler when the wake time is reached

    ; Return 0 (will be set when woken)
0x00003F00       LI R1 0
0x00003F08       STW R1 [SP + TF_R1]
0x00003F0C       B trap_restore

sleep_invalid:
0x00003F14       LI R1 ERR_FAULT
0x00003F1C       STW R1 [SP + TF_R1]
0x00003F20       B trap_restore


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
0x00003F28       PUSH LR
0x00003F2C       PUSH R5
0x00003F30       PUSH R8
0x00003F34       PUSH R9
0x00003F38       PUSH R10
0x00003F3C       PUSH R11

0x00003F40       MOV R8 R1                  ; current user source byte

; macro: GET_CURR_TASK_IDX R4
0x00003F44   LI R1 CURRENT_TASK
0x00003F4C   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00003F50   LI R1 TASK_SIZE
0x00003F58   MUL R3 R4 R1
0x00003F5C   LI R5 tasks
0x00003F64   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R9, R5    ; destination kernel path buffer
0x00003F68   LDW R9 [R5 + TASK_KBUF_RD_PTR]

0x00003F6C       PUSH R9                    ; original destination returned on success
0x00003F70       LI R10 0                   ; bytes copied before NUL

copy_path_loop:
0x00003F78       LI R11 KBUFFER_SIZE
0x00003F80       CMP R10 R11
0x00003F84       BGE copy_path_fail

0x00003F8C       PUSH R8
0x00003F90       PUSH R9
0x00003F94       PUSH R10
0x00003F98       MOV R1 R8
0x00003F9C       LI R2 1
0x00003FA4       LI R3 0                    ; read access from user source
0x00003FAC       BL user_buffer_valid_range
0x00003FB4       POP R10
0x00003FB8       POP R9
0x00003FBC       POP R8
0x00003FC0       CMP R1 1
0x00003FC4       BNE copy_path_fail

0x00003FCC       LDB R4 [R8]
0x00003FD0       STB R4 [R9]
0x00003FD4       CMP R4 0
0x00003FD8       BEQ copy_path_done

0x00003FE0       ADD R8 R8 1
0x00003FE4       ADD R9 R9 1
0x00003FE8       ADD R10 R10 1
0x00003FEC       B copy_path_loop

copy_path_done:
0x00003FF4       POP R1                     ; original kernel path pointer

0x00003FF8       POP R11
0x00003FFC       POP R10
0x00004000       POP R9
0x00004004       POP R8
0x00004008       POP R5
0x0000400C       POP LR
0x00004010       RET

copy_path_fail:
0x00004014       POP R1                     ; discard original kernel path pointer

0x00004018       POP R11
0x0000401C       POP R10
0x00004020       POP R9
0x00004024       POP R8
0x00004028       POP R5
0x0000402C       LI R1 0
0x00004034       POP LR
0x00004038       RET

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

0x0000403C       PUSH LR
0x00004040       PUSH R8
0x00004044       PUSH R9
0x00004048       PUSH R10
0x0000404C       PUSH R11

0x00004050       MOV R8 R1          ; kernel dst
0x00004054       MOV R9 R2          ; user src
0x00004058       MOV R10 R3         ; max length
0x0000405C       LI  R11 0          ; bytes copied

copy_user_loop:
    ; reached max?
0x00004064       CMP R11 R10
0x00004068       BGE copy_user_fail

    ; validate one byte
0x00004070       PUSH R8
0x00004074       PUSH R9
0x00004078       PUSH R10
0x0000407C       PUSH R11
0x00004080       MOV R1 R9
0x00004084       LI  R2 1
0x0000408C       LI  R3 0           ; read access
0x00004094       BL user_buffer_valid_range
0x0000409C       POP R11
0x000040A0       POP R10
0x000040A4       POP R9
0x000040A8       POP R8
0x000040AC       CMP R1 1
0x000040B0       BNE copy_user_fail

    ; copy byte
0x000040B8       LDB R4 [R9]
0x000040BC       STB R4 [R8]
    ;cpy ctr
0x000040C0       ADD R11 R11 1
0x000040C4       CMP R4 0    ;if string ends (null)
0x000040C8       BEQ copy_user_done

0x000040D0       ADD R8 R8 1 ;advance
0x000040D4       ADD R9 R9 1
0x000040D8       B copy_user_loop
copy_user_done:
0x000040E0       MOV R1 R11
0x000040E4       POP R11
0x000040E8       POP R10
0x000040EC       POP R9
0x000040F0       POP R8
0x000040F4       POP LR
0x000040F8       RET
copy_user_fail:
0x000040FC       LI  R1 0
0x00004104       POP R11
0x00004108       POP R10
0x0000410C       POP R9
0x00004110       POP R8
0x00004114       POP LR
0x00004118       RET

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
0x0000411C       PUSH LR
0x00004120       PUSH R7
0x00004124       PUSH R8
0x00004128       PUSH R9
0x0000412C       PUSH R10

0x00004130       MOV R8 R1                  ; save pathname ptr

0x00004134       LI R7 device_table
0x0000413C       LI R9 DEVICE_COUNT

devfs_loop:
0x00004144       CMP R9 0
0x00004148       BEQ devfs_lookup_fail

    ; compare pathname with device name
0x00004150       MOV R1 R8
0x00004154       LDW R2 [R7 + DEV_NAME]
0x00004158       BL strcmp
0x00004160       CMP R1 1
0x00004164       BEQ devfs_found

0x0000416C       ADD R7 R7 DEV_SIZE
0x00004170       SUB R9 R9 1
0x00004174       B devfs_loop

devfs_found:
    ; 1 allocate inode
0x0000417C       BL inode_alloc
0x00004184       CMP R1 0
0x00004188       BEQ devfs_lookup_fail

0x00004190       MOV R10 R1         ; inode
    ; 2 init inode
0x00004194       LDW R2 [R7 + DEV_OPS]
0x00004198       LDW R3 [R7 + DEV_PRIVATE]
0x0000419C       LI  R4 INODE_CHAR       ; inode type for dev - char
0x000041A4       LI  R5 0                ; size =0
0x000041AC       BL inode_init

0x000041B4       MOV R1 R10         ; 3 return new inited inode ptr for this dev
0x000041B8       POP R10
0x000041BC       POP R9
0x000041C0       POP R8
0x000041C4       POP R7
0x000041C8       POP LR
0x000041CC       RET

devfs_lookup_fail:
0x000041D0       LI R1 0
0x000041D8       POP R10
0x000041DC       POP R9
0x000041E0       POP R8
0x000041E4       POP R7
0x000041E8       POP LR
0x000041EC       RET

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
0x000041F0       LI R2 0                  ; R2 = node index

nsfs_node_alloc_loop:
0x000041F8       CMP R2 NSFS_MAX_NODES    ;check if we reached the max number of nodes
0x000041FC       BGE nsfs_node_alloc_fail

0x00004204       SHL R3 R2 2
0x00004208       LI R4 nsfs_node_used     ;this is the base address of the idx array of used nodes
0x00004210       ADD R4 R4 R3

0x00004214       LDW R5 [R4]              ;R4 points to the word in the bitmap, R5 = value of that word
0x00004218       CMP R5 0
0x0000421C       BEQ nsfs_node_alloc_found

0x00004224       ADD R2 R2 1
0x00004228       B nsfs_node_alloc_loop

nsfs_node_alloc_found:
0x00004230       LI R5 1
0x00004238       STW R5 [R4]              ; Mark the node as used in the bitmap

0x0000423C       LI R3 NSFS_NODE_SIZEOF
0x00004244       MUL R6 R2 R3
0x00004248       LI R1 nsfs_node_pool     ; R1 = base address of the node pool
0x00004250       ADD R1 R1 R6             ; return pointer to the allocated node ptr=base + index * sizeof(node)
0x00004254       RET

nsfs_node_alloc_fail:
0x00004258       LI R1 0
0x00004260       RET

;=====================================================================
;   nsfs_node_free - free a node back to the pool
;
;   Input R1 = idx node to free
;=====================================================================

nsfs_node_free:
0x00004264       LI R2 nsfs_node_pool
0x0000426C       SUB R3 R1 R2

0x00004270       LI R4 NSFS_NODE_SIZEOF
0x00004278       DIV R5 R3 R4

0x0000427C       SHL R5 R5 2
0x00004280       LI R6 nsfs_node_used
0x00004288       ADD R6 R6 R5

0x0000428C       LI R7 0
0x00004294       STW R7 [R6]
0x00004298       RET

;=====================================================================
; nsfs_refresh_index - refresh the NSFS index from the host JSON KV store
;
; short description:
;   This function sends a BMI command to the host to retrieve the current NSFS index. then it parses the
; reply payload and populates the nsfs_index_table and nsfs_index_path_pool with the entries.
; nsfs_index_table is an array of nsfs_index_entry structures,
; nsfs_index_path_pool is a blob of path stringZ.
;
; in:  R1 = namespace
; out: R1 = 0 on success, BMI/errno status on failure
;=====================================================================

nsfs_refresh_index:
0x0000429C       PUSH LR
0x000042A0       PUSH R8
0x000042A4       PUSH R9
0x000042A8       PUSH R10
0x000042AC       PUSH R11
0x000042B0       PUSH R12

0x000042B4       MOV R12 R1

0x000042B8       MOV R1 NSFS_INDEX   ; bmi opcode for nsfs index refresh
0x000042BC       LI R2 0
0x000042C4       LI R3 0
0x000042CC       MOV R4 R12
0x000042D0   CALL bmi_call

0x000042D8       CMP R1 0
0x000042DC       BNE nsfs_refresh_done
    ; got reply payload in R2, size in R3
    ; parse the reply payload and populate the nsfs_index_table and nsfs_index_path_pool
0x000042E4       LI R1 nsfs_index_count
0x000042EC       LI R2 0
0x000042F4       STW R2 [R1]                     ;init index count to 0
0x000042F8       LI R1 nsfs_index_path_next
0x00004300       LI R2 nsfs_index_path_pool
0x00004308       STW R2 [R1]           ;init path pool next ptr to start of path pool

0x0000430C       LI R8 BMI_BUF_READ
0x00004314       ADD R8 R8 BMI_HDR_SIZEOF       ; R8 = reply payload cursor
0x00004318       LDW R9 [R8]                    ; R9 = entry_count - first word in the reply payload
                                   ; is the number of entries
0x0000431C       ADD R8 R8 4
0x00004320       LI R10 0                       ; R10 = parsed count R8 = next is at reply payload

nsfs_refresh_loop:                 ;fill the nsfs_index_table with entries from the reply payload
0x00004328       CMP R10 R9
0x0000432C       BGE nsfs_refresh_success       ;if parsed count >= entry_count, or max reached we are done
0x00004334       CMP R10 NSFS_INDEX_MAX_ENTRIES
0x00004338       BGE nsfs_refresh_success

0x00004340       LI R11 NSFS_INDEX_ENTRY_SIZEOF
0x00004348       MUL R11 R10 R11
0x0000434C       LI R6 nsfs_index_table
0x00004354       ADD R11 R6 R11                 ; R11 = &nsfs_index_table[R10], R8 = &reply_payload[R8]

0x00004358       LDW R1 [R8 + NSFS_WIRE_TYPE]    ;copy payload wire entries to index entries elements
0x0000435C       STW R1 [R11 + NSFS_INDEX_TYPE]
0x00004360       LDW R1 [R8 + NSFS_WIRE_SIZE]
0x00004364       STW R1 [R11 + NSFS_INDEX_SIZE]
0x00004368       LDW R1 [R8 + NSFS_WIRE_VERSION]
0x0000436C       STW R1 [R11 + NSFS_INDEX_VERSION]
0x00004370       LDW R5 [R8 + NSFS_WIRE_PATH_LEN]
0x00004374       STW R5 [R11 + NSFS_INDEX_PATH_LEN]
0x00004378       ADD R8 R8 NSFS_WIRE_HDR_SIZEOF  ; move R8 to the start of the path bytes in the wire payload

    ; Copy path bytes to path pool and append a NUL for strcmp.
0x0000437C       LI R6 nsfs_index_path_next    ;get next ptr in path pool blob
0x00004384       LDW R1 [R6]
0x00004388       STW R1 [R11 + NSFS_INDEX_PATH]; save path ptr in nsfs_index_table[] entry
0x0000438C       MOV R2 R8                     ; R2(R8) = source path ptr in wire payload
0x00004390       MOV R3 R5               ; R3(R5) = path_len, R1 = dest path ptr in path pool blob
0x00004394       BL memcpy               ; save path bytes to path pool blob
0x0000439C       LI R2 0
0x000043A4       STB R2 [R1]             ; append NUL to path in path pool blob
0x000043A8       ADD R1 R1 1
0x000043AC       LI R6 nsfs_index_path_next  ; update next ptr in R1 for path in path pool blob
0x000043B4       STW R1 [R6]

    ; Advance wire cursor by path_len rounded up to 4 bytes.
0x000043B8       ADD R8 R8 R5
0x000043BC       ADD R8 R8 3
0x000043C0       LI R6 0xFFFFFFFC
0x000043C8       AND R8 R8 R6

0x000043CC       ADD R10 R10 1
0x000043D0       B nsfs_refresh_loop

nsfs_refresh_success:
0x000043D8       LI R1 nsfs_index_count
0x000043E0       STW R10 [R1]        ;update index count to parsed count
0x000043E4       LI R1 0

nsfs_refresh_done:
0x000043EC       POP R12
0x000043F0       POP R11
0x000043F4       POP R10
0x000043F8       POP R9
0x000043FC       POP R8
0x00004400       POP LR
0x00004404       RET

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
0x00004408       PUSH LR
0x0000440C       PUSH R7
0x00004410       PUSH R8
0x00004414       PUSH R9
0x00004418       PUSH R10
0x0000441C       PUSH R11
0x00004420       PUSH R12

0x00004424       MOV R8 R1                       ; pathname
0x00004428       LI R9 nsfs_index_table          ; start of index table
0x00004430       LI R10 nsfs_index_count         ; count of items in index table
0x00004438       LDW R10 [R10]

nsfs_lookup_loop:
0x0000443C       CMP R10 0
0x00004440       BEQ nsfs_lookup_not_found

0x00004448       MOV R1 R8
0x0000444C       LDW R2 [R9 + NSFS_INDEX_PATH]
0x00004450       BL strcmp                      ; compare pathname with index entry path
0x00004458       CMP R1 1
0x0000445C       BEQ nsfs_lookup_found

0x00004464       ADD R9 R9 NSFS_INDEX_ENTRY_SIZEOF
0x00004468       SUB R10 R10 1
0x0000446C       B nsfs_lookup_loop

nsfs_lookup_found:
0x00004474       BL nsfs_node_alloc              ; allocate a new nsfs node
0x0000447C       CMP R1 0
0x00004480       BEQ nsfs_lookup_not_found
0x00004488       MOV R11 R1                      ; nsfs node

0x0000448C       LI R1 NSFS_DEFAULT_NS               ;fill in the node with index entry data for that found pathname
0x00004494       STW R1 [R11 + NSFS_NODE_NAMESPACE]
0x00004498       LDW R1 [R9 + NSFS_INDEX_PATH]
0x0000449C       STW R1 [R11 + NSFS_NODE_PATH]
0x000044A0       LDW R1 [R9 + NSFS_INDEX_TYPE]
0x000044A4       CMP R1 NSFS_TYPE_DIR
0x000044A8       BEQ nsfs_lookup_type_dir
0x000044B0       LI R12 INODE_REG
0x000044B8       B nsfs_lookup_type_done
nsfs_lookup_type_dir:
0x000044C0       LI R12 INODE_DIR
nsfs_lookup_type_done:
0x000044C8       STW R12 [R11 + NSFS_NODE_TYPE]  ;node type DIR or REG
0x000044CC       LDW R7  [R9 + NSFS_INDEX_SIZE]
0x000044D0       STW R7  [R11 + NSFS_NODE_SIZE]
    ;LDW R1 [R9 + NSFS_INDEX_PATH_LEN]
0x000044D4       LI  R1 O_RDWR ;when created we set here rd/wr should be copied from open flags normally
0x000044DC       STW R1 [R11 + NSFS_NODE_FLAGS]

0x000044E0       BL inode_alloc
0x000044E8       CMP R1 0
0x000044EC       BEQ nsfs_lookup_free_node

0x000044F4       MOV R10 R1                      ; inode
0x000044F8       LI  R2 nsfs_ops                 ; nsfs ops table
0x00004500       MOV R3 R11                      ; nsfs node as inode_private data
0x00004504       MOV R4 R12                      ; inode type (DIR or REG)
0x00004508       MOV R5 R7                       ; file size.
0x0000450C       BL inode_init
0x00004514       MOV R1 R10
0x00004518       B nsfs_lookup_done

nsfs_lookup_free_node:
0x00004520       MOV R1 R11
0x00004524       BL nsfs_node_free

nsfs_lookup_not_found:
0x0000452C       LI R1 0

nsfs_lookup_done:
0x00004534       POP R12
0x00004538       POP R11
0x0000453C       POP R10
0x00004540       POP R9
0x00004544       POP R8
0x00004548       POP R7
0x0000454C       POP LR
0x00004550       RET
;=====================================================================
; nsfs_open - open a file in the NSFS overlay
; in:  R1 = file ptr
; out: R1 = 0
;=====================================================================

nsfs_open:
0x00004554       LI R1 0
0x0000455C       RET
;=====================================================================
; nsfs_close
; in:  R1 = file ptr
; out: R1 = 0
;=====================================================================

nsfs_close:
0x00004560       LI R1 0
0x00004568       RET

;=====================================================================
; nsfs_read
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;=====================================================================

nsfs_read:
0x0000456C       PUSH LR
0x00004570       PUSH R8
0x00004574       PUSH R9
0x00004578       PUSH R10
0x0000457C       PUSH R11
0x00004580       PUSH R12

0x00004584       MOV R8 R1
0x00004588       MOV R9 R2
0x0000458C       MOV R10 R3

0x00004590       CMP R10 0
0x00004594       BEQ nsfs_read_eof

0x0000459C       PUSH R8
0x000045A0       PUSH R9
0x000045A4       MOV R1 R9
0x000045A8       MOV R2 R10
0x000045AC       LI R3 1                    ; destination must be user-writable
0x000045B4       BL user_buffer_valid_range
0x000045BC       POP R9
0x000045C0       POP R8
0x000045C4       CMP R1 1
0x000045C8       BNE nsfs_read_fault

0x000045D0       LDW R11 [R8 + FILE_INODE]
0x000045D4       LDW R5  [R11 + INODE_TYPE]
0x000045D8       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x000045DC       LI  R2 INODE_DIR
0x000045E4       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x000045E8       BEQ nsfs_read_dir

0x000045F0       LDW R12 [R8 + FILE_OFFSET]
0x000045F4       LDW R4  [R11 + NSFS_NODE_SIZE]

0x000045F8       CMP R12 R4
0x000045FC       BGEU nsfs_read_eof

0x00004604       SUB R4 R4 R12             ; bytes remaining
0x00004608       CMP R10 R4
0x0000460C       BLEU nsfs_read_count_ready
0x00004614       MOV R10 R4

nsfs_read_count_ready:

;read file from nsfs
; call bmi_read_file with the file's index and offset to get the data from the host
0x00004618       MOV R1 R11                ; NSFS node
0x0000461C       MOV R2 R12                ; file offset
0x00004620       MOV R3 R10                ; clipped read length
0x00004624       MOV R4 R9                 ; user destination
0x00004628       BL  nsfs_bmi_read_file
0x00004630       CMP R1 0
0x00004634       BLT nsfs_read_done

0x0000463C       ADD R12 R12 R1
0x00004640       STW R12 [R8 + FILE_OFFSET]
0x00004644       B nsfs_read_done

nsfs_read_dir:
    ; directory read – call our dir read function
0x0000464C       MOV R1 R8
0x00004650       MOV R2 R9
0x00004654       MOV R3 R10
0x00004658       BL nsfs_readdir
0x00004660       B nsfs_read_done   ; jump to the common return path

nsfs_read_fault:
0x00004668       LI R1 ERR_FAULT
0x00004670       B nsfs_read_done

nsfs_read_eof:
0x00004678       LI R1 0

nsfs_read_done:
0x00004680       POP R12
0x00004684       POP R11
0x00004688       POP R10
0x0000468C       POP R9
0x00004690       POP R8
0x00004694       POP LR
0x00004698       RET

nsfs_bmi_read_file:
    ;=====================================================================
    ; bmi_read_file - read file data from the host via BMI
    ; in:  R1 = nsfs node, R2 = offset, R3 = length, R4 = user destination
    ; out: R1 = bytes read or errno
    ;=====================================================================
0x0000469C       PUSH LR
0x000046A0       PUSH R8
0x000046A4       PUSH R9
0x000046A8       PUSH R10
0x000046AC       PUSH R11
0x000046B0       PUSH R12

0x000046B4       MOV R8 R1              ; nsfs node
0x000046B8       MOV R9 R2              ; offset
0x000046BC       MOV R10 R3             ; length
0x000046C0       MOV R11 R4             ; current user destination
0x000046C4       LI R12 0               ; total bytes copied

bmi_read_file_loop:
0x000046CC       CMP R10 0
0x000046D0       BEQ bmi_read_file_done

0x000046D8       LI R7 BMI_BUF_WRITE
0x000046E0       ADD R7 R7 BMI_HDR_SIZEOF
0x000046E4       LDW R6 [R8 + NSFS_NODE_FLAGS]      ; path_len
0x000046E8       STW R6 [R7]                        ; u32 path_len
0x000046EC       STW R9 [R7 + 4]                    ; u32 offset

0x000046F0       LI R5 4084                         ; max BMI reply payload = 4096 - header
0x000046F8       CMP R10 R5
0x000046FC       BLEU bmi_read_file_chunk_ready
0x00004704       B bmi_read_file_chunk_store
bmi_read_file_chunk_ready:
0x0000470C       MOV R5 R10
bmi_read_file_chunk_store:
0x00004710       STW R5 [R7 + 8]                    ; u32 requested length

0x00004714       ADD R1 R7 12
0x00004718       LDW R2 [R8 + NSFS_NODE_PATH]
0x0000471C       MOV R3 R6
0x00004720       BL memcpy

0x00004728       LI R1 BMI_READ_FILE
0x00004730       MOV R2 R7
0x00004734       ADD R3 R6 12
0x00004738       LDW R4 [R8 + NSFS_NODE_NAMESPACE]
0x0000473C   CALL bmi_call
0x00004744       CMP R1 0
0x00004748       BNE bmi_read_file_fail

0x00004750       LI R4 BMI_BUF_READ
0x00004758       LDW R5 [R4 + BMI_HDR_PAYLOAD_LEN]  ; actual bytes returned
0x0000475C       CMP R5 0
0x00004760       BEQ bmi_read_file_done
0x00004768       ADD R4 R4 BMI_HDR_SIZEOF
0x0000476C       MOV R1 R11
0x00004770       MOV R2 R5
0x00004774       BL copy_to_user

0x0000477C       ADD R12 R12 R1
0x00004780       ADD R9 R9 R1
0x00004784       ADD R11 R11 R1
0x00004788       SUB R10 R10 R1
0x0000478C       CMP R1 R5
0x00004790       BNE bmi_read_file_done
0x00004798       B bmi_read_file_loop

bmi_read_file_done:
0x000047A0       MOV R1 R12
0x000047A4       POP R12
0x000047A8       POP R11
0x000047AC       POP R10
0x000047B0       POP R9
0x000047B4       POP R8
0x000047B8       POP LR
0x000047BC       RET

bmi_read_file_fail:
0x000047C0       LI  R1 ERR_IO
0x000047C8       POP R12
0x000047CC       POP R11
0x000047D0       POP R10
0x000047D4       POP R9
0x000047D8       POP R8
0x000047DC       POP LR
0x000047E0       RET
;=====================================================================
; nsfs_write
; in:  R1 = file ptr, R2 = user buffer, R3 = length
; out: R1 = bytes written or errno
;=====================================================================
nsfs_write:
0x000047E4       LI R1 ERR_NOENT
0x000047EC       RET
;=====================================================================
; nsfs_readdir - read next directory entries from NSFS overlay
; short description:
;   This function reads directory entries from the NSFS overlay.
; It checks if the provided userspace buffer is valid, retrieves the directory path from the file's inode,
; and scans the NSFS index table for entries that match the directory path.
; For each matching entry, it constructs a dirent structure and copies it to the userspace buffer.
;
; in:  R1 = file ptr, R2 = userspace dirent buffer
; out: R1 = 1 entry, 0 EOF, or errno
; This is a simplified implementation that reads one entry at a time.
;=====================================================================
nsfs_readdir:
0x000047F0       PUSH LR
0x000047F4       PUSH R8
0x000047F8       PUSH R9
0x000047FC       PUSH R10
0x00004800       PUSH R11
0x00004804       PUSH R12

0x00004808       MOV R8 R2              ; R8 = userspace dirent buffer ptr
0x0000480C       PUSH R8
0x00004810       MOV R12 R1             ; R12 = file ptr

0x00004814       LI R3 DIRENT_SIZEOF
0x0000481C       MOV R1 R8
0x00004820       LI R2 DIRENT_SIZEOF
0x00004828       LI R3 1
0x00004830       BL user_buffer_valid_range  ; check if userspace buffer is valid for writing DIRENT_SIZEOF bytes
0x00004838       CMP R1 1
0x0000483C       BNE nsfs_readdir_fault
    ; read the directory path from the file's inode, file ptr is dir
0x00004844       LDW R4 [R12 + FILE_INODE]
0x00004848       LDW R5 [R4 + INODE_PRIVATE]
0x0000484C       CMP R5 0
0x00004850       BEQ nsfs_readdir_eof
0x00004858       LDW R10 [R5 + NSFS_NODE_PATH]   ; directory path, absolute
0x0000485C       LDW R11 [R12 + FILE_OFFSET]     ; index into nsfs_index_table
0x00004860       MOV R6 R11
    ; scan the nsfs_index_table for entries that match the directory path, starting from index R6
    ; (each call to readdir returns one entry, so R6 is the index of the next entry to read)
nsfs_readdir_scan:
0x00004864       LI R1 nsfs_index_count
0x0000486C       LDW R1 [R1]
0x00004870       CMP R6 R1
0x00004874       BGE nsfs_readdir_eof

0x0000487C       LI R7 NSFS_INDEX_ENTRY_SIZEOF
0x00004884       MUL R7 R6 R7
0x00004888       LI R9 nsfs_index_table
0x00004890       ADD R9 R9 R7            ; R9 = &nsfs_index_table[R6]

0x00004894       LDW R1 [R9 + NSFS_INDEX_PATH]
0x00004898       MOV R2 R10
0x0000489C       BL str_prefix       ; check if the index entry path has the directory path as prefix
0x000048A4       CMP R1 1
0x000048A8       BNE nsfs_readdir_next
    ; if the index entry path has the directory path as prefix, extract the next component of the path
0x000048B0       LDW R1 [R9 + NSFS_INDEX_PATH]
0x000048B4       MOV R2 R10
0x000048B8       BL skip_prefix  ; skip the directory path prefix, R1 = pointer to the next component in the path
0x000048C0       LDB R2 [R1]
0x000048C4       LI R3 47
0x000048CC       CMP R2 R3
0x000048D0       BEQ nsfs_readdir_skip_slash
0x000048D8       CMP R2 0
0x000048DC       BEQ nsfs_readdir_next
0x000048E4       B nsfs_readdir_have_name
nsfs_readdir_skip_slash:
0x000048EC       ADD R1 R1 1
nsfs_readdir_have_name:
0x000048F0       MOV R8 R1                       ; component name

0x000048F4       BL path_component_len           ; get length of the next component in the path
0x000048FC       MOV R7 R1
0x00004900       CMP R7 0
0x00004904       BEQ nsfs_readdir_next
0x0000490C       LI R2 63
0x00004914       CMP R7 R2
0x00004918       BLE nsfs_readdir_name_ok
0x00004920       MOV R7 R2

nsfs_readdir_name_ok:               ; name is valid
0x00004924       MOV R11 R6                      ; R6 = index of the entry in nsfs_index_table
; macro: GET_CURR_TASK_IDX R4
0x00004928   LI R1 CURRENT_TASK
0x00004930   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00004934   LI R1 TASK_SIZE
0x0000493C   MUL R3 R4 R1
0x00004940   LI R5 tasks
0x00004948   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x0000494C   LDW R1 [R5 + TASK_KBUF_WR_PTR]

0x00004950       ADD R3 R11 1
0x00004954       STW R3 [R1 + DIRENT_INODE]      ; write the next inode number (index + 1) to the dirent structure in task write buffer
0x00004958       LDW R2 [R9 + NSFS_INDEX_SIZE]
0x0000495C       STW R2 [R1 + DIRENT_SIZE]
0x00004960       LDW R2 [R9 + NSFS_INDEX_TYPE]
0x00004964       CMP R2 NSFS_TYPE_DIR
0x00004968       BEQ nsfs_readdir_type_dir
0x00004970       LI R2 DT_REG
0x00004978       B nsfs_readdir_type_done
nsfs_readdir_type_dir:
0x00004980       LI R2 DT_DIR
nsfs_readdir_type_done:
0x00004988       STW R2 [R1 + DIRENT_TYPE]

0x0000498C       ADD R3 R11 1
0x00004990       STW R3 [R12 + FILE_OFFSET]  ; update the file offset to the next index for the next call to readdir

0x00004994       MOV R2 R8
0x00004998       ADD R3 R1 DIRENT_NAME
0x0000499C       LI R6 0
nsfs_readdir_copy_name:
0x000049A4       CMP R6 R7                   ; R7 = component name length
0x000049A8       BGE nsfs_readdir_copy_done
0x000049B0       LDB R10 [R2 + R6]
0x000049B4       STB R10 [R3 + R6]
0x000049B8       ADD R6 R6 1
0x000049BC       B nsfs_readdir_copy_name
nsfs_readdir_copy_done:
0x000049C4       LI R10 0
0x000049CC       STB R10 [R3 + R6]       ; null terminate the name in the dirent structure

0x000049D0       LI R2 DIRENT_SIZEOF
0x000049D8       MOV R4 R1
0x000049DC       POP R1
0x000049E0       BL copy_to_user          ; copy the dirent structure to the userspace buffer
0x000049E8       CMP R1 DIRENT_SIZEOF
0x000049EC       BNE nsfs_readdir_fault_after_pop
0x000049F4       MOV R1 DIRENT_SIZEOF
0x000049F8       POP R12
0x000049FC       POP R11
0x00004A00       POP R10
0x00004A04       POP R9
0x00004A08       POP R8
0x00004A0C       POP LR
0x00004A10       RET

nsfs_readdir_next:
0x00004A14       ADD R6 R6 1
0x00004A18       B nsfs_readdir_scan

nsfs_readdir_eof:
0x00004A20       POP R1
0x00004A24       LI R1 0
0x00004A2C       POP R12
0x00004A30       POP R11
0x00004A34       POP R10
0x00004A38       POP R9
0x00004A3C       POP R8
0x00004A40       POP LR
0x00004A44       RET

nsfs_readdir_fault:
0x00004A48       POP R1
nsfs_readdir_fault_after_pop:
0x00004A4C       LI R1 ERR_FAULT
0x00004A54       POP R12
0x00004A58       POP R11
0x00004A5C       POP R10
0x00004A60       POP R9
0x00004A64       POP R8
0x00004A68       POP LR
0x00004A6C       RET
;=====================================================================
; nsfs_create - create a new file in the NSFS overlay
; in:  R1 = pathname, R2 = mode/type flags, R3 namespace (in future, for now we use default namespace only)
; out: R1 = inode ptr if created, or errno
;=====================================================================
nsfs_create:
0x00004A70       PUSH LR
0x00004A74       PUSH R6
0x00004A78       PUSH R8
0x00004A7C       PUSH R9
0x00004A80       PUSH R10
0x00004A84       MOV  R8  R1
0x00004A88       MOV  R9  R2
0x00004A8C       MOV  R10 R3
0x00004A90       LI   R10 NSFS_DEFAULT_NS         ; Defaut NS for now
  ;  MOV  R6  R10                      ; namespace
    ; TODO: FILE_CREATE over BMI, then nsfs_lookup can materialize inode.
0x00004A98       MOV  R2  R8                       ; R2 = pathname
0x00004A9C       BL   get_path_len                 ; get length of the pathname string
0x00004AA4       mov  R3 R1                        ; R3 = length of the pathname string
    ; create a new nsfs_node and add it to the index table, then call nsfs_lookup to get the inode
0x00004AA8       MOV  R1 FILE_CREATE              ;opcode FILE_CREATE
0x00004AAC       MOV  R4 R10                        ; at this time we work with default namespace only
0x00004AB0   CALL bmi_call
    ;check bmi_call return status
0x00004AB8       CMP  R1 0
0x00004ABC       BNE  nsfs_create_fail
    ; refresh the index table
0x00004AC4       MOV R1 R10                        ; at this time we work with default namespace only
0x00004AC8       BL nsfs_refresh_index
0x00004AD0       CMP R1 0
0x00004AD4       BNE nsfs_create_fail
    ;file created, now lookup the new file in the index table to get its inode
0x00004ADC       MOV R1 R8
    ; find file and create inode for the newly created file
0x00004AE0       BL nsfs_lookup
0x00004AE8       cmp R1 0
0x00004AEC       BEQ nsfs_create_fail
    ;inode found, return inode ptr in R1
0x00004AF4       POP R10
0x00004AF8       POP R9
0x00004AFC       POP R8
0x00004B00       POP R6
0x00004B04       POP LR
0x00004B08       RET

nsfs_create_fail:
0x00004B0C       LI R1 ERR_NOENT
0x00004B14       POP R10
0x00004B18       POP R9
0x00004B1C       POP R8
0x00004B20       POP R6
0x00004B24       POP LR
0x00004B28       RET

;=====================================================================
; get_path_len - get length of a NUL-terminated string
; in:  R1 = pointer to string
; out: R1 = length of string (not including NUL)
;=====================================================================
get_path_len:
0x00004B2C       PUSH LR
0x00004B30       PUSH R2
0x00004B34       PUSH R3
0x00004B38       LI R2 0
get_path_len_loop:
0x00004B40       LDB R3 [R1 + R2]
0x00004B44       CMP R3 0
0x00004B48       BEQ get_path_len_done
0x00004B50       ADD R2 R2 1
0x00004B54       B get_path_len_loop
get_path_len_done:
0x00004B5C       MOV R1 R2
0x00004B60       POP R3
0x00004B64       POP R2
0x00004B68       POP LR
0x00004B6C       RET

; nsfs_unlink
; in:  R1 = pathname
; out: R1 = 0 or errno
nsfs_unlink:
    ; TODO: FILE_DELETE over BMI and create whiteout when shadowing tarfs.
0x00004B70       LI R1 ERR_NOENT
0x00004B78       RET

;=====================================================================
; nsfs_mkdir - create a new directory in the NSFS overlay
;
; in:  R1 = pathname
;      R2 = namespace
;
; out: R1 = inode ptr if created, or errno
;=====================================================================

nsfs_mkdir:
0x00004B7C       PUSH LR
0x00004B80       PUSH R6
0x00004B84       PUSH R8
0x00004B88       PUSH R9
0x00004B8C       PUSH R10

0x00004B90       MOV R8 R1                  ; pathname
0x00004B94       MOV R10 R2                 ; namespace

0x00004B98       LI  R10 NSFS_DEFAULT_NS    ; default namespace for now

0x00004BA0       MOV R2 R8
0x00004BA4       BL  get_path_len
0x00004BAC       MOV R3 R1

0x00004BB0       LI  R1 DIR_CREATE
0x00004BB8       MOV R4 R10

0x00004BBC   CALL bmi_call

0x00004BC4       CMP R1 0
0x00004BC8       BNE nsfs_mkdir_fail

0x00004BD0       MOV R1 R10
0x00004BD4       BL  nsfs_refresh_index

0x00004BDC       CMP R1 0
0x00004BE0       BNE nsfs_mkdir_fail

0x00004BE8       MOV R1 R8
0x00004BEC       BL  nsfs_lookup

0x00004BF4       CMP R1 0
0x00004BF8       BEQ nsfs_mkdir_fail

0x00004C00       POP R10
0x00004C04       POP R9
0x00004C08       POP R8
0x00004C0C       POP R6
0x00004C10       POP LR
0x00004C14       RET

nsfs_mkdir_fail:
0x00004C18       LI R1 ERR_NOENT
0x00004C20       POP R10
0x00004C24       POP R9
0x00004C28       POP R8
0x00004C2C       POP R6
0x00004C30       POP LR
0x00004C34       RET

; nsfs_rmdir
; in:  R1 = pathname R2 = NS
; out: R1 = 0 or errno
nsfs_rmdir:
    ; TODO: DIR_DELETE over BMI.
0x00004C38       LI R1 ERR_NOENT
0x00004C40       RET

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

0x00004C44       PUSH LR

0x00004C48       MOV R8 R1                  ; save pathname ptr

0x00004C4C       LI R7 device_table
0x00004C54       LI R9 DEVICE_COUNT

lookup_loop:
0x00004C5C       CMP R9 0
0x00004C60       BEQ lookup_fail

    ; compare pathname with device name

0x00004C68       MOV R1 R8
0x00004C6C       LDW R2 [R7 + DEV_NAME]

0x00004C70       BL strcmp

0x00004C78       CMP R1 1
0x00004C7C       BEQ lookup_found

0x00004C84       ADD R7 R7 DEV_SIZE
0x00004C88       SUB R9 R9 1
0x00004C8C       B lookup_loop

lookup_found:

0x00004C94       MOV R1 R7                  ; return device descriptor ptr

0x00004C98       POP LR
0x00004C9C       RET

lookup_fail:

0x00004CA0       LI R1 0

0x00004CA8       POP LR
0x00004CAC       RET

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
0x00004CB0       LDB R3 [R1]
0x00004CB4       LDB R4 [R2]

0x00004CB8       CMP R3 R4
0x00004CBC       BNE str_not_equal

0x00004CC4       CMP R3 0
0x00004CC8       BEQ str_equal

0x00004CD0       ADD R1 R1 1
0x00004CD4       ADD R2 R2 1
0x00004CD8       B str_loop

str_equal:
0x00004CE0       LI R1 1
0x00004CE8       RET

str_not_equal:
0x00004CEC       LI R1 0
0x00004CF4       RET

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
0x00004CF8       PUSH R3
0x00004CFC       PUSH R4
    ;assume match ! unless first unequal
sp_loop:
0x00004D00       LDB R3 [R2]            ; prefix char
0x00004D04       CMP R3 0
0x00004D08       BEQ sp_match           ; reached end of prefix?

0x00004D10       LDB R4 [R1]            ; string char
0x00004D14       CMP R4 R3
0x00004D18       BNE sp_nomatch

0x00004D20       ADD R1 R1 1
0x00004D24       ADD R2 R2 1
0x00004D28       B sp_loop
sp_match:
0x00004D30       LI R1 1                 ;prefix ok
0x00004D38       POP R4
0x00004D3C       POP R3
0x00004D40       RET
sp_nomatch:
0x00004D44       LI R1 0                 ; not ok
0x00004D4C       POP R4
0x00004D50       POP R3
0x00004D54       RET

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
0x00004D58       PUSH R3
0x00004D5C       PUSH R4
sk_loop:
0x00004D60       LDB R3 [R2]            ; prefix char
0x00004D64       CMP R3 0
0x00004D68       BEQ sk_match           ; reached end of prefix
0x00004D70       LDB R4 [R1]            ; string char
0x00004D74       CMP R4 R3
0x00004D78       BNE sk_nomatch
0x00004D80       ADD R1 R1 1
0x00004D84       ADD R2 R2 1
0x00004D88       B sk_loop

sk_match:
    ; R1 already points past prefix
0x00004D90       POP R4
0x00004D94       POP R3
0x00004D98       RET

sk_nomatch:
0x00004D9C       LI R1 0                 ; no prefix/or prefix not matching with that in src string
0x00004DA4       POP R4
0x00004DA8       POP R3
0x00004DAC       RET

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
0x00004DB0       PUSH R2
0x00004DB4       PUSH R3
0x00004DB8       LI R2 0                ; length
pcl_loop:
0x00004DC0       LDB R3 [R1]
0x00004DC4       CMP R3 0
0x00004DC8       BEQ pcl_done
0x00004DD0       LI R4 47               ; '/'
0x00004DD8       CMP R3 R4
0x00004DDC       BEQ pcl_done
0x00004DE4       ADD R2 R2 1
0x00004DE8       ADD R1 R1 1
0x00004DEC       B pcl_loop
pcl_done:
0x00004DF4       MOV R1 R2
0x00004DF8       POP R3
0x00004DFC       POP R2
0x00004E00       RET

;====================================================================
; file_init using inode
; in: R1 = file pointe
;     R2 = inode pointer
;     R3 = open flags
; out:file structure initialized
;====================================================================
file_init:
    ; file->inode = inode
0x00004E04       STW R2 [R1 + FILE_INODE]
    ; file->offset = 0
0x00004E08       LI R4 0
0x00004E10       STW R4 [R1 + FILE_OFFSET]
    ; file->flags = O_RDONLY etc
0x00004E14       STW R3 [R1 + FILE_FLAGS]
     ; file->refcnt = 1
0x00004E18       LI R4 1
0x00004E20       STW R4 [R1 + FILE_REFCNT]
0x00004E24       RET

;====================================================================
; fd_alloc - set initialised file to process fd_table (dynamic space )
; in R1 = file pointer
; out R1 = fd number / R1 = ERR_MFILE if full
;
;====================================================================

fd_alloc:

0x00004E28       MOV R8 R1                  ; save file pointer

; macro: GET_CURR_TASK_IDX R4
0x00004E2C   LI R1 CURRENT_TASK
0x00004E34   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00004E38   LI R1 TASK_SIZE
0x00004E40   MUL R3 R4 R1
0x00004E44   LI R4 tasks
0x00004E4C   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4   ; R4 = fd table ptr
0x00004E50   LDW R4 [R4 + TASK_FD_TABLE]

0x00004E54       LI R5 3                    ; start after stdin/out/err dynamic space

fd_alloc_loop:

0x00004E5C       CMP R5 MAX_FDS
0x00004E60       BGE fd_alloc_fail

0x00004E68       SHL R6 R5 2                ; fd * 4
0x00004E6C       ADD R7 R4 R6               ; &fd_table[fd]

0x00004E70       LDW R2 [R7]
0x00004E74       CMP R2 0                   ; 0 - empty
0x00004E78       BEQ fd_alloc_found

0x00004E80       ADD R5 R5 1
0x00004E84       B fd_alloc_loop

fd_alloc_found:

0x00004E8C       STW R8 [R7]                ; fd_table[fd] = file*

0x00004E90       MOV R1 R5                  ; return fd
0x00004E94       RET

fd_alloc_fail:

0x00004E98       LI R1 ERR_MFILE
0x00004EA0       RET

syscall_close:
    ;================================================================
    ; in R1 = fd
    ; out R1 = 0 / err -1
    ;================================================================
0x00004EA4       LDW R1 [SP + TF_R1]

0x00004EA8       BL vfs_close

0x00004EB0       LI R1 0
0x00004EB8       STW R1 [SP + TF_R1]

0x00004EBC       B trap_restore

syscall_pipe:
    ;================================================================
    ; create a pipe object
    ; in R1 = &fd[2] empty array
    ; out R1 = 0 / NULL , fd[2] populated  fd[0]-read end fd[1]-write end
    ;     R1 = -1 err
    ;================================================================

    ; user int fd[2]
0x00004EC4       LDW R7 [SP + TF_R1]

0x00004EC8       BL pipe_alloc       ;create new pipe object in pipe_pool
0x00004ED0       CMP R1 0
0x00004ED4       BEQ pipe_fail_nospc

0x00004EDC       MOV R8 R1            ; new slot in pipe_pool ( pipe* )
    ; [0] read end          write[1]>--pipe--->read[0]
0x00004EE0       BL file_alloc        ; R1 - created read file ptr for read end
0x00004EE8       CMP R1 0
0x00004EEC       BEQ pipe_fail_read_fd

0x00004EF4       MOV R9 R1           ; new file for read end  in file_pool
0x00004EF8       BL inode_alloc      ; get inode for this end file
0x00004F00       CMP R1 0
0x00004F04       BEQ pipe_fail_ia_read_fd
0x00004F0C       MOV R10 R1

0x00004F10       LI  R2 pipe_ops         ; pipe_ops table
0x00004F18       MOV R3 R8               ; store our slot pipe*
0x00004F1C       LI  R4 INODE_PIPE       ; inode type PIPE
0x00004F24       LI  R5 0                ; size =0
0x00004F2C       BL inode_init           ; make inode for read end

    ; initialize file object ;read end file
0x00004F34       MOV R1 R9                ; R1 file*
0x00004F38       MOV R2 R10               ; inode*
0x00004F3C       LI R3  FD_FLAG_READ      ; flags READ end
0x00004F44       BL file_init

0x00004F4C       MOV R1 R9
0x00004F50       BL fd_alloc                 ; insert read file to fd_table of user process

0x00004F58       LI R2 ERR_MFILE             ; check if fd_alloc problem
0x00004F60       CMP R1 R2
0x00004F64       BEQ pipe_fail_read_file

0x00004F6C       MOV R12 R1           ; get file read fd created to R10

    ; same for write end
0x00004F70       BL file_alloc
0x00004F78       CMP R1 0
0x00004F7C       BEQ pipe_fail_ia_write_fd
0x00004F84       MOV R9 R1

0x00004F88       BL inode_alloc      ; get inode for this end file
0x00004F90       CMP R1 0
0x00004F94       BEQ pipe_fail_ia_write_fd
0x00004F9C       MOV R10 R1

0x00004FA0       LI  R2 pipe_ops         ; pipe_ops table
0x00004FA8       MOV R3 R8               ; store our slot pipe* need to check if this is ok here (might be changed)
0x00004FAC       LI  R4 INODE_PIPE       ; inode type PIPE
0x00004FB4       LI  R5 0                ; size =0
0x00004FBC       BL inode_init           ; make inode for write end

    ; initialize file object ;write end file
0x00004FC4       MOV R1 R9                ; R1 file*
0x00004FC8       MOV R2 R10               ; inode*
0x00004FCC       LI  R3 FD_FLAG_WRITE     ; flags WRITE end
0x00004FD4       BL file_init

0x00004FDC       MOV R1 R9
0x00004FE0       BL  fd_alloc

0x00004FE8       LI  R2 ERR_MFILE         ; check if fd_alloc problem
0x00004FF0       CMP R1 R2
0x00004FF4       BEQ pipe_fail_write_file

0x00004FFC       MOV R11 R1           ; R11 is write and fd R12 is read fd

0x00005000       MOV R1 R7    ; in &fd[2]. not sure if R7 still has value for this ptr
0x00005004       LI  R2 8     ; len 2 words (8 bytes)
0x0000500C       LI  R3 1     ; mem perm to write cond
0x00005014       BL  user_buffer_valid_range
0x0000501C       CMP R1 1
0x00005020       BNE pipe_fail_both_fds

0x00005028       STW R12 [R7]     ;fill fd user array of read and write ends fd[0]-rd fd[1]-wr
0x0000502C       STW R11 [R7 + 4]

0x00005030       LI R1 0
0x00005038       STW R1 [SP + TF_R1]

0x0000503C       B trap_restore

pipe_fail:
0x00005044       LI R1 ERR_IO
0x0000504C       STW R1 [SP + TF_R1]

0x00005050       B trap_restore

pipe_fail_both_fds:
0x00005058       MOV R12 R8
0x0000505C       MOV R1 R11
0x00005060       BL fd_remove
0x00005068       CMP R1 0
0x0000506C       BEQ pipe_fail_both_fds_read
0x00005074       BL file_free

pipe_fail_both_fds_read:
0x0000507C       MOV R1 R10
0x00005080       BL fd_remove
0x00005088       CMP R1 0
0x0000508C       BEQ pipe_fail_free_pipe_fault
0x00005094       BL file_free

pipe_fail_free_pipe_fault:
0x0000509C       MOV R1 R12
0x000050A0       BL pipe_free
0x000050A8       LI R1 ERR_FAULT
0x000050B0       STW R1 [SP + TF_R1]

0x000050B4       B trap_restore

pipe_fail_write_file:
0x000050BC       MOV R12 R8
0x000050C0       MOV R1 R9
0x000050C4       BL file_free
0x000050CC       MOV R1 R10
0x000050D0       BL fd_remove
0x000050D8       CMP R1 0
0x000050DC       BEQ pipe_fail_free_pipe_mfile
0x000050E4       BL file_free

pipe_fail_free_pipe_mfile:
0x000050EC       MOV R1 R12
0x000050F0       BL pipe_free
0x000050F8       LI R1 ERR_MFILE
0x00005100       STW R1 [SP + TF_R1]

0x00005104       B trap_restore

pipe_fail_read_fd:
0x0000510C       MOV R12 R8
0x00005110       MOV R1 R10
0x00005114       BL fd_remove
0x0000511C       CMP R1 0
0x00005120       BEQ pipe_fail_free_pipe_nfile
0x00005128       BL file_free

pipe_fail_free_pipe_nfile:
0x00005130       MOV R1 R12
0x00005134       BL pipe_free
0x0000513C       LI R1 ERR_NFILE
0x00005144       STW R1 [SP + TF_R1]

0x00005148       B trap_restore

pipe_fail_read_file:
0x00005150       MOV R12 R8
0x00005154       MOV R1 R9
0x00005158       BL file_free
0x00005160       MOV R1 R10          ; освободить inode read end
0x00005164       BL inode_free
0x0000516C       MOV R1 R12
0x00005170       BL pipe_free
0x00005178       LI R1 ERR_MFILE
0x00005180       STW R1 [SP + TF_R1]

0x00005184       B trap_restore

pipe_fail_pipe_only:
0x0000518C       MOV R1 R8
0x00005190       BL pipe_free
0x00005198       LI R1 ERR_NFILE
0x000051A0       STW R1 [SP + TF_R1]

0x000051A4       B trap_restore

pipe_fail_nospc:
0x000051AC       LI R1 ERR_NOSPC
0x000051B4       STW R1 [SP + TF_R1]

0x000051B8       B trap_restore

pipe_fail_ia_read_fd:
    ; Ошибка при создании inode для read end
0x000051C0       MOV R1 R9          ; освобождаем file (read end)
0x000051C4       BL  file_free
0x000051CC       MOV R1 R8          ; освобождаем pipe
0x000051D0       BL  pipe_free
0x000051D8       LI R1 ERR_NFILE    ; или ERR_NOMEM - смотрите ваши коды ошибок
0x000051E0       STW R1 [SP + TF_R1]
0x000051E4       B trap_restore

pipe_fail_ia_write_fd:
    ; Ошибка при создании inode для write end
0x000051EC       MOV R1 R12         ; освобождаем read fd (если уже создан)
0x000051F0       BL fd_remove
0x000051F8       CMP R1 0
0x000051FC       BEQ skip_file_free_read
0x00005204       BL file_free
skip_file_free_read:
0x0000520C       MOV R1 R9          ; освобождаем file (write end)
0x00005210       BL file_free
0x00005218       MOV R1 R8          ; освобождаем pipe
0x0000521C       BL pipe_free
0x00005224       LI R1 ERR_NFILE
0x0000522C       STW R1 [SP + TF_R1]
0x00005230       B trap_restore

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

0x00005238       LDW R1 [SP + TF_R1]     ; argument fd

0x0000523C       BL fd_lookup            ; lookup FILE*
0x00005244       CMP R1 0
0x00005248       BEQ dup_badfd
0x00005250       MOV R8 R1               ; keep FILE*

0x00005254       BL file_get             ; FILE.ref++

0x0000525C       MOV R1 R8
0x00005260       BL fd_alloc             ; try to allocate new fd

0x00005268       LI R2 ERR_MFILE
0x00005270       CMP R1 R2
0x00005274       BEQ dup_fail_fd

0x0000527C       STW R1 [SP + TF_R1] ;R1 - new fd
0x00005280       B trap_restore

dup_fail_fd:

0x00005288       MOV R1 R8
0x0000528C       BL file_put

0x00005294       LI R1 ERR_MFILE     ;R1 -err + rollback
0x0000529C       STW R1 [SP + TF_R1]
0x000052A0       B trap_restore

dup_badfd:

0x000052A8       LI R1 ERR_BADF      ;R1 -err + file not found
0x000052B0       STW R1 [SP + TF_R1]

0x000052B4       B trap_restore

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

0x000052BC       LDW R8 [SP + TF_R1]         ; user pointer to struct timeval

    ;----------------------------------------------------------
    ; Validate destination buffer
    ;----------------------------------------------------------

0x000052C0       MOV R1 R8
0x000052C4       LI  R2 TIMEVAL_SIZE
0x000052CC       LI  R3 1                   ; write access
0x000052D4       BL  user_buffer_valid_range

0x000052DC       CMP R1 1
0x000052E0       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Get current kernel time
    ;----------------------------------------------------------

0x000052E8       BL clock_gettime           ;out: R1=sec, R2=usec

    ;----------------------------------------------------------
    ; Build timeval in kernel buffer
    ;----------------------------------------------------------

; macro: GET_CURR_TASK_IDX R4
0x000052F0   LI R1 CURRENT_TASK
0x000052F8   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000052FC   LI R1 TASK_SIZE
0x00005304   MUL R3 R4 R1
0x00005308   LI R5 tasks
0x00005310   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R6, R5   ; R6 ptr kbuf_wr
0x00005314   LDW R6 [R5 + TASK_KBUF_WR_PTR]

0x00005318       STW R1 [R6 + TIMEVAL_SEC]
0x0000531C       STW R2 [R6 + TIMEVAL_USEC]

    ;----------------------------------------------------------
    ; Copy to user
    ;----------------------------------------------------------

0x00005320       MOV R1 R8                  ; user destination
0x00005324       LI  R2 TIMEVAL_SIZE        ; size in bytes (8)
0x0000532C       MOV R4 R6                  ; kernel source

0x00005330       BL copy_to_user

0x00005338       CMP R1 TIMEVAL_SIZE
0x0000533C       BNE gettime_badptr

    ;----------------------------------------------------------
    ; Success
    ;----------------------------------------------------------

0x00005344       LI R1 0
0x0000534C       STW R1 [SP + TF_R1]

0x00005350       B trap_restore

gettime_badptr:

0x00005358       LI R1 ERR_FAULT
0x00005360       STW R1 [SP + TF_R1]

0x00005364       B trap_restore

; ================================================================
; syscall_brk - Set program break
;
; R1 = new break address (must be within data page)
;
; Returns:
;   R1 = new break address on success, -1 on error
; ================================================================

syscall_brk:
0x0000536C       LDW R8 [SP + TF_R1]        ; R8 = new break address (user space VA)

    ; Validate the address is within the data page
0x00005370       LI R2 HEAP_START
0x00005378       CMP R8 R2
0x0000537C       BLT brk_invalid            ; if new break is below data page, return error

0x00005384       LI R2 HEAP_END
0x0000538C       CMP R8 R2
0x00005390       BGT brk_invalid            ; if new break is above last address in data page, return error

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x00005398   LI R1 CURRENT_TASK
0x000053A0   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000053A4   LI R1 TASK_SIZE
0x000053AC   MUL R3 R4 R1
0x000053B0   LI R5 tasks
0x000053B8   ADD R5 R5 R3

    ; Set new break in task struct
    ; (We'll add this field to TASK structure)
; macro: TASK_SET_BREAK R5, R8
0x000053BC   STW R8 [R5 + TASK_BREAK]

    ; Return new break
0x000053C0       STW R8 [SP + TF_R1]

0x000053C4       B trap_restore

brk_invalid:
    ; Return -1
0x000053CC       LI R1 ERR_FAULT
0x000053D4       STW R1 [SP + TF_R1]

0x000053D8       B trap_restore

; ================================================================
; syscall_sbrk - Increment program break (set new break relative to current ie sbrk)
;
; R1 = increment (can be negative) update current break by this value
;
; Returns:
;   R1 = old break address on success, -1 on error
; ================================================================

syscall_sbrk:
0x000053E0       LDW R8 [SP + TF_R1]        ; R8 = increment

    ; Get current task
; macro: GET_CURR_TASK_IDX R4
0x000053E4   LI R1 CURRENT_TASK
0x000053EC   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x000053F0   LI R1 TASK_SIZE
0x000053F8   MUL R3 R4 R1
0x000053FC   LI R5 tasks
0x00005404   ADD R5 R5 R3

    ; Get current break
; macro: TASK_GET_BREAK R9, R5
0x00005408   LDW R9 [R5 + TASK_BREAK]

    ; Calculate new break
0x0000540C       ADD R10 R9 R8

    ; Validate it's within the data page
0x00005410       LI R2 HEAP_START
0x00005418       CMP R10 R2
0x0000541C       BLT sbrk_invalid

0x00005424       LI R2 HEAP_END
0x0000542C       CMP R10 R2
0x00005430       BGT sbrk_invalid

    ; Return old break
0x00005438       STW R9 [SP + TF_R1]     ; old break address

    ; Update break
; macro: TASK_SET_BREAK R5, R10  ;R10 - updated break address
0x0000543C   STW R10 [R5 + TASK_BREAK]

0x00005440       B trap_restore

sbrk_invalid:
    ; Return -1
0x00005448       LI R1 ERR_FAULT
0x00005450       STW R1 [SP + TF_R1]
0x00005454       B trap_restore

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

0x0000545C       LI  R3 timer_ticks
0x00005464       LDW R4 [R3]                ; tick counter (1 ms per tick)

    ; seconds = ticks / 1000
0x00005468       MOV R1 R4
0x0000546C       LI  R5 1000
0x00005474       DIV R1 R1 R5

    ; usec = (ticks % 1000) * 1000
0x00005478       MOD R4 R4 R5
0x0000547C       LI  R5 1000
0x00005484       MUL R2 R4 R5

0x00005488       RET

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

0x0000548C       PUSH LR

0x00005490       MOV R9 R1              ; file*
0x00005494       MOV R7 R2              ; user buffer
0x00005498       MOV R6 R3              ; requested len

0x0000549C       LDW R9 [R9 + FILE_INODE]
0x000054A0       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)
0x000054A4       CMP R6 0                ;fast clear from it if len=0
0x000054A8       BEQ pipe_read_done
;-----------------------------------------
; validate user destination buffer
;-----------------------------------------
0x000054B0       PUSH R7
0x000054B4       PUSH R6

0x000054B8       MOV R1 R7
0x000054BC       MOV R2 R6
0x000054C0       LI  R3 1               ; write access
0x000054C8       BL user_buffer_valid_range

0x000054D0       POP R6
0x000054D4       POP R7
0x000054D8       CMP R1 1
0x000054DC       BNE pipe_read_badptr

pipe_read_retry:
;-----------------------------------------
; anything in pipe?
;-----------------------------------------
0x000054E4       LDW R4 [R9 + PIPE_COUNT]
0x000054E8       CMP R4 0
0x000054EC       BEQ pipe_read_sleep     ;go to sleep
;-----------------------------------------
; bytes_to_read=min(len (R6),count(R4)
;-----------------------------------------
0x000054F4       CMP R6 R4
0x000054F8       BLT pipe_user_len

0x00005500       MOV R5 R4
0x00005504       B pipe_have_amount

pipe_user_len:
0x0000550C       MOV R5 R6

pipe_have_amount:
0x00005510       LI R10 0              ; bytes copied

pipe_read_loop:         ;cpy pipe_buffer to user with min(pipe_count,len) bytes
0x00005518       CMP R10 R5
0x0000551C       BGE pipe_read_done

;------------------------------------------
; tail = pipe->tail (idx in PIPE_BUFFER in pipe*(R9) struc)
;------------------------------------------
0x00005524       LDW R11 [R9 + PIPE_TAIL]
;------------------------------------------
; R12 addr = pipe + PIPE_BUFFER
;------------------------------------------
0x00005528       MOV R12 R9
0x0000552C       ADD R12 R12 PIPE_BUFFER
0x00005530       ADD R12 R12 R11         ; addr += tail

0x00005534       LDB R4 [R12]    ;read data from buffer[tail_idx]

;------------------------------------------
; useraddr=userbuf+copied
;------------------------------------------
0x00005538       MOV R12 R7
0x0000553C       ADD R12 R12 R10

0x00005540       STB R4 [R12]    ;copy to user side

;------------------------------------------
    ; tail=(tail+1)&255
;------------------------------------------
0x00005544       ADD R11 R11 1   ;update tail inc idx if idx > 255 idx=0
0x00005548       LI R2 255
0x00005550       AND R11 R11 R2
0x00005554       STW R11 [R9 + PIPE_TAIL]    ;save to pipe struc updated tail_idx
;------------------------------------------
; count-- (update to struc)
;------------------------------------------
0x00005558       LDW R12 [R9 + PIPE_COUNT]
0x0000555C       SUB R12 R12 1
0x00005560       STW R12 [R9 + PIPE_COUNT]

    ; copied++ loop counter
0x00005564       ADD R10 R10 1
0x00005568       B pipe_read_loop

pipe_read_done:
; wake blocked writers
0x00005570       MOV R1 R9
0x00005574       ADD R1 R1 PIPE_WWAIT
0x00005578       BL waitq_wake_all
0x00005580       MOV R1 R10          ; read bytes amount
0x00005584       POP LR
0x00005588       RET

pipe_read_badptr:
0x0000558C       LI R1 ERR_FAULT
0x00005594       POP LR
0x00005598       RET

pipe_read_sleep:
;------------------------------------------
; prepare sleep
;------------------------------------------
0x0000559C       MOV R1 R9
0x000055A0       ADD R1 R1 PIPE_RWAIT    ;ptr on wait queue read in pipe instance
0x000055A4       LI R2 WAIT_PIPE_READ    ;REASON for block in process (debug)
0x000055AC       BL waitq_prepare_sleep

;------------------------------------------
; race check
;------------------------------------------
0x000055B4       LDW R4 [R9 + PIPE_COUNT]
0x000055B8       CMP R4 0
0x000055BC       BNE pipe_read_retry

0x000055C4       BL waitq_sleep_current  ;freesze here untill unblock
    ;data arrived/unbloked
0x000055CC       B pipe_read_retry

;later sort out  issue: pipe_fail leaks objects
;pipe_alloc OK
;file_alloc OK
;fd_alloc FAIL

pipe_alloc:
    ;================================================================
    ; in nothing
    ; out R1 ptr to new slot in pipe_pool, or R1 = 0 if no slots
    ;================================================================

0x000055D4       LI R2 0

pipe_loop:
0x000055DC       LI  R1 MAX_PIPES
0x000055E4       CMP R2 R1
0x000055E8       BGE pipe_alloc_fail

0x000055F0       SHL R3 R2 2

0x000055F4       LI R4 pipe_used
0x000055FC       ADD R4 R4 R3

0x00005600       LDW R5 [R4]             ;R4 address in PIPE_USED LIST

0x00005604       CMP R5 0                ; 0 -empty
0x00005608       BEQ pipe_found

0x00005610       ADD R2 R2 1
0x00005614       B pipe_loop

pipe_found:

0x0000561C       LI R5 1
0x00005624       STW R5 [R4]             ; set it in PIPE_USED =1 as used

0x00005628       LI R4 PIPE_SIZE
0x00005630       MUL R6 R2 R4            ; r2 - is idx so get full offset = PIPE_SIZE*idx

0x00005634       LI R1 pipe_pool         ; R1 - is address of the to be allocated slot in pipe_pool
0x0000563C       ADD R1 R1 R6

0x00005640       LI R7 0                 ; clean it up
0x00005648       STW R7 [R1 + PIPE_HEAD]
0x0000564C       STW R7 [R1 + PIPE_TAIL]
0x00005650       STW R7 [R1 + PIPE_COUNT]
0x00005654       STW R7 [R1 + PIPE_RWAIT]
0x00005658       STW R7 [R1 + PIPE_WWAIT]
    ; R1 - address of the slot
0x0000565C       RET

pipe_alloc_fail:
    ; R1 = NULL
0x00005660       LI R1 0
0x00005668       RET

pipe_free:
    ;================================================================
    ; in R1 = pipe pointer from pipe_pool
    ; marks the pipe slot free
    ;================================================================

0x0000566C       LI R2 pipe_pool
0x00005674       SUB R3 R1 R2

0x00005678       LI R4 PIPE_SIZE
0x00005680       DIV R5 R3 R4

0x00005684       SHL R5 R5 2
0x00005688       LI R6 pipe_used
0x00005690       ADD R6 R6 R5

0x00005694       LI R7 0
0x0000569C       STW R7 [R6]

0x000056A0       RET

pipe_write:
;--------------------------------------------------
; R1 = file*
; R2 = user buffer
; R3 = length
;
; return:
;   R1 = bytes written
;--------------------------------------------------
0x000056A4       PUSH LR

0x000056A8       MOV R9 R1
0x000056AC       MOV R7 R2
0x000056B0       MOV R6 R3

0x000056B4       LDW R9 [R9 + FILE_INODE]
0x000056B8       LDW R9 [R9 + INODE_PRIVATE] ;get our Pipe instance allocated in pipe_pool (pipe*) (from its inode)

    ;---------------------------------------
    ; validate user source buffer
    ;---------------------------------------

0x000056BC       PUSH R7
0x000056C0       PUSH R6

0x000056C4       MOV R1 R7
0x000056C8       MOV R2 R6
0x000056CC       LI  R3 0           ; READ access
0x000056D4       BL user_buffer_valid_range

0x000056DC       POP R6
0x000056E0       POP R7

0x000056E4       CMP R1 1
0x000056E8       BNE pipe_write_badptr

0x000056F0       LI R10 0               ; bytes written
pipe_write_retry:
0x000056F8       CMP R10 R6
0x000056FC       BGE pipe_write_done
;------------------------------------------
; pipe full ?
;------------------------------------------
0x00005704       LDW R11 [R9 + PIPE_COUNT]
0x00005708       LI R2 256
0x00005710       CMP R11 R2
0x00005714       BEQ pipe_write_sleep
;------------------------------------------
; head = pipe->head
;------------------------------------------
0x0000571C       LDW R12 [R9 + PIPE_HEAD]

0x00005720       MOV R4 R7
0x00005724       ADD R4 R4 R10
0x00005728       LDB R5 [R4]     ; read byte from user buff addr

0x0000572C       MOV R4 R9
0x00005730       ADD R4 R4 PIPE_BUFFER
0x00005734       ADD R4 R4 R12
0x00005738       STB R5 [R4]     ; put it to pipe addr - ie write user -> pipe buff

;------------------------------------------
; head=(head+1)&255
;------------------------------------------
0x0000573C       ADD R12 R12 1
0x00005740       LI R2 255
0x00005748       AND R12 R12 R2
0x0000574C       STW R12 [R9 + PIPE_HEAD]
;------------------------------------------
; count++
;------------------------------------------
0x00005750       LDW R4 [R9 + PIPE_COUNT]
0x00005754       ADD R4 R4 1
0x00005758       STW R4 [R9 + PIPE_COUNT]

; written++
0x0000575C       ADD R10 R10 1
0x00005760       B pipe_write_retry

pipe_write_done:
; wake readers
0x00005768       MOV R1 R9
0x0000576C       ADD R1 R1 PIPE_RWAIT    ; wq ptr from pipe*
0x00005770       BL waitq_wake_all
0x00005778       MOV R1 R10      ;written bytes
0x0000577C       POP LR
0x00005780       RET

pipe_write_badptr:
0x00005784       LI R1 ERR_FAULT
0x0000578C       POP LR
0x00005790       RET

pipe_write_empty:
0x00005794       LI R1 0
0x0000579C       POP LR
0x000057A0       RET

pipe_write_sleep:
;setup tasks for block on write (pipe buffer is full)
0x000057A4       MOV R1 R9
0x000057A8       ADD R1 R1 PIPE_WWAIT    ; wq ptr from pipe*
0x000057AC       LI R2 WAIT_PIPE_WRITE
0x000057B4       BL waitq_prepare_sleep
    ; race check
0x000057BC       LDW R4 [R9 + PIPE_COUNT]
0x000057C0       LI R2 256
0x000057C8       CMP R4 R2
0x000057CC       BLT pipe_write_retry    ;if not full dont block/frezze go write

0x000057D4       BL waitq_sleep_current  ;block anf freeze writer here until reading buffer frees room in pipe!

0x000057DC       B pipe_write_retry      ; unblocked! go write!



;================================================================
; fd_lookup - найти file* по номеру fd
; in:  R1 = fd (номер дескриптора)
; out: R1 = file* (указатель на структуру файла) или 0 если не найден
;      R2 = указатель на ячейку в fd_table (для использования в fd_remove)
;================================================================
fd_lookup:
    ; Проверка валидности fd
0x000057E4       CMP R1 3
0x000057E8       BLT fd_lookup_invalid       ; fd 0,1,2 - stdio, нельзя закрыть пользователю
0x000057F0       CMP R1 MAX_FDS
0x000057F4       BGE fd_lookup_invalid       ; fd >= MAX_FDS - вне диапазона

0x000057FC       MOV R8 R1                   ; сохраняем fd
    ; Получаем указатель на fd_table текущего процесса
; macro: GET_CURR_TASK_IDX R4
0x00005800   LI R1 CURRENT_TASK
0x00005808   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x0000580C   LI R1 TASK_SIZE
0x00005814   MUL R3 R4 R1
0x00005818   LI R4 tasks
0x00005820   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4    ; R4 = &fd_table[0]
0x00005824   LDW R4 [R4 + TASK_FD_TABLE]

    ; Вычисляем адрес fd_table[fd]
0x00005828       SHL R5 R8 2                 ; R5 = fd * 4 (размер указателя)
0x0000582C       ADD R6 R4 R5                ; R6 = &fd_table[fd]

0x00005830       LDW R1 [R6]                 ; R1 = file* из таблицы
0x00005834       CMP R1 0
0x00005838       BEQ fd_lookup_invalid       ; если NULL - дескриптор не занят

0x00005840       MOV R2 R6                   ; возвращаем адрес ячейки для fd_remove
0x00005844       RET

fd_lookup_invalid:
0x00005848       LI R1 0
0x00005850       LI R2 0
0x00005858       RET

 ;================================================================
 ;  frees fd_entry of this fd ; fd_table[fd] = null + gives this file_ptr for file_free
 ;  in R1 = fd
 ;  out R1 = file* / R1 = 0 if invalid
 ;================================================================
 fd_remove:
0x0000585C       PUSH LR
0x00005860       BL  fd_lookup
0x00005868       CMP R1 0
0x0000586C       BEQ fd_remove_invalid

0x00005874       MOV R8 R1          ; сохраняем file*
0x00005878       LI R3 0
0x00005880       STW R3 [R2]        ; fd_table[fd] = NULL (R2 из fd_lookup)
0x00005884       MOV R1 R8          ; file*
0x00005888       POP LR
0x0000588C       RET

fd_remove_invalid:
0x00005890       LI R1 0
0x00005898       POP LR
0x0000589C       RET


syscall_read:
    ;================================================================
    ; R1 = fd (from trapframe)
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x000058A0       LDW R1 [SP + TF_R1]
0x000058A4       LDW R2 [SP + TF_R2]
0x000058A8       LDW R3 [SP + TF_R3]

0x000058AC       BL vfs_read

0x000058B4       STW R1 [SP + TF_R1]
0x000058B8       B trap_restore

; to comply with vfs interface
devfs_open:
0x000058C0       LI R1 0
0x000058C8       RET
devfs_close:
0x000058CC       LI R1 0
0x000058D4       RET


devfs_read:
    ;================================================================
    ; R1 = file ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device read loop!
    ;================================================================

0x000058D8       PUSH LR
0x000058DC       PUSH R8
0x000058E0       PUSH R9
0x000058E4       PUSH R10
0x000058E8       PUSH R11
0x000058EC       PUSH R12
0x000058F0       MOV R9 R1
0x000058F4       MOV R7 R2
0x000058F8       MOV R6 R3
0x000058FC       LI R8 0                    ; total bytes collected
0x00005904       LDW R9 [R9 + FILE_INODE]
0x00005908       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x0000590C       CMP R6 0
0x00005910       BEQ read_done

0x00005918       PUSH R7
0x0000591C       PUSH R6
0x00005920       PUSH R9
0x00005924       MOV R1 R7
0x00005928       MOV R2 R6
0x0000592C       LI R3 1                ; write access for destination buffer
0x00005934       BL user_buffer_valid_range
0x0000593C       POP R9
0x00005940       POP R6
0x00005944       POP R7
0x00005948       CMP R1 1
0x0000594C       BNE con_read_fault

read_wait_uart_rx:
0x00005954       LDW R4 [R9 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00005958       LDW R5 [R4 + 4]             ; read UART_STATUS register
0x0000595C       AND R5 R5 1                 ; bit 0 = RX_READY
0x00005960       CMP R5 0
0x00005964       BEQ read_block_uart_rx      ; bit 0=0 no data yet in rx_queue, block this curr user task inside syscall

; macro: GET_CURR_TASK_IDX R4
0x0000596C   LI R1 CURRENT_TASK
0x00005974   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005978   LI R1 TASK_SIZE
0x00005980   MUL R3 R4 R1
0x00005984   LI R5 tasks
0x0000598C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_RD R1, R5
0x00005990   LDW R1 [R5 + TASK_KBUF_RD_PTR]
0x00005994       MOV R2 R6
0x00005998       MOV R3 R9
0x0000599C       PUSH R6
0x000059A0       PUSH R7
0x000059A4       PUSH R8
0x000059A8       PUSH R9
0x000059AC       BL device_read          ;read data from rx_queue to KBUFFER_RD len=R2(<- R6) or if 0xd (enter sign)
0x000059B4       POP R9
0x000059B8       POP R8
0x000059BC       POP R7
0x000059C0       POP R6

0x000059C4       CMP R1 0
0x000059C8       BEQ read_wait_uart_rx

0x000059D0       MOV R10 R1             ; actual bytes read

; macro: GET_CURR_TASK_IDX R5
0x000059D4   LI R1 CURRENT_TASK
0x000059DC   LDW R5 [R1]
; macro: GET_TASK_PTR R4, R5
0x000059E0   LI R1 TASK_SIZE
0x000059E8   MUL R3 R5 R1
0x000059EC   LI R4 tasks
0x000059F4   ADD R4 R4 R3
; macro: TASK_GET_KBUF_RD R4, R4
0x000059F8   LDW R4 [R4 + TASK_KBUF_RD_PTR]

    ; Remember whether this chunk ended with CR/LF before copy_to_user
    ; clobbers temporary registers.
0x000059FC       LI R11 0
0x00005A04       SUB R5 R10 1
0x00005A08       ADD R5 R4 R5
0x00005A0C       LDB R5 [R5]
0x00005A10       CMP R5 10
0x00005A14       BEQ read_chunk_line_done
0x00005A1C       CMP R5 13
0x00005A20       BNE read_chunk_not_newline
read_chunk_line_done:
0x00005A28       LI R11 1

read_chunk_not_newline:
0x00005A30       PUSH R6
0x00005A34       PUSH R7
0x00005A38       PUSH R8
0x00005A3C       PUSH R9
0x00005A40       PUSH R10
0x00005A44       PUSH R11
0x00005A48       MOV R1 R7              ; user destination
0x00005A4C       MOV R2 R10
0x00005A50       BL copy_to_user        ; copy from kernel buffer to user buffer
0x00005A58       POP R11
0x00005A5C       POP R10
0x00005A60       POP R9
0x00005A64       POP R8
0x00005A68       POP R7
0x00005A6C       POP R6

0x00005A70       ADD R7 R7 R10
0x00005A74       ADD R8 R8 R10
0x00005A78       SUB R6 R6 R10

0x00005A7C       CMP R11 1
0x00005A80       BEQ read_complete
0x00005A88       CMP R6 0
0x00005A8C       BGT read_wait_uart_rx

read_complete:
0x00005A94       MOV R1 R8
0x00005A98       B read_return

read_block_uart_rx:
    ; Put the current task on the UART RX wait queue before the re-check.
    ; This ordering prevents a lost wakeup if an IRQ arrives between the
    ; status check above and the actual scheduler sleep.
0x00005AA0       LI R1 uart_rx_waitq
0x00005AA8       LI R2 WAIT_UART_RX
0x00005AB0       BL waitq_prepare_sleep

0x00005AB8       LDW R4 [R9 + UARTDEV_MMIO]
0x00005ABC       LDW R10 [R4 + 4]             ; re-check uart reg RX-ready bit 0 after marking blocked
0x00005AC0       AND R10 R10 1
0x00005AC4       CMP R10 0
0x00005AC8       BNE read_unblock_uart_rx     ; if data arrived, cancel sleep and read it

0x00005AD0       BL waitq_sleep_current       ; save this user task as frozen in kernel space

0x00005AD8       B read_wait_uart_rx          ;repeat read uart loop

read_unblock_uart_rx:            ;mark current task as unblocked
0x00005AE0       LI R1 uart_rx_waitq
0x00005AE8       BL waitq_cancel_sleep_current

0x00005AF0       B read_wait_uart_rx          ;go back and read bytes

read_done:
0x00005AF8       LI R1 0
0x00005B00       B read_return

con_read_fault:
0x00005B08       LI R1 ERR_FAULT

read_return:
0x00005B10       POP R12
0x00005B14       POP R11
0x00005B18       POP R10
0x00005B1C       POP R9
0x00005B20       POP R8
0x00005B24       POP LR
0x00005B28       RET

syscall_write:
    ;================================================================
    ; R1 = fd 0-1-2
    ; R2 = user buffer
    ; R3 = length
    ;================================================================

0x00005B2C       LDW R1 [SP + TF_R1]
0x00005B30       LDW R2 [SP + TF_R2]
0x00005B34       LDW R3 [SP + TF_R3]

0x00005B38       BL vfs_write

0x00005B40       STW R1 [SP + TF_R1]
0x00005B44       B trap_restore


devfs_write:
    ;================================================================
    ; R1 = file struc ptr
    ; R2 = user buffer
    ; R3 = length
    ; this is specific con device write loop!
    ;================================================================

0x00005B4C       PUSH LR
0x00005B50       MOV R9 R1
0x00005B54       MOV R7 R2
0x00005B58       MOV R6 R3
0x00005B5C       LDW R9 [R9 + FILE_INODE]
0x00005B60       LDW R9 [R9 + INODE_PRIVATE] ; console device pointer
0x00005B64       LI R8 0                    ; total bytes written
                               ;also R6-len R7-user buf ptr R9-file struc ptr
write_loop:
0x00005B6C       CMP R6 0
0x00005B70       BEQ write_done             ;0 bytes

0x00005B78       LI R2 KBUFFER_SIZE
0x00005B80       CMP R6 R2                  ;here we write in chunks to dev, last one is small chunk (less then Kbuffer_size)
0x00005B84       BLT write_chunk_small
0x00005B8C       LI R2 KBUFFER_SIZE

0x00005B94       B write_chunk

write_chunk_small:
0x00005B9C       MOV R2 R6

write_chunk:
    ;================================================================
    ; Validate user buffer and length for this chunk. This is required
    ; before copying to kernel buffer or accessing the device, to prevent
    ; buffer overflows or invalid memory accesses.
    ;================================================================

0x00005BA0       PUSH R7
0x00005BA4       PUSH R6
0x00005BA8       PUSH R9
0x00005BAC       PUSH R8
0x00005BB0       MOV R1 R7
0x00005BB4       MOV R2 R2
0x00005BB8       LI R3 0                ; read access for source buffer
0x00005BC0       BL user_buffer_valid_range ;Validate user buffer and length for this chunk
0x00005BC8       POP R8
0x00005BCC       POP R9
0x00005BD0       POP R6
0x00005BD4       POP R7
0x00005BD8       CMP R1 1
0x00005BDC       BNE driver_bad_pointer

0x00005BE4       PUSH R7
0x00005BE8       PUSH R6
    ;=================================================
    ; access curr task fields to get task kbuffer_wr (to avoid nasty shared buffer things)
    ;=================================================
; macro: GET_CURR_TASK_IDX R4
0x00005BEC   LI R1 CURRENT_TASK
0x00005BF4   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005BF8   LI R1 TASK_SIZE
0x00005C00   MUL R3 R4 R1
0x00005C04   LI R5 tasks
0x00005C0C   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R4, R5
0x00005C10   LDW R4 [R5 + TASK_KBUF_WR_PTR]
0x00005C14       MOV R1 R7
0x00005C18       BL copy_from_user      ; copy chunk to tasks kbuffer_wr
0x00005C20       MOV R10 R1             ; bytes copied
0x00005C24       POP R6
0x00005C28       POP R7

0x00005C2C       PUSH R7
0x00005C30       PUSH R9
0x00005C34       PUSH R6

; now actual send to uart chunk from  kbuffer_wr to device
write_wait_uart_tx:
0x00005C38       LDW R1 [R9 + UARTDEV_MMIO]
0x00005C3C       LDW R2 [R1 + 4]
0x00005C40       AND R2 R2 2                     ;check bit 1 - UART_TX rdy
0x00005C44       CMP R2 0
0x00005C48       BEQ write_block_uart_tx         ;not rdy go and block this task

; can TX to UART!

; macro: GET_CURR_TASK_IDX R4
0x00005C50   LI R1 CURRENT_TASK
0x00005C58   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00005C5C   LI R1 TASK_SIZE
0x00005C64   MUL R3 R4 R1
0x00005C68   LI R5 tasks
0x00005C70   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00005C74   LDW R1 [R5 + TASK_KBUF_WR_PTR]
0x00005C78       MOV R2 R10
0x00005C7C       MOV R3 R9
    ;============================================================================
    ; get R1 - kbuff_wr ptr R2 = R10 amounts to be sent (shunk/small_chunk size)
    ; R9 - ptr to Private (con_device)
    ; r1 - outputs number of written bytes to device
    ;-----------------------------------------------------------------------------

0x00005C80       BL device_write
0x00005C88       POP R6
0x00005C8C       POP R9
0x00005C90       POP R7

0x00005C94       CMP R1 0        ;nothing is written - go again
0x00005C98       BEQ write_loop

0x00005CA0       ADD R8 R8 R1     ;update ptrs
0x00005CA4       ADD R7 R7 R1     ;R7 pointer in user buffer R8-who knows?
0x00005CA8       SUB R6 R6 R1     ;decrease amounts for next chunk to send
0x00005CAC       B write_loop     ;chunk is sent go to next one

write_block_uart_tx:
    ; Queue the task on UART TX before the re-check. If TX becomes ready
    ; immediately after this, cancel the queued sleep without scheduling.
0x00005CB4       LI R1 uart_tx_waitq
0x00005CBC       LI R2 WAIT_UART_TX
0x00005CC4       BL waitq_prepare_sleep

0x00005CCC       LDW R1 [R9 + UARTDEV_MMIO]
0x00005CD0       LDW R2 [R1 + 4]             ; re-check after marking blocked
0x00005CD4       AND R2 R2 2
0x00005CD8       CMP R2 0
0x00005CDC       BNE write_unblock_uart_tx   ; if suddenly TX ready - unblock it
                                ; its like to check if we have zero bytes to send at the begining
                                ; putting on frezze task costs time and effort so we dont need to do it if tx is rdy!!!

0x00005CE4       BL waitq_sleep_current      ; if task is blocked it sleeps here inside syscall line waiting for irq UART handler ublocks it
                                ; (when TX rdy)
                                ; also this call saves task in trapframe and jumps to schedule and switch other tasks
0x00005CEC       B write_wait_uart_tx        ; task awakes here - jumps send uart again!!

write_unblock_uart_tx:
0x00005CF4       LI R1 uart_tx_waitq
0x00005CFC       BL waitq_cancel_sleep_current

0x00005D04       B write_wait_uart_tx

write_done:
0x00005D0C       MOV R1 R8
0x00005D10       POP LR
0x00005D14       RET

driver_bad_pointer:
0x00005D18       LI R1 ERR_FAULT
0x00005D20       POP LR
0x00005D24       RET

bad_fd:
0x00005D28       LI R1 ERR_BADF
0x00005D30       STW R1 [SP + TF_R1]

0x00005D34       B trap_restore

bad_pointer:
0x00005D3C       LI R1 ERR_FAULT
0x00005D44       STW R1 [SP + TF_R1]

0x00005D48       B trap_restore

file_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================
0x00005D50       LDW R4 [R1 + FILE_INODE]
0x00005D54       LDW R4 [R4 + INODE_OPS]
0x00005D58       LDW R4 [R4 + FSOPS_READ]
0x00005D5C       JR R4

   ; LDW R4 [R1 + FILE_OPS]
   ; LDW R4 [R4 + FOPS_READ]     ; get read function xdev_read from ops
   ; JR R4                       ; execute it

file_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ;================================================================

0x00005D60       LDW R4 [R1 + FILE_INODE]
0x00005D64       LDW R4 [R4 + INODE_OPS]
0x00005D68       LDW R4 [R4 + FSOPS_WRITE]    ; get write function xdev_write from ops
0x00005D6C       JR R4                       ; execute it

device_read:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00005D70       B uart_read_kernel

device_write:
    ;================================================================
    ; R1 = kernel buffer, R2 = len, R3 = uart device pointer
    ;================================================================

0x00005D78       B uart_write_kernel

;================================================================
; read /dev/console - from MMIO UART, consuming currently available RX bytes
;================================================================

uart_read_kernel:
    ; R1 = kernel buffer, R2 = len, R3 = device object pointer
    ; Reads up to R2 bytes from the UART into kernel buffer at R1.
    ; Returns when the UART RX FIFO is empty, without spinning.
    ; Stops early when CR or LF is received.
0x00005D80       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00005D84       LI R5 0                     ; index = 0 (bytes read so far)

dr_loop:
0x00005D8C       CMP R5 R2                   ; have we read enough bytes?
0x00005D90       BGE dr_done                 ; yes -> return

dr_poll_ready:
0x00005D98       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00005D9C       AND R6 R6 1                 ; bit 0 = RX_READY
0x00005DA0       CMP R6 0
0x00005DA4       BEQ dr_done                 ; no more buffered input available

0x00005DAC       LDW R7 [R4 + 0]             ; pop character from UART_DATA (RX FIFO)
0x00005DB0       STB R7 [R1 + R5]            ; store it into the kernel buffer
0x00005DB4       ADD R5 R5 1

    ; If we received a line terminator, stop reading early.
0x00005DB8       CMP R7 10
0x00005DBC       BEQ dr_done
0x00005DC4       CMP R7 13
0x00005DC8       BEQ dr_done

0x00005DD0       B dr_loop

dr_done:
0x00005DD8       MOV R1 R5                   ; return number of bytes actually read
0x00005DDC       RET

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
0x00005DE0       PUSH LR

    ; mutex for write to console lock
0x00005DE4       PUSH R1
0x00005DE8       PUSH R2
0x00005DEC       PUSH R3

    ; Lock console mutex
0x00005DF0       BL console_lock

    ; Write to UART
0x00005DF8       POP R3
0x00005DFC       POP R2
0x00005E00       POP R1


0x00005E04       LDW R4 [R3 + UARTDEV_MMIO]  ; UART MMIO Base Address
0x00005E08       LI R5 0                     ; index = 0 (bytes written so far)

dcw_loop:
0x00005E10       CMP R5 R2                   ; have we written all bytes?
0x00005E14       BGE dcw_done                ; yes -> return

dcw_poll_tx:
0x00005E1C       LDW R6 [R4 + 4]             ; read UART_STATUS register
0x00005E20       AND R6 R6 2                 ; bit 1 = TX_READY
0x00005E24       CMP R6 0
0x00005E28       BEQ dcw_done

0x00005E30       LDB R7 [R1 + R5]            ; load next byte from kernel buffer
0x00005E34       STW R7 [R4 + 0]             ; write to UART_DATA register (transmit)
0x00005E38       ADD R5 R5 1
0x00005E3C       B dcw_loop

dcw_done:
0x00005E44       MOV R1 R5                   ; return number of bytes written


 ; Unlock console mutex for exclusive write to uart device
0x00005E48       PUSH R1
0x00005E4C       BL console_unlock
0x00005E54       POP R1


0x00005E58       POP LR
0x00005E5C       RET

null_read:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null always returns EOF without touching the destination.
    ;================================================================

0x00005E60       LI R1 0
0x00005E68       RET

null_write:
    ;================================================================
    ; R1 = file ptr, R2 = user buffer, R3 = len
    ; /dev/null discards valid input and reports all bytes written.
    ;================================================================

0x00005E6C       PUSH LR
0x00005E70       MOV R6 R3
0x00005E74       CMP R6 0
0x00005E78       BEQ null_write_done

0x00005E80       PUSH R6
0x00005E84       MOV R1 R2
0x00005E88       MOV R2 R6
0x00005E8C       LI R3 0                    ; read access from user source
0x00005E94       BL user_buffer_valid_range
0x00005E9C       POP R6
0x00005EA0       CMP R1 1
0x00005EA4       BNE null_write_badptr

null_write_done:
0x00005EAC       MOV R1 R6
0x00005EB0       POP LR
0x00005EB4       RET

null_write_badptr:
0x00005EB8       LI R1 ERR_FAULT
0x00005EC0       POP LR
0x00005EC4       RET

fetch_fd_entry:
    ;================================================================
    ; R1 = fd, R2 = func check mode for read or write access
    ; Returns device object pointer in R1 if valid, or 0 if invalid.
    ; Validity checks:
    ; - fd must be in range [0, MAX_FDS)
    ; - fd table entry must have at least the required flags set
    ;
    ;================================================================
0x00005EC8       PUSH R5
0x00005ECC       PUSH R6
0x00005ED0       PUSH R8

0x00005ED4       CMP R1 0
0x00005ED8       BLT fd_invalid
0x00005EE0       CMP R1 MAX_FDS
0x00005EE4       BGE fd_invalid

0x00005EEC       MOV R8 R1                   ; preserve fd across task lookup macros
; macro: GET_CURR_TASK_IDX R4
0x00005EF0   LI R1 CURRENT_TASK
0x00005EF8   LDW R4 [R1]
; macro: GET_TASK_PTR R4, R4
0x00005EFC   LI R1 TASK_SIZE
0x00005F04   MUL R3 R4 R1
0x00005F08   LI R4 tasks
0x00005F10   ADD R4 R4 R3
; macro: TASK_GET_FD_TABLE R4, R4
0x00005F14   LDW R4 [R4 + TASK_FD_TABLE]

0x00005F18       SHL R5 R8 2
0x00005F1C       ADD R4 R4 R5                ; r4=fd*4+FD_TABLE
0x00005F20       LDW R1 [R4]                 ; R1 = file ptr
0x00005F24       LDW R6 [R1 + FILE_FLAGS]
0x00005F28       AND R6 R6 O_ACCMODE
    ;check func mode for Read/Write access
0x00005F2C       CMP R2 FD_FLAG_READ
0x00005F30       BEQ fd_readaccess
0x00005F38       CMP R2 FD_FLAG_WRITE
0x00005F3C       BEQ fd_writeaccess

0x00005F44       B fd_invalid
fd_writeaccess:
0x00005F4C       CMP R6 O_RDONLY
0x00005F50       BEQ fd_invalid
0x00005F58       B  fd_all_good
fd_readaccess:
0x00005F60       CMP R6 O_WRONLY
0x00005F64       BEQ fd_invalid

fd_all_good:
0x00005F6C       POP R8
0x00005F70       POP R6
0x00005F74       POP R5
0x00005F78       RET                         ;on exit R1 - has file ptr

fd_invalid:
0x00005F7C       POP R8
0x00005F80       POP R6
0x00005F84       POP R5

0x00005F88       LI R1 0
0x00005F90       RET


;================================================================
; vfs_read: - vfs wrapper read func reads from file/inode - independent from h/w
; R1 = fd, R2 = user buffer, R3 = length
; out: R1 = bytes read or errno
;================================================================
vfs_read:

0x00005F94       PUSH LR
0x00005F98       MOV R7 R2
0x00005F9C       MOV R10 R3

0x00005FA0       LI R2 FD_FLAG_READ  ; func to validate FD reader access
0x00005FA8       BL fetch_fd_entry   ; validate FD and access mode

0x00005FB0       CMP R1 0
0x00005FB4       BEQ vfs_read_badfd

0x00005FBC       MOV R9 R1
0x00005FC0       MOV R1 R9
0x00005FC4       MOV R2 R7
0x00005FC8       MOV R3 R10
0x00005FCC       BL file_read
0x00005FD4       POP LR
0x00005FD8       RET

vfs_read_badfd:
0x00005FDC       LI R1 ERR_BADF
0x00005FE4       POP LR
0x00005FE8       RET

vfs_write:
    ;================================================================
    ; R1 = fd, R2 = user buffer, R3 = length
    ; out: R1 = bytes written or errno
    ;================================================================

0x00005FEC       PUSH LR
0x00005FF0       MOV R7 R2
0x00005FF4       MOV R10 R3

0x00005FF8       LI R2 FD_FLAG_WRITE ;func to validate FD writer access
0x00006000       BL fetch_fd_entry   ;validate FD and access mode

0x00006008       CMP R1 0
0x0000600C       BEQ vfs_write_badfd

0x00006014       MOV R9 R1
0x00006018       MOV R1 R9           ; R1 - file* acc to fd
0x0000601C       MOV R2 R7
0x00006020       MOV R3 R10
0x00006024       BL file_write
0x0000602C       POP LR
0x00006030       RET

vfs_write_badfd:
0x00006034       LI R1 ERR_BADF
0x0000603C       POP LR
0x00006040       RET






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
0x00006044       PUSH R5
0x00006048       PUSH R6
0x0000604C       PUSH R7
0x00006050       PUSH R8
0x00006054       PUSH R9
0x00006058       PUSH R10
0x0000605C       PUSH R11
0x00006060       PUSH R12

0x00006064       LI R4 0
0x0000606C       CMP R2 R4
0x00006070       BEQ uv_valid

0x00006078       LI R4 USER_BASE
0x00006080       CMP R1 R4
0x00006084       BLT uv_invalid

0x0000608C       LI R4 USER_LIMIT
0x00006094       ADD R5 R1 R2
0x00006098       SUB R5 R5 1
0x0000609C       CMP R5 R1
0x000060A0       BLT uv_invalid
0x000060A8       CMP R5 R4
0x000060AC       BGT uv_invalid
0x000060B4       MOV R11 R1              ; save start address; task macros clobber R1
0x000060B8       MOV R12 R5              ; save end address for page calculation
0x000060BC       MOV R4 R3               ; save access type; task macros clobber R3

; macro: GET_CURR_TASK_IDX R6
0x000060C0   LI R1 CURRENT_TASK
0x000060C8   LDW R6 [R1]
; macro: GET_TASK_PTR R6, R6
0x000060CC   LI R1 TASK_SIZE
0x000060D4   MUL R3 R6 R1
0x000060D8   LI R6 tasks
0x000060E0   ADD R6 R6 R3
; macro: TASK_GET_PTBR R6, R6
0x000060E4   LDW R6 [R6 + TASK_PTBR]
    ; Dynamic page tables live in the supervisor-only allocator pool,
    ; which is identity-mapped into every task address space.
0x000060E8       CMP R6 0
0x000060EC       BEQ uv_invalid

uv_check_pages:
0x000060F4       SHR R7 R11 12
0x000060F8       SHR R8 R12 12
uv_loop:
    ;================================================================
    ; For each page spanned by the buffer, check the corresponding PTE in the page table:
    ; - must be present (P) and user-accessible (U)
    ; - if access type is write, must also have the writable (W) bit set
    ;================================================================

0x000060FC       CMP R7 R8
0x00006100       BGT uv_valid
0x00006108       SHL R9 R7 2
0x0000610C       ADD R9 R9 R6
0x00006110       LDW R10 [R9]
0x00006114       AND R5 R10 PTE_P
0x00006118       CMP R5 0
0x0000611C       BEQ uv_invalid
0x00006124       AND R5 R10 PTE_U
0x00006128       CMP R5 0
0x0000612C       BEQ uv_invalid
0x00006134       CMP R4 0
0x00006138       BEQ uv_check_read
0x00006140       AND R5 R10 PTE_W
0x00006144       CMP R5 0
0x00006148       BEQ uv_invalid
0x00006150       B uv_next

uv_check_read:
0x00006158       AND R5 R10 PTE_R
0x0000615C       CMP R5 0
0x00006160       BEQ uv_invalid

uv_next:
0x00006168       ADD R7 R7 1
0x0000616C       B uv_loop

uv_valid:
0x00006174       LI R1 1
0x0000617C       POP R12
0x00006180       POP R11
0x00006184       POP R10
0x00006188       POP R9
0x0000618C       POP R8
0x00006190       POP R7
0x00006194       POP R6
0x00006198       POP R5
0x0000619C       RET

uv_invalid:
0x000061A0       LI R1 0

0x000061A8       POP R12
0x000061AC       POP R11
0x000061B0       POP R10
0x000061B4       POP R9
0x000061B8       POP R8
0x000061BC       POP R7
0x000061C0       POP R6
0x000061C4       POP R5
0x000061C8       RET

copy_from_user:
    ;================================================================
    ; R1 = src user, R2 = len, R4 = dest kernel
    ; Copies data from user buffer at R1 to kernel buffer at R4, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x000061CC       PUSH R5
0x000061D0       PUSH R6
0x000061D4       PUSH R7
0x000061D8       LI R5 0
cfu_head:
0x000061E0       CMP R2 0
0x000061E4       BEQ cfu_done
0x000061EC       OR R6 R1 R4
0x000061F0       AND R6 R6 3
0x000061F4       CMP R6 0
0x000061F8       BEQ cfu_word
0x00006200       LDB R7 [R1]
0x00006204       STB R7 [R4]
0x00006208       ADD R1 R1 1
0x0000620C       ADD R4 R4 1
0x00006210       ADD R5 R5 1
0x00006214       SUB R2 R2 1
0x00006218       B cfu_head
cfu_word:
0x00006220       CMP R2 4
0x00006224       BLT cfu_tail
0x0000622C       LDW R7 [R1]
0x00006230       STW R7 [R4]
0x00006234       ADD R1 R1 4
0x00006238       ADD R4 R4 4
0x0000623C       ADD R5 R5 4
0x00006240       SUB R2 R2 4
0x00006244       B cfu_word
cfu_tail:
0x0000624C       CMP R2 0
0x00006250       BEQ cfu_done
0x00006258       LDB R7 [R1]
0x0000625C       STB R7 [R4]
0x00006260       ADD R1 R1 1
0x00006264       ADD R4 R4 1
0x00006268       ADD R5 R5 1
0x0000626C       SUB R2 R2 1
0x00006270       B cfu_tail
cfu_done:
0x00006278       MOV R1 R5
0x0000627C       POP R7
0x00006280       POP R6
0x00006284       POP R5
0x00006288       RET

copy_to_user:
    ;================================================================
    ; R1 = dest user, R2 = len, R4 = src kernel
    ; Copies data from kernel buffer at R4 to user buffer at R1, for R2 bytes.
    ; This is a simple byte-by-byte copy that handles unaligned addresses.
    ; Returns the number of bytes copied in R1.
    ;================================================================

   ; DEBUG 2
0x0000628C       PUSH R5
0x00006290       PUSH R6
0x00006294       PUSH R7
0x00006298       LI R5 0
ctu_head:
0x000062A0       CMP R2 0
0x000062A4       BEQ ctu_done
0x000062AC       OR R6 R1 R4
0x000062B0       AND R6 R6 3
0x000062B4       CMP R6 0
0x000062B8       BEQ ctu_word
0x000062C0       LDB R7 [R4]
0x000062C4       STB R7 [R1]
0x000062C8       ADD R1 R1 1
0x000062CC       ADD R4 R4 1
0x000062D0       ADD R5 R5 1
0x000062D4       SUB R2 R2 1
0x000062D8       B ctu_head
ctu_word:
0x000062E0       CMP R2 4
0x000062E4       BLT ctu_tail
0x000062EC       LDW R7 [R4]
0x000062F0       STW R7 [R1]
0x000062F4       ADD R1 R1 4
0x000062F8       ADD R4 R4 4
0x000062FC       ADD R5 R5 4
0x00006300       SUB R2 R2 4
0x00006304       B ctu_word
ctu_tail:
0x0000630C       CMP R2 0
0x00006310       BEQ ctu_done
0x00006318       LDB R7 [R4]
0x0000631C       STB R7 [R1]
0x00006320       ADD R1 R1 1
0x00006324       ADD R4 R4 1
0x00006328       ADD R5 R5 1
0x0000632C       SUB R2 R2 1
0x00006330       B ctu_tail
ctu_done:
0x00006338       MOV R1 R5
0x0000633C       POP R7
0x00006340       POP R6
0x00006344       POP R5
0x00006348       RET

handle_debug:
    ; Debug trap - just return
0x0000634C       B trap_restore

handle_irq:
    ;================================================================
    ; Read the pending IRQ vector from STVAL
    ; and dispatch based on the IRQ number. For this platform:
    ; - IRQ 0 = Timer/PIT
    ; - IRQ 1 = UART RX
    ;================================================================

0x00006354       CSRR R1 STVAL

0x00006358       CMP R1 0
0x0000635C       BEQ handle_timer_irq

0x00006364       CMP R1 1
0x00006368       BEQ handle_uart_irq
    ;================================================================
    ; Default IRQ handling: acknowledge PIC and restore
    ;================================================================
0x00006370       LI R2 0x00102000
0x00006378       STW R1 [R2 + 8]             ; PIC_ACK = R1
0x0000637C       B trap_restore

handle_timer_irq:

    ;================================================================
    ; Acknowledge IRQ 0 (Timer) in PIC MMIO
    ;================================================================

0x00006384       LI R2 0x00102000
0x0000638C       LI R3 0
0x00006394       STW R3 [R2 + 8]             ; PIC_ACK = 0

    ; Increment timer tick counter
0x00006398       LI R1 timer_ticks
0x000063A0       LDW R2 [R1]
0x000063A4       ADD R2 R2 1
0x000063A8       STW R2 [R1]

    ;================================================================
    ; Wake sleeping tasks whose time has expired
    ;================================================================

0x000063AC       LI R1 sleep_waitq
0x000063B4       LDW R8 [R1]                ; R8 = current sleep_waitq mask
0x000063B8       LI R9 0                    ; R9 = tasks to wake bitmask
0x000063C0       LI R3 0                    ; task index

timer_wake_scan:
0x000063C8       CMP R3 MAX_TASKS
0x000063CC       BGE timer_wake_scan_done

    ; Check if this task is in the sleep wait queue
0x000063D4       LI R6 1
0x000063DC       SHL R6 R6 R3               ; bit for this task
0x000063E0       AND R7 R8 R6
0x000063E4       CMP R7 0
0x000063E8       BEQ timer_wake_next        ; not in sleep queue

    ; Task is sleeping, check if it's time to wake
; macro: GET_TASK_PTR R5, R3
0x000063F0   LI R1 TASK_SIZE
0x000063F8   MUL R3 R3 R1
0x000063FC   LI R5 tasks
0x00006404   ADD R5 R5 R3
; macro: TASK_GET_WAKE_TIME R7, R5
0x00006408   LDW R7 [R5 + TASK_WAKE_TIME]
0x0000640C       CMP R2 R7                  ; current time >= wake time?
0x00006410       BLT timer_wake_next

    ; Mark this task for wakeup
0x00006418       OR R9 R9 R6                 ; add to wake bitmask bitwize

timer_wake_next:
0x0000641C       ADD R3 R3 1
0x00006420       B timer_wake_scan

timer_wake_scan_done:
    ; If no tasks to wake, skip
0x00006428       CMP R9 0
0x0000642C       BEQ timer_no_wake

    ; Wake the expired tasks using our new function
0x00006434       LI R1 sleep_waitq
0x0000643C       MOV R2 R9
0x00006440       BL waitq_wake_bitmask

timer_no_wake:

    ; Yield the CPU (reschedule and switch tasks)
0x00006448       B schedule_and_switch

handle_uart_irq:
    ;================================================================
    ; Acknowledge IRQ 1, then wake tasks blocked on UART RX/TX queues.
    ; The wait queues contain exactly the tasks that blocked on this
    ; device condition, so the IRQ path no longer scans every task and
    ; decodes TASK_WAIT reasons by hand.
    ;================================================================

0x00006450       LI R2 0x00102000
0x00006458       LI R3 1
0x00006460       STW R3 [R2 + 8]             ; PIC_ACK = 1

    ; Current UART interrupt source is coarse, so wake both sides.
    ; The resumed syscall loops re-check hardware status before doing I/O.
0x00006464       LI R1 uart_rx_waitq
0x0000646C       BL waitq_wake_all
0x00006474       LI R1 uart_tx_waitq
0x0000647C       BL waitq_wake_all

uart_wake_done:
    ; Resume the interrupted task immediately
0x00006484       B trap_restore

trap_restore:
    ;================================================================
    ; this does a resume of task restores state frame
    ; and makes SRET - machine runs the task
    ; note SP should point to task's kernel trapframe!
    ; Restore privileged state saved after the GPRs.
    ;================================================================

0x0000648C       POP R1                  ; stval, informational only
0x00006490       POP R1                  ; scause, informational only
0x00006494       POP R1
0x00006498       CSRW SSTATUS R1
0x0000649C       POP R1
0x000064A0       CSRW SFLAGS R1
0x000064A4       POP R1
0x000064A8       CSRW SEPC R1
0x000064AC       POP R1                  ; interrupted task SP
0x000064B0       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH

    ; Restore interrupted GPR state in reverse order.
0x000064B4       POP R15
0x000064B8       POP R14
0x000064BC       POP R12
0x000064C0       POP R11
0x000064C4       POP R10
0x000064C8       POP R9
0x000064CC       POP R8
0x000064D0       POP R7
0x000064D4       POP R6
0x000064D8       POP R5
0x000064DC       POP R4
0x000064E0       POP R3
0x000064E4       POP R2
0x000064E8       POP R1
    ;================================================================
    ; Switch back from kernel stack to interrupted task stack.
    ; Before: SP=kernel stack top, SSCRATCH=task SP.
    ; After:  SP=task SP, SSCRATCH=kernel stack top for next trap.
    ;================================================================

0x000064EC       CSRRW SP SSCRATCH SP
0x000064F0       SRET


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
.EQU SYS_COUNT,     19      ; update count


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

;=================================================================
; NSFS private vnode stored behind inode->private.
; Later this can hold a cached path key, namespace id, host handle,
; materialized size/type, dirty flags, and page-cache pointer.
.EQU NSFS_NODE_NAMESPACE, 0
.EQU NSFS_NODE_PATH,      4
.EQU NSFS_NODE_TYPE,      8
.EQU NSFS_NODE_SIZE,     12
.EQU NSFS_NODE_FLAGS,    16
.EQU NSFS_NODE_SIZEOF,   20
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
.EQU NSFS_WIRE_TYPE,      0
.EQU NSFS_WIRE_SIZE,      4
.EQU NSFS_WIRE_VERSION,   8
.EQU NSFS_WIRE_PATH_LEN, 12
.EQU NSFS_WIRE_HDR_SIZEOF, 16

;=========================================================================
; NSFS index table item structure
;=========================================================================
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


;=========================================================================
; nsfs index table and path pool for index entries.
;=========================================================================
nsfs_index_count:
    .WORD 0

nsfs_index_table:
    .SPACE NSFS_INDEX_MAX_ENTRIES * NSFS_INDEX_ENTRY_SIZEOF

nsfs_index_path_next:
    .WORD 0
; blob of paths for index entries,
; ptr is in NSFS_INDEX_PATH
; each path is a null-terminated string
nsfs_index_path_pool:
    .SPACE NSFS_INDEX_PATH_POOL_SIZE

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
   ; ADD R8 R8 1           ; correction we dont skip leading / all paths for tarfs start from /...

lookup_path_ready:

0x00008F85       LI R9 0                ; index

0x00008F8D       LI R10 tar_count
0x00008F95       LDW R10 [R10]

tar_lookup_loop:

0x00008F99       CMP R9 R10
0x00008F9D       BGE tar_lookup_not_found

    ; entry address

0x00008FA5       LI R1 tar_index

0x00008FAD       LI R2 TAR_IDX_SIZEOF
0x00008FB5       MUL R3 R9 R2
0x00008FB9       ADD R1 R1 R3            ;

    ; compare names

0x00008FBD       MOV R2 R8

0x00008FC1       LDW R1 [R1 + TAR_IDX_NAME]

0x00008FC5       BL strcmp   ;R1 is tar name, R2 is pathname, returns 1 if match

0x00008FCD       CMP R1 1
0x00008FD1       BEQ tar_lookup_found

0x00008FD9       ADD R9 R9 1
0x00008FDD       B tar_lookup_loop

tar_lookup_found:

0x00008FE5       LI R1 tar_index
0x00008FED       LI R2 TAR_IDX_SIZEOF
0x00008FF5       MUL R3 R9 R2
0x00008FF9       ADD R11 R1 R3        ; R11 = &tar_index[R9]

    ;alloc node for this file

0x00008FFD       BL inode_alloc
0x00009005       CMP R1 0
0x00009009       BEQ tar_lookup_not_found
0x00009011       MOV R10 R1              ; r10 = new inode ptr

    ; init this node with data from &tar_index[R9]

0x00009015       MOV R1 R10              ; inode
0x00009019       LI  R2 tarfs_ops        ; ops table
0x00009021       MOV R3 R11              ; private = tar entry

0x00009025       LDW R4 [R11 + TAR_IDX_TYPE] ; FILE type
0x00009029       LDW R5 [R11 + TAR_IDX_SIZE] ; file size
0x0000902D       BL inode_init

0x00009035       MOV R1 R10              ;R1 = new node ptr inited for file found in lookup

0x00009039       POP R10
0x0000903D       POP R9
0x00009041       POP R8
0x00009045       POP LR
0x00009049       RET

tar_lookup_not_found:

0x0000904D       LI R1 0             ; R1 = NULL

0x00009055       POP R10
0x00009059       POP R9
0x0000905D       POP R8
0x00009061       POP LR
0x00009065       RET


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

0x00009069       PUSH LR
0x0000906D       PUSH R8
0x00009071       PUSH R9
0x00009075       PUSH R10
0x00009079       PUSH R11
0x0000907D       PUSH R12

0x00009081       MOV R8 R1                  ; current tar header
0x00009085       LI R11 tar_limit
0x0000908D       ADD R2 R1 R2
0x00009091       STW R2 [R11]               ; exclusive end of archive
0x00009095       LI R9 tar_index            ; current index entry
0x0000909D       LI R10 0                   ; file count

tar_scan_loop:
0x000090A5       CMP R10 MAX_TAR_FILES
0x000090A9       BGE tar_done                ; check before writing the next index entry

0x000090B1       LI R11 tar_limit
0x000090B9       LDW R11 [R11]
0x000090BD       LI R12 TAR_HEADER_SIZE
0x000090C5       ADD R12 R8 R12
0x000090C9       CMP R12 R11
0x000090CD       BGTU tar_done               ; truncated/corrupt header

    ; ------------------------------------
    ; end of archive?
    ; ------------------------------------

0x000090D5       LDB R11 [R8 + TAR_NAME_OFF]
0x000090D9       CMP R11 0                   ; if name[0] == 0, this is the end of the archive
                                ; (two consecutive zero 512-byte blocks)
0x000090DD       BEQ tar_done

    ; ------------------------------------
    ; name pointer
    ; ------------------------------------

0x000090E5       MOV R11 R8
0x000090E9       ADD R11 R11 TAR_NAME_OFF
0x000090ED       STW R11 [R9 + TAR_IDX_NAME]

    ; ------------------------------------
    ; size
    ; ------------------------------------

0x000090F1       MOV R1 R8
0x000090F5       ADD R1 R1 TAR_SIZE_OFF
    ;R1 = ptr to TAR size field
0x000090F9       BL tar_parse_octal         ; parse octal size from tar header field to binary integer
0x00009101       MOV R12 R1                 ; save file resulted binary size
0x00009105       STW R12 [R9 + TAR_IDX_SIZE]

    ; ------------------------------------
    ; data pointer
    ; ------------------------------------

0x00009109       MOV R11 R8
0x0000910D       LI R2 TAR_HEADER_SIZE
0x00009115       ADD R11 R11 R2
0x00009119       STW R11 [R9 + TAR_IDX_DATA]

    ; ------------------------------------
    ; type - file or directory 0 for file, 5 for directory
    ; ------------------------------------

0x0000911D       LI R2 TAR_TYPE_OFF
0x00009125       ADD R2 R8 R2
0x00009129       LDB R11 [R2]
0x0000912D       STW R11 [R9 + TAR_IDX_TYPE]

    ; ------------------------------------
    ; next index entry
    ; ------------------------------------

0x00009131       ADD R10 R10 1               ; othewise go to next file count
0x00009135       ADD R9 R9 TAR_IDX_SIZEOF

    ; ------------------------------------
    ; advance to next tar header
    ; ------------------------------------
0x00009139       MOV R11 R12
    ; round up to 512 boundary

0x0000913D       LI R2 511
0x00009145       ADD R11 R11 R2
0x00009149       SHR R11 R11 9
0x0000914D       SHL R11 R11 9           ; R11 = size rounded up to next 512 multiple

0x00009151       LI R2 TAR_HEADER_SIZE
0x00009159       ADD R8 R8 R2
0x0000915D       ADD R8 R8 R11           ; advance to next tar header
0x00009161       LI R12 tar_limit
0x00009169       LDW R12 [R12]
0x0000916D       CMP R8 R12
0x00009171       BGTU tar_done            ; file data/padding extends beyond archive
0x00009179       B tar_scan_loop

tar_done:

0x00009181       LI R11 tar_count        ; store total file count for this tar archive in global variable
0x00009189       STW R10 [R11]

0x0000918D       POP R12
0x00009191       POP R11
0x00009195       POP R10
0x00009199       POP R9
0x0000919D       POP R8
0x000091A1       POP LR

0x000091A5       RET

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

0x000091A9       PUSH R2
0x000091AD       PUSH R3
0x000091B1       PUSH R4
0x000091B5       LI   R2 0                  ; result
octal_loop:
0x000091BD       LDB  R3 [R1]
    ; end of field?
    ;
    ; ASCII NUL = 0
    ; ASCII SPACE = 32
0x000091C1       CMP  R3 0
0x000091C5       BEQ  octal_done
0x000091CD       LI   R4 32                 ; ' '
0x000091D5       CMP  R3 R4
0x000091D9       BEQ  octal_done

    ; digit = ascii - '0'
    ;
    ; ASCII '0' = 48

0x000091E1       LI   R4 48
0x000091E9       SUB  R3 R3 R4

    ; result = result * 8 + digit

0x000091ED       SHL  R2 R2 3               ; multiply by 8
0x000091F1       ADD  R2 R2 R3              ; add digit
0x000091F5       ADD  R1 R1 1               ; advance to next octal character
0x000091F9       B    octal_loop
octal_done:
0x00009201       MOV  R1 R2                 ; return binary result in R1

0x00009205       POP  R4
0x00009209       POP  R3
0x0000920D       POP  R2
0x00009211       RET

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

0x0000922C       PUSH LR
0x00009230       PUSH R8
0x00009234       PUSH R9
0x00009238       PUSH R10
0x0000923C       LI R8 0
0x00009244       LI R10 tar_count
0x0000924C       LDW R10 [R10]

0x00009250       LI R1 tarfs_banner
0x00009258       BL kputs
dump_loop:
0x00009260       CMP R8 R10
0x00009264       BGE dump_done
    ; entry = tar_index + i*sizeof(entry)
0x0000926C       LI R1 tar_index
0x00009274       LI R2 TAR_IDX_SIZEOF
0x0000927C       MUL R3 R8 R2
0x00009280       ADD R9 R1 R3
    ; filename
0x00009284       LDW R2 [R9 + TAR_IDX_NAME]
    ; print string somehow
0x00009288       MOV R1 R2
0x0000928C       BL kputs
    ; newline
0x00009294       LI R1 newline
0x0000929C       BL kputs
0x000092A4       ADD R8 R8 1
0x000092A8       B dump_loop
dump_done:
0x000092B0       POP R10
0x000092B4       POP R9
0x000092B8       POP R8
0x000092BC       POP LR
0x000092C0       RET

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

0x000092C4       PUSH LR
0x000092C8       PUSH R8
0x000092CC       PUSH R9
0x000092D0       PUSH R10
0x000092D4       PUSH R11
0x000092D8       PUSH R12

0x000092DC       MOV R8 R1
0x000092E0       MOV R9 R2
0x000092E4       MOV R10 R3

0x000092E8       CMP R10 0
0x000092EC       BEQ tarfs_read_eof

0x000092F4       PUSH R8
0x000092F8       PUSH R9
0x000092FC       MOV R1 R9
0x00009300       MOV R2 R10
0x00009304       LI R3 1                    ; destination must be user-writable
0x0000930C       BL user_buffer_valid_range
0x00009314       POP R9
0x00009318       POP R8
0x0000931C       CMP R1 1
0x00009320       BNE tarfs_read_fault

0x00009328       LDW R11 [R8 + FILE_INODE]
0x0000932C       LDW R5  [R11 + INODE_TYPE]
0x00009330       LDW R11 [R11 + INODE_PRIVATE]
     ; ---- check if this is a directory ----
0x00009334       LI  R2 INODE_DIR
0x0000933C       CMP R5 R2
    ; CMP R5 INODE_DIR - this will result inerror as command will be assembled in decimal number
0x00009340       BEQ tarfs_read_dir

0x00009348       LDW R12 [R8 + FILE_OFFSET]
0x0000934C       LDW R4  [R11 + TAR_IDX_SIZE]

0x00009350       CMP R12 R4
0x00009354       BGEU tarfs_read_eof

0x0000935C       SUB R4 R4 R12             ; bytes remaining
0x00009360       CMP R10 R4
0x00009364       BLEU tarfs_read_count_ready
0x0000936C       MOV R10 R4

tarfs_read_count_ready:
0x00009370       LDW R4 [R11 + TAR_IDX_DATA]
0x00009374       ADD R4 R4 R12             ; kernel source
0x00009378       MOV R1 R9                 ; user destination
0x0000937C       MOV R2 R10
0x00009380       BL copy_to_user

0x00009388       ADD R12 R12 R1
0x0000938C       STW R12 [R8 + FILE_OFFSET]
0x00009390       B tarfs_read_done

tarfs_read_dir:
    ; directory read – call our dir read function
0x00009398       MOV R1 R8
0x0000939C       MOV R2 R9
0x000093A0       MOV R3 R10
0x000093A4       BL tarfs_readdir
0x000093AC       B tarfs_read_done   ; jump to the common return path

tarfs_read_fault:
0x000093B4       LI R1 ERR_FAULT
0x000093BC       B tarfs_read_done

tarfs_read_eof:
0x000093C4       LI R1 0

tarfs_read_done:
0x000093CC       POP R12
0x000093D0       POP R11
0x000093D4       POP R10
0x000093D8       POP R9
0x000093DC       POP R8
0x000093E0       POP LR
0x000093E4       RET

tarfs_write:
0x000093E8       LI R1 ERR_ACCES
0x000093F0       RET

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
0x000093F4       PUSH LR
0x000093F8       PUSH R8
0x000093FC       PUSH R9
0x00009400       PUSH R10
0x00009404       PUSH R11
0x00009408       PUSH R12

    ; ---- validate user buffer ----
0x0000940C       MOV R8 R2                 ; save user buffer + to stack
0x00009410       PUSH R8
0x00009414       MOV R9 R3                 ; save length
0x00009418       MOV R12 R1                ; save file ptr
0x0000941C       CMP R9 DIRENT_SIZEOF
0x00009420       BLT readdir_short         ; not enough space for one entry

    ;PUSH R9
0x00009428       MOV R1 R8
0x0000942C       LI  R2 DIRENT_SIZEOF
0x00009434       LI  R3 1                  ; write access
0x0000943C       BL  user_buffer_valid_range
    ;POP R9
0x00009444       CMP R1 1
0x00009448       BNE readdir_fault

    ; ---- get inode and private data ----
0x00009450       LDW R4 [R12 + FILE_INODE]    ; R4 = inode* r12 -file ptf
0x00009454       LDW R5 [R4 + INODE_PRIVATE] ; R5 = tar index entry for the directory itself
0x00009458       CMP R5 0
0x0000945C       BEQ readdir_eof

    ; get directory prefix from that tar entry (e.g., "etc/")
0x00009464       LDW R10 [R5 + TAR_IDX_NAME] ; R10 = full path of directory (with trailing /)

    ; load current entry index from file offset
0x00009468       LDW R11 [R12 + FILE_OFFSET] ; R11 = index (number of entries already returned)

    ; ---- scan tar index from this index ----
    ;LI R12 tar_count
    ;LDW R12 [R12]             ; total number of tar entries
0x0000946C       MOV R6 R11                ; current scan index

readdir_scan:
0x00009470       LI  R1 tar_count          ;total number entryes in index count
0x00009478       LDW R1 [R1]
0x0000947C       CMP R6 R1
0x00009480       BGE readdir_nsfs_start    ; no more tar entries; append overlay entries

    ; entry = tar_index + R6 * TAR_IDX_SIZEOF
0x00009488       LI R1 tar_index
0x00009490       LI R2 TAR_IDX_SIZEOF
0x00009498       MUL R3 R6 R2
0x0000949C       ADD R7 R1 R3              ; R7 = &tar_index[R6]

    ; check if this entry's name starts with the directory prefix
0x000094A0       LDW R1 [R7 + TAR_IDX_NAME]
0x000094A4       MOV R2 R10
0x000094A8       BL str_prefix            ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000094B0       CMP R1 1
0x000094B4       BNE readdir_skip

    ; skip the directory entry itself (exact match)
0x000094BC       LDW R1 [R7 + TAR_IDX_NAME]
0x000094C0       MOV R2 R10
0x000094C4       BL strcmp                ; ie skip if we read 'etc/' == etc/
0x000094CC       CMP R1 1
0x000094D0       BEQ readdir_skip

    ; ---- found a matching file/directory ----
    ; skip the prefix to get the relative component
0x000094D8       LDW R1 [R7 + TAR_IDX_NAME]
0x000094DC       MOV R2 R10
0x000094E0       BL skip_prefix            ; R1 = pointer after prefix omit prefix - just filename 'etc/bin' -> bin
0x000094E8       MOV R9 R1                 ; R9 = component name (e.g., "motd" (file) or "network/ (subdir)")

    ; compute the component length up to next '/'
0x000094EC       MOV R1 R9
0x000094F0       BL path_component_len     ; R1 = component length (L)
0x000094F8       MOV R8 R1                 ; R8 = component name length

    ; clamp to DIRENT_NAME_LEN - 1 to avoid overflow
0x000094FC       LI R2 63
0x00009504       CMP R8 R2
0x00009508       BLE readdir_name_ok
0x00009510       MOV R8 63
readdir_name_ok:
    ; save R6 cureent entry index
0x00009514       MOV R11 R6
    ;get type
0x00009518       LDW R6  [R7 + TAR_IDX_TYPE]  ;R6  R11 = tar type (0=file, 5=dir)

    ; map tar type to DT_* constants
0x0000951C       LI  R1 INODE_DIR     ;adapted 35hex yess
0x00009524       CMP R6 R1
    ;CMP R6 5            ;needs to be adapted 35hex
0x00009528       BEQ readdir_type_dir
0x00009530       LI R6 DT_REG               ; default type to regular r11 - file
0x00009538       B readdir_type_done
readdir_type_dir:
0x00009540       LI R6 DT_DIR               ; switch type R11 - dir
readdir_type_done:

    ; ---- build struct dirent in KBUF_WR ----
; macro: GET_CURR_TASK_IDX R4
0x00009548   LI R1 CURRENT_TASK
0x00009550   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x00009554   LI R1 TASK_SIZE
0x0000955C   MUL R3 R4 R1
0x00009560   LI R5 tasks
0x00009568   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x0000956C   LDW R1 [R5 + TASK_KBUF_WR_PTR]


   ; GET_CURR_TASK_IDX R2
   ; GET_TASK_PTR R2, R2
   ; TASK_GET_KBUF_WR R5, R2    ; R5 = kernel write buffer

    ; d_ino = index + 1 (dummy); R1 = kernel write buffer - form dirent stuc with read dir-entry
0x00009570       ADD R3 R11 1
0x00009574       STW R3 [R1 + DIRENT_INODE]
    ; d_type = DT_REG or DT_DIR
0x00009578       STW R6 [R1 + DIRENT_TYPE]

    ; get size from tar entry
0x0000957C       LDW R2  [R7 + TAR_IDX_SIZE]  ; R12 = file size
    ; d_size = file size
0x00009580       STW R2  [R1 + DIRENT_SIZE]

    ; ---- update file offset to next entry ----
    ;ADD R6 R6 1
0x00009584       STW R3 [R12 + FILE_OFFSET] ; store new index R11+1 for next read


    ; d_name = component name (copy up to 64 bytes)
0x00009588       MOV R2 R9                  ; source name R9 = component name (e.g., "motd" (file) or "network/ (subdir)")
0x0000958C       ADD R3 R1 DIRENT_NAME      ; destination dirent struc in KBUF_WR
0x00009590       LI  R6 0                   ; index

readdir_copy_name:
0x00009598       CMP R6 R8                  ;R8 = component name length
0x0000959C       BGE readdir_copy_name_done
0x000095A4       LDB R10 [R2 + R6]
0x000095A8       STB R10 [R3 + R6]
0x000095AC       ADD R6 R6 1
0x000095B0       B readdir_copy_name

readdir_copy_name_done:
    ; NUL-terminate
0x000095B8       LI R10 0
0x000095C0       STB R10 [R3 + R6]

    ; ---- copy whole dirent (DIRENT_SIZEOF bytes) to user buffer ----

0x000095C4       LI  R2 DIRENT_SIZEOF      ; len dirent
0x000095CC       MOV R4 R1                 ; kernel source (KBUF_WR)
0x000095D0       POP R1                    ; user buffer (original)
    ;MOV R1 R8                 ; user buffer (original)
0x000095D4       BL copy_to_user
0x000095DC       CMP R1 DIRENT_SIZEOF
0x000095E0       BNE readdir_fault

    ; return number of bytes written (DIRENT_SIZEOF)
0x000095E8       MOV R1 DIRENT_SIZEOF
0x000095EC       POP R12
0x000095F0       POP R11
0x000095F4       POP R10
0x000095F8       POP R9
0x000095FC       POP R8
0x00009600       POP LR
0x00009604       RET

readdir_skip:
0x00009608       ADD R6 R6 1
0x0000960C       B readdir_scan

readdir_nsfs_start:
0x00009614       LI R1 tar_count
0x0000961C       LDW R1 [R1]
0x00009620       SUB R6 R6 R1              ; convert merged file offset to nsfs index

readdir_nsfs_scan:
0x00009624       LI R1 nsfs_index_count
0x0000962C       LDW R1 [R1]
0x00009630       CMP R6 R1
0x00009634       BGE readdir_eof

0x0000963C       LI R1 NSFS_INDEX_ENTRY_SIZEOF
0x00009644       MUL R3 R6 R1
0x00009648       LI R7 nsfs_index_table
0x00009650       ADD R7 R7 R3              ; R7 = &nsfs_index_table[R6]

0x00009654       LDW R1 [R7 + NSFS_INDEX_PATH]
0x00009658       LDB R2 [R1]
0x0000965C       LI R3 47                  ; skip leading '/' for comparison with tar prefix
0x00009664       CMP R2 R3
0x00009668       BNE readdir_nsfs_prefix_ready
0x00009670       ADD R1 R1 1
readdir_nsfs_prefix_ready:
0x00009674       MOV R2 R10
0x00009678       BL str_prefix
0x00009680       CMP R1 1
0x00009684       BNE readdir_nsfs_skip

0x0000968C       LDW R1 [R7 + NSFS_INDEX_PATH]
0x00009690       LDB R2 [R1]
0x00009694       LI R3 47
0x0000969C       CMP R2 R3
0x000096A0       BNE readdir_nsfs_skip_ready
0x000096A8       ADD R1 R1 1
readdir_nsfs_skip_ready:
0x000096AC       MOV R2 R10
0x000096B0       BL skip_prefix
0x000096B8       MOV R9 R1

0x000096BC       LDB R2 [R9]
0x000096C0       CMP R2 0
0x000096C4       BEQ readdir_nsfs_skip

0x000096CC       MOV R1 R9
0x000096D0       BL path_component_len
0x000096D8       MOV R8 R1
0x000096DC       CMP R8 0
0x000096E0       BEQ readdir_nsfs_skip
0x000096E8       LI R2 63
0x000096F0       CMP R8 R2
0x000096F4       BLE readdir_nsfs_name_ok
0x000096FC       MOV R8 R2

readdir_nsfs_name_ok:
; macro: GET_CURR_TASK_IDX R4
0x00009700   LI R1 CURRENT_TASK
0x00009708   LDW R4 [R1]
; macro: GET_TASK_PTR R5, R4
0x0000970C   LI R1 TASK_SIZE
0x00009714   MUL R3 R4 R1
0x00009718   LI R5 tasks
0x00009720   ADD R5 R5 R3
; macro: TASK_GET_KBUF_WR R1, R5
0x00009724   LDW R1 [R5 + TASK_KBUF_WR_PTR]

0x00009728       LI R2 tar_count
0x00009730       LDW R2 [R2]
0x00009734       ADD R3 R2 R6
0x00009738       ADD R3 R3 1
0x0000973C       STW R3 [R1 + DIRENT_INODE]
0x00009740       STW R3 [R12 + FILE_OFFSET]

0x00009744       LDW R2 [R7 + NSFS_INDEX_SIZE]
0x00009748       STW R2 [R1 + DIRENT_SIZE]
0x0000974C       LDW R2 [R7 + NSFS_INDEX_TYPE]
0x00009750       CMP R2 NSFS_TYPE_DIR
0x00009754       BEQ readdir_nsfs_type_dir
0x0000975C       LI R2 DT_REG
0x00009764       B readdir_nsfs_type_done
readdir_nsfs_type_dir:
0x0000976C       LI R2 DT_DIR
readdir_nsfs_type_done:
0x00009774       STW R2 [R1 + DIRENT_TYPE]

0x00009778       MOV R2 R9
0x0000977C       ADD R3 R1 DIRENT_NAME
0x00009780       LI R6 0
readdir_nsfs_copy_name:
0x00009788       CMP R6 R8
0x0000978C       BGE readdir_nsfs_copy_done
0x00009794       LDB R10 [R2 + R6]
0x00009798       STB R10 [R3 + R6]
0x0000979C       ADD R6 R6 1
0x000097A0       B readdir_nsfs_copy_name
readdir_nsfs_copy_done:
0x000097A8       LI R10 0
0x000097B0       STB R10 [R3 + R6]

0x000097B4       LI R2 DIRENT_SIZEOF
0x000097BC       MOV R4 R1
0x000097C0       POP R1
0x000097C4       BL copy_to_user
0x000097CC       CMP R1 DIRENT_SIZEOF
0x000097D0       BNE readdir_fault_after_user_pop
0x000097D8       MOV R1 DIRENT_SIZEOF
0x000097DC       POP R12
0x000097E0       POP R11
0x000097E4       POP R10
0x000097E8       POP R9
0x000097EC       POP R8
0x000097F0       POP LR
0x000097F4       RET

readdir_nsfs_skip:
0x000097F8       ADD R6 R6 1
0x000097FC       LI R1 tar_count
0x00009804       LDW R1 [R1]
0x00009808       ADD R2 R1 R6
0x0000980C       STW R2 [R12 + FILE_OFFSET]
0x00009810       B readdir_nsfs_scan

readdir_eof:
0x00009818       Pop R1          ;bc we saved r8 inside loop
0x0000981C       LI R1 0
0x00009824       POP R12
0x00009828       POP R11
0x0000982C       POP R10
0x00009830       POP R9
0x00009834       POP R8
0x00009838       POP LR
0x0000983C       RET

readdir_short:
0x00009840       Pop R1
0x00009844       LI R1 ERR_FAULT
0x0000984C       POP R12
0x00009850       POP R11
0x00009854       POP R10
0x00009858       POP R9
0x0000985C       POP R8
0x00009860       POP LR
0x00009864       RET

readdir_fault:
0x00009868       Pop R1
readdir_fault_after_user_pop:
0x0000986C       LI R1 ERR_FAULT
0x00009874       POP R12
0x00009878       POP R11
0x0000987C       POP R10
0x00009880       POP R9
0x00009884       POP R8
0x00009888       POP LR
0x0000988C       RET


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

0x00009890       PUSH LR
0x00009894       PUSH R8
0x00009898       PUSH R9
0x0000989C       PUSH R10
0x000098A0       PUSH R11

0x000098A4       MOV R8 R1              ; save directory path
0x000098A8       LI R9 0                ; index

0x000098B0       LI R10 tar_count
0x000098B8       LDW R10 [R10]
tr_loop:
0x000098BC       CMP R9 R10
0x000098C0       BGE tr_done                     ;if all tar index scanned

    ; entry = &tar_index[i]
0x000098C8       LI R1 tar_index
0x000098D0       LI R2 TAR_IDX_SIZEOF
0x000098D8       MUL R3 R9 R2
0x000098DC       ADD R11 R1 R3
    ; entry name
0x000098E0       LDW R1 [R11 + TAR_IDX_NAME]
0x000098E4       MOV R2 R8                       ; src dirname "etc/"
0x000098E8       BL str_prefix                   ; check if tar_index entry name ie etc/motd matches prefix etc/
0x000098F0       CMP R1 1
0x000098F4       BNE tr_next                     ;r1=0 no match

    ; print matching name
0x000098FC       LDW R1 [R11 + TAR_IDX_NAME]
0x00009900       MOV R2 R8                       ; prefix
0x00009904       BL skip_prefix                  ; omit prefix nd print just filename

0x0000990C       MOV R12 R1         ; save component ptr
0x00009910       BL path_component_len ; out R1-length
0x00009918       MOV R2 R1
0x0000991C       MOV R1 R12
0x00009920       BL kputsn   ; r1-ptr r2-len of string

0x00009928       LI R1 newline
0x00009930       BL kputs

tr_next:
0x00009938       ADD R9 R9 1                     ;to next entry for check
0x0000993C       B tr_loop
tr_done:
0x00009944       POP R11
0x00009948       POP R10
0x0000994C       POP R9
0x00009950       POP R8
0x00009954       POP LR
0x00009958       RET

;==============================================================
; kputs - Simple kernel printf for debugging - prints a zero-terminated string
; to the console using uart_put
; R1 = zero terminated string
;==============================================================

kputs:
0x0000995C       PUSH LR
0x00009960       PUSH R8
0x00009964       MOV R8 R1

kputs_loop:
0x00009968       LDB R1 [R8]

0x0000996C       CMP R1 0
0x00009970       BEQ kputs_done

0x00009978       BL uart_putc

0x00009980       ADD R8 R8 1

0x00009984       B kputs_loop

kputs_done:
0x0000998C       POP R8
0x00009990       POP LR
0x00009994       RET

;==============================================================
; kputsn - Simple kernel printf for debugging - prints n chars of string
; to the console using uart_put
; R1 = string
; R2 = length
;==============================================================

kputsn:
0x00009998       PUSH LR
0x0000999C       PUSH R8
0x000099A0       PUSH R9
0x000099A4       MOV R8 R1
0x000099A8       MOV R9 R2
kputsn_loop:
0x000099AC       CMP R9 0
0x000099B0       BEQ kputsn_done
0x000099B8       LDB R1 [R8]
   ; CMP R1 0
   ; BEQ kputs_done
0x000099BC       BL uart_putc
0x000099C4       ADD R8 R8 1
0x000099C8       SUB R9 R9 1
0x000099CC       B kputsn_loop
kputsn_done:
0x000099D4       POP R9
0x000099D8       POP R8
0x000099DC       POP LR
0x000099E0       RET

;=====================================
; debug put char to uart from kernel
;=====================================
uart_putc:

0x000099E4       LI R3 0x00100000  ; UART MMIO Base Address
poll:
0x000099EC       LDW R2 [R3 + 4]   ; read UART status register
0x000099F0       AND R2 R2 2       ; check if TX ready (bit 1)
0x000099F4       CMP R2 0
0x000099F8       BEQ poll

0x00009A00       STW R1 [R3 + 0]   ; R1 is the character value
0x00009A04       RET



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
0x00009A08       PUSH R8
0x00009A0C       PUSH R9
0x00009A10       PUSH R10

0x00009A14       MOV R9 R1                  ; preserve wait queue pointer
0x00009A18       MOV R10 R2                 ; preserve debug wait reason
0x00009A1C       MOV R8 R3                  ; preserve task state to set

; macro: GET_CURR_TASK_IDX R2       ; R2 = current task index
0x00009A20   LI R1 CURRENT_TASK
0x00009A28   LDW R2 [R1]

0x00009A2C       LI R4 1
0x00009A34       SHL R4 R4 R2               ; R4 = bit for current task
0x00009A38       LDW R5 [R9 + WQ_MASK]
0x00009A3C       OR R5 R5 R4
0x00009A40       STW R5 [R9 + WQ_MASK]

; macro: GET_TASK_PTR R5, R2
0x00009A44   LI R1 TASK_SIZE
0x00009A4C   MUL R3 R2 R1
0x00009A50   LI R5 tasks
0x00009A58   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_BLOCKED_IO
0x00009A5C   LI R1 TASK_BLOCKED_IO
0x00009A64   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, R10
0x00009A68   STW R10 [R5 + TASK_WAIT]

; addition trick if R3 is set as TASK_SLEEPING then we also set the state to TASK_SLEEPING for syscall sleep/waitpid
0x00009A6C       CMP R8 TASK_SLEEPING
0x00009A70       BNE waitq_prepare_done
; macro: TASK_SET_STATE R5, TASK_SLEEPING
0x00009A78   LI R1 TASK_SLEEPING
0x00009A80   STW R1 [R5 + TASK_STATE]

waitq_prepare_done:
0x00009A84       POP R10
0x00009A88       POP R9
0x00009A8C       POP R8
0x00009A90       RET

waitq_cancel_sleep_current:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Removes the current task from the queue and marks it ready again.
    ; This is used by the device re-check path when the resource became
    ; ready before the task actually entered schedule_call.
    ;================================================================

0x00009A94       PUSH R9

0x00009A98       MOV R9 R1

; macro: GET_CURR_TASK_IDX R2
0x00009A9C   LI R1 CURRENT_TASK
0x00009AA4   LDW R2 [R1]

0x00009AA8       LDW R4 [R9 + WQ_MASK]

0x00009AAC       LI  R5 1
0x00009AB4       SHL R5 R5 R2        ;shift to position of current task bit

0x00009AB8       NOT R5 R5           ; invert to get mask for clearing this bit

0x00009ABC       AND R4 R4 R5        ; clear current task bit

0x00009AC0       STW R4 [R9 + WQ_MASK]   ; store back updated bitmask

; macro: GET_TASK_PTR R5, R2
0x00009AC4   LI R1 TASK_SIZE
0x00009ACC   MUL R3 R2 R1
0x00009AD0   LI R5 tasks
0x00009AD8   ADD R5 R5 R3

; macro: TASK_SET_STATE R5, TASK_READY   ;update task state to ready
0x00009ADC   LI R1 TASK_READY
0x00009AE4   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT  R5, WAIT_NONE    ;clear wait reason
0x00009AE8   LI R1 WAIT_NONE
0x00009AF0   STW R1 [R5 + TASK_WAIT]

0x00009AF4       POP R9
0x00009AF8       RET

waitq_sleep_current:
    ;================================================================
    ; Schedules away after waitq_prepare_sleep has marked this task
    ; blocked. The task resumes here when an IRQ/device wake marks it
    ; runnable and the scheduler switches back to it.
    ;================================================================

0x00009AFC       PUSH LR
0x00009B00       BL schedule_call
0x00009B08       POP LR
0x00009B0C       RET

waitq_wake_all:
    ;================================================================
    ; R1 = wait queue pointer
    ;
    ; Wakes every task currently recorded in the queue bitmask. The
    ; queue is cleared before tasks are marked ready so repeated IRQs do
    ; not keep waking stale entries.
    ;================================================================

0x00009B10       PUSH LR

0x00009B14       MOV R9 R1
0x00009B18       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00009B1C       LI R10 0
0x00009B24       STW R10 [R9 + WQ_MASK]     ; consume all queue entries

0x00009B28       LI R2 0                    ; task index

wq_wake_loop:
0x00009B30       CMP R2 MAX_TASKS           ;check if we processed all tasks in bitmask
0x00009B34       BGE wq_wake_done

0x00009B3C       LI R3 1
0x00009B44       SHL R3 R3 R2               ; R3 = bit for task R2
0x00009B48       AND R4 R8 R3
0x00009B4C       CMP R4 0
0x00009B50       BEQ wq_wake_next

; macro: GET_TASK_PTR R5, R2
0x00009B58   LI R1 TASK_SIZE
0x00009B60   MUL R3 R2 R1
0x00009B64   LI R5 tasks
0x00009B6C   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00009B70   LI R1 TASK_READY
0x00009B78   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00009B7C   LI R1 WAIT_NONE
0x00009B84   STW R1 [R5 + TASK_WAIT]

wq_wake_next:
0x00009B88       ADD R2 R2 1
0x00009B8C       B wq_wake_loop

wq_wake_done:
0x00009B94       POP LR
0x00009B98       RET

waitq_wake_bitmask:
    ;================================================================
    ; R1 = wait queue pointer
    ; R2 = bitmask of tasks to wake (1 = wake, 0 = ignore)
    ; Wakes every task currently recorded in the R2 bitmask.
    ;================================================================

0x00009B9C       PUSH LR

0x00009BA0       MOV R9 R1
0x00009BA4       LDW R8 [R9 + WQ_MASK]      ; snapshot queued tasks
0x00009BA8       MOV R10 R2                 ;
0x00009BAC       NOT R10 R10                ; invert bitmask to clear only specified tasks
0x00009BB0       AND R10 R8 R10             ; clear only specified tasks
0x00009BB4       STW R10 [R9 + WQ_MASK]     ; update queue entries to remove (tobe) woken  tasks

0x00009BB8       MOV R8 R2                  ; R8 = bitmask of tasks to wake
0x00009BBC       LI R2 0                    ; task index

wq_wake_b_loop:
0x00009BC4       CMP R2 MAX_TASKS           ; check if we processed all tasks in bitmask
0x00009BC8       BGE wq_wake_b_done

0x00009BD0       LI R3 1
0x00009BD8       SHL R3 R3 R2               ; R3 = bit for task R2
0x00009BDC       AND R4 R8 R3               ; check if this task is in the wake bitmask
0x00009BE0       CMP R4 0
0x00009BE4       BEQ wq_wake_b_next

; macro: GET_TASK_PTR R5, R2        ; wake task R2 if its in the bitmask
0x00009BEC   LI R1 TASK_SIZE
0x00009BF4   MUL R3 R2 R1
0x00009BF8   LI R5 tasks
0x00009C00   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x00009C04   LI R1 TASK_READY
0x00009C0C   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x00009C10   LI R1 WAIT_NONE
0x00009C18   STW R1 [R5 + TASK_WAIT]

wq_wake_b_next:
0x00009C1C       ADD R2 R2 1
0x00009C20       B wq_wake_b_loop

wq_wake_b_done:
0x00009C28       POP LR
0x00009C2C       RET

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
0x0000A230       LI R2 0                      ; index

ia_loop:
0x0000A238       CMP R2 MAX_INODES
0x0000A23C       BGE ia_fail

0x0000A244       SHL R3 R2 2                   ; index * 4 (inode_used is u32 array)
0x0000A248       LI R4 inode_used
0x0000A250       ADD R4 R4 R3                  ; &inode_used[index]

0x0000A254       LDW R5 [R4]                   ; load used marker
0x0000A258       CMP R5 0
0x0000A25C       BEQ ia_found

0x0000A264       ADD R2 R2 1
0x0000A268       B ia_loop

ia_found:
0x0000A270       LI R5 1
0x0000A278       STW R5 [R4]                  ; mark used

0x0000A27C       LI R3 INODE_SIZEOF
0x0000A284       MUL R6 R2 R3                 ; offset bytes into inode_pool

0x0000A288       LI R1 inode_pool
0x0000A290       ADD R1 R1 R6                 ; return inode ptr
0x0000A294       RET

ia_fail:
0x0000A298       LI R1 0
0x0000A2A0       RET

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

0x0000A2A4       LI R2 inode_pool
0x0000A2AC       SUB R3 R1 R2                  ; offset from pool base

0x0000A2B0       LI R4 INODE_SIZEOF
0x0000A2B8       DIV R5 R3 R4                 ; index

0x0000A2BC       SHL R5 R5 2                  ; index * 4 (u32 array)
0x0000A2C0       LI R6 inode_used
0x0000A2C8       ADD R6 R6 R5                 ; &inode_used[index]

0x0000A2CC       LI R7 0
0x0000A2D4       STW R7 [R6]                  ; mark free

0x0000A2D8       RET

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

0x0000A2DC       STW R2 [R1 + INODE_OPS]
0x0000A2E0       STW R3 [R1 + INODE_PRIVATE]
0x0000A2E4       STW R4 [R1 + INODE_TYPE]
0x0000A2E8       STW R5 [R1 + INODE_SIZE]
0x0000A2EC       LI R2 1
0x0000A2F4       STW R2 [R1 + INODE_REFCNT]
0x0000A2F8       RET

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
0x0000A2FC       LDW R2 [R1 + INODE_REFCNT]
0x0000A300       ADD R2 R2 1
0x0000A304       STW R2 [R1 + INODE_REFCNT]
0x0000A308       RET

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
0x0000A30C       PUSH LR
0x0000A310       LDW R2 [R1 + INODE_REFCNT]
0x0000A314       SUB R2 R2 1
0x0000A318       STW R2 [R1 + INODE_REFCNT]
0x0000A31C       CMP R2 0
0x0000A320       BNE inode_put_done
    ; destroy inode
0x0000A328       BL inode_free

inode_put_done:
0x0000A330       POP LR
0x0000A334       RET

; ----------------------------------
; file_get - increase file refcnt++
; in R1-file*
; ----------------------------------
file_get:
0x0000A338       LDW R2 [R1 + FILE_REFCNT]
0x0000A33C       ADD R2 R2 1
0x0000A340       STW R2 [R1 + FILE_REFCNT]
0x0000A344       RET
; ----------------------------------
; file_put - decrease file refcnt--
; in R1-file*. (if file.refcnt=0 - free_file and its inode (if inode.refcnt also =0))
; ----------------------------------
file_put:
0x0000A348       PUSH LR
0x0000A34C       LDW R2 [R1 + FILE_REFCNT]
0x0000A350       SUB R2 R2 1
0x0000A354       STW R2 [R1 + FILE_REFCNT]
0x0000A358       CMP R2 0
0x0000A35C       BNE file_put_done
    ; file refcnt=0 - destroy file
    ; R1-file*
0x0000A364       BL file_free

file_put_done:
0x0000A36C       POP LR
0x0000A370       RET


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
0x0000A374       PUSH LR
0x0000A378       PUSH R8
0x0000A37C       PUSH R9

0x0000A380       MOV R8 R1          ; pathname
0x0000A384       MOV R9 R2          ; flags

0x0000A388       MOV R3 R2         ; get flags copy

    ;-------------------------------------------------------------
    ; Validate access mode
    ;-------------------------------------------------------------
0x0000A38C       AND R3 R3 O_ACCMODE

0x0000A390       CMP R3 O_RDONLY
0x0000A394       BEQ vfs_access_ok

0x0000A39C       CMP R3 O_WRONLY
0x0000A3A0       BEQ vfs_access_ok

0x0000A3A8       CMP R3 O_RDWR
0x0000A3AC       BEQ vfs_access_ok
0x0000A3B4       B vfs_fail_access

vfs_access_ok:

0x0000A3BC       MOV R1 R8           ;check pathname is ok /path/name
0x0000A3C0       BL validate_pathname
0x0000A3C8       CMP R1 0
0x0000A3CC       BNE vfs_bad_pathname

0x0000A3D4       MOV R1 R8
0x0000A3D8       BL devfs_lookup    ; 1 check among /dev/.. "files"
0x0000A3E0       CMP R1 0
0x0000A3E4       BNE vfs_done       ;if exists  dev inode ok
    ; check nsfs
0x0000A3EC       MOV R1 R8
0x0000A3F0       MOV R2 R9
0x0000A3F4       BL nsfs_lookup     ; 2 writable overlay above tarfs
0x0000A3FC       CMP R1 0
0x0000A400       BNE vfs_done       ; if exists nsfs inode done
    ; check flags bf tarfs
    ; needs dbl check for rdonly mode here (to do)
0x0000A408       MOV R1 R8
0x0000A40C       MOV R2 R9
0x0000A410       AND R3 R2 O_ACCMODE
0x0000A414       cmp R3 O_RDONLY
0x0000A418       BNE vfs_nsfs_create_file
0x0000A420       BL tarfs_lookup     ; 3 check in rootfs-tarfs /... (both funcs in R1-pathname)
0x0000A428       CMP R1 0
0x0000A42C       BNE vfs_done       ; if exists tarfs inode done
vfs_nsfs_create_file:
    ; so path name valid, and not found in dev nsfs tarfs
    ; so its brand new
    ; try to create file in nsfs
0x0000A434       MOV R1 R8
0x0000A438       MOV R2 R9
    ; this is a valid pathname, check flags if need to create file or not
    ;check if no RO mode is set
0x0000A43C       AND R3 R2 1         ;check CREATE BIT 1
0x0000A440       cmp R3 O_CREATE
0x0000A444       BNE vfs_fail_access
    ; create file  if flag is set
0x0000A44C       BL nsfs_create     ; 2 writable overlay above tarfs it should create inode for the file and return result in R1
0x0000A454       CMP R1 0
0x0000A458       BNE vfs_done     ; if file created inode created - ok
    ;error creating file, return 0
0x0000A460       B vfs_err_create

vfs_done:
0x0000A468       POP R8
0x0000A46C       POP R9
0x0000A470       POP LR          ;3 R1 - return inode
0x0000A474       RET

; probably need specify reason not just R1=0 (to do)
vfs_err_create:
vfs_bad_pathname:
   ; MOV R2 R1        ;err code in R2
vfs_fail_access:
vfs_not_found:
0x0000A478       POP R8
0x0000A47C       POP R9
0x0000A480       LI R1 0         ;it can be just ret but i added it for result clarity
0x0000A488       POP LR          ;or R1 - Nul
0x0000A48C       RET

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
0x0000A490       PUSH LR
0x0000A494       PUSH R8
0x0000A498       PUSH R9
0x0000A49C       PUSH R10
0x0000A4A0       PUSH R11

0x0000A4A4       MOV R8 R1              ; R8 = pathname
0x0000A4A8       LI  R9 0               ; R9 = index
0x0000A4B0       LI  R10 EXEC_MAX_PATH  ; maximum including NUL

    ;-------------------------------------------------------------
    ; pathname[0] must exist
    ;-------------------------------------------------------------

0x0000A4B8       LDB R11 [R8]
0x0000A4BC       CMP R11 0
0x0000A4C0       BEQ validate_invalid

    ;-------------------------------------------------------------
    ; pathname must start with '/'
    ;-------------------------------------------------------------

0x0000A4C8       LI R11 47              ; '/'
0x0000A4D0       LDB R1 [R8]
0x0000A4D4       CMP R1 R11
0x0000A4D8       BNE validate_invalid

0x0000A4E0       ADD R9 R9 1

validate_loop:

    ;-------------------------------------------------------------
    ; length check
    ;-------------------------------------------------------------

0x0000A4E4       CMP R9 R10
0x0000A4E8       BGE validate_toolong

0x0000A4F0       LDB R11 [R8 + R9]

    ; end of string
0x0000A4F4       CMP R11 0
0x0000A4F8       BEQ validate_success
    ;-------------------------------------------------------------
    ; reject control characters
    ;
    ; ASCII < 0x20
    ;-------------------------------------------------------------
0x0000A500       LI R1 0x20
0x0000A508       CMP R11 R1
0x0000A50C       BLT validate_invalid
    ;-------------------------------------------------------------
    ; reject "//"
    ;-------------------------------------------------------------
0x0000A514       LI R1 47
0x0000A51C       CMP R11 R1
0x0000A520       BNE validate_next

    ; current char is '/'
    ; check previous char

0x0000A528       LI R1 1
0x0000A530       CMP R9 R1
0x0000A534       BEQ validate_next       ; first '/' is allowed

0x0000A53C       SUB R1 R9 1
0x0000A540       LDB R1 [R8 + R1]

0x0000A544       LI R2 47
0x0000A54C       CMP R1 R2
0x0000A550       BEQ validate_invalid
validate_next:
0x0000A558       ADD R9 R9 1
0x0000A55C       B validate_loop

validate_success:
0x0000A564       LI R1 0
0x0000A56C       B validate_done
validate_invalid:
0x0000A574       LI R1 ERR_INVAL
0x0000A57C       B validate_done
validate_toolong:
0x0000A584       LI R1 ERR_NAMETOOLONG
validate_done:
0x0000A58C       POP R11
0x0000A590       POP R10
0x0000A594       POP R9
0x0000A598       POP R8
0x0000A59C       POP LR
0x0000A5A0       RET

;=================================================================
; vfs_open - open pathname file
;
; in R1 - pathname ptr R2 - flags
; or R1 - fd of the file
;=================================================================

vfs_open:
0x0000A5A4       PUSH LR
0x0000A5A8       PUSH R8
0x0000A5AC       PUSH R9
0x0000A5B0       PUSH R10
0x0000A5B4       MOV R10 R2      ; flags

    ;check file R1=pathname ptr in kernel space
0x0000A5B8       BL vfs_lookup        ; vfs lookup (selects fs finds file/device and creates inited inode to put in file object)
0x0000A5C0       CMP R1 0
0x0000A5C4       BEQ fail_noent
    ;out: R1 new inited inode ptr
0x0000A5CC       MOV R8 R1            ; save inode ptr

0x0000A5D0       LDW R2 [R8 + INODE_TYPE]
0x0000A5D4       LI R3 INODE_DIR
0x0000A5DC       CMP R2 R3

    ;BEQ fail_isdir            ; if pathname is a dir -implemented readdir

0x0000A5E0       BL file_alloc        ; out: R1 = pointer to new FILE object in file_pool
0x0000A5E8       CMP R1 0
0x0000A5EC       BEQ fail_nfile

0x0000A5F4       MOV R9 R1                ; save file*

    ; initialize file object ;
0x0000A5F8       MOV R1 R9                ; R1 file*
0x0000A5FC       MOV R2 R8                ; inode*
0x0000A600       MOV R3 R10               ; flags
0x0000A604       BL file_init

0x0000A60C       MOV R1 R9
0x0000A610       BL fd_alloc             ; R1 inited file ptr
0x0000A618       LI R2 ERR_MFILE
0x0000A620       CMP R1 R2
0x0000A624       BEQ fail_fd
                            ; R1 - holds fd
0x0000A62C       POP R10
0x0000A630       POP R9
0x0000A634       POP R8
0x0000A638       POP LR
0x0000A63C       RET

fail_fd:
0x0000A640       MOV R1 R9
    ; FILE_GET_INODE R2, R1    ;
    ; R2 = [R1 file->inode] = inode
0x0000A644       LDW R2 [R1 + FILE_INODE]

0x0000A648       MOV R1 R2
0x0000A64C       BL inode_put             ; close inode refcnt--

0x0000A654       MOV R1 R9
0x0000A658       BL file_free
0x0000A660       LI R1 ERR_MFILE
0x0000A668       B  vfs_exit

fail_noent:
0x0000A670       LI R1 ERR_NOENT
0x0000A678       B  vfs_exit
fail_nfile:
0x0000A680       LI R1 ERR_NFILE
0x0000A688       B  vfs_exit
fail_isdir:
0x0000A690       LI R1 ERR_ISDIR
0x0000A698       B  vfs_exit
fail_acces:
0x0000A6A0       LI R1 ERR_ACCES
vfs_exit:
0x0000A6A8       POP R10
0x0000A6AC       POP R9
0x0000A6B0       POP R8
0x0000A6B4       POP LR
0x0000A6B8       RET

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
0x0000A6BC       PUSH LR
0x0000A6C0       BL fd_remove    ;in: R1-fd out: R1-file ptr for this fd

0x0000A6C8       CMP R1 0
0x0000A6CC       BEQ badf_fail

0x0000A6D4       MOV R8 R1          ; save file*

0x0000A6D8       MOV R1 R8
0x0000A6DC       BL  file_put    ;in R1 file_ptr in file_pool it
                    ;marks it as free (NULL) if file.refcnt==0 see doc
0x0000A6E4       LI  R1 0        ; success
0x0000A6EC       POP LR
0x0000A6F0       RET

badf_fail:
0x0000A6F4       LI R1 ERR_BADF
0x0000A6FC       POP LR
0x0000A700       RET


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

0x0000A704       LI R2 0                      ; index

fa_loop:
0x0000A70C       CMP R2 MAX_FILES
0x0000A710       BGE fa_fail

0x0000A718       SHL R3 R2 2                  ; index * 4
0x0000A71C       LI R4 file_used              ; look in file_used list 0 free 1 used
0x0000A724       ADD R4 R4 R3

0x0000A728       LDW R5 [R4]
0x0000A72C       CMP R5 0
0x0000A730       BEQ fa_found

0x0000A738       ADD R2 R2 1
0x0000A73C       B fa_loop

fa_found:
0x0000A744       LI R5 1
0x0000A74C       STW R5 [R4]                  ; mark slot used

0x0000A750       LI R4 FILE_SIZE
0x0000A758       MUL R6 R2 R4

0x0000A75C       LI R1 file_pool
0x0000A764       ADD R1 R1 R6                 ; R1 = file object pointer

    ;clean this slot
0x0000A768       LI R7 0

0x0000A770       STW R7 [R1 + FILE_INODE]
0x0000A774       STW R7 [R1 + FILE_OFFSET]
0x0000A778       STW R7 [R1 + FILE_FLAGS]

0x0000A77C       RET

fa_fail:
0x0000A780       LI R1 0
0x0000A788       RET

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
0x0000A78C       PUSH LR
0x0000A790       PUSH R10
0x0000A794       MOV  R10 R1
0x0000A798       LDW  R2 [R1 + FILE_INODE]

0x0000A79C       CMP R2 0
0x0000A7A0       BEQ no_inode

0x0000A7A8       MOV R1 R2
0x0000A7AC       BL  inode_put    ; destroys inode if inode.refcnt=0

no_inode:
0x0000A7B4       MOV R1 R10
0x0000A7B8       LI  R2 file_pool
0x0000A7C0       SUB R3 R1 R2                 ; offset from pool base

0x0000A7C4       LI  R4 FILE_SIZE
0x0000A7CC       DIV R5 R3 R4                 ; slot number

0x0000A7D0       SHL R5 R5 2                  ; slot * 4

0x0000A7D4       LI  R6 file_used
0x0000A7DC       ADD R6 R6 R5                 ; address of slot in file_used

0x0000A7E0       LI R7 0
0x0000A7E8       STW R7 [R6]                  ; mark free
0x0000A7EC       POP R10
0x0000A7F0       POP LR
0x0000A7F4       RET


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

0x0000A7F8       PUSH LR

    ;---------------------------------
    ;init task table - we can do it with mem_zero since it's all zeros and we want it clean slate
    ;---------------------------------

0x0000A7FC       LI  R1 tasks
0x0000A804       LI  R2 TASK_SIZE
0x0000A80C       LI  R3 MAX_TASKS
0x0000A814       MUL R3 R2 R3
0x0000A818       BL  mem_zero          ;zero (bytes) the whole task table for clean slate

    ; ----------------------------------
    ; idle task
    ; ----------------------------------

0x0000A820       LI R1 idle_task
0x0000A828       LI R2 0
0x0000A830       LI R3 0
0x0000A838       BL task_create

0x0000A840       CMP R1 0
0x0000A844       BEQ init_scheduler_fail

    ; ----------------------------------
    ; task_init
    ; ----------------------------------

0x0000A84C       LI R1 TASK_INIT_START
0x0000A854       LI R2 1
0x0000A85C       LI R3 0
0x0000A864       BL task_create

0x0000A86C       CMP R1 0
0x0000A870       BEQ init_scheduler_fail

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
0x0000A878       LI R1 task_count
0x0000A880       LI R2 2                     ; last task_pid+1 for now (task 0 and task 1) next id is 2
0x0000A888       STW R2 [R1]

    ; ------------------------------------------------
    ; CURRENT_TASK = 0 - init 0 task idx to scheduler first
    ; ------------------------------------------------

0x0000A88C       LI R2 0
; macro: SET_CURR_TASK_IDX R2
0x0000A894   LI R1 CURRENT_TASK
0x0000A89C   STW R2 [R1]

0x0000A8A0       POP LR

    ;MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x0000A8A4       RET


init_scheduler_fail:
0x0000A8A8       DEBUG 99
halt:
0x0000A8AC       B halt

; ================================================================
; SCHEDULE + SWITCH
; ================================================================

schedule_and_switch:

    ; ------------------------------------------------
    ; Load current task index
    ; ------------------------------------------------

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x0000A8B4   LI R1 CURRENT_TASK
0x0000A8BC   LDW R2 [R1]

    ; ------------------------------------------------
    ; Find next task
    ; ------------------------------------------------

0x0000A8C0       ADD R3 R2 1

wrap_check:

0x0000A8C4       CMP R3 MAX_TASKS     ;check if we processed all tasks in list - i
0x0000A8C8       BLT check_task
0x0000A8D0       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
    ; ------------------------------------------------
    ; Compute address of tasks[R3]
    ; ------------------------------------------------
0x0000A8D8       LI R4 TASK_SIZE
0x0000A8E0       MUL R5 R3 R4
0x0000A8E4       LI R6 tasks
0x0000A8EC       ADD R5 R5 R6               ; R5 = &tasks[R3]

    ; ------------------------------------------------
    ; Check READY state of this task
    ; ------------------------------------------------

0x0000A8F0       LDW R7 [R5 + TASK_STATE]

0x0000A8F4       CMP R7 1
0x0000A8F8       BEQ do_switch
    ; if not ready go to next task in list
0x0000A900       ADD R3 R3 1
0x0000A904       B wrap_check

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
0x0000A90C   LI R1 CURRENT_TASK
0x0000A914   STW R3 [R1]
0x0000A918       MOV R8 R3

    ; ------------------------------------------------
    ; Compute old task address
    ; ------------------------------------------------
    ; R2 - index of old/current task - get to its structure in mem
; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old], clobbers R3
0x0000A91C   LI R1 TASK_SIZE
0x0000A924   MUL R3 R2 R1
0x0000A928   LI R5 tasks
0x0000A930   ADD R5 R5 R3
0x0000A934       MOV R3 R8
0x0000A938       MOV R9 R5                  ; preserve old task pointer for deferred reap

    ; ------------------------------------------------
    ; Save old task context pointers
    ; ------------------------------------------------
    ; SP points to the old task's kernel trapframe. The original
    ; interrupted task SP is an explicit trapframe slot, so keep a copy
    ; in the task table for debugging and future user/kernel separation.

0x0000A93C       LDW R7 [SP + TF_USP]
; macro: TASK_SET_USP R5, R7
0x0000A940   STW R7 [R5 + TASK_USP]

0x0000A944       MOV R7 SP
; macro: TASK_SET_KSP R5, R7
0x0000A948   STW R7 [R5 + TASK_KSP]

; macro: TASK_SET_RESUME R5, RESUME_TRAP ;save it as it was stopped by usual trap/irq not in kernel's syscall
0x0000A94C   LI R1 RESUME_TRAP
0x0000A954   STW R1 [R5 + TASK_RESUME]

    ; ------------------------------------------------
    ; Compute new task address
    ; ------------------------------------------------
    ; now work with next task R3 - its index (+1) typic

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new]
0x0000A958   LI R1 TASK_SIZE
0x0000A960   MUL R3 R8 R1
0x0000A964   LI R5 tasks
0x0000A96C   ADD R5 R5 R3
0x0000A970       MOV R3 R8

    ; ------------------------------------------------
    ; Restore new task trap frame SP
    ; ------------------------------------------------

; macro: TASK_GET_PTBR R7, R5
0x0000A974   LDW R7 [R5 + TASK_PTBR]
0x0000A978       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries

; macro: TASK_GET_KSP SP, R5
0x0000A97C   LDW SP [R5 + TASK_KSP]

    ; SP now belongs to the new task, so it is safe to release an exiting
    ; old task's kernel stack and remaining address-space resources.
; macro: TASK_GET_STATE R7, R9
0x0000A980   LDW R7 [R9 + TASK_STATE]
0x0000A984       CMP R7 TASK_ZOMBIE
0x0000A988       BNE switch_old_reaped
0x0000A990       PUSH R5
0x0000A994       MOV R1 R9
0x0000A998       BL task_destroy
0x0000A9A0       POP R5

switch_old_reaped:
; macro: TASK_GET_RESUME R7, R5
0x0000A9A4   LDW R7 [R5 + TASK_RESUME]
0x0000A9A8       CMP R7 RESUME_KERNEL
0x0000A9AC       BEQ restore_kernel_context  ;select how to run new task - depending where it was stopped usual
                                ; trap or in kernel inside a syscall

0x0000A9B4       B trap_restore

; ================================================================
; Callable scheduler for blocking inside syscall/device code.
; Saves a kernel continuation and returns here when this task wakes.
; ================================================================

schedule_call:
0x0000A9BC       PUSH R1
0x0000A9C0       PUSH R2
0x0000A9C4       PUSH R3
0x0000A9C8       PUSH R4
0x0000A9CC       PUSH R5
0x0000A9D0       PUSH R6
0x0000A9D4       PUSH R7
0x0000A9D8       PUSH R8
0x0000A9DC       PUSH R9
0x0000A9E0       PUSH R10
0x0000A9E4       PUSH R11
0x0000A9E8       PUSH R12
0x0000A9EC       PUSH R14
0x0000A9F0       PUSH R15

; macro: GET_CURR_TASK_IDX R2       ; R2 = old task index
0x0000A9F4   LI R1 CURRENT_TASK
0x0000A9FC   LDW R2 [R1]

0x0000AA00       ADD R3 R2 1

schedule_call_wrap_check:
0x0000AA04       CMP R3 MAX_TASKS
0x0000AA08       BLT schedule_call_check_task
0x0000AA10       LI R3 0
                                ; R3 idx of next task
schedule_call_check_task:
0x0000AA18       MOV R8 R3
; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[R3] ptr on next task
0x0000AA1C   LI R1 TASK_SIZE
0x0000AA24   MUL R3 R8 R1
0x0000AA28   LI R5 tasks
0x0000AA30   ADD R5 R5 R3
0x0000AA34       MOV R3 R8

; macro: TASK_GET_STATE R7, R5
0x0000AA38   LDW R7 [R5 + TASK_STATE]
0x0000AA3C       CMP R7 TASK_READY               ; check it can be run
0x0000AA40       BEQ schedule_call_do_switch

0x0000AA48       ADD R3 R3 1
0x0000AA4C       B schedule_call_wrap_check

schedule_call_do_switch:
; macro: SET_CURR_TASK_IDX R3            ; make next current (upd CURRENT_TASK)
0x0000AA54   LI R1 CURRENT_TASK
0x0000AA5C   STW R3 [R1]
0x0000AA60       MOV R8 R3

; macro: GET_TASK_PTR R5, R2        ; R5 = &tasks[old] (r2 old task idx), clobbers R3
0x0000AA64   LI R1 TASK_SIZE
0x0000AA6C   MUL R3 R2 R1
0x0000AA70   LI R5 tasks
0x0000AA78   ADD R5 R5 R3
0x0000AA7C       MOV R3 R8

0x0000AA80       MOV R7 SP
; macro: TASK_SET_KSP R5, R7        ; tasks[old].TASK_KSP = SP (when in trap)
0x0000AA84   STW R7 [R5 + TASK_KSP]
; macro: TASK_SET_RESUME R5, RESUME_KERNEL
0x0000AA88   LI R1 RESUME_KERNEL
0x0000AA90   STW R1 [R5 + TASK_RESUME]

; macro: GET_TASK_PTR R5, R8        ; R5 = &tasks[new] (r3 new task idx)
0x0000AA94   LI R1 TASK_SIZE
0x0000AA9C   MUL R3 R8 R1
0x0000AAA0   LI R5 tasks
0x0000AAA8   ADD R5 R5 R3
0x0000AAAC       MOV R3 R8

; macro: TASK_GET_PTBR R7, R5       ; load new task's page table
0x0000AAB0   LDW R7 [R5 + TASK_PTBR]
0x0000AAB4       SETPTBR R7

; macro: TASK_GET_KSP SP, R5        ;restore new task KSP
0x0000AAB8   LDW SP [R5 + TASK_KSP]
; macro: TASK_GET_RESUME R7, R5     ;check if where new task was stopeed before
0x0000AABC   LDW R7 [R5 + TASK_RESUME]
0x0000AAC0       CMP R7 RESUME_KERNEL
0x0000AAC4       BEQ restore_kernel_context

0x0000AACC       B trap_restore              ; if new task was not stopped in kernel side - do usual via SRET

restore_kernel_context:         ;in case new task was stopped in kernel jump to it via RET
0x0000AAD4       DISABLEINT                  ; RET does jump by LR(R15)
0x0000AAD8       POP R15                     ; LR=pc of next instuction of BL shedule_call in sys_read/write eg
0x0000AADC       POP R14                     ; (in kernel)
0x0000AAE0       POP R12                     ; DI - to avoid int nesting
0x0000AAE4       POP R11
0x0000AAE8       POP R10
0x0000AAEC       POP R9
0x0000AAF0       POP R8
0x0000AAF4       POP R7
0x0000AAF8       POP R6
0x0000AAFC       POP R5
0x0000AB00       POP R4
0x0000AB04       POP R3
0x0000AB08       POP R2
0x0000AB0C       POP R1
0x0000AB10       RET
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
0x0000ABA4       PUSH  R5
0x0000ABA8       PUSH  R6
0x0000ABAC       PUSH  R7
0x0000ABB0       PUSH  R8
0x0000ABB4       PUSH  R9

0x0000ABB8       LI R2 0                  ; page index

pa_loop:
0x0000ABC0       LI R1 MAX_PHYS_PAGES

0x0000ABC8       CMP R2 R1
0x0000ABCC       BGE pa_fail                 ; if we've checked all pages, fail

    ; byte = index / 8

0x0000ABD4       MOV R3 R2
0x0000ABD8       SHR R3 R3 3                 ; divide by 8 to get byte index in bitmap

    ; bit = index & 7

0x0000ABDC       MOV R4 R2
0x0000ABE0       AND R4 R4 7                 ; modulo 8 to get bit index within the byte

    ; load bitmap byte

0x0000ABE4       LI R5 page_bitmap
0x0000ABEC       ADD R5 R5 R3                ; r3 is byte index, add to bitmap base
                                ; to get address of byte containing this page's bit

0x0000ABF0       LDB R6 [R5]                 ; load the byte containing the bit for this page

    ; mask = 1 << bit

0x0000ABF4       LI R7 1
0x0000ABFC       SHL R7 R7 R4                ; create a mask with a 1 in the position of the bit for this page

    ; allocated ?

0x0000AC00       AND R8 R6 R7                ; R8 = R6 & R7, will be 0 if the bit is not set (page is free),
                                ; non-zero if allocated
0x0000AC04       CMP R8 0
0x0000AC08       BEQ pa_found                ; if bit is 0, page is free

0x0000AC10       ADD R2 R2 1                 ; increment page index and check next page
0x0000AC14       B pa_loop

pa_found:

    ; mark page allocated

0x0000AC1C       OR  R6 R6 R7
0x0000AC20       STB R6 [R5]

    ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x0000AC24       LI  R9 PAGE_ALLOC_BASE

0x0000AC2C       MOV R1 R2
0x0000AC30       SHL R1 R1 12          ; page_index * 4096

0x0000AC34       ADD R1 R1 R9

0x0000AC38       POP R9
0x0000AC3C       POP R8
0x0000AC40       POP R7
0x0000AC44       POP R6
0x0000AC48       POP R5

0x0000AC4C       RET

pa_fail:

0x0000AC50       LI R1 0                     ; no free pages

0x0000AC58       POP R9
0x0000AC5C       POP R8
0x0000AC60       POP R7
0x0000AC64       POP R6
0x0000AC68       POP R5
0x0000AC6C       RET


;new page allocation routine with refcounts and bitmap for 128 pages of 4KB each (512KB total)

page_alloc:
0x0000AC70       PUSH R6
0x0000AC74       PUSH R7
0x0000AC78       PUSH R8
0x0000AC7C       PUSH R9

0x0000AC80       LI R2 0                     ; page index

pa1_loop:
0x0000AC88       LI R1 MAX_PHYS_PAGES
0x0000AC90       CMP R2 R1
0x0000AC94       BGE pa1_fail

0x0000AC9C       LI R1 page_refcounts
    ;ADD R5 R1 R2               ; address of refcount for this page
0x0000ACA4       LDB R6 [R1 + R2]           ; load refcount
0x0000ACA8       CMP R6 0
0x0000ACAC       BEQ pa1_found

0x0000ACB4       ADD R2 R2 1
0x0000ACB8       B pa1_loop

pa1_found:
0x0000ACC0       LI R6 1
0x0000ACC8       STB R6 [R1 + R2]          ; set refcount = 1

0x0000ACCC       LI R9 PAGE_ALLOC_BASE
0x0000ACD4       MOV R1 R2
0x0000ACD8       SHL R1 R1 12                ; index * PAGE_SIZE (4kB)
0x0000ACDC       ADD R1 R1 R9                ; physical address = PAGE_ALLOC_BASE + page_index * PAGE_SIZE

0x0000ACE0       POP R9
0x0000ACE4       POP R8
0x0000ACE8       POP R7
0x0000ACEC       POP R6                     ; R1 = physical address of allocated page
0x0000ACF0       RET

pa1_fail:
0x0000ACF4       LI R1 0                     ; no free pages
0x0000ACFC       POP R9
0x0000AD00       POP R8
0x0000AD04       POP R7
0x0000AD08       POP R6
0x0000AD0C       RET

;=================================================================
; page_get - increment refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_get:
    ; R1 = physical address
    ; Returns nothing; ignores invalid addresses
0x0000AD10       CMP R1 0
0x0000AD14       BEQ page_get_done

    ; Check lower bound
0x0000AD1C       LI R2 PAGE_ALLOC_BASE
0x0000AD24       CMP R1 R2
0x0000AD28       BLT page_get_done

    ; Check upper bound (exclusive)
0x0000AD30       LI R2 PAGE_ALLOC_END
0x0000AD38       CMP R1 R2
0x0000AD3C       BGE page_get_done

    ; Calculate index
0x0000AD44       LI R2 PAGE_ALLOC_BASE
0x0000AD4C       SUB R2 R1 R2       ; R1 pa
0x0000AD50       SHR R2 R2 12       ; R2 = page index in refcounts array
0x0000AD54       LI R3 page_refcounts
0x0000AD5C       ADD R3 R3 R2
0x0000AD60       LDB R4 [R3]
0x0000AD64       ADD R4 R4 1                 ; increment refcount
0x0000AD68       STB R4 [R3]
page_get_done:
0x0000AD6C       RET

;=================================================================
; page_put - decrement refcount for a physical page
; in R1 = physical page address
; out R1 = physical page address (unchanged)
;=================================================================

page_put:
    ; R1 = physical address
0x0000AD70       CMP R1 0                        ;if address is 0 - ignore
0x0000AD74       BEQ page_put_done

0x0000AD7C       LI R2 PAGE_ALLOC_BASE           ;check R1 is valid
0x0000AD84       CMP R1 R2
0x0000AD88       BLT page_put_done

0x0000AD90       LI R2 PAGE_ALLOC_END
0x0000AD98       CMP R1 R2
0x0000AD9C       BGE page_put_done

0x0000ADA4       LI R2 PAGE_ALLOC_BASE
0x0000ADAC       SUB R2 R1 R2
0x0000ADB0       SHR R2 R2 12        ; R2 = page index in refcounts array
0x0000ADB4       LI R3 page_refcounts
0x0000ADBC       ADD R3 R3 R2
0x0000ADC0       LDB R4 [R3]
0x0000ADC4       CMP R4 0
0x0000ADC8       BEQ page_put_done               ;if refcount already 0 - ignore it was freed already
0x0000ADD0       SUB R4 R4 1                     ;decrement refcount
0x0000ADD4       STB R4 [R3]
    ; If refcount becomes 0, the page is now free (no further action needed)
page_put_done:
0x0000ADD8       RET

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
0x0000ADDC       PUSH LR
0x0000ADE0       PUSH R8
0x0000ADE4       PUSH R9
0x0000ADE8       PUSH R10
0x0000ADEC       PUSH R11
0x0000ADF0       PUSH R12

0x0000ADF4       MOV R8 R1                 ; file size
0x0000ADF8       LI  R2 PAGE_SIZE
    ; compute num_pages = ceil(size / PAGE_SIZE)
0x0000AE00       ADD R1 R8 R2
0x0000AE04       SUB R1 R1 1               ; (fsz + 4095) / 4096
0x0000AE08       DIV R1 R1 R2              ; R1 = count
0x0000AE0C       MOV R9 R1                 ; save count

    ; ---- allocate table page ----
0x0000AE10       BL page_alloc
0x0000AE18       CMP R1 0
0x0000AE1C       BEQ table_alloc_fail
0x0000AE24       MOV R10 R1                ; table PA
0x0000AE28       LI R3 PAGE_SIZE
0x0000AE30       BL mem_zero               ; zero table
0x0000AE38       STW R9 [R10]              ; store count

    ; ---- allocate code pages and fill table ----
0x0000AE3C       LI R11 0                  ; index
0x0000AE44       LI R12 0                  ; error flag
alloc_table_loop:
0x0000AE4C       CMP R11 R9
0x0000AE50       BGE alloc_table_done
0x0000AE58       BL page_alloc             ;get new page
0x0000AE60       CMP R1 0
0x0000AE64       BEQ alloc_table_fail
0x0000AE6C       SHL R3 R11 2
0x0000AE70       ADD R4 R10 R3
0x0000AE74       ADD R4 R4 4
0x0000AE78       STW R1 [R4]               ; store R1 - new PA at table[4 + i*4]
0x0000AE7C       ADD R11 R11 1
0x0000AE80       B alloc_table_loop
alloc_table_done:
    ; success
0x0000AE88       MOV R1 R10                ; table PA
0x0000AE8C       MOV R2 R9                 ; count
0x0000AE90       LI R3 0                   ; success
0x0000AE98       POP R12
0x0000AE9C       POP R11
0x0000AEA0       POP R10
0x0000AEA4       POP R9
0x0000AEA8       POP R8
0x0000AEAC       POP LR
0x0000AEB0       RET

alloc_table_fail:
    ; free all already allocated code pages and the table
0x0000AEB4       MOV R12 R11               ; number allocated so far
0x0000AEB8       LI R11 0
rollback_loop:
0x0000AEC0       CMP R11 R12
0x0000AEC4       BGE rollback_done
0x0000AECC       SHL R3 R11 2
0x0000AED0       ADD R4 R10 R3
0x0000AED4       ADD R4 R4 4
0x0000AED8       LDW R1 [R4]
0x0000AEDC       CMP R1 0
0x0000AEE0       BEQ rollback_next
0x0000AEE8       BL page_put
rollback_next:
0x0000AEF0       ADD R11 R11 1
0x0000AEF4       B rollback_loop
rollback_done:
0x0000AEFC       MOV R1 R10
0x0000AF00       BL page_put               ; free table
0x0000AF08       LI R1 0
0x0000AF10       LI R2 0
0x0000AF18       LI R3 ERR_NOMEM
0x0000AF20       POP R12
0x0000AF24       POP R11
0x0000AF28       POP R10
0x0000AF2C       POP R9
0x0000AF30       POP R8
0x0000AF34       POP LR
0x0000AF38       RET

table_alloc_fail:
0x0000AF3C       LI R1 0
0x0000AF44       LI R2 0
0x0000AF4C       LI R3 ERR_NOMEM
0x0000AF54       POP R12
0x0000AF58       POP R11
0x0000AF5C       POP R10
0x0000AF60       POP R9
0x0000AF64       POP R8
0x0000AF68       POP LR
0x0000AF6C       RET

;------------------------------------------------------------------------------
; pages_free_table - Free a table and all its code pages.
;
; IN:   R1 = physical address of the table page
; OUT:  none
;------------------------------------------------------------------------------
pages_free_table:
0x0000AF70       PUSH LR
0x0000AF74       PUSH R8
0x0000AF78       PUSH R9
0x0000AF7C       PUSH R10

0x0000AF80       CMP R1 0
0x0000AF84       BEQ free_table_done
0x0000AF8C       MOV R8 R1                 ; table PA
0x0000AF90       LDW R9 [R8]               ; count
0x0000AF94       LI R10 0
free_table_loop:
0x0000AF9C       CMP R10 R9
0x0000AFA0       BGE free_table_done_pages
0x0000AFA8       SHL R3 R10 2
0x0000AFAC       ADD R4 R8 R3
0x0000AFB0       ADD R4 R4 4
0x0000AFB4       LDW R1 [R4]
0x0000AFB8       CMP R1 0
0x0000AFBC       BEQ free_table_next
0x0000AFC4       BL page_put
free_table_next:
0x0000AFCC       ADD R10 R10 1
0x0000AFD0       B free_table_loop
free_table_done_pages:
0x0000AFD8       MOV R1 R8
0x0000AFDC       BL page_put               ; free the table page itself
free_table_done:
0x0000AFE4       POP R10
0x0000AFE8       POP R9
0x0000AFEC       POP R8
0x0000AFF0       POP LR
0x0000AFF4       RET

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
0x0000AFF8       PUSH LR
0x0000AFFC       PUSH R5
0x0000B000       PUSH R6
0x0000B004       PUSH R7
0x0000B008       PUSH R8
0x0000B00C       PUSH R9
0x0000B010       PUSH R10
0x0000B014       PUSH R11

0x0000B018       MOV R8 R1                 ; table PA
0x0000B01C       MOV R9 R2                 ; PTBR
0x0000B020       MOV R10 R3                ; VA start
0x0000B024       MOV R11 R4                ; flags
0x0000B028       LDW R6 [R8]               ; count
0x0000B02C       LI R7 0
map_table_loop:
0x0000B034       CMP R7 R6
0x0000B038       BGE map_table_done
0x0000B040       SHL R3 R7 2
0x0000B044       ADD R4 R8 R3
0x0000B048       ADD R4 R4 4
0x0000B04C       LDW R5 [R4]            ; physical address
0x0000B050       MOV R1 R9                 ; PTBR
0x0000B054       LI  R3 PAGE_SIZE
0x0000B05C       MUL R3 R7 R3              ; offset = index * PAGE_SIZE
0x0000B060       MOV R2 R10
0x0000B064       ADD R2 R2 R3              ; VA for this page
0x0000B068       MOV R3 R5                 ; restore physical page after calculating VA offset
0x0000B06C       MOV R4 R11
0x0000B070       BL map_page_rt
0x0000B078       ADD R7 R7 1
0x0000B07C       B map_table_loop
map_table_done:
0x0000B084       POP R11
0x0000B088       POP R10
0x0000B08C       POP R9
0x0000B090       POP R8
0x0000B094       POP R7
0x0000B098       POP R6
0x0000B09C       POP R5
0x0000B0A0       POP LR
0x0000B0A4       RET


;================================================================
; Page deallocation routines
; in R1 = physical page address to free
; index = (addr - BASE)/4096
;================================================================

page_free0:
0x0000B0A8       PUSH  R5
0x0000B0AC       PUSH  R6
0x0000B0B0       PUSH  R7
0x0000B0B4       PUSH  R8
0x0000B0B8       PUSH  R9


0x0000B0BC       LI R2 PAGE_ALLOC_BASE
0x0000B0C4       SUB R3 R1 R2         ; calculate offset from base

0x0000B0C8       SHR R3 R3 12         ; page index = (addr - BASE)/4096

0x0000B0CC       MOV R4 R3
0x0000B0D0       SHR R4 R4 3          ; byte index in bitmap = page index / 8

0x0000B0D4       MOV R5 R3
0x0000B0D8       AND R5 R5 7          ; bit index in byte = page index % 8

0x0000B0DC       LI R6 page_bitmap
0x0000B0E4       ADD R6 R6 R4         ; address of byte in bitmap containing this page's bit

0x0000B0E8       LDB R7 [R6]

0x0000B0EC       LI R8 1
0x0000B0F4       SHL R8 R8 R5         ; mask for this page's bit

0x0000B0F8       NOT R8 R8            ; invert mask to have 0 in the page's bit position and 1s elsewhere

0x0000B0FC       AND R7 R7 R8         ; clear the bit to mark the page as free by ANDing with the inverted mask
                         ; which has a 0 in the position of the page's bit


0x0000B100       STB R7 [R6]          ; store the updated byte with the cleared bit back to the bitmap

0x0000B104       POP R9
0x0000B108       POP R8
0x0000B10C       POP R7
0x0000B110       POP R6
0x0000B114       POP R5
0x0000B118       RET

;=================================================================
; Zero out a page of memory at the given address (R1) R3 = PAGE_SIZE / amount to zero out
;=================================================================

mem_zero:
0x0000B11C       LI R2 0
pz_loop:
0x0000B124       CMP R3 0
0x0000B128       BEQ pz_done
0x0000B130       STB R2 [R1]
0x0000B134       ADD R1 R1 1
0x0000B138       SUB R3 R3 1
0x0000B13C       B pz_loop
pz_done:
0x0000B144       RET

;=================================================================
; memory copy at the given address (R1)<(R2) R3 = amount
;=================================================================

memcpy:

cpy_loop:
0x0000B148       CMP R3 0
0x0000B14C       BEQ cpy_done
0x0000B154       LDB R4 [R2]
0x0000B158       STB R4 [R1]
0x0000B15C       ADD R1 R1 1
0x0000B160       ADD R2 R2 1
0x0000B164       SUB R3 R3 1
0x0000B168       B cpy_loop
cpy_done:
0x0000B170       RET

; ================================================================
; Copy a memory page (or other multiple of 4 bytes) by physical address.
; R1 = source physical address (should be aligned!)
; R2 = destination physical address (aligned!)
; R3 = size in bytes (must be multiple of 4)
; each time it copyes 4 bytes (1 word)
; ================================================================
page_copy:

page_copy_loop:
0x0000B174       CMP R3 0
0x0000B178       BEQ page_copy_done
0x0000B180       LDW R4 [R1]
0x0000B184       STW R4 [R2]
0x0000B188       ADD R1 R1 4
0x0000B18C       ADD R2 R2 4
0x0000B190       SUB R3 R3 4
0x0000B194       B page_copy_loop

page_copy_done:
0x0000B19C       RET

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

0x0000B6A4       PUSH LR

0x0000B6A8       MOV R8 R1          ; entry
0x0000B6AC       MOV R9 R2          ; pid
0x0000B6B0       LI R10 0           ; task pointer, kept zero until task_alloc succeeds

    ; ----------------------------------
    ; allocate task slot
    ; ----------------------------------

0x0000B6B8       BL task_alloc       ; R1 = task pointer or 0 if no free slots

0x0000B6C0       CMP R1 0
0x0000B6C4       BEQ task_create_fail

0x0000B6CC       MOV R10 R1         ; R10 = task pointer

    ; A recycled slot may still contain pointers from its previous owner.
    ; Clear it before recording resources so failure cleanup is reliable.
0x0000B6D0       MOV R1 R10
0x0000B6D4       LI R3 TASK_SIZE
0x0000B6DC       BL mem_zero
; macro: TASK_SET_PC R10, R8
0x0000B6E4   STW R8 [R10 + TASK_PC]
; macro: TASK_SET_PID R10, R9
0x0000B6E8   STW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; allocate PTBR page
    ; ----------------------------------

0x0000B6EC       BL page_alloc
0x0000B6F4       CMP R1 0
0x0000B6F8       BEQ task_create_fail

0x0000B700       MOV R12 R1

; macro: TASK_SET_PTBR R10, R1          ; set task page table base
0x0000B704   STW R1 [R10 + TASK_PTBR]

0x0000B708       MOV R1 R12
0x0000B70C       LI  R3 PAGE_SIZE
0x0000B714       BL  mem_zero                   ; zero out the sensitive new page table

0x0000B71C       MOV R1 R12
0x0000B720       BL map_common_kernel        ; map kernel space into new page table so task can run in it
        ;and call kernel functions and access kernel data structures when needed

    ; Map only this task's executable page. User programs currently retain
    ; their assembled entry VAs; data and stack VAs are common to all tasks.
; macro: TASK_GET_PC R8, R10
0x0000B728   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x0000B72C   LDW R9 [R10 + TASK_PID]
; macro: TASK_GET_PTBR R1, R10
0x0000B730   LDW R1 [R10 + TASK_PTBR]
0x0000B734       MOV R2 R8
0x0000B738       LI R3 0xFFFFF000
0x0000B740       AND R2 R2 R3
0x0000B744       MOV R3 R2
0x0000B748       CMP R9 0
0x0000B74C       BEQ task_create_map_kernel_entry
0x0000B754       LI R4 USER_RX
0x0000B75C       B task_create_map_entry
task_create_map_kernel_entry:
0x0000B764       LI R4 KERNEL_FLAGS
task_create_map_entry:
0x0000B76C       BL map_page

    ; ----------------------------------
    ; allocate user stack page
    ; ----------------------------------

0x0000B774       BL page_alloc
0x0000B77C       CMP R1 0
0x0000B780       BEQ task_create_fail

0x0000B788       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12
0x0000B78C   STW R12 [R10 + TASK_USTACK_PAGE]

0x0000B790       LI R11 USER_STACK_TOP
; macro: TASK_SET_USP R10, R11           ; all tasks use the same virtual stack top
0x0000B798   STW R11 [R10 + TASK_USP]

; macro: TASK_GET_PTBR R1, R10       ; get task page table base to map user stack page into it
0x0000B79C   LDW R1 [R10 + TASK_PTBR]

0x0000B7A0       LI  R2 USER_STACK_VA
0x0000B7A8       MOV R3 R12
0x0000B7AC       LI  R4 USER_RW
    ;R1 = page table base R2=va to map R3=pa of page to map R4=permissions
0x0000B7B4       BL map_page                 ; map user stack page into task page table with RW permissions for user

    ; ----------------------------------
    ; allocate kernel stack page
    ; ----------------------------------

0x0000B7BC       BL page_alloc
0x0000B7C4       CMP R1 0
0x0000B7C8       BEQ task_create_fail

; macro: TASK_SET_KSTACK_PAGE R10, R1
0x0000B7D0   STW R1 [R10 + TASK_KSTACK_PAGE]
0x0000B7D4       LI R2 PAGE_SIZE

0x0000B7DC       MOV R12 SP             ; save kernel SP before we mess with it for stack frame setup

0x0000B7E0       ADD SP R1 R2           ; last address of the new allocated physical
                           ; page for kernel stack top

; macro: TASK_GET_PC R8, R10
0x0000B7E4   LDW R8 [R10 + TASK_PC]
; macro: TASK_GET_PID R9, R10
0x0000B7E8   LDW R9 [R10 + TASK_PID]

    ; ----------------------------------
    ; build initial trap frame
    ; identical to static task init
    ; into that new page
    ; ----------------------------------

0x0000B7EC       LI R1 0

0x0000B7F4       PUSH R1            ; R1
0x0000B7F8       PUSH R1            ; R2
0x0000B7FC       PUSH R1            ; R3
0x0000B800       PUSH R1            ; R4
0x0000B804       PUSH R1            ; R5
0x0000B808       PUSH R1            ; R6
0x0000B80C       PUSH R1            ; R7
0x0000B810       PUSH R1            ; R8
0x0000B814       PUSH R1            ; R9
0x0000B818       PUSH R1            ; R10
0x0000B81C       PUSH R1            ; R11
0x0000B820       PUSH R1            ; R12
0x0000B824       PUSH R1            ; R14 (FP)
0x0000B828       PUSH R1            ; R15 (LR)

0x0000B82C       PUSH R11           ; R11 - user SP top

0x0000B830       MOV R1 R8
0x0000B834       PUSH R1            ; sepc = entry

0x0000B838       LI R1 0
0x0000B840       PUSH R1            ; sflags

0x0000B844       CMP R9 0
0x0000B848       BEQ task_create_kernel_status
0x0000B850       LI R1 0x20
0x0000B858       B task_create_status_ready
task_create_kernel_status:
0x0000B860       LI R1 0x120
task_create_status_ready:
0x0000B868       PUSH R1            ; sstatus

0x0000B86C       LI R1 0
0x0000B874       PUSH R1            ; scause
0x0000B878       PUSH R1            ; stval

    ; ----------------------------------
    ; task structure
    ; ----------------------------------

0x0000B87C       MOV R1 SP
; macro: TASK_SET_KSP R10, R1                    ; save kernel trapframe SP in task struct
0x0000B880   STW R1 [R10 + TASK_KSP]

0x0000B884       MOV SP R12         ; restore kernel SP after stack frame setup

; macro: TASK_SET_WAIT R10, WAIT_NONE            ; set wait reason to none (not sleeping)
0x0000B888   LI R1 WAIT_NONE
0x0000B890   STW R1 [R10 + TASK_WAIT]

; macro: TASK_SET_RESUME R10, RESUME_TRAP        ; set resume switch to trap - this means
0x0000B894   LI R1 RESUME_TRAP
0x0000B89C   STW R1 [R10 + TASK_RESUME]
    ;when we schedule to this task it will run via trap restore path (usual case)

    ; ----------------------------------
    ; fd table
    ; ----------------------------------

0x0000B8A0       BL page_alloc
0x0000B8A8       CMP R1 0
0x0000B8AC       BEQ task_create_fail

    ; set task fd_table ptr to new page

    ; R1 = newly allocated fd table page

0x0000B8B4       MOV R12 R1

0x0000B8B8       LI  R3 PAGE_SIZE
0x0000B8C0       MOV R1 R12
0x0000B8C4       BL  mem_zero

    ; stdin
0x0000B8CC       LI  R2 file_stdin
0x0000B8D4       STW R2 [R12 + 0]

    ; stdout
0x0000B8D8       LI  R2 file_stdout
0x0000B8E0       STW R2 [R12 + 4]

    ; stderr
0x0000B8E4       LI  R2 file_stderr
0x0000B8EC       STW R2 [R12 + 8]

; macro: TASK_SET_FD_TABLE R10, R12
0x0000B8F0   STW R12 [R10 + TASK_FD_TABLE]

    ; ----------------------------------
    ; kernel buffers
    ; ----------------------------------

0x0000B8F4       BL page_alloc
0x0000B8FC       CMP R1 0
0x0000B900       BEQ task_create_fail

; macro: TASK_SET_KBUF_WR R10, R1                ; set task kernel write buffer (upto whole page for now)
0x0000B908   STW R1 [R10 + TASK_KBUF_WR_PTR]

0x0000B90C       BL page_alloc
0x0000B914       CMP R1 0
0x0000B918       BEQ task_create_fail

; macro: TASK_SET_KBUF_RD R10, R1                ; set task kernel read buffer
0x0000B920   STW R1 [R10 + TASK_KBUF_RD_PTR]

    ; ----------------------------------
    ; data page - for user buffers and heap
    ; ----------------------------------

0x0000B924       BL page_alloc
0x0000B92C       CMP R1 0
0x0000B930       BEQ task_create_fail

; macro: TASK_SET_DATA_PAGE R10, R1              ; set task data page
0x0000B938   STW R1 [R10 + TASK_DATA_PAGE]

0x0000B93C       MOV R12 R1

; macro: TASK_GET_PTBR R1, R10
0x0000B940   LDW R1 [R10 + TASK_PTBR]
0x0000B944       LI  R2 USER_DATA_VA
0x0000B94C       MOV R3 R12
0x0000B950       LI  R4 USER_RW
0x0000B958       BL map_page                 ; map task data page into task page table with RW permissions for user

    ; initialize code page pointer to zero until execve or static code assignment
    ; This means the task currently has no execve-loaded program image.
    ; When execve runs, TASK_CODE_PAGE will be updated to point to the
    ; physical page currently mapped at USER_CODE_VA.
0x0000B960       LI R1 0
; macro: TASK_SET_CODE_PAGE R10, R1
0x0000B968   STW R1 [R10 + TASK_CODE_PAGE]

    ; Publish the task only after every required resource and mapping exists.
; macro: TASK_SET_STATE R10, TASK_READY
0x0000B96C   LI R1 TASK_READY
0x0000B974   STW R1 [R10 + TASK_STATE]

    ; Initialize program break pointer to HEAP_START in User_Data_VA
0x0000B978       LI R1 HEAP_START
; macro: TASK_SET_BREAK R10, R1
0x0000B980   STW R1 [R10 + TASK_BREAK]

    ; Initialize parent PID to 0 by default
0x0000B984       LI R1 0
; macro: TASK_SET_PPID R10, R1
0x0000B98C   STW R1 [R10 + TASK_PPID]

0x0000B990       MOV R1 R10                              ; return created task pointer

0x0000B994       POP LR
0x0000B998       RET


task_create_fail:
    ; If any step of task creation fails, we must clean up all resources allocated
    ; so far and return 0.

    ; task_alloc can fail before R10 is assigned.
0x0000B99C       CMP R10 0
0x0000B9A0       BEQ task_create_fail_return

    ; Release every resource already attached to the unpublished task.
; macro: TASK_GET_PTBR R1, R10
0x0000B9A8   LDW R1 [R10 + TASK_PTBR]
0x0000B9AC       CMP R1 0
0x0000B9B0       BEQ task_create_free_ustack
0x0000B9B8       BL page_put

task_create_free_ustack:
; macro: TASK_GET_USTACK_PAGE R1, R10
0x0000B9C0   LDW R1 [R10 + TASK_USTACK_PAGE]
0x0000B9C4       CMP R1 0
0x0000B9C8       BEQ task_create_free_kstack
0x0000B9D0       BL page_put

task_create_free_kstack:
; macro: TASK_GET_KSTACK_PAGE R1, R10
0x0000B9D8   LDW R1 [R10 + TASK_KSTACK_PAGE]
0x0000B9DC       CMP R1 0
0x0000B9E0       BEQ task_create_free_fd
0x0000B9E8       BL page_put

task_create_free_fd:
; macro: TASK_GET_FD_TABLE R1, R10
0x0000B9F0   LDW R1 [R10 + TASK_FD_TABLE]
0x0000B9F4       CMP R1 0
0x0000B9F8       BEQ task_create_free_kwr
0x0000BA00       BL page_put

task_create_free_kwr:
; macro: TASK_GET_KBUF_WR R1, R10
0x0000BA08   LDW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000BA0C       CMP R1 0
0x0000BA10       BEQ task_create_free_krd
0x0000BA18       BL page_put

task_create_free_krd:
; macro: TASK_GET_KBUF_RD R1, R10
0x0000BA20   LDW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000BA24       CMP R1 0
0x0000BA28       BEQ task_create_free_data
0x0000BA30       BL page_put

task_create_free_data:
; macro: TASK_GET_DATA_PAGE R1, R10
0x0000BA38   LDW R1 [R10 + TASK_DATA_PAGE]
0x0000BA3C       CMP R1 0
0x0000BA40       BEQ task_create_clear_slot
0x0000BA48       BL page_put

task_create_clear_slot:
0x0000BA50       MOV R1 R10
0x0000BA54       LI R3 TASK_SIZE
0x0000BA5C       BL mem_zero

task_create_fail_return:
0x0000BA64       LI R1 0

0x0000BA6C       POP LR
0x0000BA70       RET

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
0x0000BA74       MOV  R8 SP ;save sp to point to task trapframe!
0x0000BA78       PUSH LR

    ; Get the current task slot and parent task pointer.
; macro: GET_CURR_TASK_IDX R6
0x0000BA7C   LI R1 CURRENT_TASK
0x0000BA84   LDW R6 [R1]
; macro: GET_TASK_PTR R7, R6           ; R7 = parent task*
0x0000BA88   LI R1 TASK_SIZE
0x0000BA90   MUL R3 R6 R1
0x0000BA94   LI R7 tasks
0x0000BA9C   ADD R7 R7 R3

    ; Allocate a fresh child task slot.
0x0000BAA0       BL task_alloc
0x0000BAA8       CMP R1 0
0x0000BAAC       BEQ clone_fail
0x0000BAB4       MOV R10 R1                    ; R10 = child task*

    ; Clear the new child task slot before use.
0x0000BAB8       MOV R1 R10
0x0000BABC       LI R3 TASK_SIZE
0x0000BAC4       BL mem_zero

    ; Assign a new PID from the dynamic pid counter.
0x0000BACC       LI R1 task_count
0x0000BAD4       LDW R2 [R1]

; macro: TASK_SET_PID R10, R2        ; set new child task Pid to child task (current task_count value)
0x0000BAD8   STW R2 [R10 + TASK_PID]
0x0000BADC       ADD R2 R2 1
0x0000BAE0       STW R2 [R1]                 ; update task_count as we created a new task

    ; Set child parent PID to the current task's PID.
; macro: TASK_GET_PID R2, R7
0x0000BAE4   LDW R2 [R7 + TASK_PID]
; macro: TASK_SET_PPID R10, R2       ; pid - new, ppid - parent task's pid (new task)
0x0000BAE8   STW R2 [R10 + TASK_PPID]

    ; Copy the current task's program break.
; macro: TASK_GET_BREAK R2, R7
0x0000BAEC   LDW R2 [R7 + TASK_BREAK]
; macro: TASK_SET_BREAK R10, R2
0x0000BAF0   STW R2 [R10 + TASK_BREAK]

    ; Copy current task PC for debugging/metadata.
; macro: TASK_GET_PC R2, R7
0x0000BAF4   LDW R2 [R7 + TASK_PC]
; macro: TASK_SET_PC R10, R2
0x0000BAF8   STW R2 [R10 + TASK_PC]

    ; Allocate and initialize a fresh page table for the child.
0x0000BAFC       BL page_alloc
0x0000BB04       CMP R1 0
0x0000BB08       BEQ clone_fail
0x0000BB10       MOV R11 R1
; macro: TASK_SET_PTBR R10, R11
0x0000BB14   STW R11 [R10 + TASK_PTBR]

    ; Clone the parent's entire page table into the child.
; macro: TASK_GET_PTBR R1, R7
0x0000BB18   LDW R1 [R7 + TASK_PTBR]
0x0000BB1C       MOV R2 R11
0x0000BB20       LI R3 PAGE_SIZE
0x0000BB28       BL page_copy

    ; child will inherit code page pa (tab+codepages) from parent
; macro: TASK_GET_CODE_PAGE R2, R7   ; R2 = parent's code page PA table
0x0000BB30   LDW R2 [R7 + TASK_CODE_PAGE]
0x0000BB34       CMP R2 0
0x0000BB38       BEQ skip_code_get
    ; 1) allocate new table page
0x0000BB40       BL page_alloc
0x0000BB48       CMP R1 0
0x0000BB4C       BEQ clone_fail
0x0000BB54       MOV R12 R1
    ; 2) copy the table page parnt to child (it contins count and pointers to pa pages)
0x0000BB58       MOV R1 R2
0x0000BB5C       MOV R2 R12
0x0000BB60       LI R3 PAGE_SIZE
0x0000BB68       BL page_copy    ;4k

; increment refcounts for each code page
0x0000BB70       LDW R8 [R12]               ; count: +0
0x0000BB74       LI R9 0                    ; page index in tab
clone_inc_loop:
0x0000BB7C       CMP R9 R8
0x0000BB80       BGE clone_inc_done
0x0000BB88       SHL R3 R9 2
0x0000BB8C       ADD R4 R12 R3
0x0000BB90       ADD R4 R4 4
0x0000BB94       LDW R1 [R4]                ;pa ptr: R4=R12(=+0) + 4+idx*4
0x0000BB98       CMP R1 0
0x0000BB9C       BEQ clone_inc_next
0x0000BBA4       BL page_get                ; refcount+1
clone_inc_next:
0x0000BBAC       ADD R9 R9 1
0x0000BBB0       B clone_inc_loop
clone_inc_done:

; macro: TASK_SET_CODE_PAGE R10, R12 ;  set child's code page PA (tab+pages)
0x0000BBB8   STW R12 [R10 + TASK_CODE_PAGE]

   ; TASK_SET_CODE_PAGE R10, R2  ; set child's code page PA to parent's code page PA
    ; Now increment refcount for the shared code page (if code page is allocated).
    ;(it is in case when execve was called before fork or when fork-execve, then fork-execve, then fork-execve etc. - all children share the same code page)
   ; MOV R1 R2
   ; BL page_get     ;increment refcount for the shared code page (if code page is allocated)
skip_code_get:

    ; The child has inherited the parent's kernel and code mappings.
    ; We will override the user stack and data mappings below.
    ; Allocate and clone the user stack page.
0x0000BBBC       BL page_alloc
0x0000BBC4       CMP R1 0
0x0000BBC8       BEQ clone_fail
0x0000BBD0       MOV R12 R1
; macro: TASK_SET_USTACK_PAGE R10, R12   ; set new page as child user stack page
0x0000BBD4   STW R12 [R10 + TASK_USTACK_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x0000BBD8   LDW R1 [R10 + TASK_PTBR]
0x0000BBDC       LI R2 USER_STACK_VA
0x0000BBE4       MOV R3 R12
0x0000BBE8       LI R4 USER_RW
0x0000BBF0       BL map_page             ; map user stack page to child ptbr

; macro: TASK_GET_USTACK_PAGE R1, R7
0x0000BBF8   LDW R1 [R7 + TASK_USTACK_PAGE]
0x0000BBFC       MOV R2 R12
0x0000BC00       LI R3 PAGE_SIZE
0x0000BC08       BL page_copy            ; copy parent user stack page -> child user stack page

    ; Allocate and clone the user data page.
0x0000BC10       BL page_alloc
0x0000BC18       CMP R1 0
0x0000BC1C       BEQ clone_fail
0x0000BC24       MOV R12 R1
; macro: TASK_SET_DATA_PAGE R10, R12     ; set new page as child user data page
0x0000BC28   STW R12 [R10 + TASK_DATA_PAGE]

; macro: TASK_GET_PTBR R1, R10
0x0000BC2C   LDW R1 [R10 + TASK_PTBR]
0x0000BC30       LI R2 USER_DATA_VA
0x0000BC38       MOV R3 R12
0x0000BC3C       LI R4 USER_RW
0x0000BC44       BL map_page                     ; map user data page to child ptbr

; macro: TASK_GET_DATA_PAGE R1, R7
0x0000BC4C   LDW R1 [R7 + TASK_DATA_PAGE]
0x0000BC50       MOV R2 R12
0x0000BC54       LI R3 PAGE_SIZE
0x0000BC5C       BL page_copy                    ; copy parent user data page -> child user data page

    ; Clone the fd table and honor open file refcounts.
0x0000BC64       BL page_alloc
0x0000BC6C       CMP R1 0
0x0000BC70       BEQ clone_fail

0x0000BC78       MOV R12 R1

; macro: TASK_SET_FD_TABLE R10, R12       ; set new page as child fd table page
0x0000BC7C   STW R12 [R10 + TASK_FD_TABLE]
0x0000BC80       LI R3 PAGE_SIZE
0x0000BC88       MOV R1 R12
0x0000BC8C       BL mem_zero                     ; clear the child fd table page just in case

; macro: TASK_GET_FD_TABLE R1, R7         ; R1 - parent fd table page
0x0000BC94   LDW R1 [R7 + TASK_FD_TABLE]
0x0000BC98       CMP R1 0
0x0000BC9C       BEQ clone_fd_done                ; if parent has no fd table, skip fd cloning

    ; parent → child copy FIRST
0x0000BCA4       MOV R1 R1        ; parent fd page
0x0000BCA8       MOV R2 R12       ; child fd page
0x0000BCAC       LI R3 PAGE_SIZE
0x0000BCB4       BL page_copy

0x0000BCBC       LI R4 3                      ; fd index loop + 3 stdin/out/err refcount=1, so start at 3

clone_fd_loop:
0x0000BCC4       CMP R4 MAX_FDS
0x0000BCC8       BGE clone_fd_done

0x0000BCD0       SHL R5 R4 2                 ; multiply fd index by 4 to get byte offset
0x0000BCD4       ADD R6 R12 R5               ; R6 = &child_fd_table[i]

0x0000BCD8       LDW R7 [R6]                 ; R7 = file* from child fd table
0x0000BCDC       CMP R7 0
0x0000BCE0       BEQ clone_fd_next           ; if fd slot is empty, skip to next

0x0000BCE8       MOV R1 R7                   ; IMPORTANT: isolate argument
0x0000BCEC       BL file_get                 ; increment refcount of the file* in child fd table

clone_fd_next:
0x0000BCF4       ADD R4 R4 1
0x0000BCF8       B clone_fd_loop

clone_fd_done:
    ; Allocate fresh kernel buffers for the child.
0x0000BD00       BL page_alloc
0x0000BD08       CMP R1 0
0x0000BD0C       BEQ clone_fail

; macro: TASK_SET_KBUF_WR R10, R1        ; set new page as child kernel write buffer
0x0000BD14   STW R1 [R10 + TASK_KBUF_WR_PTR]
0x0000BD18       LI R3 PAGE_SIZE
0x0000BD20       BL mem_zero                     ; zero out the child kernel write buffer

0x0000BD28       BL page_alloc
0x0000BD30       CMP R1 0
0x0000BD34       BEQ clone_fail
; macro: TASK_SET_KBUF_RD R10, R1        ; set new page as child kernel read buffer
0x0000BD3C   STW R1 [R10 + TASK_KBUF_RD_PTR]
0x0000BD40       LI R3 PAGE_SIZE
0x0000BD48       BL mem_zero                     ; zero out the child kernel read buffer

    ; Allocate and initialize the child's kernel stack.
0x0000BD50       BL page_alloc
0x0000BD58       CMP R1 0
0x0000BD5C       BEQ clone_fail
0x0000BD64       MOV R12 R1
; macro: TASK_SET_KSTACK_PAGE R10, R12   ; set new page as child kernel stack page
0x0000BD68   STW R12 [R10 + TASK_KSTACK_PAGE]
0x0000BD6C       LI R3 PAGE_SIZE
0x0000BD74       ADD R12 R12 R3                  ; R12 = child kernel stack top


    ; Copy the current kernel trapframe into the child's new kernel stack.
    ; task_clone_current has one saved return address below the trapframe, so
    ; recover the trapframe from the balanced current SP instead of R8, which
    ; was reused for the code-page count above. eto pizdec nado decompose clone.
    ; issue is fixed by friend - it found SP is in balance here
    ; so SP+4 is what was in R8 here
0x0000BD78       MOV R1 SP
0x0000BD7C       ADD R1 R1 4                   ; R1 = parent trapframe base
0x0000BD80       MOV R6 R12
0x0000BD84       LI R5 80                    ; trapframe size in bytes
0x0000BD8C       SUB R6 R6 R5               ; R6 = child trapframe base inside new kernel stack
0x0000BD90       MOV R2 R6
0x0000BD94       LI R3 80
0x0000BD9C       BL page_copy                ; so we copy 80 bytes from SP to R12-80 (child trapframe base)

    ; Return 0 in the child syscall result register.
0x0000BDA4       LI R4 0
0x0000BDAC       STW R4 [R6 + TF_R1]


    ; Preserve the user SP for later trap/schedule bookkeeping.
    ; User SP is already in the trapframe we copied
    ; But we also need to set it in the child's task struct
0x0000BDB0       LDW R4 [R6 + TF_USP]
; macro: TASK_SET_USP R10, R4
0x0000BDB4   STW R4 [R10 + TASK_USP]

    ; Save the child kernel trapframe pointer and make it runnable.
; macro: TASK_SET_KSP R10, R6                    ;R6 = child trapframe base inside new kernel stack
0x0000BDB8   STW R6 [R10 + TASK_KSP]
; macro: TASK_SET_RESUME R10, RESUME_TRAP
0x0000BDBC   LI R1 RESUME_TRAP
0x0000BDC4   STW R1 [R10 + TASK_RESUME]
; macro: TASK_SET_WAIT R10, WAIT_NONE
0x0000BDC8   LI R1 WAIT_NONE
0x0000BDD0   STW R1 [R10 + TASK_WAIT]
; macro: TASK_SET_STATE R10, TASK_READY
0x0000BDD4   LI R1 TASK_READY
0x0000BDDC   STW R1 [R10 + TASK_STATE]

0x0000BDE0       MOV R1 R10          ; return child task pointer

0x0000BDE4       POP LR
0x0000BDE8       RET

clone_fail:
0x0000BDEC       CMP R10 0
0x0000BDF0       BEQ clone_fail_return
0x0000BDF8       MOV R1 R10
0x0000BDFC       BL task_destroy
clone_fail_return:
0x0000BE04       LI R1 0
0x0000BE0C       POP LR
0x0000BE10       RET

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

0x0000BE14       PUSH LR
0x0000BE18       push R12 ; preserve R12 which we use for temporary storage in this function
0x0000BE1C       mov  R12 R1 ; R12 = task pointer

; macro: TASK_GET_PTBR R2, R1
0x0000BE20   LDW R2 [R1 + TASK_PTBR]
0x0000BE24       CMP R2 0
0x0000BE28       BEQ td_skip_ptbr    ; if task has no page table, it also has no resources to free, so skip to clearing slot and returning

0x0000BE30       MOV R1 R2
0x0000BE34       BL page_put        ; put-free process page table

td_skip_ptbr:

; macro: TASK_GET_USTACK_PAGE R2, R12
0x0000BE3C   LDW R2 [R12 + TASK_USTACK_PAGE]
0x0000BE40       CMP R2 0
0x0000BE44       BEQ td_skip_ustack  ; if task has no user stack page, it also has no kernel stack page, fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000BE4C       MOV R1 R2
0x0000BE50       BL page_put        ; put-free user stack page

td_skip_ustack:

; macro: TASK_GET_KSTACK_PAGE R2, R12
0x0000BE58   LDW R2 [R12 + TASK_KSTACK_PAGE]
0x0000BE5C       CMP R2 0
0x0000BE60       BEQ td_skip_kstack  ; if task has no kernel stack page, it also has no fd table, user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000BE68       MOV R1 R2
0x0000BE6C       BL page_put        ; put-free kernel stack page

td_skip_kstack:

; macro: TASK_GET_FD_TABLE R2, R12
0x0000BE74   LDW R2 [R12 + TASK_FD_TABLE]
0x0000BE78       CMP R2 0
0x0000BE7C       BEQ td_skip_fd    ; if task has no fd table page, it also has no user buffers or kernel buffers to free, so skip to those and move to clearing slot and returning
0x0000BE84       MOV R1 R2
0x0000BE88       BL page_put        ; put-free fd table page

td_skip_fd:

; macro: TASK_GET_KBUF_WR R2, R12
0x0000BE90   LDW R2 [R12 + TASK_KBUF_WR_PTR]
0x0000BE94       CMP R2 0
0x0000BE98       BEQ td_skip_kwr   ; if task has no kernel write buffer page, it may still have kernel read buffer and user data page to free, but it has no user buffers to free because user buffers are allocated and mapped together in one page and there is no way to have user buffers without having kernel write buffer because we allocate kernel write buffer first before allocating and mapping user buffers in task_create, so if there is no kernel write buffer we can skip freeing user buffers and just move to checking and freeing kernel read buffer and user data page if they exist and then move to clearing slot and returning
0x0000BEA0       MOV R1 R2
0x0000BEA4       BL page_put       ; put free KBUF_WR Page

td_skip_kwr:

; macro: TASK_GET_KBUF_RD R2, R12
0x0000BEAC   LDW R2 [R12 + TASK_KBUF_RD_PTR]
0x0000BEB0       CMP R2 0
0x0000BEB4       BEQ td_skip_krd  ; if task has no kernel read buffer page, it may still have user data page to free, but it has no user buffers to free for the same reason as in td_skip_kwr, so if there is no kernel read buffer we can skip freeing user buffers and just move to checking and freeing user data page if it exists and then move to clearing slot and returning
0x0000BEBC       MOV R1 R2
0x0000BEC0       BL page_put       ; put free KBUF_RD Page

td_skip_krd:

; macro: TASK_GET_DATA_PAGE R2, R12
0x0000BEC8   LDW R2 [R12 + TASK_DATA_PAGE]
0x0000BECC       CMP R2 0
0x0000BED0       BEQ td_skip_code
0x0000BED8       MOV R1 R2
0x0000BEDC       BL page_put        ; put-free user data page

td_skip_code:

; macro: TASK_GET_CODE_PAGE R2, R12
0x0000BEE4   LDW R2 [R12 + TASK_CODE_PAGE]
0x0000BEE8       CMP R2 0
0x0000BEEC       BEQ td_done

0x0000BEF4       MOV R1 R2
0x0000BEF8       BL pages_free_table ;codepage (tab+pages)

    ;BL page_put        ; put-free user code page

td_done:

0x0000BF00       MOV R1 R12
0x0000BF04       LI  R3 TASK_SIZE
0x0000BF0C       BL  mem_zero    ; clear the whole task slot for clean slate,
                    ;this also clears the state to TASK_DEAD which
                    ; is important to make sure scheduler won't schedule
                    ; this slot anymore and also to make sure task_create
                    ; can reuse this slot for a new task in the future

0x0000BF14       POP R12         ; restore R12
0x0000BF18       POP LR
0x0000BF1C       RET

;================================================================
; Closes all open file descriptors of a task by calling file_free on each of them.
; in R1 = task*
; output none
;================================================================

task_close_fds:

0x0000BF20       PUSH LR
0x0000BF24       PUSH R8
0x0000BF28       PUSH R9
0x0000BF2C       PUSH R10
0x0000BF30       PUSH R11
0x0000BF34       PUSH R12

; macro: TASK_GET_FD_TABLE R4, R1
0x0000BF38   LDW R4 [R1 + TASK_FD_TABLE]
0x0000BF3C       MOV R12 R4

0x0000BF40       LI R5 3              ; skip stdin/out/err
0x0000BF48       MOV R11 R5

fd_loop:

0x0000BF4C       CMP R11 MAX_FDS
0x0000BF50       BGE fd_done         ; if we processed all fd slots, we are done

0x0000BF58       SHL R6 R11 2
0x0000BF5C       ADD R10 R12 R6      ; R10 = &fd_table[fd]

0x0000BF60       LDW R8 [R10]
0x0000BF64       CMP R8 0
0x0000BF68       BEQ fd_next         ; if fd slot is empty, skip to next

0x0000BF70       MOV R1 R8
0x0000BF74       BL file_free
0x0000BF7C       LI R9 0
0x0000BF84       STW R9 [R10]        ; mark fd slot as free in task's fd table

fd_next:
0x0000BF88       ADD R11 R11 1
0x0000BF8C       B fd_loop

fd_done:
0x0000BF94       POP R12
0x0000BF98       POP R11
0x0000BF9C       POP R10
0x0000BFA0       POP R9
0x0000BFA4       POP R8
0x0000BFA8       POP LR
0x0000BFAC       RET

;================================================================
; Reclaim zombie tasks from a safe stack.
; Must only be called by a live task; it never destroys CURRENT_TASK.
;================================================================
task_reap_zombies:
0x0000BFB0       PUSH LR
0x0000BFB4       PUSH R8
0x0000BFB8       PUSH R9
0x0000BFBC       PUSH R10

; macro: GET_CURR_TASK_IDX R10
0x0000BFC0   LI R1 CURRENT_TASK
0x0000BFC8   LDW R10 [R1]
0x0000BFCC       LI R8 0

task_reap_loop:
0x0000BFD4       CMP R8 MAX_TASKS
0x0000BFD8       BGE task_reap_done

0x0000BFE0       CMP R8 R10
0x0000BFE4       BEQ task_reap_next

; macro: GET_TASK_PTR R9, R8
0x0000BFEC   LI R1 TASK_SIZE
0x0000BFF4   MUL R3 R8 R1
0x0000BFF8   LI R9 tasks
0x0000C000   ADD R9 R9 R3
; macro: TASK_GET_STATE R1, R9
0x0000C004   LDW R1 [R9 + TASK_STATE]
0x0000C008       CMP R1 TASK_ZOMBIE
0x0000C00C       BNE task_reap_next

0x0000C014       PUSH R8
0x0000C018       MOV R1 R9
0x0000C01C       BL task_destroy
0x0000C024       POP R8

task_reap_next:
0x0000C028       ADD R8 R8 1
0x0000C02C       B task_reap_loop

task_reap_done:
0x0000C034       POP R10
0x0000C038       POP R9
0x0000C03C       POP R8
0x0000C040       POP LR
0x0000C044       RET

; ----------------------------------
; task_alloc
;
; returns:
;   R1 = task*
;   R1 = 0 if full
; ----------------------------------

task_alloc:

0x0000C048       LI R1 tasks
0x0000C050       LI R2 MAX_TASKS

task_alloc_loop:

; macro: TASK_GET_STATE R3, R1                   ; load task state into R3
0x0000C058   LDW R3 [R1 + TASK_STATE]

0x0000C05C       CMP R3 TASK_DEAD                        ; check if this slot is free (0-dead)
0x0000C060       BEQ task_alloc_found

0x0000C068       ADD R1 R1 TASK_SIZE                     ; move to next task slot

0x0000C06C       SUB R2 R2 1
0x0000C070       BNE task_alloc_loop

; no free tasks slots

0x0000C078       LI R1 0
0x0000C080       RET

task_alloc_found:                           ;R1 points to free task slot

0x0000C084       RET


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
0x0000C090       PUSH R2

0x0000C094       LI R2 0
0x0000C09C       STW R2 [R1 + MUTEX_OWNER]      ; owner = NULL
0x0000C0A0       STW R2 [R1 + MUTEX_WAITQ]      ; waitq = 0 (empty)

0x0000C0A4       POP R2
0x0000C0A8       RET

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

0x0000C0AC       PUSH LR
0x0000C0B0       PUSH R8
0x0000C0B4       PUSH R9
0x0000C0B8       PUSH R10

0x0000C0BC       MOV R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000C0C0   LI R1 CURRENT_TASK
0x0000C0C8   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000C0CC   LI R1 TASK_SIZE
0x0000C0D4   MUL R3 R9 R1
0x0000C0D8   LI R9 tasks
0x0000C0E0   ADD R9 R9 R3

mutex_lock_retry:
    ; Check if mutex is already locked
0x0000C0E4       LDW R10 [R8 + MUTEX_OWNER]
0x0000C0E8       CMP R10 0
0x0000C0EC       BEQ mutex_lock_acquire      ; if unlocked, acquire it

    ; this Mutex is locked by someone else - block
    ; Add current task to mutex wait queue
0x0000C0F4       MOV R1 R8
0x0000C0F8       ADD R1 R1 MUTEX_WAITQ

0x0000C0FC       LI R2 WAIT_MUTEX
0x0000C104       LI R3 TASK_WAIT_MUTEX
0x0000C10C       BL waitq_prepare_sleep

    ; Re-check if mutex became available while preparing sleep
0x0000C114       LDW R10 [R8 + MUTEX_OWNER]
0x0000C118       CMP R10 0
0x0000C11C       BEQ mutex_lock_wake

    ; Still locked - go to sleep
0x0000C124       BL waitq_sleep_current

    ; Woken up - try to acquire again
0x0000C12C       B mutex_lock_retry

mutex_lock_wake:
    ; Mutex became available, cancel sleep and acquire
0x0000C134       MOV R1 R8
0x0000C138       ADD R1 R1 MUTEX_WAITQ
0x0000C13C       BL waitq_cancel_sleep_current

0x0000C144       B mutex_lock_retry

mutex_lock_acquire:
    ; Disable interrupts to prevent race conditions
0x0000C14C       DISABLEINT

    ; Double-check it's still unlocked
0x0000C150       LDW R10 [R8 + MUTEX_OWNER]
0x0000C154       CMP R10 0
0x0000C158       BNE mutex_lock_race

    ; Set owner to current task
0x0000C160       STW R9 [R8 + MUTEX_OWNER]

    ; Re-enable interrupts
0x0000C164       ENABLEINT

0x0000C168       POP R10
0x0000C16C       POP R9
0x0000C170       POP R8
0x0000C174       POP LR
0x0000C178       RET

mutex_lock_race:
    ; Someone else acquired it while interrupts were disabled
0x0000C17C       ENABLEINT
0x0000C180       B mutex_lock_retry


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
0x0000C188       PUSH LR
0x0000C18C       PUSH R8
0x0000C190       PUSH R9
0x0000C194       PUSH R10

0x0000C198       MOV  R8 R1                  ; save mutex pointer
; macro: GET_CURR_TASK_IDX R9
0x0000C19C   LI R1 CURRENT_TASK
0x0000C1A4   LDW R9 [R1]
; macro: GET_TASK_PTR R9, R9        ; R9 = current task*
0x0000C1A8   LI R1 TASK_SIZE
0x0000C1B0   MUL R3 R9 R1
0x0000C1B4   LI R9 tasks
0x0000C1BC   ADD R9 R9 R3

    ; Verify ownership
0x0000C1C0       LDW  R10 [R8 + MUTEX_OWNER]
0x0000C1C4       CMP  R10 R9
0x0000C1C8       BNE  mutex_unlock_error     ; Not owner - error!

    ; Release the mutex
0x0000C1D0       LI  R10 0
0x0000C1D8       STW R10 [R8 + MUTEX_OWNER]

    ; Wake one waiting task (if someone is waiting)
    ; waky next one (of any waiting)
0x0000C1DC       MOV R1 R8
0x0000C1E0       ADD R1 R1 MUTEX_WAITQ
0x0000C1E4       BL waitq_wake_one

mutex_unlock_done:
0x0000C1EC       POP R10
0x0000C1F0       POP R9
0x0000C1F4       POP R8
0x0000C1F8       POP LR
0x0000C1FC       RET

mutex_unlock_error:
    ; Not owner - ignore (or panic)
0x0000C200       POP R10
0x0000C204       POP R9
0x0000C208       POP R8
0x0000C20C       POP LR
0x0000C210       RET

; ================================================================
; waitq_wake_one - Wake exactly one task from the wait queue
; R1 = wait queue pointer
; ================================================================
waitq_wake_one:
0x0000C214       PUSH LR
0x0000C218       PUSH R8
0x0000C21C       PUSH R9
0x0000C220       PUSH R10
0x0000C224       PUSH R11

0x0000C228       MOV R8 R1                  ; wait queue pointer
0x0000C22C       LDW R9 [R8 + WQ_MASK]      ; current wait queue mask

0x0000C230       CMP R9 0
0x0000C234       BEQ waitq_wake_one_done    ; No waiters

    ; Find the first waiting task
0x0000C23C       LI R10 0                   ; task index

waitq_wake_one_find:
0x0000C244       CMP R10 MAX_TASKS
0x0000C248       BGE waitq_wake_one_done

0x0000C250       LI R11 1
0x0000C258       SHL R11 R11 R10            ; bit for this task
0x0000C25C       AND R2 R9 R11
0x0000C260       CMP R2 0
0x0000C264       BNE waitq_wake_one_found

0x0000C26C       ADD R10 R10 1
0x0000C270       B waitq_wake_one_find

waitq_wake_one_found:
    ; Clear this task's bit from the wait queue
0x0000C278       NOT R11 R11
0x0000C27C       AND R9 R9 R11
0x0000C280       STW R9 [R8 + WQ_MASK]

    ; Wake this task
; macro: GET_TASK_PTR R5, R10
0x0000C284   LI R1 TASK_SIZE
0x0000C28C   MUL R3 R10 R1
0x0000C290   LI R5 tasks
0x0000C298   ADD R5 R5 R3
; macro: TASK_SET_STATE R5, TASK_READY
0x0000C29C   LI R1 TASK_READY
0x0000C2A4   STW R1 [R5 + TASK_STATE]
; macro: TASK_SET_WAIT R5, WAIT_NONE
0x0000C2A8   LI R1 WAIT_NONE
0x0000C2B0   STW R1 [R5 + TASK_WAIT]

waitq_wake_one_done:
0x0000C2B4       POP R11
0x0000C2B8       POP R10
0x0000C2BC       POP R9
0x0000C2C0       POP R8
0x0000C2C4       POP LR
0x0000C2C8       RET

; ================================================================
; CONSOLE MUTEX WRAPPER FUNCTIONS
; ================================================================

console_lock:
0x0000C2CC       PUSH LR
0x0000C2D0       LI R1 console_mutex
0x0000C2D8       BL mutex_lock
0x0000C2E0       POP LR
0x0000C2E4       RET

console_unlock:
0x0000C2E8       PUSH LR
0x0000C2EC       LI R1 console_mutex
0x0000C2F4       BL mutex_unlock
0x0000C2FC       POP LR
0x0000C300       RET

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
0x0000C304       PUSH LR
0x0000C308       PUSH R6
0x0000C30C       PUSH R7
0x0000C310       PUSH R8
0x0000C314       PUSH R9

    ;------------------------------------
    ; Fill BMI packet
    ;------------------------------------
0x0000C318       LI  R6 BMI_BUF_WRITE

0x0000C320       STH R1 [R6 + BMI_HDR_OPCODE]

0x0000C324       LI  R7 0
0x0000C32C       STH R7 [R6 + BMI_HDR_FLAGS]

0x0000C330       STW R4 [R6 + BMI_HDR_NAMESPACE]
0x0000C334       STW R3 [R6 + BMI_HDR_PAYLOAD_LEN]

    ; Copy payload

0x0000C338       ADD R7 R6 BMI_HDR_SIZEOF

0x0000C33C       MOV R1 R7          ; dst
0x0000C340       MOV R2 R2          ; src
0x0000C344       MOV R3 R3          ; len

0x0000C348       BL memcpy

    ;------------------------------------
    ; Ring doorbell
    ;------------------------------------

0x0000C350       LI  R6 BMI_REG_BASE

0x0000C358       LI  R7 BMI_READY
0x0000C360       STW R7 [R6 + BMI_STATUS]

0x0000C364       LI  R7 1
0x0000C36C       STW R7 [R6 + BMI_DOORBELL]

wait_reply:

0x0000C370       LDW R7 [R6 + BMI_STATUS]

    ;DEBUG 2

0x0000C374       CMP R7 BMI_DONE
0x0000C378       BEQ bmi_call_done

0x0000C380       CMP R7 BMI_ERROR
0x0000C384       BEQ bmi_call_error

0x0000C38C       B wait_reply

bmi_call_done:

    ;----------------------------------------
    ; Read BMI reply packet
    ;----------------------------------------

0x0000C394       LI  R8 BMI_BUF_READ

0x0000C39C       LDH R1 [R8 + BMI_HDR_OPCODE]
0x0000C3A0       LDH R2 [R8 + BMI_HDR_FLAGS]
0x0000C3A4       LDW R3 [R8 + BMI_HDR_NAMESPACE]
0x0000C3A8       LDW R4 [R8 + BMI_HDR_PAYLOAD_LEN]

    ; R8 + BMI_HDR_SIZEOF points to reply payload


0x0000C3AC       LDW R1 [R6 + BMI_REPLY]

    ; reset state

0x0000C3B0       LI R7 BMI_IDLE
0x0000C3B8       STW R7 [R6 + BMI_STATUS]

0x0000C3BC       POP R9
0x0000C3C0       POP R8
0x0000C3C4       POP R7
0x0000C3C8       POP R6
0x0000C3CC       POP LR
0x0000C3D0       RET

bmi_call_error:
0x0000C3D4       LI R1 -1
0x0000C3DC       LI R7 BMI_IDLE
0x0000C3E4       STW R7 [R6 + BMI_STATUS]

0x0000C3E8       POP R9
0x0000C3EC       POP R8
0x0000C3F0       POP R7
0x0000C3F4       POP R6
0x0000C3F8       POP LR

0x0000C3FC       RET



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

.ORG 0xA0000
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

; /bin/cat, 4707 bytes
    .ASCIIZ "/bin/cat"
    .SPACE 115
    .ASCIIZ "00000011143"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4707 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006, 0x00001007, 0x00001008
    .WORD 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000, 0x0D00030D, 0x0100018C
    .WORD 0x02000188, 0x00820189, 0x00000408, 0x421A1200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06
    .WORD 0x08000000, 0x0000040A, 0x41E61500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x00000102, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x419A1200, 0x0B000004, 0x0C000181
    .WORD 0x00000182, 0x01000F03, 0x00000000, 0x32443000, 0x01000004, 0x00800187, 0x00000407, 0x41821300
    .WORD 0x00000004, 0x00010F01, 0x0C000000, 0x07000182, 0x00000183, 0x323C3000, 0x00000004, 0x413A0500
    .WORD 0x0B000004, 0x00000181, 0x32543000, 0x0A810004, 0x0000020A, 0x41020500, 0x00000004, 0x424F0F01
    .WORD 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000
    .WORD 0x00000004, 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A
    .WORD 0x41020500, 0x00000004, 0x01000F02, 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x423A0F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x00000000, 0x41E60500, 0x73750004, 0x3A656761
    .WORD 0x74616320, 0x6C696620, 0x2E2E2065, 0x63000A2E, 0x203A7461, 0x6E6E6163, 0x6F20746F, 0x206E6570
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

; /bin/echo, 4426 bytes
    .ASCIIZ "/bin/echo"
    .SPACE 114
    .ASCIIZ "00000010512"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4426 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x00000000, 0x0000100F, 0x00001008, 0x00001009
    .WORD 0x0100100A, 0x02000188, 0x00000189, 0x00010F0A, 0x09000000, 0x0B84018B, 0x0800020B, 0x0000040A
    .WORD 0x412E1500, 0x0B000004, 0x00002201, 0x30583000, 0x0A810004, 0x0B84020A, 0x0800020B, 0x0000040A
    .WORD 0x411E1500, 0x00000004, 0x3FF40F01, 0x00000004, 0x30583000, 0x00000004, 0x40DA0500, 0x00000004
    .WORD 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x00000F01, 0x00000000, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x0000110F, 0x00003100, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/fc, 4603 bytes
    .ASCIIZ "/bin/fc"
    .SPACE 116
    .ASCIIZ "00000010773"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4603 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006, 0x00001007, 0x00001008
    .WORD 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408, 0x41B21200, 0x00000004
    .WORD 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x418E1500, 0x0A000004, 0x02820182
    .WORD 0x09020C02, 0x02000202, 0x00002201, 0x00010F02, 0x00000000, 0x324C3000, 0x01000004, 0x0080018B
    .WORD 0x0000040B, 0x41421200, 0x0B000004, 0x00000181, 0x32543000, 0x0A810004, 0x0000020A, 0x40EE0500
    .WORD 0x00000004, 0x41E60F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x41F90F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06
    .WORD 0x0A810000, 0x0000020A, 0x40EE0500, 0x06000004, 0x00000181, 0x0000110B, 0x0000110A, 0x00001109
    .WORD 0x00001108, 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x41D20F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x00010F01, 0x00000000, 0x418E0500, 0x73750004, 0x3A656761, 0x20636620, 0x656C6966
    .WORD 0x2E2E2E20, 0x6366000A, 0x6163203A, 0x746F6E6E, 0x65726320, 0x20657461, 0x00000A00, 0x00000000

; /bin/ls, 4879 bytes
    .ASCIIZ "/bin/ls"
    .SPACE 116
    .ASCIIZ "00000011417"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4879 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006, 0x00001007, 0x00001008
    .WORD 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x01000F03, 0x0D030000, 0x0D00030D, 0x0100018C
    .WORD 0x02000188, 0x00820189, 0x00000408, 0x42AE1200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06
    .WORD 0x08000000, 0x0000040A, 0x427A1500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x00001001, 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x42F80F01, 0x00000004, 0x30583000
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x43080F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x00001101
    .WORD 0x00000F02, 0x00000000, 0x324C3000, 0x01000004, 0x0080018B, 0x0000040B, 0x422E1200, 0x0B000004
    .WORD 0x0C000181, 0x00000182, 0x004C0F03, 0x00000000, 0x32443000, 0x01000004, 0x00800187, 0x00000407
    .WORD 0x42160600, 0x00CC0004, 0x00000407, 0x42160700, 0x0C080004, 0x0C8C2005, 0x00000201, 0x30583000
    .WORD 0x00820004, 0x00000405, 0x41FE0700, 0x00000004, 0x430D0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x419E0500, 0x0B000004, 0x00000181, 0x32543000
    .WORD 0x0A810004, 0x0000020A, 0x41020500, 0x00000004, 0x42E70F01, 0x00000004, 0x30583000, 0x0A000004
    .WORD 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x3FF60F01, 0x00000004
    .WORD 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x41020500, 0x00000004, 0x01000F02
    .WORD 0x0D020000, 0x0600020D, 0x00000181, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108
    .WORD 0x00001107, 0x00001106, 0x0000110F, 0x00003100, 0x42CE0F01, 0x00000004, 0x30583000, 0x00000004
    .WORD 0x00010F06, 0x00000000, 0x427A0500, 0x73750004, 0x3A656761, 0x20736C20, 0x65726964, 0x726F7463
    .WORD 0x2E2E2079, 0x6C000A2E, 0x63203A73, 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D, 0x65726944
    .WORD 0x726F7463, 0x00203A79, 0x2D2D2D20, 0x00002F00, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/ls1, 4869 bytes
    .ASCIIZ "/bin/ls1"
    .SPACE 115
    .ASCIIZ "00000011405"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4869 bytes, padded to 5120)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006, 0x00001007, 0x00001008
    .WORD 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x004C0F03, 0x0D030000, 0x0D00030D, 0x0100018C
    .WORD 0x02000188, 0x00820189, 0x00000408, 0x42A21200, 0x00000004, 0x00010F0A, 0x00000000, 0x00000F06
    .WORD 0x08000000, 0x0000040A, 0x426E1500, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201
    .WORD 0x00001001, 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x42EC0F01, 0x00000004, 0x30583000
    .WORD 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004, 0x42FC0F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x3FF60F01, 0x00000004, 0x30583000, 0x00000004, 0x00001101
    .WORD 0x39543000, 0x01000004, 0x0080018B, 0x0000040B, 0x42220600, 0x0B000004, 0x0C000181, 0x00000182
    .WORD 0x39F83000, 0x00800004, 0x00000401, 0x420A0600, 0x00000004, 0xFFFF0F02, 0x0200FFFF, 0x00000401
    .WORD 0x420A0600, 0x0C080004, 0x0C8C2205, 0x00000201, 0x30583000, 0x00820004, 0x00000405, 0x41F20700
    .WORD 0x00000004, 0x43010F01, 0x00000004, 0x30583000, 0x00000004, 0x3FF60F01, 0x00000004, 0x30583000
    .WORD 0x00000004, 0x41960500, 0x0B000004, 0x00000181, 0x3A883000, 0x0A810004, 0x0000020A, 0x41020500
    .WORD 0x00000004, 0x42DB0F01, 0x00000004, 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202
    .WORD 0x00002201, 0x30583000, 0x00000004, 0x43030F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06
    .WORD 0x0A810000, 0x0000020A, 0x41020500, 0x00000004, 0x004C0F03, 0x0D030000, 0x0600020D, 0x00000181
    .WORD 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106, 0x0000110F
    .WORD 0x00003100, 0x42C20F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x00000000, 0x426E0500
    .WORD 0x73750004, 0x3A656761, 0x20736C20, 0x65726964, 0x726F7463, 0x2E2E2079, 0x6C000A2E, 0x63203A73
    .WORD 0x6F6E6E61, 0x706F2074, 0x00206E65, 0x202D2D2D, 0x65726944, 0x726F7463, 0x00203A79, 0x2D2D2D20
    .WORD 0x0A002F00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/mkdir, 4596 bytes
    .ASCIIZ "/bin/mkdir"
    .SPACE 113
    .ASCIIZ "00000010764"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4596 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001006, 0x00001007, 0x00001008
    .WORD 0x00001009, 0x0000100A, 0x0100100B, 0x02000188, 0x00820189, 0x00000408, 0x41A61200, 0x00000004
    .WORD 0x00010F0A, 0x00000000, 0x00000F06, 0x08000000, 0x0000040A, 0x41821500, 0x0A000004, 0x02820182
    .WORD 0x09020C02, 0x02000202, 0x00002201, 0x00000F02, 0x00000000, 0x325C3000, 0x01000004, 0x0080018B
    .WORD 0x0000040B, 0x41361200, 0x0A810004, 0x0000020A, 0x40EE0500, 0x00000004, 0x41DC0F01, 0x00000004
    .WORD 0x30583000, 0x0A000004, 0x02820182, 0x09020C02, 0x02000202, 0x00002201, 0x30583000, 0x00000004
    .WORD 0x41F20F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F06, 0x0A810000, 0x0000020A, 0x40EE0500
    .WORD 0x06000004, 0x00000181, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x00001107, 0x00001106
    .WORD 0x0000110F, 0x00003100, 0x41C60F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F01, 0x00000000
    .WORD 0x41820500, 0x73750004, 0x3A656761, 0x646B6D20, 0x64207269, 0x2E207269, 0x000A2E2E, 0x69646B6D
    .WORD 0x63203A72, 0x6F6E6E61, 0x72632074, 0x65746165, 0x000A0020, 0x00000000, 0x00000000, 0x00000000

; /bin/print, 4546 bytes
    .ASCIIZ "/bin/print"
    .SPACE 113
    .ASCIIZ "00000010702"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (4546 bytes, padded to 4608)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00001008, 0x00001009, 0x0000100A
    .WORD 0x0100100B, 0x02000188, 0x00820189, 0x00000408, 0x41621200, 0x09040004, 0x01002201, 0x0000018A
    .WORD 0x00000F02, 0x00000000, 0x00000F03, 0x00000000, 0x00000F04, 0x09080000, 0x01002201, 0x00830182
    .WORD 0x00000408, 0x41460600, 0x090C0004, 0x01002201, 0x00840183, 0x00000408, 0x41460600, 0x09100004
    .WORD 0x01002201, 0x00850184, 0x00000408, 0x41460600, 0x09140004, 0x01002201, 0x00860185, 0x00000408
    .WORD 0x41460600, 0x0A000004, 0x00000181, 0x3C543000, 0x00000004, 0x00000F01, 0x00000000, 0x417A0500
    .WORD 0x00000004, 0x41920F01, 0x00000004, 0x30583000, 0x00000004, 0x00010F01, 0x00000000, 0x0000110B
    .WORD 0x0000110A, 0x00001109, 0x00001108, 0x0000110F, 0x73753100, 0x3A656761, 0x69727020, 0x4620746E
    .WORD 0x414D524F, 0x415B2054, 0x5D314752, 0x52415B20, 0x205D3247, 0x4752415B, 0x5B205D33, 0x34475241
    .WORD 0x0000005D, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000

; /bin/sh, 5963 bytes
    .ASCIIZ "/bin/sh"
    .SPACE 116
    .ASCIIZ "00000013513"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (5963 bytes, padded to 6144)
    .WORD 0x22010D00, 0x02020D84, 0x0F030000, 0x00000000, 0x10010000, 0x10020000, 0x10030000, 0x30000000
    .WORD 0x00043654, 0x11030000, 0x11020000, 0x11010000, 0x30000000, 0x000440AE, 0x0F010000, 0x00000000
    .WORD 0x10010000, 0x0F010000, 0x00000001, 0x400F0000, 0x11010000, 0x40010000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800
    .WORD 0x01830900, 0x40040000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x0F080000, 0x00043FF8, 0x23010800, 0x0F010000, 0x00000001, 0x01820800, 0x0F030000, 0x00000001
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
    .WORD 0x31000000, 0x40120000, 0x31000000, 0x400E0000, 0x31000000, 0x400D0000, 0x31000000, 0x40100000
    .WORD 0x31000000, 0x400F0000, 0x31000000, 0x40010000, 0x05000000, 0x00043290, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x100F0000, 0x02010187
    .WORD 0x0F020000, 0xFFFFFFF8, 0x09010102, 0x01850100, 0x0F040000, 0x00000000, 0x040400B0, 0x15000000
    .WORD 0x00043560, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203, 0x22030208
    .WORD 0x04030080, 0x07000000, 0x0004353C, 0x22030204, 0x04030500, 0x15000000, 0x00043548, 0x02040481
    .WORD 0x05000000, 0x000434F8, 0x0F030000, 0x00000001, 0x25030208, 0x22010200, 0x05000000, 0x000435E0
    .WORD 0x01810500, 0x400C0000, 0x04010080, 0x12000000, 0x000435D8, 0x0F040000, 0x00000000, 0x040400B0
    .WORD 0x15000000, 0x000435D8, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403, 0x02020203
    .WORD 0x22030208, 0x04030080, 0x06000000, 0x000435BC, 0x02040481, 0x05000000, 0x0004357C, 0x25010200
    .WORD 0x25050204, 0x0F030000, 0x00000001, 0x25030208, 0x05000000, 0x000435E0, 0x0F010000, 0x00000000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x04010080, 0x06000000, 0x0004364C, 0x0F040000, 0x00000000
    .WORD 0x040400B0, 0x15000000, 0x0004364C, 0x0F020000, 0x00043298, 0x0F030000, 0x0000000C, 0x08030403
    .WORD 0x02020203, 0x22030200, 0x04030100, 0x06000000, 0x00043640, 0x02040481, 0x05000000, 0x00043600
    .WORD 0x0F030000, 0x00000000, 0x25030208, 0x110F0000, 0x31000000, 0x100F0000, 0x0F010000, 0x00043298
    .WORD 0x0F030000, 0x00000030, 0x04030080, 0x06000000, 0x00043690, 0x0F020000, 0x00000000, 0x23020100
    .WORD 0x02010181, 0x03030381, 0x05000000, 0x00043668, 0x110F0000, 0x31000000, 0x100F0000, 0x10050000
    .WORD 0x10060000, 0x10070000, 0x10080000, 0x10090000, 0x100A0000, 0x100B0000, 0x100C0000, 0x01880100
    .WORD 0x01890200, 0x018B0300, 0x018C0400, 0x030D0D05, 0x018A0D00, 0x10050000, 0x10080000, 0x040C0081
    .WORD 0x07000000, 0x0004370C, 0x04090080, 0x15000000, 0x0004370C, 0x0F020000, 0x0000002D, 0x23020800
    .WORD 0x02080881, 0x28090900, 0x02090981, 0x04090080, 0x07000000, 0x0004373C, 0x0F020000, 0x00000030
    .WORD 0x23020800, 0x02080881, 0x0F020000, 0x00000000, 0x23020800, 0x05000000, 0x000437DC, 0x0F040000
    .WORD 0x00000000, 0x01850900, 0x1606050B, 0x1707090B, 0x040B0090, 0x06000000, 0x00043768, 0x020707B0
    .WORD 0x05000000, 0x00043788, 0x04070089, 0x14000000, 0x00043780, 0x020707B0, 0x05000000, 0x00043788
    .WORD 0x0307078A, 0x020707C1, 0x23070A00, 0x020A0A81, 0x02040481, 0x01890600, 0x04090080, 0x07000000
    .WORD 0x00043744, 0x030A0A81, 0x04040080, 0x06000000, 0x000437D0, 0x20020A00, 0x23020800, 0x02080881
    .WORD 0x030A0A81, 0x03040481, 0x05000000, 0x000437A8, 0x0F020000, 0x00000000, 0x23020800, 0x11010000
    .WORD 0x11050000, 0x020D0D05, 0x110C0000, 0x110B0000, 0x110A0000, 0x11090000, 0x11080000, 0x11070000
    .WORD 0x11060000, 0x11050000, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x0000000A, 0x0F040000
    .WORD 0x00000001, 0x0F050000, 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000
    .WORD 0x0F030000, 0x00000010, 0x0F040000, 0x00000000, 0x0F050000, 0x00000009, 0x30000000, 0x00043698
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000008, 0x0F040000, 0x00000000, 0x0F050000
    .WORD 0x0000000D, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002
    .WORD 0x0F040000, 0x00000000, 0x0F050000, 0x00000021, 0x30000000, 0x00043698, 0x110F0000, 0x31000000
    .WORD 0x100F0000, 0x0F030000, 0x00000010, 0x0F040000, 0x00000001, 0x0F050000, 0x0000000A, 0x30000000
    .WORD 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x0F030000, 0x00000002, 0x0F040000, 0x00000001
    .WORD 0x0F050000, 0x00000022, 0x30000000, 0x00043698, 0x110F0000, 0x31000000, 0x100F0000, 0x01830100
    .WORD 0x01840200, 0x20020400, 0x23020100, 0x04020080, 0x06000000, 0x00043948, 0x02010181, 0x02040481
    .WORD 0x05000000, 0x00043924, 0x01810300, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x01880100, 0x01810800, 0x0F020000, 0x00000000, 0x40060000, 0x01890100, 0x04010080, 0x12000000
    .WORD 0x000439E0, 0x10090000, 0x0F010000, 0x00000008, 0x30000000, 0x000434D8, 0x11090000, 0x04010080
    .WORD 0x06000000, 0x000439C8, 0x01880100, 0x25090800, 0x0F020000, 0x00000000, 0x25020804, 0x01810800
    .WORD 0x05000000, 0x000439E8, 0x01810900, 0x40070000, 0x0F010000, 0x00000000, 0x05000000, 0x000439E8
    .WORD 0x0F010000, 0x00000000, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000
    .WORD 0x10090000, 0x01880100, 0x01890200, 0x04080080, 0x06000000, 0x00043A60, 0x22010800, 0x01820900
    .WORD 0x0F030000, 0x0000004C, 0x40050000, 0x04010080, 0x06000000, 0x00043A70, 0x040100CC, 0x07000000
    .WORD 0x00043A60, 0x22020804, 0x02020281, 0x25020804, 0x0F010000, 0x00000001, 0x05000000, 0x00043A78
    .WORD 0x0F010000, 0xFFFFFFFF, 0x05000000, 0x00043A78, 0x0F010000, 0x00000000, 0x11090000, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x01880100, 0x04080080, 0x06000000, 0x00043AC4
    .WORD 0x22010800, 0x40070000, 0x01810800, 0x30000000, 0x000435E8, 0x0F010000, 0x00000000, 0x05000000
    .WORD 0x00043ACC, 0x0F010000, 0xFFFFFFFF, 0x11080000, 0x110F0000, 0x31000000, 0x04010080, 0x06000000
    .WORD 0x00043B04, 0x0F020000, 0x00000000, 0x25020104, 0x100F0000, 0x10080000, 0x01880100, 0x11080000
    .WORD 0x110F0000, 0x31000000, 0x04010080, 0x06000000, 0x00043B1C, 0x22010100, 0x31000000, 0x0F010000
    .WORD 0xFFFFFFFF, 0x31000000, 0x100F0000, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043B5C
    .WORD 0x01820100, 0x0F010000, 0x00000001, 0x30000000, 0x00043A88, 0x05000000, 0x00043B64, 0x0F010000
    .WORD 0x00000000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100, 0x030D0DCC
    .WORD 0x01890D00, 0x01810800, 0x30000000, 0x00043954, 0x04010080, 0x06000000, 0x00043C30, 0x01880100
    .WORD 0x01810800, 0x01820900, 0x30000000, 0x000439F8, 0x04010080, 0x06000000, 0x00043C14, 0x0F020000
    .WORD 0xFFFFFFFF, 0x04010200, 0x06000000, 0x00043C30, 0x0201098C, 0x30000000, 0x00043058, 0x22020908
    .WORD 0x04020082, 0x07000000, 0x00043BFC, 0x0F010000, 0x00043C4C, 0x30000000, 0x00043098, 0x0F010000
    .WORD 0x00043C50, 0x30000000, 0x00043098, 0x05000000, 0x00043BA0, 0x01810800, 0x30000000, 0x00043A88
    .WORD 0x0F010000, 0x00000000, 0x05000000, 0x00043C38, 0x0F010000, 0xFFFFFFFF, 0x020D0DCC, 0x11090000
    .WORD 0x11080000, 0x110F0000, 0x31000000, 0x0000002F, 0x0000000A, 0x100F0000, 0x10080000, 0x10090000
    .WORD 0x100A0000, 0x100B0000, 0x100C0000, 0x030D0DD0, 0x25020D00, 0x25030D04, 0x25040D08, 0x25050D0C
    .WORD 0x25060D10, 0x25070D14, 0x25080D18, 0x25090D1C, 0x250A0D20, 0x250B0D24, 0x250C0D28, 0x01880100
    .WORD 0x0F090000, 0x00000000, 0x018A0D00, 0x020B0DAC, 0x20010800, 0x04010080, 0x06000000, 0x00043F10
    .WORD 0x040100A5, 0x07000000, 0x00043D64, 0x02080881, 0x20020800, 0x04020080, 0x06000000, 0x00043F10
    .WORD 0x040200A5, 0x06000000, 0x00043D74, 0x040200F3, 0x06000000, 0x00043E08, 0x040200E4, 0x06000000
    .WORD 0x00043E24, 0x040200E9, 0x06000000, 0x00043E24, 0x040200F8, 0x06000000, 0x00043E54, 0x040200E3
    .WORD 0x06000000, 0x00043E84, 0x040200E2, 0x06000000, 0x00043EA4, 0x040200EF, 0x06000000, 0x00043ED4
    .WORD 0x0F010000, 0x00000025, 0x30000000, 0x00043098, 0x01810200, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043098, 0x05000000, 0x00043F04, 0x0F010000, 0x00000025, 0x30000000
    .WORD 0x00043098, 0x05000000, 0x00043F04, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22010300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x100F0000, 0x10030000, 0x30000000, 0x00043DCC, 0x22020300
    .WORD 0x11030000, 0x110F0000, 0x31000000, 0x0409008B, 0x12000000, 0x00043DF4, 0x0303098B, 0x0F040000
    .WORD 0x00000004, 0x08030304, 0x02030D03, 0x020303E8, 0x31000000, 0x0F040000, 0x00000004, 0x08030904
    .WORD 0x02030A03, 0x31000000, 0x30000000, 0x00043D8C, 0x02090981, 0x30000000, 0x00043F30, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043F74, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043F94, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043D8C, 0x20010100, 0x02090981, 0x30000000, 0x00043098, 0x05000000
    .WORD 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200, 0x30000000, 0x00043FFA, 0x01820100, 0x02090981
    .WORD 0x01810B00, 0x30000000, 0x00043FB4, 0x05000000, 0x00043F04, 0x30000000, 0x00043DAC, 0x01810200
    .WORD 0x30000000, 0x00043FFA, 0x01820100, 0x02090981, 0x01810B00, 0x30000000, 0x00043FD4, 0x05000000
    .WORD 0x00043F04, 0x02080881, 0x05000000, 0x00043CB0, 0x020D0DD0, 0x110C0000, 0x110B0000, 0x110A0000
    .WORD 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x10080000, 0x10090000, 0x01880100
    .WORD 0x30000000, 0x000430D0, 0x01890100, 0x0F010000, 0x00000001, 0x01820800, 0x01830900, 0x30000000
    .WORD 0x0004323C, 0x11090000, 0x11080000, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043810
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x0004383C
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043894
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x100F0000, 0x30000000, 0x00043868
    .WORD 0x01810100, 0x30000000, 0x00043F30, 0x110F0000, 0x31000000, 0x000A0020, 0x00000000, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0100100A, 0x00000188, 0x00000F09, 0x00000000, 0x00000F0A, 0x08000000
    .WORD 0x00AD2002, 0x00000402, 0x403A0700, 0x00000004, 0x00010F0A, 0x08810000, 0x08000208, 0x00802002
    .WORD 0x00000402, 0x40820600, 0x00B00004, 0x00000402, 0x40821200, 0x00B90004, 0x00000402, 0x40821400
    .WORD 0x02B00004, 0x00000302, 0x000A0F03, 0x09030000, 0x09020809, 0x08810209, 0x00000208, 0x403A0500
    .WORD 0x00810004, 0x0000040A, 0x40960700, 0x09000004, 0x09812809, 0x09000209, 0x00000181, 0x0000110A
    .WORD 0x00001109, 0x00001108, 0x0000110F, 0x00003100, 0x0000100F, 0x00010F01, 0x00000000, 0x46220F02
    .WORD 0x00000004, 0x00020F03, 0x00000000, 0x323C3000, 0x00000004, 0x00000F01, 0x00000000, 0x464B0F02
    .WORD 0x00000004, 0x007F0F03, 0x00000000, 0x32443000, 0x00800004, 0x00000401, 0x42921300, 0x01000004
    .WORD 0x00000184, 0x464B0F08, 0x00000004, 0x464B0F09, 0x00000004, 0x00000F0A, 0x04000000, 0x0000040A
    .WORD 0x41921500, 0x080A0004, 0x05000205, 0x008A2006, 0x00000406, 0x41860600, 0x008D0004, 0x00000406
    .WORD 0x41860600, 0x00880004, 0x00000406, 0x416E0600, 0x00FF0004, 0x00000406, 0x416E0600, 0x09000004
    .WORD 0x09812306, 0x00000209, 0x41860500, 0x08000004, 0x00000409, 0x41861300, 0x09810004, 0x00000309
    .WORD 0x41860500, 0x0A810004, 0x0000020A, 0x411A0500, 0x00000004, 0x00000F06, 0x09000000, 0x00002306
    .WORD 0x464B0F07, 0x07000004, 0x00802006, 0x00000406, 0x40B20600, 0x00000004, 0x429A3000, 0x00000004
    .WORD 0x464B0F01, 0x00000004, 0x46260F02, 0x00000004, 0x31183000, 0x00810004, 0x00000401, 0x42920600
    .WORD 0x00000004, 0x326C3000, 0x00800004, 0x00000401, 0x422A0600, 0x00000004, 0x42621200, 0x00000004
    .WORD 0xFFFF0F01, 0x0000FFFF, 0x00000F02, 0x00000000, 0x327C3000, 0x00800004, 0x00000401, 0x427A1200
    .WORD 0x00000004, 0x40B20500, 0x00000004, 0x464B0F01, 0x00000004, 0x46CB0F02, 0x00000004, 0x00000F03
    .WORD 0x00000000, 0x32743000, 0x00000004, 0x462B0F01, 0x00000004, 0x30583000, 0x00000004, 0x0000110F
    .WORD 0x00003100, 0x46370F01, 0x00000004, 0x30583000, 0x00000004, 0x40B20500, 0x00000004, 0x46410F01
    .WORD 0x00000004, 0x30583000, 0x00000004, 0x40B20500, 0x00000004, 0x0000110F, 0x00003100, 0x0000100F
    .WORD 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x0000100C, 0x464B0F08, 0x00000004, 0x464B0F09
    .WORD 0x00000004, 0x00000F0A, 0x00000000, 0x00000F0C, 0x08000000, 0x0080200B, 0x0000040B, 0x45060600
    .WORD 0x00A00004, 0x0000040B, 0x42FA0700, 0x08810004, 0x00000208, 0x42D20500, 0x00880004, 0x0000040A
    .WORD 0x45061500, 0x00000004, 0x46CB0F07, 0x0A000004, 0x06820186, 0x07060C06, 0x07000207, 0x0A812509
    .WORD 0x0000020A, 0x00000F0C, 0x00000000, 0x43320500, 0x08000004, 0x0080200B, 0x0000040B, 0x44FA0600
    .WORD 0x00800004, 0x0000040C, 0x43BA0700, 0x00A00004, 0x0000040B, 0x44DE0600, 0x00A20004, 0x0000040B
    .WORD 0x43920600, 0x00A70004, 0x0000040B, 0x43A60600, 0x00DC0004, 0x0000040B, 0x43FA0600, 0x09000004
    .WORD 0x0881230B, 0x09810208, 0x00000209, 0x43320500, 0x00000004, 0x00220F0C, 0x08810000, 0x00000208
    .WORD 0x43320500, 0x00000004, 0x00270F0C, 0x08810000, 0x00000208, 0x43320500, 0x0C000004, 0x0000040B
    .WORD 0x43E60600, 0x00DC0004, 0x0000040B, 0x43FA0600, 0x09000004, 0x0881230B, 0x09810208, 0x00000209
    .WORD 0x43320500, 0x00000004, 0x00000F0C, 0x08810000, 0x00000208, 0x43320500, 0x08810004, 0x08000208
    .WORD 0x0080200B, 0x0000040B, 0x44FA0600, 0x00EE0004, 0x0000040B, 0x446A0600, 0x00F20004, 0x0000040B
    .WORD 0x447A0600, 0x00F40004, 0x0000040B, 0x448A0600, 0x00DC0004, 0x0000040B, 0x449A0600, 0x00A20004
    .WORD 0x0000040B, 0x44AA0600, 0x00A70004, 0x0000040B, 0x44BA0600, 0x09000004, 0x0881230B, 0x09810208
    .WORD 0x00000209, 0x43320500, 0x00000004, 0x000A0F0B, 0x00000000, 0x44CA0500, 0x00000004, 0x000D0F0B
    .WORD 0x00000000, 0x44CA0500, 0x00000004, 0x00090F0B, 0x00000000, 0x44CA0500, 0x00000004, 0x005C0F0B
    .WORD 0x00000000, 0x44CA0500, 0x00000004, 0x00220F0B, 0x00000000, 0x44CA0500, 0x00000004, 0x00270F0B
    .WORD 0x00000000, 0x44CA0500, 0x09000004, 0x0881230B, 0x09810208, 0x00000209, 0x43320500, 0x00000004
    .WORD 0x00000F0B, 0x09000000, 0x0981230B, 0x08810209, 0x00000208, 0x42D20500, 0x00000004, 0x00000F0B
    .WORD 0x09000000, 0x0000230B, 0x46CB0F07, 0x0A000004, 0x06820186, 0x07060C06, 0x00000207, 0x00000F0B
    .WORD 0x07000000, 0x0000250B, 0x0000110C, 0x0000110B, 0x0000110A, 0x00001109, 0x00001108, 0x0000110F
    .WORD 0x00003100, 0x0000100F, 0x00001008, 0x00001009, 0x0000100A, 0x0000100B, 0x464B0F08, 0x00000004
    .WORD 0x46CB0F09, 0x00000004, 0x00000F0A, 0x08000000, 0x00A0200B, 0x0000040B, 0x42FA0700, 0x00000004
    .WORD 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208, 0x456E0500, 0x08000004, 0x0080200B, 0x0000040B
    .WORD 0x45060600, 0x00880004, 0x0000040A, 0x45061500, 0x09000004, 0x09842508, 0x0A810209, 0x0800020A
    .WORD 0x0080200B, 0x0000040B, 0x45060600, 0x00A00004, 0x0000040B, 0x45E60600, 0x08810004, 0x00000208
    .WORD 0x43320500, 0x00000004, 0x00000F0B, 0x08000000, 0x0881230B, 0x00000208, 0x42D20500, 0x00000004
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

; /lib/libc.inc, 45176 bytes
    .ASCIIZ "/lib/libc.inc"
    .SPACE 110
    .ASCIIZ "00000130170"
    .SPACE 20
    .ASCIIZ "0"
    .SPACE 354
    ; file data (45176 bytes, padded to 45568)
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
    .WORD 0x0A373120, 0x5551452E, 0x53595320, 0x444D525F, 0x202C5249, 0x38312020, 0x51452E0A, 0x54532055
    .WORD 0x54554F44, 0x2C44465F, 0x0A0A3120, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x6944203B
    .WORD 0x746E6572, 0x72747320, 0x75746375, 0x28206572, 0x6374616D, 0x20736568, 0x6E72656B, 0x64206C65
    .WORD 0x6E696665, 0x6F697469, 0x3B0A296E, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x2E0A3D3D, 0x20555145
    .WORD 0x525F5444, 0x202C4745, 0x20202020, 0x31202020, 0x51452E0A, 0x54442055, 0x5249445F, 0x2020202C
    .WORD 0x20202020, 0x0A0A3220, 0x5551452E, 0x52494420, 0x5F544E45, 0x444F4E49, 0x20202C45, 0x452E0A30
    .WORD 0x44205551, 0x4E455249, 0x49535F54, 0x202C455A, 0x0A342020, 0x5551452E, 0x52494420, 0x5F544E45
    .WORD 0x45505954, 0x2020202C, 0x452E0A38, 0x44205551, 0x4E455249, 0x414E5F54, 0x202C454D, 0x32312020
    .WORD 0x51452E0A, 0x49442055, 0x544E4552, 0x5A49535F, 0x2C464F45, 0x0A363720, 0x3D203B0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x704F203B
    .WORD 0x66206E65, 0x7367616C, 0x3D203B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x41203B0A, 0x73656363, 0x6F6D2073, 0x6D206564, 0x0A6B7361
    .WORD 0x5551452E, 0x415F4F20, 0x4F4D4343, 0x202C4544, 0x30337830, 0x203B0A0A, 0x65636341, 0x6D207373
    .WORD 0x7365646F, 0x51452E0A, 0x5F4F2055, 0x4E4F4452, 0x202C594C, 0x30783020, 0x452E0A30, 0x4F205551
    .WORD 0x4F52575F, 0x2C594C4E, 0x78302020, 0x2E0A3031, 0x20555145, 0x44525F4F, 0x202C5257, 0x30202020
    .WORD 0x0A303278, 0x46203B0A, 0x20656C69, 0x61657263, 0x6E6F6974, 0x62202F20, 0x76616865, 0x20726F69
    .WORD 0x67616C66, 0x452E0A73, 0x4F205551, 0x4552435F, 0x2C455441, 0x78302020, 0x2E0A3130, 0x20555145
    .WORD 0x58455F4F, 0x202C4C43, 0x30202020, 0x0A323078, 0x5551452E, 0x545F4F20, 0x434E5552, 0x2020202C
    .WORD 0x34307830, 0x51452E0A, 0x5F4F2055, 0x45505041, 0x202C444E, 0x30783020, 0x0A0A0A38, 0x3D3D3D3B
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x735F203B, 0x74726174, 0x50202D20, 0x72676F72, 0x65206D61
    .WORD 0x7972746E, 0x696F7020, 0x3B0A746E, 0x3A4E4920, 0x72612020, 0x61206367, 0x535B2074, 0x202C5D50
    .WORD 0x76677261, 0x20746120, 0x2B50535B, 0x3B0A5D34, 0x54554F20, 0x654E203A, 0x20726576, 0x75746572
    .WORD 0x20736E72, 0x6163202D, 0x20736C6C, 0x5F535953, 0x54495845, 0x74697720, 0x616D2068, 0x73276E69
    .WORD 0x74657220, 0x206E7275, 0x756C6176, 0x3D3B0A65, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x735F0A3D
    .WORD 0x74726174, 0x20200A3A, 0x444C2020, 0x31522057, 0x50535B20, 0x2020205D, 0x20202020, 0x3B202020
    .WORD 0x67726120, 0x20200A63, 0x44412020, 0x32522044, 0x20505320, 0x20202034, 0x20202020, 0x3B202020
    .WORD 0x67726120, 0x20200A76, 0x494C2020, 0x20335220, 0x20202030, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x766E6520, 0x203D2070, 0x4C4C554E, 0x2020200A, 0x53555020, 0x31522048, 0x2020200A, 0x53555020
    .WORD 0x32522048, 0x2020200A, 0x53555020, 0x33522048, 0x2020200A, 0x49203B20, 0x6974696E, 0x7A696C61
    .WORD 0x68742065, 0x6C612065, 0x61636F6C, 0x20726F74, 0x73756D28, 0x6F642074, 0x69687420, 0x69662073
    .WORD 0x21747372, 0x20200A29, 0x41432020, 0x6D204C4C, 0x6F6C6C61, 0x6E695F63, 0x200A7469, 0x50202020
    .WORD 0x2020504F, 0x200A3352, 0x50202020, 0x2020504F, 0x200A3252, 0x50202020, 0x2020504F, 0x200A3152
    .WORD 0x3B202020, 0x75626544, 0x0A322067, 0x20202020, 0x6D204C42, 0x206E6961, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x63203B20, 0x206C6C61, 0x6E69616D, 0x6F6F6C20, 0x202D2070, 0x6320736C, 0x65207461
    .WORD 0x206F6863, 0x0A637465, 0x20202020, 0x6265443B, 0x32206775, 0x2020200A, 0x20494C20, 0x30203152
    .WORD 0x2020200A, 0x53555020, 0x31522048, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x74697865
    .WORD 0x2D203020, 0x63757320, 0x73736563, 0x2D203120, 0x72726520, 0x200A726F, 0x4C202020, 0x31522049
    .WORD 0x20203120, 0x20202020, 0x20202020, 0x20202020, 0x7570203B, 0x6F742074, 0x656C7320, 0x73207065
    .WORD 0x6170206F, 0x746E6572, 0x69617720, 0x64697074, 0x6E616320, 0x726F7720, 0x20200A6B, 0x56532020
    .WORD 0x59532043, 0x4C535F53, 0x0A504545, 0x20202020, 0x6265443B, 0x32206775, 0x2020200A, 0x504F5020
    .WORD 0x31522020, 0x2020200A, 0x494C203B, 0x20315220, 0x20200A31, 0x56532020, 0x59532043, 0x58455F53
    .WORD 0x0A0A5449, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x7570203B, 0x2D207374, 0x69725720
    .WORD 0x6E206574, 0x2D6C6C75, 0x6D726574, 0x74616E69, 0x73206465, 0x6E697274, 0x6F742067, 0x64747320
    .WORD 0x0A74756F, 0x4E49203B, 0x5220203A, 0x203D2031, 0x69727473, 0x7020676E, 0x746E696F, 0x3B0A7265
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
    .WORD 0x3B202020, 0x2020494C, 0x31203152, 0x20202030, 0x20202020, 0x20202020, 0x203B2020, 0x6C77654E
    .WORD 0x20656E69, 0x72616863, 0x65746361, 0x20200A72, 0x423B2020, 0x7020204C, 0x68637475, 0x20207261
    .WORD 0x20202020, 0x20202020, 0x57203B20, 0x65746972, 0x77656E20, 0x656E696C, 0x2020200A, 0x504F5020
    .WORD 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020
    .WORD 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x74757020, 0x72616863, 0x57202D20
    .WORD 0x65746972, 0x6E697320, 0x20656C67, 0x72616863, 0x65746361, 0x6F742072, 0x64747320, 0x0A74756F
    .WORD 0x4E49203B, 0x5220203A, 0x203D2031, 0x72616863, 0x65746361, 0x203B0A72, 0x3A54554F, 0x20315220
    .WORD 0x7962203D, 0x20736574, 0x74697277, 0x206E6574, 0x20293128, 0x6520726F, 0x726F7272, 0x646F6320
    .WORD 0x3D3B0A65, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x75700A3D, 0x61686374, 0x200A3A72, 0x50202020
    .WORD 0x20485355, 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x4C202020, 0x38522049, 0x5F686320
    .WORD 0x0A667562, 0x20202020, 0x20425453, 0x5B203152, 0x205D3852, 0x20202020, 0x20202020, 0x53203B20
    .WORD 0x65726F74, 0x61686320, 0x6E692072, 0x61747320, 0x20636974, 0x66667562, 0x200A7265, 0x4C202020
    .WORD 0x31522049, 0x44545320, 0x5F54554F, 0x200A4446, 0x4D202020, 0x5220564F, 0x38522032, 0x2020200A
    .WORD 0x20494C20, 0x31203352, 0x2020200A, 0x43565320, 0x53595320, 0x4952575F, 0x200A4554, 0x50202020
    .WORD 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x3D3B0A0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x6C727473, 0x2D206E65, 0x6C614320, 0x616C7563, 0x73206574
    .WORD 0x6E697274, 0x656C2067, 0x6874676E, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x72747320, 0x20676E69
    .WORD 0x6E696F70, 0x0A726574, 0x554F203B, 0x52203A54, 0x203D2031, 0x676E656C, 0x28206874, 0x6C637865
    .WORD 0x6E696475, 0x756E2067, 0x74206C6C, 0x696D7265, 0x6F74616E, 0x3B0A2972, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x730A3D3D, 0x656C7274, 0x200A3A6E, 0x50202020, 0x20485355, 0x200A524C, 0x50202020
    .WORD 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x4D202020, 0x5220564F, 0x31522038
    .WORD 0x2020200A, 0x20494C20, 0x30203952, 0x7274730A, 0x5F6E656C, 0x706F6F6C, 0x20200A3A, 0x444C2020
    .WORD 0x32522042, 0x38525B20, 0x52202B20, 0x20205D39, 0x3B202020, 0x61655220, 0x68632064, 0x63617261
    .WORD 0x20726574, 0x63207461, 0x65727275, 0x6F20746E, 0x65736666, 0x20200A74, 0x4D432020, 0x32522050
    .WORD 0x200A3020, 0x42202020, 0x73205145, 0x656C7274, 0x6F645F6E, 0x200A656E, 0x41202020, 0x52204444
    .WORD 0x39522039, 0x20203120, 0x20202020, 0x20202020, 0x6E49203B, 0x6D657263, 0x20746E65, 0x6E756F63
    .WORD 0x0A726574, 0x20202020, 0x74732042, 0x6E656C72, 0x6F6F6C5F, 0x74730A70, 0x6E656C72, 0x6E6F645F
    .WORD 0x200A3A65, 0x4D202020, 0x5220564F, 0x39522031, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020
    .WORD 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D, 0x72747320, 0x20706D63, 0x6F43202D, 0x7261706D, 0x77742065
    .WORD 0x7473206F, 0x676E6972, 0x203B0A73, 0x203A4E49, 0x20315220, 0x7473203D, 0x676E6972, 0x52202C31
    .WORD 0x203D2032, 0x69727473, 0x0A32676E, 0x554F203B, 0x52203A54, 0x203D2031, 0x66692031, 0x75716520
    .WORD 0x202C6C61, 0x66692030, 0x66696420, 0x65726566, 0x3B0A746E, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x730A3D3D, 0x6D637274, 0x200A3A70, 0x50202020, 0x20485355, 0x200A524C, 0x50202020, 0x20485355
    .WORD 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x50202020, 0x20485355, 0x0A303152, 0x20202020
    .WORD 0x20564F4D, 0x52203852, 0x20200A31, 0x4F4D2020, 0x39522056, 0x0A325220, 0x63727473, 0x6C5F706D
    .WORD 0x3A706F6F, 0x2020200A, 0x42444C20, 0x30315220, 0x38525B20, 0x2020205D, 0x20202020, 0x203B2020
    .WORD 0x64616F4C, 0x61686320, 0x72662072, 0x73206D6F, 0x6E697274, 0x200A3167, 0x4C202020, 0x52204244
    .WORD 0x525B2031, 0x20205D39, 0x20202020, 0x20202020, 0x6F4C203B, 0x63206461, 0x20726168, 0x6D6F7266
    .WORD 0x72747320, 0x32676E69, 0x2020200A, 0x504D4320, 0x30315220, 0x0A315220, 0x20202020, 0x20454E42
    .WORD 0x63727473, 0x6E5F706D, 0x20202065, 0x20202020, 0x4D203B20, 0x616D7369, 0x20686374, 0x6E756F66
    .WORD 0x20200A64, 0x4D432020, 0x31522050, 0x0A302030, 0x20202020, 0x20514542, 0x63727473, 0x655F706D
    .WORD 0x20202071, 0x20202020, 0x42203B20, 0x2068746F, 0x69727473, 0x2073676E, 0x65646E65, 0x74612064
    .WORD 0x6D617320, 0x69742065, 0x200A656D, 0x41202020, 0x52204444, 0x38522038, 0x20203120, 0x20202020
    .WORD 0x20202020, 0x6441203B, 0x636E6176, 0x6F622065, 0x70206874, 0x746E696F, 0x0A737265, 0x20202020
    .WORD 0x20444441, 0x52203952, 0x0A312039, 0x20202020, 0x74732042, 0x706D6372, 0x6F6F6C5F, 0x74730A70
    .WORD 0x706D6372, 0x3A71655F, 0x2020200A, 0x20494C20, 0x31203152, 0x2020200A, 0x73204220, 0x6D637274
    .WORD 0x6F645F70, 0x730A656E, 0x6D637274, 0x656E5F70, 0x20200A3A, 0x494C2020, 0x20315220, 0x74730A30
    .WORD 0x706D6372, 0x6E6F645F, 0x200A3A65, 0x50202020, 0x5220504F, 0x200A3031, 0x50202020, 0x5220504F
    .WORD 0x20200A39, 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552
    .WORD 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x6D203B0A, 0x70636D65, 0x202D2079, 0x79706F43
    .WORD 0x6D656D20, 0x2079726F, 0x636F6C62, 0x203B0A6B, 0x203A4E49, 0x20315220, 0x6564203D, 0x202C7473
    .WORD 0x3D203252, 0x63727320, 0x3352202C, 0x63203D20, 0x746E756F, 0x4F203B0A, 0x203A5455, 0x3D203152
    .WORD 0x73656420, 0x65282074, 0x7020646E, 0x7469736F, 0x296E6F69, 0x3D3D3B0A, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x6D656D0A, 0x3A797063, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020
    .WORD 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x53555020, 0x31522048, 0x20200A30
    .WORD 0x4F4D2020, 0x38522056, 0x0A315220, 0x20202020, 0x20564F4D, 0x52203952, 0x20200A32, 0x4F4D2020
    .WORD 0x31522056, 0x33522030, 0x6D656D0A, 0x5F797063, 0x706F6F6C, 0x20200A3A, 0x4D432020, 0x31522050
    .WORD 0x0A302030, 0x20202020, 0x20514542, 0x636D656D, 0x645F7970, 0x0A656E6F, 0x20202020, 0x2042444C
    .WORD 0x5B203152, 0x205D3952, 0x20202020, 0x20202020, 0x52203B20, 0x20646165, 0x65747962, 0x6F726620
    .WORD 0x6F73206D, 0x65637275, 0x2020200A, 0x42545320, 0x20315220, 0x5D38525B, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x74697257, 0x79622065, 0x74206574, 0x6564206F, 0x6E697473, 0x6F697461, 0x20200A6E
    .WORD 0x44412020, 0x38522044, 0x20385220, 0x20202031, 0x20202020, 0x3B202020, 0x76644120, 0x65636E61
    .WORD 0x746F6220, 0x6F702068, 0x65746E69, 0x200A7372, 0x41202020, 0x52204444, 0x39522039, 0x200A3120
    .WORD 0x53202020, 0x52204255, 0x52203031, 0x31203031, 0x20202020, 0x20202020, 0x6544203B, 0x6D657263
    .WORD 0x20746E65, 0x6E756F63, 0x0A726574, 0x20202020, 0x656D2042, 0x7970636D, 0x6F6F6C5F, 0x656D0A70
    .WORD 0x7970636D, 0x6E6F645F, 0x200A3A65, 0x4D202020, 0x5220564F, 0x38522031, 0x2020200A, 0x504F5020
    .WORD 0x30315220, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020
    .WORD 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A3D3D
    .WORD 0x6D656D20, 0x20746573, 0x6946202D, 0x6D206C6C, 0x726F6D65, 0x69772079, 0x63206874, 0x74736E6F
    .WORD 0x20746E61, 0x65747962, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x73656420, 0x52202C74, 0x203D2032
    .WORD 0x756C6176, 0x52202C65, 0x203D2033, 0x6E756F63, 0x203B0A74, 0x3A54554F, 0x20315220, 0x6564203D
    .WORD 0x28207473, 0x20646E65, 0x69736F70, 0x6E6F6974, 0x3D3B0A29, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x656D0A3D, 0x7465736D, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020, 0x52204853
    .WORD 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x55502020, 0x52204853, 0x200A3031, 0x4D202020
    .WORD 0x5220564F, 0x31522038, 0x2020200A, 0x564F4D20, 0x20395220, 0x200A3252, 0x4D202020, 0x5220564F
    .WORD 0x52203031, 0x656D0A33, 0x7465736D, 0x6F6F6C5F, 0x200A3A70, 0x43202020, 0x5220504D, 0x30203031
    .WORD 0x2020200A, 0x51454220, 0x6D656D20, 0x5F746573, 0x656E6F64, 0x2020200A, 0x42545320, 0x20395220
    .WORD 0x5D38525B, 0x20202020, 0x20202020, 0x203B2020, 0x726F7453, 0x61762065, 0x2065756C, 0x63207461
    .WORD 0x65727275, 0x7020746E, 0x7469736F, 0x0A6E6F69, 0x20202020, 0x20444441, 0x52203852, 0x20312038
    .WORD 0x20202020, 0x20202020, 0x41203B20, 0x6E617664, 0x70206563, 0x746E696F, 0x200A7265, 0x53202020
    .WORD 0x52204255, 0x52203031, 0x31203031, 0x20202020, 0x20202020, 0x6544203B, 0x6D657263, 0x20746E65
    .WORD 0x6E756F63, 0x0A726574, 0x20202020, 0x656D2042, 0x7465736D, 0x6F6F6C5F, 0x656D0A70, 0x7465736D
    .WORD 0x6E6F645F, 0x200A3A65, 0x4D202020, 0x5220564F, 0x38522031, 0x2020200A, 0x504F5020, 0x30315220
    .WORD 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F
    .WORD 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x69727720
    .WORD 0x66286574, 0x62202C64, 0x202C6675, 0x296E656C, 0x3B0A3B0A, 0x3A4E4920, 0x20203B0A, 0x20315220
    .WORD 0x6466203D, 0x20203B0A, 0x20325220, 0x7562203D, 0x72656666, 0x20203B0A, 0x20335220, 0x656C203D
    .WORD 0x6874676E, 0x3B0A3B0A, 0x54554F20, 0x203B0A3A, 0x31522020, 0x62203D20, 0x73657479, 0x69727720
    .WORD 0x6E657474, 0x65202F20, 0x6F6E7272, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6972770A
    .WORD 0x0A3A6574, 0x20202020, 0x20435653, 0x5F535953, 0x54495257, 0x20200A45, 0x45522020, 0x0A0A0A54
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6572203B, 0x66286461, 0x62202C64, 0x202C6675
    .WORD 0x296E656C, 0x3B0A3B0A, 0x3A4E4920, 0x20203B0A, 0x20315220, 0x6466203D, 0x20203B0A, 0x20325220
    .WORD 0x7562203D, 0x72656666, 0x20203B0A, 0x20335220, 0x656C203D, 0x6874676E, 0x3B0A3B0A, 0x54554F20
    .WORD 0x203B0A3A, 0x31522020, 0x62203D20, 0x73657479, 0x61657220, 0x2D3B0A64, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x65720A2D, 0x0A3A6461, 0x20202020, 0x20435653, 0x5F535953, 0x44414552, 0x2020200A
    .WORD 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x65706F20, 0x6170286E
    .WORD 0x202C6874, 0x67616C66, 0x3B0A2973, 0x49203B0A, 0x3B0A3A4E, 0x52202020, 0x203D2031, 0x68746170
    .WORD 0x20203B0A, 0x20325220, 0x6C66203D, 0x0A736761, 0x203B0A3B, 0x3A54554F, 0x20203B0A, 0x20315220
    .WORD 0x6466203D, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x65706F0A, 0x200A3A6E, 0x53202020
    .WORD 0x53204356, 0x4F5F5359, 0x0A4E4550, 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x203B0A2D, 0x736F6C63, 0x64662865, 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6C630A2D, 0x3A65736F, 0x2020200A, 0x43565320, 0x53595320, 0x4F4C435F, 0x200A4553, 0x52202020
    .WORD 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6B6D203B, 0x0A726964, 0x2D2D2D3B
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x69646B6D, 0x200A3A72, 0x53202020, 0x53204356, 0x4D5F5359
    .WORD 0x5249444B, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D
    .WORD 0x69646D72, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6D720A2D, 0x3A726964, 0x2020200A
    .WORD 0x43565320, 0x53595320, 0x444D525F, 0x200A5249, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x66203B0A, 0x286B726F, 0x0A3B0A29, 0x6170203B, 0x746E6572, 0x203B0A3A
    .WORD 0x31522020, 0x63203D20, 0x646C6968, 0x64697020, 0x3B0A3B0A, 0x69686320, 0x0A3A646C, 0x2020203B
    .WORD 0x3D203152, 0x3B0A3020, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x660A2D2D, 0x3A6B726F, 0x2020200A
    .WORD 0x43565320, 0x53595320, 0x524F465F, 0x20200A4B, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x7865203B, 0x65766365, 0x74617028, 0x61202C68, 0x2C766772, 0x766E6520
    .WORD 0x3B0A2970, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x650A2D2D, 0x76636578, 0x200A3A65, 0x53202020
    .WORD 0x53204356, 0x455F5359, 0x56434558, 0x20200A45, 0x45522020, 0x0A0A0A54, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x6177203B, 0x69707469, 0x69702864, 0x74732C64, 0x73757461, 0x2D3B0A29
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x61770A2D, 0x69707469, 0x200A3A64, 0x53202020, 0x53204356
    .WORD 0x575F5359, 0x50544941, 0x200A4449, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x73203B0A, 0x7065656C, 0x6C696D28, 0x6573696C, 0x646E6F63, 0x3B0A2973, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x730A2D2D, 0x7065656C, 0x20200A3A, 0x56532020, 0x59532043, 0x4C535F53
    .WORD 0x0A504545, 0x20202020, 0x0A544552, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D
    .WORD 0x74697865, 0x61747328, 0x29737574, 0x3B0A3B0A, 0x76656E20, 0x72207265, 0x72757465, 0x3B0A736E
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x650A2D2D, 0x3A746978, 0x2020200A, 0x43565320, 0x53595320
    .WORD 0x4958455F, 0x650A0A54, 0x5F746978, 0x676E6168, 0x20200A3A, 0x20422020, 0x74697865, 0x6E61685F
    .WORD 0x0A0A0A67, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x454D203B, 0x59524F4D, 0x4E414D20
    .WORD 0x4D454741, 0x0A544E45, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x56203B0A, 0x20595245, 0x504D4953, 0x4D20454C, 0x524F4D45, 0x4C412059
    .WORD 0x41434F4C, 0x0A524F54, 0x203B0A3B, 0x73696854, 0x20736920, 0x696D2061, 0x616D696E, 0x616D206C
    .WORD 0x636F6C6C, 0x6572662F, 0x6D692065, 0x6D656C70, 0x61746E65, 0x6E6F6974, 0x61687420, 0x3B0A3A74
    .WORD 0x202E3120, 0x73657355, 0x66206120, 0x64657869, 0x72726120, 0x74207961, 0x7274206F, 0x206B6361
    .WORD 0x6F6D656D, 0x62207972, 0x6B636F6C, 0x203B0A73, 0x44202E32, 0x2073656F, 0x20544F4E, 0x6C616F63
    .WORD 0x65637365, 0x656D2820, 0x20656772, 0x616A6461, 0x746E6563, 0x65726620, 0x6C622065, 0x736B636F
    .WORD 0x203B0A29, 0x44202E33, 0x2073656F, 0x20544F4E, 0x696C7073, 0x6C622074, 0x736B636F, 0x73752820
    .WORD 0x65207365, 0x7269746E, 0x6C622065, 0x206B636F, 0x692D7361, 0x3B0A2973, 0x202E3420, 0x73657355
    .WORD 0x72696620, 0x662D7473, 0x73207469, 0x63726165, 0x66282068, 0x73646E69, 0x72696620, 0x62207473
    .WORD 0x6B636F6C, 0x61687420, 0x20732774, 0x20676962, 0x756F6E65, 0x0A296867, 0x2E35203B, 0x65735520
    .WORD 0x62732073, 0x73206B72, 0x61637379, 0x74206C6C, 0x6567206F, 0x6F6D2074, 0x6D206572, 0x726F6D65
    .WORD 0x72662079, 0x6B206D6F, 0x656E7265, 0x0A3B0A6C, 0x7254203B, 0x2D656461, 0x7366666F, 0x203B0A3A
    .WORD 0x6556202B, 0x73207972, 0x6C706D69, 0x6E612065, 0x61652064, 0x74207973, 0x6E75206F, 0x73726564
    .WORD 0x646E6174, 0x2B203B0A, 0x65725020, 0x74636964, 0x656C6261, 0x6D656D20, 0x2079726F, 0x67617375
    .WORD 0x66282065, 0x64657869, 0x62617420, 0x0A29656C, 0x202B203B, 0x63206F4E, 0x6C706D6F, 0x6C207865
    .WORD 0x656B6E69, 0x696C2064, 0x6D207473, 0x67616E61, 0x6E656D65, 0x203B0A74, 0x654D202D, 0x79726F6D
    .WORD 0x61726620, 0x6E656D67, 0x69746174, 0x28206E6F, 0x276E6163, 0x656D2074, 0x20656772, 0x65657266
    .WORD 0x6F6C6220, 0x29736B63, 0x2D203B0A, 0x73615720, 0x20646574, 0x63617073, 0x63282065, 0x74276E61
    .WORD 0x6C707320, 0x6C207469, 0x65677261, 0x6F6C6220, 0x29736B63, 0x2D203B0A, 0x6D694C20, 0x64657469
    .WORD 0x206F7420, 0x5F58414D, 0x434F4C42, 0x6120534B, 0x636F6C6C, 0x6F697461, 0x3B0A736E, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x0A0A2D2D, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x4F43203B
    .WORD 0x4154534E, 0x0A53544E, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x51452E0A, 0x414D2055
    .WORD 0x4C425F58, 0x534B434F, 0x3834202C, 0x20202020, 0x3B202020, 0x78614D20, 0x6D756D69, 0x6D756E20
    .WORD 0x20726562, 0x6220666F, 0x6B636F6C, 0x65772073, 0x6E616320, 0x61727420, 0x200A6B63, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x28203B20, 0x276E6163, 0x6C612074
    .WORD 0x61636F6C, 0x6D206574, 0x2065726F, 0x6E616874, 0x20323320, 0x656D6974, 0x69772073, 0x756F6874
    .WORD 0x72662074, 0x6E696565, 0x0A0A2967, 0x6C42203B, 0x206B636F, 0x63736564, 0x74706972, 0x6F20726F
    .WORD 0x65736666, 0x28207374, 0x68636165, 0x6F6C6220, 0x6E206B63, 0x73646565, 0x65687420, 0x33206573
    .WORD 0x6C617620, 0x29736575, 0x51452E0A, 0x4C422055, 0x5F4B434F, 0x52444441, 0x3020202C, 0x20202020
    .WORD 0x3B202020, 0x66664F20, 0x3A746573, 0x61747320, 0x6E697472, 0x64612067, 0x73657264, 0x666F2073
    .WORD 0x65687420, 0x6F6C6220, 0x28206B63, 0x79622034, 0x29736574, 0x51452E0A, 0x4C422055, 0x5F4B434F
    .WORD 0x455A4953, 0x3420202C, 0x20202020, 0x3B202020, 0x66664F20, 0x3A746573, 0x7A697320, 0x666F2065
    .WORD 0x65687420, 0x6F6C6220, 0x69206B63, 0x7962206E, 0x20736574, 0x62203428, 0x73657479, 0x0A202029
    .WORD 0x5551452E, 0x4F4C4220, 0x555F4B43, 0x2C444553, 0x20382020, 0x20202020, 0x203B2020, 0x7366664F
    .WORD 0x203A7465, 0x72663D30, 0x202C6565, 0x73753D31, 0x28206465, 0x79622034, 0x29736574, 0x51452E0A
    .WORD 0x4C422055, 0x5F4B434F, 0x43534544, 0x3120202C, 0x20202032, 0x3B202020, 0x746F5420, 0x73206C61
    .WORD 0x20657A69, 0x6F20666F, 0x6220656E, 0x6B636F6C, 0x73656420, 0x70697263, 0x20726F74, 0x77203328
    .WORD 0x7364726F, 0x31203D20, 0x79622032, 0x29736574, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x41544144, 0x43455320, 0x4E4F4954, 0x54202D20, 0x62206568, 0x6B636F6C, 0x62617420
    .WORD 0x0A20656C, 0x6F6E203B, 0x6C616D72, 0x6D20796C, 0x726F6D65, 0x6C622079, 0x736B636F, 0x74656720
    .WORD 0x73657220, 0x76657265, 0x66206465, 0x206D6F72, 0x50414548, 0x69687720, 0x69206863, 0x6F6C2073
    .WORD 0x65746163, 0x74612064, 0x74616420, 0x65732061, 0x6E656D67, 0x3B0A2074, 0x67617020, 0x70282065
    .WORD 0x20656761, 0x72646461, 0x20737365, 0x63657073, 0x65696669, 0x73612064, 0x65737520, 0x61645F72
    .WORD 0x765F6174, 0x0A202961, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x6F6C620A, 0x745F6B63
    .WORD 0x656C6261, 0x20200A3A, 0x203B2020, 0x73696854, 0x20736920, 0x61206E61, 0x79617272, 0x20666F20
    .WORD 0x5F58414D, 0x434F4C42, 0x6420534B, 0x72637365, 0x6F747069, 0x0A2E7372, 0x20202020, 0x6145203B
    .WORD 0x64206863, 0x72637365, 0x6F747069, 0x61682072, 0x61203A73, 0x65726464, 0x202C7373, 0x657A6973
    .WORD 0x7375202C, 0x665F6465, 0x0A67616C, 0x20202020, 0x6F54203B, 0x206C6174, 0x657A6973, 0x414D203A
    .WORD 0x4C425F58, 0x534B434F, 0x31202A20, 0x79622032, 0x0A736574, 0x20202020, 0x4150532E, 0x4D204543
    .WORD 0x425F5841, 0x4B434F4C, 0x202A2053, 0x434F4C42, 0x45445F4B, 0x0A0A4353, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x616D203B, 0x636F6C6C, 0x7A697328, 0x3B0A2965, 0x41203B0A, 0x636F6C6C
    .WORD 0x73657461, 0x6D656D20, 0x2079726F, 0x6D6F7266, 0x65687420, 0x61656820, 0x3B0A2E70, 0x48203B0A
    .WORD 0x6920776F, 0x6F772074, 0x3A736B72, 0x31203B0A, 0x6C41202E, 0x206E6769, 0x20656874, 0x75716572
    .WORD 0x65747365, 0x69732064, 0x7420657A, 0x2038206F, 0x65747962, 0x6D282073, 0x73656B61, 0x6D656D20
    .WORD 0x2079726F, 0x616E616D, 0x656D6567, 0x6520746E, 0x65697361, 0x3B0A2972, 0x202E3220, 0x72616553
    .WORD 0x74206863, 0x62206568, 0x6B636F6C, 0x62617420, 0x6620656C, 0x6120726F, 0x65726620, 0x6C622065
    .WORD 0x206B636F, 0x74616874, 0x6C207327, 0x65677261, 0x6F6E6520, 0x0A686775, 0x2E33203B, 0x20664920
    .WORD 0x6E756F66, 0x6D202C64, 0x206B7261, 0x61207469, 0x73752073, 0x61206465, 0x7220646E, 0x72757465
    .WORD 0x7469206E, 0x64612073, 0x73657264, 0x203B0A73, 0x49202E34, 0x6F6E2066, 0x6F662074, 0x2C646E75
    .WORD 0x6B736120, 0x65687420, 0x72656B20, 0x206C656E, 0x20726F66, 0x65726F6D, 0x6D656D20, 0x2079726F
    .WORD 0x20616976, 0x6B726273, 0x73797320, 0x6C6C6163, 0x35203B0A, 0x6441202E, 0x68742064, 0x656E2065
    .WORD 0x656D2077, 0x79726F6D, 0x206F7420, 0x20656874, 0x636F6C62, 0x6174206B, 0x20656C62, 0x20646E61
    .WORD 0x75746572, 0x69206E72, 0x0A3B0A74, 0x6E49203B, 0x3A747570, 0x31522020, 0x73203D20, 0x20657A69
    .WORD 0x62206E69, 0x73657479, 0x2E652820, 0x202C2E67, 0x29303031, 0x4F203B0A, 0x75707475, 0x52203A74
    .WORD 0x203D2031, 0x6E696F70, 0x20726574, 0x61206F74, 0x636F6C6C, 0x64657461, 0x6D656D20, 0x2079726F
    .WORD 0x20726F28, 0x66692030, 0x69616620, 0x2964656C, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x6C616D0A, 0x3A636F6C, 0x2020200A, 0x53203B20, 0x20657661, 0x69676572, 0x72657473, 0x65772073
    .WORD 0x206C6C27, 0x20657375, 0x206F7328, 0x64206577, 0x74276E6F, 0x726F6320, 0x74707572, 0x6C616320
    .WORD 0x2772656C, 0x61762073, 0x7365756C, 0x20200A29, 0x55502020, 0x4C204853, 0x20202052, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6153203B, 0x72206576, 0x72757465, 0x6461206E, 0x73657264, 0x20200A73
    .WORD 0x200A2020, 0x3B202020, 0x65745320, 0x3A312070, 0x696C4120, 0x73206E67, 0x20657A69, 0x6D206F74
    .WORD 0x69746C75, 0x20656C70, 0x3820666F, 0x74796220, 0x200A7365, 0x3B202020, 0x79685720, 0x614D203F
    .WORD 0x4320796E, 0x20735550, 0x6B726F77, 0x73616620, 0x20726574, 0x68746977, 0x696C6120, 0x64656E67
    .WORD 0x6D656D20, 0x0A79726F, 0x20202020, 0x7845203B, 0x6C706D61, 0x73203A65, 0x3D657A69, 0x0A303031
    .WORD 0x20202020, 0x2020203B, 0x20444441, 0x37203152, 0x20202020, 0x31203E2D, 0x200A3730, 0x3B202020
    .WORD 0x41202020, 0x3020444E, 0x46464678, 0x46464646, 0x3E2D2038, 0x34303120, 0x756D2820, 0x7069746C
    .WORD 0x6F20656C, 0x29382066, 0x2020200A, 0x44444120, 0x20315220, 0x37203152, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x64644120, 0x74203720, 0x6F72206F, 0x20646E75, 0x200A7075, 0x4C202020, 0x52202049
    .WORD 0x78302032, 0x46464646, 0x38464646, 0x20200A20, 0x4E412020, 0x31522044, 0x20315220, 0x20203252
    .WORD 0x20202020, 0x20202020, 0x6C43203B, 0x20726165, 0x65776F6C, 0x20332072, 0x73746962, 0x616D2820
    .WORD 0x6D20656B, 0x69746C75, 0x20656C70, 0x3820666F, 0x20200A29, 0x4F4D2020, 0x35522056, 0x20315220
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x3552203B, 0x61203D20, 0x6E67696C, 0x73206465, 0x20657A69
    .WORD 0x672E6528, 0x31202C2E, 0x0A293430, 0x20202020, 0x2020200A, 0x53203B20, 0x20706574, 0x53203A32
    .WORD 0x63726165, 0x6F662068, 0x20612072, 0x65657266, 0x6F6C6220, 0x69206B63, 0x6874206E, 0x61742065
    .WORD 0x0A656C62, 0x20202020, 0x6557203B, 0x206C6C27, 0x20657375, 0x61203452, 0x6E692073, 0x20786564
    .WORD 0x6F746E69, 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x20302820, 0x4D206F74, 0x425F5841, 0x4B434F4C
    .WORD 0x29312D53, 0x2020200A, 0x20494C20, 0x30203452, 0x20202020, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x61745320, 0x61207472, 0x69662074, 0x20747372, 0x636F6C62, 0x6928206B, 0x7865646E, 0x0A293020
    .WORD 0x20202020, 0x6C616D0A, 0x5F636F6C, 0x706F6F6C, 0x20200A3A, 0x203B2020, 0x63656843, 0x6669206B
    .WORD 0x27657720, 0x73206576, 0x63726165, 0x20646568, 0x206C6C61, 0x636F6C62, 0x200A736B, 0x43202020
    .WORD 0x5220504D, 0x414D2034, 0x4C425F58, 0x534B434F, 0x20202020, 0x43203B20, 0x61706D6F, 0x69206572
    .WORD 0x7865646E, 0x74697720, 0x616D2068, 0x756D6978, 0x20200A6D, 0x47422020, 0x616D2045, 0x636F6C6C
    .WORD 0x7262735F, 0x2020206B, 0x20202020, 0x6649203B, 0x646E6920, 0x3E207865, 0x414D203D, 0x4C425F58
    .WORD 0x534B434F, 0x6F6E202C, 0x65726620, 0x6C622065, 0x206B636F, 0x6E756F66, 0x20200A64, 0x200A2020
    .WORD 0x3B202020, 0x6C614320, 0x616C7563, 0x61206574, 0x65726464, 0x6F207373, 0x68742066, 0x62207369
    .WORD 0x6B636F6C, 0x64207327, 0x72637365, 0x6F747069, 0x20200A72, 0x203B2020, 0x636F6C62, 0x61745F6B
    .WORD 0x20656C62, 0x6928202B, 0x7865646E, 0x64202A20, 0x72637365, 0x6F747069, 0x69735F72, 0x0A29657A
    .WORD 0x20202020, 0x5220494C, 0x6C622032, 0x5F6B636F, 0x6C626174, 0x20202065, 0x203B2020, 0x3D203252
    .WORD 0x73616220, 0x64612065, 0x73657264, 0x666F2073, 0x6F6C6220, 0x745F6B63, 0x656C6261, 0x2020200A
    .WORD 0x20494C20, 0x42203352, 0x4B434F4C, 0x5345445F, 0x20202043, 0x3B202020, 0x20335220, 0x6973203D
    .WORD 0x6F20657A, 0x6E6F2066, 0x65642065, 0x69726373, 0x726F7470, 0x32312820, 0x74796220, 0x0A297365
    .WORD 0x20202020, 0x204C554D, 0x52203352, 0x33522034, 0x20202020, 0x20202020, 0x203B2020, 0x3D203352
    .WORD 0x646E6920, 0x2A207865, 0x20323120, 0x66666F28, 0x20746573, 0x6F746E69, 0x62617420, 0x0A29656C
    .WORD 0x20202020, 0x20444441, 0x52203252, 0x33522032, 0x20202020, 0x20202020, 0x203B2020, 0x3D203252
    .WORD 0x6C622620, 0x5B6B636F, 0x65646E69, 0x200A5D78, 0x0A202020, 0x20202020, 0x6843203B, 0x206B6365
    .WORD 0x74206669, 0x20736968, 0x636F6C62, 0x7369206B, 0x65726620, 0x55282065, 0x20444553, 0x67616C66
    .WORD 0x30203D20, 0x20200A29, 0x444C2020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C, 0x4553555F
    .WORD 0x20205D44, 0x6F4C203B, 0x74206461, 0x26206568, 0x636F6C62, 0x6E695B6B, 0x5D786564, 0x6F6C622E
    .WORD 0x755F6B63, 0x20646573, 0x67616C66, 0x2020200A, 0x504D4320, 0x20335220, 0x20202030, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x20734920, 0x30207469, 0x72662820, 0x3F296565, 0x2020200A, 0x454E4220
    .WORD 0x6C616D20, 0x5F636F6C, 0x7478656E, 0x20202020, 0x3B202020, 0x20664920, 0x20746F6E, 0x65657266
    .WORD 0x73752820, 0x2C296465, 0x696B7320, 0x6F742070, 0x78656E20, 0x6C622074, 0x0A6B636F, 0x20202020
    .WORD 0x2020200A, 0x66203B20, 0x2E656572, 0x65684320, 0x69206B63, 0x68742066, 0x62207369, 0x6B636F6C
    .WORD 0x20736920, 0x6772616C, 0x6E652065, 0x6867756F, 0x726F6620, 0x72756F20, 0x71657220, 0x74736575
    .WORD 0x2020200A, 0x57444C20, 0x20335220, 0x2032525B, 0x4C42202B, 0x5F4B434F, 0x455A4953, 0x3B20205D
    .WORD 0x616F4C20, 0x68742064, 0x6C622065, 0x206B636F, 0x657A6973, 0x2020200A, 0x504D4320, 0x20335220
    .WORD 0x20203552, 0x20202020, 0x20202020, 0x3B202020, 0x20734920, 0x636F6C62, 0x6973206B, 0x3E20657A
    .WORD 0x6572203D, 0x73657571, 0x20646574, 0x657A6973, 0x20200A3F, 0x47422020, 0x616D2045, 0x636F6C6C
    .WORD 0x756F665F, 0x2020646E, 0x20202020, 0x6559203B, 0x57202173, 0x6F662065, 0x20646E75, 0x75732061
    .WORD 0x62617469, 0x6220656C, 0x6B636F6C, 0x2020200A, 0x616D0A20, 0x636F6C6C, 0x78656E5F, 0x200A3A74
    .WORD 0x3B202020, 0x69685420, 0x6C622073, 0x206B636F, 0x65207369, 0x65687469, 0x73752072, 0x6F206465
    .WORD 0x6F742072, 0x6D73206F, 0x2C6C6C61, 0x79727420, 0x78656E20, 0x6E6F2074, 0x20200A65, 0x44412020
    .WORD 0x34522044, 0x20345220, 0x20202031, 0x20202020, 0x20202020, 0x6E49203B, 0x6D657263, 0x20746E65
    .WORD 0x65646E69, 0x6F742078, 0x65686320, 0x6E206B63, 0x20747865, 0x636F6C62, 0x20200A6B, 0x20422020
    .WORD 0x6C6C616D, 0x6C5F636F, 0x20706F6F, 0x20202020, 0x20202020, 0x6F47203B, 0x63616220, 0x6F74206B
    .WORD 0x61747320, 0x6F207472, 0x6F6C2066, 0x0A0A706F, 0x6C6C616D, 0x665F636F, 0x646E756F, 0x20200A3A
    .WORD 0x203B2020, 0x70657453, 0x203A3320, 0x66206557, 0x646E756F, 0x66206120, 0x20656572, 0x636F6C62
    .WORD 0x616C206B, 0x20656772, 0x756F6E65, 0x0A216867, 0x20202020, 0x3252203B, 0x70203D20, 0x746E696F
    .WORD 0x74207265, 0x6874206F, 0x6C622065, 0x206B636F, 0x63736564, 0x74706972, 0x200A726F, 0x3B202020
    .WORD 0x20335220, 0x6C62203D, 0x206B636F, 0x657A6973, 0x65772820, 0x6E6F6420, 0x75207427, 0x69206573
    .WORD 0x6F662074, 0x70732072, 0x7474696C, 0x20676E69, 0x74206E69, 0x20736968, 0x706D6973, 0x7620656C
    .WORD 0x69737265, 0x0A296E6F, 0x20202020, 0x2020200A, 0x4D203B20, 0x206B7261, 0x20656874, 0x636F6C62
    .WORD 0x7361206B, 0x65737520, 0x55282064, 0x20444553, 0x67616C66, 0x31203D20, 0x20200A29, 0x494C2020
    .WORD 0x20335220, 0x20202031, 0x20202020, 0x20202020, 0x20202020, 0x3352203B, 0x31203D20, 0x73752820
    .WORD 0x0A296465, 0x20202020, 0x20575453, 0x5B203352, 0x2B203252, 0x4F4C4220, 0x555F4B43, 0x5D444553
    .WORD 0x203B2020, 0x726F7453, 0x20312065, 0x74206E69, 0x55206568, 0x20444553, 0x6C656966, 0x20200A64
    .WORD 0x200A2020, 0x3B202020, 0x74654720, 0x65687420, 0x6F6C6220, 0x73276B63, 0x61747320, 0x6E697472
    .WORD 0x64612067, 0x73657264, 0x6E612073, 0x65722064, 0x6E727574, 0x0A746920, 0x20202020, 0x2057444C
    .WORD 0x5B203152, 0x2B203252, 0x4F4C4220, 0x415F4B43, 0x5D524444, 0x203B2020, 0x3D203152, 0x64646120
    .WORD 0x73736572, 0x20666F20, 0x73696874, 0x6F6C6220, 0x200A6B63, 0x42202020, 0x6C616D20, 0x5F636F6C
    .WORD 0x656E6F64, 0x20202020, 0x20202020, 0x4A203B20, 0x20706D75, 0x63206F74, 0x6E61656C, 0x61207075
    .WORD 0x7220646E, 0x72757465, 0x6D0A0A6E, 0x6F6C6C61, 0x62735F63, 0x0A3A6B72, 0x20202020, 0x7453203B
    .WORD 0x34207065, 0x6F4E203A, 0x65726620, 0x6C622065, 0x206B636F, 0x6E756F66, 0x6E692064, 0x62617420
    .WORD 0x200A656C, 0x3B202020, 0x6B734120, 0x65687420, 0x72656B20, 0x206C656E, 0x20726F66, 0x65726F6D
    .WORD 0x6D656D20, 0x2079726F, 0x6E697375, 0x62732067, 0x73206B72, 0x61637379, 0x200A6C6C, 0x0A202020
    .WORD 0x20202020, 0x3552203B, 0x726C6120, 0x79646165, 0x73616820, 0x65687420, 0x696C6120, 0x64656E67
    .WORD 0x7A697320, 0x65772065, 0x65656E20, 0x20200A64, 0x4F4D2020, 0x31522056, 0x20355220, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x3152203B, 0x73203D20, 0x20657A69, 0x61206F74, 0x636F6C6C, 0x0A657461
    .WORD 0x20202020, 0x20435653, 0x5F535953, 0x4B524253, 0x20202020, 0x20202020, 0x203B2020, 0x6C6C6143
    .WORD 0x72656B20, 0x3A6C656E, 0x72627320, 0x6973286B, 0x0A29657A, 0x20202020, 0x2020200A, 0x43203B20
    .WORD 0x6B636568, 0x20666920, 0x6B726273, 0x69616620, 0x2064656C, 0x74657228, 0x736E7275, 0x20312D20
    .WORD 0x3020726F, 0x206E6F20, 0x6F727265, 0x200A2972, 0x43202020, 0x5220504D, 0x20302031, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x44203B20, 0x73206469, 0x206B7262, 0x75746572, 0x30206E72, 0x20726F20
    .WORD 0x6167656E, 0x65766974, 0x20200A3F, 0x4C422020, 0x616D2054, 0x636F6C6C, 0x7272655F, 0x2020726F
    .WORD 0x20202020, 0x6649203B, 0x72726520, 0x202C726F, 0x75746572, 0x4E206E72, 0x0A4C4C55, 0x20202020
    .WORD 0x2020200A, 0x53203B20, 0x20706574, 0x73203A35, 0x206B7262, 0x63637573, 0x65646565, 0x77202C64
    .WORD 0x61682065, 0x6E206576, 0x6D207765, 0x726F6D65, 0x74612079, 0x64646120, 0x73736572, 0x206E6920
    .WORD 0x200A3152, 0x3B202020, 0x776F4E20, 0x20657720, 0x6465656E, 0x206F7420, 0x20646461, 0x73696874
    .WORD 0x77656E20, 0x6F6C6220, 0x74206B63, 0x756F206F, 0x61742072, 0x0A656C62, 0x20202020, 0x2020200A
    .WORD 0x46203B20, 0x20646E69, 0x65206E61, 0x7974706D, 0x6F6C7320, 0x6E692074, 0x65687420, 0x6F6C6220
    .WORD 0x74206B63, 0x656C6261, 0x2020200A, 0x20494C20, 0x30203452, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x61745320, 0x61207472, 0x69662074, 0x20747372, 0x636F6C62, 0x20200A6B, 0x6D0A2020
    .WORD 0x6F6C6C61, 0x64615F63, 0x200A3A64, 0x3B202020, 0x65684320, 0x69206B63, 0x65772066, 0x20657627
    .WORD 0x72616573, 0x64656863, 0x6C6C6120, 0x6F6C6220, 0x0A736B63, 0x20202020, 0x20504D43, 0x4D203452
    .WORD 0x425F5841, 0x4B434F4C, 0x20202053, 0x200A2020, 0x42202020, 0x6D204547, 0x6F6C6C61, 0x72655F63
    .WORD 0x20726F72, 0x20202020, 0x4E203B20, 0x6D65206F, 0x20797470, 0x746F6C73, 0x73282021, 0x6C756F68
    .WORD 0x74276E64, 0x70616820, 0x296E6570, 0x2020200A, 0x20200A20, 0x203B2020, 0x20746547, 0x63736564
    .WORD 0x74706972, 0x6120726F, 0x65726464, 0x200A7373, 0x4C202020, 0x32522049, 0x6F6C6220, 0x745F6B63
    .WORD 0x656C6261, 0x2020200A, 0x20494C20, 0x42203352, 0x4B434F4C, 0x5345445F, 0x20200A43, 0x554D2020
    .WORD 0x3352204C, 0x20345220, 0x200A3352, 0x41202020, 0x52204444, 0x32522032, 0x20335220, 0x20202020
    .WORD 0x3B202020, 0x6C622620, 0x5B6B636F, 0x65646E69, 0x5D345278, 0x2020200A, 0x20200A20, 0x203B2020
    .WORD 0x63656843, 0x6669206B, 0x69687420, 0x6C732073, 0x6920746F, 0x72662073, 0x28206565, 0x44455355
    .WORD 0x616C6620, 0x203D2067, 0x200A2930, 0x4C202020, 0x52205744, 0x525B2033, 0x202B2032, 0x434F4C42
    .WORD 0x53555F4B, 0x0A5D4445, 0x20202020, 0x20504D43, 0x30203352, 0x2020200A, 0x51454220, 0x6C616D20
    .WORD 0x5F636F6C, 0x5F646461, 0x6E756F66, 0x3B202064, 0x756F4620, 0x6120646E, 0x6D65206E, 0x20797470
    .WORD 0x746F6C73, 0x20200A21, 0x200A2020, 0x3B202020, 0x6F6C5320, 0x73692074, 0x65737520, 0x74202C64
    .WORD 0x6E207972, 0x20747865, 0x0A656E6F, 0x20202020, 0x20444441, 0x52203452, 0x0A312034, 0x20202020
    .WORD 0x616D2042, 0x636F6C6C, 0x6464615F, 0x616D0A0A, 0x636F6C6C, 0x6464615F, 0x756F665F, 0x0A3A646E
    .WORD 0x20202020, 0x6557203B, 0x756F6620, 0x6120646E, 0x6D65206E, 0x20797470, 0x746F6C73, 0x20746120
    .WORD 0x200A3252, 0x3B202020, 0x6F745320, 0x74206572, 0x6E206568, 0x62207765, 0x6B636F6C, 0x69207327
    .WORD 0x726F666E, 0x6974616D, 0x200A6E6F, 0x0A202020, 0x20202020, 0x7453203B, 0x2065726F, 0x20656874
    .WORD 0x72646461, 0x20737365, 0x20315228, 0x6D6F7266, 0x72627320, 0x200A296B, 0x53202020, 0x52205754
    .WORD 0x525B2031, 0x202B2032, 0x434F4C42, 0x44415F4B, 0x205D5244, 0x203B2020, 0x636F6C62, 0x64612E6B
    .WORD 0x73657264, 0x203D2073, 0x72646461, 0x20737365, 0x6D6F7266, 0x72627320, 0x20200A6B, 0x200A2020
    .WORD 0x3B202020, 0x6F745320, 0x74206572, 0x73206568, 0x20657A69, 0x20355228, 0x6C61203D, 0x656E6769
    .WORD 0x69732064, 0x0A29657A, 0x20202020, 0x20575453, 0x5B203552, 0x2B203252, 0x4F4C4220, 0x535F4B43
    .WORD 0x5D455A49, 0x3B202020, 0x6F6C6220, 0x732E6B63, 0x20657A69, 0x6973203D, 0x200A657A, 0x0A202020
    .WORD 0x20202020, 0x614D203B, 0x61206B72, 0x73752073, 0x28206465, 0x44455355, 0x31203D20, 0x20200A29
    .WORD 0x494C2020, 0x20335220, 0x20200A31, 0x54532020, 0x33522057, 0x32525B20, 0x42202B20, 0x4B434F4C
    .WORD 0x4553555F, 0x20205D44, 0x62203B20, 0x6B636F6C, 0x6573752E, 0x203D2064, 0x20200A31, 0x200A2020
    .WORD 0x3B202020, 0x20315220, 0x65726C61, 0x20796461, 0x20736168, 0x20656874, 0x72646461, 0x20737365
    .WORD 0x6D6F7266, 0x72627320, 0x73202C6B, 0x756A206F, 0x72207473, 0x72757465, 0x7469206E, 0x2020200A
    .WORD 0x6D204220, 0x6F6C6C61, 0x6F645F63, 0x0A0A656E, 0x6C6C616D, 0x655F636F, 0x726F7272, 0x20200A3A
    .WORD 0x203B2020, 0x656D6F53, 0x6E696874, 0x65772067, 0x7720746E, 0x676E6F72, 0x72202D20, 0x72757465
    .WORD 0x554E206E, 0x28204C4C, 0x200A2930, 0x4C202020, 0x31522049, 0x0A0A3020, 0x6C6C616D, 0x645F636F
    .WORD 0x3A656E6F, 0x2020200A, 0x504F5020, 0x20524C20, 0x20202020, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x73655220, 0x65726F74, 0x74657220, 0x206E7275, 0x72646461, 0x0A737365, 0x20202020, 0x20544552
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x75746552, 0x74206E72, 0x6163206F
    .WORD 0x72656C6C, 0x74697720, 0x31522068, 0x70203D20, 0x746E696F, 0x6F207265, 0x554E2072, 0x0A0A4C4C
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7266203B, 0x70286565, 0x0A297274, 0x203B0A3B
    .WORD 0x65657246, 0x72702073, 0x6F697665, 0x796C7375, 0x6C6C6120, 0x7461636F, 0x6D206465, 0x726F6D65
    .WORD 0x3B0A2E79, 0x48203B0A, 0x6920776F, 0x6F772074, 0x3A736B72, 0x31203B0A, 0x6946202E, 0x7420646E
    .WORD 0x62206568, 0x6B636F6C, 0x73656420, 0x70697263, 0x20726F74, 0x20726F66, 0x73696874, 0x64646120
    .WORD 0x73736572, 0x32203B0A, 0x614D202E, 0x69206B72, 0x73612074, 0x65726620, 0x55282065, 0x20444553
    .WORD 0x2930203D, 0x33203B0A, 0x654D202E, 0x79726F6D, 0x20736920, 0x20776F6E, 0x69617661, 0x6C62616C
    .WORD 0x6F662065, 0x75662072, 0x65727574, 0x6C616D20, 0x20636F6C, 0x6C6C6163, 0x0A3B0A73, 0x6F4E203B
    .WORD 0x203A6574, 0x73696854, 0x6D697320, 0x20656C70, 0x73726576, 0x206E6F69, 0x73656F64, 0x544F4E20
    .WORD 0x616F6320, 0x6373656C, 0x64612065, 0x6563616A, 0x6620746E, 0x20656572, 0x636F6C62, 0x0A21736B
    .WORD 0x2020203B, 0x20202020, 0x66206F53, 0x6D676172, 0x61746E65, 0x6E6F6974, 0x6E616320, 0x63636F20
    .WORD 0x6F207275, 0x20726576, 0x656D6974, 0x0A3B0A2E, 0x6E49203B, 0x3A747570, 0x31522020, 0x70203D20
    .WORD 0x746E696F, 0x74207265, 0x656D206F, 0x79726F6D, 0x206F7420, 0x65657266, 0x72662820, 0x6D206D6F
    .WORD 0x6F6C6C61, 0x3B0A2963, 0x74754F20, 0x3A747570, 0x746F4E20, 0x676E6968, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x6572660A, 0x200A3A65, 0x3B202020, 0x76615320, 0x65722065, 0x74736967
    .WORD 0x0A737265, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x2020200A, 0x53203B20, 0x20706574
    .WORD 0x43203A31, 0x6B636568, 0x20666920, 0x6E696F70, 0x20726574, 0x4E207369, 0x0A4C4C55, 0x20202020
    .WORD 0x20504D43, 0x30203152, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x52207349, 0x3D3D2031
    .WORD 0x0A3F3020, 0x20202020, 0x20514542, 0x65657266, 0x6E6F645F, 0x20202065, 0x20202020, 0x203B2020
    .WORD 0x4E206649, 0x2C4C4C55, 0x746F6E20, 0x676E6968, 0x206F7420, 0x65657266, 0x756A202C, 0x72207473
    .WORD 0x72757465, 0x20200A6E, 0x200A2020, 0x3B202020, 0x65745320, 0x3A322070, 0x61655320, 0x20686372
    .WORD 0x20656874, 0x636F6C62, 0x6174206B, 0x20656C62, 0x20726F66, 0x73696874, 0x64646120, 0x73736572
    .WORD 0x2020200A, 0x20494C20, 0x30203452, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x61745320
    .WORD 0x61207472, 0x69662074, 0x20747372, 0x636F6C62, 0x20200A6B, 0x660A2020, 0x5F656572, 0x706F6F6C
    .WORD 0x20200A3A, 0x203B2020, 0x63656843, 0x6669206B, 0x27657720, 0x73206576, 0x63726165, 0x20646568
    .WORD 0x206C6C61, 0x636F6C62, 0x200A736B, 0x43202020, 0x5220504D, 0x414D2034, 0x4C425F58, 0x534B434F
    .WORD 0x2020200A, 0x45474220, 0x65726620, 0x6F645F65, 0x2020656E, 0x20202020, 0x3B202020, 0x746F4E20
    .WORD 0x756F6620, 0x2D20646E, 0x6E676920, 0x2065726F, 0x756F6328, 0x6220646C, 0x6E692065, 0x696C6176
    .WORD 0x6F702064, 0x65746E69, 0x200A2972, 0x0A202020, 0x20202020, 0x6547203B, 0x65642074, 0x69726373
    .WORD 0x726F7470, 0x64646120, 0x73736572, 0x2020200A, 0x20494C20, 0x62203252, 0x6B636F6C, 0x6261745F
    .WORD 0x200A656C, 0x4C202020, 0x33522049, 0x4F4C4220, 0x445F4B43, 0x20435345, 0x20202020, 0x6C203B20
    .WORD 0x74676E65, 0x666F2068, 0x656E6F20, 0x6F6C6220, 0x64206B63, 0x72637365, 0x6F747069, 0x20200A72
    .WORD 0x554D2020, 0x3352204C, 0x20345220, 0x20203352, 0x20202020, 0x20202020, 0x3472203B, 0x6F6C6220
    .WORD 0x69206B63, 0x200A7864, 0x41202020, 0x52204444, 0x32522032, 0x20335220, 0x20202020, 0x20202020
    .WORD 0x52203B20, 0x203D2032, 0x6F6C6226, 0x695B6B63, 0x20200A5D, 0x200A2020, 0x3B202020, 0x65684320
    .WORD 0x69206B63, 0x68742066, 0x62207369, 0x6B636F6C, 0x61207327, 0x65726464, 0x6D207373, 0x68637461
    .WORD 0x74207365, 0x70206568, 0x746E696F, 0x200A7265, 0x4C202020, 0x52205744, 0x525B2033, 0x202B2032
    .WORD 0x434F4C42, 0x44415F4B, 0x205D5244, 0x52203B20, 0x203D2033, 0x6C622620, 0x5B6B636F, 0x622E5D69
    .WORD 0x6B636F6C, 0x64646120, 0x73736572, 0x2020200A, 0x504D4320, 0x20335220, 0x20203152, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x20734920, 0x73696874, 0x72756F20, 0x6F6C6220, 0x0A3F6B63, 0x20202020
    .WORD 0x20514542, 0x65657266, 0x756F665F, 0x2020646E, 0x20202020, 0x203B2020, 0x2C736559, 0x20657720
    .WORD 0x6E756F66, 0x74692064, 0x20200A21, 0x200A2020, 0x3B202020, 0x746F4E20, 0x69687420, 0x6C622073
    .WORD 0x2C6B636F, 0x79727420, 0x78656E20, 0x20200A74, 0x44412020, 0x34522044, 0x20345220, 0x20200A31
    .WORD 0x20422020, 0x65657266, 0x6F6F6C5F, 0x660A0A70, 0x5F656572, 0x6E756F66, 0x200A3A64, 0x3B202020
    .WORD 0x65745320, 0x3A332070, 0x20655720, 0x6E756F66, 0x68742064, 0x6C622065, 0x206B636F, 0x63736564
    .WORD 0x74706972, 0x6120726F, 0x32522074, 0x2020200A, 0x4D203B20, 0x206B7261, 0x61207469, 0x72662073
    .WORD 0x73206565, 0x616D206F, 0x636F6C6C, 0x6E616320, 0x65737520, 0x20746920, 0x69616761, 0x20200A6E
    .WORD 0x200A2020, 0x4C202020, 0x33522049, 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x52203B20
    .WORD 0x203D2033, 0x66282030, 0x29656572, 0x2020200A, 0x57545320, 0x20335220, 0x2032525B, 0x4C42202B
    .WORD 0x5F4B434F, 0x44455355, 0x3B20205D, 0x6C622620, 0x5B6B636F, 0x752E5D69, 0x20646573, 0x0A30203D
    .WORD 0x20202020, 0x2020200A, 0x4E203B20, 0x3A45544F, 0x20655720, 0x4E206F64, 0x6320544F, 0x7261656C
    .WORD 0x65687420, 0x64646120, 0x73736572, 0x20726F20, 0x657A6973, 0x2020200A, 0x54203B20, 0x20796568
    .WORD 0x79617473, 0x206E6920, 0x20656874, 0x6C626174, 0x6E612065, 0x69772064, 0x62206C6C, 0x766F2065
    .WORD 0x72777265, 0x65747469, 0x6877206E, 0x72206E65, 0x65737565, 0x20200A64, 0x660A2020, 0x5F656572
    .WORD 0x656E6F64, 0x20200A3A, 0x203B2020, 0x61656C43, 0x7075206E, 0x646E6120, 0x74657220, 0x0A6E7275
    .WORD 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A2D2D2D, 0x616D203B, 0x636F6C6C, 0x696E695F, 0x202D2074, 0x74696E49, 0x696C6169, 0x7420657A
    .WORD 0x6D206568, 0x726F6D65, 0x6C612079, 0x61636F6C, 0x0A726F74, 0x203B0A3B, 0x61656C43, 0x74207372
    .WORD 0x65206568, 0x7269746E, 0x6C622065, 0x206B636F, 0x6C626174, 0x6F732065, 0x6C6C6120, 0x6F6C6220
    .WORD 0x20736B63, 0x20657261, 0x6B72616D, 0x61206465, 0x72662073, 0x3B0A6565, 0x6F685320, 0x20646C75
    .WORD 0x63206562, 0x656C6C61, 0x6E6F2064, 0x61206563, 0x79732074, 0x6D657473, 0x61747320, 0x70757472
    .WORD 0x66656220, 0x2065726F, 0x6E697375, 0x616D2067, 0x636F6C6C, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6C616D0A, 0x5F636F6C, 0x74696E69, 0x20200A3A, 0x203B2020, 0x65766153, 0x67657220
    .WORD 0x65747369, 0x200A7372, 0x50202020, 0x20485355, 0x2020524C, 0x20200A20, 0x203B2020, 0x70657453
    .WORD 0x203A3120, 0x61656C43, 0x68742072, 0x6E652065, 0x65726974, 0x6F6C6220, 0x74206B63, 0x656C6261
    .WORD 0x2020200A, 0x53203B20, 0x61207465, 0x62206C6C, 0x73657479, 0x206E6920, 0x636F6C62, 0x61745F6B
    .WORD 0x20656C62, 0x30206F74, 0x2020200A, 0x20494C20, 0x62203152, 0x6B636F6C, 0x6261745F, 0x2020656C
    .WORD 0x3B202020, 0x20315220, 0x7473203D, 0x20747261, 0x72646461, 0x20737365, 0x7420666F, 0x656C6261
    .WORD 0x2020200A, 0x20494C20, 0x4D203352, 0x425F5841, 0x4B434F4C, 0x202A2053, 0x434F4C42, 0x45445F4B
    .WORD 0x20204353, 0x3352203B, 0x74203D20, 0x6C61746F, 0x74796220, 0x74207365, 0x6C63206F, 0x0A726165
    .WORD 0x20202020, 0x6C616D0A, 0x5F636F6C, 0x74696E69, 0x6F6F6C5F, 0x200A3A70, 0x43202020, 0x5220504D
    .WORD 0x20302033, 0x20202020, 0x20202020, 0x20202020, 0x48203B20, 0x20657661, 0x63206577, 0x7261656C
    .WORD 0x61206465, 0x62206C6C, 0x73657479, 0x20200A3F, 0x45422020, 0x616D2051, 0x636F6C6C, 0x696E695F
    .WORD 0x6F645F74, 0x2020656E, 0x6559203B, 0x77202C73, 0x65722765, 0x6E6F6420, 0x20200A65, 0x200A2020
    .WORD 0x4C202020, 0x32522049, 0x20203020, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2032
    .WORD 0x76282030, 0x65756C61, 0x206F7420, 0x74697277, 0x200A2965, 0x53202020, 0x52204254, 0x525B2032
    .WORD 0x20205D31, 0x20202020, 0x20202020, 0x53203B20, 0x65726F74, 0x61203020, 0x75632074, 0x6E657272
    .WORD 0x64612074, 0x73657264, 0x20200A73, 0x44412020, 0x31522044, 0x20315220, 0x20202031, 0x20202020
    .WORD 0x20202020, 0x6F4D203B, 0x74206576, 0x656E206F, 0x62207478, 0x0A657479, 0x20202020, 0x20425553
    .WORD 0x52203352, 0x20312033, 0x20202020, 0x20202020, 0x203B2020, 0x72636544, 0x6E656D65, 0x79622074
    .WORD 0x63206574, 0x746E756F, 0x200A7265, 0x42202020, 0x6C616D20, 0x5F636F6C, 0x74696E69, 0x6F6F6C5F
    .WORD 0x20202070, 0x43203B20, 0x69746E6F, 0x0A65756E, 0x20202020, 0x6C616D0A, 0x5F636F6C, 0x74696E69
    .WORD 0x6E6F645F, 0x200A3A65, 0x3B202020, 0x656C4320, 0x75206E61, 0x6E612070, 0x65722064, 0x6E727574
    .WORD 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x3D3B0A0A, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x203B0A3D, 0x45544E49, 0x4C414E52, 0x4C454820, 0x53524550, 0x3D3D3B0A, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D203B0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x6F43203B, 0x7265766E, 0x6E692074, 0x65676574, 0x6E692072
    .WORD 0x74206F74, 0x6F706D65, 0x79726172, 0x66756220, 0x0A726566, 0x203B0A3B, 0x20203952, 0x7563203D
    .WORD 0x6E657272, 0x61762074, 0x0A65756C, 0x3152203B, 0x203D2030, 0x6E696F70, 0x20726574, 0x6E206F74
    .WORD 0x20747865, 0x65657266, 0x74796220, 0x6E692065, 0x6D657420, 0x61726F70, 0x62207972, 0x65666675
    .WORD 0x203B0A72, 0x20313152, 0x6162203D, 0x28206573, 0x31202C32, 0x6F202C30, 0x36312072, 0x203B0A29
    .WORD 0x20203452, 0x756E203D, 0x7265626D, 0x20666F20, 0x69676964, 0x73207374, 0x65726F74, 0x0A3B0A64
    .WORD 0x6145203B, 0x64206863, 0x73697669, 0x206E6F69, 0x646F7270, 0x73656375, 0x0A3B0A3A, 0x2020203B
    .WORD 0x746F7571, 0x746E6569, 0x203D2020, 0x756C6176, 0x202F2065, 0x65736162, 0x20203B0A, 0x6D657220
    .WORD 0x646E6961, 0x3D207265, 0x6C617620, 0x25206575, 0x73616220, 0x0A3B0A65, 0x6854203B, 0x65722065
    .WORD 0x6E69616D, 0x20726564, 0x74207369, 0x6E206568, 0x20747865, 0x69676964, 0x3B0A2E74, 0x44203B0A
    .WORD 0x74696769, 0x72612073, 0x65672065, 0x6172656E, 0x20646574, 0x6B636162, 0x64726177, 0x66202C73
    .WORD 0x6520726F, 0x706D6178, 0x0A3A656C, 0x203B0A3B, 0x32312020, 0x0A3B0A33, 0x6966203B, 0x20747372
    .WORD 0x646F7270, 0x73656375, 0x0A3B0A3A, 0x2020203B, 0x203B0A33, 0x0A322020, 0x2020203B, 0x0A3B0A31
    .WORD 0x6F73203B, 0x65687420, 0x6D657420, 0x61726F70, 0x62207972, 0x65666675, 0x6F632072, 0x6961746E
    .WORD 0x0A3A736E, 0x203B0A3B, 0x33222020, 0x0A223132, 0x203B0A3B, 0x20656854, 0x79706F63, 0x6F6F6C20
    .WORD 0x65622070, 0x20776F6C, 0x6C6C6977, 0x76657220, 0x65737265, 0x20746920, 0x6F746E69, 0x32312220
    .WORD 0x0A2E2233, 0x203B0A3B, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x616F7469, 0x726F635F
    .WORD 0x203B0A65, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x203B0A7C, 0x20202020
    .WORD 0x20202020, 0x8C94E220, 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x94E28094, 0x8094E280
    .WORD 0xE28094E2, 0x94E28094, 0x8094E2B4, 0xE28094E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x94E28094
    .WORD 0x8094E280, 0xE28094E2, 0x3B0A9094, 0x20202020, 0x20202020, 0x94E22020, 0x20202082, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x94E22020, 0x203B0A82, 0x20202020, 0x20395220, 0x6176203D
    .WORD 0x2065756C, 0x20202020, 0x20202020, 0x31522020, 0x203D2030, 0x706D6574, 0x3B0A5D5B, 0x20202020
    .WORD 0x20202020, 0x94E22020, 0x20202082, 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x94E22020
    .WORD 0x203B0A82, 0x20202020, 0x20202020, 0x9386E220, 0x20202020, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x9386E220, 0x20203B0A, 0x20202020, 0x56494420, 0x444F4D2F, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x0A425453, 0x2020203B, 0x20202020, 0xE2202020, 0x20208294, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x20202020, 0xE2202020, 0x3B0A8294, 0x20202020, 0x8C94E220, 0xE28094E2
    .WORD 0x94E28094, 0x8094E280, 0xE2B494E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x20209094, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x94E22020, 0x203B0A82, 0x20202020, 0x209386E2, 0x20202020, 0x20202020
    .WORD 0x209386E2, 0x20202020, 0x20202020, 0x20202020, 0xE2202020, 0x3B0A8294, 0x3D365220, 0x746F7571
    .WORD 0x746E6569, 0x3D375220, 0x616D6572, 0x65646E69, 0x20202072, 0x20202020, 0x0A8294E2, 0x2020203B
    .WORD 0x94E22020, 0x20202082, 0x20202020, 0x94E22020, 0x20202082, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x8294E220, 0x20203B0A, 0xE2202020, 0x20208294, 0x20202020, 0xE2202020, 0x94E29494, 0x8094E280
    .WORD 0x209286E2, 0x49435341, 0x94E22049, 0x8094E280, 0xE28094E2, 0x2D2D8094, 0x0A9894E2, 0x2020203B
    .WORD 0x94E22020, 0x203B0A82, 0x20202020, 0xE29494E2, 0x94E28094, 0x8094E280, 0xE28094E2, 0x52209286
    .WORD 0x6F662039, 0x656E2072, 0x6C207478, 0x0A706F6F, 0x2038523B, 0x73656420, 0x616E6974, 0x6E6F6974
    .WORD 0x696F7020, 0x7265746E, 0x39523B0A, 0x75632020, 0x6E657272, 0x6E692074, 0x65676574, 0x61762072
    .WORD 0x0A65756C, 0x3031523B, 0x6D657420, 0x61726F70, 0x622D7972, 0x65666675, 0x6F702072, 0x65746E69
    .WORD 0x523B0A72, 0x62203131, 0x0A657361, 0x3231523B, 0x67697320, 0x6C66206E, 0x3B0A6761, 0x20203452
    .WORD 0x69676964, 0x6F632074, 0x65746E75, 0x523B0A72, 0x71202036, 0x69746F75, 0x0A746E65, 0x2037523B
    .WORD 0x6D657220, 0x646E6961, 0x3B0A7265, 0x20203552, 0x61726373, 0x20686374, 0x6964202F, 0x6F736976
    .WORD 0x203B0A72, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x74690A0A, 0x635F616F, 0x3A65726F, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x53555020, 0x35522048, 0x2020200A, 0x53555020, 0x36522048, 0x2020200A, 0x53555020, 0x37522048
    .WORD 0x2020200A, 0x53555020, 0x38522048, 0x2020200A, 0x53555020, 0x39522048, 0x2020200A, 0x53555020
    .WORD 0x31522048, 0x20200A30, 0x55502020, 0x52204853, 0x200A3131, 0x50202020, 0x20485355, 0x20323152
    .WORD 0x20200A0A, 0x4F4D2020, 0x52202056, 0x52202038, 0x20202031, 0x20202020, 0x3B202020, 0x76615320
    .WORD 0x65642065, 0x6E697473, 0x6F697461, 0x20200A6E, 0x4F4D2020, 0x52202056, 0x52202039, 0x20202032
    .WORD 0x20202020, 0x3B202020, 0x726F5720, 0x676E696B, 0x6C617620, 0x200A6575, 0x4D202020, 0x2020564F
    .WORD 0x20313152, 0x20203352, 0x20202020, 0x20202020, 0x6142203B, 0x200A6573, 0x4D202020, 0x2020564F
    .WORD 0x20323152, 0x20203452, 0x20202020, 0x20202020, 0x6953203B, 0x66206E67, 0x0A67616C, 0x20202020
    .WORD 0x6C41203B, 0x61636F6C, 0x74206574, 0x20706D65, 0x66667562, 0x28207265, 0x657A6973, 0x73617020
    .WORD 0x20646573, 0x52206E69, 0x200A2935, 0x53202020, 0x20204255, 0x53205053, 0x35522050, 0x2020200A
    .WORD 0x564F4D20, 0x31522020, 0x50532030, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220
    .WORD 0x20726566, 0x6E696F70, 0x0A726574, 0x20200A20, 0x55502020, 0x52204853, 0x20202035, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x76617320, 0x35522065, 0x726F6620, 0x61726620, 0x6C20656D, 0x65766165
    .WORD 0x2020200A, 0x53555020, 0x38522048, 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x65766173
    .WORD 0x73657220, 0x20746C75, 0x65667562, 0x20200A72, 0x200A2020, 0x3B202020, 0x65684320, 0x66206B63
    .WORD 0x7320726F, 0x206E6769, 0x20666928, 0x6E676973, 0x61206465, 0x6E20646E, 0x74616765, 0x29657669
    .WORD 0x2020200A, 0x504D4320, 0x31522020, 0x0A312032, 0x20202020, 0x20454E42, 0x6F746920, 0x6F635F61
    .WORD 0x755F6572, 0x6769736E, 0x0A64656E, 0x20202020, 0x2020200A, 0x504D4320, 0x39522020, 0x200A3020
    .WORD 0x42202020, 0x20204547, 0x616F7469, 0x726F635F, 0x6E755F65, 0x6E676973, 0x200A6465, 0x0A202020
    .WORD 0x20202020, 0x654E203B, 0x69746167, 0x6E206576, 0x65626D75, 0x202D2072, 0x20646461, 0x756E696D
    .WORD 0x69732073, 0x200A6E67, 0x4C202020, 0x20202049, 0x34203252, 0x20202035, 0x273B2020, 0x200A272D
    .WORD 0x53202020, 0x20204254, 0x5B203252, 0x0A5D3852, 0x20202020, 0x20444441, 0x20385220, 0x31203852
    .WORD 0x2020200A, 0x544F4E20, 0x39522020, 0x0A395220, 0x20202020, 0x20444441, 0x20395220, 0x31203952
    .WORD 0x2020200A, 0x454E3B20, 0x52202047, 0x20202039, 0x20202020, 0x20202020, 0x3B202020, 0x6B614D20
    .WORD 0x6F702065, 0x69746973, 0x200A6576, 0x0A202020, 0x616F7469, 0x726F635F, 0x6E755F65, 0x6E676973
    .WORD 0x0A3A6465, 0x20202020, 0x7053203B, 0x61696365, 0x6163206C, 0x203A6573, 0x6F72657A, 0x2020200A
    .WORD 0x504D4320, 0x39522020, 0x200A3020, 0x42202020, 0x2020454E, 0x616F7469, 0x726F635F, 0x6F635F65
    .WORD 0x7265766E, 0x20200A74, 0x200A2020, 0x4C202020, 0x20202049, 0x34203252, 0x20202038, 0x27203B20
    .WORD 0x200A2730, 0x53202020, 0x20204254, 0x5B203252, 0x0A5D3852, 0x20202020, 0x20444441, 0x20385220
    .WORD 0x31203852, 0x2020200A, 0x20494C20, 0x32522020, 0x200A3020, 0x53202020, 0x20204254, 0x5B203252
    .WORD 0x0A5D3852, 0x20202020, 0x20202042, 0x6F746920, 0x6F635F61, 0x665F6572, 0x73696E69, 0x690A0A68
    .WORD 0x5F616F74, 0x65726F63, 0x6E6F635F, 0x74726576, 0x200A0A3A, 0x4C202020, 0x52202049, 0x20302034
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x203D2034, 0x69676964, 0x6F632074
    .WORD 0x65746E75, 0x690A0A72, 0x5F616F74, 0x65726F63, 0x7669645F, 0x706F6F6C, 0x20200A3A, 0x203B2020
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2020200A
    .WORD 0x44203B20, 0x64697669, 0x75632065, 0x6E657272, 0x61762074, 0x2065756C, 0x62207962, 0x0A657361
    .WORD 0x20202020, 0x20200A3B, 0x203B2020, 0x20203952, 0x7563203D, 0x6E657272, 0x61762074, 0x0A65756C
    .WORD 0x20202020, 0x3152203B, 0x203D2031, 0x65736162, 0x2020200A, 0x200A3B20, 0x3B202020, 0x20655720
    .WORD 0x6465656E, 0x206F7420, 0x7065656B, 0x20395220, 0x68636E75, 0x65676E61, 0x6F662064, 0x4F4D2072
    .WORD 0x73202C44, 0x7375206F, 0x35522065, 0x2020200A, 0x61203B20, 0x68742073, 0x49442065, 0x6F732056
    .WORD 0x65637275, 0x20200A2E, 0x203B2020, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2020200A, 0x564F4D20, 0x20355220, 0x200A3952, 0x3B202020, 0x20365220
    .WORD 0x7571203D, 0x6569746F, 0x200A746E, 0x44202020, 0x52205649, 0x35522036, 0x31315220, 0x2020200A
    .WORD 0x52203B20, 0x203D2037, 0x616D6572, 0x65646E69, 0x20200A72, 0x4F4D2020, 0x37522044, 0x20395220
    .WORD 0x0A313152, 0x20202020, 0x2D2D203B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x200A2D2D, 0x3B202020, 0x6E6F4320, 0x74726576, 0x6D657220, 0x646E6961, 0x74207265
    .WORD 0x5341206F, 0x0A494943, 0x20202020, 0x20200A3B, 0x203B2020, 0x20726F46, 0x65736162, 0x61203220
    .WORD 0x3120646E, 0x200A3A30, 0x3B202020, 0x20202020, 0x2E2E3020, 0x3E2D2039, 0x27302720, 0x39272E2E
    .WORD 0x20200A27, 0x0A3B2020, 0x20202020, 0x6F46203B, 0x61622072, 0x31206573, 0x200A3A36, 0x3B202020
    .WORD 0x20202020, 0x2E2E3020, 0x2D202039, 0x3027203E, 0x272E2E27, 0x200A2739, 0x3B202020, 0x20202020
    .WORD 0x2E303120, 0x2035312E, 0x27203E2D, 0x2E2E2741, 0x0A274627, 0x20202020, 0x2D2D203B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x200A2D2D, 0x43202020, 0x5220504D
    .WORD 0x31203131, 0x20200A36, 0x45422020, 0x74692051, 0x635F616F, 0x5F65726F, 0x5F786568, 0x69676964
    .WORD 0x20200A74, 0x203B2020, 0x65736142, 0x6F203220, 0x61622072, 0x31206573, 0x20200A30, 0x44412020
    .WORD 0x37522044, 0x20375220, 0x20203834, 0x20202020, 0x20202020, 0x3B202020, 0x27302720, 0x64202B20
    .WORD 0x74696769, 0x2020200A, 0x69204220, 0x5F616F74, 0x65726F63, 0x6F74735F, 0x0A0A6572, 0x616F7469
    .WORD 0x726F635F, 0x65685F65, 0x69645F78, 0x3A746967, 0x2020200A, 0x504D4320, 0x20375220, 0x20200A39
    .WORD 0x47422020, 0x74692054, 0x635F616F, 0x5F65726F, 0x5F786568, 0x7474656C, 0x200A7265, 0x3B202020
    .WORD 0x2E2E3020, 0x20200A39, 0x44412020, 0x37522044, 0x20375220, 0x20203834, 0x20202020, 0x20202020
    .WORD 0x3B202020, 0x27302720, 0x64202B20, 0x74696769, 0x2020200A, 0x69204220, 0x5F616F74, 0x65726F63
    .WORD 0x6F74735F, 0x0A0A6572, 0x616F7469, 0x726F635F, 0x65685F65, 0x656C5F78, 0x72657474, 0x20200A3A
    .WORD 0x203B2020, 0x2E2E3031, 0x200A3531, 0x53202020, 0x52204255, 0x37522037, 0x0A303120, 0x20202020
    .WORD 0x20444441, 0x52203752, 0x35362037, 0x20202020, 0x20202020, 0x20202020, 0x27203B20, 0x2B202741
    .WORD 0x69642820, 0x20746967, 0x3031202D, 0x3B0A0A29, 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x203B0A3D, 0x726F7453, 0x65672065, 0x6172656E
    .WORD 0x20646574, 0x69676964, 0x203B0A74, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x74690A0A, 0x635F616F, 0x5F65726F, 0x726F7473, 0x200A3A65
    .WORD 0x0A202020, 0x20202020, 0x20425453, 0x5B203752, 0x5D303152, 0x20202020, 0x3031523B, 0x20736920
    .WORD 0x20656874, 0x706D6574, 0x7261726F, 0x75622D79, 0x72656666, 0x696F7020, 0x7265746E, 0x200A0A2E
    .WORD 0x41202020, 0x52204444, 0x52203031, 0x31203031, 0x2020200A, 0x44444120, 0x20345220, 0x31203452
    .WORD 0x20202020, 0x4F203B20, 0x6D20656E, 0x2065726F, 0x69676964, 0x65672074, 0x6172656E, 0x0A646574
    .WORD 0x2020200A, 0x2D203B20, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x0A2D2D2D, 0x20202020, 0x6854203B, 0x75712065, 0x6569746F, 0x6220746E, 0x6D6F6365, 0x74207365
    .WORD 0x76206568, 0x65756C61, 0x726F6620, 0x65687420, 0x78656E20, 0x74692074, 0x74617265, 0x2E6E6F69
    .WORD 0x2020200A, 0x200A3B20, 0x3B202020, 0x61784520, 0x656C706D, 0x20200A3A, 0x0A3B2020, 0x20202020
    .WORD 0x2020203B, 0x20333231, 0x3031202F, 0x31203D20, 0x20200A32, 0x203B2020, 0x31202020, 0x202F2032
    .WORD 0x3D203031, 0x200A3120, 0x3B202020, 0x20202020, 0x2F203120, 0x20303120, 0x0A30203D, 0x20202020
    .WORD 0x2D2D203B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A0A2D2D
    .WORD 0x20202020, 0x20564F4D, 0x52203952, 0x200A0A36, 0x3B202020, 0x6E6F4320, 0x756E6974, 0x6E752065
    .WORD 0x206C6974, 0x746F7571, 0x746E6569, 0x63656220, 0x73656D6F, 0x72657A20, 0x20200A6F, 0x4D432020
    .WORD 0x39522050, 0x200A3020, 0x42202020, 0x6920454E, 0x5F616F74, 0x65726F63, 0x7669645F, 0x706F6F6C
    .WORD 0x203B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x44203B0A, 0x74696769, 0x72612073, 0x6F6E2065, 0x74732077, 0x6465726F, 0x63616220
    .WORD 0x7261776B, 0x69207364, 0x6574206E, 0x726F706D, 0x20797261, 0x66667562, 0x0A2E7265, 0x6574203B
    .WORD 0x3D20706D, 0x32332220, 0x3B0A2231, 0x52203B0A, 0x70203031, 0x746E696F, 0x756A2073, 0x41207473
    .WORD 0x52455446, 0x65687420, 0x73616C20, 0x69642074, 0x2E746967, 0x3B0A3B0A, 0x766F4D20, 0x61622065
    .WORD 0x74206B63, 0x6874206F, 0x69662065, 0x206C616E, 0x69676964, 0x3B0A3A74, 0x3D3D3D20, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x200A0A3D, 0x53202020
    .WORD 0x52204255, 0x52203031, 0x31203031, 0x203B0A0A, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x43203B0A, 0x2079706F, 0x69676964, 0x66207374
    .WORD 0x206D6F72, 0x706D6574, 0x7261726F, 0x75622079, 0x72656666, 0x63616220, 0x7261776B, 0x3B0A7364
    .WORD 0x3D3D3D20, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x690A0A3D, 0x5F616F74, 0x65726F63, 0x706F635F, 0x200A3A79, 0x43202020, 0x5220504D, 0x0A302034
    .WORD 0x20202020, 0x20514542, 0x616F7469, 0x726F635F, 0x6F645F65, 0x200A656E, 0x3B202020, 0x61655220
    .WORD 0x616C2064, 0x67207473, 0x72656E65, 0x64657461, 0x67696420, 0x200A7469, 0x4C202020, 0x52204244
    .WORD 0x525B2032, 0x0A5D3031, 0x20202020, 0x7257203B, 0x20657469, 0x74207469, 0x6564206F, 0x6E697473
    .WORD 0x6F697461, 0x20200A6E, 0x54532020, 0x32522042, 0x38525B20, 0x20200A5D, 0x44412020, 0x38522044
    .WORD 0x20385220, 0x20200A31, 0x203B2020, 0x65766F4D, 0x63616220, 0x7261776B, 0x74207364, 0x756F7268
    .WORD 0x74206867, 0x6F706D65, 0x79726172, 0x66756220, 0x0A726566, 0x20202020, 0x20425553, 0x20303152
    .WORD 0x20303152, 0x20200A31, 0x203B2020, 0x20656E4F, 0x7373656C, 0x67696420, 0x200A7469, 0x53202020
    .WORD 0x52204255, 0x34522034, 0x200A3120, 0x42202020, 0x6F746920, 0x6F635F61, 0x635F6572, 0x0A79706F
    .WORD 0x6F74690A, 0x6F635F61, 0x645F6572, 0x3A656E6F, 0x2020200A, 0x20494C20, 0x32522020, 0x200A3020
    .WORD 0x53202020, 0x20204254, 0x5B203252, 0x205D3852, 0x20202020, 0x20202020, 0x754E203B, 0x74206C6C
    .WORD 0x696D7265, 0x6574616E, 0x2020200A, 0x74690A20, 0x635F616F, 0x5F65726F, 0x696E6966, 0x0A3A6873
    .WORD 0x20202020, 0x20504F50, 0x20315220, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x72757465
    .WORD 0x726F206E, 0x6E696769, 0x70206C61, 0x746E696F, 0x200A7265, 0x50202020, 0x2020504F, 0x200A3552
    .WORD 0x3B202020, 0x656C4320, 0x75206E61, 0x65742070, 0x6220706D, 0x65666675, 0x20200A72, 0x44412020
    .WORD 0x53202044, 0x50532050, 0x0A355220, 0x20202020, 0x2020200A, 0x504F5020, 0x32315220, 0x2020200A
    .WORD 0x504F5020, 0x31315220, 0x2020200A, 0x504F5020, 0x30315220, 0x2020200A, 0x504F5020, 0x0A395220
    .WORD 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x5220504F, 0x20200A37, 0x4F502020, 0x36522050
    .WORD 0x2020200A, 0x504F5020, 0x0A355220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x6F746920
    .WORD 0x65645F61, 0x202D2063, 0x69636544, 0x206C616D, 0x766E6F63, 0x69737265, 0x77206E6F, 0x70706172
    .WORD 0x3B0A7265, 0x52203B0A, 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x3B0A7265
    .WORD 0x20325220, 0x6973203D, 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E
    .WORD 0x3D203152, 0x69726F20, 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x6365645F
    .WORD 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20, 0x20313120
    .WORD 0x69676964, 0x2B207374, 0x67697320, 0x202B206E, 0x6C6C756E, 0x31203D20, 0x79622033, 0x0A736574
    .WORD 0x20202020, 0x2020494C, 0x20335220, 0x20203031, 0x20202020, 0x20202020, 0x42203B20, 0x20657361
    .WORD 0x200A3031, 0x4C202020, 0x20202049, 0x31203452, 0x20202020, 0x20202020, 0x20202020, 0x6953203B
    .WORD 0x64656E67, 0x2020200A, 0x20494C20, 0x35522020, 0x20333120, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x706D6554, 0x66756220, 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F
    .WORD 0x0A65726F, 0x20202020, 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74
    .WORD 0x20786568, 0x6548202D, 0x65646178, 0x616D6963, 0x6F63206C, 0x7265766E, 0x6E6F6973, 0x61727720
    .WORD 0x72657070, 0x3B0A3B0A, 0x20315220, 0x6564203D, 0x6E697473, 0x6F697461, 0x7562206E, 0x72656666
    .WORD 0x52203B0A, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465
    .WORD 0x203A736E, 0x3D203152, 0x69726F20, 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469
    .WORD 0x7865685F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020, 0x3B202020, 0x78614D20
    .WORD 0x64203820, 0x74696769, 0x202B2073, 0x6C6C756E, 0x39203D20, 0x74796220, 0x200A7365, 0x4C202020
    .WORD 0x20202049, 0x31203352, 0x20202036, 0x20202020, 0x20202020, 0x6142203B, 0x31206573, 0x20200A36
    .WORD 0x494C2020, 0x52202020, 0x20302034, 0x20202020, 0x20202020, 0x3B202020, 0x736E5520, 0x656E6769
    .WORD 0x73282064, 0x73776F68, 0x77617220, 0x74696220, 0x200A2973, 0x4C202020, 0x20202049, 0x39203552
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x6554203B, 0x6220706D, 0x65666675, 0x69732072, 0x200A657A
    .WORD 0x43202020, 0x204C4C41, 0x616F7469, 0x726F635F, 0x20200A65, 0x200A2020, 0x50202020, 0x2020504F
    .WORD 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x7469203B, 0x6F5F616F, 0x2D207463, 0x74634F20, 0x63206C61, 0x65766E6F
    .WORD 0x6F697372, 0x7277206E, 0x65707061, 0x0A3B0A72, 0x3152203B, 0x64203D20, 0x69747365, 0x6974616E
    .WORD 0x62206E6F, 0x65666675, 0x203B0A72, 0x3D203252, 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574
    .WORD 0x203B0A72, 0x75746552, 0x3A736E72, 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675
    .WORD 0x6F702072, 0x65746E69, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6F74690A, 0x636F5F61, 0x200A3A74, 0x50202020, 0x20485355, 0x200A524C, 0x0A202020
    .WORD 0x20202020, 0x614D203B, 0x32312078, 0x67696420, 0x20737469, 0x756E202B, 0x3D206C6C, 0x20333120
    .WORD 0x65747962, 0x20200A73, 0x494C2020, 0x52202020, 0x20382033, 0x20202020, 0x20202020, 0x3B202020
    .WORD 0x73614220, 0x0A382065, 0x20202020, 0x2020494C, 0x20345220, 0x20202030, 0x20202020, 0x20202020
    .WORD 0x55203B20, 0x6769736E, 0x2064656E, 0x6F687328, 0x72207377, 0x62207761, 0x29737469, 0x2020200A
    .WORD 0x20494C20, 0x35522020, 0x20333120, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220
    .WORD 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020
    .WORD 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x206E6962, 0x6942202D
    .WORD 0x7972616E, 0x6E6F6320, 0x73726576, 0x206E6F69, 0x70617277, 0x0A726570, 0x203B0A3B, 0x3D203152
    .WORD 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220, 0x0A726566, 0x3252203B, 0x75203D20, 0x6769736E
    .WORD 0x2064656E, 0x65746E69, 0x0A726567, 0x6552203B, 0x6E727574, 0x52203A73, 0x203D2031, 0x6769726F
    .WORD 0x6C616E69, 0x66756220, 0x20726566, 0x6E696F70, 0x0A726574, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x690A2D2D, 0x5F616F74, 0x3A6E6962, 0x2020200A, 0x53555020
    .WORD 0x524C2048, 0x2020200A, 0x20200A20, 0x203B2020, 0x2078614D, 0x62203233, 0x20737469, 0x756E202B
    .WORD 0x3D206C6C, 0x20333320, 0x65747962, 0x20200A73, 0x494C2020, 0x52202020, 0x20322033, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x73614220, 0x0A322065, 0x20202020, 0x2020494C, 0x20345220, 0x20202030
    .WORD 0x20202020, 0x20202020, 0x55203B20, 0x6769736E, 0x2064656E, 0x6F687328, 0x72207377, 0x62207761
    .WORD 0x29737469, 0x2020200A, 0x20494C20, 0x35522020, 0x20333320, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x706D6554, 0x66756220, 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F
    .WORD 0x0A65726F, 0x20202020, 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74
    .WORD 0x6E676973, 0x685F6465, 0x2D207865, 0x67695320, 0x2064656E, 0x61786568, 0x69636564, 0x206C616D
    .WORD 0x70617277, 0x0A726570, 0x203B0A3B, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220
    .WORD 0x0A726566, 0x3252203B, 0x73203D20, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x75746552
    .WORD 0x3A736E72, 0x20315220, 0x726F203D, 0x6E696769, 0x62206C61, 0x65666675, 0x6F702072, 0x65746E69
    .WORD 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6F74690A
    .WORD 0x69735F61, 0x64656E67, 0x7865685F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020
    .WORD 0x3B202020, 0x78614D20, 0x64203820, 0x74696769, 0x202B2073, 0x6E676973, 0x6E202B20, 0x206C6C75
    .WORD 0x3031203D, 0x74796220, 0x200A7365, 0x4C202020, 0x20202049, 0x31203352, 0x20202036, 0x20202020
    .WORD 0x20202020, 0x6142203B, 0x31206573, 0x20200A36, 0x494C2020, 0x52202020, 0x20312034, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x67695320, 0x2064656E, 0x6F687328, 0x73207377, 0x296E6769, 0x2020200A
    .WORD 0x20494C20, 0x35522020, 0x20303120, 0x20202020, 0x20202020, 0x203B2020, 0x706D6554, 0x66756220
    .WORD 0x20726566, 0x657A6973, 0x2020200A, 0x4C414320, 0x7469204C, 0x635F616F, 0x0A65726F, 0x20202020
    .WORD 0x2020200A, 0x504F5020, 0x524C2020, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x69203B0A, 0x5F616F74, 0x6E676973, 0x625F6465
    .WORD 0x2D206E69, 0x67695320, 0x2064656E, 0x616E6962, 0x77207972, 0x70706172, 0x3B0A7265, 0x52203B0A
    .WORD 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x3B0A7265, 0x20325220, 0x6973203D
    .WORD 0x64656E67, 0x746E6920, 0x72656765, 0x52203B0A, 0x72757465, 0x203A736E, 0x3D203152, 0x69726F20
    .WORD 0x616E6967, 0x7562206C, 0x72656666, 0x696F7020, 0x7265746E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x616F7469, 0x6769735F, 0x5F64656E, 0x3A6E6962
    .WORD 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x20200A20, 0x203B2020, 0x2078614D, 0x62203233
    .WORD 0x20737469, 0x6973202B, 0x2B206E67, 0x6C756E20, 0x203D206C, 0x62203433, 0x73657479, 0x2020200A
    .WORD 0x20494C20, 0x33522020, 0x20203220, 0x20202020, 0x20202020, 0x203B2020, 0x65736142, 0x200A3220
    .WORD 0x4C202020, 0x20202049, 0x31203452, 0x20202020, 0x20202020, 0x20202020, 0x6953203B, 0x64656E67
    .WORD 0x68732820, 0x2073776F, 0x6E676973, 0x20200A29, 0x494C2020, 0x52202020, 0x34332035, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x6D655420, 0x75622070, 0x72656666, 0x7A697320, 0x20200A65, 0x41432020
    .WORD 0x69204C4C, 0x5F616F74, 0x65726F63, 0x2020200A, 0x20200A20, 0x4F502020, 0x4C202050, 0x20200A52
    .WORD 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72747320, 0x28797063
    .WORD 0x74736564, 0x7273202C, 0x3B0A2963, 0x43203B0A, 0x6569706F, 0x74732073, 0x676E6972, 0x6F726620
    .WORD 0x7273206D, 0x6F742063, 0x73656420, 0x6E692074, 0x64756C63, 0x20676E69, 0x6D726574, 0x74616E69
    .WORD 0x20676E69, 0x6C6C756E, 0x61686320, 0x74636172, 0x3B0A7265, 0x49203B0A, 0x7475706E, 0x203B0A3A
    .WORD 0x31522020, 0x64203D20, 0x69747365, 0x6974616E, 0x70206E6F, 0x746E696F, 0x3B0A7265, 0x52202020
    .WORD 0x203D2032, 0x72756F73, 0x70206563, 0x746E696F, 0x3B0A7265, 0x4F203B0A, 0x75707475, 0x3B0A3A74
    .WORD 0x52202020, 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x6E696F70, 0x20726574, 0x69726F28
    .WORD 0x616E6967, 0x3B0A296C, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x730A2D2D, 0x70637274, 0x200A3A79
    .WORD 0x50202020, 0x20485355, 0x200A524C, 0x4D202020, 0x5220564F, 0x31522033, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x203B2020, 0x65766153, 0x69726F20, 0x616E6967, 0x6564206C, 0x6E697473, 0x6F697461
    .WORD 0x6F70206E, 0x65746E69, 0x20200A72, 0x4F4D2020, 0x34522056, 0x20325220, 0x20202020, 0x20202020
    .WORD 0x20202020, 0x53203B20, 0x20657661, 0x72756F73, 0x70206563, 0x746E696F, 0x200A7265, 0x0A202020
    .WORD 0x63727473, 0x6C5F7970, 0x3A706F6F, 0x2020200A, 0x42444C20, 0x20325220, 0x5D34525B, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6F4C203B, 0x62206461, 0x20657479, 0x6D6F7266, 0x756F7320, 0x0A656372
    .WORD 0x20202020, 0x20425453, 0x5B203252, 0x205D3152, 0x20202020, 0x20202020, 0x3B202020, 0x6F745320
    .WORD 0x62206572, 0x20657479, 0x64206F74, 0x69747365, 0x6974616E, 0x200A6E6F, 0x0A202020, 0x20202020
    .WORD 0x20504D43, 0x30203252, 0x20202020, 0x20202020, 0x20202020, 0x3B202020, 0x65684320, 0x69206B63
    .WORD 0x74692066, 0x6E207327, 0x206C6C75, 0x6D726574, 0x74616E69, 0x200A726F, 0x42202020, 0x73205145
    .WORD 0x70637274, 0x6F645F79, 0x2020656E, 0x20202020, 0x203B2020, 0x7A206649, 0x2C6F7265, 0x27657720
    .WORD 0x64206572, 0x0A656E6F, 0x20202020, 0x2020200A, 0x44444120, 0x20315220, 0x31203152, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6441203B, 0x636E6176, 0x65642065, 0x6E697473, 0x6F697461, 0x6F70206E
    .WORD 0x65746E69, 0x20200A72, 0x44412020, 0x34522044, 0x20345220, 0x20202031, 0x20202020, 0x20202020
    .WORD 0x41203B20, 0x6E617664, 0x73206563, 0x6372756F, 0x6F702065, 0x65746E69, 0x20200A72, 0x20422020
    .WORD 0x63727473, 0x6C5F7970, 0x0A706F6F, 0x20202020, 0x7274730A, 0x5F797063, 0x656E6F64, 0x20200A3A
    .WORD 0x4F4D2020, 0x31522056, 0x20335220, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x72757465
    .WORD 0x726F206E, 0x6E696769, 0x64206C61, 0x69747365, 0x6974616E, 0x70206E6F, 0x746E696F, 0x200A7265
    .WORD 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x0A0A0A54, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x0A3D3D3D, 0x4944203B, 0x54434552, 0x2059524F, 0x5245504F, 0x4F495441, 0x2D20534E, 0x74614D20
    .WORD 0x6E696863, 0x6F792067, 0x6B207275, 0x656E7265, 0x2073276C, 0x66726174, 0x65725F73, 0x69646461
    .WORD 0x3D3B0A72, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3B0A0A3D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x72694420, 0x6F746365, 0x73207972, 0x63757274, 0x65727574, 0x706F2820, 0x65757161
    .WORD 0x206F7420, 0x72657375, 0x2D3B0A29, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x452E0A2D, 0x44205551
    .WORD 0x465F5249, 0x20202C44, 0x20202020, 0x20203020, 0x20202020, 0x46203B20, 0x20656C69, 0x63736564
    .WORD 0x74706972, 0x2820726F, 0x79622034, 0x29736574, 0x51452E0A, 0x49442055, 0x464F5F52, 0x54455346
    .WORD 0x2020202C, 0x20202034, 0x20202020, 0x7543203B, 0x6E657272, 0x6F702074, 0x69746973, 0x69206E6F
    .WORD 0x6964206E, 0x74636572, 0x2079726F, 0x65727473, 0x28206D61, 0x79622034, 0x29736574, 0x2E0A2020
    .WORD 0x20555145, 0x5F524944, 0x455A4953, 0x202C464F, 0x0A382020, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x6F203B0A, 0x646E6570, 0x2D207269, 0x65704F20, 0x2061206E, 0x65726964, 0x726F7463
    .WORD 0x6F662079, 0x65722072, 0x6E696461, 0x0A3B0A67, 0x4E49203B, 0x5220203A, 0x203D2031, 0x68746170
    .WORD 0x756E2820, 0x742D6C6C, 0x696D7265, 0x6574616E, 0x74732064, 0x676E6972, 0x203B0A29, 0x3A54554F
    .WORD 0x20315220, 0x4944203D, 0x28202A52, 0x646E6168, 0x2029656C, 0x3020726F, 0x206E6F20, 0x6F727265
    .WORD 0x0A3B0A72, 0x704F203B, 0x20736E65, 0x69642061, 0x74636572, 0x2079726F, 0x656C6966, 0x646E6120
    .WORD 0x74657220, 0x736E7275, 0x68206120, 0x6C646E61, 0x6F662065, 0x65722072, 0x69646461, 0x2D3B0A72
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x706F0A2D, 0x69646E65, 0x200A3A72, 0x50202020, 0x20485355
    .WORD 0x200A524C, 0x50202020, 0x20485355, 0x200A3852, 0x50202020, 0x20485355, 0x200A3952, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x53203B20, 0x20657661
    .WORD 0x68746170, 0x2020200A, 0x4F203B20, 0x206E6570, 0x65726964, 0x726F7463, 0x69772079, 0x72206874
    .WORD 0x2D646165, 0x796C6E6F, 0x616C6620, 0x28207367, 0x656D6173, 0x20736120, 0x72756F79, 0x2E736C20
    .WORD 0x296D7361, 0x2020200A, 0x564F4D20, 0x20315220, 0x200A3852, 0x4C202020, 0x52202049, 0x5F4F2032
    .WORD 0x4E4F4452, 0x200A594C, 0x53202020, 0x53204356, 0x4F5F5359, 0x0A4E4550, 0x20202020, 0x20564F4D
    .WORD 0x52203952, 0x20202031, 0x20202020, 0x20202020, 0x0A64663B, 0x20202020, 0x20504D43, 0x30203152
    .WORD 0x2020200A, 0x544C4220, 0x65706F20, 0x7269646E, 0x7272655F, 0x200A726F, 0x0A202020, 0x20202020
    .WORD 0x6C41203B, 0x61636F6C, 0x44206574, 0x73205249, 0x63757274, 0x65727574, 0x6D732820, 0x2C6C6C61
    .WORD 0x73756A20, 0x64662074, 0x646E6120, 0x66666F20, 0x29746573, 0x2020200A, 0x53555020, 0x39522048
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x61733B20, 0x52206576, 0x696A2039, 0x20200A63
    .WORD 0x494C2020, 0x20315220, 0x5F524944, 0x455A4953, 0x200A464F, 0x43202020, 0x204C4C41, 0x6C6C616D
    .WORD 0x200A636F, 0x50202020, 0x2020504F, 0x0A0A3952, 0x20202020, 0x20504D43, 0x30203152, 0x2020200A
    .WORD 0x51454220, 0x65706F20, 0x7269646E, 0x7272655F, 0x635F726F, 0x65736F6C, 0x2020200A, 0x20200A20
    .WORD 0x4F4D2020, 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x76615320, 0x49442065
    .WORD 0x200A2A52, 0x0A202020, 0x20202020, 0x6E49203B, 0x61697469, 0x657A696C, 0x52494420, 0x72747320
    .WORD 0x75746375, 0x200A6572, 0x3B202020, 0x20325220, 0x6C697473, 0x6168206C, 0x64662073, 0x6F726620
    .WORD 0x706F206D, 0x200A6E65, 0x53202020, 0x52205754, 0x525B2039, 0x202B2038, 0x5F524944, 0x0A5D4446
    .WORD 0x20202020, 0x2020494C, 0x30203252, 0x2020200A, 0x57545320, 0x20325220, 0x2038525B, 0x4944202B
    .WORD 0x464F5F52, 0x54455346, 0x20200A5D, 0x200A2020, 0x4D202020, 0x5220564F, 0x38522031, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6552203B, 0x6E727574, 0x52494420, 0x20200A2A, 0x20422020, 0x6E65706F
    .WORD 0x5F726964, 0x656E6F64, 0x2020200A, 0x706F0A20, 0x69646E65, 0x72655F72, 0x5F726F72, 0x736F6C63
    .WORD 0x200A3A65, 0x4D202020, 0x5220564F, 0x39522031, 0x20202020, 0x20202020, 0x20202020, 0x6466203B
    .WORD 0x20736920, 0x52206E69, 0x20200A39, 0x56532020, 0x59532043, 0x4C435F53, 0x0A45534F, 0x20202020
    .WORD 0x5220494C, 0x0A302031, 0x20202020, 0x706F2042, 0x69646E65, 0x6F645F72, 0x200A656E, 0x0A202020
    .WORD 0x6E65706F, 0x5F726964, 0x6F727265, 0x200A3A72, 0x4C202020, 0x31522049, 0x200A3020, 0x0A202020
    .WORD 0x6E65706F, 0x5F726964, 0x656E6F64, 0x20200A3A, 0x4F502020, 0x39522050, 0x2020200A, 0x504F5020
    .WORD 0x0A385220, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x6572203B, 0x69646461, 0x202D2072, 0x64616552, 0x78656E20, 0x69642074
    .WORD 0x74636572, 0x2079726F, 0x72746E65, 0x0A3B0A79, 0x4E49203B, 0x5220203A, 0x203D2031, 0x2A524944
    .WORD 0x72662820, 0x6F206D6F, 0x646E6570, 0x0A297269, 0x2020203B, 0x52202020, 0x203D2032, 0x6E696F70
    .WORD 0x20726574, 0x73206F74, 0x63757274, 0x69642074, 0x746E6572, 0x206F7420, 0x6C6C6966, 0x4F203B0A
    .WORD 0x203A5455, 0x3D203152, 0x69203120, 0x6E652066, 0x20797274, 0x64616572, 0x2030202C, 0x6E206669
    .WORD 0x6F6D206F, 0x65206572, 0x6972746E, 0x202C7365, 0x6F20312D, 0x7265206E, 0x0A726F72, 0x203B0A3B
    .WORD 0x64616552, 0x68742073, 0x656E2065, 0x64207478, 0x63657269, 0x79726F74, 0x746E6520, 0x75207972
    .WORD 0x676E6973, 0x65687420, 0x72656B20, 0x276C656E, 0x65722073, 0x69646461, 0x69762072, 0x59532061
    .WORD 0x45525F53, 0x3B0A4441, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x720A2D2D, 0x64646165, 0x0A3A7269
    .WORD 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550, 0x0A385220, 0x20202020, 0x48535550
    .WORD 0x0A395220, 0x20202020, 0x2020200A, 0x564F4D20, 0x20385220, 0x20203152, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x2A524944, 0x2020200A, 0x564F4D20, 0x20395220, 0x20203252, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x72657355, 0x64207327, 0x6E657269, 0x75622074, 0x72656666, 0x2020200A, 0x20200A20
    .WORD 0x203B2020, 0x63656843, 0x6669206B, 0x52494420, 0x696F7020, 0x7265746E, 0x20736920, 0x696C6176
    .WORD 0x20200A64, 0x4D432020, 0x38522050, 0x200A3020, 0x42202020, 0x72205145, 0x64646165, 0x655F7269
    .WORD 0x726F7272, 0x2020200A, 0x20200A20, 0x203B2020, 0x64616552, 0x656E6F20, 0x72696420, 0x20746E65
    .WORD 0x6D6F7266, 0x72696420, 0x6F746365, 0x66207972, 0x73752064, 0x20676E69, 0x72727563, 0x20746E65
    .WORD 0x7366666F, 0x200A7465, 0x4C202020, 0x52205744, 0x525B2031, 0x202B2038, 0x5F524944, 0x205D4446
    .WORD 0x6466203B, 0x2020200A, 0x20200A20, 0x203B2020, 0x20657355, 0x20656874, 0x65726964, 0x726F7463
    .WORD 0x20732779, 0x7366666F, 0x2D207465, 0x20657720, 0x6465656E, 0x206F7420, 0x6C706D69, 0x6E656D65
    .WORD 0x736C2074, 0x206B6565, 0x7520726F, 0x200A6573, 0x3B202020, 0x65687420, 0x63616620, 0x68742074
    .WORD 0x65207461, 0x20686361, 0x64616572, 0x74656720, 0x6E6F2073, 0x69642065, 0x746E6572, 0x20746120
    .WORD 0x69742061, 0x6620656D, 0x206D6F72, 0x66726174, 0x20200A73, 0x4F4D2020, 0x32522056, 0x20395220
    .WORD 0x20202020, 0x20202020, 0x3B202020, 0x65737520, 0x75622072, 0x72656666, 0x2020200A, 0x20494C20
    .WORD 0x20335220, 0x45524944, 0x535F544E, 0x4F455A49, 0x203B2046, 0x657A6973, 0x20666F20, 0x20656E6F
    .WORD 0x65726964, 0x200A746E, 0x53202020, 0x53204356, 0x525F5359, 0x0A444145, 0x20202020, 0x20504D43
    .WORD 0x30203152, 0x2020200A, 0x51454220, 0x61657220, 0x72696464, 0x646E655F, 0x20202020, 0x203B2020
    .WORD 0x0A464F45, 0x20202020, 0x20504D43, 0x44203152, 0x4E455249, 0x49535F54, 0x464F455A, 0x2020200A
    .WORD 0x454E4220, 0x61657220, 0x72696464, 0x7272655F, 0x2020726F, 0x203B2020, 0x726F6853, 0x65722074
    .WORD 0x6F206461, 0x72652072, 0x0A726F72, 0x20202020, 0x2020200A, 0x45203B20, 0x7972746E, 0x61657220
    .WORD 0x75732064, 0x73656363, 0x6C756673, 0x200A796C, 0x3B202020, 0x64705520, 0x20657461, 0x20656874
    .WORD 0x7366666F, 0x69207465, 0x4944206E, 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x2057444C
    .WORD 0x5B203252, 0x2B203852, 0x52494420, 0x46464F5F, 0x5D544553, 0x2020200A, 0x44444120, 0x20325220
    .WORD 0x31203252, 0x2020200A, 0x57545320, 0x20325220, 0x2038525B, 0x4944202B, 0x464F5F52, 0x54455346
    .WORD 0x20200A5D, 0x200A2020, 0x4C202020, 0x31522049, 0x20203120, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x6552203B, 0x6E727574, 0x63757320, 0x73736563, 0x2020200A, 0x72204220, 0x64646165, 0x645F7269
    .WORD 0x0A656E6F, 0x20202020, 0x6165720A, 0x72696464, 0x7272655F, 0x0A3A726F, 0x20202020, 0x5220494C
    .WORD 0x312D2031, 0x2020200A, 0x72204220, 0x64646165, 0x645F7269, 0x0A656E6F, 0x20202020, 0x6165720A
    .WORD 0x72696464, 0x646E655F, 0x20200A3A, 0x494C2020, 0x20315220, 0x20200A30, 0x720A2020, 0x64646165
    .WORD 0x645F7269, 0x3A656E6F, 0x2020200A, 0x504F5020, 0x0A395220, 0x20202020, 0x20504F50, 0x200A3852
    .WORD 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x6F6C6320, 0x69646573, 0x202D2072, 0x736F6C43, 0x69642065, 0x74636572, 0x2079726F
    .WORD 0x65727473, 0x3B0A6D61, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x52494420, 0x203B0A2A, 0x3A54554F
    .WORD 0x20315220, 0x2030203D, 0x73206E6F, 0x65636375, 0x202C7373, 0x6F20312D, 0x7265206E, 0x0A726F72
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x736F6C63, 0x72696465, 0x20200A3A, 0x55502020
    .WORD 0x4C204853, 0x20200A52, 0x55502020, 0x52204853, 0x20200A38, 0x200A2020, 0x4D202020, 0x5220564F
    .WORD 0x31522038, 0x2020200A, 0x504D4320, 0x20385220, 0x20200A30, 0x45422020, 0x6C632051, 0x6465736F
    .WORD 0x655F7269, 0x726F7272, 0x2020200A, 0x20200A20, 0x203B2020, 0x736F6C43, 0x68742065, 0x69642065
    .WORD 0x74636572, 0x2079726F, 0x200A6466, 0x4C202020, 0x52205744, 0x525B2031, 0x202B2038, 0x5F524944
    .WORD 0x0A5D4446, 0x20202020, 0x20435653, 0x5F535953, 0x534F4C43, 0x20200A45, 0x200A2020, 0x3B202020
    .WORD 0x65724620, 0x68742065, 0x49442065, 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x20564F4D
    .WORD 0x52203152, 0x20200A38, 0x41432020, 0x66204C4C, 0x0A656572, 0x20202020, 0x2020200A, 0x20494C20
    .WORD 0x30203152, 0x2020200A, 0x63204220, 0x65736F6C, 0x5F726964, 0x656E6F64, 0x2020200A, 0x6C630A20
    .WORD 0x6465736F, 0x655F7269, 0x726F7272, 0x20200A3A, 0x494C2020, 0x20315220, 0x200A312D, 0x0A202020
    .WORD 0x736F6C63, 0x72696465, 0x6E6F645F, 0x200A3A65, 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020
    .WORD 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D
    .WORD 0x69776572, 0x6964646E, 0x202D2072, 0x65736552, 0x69642074, 0x74636572, 0x2079726F, 0x65727473
    .WORD 0x74206D61, 0x6562206F, 0x6E6E6967, 0x0A676E69, 0x203B0A3B, 0x203A4E49, 0x20315220, 0x4944203D
    .WORD 0x3B0A2A52, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x720A2D2D, 0x6E697765, 0x72696464, 0x20200A3A
    .WORD 0x4D432020, 0x31522050, 0x200A3020, 0x42202020, 0x72205145, 0x6E697765, 0x72696464, 0x6E6F645F
    .WORD 0x20200A65, 0x200A2020, 0x4C202020, 0x32522049, 0x200A3020, 0x53202020, 0x52205754, 0x525B2032
    .WORD 0x202B2031, 0x5F524944, 0x5346464F, 0x0A5D5445, 0x20202020, 0x2020200A, 0x4E203B20, 0x20646565
    .WORD 0x73206F74, 0x206B6565, 0x62206F74, 0x6E696765, 0x676E696E, 0x20666F20, 0x65726964, 0x726F7463
    .WORD 0x20200A79, 0x203B2020, 0x20726F46, 0x66726174, 0x74202C73, 0x20736968, 0x6E61656D, 0x6C632073
    .WORD 0x6E69736F, 0x6E612067, 0x65722064, 0x6E65706F, 0x2C676E69, 0x20726F20, 0x6E697375, 0x736C2067
    .WORD 0x0A6B6565, 0x20202020, 0x6953203B, 0x656C706D, 0x70706120, 0x63616F72, 0x63203A68, 0x65736F6C
    .WORD 0x646E6120, 0x6F657220, 0x0A6E6570, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x48535550
    .WORD 0x0A385220, 0x20202020, 0x2020200A, 0x564F4D20, 0x20385220, 0x200A3152, 0x3B202020, 0x76615320
    .WORD 0x68742065, 0x61702065, 0x2D206874, 0x20657720, 0x276E6F64, 0x61682074, 0x69206576, 0x74732074
    .WORD 0x6465726F, 0x6F73202C, 0x69687420, 0x73692073, 0x69727420, 0x0A796B63, 0x20202020, 0x6E49203B
    .WORD 0x72206120, 0x206C6165, 0x6C706D69, 0x6E656D65, 0x69746174, 0x202C6E6F, 0x726F7473, 0x61702065
    .WORD 0x69206874, 0x4944206E, 0x74732052, 0x74637572, 0x0A657275, 0x20202020, 0x2020200A, 0x46203B20
    .WORD 0x6E20726F, 0x202C776F, 0x7473756A, 0x73657220, 0x6F207465, 0x65736666, 0x6E612074, 0x65722064
    .WORD 0x6F20796C, 0x6572206E, 0x69646461, 0x20732772, 0x61686562, 0x726F6976, 0x2020200A, 0x20200A20
    .WORD 0x4F502020, 0x38522050, 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x7765720A, 0x64646E69
    .WORD 0x645F7269, 0x3A656E6F, 0x2020200A, 0x54455220, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x66726964, 0x202D2064, 0x20746547, 0x656C6966, 0x73656420, 0x70697263, 0x20726F74
    .WORD 0x6D6F7266, 0x52494420, 0x0A3B0A2A, 0x4E49203B, 0x5220203A, 0x203D2031, 0x2A524944, 0x4F203B0A
    .WORD 0x203A5455, 0x3D203152, 0x6C696620, 0x65642065, 0x69726373, 0x726F7470, 0x726F202C, 0x20312D20
    .WORD 0x65206E6F, 0x726F7272, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x7269640A, 0x0A3A6466
    .WORD 0x20202020, 0x20504D43, 0x30203152, 0x2020200A, 0x51454220, 0x72696420, 0x655F6466, 0x726F7272
    .WORD 0x2020200A, 0x20200A20, 0x444C2020, 0x31522057, 0x31525B20, 0x44202B20, 0x465F5249, 0x200A5D44
    .WORD 0x52202020, 0x200A5445, 0x0A202020, 0x66726964, 0x72655F64, 0x3A726F72, 0x2020200A, 0x20494C20
    .WORD 0x2D203152, 0x20200A31, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D
    .WORD 0x6C654820, 0x3A726570, 0x5F736920, 0x20726964, 0x6843202D, 0x206B6365, 0x61206669, 0x74617020
    .WORD 0x73692068, 0x64206120, 0x63657269, 0x79726F74, 0x3B0A3B0A, 0x3A4E4920, 0x31522020, 0x70203D20
    .WORD 0x0A687461, 0x554F203B, 0x52203A54, 0x203D2031, 0x66692031, 0x72696420, 0x6F746365, 0x202C7972
    .WORD 0x66692030, 0x746F6E20, 0x312D202C, 0x206E6F20, 0x6F727265, 0x2D3B0A72, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x73690A2D, 0x7269645F, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x200A2020
    .WORD 0x3B202020, 0x79725420, 0x206F7420, 0x6E65706F, 0x20736120, 0x65726964, 0x726F7463, 0x20200A79
    .WORD 0x41432020, 0x6F204C4C, 0x646E6570, 0x200A7269, 0x43202020, 0x5220504D, 0x0A302031, 0x20202020
    .WORD 0x20514542, 0x645F7369, 0x6E5F7269, 0x645F746F, 0x200A7269, 0x0A202020, 0x20202020, 0x7449203B
    .WORD 0x65706F20, 0x2064656E, 0x61207361, 0x72696420, 0x6F746365, 0x200A7972, 0x4D202020, 0x5220564F
    .WORD 0x31522032, 0x20202020, 0x20202020, 0x20202020, 0x6153203B, 0x44206576, 0x0A2A5249, 0x20202020
    .WORD 0x5220494C, 0x20312031, 0x20202020, 0x20202020, 0x20202020, 0x52203B20, 0x72757465, 0x7274206E
    .WORD 0x200A6575, 0x43202020, 0x204C4C41, 0x736F6C63, 0x72696465, 0x20202020, 0x20202020, 0x6C43203B
    .WORD 0x2065736F, 0x200A7469, 0x42202020, 0x5F736920, 0x5F726964, 0x656E6F64, 0x2020200A, 0x73690A20
    .WORD 0x7269645F, 0x746F6E5F, 0x7269645F, 0x20200A3A, 0x494C2020, 0x20315220, 0x20200A30, 0x690A2020
    .WORD 0x69645F73, 0x6F645F72, 0x0A3A656E, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020, 0x0A0A5445
    .WORD 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7845203B, 0x6C706D61, 0x73752065, 0x20656761
    .WORD 0x636E7566, 0x6E6F6974, 0x6C202D20, 0x20747369, 0x65726964, 0x726F7463, 0x6F632079, 0x6E65746E
    .WORD 0x28207374, 0x656B696C, 0x29736C20, 0x54203B0A, 0x20736968, 0x6F6D6564, 0x7274736E, 0x73657461
    .WORD 0x776F6820, 0x206F7420, 0x20657375, 0x6E65706F, 0x2F726964, 0x64616572, 0x2F726964, 0x736F6C63
    .WORD 0x72696465, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x73696C0A, 0x69645F74, 0x74636572
    .WORD 0x3A79726F, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x38522048, 0x2020200A
    .WORD 0x53555020, 0x39522048, 0x2020200A, 0x20200A20, 0x4F4D2020, 0x38522056, 0x20315220, 0x20202020
    .WORD 0x20202020, 0x3B202020, 0x74617020, 0x20200A68, 0x200A2020, 0x3B202020, 0x6C6C4120, 0x7461636F
    .WORD 0x69642065, 0x746E6572, 0x206E6F20, 0x63617473, 0x20200A6B, 0x55532020, 0x50532042, 0x20505320
    .WORD 0x45524944, 0x535F544E, 0x4F455A49, 0x20200A46, 0x4F4D2020, 0x39522056, 0x0A505320, 0x20202020
    .WORD 0x2020200A, 0x4F203B20, 0x206E6570, 0x65726964, 0x726F7463, 0x20200A79, 0x4F4D2020, 0x31522056
    .WORD 0x0A385220, 0x20202020, 0x4C4C4143, 0x65706F20, 0x7269646E, 0x2020200A, 0x504D4320, 0x20315220
    .WORD 0x20200A30, 0x45422020, 0x696C2051, 0x645F7473, 0x655F7269, 0x726F7272, 0x2020200A, 0x20200A20
    .WORD 0x4F4D2020, 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x3B202020, 0x52494420, 0x20200A2A
    .WORD 0x6C0A2020, 0x5F747369, 0x5F726964, 0x706F6F6C, 0x20200A3A, 0x4F4D2020, 0x31522056, 0x0A385220
    .WORD 0x20202020, 0x20564F4D, 0x52203252, 0x20200A39, 0x41432020, 0x72204C4C, 0x64646165, 0x200A7269
    .WORD 0x43202020, 0x5220504D, 0x0A302031, 0x20202020, 0x20514542, 0x7473696C, 0x7269645F, 0x6F6C635F
    .WORD 0x200A6573, 0x4C202020, 0x52202049, 0x312D2032, 0x2020200A, 0x504D4320, 0x20315220, 0x200A3252
    .WORD 0x42202020, 0x6C205145, 0x5F747369, 0x5F726964, 0x6F727265, 0x20200A72, 0x200A2020, 0x3B202020
    .WORD 0x69725020, 0x7420746E, 0x6E206568, 0x0A656D61, 0x20202020, 0x20444441, 0x52203152, 0x49442039
    .WORD 0x544E4552, 0x4D414E5F, 0x20200A45, 0x41432020, 0x70204C4C, 0x0A737475, 0x20202020, 0x2020200A
    .WORD 0x49203B20, 0x74692066, 0x61207327, 0x72696420, 0x6F746365, 0x202C7972, 0x6E697270, 0x2F272074
    .WORD 0x20200A27, 0x444C2020, 0x32522057, 0x39525B20, 0x44202B20, 0x4E455249, 0x59545F54, 0x0A5D4550
    .WORD 0x20202020, 0x20504D43, 0x44203252, 0x49445F54, 0x20200A52, 0x4E422020, 0x696C2045, 0x645F7473
    .WORD 0x6E5F7269, 0x645F746F, 0x200A7269, 0x0A202020, 0x20202020, 0x5220494C, 0x6C732031, 0x5F687361
    .WORD 0x72616863, 0x2020200A, 0x4C414320, 0x7570204C, 0x61686374, 0x20200A72, 0x6C0A2020, 0x5F747369
    .WORD 0x5F726964, 0x5F746F6E, 0x3A726964, 0x2020200A, 0x20494C20, 0x6E203152, 0x696C7765, 0x635F656E
    .WORD 0x0A726168, 0x20202020, 0x4C4C4143, 0x74757020, 0x72616863, 0x2020200A, 0x20200A20, 0x20422020
    .WORD 0x7473696C, 0x7269645F, 0x6F6F6C5F, 0x20200A70, 0x6C0A2020, 0x5F747369, 0x5F726964, 0x736F6C63
    .WORD 0x200A3A65, 0x4D202020, 0x5220564F, 0x38522031, 0x2020200A, 0x4C414320, 0x6C63204C, 0x6465736F
    .WORD 0x200A7269, 0x4C202020, 0x31522049, 0x200A3020, 0x42202020, 0x73696C20, 0x69645F74, 0x6F645F72
    .WORD 0x200A656E, 0x0A202020, 0x7473696C, 0x7269645F, 0x7272655F, 0x0A3A726F, 0x20202020, 0x5220494C
    .WORD 0x312D2031, 0x2020200A, 0x696C0A20, 0x645F7473, 0x645F7269, 0x3A656E6F, 0x2020200A, 0x44444120
    .WORD 0x20505320, 0x44205053, 0x4E455249, 0x49535F54, 0x464F455A, 0x2020200A, 0x504F5020, 0x0A395220
    .WORD 0x20202020, 0x20504F50, 0x200A3852, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x74614420, 0x65532061, 0x6F697463, 0x2D3B0A6E
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x6C730A2D, 0x5F687361, 0x72616863, 0x20200A3A, 0x572E2020
    .WORD 0x2044524F, 0x20203734, 0x20202020, 0x272F273B, 0x77656E0A, 0x656E696C, 0x6168635F, 0x200A3A72
    .WORD 0x2E202020, 0x44524F57, 0x0A303120, 0x41203B0A, 0x6D756772, 0x73746E65, 0x65726120, 0x73617020
    .WORD 0x20646573, 0x52206E69, 0x522E2E32, 0x28203231, 0x74207075, 0x3131206F, 0x3B0A2E29, 0x74754F20
    .WORD 0x20747570, 0x77207369, 0x74746972, 0x69206E65, 0x64656D6D, 0x65746169, 0x203B796C, 0x69206F6E
    .WORD 0x7265746E, 0x206C616E, 0x66667562, 0x6E697265, 0x3B0A2E67, 0x49203B0A, 0x20203A4E, 0x3D203152
    .WORD 0x726F6620, 0x2074616D, 0x69727473, 0x3B0A676E, 0x54554F20, 0x3152203A, 0x6E203D20, 0x65626D75
    .WORD 0x666F2072, 0x61686320, 0x74636172, 0x20737265, 0x74697277, 0x206E6574, 0x74706F28, 0x616E6F69
    .WORD 0x63202C6C, 0x62206E61, 0x67692065, 0x65726F6E, 0x3B0A2964, 0x61737520, 0x0A3A6567, 0x2020203B
    .WORD 0x6E697270, 0x22286674, 0x6C6C6548, 0x7325206F, 0x756E202C, 0x7265626D, 0x2C64253D, 0x78656820
    .WORD 0x2C78253D, 0x61686320, 0x63253D72, 0x2C226E5C, 0x6F772220, 0x22646C72, 0x3234202C, 0x3532202C
    .WORD 0x27202C35, 0x0A292741, 0x2020203B, 0x3233524B, 0x203B0A3A, 0x494C2020, 0x20315220, 0x5F746D66
    .WORD 0x0A727473, 0x2020203B, 0x5220494C, 0x32342032, 0x20203B0A, 0x20494C20, 0x68203352, 0x6F6C6C65
    .WORD 0x7274735F, 0x20203B0A, 0x204C4220, 0x6E697270, 0x3B0A6674, 0x0A2E2E2E, 0x746D663B, 0x7274735F
    .WORD 0x412E203A, 0x49494353, 0x4E22205A, 0x65626D75, 0x25203A72, 0x53202C64, 0x6E697274, 0x25203A67
    .WORD 0x226E5C73, 0x65683B0A, 0x5F6F6C6C, 0x3A727473, 0x53412E20, 0x5A494943, 0x6F772220, 0x22646C72
    .WORD 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D3B0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x203B0A2D, 0x6E697270, 0x2D206674, 0x726F4620, 0x7474616D, 0x6F206465, 0x75707475, 0x6F742074
    .WORD 0x64747320, 0x0A74756F, 0x203B0A3B, 0x70707553, 0x6574726F, 0x6F632064, 0x7265766E, 0x6E6F6973
    .WORD 0x3B0A3A73, 0x25202020, 0x20202025, 0x6C202020, 0x72657469, 0x27206C61, 0x3B0A2725, 0x25202020
    .WORD 0x20202073, 0x73202020, 0x6E697274, 0x63282067, 0x2A726168, 0x203B0A29, 0x64252020, 0x25202F20
    .WORD 0x69732069, 0x64656E67, 0x63656420, 0x6C616D69, 0x20203B0A, 0x20782520, 0x20202020, 0x736E7520
    .WORD 0x656E6769, 0x65682064, 0x65646178, 0x616D6963, 0x6C28206C, 0x7265776F, 0x65736163, 0x203B0A29
    .WORD 0x63252020, 0x20202020, 0x69732020, 0x656C676E, 0x61686320, 0x74636172, 0x3B0A7265, 0x25202020
    .WORD 0x20202062, 0x75202020, 0x6769736E, 0x2064656E, 0x616E6962, 0x3B0A7972, 0x25202020, 0x2020206F
    .WORD 0x75202020, 0x6769736E, 0x2064656E, 0x6174636F, 0x0A3B0A6C, 0x7241203B, 0x656D7567, 0x3A73746E
    .WORD 0x2E325220, 0x3231522E, 0x69662820, 0x20747372, 0x2C293131, 0x65687420, 0x6E6F206E, 0x61747320
    .WORD 0x28206B63, 0x6C6C6163, 0x80E27265, 0x73757091, 0x29646568, 0x2D3B0A2E, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x72700A2D, 0x66746E69, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020
    .WORD 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x55502020, 0x52204853, 0x200A3031
    .WORD 0x50202020, 0x20485355, 0x0A313152, 0x20202020, 0x48535550, 0x32315220, 0x20200A0A, 0x55532020
    .WORD 0x50532042, 0x20505320, 0x20203038, 0x20202020, 0x20202020, 0x20202020, 0x6F6C203B, 0x206C6163
    .WORD 0x6D617266, 0x34203A65, 0x202B2034, 0x2B203433, 0x64617020, 0x676E6964, 0x20200A0A, 0x203B2020
    .WORD 0x65766153, 0x2E325220, 0x3231522E, 0x206F7420, 0x61636F6C, 0x7261206C, 0x0A796172, 0x20202020
    .WORD 0x20575453, 0x5B203252, 0x2B205053, 0x0A5D3020, 0x20202020, 0x20575453, 0x5B203352, 0x2B205053
    .WORD 0x0A5D3420, 0x20202020, 0x20575453, 0x5B203452, 0x2B205053, 0x0A5D3820, 0x20202020, 0x20575453
    .WORD 0x5B203552, 0x2B205053, 0x5D323120, 0x2020200A, 0x57545320, 0x20365220, 0x2050535B, 0x3631202B
    .WORD 0x20200A5D, 0x54532020, 0x37522057, 0x50535B20, 0x32202B20, 0x200A5D30, 0x53202020, 0x52205754
    .WORD 0x535B2038, 0x202B2050, 0x0A5D3432, 0x20202020, 0x20575453, 0x5B203952, 0x2B205053, 0x5D383220
    .WORD 0x2020200A, 0x57545320, 0x30315220, 0x50535B20, 0x33202B20, 0x200A5D32, 0x53202020, 0x52205754
    .WORD 0x5B203131, 0x2B205053, 0x5D363320, 0x2020200A, 0x57545320, 0x32315220, 0x50535B20, 0x34202B20
    .WORD 0x0A0A5D30, 0x20202020, 0x20564F4D, 0x52203852, 0x20202031, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x203B2020, 0x6D726F66, 0x70207461, 0x746E696F, 0x200A7265, 0x4C202020, 0x52202049, 0x20302039
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x61203B20, 0x6D756772, 0x20746E65, 0x65646E69
    .WORD 0x200A0A78, 0x4D202020, 0x5220564F, 0x53203031, 0x20202050, 0x20202020, 0x20202020, 0x20202020
    .WORD 0x62203B20, 0x20657361, 0x7320666F, 0x64657661, 0x67657220, 0x65747369, 0x200A7372, 0x41202020
    .WORD 0x52204444, 0x53203131, 0x34342050, 0x20202020, 0x20202020, 0x20202020, 0x63203B20, 0x65766E6F
    .WORD 0x6F697372, 0x7562206E, 0x72656666, 0x72700A0A, 0x66746E69, 0x6F6F6C5F, 0x200A3A70, 0x4C202020
    .WORD 0x52204244, 0x525B2031, 0x20205D38, 0x3B202020, 0x64616572, 0x746D6620, 0x72747320, 0x20676E69
    .WORD 0x72616863, 0x2020200A, 0x504D4320, 0x20315220, 0x20200A30, 0x45422020, 0x72702051, 0x66746E69
    .WORD 0x6E6F645F, 0x200A0A65, 0x43202020, 0x5220504D, 0x37332031, 0x3B202020, 0x63656863, 0x6F66206B
    .WORD 0x25272072, 0x20200A27, 0x4E422020, 0x72702045, 0x66746E69, 0x726F6E5F, 0x5F6C616D, 0x72616863
    .WORD 0x20200A0A, 0x44412020, 0x38522044, 0x20385220, 0x203B2031, 0x20737469, 0x25272061, 0x6D202C27
    .WORD 0x2065766F, 0x6E206F74, 0x20747865, 0x72616863, 0x726F6620, 0x65707320, 0x69666963, 0x200A7265
    .WORD 0x4C202020, 0x52204244, 0x525B2032, 0x200A5D38, 0x43202020, 0x5220504D, 0x0A302032, 0x20202020
    .WORD 0x20514542, 0x6E697270, 0x645F6674, 0x0A656E6F, 0x2020200A, 0x504D4320, 0x20325220, 0x20203733
    .WORD 0x63203B20, 0x6B636568, 0x726F6620, 0x25252720, 0x20200A27, 0x45422020, 0x72702051, 0x66746E69
    .WORD 0x7265705F, 0x746E6563, 0x2020200A, 0x504D4320, 0x20325220, 0x20353131, 0x63203B20, 0x6B636568
    .WORD 0x726F6620, 0x73252720, 0x20200A27, 0x45422020, 0x72702051, 0x66746E69, 0x7274735F, 0x0A676E69
    .WORD 0x20202020, 0x20504D43, 0x31203252, 0x20203030, 0x6568633B, 0x66206B63, 0x2720726F, 0x0A276425
    .WORD 0x20202020, 0x20514542, 0x6E697270, 0x695F6674, 0x200A746E, 0x43202020, 0x5220504D, 0x30312032
    .WORD 0x3B202035, 0x63656863, 0x6F66206B, 0x25272072, 0x200A2769, 0x42202020, 0x70205145, 0x746E6972
    .WORD 0x6E695F66, 0x20200A74, 0x4D432020, 0x32522050, 0x30323120, 0x633B2020, 0x6B636568, 0x726F6620
    .WORD 0x78252720, 0x20200A27, 0x45422020, 0x72702051, 0x66746E69, 0x7865685F, 0x2020200A, 0x504D4320
    .WORD 0x20325220, 0x20203939, 0x68633B20, 0x206B6365, 0x20726F66, 0x27632527, 0x2020200A, 0x51454220
    .WORD 0x69727020, 0x5F66746E, 0x72616863, 0x2020200A, 0x504D4320, 0x20325220, 0x20203839, 0x68633B20
    .WORD 0x206B6365, 0x20726F66, 0x27622527, 0x2020200A, 0x51454220, 0x69727020, 0x5F66746E, 0x0A6E6962
    .WORD 0x20202020, 0x20504D43, 0x31203252, 0x20203131, 0x6568633B, 0x66206B63, 0x2720726F, 0x0A276F25
    .WORD 0x20202020, 0x20514542, 0x6E697270, 0x6F5F6674, 0x0A0A7463, 0x20202020, 0x6E75203B, 0x776F6E6B
    .WORD 0x7073206E, 0x66696365, 0x0A726569, 0x20202020, 0x2020494C, 0x33203152, 0x20202037, 0x6B6E753B
    .WORD 0x6E776F6E, 0x65707320, 0x69666963, 0x202C7265, 0x6E697270, 0x25272074, 0x20200A27, 0x41432020
    .WORD 0x70204C4C, 0x68637475, 0x200A7261, 0x4D202020, 0x5220564F, 0x32522031, 0x3B202020, 0x69727020
    .WORD 0x7420746E, 0x75206568, 0x6F6E6B6E, 0x73206E77, 0x69636570, 0x72656966, 0x61686320, 0x20200A72
    .WORD 0x41432020, 0x70204C4C, 0x68637475, 0x200A7261, 0x42202020, 0x70202020, 0x746E6972, 0x6F635F66
    .WORD 0x6E69746E, 0x0A0A6575, 0x6E697270, 0x6E5F6674, 0x616D726F, 0x68635F6C, 0x0A3A7261, 0x20202020
    .WORD 0x4C4C4143, 0x74757020, 0x72616863, 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E, 0x746E6F63
    .WORD 0x65756E69, 0x72700A0A, 0x66746E69, 0x7265705F, 0x746E6563, 0x20200A3A, 0x494C2020, 0x31522020
    .WORD 0x20373320, 0x703B2020, 0x746E6972, 0x27252720, 0x2020200A, 0x4C414320, 0x7570204C, 0x61686374
    .WORD 0x20200A72, 0x20422020, 0x72702020, 0x66746E69, 0x6E6F635F, 0x756E6974, 0x3B0A0A65, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x67724120, 0x6E656D75, 0x65662074, 0x20686374, 0x706C6568
    .WORD 0x20737265, 0x6D617328, 0x73612065, 0x66656220, 0x2965726F, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x65665F0A, 0x5F686374, 0x5F677261, 0x0A3A3172, 0x20202020, 0x48535550, 0x20524C20
    .WORD 0x2020200A, 0x53555020, 0x33522048, 0x2020200A, 0x4C414320, 0x675F204C, 0x615F7465, 0x615F6772
    .WORD 0x65726464, 0x200A7373, 0x4C202020, 0x52205744, 0x525B2031, 0x200A5D33, 0x50202020, 0x5220504F
    .WORD 0x20200A33, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x665F0A0A, 0x68637465, 0x6772615F
    .WORD 0x3A32725F, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x53555020, 0x33522048, 0x2020200A
    .WORD 0x4C414320, 0x675F204C, 0x615F7465, 0x615F6772, 0x65726464, 0x200A7373, 0x4C202020, 0x52205744
    .WORD 0x525B2032, 0x200A5D33, 0x50202020, 0x5220504F, 0x20200A33, 0x4F502020, 0x524C2050, 0x2020200A
    .WORD 0x54455220, 0x675F0A0A, 0x615F7465, 0x615F6772, 0x65726464, 0x203A7373, 0x203B2020, 0x63746566
    .WORD 0x68742068, 0x64612065, 0x73657264, 0x666F2073, 0x65687420, 0x78656E20, 0x72612074, 0x656D7567
    .WORD 0x6220746E, 0x64657361, 0x206E6F20, 0x28203952, 0x20677261, 0x65646E69, 0x200A2978, 0x43202020
    .WORD 0x5220504D, 0x31312039, 0x20202020, 0x3B202020, 0x20666920, 0x20677261, 0x65646E69, 0x3D3E2078
    .WORD 0x2C313120, 0x27746920, 0x6E6F2073, 0x65687420, 0x61747320, 0x200A6B63, 0x42202020, 0x5F20544C
    .WORD 0x5F677261, 0x725F6E69, 0x0A736765, 0x20202020, 0x20425553, 0x52203352, 0x31312039, 0x20202020
    .WORD 0x3352203B, 0x6E203D20, 0x65626D75, 0x666F2072, 0x74786520, 0x61206172, 0x20736772, 0x73206E6F
    .WORD 0x6B636174, 0x2020200A, 0x20494C20, 0x20345220, 0x20200A34, 0x554D2020, 0x3352204C, 0x20335220
    .WORD 0x200A3452, 0x41202020, 0x52204444, 0x50532033, 0x20335220, 0x3B202020, 0x20335220, 0x6461203D
    .WORD 0x73657264, 0x666F2073, 0x72696620, 0x65207473, 0x61727478, 0x67726120, 0x206E6F20, 0x63617473
    .WORD 0x6E28206B, 0x7320746F, 0x20657275, 0x74206669, 0x20736968, 0x63207369, 0x6572726F, 0x0A297463
    .WORD 0x20202020, 0x20444441, 0x52203352, 0x30312033, 0x20202034, 0x666F203B, 0x74657366, 0x206F7420
    .WORD 0x6C6C6163, 0x73277265, 0x72696620, 0x65207473, 0x61727478, 0x67726120, 0x34303120, 0x20200A20
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x20202020, 0x693B2020, 0x68742073, 0x69732065, 0x6F20657A
    .WORD 0x68742066, 0x6F6C2065, 0x206C6163, 0x6D617266, 0x38282065, 0x2B202930, 0x76617320, 0x72206465
    .WORD 0x73696765, 0x73726574, 0x34342820, 0x20200A29, 0x45522020, 0x5F0A0A54, 0x5F677261, 0x725F6E69
    .WORD 0x3A736765, 0x20202020, 0x3B202020, 0x74656620, 0x61206863, 0x6D756772, 0x20746E65, 0x6D6F7266
    .WORD 0x2E325220, 0x3231522E, 0x73616220, 0x6F206465, 0x3952206E, 0x2020200A, 0x20494C20, 0x20345220
    .WORD 0x20202034, 0x20202020, 0x20200A20, 0x554D2020, 0x3352204C, 0x20395220, 0x20203452, 0x203B2020
    .WORD 0x3D203952, 0x67726120, 0x646E6920, 0x202C7865, 0x20335228, 0x666F203D, 0x74657366, 0x206E6920
    .WORD 0x65747962, 0x200A2973, 0x41202020, 0x52204444, 0x31522033, 0x33522030, 0x3B202020, 0x20335220
    .WORD 0x6461203D, 0x73657264, 0x666F2073, 0x76617320, 0x72206465, 0x73696765, 0x20726574, 0x6C206E69
    .WORD 0x6C61636F, 0x72726120, 0x202C7961, 0x20303152, 0x6162203D, 0x6F206573, 0x61732066, 0x20646576
    .WORD 0x69676572, 0x72657473, 0x20200A73, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x65705320, 0x69666963, 0x68207265, 0x6C646E61, 0x0A737265, 0x2D2D2D3B, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x0A2D2D2D, 0x6E697270, 0x735F6674, 0x6E697274, 0x200A3A67, 0x43202020, 0x204C4C41
    .WORD 0x7465665F, 0x615F6863, 0x725F6772, 0x3B202031, 0x20746567, 0x69727473, 0x7020676E, 0x746E696F
    .WORD 0x66207265, 0x206D6F72, 0x200A3152, 0x41202020, 0x52204444, 0x39522039, 0x200A3120, 0x43202020
    .WORD 0x204C4C41, 0x6972705F, 0x735F746E, 0x6E697274, 0x3B202067, 0x6E697270, 0x68742074, 0x74732065
    .WORD 0x676E6972, 0x2020200A, 0x20204220, 0x69727020, 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A
    .WORD 0x66746E69, 0x746E695F, 0x20200A3A, 0x41432020, 0x5F204C4C, 0x63746566, 0x72615F68, 0x32725F67
    .WORD 0x673B2020, 0x69207465, 0x6765746E, 0x70207265, 0x66207274, 0x206D6F72, 0x200A3252, 0x0A202020
    .WORD 0x20202020, 0x20564F4D, 0x52203152, 0x20202032, 0x20202020, 0x20202020, 0x6E6F633B, 0x74726576
    .WORD 0x6D756E20, 0x20726562, 0x6D6F7266, 0x72747320, 0x20676E69, 0x6D726F66, 0x63207461, 0x7420646D
    .WORD 0x6E69206F, 0x65676574, 0x6D282072, 0x62207961, 0x69732065, 0x6465676E, 0x20200A29, 0x41432020
    .WORD 0x61204C4C, 0x0A696F74, 0x20202020, 0x20564F4D, 0x52203252, 0x200A2031, 0x0A202020, 0x20202020
    .WORD 0x20444441, 0x52203952, 0x0A312039, 0x20202020, 0x20564F4D, 0x52203152, 0x20203131, 0x20202020
    .WORD 0x20202020, 0x3172203B, 0x73692031, 0x65687420, 0x6E6F6320, 0x73726576, 0x206E6F69, 0x66667562
    .WORD 0x28207265, 0x73206E6F, 0x6B636174, 0x20200A29, 0x41432020, 0x5F204C4C, 0x6E697270, 0x756E5F74
    .WORD 0x7265626D, 0x703B2020, 0x746E6972, 0x65687420, 0x746E6920, 0x72656765, 0x2020200A, 0x20204220
    .WORD 0x69727020, 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69, 0x7865685F, 0x20200A3A
    .WORD 0x41432020, 0x5F204C4C, 0x63746566, 0x72615F68, 0x32725F67, 0x20200A0A, 0x4F4D2020, 0x31522056
    .WORD 0x20325220, 0x20202020, 0x20202020, 0x633B2020, 0x65766E6F, 0x6E207472, 0x65626D75, 0x72662072
    .WORD 0x73206D6F, 0x6E697274, 0x6F662067, 0x74616D72, 0x646D6320, 0x206F7420, 0x65746E69, 0x20726567
    .WORD 0x79616D28, 0x20656220, 0x676E6973, 0x0A296465, 0x20202020, 0x4C4C4143, 0x6F746120, 0x20200A69
    .WORD 0x4F4D2020, 0x32522056, 0x0A315220, 0x2020200A, 0x44444120, 0x20395220, 0x31203952, 0x2020200A
    .WORD 0x564F4D20, 0x20315220, 0x20313152, 0x20202020, 0x20202020, 0x72203B20, 0x69203131, 0x68742073
    .WORD 0x6F632065, 0x7265766E, 0x6E6F6973, 0x66756220, 0x20726566, 0x206E6F28, 0x63617473, 0x6120296B
    .WORD 0x7320646E, 0x6E6F206F, 0x726F6620, 0x68746F20, 0x63207265, 0x65766E6F, 0x6F697372, 0x6820736E
    .WORD 0x65706C65, 0x2E2E7372, 0x2020200A, 0x4C414320, 0x705F204C, 0x746E6972, 0x7865685F, 0x2020200A
    .WORD 0x20204220, 0x69727020, 0x5F66746E, 0x746E6F63, 0x65756E69, 0x72700A0A, 0x66746E69, 0x6168635F
    .WORD 0x200A3A72, 0x43202020, 0x204C4C41, 0x7465665F, 0x615F6863, 0x725F6772, 0x20200A31, 0x444C2020
    .WORD 0x31522062, 0x31525B20, 0x2020205D, 0x20202020, 0x673B2020, 0x63207465, 0x20726168, 0x69207962
    .WORD 0x70207374, 0x200A7274, 0x41202020, 0x52204444, 0x39522039, 0x200A3120, 0x43202020, 0x204C4C41
    .WORD 0x63747570, 0x0A726168, 0x20202020, 0x20202042, 0x6E697270, 0x635F6674, 0x69746E6F, 0x0A65756E
    .WORD 0x6972700A, 0x5F66746E, 0x3A6E6962, 0x2020200A, 0x4C414320, 0x665F204C, 0x68637465, 0x6772615F
    .WORD 0x0A32725F, 0x20202020, 0x2020200A, 0x564F4D20, 0x20315220, 0x20203252, 0x20202020, 0x20202020
    .WORD 0x6F633B20, 0x7265766E, 0x756E2074, 0x7265626D, 0x6F726620, 0x7473206D, 0x676E6972, 0x726F6620
    .WORD 0x2074616D, 0x20646D63, 0x69206F74, 0x6765746E, 0x28207265, 0x2079616D, 0x73206562, 0x65676E69
    .WORD 0x200A2964, 0x43202020, 0x204C4C41, 0x696F7461, 0x2020200A, 0x564F4D20, 0x20325220, 0x0A0A3152
    .WORD 0x20202020, 0x20444441, 0x52203952, 0x0A312039, 0x20202020, 0x20564F4D, 0x52203152, 0x200A3131
    .WORD 0x43202020, 0x204C4C41, 0x6972705F, 0x625F746E, 0x200A6E69, 0x42202020, 0x70202020, 0x746E6972
    .WORD 0x6F635F66, 0x6E69746E, 0x0A0A6575, 0x6E697270, 0x6F5F6674, 0x0A3A7463, 0x20202020, 0x4C4C4143
    .WORD 0x65665F20, 0x5F686374, 0x5F677261, 0x0A0A3272, 0x20202020, 0x20564F4D, 0x52203152, 0x20202032
    .WORD 0x20202020, 0x20202020, 0x6E6F633B, 0x74726576, 0x6D756E20, 0x20726562, 0x6D6F7266, 0x72747320
    .WORD 0x20676E69, 0x6D726F66, 0x63207461, 0x7420646D, 0x6E69206F, 0x65676574, 0x6D282072, 0x62207961
    .WORD 0x69732065, 0x6465676E, 0x20200A29, 0x41432020, 0x61204C4C, 0x0A696F74, 0x20202020, 0x20564F4D
    .WORD 0x52203252, 0x200A0A31, 0x41202020, 0x52204444, 0x39522039, 0x200A3120, 0x4D202020, 0x5220564F
    .WORD 0x31522031, 0x20200A31, 0x41432020, 0x5F204C4C, 0x6E697270, 0x636F5F74, 0x20200A74, 0x20422020
    .WORD 0x72702020, 0x66746E69, 0x6E6F635F, 0x756E6974, 0x700A0A65, 0x746E6972, 0x6F635F66, 0x6E69746E
    .WORD 0x203A6575, 0x3B202020, 0x63206F74, 0x69746E6F, 0x2065756E, 0x636F7270, 0x69737365, 0x6620676E
    .WORD 0x616D726F, 0x74732074, 0x676E6972, 0x2020200A, 0x44444120, 0x20385220, 0x31203852, 0x2020200A
    .WORD 0x20204220, 0x69727020, 0x5F66746E, 0x706F6F6C, 0x72700A0A, 0x66746E69, 0x6E6F645F, 0x200A3A65
    .WORD 0x41202020, 0x53204444, 0x50532050, 0x0A303820, 0x20202020, 0x20504F50, 0x0A323152, 0x20202020
    .WORD 0x20504F50, 0x0A313152, 0x20202020, 0x20504F50, 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952
    .WORD 0x50202020, 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x2D3B0A0A
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x203B0A2D, 0x6972705F, 0x735F746E, 0x6E697274, 0x202D2067
    .WORD 0x74697257, 0x20612065, 0x6C6C756E, 0x749180E2, 0x696D7265, 0x6574616E, 0x74732064, 0x676E6972
    .WORD 0x206F7420, 0x6F647473, 0x28207475, 0x6E206F6E, 0x696C7765, 0x0A29656E, 0x203B0A3B, 0x73657355
    .WORD 0x65687420, 0x62696C20, 0x77602063, 0x65746972, 0x72772060, 0x65707061, 0x66282072, 0x62202C64
    .WORD 0x65666675, 0x6C202C72, 0x20296E65, 0x74736E69, 0x20646165, 0x6420666F, 0x63657269, 0x56532074
    .WORD 0x3B0A2E43, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x696F7020, 0x7265746E, 0x206F7420, 0x69727473
    .WORD 0x3B0A676E, 0x54554F20, 0x6F6E203A, 0x3B0A656E, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x5F0A2D2D
    .WORD 0x6E697270, 0x74735F74, 0x676E6972, 0x20200A3A, 0x55502020, 0x4C204853, 0x20200A52, 0x55502020
    .WORD 0x52204853, 0x20200A38, 0x55502020, 0x52204853, 0x20200A39, 0x4F4D2020, 0x38522056, 0x0A315220
    .WORD 0x20202020, 0x4C4C4143, 0x72747320, 0x206E656C, 0x20202020, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x3D203152, 0x6E656C20, 0x0A687467, 0x20202020, 0x20564F4D, 0x52203952, 0x20200A31, 0x494C2020
    .WORD 0x31522020, 0x44545320, 0x5F54554F, 0x200A4446, 0x4D202020, 0x5220564F, 0x38522032, 0x2020200A
    .WORD 0x564F4D20, 0x20335220, 0x200A3952, 0x43202020, 0x204C4C41, 0x74697277, 0x20202065, 0x20202020
    .WORD 0x20202020, 0x20202020, 0x6C203B20, 0x20636269, 0x70617277, 0x2C726570, 0x746F6E20, 0x72696420
    .WORD 0x20746365, 0x0A435653, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020, 0x5220504F, 0x20200A38
    .WORD 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x3B0A0A0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x3B0A2D2D, 0x72705F20, 0x5F746E69, 0x626D756E, 0x2D207265, 0x726F4620, 0x2074616D, 0x20646E61
    .WORD 0x6E697270, 0x20612074, 0x6E676973, 0x69206465, 0x6765746E, 0x28207265, 0x73657375, 0x6F746920
    .WORD 0x65645F61, 0x3B0A2963, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974
    .WORD 0x66756220, 0x20726566, 0x73756D28, 0x65622074, 0xA589E220, 0x62203331, 0x73657479, 0x203B0A29
    .WORD 0x20202020, 0x20325220, 0x6973203D, 0x64656E67, 0x746E6920, 0x72656765, 0x4F203B0A, 0x203A5455
    .WORD 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x72705F0A, 0x5F746E69, 0x626D756E
    .WORD 0x0A3A7265, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020, 0x4C4C4143, 0x6F746920, 0x65645F61
    .WORD 0x20202063, 0x20202020, 0x20202020, 0x203B2020, 0x73657375, 0x20315220, 0x66756228, 0x29726566
    .WORD 0x646E6120, 0x20325220, 0x6C617628, 0x0A296575, 0x20202020, 0x20564F4D, 0x52203152, 0x20202031
    .WORD 0x20202020, 0x20202020, 0x20202020, 0x203B2020, 0x73203152, 0x6C6C6974, 0x696F7020, 0x2073746E
    .WORD 0x62206F74, 0x65666675, 0x74732072, 0x0A747261, 0x20202020, 0x4C4C4143, 0x72705F20, 0x5F746E69
    .WORD 0x69727473, 0x200A676E, 0x50202020, 0x4C20504F, 0x20200A52, 0x45522020, 0x3B0A0A54, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x3B0A2D2D, 0x72705F20, 0x5F746E69, 0x20786568, 0x6F46202D, 0x74616D72
    .WORD 0x646E6120, 0x69727020, 0x6120746E, 0x6E75206E, 0x6E676973, 0x69206465, 0x6765746E, 0x69207265
    .WORD 0x6568206E, 0x75282078, 0x20736573, 0x616F7469, 0x7865685F, 0x0A3B0A29, 0x4E49203B, 0x5220203A
    .WORD 0x203D2031, 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x28207265, 0x7473756D, 0x20656220
    .WORD 0x39A589E2, 0x74796220, 0x0A297365, 0x2020203B, 0x52202020, 0x203D2032, 0x69736E75, 0x64656E67
    .WORD 0x746E6920, 0x72656765, 0x4F203B0A, 0x203A5455, 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x72705F0A, 0x5F746E69, 0x3A786568, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A
    .WORD 0x4C414320, 0x7469204C, 0x685F616F, 0x200A7865, 0x4D202020, 0x5220564F, 0x31522031, 0x2020200A
    .WORD 0x4C414320, 0x705F204C, 0x746E6972, 0x7274735F, 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C
    .WORD 0x52202020, 0x0A0A5445, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x705F203B, 0x746E6972
    .WORD 0x7865685F, 0x46202D20, 0x616D726F, 0x6E612074, 0x72702064, 0x20746E69, 0x75206E61, 0x6769736E
    .WORD 0x2064656E, 0x65746E69, 0x20726567, 0x68206E69, 0x28207865, 0x73657375, 0x6F746920, 0x65685F61
    .WORD 0x3B0A2978, 0x49203B0A, 0x20203A4E, 0x3D203152, 0x73656420, 0x616E6974, 0x6E6F6974, 0x66756220
    .WORD 0x20726566, 0x73756D28, 0x65622074, 0xA589E220, 0x79622039, 0x29736574, 0x20203B0A, 0x20202020
    .WORD 0x3D203252, 0x736E7520, 0x656E6769, 0x6E692064, 0x65676574, 0x203B0A72, 0x3A54554F, 0x6E6F6E20
    .WORD 0x2D3B0A65, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x705F0A2D, 0x746E6972, 0x6E69625F, 0x20200A3A
    .WORD 0x55502020, 0x4C204853, 0x20200A52, 0x41432020, 0x69204C4C, 0x5F616F74, 0x0A6E6962, 0x20202020
    .WORD 0x20564F4D, 0x52203152, 0x20200A31, 0x41432020, 0x5F204C4C, 0x6E697270, 0x74735F74, 0x676E6972
    .WORD 0x2020200A, 0x504F5020, 0x0A524C20, 0x20202020, 0x0A544552, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x5F203B0A, 0x6E697270, 0x636F5F74, 0x202D2074, 0x6D726F46, 0x61207461, 0x7020646E
    .WORD 0x746E6972, 0x206E6120, 0x69736E75, 0x64656E67, 0x746E6920, 0x72656765, 0x206E6920, 0x6174636F
    .WORD 0x7528206C, 0x20736573, 0x616F7469, 0x74636F5F, 0x0A3B0A29, 0x4E49203B, 0x5220203A, 0x203D2031
    .WORD 0x74736564, 0x74616E69, 0x206E6F69, 0x66667562, 0x28207265, 0x7473756D, 0x20656220, 0x39A589E2
    .WORD 0x74796220, 0x0A297365, 0x2020203B, 0x52202020, 0x203D2032, 0x69736E75, 0x64656E67, 0x746E6920
    .WORD 0x72656765, 0x4F203B0A, 0x203A5455, 0x656E6F6E, 0x2D2D3B0A, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x72705F0A, 0x5F746E69, 0x3A74636F, 0x2020200A, 0x53555020, 0x524C2048, 0x2020200A, 0x4C414320
    .WORD 0x7469204C, 0x6F5F616F, 0x200A7463, 0x4D202020, 0x5220564F, 0x31522031, 0x2020200A, 0x4C414320
    .WORD 0x705F204C, 0x746E6972, 0x7274735F, 0x0A676E69, 0x20202020, 0x20504F50, 0x200A524C, 0x52202020
    .WORD 0x0A0A5445, 0x3D3D3D3B, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x0A3D3D3D, 0x6144203B, 0x53206174, 0x69746365
    .WORD 0x3B0A6E6F, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D
    .WORD 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x3D3D3D3D, 0x730A3D3D, 0x65636170, 0x7274735F, 0x20200A3A
    .WORD 0x412E2020, 0x49494353, 0x2022205A, 0x6E0A0A22, 0x696C7765, 0x735F656E, 0x0A3A7274, 0x20202020
    .WORD 0x4353412E, 0x205A4949, 0x226E5C22, 0x68630A0A, 0x6675625F, 0x20200A3A, 0x412E2020, 0x49494353
    .WORD 0x5C22205A, 0x0A0A2230, 0x2D2D2D3B, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x0A2D2D2D, 0x7461203B, 0x3B0A696F
    .WORD 0x43203B0A, 0x65766E6F, 0x64207472, 0x6D696365, 0x41206C61, 0x49494353, 0x72747320, 0x20676E69
    .WORD 0x73206F74, 0x656E6769, 0x6E692064, 0x65676574, 0x3B0A2E72, 0x49203B0A, 0x3B0A3A4E, 0x52202020
    .WORD 0x203D2031, 0x69727473, 0x7020676E, 0x746E696F, 0x3B0A7265, 0x4F203B0A, 0x0A3A5455, 0x2020203B
    .WORD 0x3D203152, 0x746E6920, 0x72656765, 0x3B0A3B0A, 0x70755320, 0x74726F70, 0x3B0A3A73, 0x22202020
    .WORD 0x22333231, 0x20203B0A, 0x312D2220, 0x0A223332, 0x2020203B, 0x0A223022, 0x203B0A3B, 0x696E694D
    .WORD 0x206C616D, 0x3233524B, 0x706D6920, 0x656D656C, 0x7461746E, 0x2E6E6F69, 0x2D2D3B0A, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D, 0x2D2D2D2D
    .WORD 0x2D2D2D2D, 0x2D2D2D2D, 0x74610A0A, 0x0A3A696F, 0x20202020, 0x48535550, 0x0A524C20, 0x20202020
    .WORD 0x48535550, 0x0A385220, 0x20202020, 0x48535550, 0x0A395220, 0x20202020, 0x48535550, 0x30315220
    .WORD 0x20200A0A, 0x4F4D2020, 0x38522056, 0x20315220, 0x20202020, 0x20202020, 0x52203B20, 0x203D2038
    .WORD 0x69727473, 0x200A676E, 0x4C202020, 0x52202049, 0x20302039, 0x20202020, 0x20202020, 0x203B2020
    .WORD 0x3D203952, 0x73657220, 0x0A746C75, 0x20202020, 0x2020494C, 0x20303152, 0x20202030, 0x20202020
    .WORD 0x3B202020, 0x30315220, 0x6E203D20, 0x74616765, 0x20657669, 0x67616C66, 0x20200A0A, 0x203B2020
    .WORD 0x63656843, 0x2D27206B, 0x20200A27, 0x444C2020, 0x32522042, 0x38525B20, 0x20200A5D, 0x4D432020
    .WORD 0x32522050, 0x20353420, 0x20202020, 0x20202020, 0x27203B20, 0x200A272D, 0x42202020, 0x6120454E
    .WORD 0x5F696F74, 0x706F6F6C, 0x2020200A, 0x20494C20, 0x20303152, 0x20200A31, 0x44412020, 0x38522044
    .WORD 0x20385220, 0x74610A31, 0x6C5F696F, 0x3A706F6F, 0x2020200A, 0x42444C20, 0x20325220, 0x5D38525B
    .WORD 0x2020200A, 0x65203B20, 0x6F20646E, 0x74732066, 0x676E6972, 0x2020200A, 0x504D4320, 0x20325220
    .WORD 0x20200A30, 0x45422020, 0x74612051, 0x645F696F, 0x0A656E6F, 0x20202020, 0x6E6F203B, 0x6120796C
    .WORD 0x70656363, 0x30272074, 0x272E2E27, 0x200A2739, 0x43202020, 0x5220504D, 0x38342032, 0x20202020
    .WORD 0x3B202020, 0x27302720, 0x2020200A, 0x544C4220, 0x6F746120, 0x6F645F69, 0x200A656E, 0x43202020
    .WORD 0x5220504D, 0x37352032, 0x20202020, 0x3B202020, 0x27392720, 0x2020200A, 0x54474220, 0x6F746120
    .WORD 0x6F645F69, 0x0A0A656E, 0x20202020, 0x6964203B, 0x20746967, 0x6863203D, 0x2D207261, 0x27302720
    .WORD 0x2020200A, 0x42555320, 0x20325220, 0x34203252, 0x200A0A38, 0x3B202020, 0x73657220, 0x20746C75
    .WORD 0x6572203D, 0x746C7573, 0x31202A20, 0x202B2030, 0x69676964, 0x20200A74, 0x494C2020, 0x33522020
    .WORD 0x0A303120, 0x20202020, 0x204C554D, 0x52203952, 0x33522039, 0x2020200A, 0x44444120, 0x20395220
    .WORD 0x52203952, 0x20200A32, 0x44412020, 0x38522044, 0x20385220, 0x20200A31, 0x20422020, 0x696F7461
    .WORD 0x6F6F6C5F, 0x74610A70, 0x645F696F, 0x3A656E6F, 0x2020200A, 0x504D4320, 0x30315220, 0x200A3120
    .WORD 0x42202020, 0x6120454E, 0x5F696F74, 0x69736F70, 0x65766974, 0x2020200A, 0x6E203B20, 0x74616765
    .WORD 0x454E2065, 0x293D2047, 0x2020200A, 0x544F4E20, 0x20395220, 0x200A3952, 0x41202020, 0x52204444
    .WORD 0x39522039, 0x610A3120, 0x5F696F74, 0x69736F70, 0x65766974, 0x20200A3A, 0x4F4D2020, 0x31522056
    .WORD 0x0A395220, 0x20202020, 0x20504F50, 0x0A303152, 0x20202020, 0x20504F50, 0x200A3952, 0x50202020
    .WORD 0x5220504F, 0x20200A38, 0x4F502020, 0x524C2050, 0x2020200A, 0x54455220, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
    .WORD 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
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
