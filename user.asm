USER_START:

    ; Calling convention: R1=arg0, R2=arg1, R3=arg2, R4=arg3
    ; Return value is delivered in R1. R5-R11 are caller-saved.
    LI R2 5           ; word count
    ARG1 R2
    CALLEX fill_array

    ; exercise byte/halfword loads and stores
    LI R6 0x00008100
    LI R7 0x000000AB
    STB R7 R6 0
    LI R7 0x0000CDEF
    STH R7 R6 2
    LDB R8 R6 0
    LDH R9 R6 2
    LDW R10 R1 0

    ; signed load checks
    LI R7 0xFFFFFF80
    STB R7 R6 4
    LDBS R8 R6 4

    LI R7 0xFFFF8001
    STH R7 R6 6
    LDHS R9 R6 6

    ; ALU and signed branch checks, results at 0x8200
    LI R11 0x00008200

    LI R7 6
    LI R8 7
    MUL R9 R7 R8
    STW R9 R11 0

    LI R7 0x00000F0F
    AND R9 R7 15
    STW R9 R11 4

    OR R9 R9 112
    STW R9 R11 8

    XOR R9 R9 85
    STW R9 R11 12

    SHL R9 R9 1
    STW R9 R11 16

    SHR R9 R9 1
    STW R9 R11 20

    LI R7 0xFFFFFF80
    SAR R9 R7 4
    STW R9 R11 24

    CMP R9 0
    BLT signed_negative_ok
    LI R9 0xBAD00001

signed_negative_ok:

    LI R9 0x12345678
    STW R9 R11 28

    CMP R2 5
    BGE count_ok
    LI R9 0xBAD00002

count_ok:

    LI R9 0xCAFEBABE
    STW R9 R11 32

    CMP R2 10
    BLE less_equal_ok
    LI R9 0xBAD00003

less_equal_ok:

    LI R9 0x0B1E0001
    STW R9 R11 36

    CMP R2 1
    BGT greater_ok
    LI R9 0xBAD00004

greater_ok:

    LI R9 0x0B670001
    STW R9 R11 40

    ; divide/modulo and unsigned branch checks
    LI R7 0xFFFFFFF3  ; -13
    LI R8 0           ; 0 make trap div by 0
    DIV R9 R7 R8

    DEBUG

    STW R9 R11 44

    MOD R9 R7 R8
    STW R9 R11 48

    LI R7 13
    LI R8 5
    DIVU R9 R7 R8
    STW R9 R11 52

    MODU R9 R7 R8
    STW R9 R11 56

    LI R7 1
    LI R8 2
    CMP R7 R8
    BLTU unsigned_less_ok
    LI R9 0xBAD00005

unsigned_less_ok:

    LI R9 0x0B1A0001
    STW R9 R11 60

    CMP R7 R8
    BLEU unsigned_less_equal_ok
    LI R9 0xBAD00006

unsigned_less_equal_ok:

    LI R9 0x0B1B0001
    STW R9 R11 64

    LI R7 3
    LI R8 2
    CMP R7 R8
    BGTU unsigned_greater_ok
    LI R9 0xBAD00007

unsigned_greater_ok:

    LI R9 0x0B1C0001
    STW R9 R11 68

    CMP R7 R8
    BGEU unsigned_greater_equal_ok
    LI R9 0xBAD00008

unsigned_greater_equal_ok:

    LI R9 0x0B1D0001
    STW R9 R11 72

    DEBUG 3
    LI R1 0x00300000
    LDW R2 R1 0
    SVC 1
    ; HLT  ; Remove HLT to loop

loop_forever:
    ;DEBUG 2
    B loop_forever


fill_array:
    ; Input: R1 = word count
    ; Return: R1 = word count
    ; Creates local array on stack, fills it, then returns.
    ; Uses caller-saved registers R3-R6; preserves FP/LR/SP.

    FUNC_ENTER

    ; Preserve the incoming argument for return
    MOV R2 R1

    ; Allocate space for local array (R1 words = R1*4 bytes)
    MOV R3 R1
    SHL R3 R3 2         ; convert words to bytes
    SUB SP SP R3        ; allocate on stack

    ; Stack frame now:
    ; [FP]     = saved FP
    ; [FP-4]   = saved LR
    ; [FP-8..] = local array starts here

    MOV R3 R2           ; R3 = loop counter (word count)
    MOV R4 0            ; R4 = byte offset into local array

loop:
    MOV R5 R3           ; value = counter (count down from R2)

    ; Calculate address: FP - 8 - offset
    MOV R6 FP
    SUB R6 R6 8         ; point to local array start
    SUB R6 R6 R4        ; adjust by offset
    STW R5 R6 0         ; store counter value

    ADD R4 R4 4
    SUB R3 R3 1
    CMP R3 ZERO
    BNE loop

    DEBUG 3              ; inspect stack frame with filled locals

    ; Set return value before restoring caller state
    MOV R1 R2

    ; Epilogue: deallocate and restore
    MOV R3 R2
    SHL R3 R3 2         ; recalculate bytes to deallocate
    ADD SP SP R3        ; deallocate local array
    RETURN R2
