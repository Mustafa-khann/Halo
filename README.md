# Halo

A native macOS companion that makes the camera notch a little more useful. Halo blends into the notch at rest, opens with a short spring animation, and keeps your music, files, battery, and focus within reach.

![Halo on a MacBook](docs/halo-notch.png)

## Download and install

[Download the Halo beta DMG](https://github.com/Mustafa-khann/Halo/releases/download/v1.2.2-beta.1/Halo-1.2.2.dmg) · [Release notes and checksum](https://github.com/Mustafa-khann/Halo/releases/tag/v1.2.2-beta.1)

1. Open the downloaded DMG and drag **Halo** into **Applications**.
2. Launch **Halo** from Applications. It appears in the menu bar and around the camera notch.
3. Open Settings → Activities to connect Spotify or Apple Music. Volume controls the Mac's system output.

The beta is ad hoc signed and **not notarized by Apple**. macOS may block its first launch because the developer cannot be verified. If you trust this release, after attempting to launch it, use **System Settings → Privacy & Security → Open Anyway** for Halo. See [Apple's instructions for opening an unnotarized app](https://support.apple.com/102445).

Halo supports **macOS 14 or later**, with one universal app for **Apple silicon and Intel**. No developer tools or Python are needed to run the installed app.

To verify the download, place the DMG and its `.sha256` file in the same folder and run:

```sh
shasum -a 256 -c Halo-1.2.2.dmg.sha256
```

## Features

- Spotify and Apple Music track information, playback controls, and draggable seeking, with optional Automation access.
- Mac system output volume, synchronized with volume keys and changes to the selected audio output. Outputs with hardware-only volume controls show the slider as unavailable.
- Live battery percentage, charging state, and a brief indicator when power is connected or disconnected.
- Focus timers with presets, custom durations, pause/resume, sound, optional notifications, and saved deadlines that survive sleep and relaunch.
- A local file shelf: drop files onto Halo, drag individual files into other apps, select several files for AirDrop or copying, open them, or reveal them in Finder. File references survive relaunch, with duplicate detection and a 20-file limit. Removing an item never deletes the original.
- Keep awake for 15 minutes, 30 minutes, an hour, two hours, or until stopped. Optionally keep the display awake too. Timed sessions use macOS-managed timeouts, and all sessions end on quit or system sleep. Manual sleep and lid-close sleep still work normally.
- A nonactivating panel, configurable Control–Option–H shortcut, Escape dismissal, pinning, and delayed hover expansion.
- A frosted glass interface that blurs the actual app windows or wallpaper behind Halo, with SF typography, softly rounded cards, larger music artwork, a focus progress ring, and consistent controls. The camera area stays black; Reduce Transparency and increased contrast use an opaque background. Tabs switch on hover across their full padded area, with a gently moving selection highlight. Battery details live in the Battery tab.
- Native settings, system appearance, Reduce Motion support, launch at login, and a floating fallback for displays without a notch.

Halo requires macOS Sonoma 14 or later. The release bundle includes Apple silicon and Intel binaries. It lives in the menu bar rather than the Dock.

Music is disconnected by default. Connect it in Settings → Activities. macOS asks for Automation permission when Halo first communicates with the selected running player. Halo does not request Accessibility or Screen Recording access, capture keystrokes, or collect analytics. Spotify artwork loads from the artwork URL supplied by Spotify.

## Files and Keep awake

Drag a file or folder from Finder toward the notch and briefly pause while Halo opens, then drop it onto Halo. You can also use **Files → Choose files**. Click file cards to select them; actions apply to every file when none are selected. Drag a card into another app, or right-click it to open, reveal, copy, or remove its reference. **AirDrop** opens the native macOS recipient picker. File references are stored only on this Mac; Halo does not upload files automatically or duplicate their contents. Moved or unavailable files can be removed from the shelf without touching the originals.

Open **Awake**, choose a duration, decide whether the display should stay awake, and select **Keep awake**. An active session appears beside the collapsed notch. **Stop keeping awake** immediately restores normal idle sleep. Sessions do not resume automatically after quitting Halo or sleeping your Mac. Both activities can be hidden in **Settings → Activities**; disabling Keep awake also stops its current session.

## Build and run

Install Apple's command-line developer tools with a Swift 6 or later compiler. No third-party runtime is required by the app.

```sh
scripts/build.sh debug
open dist/Halo.app
```

The debug build targets the current Mac. A release build creates a universal application:

```sh
scripts/test.sh
scripts/build.sh release
scripts/package-dmg.sh
```

The installer script uses Python 3.11 or later and installs its pinned packaging dependencies in `.build/dmg-tools`. Set `HALO_PYTHON` if your Python executable has another name. These dependencies generate the Finder layout and are not shipped or needed by Halo itself.

Outputs are `dist/Halo.app`, `dist/Halo-1.2.2.dmg`, and a SHA-256 checksum. The disk image has a drag-to-Applications layout and custom artwork.

## Signing a notarized release

Without a signing identity, builds are ad hoc signed. That verifies bundle integrity but is not Developer ID signing or Apple notarization. The downloadable beta uses this signing mode.

For a notarized release, use a stable bundle identifier belonging to your project in `Resources/Info.plist`, an Apple Developer ID Application certificate, and Apple's `notarytool` and `stapler`. Store notarization credentials in Keychain with `notarytool store-credentials`; never put them in this repository.

```sh
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='halo-notary'
scripts/notarize.sh
```

The release script rebuilds and signs both architectures, signs the disk image, submits it for notarization, staples the ticket, checks Gatekeeper assessment, and updates the checksum. No release is uploaded automatically by a normal build.

For a release candidate, manually check music controls with each connected player; Finder-to-notch drops and dragging shelf files into other apps; AirDrop transfers; Keep awake expiry, stopping, and lid-close behavior; Spaces, Stage Manager, full-screen apps, and an auto-hidden menu bar; display scaling, external monitors, and clamshell mode; sleep/wake and timer completion; VoiceOver; and a clean installation on supported Intel and Apple silicon Macs. The 13 core tests cover timer deadlines, persistence, notch coordinates, media progress, preference migration, shelf capacity and duplicates, preserving original files, file-provider drops, and Keep awake deadlines. Architecture compilation does not substitute for testing on an Intel Mac.

## Structure

`AppModel` owns persisted preferences and activity state. `PowerService` uses IOKit notifications. `SystemVolumeService` uses Core Audio output-device volume and mute controls, with property listeners for live updates. `MediaService` communicates with each player's published scripting interface on a background queue. `FileShelfService` stores file references and manages native file picking, drop providers, and AirDrop. `KeepAwakeService` manages public IOKit power assertions and their lifetimes. `OverlayController` owns display geometry, mouse and drag routing, and public Carbon hotkeys. `HaloDesign` defines shared spacing, colors, accessible motion, and control styles. `HaloBackground` uses a masked native behind-window material, a neutral readability wash, a black camera area, and an opaque accessibility fallback. Its colors come from the live content behind Halo; it does not capture the screen or load the wallpaper file. `HaloView` and `UtilityViews` draw the notch and activity controls; `SettingsView` provides native configuration. Additional activities can be added as independent services and views in later releases.
