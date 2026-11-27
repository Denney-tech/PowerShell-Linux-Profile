# PowerShell-Linux-Profile

**PwshUnixBridge** is a PowerShell module for using pwsh as your everyday shell on Linux, login shell included. It keeps PowerShell's object model and Windows PowerShell's keyboard habits, and adds bridging layers where bash muscle memory or Unix tools expect something pwsh doesn't do on its own.

With the module installed, the profile in [.config/powershell/profile.ps1](.config/powershell/profile.ps1) is a single `Import-Module PwshUnixBridge` line plus personal preferences (colors, `$EDITOR`).

Requires PowerShell 7.4 or later.

## Features

| Feature | What you get |
|---|---|
| **Aliases** | bash-style aliases: `ls`, `grep`, `diff` and `ip` get `--color=auto`, and you can add your own (`Set-UnixAlias ll 'ls -l'`). They expand on the command line when you press Enter. |
| **Sudo** | `sudo` runs PowerShell commands as root, with your quoting intact: `sudo Remove-Item /opt/foo -Recurse`. |
| **Completion** | bash-like tab completion for native commands (subcommands, flags, live values like systemd units), through [carapace](https://carapace.sh) if it's installed. |
| **Environment** | `$env:PWD` follows every location change, so child processes start in the right directory. `$env:SHELL` points at pwsh. |
| **KeyBindings** | Windows-style PSReadLine keys: Tab cycles completions, Ctrl+Space opens the menu, Ctrl+Left/Right move by word. |

Every feature is on by default. To turn one off, pass an options table when you import the module:

```powershell
Import-Module PwshUnixBridge -ArgumentList @{ KeyBindings = $false; Completion = $false }
```

### Aliases

```powershell
Set-UnixAlias ll 'ls -l'       # ll /etc  ->  ls --color=auto -l /etc
Get-UnixAlias                  # list them (wildcards allowed)
Remove-UnixAlias ll
Expand-UnixAlias 'll /etc'     # show what a line expands to
```

Aliases work the way they do in bash:
- Only interactive command lines are expanded, never scripts.
- Only the command word expands. Quoted names, paths and `& ls` are left alone.
- Aliases expand recursively, but an alias never re-expands itself, so `ls` → `ls --color=auto` stops there.
- A value ending in a space makes the next word eligible too. The default `sudo` alias uses this, so `sudo ls` expands `ls`.

The expanded line is what runs, so the real program gets the terminal directly. Colors, streaming output, pipeline input and exit codes behave exactly as they would without the alias.

History stores what you typed (`ll /etc`), not the expansion. Lines that PSReadLine keeps out of the history file because they look like they contain secrets stay out of it.

### Sudo

| You type | What runs |
|---|---|
| `sudo dnf upgrade` | sudo directly; native programs need no bridging. |
| `sudo Get-Content /etc/shadow -TotalCount 1` | `pwsh -NoProfile` as root, with the command text forwarded exactly as typed. |
| `sudo { Get-ChildItem /root \| Measure-Object }` | The script block, as root. |
| `sudo -i`, `sudo -u bob id` | sudo unchanged. A leading option means you're talking to sudo itself. |

Quoting survives: `sudo chown -R 'root:domain users@domain.com' /usr/local/` works as typed. Your own global aliases for programs (for example `Set-Alias k kubectl` in your profile) are resolved before sudo sees them. Aliases and functions defined only inside a script's own scope aren't visible to the module, and they don't exist in the root pwsh either.

The root pwsh loads PwshUnixBridge too, so its aliases and functions are available inside elevated commands. Output comes back as text, not live objects. You can pipe it into `ForEach-Object` and similar commands, but its properties are gone.

### Completion

Install [carapace](https://carapace-sh.github.io/carapace-bin/install.html) (the `carapace` binary on your `PATH`). The module then loads carapace's completers for about 1000 CLIs. For other commands it borrows bash-completion's completers (it sets `CARAPACE_BRIDGES=bash` unless you've set it yourself). Without carapace, native commands keep PowerShell's default path completion.

carapace's PowerShell setup takes about 400 ms to generate, so the module caches it under `~/.cache/PwshUnixBridge/`. The cache is rebuilt automatically when the carapace binary, `~/.config/carapace` or `CARAPACE_BRIDGES` changes.

> Don't load `Microsoft.PowerShell.UnixTabCompletion` alongside the module. That module is archived, and its bash bridge runs some programs (nano, for one) while it computes completions, which looks like a hung shell.

## Install

The module isn't on the PowerShell Gallery yet. Clone the repo and link the module folder into your module path:

```bash
git clone https://github.com/Denney-tech/PowerShell-Linux-Profile.git ~/src/PowerShell-Linux-Profile
mkdir -p ~/.local/share/powershell/Modules
ln -s ~/src/PowerShell-Linux-Profile/PwshUnixBridge ~/.local/share/powershell/Modules/PwshUnixBridge
```

Then add `Import-Module PwshUnixBridge` to your profile (`$PROFILE`, usually `~/.config/powershell/Microsoft.PowerShell_profile.ps1`), or use [.config/powershell/profile.ps1](.config/powershell/profile.ps1) as a starting point. A `git pull` updates it.

To make pwsh your login shell, make sure its absolute path (`command -v pwsh`, e.g. `/usr/bin/pwsh`) is listed in `/etc/shells`, then pass that same path to `chsh -s "$(command -v pwsh)"`.

## Upgrading from the old profile

- `Invoke-Nano`, `Invoke-LS` and `Invoke-Grep` are gone. `nano` is the real binary again, and the `ls`/`grep` colors now come from aliases.
- The Enter-key `$env:PWD` workaround is replaced by a location-change hook. It also covers scripts and functions.
- `Microsoft.PowerShell.UnixTabCompletion` is no longer imported. See [Completion](#completion).

## Tests

```bash
pwsh -NoProfile -File tests/Test-PwshUnixBridge.ps1
```

Some parts run only when their prerequisites exist, and the runner says which ones it skipped:
- `sudo` tests: passwordless `sudo`.
- Completion tests: `carapace` on your `PATH`.
- Interactive Enter-key and history tests: `python3`. [tests/pty_session.py](tests/pty_session.py) drives a real PSReadLine session through a pseudo-terminal.

CI runs all of them, plus PSScriptAnalyzer, on every pull request.
