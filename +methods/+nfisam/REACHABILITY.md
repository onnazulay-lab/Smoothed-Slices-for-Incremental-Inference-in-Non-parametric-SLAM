# NF-iSAM: what Algorithm N1 can and cannot simulate

A documented limitation of the method as specified, not a defect in this
implementation and not a property of the cases it fails on. It is recorded here
because two cases in this repository hit it, and because the honest response to
a structural limit is to state it rather than to reshape the experiment until
it stops appearing. A third case that this document used to cite turned out to
be a bug in the validator, and is recorded below as such.

## The limit

NF-iSAM trains each clique's normalizing flow on samples it generates itself.
Algorithm N1 builds those samples **generatively**, in three steps: start from
what the clique already holds, draw the variables that priors cover, then walk
outward along binary measurements, simulating one endpoint from the other. Data
association is handled last, and is explicitly not allowed to introduce a
variable — a multimodal factor selects among candidates that must already be
reachable.

The consequence is that reachability is a property of the *generative route*,
not of the information content of the graph. A variable can be perfectly well
determined by the posterior and still be unreachable, because being
*constrained* by a factor and being *simulable* from it are different things.
An optimiser does not care about the difference. A method that must manufacture
its own training samples does.

`methods.nfisam.reachabilityPreflight` decides this deterministically, before
any flow is fitted, and names which of four things went wrong:

| reason | what it means |
|---|---|
| *stranded* | The variable is touched by no prior and no binary factor. No generative route to it exists at all. |
| `notInvertible` | A binary factor was reached from one side and refuses to simulate the other. The route exists but does not run in that direction. |
| `associationUnreached` | A data-association factor's latent variable was not already reachable. Step 4 may choose among candidates; it may not create one. |
| `frontalUnreached` | A frontal variable survived all three steps unreached. |

These are four different findings and the failure packet keeps them apart. "The
clique was unreachable" is not a diagnosis.

## Why it is not fixed here

It could be made to go away, and each way of doing so would cost more than it
buys:

- **Let a multimodal factor introduce its latent variable.** This is what
  section 14 of the closeout brief forbids. It would mean the data-association
  factor inventing the landmark it is supposed to be choosing between, which
  changes what the ambiguity experiment measures.
- **Let the preflight supply what the simulator could not.** The preflight's
  own header refuses this: it is a validator, and if it and the simulator ever
  disagree, the simulator is right.
- **Change the case until the method runs.** The standing rule is that all
  three methods receive the same case definition. A case edited to suit one
  method stops being a comparison.

So the failure is exported instead. `methods.failedResult` records it in the
unified contract with its identifier, message and stack, and the other methods
on the same case keep their results — which is what makes the limit *measurable*
rather than merely fatal.

## Where it has been observed

Two genuine cases, plus one withdrawn, listed with what is actually pinned
about each.

**Grid World, warehouse layout** — landmarks `l2`, `l3` and `l6` are stranded:
no prior, no binary factor. Pinned by `tests/tNFiSAMReachability`, which asserts
the stranded set exactly so that a change to the case is caught rather than
absorbed. The replay fails naming `l2`.

**Grid World, corridor layout** — strands a landmark on the same grounds, and
additionally raises `associationUnreached` under `Association="ambiguous"`.
Recorded as evidence beside regression-matrix row 4, which does not let it vote
on the verdict because row 4's named case is the office layout.

**Plaza1, `Association="known"`** — *withdrawn; this was a validator defect, not
the limit.* The preflight refused increment 6, clique `(x6 l2 l1)`, reporting
`frontalUnreached` on `l2`. But the same packet showed `l2` in the clique's
`given` set: it arrives as a child's separator density and appears in no local
factor. `reachabilityPreflight` built its variable universe from
`[factors.Scope]` alone, so `l2` was not in the mask that the very next line
seeds from `Given`, and a variable the clique already held was reported as
unreached. `trainingSampleSimulator` seeds `S = opts.Given` directly and would
have proceeded. The two disagreed, and by the rule stated above the simulator
is right. Fixed by including `Frontal` and `Separator` in the universe.

The consequence is worth stating plainly, because it cuts the other way from
everything else in this file: for as long as that line stood, NF-iSAM was being
denied Plaza cases it can run, and any comparison drawn from those runs
understated it.

## What this does and does not license as a claim

It supports: *Algorithm N1's generative training-sample construction cannot
reach every variable that the corresponding factor graph determines.* The
observed instances are synthetic Grid World layouts, where a landmark is
touched by no prior and no binary factor at all.

It does **not** support any claim that the limit has been observed on real
range-only data. That claim was made here on the strength of the Plaza1 case
and is withdrawn with it. Whether NF-iSAM completes Plaza1 under the corrected
preflight is a measurement that has not been made yet, and until it is, this
file should not be read as saying either way.

It does not support any statement about NF-iSAM's posterior accuracy, runtime,
or the quality of the flows it fits when it does run. A method that declines a
case has told you about its preconditions, not about its answers.

See also `methods.nfisam.reachabilityPreflight`, `methods.nfisam.factorRole`,
`methods.failedResult`, `tests/tNFiSAMReachability`.
