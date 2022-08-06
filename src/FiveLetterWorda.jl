module FiveLetterWorda

using Arrow
using Downloads
using LinearAlgebra
using LoopVectorization
using Polyester
using ProgressMeter
using Scratch
using ZipFile

export main, WordCombination, nwords, nchars,
       adjacency_matrix, cliques!, five_letter_words,
       remove_anagrams, write_tab

const CACHE = Ref("")
const WORD_ZIP_URL = "https://github.com/dwyl/english-words/raw/master/words_alpha.zip"

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

Methods for [`union[!]`](@ref), [`intersect[!]`](@ref), [`push[!]`](@ref)
and [`in[!]`](@ref) are provided.

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
    words = convert(Vector{String}, tbl.words)
    # restrict ourselves to 5 letters
    filter!(x -> length(x) == 5, words)
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
    five_letter_words()

Return the set of five-letter words containing five unique letters.

Use [`remove_anagrams`](@ref) to remove anagrams.
"""
function five_letter_words()
    words = load_data()
    # remove words with repeated letters
    words = filter(x -> length(Set(x)) == 5, words)
    return words
end

#####
##### The Algorithm™
#####

# TODO: expose constraint on word length
"""
    main(; exclude_anagrams=true, adjacency_matrix_type=BitMatrix)

Do everything. 😉

Find the set of five five-letter words where each group of five words has
no shared letters between words.

If `exclude_anagrams=true`, then anagrams are removed from the word list
before finding the result.

You can specify the storage type of the adjaceny matrix with
`adjacency_matrix_type`. The default, `BitMatrix`, is very dense in memory,
packing eight vertices into a single byte. `Matrix{Bool}` stores one vertex per
byte and is thus 8 times as large, but noticably faster.
See also [`adjacency_matrix`](@ref)

Returns a named tuple of containing
- the adjacency matrix `adj` of words, i.e. the matrix of indicators for
  whether a given pair of words have no letters in common
- the vector of words used `words`
- the vector of [`WordCombination`](@ref)s found.
"""
function main(; exclude_anagrams=true, adjacency_matrix_type=BitMatrix)
    words = five_letter_words()
    if exclude_anagrams
        words = remove_anagrams(words)
    end
    adj = adjacency_matrix(words, adjacency_matrix_type)
    sets = cliques(adj, words)
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

function num_shared_neighbors(r1, r2, start=1)
    # this is an efficient, non allocating way to
    # compute the number of elements in the intersection
    s = 0
    length(r1) == length(r2) || throw(DimensionMismatch())
    @inbounds for i in start:length(r1)
        s += r1[i] * r2[i]
    end
    return s
end

const BoolRowView = SubArray{Bool, 1, Matrix{Bool}, Tuple{Base.Slice{Base.OneTo{Int}}, Int}, true}

function num_shared_neighbors(r1::BoolRowView, r2::BoolRowView, start=1)
    # this method is specialized on row-views of Matrix{Bool}
    # and takes advantage of LoopVectorization.@turbo for SIMD instructions
    s = 0
    length(r1) == length(r2) || throw(DimensionMismatch())
    @turbo for i in start:length(r1)
        s += r1[i] * r2[i]
    end
    return s
end

shared_neighbors(r1, r2, start=1) = @view(r1[start:end]) .* @view(r2[start:end])

"""
    cliques(adj, wordlist)

Find all five-cliques in the adjacency matrix `adj`.

The cliques are interpreted as entries in `wordlist` (so the adjacency
matrix should reflect the same ordering as `wordlist`) and the results
are then returned as the relevant words.
"""
cliques(adj, wordlist) = cliques!(Vector{Vector{String}}(), adj, wordlist)

"""
    cliques!(results::Vector{Vector{String}}, adj, wordlist)

Find all five-cliques in the adjacency matrix `adj`, storing the
result in `results`.

!!! warn
    `result` is emptied before being populated.

See also [`cliques`](@ref)
"""
function cliques!(results::Vector{Vector{String}}, adj, wordlist)
# TODO: turn this into a recursive call that allows find cliques of order n
    empty!(results)
    # sorting by degree so that more interconnected words come later
    # really really improves performance
    deg = sum(eachrow(adj))
    deg_sort = sortperm(deg; rev=false)
    adj = adj[deg_sort, deg_sort]
    wordlist = wordlist[deg_sort]

    ncols = size(adj, 2)
    p = Progress(ncols; showspeed=true, desc="Finding cliques...")
    @batch per=thread threadlocal=copy(results) for i in 1:ncols
    # for i in 1:ncols
        ri = @view(adj[:, i])
        for j in (i+1):ncols
            ri[j] || continue
            rj = @view(adj[:, j])
            num_shared_neighbors(ri, rj, j) < 3 && continue
            # only allocate if useful
            rj = shared_neighbors(ri, rj)
            for k in (j+1):ncols
                rj[k] || continue
                rk = @view(adj[:, k])
                num_shared_neighbors(rj, rk, k) < 2 && continue
                # only allocate if useful
                rk = shared_neighbors(rj, rk)
                for l in (k+1):ncols
                    rk[l] || continue
                    rl = @view(adj[:, l])
                    num_shared_neighbors(rk, rl, l) < 1 && continue
                    # only allocate if useful
                    rl = shared_neighbors(rk, rl)
                    ws = view(wordlist, rl)
                    for w in ws
                        rr = wordlist[[i, j, k, l]]
                        push!(rr, w)
                        push!(threadlocal, rr)
                    end
                end
            end
        end
        next!(p)
    end

    finish!(p)
    sizehint!(results, sum(length, threadlocal))
    for th in threadlocal
        append!(results, th)
    end

    @info "$(length(results)) combinations found"
    return results
end

"""
    adjacency_matrix(words, T::Type{<:AbstractMatrix}=BitMatrix)

Compute the adjacency matrix.

Default is `BitMatrix`, which is a memory dense format, but which
can be slower to read individual elements. Another alternative is
`Matrix{Bool}`, which is noticably faster for reading individual
elements but requires 8 times the storage space.
"""
function adjacency_matrix(words, T::Type{<:AbstractMatrix}=BitMatrix)
    adj = T(undef, length(words), length(words))
    fill!(adj, false) # init the diagonal; everything else is overwritten
    # fill!(view(adj, diagind(adj)), true)
    @showprogress "Computing adjacency matrix..." for i in 1:length(words), j in 1:(i-1)
        adj[j, i] = adj[i, j] = good_pair(words[i], words[j])
    end
    # why not make this Symmetric()? well, we don't do anything with methods
    # specialized on Symmetric and the view-based access pattern is slower
    # in some circumstances
    return adj
end

function adjacency_matrix(words, T::Type{Matrix{Bool}})
    # this method is specialized with a threading improvement and additional
    # broadcasting that works nicely for this storage type
    nw = length(words)
    adj = T(undef, nw, nw)
    fill!(adj, false) # init the diagonal; everything else is overwritten
    p = Progress(nw; showspeed=false, desc="Computing adjacency matrix...")
    @batch per=core for i in 1:nw
        j = 1:(i-1)
        adj[j, i] .= adj[i, j] .= good_pair.(Ref(words[i]), words[j])
        next!(p)
    end
    finish!(p)
    # why not make this Symmetric()? well, we don't do anything with methods
    # specialized on Symmetric and the view-based access pattern is slower
    # in some circumstances
    return adj
end

function good_pair(w1::String, w2::String)
    return isempty(intersect!(Set(w1), w2))
end

end # module
