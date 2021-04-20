NULL equ 0 ; Character ending ASCIIZ string.
INPUT_ON equ 1 ; Signifies that input mode for hex digits is on.
MIN_DIGIT equ 48 ; ASCII code of '0'.
MAX_DIGIT equ 57 ; ASCII code of '9'.
MIN_BIG_LETTER equ 65 ; ASCII code of 'A'.
MAX_BIG_LETTER equ 70 ; ASCII code of 'F'.
MIN_SMALL_LETTER equ 97 ; ASCII code of 'a'.
MAX_SMALL_LETTER equ 102 ; ASCII code of 'f'.

EQUAL_SIGN equ 61
PLUS_SIGN equ 43
TIMES_SIGN equ 42
MINUS_SIGN equ 45
AND_SIGN equ 38
OR_SIGN equ 124
XOR_SIGN equ 94
TILDE_SIGN equ 126
Z_SIGN equ 90
Y_SIGN equ 89
X_SIGN equ 88
N_SIGN equ 78
SMALL_N_SIGN equ 110
SMALL_G_SIGN equ 103
W_SIGN equ 87

NUMBER_STACK_OFFSET equ 32 ; Offset to number stack.
HEX_DIGIT_BINARY_SHIFT equ 4
STACK_ELEMENT_SIZE equ 8
STACK_ALIGNMENT_MASK equ -16 ; Mask to cancel 4 least significant bits.

; ------------------------------ BSS SECTION ------------------------------
section .bss
align 8
; Variable swapWith[i] is the ID of the instance that
; i-th instance wants to swap top of the number stacks with.
swapWith resd N + 1
; Variable topOfStack[i] stores the value of the top of the number 
; stack of i-th instance for purposes of W operation.
topOfStack resq N + 1

; ------------------------------ TEXT SECTION ------------------------------
section .text

; C function prototype: int64_t debug(uint32_t n, uint64_t *stack_pointer);
extern debug

; C function prototype: uint64_t notec(uint32_t n, char const *calc);
global notec
notec:
    push rbp
    mov rbp, rsp

    push r12 ; Used to iterate over calc.
    push r13 ; Used to store information on whether instance is in input mode.
    push rbx ; For saving first argument.
    push r14 ; For saving rsp.

    mov r12, rsi ; Load character pointer into r12.
    xor r13d, r13d ; Set r13 to 0.
    mov rbx, rdi ; Save first argument.

iterateOverCalcBegin:
    movzx r10, byte [r12] ; Load character pointed by r12 to r10.

    cmp r10, MIN_DIGIT
    jb bigLeter

    cmp r10, MAX_DIGIT
    ja bigLeter

    sub r10, MIN_DIGIT

    jmp processHexDigit

bigLeter:
    cmp r10, MIN_BIG_LETTER
    jb smallLeter

    cmp r10, MAX_BIG_LETTER
    ja smallLeter

    sub r10, MIN_BIG_LETTER - 10 ; Subtracting 10, because A = 10, B = 11, ...

    jmp processHexDigit

smallLeter:
    cmp r10, MIN_SMALL_LETTER
    jb plusSign

    cmp r10, MAX_SMALL_LETTER
    ja plusSign

    sub r10, MIN_SMALL_LETTER - 10

processHexDigit:
    cmp r13, INPUT_ON
    je inputOn

    push r10

    mov r13, INPUT_ON
    jmp characterProcessed

inputOn:
    shl qword [rsp], HEX_DIGIT_BINARY_SHIFT
    add qword [rsp], r10

    jmp characterProcessed

plusSign:
    cmp r10, PLUS_SIGN
    jne timesSign

    pop r11
    add qword [rsp], r11

    jmp closeInputMode

timesSign:
    cmp r10, TIMES_SIGN
    jne minusSign

    pop rax

    mul qword [rsp]

    mov qword [rsp], rax

    jmp closeInputMode

minusSign:
    cmp r10, MINUS_SIGN
    jne andSign

    neg qword [rsp]

    jmp closeInputMode

andSign:
    cmp r10, AND_SIGN
    jne orSign

    pop r11
    and qword [rsp], r11

    jmp closeInputMode

orSign:
    cmp r10, OR_SIGN
    jne xorSign

    pop r11
    or qword [rsp], r11

    jmp closeInputMode

xorSign:
    cmp r10, XOR_SIGN
    jne tildeSign

    pop r11
    xor qword [rsp], r11

    jmp closeInputMode

tildeSign:
    cmp r10, TILDE_SIGN
    jne ZSign

    not qword [rsp]

    jmp closeInputMode

ZSign:
    cmp r10, Z_SIGN
    jne YSign

    add rsp, STACK_ELEMENT_SIZE

    jmp closeInputMode

YSign:
    cmp r10, Y_SIGN
    jne XSign

    mov r10, qword [rsp]

    push r10

    jmp closeInputMode

XSign:
    cmp r10, X_SIGN
    jne NSign

    mov r11, qword [rsp]
    mov r10, qword [rsp + STACK_ELEMENT_SIZE]

    mov qword [rsp], r10
    mov qword [rsp + STACK_ELEMENT_SIZE], r11

    jmp closeInputMode

NSign:
    cmp r10, N_SIGN
    jne nSign

    push N

    jmp closeInputMode

nSign:
    cmp r10, SMALL_N_SIGN
    jne gSign

    push rdi

    jmp closeInputMode

gSign:
    cmp r10, SMALL_G_SIGN
    jne WSign

    mov r14, rsp ; Save stack pointer in r14.
    mov rsi, rsp ; Second argument to debug is a pointer to the number stack.

    and rsp, STACK_ALIGNMENT_MASK ; Align stack to 16 bytes to meet ABI requirements.

    call debug

    mov rdi, rbx ; Restore n.

    mov rsp, r14 ; Restore stack pointer before alignment.
    lea rsp, [rsp + rax * 8] ; Move stack pointer by rax positions.

    jmp closeInputMode

WSign:
    cmp r10, W_SIGN
    jne closeInputMode

    lea r8, [rel swapWith] ; Relative address of swapWith.
    lea r9, [rel topOfStack] ; Relative address of topOfStack.

    ; r11 - my ID.
    ; r10 - the other ID.
    ; Both values get incremented, because BSS arrays are
    ; initially filled with zeroes, but IDs also start from 0.

    pop r10
    inc r10

    mov r11, rdi
    inc r11

    cmp r10, r11
    je closeInputMode

    ; Place the top of my number stack in the array.
    pop qword [r9 + r11 * 8]
    
    ; Notify the other instance that I want to swap with it.
    mov dword [r8 + r11 * 4], r10d

waitForMatch:
    ; Wait for reply from the other instance.
    cmp dword [r8 + r10 * 4], r11d
    jne waitForMatch

matchedWaiters:
    ; Take the value from the other instance.
    push qword [r9 + r10 * 8]

    ; Notify the other instance that I have read their value.
    mov dword [r8 + r10 * 4], r10d

synchronize:
    ; Wait for the other instance to confirm that they have read
    ; my value, so I can contnue without worrying about the possibility
    ; that the top of my number stack will change.
    cmp dword [r8 + r11 * 4], r11d
    jne synchronize

closeInputMode:
    xor r13d, r13d

characterProcessed:
    inc r12
    cmp byte [r12], NULL ; While next character is not NULL.
    je iterateOverCalcEnd

    jmp iterateOverCalcBegin

iterateOverCalcEnd:
    mov rax, qword [rsp] ; Return value is the top of the number stack.

    sub rbp, NUMBER_STACK_OFFSET
    mov rsp, rbp ; Clearing number stack.

    pop r14
    pop rbx
    pop r13
    pop r12
    pop rbp
    ret
