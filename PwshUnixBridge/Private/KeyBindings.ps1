# Windows-style PSReadLine keys. On Linux PSReadLine defaults to Emacs-style bindings, where
# Tab opens a menu; these restore the Windows PowerShell habits.
function Initialize-WindowsKeyBinding {
  Set-PSReadLineKeyHandler -Key 'Ctrl+LeftArrow' -Function BackwardWord
  Set-PSReadLineKeyHandler -Key 'Ctrl+RightArrow' -Function ForwardWord
  # Terminals send Ctrl+Space as Ctrl+@.
  Set-PSReadLineKeyHandler -Key 'Ctrl+@' -Function MenuComplete
  Set-PSReadLineKeyHandler -Key 'Ctrl+Spacebar' -Function MenuComplete
  Set-PSReadLineKeyHandler -Key 'Tab' -Function TabCompleteNext
  Set-PSReadLineKeyHandler -Key 'Shift+Tab' -Function TabCompletePrevious
}
