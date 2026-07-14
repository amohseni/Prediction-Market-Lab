# =============================================================================
# reliability_plots.R -- Tab 3 (Reliability) plot helpers + sweep-param metadata.
# Pure functions of a sweep_1d() data frame (see core_ensemble.R). One metric
# family per function: the Brier headline with reference lines, the extra-metric
# facets, and the Murphy decomposition. Plus the bundled n_eff exhibit.
# =============================================================================

# pm_sweep_params(): the parameters a user may sweep (everything in the sidebar
# except the seed and the ensemble size R), with a readable label and the range
# to seed the min/max inputs. Drawn from the single control spec.
pm_sweep_params <- function() {
  out <- list()
  for (g in pm_controls()) for (ctrl in g$controls) {
    if (ctrl$id %in% c("seed", "R")) next
    out[[ctrl$id]] <- list(
      id = ctrl$id,
      label = paste0(tools::toTitleCase(ctrl$desc), " (", ctrl$id, ")"),
      min = ctrl$min, max = ctrl$max, kind = ctrl$kind)
  }
  out
}

# pm_sweep_param_choices(): named vector for the sweep-parameter dropdown.
pm_sweep_param_choices <- function() {
  sp <- pm_sweep_params()
  stats::setNames(vapply(sp, `[[`, "", "id"), vapply(sp, `[[`, "", "label"))
}

# ---- Bundled exhibit --------------------------------------------------------
# pm_neff_exhibit_plot(): the never-blank initial state. Solid = market Brier
# (with CI), dashed = analytic omniscient Brier; one color per rho. The ceiling
# is the fanning-out of the dashed curves.
pm_neff_exhibit_plot <- function(exhibit) {
  df <- exhibit$data
  df$rho_f <- factor(sprintf("rho = %.1f", df$rho))
  ggplot2::ggplot(df, ggplot2::aes(n, B, color = rho_f)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = B_lo, ymax = B_hi, fill = rho_f),
                         alpha = 0.12, color = NA) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 1.6) +
    ggplot2::geom_line(ggplot2::aes(y = B_omn), linetype = "dashed", linewidth = 0.7,
                       alpha = 0.75) +
    ggplot2::scale_x_log10(breaks = exhibit$ns) +
    ggplot2::scale_color_viridis_d(end = 0.85, name = NULL, aesthetics = c("color", "fill")) +
    ggplot2::labs(
      title = "The n_eff ceiling",
      subtitle = "Solid = market Brier; dashed = best possible. Correlation caps the payoff to more traders.",
      x = "Number of traders  n  (log scale)", y = "Mean Brier score") +
    theme_pm()
}

# ---- Live sweep -------------------------------------------------------------
# pm_sweep_brier_plot(): the headline. Market Brier with a 95% CI ribbon, plus
# the prior-Brier and omniscient-Brier reference curves and -- where the
# frictionless closed form exists -- the dashed static-benchmark overlay.
pm_sweep_brier_plot <- function(df, param_label) {
  lines <- rbind(
    data.frame(value = df$value, y = df$B,       series = "Market"),
    data.frame(value = df$value, y = df$B_prior, series = "Prior"),
    data.frame(value = df$value, y = df$B_omn,   series = "Best possible"))
  if (any(is.finite(df$B_static))) {
    lines <- rbind(lines,
      data.frame(value = df$value, y = df$B_static, series = "Static benchmark"))
  }
  lines$series <- factor(lines$series,
    levels = c("Market", "Best possible", "Prior", "Static benchmark"))
  cols <- c("Market" = PM_COL$price, "Best possible" = PM_COL$omniscient,
            "Prior" = PM_COL$prior, "Static benchmark" = PM_COL$benchmark)
  ltys <- c("Market" = "solid", "Best possible" = "dashed",
            "Prior" = "dotted", "Static benchmark" = "longdash")
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(data = df,
      ggplot2::aes(value, ymin = B_lo, ymax = B_hi),
      fill = PM_COL$ci_ribbon, alpha = PM_CI_ALPHA) +
    ggplot2::geom_line(data = lines,
      ggplot2::aes(value, y, color = series, linetype = series), linewidth = 0.9) +
    ggplot2::geom_point(data = df, ggplot2::aes(value, B), color = PM_COL$price, size = 1.6) +
    ggplot2::scale_color_manual(values = cols, name = NULL) +
    ggplot2::scale_linetype_manual(values = ltys, name = NULL) +
    ggplot2::labs(title = "Accuracy vs parameter",
                  subtitle = "Mean Brier (lower is better) with 95% CI, against the prior and best-possible benchmarks",
                  x = param_label, y = "Mean Brier score") +
    theme_pm() + ggplot2::theme(legend.position = "bottom")
}

# pm_sweep_metrics_plot(): the selected extra metrics as small multiples with a
# free y scale. `metrics` is a subset of the keys in PM_SWEEP_METRICS.
PM_SWEEP_METRICS <- c(AE = "AE", log_score = "Log score", bias = "Bias",
                      REL = "Reliability (REL)", RES = "Resolution (RES)")

pm_sweep_metrics_plot <- function(df, param_label, metrics) {
  metrics <- intersect(metrics, names(PM_SWEEP_METRICS))
  if (length(metrics) == 0) return(NULL)
  long <- do.call(rbind, lapply(metrics, function(m) {
    data.frame(value = df$value, y = df[[m]], metric = PM_SWEEP_METRICS[[m]])
  }))
  long$metric <- factor(long$metric, levels = PM_SWEEP_METRICS[metrics])
  ggplot2::ggplot(long, ggplot2::aes(value, y)) +
    ggplot2::geom_hline(yintercept = 0, color = "grey85", linewidth = 0.4) +
    ggplot2::geom_line(color = PM_COL$price, linewidth = 0.8) +
    ggplot2::geom_point(color = PM_COL$price, size = 1.4) +
    ggplot2::facet_wrap(~ metric, scales = "free_y") +
    ggplot2::labs(title = "Other metrics", x = param_label, y = NULL) +
    theme_pm()
}

# pm_murphy_plot(): the Brier's Murphy decomposition across the sweep --
# reliability (REL, lower better), resolution (RES, higher better) and the
# base-rate uncertainty (UNC).
pm_murphy_plot <- function(df, param_label) {
  long <- rbind(
    data.frame(value = df$value, y = df$REL, part = "Reliability (REL)"),
    data.frame(value = df$value, y = df$RES, part = "Resolution (RES)"),
    data.frame(value = df$value, y = df$UNC, part = "Uncertainty (UNC)"))
  long$part <- factor(long$part,
    levels = c("Reliability (REL)", "Resolution (RES)", "Uncertainty (UNC)"))
  ggplot2::ggplot(long, ggplot2::aes(value, y, color = part)) +
    ggplot2::geom_line(linewidth = 0.9) + ggplot2::geom_point(size = 1.4) +
    ggplot2::scale_color_manual(values = c(
      "Reliability (REL)" = PM_COL$manip, "Resolution (RES)" = PM_COL$benchmark,
      "Uncertainty (UNC)" = PM_COL$prior), name = NULL) +
    ggplot2::labs(title = "Murphy decomposition",
                  subtitle = "Brier = REL - RES + UNC (+ a small within-bin term)",
                  x = param_label, y = "Score component") +
    theme_pm() + ggplot2::theme(legend.position = "bottom")
}
