code = ARGS[1]
code = replace(code, "⏎" => "\n")

highlighter = nothing
if (highlighter_str = get(ENV, "_INTERACTIVECODESEARCH_JL_HIGHLIGHTER", nothing)) !== nothing
    highlighter = @eval @cmd $highlighter_str
end

file = line = nothing
if (m = match(r"(.*) in \w+ at (.*):([0-9]+)$", code)) !== nothing
    # code = String(m[1])
    file = m[2]
    line = parse(Int, m[3])
    if isabspath(file)
        print(basename(file), " (")
        printstyled(file; color = :light_black)
        println(")")
    else
        print(file, " ")
    end
    println("at line ", line)
    if isfile(file)
        open(pipeline(highlighter, stdin=IOBuffer(read(file)), stderr=stderr)) do io
            width, height = displaysize(stdout)
            for (i, str) in enumerate(eachline(io))
                if i > line + height * 2
                    close(io)
                    break
                elseif i > line - 2
                    if i == line
                        printstyled(lpad(i, 5), " "; color=:magenta, bold=true)
                        printstyled(">"; color=:red)
                    else
                        print(lpad(i, 5), " ")
                        printstyled(":"; color=:light_black)
                    end
                    print(str)
                    printstyled("\u200b")  # zero-width space
                    println()
                end
            end
        end
        exit()
    end
end

if highlighter === nothing
    print(code)
else
    run(pipeline(highlighter, stdin=IOBuffer(code), stdout=stdout, stderr=stderr))
end
