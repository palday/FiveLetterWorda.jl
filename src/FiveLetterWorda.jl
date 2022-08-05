module FiveLetterWorda

using Arrow
using Downloads
using LinearAlgebra
using ProgressMeter
using Scratch
using ZipFile

export main, WordCombination, nwords, nchars
export adjacency_matrix, cliques!

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

# TODO intersect[!]
# TODO push!
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
    sets = Vector{Vector{String}}()
    cliques!(sets, adj, words)
    return (; adj, words, combinations=WordCombination.(sets))
end

function num_shared_neigbors(r1, r2, start=1)
    return count(zip(@view(r1[start:end]), @view(r2[start:end]))) do x
        return x[1] & x[2]
    end
end
shared_neighbors(r1, r2, start=1) = @view(r1[start:end]) .& @view(r2[start:end])

function cliques!(results::Vector{Vector{String}}, adj, wordlist)
    ll = Threads.SpinLock()
    ncols = size(adj, 2)
    p = Progress(ncols; showspeed=true, desc="Finding cliques...")
    Threads.@threads for i in 1:ncols
        ri = @view(adj[:, i])
        for j in (i+1):ncols
            ri[j] || continue
            rj = @view(adj[:, j])
            num_shared_neigbors(ri, rj, j) < 3 && continue
            # only allocate if useful
            rj = shared_neighbors(ri, rj)
            for k in (j+1):ncols
                rj[k] || continue
                rk = @view(adj[:, k])
                num_shared_neigbors(rj, rk, k) < 2 && continue
                # only allocate if useful
                rk = shared_neighbors(rj, rk)
                for l in (k+1):ncols
                    rk[l] || continue
                    rl = @view(adj[:, l])
                    num_shared_neigbors(rk, rl, l) < 1 && continue
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

function adjacency_matrix(words)
    adj = BitMatrix(undef, length(words), length(words))
    fill!(adj, false) # init the diagonal; everything else is overwritten
    # fill!(view(adj, diagind(adj)), true)
    @showprogress "Computing adjacency matrix..." for i in 1:length(words), j in 1:(i-1)
        adj[j, i] = adj[i, j] = good_pair(words[i], words[j])
    end
    return Symmetric(adj)
end

function good_pair(w1::String, w2::String)
    return isempty(intersect!(Set(w1), w2))
end

end # module
