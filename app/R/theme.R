# =============================================================================
# theme.R -- Visual language: color constants and the single ggplot theme.
#
# One semantics everywhere (handoff Sec. 6). Every plot in the app pulls its
# colors from PM_COL and applies theme_pm(). No color literals anywhere else.
#
# Depends on: ggplot2 (loaded in global.R). This file is also sourced by the
# model/ensemble code, which only needs the numeric constants below, so the
# ggplot pieces are guarded to no-op if ggplot2 is absent.
# =============================================================================

# ---- Numerical guards (handoff Sec. 1.2) -----------------------------------
# Clamp all prices/beliefs into [P_MIN, P_MAX] before any logit/log. Never let a
# price hit 0 or 1 (would send logit/log to +/-Inf).
P_MIN <- 0.001
P_MAX <- 0.999

# ---- Color semantics (handoff Sec. 6) --------------------------------------
PM_COL <- list(
  price      = "#1a1a1a",  # price path: ink, solid, thick
  prior      = "#9e9e9e",  # prior p0 / prior-Brier: gray, dotted
  omniscient = "#2b6cb0",  # omniscient p* / omn-Brier: blue, dashed
  manip      = "#c0392b",  # manipulation (bot + structural): red
  user       = "#e67e22",  # user trades: orange
  informed   = "#2b6cb0",  # informed agents (swarm/log) -- reuse omniscient blue
  noise      = "#7f8c8d",  # noise traders: muted gray
  ci_ribbon  = "#9e9e9e"   # CI ribbons: gray, alpha 0.25 at use site
)

# Trader-type -> color map, used by swarm dots, event log, color-by-trader path.
PM_TYPE_COL <- c(
  informed    = PM_COL$informed,
  noise       = PM_COL$noise,
  manipulator = PM_COL$manip,
  bot         = PM_COL$manip,
  user        = PM_COL$user
)

PM_CI_ALPHA <- 0.25

# ---- The one theme ----------------------------------------------------------
# theme_pm(): applied to every plot. White background, labeled axes always,
# legends where needed. Guarded so this file can be sourced by headless model
# code that has not loaded ggplot2.
theme_pm <- function(base_size = 13) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.background = ggplot2::element_rect(fill = "white", color = NA),
      plot.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = "#ececec"),
      axis.title       = ggplot2::element_text(color = "#333333"),
      axis.text        = ggplot2::element_text(color = "#555555"),
      legend.position  = "right",
      plot.title       = ggplot2::element_text(face = "bold", size = base_size + 2),
      plot.subtitle    = ggplot2::element_text(color = "#666666")
    )
}
