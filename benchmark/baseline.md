# Benchmark baselines

Captured median runtimes from `benchmark/bench.jl`. Each row is the median of
3 samples, 1 second budget, 1 evaluation per sample.

Update this file at the end of each optimization stage so the progression
is visible.

## System

- Julia 1.10.11
- 8 threads
- 5-letter words (no anagrams): 5976 words
- 5-letter words (with anagrams): 10175 words

## Stage 0 — baseline (unmodified source)

| Group              | Variant                       | Median   |
| ------------------ | ----------------------------- | -------- |
| `adjacency_matrix` | `Matrix{Bool}`, no_anagrams   |   627 ms |
| `adjacency_matrix` | `Matrix{Bool}`, with_anagrams | 1.785 s  |
| `adjacency_matrix` | `BitMatrix`, no_anagrams      | 1.225 s  |
| `adjacency_matrix` | `BitMatrix`, with_anagrams    | 3.202 s  |
| `cliques`          | `Matrix{Bool}`, no_anagrams   | 9.534 s  |
| `cliques`          | `Matrix{Bool}`, with_anagrams | 30.735 s |
| `cliques`          | `BitMatrix`, no_anagrams      | 69.035 s |
| `cliques`          | `BitMatrix`, with_anagrams    | 237.7 s  |
| `main`             | `Matrix{Bool}`, no_anagrams   | 10.181 s |
| `main`             | `Matrix{Bool}`, with_anagrams | 31.516 s |

Observations:
- `cliques` on `BitMatrix` is 7–8× slower than on `Matrix{Bool}` because the
  inner Bool-by-Bool indexing on a BitArray goes through `getindex` per bit
  instead of using `.chunks` directly.
- `cliques` dominates total runtime. `adjacency_matrix` is a secondary cost.
