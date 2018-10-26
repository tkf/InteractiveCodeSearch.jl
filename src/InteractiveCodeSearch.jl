__precompile__()

"""
# InteractiveCodeSearch.jl --- Interactively search Julia code

Julia has `@edit`, `@less`, etc. which are very handy for reading the
implementation of functions.  However, you need to specify a "good
enough" set of (type) parameters for them to find the location of the
code.

Instead, `InteractiveCodeSearch` provides a few macros to
interactively choose the code you want to read.

## Features

* Interactively choose a method signature before opening the code
  location in your editor.

* Various ways to search methods, such as: by function name `@search show`,
  function call expression `@search show(stdout, "hello")`,
  function call signature `@search show(::IO, ::String)`,
  module name `@search Base`, argument value `@searchmethods 1`,
  argument type `@searchmethods ::Int`, and return type `@searchreturn Int`.

* Interactively search history.  It works in IJulia as well.

## Examples

```julia
using InteractiveCodeSearch
@search show             # search method definitions
@searchmethods 1         # search methods defined for integer
@searchhistory           # search history (Julia ≥ 0.7)
@searchreturn String Pkg # search methods returning a given type (Julia ≥ 0.7)
```

## Requirements

* Interactive matching command.  For example:
  * [peco](https://github.com/peco/peco) (default in terminal)
  * [percol](https://github.com/mooz/percol)
  * [rofi](https://github.com/DaveDavenport/rofi) (GUI; default in IJulia)
"""
module InteractiveCodeSearch
export @search, @searchmethods

using Base

@static if VERSION < v"0.7-"
    const IOError = Base.UVError
    const Nothing = Void
    const findall = find
    const occursin = ismatch
    const _readandwrite = readandwrite
    const fetch = wait
    names(x; all=false) = Base.names(x, all)
    methodswith(args...; supertypes=false) =
        Base.methodswith(args..., supertypes)
    macro info(x)
        :(info($(esc(x))))
    end
    macro warn(x)
        :(warn($(esc(x))))
    end
    using Base: gen_call_with_extracted_types
    @eval module Sys
        function which(program::AbstractString)
            try
                strip(readstring(`which $program`))
            catch
                nothing
            end
        end
    end  # module
else
    import Pkg
    using Base: IOError
    using InteractiveUtils: edit, gen_call_with_extracted_types, methodswith
    function _readandwrite(cmds)
        processes = open(cmds, "r+")
        return (processes.out, processes.in, processes)
    end
end

abstract type SearchPolicy end
struct Shallow <: SearchPolicy end
struct Recursive <: SearchPolicy end


mutable struct SearchConfig  # CONFIG
    open
    interactive_matcher::Cmd
    auto_open::Bool
end

maybe_identifier(s) = !startswith(string(s), "#")

is_locatable(::Any) = false
is_locatable(::Function) = true
is_locatable(t::Type) = !(t <: Vararg)
# https://github.com/JuliaLang/julia/issues/29645

@static if VERSION < v"0.7-"
    is_defined_in(_...) = false
else
    is_defined_in(child, parent) =
        child !== parent && parentmodule(child) === parent
end

function list_locatables(p::SearchPolicy, m::Module)
    locs = []
    for s in names(m; all=true)
        if maybe_identifier(s)
            x = try
                getfield(m, s)
            catch err
                err isa UndefVarError && continue
                rethrow()
            end
            if is_locatable(x)
                push!(locs, x)
            elseif p isa Recursive && x isa Module && is_defined_in(x, m)
                append!(locs, list_locatables(p, x))
            end
        end
    end
    return locs
end

module_methods(p::SearchPolicy, m::Module) :: Vector{Method} =
    vcat(collect.(methods.(list_locatables(p, m)))...)
# Note: the conversion `:: Vector{Method}` seems to be required only
# for Julia 0.6.


struct _Dummy end

function uninteresting_locs()
    locs = []
    for m in methods(_Dummy)
        path = string(m.file)
        if path != @__FILE__
            push!(locs, (path, m.line))
        end
    end
    return locs
end


"""
    find_source_file(file)

Find source `file` and return its full path.  It just calls
`Base.find_source_file` and return its result for normal Julia
installation.  For nightly Julia build, it tries to guess the right
path when `Base.find_source_file` failed.
"""
function find_source_file(file)
    path = Base.find_source_file(file)
    if path isa AbstractString && ! isfile(path)
        for m in methods(Pkg.add)
            exfile = try
                String(m.file)
            catch err
                continue
            end
            idx = findlast(joinpath(Base.Filesystem.path_separator,
                                    "share", "julia"), exfile)
            if idx isa Nothing
                continue
            end
            prefix = exfile[1:idx[1]]
            if startswith(file, prefix)
                # e.g., relpath = "share/julia/stdlib/v0.7/..."
                relpath = file[length(prefix)+1:end]
                return joinpath(Base.Sys.BINDIR, "..", relpath)
            end
        end
    end
    return path
end


"""
    read_stdout(input::AbstractString, cmd)
    read_stdout(input_provider, cmd)

Julia implementation of "echo {input} | {cmd}".
"""
function read_stdout(input::AbstractString, cmd)
    read_stdout(cmd) do stdin
        write(stdin, input)
    end
end

function read_stdout(input_provider, cmd)
    stdout, stdin, process = _readandwrite(cmd)
    reader = @async read(stdout)
    try
        input_provider(stdin)
    catch err
        if ! (err isa IOError)
            rethrow()
        end
    finally
        close(stdin)
    end
    return fetch(reader)
end

function parse_loc(line)
    rest, lineno = rsplit(line, ":", limit=2)
    _, path = rsplit(rest, " at ", limit=2)
    return String(path), parse(Int, lineno)
end

function run_matcher(input)
    maybe_warn_matcher()
    return String(read_stdout(input, CONFIG.interactive_matcher))
end

choose_method(methods::T) where T =
    _choose_method(Base.IteratorSize(T), methods)

@static if VERSION < v"0.7-"
    choose_method(methods::Union{Base.MethodList, AbstractVector}) =
        _choose_method(Base.HasLength(), methods)
end

function _choose_method(::Base.HasLength, methods)
    if isempty(methods)
        @info "No (interesting) method found"
        return
    end
    if CONFIG.auto_open && length(methods) == 1
        m = first(methods)
        loc = (string(m.file), m.line)
        if loc in uninteresting_locs()
            path, lineno = loc
            @info "Not opening uninteresting location: $path:$lineno"
            return
        end
        return loc
    end
    return _choose_method(Base.SizeUnknown(), methods)
end

function _choose_method(::Base.IteratorSize, methods)
    out = run_matcher() do stdin
        for m in methods
            show(stdin, m)
            println(stdin)
        end
    end
    if isempty(out)
        return
    end
    return parse_loc(out)
end

function run_open(path, lineno)
    @info "Opening $path:$lineno"
    CONFIG.open(find_source_file(path), lineno)
end

maybe_open(::Nothing) = nothing
maybe_open(x::Tuple{String, Integer}) = run_open(x...)

search_methods(methods) = maybe_open(choose_method(methods))


code_search_typed(f, t) = search_methods(methods(f, t))

code_search(::SearchPolicy, f::Base.Callable) = search_methods(methods(f))
code_search(p::SearchPolicy, m::Module) = search_methods(module_methods(p, m))

function code_search(p::SearchPolicy, ::T) where T
    @warn """Cannot search for given value of type $T
             Searching for its type instead..."""
    code_search(p, T)
end

"""
Configuration interface for `InteractiveCodeSearch`.

# Examples

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

Put the following code in your `~/.julia/config/startup.jl` (≥ Julia 0.7)
or `~/.juliarc.jl` (Julia 0.6):

```julia
using InteractiveCodeSearch
# InteractiveCodeSearch.CONFIG.interactive_matcher = ...
```
"""
const CONFIG = SearchConfig(
    edit,                       # open
    `peco`,                     # interactive_matcher
    true,                       # auto_open
)

should_eval(::Any) = false
should_eval(::Symbol) = true
should_eval(ex::Expr) = ex.head in (:., :ref)
# Given (say) `a.b[c].d[e]` It probably is better to only eval
# `a.b[c].d` and then search for `getindex(a.b[c].d, e)`.  But it's
# (1) a bit harder to implement and (2) evaluating the whole
# expression is still useful.  So let's keep the current
# implementation for a while.

isliteral(::Symbol) = false
isliteral(::Expr) = false
isliteral(::Any) = true

isline(::Any) = false
isline(ex::Expr) = ex.head == :line
isline(::LineNumberNode) = true

single_macrocall(::Any) = nothing
function single_macrocall(x::Expr)
    if x.head == :macrocall && all(isline.(x.args[2:end]))
        return x.args[1]
    elseif x.head == :block
        statements = findall(a -> !isline(a), x.args)
        if length(statements) == 1
            return single_macrocall(x.args[statements[1]])
        end
    end
    return nothing
end

explicitly_typed(::Any) = nothing
function explicitly_typed(ex::Expr)
    if ex.head == :call &&
            all(x isa Expr && x.head == :(::) for x in ex.args[2:end])
        return ex.args[1], [x.args[end] for x in ex.args[2:end]]
    end
    return nothing
end

# Julia >= 0.7:
parse_search_policy(flag::QuoteNode) = parse_search_policy(flag.value)
# Julia 0.6:
function parse_search_policy(flag::Expr)
    @assert flag.head == :quote
    @assert length(flag.args) == 1
    return parse_search_policy(flag.args[1])
end

function parse_search_policy(flag::Symbol)
    if flag in (:shallow, :s)
        return Shallow()
    elseif flag in (:recursive, :r)
        return Recursive()
    end
    error("Invalid flag $flag")
end

"""
    @search x [:shallow | :s | :recursive | :r]

List file locations at which `x` are defined in an interactive matcher
and then open the chosen location in the editor.

When `x` is a module, only the top-level definitions are searched.  To
search all definitions in the submodule, pass `:recursive` or `:r`
flag.

    @search

If no expression is provided, search for the method returned by the
previous execution; i.e., `x` defaults to `ans`.

# Examples
```julia
@search show                      # all method definitions
@search @time                     # all macro definitions
@search Base.Enums                # methods and macros in a module
@search REPL :r                   # search the module recursively
@search *(::Integer, ::Integer)   # methods with specified types
@search dot(π, ℯ)                 # methods with inferred types
```

Note that `@search` evaluates complex expression with `.` and `[]`
such as follows and search the returned value or the type of it:
```julia
@search Base.Multimedia.displays[2].repl
```
"""
macro search(x = :ans, flag = :(:shallow))
    p = parse_search_policy(flag)

    if should_eval(x)
        # Examples:
        #   @search show
        #   @search Base.Enums
        #   @search Base.Multimedia.displays[2].repl
        return :(code_search($p, $(esc(x))))
    end

    macrocall = single_macrocall(x)
    if macrocall !== nothing
        # Examples:
        #   @search @time
        #   @search begin @time end
        return :(code_search($p, $(esc(macrocall))))
    end

    func_type = explicitly_typed(x)
    if func_type !== nothing
        f, ts = func_type
        # Examples:
        #   @search *(::Integer, ::Integer)
        #   @search dot(::AbstractVector, ::SparseVector)
        return :(code_search_typed($(esc(f)), tuple($(esc.(ts)...))))
    end

    # Since `gen_call_with_extracted_types` does not handle literals,
    # let's handle this case here (although there are not much can be
    # done).
    if isliteral(x)
        # Examples:
        #   @search ""
        #   @search 1
        return :(code_search($p, $(esc(x))))
    end

    # Examples:
    #   @search 1 * 2
    #   @search dot([], [])
    if VERSION < v"0.7-"
        gen_call_with_extracted_types(code_search_typed, x)
    else
        gen_call_with_extracted_types(__module__, code_search_typed, x)
    end
end

code_search_methods(T) = search_methods(methodswith(T; supertypes=true))

"""
    @searchmethods x
    @searchmethods ::X

Interactively search through `methodswith(typeof(x))` or
`methodswith(X)`.

# Examples
```julia
@searchmethods 1         # search methods defined for integer
@searchmethods ::Int     # search methods defined for a specified type
```
"""
macro searchmethods(x)
    if x isa Expr && x.head == :(::)
        if length(x.args) > 1
            @info "Ignoring: $(x.args[1:end-1]...) in $x"
        end
        :(code_search_methods($(esc(x.args[end]))))
    else
        :(code_search_methods(typeof($(esc(x)))))
    end
end

const preferred_terminal = Cmd[
    `peco`,
    `percol`,
]

const preferred_gui = Cmd[
    `rofi -dmenu -i -p "🔎"`,
    # what else?
]

function need_gui(stdstreams = [
                      (@static VERSION < v"0.7-" ? STDOUT : stdout),
                      (@static VERSION < v"0.7-" ? STDIN : stdin),
                  ])
    return !all(isa.(stdstreams, Ref(Base.TTY)))
end

function choose_preferred_command(commands::Vector{Cmd})
    for cmd in commands
        if Sys.which(cmd.exec[1]) !== nothing
            return cmd
        end
    end
    return nothing
end

function choose_preferred_command(f, commands::Vector{Cmd})
    cmd = choose_preferred_command(commands)
    if cmd !== nothing
        return cmd
    else
        return f()
    end
end

# Julia 0.6
const _preferred_terminal = preferred_terminal
const _preferred_gui = preferred_gui

function choose_interactive_matcher(;
        preferred_terminal = _preferred_terminal,
        preferred_gui = _preferred_gui,
        gui = need_gui())
    if gui
        return choose_preferred_command(preferred_gui) do
            return preferred_gui[1]
        end
    else
        return choose_preferred_command(preferred_terminal) do
            return choose_preferred_command(preferred_gui) do
                return preferred_terminal[1]
            end
        end
    end
end

function matcher_installation_tips(program::AbstractString)
    if program == "peco"
        return """
        See https://github.com/peco/peco for how to install peco.
        """
    elseif program == "rofi"
        msg = """
        See https://github.com/DaveDavenport/rofi for how to install rofi.
        """
    else
        msg = ""
    end
    return """
    $msg
    For terminal usage, `peco` is recommended.
    See https://github.com/peco/peco for how to install peco.
    """
end

function maybe_warn_matcher(cmd = CONFIG.interactive_matcher)
    if Sys.which(cmd.exec[1]) === nothing
        @warn """
        Matcher $(cmd.exec[1]) not installed.
        $(matcher_installation_tips(cmd.exec[1]))
        """
    end
end

function __init__()
    CONFIG.interactive_matcher = choose_interactive_matcher()
    maybe_warn_matcher()
end

@static if VERSION >= v"0.7-"
    include("taskmanager.jl")
    include("history.jl")
    include("return.jl")
end

end # module
