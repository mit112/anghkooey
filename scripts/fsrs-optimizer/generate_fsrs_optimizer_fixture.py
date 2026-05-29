"""
Generate a deterministic FSRS-6 optimizer parity fixture for AnghkooeyCore tests.

RECORDED SEMANTICS — what the Swift LiveFSRSOptimizer must replicate exactly
=============================================================================

This generator implements FSRS-6 using the exact same formulas as
LiveFSRS6Engine.swift. The resulting fixture is the oracle for:
  (a) eligible-sample count semantics
  (b) BCE loss computation
  (c) loss improvement (optimized < baseline)

NOTE ON ORACLE CHOICE
---------------------
py-fsrs's Optimizer class requires PyTorch (pip install fsrs[optimizer]), which
in turn requires CUDA/MKL shared libs not available in all build environments.
This generator instead implements a self-contained FD-Adam optimizer — the same
algorithm LiveFSRSOptimizer.swift uses — making it a MORE direct parity target
than a PyTorch autograd oracle (Swift uses finite differences, not autograd).
The semantics being tested are eligibility + BCE loss, not the optimizer itself.
Both Python and Swift run the same algorithm from the same starting point.

ELIGIBILITY SEMANTICS (reproduced by Swift)
-------------------------------------------
For each card's review sequence (ordered by reviewedAt):
  - index 0 (first review):   EXCLUDED from loss; initialises state via seed path.
  - index i > 0, elapsedDays == 0 (same-day re-review):
                              EXCLUDED from loss; advances state via short-term path.
  - index i > 0, elapsedDays > 0 (genuine spaced review):
                              ELIGIBLE — predicted recall enters BCE.

BCE LOSS
--------
  label  y = 0 if rating == Again (1), else 1
  predicted r = forgettingCurve(elapsedDays, stability)
  r clipped to [1e-7, 1-1e-7]
  loss_i = -(y*log(r) + (1-y)*log(1-r))
  mean_loss = sum(loss_i) / eligible_count

STATE REPLAY — matches LiveFSRS6Engine exactly
-----------------------------------------------
Notation: w = candidate weight vector (length 21).

  decay   = -w[20]   (negative; matches ts-fsrs)
  factor  = (1/9)^(-decay) - 1
  round8  = round(x, 8)
  sMin    = 0.001
  sMax    = 36500.0

  forgettingCurve(t, s, w):
      factor = exp(ln(0.9) / decay) - 1   # matches LiveFSRS6Engine exactly
      round8((1 + factor * t / s)^decay)

  initStability(g, w):
      max(w[g.rawValue - 1], 0.1)   # g.rawValue: Again=1,Hard=2,Good=3,Easy=4

  initDifficulty(g, w):
      round8(w[4] - exp((g.rawValue - 1) * w[5]) + 1.0)

  linearDamping(deltaD, oldD):
      round8(deltaD * (10 - oldD) / 9)

  meanReversion(initial, current, w):
      round8(w[7] * initial + (1 - w[7]) * current)

  nextDifficulty(d, g, w):
      deltaD = -w[6] * (g.rawValue - 3)
      nextD  = d + linearDamping(deltaD, d)
      # NOTE: initDifficulty(Easy) is intentionally NOT clamped before meanReversion
      clamp(meanReversion(initDifficulty(Easy, w), nextD, w), 1, 10)

  nextRecallStability(d, s, r, g, w):
      hardPenalty = w[15] if g == Hard else 1.0
      easyBonus   = w[16] if g == Easy else 1.0
      value = s * (1 + exp(w[8]) * (11 - d) * s^(-w[9])
                    * (exp((1-r)*w[10]) - 1) * hardPenalty * easyBonus)
      round8(clamp(value, sMin, sMax))

  nextForgetStability(d, s, r, w):
      value = w[11] * d^(-w[12]) * ((s+1)^w[13] - 1) * exp((1-r)*w[14])
      round8(clamp(value, sMin, sMax))

  nextShortTermStability(s, g, w):   # used when t==0 and enableShortTerm==True
      sinc   = s^(-w[19]) * exp(w[17] * (g.rawValue - 3 + w[18]))
      masked = max(sinc, 1.0) if g.rawValue >= Hard.rawValue else sinc
      round8(clamp(s * masked, sMin, sMax))

  nextMemoryState(d, s, t, g, w):   # t = elapsedDays as int
      if d == 0 and s == 0:          # seed path (first review)
          return (clamp(initDifficulty(g,w), 1, 10), initStability(g,w))
      r = forgettingCurve(t, s, w)
      if t == 0:                     # same-day, enableShortTerm=True
          newS = nextShortTermStability(s, g, w)
      elif g == Again:
          sAfterFail = nextForgetStability(d, s, r, w)
          nextSMin   = s / exp(w[17] * w[18])
          newS = clamp(round8(nextSMin), sMin, sAfterFail)
      else:
          newS = nextRecallStability(d, s, r, g, w)
      return (nextDifficulty(d, g, w), newS)

w[0..3] PRETRAINING
-------------------
Before running Adam on all 21 weights, pretrain w[0..3] (initial stability per
first-review rating bucket). For each card with ≥2 reviews:
  - bucket = first review rating (1..4, i.e. Again/Hard/Good/Easy)
  - interval = second review elapsedDays (the actual elapsed since first review)
  - outcome = (second_review_rating != Again)  → 1/0
Fit w[bucket-1] independently for each bucket via a simple 1-D Adam minimising
the same BCE loss. Use w[bucket-1] = 1.0 as initial value per bucket.
Clamp each w[i], i in 0..3, to [0.1, sMax] after fitting.

This is the contract Swift T3 must replicate. Swift groups all first-reviews by
rating, collects (interval, outcome) pairs, and gradient-descends each w[i] in
isolation using the same FD-Adam logic before the full 21-D phase.

FSRS-6 WEIGHT CLAMP RANGES (from ts-fsrs v5.4.0)
--------------------------------------------------
  w[0..3]:  [0.1, 36500]
  w[4]:     [1, 10]
  w[5]:     [0.1, 5]
  w[6]:     [0.1, 5]
  w[7]:     [0, 0.5]
  w[8]:     [-inf, +inf] — but clamp to [-5, 5] for numerical stability
  w[9]:     [0.1, 3]
  w[10]:    [0.1, 5]
  w[11]:    [0.1, 5]
  w[12]:    [0.1, 5]
  w[13]:    [-inf, +inf] — clamp to [-5, 5]
  w[14]:    [-inf, +inf] — clamp to [-5, 5]
  w[15]:    [0.1, 1]
  w[16]:    [1, 5]
  w[17]:    [-2, 2]
  w[18]:    [-2, 2]
  w[19]:    [0.01, 1.5]
  w[20]:    [0.1, 0.8]
"""

import json
import math
import random
import datetime
import sys


# ── FSRS-6 default weights (ts-fsrs v5.4.0 pinned, len=21) ──────────────────

# MUST match FSRSParameters.default.w exactly (ADR-0002, ts-fsrs v5.4.0 pinned).
# This is NOT the FSRS-6 reference default vector — the codebase pins its own.
# The baseline loss is computed under these weights and asserted (abs 0.001)
# against Swift's optimize(from: .default) baseline, so they must be identical.
DEFAULT_W = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
    1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
    1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
]

# Rating raw values (matches Swift Rating enum: Again=1,Hard=2,Good=3,Easy=4)
AGAIN, HARD, GOOD, EASY = 1, 2, 3, 4

S_MIN = 0.001
S_MAX = 36500.0
ENABLE_SHORT_TERM = True


# ── FSRS-6 math primitives ───────────────────────────────────────────────────

def _round8(x: float) -> float:
    return round(x, 8)

def _clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))

def forgetting_curve(t: float, s: float, w: list) -> float:
    decay = -w[20]
    factor = math.exp(math.log(0.9) / decay) - 1.0  # matches LiveFSRS6Engine exactly
    return _round8((1.0 + factor * t / s) ** decay)

def init_stability(g: int, w: list) -> float:
    return max(w[g - 1], 0.1)

def init_difficulty(g: int, w: list) -> float:
    return _round8(w[4] - math.exp((g - 1) * w[5]) + 1.0)

def linear_damping(delta_d: float, old_d: float) -> float:
    return _round8(delta_d * (10.0 - old_d) / 9.0)

def mean_reversion(initial: float, current: float, w: list) -> float:
    return _round8(w[7] * initial + (1.0 - w[7]) * current)

def next_difficulty(d: float, g: int, w: list) -> float:
    delta_d = -w[6] * (g - 3)
    next_d = d + linear_damping(delta_d, d)
    return _clamp(mean_reversion(init_difficulty(EASY, w), next_d, w), 1.0, 10.0)

def next_recall_stability(d: float, s: float, r: float, g: int, w: list) -> float:
    hard_penalty = w[15] if g == HARD else 1.0
    easy_bonus   = w[16] if g == EASY else 1.0
    value = s * (1.0
        + math.exp(w[8])
        * (11.0 - d)
        * (s ** -w[9])
        * (math.exp((1.0 - r) * w[10]) - 1.0)
        * hard_penalty
        * easy_bonus)
    return _round8(_clamp(value, S_MIN, S_MAX))

def next_forget_stability(d: float, s: float, r: float, w: list) -> float:
    value = (w[11]
        * (d ** -w[12])
        * ((s + 1.0) ** w[13] - 1.0)
        * math.exp((1.0 - r) * w[14]))
    return _round8(_clamp(value, S_MIN, S_MAX))

def next_short_term_stability(s: float, g: int, w: list) -> float:
    sinc = (s ** -w[19]) * math.exp(w[17] * (g - 3 + w[18]))
    masked = max(sinc, 1.0) if g >= HARD else sinc
    return _round8(_clamp(s * masked, S_MIN, S_MAX))

def next_memory_state(d: float, s: float, t: float, g: int, w: list) -> tuple:
    """Matches LiveFSRS6Engine.nextMemoryState. t=elapsedDays (float, truncated to int for recall)."""
    if d == 0.0 and s == 0.0:
        init_d = _clamp(init_difficulty(g, w), 1.0, 10.0)
        return (init_d, init_stability(g, w))
    t_int = int(t)
    r = forgetting_curve(float(t_int), s, w)
    if t_int == 0 and ENABLE_SHORT_TERM:
        new_s = next_short_term_stability(s, g, w)
    elif g == AGAIN:
        s_after_fail = next_forget_stability(d, s, r, w)
        next_s_min = s / math.exp(w[17] * w[18])
        new_s = _clamp(_round8(next_s_min), S_MIN, s_after_fail)
    else:
        new_s = next_recall_stability(d, s, r, g, w)
    new_d = next_difficulty(d, g, w)
    return (new_d, new_s)


# ── Loss computation ─────────────────────────────────────────────────────────

def mean_bce_loss(card_seqs: list, w: list) -> tuple:
    """Returns (mean_bce_loss, eligible_count) over all card sequences."""
    total = 0.0
    count = 0
    for seq in card_seqs:
        d, s = 0.0, 0.0
        for idx, sample in enumerate(seq):
            elapsed, rating, same_day = sample
            eligible = (idx > 0 and not same_day)
            if eligible and s > 0:
                r = forgetting_curve(elapsed, s, w)
                r = _clamp(r, 1e-7, 1.0 - 1e-7)
                y = 0.0 if rating == AGAIN else 1.0
                total += -(y * math.log(r) + (1.0 - y) * math.log(1.0 - r))
                count += 1
            d, s = next_memory_state(d, s, elapsed, rating, w)
    return (total / count if count > 0 else 0.0, count)


# ── Pretraining w[0..3] ─────────────────────────────────────────────────────

def pretrain_initial_stability(card_seqs: list, w: list) -> list:
    """
    Fit w[0..3] independently by rating bucket using the first→second-review
    transitions (1-D FD-Adam per bucket). See docstring at top for contract.
    """
    w = list(w)
    buckets = {g: [] for g in [AGAIN, HARD, GOOD, EASY]}
    for seq in card_seqs:
        if len(seq) < 2:
            continue
        first_rating = seq[0][1]
        elapsed1, rating1, same_day1 = seq[1]
        if same_day1:
            continue  # skip same-day second review
        outcome = 0.0 if rating1 == AGAIN else 1.0
        buckets[first_rating].append((float(elapsed1), outcome))

    for g in [AGAIN, HARD, GOOD, EASY]:
        pairs = buckets[g]
        if not pairs:
            continue
        s = 1.0  # initial estimate
        lr = 0.05
        beta1, beta2, eps_adam = 0.9, 0.999, 1e-8
        m, v, t = 0.0, 0.0, 0
        for _ in range(200):
            # FD gradient for single weight s
            eps = max(1e-5, 1e-4 * abs(s))
            def bce_bucket(sv):
                total = 0.0
                for elapsed, y in pairs:
                    r = _clamp(forgetting_curve(elapsed, max(sv, 0.001), DEFAULT_W), 1e-7, 1.0 - 1e-7)
                    total += -(y * math.log(r) + (1.0 - y) * math.log(1.0 - r))
                return total / len(pairs)
            grad = (bce_bucket(s + eps) - bce_bucket(s - eps)) / (2 * eps)
            t += 1
            m = beta1 * m + (1 - beta1) * grad
            v = beta2 * v + (1 - beta2) * grad ** 2
            m_hat = m / (1 - beta1 ** t)
            v_hat = v / (1 - beta2 ** t)
            s -= lr * m_hat / (math.sqrt(v_hat) + eps_adam)
            s = _clamp(s, 0.1, S_MAX)
        w[g - 1] = s
    return w


# ── FD gradient + Adam optimizer ────────────────────────────────────────────

W_CLAMPS = [
    (0.1, S_MAX), (0.1, S_MAX), (0.1, S_MAX), (0.1, S_MAX),  # w[0..3]
    (1.0, 10.0),  (0.1, 5.0),   (0.1, 5.0),   (0.0, 0.5),    # w[4..7]
    (-5.0, 5.0),  (0.1, 3.0),   (0.1, 5.0),   (0.1, 5.0),    # w[8..11]
    (0.1, 5.0),   (-5.0, 5.0),  (-5.0, 5.0),  (0.1, 1.0),    # w[12..15]
    (1.0, 5.0),   (-2.0, 2.0),  (-2.0, 2.0),  (0.01, 1.5),   # w[16..19]
    (0.1, 0.8),                                                 # w[20]
]

def fd_gradient(card_seqs: list, w: list) -> list:
    """Central finite-difference gradient, per-parameter relative epsilon."""
    grads = []
    for i in range(21):
        eps = max(1e-5, 1e-4 * abs(w[i]))
        wp = list(w); wp[i] += eps
        wm = list(w); wm[i] -= eps
        loss_p, _ = mean_bce_loss(card_seqs, wp)
        loss_m, _ = mean_bce_loss(card_seqs, wm)
        grads.append((loss_p - loss_m) / (2 * eps))
    return grads

def optimize(card_seqs: list, w_init: list, epochs: int = 60, lr: float = 0.01,
             batch_size: int = 256, seed: int = 42) -> list:
    w = list(w_init)
    beta1, beta2, adam_eps = 0.9, 0.999, 1e-8
    m = [0.0] * 21
    v = [0.0] * 21
    t = 0
    rng = random.Random(seed)
    for epoch in range(epochs):
        batch = rng.sample(card_seqs, min(batch_size, len(card_seqs)))
        grads = fd_gradient(batch, w)
        t += 1
        for i in range(21):
            m[i] = beta1 * m[i] + (1 - beta1) * grads[i]
            v[i] = beta2 * v[i] + (1 - beta2) * grads[i] ** 2
            m_hat = m[i] / (1 - beta1 ** t)
            v_hat = v[i] / (1 - beta2 ** t)
            w[i] -= lr * m_hat / (math.sqrt(v_hat) + adam_eps)
            lo, hi = W_CLAMPS[i]
            w[i] = _clamp(w[i], lo, hi)
    return w


# ── Synthetic dataset generation ─────────────────────────────────────────────

def generate_reviews(num_cards: int, seed: int = 42) -> list:
    """
    Produce a flat review list where each entry matches OptimizationReviewLogRow:
      {card_id, reviewed_at, rating, elapsed_days}
    Uses DEFAULT_W to simulate realistic state-driven intervals.
    """
    rng = random.Random(seed)
    ratings_pool = [AGAIN, HARD, GOOD, GOOD, GOOD, EASY]
    base_ts = 1_700_000_000.0
    reviews = []
    for card_idx in range(num_cards):
        card_id = f"card-{card_idx:04d}"
        d, s = 0.0, 0.0
        elapsed = 0.0
        ts = base_ts + card_idx * 3600.0
        num_reviews = rng.randint(6, 14)
        for rev_idx in range(num_reviews):
            reviewed_at = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
            rating = rng.choice(ratings_pool)
            reviews.append({
                "card_id": card_id,
                "reviewed_at": reviewed_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "rating": rating,
                "elapsed_days": round(elapsed, 6),
            })
            d, s = next_memory_state(d, s, elapsed, rating, DEFAULT_W)
            # Occasionally add a same-day re-review
            if rev_idx > 0 and rng.random() < 0.08:
                same_rating = rng.choice([HARD, GOOD])
                reviews.append({
                    "card_id": card_id,
                    "reviewed_at": reviewed_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "rating": same_rating,
                    "elapsed_days": 0.0,
                })
                d, s = next_memory_state(d, s, 0.0, same_rating, DEFAULT_W)
            # Next interval based on current stability + jitter
            from_default_s = s
            interval = max(1.0, from_default_s)  # rough proxy
            jitter = rng.uniform(0.8, 1.2)
            advance = interval * jitter
            ts += advance * 86400.0
            elapsed = advance
    return reviews


def build_card_sequences(reviews: list) -> list:
    """Convert flat review list to per-card sequence of (elapsed, rating, sameDay)."""
    groups: dict = {}
    for r in reviews:
        groups.setdefault(r["card_id"], []).append(r)
    seqs = []
    for group in groups.values():
        sorted_g = sorted(group, key=lambda x: x["reviewed_at"])
        seq = [(entry["elapsed_days"], entry["rating"],
                entry["elapsed_days"] == 0.0 and i > 0)
               for i, entry in enumerate(sorted_g)]
        seqs.append(seq)
    return seqs


# ── Main ──────────────────────────────────────────────────────────────────────

SEED = 42
NUM_CARDS = 350
MIN_ELIGIBLE = 512

reviews = generate_reviews(NUM_CARDS, seed=SEED)
seqs = build_card_sequences(reviews)

baseline_loss, eligible_count = mean_bce_loss(seqs, DEFAULT_W)
assert eligible_count >= MIN_ELIGIBLE, (
    f"Only {eligible_count} eligible samples; need ≥{MIN_ELIGIBLE}. Increase NUM_CARDS."
)

# Pretrain + optimize
w_init = pretrain_initial_stability(seqs, DEFAULT_W)
optimized_w = optimize(seqs, w_init, epochs=60, lr=0.01, batch_size=256, seed=SEED)
optimized_loss, _ = mean_bce_loss(seqs, optimized_w)

assert optimized_loss < baseline_loss, (
    f"Optimized loss {optimized_loss:.5f} >= baseline {baseline_loss:.5f}"
)

fixture = {
    "meta": {
        "oracle": "self-contained FD-Adam (stdlib only); same algorithm as LiveFSRSOptimizer.swift",
        "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "seed": SEED,
        "eligible_sample_count": eligible_count,
        "fsrs_version": "FSRS-6.0",
        "num_cards": NUM_CARDS,
        "total_reviews": len(reviews),
        "epochs": 60,
        "learning_rate": 0.01,
        "batch_size": 256,
    },
    "reviews": reviews,
    "baseline_loss": baseline_loss,
    "optimized_loss": optimized_loss,
    "optimized_w": optimized_w,
}

json.dump(fixture, sys.stdout, indent=2)
print()
