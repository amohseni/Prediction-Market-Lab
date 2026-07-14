# =============================================================================
# theme.R -- Visual language: color constants and the single ggplot theme.
#
# One semantics everywhere (handoff Sec. 6). Every plot in the app pulls its
# colors from PM_COL and applies theme_pm(). No color literals anywhere else.
#
# Depends on: ggplot2 (loaded in global.R). This file is also sourced by the
# model/ensemble code, which only needs the numeric constants below, so the
# ggplot pieces are guarded to no-op if ggplot2 is absent.
# =============================================================================

# ---- Numerical guards (handoff Sec. 1.2) -----------------------------------
# Clamp all prices/beliefs into [P_MIN, P_MAX] before any logit/log. Never let a
# price hit 0 or 1 (would send logit/log to +/-Inf).
P_MIN <- 0.001
P_MAX <- 0.999

# ---- Color semantics (handoff Sec. 6) --------------------------------------
PM_COL <- list(
  price      = "#1a1a1a",  # price path: ink, solid, thick
  prior      = "#9e9e9e",  # prior p0 / prior-Brier: gray, dotted
  omniscient = "#2b6cb0",  # omniscient p* / omn-Brier: blue, dashed
  manip      = "#c0392b",  # manipulation (bot + structural): red
  user       = "#e67e22",  # user trades: orange
  benchmark  = "#2e7d32",  # wealth-weighted / static benchmark: green (Tabs 2,3)
  informed   = "#2b6cb0",  # informed agents (swarm/log) -- reuse omniscient blue
  noise      = "#7f8c8d",  # noise traders: muted gray
  ci_ribbon  = "#9e9e9e"   # CI ribbons: gray, alpha 0.25 at use site
)

# Trader-type -> color map, used by swarm dots, event log, color-by-trader path.
PM_TYPE_COL <- c(
  informed    = PM_COL$informed,
  noise       = PM_COL$noise,
  manipulator = PM_COL$manip,
  bot         = PM_COL$manip,
  user        = PM_COL$user
)

PM_CI_ALPHA <- 0.25

# ---- UI (chrome) palette: grayscale only ------------------------------------
# House style: text is only black / dark gray, UI panels are very light gray,
# accents are dark gray. Hue is reserved for plots (PM_COL above). Everything in
# pm_app_css() draws from here so no color literals leak into the chrome.
PM_UI <- list(
  text        = "#212529",  # body / titles: near-black
  text_muted  = "#495057",  # secondary text, group subtitles
  text_faint  = "#6c757d",  # captions / help text
  accent      = "#343a40",  # interactive dark gray (tabs, sliders, buttons)
  panel_bg    = "#f8f9fa",  # description / summary panels
  panel_bg_alt= "#fafafa",  # accordion body
  header_bg   = "#f5f5f5",  # accordion / card headers
  hover_bg    = "#e9ecef",  # header hover
  border      = "#dee2e6",  # light borders
  border_dark = "#495057"   # accent rule (e.g. panel left border)
)

# One typeface for all text: Helvetica Neue system stack, matching the other
# apps (default Bootstrap sans). No web font.
PM_FONT <- "'Helvetica Neue', Helvetica, Arial, sans-serif"

# ---- The one theme ----------------------------------------------------------
# pm_app_css(): the app's custom CSS. Returned as a string for a single <style>
# block in ui.R. Grayscale chrome only (PM_UI); no hue. Overrides bslib/Shiny
# component colors (tabs, accordion, sliders) that otherwise default to blue.
pm_app_css <- function() {
  # Build from named tokens (no positional sprintf) so the CSS stays readable
  # and adding a rule never means recounting arguments.
  tmpl <- "
    /* One typeface everywhere; near-black body text */
    body, .bslib-page-fluid { font-family: {font}; color: {text}; }

    /* Header */
    .pm-header { padding: 0.4rem 0 0.25rem 0; }
    .pm-title { font-weight: 700; color: {text}; letter-spacing: -0.01em; margin-bottom: 0.15rem; }
    .pm-thesis { font-size: 1.1rem; color: {muted}; margin-bottom: 1.1rem; }

    /* Three-column precis, set in a light-gray panel (no decorative rules) */
    .pm-precis { background: {panel}; border: 1px solid {border}; border-radius: 4px;
      padding: 1rem 1.1rem; margin-bottom: 1.25rem; }
    .pm-precis-head { font-size: 0.78rem; text-transform: uppercase;
      letter-spacing: 0.07em; color: {muted}; margin-bottom: 0.35rem; font-weight: 700; }
    .pm-precis-col p { color: {muted}; font-size: 0.92rem; margin-bottom: 0; line-height: 1.5; }

    /* Sidebar controls */
    .pm-control { margin-bottom: 0.65rem; }
    .pm-caption { font-size: 0.8rem; color: {faint}; margin: -0.35rem 0 0 0; line-height: 1.3; }
    .pm-group-subtitle { color: {muted}; margin-bottom: 0.25rem; font-size: 0.88rem; }
    .pm-group-details { color: {faint}; font-size: 0.82rem; margin-bottom: 0.85rem; line-height: 1.45; }
    .control-label, .form-label { font-weight: 600; color: {text}; }

    /* Sidebar actions + stale badge (grayscale, differentiated by fill/weight) */
    .pm-sidebar-actions { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.5rem; }
    .pm-badge { font-size: 0.74rem; padding: 0.2rem 0.55rem; border-radius: 0.35rem;
      border: 1px solid {border}; white-space: nowrap; }
    .pm-badge-fresh { background: {hover}; color: {muted}; }
    .pm-badge-stale { background: {accent}; color: #ffffff; border-color: {accent}; font-weight: 600; }

    /* Tabs (underline style): same color/weight as the sidebar section titles */
    .nav-underline .nav-link { color: {muted}; font-weight: 600; }
    .nav-underline .nav-link:hover { color: {text}; }
    .nav-underline .nav-link.active { color: {text}; font-weight: 600; border-bottom-color: {accent}; }
    a { color: {text}; }

    /* Tab content padding */
    .pm-tab-body { padding-top: 0.85rem; color: {text}; }

    /* Live Market: control strip, cards, log, P&L table */
    .pm-live-controls { display: flex; align-items: flex-end; gap: 0.9rem;
      flex-wrap: wrap; margin-bottom: 0.5rem; }
    .pm-live-controls .form-group { margin-bottom: 0; }
    .pm-live-scrub { flex: 1 1 260px; min-width: 220px; }
    .pm-live-colormode { margin: 0.25rem 0 -0.25rem 0; }
    .pm-wallet-buttons { display: flex; gap: 0.5rem; margin-bottom: 0.4rem; }
    .pm-wallet-line { font-size: 0.95rem; margin-bottom: 0.6rem; }
    .pm-event-log { font-family: inherit; white-space: pre-wrap; font-size: 0.82rem;
      color: {muted}; background: {panel}; border: 1px solid {border};
      border-radius: 4px; padding: 0.6rem 0.75rem; max-height: 220px; overflow-y: auto; }
    /* Reliability (Tab 3) setup + exports + stale note */
    .pm-sweep-actions { display: flex; align-items: center; justify-content: space-between;
      gap: 1rem; flex-wrap: wrap; margin-top: 0.25rem; }
    .pm-sweep-downloads { display: flex; gap: 0.5rem; margin: 0.6rem 0; }
    .pm-stale-note { background: {header}; border-left: 3px solid {accent};
      color: {muted}; font-size: 0.85rem; padding: 0.5rem 0.75rem;
      border-radius: 3px; margin: 0.4rem 0 0.6rem 0; }

    /* Guide (Tab 5) prose */
    .pm-guide-section { padding-top: 0.75rem; max-width: 820px; }
    .pm-guide-prose h4 { font-weight: 700; color: {text}; margin: 1.25rem 0 0.4rem 0;
      font-size: 1.02rem; }
    .pm-guide-prose h4:first-child { margin-top: 0.25rem; }
    .pm-guide-prose p, .pm-guide-prose li { color: {muted}; line-height: 1.6; font-size: 0.94rem; }
    .pm-guide-prose b { color: {text}; }
    .pm-guide-refs li { color: {muted}; line-height: 1.5; margin-bottom: 0.5rem; font-size: 0.92rem; }
    .pm-anatomy-link { color: {accent}; font-weight: 600; cursor: pointer; text-decoration: none; }
    .pm-anatomy-link:hover { text-decoration: underline; color: {text}; }

    .pm-empty-state { background: {panel}; border: 1px dashed {border};
      border-radius: 4px; padding: 1.1rem 1.25rem; margin: 0.5rem 0; color: {muted}; }
    .pm-empty-state p { margin: 0 0 0.35rem 0; }
    .pm-post-card { margin-top: 0.9rem; }
    .pm-pnl-table { width: 100%; font-size: 0.9rem; margin-top: 0.4rem; }
    .pm-pnl-table th { color: {muted}; font-weight: 600; border-bottom: 1px solid {border};
      padding: 0.2rem 0; }
    .pm-pnl-table td { padding: 0.15rem 0; border-bottom: 1px solid {panel}; }

    /* Accordion: light-gray headers, dark title, no blue active tint */
    .accordion-button { background: {header}; color: {text}; font-weight: 600; }
    .accordion-button:not(.collapsed) { background: {header}; color: {text}; box-shadow: none; }
    .accordion-button:hover { background: {hover}; }
    .accordion-button:focus { box-shadow: none; border-color: {accent}; }
    .accordion-body { background: {panel_alt}; }
    .accordion-button::after { filter: grayscale(1) brightness(0.5); }

    /* Sliders (ionRangeSlider): neutral dark gray, no blue/green */
    .irs--shiny .irs-bar { background: {accent}; border-top-color: {accent}; border-bottom-color: {accent}; }
    .irs--shiny .irs-from, .irs--shiny .irs-to, .irs--shiny .irs-single { background: {accent}; }
    .irs--shiny .irs-from:before, .irs--shiny .irs-to:before, .irs--shiny .irs-single:before { border-top-color: {accent}; }
    .irs--shiny .irs-handle { border: 1px solid {accent}; }
    .irs--shiny .irs-handle:hover { border-color: {accent}; }

    /* Buttons */
    .btn-outline-secondary { color: {accent}; border-color: {accent}; }
    .btn-outline-secondary:hover { background: {accent}; color: #ffffff; border-color: {accent}; }
  "
  repl <- c(
    "{font}" = PM_FONT,       "{text}" = PM_UI$text,     "{muted}" = PM_UI$text_muted,
    "{faint}" = PM_UI$text_faint, "{accent}" = PM_UI$accent,
    "{panel}" = PM_UI$panel_bg, "{panel_alt}" = PM_UI$panel_bg_alt,
    "{header}" = PM_UI$header_bg, "{hover}" = PM_UI$hover_bg, "{border}" = PM_UI$border
  )
  for (tok in names(repl)) tmpl <- gsub(tok, repl[[tok]], tmpl, fixed = TRUE)
  tmpl
}

# pm_tab_placeholder(): a tidy "what this tab will show" block used by the
# milestone-3 shell modules. `lead` is a one-line purpose; `items` is a bullet
# list of the tab's planned contents; `milestone` names the build step that
# fills it in. Requires shiny/htmltools (present whenever the UI is built).
pm_tab_placeholder <- function(lead, items, milestone) {
  htmltools::tagList(
    htmltools::tags$p(htmltools::tags$strong(lead)),
    htmltools::tags$ul(lapply(items, htmltools::tags$li)),
    htmltools::tags$p(
      style = sprintf("color:%s; font-style:italic; margin-top:0.75rem;", PM_UI$text_faint),
      sprintf("Wired up in build milestone %d.", milestone)
    )
  )
}

# theme_pm(): applied to every plot (handoff Sec. 6). White panel, subtle gray
# grid, near-black text, system font -- matching the house theme_sim(). Color is
# carried only by the geoms (PM_COL). Guarded to no-op without ggplot2.
theme_pm <- function(base_size = 13) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  ggplot2::theme_minimal(base_size = base_size, base_family = "") +
    ggplot2::theme(
      plot.title.position = "plot",
      # Bottom margins keep the (vertically centered) y-axis title from bumping
      # into the title/subtitle: whichever text is lowest sits >= 10pt above the panel.
      plot.title       = ggplot2::element_text(face = "bold", size = base_size + 1,
                                               color = PM_UI$text,
                                               margin = ggplot2::margin(b = 10)),
      plot.subtitle    = ggplot2::element_text(color = "grey40", size = base_size - 2,
                                               margin = ggplot2::margin(t = -4, b = 10)),
      panel.background = ggplot2::element_rect(fill = "white", color = NA),
      plot.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = "#ececec", linewidth = 0.25),
      axis.title       = ggplot2::element_text(color = "grey20"),
      axis.text        = ggplot2::element_text(color = "grey20"),
      strip.text       = ggplot2::element_text(face = "bold"),
      legend.title     = ggplot2::element_text(face = "plain"),
      legend.position  = "right",
      plot.margin      = ggplot2::margin(12, 12, 12, 12)
    )
}
