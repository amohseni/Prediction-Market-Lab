;; Prediction Market
;; From Politics to Pandemics (66-146), Week 6: Collective Intelligence
;; The same voters as in Wisdom and Madness, but now they bet instead of
;; voting. A hidden yes/no truth is drawn; each informed trader gets a
;; private signal that is right with probability signal-accuracy; traders
;; buy YES or NO shares from an automated market maker (Hanson's
;; logarithmic market scoring rule). The price of a YES share is the
;; market's probability that the answer is YES. One tick = one trade.
;; After trades-per-market trades the truth is revealed, shares pay off,
;; and a new market opens.

breed [traders trader]

globals [
  prior-probability  ; fixed at 0.5
  stake-fraction     ; fixed at 0.2 of wealth per trade
  initial-wealth     ; fixed at 100
  imitation-strength ; fixed at 0.5: how much of the price's last move an imitator expects to continue
  resolved-wealth    ; list of wealth by kind (informed, noise, imitator, manipulator) at the last resolution
  truth-yes?       ; the hidden answer this market
  common-signal    ; the shared signal this market (right with prob. signal-accuracy)
  q-yes q-no       ; shares outstanding
  price            ; price of a YES share = market probability of YES
  p-star           ; the forecast of someone who saw every distinct signal
  crowd-belief     ; average initial belief of informed traders (a poll)
  trade-number     ; trades so far in this market
  markets-done     ; markets resolved so far
  market-brier-sum ; running sums of squared forecast errors
  prior-brier-sum
  crowd-brier-sum
  pstar-brier-sum
  manip-spent      ; what the manipulator has spent this market
  operator-fees    ; fees collected by the market operator
  quiet-trades     ; turns this market in which the chosen trader did not trade
]

traders-own [
  kind             ; "informed", "noise", "imitator", "manipulator"
  signal           ; 1 (YES) or 0 (NO): the private evidence this trader received
  shared?          ; true if this trader's signal was the shared one
  belief-logit     ; the trader's current belief, in log-odds
  last-seen-logit  ; the price (log-odds) when this trader last traded
  wealth
  yes-shares
  no-shares
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  set prior-probability 0.5
  set stake-fraction 0.2
  set initial-wealth 100
  set imitation-strength 0.5
  set resolved-wealth [0 0 0 0]
  set-default-shape traders "circle"
  create-traders num-traders [
    set kind "informed"
    set wealth initial-wealth
  ]
  let n-noise round (share-noise-traders * num-traders)
  ask n-of n-noise traders [ set kind "noise" ]
  let n-imitators min (list (round (share-imitators * num-traders)) (count traders with [ kind = "informed" ]))
  ask n-of n-imitators traders with [ kind = "informed" ] [ set kind "imitator" ]
  if manipulator? [
    create-traders 1 [
      set kind "manipulator"
      set wealth initial-wealth * 10
    ]
  ]
  ask traders [ color-by-kind ]
  set markets-done 0
  set market-brier-sum 0
  set prior-brier-sum 0
  set crowd-brier-sum 0
  set pstar-brier-sum 0
  set operator-fees 0
  new-market
  reset-ticks
end

to new-market
  set truth-yes? (random-float 1 < prior-probability)
  set common-signal ifelse-value (random-float 1 < signal-accuracy) [truth-as-number] [1 - truth-as-number]
  ;; open the market at the prior: q-yes - q-no = b * ln (p / (1 - p))
  set q-no 0
  set q-yes liquidity * logit prior-probability
  update-price
  set trade-number 0
  set manip-spent 0
  set quiet-trades 0
  ask traders [
    set yes-shares 0
    set no-shares 0
    form-belief
  ]
  set p-star pooled-forecast
  ifelse any? traders with [ kind = "informed" ]
    [ set crowd-belief mean [ logistic belief-logit ] of traders with [ kind = "informed" ] ]
    [ set crowd-belief prior-probability ]
  place-traders
end

;; Each trader's starting belief for this market.
to form-belief
  set last-seen-logit logit prior-probability
  set shared? false
  if kind = "informed" [
    ifelse random-float 1 < shared-error [
      set signal common-signal
      set shared? true
    ] [
      set signal ifelse-value (random-float 1 < signal-accuracy) [truth-as-number] [1 - truth-as-number]
    ]
    ;; Bayes: log-odds of YES = prior log-odds + log-likelihood ratio of the signal
    set belief-logit (logit prior-probability) + signal-llr
  ]
  if kind = "noise" [ set belief-logit logit (0.02 + random-float 0.96) ]
  if kind = "imitator" [ set belief-logit logit prior-probability ]
  if kind = "manipulator" [ set belief-logit logit manipulator-target ]
end

;; The log-likelihood ratio a signal carries: + for a YES signal, - for NO.
to-report signal-llr
  report (ifelse-value (signal = 1) [1] [-1]) * ln (signal-accuracy / (1 - signal-accuracy))
end

;; The best forecast available to anyone: add up every distinct signal.
;; Copies of the shared signal count once, because they are one piece of evidence.
to-report pooled-forecast
  let evidence (logit prior-probability) + sum [ signal-llr ] of traders with [ kind = "informed" and not shared? ]
  if any? traders with [ shared? ] [
    set evidence evidence + (ifelse-value (common-signal = 1) [1] [-1]) * ln (signal-accuracy / (1 - signal-accuracy))
  ]
  report logistic evidence
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GO: one trade per tick
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if trade-number >= trades-per-market [
    resolve-market
    new-market
  ]
  ask one-of traders [ trade ]
  set trade-number trade-number + 1
  if ticks mod 5 = 0 [ place-traders ]
  tick
end

to trade
  ;; learn from the price: absorb a share price-trust of the price movement since last look
  let price-logit logit price
  ifelse kind = "imitator"
    ;; an imitator has no signal: they bet that the price's recent move will continue
    [ set belief-logit price-logit + imitation-strength * (price-logit - last-seen-logit) ]
    [ set belief-logit belief-logit + price-trust * (price-logit - last-seen-logit) ]
  set last-seen-logit price-logit
  let target logistic belief-logit
  if kind = "manipulator" [
    set target manipulator-target
    if manip-spent >= manipulator-budget [
      set quiet-trades quiet-trades + 1
      stop
    ]
  ]
  let edge target - price
  if abs edge <= fee [
    set quiet-trades quiet-trades + 1
    stop
  ]
  let budget (stake-fraction * wealth) / (1 + fee)
  if kind = "manipulator" [
    set budget min (list budget ((manipulator-budget - manip-spent) / (1 + fee)))
  ]
  if budget <= 0 [
    set quiet-trades quiet-trades + 1
    stop
  ]
  ifelse edge > 0 [ buy-yes target budget ] [ buy-no target budget ]
  ;; the trader's own trade moved the price; that move is not news to them
  set last-seen-logit logit price
end

to buy-yes [t m]
  let tc clamp t 0.001 0.999
  let x-desired (liquidity * logit tc) - (q-yes - q-no)
  if x-desired <= 0 [ stop ]
  let x affordable x-desired m true
  if x <= 0 [ stop ]
  let cost marginal-cost x true
  set q-yes q-yes + x
  set yes-shares yes-shares + x
  set wealth wealth - cost * (1 + fee)
  set operator-fees operator-fees + cost * fee
  if kind = "manipulator" [ set manip-spent manip-spent + cost ]
  update-price
end

to buy-no [t m]
  let tc clamp t 0.001 0.999
  let x-desired (liquidity * logit (1 - tc)) - (q-no - q-yes)
  if x-desired <= 0 [ stop ]
  let x affordable x-desired m false
  if x <= 0 [ stop ]
  let cost marginal-cost x false
  set q-no q-no + x
  set no-shares no-shares + x
  set wealth wealth - cost * (1 + fee)
  set operator-fees operator-fees + cost * fee
  if kind = "manipulator" [ set manip-spent manip-spent + cost ]
  update-price
end

;; The largest number of shares up to x that budget m can buy (bisection).
to-report affordable [x m yes?]
  if (marginal-cost x yes?) <= m [ report x ]
  let lo 0
  let hi x
  repeat 25 [
    let mid (lo + hi) / 2
    ifelse (marginal-cost mid yes?) <= m [ set lo mid ] [ set hi mid ]
  ]
  report lo
end

to-report marginal-cost [x yes?]
  ifelse yes?
    [ report (cost-of (q-yes + x) q-no) - (cost-of q-yes q-no) ]
    [ report (cost-of q-yes (q-no + x)) - (cost-of q-yes q-no) ]
end

;; Hanson's LMSR cost function, computed stably.
to-report cost-of [qy qn]
  let mx max (list qy qn)
  report mx + liquidity * ln (exp ((qy - mx) / liquidity) + exp ((qn - mx) / liquidity))
end

to update-price
  set price 1 / (1 + exp ((q-no - q-yes) / liquidity))
end

to resolve-market
  let outcome truth-as-number
  ask traders [
    set wealth wealth + (ifelse-value truth-yes? [yes-shares] [no-shares])
    set yes-shares 0
    set no-shares 0
  ]
  set markets-done markets-done + 1
  set resolved-wealth map [k -> wealth-of k] ["informed" "noise" "imitator" "manipulator"]
  set market-brier-sum market-brier-sum + (price - outcome) ^ 2
  set prior-brier-sum prior-brier-sum + (prior-probability - outcome) ^ 2
  set crowd-brier-sum crowd-brier-sum + (crowd-belief - outcome) ^ 2
  set pstar-brier-sum pstar-brier-sum + (p-star - outcome) ^ 2
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DISPLAY
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Traders sit at x = their current belief (0 at left, 1 at right), in rows by kind;
;; size shows wealth. The yellow column is the price; the white column is p*.
to place-traders
  let width (max-pxcor - min-pxcor)
  ask traders [
    set xcor min-pxcor + width * (logistic belief-logit)
    set ycor (ifelse-value (kind = "informed") [7] [ifelse-value (kind = "imitator") [2.5] [ifelse-value (kind = "noise") [-2.5] [-7]]]) + random-float 1.6 - 0.8
    set size clamp (0.6 + 1.2 * wealth / initial-wealth) 0.3 5
  ]
  let price-col round (min-pxcor + width * price)
  let pstar-col round (min-pxcor + width * p-star)
  ask patches [
    set pcolor ifelse-value (pxcor = price-col) [yellow] [ifelse-value (pxcor = pstar-col) [white] [black]]
  ]
end

to color-by-kind
  if kind = "informed" [ set color blue ]
  if kind = "noise" [ set color gray ]
  if kind = "imitator" [ set color orange ]
  if kind = "manipulator" [ set color red ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REPORTERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report truth-as-number
  report ifelse-value truth-yes? [1] [0]
end

to-report total-wealth
  report sum [ wealth ] of traders
end

to-report wealth-of [k]
  report sum [ wealth ] of traders with [ kind = k ]
end

;; Average change in wealth per resolved market for traders of kind k, in dollars.
;; Positive: that kind has been taking money from the others (and from the operator's subsidy).
to-report gain-per-market [k]
  if (not any? traders with [ kind = k ]) or (markets-done = 0) [ report 0 ]
  let start ifelse-value (k = "manipulator") [initial-wealth * 10] [initial-wealth]
  let w item (position k ["informed" "noise" "imitator" "manipulator"]) resolved-wealth
  report (w - start * (count traders with [ kind = k ])) / markets-done
end

to-report market-brier
  report ifelse-value (markets-done = 0) [0] [market-brier-sum / markets-done]
end

to-report prior-brier
  report ifelse-value (markets-done = 0) [0] [prior-brier-sum / markets-done]
end

to-report crowd-brier
  report ifelse-value (markets-done = 0) [0] [crowd-brier-sum / markets-done]
end

to-report pstar-brier
  report ifelse-value (markets-done = 0) [0] [pstar-brier-sum / markets-done]
end

to-report logit [p]
  let pc clamp p 0.0001 0.9999
  report ln (pc / (1 - pc))
end

to-report logistic [l]
  report 1 / (1 + exp (0 - l))
end

to-report clamp [x lo hi]
  report max (list lo (min (list x hi)))
end
@#$#@#$#@
GRAPHICS-WINDOW
560
10
980
115
-1
-1
4.0
1
10
1
1
1
0
0
0
1
-50
50
-10
10
0
0
1
ticks
30.0

BUTTON
10
10
90
43
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
95
10
175
43
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
180
10
260
43
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

TEXTBOX
10
50
260
68
Information
13
0.0
1

SLIDER
10
70
260
103
num-traders
num-traders
5
300
50.0
5
1
NIL
HORIZONTAL

SLIDER
10
110
260
143
signal-accuracy
signal-accuracy
0.5
0.99
0.6
0.01
1
NIL
HORIZONTAL

SLIDER
10
150
260
183
shared-error
shared-error
0
1
0.0
0.05
1
NIL
HORIZONTAL

SLIDER
10
190
260
223
price-trust
price-trust
0
1
1.0
0.05
1
NIL
HORIZONTAL

TEXTBOX
10
228
260
246
Market
13
0.0
1

SLIDER
10
250
260
283
liquidity
liquidity
1
200
20.0
1
1
NIL
HORIZONTAL

SLIDER
10
290
260
323
fee
fee
0
0.3
0.0
0.01
1
NIL
HORIZONTAL

SLIDER
10
330
260
363
trades-per-market
trades-per-market
10
2000
200.0
10
1
NIL
HORIZONTAL

TEXTBOX
275
50
545
68
Traders
13
0.0
1

SLIDER
275
70
545
103
share-noise-traders
share-noise-traders
0
1
0.0
0.05
1
NIL
HORIZONTAL

SWITCH
275
110
545
143
manipulator?
manipulator?
1
1
-1000

SLIDER
275
150
545
183
manipulator-target
manipulator-target
0.05
0.95
0.9
0.05
1
NIL
HORIZONTAL

SLIDER
275
190
545
223
manipulator-budget
manipulator-budget
0
1000
50.0
10
1
$ per market
HORIZONTAL

SLIDER
275
230
545
263
share-imitators
share-imitators
0
0.9
0.0
0.05
1
NIL
HORIZONTAL

MONITOR
275
275
408
320
manipulator gain/market
gain-per-market "manipulator"
1
1
11

MONITOR
412
275
545
320
informed gain/market
gain-per-market "informed"
1
1
11

MONITOR
275
355
365
400
price
price
3
1
11

MONITOR
370
355
455
400
p* (pooled)
p-star
3
1
11

MONITOR
460
355
545
400
truth: YES?
truth-yes?
0
1
11

MONITOR
275
405
365
450
markets done
markets-done
0
1
11

MONITOR
370
405
455
450
market Brier
market-brier
3
1
11

MONITOR
460
405
545
450
prior Brier
prior-brier
3
1
11

MONITOR
275
455
365
500
poll Brier
crowd-brier
3
1
11

MONITOR
370
455
455
500
p* Brier
pstar-brier
3
1
11

MONITOR
460
455
545
500
operator fees
operator-fees
1
1
11

PLOT
560
125
980
305
Price path (this market)
trade
price
0.0
10.0
0.0
1.0
true
true
"" "if trade-number = 1 [ clear-plot ]"
PENS
"price" 1.0 0 -1184463 true "" "plot price"
"p* (pooled)" 1.0 0 -16777216 true "" "plot p-star"
"outcome" 1.0 0 -2674135 true "" "plot truth-as-number"

PLOT
560
315
980
495
Forecast error (Brier, lower is better)
market
Brier
0.0
10.0
0.0
0.3
true
true
"" ""
PENS
"market" 1.0 0 -1184463 true "" "plotxy markets-done market-brier"
"prior" 1.0 0 -7500403 true "" "plotxy markets-done prior-brier"
"poll of traders" 1.0 0 -13345367 true "" "plotxy markets-done crowd-brier"
"p* (pooled)" 1.0 0 -16777216 true "" "plotxy markets-done pstar-brier"

PLOT
10
540
545
700
Wealth by trader type
trade
wealth
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"informed" 1.0 0 -13345367 true "" "plot wealth-of \"informed\""
"noise" 1.0 0 -7500403 true "" "plot wealth-of \"noise\""
"imitator" 1.0 0 -955883 true "" "plot wealth-of \"imitator\""
"manipulator" 1.0 0 -2674135 true "" "plot wealth-of \"manipulator\""

TEXTBOX
560
505
980
575
View: traders sit at x = their current belief (0 left, 1 right); rows from top: informed (blue), imitators (orange), noise (gray), manipulator (red). Size = wealth. Yellow column = price; white column = p*, the pooled forecast.
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

A prediction market is a betting market on whether something will happen. The price of a share that pays $1 if the event happens can be read as the market's probability that it happens. This model shows how such a market turns the scattered, noisy evidence of many traders into one forecast, and what breaks it.

The traders are the voters of the Wisdom and Madness model: each has a private signal that is right with probability `signal-accuracy`, and a share `shared-error` of them hold copies of one shared signal instead of independent evidence. Instead of voting, they bet.

## HOW IT WORKS

**The event.** Each market, the hidden answer is YES or NO with equal probability.

**Beliefs.** An informed trader starts with the Bayesian belief given their own signal: prior log-odds plus the signal's log-likelihood ratio. Noise traders start with a random belief. Imitators (share `share-imitators` of the traders) have no signal at all: each time they trade, they bet that the price's move since they last looked will continue (they expect half of the move to happen again), so they chase trends and can push the price past the evidence. The manipulator, if switched on, wants the price at `manipulator-target` and will spend up to `manipulator-budget` dollars per market pushing it there (and never more than `stake-fraction` of their wealth per trade).

**Learning from the price.** When a trader comes to trade, they see how far the price has moved since they last looked, and absorb a share `price-trust` of that movement into their own belief (in log-odds). With `price-trust` = 1 a trader treats every price move as information: on their first trade they add their own evidence on top of the price, and after that they trust the price completely. With `price-trust` = 0 a trader ignores the price and always bets toward their private belief. Values in between blend the two.

**The market maker.** Traders trade with an automated market maker that always quotes a price, using Hanson's logarithmic market scoring rule with liquidity parameter `liquidity`. Buying YES shares raises the price; buying NO shares lowers it. A trader whose belief differs from the price buys toward their belief, spending at most a fifth of their wealth per trade and paying `fee` on each trade; they skip trades whose edge is smaller than the fee.

**Resolution.** After `trades-per-market` trades the answer is revealed. YES shares pay $1 if YES, NO shares pay $1 if NO. Wealth carries over to the next market, so good forecasters grow and bad ones shrink.

**Scoring.** The Brier score is the squared error of a probability forecast (0 is perfect; guessing 0.5 scores 0.25). The monitors compare four forecasters across markets: the market's final price; the prior (no evidence); a poll (the average starting belief of informed traders); and p*, the forecast someone who saw every distinct signal would make (copies of the shared signal count once). No forecaster can beat p* on average, and p* gets worse as `shared-error` rises. The two gain monitors report the average change in wealth per resolved market for the manipulator and for the informed traders: where the manipulator's money goes.

## HOW TO USE IT

Press `setup`, then `go`. Watch the price path chase p* within each market, then let it run for 50 or more markets before comparing Brier scores.

## THINGS TO NOTICE

With default settings (50 traders, accuracy 0.6, price-trust 1), the market's price reaches p* almost exactly: each trader adds their evidence once and the price sums it all. The poll is far worse: averaging beliefs is not the same as adding up evidence.

Set `price-trust` to 0. The market becomes a tug of war between private beliefs and the price ends up near the average belief.

Raise `shared-error` with `price-trust` 1. The price now double-counts the shared signal and becomes overconfident: the market Brier rises above p*.

Switch on the manipulator. With `price-trust` 1 every trader reads the manipulator's push as news, so the push stays in the price and the market is badly wrong until the manipulator runs out of money. Lower `price-trust` makes traders push back, but also stops them adding up evidence. More traders and more liquidity make the push more expensive and shorter-lived; the gain monitors show the manipulator losing and the informed traders collecting.

Set `share-imitators` to 0.5. Imitators chase the last move, so a price that starts toward the truth overshoots it, and one that starts the wrong way runs further wrong; the market Brier rises and the price path swings.

## THINGS TO TRY

See the exploration questions in the course handout.

## EXTENDING THE MODEL

Ideas for group projects: let traders decide how much to trust the price by learning from experience; let some traders buy signals at a cost (how much information does the market pay for?); add a second event whose answer is correlated with the first; let traders enter and leave; replace the market maker with an order book where traders trade with each other.

## CREDITS AND REFERENCES

Hanson (2003), "Combinatorial information market design," Information Systems Frontiers 5: 107-119. Wolfers and Zitzewitz (2004), "Prediction markets," Journal of Economic Perspectives 18: 107-126. Hanson and Oprea (2009), "A manipulator can aid prediction market accuracy," Economica 76: 304-314.

A richer, continuous-signal version of this setting is Aydin Mohseni's Prediction Markets Lab: https://amohseni.shinyapps.io/Prediction-Markets-Lab/

Model written for 66-146 From Politics to Pandemics, Carnegie Mellon University, Fall 2026.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

circle
false
0
Circle -7500403 true true 0 0 300
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="trust-and-shared-error" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="20000"/>
    <metric>market-brier</metric>
    <metric>prior-brier</metric>
    <metric>crowd-brier</metric>
    <metric>pstar-brier</metric>
    <enumeratedValueSet variable="price-trust">
      <value value="0"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="shared-error">
      <value value="0"/>
      <value value="0.3"/>
      <value value="0.6"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
