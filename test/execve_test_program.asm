.ORG 0x43000

    ; Simple user program for execve test.
    ; It writes a message to stdout and then loops forever.

    LI R1 exec_msg
    LI R2 1
    LI R3 14
    SVC SYS_WRITE

exec_loop:
    SVC SYS_YIELD
    B exec_loop

exec_msg:
    .ASCIIZ "EXECVE OK!\n"
