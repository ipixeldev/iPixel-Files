# iPixel-Files 2.0

- Added a complete Arabic interface with natural, concise wording and right-to-left layouts. Paths, bundle IDs, and other technical values remain left-to-right for readability.
- Replaced the theme shortcut with an organized Settings screen for language, design, app icon, appearance, and navigation preferences.
- Fixed the Tools disclosure so collapsing it keeps the current scroll position.
- Dual Browser panes can now move to parent folders and navigate freely instead of remaining inside their starting roots.

## Your file manager, your tab bar

- Added a complete tab-bar editor under **Appearance → Customize Tabs**. Every destination can be active or inactive, including Apps, Starred, Recents, Cache Cleaner, Go to Path, App Backups, Backups, Log, Dual Browser and Search.
- Active tabs have remove controls and drag handles. Inactive tabs have add controls. Every change updates the visible tab bar immediately without resetting existing navigation stacks.
- Search now uses Apple’s system Search tab and appears as the separate trailing control on supported compact layouts.
- Home automatically hides only the tool rows currently present in the tab bar, keeping the dashboard short without making inactive tools disappear.
- Restored theme-linked automatic app-icon switching and added an explicit icon selector with Blue, Lime, Purple, Pink, Red, Orange, Gold, Teal and Monochrome options.
- Improved installed-app icon discovery through guarded UIKit, LaunchServices and loose bundle-icon paths. If an icon is unavailable, Apps now shows an honest neutral app glyph instead of guessing the wrong app type.
- Added **Copy Bundle ID** to the Apps action menu.
- Fixed compact Search visibility, tab-reorder row placement and equalized tab-item layout. The Home Tools list can now collapse, and dashboard/disclosure transitions include subtle Reduce Motion-aware animation.
- Added guarded CoreUI decoding for third-party icons stored only in an app’s compiled `Assets.car` catalog.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
