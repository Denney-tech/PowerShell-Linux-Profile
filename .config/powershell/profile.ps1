# stylization
$PSStyle.Formatting.FormatAccent = $PSStyle.Foreground.Green
$PSStyle.Formatting.TableHeader = $PSStyle.Foreground.Green
$PSStyle.Formatting.ErrorAccent = $PSStyle.Foreground.Cyan
$PSStyle.Formatting.Error = $PSStyle.Foreground.Red
$PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
$PSStyle.Formatting.Verbose = $PSStyle.Foreground.Blue
$PSStyle.Formatting.Debug = $PSStyle.Foreground.Magenta

# environment
$env:SHELL = [Environment]::ProcessPath # wherever this pwsh lives (/usr/bin/pwsh, /opt/microsoft/..., snap)
$env:EDITOR = "nano"

# default modules
if (Get-Module -ListAvailable -Name Microsoft.PowerShell.UnixTabCompletion) {
  Import-Module Microsoft.PowerShell.UnixTabCompletion

  # UnixTabCompletion's bash bridge ends up *running* nano while computing completions,
  # which grabs the terminal and looks like a hung shell. Complete nano's arguments with
  # PowerShell's own filename completer instead (must be registered after the import).
  Register-ArgumentCompleter -Native -CommandName nano -ScriptBlock {
    param($wordToComplete)
    [System.Management.Automation.CompletionCompleters]::CompleteFilename($wordToComplete)
  }
}

# custom bash-pwsh compatiblity functions
function Invoke-Sudo {
  if ($args.Count -eq 0 -or "$($args[0])".StartsWith('-')) {
    /usr/bin/sudo @args
  } else {
    /usr/bin/sudo $env:SHELL -c "$args"
  }
}

function Invoke-LS {
  process {
    /usr/bin/ls --color=auto $args $_
  }
}

function Invoke-Grep {
  # Pass the whole pipeline to a single grep, so counts (-c), context (-A/-B/-C) and the
  # exit status cover all of the input instead of one line at a time.
  if ($MyInvocation.ExpectingInput) {
    $input | /usr/bin/grep --color=auto @args
  } else {
    /usr/bin/grep --color=auto @args
  }
}

# alias bash commands to compatibility function
Set-Alias -Name sudo -Value Invoke-Sudo -Description "Passes command to sudo"
Set-Alias -Name ls   -Value Invoke-LS   -Description "Enables ls autocolors"
Set-Alias -Name grep -Value Invoke-Grep -Description "Enables grep autocolors"


# Set Curser movements

Import-Module PSReadLine

Set-PSReadLineKeyHandler -Key "Ctrl+LeftArrow" -Function "BackwardWord"
Set-PSReadLineKeyHandler -Key "Ctrl+RightArrow" -Function "ForwardWord"

Set-PSReadLineKeyHandler -Key "Ctrl+@" -Function "MenuComplete"
Set-PSReadLineKeyHandler -Key "Ctrl+Spacebar" -Function "MenuComplete"
Set-PSReadLineKeyHandler -Key "Tab" -Function "TabCompleteNext"
Set-PSReadLineKeyHandler -Key "Shift+Tab" -Function "TabCompletePrevious"

# Workaround for synchronizing pwsh and unix PWD environment variable. Only fixes Console commands, not scripts or other actions that may change PWD on the fly.
Set-PSReadLineKeyHandler -Key Enter {
  $env:PWD = $PWD
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}
