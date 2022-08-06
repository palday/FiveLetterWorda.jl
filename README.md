# FiveLetterWorda.jl

Inspired by: https://github.com/standupmaths/fiveletterworda/

See also a similar idea done in Python: https://gitlab.com/bpaassen/five_clique

This is a moderately optimized Julia program. We could probably optimize things a bit more, but it doesn't seem worth the effort. We use views throughout in order to reduce allocations and access arrays in column-major order.
(Unlike NumPy, Julia is column-major.) The adjacency matrix is sorted by degree, so that higher degree nodes are searched later. This dramatically improves performance -- my hypothesis is that this leads to earlier "short-circuiting" on average, i.e., realizing that a clique-candiate is nonviable sooner. Sorting the adjacency matrix in the reverse order dramatically decreases performance because it takes much longer to realize that a clique is nonviable.

Here's a worst-case timing run (clean run in a new session, so you the just-ahead-of-time compilation is included in the timings):

```julia
julia> @time begin
              using FiveLetterWorda
              (; adj, words, combinations) = main()
              end;
[ Info: Precompiling FiveLetterWorda [40c3fe41-db9e-4ab5-a060-da035752fe98]
Computing adjacency matrix... 100%|███████████████████████████████████████████| Time: 0:00:11
Finding cliques... 100%|████████████████████████████████████████| Time: 0:00:55 ( 9.34 ms/it)
[ Info: 540 combinations found
 83.312460 seconds (213.71 M allocations: 59.940 GiB, 8.21% gc time, 13.73% compilation time)
```

This is fast enough that we can even include anagrams if do desired (run in the same session as the previous):
```julia
julia> @time begin
              using FiveLetterWorda
              (; adj, words, combinations) = main(; exclude_anagrams=false)
              end;
Computing adjacency matrix... 100%|███████████████████████████████████████████| Time: 0:00:33
Finding cliques... 100%|████████████████████████████████████████| Time: 0:03:10 (18.70 ms/it)
[ Info: 831 combinations found
225.831852 seconds (475.65 M allocations: 136.695 GiB, 6.03% gc time, 0.30% compilation time)
```

For that timing run, I used 8 threads on a 4-core 11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz.
This corresponds to the default behavior with `julia --threads=auto`, with 2 threads per hyperthreaded core. See below for more information.

The adjacency matrix computation is quite fast and efficient in memory because we use `BitArray`s to pack 8 vertices in a single byte. Here, we show the adjaceny matrix _without anagrams_.
```julia
julia> Base.summarysize(adj) # approximate size in bytes
4464160

julia> length(adj) / Base.summarysize(adj)
7.999842299559155
```

Somewhat surprisingly, the pairwise connectivity is quite high:
```julia
julia> sparse(adj)
5976×5976 SparseMatrixCSC{Bool, Int64} with 6425280 stored entries:
⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣀⣀⣀⠘⠛⢛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⢀⣀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⠀⠀⢸⣿⣿⣿⣿⣿⣿⣯⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣶⣶⣾⠛⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣾⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⣀⡸⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣷⣿⣿⣿⣿⣿⣿⣿⣿⣷⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⠛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣻⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣀⣸⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡏⠉⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⡿

julia> using Statistics

julia> mean(count, eachrow(adj))
1075.1807228915663
```

There is a type `WordCombination` defined for representing word combinations in a nice way, including pretty printing.

```julia
julia> combinations[end]
WordCombination with 5 words containing 25 distinct characters
Chars: abcdefghijklmnoprstuvwxyz
Words: comps, fldxt, jarvy, uzbek, whing
```

## Julia quick start

You'll need Julia 1.7+ to run the code here.
Note that the Julia REPL is pretty smart and you can copy and paste the lines below directly.
In other words, there's no need to strip out the `julia>` prompt; the REPL will do that for you.

```julia
julia> using Pkg

julia> Pkg.activate(".") # activate the current project in the current director

julia> Pkg.instantiate() # install all dependencies

julia> using FiveLetterWorda

julia> (; adj, words, combinations) = main(); # semicolon suppresses displaying the return value

julia> combinations[1] # Julia uses 1-based indexing
WordCombination with 5 words containing 25 distinct characters
Chars: abcdefghijklmnoprstuvwxyz
Words: birch, fldxt, gawky, numps, vejoz

```

We take advantage of multithreading to speed things up. You'll need to start Julia with the `--threads=auto` (or whatever number of threads you want to use). If you're using VSCode or the like, you can set this via preferences.

If we disable threading (i.e., don't specify `--threads` or set `--threads=1`), then performance suffers quite a bit (runtime essentially doubles):

```julia
julia> @time begin
              using FiveLetterWorda
              (; adj, words, combinations) = main()
              end;
Computing adjacency matrix... 100%|██████████████████████████████████████████| Time: 0:00:11
Finding cliques... 100%|███████████████████████████████████████| Time: 0:02:29 (25.02 ms/it)
[ Info: 540 combinations found
173.556632 seconds (211.81 M allocations: 59.816 GiB, 2.76% gc time, 6.31% compilation time)
```


```julia
julia> @time begin
              using FiveLetterWorda
              (; adj, words, combinations) = main(; exclude_anagrams=false)
              end;
Computing adjacency matrix... 100%|███████████████████████████████████████████| Time: 0:00:36
Finding cliques... 100%|████████████████████████████████████████| Time: 0:07:58 (47.05 ms/it)
[ Info: 831 combinations found
528.429535 seconds (515.71 M allocations: 142.489 GiB, 2.12% gc time, 2.08% compilation time)
```
