#!/usr/bin/env node
// Drives the pinned ts-fsrs reference impl to produce
// Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs6-parity.json.
//
// Run from this directory:
//   npm ci && node generate-parity-fixtures.mjs
//
// See docs/DECISIONS/0002-fsrs-reference.md for the schema and rationale.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  fsrs,
  generatorParameters,
  createEmptyCard,
  Rating,
  FSRSVersion,
} from 'ts-fsrs';

const PINNED_TAG = 'v5.4.0';
const PINNED_SHA = '80bab011a7f496b06c99924d54e772cf258244f2';

// ts-fsrs exposes `FSRSVersion = "v{package_version} using FSRS-6.0"`.
// Parse + assert pinned tag, since the package blocks `package.json` subpath imports.
const versionMatch = FSRSVersion.match(/^(v\d+\.\d+\.\d+)\s+using\s+FSRS-([\d.]+)/);
if (!versionMatch) {
  throw new Error(`Unrecognized FSRSVersion string: "${FSRSVersion}"`);
}
const [, installedTag, fsrsAlgVersion] = versionMatch;
if (installedTag !== PINNED_TAG) {
  throw new Error(
    `ts-fsrs version mismatch: installed ${installedTag}, pinned ${PINNED_TAG}. ` +
      `Run "npm ci" against the committed package-lock.json or update ADR-0002.`
  );
}
if (!fsrsAlgVersion.startsWith('6')) {
  throw new Error(`Pinned ts-fsrs is not FSRS-6: got "${FSRSVersion}"`);
}

// ---------------------------------------------------------------------------
// Parameters — identical to ts-fsrs defaults at the pinned commit.
// ---------------------------------------------------------------------------
const params = generatorParameters({
  enable_fuzz: false,
  enable_short_term: true,
});

// Reflect learning/relearning step durations back to seconds for the schema.
// ts-fsrs defaults: learning_steps = ['1m', '10m'], relearning_steps = ['10m'].
const learningStepsSeconds = [60, 600];
const relearningStepsSeconds = [600];

const EPOCH_ISO = '2026-01-01T00:00:00.000Z';
const EPOCH = new Date(EPOCH_ISO);

// ---------------------------------------------------------------------------
// Fixture runner.
// A decision is one of:
//   { rating, elapsed }                            // elapsed = seconds (number)
//   { rating, elapsed: 'when_due' }                // wait until card.due
//   { rating, elapsed: 'half_due' }                // wait half the gap to due
//   { rating, elapsed: { multiplier: number } }    // (due - now) * multiplier
// ---------------------------------------------------------------------------
function resolveElapsedSeconds(decision, card, now) {
  const gapSeconds = Math.max(0, Math.round((card.due.getTime() - now.getTime()) / 1000));
  if (typeof decision.elapsed === 'number') return Math.max(0, Math.round(decision.elapsed));
  if (decision.elapsed === 'when_due') return gapSeconds;
  if (decision.elapsed === 'half_due') return Math.max(0, Math.round(gapSeconds / 2));
  if (decision.elapsed && typeof decision.elapsed.multiplier === 'number') {
    return Math.max(0, Math.round(gapSeconds * decision.elapsed.multiplier));
  }
  throw new Error(`Unknown elapsed spec: ${JSON.stringify(decision.elapsed)}`);
}

function runDecisions(decisions) {
  const f = fsrs(params);
  let card = createEmptyCard(EPOCH);
  let now = EPOCH;
  const steps = [];
  for (let i = 0; i < decisions.length; i++) {
    const d = decisions[i];
    const elapsedSeconds = resolveElapsedSeconds(d, card, now);
    now = new Date(now.getTime() + elapsedSeconds * 1000);
    const { card: nextCard } = f.next(card, now, d.rating);
    card = nextCard;
    steps.push({
      step_index: i,
      elapsed_seconds_since_prev: elapsedSeconds,
      absolute_seconds_from_epoch: Math.round((now.getTime() - EPOCH.getTime()) / 1000),
      rating: d.rating,
      expected: {
        stability: card.stability,
        difficulty: card.difficulty,
        state: card.state,
        due_seconds_from_epoch: Math.floor((card.due.getTime() - EPOCH.getTime()) / 1000),
        scheduled_days: card.scheduled_days,
        reps: card.reps,
        lapses: card.lapses,
        learning_steps: card.learning_steps,
      },
    });
  }
  return steps;
}

// ---------------------------------------------------------------------------
// Synthetic fixtures — 50 hand-shaped sequences covering the spec's coverage
// requirements (see ADR-0002 §Coverage requirements).
// ---------------------------------------------------------------------------
const A = Rating.Again, H = Rating.Hard, G = Rating.Good, E = Rating.Easy;
const wd = 'when_due';

const synthetic = [];
function add(id, description, decisions) {
  synthetic.push({ id, description, decisions });
}

// 1–4: single first-review by rating.
add('first-rating-again', 'New card, single Again at t=0', [{ rating: A, elapsed: 0 }]);
add('first-rating-hard', 'New card, single Hard at t=0', [{ rating: H, elapsed: 0 }]);
add('first-rating-good', 'New card, single Good at t=0', [{ rating: G, elapsed: 0 }]);
add('first-rating-easy', 'New card, single Easy at t=0', [{ rating: E, elapsed: 0 }]);

// 5–10: graduation via Good (short-term mode steps 1m, 10m).
add('graduate-good-good', 'Good in New, Good at 1m — graduates to Review',
  [{ rating: G, elapsed: 0 }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('graduate-easy-from-new', 'Easy in New — direct graduation',
  [{ rating: E, elapsed: 0 }, { rating: G, elapsed: wd }]);
add('graduate-then-one-review', 'Graduate, then one Good in Review',
  [{ rating: G, elapsed: 0 }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('graduate-hard-good', 'Hard in New, Good — slower graduation',
  [{ rating: H, elapsed: 0 }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('graduate-good-then-easy', 'Good then Easy graduates faster',
  [{ rating: G, elapsed: 0 }, { rating: E, elapsed: wd }, { rating: G, elapsed: wd }]);
add('learning-again-then-good', 'Good in New, Again at 1m (back to step 0), Good, Good',
  [{ rating: G, elapsed: 0 }, { rating: A, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);

// 11–14: each first rating followed by a Good chain.
for (const r of [A, H, G, E]) {
  const name = ['', 'again', 'hard', 'good', 'easy'][r];
  add(`first-${name}-then-3-goods`, `First ${name}, then 3 Goods reviewed when due`,
    [{ rating: r, elapsed: 0 },
     { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
}

// 15–19: Good chains of length 2..6 from a graduated card.
const graduate2 = [{ rating: G, elapsed: 0 }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }];
for (let n = 2; n <= 6; n++) {
  add(`review-good-x${n}`, `Graduate then ${n} Goods in Review`,
    [...graduate2, ...Array.from({ length: n }, () => ({ rating: G, elapsed: wd }))]);
}

// 20–24: Review-state mixed ratings — exercise per-rating branches.
add('review-mixed-good-easy-hard', 'Review: Good Easy Hard Good',
  [...graduate2, { rating: G, elapsed: wd }, { rating: E, elapsed: wd }, { rating: H, elapsed: wd }, { rating: G, elapsed: wd }]);
add('review-easy-streak', 'Review: 4 Easies',
  [...graduate2, { rating: E, elapsed: wd }, { rating: E, elapsed: wd }, { rating: E, elapsed: wd }, { rating: E, elapsed: wd }]);
add('review-hard-streak', 'Review: 4 Hards',
  [...graduate2, { rating: H, elapsed: wd }, { rating: H, elapsed: wd }, { rating: H, elapsed: wd }, { rating: H, elapsed: wd }]);
add('review-alternating-good-hard', 'Review: Good Hard Good Hard Good',
  [...graduate2, { rating: G, elapsed: wd }, { rating: H, elapsed: wd }, { rating: G, elapsed: wd }, { rating: H, elapsed: wd }, { rating: G, elapsed: wd }]);
add('review-good-then-easy-tail', 'Review: 3 Goods then 2 Easies',
  [...graduate2, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: E, elapsed: wd }, { rating: E, elapsed: wd }]);

// 25–29: lapses and relearning recovery.
add('lapse-once-recover', 'Graduate, Good, Again (lapse), Good (relearn), Good (back in Review)',
  [...graduate2, { rating: G, elapsed: wd }, { rating: A, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('lapse-then-easy-recover', 'Graduate, Again, Easy in Relearning',
  [...graduate2, { rating: A, elapsed: wd }, { rating: E, elapsed: wd }]);
add('lapse-then-hard-stay-relearn', 'Graduate, Again, Hard (stays in Relearning longer)',
  [...graduate2, { rating: A, elapsed: wd }, { rating: H, elapsed: wd }, { rating: G, elapsed: wd }]);
add('lapse-double-fail', 'Graduate, Again, Again in Relearning, then Good',
  [...graduate2, { rating: A, elapsed: wd }, { rating: A, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('lapse-multi-cycle', 'Graduate, lapse-recover-lapse-recover',
  [...graduate2, { rating: A, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd },
   { rating: A, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);

// 30–34: very-overdue reviews (elapsed = 3x scheduled).
add('overdue-3x-then-good', 'Graduate, then Good at 3x due gap',
  [...graduate2, { rating: G, elapsed: { multiplier: 3 } }]);
add('overdue-5x-then-good', 'Graduate, then Good at 5x due gap',
  [...graduate2, { rating: G, elapsed: { multiplier: 5 } }]);
add('overdue-3x-then-hard', 'Graduate, then Hard at 3x due gap',
  [...graduate2, { rating: H, elapsed: { multiplier: 3 } }]);
add('overdue-2x-then-again', 'Graduate, then Again at 2x due gap (overdue lapse)',
  [...graduate2, { rating: A, elapsed: { multiplier: 2 } }, { rating: G, elapsed: wd }]);
add('overdue-chain', 'Graduate, two Goods at 2x then 4x due gap',
  [...graduate2, { rating: G, elapsed: { multiplier: 2 } }, { rating: G, elapsed: { multiplier: 4 } }]);

// 35–39: rapid-fire (reviewed early, half due gap).
add('early-half-due-good', 'Graduate, then Good at half due gap',
  [...graduate2, { rating: G, elapsed: 'half_due' }]);
add('early-half-due-easy', 'Graduate, then Easy at half due gap',
  [...graduate2, { rating: E, elapsed: 'half_due' }]);
add('early-quarter-due', 'Graduate, then Good at quarter due gap',
  [...graduate2, { rating: G, elapsed: { multiplier: 0.25 } }]);
add('early-then-overdue', 'Graduate, Good early, Good overdue',
  [...graduate2, { rating: G, elapsed: 'half_due' }, { rating: G, elapsed: { multiplier: 2 } }]);
add('early-mixed-ratings', 'Graduate, then Hard Good Easy at half due gaps',
  [...graduate2, { rating: H, elapsed: 'half_due' }, { rating: G, elapsed: 'half_due' }, { rating: E, elapsed: 'half_due' }]);

// 40–44: long sequences (8+ reviews).
add('long-good-streak-10', 'Graduate then 10 Goods (long retention)',
  [...graduate2, ...Array.from({ length: 10 }, () => ({ rating: G, elapsed: wd }))]);
add('long-mixed-stable', 'Graduate then 10 mostly-Good with occasional Hard',
  [...graduate2,
    { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: H, elapsed: wd },
    { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: H, elapsed: wd },
    { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: E, elapsed: wd }]);
add('long-lapse-then-recover', 'Graduate, 3 Goods, lapse, 6-step recovery',
  [...graduate2,
    { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd },
    { rating: A, elapsed: wd }, { rating: G, elapsed: wd },
    { rating: G, elapsed: wd }, { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('long-double-lapse', 'Graduate, lapse, recover, lapse, recover',
  [...graduate2,
    { rating: G, elapsed: wd }, { rating: A, elapsed: wd }, { rating: G, elapsed: wd },
    { rating: G, elapsed: wd }, { rating: A, elapsed: wd }, { rating: G, elapsed: wd },
    { rating: G, elapsed: wd }, { rating: G, elapsed: wd }]);
add('long-easy-acceleration', 'Graduate then 8 Easies (max growth)',
  [...graduate2, ...Array.from({ length: 8 }, () => ({ rating: E, elapsed: wd }))]);

// 45–50: tours and edge cases.
add('all-ratings-tour', 'Graduate then all four ratings in order',
  [...graduate2, { rating: A, elapsed: wd }, { rating: H, elapsed: wd }, { rating: G, elapsed: wd }, { rating: E, elapsed: wd }]);
add('reverse-ratings-tour', 'Graduate then ratings Easy Good Hard Again',
  [...graduate2, { rating: E, elapsed: wd }, { rating: G, elapsed: wd }, { rating: H, elapsed: wd }, { rating: A, elapsed: wd }, { rating: G, elapsed: wd }]);
add('zero-elapsed-twice', 'Two Goods at elapsed=0 in Learning state',
  [{ rating: G, elapsed: 0 }, { rating: G, elapsed: 0 }]);
add('explicit-1day', 'Graduate then Good at exactly 86400s',
  [...graduate2, { rating: G, elapsed: 86400 }]);
add('explicit-7day', 'Graduate then Good at exactly 7d (604800s)',
  [...graduate2, { rating: G, elapsed: 604800 }]);
add('explicit-30day', 'Graduate then Good at exactly 30d',
  [...graduate2, { rating: G, elapsed: 30 * 86400 }]);

if (synthetic.length !== 50) {
  throw new Error(`Expected 50 synthetic fixtures, got ${synthetic.length}`);
}

// ---------------------------------------------------------------------------
// Random fixtures — mulberry32 PRNG, seeds 0..99.
// Each: 3..12 ratings drawn uniformly, elapsed log-uniform in [60s, 365d].
// ---------------------------------------------------------------------------
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = t;
    r = Math.imul(r ^ (r >>> 15), r | 1);
    r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

const MIN_ELAPSED = 60;            // 1 minute
const MAX_ELAPSED = 365 * 86400;   // 1 year
const LOG_MIN = Math.log(MIN_ELAPSED);
const LOG_MAX = Math.log(MAX_ELAPSED);

function randomFixture(seed) {
  const rng = mulberry32(seed);
  const length = 3 + Math.floor(rng() * 10); // 3..12 inclusive
  const decisions = [];
  for (let i = 0; i < length; i++) {
    const rating = 1 + Math.floor(rng() * 4); // 1..4
    const elapsed = i === 0
      ? 0
      : Math.round(Math.exp(LOG_MIN + rng() * (LOG_MAX - LOG_MIN)));
    decisions.push({ rating, elapsed });
  }
  return { id: `random-${String(seed).padStart(3, '0')}`, description: `Random seed=${seed}, len=${length}`, decisions, seed };
}

const random = Array.from({ length: 100 }, (_, i) => randomFixture(i));

// ---------------------------------------------------------------------------
// Build the file.
// ---------------------------------------------------------------------------
const fixtures = [
  ...synthetic.map((f) => ({
    id: f.id,
    category: 'synthetic',
    description: f.description,
    seed: null,
    epoch_iso: EPOCH_ISO,
    steps: runDecisions(f.decisions),
  })),
  ...random.map((f) => ({
    id: f.id,
    category: 'random',
    description: f.description,
    seed: f.seed,
    epoch_iso: EPOCH_ISO,
    steps: runDecisions(f.decisions),
  })),
];

const output = {
  schema_version: 1,
  fsrs_version: 'FSRS-6.0',
  generated_at: new Date().toISOString(),
  source: {
    library: 'ts-fsrs',
    tag: PINNED_TAG,
    commit: PINNED_SHA,
    url: 'https://github.com/open-spaced-repetition/ts-fsrs',
  },
  parameters: {
    w: Array.from(params.w),
    request_retention: params.request_retention,
    maximum_interval: params.maximum_interval,
    enable_fuzz: params.enable_fuzz,
    enable_short_term: params.enable_short_term,
    learning_steps_seconds: learningStepsSeconds,
    relearning_steps_seconds: relearningStepsSeconds,
  },
  epsilon: {
    stability: 1e-9,
    difficulty: 1e-9,
    scheduled_days_exact: true,
    due_seconds_tolerance: 1,
  },
  fixtures,
};

// Sanity assertions.
const counts = { synthetic: 0, random: 0 };
for (const fx of fixtures) counts[fx.category]++;
if (counts.synthetic !== 50 || counts.random !== 100) {
  throw new Error(`Fixture counts wrong: ${JSON.stringify(counts)}`);
}
if (output.parameters.w.length !== 21) {
  throw new Error(`Expected 21 weights, got ${output.parameters.w.length}`);
}

// ---------------------------------------------------------------------------
// Write to the test target's Fixtures dir.
// ---------------------------------------------------------------------------
const __dirname = dirname(fileURLToPath(import.meta.url));
const outPath = resolve(__dirname, '..', '..', 'Packages', 'AnghkooeyCore', 'Tests', 'AnghkooeyCoreTests', 'Fixtures', 'fsrs6-parity.json');
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(output, null, 2) + '\n');

console.log(`Wrote ${fixtures.length} fixtures (${counts.synthetic} synthetic + ${counts.random} random) to ${outPath}`);
console.log(`ts-fsrs version: ${FSRSVersion}`);
