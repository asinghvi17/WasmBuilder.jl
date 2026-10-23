# Subtyping between the value types of a module (the GC proposal's rules).

"""
    heap_subtype(m, a, b) -> Bool

Whether the heap type `a` is a subtype of `b` in the module `m`.
"""
function heap_subtype(m::WModule, a::HeapType, b::HeapType)
    a == b && return true
    if a isa TypeRef
        t = typedef(m, a)
        if b isa TypeRef
            s = t.super
            while s !== nothing
                s == b && return true
                s = typedef(m, s).super
            end
            return false
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
