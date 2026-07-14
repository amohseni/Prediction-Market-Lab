# =============================================================================
# ui.R -- page layout only (handoff Sec. 2/3). No computation here.
# Title -> three-column precis -> sidebar (presets + Reset + stale badge +
# 5 accordion parameter groups) + main panel (5 tabs). Controls are generated
# from the single spec in pm_controls() so labels/ranges live in one place.
# =============================================================================

# ---- helpers: build one sidebar control and one accordion group -------------

# pm_control_label(): build a control's label as "Description \(sym\)" -- text
# first, symbol second (MathJax typesets the symbol). Description is sentence-
# cased. Controls without a symbol (sym = NA) show the description alone.
pm_control_label <- function(ctrl) {
  desc <- sub("^(.)", "\\U\\1", ctrl$desc, perl = TRUE)   # sentence-case first letter
  if (is.null(ctrl$sym) || is.na(ctrl$sym)) return(desc)
  HTML(paste0(desc, " \\(", ctrl$sym, "\\)"))
}

# pm_input_tag(): render a single control (slider / integer slider / numeric)
# with its default value (from pm_default_params()) and a one-line caption.
pm_input_tag <- function(ctrl, defaults) {
  val <- defaults[[ctrl$id]]
  lbl <- pm_control_label(ctrl)
  input <- switch(
    ctrl$kind,
    "slider" = sliderInput(ctrl$id, lbl, min = ctrl$min, max = ctrl$max,
                           value = val, step = ctrl$step, width = "100%"),
    "int"    = sliderInput(ctrl$id, lbl, min = ctrl$min, max = ctrl$max,
                           value = val, step = ctrl$step, width = "100%"),
    "numeric" = numericInput(ctrl$id, lbl, value = val, min = ctrl$min,
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

# ---- main panel: five tabs (underline style -> reads like text, not boxes) --
pm_tabs <- bslib::navset_underline(
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
    base_font = bslib::font_collection("Helvetica Neue", "Helvetica", "Arial", "sans-serif"),
    primary = PM_UI$accent      # dark gray: no blue chrome
  ),
  tags$head(
    tags$style(HTML(pm_app_css())),
    # bslib renders a tab's plots at 0/tiny width during the hidden->shown
    # transition (causing "invalid quartz() device size" or oversized text).
    # Nudge Shiny to re-measure and re-render once the tab is visible.
    tags$script(HTML(
      "document.addEventListener('shown.bs.tab', function(){",
      "  setTimeout(function(){ window.dispatchEvent(new Event('resize')); }, 60);",
      "});"))
  ),
  withMathJax(),                # typeset the LaTeX symbols in labels / details
  pm_header,
  bslib::layout_sidebar(
    sidebar = pm_sidebar,
    pm_tabs
  )
)
