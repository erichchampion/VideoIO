//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation

public class AssetExportSession: @unchecked Sendable {
    
    public struct Configuration {
        
        public var fileType: AVFileType
        
        public var shouldOptimizeForNetworkUse: Bool = true
        
        public var videoSettings: [String: Any]
        
        public var audioSettings: [String: Any]
        
        public var timeRange: CMTimeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        
        public var metadata: [AVMetadataItem] = []
        
        public var videoComposition: AVVideoComposition?
        
        public var audioMix: AVAudioMix?
        
        public init(fileType: AVFileType, rawVideoSettings: [String: Any], rawAudioSettings: [String: Any]) {
            self.fileType = fileType
            self.videoSettings = rawVideoSettings
            self.audioSettings = rawAudioSettings
        }
        
        public init(fileType: AVFileType, videoSettings: VideoSettings, audioSettings: AudioSettings) {
            self.fileType = fileType
            self.videoSettings = videoSettings.toDictionary()
            self.audioSettings = audioSettings.toDictionary()
        }
    }
    
    public enum Status {
        case idle
        case exporting
        case paused
        case completed
    }
    
    public enum Error: Swift.Error {
        case noTracks
        case cannotAddVideoOutput
        case cannotAddVideoInput
        case cannotAddAudioOutput
        case cannotAddAudioInput
        case cannotStartWriting
        case cannotStartReading
        case invalidStatus
        case cancelled
    }
    
    public private(set) var status: Status = .idle
    
    private let asset: AVAsset
    private let configuration: Configuration
    private let outputURL: URL
    
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    
    private let videoOutput: AVAssetReaderOutput?
    private let audioOutput: AVAssetReaderAudioMixOutput?
    private let videoInput: AVAssetWriterInput?
    private let audioInput: AVAssetWriterInput?
    
    private let queue: DispatchQueue = DispatchQueue(label: "com.MetalPetal.VideoIO.AssetExportSession")
    private let duration: CMTime
    
    private let pauseDispatchGroup = DispatchGroup()
    private var cancelled: Bool = false
    
    // Async factory method using modern async APIs (iOS 16.0+)
    @available(iOS 16.0, tvOS 16.0, macOS 13.0, *)
    public static func create(asset: AVAsset, outputURL: URL, configuration: Configuration) async throws -> AssetExportSession {
        let assetCopy = asset.copy() as! AVAsset
        
        let reader = try AVAssetReader(asset: assetCopy)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.fileType)
        reader.timeRange = configuration.timeRange
        writer.shouldOptimizeForNetworkUse = configuration.shouldOptimizeForNetworkUse
        writer.metadata = configuration.metadata
        
        let duration: CMTime
        if configuration.timeRange.duration.isValid && !configuration.timeRange.duration.isPositiveInfinity {
            duration = configuration.timeRange.duration
        } else {
            duration = try await assetCopy.load(.duration)
        }
        
        let videoTracks = try await assetCopy.loadTracks(withMediaType: .video)
        var videoOutput: AVAssetReaderOutput?
        var videoInput: AVAssetWriterInput?
        
        if videoTracks.count > 0 {
            let inputTransform: CGAffineTransform?
            if configuration.videoComposition != nil {
                let videoCompositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: nil)
                videoCompositionOutput.alwaysCopiesSampleData = false
                videoCompositionOutput.videoComposition = configuration.videoComposition
                videoOutput = videoCompositionOutput
                inputTransform = nil
            } else {
                let firstTrack = videoTracks.first!
                // Note: containsAlphaChannel is available since iOS 13.0/tvOS 13.0/macOS 10.15,
                // but since create() requires iOS 16.0+/tvOS 16.0+/macOS 13.0+, the availability check is unnecessary
                let mediaCharacteristics = try await firstTrack.load(.mediaCharacteristics)
                if mediaCharacteristics.contains(.containsAlphaChannel) {
                    videoOutput = AVAssetReaderTrackOutput(track: firstTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                } else {
                    videoOutput = AVAssetReaderTrackOutput(track: firstTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]])
                }
                videoOutput?.alwaysCopiesSampleData = false
                inputTransform = try await firstTrack.load(.preferredTransform)
            }
            
            if let videoOutput = videoOutput, reader.canAdd(videoOutput) {
                reader.add(videoOutput)
            } else {
                throw Error.cannotAddVideoOutput
            }
            
            if let transform = inputTransform {
                let size = CGSize(width: configuration.videoSettings[AVVideoWidthKey] as! CGFloat, height: configuration.videoSettings[AVVideoHeightKey] as! CGFloat)
                let transformedSize = size.applying(transform.inverted())
                var videoSettings = configuration.videoSettings
                videoSettings[AVVideoWidthKey] = abs(transformedSize.width)
                videoSettings[AVVideoHeightKey] = abs(transformedSize.height)
                videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput?.transform = transform
            } else {
                videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoSettings)
            }
            videoInput?.expectsMediaDataInRealTime = false
            if let videoInput = videoInput, writer.canAdd(videoInput) {
                writer.add(videoInput)
            } else {
                throw Error.cannotAddVideoInput
            }
        }
        
        let audioTracks = try await assetCopy.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        var audioInput: AVAssetWriterInput?
        
        if audioTracks.count > 0 {
            audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            audioOutput?.alwaysCopiesSampleData = false
            audioOutput?.audioMix = configuration.audioMix
            if let audioOutput = audioOutput, reader.canAdd(audioOutput) {
                reader.add(audioOutput)
            } else {
                throw Error.cannotAddAudioOutput
            }
            
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: configuration.audioSettings)
            audioInput?.expectsMediaDataInRealTime = false
            if let audioInput = audioInput, writer.canAdd(audioInput) {
                writer.add(audioInput)
            } else {
                throw Error.cannotAddAudioInput
            }
        }
        
        if videoTracks.count == 0 && audioTracks.count == 0 {
            throw Error.noTracks
        }
        
        return AssetExportSession(
            asset: assetCopy,
            configuration: configuration,
            outputURL: outputURL,
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            audioOutput: audioOutput,
            videoInput: videoInput,
            audioInput: audioInput,
            duration: duration
        )
    }
    
    private init(asset: AVAsset, configuration: Configuration, outputURL: URL, reader: AVAssetReader, writer: AVAssetWriter, videoOutput: AVAssetReaderOutput?, audioOutput: AVAssetReaderAudioMixOutput?, videoInput: AVAssetWriterInput?, audioInput: AVAssetWriterInput?, duration: CMTime) {
        self.asset = asset
        self.configuration = configuration
        self.outputURL = outputURL
        self.reader = reader
        self.writer = writer
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.duration = duration
    }
    
    // Legacy synchronous initializer - uses deprecated APIs for backward compatibility
    // swiftlint:disable deprecated
    public init(asset: AVAsset, outputURL: URL, configuration: Configuration) throws {
        self.asset = asset.copy() as! AVAsset
        self.configuration = configuration
        self.outputURL = outputURL
        
        self.reader = try AVAssetReader(asset: self.asset)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.fileType)
        self.reader.timeRange = configuration.timeRange
        self.writer.shouldOptimizeForNetworkUse = configuration.shouldOptimizeForNetworkUse
        self.writer.metadata = configuration.metadata
        
        if configuration.timeRange.duration.isValid && !configuration.timeRange.duration.isPositiveInfinity {
            self.duration = configuration.timeRange.duration
        } else {
            self.duration = self.asset.duration
        }
        
        let videoTracks = self.asset.tracks(withMediaType: .video)
        if (videoTracks.count > 0) {
            let videoOutput: AVAssetReaderOutput
            let inputTransform: CGAffineTransform?
            if configuration.videoComposition != nil {
                let videoCompositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: nil)
                videoCompositionOutput.alwaysCopiesSampleData = false
                videoCompositionOutput.videoComposition = configuration.videoComposition
                videoOutput = videoCompositionOutput
                inputTransform = nil
            } else {
                if #available(iOS 13.0, tvOS 13.0, macOS 10.15, *) {
                    if videoTracks.first!.hasMediaCharacteristic(.containsAlphaChannel) {
                        videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    } else {
                        videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]])
                    }
                } else {
                    videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]])
                }
                videoOutput.alwaysCopiesSampleData = false
                inputTransform = videoTracks.first!.preferredTransform
            }
            if self.reader.canAdd(videoOutput) {
                self.reader.add(videoOutput)
            } else {
                throw Error.cannotAddVideoOutput
            }
            self.videoOutput = videoOutput
            
            let videoInput: AVAssetWriterInput
            if let transform = inputTransform {
                let size = CGSize(width: configuration.videoSettings[AVVideoWidthKey] as! CGFloat, height: configuration.videoSettings[AVVideoHeightKey] as! CGFloat)
                let transformedSize = size.applying(transform.inverted())
                var videoSettings = configuration.videoSettings
                videoSettings[AVVideoWidthKey] = abs(transformedSize.width)
                videoSettings[AVVideoHeightKey] = abs(transformedSize.height)
                videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput.transform = transform
            } else {
                videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoSettings)
            }
            videoInput.expectsMediaDataInRealTime = false
            if self.writer.canAdd(videoInput) {
                self.writer.add(videoInput)
            } else {
                throw Error.cannotAddVideoInput
            }
            self.videoInput = videoInput
        } else {
            self.videoOutput = nil
            self.videoInput = nil
        }
        
        let audioTracks = self.asset.tracks(withMediaType: .audio)
        if audioTracks.count > 0 {
            let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            audioOutput.alwaysCopiesSampleData = false
            audioOutput.audioMix = configuration.audioMix
            if self.reader.canAdd(audioOutput) {
                self.reader.add(audioOutput)
            } else {
                throw Error.cannotAddAudioOutput
            }
            self.audioOutput = audioOutput
            
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: configuration.audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            if self.writer.canAdd(audioInput) {
                self.writer.add(audioInput)
            }
            self.audioInput = audioInput
        } else {
            self.audioOutput = nil
            self.audioInput = nil
        }
        
        if videoTracks.count == 0 && audioTracks.count == 0 {
            throw Error.noTracks
        }
    }
    // swiftlint:enable deprecated
    
    private func encode(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) -> Bool {
        while input.isReadyForMoreMediaData {
            if self.reader.status != .reading || self.writer.status != .writing {
                input.markAsFinished()
                return false
            }
            self.pauseDispatchGroup.wait()
            if let buffer = output.copyNextSampleBuffer() {
                let progress = (CMSampleBufferGetPresentationTimeStamp(buffer) - self.configuration.timeRange.start).seconds/self.duration.seconds
                if self.videoOutput === output {
                    self.dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: progress) }
                }
                if self.audioOutput === output {
                    self.dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: progress) }
                }
                if !input.append(buffer) {
                    input.markAsFinished()
                    return false
                }
            } else {
                if self.videoOutput === output {
                    self.dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: 1) }
                }
                if self.audioOutput === output {
                    self.dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: 1) }
                }
                input.markAsFinished()
                return false
            }
        }
        return true
    }
    
    
    public class ExportProgress: Progress, @unchecked Sendable {
        public let videoEncodingProgress: Progress?
        public let audioEncodingProgress: Progress?
        public let finishWritingProgress: Progress
        
        private let childProgressTotalUnitCount: Int64 = 10000
        
        fileprivate init(tracksAudioEncoding: Bool, tracksVideoEncoding: Bool) {
            finishWritingProgress = Progress(totalUnitCount: childProgressTotalUnitCount)
            audioEncodingProgress = tracksAudioEncoding ? Progress(totalUnitCount: childProgressTotalUnitCount) : nil
            videoEncodingProgress = tracksVideoEncoding ? Progress(totalUnitCount: childProgressTotalUnitCount) : nil
            
            super.init(parent: nil, userInfo: nil)
            
            let pendingUnitCount: Int64 = 1
            self.addChild(finishWritingProgress, withPendingUnitCount: pendingUnitCount)
            self.totalUnitCount += pendingUnitCount
            
            if let progress = audioEncodingProgress {
                let pendingUnitCount: Int64 = 5000
                self.addChild(progress, withPendingUnitCount: pendingUnitCount)
                self.totalUnitCount += pendingUnitCount
            }
            
            if let progress = videoEncodingProgress {
                let pendingUnitCount: Int64 = 5000
                self.addChild(progress, withPendingUnitCount: pendingUnitCount)
                self.totalUnitCount += pendingUnitCount
            }
        }
        
        fileprivate func updateVideoEncodingProgress(fractionCompleted: Double) {
            self.videoEncodingProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
        fileprivate func updateAudioEncodingProgress(fractionCompleted: Double) {
            self.audioEncodingProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
        fileprivate func updateFinishWritingProgress(fractionCompleted: Double) {
            self.finishWritingProgress.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
    }
    
    private var progress: ExportProgress?
    private var progressHandler: ((ExportProgress) -> Void)?

    public func export(progress: ((ExportProgress) -> Void)?, completion: @escaping @Sendable (Swift.Error?) -> Void) {
        assert(status == .idle && cancelled == false)
        if self.status != .idle || self.cancelled {
            DispatchQueue.main.async {
                completion(Error.invalidStatus)
            }
            return
        }
        
        do {
            guard self.writer.startWriting() else {
                if let error = self.writer.error {
                    throw error
                } else {
                    throw Error.cannotStartWriting
                }
            }
            guard self.reader.startReading() else {
                if let error = self.reader.error {
                    throw error
                } else {
                    throw Error.cannotStartReading
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(error)
            }
            return
        }
        
        self.status = .exporting
        self.progressHandler = progress
        self.progress = ExportProgress(tracksAudioEncoding: self.audioInput != nil, tracksVideoEncoding: self.videoInput != nil)
        
        self.writer.startSession(atSourceTime: configuration.timeRange.start)
        
        final class CompletionState: @unchecked Sendable {
            let lock = UnfairLock()
            var videoCompleted = false
            var audioCompleted = false
            var hasCalledCompletion = false
        }
        let completionState = CompletionState()

        if let videoInput = self.videoInput, let videoOutput = self.videoOutput {
            // Use a final class to hold references for thread-safe capture
            final class VideoEncoderState: @unchecked Sendable {
                weak var session: AssetExportSession?
                let videoOutput: AVAssetReaderOutput
                let videoInput: AVAssetWriterInput
                init(session: AssetExportSession, videoOutput: AVAssetReaderOutput, videoInput: AVAssetWriterInput) {
                    self.session = session
                    self.videoOutput = videoOutput
                    self.videoInput = videoInput
                }
            }
            let encoderState = VideoEncoderState(session: self, videoOutput: videoOutput, videoInput: videoInput)
            // Capture completion separately to avoid Sendable warnings
            let completionForVideo = completion
            // Use nonisolated(unsafe) for videoInput since it's only accessed on self.queue
            nonisolated(unsafe) let videoInputUnsafe = videoInput
            videoInput.requestMediaDataWhenReady(on: self.queue) { @Sendable in
                guard let session = encoderState.session else { return }
                if !session.encode(from: encoderState.videoOutput, to: videoInputUnsafe) {
                    completionState.lock.lock()
                    completionState.videoCompleted = true
                    encoderState.session = nil
                    let shouldComplete = completionState.audioCompleted && !completionState.hasCalledCompletion
                    if shouldComplete {
                        completionState.hasCalledCompletion = true
                    }
                    completionState.lock.unlock()
                    if shouldComplete {
                        let handler: @Sendable (Swift.Error?) -> Void = completionForVideo
                        session.finish(completionHandler: handler)
                    }
                }
            }
        } else {
            completionState.lock.lock()
            completionState.videoCompleted = true
            completionState.lock.unlock()
        }
        
        if let audioInput = self.audioInput, let audioOutput = self.audioOutput {
            // Use a final class to hold references for thread-safe capture
            final class AudioEncoderState: @unchecked Sendable {
                weak var session: AssetExportSession?
                let audioOutput: AVAssetReaderAudioMixOutput
                let audioInput: AVAssetWriterInput
                init(session: AssetExportSession, audioOutput: AVAssetReaderAudioMixOutput, audioInput: AVAssetWriterInput) {
                    self.session = session
                    self.audioOutput = audioOutput
                    self.audioInput = audioInput
                }
            }
            let encoderState = AudioEncoderState(session: self, audioOutput: audioOutput, audioInput: audioInput)
            // Capture completion separately to avoid Sendable warnings
            let completionForAudio = completion
            // Use nonisolated(unsafe) for audioInput since it's only accessed on self.queue
            nonisolated(unsafe) let audioInputUnsafe = audioInput
            audioInput.requestMediaDataWhenReady(on: self.queue) { @Sendable in
                guard let session = encoderState.session else { return }
                if !session.encode(from: encoderState.audioOutput, to: audioInputUnsafe) {
                    completionState.lock.lock()
                    completionState.audioCompleted = true
                    encoderState.session = nil
                    let shouldComplete = completionState.videoCompleted && !completionState.hasCalledCompletion
                    if shouldComplete {
                        completionState.hasCalledCompletion = true
                    }
                    completionState.lock.unlock()
                    if shouldComplete {
                        let handler: @Sendable (Swift.Error?) -> Void = completionForAudio
                        session.finish(completionHandler: handler)
                    }
                }
            }
        } else {
            completionState.lock.lock()
            completionState.audioCompleted = true
            completionState.lock.unlock()
        }
    }
    
    private func dispatchProgressCallback(with updater: @escaping @Sendable (ExportProgress) -> Void) {
        // Extract values before closure to avoid sending self
        let progress = self.progress
        // Use nonisolated(unsafe) for progressHandler since it's only accessed on main queue
        nonisolated(unsafe) let progressHandler = self.progressHandler
        DispatchQueue.main.async { @Sendable in
            guard let progress = progress else { return }
            updater(progress)
            progressHandler?(progress)
        }
    }
    
    private func dispatchCallback(with error: Swift.Error?, _ completionHandler: @escaping @Sendable (Swift.Error?) -> Void) {
        DispatchQueue.main.async { @Sendable in
            self.progressHandler = nil
            self.status = .completed
            completionHandler(error)
        }
    }
    
    private func finish(completionHandler: @escaping @Sendable (Swift.Error?) -> Void) {
        dispatchPrecondition(condition: DispatchPredicate.onQueue(queue))
        
        if self.reader.status == .cancelled || self.writer.status == .cancelled {
            if self.writer.status != .cancelled {
                self.writer.cancelWriting()
            } else {
                assertionFailure("Internal error. Please file a bug report.")
            }
            
            if self.reader.status != .cancelled {
                assertionFailure("Internal error. Please file a bug report.")
                self.reader.cancelReading()
            }
            
            try? FileManager().removeItem(at: self.outputURL)
            self.dispatchCallback(with: Error.cancelled, completionHandler)
            return
        }
        
        if self.writer.status == .failed {
            try? FileManager().removeItem(at: self.outputURL)
            self.dispatchCallback(with: self.writer.error, completionHandler)
        } else if self.reader.status == .failed {
            try? FileManager().removeItem(at: self.outputURL)
            self.writer.cancelWriting()
            self.dispatchCallback(with: self.reader.error, completionHandler)
        } else {
            self.writer.finishWriting { @Sendable in
                self.queue.async { @Sendable in
                    if self.writer.status == .failed {
                        try? FileManager().removeItem(at: self.outputURL)
                    }
                    if self.writer.error == nil {
                        self.dispatchProgressCallback { $0.updateFinishWritingProgress(fractionCompleted: 1) }
                    }
                    self.dispatchCallback(with: self.writer.error, completionHandler)
                }
            }
        }
    }
    
    public func pause() {
        guard self.status == .exporting && self.cancelled == false else {
            assertionFailure("self.status == .exporting && self.cancelled == false")
            return
        }
        self.status = .paused
        self.pauseDispatchGroup.enter()
    }
    
    public func resume() {
        guard self.status == .paused && self.cancelled == false else {
            assertionFailure("self.status == .paused && self.cancelled == false")
            return
        }
        self.status = .exporting
        self.pauseDispatchGroup.leave()
    }
    
    public func cancel() {
        if self.status == .paused {
            self.resume()
        }
        guard self.status == .exporting && self.cancelled == false else {
            assertionFailure("self.status == .exporting && self.cancelled == false")
            return
        }
        self.cancelled = true
        self.queue.async { @Sendable in
            if self.reader.status == .reading {
                self.reader.cancelReading()
            }
        }
    }
}

extension AssetExportSession {
    public static func fileType(for url: URL) -> AVFileType? {
        switch url.pathExtension.lowercased() {
        case "mp4":
            return .mp4
        case "mp3":
            return .mp3
        case "mov":
            return .mov
        case "qt":
            return .mov
        case "m4a":
            return .m4a
        case "m4v":
            return .m4v
        case "amr":
            return .amr
        case "caf":
            return .caf
        case "wav":
            return .wav
        case "wave":
            return .wav
        default:
            return nil
        }
    }
}
