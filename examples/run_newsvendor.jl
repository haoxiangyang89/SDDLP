include("newsvendor_baseline.jl")
using .NewsvendorBaseline

result = NewsvendorBaseline.run_baseline()
println("Three-stage fixed-probability newsvendor (continuous LP)")
println("SDDP version: ", pkgversion(NewsvendorBaseline.SDDP))
println("Training: 40 iterations, deterministic cycling through all 4 paths")
println("Extensive-form optimum: ", result.reference_objective)
println("Extensive-form solver bound: ", result.reference_bound)
println("SDDP lower bound: ", result.sddp_lower_bound)
println("Exact policy expected cost: ", result.policy_expected_cost)
println("First-stage purchase: ", first(result.paths).decisions[1].purchase)
for path in result.paths
    println("Demand ", path.demands, "; probability = ", path.probability,
            "; policy cost = ", path.total_cost)
end
