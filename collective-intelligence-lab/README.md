# Collective Intelligence Lab

Teaching materials for Week 6 of 66-146 From Politics to Pandemics (Carnegie Mellon, Fall 2026): collective intelligence, the Condorcet jury theorem, the wisdom and madness of crowds, and prediction markets. Built alongside the Prediction Market Lab Shiny app in this repository, which covers the market side with continuous signals.

## Contents

- `collective-intelligence-lab.html`: a single-file web page (HTML, CSS, JavaScript; no libraries; canvas charts). Four tabs. Experiments: a three-round class experiment on guessing a book's page count (private guesses, guesses out loud, a class prediction market on a market maker). Lessons: seven step-by-step lessons (averaging; voting and cascades; prediction markets; one crowd under every mechanism; better than the mean: weighting, extremizing, the surprisingly popular rule; scoring and calibration; talking without herding), each ending in three self-check questions. Simulations: Condorcet, informational cascades, social influence. Evidence: a scoreboard of field results for each claim. The page runs from a file in any browser; a hosted copy is at https://claude.ai/artifact/DSpbWLNFMtbtByQLrcBjNT (private until shared).
- `WisdomAndMadness.nlogo`: a NetLogo 6.4 jury model. Voters with a private signal vote simultaneously, in sequence (rational or naive herding), or after talking on a small-world network. Sliders for crowd size, competence and its spread, shared error, network degree and rewiring, talk rounds, and conformity. Monitors for majority accuracy, average voter accuracy, the exact Condorcet prediction, the first herded voter, the share who ignored their own signal, and agreement.
- `PredictionMarket.nlogo`: the same voters bet instead of voting, against a logarithmic market scoring rule market maker. Sliders for traders, signal accuracy, shared error, trust in the price, liquidity, fee, trades per market, noise traders, imitators, and a manipulator with a target and a budget. Monitors compare the market's Brier score with the prior, a poll of the traders, and p*, the forecast from every distinct signal; gain monitors show where the manipulator's money goes.
- `port_jury.py`, `port_market.py`: Python ports of the two models used for parameter sweeps.

Both models run in NetLogo Web (https://www.netlogoweb.org/launch, Upload a Model) without installing anything.
