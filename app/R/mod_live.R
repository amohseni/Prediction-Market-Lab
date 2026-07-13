# =============================================================================
# mod_live.R -- Tab 1: Live Market (handoff Sec. 4, GUI Sec. 4 Tab 1).
# SHELL (milestone 3): placeholder describing the tab; the animation engine,
# bot, user wallet, color modes and post-resolution card arrive in milestone 4.
# =============================================================================

mod_live_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",
    pm_tab_placeholder(
      "Watch one market work, trade by trade.",
      c(
        "Price path over trade index, with prior (gray dotted) and best-possible p* (blue dashed) reference lines.",
        "Run / Pause / Step / New market controls, a speed control and a scrub slider.",
        "A manipulator-bot card and a user-wallet card for mid-run interventions.",
        "An animated agent swarm (belief vs position, size = wealth, color = type).",
        "A plain-language event log and a post-resolution P&L card."
      ),
      milestone = 4
    )
  )
}

mod_live_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    # Wiring arrives in milestone 4. The `params` reactive and `stale` flag are
    # already threaded in so the tab can consume shared state without rework.
    invisible(NULL)
  })
}
