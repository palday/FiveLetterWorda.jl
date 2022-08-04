module FiveLetterWorda

using Arrow
using Combinatorics
using Downloads
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
    words = filter(x -> length(Set(x)) == 5, words)
    hits = sizehint!(Set{WordCombination}(), 538)
    find_word_combo!(hits, words)
    return hits
end

function skip(wc::WordCombination, word::String)
    return word in wc || length(setdiff(word, wc.chars)) != 5
end


function find_word_combo!(hits::Set{WordCombination}, wordlist::Vector{String})
    wc = WordCombination()
    p = Progress(length(wordlist); showspeed=true)
    spinlock = Threads.SpinLock()
    Threads.@threads for (i, a) in enumerate(wordlist)
        skip(wc, a) && continue
        wca = union(wc, a)
        for (j, b) in enumerate(@view wordlist[i:end])
            skip(wca, b) && continue
            wcb = union(wca, b)
            for (k, c) in enumerate(@view wordlist[j:end])
                skip(wcb, c) && continue
                wcc = union(wcb, a)
                for (l, d) in enumerate(@view wordlist[k:end])
                    skip(wcc, d) && continue
                    wcd = union(wcc, d)
                    for (m, e) in enumerate(@view wordlist[l:end])
                        skip(wcd, e) && continue
                        wce = union(wcd, e)
                        # @info wce
                        lock(spinlock)
                        push!(hits, wce)
                        unlock(spinlock)
                    end
                end
            end
        end
        next!(p)
    end

    finish!(p)

    return hits
end

# great way that results in a stack overflow
# function find_word_combo!(hits::Set{WordCombination}, wc::WordCombination, wordlist::Vector{String}, idx::Int=1)
#     # idx > 10 && return
#     word = wordlist[idx]
#     # word in wc && error("got a repeat! $(wc), $(idx)")

#     chars = Set(word)
#     # this depends on no words having duplicate letters
#     wc = length(setdiff(chars, wc.chars)) == 5 ? wc : union(wc, word)
#     # wc = length(setdiff(chars, wc.chars)) == 5 ? wc : union(wc, word)
#     if nwords(wc) == 2
#         @info wc
#         # push!(hits, wc)
#         return nothing
#     end

#     # notice the type restriction on wordlist before judging my indexing
#     Threads.@threads for i in (idx+1):length(wordlist)
#         find_word_combo!(hits, wc, wordlist, i)
#     end
#     return nothing
# end

# function find_word_combo(wc::WordCombination, wordlist::AbstractVector{String},
#                          mask::BitVector=BitVector(true for _ in wordlist))
#     isempty(wordlist) && return nothing
#     nwords(wc) == 2 && return wc

#     newmask = copy(mask)
#     for i in eachindex(newmask)
#         newmask[i] || continue
#         word = wordlist[i]
#         find_word_combo(union(wc, word), wordlist, newmask)
#         newmask[i] = false
#     end
#     @show wc
#     return nothing
# end

end # module
