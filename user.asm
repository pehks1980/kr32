USER_START:

    MOV R1 0x8000     ; base pointer
    MOV R2 5          ; size

    MOV R0 0          ; IMPORTANT: define zero register

    BL fill_array

    SVC 1
    HLT


fill_array:

    ; R2 = counter (100)
    ; R1 = base
    ; R0 = 0 constant

    SUB R13 R13 100   ; stack frame (logical only)

    MOV R3 R2         ; counter
    MOV R4 0          ; offset

loop:

    ; value = counter
    MOV R5 R3

    STR R5 R1 R4

    ADD R4 R4 1
    SUB R3 R3 1

    CMP R3 R0
    BNE loop

    ADD R13 R13 100
    RET