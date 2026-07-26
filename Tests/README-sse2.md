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

## What an application gets

The numbers above are routine level: one size in a loop, stack traces switched
off, which isolates the check but is not what a program runs. Two things dilute
it in practice, and both are measurable.

**Stack traces.** The microbenchmark sets `StackTraceEntryCount` to 0; the debug
mode default is 20, and capturing a stack trace per allocation costs roughly what
the fill pattern check costs at medium sizes. Same measurement, Win64, at the
default depth:

| User size | depth 0 | depth 20 |
|---:|---:|---:|
| 64 B (control) | -1.12% [-1.68, -0.85] | +3.59% [+3.36, +4.74] |
| 256 B | - | +4.48% [+3.53, +5.34] |
| 1 KiB | - | +14.04% [+12.21, +16.91] |
| 4 KiB | +64.44% | +32.31% [+30.81, +33.86] |

Note the control size: without stack traces the layout effect is negative, with
them it is positive, and both intervals exclude zero. At 64 B the two builds
execute the same instructions, so that is layout alone - the same effect
janrysavy found, and evidence that its sign is not even stable across
configurations. Another reason to prefer the layout-preserving integration.

**Allocation size mix.** `FastMM5Bench_AppWorkload` runs a mixed workload of the
kind an application produces - strings, objects, growing lists, payload buffers -
and `-histogram` reports the size distribution of the blocks that get freed,
which is the population the check walks:

```
Blocks that can reach the vector path (>136 bytes):  18.26% of blocks, 90.64% of bytes
Total: 32072 freed blocks, 18436579 bytes
```

Four fifths of the blocks are too small to reach the vector path - but they carry
under a tenth of the bytes, and the check's cost scales with bytes, not with
blocks. That is why the end to end gain is neither zero nor anywhere near the
routine level figure:

| Platform | depth 0 | depth 20 (debug mode default) |
|---|---:|---:|
| Win64 | +4.20% [+3.55, +5.86] | +4.35% [+3.31, +5.26] |
| Win32 | +6.75% [+5.11, +8.48] | +8.46% [+6.82, +8.87] |

Roughly 4% of total run time on Win64 and 8% on Win32, for a program spending a
substantial share of its time allocating in debug mode. A program with a
different size mix will get a different number, which is exactly why the
histogram is part of the tool rather than a footnote.

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
candidate executable, alternating the order, and prints the median gain with a
bootstrap confidence interval:

```
pwsh -File MeasureFillPattern.ps1 -Baseline <base>.exe -Candidate <cand>.exe
pwsh -File MeasureFillPattern.ps1 -Root <dir> -StackTrace 20
```

`FastMM5Bench_AppWorkload` and `MeasureAppWorkload.ps1` do the same for the
application shaped workload, and `-histogram` reports the size distribution
behind the number:

```
FastMM5Bench_AppWorkload 8 20 -histogram
pwsh -File MeasureAppWorkload.ps1 -Root <dir>
```

**A median without an interval does not answer "is this real".** Our own table
read -1.0% at a control size as noise; a paired bootstrap over the same kind of
data shows the control effects excluding zero in both directions depending on
configuration. Both measuring scripts therefore report an interval, and the
control sizes exist so there is something to point it at.

**Do not measure both variants inside one executable.** Below the threshold both
run identical code, and that built-in null control still swung by up to 30% from
code layout interaction alone. Separate executables with a fresh process per
sample bring the noise floor to about 3%.

Also: never build the work-equality checksum from block addresses. The heap base
is randomised per process, so addresses never match between two runs. Sum
`FastMM_BlockCurrentUserBytes` instead, which additionally proves debug mode was
active.
