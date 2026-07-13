# =============================================================================
# mod_guide.R -- Tab 5: Guide (handoff Sec. 4, GUI Sec. 4 Tab 5).
# SHELL (milestone 3): placeholder; How-it-works / Glossary / References content
# arrives in milestone 8.
# =============================================================================

mod_guide_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",
    pm_tab_placeholder(
      "Reference material — no computation.",
      c(
        "How it works: a readable account of the model and the three frictions.",
        "Glossary: every term of art, searchable.",
        "References: the literature behind the model."
      ),
      milestone = 8
    )
  )
}

mod_guide_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    invisible(NULL)
  })
}
