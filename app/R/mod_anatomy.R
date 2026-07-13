# =============================================================================
# mod_anatomy.R -- Tab 2: Run Anatomy (handoff Sec. 4, GUI Sec. 4 Tab 2).
# SHELL (milestone 3): placeholder; diagnostics of the current run arrive in
# milestone 5.
# =============================================================================

mod_anatomy_ui <- function(id) {
  ns <- NS(id)
  bslib::card(
    bslib::card_header("Run Anatomy"),
    bslib::card_body(
      pm_tab_placeholder(
        "Why did the price do that? Diagnostics of the current run.",
        c(
          "Distance to p* per round (log scale) — the healing curve.",
          "Price vs wealth-weighted mean belief per round — the aggregation check.",
          "Participation bars: traded / inside no-trade band / never entered.",
          "Belief-migration lines (all beliefs over time) — cascades when herding is on.",
          "Trading volume per round."
        ),
        milestone = 5
      )
    )
  )
}

mod_anatomy_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    invisible(NULL)
  })
}
