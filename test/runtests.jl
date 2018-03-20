module TestInteractiveCodeSearch

using InteractiveCodeSearch: read_stdout, parse_loc
using Base.Test

@testset "read_stdout" begin
    @test strip(String(read_stdout(`cat`, "spam"))) == "spam"
end

@testset "parse_loc" begin
    @test parse_loc("@test(ex::ANY, kws...) in Base.Test at test.jl:249") ==
        ("test.jl", 249)
end

end  # module
