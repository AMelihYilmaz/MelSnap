# Changelog

## v0.4

- Filter screenshots by Today, Last 7 Days, or All Dates.
- Cycle through highlighted matches with arrow buttons or arrow keys.

## v0.3

### Added
- Add a folder menu with Choose Folder, Open in Finder, and Rescan Folder.
- Add Command-O for folder selection and a custom MelSnap app icon.

### Improved
- Start refreshing on macOS file notifications instead of a two-second polling interval.
- Ship an English interface, README, and versioned Apple Silicon download.

## v0.2

### Added
- Show thumbnails in search results and open a larger preview with yellow match highlights.
- Press Command-F to focus search.
- Watch the selected folder using a two-second refresh interval.

### Improved
- Reuse OCR results for unchanged files, remove deleted files, and index new or edited images.
- Use fast OCR and process up to three images concurrently.

## v0.1

### Added
- Choose a folder and search text inside screenshots with on-device Apple Vision OCR.
- Open results in the default image viewer or reveal their files in Finder.
- Keep the search index in memory while the app is open.
