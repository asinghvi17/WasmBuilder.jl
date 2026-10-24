function read_uleb(io)
    value, shift = 0, 0
    while true
        byte = read(io, UInt8)
        value |= Int(byte & 0x7f) << shift
        byte < 0x80 && return value
        shift += 7
    end
end

function wasm_sections(bytes)
    io = IOBuffer(bytes)
    skip(io, 8)
    sections = Pair{UInt8,Vector{UInt8}}[]
    while !eof(io)
        id = read(io, UInt8)
        push!(sections, id => read(io, read_uleb(io)))
    end
    sections
end


encode_inst(op, imms...) = (io = IOBuffer(); W.write_inst(io, Inst(op, imms)); take!(io))

@testset "Memory and SIMD binary immediates" begin
    cases = [
        (:i32_load, (MemArg(2, 128),), [0x28, 0x02, 0x80, 0x01]),
        (:i64_load8_s, (MemArg(0, 3),), [0x30, 0x00, 0x03]),
        (:i64_load32_u, (MemArg(2, 0),), [0x35, 0x02, 0x00]),
        (:f32_store, (MemArg(2, 0),), [0x38, 0x02, 0x00]),
        (:i64_store16, (MemArg(1, 0),), [0x3d, 0x01, 0x00]),
        (:memory_size, (0,), [0x3f, 0x00]),
        (:memory_grow, (0,), [0x40, 0x00]),
        (:memory_init, (129, 0), [0xfc, 0x08, 0x81, 0x01, 0x00]),
        (:data_drop, (128,), [0xfc, 0x09, 0x80, 0x01]),
        (:memory_copy, (0, 0), [0xfc, 0x0a, 0x00, 0x00]),
        (:memory_fill, (0,), [0xfc, 0x0b, 0x00]),
        (:v128_load, (MemArg(4, 0),), [0xfd, 0x00, 0x04, 0x00]),
        (:v128_load16x4_s, (MemArg(3, 0),), [0xfd, 0x03, 0x03, 0x00]),
        (:v128_load8_splat, (MemArg(0, 0),), [0xfd, 0x07, 0x00, 0x00]),
        (:v128_store, (MemArg(4, 0),), [0xfd, 0x0b, 0x04, 0x00]),
        (:i8x16_swizzle, (), [0xfd, 0x0e]),
        (:i16x8_splat, (), [0xfd, 0x10]),
        (:i8x16_extract_lane_u, (15,), [0xfd, 0x16, 0x0f]),
        (:i16x8_replace_lane, (7,), [0xfd, 0x1a, 0x07]),
        (:f64x2_extract_lane, (1,), [0xfd, 0x21, 0x01]),
        (:i32x4_lt_u, (), [0xfd, 0x3a]),
        (:f64x2_ge, (), [0xfd, 0x4c]),
        (:v128_andnot, (), [0xfd, 0x4f]),
        (:v128_bitselect, (), [0xfd, 0x52]),
        (:v128_any_true, (), [0xfd, 0x53]),
        (:v128_load16_lane, (MemArg(1, 300), 7), [0xfd, 0x55, 0x01, 0xac, 0x02, 0x07]),
        (:v128_store64_lane, (MemArg(3, 0), 1), [0xfd, 0x5b, 0x03, 0x00, 0x01]),
        (:v128_load32_zero, (MemArg(2, 0),), [0xfd, 0x5c, 0x02, 0x00]),
        (:f32x4_demote_f64x2_zero, (), [0xfd, 0x5e]),
        (:i8x16_popcnt, (), [0xfd, 0x62]),
        (:i8x16_narrow_i16x8_s, (), [0xfd, 0x65]),
        (:f32x4_nearest, (), [0xfd, 0x6a]),
        (:i8x16_shr_u, (), [0xfd, 0x6d]),
        (:i8x16_add_sat_s, (), [0xfd, 0x6f]),
        (:i8x16_avgr_u, (), [0xfd, 0x7b]),
        (:i32x4_extadd_pairwise_i16x8_u, (), [0xfd, 0x7f]),
        (:i16x8_abs, (), [0xfd, 0x80, 0x01]),
        (:i16x8_q15mulr_sat_s, (), [0xfd, 0x82, 0x01]),
        (:i16x8_bitmask, (), [0xfd, 0x84, 0x01]),
        (:i16x8_extend_high_i8x16_u, (), [0xfd, 0x8a, 0x01]),
        (:f64x2_nearest, (), [0xfd, 0x94, 0x01]),
        (:i16x8_extmul_high_i8x16_u, (), [0xfd, 0x9f, 0x01]),
        (:i32x4_add, (), [0xfd, 0xae, 0x01]),
        (:i32x4_dot_i16x8_s, (), [0xfd, 0xba, 0x01]),
        (:i64x2_all_true, (), [0xfd, 0xc3, 0x01]),
        (:i64x2_lt_s, (), [0xfd, 0xd8, 0x01]),
        (:f32x4_sqrt, (), [0xfd, 0xe3, 0x01]),
        (:f32x4_pmin, (), [0xfd, 0xea, 0x01]),
        (:f64x2_mul, (), [0xfd, 0xf2, 0x01]),
        (:i32x4_trunc_sat_f32x4_s, (), [0xfd, 0xf8, 0x01]),
        (:f64x2_convert_low_i32x4_u, (), [0xfd, 0xff, 0x01]),
    ]
    relaxed = [:i8x16_relaxed_swizzle, :i32x4_relaxed_trunc_f32x4_s,
        :i32x4_relaxed_trunc_f32x4_u, :i32x4_relaxed_trunc_f64x2_s_zero,
        :i32x4_relaxed_trunc_f64x2_u_zero, :f32x4_relaxed_madd, :f32x4_relaxed_nmadd,
        :f64x2_relaxed_madd, :f64x2_relaxed_nmadd, :i8x16_relaxed_laneselect,
        :i16x8_relaxed_laneselect, :i32x4_relaxed_laneselect, :i64x2_relaxed_laneselect,
        :f32x4_relaxed_min, :f32x4_relaxed_max, :f64x2_relaxed_min, :f64x2_relaxed_max,
        :i16x8_relaxed_q15mulr_s, :i16x8_relaxed_dot_i8x16_i7x16_s,
        :i32x4_relaxed_dot_i8x16_i7x16_add_s]
    for (i, op) in enumerate(relaxed)
        push!(cases, (op, (), UInt8[0xfd, 0x80 + i - 1, 0x02]))
    end
    for (op, imms, expected) in cases
        @test encode_inst(op, imms...) == expected
        @test startswith(sprint(W.show_inst, Inst(op, imms)), replace(string(op), '_' => '.'; count=1))
    end
    bytes = UInt8.(0:15)
    bits = UInt128(0x0f0e0d0c0b0a09080706050403020100)
    @test Inst(:v128_load, MemArg(3, 0)).imm == (MemArg(3, 0),)
    @test Inst(:v128_const, bytes).imm == (bytes,)
    @test Inst(:i8x16_shuffle, bytes).imm == (bytes,)
    @test sprint(W.show_inst, Inst(:memory_init, 129, 0)) == "memory.init 0 129"
    @test sprint(W.show_inst, Inst(:v128_const, fill(-128, 16))) ==
        "v128.const i8x16 " * join(fill(128, 16), " ")
    @test encode_inst(:v128_const, bits) == [0xfd, 0x0c, bytes...]
    @test encode_inst(:v128_const, Int8.(-16:-1)) == [0xfd, 0x0c, UInt8.(240:255)...]
    @test encode_inst(:v128_const, bytes) == [0xfd, 0x0c, bytes...]
    @test encode_inst(:i8x16_shuffle, 16:31) == [0xfd, 0x0d, UInt8.(16:31)...]
    @test sprint(W.show_inst, Inst(:v128_const, bits)) == "v128.const i8x16 " * join(0:15, " ")
    @test sprint(W.show_inst, Inst(:v128_load32_lane, MemArg(2, 16), 3)) ==
        "v128.load32_lane offset=16 align=4 3"
    @test sprint(W.show_inst, Inst(:i8x16_shuffle, 16:31)) == "i8x16.shuffle " * join(16:31, " ")
end

function memory_imms(info; alignment=info.alignment, lane=info.lanes)
    Tuple(k === :memarg ? MemArg(alignment, 0) : k === :lane ? lane - 1 :
          k === :v128 ? UInt128(0) : k === :lanes16 ? collect(0:15) : 0 for k in info.imms)
end

@testset "Complete SIMD table and validation boundaries" begin
    m = WModule(relaxed_simd=true)
    add_memory!(m, 1)
    add_data!(m, UInt8[])
    ops = filter(p -> p.second.sig !== nothing && (p.second.code[1] == 0xfd ||
                 any(k -> k in (:memarg, :memidx, :dataidx), p.second.imms)), collect(W.INSTRUCTIONS))
    @test count(p -> p.second.code[1] == 0xfd && !p.second.relaxed, ops) == 236
    @test count(p -> p.second.relaxed, ops) == 20
    @test length(unique(p.second.code for p in ops)) == length(ops)
    for (op, info) in ops
        imms = memory_imms(info)
        params, results = info.sig
        build(m, string(op), params, results; export_=false) do b
            for i in 0:length(params)-1
                emit!(b, :local_get, i)
            end
            emit!(b, op, imms...)
        end
        if !isempty(params)
            @test fails(m) do b
                unreachable!(b)
                emit!(b, params[end] == F64 ? :i32_const : :f64_const, 0)
                emit!(b, op, imms...)
            end
        end
        if info.lanes !== nothing
            for lane in (-1, info.lanes, 256, 1.0, nothing)
                bad = Tuple(k === :lane ? lane : x for (k, x) in zip(info.imms, imms))
                @test fails(b -> (unreachable!(b); emit!(b, op, bad...)), m)
            end
        end
        if info.alignment !== nothing
            for align in (-1, info.alignment + 1, 32, 1.0)
                bad = Tuple(k === :memarg ? (align isa Integer ? MemArg(align, 0) : (align, 0)) : x for (k, x) in zip(info.imms, imms))
                @test fails(b -> (unreachable!(b); emit!(b, op, bad...)), m)
            end
            for offset in (-1, UInt64(1) << 32, 0.0)
                bad = Tuple(k === :memarg ? (offset isa Integer ? MemArg(0, offset) : (0, offset)) : x for (k, x) in zip(info.imms, imms))
                @test fails(b -> (unreachable!(b); emit!(b, op, bad...)), m)
            end
            build(m, "unaligned_$(op)", params, results; export_=false) do b
                for i in 0:length(params)-1
                    emit!(b, :local_get, i)
                end
                emit!(b, op, memory_imms(info; alignment=0)...)
            end
        end
        if :memarg in info.imms || :memidx in info.imms
            empty = WModule()
            add_data!(empty, UInt8[])
            @test fails(b -> (unreachable!(b); emit!(b, op, imms...)), empty)
            f = add_func!(empty, "raw", params, results)
            push!(f.body, Inst(op, imms))
            err = try
                verify(empty)
            catch e
                e
            end
            @test err isa WasmValidationError
            @test err isa WasmValidationError && err.msg == "module has no memory"
        end
        if info.relaxed
            disabled = WModule()
            @test fails(b -> (unreachable!(b); emit!(b, op)), disabled)
            f = add_func!(disabled, "raw", params, results)
            push!(f.body, Inst(op))
            @test_throws WasmValidationError verify(disabled)
        end
    end
    bytes = to_bytes(m)
    @test checkvalid(bytes)
    @test node_run(bytes, "console.log('validated all opcodes')") == "validated all opcodes"
    if HAS_WASM_TOOLS
        mktempdir() do dir
            wat = disassemble(bytes)
            for (_, info) in ops
                @test occursin(info.text, wat)
            end
            path = joinpath(dir, "module.wat")
            output = joinpath(dir, "module.wasm")
            write(path, wat)
            run(`$(W.wasm_tools()) parse $path -o $output`)
            @test Dict(wasm_sections(read(output)))[10] == Dict(wasm_sections(bytes))[10]
            printed = IOBuffer()
            println(printed, "(module (memory 1) (data \"\")")
            for f in m.funcs
                println(printed, "(func (param ", join(lowercase.(string.(f.params)), " "),
                        ") (result ", join(lowercase.(string.(f.results)), " "), ")")
                W.show_insts(printed, f.body, 1)
                println(printed, ")")
            end
            println(printed, ")")
            write(path, take!(printed))
            run(`$(W.wasm_tools()) parse $path -o $output`)
            @test validate(read(output))
            @test Dict(wasm_sections(read(output)))[10] == Dict(wasm_sections(bytes))[10]
        end
    else
        @info "wasm-tools not found: independent SIMD table disassembly and WAT round-trip checks skipped"
    end

    for op in (:v128_const, :i8x16_shuffle)
        for value in (nothing, 0, "0123456789abcdef", zeros(16), fill(false, 16), Tuple(0:15), [0 for _ in 1:15],
                      [fill(0, 15); op === :v128_const ? -129 : -1], [fill(0, 15); op === :v128_const ? 256 : 32])
            @test fails(b -> (unreachable!(b); emit!(b, op, value)), m)
        end
    end
    for value in (1, -1, 0.0, nothing)
        @test fails(b -> emit!(b, :memory_size, value), m)
    end
    for value in (-1, 1, 0.0, nothing)
        @test fails(b -> emit!(b, :data_drop, value), m)
        @test fails(b -> (unreachable!(b); emit!(b, :memory_init, value, 0)), m)
    end
    @test fails(b -> emit!(b, :v128_load), m)
    @test fails(b -> emit!(b, :f64x2_add, 1), m)
    @test fails(b -> (unreachable!(b); emit!(b, :v128_load, (0,))), m)
    @test fails(b -> (unreachable!(b); emit!(b, :v128_load, [0, 0])), m)

    @test fails(b -> (unreachable!(b); emit!(b, :v128_load, (3, 0))), m)

    mutable_mask = collect(0:15)
    changed = WModule()
    build(changed, "shuffle", ValType[V128, V128], ValType[V128]) do b
        emit!(b, :local_get, 0); emit!(b, :local_get, 1)
        emit!(b, :i8x16_shuffle, mutable_mask)
    end
    mutable_mask[1] = 32
    @test_throws WasmValidationError verify(changed)

    for inst in (Inst(:f64x2_extract_lane, 2), Inst(:i32_load8_u, (MemArg(1, 0),)),
                 Inst(:v128_load64_lane, MemArg(4, 0), 0), Inst(:i8x16_shuffle, fill(32, 16)))
        bad = WModule()
        add_memory!(bad, 1)
        f = add_func!(bad, "raw", ValType[], ValType[])
        push!(f.body, inst)
        @test_throws WasmValidationError to_bytes(bad)
    end
end

@testset "Memory sections, imports and data segments" begin
    for (min, max, expected) in ((0, nothing, [0x01, 0x00, 0x00]),
                                (1, 2, [0x01, 0x01, 0x01, 0x02]),
                                (65536, nothing, [0x01, 0x00, 0x80, 0x80, 0x04]))
        m = WModule()
        add_memory!(m, min, max)
        @test Dict(wasm_sections(to_bytes(m)))[5] == expected
    end
    for (min, max) in ((-1, nothing), (65537, nothing), (2, 1), (0, -1), (0, 65537))
        @test_throws ArgumentError add_memory!(WModule(), min, max)
    end
    m = WModule()
    mem = add_memory!(m, 1, 2)
    @test_throws ArgumentError add_memory!(m, 1)
    @test_throws ArgumentError add_import!(m, "env", "mem", WMemory(1))
    mem.max = 0
    @test_throws WasmValidationError verify(m)
    mem.max = 2
    add_export!(m, "foreign", WMemory(1, 2))
    @test_throws WasmValidationError verify(m)

    m = WModule()
    mem = add_memory!(m, 1)
    add_export!(m, "mem", mem)
    @test add_data!(m, UInt8[0xaa, 0xbb]; offset=4) == 0
    @test add_data!(m, UInt8[0xcc]) == 1
    sections = wasm_sections(to_bytes(m))
    @test Dict(sections)[11] == [0x02, 0x00, 0x41, 0x04, 0x0b, 0x02, 0xaa, 0xbb,
                                 0x01, 0x01, 0xcc]
    @test Dict(sections)[12] == [0x02]
    ids = first.(sections)
    @test findfirst(==(12), ids) < findfirst(==(10), ids) < findfirst(==(11), ids)
    @test occursin("(data (offset (i32.const 4)) \"\\aa\\bb\")", sprint(print_wat, m))
    @test occursin("(data \"\\cc\")", sprint(print_wat, m))
    @test occursin("(memory 1)", sprint(print_wat, m))
    @test occursin("(export \"mem\" (memory 0))", sprint(print_wat, m))
    @test node_run(to_bytes(m), "console.log([...new Uint8Array(e.mem.buffer, 4, 2)].join(','))") == "170,187"

    m = WModule()
    mem = WMemory(1, 2)
    @test add_import!(m, "env", "mem", mem) === mem
    add_export!(m, "mem", mem)
    add_data!(m, UInt8[0x80]; offset=3)
    build(b -> (emit!(b, :i32_const, 3); emit!(b, :i32_load8_s, MemArg(0, 0))), m, "load",
          ValType[], ValType[I32])
    host = add_import!(m, "env", "identity", ValType[I32], ValType[I32])
    build(b -> (emit!(b, :i32_const, 42); call!(b, host)), m, "call_host", ValType[], ValType[I32])
    @test occursin("(memory (import \"\\65\\6e\\76\" \"\\6d\\65\\6d\") 1 2)", sprint(print_wat, m))
    @test occursin("(export \"mem\" (memory 0))", sprint(print_wat, m))
    bytes = to_bytes(m)
    sections = Dict(wasm_sections(bytes))
    @test !haskey(sections, 5)
    @test sections[2][1] == 2
    @test sections[2][end-3:end] == [0x02, 0x01, 0x01, 0x02]
    @test checkvalid(bytes)
    @test node_run(bytes, "console.log(e.load(), e.call_host(), e.mem.buffer.byteLength)";
                   imports="{env: {mem: new WebAssembly.Memory({initial:1, maximum:2}), identity: x => x}}") ==
          "-128 42 65536"

    m = WModule()
    add_data!(m, UInt8[1]; offset=0)
    @test_throws WasmValidationError verify(m)
    for offset in (Inst[Inst(:i64_const, 0)], Inst[Inst(:memory_size, 0)],
                   Inst[Inst(:i32_const, 0), Inst(:i32_const, 1)], Inst[])
        m = WModule()
        add_memory!(m, 1)
        add_data!(m, UInt8[]; offset)
        @test_throws WasmValidationError verify(m)
    end
    m = WModule()
    add_data!(m, UInt8[])
    build(b -> emit!(b, :data_drop, 0), m, "drop")
    @test node_run(to_bytes(m), "e.drop(); console.log('ok')") == "ok"
end

@testset "Linear memory execution" begin
    m = WModule()
    add_export!(m, "mem", add_memory!(m, 1, 2))
    add_data!(m, UInt8[0x55])
    d = add_data!(m, UInt8[0x80, 0xff, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff])
    build(m, "init") do b
        emit!(b, :i32_const, 0); emit!(b, :i32_const, 0); emit!(b, :i32_const, 8)
        emit!(b, :memory_init, d, 0)
    end
    @test occursin("memory.init 0 1", sprint(print_wat, m))
    build(b -> emit!(b, :data_drop, d), m, "drop_data")
    build(m, "copy", ValType[I32, I32, I32]) do b
        for i in 0:2; emit!(b, :local_get, i); end
        emit!(b, :memory_copy, 0, 0)
    end
    build(m, "fill", ValType[I32, I32, I32]) do b
        for i in 0:2; emit!(b, :local_get, i); end
        emit!(b, :memory_fill, 0)
    end
    build(b -> emit!(b, :memory_size, 0), m, "size", ValType[], ValType[I32])
    build(b -> (emit!(b, :local_get, 0); emit!(b, :memory_grow, 0)), m, "grow", ValType[I32], ValType[I32])
    for (op, info) in W.INSTRUCTIONS
        info.code[1] in 0x28:0x3e || continue
        params, results = info.sig
        build(m, string(op), params, results) do b
            for i in 0:length(params)-1; emit!(b, :local_get, i); end
            emit!(b, op, MemArg(0, 0))
        end
    end
    @test node_run(to_bytes(m), """
        const assert = require('assert');
        e.init();
        assert.equal(e.i32_load8_s(0), -128); assert.equal(e.i32_load8_u(0), 128);
        assert.equal(e.i32_load16_s(2), -2); assert.equal(e.i32_load16_u(2), 65534);
        assert.equal(e.i64_load8_s(0), -128n); assert.equal(e.i64_load8_u(0), 128n);
        assert.equal(e.i64_load16_s(2), -2n); assert.equal(e.i64_load16_u(2), 65534n);
        assert.equal(e.i64_load32_s(4), -1n); assert.equal(e.i64_load32_u(4), 4294967295n);
        for (const [type, value] of [['i32', -123456], ['i64', -1234567890123n], ['f32', 1.5], ['f64', Math.PI]]) {
            e[type + '_store'](33, value); assert.equal(e[type + '_load'](33), value);
        }
        for (const [store, load, value, expected] of [
            ['i32_store8', 'i32_load8_u', 511, 255], ['i32_store16', 'i32_load16_u', 65537, 1],
            ['i64_store8', 'i64_load8_u', 511n, 255n], ['i64_store16', 'i64_load16_u', 65537n, 1n],
            ['i64_store32', 'i64_load32_u', 4294967297n, 1n]]) {
            e[store](33, value); assert.equal(e[load](33), expected);
        }
        e.copy(1, 0, 7);
        assert.deepEqual([...new Uint8Array(e.mem.buffer, 0, 8)], [128,128,255,254,255,255,255,255]);
        e.fill(8, 0x1ab, 4); assert.equal(e.i32_load(8), 0xabababab | 0);
        e.drop_data(); e.drop_data(); assert.throws(() => e.init(), WebAssembly.RuntimeError);
        assert.equal(e.size(), 1); assert.equal(e.grow(1), 1); assert.equal(e.size(), 2);
        assert.equal(e.grow(1), -1); assert.equal(e.size(), 2);
        assert.throws(() => e.i32_load(131071), WebAssembly.RuntimeError);
        console.log('ok');
    """) == "ok"
end

@testset "f64x2 kernel with WasmGC and relaxed SIMD" begin
    for relaxed in (false, true)
        m = WModule(relaxed_simd=relaxed)
        add_export!(m, "mem", add_memory!(m, 1))
        array = add_type!(m, ArrayType(FieldType(F64, true)))
        pair = add_type!(m, StructType([FieldType(V128, false)]))
        add_global!(m, "zero", V128, false, Inst[Inst(:v128_const, UInt128(0))])
        build(m, "kernel", ValType[I32, I32, I32, I32, F64], ValType[F64]) do b
            i = add_local!(b.func, I32)
            acc = add_local!(b.func, F64)
            gc = add_local!(b.func, RefType(array))
            vec = add_local!(b.func, V128)
            emit!(b, :f64_const, 0); emit!(b, :local_get, 3); emit!(b, :array_new, array)
            emit!(b, :local_set, gc)
            block!(b); loop!(b)
            emit!(b, :local_get, i); emit!(b, :local_get, 3); emit!(b, :i32_ge_u); br_if!(b, 1)
            emit!(b, :local_get, 0); emit!(b, :local_get, i); emit!(b, :i32_const, 3); emit!(b, :i32_shl)
            emit!(b, :i32_add); emit!(b, :v128_load, MemArg(3, 0))
            emit!(b, :local_get, 4); emit!(b, :f64x2_splat)
            relaxed || emit!(b, :f64x2_mul)
            emit!(b, :local_get, 1); emit!(b, :local_get, i); emit!(b, :i32_const, 3); emit!(b, :i32_shl)
            emit!(b, :i32_add); emit!(b, :v128_load, MemArg(3, 0))
            emit!(b, relaxed ? :f64x2_relaxed_madd : :f64x2_add)
            emit!(b, :struct_new, pair); emit!(b, :struct_get, pair, 0); emit!(b, :local_set, vec)
            emit!(b, :local_get, 2); emit!(b, :local_get, i); emit!(b, :i32_const, 3); emit!(b, :i32_shl)
            emit!(b, :i32_add); emit!(b, :local_get, vec); emit!(b, :v128_store, MemArg(3, 0))
            for lane in 0:1
                emit!(b, :local_get, gc); emit!(b, :local_get, i); emit!(b, :i32_const, lane); emit!(b, :i32_add)
                emit!(b, :local_get, vec); emit!(b, :f64x2_extract_lane, lane); emit!(b, :array_set, array)
                emit!(b, :local_get, acc)
                emit!(b, :local_get, gc); emit!(b, :local_get, i); emit!(b, :i32_const, lane); emit!(b, :i32_add)
                emit!(b, :array_get, array); emit!(b, :f64_add); emit!(b, :local_set, acc)
            end
            emit!(b, :local_get, i); emit!(b, :i32_const, 2); emit!(b, :i32_add); emit!(b, :local_set, i)
            br!(b, 0); end!(b); end!(b)
            emit!(b, :local_get, acc)
        end
        x = [0.25, -2.0, 3.5, 4.0, -0.5, 6.0, 10.0, -8.0]
        y = [-1.0, 3.0, 2.5, -2.0, 0.0, 1.0, -4.0, 9.0]
        expected = 2 .* x .+ y
        bytes = to_bytes(m)
        @test checkvalid(bytes)
        actual = node_run(bytes, """
            const a = new Float64Array(e.mem.buffer);
            a.set($(x), 1); a.set($(y), 17);
            const sum = e.kernel(8, 136, 264, 8, 2);
            console.log([sum, ...a.slice(33,41)].join(','));
        """)
        @test parse.(Float64, split(actual, ',')) == [sum(expected); expected]
    end
end

@testset "Global data offsets and raw immediate validation" begin
    m = WModule()
    add_export!(m, "mem", add_memory!(m, WMemory(1)))
    defined = add_global!(m, "defined", I32, false, Inst[Inst(:i32_const, 12)])
    offset = add_import!(m, "env", "offset", I32)
    @test offset === m.globals[1]
    @test offset.idx == 0 && defined.idx == 1
    add_export!(m, "offset", offset)
    add_export!(m, "defined", defined)
    add_data!(m, UInt8[0xab, 0xcd]; offset=Inst[Inst(:global_get, offset)])
    @test verify(m) === nothing
    @test occursin("(offset (global.get \$offset))", sprint(print_wat, m))
    bytes = to_bytes(m)
    @test checkvalid(bytes)
    @test node_run(bytes, """
        const assert = require('assert');
        assert.deepEqual([...new Uint8Array(e.mem.buffer, 7, 2)], [171, 205]);
        assert.equal(e.offset.value, 7); assert.equal(e.defined.value, 12);
        console.log('ok');
    """; imports="{env: {offset: new WebAssembly.Global({value:'i32', mutable:false}, 7)}}") == "ok"
    offset.mutable = true
    @test_throws WasmValidationError verify(m)
    offset.mutable = false
    offset.type = I64
    @test_throws WasmValidationError verify(m)
    offset.type = I32
    push!(offset.init, Inst(:i32_const, 0))
    @test_throws WasmValidationError verify(m)
    empty!(offset.init)
    m.datas[1] = DataSegment(UInt8[1], Inst[Inst(:global_get, defined)])
    @test verify(m) === nothing
    foreign = add_global!(WModule(), "foreign", I32, false, Inst[Inst(:i32_const, 0)])
    m.datas[1] = DataSegment(UInt8[1], Inst[Inst(:global_get, foreign)])
    @test_throws WasmValidationError verify(m)

    for inst in (Inst(:i32_const, 1 << 40), Inst(:i64_const, "bad"),
                 Inst(:i32_add, 0), Inst(:local_get, -1), Inst(:block, :empty, 0),
                 Inst(:v128_const, Tuple(0:15)), Inst(:i8x16_shuffle, Tuple(0:15)))
        m = WModule()
        f = add_func!(m, "raw", ValType[], ValType[])
        push!(f.body, inst)
        @test_throws WasmValidationError verify(m)
    end
    for op in (:array_new_data, :array_init_data)
        m = WModule()
        t = add_type!(m, ArrayType(FieldType(I8, true)))
        @test W.INSTRUCTIONS[op].imms == (:type, :dataidx)
        f = add_func!(m, "raw", ValType[], ValType[])
        push!(f.body, Inst(op, t, 0))
        @test_throws WasmValidationError verify(m)
    end
end
