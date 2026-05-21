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
.EQU CONSOLE_INPUT_LEN, 5
.EQU USER_WRITE_BUF, 0x6000
.EQU USER_READ_BUF,  0x6010
.org 0x1000
KBUFFER_WR:
    .SPACE 256              ; 256b
KBUFFER_RD:
    .SPACE 256              ; 256b
.org 0x2000
KERNEL_START:
0x00002000       LI SP 0x0000F000
0x00002008       MOV FP SP
0x0000200C       BL init_idt
0x00002014       BL init_page_tables
0x0000201C       BL init_scheduler
0x00002024       BL enable_vm
0x0000202C       LI R1 tasks
0x00002034       LDW SP [R1 + TASK_KSP]
0x00002038       B trap_restore
init_idt:
0x00002040       LI R1 0x00200000           ; IDT base physical address
0x00002048       LI R2 trap_entry
0x00002050       STW R2 [R1]                ; IDT[0] = trap_entry
0x00002054       LI R2 trap_entry
0x0000205C       STW R2 [R1+4]                ; IDT[1]
0x00002060       STW R2 [R1+8]                ; IDT[2]
0x00002064       STW R2 [R1+12]               ; IDT[3]
0x00002068       STW R2 [R1+24]               ; IDT[6]
0x0000206C       STW R2 [R1+64]               ; IDT[16]
0x00002070       SETIDTR R1
0x00002074       RET
init_page_tables:
0x00002078       PUSH LR
0x0000207C       LI R1 TASK0_PTBR            ; task 0 page table pointer (phys address)
0x00002084       BL map_common_kernel        ; map kernel page table for task 0 - a kernel process "idle loop" run in kernel mode
0x0000208C       LI R2 0x00005000            ; page VA -virt addr
0x00002094       LI R3 TASK0_USTACK_PA       ; page PA -phys addr (.org one)
0x0000209C       LI R4 USER_RW               ; page access matrix stored it page table entry (PTE)
0x000020A4       BL map_page
0x000020AC       LI R2 0x00006000
0x000020B4       LI R3 TASK0_DATA_PA
0x000020BC       LI R4 USER_RW
0x000020C4       BL map_page
0x000020CC       LI R1 TASK1_PTBR             ; USER task 1 page table pointer (phys address)
0x000020D4       BL map_common_kernel
0x000020DC       LI R2 0x00005000             ;page used for stack
0x000020E4       LI R3 TASK1_USTACK_PA        ; physical address - note! in virtual space virtual address can be the same (like here x05000)
0x000020EC       LI R4 USER_RW                ; so mmu does the trick and with help of tlb fast translates vpn to ppn : offset
0x000020F4       BL map_page
0x000020FC       LI R2 0x00006000             ;page used for data
0x00002104       LI R3 TASK1_DATA_PA
0x0000210C       LI R4 USER_RW
0x00002114       BL map_page
0x0000211C       LI R1 TASK2_PTBR            ; USER task 2 - same
0x00002124       BL map_common_kernel
0x0000212C       LI R2 0x00005000
0x00002134       LI R3 TASK2_USTACK_PA
0x0000213C       LI R4 USER_RW
0x00002144       BL map_page
0x0000214C       LI R2 0x00006000
0x00002154       LI R3 TASK2_DATA_PA
0x0000215C       LI R4 USER_RW
0x00002164       BL map_page
0x0000216C       LI R1 TASK0_PTBR
0x00002174       SETPTBR R1
0x00002178       POP LR
0x0000217C       RET
map_common_kernel:
0x00002180       PUSH LR
0x00002184       LI R2 0x00000000      ;page 0 - boot (0000)
0x0000218C       LI R3 0x00000000
0x00002194       LI R4 KERNEL_FLAGS
0x0000219C       BL map_page
0x000021A4       LI R2 0x00002000      ;page 1,2,3 = kernel code (2000,3000,4000)
0x000021AC       LI R3 0x00002000
0x000021B4       LI R4 KERNEL_FLAGS
0x000021BC       BL map_page
0x000021C4       LI R2 0x00003000
0x000021CC       LI R3 0x00003000
0x000021D4       LI R4 KERNEL_FLAGS
0x000021DC       BL map_page
0x000021E4       LI R2 0x00004000
0x000021EC       LI R3 0x00004000
0x000021F4       LI R4 KERNEL_FLAGS
0x000021FC       BL map_page
0x00002204       LI R2 0x00007000      ; page 4 (number is page table entry one) tasks data
0x0000220C       LI R3 0x00007000
0x00002214       LI R4 KERNEL_FLAGS
0x0000221C       BL map_page
0x00002224       LI R2 0x00008000      ; page 5 text page (program) for user mode process
0x0000222C       LI R3 0x00008000
0x00002234       LI R4 USER_RX
0x0000223C       BL map_page
0x00002244       LI R2 0x00019000      ; page 5 text page (program) for user mode process
0x0000224C       LI R3 0x00019000
0x00002254       LI R4 USER_RX
0x0000225C       BL map_page
0x00002264       LI R2 0x0001a000      ; page 5 text page (program) for user mode process
0x0000226C       LI R3 0x0001a000
0x00002274       LI R4 USER_RX
0x0000227C       BL map_page
0x00002284       LI R2 0x00001000      ; page for kernel buffers
0x0000228C       LI R3 0x00001000
0x00002294       LI R4 KERNEL_FLAGS
0x0000229C       BL map_page
0x000022A4       LI R2 PTBR0_VA
0x000022AC       LI R3 TASK0_PTBR
0x000022B4       LI R4 KERNEL_FLAGS
0x000022BC       BL map_page
0x000022C4       LI R2 PTBR1_VA
0x000022CC       LI R3 TASK1_PTBR
0x000022D4       LI R4 KERNEL_FLAGS
0x000022DC       BL map_page
0x000022E4       LI R2 PTBR2_VA
0x000022EC       LI R3 TASK2_PTBR
0x000022F4       LI R4 KERNEL_FLAGS
0x000022FC       BL map_page
0x00002304       POP LR
0x00002308       RET
map_page:
0x0000230C       SHR R5 R2 12               ; VPN
0x00002310       SHL R5 R5 2                ; page-table byte offset
0x00002314       OR R6 R3 R4                ; PTE = PA page base | flags
0x00002318       STW R6 [R1 + R5]
0x0000231C       RET
enable_vm:
0x00002320       ENABLEMMU
0x00002324       RET
trap_entry:
0x00002328       CSRRW SP SSCRATCH SP
0x0000232C       PUSH R1
0x00002330       PUSH R2
0x00002334       PUSH R3
0x00002338       PUSH R4
0x0000233C       PUSH R5
0x00002340       PUSH R6
0x00002344       PUSH R7
0x00002348       PUSH R8
0x0000234C       PUSH R9
0x00002350       PUSH R10
0x00002354       PUSH R11
0x00002358       PUSH R12
0x0000235C       PUSH R14
0x00002360       PUSH R15
0x00002364       CSRR R1 SSCRATCH
0x00002368       PUSH R1
0x0000236C       CSRR R1 SEPC
0x00002370       PUSH R1
0x00002374       CSRR R1 SFLAGS
0x00002378       PUSH R1
0x0000237C       CSRR R1 SSTATUS
0x00002380       PUSH R1
0x00002384       CSRR R1 SCAUSE
0x00002388       PUSH R1
0x0000238C       CSRR R1 STVAL
0x00002390       PUSH R1
0x00002394       CSRR R1 SCAUSE
0x00002398       CMP R1 0
0x0000239C       BEQ handle_divide_zero
0x000023A4       CMP R1 1
0x000023A8       BEQ handle_invalid_instr
0x000023B0       CMP R1 2
0x000023B4       BEQ handle_page_fault
0x000023BC       CMP R1 3
0x000023C0       BEQ handle_syscall
0x000023C8       CMP R1 6
0x000023CC       BEQ handle_debug
0x000023D4       CMP R1 16
0x000023D8       BEQ handle_irq
0x000023E0       HLT
handle_divide_zero:
0x000023E4       B trap_restore
handle_invalid_instr:
0x000023EC       B trap_restore
handle_page_fault:
0x000023F4       HLT
0x000023F8       B trap_restore
handle_syscall:
0x00002400       CSRR R2 STVAL
0x00002404       CMP R2 SYS_COUNT
0x00002408       BGE syscall_unknown
0x00002410       LI R3 syscall_table         ;compute entry by SVC x number and execute call function call on address on R5
0x00002418       SHL R4 R2 2
0x0000241C       LDW R5 [R3 + R4]
0x00002420       JR R5
syscall_unknown:
0x00002424       LI R1 0xFFFFFFFF                    ; R1 has error code FFFF
0x0000242C       STW R1 [SP + TF_R1]
0x00002430       B trap_restore
syscall_table:
    .WORD syscall_yield         ; SVC 0
    .WORD syscall_exit          ; SVC 1
    .WORD syscall_getpid        ; SVC 2
    .WORD syscall_debug         ; SVC 3
    .WORD syscall_write         ; SVC 4
    .WORD syscall_read          ; SVC 5
syscall_yield:
0x00002450       LI R1 0
0x00002458       STW R1 [SP + TF_R1]         ; r1=0 - success
0x0000245C       B schedule_and_switch
syscall_exit:               ; basically a call from task to remove from scheduler so it wont be executed
0x00002464       LI R1 CURRENT_TASK
0x0000246C       LDW R2 [R1]
0x00002470       LI R3 TASK_SIZE
0x00002478       MUL R4 R2 R3
0x0000247C       LI R5 tasks
0x00002484       ADD R5 R5 R4
0x00002488       LI R6 0                     ;0 to disable this task
0x00002490       STW R6 [R5 + TASK_ACTIVE]
0x00002494       LI R1 0
0x0000249C       STW R1 [SP + TF_R1]         ; r1=0 - return success
0x000024A0       B schedule_and_switch
syscall_getpid:
0x000024A8       LI R1 CURRENT_TASK
0x000024B0       LDW R2 [R1]
0x000024B4       LI R3 TASK_SIZE
0x000024BC       MUL R4 R2 R3
0x000024C0       LI R5 tasks
0x000024C8       ADD R5 R5 R4
0x000024CC       LDW R1 [R5 + TASK_PID]        ; get pid from task scheduler data
0x000024D0       STW R1 [SP + TF_R1]           ; save it to its trapframe which goes back when it s next time this task resumes
0x000024D4       B trap_restore
syscall_debug:
0x000024DC       LDW R1 [SP + TF_R1]
0x000024E0       STW R1 [SP + TF_R1]
0x000024E4       B trap_restore
syscall_read:
0x000024EC       LDW R1 [SP + TF_R1]
0x000024F0       LDW R2 [SP + TF_R2]
0x000024F4       LDW R3 [SP + TF_R3]
0x000024F8       MOV R7 R2               ; save user buffer
0x000024FC       MOV R6 R3               ; save length
0x00002500       PUSH R7
0x00002504       PUSH R6
0x00002508       LI R2 FD_FLAG_READ      ; pass flags in R2 per fetch_fd_entry convention
0x00002510       BL fetch_fd_entry
0x00002518       POP R6
0x0000251C       POP R7
0x00002520       CMP R1 0
0x00002524       BEQ bad_fd
0x0000252C       MOV R9 R1               ; device object pointer /dev/console for example
0x00002530       CMP R6 0
0x00002534       BEQ read_done
0x0000253C       PUSH R7
0x00002540       PUSH R6
0x00002544       PUSH R9
0x00002548       MOV R1 R7
0x0000254C       MOV R2 R6
0x00002550       LI R3 1                ; write access for destination buffer
0x00002558       BL user_buffer_valid_range
0x00002560       POP R9
0x00002564       POP R6
0x00002568       POP R7
0x0000256C       CMP R1 1
0x00002570       BNE bad_pointer
0x00002578       PUSH R7
0x0000257C       LI R1 KBUFFER_RD
0x00002584       MOV R2 R6
0x00002588       MOV R3 R9
0x0000258C       BL device_read          ; read from device fake string console_input - like buffer and copy to kernel buffer  
0x00002594       POP R7
0x00002598       CMP R1 0
0x0000259C       BEQ read_done
0x000025A4       MOV R2 R1              ; actual bytes read
0x000025A8       MOV R1 R7              ; user destination
0x000025AC       MOV R4 KBUFFER_RD
0x000025B0       BL copy_to_user        ; copy from kernel buffer to user buffer
0x000025B8       STW R1 [SP + TF_R1]
0x000025BC       B trap_restore
read_done:
0x000025C4       LI R1 0
0x000025CC       STW R1 [SP + TF_R1]
0x000025D0       B trap_restore
syscall_write:
0x000025D8       LDW R1 [SP + TF_R1]
0x000025DC       LDW R2 [SP + TF_R2]
0x000025E0       LDW R3 [SP + TF_R3]
0x000025E4       MOV R7 R2               ; save user buffer
0x000025E8       MOV R6 R3               ; save length
0x000025EC       PUSH R7
0x000025F0       PUSH R6
0x000025F4       LI R2 FD_FLAG_WRITE     ; pass flags in R2 per fetch_fd_entry convention
0x000025FC       BL fetch_fd_entry
0x00002604       POP R6
0x00002608       POP R7
0x0000260C       CMP R1 0
0x00002610       BEQ bad_fd
0x00002618       MOV R9 R1               ; device object pointer
0x0000261C       LI R8 0                ; total written
write_loop:
0x00002624       CMP R6 0
0x00002628       BEQ write_done
0x00002630       LI R2 KBUFFER_SIZE
0x00002638       CMP R6 R2
0x0000263C       BLT write_chunk_small
0x00002644       LI R2 KBUFFER_SIZE
0x0000264C       B write_chunk
write_chunk_small:
0x00002654       MOV R2 R6
write_chunk:
0x00002658       PUSH R7
0x0000265C       PUSH R6
0x00002660       PUSH R9
0x00002664       MOV R1 R7
0x00002668       MOV R2 R2
0x0000266C       LI R3 0                ; read access for source buffer
0x00002674       BL user_buffer_valid_range
0x0000267C       POP R9
0x00002680       POP R6
0x00002684       POP R7
0x00002688       CMP R1 1
0x0000268C       BNE bad_pointer
0x00002694       MOV R1 R7
0x00002698       MOV R4 KBUFFER_WR
0x0000269C       BL copy_from_user
0x000026A4       MOV R10 R1             ; bytes copied
0x000026A8       PUSH R7
0x000026AC       PUSH R9
0x000026B0       MOV R1 KBUFFER_WR
0x000026B4       MOV R2 R10
0x000026B8       MOV R3 R9
0x000026BC       BL device_write
0x000026C4       POP R9
0x000026C8       POP R7
0x000026CC       ADD R8 R8 R1
0x000026D0       ADD R7 R7 R10
0x000026D4       SUB R6 R6 R10
0x000026D8       B write_loop
write_done:
0x000026E0       MOV R1 R8
0x000026E4       STW R1 [SP + TF_R1]
0x000026E8       B trap_restore
bad_fd:
0x000026F0       LI R1 0xFFFF
0x000026F8       STW R1 [SP + TF_R1]
0x000026FC       B trap_restore
bad_pointer:
0x00002704       LI R1 0xFFFF
0x0000270C       STW R1 [SP + TF_R1]
0x00002710       B trap_restore
device_read:
0x00002718       LDW R4 [R3 + DEV_OFF_READ]
0x0000271C       JR R4
device_write:
0x00002720       LDW R4 [R3 + DEV_OFF_WRITE]
0x00002724       JR R4
dev_console_read:
0x00002728       LI R4 CONSOLE_INPUT_LEN
0x00002730       CMP R4 R2
0x00002734       BLT dr_use_len
0x0000273C       MOV R4 R2
dr_use_len:
0x00002740       LI R5 console_input
0x00002748       MOV R6 R4
dr_copy_loop:
0x0000274C       CMP R6 0
0x00002750       BEQ dr_done
0x00002758       LDB R7 [R5]
0x0000275C       STB R7 [R1]
0x00002760       ADD R1 R1 1
0x00002764       ADD R5 R5 1
0x00002768       SUB R6 R6 1
0x0000276C       B dr_copy_loop
dr_done:
0x00002774       MOV R1 R4
0x00002778       RET
dev_console_write:
0x0000277C       LI R3 0
dcw_loop:
0x00002784       CMP R3 R2
0x00002788       BGE dcw_done
0x00002790       LDB R4 [R1 + R3]
0x00002794       ADD R3 R3 1
0x00002798       B dcw_loop
dcw_done:
0x000027A0       MOV R1 R2
0x000027A4       RET
fetch_fd_entry:
0x000027A8       CMP R1 0
0x000027AC       BLT fd_invalid
0x000027B4       CMP R1 3
0x000027B8       BGE fd_invalid
0x000027C0       LI R4 CURRENT_TASK
0x000027C8       LDW R4 [R4]
0x000027CC       LI R5 TASK_SIZE
0x000027D4       MUL R4 R4 R5
0x000027D8       LI R5 tasks
0x000027E0       ADD R4 R4 R5
0x000027E4       LDW R4 [R4 + TASK_FD_TABLE]
0x000027E8       SHL R5 R1 3
0x000027EC       ADD R4 R4 R5
0x000027F0       LDW R6 [R4 + FD_ENTRY_FLAGS]
0x000027F4       AND R6 R6 R2
0x000027F8       CMP R6 R2
0x000027FC       BNE fd_invalid
0x00002804       LDW R1 [R4 + FD_ENTRY_DEVICE]
0x00002808       RET
fd_invalid:
0x0000280C       LI R1 0
0x00002814       RET
user_buffer_valid_range:
0x00002818       LI R4 0
0x00002820       CMP R2 R4
0x00002824       BEQ uv_valid
0x0000282C       LI R4 USER_BASE
0x00002834       CMP R1 R4
0x00002838       BLT uv_invalid
0x00002840       LI R4 USER_LIMIT
0x00002848       ADD R5 R1 R2
0x0000284C       SUB R5 R5 1
0x00002850       CMP R5 R1
0x00002854       BLT uv_invalid
0x0000285C       CMP R5 R4
0x00002860       BGT uv_invalid
0x00002868       MOV R12 R5              ; save end address for page calculation
0x0000286C       LI R6 CURRENT_TASK
0x00002874       LDW R6 [R6]
0x00002878       LI R7 TASK_SIZE
0x00002880       MUL R6 R6 R7
0x00002884       LI R7 tasks
0x0000288C       ADD R6 R6 R7
0x00002890       LDW R6 [R6 + TASK_PTBR]
0x00002894       LI R7 TASK0_PTBR
0x0000289C       CMP R6 R7
0x000028A0       BEQ uv_ptbr0
0x000028A8       LI R7 TASK1_PTBR
0x000028B0       CMP R6 R7
0x000028B4       BEQ uv_ptbr1
0x000028BC       LI R7 TASK2_PTBR
0x000028C4       CMP R6 R7
0x000028C8       BEQ uv_ptbr2
0x000028D0       B uv_invalid
uv_ptbr0:
0x000028D8       LI R6 PTBR0_VA
0x000028E0       B uv_check_pages
uv_ptbr1:
0x000028E8       LI R6 PTBR1_VA
0x000028F0       B uv_check_pages
uv_ptbr2:
0x000028F8       LI R6 PTBR2_VA
uv_check_pages:
0x00002900       SHR R7 R1 12
0x00002904       SHR R8 R12 12
uv_loop:
0x00002908       CMP R7 R8
0x0000290C       BGT uv_valid
0x00002914       SHL R9 R7 2
0x00002918       ADD R9 R9 R6
0x0000291C       LDW R10 [R9]
0x00002920       AND R11 R10 PTE_P
0x00002924       CMP R11 0
0x00002928       BEQ uv_invalid
0x00002930       AND R11 R10 PTE_U
0x00002934       CMP R11 0
0x00002938       BEQ uv_invalid
0x00002940       CMP R3 0
0x00002944       BEQ uv_check_read
0x0000294C       AND R11 R10 PTE_W
0x00002950       CMP R11 0
0x00002954       BEQ uv_invalid
0x0000295C       B uv_next
uv_check_read:
0x00002964       AND R11 R10 PTE_R
0x00002968       CMP R11 0
0x0000296C       BEQ uv_invalid
uv_next:
0x00002974       ADD R7 R7 1
0x00002978       B uv_loop
uv_valid:
0x00002980       LI R1 1
0x00002988       RET
uv_invalid:
0x0000298C       LI R1 0
0x00002994       RET
copy_from_user:
0x00002998       LI R5 0
cfu_head:
0x000029A0       CMP R2 0
0x000029A4       BEQ cfu_done
0x000029AC       OR R6 R1 R4
0x000029B0       AND R6 R6 3
0x000029B4       CMP R6 0
0x000029B8       BEQ cfu_word
0x000029C0       LDB R7 [R1]
0x000029C4       STB R7 [R4]
0x000029C8       ADD R1 R1 1
0x000029CC       ADD R4 R4 1
0x000029D0       ADD R5 R5 1
0x000029D4       SUB R2 R2 1
0x000029D8       B cfu_head
cfu_word:
0x000029E0       CMP R2 4
0x000029E4       BLT cfu_tail
0x000029EC       LDW R7 [R1]
0x000029F0       STW R7 [R4]
0x000029F4       ADD R1 R1 4
0x000029F8       ADD R4 R4 4
0x000029FC       ADD R5 R5 4
0x00002A00       SUB R2 R2 4
0x00002A04       B cfu_word
cfu_tail:
0x00002A0C       CMP R2 0
0x00002A10       BEQ cfu_done
0x00002A18       LDB R7 [R1]
0x00002A1C       STB R7 [R4]
0x00002A20       ADD R1 R1 1
0x00002A24       ADD R4 R4 1
0x00002A28       ADD R5 R5 1
0x00002A2C       SUB R2 R2 1
0x00002A30       B cfu_tail
cfu_done:
0x00002A38       MOV R1 R5
0x00002A3C       RET
copy_to_user:
0x00002A40       LI R5 0
ctu_head:
0x00002A48       CMP R2 0
0x00002A4C       BEQ ctu_done
0x00002A54       OR R6 R1 R4
0x00002A58       AND R6 R6 3
0x00002A5C       CMP R6 0
0x00002A60       BEQ ctu_word
0x00002A68       LDB R7 [R4]
0x00002A6C       STB R7 [R1]
0x00002A70       ADD R1 R1 1
0x00002A74       ADD R4 R4 1
0x00002A78       ADD R5 R5 1
0x00002A7C       SUB R2 R2 1
0x00002A80       B ctu_head
ctu_word:
0x00002A88       CMP R2 4
0x00002A8C       BLT ctu_tail
0x00002A94       LDW R7 [R4]
0x00002A98       STW R7 [R1]
0x00002A9C       ADD R1 R1 4
0x00002AA0       ADD R4 R4 4
0x00002AA4       ADD R5 R5 4
0x00002AA8       SUB R2 R2 4
0x00002AAC       B ctu_word
ctu_tail:
0x00002AB4       CMP R2 0
0x00002AB8       BEQ ctu_done
0x00002AC0       LDB R7 [R4]
0x00002AC4       STB R7 [R1]
0x00002AC8       ADD R1 R1 1
0x00002ACC       ADD R4 R4 1
0x00002AD0       ADD R5 R5 1
0x00002AD4       SUB R2 R2 1
0x00002AD8       B ctu_tail
ctu_done:
0x00002AE0       MOV R1 R5
0x00002AE4       RET
handle_debug:
0x00002AE8       B trap_restore
handle_irq:
0x00002AF0       CSRR R1 STVAL
0x00002AF4       EOI R1
0x00002AF8       B schedule_and_switch
trap_restore:               ; this does a resume of task restores state frame
0x00002B00       POP R1                  ; stval, informational only
0x00002B04       POP R1                  ; scause, informational only
0x00002B08       POP R1
0x00002B0C       CSRW SSTATUS R1
0x00002B10       POP R1
0x00002B14       CSRW SFLAGS R1
0x00002B18       POP R1
0x00002B1C       CSRW SEPC R1
0x00002B20       POP R1                  ; interrupted task SP
0x00002B24       CSRW SSCRATCH R1        ; task SP goes to SSCRATCH
0x00002B28       POP R15
0x00002B2C       POP R14
0x00002B30       POP R12
0x00002B34       POP R11
0x00002B38       POP R10
0x00002B3C       POP R9
0x00002B40       POP R8
0x00002B44       POP R7
0x00002B48       POP R6
0x00002B4C       POP R5
0x00002B50       POP R4
0x00002B54       POP R3
0x00002B58       POP R2
0x00002B5C       POP R1
0x00002B60       CSRRW SP SSCRATCH SP
0x00002B64       SRET
.EQU TASK_KSP,     0          ; saved kernel trapframe stack pointer
.EQU TASK_USP,     4          ; last saved interrupted task stack pointer
.EQU TASK_PC,      8          ; debug/metadata: entry or last known PC
.EQU TASK_ACTIVE, 12
.EQU TASK_PID,    16
.EQU TASK_PTBR,   20         ; physical base of this task's page table
.EQU TASK_FD_TABLE, 24       ; pointer to task file descriptor table
.EQU TASK_SIZE,   28
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
.EQU SYS_YIELD,    0
.EQU SYS_EXIT,     1
.EQU SYS_GETPID,   2
.EQU SYS_DEBUG,    3
.EQU SYS_WRITE,    4
.EQU SYS_READ,     5
.EQU SYS_COUNT,    6
.ORG 0x7000
tasks:
    .SPACE 84              ; 3 tasks * 28 bytes
CURRENT_TASK:
    .WORD 0
fd_table:
    .WORD console_dev
    .WORD FD_FLAG_READ
    .WORD console_dev
    .WORD FD_FLAG_WRITE
    .WORD console_dev
    .WORD FD_FLAG_WRITE
console_dev:
    .WORD dev_console_read
    .WORD dev_console_write
console_input:
    .WORD 0x41544144      ; "DATA"
    .WORD 0x0A000000      ; "\n"
.EQU TASK0_KSTACK_TOP, 0x4000
.EQU TASK1_KSTACK_TOP, 0x4200
.EQU TASK2_KSTACK_TOP, 0x4400
.EQU TASK0_USTACK_TOP, 0x6000
.EQU TASK1_USTACK_TOP, 0x6000
.EQU TASK2_USTACK_TOP, 0x6000
init_scheduler:
0x00007080       MOV R12 SP ;important we save kernel sp becuse we form stack frame at tasks SPs
0x00007084       LI SP TASK0_KSTACK_TOP
0x0000708C       LI R1 0
0x00007094       PUSH R1                  ; R1
0x00007098       PUSH R1                  ; R2
0x0000709C       PUSH R1                  ; R3
0x000070A0       PUSH R1                  ; R4
0x000070A4       PUSH R1                  ; R5
0x000070A8       PUSH R1                  ; R6
0x000070AC       PUSH R1                  ; R7
0x000070B0       PUSH R1                  ; R8
0x000070B4       PUSH R1                  ; R9
0x000070B8       PUSH R1                  ; R10
0x000070BC       PUSH R1                  ; R11
0x000070C0       PUSH R1                  ; R12
0x000070C4       PUSH R1                  ; R14
0x000070C8       PUSH R1                  ; R15
0x000070CC       LI R1 TASK0_USTACK_TOP
0x000070D4       PUSH R1                  ; interrupted task SP restored by CSRRW before SRET
0x000070D8       LI R1 idle_task
0x000070E0       PUSH R1                  ; sepc - this is new place of PC in trap frame
0x000070E4       LI R1 0
0x000070EC       PUSH R1                  ; sflags
0x000070F0       LI R1 0x120
0x000070F8       PUSH R1                  ; sstatus.SPIE|SPP: idle resumes as supervisor task
0x000070FC       LI R1 0
0x00007104       PUSH R1                  ; scause
0x00007108       PUSH R1                  ; stval - other valuable s-data on top (or bottom-)
0x0000710C       LI R2 tasks
0x00007114       MOV R1 SP
0x00007118       STW R1 [R2 + TASK_KSP]  ; save kernel trapframe SP
0x0000711C       LI R1 TASK0_USTACK_TOP
0x00007124       STW R1 [R2 + TASK_USP]  ; save initial task stack SP for debug/metadata
0x00007128       LI R1 idle_task
0x00007130       STW R1 [R2 + TASK_PC]   ;start PC of the task
0x00007134       LI R1 1
0x0000713C       STW R1 [R2 + TASK_ACTIVE] ;set this task as as active
0x00007140       LI R1 0
0x00007148       STW R1 [R2 + TASK_PID]   ;set PID=0 for this task
0x0000714C       LI R1 TASK0_PTBR
0x00007154       STW R1 [R2 + TASK_PTBR]
0x00007158       LI R1 fd_table
0x00007160       STW R1 [R2 + TASK_FD_TABLE]
0x00007164       LI SP TASK1_KSTACK_TOP
0x0000716C       LI R1 0
0x00007174       PUSH R1                  ; R1
0x00007178       PUSH R1                  ; R2
0x0000717C       PUSH R1                  ; R3
0x00007180       PUSH R1                  ; R4
0x00007184       PUSH R1                  ; R5
0x00007188       PUSH R1                  ; R6
0x0000718C       PUSH R1                  ; R7
0x00007190       PUSH R1                  ; R8
0x00007194       PUSH R1                  ; R9
0x00007198       PUSH R1                  ; R10
0x0000719C       PUSH R1                  ; R11
0x000071A0       PUSH R1                  ; R12
0x000071A4       PUSH R1                  ; R14
0x000071A8       PUSH R1                  ; R15
0x000071AC       LI R1 TASK1_USTACK_TOP
0x000071B4       PUSH R1                  ; interrupted task SP
0x000071B8       LI R1 TASK_A_START
0x000071C0       PUSH R1                  ; sepc
0x000071C4       LI R1 0
0x000071CC       PUSH R1                  ; sflags
0x000071D0       LI R1 0x20
0x000071D8       PUSH R1                  ; sstatus.SPIE
0x000071DC       LI R1 0
0x000071E4       PUSH R1                  ; scause
0x000071E8       PUSH R1                  ; stval
0x000071EC       LI R2 tasks
0x000071F4       ADD R2 R2 TASK_SIZE
0x000071F8       MOV R1 SP
0x000071FC       STW R1 [R2 + TASK_KSP]
0x00007200       LI R1 TASK1_USTACK_TOP
0x00007208       STW R1 [R2 + TASK_USP]
0x0000720C       LI R1 TASK_A_START
0x00007214       STW R1 [R2 + TASK_PC]
0x00007218       LI R1 1
0x00007220       STW R1 [R2 + TASK_ACTIVE]
0x00007224       LI R1 1
0x0000722C       STW R1 [R2 + TASK_PID]
0x00007230       LI R1 TASK1_PTBR
0x00007238       STW R1 [R2 + TASK_PTBR]
0x0000723C       LI R1 fd_table
0x00007244       STW R1 [R2 + TASK_FD_TABLE]
0x00007248       LI SP TASK2_KSTACK_TOP
0x00007250       LI R1 0
0x00007258       PUSH R1                  ; R1
0x0000725C       PUSH R1                  ; R2
0x00007260       PUSH R1                  ; R3
0x00007264       PUSH R1                  ; R4
0x00007268       PUSH R1                  ; R5
0x0000726C       PUSH R1                  ; R6
0x00007270       PUSH R1                  ; R7
0x00007274       PUSH R1                  ; R8
0x00007278       PUSH R1                  ; R9
0x0000727C       PUSH R1                  ; R10
0x00007280       PUSH R1                  ; R11
0x00007284       PUSH R1                  ; R12
0x00007288       PUSH R1                  ; R14
0x0000728C       PUSH R1                  ; R15
0x00007290       LI R1 TASK2_USTACK_TOP
0x00007298       PUSH R1                  ; interrupted task SP
0x0000729C       LI R1 TASK_B_START
0x000072A4       PUSH R1                  ; sepc
0x000072A8       LI R1 0
0x000072B0       PUSH R1                  ; sflags
0x000072B4       LI R1 0x20
0x000072BC       PUSH R1                  ; sstatus.SPIE
0x000072C0       LI R1 0
0x000072C8       PUSH R1                  ; scause
0x000072CC       PUSH R1                  ; stval
0x000072D0       LI R2 tasks
0x000072D8       LI R3 TASK_SIZE
0x000072E0       ADD R2 R2 R3
0x000072E4       ADD R2 R2 R3
0x000072E8       MOV R1 SP
0x000072EC       STW R1 [R2 + TASK_KSP]
0x000072F0       LI R1 TASK2_USTACK_TOP
0x000072F8       STW R1 [R2 + TASK_USP]
0x000072FC       LI R1 TASK_B_START
0x00007304       STW R1 [R2 + TASK_PC]
0x00007308       LI R1 1
0x00007310       STW R1 [R2 + TASK_ACTIVE]
0x00007314       LI R1 2
0x0000731C       STW R1 [R2 + TASK_PID]
0x00007320       LI R1 TASK2_PTBR
0x00007328       STW R1 [R2 + TASK_PTBR]
0x0000732C       LI R1 fd_table
0x00007334       STW R1 [R2 + TASK_FD_TABLE]
0x00007338       LI R1 CURRENT_TASK
0x00007340       LI R2 0
0x00007348       STW R2 [R1]
0x0000734C       MOV SP R12 ;restore kernel SP after finsh dealing with tasks SPs
0x00007350       RET
schedule_and_switch:
0x00007354       LI R1 CURRENT_TASK
0x0000735C       LDW R2 [R1]                ; R2 = old task index
0x00007360       ADD R3 R2 1
wrap_check:
0x00007364       CMP R3 3
0x00007368       BLT check_task
0x00007370       LI R3 0              ;R3 next task (1) ;R2 current task (0) for eg
check_task:
0x00007378       LI R4 TASK_SIZE
0x00007380       MUL R5 R3 R4
0x00007384       LI R6 tasks
0x0000738C       ADD R5 R5 R6               ; R5 = &tasks[R3]
0x00007390       LDW R7 [R5 + TASK_ACTIVE]
0x00007394       CMP R7 1
0x00007398       BEQ do_switch
0x000073A0       ADD R3 R3 1
0x000073A4       B wrap_check
do_switch:
0x000073AC       STW R3 [R1]
0x000073B0       LI R4 TASK_SIZE
0x000073B8       MUL R5 R2 R4
0x000073BC       LI R6 tasks
0x000073C4       ADD R5 R5 R6               ; R5 = &tasks[old]
0x000073C8       LDW R7 [SP + TF_USP]
0x000073CC       STW R7 [R5 + TASK_USP]
0x000073D0       MOV R7 SP
0x000073D4       STW R7 [R5 + TASK_KSP]
0x000073D8       LI R4 TASK_SIZE
0x000073E0       MUL R5 R3 R4
0x000073E4       LI R6 tasks
0x000073EC       ADD R5 R5 R6               ; R5 = &tasks[new]
0x000073F0       LDW R7 [R5 + TASK_PTBR]
0x000073F4       SETPTBR R7              ; switch address space; VM flushes non-global TLB entries
0x000073F8       LDW SP [R5 + TASK_KSP] ; load next task's kernel trapframe
0x000073FC       B trap_restore
.ORG 0x8000
idle_task:
0x00008000       ENABLEINT
0x00008004       LI R1 0
idle_loop:
0x0000800C       ADD R1 R1 1
0x00008010       DEBUG 1 
0x00008014       B idle_loop
.ORG 0x19000
TASK_A_START:
0x00019000       LI R1 USER_WRITE_BUF
0x00019008       LI R2 0x6C6C6548         ; "Hell"
0x00019010       STW R2 [R1]
0x00019014       LI R2 0x57202C6F         ; "o, W"
0x0001901C       STW R2 [R1 + 4]
0x00019020       LI R2 0x21646C72         ; "rld!"
0x00019028       STW R2 [R1 + 8]
0x0001902C       LI R2 0x0A
0x00019034       STB R2 [R1 + 12]
0x00019038       LI R1 1
0x00019040       LI R2 USER_WRITE_BUF
0x00019048       LI R3 13
0x00019050       SVC SYS_WRITE
0x00019054       DEBUG 2
0x00019058       LI R1 SYS_EXIT
0x00019060       SVC SYS_EXIT
.org 0x1a000
TASK_B_START:
0x0001A000       TRACE 1
0x0001A004       LI R1 0
0x0001A00C       DEBUG 2
0x0001A010       LI R2 USER_READ_BUF
0x0001A018       LI R3 CONSOLE_INPUT_LEN
0x0001A020       SVC SYS_READ
0x0001A024       DEBUG 2
0x0001A028       LI R4 USER_READ_BUF
0x0001A030       STW R1 [R4 + 8]
0x0001A034       TRACE 0
0x0001A038       HLT
0x0001A03C       LI R1 SYS_EXIT
0x0001A044       SVC SYS_EXIT
[ASM] Listing generated, binary output skipped
