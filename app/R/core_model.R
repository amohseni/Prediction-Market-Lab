# =============================================================================
# core_model.R -- The model core (handoff Sec. 1). Pure functions, no Shiny.
#
# One prediction market, one binary event A = 1[theta >= c]. n agents trade an
# LMSR automated market maker over T rounds; each agent forms a belief, then on
# its turn takes a Kelly-sized position toward that belief subject to frictions.
# The same functions here drive the live single run, the ensembles, and the
# unit tests. Nothing here draws or knows about the UI.
#
# Reader's map:
#   - Parameters ............ pm_default_params()
#   - Numerics .............. clamp_p(), pm_logit(), pm_inv_logit()
#   - Beliefs (closed form) . prior_forecast(), informed_posterior(),
#                             omniscient_forecast(), n_eff()
#   - LMSR (closed form) .... lmsr_price(), lmsr_cost_C(), lmsr_buy_yes/no(),
#                             lmsr_price_after_spend_yes/no()
#   - One agent's decision .. agent_turn()          (mutates market/agents)
#   - One whole market ...... run_market()
#
# Sourcing this file also brings in theme.R for the numeric guards P_MIN/P_MAX.
# =============================================================================

if (!exists("P_MIN")) {
  # theme.R lives next to this file; source it for P_MIN / P_MAX if not present.
  .this_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
  if (!is.na(.this_dir) && file.exists(file.path(.this_dir, "theme.R"))) {
    source(file.path(.this_dir, "theme.R"))
  } else {
    P_MIN <- 0.001; P_MAX <- 0.999   # fallback: keep the core self-contained
  }
}

# -----------------------------------------------------------------------------
# pm_default_params(): the full default parameter set (handoff Sec. 1.2).
# Every knob the model reads lives here with its default. UI presets are just
# deltas layered on top of this list (see presets.R).
#
# r_wp is a hidden extension (Tab 4 Q3): rank-correlation between an agent's
# wealth and its signal precision. Default 0 => every agent shares sigma_eps.
# bot_* fields describe the optional manipulator bot that lives outside the n
# agents; bot_on = FALSE by default so the plain model ignores it.
# -----------------------------------------------------------------------------
pm_default_params <- function() {
  list(
    # Information
    n        = 100L,   # number of agents
    sigma_eps = 1,     # signal noise SD
    rho      = 0,      # error correlation in [0,1)
    mu0      = 0,      # prior mean on theta
    sigma0   = 1,      # prior SD on theta
    c        = 0,      # event threshold: A = 1[theta >= c]
    # Market
    b        = 10,     # LMSR liquidity
    p0_init  = 0.5,    # opening price
    T        = 20L,    # trading rounds
    # Traders
    alpha_w  = 2,      # Pareto tail index (w_min = 1)
    lambda   = 1,      # Kelly fraction
    phi_noise = 0,     # noise-trader share
    phi_manip = 0,     # structural-manipulator share
    pistar   = 0.8,    # manipulator target price pi*
    h        = 0,      # herding weight (belief adoption), informed agents
    # Frictions
    tau      = 0,      # proportional fee on trade cost
    kappa    = 0,      # fixed cost per trade
    c_part   = 0,      # one-time participation cost
    # Simulation
    seed     = NA_integer_,  # RNG seed (run_market takes seed as an argument)
    R        = 200L,   # ensemble replications
    # Hidden / extension knobs
    r_wp     = 0,      # wealth-precision rank correlation in [-1, 1] (Tab 4 Q3)
    # Manipulator bot (in-tab intervention; outside the n agents)
    bot_on     = FALSE,
    B_m        = 0.1,           # bot budget as share of total agent wealth
    bot_pistar = 0.8,           # bot target price (own pi*)
    bot_pistar_random = FALSE,  # if TRUE, draw bot target ~ U(0.1, 0.9) per run
    bot_rounds = NULL,          # NULL => active every round; else vector of t's
    # Interactive user account (Live Market tab only; 0 => no user)
    user_wallet = 0             # starting cash for the user's own trades
  )
}

# =============================================================================
# Numerical guards
# =============================================================================

# clamp_p(): keep prices/beliefs strictly inside (0,1) so logit/log never blow
# up (handoff pitfall: clamp before every logit/log).
clamp_p <- function(p) pmin(pmax(p, P_MIN), P_MAX)

# logit and its inverse. Base R's qlogis/plogis are exactly these; we wrap them
# under model-native names and clamp the input to logit.
pm_logit     <- function(p) qlogis(clamp_p(p))
pm_inv_logit <- function(x) plogis(x)

# =============================================================================
# Beliefs -- all closed form (handoff Sec. 1.3). Never numerically integrate.
# =============================================================================

# prior_forecast(): p0 = Phi((mu0 - c)/sigma0), the market's belief before any
# private signal. Also the "prior" reference line in the plots.
prior_forecast <- function(mu0, sigma0, c) {
  pnorm((mu0 - c) / sigma0)
}

# informed_posterior(): conjugate-normal update of one (or many) agents who saw
# signal(s) s. Precision-weighted blend of prior and signal; returns the
# posterior mean/SD and the implied forecast p_tilde = Phi((mu_post - c)/sigma_post).
# Vectorized over s and sigma_eps (per-agent precision allowed).
informed_posterior <- function(s, mu0, sigma0, sigma_eps, c) {
  prec      <- 1 / sigma0^2 + 1 / sigma_eps^2
  mu_post   <- (mu0 / sigma0^2 + s / sigma_eps^2) / prec
  sigma_post <- prec^(-1 / 2)
  list(
    mu_post    = mu_post,
    sigma_post = sigma_post,
    p_tilde    = pnorm((mu_post - c) / sigma_post)
  )
}

# n_eff(): effective sample size of n equicorrelated (rho) signals. Averaging
# correlated signals is worth fewer than n independent ones; this is the source
# of the "n_eff ceiling" (Echo chamber preset). n_eff = n / (1 + (n-1) rho).
n_eff <- function(n, rho) {
  n / (1 + (n - 1) * rho)
}

# omniscient_forecast(): the best forecast attainable from ALL n signals at once
# (handoff Sec. 1.3). Pools the signals through n_eff, then does the conjugate
# update. p* is the "best possible" reference line and the ceiling for accuracy.
# Assumes homogeneous sigma_eps (the equicorrelated case the ceiling is defined
# for); with per-agent precision it uses the supplied scalar sigma_eps.
omniscient_forecast <- function(s_vec, mu0, sigma0, sigma_eps, rho, c) {
  n     <- length(s_vec)
  ne    <- n_eff(n, rho)
  s_bar <- mean(s_vec)
  prec_star  <- 1 / sigma0^2 + ne / sigma_eps^2
  mu_star    <- (mu0 / sigma0^2 + ne * s_bar / sigma_eps^2) / prec_star
  sigma_star <- prec_star^(-1 / 2)
  pnorm((mu_star - c) / sigma_star)
}

# =============================================================================
# LMSR market maker -- all closed form (handoff Sec. 1.4).
#
# State is share counts (q_Y, q_N). Price of YES is a softmax of the two.
# Buying YES pushes price up; buying NO pushes it down. Selling is modeled as
# buying the opposite side. Cost function C(q) = b * log(sum exp(q/b)); a trade's
# cash cost is the increase in C. We also expose the closed-form cost/share and
# "how far does m dollars move the price" (budget) formulas the spec gives, and
# a test checks the two agree to 1e-9.
# =============================================================================

# lmsr_price(): p = e^{q_Y/b} / (e^{q_Y/b} + e^{q_N/b}), written stably via plogis.
lmsr_price <- function(q_Y, q_N, b) {
  plogis((q_Y - q_N) / b)
}

# lmsr_cost_C(): the LMSR cost potential C(q_Y, q_N) = b * log(e^{q_Y/b}+e^{q_N/b}),
# computed with the log-sum-exp trick for numerical stability.
lmsr_cost_C <- function(q_Y, q_N, b) {
  a <- q_Y / b; d <- q_N / b
  m <- pmax(a, d)
  b * (m + log(exp(a - m) + exp(d - m)))
}

# lmsr_buy_yes(): buy YES to move price p -> p_prime (p_prime > p).
# Returns shares gained and cash cost. Closed forms from Sec. 1.4.
lmsr_buy_yes <- function(p, p_prime, b) {
  p <- clamp_p(p); p_prime <- clamp_p(p_prime)
  shares <- b * (pm_logit(p_prime) - pm_logit(p))
  cost   <- b * (log(1 - p) - log(1 - p_prime))   # = b*log((1-p)/(1-p'))
  list(shares = shares, cost = cost)
}

# lmsr_buy_no(): buy NO to move price p -> p_prime (p_prime < p).
lmsr_buy_no <- function(p, p_prime, b) {
  p <- clamp_p(p); p_prime <- clamp_p(p_prime)
  shares <- b * (pm_logit(1 - p_prime) - pm_logit(1 - p))
  cost   <- b * (log(p) - log(p_prime))           # = b*log(p/p')
  list(shares = shares, cost = cost)
}

# lmsr_price_after_spend_yes(): spending m dollars buying YES reaches this price.
lmsr_price_after_spend_yes <- function(p, m, b) {
  p <- clamp_p(p)
  1 - (1 - p) * exp(-m / b)
}

# lmsr_price_after_spend_no(): spending m dollars buying NO reaches this price.
lmsr_price_after_spend_no <- function(p, m, b) {
  p <- clamp_p(p)
  p * exp(-m / b)
}

# =============================================================================
# One agent's turn (handoff Sec. 1.5) -- the core decision rule.
#
# Mutates two environments in place (R passes environments by reference), which
# is what makes a sequential market cheap to simulate:
#   market : q_Y, q_N, p, operator, burned  (+ trade log when recording)
#   ag     : per-agent vectors w, p_tilde, y, z, type, is_bot, entered
# Returns invisibly; all effects are on `market` and `ag`.
#
# The nine steps below map 1:1 onto the algorithm in the spec. Manipulators and
# the bot skip belief adoption (step 1) and the participation gate (step 6):
# they are ordinary agents with a frozen belief who are always "entered".
# =============================================================================
agent_turn <- function(i, market, ag, params, t = NA_integer_) {
  # Hot path: called n*T times per market, so the scalar math below is inlined
  # (no helper list allocations, no plogis/qlogis wrappers) rather than calling
  # the lmsr_* functions. The formulas are identical to Sec. 1.4 -- the unit
  # tests pin the lmsr_* helpers, and test 5 pins this inlined arithmetic via
  # the money-conservation invariant.
  tau <- params$tau; b <- params$b; lambda <- params$lambda
  is_manip <- ag$type[i] == "manipulator"   # structural manipulators and the bot

  p  <- market$p
  pt <- ag$p_tilde[i]

  # Step 1: belief adoption (herding), informed agents only, before trading.
  if (!is_manip && params$h > 0 && ag$type[i] == "informed") {
    pt <- (1 - params$h) * pt + params$h * p
    if (pt < P_MIN) pt <- P_MIN else if (pt > P_MAX) pt <- P_MAX
    ag$p_tilde[i] <- pt          # persistent: stored belief overwritten
  }

  # Step 2: direction. The (1+tau) factor is the no-trade band around price.
  if (pt > p * (1 + tau)) {
    side_yes <- TRUE
  } else if ((1 - pt) > (1 - p) * (1 + tau)) {
    side_yes <- FALSE
  } else {
    return(invisible(FALSE))     # inside no-trade band
  }

  # Step 3: Kelly stake at the pre-trade price (fixed-odds convention, not a bug).
  f_star <- if (side_yes) (pt - p) / (1 - p) else (p - pt) / p
  m_star <- lambda * ag$w[i] * f_star   # max total outlay incl. fee
  if (m_star <= 0) return(invisible(FALSE))
  m_cost <- m_star / (1 + tau)          # portion available for LMSR cost

  # Steps 4-5: price caps (belief-implied vs budget) and the resulting trade.
  # p_final clamped into (P_MIN, P_MAX); shares/cost from the Sec. 1.4 forms.
  if (side_yes) {
    p_target <- pt / (1 + tau)
    p_reach  <- 1 - (1 - p) * exp(-m_cost / b)
    p_final  <- if (p_target < p_reach) p_target else p_reach
    if (p_final < P_MIN) p_final <- P_MIN else if (p_final > P_MAX) p_final <- P_MAX
    delta <- b * (log(p_final / (1 - p_final)) - log(p / (1 - p)))
    cost  <- b * (log(1 - p) - log(1 - p_final))
  } else {
    p_target <- 1 - (1 - pt) / (1 + tau)
    p_reach  <- p * exp(-m_cost / b)
    p_final  <- if (p_target > p_reach) p_target else p_reach
    if (p_final < P_MIN) p_final <- P_MIN else if (p_final > P_MAX) p_final <- P_MAX
    delta <- b * (log((1 - p_final) / p_final) - log((1 - p) / p))
    cost  <- b * (log(p) - log(p_final))
  }
  if (delta <= 0 || cost <= 0) return(invisible(FALSE))
  fee    <- tau * cost
  outlay <- cost + fee

  # Expected profit at the agent's own belief (used by both gates below).
  e_profit <- if (side_yes) delta * pt - outlay else delta * (1 - pt) - outlay

  # Step 6: participation gate (one-way entry), skipped by manipulators/bot.
  if (!is_manip && ag$entered[i] == 0L) {
    if (e_profit < params$c_part) return(invisible(FALSE))   # stays dormant
    ag$entered[i] <- 1L
    ag$w[i]       <- ag$w[i] - params$c_part
    market$burned <- market$burned + params$c_part           # c_part is burned
  }

  # Step 7: fixed-cost gate (only when kappa > 0). kappa goes to the operator.
  if (params$kappa > 0) {
    if (e_profit < params$kappa) return(invisible(FALSE))
    ag$w[i]         <- ag$w[i] - params$kappa
    market$operator <- market$operator + params$kappa
  }

  # Step 8: execute. Cash leaves the agent; cost + fee accrue to the operator;
  # shares and the corresponding q update; price moves to p_final.
  ag$w[i]         <- ag$w[i] - outlay
  market$operator <- market$operator + outlay              # = cost + fee
  if (side_yes) {
    ag$y[i]     <- ag$y[i] + delta
    market$q_Y  <- market$q_Y + delta
  } else {
    ag$z[i]     <- ag$z[i] + delta
    market$q_N  <- market$q_N + delta
  }
  market$p <- p_final

  # Step 9: record the trade event (only when the market is recording trades).
  if (isTRUE(market$record_trades)) {
    k <- market$ntr + 1L
    market$ntr            <- k
    market$tr_t[k]        <- t
    market$tr_trader[k]   <- i
    market$tr_type[k]     <- ag$type[i]
    market$tr_is_bot[k]   <- ag$is_bot[i]
    market$tr_side[k]     <- if (side_yes) "YES" else "NO"
    market$tr_shares[k]   <- delta
    market$tr_cost[k]     <- cost
    market$tr_fee[k]      <- fee
    market$tr_p_before[k] <- p
    market$tr_p_after[k]  <- p_final
  }
  market$volume <- market$volume + cost   # running trade volume (all record levels)

  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# user_trade(): the interactive user spends `amount` of their wallet on `side`
# ("YES"/"NO") using the Sec. 1.4 budget formulas -- no Kelly logic (handoff
# Sec. 1.5 note). The spend is capped at the wallet. Of the outlay, cost goes to
# the LMSR and fee = tau*cost is the operator's fee; both accrue to the operator
# (as for agents). Records the trade with trader id 0 and type "user".
# -----------------------------------------------------------------------------
user_trade <- function(market, side, amount, params, t = NA_integer_) {
  tau <- params$tau; b <- params$b
  m <- min(amount, market$user_wallet)          # subject to wallet
  if (m <= 0) return(invisible(FALSE))
  cost <- m / (1 + tau)                          # portion available for LMSR cost
  fee  <- m - cost
  p <- market$p
  if (side == "YES") {
    p_final <- 1 - (1 - p) * exp(-cost / b)
    if (p_final > P_MAX) p_final <- P_MAX
    delta <- b * (log(p_final / (1 - p_final)) - log(p / (1 - p)))
    market$user_y <- market$user_y + delta
    market$q_Y    <- market$q_Y + delta
  } else {
    p_final <- p * exp(-cost / b)
    if (p_final < P_MIN) p_final <- P_MIN
    delta <- b * (log((1 - p_final) / p_final) - log((1 - p) / p))
    market$user_z <- market$user_z + delta
    market$q_N    <- market$q_N + delta
  }
  if (delta <= 0) return(invisible(FALSE))
  market$user_wallet <- market$user_wallet - m
  market$operator    <- market$operator + m       # cost + fee to operator
  market$p           <- p_final
  if (isTRUE(market$record_trades)) {
    k <- market$ntr + 1L
    market$ntr <- k
    market$tr_t[k] <- t;         market$tr_trader[k] <- 0L
    market$tr_type[k] <- "user"; market$tr_is_bot[k] <- FALSE
    market$tr_side[k] <- side;   market$tr_shares[k] <- delta
    market$tr_cost[k] <- cost;   market$tr_fee[k] <- fee
    market$tr_p_before[k] <- p;  market$tr_p_after[k] <- p_final
  }
  market$volume <- market$volume + cost
  invisible(TRUE)
}

# =============================================================================
# One whole market (handoff Sec. 1.6): draw the world, run T rounds, resolve.
#
# record: "full"  -> trade log + per-round agent snapshots (for Tab 1/2)
#         "light" -> price path per round + summary stats only (for ensembles)
# audit:  when TRUE, records the money-conservation total after every turn so
#         the unit test can check the invariant step by step.
#
# user_trades: NULL for ordinary runs (ensembles/tests -> zero overhead). For the
#   Live Market tab, a list of list(round=t, side="YES"/"NO", amount=m): the user
#   spends m of their wallet at the END of round t via the Sec. 1.4 budget
#   formulas (no Kelly). Because the run is deterministic in `seed`, scheduling a
#   user trade (or the bot via params$bot_rounds) and re-running reproduces the
#   identical prefix and the correct divergent suffix -- no resumable engine
#   needed. The user is an extra account (params$user_wallet) tracked in the
#   money-conservation identity alongside agents/operator/burned.
#
# Returns a list with the drawn world (theta, A), the reference forecasts
# (p0, p*, p_static), the price trajectory, resolution P&L, and -- in full mode
# -- the trade log and snapshots. Deterministic given `seed`.
# =============================================================================
run_market <- function(params, seed = NULL, record = c("full", "light"),
                       audit = FALSE, user_trades = NULL) {
  record <- match.arg(record)
  if (is.null(seed)) seed <- params$seed
  if (!is.null(seed) && !is.na(seed)) set.seed(as.integer(seed))

  n <- params$n; Tt <- params$T; b <- params$b

  # ---- Draw the world -------------------------------------------------------
  theta <- rnorm(1, params$mu0, params$sigma0)
  A     <- as.integer(theta >= params$c)

  eta <- rnorm(1)                       # shared component (drives correlation)
  nu  <- rnorm(n)                       # idiosyncratic components

  # Per-agent signal precision. Default: homogeneous sigma_eps. With r_wp != 0,
  # rank-correlate each agent's precision with its wealth (Tab 4 Q3 extension):
  # higher |r_wp| ties being rich to seeing sharper (r_wp>0) or noisier signals.
  w <- runif(n)^(-1 / params$alpha_w)   # Pareto(alpha_w, w_min = 1) via inverse CDF
  sigma_eps_i <- rep(params$sigma_eps, n)
  if (params$r_wp != 0) {
    # Gaussian-copula rank coupling: blend wealth ranks with fresh noise, then
    # map to a spread of sigma_eps around the base value.
    z_w <- qnorm((rank(w) - 0.5) / n)
    z_s <- params$r_wp * z_w + sqrt(1 - params$r_wp^2) * rnorm(n)
    spread <- exp(0.5 * (z_s - mean(z_s)))        # log-normal multiplier, mean ~1
    sigma_eps_i <- params$sigma_eps * spread
  }

  eps <- sigma_eps_i * (sqrt(params$rho) * eta + sqrt(1 - params$rho) * nu)
  s   <- theta + eps                    # private signals

  # ---- Reference forecasts --------------------------------------------------
  p0     <- prior_forecast(params$mu0, params$sigma0, params$c)
  p_star <- omniscient_forecast(s, params$mu0, params$sigma0, params$sigma_eps,
                                params$rho, params$c)

  # ---- Assign types and initial beliefs ------------------------------------
  n_noise <- round(params$phi_noise * n)
  n_manip <- round(params$phi_manip * n)
  n_noise <- min(n_noise, n)
  n_manip <- min(n_manip, n - n_noise)
  type <- rep("informed", n)
  if (n_noise > 0) type[seq_len(n_noise)] <- "noise"
  if (n_manip > 0) type[n_noise + seq_len(n_manip)] <- "manipulator"

  p_tilde <- numeric(n)
  inf_idx <- which(type == "informed")
  if (length(inf_idx) > 0) {
    post <- informed_posterior(s[inf_idx], params$mu0, params$sigma0,
                               sigma_eps_i[inf_idx], params$c)
    p_tilde[inf_idx] <- post$p_tilde
  }
  noise_idx <- which(type == "noise")
  if (length(noise_idx) > 0) p_tilde[noise_idx] <- rbeta(length(noise_idx), 2, 2)
  manip_idx <- which(type == "manipulator")
  if (length(manip_idx) > 0) p_tilde[manip_idx] <- params$pistar
  p_tilde <- clamp_p(p_tilde)

  is_bot  <- rep(FALSE, n)
  # entered: everyone in if c_part == 0; else dormant. Manipulators always in.
  entered <- if (params$c_part > 0) rep(0L, n) else rep(1L, n)
  entered[manip_idx] <- 1L

  # ---- Optional manipulator bot (agent n+1, outside the n) ------------------
  if (isTRUE(params$bot_on) && params$B_m > 0) {
    bot_w <- params$B_m * sum(w)
    # Bot target: fixed pi*, or drawn per run (so its push direction averages out
    # across an ensemble -- the Hanson-Oprea "waking the market" test, V4/Q5).
    bot_target <- if (isTRUE(params$bot_pistar_random)) runif(1, 0.1, 0.9) else params$bot_pistar
    w        <- c(w, bot_w)
    p_tilde  <- c(p_tilde, clamp_p(bot_target))
    type     <- c(type, "manipulator")
    is_bot   <- c(is_bot, TRUE)
    entered  <- c(entered, 1L)
    sigma_eps_i <- c(sigma_eps_i, params$sigma_eps)
  }
  n_all <- length(w)

  # ---- Static (frictionless) benchmark: wealth-weighted mean belief over -----
  # informed + noise agents. Theory overlay for Tab 3; uses INITIAL beliefs.
  bench_idx <- which(type %in% c("informed", "noise"))
  p_static <- if (length(bench_idx) > 0) {
    sum(w[bench_idx] * p_tilde[bench_idx]) / sum(w[bench_idx])
  } else NA_real_

  # ---- Package agent state as a mutable environment -------------------------
  ag <- new.env(parent = emptyenv())
  ag$w       <- w
  ag$p_tilde <- p_tilde
  ag$y       <- numeric(n_all)     # YES shares held
  ag$z       <- numeric(n_all)     # NO shares held
  ag$type    <- type
  ag$is_bot  <- is_bot
  ag$entered <- entered
  p_tilde_init <- p_tilde          # keep initial beliefs (herding overwrites)

  # User account (Live Market tab). user_wallet default 0 => inert.
  user_wallet0 <- params$user_wallet
  if (is.null(user_wallet0) || is.na(user_wallet0)) user_wallet0 <- 0
  n_user_tr <- if (is.null(user_trades)) 0L else length(user_trades)

  initial_total <- sum(w) + user_wallet0   # conservation baseline (incl. bot + user)

  # ---- Market environment ---------------------------------------------------
  market <- new.env(parent = emptyenv())
  market$q_Y      <- b * pm_logit(params$p0_init)   # init (q_Y,q_N)=(b*logit(p0),0)
  market$q_N      <- 0
  market$p        <- params$p0_init
  market$operator <- 0
  market$burned   <- 0
  market$volume   <- 0
  market$user_wallet <- user_wallet0   # user's cash
  market$user_y      <- 0              # user's YES shares
  market$user_z      <- 0              # user's NO shares
  market$record_trades <- (record == "full")
  if (market$record_trades) {
    maxtr <- n_all * Tt + n_user_tr
    market$ntr        <- 0L
    market$tr_t        <- integer(maxtr)
    market$tr_trader   <- integer(maxtr)
    market$tr_type     <- character(maxtr)
    market$tr_is_bot   <- logical(maxtr)
    market$tr_side     <- character(maxtr)
    market$tr_shares   <- numeric(maxtr)
    market$tr_cost     <- numeric(maxtr)
    market$tr_fee      <- numeric(maxtr)
    market$tr_p_before <- numeric(maxtr)
    market$tr_p_after  <- numeric(maxtr)
  }

  # ---- Main loop: T rounds, agents trade in a fresh random order each round --
  price_round <- numeric(Tt)
  snapshots   <- if (record == "full") vector("list", Tt) else NULL
  audit_vec   <- if (audit) numeric(0) else NULL
  bot_idx     <- which(is_bot)

  for (t in seq_len(Tt)) {
    # Which traders act this round: all n agents, plus the bot if it is active.
    active <- seq_len(n)
    if (length(bot_idx) == 1L) {
      bot_active <- is.null(params$bot_rounds) || (t %in% params$bot_rounds)
      if (bot_active) active <- c(active, bot_idx)
    }
    order <- sample(active)                       # random permutation
    for (i in order) {
      agent_turn(i, market, ag, params, t = t)
      if (audit) audit_vec <- c(audit_vec,
                                sum(ag$w) + market$operator + market$burned +
                                  market$user_wallet)
    }
    # User interventions scheduled for this round execute after the agents.
    if (n_user_tr > 0) {
      for (ut in user_trades) {
        if (isTRUE(ut$round == t)) {
          user_trade(market, ut$side, ut$amount, params, t = t)
          if (audit) audit_vec <- c(audit_vec,
                                    sum(ag$w) + market$operator + market$burned +
                                      market$user_wallet)
        }
      }
    }
    price_round[t] <- market$p
    if (record == "full") {
      snapshots[[t]] <- list(
        t = t, p = market$p,
        w = ag$w, p_tilde = ag$p_tilde,
        y = ag$y, z = ag$z, entered = ag$entered
      )
    }
  }

  p_T <- market$p

  # ---- Resolution: pay 1 per winning share from the operator ----------------
  payout <- if (A == 1L) ag$y else ag$z          # YES pays if A, else NO pays
  ag$w   <- ag$w + payout
  market$operator <- market$operator - sum(payout)

  # User resolution (if any user account activity).
  user_payout <- if (A == 1L) market$user_y else market$user_z
  market$user_wallet <- market$user_wallet + user_payout
  market$operator    <- market$operator - user_payout

  # Per-agent P&L: final wealth minus initial wealth (bot included).
  pnl <- ag$w - w
  operator_pnl <- market$operator
  user_info <- list(
    wallet0 = user_wallet0, wallet = market$user_wallet,
    y = market$user_y, z = market$user_z,
    pnl = market$user_wallet - user_wallet0
  )

  # ---- Trade log as a data frame (full mode) --------------------------------
  trades <- NULL
  price_path <- NULL
  if (market$record_trades) {
    k <- market$ntr
    trades <- data.frame(
      t        = market$tr_t[seq_len(k)],
      trader   = market$tr_trader[seq_len(k)],
      type     = market$tr_type[seq_len(k)],
      is_bot   = market$tr_is_bot[seq_len(k)],
      side     = market$tr_side[seq_len(k)],
      shares   = market$tr_shares[seq_len(k)],
      cost     = market$tr_cost[seq_len(k)],
      fee      = market$tr_fee[seq_len(k)],
      p_before = market$tr_p_before[seq_len(k)],
      p_after  = market$tr_p_after[seq_len(k)],
      stringsAsFactors = FALSE
    )
    # Per-trade price path (for Tab 1's trade-index x-axis).
    price_path <- data.frame(
      idx    = seq_len(k),
      t      = trades$t,
      trader = trades$trader,
      type   = trades$type,
      is_bot = trades$is_bot,
      side   = trades$side,
      p      = trades$p_after
    )
  }

  # ---- Trajectory summary stats --------------------------------------------
  # Convergence time: first round t s.t. |p_s - p_T| < 0.02 for all s >= t.
  conv_tol <- 0.02
  within   <- abs(price_round - p_T) < conv_tol
  conv_time <- {
    # find the earliest t from which all subsequent rounds stay within tol
    run_ok <- rev(cumprod(rev(as.integer(within))))   # 1 while tail all within
    w_ok <- which(run_ok == 1L)
    if (length(w_ok) > 0) min(w_ok) else Tt
  }
  volatility <- sum(diff(c(params$p0_init, price_round))^2)
  volume     <- market$volume

  list(
    params   = params,
    seed     = seed,
    theta    = theta,
    A        = A,
    c        = params$c,
    p0       = p0,
    p_star   = p_star,
    p_static = p_static,
    p_T      = p_T,
    price_round   = price_round,
    price_path    = price_path,
    trades        = trades,
    snapshots     = snapshots,
    agents_final  = list(
      w = ag$w, w_init = w, p_tilde = ag$p_tilde, p_tilde_init = p_tilde_init,
      y = ag$y, z = ag$z, type = type, is_bot = is_bot, entered = ag$entered,
      pnl = pnl
    ),
    operator_pnl  = operator_pnl,
    burned        = market$burned,
    user          = user_info,
    initial_total = initial_total,
    conv_time     = conv_time,
    volatility    = volatility,
    volume        = volume,
    audit         = audit_vec
  )
}
