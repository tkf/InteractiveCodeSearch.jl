module InteractiveCodeSearch
export @search

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

function search_methods(methods)
    out = String(read_stdout(`peco`, join(map(string, methods), "\n")))
    if isempty(out)
        return
    end
    path, lineno = parse_loc(out)
    info("Opening $path:$lineno")
    edit(path, lineno)
end


code_search(f::Base.Callable) = code_search(methods(f))
code_search(ms::Base.MethodList) = search_methods(ms)
code_search(m::Module) = search_methods(module_methods(m))

macro search(x)
    if x isa Symbol || x isa Expr && x.head == :.
        :(code_search($(esc(x))))
    elseif x isa Expr && x.head == :macrocall && length(x.args) == 1
        :(code_search(Base.methods($(esc(x.args[1])))))
    else
        :(@edit $(esc(x)))
    end
end

end # module
