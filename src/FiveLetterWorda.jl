module FiveLetterWorda

using Arrow
using Downloads
using LinearAlgebra
using LoopVectorization
using Polyester
using PrecompileTools
using ProgressMeter
using Scratch
using ZipFile

export main, WordCombination, nwords, nchars,
       adjacency_matrix, cliques, cliques!, five_letter_words,
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

You can specify the storage type of the adjaceny matrix with
`adjacency_matrix_type`. `BitMatrix`, is very dense in memory,
packing eight vertices into a single byte. `Matrix{Bool}` stores one vertex per
byte and is thus 8 times as large, but noticably faster.
See also [`adjacency_matrix`](@ref)

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

function num_shared_neighbors(r1, r2, start=1)
    # this is an efficient, non allocating way to
    # compute the number of elements in the intersection
    s = 0
    length(r1) == length(r2) > 0 || throw(DimensionMismatch())
    @inbounds for i in start:length(r1)
        s += r1[i] * r2[i]
    end
    return s
end

const BoolRowView =
    SubArray{Bool, 1, Matrix{Bool}, Tuple{Base.Slice{Base.OneTo{Int}}, Int}, true}

function num_shared_neighbors(r1::BoolRowView, r2::BoolRowView, start=1)
    # this method is specialized on row-views of Matrix{Bool}
    # and takes advantage of LoopVectorization.@turbo for SIMD instructions
    s = 0
    length(r1) == length(r2) > 0 || throw(DimensionMismatch())
    @turbo for i in start:length(r1)
        s += r1[i] * r2[i]
    end
    return s
end

shared_neighbors(r1, r2, start=1) =
    @view(r1[start:end]) .* @view(r2[start:end])

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

Find all five-cliques in the adjacency matrix `adj`, storing the
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

    ncols = size(adj, 2)
    p = Progress(ncols; showspeed=true, desc="Finding cliques...", enabled=progress, barlen=50)
    @batch per=thread threadlocal=copy(results) for i in 1:ncols
    # threadlocal = copy(results)
    # for i in 1:ncols
        ri = @view(adj[:, i])
        cliques!(threadlocal, adj, wordlist, order-2, ri, i)
        next!(p)
    end

    finish!(p)
    sizehint!(results, sum(length, threadlocal))
    for th in threadlocal
        append!(results, th)
    end

    progress && @info "$(length(results)) combinations found"
    return results
end

# this is an internal method that uses a recursive call to avoid
# having explicit nested for loops
function cliques!(results::Vector{Vector{String}}, adj, wordlist, depth, prev_row::AbstractVector, members...)
    ncols = size(adj, 2)

    offset = first(members)
    for i in (offset+1):ncols
        prev_row[i] || continue
        row = @view(adj[:, i])
        num_shared_neighbors(prev_row, row, i) < depth && continue
        # only allocate when you actually need it -- the extra computation
        # is cheaper than the unnecessary allocations
        row = shared_neighbors(prev_row, row)
        if depth > 1
            cliques!(results, adj, wordlist, depth-1, row, i, members...)
        else
            idx = [i, members...]
            for w in view(wordlist, row)
                rr = similar(wordlist, 5)
                rr[1:4] .= view(wordlist, idx)
                rr[5] = w
                push!(results, rr)
            end
        end
    end

    return results
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
    adj = T(undef, length(words), length(words))
    fill!(adj, false) # init the diagonal; everything else is overwritten
    @showprogress enabled=progress barlen=50 "Computing adjacency matrix..." for i in 1:length(words), j in 1:(i-1)
        adj[j, i] = adj[i, j] = good_pair(words[i], words[j])
    end
    # why not make this Symmetric()? well, we don't do anything with methods
    # specialized on Symmetric and the view-based access pattern is slower
    # in some circumstances
    return adj
end

function adjacency_matrix(words, T::Type{Matrix{Bool}}; progress=true)
    # this method is specialized with a threading improvement and additional
    # broadcasting that works nicely for this storage type
    nw = length(words)
    adj = T(undef, nw, nw)
    fill!(adj, false) # init the diagonal; everything else is overwritten
    p = Progress(nw; showspeed=false, desc="Computing adjacency matrix...", enabled=progress, barlen=50)
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
