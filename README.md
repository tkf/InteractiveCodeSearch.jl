# InteractiveCodeSearch

[![Build Status][travis-img]][travis-url]
[![Coverage Status][coveralls-img]][coveralls-url]
[![codecov.io][codecov-img]][codecov-url]

![gif animation](search.gif "Searching code using @search")

Julia has `@edit` and `@less` which are very handy for reading the
implementation of functions.  However, you need to specify a "good
enough" (type) parameters for it to find the location of the code.

Instead, `InteractiveCodeSearch` provides a way to interactively
choose the code you want to read.


## Examples

```julia
using InteractiveCodeSearch
@search show       # search method definitions
@search @time      # search macro definitions
@search Base.REPL  # search methods and macros in a module
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
```


## Using InteractiveCodeSearch.jl by default

Use the same trick as [Revise.jl](https://github.com/timholy/Revise.jl); i.e.,
put the following code in your `.juliarc.jl`:

```julia
@schedule begin
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
