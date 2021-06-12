# SO
MIMUW University Assignments - Operating Systems (MINIX + assembly)

Lab part of the course consits of 6 problems - 2 programs in NASM and 4 tasks in MINIX 3 consisting of modyfing various parts of drivers, servers and kernel.

**Task 1**

Wrtie a program in NASM that reads UTF-8 encoded string from stdin, transforms every Unicode code point p into code point (W(p - 0x80) + 0x80) modulo 0x10FF80 and outputs results to stdout, also in UTF-8.

W(x) = a_n * x^n + ... + a_1 * x + a_0

The coefficients are given as program parameters.

**Task 2**

Write a program in NASM that allows running n concurrent instances of _uint64_t notec(uint32_t n, char const *calc);_:
- performing various arithmetic operations on the element of the stack
- calling external function _int64_t debug(uint32_t n, uint64_t *stack_pointer);_ while satisfying System V x86 ABI
- exchaning stack elements between concurrently running instances using spin lock and atomicity of mov on aligned addresses.

**Task 3**

Add syscall _int negateexit(int negate)_ to MINIX's process manager (PM), such that, when called with _negate != 0_, will apply logical NOT to the calling process's exit code. If _negate == 0_, restore the original exit code. Forked processes inherit behavior of parent. Subsequent negateexit calls do not influence behavior of children. Processes terminated by signals should not have their exit codes changed.

**Task 4**

Modify MINIX kernel, sched server and add syscall _int setbid(int bid)_ to allow user programs to choose alternative scheduling algorithm called unique lowest bid. Every process can bid a postivie number. The one with the lowest unique bid is chosen to run. If there are no unique bids, any of the highest bidders is chosen. Processes scheduled with this algorithm have priority _AUCTION_Q = 8_. Calling _setbid(0)_ restores default scheduling behavior.

**Task 5**

Modify Minix File System (MFS) to generate errors in three ways:
A) Add 1 to every 3rd byte that is written to a file by MFS.
B) Let every 3rd _chmod_ syscall modify S_IWOTH bit of file permissions.
C) If there's a directory named _debug_ in the same directory as file being removed, move the file to debug instead of removing it.

**Task 6**

Write a device driver that imitates a simple queue.
