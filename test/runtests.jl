module TestInteractiveCodeSearch

include("preamble.jl")
using InteractiveCodeSearch:
    Shallow, Recursive, list_locatables, module_methods, choose_method,
    read_stdout, parse_loc, single_macrocall, isliteral
using Base: find_source_file

function with_config(f; kwargs...)
    config = deepcopy(InteractiveCodeSearch.CONFIG)
    try
        for (name, value) in kwargs
            setfield!(InteractiveCodeSearch.CONFIG, name, value)
        end
        f()
    finally
        for name in fieldnames(typeof(config))
            value = getfield(config, name)
            setfield!(InteractiveCodeSearch.CONFIG, name, value)
        end
    end
end

@testset "read_stdout" begin
    @test strip(String(read_stdout("spam", `cat`))) == "spam"
    @test strip(String(read_stdout(io -> write(io, "egg"), `cat`))) == "egg"
end

@testset "parse_loc" begin
    @test parse_loc("@test(ex::ANY, kws...) in Base.Test at test.jl:249") ==
        ("test.jl", 249)
end

module ModuleA
    module ModuleB
        b() = nothing
    end
    a() = nothing
end

@testset "list_locatables" begin
    locs = Set(list_locatables(Shallow(), InteractiveCodeSearch))
    @test Set([
        InteractiveCodeSearch.list_locatables,
        InteractiveCodeSearch.module_methods,
        InteractiveCodeSearch.read_stdout,
        InteractiveCodeSearch.parse_loc,
        InteractiveCodeSearch.search_methods,
        getfield(InteractiveCodeSearch, Symbol("@search")),
    ]) <= locs

    locs = Set(list_locatables(Shallow(), ModuleA))
    @test locs >= Set(Any[ModuleA.a])
    locs = Set(list_locatables(Shallow(), ModuleA.ModuleB))
    @test locs >= Set(Any[ModuleA.ModuleB.b])
    if VERSION >= v"0.7-"
        locs = Set(list_locatables(Recursive(), ModuleA))
        @test locs >= Set(Any[ModuleA.a, ModuleA.ModuleB.b])
    end
end

@testset "module_methods" begin
    @testset for
            p in [Shallow(), Recursive()],
            m in [InteractiveCodeSearch, Base.Filesystem]
        @test_nothrow module_methods(p, m)
    end
end

@testset "choose_method" begin
    single_method = module_methods  # has only one method

    with_config(
        open = (_...) -> error("must not be called"),
        interactive_matcher = `echo " at test.jl:249"`,
        auto_open = true,
    ) do
        # when function has only one method, `auto_open` has to kick-in:
        path, line = choose_method(methods(single_method))
        @test path isa String
        @test path != "test.jl"
        @test line isa Integer
        @test line != 249

        # `code_search` has several methods, so the matcher has to be called:
        path, line = choose_method(methods(InteractiveCodeSearch.code_search))
        @test (path, line) == ("test.jl", 249)

        # "Not opening uninteresting location"
        chosen = choose_method(methods(InteractiveCodeSearch._Dummy, (Any,)))
        @eval @test ($chosen) === nothing
    end

    with_config(
        open = (_...) -> error("must not be called"),
        interactive_matcher = `echo " at test.jl:249"`,
        auto_open = false,
    ) do
        # When `auto_open = false`, the matcher has to be called
        path, line = choose_method(methods(single_method))
        @test (path, line) == ("test.jl", 249)
    end
end

@testset "find_source_file" begin
    m = first(methods(Pkg.clone))
    file = string(m.file)
    found = InteractiveCodeSearch.find_source_file(file)
    @eval @test isfile($found)
end

@testset "isliteral" begin
    @test isliteral(1)
    @test isliteral(1.0)
    @test isliteral("1")
    @test ! isliteral(:a)
    @test ! isliteral(:(a + b))
end

@testset "single_macrocall" begin
    @test single_macrocall(:(@search)) == Symbol("@search")
    @test single_macrocall(quote @search end) == Symbol("@search")
    @test single_macrocall(:f) == nothing
    @test single_macrocall(quote f end) == nothing
end

@testset "patched" begin
    open_args = []
    dummy_openline(args...) = push!(open_args, args)

    with_config(
        interactive_matcher = `echo " at test.jl:249"`,
        open = dummy_openline,
        auto_open = false,
    ) do
        @test_nothrow @eval @search read_stdout
        @test_nothrow @eval @search read_stdout(`cat`, "hello")
        @test_nothrow @eval @search read_stdout(::Cmd, ::String)
        @test_nothrow @eval @search read_stdout(`cat`::Cmd, "hello"::String)
        @test_nothrow @eval @search @search
        @test_nothrow @eval @search @search(read_stdout)
        @test_nothrow @eval @search ""
        @test_nothrow @eval @search InteractiveCodeSearch
        @test_nothrow @eval @searchmethods im
        @test_nothrow @eval @searchmethods ::Complex
        @test_nothrow @eval @searchmethods c::Complex
        @test open_args == repeat([(find_source_file("test.jl"), 249)],
                                  outer=11)

        # @show open_args
    end

    with_config(
        interactive_matcher = `true`,
        open = (args...) -> error("open must not be called"),
        auto_open = false,
    ) do
        @test_nothrow @eval @search read_stdout
    end
end

if v"0.7-" <= VERSION < v"1.2-"
    include("test_return.jl")
end

end  # module
