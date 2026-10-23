# Subtyping between the value types of a module (the GC proposal's rules).

# `:bot` is the heap type of an unknown reference operand in unreachable code (the
# validation algorithm's `Ref(Bot, false)`): a subtype of every heap type, never encoded.

"""
    heap_subtype(m, a, b) -> Bool

Whether the heap type `a` is a subtype of `b` in the module `m`.
"""
function heap_subtype(m::WModule, a::HeapType, b::HeapType)
    a == b && return true
    a === :bot && return true
    if a isa TypeRef
        t = typedef(m, a)
        if b isa TypeRef
            # declared supertypes have smaller indices (`verify` checks it): stopping
            # otherwise terminates on invalid declarations
            s = a
            while true
                sup = typedef(m, s).super
                (sup === nothing || !(0 <= sup.idx < s.idx)) && return false
                sup == b && return true
                s = sup
            end
        end
        c = t.comp
        c isa FuncType && return b === :func
        c isa StructType && return b === :struct || b === :eq || b === :any
        c isa ArrayType && return b === :array || b === :eq || b === :any
        return false
    end
    if b isa TypeRef
        c = typedef(m, b).comp
        a === :none && return !(c isa FuncType)
        a === :nofunc && return c isa FuncType
        return false
    end
    a === :none && return b in (:i31, :struct, :array, :eq, :any)
    a in (:i31, :struct, :array) && return b === :eq || b === :any
    a === :eq && return b === :any
    a === :nofunc && return b === :func
    a === :noextern && return b === :extern
    a === :noexn && return b === :exn
    return false
end

"""
    subtype(m, a, b) -> Bool

Whether the value type `a` is a subtype of `b` in the module `m`.
"""
subtype(m::WModule, a::NumType, b::NumType) = a === b
subtype(m::WModule, a::NumType, b::RefType) = false
subtype(m::WModule, a::RefType, b::NumType) = false
subtype(m::WModule, a::RefType, b::RefType) =
    (!a.nullable || b.nullable) && heap_subtype(m, a.heap, b.heap)

subtypes(m::WModule, as, bs) =
    length(as) == length(bs) && all(subtype(m, a, b) for (a, b) in zip(as, bs))

# storage types: packed types match only themselves
storage_subtype(m::WModule, a::PackedType, b::PackedType) = a === b
storage_subtype(m::WModule, a::PackedType, b::ValType) = false
storage_subtype(m::WModule, a::ValType, b::PackedType) = false
storage_subtype(m::WModule, a::ValType, b::ValType) = subtype(m, a, b)

# mutable fields are invariant, immutable ones covariant
field_subtype(m::WModule, a::FieldType, b::FieldType) =
    a.mutable == b.mutable && storage_subtype(m, a.storage, b.storage) &&
    (!a.mutable || storage_subtype(m, b.storage, a.storage))

# whether the composite type `a` can be declared a subtype of `b`
comp_subtype(m::WModule, a::CompType, b::CompType) = false
comp_subtype(m::WModule, a::FuncType, b::FuncType) =
    subtypes(m, b.params, a.params) && subtypes(m, a.results, b.results)
comp_subtype(m::WModule, a::StructType, b::StructType) =
    length(a.fields) >= length(b.fields) &&
    all(field_subtype(m, fa, fb) for (fa, fb) in zip(a.fields, b.fields))
comp_subtype(m::WModule, a::ArrayType, b::ArrayType) = field_subtype(m, a.elem, b.elem)

"The top of the hierarchy of a heap type: `:any`, `:func`, `:extern` or `:exn`."
function heap_top(m::WModule, h::HeapType)
    if h isa TypeRef
        return typedef(m, h).comp isa FuncType ? :func : :any
    end
    h in (:func, :nofunc) && return :func
    h in (:extern, :noextern) && return :extern
    h in (:exn, :noexn) && return :exn
    return :any
end

valid_heap(m::WModule, h) =
    h isa Symbol ? haskey(ABSTRACT_HEAPTYPES, h) : h isa TypeRef && 0 <= h.idx < length(m.types)
valid_valtype(m::WModule, t) = t isa NumType || t isa RefType && valid_heap(m, t.heap)
valid_storage(m::WModule, t) = t isa PackedType || valid_valtype(m, t)
