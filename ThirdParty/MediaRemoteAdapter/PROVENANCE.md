# MediaRemote Adapter

Source: https://github.com/ungive/mediaremote-adapter
Revision: `29718252613a5b0e210bdc64de0bd944ab379706`
License: BSD 3-Clause. See [LICENSE](LICENSE).

The vendored source is unchanged. Halo builds the framework with its own
`scripts/build-media-helper.sh` and bundles the Perl launcher and license.
The test publisher is source only and is not included in Halo.
Halo adds a separate parent-process watchdog from `Resources/MediaHelperParentMonitor.m`
so the helper exits if the app crashes. No upstream files are modified.

The adapter uses the private macOS MediaRemote interface through the system
Perl interpreter. This interface may change in future macOS releases. It
requires no Accessibility or Screen Recording permission. The app retains
optional direct Spotify and Apple Music integrations when needed.
