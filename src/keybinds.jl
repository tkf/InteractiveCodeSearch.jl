using REPL
using REPL: LineEdit

function setup_keybinds()
    schedule(Task(setup_keybinds_background))
    return
end

function setup_keybinds_background()
    try
        setup_keybinds_impl()
    catch err
        @error(
            "Unexpected error from `setup_keybinds_impl`",
            exception = (err, catch_backtrace()),
        )
    end
end

function setup_keybinds_impl()
    # This is why we need https://github.com/JuliaLang/julia/pull/29896...
    for _ in 1:20
        try
            Base.active_repl.interface.modes[1].keymap_dict
            @goto ok
        catch
        end
        sleep(0.05)
    end
    @warn "Failed to wait for REPL"
    return
    @label ok

    trigger_key = CONFIG.trigger_key
    if trigger_key === nothing
        @debug "`trigger_key` is `nothing`; not defining a shortcut key"
        return
    end
    trigger_key::Char

    repl = Base.active_repl
    repl isa REPL.LineEditREPL || return
    insert_search = function(s, _...)
        if isempty(s) || position(LineEdit.buffer(s)) == 0
            LineEdit.edit_insert(s, "@search")
        else
            LineEdit.edit_insert(s, trigger_key)
        end
    end
    new_keymap = Dict{Any,Any}(trigger_key => insert_search)

    main_mode = repl.interface.modes[1]
    main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict,
                                                  new_keymap)
    return
end

precompile(Tuple{typeof(setup_keybinds)})
precompile(Tuple{typeof(setup_keybinds_background)})
