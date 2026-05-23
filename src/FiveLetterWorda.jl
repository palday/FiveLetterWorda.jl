module FiveLetterWorda

using Arrow
using Downloads
using LinearAlgebra
using Polyester
using PrecompileTools
using ProgressMeter
using Scratch
using ZipFile

export main, WordCombination, nwords, nchars,
       adjacency_matrix, cliques, cliques!, 
       remove_anagrams, write_tab

const CACHE = Ref("")
const WORD_ZIP_URL = "https://github.com/dwyl/english-words/raw/a77cb15f4f5beb59c15b945f2415328a6b33c3b0/words_alpha.zip"

clear_scratchspaces!() = Scratch.clear_scratchspaces!(@__MODULE__)

"""
    WordCombination
    WordCombination()
    WordCombination(w::String)
    WordCombination(ws::AbstractVector{String})

A conveniencce data type for a set of words and associated characters.

Fields:
- `chars::Set{Char}`
- `words::Set{String}`

Methods for [`union`](@ref), [`intersect`](@ref), [`push!`](@ref)
and [`in`](@ref) are provided.

See also [`nwords`](@ref) and [`nchars`](@ref).
"""
struct WordCombination <: AbstractSet{String}
    chars::Set{Char}
    words::Set{String}
end

"""
    nwords(wc::WordCombination)

Return the number of words in a `wc`.

See also [`nchars`](@ref).
"""
nwords(wc::WordCombination) = length(wc.words)

"""
    nchars(wc::WordCombination)

Return the number of characters in a `wc`.

See also [`nwords`](@ref).
"""
nchars(wc::WordCombination) = length(wc.chars)

WordCombination() = WordCombination(Set{Char}(), Set{String}())
WordCombination(w::String) = WordCombination(Set{Char}(w), Set{String}([w]))

function Base.show(io::IO, wc::WordCombination)
    println(io, "WordCombination with $(nwords(wc)) words " *
            "containing $(nchars(wc)) distinct characters")

    println(io, "Chars: ", join(sort!(collect(wc.chars))))
    println(io, "Words: ", join(sort!(collect(wc.words)), ", "))
    return nothing
end

function WordCombination(ws::Union{AbstractSet{String}, AbstractVector{String}})
    chars = mapreduce(Set, union!, ws; init=Set{Char}())
    return WordCombination(chars, Set{String}(ws))
end

#####
##### Set-like operations
#####

Base.length(wc::WordCombination) = nwords(wc)
Base.in(w::String, wc::WordCombination) = w in wc.words
Base.in(c::Char, wc::WordCombination) = c in wc.chars
Base.isempty(wc::WordCombination) = isempty(wc.words)
Base.iterate(wc::WordCombination, args...) = iterate(wc.words, args...)
Base.display(wc::WordCombination) = show(stdout, wc)

function Base.:(==)(w1::WordCombination, w2::WordCombination)
    return w1.words == w2.words
end

function Base.empty!(wc::WordCombination)
    empty!(wc.words)
    empty!(wc.chars)
    return wc
end

function Base.intersect(w1::WordCombination, w2::WordCombination)
    words = intersect(w1.words, w2.words)
    return WordCombination(words)
end

function Base.intersect!(w1::WordCombination, w2::WordCombination)
    intersect!(w1.words, w2.words)
    mapreduce(Set, intersect!, w2.words; init=w1.chars)
    return w1
end

function Base.push!(wc::WordCombination, w::String)
    union!(wc.chars, Set(w))
    push!(wc.words, w)
    return wc
end

function Base.setdiff(w1::WordCombination, w2::WordCombination)
    words = setdiff(w1.words, w2.words)
    return WordCombination(words)
end

function Base.setdiff!(w1::WordCombination, w2::WordCombination)
    setdiff!(w1.words, w2.words)
    mapreduce(Set, union!, w1.words; init=empty!(w1.chars))
    return w1
end

function Base.symdiff(w1::WordCombination, w2::WordCombination)
    words = symdiff(w1.words, w2.words)
    return WordCombination(words)
end

function Base.symdiff!(w1::WordCombination, w2::WordCombination)
    symdiff!(w1.words, w2.words)
    mapreduce(Set, union!, w1.words; init=empty!(w1.chars))
    return w1
end

function Base.union(w1::WordCombination, w2::WordCombination)
    chars = union(w1.chars, w2.chars)
    words = union(w1.words, w2.words)
    return WordCombination(chars, words)
end

function Base.union!(w1::WordCombination, w2::WordCombination)
    union!(w1.chars, w2.chars)
    union!(w1.words, w2.words)
    return w1
end

function Base.isdisjoint(w1::WordCombination, w2::WordCombination)
    return isdisjoint(w1.words, w2.words)
end

#####
##### Data loading
#####

function __init__()
    CACHE[] = @get_scratch!("data")
end

_fname() = joinpath(CACHE[], "words_alpha.arrow")

# the zipped version is far smaller so we download that for speed
# it is missing a few things in the current unzipped file, but
# none that are 5 letters long
# diff words_alpha.txt words_alpha.zip.txt
# 561d560
# < abled
# 1440a1440
# > acceleratorh
# 73224d73223
# < cryptocurrency
# 198697d198695
# < nerdy
# 298304,298306d298301
# < spam
# < spammed
# < spamming
# 327928d327922
# < transgender
function download_data()
    @info "Downloading data"
    open(Downloads.download(WORD_ZIP_URL), "r") do io
        zipfile = ZipFile.Reader(io)
        compressed = only(zipfile.files)
        @info "Saving data to compressed local storage"
        Arrow.write(_fname(), (; words=readlines(compressed)); compress=:lz4)
        return nothing
    end
    return nothing
end

function load_data()
    f = _fname()
    isfile(f) || download_data()
    tbl = Arrow.Table(f)
    return tbl.words
end

"""
    remove_anagrams(words::Vector{String})

Remove all anagrams from `words`.

This reduces the set of words to the set of equivalence classes under the
operation "anagram". The representative member from each class is just the
first word encountered from that class. If the vector is sorted
lexicographically, then this is just the anagram that comes first in the
alphabet.
"""
remove_anagrams(words::Vector{String}) = unique(Set, words)

"""
    n_letter_words()

Return the set of n-letter words containing n unique letters.

Use [`remove_anagrams`](@ref) to remove anagrams.
"""
function n_letter_words(n::Int)
    words = filter(x -> length(x) == n, load_data())
    # remove words with repeated letters
    words = filter!(x -> length(Set(x)) == n, words)
    return words
end

#####
##### The Algorithm™
#####

# TODO: expose constraint on word length
"""
    main(n=5; exclude_anagrams=true,
        adjacency_matrix_type=Matrix{Bool}, order=fld(26, n),
        progress=true)

Do everything. 😉

Find the set of groups of `order` `n`-letter words where each group of words
has no shared letters between words.

If `exclude_anagrams=true`, then anagrams are removed from the word list
before finding the result.

You can specify the storage type of the adjacency matrix with
`adjacency_matrix_type`. `BitMatrix` is very dense in memory,
packing eight vertices into a single byte. `Matrix{Bool}` stores one vertex
per byte and is thus 8× as large but slightly faster to construct. The
clique-finding algorithm converts whichever storage you pick to an
internal chunked representation, so the choice no longer affects search
performance — it only affects the construction cost and the size of the
returned matrix. See also [`adjacency_matrix`](@ref).

The `order` specifies the order of cliques to find and defaults to
`fld(26, n)`, i.e. the maximal possible order for a given word length.
Note that cliques of lower order are more common, so there are **many**
more of them.

Returns a named tuple of containing
- the adjacency matrix `adj` of words, i.e. the matrix of indicators for
  whether a given pair of words have no letters in common
- the vector of words used `words`
- the vector of [`WordCombination`](@ref)s found.
"""
function main(n::Int=5; exclude_anagrams=true, adjacency_matrix_type=Matrix{Bool},
              order=fld(26, n), progress=true)
    words = n_letter_words(n)
    if exclude_anagrams
        words = remove_anagrams(words)
    end
    adj = adjacency_matrix(words, adjacency_matrix_type; progress)
    sets = cliques(adj, words, order; progress)
    return (; adj, words, combinations=WordCombination.(sets))
end

function write_tab(fname, wcs::Vector{WordCombination})
    # XXX this is very inefficient but nothing here is so huge in memory
    # that I'm really worried about it
    return write_tab(fname, collect.(getproperty.(wcs, :words)))
end

"""
    write_tab(fname, wcs::Vector{Vector{String}})
    write_tab(fname, wcs::Vector{WordCollection})

Write the results out to a tab delimited file.
"""
function write_tab(fname, wcs::Vector{Vector{String}})
    wcs = sort!(sort.(wcs))
    open(fname, "w") do io
        for combi in wcs
            println(io, join(combi, "\t"))
        end
        return nothing
    end
    return nothing
end

# Column-chunked bit representation of an adjacency matrix. The neighborhood
# of vertex `j` is a `Cpc`-long view into `data` (`Cpc = cld(n, 64)` chunks
# per column). Each column is 64-bit aligned, so chunk-level AND and
# popcount can be applied directly without worrying about cross-column
# boundary bits.
struct ColumnChunks
    data::Vector{UInt64}
    Cpc::Int
    n::Int
end

ColumnChunks(n::Int) = ColumnChunks(zeros(UInt64, cld(n, 64) * n), cld(n, 64), n)

function ColumnChunks(adj::AbstractMatrix{Bool})
    n = size(adj, 2)
    @assert size(adj, 1) == n
    cc = ColumnChunks(n)
    @batch per=core for j in 1:n
        base = (j - 1) * cc.Cpc
        @inbounds for i in 1:n
            if adj[i, j]
                cc.data[base + ((i - 1) >> 6) + 1] |= UInt64(1) << ((i - 1) & 63)
            end
        end
    end
    return cc
end

@inline column(cc::ColumnChunks, j::Int) =
    view(cc.data, ((j - 1) * cc.Cpc + 1):(j * cc.Cpc))

# Count set bits in `c1 .& c2`, restricted to bit positions >= start_bit
# (1-based). `start_bit > n` is allowed and returns 0.
function num_shared_neighbors_chunks(c1, c2, start_bit::Int)
    Cpc = length(c1)
    k0 = ((start_bit - 1) >> 6) + 1
    k0 > Cpc && return 0
    b0 = (start_bit - 1) & 63
    # bits at positions >= b0 within the first chunk
    mask0 = ~UInt64(0) << b0
    s = count_ones(c1[k0] & c2[k0] & mask0)
    @inbounds @simd for k in (k0 + 1):Cpc
        s += count_ones(c1[k] & c2[k])
    end
    return s
end

function shared_neighbors_chunks!(out, c1, c2)
    @inbounds @simd for k in eachindex(out, c1, c2)
        out[k] = c1[k] & c2[k]
    end
    return out
end

# Invoke `f(i)` for every 1-based vertex index whose bit is set in `c`,
# bounded by `n` (the logical vertex count).
@inline function foreach_set_bit(f, c::AbstractVector{UInt64}, n::Int)
    Cpc = length(c)
    @inbounds for k in 1:Cpc
        chunk = c[k]
        while chunk != UInt64(0)
            b = trailing_zeros(chunk)
            i = (k - 1) * 64 + b + 1
            i > n && return nothing
            f(i)
            chunk &= chunk - UInt64(1)
        end
    end
    return nothing
end

"""
    cliques(adj, wordlist, order=5; progress=true)

Find all five-cliques in the adjacency matrix `adj`.

The cliques are interpreted as entries in `wordlist` (so the adjacency
matrix should reflect the same ordering as `wordlist`) and the results
are then returned as the relevant words.
"""
cliques(adj, wordlist, order=5; progress=true) =
    cliques!(Vector{Vector{String}}(), adj, wordlist, order; progress)

"""
    cliques!(results::Vector{Vector{String}}, adj, wordlist, order=5;
             progress=true)

Find all `order`-cliques in the adjacency matrix `adj`, storing the
result in `results`.

!!! warn
    `result` is emptied before being populated.

See also [`cliques`](@ref)
"""
function cliques!(results::Vector{Vector{String}}, adj, wordlist, order::Int=5; progress=true)
    order < 2 && throw(ArgumentError("Cliques of order < 2 are just vertices"))
    empty!(results)
    # sorting by degree so that more interconnected words come later
    # really really improves performance
    deg = vec(sum(adj; dims=1))
    deg_sort = sortperm(deg; rev=false)
    adj = adj[deg_sort, deg_sort]
    wordlist = wordlist[deg_sort]

    cc = ColumnChunks(adj)
    n = cc.n
    Cpc = cc.Cpc
    depth0 = order - 1

    p = Progress(n; showspeed=true, desc="Finding cliques...", enabled=progress, barlen=50)
    @batch per=thread stride=true threadlocal=(
        results=copy(results),
        bufs=[Vector{UInt64}(undef, Cpc) for _ in 1:max(depth0 - 1, 1)],
    ) for i in 1:n
        _clique_search!(
            threadlocal.results, cc, wordlist, depth0, column(cc, i), (i,),
            threadlocal.bufs,
        )
        next!(p)
    end

    finish!(p)
    results = reduce(vcat, (t.results for t in threadlocal))

    progress && @info "$(length(results)) combinations found"
    return results
end

# Internal recursive worker. `members` is a small NTuple of already-picked
# vertex indices (so K is the count picked so far); `depth` counts the
# number of additional vertices still to pick. We branch on the next
# vertex `i > last(members)` that is still in the intersection
# `prev_row` of all picked neighborhoods. `bufs` is a stack of pre-
# allocated chunk buffers, indexed by the remaining depth.
function _clique_search!(
    results::Vector{Vector{String}},
    cc::ColumnChunks,
    wordlist,
    depth::Int,
    prev_row::AbstractVector{UInt64},
    members::NTuple{K,Int},
    bufs::Vector{Vector{UInt64}},
) where {K}
    n = cc.n
    offset = members[K]
    if depth == 1
        # Base case: every set bit in `prev_row` at position > offset is a
        # valid completion of the clique.
        wlist = wordlist
        m = members
        foreach_set_bit(prev_row, n) do i
            i > offset || return nothing
            push!(results, _emit(wlist, m, i))
            return nothing
        end
        return results
    end
    row = bufs[depth - 1]
    @inbounds for i in (offset + 1):n
        # `prev_row[i]` set?
        if (prev_row[((i - 1) >> 6) + 1] >> ((i - 1) & 63)) & UInt64(1) == 0
            continue
        end
        ci = column(cc, i)
        num_shared_neighbors_chunks(prev_row, ci, i) < depth - 1 && continue
        shared_neighbors_chunks!(row, prev_row, ci)
        _clique_search!(results, cc, wordlist, depth - 1, row, (members..., i), bufs)
    end
    return results
end

# Build a clique result vector from `(members..., last)` without
# intermediate index allocations.
@inline function _emit(wordlist, members::NTuple{K,Int}, last::Int) where {K}
    out = Vector{eltype(wordlist)}(undef, K + 1)
    @inbounds for k in 1:K
        out[k] = wordlist[members[k]]
    end
    @inbounds out[K + 1] = wordlist[last]
    return out
end

# A 26-bit letter set as a UInt32: bit (c - 'a') is set iff `c` is in the
# word. Disjointness of two words reduces to `(m1 & m2) == 0`.
function letter_mask(w::AbstractString)
    m = UInt32(0)
    for c in w
        m |= UInt32(1) << (UInt32(c) - UInt32('a'))
    end
    return m
end

"""
    adjacency_matrix(words, T::Type{<:AbstractMatrix}=BitMatrix; progress=true)

Compute the adjacency matrix.

Default is `BitMatrix`, which is a memory dense format, but which
can be slower to read individual elements. Another alternative is
`Matrix{Bool}`, which is noticably faster for reading individual
elements but requires 8 times the storage space.
"""
function adjacency_matrix(words, T::Type{<:AbstractMatrix}=BitMatrix; progress=true)
    nw = length(words)
    adj = T(undef, nw, nw)
    fill!(adj, false) # init the diagonal; everything else is overwritten
    masks = letter_mask.(words)
    @showprogress enabled=progress barlen=50 "Computing adjacency matrix..." for i in 1:nw, j in 1:(i-1)
        adj[j, i] = adj[i, j] = (masks[i] & masks[j]) == 0
    end
    # why not make this Symmetric()? well, we don't do anything with methods
    # specialized on Symmetric and the view-based access pattern is slower
    # in some circumstances
    return adj
end

function adjacency_matrix(words, T::Type{Matrix{Bool}}; progress=true)
    # this method is specialized with a threading improvement that works
    # nicely for this storage type
    nw = length(words)
    adj = T(undef, nw, nw)
    fill!(adj, false) # init the diagonal; everything else is overwritten
    masks = letter_mask.(words)
    p = Progress(nw; showspeed=false, desc="Computing adjacency matrix...", enabled=progress, barlen=50)
    @batch per=core for i in 1:nw
        mi = masks[i]
        @inbounds for j in 1:(i-1)
            adj[j, i] = adj[i, j] = (mi & masks[j]) == 0
        end
        next!(p)
    end
    finish!(p)
    # why not make this Symmetric()? well, we don't do anything with methods
    # specialized on Symmetric and the view-based access pattern is slower
    # in some circumstances
    return adj
end

good_pair(w1, w2) = isdisjoint(w1, w2)

@compile_workload begin
    for exclude_anagrams in [true, false],
        adjacency_matrix_type in [Matrix{Bool}, BitMatrix]
        # 10 letter words are rare, so there isn't a huge list to deal with
        # and we also can't examine cliques bigger than 2, so we don't
        # have to recurse deeply
        main(10; exclude_anagrams, adjacency_matrix_type, progress=false)
    end
end

end # module
