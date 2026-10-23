# A builder of function bodies that validates every instruction as it is emitted, against
# the operand stack and the control frames (the validation algorithm of the spec's
# appendix), so that a code generator's mistakes are reported where they are made.

"""
    WasmValidationError

An instruction that does not validate, with the function, the position of the
instruction and the reason.
"""
struct WasmValidationError <: Exception
    func::String
    pos::Int
    op::Symbol
    msg::String
    stack::Vector{Any}
end

function Base.showerror(io::IO, e::WasmValidationError)
    print(io, "WasmValidationError in function ", e.func, " at instruction ", e.pos, " (",
          e.op, "): ", e.msg)
    print(io, "\n  operand stack: [", join(map(t -> t === nothing ? "⊥" : string(t), e.stack), ", "), "]")
end

struct Frame
    kind::Symbol            # :func, :block, :loop, :if, :else, :try_table
    params::Vector{ValType}
    results::Vector{ValType}
    height::Int
    unreachable::Bool
end

"""
    Builder(m::WModule, f::Func)

A builder appending to the body of the function `f` of the module `m`. Instructions are
emitted with [`emit!`](@ref) (and the control instructions with their own functions),
and validated as they are. [`finish!`](@ref) ends the body.
"""
mutable struct Builder
    mod::WModule
    func::Func
    stack::Vector{Union{Nothing,ValType}}
    frames::Vector{Frame}
end

function Builder(m::WModule, f::Func)
    b = Builder(m, f, Union{Nothing,ValType}[], Frame[])
    push!(b.frames, Frame(:func, ValType[], f.results, 0, false))
    return b
end

const VALIDATE = Ref(true)

verr(b::Builder, op::Symbol, msg) =
    throw(WasmValidationError(b.func.name, length(b.func.body) + 1, op, msg, copy(b.stack)))

top_frame(b::Builder) = b.frames[end]

function push_t!(b::Builder, t::Union{Nothing,ValType})
    push!(b.stack, t)
end

function pop_any!(b::Builder, op::Symbol)
    f = top_frame(b)
    if length(b.stack) == f.height
        f.unreachable && return nothing
        verr(b, op, "operand stack underflow")
    end
    return pop!(b.stack)
end

function pop_t!(b::Builder, op::Symbol, expected::ValType)
    actual = pop_any!(b, op)
    actual === nothing && return expected
    subtype(b.mod, actual, expected) || verr(b, op, "expected $expected, got $actual")
    return actual
end

function pop_ts!(b::Builder, op::Symbol, ts)
    for t in Iterators.reverse(ts)
        pop_t!(b, op, t)
    end
end

function set_unreachable!(b::Builder)
    f = b.frames[end]
    resize!(b.stack, f.height)
    b.frames[end] = Frame(f.kind, f.params, f.results, f.height, true)
end

"Whether the code being emitted is unreachable (after a branch, `return`, ...)."
is_unreachable(b::Builder) = b.frames[end].unreachable

"The types of the operand stack (`nothing` for unknown ones in unreachable code)."
stack(b::Builder) = b.stack

append_inst!(b::Builder, op::Symbol, imm...) = push!(b.func.body, Inst(op, imm))

## block types

"""
    blocktype(b, params, results)

The block type of a block taking `params` and producing `results`: empty, a value type,
or a function type of the module.
"""
function blocktype(b::Builder, params::Vector{ValType}, results::Vector{ValType})
    isempty(params) && isempty(results) && return :empty
    isempty(params) && length(results) == 1 && return results[1]
    return functype!(b.mod, params, results)
end

function blocktype_sig(b::Builder, bt)
    (bt === :empty || bt === nothing) && return ValType[], ValType[]
    bt isa ValType && return ValType[], ValType[bt]
    ft = typedef(b.mod, bt::TypeRef).comp::FuncType
    return ft.params, ft.results
end

label_types(f::Frame) = f.kind === :loop ? f.params : f.results

function label_frame(b::Builder, op::Symbol, depth::Integer)
    depth < length(b.frames) || verr(b, op, "invalid branch depth $depth")
    return b.frames[end-depth]
end

## control instructions

function push_frame!(b::Builder, kind::Symbol, params, results)
    push!(b.frames, Frame(kind, params, results, length(b.stack), false))
    for t in params
        push_t!(b, t)
    end
end

"Begin a `block` with the block type `bt`."
function block!(b::Builder, bt=:empty)
    params, results = blocktype_sig(b, bt)
    VALIDATE[] && pop_ts!(b, :block, params)
    append_inst!(b, :block, bt)
    push_frame!(b, :block, params, results)
end

"Begin a `loop` with the block type `bt`."
function loop!(b::Builder, bt=:empty)
    params, results = blocktype_sig(b, bt)
    VALIDATE[] && pop_ts!(b, :loop, params)
    append_inst!(b, :loop, bt)
    push_frame!(b, :loop, params, results)
end

"Begin an `if` (on an `i32` condition) with the block type `bt`."
function if!(b::Builder, bt=:empty)
    params, results = blocktype_sig(b, bt)
    if VALIDATE[]
        pop_t!(b, :if, I32)
        pop_ts!(b, :if, params)
    end
    append_inst!(b, :if, bt)
    push_frame!(b, :if, params, results)
end

"Begin the `else` arm of the current `if`."
function else!(b::Builder)
    f = top_frame(b)
    f.kind === :if || verr(b, :else, "else outside of an if")
    end_check!(b, :else, f)
    pop!(b.frames)
    resize!(b.stack, f.height)
    append_inst!(b, :else)
    push_frame!(b, :else, f.params, f.results)
end

function end_check!(b::Builder, op::Symbol, f::Frame)
    VALIDATE[] || return
    pop_ts!(b, op, f.results)
    length(b.stack) == f.height ||
        verr(b, op, "$(length(b.stack) - f.height) values left on the stack at the end of a $(f.kind)")
end

"End the current block, loop, if or the function body."
function end!(b::Builder)
    f = top_frame(b)
    if f.kind === :if && f.params != f.results
        verr(b, :end, "an if without else must have matching params and results")
    end
    end_check!(b, :end, f)
    pop!(b.frames)
    resize!(b.stack, f.height)
    append_inst!(b, :end)
    if !isempty(b.frames)
        for t in f.results
            push_t!(b, t)
        end
    end
end

"End the function body (the final `end` is implicit in the binary format)."
function finish!(b::Builder)
    length(b.frames) == 1 || verr(b, :end, "$(length(b.frames) - 1) unclosed blocks at the end of the function")
    end_check!(b, :end, top_frame(b))
    pop!(b.frames)
    return b.func
end

"Branch to the label `depth` (0 is the innermost block)."
function br!(b::Builder, depth::Integer)
    f = label_frame(b, :br, depth)
    VALIDATE[] && pop_ts!(b, :br, label_types(f))
    append_inst!(b, :br, depth)
    set_unreachable!(b)
end

"Branch to the label `depth` if the `i32` on the stack is nonzero."
function br_if!(b::Builder, depth::Integer)
    f = label_frame(b, :br_if, depth)
    ts = label_types(f)
    if VALIDATE[]
        pop_t!(b, :br_if, I32)
        pop_ts!(b, :br_if, ts)
        foreach(t -> push_t!(b, t), ts)
    end
    append_inst!(b, :br_if, depth)
end

"Branch to `labels[i]` for `i` on the stack, or to `default`."
function br_table!(b::Builder, labels::Vector{Int}, default::Integer)
    ts = label_types(label_frame(b, :br_table, default))
    if VALIDATE[]
        pop_t!(b, :br_table, I32)
        for l in labels
            length(label_types(label_frame(b, :br_table, l))) == length(ts) ||
                verr(b, :br_table, "branch targets of different arities")
        end
        pop_ts!(b, :br_table, ts)
    end
    append_inst!(b, :br_table, labels, default)
    set_unreachable!(b)
end

"Branch to `depth` if the reference on the stack is null; otherwise keep it, non-null."
function br_on_null!(b::Builder, depth::Integer)
    ts = label_types(label_frame(b, :br_on_null, depth))
    t = pop_any!(b, :br_on_null)
    VALIDATE[] && (pop_ts!(b, :br_on_null, ts); foreach(t -> push_t!(b, t), ts))
    append_inst!(b, :br_on_null, depth)
    push_t!(b, t === nothing ? nothing : RefType(t.heap, false))
end

"Return from the function."
function return!(b::Builder)
    VALIDATE[] && pop_ts!(b, :return, b.frames[1].results)
    append_inst!(b, :return)
    set_unreachable!(b)
end

"Trap."
function unreachable!(b::Builder)
    append_inst!(b, :unreachable)
    set_unreachable!(b)
end

"Throw the exception `tag` with the payload on the stack."
function throw!(b::Builder, tag::Tag)
    ft = typedef(b.mod, tag.type).comp::FuncType
    VALIDATE[] && pop_ts!(b, :throw, ft.params)
    append_inst!(b, :throw, tag)
    set_unreachable!(b)
end

"""
    try_table!(b, bt, catches)

Begin a `try_table` block with the handlers `catches`, `(kind, tag, label)` tuples: kind 0
`catch`, 1 `catch_ref`, 2 `catch_all`, 3 `catch_all_ref` (labels relative to outside the
`try_table`).
"""
function try_table!(b::Builder, bt, catches::Vector)
    params, results = blocktype_sig(b, bt)
    VALIDATE[] && pop_ts!(b, :try_table, params)
    append_inst!(b, :try_table, bt, catches)
    push_frame!(b, :try_table, params, results)
end

## calls

"Call the function `f`."
function call!(b::Builder, f::Func)
    VALIDATE[] && pop_ts!(b, :call, f.params)
    append_inst!(b, :call, f)
    foreach(t -> push_t!(b, t), f.results)
end

"Call the function reference on the stack, of function type `t`."
function call_ref!(b::Builder, t::TypeRef)
    ft = typedef(b.mod, t).comp::FuncType
    if VALIDATE[]
        pop_t!(b, :call_ref, RefType(t, true))
        pop_ts!(b, :call_ref, ft.params)
    end
    append_inst!(b, :call_ref, t)
    foreach(t -> push_t!(b, t), ft.results)
end

## other instructions: validated by their signatures

"""
    emit!(b, op, imms...)

Emit the (non-control) instruction `op` with the immediates `imms`, validating it.
"""
function emit!(b::Builder, op::Symbol, imms...)
    if VALIDATE[]
        typecheck!(b, op, imms)
    else
        typecheck_push!(b, op, imms)
    end
    append_inst!(b, op, imms...)
    return b
end

const NUMTYPES = Dict("i32" => I32, "i64" => I64, "f32" => F32, "f64" => F64)
const BINOPS = Set(["add", "sub", "mul", "div", "div_s", "div_u", "rem_s", "rem_u", "and",
                    "or", "xor", "shl", "shr_s", "shr_u", "rotl", "rotr", "min", "max",
                    "copysign"])
const UNOPS = Set(["clz", "ctz", "popcnt", "abs", "neg", "ceil", "floor", "trunc",
                   "nearest", "sqrt", "extend8_s", "extend16_s", "extend32_s"])
const RELOPS = Set(["eq", "ne", "lt", "lt_s", "lt_u", "gt", "gt_s", "gt_u", "le", "le_s",
                    "le_u", "ge", "ge_s", "ge_u"])

# the signature (params, results) of a numeric instruction, from its name
const NUMERIC_SIGS = Dict{Symbol,Union{Nothing,Tuple{Vector{ValType},Vector{ValType}}}}()
function numeric_sig(op::Symbol)
    get!(NUMERIC_SIGS, op) do
        parts = split(string(op), '_')
        t = get(NUMTYPES, parts[1], nothing)
        t === nothing && return nothing
        rest = join(parts[2:end], '_')
        src = nothing
        for p in parts[2:end]
            haskey(NUMTYPES, p) && (src = NUMTYPES[p])
        end
        if src !== nothing
            (ValType[src], ValType[t])          # conversion
        elseif rest in BINOPS
            (ValType[t, t], ValType[t])
        elseif rest in UNOPS
            (ValType[t], ValType[t])
        elseif rest == "eqz"
            (ValType[t], ValType[I32])
        elseif rest in RELOPS
            (ValType[t, t], ValType[I32])
        else
            nothing
        end
    end
end

field_types(b::Builder, t::TypeRef) = (typedef(b.mod, t).comp::StructType).fields
array_elem(b::Builder, t::TypeRef) = (typedef(b.mod, t).comp::ArrayType).elem

function expect_struct(b::Builder, op, t)
    t isa TypeRef && typedef(b.mod, t).comp isa StructType || verr(b, op, "$t is not a struct type")
end
function expect_array(b::Builder, op, t)
    t isa TypeRef && typedef(b.mod, t).comp isa ArrayType || verr(b, op, "$t is not an array type")
end

function check_field_read(b, op, f::FieldType)
    packed = f.storage isa PackedType
    if op === :struct_get || op === :array_get
        packed && verr(b, op, "packed field read without sign extension")
    else
        packed || verr(b, op, "sign extension on a non-packed field")
    end
end

# the type of a reference operand: a reference whose heap type is in the hierarchy of `top`
function pop_ref!(b::Builder, op::Symbol)
    t = pop_any!(b, op)
    t === nothing || t isa RefType || verr(b, op, "expected a reference, got $t")
    return t
end

function typecheck!(b::Builder, op::Symbol, imms)
    m = b.mod
    sig = numeric_sig(op)
    if sig !== nothing && !(op in (:i32_const, :i64_const, :f32_const, :f64_const))
        pop_ts!(b, op, sig[1])
        foreach(t -> push_t!(b, t), sig[2])
        return
    end
    if op === :i32_const
        push_t!(b, I32)
    elseif op === :i64_const
        push_t!(b, I64)
    elseif op === :f32_const
        push_t!(b, F32)
    elseif op === :f64_const
        push_t!(b, F64)
    elseif op === :nop
    elseif op === :drop
        pop_any!(b, op)
    elseif op === :select
        pop_t!(b, op, I32)
        t2 = pop_any!(b, op); t1 = pop_any!(b, op)
        (t1 === nothing || t1 isa NumType) && (t2 === nothing || t2 isa NumType) ||
            verr(b, op, "untyped select on references")
        t1 !== nothing && t2 !== nothing && t1 !== t2 && verr(b, op, "select of $t1 and $t2")
        push_t!(b, something(t1, t2, Some(nothing)))
    elseif op === :select_t
        t = only(imms[1])
        pop_t!(b, op, I32); pop_t!(b, op, t); pop_t!(b, op, t)
        push_t!(b, t)
    elseif op === :local_get
        push_t!(b, local_type(b.func, imms[1]))
    elseif op === :local_set
        pop_t!(b, op, local_type(b.func, imms[1]))
    elseif op === :local_tee
        t = local_type(b.func, imms[1])
        pop_t!(b, op, t)
        push_t!(b, t)
    elseif op === :global_get
        push_t!(b, (imms[1]::Global).type)
    elseif op === :global_set
        g = imms[1]::Global
        g.mutable || verr(b, op, "global $(g.name) is immutable")
        pop_t!(b, op, g.type)
    elseif op === :ref_null
        push_t!(b, RefType(imms[1], true))
    elseif op === :ref_is_null
        pop_ref!(b, op)
        push_t!(b, I32)
    elseif op === :ref_as_non_null
        t = pop_ref!(b, op)
        push_t!(b, t === nothing ? nothing : RefType(t.heap, false))
    elseif op === :ref_eq
        pop_t!(b, op, RefType(:eq, true)); pop_t!(b, op, RefType(:eq, true))
        push_t!(b, I32)
    elseif op === :ref_func
        f = imms[1]::Func
        declare!(m, f)
        push_t!(b, RefType(f.type, false))
    elseif op in (:ref_test, :ref_test_null, :ref_cast, :ref_cast_null)
        ht = imms[1]
        t = pop_ref!(b, op)
        t === nothing || heap_top(m, t.heap) === heap_top(m, ht) ||
            verr(b, op, "cast of $t to a different hierarchy ($ht)")
        if op in (:ref_test, :ref_test_null)
            push_t!(b, I32)
        else
            push_t!(b, RefType(ht, op === :ref_cast_null))
        end
    elseif op === :ref_i31
        pop_t!(b, op, I32)
        push_t!(b, RefType(:i31, false))
    elseif op in (:i31_get_s, :i31_get_u)
        pop_t!(b, op, RefType(:i31, true))
        push_t!(b, I32)
    elseif op === :any_convert_extern
        t = pop_ref!(b, op)
        push_t!(b, RefType(:any, t === nothing || t.nullable))
    elseif op === :extern_convert_any
        t = pop_ref!(b, op)
        push_t!(b, RefType(:extern, t === nothing || t.nullable))
    elseif op === :struct_new
        t = imms[1]; expect_struct(b, op, t)
        pop_ts!(b, op, [unpacked(f.storage) for f in field_types(b, t)])
        push_t!(b, RefType(t, false))
    elseif op === :struct_new_default
        t = imms[1]; expect_struct(b, op, t)
        all(f -> f.storage isa PackedType || defaultable(f.storage), field_types(b, t)) ||
            verr(b, op, "struct with non-defaultable fields")
        push_t!(b, RefType(t, false))
    elseif op in (:struct_get, :struct_get_s, :struct_get_u)
        t, i = imms; expect_struct(b, op, t)
        fs = field_types(b, t)
        0 <= i < length(fs) || verr(b, op, "no field $i in $t")
        check_field_read(b, op, fs[i+1])
        pop_t!(b, op, RefType(t, true))
        push_t!(b, unpacked(fs[i+1].storage))
    elseif op === :struct_set
        t, i = imms; expect_struct(b, op, t)
        fs = field_types(b, t)
        0 <= i < length(fs) || verr(b, op, "no field $i in $t")
        fs[i+1].mutable || verr(b, op, "field $i of $t is immutable")
        pop_t!(b, op, unpacked(fs[i+1].storage))
        pop_t!(b, op, RefType(t, true))
    elseif op === :array_new
        t = imms[1]; expect_array(b, op, t)
        pop_t!(b, op, I32)
        pop_t!(b, op, unpacked(array_elem(b, t).storage))
        push_t!(b, RefType(t, false))
    elseif op === :array_new_default
        t = imms[1]; expect_array(b, op, t)
        pop_t!(b, op, I32)
        push_t!(b, RefType(t, false))
    elseif op === :array_new_fixed
        t, n = imms; expect_array(b, op, t)
        et = unpacked(array_elem(b, t).storage)
        for _ in 1:n
            pop_t!(b, op, et)
        end
        push_t!(b, RefType(t, false))
    elseif op === :array_new_data
        t, d = imms; expect_array(b, op, t)
        array_elem(b, t).storage isa NumType || array_elem(b, t).storage isa PackedType ||
            verr(b, op, "array.new_data of a reference array")
        0 <= d < length(m.datas) || verr(b, op, "no data segment $d")
        pop_t!(b, op, I32); pop_t!(b, op, I32)
        push_t!(b, RefType(t, false))
    elseif op in (:array_get, :array_get_s, :array_get_u)
        t = imms[1]; expect_array(b, op, t)
        f = array_elem(b, t)
        check_field_read(b, op, f)
        pop_t!(b, op, I32)
        pop_t!(b, op, RefType(t, true))
        push_t!(b, unpacked(f.storage))
    elseif op === :array_set
        t = imms[1]; expect_array(b, op, t)
        f = array_elem(b, t)
        f.mutable || verr(b, op, "array $t is immutable")
        pop_t!(b, op, unpacked(f.storage))
        pop_t!(b, op, I32)
        pop_t!(b, op, RefType(t, true))
    elseif op === :array_len
        pop_t!(b, op, RefType(:array, true))
        push_t!(b, I32)
    elseif op === :array_fill
        t = imms[1]; expect_array(b, op, t)
        f = array_elem(b, t)
        f.mutable || verr(b, op, "array $t is immutable")
        pop_t!(b, op, I32)
        pop_t!(b, op, unpacked(f.storage))
        pop_t!(b, op, I32)
        pop_t!(b, op, RefType(t, true))
    elseif op === :array_copy
        t1, t2 = imms; expect_array(b, op, t1); expect_array(b, op, t2)
        array_elem(b, t1).mutable || verr(b, op, "array $t1 is immutable")
        subtype(m, unpacked(array_elem(b, t2).storage), unpacked(array_elem(b, t1).storage)) ||
            verr(b, op, "array.copy between incompatible arrays $t1 and $t2")
        pop_t!(b, op, I32); pop_t!(b, op, I32)
        pop_t!(b, op, RefType(t2, true))
        pop_t!(b, op, I32)
        pop_t!(b, op, RefType(t1, true))
    elseif op === :array_init_data
        t, d = imms; expect_array(b, op, t)
        pop_t!(b, op, I32); pop_t!(b, op, I32); pop_t!(b, op, I32)
        pop_t!(b, op, RefType(t, true))
    else
        verr(b, op, "unknown instruction (or a control instruction: use its function)")
    end
    return
end

# without validation, only track the pushed types (best effort, for speed)
typecheck_push!(b::Builder, op::Symbol, imms) = typecheck!(b, op, imms)
