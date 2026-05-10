USER_START:

    MOV R1 0x8000     ; word array base pointer
    MOV R2 5          ; word count

    BL fill_array

    ; exercise byte/halfword loads and stores
    MOV R6 0x8100
    MOV R7 0x00AB
    STB R7 R6 0
    MOV R7 0xCDEF
    STH R7 R6 2
    LDB R8 R6 0
    LDH R9 R6 2
    LDW R10 R1 0

    SVC 1
    HLT


fill_array:

    ; R2 = counter
    ; R1 = base
    ; R0 = hardwired zero

    MOV R12 400       ; 100 words
    SUB SP SP R12

    MOV R3 R2         ; counter
    MOV R4 0          ; byte offset

loop:

    ; value = counter
    MOV R5 R3

    STW R5 R1 R4

    ADD R4 R4 4
    SUB R3 R3 1

    CMP R3 R0
    BNE loop

    ADD SP SP R12
    RET
