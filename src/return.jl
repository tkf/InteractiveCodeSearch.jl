export @searchreturn

struct CallableFinder{P <: SearchPolicy}
    modules::AbstractVector{Module}
    sp::P
    should_stop::Base.RefValue{Bool}
end

Base.IteratorSize(::Type{<: CallableFinder}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{<: CallableFinder}) = Base.HasEltype()
Base.eltype(::Type{<: CallableFinder}) = Base.Callable

struct CFState
    names::Vector{Symbol}
    modules::Vector{Module}
    i_name::Int
    i_module::Int
    seen::Set{Base.Callable}
end

advance_name(state::CFState, i_name) =
    CFState(state.names,
            state.modules,
            i_name,
            state.i_module,
            state.seen)

function advance_module(state::CFState)
    i = state.i_module + 1
    return CFState(
        names(state.modules[i]; all=true),
        state.modules,
        1,
        i,
        state.seen)
end

function Base.iterate(cf::CallableFinder)
    if isempty(cf.modules)
        return nothing
    end
    state = CFState(
        names(cf.modules[1]; all=true),
        collect(cf.modules),
        1,
        1,
        Set{Base.Callable}())
    return Base.iterate(cf, state)
end

function Base.iterate(cf::CallableFinder, state::CFState)
    m = state.modules[state.i_module]
    for i in state.i_name:lastindex(state.names)
        name = state.names[i]
        yield()  # Maybe throttle? Or Julia scheduler would do it?
        if cf.should_stop[]
            return nothing
        end
        if isdefined(m, name)
            x = getproperty(m, name)
            if (cf.sp isa Recursive &&
                    x isa Module &&
                    is_defined_in(x, m) &&
                    !(x in state.modules))
                insert!(state.modules, state.i_module + 1, x)
            elseif x isa Base.Callable && !(x in state.seen)
                push!(state.seen, x)
                return (x, advance_name(state, i + 1))
            end
        end
    end
    if state.i_module < length(state.modules)
        return Base.iterate(cf, advance_module(state))
    end
    return nothing
end

rettype_is(method::Method, typ::Type) =
    rettype_is(method.specializations, typ)

function rettype_is(specializations::Core.TypeMapEntry, typ::Type)
    while true
        specializations isa Core.TypeMapEntry || return false
        specializations.func isa Core.MethodInstance || return false
        specializations.func.rettype isa DataType || return false
        specializations.func.rettype <: typ && return true
        specializations.next === nothing && return false
        specializations = specializations.next
    end
end

rettype_is(::Any, typ::Type) = false

# What to do with `Core.TypeMapLevel`?  See:
# [typeof(m.specializations) for m in methods(!=).ms]

rettype_is(typ::Type) = method -> rettype_is(method, typ)

function search_by_rettype(sp::SearchPolicy,
                           typ::Type,
                           modules::AbstractVector{Module},
                           should_stop::Ref{Bool} = Ref(false))
    if isempty(modules)
        modules = Base.loaded_modules_array()
    end
    callables = CallableFinder(modules, sp, should_stop)
    methiters = Base.Generator(methods, callables)
    meths = Iterators.flatten(methiters)
    return Iterators.filter(rettype_is(typ), meths)
end

struct SearchQuery
    policy::SearchPolicy
    returntype::Type
    modules::Vector{Module}
end

struct BackgroundSearch
    id::Int
    query::SearchQuery
    found::Vector
    task::Task
    done::Base.RefValue{Bool}
    should_stop::Base.RefValue{Bool}
end

function showquery(io::IO, query::SearchQuery)
    print(io, "::")
    printstyled(io, query.returntype, color=:cyan)
    if !isempty(query.modules)
        print(io, " from ")
        printstyled(io, query.modules, color=:cyan)
    end
    if query.policy isa Recursive
        print(io, " recursively")
    end
    return
end

showquery(io, search::BackgroundSearch) = showquery(io, search.query)

function Base.show(io::IO, query::SearchQuery)
    print(io, nameof(typeof(query)), ": ")
    showquery(io, query)
    return
end

function Base.show(io::IO, search::BackgroundSearch)
    print(io, nameof(typeof(search)), " id=", search.id)

    # print " [done]" etc.
    print(io, " [")
    if search.should_stop[]
        printstyled(io, "canceled"; color=:yellow)
    elseif search.done[]
        printstyled(io, "done"; color=:green)
    elseif istaskdone(search.task)
        printstyled(io, "error"; color=:light_red, bold=true)
    else
        printstyled(io, "active"; color=:red)
    end
    print(io, "]")
    # Notes: `istaskdone(search.task)` can't be used here since `show`
    # is called at the end of the `search.task`.  (Though this can be
    # worked around by using additional task watching `search.task`.)

    print(io, " ", length(search.found), " found")
    return
end

function Base.show(io::IO, ::MIME"text/plain", search::BackgroundSearch)
    show(io, search)
    println(io)
    if search.done[] || search.should_stop[] || istaskdone(search.task)
        print(io, "Searched ")
    else
        print(io, "Searching ")
    end
    showquery(io, search)
    return
end

function _start_search_return(id, args...)
    query = SearchQuery(args...)
    found = []
    done = Ref(false)
    should_stop = Ref(false)
    task = @async begin
        append!(found, search_by_rettype(args..., should_stop))
        done[] = true

        @info "Finished search id=$id.  Look it up by `@search $id`."
        show(stderr, "text/plain", background_searches[id])
        println(stderr)
    end
    return BackgroundSearch(id, query, found, task, done, should_stop)
end

const background_searches = BackgroundSearch[]

nextid() = length(background_searches) + 1

function schedule_search_return(typ::Type,
                                modules::AbstractVector{Module};
                                policy = Recursive())
    search = _start_search_return(nextid(), policy, typ, modules)
    # TODO: don't start search task immediately
    push!(background_searches, search)
    return search
end

"""
    kill(search::InteractiveCodeSearch.BackgroundSearch)

Stop `search`.
"""
Base.kill(search::BackgroundSearch) = stop(search)

"""
    InteractiveCodeSearch.stop(search::BackgroundSearch)
    InteractiveCodeSearch.stop(id::Int = 0)

Stop `search`.  The first form can be invoked via `kill(search)` as well
(where `kill` is the function exported from `Base`).  See also `bg`.
"""
function stop(search::BackgroundSearch)
    # schedule(...; error=true) is not the right way to stop the task?
    # https://github.com/JuliaLang/julia/issues/25353#issuecomment-354807622
    search.should_stop[] = true
    wait(search.task)
    return
end
stop(id::Int = 0) = kill(bg(id))

"""
    InteractiveCodeSearch.bg(id::Int = 0)

Lookup background search by `id`.  For convenience, `id = 0` is the
last search and `id = -1` is the second last search.  More generally,
non-positive `id` is treated as the offset from `end`.
"""
function bg(id::Int = 0)
    if id < 1
        return background_searches[end + id]
    else
        return background_searches[id]
    end
end

# @search _s1
code_search(::SearchPolicy, search::BackgroundSearch) =
    search_methods(search.found)

# @search 1
code_search(p::SearchPolicy, id::Int) = code_search(p, bg(id))

function searchreturn(typ::Type, modules::AbstractVector{Module};
                      policy = Recursive())
    search_methods(search_by_rettype(policy, typ, modules))
end

"""
    @searchreturn Type Module [Module...]

Search functions returning type `Type` in `Module`s.  As this search
typically takes some time to finish, interactive matcher will not be
launched by this command.  Instead, a "handle" to the search in
background is returned which can be queried via `@search` later.
Calling `kill` (`Base.kill`) on the handle cancels the search.

# Limitations

* First run of `@searchreturn` for a large package like `LinearAlgebra`
  may be slow (~ 1 minute).
* The functions must be executed (JIT'ed) once for `@searchreturn` to
  find their returned by type.
* Any IO operations (like printing in REPL) would be slow while the search
  is active in background.
* Keyboard interruption does not work well while background search is
  active.  You need to hit CTRL-C multiple times to terminate a "foreground"
  code.  Furthermore, it will bring down the background search task as well.

# Examples
```julia-repl
julia> using LinearAlgebra, SparseArrays

julia> spzeros(3, 3)

julia> @searchreturn AbstractMatrix LinearAlgebra SparseArrays
┌ Info: Search result is stored in variable `_s1`.
│ You can interactively narrow down the search result later by
└ `@search _s1` or `@search 1`.

BackgroundSearch id=1 [active] 0 found
Searching ::AbstractArray{T,1} where T from Module[LinearAlgebra SparseArrays] recursively

julia> @search _s1

julia> kill(_s1)  # stop the search
```

If you prefer giving a custom name to the search result, just assign it to
some variable.

```julia-repl
julia> my_search = @searchreturn AbstractMatrix LinearAlgebra SparseArrays
julia> @search my_search
```
"""
macro searchreturn(typ, modules...)
    modules_array = Expr(:vect, esc.(modules)...)
    id = nextid()
    result = Symbol("_s", id)
    quote
        let search = schedule_search_return($(esc(typ)), $modules_array)
            global $(esc(result))
            if isdefined($(__module__), $(QuoteNode(result)))
                @warn $("""
                Variable `$result` exists!
                To refer to the search result, `ans` must be saved to some
                variable **NOW**.
                """)
            else
                @info $("""
                Search result is stored in variable `$result`.
                You can interactively narrow down the search result later by
                `@search $result` or `@search $id`.
                """)
                $(esc(result)) = search
            end
            println(stderr)
            search
        end
    end
end
