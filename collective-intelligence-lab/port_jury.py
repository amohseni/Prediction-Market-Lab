"""Python port of WisdomAndMadness.nlogo, used to compute the answer-key numbers.
Same logic as the NetLogo model. Run: python3 port_jury.py [sweep-name|all]
"""
import math, random, statistics, sys

DEFAULTS = dict(num_voters=51, competence=0.6, competence_spread=0.0, shared_error=0.0, voting='simultaneous',
                network_degree=4, rewiring_probability=0.0, talk_rounds=5, conformity=0.5)

def condorcet(n, p):
    k = n // 2 + 1
    total = sum(math.comb(n, j) * p ** j * (1 - p) ** (n - j) for j in range(k, n + 1))
    if n % 2 == 0:
        total += 0.5 * math.comb(n, n // 2) * p ** (n // 2) * (1 - p) ** (n // 2)
    return total

class Jury:
    def __init__(self, seed=None, **kw):
        self.p = dict(DEFAULTS); self.p.update(kw)
        self.rng = random.Random(seed)
        p = self.p; n = p['num_voters']
        self.comp = [max(0.01, min(0.99, p['competence'] - p['competence_spread'] + self.rng.random() * 2 * p['competence_spread'])) for _ in range(n)]
        self.nbrs = [set() for _ in range(n)]
        if p['voting'] == 'talk first (network)':
            self.build_network()
        self.trials = 0; self.maj_correct = 0; self.sum_ind = 0.0; self.cascade_starts = []; self.share_cascaded = 0.0

    def build_network(self):
        p = self.p; n = p['num_voters']; r = self.rng
        k = max(1, p['network_degree'] // 2)
        links = set()
        for i in range(n):
            for d in range(1, k + 1):
                j = (i + d) % n
                if j != i: links.add(tuple(sorted((i, j))))
        links = list(links); r.shuffle(links)
        final = set(links)
        for (a, b) in links:
            if r.random() < p['rewiring_probability']:
                # rewire: end1 (a) keeps, pick new partner not already linked
                current = final
                cands = [c for c in range(n) if c != a and tuple(sorted((a, c))) not in current]
                if cands:
                    c = r.choice(cands)
                    final.discard((a, b)); final.add(tuple(sorted((a, c))))
        for (a, b) in final:
            self.nbrs[a].add(b); self.nbrs[b].add(a)

    def trial(self):
        p = self.p; r = self.rng; n = p['num_voters']
        truth = 1 if r.random() < 0.5 else 0
        common = truth if r.random() < p['competence'] else 1 - truth
        sig = []
        for i in range(n):
            if r.random() < p['shared_error']: sig.append(common)
            else: sig.append(truth if r.random() < self.comp[i] else 1 - truth)
        vote = list(sig)
        start = -1
        mode = p['voting']
        if mode == 'sequential (rational)':
            net = 0
            for i in range(n):
                if abs(net) >= 2:
                    vote[i] = 1 if net > 0 else 0
                    if start == -1: start = i
                else:
                    vote[i] = sig[i]; net += 1 if sig[i] == 1 else -1
        elif mode == 'sequential (naive)':
            v1 = v0 = 0
            for i in range(n):
                ev = (v1 - v0) + (1 if sig[i] == 1 else -1)
                vote[i] = 1 if ev > 0 else (0 if ev < 0 else sig[i])
                if vote[i] != sig[i] and start == -1: start = i
                if vote[i] == 1: v1 += 1
                else: v0 += 1
        elif mode == 'talk first (network)':
            for _ in range(p['talk_rounds']):
                nxt = list(vote)
                for i in range(n):
                    nb = self.nbrs[i]
                    if nb and r.random() < p['conformity']:
                        ones = sum(vote[j] for j in nb); zeros = len(nb) - ones
                        nxt[i] = 1 if ones > zeros else (0 if zeros > ones else vote[i])
                vote = nxt
        ones = sum(vote); zeros = n - ones
        maj = 1 if ones > zeros else (0 if zeros > ones else r.randrange(2))
        self.trials += 1
        if maj == truth: self.maj_correct += 1
        self.sum_ind += sum(1 for v in vote if v == truth) / n
        self.share_cascaded += sum(1 for i in range(n) if vote[i] != sig[i]) / n
        self.sum_agree = getattr(self, 'sum_agree', 0.0) + max(ones, zeros) / n
        if start != -1: self.cascade_starts.append(start)

    def run(self, trials):
        for _ in range(trials): self.trial()
        return dict(maj=self.maj_correct / self.trials, ind=self.sum_ind / self.trials,
                    casc=self.share_cascaded / self.trials, agree=getattr(self, 'sum_agree', 0.0) / self.trials,
                    start=(statistics.mean(self.cascade_starts) if self.cascade_starts else None))

def sweep(name, grid, trials=4000, seeds=(1, 2), **fixed):
    for g in grid:
        res = [Jury(seed=s, **fixed, **g).run(trials) for s in seeds]
        avg = {k: (statistics.mean(r[k] for r in res) if res[0][k] is not None else None) for k in res[0]}
        cfg = dict(fixed); cfg.update(g)
        n = cfg.get('num_voters', DEFAULTS['num_voters']); c = cfg.get('competence', DEFAULTS['competence'])
        print(name, g, {k: (round(v, 3) if v is not None else None) for k, v in avg.items()}, 'condorcet', round(condorcet(n, c), 3), flush=True)

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if which in ('all', 'n'):
        sweep('n x competence', [dict(num_voters=n, competence=c) for c in (0.45, 0.51, 0.55, 0.6, 0.7) for n in (1, 3, 11, 51, 101, 301)])
    if which in ('all', 'shared'):
        sweep('shared-error', [dict(shared_error=s, num_voters=n) for s in (0, 0.2, 0.4, 0.6, 0.8, 1.0) for n in (11, 101, 301)])
    if which in ('all', 'spread'):
        sweep('competence-spread', [dict(competence_spread=s) for s in (0, 0.2, 0.4)])
        sweep('spread at low competence', [dict(competence=0.52, competence_spread=s, num_voters=101) for s in (0, 0.2, 0.4)])
    if which in ('all', 'seq'):
        sweep('sequential rational', [dict(voting='sequential (rational)', num_voters=n, competence=c) for c in (0.55, 0.6, 0.7, 0.9) for n in (11, 51, 301)])
        sweep('sequential naive', [dict(voting='sequential (naive)', num_voters=n, competence=c) for c in (0.6, 0.9) for n in (11, 51, 301)])
        sweep('sequential rational x shared', [dict(voting='sequential (rational)', shared_error=s) for s in (0, 0.4, 0.8)])
    if which in ('all', 'talk'):
        sweep('talk: conformity', [dict(voting='talk first (network)', conformity=c) for c in (0, 0.25, 0.5, 0.75, 1.0)])
        sweep('talk: rounds', [dict(voting='talk first (network)', talk_rounds=t) for t in (0, 1, 3, 5, 10, 30)])
        sweep('talk: degree', [dict(voting='talk first (network)', network_degree=d) for d in (2, 4, 8, 16)])
        sweep('talk: rewiring', [dict(voting='talk first (network)', rewiring_probability=r) for r in (0, 0.1, 0.5, 1.0)])
        sweep('talk x shared', [dict(voting='talk first (network)', shared_error=s) for s in (0, 0.4, 0.8)])
        sweep('talk at low competence', [dict(voting='talk first (network)', competence=0.52, num_voters=101, talk_rounds=t) for t in (0, 5, 30)])
        sweep('talk at degree 16, rounds 30', [dict(voting='talk first (network)', network_degree=16, talk_rounds=30, conformity=c) for c in (0.5, 1.0)])
