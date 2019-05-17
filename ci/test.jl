#!/bin/bash
# -*- mode: julia -*-
#=
JULIA="${JULIA:-julia --color=yes --startup-file=no}"
exec ${JULIA} "$@" "${BASH_SOURCE[0]}"
=#

JL_PKG = "InteractiveCodeSearch"
VERSION >= v"0.7.0-DEV.5183" && using Pkg
Pkg.test(JL_PKG; coverage=true)
