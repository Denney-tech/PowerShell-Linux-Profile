# Environment bridging for pwsh as a login shell.

$script:PreviousLocationChangedAction = $null
$script:LocationActionInstalled = $false

function Resolve-RealPath([string] $Path) {
  $item = [IO.FileInfo]::new($Path)
  if (-not $item.Exists) { return $null }
  $target = $item.ResolveLinkTarget($true)
  if ($target) { $target.FullName } else { $item.FullName }
}

function Get-PwshShellPath {
  # Prefer the path registered in /etc/shells (what login, chsh and tools comparing $SHELL
  # expect, e.g. /usr/bin/pwsh), as long as it is this same pwsh; else this pwsh's own path.
  $self = [Environment]::ProcessPath
  $selfReal = Resolve-RealPath $self
  $registered = if ([IO.File]::Exists('/etc/shells')) {
    [IO.File]::ReadAllLines('/etc/shells') -match '^/\S*/pwsh[^/\s]*$'
  }
  foreach ($candidate in $registered) {
    if ((Resolve-RealPath $candidate) -eq $selfReal) { return $candidate }
  }
  $self
}

function Initialize-UnixEnvironment {
  $env:SHELL = Get-PwshShellPath

  # Set-Location doesn't update the process's PWD, so child processes (and scripts reading
  # $env:PWD) see a stale directory. LocationChangedAction fires on every location change,
  # including inside scripts and functions, unlike a prompt or Enter-key hook.
  $script:PreviousLocationChangedAction = $ExecutionContext.InvokeCommand.LocationChangedAction
  $ExecutionContext.InvokeCommand.LocationChangedAction = {
    param($source, $locationArgs)
    if ($locationArgs.NewPath.Provider.Name -eq 'FileSystem') {
      $env:PWD = $locationArgs.NewPath.ProviderPath
    }
    if ($script:PreviousLocationChangedAction) {
      & $script:PreviousLocationChangedAction $source $locationArgs
    }
  }
  $script:LocationActionInstalled = $true
  if ($PWD.Provider.Name -eq 'FileSystem') { $env:PWD = $PWD.ProviderPath }
}

function Restore-UnixEnvironment {
  if ($script:LocationActionInstalled) {
    $ExecutionContext.InvokeCommand.LocationChangedAction = $script:PreviousLocationChangedAction
    $script:LocationActionInstalled = $false
  }
}
