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
@search Base.REPL        # search methods and macros in a module
@search *(::Int, ::Int)  # search methods with specified type
@searchmethods 1         # search methods defined for integer
@searchmethods ::Int     # search methods defined for a specified type
```


## Requirements

* Interactive matching command.  For example:
  * [peco](https://github.com/peco/peco)
  * [percol](https://github.com/mooz/percol)


## Configuration

```julia
using InteractiveCodeSearch
InteractiveCodeSearch.CONFIG.interactive_matcher = `peco`    # default
InteractiveCodeSearch.CONFIG.interactive_matcher = `percol`
InteractiveCodeSearch.CONFIG.open = edit  # default
InteractiveCodeSearch.CONFIG.open = less  # use Base.less to read code
InteractiveCodeSearch.CONFIG.auto_open = true   # default
InteractiveCodeSearch.CONFIG.auto_open = false  # open matcher even when there
                                                # is only one candidate
```


## Using InteractiveCodeSearch.jl by default

Use the same trick as
[Revise.jl](https://github.com/timholy/Revise.jl/tree/v0.6); i.e., put
the following code in your `.juliarc.jl`:

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
