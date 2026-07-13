# Prediction Market Lab

**When do markets know things? Watch one work — and find out when it fails.**

An interactive R/Shiny lab for exploring the **robustness of prediction markets**. A
single binary market runs on an LMSR automated market maker; a crowd of agents
form Bayesian beliefs from noisy signals and take Kelly-sized positions toward
them, subject to fees, participation costs, correlation, wealth inequality,
herding, and manipulation. The app lets you run one market live, dissect its
anatomy, sweep any parameter, and map two-parameter interaction effects.

> Status: **model core + ensemble layer complete and validated** (build
> milestones 1–2 of [`docs/CLAUDE_CODE_HANDOFF.md`](docs/CLAUDE_CODE_HANDOFF.md)
> §8). The Shiny UI (tabs) is next.

## What the model does

- **One market, one event** `A = 1[θ ≥ c]`. Agents see noisy signals of the
  latent state θ and update via conjugate-normal Bayes (all closed form).
- **LMSR maker** with closed-form price/cost/budget formulas; the operator's
  worst-case loss is bounded by `b·ln 2`.
- **Agents** take a Kelly-sized position toward their belief each round, gated by
  a proportional fee `τ`, a fixed cost `κ`, and a one-time participation cost
  `c_part`. Manipulators are ordinary agents with a frozen belief; an optional
  manipulator **bot** lives outside the crowd.
- **Ensembles** of independent markets yield the accuracy scores: Brier and its
  Murphy decomposition, the accuracy-efficiency ratio **AE**, calibration, log
  score, bias, and a frictionless wealth-weighted static benchmark.

See [`docs/PREDICTION_MARKET_MODEL_PLAN.md`](docs/PREDICTION_MARKET_MODEL_PLAN.md)
for the full rationale and literature, and
[`docs/GUI_DESIGN.md`](docs/GUI_DESIGN.md) for the interface design.

## Layout

```
app/
  R/
    theme.R          # color constants, P_MIN/P_MAX, the one ggplot theme
    core_model.R     # beliefs, LMSR, AgentTurn, RunMarket   (pure, no Shiny)
    core_ensemble.R  # RunEnsemble, metrics, sweeps, static benchmark, cache
  tests/testthat/    # unit tests (handoff §7.1)
  scripts/
    run_tests.R      # run the test suite
    validate.R       # emergent-behavior validation -> VALIDATION.md + figures
  figures/validation/# generated validation figures
  VALIDATION.md      # emergent-behavior report (handoff §7.2)
docs/                # binding spec + design docs
PROGRESS.md          # running build log
```

## Run it

Requires R (developed on 4.4.2) with `testthat`, `ggplot2`, `digest`, `dplyr`.

```bash
cd app
APP_DIR="$PWD" Rscript scripts/run_tests.R    # unit tests (should be all green)
APP_DIR="$PWD" Rscript scripts/validate.R     # regenerate VALIDATION.md + figures
```

## Validation

Three emergent behaviors are checked against known market theory (full report in
[`app/VALIDATION.md`](app/VALIDATION.md)):

| Check | Behavior | Result |
|---|---|---|
| V1 | Price tracks the wealth-weighted mean belief | PASS (corr ≈ 0.97, ~0 bias) |
| V2 | The `n_eff` accuracy ceiling under correlated signals | PASS |
| V3 | Fees degrade accuracy and thin out trading | PASS |

## License

MIT — see [`LICENSE`](LICENSE).
