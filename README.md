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

Note that Matt Parker's original only found the combinations of equivalence classes under anagrams, giving him 538 combinations, computed over approximately a month. (However, I think he missed two, see below.)

Benjamin Paassen's Python-based code found the combinations of all five-letter words (at least those without internally repeated letters), giving him 831 combinations, computed in approximately twenty minutes on my laptop. (This is also the result I get.)

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

This started off as a moderately optimized Julia program, but then I wanted to see how fast I could make it without doing really fancy things with the low-level representation of the adjaceny matrix.
As such, it's a nice example of the power of Julia: you start off writing a program in a high-level language, much like
you would in Python or Matlab.
But unlike Python or Matlab where you have to start using a second language or libraries/functions wrapping things in a second language (e.g. NumPy), you just keep applying successive optimizations in Julia.
There are a bunch here, including

- the use of views to avoid unnecessary memory allocations
- access arrays in column-major order (Julia is column-major, unlike NumPy, which is row-major)
- a few optimized loops including
    - disabling of bounds checks in a tight inner loop via `@inbounds` (after a dimensionality check)
    - threading via [`Polyester.jl`](https://juliasimd.github.io/Polyester.jl/stable/) and
    - [SIMD](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data) operations via [`@simd`](https://docs.julialang.org/en/v1/base/base/#Base.SimdLoop.@simd).
- method specialization to enable optimizations only available on certain datatypes, which allows choosing between space and computation time for `BitMatrix` and `Matrix{Bool}`.

Despite these specializations and optimizations, the majority of the code is written in a fairly general style with comparatively few type constraints to allow users to use other data types.
Julia will nonetheless produce specialized methods for the types actually used.
**The main constraint is that the adjacency matrix and word list are assumed to be stored in 1-based linearly indexed arrays. If you violate this constraint, you may get errors, inaccurate results or even a segfault.**
So please, no [`StarWarsArrays`](https://github.com/giordano/StarWarsArrays.jl) or [`OffsetArrays`](https://github.com/JuliaArrays/OffsetArrays.jl).

I also took advantage of [`ProgressMeter.jl`](https://github.com/timholy/ProgressMeter.jl) to add nice progress meters to everything.

I originally wrote everything as a series of nested loops, but moved things over to a more general recursive call (hidden from the user) to allow for a more general approach that kind find cliques of arbitrary order.
Nonetheless, performance is still quite good (see below).

Internally, the main clique-finding functions sorts the adjacency matrix by degree before searching cliques, so that higher degree nodes are searched later.
(The function `adjacency_matrix` returns the adjacency matrix in the same order as the provided word list so that the row/column indices of the matrix map directly to indices in the word list.)
This dramatically improves performance -- my hypothesis is that this leads to earlier "short-circuiting" on average, i.e., realizing that a clique-candiate is nonviable sooner.
Sorting the adjacency matrix in the reverse order dramatically decreases performance because it takes much longer to realize that a clique is nonviable.

## Timings

For these, we use worst case timings (clean run in a new session, so the just-ahead-of-time compilation is included in the timings).
We use the shell's timing utility instead of Julia's `@time` for maximum comparability with the Python timings.
Julia's compilation model means that it often has noticeably worse startup times than Python, but you often gain that time back if you're doing repeated or otherwise nontrivial computations.

All times were done on the following system:

```julia
julia> versioninfo()
Julia Version 1.10.3
Commit 0b4590a5507 (2024-04-30 10:59 UTC)
Build Info:
  Official https://julialang.org/ release
Platform Info:
  OS: Linux (x86_64-linux-gnu)
  CPU: 16 × Intel(R) Xeon(R) E-2288G CPU @ 3.70GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, skylake)
Threads: 16 default, 0 interactive, 8 GC (on 16 virtual cores)
```

### Excluding anagrams

```bash
$ time julia --project --threads=auto -e'using FiveLetterWorda; main();'
Computing adjacency matrix... 100%|██████████████████████████████████████████████████| Time: 0:00:01
Finding cliques... 100%|██████████████████████████████████████████████████| Time: 0:00:04 ( 0.73 ms/it)
[ Info: 540 combinations found

real    0m6.738s
user    0m45.099s
sys     0m3.794s
```

**Total: approximately 7 seconds**

### Including anagrams

```bash
Computing adjacency matrix... 100%|██████████████████████████████████████████████████| Time: 0:00:01
Finding cliques... 100%|██████████████████████████████████████████████████| Time: 0:00:12 ( 1.18 ms/it)
[ Info: 831 combinations found

real    0m15.158s
user    2m9.641s
sys     0m9.119s
```

**Total: approximately 15 seconds**

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

We take advantage of multithreading to speed things up. You'll need to start Julia with the `--threads=auto` (or whatever number of threads you want to use). If you're using VSCode or the like, you can set this via preferences.

If we disable threading (i.e., don't specify `--threads` or set `--threads=1`), then performance suffers quite a bit (runtime increases dramatically, but scales less than linearly with the number of threads):

### Excluding anagrams

```bash
$ time julia --project --threads=1 -e'using FiveLetterWorda; main();'
Computing adjacency matrix... 100%|██████████████████████████████████████████████████| Time: 0:00:01
Finding cliques... 100%|██████████████████████████████████████████████████| Time: 0:00:50 ( 8.49 ms/it)
[ Info: 540 combinations found

real    0m54.032s
user    0m53.995s
sys     0m0.551s
```

**Total: approximately 54 seconds**

### Including anagrams

```bash
$ time julia --project --threads=1 -e'using FiveLetterWorda; main(; exclude_anagrams=false);'
Computing adjacency matrix... 100%|██████████████████████████████████████████████████| Time: 0:00:03
Finding cliques... 100%|██████████████████████████████████████████████████| Time: 0:02:35 (15.33 ms/it)
[ Info: 831 combinations found

real    2m41.330s
user    2m39.746s
sys     0m2.108s
```

**Total: approximately 2 minutes, 41 seconds**


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
