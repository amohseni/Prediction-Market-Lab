# =============================================================================
# interaction_plots.R -- Tab 4 (Interactions) 2-D maps: curated questions, the
# viridis heatmap with contours, the click-to-slice 1-D cut, and the
# friction-ranking bars. Pure functions of a sweep_2d() / hanson_oprea_effect()
# data frame.
# =============================================================================

# Metrics offered on the interaction maps (id -> label). Sequential unless noted.
PM_INTERACTION_METRICS <- c(
  B = "Mean Brier", AE = "Accuracy-efficiency (AE)",
  dist_star = "Distortion |p_T - p*|", signed_dist = "Signed distortion",
  log_score = "Log score", bias = "Bias")

# Params a user may put on a map axis: the sidebar sweepables plus the two
# manipulation/extension knobs surfaced only here (B_m, r_wp).
pm_interaction_axis_choices <- function() {
  base <- pm_sweep_param_choices()
  c(base, "Bot budget (B_m)" = "B_m", "Wealth-precision corr (r_wp)" = "r_wp")
}

# pm_param_label(): readable label for any parameter id.
pm_param_label <- function(id) {
  sp <- pm_sweep_params()
  if (!is.null(sp[[id]])) return(sp[[id]]$label)
  extra <- c(B_m = "Bot budget (B_m)", r_wp = "Wealth-precision corr (r_wp)",
             bot_pistar = "Bot target price")
  if (!is.null(extra[[id]])) unname(extra[[id]]) else id
}

# pm_interaction_questions(): the curated menu (handoff Sec. 4 Tab 4). Each entry
# fixes both axes + metric (+ any extra param overrides); q5 is the special
# friction-ranking bar exhibit.
pm_interaction_questions <- function() list(
  q1 = list(label = "Echo-chamber wealth: does inequality deepen the correlation ceiling?",
            x = "rho", y = "alpha_w", metric = "AE", extra = NULL, contour = FALSE,
            xr = c(0, 0.9), yr = c(1.1, 3)),
  q2 = list(label = "Manipulation frontier: how far can a funded bot push the price?",
            x = "B_m", y = "tau", metric = "dist_star", extra = list(bot_on = TRUE),
            contour = TRUE, xr = c(0.02, 0.5), yr = c(0, 0.3)),
  q3 = list(label = "Fee optimum: is there a best fee when the rich see sharper signals?",
            x = "tau", y = "r_wp", metric = "B", extra = NULL, contour = FALSE,
            xr = c(0, 0.3), yr = c(-1, 1)),
  q4 = list(label = "Manufactured cascades: does a brief bot (rounds 3-8) leave a lasting mark?",
            x = "h", y = "B_m", metric = "dist_star",
            extra = list(bot_on = TRUE, bot_rounds = 3:8), contour = FALSE,
            xr = c(0, 0.9), yr = c(0.02, 0.5)),
  q5 = list(label = "Friction ranking: which cost lets manipulation wake a sleepy market?",
            special = "hanson_oprea")
)

# pm_heatmap_plot(): viridis fill over the (x, y) grid with contour lines. When
# `contour_frontier` is given, that one level is drawn heavy (the frontier).
pm_heatmap_plot <- function(df, x_param, y_param, metric, contour = FALSE,
                            contour_frontier = NULL) {
  df$z <- df[[metric]]
  mlab <- unname(PM_INTERACTION_METRICS[metric])
  p <- ggplot2::ggplot(df, ggplot2::aes(x, y)) +
    ggplot2::geom_tile(ggplot2::aes(fill = z)) +
    ggplot2::scale_fill_viridis_c(name = mlab, option = "viridis")
  if (contour) {
    p <- p + ggplot2::geom_contour(ggplot2::aes(z = z), color = "white",
                                   alpha = 0.5, linewidth = 0.3)
    if (!is.null(contour_frontier)) {
      p <- p + ggplot2::geom_contour(ggplot2::aes(z = z), breaks = contour_frontier,
                                     color = "white", linewidth = 1)
    }
  }
  p +
    ggplot2::labs(
      title = mlab,
      subtitle = "Click a cell to slice along the x-axis below",
      x = pm_param_label(x_param), y = pm_param_label(y_param)) +
    ggplot2::scale_x_continuous(expand = c(0, 0)) +
    ggplot2::scale_y_continuous(expand = c(0, 0)) +
    theme_pm()
}

# pm_interaction_slice_plot(): the 1-D cut through the map at the y value nearest
# the click -- metric vs x, holding y fixed.
pm_interaction_slice_plot <- function(df, x_param, y_param, metric, at_y) {
  ys <- sort(unique(df$y))
  y_sel <- ys[which.min(abs(ys - at_y))]
  sub <- df[df$y == y_sel, ]
  sub <- sub[order(sub$x), ]
  mlab <- unname(PM_INTERACTION_METRICS[metric])
  ggplot2::ggplot(sub, ggplot2::aes(x, .data[[metric]])) +
    ggplot2::geom_line(color = PM_COL$price, linewidth = 0.9) +
    ggplot2::geom_point(color = PM_COL$price, size = 1.8) +
    ggplot2::labs(
      title = sprintf("Slice at %s = %s", pm_param_label(y_param), formatC(y_sel, digits = 3)),
      x = pm_param_label(x_param), y = mlab) +
    theme_pm()
}

# pm_friction_ranking_plot(): the Hanson-Oprea exhibit (q5). Bars = change in
# Brier when the bot is switched on, one per friction; below zero means the bot
# *improves* accuracy (wakes dormant traders).
pm_friction_ranking_plot <- function(ho) {
  ho$friction <- factor(ho$friction, levels = ho$friction[order(ho$effect)])
  ho$helps <- ifelse(ho$effect < 0, "Bot improves accuracy", "Bot worsens accuracy")
  ggplot2::ggplot(ho, ggplot2::aes(friction, effect, fill = helps)) +
    ggplot2::geom_col(width = 0.6) +
    ggplot2::geom_hline(yintercept = 0, color = "grey40", linewidth = 0.4) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%+.3f", effect),
                                    vjust = ifelse(effect >= 0, -0.4, 1.3)),
                       size = 3.4, color = PM_UI$text) +
    ggplot2::scale_fill_manual(values = c("Bot improves accuracy" = PM_COL$benchmark,
                                          "Bot worsens accuracy" = PM_COL$manip), name = NULL) +
    ggplot2::labs(
      title = "Does manipulation wake a sleepy market?",
      subtitle = "Change in Brier when the bot is switched on, by which friction is present (lower = bot helps)",
      x = NULL, y = "Brier(bot on) - Brier(bot off)") +
    theme_pm() + ggplot2::theme(legend.position = "bottom")
}
