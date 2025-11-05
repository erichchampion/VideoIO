# TODO: Fix Warnings and Errors

## Priority 1: Deprecation Warnings (iOS 16.0+ APIs)

### AssetExportSession.swift

1. **Line 97**: `asset.duration` deprecated
   - **Fix**: Replace with `await asset.load(.duration)` or use async/await pattern
   - **Impact**: Requires making initialization async or using a different approach

2. **Line 100**: `asset.tracks(withMediaType:)` deprecated  
   - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
   - **Impact**: Requires async context

3. **Line 111**: `track.hasMediaCharacteristic(.containsAlphaChannel)` deprecated
   - **Fix**: Replace with `await track.load(.mediaCharacteristics)` then check
   - **Impact**: Requires async context

4. **Line 117**: `track.preferredTransform` deprecated
   - **Fix**: Replace with `await track.load(.preferredTransform)`
   - **Impact**: Requires async context

5. **Line 150**: `asset.tracks(withMediaType:)` deprecated (audio tracks)
   - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
   - **Impact**: Requires async context

### AVAsset.swift

6. **Line 13**: `asset.tracks(withMediaType:)` deprecated
   - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
   - **Impact**: Requires async context

7. **Line 14**: `composition.naturalSize` and `track.preferredTransform` deprecated
   - **Fix**: Replace with `await composition.load(.naturalSize)` and `await track.load(.preferredTransform)`
   - **Impact**: Requires async context

8. **Line 20**: `asset.tracks(withMediaType:)` deprecated
   - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
   - **Impact**: Requires async context

9. **Line 21**: `composition.naturalSize` deprecated
   - **Fix**: Replace with `await composition.load(.naturalSize)`
   - **Impact**: Requires async context

### MovieMerger.swift

10. **Line 41**: `asset.tracks(withMediaType:)` deprecated
    - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
    - **Impact**: Requires async context

11. **Line 42**: `track.preferredTransform` deprecated
    - **Fix**: Replace with `await track.load(.preferredTransform)`
    - **Impact**: Requires async context

12. **Line 45**: `asset.duration` deprecated
    - **Fix**: Replace with `await asset.load(.duration)`
    - **Impact**: Requires async context

13. **Line 47**: `composition.insertTimeRange(_:of:at:)` deprecated in iOS 18.0
    - **Fix**: Replace with new async API `insertTimeRange(_:of:at:) async throws` or equivalent
    - **Impact**: Requires async context

14. **Line 48**: `composition.duration` deprecated
    - **Fix**: Replace with `await composition.load(.duration)`
    - **Impact**: Requires async context

15. **Line 72**: `exportSession.exportAsynchronously(completionHandler:)` deprecated in iOS 18.0
    - **Fix**: Replace with `try await exportSession.export(to:as:)` or `exportSession.export(to:as:) async throws`
    - **Impact**: Requires async/await pattern

16. **Line 73**: `exportSession.status` deprecated in iOS 18.0
    - **Fix**: Replace with `exportSession.states(updateInterval:)` 
    - **Impact**: Different API pattern (async stream)

17. **Line 75**: `exportSession.error` deprecated in iOS 18.0
    - **Fix**: Use error from `export(to:as:) async throws`
    - **Impact**: Error handling becomes part of async throws

### PlayerVideoOutput.swift

18. **Line 138**: `asset.tracks` deprecated
    - **Fix**: Replace with `await asset.load(.tracks)`
    - **Impact**: Requires async context

19. **Line 141**: `track.preferredTransform` deprecated
    - **Fix**: Replace with `await track.load(.preferredTransform)`
    - **Impact**: Requires async context

### VideoIOTests.swift

20. **Line 70**: `asset.tracks(withMediaType:)` deprecated
    - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
    - **Impact**: Requires async context in test

21. **Line 71**: `track.timeRange` deprecated
    - **Fix**: Replace with `await track.load(.timeRange)`
    - **Impact**: Requires async context in test

22. **Line 72**: `asset.tracks(withMediaType:)` deprecated
    - **Fix**: Replace with `await asset.loadTracks(withMediaType:)`
    - **Impact**: Requires async context in test

23. **Line 74**: `track.timeRange` deprecated
    - **Fix**: Replace with `await track.load(.timeRange)`
    - **Impact**: Requires async context in test

## Priority 2: Concurrency/Sendable Issues

### AssetExportSession.swift

24. **Line 300-304**: Multiple concurrency issues in video encoding closure
    - **Issues**:
      - Reference to captured var `sessionForVideoEncoder` in concurrently-executing code
      - Capture of `videoOutput` (non-Sendable `AVAssetReaderOutput`)
      - Capture of `videoInput` (non-Sendable `AVAssetWriterInput`)
      - Mutation of captured vars `videoCompleted` and `sessionForVideoEncoder`
      - Reference to `audioCompleted` from different closure
    - **Fix**: 
      - Use `nonisolated(unsafe)` for non-Sendable types if safe
      - Or restructure to avoid cross-closure state
      - Use actors or proper synchronization
      - Consider making `videoCompleted` and `audioCompleted` thread-safe (e.g., using a lock or atomic)

25. **Line 316-320**: Multiple concurrency issues in audio encoding closure
    - **Issues**:
      - Reference to captured var `sessionForAudioEncoder` in concurrently-executing code
      - Capture of `audioOutput` (non-Sendable `AVAssetReaderAudioMixOutput`)
      - Capture of `audioInput` (non-Sendable `AVAssetWriterInput`)
      - Mutation of captured vars `audioCompleted` and `sessionForAudioEncoder`
      - Reference to `videoCompleted` from different closure
    - **Fix**: Same as above for video encoding

### AudioQueueCaptureSession.swift

26. **Line 133**: Capture of `self` (non-Sendable `AudioQueueCaptureSession`) in `@Sendable` closure
    - **Fix**: Add `@unchecked Sendable` conformance to `AudioQueueCaptureSession` class, or use `weak self` if appropriate

27. **Line 136, 141**: Capture of `completion` (non-Sendable closure type) in `@Sendable` closure
    - **Fix**: Mark completion parameter as `@Sendable ((any Error)?) -> Void`

28. **Line 199**: Capture of `session` (non-Sendable) and `sampleBuffer` (non-Sendable `CMSampleBuffer`) in `@Sendable` closure
    - **Fix**: 
      - Add `@unchecked Sendable` to `AudioQueueCaptureSession`
      - Mark `CMSampleBuffer` usage as safe (it's thread-safe for read operations)
      - Or use `nonisolated(unsafe)` annotation where safe

29. **Line 209**: Forming `UnsafeMutableRawPointer` to `Optional<AudioQueueCaptureSession.ClientInfo>`
    - **Fix**: Review the pointer usage - may need to unwrap optional or use different approach for storing context

### MovieMerger.swift

30. **Line 73**: Capture of `exportSession` (non-Sendable `AVAssetExportSession`) in `@Sendable` closure
    - **Fix**: Use `weak var` capture or mark as `@unchecked Sendable` where safe

31. **Line 76**: Capture of `completion` (non-Sendable closure type) in `@Sendable` closure
    - **Fix**: Mark completion parameter as `@Sendable ((any Error)?) -> Void`

### MultitrackMovieRecorder.swift

32. **Line 184**: Capture of `sampleBuffers` (non-Sendable `[CMSampleBuffer]`) in `@Sendable` closure
    - **Fix**: Mark closure parameter as `@Sendable` or use `nonisolated(unsafe)` if safe (CMSampleBuffer is thread-safe for reads)

33. **Line 294**: Capture of `sampleBuffers` (non-Sendable `[CMSampleBuffer]`) in `@Sendable` closure
    - **Fix**: Same as above

34. **Line 358**: Capture of `completion` (non-Sendable `() -> Void`) in `@Sendable` closure
    - **Fix**: Mark completion parameter as `@Sendable () -> Void`

35. **Line 383**: Capture of `completion` (non-Sendable `((any Error)?) -> Void`) in `@Sendable` closure
    - **Fix**: Mark completion parameter as `@Sendable ((any Error)?) -> Void`

36. **Line 410**: Capture of `completion` (non-Sendable `((any Error)?) -> Void`) in `@Sendable` closure
    - **Fix**: Mark completion parameter as `@Sendable ((any Error)?) -> Void`

### PlayerVideoOutput.swift

37. **Line 137**: Main actor-isolated property `asset` cannot be referenced from nonisolated context
    - **Fix**: 
      - Extract `asset` to local variable before accessing in nonisolated context
      - Or mark the method/closure as `@MainActor`
      - Or use `nonisolated(unsafe)` if appropriate

38. **Line 150**: Type `Any` does not conform to `Sendable` protocol
    - **Fix**: Replace `Any` with a `Sendable` type or use `any Sendable`

### VideoIOTests.swift

39. **Line 56-57**: Reference to captured vars `overallProgress` and `videoProgress` in concurrently-executing code
    - **Fix**: Use thread-safe storage (e.g., `@MainActor` property wrapper, `Actor`, or synchronization primitive)

40. **Line 86-87**: Reference to captured vars `overallProgress` and `videoProgress` in concurrently-executing code
    - **Fix**: Same as above

41. **Line 120**: Reference to captured var `overallProgress` in concurrently-executing code
    - **Fix**: Same as above

42. **Line 141, 143**: Reference to captured vars `weakExporter` and `overallProgress` in concurrently-executing code
    - **Fix**: Same as above

43. **Line 168, 170**: Reference to captured vars `weakExporter` and `overallProgress` in concurrently-executing code
    - **Fix**: Same as above

## Priority 3: Other Issues

### AudioVideoSettings.swift

44. **Line 12**: Extension declares conformance of imported type `AVVideoCodecType` to `Codable`
    - **Fix**: Add `@retroactive` attribute to the extension: `extension AVVideoCodecType: @retroactive Codable`

### Camera+FocusExposure.swift

45. **Line 81**: Unnecessary check for 'iOS'; enclosing scope ensures guard will always be true
    - **Fix**: Remove the redundant `#if !os(macOS)` or `@available(iOS, ...)` check if the enclosing scope already ensures iOS-only execution

### VideoIOTests.swift

46. **Line 5**: Conformance of `CMSampleTimingInfo` to `Equatable` already stated in CoreMedia
    - **Fix**: Remove the redundant extension that declares `Equatable` conformance

## Implementation Strategy

### Phase 1: Fix Sendable/Concurrency Issues (Can be done immediately)
- Add `@unchecked Sendable` where appropriate for classes
- Mark closure parameters as `@Sendable`
- Fix main actor isolation issues
- Fix captured variable mutations in concurrent contexts

### Phase 2: Fix Deprecation Warnings (Requires API redesign)
- Evaluate which methods need to become async
- Consider providing both sync and async variants for backward compatibility
- Update all call sites to use async/await
- For tests, use async test functions

### Phase 3: Clean Up Other Issues
- Fix `@retroactive` conformance
- Remove redundant availability checks
- Remove duplicate protocol conformances

## Notes

- Many deprecation warnings require async/await, which may break existing APIs
- Consider maintaining backward compatibility with wrapper methods
- Some AVFoundation types are inherently non-Sendable but can be safely used with `@unchecked Sendable` or `nonisolated(unsafe)`
- Test thoroughly after making concurrency changes
