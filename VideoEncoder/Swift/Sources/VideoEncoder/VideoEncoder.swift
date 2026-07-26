//
//  VideoEncoder.swift
//  SwiftGodotIosPlugins
//
//  Video encoding plugin for Godot using AVAssetWriter (iOS equivalent of Android MediaCodec).
//  Accepts raw RGBA frames from Godot SubViewport and encodes to H.264 MP4.
//

import Accelerate
import AVFoundation
import CoreVideo
import SwiftGodot

#initSwiftExtension(
    cdecl: "videoencoder",
    types: [
        VideoEncoder.self,
    ]
)

@Godot
class VideoEncoder: Object {

    // MARK: - Signals (match Android plugin signal names)

    /// Emitted when encoding finishes successfully. Parameter: output file path.
    @Signal var encodingCompleted: SignalWithArguments<String>

    /// Emitted when encoding fails. Parameter: error message.
    @Signal var encodingFailed: SignalWithArguments<String>

    /// Emitted after each frame with progress percentage (0-100).
    @Signal var encodingProgress: SignalWithArguments<Float>

    // MARK: - Properties

    static var shared: VideoEncoder?

    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var frameIndex: Int = 0
    private var totalFrames: Int = 0
    private var frameDurationCMTime: CMTime = .zero
    private var encoding: Bool = false
    private var outputPath: String = ""
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    private var lastPixelBuffer: CVPixelBuffer?  // Cached for duplicate static frames

    // MARK: - Initialization

    required override init() {
        super.init()
        VideoEncoder.shared = self
        GD.print("[VideoEncoder] Plugin initialized via init()")
    }

    required init(nativeHandle: UnsafeRawPointer) {
        super.init(nativeHandle: nativeHandle)
        VideoEncoder.shared = self
        GD.print("[VideoEncoder] Plugin initialized via nativeHandle")
    }

    // MARK: - Public Callable Methods

    /// Start encoding a new video.
    /// - Parameters:
    ///   - width: Video width in pixels
    ///   - height: Video height in pixels
    ///   - fps: Frames per second
    ///   - bitrate: Target bitrate in bits/sec (e.g. 4_000_000 for 4 Mbps)
    ///   - path: Output file path for the MP4
    /// - Returns: true if encoding started successfully
    @Callable
    func startEncoding(width: Int, height: Int, fps: Int, bitrate: Int, path: String) -> Bool {
        if encoding {
            GD.print("[VideoEncoder] Already encoding, ignoring startEncoding call")
            return false
        }

        GD.print("[VideoEncoder] startEncoding: \(width)x\(height) @ \(fps)fps, bitrate=\(bitrate), path=\(path)")

        // Clean up any existing file at the output path
        let fileURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            outputPath = path
            frameIndex = 0
            totalFrames = 0
            videoWidth = width
            videoHeight = height
            frameDurationCMTime = CMTime(value: 1, timescale: CMTimeScale(fps))

            // Create AVAssetWriter for MP4 output
            assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)

            // Configure H.264 video output settings
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoMaxKeyFrameIntervalKey: fps, // Keyframe every 1 second
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ] as [String: Any]
            ]

            writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput!.expectsMediaDataInRealTime = false

            // Create pixel buffer adaptor for raw pixel data input
            let sourceAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput!,
                sourcePixelBufferAttributes: sourceAttributes
            )

            assetWriter!.add(writerInput!)
            assetWriter!.startWriting()
            assetWriter!.startSession(atSourceTime: .zero)

            encoding = true
            GD.print("[VideoEncoder] Encoding started successfully")
            return true
        } catch {
            GD.print("[VideoEncoder] Failed to start encoding: \(error.localizedDescription)")
            releaseResources()
            encodingFailed.emit("Failed to start encoding: \(error.localizedDescription)")
            return false
        }
    }

    /// Set the expected total number of frames for progress reporting.
    @Callable
    func setTotalFrames(count: Int) {
        totalFrames = count
    }

    /// Add a raw RGBA frame to the video.
    /// - Parameter rgbaBytes: Raw RGBA pixel data from Godot Image.get_data()
    /// - Returns: true if frame was added successfully
    @Callable
    func addFrameRGBA(rgbaBytes: PackedByteArray) -> Bool {
        guard encoding,
              let adaptor = pixelBufferAdaptor,
              let input = writerInput else {
            GD.print("[VideoEncoder] addFrameRGBA called but not encoding")
            return false
        }

        // Wait for the writer input to be ready
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.001)
        }

        // Create CVPixelBuffer from RGBA data
        guard let pixelBuffer = createPixelBuffer(from: rgbaBytes) else {
            GD.print("[VideoEncoder] Failed to create pixel buffer for frame \(frameIndex)")
            return false
        }

        // Calculate presentation time for this frame
        let presentationTime = CMTime(
            value: CMTimeValue(frameIndex),
            timescale: frameDurationCMTime.timescale
        )

        // Append pixel buffer
        let success = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        if !success {
            GD.print("[VideoEncoder] Failed to append frame \(frameIndex): \(assetWriter?.error?.localizedDescription ?? "unknown error")")
            return false
        }

        // Cache for duplicate frame reuse
        lastPixelBuffer = pixelBuffer

        frameIndex += 1

        // Emit progress if total is known
        if totalFrames > 0 {
            let percent = Float(frameIndex) / Float(totalFrames) * 100.0
            encodingProgress.emit(percent)
        }

        return true
    }

    /// Re-append the last pixel buffer as a new frame (no RGBA conversion needed).
    /// Use for static scenes where the visual content hasn't changed.
    /// - Returns: true if frame was added successfully
    @Callable
    func addDuplicateFrame() -> Bool {
        guard encoding,
              let adaptor = pixelBufferAdaptor,
              let input = writerInput,
              let cached = lastPixelBuffer else {
            return false
        }

        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.001)
        }

        let presentationTime = CMTime(
            value: CMTimeValue(frameIndex),
            timescale: frameDurationCMTime.timescale
        )

        let success = adaptor.append(cached, withPresentationTime: presentationTime)
        if !success { return false }

        frameIndex += 1

        if totalFrames > 0 {
            let percent = Float(frameIndex) / Float(totalFrames) * 100.0
            encodingProgress.emit(percent)
        }

        return true
    }

    /// Finish encoding and finalize the MP4 file.
    /// - Returns: true if video was finalized successfully
    @Callable
    func finishEncoding() -> Bool {
        guard encoding, let writer = assetWriter, let input = writerInput else {
            GD.print("[VideoEncoder] finishEncoding called but not encoding")
            return false
        }

        GD.print("[VideoEncoder] Finishing encoding (\(frameIndex) frames)")

        // Mark input as finished
        input.markAsFinished()

        // Finalize writing (synchronous via semaphore)
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        writer.finishWriting {
            if writer.status == .completed {
                GD.print("[VideoEncoder] Encoding finished: \(self.outputPath)")
                success = true
            } else {
                let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
                GD.print("[VideoEncoder] Encoding failed during finalization: \(errorMsg)")
            }
            semaphore.signal()
        }

        semaphore.wait()

        encoding = false

        if success {
            encodingCompleted.emit(outputPath)
        } else {
            let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
            encodingFailed.emit("Failed to finish encoding: \(errorMsg)")
        }

        releaseResources()
        return success
    }

    /// Cancel encoding and delete the partial output file.
    /// - Returns: true if cancelled successfully
    @Callable
    func cancelEncoding() -> Bool {
        guard encoding else { return false }

        GD.print("[VideoEncoder] Cancelling encoding")

        assetWriter?.cancelWriting()
        releaseResources()
        encoding = false

        // Delete partial file
        if FileManager.default.fileExists(atPath: outputPath) {
            try? FileManager.default.removeItem(atPath: outputPath)
            GD.print("[VideoEncoder] Deleted partial file: \(outputPath)")
        }

        return true
    }

    /// Check if encoding is currently in progress.
    @Callable
    func isCurrentlyEncoding() -> Bool {
        return encoding
    }

    // MARK: - Audio Mux (replay SFX Phase 2)

    // Design: geofast_bmad/docs/projects/replay-sfx-ios-mux/design.md
    // iOS mirror of the Android muxAudioTrack: marries the replay mixer's PCM
    // WAV to an already-encoded MP4 IN PLACE. The video track is passed through
    // sample-by-sample (never re-encoded, the AVFoundation equivalent of
    // `-c:v copy`); the WAV is re-encoded to AAC-LC. The file at videoPath is
    // only replaced once the muxed temp is fully finalized, so ANY failure
    // leaves the original silent MP4 intact and returns false.

    /// Mux a PCM WAV audio track into the MP4 at videoPath, in place.
    /// - Parameters:
    ///   - videoPath: Already-encoded MP4 (video-only) to receive the track
    ///   - wavPath: 16-bit mono PCM WAV of exactly the video's duration
    ///   - bitrateKbps: AAC bitrate in kbit/s (from ReplayRenderConfig)
    /// - Returns: true only if videoPath now carries the audio track
    @Callable
    func muxAudioTrack(videoPath: String, wavPath: String, bitrateKbps: Int) -> Bool {
        if encoding {
            GD.print("[VideoEncoder] muxAudioTrack called while encoding — rejected")
            return false
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: videoPath), fm.fileExists(atPath: wavPath), bitrateKbps > 0 else {
            GD.print("[VideoEncoder] muxAudioTrack: bad input (video/wav missing or kbps <= 0)")
            return false
        }

        let videoURL = URL(fileURLWithPath: videoPath)
        let tempURL = videoURL.deletingPathExtension()
            .appendingPathExtension("sfx.tmp.mp4")
        let bakURL = URL(fileURLWithPath: videoPath + ".bak")
        try? fm.removeItem(at: tempURL)

        guard writeMuxedFile(videoURL: videoURL, wavURL: URL(fileURLWithPath: wavPath),
                             outURL: tempURL, bitrateKbps: bitrateKbps) else {
            try? fm.removeItem(at: tempURL)
            return false
        }
        let muxedSize = (try? fm.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
        guard (muxedSize ?? 0) > 0 else {
            GD.print("[VideoEncoder] muxAudioTrack: muxed temp file is empty")
            try? fm.removeItem(at: tempURL)
            return false
        }

        // Original-preserving swap: the silent MP4 is recoverable at every step.
        try? fm.removeItem(at: bakURL)
        do {
            try fm.moveItem(at: videoURL, to: bakURL)
        } catch {
            GD.print("[VideoEncoder] muxAudioTrack: could not stage original — \(error.localizedDescription)")
            try? fm.removeItem(at: tempURL)
            return false
        }
        do {
            try fm.moveItem(at: tempURL, to: videoURL)
        } catch {
            try? fm.moveItem(at: bakURL, to: videoURL)  // restore
            GD.print("[VideoEncoder] muxAudioTrack: swap failed, original restored — \(error.localizedDescription)")
            try? fm.removeItem(at: tempURL)
            return false
        }
        try? fm.removeItem(at: bakURL)
        GD.print("[VideoEncoder] muxAudioTrack: audio track muxed into \(videoPath)")
        return true
    }

    /// Write outURL = video track (passthrough copy) + AAC-encoded WAV.
    /// Synchronous: the caller is already on a Godot worker thread.
    private func writeMuxedFile(videoURL: URL, wavURL: URL, outURL: URL, bitrateKbps: Int) -> Bool {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: wavURL)
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
            GD.print("[VideoEncoder] muxAudioTrack: no video track in source")
            return false
        }
        guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else {
            GD.print("[VideoEncoder] muxAudioTrack: no audio track in WAV")
            return false
        }

        do {
            let reader = try AVAssetReader(asset: videoAsset)
            let audioReader = try AVAssetReader(asset: audioAsset)
            let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

            // Video: outputSettings nil on BOTH sides = sample passthrough, no re-encode.
            let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            guard reader.canAdd(videoOut) else { return false }
            reader.add(videoOut)
            let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                             sourceFormatHint: videoTrack.formatDescriptions.first as! CMFormatDescription?)
            videoIn.expectsMediaDataInRealTime = false
            guard writer.canAdd(videoIn) else { return false }
            writer.add(videoIn)

            // Audio: decode the WAV to LPCM, encode to AAC-LC on the way out.
            let pcmSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let audioOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcmSettings)
            guard audioReader.canAdd(audioOut) else { return false }
            audioReader.add(audioOut)

            let audioDesc = audioTrack.formatDescriptions.first as! CMAudioFormatDescription?
            let asbd = audioDesc.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            let aacSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: asbd?.mSampleRate ?? 44100,
                AVNumberOfChannelsKey: Int(asbd?.mChannelsPerFrame ?? 1),
                AVEncoderBitRateKey: bitrateKbps * 1000,
            ]
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
            audioIn.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioIn) else { return false }
            writer.add(audioIn)

            guard writer.startWriting(), reader.startReading(), audioReader.startReading() else {
                GD.print("[VideoEncoder] muxAudioTrack: reader/writer failed to start")
                return false
            }
            writer.startSession(atSourceTime: .zero)

            let queue = DispatchQueue(label: "com.geofast.videoencoder.mux")
            let group = DispatchGroup()
            group.enter()
            videoIn.requestMediaDataWhenReady(on: queue) {
                while videoIn.isReadyForMoreMediaData {
                    guard let buf = videoOut.copyNextSampleBuffer() else {
                        videoIn.markAsFinished(); group.leave(); return
                    }
                    videoIn.append(buf)
                }
            }
            group.enter()
            audioIn.requestMediaDataWhenReady(on: queue) {
                while audioIn.isReadyForMoreMediaData {
                    guard let buf = audioOut.copyNextSampleBuffer() else {
                        audioIn.markAsFinished(); group.leave(); return
                    }
                    audioIn.append(buf)
                }
            }
            group.wait()

            guard reader.status != .failed, audioReader.status != .failed else {
                GD.print("[VideoEncoder] muxAudioTrack: read failed — \(reader.error?.localizedDescription ?? audioReader.error?.localizedDescription ?? "unknown")")
                writer.cancelWriting()
                return false
            }

            let semaphore = DispatchSemaphore(value: 0)
            var ok = false
            writer.finishWriting {
                ok = writer.status == .completed
                if !ok {
                    GD.print("[VideoEncoder] muxAudioTrack: write failed — \(writer.error?.localizedDescription ?? "unknown")")
                }
                semaphore.signal()
            }
            semaphore.wait()
            return ok
        } catch {
            GD.print("[VideoEncoder] muxAudioTrack threw: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Methods

    /// Create a CVPixelBuffer from raw RGBA bytes.
    /// Godot provides RGBA (R first), but CVPixelBuffer uses BGRA, so we swap channels.
    /// Uses Accelerate vImage for SIMD-optimized channel permutation with zero-copy
    /// access to PackedByteArray via withUnsafeConstAccessToData.
    private func createPixelBuffer(from rgbaBytes: PackedByteArray) -> CVPixelBuffer? {
        let byteCount = videoWidth * videoHeight * 4
        guard rgbaBytes.count == byteCount else {
            GD.print("[VideoEncoder] RGBA byte count mismatch: expected \(byteCount), got \(rgbaBytes.count)")
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            videoWidth,
            videoHeight,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            GD.print("[VideoEncoder] Failed to create CVPixelBuffer: \(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            GD.print("[VideoEncoder] Failed to get pixel buffer base address")
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let srcBytesPerRow = videoWidth * 4

        // Zero-copy access to PackedByteArray's underlying Godot memory
        let success: Bool? = rgbaBytes.withUnsafeConstAccessToData { srcPtr, count in
            // Use vImage to do RGBA → BGRA channel permutation (SIMD-optimized)
            var srcBuffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: srcPtr),
                height: vImagePixelCount(self.videoHeight),
                width: vImagePixelCount(self.videoWidth),
                rowBytes: srcBytesPerRow
            )

            var dstBuffer = vImage_Buffer(
                data: baseAddress,
                height: vImagePixelCount(self.videoHeight),
                width: vImagePixelCount(self.videoWidth),
                rowBytes: bytesPerRow
            )

            // Permute map: RGBA[0,1,2,3] → BGRA[2,1,0,3]
            let permuteMap: [UInt8] = [2, 1, 0, 3]
            let vErr = vImagePermuteChannels_ARGB8888(&srcBuffer, &dstBuffer, permuteMap, vImage_Flags(kvImageNoFlags))
            return vErr == kvImageNoError
        }

        guard success == true else {
            GD.print("[VideoEncoder] vImage permute failed or could not access PackedByteArray data")
            return nil
        }

        return buffer
    }

    /// Release all encoding resources.
    private func releaseResources() {
        writerInput = nil
        pixelBufferAdaptor = nil
        assetWriter = nil
        lastPixelBuffer = nil
    }
}
