export @searchhistory

using REPL: LineEdit, LineEditREPL,
    REPLHistoryProvider, find_hist_file, hist_from_file
using REPL.LineEdit: edit_insert, InputAreaState

newline_symbol = "⏎"
# newline_symbol = "⏎⃣"

"""
Some random character from Unicode Private Use Area.
"""
const fake_newline = '\uf056'  # = rand('\uE000':'\uF8FF')

function escape_history(code::String)
    code = replace(code, newline_symbol => fake_newline)
    code = replace(code, '\n' => newline_symbol)
    return code
end

function unescape_history(code::String)
    code = replace(code, newline_symbol => '\n')
    code = replace(code, fake_newline => newline_symbol)
    return code
end

const _history = String[]

function load_history!(history::Vector{String})
    path = find_hist_file()
    if !isfile(path)
        return empty!(history)
    end
    open(path) do file
        hp = hist_from_file(REPLHistoryProvider(Dict()), file, path)
        resize!(_history, length(hp.history))
        copyto!(_history, hp.history)
    end
    return history
end

load_history!() = load_history!(_history)

function get_history()
    try
        return Base.active_repl.interface.modes[1].hist.history
    catch
        if isempty(_history)
            load_history!(_history)
        end
        return _history
    end
end

function write_transformed_history(io::IO,
                                   history::Vector{String} = get_history())
    for code in Iterators.reverse(history)
        write(io, escape_history(code))
        write(io, "\n")
    end
end

function _set_next_input(repl::LineEditREPL, code::AbstractString)
    @async begin
        for _ in 1:10
            sleep(0.01)
            if LineEdit.state(repl.mistate).ias != InputAreaState(0, 0)
                edit_insert(repl.mistate, code)
                return
            end
        end
        @warn "Could not insert:\n$code"
    end
end

function _set_next_input(repl::Any, code::AbstractString)
    @info "Setting next input to $repl is not supported. Got:\n$code"
end

function is_ijulia()
    try
        return Main.IJulia.inited
    catch
        return false
    end
end

function set_next_input(code::AbstractString)
    repl = try
        Base.active_repl
    catch
        nothing
    end
    if repl == nothing && is_ijulia()
        Main.IJulia.load_string(code, true)  # replace = true
        return
    else
        _set_next_input(repl, code)
    end 
end

function searchhistory()
    buf = IOBuffer()
    write_transformed_history(buf)
    result = run_matcher(String(take!(buf)))
    set_next_input(rstrip(unescape_history(result)))
    return nothing
end

macro searchhistory()
    :(searchhistory())
end
