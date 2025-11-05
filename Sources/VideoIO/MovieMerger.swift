//
//  File.swift
//  
//
//  Created by YuAo on 2021/3/20.
//

import Foundation
import AVFoundation

public final class MovieMerger {
    
    public enum Error: LocalizedError {
        case noAssets
        case cannotCreateExportSession
        case unsupportedFileType
        public var errorDescription: String? {
            switch self {
            case .noAssets:
                return "No assets to merge."
            case .cannotCreateExportSession:
                return "Cannot create export session."
            case .unsupportedFileType:
                return "Unsupported file type."
            }
        }
    }
    
    @available(iOS 16.0, tvOS 16.0, macOS 13.0, *)
    public static func merge(_ assets: [URL], to url: URL) async throws {
        if assets.isEmpty {
            throw Error.noAssets
        }
        let composition = AVMutableComposition()
        var current: CMTime = .zero
        var firstSegmentTransform: CGAffineTransform = .identity
        
        var isFirstSegmentTransformSet = false
        for segment in assets {
            let asset = AVURLAsset(url: segment, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            if !isFirstSegmentTransformSet {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = videoTracks.first {
                    firstSegmentTransform = try await videoTrack.load(.preferredTransform)
                    isFirstSegmentTransformSet = true
                }
            }
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            
            // Use async insertTimeRange for iOS 18.0+ (runtime available on iOS 16.0+)
            if #available(iOS 18.0, tvOS 18.0, macOS 14.0, *) {
                try await composition.insertTimeRange(range, of: asset, at: current)
            } else {
                // Fallback to completion handler version for older runtimes
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                    if #available(tvOS 16.0, *) {
                        composition.insertTimeRange(range, of: asset, at: current, completionHandler: { error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        })
                    } else {
                        // Fallback to sync for very old versions
                        do {
                            try composition.insertTimeRange(range, of: asset, at: current)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            current = CMTimeAdd(current, duration)
        }
        
        if isFirstSegmentTransformSet {
            // Note: composition.tracks is not deprecated, only AVAsset.tracks is
            let videoTracks = composition.tracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                videoTrack.preferredTransform = firstSegmentTransform
            }
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw Error.cannotCreateExportSession
        }
        
        guard let fileType = MovieFileType.from(url: url)?.avFileType else {
            throw Error.unsupportedFileType
        }
        
        exportSession.outputURL = url
        exportSession.outputFileType = fileType
        
        // Use async export for iOS 18.0+, fallback to deprecated API for older versions
        if #available(iOS 18.0, tvOS 18.0, macOS 14.0, *) {
            let compositionDuration = try await composition.load(.duration)
            exportSession.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)
            try await exportSession.export(to: url, as: fileType)
        } else {
            // Note: composition.duration is not deprecated, only AVAsset.duration is
            exportSession.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            // Use a final class to hold the weak reference for thread-safe capture
            final class ExportSessionHolder: @unchecked Sendable {
                weak var session: AVAssetExportSession?
                init(session: AVAssetExportSession) {
                    self.session = session
                }
            }
            let sessionHolder = ExportSessionHolder(session: exportSession)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                guard let exportSession = sessionHolder.session else {
                    continuation.resume(throwing: Error.cannotCreateExportSession)
                    return
                }
                exportSession.exportAsynchronously {
                    guard let exportSession = sessionHolder.session else { return }
                    switch exportSession.status {
                    case .failed:
                        if let error = exportSession.error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: Error.cannotCreateExportSession)
                        }
                    case .cancelled:
                        continuation.resume(throwing: Error.cannotCreateExportSession)
                    case .completed:
                        continuation.resume()
                    default:
                        continuation.resume(throwing: Error.cannotCreateExportSession)
                    }
                }
            }
        }
    }
    
    // Legacy completion-based API - uses deprecated APIs for backward compatibility
    // For new code, use the async merge(_:to:) method instead
    @available(*, deprecated, message: "Use merge(_:to:) async throws instead. This method uses deprecated AVFoundation APIs.")
    public static func merge(_ assets: [URL], to url: URL, completion: @escaping @Sendable (Swift.Error?) -> Void) {
        if assets.isEmpty {
            completion(Error.noAssets)
            return
        }
        let composition = AVMutableComposition()
        var current: CMTime = .zero
        var firstSegmentTransform: CGAffineTransform = .identity
        
        var isFirstSegmentTransformSet = false
        for segment in assets {
            let asset = AVURLAsset(url: segment, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            if !isFirstSegmentTransformSet, let videoTrack = asset.tracks(withMediaType: .video).first {
                firstSegmentTransform = videoTrack.preferredTransform
                isFirstSegmentTransformSet = true
            }
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            do {
                try composition.insertTimeRange(range, of: asset, at: current)
                current = CMTimeAdd(current, asset.duration)
            } catch {
                completion(error)
                return
            }
        }
        
        if isFirstSegmentTransformSet, let videoTrack = composition.tracks(withMediaType: .video).first {
            videoTrack.preferredTransform = firstSegmentTransform
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            completion(Error.cannotCreateExportSession)
            return
        }
        
        guard let fileType = MovieFileType.from(url: url)?.avFileType else {
            completion(Error.unsupportedFileType)
            return
        }
        
        exportSession.outputURL = url
        exportSession.outputFileType = fileType
        exportSession.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        // Use a final class to hold the reference for thread-safe capture
        final class ExportSessionHolder: @unchecked Sendable {
            let session: AVAssetExportSession
            init(session: AVAssetExportSession) {
                self.session = session
            }
        }
        let sessionHolder = ExportSessionHolder(session: exportSession)
        exportSession.exportAsynchronously {
            switch sessionHolder.session.status {
            case .failed:
                if let error = sessionHolder.session.error {
                    completion(error)
                } else {
                    assertionFailure()
                }
            case .cancelled:
                assertionFailure()
            case .completed:
                completion(nil)
            default:
                assertionFailure()
            }
        }
    }
}

