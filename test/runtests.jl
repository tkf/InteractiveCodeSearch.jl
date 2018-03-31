module TestInteractiveCodeSearch

using InteractiveCodeSearch
using InteractiveCodeSearch: list_locatables, module_methods,
    read_stdout, parse_loc, single_macrocall
using Base.Test

macro test_nothrow(ex)
    quote
        @test begin
            $(esc(ex))
            true
        end
    end
end

@testset "read_stdout" begin
    @test strip(String(read_stdout(`cat`, "spam"))) == "spam"
end

@testset "parse_loc" begin
    @test parse_loc("@test(ex::ANY, kws...) in Base.Test at test.jl:249") ==
        ("test.jl", 249)
end

@testset "list_locatables" begin
    locs = Set(list_locatables(InteractiveCodeSearch))
    @test Set([
        InteractiveCodeSearch.list_locatables,
        InteractiveCodeSearch.module_methods,
        InteractiveCodeSearch.read_stdout,
        InteractiveCodeSearch.parse_loc,
        InteractiveCodeSearch.search_methods,
        getfield(InteractiveCodeSearch, Symbol("@search")),
    ]) <= locs
end

@testset "module_methods" begin
    @test_nothrow module_methods(InteractiveCodeSearch)
    @test_nothrow module_methods(Base.Filesystem)
end

@testset "single_macrocall" begin
    @test single_macrocall(:(@search)) == Symbol("@search")
    @test single_macrocall(quote @search end) == Symbol("@search")
    @test single_macrocall(:f) == nothing
    @test single_macrocall(quote f end) == nothing
end

@testset "patched" begin
    config = deepcopy(InteractiveCodeSearch.CONFIG)
    try
        open_args = []
        dummy_openline(args...) = push!(open_args, args)

        let c = InteractiveCodeSearch.CONFIG
            c.interactive_matcher = `echo " at test.jl:249"`
            c.open = dummy_openline
        end

        @test_nothrow @eval @search read_stdout
        @test_nothrow @eval @search @search
        @test_nothrow @eval @search InteractiveCodeSearch
        @test open_args == repeat([("test.jl", 249)], outer=3)

        # @show open_args
    finally
        let c = InteractiveCodeSearch.CONFIG
            c.interactive_matcher = config.interactive_matcher
            c.open = config.open
        end
    end
end

end  # module
