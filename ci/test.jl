@static if VERSION >= v"0.7.0-DEV"
    using Pkg
else
    Pkg.clone(pwd())
end

Pkg.build("InteractiveCodeSearch")
Pkg.test("InteractiveCodeSearch"; coverage=true)
