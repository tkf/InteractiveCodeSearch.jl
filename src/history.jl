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

const history_provider = Ref{REPLHistoryProvider}()

"""
    load_history_provider() :: REPLHistoryProvider
"""
function load_history_provider()
    if !isdefined(history_provider, 1)
        history_provider[] = REPLHistoryProvider(Dict())
    end
    hp = history_provider[]
    if !isempty(hp.history)
        return hp
    end
    path = find_hist_file()
    if !isfile(path)
        return hp
    end
    open(path) do file
        hist_from_file(hp, file, path)
    end
    return hp
end

"""
    get_history_provider() :: REPLHistoryProvider
"""
function get_history_provider()
    try
        return Base.active_repl.interface.modes[1].hist
    catch
        return load_history_provider()
    end
end

function write_transformed_history(io::IO,
                                   hp = get_history_provider())
    seen = Set(String[])
    for (mode, code) in Iterators.reverse(zip(hp.modes, hp.history))
        if mode == :julia
            if !(code in seen)
                write(io, escape_history(code))
                write(io, "\n")
                push!(seen, code)
            end
        end
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
    result = run_matcher(write_transformed_history)
    set_next_input(rstrip(unescape_history(result)))
    return nothing
end

"""
    @searchhistory

Search history interactively.  Interactively narrows down the code you
looking for from the REPL history.

_Limitation/feature in IJulia_:
In IJulia, `@searchhistory` searches history of terminal REPL, not the
history of the current IJulia session.
"""
macro searchhistory()
    :(searchhistory())
end
