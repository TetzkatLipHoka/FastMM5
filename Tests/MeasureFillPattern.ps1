<#
  MeasureFillPattern.ps1 - pairs a baseline and a candidate build of
  FastMM5Bench_FillPattern.

  Each sample runs in a fresh process, and the order within a pair alternates, so
  neither build is consistently favoured by clock, scheduler or thermal drift, and
  the two builds never share a process (which is what made an in-binary
  comparison unusable at these timescales).

  Reports the median of the per pair throughput gains, plus the 5th and 95th
  percentile of those gains as a spread indication.

  Build each executable from a working tree of its own - one at the baseline
  revision, one at the candidate revision - and point -Baseline and -Candidate at
  the results, or pass -Root to a directory laid out as
  <root>\base\<platform>\FastMM5Bench_FillPattern.exe and the same under \cand.

  Usage:
      pwsh -File MeasureFillPattern.ps1 -Baseline .\base.exe -Candidate .\cand.exe
      pwsh -File MeasureFillPattern.ps1 -Root D:\simd2 -Platform dcc32
#>

param(
  [string]$Baseline = '',
  [string]$Candidate = '',
  [string]$Root = '',
  [string]$Platform = 'dcc64',
  [int]$Pairs = 25
)

$ErrorActionPreference = 'Stop'

$base = $Baseline
$cand = $Candidate
if ((-not $base) -or (-not $cand)) {
  if (-not $Root) {
    Write-Host 'Give either -Baseline and -Candidate, or -Root.'
    exit 1
  }
  $base = Join-Path $Root "base\$Platform\FastMM5Bench_FillPattern.exe"
  $cand = Join-Path $Root "cand\$Platform\FastMM5Bench_FillPattern.exe"
}
foreach ($exe in @($base, $cand)) {
  if (-not (Test-Path $exe)) {
    Write-Host "Not found: $exe"
    exit 1
  }
}

# size, iterations - chosen so each run takes roughly 150-400 ms
$Cases = @(
  @{ size = 64;    iters = 3000000 }   # control: below the vector threshold
  @{ size = 128;   iters = 1500000 }   # control: just below the threshold
  @{ size = 136;   iters = 1500000 }   # first size that engages the vector loop
  @{ size = 256;   iters = 1000000 }
  @{ size = 1024;  iters = 400000 }
  @{ size = 4096;  iters = 1500000 }
  @{ size = 16384; iters = 400000 }
  @{ size = 65536; iters = 100000 }
)

function Invoke-Bench([string]$exe, [int]$size, [int]$iters) {
  $out = & $exe $size $iters
  $parts = $out.Trim() -split '\s+'
  # The benchmark prints with the system decimal separator; normalise it.
  $ms = [double]::Parse($parts[0].Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture)
  return @{ ms = $ms; checksum = $parts[1] }
}

function Percentile([double[]]$values, [double]$p) {
  $sorted = $values | Sort-Object
  $index = [Math]::Floor(($sorted.Count - 1) * $p)
  return $sorted[$index]
}

Write-Output ""
Write-Output "Platform: $Platform,  $Pairs pairs per size,  fresh process per sample"
Write-Output ""
Write-Output ("{0,10} {1,14} {2,14} {3,12} {4,18}" -f 'user size', 'baseline (ms)', 'candidate (ms)', 'gain (%)', 'gain p5..p95 (%)')

$anyMismatch = $false

foreach ($case in $Cases) {
  $gains = New-Object System.Collections.Generic.List[double]
  $baseTimes = New-Object System.Collections.Generic.List[double]
  $candTimes = New-Object System.Collections.Generic.List[double]
  $checksums = @{}

  # Two unrecorded warmups.
  for ($w = 0; $w -lt 2; $w++) {
    [void](Invoke-Bench $base $case.size $case.iters)
    [void](Invoke-Bench $cand $case.size $case.iters)
  }

  for ($i = 0; $i -lt $Pairs; $i++) {
    if ($i % 2 -eq 0) {
      $b = Invoke-Bench $base $case.size $case.iters
      $c = Invoke-Bench $cand $case.size $case.iters
    } else {
      $c = Invoke-Bench $cand $case.size $case.iters
      $b = Invoke-Bench $base $case.size $case.iters
    }
    $checksums[$b.checksum] = $true
    $checksums[$c.checksum] = $true
    $baseTimes.Add($b.ms)
    $candTimes.Add($c.ms)
    $gains.Add((($b.ms / $c.ms) - 1) * 100)
  }

  # Both builds must have produced the same pointer checksum, otherwise they did
  # not do the same work and the comparison is meaningless.
  if ($checksums.Keys.Count -ne 1) { $anyMismatch = $true }

  $g = $gains.ToArray()
  Write-Output ("{0,10} {1,14:F2} {2,14:F2} {3,12:F2} {4,18}" -f `
    $case.size,
    (Percentile $baseTimes.ToArray() 0.5),
    (Percentile $candTimes.ToArray() 0.5),
    (Percentile $g 0.5),
    ("{0:F2} .. {1:F2}" -f (Percentile $g 0.05), (Percentile $g 0.95)))
}

Write-Output ""
if ($anyMismatch) {
  Write-Output "WARNING: the two builds reported different checksums for at least one size."
} else {
  Write-Output "Checksums matched for every size (both builds did identical work)."
}
