__precompile__()

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
    macro info(x)
        :(info($(esc(x))))
    end
    macro warn(x)
        :(warn($(esc(x))))
    end
    using Base: gen_call_with_extracted_types
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
    interactive_matcher
    auto_open
end

is_identifier(s) = occursin(r"^@?[a-z_]+$"i, string(s))

is_locatable(::Any) = false
is_locatable(::Base.Callable) = true

@static if VERSION < v"0.7-"
    is_defined_in(_...) = false
else
    is_defined_in(child, parent) =
        child !== parent && parentmodule(child) === parent
end

function list_locatables(p::SearchPolicy, m::Module)
    locs = []
    for s in names(m; all=true)
        if is_identifier(s)
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
    read_stdout(cmd, input)

Julia implementation of "echo {input} | {cmd}".
"""
function read_stdout(cmd, input)
    stdout, stdin, process = _readandwrite(cmd)
    reader = @async read(stdout)
    try
        write(stdin, input)
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

run_matcher(input) = String(read_stdout(CONFIG.interactive_matcher, input))

function choose_method(methods)
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
    out = run_matcher(join(map(string, methods), "\n"))
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

function parse_search_policy(flag)
    if flag in :(:shallow, :s).args
        return Shallow()
    elseif flag in :(:recursive, :r).args
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
```
@search show                      # all method definitions
@search @time                     # all macro definitions
@search Base.Enums                # methods and macros in a module
@search REPL :r                   # search the module recursively
@search *(::Integer, ::Integer)   # methods with specified types
@search dot(π, ℯ)                 # methods with inferred types
```

Note that `@search` evaluates complex expression with `.` and `[]`
such as follows and search the returned value or the type of it:
```
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

code_search_methods(T) = search_methods(methodswith(T))

"""
    @searchmethods x
    @searchmethods ::X

Interactively search through `methodswith(typeof(x))` or
`methodswith(X)`.
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

end # module
