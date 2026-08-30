# wayland-spice-clipboard-fix

A bridge between the Wayland clipboard and the X11 selection for SPICE/QEMU virtual
machines, so that copying from the guest reaches the host.

Rewrite of [chrisbelson/wayland-spice-clipboard-fix](https://github.com/chrisbelson/wayland-spice-clipboard-fix),
fixing the defects that stopped the bridge from working after a logout or a reboot,
and removing the hard dependency on Fedora for installation.

## The defect this fork fixes

The original works in the session where you start it by hand, and stops working after
a logout or a reboot. It never resolves `XAUTHORITY`: the name of the X authority file
changes on every session start, and the environment systemd gives the service does not
carry it. Without it, `xclip` cannot connect to the X server.

The failure is silent in a particularly misleading way. The service stays `active`, its
log keeps printing `Synced: N chars` on every copy, and every write to X11 fails, because
the error is sent to `/dev/null`. Everything looks healthy while nothing works.

Here the display and the authority are read from the Xwayland process of the current
session, every time the service starts. Verified across three consecutive sessions, each
with a different file, all resolved with no manual intervention:

```
original session     /run/user/1000/xauth_xMtXFp
after logout/login   /run/user/1000/xauth_OThHaF
after reboot         /run/user/1000/xauth_wcKAuq
```

## Why the bridge is needed at all

`spice-vdagent` only reads the X11 selection. In a Wayland session the compositor exposes
the clipboard to X11 applications only while the active window is itself an X11 window:
a deliberate security measure against X11 applications snooping on the clipboard. In KWin
the check lives in `Clipboard::checkWlSource()`.

`spice-vdagent` is an X11 client with no windows, so when you copy from a native Wayland
application it receives nothing and has nothing to send to the host. KDE closed the report
as [RESOLVED UPSTREAM](https://bugs.kde.org/show_bug.cgi?id=510225), deferring to SPICE,
which has no Wayland support in any release.

This bridge reads the Wayland clipboard through `wl-paste`, which uses the
`wlr-data-control` (or `ext-data-control`) protocol, designed for clipboard managers and
therefore not subject to that restriction, and copies the content into the X11 selection
where `spice-vdagent` finds it.

## What else changed

**The display check verified nothing.** The original uses `xclip -version`, which prints
a version string without connecting to X and therefore always succeeds, so the fallback
to other displays never ran. Replaced with `xset q`, which actually opens a connection.

**Errors went to `/dev/null`.** The write to X11 silenced the one message that explained
the failure. Errors now reach the journal.

**The loop polled the clipboard every second.** Replaced with `wl-paste --watch`, which
reacts the moment a copy happens, never misses copies made in quick succession, and does
not keep waking the CPU. The polling version had burned 6.2 seconds of CPU time for a
function that fires a handful of times per hour.

Note that going event-driven requires deduplication. Writing to X11 makes the compositor
propagate the change back to Wayland, which wakes `--watch` a second time. The original
loop happened to break that cycle through its `current_clipboard != last_clipboard`
comparison; without an explicit check against what is already in the X11 selection, the
bridge chases its own writes.

**Installation assumed `dnf`.** Now detects apt, dnf, pacman and zypper.

**The service outlived its session.** The original uses `WantedBy=default.target`, so the
service survives the graphical session and keeps looking for an X server that is gone.
Now bound to `graphical-session.target`, with `Restart=on-failure` and rate limiting
instead of an unbounded restart loop.

## Installation

```
./install.sh
```

Installs the script into `/usr/local/bin`, registers the user service and starts it.

## Verifying

```
systemctl --user status wayland-spice-clipboard.service
```

On startup the service logs which display and which authority file it resolved. If the
authority reads `none`, the bridge will not work: that is the first place to look.

When the bridge is working there is always a live `xclip` process holding ownership of
the selection. If there is none, the X11 clipboard reads as empty even right after a copy.

## Known limits

Text only. Images need separate handling.

In the other direction, when you copy on the host, the compositor writes the guest's X11
selection and propagates it to Wayland; the bridge sees that change and writes it back to
X11. The cycle terminates because the content matches and the deduplication check stops
it, but it is the first thing to look at if the clipboard starts behaving oddly.
