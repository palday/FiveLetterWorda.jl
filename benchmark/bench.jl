using Pkg
if Base.active_project() != joinpath(@__DIR__, "Project.toml")
    Pkg.activate(@__DIR__)
end
# Ensure FiveLetterWorda is dev'd to the parent path. Idempotent: Pkg.develop
# is a no-op when the dependency is already pointed at the same source.
let parent = abspath(joinpath(@__DIR__, ".."))
    flw_uuid = Base.UUID("40c3fe41-db9e-4ab5-a060-da035752fe98")
    manifest_ok = false
    try
        info = get(Pkg.dependencies(), flw_uuid, nothing)
        manifest_ok = info !== nothing && info.source == parent
    catch
        manifest_ok = false
    end
    if !manifest_ok
        Pkg.develop(; path=parent)
    end
    Pkg.instantiate()
end

using BenchmarkTools
using FiveLetterWorda
using FiveLetterWorda: n_letter_words, remove_anagrams, adjacency_matrix, cliques

const SUITE = BenchmarkGroup()

# Cache inputs across samples
const WORDS_WITH_ANAGRAMS = n_letter_words(5)
const WORDS_NO_ANAGRAMS = remove_anagrams(WORDS_WITH_ANAGRAMS)

# Prebuild adjacency matrices once so the `cliques` group times search only
const ADJ_BOOL_NA = adjacency_matrix(WORDS_NO_ANAGRAMS, Matrix{Bool}; progress=false)
const ADJ_BOOL_WA = adjacency_matrix(WORDS_WITH_ANAGRAMS, Matrix{Bool}; progress=false)
const ADJ_BIT_NA = adjacency_matrix(WORDS_NO_ANAGRAMS, BitMatrix; progress=false)
const ADJ_BIT_WA = adjacency_matrix(WORDS_WITH_ANAGRAMS, BitMatrix; progress=false)

SUITE["adjacency_matrix"] = BenchmarkGroup()
SUITE["adjacency_matrix"]["Matrix{Bool}, no_anagrams"] =
    @benchmarkable adjacency_matrix($WORDS_NO_ANAGRAMS, Matrix{Bool}; progress=false)
SUITE["adjacency_matrix"]["Matrix{Bool}, with_anagrams"] =
    @benchmarkable adjacency_matrix($WORDS_WITH_ANAGRAMS, Matrix{Bool}; progress=false)
SUITE["adjacency_matrix"]["BitMatrix, no_anagrams"] =
    @benchmarkable adjacency_matrix($WORDS_NO_ANAGRAMS, BitMatrix; progress=false)
SUITE["adjacency_matrix"]["BitMatrix, with_anagrams"] =
    @benchmarkable adjacency_matrix($WORDS_WITH_ANAGRAMS, BitMatrix; progress=false)

SUITE["cliques"] = BenchmarkGroup()
SUITE["cliques"]["Matrix{Bool}, no_anagrams, order=5"] =
    @benchmarkable cliques($ADJ_BOOL_NA, $WORDS_NO_ANAGRAMS, 5; progress=false)
SUITE["cliques"]["Matrix{Bool}, with_anagrams, order=5"] =
    @benchmarkable cliques($ADJ_BOOL_WA, $WORDS_WITH_ANAGRAMS, 5; progress=false)
SUITE["cliques"]["BitMatrix, no_anagrams, order=5"] =
    @benchmarkable cliques($ADJ_BIT_NA, $WORDS_NO_ANAGRAMS, 5; progress=false)
SUITE["cliques"]["BitMatrix, with_anagrams, order=5"] =
    @benchmarkable cliques($ADJ_BIT_WA, $WORDS_WITH_ANAGRAMS, 5; progress=false)

SUITE["main"] = BenchmarkGroup()
SUITE["main"]["no_anagrams"] =
    @benchmarkable main(5; exclude_anagrams=true, adjacency_matrix_type=Matrix{Bool}, progress=false)
SUITE["main"]["with_anagrams"] =
    @benchmarkable main(5; exclude_anagrams=false, adjacency_matrix_type=Matrix{Bool}, progress=false)

# When run as a script (julia --project=benchmark benchmark/bench.jl),
# execute the suite and print a compact summary.
if abspath(PROGRAM_FILE) == @__FILE__
    seconds = parse(Float64, get(ENV, "BENCH_SECONDS", "2"))
    samples = parse(Int, get(ENV, "BENCH_SAMPLES", "20"))
    @info "Running benchmark suite" seconds samples threads=Threads.nthreads()
    results = run(SUITE; seconds=seconds, samples=samples, evals=1)
    display(median(results))
    println()
end

return SUITE
