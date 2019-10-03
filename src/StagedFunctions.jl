module StagedFunctions # end

export @staged

@assert VERSION >= v"1.3.0-DEV.379"
# TODO: THIS MUST BE BUILT WITH A MODIFIED VERSION OF JULIA TO EXPORT A NEEDED FUNCTION.
# YOU CAN CHECKOUT AND BUILD FROM THIS BRANCH:
#    https://github.com/NHDaly/julia/tree/export_jl_resolve_globals_in_ir

import Cassette # To recursively track _ALL FUNCTIONS CALLED_ while computing staged result.
import MacroTools

function expr_to_codeinfo(m, argnames, spnames, sp, e)
    lam = Expr(:lambda, argnames,
               Expr(Symbol("scope-block"),
                    Expr(:block,
                        Expr(:return,
                            Expr(:block,
                                e,
                            )))))
    ex = if spnames === nothing || isempty(spnames)
        lam
    else
        Expr(Symbol("with-static-parameters"), lam, spnames...)
    end
    #Core.println("ex: $ex")


    # Get the code-info for the generatorbody in order to use it for generating a dummy
    # code info object.
    ci = ccall(:jl_expand_and_resolve, Any, (Any, Any, Core.SimpleVector), ex, m, Core.svec(sp...))

    @assert ci isa Core.CodeInfo "Failed to compile @staged function. This might mean it contains a closure or comprehension?"

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
    if e.head == Symbol("::") || e.head == Symbol("<:")
        return length(e.args) == 2 ? (e.args[1]) : nothing
    elseif e.head == Symbol("...")
        return e.args[1]
    else
        throw(AssertionError("Expected valid argument expression (`x::T`, `T<:S`, `x...`). Got $e"))
    end
end

# ---------------------
# Set up Cassette for tracing generator execution

Cassette.@context TraceCtx

mutable struct Trace
    calls::Vector{Any}
    Trace() = new(Any[])
end

function Cassette.prehook(ctx::TraceCtx, f, args...)
    push!(ctx.metadata.calls, (f, Tuple{(type_arg(a) for a in args)...}))
    return nothing
end
# Skip Builtins, which can't be redefined so we don't need edges to them!
Cassette.prehook(ctx::TraceCtx, f::Core.Builtin, args...) = nothing
# Get typeof(arg) or Type{T} if arg is a Type. This keeps the method instances more precise.
type_arg(a) = typeof(a)
type_arg(::Type{T}) where {T} = Type{T}

function generate_and_trace(generatorbody, args)
    trace = Trace()
    expr = Cassette.overdub(TraceCtx(metadata = trace), () -> generatorbody(args...))
    expr, trace
end
# ---------------------

function _make_generator(__module__, f)
    def = MacroTools.splitdef(f)

    stripped_args = argnames(def[:args])
    stripped_whereparams = argnames(def[:whereparams])

    userbody = def[:body]

    def[:body] = quote
        # Note that this captures all the args and type params
        userfunc = () -> $userbody

        # Call the generatorbody at latest world-age, to avoid currently frozen world-age.
        expr, trace = Core._apply_pure($generate_and_trace, (userfunc, ()))
        #Core.println("expr: $expr")
        code_info = $expr_to_codeinfo($__module__,
                                      # Note that generated functions all take an extra arg
                                      # for the generator itself: `#self#`
                                      [Symbol("#self#"), $stripped_args...],
                                      $stripped_whereparams, ($(stripped_whereparams...),),
                                      expr)
        #Core.println("code_info: $code_info")

        code_info.edges = Core.MethodInstance[]
        failures = Any[]
        for (callf,callargs) in trace.calls
            # Skip DataType constructor which found its way in here somehow
            if callf == DataType continue end
            try
                push!(code_info.edges, Core.Compiler.method_instances(callf, callargs)[1])
            catch
                push!(failures, callargs)
                continue
            end
        end
        if !isempty(failures)
            Core.println("WARNING: Some edges could not be found:")
            Core.println(failures)
        end
        #Core.println("edges: $(code_info.edges)")

        code_info
    end
    f = MacroTools.combinedef(def)

    # Last, we modify f to _actually_ return its CodeInfo, instead of quoting it
    lowered_gen_f = Meta.lower(__module__, :(@generated $f))
    # Extract the CodeInfo return value out of the :($(Expr(:block, QuoteNode(%2)))
    method = [ex for ex in lowered_gen_f.args[1].code
                 if ex isa Expr && ex.head == :method][end-2]
    method.args[end].code[end-1] =
        method.args[end].code[end-1].args[end]

    return esc(:(
        $lowered_gen_f;
    ))
end

macro staged(f)
    @assert isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f)) "invalid syntax; @staged must be used with a function definition"

    _make_generator(__module__, f)
end

end # module
