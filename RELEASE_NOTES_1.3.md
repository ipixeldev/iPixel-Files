# iPixel-Files 1.3

## Usability and Pixel UI refinement

- Folder screens now distinguish **Loading**, **Loaded but empty**, **No search matches**, and **Cannot open** instead of presenting the same blank screen for every state.
- Added persistent **Starred** folders. Tap the navigation-bar star while inside a folder, or long-press a folder and choose Add to Starred. Saved locations are available from Home → Starred and can be removed with a swipe.
- Reworked Pixel typography around a small semantic type scale so headings, cards, tool rows, paths and supporting text have consistent visual hierarchy.
- Normalized Pixel dashboard card title/subtitle sizes and themed section headers and footers.
- Rejected transparent icon results from private UIKit icon lookup.
- Missing or unavailable app icons now receive stable colored fallback tiles instead of blank or dashed placeholders.
- Corrected folder-state update ordering so an access failure cannot be presented as an empty folder.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
