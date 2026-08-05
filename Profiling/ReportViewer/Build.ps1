<#
  Build.ps1 - command-line build + self-tests for the FastMM report viewer.

  Compiles and runs both parser self-tests, then compiles the GUI demo, on each
  Delphi compiler found.  Old dcc32 (Delphi 7) can crash on very long working
  directory paths, so the sources are copied to a short temporary folder first.

  Usage:
      pwsh -File Build.ps1                # build with every compiler below that exists
      pwsh -File Build.ps1 -Only Delphi7  # build with a single compiler

  Adjust the $Compilers table below if your Delphi installations live elsewhere.
#>

param(
  [string]$Only = ''
)

$ErrorActionPreference = 'Stop'
$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$work   = Join-Path $env:USERPROFILE 'fmmlrv_build'

# name -> @{ bin; lib; modern }   (modern compilers need namespace search + Vcl DCUs)
$modernNS = '-NSSystem;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Xml;Datasnap;Web;Soap'
$Compilers = [ordered]@{
  'Delphi7' = @{ bin='C:\Delphi\7\bin';    lib='C:\Delphi\7\Lib';                  ns=$null }
  'Seattle' = @{ bin='C:\Delphi\10\bin';   lib='C:\Delphi\10\lib\win32\release';   ns=$modernNS }
  'D13.1'   = @{ bin='C:\Delphi\13.1\bin'; lib='C:\Delphi\13.1\lib\win32\release'; ns=$modernNS }
}

if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
Get-ChildItem $work -File -ErrorAction SilentlyContinue | Remove-Item -Force
foreach ($f in 'FastMM_LeakReportParser.pas','FastMM_SamplingLogParser.pas','FastMM_ReportViewerForm.pas',
               'LeakReportParserTest.dpr','SamplingLogParserTest.dpr','ReportViewerDemo.dpr') {
  Copy-Item (Join-Path $srcDir $f) $work -Force
}

function Invoke-Build($name, $cfg, $dpr, [switch]$Run) {
  $dcc = Join-Path $cfg.bin 'dcc32.exe'
  if (-not (Test-Path $dcc)) { Write-Host "[$name] dcc32 not found at $dcc - skipped"; return }
  Push-Location $work
  try {
    Get-ChildItem $work -Include *.dcu -File | Remove-Item -Force -ErrorAction SilentlyContinue
    $exe = Join-Path $work ([IO.Path]::ChangeExtension($dpr, '.exe'))
    if (Test-Path $exe) { Remove-Item $exe -Force }
    $libArgs = @("-U$($cfg.lib)")
    if ($cfg.ns) { $libArgs += $cfg.ns }
    $extra = @()
    if ($Run) { $extra += '-CC' }   # console app
    $out = & $dcc -B -Q @libArgs @extra "-N$work" "-E$work" $dpr 2>&1
    $problems = $out | Select-String -Pattern 'Error|Fatal|Fehler|Warning|Warnung|Hint|Hinweis'
    if (Test-Path $exe) {
      $status = if ($problems) { 'OK (with messages)' } else { 'OK (clean)' }
      Write-Host "[$name] $dpr -> $status"
      $problems | ForEach-Object { Write-Host "    $_" }
      if ($Run) { & $exe; Write-Host "[$name] test exit code = $LASTEXITCODE" }
    } else {
      Write-Host "[$name] $dpr -> BUILD FAILED"
      $out | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" }
    }
  } finally { Pop-Location }
}

foreach ($name in $Compilers.Keys) {
  if ($Only -and ($Only -ne $name)) { continue }
  Write-Host "===================== $name ====================="
  Invoke-Build $name $Compilers[$name] 'LeakReportParserTest.dpr' -Run
  Invoke-Build $name $Compilers[$name] 'SamplingLogParserTest.dpr' -Run
  Invoke-Build $name $Compilers[$name] 'ReportViewerDemo.dpr'
}

Write-Host ''
Write-Host "Build artifacts are in: $work"
