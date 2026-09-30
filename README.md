<p align="center">
  <img src="Resources/AppIcon.png" width="96" alt="Halo app icon" />
</p>

<h1 align="center">Halo</h1>

<p align="center"><strong>A little more Mac.</strong></p>

<p align="center">
  <a href="https://github.com/Mustafa-khann/Halo/releases/download/v1.3.0-beta.1/Halo-1.3.0.dmg">Download Halo</a>
  ·
  <a href="https://github.com/Mustafa-khann/Halo/releases/tag/v1.3.0-beta.1">What’s new</a>
</p>

Halo brings media, focus, files, and battery information to the space around your Mac’s camera notch. It opens with a hover, gives you room to do a little more, and settles back into the notch when you’re done.

Its frosted glass surface blurs the actual windows or wallpaper behind it. Quiet tabs, soft edges, and gentle feedback make every interaction feel at home on your Mac.

**Current release: 1.3.0 beta.** Requires macOS 14 or later. One app for Apple silicon and Intel, with a floating option for displays without a notch.

## Get started

1. Download the DMG and drag **Halo** into **Applications**.
2. Open Halo from Applications. It lives in the menu bar and around the notch.
3. To see what’s playing, open **Settings → Activities**, turn on **Media**, and leave **Playback source** set to **System Now Playing**.

The beta is ad hoc signed and **not notarized by Apple**. If macOS blocks the first launch, and you trust this download, try opening Halo once, then choose **System Settings → Privacy & Security → Open Anyway** for Halo. [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445) explains the process.

You don’t need developer tools or Python to use Halo.

<details>
<summary>Verify your download</summary>

Download the [SHA-256 checksum](https://github.com/Mustafa-khann/Halo/releases/download/v1.3.0-beta.1/Halo-1.3.0.dmg.sha256) and place it beside the DMG. In that folder, run:

```sh
shasum -a 256 -c Halo-1.3.0.dmg.sha256
```

</details>

## Keep the essentials close

**Now playing, right here.** Follow the player in your Mac’s Control Center. Music, Apple Podcasts, and videos from apps and browsers that publish Now Playing information appear automatically, with artwork and the name of the active app. Play, pause, skip, and scrub through supported media. Podcasts get 15-second controls; media without a duration keeps playback controls without a seek bar.

Adjust your Mac’s system volume from the same view. Outputs with hardware-only volume controls show the slider as unavailable. Only media shared with macOS Now Playing can appear in Halo; individual players decide which controls they support.

**A moment to focus.** Start with a 5, 15, 25, or 45-minute timer, or choose your own duration. Pause and resume as needed. Timers keep their place through sleep and app restarts, with sound and optional notifications when time is up.

**A place for your files.** Drop files or folders onto Halo, then drag them into another app, copy them, or reveal them in Finder. Select several items to share with the native AirDrop picker. Your shelf holds up to 20 items and is saved between launches. Removing an item leaves the original in place.

**A little more time.** Keep your Mac awake for 15 minutes, 30 minutes, an hour, two hours, or until you stop the session. You can keep the display awake too. Sessions end when Halo quits or your Mac sleeps. Closing the lid and choosing Sleep still work normally.

**Power, at a glance.** Check your battery level, charging state, and power source in the Battery tab. A brief indicator beside the notch lets you know when power connects or disconnects.

Home brings your focus timer, file shelf, and media shortcuts together. Open a tab when you want more room for an activity.

## Make it yours

- Hover over a tab to switch, or click anywhere within its padded area.
- Click the pin to keep Halo open. Press **Escape** or click outside it to close.
- Press **Control–Option–H** to open or close Halo. Choose another shortcut in Settings.
- Adjust the width, animation, and hover timing in **Settings → Appearance**.
- Choose your activities and launch-at-login preference in Settings.

Halo follows Reduce Motion when enabled in its settings. Reduce Transparency and increased contrast use an opaque surface for readability. Your current app keeps keyboard focus while you use the island.

## Your Mac. Your choice.

No account, subscription, or usage analytics. Media is off until you enable it. System Now Playing reads the active media session locally and does not need Automation permission. If you choose the direct Spotify or Apple Music source, macOS asks for Automation permission. Timer notifications are optional.

Halo doesn’t request Accessibility or Screen Recording access, record keystrokes, or upload your file shelf. File references stay on this Mac. System artwork comes from the media session. When using the direct Spotify source, artwork loads from the image URL supplied by Spotify.

## For developers

<details>
<summary>Build, test, and package Halo</summary>

Install Apple’s command-line developer tools with a Swift 6 or later compiler. The app uses SwiftUI, AppKit, and native macOS services.

To build for your current Mac:

```sh
scripts/build.sh debug
open dist/Halo.app
```

To run the tests and create a universal release:

```sh
scripts/test.sh
scripts/build.sh release
scripts/package-dmg.sh
```

The output is `dist/Halo.app`, `dist/Halo-1.3.0.dmg`, and its `.sha256` file. The DMG includes a drag-to-Applications layout.

Packaging requires Python 3.11 or later. The script installs pinned packaging tools in `.build/dmg-tools`; they are not included in the app. Set `HALO_PYTHON` to use a different Python executable.

The 20 core tests cover timers and saved state, display geometry, media progress and playback speed, system metadata updates and source changes, live media, malformed and partial stream records, preference migration, file shelf limits and drops, preserving original files, and Keep awake deadlines.

### Project layout

- `Sources/Halo` — the app, activity services, native overlay, and settings.
- `Tests/HaloTests` — core behavior tests.
- `Resources` — app artwork, bundle information, and entitlements.
- `scripts` — builds, tests, installer artwork, packaging, and notarization.
- `ThirdParty/MediaRemoteAdapter` — pinned BSD-licensed source for the system media helper.

`AppModel` connects preferences and services to the interface. `OverlayController` handles display placement, pointer routing, and shortcuts. `HaloDesign` and `HaloBackground` define the shared controls and native backdrop material. Media, system volume, file shelf, and Keep awake have separate services.

System Now Playing uses the private macOS MediaRemote interface through the bundled [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter) framework and the system Perl interpreter. Its source is pinned and built for both architectures; the launcher and BSD license ship inside Halo. No runtime download or package installation is needed. Apple may change this interface in a future macOS release. If it becomes unavailable, choose the direct Spotify or Apple Music source in Activities. This beta is distributed outside the Mac App Store. See [third-party provenance](ThirdParty/MediaRemoteAdapter/PROVENANCE.md).

</details>

<details>
<summary>Sign and notarize a release</summary>

Without a signing identity, the build uses ad hoc signing. For a notarized release, use an appropriate bundle identifier, a Developer ID Application certificate, and a notarization profile saved in Keychain. Keep certificates and credentials out of the repository.

```sh
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='halo-notary'
scripts/notarize.sh
```

The script rebuilds both architectures, signs the app and DMG, submits the DMG for notarization, staples and validates the ticket, checks Gatekeeper assessment, and updates the checksum. Building does not publish a release automatically.

Before publishing, check Control Center source switching, Podcasts, supported browser videos, seeking, and direct player fallbacks; file drops, dragging, and AirDrop; Keep awake expiry and stopping; timers across sleep and relaunch; Spaces, Stage Manager, and full-screen apps; display scaling and external monitors; VoiceOver; and a clean installation on Apple silicon and Intel Macs. A successful Intel build does not replace testing on Intel hardware.

</details>
