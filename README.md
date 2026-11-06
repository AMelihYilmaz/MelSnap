# MelSnap 0.4

MelSnap is an open-source macOS app for finding screenshots by the text inside
them. Apple Vision recognizes text on your Mac. Search data stays in memory.

## Use MelSnap

Download the Apple Silicon ZIP from release **v0.4**, unzip it, and open
**MelSnap 0.4.app**. Choose the folder where your screenshots are saved,
then search for a word or phrase. While MelSnap is open, new and changed screenshots are indexed automatically.

Filter by **Today**, **Last 7 Days**, or **All Dates**. MelSnap uses the file creation date, falling back to its modification date. In the preview, use the arrow buttons or arrow keys to cycle through matches.

The release app is ad-hoc signed and has not been notarized by Apple.

## Build from source

On macOS with Xcode Command Line Tools installed, run `./build.sh`.

See the [changelog](CHANGELOG.md) and [MIT license](LICENSE).
