# iPixel-Files 1.7

## Stable playback and smoother folders

- Replaced the unsupported `AVPlayerViewController` subclass with a normal container that embeds an untouched native player controller.
- Pause, play, seek and other native audio/video controls no longer share an overridden player lifecycle that could terminate the app.
- Preserved full-screen playback, swipe-down dismissal, audio artwork, and a single set of close/share controls.
- Added table prefetching so thumbnails begin loading shortly before their rows scroll on-screen.
- Added an `AVAssetImageGenerator` fallback when Quick Look cannot produce a video thumbnail.
- Coalesced thumbnail updates instead of reloading each row independently.
- Deferred initial folder-content refreshes until the navigation transition is complete, fixing the brief overlapping labels seen when entering media-heavy subfolders.

The first preview for some video codecs can still require frame decoding, but a type-specific placeholder remains visible and subsequent visits use the in-memory cache.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
