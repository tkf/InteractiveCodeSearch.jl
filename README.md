# InteractiveCodeSearch.jl –- Interactively search Julia code

[![Build Status][travis-img]][travis-url]
[![Coverage Status][coveralls-img]][coveralls-url]
[![codecov.io][codecov-img]][codecov-url]

![gif animation](search.gif "Searching code using @search")


Julia has `@edit`, `@less`, etc. which are very handy for reading the implementation of functions.  However, you need to specify a "good enough" set of (type) parameters for them to find the location of the code.

Instead, `InteractiveCodeSearch` provides a way to interactively choose the code you want to read.

## Examples

```julia
using InteractiveCodeSearch
@search show             # search method definitions
@searchmethods 1         # search methods defined for integer
@searchhistory           # search history (Julia >= 0.7)
@searchreturn String Pkg # search methods returning a given type (Julia >= 0.7)
```

## Requirements

  * Interactive matching command.  For example:

      * [peco](https://github.com/peco/peco) (default in terminal)
      * [percol](https://github.com/mooz/percol)
      * [rofi](https://github.com/DaveDavenport/rofi) (GUI; default in IJulia)

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

### Using InteractiveCodeSearch.jl by default

Use the same trick as [Revise.jl](https://github.com/timholy/Revise.jl/tree/v0.6); i.e., put the following code in your `~/.julia/config/startup.jl` (>= Julia 0.7) or `~/.juliarc.jl` (Julia 0.6):

```julia
@async begin
    sleep(0.1)
    @eval using InteractiveCodeSearch
end
```

## Reference

### `@search`

```
@search x [:shallow | :s | :recursive | :r]
```

List file locations at which `x` are defined in an interactive matcher and then open the chosen location in the editor.

When `x` is a module, only the top-level definitions are searched.  To search all definitions in the submodule, pass `:recursive` or `:r` flag.

```
@search
```

If no expression is provided, search for the method returned by the previous execution; i.e., `x` defaults to `ans`.

**Examples**

```julia
@search show                      # all method definitions
@search @time                     # all macro definitions
@search Base.Enums                # methods and macros in a module
@search REPL :r                   # search the module recursively
@search *(::Integer, ::Integer)   # methods with specified types
@search dot(π, ℯ)                 # methods with inferred types
```

Note that `@search` evaluates complex expression with `.` and `[]` such as follows and search the returned value or the type of it:

```julia
@search Base.Multimedia.displays[2].repl
```


### `@searchhistory`

```
@searchhistory
```

Search history interactively.  Interactively narrows down the code you looking for from the REPL history.

*Limitation/feature in IJulia*: In IJulia, `@searchhistory` searches history of terminal REPL, not the history of the current IJulia session.


### `@searchmethods`

```
@searchmethods x
@searchmethods ::X
```

Interactively search through `methodswith(typeof(x))` or `methodswith(X)`.

**Examples**

```julia
@searchmethods 1         # search methods defined for integer
@searchmethods ::Int     # search methods defined for a specified type
```


### `@searchreturn`

```
@searchreturn Type Module [Module...]
```

Search functions returning type `Type` in `Module`s.

**Limitations**

  * First run of `@searchreturn` for a large package like `LinearAlgebra` may be slow (~ 1 minute).
  * The functions must be executed (JIT'ed) once for `@searchreturn` to find their returned by type.

**Examples**

```julia
using LinearAlgebra, SparseArrays
spzeros(3, 3)
@searchreturn AbstractMatrix LinearAlgebra SparseArrays
```


[travis-img]: https://travis-ci.org/tkf/InteractiveCodeSearch.jl.svg?branch=master
[travis-url]: https://travis-ci.org/tkf/InteractiveCodeSearch.jl
[coveralls-img]: https://coveralls.io/repos/tkf/InteractiveCodeSearch.jl/badge.svg?branch=master&service=github
[coveralls-url]: https://coveralls.io/github/tkf/InteractiveCodeSearch.jl?branch=master
[codecov-img]: http://codecov.io/github/tkf/InteractiveCodeSearch.jl/coverage.svg?branch=master
[codecov-url]: http://codecov.io/github/tkf/InteractiveCodeSearch.jl?branch=master

<!--
Generated by `./scripts/generate_readme.jl README.md`.
-->
