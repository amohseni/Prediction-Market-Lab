# CLAUDE CODE HANDOFF — Prediction Market Lab (R/Shiny)

**Status:** binding implementation spec, 2026-07-13. Design is closed; do not reopen design questions.
**Companion docs (same folder):** PREDICTION_MARKET_MODEL_PLAN.md (rationale, literature, research agenda), GUI_DESIGN.md (full GUI rationale), PROGRESS.md (maintain it), FORMALIZATION_GUIDE.md / PSEUDOCODE_CONVENTIONS.md / RSHINY_STYLE_GUIDE.md / GUI_DESIGN_PRINCIPLES.md (project conventions — follow them).
**This file alone is sufficient to build the app.** Where this file and the companions disagree, this file wins.

## 0. Instructions to the implementing agent

1. Build in the milestone order of §8. Do not start GUI work until the model core passes the §7.1 unit tests.
2. The model core must be pure functions, UI-free, in its own file(s). The same core drives the live single run, the ensembles, and the tests.
3. Maintain PROGRESS.md (Planned/Done) with every substantive change.
4. Where this spec says "tune and report," you have discretion — exercise it, then record the chosen value and evidence in PROGRESS.md. Everything else is fixed.
5. Comment for a reader who knows R but not this model (per RSHINY_STYLE_GUIDE.md function-header format).

---

## 1. Model specification (normative)

### 1.1 State space

One market. Latent state θ ∈ ℝ. Event A = 𝟙[θ ≥ c] ∈ {0,1}. Market state: (q_Y, q_N) ∈ ℝ² (shares sold), price p ∈ (0,1). Agent i ∈ {1..n}: wealth wᵢ ≥ 0, stored belief p̃ᵢ ∈ (0,1), position (y_i, z_i) = (YES shares, NO shares), type ∈ {informed, noise, manipulator}, entered_i ∈ {0,1}. Plus: bot (a manipulator outside the n), user, operator account.

### 1.2 Parameters

| Symbol | Domain | Meaning | Default |
|---|---|---|---|
| n | ℤ⁺ | number of agents | 100 |
| μ₀, σ₀ | ℝ, ℝ⁺ | prior on θ | 0, 1 |
| c | ℝ | event threshold | 0 |
| σ_ε | ℝ⁺ | signal noise SD | 1 |
| ρ | [0,1) | error correlation | 0 |
| b | ℝ⁺ | LMSR liquidity | 10 |
| τ | [0,1) | proportional fee on trade cost | 0 |
| κ | ℝ≥0 | fixed cost per trade | 0 |
| c_part | ℝ≥0 | one-time participation cost | 0 |
| α_w | (1,∞) | Pareto tail index, w_min = 1 | 2 |
| λ | (0,1] | Kelly fraction | 1 |
| φ_noise | [0,1] | noise-trader share | 0 |
| φ_manip | [0,1] | structural-manipulator share | 0 |
| π★ | (0,1) | manipulator target price | 0.8 |
| h | [0,1] | herding weight (belief adoption) | 0 |
| T | ℤ⁺ | trading rounds | 20 |
| p₀_init | (0,1) | opening price | 0.5 |
| B_m | [0,1] | bot budget as share of total agent wealth | 0.1 |
| seed, R | — | RNG seed; ensemble replications | —, 200 |

h applies to **all informed agents** (there is no separate price-learner share). Numerical guard: clamp all prices/beliefs to [P_MIN, P_MAX] = [0.001, 0.999] before any logit.

### 1.3 Beliefs (closed forms — do not numerically integrate)

logit(p) := ln(p/(1−p)); Φ = standard normal CDF.

- Prior forecast: p₀ = Φ((μ₀ − c)/σ₀).
- Signals: εᵢ = σ_ε(√ρ·η + √(1−ρ)·νᵢ); η, νᵢ ~ iid N(0,1); sᵢ = θ + εᵢ. ⟨stochastic⟩
- Informed posterior (precision-weighted, conjugate normal):
  prec = 1/σ₀² + 1/σ_ε²; μ_post,i = (μ₀/σ₀² + sᵢ/σ_ε²)/prec; σ_post = prec^(−1/2);
  initial p̃ᵢ = Φ((μ_post,i − c)/σ_post).
- Omniscient forecast: n_eff = n/(1 + (n−1)ρ); s̄ = mean(sᵢ);
  prec★ = 1/σ₀² + n_eff/σ_ε²; μ★ = (μ₀/σ₀² + n_eff·s̄/σ_ε²)/prec★; σ★ = prec★^(−1/2);
  p★ = Φ((μ★ − c)/σ★).
- Noise trader initial belief: p̃ᵢ ~ Beta(2,2). ⟨stochastic⟩
- Manipulator (structural and bot) belief: fixed at π★, never updated, ignores h, always participates. **Manipulators are ordinary agents with an exogenous frozen belief** — reuse all trading machinery.
- Herding (belief adoption), informed agents only, applied at the agent's own turn before trading:
  p̃ᵢ ← (1−h)·p̃ᵢ + h·p_current. Persistent (stored belief overwritten).

### 1.4 LMSR (all closed-form; verified numerically — see §7.1 test values)

Price: p = e^{q_Y/b}/(e^{q_Y/b} + e^{q_N/b}).

Buying YES to move price p → p′ (p′ > p):
- shares Δ_Y = b·[logit(p′) − logit(p)]
- cost = b·ln((1−p)/(1−p′))
- price after spending cost m: p′ = 1 − (1−p)·e^{−m/b}

Buying NO to move price p → p′ (p′ < p):
- shares Δ_N = b·[logit(1−p′) − logit(1−p)]
- cost = b·ln(p/p′)
- price after spending cost m: p′ = p·e^{−m/b}

Selling is modeled as buying the opposite side (agents may hold both; net at resolution). Worst-case operator loss = b·ln 2. Initialization: set (q_Y, q_N) = (b·logit(p₀_init), 0).

### 1.5 One agent turn (the core decision rule)

```
ALGORITHM: AgentTurn(i, market, params)
1  if type_i = informed and h > 0:  p̃ᵢ ← (1−h)·p̃ᵢ + h·p          # belief adoption
2  direction:
     BUY-YES  if p̃ᵢ > p·(1+τ)
     BUY-NO   if (1−p̃ᵢ) > (1−p)·(1+τ)
     else return (inside no-trade band)
3  Kelly stake (pre-trade price; fixed-odds approximation — a modeling convention):
     f★ = (p̃ᵢ − p)/(1 − p)   [YES]    or    f★ = (p − p̃ᵢ)/p   [NO]
     m★ = λ · wᵢ · f★                       # max total outlay incl. fee
     m_cost = m★/(1+τ)                      # portion available for LMSR cost
4  price caps:
     p_target = p̃ᵢ/(1+τ)                [YES]   or   1 − (1−p̃ᵢ)/(1+τ)   [NO]
     p_reach  = budget formula of §1.4 with m = m_cost
     p_final  = min(p_target, p_reach)  [YES]   or   max(...)            [NO]
5  planned trade: shares Δ, cost, fee = τ·cost, outlay = cost + fee
6  participation gate (only if entered_i = 0):
     E_profit = Δ·p̃ᵢ − outlay   [YES]   or   Δ·(1−p̃ᵢ) − outlay   [NO]
     if E_profit < c_part: return (stays dormant; re-evaluated every turn)
     else: entered_i ← 1;  wᵢ ← wᵢ − c_part          # c_part burned (tracked)
7  fixed-cost gate (only if κ > 0): if E_profit < κ: return
     else wᵢ ← wᵢ − κ; operator ← operator + κ
8  execute: wᵢ ← wᵢ − outlay; operator ← operator + fee (τ·cost) + cost;
     positions and (q_Y or q_N) updated; p ← p_final
9  RECORD trade event (trader id, type, side, Δ, cost, fee, p_before, p_after)
```

Notes: dormant agents (entered = 0) re-check the gate at every turn — this is the Hanson–Oprea channel (manipulation-widened edges pull them in); once entered, c_part is sunk forever. Manipulators and the bot skip lines 1 and 6 (always entered). The user's trades are raw amounts: spend m on YES or NO via the §1.4 budget formulas (no Kelly logic), subject to wallet.

### 1.6 Market run

```
ALGORITHM: RunMarket(params, seed)
INITIALIZE: draw θ ~ N(μ₀,σ₀²); η; νᵢ; wealths wᵢ ~ Pareto(α_w, w_min=1);   ⟨stochastic⟩
    types by shares (φ_noise, φ_manip, rest informed); beliefs per §1.3;
    market at p₀_init; entered_i ← 1 if c_part = 0 else 0 (manipulators always 1);
    bot wealth = B_m · Σwᵢ (if bot enabled)
MAIN LOOP (t = 1..T, sequential):
    order ← RandomPermutation(agents ∪ {bot if on})                        ⟨stochastic⟩
    for each trader in order: AgentTurn(trader)
    RECORD: p_t, per-agent state snapshot (for anatomy/animation)
RESOLUTION: A ← 𝟙[θ ≥ c]; pay 1 per YES share if A, 1 per NO share if ¬A (from operator);
    RECORD: final price p_T, A, P&L by trader and type, operator P&L
RETURN: trajectory (trade-level), snapshots, resolution summary
```

Money conservation (test invariant): at every step, Σᵢwᵢ + user wallet + bot wealth + operator + Σburned c_part = initial total. After resolution the identity still holds (payouts move operator → traders); operator ≥ −b·ln 2 always.

### 1.7 Ensembles and metrics

`RunEnsemble(params, R, seed)`: R independent RunMarket calls (vary θ, η, ν, wealth, beliefs, order). Return per-run (p_T, A, p₀, p★, trajectory stats). Metrics computed from the ensemble:

- Mean Brier B̄ = mean[(p_T − A)²]; also B̄_prior (p₀), B̄_omn (p★).
- **AE = (B̄_prior − B̄)/(B̄_prior − B̄_omn)**.
- Murphy decomposition, K = 10 equal-width forecast bins: with bin means f_k, outcome rates ō_k, counts n_k, grand mean ō:
  REL = Σn_k(f_k − ō_k)²/N; RES = Σn_k(ō_k − ō)²/N; UNC = ō(1−ō). Check B̄ ≈ REL − RES + UNC (exact up to within-bin variance; report gap).
- Calibration slope/intercept: glm(A ~ logit(p_T), binomial).
- Log score: mean[−(A·ln p_T + (1−A)·ln(1−p_T))] (clamped).
- Bias: mean(p_T) − mean(A). Favorite–longshot: ō_k vs f_k at tail bins, computed conditional on θ regimes when sweeping c.
- Convergence time: first t with |p_s − p_T| < 0.02 ∀ s ≥ t. Volatility: Σ(p_t − p_{t−1})². Volume: Σ|cost|.
- Static benchmark (frictionless analytic check, vectorized, no market loop): p_static = Σwᵢp̃ᵢ/Σwᵢ over informed+noise agents; its ensemble Brier is the theory overlay for Tab 3.

---

## 2. File structure (per RSHINY_STYLE_GUIDE.md, ≥600 lines)

```
app/
  global.R        # libraries, constants (colors, P_MIN/P_MAX, defaults), sourcing
  ui.R            # page layout only
  server.R        # top-level server; wires modules
  R/
    core_model.R      # §1: beliefs, LMSR, AgentTurn, RunMarket  (pure, no Shiny)
    core_ensemble.R   # RunEnsemble, sweeps, metrics, static benchmark, cache
    presets.R         # preset parameter vectors (§5)
    theme.R           # ggplot theme + color constants (§6)
    mod_live.R        # Tab 1 module (incl. animation engine)
    mod_anatomy.R     # Tab 2 module
    mod_reliability.R # Tab 3 module
    mod_interactions.R# Tab 4 module
    mod_guide.R       # Tab 5 (static content; glossary from plan §14)
  tests/testthat/     # §7.1 unit tests
  scripts/validate.R  # §7.2 emergent-behavior validation, writes VALIDATION.md
```

ggplot2 throughout; one theme object applied everywhere. No magic numbers — named constants.

---

## 3. Page layout (binding; rationale in GUI_DESIGN.md)

Title bar: **Prediction Market Lab** — "When do markets know things? Watch one work — and find out when it fails."
Below: three equal text columns (copy in GUI_DESIGN.md §2): The model / The mechanism / The science.
Below: sidebar (≈1/4 width) + main panel (≈3/4) with 5 tabs: **Live Market · Run Anatomy · Reliability · Interactions · Guide**.

**Sidebar:** preset dropdown (§5) + Reset button + stale badge; then 5 accordion groups (one open at a time): Information (n, σ_ε, ρ, μ₀, σ₀, c) · Market (b, p₀_init, T) · Traders (α_w, λ, φ_noise, φ_manip, π★, h) · Frictions (τ, κ, c_part) · Simulation (seed, R). Every control: slider + numeric readout + one-line caption (exact caption copy: GUI_DESIGN.md §3.2). Group headers expand to a 2–4 sentence details paragraph. The bot is NOT in the sidebar (it is an in-tab intervention).

---

## 4. Tabs (binding content; layout details in GUI_DESIGN.md §4)

**Tab 1 — Live Market.**
- Control strip: Run / Pause / Step / New market / speed / scrub slider.
- Main plot: x = trade index, y = price. Ink price path; gray dotted h-line p₀ (labeled "prior"); blue dashed h-line p★ ("best possible"); resolution marker at 0/1 with vertical line. **Path color modes (toggle):** default *Highlight manipulation* — red segments = trades by bot or structural manipulators; orange = user trades; toggle *Color by trader* — segments tinted by mover type (informed/noise/manipulator+bot/user). First render carries small text labels on each reference line.
- Intervention strip: manipulator-bot card (on/off toggle usable mid-run, B_m slider, π★ slider, pulsing red dot while on) + user-wallet card (balance, position, Buy YES / Buy NO with amount).
- Agent swarm below (animated with path): dot per agent, x = p̃ᵢ, y = net position, size = wᵢ, color = type, hollow = not entered.
- Event log (collapsible): full log when n·T ≤ 2,000, else round summaries.
- Post-resolution card: outcome, final price, run Brier vs prior Brier, P&L table by type incl. bot & user, link → Run Anatomy.
- **Animation engine: precompute-and-replay with intervention injection.** Simulate forward in round chunks into a trajectory store; animate reveal via invalidateLater; scrub indexes the store; on any user/bot intervention, truncate the store at the current trade and resimulate forward. Swarm: try per-trade frames, fall back to per-round if it stutters (record choice in PROGRESS.md).

**Tab 2 — Run Anatomy** (diagnostics of the current run): |p_t − p★| per round (log y); price vs wealth-weighted mean belief per round; participation bars per round (traded / in no-trade band / never entered); belief-migration lines (all p̃ᵢ over time; shows cascades when h > 0, friendly empty-state message when h = 0); volume per round.

**Tab 3 — Reliability** (1-D sweeps): setup strip (sweep parameter — any sidebar param; range; #points; metric checkboxes Brier/AE/log/bias/REL/RES; R; Run button with progress + cancel). Main plot: metric vs parameter, mean ± 95% CI ribbon; gray line B̄_prior, blue line B̄_omn, dashed theory overlay = static-benchmark Brier where computable. Sub-panels: Murphy stack, calibration curve at selected points, favorite–longshot (activates when sweeping c). **Initial state: precomputed n_eff-ceiling exhibit** (Brier vs n ∈ {25..800} at ρ ∈ {0, .1, .3, .5}) — ship as bundled .rds so the tab never opens blank. CSV/PNG export.

**Tab 4 — Interactions** (2-D maps): curated-question radios (each sets both axes + metric): (1) ρ × α_w → AE; (2) B_m × τ → |E p_T − p★| with frontier contour; (3) τ × wealth–precision correlation → Brier (needs a small extension: assign σ_ε,i rank-correlated with wᵢ; add hidden parameter r_wp ∈ [−1,1], default 0, exposed only here); (4) h × B_m → post-bot price persistence (bot on for rounds 3–8 only; metric = |p_T − p★|); (5) friction ranking — grouped bar chart of the Hanson–Oprea effect (Brier bot-on minus bot-off) under c_part-only vs κ-only vs τ-only. Free x/y/metric choice below the radios. Heatmap: viridis fill, contour lines; click a cell → 1-D slice renders beneath. Progress + cancel + export as Tab 3.

**Tab 5 — Guide** (static): How it works (readable version of plan §1); Glossary (plan §14 verbatim, searchable via DT or simple filter); References (plan §13).

**Cross-cutting:** one reactive params state consumed by all tabs; any sidebar change flips a stale badge on every computed artifact (plots dim + "settings changed — rerun"; never auto-recompute sweeps); ensemble results cached keyed by digest::digest(list(params, sweep_spec, R, seed)); app loads on Textbook preset with one precomputed run in Tab 1.

---

## 5. Presets (starting values — tune to make each lesson vivid; record final values)

| Preset | Deltas from defaults | Lesson |
|---|---|---|
| Textbook market | none | price → p★ |
| Echo chamber | ρ = 0.5 | n_eff ceiling |
| Whale market | α_w = 1.2 | wealth-weighted opinion |
| Toll road | τ = 0.05, κ = 0.1 | no-trade bands, stale price |
| Sleepy market | c_part = 0.2, σ_ε = 1.5 | thin participation; bot wakes the market (Hanson–Oprea) |
| Cascade | h = 0.4, ρ = 0.3, bot scripted on rounds 3–8 (B_m = 0.1, π★ = 0.9) | manipulation outlives the manipulator |

---

## 6. Visual language (one semantics everywhere)

| Element | Color |
|---|---|
| price path | ink `#1a1a1a` solid thick |
| prior p₀ / prior-Brier | gray `#9e9e9e` dotted |
| omniscient p★ / omn-Brier | blue `#2b6cb0` dashed |
| manipulation (bot + structural) | red `#c0392b` |
| user | orange `#e67e22` |
| CIs | gray ribbon, alpha 0.25 |
| heatmap fills | viridis |

White backgrounds; labeled axes always; legends where needed; theme defined once in theme.R.

---

## 7. Testing and validation

### 7.1 Unit tests (testthat; exact, must pass)

1. LMSR consistency: for random (b, p, p′): closed-form cost (§1.4) == C(q′) − C(q) to 1e-9; budget-formula price reached matches; shares formula consistent. Reference values (independently verified): b = 7, state (q_Y, q_N) = (4.2, −2.0) ⇒ p = 0.7080050; YES to p′ = 0.85 costs 4.6627106; NO to p′ = 0.45 costs 3.1724246; spending m = 3 on YES from p reaches p′ = 0.8097830.
2. Worst-case operator loss ≤ b·ln 2 (drive price to extremes; equality in the limit).
3. Posterior formulas: agent posterior and omniscient posterior match brute-force numeric Bayes on a grid to 1e-6; n_eff matches 1ᵀΣ1 computation for the equicorrelated Σ (n = 50, ρ = 0.3 ⇒ n_eff = 3.1847134).
4. Kelly stake: f★ = (p̃−p)/(1−p) maximizes E[log wealth] (grid check).
5. Money conservation invariant (§1.6) at every step of a random run with all frictions on, to 1e-8; operator ≥ −b·ln 2 post-resolution.
6. Determinism: same seed ⇒ identical trajectory.
7. Murphy identity: B̄ = REL − RES + UNC + within-bin variance term; verify decomposition arithmetic on synthetic forecasts.

### 7.2 Emergent validation (scripts/validate.R → VALIDATION.md; qualitative, report evidence)

- V1 wealth-weighting: frictionless defaults, T = 50, R = 500: corr(p_T, p_static) > 0.95 and mean bias ≈ 0. [Revised 2026-07-13: the original mean|p_T − p_static| < 0.03 target was retired after implementation — that gap is ~0.067 and irreducible (flat across T = 50/80/120 and n = 50..800, bias ≈ 0), i.e. realization scatter of one market's price around the wealth-weighted fixed point, not a modeling error. Pass on correlation + zero bias.]
- V2 n_eff ceiling: B̄(n) flattens by n ≈ 1/ρ·(a few multiples) for ρ = 0.3 while ρ = 0 keeps improving; overlay analytic B̄_omn(n).
- V3 fees: B̄ increasing in τ; participation collapse visible at high τ.
- V4 Hanson–Oprea: with c_part = 0.2 and bot with target π★ ~ U(0.1, 0.9) per run: B̄(bot on) < B̄(bot off). Find and report a parameter region where this holds and one where τ reverses it.
- V5 favorite–longshot: sweep c to extreme base rates with φ_noise = 0.3; tail miscalibration in the classic direction.
- V6 herding: Cascade preset: price persistently displaced after bot exit vs h = 0 control.

---

## 8. Build order (milestones; complete + verify each before the next)

1. **core_model.R + unit tests 7.1.** Deliverable: all tests green.
2. **core_ensemble.R + validate.R (V1–V3).** Deliverable: VALIDATION.md with figures.
3. **Shell app:** layout, sidebar, presets, theme, empty tabs. Loads < 3 s.
4. **Tab 1 Live Market** incl. animation engine, bot, user wallet, color modes, post-resolution card.
5. **Tab 2 Anatomy.**
6. **Tab 3 Reliability** incl. cache, theory overlay, bundled initial exhibit.
7. **Tab 4 Interactions** (curated questions incl. r_wp extension and friction-ranking bars) + V4–V6 validation.
8. **Tab 5 Guide + polish:** captions, tooltips, exports, stale badges, empty states, performance pass.

## 9. Pitfalls (learned/anticipated — do not rediscover these)

- Clamp before every logit/log; never let p hit 0/1 (P_MIN/P_MAX).
- Kelly at fixed pre-trade price is a stated convention, not a bug; do not "fix" it into an optimization against the cost function.
- c_part is burned; κ and τ go to operator — the conservation test encodes this; keep it that way.
- Manipulators = frozen-belief agents. Do not write a second trading code path for them.
- Never auto-recompute ensembles on slider drag or tab switch (stale badge + explicit rerun only); debounce sliders driving the single run.
- Dormant agents re-check entry every turn; entry is one-way. Getting this wrong silently kills V4.
- Pre-2022-style AMM ≠ order book: no bid/ask anywhere in v1 language or plots.
- Vectorize ensemble runs (no per-trade R loops inside R replications where avoidable); target: default sweep point (R = 200, n = 100, T = 20) in ≲ 2 s.
