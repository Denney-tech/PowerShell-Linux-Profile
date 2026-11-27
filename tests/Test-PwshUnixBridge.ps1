#!/usr/bin/env pwsh
# Tests for the PwshUnixBridge module. Run with: pwsh -NoProfile -File tests/Test-PwshUnixBridge.ps1
# Optional parts run only when their prerequisites exist (and say so when skipped):
#   sudo        - passwordless sudo (`sudo -n true`), e.g. GitHub's Ubuntu runners
#   completion  - carapace on PATH
#   interactive - python3, to drive a real PSReadLine session through a pseudo-terminal
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'test runner output')]
param()
$ErrorActionPreference = 'Stop'
$script:failures = 0
function Assert-Equal($Name, $Expected, $Actual) {
  if ("$Expected" -ceq "$Actual") {
    Write-Host "ok   - $Name"
  } else {
    Write-Host "FAIL - $Name`n       expected: $Expected`n       actual:   $Actual"
    $script:failures++
  }
}
function Skip($Name, $Why) { Write-Warning "skip - ${Name}: $Why" }

$manifest = Join-Path $PSScriptRoot '..' 'PwshUnixBridge' 'PwshUnixBridge.psd1' -Resolve
$work = Join-Path ([IO.Path]::GetTempPath()) "pwshunixbridge-test-$PID"
New-Item -ItemType Directory -Path $work | Out-Null
$env:XDG_CACHE_HOME = Join-Path $work 'cache'
$hasCarapace = [bool](Get-Command carapace -CommandType Application -ErrorAction SilentlyContinue)

try {
  Import-Module $manifest -Force
  Assert-Equal 'exports' 'Expand-UnixAlias Get-UnixAlias Invoke-Sudo Remove-UnixAlias Set-UnixAlias sudo' `
    (((Get-Module PwshUnixBridge).ExportedCommands.Keys | Sort-Object) -join ' ')

  # --- aliases --------------------------------------------------------------------------------
  Set-UnixAlias -Name ll -Value 'ls -l'
  $cases = [ordered]@{
    'ls'                             = 'ls --color=auto'
    'ls -d /etc'                     = 'ls --color=auto -d /etc'
    'Get-Content x | grep -c ERROR'  = 'Get-Content x | grep --color=auto -c ERROR'
    'll /etc'                        = 'ls --color=auto -l /etc'
    'sudo ls /root'                  = 'sudo ls --color=auto /root'
    'sudo -i'                        = 'sudo -i'
    '& ls'                           = '& ls'
    '. ls'                           = '. ls'
    '"ls"'                           = '"ls"'
    './ls'                           = './ls'
    'Get-Item ls'                    = 'Get-Item ls'
    'echo ls; ls'                    = 'echo ls; ls --color=auto'
    'if ($true) { grep x y }'        = 'if ($true) { grep --color=auto x y }'
    "ls ``n  -a"                     = "ls --color=auto ``n  -a"
    'lsblk'                          = 'lsblk'
    ''                               = ''
  }
  foreach ($line in $cases.Keys) {
    Assert-Equal "expand [$line]" $cases[$line] (Expand-UnixAlias -Line $line)
  }

  Set-UnixAlias -Name loopa -Value 'loopb x'
  Set-UnixAlias -Name loopb -Value 'loopa y'
  Assert-Equal 'mutually recursive aliases terminate' 'loopa y x z' (Expand-UnixAlias 'loopa z')
  Assert-Equal 'Get-UnixAlias' 'll=ls -l' ((Get-UnixAlias -Name ll | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ',')
  Remove-UnixAlias -Name ll, loopa, loopb
  Assert-Equal 'Remove-UnixAlias' 'll /etc' (Expand-UnixAlias 'll /etc')
  $err = $null
  try { Set-UnixAlias -Name 'a b' -Value x } catch { $err = $_ }
  Assert-Equal 'alias names cannot contain spaces' 'True' ($null -ne $err)

  $err = $null
  try { Import-Module $manifest -Force -ArgumentList @{ Bogus = $true } } catch { $err = $_ }
  Assert-Equal 'unknown import option is rejected' 'True' ("$err" -like "*unknown option 'Bogus'*")
  Import-Module $manifest -Force -ArgumentList @{ Sudo = $false }
  Assert-Equal 'Sudo = $false leaves no sudo alias' 'False' ([bool](Get-Alias sudo -ErrorAction SilentlyContinue))
  Import-Module $manifest -Force

  # --- environment ----------------------------------------------------------------------------
  $self = [Environment]::ProcessPath
  $selfReal = (Get-Item $self).ResolveLinkTarget($true)?.FullName ?? $self
  $registered = Get-Content /etc/shells -ErrorAction SilentlyContinue | Where-Object {
    $_ -match '/pwsh' -and (Test-Path $_) -and (((Get-Item $_).ResolveLinkTarget($true)?.FullName ?? $_) -eq $selfReal)
  } | Select-Object -First 1
  Assert-Equal 'SHELL is the /etc/shells path of this pwsh (or its own path)' ($registered ?? $self) $env:SHELL

  function Enter-TestDirectory { Set-Location -Path $work }
  Push-Location /
  Enter-TestDirectory
  Assert-Equal 'PWD follows Set-Location inside a function' $work (/usr/bin/env | Where-Object { $_ -like 'PWD=*' }).Substring(4)
  Pop-Location
  Assert-Equal 'PWD follows Pop-Location' $PWD.ProviderPath $env:PWD

  Remove-Module PwshUnixBridge
  Assert-Equal 'removing the module restores LocationChangedAction' '' "$($ExecutionContext.InvokeCommand.LocationChangedAction)"
  Import-Module $manifest -Force

  # --- sudo -----------------------------------------------------------------------------------
  $sudoBinary = Get-Command sudo -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  $canSudo = $false
  if ($sudoBinary) {
    $null = & $sudoBinary.Source -n true 2>&1
    $canSudo = $LASTEXITCODE -eq 0
  }
  if ($canSudo) {
    Assert-Equal 'sudo native command' 'root' (sudo whoami)
    Assert-Equal 'sudo native args keep quoting' 'a b|c|' (sudo printf '%s|' 'a b' c)
    Set-Alias -Name whoamialias -Value whoami
    Assert-Equal 'sudo resolves a PowerShell alias for a native program' 'root' (sudo whoamialias)
    Remove-Item Alias:whoamialias
    Assert-Equal 'sudo PowerShell expression runs as root' 'root' (sudo [Environment]::UserName)
    Assert-Equal 'sudo cmdlet keeps quoting' "[a  b] [c'd]" ((sudo Write-Output 'a  b' "c'd" | ForEach-Object { "[$_]" }) -join ' ')
    Assert-Equal 'sudo output pipes back' 'root' (sudo Get-Content -Path /etc/shadow -TotalCount 1 | ForEach-Object { ($_ -split ':')[0] })
    Assert-Equal 'sudo script block, module loaded as root' 'root True' (sudo { "$([Environment]::UserName) $([bool](Get-Module PwshUnixBridge))" })
    sudo false; Assert-Equal 'sudo passes the exit code through' '1' $LASTEXITCODE
    $errorText = (sudo Get-Item /nonexistent-pwshunixbridge 2>&1 | Out-String)
    Assert-Equal 'root pwsh errors come back as text, not CLIXML' 'True' ($errorText -match 'Cannot find path' -and $errorText -notmatch 'CLIXML')
  } else {
    Skip 'sudo' 'sudo missing or not passwordless'
  }

  # --- completion -----------------------------------------------------------------------------
  if ($hasCarapace) {
    $line = 'git sta'
    $r = TabExpansion2 -inputScript $line -cursorColumn $line.Length
    Assert-Equal 'carapace completes native subcommands' 'True' (($r.CompletionMatches.CompletionText | ForEach-Object Trim) -contains 'status')
    $cacheFile = Get-ChildItem (Join-Path $env:XDG_CACHE_HOME 'PwshUnixBridge') -Filter 'carapace-*.ps1'
    Assert-Equal 'carapace setup is cached' '1' @($cacheFile).Count
    $before = $cacheFile.LastWriteTimeUtc
    Import-Module $manifest -Force
    Assert-Equal 'cached carapace setup is reused' $before (Get-Item $cacheFile.FullName).LastWriteTimeUtc
  } else {
    Skip 'completion' 'carapace not on PATH'
  }

  # --- interactive (PSReadLine Enter handler) -------------------------------------------------
  $python = Get-Command python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($python) {
    $profilePath = Join-Path $work 'profile.ps1'
    $historyFile = Join-Path $work 'history.txt'
    $memoryFile = Join-Path $work 'memory.txt'
    $keysFile = Join-Path $work 'keys.txt'
    @"
Set-PSReadLineOption -HistorySavePath '$historyFile'
Import-Module '$manifest' -ArgumentList @{ Completion = `$false }
Set-UnixAlias ll 'ls -d'
function prompt { 'PS> ' }
"@ | Set-Content -Path $profilePath
    $out = & $python.Source (Join-Path $PSScriptRoot 'pty_session.py') $self $profilePath `
      "'root' | grep root" `
      'll /etc' `
      'echo password | grep pass' `
      "[Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems() | ForEach-Object CommandLine | Set-Content '$memoryFile'" `
      "Get-PSReadLineKeyHandler -Bound | ForEach-Object { `$_.Key + '=' + `$_.Function } | Set-Content '$keysFile'" |
      Out-String
    $esc = [char]27
    Assert-Equal 'Enter expands aliases; grep keeps its color at the terminal' 'True' $out.Contains("$esc[01;31m$esc[Kroot")
    Assert-Equal 'expanded alias runs (ll -> ls --color=auto -d)' 'True' $out.Contains("$esc[01;34m/etc")
    $memory = Get-Content $memoryFile -ErrorAction SilentlyContinue
    $saved = Get-Content $historyFile -ErrorAction SilentlyContinue
    Assert-Equal 'history keeps what was typed, not the expansion' "'root' | grep root|ll /etc" ((@($memory) | Select-Object -First 2) -join '|')
    Assert-Equal 'lines PSReadLine marks sensitive stay out of the history file' 'True|False' `
      ("$($memory -contains 'echo password | grep pass')|$($saved -contains 'echo password | grep pass')")
    # Same functions PSReadLine's Windows edit mode binds (Ctrl+Space arrives as Ctrl+@).
    $bound = Get-Content $keysFile -ErrorAction SilentlyContinue
    Assert-Equal 'Windows-style key bindings' 'Ctrl+LeftArrow=BackwardWord Ctrl+RightArrow=NextWord Ctrl+@=MenuComplete Tab=TabCompleteNext Shift+Tab=TabCompletePrevious' `
      ((@('Ctrl+LeftArrow', 'Ctrl+RightArrow', 'Ctrl+@', 'Tab', 'Shift+Tab') | ForEach-Object { $k = $_; @($bound) -like "$k=*" | Select-Object -First 1 }) -join ' ')
    if ($script:failures) {
      Write-Host '--- interactive session transcript (escape sequences stripped):'
      Write-Host ($out -replace "$esc\[[0-9;?]*[a-zA-Z]|$esc\][^\a]*\a|$esc[=>]", '' -replace "`r", '')
    }
  } else {
    Skip 'interactive' 'python3 not installed'
  }
} finally {
  Set-Location $HOME
  Remove-Module PwshUnixBridge -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $work
}

if ($script:failures) { throw "$script:failures test(s) failed" }
