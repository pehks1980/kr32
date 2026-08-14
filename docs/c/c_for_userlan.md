c compiler for userland programs
+ for porting c programs from unix / linux / bsd utilities - ie pre brew system for kr32 

 # KR32 Userland C Compiler and Portability Guidelines

## 1. Purpose

The KR32 C compiler exists to provide a practical path for building native userland programs and porting existing Unix/Linux/BSD utilities to KR32.

The long-term goal is to create a small, self-hosted-style userland ecosystem where programs can be obtained, adapted, compiled, and installed without requiring the original operating system.

Conceptually:

```text
Unix / Linux / BSD source
        |
        v
   portable C code
        |
        v
 KR32 libc / headers
        |
        v
 KR32 C compiler
        |
        v
 KR32 executable
        |
        v
      TARFS
```

The compiler is therefore not only a programming-language tool. It is the foundation for a future KR32 package/utility ecosystem.

---

## 2. Primary Goal

The primary goal is:

> Make existing small Unix utilities portable to KR32 with the minimum possible modification to their source code.

Prefer adapting the **environment around the program** rather than rewriting the program itself.

For example, if a program expects:

```c
open()
read()
write()
close()
fork()
execve()
waitpid()
```

the preferred solution is to provide those interfaces through KR32 libc and syscalls.

Do not rewrite the application merely because KR32 implements the underlying mechanism differently.

---

## 3. Unix Compatibility First

KR32 userland should follow established Unix conventions whenever they are simple and useful.

Prefer existing concepts such as:

* file descriptors
* stdin/stdout/stderr
* `open()`
* `read()`
* `write()`
* `close()`
* `fork()`
* `execve()`
* `waitpid()`
* pipes
* command-line arguments
* environment variables
* exit status
* pathname semantics

This gives KR32 access to a large body of existing software.

However:

> Compatibility is a tool, not a restriction.

KR32 may introduce new interfaces where they provide a clear architectural advantage.

---

## 4. libc Is the Portability Boundary

User programs should normally interact with the kernel through libc rather than directly issuing syscalls.

Preferred:

```c
printf("hello\n");

fd = open("file", ...);

read(fd, buf, size);

write(fd, buf, size);
```

rather than embedding KR32 syscall details into applications.

KR32-specific syscall numbers and ABI details belong primarily inside:

```text
libc
```

This keeps applications portable.

---

## 5. Keep libc Small

The initial libc should contain only functionality that is actually required by userland.

Initial priorities:

```text
string functions
memory functions
stdio-like functions
process functions
file functions
sleep/time functions
```

Examples:

```text
puts()
printf()
strlen()
strcmp()
strcpy()
memcpy()
memset()

malloc()
free()

exit()
fork()
execve()
waitpid()
sleep()

open()
close()
read()
write()
```

Additional functionality should be added when a real application requires it.

Avoid implementing a large POSIX library before there is a userland need for it.

---

## 6. Prefer Simple Implementations

KR32 is intentionally transparent.

A libc implementation should therefore prefer:

```text
small
predictable
readable
debuggable
```

over:

```text
highly optimized
generic
abstract
complex
```

The first implementation should be easy to inspect in assembly and easy to debug in the VM.

Optimization comes after correctness.

---

## 7. Native KR32 ABI Must Remain Explicit

The compiler must have a clearly documented KR32 ABI.

The ABI should define:

* register usage
* argument passing
* return values
* stack layout
* stack alignment
* caller/callee-saved registers
* integer sizes
* pointer size
* structure layout
* syscall convention
* process entry convention

The compiler, assembler, libc, kernel and user programs must all follow the same ABI.

The ABI is a contract.

Changes to it should be treated as architectural changes rather than casual implementation changes.

---

## 8. C Runtime Startup

A compiled program should not enter directly at `main()`.

The KR32 runtime should provide a small startup layer:

```text
_start
   |
   +-- obtain argc
   |
   +-- obtain argv
   |
   +-- initialize libc
   |
   +-- call main()
   |
   +-- exit(return_value)
```

This keeps the C program independent from the exact KR32 process startup mechanism.

---

## 9. Porting Strategy

When porting a Unix utility, use the following order:

### Step 1 — Compile unchanged source

Determine what the compiler and headers are missing.

### Step 2 — Provide missing libc functionality

If the program needs a normal Unix function, prefer adding it to KR32 libc.

### Step 3 — Provide missing headers

Add the minimum required definitions.

### Step 4 — Adapt OS-specific code

Only modify source where the program depends on an operating-system-specific feature that KR32 intentionally does not provide.

### Step 5 — Keep modifications isolated

Prefer:

```text
compat/
kr32/
```

wrappers or small compatibility modules over scattering:

```c
#ifdef KR32
...
#endif
```

throughout the application.

---

## 10. Portability Layers

A ported program should ideally have this structure:

```text
application
     |
     v
portable C
     |
     +----------------+
     |                |
     v                v
 Unix libc         KR32 libc
                      |
                      v
                  KR32 kernel
```

The application should contain as little KR32-specific code as possible.

---

## 11. KR32 Compatibility Headers

Where necessary, provide compatibility headers such as:

```text
include/
    stdio.h
    string.h
    stdlib.h
    unistd.h
    fcntl.h
    sys/
        types.h
        stat.h
        wait.h
```

The initial headers should expose only functionality actually implemented by KR32.

Do not create declarations for functionality that does not exist merely to make compilation succeed.

A successful compile must mean that the corresponding runtime behavior exists.

---

## 12. No Fake APIs

Do not provide a function merely because another Unix system has it.

For example, do not implement:

```c
foo()
```

as an empty function simply to satisfy the linker.

If a feature is unsupported, the preferred behavior is:

```text
compile-time error
```

or an explicit runtime error.

Silent fake behavior is dangerous in an operating system.

---

## 13. Command-Line Compatibility

KR32 utilities should follow normal Unix command-line conventions where practical.

For example:

```text
utility [options] [arguments]
```

Programs should receive:

```c
int main(int argc, char **argv)
```

and should use standard exit status conventions.

This makes existing utilities easier to port and makes the KR32 shell familiar.

---

## 14. File Descriptor Model

Userland should treat files, terminals and pipes through the same file-descriptor interface whenever possible.

For example:

```text
cat file
```

and:

```text
cat file | grep hello
```

should not require different application logic.

`cat` should primarily perform:

```text
read()
    |
    v
write()
```

The shell and kernel arrange where those descriptors point.

This preserves one of the fundamental Unix design principles:

> Programs operate on interfaces; the kernel determines what lies behind those interfaces.

---

## 15. Porting Priority

Initial porting should favor small utilities that exercise fundamental kernel interfaces.

Recommended order:

```text
echo
cat
ls
pwd
mkdir
rm
cp
mv
sleep
date
true
false
wc
head
tail
grep
```

These utilities progressively exercise:

```text
argv
filesystem
directories
file descriptors
processes
pipes
memory
time
```

Larger applications should come later.

---

## 16. Build System Philosophy

KR32 should eventually provide a simple build/install workflow.

Conceptually:

```text
krcc source.c -o program
```

and eventually:

```text
krpkg build package
krpkg install package
```

The package system should produce a KR32-native executable and install it into the filesystem image.

The long-term goal is a "pre-Brew" style ecosystem:

```text
source
   |
   v
configure/adapt
   |
   v
compile
   |
   v
package
   |
   v
install into KR32
```

The system should remain substantially simpler than modern desktop package ecosystems.

---

## 17. Cross Compilation First

The first C compiler implementation is expected to run on the development host and produce KR32 binaries.

```text
Host machine
     |
     | krcc
     v
KR32 executable
```

A native KR32 compiler can be considered later.

Do not make self-hosting a prerequisite for useful C userland.

---

## 18. Compiler Independence

The kernel must not depend on the C compiler.

The architectural dependency is:

```text
KR32 ABI
   ^
   |
   +-- assembler
   |
   +-- C compiler
   |
   +-- libc
   |
   +-- user programs
```

The kernel defines the execution environment.

The compiler targets that environment.

This allows the compiler to be replaced or improved without redesigning the kernel.

---

## 19. Assembly Remains the Reference

Assembly is the final authority for the KR32 machine.

The compiler must ultimately produce code compatible with the documented KR32 ISA and ABI.

When investigating compiler problems, the generated assembly should be inspectable.

Recommended development workflow:

```text
C source
   |
   v
compiler
   |
   v
assembly
   |
   v
assembler
   |
   v
KR32 executable
```

The intermediate assembly should remain available for debugging.

---

## 20. Debuggability Is a Requirement

A compiled KR32 program must remain observable.

The development environment should allow inspection of:

```text
generated assembly
registers
stack
memory
syscalls
page mappings
executable image
```

Compiler optimization must not make the system impossible to understand.

During early development:

```text
-O0
```

or equivalent should be the normal debugging mode.

Optimization can be introduced progressively.

---

## 21. No Hidden Runtime

The initial KR32 C environment should avoid depending on a large hidden runtime.

Every important operation should eventually reduce to a known KR32 mechanism:

```text
C
 ↓
libc
 ↓
syscall
 ↓
kernel
 ↓
VFS/device
```

This is part of the KR32 "X-ray" principle.

A programmer should be able to follow a C operation all the way down to the machine.

---

## 22. Portability vs KR32 Innovation

KR32 should distinguish between:

### Portable interface

Established Unix/C behavior that makes software portable.

### KR32-specific implementation

The internal mechanism used to implement that behavior.

For example:

```text
C program
   |
   | open()
   v
KR32 libc
   |
   | syscall
   v
VFS
   |
   +-- TARFS
   |
   +-- NSFS
```

A program should not need to know whether its file came from TARFS or NSFS.

This allows KR32 to innovate internally while preserving a familiar userland interface.

---

## 23. Rule: Port, Don't Rewrite

When an existing Unix utility can be adapted through:

```text
libc
headers
small compatibility layer
```

prefer that approach over rewriting the application.

Rewrite only when:

* the original implementation is unsuitable,
* the dependency is excessively complex,
* or a simpler KR32-native implementation is clearly preferable.

The purpose of the compiler is to open the door to existing software, not to create another requirement to rewrite everything.

---

## 24. Long-Term Architecture

The intended KR32 software stack is:

```text
                    Applications
                         |
              +----------+----------+
              |                     |
        KR32-native             Ported Unix
          programs               programs
              |                     |
              +----------+----------+
                         |
                        libc
                         |
                      Syscalls
                         |
                       Kernel
                         |
            +------------+------------+
            |            |            |
           VFS         Process      Devices
            |
       +----+----+
       |         |
     TARFS      NSFS
```

The compiler sits beside this architecture as the tool that turns portable C source into native KR32 programs.

---

## 25. Guiding Principle

KR32 userland should follow one central rule:

> **Make the machine understandable, make the Unix interface familiar, and make porting existing software easier than rewriting it.**

The compiler, libc and package tools should progressively turn KR32 from an operating-system project into a usable operating environment.
