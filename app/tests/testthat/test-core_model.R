# =============================================================================
# test-core_model.R -- Unit tests 1-6 of handoff Sec. 7.1 (exact, must pass).
# Test 7 (Murphy identity) lives in test-metrics.R since it needs the ensemble
# metric helpers. Reference values in the comments are from the handoff.
# =============================================================================

# The model core is sourced by helper-source.R (testthat loads helpers first).

# -----------------------------------------------------------------------------
# Test 1: LMSR consistency -- closed-form cost equals C(q') - C(q) to 1e-9,
# budget-formula price matches, shares formula consistent. Plus the exact
# reference values from the spec (b = 7).
# -----------------------------------------------------------------------------
test_that("LMSR closed forms agree with the cost potential C and reference values", {
  b <- 7; qY <- 4.2; qN <- -2.0
  p <- lmsr_price(qY, qN, b)
  expect_equal(p, 0.7080050, tolerance = 1e-6)

  # Reference: buying YES to p' = 0.85 costs 4.6627106.
  by <- lmsr_buy_yes(p, 0.85, b)
  expect_equal(by$cost, 4.6627106, tolerance = 1e-6)
  # Cost equals the increase in the cost potential C when q_Y grows by `shares`.
  C0 <- lmsr_cost_C(qY, qN, b)
  C1 <- lmsr_cost_C(qY + by$shares, qN, b)
  expect_equal(by$cost, C1 - C0, tolerance = 1e-9)

  # Reference: buying NO to p' = 0.45 costs 3.1724246.
  bn <- lmsr_buy_no(p, 0.45, b)
  expect_equal(bn$cost, 3.1724246, tolerance = 1e-6)
  Cn <- lmsr_cost_C(qY, qN + bn$shares, b)
  expect_equal(bn$cost, Cn - C0, tolerance = 1e-9)

  # Reference: spending m = 3 on YES from p reaches p' = 0.8097830.
  p_reach <- lmsr_price_after_spend_yes(p, 3, b)
  expect_equal(p_reach, 0.8097830, tolerance = 1e-6)
  # And the cost of moving to that reached price is exactly m = 3.
  expect_equal(lmsr_buy_yes(p, p_reach, b)$cost, 3, tolerance = 1e-9)

  # Random consistency sweep over interior prices. Build each state so its true
  # price is exactly p (q_Y = b*logit(p), q_N = 0), keeping p, p' inside the
  # clamp band so the closed forms are the exact market state (no clamping).
  set.seed(11)
  for (r in seq_len(200)) {
    bb <- runif(1, 2, 20)
    pp <- runif(1, 0.05, 0.95)
    qy <- bb * qlogis(pp); qn <- 0
    # YES leg: move up to a price in (pp, 0.98)
    ptp <- runif(1, pp + 0.005, 0.98)
    ty  <- lmsr_buy_yes(pp, ptp, bb)
    expect_equal(ty$cost, lmsr_cost_C(qy + ty$shares, qn, bb) - lmsr_cost_C(qy, qn, bb),
                 tolerance = 1e-9)
    expect_equal(lmsr_price_after_spend_yes(pp, ty$cost, bb), ptp, tolerance = 1e-9)
    # NO leg: move down to a price in (0.02, pp)
    ptn <- runif(1, 0.02, pp - 0.005)
    tn  <- lmsr_buy_no(pp, ptn, bb)
    expect_equal(tn$cost, lmsr_cost_C(qy, qn + tn$shares, bb) - lmsr_cost_C(qy, qn, bb),
                 tolerance = 1e-9)
    expect_equal(lmsr_price_after_spend_no(pp, tn$cost, bb), ptn, tolerance = 1e-9)
  }
})

# -----------------------------------------------------------------------------
# Test 2: worst-case operator loss <= b*ln 2 (equality in the limit as price is
# driven to an extreme). From p0 = 0.5, driving YES to p' and paying out the
# YES shares gives loss = b*ln(2p'), which approaches b*ln2 from below.
# -----------------------------------------------------------------------------
test_that("worst-case operator loss is bounded by b*ln 2", {
  b <- 10; p0 <- 0.5
  loss_at <- function(pp) {                  # operator loss if YES wins
    shares <- b * (qlogis(pp) - qlogis(p0))  # YES shares sold from p0 -> pp
    cost   <- b * (log(1 - p0) - log(1 - pp))
    shares - cost                            # payout (1/share) minus revenue
  }
  bound <- b * log(2)
  for (pp in c(0.9, 0.99, 0.999, 0.999999)) {
    expect_lt(loss_at(pp), bound + 1e-9)     # never exceeds the bound
  }
  expect_equal(loss_at(1 - 1e-9), bound, tolerance = 1e-6)  # equality in limit

  # Same guarantee end-to-end: no full run's operator P&L drops below -b*ln2.
  for (sd in 1:20) {
    res <- run_market(pm_default_params(), seed = sd, record = "light")
    expect_gte(res$operator_pnl, -res$params$b * log(2) - 1e-8)
  }
})

# -----------------------------------------------------------------------------
# Test 3: posterior formulas match brute-force numeric Bayes to 1e-6, and n_eff
# matches the 1'Sigma 1 computation (n = 50, rho = 0.3 => 3.1847134).
# -----------------------------------------------------------------------------
test_that("informed posterior matches a fine-grid Bayes computation", {
  # Independent numeric Bayes: integrate the unnormalized posterior over theta
  # with adaptive quadrature (integrate()), then normalize. No closed form used.
  bayes_grid <- function(s, mu0, sigma0, sigma_eps, c) {
    kern <- function(th) dnorm(th, mu0, sigma0) * dnorm(s, th, sigma_eps)
    num <- integrate(kern, c, Inf, rel.tol = 1e-10)$value
    den <- integrate(kern, -Inf, Inf, rel.tol = 1e-10)$value
    num / den
  }
  cases <- list(
    c(s =  1.3, mu0 = 0, sigma0 = 1,   sigma_eps = 1,   c = 0),
    c(s = -0.7, mu0 = 0.2, sigma0 = 1.5, sigma_eps = 0.8, c = 0.3),
    c(s =  2.5, mu0 = -1, sigma0 = 2,   sigma_eps = 1.2, c = 0.5)
  )
  for (cs in cases) {
    got <- informed_posterior(cs["s"], cs["mu0"], cs["sigma0"], cs["sigma_eps"], cs["c"])$p_tilde
    ref <- bayes_grid(cs["s"], cs["mu0"], cs["sigma0"], cs["sigma_eps"], cs["c"])
    expect_equal(unname(got), unname(ref), tolerance = 1e-6)
  }
})

test_that("n_eff matches 1'Sigma 1 for the equicorrelated covariance", {
  n <- 50; rho <- 0.3
  Sigma <- matrix(rho, n, n); diag(Sigma) <- 1
  n_eff_from_Sigma <- n^2 / sum(Sigma)      # = n / (1 + (n-1) rho)
  expect_equal(n_eff(n, rho), n_eff_from_Sigma, tolerance = 1e-9)
  expect_equal(n_eff(n, rho), 3.1847134, tolerance = 1e-6)
})

# -----------------------------------------------------------------------------
# Test 4: the Kelly stake f* = (p_tilde - p)/(1 - p) maximizes E[log wealth]
# (fixed-odds bet at price p). Grid search over f must land on f*.
# -----------------------------------------------------------------------------
test_that("Kelly fraction maximizes expected log wealth (grid check)", {
  elog <- function(f, pt, p) pt * log(1 - f + f / p) + (1 - pt) * log(1 - f)
  for (cs in list(c(pt = 0.7, p = 0.5), c(pt = 0.9, p = 0.6), c(pt = 0.55, p = 0.4))) {
    pt <- cs["pt"]; p <- cs["p"]
    f_star <- (pt - p) / (1 - p)
    fs <- seq(1e-4, min(0.999, 1 - 1e-4), length.out = 200001)
    f_grid_best <- fs[which.max(elog(fs, pt, p))]
    expect_equal(unname(f_star), unname(f_grid_best), tolerance = 1e-3)
  }
})

# -----------------------------------------------------------------------------
# Test 5: money conservation at every step with all frictions on (1e-8), and
# operator >= -b*ln2 post-resolution.
# -----------------------------------------------------------------------------
test_that("money is conserved at every step and operator stays above -b*ln2", {
  p <- pm_default_params()
  p$n <- 60L; p$T <- 15L
  p$tau <- 0.04; p$kappa <- 0.05; p$c_part <- 0.15
  p$phi_noise <- 0.2; p$phi_manip <- 0.1; p$h <- 0.2
  p$bot_on <- TRUE; p$B_m <- 0.1
  res <- run_market(p, seed = 123, record = "full", audit = TRUE)

  # Invariant holds after every single agent turn.
  expect_true(all(abs(res$audit - res$initial_total) < 1e-8))

  # Invariant still holds post-resolution: wealth + operator + burned == initial.
  final_total <- sum(res$agents_final$w) + res$operator_pnl + res$burned
  expect_equal(final_total, res$initial_total, tolerance = 1e-8)

  # Operator's realized P&L never below the LMSR subsidy bound.
  expect_gte(res$operator_pnl, -res$params$b * log(2) - 1e-8)
})

# -----------------------------------------------------------------------------
# Test 6: determinism -- same seed reproduces the trajectory exactly.
# -----------------------------------------------------------------------------
test_that("run_market is deterministic given a seed", {
  p <- pm_default_params(); p$phi_noise <- 0.2; p$bot_on <- TRUE
  a <- run_market(p, seed = 777, record = "full")
  b <- run_market(p, seed = 777, record = "full")
  expect_identical(a$price_round, b$price_round)
  expect_identical(a$p_T, b$p_T)
  expect_identical(a$theta, b$theta)
  expect_equal(a$trades, b$trades)
})

# -----------------------------------------------------------------------------
# User account (Live Market tab): money conservation still holds with a user
# wallet + injected user trades and all frictions; and a scheduled intervention
# leaves the pre-intervention prefix identical (the basis of the replay engine).
# -----------------------------------------------------------------------------
test_that("user trades conserve money and preserve the pre-intervention prefix", {
  p <- pm_default_params()
  p$n <- 50L; p$T <- 12L
  p$tau <- 0.03; p$kappa <- 0.04; p$c_part <- 0.1
  p$phi_noise <- 0.2; p$bot_on <- TRUE
  p$user_wallet <- 8
  uts <- list(list(round = 4L, side = "YES", amount = 3),
              list(round = 7L, side = "NO",  amount = 2))
  res <- run_market(p, seed = 55, record = "full", audit = TRUE, user_trades = uts)

  # Invariant (now including the user wallet) holds after every step...
  expect_true(all(abs(res$audit - res$initial_total) < 1e-8))
  # ...and post-resolution.
  final_total <- sum(res$agents_final$w) + res$operator_pnl + res$burned + res$user$wallet
  expect_equal(final_total, res$initial_total, tolerance = 1e-8)
  # User actually took a position and it is reflected in the log.
  expect_true(res$user$y > 0 && res$user$z > 0)
  expect_true(any(res$trades$type == "user"))

  # Prefix determinism: a user trade at round 4 leaves rounds 1..3 unchanged
  # versus the no-intervention run with the same seed.
  base <- run_market(p, seed = 55, record = "full")          # no user_trades
  one  <- run_market(p, seed = 55, record = "full",
                     user_trades = list(list(round = 4L, side = "YES", amount = 3)))
  expect_equal(base$price_round[1:3], one$price_round[1:3], tolerance = 1e-12)
  expect_false(isTRUE(all.equal(base$price_round[5:12], one$price_round[5:12])))
})
