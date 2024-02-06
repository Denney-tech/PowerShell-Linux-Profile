# file path tab completion fix for nano; prevents shell from hanging
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
using namespace System.Collections
using namespace System.Collections.Generic

class Completer : IArgumentCompleter {
    hidden [List[CompletionResult]] $Results = [List[CompletionResult]]::new()

    [IEnumerable[CompletionResult]] CompleteArgument(
        [string] $CommandName,
        [string] $ParameterName,
        [string] $WordToComplete,
        [CommandAst] $CommandAst,
        [IDictionary] $FakeBoundParameters
    ) {
        $this.Results.Clear()
        $dirs = $WordToComplete.split('/')
        $WorkingDir = $(Get-ChildItem $dirs[0..$($dirs.count - 1)] -join '/').FullName
        foreach ($item in Get-ChildItem $WorkingDir) {
            if ($item.Name -like "*$wordToComplete*") {
                $this.Results.Add([CompletionResult]::new(
                    $item.FullName,
                    $item.Name,
                    [CompletionResultType]::ParameterValue,
                    $item.Name))
            }
        }
        return $this.Results
    }
}

# stylization
$PSStyle.Formatting.FormatAccent = $PSStyle.Foreground.Green
$PSStyle.Formatting.TableHeader = $PSStyle.Foreground.Green
$PSStyle.Formatting.ErrorAccent = $PSStyle.Foreground.Cyan
$PSStyle.Formatting.Error = $PSStyle.Foreground.Red
$PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
$PSStyle.Formatting.Verbose = $PSStyle.Foreground.Blue
$PSStyle.Formatting.Debug = $PSStyle.Foreground.Magenta

# environment
$env:SHELL = "/bin/pwsh"
$env:EDITOR = "nano"

# default modules
Import-Module Microsoft.PowerShell.UnixTabCompletion

# custom bash-pwsh compatiblity functions
function Invoke-Sudo {
  if ($args[0][0] -eq '-') {
    /usr/bin/sudo $args
  } else {
    /usr/bin/sudo $env:SHELL -c "$args"
  }

}

function Invoke-Nano {
  [CmdletBinding()]
  param(
    [ArgumentCompleter([Completer])]
    $Path
  )

# alias bash commands to compatibility function
Set-Alias -Name sudo -Value Invoke-Sudo -Description "Passes command to sudo"
Set-Alias -Name nano -Value Invoke-Nano -Description "Passes command to nano"


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
