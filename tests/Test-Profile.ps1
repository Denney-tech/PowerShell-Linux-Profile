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
  # Matches must arrive while the producer is still running, exactly as with the bare
  # binary. (pwsh itself holds each record's newline back until the next record, so even
  # /usr/bin/grep sees a1 only once a2 is written; a grep that only starts after upstream
  # finishes would report every match at 4s instead.)
  $arrivals = foreach ($cmd in 'grep', '/usr/bin/grep') {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    (& { 'a1'; Start-Sleep -Seconds 2; 'a2'; Start-Sleep -Seconds 2; 'a3' } | & $cmd --line-buffered a |
      ForEach-Object { "$_@$([int]$sw.Elapsed.TotalSeconds)s" }) -join ' '
  }
  Assert-Equal 'grep streams piped input like the bare binary' $arrivals[1] $arrivals[0]
  Assert-Equal 'bare grep timing is as expected (test sanity)' 'a1@2s a2@4s a3@4s' $arrivals[1]
  Assert-Equal 'grep exit status covers the whole pipeline' '1' $(('x', 'y' | grep -q zzz); $LASTEXITCODE)
  Assert-Equal 'grep still works on files' "$dir/needle.txt" (ls -d "$dir/needle.txt" | grep needle)

  $sudoError = $null
  try { Invoke-Sudo -V | Out-Null } catch { $sudoError = $_ }
  Assert-Equal 'sudo with a leading flag passes it through' '' $sudoError
} finally {
  Remove-Item -Recurse -Force $dir
}

if ($failures) { throw "$failures test(s) failed" }
