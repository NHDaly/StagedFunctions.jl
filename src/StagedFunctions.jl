module StagedFunctions # end

export @staged

@assert VERSION >= v"1.3.0-DEV.379"
# TODO: THIS MUST BE BUILT WITH A MODIFIED VERSION OF JULIA TO EXPORT A NEEDED FUNCTION.
# YOU CAN CHECKOUT AND BUILD FROM THIS BRANCH:
#    https://github.com/NHDaly/julia/tree/export_jl_resolve_globals_in_ir

import Cassette # To recursively track _ALL FUNCTIONS CALLED_ while computing staged result.
import MacroTools

function expr_to_codeinfo(m, f, t, e)
    scoped = Expr(Symbol("scope-block"),
    Expr(:block,
        Expr(:return,
            Expr(:block,
                e,
            ))))

    # Get the code-info for the generatorbody in order to use it for generating a dummy
    # code info object.
    # NOTE: We're using the actual function signature of the expected staged_func, so it
    # matches what the user provided.
    function_sig = (typeof(f), t...)
    Core.println("function_sig: $function_sig")
    reflection = Cassette.reflect(function_sig)
    ci = reflection.code_info
    # Update the CodeInfo with our scoped expression from above.
    ge = Expr(:lambda, ci.slotnames, scoped)
    l = Meta.lower(m, ge)
    ci.code = l.code
    # TODO this requires modifications to Julia to expose jl_resolve_globals_in_ir
    ccall(:jl_resolve_globals_in_ir, Cvoid, (Any, Any, Any), ci.code, @__MODULE__,
            Core.svec(reflection.static_params...)
         )
    ci
end

# ---- Utilities -------
"""
    argnames(fsig.args[2:end])

Return an array of names or gensymed names for each argument in an args list:
```julia-repl
julia> argnames(:(f(x::Int, ::Float32, z)).args[2:end])
3-element Array{Any,1}:
 :x
 Symbol("##_1#413")
 :z
```
"""
argnames(args::Tuple) = argnames([args...])
function argnames(args::Array)
    tmpcount = 0
    out = []
    for a in args
        name = argname(a)
        if name == nothing
            tmpcount += 1
            name = gensym("_$tmpcount")
        end
        push!(out, name)
    end
    out
end
argname(x::Symbol) = (x)
function argname(e::Expr)
    @assert e.head == Symbol("::")  "Expected (x::T), Got $e"
    return length(e.args) == 2 ? (e.args[1]) : nothing
end

# ---------------------
# Set up Cassette for tracing generator execution

Cassette.@context TraceCtx

mutable struct Trace
    calls::Vector{Any}
    Trace() = new(Any[])
end

function Cassette.prehook(ctx::TraceCtx, args...)
    push!(ctx.metadata.calls, Tuple(typeof(a) for a in args))
    return nothing
end
# Skip Builtins, which can't be redefined so we don't need edges to them!
Cassette.prehook(ctx::TraceCtx, f::Core.Builtin, args...) = nothing


function generate_and_trace(generatorbody, args)
    trace = Trace()
    expr = Cassette.overdub(TraceCtx(metadata = trace), () -> generatorbody(args...))
    expr, trace
end
# ---------------------

function _make_generator(f)
    def = MacroTools.splitdef(f)

    fname = def[:name]
    stripped_args = argnames(def[:args])

    userbody = def[:body]

    fcopy_def = deepcopy(def)
    fcopy_def[:body] = nothing
    fcopy_def[:name] = gensym(fname)
    fcopy_for_codeinfo_def = MacroTools.combinedef(fcopy_def)


    def[:body] = quote
        # Note that this captures all the args and type params
        userfunc = () -> $userbody

        args = $stripped_args

        # Call the generatorbody at latest world-age, to avoid currently frozen world-age.
        expr, trace = Core._apply_pure($generate_and_trace, (userfunc, ()))
        Core.println(expr)
        code_info = $(@__MODULE__).expr_to_codeinfo(@__MODULE__, $(fcopy_def[:name]), ($(stripped_args...),), expr)
        Core.println(code_info)

        code_info.edges = Core.MethodInstance[]
        failures = Any[]
        for callargs in trace.calls
            # Skip DataType constructor which found its way in here somehow
            if callargs[1] == DataType continue end
            try
                push!(code_info.edges, Core.Compiler.method_instances(
                    callargs[1].instance, Tuple{(a for a in callargs[2:end])...})[1])
            catch
                push!(failures, callargs)
                continue
            end
        end
        if !isempty(failures)
            Core.println("WARNING: Some edges could not be found:")
            Core.println(failures)
        end

        code_info
    end
    f = MacroTools.combinedef(def)
    return esc(:(
        $fcopy_for_codeinfo_def;
        @generated $f;
    ))
end

macro staged(f)
    @assert isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f)) "invalid syntax; @staged must be used with a function definition"

    _make_generator(f)
end

end # module
