# Bash-style aliases, sudo for PowerShell commands, completion for native commands, PWD/SHELL
# sync and Windows-style keys. See README.md for options.
Import-Module PwshUnixBridge

# Personal preferences (not part of the module)
$PSStyle.Formatting.FormatAccent = $PSStyle.Foreground.Green
$PSStyle.Formatting.TableHeader = $PSStyle.Foreground.Green
$PSStyle.Formatting.ErrorAccent = $PSStyle.Foreground.Cyan
$PSStyle.Formatting.Error = $PSStyle.Foreground.Red
$PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
$PSStyle.Formatting.Verbose = $PSStyle.Foreground.Blue
$PSStyle.Formatting.Debug = $PSStyle.Foreground.Magenta
$env:EDITOR = 'nano'
