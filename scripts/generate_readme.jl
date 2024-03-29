#!/bin/bash
# -*- mode: julia -*-
#=
JULIA="${JULIA:-julia}"
JULIA_CMD="${JULIA_CMD:-${JULIA} --color=yes --startup-file=no}"

thisdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
rootdir="$(dirname "$thisdir")"
export JULIA_PROJECT="$thisdir"
export JULIA_LOAD_PATH="@"

set -ex
${JULIA_CMD} \
    -e 'using Pkg; Pkg.develop(name="InteractiveCodeSearch", url=ARGS[1])' \
    "$rootdir"

exec ${JULIA_CMD} "${BASH_SOURCE[0]}" "$@"
=#

header = """

[![Build Status][ci-img]][ci-url]
[![codecov.io][codecov-img]][codecov-url]

![gif animation](search.gif "Searching code using @search")
"""

footer = """
[ci-img]: https://github.com/tkf/InteractiveCodeSearch.jl/actions/workflows/test.yml/badge.svg
[ci-url]: https://github.com/tkf/InteractiveCodeSearch.jl/actions/workflows/test.yml
[codecov-img]: http://codecov.io/github/tkf/InteractiveCodeSearch.jl/coverage.svg?branch=master
[codecov-url]: http://codecov.io/github/tkf/InteractiveCodeSearch.jl?branch=master

<!--
Generated by `./scripts/generate_readme.jl README.md`.
-->
"""

using Base.Docs: doc
import Markdown

using Documenter.Writers.MarkdownWriter: dropheaders

import InteractiveCodeSearch


function generate_readme(io::IO = stdout)
    text = sprint(show, "text/markdown", @doc InteractiveCodeSearch)
    lines = split(text, "\n")

    println(io, lines[1])
    println(io, header)
    for line in lines[2:end]
        println(io, line)
    end

    println(io, "## Reference")
    println(io)

    function loc(f)
        m1, = methods(f).ms
        return (m1.file, m1.line)
    end
    exports = [
        (name, getproperty(InteractiveCodeSearch, name))
        for name in names(InteractiveCodeSearch)
    ]
    exports = filter((x -> x[2] isa Function), exports)
    exports = sort(collect(exports), by=x -> loc(x[2]))

    for (name, exported) in exports
        md = dropheaders(doc(exported))
        println(io, "### `$name`")
        println(io)
        show(io, "text/markdown", md)
        println(io)
        println(io)
    end

    println(io, "### `InteractiveCodeSearch.CONFIG`")
    show(io, "text/markdown", dropheaders(@doc InteractiveCodeSearch.CONFIG))
    println(io)
    println(io)

    print(io, footer)
end


function generate_readme(filename::AbstractString)
    open(filename, "w") do io
        generate_readme(io)
    end
end


function rerender()
    io = IOBuffer()
    generate_readme(io)
    seek(io, 0)
    return Markdown.parse(io)
end


if isinteractive()
    # so that it can be called via `include("scripts/generate_readme.jl")()`
    generate_readme
else
    generate_readme(ARGS...)
end
