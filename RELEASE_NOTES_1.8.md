# iPixel-Files 1.8

## Safer gestures, recents and deeper inspection

- Removed the redundant media close button. Audio and video dismiss with a downward swipe, while Share now occupies the unobstructed top-left control position.
- Added a dedicated full-screen image viewer with zoom, tap-to-hide controls, Share, and swipe-down dismissal.
- Made row gestures safer: right-to-left is the only destructive swipe; left-to-right shares and cannot collide with the navigation-back gesture.
- Added Recent Folders and Viewed Files to Home, with individual removal and a Clear All action that never deletes files.
- Added bounded cross-location search across accessible recently visited, starred and backup folder trees.
- Folder Info now measures recursive size and clearly reports partial results when some contents are inaccessible.
- Opening a SQLite `-wal` or `-shm` file now finds and opens its matching main database, or explains when that database is unavailable.
- Added regression checks for the new gesture, viewer, history, search, measurement and database behavior.

Global search can only traverse locations the app can access; it cannot turn an undiscovered or denied container into a readable one. SQLite sidecars are transaction companions rather than standalone databases, so the viewer remains read-only and opens the main file.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
