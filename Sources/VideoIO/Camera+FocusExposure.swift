//
//  File.swift
//  
//
//  Created by Yu Ao on 2019/12/27.
//

import Foundation
import AVFoundation

@available(iOS 18.0, macOS 10.15, *)
@available(tvOS, unavailable)
@available(macCatalyst 14.0, *)
extension Camera {
    @available(macOS, unavailable)
    public func setFocusExposurePointOfInterest(to devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus, exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure, shouldMonitorSubjectAreaChange: Bool = false) throws {
        guard let videoDevice = self.videoDevice else {
            return
        }
        try videoDevice.lockForConfiguration()
        if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
            videoDevice.focusPointOfInterest = devicePoint
            videoDevice.focusMode = focusMode
        }
        if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
            videoDevice.exposurePointOfInterest = devicePoint
            videoDevice.exposureMode = exposureMode
        }
        videoDevice.isSubjectAreaChangeMonitoringEnabled = shouldMonitorSubjectAreaChange
        videoDevice.unlockForConfiguration()
    }
    
    public func setFocusExposurePointOfInterest(to devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus, exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure) throws {
        guard let videoDevice = self.videoDevice else {
            return
        }
        try videoDevice.lockForConfiguration()
        if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
            videoDevice.focusPointOfInterest = devicePoint
            videoDevice.focusMode = focusMode
        }
        if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
            videoDevice.exposurePointOfInterest = devicePoint
            videoDevice.exposureMode = exposureMode
        }
        videoDevice.unlockForConfiguration()
    }
    
    @available(macOS, unavailable)
    public func setExposureTargetBias(_ bias: Float, completion: (@Sendable (CMTime) -> Void)? = nil) throws {
        guard let device = self.videoDevice else {
            return
        }
        let targetBias = simd_clamp(bias, device.minExposureTargetBias, device.maxExposureTargetBias)
        if device.exposureTargetBias == targetBias { return }
        try device.lockForConfiguration()
        device.setExposureTargetBias(targetBias, completionHandler: completion)
        device.unlockForConfiguration()
    }
    
    public func captureDevicePointOfInterest(for point: CGPoint, inPreviewBounds: CGRect, videoGravity: AVLayerVideoGravity) -> CGPoint {
        guard let device = self.videoDevice, let connection = self.videoCaptureConnection else { return CGPoint(x: 0.5, y: 0.5) }
        
        var point = point
        let size = inPreviewBounds.size
        if connection.isVideoMirrored {
            point.x = size.width - point.x
        }
        let format = device.activeFormat
        let videoDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        if videoDimensions.width == 0 || videoDimensions.height == 0 {
            return CGPoint(x: 0.5, y: 0.5)
        }
        var xInView: CGFloat
        var yInView: CGFloat
        var viewHeight: CGFloat
        var viewWidth: CGFloat
        
        // Use videoRotationAngle instead of deprecated videoOrientation (macOS 14.0+)
        let rotationAngle: CGFloat
        if #available(macOS 14.0, *) {
            rotationAngle = connection.videoRotationAngle
        } else {
            // Fallback: convert deprecated videoOrientation to angle
            let orientation = connection.videoOrientation
            switch orientation {
            case .portrait:
                rotationAngle = 0.0
            case .portraitUpsideDown:
                rotationAngle = 180.0
            case .landscapeRight:
                rotationAngle = 90.0
            case .landscapeLeft:
                rotationAngle = 270.0
            @unknown default:
                rotationAngle = 0.0
            }
        }
        // Convert rotation angle (in degrees) to determine orientation equivalent
        // 0 = portrait, 90 = landscapeRight, 180 = portraitUpsideDown, 270 = landscapeLeft
        switch Int(rotationAngle) {
        case 0:
            // Portrait
            viewHeight = size.width
            viewWidth = size.height
            xInView = point.y
            yInView = viewHeight - point.x
        case 90:
            // LandscapeRight
            viewHeight = size.height
            viewWidth = size.width
            xInView = point.x
            yInView = point.y
        case 180:
            // PortraitUpsideDown
            viewHeight = size.width
            viewWidth = size.height
            xInView = point.y
            yInView = point.x
        case 270:
            // LandscapeLeft
            viewHeight = size.height
            viewWidth = size.width
            xInView = viewWidth - point.x
            yInView = viewHeight - point.y
        default:
            // Default to portrait for unrecognized angles
            viewHeight = size.width
            viewWidth = size.height
            xInView = point.y
            yInView = viewHeight - point.x
        }
        
        let videoRatio = CGFloat(videoDimensions.width) / CGFloat(videoDimensions.height)
        let viewRatio = viewWidth / viewHeight
        
        var videoHeight: CGFloat = viewHeight
        var videoWidth: CGFloat = viewWidth
        
        var xInVideo: CGFloat = xInView
        var yInVideo: CGFloat = yInView
        
        switch videoGravity {
        case .resize:
            videoWidth = viewWidth
            videoHeight = viewHeight
            xInVideo = xInView
            yInVideo = yInView
        case .resizeAspect:
            if (videoRatio >= viewRatio) {
                videoWidth = viewWidth
                videoHeight = videoWidth / videoRatio
                xInVideo = xInView
                let blackBar = (viewHeight - videoHeight) / 2
                if (yInView >= blackBar && yInView <= viewHeight - blackBar) {
                    yInVideo = yInView - blackBar
                }
            } else {
                videoHeight = viewHeight
                videoWidth = videoHeight * videoRatio
                yInVideo = yInView
                let blackBar = (viewWidth - videoWidth) / 2
                if (xInView >= blackBar && xInView <= viewWidth - blackBar) {
                    xInVideo = xInView - blackBar
                }
            }
        case .resizeAspectFill:
            if (videoRatio >= viewRatio) {
                videoHeight = viewHeight
                videoWidth = videoHeight * videoRatio
                yInVideo = yInView
                xInVideo = xInView + (videoWidth - viewWidth) / 2
            } else {
                videoWidth = viewWidth
                videoHeight = videoWidth / videoRatio
                xInVideo = xInView
                yInVideo = yInView + (videoHeight - viewHeight) / 2
            }
        default:
            assertionFailure()
            return CGPoint(x: 0.5, y: 0.5)
        }
        
        return CGPoint(x: xInVideo / videoWidth, y: yInVideo / videoHeight)
    }
    
    public func captureDevicePointOfInterestForPointInOutputImage(_ point: CGPoint) -> CGPoint {
        guard let output = self.videoDataOutput else { return CGPoint(x: 0.5, y: 0.5) }
        return output.metadataOutputRectConverted(fromOutputRect: CGRect(origin: point, size: .zero)).origin
    }
}
