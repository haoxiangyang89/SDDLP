# Step 1: fixed-probability newsvendor baseline

This small reference case is adapted from the inventory-flow logic in
Arslan, Dowson, and Morton (2024), Sections 2–5, and the existing research
scripts. It is a continuous stochastic linear program. Its purpose is to check
model timing, SDDP integration, and evaluation before adding integer lifting and
custom Lagrangian cuts. It does not benchmark the future stochastic-MIP solver.

## Data and information structure

There is one product and three stages. Stage 1 stocks inventory; stages 2 and 3
observe demand, sell available inventory, and carry leftovers forward. A purchase
at stage t becomes available for sales at stage t+1. Unmet demand is lost, with
no backlogging or shortage penalty.

| Parameter | Value |
|---|---:|
| Initial inventory | 0 |
| Stage-1 demand | 0 |
| Stage-2 and stage-3 demand | 20 or 50 |
| Probability of each demand value | 0.5 |
| Purchase cost per unit | 2 |
| Sales revenue per unit | 8 |
| Holding cost per unit per stage | 0.1 |
| Purchase capacity per stage | 35 |
| Inventory upper bound | 70 |
| Terminal purchases | 0 |
| Terminal salvage value | 0 |

The two random demands are independent, with fixed probabilities unaffected by
decisions. Marketing variables are omitted. All quantities are continuous.
Holding cost applies to terminal leftovers as well as earlier inventory.

## Model formulation

Let u_t be purchases, s_t sales, x_t outgoing inventory, and D_t observed
demand. With x_0 = 0 and D_1 = 0, solve

\[
\min_{\text{adapted }(u,s,x)}
\mathbb E\left[\sum_{t=1}^{3}
  \left(2u_t+0.1x_t-8s_t\right)\right]
\]

subject to, for every realized history and stage,

\[
\begin{aligned}
x_t &= x_{t-1}-s_t+u_t,\\
0 &\le s_t\le D_t, & s_t&\le x_{t-1},\\
0 &\le u_t\le35, & 0&\le x_t\le70,\\
u_3&=0.
\end{aligned}
\]

Here D_2 and D_3 independently take values 20 and 50 with probability 1/2.
Decisions at stage t depend only on demand observed through that stage. In
particular, stage-2 decisions cannot depend on stage-3 demand. The separate
constraint s_t <= x_{t-1} prevents same-stage purchases from serving demand.

For SDDP, the equivalent stage recursion is

\[
V_t(x,d)=\min_{u,s,x'}
\left\{2u+0.1x'-8s+C_t(x')\right\},
\]

with the same stage constraints, and

\[
C_t(x')=
\begin{cases}
\tfrac12V_{t+1}(x',20)+\tfrac12V_{t+1}(x',50),&t<3,\\
0,&t=3.
\end{cases}
\]

The desired value is V_1(0,0). Inventory is the single physical SDDP state;
purchase and sales are stage-local controls. A uniform initial continuation
lower bound of -800 is valid: total sales revenue cannot exceed
2 * 50 * 8, and purchasing/holding costs are nonnegative.

## Independent reference model

`build_extensive_form` builds seven nodes: one root, two second-stage nodes,
and four terminal nodes. Each node gets its own purchase, sales, and inventory
variables, and inventory is linked to its unique predecessor. There is only
one stage-2 decision vector for each observed D_2, automatically enforcing
nonanticipativity across its terminal continuations.

The objective weights the root by 1, stage-2 nodes by 1/2, and terminal nodes by
1/4. This model is constructed directly in JuMP without calling SDDP's
deterministic-equivalent converter.

## Reference solution

The expected minimum cost is **-321.125** (expected profit **321.125**).

| Stage/history | Incoming inventory | Purchase | Sales | Outgoing inventory |
|---|---:|---:|---:|---:|
| Stage 1 | 0 | 35 | 0 | 35 |
| Stage 2: demand 20 | 35 | 35 | 20 | 50 |
| Stage 2: demand 50 | 35 | 35 | 35 | 35 |
| Stage 3: demands (20,20) | 50 | 0 | 20 | 30 |
| Stage 3: demands (20,50) | 50 | 0 | 50 | 0 |
| Stage 3: demands (50,20) | 35 | 0 | 20 | 15 |
| Stage 3: demands (50,50) | 35 | 0 | 35 | 0 |

| (D_2,D_3) | Probability | Total policy cost |
|---|---:|---:|
| (20,20) | 0.25 | -168.5 |
| (20,50) | 0.25 | -411.5 |
| (50,20) | 0.25 | -291.5 |
| (50,50) | 0.25 | -413.0 |

Expected purchase cost is 140, holding cost is 8.875, and revenue is 470.
Consequently, 140 + 8.875 - 470 = -321.125.

## Training and evaluation

The baseline uses stock `SDDP.ContinuousConicDuality`, multi-cuts, serial
execution, and 40 training iterations. A deterministic historical sampler cycles
through all four histories. Cut deletion and cross-node cut sharing are disabled.
The iteration limit is a reproducible benchmark budget, not a stopping proof.

After training, public `SDDP.DecisionRule` evaluations execute the policy on all
four histories. Only immediate stage costs are accumulated; approximate Bellman
terms are excluded. The probability-weighted result is an exact finite-support
policy expectation, up to solver tolerances, rather than a Monte Carlo estimate.

The tests compare the SDDP lower bound and exact policy expectation against the
independent LP optimum with absolute tolerance 1e-6. They also check each path's
cost, inventory balance, sales availability, capacities, terminal purchases, and
common-history decisions.

## Sources

- Arslan, Dowson, and Morton (2024), “An SDDP Algorithm for Multistage Stochastic
  Programs with Decision-Dependent Uncertainty,” supplied by the user; the
  baseline fixes the demand law and omits marketing.
- [SDDP.jl two-stage modeling example](https://sddp.dev/stable/tutorial/example_newsvendor/)
  and [public API reference](https://sddp.dev/stable/apireference/) for the modeling,
  training, and decision-rule APIs used here.
