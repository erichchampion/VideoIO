//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/18.
//

import Foundation
import AVFoundation

public protocol VideoCompositorProtocol: AVVideoCompositing {
    associatedtype Instruction: AVVideoCompositionInstructionProtocol
}

public final class BlockBasedVideoCompositor: NSObject, VideoCompositorProtocol, @unchecked Sendable {
    
    public enum Error: Swift.Error {
        case unsupportedInstruction
    }
    
    public final class Instruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
        
        typealias Handler = @Sendable (_ request: AVAsynchronousVideoCompositionRequest) -> Void
        
        public let timeRange: CMTimeRange
        
        public let enablePostProcessing: Bool = false
        
        public let containsTweening: Bool = true
        
        public let requiredSourceTrackIDs: [NSValue]?
        
        public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
        
        internal let handler: Handler
        
        internal init(handler: @escaping Handler, timeRange: CMTimeRange, requiredSourceTrackIDs: [CMPersistentTrackID] = []) {
            self.handler = handler
            self.timeRange = timeRange
            if requiredSourceTrackIDs.count > 0 {
                // NSNumber is a subclass of NSValue, so this works for the protocol requirement
                self.requiredSourceTrackIDs = requiredSourceTrackIDs.map({ NSNumber(value: $0) as NSValue })
            } else {
                self.requiredSourceTrackIDs = nil
            }
        }
    }
    
    public var sourcePixelBufferAttributes: [String : any Sendable]? {
        let formats: [UInt32] = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        return [kCVPixelBufferPixelFormatTypeKey as String: formats]
    }
    
    public var requiredPixelBufferAttributesForRenderContext: [String : any Sendable] {
        let format: UInt32 = kCVPixelFormatType_32BGRA
        return [kCVPixelBufferPixelFormatTypeKey as String: format]
    }
    
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        
    }
    
    public func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? Instruction else {
            assertionFailure()
            asyncVideoCompositionRequest.finish(with: Error.unsupportedInstruction)
            return
        }
        instruction.handler(asyncVideoCompositionRequest)
    }
}

private final class CompositionHolder: @unchecked Sendable {
    var composition: AVMutableVideoComposition?
}

private final class SizeHolder: @unchecked Sendable {
    var size: CGSize?
}

public class VideoComposition<Compositor> where Compositor: VideoCompositorProtocol {
    public let asset: AVAsset
    
    public var sourceTrackIDForFrameTiming: CMPersistentTrackID {
        get {
            return self.videoComposition.sourceTrackIDForFrameTiming
        }
        set {
            self.videoComposition.sourceTrackIDForFrameTiming = newValue
        }
    }
    
    public var frameDuration: CMTime {
        get {
            return self.videoComposition.frameDuration
        }
        set {
            return self.videoComposition.frameDuration = newValue
        }
    }
    
    public var renderSize: CGSize {
        get {
            return self.videoComposition.renderSize
        }
        set {
            self.videoComposition.renderSize = newValue
        }
    }
    
    @available(macOS 10.14, *)
    public var renderScale: Float {
        get {
            return self.videoComposition.renderScale
        }
        set {
            self.videoComposition.renderScale = newValue
        }
    }
    
    public var instructions: [Compositor.Instruction] {
        get {
            return self.videoComposition.instructions as! [Compositor.Instruction]
        }
        set {
            self.videoComposition.instructions = newValue
        }
    }
    
    private let videoComposition: AVMutableVideoComposition
    
    public func makeAVVideoComposition() -> AVVideoComposition {
        return self.videoComposition.copy() as! AVVideoComposition
    }
    
    public init(propertiesOf asset: AVAsset) {
        self.asset = asset.copy() as! AVAsset
        // Use the new async API for iOS 18.0+, fallback to deprecated API for older versions
        if #available(iOS 18.0, tvOS 18.0, macOS 14.0, *) {
            // Use completion handler version synchronously using semaphore
            let semaphore = DispatchSemaphore(value: 0)
            let holder = CompositionHolder()
            AVMutableVideoComposition.videoComposition(withPropertiesOf: self.asset) { videoComposition, error in
                if let error = error {
                    fatalError("Failed to create video composition: \(error)")
                }
                holder.composition = videoComposition
                semaphore.signal()
            }
            semaphore.wait()
            guard let videoComposition = holder.composition else {
                fatalError("Failed to create video composition: composition is nil")
            }
            self.videoComposition = videoComposition
        } else {
            // Fallback to deprecated API for older versions
            self.videoComposition = AVMutableVideoComposition(propertiesOf: self.asset)
        }
        self.videoComposition.customVideoCompositorClass = Compositor.self
        // Use async presentationVideoSize() for iOS 16.0+, fallback to deprecated property for older versions
        if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
            // Use async API synchronously using semaphore
            let semaphore = DispatchSemaphore(value: 0)
            // Extract asset before Task to avoid capturing self
            // Note: AVAsset is not Sendable but is safe to capture here since it's only accessed from the Task
            nonisolated(unsafe) let asset = self.asset
            // Use a holder class to safely share mutable state between Task and init
            let sizeHolder = SizeHolder()
            Task { @Sendable in
                sizeHolder.size = await asset.presentationVideoSize()
                semaphore.signal()
            }
            semaphore.wait()
            if let presentationVideoSize = sizeHolder.size {
                self.renderSize = presentationVideoSize
            }
        } else {
            // Fallback to deprecated property for older versions
            // Extract to helper to suppress deprecation warning in legacy code path
            func getLegacyPresentationVideoSize(asset: AVAsset) -> CGSize? {
                // This branch is only for versions < iOS 16.0, so deprecated API is acceptable
                return asset.presentationVideoSize
            }
            if let presentationVideoSize = getLegacyPresentationVideoSize(asset: self.asset) {
                self.renderSize = presentationVideoSize
            }
        }
    }
}

extension VideoComposition where Compositor == BlockBasedVideoCompositor {
    public convenience init(propertiesOf asset: AVAsset, compositionRequestHandler: @escaping @Sendable (AVAsynchronousVideoCompositionRequest) -> Void) {
        self.init(propertiesOf: asset)
        self.instructions = [.init(handler: compositionRequestHandler, timeRange: CMTimeRange(start: .zero, duration: CMTime(value: CMTimeValue.max, timescale: 48000)))]
    }
}
