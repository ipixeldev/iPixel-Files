# iPixel-Files 1.5

## Media previews and native dismissal

- Added asynchronous image and video thumbnails to file rows using the system Quick Look thumbnail generator.
- Added persistent **List** and two-column **Grid** choices directly in the Sort and View menu; Grid uses larger icons and thumbnails while retaining tap and long-press actions.
- Thumbnail generation runs outside the main thread, is cached, and never blocks folder scrolling.
- Video and audio now open in a dedicated full-screen player instead of being pushed onto the folder navigation stack.
- Swipe downward to dismiss the player, with distance and velocity thresholds that prevent small accidental drags from closing it.
- Added persistent 44-point close and share controls so playback is always easy to exit or export.
- Kept unsupported or inaccessible files usable with their existing document icons when a preview cannot be generated.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
