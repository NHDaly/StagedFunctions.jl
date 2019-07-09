module Generated265 #end
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
@assert g(1) == 3
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

    reflection = Cassette.reflect((typeof(f), t...))
    ci = reflection.code_info
    ge = Expr(:lambda, ci.slotnames, scoped)
    l = Meta.lower(m, ge)
    ci.code = l.code
    # TODO this requires modifications to Julia to expose jl_resolve_globals_in_ir
    ccall(:jl_resolve_globals_in    _ir, Cvoid, (Any, Any, Any), ci.code, @__MODULE__,
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

@assert g(1) == 10 # SUCCESS

generatorbody(x) = :(2+$(f(x)))
g(1)



# ----------------
# -- Now do this automatically!
# ----------------

using MacroTools


collectcalls(v, out = []) = out
function collectcalls(e::Expr, out = Any[])
    if e.head == :call
        push!(out, e)
        for a in e.args
            collectcalls(a, out)
        end
    elseif e.head == :quote
        return out
    else
        for a in e.args
            collectcalls(a, out)
        end
    end
    out
end

# TEST
macro quoted(e) QuoteNode(e) end
collectcalls(:(a(x) + b(x)))
collectcalls(@quoted :(x + $(f(x))) )
@assert length( collectcalls(:(a(x) + b(x))) ) == 3

function call_expr_to_methodinstance_expr(e)
    argtypes = [:(typeof($a)) for a in e.args[2:end]]
    :(Cthulhu.first_method_instance($(e.args[1]), ($(argtypes...),)))
end
call_expr_to_methodinstance_expr(:(a(x) + b(x)))


function _make_generator(f)
    global e = f
    signature = f.args[1]
    (fname, fargs) = signature.args[1], signature.args[2:end]
    body = f.args[2]

    # Collect all calls in f
    calls = collectcalls(body)

    methodinstances = [call_expr_to_methodinstance_expr(c) for c in calls]


    # Update f to be the generatorbody
    generatorbodyname = signature.args[1] = :generatorbody
    f_generator = #=gensym(=# Symbol("$(fname)_generator")
    esc(:(
        $f;
        function $f_generator(self, $(fargs...))
            expr = Core._apply_pure($generatorbodyname, ($(fargs...),))
            Core.println(expr)
            # TODO switch back to expr_to_codeinfo
            #mi = Cthulhu.first_method_instance($generatorbodyname, (x,))
            #code_info = Core.Compiler.retrieve_code_info(mi)
            code_info = expr_to_codeinfo(@__MODULE__, $generatorbodyname, ($(fargs...),), expr)

            # Add edge to `f` since generatorbody calls `f`.
            # TODO: why isn't it enough to pass generatorbody?:
            #code_info.edges = [Cthulhu.first_method_instance($generatorbodyname, ($(fargs...),))]

            # For now, manually construct an edge for every function that f calls, by
            # collecting them from the expression tree (EWWW....)
            code_info.edges = [Cthulhu.first_method_instance($generatorbodyname, ($(fargs...),)),
                              $(methodinstances...)
                               ]
            Core.println(code_info.edges)
            code_info
        end;
        function $fname($(fargs...))
            $(Expr(:meta, :generated_only))
            $(Expr(:meta,
                :generated,
                Expr(:new,
                    Core.GeneratedFunctionStub,
                    f_generator,
                    Any[fname, fargs...],
                    Any[],  # spnames
                    @__LINE__,
                    QuoteNode(Symbol(@__FILE__)),
                    true)))
        end
    ))
end

macro generated265(f)
    @assert isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f)) "invalid syntax; @generated265 must be used with a function definition"

    _make_generator(f)
end

@macroexpand @generated265 function g(x)  :(x + $(f(x)))  end
@generated265 function g2(x)
      v = f(x)
      Expr(:call, :+, :x, v)
end

f(x) = 2
@assert g2(1)  == 3
f(x) = 6
@assert g2(1)  == 7

f(x) = bar(x)
bar(x) = 1
@assert g2(1)  == 2
bar(x) = 3
@assert g2(1)  == 4



end # module
