@static if VERSION < v"0.7.0-"
    using Base.Test
else
    using Test
    import Pkg
end

using InteractiveCodeSearch

macro test_nothrow(ex)
    quote
        @test begin
            $(esc(ex))
            true
        end
    end
end
