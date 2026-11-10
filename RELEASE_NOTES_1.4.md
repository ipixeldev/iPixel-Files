# iPixel-Files 1.4

## Rich file viewers and aligned cards

- Added native video and audio playback for MP4, MOV, M4V, MP3, M4A, AAC, WAV, CAF and AIFF files.
- Corrected automatic detection that previously sent MP4/MOV files to the hex viewer.
- Existing image viewing, UTF-8 text editing, property-list editing and editable hex viewing are now joined by explicit **Open As** actions for every supported viewer.
- Added archive browsing and safe extraction for formats supported by the system archive library, including ZIP and TAR-family archives.
- Archive extraction rejects absolute paths, `..` traversal, symbolic links, unsupported entries, excessive entry counts and oversized expansion. Existing destination folders are never silently overwritten.
- Added a read-only SQLite browser showing tables/views and up to 200 rows per table, with blobs represented by size rather than loaded into the UI.
- Rebuilt container cards with leading icons and a shared text axis, fixing the centered-icon/left-aligned-text mismatch.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
