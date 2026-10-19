# easynote

Plain notes — a title, bullets and checkboxes — on a Linux desktop and on
Android, with a home-screen widget. Notes are Markdown files in a private
GitHub repository of your own. There is no server and no background sync:
the app syncs when it opens and when you close a note.

## Download

- **Android** (phone, e-ink tablet): [easynote.apk](https://github.com/corentinravoux/easynote/releases/latest/download/easynote.apk)
- **Linux** (x64): [easynote-linux-x64.tar.gz](https://github.com/corentinravoux/easynote/releases/latest/download/easynote-linux-x64.tar.gz)

These links always point to the newest release. All releases:
[releases](https://github.com/corentinravoux/easynote/releases).

## How notes are stored

The repository *is* the note tree. A folder is a directory, at any depth;
a note is a `.md` file:

```markdown
# Lyα tomography
- void finder on the reconstructed maps
  - sub-item, indented two spaces
- [ ] check the Wiener filter
- [x] compare with VIDE
```

Anything else in a file (a paragraph, a line typed on github.com) is kept
exactly as written. Hidden files, non-Markdown files and the top-level
`README.md` are ignored.

Each save is one commit. If two devices change the same note before
syncing, nothing is merged and nothing is lost: the version from the other
device stays at the original path and yours is saved next to it as
`<name>.conflict-<device>-<date>.md`, marked in the grid. Merge by hand and
delete the copy.

## Set up

1. On github.com, create a **private** repository for your notes and add a
   README (the app needs at least one commit).
2. Create a [fine-grained personal access
   token](https://github.com/settings/personal-access-tokens/new) with
   access to **only that repository** and the permission
   **Contents: read and write**.
3. Install easynote (below), open Settings, fill in owner, repository and
   token, and press **Test connection**.

The token is stored in the system keyring (GNOME Keyring on Linux, the
Keystore on Android), never in a file. Notes are not encrypted: GitHub and
anyone with access to the repository can read them.

## Install

**Android** (phone or e-ink tablet): download
[easynote.apk](https://github.com/corentinravoux/easynote/releases/latest/download/easynote.apk)
on the device and open it. Long-press the home
screen to add the *Recent notes* widget. On an e-ink tablet, turn on
**E-ink mode** in Settings.

**Linux**: download
[easynote-linux-x64.tar.gz](https://github.com/corentinravoux/easynote/releases/latest/download/easynote-linux-x64.tar.gz)
and run

```bash
scripts/install-linux.sh easynote-linux-x64.tar.gz
```

It installs into `~/.local/share/easynote/app` and adds a menu entry.
Notes and settings live in `~/.local/share/io.easynote.app`.

## Keys

| key | in the grid | in a note |
|---|---|---|
| Ctrl+N | new note | |
| Ctrl+F | search | |
| F5 | sync now | |
| Enter | | new item |
| Tab / Shift+Tab | | indent / outdent |
| Ctrl+Enter | | bullet ↔ checkbox |
| Backspace on an empty item | | delete it |
| Ctrl+S | | save and sync |
| Esc | | close and sync |

## Build from source

Requires Flutter (stable), and for Linux:
`clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev`.

```bash
flutter test                  # unit and widget tests
flutter build linux --release
flutter build apk --release   # signed if android/key.properties exists
```

`flutter test test/live` runs a sync test against a real, throwaway
repository when `EASYNOTE_TEST_TOKEN` and `EASYNOTE_TEST_REPO` are set.
`flutter test tool/screens --update-goldens` renders the main screens to
`tool/screens/out/` for review.

### Release signing

Create a keystore once and keep it safe — an APK signed with another key
cannot update an installed one:

```bash
keytool -genkeypair -v -keystore easynote-release.jks -keyalg RSA \
  -keysize 4096 -validity 36500 -alias easynote
```

For local builds, write `android/key.properties` (gitignored):

```properties
storeFile=/absolute/path/to/easynote-release.jks
storePassword=…
keyAlias=easynote
keyPassword=…
```

For CI releases, add the repository secrets `ANDROID_KEYSTORE_B64`
(`base64 -w0 easynote-release.jks`), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`, then push a tag `v*`.

## Licence

MIT. Bundled fonts: Literata and Atkinson Hyperlegible, both under the SIL
Open Font License (see `assets/fonts/`).
