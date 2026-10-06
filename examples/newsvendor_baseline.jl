module NewsvendorBaseline

using JuMP
import HiGHS
import SDDP

"""The fixed, three-stage reference instance; quantities are continuous."""
const DATA = (
    stages = 3,
    initial_inventory = 0.0,
    demand = (20.0, 50.0),
    probabilities = (0.5, 0.5),
    purchase_cost = 2.0,
    sale_price = 8.0,
    holding_cost = 0.1,
    purchase_capacity = 35.0,
    inventory_capacity = 70.0,
)

default_optimizer() = optimizer_with_attributes(HiGHS.Optimizer, "threads" => 1)

"""A valid lower bound: omit nonnegative costs and bound all remaining sales."""
initial_lower_bound() = -(DATA.stages - 1) * DATA.sale_price * maximum(DATA.demand)

"""
    build_policy(; optimizer = default_optimizer())

Construct an ordinary SDDP.jl linear policy graph. Demand is observed before
sales and purchasing; a purchase cannot be sold until the next stage. Stage 1
has zero demand, and terminal purchases are fixed to zero. No lifting or custom
duality handler is used.
"""
function build_policy(; optimizer = default_optimizer())
    return SDDP.LinearPolicyGraph(;
        stages = DATA.stages,
        sense = :Min,
        lower_bound = initial_lower_bound(),
        optimizer = optimizer,
    ) do sp, t
        @variable(sp, 0 <= inventory <= DATA.inventory_capacity,
                  SDDP.State, initial_value = DATA.initial_inventory)
        @variable(sp, 0 <= purchase <= DATA.purchase_capacity)
        @variable(sp, sales >= 0)
        @constraint(sp, sales <= inventory.in)
        demand_limit = @constraint(sp, sales <= 0.0)
        @constraint(sp, inventory.out == inventory.in - sales + purchase)
        if t == DATA.stages
            fix(purchase, 0.0; force = true)
        end
        support = t == 1 ? [0.0] : collect(DATA.demand)
        probabilities = t == 1 ? [1.0] : collect(DATA.probabilities)
        SDDP.parameterize(sp, support, probabilities) do demand
            set_normalized_rhs(demand_limit, demand)
        end
        SDDP.@stageobjective(sp,
            DATA.purchase_cost * purchase + DATA.holding_cost * inventory.out -
            DATA.sale_price * sales)
    end
end

"""All four demand histories, in lexicographic (stage-2, stage-3) order."""
function scenario_paths()
    return [[(1, 0.0), (2, d2), (3, d3)] for d2 in DATA.demand for d3 in DATA.demand]
end

"""
    train_baseline!(policy; iterations = 40)

Run stock SDDP with LP duality. Cycle through all histories deterministically
so the reference run does not depend on a random seed. Forty iterations are a
benchmark budget, not a convergence guarantee.
"""
function train_baseline!(policy; iterations::Int = 40)
    iterations > 0 || throw(ArgumentError("iterations must be positive"))
    mktempdir() do directory
        SDDP.train(policy;
            iteration_limit = iterations,
            sampling_scheme = SDDP.Historical(scenario_paths()),
            duality_handler = SDDP.ContinuousConicDuality(),
            cut_type = SDDP.MULTI_CUT,
            cut_deletion_minimum = -1,
            refine_at_similar_nodes = false,
            parallel_scheme = SDDP.Serial(),
            print_level = 0,
            log_file = joinpath(directory, "training.log"),
        )
    end
    return policy
end

"""
    build_extensive_form(; optimizer = default_optimizer())

Independently formulate the seven-node scenario-tree LP, without SDDP's
deterministic-equivalent converter. Each history has one decision vector, so
nonanticipativity is enforced by construction. Node weights are unconditional
probabilities, not the conditional edge probabilities used by SDDP.
"""
function build_extensive_form(; optimizer = default_optimizer())
    model = Model(optimizer)
    set_silent(model)
    parent = [0, 1, 1, 2, 2, 3, 3]
    stage = [1, 2, 2, 3, 3, 3, 3]
    low, high = DATA.demand
    p_low, p_high = DATA.probabilities
    demand = [0.0, low, high, low, high, low, high]
    probability = [1.0, p_low, p_high, p_low^2,
                   p_low * p_high, p_high * p_low, p_high^2]
    @variable(model, 0 <= inventory[1:7] <= DATA.inventory_capacity)
    @variable(model, 0 <= purchase[1:7] <= DATA.purchase_capacity)
    @variable(model, sales[1:7] >= 0)
    for n in 1:7
        incoming = parent[n] == 0 ? DATA.initial_inventory : inventory[parent[n]]
        @constraint(model, sales[n] <= incoming)
        @constraint(model, sales[n] <= demand[n])
        @constraint(model, inventory[n] == incoming - sales[n] + purchase[n])
        if stage[n] == DATA.stages
            fix(purchase[n], 0.0; force = true)
        end
    end
    @objective(model, Min, sum(probability[n] * (
        DATA.purchase_cost * purchase[n] + DATA.holding_cost * inventory[n] -
        DATA.sale_price * sales[n]) for n in 1:7))
    return model
end

"""
    evaluate_all_paths(policy)

Evaluate the trained policy along every history using public DecisionRule
APIs. Sum immediate costs only, then weight each history by its probability.
The result is an exact finite-support policy expectation, not a sample mean.
"""
function evaluate_all_paths(policy)
    rules = [SDDP.DecisionRule(policy; node = t) for t in 1:DATA.stages]
    paths = map(scenario_paths()) do path
        incoming = Dict(:inventory => DATA.initial_inventory)
        decisions = map(path) do (t, demand)
            result = SDDP.evaluate(rules[t];
                incoming_state = incoming,
                noise = demand,
                controls_to_record = [:purchase, :sales],
            )
            decision = (
                stage = t,
                demand = demand,
                inventory_in = incoming[:inventory],
                purchase = result.controls[:purchase],
                sales = result.controls[:sales],
                inventory_out = result.outgoing_state[:inventory],
                stage_cost = result.stage_objective,
            )
            incoming = copy(result.outgoing_state)
            return decision
        end
        probability = prod(
            DATA.probabilities[findfirst(==(demand), DATA.demand)]
            for (_, demand) in path[2:end]
        )
        return (
            demands = (path[2][2], path[3][2]),
            probability = probability,
            total_cost = sum(d.stage_cost for d in decisions),
            decisions = decisions,
        )
    end
    return (
        expected_cost = sum(p.probability * p.total_cost for p in paths),
        paths = paths,
    )
end

"""Solve both formulations and return the independently checked baseline results."""
function run_baseline(; iterations::Int = 40, optimizer = default_optimizer())
    reference = build_extensive_form(; optimizer)
    optimize!(reference)
    assert_is_solved_and_feasible(reference; dual = true)
    policy = build_policy(; optimizer)
    train_baseline!(policy; iterations)
    evaluation = evaluate_all_paths(policy)
    return (
        policy = policy,
        reference = reference,
        reference_objective = objective_value(reference),
        reference_bound = objective_bound(reference),
        sddp_lower_bound = SDDP.calculate_bound(policy),
        policy_expected_cost = evaluation.expected_cost,
        paths = evaluation.paths,
    )
end

end
