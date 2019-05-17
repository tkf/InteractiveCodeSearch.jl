#!/bin/bash
# -*- mode: julia -*-
#=
JULIA="${JULIA:-julia --color=yes --startup-file=no}"
exec ${JULIA} "$@" "${BASH_SOURCE[0]}"
=#

JL_PKG = "InteractiveCodeSearch"
VERSION >= v"0.7.0-DEV.5183" && using Pkg

if isfile("Project.toml") || isfile("JuliaProject.toml")
    if VERSION < v"0.7.0-DEV.5183"
        Pkg.clone(pwd())
        Pkg.build(JL_PKG)
    elseif VERSION >= v"1.1.0-rc1"
        Pkg.build(verbose=true)
    else
        Pkg.build()
    end
else
    Pkg.clone(pwd())
    if VERSION >= v"1.1.0-rc1"
        Pkg.build(JL_PKG; verbose=true)
    else
        Pkg.build(JL_PKG)
    end
end

# https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/script/julia.rb
