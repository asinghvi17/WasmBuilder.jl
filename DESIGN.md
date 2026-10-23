# WasmBuilder.jl design

WasmBuilder is to WebAssembly what LLVM.jl is to LLVM IR: a Julia library for building
modules, used by code generators (WasmCodegen.jl is the first). It covers the parts of
WebAssembly that a GC-language compiler targets: the GC proposal (structs, arrays,
subtyping, casts, i31), typed function references, multi-value, exception handling (the
`exnref` version: `try_table`, `throw`, `throw_ref`), passive data segments.

It does not depend on an external toolchain to produce modules. External tools are
optional: `wasm-tools` for an independent validation (`validate`) and disassembly, and
Binaryen's `wasm-opt` for optimization (a code generator's choice).

## Objects

| Object | Role |
|---|---|
| `WModule` | the module under construction: types, functions, globals, tags, data, exports, start |
| `SubType`, `FuncType`, `StructType`, `ArrayType`, `FieldType` | type definitions |
| `NumType`, `RefType`, `PackedType`, `TypeRef` | value, reference, packed storage types; a defined type by index |
| `Func`, `Global`, `Tag` | module items; function indices are assigned when written |
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

## The builder

`Builder(m, f)` validates each instruction as it is appended, with the validation
algorithm of the specification's appendix: an operand stack of value types (with an
unknown bottom type in unreachable code) and a stack of control frames (`block`, `loop`,
`if`/`else`, `try_table`, the function). Each instruction pops its operand types
(checking subtyping in the module) and pushes its result types; control instructions
check their label types and arities.

Errors are `WasmValidationError`s naming the function, the position of the instruction,
the instruction and the operand stack: the code generator gets the error where it emits
the wrong instruction, with its own backtrace, instead of a byte offset from an engine.

Validation can be switched off (`WasmBuilder.VALIDATE[] = false`) for speed once a
generator is trusted; the operand stack is still tracked.

Numeric instructions are typed from their names (`i64_trunc_sat_f64_s`: `f64 → i64`);
the others have explicit rules.

Not covered yet: `br_on_cast`/`br_on_cast_fail` validation, tables and `call_indirect`,
linear memory, SIMD, `return_call_ref`, element segments beyond the declarative one that
`ref.func` needs (`declare!` adds functions to it), imported globals.

## Output

- `to_bytes(m)`: the binary format; a `name` section names the functions.
- `print_wat(io, m)`: the text format, approximately, for reading.
- `validate(bytes)`: `wasm-tools validate --features=all`, when available.
- `disassemble(bytes)`: `wasm-tools print`.

## Planned

- Reading binary modules (to link a code generator's output with hand-written modules).
- An optimization entry point running `wasm-opt` (Binaryen_jll) with GC-aware passes.
- A WAT parser for tests.
