"""Python port of PredictionMarket.nlogo, used to compute the answer-key numbers.
Same logic as the NetLogo model, trade for trade. Run: python3 port_market.py [sweep-name|all]
"""
import math, random, statistics, sys

def clamp(x, lo, hi):
    return max(lo, min(x, hi))

def logit(p):
    pc = clamp(p, 0.0001, 0.9999)
    return math.log(pc / (1 - pc))

def logistic(l):
    return 1 / (1 + math.exp(-l))

DEFAULTS = dict(num_traders=50, signal_accuracy=0.6, shared_error=0.0, prior_probability=0.5, price_trust=1.0,
                liquidity=20.0, fee=0.0, stake_fraction=0.2, initial_wealth=100.0, trades_per_market=200,
                share_noise_traders=0.0, share_imitators=0.0, imitation_strength=0.5,
                manipulator=False, manipulator_target=0.9, manipulator_budget=50.0, manipulator_wealth_multiple=10)

class Market:
    def __init__(self, seed=None, **kw):
        self.p = dict(DEFAULTS); self.p.update(kw)
        self.rng = random.Random(seed)
        p = self.p
        n = p['num_traders']
        kinds = ['informed'] * n
        n_noise = round(p['share_noise_traders'] * n)
        n_imit = min(round(p['share_imitators'] * n), n - n_noise)
        idx = list(range(n)); self.rng.shuffle(idx)
        for i in idx[:n_noise]: kinds[i] = 'noise'
        informed_idx = [i for i in range(n) if kinds[i] == 'informed']; self.rng.shuffle(informed_idx)
        for i in informed_idx[:n_imit]: kinds[i] = 'imitator'
        self.traders = [dict(kind=k, wealth=p['initial_wealth'], signal=0, shared=False, bl=0.0, seen=0.0, yes=0.0, no=0.0) for k in kinds]
        if p['manipulator']:
            self.traders.append(dict(kind='manipulator', wealth=p['initial_wealth'] * p['manipulator_wealth_multiple'], signal=0, shared=False, bl=0.0, seen=0.0, yes=0.0, no=0.0))
        self.markets_done = 0
        self.sums = dict(market=0.0, prior=0.0, crowd=0.0, pstar=0.0)
        self.operator_fees = 0.0
        self.final_prices = []
        self.new_market()

    def llr_of(self, sig):
        q = self.p['signal_accuracy']
        return (1 if sig == 1 else -1) * math.log(q / (1 - q))

    def new_market(self):
        p = self.p; r = self.rng
        self.truth = r.random() < p['prior_probability']
        t = 1 if self.truth else 0
        self.common = t if r.random() < p['signal_accuracy'] else 1 - t
        self.q_no = 0.0
        self.q_yes = p['liquidity'] * logit(p['prior_probability'])
        self.update_price()
        self.price_history = [self.price]
        self.trade_number = 0
        self.manip_spent = 0.0
        self.quiet = 0
        for tr in self.traders:
            tr['yes'] = tr['no'] = 0.0
            tr['seen'] = logit(p['prior_probability'])
            tr['shared'] = False
            if tr['kind'] == 'imitator':
                tr['bl'] = logit(p['prior_probability'])
            elif tr['kind'] == 'informed':
                if r.random() < p['shared_error']:
                    tr['signal'] = self.common; tr['shared'] = True
                else:
                    tr['signal'] = t if r.random() < p['signal_accuracy'] else 1 - t
                tr['bl'] = logit(p['prior_probability']) + self.llr_of(tr['signal'])
            elif tr['kind'] == 'noise':
                tr['bl'] = logit(0.02 + r.random() * 0.96)
            else:
                tr['bl'] = logit(p['manipulator_target'])
        ev = logit(p['prior_probability'])
        for tr in self.traders:
            if tr['kind'] == 'informed' and not tr['shared']:
                ev += self.llr_of(tr['signal'])
        if any(tr['shared'] for tr in self.traders):
            ev += self.llr_of(self.common)
        self.p_star = logistic(ev)
        informed = [tr for tr in self.traders if tr['kind'] == 'informed']
        self.crowd_belief = statistics.mean(logistic(tr['bl']) for tr in informed) if informed else p['prior_probability']

    def cost_of(self, qy, qn):
        b = self.p['liquidity']; mx = max(qy, qn)
        return mx + b * math.log(math.exp((qy - mx) / b) + math.exp((qn - mx) / b))

    def update_price(self):
        self.price = 1 / (1 + math.exp((self.q_no - self.q_yes) / self.p['liquidity']))

    def marginal_cost(self, x, yes):
        base = self.cost_of(self.q_yes, self.q_no)
        return (self.cost_of(self.q_yes + x, self.q_no) if yes else self.cost_of(self.q_yes, self.q_no + x)) - base

    def affordable(self, x, m, yes):
        if self.marginal_cost(x, yes) <= m: return x
        lo, hi = 0.0, x
        for _ in range(25):
            mid = (lo + hi) / 2
            if self.marginal_cost(mid, yes) <= m: lo = mid
            else: hi = mid
        return lo

    def total_wealth(self):
        return sum(t['wealth'] for t in self.traders)

    def imitator_target(self):
        past = self.price_history[0]; s = self.p['imitation_strength']
        return clamp(self.price + s, 0.001, 0.999) if self.price >= past else clamp(self.price - s, 0.001, 0.999)

    def trade(self, t):
        p = self.p
        pl = logit(self.price)
        if t['kind'] == 'imitator':
            # no signal: bet that a share imitation_strength of the price's move since last look will continue
            t['bl'] = pl + p['imitation_strength'] * (pl - t['seen'])
        else:
            t['bl'] += p['price_trust'] * (pl - t['seen'])
        t['seen'] = pl
        target = logistic(t['bl'])
        if t['kind'] == 'manipulator':
            target = p['manipulator_target']
            if self.manip_spent >= p['manipulator_budget']:
                self.quiet += 1; return
        edge = target - self.price
        if abs(edge) <= p['fee']:
            self.quiet += 1; return
        budget = (p['stake_fraction'] * t['wealth']) / (1 + p['fee'])
        if t['kind'] == 'manipulator':
            budget = min(budget, (p['manipulator_budget'] - self.manip_spent) / (1 + p['fee']))
        if budget <= 0:
            self.quiet += 1; return
        b = p['liquidity']
        tc = clamp(target, 0.001, 0.999)
        if edge > 0:
            xd = b * logit(tc) - (self.q_yes - self.q_no)
            if xd <= 0: return
            x = self.affordable(xd, budget, True)
            if x <= 0: return
            cost = self.marginal_cost(x, True)
            self.q_yes += x; t['yes'] += x
        else:
            xd = b * logit(1 - tc) - (self.q_no - self.q_yes)
            if xd <= 0: return
            x = self.affordable(xd, budget, False)
            if x <= 0: return
            cost = self.marginal_cost(x, False)
            self.q_no += x; t['no'] += x
        t['wealth'] -= cost * (1 + p['fee'])
        self.operator_fees += cost * p['fee']
        if t['kind'] == 'manipulator': self.manip_spent += cost
        self.update_price()
        t['seen'] = logit(self.price)

    def resolve(self):
        o = 1.0 if self.truth else 0.0
        for t in self.traders:
            t['wealth'] += t['yes'] if self.truth else t['no']
            t['yes'] = t['no'] = 0.0
        self.markets_done += 1
        self.final_prices.append((self.price, self.p_star, o))
        self.sums['market'] += (self.price - o) ** 2
        self.sums['prior'] += (self.p['prior_probability'] - o) ** 2
        self.sums['crowd'] += (self.crowd_belief - o) ** 2
        self.sums['pstar'] += (self.p_star - o) ** 2

    def go(self):
        if self.trade_number >= self.p['trades_per_market']:
            self.resolve(); self.new_market()
        self.trade(self.rng.choice(self.traders))
        self.trade_number += 1
        self.price_history.append(self.price)
        if len(self.price_history) > 20: self.price_history.pop(0)

    def run(self, n_markets):
        while self.markets_done < n_markets:
            self.go()
        return {k: v / self.markets_done for k, v in self.sums.items()}

    def wealth_by_kind(self):
        d = {}
        for t in self.traders: d[t['kind']] = d.get(t['kind'], 0.0) + t['wealth']
        return d

def sweep(name, grid, n_markets=300, seeds=(1, 2, 3), **fixed):
    rows = []
    for g in grid:
        res, wk, gap = [], [], []
        for sd in seeds:
            m = Market(seed=sd, **fixed, **g)
            res.append(m.run(n_markets)); wk.append(m.wealth_by_kind())
            gap.append(statistics.mean(abs(a - b) for a, b, _ in m.final_prices))
        avg = {k: statistics.mean(r[k] for r in res) for k in res[0]}
        wavg = {k: statistics.mean(w.get(k, 0) for w in wk) for k in wk[0]}
        rows.append((g, avg, wavg))
        print(name, g, 'brier', {k: round(v, 3) for k, v in avg.items()}, '|price-p*|', round(statistics.mean(gap), 3), 'wealth', {k: round(v) for k, v in wavg.items()}, flush=True)
    return rows

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if which in ('all', 'trust'):
        sweep('price-trust', [dict(price_trust=t) for t in (0, 0.25, 0.5, 0.75, 1.0)])
    if which in ('all', 'shared'):
        sweep('shared-error', [dict(shared_error=s) for s in (0, 0.2, 0.4, 0.6, 0.8, 1.0)])
        sweep('shared-error, trust 0.5', [dict(shared_error=s, price_trust=0.5) for s in (0, 0.4, 0.8)])
    if which in ('all', 'n'):
        sweep('num-traders', [dict(num_traders=n) for n in (5, 10, 25, 50, 100, 200)])
    if which in ('all', 'acc'):
        sweep('signal-accuracy', [dict(signal_accuracy=q) for q in (0.5, 0.55, 0.6, 0.7, 0.9)])
    if which in ('all', 'liq'):
        sweep('liquidity', [dict(liquidity=l) for l in (2, 5, 20, 50, 100, 200)])
    if which in ('all', 'noise'):
        sweep('noise-traders', [dict(share_noise_traders=s) for s in (0, 0.25, 0.5, 0.75, 0.9)])
        sweep('noise-traders, trust 0.5', [dict(share_noise_traders=s, price_trust=0.5) for s in (0.5, 0.9)])
    if which in ('all', 'imit'):
        sweep('imitators', [dict(share_imitators=s) for s in (0, 0.25, 0.5, 0.75)])
        sweep('imitators strength', [dict(share_imitators=0.5, imitation_strength=k) for k in (0.05, 0.2, 0.5)])
    if which in ('all', 'manip'):
        sweep('manipulator budget, trust 1', [dict(manipulator=True, manipulator_budget=b) for b in (0.02, 0.1, 0.3)])
        sweep('manipulator budget, trust 0.5', [dict(manipulator=True, manipulator_budget=b, price_trust=0.5) for b in (0.02, 0.1, 0.3)])
        sweep('manipulator budget, trust 0', [dict(manipulator=True, manipulator_budget=b, price_trust=0) for b in (0.02, 0.1, 0.3)])
        sweep('manipulator x trades', [dict(manipulator=True, manipulator_budget=50.0, price_trust=0.5, trades_per_market=k) for k in (50, 200, 1000)])
    if which in ('all', 'fee'):
        sweep('fee', [dict(fee=f) for f in (0, 0.02, 0.05, 0.1, 0.2)])
    if which in ('all', 'stake'):
        sweep('stake', [dict(stake_fraction=s) for s in (0.01, 0.05, 0.2, 1.0)])
        sweep('stake x liquidity', [dict(stake_fraction=0.05, liquidity=l) for l in (5, 20, 100)])
    if which in ('all', 'prior'):
        sweep('prior', [dict(prior_probability=q) for q in (0.5, 0.8, 0.95)])
    if which in ('all', 'trades'):
        sweep('trades-per-market', [dict(trades_per_market=k) for k in (20, 50, 100, 200, 500)])
