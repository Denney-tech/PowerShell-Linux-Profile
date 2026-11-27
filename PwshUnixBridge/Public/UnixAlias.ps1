# bash-style aliases: textual replacement of the command word, expanded on the interactive
# command line before it runs (like bash, scripts are not affected). Because the line itself is
# rewritten, the real program runs directly with the terminal attached, so --color=auto,
# streaming, exit codes and pipeline input behave exactly as without the alias.

$script:UnixAliases = [ordered]@{}

$script:DefaultUnixAliases = [ordered]@{
  ls   = 'ls --color=auto'
  grep = 'grep --color=auto'
  diff = 'diff --color=auto'
  ip   = 'ip -color=auto'
  # A value ending in a space makes the next word eligible too, so `sudo ls` expands ls.
  sudo = 'sudo '
}

function Initialize-UnixAlias {
  foreach ($name in $script:DefaultUnixAliases.Keys) {
    $script:UnixAliases[$name] = $script:DefaultUnixAliases[$name]
  }
}

function Set-UnixAlias {
  <#
  .SYNOPSIS
  Defines a bash-style alias, expanded on the command line when you press Enter.
  .EXAMPLE
  Set-UnixAlias ll 'ls -l'
  `ll /etc` runs as `ls --color=auto -l /etc` (aliases expand recursively, as in bash).
  .EXAMPLE
  Set-UnixAlias sudo 'sudo '
  A trailing space makes the following word an alias candidate too.
  #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^\s|;&(){}<>''"`$]+$')]
    [string] $Name,

    [Parameter(Mandatory, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string] $Value
  )
  if ($PSCmdlet.ShouldProcess($Name, "Set Unix alias to '$Value'")) {
    $script:UnixAliases[$Name] = $Value
  }
}

function Get-UnixAlias {
  <#
  .SYNOPSIS
  Lists bash-style aliases defined with Set-UnixAlias (wildcards allowed).
  #>
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Position = 0)]
    [SupportsWildcards()]
    [string] $Name = '*'
  )
  foreach ($key in $script:UnixAliases.Keys) {
    if ($key -like $Name) {
      [pscustomobject]@{ Name = $key; Value = $script:UnixAliases[$key] }
    }
  }
}

function Remove-UnixAlias {
  <#
  .SYNOPSIS
  Removes a bash-style alias.
  #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
    [string[]] $Name
  )
  process {
    foreach ($n in $Name) {
      if (-not $script:UnixAliases.Contains($n)) {
        Write-Error "No Unix alias named '$n'."
      } elseif ($PSCmdlet.ShouldProcess($n, 'Remove Unix alias')) {
        $script:UnixAliases.Remove($n)
      }
    }
  }
}

function Resolve-UnixAliasWord([string] $Word) {
  # bash semantics: expand repeatedly, but never re-expand a name already being expanded
  # (so `ls` -> `ls --color=auto` stops). Returns $null when $Word is not an alias.
  if (-not $script:UnixAliases.Contains($Word)) { return $null }
  $seen = @{}
  $head = $Word
  $rest = ''
  $trailingSpace = $false
  while ($script:UnixAliases.Contains($head) -and -not $seen.ContainsKey($head)) {
    $seen[$head] = $true
    $value = $script:UnixAliases[$head]
    $trailingSpace = $value.EndsWith(' ')
    $parts = $value.Trim() -split '\s+', 2
    $head = $parts[0]
    $rest = (@($parts[1], $rest) | Where-Object { $_ }) -join ' '
  }
  [pscustomobject]@{
    Text          = (@($head, $rest) | Where-Object { $_ }) -join ' '
    TrailingSpace = $trailingSpace
  }
}

function Expand-UnixAlias {
  <#
  .SYNOPSIS
  Returns a command line with bash-style aliases expanded (what Enter runs).
  .EXAMPLE
  Expand-UnixAlias 'Get-Content log | grep -c ERROR'
  Get-Content log | grep --color=auto -c ERROR
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
    [AllowEmptyString()]
    [string] $Line
  )
  process {
    if (-not $Line.Trim() -or $script:UnixAliases.Count -eq 0) { return $Line }
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$parseErrors)

    $edits = [System.Collections.Generic.List[object]]::new()
    $commands = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($command in $commands) {
      # `& ls` / `. ls` explicitly ask for the command itself, as does a quoted or path name.
      if ($command.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown) { continue }
      $elements = $command.CommandElements
      for ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        $isBareWord = $element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
          $element.StringConstantType -eq [System.Management.Automation.Language.StringConstantType]::BareWord
        if (-not $isBareWord) { break }
        $resolved = Resolve-UnixAliasWord $element.Value
        if (-not $resolved) { break }
        if ($resolved.Text -ne $element.Value) {
          $edits.Add([pscustomobject]@{ Start = $element.Extent.StartOffset; Length = $element.Extent.EndOffset - $element.Extent.StartOffset; Text = $resolved.Text })
        }
        if (-not $resolved.TrailingSpace) { break }
      }
    }

    $result = [System.Text.StringBuilder]::new($Line)
    foreach ($edit in ($edits | Sort-Object -Property Start -Descending)) {
      [void]$result.Remove($edit.Start, $edit.Length).Insert($edit.Start, $edit.Text)
    }
    $result.ToString()
  }
}

# --- Enter-key integration -------------------------------------------------------------------

$script:PreviousAddToHistoryHandler = $null
$script:PendingHistory = @{}
$script:HistoryOverride = $null

function Initialize-AliasExpansionOnEnter {
  $script:PreviousAddToHistoryHandler = (Get-PSReadLineOption).AddToHistoryHandler

  Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'ExpandUnixAliasAndAcceptLine' -Description 'Expand PwshUnixBridge aliases, then run the line' -ScriptBlock {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $expanded = Expand-UnixAlias -Line $line
    if ($expanded -ne $line) {
      $script:PendingHistory[$expanded] = $line
      [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $expanded)
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
  }

  # History keeps what you typed, not the expansion, so recalling a line expands it afresh.
  Set-PSReadLineOption -AddToHistoryHandler {
    param([string] $line)
    $original = $script:PendingHistory[$line]
    if ($null -eq $original) { return Invoke-PreviousAddToHistoryHandler $line }
    $script:PendingHistory.Remove($line)
    # Let the previous handler (PSReadLine's default skips lines that look like they hold
    # secrets) decide about what was typed; then store that instead of the expansion.
    $decision = Invoke-PreviousAddToHistoryHandler $original
    if ($decision -is [bool]) {
      $decision = if ($decision) { [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile } else { [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding }
    }
    if ($decision -ne [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding) {
      $script:HistoryOverride = @{ Line = $original; Decision = $decision }
      [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($original)
      $script:HistoryOverride = $null
    }
    [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding
  }
}

function Invoke-PreviousAddToHistoryHandler([string] $Line) {
  if ($null -ne $script:HistoryOverride -and $script:HistoryOverride.Line -eq $Line) {
    # Our own AddToHistory() call above re-enters the handler: keep the decision already made
    # for this line (MemoryOnly for lines that look like they contain secrets).
    return $script:HistoryOverride.Decision
  }
  $handler = $script:PreviousAddToHistoryHandler
  if ($null -eq $handler) { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile }
  if ($handler -is [scriptblock]) { return & $handler $Line }
  $handler.Invoke($Line)
}

function Restore-AliasExpansionOnEnter {
  if (-not (Get-Module -Name PSReadLine)) { return }
  if ((Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Enter' }).Function -eq 'ExpandUnixAliasAndAcceptLine') {
    Set-PSReadLineKeyHandler -Key Enter -Function AcceptLine
    Set-PSReadLineOption -AddToHistoryHandler $script:PreviousAddToHistoryHandler
  }
}
