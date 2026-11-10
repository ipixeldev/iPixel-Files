# iPixel-Files

A native UIKit redesign of [WQFiles](https://github.com/kolbicz/WQFiles), developed by **iPixelDev**, with a charcoal dashboard, lime accents, pastel container cards, device storage, and a descriptive toolkit. The original container browser, app manager, cache cleaner, backups, text/plist/hex editors, sharing, and activity log remain connected to their native implementations.

## Complete interface themes

**iPixel Blue** is the default design. Open the paint-palette button on the dashboard to switch between **iPixel Blue** and **iPixel Lime**. Each visual system applies to the dashboard and every nested screen, including location cards, file and app lists, cache tools, search, property-list and hex editors, logs, toolbars, progress states and menus. Appearance can follow the iPhone or be fixed to Light or Dark. All palettes use semantic light/dark colors rather than hard-coded white text or dark surfaces.

Launch uses a text-free animated stack of folders. Long scans use the same visual language with real percentage/fraction progress when the backend reports it, and a subtle indeterminate animation otherwise.

The app icon is original pixel artwork for iPixel-Files: a layered blue folder, data block and lime accent. The 1024 px master and all required iPhone/iPad renditions are included under `icons/`.

## Build an IPA without owning a Mac

Upload this source tree to your own GitHub repository, including `.github/workflows/build-ipixel.yml`. Open **Actions → Build iPixel-Files IPA → Run workflow**. The workflow uses a hosted macOS runner, runs the upstream regression suite, builds the app, and uploads **iPixel-Files-IPA**. Download and extract that artifact to obtain `iPixel-Files.ipa`.

The workflow has been prepared but has not been run in this session. Hosted runner availability, installed Xcode version, and GitHub Actions usage limits apply.

The IPA is ad-hoc signed for re-signing, not ready for direct installation. Sideload using a signer that provisions and preserves an App Group, such as AltStore, SideStore, or Sideloadly. The app uses the group supplied by the signer. iOS 26.0 or later is required; System Data and System Groups remain available only where supported by upstream.

## Build on a Mac

With full Xcode selected:

```sh
WQFILES_FINAL_IPA="$PWD/iPixel-Files.ipa" ./build.sh
```

The internal executable remains `WQFiles` to retain the existing validated packaging pipeline. The display name is **iPixel-Files** and the bundle identifier is `app.ipixel.files`, with App Group `group.app.ipixel.files`.

## Linux / xtool

The official Linux xtool release was downloaded and executed during development. `xtool sdk status` returned **Not installed**. Its SDK installer requires `Xcode.xip`, `Xcode.app`, or an existing `darwin.xtoolsdk`. This environment contains none of those and also lacks Swift and Clang. Installing xtool alone does not supply Apple's SDK or produce an IPA. The existing project uses an Objective-C shell build rather than a SwiftPM xtool project; a Linux build would additionally need the matching compiler/linker and a packaging/signing adaptation.

## Validation status

The static browser regression checks, Python release policy tests, and catalog updater fixtures run on Linux. Native Objective-C compilation, UIKit rendering, host Foundation fixtures, and signing require the SDK-equipped build above. No iPhone runtime testing or compiled IPA is claimed by this source handoff.

## Credits and license

**iPixel-Files** is developed by **iPixelDev** and based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. The worse_query technique is by **Taj C / forcequit**; enumeration credits include **murk-sus / KAMUI**. The original license and source are included under **GPL-3.0-or-later**. See `LICENSE` and the upstream `README.md` for operation and safety details. The original `source.json` is upstream release metadata, not an iPixel update feed.
