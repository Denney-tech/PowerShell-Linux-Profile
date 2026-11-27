function Get-SudoCommandText {
  # The text after `sudo`, exactly as typed. $MyInvocation.Statement is the invoking command's
  # own source text (just this command, even inside a pipeline or assignment), so quoting and
  # escaping reach the root pwsh unchanged instead of being re-joined from parsed $args.
  param(
    [System.Management.Automation.InvocationInfo] $Invocation,
    [object[]] $Arguments
  )
  $statement = $Invocation.Statement
  if ($statement) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($statement, [ref]$tokens, [ref]$parseErrors)
    $command = $ast.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
    if ($command -and $command.CommandElements.Count -gt 1) {
      return $statement.Substring($command.CommandElements[1].Extent.StartOffset).Trim()
    }
  }
  # Fallback (no source text, e.g. invoked through the API): quoting may be lost.
  "$Arguments"
}

function Invoke-Sudo {
  <#
  .SYNOPSIS
  Runs a command as root with sudo; PowerShell commands run in a root pwsh.
  .DESCRIPTION
  - Native programs (sudo dnf upgrade, sudo systemctl restart sshd) go straight to sudo.
  - PowerShell commands (cmdlets, functions, aliases, scripts) run in `pwsh -NoProfile` as
    root, with the command text forwarded exactly as typed and PwshUnixBridge loaded.
  - A script block runs as-is: sudo { Get-ChildItem /root | Measure-Object }
  - A leading sudo option (sudo -i, sudo -u bob id) passes everything to sudo unchanged.
  Output from a root pwsh comes back as text, not live objects.
  .EXAMPLE
  sudo chown -R 'root:domain users@domain.com' /usr/local/
  .EXAMPLE
  sudo Remove-Item -Path /usr/local/share/powershell/Modules/* -Recurse -Force
  #>
  $sudo = Get-Command -Name sudo -CommandType Application -ErrorAction Stop | Select-Object -First 1

  if ($args.Count -eq 0 -or "$($args[0])".StartsWith('-')) {
    & $sudo.Source @args
    return
  }

  if ($args.Count -eq 1 -and $args[0] -is [scriptblock]) {
    $commandText = $args[0].ToString()
  } else {
    $target = Get-Command -Name "$($args[0])" -ErrorAction SilentlyContinue | Select-Object -First 1
    $viaAlias = $target -and $target.CommandType -eq 'Alias'
    if ($viaAlias) { $target = $target.ResolvedCommand }
    if ($target -and $target.CommandType -eq 'Application') {
      # PowerShell's native argument passing already preserves quoting for executables. A
      # PowerShell alias (Set-Alias k kubectl) means nothing to sudo, so pass its target.
      $native = @($args)
      if ($viaAlias) { $native[0] = $target.Source }
      & $sudo.Source @native
      return
    }
    $commandText = Get-SudoCommandText -Invocation $MyInvocation -Arguments $args
  }

  $manifest = Join-Path $PSScriptRoot '..' 'PwshUnixBridge.psd1' -Resolve
  $bootstrap = "Import-Module -Name '{0}' -ArgumentList @{{ Completion = `$false; KeyBindings = `$false }}`n" -f ($manifest -replace "'", "''")
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap + $commandText))
  & $sudo.Source -- ([Environment]::ProcessPath) -NoProfile -NoLogo -NonInteractive -OutputFormat Text -EncodedCommand $encoded
}
