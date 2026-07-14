# =============================================================================
# core_ensemble.R -- Ensembles, metrics, sweeps, static benchmark, cache.
# (handoff Sec. 1.7). Pure functions on top of core_model.R; no Shiny.
#
# An "ensemble" is R independent markets run under the same parameters but
# different draws (theta, signals, wealth, beliefs, trade order). From the R
# final prices and outcomes we compute the accuracy scores the app reports:
# Brier and its Murphy decomposition, the accuracy-efficiency ratio AE,
# calibration, log score, bias, and the frictionless static benchmark.
#
# Reader's map:
#   - Scores ............. pm_brier(), murphy_decomposition(), accuracy_eff(),
#                          log_score(), calibration_fit()
#   - Ensembles .......... run_ensemble()  -> per-run table + summary metrics
#   - Sweeps ............. sweep_1d()       (1-D), with mean +/- 95% CI
#   - Cache .............. ensemble_cache_key(), cache_get(), cache_set()
# =============================================================================

# =============================================================================
# Scores
# =============================================================================

# pm_brier(): mean squared error of probabilistic forecast p against 0/1 A.
pm_brier <- function(p, A) mean((p - A)^2)

# log_score(): mean negative log-likelihood of the forecasts (clamped so a
# forecast at 0/1 that is wrong does not return Inf). Lower is better.
log_score <- function(p, A) {
  p <- clamp_p(p)
  mean(-(A * log(p) + (1 - A) * log(1 - p)))
}

# murphy_decomposition(): Murphy / calibration-refinement decomposition of the
# Brier score over K equal-width forecast bins (handoff Sec. 1.7).
#   REL (reliability, lower better): weighted gap between bin forecast and bin
#       outcome rate. RES (resolution, higher better): spread of bin outcome
#       rates around the base rate. UNC (uncertainty): base-rate variance.
# For forecasts that are constant within each bin, B = REL - RES + UNC exactly.
# With continuous forecasts a within-bin term remains; we return it as `gap` and
# also its exact algebraic value wbv - 2*wbc (verified in test 7):
#   B = REL - RES + UNC + (WBV - 2*WBC),
# where WBV = within-bin forecast variance and WBC = within-bin forecast/outcome
# covariance (both weighted by 1/N).
murphy_decomposition <- function(f, o, K = 10) {
  N <- length(f)
  f <- clamp_p(f)
  obar <- mean(o)
  # Equal-width bins over [0,1]; bin index in 1..K.
  bin <- pmin(floor(f * K) + 1L, K)
  bin <- pmax(bin, 1L)
  fk <- tapply(f, bin, mean)
  ok <- tapply(o, bin, mean)
  nk <- tapply(f, bin, length)
  # Align to present bins only (empty bins contribute nothing).
  present <- as.integer(names(nk))
  fk <- as.numeric(fk); ok <- as.numeric(ok); nk <- as.numeric(nk)

  REL <- sum(nk * (fk - ok)^2) / N
  RES <- sum(nk * (ok - obar)^2) / N
  UNC <- obar * (1 - obar)
  B   <- pm_brier(f, o)

  # Within-bin terms (exact decomposition remainder).
  fk_of_i <- fk[match(bin, present)]
  ok_of_i <- ok[match(bin, present)]
  WBV <- sum((f - fk_of_i)^2) / N
  WBC <- sum((f - fk_of_i) * (o - ok_of_i)) / N

  list(
    B = B, REL = REL, RES = RES, UNC = UNC,
    gap = B - (REL - RES + UNC),          # numerical remainder
    within_term = WBV - 2 * WBC,          # exact algebraic remainder
    WBV = WBV, WBC = WBC,
    bins = data.frame(bin = present, f = fk, o = ok, n = nk)
  )
}

# accuracy_eff(): AE = (B_prior - B) / (B_prior - B_omn). 1 => the market is as
# good as the omniscient forecast; 0 => no better than the prior; <0 => worse
# than the prior (handoff Sec. 1.7).
accuracy_eff <- function(B, B_prior, B_omn) {
  denom <- B_prior - B_omn
  if (abs(denom) < 1e-12) return(NA_real_)
  (B_prior - B) / denom
}

# calibration_fit(): logistic calibration of outcomes on the forecast logit.
# Slope 1 / intercept 0 is perfect calibration. Guarded against degenerate fits.
calibration_fit <- function(p, A) {
  p <- clamp_p(p)
  out <- tryCatch(
    stats::glm(A ~ pm_logit(p), family = stats::binomial()),
    warning = function(w) NULL, error = function(e) NULL
  )
  if (is.null(out)) return(c(intercept = NA_real_, slope = NA_real_))
  co <- stats::coef(out)
  c(intercept = unname(co[1]), slope = unname(co[2]))
}

# =============================================================================
# Ensembles
# =============================================================================

# run_ensemble(): R independent markets under `params`. Replication r uses
# seed base_seed + r so the whole ensemble is reproducible and each run sees a
# fresh world. Returns the per-run table and a one-row summary of ensemble
# metrics. record = "light" keeps each run cheap (no trade log / snapshots).
run_ensemble <- function(params, R = NULL, seed = NULL) {
  if (is.null(R)) R <- params$R
  if (is.null(seed)) seed <- params$seed
  base_seed <- if (is.null(seed) || is.na(seed)) 1L else as.integer(seed)

  # Per-run accumulators.
  p_T <- p0 <- p_star <- p_static <- numeric(R)
  A   <- integer(R)
  conv <- volat <- volume <- particip <- active <- numeric(R)

  for (r in seq_len(R)) {
    res <- run_market(params, seed = base_seed + r, record = "light")
    p_T[r]      <- res$p_T
    p0[r]       <- res$p0
    p_star[r]   <- res$p_star
    p_static[r] <- res$p_static
    A[r]        <- res$A
    conv[r]     <- res$conv_time
    volat[r]    <- res$volatility
    volume[r]   <- res$volume
    tp <- res$agents_final$type
    nonmanip <- tp != "manipulator"
    # Participation = entered the market (paid c_part); active = actually took a
    # position (traded at least once -> outside the no-trade band). Both are over
    # non-manipulator agents; together they carry the friction / Hanson-Oprea story.
    held <- (res$agents_final$y + res$agents_final$z) > 1e-9
    particip[r] <- if (any(nonmanip)) mean(res$agents_final$entered[nonmanip]) else NA_real_
    active[r]   <- if (any(nonmanip)) mean(held[nonmanip]) else NA_real_
  }

  runs <- data.frame(
    r = seq_len(R), p_T = p_T, A = A, p0 = p0, p_star = p_star,
    p_static = p_static, conv_time = conv, volatility = volat,
    volume = volume, participation = particip, active = active
  )

  # Ensemble scores.
  B       <- pm_brier(p_T, A)
  B_prior <- pm_brier(p0, A)
  B_omn   <- pm_brier(p_star, A)
  B_static <- pm_brier(p_static, A)
  AE      <- accuracy_eff(B, B_prior, B_omn)
  mu      <- murphy_decomposition(p_T, A)
  cal     <- calibration_fit(p_T, A)

  # Per-run Brier (for analytic CIs on B).
  brier_i <- (p_T - A)^2

  summary <- list(
    R = R,
    B = B, B_prior = B_prior, B_omn = B_omn, B_static = B_static,
    AE = AE,
    REL = mu$REL, RES = mu$RES, UNC = mu$UNC, murphy_gap = mu$gap,
    log_score = log_score(p_T, A),
    bias = mean(p_T) - mean(A),
    dist_star = mean(abs(p_T - p_star)),   # mean |p_T - p*|: distance to best possible
    signed_dist = mean(p_T - p_star),      # signed: manipulation pushes this away from 0
    calib_intercept = cal["intercept"], calib_slope = cal["slope"],
    conv_time = mean(conv), volatility = mean(volat), volume = mean(volume),
    participation = mean(particip, na.rm = TRUE),
    active = mean(active, na.rm = TRUE),
    brier_se = stats::sd(brier_i) / sqrt(R),
    base_rate = mean(A)
  )

  list(runs = runs, summary = summary, params = params, seed = base_seed)
}

# =============================================================================
# Sweeps (1-D)
# =============================================================================

# sweep_1d(): vary one parameter across `values`, run an ensemble at each, and
# return a tidy data frame: one row per value with the requested metrics and a
# 95% CI for the mean Brier (analytic, from per-run variance). Reference lines
# B_prior and B_omn and the static-benchmark Brier travel along for the plot.
#
# metrics: any subset of c("B","AE","log_score","bias","REL","RES"). The frame
# always includes B, B_prior, B_omn, B_static and the Brier CI.
sweep_1d <- function(base_params, param, values, R = NULL, seed = NULL,
                     metrics = c("B", "AE", "log_score", "bias", "REL", "RES"),
                     progress = NULL) {
  rows <- vector("list", length(values))
  for (j in seq_along(values)) {
    p <- base_params
    p[[param]] <- values[[j]]
    ens <- run_ensemble(p, R = R, seed = seed)
    s <- ens$summary
    ci <- 1.96 * s$brier_se
    rows[[j]] <- data.frame(
      param = param, value = values[[j]],
      B = s$B, B_lo = s$B - ci, B_hi = s$B + ci,
      B_prior = s$B_prior, B_omn = s$B_omn, B_static = s$B_static,
      AE = s$AE, log_score = s$log_score, bias = s$bias,
      REL = s$REL, RES = s$RES, UNC = s$UNC,
      participation = s$participation, active = s$active, conv_time = s$conv_time,
      volatility = s$volatility, volume = s$volume,
      calib_slope = unname(s$calib_slope),
      stringsAsFactors = FALSE
    )
    if (is.function(progress)) progress(j / length(values))
  }
  do.call(rbind, rows)
}

# =============================================================================
# Sweeps (2-D) -- interaction maps (Tab 4)
# =============================================================================

# sweep_2d(): vary two parameters over a grid and run an ensemble at each cell.
# `extra` is a list of fixed parameter overrides applied on top of base (e.g.
# list(bot_on = TRUE, bot_rounds = 3:8) for a scripted-bot map). Returns one row
# per cell with the full metric set. `progress` is called with a 0..1 fraction.
sweep_2d <- function(base_params, x_param, x_values, y_param, y_values,
                     R = NULL, seed = NULL, extra = NULL, progress = NULL) {
  grid <- expand.grid(x = x_values, y = y_values, KEEP.OUT.ATTRS = FALSE)
  n <- nrow(grid)
  rows <- vector("list", n)
  for (k in seq_len(n)) {
    p <- base_params
    if (length(extra)) for (nm in names(extra)) p[[nm]] <- extra[[nm]]
    p[[x_param]] <- grid$x[k]
    p[[y_param]] <- grid$y[k]
    s <- run_ensemble(p, R = R, seed = seed)$summary
    rows[[k]] <- data.frame(
      x = grid$x[k], y = grid$y[k],
      B = s$B, AE = s$AE, dist_star = s$dist_star, signed_dist = s$signed_dist,
      log_score = s$log_score, bias = s$bias, REL = s$REL, RES = s$RES,
      participation = s$participation, active = s$active,
      stringsAsFactors = FALSE)
    if (is.function(progress)) progress(k / n)
  }
  out <- do.call(rbind, rows)
  attr(out, "x_param") <- x_param
  attr(out, "y_param") <- y_param
  out
}

# hanson_oprea_effect(): the friction-ranking exhibit (Tab 4 Q5). For each single
# friction (c_part / kappa / tau) at `level`, the change in mean Brier when the
# manipulator bot is switched on (with a per-run random target so its direction
# averages out): negative => the bot's noise wakes dormant traders and *improves*
# accuracy (Hanson-Oprea). Returns a tidy frame: friction, B_off, B_on, effect.
hanson_oprea_effect <- function(base_params, level = 0.2, B_m = 0.1, R = NULL,
                                seed = NULL, progress = NULL) {
  regimes <- list(
    "Participation cost" = list(c_part = level),
    "Fixed cost"         = list(kappa = level),
    "Proportional fee"   = list(tau = min(level, 0.15)))
  rows <- list(); i <- 0; tot <- length(regimes) * 2
  for (nm in names(regimes)) {
    p0 <- base_params
    p0$c_part <- 0; p0$kappa <- 0; p0$tau <- 0
    for (k in names(regimes[[nm]])) p0[[k]] <- regimes[[nm]][[k]]
    p_off <- p0; p_off$bot_on <- FALSE
    p_on  <- p0; p_on$bot_on <- TRUE; p_on$B_m <- B_m; p_on$bot_pistar_random <- TRUE
    B_off <- run_ensemble(p_off, R = R, seed = seed)$summary$B
    i <- i + 1; if (is.function(progress)) progress(i / tot)
    B_on  <- run_ensemble(p_on,  R = R, seed = seed)$summary$B
    i <- i + 1; if (is.function(progress)) progress(i / tot)
    rows[[length(rows) + 1]] <- data.frame(
      friction = nm, B_off = B_off, B_on = B_on, effect = B_on - B_off,
      stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

# =============================================================================
# Cache: ensemble results are expensive; key them by a digest of the inputs so
# the app never recomputes an identical sweep (handoff Sec. 4 cross-cutting).
# A simple in-memory environment; the app can swap in a disk cache later.
# =============================================================================
.pm_cache <- new.env(parent = emptyenv())

ensemble_cache_key <- function(params, sweep_spec = NULL, R = NULL, seed = NULL) {
  digest::digest(list(params = params, sweep_spec = sweep_spec, R = R, seed = seed))
}
cache_get <- function(key) if (exists(key, envir = .pm_cache, inherits = FALSE))
  get(key, envir = .pm_cache) else NULL
cache_set <- function(key, value) assign(key, value, envir = .pm_cache)
cache_clear <- function() rm(list = ls(.pm_cache), envir = .pm_cache)
