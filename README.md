# PowerShell-Linux-Profile
Customizes syntax highlighting.
Imports Modules
Adds aliases for bash compatiblity functions.

# Aliases
sudo - Invoke-Sudo

ls   - Invoke-LS

grep - Invoke-Grep

# Compatibility Functions
## Nano
With the Microsoft.PowerShell.UnixTabCompletion module loaded, tab completing a path after `nano` used to hang the shell. The cause: the module's bash-completion bridge ends up *running nano* while it computes completions, and nano grabs the terminal. The profile now registers PowerShell's own filename completer for `nano` after importing the module, so paths complete normally and `nano` is the real binary again — every nano option works (`nano -l file`, `nano +10 file`, ...).

## Sudo
With no arguments, or when the first argument is a flag (`sudo -i`, `sudo -u user ...`), arguments go straight to sudo. Otherwise, sudo traditionally does not work with PowerShell, but this is partcially because sudo runs as the shell of the targeted user (default root user tends to use bash). Since Bash and PowerShell commands are not interchangable, the sudo shell needs to switch to pwsh for it to understand the command. `Invoke-Sudo` is a custom function to facilitate running sudo in powershell when appropriate, and forwarding cli arguments to the new shell instance. 

This allows for some useful commands such as the ones below:

``` powershell
# Forcefully remove files
sudo Remove-Item -Path /usr/local/share/powershell/Modules/* -Recurse -Force
```

However, some things will break due to argument/quote/escape encapsulation not quite forwarding as expected:
``` powershell
# This doesn't work
sudo chown -R root:domain\ users@domain.com /usr/local/
# /bin/chown: invalid group: 'root:domain\\'

# This does work
sudo chown -R '"root:domain users@domain.com"' /usr/local/
```

## LS
This enables colored output for `ls` by default (`ls --color=auto`), while maintaining expected behavior.

## Grep
This enables colored output for `grep` by default (`grep --color=auto`), while maintaining expected behavior. Piped input goes to a single `grep` process, so `-c`, `-A`/`-B`/`-C` and the exit status cover all of the input.

## LS/GREP
Neither of these seemed to respect environment variables set in PowerShell to enable color.

# Note to self
I should probably make a bash-pwsh compatibility module and place the related code there so that the module can be dynamically loaded into noprofile sessions.

# Tests
`pwsh -NoProfile -File tests/Test-Profile.ps1` runs smoke tests against the profile (needs `nano`; the completion test also needs Microsoft.PowerShell.UnixTabCompletion). CI runs them, plus PSScriptAnalyzer, on every pull request.
