# =============================================================================
# live_engine.R -- Live Market (Tab 1) support: build a single full run from the
# current sidebar params + in-tab interventions (bot, user trades), and render
# the price path, agent swarm, event log and P&L. Pure helpers; the reactive
# controller lives in mod_live.R.
#
# Animation model (handoff GUI Sec. 6.1): precompute + replay with intervention
# injection. Because run_market is deterministic in `seed`, we don't resume a
# paused sim -- we re-run the whole market with the intervention scheduled, which
# reproduces the identical revealed prefix and the correct divergent suffix. The
# UI just reveals trades 1..idx of the recomputed trajectory.
# =============================================================================

# Money is modeled in abstract units (agent wealth ~ Pareto mean 2, wallet ~ 10).
# For the UI we scale by PM_MONEY_SCALE so the sums feel like a real market (a
# few-percent stake is tens of thousands) -- display only; the dynamics are
# scale-free (prices depend on ratios, not levels).
PM_MONEY_SCALE <- 1000

# pm_money(): format a model-unit amount as scaled currency, e.g. "$10,000".
# signed = TRUE prefixes +/- (for P&L).
pm_money <- function(x, signed = FALSE) {
  v <- x * PM_MONEY_SCALE
  s <- paste0("$", formatC(abs(v), format = "f", digits = 0, big.mark = ","))
  if (signed) paste0(if (v < 0) "−" else "+", s) else if (v < 0) paste0("−", s) else s
}

# pm_live_params(): fold the in-tab bot config + user wallet into a params list.
# bot$from is the first round the bot is active (set when the user toggles it on);
# rounds before that run bot-free, preserving the revealed prefix.
pm_live_params <- function(params, bot, user_wallet) {
  p <- params
  p$bot_on     <- isTRUE(bot$on)
  p$B_m        <- bot$B_m
  p$bot_pistar <- bot$pistar
  p$bot_rounds <- if (isTRUE(bot$on)) seq.int(bot$from, p$T) else NULL
  p$user_wallet <- user_wallet
  p
}

# pm_live_run(): the full run_market for the current live state.
pm_live_run <- function(params, seed, bot, user_wallet, user_trades) {
  lp <- pm_live_params(params, bot, user_wallet)
  run_market(lp, seed = seed, record = "full", user_trades = user_trades)
}

# pm_n_trades(): number of trades in a trajectory (0 if none).
pm_n_trades <- function(traj) if (is.null(traj$price_path)) 0L else nrow(traj$price_path)

# pm_current_round(): the round of the currently revealed trade (0 if none).
pm_current_round <- function(traj, idx) {
  if (idx <= 0 || is.null(traj$trades) || nrow(traj$trades) == 0) return(0L)
  as.integer(traj$trades$t[min(idx, nrow(traj$trades))])
}

# pm_round_end(): trade index at the end of round k (0 for k < 1). Used to
# animate per round -- one tick reveals a whole round (smoother than per trade).
pm_round_end <- function(traj, k) {
  if (k < 1 || is.null(traj$trades) || nrow(traj$trades) == 0) return(0L)
  re <- cumsum(tabulate(traj$trades$t, nbins = traj$params$T))
  as.integer(re[min(k, length(re))])
}

# pm_user_status(): the user's revealed cash / position at trade `idx`, derived
# from the user trades among the first idx trades.
pm_user_status <- function(traj, idx, wallet0) {
  out <- list(cash = wallet0, yes = 0, no = 0)
  if (idx < 1 || is.null(traj$trades)) return(out)
  tr <- traj$trades[seq_len(min(idx, nrow(traj$trades))), , drop = FALSE]
  u <- tr[tr$type == "user", , drop = FALSE]
  if (nrow(u) == 0) return(out)
  out$cash <- wallet0 - sum(u$cost + u$fee)
  out$yes  <- sum(u$shares[u$side == "YES"])
  out$no   <- sum(u$shares[u$side == "NO"])
  out
}

# pm_mover_color(): segment color for the two path-coloring modes (GUI Sec. 4).
#   "highlight": ink, except red = bot/structural manipulator, orange = user.
#   "trader":    tinted by the mover's type (informed/noise/manip+bot/user).
pm_mover_color <- function(type, is_bot, mode) {
  if (mode == "trader") {
    out <- unname(PM_TYPE_COL[type])
    out[is.na(out)] <- PM_COL$price
    return(out)
  }
  out <- rep(PM_COL$price, length(type))          # highlight-manipulation (default)
  out[type == "manipulator" | is_bot] <- PM_COL$manip
  out[type == "user"] <- PM_COL$user
  out
}

# pm_price_plot(): the centerpiece. Ink price path over trade index with the
# prior (gray dotted) and omniscient p* (blue dashed) reference lines, colored
# segments per the mode, and -- once fully revealed -- the resolution marker.
pm_price_plot <- function(traj, idx, color_mode = "highlight") {
  ntr <- pm_n_trades(traj)
  idx <- max(0L, min(idx, ntr))
  p0_init <- traj$params$p0_init
  xmax <- max(ntr, 1L)

  base <- ggplot2::ggplot() +
    ggplot2::geom_hline(yintercept = traj$p0, linetype = "dotted",
                        color = PM_COL$prior, linewidth = 0.6) +
    ggplot2::geom_hline(yintercept = traj$p_star, linetype = "dashed",
                        color = PM_COL$omniscient, linewidth = 0.7) +
    ggplot2::annotate("text", x = 0, y = traj$p0, label = "prior", hjust = 0,
                      vjust = -0.4, size = 3, color = PM_COL$prior) +
    ggplot2::annotate("text", x = 0, y = traj$p_star, label = "best possible",
                      hjust = 0, vjust = -0.4, size = 3, color = PM_COL$omniscient)

  if (idx >= 1) {
    tr <- traj$trades[seq_len(idx), , drop = FALSE]
    seg <- data.frame(
      x0 = seq_len(idx) - 1, x1 = seq_len(idx),
      y0 = tr$p_before,      y1 = tr$p_after,
      col = pm_mover_color(tr$type, tr$is_bot, color_mode)
    )
    base <- base +
      ggplot2::geom_segment(data = seg,
                            ggplot2::aes(x = x0, y = y0, xend = x1, yend = y1),
                            color = seg$col, linewidth = 1.1, lineend = "round")
  } else {
    base <- base +
      ggplot2::annotate("point", x = 0, y = p0_init, color = PM_COL$price, size = 1.5)
  }

  # Resolution marker once the whole run is revealed. Label is right-aligned at
  # the terminal step so it extends left (never cropped off the right edge).
  if (idx >= ntr && ntr >= 1) {
    base <- base +
      ggplot2::geom_vline(xintercept = ntr, linetype = "dotted", color = "grey60") +
      ggplot2::annotate("point", x = ntr, y = traj$A, size = 3, color = PM_COL$price) +
      ggplot2::annotate("text", x = ntr, y = traj$A,
                        label = if (traj$A == 1L) "Resolves YES  " else "Resolves NO  ",
                        hjust = 1, vjust = if (traj$A == 1L) 1.6 else -0.8,
                        size = 3.2, fontface = "bold", color = PM_COL$price)
  }

  base +
    ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25)) +
    ggplot2::scale_x_continuous(limits = c(0, xmax), expand = ggplot2::expansion(mult = c(0.01, 0.06))) +
    ggplot2::labs(title = "Market price", x = "Trade", y = "Price of YES") +
    theme_pm()
}

# pm_swarm_plot(): one dot per agent -- x = belief, y = net position, size =
# wealth, color = type, hollow = not yet entered. A vertical rule marks the
# current price. Uses the end-of-round snapshot nearest the revealed trade.
pm_swarm_plot <- function(traj, idx) {
  r <- pm_current_round(traj, idx)
  af <- traj$agents_final
  if (r >= 1 && !is.null(traj$snapshots[[r]])) {
    snap <- traj$snapshots[[r]]
    p_tilde <- snap$p_tilde; y <- snap$y; z <- snap$z; entered <- snap$entered; w <- snap$w
  } else {
    p_tilde <- af$p_tilde_init; y <- rep(0, length(af$w_init)); z <- y
    entered <- af$entered; w <- af$w_init
  }
  type <- af$type
  type[af$is_bot] <- "bot"
  df <- data.frame(
    belief = p_tilde, pos = y - z, w = w, type = type,
    entered = ifelse(entered > 0, "in", "out")
  )
  price_now <- if (idx >= 1) traj$trades$p_after[min(idx, nrow(traj$trades))] else traj$params$p0_init

  ggplot2::ggplot(df, ggplot2::aes(x = belief, y = pos, size = w, color = type, shape = entered)) +
    ggplot2::geom_vline(xintercept = price_now, color = PM_COL$price, linetype = "dashed",
                        linewidth = 0.5) +
    ggplot2::geom_hline(yintercept = 0, color = "grey85", linewidth = 0.4) +
    ggplot2::geom_point(alpha = 0.8) +
    ggplot2::scale_color_manual(values = PM_TYPE_COL, drop = FALSE, name = "Type") +
    ggplot2::scale_shape_manual(values = c(`in` = 16, out = 1), name = "Status") +
    ggplot2::scale_size_continuous(range = c(1, 6), guide = "none") +
    ggplot2::scale_x_continuous(limits = c(0, 1)) +
    ggplot2::labs(title = "Traders", x = "Belief (probability of YES)", y = "Net position") +
    theme_pm()
}

# pm_event_log_lines(): plain-language log of the revealed trades. Full detail
# when n*T <= 2000, else per-round summaries (handoff GUI Sec. 7.4). Newest last.
pm_event_log_lines <- function(traj, idx, detail_cap = 2000) {
  ntr <- pm_n_trades(traj)
  idx <- max(0L, min(idx, ntr))
  if (idx < 1) return("No trades yet.")
  tr <- traj$trades[seq_len(idx), , drop = FALSE]
  full <- (traj$params$n * traj$params$T) <= detail_cap
  who <- function(row) {
    if (row$type == "user") "You"
    else if (row$is_bot) "Bot"
    else sprintf("%s #%d", tools::toTitleCase(row$type), row$trader)
  }
  if (full) {
    lines <- vapply(seq_len(idx), function(i) {
      row <- tr[i, ]
      fee <- if (row$fee > 1e-9) sprintf(" (+fee %.2f)", row$fee) else ""
      sprintf("Round %d: %s buys %.0f %s @ %.2f%s",
              row$t, who(row), row$shares, row$side, row$p_after, fee)
    }, character(1))
  } else {
    agg <- stats::aggregate(cbind(cost, shares) ~ t, data = tr, FUN = sum)
    lines <- sprintf("Round %d: %d trades, volume %.1f, price -> %.2f",
                     agg$t, as.integer(table(tr$t)[as.character(agg$t)]),
                     agg$cost,
                     tr$p_after[cumsum(as.integer(table(tr$t)))])
  }
  # Show the most recent ~200 lines.
  utils::tail(lines, 200)
}

# pm_pnl_by_type(): resolution P&L grouped by trader type, plus bot and user.
pm_pnl_by_type <- function(traj) {
  af <- traj$agents_final
  grp <- af$type
  grp[af$is_bot] <- "bot"
  tab <- tapply(af$pnl, grp, sum)
  df <- data.frame(who = names(tab), pnl = as.numeric(tab), stringsAsFactors = FALSE)
  # Friendly labels.
  lbl <- c(informed = "Informed traders", noise = "Noise traders",
           manipulator = "Manipulators", bot = "Bot", user = "You")
  df$who <- ifelse(df$who %in% names(lbl), lbl[df$who], df$who)
  if (!is.null(traj$user) && traj$user$wallet0 > 0) {
    df <- rbind(df, data.frame(who = "You", pnl = traj$user$pnl))
  }
  df <- rbind(df, data.frame(who = "Operator", pnl = traj$operator_pnl))
  df$pnl <- round(df$pnl, 2)
  df
}
