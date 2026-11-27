# PwshUnixBridge: Windows PowerShell habits, Unix behavior.
#
#   Import-Module PwshUnixBridge
#   Import-Module PwshUnixBridge -ArgumentList @{ KeyBindings = $false }   # opt out of a feature
#
# Features (all on by default):
#   Aliases     - bash-style aliases (Set-UnixAlias), expanded on the command line when you
#                 press Enter, so the real program runs with the terminal attached
#   Sudo        - `sudo` runs PowerShell commands as root, with exact quoting (Invoke-Sudo)
#   Completion  - bash-like completion for native commands through carapace, if installed
#   Environment - keeps $env:PWD in sync with the current location, sets $env:SHELL to pwsh
#   KeyBindings - Windows-style PSReadLine keys (Tab cycles, Ctrl+Space menu, Ctrl+arrows)
param(
  [hashtable] $Options = @{}
)

# .NET file APIs instead of Get-ChildItem/Get-Content throughout: each built-in module's first
# use costs ~200 ms of autoloading at shell start.
foreach ($file in [IO.Directory]::GetFiles("$PSScriptRoot/Private", '*.ps1') + [IO.Directory]::GetFiles("$PSScriptRoot/Public", '*.ps1')) {
  . $file
}

$script:Settings = @{
  Aliases     = $true
  Sudo        = $true
  Completion  = $true
  Environment = $true
  KeyBindings = $true
}
foreach ($key in $Options.Keys) {
  if (-not $script:Settings.ContainsKey($key)) {
    throw "PwshUnixBridge: unknown option '$key' (valid: $($script:Settings.Keys -join ', '))"
  }
  $script:Settings[$key] = [bool]$Options[$key]
}

# PSReadLine is only loaded in interactive console sessions; key handlers make no sense elsewhere.
$script:Interactive = [bool](Get-Module -Name PSReadLine)

if ($script:Settings.Aliases) {
  Initialize-UnixAlias
}
if ($script:Settings.Environment) {
  Initialize-UnixEnvironment
}
if ($script:Settings.Completion) {
  $completionScript = Get-UnixCompletionScript
  if ($completionScript) { . $completionScript }
}
if ($script:Interactive -and $script:Settings.KeyBindings) {
  Initialize-WindowsKeyBinding
}
if ($script:Interactive -and $script:Settings.Aliases) {
  Initialize-AliasExpansionOnEnter
}

$ExecutionContext.SessionState.Module.OnRemove = {
  Restore-UnixEnvironment
  Restore-AliasExpansionOnEnter
}

$exportedAliases = @()
if ($script:Settings.Sudo) {
  Set-Alias -Name sudo -Value Invoke-Sudo -Description 'Runs PowerShell or native commands as root (PwshUnixBridge)'
  $exportedAliases += 'sudo'
}
Export-ModuleMember -Alias $exportedAliases -Function @(
  'Expand-UnixAlias'
  'Get-UnixAlias'
  'Invoke-Sudo'
  'Remove-UnixAlias'
  'Set-UnixAlias'
)
