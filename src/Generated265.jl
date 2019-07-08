module Generated265
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

f(x) = bar(x)

_ci = Core.Compiler.retrieve_code_info(Cthulhu.first_method_instance(f, Tuple{Int}))

function g_gen(self, x)
    mi = Cthulhu.first_method_instance(f, Tuple{Int})
    code_info = Core.Compiler.retrieve_code_info(mi)
    code_info.edges = [mi]
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
g(1)

# ----------------
# -- Turning generated expression into a codeinfo
# -----------------

f(x) = 1

function generatorbody(x)
    v = f(x)
    :(x + $v)
end

expr_to_codeinfo(m, e) = Meta.lower(m, e).args[1]
ci = expr_to_codeinfo(@__MODULE__, :(x+1))
ccall(:jl_resolve_globals_in_ir, Cvoid, (Any, Any, Any), ci.code, @__MODULE__,
     Core.svec(),  # TODO: THIS SHOULD BE THE TYPE PARAMETER SPECIALIZATIONS
     )
#ci = code_lowered(x->x+1, (Int,))[1]
ci.slotnames
function expr_to_codeinfo(m, f, t, e)

    scoped = Expr(Symbol("scope-block"),
    Expr(:block,
        Expr(:return,
            Expr(:block,
                e,
            ))))

    mi = Cthulhu.first_method_instance(f, t)
    ci = copy(Core.Compiler.retrieve_code_info(mi))
    ge = Expr(:lambda, ci.slotnames, scoped)
    l = Meta.lower(m, ge)
    ci.code = l.code
    # TODO this requires modifications to Julia to expose jl_resolve_globals_in_ir
    ccall(:jl_resolve_globals_in_ir, Cvoid, (Any, Any, Any), ci.code, @__MODULE__,
         Core.svec(:x),  # TODO: THIS SHOULD BE THE TYPE PARAMETER SPECIALIZATIONS
         )
    ci
end
ci = expr_to_codeinfo(@__MODULE__, generatorbody, (Int,), generatorbody(Int))
ci.slotnames
#println(ci.code)

function g_gen(self, x)
    expr = Core._apply_pure(generatorbody,(x,))
    Core.println(expr)
    code_info = expr_to_codeinfo(@__MODULE__, generatorbody, (x,), expr)
    # Add edge to `f` since generatorbody calls `f`.
    code_info.edges = [Cthulhu.first_method_instance(f, (x,)),
                       Cthulhu.first_method_instance(generatorbody, (x,))]
    # TODO: why isn't it enough to pass generatorbody?:
        # code_info.edges = [Cthulhu.first_method_instance(generatorbody, (x,))]
   code_info.edges = [Cthulhu.first_method_instance(foo, ())]
   Core.println(code_info.edges)
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

f(x) = 1
foo() = bar()
dump(Core.Compiler.retrieve_code_info(Cthulhu.first_method_instance(g, (Int,))))
ci = @code_lowered g(1)
ci.slotnames
g(1)

f(x) = 9

generatorbody(Int)

g(1)

bar() = 3
g(1)
@assert g(1) == 10 # SUCCESS

foo() = bar()
@assert g(1) == 10 # SUCCESS



# ----------------
# -- Now do this automatically!
# ----------------

using MacroTools


macro mygenerated(f)
    @show f
end



end # module
