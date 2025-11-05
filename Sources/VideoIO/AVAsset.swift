//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/19.
//

import Foundation
import AVFoundation

extension AVAsset {
    @available(iOS 16.0, tvOS 16.0, macOS 13.0, *)
    public func presentationVideoSize() async -> CGSize? {
        do {
            // For AVURLAsset, ensure tracks are loaded by loading the tracks property first
            // This helps ensure the asset metadata is ready
            if let urlAsset = self as? AVURLAsset {
                // Load tracks property to ensure asset is ready
                _ = try await urlAsset.load(.tracks)
            }
            let videoTracks = try await self.loadTracks(withMediaType: AVMediaType.video)
            guard let videoTrack = videoTracks.first else { return nil }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let size = naturalSize.applying(preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        } catch {
            // Log error for debugging
            print("VideoIO: Failed to load presentationVideoSize: \(error)")
            return nil
        }
    }
    
    @available(iOS 16.0, tvOS 16.0, macOS 13.0, *)
    public func naturalVideoSize() async -> CGSize? {
        do {
            // For AVURLAsset, ensure tracks are loaded by loading the tracks property first
            if let urlAsset = self as? AVURLAsset {
                _ = try await urlAsset.load(.tracks)
            }
            let videoTracks = try await self.loadTracks(withMediaType: AVMediaType.video)
            guard let videoTrack = videoTracks.first else { return nil }
            let naturalSize = try await videoTrack.load(.naturalSize)
            return naturalSize
        } catch {
            print("VideoIO: Failed to load naturalVideoSize: \(error)")
            return nil
        }
    }
    
    // Legacy synchronous API for backward compatibility
    // Note: These properties use deprecated APIs. For new code, use the async methods instead.
    @available(*, deprecated, message: "Use presentationVideoSize() async instead")
    public var presentationVideoSize: CGSize? {
        if let videoTrack = self.tracks(withMediaType: AVMediaType.video).first {
            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        }
        return nil
    }
    
    @available(*, deprecated, message: "Use naturalVideoSize() async instead")
    public var naturalVideoSize: CGSize? {
        if let videoTrack = self.tracks(withMediaType: AVMediaType.video).first {
            return videoTrack.naturalSize
        }
        return nil
    }
}
