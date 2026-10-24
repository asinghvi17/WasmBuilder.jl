# A WebAssembly module under construction: its types, functions (with their bodies as
# lists of instructions), globals, tags, data segments and exports. Function and global
# indices are assigned when the module is written, so that imports and definitions can
# be added in any order.

"""
    Inst(op, imms...)

An instruction: its name (as in the text format, with `.` replaced by `_`) and its
immediates. Function, global and tag immediates are the objects themselves, resolved to
indices when the module is written.
"""
struct Inst
    op::Symbol
    imm::Tuple
end
Inst(op::Symbol, imm...) = Inst(op, imm)

"""
    Func

A function of a module, imported (`imported` is `(module, name)`) or defined, with its
type, locals beyond the parameters, and body.
"""
mutable struct Func
    idx::Int
    name::String
    type::TypeRef
    params::Vector{ValType}
    results::Vector{ValType}
    locals::Vector{ValType}
    body::Vector{Inst}
    imported::Union{Nothing,Tuple{String,String}}
end

"A global of a module: its type, mutability and constant initializer."
mutable struct Global
    idx::Int
    name::String
    type::ValType
    mutable::Bool
    init::Vector{Inst}
end

"An exception tag, with the function type of its payload."
mutable struct Tag
    idx::Int
    type::TypeRef
end

"The linear memory of a module (only one): its limits in 64 KiB pages."
mutable struct Memory
    min::Int
    max::Union{Nothing,Int}
    imported::Union{Nothing,Tuple{String,String}}
end

Memory(min::Integer, max::Union{Nothing,Integer}=nothing) = Memory(min, max, nothing)

"A data segment: bytes and an optional active offset expression in memory 0."
struct DataSegment
    bytes::Vector{UInt8}
    offset::Union{Nothing,Vector{Inst}}
end

"""
    WModule(; relaxed_simd=false)

A WebAssembly module under construction. All its types are defined in one recursion
group, so that types with the same structure are distinct (nominal), which the code
generator relies on to test for the Julia type of a value. Set `relaxed_simd=true` to
enable relaxed SIMD instructions.
"""
mutable struct WModule
    types::Vector{SubType}
    functypes::Dict{Tuple{Vector{ValType},Vector{ValType}},TypeRef}
    funcs::Vector{Func}
    globals::Vector{Global}
    tags::Vector{Tag}
    datas::Vector{DataSegment}
    exports::Vector{Tuple{String,Any}}
    start::Union{Nothing,Func}
    "The functions referenced by `ref.func`, which must be declared."
    declared::Vector{Func}
    declared_set::Set{Func}
    memory::Union{Nothing,Memory}
    relaxed_simd::Bool
end

WModule(; relaxed_simd::Bool=false) =
    WModule(SubType[], Dict{Tuple{Vector{ValType},Vector{ValType}},TypeRef}(),
            Func[], Global[], Tag[], DataSegment[], Tuple{String,Any}[], nothing,
            Func[], Set{Func}(), nothing, relaxed_simd)

"Add the type definition `t`, returning a reference to it."
function add_type!(m::WModule, t::SubType)
    push!(m.types, t)
    return TypeRef(length(m.types) - 1)
end
add_type!(m::WModule, t::CompType; kw...) = add_type!(m, SubType(t; kw...))

"The type definition of `t`."
typedef(m::WModule, t::TypeRef) = m.types[t.idx+1]

"The (deduplicated) function type with `params` and `results`."
function functype!(m::WModule, params::Vector{ValType}, results::Vector{ValType})
    t = get(m.functypes, (params, results), nothing)
    t === nothing || return t
    # copies, so that the caller mutating its vectors does not change the key
    return m.functypes[(copy(params), copy(results))] =
        add_type!(m, FuncType(copy(params), copy(results)))
end

"Declare a function of the module named `name`, with an empty body."
function add_func!(m::WModule, name::AbstractString, params::Vector{ValType},
                   results::Vector{ValType})
    f = Func(-1, String(name), functype!(m, params, results), params, results, ValType[],
             Inst[], nothing)
    push!(m.funcs, f)
    return f
end

"""
Import a function `mod.name` with `params` and `results`. Importing the same name with
the same signature again returns the same function; with another signature, a distinct
import (a JavaScript host function can be imported at several types).
"""
function add_import!(m::WModule, mod::AbstractString, name::AbstractString,
                     params::Vector{ValType}, results::Vector{ValType})
    type = functype!(m, params, results)
    for f in m.funcs
        f.imported == (mod, name) && f.type == type && return f
    end
    f = Func(-1, String(name), type, params, results, ValType[],
             Inst[], (String(mod), String(name)))
    push!(m.funcs, f)
    return f
end

"Add a global with the initializer `init` (constant instructions)."
function add_global!(m::WModule, name::AbstractString, type::ValType, mutable::Bool,
                     init::Vector{Inst})
    g = Global(-1, String(name), type, mutable, init)
    push!(m.globals, g)
    g.idx = length(m.globals) - 1   # globals are never imported, so indices are final
    return g
end

"Add a tag whose payload has the types `params`."
function add_tag!(m::WModule, params::Vector{ValType})
    t = Tag(length(m.tags), functype!(m, params, ValType[]))
    push!(m.tags, t)
    return t
end

"""
    add_data!(m, bytes; offset=nothing)

Add a data segment, returning its index. With `offset=nothing` it is passive; an
integer byte offset or an `Inst` vector makes it active in memory 0.
"""
function add_data!(m::WModule, bytes::Vector{UInt8}; offset=nothing)
    init = offset isa Integer ? Inst[Inst(:i32_const, offset)] : offset
    init isa Union{Nothing,Vector{Inst}} || throw(ArgumentError("invalid data offset"))
    push!(m.datas, DataSegment(copy(bytes), init))
    return length(m.datas) - 1
end

"Give the module its linear memory, of `min` (and at most `max`) 64 KiB pages."
function add_memory!(m::WModule, min::Integer, max::Union{Nothing,Integer}=nothing)
    return add_memory!(m, Memory(min, max))
end

function add_memory!(m::WModule, mem::Memory)
    m.memory === nothing || throw(ArgumentError("the module already has a memory"))
    valid_limits(mem) || throw(ArgumentError("memory limits must satisfy 0 ≤ min ≤ max ≤ 65536"))
    return m.memory = mem
end

valid_limits(mem::Memory) = 0 <= mem.min <= 65536 &&
    (mem.max === nothing || mem.min <= mem.max <= 65536)

"Import `mod.name` as the module's memory with the limits of `mem`."
function add_import!(m::WModule, mod::AbstractString, name::AbstractString, mem::Memory)
    return add_memory!(m, Memory(mem.min, mem.max, (String(mod), String(name))))
end

"Export `item` (a `Func`, `Global`, `Tag` or the `Memory`) as `name`."
add_export!(m::WModule, name::AbstractString, item) = push!(m.exports, (String(name), item))

"Declare `f` as referenced by `ref.func`."
function declare!(m::WModule, f::Func)
    f in m.declared_set && return
    push!(m.declared_set, f)
    push!(m.declared, f)
end

"Add a local of type `t` to the function `f`, returning its index."
function add_local!(f::Func, t::ValType)
    push!(f.locals, t)
    return length(f.params) + length(f.locals) - 1
end

"The type of the local `i` of `f`."
local_type(f::Func, i::Int) = i < length(f.params) ? f.params[i+1] : f.locals[i-length(f.params)+1]

# assign the function indices: imports first, as the index space requires
function assign_indices!(m::WModule)
    i = 0
    for f in m.funcs
        f.imported === nothing && continue
        f.idx = i
        i += 1
    end
    for f in m.funcs
        f.imported === nothing || continue
        f.idx = i
        i += 1
    end
    return m
end
