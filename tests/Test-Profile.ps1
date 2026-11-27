#!/usr/bin/env pwsh
# Smoke tests for .config/powershell/profile.ps1. Run with: pwsh -NoProfile -File tests/Test-Profile.ps1
# Needs nano on PATH; the nano-completion test also needs Microsoft.PowerShell.UnixTabCompletion
# (it is skipped, with a warning, when that module isn't installed).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'test runner output')]
param()
$ErrorActionPreference = 'Stop'
$failures = 0
function Assert-Equal($Name, $Expected, $Actual) {
  if ("$Expected" -ceq "$Actual") {
    Write-Host "ok   - $Name"
  } else {
    Write-Host "FAIL - $Name`n       expected: $Expected`n       actual:   $Actual"
    $script:failures++
  }
}

. "$PSScriptRoot/../.config/powershell/profile.ps1"

$dir = Join-Path ([IO.Path]::GetTempPath()) "profile-test-$PID"
New-Item -ItemType Directory -Path $dir | Out-Null
try {
  New-Item -ItemType File -Path "$dir/needle.txt" | Out-Null

  # nano must be the real binary (so all its flags work), not an alias to a wrapper function.
  Assert-Equal 'nano runs the real nano' 'Application' (Get-Command nano).CommandType

  if (Get-Module -Name Microsoft.PowerShell.UnixTabCompletion) {
    # Before the fix, completing nano's arguments launched nano itself and returned its
    # screen output as the "completion".
    $line = "nano $dir/nee"
    $r = TabExpansion2 -inputScript $line -cursorColumn $line.Length
    Assert-Equal 'nano completes paths without running nano' "$dir/needle.txt" ($r.CompletionMatches.CompletionText -join ' ')
  } else {
    Write-Warning 'Microsoft.PowerShell.UnixTabCompletion not installed; skipping the nano completion test'
  }

  Assert-Equal 'grep -c counts across the whole pipeline' '2' ('a1', 'b', 'a2' | grep -c a)
  Assert-Equal 'grep -A keeps context across piped lines' 'a1 b' (('a1', 'b', 'c' | grep -A1 a1) -join ' ')
  # The first match must arrive while the producer is still running (it runs for 4s; a
  # grep that only starts after upstream finishes reports nothing before then). pwsh
  # buffers what it writes to a native program's stdin, so the margin is wide on purpose.
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $firstAt = $null
  & { foreach ($i in 1..5) { "a$i"; Start-Sleep -Milliseconds 800 } } | grep a |
    ForEach-Object { if ($null -eq $firstAt) { $firstAt = $sw.Elapsed.TotalSeconds } }
  Assert-Equal 'grep streams piped input as it arrives' 'True' ($firstAt -lt 2.5)

  # An upstream error must not leave the grep process behind.
  try { & { 'zq1'; throw 'upstream failed' } | grep zq | Out-Null } catch { $null = $_ }
  Start-Sleep -Milliseconds 500
  $leftover = @(Get-Process grep -ErrorAction SilentlyContinue | Where-Object { $_.Parent.Id -eq $PID })
  Assert-Equal 'grep is cleaned up when upstream throws' '0' $leftover.Count
  Assert-Equal 'grep exit status covers the whole pipeline' '1' $(('x', 'y' | grep -q zzz); $LASTEXITCODE)
  Assert-Equal 'grep still works on files' "$dir/needle.txt" (ls -d "$dir/needle.txt" | grep needle)

  $sudoError = $null
  try { Invoke-Sudo -V | Out-Null } catch { $sudoError = $_ }
  Assert-Equal 'sudo with a leading flag passes it through' '' $sudoError
} finally {
  Remove-Item -Recurse -Force $dir
}

if ($failures) { throw "$failures test(s) failed" }
