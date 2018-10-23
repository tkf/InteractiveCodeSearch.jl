module TestReturn

include("preamble.jl")
using InteractiveCodeSearch: seenkey, SeenKey

@testset "seenkey" begin
    @testset for x in [
                sin,
                Base,
                Array,
                Vector,
                Union{AbstractArray{T,1}, AbstractArray{T,2}} where T,
                Union{Int, Bool},
            ]
        @test seenkey(x) isa SeenKey
    end
end

@testset "@searchreturn" begin
    s = @eval @searchreturn Vector Pkg
    @test_nothrow @time wait(s.task)

    s = @eval @searchreturn Bool Base
    kill(s)
    _, t = @timed wait(s.task)
    @test t < 0.5

    # Check "Variable `_s3` exists!" path:
    global _s3 = nothing
    s = @eval @searchreturn Vector Pkg
    @test_nothrow @time wait(s.task)
end

end  # module
