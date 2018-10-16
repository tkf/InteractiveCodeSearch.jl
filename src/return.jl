export @searchreturn

struct CallableFinder{P <: SearchPolicy}
    modules::AbstractVector{Module}
    sp::P
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
                           modules::AbstractVector{Module})
    # methiters = map(methods, CallableFinder(modules, sp))  # -> array
    methiters = Base.Generator(methods, CallableFinder(modules, sp))
    meths = Iterators.flatten(methiters)
    return Iterators.filter(rettype_is(typ), meths)
end

function searchreturn(typ::Type, modules::AbstractVector{Module};
                      policy = Recursive())
    if isempty(modules)
        modules = Base.loaded_modules_array()
    end
    search_methods(search_by_rettype(policy, typ, modules))
end

"""
    @searchreturn Type Module [Module...]

Search functions returning type `Type` in `Module`s.

# Limitations

* First run of `@searchreturn` for a large package like `LinearAlgebra`
  may be slow (~ 1 minute).
* The functions must be executed (JIT'ed) once for `@searchreturn` to
  find their returned by type.

# Examples
```julia
using LinearAlgebra, SparseArrays
spzeros(3, 3)
@searchreturn AbstractMatrix LinearAlgebra SparseArrays
```
"""
macro searchreturn(typ, modules...)
    modules_array = Expr(:vect, esc.(modules)...)
    :(searchreturn($(esc(typ)), $modules_array))
end
