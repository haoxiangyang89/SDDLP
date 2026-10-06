# SDDLP.jl

SDDLP is being developed as an SDDP.jl extension for adaptive state lifting and
Lagrangian cuts in multistage stochastic mixed-integer programs.

## Current status: Step 1

The package foundation and a fixed-probability, continuous newsvendor baseline
are implemented. The baseline uses stock SDDP.jl. Adaptive lifting, custom LC/SMC
generation, the general model wrapper, and decision-dependent probabilities are
future steps and are not exposed as implemented APIs.

The four original research scripts in `src/` are preserved and are not loaded
when importing `SDDLP`. The package has no runtime dependency on Gurobi; the
baseline and tests use HiGHS.

## Run from the repository root

Use Julia 1.10 or later. SDDP is pinned to version 1.15.0 in both environments.

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=examples -e 'using Pkg; Pkg.instantiate()'
julia --project=examples examples/run_newsvendor.jl
```

The package and example environments are separate from the user's global Julia
project. Julia will generate local `Manifest.toml` files, which the repository's
existing ignore rules exclude. Other dependencies have compatible version
ranges; their exact resolved versions are recorded in those local manifests.

The reference has one product, three stages, and four equally likely demand
histories. The expected minimum cost is **-321.125**, equivalent to expected
profit **321.125**. The SDDP bound and exhaustive policy evaluation are checked
against an independently constructed seven-node extensive-form LP.

- [Model formulation, data, and reference solution](docs/newsvendor_baseline.md)
- [Baseline implementation](examples/newsvendor_baseline.jl)
- [Tests](test/runtests.jl)
- [Step 1 review](docs/step_1_review.md)
