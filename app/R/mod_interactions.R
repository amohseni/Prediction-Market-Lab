# =============================================================================
# mod_interactions.R -- Tab 4: Interactions, 2-D maps (handoff Sec. 4, GUI Tab 4).
# Curated questions (each fixes both axes + metric) or a free x/y/metric choice,
# rendered as a viridis heatmap with contours; click a cell to slice along x.
# One special question (q5) is the friction-ranking bar exhibit. Cached; never
# auto-recomputes; a stale note appears when the sidebar changes.
# =============================================================================

PM_MAP_DEFAULTS <- list(resolution = 5, R = 50)

# Axis range for any parameter id (sidebar sweepables + B_m / r_wp).
pm_axis_range <- function(id) {
  sp <- pm_sweep_params()
  if (!is.null(sp[[id]])) return(c(sp[[id]]$min, sp[[id]]$max))
  switch(id, B_m = c(0.02, 0.5), r_wp = c(-1, 1), c(0, 1))
}
pm_axis_is_int <- function(id) {
  sp <- pm_sweep_params(); identical(sp[[id]]$kind, "int")
}

mod_interactions_ui <- function(id) {
  ns <- NS(id)
  qs <- pm_interaction_questions()
  q_choices <- c(stats::setNames(names(qs), vapply(qs, `[[`, "", "label")),
                 "Free choice (pick axes below)" = "free")
  tags$div(
    class = "pm-tab-body",
    bslib::card(
      bslib::card_body(
        radioButtons(ns("question"), "Curated question", choices = q_choices,
                     selected = "q1", width = "100%"),
        bslib::layout_columns(
          col_widths = c(3, 3, 3, 1, 2),
          selectInput(ns("x"), "x-axis", choices = pm_interaction_axis_choices(),
                      selected = "rho", width = "100%"),
          selectInput(ns("y"), "y-axis", choices = pm_interaction_axis_choices(),
                      selected = "alpha_w", width = "100%"),
          selectInput(ns("metric"), "Metric", choices = PM_INTERACTION_METRICS,
                      selected = "AE", width = "100%"),
          numericInput(ns("resolution"), "Grid", value = PM_MAP_DEFAULTS$resolution,
                       min = 4, max = 10, step = 1, width = "100%"),
          numericInput(ns("R"), "R", value = PM_MAP_DEFAULTS$R, min = 20, max = 500,
                       step = 10, width = "100%")
        ),
        tags$div(class = "pm-sweep-actions",
                 tags$span(class = "pm-caption", "Maps run many ensembles — expect a short wait."),
                 actionButton(ns("run"), "Run map", class = "btn-sm btn-outline-secondary"))
      )
    ),
    uiOutput(ns("stale_note")),
    uiOutput(ns("main_ui")),
    tags$div(class = "pm-sweep-downloads",
             downloadButton(ns("dl_csv"), "Download CSV", class = "btn-sm btn-outline-secondary"),
             downloadButton(ns("dl_png"), "Download PNG", class = "btn-sm btn-outline-secondary")),
    plotOutput(ns("slice_plot"), height = "260px")
  )
}

mod_interactions_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    map_df   <- reactiveVal(NULL)   # sweep_2d result (heatmap) ...
    bars_df  <- reactiveVal(NULL)   # ... or hanson_oprea_effect result (q5)
    meta     <- reactiveVal(NULL)   # list(x, y, metric, contour)
    used     <- reactiveVal(NULL)   # sidebar params at last run
    clicked_y <- reactiveVal(NULL)

    # Reflect a curated question's axes in the dropdowns (informational; a
    # curated run uses the question spec regardless). Fires on load too, so the
    # dropdowns match the default question.
    observeEvent(input$question, {
      q <- input$question
      if (q %in% c("free", "q5")) return()
      spec <- pm_interaction_questions()[[q]]
      updateSelectInput(session, "x", selected = spec$x)
      updateSelectInput(session, "y", selected = spec$y)
      updateSelectInput(session, "metric", selected = spec$metric)
    })

    # --- Run the map ---------------------------------------------------------
    observeEvent(input$run, {
      base <- params()
      Rr <- max(20L, as.integer(input$R))
      seed <- if (is.null(base$seed) || is.na(base$seed)) 1L else as.integer(base$seed)
      q <- input$question

      if (q == "q5") {                       # friction-ranking bars
        key <- ensemble_cache_key(base, list(q = "q5"), Rr, seed)
        res <- cache_get(key)
        if (is.null(res)) {
          res <- withProgress(message = "Comparing frictions", value = 0,
            hanson_oprea_effect(base, level = 0.2, R = Rr, seed = seed,
                                progress = function(f) setProgress(value = f)))
          cache_set(key, res)
        }
        bars_df(res); map_df(NULL); clicked_y(NULL)
        meta(list(mode = "bars")); used(base); stale(FALSE)
        return()
      }

      if (q == "free") {
        xp <- input$x; yp <- input$y; met <- input$metric
        extra <- NULL; contour <- FALSE
        xr <- pm_axis_range(xp); yr <- pm_axis_range(yp)
      } else {
        spec <- pm_interaction_questions()[[q]]
        xp <- spec$x; yp <- spec$y; met <- spec$metric
        extra <- spec$extra; contour <- isTRUE(spec$contour)
        xr <- spec$xr; yr <- spec$yr
      }
      if (identical(xp, yp)) { showNotification("Pick two different axes.", type = "warning"); return() }
      res_n <- max(4L, as.integer(input$resolution))
      xv <- seq(xr[1], xr[2], length.out = res_n)
      yv <- seq(yr[1], yr[2], length.out = res_n)
      if (pm_axis_is_int(xp)) xv <- unique(round(xv))
      if (pm_axis_is_int(yp)) yv <- unique(round(yv))

      key <- ensemble_cache_key(base, list(x = xp, y = yp, xv = xv, yv = yv,
                                           extra = extra), Rr, seed)
      res <- cache_get(key)
      if (is.null(res)) {
        res <- withProgress(message = "Running map", value = 0,
          sweep_2d(base, xp, xv, yp, yv, R = Rr, seed = seed, extra = extra,
                   progress = function(f) setProgress(value = f)))
        cache_set(key, res)
      }
      map_df(res); bars_df(NULL); clicked_y(NULL)
      meta(list(mode = "heatmap", x = xp, y = yp, metric = met, contour = contour))
      used(base); stale(FALSE)
    })

    is_stale <- reactive({
      (!is.null(map_df()) || !is.null(bars_df())) && !identical(used(), params())
    })
    output$stale_note <- renderUI({
      if (isTRUE(is_stale()))
        tags$div(class = "pm-stale-note",
                 "Settings changed since this map — click Run map to update.")
    })

    # --- Main plot (heatmap or bars) + click-to-slice ------------------------
    main_plot_obj <- reactive({
      m <- meta()
      if (is.null(m)) return(NULL)
      if (identical(m$mode, "bars")) { req(bars_df()); pm_friction_ranking_plot(bars_df()) }
      else {
        req(map_df())
        # Frontier = the median distortion level, so a heavy contour always shows.
        frontier <- if (isTRUE(m$contour))
          stats::median(map_df()[[m$metric]], na.rm = TRUE) else NULL
        pm_heatmap_plot(map_df(), m$x, m$y, m$metric, contour = m$contour,
                        contour_frontier = frontier)
      }
    })

    output$main_ui <- renderUI({
      if (is.null(meta())) {
        tags$div(class = "pm-empty-state",
                 tags$p(tags$strong("Pick a question and click Run map.")),
                 tags$p("Each map runs a grid of ensembles, so it takes a little while; results are cached."))
      } else if (identical(meta()$mode, "bars")) {
        plotOutput(ns("main_plot"), height = "360px")
      } else {
        plotOutput(ns("main_plot"), height = "380px",
                   click = clickOpts(ns("hm_click")))
      }
    })
    output$main_plot <- renderPlot({ p <- main_plot_obj(); req(p); p }, res = 96)

    observeEvent(input$hm_click, { clicked_y(input$hm_click$y) })
    output$slice_plot <- renderPlot({
      m <- meta(); req(m); req(identical(m$mode, "heatmap")); req(map_df()); req(clicked_y())
      pm_interaction_slice_plot(map_df(), m$x, m$y, m$metric, clicked_y())
    }, res = 96)

    # --- Exports -------------------------------------------------------------
    output$dl_csv <- downloadHandler(
      filename = function() "interaction_map.csv",
      content = function(file) {
        df <- if (!is.null(map_df())) map_df() else bars_df(); req(df)
        utils::write.csv(df, file, row.names = FALSE)
      })
    output$dl_png <- downloadHandler(
      filename = function() "interaction_map.png",
      content = function(file) { p <- main_plot_obj(); req(p)
        ggplot2::ggsave(file, p, width = 7.5, height = 5, dpi = 120) })
  })
}
