

include("annotate_genomes.jl")
using JuliaWebAPI
using ArgParse
using Logging
using LogRoller

const LEVELS = Dict("info"=>Logging.Info, "debug"=> Logging.Debug, 
                    "warn" => Logging.Warn, "error"=>Logging.Error)

const ADDRESS = "tcp://127.0.0.1:9999"

function chloe_svr(;refsdir = "reference_1116", address=[ADDRESS],
    template = "optimised_templates.v2.tsv", level="warn", async=false,
    logfile::MayBeString=nothing, connect=false, nthreads=1)
    
    llevel = get(LEVELS, level, Logging.Warn)
    
    if length(address) === 0
        push!(address, ADDRESS)
    end

    address = repeat(address, nthreads)

    if logfile === nothing
        logger = ConsoleLogger(stderr,llevel)
    else
        logger = RollingLogger(logfile::String, 10 * 1000000, 2, llevel);
    end

    conn = connect ? "connecting to" : "listening on"

    with_logger(logger) do
        reference = readReferences(refsdir, template)
        @info show_reference(reference)
        @info "using $(Threads.nthreads()) threads"
        @info "$(conn) $(address)"

        function chloe(fasta::String, fname::MayBeString)
            @info "running on thread: $(Threads.threadid())"
            annotate_one(fasta, reference, fname)
            @info "finished on thread: $(Threads.threadid())"
            return fname
        end

        function ping()
            return "OK $(Threads.threadid())"
        end
        if length(address) == 1
            process(
                    JuliaWebAPI.create_responder([
                            (chloe, false),
                            (ping, false)

                        ], address[1], !connect, "chloe"); async=async
                    )
        else
            Threads.@threads for addr in address
                    process(
                        JuliaWebAPI.create_responder([
                            (chloe, false),
                            (ping, false)

                        ], addr, !connect, "chloe"); async=async
                    )
            end
        end
        if isa(logger, RollingLogger)
            close(logger::RollingLogger)
        end

    end
end

args = ArgParseSettings(prog="Chloë", autofix_names = true)  # turn "-" into "_" for arg names.

@add_arg_table! args begin
    "--reference", "-r"
        arg_type = String
        default = "reference_1116"
        dest_name = "refsdir"
        metavar = "DIRECTORY"
        help = "reference directory"
    "--template", "-t"
        arg_type = String
        default = "optimised_templates.v2.tsv"
        metavar = "TSV"
        dest_name = "template"
        help = "template tsv"
    "--address", "-a"
        arg_type = String
        default = []
        help = "ZMQ address(es) to listen on or connect to"
        action = :append_arg
    "--logfile"
        arg_type=String
        metavar="FILE"
        help="log to file"
    "--level", "-l"
        arg_type = String
        metavar = "LOGLEVEL"
        default ="warn"
        help = "log level (warn,debug,info,error)"
    "--async"
        action = :store_true
        help = "run APIresponder async"
    "--connect"
        action = :store_true
        help = "connect to addresses instead of bind"
    "--nthreads"
        arg_type = Int
        default = 1
        help = "number of threads when connecting"

end
args.epilog = """
Run Chloe as a background ZMQ service
"""

function real_main() 
    parsed_args = parse_args(ARGS, args; as_symbols = true)
    # filter!(kv->kv.second ∉ (nothing, false), parsed_args)
    chloe_svr(;parsed_args...)
end


if abspath(PROGRAM_FILE) == @__FILE__
    real_main()
end
