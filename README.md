# iPixel-Files

<p align="center">
  <img src="icons/AppIcon1024.png" width="140" alt="iPixel-Files icon" style="border-radius: 28px;">
</p>

<p align="center">
  <strong>A modern, safety-first iOS container and file manager.</strong><br>
  Built on the <code>worse_query</code> sandbox technique — no jailbreak and no kernel exploit required.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-26.0%2B-blue.svg?style=flat-square" alt="iOS 26.0+">
  <img src="https://img.shields.io/badge/version-2.1-success.svg?style=flat-square" alt="Version 2.1">
  <img src="https://img.shields.io/badge/license-GPL--3.0-orange.svg?style=flat-square" alt="GPL-3.0">
  <img src="https://img.shields.io/badge/architecture-arm64-lightgrey.svg?style=flat-square" alt="arm64">
</p>

---

## 📱 Screenshots

<p align="center">
  <img src="screenshots/dashboard-blue.png" width="320" alt="iPixel-Files Blue Theme Dashboard">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="screenshots/dashboard-lime.png" width="320" alt="iPixel-Files Lime Theme Dashboard">
</p>

<p align="center">
  <em>iPixel Blue (default) &nbsp;|&nbsp; iPixel Lime with customizable containers, storage telemetry, and quick actions.</em>
</p>

---

## ✨ Overview

**iPixel-Files** is an advanced native iOS file browser, app data manager, and container explorer designed and developed by **[iPixelDev](https://github.com/ipixeldev)**, based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**.

Powered by the `worse_query` sandbox technique, iPixel-Files reaches app data containers, shared app groups, extension containers, and daemons on **iOS 26 and iOS 27** without requiring a jailbreak or kernel exploits.

---

## 🚀 Key Features

### 🎨 Themes & Customization
- **Distinct Visual Themes**: Switch between **iPixel Blue** (default) and **iPixel Lime** with deep dark, light, or system appearance modes.
- **Nine Selectable App Icons**: Choose between Blue, Lime, Purple, Pink, Red, Orange, Gold, Teal, and Monochrome icons, or let the app automatically match your theme.
- **Dynamic Tab-Bar Editor**: Fully customize your navigation bar in **Settings → Appearance → Customize Tabs**. Add, remove, or reorder any destination (Home, Apps, Starred, Recents, Cache Cleaner, Go to Path, App Backups, Dual Browser, and Log).
- **Native System Search**: Uses Apple’s standalone search tab control on supported layouts, keeping search accessible without cluttering your home screen.

### 🌍 Localization & RTL
- **Full Arabic Support**: Complete Arabic localization (`ar.lproj`) with natural translations and Right-to-Left (RTL) interface flow.
- **Gesture Navigation**: Right-edge swipe-to-back gesture tailored for RTL layouts.
- **Intelligent Directionality**: File paths, bundle identifiers, hex dumps, and technical data remain consistently Left-to-Right (LTR) for optimal readability.

### 📂 Container & File Browser
- **Deep Container Access**:
  - **App Data** (`Containers/Data/Application`): View installed applications by display name and authentic icon rather than cryptic UUIDs.
  - **App Groups**: Inspect shared data directories across app suites.
  - **Extension Data & Internal Daemons**: Explore background services and widget containers.
  - **System Data & System Groups**: Access system container roots where supported (e.g., MobileGestalt cache, supervision profiles).
  - **Go to Path**: Jump directly to any absolute filesystem path.
- **Dual Browser**: Side-by-side two-pane browser on iPad; retained Left/Right state on iPhone with seamless parent folder navigation.
- **List & Grid Layouts**: View directories as detailed lists or clean two-column grids with media previews.
- **Sorting Options**: Sort by Name, Date, Size, or File Type in ascending or descending order.
- **Multi-File Batch Operations**: Select multiple files simultaneously to share, copy between containers, or delete with verified safety backups.
- **Starred & Recents**: Bookmark frequently visited directories and access recent files instantly.

### 🛠️ Built-in Tools & Editors
- **App Manager**:
  - View installed applications with storage size and authentic app icons retrieved directly via LaunchServices.
  - Copy bundle identifiers with one tap.
  - Backup **Documents & Library** containers as ZIP archives or share via AirDrop / Files.
  - Restore backups or clear ephemeral cache/tmp directories.
- **Cache Cleaner**:
  - Inspect per-app cache and temporary storage consumption.
  - Batch clean caches with filters for large caches (50 MB+).
  - View and prune system crash logs.
- **Property List (Plist) Editor**:
  - Native tree browser for dictionaries and arrays.
  - In-place editing of booleans, numbers, strings, dates, and binary data.
  - Preserves binary and XML formats automatically.
- **Hex Viewer & Editor**:
  - Paged hex browsing for files of any size.
  - Jump to offset, search byte sequences or ASCII strings, and patch bytes in place with visual modification tracking.
- **Media & Archive Handlers**:
  - High-performance image, video, and audio players with intuitive swipe-down dismissal.
  - Browse and unpack ZIP and TAR archives safely.
  - Read-only SQLite table viewer with automatic WAL/SHM sidecar redirection.
- **Diagnostic Activity Log**: Real-time auditing of file reads, writes, backups, token grants, and sandbox operations.

---

## 🛡️ Safety & Integrity

iPixel-Files is engineered with strict safeguards before modifying files:

1. **Pre-modification Backups**: Whenever a file is modified or removed, its contents are duplicated to internal **Backups** (also visible in the Files app). Backups can be restored to their original location at any time.
2. **Transactional Consistency**: App backups and restores verify source stability digests, destination shape digests, and content part hashes before and after execution.
3. **Directory Protection**: Only empty directories can be deleted in the file browser. Symbolic links are safely removed as links rather than following target paths.
4. **Advisory File Locking**: Protects against concurrent writes where supported.

---

## 📥 Installation

Download the latest `iPixel-Files.ipa` from **[Releases](https://github.com/ipixeldev/iPixel-Files/releases)**.

### Sideloading Requirements
Because the `worse_query` sandbox bypass relies on an **App Group** to negotiate access tokens, the IPA must be signed with an App Group entitlement (`group.app.ipixel.files` or any group supplied by your signer).

- **AltStore / SideStore**: Automatically manages and assigns an App Group during installation.
- **Sideloadly**: Retains entitlements and provisions an App Group with free or paid Apple IDs.
- **TrollStore** (iOS 15.0 – 17.0): Supports direct installation with full entitlements.
- **Custom Certificate / Developer Account**: Create an explicit App ID with the **App Groups** capability enabled, assign an App Group, and sign using your provisioning profile.

---

## 🔨 Building from Source

### Prerequisites
- macOS with Xcode (or Command Line Tools)
- Python 3

### Build Script
To run the full regression test suite, compile the arm64 binary, and package the signed IPA:

```bash
./build.sh
```

To specify a custom output destination:
```bash
WQFILES_FINAL_IPA="$PWD/iPixel-Files.ipa" ./build.sh
```

### GitHub Actions CI/CD
You can also build the IPA in the cloud without a local macOS setup:
1. Fork or push this repository to GitHub.
2. Navigate to **Actions → Build iPixel-Files IPA → Run workflow**.
3. Download the compiled `iPixel-Files-IPA` artifact from the completed run.

---

## 🧪 Testing

The test suite covers Foundation fixtures, access safety, traversal limits, SQLite redirects, and strict iOS arm64 clang syntax verification:

```bash
./tests/run_all_tests.sh
```

Set `WQ_SKIP_IOS_CHECK=1` to run only the host tests without an iOS SDK installed, or `WQ_ASAN=1` to test with AddressSanitizer.

---

## 🔍 Troubleshooting

- **Apps list is empty**:
  - The app uses LaunchServices first and falls back to an inode scan (`fsgetpath`). If an inode scan is required, the initial pass may take a minute. Check the in-app **Log** for `enumerate:` or `app scan:` entries.
- **`NO TOKEN`**:
  - `wq_grant` could not acquire a sandbox token. Confirm that your sideloading tool signed the app with an active App Group entitlement.
- **`(no label)`**:
  - A container was granted access, but its bundle identifier xattr or metadata plist was unreadable. The directory remains browsable, but backup and clear options are disabled until identity can be verified.

---

## 📜 Credits & License

- **iPixel-Files Design & Development**: **[iPixelDev](https://github.com/ipixeldev)**
- **Original Project**: **[WQFiles](https://github.com/kolbicz/WQFiles)** by **[kolbicz](https://github.com/kolbicz)**
- **Sandbox Technique**: **[worse_query](https://github.com/forcequitOS/worse_query)** by **Taj C (forcequit)**
- **Inode Enumeration**: **[KAMUI](https://github.com/murk-sus/kamui-escape)** by **murk-sus**
- **Typography**: [Press Start 2P](https://github.com/google/fonts/tree/main/ofl/pressstart2p) by CodeMan38 (SIL Open Font License 1.1)

Distributed under the **GNU General Public License v3.0 or later**. See [LICENSE](LICENSE) for full terms.
