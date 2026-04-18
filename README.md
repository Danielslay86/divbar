# DivBar

Visual dividers for your Linux taskbar. Any desktop environment.

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Shell: Bash](https://img.shields.io/badge/Shell-Bash_4.4%2B-4EAA25.svg)
![Tests: 258 passing](https://img.shields.io/badge/Tests-258_passing-brightgreen.svg)

Linux taskbars don't give you a way to group pinned apps. Ten icons in a row, no separation, no breathing room. DivBar fixes that by generating `.desktop` entries with thin divider icons you can drag onto the panel between your app groups.

No panel plugins. No widgets. No compilation.

## Requirements

Bash 4.4+, and either `zenity` or `kdialog` for the dialogs. Zenity ships with most GTK desktops (GNOME, XFCE, Cinnamon, MATE, Budgie, Pantheon). Plasma ships kdialog. DivBar figures out which one you have and uses it.

Tested on KDE Plasma, GNOME, XFCE, Cinnamon, MATE, LXQt, Budgie, Pantheon, Sway, Hyprland, i3, LXDE, Deepin, Enlightenment, and headless.

## Install

From source:

```bash
git clone https://github.com/danielslay86/divbar.git
cd divbar
bash install.sh
```

From the AUR:

```bash
yay -S divbar
```

From Flathub:

```bash
flatpak install flathub net.slaylab.DivBar
```

The installer puts assets in `~/.local/share/divbar/assets/`, the executable in `~/.local/bin/divbar`, and adds a menu entry. It refreshes the KDE menu cache if you're on Plasma; other DEs pick up new `.desktop` files on their own.

No root needed. Nothing outside `$HOME` gets touched.

## Usage

Launch DivBar from your application menu, pick **Add New Div**, choose orientation (vertical for top/bottom taskbars, horizontal for side ones), pick a style or bring your own image. The new div shows up in your app menu and you drag it to the taskbar from there.

To remove divs, launch DivBar and pick **Uninstall / Remove**. You get three options: clear only the generated divs, complete uninstall of DivBar itself, or select specific divs to remove. Individual divs can also be unpinned directly from the taskbar.

## How it works

Each div is a `.desktop` file with `Exec=/usr/bin/true` and a thin image as its icon. The freedesktop spec is universal, so divs show up in every major DE's application menu and can be dragged to any panel that accepts pinned apps.

At launch DivBar checks `XDG_CURRENT_DESKTOP` and `KDE_FULL_SESSION` to figure out your environment. On Plasma it uses kdialog and refreshes sycoca after adding a div. Everywhere else it uses zenity. If only one of the two is installed it uses that one regardless of DE. If neither is installed it tells you to install one.

## Project layout

```
divbar/
├── install.sh          # installer
├── divbar.sh           # the app
├── verify.sh           # post-install sanity check
├── test_suite.sh       # 258 tests
├── assets/
│   ├── vertical/       # for top/bottom taskbars
│   └── horizontal/     # for left/right taskbars
├── LICENSE
├── README.md
└── CONTRIBUTING.md
```

Installed paths (source install):

| What | Where |
|---|---|
| Executable | `~/.local/bin/divbar` |
| Assets | `~/.local/share/divbar/assets/` |
| Menu entry | `~/.local/share/applications/divbar.desktop` |
| Generated divs | `~/.local/share/applications/div_N.desktop` |
| Div icons | `~/.local/share/icons/hicolor/128x128/apps/div-*` |

## Testing

```bash
bash test_suite.sh        # run all
bash test_suite.sh -v     # verbose
```

258 tests, 34 sections. Runs in a `/tmp` sandbox with mock dialog binaries, so you don't need an actual DE to run it. Covers backend detection across 15 desktop environments, both zenity and kdialog paths (add, remove, cancel, uninstall), input sanitization for path traversal and shell metacharacters, file permissions, installer idempotency, and the kbuildsycoca-only-on-KDE behavior.

## Security notes

Installer bails if run as root. All destructive ops are scoped to `$HOME/.local/share/`. Filenames get sanitized before they hit the filesystem (strips path traversal sequences, shell metacharacters, and non-ASCII). Only `.png`, `.svg`, `.jpg`, `.jpeg`, and `.ico` are accepted as custom images. There's exactly one `rm -rf` in the installer and it targets a validated path. No `eval` anywhere. Generated `.desktop` files use `Exec=/usr/bin/true` so a pinned div can't execute anything if clicked.

## Troubleshooting

**"No dialog tool found."** Install zenity (`sudo apt install zenity`) or kdialog (`sudo apt install kdialog`) depending on your DE.

**Div doesn't show up after adding it on KDE.** Run `kbuildsycoca5` or `kbuildsycoca6` manually. The installer does this automatically but sometimes the cache needs a nudge.

**Div doesn't show up after adding it on other DEs.** Log out and back in. Most DEs watch `~/.local/share/applications/` for new files, but some only rescan on session start.

**"Assets folder not found."** Re-run `bash install.sh` from the cloned repo directory.

**Blank icon on taskbar.** `touch ~/.local/share/icons/hicolor/128x128/apps/` and log out/in to force an icon cache refresh.

**`divbar: command not found` in the terminal.** `~/.local/bin` isn't in your `PATH`. Add it:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## License

MIT. Copyright Daniel Slay.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Fork, branch, make sure tests pass, open a PR.
