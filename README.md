# FiveLetterWorda.jl

[![Build Status][build-img]][build-url] [![codecov](https://codecov.io/gh/palday/FiveLetterWorda.jl/graph/badge.svg?token=iBTLt2GfOe)](https://codecov.io/gh/palday/FiveLetterWorda.jl) 
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://palday.github.io/FiveLetterWorda.jl/dev)
<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://palday.github.io/FiveLetterWorda.jl/stable) -->


[build-img]: https://github.com/palday/FiveLetterWorda.jl/actions/workflows/ci.yml/badge.svg
[build-url]: https://github.com/palday/FiveLetterWorda.jl/actions

*Can you find: five five-letter words with twenty-five unique letters?*

Inspired by: https://youtu.be/_-AfhLQfb6w

Matt Parker's original solution: https://github.com/standupmaths/fiveletterworda/

Benjamin Paassen's optimized solution: https://gitlab.com/bpaassen/five_clique

Matt Parker's original found 538 combinations of equivalence classes under anagrams, computed over approximately a month. This package reports the same 538 (earlier revisions of the package reported 540; the extra two were double-counts from a base-case off-by-one in the recursive search, not new cliques).

Benjamin Paassen's Python-based code found the combinations of all five-letter words (at least those without internally repeated letters), giving him 831 combinations, computed in approximately twenty minutes on my laptop. (This is also the result we get.)

```bash
$ time python generate_graph.py
--- reading words file ---
370105it [00:00, 1621336.98it/s]
--- building neighborhoods ---
100%|█████████████████████████████████████████| 10175/10175 [00:28<00:00, 359.17it/s]
--- write to output ---
100%|████████████████████████████████████████| 10175/10175 [00:02<00:00, 4416.99it/s]

real    0m31.578s
user    0m30.915s
sys     0m0.644s
$ time python five_clique.py
--- loading graph ---
10175it [00:03, 3068.66it/s]
--- start clique finding (THIS WILL TAKE LONG!) ---
100%|██████████████████████████████████████████| 10175/10175 [19:56<00:00,  8.50it/s]
completed! Found 831 cliques
--- write to output ---

real    20m0.672s
user    19m59.812s
sys     0m0.548s
```

**Total: approximately 20 minutes, 30 seconds**

*Timings based on the Python code at git commit #9587e1cd.*

## Julia FTW

This started off as a moderately optimized Julia program, but then I wanted to see how fast I could make it without doing really fancy things with the low-level representation of the adjacency matrix.
As such, it's a nice example of the power of Julia: you start off writing a program in a high-level language, much like
you would in Python or Matlab.
But unlike Python or Matlab where you have to start using a second language or libraries/functions wrapping things in a second language (e.g. NumPy), you just keep applying successive optimizations in Julia.
There are a bunch here, including

- words are represented as 26-bit `UInt32` letter masks, so the disjointness check for a pair of words is a single `(m1 & m2) == 0`
- the adjacency matrix is converted internally to a flat column-aligned `Vector{UInt64}` of 64-bit chunks, so intersection and "is bit set" checks run as `count_ones(c1 & c2)` and a single shifted AND
- when the search is dense enough that letters must be (almost) fully covered (e.g. five 5-letter words → 25 of 26 letters), the algorithm switches to a rarest-letter-first exact-cover branch-and-bound that visits each clique exactly once and ignores the adjacency matrix entirely
- threading via [`Polyester.jl`](https://juliasimd.github.io/Polyester.jl/stable/) and [SIMD](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data) hints via [`@simd`](https://docs.julialang.org/en/v1/base/base/#Base.SimdLoop.@simd)
- type-stable recursion via `NTuple{K,Int}` for the picked-vertex stack so the compiler specializes on recursion depth
- per-thread, depth-indexed pre-allocated chunk buffers reused across recursive calls

Despite these specializations and optimizations, the majority of the code is written in a fairly general style with comparatively few type constraints to allow users to use other data types.
Julia will nonetheless produce specialized methods for the types actually used.
**The main constraint is that the adjacency matrix and word list are assumed to be stored in 1-based linearly indexed arrays. If you violate this constraint, you may get errors, inaccurate results or even a segfault.**
So please, no [`StarWarsArrays`](https://github.com/giordano/StarWarsArrays.jl) or [`OffsetArrays`](https://github.com/JuliaArrays/OffsetArrays.jl).

I also took advantage of [`ProgressMeter.jl`](https://github.com/timholy/ProgressMeter.jl) to add nice progress meters to everything.

The clique-finding algorithm has two paths internally:

- For low-order searches (`order < 4`), the adjacency-matrix backtracking is still the right tool. It sorts vertices by degree (ascending) so that higher-degree, more interconnected words come later in the search, which improves short-circuiting on average. Sorting in the reverse order dramatically decreases performance because non-viability is noticed much later.
- For dense searches (`order * word_size <= 26` and `order >= 4`, e.g. order 5 over 5-letter words), `cliques!` switches to a rarest-letter-first exact-cover search over 26-bit letter masks. It picks the rarest still-uncovered letter at each level and branches over masks containing that letter (or, within budget, skips the letter). Anagrams collapse into a single branch and are expanded at emit time. On this path the adjacency-matrix argument is informational; the algorithm derives masks from the word list directly.

## Timings

For these, we use worst case timings (clean run in a new session, so the just-ahead-of-time compilation is included in the timings).
We use the shell's timing utility instead of Julia's `@time` for maximum comparability with the Python timings.
Julia's compilation model means that it often has noticeably worse startup times than Python, but you often gain that time back if you're doing repeated or otherwise nontrivial computations.

All times below were measured on Julia 1.10.11 on an 8-thread laptop.

### Excluding anagrams

```bash
$ time julia --project --threads=auto -e'using FiveLetterWorda; main();'
Computing adjacency matrix... 100%|██████████████████████████████████████████████████| Time: 0:00:00
[ Info: 538 combinations found

real    0m1.7s
```

**Total: approximately 1.7 seconds** (most of which is Julia startup and package precompile load; the actual search runs in tens of milliseconds — see `benchmark/baseline.md`).

### Including anagrams

```bash
$ time julia --project --threads=auto -e'using FiveLetterWorda; main(; exclude_anagrams=false);'
Computing adjacency matrix... 100%|██████████████████████████████████████████████████| Time: 0:00:00
[ Info: 831 combinations found

real    0m1.9s
```

**Total: approximately 1.9 seconds**

## Inspecting the results

There is a type `WordCombination` defined for representing word combinations in a nice way, including pretty printing.

```julia
julia> using FiveLetterWorda

julia> (; adj, words, combinations) = main(); # semicolon suppresses displaying the return value

julia> combinations[1] # Julia uses 1-based indexing
WordCombination with 5 words containing 25 distinct characters
Chars: abcdefghijklmnoprstuvwxyz
Words: birch, fldxt, gawky, numps, vejoz
```

There is also a method for saving the output to file. Note that the results are sorted before saving in order to make it easier to compare results, but the results returned by `cliques` and thus `main` are unsorted.
The ordering will likely differ between runs due to the use of multithreading.

## The impact of multithreading

Threading is still wired up via [`Polyester.jl`](https://juliasimd.github.io/Polyester.jl/stable/) for both adjacency matrix construction and the clique search. With the current algorithm the search runs in tens of milliseconds and Julia startup dominates total wall-clock time, so threading has only a small effect for `n=5, order=5` on a single run. It does still help for adjacency matrix construction and for larger problem sizes.

```bash
$ time julia --project --threads=1 -e'using FiveLetterWorda; main();'
[ Info: 538 combinations found

real    0m1.5s

$ time julia --project --threads=1 -e'using FiveLetterWorda; main(; exclude_anagrams=false);'
[ Info: 831 combinations found

real    0m2.1s
```


## Julia quick start

You'll need Julia 1.7+ to run the code here.
Note that the Julia REPL is pretty smart and you can copy and paste the lines below directly.
In other words, there's no need to strip out the `julia>` prompt; the REPL will do that for you.

```julia
julia> using Pkg

julia> Pkg.activate(".") # activate the current project in the current directory

julia> Pkg.instantiate() # install all dependencies

julia> using FiveLetterWorda

julia> (; adj, words, combinations) = main(); # semicolon suppresses displaying the return value

julia> combinations[1] # Julia uses 1-based indexing
WordCombination with 5 words containing 25 distinct characters
Chars: abcdefghijklmnoprstuvwxyz
Words: birch, fldxt, gawky, numps, vejoz

```
