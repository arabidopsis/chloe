
import ..Annotator: iterFasta, readFasta, DNAString, makeSuffixArray, makeSuffixArrayRanksArray, revComp, alignLoops, genome_wrap
import Crayons: @crayon_str

const success = crayon"bold green"

function to80(io::IO, genome::String, width::Int=80)
    len = length(genome)
    for i in 1:width:len
        println(io, SubString(genome, i:min(len, i + width - 1)))
    end
end


function rotateGenome(target_id::String, target_seqf::DNAString, flip_LSC::Bool, flip_SSC::Bool, extend::Int=0)::String
    target_length = length(target_seqf)
    targetloopf = target_seqf * target_seqf[1:end - 1]
    target_saf = makeSuffixArray(targetloopf, true)
    target_raf = makeSuffixArrayRanksArray(target_saf)

    target_seqr = revComp(target_seqf)
    targetloopr = target_seqr * target_seqr[1:end - 1]
    target_sar = makeSuffixArray(targetloopr, true)
    target_rar = makeSuffixArrayRanksArray(target_sar)

    f_aligned_blocks, r_aligned_blocks = alignLoops(target_id,
        targetloopf, target_saf, target_raf,
        targetloopr, target_sar, target_rar)

    # sort blocks by length
    f_aligned_blocks = sort(f_aligned_blocks, by=last, rev=true)
    
    ir1, ir2, IR_length = f_aligned_blocks[1]

    @debug "[$(target_id)] $target_length found inverted repeats: $(ir1) $(ir2) len=$(IR_length)"

    s1 = SubString(targetloopf, ir1, ir1 + IR_length - 1)
    s2 = SubString(targetloopr, ir2, ir2 + IR_length - 1)
    if s1 != s2
        @error "s1 != s2 $(s1[1:20]) $(s2[1:20])"
    end
    s = genome_wrap(target_length, target_length - ir2  - IR_length + 2)
    s3 = revComp(SubString(targetloopf, s, s + IR_length - 1))
    if s1 != s3 
        @error "s1 != s3 $(s1[1:20]) $(s3[1:20])"
    end


    out = Vector{String}()
    
    ss = (rng::UnitRange) -> SubString(targetloopf, rng)


    if IR_length >= 1000
        @debug "[$(target_id)] found inverted repeat: $(ir1) $(ir2) len=$(IR_length)"
        ir1 = genome_wrap(target_length, ir1)
        ir2 = genome_wrap(target_length, target_length - ir2  - IR_length + 2)
        if ir2 < ir1
            ir1, ir2 = ir2, ir1
        end
        IR1 = ir1:ir1 + IR_length - 1
        IR2 = ir2:ir2 + IR_length - 1
        if last(IR1) >= first(IR2)
            error("$(target_id): inverted repeats overlap ... too vague sequence?")
        end
        # extra is after IR2 but we need to place it first

        # IR2 *end* might extend beyond target_length
        LSC = max(1, 1 + last(IR2) - target_length):first(IR1) - 1
        SSC = last(IR1) + 1:first(IR2) - 1
        rest = last(IR2) + 1:target_length
        
        @info "[$(target_id)] $(target_length) ir=$IR_length LSC=$(LSC)[$(length(LSC))] IR1=$(IR1)[$(length(IR1))] SSC=$(SSC)[$(length(SSC))] IR2=$(IR2)[$(length(IR2))] rest=$(rest)[$(length(rest))]"
        
        LSC, IR1, SSC, IR2, rest = map(ss, [LSC, IR1, SSC, IR2, rest])
        LSC = length(rest) > 0 ? join([rest, LSC], "") : LSC
        rotated = if length(LSC) < length(SSC)
            [
                flip_LSC ? revComp(SSC) : SSC,
                IR2,
                flip_SSC ? revComp(LSC) : LSC,
                IR1
            ]
        else
            [
                flip_LSC ? revComp(LSC) : LSC,
                IR1,
                flip_SSC ? revComp(SSC) : SSC, 
                IR2
            ]
        end
        push!(out, rotated...)

    else
        @warn "[$(target_id)] no inverted repeat found"
        push!(out, target_seqf)
    end
    
    if extend != 0
        e = min(extend > 0 ? extend : target_length - 1, target_length - 1)
        @debug "[$(target_id)] extending by $e"
        # extend transformed seq
        o = join(out, "") # can we do better here?
        push!(out, SubString(o, 1:e))
    end
    join(out, "")
end

function rotateGenome(fasta, io::IO, flip_LSC::Bool, flip_SSC::Bool, extend::Int=0, width::Int=80)

    for (target_id, target_seqf) in iterFasta(fasta; full=false)
        seq = rotateGenome(target_id, target_seqf, flip_LSC, flip_SSC, extend)
        if extend == 0
            if length(seq) != length(target_seqf)
                error("[$(target_id)] lengths differ: $(length(target_seqf)) != rotated $(length(seq))")
            end
        end
        @debug "[$(target_id)] seq length=$(length(target_seqf)) rotated=$(length(seq))"
        println(io, ">", target_id, " rotated:LSC=$(flip_LSC),SSC=$(flip_SSC),extend=$(extend)")
        
        iio = IOBuffer()
        ir(iio, fasta, flip_LSC, flip_SSC, extend)
        ss2 = replace(String(take!(iio)), r"\s+" => "")
        if ss2 != seq
            @error "$target_id len=$(length(target_seqf)) ian=$(length(ss2)) me=$(length(seq))"
            # @error "$(ss2[1:100])"
            # @error "$(seq[1:100])"
            for (idx, (c1, c2)) in enumerate(zip(ss2, seq))
                if c1 != c2
                    @error "$idx $c1 $c2"
                    break
                end
            end
        else
            @info success(target_id)
        end
        
        to80(io, seq, width)
    end

end

function rotateGenome(;fasta_files::Vector{String}, directory::Union{String,Nothing}=nothing,
                      flip_LSC::Bool=false, flip_SSC::Bool=false, extend::Int=0, width::Int=80)
    if width <= 0
        error("width should be positive!")
    end

    if directory == "-"
        for fasta in fasta_files
            rotateGenome(fasta, stdout, flip_LSC, flip_SSC, extend, width)
        end
        return
    end

    for fasta in fasta_files
        d = splitpath(fasta)
        fname = if directory !== nothing
            joinpath(directory, d[end])
        else
            f, ext = splitext(d[end])
            joinpath(d[1:end - 1]..., f * "-rotated" * ext)
        end

        open(fname, "w") do io
            rotateGenome(fasta, io, flip_LSC, flip_SSC, extend, width)
        end
        @info "$(fasta) rotated to $(fname)"
    end
end


function ir(io, fasta, flip_LSC::Bool, flip_SSC::Bool, extend::Int=0)

    target_id, target_seqf = readFasta(fasta)
    target_length = length(target_seqf)
    targetloopf = target_seqf * target_seqf[1:end - 1]
    target_saf = makeSuffixArray(targetloopf, true)
    target_raf = makeSuffixArrayRanksArray(target_saf)
    
    target_seqr = revComp(target_seqf)
    targetloopr = target_seqr * target_seqr[1:end - 1]
    target_sar = makeSuffixArray(targetloopr, true)
    target_rar = makeSuffixArrayRanksArray(target_sar)
    
    f_aligned_blocks, r_aligned_blocks = alignLoops(target_id, targetloopf, target_saf, target_raf, targetloopr, target_sar, target_rar)
    
    # sort blocks by length
    f_aligned_blocks = sort(f_aligned_blocks, by=last, rev=true)
    IR_length = f_aligned_blocks[1][3]
    @info "$target_id $target_length $IR_length"
    
    # println(">" * target_id)
    if IR_length >= 1000
        IR1 = (f_aligned_blocks[1][1], IR_length)
        IR2 = (f_aligned_blocks[1][2], IR_length)
        SSC = (f_aligned_blocks[1][1] + IR_length, length(target_seqf) - 2 * IR_length - IR1[1] - 1 - IR2[1] - 1)
        LSC = (length(target_seqf) - f_aligned_blocks[1][2] + 2, length(target_seqf) - 2 * IR_length - SSC[2])
        if LSC[2] < SSC[2]
            temp = LSC
            LSC = SSC
            SSC = temp
            temp = IR1
            IR1 = IR2
            IR2 = temp
        end
        # println(LSC,IR1,SSC,IR2)
        n = LSC[2] + IR1[2] + SSC[2] + IR2[2]
        @assert n == target_length "$(target_id) $n != $target_length"
        # @info "$LSC $IR1 $SSC $IR2"
        lsc = LSC[1]:LSC[1] + LSC[2] - 1
        ir1 = IR1[1]:IR1[1] + IR1[2] - 1
        ssc = SSC[1]:SSC[1] + SSC[2] - 1
        ir2 = IR2[1]:IR2[1] + IR2[2] - 1
        @info "LSC=$(lsc)[$(length(lsc))] IR1=$(ir1)[$(length(ir1))] SSC=$(ssc)[$(length(ssc))] IR2=$(ir2)[$(length(ir2))]"
        if flip_LSC
            print(io, revComp(targetloopf[LSC[1]:LSC[1] + LSC[2] - 1]))
        else
            print(io, targetloopf[LSC[1]:LSC[1] + LSC[2] - 1])
        end
        print(io, targetloopf[IR1[1]:IR1[1] + IR1[2] - 1])
        if flip_SSC
            print(io, revComp(targetloopf[SSC[1]:SSC[1] + SSC[2] - 1]))
        else
            print(io, targetloopf[SSC[1]:SSC[1] + SSC[2] - 1])
        end
        print(io, revComp(targetloopr[IR2[1]:IR2[1] + IR2[2] - 1]))
    else
        print(io, target_seqf)
    end
    if extend > 0
        print(io, target_seqf[1:1 + extend])
    end
    println(io, "")
end