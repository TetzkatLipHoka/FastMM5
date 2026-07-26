<#
  MeasureAppWorkload.ps1 - pairs a baseline and a candidate build of
  FastMM5Bench_AppWorkload.

  Same methodology as MeasureFillPattern.ps1 - separate executables, fresh
  process per sample, alternating order, bootstrap confidence interval - but the
  question is different.  MeasureFillPattern says how much faster the routine
  itself became; this says what a program gets out of that, which is always less:
  the check is one part of an allocation, an allocation is one part of the work,
  and most of an application's allocations are too small to reach the vector path
  at all.

  Run FastMM5Bench_AppWorkload with -histogram first.  It reports the size
  distribution of the freed blocks, and that distribution is what makes the
  number below transferable to another program - or not.

  Build each executable from a working tree of its own - one at the baseline
  revision, one at the candidate revision - and point -Baseline and -Candidate at
  the results, or pass -Root to a directory laid out as
  <root>\base\<platform>\FastMM5Bench_AppWorkload.exe and the same under \cand.

  Usage:
      pwsh -File MeasureAppWorkload.ps1 -Root D:\simd2
      pwsh -File MeasureAppWorkload.ps1 -Root D:\simd2 -Platform dcc32 -Rounds 600
#>

param(
  [string]$Baseline = '',
  [string]$Candidate = '',
  [string]$Root = '',
  [string]$Platform = 'dcc64',
  [int]$Pairs = 25,
  [int]$Rounds = 300,
  [int]$Resamples = 10000,
  # 0 isolates the allocator;  20 is the debug mode default, which is what an
  # application actually runs with.  Both are reported by default.
  [int[]]$StackDepths = @(0, 20)
)

$ErrorActionPreference = 'Stop'

$base = $Baseline
$cand = $Candidate
if ((-not $base) -or (-not $cand)) {
  if (-not $Root) {
    Write-Host 'Give either -Baseline and -Candidate, or -Root.'
    exit 1
  }
  $base = Join-Path $Root "base\$Platform\FastMM5Bench_AppWorkload.exe"
  $cand = Join-Path $Root "cand\$Platform\FastMM5Bench_AppWorkload.exe"
}
foreach ($exe in @($base, $cand)) {
  if (-not (Test-Path $exe)) {
    Write-Host "Not found: $exe"
    exit 1
  }
}

function Invoke-Run([string]$exe, [int]$rounds, [int]$stack) {
  $out = & $exe $rounds $stack
  $parts = $out.Trim() -split '\s+'
  $ms = [double]::Parse($parts[0].Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture)
  return @{ ms = $ms; checksum = $parts[1] }
}

function Percentile([double[]]$values, [double]$p) {
  $sorted = $values | Sort-Object
  $index = [Math]::Floor(($sorted.Count - 1) * $p)
  return $sorted[$index]
}

function BootstrapCI([double[]]$gains, [int]$resamples) {
  $rng = [Random]::new(12345)          # fixed seed, so the interval reproduces
  $n = $gains.Count
  $medians = New-Object double[] $resamples
  $sample = New-Object double[] $n
  for ($r = 0; $r -lt $resamples; $r++) {
    for ($i = 0; $i -lt $n; $i++) { $sample[$i] = $gains[$rng.Next($n)] }
    $medians[$r] = Percentile $sample 0.5
  }
  $sorted = @($medians | Sort-Object)
  return @{
    lo = $sorted[[int][Math]::Floor(($resamples - 1) * 0.025)]
    hi = $sorted[[int][Math]::Floor(($resamples - 1) * 0.975)]
  }
}

Write-Output ""
Write-Output "Platform: $Platform,  $Rounds rounds per run,  $Pairs pairs,  fresh process per sample"
Write-Output ""
Write-Output ("{0,18} {1,14} {2,14} {3,26}" -f 'stack trace depth', 'baseline (ms)', 'candidate (ms)', 'gain % [95% CI]')

$anyMismatch = $false

foreach ($stack in $StackDepths) {
  $gains = New-Object System.Collections.Generic.List[double]
  $baseTimes = New-Object System.Collections.Generic.List[double]
  $candTimes = New-Object System.Collections.Generic.List[double]
  $checksums = @{}

  for ($w = 0; $w -lt 3; $w++) {
    [void](Invoke-Run $base $Rounds $stack)
    [void](Invoke-Run $cand $Rounds $stack)
  }

  for ($i = 0; $i -lt $Pairs; $i++) {
    if ($i % 2 -eq 0) {
      $b = Invoke-Run $base $Rounds $stack
      $c = Invoke-Run $cand $Rounds $stack
    } else {
      $c = Invoke-Run $cand $Rounds $stack
      $b = Invoke-Run $base $Rounds $stack
    }
    $checksums[$b.checksum] = $true
    $checksums[$c.checksum] = $true
    $baseTimes.Add($b.ms)
    $candTimes.Add($c.ms)
    $gains.Add((($b.ms / $c.ms) - 1) * 100)
  }

  # The workload checksum is derived from the data, not from addresses, so it has
  # to match:  if it does not, the two builds did different work.
  if ($checksums.Keys.Count -ne 1) { $anyMismatch = $true }

  $g = $gains.ToArray()
  $ci = BootstrapCI $g $Resamples
  Write-Output ("{0,18} {1,14:F2} {2,14:F2} {3,26}" -f `
    $stack,
    (Percentile $baseTimes.ToArray() 0.5),
    (Percentile $candTimes.ToArray() 0.5),
    ("{0:F2}  [{1:F2}, {2:F2}]" -f (Percentile $g 0.5), $ci.lo, $ci.hi))
}

Write-Output ""
if ($anyMismatch) {
  Write-Output "WARNING: the two builds reported different checksums - they did not do the same work."
} else {
  Write-Output "Checksums matched (both builds did identical work)."
}
