# claudedesk

Run two Claude Desktop instances side by side on a Mac, each signed in to a
different organization. Built for SPST + Resurrection, configurable for any
set of profiles.

Claude Desktop keeps one login per data directory and has no account switcher.
It is an Electron app, and Electron honors `--user-data-dir`, so a second copy
started with its own data directory runs fully isolated: its own login, chat
cache, MCP configuration, and single-instance lock. claudedesk wraps that in
two small launcher apps so it works from Spotlight and the Dock.

Nothing in `Claude.app` is modified. Its code signature and auto-update keep
working.

## What you get

| Launcher                   | Profile directory                                   | Signed in as |
| -------------------------- | --------------------------------------------------- | ------------ |
| `Claude SPST.app`          | `~/Library/Application Support/Claude` (the default) | SPST         |
| `Claude Resurrection.app`  | `~/Library/Application Support/Claude-Resurrection`  | Resurrection |

Each launcher either brings its own running Claude window to the front or
starts a new instance for its profile. Clicking a launcher never spawns a
duplicate.

## Install

Requirements: macOS 12 or later, Claude Desktop installed in `/Applications`.
No Xcode, Homebrew, or other dependencies.

```sh
git clone https://github.com/inspectorgad/claudedesk.git
cd claudedesk
./install.sh
```

`install.sh` builds both launchers into `build/` and copies them to
`/Applications` (or `~/Applications` if that is not writable). Re-run it any
time to rebuild.

## First sign-in to the second profile

Claude finishes sign-in through a `claude://` link that the browser hands back
to macOS. With two Claude windows open, macOS may deliver that link to the
wrong one. So:

1. Open **Claude SPST**. It runs your existing profile, already signed in.
2. Open **Claude Resurrection**. Because its profile does not exist yet and
   another Claude window is open, it offers to quit the other Claude first.
   Choose **Quit Other Claude**, then sign in with the Resurrection account.
3. Open **Claude SPST** again. Both windows now run at the same time, each
   signed in to its own organization, and they stay that way across restarts.

If you ever sign out of one profile and need to sign back in, quit the other
Claude window first for the same reason.

## Daily use

- Launch either profile from Spotlight (`Claude SPST`, `Claude Resurrection`)
  or pin both launchers to the Dock.
- The two running windows both show the stock Claude icon and the name
  "Claude". The launchers carry the badged icons. Tell the windows apart by
  the organization shown inside Claude.
- The first time a launcher focuses a running window, macOS asks to allow it
  to control **System Events**. Click OK. That permission is what brings the
  right window forward.

## Where things live

| Item                              | SPST                                                 | Resurrection                                                      |
| --------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------- |
| Profile data                      | `~/Library/Application Support/Claude/`              | `~/Library/Application Support/Claude-Resurrection/`              |
| MCP servers                       | `.../Claude/claude_desktop_config.json`              | `.../Claude-Resurrection/claude_desktop_config.json`              |
| Launcher log                      | `~/Library/Logs/claudedesk.log`                      | same file, tagged by profile                                      |

MCP configuration is intentionally separate. To give Resurrection the same
servers, copy the JSON file across once.

## Adding or renaming profiles

Edit `profiles.conf` and re-run `./install.sh`. One launcher is built per
line:

```
# name | profile dir | badge text | badge color (hex)
SPST||SPST|1F3A5F
Resurrection|~/Library/Application Support/Claude-Resurrection|COR|7A1F3D
```

Leave the profile dir empty for exactly one line; that launcher uses Claude's
default data directory.

## Uninstall

```sh
./uninstall.sh                   # remove the launcher apps only
./uninstall.sh --purge-profiles  # also delete the extra profile data (asks first)
```

Claude Desktop and its default profile are never removed.

## How it works

- `src/launch.sh` is the executable inside each launcher bundle. It reads its
  profile from the bundle's `Info.plist`, finds `Claude.app`, and inspects
  running Claude processes by their command line to decide between focusing
  an existing window and starting a new one with
  `open -n -a Claude.app --args --user-data-dir=<profile dir>`.
- `build.sh` renders `src/Info.plist.tmpl` for each profile, copies the
  launcher in, draws a badged icon from Claude's own icon with
  `src/make-icon.js` (a JavaScript for Automation script using AppKit), and
  ad-hoc signs the bundle.
- Launchers are marked `LSUIElement`, so they never appear in the Dock
  themselves; they hand off to Claude and exit.

## Development

```sh
tests/test_launch.sh
```

The tests drive the launcher in `--dry-run` mode with fake `pgrep`/`ps` and
run a build smoke test. They pass on Linux and macOS; the icon step only runs
on macOS with Claude installed.

## Troubleshooting

- **"Claude Desktop not found"**: install Claude Desktop into
  `/Applications` (or `~/Applications`).
- **Sign-in opened in the wrong window**: quit both Claude windows, open only
  the launcher you want to sign in to, and sign in again.
- **Launcher does nothing**: check `~/Library/Logs/claudedesk.log`. Each run
  logs the profile, the resolved `Claude.app` path, and the action taken.
- **Reset the Resurrection profile**: quit that instance, then delete
  `~/Library/Application Support/Claude-Resurrection`. The next launch starts
  clean.

## Sources

The `--user-data-dir` technique and the deep-link caveat are documented in:

- [How I Forced My Mac to Run 2 Instances of Claude Desktop AND Claude Code](https://helloai.substack.com/p/how-i-forced-my-mac-to-run-2-instances)
- [Running Multiple Claude Desktop Instances Side by Side](https://philippstracker.com/multiple-claude-instances/)
- [How To Run Two Claude Accounts on Mac Simultaneously](https://melkon.tech/blog/two-claude-accounts-mac)
