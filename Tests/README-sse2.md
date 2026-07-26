# SSE2 fill pattern check - working branch

The vector implementation of `CheckFreedDebugBlockFillPatternIntact`, offered to
Pierre under [PR #97](https://github.com/pleriche/FastMM5/pull/97#issuecomment-5078706031)
on 2026-07-25. **No pull request was opened on purpose** - he asked in #101 not
to be sent unsolicited PRs, and this routine is on his own to-do list. This
branch exists so the work survives and can be handed over the moment he asks.

## What the change does

`pcmpeqb` against a broadcast fill byte, with the comparison results accumulated
using `pand` instead of being branched on. That preserves the single loop exit
and the data independent run time of the current scalar code. One `pmovmskb`
against `$FFFF` at the end decides the result. 64 bytes per iteration.

Two deliberate constraints keep it low risk:

* Only whole 16 byte units go to the vector helper; the freed object marker and
  the trailing bytes stay on the existing scalar path. The diff is **+140 lines,
  0 removed**.
* The vector path engages only from `CMinimumVectorFillPatternBytes` (128) whole
  vector bytes upward, so smaller blocks execute exactly today's code. "No
  regression for small blocks" is therefore a property of the code, not a
  measurement claim.

SSE2 only, matching what the file already does for the move routines: guaranteed
under 64-bit, gated on `System.TestSSE and 2 <> 0` under 32-bit via
`FillPatternSSE2Available`, which is set in `FastMM_InitializeMemoryManager`.

## Measured

Intel Core i9-12900K (Alder Lake, pinned to a P-core), Windows 11 build 26200,
Delphi 13.1. Median of 25 alternating pairs, each sample in a fresh process.

| User size | Win64 | Win32 |
|---:|---:|---:|
| 64 B (control, path unchanged) | -1.0% | +1.9% |
| 128 B (control, just below threshold) | -0.7% | +2.4% |
| 136 B (first engaged size) | +0.3% | +4.5% |
| 256 B | +3.2% | +10.7% |
| 1 KiB | +18.9% | +36.0% |
| 4 KiB | +65.2% | +106.5% |
| 16 KiB | +87.5% | +158.1% |
| 64 KiB | +41.6% | +80.2% |

Win32 gains most, which is where PR #97 was weakest (+3.30% on Intel Win32 at
4 KiB), so this lands on the side the scalar widening could not reach.

## Independent reproduction, and what it found

janrysavy reconstructed the approach from the description and the assembly loop
and measured it on a Ryzen 9 7950X and a Core i7-8750H, Win32 and Win64, on top
of `823ba35`
([#97 comment](https://github.com/pleriche/FastMM5/pull/97#issuecomment-5082105575),
patch on [janrysavy/FastMM5@9e0ce1a](https://github.com/janrysavy/FastMM5/commit/9e0ce1afb4ed60e47f071f10ac9c76aae9b1c30a)).
He confirms the shape of the gains on both CPUs, and the reproduction is worth
more than the agreement:

**A straightforward Win64 integration costs the sizes that never use it.** Adding
the helper call inside the Pascal checker made the compiler save five nonvolatile
registers on *every* check and moved the allocator routines that follow it. The
result was a repeatable 3.58% regression at 64 B on Intel - a size the vector
path does not even touch. The threshold makes the small path execute the same
*instructions*, but it does not keep the surrounding code at the same
*addresses*, and at these timescales that is a measurable difference. This is
the same effect that made the in-binary comparison unusable (see below), showing
up in the shipped code instead of in the harness.

His fix keeps the layout: the scalar checker retains the upstream instruction
flow, tests the crossover once, and tail-jumps to an out-of-line SSE2 checker for
larger blocks, with corruption logging out of line as well. That leaves
`CheckFreedDebugBlockFillPatternIntact`, `CheckFreeDebugBlockIntact` and every
allocator routine after them at the addresses they have in the upstream binary,
and the 64 B regression disappears (AMD neutral at [-0.89%, +0.44%], Intel +1.08%
at [0.57%, 1.12%]). The cost is a larger assembly surface on Win64. Win32 is
unchanged from the measurement above.

If this branch is ever handed over, the Win64 side should adopt that
layout-preserving integration rather than the helper call used here.

## Verifying it

`FastMM5Test_FillPattern` corrupts **every** byte position of a freed medium
block across 12 sizes chosen to cover exact multiples of the unrolled width,
16/32/48 byte remainders and 1/2/3/7/15 byte scalar tails - 34,949 positions, all
of which must be detected. It is part of the suite, so `RunTests.ps1` builds and
runs it with everything else; the full run takes about a fifth of a second.
Build it against this branch and against unmodified master; both must pass.
janrysavy's reproduction used the same 12 sizes and the same 34,949 positions on
AMD and Intel, Win32 and Win64.

`FastMM5Bench_FillPattern` is the timing harness: one process measures one build,
which is why it is a `Bench` program and not part of the test suite - it reports
a time, not a pass or a fail. `MeasureFillPattern.ps1` pairs a baseline and a
candidate executable, alternating the order, and prints the median gain:

```
pwsh -File MeasureFillPattern.ps1 -Baseline <base>.exe -Candidate <cand>.exe
```

**Do not measure both variants inside one executable.** Below the threshold both
run identical code, and that built-in null control still swung by up to 30% from
code layout interaction alone. Separate executables with a fresh process per
sample bring the noise floor to about 3%.

Also: never build the work-equality checksum from block addresses. The heap base
is randomised per process, so addresses never match between two runs. Sum
`FastMM_BlockCurrentUserBytes` instead, which additionally proves debug mode was
active.
