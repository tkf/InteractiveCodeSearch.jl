module TestReturn

include("preamble.jl")

@testset "@searchreturn" begin
    s = @eval @searchreturn Vector Pkg
    @test_nothrow @time wait(s.task)

    s = @eval @searchreturn Bool Base
    kill(s)
    _, t = @timed wait(s.task)
    @test t < 0.5
end

end  # module
