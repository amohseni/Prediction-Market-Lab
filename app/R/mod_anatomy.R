# =============================================================================
# mod_anatomy.R -- Tab 2: Run Anatomy (handoff Sec. 4, GUI Sec. 4 Tab 2).
# Diagnostics of the *current* run -- the same trajectory shown in Tab 1, passed
# in as the `traj` reactive (returned by mod_live_server). "Why did the price do
# that?" No new simulation here; it reads the run apart.
# =============================================================================

mod_anatomy_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",
    tags$p(class = "pm-group-details",
           "A dissection of the market currently loaded in Live Market. Change the settings or intervene there and these update."),
    bslib::layout_columns(
      col_widths = c(6, 6),
      plotOutput(ns("convergence"), height = "270px"),
      plotOutput(ns("aggregation"), height = "270px")
    ),
    plotOutput(ns("participation"), height = "280px"),
    uiOutput(ns("migration_ui")),
    plotOutput(ns("volume"), height = "240px")
  )
}

mod_anatomy_server <- function(id, traj) {
  moduleServer(id, function(input, output, session) {
    output$convergence   <- renderPlot({ req(traj()); pm_anatomy_convergence(traj()) },   res = 96)
    output$aggregation   <- renderPlot({ req(traj()); pm_anatomy_aggregation(traj()) },   res = 96)
    output$participation <- renderPlot({ req(traj()); pm_anatomy_participation(traj()) }, res = 96)
    output$volume        <- renderPlot({ req(traj()); pm_anatomy_volume(traj()) },        res = 96)

    # Belief migration only exists with herding on; otherwise a friendly note.
    output$migration_ui <- renderUI({
      req(traj())
      if (pm_anatomy_has_migration(traj())) {
        plotOutput(session$ns("migration"), height = "300px")
      } else {
        tags$div(
          class = "pm-empty-state",
          tags$p(tags$strong("Belief migration")),
          tags$p(paste("Herding is off (h = 0), so beliefs are fixed -- there is nothing to migrate.",
                       "Turn up h in the Traders group to watch beliefs cascade toward the price."))
        )
      }
    })
    output$migration <- renderPlot({ req(traj()); pm_anatomy_migration(traj()) }, res = 96)
  })
}
