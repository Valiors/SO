; ------------------------ CONSTANTS ------------------------
NULL equ 0 ; End of string.
EXIT_SUCCESS equ 0
EXIT_ERROR equ 1
STDIN equ 0
STDOUT equ 1
SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60
MIN_DIGIT_CODE equ 48 ; Code of 0 digit in Unicode.
MAX_DIGIT_CODE equ 57 ; Code of 9 digit in Unicode.
BUFFER_SIZE equ 4096
MINUS_CODE equ 45 ; Minus sign code.
ARGV_OFFSET equ 8
POLYNOMIAL_ARG_OFFSET equ 0x80
FOURTH_BRACKET equ 3
UTF_NEXT_BYTE_PATTERN equ 10b ; Bit pattern of bytes 2, 3, 4 of UTF-8 encoding.
UTF_NEXT_BYTE_UNICODE_BITS_COUNT equ 6 ; How many bits of 2nd, 3rd, 4th byte of UTF-8 brackets comprise a code point.
UTF_NEXT_BYTE_UNICODE_BIT_PATTERN equ 0x3F
NEXT_OUTPUT_BYTE equ 0x80
SHIFT_OUT equ 6

; ------------------------ READ-ONLY DATA SECTION ------------------------
section .rodata
COEFFICIENT_BASE dq 10
MOD dq 0x10FF80
NEXT_BYTES_COUNT_IN_BRACKET dq 0, 1, 2, 3 ; How many bytes to read, except for the first one, for 1/2/3/4 UTF-8 bracket.
UTF_BRACKET_PATTERN dq 0, 110b, 1110b, 11110b ; Bit patterns for recognizing UTF-8 brackets.
UTF_BRACKET_UNICODE_BITS_COUNT db 7, 5, 4, 3 ; How many bits of first byte of UTF-8 brackets comprise a code point.
UTF_BRACKET_UNICODE_BIT_PATTERN dq 0x7F, 0x1F, 0xF, 0x7
UTF_BRACKET_MIN dq 0, 0x007F + 1, 0x07FF + 1, 0xFFFF + 1
UTF_BRACKET_MAX dq 0x007F, 0x07FF, 0xFFFF, 0x10FFFF
FIRST_OUTPUT_BYTE dq 0, 0xC0, 0xE0, 0xF0
SHIFT_OF_FIRST_OUTPUT_BYTE db 0, 6, 12, 18


; ------------------------ BSS SECTION -------------------------
section .bss
inputBuffer resb BUFFER_SIZE ; Input buffer.
outputBuffer resb BUFFER_SIZE ; Output buffer.

; ------------------------ TEXT SECTION ------------------------
section .text
global _start
_start:
    mov rbp, rsp

    ; Our polynomial is a_n * x^n + ... + a_1 * x + a_0.
    ; Command line arguments are arranged in a stack, like
    ; argv[n + 1]
    ; argv[n]
    ; ...
    ; argv[1]
    ; argv[0]
    ; argc
    ; Where argc is n + 2, argv[0] is program name,
    ; argv[i] is an address of a string representing a_{i-1}.
    ; The following code transforms argc into n+1 and
    ; argv[i] into a_{i-1} modulo MOD.

    ; Load polynomial size (n + 1) into r10.
    dec qword [rbp] ; Exclude program name from argc.
    mov r10, qword [rbp]

    ; If polynomial has no coefficients, exit program, otherwise start looping.
    cmp r10, 0
    jne loopBegin

    jmp unsuccessfulProgramExit

    ; Iterate over argv[n + 1], ... argv[1].
loopBegin:
    cmp r10, 0
    je loopEnd

    ; Load argv[r10] into r11.
    mov r11, qword [rbp + r10 * 8 + ARGV_OFFSET]

    ; RAX will store the calculated coefficient value.
    mov rax, 0

    ; Let r8 = 0, if coefficient is nonnegative, MOD otherwise.
    mov r8, 0

    ; Length of the coefficient.
    mov r14, 0

    ; Check for minus sign.
    movzx rsi, byte [r11]
    cmp rsi, MINUS_CODE
    jne digitLoopBegin

    ; Coefficient is negative, so set r8 to MOD and advance r11.
    mov r8, [MOD]
    inc r11

    ; While the next character is not NULL.
digitLoopBegin:
    ; Load next byte into rsi.
    movzx rsi, byte [r11]
    cmp rsi, NULL
    je digitLoopEnd

    ; If x < '0' or x > '9' then the input is in error.
    cmp rsi, MIN_DIGIT_CODE
    jb unsuccessfulProgramExit

    cmp rsi, MAX_DIGIT_CODE
    ja unsuccessfulProgramExit

    sub rsi, MIN_DIGIT_CODE

    inc r14

digitInRange:
    ; Update RAX with Horner's method ((rax * 10 + rsi) % MOD).
    mul qword [COEFFICIENT_BASE]
    add rax, rsi
    mov rdx, 0
    div qword [MOD]
    mov rax, rdx

    inc r11
    jmp digitLoopBegin

digitLoopEnd:
    ; Coefficient with 0 digits is an error.
    cmp r14, 0
    je unsuccessfulProgramExit

    cmp r8, 0
    je nonnegative

    ; Change rax into MOD - rax.
    sub r8, rax
    mov rax, r8
    
nonnegative:
    ; Change argv[i] into a_{i - 1} % MOD.
    mov qword [rbp + r10 * 8 + ARGV_OFFSET], rax

    dec r10
    jmp loopBegin

loopEnd:
    ; At this point, our polynomial data is ready.
    ; Now let's move on to reading text from STDIN.
    ; We will use a buffer in order to use less syscalls.
    
    mov r8, 0
    mov r9, 0
    mov r10, 0
    mov r11, 0
    mov r12, 0
    mov r13, 0
    mov r14, 0
    mov rbx, 0

; r8 - no. of bytes read by current read syscall.
; r9 - UTF-8 "bracket" (there are 4 brackets with different encoding lengths).
; r10 - no. of bytes that have to be read yet for current Unicode code point.
; r11, r12 - auxiliary.
; r13 - calculated Unicode code point.
; r14, r15 - auxiliary.
; rbx - no. of bytes written to output buffer.

readingLoopBegin:    
    ; Call read(STDIN, buffer, BUFFER_SIZE).
    mov rax, SYS_READ
    mov rdi, STDIN
    mov rsi, inputBuffer
    mov rdx, BUFFER_SIZE
    syscall

    ; If read returned < 0, then input is in error.
    cmp rax, 0
    jl unsuccessfulProgramExit

    ; If read returned 0 (no bytes read), then reading is finished.
    cmp rax, 0
    je readingLoopEnd

    ; If read returned > 0, then store number of bytes read in r8.
    mov r8, rax
    mov r15, 0

byteItrationLoopBegin:
    cmp r8, 0
    je byteIterationLoopEnd

    ; Read byte.
    movzx r11, byte [inputBuffer + r15]

    ; If the current UTF-8 character still requires next bytes, process next.
    cmp r10, 0
    jne processNonFirstByte

    mov r14, 0

; We find the kind of UTF-8 bracket based on the byte.
assignBracket:
    mov r12, r11
    mov cl, [UTF_BRACKET_UNICODE_BITS_COUNT + r14]
    shr r12, cl
    cmp r12, [UTF_BRACKET_PATTERN + r14 * 8]
    je foundBracket

    inc r14
    cmp r14, FOURTH_BRACKET
    jbe assignBracket

    jmp unsuccessfulProgramExit

foundBracket:
    mov r9, r14
    mov r10, [NEXT_BYTES_COUNT_IN_BRACKET + r14 * 8]

    and r11, [UTF_BRACKET_UNICODE_BIT_PATTERN + r14 * 8]
    mov r13, r11

    jmp unicodeReadyForProcessing

processNonFirstByte:
    ; Verify that the byte is 10xxxxxx.
    mov r12, r11
    mov cl, UTF_NEXT_BYTE_UNICODE_BITS_COUNT
    shr r12, cl
    cmp r12, UTF_NEXT_BYTE_PATTERN
    jne unsuccessfulProgramExit

    ; Update r13.
    shl r13, UTF_NEXT_BYTE_UNICODE_BITS_COUNT
    and r11, UTF_NEXT_BYTE_UNICODE_BIT_PATTERN
    add r13, r11

    dec r10

unicodeReadyForProcessing:
    cmp r10, 0
    je unicodeShortestLengthEvaluation

byteFinished:
    dec r8
    inc r15
    jmp byteItrationLoopBegin

byteIterationLoopEnd:
    jmp readingLoopBegin

readingLoopEnd:
    cmp r10, 0
    jne unsuccessfulProgramExit

    jmp successfulProgramExit

unicodeShortestLengthEvaluation:
    ; Code point was encoded in the shortest possible way
    ; if its encoding falls into its bracket.
    cmp r13, qword [UTF_BRACKET_MIN + r9 * 8]
    jb unsuccessfulProgramExit

    cmp r13, qword [UTF_BRACKET_MAX + r9 * 8]
    ja unsuccessfulProgramExit

unicodePolynomialEvaluation:
    mov r11, r13
    sub r11, POLYNOMIAL_ARG_OFFSET
    cmp r11, 0
    jl outputPhase

    ; r13 = r13 - 0x80.
    mov r13, r11

    ; r13 = r13 % 0x80.
    mov rax, r13
    mov rdx, 0
    mov r11, [MOD]
    div r11
    mov r13, rdx
    
    mov rax, 0

    mov r12, [rbp]

evaluationLoopBegin:
    cmp r12, 0
    je evaluationLoopEnd

    mul r13
    add rax, qword [rbp + r12 * 8 + ARGV_OFFSET]
    div r11
    mov rax, rdx

    dec r12
    jmp evaluationLoopBegin

evaluationLoopEnd:
    add rax, POLYNOMIAL_ARG_OFFSET
    mov rdx, 0
    div r11
    mov rax, rdx

    mov r13, rax

; At this point, we have to transform Unicode code point into
; UTF-8 and push the result to the output buffer (flushing it, if necessary).
outputPhase:
    push r9
    push r10

    mov r14, 0

findOutputBracket:
    cmp r13, [UTF_BRACKET_MAX + r14 * 8]
    jbe foundOutputBracket

    inc r14
    jmp findOutputBracket

foundOutputBracket:
    mov r9, r14
    mov r10, r14

    mov r11, rbx
    add r11, r14
    cmp r11, BUFFER_SIZE
    jb bufferIsNowFixed

    call flushBuffer

bufferIsNowFixed:
    mov r11, [FIRST_OUTPUT_BYTE + r14 * 8]
    
    mov r12, r13
    mov cl, [SHIFT_OF_FIRST_OUTPUT_BYTE + r14]
    shr r12, cl

    add r11, r12

    mov [outputBuffer + rbx], r11b
    inc rbx

restOfOutputBytes:
    cmp r10, 0
    je outputingCodePointFinished
    
    mov r11, NEXT_OUTPUT_BYTE

    mov r12, r13
    and r12, UTF_NEXT_BYTE_UNICODE_BIT_PATTERN
    
    add r11, r12

    add rbx, r10
    mov [outputBuffer + rbx - 1], r11b
    sub rbx, r10

    shr r13, SHIFT_OUT

    dec r10
    jmp restOfOutputBytes

outputingCodePointFinished:
    add rbx, r9

    pop r10
    pop r9
    jmp byteFinished

successfulProgramExit:
    call flushBuffer
    mov rax, SYS_EXIT
    mov rdi, EXIT_SUCCESS
    syscall

unsuccessfulProgramExit:
    call flushBuffer
    mov rax, SYS_EXIT
    mov rdi, EXIT_ERROR
    syscall

; Flushes output buffer.
; Takes rbx - size (in bytes) of data in the buffer.
; Modifies rax, rdi, rsi, rdx, rbx.
global flushBuffer
flushBuffer:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, outputBuffer
    mov rdx, rbx
    syscall

    ; Reset buffer counter.
    mov rbx, 0
    ret
