# Bash-like completion for native commands through carapace (https://carapace.sh), which has
# completers for ~1000 CLIs and borrows bash-completion's for the rest (CARAPACE_BRIDGES=bash).
# carapace's generated PowerShell setup costs ~400 ms to produce on every shell start, so it is
# cached and regenerated only when the carapace binary, its config or the bridges change
# (loading the cached copy takes ~80 ms).

function Get-UnixCompletionCacheDirectory {
  $base = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $HOME '.cache' }
  Join-Path $base 'PwshUnixBridge'
}

function Find-Executable([string] $Name) {
  # Checks each PATH entry directly instead of Get-Command, which enumerates every PATH
  # directory: ~1 s under WSL, where PATH includes the Windows drives (/mnt/c/...).
  foreach ($dir in $env:PATH -split [IO.Path]::PathSeparator) {
    if (-not $dir) { continue }
    $candidate = [IO.Path]::Combine($dir, $Name)
    if ([IO.File]::Exists($candidate)) { return $candidate }
  }
}

function Get-UnixCompletionScript {
  # Returns the path of the cached carapace setup script (the caller dot-sources it at module
  # scope), or nothing when carapace isn't installed.
  $carapace = Find-Executable carapace
  if (-not $carapace) {
    Write-Verbose 'PwshUnixBridge: carapace not found on PATH; native commands keep PowerShell''s default completion.'
    return
  }
  if (-not $env:CARAPACE_BRIDGES) { $env:CARAPACE_BRIDGES = 'bash' }

  $binary = Get-Item -LiteralPath $carapace
  $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
  $config = Get-Item -LiteralPath (Join-Path $configHome 'carapace') -ErrorAction SilentlyContinue
  $fingerprint = '{0}|{1}|{2}|{3}|{4}' -f $binary.FullName, $binary.Length, $binary.LastWriteTimeUtc.Ticks,
    $config.LastWriteTimeUtc.Ticks, $env:CARAPACE_BRIDGES
  $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($fingerprint))).Substring(0, 16)

  $cacheDir = Get-UnixCompletionCacheDirectory
  $cacheFile = Join-Path $cacheDir "carapace-$hash.ps1"
  if (-not (Test-Path -LiteralPath $cacheFile)) {
    $setup = & $carapace _carapace powershell | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $setup.Trim()) {
      Write-Warning "PwshUnixBridge: 'carapace _carapace powershell' failed (exit $LASTEXITCODE); completion not loaded."
      return
    }
    $null = New-Item -ItemType Directory -Path $cacheDir -Force
    Get-ChildItem -LiteralPath $cacheDir -Filter 'carapace-*.ps1' | Remove-Item -Force
    $temp = "$cacheFile.$PID.tmp"
    Set-Content -LiteralPath $temp -Value $setup -NoNewline
    Move-Item -LiteralPath $temp -Destination $cacheFile -Force
  }
  $cacheFile
}
