# =============================================================================
# mod_guide.R -- Tab 5: Guide (handoff Sec. 4, GUI Sec. 4 Tab 5). Static
# reference, three sub-sections: How it works (a readable account of the model),
# Glossary (every term of art, searchable), References. No computation.
# Text drawn from docs/PREDICTION_MARKET_MODEL_PLAN.md (§1, §13, §14).
# =============================================================================

# ---- Glossary (plan §14, verbatim) ------------------------------------------
pm_glossary <- function() {
  g <- function(term, def) data.frame(Term = term, Definition = def, stringsAsFactors = FALSE)
  do.call(rbind, list(
    g("Adverse selection", "Trading against a counterparty who knows more than you; the reason order-book market makers quote a bid-ask spread (Glosten-Milgrom)."),
    g("Aggregation efficiency (AE)", "The fraction of achievable forecast improvement the market captures: (B_prior - B_market)/(B_prior - B_omniscient). 1 = perfect aggregation; below 0 = worse than the prior."),
    g("Automated market maker (AMM)", "An algorithm that always quotes a price and takes the other side of any trade, instead of matching buyers with sellers. LMSR and CPMM are examples."),
    g("Base rate", "The unconditional probability of the event, before any signals."),
    g("Bid-ask spread", "In an order book, the gap between the best standing offer to buy and the best to sell. A friction and a measure of illiquidity."),
    g("Binary contract", "A security paying $1 if a specified event happens, $0 otherwise. Its fair price is the event's probability."),
    g("Brier score", "Squared error of a probability forecast, (forecast - outcome). 0 is perfect; 0.25 is the score of always saying 50%."),
    g("Calibration", "The property that events forecast at probability p happen with frequency p. Measured by the reliability term of the Murphy decomposition and by the calibration curve's slope and intercept."),
    g("CDA (continuous double auction)", "The order-book trading mechanism -- buyers and sellers post offers, trades occur when offers cross. What Kalshi and Polymarket run."),
    g("CLOB (central limit order book)", "The standard implementation of a CDA: a ranked list of all standing buy and sell orders."),
    g("Common error (eta)", "The component of signal noise shared by all agents -- the same misleading poll, narrative, or method. Governs the error correlation rho."),
    g("Conjugacy", "When the prior and the data model combine so the posterior has the same form as the prior (normal + normal -> normal). Buys us closed-form beliefs."),
    g("CPMM (constant product market maker)", "An AMM that keeps the product of its two token reserves constant (the Uniswap rule); Polymarket's pre-2022 mechanism."),
    g("CRPS", "Continuous ranked probability score: the generalization of the Brier score to forecasts of continuous quantities. Needed only for continuous contracts (deferred)."),
    g("Effective sample size (n_eff)", "The number of independent signals that would carry the same information as n correlated ones: n_eff = n/(1+(n-1)rho). Tends to 1/rho as n grows -- the information ceiling."),
    g("Equicorrelated noise", "The simplest correlation structure -- every pair of agents' errors has the same correlation rho."),
    g("Extensive vs intensive margin", "Whether a cost changes if an action is taken (extensive) or how much of it is taken (intensive). Proportional fees act on the intensive margin; fixed and participation costs on extensive margins (per trade and per market)."),
    g("Favorite-longshot bias", "The classic market distortion of overpricing unlikely events and underpricing near-certain ones."),
    g("Fractional Kelly", "Staking a fixed fraction lambda of the full Kelly amount; a one-parameter model of caution."),
    g("Gini coefficient", "A 0-1 measure of inequality; 0 = everyone equal, 1 = one agent owns everything."),
    g("Grossman-Stiglitz paradox", "If prices perfectly reflected all information, gathering costly information would never pay -- so perfectly efficient prices undermine their own information supply. Motivates the participation/information-cost margin."),
    g("Herding / information cascade", "Agents imitating the price (or each other) rather than using private information; past a threshold, imitation feeds itself and private information stops entering the price."),
    g("Kelly criterion", "Bet the bankroll fraction that maximizes expected log wealth (equivalently, long-run growth). For a binary contract: f = (belief - price)/(1 - price)."),
    g("Kyle's lambda", "The standard measure of price impact -- how much one unit of trading moves the price. In LMSR: p(1-p)/b."),
    g("Liquidity (b)", "How much money it takes to move the price. In LMSR, the single parameter b; larger b = deeper, more stable, but more sluggish market."),
    g("LMSR", "Logarithmic market scoring rule: Hanson's automated market maker with cost function C(q) = b*ln(e^{q_Y/b} + e^{q_N/b}); always quotes a price in (0,1); worst-case operator loss b*ln 2."),
    g("Manipulation-robustness frontier", "The boundary in (manipulator budget, fee, liquidity)-space separating the regime where manipulation improves accuracy from the regime where distortions stick."),
    g("Market microstructure", "The study of how the mechanics of trading (mechanism, fees, liquidity) shape prices."),
    g("Market selection", "The dynamic by which accurate traders accumulate wealth and influence while inaccurate ones are driven out -- the market's hypothesized self-improvement mechanism."),
    g("Murphy decomposition", "The exact split of the ensemble Brier score into reliability (calibration error) - resolution (discrimination) + uncertainty (difficulty of the question)."),
    g("No-trade band", "The belief-price gap within which trading isn't worth the transaction cost, so nothing happens. The mechanism of stale prices."),
    g("No-trade theorem (Milgrom-Stokey)", "Rational, risk-averse traders with common priors should not bet against each other on pure information. Why real markets need noise traders, hedgers, or subsidies to generate volume."),
    g("Noise trader", "A trader whose beliefs are unrelated to the truth. Loses on average; that loss is the informed traders' profit."),
    g("Omniscient forecast (p*)", "The posterior probability given all agents' signals at once -- the ceiling on what any aggregation method could achieve."),
    g("Opinion pool", "A direct (non-market) belief-aggregation rule, e.g., the mean, the median, or the extremized logit pool of individual probabilities."),
    g("Pareto distribution", "The standard heavy-tailed wealth distribution; tail index alpha_w, with lower alpha_w meaning more inequality."),
    g("Participation cost (c_part)", "The effort cost of paying attention and trading at all; agents trade only when expected gains exceed it. Load-bearing for the manipulation-helps result."),
    g("Posterior", "A belief after updating on evidence by Bayes' rule."),
    g("Price impact", "How much a trade of a given size moves the price; see Kyle's lambda."),
    g("Prior", "The belief held before seeing any evidence."),
    g("Quadrature", "Deterministic numerical integration; used to compute exact expected Brier scores in the frictionless case instead of simulating."),
    g("Rational expectations equilibrium (REE)", "A price that already incorporates all traders' information, leaving no private informational advantage."),
    g("Resolution", "(of a forecast system) The degree to which forecasts differ between events that occur and don't -- the RES term of the Murphy decomposition. Also: (of a market) the settlement of the contract when the outcome is realized."),
    g("Spoofing", "Posting orders you intend to cancel, to fake supply or demand; an order-book manipulation tactic with no analog against an automated market maker."),
    g("Stale price", "A price that has stopped tracking available information because, given transaction costs, no one finds it worthwhile to correct."),
    g("Subsidy", "The market maker's expected loss, which pays traders to reveal information. LMSR's worst case: b*ln 2."),
    g("Sufficient statistic", "A summary of data that preserves all its information about the unknown -- here, the average signal s-bar.")
  ))
}

# ---- How it works (readable account of plan §1) -----------------------------
pm_guide_how <- function() {
  htmltools::div(
    class = "pm-guide-prose",
    htmltools::HTML("
<h4>The world, and what traders know</h4>
<p>A hidden number &theta; (theta) is the truth &mdash; say, a candidate's true vote share. Nobody sees it. The market trades a <b>binary contract</b> on a yes/no question: does &theta; clear a threshold <i>c</i>? The contract pays $1 if yes and $0 if no, so its fair price is just the probability of yes.</p>
<p>Everyone starts with the same <b>prior</b> (a bell curve for &theta;). Each of the <i>n</i> traders then gets a private <b>signal</b> &mdash; a noisy reading of the truth. The noise is <b>correlated</b>: a fraction &rho; (rho) of it is a <i>shared</i> mistake (a misleading poll, a media narrative) and the rest is each trader's own. Traders update by Bayes' rule to a belief about the event.</p>
<p>Two forecasts bracket the market. The <b>prior</b> p&#8320; is what you'd say with no market at all; any market worth having must beat it. The <b>best possible</b> forecast p&#42; pools <i>all</i> signals at once. The key fact: correlated signals are worth only <b>n_eff = n/(1 + (n&minus;1)&rho;)</b> independent ones, which tends to 1/&rho; as the crowd grows. With &rho; = 0.1, a million traders know at most as much as ten independent ones. <b>Correlation is a hard ceiling on what any market can know.</b> The real question is never &ldquo;is the price accurate?&rdquo; but &ldquo;how much of the gap between the prior and the best possible does it close?&rdquo; &mdash; the <i>accuracy-efficiency</i> AE.</p>

<h4>The market maker</h4>
<p>Trades run against an <b>LMSR</b> automated market maker (Hanson's logarithmic market scoring rule) instead of a matching order book. It always quotes a price in (0,1), and one parameter <b>b</b> (liquidity) sets how much money it takes to move that price. The maker can lose money &mdash; that subsidy is what pays traders to reveal information &mdash; but never more than <b>b&middot;ln 2</b>.</p>

<h4>The traders</h4>
<p>Wealth is heavy-tailed (a few whales), and each trader bets a <b>Kelly</b> fraction of their wealth toward their belief &mdash; the stake that maximizes long-run growth. In the frictionless case theory pins the resting price exactly: the <b>wealth-weighted average of beliefs</b> (Beygelzimer-Langford-Pennock). Rich traders' opinions count for more. Besides <i>informed</i> traders there are <i>noise</i> traders (beliefs unrelated to the truth; they lose on average and thereby pay the informed) and <i>manipulators</i> (who ignore information and push toward a target price).</p>

<h4>Three frictions, three mechanisms</h4>
<p>All three cost parameters make trading costly, but they bite differently:</p>
<ul>
<li><b>Proportional fee &tau;</b> (intensive margin): shrinks every trade, so the price is pulled toward its start &mdash; <i>shrinkage</i>.</li>
<li><b>Fixed cost &kappa;</b> (extensive, per trade): kills small trades entirely &mdash; <i>censoring</i>.</li>
<li><b>Participation cost c_part</b> (extensive, per market, decided <i>before</i> seeing prices): decides who even shows up &mdash; <i>sample selection</i>.</li>
</ul>
<p>All three open a <b>no-trade band</b>: a gap between belief and price too small to be worth trading, which leaves the price <b>stale</b>. Only c_part can cleanly produce the Hanson-Oprea effect (manipulation drawing dormant traders in) &mdash; though in this model, as the Reliability and validation results show, that benefit is elusive.</p>

<h4>Herding</h4>
<p>With herding (weight <i>h</i>), traders partly <b>adopt the price as their own belief</b>. This rewrites the beliefs that feed the price, so a distortion held for a few rounds can <b>outlive</b> the trader who caused it &mdash; a genuine information cascade. With h = 0 the market is unreasonably well-behaved: manipulation is self-defeating and fees only slow things down. Turn <i>h</i> up to see cascades in Run Anatomy.</p>

<h4>What we measure</h4>
<p>Accuracy is the <b>Brier score</b> (squared forecast error; 0.25 is chance), split by the <b>Murphy decomposition</b> into reliability, resolution, and uncertainty. <b>AE</b> rescales Brier between the prior (0) and the best possible (1). The <b>Reliability</b> tab sweeps one parameter; <b>Interactions</b> maps two at once.</p>
")
  )
}

# ---- References (plan §13) --------------------------------------------------
pm_guide_refs <- function() {
  refs <- c(
    "Hanson (2003). Logarithmic market scoring rules for modular combinatorial information aggregation. (LMSR.)",
    "Hanson & Oprea (2009). A Manipulator Can Aid Prediction Market Accuracy. Economica.",
    "Hanson, Oprea & Porter (2006). Information aggregation and manipulation in an experimental market.",
    "Wolfers & Zitzewitz (2006). Interpreting Prediction Market Prices as Probabilities.",
    "Beygelzimer, Langford & Pennock (2012). Learning Performance of Prediction Markets with Kelly Bettors.",
    "Kets, Pennock, Sethi & Shah (2014). Betting Strategies, Market Selection, and the Wisdom of Crowds.",
    "Blume & Easley (2006). If you're so smart, why aren't you rich? Belief selection in complete and incomplete markets.",
    "Kyle (1985). Continuous Auctions and Insider Trading. (Informed trading and market depth.)",
    "Grossman & Stiglitz (1980). On the Impossibility of Informationally Efficient Markets.",
    "Glosten & Milgrom (1985). Bid, ask and transaction prices with heterogeneously informed traders.",
    "Milgrom & Stokey (1982). Information, trade and common knowledge. (No-trade theorem.)",
    "Murphy (1973). A new vector partition of the probability score. (Brier decomposition.)",
    "Snowberg & Wolfers (2010). Explaining the Favorite-Longshot Bias.")
  htmltools::tags$ul(class = "pm-guide-refs", lapply(refs, htmltools::tags$li))
}

# ---- Module -----------------------------------------------------------------
mod_guide_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "pm-tab-body",
    bslib::navset_underline(
      bslib::nav_panel("How it works", tags$div(class = "pm-guide-section", pm_guide_how())),
      bslib::nav_panel("Glossary",
        tags$div(class = "pm-guide-section",
                 tags$p(class = "pm-group-details",
                        "Every term of art in the model, searchable. Type in the box to filter."),
                 DT::dataTableOutput(ns("glossary")))),
      bslib::nav_panel("References",
        tags$div(class = "pm-guide-section",
                 tags$p(class = "pm-group-details", "The literature the model draws on."),
                 pm_guide_refs()))
    )
  )
}

mod_guide_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    output$glossary <- DT::renderDataTable({
      DT::datatable(
        pm_glossary(),
        rownames = FALSE,
        options = list(pageLength = 15, dom = "ft", autoWidth = FALSE,
                       columnDefs = list(list(width = "220px", targets = 0))),
        class = "compact stripe")
    })
  })
}
