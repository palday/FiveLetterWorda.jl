module FiveLetterWorda

using Arrow
using Combinatorics
using Downloads
using LinearAlgebra
using ProgressMeter
using Scratch
using ZipFile

using Base.Iterators: product
using Combinatorics: combinations

export main, WordCombination, nwords, nchars

const CACHE = Ref("")
const WORD_ZIP_URL = "https://github.com/dwyl/english-words/raw/master/words_alpha.zip"

clear_scratchspaces!() = Scratch.clear_scratchspaces!(@__MODULE__)

struct WordCombination
    chars::Set{Char}
    words::Set{String}
end

nwords(wc::WordCombination) = length(wc.words)
nchars(wc::WordCombination) = length(wc.chars)
get_words(wc::WordCombination) = wc.words

WordCombination() = WordCombination(Set{Char}(), Set{String}())
WordCombination(w::String) = WordCombination(Set{Char}(w), Set{String}([w]))

function Base.show(io::IO, wc::WordCombination)
    println(io, "WordCombination with $(nwords(wc)) words " *
            "containing $(nchars(wc)) distinct characters")

    println(io, "Chars: ", join(sort!(collect(wc.chars))))
    println(io, "Words: ", join(sort!(collect(wc.words)), ", "))
    return nothing
end
function WordCombination(ws::AbstractVector{String})
    chars = mapreduce(Set, union!, ws; init=Set{Char}())
    return WordCombination(chars, Set{String}(ws))
end

function Base.union!(w1::WordCombination, w2::WordCombination)
    union!(w1.chars, w2.chars)
    union!(w1.words, w2.words)
    return w1
end

function Base.union(w1::WordCombination, w2::WordCombination)
    chars = union(w1.chars, w2.chars)
    words = union(w1.words, w2.words)
    return WordCombination(chars, words)
end

function Base.union(w1::WordCombination, w2::String)
    chars = union(w1.chars, Set(w2))
    words = union!(Set([w2]), w1.words)
    return WordCombination(chars, words)
end

Base.in(w::String, wc::WordCombination) = w in wc.words


function __init__()
    CACHE[] = @get_scratch!("data")
end

_fname() = joinpath(CACHE[], "words_alpha.arrow")

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

remove_anagrams(words::Vector{String}) = unique(Set, words)

function main()
    words = remove_anagrams(load_data())
    # remove words with repeated letters
    words = filter(x -> length(Set(x)) == 5, words)
    adj = adjacency_matrix(words)

    return (; adj, words)
    # pairs = skipmissing(maybe_wc(c) for c in combinations(words, 2))
    # triples = skipmissing(maybe_push(wc, w) for (wc, w) in product(pairs, words))
    # quads = skipmissing(maybe_push(wc, w) for (wc, w) in product(triples, words))
    # quints = skipmissing(maybe_push(wc, w) for (wc, w) in product(quads, words))
    # return (; words, pairs, triples, quads, quints)
end

num_shared_neigbors(r1, r2) = count(x -> x[1] & x[2], zip(r1, r2))
shared_neighbors(r1, r2) = r1 .& r2

export num_shared_neigbors

function cliques!(results::Vector{Vector{String}}, adj, wordlist)
    ll = Threads.SpinLock()
    ncols = size(adj, 2)
    p = Progress(ncols; showspeed=true, desc="Finding cliques...")
    Threads.@threads for i in 1:ncols
        ri = view(adj, :, i)
        for j in (i+1):ncols
            ri[j] || continue
            rj = view(adj, :, j)
            num_shared_neigbors(ri, rj) < 3 && continue
            # only allocate if useful
            rj = shared_neighbors(ri, rj)
            for k in (j+1):ncols
                rj[k] || continue
                rk = view(adj, :, k)
                num_shared_neigbors(rj, rk) < 2 && continue
                # only allocate if useful
                rk = shared_neighbors(rj, rk)
                for l in (k+1):ncols
                    rk[l] || continue
                    rl = view(adj, :, l)
                    num_shared_neigbors(rk, rl) < 1 && continue
                    # only allocate if useful
                    rl = shared_neighbors(rk, rl)
                    rr = wordlist[[i, j, k, l]]
                    append!(rr, view(wordlist, rl))
                    lock(ll) do
                        return push!(results, rr)
                    end
                end
            end
        end
        next!(p)
    end

    finish!(p)
    return results
end

export cliques!

function adjacency_matrix(words)
    adj = BitMatrix(undef, length(words), length(words))
    fill!(adj, false) # init the diagonal; everything else is overwritten
    # fill!(view(adj, diagind(adj)), true)
    @showprogress for i in 1:length(words), j in 1:(i-1)
        adj[j, i] = adj[i, j] = good_pair(words[i], words[j])
    end
    return Symmetric(adj)
end

export adjacency_matrix

function good_pair(w1::String, w2::String)
    return isempty(intersect!(Set(w1), w2))
end

export good_pair

# function maybe_wc(w::Vector{String})
#     chars = Set(w[1])
#     for i in 2:length(w)
#         length(union!(chars, Set(w[i]))) == 5i || return missing
#     end
#     return WordCombination(chars, Set(w))
# end

# export maybe_wc

# function maybe_push(wc::WordCombination, w::String)
#     w in wc && return missing
#     chars = union(wc.chars, w)
#     length(chars) != nchars(wc) + length(w) && return missing
#     return WordCombination(chars, union(wc.words, [w]))
# end

# export maybe_push

end # module
