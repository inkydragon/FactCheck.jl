module DeFacto

export @fact,
       @facts,

       # assertion helpers
       not

abstract Result
type Success <: Result
    expr::Expr
    meta::Dict
end
type Failure <: Result
    expr::Expr
    meta::Dict
end
type Error <: Result
    expr::Expr
    err::Exception
    backtrace
    meta::Dict
end

import Base.error_show

function error_show(io::IO, r::Error, backtrace)
    println(io, "Test error: $(r.expr)")
    error_show(io, r.err, r.backtrace)
end
error_show(io::IO, r::Error) = error_show(io, r, {})

type TestSuite
    file::String
    desc::Union(String, Nothing)
    successes::Array{Success}
    failures::Array{Failure}
    errors::Array{Error}
end
function TestSuite(file::String, desc::Union(String, Nothing))
    TestSuite(file, desc, Success[], Failure[], Error[])
end

# Display
# =======

RED     = "\x1b[31m"
GREEN   = "\x1b[32m"
BOLD    = "\x1b[1m"
DEFAULT = "\x1b[0m"

colored(s::String, color) = string(color, s, DEFAULT)
red(s::String)   = colored(s, RED)
green(s::String) = colored(s, GREEN)
bold(s::String)  = colored(s, BOLD)

pluralize(s::String, n::Number) = n == 1 ? s : string(s, "s")

function format_failed(ex::Expr)
    x, y = ex.args
    "$(repr(x)) => $(repr(y))"
end

function format_line(r::Result, s::String)
    "$s $(has(r.meta, "line") ? "(line:$(r.meta["line"].args[1])) " : ""):: "
end

function print_failure(f::Failure)
    formatted = "$(red("Failure")) "
    formatted = format_line(f, formatted)
    formatted = string(formatted, format_failed(f.expr), "\n")

    println(formatted)
end

function print_error(e::Error)
    formatted = "$(red("Error"))   "
    formatted = format_line(e, formatted)
    print(formatted)
    error_show(STDOUT, e)
    println("\n")
end

function print_results(suite::TestSuite)
    if length(suite.failures) == 0 && length(suite.errors) == 0
        println(green("$(length(suite.successes)) $(pluralize("fact", length(suite.successes))) verified.\n"))
    else
        total = length(suite.successes) + length(suite.failures)
        println("Out of $total total $(pluralize("fact", total)):")
        println(green("  Verified: $(length(suite.successes))"))
        println(  red("  Failed:   $(length(suite.failures))"))
        println(  red("  Errored:  $(length(suite.errors))\n"))
    end
end

function format_suite(suite::TestSuite)
    bold(string(suite.desc != nothing ? "$(suite.desc) ($(suite.file))" : suite.file, "\n"))
end

# Core
# ====

const handlers = Function[]

function do_fact(thunk, factex, meta)
    result = try
        thunk() ? Success(factex, meta) : Failure(factex, meta)
    catch err
        Error(factex, err, catch_backtrace(), meta)
    end

    handlers[end](result)
end

throws_pred(ex) = :(try $(esc(ex)); false catch e true end)

function fact_pred(ex, assertion)
    quote
        pred = function(t)
            e = $(esc(assertion))
            isa(e, Function) ? e(t) : e == t
        end
        pred($(esc(ex)))
    end
end

function rewrite_assertion(factex::Expr, meta::Dict)
    ex, assertion = factex.args
    test = assertion == :(:throws) ? throws_pred(ex) : fact_pred(ex, assertion)
    :(do_fact(()->$test, $(Expr(:quote, factex)), $meta))
end

function process_fact(desc::Union(String, Nothing), factex::Expr)
    if factex.head == :block
        out = :(begin end)
        for ex in factex.args
            if ex.head == :line
                line_ann = ex
            else
                push!(out.args,
                      ex.head == :(=>) ?
                      rewrite_assertion(ex, {"desc" => desc, "line" => line_ann}) :
                      esc(ex))
            end
        end
        out
    else
        rewrite_assertion(factex, {"desc" => desc})
    end
end
process_fact(factex::Expr) = process_fact(nothing, factex)

function make_handler(suite::TestSuite)
    function delayed_handler(r::Success)
        push!(suite.successes, r)
    end
    function delayed_handler(r::Failure)
        push!(suite.failures, r)
        print_failure(r)
    end
    function delayed_handler(r::Error)
        push!(suite.errors, r)
        print_error(r)
    end
    delayed_handler
end

function do_facts(desc::Union(String, Nothing), facts_block::Expr)
    file_name = split(string(facts_block.args[1].args[2]), "/")[end]

    suite = TestSuite(file_name, desc)
    test_handler = make_handler(suite)
    push!(handlers, test_handler)

    quote
        println()
        println(format_suite($suite))
        $(esc(facts_block))
        print_results($suite)
    end
end
do_facts(facts_block::Expr) = do_facts(nothing, facts_block)

macro facts(args...)
    do_facts(args...)
end

macro fact(args...)
    process_fact(args...)
end

# Assertion functions
# ===================

not(x) = isa(x, Function) ? (y) -> !x(y) : (y) -> x != y

end # module DeFacto
