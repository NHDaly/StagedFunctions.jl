#module Generated265 #end

const dave = []
using InteractiveUtils
@assert VERSION >= v"1.3.0-DEV.379"
# TODO: THIS MUST BE BUILT WITH A MODIFIED VERSION OF JULIA TO EXPORT A NEEDED FUNCTION.
# YOU CAN CHECKOUT AND BUILD FROM THIS BRANCH:
#    https://github.com/NHDaly/julia/tree/export_jl_resolve_globals_in_ir

using Cthulhu
using Cassette # To share their 265 fixing code

import Main: @code_lowered

# ----------------
# -- Adding manual backedges to CodeInfo generator
# -----------------

_whee() = 2
_whee()
f(x) = :($(bar(x)))

function g_gen(self, x)
    mi = Cthulhu.first_method_instance(f, Tuple{Int})
    code_info = Core.Compiler.retrieve_code_info(mi)
    #code_info.edges = [mi]
    #code_info.edges = [Cthulhu.first_method_instance(_whee, Tuple{})]
    Core.println("HI")
    code_info
end
@eval function g(x)
    $(Expr(:meta, :generated_only))
    $(Expr(:meta,
        :generated,
        Expr(:new,
            Core.GeneratedFunctionStub,
            :g_gen,
            Any[:g, :x],
            Any[],  # spnames
            @__LINE__,
            QuoteNode(Symbol(@__FILE__)),
            true)))
end

bar(x) = 1
g(1)
bar(x) = 3
##@assert g(1) == 3
g(1)
_whee() = whaz()
whaz() = 1
g(1)
whaz() = 3
g(1)

ci = code_lowered(g, (Int,))[1]
@show ci.edges


# ----------------
# -- Turning generated expression into a codeinfo
# -----------------

f(x) = 1

function generatorbody(x)
    v = f(x)
    :(x + $v)
end


function expr_to_codeinfo(m, f, t, e)

    scoped = Expr(Symbol("scope-block"),
    Expr(:block,
        Expr(:return,
            Expr(:block,
                e,
            ))))

    #function_sig = (typeof(f), map(Core.Typeof, t)...)
    function_sig = (typeof(f), (Type for _ in t)...)
    Core.println("sig: ", function_sig)
    reflection = Cassette.reflect(function_sig)
    ci = reflection.code_info
    ge = Expr(:lambda, ci.slotnames, scoped)
    l = Meta.lower(m, ge)
    ci.code = l.code
    # TODO this requires modifications to Julia to expose jl_resolve_globals_in_ir
    ccall(:jl_resolve_globals_in_ir, Cvoid, (Any, Any, Any), ci.code, @__MODULE__,
            Core.svec(reflection.static_params...)
         )
    ci
end
ci = expr_to_codeinfo(@__MODULE__, generatorbody, (Int,), generatorbody(Int))
ci.slotnames
#println(ci.code)

function g_gen2(self, x)
    expr = Core._apply_pure(generatorbody,(x,))
    Core.println(expr)
    # TODO switch back to expr_to_codeinfo
    #mi = Cthulhu.first_method_instance(generatorbody, (x,))
    #code_info = Core.Compiler.retrieve_code_info(mi)
    # expr_to_codeinfo now sets the edges via Cassette.reflect
    code_info = expr_to_codeinfo(@__MODULE__, generatorbody, (x,), expr)

    # Add edge to `f` since generatorbody calls `f`.
    #code_info.edges = [Cthulhu.first_method_instance(f, (x,)),
    #                   Cthulhu.first_method_instance(generatorbody, (x,))]
    # TODO: why isn't it enough to pass generatorbody?:
    #code_info.edges = [Cthulhu.first_method_instance(generatorbody, (x,))]
    Core.println(code_info.edges)
    code_info
end
@eval function g(x)
    $(Expr(:meta, :generated_only))
    $(Expr(:meta,
        :generated,
        Expr(:new,
            Core.GeneratedFunctionStub,
            :g_gen2,
            Any[:g, :x],
            Any[],  # spnames
            @__LINE__,
            QuoteNode(Symbol(@__FILE__)),
            true)))
end

f(x) = 1
dump(Core.Compiler.retrieve_code_info(Cthulhu.first_method_instance(g, (Int,))))
ci = @code_lowered g(1)
ci.slotnames
g(1)

f(x) = 9

g(1)
generatorbody(Int)
Base.invokelatest(g,1)
Core._apply_pure(g,1)
@code_lowered g(1)

#@assert g(1) == 10 # SUCCESS

generatorbody(x) = :(2+$(f(x)))
g(1)



# ----------------
# -- Now do this automatically!
# ----------------

# ---- Utitlities -------
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

function _delete_prev_methods(f, t)
    ms = Base.methods(f, t).ms
    for m in ms
        if m.sig == Tuple{typeof(f), t...}
            Base.delete_method(m)
            return nothing
        end
    end
    return nothing
end

function _make_generator(f)
    global e = f
    signature = f.args[1]
    (fname, fargs) = signature.args[1], signature.args[2:end]

    # Strip type-assertions and gensymed missing names for all args
    # (x::Int, y, ::Float32) -> (x,y,##genarg##)
    signature.args = argnames(signature.args)

    # Update f to be the generatorbody
    generatorbodyname = signature.args[1] = gensym(:generatorbody)
    f_stager = gensym( Symbol("$(fname)_stager") )
    esc(:(
        $f;   # user-written generator body function
        function $f_stager(self, args...)
            # Within this function, args are types.

            Core.println("ARGS: ", args)
            #@isdefined($generatorbodyname) && $(@__MODULE__)._delete_prev_methods($generatorbodyname, (args...,));
            expr = Core._apply_pure($generatorbodyname, (args...,))
            Core.println(expr)
            # TODO switch back to expr_to_codeinfo
            #mi = Core.Compiler.method_instances($generatorbodyname, Tuple{x})[1]
            #code_info = Core.Compiler.retrieve_code_info(mi)
            code_info = expr_to_codeinfo(@__MODULE__, $generatorbodyname, (args...,), expr)

            Core.println("BEFORE")
            Core.println(code_info.edges)
            Core.println("AFTER")

              # # TODO: Cassette.reflect already adds an edge to (generatorbody, (Int64,)) (for generatorbody(::Type{Int}))
              # # TODO: Shouldn't it be typeof{Int}
              # # Add edge to `f` since generatorbody calls `f`.
               #push!(code_info.edges, Core.Compiler.method_instances($generatorbodyname, Tuple{map(Core.Typeof, args)...})[1])
               # TODO: DELETE THIS: Manaualy add edge to f
               #push!(code_info.edges, Core.Compiler.method_instances(f, Tuple{(Type for _ in args)...})[1])

            push!(dave, deepcopy(code_info))
            Core.println(code_info.edges)

            #code_info.edges = nothing
            code_info
        end;
        function $fname($(fargs...))   # staged function
            $(Expr(:meta, :generated_only))
            $(Expr(:meta,
                :generated,
                Expr(:new,
                    Core.GeneratedFunctionStub,
                    f_stager,
                    Any[fname, fargs...],
                    Any[],  # spnames
                    @__LINE__,
                    QuoteNode(Symbol(@__FILE__)),
                    true)))
        end
    ))
end

macro staged(f)
    @assert isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f)) "invalid syntax; @staged must be used with a function definition"

    _make_generator(f)
end

@macroexpand @staged function g(x)  :(x + $(f(x)))  end
@staged function g2(x)
      f(x)
end


f(x) = 1
f(1)
g2(1)
f(x) = 2
g2(1)


bar(x) = 4
f(x) = bar(x)
f(2)
g2(1)
bar(x) = 3
f(2)
g2(1)

@generated g_norm(x) = :(x + $(f(x)))
Cassette.@context Ctx;
Cassette.overdub(Ctx(), g_norm, 1)
bar(x) = 5
Cassette.overdub(Ctx(), g_norm, 1)

@staged function g3(x::Int)
      v = f(x)
      :(x + $v)
end


g3(1)
g3(1)
f(x) = 3
g3(1)
f(x) = 8
@code_typed g3(1)


#end # module
