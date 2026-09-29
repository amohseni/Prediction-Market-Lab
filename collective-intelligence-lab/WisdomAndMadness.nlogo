;; Wisdom and Madness of Crowds
;; From Politics to Pandemics (66-146), Week 6: Collective Intelligence
;; A jury of agents votes on a yes/no question. The model lets you vary
;; how good each voter is, how much their errors overlap, and whether they
;; vote independently, in sequence (seeing earlier votes), or after talking
;; to their neighbors. One tick = one trial (one question decided).

globals [
  truth                     ; 1 or 0: the true answer this trial
  common-signal             ; the shared signal this trial (correct with prob. competence)
  trials                    ; completed trials
  majority-correct-trials   ; trials in which the majority vote was correct
  sum-individual-accuracy   ; running sum of the share of voters who were correct
  last-majority-correct?    ; result of the last trial
  last-share-correct        ; share of voters correct in the last trial
  sum-agreement             ; running sum of the share of voters who voted with the majority
  net-evidence              ; sequential (rational) bookkeeping: informative votes for 1 minus for 0
  votes-for-1               ; sequential (naive) bookkeeping
  votes-for-0
  cascade-started-at        ; voting position of the first voter who ignored their own signal, or -1
]

turtles-own [
  competence-i   ; probability this voter's private signal is correct
  offset-unit    ; this voter's place in the competence spread, from -1 to 1
  signal         ; 1 or 0: the private evidence this voter received
  vote           ; 1 or 0: what this voter finally voted
  next-vote      ; scratch variable for synchronous updating in talk mode
  cascaded?      ; true if the voter's vote differs from their own signal
  order          ; voting position, 0 to n - 1
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  create-turtles num-voters [
    set shape "circle"
    set size 1.3
    set offset-unit (random-float 2) - 1
    set competence-i clamp (competence + competence-spread * offset-unit) 0.01 0.99
    set cascaded? false
    set vote 0
    set signal 0
  ]
  ask turtles [ set order who ]
  layout-circle sort-on [order] turtles (max-pxcor - 3)
  build-network
  set trials 0
  set majority-correct-trials 0
  set sum-individual-accuracy 0
  set last-majority-correct? false
  set last-share-correct 0
  set sum-agreement 0
  set cascade-started-at -1
  set truth 0
  reset-ticks
end

;; ring lattice with network-degree neighbors, then random rewiring
to build-network
  let n count turtles
  let k max (list 1 floor (network-degree / 2))
  ask turtles [
    let me order
    foreach (range 1 (k + 1)) [ d ->
      let partner one-of turtles with [ order = ((me + d) mod n) ]
      if partner != nobody and partner != self [ create-link-with partner ]
    ]
  ]
  ask links [
    if random-float 1 < rewiring-probability [
      let a end1
      let candidates turtles with [ self != a and not link-neighbor? a ]
      if any? candidates [
        let b one-of candidates
        ask a [ create-link-with b ]
        die
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GO: one trial per tick
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  run-trial
  record-trial
  tick
end

to run-trial
  set truth ifelse-value (random-float 1 < 0.5) [1] [0]
  set common-signal ifelse-value (random-float 1 < competence) [truth] [1 - truth]
  ask links [ set hidden? (voting != "talk first (network)") ]
  ask turtles [
    set competence-i clamp (competence + competence-spread * offset-unit) 0.01 0.99
    ifelse random-float 1 < shared-error
      [ set signal common-signal ]
      [ set signal ifelse-value (random-float 1 < competence-i) [truth] [1 - truth] ]
    set vote signal
    set cascaded? false
  ]
  set cascade-started-at -1
  if voting = "sequential (rational)" [ vote-sequentially-rational ]
  if voting = "sequential (naive)" [ vote-sequentially-naive ]
  if voting = "talk first (network)" [ talk ]
  ask turtles [ set cascaded? (vote != signal) ]
  color-voters
end

;; Bikhchandani, Hirshleifer and Welch (1992): each voter sees all earlier votes.
;; Votes made inside a cascade carry no information, and later voters know it.
;; Once the informative votes lean two or more one way, everyone follows.
to vote-sequentially-rational
  set net-evidence 0
  foreach sort-on [order] turtles [ t ->
    ask t [
      ifelse abs net-evidence >= 2 [
        set vote ifelse-value (net-evidence > 0) [1] [0]
        if cascade-started-at = -1 [ set cascade-started-at order ]
      ] [
        set vote signal
        set net-evidence net-evidence + (ifelse-value (signal = 1) [1] [-1])
      ]
    ]
  ]
end

;; Naive voters treat every earlier vote as if it were an independent signal.
to vote-sequentially-naive
  set votes-for-1 0
  set votes-for-0 0
  foreach sort-on [order] turtles [ t ->
    ask t [
      let evidence (votes-for-1 - votes-for-0) + (ifelse-value (signal = 1) [1] [-1])
      set vote ifelse-value (evidence > 0) [1] [ifelse-value (evidence < 0) [0] [signal]]
      if vote != signal and cascade-started-at = -1 [ set cascade-started-at order ]
      ifelse vote = 1 [ set votes-for-1 votes-for-1 + 1 ] [ set votes-for-0 votes-for-0 + 1 ]
    ]
  ]
end

;; Voters talk before voting: each round, with probability conformity,
;; a voter adopts the majority view among their network neighbors.
to talk
  repeat talk-rounds [
    ask turtles [
      let nbrs link-neighbors
      ifelse any? nbrs and random-float 1 < conformity [
        let ones count nbrs with [ vote = 1 ]
        let zeros (count nbrs) - ones
        set next-vote ifelse-value (ones > zeros) [1] [ifelse-value (zeros > ones) [0] [vote]]
      ] [
        set next-vote vote
      ]
    ]
    ask turtles [ set vote next-vote ]
  ]
end

to record-trial
  let ones count turtles with [ vote = 1 ]
  let zeros (count turtles) - ones
  let majority 0
  ifelse ones > zeros [ set majority 1 ] [
    ifelse zeros > ones [ set majority 0 ] [ set majority random 2 ]
  ]
  set last-majority-correct? (majority = truth)
  set last-share-correct (count turtles with [ vote = truth ]) / (count turtles)
  set trials trials + 1
  if last-majority-correct? [ set majority-correct-trials majority-correct-trials + 1 ]
  set sum-individual-accuracy sum-individual-accuracy + last-share-correct
  set sum-agreement sum-agreement + (max (list ones zeros)) / (count turtles)
end

to color-voters
  ask turtles [
    set color ifelse-value (vote = truth) [green] [red]
    set shape ifelse-value cascaded? ["square"] ["circle"]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REPORTERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report majority-accuracy
  report ifelse-value (trials = 0) [0] [majority-correct-trials / trials]
end

to-report individual-accuracy
  report ifelse-value (trials = 0) [0] [sum-individual-accuracy / trials]
end

;; How much the voters agree: the average share of voters on the majority side.
;; 0.5 means an even split every time; 1 means unanimity every time.
to-report agreement
  report ifelse-value (trials = 0) [0] [sum-agreement / trials]
end

;; Condorcet's prediction for independent voters of equal competence:
;; the probability that a binomial majority is correct (ties split evenly).
to-report condorcet-prediction
  let n count turtles
  if n = 0 [ report 0 ]
  let p competence
  let k (floor (n / 2)) + 1
  let total 0
  let j k
  while [ j <= n ] [
    set total total + binomial-prob n j p
    set j j + 1
  ]
  if n mod 2 = 0 [ set total total + 0.5 * binomial-prob n (n / 2) p ]
  report min (list 1 total)
end

to-report binomial-prob [n j p]
  report exp (log-choose n j + j * ln p + (n - j) * ln (1 - p))
end

to-report log-choose [n j]
  report (log-factorial n) - (log-factorial j) - (log-factorial (n - j))
end

to-report log-factorial [m]
  let s 0
  let i 2
  while [ i <= m ] [
    set s s + ln i
    set i i + 1
  ]
  report s
end

to-report clamp [x lo hi]
  report max (list lo (min (list x hi)))
end

to-report share-cascaded
  report ifelse-value (count turtles = 0) [0] [(count turtles with [ cascaded? ]) / (count turtles)]
end
@#$#@#$#@
GRAPHICS-WINDOW
455
10
875
431
-1
-1
12.5
1
10
1
1
1
0
0
0
1
-16
16
-16
16
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

SLIDER
10
55
260
88
num-voters
num-voters
3
301
51.0
2
1
NIL
HORIZONTAL

SLIDER
10
95
260
128
competence
competence
0.3
0.99
0.6
0.01
1
NIL
HORIZONTAL

SLIDER
10
135
260
168
competence-spread
competence-spread
0
0.45
0.0
0.05
1
NIL
HORIZONTAL

SLIDER
10
175
260
208
shared-error
shared-error
0
1
0.0
0.05
1
NIL
HORIZONTAL

CHOOSER
10
220
260
265
voting
voting
"simultaneous" "sequential (rational)" "sequential (naive)" "talk first (network)"
0

SLIDER
10
275
260
308
network-degree
network-degree
2
20
4.0
2
1
NIL
HORIZONTAL

SLIDER
10
315
260
348
rewiring-probability
rewiring-probability
0
1
0.0
0.05
1
NIL
HORIZONTAL

SLIDER
10
355
260
388
talk-rounds
talk-rounds
0
30
5.0
1
1
NIL
HORIZONTAL

SLIDER
10
395
260
428
conformity
conformity
0
1
0.5
0.05
1
NIL
HORIZONTAL

MONITOR
270
55
445
100
majority accuracy
majority-accuracy
3
1
11

MONITOR
270
105
445
150
average voter accuracy
individual-accuracy
3
1
11

MONITOR
270
155
445
200
Condorcet prediction
condorcet-prediction
3
1
11

MONITOR
270
205
355
250
trials
trials
0
1
11

MONITOR
360
205
445
250
truth
truth
0
1
11

MONITOR
270
255
445
300
first cascaded voter (position)
cascade-started-at
0
1
11

MONITOR
270
305
445
350
share who ignored own signal
share-cascaded
3
1
11

PLOT
10
440
445
620
Accuracy over trials
trial
accuracy
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"majority" 1.0 0 -13345367 true "" "plot majority-accuracy"
"average voter" 1.0 0 -7500403 true "" "plot individual-accuracy"
"Condorcet" 1.0 0 -2674135 true "" "plot condorcet-prediction"

PLOT
455
440
875
620
Share of votes correct, this trial
trial
share
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"share correct" 1.0 0 -10899396 true "" "plot last-share-correct"

MONITOR
270
355
445
400
agreement (share with majority)
agreement
3
1
11

TEXTBOX
270
403
445
438
Green: right. Red: wrong. Squares: voted against own signal (herded).
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

A jury of voters decides a yes/no question by majority vote. Each voter receives a private signal (a piece of evidence) that is correct with some probability. The model lets you change three things and watch what happens to the accuracy of the majority:

1. **How good each voter is** (competence), and how much voters differ (competence-spread).
2. **How much their errors overlap** (shared-error): the probability that a voter's signal is a copy of one shared signal rather than an independent draw.
3. **How they vote**: all at once and independently (Condorcet's setting), one after another while seeing earlier votes (information cascades), or after talking to neighbors on a network (conformity).

One tick is one trial: a new truth is drawn, signals are drawn, votes are cast, and the majority is scored. The monitors report running averages over trials.

## HOW IT WORKS

**Signals.** Each trial, the truth is 1 or 0 with equal probability. One shared signal is drawn, correct with probability `competence`. Each voter then, with probability `shared-error`, copies the shared signal; otherwise they draw their own private signal, correct with probability `competence-i` (their own competence, drawn once at setup from `competence` plus or minus `competence-spread`).

**Voting rules.**

- *simultaneous*: everyone votes their own signal.
- *sequential (rational)*: voters vote in order, each seeing all earlier votes. A voter counts only the votes that carried information. Once the informative votes lean two or more in one direction, the voter's own signal cannot outweigh them, so they follow the crowd, and every later voter does the same. This is the information cascade of Bikhchandani, Hirshleifer and Welch (1992).
- *sequential (naive)*: as above, but voters treat every earlier vote as an independent signal, including votes that were themselves copied.
- *talk first (network)*: voters sit on a ring network with `network-degree` neighbors each, rewired at random with probability `rewiring-probability`. For `talk-rounds` rounds, each voter, with probability `conformity`, adopts the majority view among their neighbors. Then they vote.

**Scoring.** Ties are broken by coin flip. `majority accuracy` is the share of trials in which the majority was right. `average voter accuracy` is the mean share of voters who were right. `agreement` is the mean share of voters on the majority side (0.5 is an even split, 1 is unanimity); talking raises it whether or not accuracy rises. `Condorcet prediction` is the exact probability that a majority of `num-voters` independent voters of competence `competence` is right.

## HOW TO USE IT

Press `setup`, then `go`. Let the trial count reach a few hundred before reading the monitors; the plot shows the running averages settling. Competence, spread, shared error, the voting rule, talk rounds, and conformity can be changed while the model runs (the running averages then mix the old and new settings; press `setup` to start the averages fresh). Changing num-voters, network-degree, or rewiring-probability takes effect at the next `setup`.

Squares in the view are voters whose final vote differs from their own signal. In the sequential modes the monitor `first cascaded voter` reports the position at which the cascade began.

## THINGS TO NOTICE

With the default settings (51 voters, competence 0.6, independent, simultaneous), the majority is right about 92% of the time even though each voter is right only 60% of the time. Try 3 voters, then 11, then 101.

Move `shared-error` up. The majority's accuracy falls toward the competence of the shared signal, no matter how many voters there are.

Switch to `sequential (rational)`. Watch how early the cascade starts and how often the whole crowd locks onto the wrong answer.

## THINGS TO TRY

See the exploration questions in the course handout. Some starting points: What competence makes 101 voters worse than one? What does talking do when signals are independent, and when they are shared? Can a network make the crowd smarter than independent voting?

## EXTENDING THE MODEL

Ideas for group projects: let voters have different competences and give the good ones more weight (weighted majority); let voters choose whether to look at their own evidence (costly) or copy others (free); let the network rewire toward like-minded voters (echo chambers); replace the yes/no question with a number to estimate and average the guesses; add a persuasive voter who always votes the same way.

## CREDITS AND REFERENCES

Condorcet (1785), Essai sur l'application de l'analyse. Bikhchandani, Hirshleifer and Welch (1992), "A theory of fads, fashion, custom, and cultural change as informational cascades," Journal of Political Economy 100: 992-1026. Lorenz, Rauhut, Schweitzer and Helbing (2011), "How social influence can undermine the wisdom of crowd effect," PNAS 108: 9020-9025.

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

square
false
0
Rectangle -7500403 true true 30 30 270 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="condorcet-sweep" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>majority-accuracy</metric>
    <metric>individual-accuracy</metric>
    <metric>condorcet-prediction</metric>
    <enumeratedValueSet variable="num-voters">
      <value value="3"/>
      <value value="11"/>
      <value value="51"/>
      <value value="101"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="competence">
      <value value="0.45"/>
      <value value="0.55"/>
      <value value="0.6"/>
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="shared-error">
      <value value="0"/>
      <value value="0.3"/>
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="voting">
      <value value="&quot;simultaneous&quot;"/>
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
