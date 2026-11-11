# iPixel-Files 2.1

- Added Arabic localization and right-to-left layouts, including a right-edge Back gesture.
- Reorganized language, design, icon, appearance, and navigation controls into Settings.
- Apps now use lsd's LaunchServices container list first and retain the inode scan as a validated fallback.
- Fixed `/var` versus `/private/var` LaunchServices paths that could incorrectly produce an empty Apps screen.
- Improved installed-app icon detection, placeholder rejection, original-colour rendering, and diagnostics.
- Fixed live language switching, delayed alternate-icon changes, Tools disclosure scrolling, and Dual Browser parent navigation.
