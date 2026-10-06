using Test
using SDDLP
using JuMP
import SDDP

include(joinpath(@__DIR__, "..", "examples", "newsvendor_baseline.jl"))
using .NewsvendorBaseline

@testset "Package foundation" begin
    @test nameof(SDDLP) == :SDDLP
    @test pkgversion(SDDP) == v"1.15.0"
end

@testset "Fixed-probability newsvendor baseline" begin
    result = NewsvendorBaseline.run_baseline()
    data = NewsvendorBaseline.DATA
    tol = 1e-6

    # A seven-node reference LP, independently formulated and independently
    # hand-checked, guards against errors shared by training and evaluation.
    @test termination_status(result.reference) == MOI.OPTIMAL
    @test result.reference_objective ≈ -321.125 atol = tol
    @test result.reference_bound ≈ result.reference_objective atol = tol
    @test result.sddp_lower_bound ≈ result.reference_objective atol = tol
    @test result.policy_expected_cost ≈ result.reference_objective atol = tol
    @test NewsvendorBaseline.initial_lower_bound() <= result.reference_objective
    @test value.(result.reference[:purchase]) ≈ [35, 35, 35, 0, 0, 0, 0] atol = tol
    @test value.(result.reference[:inventory]) ≈ [35, 50, 35, 30, 0, 15, 0] atol = tol

    expected_costs = Dict(
        (20.0, 20.0) => -168.5,
        (20.0, 50.0) => -411.5,
        (50.0, 20.0) => -291.5,
        (50.0, 50.0) => -413.0,
    )
    @test Set(path.demands for path in result.paths) == Set(keys(expected_costs))
    @test sum(path.probability for path in result.paths) ≈ 1.0
    for path in result.paths
        @test path.probability ≈ 0.25
        @test path.total_cost ≈ expected_costs[path.demands] atol = tol
        @test path.decisions[1].purchase ≈ 35.0 atol = tol
        @test path.decisions[1].sales ≈ 0.0 atol = tol
        @test path.decisions[2].purchase ≈ 35.0 atol = tol
        @test path.decisions[2].sales ≈ min(35.0, path.demands[1]) atol = tol
        @test path.decisions[3].purchase ≈ 0.0 atol = tol
        for decision in path.decisions
            @test -tol <= decision.sales <= min(decision.demand, decision.inventory_in) + tol
            @test -tol <= decision.purchase <= data.purchase_capacity + tol
            @test -tol <= decision.inventory_out <= data.inventory_capacity + tol
            @test decision.inventory_out ≈ decision.inventory_in - decision.sales + decision.purchase atol = tol
            @test decision.stage_cost ≈ data.purchase_cost * decision.purchase +
                data.holding_cost * decision.inventory_out - data.sale_price * decision.sales atol = tol
        end
    end

    # Decisions at a common history must not depend on the future demand.
    @test result.paths[1].decisions[1] == result.paths[4].decisions[1]
    @test result.paths[1].decisions[2] == result.paths[2].decisions[2]
    @test result.paths[3].decisions[2] == result.paths[4].decisions[2]
    @test_throws ArgumentError NewsvendorBaseline.train_baseline!(result.policy; iterations = 0)
end
