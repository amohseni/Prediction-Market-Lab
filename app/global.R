# =============================================================================
# global.R -- app bootstrap: libraries, constants, and sourcing of the R/ core.
# Sourced once by Shiny before ui.R/server.R. We source R/ explicitly (in
# dependency order) and turn OFF Shiny's automatic R/ autoloading so the load
# order is deterministic -- theme.R defines P_MIN/P_MAX that core_model.R needs.
# =============================================================================

options(shiny.autoload.r = FALSE)   # we source R/ ourselves, below

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

# Three-column precis under the title (GUI Sec. 2, verbatim copy).
PM_PRECIS <- list(
  list(head = "The model",
       body = "A hidden truth; traders with noisy, correlated clues, unequal wealth, betting against an automated market maker."),
  list(head = "The mechanism",
       body = "Traders move the price toward their beliefs, wallet-limited. Watch the price converge — then try to manipulate it."),
  list(head = "The science",
       body = "Accuracy measured against hard limits: correlated errors cap what any market can know; fees, inequality, herding, and manipulators do the rest. Map the failure modes in parameter space.")
)
