KERNEL_START:

    LI SP 0x0000F000
    MOV FP SP

    ; allocate page table at 0x100000 (1MB), size 4MB
    LI R1 0x00100000  ; PT base
    LI R2 10         ; num entries for test
    LI R3 0           ; vpn counter

init_loop:
    ; PTE: PPN = vpn, flags = PRESENT|READ|WRITE|EXEC|USER
    MOV R4 R3       ; PPN = vpn
    SHL R4 R4 12    ; shift to high bits
    LI R6 0x001F    ; flags
    OR R4 R4 R6     ; add flags
    SHL R5 R3 2     ; offset = vpn * 4
    STW R4 R1 R5    ; store PTE

    ADD R3 R3 1
    CMP R3 R2
    BNE init_loop

    ; set PTBR
    LI R1 0x00100000
    SETPTBR R1

    ; enable MMU
    ENABLEMMU

    BL USER_START
    HLT
