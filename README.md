# PowerShell-Linux-Profile
Customizes syntax highlighting.
Imports Modules
Adds aliases for bash compatiblity functions.

# Aliases
nano - Invoke-Nano

sudo - Invoke-Sudo

# Compatibility Functions
## Nano
For some reason, even with the Microsoft.PowerShell.UnixTabCompletion module, the pwsh 7.4 shell hangs whenever you try to tab complete paths for nano.  This doesn't occur with any other binary I've tried so far.  To fix this, a custom function `Invoke-Nano` and arguement completer for it are created. The IArgument class is used to prevent falling back to default Completion behavior, which was causing the shell to hang. As a result, only filepaths can be tab completed, and other arguments cannot be passed through to nano.

## Sudo
Sudo traditionally does not work with PowerShell, but this is partcially because sudo runs as the shell of the targeted user (default root user tends to use bash). Since Bash and PowerShell commands are not interchangable, the sudo shell needs to switch to pwsh for it to understand the command. Similarly to nano, `Invoke-Sudo` is a custom function to facilitate running sudo in powershell when appropriate, and forwarding cli arguments to the new shell instance. 

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

# Note to self
I should probably make a bash-pwsh compatibility module and place the related code there so that the module can be dynamically loaded into noprofile sessions.
