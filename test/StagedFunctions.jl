module StagedFunctionsTest #end

using StagedFunctions

using Test
using InteractiveUtils

f(x) = 2
@staged lyndon(x) = f(x)
lyndon(2)
f(x) = 3
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
#Main.NHDalyUtils.func_all_specializations(bar)
#Core.Compiler.method_instances(bar, Type)[1].backedges



@generated typeargs(x::Vector{T}) where {T} = sizeof(T)
typeargs([2,3])





@staged lyndon(x) = :(x+1)
lyndon(2)


@testset "generated" begin
    @generated oldstyle() = 1
    @test oldstyle() == 1
end
@testset "staged" begin
    @staged g1() = 1
    @test g1() == 1
end

@testset "simple" begin
    @staged g1(x) = sizeof(x)
    @test @inferred g1(3) == 8
end

@testset "type params and where clauses; fixed in PR (#2)" begin
    @staged typeparam(x::Int, y::Int) = :(x+y)
    @test typeparam(2,3) == 5
    @test_throws MethodError typeparam("", "")

    # Test that @staged functions work with where clauses
    @staged wherefunc(x::T) where {T} = (T)
    @test wherefunc(2) == Int

    @staged wherefunc2(x::Vector{T}) where {T} = (T)
    @test wherefunc2([1,2,3]) == Int
end

@testset "varargs...; fixed in PR (#3)" begin
    @staged argscount(x...) = length(x)
    @test argscount(1,2,3) == 3

    @staged tail(x, y...) = :y
    @test tail(1, 2,3) == (2,3)
end
@testset "type params + varargs" begin
    @staged f(x::Int, y::T, z...) where {T} = :(T, x, z)
    @test f(1, 2, 3, 4) == (Int, 1, (3,4))
end

# Dynamic dispatches: Fixed by tracing compilation (PR #1)
#  Simple backedges aren't sufficient for these cases
baz() = 2
f() = Any[baz][1]()
@staged foo() = f()
@test foo() == 2
baz() = 4             # Update baz()
@test foo() == 4      # And foo() is regenerated


# Currently, @staged functions are around 10x slower than @generated funcs b/c of the
# tracing with Cassette.
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

# Staged functions that operate on type params: Fixed in PR (#4)
struct X x end
@staged foo() = typemax(X)
Base.typemax(::Type{X}) = X(10)
@test foo() == X(10)
Base.typemax(::Type{X}) = X(100)
@test foo() == X(100)

@testset "error handling" begin
    # Ensure that `@staged` reports the same errors that @generated would for users' errors

    # static parameter names not unique
    @test try @eval @staged foo(x) where T where T = 2 catch e; e end ==
        try @eval @generated foo(x) where T where T = 2 catch e; e end
end


end  # module
