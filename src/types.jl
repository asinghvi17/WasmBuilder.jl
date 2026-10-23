# The WebAssembly types of a module: value types, the composite types of the GC proposal
# (functions, structs, arrays) and the subtyping declarations that define them.

"A numeric value type."
@enum NumType::UInt8 I32 = 0x7f I64 = 0x7e F32 = 0x7d F64 = 0x7c V128 = 0x7b

"""
    HeapType

A heap type: one of the abstract ones (`:any`, `:eq`, `:i31`, `:struct`, `:array`,
`:none`, `:func`, `:nofunc`, `:extern`, `:noextern`, `:exn`, `:noexn`), or a defined type
of the module (a [`TypeRef`](@ref)).
"""
const ABSTRACT_HEAPTYPES = Dict{Symbol,UInt8}(
    :nofunc => 0x73, :noextern => 0x72, :none => 0x71, :func => 0x70, :extern => 0x6f,
    :any => 0x6e, :eq => 0x6d, :i31 => 0x6c, :struct => 0x6b, :array => 0x6a,
    :exn => 0x69, :noexn => 0x74)

"""
    TypeRef

A defined type of a module, by its index in the module's type section (0-based).
"""
struct TypeRef
    idx::Int
end

const HeapType = Union{Symbol,TypeRef}

"""
    RefType(heap; nullable=true)

A reference type, `(ref null? heap)`.
"""
struct RefType
    heap::HeapType
    nullable::Bool
end
RefType(heap::HeapType; nullable::Bool=true) = RefType(heap, nullable)

const ValType = Union{NumType,RefType}

"A packed storage type, only for fields of structs and arrays."
@enum PackedType::UInt8 I8 = 0x78 I16 = 0x77

const StorageType = Union{ValType,PackedType}

"The type of a field of a struct or the elements of an array."
struct FieldType
    storage::StorageType
    mutable::Bool
end

struct FuncType
    params::Vector{ValType}
    results::Vector{ValType}
end

struct StructType
    fields::Vector{FieldType}
end

struct ArrayType
    elem::FieldType
end

const CompType = Union{FuncType,StructType,ArrayType}

"""
    SubType(comp; final=true, super=nothing)

A type definition: a composite type, final or not (whether it can have subtypes), with
its declared supertype.
"""
struct SubType
    comp::CompType
    final::Bool
    super::Union{Nothing,TypeRef}
end
SubType(comp::CompType; final::Bool=true, super::Union{Nothing,TypeRef}=nothing) =
    SubType(comp, final, super)

# the value type of the storage type of a field when it is read (packed types widen)
unpacked(t::PackedType) = I32
unpacked(t::ValType) = t

is_ref(t) = t isa RefType
is_num(t) = t isa NumType

# whether values of the type have a default value (zero or null), which locals need
defaultable(t::NumType) = true
defaultable(t::RefType) = t.nullable

Base.show(io::IO, t::TypeRef) = print(io, "\$", t.idx)
function Base.show(io::IO, t::RefType)
    print(io, "(ref ", t.nullable ? "null " : "")
    t.heap isa Symbol ? print(io, t.heap) : show(io, t.heap)
    print(io, ")")
end
Base.show(io::IO, t::NumType) = print(io, lowercase(string(Symbol(t))))
