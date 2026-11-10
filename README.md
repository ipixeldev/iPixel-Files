# iPixel-Files

<p align="center">
  <img src="icons/AppIcon1024.png" width="168" alt="iPixel-Files pixel art icon">
</p>

<p align="center"><strong>A beautiful, safety-first iOS container and file manager.</strong></p>

This tree contains the **iPixel-Files** native UI redesign by **iPixelDev**, based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. See [IPIXEL-README.md](IPIXEL-README.md) for build instructions, validation status, complete credits, and the included GitHub Actions IPA workflow.

Version 1.4 adds native media playback, safe archive browsing/extraction, read-only SQLite browsing and aligned container cards. Version 1.3 added explicit folder states, persistent starred locations, reliable icon fallbacks and a disciplined Pixel type scale.

## iPixel-Files highlights

- Complete **iPixel Blue**, **iPixel Lime** and optional **iPixel Pixel** visual systems.
- Automatic blue or yellow/lime app icon and matching animated folder stacks.
- File sorting by default order, name, date, type or size in either direction.
- Dual browser: side-by-side on iPad and retained Left/Right locations on iPhone.
- Cross-container transfer shelf, safe replacement backups, Duplicate and detailed Info.
- Persistent starred folders with quick access from Home.
- Clear loading, loaded-empty, no-results and access-denied folder states.
- System, Light and Dark appearance modes.
- Animated, text-free folder-stack splash and scan progress UI.
- App/container browser, backups, cache cleaner and activity log.
- Text, image, property-list and hex viewing/editing tools.
- Native video/audio playback, safe ZIP/TAR browsing and extraction, and read-only SQLite table browsing.
- Safety backups and verification before destructive file operations.
- Original pixel-art icon and iPhone/iPad icon renditions.

---

# Worse Query Files

**WQ Files** is a file browser, app data manager and cache cleaner for iOS 26
and 27. "WQ" stands for worse_query, the sandbox technique it is built on. It
reaches other apps' and system containers with no jailbreak and no kernel
exploit. Tested on iOS 26.7.1, 27.0.1 and 27.2.

**iOS 26 (26.0 to 26.7.2):** supported since 0.7; tested on 26.7.1. worse_query reaches the app, extension, daemon and app group
containers there, but not System Data or the system groups, so WQ Files hides
those two and the Cache Cleaner has no crash-log section. A full inode scan
would take most of an hour on iOS 26, so App Data, Extension Data and App
Groups are listed from the LaunchServices database instead (found once and
remembered). Internal Daemons aren't in that database: the first scan for them
takes long, later ones only check new files. Apps, backups, restores, clearing
app data, the Cache Cleaner and the file browser work as on iOS 27.

## What it opens

- **App Data**: every app's data container (`Containers/Data/Application`),
  shown with the app's name and icon instead of a UUID.
- **App Groups**: shared group containers.
- **Extension Data** and **Internal Daemons**.
- **System Data**: `/var/containers/Data/System` (listing only; its contents
  are owned by root).
- **System Groups**: the parent cannot be listed on 27.0.1, so known container
  names are tried one by one; tap **+** to try another name. Covers the
  MobileGestalt cache and the configuration-profiles (Supervision) folder.
- **Go to Path** for any absolute path.

The container parents give no access token on 27.0.1, so their contents are
found by asking the kernel for the path of each inode number (`fsgetpath`),
the way KAMUI does it.

## Tools

- **Apps**: every app with its data size. Back up an app's **Documents and
  Library**, restore the latest backup, clear its data (Documents, Library,
  and tmp), open its folder, or share a backup as a ZIP over AirDrop, Files,
  Mail and so on. `tmp` is intentionally ephemeral: clear removes it, but app
  backups do not include it and restore leaves the current `tmp` untouched.
- **Cache Cleaner**: cache and temp size per app, with search, Select All /
  None / Large Caches (50 MB+) and crash logs. Long-press an app to jump to its
  Caches, tmp or data folder.
- **Files**: browse, read and share files; each opens in the fitting tool,
  and **Open As** switches between them. Saving writes back in place (same
  inode, owner and attributes). Create folders, import files, rename and
  delete (long-press, or swipe a row left or right; deleting always asks
  first). Long-press a folder to share it as a ZIP.
  - **Plist editor**: browse dictionaries and arrays, edit values by type
    (switches for booleans, numbers, text, dates, data as hex), add, delete,
    rename and reorder. Saves in the file's own format (binary or XML).
  - **Hex viewer and editor**: any file size (read in pages), go to offset,
    find hex bytes or text, overwrite bytes in place. Changed bytes are
    highlighted until saved; the file size never changes.
  - **Text and images**: text is editable, images render, plists can also be
    edited as XML text.
- **Log**: file writes, backups, deletions, restores and errors the app handled, plus the App Group it received.

App names come from LaunchServices' own database, read from lsd's container
(the LaunchServices API itself refuses this app on 27.x). Apple services that
only have localized names use a built-in table. Services without an icon get a
symbol tile.

## Safety

Before a regular file is overwritten or deleted, its contents are copied to
**Backups** inside the app (also reachable in the Files app). Long-press a
backup to restore it to its original location. In the file browser only empty
folders can be deleted; symbolic links are removed as links. Clearing an app's
data and cleaning caches delete without a file-by-file backup; Apps offers to
back up Documents and Library first, while `tmp` is discarded and cannot be
restored. Close the target app before backup, restore, or clear. App copies are
verified by a source-stability digest, a destination-shape digest and stored
part content hashes (rechecked before restore and rollback), and purge
postconditions are rechecked, but the operations are not filesystem snapshots
if the target app keeps running. Target data is changed only in response to
explicit actions; interrupted safety transactions may be recovered on startup.

File saves retain the original inode and verify descriptor identity and saved
contents. Locks are advisory: another app that ignores them can still write
concurrently, and in-place writes are not crash-atomic. Close the target app and
keep the durable backups. Recovery fails closed when required safety material is
missing. Generic overwrite/delete operations on backup-storage files are refused
to avoid recursively backing up backups; valid backups can still be restored.
App backups live in **App Backups** (also in the Files app); old ones are never
pruned automatically. Tap **Select** in **Backups** or **App Backups** to
choose one or more complete backup folders and delete them together; a single
folder can still be removed with **Delete Backup**. Automatic pruning is
intentionally left out so a safety copy is never discarded without a user
decision.

Editing another app's or the system's files can break things. Keep the backups
and only change what you understand.

## Troubleshooting

- **Apps list is empty**: the Apps screen depends on a full `fsgetpath` scan of
  the data volume. A missing/denied container parent, an unavailable inode
  probe, or an exhausted scan bound is logged as `enumerate: …` and
  `app scan: …` in **Log**. The current build only treats a *missing* parent as
  failure; a denied parent and a completion-probe miss still return the
  scanned subset, so refresh instead of assuming there are no apps.
- **`NO TOKEN`**: the container path was visible but `wq_grant` could not
  obtain a sandbox token. Common causes are a signer that dropped the App
  Group, an app-group cache-swap failure, or a container the app-group query
  refuses. See the `grant failed`/`enumerate` lines in **Log**.
- **`(no label)`**: a token was obtained, but the container identifier
  (`com.apple.containermanager.identifier` xattr or the container metadata
  plist) could not be read. On iOS 27.2 the attribute can't be read at all,
  so WQ Files also asks the container manager for a path-to-identifier map
  and then looks the container up in the LaunchServices database, which lists
  the data container of every app and most extensions. If the identifier is
  still missing (for example a system/daemon container with none, or an
  extension the database doesn't list), the folder stays browsable but cannot
  be backed up or cleared until identity is available.

## Install with AltStore or SideStore

Add this source to get WQ Files and its updates:

```
https://raw.githubusercontent.com/kolbicz/WQFiles/main/source.json
```

Or download `WQFiles.ipa` from [Releases](https://github.com/kolbicz/WQFiles/releases) and sign it yourself.

## Signing: the App Group

WQ Files needs an **App Group** to work: worse_query asks for access through
your app's group container. Whatever signs the IPA must give it one. The app
uses whichever group it receives, so the group name doesn't matter. The top
of **Log** shows the group it got, or "No App Group" when it got none.

- **AltStore, SideStore or Sideloadly with your Apple ID** (free or paid):
  they create the App Group automatically. This is the easiest way.
- **Feather, ESign and similar tools with a certificate (.p12) and a
  provisioning profile:** the profile has to contain an App Group. Wildcard
  profiles (App ID `*`), which most certificate sellers provide, can't contain
  one, so signing fails with an entitlement error, or the app reports "No App
  Group".
- **Your own developer account:** in the Apple Developer portal create an App
  Group (Identifiers → App Groups), create an explicit App ID with the **App
  Groups** capability and that group assigned, then create a provisioning
  profile for that App ID. Sign the IPA with that profile, keeping the App
  Group entitlement.

## Build and signing

`./build.sh` compiles an arm64 binary and ad-hoc signs it with an App Group
entitlement (`group.app.ipixel.files`). The technique needs an App Group, so
re-sign with a tool that keeps one; the app uses whichever group it actually
receives and shows it at the top of the **Log**. If it reports "No App Group",
the signer dropped it.

The deployment minimum is iOS 26.0. Builds first run the host regression suite,
then stage and validate the archive, metadata, signature and App Group before
replacing `iPixel-Files.ipa` in the project directory. Set `WQ_SKIP_PREFLIGHT=1` for
fixture builds that do not have a test tree. For a separate output, set
`WQFILES_FINAL_IPA` to an absolute path in an existing directory. The source
updater validates the IPA's embedded metadata before atomically replacing
`source.json`; its version/build arguments must match the artifact, and an
existing release description is preserved when no new notes are supplied.

## Regression tests

Run `./tests/run_all_tests.sh` on macOS with Xcode and Python 3. It runs twelve
portable Foundation fixture executables, the Python release fixtures, static
browser checks, and strict iOS arm64 compilation/linkage. Logs and generated
files stay under `.work/tests/`; the existing IPA is not replaced. With only
Command Line Tools installed, set `WQ_SKIP_IOS_CHECK=1` to run the host tests.
Set `WQ_ASAN=1` to compile the host fixtures with AddressSanitizer.

These tests use disposable files and entitlement/access doubles. They do not
issue sandbox tokens or mutate installed app containers. Real iOS signing,
token issuance, navigation/lifecycle timing, power-loss behavior and app-side
concurrent writes still require supported-device validation.

## Credit and license

- **iPixel-Files design and development:** [iPixelDev](https://github.com/ipixeldev).
- Pixel typography: Press Start 2P from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/pressstart2p), licensed under the SIL Open Font License 1.1.
- **Original project:** [WQFiles](https://github.com/kolbicz/WQFiles) by [kolbicz](https://github.com/kolbicz).
- Sandbox technique: [worse_query](https://github.com/forcequitOS/worse_query)
  by Taj C (forcequit), GPL-3.0-or-later. This app reimplements it.
- Container enumeration with `fsgetpath`: from
  [KAMUI](https://github.com/murk-sus/kamui-escape) by murk-sus.

iPixel-Files and its WQFiles-derived source are distributed under GPL-3.0-or-later. See `LICENSE`.
