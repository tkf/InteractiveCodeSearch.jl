@static if VERSION >= v"0.7.0-DEV"
    using Pkg
end

Pkg.clone(pwd())
Pkg.build("InteractiveCodeSearch")
Pkg.test("InteractiveCodeSearch"; coverage=true)
