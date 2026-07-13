# =============================================================================
# presets.R -- Named scenarios (handoff Sec. 5, GUI Sec. 3.1). Each preset is a
# lesson: selecting it loads a full parameter vector (defaults + the deltas
# below). Some presets also script the in-tab manipulator bot; that config
# travels with the preset for Tab 1 to pick up (the bot is an intervention, not
# a sidebar parameter, so it is stored separately here).
#
# pm_presets() returns a named list; names are the dropdown keys/labels.
# Each entry: list(label, lesson, params = <deltas>, bot = <list or NULL>).
# =============================================================================

pm_presets <- function() {
  list(
    "Textbook market" = list(
      label  = "Textbook market",
      lesson = "Markets work: with independent clues and no frictions, the price converges to the best forecast anyone could make (p*).",
      params = list(),                                   # pure defaults
      bot    = NULL
    ),
    "Echo chamber" = list(
      label  = "Echo chamber",
      lesson = "Many traders, little knowledge. When errors are correlated the effective sample size saturates, so extra traders stop adding accuracy -- the n_eff ceiling.",
      params = list(rho = 0.5),
      bot    = NULL
    ),
    "Whale market" = list(
      label  = "Whale market",
      lesson = "One fortune moves the price. Extreme wealth inequality makes the market's opinion close to a single rich trader's belief.",
      params = list(alpha_w = 1.2),
      bot    = NULL
    ),
    "Toll road" = list(
      label  = "Toll road",
      lesson = "Trading costs money. A proportional fee plus a flat cost open no-trade bands, leaving the price stale and less accurate.",
      params = list(tau = 0.05, kappa = 0.1),
      bot    = NULL
    ),
    "Sleepy market" = list(
      label  = "Sleepy market",
      lesson = "Thin participation: a cost to show up keeps most traders dormant. Switch the bot on and watch it wake the market up (Hanson-Oprea).",
      params = list(c_part = 0.2, sigma_eps = 1.5),
      bot    = NULL
    ),
    "Cascade" = list(
      label  = "Cascade",
      lesson = "Manipulation that outlives the manipulator. With herding, a bot that pushes the price for a few rounds leaves a lasting distortion after it exits.",
      params = list(h = 0.4, rho = 0.3),
      bot    = list(on = TRUE, B_m = 0.1, pistar = 0.9, rounds = 3:8)
    )
  )
}

# pm_preset_params(): resolve a preset name to a full parameter list (defaults
# with the preset's deltas applied). Unknown name -> defaults.
pm_preset_params <- function(name) {
  presets <- pm_presets()
  p <- pm_default_params()
  if (!is.null(name) && name %in% names(presets)) {
    deltas <- presets[[name]]$params
    for (k in names(deltas)) p[[k]] <- deltas[[k]]
  }
  p
}

# pm_default_preset(): the scenario the app opens on.
pm_default_preset <- function() "Textbook market"

# =============================================================================
# Sidebar control specification (GUI Sec. 3.2). One source of truth so ui.R
# (which renders the inputs) and server.R (which reads them back into a params
# list) never drift. Input ids match pm_default_params() names exactly, so the
# server can do params[[id]] <- input[[id]] in a loop.
#
# Each group: list(id, title, subtitle, details, controls). Each control:
#   id, label, min, max, step, kind ("slider" | "int" | "numeric"), caption.
# Default values come from pm_default_params() (looked up by id) so defaults are
# defined in exactly one place.
# =============================================================================
# Each control carries `sym` (a LaTeX symbol, typeset by MathJax; NA when the
# control has no math symbol) and `desc` (plain description). ui.R renders the
# label as \(sym\) — desc. Group `details` use inline LaTeX for their symbols.
pm_controls <- function() {
  list(
    list(
      id = "grp_information", title = "Information",
      subtitle = "What there is to know, and who knows it",
      details = paste(
        "A hidden number \\(\\theta\\) decides the event: YES happens if \\(\\theta\\)",
        "clears the threshold \\(c\\). Each trader sees \\(\\theta\\) plus noise.",
        "Correlated noise (\\(\\rho\\)) means traders share mistakes rather than making",
        "independent checks, which caps how much the crowd can ever learn."),
      controls = list(
        list(id = "n",         sym = "n",                   desc = "traders",         min = 10,  max = 800, step = 5,    kind = "int",
             caption = "How many traders receive a clue."),
        list(id = "sigma_eps", sym = "\\sigma_\\varepsilon", desc = "signal noise",    min = 0.1, max = 3,  step = 0.05, kind = "slider",
             caption = "How noisy each clue is."),
        list(id = "rho",       sym = "\\rho",               desc = "error correlation", min = 0, max = 0.95, step = 0.05, kind = "slider",
             caption = "How much traders' errors overlap — shared mistakes, not independent checks."),
        list(id = "mu0",       sym = "\\mu_0",              desc = "prior mean",      min = -3, max = 3, step = 0.1, kind = "slider",
             caption = "What everyone believes before any clues (mean)."),
        list(id = "sigma0",    sym = "\\sigma_0",           desc = "prior SD",        min = 0.2, max = 3, step = 0.1, kind = "slider",
             caption = "What everyone believes before any clues (spread)."),
        list(id = "c",         sym = "c",                   desc = "event threshold", min = -3, max = 3, step = 0.1, kind = "slider",
             caption = "The bar the truth must clear for YES — sets how rare the event is.")
      )
    ),
    list(
      id = "grp_market", title = "Market",
      subtitle = "The trading machinery",
      details = paste(
        "Trades run against an LMSR automated market maker. Liquidity \\(b\\) sets how",
        "much money it takes to move the price; the market opens at \\(p_0\\) and runs",
        "for \\(T\\) rounds before the truth is revealed and shares pay out."),
      controls = list(
        list(id = "b",       sym = "b",     desc = "liquidity",     min = 1, max = 100, step = 1, kind = "slider",
             caption = "Market depth: how much money it takes to move the price."),
        list(id = "p0_init", sym = "p_0",   desc = "opening price", min = 0.01, max = 0.99, step = 0.01, kind = "slider",
             caption = "Where the price starts (0.5 = ignorance)."),
        list(id = "T",       sym = "T",     desc = "trading rounds", min = 1, max = 100, step = 1, kind = "int",
             caption = "How many rounds of trading before the answer is revealed.")
      )
    ),
    list(
      id = "grp_traders", title = "Traders",
      subtitle = "Who shows up",
      details = paste(
        "Wealth is Pareto-distributed (\\(\\alpha_w\\) controls how top-heavy). Each",
        "trader bets a Kelly fraction (\\(\\lambda\\)) of wealth toward their belief.",
        "Some trade on noise; some are manipulators with a fixed target price; herding",
        "(\\(h\\)) makes traders adopt the current price as their own belief."),
      controls = list(
        list(id = "alpha_w",   sym = "\\alpha_w",             desc = "wealth inequality", min = 1.05, max = 4, step = 0.05, kind = "slider",
             caption = "Wealth inequality (lower = a few whales own everything)."),
        list(id = "lambda",    sym = "\\lambda",              desc = "Kelly fraction",  min = 0.05, max = 1, step = 0.05, kind = "slider",
             caption = "Betting aggression: 1 = full Kelly, lower = timid."),
        list(id = "phi_noise", sym = "\\phi_{\\text{noise}}", desc = "noise traders",   min = 0, max = 1, step = 0.05, kind = "slider",
             caption = "Share of traders betting on noise instead of information."),
        list(id = "phi_manip", sym = "\\phi_{\\text{manip}}", desc = "manipulators",    min = 0, max = 1, step = 0.05, kind = "slider",
             caption = "Share of built-in manipulators (fixed target price)."),
        list(id = "pistar",    sym = "\\pi^{\\star}",         desc = "manipulator target", min = 0.01, max = 0.99, step = 0.01, kind = "slider",
             caption = "The price the built-in manipulators push toward."),
        list(id = "h",         sym = "h",                     desc = "herding",         min = 0, max = 1, step = 0.05, kind = "slider",
             caption = "Herding: how much traders adopt the price as their own belief.")
      )
    ),
    list(
      id = "grp_frictions", title = "Frictions",
      subtitle = "What trading costs",
      details = paste(
        "Three costs, three mechanisms. A proportional fee (\\(\\tau\\)) shrinks every",
        "trade and widens a no-trade band; a flat cost (\\(\\kappa\\)) kills small",
        "trades; a participation cost (\\(c_{\\text{part}}\\)) decides who bothers to",
        "show up at all."),
      controls = list(
        list(id = "tau",    sym = "\\tau",              desc = "proportional fee", min = 0, max = 0.5, step = 0.01, kind = "slider",
             caption = "Fee as a share of each trade (shrinks every trade)."),
        list(id = "kappa",  sym = "\\kappa",            desc = "fixed cost",       min = 0, max = 2, step = 0.05, kind = "slider",
             caption = "Flat cost per trade (kills small trades entirely)."),
        list(id = "c_part", sym = "c_{\\text{part}}",   desc = "participation cost", min = 0, max = 2, step = 0.05, kind = "slider",
             caption = "Cost of paying attention at all (decides who even shows up).")
      )
    ),
    list(
      id = "grp_simulation", title = "Simulation",
      subtitle = "Randomness and averaging",
      details = paste(
        "The seed fixes the random draws so a run is reproducible. \\(R\\) is how many",
        "independent markets each research sweep averages over (research tabs only)."),
      controls = list(
        list(id = "seed", sym = NA, desc = "Random seed", min = 1, max = 99999, step = 1, kind = "numeric",
             caption = "Random seed (reproducibility)."),
        list(id = "R",    sym = "R", desc = "replications", min = 10, max = 1000, step = 10, kind = "int",
             caption = "Replications per ensemble point (research tabs only).")
      )
    )
  )
}

# pm_control_ids(): flat vector of every input id in the sidebar (param names).
pm_control_ids <- function() {
  unlist(lapply(pm_controls(), function(g) vapply(g$controls, `[[`, "", "id")),
         use.names = FALSE)
}

