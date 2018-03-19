module InteractiveCodeSearch
export @search

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

function code_search(methods::Base.MethodList)
    out = String(read_stdout(`peco`, join(map(string, methods), "\n")))
    path, lineno = parse_loc(out)
    info("Opening $path:$lineno")
    edit(path, lineno)
end

code_search(f::Base.Callable) = code_search(methods(f))

macro search(x)
    if x isa Symbol
        :(code_search($(esc(x))))
    else
        :(@edit $(esc(x)))
    end
end

end # module
