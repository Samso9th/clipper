# Clipper

Standalone native SwiftUI app for iPhone and Apple silicon Mac. Import a spoken recording, transcribe with Voz, select highlights with Clips, then export individual clips or a reel. Both models come from Desert Ant Core.

## Install (Mac)

Download `Clipper-<version>.dmg` from [Releases](../../releases), open it, and drag **Clipper** onto **Applications**. Needs an Apple silicon Mac on macOS 15 or later.

The app is not notarized, so the first launch is blocked with "Apple could not verify Clipper". Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or, in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Clipper.app
```

The first run downloads the transcription and highlight models (about 740 MB). After that it works offline. A two-hour podcast in H.264 MP4 takes under a minute on an M2 Pro.

## Tide interface

The interface is native: a sea-green workspace, featured recording or selected moment, selectable highlight cards, and a floating Recording / Moments / Transcript dock. The layout uses two columns on wider windows and stacks on iPhone or at accessibility text sizes.

Controls use native Liquid Glass on iOS 26 / macOS 26. Older supported versions use material and bordered-button fallbacks. Light/dark appearance, Reduce Transparency, and Reduce Motion follow the system settings. Recordings and generated results are real; the HTML demo's sample media and fictional highlights are not bundled with the app.

## Run

Open `Clipper.xcodeproj` in Xcode 26 or later. Select the **Clipper** scheme and **My Mac**, or your connected iPhone. For iPhone, choose your signing team and a unique bundle identifier in Signing & Capabilities.

To build the Mac app from the terminal:

```sh
cd clipper
./scripts/build-mac-app.sh
open .build/Clipper.app
```

Xcode must be installed (it need not be selected with `xcode-select`): the macOS 27 SDK implements SwiftUI's `@State` as a macro whose plugin ships only with Xcode. The script uses `/Applications/Xcode.app` automatically.

## Distributable DMG

```sh
./scripts/build-dmg.sh        # -> .build/Clipper-<version>.dmg
```

The app embeds the FFmpeg frameworks, so it runs on Macs without this build tree. It is ad-hoc signed, not notarized. On first launch, recipients see "Apple could not verify Clipper"; they open it from **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Clipper.app`. Notarizing requires a paid Apple Developer ID. Recipients need Apple silicon and macOS 15+, and the first run downloads the models (about 740 MB).

## YouTube downloads

MKV and WebM are converted with the embedded FFmpeg. H.264/HEVC video is repackaged and VP9 is re-encoded. **AV1 cannot be decoded on M1/M2 Macs** (no software decoder in this FFmpeg build, no hardware decoder on those chips), so those recordings import as audio only and clips export as M4A. For video clips, download H.264:

```sh
yt-dlp -f "bv*[vcodec^=avc1][height<=1080]+ba[ext=m4a]" --merge-output-format mp4 <url>
```

Requires macOS 15+ or iOS 18+. The full recording workflow targets Apple silicon. A physical device is the reference environment for Neural Engine inference.

## Build and tests

```sh
swift build
./scripts/test.sh
```

Tests exercise transcript boundaries, timestamp safety, and real audio export without downloading model weights. The test script also locates Swift Testing when only Command Line Tools are installed; with full Xcode, plain `swift test` works. `Package.resolved` records the verified SDK version, 3.1.0.

## Independent project

Everything needed to build this app lives in this directory. `ClipperKit` is an internal library target in this app's package, not a separately deployed service.


## Processing

- Recording mode uses Voz for timed words, Transcript for sentence boundaries, Clips for selection, and AVFoundation for local cuts.
- Transcript mode needs only Clips. Its results can be shared as text; estimated durations are never used as media timestamps.
- Export keeps source framing and orientation. Video is MOV; audio is M4A. Reels concatenate selected clips in ranking order.
- Models download on first use. **Prepare for offline use** downloads and loads the models needed by the selected mode.
- Media imports and exports are temporary local files. Save or share exports before replacing the recording or quitting. There is no persistent project library or automatic cloud sync.
- The SDK makes usage-metadata requests when connected. The recording and transcript are processed locally.

API references: [SDK README](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/v3.1.0/README.md), [Clips](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/v3.1.0/docs/models/clips.md), [Voz](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/v3.1.0/docs/models/voz.md).

## Licenses

Clipper's own source code is under the [MIT License](LICENSE). The dependencies keep their own licenses:

- **Clips and Voz models and the desert-ant-core SDK**, by [Desert Ant Labs](https://desertant.com): [Desert Ant Labs Source-Available License 1.0](https://license.desertant.com/1.0). This is not an open-source license. It is free below 100,000 monthly active devices per platform for each model, needs a commercial license above that, forbids using the models or their outputs to train a competing on-device model, and requires in-app credit (shown in the app's About sheet).
- **FFmpeg**, via [ffmpeg-kit](https://github.com/jaywcjlove/ffmpeg-kit): the bundled build is configured with `--enable-gpl --enable-version3 --enable-libx264`, so the FFmpeg frameworks in the DMG are under the GPL v3.
