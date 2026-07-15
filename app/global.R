# =============================================================================
# global.R -- app bootstrap: libraries, constants, and sourcing of the R/ core.
# Sourced once by Shiny before ui.R/server.R. We source R/ explicitly (in
# dependency order) and turn OFF Shiny's automatic R/ autoloading so the load
# order is deterministic -- theme.R defines P_MIN/P_MAX that core_model.R needs.
# =============================================================================

options(shiny.autoload.r = FALSE)   # we source R/ ourselves, below

# Null-coalescing helper (used across modules); harmless if a package exports it.
`%||%` <- function(a, b) if (is.null(a)) b else a

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(ggplot2)
  library(htmltools)
})
# Used lazily by later tabs; loaded here so a missing package fails fast at boot.
for (pkg in c("DT", "digest", "viridisLite", "dplyr")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    warning(sprintf("package '%s' not installed; some tabs will be limited", pkg))
  }
}

# Source the model core and UI pieces in dependency order.
local({
  r_dir <- "R"
  files <- c(
    "theme.R",           # colors, P_MIN/P_MAX, ggplot theme, UI helpers
    "core_model.R",      # beliefs, LMSR, AgentTurn, RunMarket
    "core_ensemble.R",   # ensembles, metrics, sweeps, cache
    "live_engine.R",     # Tab 1 live-run assembly + plot/log/pnl helpers
    "anatomy_plots.R",   # Tab 2 per-round diagnostic plots
    "reliability_plots.R", # Tab 3 sweep plots + sweep-param metadata
    "interaction_plots.R", # Tab 4 2-D maps + curated questions
    "presets.R",         # presets + sidebar control spec
    "mod_live.R", "mod_anatomy.R", "mod_reliability.R",
    "mod_interactions.R", "mod_guide.R"
  )
  for (f in files) source(file.path(r_dir, f), local = FALSE)
})

# ---- App-level constants ----------------------------------------------------
PM_APP_TITLE    <- "When are prediction markets reliable?"
PM_APP_THESIS   <- "A simulation model of prediction market performance under a variety of conditions."
PM_SIDEBAR_WIDTH <- 340   # px; ~1/4 of a standard window (handoff Sec. 3)

# Bundled n_eff-ceiling exhibit for Tab 3's initial (never-blank) state. NULL if
# it has not been generated yet (scripts/make_exhibit.R).
PM_NEFF_EXHIBIT <- local({
  f <- file.path("data", "neff_exhibit.rds")
  if (file.exists(f)) readRDS(f) else NULL
})

# Three-column precis under the title (GUI Sec. 2).
PM_PRECIS <- list(
  list(head = "The model",
       body = "A prediction market turns bets into a forecast: the price of a bet, between 0 and 1, can be interpreted as the market's estimate of the probability that the proposition under consideration will resolve as true. Traders with different wealth each hold partial, potentially biased information about the proposition's truth, and their errors can overlap rather than being independent. They trade with an automated dealer that will always buy or sell at the current price."),
  list(head = "The mechanism",
       body = "A trader who believes the price is too low buys, and buying pushes the price up toward their belief. The more wealth they stake, the further the price moves, so at any moment the price blends the traders' beliefs weighted by their wealth. Blending is the market's power: independent mistakes cancel, so under the right conditions the price is more accurate than any individual trader. When the proposition resolves, correct bets pay off, so across repeated markets wealth tends to flow toward better-informed traders and the weighting improves. But cancellation has a limit: whatever error the traders share remains in the price, and no market, however large, can be more accurate than the shared error allows."),
  list(head = "The science",
       body = "The traders' shared error sets the best accuracy any market can achieve, and four forces can hold performance below it: trading fees make small corrections not worth making, low liquidity makes prices overreact or barely respond, concentrated wealth lets a few voices dominate, and imitation spreads errors instead of canceling them. A manipulator, who spends money to push the price toward a target, is the sharpest test: a pushed price is a mispricing that informed traders profit by correcting, so under the right conditions the market resists, and manipulation can even improve accuracy. The app lets you vary every force and map when the market stays accurate, stalls, or fails outright.")
)
