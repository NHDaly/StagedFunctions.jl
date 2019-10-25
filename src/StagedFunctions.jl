module StagedFunctions # end

export @staged

@assert VERSION >= v"1.4.0-DEV.249" "This package reqiures a Julia version >= v\"1.4.0-DEV.249\", or later than 2019-10-03."

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
# Use the Julia modifications introduced in
# https://github.com/JuliaLang/julia/compare/master...NHDaly:nhdaly-track-dynamic-dispatches
# to track the MethodInstances of all dynamic dispatches that occur while executing generatorbody(args...)
# NOTE: This function is the MAIN INTERESTING PART of this package! Here we collect all the
# functions that are dispatched-to during execution of the generatorbody (importantly,
# including the generatorbody itself), and we set backedges from all of them to the generated function.
# NOTE also that we only need to capture _dynamic dispatches_, since regular back-edges are
# sufficient to cover all other methods being updated.
function generate_and_trace(@nospecialize(generatorbody))
    ccall(:jl_start_tracking_dispatches, Cint, ())
    expr = generatorbody()
    trace = ccall(:jl_finish_tracking_dispatches, Vector{Any}, ())
    (expr, trace)
end
# ---------------------

function _make_generator(__module__, f)
    def = MacroTools.splitdef(f)

    stripped_args = argnames(def[:args])
    stripped_whereparams = argnames(def[:whereparams])

    # Extract the user's function body, and have our generated function use it to compute
    # the result, setting edges to the functions invoked to compute it.
    userbody = def[:body]

    def[:body] = quote
        # Note that this captures all the args and type params
        userfunc = () -> $userbody

        # Call the generatorbody at latest world-age, to avoid currently frozen world-age.
        expr, trace = Core._apply_pure($generate_and_trace, (userfunc,))
        #Core.println("expr: $expr")
        code_info = $expr_to_codeinfo($__module__,
                                      # Note that generated functions all take an extra arg
                                      # for the generator itself: `#self#`
                                      [Symbol("#self#"), $stripped_args...],
                                      $stripped_whereparams, ($(stripped_whereparams...),),
                                      expr)
        #Core.println("code_info: $code_info")

        # NOTE: This is the other interesting part of this package! Here we set the edges
        # of the returned code_info, which ultimately leads Julia to generate a new function
        # and set backdges from all the method specializations in the trace back to it, so
        # that if any of them change, this generated function will be updated as well!
        code_info.edges = Core.MethodInstance[trace...]
        #Core.println("edges: $(code_info.edges)")

        # NOTE: The "return" here is very important! Apparently this is a bit of syntax that
        # julia is very sensitive to: Apparently the code-lowering for generated functions
        # wraps _final expressions_ in an `Expr(:block, ...)` quote, but _doesn't_ do that
        # for _`return` expressions_. So if this line was `code_info` instead of `return
        # code_info`, this would produce a generated function that returns a CodeInfo.
        # Instead, _with_ the `return` here, Julia uses the returned CodeInfo we've
        # constructd to create the generated function, so we get a function based on the
        # user's provided code like we want.
        return code_info
    end

    f = MacroTools.combinedef(def)
    f = :(@generated $f)

    return esc(f)
end

macro staged(f)
    @assert isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f)) "invalid syntax; @staged must be used with a function definition"

    _make_generator(__module__, f)
end

end # module
