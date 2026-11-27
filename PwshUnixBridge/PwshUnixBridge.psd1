@{
  RootModule           = 'PwshUnixBridge.psm1'
  ModuleVersion        = '0.1.0'
  GUID                 = 'fc1158e9-0d36-474f-9799-09c5993e5d4d'
  Author               = 'Caleb Denney'
  Copyright            = '(c) 2024 Caleb Denney. MIT License.'
  Description          = 'Bridges Windows PowerShell habits with Unix behavior for pwsh as a daily (login) shell on Linux: bash-style aliases expanded on the command line, sudo that runs PowerShell commands, bash-like completion for native commands via carapace, PWD/SHELL environment sync, and Windows-style PSReadLine keys.'
  PowerShellVersion    = '7.4'
  CompatiblePSEditions = @('Core')

  FunctionsToExport    = @(
    'Expand-UnixAlias'
    'Get-UnixAlias'
    'Invoke-Sudo'
    'Remove-UnixAlias'
    'Set-UnixAlias'
  )
  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @('sudo')

  PrivateData          = @{
    PSData = @{
      Tags       = @('Linux', 'Unix', 'bash', 'sudo', 'alias', 'completion', 'carapace', 'PSReadLine', 'PSEdition_Core')
      LicenseUri = 'https://github.com/Denney-tech/PowerShell-Linux-Profile/blob/main/LICENSE'
      ProjectUri = 'https://github.com/Denney-tech/PowerShell-Linux-Profile'
    }
  }
}
