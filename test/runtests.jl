using Test, WasmBuilder

function node_run(bytes, js)
    dir = mktempdir()
    write(joinpath(dir, "m.wasm"), bytes)
    script = """
    const fs = require('fs');
    const bytes = fs.readFileSync('$(joinpath(dir, "m.wasm"))');
    WebAssembly.instantiate(bytes, {}).then(({instance}) => { const e = instance.exports; $js });
    """
    write(joinpath(dir, "run.js"), script)
    return strip(read(`node $(joinpath(dir, "run.js"))`, String))
end

@testset "WasmBuilder" begin
    m = WModule()
    # a struct {i32 tag; mut f64 x} and a subtype adding an i64
    base = add_type!(m, StructType([FieldType(I32, false)]); final=false)
    pt = add_type!(m, StructType([FieldType(I32, false), FieldType(F64, true)]); final=false, super=base)
    arr = add_type!(m, ArrayType(FieldType(F64, true)))

    # factorial with a loop: block { loop { br_if exit; ...; br loop } }
    f = add_func!(m, "fact", ValType[I64], ValType[I64])
    acc = add_local!(f, I64)
    b = Builder(m, f)
    emit!(b, :i64_const, 1); emit!(b, :local_set, acc)
    block!(b)
    loop!(b)
    emit!(b, :local_get, 0); emit!(b, :i64_const, 1); emit!(b, :i64_le_s); br_if!(b, 1)
    emit!(b, :local_get, acc); emit!(b, :local_get, 0); emit!(b, :i64_mul); emit!(b, :local_set, acc)
    emit!(b, :local_get, 0); emit!(b, :i64_const, 1); emit!(b, :i64_sub); emit!(b, :local_set, 0)
    br!(b, 0)
    end!(b)
    end!(b)
    emit!(b, :local_get, acc)
    finish!(b)
    add_export!(m, "fact", f)

    # struct and array round trip: sum of an array of n copies of x, stored through a struct
    g = add_func!(m, "sumfill", ValType[F64, I32], ValType[F64])
    s = add_local!(g, RefType(pt))
    a = add_local!(g, RefType(arr))
    i = add_local!(g, I32)
    acc2 = add_local!(g, F64)
    b = Builder(m, g)
    emit!(b, :i32_const, 7); emit!(b, :local_get, 0); emit!(b, :struct_new, pt); emit!(b, :local_set, s)
    emit!(b, :local_get, s); emit!(b, :struct_get, pt, 1); emit!(b, :local_get, 1); emit!(b, :array_new, arr)
    emit!(b, :local_set, a)
    block!(b); loop!(b)
    emit!(b, :local_get, i); emit!(b, :local_get, a); emit!(b, :array_len); emit!(b, :i32_ge_u); br_if!(b, 1)
    emit!(b, :local_get, acc2); emit!(b, :local_get, a); emit!(b, :local_get, i); emit!(b, :array_get, arr)
    emit!(b, :f64_add); emit!(b, :local_set, acc2)
    emit!(b, :local_get, i); emit!(b, :i32_const, 1); emit!(b, :i32_add); emit!(b, :local_set, i)
    br!(b, 0); end!(b); end!(b)
    # upcast and test
    emit!(b, :local_get, s); emit!(b, :ref_test, pt)
    if!(b, F64)
    emit!(b, :local_get, acc2)
    else!(b)
    emit!(b, :f64_const, -1.0)
    end!(b)
    finish!(b)
    add_export!(m, "sumfill", g)

    bytes = to_bytes(m)
    @test validate(bytes)
    @test node_run(bytes, "console.log(e.fact(20n).toString(), e.sumfill(1.5, 4))") == "2432902008176640000 6"
    @test occursin("struct.new", sprint(print_wat, m))

    # validation errors at emission
    h = add_func!(m, "bad", ValType[I32], ValType[F64])
    b = Builder(m, h)
    @test_throws WasmValidationError emit!(b, :f64_add)
    emit!(b, :local_get, 0)
    @test_throws WasmValidationError emit!(b, :f64_neg)
    b = Builder(m, h)
    emit!(b, :local_get, 0)
    @test_throws WasmValidationError finish!(b)
    b = Builder(m, h)
    emit!(b, :i32_const, 0); emit!(b, :local_get, 0); 
    @test_throws WasmValidationError emit!(b, :struct_set, pt, 1)
    b = Builder(m, h)
    unreachable!(b)
    emit!(b, :f64_add)   # polymorphic stack
    finish!(b)
end
