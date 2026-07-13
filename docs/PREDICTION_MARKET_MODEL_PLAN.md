# Prediction Market Reliability: A Minimal Model — Design Document

**Stage:** Formalization (draft v0.3 — design decisions of 2026-07-13 integrated; see §11). Per project workflow: no pseudocode until this is approved.

**Goal.** Build the simplest possible model of a prediction market that does two jobs. First, a *pedagogical* job: let a user watch, trade by trade, how a market price forms from individual decisions — so that "the market aggregates information" stops being a slogan and becomes a mechanism you can see. Second, a *research* job: compute the market's expected accuracy across the whole space of conditions — population size, signal quality, fees, wealth inequality, manipulation — and so map out precisely when prediction markets are reliable and when they fail.

Every technical term is explained when it first appears and collected in the **Index of terms** (§14).

---

## 1. The baseline model

### 1.1 The world and what agents know

There is a hidden quantity θ (theta) — think of it as the true state of the world, e.g., the actual vote share a candidate will get. Nobody observes θ directly. Everyone starts with the same **prior** — the probability distribution you'd assign before seeing any evidence. Here the prior is a normal (bell-curve) distribution: θ ~ N(μ₀, σ₀²), centered at μ₀ with spread σ₀.

The market trades a contract on a yes/no question about θ: does θ exceed a threshold c? Formally, the event is A = "θ ≥ c", and the contract pays $1 if A happens and $0 otherwise. This is a **binary contract**, the standard instrument on real prediction markets ("Will X win?"). Its price, if the market works, should equal the probability of A.

*Design decision:* the traded question must be binary (or a family of binary thresholds) because our accuracy measures — the Brier score and calibration, defined in §4 — are built for probability forecasts of yes/no events. A market directly on the value of θ (a "continuous contract") is a possible extension, but it requires a different scoring apparatus (the CRPS — see index) and is deferred.

Each of the n agents receives a **private signal**: a noisy observation of the truth,

  sᵢ = θ + εᵢ.

The noise terms εᵢ are correlated across agents. We use the simplest correlation structure, **equicorrelated noise**: every pair of agents has the same error correlation ρ (rho). Concretely, each agent's error is a mix of two pieces:

  εᵢ = σ_ε (√ρ · η + √(1−ρ) · νᵢ),

where η is a **common error** — a mistake everyone shares, such as a misleading poll, a media narrative, or a methodological bias — and νᵢ is agent i's own idiosyncratic error. The parameter ρ is the fraction of error variance that is shared. ρ = 0 means fully independent errors; ρ near 1 means everyone is wrong in the same way.

Because the prior and the signals are both normal, each agent's **posterior** — their updated belief after seeing their signal, computed by Bayes' rule — is again normal, in closed form. (This convenient closure property is called **conjugacy**.) Agent i's belief that the event happens is then

  pᵢ = Φ((μᵢ,post − c) / σᵢ,post),

where Φ is the standard normal cumulative distribution function. In words: take your updated estimate of θ, ask how many standard deviations it sits above the threshold, and convert that to a probability.

**Two reference forecasts, both computable on paper:**

1. **Prior forecast** p₀ = Φ((μ₀ − c)/σ₀): what anyone could say with no market and no signals. Any market worth having must beat this.
2. **Omniscient forecast** p★: the posterior probability of A if you could see *all n signals at once*. This is the best any aggregation method could possibly do with the available information. Under equicorrelated noise, the average signal s̄ carries all the information (it is a **sufficient statistic** — a summary that loses nothing), and n correlated signals are worth exactly

  **n_eff = n / (1 + (n−1)ρ)**

 independent signals. n_eff is the **effective sample size**. The crucial consequence: as n → ∞, n_eff → 1/ρ. With ρ = 0.1, a million traders carry at most as much information as 10 independent ones. **Correlation puts a hard ceiling on what any market can know**, and this one formula is the analytic backbone of every correlated-error result in the model.

These two references bracket the market: the interesting question is never "is the market accurate?" but "how much of the gap between the prior and the omniscient forecast does the market close?" (made precise as *aggregation efficiency* in §4). A market can aggregate perfectly and still be inaccurate, simply because high ρ meant there was little to aggregate.

### 1.2 The market mechanism

Real markets match buyers and sellers. Modeling that matching machinery (an **order book**: the list of standing offers to buy and sell at various prices, used by Kalshi and today's Polymarket) is heavy. For v1 we instead use the cleanest theoretical mechanism, Robin Hanson's **LMSR** (logarithmic market scoring rule) — an **automated market maker**: an algorithm that always quotes a price and takes the other side of any trade.

How LMSR works: the market maker tracks how many YES and NO shares it has sold (q_Y and q_N) and charges according to a cost function

  C(q) = b · ln(e^{q_Y/b} + e^{q_N/b}),

so a trade's cost is the change in C. The instantaneous price of YES is

  p = e^{q_Y/b} / (e^{q_Y/b} + e^{q_N/b}),

which always lies strictly between 0 and 1 and behaves like a probability. Three properties make LMSR ideal for a minimal model:

- **One liquidity parameter, b.** Liquidity is how much money it takes to move the price. Larger b = deeper market = harder to move. Concretely, the **price impact** of buying one share is dp/dq = p(1−p)/b.
- **Bounded subsidy.** The market maker can lose money — that loss is the subsidy that pays for price discovery — but its worst-case loss is exactly b·ln 2. Someone must pay this; that is itself a teaching point (§7).
- **Always open.** There is always a quoted price; no waiting for a counterparty.

An order book (a **CDA**, continuous double auction, implemented as a **CLOB**) is deferred to v2. What would actually change if we switched, in rough order of importance:

1. **Liquidity becomes endogenous — and can flee.** In LMSR, depth is a constant b that someone subsidizes. In an order book, depth is whatever traders choose to post, so it thins exactly when uncertainty spikes — the moments accuracy matters most. Every result in §6 that holds b fixed becomes a moving target.
2. **A bid–ask spread emerges from adverse selection.** (**Adverse selection:** trading against a counterparty who knows more than you.) Market makers widen their quotes to protect themselves from better-informed traders — the Glosten–Milgrom mechanism — so the **bid–ask spread** (the gap between the best standing buy and sell offers) becomes an observable measure of how much private information the market suspects is in play. LMSR has zero spread by construction.
3. **Manipulation economics change.** Against LMSR, a manipulator always has a counterparty at posted prices, so the cost of distortion is deterministic and calculable. Against a book, they must eat through posted orders (thin books are cheap to capture) and gain new tactics, like **spoofing** — posting orders they intend to cancel, to fake supply or demand.
4. **Volume needs a reason to exist.** A pure order book among rational traders faces the Milgrom–Stokey **no-trade theorem**: rational agents shouldn't bet against each other on a common-value question, since someone offering you a bet is evidence they know something you don't. Real books run on noise traders, hedgers, and paid market makers; LMSR's subsidy sidesteps the problem.
5. **Best responses become strategic.** Limit vs market orders, order splitting, queue position, timing games — the agents' trading rule becomes a much richer (and harder to defend) object.

Bottom line: the information-theoretic results (the n_eff ceiling, wealth-weighted aggregation, correlation effects) should survive the switch; the friction and manipulation quantities — frontier locations, robustness curves, optimal liquidity — could shift meaningfully. That is exactly why the comparison is worth doing eventually, and why v1 conclusions about frictions should be stated as LMSR-conditional.

**Transaction costs.** We add a proportional fee τ (a percentage of each trade's value) and optionally a fixed cost κ per trade. Either creates a **no-trade band**: an agent only trades when their belief differs from the price by more than the cost of trading. No-trade bands are the mechanism by which fees cause **stale prices** — prices that stop tracking information because updating them is no longer worth anyone's while.

### 1.3 The agents

**Wealth.** Each agent starts with wealth drawn from a **Pareto distribution** — the standard heavy-tailed model of wealth, in which a few agents are far richer than the rest. Its tail index α_w controls inequality: *lower* α_w means *heavier* tail, i.e., more inequality. Inequality matters because, as we'll see, the market price is effectively a wealth-weighted average of beliefs — rich agents' opinions count for more.

**Betting behavior.** Agents have logarithmic utility, which implies they bet according to the **Kelly criterion**: stake the fraction of your bankroll that maximizes the expected logarithm of wealth (equivalently, your long-run growth rate). For a binary contract priced at p when you believe pᵢ, the Kelly stake is the fraction

  f★ = (pᵢ − p) / (1 − p)

of bankroll on YES when pᵢ > p (symmetric for NO). We generalize to **fractional Kelly**: stake only a fraction λ ∈ (0,1] of the full Kelly amount. λ is a one-parameter knob for caution — λ = 1 is aggressive full Kelly; small λ is timid. (Fractional Kelly also turns out to matter for survival; see §5, item 7.)

**Trading rule.** When it is an agent's turn, they trade against the LMSR until one of three things stops them: the price reaches their belief pᵢ; their Kelly bankroll limit binds; or fees have eaten the remaining edge (they hit the no-trade band).

**Agent types** (population shares are parameters):

- *Informed traders:* believe their Bayesian posterior, as in §1.1.
- *Noise traders:* hold beliefs unrelated to the truth (drawn from, say, a Beta distribution). They lose money on average — and thereby subsidize the informed. This is the classic logic (Kyle; Grossman–Stiglitz) of why informed trading is profitable at all.
- *Manipulators:* ignore their information and trade toward a target price π★, with a budget equal to a share B_m of total market wealth. They model anyone who wants the price to *say* something — a campaign, a promoter, a saboteur.
- *Price-learners (the herding channel):* agents who partly absorb the market's opinion instead of relying on their own analysis. The weight h ∈ [0,1] is how much they lean on the current price: h = 0 is a pure private thinker, h = 1 a pure imitator. The specification choice matters more than the parameter — there are two variants with very different consequences:
  - *Transient blend:* at each trade the agent acts on the blend (1−h)·pᵢ + h·p_t but keeps their stored belief pᵢ intact. This variant is nearly harmless. The market's resting point is unchanged: if everyone trades toward their blend, the fixed-point condition p = (1−h)·p̄_w + h·p still solves to p = p̄_w, the wealth-weighted average of *private* beliefs. The damage is purely dynamic — each trade closes only a (1−h) fraction of the belief–price gap, so convergence slows, and under finite T, fees, or participation costs the price stalls nearer its starting point (**anchoring** to p₀_init).
  - *Belief adoption (recommended):* the agent's stored belief itself migrates toward the price — pᵢ ← (1−h)·pᵢ + h·p_t whenever they observe the market. Now the price rewrites the very beliefs that feed it. This creates genuine path dependence: hold the price at a distorted level for a while and the surrounding beliefs migrate to it, so the distortion outlives the distorter — a true **information cascade** (the crowd following the crowd until private information stops entering the price), here with an explicit market mechanism underneath it.

  (An agent who updates on the price *rationally* — inferring what other traders must know, and discounting the portion of the price owed to imitation — is a different, well-behaved creature; naive weighting is what generates cascades.)

  **What hangs on the herding channel.** Without it (h = 0 for everyone), this market is unreasonably well-behaved: manipulation is always self-defeating — the manipulator merely pays informed traders to correct the price, which returns to the wealth-weighted belief average — and fees do nothing worse than slow convergence. The manipulation-robustness frontier (§6, item 2) and manufactured cascades (§6, item 4) both require h > 0, and without it the pedagogical story is one-sidedly pro-market. Herding also interacts with correlation: high ρ means fewer independent private checks against a runaway price, so cascades should trigger at lower h. Decision (confirmed 2026-07-13): included in v1, belief-adoption variant, default h = 0 (off).

**Participation margin (confirmed v1 feature).** Agents trade only if their expected gain exceeds a participation cost c_part — the effort of paying attention. This margin sounds like a detail but is load-bearing: the celebrated result that manipulators can *improve* market accuracy (§5, item 4) works entirely through it. Manipulation distorts the price; a distorted price means bigger profit opportunities; bigger opportunities pull marginal informed traders into the market; their trading adds information. Without a participation margin, the model is structurally incapable of producing this effect — manipulation would just be noise the market absorbs. How c_part differs formally from the transaction costs τ and κ is spelled out next, in §1.4.

### 1.4 Three frictions, three distinct mechanisms

The three cost parameters — proportional fee τ, fixed per-trade cost κ, and participation cost c_part — all make trading costly, but they are *not* formally interchangeable. They act on different margins, at different information sets, and produce different aggregation failures. (**Intensive vs extensive margin:** whether a cost changes *how much* of an action is taken, versus *whether* it is taken at all.)

- **Proportional fee τ — intensive margin.** The fee enters the per-unit payoff (buying YES effectively costs p(1+τ)), so the agent's usable edge shrinks and they stop trading *short* of their belief. Every signal still enters the price, but attenuated. Aggregate signature: **shrinkage** — the price is systematically pulled toward its starting point.
- **Fixed cost κ — extensive margin per trade, evaluated ex post.** Seeing the current price, the agent asks whether the gap is worth κ; once they trade, κ is sunk and the trade size is undistorted. Signals enter *in full* or not at all. Aggregate signature: **censoring** — edges smaller than the no-trade band never register.
- **Participation cost c_part — extensive margin per market, evaluated ex ante.** *Before* seeing any prices, the agent asks whether the *expected* profit from paying attention to this market justifies the effort. Aggregate signature: **sample selection** — the market aggregates only the signals of those who chose to show up.

The ex-ante timing is the crucial difference, and it answers a natural question: **can transaction costs alone produce the Hanson–Oprea effect** (manipulation improving accuracy by attracting informed trading)? *Partially, but the effect taxes itself.* A κ- or τ-induced no-trade band does hold information dormant, and manipulation that pushes the price outside a dormant trader's band activates them — a per-trade version of the attraction channel. But this version is self-taxing three ways: the manipulation must be large enough to clear the band; the activated traders correct the price only back to the *edges* of their bands, not to their beliefs; and the fee is levied on the corrective trades themselves. Only c_part delivers the effect cleanly, because its threshold responds to *anticipated* profit — manipulation raises the ex-ante variance of mispricing, hence the expected returns to attention, hence entry — and, once in, entrants trade frictionlessly to their posteriors. This yields a testable conjecture, added to §6 as item 7: the strength of the Hanson–Oprea effect is ordered **c_part > κ > τ**, and τ can reverse its sign. The margins also compound: τ and κ lower the expected gains against which c_part is weighed, so each friction raises the others' effective hurdles.

(As noted in §3, c_part also serves as the reduced form of costly information acquisition — the Grossman–Stiglitz margin: it prices "becoming informed and showing up," not merely "showing up.")

### 1.5 Timing

- The market opens at price p₀_init (see §7 for the choice).
- Trading runs for T rounds. Each round, agents act one at a time in uniform-random order (asynchronous, random sequential updating — matching project conventions).
- After round T, the event resolves (A is realized given θ), contracts pay out, wealth updates.
- *(Deferred — out of scope for v1.)* A repeated-markets mode — M successive markets with wealth carried over from one to the next — is where **market selection** lives: the hypothesis that markets self-improve because accurate traders get richer and thus more influential, while the inaccurate go broke. Interesting, but cut by decision (§11); the dependent material in §4, §5, and §6 is marked accordingly.

### 1.6 Theoretical anchor

In the frictionless case — full Kelly (λ = 1), no fees, no herding, no manipulators — theory tells us exactly where the price must settle: at (approximately) the **wealth-weighted average of the traders' beliefs**. This is the Beygelzimer–Langford–Pennock result: a market of Kelly bettors behaves, in aggregate, like a single Bayesian learner whose belief is the wealth-weighted pool of individual beliefs. It is the model's primary validation target: the simulation must reproduce it before any other output is trusted.

(The related benchmark concept from economics is the **rational expectations equilibrium**, or REE: a price that already reflects all the traders' information, so that no one can profit from what they privately know. The omniscient forecast p★ of §1.1 is our REE-style ideal.)

---

## 2. Parameters

| Symbol | Domain | Interpretation | Default |
|--------|--------|----------------|---------|
| n | ℤ⁺ | Number of agents | 100 |
| μ₀, σ₀ | ℝ, ℝ⁺ | Prior mean and SD of θ | 0, 1 |
| c | ℝ | Event threshold (controls the base rate of A) | 0 |
| σ_ε | ℝ⁺ | Signal noise SD | 1 |
| ρ | [0,1) | Error correlation between agents | 0 |
| b | ℝ⁺ | LMSR liquidity | 10 |
| τ | [0,1) | Proportional fee | 0 |
| κ | ℝ≥0 | Fixed cost per trade | 0 |
| c_part | ℝ≥0 | Participation cost | 0 |
| α_w | (1,∞) | Pareto wealth-tail index (higher = less inequality) | 2 |
| λ | (0,1] | Kelly fraction | 1 |
| φ_noise | [0,1] | Share of noise traders | 0 |
| φ_manip, B_m, π★ | [0,1]², [0,1] | Manipulator share, budget share, target price | 0, 0, — |
| h | [0,1] | Herding weight on price | 0 |
| T | ℤ⁺ | Trading rounds | 20 |
| p₀_init | (0,1) | Opening price | 0.5 |

Structural parameters vs initial conditions: everything except p₀_init is structural (fixed across runs); p₀_init and the realized draws (θ, η, ν, wealth) are initial conditions or per-run shocks.

---

## 3. What determines reliability — the full inventory

Every factor that plausibly affects market accuracy, grouped in four blocks, each mapped to a parameter above.

**A. Information environment**

1. Population size n — more signals, but see item 3.
2. Signal precision σ_ε — how good each trader's evidence is.
3. **Error correlation ρ** — the most important and most neglected factor. It caps total information at n_eff = 1/ρ, no matter how many traders show up.
4. Prior informativeness σ₀ and the base rate (via c). Markets on rare events — extreme base rates — are where reliability is weakest: thin trading and longshot territory (§4, item 5).
5. Heterogeneous precision (extension): some agents are experts (small σ_ε,i), some dabblers.
6. Endogenous information acquisition (extension): agents pay to acquire or sharpen signals. This is the **Grossman–Stiglitz** margin — the classic paradox that if prices were perfectly informative, nobody would bother gathering the costly information the prices reflect. Folded into c_part for v1.

**B. Market microstructure** (the mechanics of how trading happens)

7. Liquidity b. Too low: the price is volatile and can be shoved around for pennies. Too high: the price is sluggish — no individual has the budget to move it to where their information says it should go.
8. Transaction costs τ, κ — no-trade bands, stale prices, and screening of who bothers to participate.
9. Mechanism: LMSR vs order book (v2 comparison).
10. Time horizon T — are there enough rounds to converge?
11. Opening price p₀_init — matters only when traders herd (h > 0), in which case it can anchor the market.
12. Out of scope for v1: ambiguity in resolution criteria, settlement risk, the opportunity cost of capital locked in positions, platform fee structures.

**C. Trader population**

13. Wealth inequality α_w — since the price is wealth-weighted, inequality concentrates effective belief mass in few hands.
14. Wealth–accuracy correlation — does money sit with the well-informed? (Would evolve endogenously in the deferred repeated-markets mode; in v1 it is a static property of the wealth draw.)
15. Risk attitude λ.
16. Noise-trader share φ_noise — they subsidize the informed but add variance.
17. Manipulators: share φ_manip, budget B_m, target π★.
18. Herding weight h.
19. Participation cost c_part — selection into trading.

**D. Feedback from market to world (explicitly out of scope for v1)**

20. Self-referential markets, where the price influences the event itself (e.g., an electability market shaping the primary it forecasts). Noted; not modeled.

---

## 4. What we measure

All quantities below are standard in the forecasting and market-microstructure literatures. Macro (market-level) observables, per run and averaged over ensembles of runs:

1. **Brier score:** B = (p_T − A)², the squared error of the final price as a probability forecast (0 is perfect; 0.25 is what always-saying-50% earns). Named for Glenn Brier (1950) — note the spelling. Our headline accuracy metric is the ensemble mean Brier score.
2. **Murphy decomposition.** The ensemble Brier score splits exactly into three parts: **B = REL − RES + UNC**.
   - **Reliability (REL):** calibration error. When the market says 70%, does the event happen 70% of the time? Zero is perfect; this is the term manipulation and herding inflate.
   - **Resolution (RES):** discrimination. Do the market's forecasts *differ* between events that happen and events that don't? Higher is better; a market that always says the base rate has zero resolution.
   - **Uncertainty (UNC):** the variance of the outcome itself — how hard the question is. Fixed by (μ₀, σ₀, c), untouched by anything the market does. So REL and RES carry all the model-driven signal.
3. **Calibration curve** — plot of observed frequency against forecast probability — plus its slope and intercept from a logistic regression of outcomes on forecasts. Slope < 1 means overconfident forecasts; intercept ≠ 0 means systematic bias.
4. **Log score:** −ln(probability assigned to what happened). Reported alongside Brier because its unbounded penalty near 0 and 1 makes it far more sensitive to how the market handles longshots.
5. **Bias and the favorite–longshot pattern.** Bias is E[p_T] − E[A]. The **favorite–longshot bias** is the classic empirical deviation (documented by Wolfers–Zitzewitz and Snowberg–Wolfers): markets systematically overprice low-probability events and underprice near-certainties. Measured as E[A | p_T] vs p_T at the tails.
6. **Aggregation efficiency (AE)** — the headline *relative* metric:

  **AE = (B_prior − B_market) / (B_prior − B_omniscient)**, taking values in (−∞, 1].

 In words: of the Brier improvement that was *achievable* (prior → omniscient), what fraction did the market capture? AE = 1: perfect aggregation. AE cleanly separates "the market failed to aggregate" from "there was nothing to aggregate" (high ρ). AE < 0 means the market did worse than the prior — possible under manipulation or herding.
7. **Convergence time** t* — the first round after which the price stays within δ of its final value — and **path volatility**, Σ(p_t − p_{t−1})².
8. **Depth and volume.** Depth is measured by price impact — the LMSR analog of **Kyle's λ** (lambda), the standard microstructure measure of how much one dollar of trading moves the price; here it is p(1−p)/b. Plus total trading volume. (Bid–ask spread: order-book mode only, v2.)
9. **Manipulation robustness:** the minimum manipulator budget share needed to hold the price at least δ away from its no-manipulator benchmark for k rounds. A "cost of distortion" curve — the model's analog of the theoretical limits on manipulation in the literature (Ottaviani–Sørensen).
10. **Wealth dynamics** *(deferred — requires the repeated-markets mode, out of scope for v1)*: the **Gini coefficient** of wealth (0 = perfect equality, 1 = one agent owns everything) over time; the correlation between a trader's accuracy and terminal wealth; survival rates of accurate traders. This connects to the **market selection** literature (Blume–Easley; Kets–Pennock–Sethi–Shah): accurate fractional-Kelly bettors survive and accumulate; full-Kelly bettors overbet and can be wiped out by bad luck despite accurate beliefs.

Micro (agent-level) observables, mainly for the pedagogical mode: each agent's belief pᵢ, position, wealth, and realized profit/loss; the omniscient forecast p★ drawn as the reference line the price ought to chase.

Quantities from the literature we deliberately *exclude*, and why: Manski's bounds on the gap between price and mean belief (superseded here — our agents satisfy Wolfers–Zitzewitz's sufficient conditions under log utility, so price ≈ wealth-weighted mean belief holds by construction); bid–ask spread and adverse-selection decompositions (order-book-specific, v2); consistency measures for combinatorial markets (out of scope).

---

## 5. Known results the model must reproduce (validation suite)

An ordered test battery. Each item checks the machinery before we hunt anything new.

1. **Convergence and wealth-weighting** (Beygelzimer–Langford–Pennock): with pure Kelly bettors and no frictions, the price converges to the wealth-weighted average belief, and the ensemble behaves like a Bayesian learner.
2. **Price ≈ mean belief** (Wolfers–Zitzewitz): holds under log utility; systematic deviations appear when the belief distribution is skewed. Verify at extreme thresholds c.
3. **The n_eff ceiling:** for any ρ > 0, mean Brier score plateaus in n at the level implied by n_eff = 1/ρ. Aggregation efficiency can be ≈ 1 while accuracy stays poor. (Checkable analytically and by simulation — a good cross-validation.)
4. **Manipulators can help** (Hanson–Oprea 2009): a manipulator whose target price is *uncertain* to others increases average accuracy, because the distortion raises the returns to informed trading and pulls more information into the market. ⚠ Two caveats. First, in our model the effect exists *only* through the participation margin (c_part > 0) — see §1.3. Second, this is a theorem with conditions, not a law: the experimental record is mixed (in Hanson–Oprea–Porter's lab experiments, manipulators simply failed to move prices), and the effect can reverse under fees and herding (§6, item 2). The teaching module must show both regimes, not preach the optimistic one.
5. **Fees cause staleness:** as τ or κ rise, no-trade bands widen, convergence stops short of the omniscient forecast, and the Brier score degrades — smoothly at first, then sharply when participation collapses.
6. **Favorite–longshot bias emerges** at extreme base rates from bounded prices plus noise traders alone — without assuming anyone loves risk.
7. **Market selection** *(deferred with repeated markets)*: accurate full-Kelly traders accumulate wealth but with high variance; fractional Kelly survives more reliably (Kets et al.); market accuracy improves across successive markets as wealth flows to the accurate.

---

## 6. Neglected interaction effects — candidate research contributions

Ranked by interest × neglect × tractability in this model.

1. **Correlation × wealth concentration: "wealth-weighted effective information."** The price aggregates a *wealth-weighted* pool of signals, so the operative quantity is not n_eff but a wealth-weighted analog, n_eff^w. If the wealthy share correlated errors — plausible, since they plausibly read the same sources — a market with thousands of traders can carry the information of roughly two signals. Prediction: accuracy is far more sensitive to correlation *among the rich* than to overall correlation. Nobody has this decomposition cleanly, and it is closed-form in the one-shot model.
2. **Manipulation × liquidity × fees: when does Hanson–Oprea reverse?** The optimistic theorem assumes frictionless counter-trading. With fees and finite counter-party budgets there should be a **manipulation-robustness frontier** in (B_m, τ, b)-space: below it, manipulation improves accuracy (the theorem); above it, the distortion *sticks*, because correcting it isn't worth the fee. Mapping that frontier is a real contribution — and it is exactly the chart the pedagogical mode's manipulation experiment should trace.
3. **Fees × wealth × precision: transaction costs are non-monotone.** Fees screen out low-information dabblers (raising average trade quality) but also exclude poor-but-well-informed traders (destroying information). This predicts an *interior optimum* fee τ★ > 0 whose location depends on the wealth–precision correlation. Cuts against the reflexive "lower fees are always better," and is nearly unstudied.
4. **Herding × correlation × manipulation: manufactured cascades.** With herding (h > 0), a manipulator need not hold the price — only push it far enough that the price-learners carry it onward. The interaction of h, ρ, and B_m sets a cascade threshold below which small budgets have outsized effects. Connects prediction markets to the information-cascade literature, which mostly ignores market mechanisms.
5. **Repeated markets × common shocks: corrupted market selection.** *(Deferred — requires the repeated-markets mode.)* Market selection works when profit tracks skill. Common error shocks (η) make whole cohorts win or lose *together*, so wealth becomes a noisy proxy for accuracy, and the market's self-correction slows or reverses. Interaction of ρ with M and α_w.
6. **Liquidity × population: the optimal subsidy b★(n).** Practical and semi-neglected: b too small and the price is noise-dominated; b too large and no one can move the price to their posterior within their Kelly budget. An optimal-liquidity curve b★(n, wealth) would be directly useful to market designers.
7. **Friction type × manipulation: which costs preserve self-healing?** From §1.4: the Hanson–Oprea attraction channel should be strong under participation costs (ex-ante entry margin), weak under fixed per-trade costs (ex-post censoring), and reversible under proportional fees (which tax the corrective trades themselves) — a predicted ordering c_part > κ > τ. A clean ranking experiment across friction types that, to my knowledge, nobody has run.

---

## 7. Opening a market — how it's done in practice, and in the model

How real platforms initialize prices:

- **LMSR markets** (the classic design; used by older corporate systems like Inkling/Consensus Point): the operator seeds the cost function, so the opening price is the operator's chosen prior — often just 50% — and the operator's maximum loss, b·ln 2, is the subsidy that pays for liquidity.
- **Polymarket:** before 2022, an automated market maker (a CPMM — constant product market maker, the Uniswap-style algorithm) seeded by liquidity providers; since 2022, an order book (CLOB — central limit order book). Order-book markets open *empty*; the first prices are simply the first quotes, posted by professional market makers in paid incentive programs.
- **Kalshi:** an order book with designated market-maker and liquidity programs; the opening price is wherever the first quotes cross.
- **Manifold:** an automated market maker seeded by the question creator's own subsidy, at an initial probability the creator chooses.

**Model choice:** open at p₀_init = 0.5 by default, so the user watches the market converge from complete ignorance — the central pedagogical image. Offer p₀_init = prior as an option (useful for testing anchoring when h > 0). Keeping the LMSR subsidy explicit is itself a lesson: price discovery is a public good, and someone has to pay for it.

---

## 8. What we solve on paper vs what we simulate

**Closed-form (derive, don't simulate):**

- Agent posteriors, the omniscient forecast, n_eff, and the prior/omniscient Brier benchmarks.
- The frictionless one-shot equilibrium (λ = 1, τ = 0): price = wealth-weighted average belief, with its *expected* Brier score computed exactly by two-dimensional numerical integration (**quadrature**) over the two random inputs (θ, η). This yields exact research-mode surfaces for the frictionless case, including interaction 6.1.

**Simulation required:** everything sequential or frictional — convergence paths and volatility, no-trade bands, the participation margin, manipulation, herding, repeated markets. Discipline: the simulated frictionless case must match the quadrature answer before any frictional result is trusted.

---

## 9. The two modes

**Mode A — Market Lab (pedagogical).** A live price path p_t with reference lines (prior, omniscient forecast, eventual resolution); an agent-swarm view (each agent plotted by belief vs position, sized by wealth); step / run / pause controls; a plain-language event log ("Agent 17 buys 30 YES at 0.62"). **User interjection:** the user is an agent with a wallet — buy and sell at will, try to pin the price somewhere — and can additionally configure a **manipulator bot** (budget B_m, target π★, toggled on and off mid-run). Every segment of the price path moved by manipulation trades, the bot's or the user's own, is drawn in **red** against the neutral color of ordinary trading, so the manipulation's footprint — and the market's absorption of it, or failure to absorb it past the frontier of §6.2 — is visually unmistakable. After resolution, a profit-and-loss report: what the manipulation attempt cost, and which traders collected it.

**Mode B — Ensemble analysis (research).** Expected values of every §4 metric over ensembles of runs; one-dimensional parameter sweeps with confidence intervals; two-dimensional interaction heatmaps (the §6 list is the sweep menu); Murphy-decomposition and calibration panels. Sweep design follows the adaptive-parameter-sweeps workflow — hunting regime boundaries rather than filling uniform grids.

---

## 10. Implementation notes

- R/Shiny per project conventions; this will exceed 600 lines, so modularize: model core / Market Lab UI / Ensemble Analysis UI.
- The model core must be UI-independent (pure functions), so the same code drives both modes and batch sweeps.
- ggplot2 for Mode B; Mode A's live view likely uses base Shiny reactivity with ggplot frames (decide at implementation stage).
- PROGRESS.md maintained alongside.

---

## 11. Decisions (resolved 2026-07-13) and remaining questions

**Resolved:**

1. **Contract space:** single binary contract "θ ≥ c" for v1. Bucket markets and continuous contracts deferred.
2. **Mechanism:** LMSR-only for v1; order book deferred to v2 — see §1.2 for exactly what would change and why v1 friction results are stated as LMSR-conditional.
3. **Participation margin:** in for v1 (c_part). See §1.4 for how it differs formally from transaction costs.
4. **Repeated markets:** out of scope for v1. The market-selection material is retained in the text but marked deferred (§1.5, §4 item 10, §5 item 7, §6 item 5).
5. **Research-mode ground truth:** both — expectations over the joint (θ, signals) distribution for headline metrics; conditional-on-θ for the favorite–longshot analysis.
6. **User interjection:** manual wallet trading *and* a configurable manipulator bot; all manipulation-driven price movement drawn in red (§9).
7. **Platform:** R/Shiny for both modes.
8. **Herding channel:** in for v1 — belief-adoption specification, default h = 0 (full analysis in §1.3).

No open model-design questions remain. Next stage: full formalization spec, then pseudocode. GUI decisions are logged in GUI_DESIGN.md.

---

## 12. Ideas parking lot (noted, not planned)

Continuous contracts scored by CRPS; heterogeneous signal precision with endogenous investment in expertise (the full Grossman–Stiglitz treatment); resolution ambiguity modeled as random settlement error; self-referential markets where the price affects the outcome; AI/algorithmic traders whose shared model errors microfound ρ (topical: beliefs derived from a common LLM are exactly a common error η); whale-vs-crowd decompositions of realized price moves; benchmarking the market against simple *opinion pools* — the plain mean, the median, and the extremized logit pool (average the log-odds, then push away from 0.5) — to answer "is the market worth its friction?"

---

## 13. Key references

Hanson (2003), LMSR. Hanson & Oprea (2009), *A Manipulator Can Aid Prediction Market Accuracy*, Economica. Hanson, Oprea & Porter (2006), manipulation experiments. Wolfers & Zitzewitz (2006), *Interpreting Prediction Market Prices as Probabilities*. Beygelzimer, Langford & Pennock (2012), *Learning Performance of Prediction Markets with Kelly Bettors*. Kets, Pennock, Sethi & Shah (2014), *Betting Strategies, Market Selection, and the Wisdom of Crowds*. Blume & Easley (2006), market selection. Kyle (1985), informed trading and market depth. Grossman & Stiglitz (1980), the impossibility of informationally efficient markets. Glosten & Milgrom (1985), bid–ask spreads from adverse selection. Milgrom & Stokey (1982), the no-trade theorem. Murphy (1973), Brier decomposition. Snowberg & Wolfers (2010), favorite–longshot bias.

---

## 14. Index of terms

- **Adverse selection:** trading against a counterparty who knows more than you; the reason order-book market makers quote a bid–ask spread (Glosten–Milgrom).
- **Aggregation efficiency (AE):** the fraction of achievable forecast improvement the market captures: (B_prior − B_market)/(B_prior − B_omniscient). 1 = perfect aggregation; below 0 = worse than the prior.
- **Automated market maker (AMM):** an algorithm that always quotes a price and takes the other side of any trade, instead of matching buyers with sellers. LMSR and CPMM are examples.
- **Base rate:** the unconditional probability of the event, before any signals.
- **Bid–ask spread:** in an order book, the gap between the best standing offer to buy and the best to sell. A friction and a measure of illiquidity.
- **Binary contract:** a security paying $1 if a specified event happens, $0 otherwise. Its fair price is the event's probability.
- **Brier score:** squared error of a probability forecast, (forecast − outcome)². 0 is perfect; 0.25 is the score of always saying 50%.
- **Calibration:** the property that events forecast at probability p happen with frequency p. Measured by the reliability term of the Murphy decomposition and by the calibration curve's slope and intercept.
- **CDA (continuous double auction):** the order-book trading mechanism — buyers and sellers post offers, trades occur when offers cross. What Kalshi and Polymarket run.
- **CLOB (central limit order book):** the standard implementation of a CDA: a ranked list of all standing buy and sell orders.
- **Common error (η):** the component of signal noise shared by all agents — the same misleading poll, narrative, or method. Governs the error correlation ρ.
- **Conjugacy:** when the prior and the data model combine so the posterior has the same form as the prior (normal + normal → normal). Buys us closed-form beliefs.
- **CPMM (constant product market maker):** an AMM that keeps the product of its two token reserves constant (the Uniswap rule); Polymarket's pre-2022 mechanism.
- **CRPS (continuous ranked probability score):** the generalization of the Brier score to forecasts of continuous quantities. Needed only for continuous contracts (deferred).
- **Effective sample size (n_eff):** the number of *independent* signals that would carry the same information as n correlated ones: n_eff = n/(1+(n−1)ρ). Tends to 1/ρ as n grows — the information ceiling.
- **Equicorrelated noise:** the simplest correlation structure — every pair of agents' errors has the same correlation ρ.
- **Extensive vs intensive margin:** whether a cost changes *if* an action is taken (extensive) or *how much* of it is taken (intensive). Proportional fees act on the intensive margin; fixed and participation costs on extensive margins (per trade and per market, respectively).
- **Favorite–longshot bias:** the classic market distortion of overpricing unlikely events and underpricing near-certain ones.
- **Fractional Kelly:** staking a fixed fraction λ of the full Kelly amount; a one-parameter model of caution.
- **Gini coefficient:** a 0–1 measure of inequality; 0 = everyone equal, 1 = one agent owns everything.
- **Grossman–Stiglitz paradox:** if prices perfectly reflected all information, gathering costly information would never pay — so perfectly efficient prices undermine their own information supply. Motivates the participation/information-cost margin.
- **Herding / information cascade:** agents imitating the price (or each other) rather than using private information; past a threshold, imitation feeds itself and private information stops entering the price.
- **Kelly criterion:** bet the bankroll fraction that maximizes expected log wealth (equivalently, long-run growth). For a binary contract: f★ = (belief − price)/(1 − price).
- **Kyle's λ:** the standard measure of price impact — how much one unit of trading moves the price. In LMSR: p(1−p)/b.
- **Liquidity (b):** how much money it takes to move the price. In LMSR, the single parameter b; larger b = deeper, more stable, but more sluggish market.
- **LMSR (logarithmic market scoring rule):** Hanson's automated market maker with cost function C(q) = b·ln(e^{q_Y/b} + e^{q_N/b}); always quotes a price in (0,1); worst-case operator loss b·ln 2.
- **Manipulation-robustness frontier:** the boundary in (manipulator budget, fee, liquidity)-space separating the regime where manipulation improves accuracy from the regime where distortions stick.
- **Market microstructure:** the study of how the mechanics of trading (mechanism, fees, liquidity) shape prices.
- **Market selection:** the dynamic by which accurate traders accumulate wealth and influence while inaccurate ones are driven out — the market's hypothesized self-improvement mechanism.
- **Murphy decomposition:** the exact split of the ensemble Brier score into reliability (calibration error) − resolution (discrimination) + uncertainty (difficulty of the question).
- **No-trade band:** the belief–price gap within which trading isn't worth the transaction cost, so nothing happens. The mechanism of stale prices.
- **No-trade theorem (Milgrom–Stokey):** rational, risk-averse traders with common priors should not bet against each other on pure information — someone offering you a bet is evidence they know something you don't. Why real markets need noise traders, hedgers, or subsidies to generate volume.
- **Noise trader:** a trader whose beliefs are unrelated to the truth. Loses on average; that loss is the informed traders' profit.
- **Omniscient forecast (p★):** the posterior probability given *all* agents' signals at once — the ceiling on what any aggregation method could achieve.
- **Opinion pool:** a direct (non-market) belief-aggregation rule, e.g., the mean, the median, or the extremized logit pool of individual probabilities.
- **Order book:** see CLOB.
- **Pareto distribution:** the standard heavy-tailed wealth distribution; tail index α_w, with lower α_w meaning more inequality.
- **Participation cost (c_part):** the effort cost of paying attention and trading at all; agents trade only when expected gains exceed it. Load-bearing for the manipulation-helps result.
- **Posterior:** a belief after updating on evidence by Bayes' rule.
- **Price impact:** how much a trade of a given size moves the price; see Kyle's λ.
- **Prior:** the belief held before seeing any evidence.
- **Quadrature:** deterministic numerical integration; used to compute exact expected Brier scores in the frictionless case instead of simulating.
- **Rational expectations equilibrium (REE):** a price that already incorporates all traders' information, leaving no private informational advantage.
- **Resolution:** (of a forecast system) the degree to which forecasts differ between events that occur and events that don't — the RES term of the Murphy decomposition. Also: (of a market) the settlement of the contract when the outcome is realized.
- **Spoofing:** posting orders you intend to cancel, to fake supply or demand; an order-book manipulation tactic with no analog against an automated market maker.
- **Stale price:** a price that has stopped tracking available information because, given transaction costs, no one finds it worthwhile to correct.
- **Subsidy:** the market maker's expected loss, which pays traders to reveal information. LMSR's worst case: b·ln 2.
- **Sufficient statistic:** a summary of data that preserves all its information about the unknown — here, the average signal s̄.
