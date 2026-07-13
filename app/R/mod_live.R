# =============================================================================
# mod_live.R -- Tab 1: Live Market (handoff Sec. 4, GUI Sec. 4 Tab 1).
#
# Precompute-and-replay animation (see live_engine.R): the whole market is a
# deterministic run of the current sidebar params + in-tab interventions (bot,
# user trades); the scrub slider indexes how much of it is revealed. Any
# intervention re-runs the market (identical prefix, divergent suffix) and the
# reveal continues. Animation advances one round per tick (smooth + cheap).
# =============================================================================

PM_LIVE_USER_WALLET <- 10   # starting cash for the user's own trades (Tab 1)

mod_live_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",

    # --- Control strip -------------------------------------------------------
    tags$div(
      class = "pm-live-controls",
      actionButton(ns("run"),  "Play",       class = "btn-sm btn-outline-secondary"),
      actionButton(ns("step"), "Step",       class = "btn-sm btn-outline-secondary"),
      actionButton(ns("new"),  "New market", class = "btn-sm btn-outline-secondary"),
      tags$div(class = "pm-live-speed",
               sliderInput(ns("speed"), "Speed (rounds/s)", min = 1, max = 12,
                           value = 4, step = 1, width = "150px", ticks = FALSE)),
      tags$div(class = "pm-live-scrub",
               sliderInput(ns("scrub"), "Trade", min = 0, max = 1, value = 0,
                           step = 1, width = "100%", ticks = FALSE))
    ),

    # --- Path color mode + main price plot -----------------------------------
    tags$div(
      class = "pm-live-colormode",
      radioButtons(ns("color_mode"), NULL,
                   choices = c("Highlight manipulation" = "highlight",
                               "Color by trader" = "trader"),
                   selected = "highlight", inline = TRUE)
    ),
    plotOutput(ns("price_plot"), height = "330px"),

    # --- Intervention strip: bot + wallet ------------------------------------
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_header(tags$span(uiOutput(ns("bot_dot"), inline = TRUE),
                                     " Manipulator bot")),
        bslib::card_body(
          checkboxInput(ns("bot_on"), "Unleash the bot", value = FALSE),
          sliderInput(ns("bot_Bm"), "Budget (share of market wealth)",
                      min = 0.02, max = 0.5, value = 0.1, step = 0.02, width = "100%"),
          sliderInput(ns("bot_pistar"), "Target price", min = 0.05, max = 0.95,
                      value = 0.9, step = 0.05, width = "100%"),
          tags$p(class = "pm-caption",
                 "The bot trades toward its target from the current round on — its trades show red.")
        )
      ),
      bslib::card(
        bslib::card_header("Your wallet"),
        bslib::card_body(
          uiOutput(ns("wallet_status")),
          numericInput(ns("amount"), "Amount to spend", value = 2, min = 0.1,
                       max = PM_LIVE_USER_WALLET, step = 0.5, width = "100%"),
          tags$div(
            class = "pm-wallet-buttons",
            actionButton(ns("buy_yes"), "Buy YES", class = "btn-sm btn-outline-secondary"),
            actionButton(ns("buy_no"),  "Buy NO",  class = "btn-sm btn-outline-secondary")
          ),
          tags$p(class = "pm-caption", "Your trades show orange on the price path.")
        )
      )
    ),

    # --- Agent swarm ---------------------------------------------------------
    plotOutput(ns("swarm_plot"), height = "260px"),

    # --- Event log (collapsible) + post-resolution card ----------------------
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        "Event log",
        tags$pre(class = "pm-event-log", textOutput(ns("event_log")))
      )
    ),
    uiOutput(ns("post_resolution"))
  )
}

mod_live_server <- function(id, params, stale) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(
      seed = 1L,
      traj = NULL,
      bot = list(on = FALSE, B_m = 0.1, pistar = 0.9, from = 1L),
      user_trades = list(),
      playing = FALSE,
      pos = 0L          # revealed trade index -- the source of truth (not the slider)
    )

    idx <- reactive(rv$pos)

    # set_pos(): move the reveal position and sync the slider display to it. The
    # slider is display + manual scrub only; the animation writes rv$pos directly
    # so it never waits on the slider's client round-trip (avoids the race).
    set_pos <- function(x, max = NULL) {
      x <- max(0L, as.integer(x))
      rv$pos <- x
      if (is.null(max)) updateSliderInput(session, "scrub", value = x)
      else updateSliderInput(session, "scrub", value = x, max = max)
    }

    # Manual scrub: only honor slider input while paused (ignore animation echoes),
    # and only when it actually differs from the current position.
    observeEvent(input$scrub, {
      v <- as.integer(input$scrub)
      if (!isolate(rv$playing) && !identical(v, isolate(rv$pos))) rv$pos <- v
    })

    # --- (re)compute the trajectory from current state -----------------------
    recompute <- function(to = c("keep", "end", "round"), round = NULL) {
      to <- match.arg(to)
      traj <- pm_live_run(params(), rv$seed, rv$bot, PM_LIVE_USER_WALLET, rv$user_trades)
      rv$traj <- traj
      ntr <- pm_n_trades(traj)
      newval <- switch(to,
        keep  = min(isolate(rv$pos), ntr),
        end   = ntr,
        round = pm_round_end(traj, round))
      set_pos(newval, max = max(ntr, 1L))
    }

    # Initial precomputed run (never blank): reveal the whole first market.
    observeEvent(TRUE, { rv$seed <- 1L; recompute(to = "end") }, once = TRUE)

    # Sidebar params changed (debounced): rebuild the world, keep position.
    params_d <- debounce(reactive(params()), 400)
    observeEvent(params_d(), { rv$playing <- FALSE; recompute(to = "keep") },
                 ignoreInit = TRUE)

    # --- Transport controls (ignoreInit: actionButtons fire on startup) ------
    observeEvent(input$run, {
      ntr <- pm_n_trades(rv$traj)
      if (rv$playing) { rv$playing <- FALSE }
      else {
        if (isolate(rv$pos) >= ntr) set_pos(0L)   # replay from the start
        rv$playing <- TRUE
      }
    }, ignoreInit = TRUE)
    observeEvent(rv$playing, {
      updateActionButton(session, "run", label = if (rv$playing) "Pause" else "Play")
    })
    observeEvent(input$step, {
      rv$playing <- FALSE
      r <- pm_current_round(rv$traj, isolate(rv$pos))
      set_pos(pm_round_end(rv$traj, r + 1L))
    }, ignoreInit = TRUE)
    observeEvent(input$new, {
      rv$playing <- FALSE
      rv$user_trades <- list()
      rv$bot$from <- 1L
      rv$seed <- rv$seed + 1L
      recompute(to = "keep"); set_pos(0L)
      rv$playing <- TRUE
    }, ignoreInit = TRUE)

    # Animation: one round per tick while playing. rv$pos advances synchronously
    # (no slider round-trip); invalidateLater re-arms the tick.
    observe({
      if (!rv$playing) return()
      traj <- isolate(rv$traj); ntr <- pm_n_trades(traj)
      cur <- isolate(rv$pos)
      if (cur >= ntr) { rv$playing <- FALSE; return() }
      invalidateLater(round(1000 / max(1, isolate(input$speed))))
      r <- pm_current_round(traj, cur)
      set_pos(pm_round_end(traj, r + 1L))
    })

    # --- Bot intervention ----------------------------------------------------
    observeEvent(list(input$bot_on, input$bot_Bm, input$bot_pistar), {
      turning_on <- isTRUE(input$bot_on) && !isTRUE(rv$bot$on)
      from <- if (turning_on)
        min(pm_current_round(rv$traj, isolate(idx())) + 1L, params()$T)
      else rv$bot$from
      rv$bot <- list(on = isTRUE(input$bot_on), B_m = input$bot_Bm,
                     pistar = input$bot_pistar, from = from)
      recompute(to = "keep")
    }, ignoreInit = TRUE)

    output$bot_dot <- renderUI({
      col <- if (isTRUE(input$bot_on)) PM_COL$manip else "#ccc"
      tags$span(style = sprintf(
        "display:inline-block;width:9px;height:9px;border-radius:50%%;background:%s;", col))
    })

    # --- User trades ---------------------------------------------------------
    add_user_trade <- function(side) {
      r <- max(1L, pm_current_round(rv$traj, isolate(idx())))
      amt <- input$amount; if (is.null(amt) || is.na(amt) || amt <= 0) return()
      ut <- rv$user_trades
      ut[[length(ut) + 1L]] <- list(round = r, side = side, amount = amt)
      rv$user_trades <- ut
      rv$playing <- FALSE
      recompute(to = "round", round = r)
    }
    observeEvent(input$buy_yes, add_user_trade("YES"), ignoreInit = TRUE)
    observeEvent(input$buy_no,  add_user_trade("NO"),  ignoreInit = TRUE)

    output$wallet_status <- renderUI({
      st <- pm_user_status(rv$traj, idx(), PM_LIVE_USER_WALLET)
      tags$p(class = "pm-wallet-line", HTML(sprintf(
        "Cash <b>$%.2f</b> &nbsp;·&nbsp; YES <b>%.0f</b> &nbsp;·&nbsp; NO <b>%.0f</b>",
        st$cash, st$yes, st$no)))
    })

    # --- Plots + log ---------------------------------------------------------
    output$price_plot <- renderPlot({
      req(rv$traj)
      pm_price_plot(rv$traj, idx(), input$color_mode %||% "highlight")
    }, res = 96)
    output$swarm_plot <- renderPlot({ req(rv$traj); pm_swarm_plot(rv$traj, idx()) }, res = 96)
    output$event_log  <- renderText({
      req(rv$traj); paste(pm_event_log_lines(rv$traj, idx()), collapse = "\n")
    })

    # --- Post-resolution card (only when fully revealed) ---------------------
    output$post_resolution <- renderUI({
      traj <- rv$traj; if (is.null(traj)) return(NULL)
      if (idx() < pm_n_trades(traj)) return(NULL)
      brier <- (traj$p_T - traj$A)^2
      brier_prior <- (traj$p0 - traj$A)^2
      beat <- brier_prior - brier
      pnl <- pm_pnl_by_type(traj)
      rows <- lapply(seq_len(nrow(pnl)), function(i) {
        tags$tr(tags$td(pnl$who[i]),
                tags$td(style = "text-align:right;", sprintf("%+.2f", pnl$pnl[i])))
      })
      bslib::card(
        class = "pm-post-card",
        bslib::card_header("Result"),
        bslib::card_body(
          tags$p(HTML(sprintf(
            "Outcome: <b>%s</b>. Final price <b>%.2f</b> (prior %.2f, best possible %.2f).",
            if (traj$A == 1L) "YES" else "NO", traj$p_T, traj$p0, traj$p_star))),
          tags$p(HTML(sprintf(
            "Run Brier <b>%.3f</b> vs prior Brier %.3f — the market %s the prior by %.3f.",
            brier, brier_prior,
            if (beat >= 0) "beat" else "trailed", abs(beat)))),
          tags$table(class = "pm-pnl-table",
                     tags$thead(tags$tr(tags$th("P&L by participant"), tags$th(""))),
                     tags$tbody(rows))
        )
      )
    })
  })
}
