using Aqua
using FiveLetterWorda
using Test
using TestSetExtensions

@testset ExtendedTestSet "FiveLetterWorda.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(FiveLetterWorda; ambiguities=false)
    end
end
