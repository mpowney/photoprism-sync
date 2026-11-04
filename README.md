# PhotoPrism Sync

A simple SwiftUI iPhone app for syncing media between the iOS Photos library and a PhotoPrism instance.

## Included in this repository

- `PhotoPrismSync.xcodeproj` – Xcode project for the iOS app
- `PhotoPrismSync/` – SwiftUI app code, services, and view models
- `Sources/PhotoPrismSyncCore/` – shared filtering, duplicate detection, and calculation models
- `Tests/PhotoPrismSyncCoreTests/` – focused tests for shared criteria evaluation logic

## Features

- Sign in to a PhotoPrism instance with URL, username, and password
- Choose Upload, Download, or Delete flows from the main screen
- Filter by age range using days, weeks, months, or years
- Include or exclude photos, Live Photos, and videos
- Avoid duplicates by filename and/or photo timestamp
- Calculate matching item count and total size before executing
- Keep a calculated reference list so only reviewed items are processed
- Preview matching local or PhotoPrism assets before executing
- Load PhotoPrism preview images directly from the server with an ephemeral no-cache session
- Upload original iOS asset resources, then trigger PhotoPrism import processing
- Download PhotoPrism originals back into the iOS photo library
- Delete local photos either when they already exist in PhotoPrism or when they are older than the selected age rule

## PhotoPrism API assumptions

The app uses the current PhotoPrism API flow:

- `POST /api/v1/session` for sign-in
- `GET /api/v1/photos?merged=true` for remote calculations
- `GET /api/v1/dl/{hash}?t={downloadToken}` for original downloads
- `POST /api/v1/users/{uid}/upload/{token}` to stage uploads
- `PUT /api/v1/users/{uid}/upload/{token}` to process staged uploads

Preview and download tokens are refreshed from PhotoPrism response headers while paging through results.

## Open and run

1. Open `PhotoPrismSync.xcodeproj` in Xcode on macOS.
2. Select an iPhone simulator or physical iPhone.
3. Set your Apple development team if code signing is required.
4. Build and run the `PhotoPrismSync` target.
5. On first launch, grant Photos access.
6. Open **Settings** in the app and enter your PhotoPrism URL and credentials.

## Validation completed here

- `swift test`

The shared sync core is validated in this environment. The iOS app target itself must be built in Xcode on macOS because UIKit, Photos, and SwiftUI are not available in this Linux runner.

## Implementation notes

- Credentials are stored with `UserDefaults` for server URL and username, and the iOS Keychain for password.
- Local previews use `PHCachingImageManager`.
- Remote previews are loaded directly from the PhotoPrism instance without persistent caching.
- Upload export uses original `PHAssetResource` files to preserve metadata as closely as iOS allows.
- Download import restores the original filename and creation date when saving assets back to Photos.
