# Smoothed Slices — comparative posterior-recovery demonstrator

A MATLAB app that compares three methods for non-Gaussian SLAM inference on
shared case studies, scored on how well each recovers the **full posterior**,
not just a point estimate:

1. **Slices Perspective** — Shienman, Levy-Or, Kaess & Indelman, IROS 2024
2. **NF-iSAM** — Huang et al., T-RO 2023
3. **Smoothed Slices (RCS)** — our proposed extension

## Quick start

```matlab
addpath('src')
runSmoothedSlicesApp        % opens the app; pick a case, press "Run All"
```

A run takes minutes rather than seconds, so it is watched and interruptible:
both **Run All** and **Run Selected** drive a progress bar with a red **Stop**
beside it. Stop cancels at the next reporting boundary — an elimination step,
an increment, a clique flow — and **keeps the methods that already finished**,
reporting the rest as `cancelled` rather than discarding a completed
comparison to report a clean failure.

That last sentence described the intent rather than the behaviour until
iteration 4 measured it. Two defects, both on the same path and both found by
one test:

- The message announcing each method (`running Smoothed Slices (2 of 2)`) is
  itself a cancellation point, and it sat **outside** the handler. Pressing
  Stop in that instant threw past every method that had already finished, and
  the sweep above kept nothing — the one moment in a run where Stop destroyed
  the work it exists to preserve.
- A sweep cell interrupted part-way wrote the interrupted method into its rows
  as a `cancelled` stub with every metric `NaN`, which is exactly the "curve
  with a hole in it" that `parameterSweep`'s own docstring promised not to
  produce.

The unit of preserved work is now the (cell, method) pair: every method that
finished keeps its row, nothing unfinished contributes one.

```matlab
cd tests
runAllTests                 % 375 tests, 15-20 min headless / 40-55 min on the desktop
```

**`tApp` is the largest single cost** — 60-65 % of the whole suite, for 26 of
the 375 tests — because every one of them builds a `uifigure` and runs
inference in it. Two headless runs put it at 554 s of 928 s and 776 s of
1189 s. The 349 non-UI tests take 374-413 s between them, and of that,
`tNFiSAMPosterior` (~110-120 s) and `tNFiSAMIncremental` (~55-60 s) are
NF-iSAM fitting flows.

**These timings are not repeatable to better than about a third, so read them
as scale and not as measurements.** The two headless runs above ran the same
375 tests and differed by 261 s. Only about 15 s of that was a real change —
the evidence ladder moving from four-pose to eight-pose windows, which shows
up as `tApp/theLadderIsClearedWhenTheCaseChanges` going 13.2 s to 25.4 s and
`tPlazaProtocol` going 5.1 s to 8.2 s. Everything else is the machine:
`everyLatexLabelRendersWithoutWarning`, which touches none of it, went 31.8 s
to 58.7 s across the same pair. Per-class figures here are one sample each of
a quantity that moves this much, and a class that looks 30 % slower than the
number below has not necessarily regressed.

**The two figures in the comment are two different instruments, not a range.**
The per-class numbers above come from headless `matlab -batch` runs.
The 40-55 min is the desktop session the next paragraph
tells you to use, and the two runs behind it came in at 2430 s and 3286 s —
a 35 % spread between themselves, on 353 tests, on the same machine. Neither
figure is wrong and neither is a correction of the other; read each against
its own harness, and do not compute a speedup from the pair, because nothing
here was measured to support that comparison.
That cost is the method rather than the tests — a comparative run trains one
flow per clique — but it is why `runAllTests('Filter', "…")` is worth knowing.
The filter is a **substring** match on the class name, not a regex, so it
takes one class at a time.

Run the suite from a normal MATLAB session, not `matlab -batch`. The non-UI
tests are fine headless, but `tApp` builds a `uifigure` per test and runs
inference in each; headless, the figure connector goes intermittently bad
somewhere around the fourth, and a test that passes alone and in pairs will
then either fail on an invalidated handle or hang. It is a harness limit, not
a defect in what is being tested: the same tests pass in a desktop session,
and a script that builds six apps and runs two inferences headless keeps
every handle. `runAllTests('Filter', "tIncremental")` runs one class.

The full suite has since completed headless **three times** — 374/374 in
983 s, then 375/375 in 928 s and in 1189 s — with all 26 `tApp` tests passing
in every one, plus a fourth run of `tApp` alone at 26/26. That is recorded and
the warning is **kept**. Three clean runs are better evidence than one and
still not evidence of absence: the failure it describes is intermittent, so a
small run of successes is what an intermittent fault looks like most of the
time. This is the number to revisit the warning on, not the number to act on.
Use the desktop session; if you do run headless, a hang or an invalid handle
in `tApp` is the known harness limit rather than a new defect.

**`useCS = logical 1` in the console is MATLAB's, not ours.** Any `xline` or
`yline` drawn into a `uiaxes` prints it when the axes render — bisected to the
constant-line render path on this prerelease build, reproducible in six lines
with no project code involved. It predates the surface panels
(`viz.plotPlazaMarginal` has drawn constant lines all along) and it is noise
rather than a failure. Written down so the next person does not spend an
afternoon on it.

That limit is why the two tabs added in iteration 3 keep their content out of
the app. The cards, the budget check and the four diagnostic tables are
`methods.methodCard`, `methods.budgetComparison` and
`methods.diagnosticsReport` — plain functions, covered by `tCompareMethods`
and `tDiagnosticsReport` headless. `tApp` is then left testing the widgets
rather than the claims.

## Where things live

| path | contents |
|---|---|
| `Instructions/` | **Implementation authority.** The four specs the code follows. |
| `Literature/` | Papers, read for understanding. *Not* executable specification. |
| `src/+core/` | `Factor`, `FactorGraph`, `Variable`, `ApproximateFactor`, `ConditionalFactor`, `SliceConditional`, `BayesNet`, `eliminationOrder`, `eliminationSchedule` |
| `src/+methods/` | `runSlicesMethod`, `runSmoothedSlicesMethod`, `runNFISAMMethod`, `runComparison`, `cancelledResult`, and the three functions behind the two new tabs: `methodCard`, `budgetComparison`, `diagnosticsReport` |
| `src/+methods/+general/` | The general-graph engine: proposals, support, forward, backward, `runIncrementalGeneral`, `StepCache` |
| `src/+methods/+nfisam/` | NF-iSAM's own pieces: `trainingSampleSimulator` (Algorithm N1), `virtualMeasurement`, `factorRole`, `conditionalSamplerTrainer` (Algorithm N2), `ConditionalSampler`, `packSamples`/`unpackSamples`, `incrementalUpdate` (Algorithm N3), `initialState`, `cliqueKeys`, `combineChildSeparators`, `sampleJointPosterior` (the root-to-leaf pass) |
| `src/+flows/` | `FlowModel` (the seam), `RQSplineFlow`, `rqSplineTransform`, `trainFlow`. A package of its own because MATLAB reserves `methods` as a keyword and will not accept `methods.nfisam.FlowModel` as a superclass — and because spec §12 lists `FlowModel` as a module in its own right, not an NF-iSAM part. |
| `src/+datasets/` | Case generators, the ground-truth references, and the Plaza loader |
| `src/+experiments/` | `runPlazaProtocol` (the manual's P1-A/P1-B/P2-A/P2-B), `plazaLandmarkWindows` |
| `src/+research/` | `costQualityFrontier`, `complexityExponent` — the open question, and the refusal to answer it where the mechanism never runs |
| `src/+viz/`, `+metrics/`, `+utils/` | Plotting, metrics, config/LaTeX/export helpers, `ProgressReporter`, `ProgressBar` |
| `tests/` | `matlab.unittest` suite |
| `results/` | `run_YYYYMMDD_HHMMSS_methodCompare/` export bundles |

## Two engines, one entry point

`runInferenceCore` dispatches on `caseData.engine`.

**`slices3`** follows Algorithm S1 literally: the sampling factor is drawn
from and then excluded from the slice product, so its normalizer cancels
(Eq. S8). That needs the Lemma 1 structural condition and a generated factor
that still carries its mixture. It is validated against dense quadrature.

**`general`** keeps every removed factor in the product and divides by an
**explicit proposal density** instead. The two are the same estimator when
the proposal is the sampling factor. That equivalence is tested rather than
asserted: the general engine runs on the two-pose range benchmark and is
scored against the same quadrature reference, giving **3.7 % relative L1**.

Writing the density explicitly is what lets a generated factor be tabulated
and its mixture discarded, which is what stops the nesting cost from
multiplying out over a dozen eliminations.

## Case studies

| case | ground truth | what it shows |
|---|---|---|
| Two-pose range benchmark | dense quadrature **and** a closed form, agreeing to 1e-9 | nested sampling vs. the RCS surface |
| Four Doors | **exact**, by discrete forward–backward on the chain | mode preservation and mode collapse |
| Grid world | true poses and landmarks only | a robot on a blocked map, three layouts, three methods |
| Plaza1 / Plaza2 | the surveyed track and beacon survey | the same three methods on **real range-only data** |

The two synthetic map cases have no tractable exact posterior, and the code
says so rather than implying one: `runComparison` reports
`referenceKind = "truthOnly"`, and the engine's own health diagnostics carry
the weight a reference otherwise would.

Each of the three synthetic cases has a **sweep plan** of its own, because
each breaks down along a different axis, and one grid cannot ask three
questions:

| plan | axis | cells | what a curve across it means |
|---|---|---|---|
| `twoPoseSweepPlan` | budget × mixture separation | 24 | a curve flat in *N* is bias, not sampling noise |
| `fourDoorsSweepPlan` | door spacing × odometry | 24 | whether the posterior's **shape** survives, measured in mode weight rather than RMSE |
| `gridWorldSweepPlan` | problem **size**, at one budget | 18 | where a given map turns, and whether that is a property of the case or of one seed. Run, it showed there is no single ceiling across maps |

The Four Doors grid includes one deliberately **irregular** corridor
(`[2 6 8 14]`), because every evenly spaced corridor is symmetric and on a
symmetric posterior a method that collapses to the midpoint of two modes
lands near the truth by construction — the error cancels and both RMSE and
the mode-weight L1 flatter it.

The grid-world grid sweeps size rather than budget because this case has no
exact posterior to converge *to*: an estimator here can be perfectly
converged and still sit at 12 m of pose error once the nearest-support lookup
has broken down. Budget belongs on the two-pose sweep, where a reference
exists.

## What iteration 2 established

**The general engine holds to about thirteen variables and then breaks.** —
*this is the claim iteration 2 made, and iteration 4 falsified it. The
correction is below the table; the table itself still stands.*

Re-measured over five seeds `[5 3 7 11 13]` at `numSamples` 200 and separator
support 250, after the mission path was fixed to go **around** the blocks
rather than through them — which changed the geometry and therefore every
number in the table this replaces:

| poses | variables | pose RMSE per seed | median | landmark RMSE |
|---|---|---|---|---|
| 4 | 11 | 0.40 0.66 0.86 0.23 1.09 | **0.66** | 3.98 m |
| 5 | 13 | 0.40 1.01 0.75 0.18 1.35 | **0.75** | 3.94 m |
| 6 | 14 | 2.56 18.3 12.9 11.1 13.5 | 12.86 | 14.66 m |
| 7 | 15 | 11.39 15.0 12.8 4.30 6.73 | 11.39 | 11.81 m |

On this map, not a gradual decay — a cliff between thirteen and fourteen
variables. Every seed is under 1.4 m at thirteen; four of five are over 11 m
at fourteen.

**But thirteen is the office's number, not the engine's** — established in
iteration 4, and the reason the warehouse layout was built. Eighteen cells,
same engine, same budget, same support size:

| layout | variables | pose RMSE |
|---|---|---|
| office | 13 | 0.2 – 1.2 m (twelve cells, four seeds) |
| **warehouse** | **10** | **9.2 – 12.7 m** |
| warehouse | 13 | 7.5 m |
| office | 14 | 1.4 – 17.5 m |

A second map fails three variables *below* the first map's ceiling, and the
first map's own fourteen-variable row is a spread rather than a uniform
failure. So "sound to about thirteen variables" was a fact about one layout
that read as a fact about the engine, because it had only ever been measured
on one layout. What survives is weaker and true: **within a fixed geometry,
error rises sharply with mission length, and where it turns is a property of
the map.**

Three candidate explanations were tested and eliminated:

- **Map scale** — the warehouse diagonal is 28.8 m against the office's
  24.4 m. 18 % larger, against an order of magnitude in the error.
- **The variable count itself** — raising the warehouse's sensor range from
  4.0 m to 5.0 m *adds three variables* and *drops* Slices' error from 9.2 m
  to 7.5 m. The opposite of the prediction, on the same map and route. The
  4.0 m range had been chosen to hold the variable count down; it bought that
  count by spending sightings, and the sightings were the part that mattered.
- **Loop closure** — the office route ends 2.5 m from where it started and
  the warehouse's 21 m away, which looks like the answer until you list the
  factors: there is no loop-closure factor in *any* layout. All three are
  open odometry chains, so the office's route nearly closing buys the
  estimator nothing. (An earlier comment claiming "the loop closes at the
  fifth" described the picture, not the graph.)

Still standing and untested: **total path length** — drift accumulates along
the chain and the office's route is much the most compact. Written down as
the next experiment, not as the reason.

One caution on all of these numbers: run-to-run scatter at a *fixed*
configuration is large — the warehouse at five poses measured 12.7 m in the
sweep and 9.2 m in a probe. Differences under about 3 m are not evidence.

**It is not separator size.** This is the one negative result that held up,
and the warehouse strengthened it rather than breaking it. The largest
separator is three variables at *every* row of the office table above,
including the fourteen-variable row that fails — and the warehouse fails on
separators of **two**. A narrower graph, the same failure. Width is not the
mechanism.

The landmark column is in the table because leaving it out was flattering: it
never drops below about 3.9 m even in the good rows, because several beacons
are seen from a short arc, which fixes them only up to reflection in it, and
the mean of a two-mode posterior is an estimate of neither mode. Pose RMSE
alone would report this case as solved.

**Both diagnostics call it before the RMSE does.** Support effective sample
size falls 13.6 → 2.6 and the nearest-support lookup distance rises
0.42 m → 2.29 m across the same step. `runGeneralCore` turns both into
warnings on the result, and the test suite pins that an oversized graph
**warns** rather than that it is accurate.

**Four Doors: both methods collapse the ambiguity** at these budgets. The
exact reference splits pose 2 as 0.48/0.52 between two doors; Slices returns
0.07/0.78 and Smoothed Slices 0.01/0.92. That is mode collapse, and having
an exact answer is what makes it a finding rather than a suspicion.

**Ordering matters more than separator size.** Pure minimum fill picks a late
pose whose only proposal route is a range annulus metres wide. It scored a
*smaller* separator and a **16 m** pose RMSE where following the chain
outward from the prior gives **0.2 m**. `core.eliminationOrder` therefore
ranks hop distance from the prior above separator dimension.

## Plaza: the real data

`Plaza1` and `Plaza2` are the Djugash range-only datasets the NF-iSAM paper
reports on, loaded from the survey files rather than regenerated. A case is
one window of the sequence, sized against a cap on **variables** rather than
on poses: eight keyframes by default, and on Plaza1 that lands at keyframe 24
holding eight poses and two landmarks, **ten variables** under a cap of
thirteen. The cap is on the variables because the landmarks a window ranges
are half of what it holds, and how many there are is a property of where the
robot was rather than a number anyone chose.

That count is a **budget, not a safety margin**. This README used to call six
variables "under half the smallest count any layout has been seen to fail at";
that reading was falsified in the grid world, where adding three variables to
the warehouse made the error *fall*. Ten variables is not a claim that this
window is safe — it is a claim about what the window costs.

The landmarks are **eliminated last** because their posteriors are bimodal and
handing that density to the poses costs an order of magnitude of pose RMSE.
They are deferred inside the ordering loop, not filtered out of a finished
order: `core.eliminationOrder` uses them as connectors, so lifting one out
afterwards strands whatever it joined.

At the manual's own settings — 150 posterior samples, 100 MMD samples,
threshold 1e-4, 2000 NF-iSAM training samples — protocol P1-A, known
association, on the window as loaded:

| method | pose RMSE | aligned | landmark RMSE | runtime |
|---|---|---|---|---|
| Slices | 0.699 m | 0.611 m | 24.97 m | 2.6 s |
| NF-iSAM | 0.451 m | 0.042 m | 2.26 m | 186.8 s |
| Smoothed Slices | 0.541 m | 0.313 m | 23.64 m | 2.3 s |
| *dead reckoning* | *0.414 m* | *0.087 m* | — | — |

**The baseline row is new, and it changes how the table reads.** It is the
window's odometry integrated alone, from the true first pose and heading — the
same anchor the estimator gets from its prior — so the two start level and only
the estimates also see the ranges. It had never been compared against: the case
has carried `plaza.deadReckoned` since the loader was written and used it only
to draw a dotted line, so no metric, protocol or table put the two side by
side. Both columns are now in `experiments.runPlazaProtocol` output.

Against it, the three methods split rather than fail together:

- **Unaligned, all three lose.** 0.699, 0.451 and 0.541 m against 0.414 m.
- **Aligned, NF-iSAM wins and the two Slices variants lose.** 0.042 m against
  the baseline's 0.087 m, a factor of two; Slices and Smoothed Slices are
  0.611 and 0.313 m, worse than doing nothing.

Reporting only one of those columns would have supported whichever conclusion
it sat next to, which is why the baseline is carried in both.

Across three seeds, on the unaligned column:

| window | variables | pose RMSE | baseline | ratio |
|---|---|---|---|---|
| Plaza1, default | 10 | 0.541 – 0.634 m | 0.414 m | 1.31 – 1.53 |
| Plaza2, default | 10 | 0.890 – 1.206 m | 0.775 m | 1.15 – 1.56 |
| Plaza1, one lap | 19 | 0.822 – 2.473 m | 0.736 m | 1.12 – 3.36 |
| Plaza2, one closure | 38 | 4.926 – 5.539 m | 5.193 m | 0.95 – 1.07 |

Over a short window this is a **hard baseline, not a straw man**: eight
keyframes of good odometry have barely drifted, so there is very little for a
range reading to correct, and the sampling noise the estimator adds costs more
than the ranges return. That is why the ratio falls as the window grows and
the drift accumulates — on Plaza2's 34-pose closure, where dead reckoning has
itself drifted to 5.19 m, Smoothed Slices finally draws level.

What the numbers do **not** support is that a longer window fixes this. The
Plaza1 lap gets *worse* and far more seed-dependent, 0.822 to 2.473 m across
three seeds, which is weight degeneracy showing through rather than geometry:
minimum `essSupport` on those runs is 1.0 – 2.4 out of 201.

**These are not the numbers this table used to carry**, and the difference is
the window rather than the methods. On the old four-keyframe window the three
pose RMSEs were 0.207, 0.185 and 0.237 m; at eight keyframes every one of them
roughly tripled, in the same order and by about the same factor. That is the
one grid-world result that did survive falsification — within a fixed
geometry, error rises sharply with mission length — showing up on real data.
A longer window is a harder problem, not a better-measured one.

"Aligned" is after Kabsch–Umeyama onto the surveyed track, rigid only: no
scale and no reflection, since ranges are metric and a reflection would be
mode collapse rather than a fit. Both columns are reported because the gap
between them **is** information — aligned-only would hide a rigid drift, and
unaligned-only is not what the papers report.

**The landmark column is not an accuracy comparison.** The Plaza landmark
posterior is bimodal: range-only observations from a short pose chain fix a
landmark up to reflection in the chain. Checked against the readings
themselves, on the eight-keyframe window and Slices' posterior:

| landmark | readings | truth explains them | posterior *mean* explains them | mean's distance from truth |
|---|---|---|---|---|
| `l1` = node 1 | 7 | 1.42 m | 6.31 m | 12.4 m |
| `l2` = node 6 | 5 | 1.56 m | 10.44 m | 33.1 m |

A mean sitting **33 m** from truth explains the readings only 8.9 m worse than
truth does. That gap is the signature: `landmarkRMSE` here measures **mode
separation**, not estimate quality, and a method that collapsed one mode would
score better for doing it. Both figures were re-measured on this window — the
earlier 0.51/1.25 m and 15.9/18.2 m were the same check on the four-keyframe
one, and the conclusion is what carried over, not the numbers.

The manual's own L2 specification does not transfer to this data, and
`experiments/plazaLandmarkWindows` says so with the mapping table rather than
quietly substituting: it derives the evidence ladder from the data instead,
returning windows at distinct numbers of *observing poses* rather than raw
readings — the two differ because the loader thins to a maximum number of
readings per pose–landmark pair.

## The open research question

The research instruction sheet asks one quantitative question: **when does
Smoothed Slices reduce computation relative to Slices nested sampling, and by
how much** — measured in factor evaluations, not wall time, which confounds
the algorithm with the machine and would flatter the method that turns a
sample tree into a matrix product.

**Answer, on the two-pose benchmark at seed 3:** Smoothed Slices reduces
computation. Budget for budget it costs **83–97 %** of Slices' evaluations at
**81–99 %** of its error — cheaper *and* more accurate at every shared
budget, which is dominance rather than a matched-quality trade. But the
saving shrinks as the budget grows (83 % at *N* = 50 → 97 % at *N* = 400),
and the fitted exponents say why: work ~ *N*^α gives **α = 1.89** for Slices
and **1.97** for Smoothed Slices, both at r² = 1.000. The surfaces buy a
**constant factor, not a change in growth class**.

**Where the question cannot be asked at all**, which is the larger finding.
`innerEstimator` is consulted *only* on the Lemma 1 structural route, which
elimination takes when a variable has neither a unary factor nor an
eliminated neighbour:

| case | Slices | Smoothed Slices | |
|---|---|---|---|
| Four Doors | 290,916 | 290,916 | identical |
| grid world | 1,940,172 | 1,940,172 | identical |
| Plaza2 | 1,932,540 | 1,932,540 | identical |
| two-pose | 5,233,463 | 5,018,663 | differs |

On three of four cases the two methods are the same computation, so
`research.costQualityFrontier` returns **"mechanism not exercised"** rather
than a verdict when the cost columns match. Without that guard it reported,
confidently, that Smoothed Slices needed 1.68× the evaluations on Four Doors
— a number that was really about which method wanted a bigger budget.

`viz.plotCostQuality` draws the sheet's decisive figure: error against
measured factor evaluations, log–log, with matched-quality ties connected and
the verdict in the title. NF-iSAM is excluded from that axis **with its
reason attached**, because Algorithm N1 simulates from its factors rather
than evaluating them, and a zero-cost point would show it winning infinitely.

**It is answerable from the app, not only from a script** — the eleventh tab,
**Research Question**, runs the measurement and reports it. Two panels,
because one of them cannot distinguish the two possible answers on its own:
error against measured evaluations, and beside it the same measurement as
*work against budget*. A constant-factor discount and a change in growth
class look identical on the first plot and completely different on the
second, and the sheet's hypothesis was specifically about growth class. One
verdict **per scenario** with its evidence string, because the scenarios
disagree — dominance in two of six, no reduction in others — and a single
headline would be a median over disagreeing measurements.

**What the sheet asks for and this does not yet do:** E6, the ablation. It is
scheduled rather than dropped, and it has a constraint worth stating before
anyone starts it: on three of the four cases the inner estimator is never
consulted, so an ablation there would compare a setting against itself and
read as "no effect" for entirely the wrong reason. It needs a case that
provably takes the nested route, and the harness must **assert** that it did.

## Are the surfaces actually compact? (E2)

The question above asks whether the method *saved* anything. This one asks
whether the **reason it would** is true, and it is the sheet's own framing:
the idea is stated as a conditional — *if* the surfaces `R_r` are lower-rank,
sparse or well approximated by small active successor sets, *then* the cost
can move. Everything left of that "then" is measured by
`research.surfaceComplexityStudy` and `research.activeSetProfile`, drawn by
three panels on the **Surface Complexity** tab.

**The surfaces are compact, on every configuration swept.** Six of the 99 %
energy directions carry a 120 × 101 surface at the baseline, and across 17
configurations that figure runs 2–8. `rank_eps` is looser and averages 20 % of
full — both are reported, and the verdict is taken on the *smaller* of the
two, so quoting only the flattering number would have been easy and is what
the evidence string exists to prevent.

**A control decides whether any of that is readable.** One swept knob — the
odometry σ — *cannot* reach the surface: it belongs to a front factor `b_0`
that multiplies the slice matrix after `R_0` is built. Sweeping it must leave
every statistic identical, and it does, to the bit. That is what licenses the
two knobs that do move things: widening the fusion factor takes the energy
rank 8 → 2 and sparsity 0.83 → 0.35, and it is the dominant axis by a wide
margin. Multimodality and overlap width — the two variables the sheet
emphasises — barely register.

**But the active set is where it fails.** `research.activeSetProfile` runs the
same case at each `K` and measures the distance from the dense update of
Eq. (48). To match the dense *surface* to 10⁻³ takes **K = 96 of |X₁| = 120**,
which is the sheet's own failure signal — "K must approach |X_{r+1}|" — met
almost exactly. To match the dense *answer*, `K = 32` is enough: it scores
0.084 against the quadrature reference, inside the band the dense run's own
0.076 sits in. **The two criteria disagree by a factor of three**, so the
headline carries both rather than picking one.

**And the predicted saving is not a measured one.** The cost model
`|X_0| |N_0| |S|` is linear in `K` and predicts a **48×** spread across the
tested range. The factor-evaluation counter moves by **1.000×** — not at all —
because `evaluateSurfaceRecursion` evaluates `g_0` over the whole
|X₀| × |X₁| grid and the fusion factors over the whole |X₁| × |S| grid
*before* `buildActiveSuccessors` chooses what to keep. The active set
sparsifies a matrix that has already been paid for. That is a property of this
implementation and not of the idea — an active set chosen without consulting
every successor would realise the saving — but until something does that,
`predictedCost` is a model and `evaluations` is the measurement, and
`OUT.costRealized` exists so the two are never quoted as if they agreed.

**What the sheet asked for, and where each piece is**, including the one thing
that had to be substituted rather than built:

| sheet, section 10 | here |
|---|---|
| singular-value decay of `R_r` | `viz.plotSurfaceSpectrum`, markers at the 99 %-energy rank |
| numerical rank **vs step** | `viz.plotSurfaceRankVsAxis`, **vs difficulty instead** — the one case with a surface has a single Lemma 1 elimination, so there is no step axis to plot against, and a one-point line under that title would be a figure pretending to a sequence |
| sparsity heatmap | the sparsity *series* on that same panel; the surface itself is already drawn as a heatmap by `viz.plotSmoothingSurfaceStep`, and a second one thresholded at `nnz_eps` would be the same picture twice |
| active-K vs error curve | `viz.plotActiveSetError`, with `\|X_1\|` and both criteria marked |
| `rank_eps`, `nnz_eps` saved to diagnostics | `Diagnostics.inner.surface` on every surface update, and an E2 block in the exported `diagnostics.md` |

E2's fourth independent variable, **nonlinearity, is not swept at all**. The
only case that builds a surface is linear-Gaussian by construction — its modes
come from an explicit two-component mixture, not from the annulus of a real
range measurement — and the cases with genuinely nonlinear factors are exactly
the ones running the general engine, which never consults `innerEstimator`. On
this case the sheet's nonlinearity axis and its multimodality axis are the
same knob, and `OUT.note` says so rather than letting a reader assume four
axes were varied.

## Seeing the elimination

Two panels, side by side on Case Study and again in the Process Explorer,
driven by the stage slider:

- **Factor graph** — G_{j-1} as it stands when step *j* begins. The variable
  being eliminated is red, the factors that go with it orange, the separator
  blue, and the factor about to be generated green and dotted. Variables
  already eliminated stay on the canvas, ghosted, so the graph visibly gets
  denser as they leave.
- **Bayes net** — the conditionals the elimination *creates*. Arrows point
  S_j → ω_j, which is also the order the backward pass must sample in, and
  each node carries its elimination index so the procedure can be followed
  across the map.

Both replay the elimination structurally from G_0 through
`core.eliminationSchedule`, so they need no run to draw and cannot disagree
with each other about a separator. A test asserts the replay matches what the
engine actually did. On the grid world the layout puts every node at its true
position: the factor graph of that case *is* the map, with beacons tied to
the poses that saw them.

## Incremental replay

Tick **replay increment by increment** on Case Study (`'incremental', true`
in the config) and the mission is re-derived the way it arrives: at increment
*k* the graph holds only the variables and factors introduced up to *k*. Two
reuse rules then have somewhere to stand, and they cut the pass from opposite
ends.

**Forward — surfaces reused across increments.** A new pose adds odometry and
some ranges, all at the far end of the elimination order, so every step before
the first one those factors touch has identical inputs to the step of the same
name at *k-1*. `methods.general.StepCache` keys a step on a running digest of
its whole prefix, which means it reuses the longest **unchanged prefix** of the
elimination and recomputes from the first step the new data reached.

**Backward — Algorithm S5 early stopping.** Root-to-leaf is newest-to-oldest,
so walking back through the trajectory and stopping when a marginal stops
moving stops walking back in *time*. The poses behind the boundary keep the
samples they had.

Measured on the grid world, six poses, default budgets:

| configuration | pose RMSE | runtime | factor evaluations | steps cached |
|---|---|---|---|---|
| batch (default) | 0.653 | 3.0 s | 11.3 M | — |
| replay, both rules | 0.542 | 2.8 s | 14.4 M | 55 % |
| replay, no cache | 0.542 | 4.7 s | 36.1 M | 0 % |
| replay, no stopping | 0.536 | 2.0 s | 14.4 M | 55 % |

Three things worth reading off that table, all of them things the feature does
*not* do:

- **The cache changes the cost and not the answer.** 2.5× fewer factor
  evaluations, and the marginals are identical to the last bit — pinned by a
  test, not by a tolerance. Per-step seeding is what buys that: each step's
  stream is derived from its own signature, so a skipped step cannot shift the
  randomness of the steps behind it.
- **Early stopping costs more than it saves at this size.** Turning it on adds
  0.8 s, because computing an MMD per variable is more work than the
  nearest-neighbour lookups it avoids on the office grid world's
  thirteen-variable graph. It is a
  rule for a Plaza2-length trajectory, where the tail left unvisited is
  hundreds of poses rather than six.
- **The replay costs more in total than the batch pass.** 14.4 M evaluations
  against 11.3 M. You are buying an answer at every *k*, not a cheaper answer
  at *K*; the cache pays back most of the difference, not all of it.

**The paper's stopping threshold is below its own noise floor.** At N_M = 100
the sampling noise on MMD² is of order 1/N_M, so ϑ = 1e-4 cannot be reached by
either estimator on marginals that genuinely differ. Every stop this code makes
is therefore a stop on a U-statistic that went *negative* — the estimator
declaring it cannot separate the two sets. That is a defensible rule and it is
not the rule as written, so the count of such stops is reported on every run:

> 4 of 4 early stops were made on an MMD estimate that had gone negative: at
> N_M = 100 the U-statistic cannot separate the two marginals, so the rule
> stopped because it could not tell rather than because nothing moved.

## Decisions worth knowing

- **Explicit proposals, not resampling.** The support is kept as weighted
  candidates rather than resampled to |S|. Resampling would leave the support
  distributed according to `f_new`, which sounds strictly better and is not:
  at an ESS of two it yields hundreds of copies of a handful of distinct
  points, and the nearest-neighbour lookup everything downstream depends on
  has nothing left to snap to.
- **Beacon placement sets the treewidth.** Beacons in the map interior are
  seen from opposite ends of the mission and tie those poses together, taking
  separators past ten dimensions. The corridors are lined with beacons
  instead, so visibility is local and the graph stays banded.
- **The range factor's normalizer carries the polar Jacobian**,
  `Z = 2π(r·Φ(r/σ) + σ·φ(r/σ))`, verified against 2-D quadrature. Its sampler
  draws the radius from `ρ·N(ρ;r,σ)`, not `N(ρ;r,σ)` — the latter still plots
  as a donut but over-weights the inner edge.
- **Indexing.** The Smoothed Slices spec is inconsistent about `R`'s index:
  §7 writes `R₁(x₁,x₂)`, §9 writes `R_r(ξ_r,s)`. The code follows §9 — the
  form §10's matrix recursion implements — and documents the mapping.
- **Node weights.** The RCS support is quantile-spaced, so each support point
  carries its Voronoi width; row-normalizing raw `g₀` values would integrate
  against the wrong reference measure.
- **Shared driver.** Slices and Smoothed Slices differ in exactly one config
  field. On a general graph that field selects the active successor sets of
  Eq. (49) — without them the two would be bit-for-bit identical and two
  robots would draw on top of each other.
- **MMD.** Neither paper specifies kernel, bandwidth or estimator. All three
  travel with every reported value. `N_M = 100` is the paper's
  *early-stopping* budget and is kept separate from the evaluation budget.
  The stopping test compares **MMD² against ϑ² on the unclamped estimate**:
  the U-statistic is unbiased for MMD², not for MMD, and testing the clamped
  square root would make every negative estimate compare equal to zero and
  stop unconditionally — a threshold that looks consulted and never is.
- **An increment extends the elimination order, it does not re-derive it.**
  Four Doors forces this: a door sighting *is* a unary factor, so the ordering
  heuristic promotes the pose that saw it to second place and shifts every
  step behind it. Re-running the heuristic per increment took the cache hit
  rate from 67 % to 40 % and, worse, broke the newest-to-oldest traversal that
  early stopping stands on. New variables are appended in the heuristic's
  relative order instead, and Lemma 1 is re-checked rather than assumed.
- **The export saves a record, not a checkpoint.** Generated factors nest —
  each carries the factors it was built from, which carry their own slice
  matrices — so saving the raw run reached 1.2 GB on the grid world and the
  v7.3 write failed *after* every figure had been written. `run_state.mat`
  now holds a per-step `eliminationSummary` instead; `KeepStates` brings the
  internals back when a run is being saved to be debugged.
- **The authors' `n_train = 2000` overfits a four-dimensional clique, and the
  paper's stopping rule cannot see it.** The rule watches the training loss,
  which keeps improving as the flow memorises. Measured on a clique whose
  posterior is known exactly: at 2000 samples the fit reported a flattened,
  converged loss curve and returned a marginal of standard deviation **0.85
  where the truth is 1.0**, the error concentrated at the measured value —
  precisely where the answer is read. At 8000 it is 1.00, and train and
  held-out log likelihood agree. So `trainFlow` gained an opt-in `Holdout`
  that scores reserved samples, because the failure is otherwise a *confident*
  wrong posterior. It does not change the stopping rule, which is the
  authors'. The default batch size is 2000 rather than the full batch for the
  same finding's sake: the sample count that fixes the fit is the one that
  makes full-batch iterations expensive, and minibatching that clique was
  4× faster **and** more accurate.
- **NF-iSAM's flow cache is keyed on clique identity, not on the changed
  subtree.** Spec §7 step 2 extracts the cliques the new factors touch, and
  that is the right answer to the question it asks. It is not sufficient here,
  because this implementation rebuilds the Bayes tree after each update rather
  than re-eliminating it surgically, and a rebuild can reshape a clique that
  lies *below* the changed subtree: whether a variable merges into its parent
  depends on the **parent's** separator, which a distant loop closure can
  grow. Adding `f(x3,x5)` to a five-pose chain that already closes `x2–x4`
  moves a clique from
  `x2 x3 : x4` to `x2 : x3 x4` while step 2 names the root alone — the
  reshaped clique being the root's *child*, not its ancestor. So retraining is
  driven by a subtree key (the clique's frontals, separator and factors, plus
  its children's keys), and step 2's answer is computed alongside and
  reported. `info.outsideSubtree` is where the two disagreed.
- **A child hands its parent samples, not a factor.** Spec §7 says to append
  `p(S_C)` to the parent clique as a factor, and Algorithm N1 never evaluates
  a factor — it simulates from one, so draws are exactly what the appended
  factor would have been asked for. Passing a `core.Factor` instead would be
  refused outright for a separator wider than two variables, and N1 samples a
  factor one variable at a time, which would discard the correlation between
  separator variables — the one thing the child learned that the parent cannot
  rederive. Where two children's separators coincide, their densities are
  multiplied by weighting the first child's draws and resampling; the
  effective sample size travels with the result.
- **The two NF-iSAM passes move opposite ways, and that is not symmetry for
  its own sake.** Training goes leaf to root because a clique's flow must be
  fitted to what its children already learned, which reaches it as separator
  draws. Sampling goes root to leaf because a clique's frontals are
  conditioned on its separator, whose values the parent decides. Row `n` of
  every variable comes from the same descent, so a draw of `x1` and a draw of
  `l5` belong to one trajectory even though no flow ever saw both. Drawing
  each clique from a fresh separator sample instead would give correct
  marginals and a joint that is their product — an error invisible in every
  per-variable plot. On the three-variable chain whose posterior can be
  written down, `corr(x1,x3)` comes out **0.468 against an exact 0.471**, and
  those two variables share no factor and no flow.
- **NF-iSAM is scored against the *normalized* reference, and says so.** The
  elimination methods return the unnormalized `f_new` of Eq. (19) and its mass
  is a result in its own right. A flow is a density: there is no unnormalized
  counterpart to report, so `posterior.estimator.normalized` is true, the mass
  error is `NaN` rather than a large number the method cannot avoid, and
  `scoreAgainstReference` compares against `ref.pdf`. The curve itself is a
  kernel density estimate of the draws, marked as a reconstruction on the
  result — the MMD and the RMSE the comparison turns on are computed from the
  draws directly, where no bandwidth choice can reach them.
- **NF-iSAM makes zero factor evaluations, and that is a result rather than a
  gap.** Algorithm N1 is generative: it draws from a factor and never asks one
  for a value. Next to the ~3×10⁷ evaluations the elimination methods spend on
  the Eq. (16) case, a `0` in that column reads as a stub unless it is said
  out loud, so the result carries a log line saying what this method spends
  instead — clique fits, measured in runtime.
- **RMSE** is reported with the standing warning that it hides
  posterior-shape errors — the reason this app exists. On Four Doors the mean
  of a four-mode posterior is a place the robot has never been.
- **Stop keeps what finished.** Cancelling a run of three methods during the
  second leaves one complete answer in hand, and discarding it to report a
  clean failure would make the button cost more than it saves. The methods
  that did not finish get a result of the right shape with `NaN` metrics —
  never `0`, because a zero in a runtime column reads as *instant*.
- **Cancellation is only possible because the progress bar yields.** MATLAB
  shares one thread between the UI and the computation, so a Stop callback
  cannot fire while an elimination is running. The bar's `drawnow` is the
  entire mechanism, which is why it is plain rather than `limitrate` —
  `limitrate` may return without flushing the event queue — and why the rate
  limiting lives in `ProgressReporter.MinInterval` instead, where it is also
  the worst-case lag between pressing Stop and the run noticing.
- **"ESS" means three different things, so the column says which.** The
  three-node engine reports it for the outer slice weights, the general engine
  for the separator support, NF-iSAM for the product of child separator
  densities. One column headed *ESS* would invite comparing unlike numbers.
- **Only one of the two memory columns is the method's.** Result MB is the
  serialized size of what a method handed back: deterministic and comparable.
  Process MB is the whole MATLAB process at the instant that method returned.
  MATLAB cannot measure the high-water mark of a block of code, so no peak is
  reported rather than a plausible-looking number that is not one.
- **A budget that differs needs a reason, and a shared note is not one.**
  `commonMethodConfig` attaches provenance like *"paper: 150 (Plaza2)"* to
  most budgets and every method carries that same string away. It says where
  the default came from and nothing about why two methods diverged, so the
  Compare Methods tab counts as an explanation only a note that not every
  method carries — otherwise it reports *"NO method recorded why"*. And it
  reports agreement only when at least two methods finished: with one, every
  budget trivially agrees with itself, and rendering that as a green *every
  budget agreed* would give a stopped run a pass for a check that never ran.
- **A stopped run never reaches a full bar, anywhere.** Both `runComparison`
  and the exporter used to announce their closing state unconditionally, so a
  run stopped at 40% walked its bar to 95% on the way out and a stopped export
  finished at 100% under the word *complete*. The bar is held where the
  cancellation landed instead. The colour says *stopped*, but the fill is what
  a glance actually reads.
- **The `drawnow` that makes Stop work makes every other button work too.**
  It is the one mechanism and it cuts both ways: with `Run Selected` left
  enabled, pressing it mid-run started a second `runComparison` *inside* the
  first, on the same `app.Results`, with the outer run overwriting the inner
  one's answer on the way out. Every control that starts work is disabled for
  the length of any work, runs and exports alike.
- **One run, two bars.** The results belong to the app rather than to the tab
  whose button was pressed, so the bar on the other tab mirrors the live one
  instead of sitting on the previous run — a green *done: 3 of 3* next to a run
  that had just been stopped after one method is the same lie as a full bar,
  told one tab over. The mirror never gets a live Stop: one run with two
  cancel buttons is a second thing to reason about and buys nothing.
- **A progress view reads the run's state, not its own.** `ProgressReporter`
  children share the root's cancellation *and* its fraction, message and
  counters. Storing those per object while writing only the root's meant a
  sub-view could sit three quarters through a run and still answer `Fraction
  0` — which `runComparison` depended on not happening when it held the bar at
  a Stop by reading `p.Fraction`.

## Iteration status

| # | Theme | State |
|---|---|---|
| 1 | Engine core + two-pose range benchmark, validated against quadrature | **done** |
| 2 | General graphs, grid world, Four Doors, map view, Process Explorer, incremental replay | **done** |
| 3 | NF-iSAM (Bayes tree, Algorithms N1–N3, flow backend, root-to-leaf sampling); Compare Methods and Diagnostics tabs; progress and cancellation | **done** |
| 4 | Four case studies, each swept rather than shown once; **real Plaza data**; the open research question measured; and the surfaces measured for compactness (E2) | **done** |
| 5 | RCS Modes B/C, surface-guided proposals; an active set chosen **without evaluating every successor first**, which is what would turn E2's predicted saving into a measured one; the ablation (E6); and **what actually predicts the grid-world failure**, now that variable count does not | **next** |

**Iteration 4 is not the one originally planned here, and the reason is a
measurement.** This table used to schedule RCS Modes B and C for iteration 4
as the documented fix for the thirteen-variable cliff. They moved out because
the diagnosis they were the fix for did not survive being measured.

The cliff is not about separator width — the largest separator is three
variables at every pose count, including the one that fails, and the
warehouse fails on separators narrower still. And the *number* does not hold
either: the warehouse fails at ten variables where the office is fine at
thirteen, so there is no single size to build past. A richer surface
representation may well be worth having, but "it fixes the thirteen-variable
ceiling" is not a reason to build it, because there is no thirteen-variable
ceiling. Modes B and C are still scheduled; they are no longer being built on
the strength of a diagnosis nobody had checked.

What landed instead: the Plaza datasets that were scheduled for iteration 5,
because a method comparison on synthetic data only is a comparison of
generators; a sweep plan per case study, because a single run says which
method won on one problem at one budget and nothing about the methods; and an
answer to the research sheet's open question, together with the refusal to
answer it on the three cases where the mechanism it asks about never runs.

Both items carried out of iteration 2 — MMD early stopping and RCS surface
caching across increments — landed with the replay loop described above.

Seven of specification section 5's eight tabs are built, plus two beyond it:
**Sweep**, because no single run distinguishes a method that loses to
sampling noise from one that is biased, and **Plaza**, because the only real
data in the app is solved on a *window* and a panel that does not show which
window leaves the numbers unreadable. **Figure Generator** is now built: it
reads the figure registry into a checklist so that what an export will
contain — including which axes are registered but still empty, and therefore
about to be written as blank images — is visible before the export runs.

**Implementation Notes is dropped, not deferred.** It was to carry equations,
file provenance and per-method checklists. Each of those already has a home
that cannot drift out of step with what it describes: the equations sit in
the function headers beside their code, the provenance in
`data/PROVENANCE.md`, and the checklists are the test suite. A tab restating
them would be a fourth copy of three things that already disagree whenever
one is edited alone.

## Environment

MATLAB R2026a. Uses Statistics and Machine Learning Toolbox
(`pdist2`, `kmeans`, `quantile`, `normpdf`), Signal Processing Toolbox
(`findpeaks`) and, since iteration 3, Deep Learning Toolbox (`dlarray`,
`dlfeval`, `dlgradient`, `adamupdate`) for NF-iSAM's normalizing flows.

The flows are MATLAB-native rather than a PyTorch bridge, so the method runs
in one process and inside this test suite. Note that `cumsum` is not a
differentiable `dlarray` operation; `rqSplineTransform` builds its knots with
a triangular matrix multiply for that reason.
