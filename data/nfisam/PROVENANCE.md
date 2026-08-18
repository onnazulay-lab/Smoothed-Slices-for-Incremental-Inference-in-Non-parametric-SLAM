# NF-iSAM factor graph fixtures

Two small factor graphs vendored from the NF-iSAM release, used as fixtures for
`datasets.readFactorGraphFile`. They are here so the reader has something to
parse in the test suite without a network call, and because they are the two
files that between them exercise every record kind in the format.

| file | upstream path | records |
|---|---|---|
| `case1.fg` | `example/slam/small_range_gaussian_problem/journal_paper/case1/factor_graph.fg` | poses, landmarks, prior, odometry, ranges |
| `case1_da.fg` | `example/slam/small_range_gaussian_problem/journal_paper/case1_da/factor_graph.fg` | the same plus `AmbiguousDataAssociationFactor` |

## Source

- Repository: <https://github.com/MarineRoboticsGroup/NF-iSAM>
- Commit: `3974eb9839122c825c4164b57296af44d3079187` (2022-10-19)
- Licence: MIT, held by the Marine Robotics Group. Vendored under its terms;
  the files are unmodified.
- Paper: Huang, Hsiao, Leonard et al., *NF-iSAM: Incremental Smoothing and
  Mapping via Normalizing Flows*, T-RO 2023.

## What is NOT vendored

The eight Plaza factor graphs under `example/slam/plaza_dataset/RangeOnlyDataset/`
(`Plaza1EFG`, `Plaza2EFG`, and the `ADA0.2/0.4/0.6` ambiguous-association
variants) are 276–424 KB each, about 2.8 MB together. They are the ones a case
study actually runs on, but they are large enough that pulling them in should
be a deliberate act rather than a side effect of cloning. Fetch them from the
commit above into this directory when they are needed.

Note that these files are NOT the same problem as the ones
`datasets.loadPlazaDataset` builds, even though both descend from the same
Djugash survey. Theirs carry 778 poses on Plaza1 against our 305 keyframes at
6 m spacing, and their landmarks are renumbered `L0..L3` where the survey calls
them 0, 1, 5 and 6. Comparing a number measured on one against a number
measured on the other is comparing two keyframings, not two methods.
