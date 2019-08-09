module StagedFunctionsTest #end

using StagedFunctions

using Test
using InteractiveUtils


f(x) = 2
@macroexpand @staged lyndon(x) = f(x)
lyndon(2)
@staged nathan(x::T) where T = f(T)
lyndon(2)
struct X x end
@staged X(v) = :(v)
@staged X(v::T) where {T<:Int} = :(T)
X(1.0)
X(1)
@staged X(v::T, y::S) where {T,S} = :(println(v, y, $T); T)
X(X,1)

@staged sarah(x) = :(x+x)
sarah(2)


f(x) = 2
@generated g(x) = f(x)
f(x) = 6
g(1)

bar(x) = f(x)
bar(2)
@code_typed bar(2)


f(x) = 2
@staged lyndon(x) = f(x)

@test lyndon(3) == 2
f(x) = 3
@test lyndon(3) == 3
@code_typed lyndon(3)

@staged s2(x) = :(x*$(f(x)))
s2(10)



#  bodyf = getfield(@__MODULE__, Symbol("##generatorbody#443"))
#
#  Main.NHDalyUtils.func_all_specializations(lyndon)
#  Main.NHDalyUtils.func_all_specializations(bodyf)
#
#
#
#
#  lyndon(2)
#
#  Main.NHDalyUtils.func_all_specializations(lyndon)
#  Main.NHDalyUtils.func_all_specializations(bodyf)
#
#
#
#  f_mi = Core.Compiler.method_instances(f, Tuple{Type{Int}})[1]
#  f_mi.backedges
#
#
#  dave[end].edges
#  f(2)
#  f_mi.backedges
#
#  #nbits(::Type{T})
#  f(x) = nathan(x)
#  nathan(x) = 2
#  lyndon(1)
#  nathan(x::Type{Int}) = "Int"
#  nathan(x::Type{<:AbstractFloat}) = "Float"
#  lyndon(1)
#  lyndon(1.0)
#
#  l_mi = Core.Compiler.method_instances(bodyf, Tuple{Type{Int}})[1]
#  l_mi.backedges
#
#  f_mi = Core.Compiler.method_instances(f, Tuple{Type})[1]
#  f_mi.backedges
#  Main.NHDalyUtils.func_all_specializations(bodyf)
#  Main.NHDalyUtils.func_all_specializations(f)
#
#  l_mi == dave[end].edges[1]
#
#
#
#  # PROBLEM: There are no backedges from f to bodyf
#  # We can cause them by regular invoke
#  #invoke(bodyf, Tuple{Type{Int}}, Int)
#  bodyf(Int)
#  f_mi.backedges


foo(x) = bar(x)
bar(x) = 2

foo(Type{Int})
Main.NHDalyUtils.func_all_specializations(bar)
#Core.Compiler.method_instances(bar, Type)[1].backedges



@generated typeargs(x::Vector{T}) where {T} = sizeof(T)
typeargs([2,3])



# ============================================================================
# Comparing with Cassette
# ============================================================================

using Cassette

Cassette.@context Ctx;

foo(x) = bar(x)
bar(x) = x+1
Cassette.overdub(Ctx(), foo, 2)

foo_mi = Core.Compiler.method_instances(foo, Tuple{Type{Int}})[1]
#foo_mi.backedges
Main.NHDalyUtils.func_all_specializations(foo)






@staged lyndon(x) = :(x+1)
lyndon(2)


@testset "generated" begin
    @generated oldstyle(x) = 1
    oldstyle(3)
end
# TODO: We can't generate staged functions inside @testsets
@testset "inside testset" begin
    try
        @staged g1(x) = 1
        @test true
    catch e
        @test_broken false
    end
end

#@testset "simple" begin
    @staged g1(x) = sizeof(x)
    @test @inferred g1(3) == 8
#end

#@testset "where clause" begin
    # TODO: This is broken for the same reason it was broken in #32774, fixed in 8c05fc6!
    # The arguments passed-in are different: (Int, typeof(wherefunc), Int)
    # Apply that fix, and also the fix for varargs... in f20d374! :)
    @staged wherefunc(x::T) where {T} = (T)
    @test_broken wherefunc(2)

    @staged wherefunc2(x::Vector{T}) where {T} = (T)
    @test_broken wherefunc2([1,2,3])
#end


# Dynamic Dispatch example: can't use simple backedges
baz() = 2
f() = Any[baz][1]()
@staged foo() = f()
@test foo() == 2
baz() = 4
@test foo() == 4

@time @eval begin
    @staged foo() = f()
    foo()
end
@time foo()
@time @eval begin
    @generated foo() = f()
    foo()
end
@time foo()

struct X x end
@staged foo() = typemax(X)
Base.typemax(::Type{X}) = X(10)
@test foo() == X(10)
Base.typemax(::Type{X}) = X(100)
@test foo() == X(100)

end  # module
