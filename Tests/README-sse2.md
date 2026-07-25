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

## Verifying it

`Tests/exhaustive.dpr` corrupts **every** byte position of a freed medium block
across 12 sizes chosen to cover exact multiples of 64, 16/32/48 byte vector
remainders and 1/2/3/7/15 byte scalar tails - 34,949 positions, all of which must
be detected. Build it against this branch and against unmodified master; both
must pass.

`Tests/fillbench.dpr` is the timing harness: one process measures one build.
`Tests/Measure.ps1` pairs a baseline and a candidate executable, alternating the
order, and prints the median gain.

**Do not measure both variants inside one executable.** Below the threshold both
run identical code, and that built-in null control still swung by up to 30% from
code layout interaction alone. Separate executables with a fresh process per
sample bring the noise floor to about 3%.

Also: never build the work-equality checksum from block addresses. The heap base
is randomised per process, so addresses never match between two runs. Sum
`FastMM_BlockCurrentUserBytes` instead, which additionally proves debug mode was
active.
