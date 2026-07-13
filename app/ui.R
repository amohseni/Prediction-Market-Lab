# =============================================================================
# ui.R -- page layout only (handoff Sec. 2/3). No computation here.
# Title -> three-column precis -> sidebar (presets + Reset + stale badge +
# 5 accordion parameter groups) + main panel (5 tabs). Controls are generated
# from the single spec in pm_controls() so labels/ranges live in one place.
# =============================================================================

# ---- helpers: build one sidebar control and one accordion group -------------

# pm_input_tag(): render a single control (slider / integer slider / numeric)
# with its default value (from pm_default_params()) and a one-line caption.
pm_input_tag <- function(ctrl, defaults) {
  val <- defaults[[ctrl$id]]
  input <- switch(
    ctrl$kind,
    "slider" = sliderInput(ctrl$id, ctrl$label, min = ctrl$min, max = ctrl$max,
                           value = val, step = ctrl$step, width = "100%"),
    "int"    = sliderInput(ctrl$id, ctrl$label, min = ctrl$min, max = ctrl$max,
                           value = val, step = ctrl$step, width = "100%"),
    "numeric" = numericInput(ctrl$id, ctrl$label, value = val, min = ctrl$min,
                             max = ctrl$max, step = ctrl$step, width = "100%")
  )
  tags$div(
    class = "pm-control",
    input,
    tags$p(class = "pm-caption", ctrl$caption)
  )
}

# pm_group_panel(): one accordion panel = a short "details" paragraph + controls.
pm_group_panel <- function(group, defaults) {
  bslib::accordion_panel(
    title = group$title,
    value = group$title,
    tags$p(class = "pm-group-subtitle", tags$em(group$subtitle)),
    tags$p(class = "pm-group-details", group$details),
    lapply(group$controls, pm_input_tag, defaults = defaults)
  )
}

# ---- assemble the sidebar ---------------------------------------------------
pm_defaults <- pm_default_params()

pm_sidebar <- bslib::sidebar(
  width = PM_SIDEBAR_WIDTH,
  title = NULL,
  open = "open",           # start expanded on load (still collapsible)
  # Preset scenario + Reset + stale badge.
  selectInput("preset", "Scenario", choices = names(pm_presets()),
              selected = pm_default_preset(), width = "100%"),
  uiOutput("preset_lesson"),
  tags$div(
    class = "pm-sidebar-actions",
    actionButton("reset", "Reset to defaults", class = "btn-sm btn-outline-secondary"),
    uiOutput("stale_badge", inline = TRUE)
  ),
  tags$hr(),
  # Five parameter groups; one open at a time.
  do.call(bslib::accordion, c(
    list(id = "param_accordion", open = "Information", multiple = FALSE),
    lapply(pm_controls(), pm_group_panel, defaults = pm_defaults)
  ))
)

# ---- assemble the header (title + thesis + three columns) -------------------
pm_header <- tags$div(
  class = "pm-header",
  tags$h1(class = "pm-title", PM_APP_TITLE),
  tags$p(class = "pm-thesis", PM_APP_THESIS),
  do.call(bslib::layout_columns, c(
    list(col_widths = c(4, 4, 4), class = "pm-precis"),
    lapply(PM_PRECIS, function(col) {
      tags$div(
        class = "pm-precis-col",
        tags$h3(class = "pm-precis-head", col$head),
        tags$p(col$body)
      )
    })
  ))
)

# ---- main panel: five tabs --------------------------------------------------
pm_tabs <- bslib::navset_tab(
  id = "main_tabs",
  bslib::nav_panel("Live Market",  mod_live_ui("live")),
  bslib::nav_panel("Run Anatomy",  mod_anatomy_ui("anatomy")),
  bslib::nav_panel("Reliability",  mod_reliability_ui("reliability")),
  bslib::nav_panel("Interactions", mod_interactions_ui("interactions")),
  bslib::nav_panel("Guide",        mod_guide_ui("guide"))
)

# ---- page -------------------------------------------------------------------
ui <- bslib::page_fluid(
  theme = bslib::bs_theme(
    version = 5,
    base_font = bslib::font_google("Inter", local = FALSE),
    primary = PM_COL$omniscient
  ),
  tags$head(tags$style(HTML(pm_app_css()))),
  pm_header,
  bslib::layout_sidebar(
    sidebar = pm_sidebar,
    pm_tabs
  )
)
