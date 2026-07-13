# =============================================================================
# mod_interactions.R -- Tab 4: Interactions, 2-D maps (handoff Sec. 4, GUI Tab 4).
# SHELL (milestone 3): placeholder; curated questions, heatmaps and the
# friction-ranking bars arrive in milestone 7.
# =============================================================================

mod_interactions_ui <- function(id) {
  ns <- NS(id)
  bslib::card(
    bslib::card_header("Interactions"),
    bslib::card_body(
      pm_tab_placeholder(
        "Map how two forces combine across the parameter space.",
        c(
          "Curated questions (one click sets both axes + metric): echo-chamber wealth, manipulation frontier, fee optimum, manufactured cascades, friction ranking.",
          "Free choice of x / y / metric below the curated menu.",
          "Viridis heatmap with contour lines; click a cell to render its 1-D slice beneath.",
          "Progress bar, cancel and CSV / PNG export."
        ),
        milestone = 7
      )
    )
  )
}

mod_interactions_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    invisible(NULL)
  })
}
