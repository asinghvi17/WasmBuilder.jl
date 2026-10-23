# The binary encoding of a module.

function leb_u(io::IO, x::Integer)
    x = UInt64(x)
    while true
        b = UInt8(x & 0x7f)
        x >>= 7
        if x == 0
            write(io, b)
            return
        end
        write(io, b | 0x80)
    end
end

function leb_s(io::IO, x::Integer)
    x = Int64(x)
    while true
        b = UInt8(x & 0x7f)
        x >>= 7
        if (x == 0 && b & 0x40 == 0) || (x == -1 && b & 0x40 != 0)
            write(io, b)
            return
        end
        write(io, b | 0x80)
    end
end

function leb_s128(io::IO, x::Int128)
    while true
        b = UInt8(x & 0x7f)
        x >>= 7
        if (x == 0 && b & 0x40 == 0) || (x == -1 && b & 0x40 != 0)
            write(io, b)
            return
        end
        write(io, b | 0x80)
    end
end

function write_name(io::IO, s::AbstractString)
    leb_u(io, ncodeunits(s))
    write(io, codeunits(s))
end

function write_vec(f, io::IO, xs)
    leb_u(io, length(xs))
    foreach(x -> f(io, x), xs)
end

write_heap(io::IO, h::Symbol) = write(io, ABSTRACT_HEAPTYPES[h])
write_heap(io::IO, h::TypeRef) = leb_s(io, h.idx)   # s33

write_valtype(io::IO, t::NumType) = write(io, UInt8(t))
function write_valtype(io::IO, t::RefType)
    write(io, t.nullable ? 0x63 : 0x64)
    write_heap(io, t.heap)
end
write_storage(io::IO, t::PackedType) = write(io, UInt8(t))
write_storage(io::IO, t::ValType) = write_valtype(io, t)

function write_field(io::IO, f::FieldType)
    write_storage(io, f.storage)
    write(io, f.mutable ? 0x01 : 0x00)
end

function write_comp(io::IO, t::FuncType)
    write(io, 0x60)
    write_vec(write_valtype, io, t.params)
    write_vec(write_valtype, io, t.results)
end
function write_comp(io::IO, t::StructType)
    write(io, 0x5f)
    write_vec(write_field, io, t.fields)
end
function write_comp(io::IO, t::ArrayType)
    write(io, 0x5e)
    write_field(io, t.elem)
end

function write_subtype(io::IO, t::SubType)
    write(io, t.final ? 0x4f : 0x50)
    if t.super === nothing
        leb_u(io, 0)
    else
        leb_u(io, 1)
        leb_u(io, t.super.idx)
    end
    write_comp(io, t.comp)
end

## instructions

# name => (opcode bytes, immediate kinds)
const OPCODES = Dict{Symbol,Tuple{Vector{UInt8},Tuple}}()

let simple = [
        :unreachable => 0x00, :nop => 0x01, :else => 0x05, :end => 0x0b, :return => 0x0f,
        :drop => 0x1a, :select => 0x1b, :throw_ref => 0x0a,
        :i32_eqz => 0x45, :i32_eq => 0x46, :i32_ne => 0x47, :i32_lt_s => 0x48,
        :i32_lt_u => 0x49, :i32_gt_s => 0x4a, :i32_gt_u => 0x4b, :i32_le_s => 0x4c,
        :i32_le_u => 0x4d, :i32_ge_s => 0x4e, :i32_ge_u => 0x4f,
        :i64_eqz => 0x50, :i64_eq => 0x51, :i64_ne => 0x52, :i64_lt_s => 0x53,
        :i64_lt_u => 0x54, :i64_gt_s => 0x55, :i64_gt_u => 0x56, :i64_le_s => 0x57,
        :i64_le_u => 0x58, :i64_ge_s => 0x59, :i64_ge_u => 0x5a,
        :f32_eq => 0x5b, :f32_ne => 0x5c, :f32_lt => 0x5d, :f32_gt => 0x5e,
        :f32_le => 0x5f, :f32_ge => 0x60,
        :f64_eq => 0x61, :f64_ne => 0x62, :f64_lt => 0x63, :f64_gt => 0x64,
        :f64_le => 0x65, :f64_ge => 0x66,
        :i32_clz => 0x67, :i32_ctz => 0x68, :i32_popcnt => 0x69, :i32_add => 0x6a,
        :i32_sub => 0x6b, :i32_mul => 0x6c, :i32_div_s => 0x6d, :i32_div_u => 0x6e,
        :i32_rem_s => 0x6f, :i32_rem_u => 0x70, :i32_and => 0x71, :i32_or => 0x72,
        :i32_xor => 0x73, :i32_shl => 0x74, :i32_shr_s => 0x75, :i32_shr_u => 0x76,
        :i32_rotl => 0x77, :i32_rotr => 0x78,
        :i64_clz => 0x79, :i64_ctz => 0x7a, :i64_popcnt => 0x7b, :i64_add => 0x7c,
        :i64_sub => 0x7d, :i64_mul => 0x7e, :i64_div_s => 0x7f, :i64_div_u => 0x80,
        :i64_rem_s => 0x81, :i64_rem_u => 0x82, :i64_and => 0x83, :i64_or => 0x84,
        :i64_xor => 0x85, :i64_shl => 0x86, :i64_shr_s => 0x87, :i64_shr_u => 0x88,
        :i64_rotl => 0x89, :i64_rotr => 0x8a,
        :f32_abs => 0x8b, :f32_neg => 0x8c, :f32_ceil => 0x8d, :f32_floor => 0x8e,
        :f32_trunc => 0x8f, :f32_nearest => 0x90, :f32_sqrt => 0x91, :f32_add => 0x92,
        :f32_sub => 0x93, :f32_mul => 0x94, :f32_div => 0x95, :f32_min => 0x96,
        :f32_max => 0x97, :f32_copysign => 0x98,
        :f64_abs => 0x99, :f64_neg => 0x9a, :f64_ceil => 0x9b, :f64_floor => 0x9c,
        :f64_trunc => 0x9d, :f64_nearest => 0x9e, :f64_sqrt => 0x9f, :f64_add => 0xa0,
        :f64_sub => 0xa1, :f64_mul => 0xa2, :f64_div => 0xa3, :f64_min => 0xa4,
        :f64_max => 0xa5, :f64_copysign => 0xa6,
        :i32_wrap_i64 => 0xa7, :i32_trunc_f32_s => 0xa8, :i32_trunc_f32_u => 0xa9,
        :i32_trunc_f64_s => 0xaa, :i32_trunc_f64_u => 0xab, :i64_extend_i32_s => 0xac,
        :i64_extend_i32_u => 0xad, :i64_trunc_f32_s => 0xae, :i64_trunc_f32_u => 0xaf,
        :i64_trunc_f64_s => 0xb0, :i64_trunc_f64_u => 0xb1, :f32_convert_i32_s => 0xb2,
        :f32_convert_i32_u => 0xb3, :f32_convert_i64_s => 0xb4, :f32_convert_i64_u => 0xb5,
        :f32_demote_f64 => 0xb6, :f64_convert_i32_s => 0xb7, :f64_convert_i32_u => 0xb8,
        :f64_convert_i64_s => 0xb9, :f64_convert_i64_u => 0xba, :f64_promote_f32 => 0xbb,
        :i32_reinterpret_f32 => 0xbc, :i64_reinterpret_f64 => 0xbd,
        :f32_reinterpret_i32 => 0xbe, :f64_reinterpret_i64 => 0xbf,
        :i32_extend8_s => 0xc0, :i32_extend16_s => 0xc1, :i64_extend8_s => 0xc2,
        :i64_extend16_s => 0xc3, :i64_extend32_s => 0xc4,
        :ref_is_null => 0xd1, :ref_eq => 0xd3, :ref_as_non_null => 0xd4]
    for (name, op) in simple
        OPCODES[name] = (UInt8[op], ())
    end
    for (i, name) in enumerate((:i32_trunc_sat_f32_s, :i32_trunc_sat_f32_u,
                                :i32_trunc_sat_f64_s, :i32_trunc_sat_f64_u,
                                :i64_trunc_sat_f32_s, :i64_trunc_sat_f32_u,
                                :i64_trunc_sat_f64_s, :i64_trunc_sat_f64_u))
        OPCODES[name] = (UInt8[0xfc, i - 1], ())
    end
    OPCODES[:block] = (UInt8[0x02], (:bt,))
    OPCODES[:loop] = (UInt8[0x03], (:bt,))
    OPCODES[:if] = (UInt8[0x04], (:bt,))
    OPCODES[:br] = (UInt8[0x0c], (:u32,))
    OPCODES[:br_if] = (UInt8[0x0d], (:u32,))
    OPCODES[:br_table] = (UInt8[0x0e], (:labels, :u32))
    OPCODES[:call] = (UInt8[0x10], (:func,))
    OPCODES[:return_call] = (UInt8[0x12], (:func,))
    OPCODES[:call_ref] = (UInt8[0x14], (:type,))
    OPCODES[:throw] = (UInt8[0x08], (:tag,))
    OPCODES[:try_table] = (UInt8[0x1f], (:bt, :catches))
    OPCODES[:select_t] = (UInt8[0x1c], (:valtypes,))
    OPCODES[:local_get] = (UInt8[0x20], (:u32,))
    OPCODES[:local_set] = (UInt8[0x21], (:u32,))
    OPCODES[:local_tee] = (UInt8[0x22], (:u32,))
    OPCODES[:global_get] = (UInt8[0x23], (:global,))
    OPCODES[:global_set] = (UInt8[0x24], (:global,))
    OPCODES[:i32_const] = (UInt8[0x41], (:i32,))
    OPCODES[:i64_const] = (UInt8[0x42], (:i64,))
    OPCODES[:f32_const] = (UInt8[0x43], (:f32,))
    OPCODES[:f64_const] = (UInt8[0x44], (:f64,))
    OPCODES[:ref_null] = (UInt8[0xd0], (:heap,))
    OPCODES[:ref_func] = (UInt8[0xd2], (:func,))
    OPCODES[:br_on_null] = (UInt8[0xd5], (:u32,))
    OPCODES[:br_on_non_null] = (UInt8[0xd6], (:u32,))
    gc = [
        :struct_new => (0x00, (:type,)), :struct_new_default => (0x01, (:type,)),
        :struct_get => (0x02, (:type, :u32)), :struct_get_s => (0x03, (:type, :u32)),
        :struct_get_u => (0x04, (:type, :u32)), :struct_set => (0x05, (:type, :u32)),
        :array_new => (0x06, (:type,)), :array_new_default => (0x07, (:type,)),
        :array_new_fixed => (0x08, (:type, :u32)), :array_new_data => (0x09, (:type, :u32)),
        :array_get => (0x0b, (:type,)), :array_get_s => (0x0c, (:type,)),
        :array_get_u => (0x0d, (:type,)), :array_set => (0x0e, (:type,)),
        :array_len => (0x0f, ()), :array_fill => (0x10, (:type,)),
        :array_copy => (0x11, (:type, :type)), :array_init_data => (0x12, (:type, :u32)),
        :ref_test => (0x14, (:heap,)), :ref_test_null => (0x15, (:heap,)),
        :ref_cast => (0x16, (:heap,)), :ref_cast_null => (0x17, (:heap,)),
        :br_on_cast => (0x18, (:castflags, :u32, :heap, :heap)),
        :br_on_cast_fail => (0x19, (:castflags, :u32, :heap, :heap)),
        :any_convert_extern => (0x1a, ()), :extern_convert_any => (0x1b, ()),
        :ref_i31 => (0x1c, ()), :i31_get_s => (0x1d, ()), :i31_get_u => (0x1e, ())]
    for (name, (op, imms)) in gc
        OPCODES[name] = (UInt8[0xfb, op], imms)
    end
end

function write_blocktype(io::IO, bt)
    if bt === nothing || bt === :empty
        write(io, 0x40)
    elseif bt isa ValType
        write_valtype(io, bt)
    elseif bt isa TypeRef
        leb_s(io, bt.idx)
    else
        error("invalid block type $bt")
    end
end

function write_imm(io::IO, kind::Symbol, @nospecialize(x))
    if kind === :u32
        leb_u(io, x)
    elseif kind === :i32
        leb_s(io, x isa Unsigned ? reinterpret(signed(typeof(x)), x) : x)
    elseif kind === :i64
        leb_s(io, x isa Unsigned ? reinterpret(Int64, UInt64(x)) : Int64(x))
    elseif kind === :f32
        write(io, htol(reinterpret(UInt32, Float32(x))))
    elseif kind === :f64
        write(io, htol(reinterpret(UInt64, Float64(x))))
    elseif kind === :bt
        write_blocktype(io, x)
    elseif kind === :type
        leb_u(io, (x::TypeRef).idx)
    elseif kind === :heap
        write_heap(io, x)
    elseif kind === :func
        leb_u(io, (x::Func).idx)
    elseif kind === :global
        leb_u(io, (x::Global).idx)
    elseif kind === :tag
        leb_u(io, (x::Tag).idx)
    elseif kind === :labels
        write_vec(leb_u, io, x)
    elseif kind === :valtypes
        write_vec(write_valtype, io, x)
    elseif kind === :castflags
        write(io, UInt8(x))
    elseif kind === :catches
        # (kind, tag or nothing, label): 0 catch, 1 catch_ref, 2 catch_all, 3 catch_all_ref
        leb_u(io, length(x))
        for (k, tag, label) in x
            write(io, UInt8(k))
            k < 2 && leb_u(io, (tag::Tag).idx)
            leb_u(io, label)
        end
    else
        error("unknown immediate kind $kind")
    end
end

function write_inst(io::IO, inst::Inst)
    entry = get(OPCODES, inst.op, nothing)
    entry === nothing && error("unknown instruction $(inst.op)")
    bytes, kinds = entry
    write(io, bytes)
    length(kinds) == length(inst.imm) ||
        error("instruction $(inst.op) takes $(length(kinds)) immediates, got $(length(inst.imm))")
    for (k, x) in zip(kinds, inst.imm)
        write_imm(io, k, x)
    end
end

function write_expr(io::IO, insts::Vector{Inst})
    foreach(i -> write_inst(io, i), insts)
    write(io, 0x0b)
end

## sections

function write_section(f, io::IO, id::Integer)
    buf = IOBuffer()
    f(buf)
    bytes = take!(buf)
    write(io, UInt8(id))
    leb_u(io, length(bytes))
    write(io, bytes)
end

function write_locals(io::IO, locals::Vector{ValType})
    # runs of equal types
    runs = Tuple{Int,ValType}[]
    for t in locals
        if !isempty(runs) && runs[end][2] == t
            runs[end] = (runs[end][1] + 1, t)
        else
            push!(runs, (1, t))
        end
    end
    leb_u(io, length(runs))
    for (n, t) in runs
        leb_u(io, n)
        write_valtype(io, t)
    end
end

"""
    to_bytes(m::WModule) -> Vector{UInt8}

The binary encoding of the module.
"""
function to_bytes(m::WModule)
    assign_indices!(m)
    io = IOBuffer()
    write(io, UInt8[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
    imports = filter(f -> f.imported !== nothing, m.funcs)
    defined = filter(f -> f.imported === nothing, m.funcs)

    # types: one recursion group
    write_section(io, 1) do s
        leb_u(s, 1)
        write(s, 0x4e)
        write_vec(write_subtype, s, m.types)
    end
    isempty(imports) || write_section(io, 2) do s
        write_vec(s, imports) do s, f
            write_name(s, f.imported[1])
            write_name(s, f.imported[2])
            write(s, 0x00)
            leb_u(s, f.type.idx)
        end
    end
    write_section(io, 3) do s
        write_vec((s, f) -> leb_u(s, f.type.idx), s, defined)
    end
    isempty(m.tags) || write_section(io, 13) do s
        write_vec(s, m.tags) do s, t
            write(s, 0x00)
            leb_u(s, t.type.idx)
        end
    end
    isempty(m.globals) || write_section(io, 6) do s
        write_vec(s, m.globals) do s, g
            write_valtype(s, g.type)
            write(s, g.mutable ? 0x01 : 0x00)
            write_expr(s, g.init)
        end
    end
    isempty(m.exports) || write_section(io, 7) do s
        write_vec(s, m.exports) do s, (name, item)
            write_name(s, name)
            if item isa Func
                write(s, 0x00); leb_u(s, item.idx)
            elseif item isa Global
                write(s, 0x03); leb_u(s, item.idx)
            elseif item isa Tag
                write(s, 0x04); leb_u(s, item.idx)
            else
                error("cannot export $item")
            end
        end
    end
    m.start === nothing || write_section(io, 8) do s
        leb_u(s, m.start.idx)
    end
    isempty(m.declared) || write_section(io, 9) do s
        # one declarative segment of function indices
        leb_u(s, 1)
        leb_u(s, 3)
        write(s, 0x00)
        write_vec((s, f) -> leb_u(s, f.idx), s, m.declared)
    end
    isempty(m.datas) || write_section(io, 12) do s
        leb_u(s, length(m.datas))
    end
    write_section(io, 10) do s
        write_vec(s, defined) do s, f
            body = IOBuffer()
            write_locals(body, f.locals)
            write_expr(body, f.body)
            bytes = take!(body)
            leb_u(s, length(bytes))
            write(s, bytes)
        end
    end
    isempty(m.datas) || write_section(io, 11) do s
        write_vec(s, m.datas) do s, d
            leb_u(s, 1)    # passive
            leb_u(s, length(d))
            write(s, d)
        end
    end
    # names, for debugging (function names)
    write_section(io, 0) do s
        write_name(s, "name")
        sub = IOBuffer()
        all = sort(m.funcs; by=f -> f.idx)
        write_vec(sub, all) do sub, f
            leb_u(sub, f.idx)
            write_name(sub, f.name)
        end
        bytes = take!(sub)
        write(s, 0x01)
        leb_u(s, length(bytes))
        write(s, bytes)
    end
    return take!(io)
end
