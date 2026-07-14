# Prediction Market Lab

**When are prediction markets reliable?** A simulation model of prediction-market
performance under a variety of conditions.

An interactive R/Shiny lab for exploring the **robustness of prediction markets**. A
single binary market runs on an LMSR automated market maker; a crowd of agents
form Bayesian beliefs from noisy signals and take Kelly-sized positions toward
them, subject to fees, participation costs, correlation, wealth inequality,
herding, and manipulation. The app lets you run one market live, dissect its
anatomy, sweep any parameter, and map two-parameter interaction effects.

> Status: **complete** — all eight build milestones of
> [`docs/CLAUDE_CODE_HANDOFF.md`](docs/CLAUDE_CODE_HANDOFF.md) §8: a validated,
> tested model core and a five-tab Shiny app.

## The app

Launch with `shiny::runApp("app")`. Five tabs share one parameter state (set in
the sidebar via presets or the accordion controls):

- **Live Market** — watch one market resolve trade by trade; intervene with a
  manipulator bot or your own wallet; the price path highlights who moved it.
- **Run Anatomy** — dissect the current run: convergence to the best forecast,
  the aggregation check, participation, belief migration (cascades), volume.
- **Reliability** — sweep any one parameter; Brier with CI against the prior and
  best-possible benchmarks, the Murphy decomposition, and more. Opens on the
  bundled n_eff-ceiling exhibit.
- **Interactions** — 2-D maps of two parameters at once, with five curated
  research questions, a viridis heatmap, click-to-slice, and friction-ranking.
- **Guide** — how the model works, a searchable glossary, and references.

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
  global.R           # bootstrap: libraries, constants, sourcing
  ui.R  server.R     # page layout / top-level server (wires the modules)
  R/
    theme.R          # color + UI palette, the one ggplot theme, app CSS
    core_model.R     # beliefs, LMSR, AgentTurn, RunMarket   (pure, no Shiny)
    core_ensemble.R  # RunEnsemble, metrics, 1-D/2-D sweeps, benchmark, cache
    presets.R        # presets + the single sidebar control spec
    live_engine.R  anatomy_plots.R  reliability_plots.R  interaction_plots.R
    mod_live.R  mod_anatomy.R  mod_reliability.R  mod_interactions.R  mod_guide.R
  data/              # bundled n_eff-ceiling exhibit (.rds)
  tests/testthat/    # unit tests (handoff §7.1)
  scripts/           # run_tests.R, validate.R, make_exhibit.R
  VALIDATION.md      # emergent-behavior report (handoff §7.2)
docs/                # binding spec + design docs
PROGRESS.md          # running build log
```

## Run it

Requires R (developed on 4.4.2) with `shiny`, `bslib`, `ggplot2`, `DT`, `digest`,
`viridisLite`, `dplyr`, and `testthat` (for the tests).

```bash
cd app
Rscript -e 'shiny::runApp(".", port = 8200)'  # launch the app
APP_DIR="$PWD" Rscript scripts/run_tests.R    # unit tests (should be all green)
APP_DIR="$PWD" Rscript scripts/validate.R     # regenerate VALIDATION.md + figures
```

## Validation

Six emergent behaviors are checked against known market theory (full report in
[`app/VALIDATION.md`](app/VALIDATION.md)):

| Check | Behavior | Result |
|---|---|---|
| V1 | Price tracks the wealth-weighted mean belief | PASS (corr ≈ 0.97, ~0 bias) |
| V2 | The `n_eff` accuracy ceiling under correlated signals | PASS |
| V3 | Fees degrade accuracy and thin out trading | PASS |
| V4 | Hanson–Oprea: can a bot improve accuracy? | REVIEW (searched — the bot only adds noise here) |
| V5 | Favorite–longshot miscalibration from noise traders | PASS |
| V6 | Herding makes a brief manipulation persist | PASS |

## License

MIT — see [`LICENSE`](LICENSE).
