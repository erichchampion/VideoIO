# VideoIO

![](https://github.com/MetalPetal/VideoIO/workflows/Swift/badge.svg)

Video Input/Output Utilities

## Requirements

- iOS 18.0+ / macOS 10.13+ / tvOS 12.0+
- Xcode 15.0+ (Swift 6.0+)
- Swift Package Manager

## Building with Xcode

### Opening the Package

1. Clone the repository:
   ```bash
   git clone git@github.com:erichchampion/VideoIO.git
   cd VideoIO
   ```

2. Open the package in Xcode:
   ```bash
   open Package.swift
   ```
   Or open Xcode and select `File > Open` and navigate to the `Package.swift` file.

### Building

1. Select a scheme:
   - Choose `VideoIO` from the scheme menu (or `VideoIO-Package` depending on Xcode version)
   - Select your target platform (iOS, macOS, or tvOS) from the destination menu

2. Build the package:
   - Press `Cmd + B` or select `Product > Build`
   - Alternatively, build from the command line:
     ```bash
     swift build
     ```

### Running Tests

1. Select the test scheme:
   - Choose `VideoIOTests` from the scheme menu
   - Ensure a simulator/device is selected for iOS/tvOS, or your Mac for macOS

2. Run tests:
   - Press `Cmd + U` or select `Product > Test`
   - Or from the command line:
     ```bash
     swift test
     ```

3. View test results:
   - Open the Test Navigator (`Cmd + 6`) to see all tests
   - Check the test report in the Report Navigator (`Cmd + 9`)

### Using VideoIO in Your Project

#### Swift Package Manager

Add VideoIO to your project:

1. In Xcode, select your project
2. Go to the `Package Dependencies` tab
3. Click the `+` button
4. Enter the repository URL:
   ```
   https://github.com/erichchampion/VideoIO.git
   ```
5. Choose the version or branch you want to use
6. Click `Add Package`

#### Manual Integration

If adding as a local package:

1. In Xcode, select your project
2. Go to the `Package Dependencies` tab
3. Click the `+` button
4. Click `Add Local...`
5. Navigate to the VideoIO directory
6. Click `Add Package`

## Releasing

### Versioning

1. Update the version in `Package.swift` if needed (the package uses semantic versioning)

2. Create a git tag for the release:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

### Publishing to Your Fork

1. Ensure all changes are committed:
   ```bash
   git status
   git add .
   git commit -m "Your commit message"
   ```

2. Push to your fork:
   ```bash
   git push origin main
   ```
   (Replace `main` with your branch name if different)

3. Create a GitHub release (optional):
   - Go to your repository on GitHub: `https://github.com/erichchampion/VideoIO`
   - Click `Releases` → `Draft a new release`
   - Select the tag you created
   - Add release notes
   - Click `Publish release`

### Verifying the Release

Test that the package can be imported:

```bash
swift package resolve
swift build
swift test
```

Or create a test project in Xcode that depends on your released version to ensure everything works correctly.

## VideoComposition

Wraps around `AVMutableVideoComposition` with custom video compositor. A `BlockBasedVideoCompositor` is provided for convenience.

With [MetalPetal](https://github.com/MetalPetal/MetalPetal)

```Swift
let context = try! MTIContext(device: MTLCreateSystemDefaultDevice()!)
let handler = MTIAsyncVideoCompositionRequestHandler(context: context, tracks: asset.tracks(withMediaType: .video)) {   request in
    return FilterGraph.makeImage { output in
        request.anySourceImage => filterA => filterB => output
    }!
}
let composition = VideoComposition(propertiesOf: asset, compositionRequestHandler: handler.handle(request:))
let playerItem = AVPlayerItem(asset: asset)
playerItem.videoComposition = composition.makeAVVideoComposition()
player.replaceCurrentItem(with: playerItem)
player.play()
```

Without MetalPetal

```Swift
let composition = VideoComposition(propertiesOf: asset, compositionRequestHandler: { request in
    //Process video frame
})
let playerItem = AVPlayerItem(asset: asset)
playerItem.videoComposition = composition.makeAVVideoComposition()
player.replaceCurrentItem(with: playerItem)
player.play()
```

## AssetExportSession

Export `AVAsset`s. With the ability to customize video/audio settings as well as `pause` / `resume`.

```Swift
var configuration = AssetExportSession.Configuration(fileType: .mp4, videoSettings: .h264(videoSize: videoComposition.renderSize), audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 128 * 1000))
configuration.metadata = ...
configuration.videoComposition = ...
configuration.audioMix = ...
self.exporter = try! AssetExportSession(asset: asset, outputURL: outputURL, configuration: configuration)
exporter.export(progress: { p in
    
}, completion: { error in
    //Done
})
```

## PlayerVideoOutput

Output video buffers from `AVPlayer`.

```Swift
let player: AVPlayer = ...
let playerOutput = PlayerVideoOutput(player: player) { videoFrame in
    //Got video frame
}
player.play()
```

## MovieRecorder

Record video and audio.

## AudioQueueCaptureSession

Capture audio using `AudioQueue`.

## Camera

Simple audio/video capture.

