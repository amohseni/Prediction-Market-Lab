# =============================================================================
# test-metrics.R -- Test 7 of handoff Sec. 7.1: the Murphy decomposition
# arithmetic. Sourcing is handled by helper-source.R.
# =============================================================================

# -----------------------------------------------------------------------------
# Test 7: Murphy identity B = REL - RES + UNC + (within-bin term), verified on
# synthetic forecasts. The within-bin term equals WBV - 2*WBC exactly; the
# numerical remainder `gap` must match it to 1e-9. Also sanity-check REL/RES/UNC
# against their direct definitions.
# -----------------------------------------------------------------------------
test_that("Murphy decomposition arithmetic is exact on synthetic forecasts", {
  set.seed(42)
  for (rep in seq_len(50)) {
    N <- sample(200:2000, 1)
    f <- runif(N)                       # arbitrary continuous forecasts
    # Outcomes correlated with forecasts so bins are non-degenerate.
    o <- rbinom(N, 1, pmin(pmax(f + rnorm(N, 0, 0.15), 0.01), 0.99))
    m <- murphy_decomposition(f, o, K = 10)

    # Exact remainder equals the algebraic within-bin term.
    expect_equal(m$gap, m$within_term, tolerance = 1e-9)
    # Full identity reconstructs the Brier score.
    expect_equal(m$B, m$REL - m$RES + m$UNC + m$within_term, tolerance = 1e-9)
    # UNC is the base-rate variance.
    expect_equal(m$UNC, mean(o) * (1 - mean(o)), tolerance = 1e-12)
  }

  # Constant-within-bin forecasts: within-bin term vanishes, classic identity.
  f2 <- rep(c(0.05, 0.25, 0.45, 0.65, 0.85, 0.95), each = 100)
  o2 <- rbinom(length(f2), 1, f2)
  m2 <- murphy_decomposition(f2, o2, K = 10)
  expect_equal(m2$within_term, 0, tolerance = 1e-12)
  expect_equal(m2$B, m2$REL - m2$RES + m2$UNC, tolerance = 1e-9)
})

# -----------------------------------------------------------------------------
# Supporting checks on the other scores (not in Sec 7.1, but cheap guards).
# -----------------------------------------------------------------------------
test_that("AE is 1 at the omniscient forecast and 0 at the prior", {
  expect_equal(accuracy_eff(0.10, 0.25, 0.10), 1)
  expect_equal(accuracy_eff(0.25, 0.25, 0.10), 0)
})
