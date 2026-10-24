# WasmBuilder.jl design

WasmBuilder is to WebAssembly what LLVM.jl is to LLVM IR: a Julia library for building
modules, used by code generators (WasmCodegen.jl is the first). It covers the parts of
WebAssembly that a GC-language compiler targets: the GC proposal (structs, arrays,
subtyping, casts, i31), typed function references, multi-value, exception handling (the
`exnref` version: `try_table`, `throw`, `throw_ref`), linear memory, active and passive
data segments, fixed-width SIMD128 and opt-in relaxed SIMD.

It does not depend on an external toolchain to produce modules. External tools are
optional: `wasm-tools` for an independent validation (`validate`) and disassembly, and
Binaryen's `wasm-opt` for optimization (a code generator's choice).

## Objects

| Object | Role |
|---|---|
| `WModule` | the module under construction: types, functions, globals, tags, memory, data, exports, start |
| `SubType`, `FuncType`, `StructType`, `ArrayType`, `FieldType` | type definitions |
| `NumType`, `RefType`, `PackedType`, `TypeRef` | value, reference, packed storage types; a defined type by index |
| `Func`, `Global`, `Tag`, `WMemory`, `DataSegment` | module items; function indices are assigned when written |
| `Inst` | an instruction: name (text format with `_`) and immediates (items, not indices) |
| `Builder` | appends validated instructions to a function body |

### Types: one recursion group

All type definitions of a module are in a single recursion group. Under the iso-recursive
type equivalence of the GC proposal, two definitions in the same group at different
positions are distinct types even if structurally equal. That makes the module's types
nominal, which a code generator needs to distinguish source types by `ref.test`/`ref.cast`
(two Julia structs with the same field types must not be the same Wasm type). dart2wasm
does the same. The cost is that types cannot be deduplicated against other modules, which
does not matter for a whole-program compiler. Function types are deduplicated within the
module (`functype!`).

A subtype's supertype must have a smaller index; types are numbered in creation order, so
a code generator creates a supertype before its subtypes.

### Items and indices

Instructions refer to functions, globals and tags by the objects themselves, not by
index. Function indices are assigned when the module is written (imports first, as the
index space requires), so imports can be added at any time during code generation,
including after calls to other functions were emitted. This avoids a relocation pass.
`add_import!` deduplicates by name and signature: the same name imported at another
signature is another import (a JavaScript function can be imported at several types).

## The builder

`Builder(m, f)` validates each instruction as it is appended, with the validation
algorithm of the specification's appendix: an operand stack of value types (with an
unknown bottom type in unreachable code) and a stack of control frames (`block`, `loop`,
`if`/`else`, `try_table`, the function). Each instruction pops its operand types
(checking subtyping in the module) and pushes its result types; control instructions
check their label types and arities. Non-defaultable locals (non-nullable references) must
be set before they are read, with the spec's definite-initialization rule (a `local.set`
counts until the end of its block). `end!` ends blocks; `finish!` ends the function.

Errors are `WasmValidationError`s naming the function, the position of the instruction,
the instruction and the operand stack: the code generator gets the error where it emits
the wrong instruction, with its own backtrace, instead of a byte offset from an engine.

Validation can be switched off (`WasmBuilder.VALIDATE[] = false`) for speed once a
generator is trusted; the operand stack is still tracked.

One table (`INSTRUCTIONS`, populated by `instructions.jl` and `memory_simd.jl`) gives
each instruction its opcode, immediate kinds, text name and, when its type is fixed,
its signature: it drives encoding, printing and validation. Numeric signatures come from the names
(`i64_trunc_sat_f64_s`: `f64 → i64`); the other instructions have explicit rules.

What the builder cannot check instruction by instruction is checked by `verify(m)`: type
definitions (supertypes defined earlier, not final, and matching), global initializers
(constant expressions of the global's type, reading earlier immutable globals), tags,
unique export names and the type of the start function. It also validates memory limits,
active data offsets, memory availability, instruction immediates and memory/SIMD
feature flags in function bodies, including bodies assembled directly from `Inst`s. Operand/control
stack validation remains the builder's responsibility. `to_bytes` calls `verify`.

Not covered yet: tables and `call_indirect`, multi-memory, memory64, shared memory and
atomics, element segments beyond the declarative one that `ref.func` needs (`declare!` adds functions to it).

### Linear memory and vector instructions

`m.memory` is either absent or one `WMemory`, defined or imported, with limits in 64 KiB
pages (`0 ≤ min ≤ max ≤ 65536`). The memory index is always zero; addresses and lengths
are `i32`. A second memory is rejected. Memory imports share the import section with
function and global imports; only defined memory appears in the memory section.

`add_data!(m, bytes)` adds a passive `DataSegment`. Its `offset` keyword makes the
segment active in memory zero, taking an integer or an `i32` constant expression.
Offsets can read immutable globals, including imports added with
`add_import!(m, "env", "offset", I32)`. Global imports precede definitions in the
global index space; adding an import updates the indices of existing globals.
Segment indices remain stable across active and passive segments. The data-count
section precedes code, and the data section follows it. Both GC array data instructions
and bulk memory instructions refer to these indices.

Memory instructions take `MemArg(alignment_exponent, byte_offset)` memargs. `OpInfo` holds
the maximum alignment exponent and lane count for each applicable instruction, so
validation uses the access width, including splat, extending and lane loads. Shuffle
masks are vectors of 16 integer selectors in `0:31`. Vector constants accept a
`UInt128` or a vector of 16 integer bytes in `-128:255`; both vectors exclude `Bool`.
The dedicated memarg type and vector payloads each occupy one `Inst` immediate.
Vector constants contain exactly 128 bits and are encoded in little-endian byte order. The `0xfd` opcode suffix uses unsigned LEB128,
including opcodes above `0x7f` and relaxed opcodes `0x100:0x113`.

`WModule(relaxed_simd=true)` enables all 20 relaxed instructions; the default is false.
The flag belongs to the module so code generators can target engines independently.
The fixed SIMD table and signatures follow the
[SIMD binary specification](https://github.com/WebAssembly/simd/blob/main/proposals/simd/BinarySIMD.md);
relaxed operations follow the
[relaxed SIMD proposal](https://github.com/WebAssembly/relaxed-simd/blob/main/proposals/relaxed-simd/Overview.md).

## Output

- `to_bytes(m; verify=true)`: the binary format, after `verify(m)`; a `name` section
  names the functions.
- `print_wat(io, m)`: the text format, approximately, for reading.
- `validate(bytes)`: `wasm-tools validate --features=all`, when available.
- `disassemble(bytes)`: `wasm-tools print`.

## Planned

- Reading binary modules (to link a code generator's output with hand-written modules).
- An optimization entry point running `wasm-opt` (Binaryen_jll) with GC-aware passes.
- A WAT parser for tests.
