# Plaza1 / Plaza2 — where these files came from

Real range-only SLAM sequences: a planar vehicle driving a plaza, with wheel
odometry and time-of-flight radio ranges to four fixed nodes whose positions
were surveyed but are treated as unknown by the estimator. They are the real
data both reference papers use — NF-iSAM reports Plaza1 and Plaza2, the Slices
paper reports Plaza2 — which is why the case study is built on them rather
than on anything synthetic.

## Download

Fetched 2026-08-16 from the GTSAM distribution, which redistributes them:

    https://github.com/borglab/gtsam  →  examples/Data/

**Pinned to commit `9fabbb312ad62d8dce8ae04fcae92036ed473b92`** (recorded in
`raw/.gtsam_commit`). Pinned rather than tracked to a branch because `develop`
moves: a rerun six months from now must fetch the same bytes or the numbers in
this repository stop meaning anything.

    curl -o <file> https://raw.githubusercontent.com/borglab/gtsam/9fabbb31.../examples/Data/<file>

SHA-256, so a corrupted or silently updated copy is caught rather than parsed:

    41233e2e97d482c12a6cd074583c15fb47918d015a3d59e90d8b3b3cfba8b09d  Plaza1_DR.txt
    56b6cdd86327da38143c0f2b2a3e4337908e1d3447c32b2897005ebbd3326be8  Plaza1_TD.txt
    9ccbfec19942eabecfa3206bff983bf708b98d6c7db462d81c55376f92d75847  Plaza1_.mat
    afd63364d0650e90ca1a9f13ceb9105104f52ab6768beb1cdf584ab9aada024e  Plaza2_DR.txt
    05e884e9e131b805db71bacd345b8606e8d53fe21a6b5a3acbbb4f33d0a68cfd  Plaza2_TD.txt
    72f0abe0fea2050eb5ee1cffc8c43823266a35785b7cdecac4ec5eae727561a2  Plaza2_.mat

Upstream the sequences are Joseph Djugash and Sanjiv Singh's range-only SLAM
data, collected at Carnegie Mellon. GTSAM is BSD-3-Clause; the data travel with
it. They are here for academic use, unmodified — nothing in this folder is
edited, and every correction (range-bias calibration in particular) happens in
the loader where it can be turned off and inspected.

## What is in each file

**`PlazaN_.mat` is the complete record and is what the loader reads.** The two
`.txt` files carry only DR and TD — the subset GTSAM's C++ examples need — and
in particular contain no ground truth at all. They are kept as an independent
cross-check on the parse, not as a source.

| Variable | Plaza1     | Plaza2     | Columns                                  |
|----------|------------|------------|------------------------------------------|
| `DR`     | 9657 x 3   | 4090 x 3   | time (s), distance travelled (m), heading change (rad) |
| `DRp`    | 9658 x 4   | 4091 x 4   | time, x, y, theta — dead-reckoned path, i.e. DR integrated |
| `GT`     | 9658 x 4   | 4091 x 4   | time, x, y, theta — ground-truth path    |
| `TD`     | 3529 x 4   | 1816 x 4   | time, sender id, receiver id, range (m)  |
| `TL`     | 4 x 3      | 4 x 3      | landmark id, x, y — the surveyed nodes   |

Measured from Plaza2, so that a loader which quietly transposes or rescales
something has numbers to fail against:

  * landmark ids are `{0, 1, 5, 6}` — **not** `1..4`, and an implementation
    that indexes `TL` by id rather than by row will read past the end or, worse,
    silently return the wrong landmark for id 0
  * the sender id is always `2` (the vehicle's own antenna), so column 2 of
    `TD` identifies the robot and column 3 identifies the landmark
  * ranges span 4.2 m to 88.7 m; the plaza is roughly 68 m across
  * per-step odometry is 0.0002 m to 1.24 m of travel and at most 0.09 rad of
    turn, at roughly 10 Hz — so a "step" of the sequence is far smaller than a
    keyframe of the estimated window
  * the sequence covers 3152 s to 3562 s; times are absolute, not from zero,
    and differencing is the only safe way to use them

`DRp` is derivable from `DR` and is kept because it is a free check on the
integration convention — which is worth having, because the convention is not
the obvious one.

## Two conventions, both measured, both able to ruin the case silently

**Odometry integrates at the MID heading.** Advance the heading by the full
step, translate along the average of the old and new headings. Measured against
`DRp` over Plaza2's 1354 m dead-reckoned path:

| convention                                  | max gap | mean gap |
|---------------------------------------------|---------|----------|
| translate at mid heading (`theta + dtheta/2`) | 0.063 m | 0.031 m  |
| turn, then translate at the new heading       | 0.552 m | 0.272 m  |
| translate at the old heading, then turn       | 0.444 m | 0.222 m  |

The wrong choice is out by roughly half a metre after 4090 steps. That is small
enough to look like odometry drift — which is exactly the problem, because a
range-only case is a case about drift, and a systematic integration error would
be absorbed into the estimate and read as a method result.

**Plaza2's ground-truth heading is offset by pi from its direction of travel,
and Plaza1's is not.** Taking the course between consecutive ground-truth
positions and comparing it with the recorded heading:

    Plaza1   median difference  -0.017 rad   agrees on 100% of moving steps
    Plaza2   median difference   3.106 rad   agrees on 100% only after adding pi

So the two sequences do not share a heading convention. A loader that seeds its
first pose from ground truth is correct on Plaza1 and drives the estimate
backwards on Plaza2. Nothing about that failure announces itself as a data
problem: the odometry is fine, the ranges are fine, and the estimator simply
produces a bad trajectory on the real-data case — which is precisely the result
one would be tempted to attribute to the method under test.

Both facts are handled in `datasets.loadPlazaDataset` and pinned by tests, not
left as knowledge someone has to remember.

## The constraint this data lands on

The engine degrades sharply above roughly thirteen **variables** — each of them
planar, so about twenty-six dimensions. Counting the window's dimension against
that ceiling, as an earlier version of this file did, overstates its size by a
factor of two and gets the mechanism wrong as well: the grid world's separator
is 3 variables at *every* size, including the one that fails, so the cliff is
not a separator effect.

Neither reference paper faced this limit, so the paper figures for a full Plaza
trajectory are not reachable here. What is reachable is a keyframe window — four
poses and two landmarks, six variables — and figures that say so on their face.

Two properties of this data matter more than the ceiling, and both were found by
measurement rather than expected:

- **Elimination order dominates.** The min-degree order eliminates the landmarks
  in the middle of the window and pose RMSE lands anywhere between 3.5 m and
  23 m depending on seed; eliminating them last gives 1.5–1.8 m with the support
  ESS two orders of magnitude higher. The separator sizes are *identical* either
  way. See `datasets.makePlazaCase`.
- **The landmark posterior is bimodal, and its mean is not an estimate.** Ranges
  from a short pose chain fix a landmark only up to reflection in that chain, and
  both modes carry mass (measured 51/49 and 48/52). The true position explains
  the readings to 0.51 m and 1.25 m; the posterior mean explains them 15.9 m and
  18.2 m worse, because it sits between the modes, on the trajectory. Landmark
  RMSE-of-the-mean therefore measures the gap between two modes and not the
  quality of the estimate — which is the phenomenon the two reference papers
  exist to address, arriving here unforced, from real radios.
