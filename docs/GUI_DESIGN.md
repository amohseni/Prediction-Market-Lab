# Prediction Market Lab — GUI Design

**Stage:** design (v0.1). Companion to PREDICTION_MARKET_MODEL_PLAN.md (v0.3). Follows GUI_DESIGN_PRINCIPLES.md, adapted to Aydin's standard layout: title → three-column explainer → sidebar + tabbed main panel.

---

## 1. Content inventory

Everything the interface must carry, before any layout. Sources: plan §4 (metrics), §6 (research questions), §9 (modes), §11 (decisions).

### 1.1 Explanatory content
| Item | Source |
|---|---|
| Title + one-line thesis | new |
| Three-column précis: the model / the mechanism / the science | new (§1 of plan, compressed) |
| One-line explanation per parameter (17 of them) | §2, written below in §3.2 |
| Expandable "details" text per parameter group | plan §1.1–1.4, compressed |
| Full glossary | plan §14, verbatim |
| References | plan §13 |

### 1.2 Single-run content (pedagogical)
| Item | Notes |
|---|---|
| Price path p_t over trades | the centerpiece; animated |
| Reference lines: prior p₀, omniscient forecast p★, resolution outcome | p★ recomputed per run from realized signals |
| Price-path color modes: red = manipulators/bot, orange = user; color-by-trader toggle | decisions plan §11.6, GUI §7.2 |
| Run controls: run / pause / step / reset / speed | plus scrub slider (see §4.3) |
| Manipulator bot controls: on/off, budget B_m, target π★ | in-tab, toggleable mid-run |
| User wallet: balance, position, buy/sell YES controls | user trades count as manipulation → red |
| Agent swarm: belief vs position, dot size = wealth, color = type | animated with price path |
| Event log: "Agent 17 buys 30 YES @ 0.62 (+fee 0.31)" | scrolling, plain language |
| Post-resolution card: outcome, final price, run Brier, P&L by trader type incl. bot & user | |
| Belief-migration view (herding): each pᵢ over time | shows cascades when h > 0; empty message when h = 0 |
| Convergence diagnostics: distance to p★ per round, volume per round, price vs wealth-weighted mean belief | "anatomy" content |
| Participation display: who sat out (c_part) and who is inside no-trade bands | makes frictions visible |

### 1.3 Ensemble content (research)
| Item | Notes |
|---|---|
| 1-D sweeps: any parameter → mean Brier, AE, log score, bias, REL, RES | CIs; reference lines = prior & omniscient Brier |
| Analytic overlay: closed-form frictionless curve where available | quadrature; validates simulation on sight |
| Murphy decomposition panel (REL − RES + UNC stacked) | per parameter setting |
| Calibration curve + slope/intercept | pooled over ensemble |
| Favorite–longshot panel: E[A \| p_T] vs p_T at extreme c | conditional-on-θ ground truth (decision §11.5) |
| 2-D interaction heatmaps: curated pairs from plan §6 + free choice | metric selector: Brier / AE / REL / bias |
| Manipulation-robustness frontier: min B_m to hold δ-distortion, over (τ, b) | plan §4 item 9, §6 item 2 |
| Friction comparison: Hanson–Oprea effect under c_part vs κ vs τ | plan §6 item 7 |
| n_eff ceiling exhibit: Brier vs n for several ρ | the single most important research picture |
| Ensemble controls: replications R, seed, progress bar, cancel | |
| CSV/PNG export per plot | |

### 1.4 Cross-cutting state
| Item | Notes |
|---|---|
| Preset scenarios (see §3.1) | one click → full parameter vector |
| Stale-plot indicator: "parameters changed since this was computed" | prevents silent mismatch between sidebar and plots |
| Result cache keyed by parameter hash | sweeps are expensive; don't recompute on tab switch |
| Seed control | reproducibility |

---

## 2. Page layout

```
+--------------------------------------------------------------------------+
| PREDICTION MARKET LAB                                                     |
| When do markets know things? Watch one work — and find out when it fails. |
+--------------------------------------------------------------------------+
| THE MODEL          | THE MECHANISM        | THE SCIENCE                   |
| A hidden truth;    | Traders move the     | Accuracy measured against     |
| traders with noisy | price toward their   | hard limits: correlated       |
| correlated clues,  | beliefs, wallet-     | errors cap what any market    |
| unequal wealth,    | limited. Watch the   | can know; fees, inequality,   |
| betting against an | price converge —     | herding, and manipulators     |
| automated market   | then try to          | do the rest. Map the failure  |
| maker.             | manipulate it.       | modes in parameter space.     |
+------------+-------------------------------------------------------------+
| PRESETS ▾  |  [ Live Market | Run Anatomy | Reliability | Interactions |  |
| Reset      |    Guide ]                                                   |
|            |                                                              |
| ▸ Informa- |   +------------------------------------------------------+  |
|   tion     |   |                                                      |  |
| ▸ Market   |   |                (active tab content)                  |  |
| ▸ Traders  |   |                                                      |  |
| ▸ Frictions|   +------------------------------------------------------+  |
| ▸ Simula-  |                                                              |
|   tion     |                                                              |
+------------+--------------------------------------------------------------+
```

- Single page; both use cases live in one interface as tabs, sharing one parameter state. No mode switch, no duplicated controls.
- Sidebar ≈ 1/4 width; main panel ≈ 3/4.
- GUI_DESIGN_PRINCIPLES.md says 2–4 tabs; we have 5. Resolution: *Guide* is reference material, not a working view, so the working-tab count stays at 4. If it still feels heavy, Run Anatomy can fold into Live Market as a sub-panel — decide at implementation after seeing it.

---

## 3. Sidebar

### 3.1 Presets (top of sidebar)

A dropdown of named scenarios; selecting one sets the full parameter vector. This is the single highest-leverage pedagogical element — each preset is a lesson:

| Preset | Settings gist | Lesson |
|---|---|---|
| Textbook market | defaults: ρ=0, no frictions, no manipulation | markets work; price → p★ |
| Echo chamber | ρ = 0.5 | many traders, little knowledge: the n_eff ceiling |
| Whale market | α_w = 1.2 | one fortune ≈ the whole market's opinion |
| Toll road | τ = 0.05, κ > 0 | no-trade bands, stale price |
| Sleepy market | c_part > 0, moderate signals | thin participation; then switch the bot on and watch it *wake the market up* (Hanson–Oprea) |
| Cascade | h = 0.4, ρ = 0.3, bot on briefly | manipulation that outlives the manipulator |

Below presets: **Reset to defaults** button and the stale-plot badge.

### 3.2 Parameter groups (accordion: titled, collapsible, one open at a time)

Every input: slider with numeric readout, label, and a one-line caption (the text below is the actual copy). Each group header expands to a short "details" paragraph (2–4 sentences, drawn from plan §1) for those who want the mechanics.

**▸ Information** — *what there is to know, and who knows it*
| Control | Caption |
|---|---|
| n | How many traders receive a clue. |
| σ_ε | How noisy each clue is. |
| ρ | How much traders' errors overlap — shared mistakes, not independent checks. |
| μ₀, σ₀ | What everyone believes before any clues. |
| c | The bar the truth must clear for YES — sets how rare the event is. |

**▸ Market** — *the trading machinery*
| Control | Caption |
|---|---|
| b | Market depth: how much money it takes to move the price. |
| p₀_init | Where the price starts (0.5 = ignorance). |
| T | How many rounds of trading before the answer is revealed. |

**▸ Traders** — *who shows up*
| Control | Caption |
|---|---|
| α_w | Wealth inequality (lower = a few whales own everything). |
| λ | Betting aggression: 1 = full Kelly, lower = timid. |
| φ_noise | Share of traders betting on noise instead of information. |
| φ_manip, B_m, π★ | Built-in manipulators: how many, how funded, what price they want. |
| h | Herding: how much traders adopt the price as their own belief. |

**▸ Frictions** — *what trading costs*
| Control | Caption |
|---|---|
| τ | Fee as a share of each trade (shrinks every trade). |
| κ | Flat cost per trade (kills small trades entirely). |
| c_part | Cost of paying attention at all (decides who even shows up). |

**▸ Simulation**
| Control | Caption |
|---|---|
| seed | Random seed (reproducibility). |
| R | Replications per ensemble point (research tabs only). |

Note the separation of concerns: the sidebar defines *the world*; anything the user does *to* that world mid-run (trade, unleash the bot) lives inside the Live Market tab. Structural manipulators (φ_manip) are part of the world and stay in the sidebar; the interactive bot is an intervention and does not.

---

## 4. Main panel tabs

### Tab 1 — Live Market (the pedagogical centerpiece)

Layout, top to bottom:

1. **Control strip:** ▶ Run · ⏸ Pause · ⏭ Step · ↺ New market · speed slider · scrub slider (drag back through the trade history of the current run).
2. **Main plot** (the one Aydin specified): x = trade index (time), y = price ∈ (0,1).
   - Price path: ink, thick.
   - Prior p₀: gray dotted horizontal line.
   - Omniscient forecast p★: blue dashed horizontal line — "the best anyone could know."
   - Resolution: at t = end, outcome marker at 0 or 1 and vertical resolution line.
   - **Path coloring — two-mode toggle** (decided 2026-07-13). *Highlight manipulation* (default): ink path; **red** = segments moved by the bot or structural manipulators (manipulation by construction); **orange** = segments moved by the user (motive unknown — orange means "you," whether distorting or correcting). *Color by trader* (toggle): every segment tinted by the type of the trader who moved it (informed / noise / manipulator+bot / user) — the full mechanistic view, opt-in. The toggle governs the price path only; swarm and event log are always type-colored.
   - Annotations at first render (textbook preset): small labels on each reference line so the plot is self-explanatory before anyone reads anything.
3. **Intervention strip** (two cards side by side):
   - *Manipulator bot:* on/off toggle, B_m slider, π★ slider. Toggleable mid-run; while on, a red dot pulses next to the toggle.
   - *Your wallet:* balance, current position, [Buy YES] [Sell YES] with amount box. User trades are orange on the plot.
4. **Agent swarm** (below main plot, shares x-axis time via animation frame): each agent a dot — x = current belief pᵢ, y = position (long ↔ short), size = wealth, color = type (informed / noise / manipulator / sat-out shown hollow). Watching dots stream toward the price line as their beliefs are absorbed *is* the herding lesson.
5. **Event log** (right of swarm or collapsible): scrolling plain-language trades; fee paid shown when τ, κ > 0.
6. **Post-resolution card** (appears at resolution): outcome, final price, run Brier vs prior-Brier ("the market beat the prior by X"), P&L table by trader type including bot and user — "your manipulation cost you $Y; it was collected by the informed traders."

### Tab 2 — Run Anatomy (what just happened, mechanically)

Diagnostics of the *current* single run; answers "why did the price do that?"

- **Convergence:** |p_t − p★| per round (log scale) — the healing curve.
- **Aggregation check:** price vs wealth-weighted mean belief per round — they should hug each other (plan §1.6); divergence indicates herding or frictions at work.
- **Participation:** bar of agents by status per round — traded / inside no-trade band / never entered (c_part). Makes all three frictions of plan §1.4 visually distinct.
- **Belief migration** (when h > 0): thin line per agent, pᵢ over time; a cascade is visible as lines being reeled in by the (possibly red) price. When h = 0: message "herding is off — beliefs are fixed; turn h up to see cascades."
- **Volume** per round.

### Tab 3 — Reliability (1-D research sweeps)

- **Setup strip:** sweep parameter (dropdown, any sidebar parameter) · range · points · metric checkboxes (Brier, AE, log score, bias, REL, RES) · replications R · [Run sweep] with progress bar and cancel.
- **Main sweep plot:** metric vs parameter, mean ± CI; gray line = prior Brier, blue line = omniscient Brier; **analytic overlay** (dashed) where the frictionless closed form exists — the simulation validating itself in public.
- **Sub-panels** (small multiples under the main plot): Murphy decomposition (stacked REL/RES/UNC), calibration curve at selected sweep points, favorite–longshot panel (activates when sweeping c).
- **Preloaded exhibit:** on first visit this tab shows the precomputed *n_eff ceiling* figure (Brier vs n at ρ ∈ {0, 0.1, 0.3, 0.5}) — never blank, and it's the most important picture in the project.
- Export: CSV of sweep data, PNG of plots.

### Tab 4 — Interactions (2-D research maps)

- **Setup strip:** x-parameter, y-parameter, metric, resolution, R, [Run map] + progress.
- **Curated questions menu** (radio buttons above the free choice) — one click configures the whole map, directly from plan §6:
  1. Echo-chamber wealth: ρ × α_w → AE
  2. Manipulation frontier: B_m × τ → price distortion (with frontier contour overlaid)
  3. Fee optimum: τ × wealth–precision correlation → Brier (shows interior τ★)
  4. Manufactured cascades: h × B_m → post-manipulation persistence
  5. Friction ranking: Hanson–Oprea effect size under c_part vs κ vs τ (grouped bars, not a heatmap)
- **Heatmap** with contour lines; diverging palette centered on the no-effect value; marginal 1-D slices on hover/click (click a cell → the corresponding 1-D slice renders below).
- Export as in Tab 3.

### Tab 5 — Guide

Static reference, three sections in internal sub-navigation: **How it works** (plan §1 in readable form, with the three frictions and two herding variants), **Glossary** (plan §14 verbatim, searchable), **References** (plan §13). No computation.

---

## 5. Visual language (one semantics everywhere)

| Element | Style |
|---|---|
| Market price | ink, solid, thick |
| Prior p₀ / prior-Brier line | gray, dotted |
| Omniscient p★ / omniscient-Brier line | blue, dashed |
| Manipulation (bot + structural manipulators) | red |
| User trades | orange |
| Outcome/resolution | black marker, vertical line |
| CIs | gray ribbon |
| Color-by-trader toggle (price path only) | informed / noise / manipulator+bot / user tints |

Same encoding in every tab: a user who learns "blue dashed = best possible" in the Live Market reads the sweep plots for free. Palette matches Aydin's standard (ink/gray/blue/red), and ink/blue/red survives common colorblindness; keep viridis for heatmap fills per GUI_DESIGN_PRINCIPLES.md.

---

## 6. Interaction architecture (implementation-relevant decisions)

1. **Animation = precompute + replay, with an injection point.** Naive live stepping in Shiny is fragile. Design: simulate ahead in chunks (one round at a time), append to a trajectory store, animate the reveal with `invalidateLater`; the scrub slider indexes the store. User/bot interventions invalidate the not-yet-revealed future: on intervention, truncate the store at the current trade and resimulate forward with the intervention in the queue. Gives smooth animation, scrubbing, *and* mid-run interjection.
2. **One reactive parameter state**, consumed by all tabs. Any sidebar change flips the stale badge on every computed artifact (single run and cached sweeps); plots dim slightly + show "settings changed — rerun" rather than auto-recomputing (sweeps are expensive; surprise recomputation is worse).
3. **Cache** ensemble results keyed by hash(params, sweep spec, R, seed). Tab switching never recomputes.
4. **Ensembles run chunked** with progress + cancel (Shiny `withProgress` or promises/future if needed; decide at implementation).
5. **Initial state** (GUI_DESIGN_PRINCIPLES.md: never blank): app loads on the Textbook preset with one precomputed run displayed in Tab 1 and the precomputed n_eff exhibit in Tab 3.
6. **Modularity** (plan §10): model core is UI-free; each tab a Shiny module; `app.R` + `R/` files since we'll exceed 600 lines.

---

## 7. GUI decisions (resolved 2026-07-13) and implementation defaults

Resolved:

1. **Run Anatomy:** own tab; the post-resolution card links to it. Revisit after first build if it feels heavy.
2. **Price-path coloring:** two-mode toggle (§4, Tab 1). Default *Highlight manipulation*: red = bot + structural manipulators (manipulation by construction), orange = user (motive unknown — "you," whether distorting or correcting). Toggle *Color by trader*: segments tinted by mover's type. Swarm and event log always type-colored.

Implementation defaults (no user decision required; flag deviations in PROGRESS):

3. Swarm animation: try per-trade updates; fall back to per-round if it stutters.
4. Event log: every trade when n·T ≤ 2,000; round summaries above.
