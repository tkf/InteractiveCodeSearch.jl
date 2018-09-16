# InteractiveCodeSearch

[![Build Status][travis-img]][travis-url]
[![Coverage Status][coveralls-img]][coveralls-url]
[![codecov.io][codecov-img]][codecov-url]

![gif animation](search.gif "Searching code using @search")

Julia has `@edit`, `@less`, etc. which are very handy for reading the
implementation of functions.  However, you need to specify a "good
enough" set of (type) parameters for them to find the location of the
code.

Instead, `InteractiveCodeSearch` provides a way to interactively
choose the code you want to read.


## Examples

```julia
using InteractiveCodeSearch
@search show             # search method definitions
@search @time            # search macro definitions
@search Base.Enums       # search methods and macros in a module
@search REPL :r          # search the module recursively
@search *(::Int, ::Int)  # search methods with specified type
@searchmethods 1         # search methods defined for integer
@searchmethods ::Int     # search methods defined for a specified type
@searchhistory           # search history (Julia >= 0.7)
@searchreturn String Pkg # search methods returning a given type (Julia >= 0.7)
```

First run of `@searchreturn` for a large package like `LinearAlgebra`
may be slow (~ 1 minute).


## Requirements

* Interactive matching command.  For example:
  * [peco](https://github.com/peco/peco)
  * [percol](https://github.com/mooz/percol)
  * [rofi](https://github.com/DaveDavenport/rofi) (GUI)


## Configuration

```julia
using InteractiveCodeSearch
InteractiveCodeSearch.CONFIG.interactive_matcher = `peco`  # default in terminal
InteractiveCodeSearch.CONFIG.interactive_matcher = `percol`
InteractiveCodeSearch.CONFIG.interactive_matcher =
    `rofi -dmenu -i -p "🔎"`  # use GUI matcher (default in non-terminal
                              # environment like IJulia)
InteractiveCodeSearch.CONFIG.interactive_matcher =
    `rofi -dmenu -i -p "🔎" -fullscreen`  # bigger screen
InteractiveCodeSearch.CONFIG.open = edit  # default
InteractiveCodeSearch.CONFIG.open = less  # use Base.less to read code
InteractiveCodeSearch.CONFIG.auto_open = true   # default
InteractiveCodeSearch.CONFIG.auto_open = false  # open matcher even when there
                                                # is only one candidate
```


## Using InteractiveCodeSearch.jl by default

Use the same trick as
[Revise.jl](https://github.com/timholy/Revise.jl/tree/v0.6); i.e., put
the following code in your `~/.julia/config/startup.jl` (>= Julia 0.7)
or `~/.juliarc.jl` (Julia 0.6):

```julia
@async begin
    sleep(0.1)
    @eval using InteractiveCodeSearch
end
```

[travis-img]: https://travis-ci.org/tkf/InteractiveCodeSearch.jl.svg?branch=master
[travis-url]: https://travis-ci.org/tkf/InteractiveCodeSearch.jl
[coveralls-img]: https://coveralls.io/repos/tkf/InteractiveCodeSearch.jl/badge.svg?branch=master&service=github
[coveralls-url]: https://coveralls.io/github/tkf/InteractiveCodeSearch.jl?branch=master
[codecov-img]: http://codecov.io/github/tkf/InteractiveCodeSearch.jl/coverage.svg?branch=master
[codecov-url]: http://codecov.io/github/tkf/InteractiveCodeSearch.jl?branch=master
