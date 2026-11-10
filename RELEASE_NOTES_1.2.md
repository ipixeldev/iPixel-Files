# iPixel-Files 1.2

## Multi-App-Group container access fix

- Fixed app names and app files appearing as **Unknown container**, **NO TOKEN**, or empty folders when a sideloading service gives iPixel-Files several generated App Groups.
- Token acquisition now tries every usable App Group entitlement instead of trusting the entitlement array's first entry.
- Each candidate token is verified against the requested container; the working App Group is remembered for the rest of the launch.
- Directory access verification now requires real enumeration. Merely opening a directory handle no longer creates a false success while its names and children remain sandbox-denied.
- When no entitled group works, repeated attempts are stopped after one complete probe so hundreds of containers do not each repeat the same expensive failure.
- Added concise diagnostic log entries showing which App Group and query mode succeeds or fails.

Designed and developed by **iPixelDev**. Based on [WQFiles](https://github.com/kolbicz/WQFiles) by **kolbicz**. Licensed under GPL-3.0-or-later.
