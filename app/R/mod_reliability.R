# =============================================================================
# mod_reliability.R -- Tab 3: Reliability, 1-D sweeps (handoff Sec. 4, GUI Tab 3).
# SHELL (milestone 3): placeholder; sweep engine, theory overlay and the bundled
# n_eff-ceiling exhibit arrive in milestone 6.
# =============================================================================

mod_reliability_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",
    pm_tab_placeholder(
      "Sweep any one parameter and see how accuracy responds.",
      c(
        "Pick a sweep parameter, range, number of points and metrics (Brier / AE / log / bias / REL / RES).",
        "Metric vs parameter with a 95% CI ribbon; prior-Brier and omniscient-Brier reference lines.",
        "A dashed static-benchmark overlay where the frictionless closed form exists.",
        "Sub-panels: Murphy stack, calibration curve, favorite–longshot (when sweeping c).",
        "Opens on the precomputed n_eff-ceiling exhibit; CSV / PNG export."
      ),
      milestone = 6
    )
  )
}

mod_reliability_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    invisible(NULL)
  })
}
