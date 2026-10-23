# External tools: validation with `wasm-tools` and optimization with Binaryen's `wasm-opt`.

"The `wasm-tools` executable, if there is one (`WASM_TOOLS` overrides the search)."
function wasm_tools()
    p = get(ENV, "WASM_TOOLS", "")
    isempty(p) || return p
    p = Sys.which("wasm-tools")
    p === nothing || return p
    p = joinpath(homedir(), ".cargo", "bin", "wasm-tools")
    return isfile(p) ? p : nothing
end

"""
    validate(bytes) -> Bool

Validate a binary module with `wasm-tools validate`, throwing an error with its message
if it is invalid. Returns `false` (without validating) when `wasm-tools` is not found.
"""
function validate(bytes::Vector{UInt8})
    exe = wasm_tools()
    exe === nothing && return false
    mktempdir() do dir
        path = joinpath(dir, "module.wasm")
        write(path, bytes)
        err = IOBuffer()
        ok = success(pipeline(`$exe validate --features=all $path`; stderr=err))
        ok || error("invalid module:\n", String(take!(err)))
    end
    return true
end

"""
    disassemble(bytes) -> String

The text format of a binary module, from `wasm-tools print`.
"""
function disassemble(bytes::Vector{UInt8})
    exe = wasm_tools()
    exe === nothing && error("wasm-tools not found")
    mktempdir() do dir
        path = joinpath(dir, "module.wasm")
        write(path, bytes)
        read(`$exe print $path`, String)
    end
end
