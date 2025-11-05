# Test Failure Investigation Plan

## Overview
This document outlines a systematic investigation plan to determine whether the test failures indicate code problems or test problems. The investigation will be conducted in phases, starting with the most likely causes.

## Phase 1: Asset Loading and Path Resolution Issues

### Problem: Multiple `presentationVideoSize()` returning nil

**Symptoms:**
- `testVideoExport()` - Line 42: `XCTUnwrap failed: expected non-nil value of type "CGSize"`
- `testVideoExportCancel()` - Line 119: Same error
- `testVideoExportCancel_delay()` - Line 144: Same error
- `testVideoExportCancel_lifecycle()` - Line 178: Same error
- `testVideoExportCancel_pauseThenCancel()` - Line 219: Same error

**Investigation Steps:**

1. **Verify Asset File Accessibility**
   - [ ] Check if `testMovieURL` resolves correctly at runtime in simulator
   - [ ] Verify file exists and is readable at test execution time
   - [ ] Check file permissions (readable by simulator process)
   - [ ] Validate the URL path construction: `URL(fileURLWithPath: "\(#file)")`

2. **Test Asset Loading Directly**
   - [ ] Create a diagnostic test to load asset and check tracks synchronously
   - [ ] Create a diagnostic test to load asset tracks asynchronously
   - [ ] Check if `AVURLAssetPreferPreciseDurationAndTimingKey` is working correctly
   - [ ] Verify the asset can be loaded in a minimal test case

3. **Debug `presentationVideoSize()` Implementation**
   - [ ] Add detailed logging to `AVAsset.presentationVideoSize()` to see where it fails
   - [ ] Check if `load(.tracks)` succeeds before calling `loadTracks(withMediaType:)`
   - [ ] Verify error messages are being printed (check console output)
   - [ ] Test if the issue is specific to async loading vs sync loading

4. **Test Environment Verification**
   - [ ] Check if the issue occurs on device vs simulator
   - [ ] Verify iOS version compatibility (tests require iOS 16.0+)
   - [ ] Check if there are any simulator-specific limitations

**Expected Outcomes:**
- If asset file is inaccessible: **TEST PROBLEM** - Fix file path resolution
- If asset loads but `presentationVideoSize()` still fails: **CODE PROBLEM** - Fix async loading logic
- If issue is simulator-specific: **TEST PROBLEM** - Add conditional logic or skip on simulator

---

## Phase 2: Video Composition Test Error Analysis

### Problem: `testVideoExport_videoComposition()` failing with AVFoundation error

**Symptoms:**
- Line 77: Error Domain=AVFoundationErrorDomain Code=-11800
- NSUnderlyingError Code=-17913
- AVErrorFailedDependenciesKey: "assetProperty_Tracks"

**Investigation Steps:**

1. **Error Code Analysis**
   - [ ] Research AVFoundation error code -17913 (likely kCMIOExtensionPropertyError_PropertyNotFound or similar)
   - [ ] Verify error -11800 is `AVErrorOperationInterrupted` or related
   - [ ] Check if error occurs during `insertTimeRange` or during export

2. **Test Asset Loading in Composition Context**
   - [ ] Verify `movieAsset.load(.tracks)` succeeds before composition operations
   - [ ] Check if tracks are properly loaded before `insertTimeRange`
   - [ ] Test if issue is with async track loading in composition context
   - [ ] Verify `insertTimeRange` can handle async-loaded tracks

3. **Deprecated API Usage Check**
   - [ ] Verify if `testVideoExport_videoComposition()` is using deprecated `AssetExportSession.init` correctly
   - [ ] Check if the deprecated initializer has issues with compositions created from async-loaded assets
   - [ ] Test if using the new `AssetExportSession.create` async method fixes the issue

4. **Composition vs Asset Track Handling**
   - [ ] Verify difference between `AVMutableComposition.tracks` and `AVAsset.tracks`
   - [ ] Check if composition tracks need special handling
   - [ ] Test if the error occurs when creating the exporter or during export

**Expected Outcomes:**
- If error is due to asset not being fully loaded: **TEST PROBLEM** - Add proper async loading
- If deprecated initializer has issues with async-loaded assets: **CODE PROBLEM** - Fix initializer or migrate test
- If error is due to composition track handling: **CODE PROBLEM** - Fix track insertion/loading logic

---

## Phase 3: PlayerVideoOutput Timeout

### Problem: `testPlayerVideoOutput_iOS()` timeout

**Symptoms:**
- Line 296: Asynchronous wait failed: Exceeded timeout of 10 seconds
- Expectation not fulfilled (no description provided)

**Investigation Steps:**

1. **Test Expectation Setup**
   - [ ] Verify expectation has a meaningful description for debugging
   - [ ] Check if the completion callback is actually being called
   - [ ] Verify the frame count threshold (28 frames) is reasonable for test asset
   - [ ] Check if player is actually playing and producing frames

2. **PlayerVideoOutput Implementation Check**
   - [ ] Verify `handleReadyToPlay()` is being called and completing
   - [ ] Check if async loading in `handleReadyToPlay()` is causing issues
   - [ ] Verify `setupDisplayLink()` is working correctly
   - [ ] Check if video track detection is working

3. **Simulator vs Device Behavior**
   - [ ] Test if this works on a physical device
   - [ ] Check if simulator has limitations with AVPlayer frame output
   - [ ] Verify if test asset plays correctly in a simple AVPlayer test

4. **Async Context Issues**
   - [ ] Check if `handleReadyToPlay()` async method is properly awaited
   - [ ] Verify no deadlocks or race conditions in async setup
   - [ ] Test if issue is with `@MainActor` isolation

**Expected Outcomes:**
- If simulator-specific issue: **TEST PROBLEM** - Add conditional logic or increase timeout
- If async loading issue: **CODE PROBLEM** - Fix async/await in PlayerVideoOutput
- If player not producing frames: **TEST PROBLEM** - Fix test setup or use different test asset

---

## Phase 4: Systematic Testing

### Diagnostic Test Suite

Create the following diagnostic tests to isolate issues:

1. **`testAssetFileAccessibility()`**
   ```swift
   func testAssetFileAccessibility() {
       XCTAssertTrue(FileManager.default.fileExists(atPath: testMovieURL.path))
       XCTAssertTrue(FileManager.default.isReadableFile(atPath: testMovieURL.path))
       print("Test asset URL: \(testMovieURL)")
       print("Test asset path: \(testMovieURL.path)")
   }
   ```

2. **`testAssetTracksLoading() async throws`**
   ```swift
   func testAssetTracksLoading() async throws {
       let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
       let tracks = try await asset.load(.tracks)
       XCTAssertFalse(tracks.isEmpty, "Asset should have tracks")
       let videoTracks = try await asset.loadTracks(withMediaType: .video)
       XCTAssertFalse(videoTracks.isEmpty, "Asset should have video tracks")
       print("Found \(videoTracks.count) video tracks")
   }
   ```

3. **`testPresentationVideoSizeDirectly() async throws`**
   ```swift
   func testPresentationVideoSizeDirectly() async throws {
       let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
       // Load tracks first
       _ = try await asset.load(.tracks)
       // Then get size
       let size = await asset.presentationVideoSize()
       XCTAssertNotNil(size, "presentationVideoSize should not be nil")
       print("Video size: \(size!)")
   }
   ```

4. **`testLegacyPresentationVideoSize()`**
   ```swift
   func testLegacyPresentationVideoSize() {
       let asset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
       // Test deprecated synchronous API
       let size = asset.presentationVideoSize
       XCTAssertNotNil(size, "Legacy presentationVideoSize should work")
       print("Legacy video size: \(size!)")
   }
   ```

5. **`testCompositionWithAsyncLoadedTracks() async throws`**
   ```swift
   func testCompositionWithAsyncLoadedTracks() async throws {
       let movieAsset = AVURLAsset(url: testMovieURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
       _ = try await movieAsset.load(.tracks)
       let composition = AVMutableComposition()
       let videoTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: composition.unusedTrackID()))
       let originalVideoTracks = try await movieAsset.loadTracks(withMediaType: .video)
       let originalVideoTrack = try XCTUnwrap(originalVideoTracks.first)
       let videoTimeRange = try await originalVideoTrack.load(.timeRange)
       // This should work without errors
       try videoTrack.insertTimeRange(videoTimeRange, of: originalVideoTrack, at: .zero)
       print("Composition created successfully")
   }
   ```

---

## Phase 5: Code Review Focus Areas

### Critical Code Sections to Review

1. **`AVAsset.presentationVideoSize()` in `Sources/VideoIO/AVAsset.swift`**
   - Review the async loading logic
   - Check if `load(.tracks)` before `loadTracks(withMediaType:)` is necessary or causing issues
   - Verify error handling is not swallowing important errors
   - Check if the double-loading (`.tracks` then `loadTracks`) is causing problems

2. **`AssetExportSession.create()` in `Sources/VideoIO/AssetExportSession.swift`**
   - Verify async loading is working correctly
   - Check if asset copy is necessary and working
   - Verify track loading happens in correct order

3. **`VideoComposition.init()` in `Sources/VideoIO/VideoComposition.swift`**
   - Check if synchronous semaphore-based async call is causing deadlocks
   - Verify asset loading before video composition creation
   - Check if the Task-based async call in init could cause issues

4. **`PlayerVideoOutput.handleReadyToPlay()` in `Sources/VideoIO/PlayerVideoOutput.swift`**
   - Verify async loading is completing
   - Check if `@MainActor` isolation is causing issues
   - Verify display link setup happens after async loading completes

---

## Phase 6: Hypothesis and Fix Prioritization

### Hypothesis 1: Double-Loading Issue
**Theory:** Loading `.tracks` before `loadTracks(withMediaType:)` may be causing conflicts or race conditions.

**Test:** Remove the `load(.tracks)` call from `presentationVideoSize()` and see if it still works.

### Hypothesis 2: Simulator Asset Loading Limitations
**Theory:** Simulator may have issues with async asset loading or file access.

**Test:** Run tests on physical device and compare results.

### Hypothesis 3: Timing/Concurrency Issues
**Theory:** Async loading may not be completing before subsequent operations.

**Test:** Add explicit delays or better synchronization mechanisms.

### Hypothesis 4: Test Asset Issues
**Theory:** The test asset may be corrupted or incompatible with async loading APIs.

**Test:** Create a simple test asset programmatically and test with that.

---

## Execution Order

1. **Immediate (Quick Wins):**
   - Add diagnostic tests (Phase 4)
   - Run diagnostic tests to gather data
   - Check console output for error messages

2. **Short-term (1-2 hours):**
   - Review code sections (Phase 5)
   - Test hypotheses (Phase 6)
   - Try removing double-loading in `presentationVideoSize()`

3. **Medium-term (Half day):**
   - Comprehensive debugging with logging
   - Test on physical device if available
   - Fix identified issues

4. **Long-term (If needed):**
   - Refactor async loading if architecture issues found
   - Update test infrastructure if test problems identified
   - Add better error reporting and diagnostics

---

## Success Criteria

The investigation is successful when:
1. ✅ All diagnostic tests pass
2. ✅ Root cause of each failure is identified (code vs test)
3. ✅ Appropriate fixes are implemented
4. ✅ All original tests pass or are appropriately marked as skipped/fixed
5. ✅ No regressions introduced

---

## Next Steps

1. Create diagnostic test file: `Tests/VideoIOTests/DiagnosticTests.swift`
2. Run diagnostic tests to gather baseline data
3. Review console output for detailed error messages
4. Implement fixes based on findings
5. Re-run full test suite to verify fixes
