# SO
MIMUW University Assignments - Operating Systems (MINIX + assembly)

Lab part of the course consits of 6 problems - 2 programs in NASM and 4 tasks in MINIX 3 consisting of modyfing various parts of drivers, servers and kernel.

**Task 1**
Program in NASM that reads UTF-8 encoded string from stdin, transforms every Unicode code point p into code point (W(p - 0x80) + 0x80) modulo 0x10FF80 and outputs results to stdout, also in UTF-8.

W(x) = a_n * x^n + ... + a_1 * x + a_0

The coefficients are given as program parameters.

**Task 2**

Program in NASM that allows running n concurrent instances of _uint64_t notec(uint32_t n, char const *calc);_:
- performing various arithmetic operations on the element of the stack
- calling external function _int64_t debug(uint32_t n, uint64_t *stack_pointer);_ while satisfying System V x86 ABI
- exchaning stack elements between concurrently running instances using spin lock and atomicity of mov on aligned addresses.
