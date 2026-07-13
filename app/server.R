# =============================================================================
# server.R -- top-level server: one shared parameter state, preset/reset wiring,
# the stale badge, and the five tab modules. Computation lives in the modules
# (from milestone 4 on); this file only assembles and shares state.
# =============================================================================

server <- function(input, output, session) {

  # --- id -> kind map, for updating the right input widget on preset change ---
  ctrl_kind <- local({
    m <- list()
    for (g in pm_controls()) for (ctrl in g$controls) m[[ctrl$id]] <- ctrl$kind
    m
  })
  ids <- pm_control_ids()
  int_ids <- c("n", "T", "R", "seed")   # coerce these to integer

  # --- shared parameter state: sidebar inputs -> a params list ---------------
  # Consumed by every tab. Starts from defaults; each control overwrites its
  # field. Never NULL (inputs carry their ui defaults from first render).
  params <- reactive({
    p <- pm_default_params()
    for (id in ids) {
      v <- input[[id]]
      if (!is.null(v) && !is.na(v)) {
        p[[id]] <- if (id %in% int_ids) as.integer(round(v)) else v
      }
    }
    p
  })

  # --- apply a full params list back onto the sidebar widgets ----------------
  apply_params_to_inputs <- function(p) {
    for (id in ids) {
      val <- p[[id]]
      if (identical(ctrl_kind[[id]], "numeric")) {
        updateNumericInput(session, id, value = val)
      } else {
        updateSliderInput(session, id, value = val)
      }
    }
  }

  # --- preset selection: load the full parameter vector ----------------------
  observeEvent(input$preset, {
    apply_params_to_inputs(pm_preset_params(input$preset))
  }, ignoreInit = TRUE)

  # --- reset: back to Textbook defaults --------------------------------------
  observeEvent(input$reset, {
    if (!identical(input$preset, pm_default_preset())) {
      updateSelectInput(session, "preset", selected = pm_default_preset())
    }
    apply_params_to_inputs(pm_default_params())
  })

  # --- selected preset's lesson caption --------------------------------------
  output$preset_lesson <- renderUI({
    pr <- pm_presets()[[input$preset]]
    if (is.null(pr)) return(NULL)
    tags$p(class = "pm-caption", style = "margin-top:0.25rem;", pr$lesson)
  })

  # --- stale badge: flips when the world changes after something was computed -
  # The mechanism the tabs consume (handoff Sec. 4): any sidebar change marks
  # computed artifacts stale. Tabs (from milestone 4) call stale(FALSE) when they
  # (re)compute. In the shell there is nothing to compute yet, so it simply
  # reflects whether the sidebar has been touched since load.
  stale <- reactiveVal(FALSE)
  observeEvent(params(), { stale(TRUE) }, ignoreInit = TRUE)

  output$stale_badge <- renderUI({
    if (isTRUE(stale())) {
      tags$span(class = "pm-badge pm-badge-stale", "settings changed — rerun")
    } else {
      tags$span(class = "pm-badge pm-badge-fresh", "up to date")
    }
  })

  # --- tab modules (shells for now; share params + stale) --------------------
  mod_live_server("live", params, stale)
  mod_anatomy_server("anatomy", params, stale)
  mod_reliability_server("reliability", params, stale)
  mod_interactions_server("interactions", params, stale)
  mod_guide_server("guide")
}
