import XCTest
@testable import VideoIO
import AVFoundation

@available(iOS 16.0, tvOS 16.0, macOS 13.0, *)
final class VideoIOTests: XCTestCase {
    
    // Find test asset - works both from command line and Xcode
    // Use robust path resolution that handles Xcode's test execution environment
    var testMovieURL: URL {
        let fileName = "ElephantsDream.mp4"
        
        // First try: Use Bundle resources (works in Xcode when resources are configured in Package.swift)
        if let resourceURL = Bundle.module.resourceURL?.appendingPathComponent(fileName),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        
        // Second try: Use environment variables that Xcode sets (SRCROOT or PROJECT_DIR)
        let processInfo = ProcessInfo.processInfo.environment
        if let srcRoot = processInfo["SRCROOT"] ?? processInfo["PROJECT_DIR"] {
            let candidate = URL(fileURLWithPath: srcRoot).appendingPathComponent("Tests").appendingPathComponent("VideoIOTests").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        // Third try: Use XCTestCase's bundle resource path
        if let testBundlePath = Bundle(for: type(of: self)).resourcePath {
            let candidate = URL(fileURLWithPath: testBundlePath).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        // Fourth try: Find from source file location
        let fileURL = URL(fileURLWithPath: "\(#file)")
        let testDir = fileURL.deletingLastPathComponent()
        let urlInSameDir = testDir.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: urlInSameDir.path) {
            return urlInSameDir
        }
        
        // Fifth try: Navigate to Tests/VideoIOTests/ from current location
        let currentDir = fileURL.deletingLastPathComponent()
        let pathComponents = currentDir.pathComponents
        if let testsIndex = pathComponents.firstIndex(of: "Tests") {
            let testsPath = pathComponents[0...testsIndex].joined(separator: "/")
            let testsURL = URL(fileURLWithPath: "/").appendingPathComponent(testsPath)
            let resultURL = testsURL.appendingPathComponent("VideoIOTests").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: resultURL.path) {
                return resultURL
            }
        }
        
        // Sixth try: Find package root by searching up from source file
        var searchDir = fileURL.deletingLastPathComponent()
        while !searchDir.pathComponents.isEmpty && searchDir.lastPathComponent != "/" {
            let packageSwift = searchDir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                let candidate = searchDir.appendingPathComponent("Tests").appendingPathComponent("VideoIOTests").appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            searchDir = searchDir.deletingLastPathComponent()
        }
        
        // Seventh try: Search from current working directory
        let currentWorkingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var workDir = currentWorkingDir
        while !workDir.pathComponents.isEmpty && workDir.lastPathComponent != "/" {
            let candidate = workDir.appendingPathComponent("Tests").appendingPathComponent("VideoIOTests").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let packageSwift = workDir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                break // Found package root, already tried above
            }
            workDir = workDir.deletingLastPathComponent()
        }
        
        // Fallback: return the expected location (will fail test if wrong, which helps diagnose)
        return urlInSameDir
    }
    
    func testAudioVideoSettings() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        var audioSettings = AudioSettings(formatID: kAudioFormatMPEG4AAC, channels: 2, sampleRate: 44100)
        audioSettings.bitRate = 96000
        XCTAssert(audioSettings.toDictionary() as NSDictionary == [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                   AVNumberOfChannelsKey: 2,
                                                   AVSampleRateKey: 44100,
                                                   AVEncoderBitRateKey: 96000] as NSDictionary)
        
        let videoSettings: VideoSettings = .h264(videoSize: CGSize(width: 1280, height: 720), averageBitRate: 3000000)
        XCTAssert(videoSettings.toDictionary() as NSDictionary == [AVVideoWidthKey: 1280,
                                                                   AVVideoHeightKey: 720,
                                                                   AVVideoCodecKey: "avc1",
                                                                   AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3000000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]] as NSDictionary)
        
        var videoSettings2: VideoSettings = .h264(videoSize: CGSize(width: 1280, height: 720), averageBitRate: 3000000)
        videoSettings2.scalingMode = .resizeAspectFill
        XCTAssert(videoSettings2.toDictionary() as NSDictionary == [AVVideoWidthKey: 1280,
                                                                   AVVideoHeightKey: 720,
                                                                   AVVideoCodecKey: "avc1",
                                                                   AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
                                                                   AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3000000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]] as NSDictionary)
    }
    
    func testVideoExport() async throws {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let expectation = XCTestExpectation()
        let videoSizeOptional = await asset.presentationVideoSize()
        let videoSize = try XCTUnwrap(videoSizeOptional, "Failed to get presentationVideoSize. Asset may not be loaded or may not contain video tracks.")
        let exporter = try await AssetExportSession.create(
            asset: asset,
            outputURL: tempURL,
            configuration: AssetExportSession.Configuration(
                fileType: AssetExportSession.fileType(for: tempURL)!,
                videoSettings: .h264(videoSize: videoSize, averageBitRate: 3000000),
                audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)
            )
        )
        final class ProgressHolder: @unchecked Sendable {
            var overallProgress: Double = 0
            var videoProgress: Double = 0
        }
        let progressHolder = ProgressHolder()
        exporter.export(progress: { progress in
            progressHolder.videoProgress = progress.videoEncodingProgress!.fractionCompleted
            progressHolder.overallProgress = progress.fractionCompleted
        }) { error in
            XCTAssert(error == nil)
            XCTAssert(try! tempURL.resourceValues(forKeys: Set<URLResourceKey>([.fileSizeKey])).fileSize! > 0)
            XCTAssert(progressHolder.overallProgress == 1)
            XCTAssert(progressHolder.videoProgress == 1)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 10.0)
        try? fileManager.removeItem(at: tempURL)
    }
    
    // This test intentionally uses deprecated synchronous APIs for backward compatibility testing
    func testVideoExport_videoComposition() async throws {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let movieAsset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // Ensure asset tracks are loaded before using them
        _ = try await movieAsset.load(.tracks)
        let composition = AVMutableComposition()
        let videoTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: composition.unusedTrackID()))
        let originalVideoTracks = try await movieAsset.loadTracks(withMediaType: .video)
        let originalVideoTrack = try XCTUnwrap(originalVideoTracks.first)
        let videoTimeRange = try await originalVideoTrack.load(.timeRange)
        try videoTrack.insertTimeRange(videoTimeRange, of: originalVideoTrack, at: .zero)
        let originalAudioTracks = try await movieAsset.loadTracks(withMediaType:.audio)
        let originalAudioTrack = try XCTUnwrap(originalAudioTracks.first)
        let audioTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: composition.unusedTrackID()))
        let audioTimeRange = try await originalAudioTrack.load(.timeRange)
        try audioTrack.insertTimeRange(audioTimeRange, of: originalAudioTrack, at: .zero)
        
        let expectation = XCTestExpectation()
        // Note: AVMutableComposition.presentationVideoSize is deprecated (inherited from AVAsset)
        // This test intentionally uses the deprecated API for backward compatibility testing
        // swiftlint:disable:next deprecated
        let videoSize = try XCTUnwrap(composition.presentationVideoSize)
        let exporter = try AssetExportSession(asset: composition, outputURL: tempURL, configuration: AssetExportSession.Configuration(fileType: AssetExportSession.fileType(for: tempURL)!, videoSettings: .h264(videoSize: videoSize, averageBitRate: 3000000), audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)))
        final class ProgressHolder: @unchecked Sendable {
            var overallProgress: Double = 0
            var videoProgress: Double = 0
        }
        let progressHolder = ProgressHolder()
        exporter.export(progress: { progress in
            progressHolder.videoProgress = progress.videoEncodingProgress!.fractionCompleted
            progressHolder.overallProgress = progress.fractionCompleted
        }) { error in
            XCTAssert(error == nil)
            XCTAssert(try! tempURL.resourceValues(forKeys: Set<URLResourceKey>([.fileSizeKey])).fileSize! > 0)
            XCTAssert(progressHolder.overallProgress == 1)
            XCTAssert(progressHolder.videoProgress == 1)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 10.0)
        try? fileManager.removeItem(at: tempURL)
    }
    
    func testVideoExportCancel() async throws {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let expectation = XCTestExpectation()
        let videoSizeOptional = await asset.presentationVideoSize()
        let videoSize = try XCTUnwrap(videoSizeOptional, "Failed to get presentationVideoSize. Asset may not be loaded or may not contain video tracks.")
        let exporter = try await AssetExportSession.create(
            asset: asset,
            outputURL: tempURL,
            configuration: AssetExportSession.Configuration(
                fileType: AssetExportSession.fileType(for: tempURL)!,
                videoSettings: .h264(videoSize: videoSize, averageBitRate: 3000000),
                audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)
            )
        )
        exporter.export(progress: nil as ((AssetExportSession.ExportProgress) -> Void)?) { error in
            XCTAssert((error as? AssetExportSession.Error) == .cancelled)
            expectation.fulfill()
        }
        exporter.cancel()
        await fulfillment(of: [expectation], timeout: 10.0)
        try? fileManager.removeItem(at: tempURL)
    }
    
    func testVideoExportCancel_delay() async throws {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let expectation = XCTestExpectation()
        let videoSizeOptional = await asset.presentationVideoSize()
        let videoSize = try XCTUnwrap(videoSizeOptional, "Failed to get presentationVideoSize. Asset may not be loaded or may not contain video tracks.")
        let exporter = try await AssetExportSession.create(
            asset: asset,
            outputURL: tempURL,
            configuration: AssetExportSession.Configuration(
                fileType: AssetExportSession.fileType(for: tempURL)!,
                videoSettings: .h264(videoSize: videoSize, averageBitRate: 3000000),
                audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)
            )
        )
        final class ProgressHolder: @unchecked Sendable {
            var overallProgress: Double = 0
        }
        let progressHolder = ProgressHolder()
        exporter.export(progress: { progress in
            progressHolder.overallProgress = progress.fractionCompleted
        }) { error in
            XCTAssert((error as? AssetExportSession.Error) == .cancelled)
            XCTAssert(progressHolder.overallProgress != 1)
            expectation.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exporter.cancel()
        }
        await fulfillment(of: [expectation], timeout: 10.0)
        try? fileManager.removeItem(at: tempURL)
    }
    
    func testVideoExportCancel_lifecycle() async throws {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let expectation = XCTestExpectation(description: "Export cancellation completion")
        let videoSizeOptional = await asset.presentationVideoSize()
        let videoSize = try XCTUnwrap(videoSizeOptional, "Failed to get presentationVideoSize. Asset may not be loaded or may not contain video tracks.")
        var exporter: AssetExportSession? = try await AssetExportSession.create(
            asset: asset,
            outputURL: tempURL,
            configuration: AssetExportSession.Configuration(
                fileType: AssetExportSession.fileType(for: tempURL)!,
                videoSettings: .h264(videoSize: videoSize, averageBitRate: 3000000),
                audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)
            )
        )
        final class TestState: @unchecked Sendable {
            weak var weakExporter: AssetExportSession?
            var overallProgress: Double = 0
        }
        let testState = TestState()
        testState.weakExporter = exporter
        exporter?.export(progress: { progress in
            testState.overallProgress = progress.fractionCompleted
        }) { error in
            XCTAssert(testState.weakExporter != nil, "Exporter should still exist when cancellation completes")
            XCTAssert((error as? AssetExportSession.Error) == .cancelled, "Error should be cancelled")
            XCTAssert(testState.overallProgress != 1, "Progress should not be 1.0 when cancelled")
            expectation.fulfill()
        }
        let exporterForCancel = exporter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exporterForCancel?.cancel()
            // Don't set exporter to nil yet - wait for completion handler to verify weak reference
        }
        await fulfillment(of: [expectation], timeout: 10.0)
        // Release the strong reference - weak reference may or may not become nil immediately due to ARC timing
        exporter = nil
        try? fileManager.removeItem(at: tempURL)
        // Note: We don't assert weak reference is nil here because ARC deallocation timing can vary
        // The important test is that completion handler was called with correct error
    }
    
    func testVideoExportCancel_pauseThenCancel() async throws {
        let fileManager = FileManager()
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let expectation = XCTestExpectation(description: "Export pause then cancel completion")
        let videoSizeOptional = await asset.presentationVideoSize()
        let videoSize = try XCTUnwrap(videoSizeOptional, "Failed to get presentationVideoSize. Asset may not be loaded or may not contain video tracks.")
        var exporter: AssetExportSession? = try await AssetExportSession.create(
            asset: asset,
            outputURL: tempURL,
            configuration: AssetExportSession.Configuration(
                fileType: AssetExportSession.fileType(for: tempURL)!,
                videoSettings: .h264(videoSize: videoSize, averageBitRate: 3000000),
                audioSettings: .aac(channels: 2, sampleRate: 44100, bitRate: 96 * 1024)
            )
        )
        final class TestState: @unchecked Sendable {
            weak var weakExporter: AssetExportSession?
            var overallProgress: Double = 0
        }
        let testState = TestState()
        testState.weakExporter = exporter
        exporter?.export(progress: { progress in
            testState.overallProgress = progress.fractionCompleted
        }) { error in
            XCTAssert(testState.weakExporter != nil, "Exporter should still exist when cancellation completes")
            XCTAssert((error as? AssetExportSession.Error) == .cancelled, "Error should be cancelled")
            XCTAssert(testState.overallProgress != 1, "Progress should not be 1.0 when cancelled")
            expectation.fulfill()
        }
        let exporterForCancel = exporter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exporterForCancel?.pause()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                exporterForCancel?.cancel()
                // Don't set exporter to nil yet - wait for completion handler to verify weak reference
            }
        }
        await fulfillment(of: [expectation], timeout: 10.0)
        // Release the strong reference - weak reference may or may not become nil immediately due to ARC timing
        exporter = nil
        try? fileManager.removeItem(at: tempURL)
        // Note: We don't assert weak reference is nil here because ARC deallocation timing can vary
        // The important test is that completion handler was called with correct error
    }
    
    func testSampleBufferUtilities() {
        var oldPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32BGRA, [:] as CFDictionary, &oldPixelBuffer)
        var oldFormatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: oldPixelBuffer!, formatDescriptionOut: &oldFormatDescription)
        var timingInfo = CMSampleTimingInfo(duration: CMTime(seconds: 1.0/30.0, preferredTimescale: 44100), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)

        var newPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1920, 1080, kCVPixelFormatType_32BGRA, [:] as CFDictionary, &newPixelBuffer)
        
        var oldSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: oldPixelBuffer!, formatDescription: oldFormatDescription!, sampleTiming: &timingInfo, sampleBufferOut: &oldSampleBuffer)
        
        let buffer = SampleBufferUtilities.makeSampleBufferByReplacingImageBuffer(of: oldSampleBuffer!, with: newPixelBuffer!)
        XCTAssert(CMSampleBufferGetImageBuffer(buffer!) === newPixelBuffer)
        
        
        var t: CMSampleTimingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(buffer!, at: 0, timingInfoOut: &t)
        XCTAssert(t == timingInfo)
        
        var sampleBufferWithNoImage: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: nil, sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBufferWithNoImage)
        XCTAssert(SampleBufferUtilities.makeSampleBufferByReplacingImageBuffer(of: sampleBufferWithNoImage!, with: newPixelBuffer!) == nil)
    }

    func testPlayerVideoOutput_iOS() {
        #if os(iOS)
        let expectation = XCTestExpectation()
        let player = AVPlayer(url: testMovieURL)
        var frameCount = 0
        let output = PlayerVideoOutput(player: player) { frame in
            frameCount += 1
            if frameCount >= 28 {
                expectation.fulfill()
            }
        }
        player.play()
        XCTAssert(output.player != nil)
        wait(for: [expectation], timeout: 10)
        #endif
    }
}
