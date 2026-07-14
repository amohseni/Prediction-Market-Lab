# =============================================================================
# mod_reliability.R -- Tab 3: Reliability, 1-D sweeps (handoff Sec. 4, GUI Tab 3).
# Sweep any one parameter and watch accuracy respond. Opens on the bundled
# n_eff-ceiling exhibit (never blank); a sweep replaces it. Results are cached
# by input digest and never auto-recompute -- the user clicks Run, and a stale
# note appears if the sidebar changes afterwards.
# =============================================================================

PM_SWEEP_DEFAULTS <- list(param = "n", min = 25, max = 400, points = 6, R = 120)

mod_reliability_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",

    # --- Setup strip ---------------------------------------------------------
    bslib::card(
      bslib::card_body(
        bslib::layout_columns(
          col_widths = c(3, 2, 2, 2, 3),
          selectInput(ns("param"), "Sweep parameter", choices = pm_sweep_param_choices(),
                      selected = PM_SWEEP_DEFAULTS$param, width = "100%"),
          numericInput(ns("min"), "From", value = PM_SWEEP_DEFAULTS$min, width = "100%"),
          numericInput(ns("max"), "To",   value = PM_SWEEP_DEFAULTS$max, width = "100%"),
          numericInput(ns("points"), "Points", value = PM_SWEEP_DEFAULTS$points,
                       min = 3, max = 25, step = 1, width = "100%"),
          numericInput(ns("R"), "Replications (R)", value = PM_SWEEP_DEFAULTS$R,
                       min = 20, max = 1000, step = 10, width = "100%")
        ),
        tags$div(
          class = "pm-sweep-actions",
          checkboxGroupInput(ns("metrics"), "Extra metrics",
                             choices = PM_SWEEP_METRICS, selected = c("AE"),
                             inline = TRUE),
          actionButton(ns("run"), "Run sweep", class = "btn-sm btn-outline-secondary")
        )
      )
    ),

    uiOutput(ns("stale_note")),
    plotOutput(ns("main_plot"), height = "360px"),
    tags$div(class = "pm-sweep-downloads",
             downloadButton(ns("dl_csv"), "Download CSV", class = "btn-sm btn-outline-secondary"),
             downloadButton(ns("dl_png"), "Download PNG", class = "btn-sm btn-outline-secondary")),
    uiOutput(ns("extra_ui"))
  )
}

mod_reliability_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    sweep_df    <- reactiveVal(NULL)   # NULL => show the bundled exhibit
    params_used <- reactiveVal(NULL)   # sidebar params at last sweep (for staleness)

    # When the sweep parameter changes, reset From/To to its natural range.
    observeEvent(input$param, {
      sp <- pm_sweep_params()[[input$param]]
      if (!is.null(sp)) {
        updateNumericInput(session, "min", value = sp$min)
        updateNumericInput(session, "max", value = sp$max)
      }
    }, ignoreInit = TRUE)

    # --- Run the sweep (cached; progress bar) --------------------------------
    observeEvent(input$run, {
      sp <- pm_sweep_params()[[input$param]]
      npts <- max(3L, as.integer(input$points))
      vals <- seq(input$min, input$max, length.out = npts)
      if (identical(sp$kind, "int")) vals <- unique(as.integer(round(vals)))
      base <- params()
      Rr   <- max(20L, as.integer(input$R))
      seed <- if (is.null(base$seed) || is.na(base$seed)) 1L else as.integer(base$seed)

      key <- ensemble_cache_key(base, list(param = input$param, values = vals), Rr, seed)
      cached <- cache_get(key)
      if (!is.null(cached)) {
        res <- cached
      } else {
        res <- withProgress(message = "Running sweep", value = 0, {
          sweep_1d(base, input$param, vals, R = Rr, seed = seed,
                   progress = function(frac) setProgress(value = frac))
        })
        cache_set(key, res)
      }
      sweep_df(res)
      params_used(base)
      stale(FALSE)                     # this sweep reflects the current settings
    })

    # Is the displayed sweep out of date vs the current sidebar?
    is_stale <- reactive({
      !is.null(sweep_df()) && !identical(params_used(), params())
    })
    output$stale_note <- renderUI({
      if (isTRUE(is_stale())) {
        tags$div(class = "pm-stale-note",
                 "Settings changed since this sweep — click Run sweep to update.")
      }
    })

    param_label <- reactive({
      sp <- pm_sweep_params()[[isolate(input$param)]]
      if (is.null(sp)) input$param else sp$label
    })

    # The main plot object (exhibit until a sweep runs) -- shared by render + PNG.
    main_plot_obj <- reactive({
      if (is.null(sweep_df())) {
        if (is.null(PM_NEFF_EXHIBIT)) return(NULL)
        pm_neff_exhibit_plot(PM_NEFF_EXHIBIT)
      } else {
        pm_sweep_brier_plot(sweep_df(), param_label())
      }
    })

    output$main_plot <- renderPlot({ p <- main_plot_obj(); req(p); p }, res = 96)

    # Extra panels appear only after a sweep.
    output$extra_ui <- renderUI({
      req(sweep_df())
      ns <- session$ns
      tagList(
        plotOutput(ns("murphy_plot"), height = "300px"),
        if (length(input$metrics) > 0) plotOutput(ns("metrics_plot"), height = "300px")
      )
    })
    output$murphy_plot  <- renderPlot({ req(sweep_df()); pm_murphy_plot(sweep_df(), param_label()) }, res = 96)
    output$metrics_plot <- renderPlot({
      req(sweep_df()); req(length(input$metrics) > 0)
      pm_sweep_metrics_plot(sweep_df(), param_label(), input$metrics)
    }, res = 96)

    # --- Exports -------------------------------------------------------------
    output$dl_csv <- downloadHandler(
      filename = function() if (is.null(sweep_df())) "neff_exhibit.csv" else
        sprintf("sweep_%s.csv", isolate(input$param)),
      content = function(file) {
        df <- if (is.null(sweep_df())) PM_NEFF_EXHIBIT$data else sweep_df()
        utils::write.csv(df, file, row.names = FALSE)
      })
    output$dl_png <- downloadHandler(
      filename = function() if (is.null(sweep_df())) "neff_exhibit.png" else
        sprintf("sweep_%s.png", isolate(input$param)),
      content = function(file) {
        p <- main_plot_obj(); req(p)
        ggplot2::ggsave(file, p, width = 8, height = 4.8, dpi = 120)
      })
  })
}
