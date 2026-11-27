#!/usr/bin/env python3
"""Drive an interactive pwsh session through a pseudo-terminal, for testing PSReadLine handlers.

    pty_session.py <pwsh> <profile.ps1> <line>...

Starts `pwsh -NoProfile -NoExit -Command . <profile>`, types each line (then `exit`) once the
`PS> ` prompt appears, and writes the raw terminal output to stdout. PSReadLine asks the terminal
for the cursor position (ESC[6n) and blocks until it answers, so this answers every query, which a
plain pipe into script(1) can't do.
"""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

PROMPT = b"PS> "
CURSOR_QUERY = b"\x1b[6n"
TIMEOUT = 90
EXIT_GRACE = 10  # seconds to wait for pwsh to exit after the final `exit` line


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    pwsh, profile, *lines = sys.argv[1:]
    pending = [*lines, "exit"]
    sent_all_at = 0.0

    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 250, 0, 0))
        os.environ["TERM"] = "xterm-256color"
        os.execv(pwsh, [pwsh, "-NoLogo", "-NoProfile", "-NoExit", "-Command", f". '{profile}'"])

    output = bytearray()
    prompts_answered = 0
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        if not pending:
            # Everything is typed; don't wait out the full timeout if an older PSReadLine
            # leaves the session open (seen with pwsh 7.4.2).
            deadline = min(deadline, sent_all_at + EXIT_GRACE)
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:  # EIO: the child exited and closed the terminal
                break
            if not data:
                break
            output += data
            for _ in range(data.count(CURSOR_QUERY)):
                os.write(fd, b"\x1b[1;1R")
        if pending and output.count(PROMPT) > prompts_answered:
            prompts_answered = output.count(PROMPT)
            time.sleep(0.3)  # let PSReadLine finish rendering the prompt
            os.write(fd, pending.pop(0).encode() + b"\r")
            if not pending:
                sent_all_at = time.monotonic()

    try:
        finished, _ = os.waitpid(pid, os.WNOHANG)
        if not finished:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    sys.stdout.buffer.write(bytes(output))
    if pending:
        print(f"pty_session: timed out with {len(pending)} line(s) not typed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
