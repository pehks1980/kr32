KR32 Manifest — principles I'd add

I'd keep it almost Lenin-like: short sentences, no marketing language, each sentence a rule.

KR32 Tovarishi! 

KR32 is a computer system built from first principles.

The machine comes first. The operating system follows the machine.

Assembly is the language of the machine and remains a first-class language of KR32.

Every abstraction must have a visible implementation.

Hide dependencies. Do not hide mechanisms.

If something cannot be inspected, it cannot be fully understood.

If something cannot be changed, it is not fully under our control.

Prefer simple mechanisms that compose over complex mechanisms that conceal.

Use Unix principles where they remain fundamental. Question implementations where history is no longer a constraint.

Do not reproduce historical complexity merely because it exists elsewhere.

An interface is a contract, not a prison.

Applications depend on stable interfaces; engineers remain free to change the implementation beneath them.

The kernel is a hub, not a universe.

Specialized functions belong in specialized components.

The kernel orchestrates; devices and cores perform.

Materialize complex internal representations into simple interfaces.

One operation should have one understandable path through the system.

Prefer deterministic behavior over hidden convenience.

Prefer observability over abstraction for abstraction's sake.

Debugging is a feature of the architecture, not an afterthought.

The VM is a development machine, not the final machine.

The FPGA is an implementation of the idea, not the definition of the idea.

Define the interface first. Implement it in software. Implement it in hardware when appropriate.

Hardware is replaceable. Software is replaceable. Interfaces are what we preserve.

A CPU core is not the whole computer. KR32 may orchestrate heterogeneous computational cores and devices.

New capabilities should be added by composition, not by destroying existing simplicity.

Port existing software where useful. Do not rewrite merely for ideological purity.

Build the smallest mechanism that proves the idea.

Measure before optimizing. Understand before optimizing.

Document significant decisions, not every keystroke.

Every important subsystem must be explainable from its interface down to its implementation.

KR32 is not designed to preserve the past. It is designed to understand it, use what remains good, and build what comes next.

final principle I think belongs specifically to project

The current kernel already has explicit machine-level contracts—calling convention, page permissions, virtual addresses, trap causes, syscall dispatch, etc.—rather than leaving those things to an external environment. The VM likewise exposes the CPU, memory and trap machinery instead of hiding it behind a host OS abstraction.

the more accurate principle is:

Idea → Specification → Code → VM → Hardware.

KR32 is engineer-first.

The machine should be understandable by the person building it, debugging it, porting it, modifying it, and eventually putting it into an FPGA.

That gives the whole thing a very clear identity:

simple principles, explicit mechanisms, replaceable implementations, no unnecessary historical baggage, and complete visibility from idea to machine.