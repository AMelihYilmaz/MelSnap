# MelSnap 0.5

MelSnap is an open-source macOS app for finding screenshots by the text inside
them. Apple Vision recognizes text on your Mac. Search text, image paths, file dates, and word positions are saved locally in ~/Library/Application Support/MelSnap/index.json. The last folder and cached results are restored on launch; new and changed images are reindexed. Use Folder → Clear Saved Search Data to delete the saved index and stop watching. No image pixels are stored in the index.

## Use MelSnap

Download the Apple Silicon ZIP from release **v0.5**, unzip it, and open
**MelSnap 0.5.app**. Choose the folder where your screenshots are saved,
then search for a word or phrase. While MelSnap is open, new and changed screenshots are indexed automatically.

Filter by **Today**, **Last 7 Days**, or **All Dates**. MelSnap uses the file creation date, falling back to its modification date. In the preview, use the arrow buttons or arrow keys to cycle through matches.

The release app is ad-hoc signed and has not been notarized by Apple.

## Build from source

On macOS with Xcode Command Line Tools installed, run `./build.sh`.

In the image preview, use the zoom slider (100–800%) or Fit. Selecting another highlighted match scrolls it into view.

See the [changelog](CHANGELOG.md) and [MIT license](LICENSE).
