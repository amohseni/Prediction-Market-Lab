# =============================================================================
# anatomy_plots.R -- Run Anatomy (Tab 2) diagnostics of the current run
# (handoff Sec. 4, GUI Sec. 4 Tab 2). Pure functions of a full run_market()
# trajectory (the same run shown in Tab 1). All per-round.
#
#   pm_anatomy_convergence()   |p_t - p*| per round (log y) -- the healing curve
#   pm_anatomy_aggregation()   price vs wealth-weighted mean belief per round
#   pm_anatomy_participation() traded / no-trade band / never entered, per round
#   pm_anatomy_migration()     each belief over time (cascades when h > 0)
#   pm_anatomy_volume()        trade volume per round
# =============================================================================

# pm_anatomy_convergence(): how fast the price closes on the best-possible
# forecast p*. Gap floored so the log axis never sees zero.
pm_anatomy_convergence <- function(traj) {
  Tt <- traj$params$T
  df <- data.frame(round = seq_len(Tt),
                   gap = pmax(abs(traj$price_round - traj$p_star), 1e-4))
  ggplot2::ggplot(df, ggplot2::aes(round, gap)) +
    ggplot2::geom_line(color = PM_COL$price, linewidth = 0.8) +
    ggplot2::geom_point(color = PM_COL$price, size = 1.5) +
    ggplot2::scale_y_log10() +
    ggplot2::labs(title = "Distance to best possible",
                  subtitle = "How fast the price closes on p* (lower is better)",
                  x = "Round", y = "|price - p*|  (log)") +
    theme_pm()
}

# pm_anatomy_aggregation(): the market price should hug the wealth-weighted mean
# belief of the (non-manipulator) traders -- that is the crowd's aggregate view.
# Persistent divergence flags herding or frictions at work.
pm_anatomy_aggregation <- function(traj) {
  Tt   <- traj$params$T
  af   <- traj$agents_final
  keep <- af$type %in% c("informed", "noise") & !af$is_bot
  wwmb <- vapply(seq_len(Tt), function(t) {
    s <- traj$snapshots[[t]]
    if (!any(keep)) return(NA_real_)
    sum(s$w[keep] * s$p_tilde[keep]) / sum(s$w[keep])
  }, numeric(1))
  df <- data.frame(
    round  = rep(seq_len(Tt), 2),
    value  = c(traj$price_round, wwmb),
    series = rep(c("Market price", "Wealth-weighted belief"), each = Tt))
  ggplot2::ggplot(df, ggplot2::aes(round, value, color = series)) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::scale_color_manual(
      values = c("Market price" = PM_COL$price,
                 "Wealth-weighted belief" = PM_COL$benchmark), name = NULL) +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::labs(title = "Aggregation check",
                  subtitle = "Price vs wealth-weighted belief",
                  x = "Round", y = "Probability of YES") +
    theme_pm() + ggplot2::theme(legend.position = "bottom")
}

# pm_anatomy_participation(): per round, split the n agents into traded this
# round / entered but idle (inside the no-trade band) / never entered (still
# priced out by the participation cost). Makes the three frictions visible.
pm_anatomy_participation <- function(traj) {
  n <- traj$params$n; Tt <- traj$params$T
  tr <- traj$trades
  rows <- lapply(seq_len(Tt), function(t) {
    entered <- traj$snapshots[[t]]$entered[seq_len(n)]
    traded_ids <- unique(tr$trader[tr$t == t & !tr$is_bot & tr$type != "user" &
                                     tr$trader >= 1 & tr$trader <= n])
    n_traded  <- length(traded_ids)
    n_entered <- sum(entered == 1L)
    data.frame(round = t,
               status = c("Traded", "In no-trade band", "Never entered"),
               count  = c(n_traded, n_entered - n_traded, n - n_entered))
  })
  df <- do.call(rbind, rows)
  df$status <- factor(df$status,
                      levels = c("Never entered", "In no-trade band", "Traded"))
  ggplot2::ggplot(df, ggplot2::aes(round, count, fill = status)) +
    ggplot2::geom_col(width = 0.9) +
    ggplot2::scale_fill_manual(values = c(
      "Traded" = "#495057", "In no-trade band" = "#adb5bd",
      "Never entered" = "#dee2e6"), name = NULL) +
    ggplot2::labs(title = "Participation",
                  subtitle = "Who traded, who sat inside the no-trade band, who never showed up",
                  x = "Round", y = "Traders") +
    theme_pm() + ggplot2::theme(legend.position = "bottom")
}

# pm_anatomy_has_migration(): belief migration only happens with herding on.
pm_anatomy_has_migration <- function(traj) traj$params$h > 0

# pm_anatomy_migration(): each informed agent's belief over time. With herding
# the lines are reeled toward the price (a cascade). Samples up to `max_lines`
# agents for legibility; overlays the price path for reference.
pm_anatomy_migration <- function(traj, max_lines = 120) {
  Tt <- traj$params$T
  af <- traj$agents_final
  inf <- which(af$type == "informed" & !af$is_bot)
  if (length(inf) == 0) inf <- which(!af$is_bot)
  sampled_note <- ""
  if (length(inf) > max_lines) {
    inf <- inf[round(seq(1, length(inf), length.out = max_lines))]
    sampled_note <- sprintf(" (sample of %d)", max_lines)
  }
  # round 0 = initial belief; rounds 1..T from snapshots.
  belief0 <- af$p_tilde_init[inf]
  mat <- sapply(seq_len(Tt), function(t) traj$snapshots[[t]]$p_tilde[inf])
  if (is.null(dim(mat))) mat <- matrix(mat, nrow = length(inf))
  long <- data.frame(
    agent  = rep(inf, times = Tt + 1L),
    round  = rep(0:Tt, each = length(inf)),
    belief = c(belief0, as.vector(mat)))
  price_df <- data.frame(round = 0:Tt, price = c(traj$params$p0_init, traj$price_round))
  ggplot2::ggplot() +
    ggplot2::geom_line(data = long,
                       ggplot2::aes(round, belief, group = agent),
                       color = PM_COL$informed, alpha = 0.18, linewidth = 0.35) +
    ggplot2::geom_line(data = price_df, ggplot2::aes(round, price),
                       color = PM_COL$price, linewidth = 1.1) +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::labs(title = "Belief migration",
                  subtitle = paste0("Each line is one trader's belief; the ink line is the price",
                                    sampled_note),
                  x = "Round", y = "Belief (probability of YES)") +
    theme_pm()
}

# pm_anatomy_volume(): money traded per round (scaled to display dollars).
pm_anatomy_volume <- function(traj) {
  Tt <- traj$params$T
  tr <- traj$trades
  vol <- vapply(seq_len(Tt), function(t) sum(tr$cost[tr$t == t]), numeric(1))
  df <- data.frame(round = seq_len(Tt), volume = vol * PM_MONEY_SCALE)
  ggplot2::ggplot(df, ggplot2::aes(round, volume)) +
    ggplot2::geom_col(width = 0.9, fill = "#495057") +
    ggplot2::scale_y_continuous(labels = function(x) paste0("$", formatC(x, format = "d", big.mark = ","))) +
    ggplot2::labs(title = "Volume",
                  subtitle = "Money traded each round",
                  x = "Round", y = "Volume") +
    theme_pm()
}
