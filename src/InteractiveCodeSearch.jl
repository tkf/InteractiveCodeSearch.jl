module InteractiveCodeSearch
export @search

using Base: find_source_file

mutable struct SearchConfig  # CONFIG
    open
    interactive_matcher
    auto_open
end

is_identifier(s) = ismatch(r"^@?[a-z_]+$"i, string(s))

is_locatables(::Any) = false
is_locatables(::Base.Callable) = true

function list_locatables(m::Module)
    locs = []
    for s in names(m, true)
        if is_identifier(s)
            x = try
                getfield(m, s)
            catch err
                err isa UndefVarError && continue
                rethrow()
            end
            if is_locatables(x)
                push!(locs, x)
            end
        end
    end
    return locs
end

module_methods(m::Module) :: Vector{Method} =
    vcat(collect.(methods.(list_locatables(m)))...)


function read_stdout(cmd, input)
    stdout, stdin, process = readandwrite(cmd)
    reader = @async read(stdout)
    write(stdin, input)
    close(stdin)
    return wait(reader)
end

function parse_loc(line)
    rest, lineno = rsplit(line, ":", limit=2)
    _, path = rsplit(rest, " at ", limit=2)
    return String(path), parse(Int, lineno)
end

run_matcher(input) = String(read_stdout(CONFIG.interactive_matcher, input))

function choose_method(methods)
    if CONFIG.auto_open && length(methods) == 1
        m = first(methods)
        return string(m.file), m.line
    end
    out = run_matcher(join(map(string, methods), "\n"))
    if isempty(out)
        return
    end
    return parse_loc(out)
end

function run_open(path, lineno)
    info("Opening $path:$lineno")
    CONFIG.open(find_source_file(path), lineno)
end

maybe_open(::Void) = nothing
maybe_open(x::Tuple{String, Integer}) = run_open(x...)

search_methods(methods) = maybe_open(choose_method(methods))


code_search(f, t) = search_methods(methods(f, t))
code_search(f::Base.Callable) = search_methods(methods(f))
code_search(m::Module) = search_methods(module_methods(m))

function code_search(x::T) where T
    warn("Cannot search for $x; searching for its type $T instead...")
    code_search(T)
end

const CONFIG = SearchConfig(
    edit,                       # open
    `peco`,                     # interactive_matcher
    true,                       # auto_open
)

isline(::Any) = false
isline(ex::Expr) = ex.head == :line
try
    isline(::LineNumberNode) = true
catch err
    err isa UndefVarError || rethrow()
end

single_macrocall(::Any) = nothing
function single_macrocall(x::Expr)
    if x.head == :macrocall && all(isline.(x.args[2:end]))
        return x.args[1]
    elseif x.head == :block
        statements = find(a -> !isline(a), x.args)
        if length(statements) == 1
            return single_macrocall(x.args[statements[1]])
        end
    end
    return nothing
end

"""
    @search x

List file locations at which `x` are defined in an interactive matcher
and then open the chosen location in the editor.

See also `?InteractiveCodeSearch`
"""
macro search(x)
    if x isa Symbol || x isa Expr && x.head == :.
        :(code_search($(esc(x))))
    else
        macrocall = single_macrocall(x)
        if macrocall !== nothing
            :(code_search($(esc(macrocall))))
        else
            Base.gen_call_with_extracted_types(code_search, x)
        end
    end
end

end # module
