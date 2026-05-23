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

## Stage 1 — UInt32 masks + chunked column representation

Changes:
- `adjacency_matrix` precomputes `UInt32` letter masks and uses
  `(m1 & m2) == 0` for the disjointness check.
- `cliques` internally converts the adjacency matrix to a flat
  `ColumnChunks` (column-aligned 64-bit chunks). The recursive search
  operates on chunks with `count_ones(c1 & c2)` and chunked AND.
- The recursive worker is type-stabilized on the picked-vertex tuple
  via `NTuple{K,Int}`.
- Per-thread chunk buffers are pre-allocated once at the outer parallel
  loop boundary and indexed by remaining depth.
- The base-case emit allocates a single `Vector{String}` per clique
  via `_emit`, removing the intermediate `idx` allocation.

Also fixed a longstanding over-counting bug: previous versions reported
540 cliques for `n=5, exclude_anagrams=true` because the base case
enumerated every set bit in the neighborhood intersection (including
indices < the most-recent pick), emitting 2 cliques twice. Matt
Parker's count of 538 was actually correct; this implementation now
reports 538 by walking every clique in strictly increasing index order.

| Group              | Variant                       |  Stage 1 | vs Stage 0 |
| ------------------ | ----------------------------- | -------- | ---------- |
| `adjacency_matrix` | `Matrix{Bool}`, no_anagrams   |    53 ms |     11.9 × |
| `adjacency_matrix` | `Matrix{Bool}`, with_anagrams |   174 ms |     10.3 × |
| `adjacency_matrix` | `BitMatrix`, no_anagrams      |    97 ms |     12.6 × |
| `adjacency_matrix` | `BitMatrix`, with_anagrams    |   287 ms |     11.1 × |
| `cliques`          | `Matrix{Bool}`, no_anagrams   |  3.208 s |      3.0 × |
| `cliques`          | `Matrix{Bool}`, with_anagrams |  9.441 s |      3.3 × |
| `cliques`          | `BitMatrix`, no_anagrams      |  3.431 s |     20.1 × |
| `cliques`          | `BitMatrix`, with_anagrams    |  9.786 s |     24.3 × |
| `main`             | `Matrix{Bool}`, no_anagrams   |  3.539 s |      2.9 × |
| `main`             | `Matrix{Bool}`, with_anagrams | 10.236 s |      3.1 × |

Observations:
- `cliques` is now insensitive to `adjacency_matrix_type` (both go
  through `ColumnChunks`), removing the prior recommendation that
  callers should choose `Matrix{Bool}` for speed.
- The clique search is now the only nontrivial cost; adjacency
  construction dropped to ~5% of total `main` runtime.
- Cleared the per-bit `getindex` overhead that previously made the
  `BitMatrix` path 7× slower than `Matrix{Bool}` (now equivalent).
