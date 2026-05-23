using Aqua
using FiveLetterWorda
using Test
using TestSetExtensions

# Canonicalize a results vector for ordering-independent comparison.
# Each clique is represented as a Set{String}; the full result is a Set
# of those sets. This survives multithreaded ordering and per-clique
# permutation.
canon(combos::AbstractVector{<:AbstractVector{<:AbstractString}}) =
    Set(Set.(combos))

@testset ExtendedTestSet "FiveLetterWorda.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(FiveLetterWorda; ambiguities=false)
    end

    @testset "Regression: combination counts" begin
        # n=5, order=5 — the canonical problem. 538 matches Matt Parker's
        # original count; previous versions of this package reported 540
        # because the recursive base case enumerated set bits in the
        # neighborhood intersection without enforcing a strict index
        # ordering on the final pick, leading to 2 cliques being
        # emitted twice. The current implementation walks every clique
        # in strictly increasing index order and emits each exactly once.
        result_na = main(5; exclude_anagrams=true, progress=false)
        @test length(result_na.combinations) == 538

        result_wa = main(5; exclude_anagrams=false, progress=false)
        @test length(result_wa.combinations) == 831

        # Smaller cases exercise the recursive depth differently and
        # are fast enough for CI.
        # n=10, order=2 — the precompile workload case
        result_10 = main(10; exclude_anagrams=true, progress=false)
        @test result_10 isa NamedTuple
        @test result_10.combinations isa Vector{WordCombination}
    end

    @testset "Regression: result stability across adjacency_matrix_type" begin
        # Both storage types must produce the same set of cliques.
        words = FiveLetterWorda.n_letter_words(5)
        words = remove_anagrams(words)

        adj_bool = adjacency_matrix(words, Matrix{Bool}; progress=false)
        adj_bit = adjacency_matrix(words, BitMatrix; progress=false)
        @test adj_bool == adj_bit

        c_bool = cliques(adj_bool, words, 5; progress=false)
        c_bit = cliques(adj_bit, words, 5; progress=false)
        @test canon(c_bool) == canon(c_bit)
        @test length(c_bool) == 538
    end
end
