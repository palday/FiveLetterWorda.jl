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

## Stage 2 — rarest-letter exact-cover search (`order >= 4`)

Changes:
- For `order * word_size <= 26` and `order >= 4`, `cliques!` dispatches
  to a 26-bit-mask exact-cover search that branches on the rarest
  still-uncovered letter at each level. Words sharing a letter mask
  (anagrams) are collapsed into a single branch and expanded at emit
  time via a cartesian product over the anagram groups.
- The adjacency matrix is no longer required by the clique search on
  this path; the `adj` argument is informational. The adjacency matrix
  is still built when `main` runs because the documented return
  NamedTuple includes it.
- Top-level branches (one per word containing the rarest letter, plus
  one "skip the rarest letter" branch when the skip budget allows) are
  parallelized with `@batch per=thread`.
- For `order < 4` (skip budget grows to 11+ letters and the search
  degenerates), `cliques!` continues to use the Stage 1 chunked-column
  backtracking path.

| Group              | Variant                       |  Stage 2 | vs Stage 0 |
| ------------------ | ----------------------------- | -------- | ---------- |
| `adjacency_matrix` | `Matrix{Bool}`, no_anagrams   |    50 ms |     12.5 × |
| `adjacency_matrix` | `Matrix{Bool}`, with_anagrams |   172 ms |     10.4 × |
| `adjacency_matrix` | `BitMatrix`, no_anagrams      |    94 ms |     13.0 × |
| `adjacency_matrix` | `BitMatrix`, with_anagrams    |   278 ms |     11.5 × |
| `cliques`          | `Matrix{Bool}`, no_anagrams   |    78 ms |    122   × |
| `cliques`          | `Matrix{Bool}`, with_anagrams |    62 ms |    496   × |
| `cliques`          | `BitMatrix`, no_anagrams      |    56 ms |   1233   × |
| `cliques`          | `BitMatrix`, with_anagrams    |    64 ms |   3714   × |
| `main`             | `Matrix{Bool}`, no_anagrams   |   158 ms |     64.4 × |
| `main`             | `Matrix{Bool}`, with_anagrams |   280 ms |    112.6 × |

Observations:
- The clique search is now O(letter-frequency-tree depth) rather than
  O(dense adjacency intersection) and runs in tens of milliseconds.
- Adjacency matrix construction is the dominant cost of `main`, but it
  is only there because the documented return value includes it; the
  algorithm itself does not need it on the order-5 path.
- The `cliques` numbers above pass an adjacency matrix in even though
  the order-5 path ignores it. The pass-through cost is one Dict build
  and `letter_mask` over the word list, both already cheap.
