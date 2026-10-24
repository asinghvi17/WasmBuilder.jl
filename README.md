# WasmBuilder.jl

[![CI](https://github.com/gbaraldi/WasmBuilder.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/gbaraldi/WasmBuilder.jl/actions/workflows/CI.yml)

A Julia library for building WebAssembly modules, as LLVM.jl is for LLVM IR: types,
functions, globals and instructions as Julia objects, a builder that validates every
instruction as it is appended, and an encoder to the binary format. It covers what a
compiler for a garbage-collected language targets:

- the GC proposal: structs, arrays, subtyping, `ref.test`/`ref.cast`, `i31`;
- typed function references, multi-value;
- exception handling (the `exnref` version: `try_table`, `throw`, `throw_ref`);
- linear memory with imports/exports, active and passive data segments, scalar loads/stores
  and bulk memory operations (`memory.init`, `data.drop`, `memory.copy`, `memory.fill`);
- all 236 fixed-width SIMD128 instructions and all 20 relaxed SIMD instructions;
- GC data operations (`array.new_data`, `array.init_data`), start functions.

It has no dependencies and does not need an external toolchain. If `wasm-tools` is
installed, `validate` and `disassemble` use it for a second opinion. The first user is
[WasmCodegen.jl](https://github.com/gbaraldi/WasmCodegen.jl), a Julia-to-WasmGC compiler.

## Example

```julia
using WasmBuilder

m = WModule()
# a struct type: an immutable i32 tag and a mutable f64
point = add_type!(m, StructType([FieldType(I32, false), FieldType(F64, true)]))

# build a point, scale its field, read it back
f = add_func!(m, "scaled", ValType[F64, F64], ValType[F64])
p = add_local!(f, RefType(point))
b = Builder(m, f)               # validates every instruction as it is appended
emit!(b, :i32_const, 1)
emit!(b, :local_get, 0)
emit!(b, :struct_new, point)
emit!(b, :local_set, p)
emit!(b, :local_get, p)
emit!(b, :local_get, p); emit!(b, :struct_get, point, 1)
emit!(b, :local_get, 1); emit!(b, :f64_mul)
emit!(b, :struct_set, point, 1)
emit!(b, :local_get, p); emit!(b, :struct_get, point, 1)
finish!(b)
add_export!(m, "scaled", f)

bytes = to_bytes(m)             # verifies the module, then encodes it
print_wat(stdout, m)            # the text format
validate(bytes)                 # wasm-tools, if it is installed
```

A mistake is reported where the code generator makes it, with its backtrace, rather than
as a byte offset from an engine:

```julia
emit!(b, :f64_const, 1.0)
emit!(b, :i32_eqz)
# WasmValidationError in function bad at instruction 2 (i32_eqz): expected I32, got F64
```

## Linear memory and SIMD

```julia
m = WModule()                         # WModule(relaxed_simd=true) enables relaxed SIMD
mem = add_memory!(m, 1, 4)            # minimum and optional maximum, in 64 KiB pages
add_export!(m, "memory", mem)
add_data!(m, UInt8[1, 2, 3]; offset=0) # active segment; omit offset for a passive segment

f = add_func!(m, "scale_pair", ValType[I32, F64], ValType[])
b = Builder(m, f)
emit!(b, :local_get, 0)               # destination address
emit!(b, :local_get, 0)
emit!(b, :v128_load, (3, 0))          # (log2 alignment, byte offset)
emit!(b, :local_get, 1)
emit!(b, :f64x2_splat)
emit!(b, :f64x2_mul)
emit!(b, :v128_store, (3, 0))
finish!(b)
add_export!(m, "scale_pair", f)
bytes = to_bytes(m)
```

A module has at most one 32-bit, unshared memory. Import it with
`add_import!(m, "env", "memory", WasmBuilder.Memory(1, 4))` in place of `add_memory!`.
Memory indices are explicit zero immediates: `emit!(b, :memory_size, 0)`,
`emit!(b, :memory_copy, 0, 0)`, or `emit!(b, :memory_init, data_index, 0)`.
`add_data!` returns a zero-based index; `emit!(b, :data_drop, data_index)` drops it.
Active offsets can also be constant-expression `Vector{Inst}` values.

SIMD names use underscores in Julia (`:i16x8_extract_lane_s`) and the specification's
names in text (`i16x8.extract_lane_s`). Lane indices are zero-based. `v128.const` takes
a `UInt128` bit pattern (encoded little-endian) or 16 integer bytes; `i8x16.shuffle`
takes 16 integer lane selectors in `0:31`. A memarg's alignment exponent must be at most
the instruction's natural alignment, including narrow and lane loads/stores.
When constructing `Inst` directly, wrap tuple-valued immediates in the immediate list:
`Inst(:v128_load, ((3, 0),))`; `emit!` takes the memarg directly as above.

Relaxed SIMD is enabled per module with `WModule(relaxed_simd=true)`. Its instructions
may produce host-dependent results and require engine support. The builder and
`verify()` reject them when the flag is false. Fixed SIMD is always available and
can coexist with GC values, including `v128` struct fields and globals.

## Design

- **Nominal types.** All type definitions are in one recursion group, so two struct types
  with the same fields are distinct types, as a source language's types need to be.
- **Items, not indices.** Instructions refer to functions, globals and tags as objects.
  Indices are assigned when the module is written, so imports can be added at any point of
  code generation.
- **One instruction table** (`src/instructions.jl`) drives encoding, printing and
  validation.
- **Validation in two parts.** `Builder` checks each instruction against an operand stack
  and control frames, as the specification's validation algorithm does, including
  initialization of non-defaultable locals. `verify(m)` checks the rest: type definitions,
  constant expressions of globals and data offsets, memory limits, tags, exports, the
  start function. It also rechecks memory/SIMD immediates and feature requirements.

See [DESIGN.md](DESIGN.md) for details, and what is not covered yet (tables and
`call_indirect`, multi-memory, memory64, shared memory/atomics).

## Tests

`Pkg.test()` runs the modules it builds in Node.js 24 (from `NodeJS_24_jll`). It also
validates them with `wasm-tools` when it is on the `PATH`, in `~/.cargo/bin`, or named by
`WASM_TOOLS`.

The tests validate every memory/SIMD opcode in Node and exercise a linear-memory
`f64x2` kernel with GC arrays and structs. With `wasm-tools`, they also check binary/text
round trips. Set `WASMBUILDER_NODE` to use a local Node executable instead of the JLL.
