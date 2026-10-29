import Foundation
@preconcurrency import AVFoundation
import ShengJianCore

struct AudioChunk: Sendable {
    var start: Double
    var samples: [Float]
    var end: Double { start + Double(samples.count) / 16000 }
}

// All microphone PCM is transient memory. No audio file is ever opened or written.
final class AudioSink: @unchecked Sendable {
    let queue = DispatchQueue(label: "local.shengjian.microphone", qos: .userInitiated)
    private var converter: AVAudioConverter
    private var pending: [Float] = []
    private var cursor: Int64 = 0
    private var total: Int64 = 0
    private var level: Float = 0
    private var silence: Double = 0
    private var failure: String?
    private var stopped = false
    init(inputFormat: AVAudioFormat) throws {
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: output) else { throw AppError.message("麦克风音频格式无法转换。") }
        self.converter = converter
    }
    func accept(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            guard !stopped else { return }
            let count = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: count) else { return }
            var delivered = false
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { _, status in
                if delivered { status.pointee = .noDataNow; return nil }
                delivered = true; status.pointee = .haveData; return buffer
            }
            guard result != .error, error == nil, let data = output.floatChannelData?[0] else { failure = "麦克风格式转换失败，请停止录音后重试。"; return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            pending.append(contentsOf: samples); total += Int64(samples.count)
            let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
            level = min(1, rms * 12)
            silence = rms < 0.003 ? silence + Double(samples.count) / 16000 : 0
        }
    }
    func snapshot() async -> (Double, Float, String?) {
        await withCheckedContinuation { continuation in queue.async { continuation.resume(returning: (Double(self.total) / 16000, self.level, self.failure)) } }
    }
    func pull(interval: Double, force: Bool = false) async -> AudioChunk? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let seconds = Double(pending.count) / 16000
                guard pending.count > 0, force || (seconds >= interval && silence >= 0.45) || seconds >= interval + 5 else { continuation.resume(returning: nil); return }
                let count = min(pending.count, Int((interval + 5) * 16000))
                let chunk = AudioChunk(start: Double(cursor) / 16000, samples: Array(pending.prefix(count)))
                let overlap = !force && silence < 0.45 ? min(12800, count / 4) : 0
                pending.removeFirst(count - overlap); cursor += Int64(count - overlap)
                continuation.resume(returning: chunk)
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if !stopped {
                    // Finish resampling before releasing the microphone; the converter otherwise holds back its final frames.
                    for _ in 0..<8 {
                        let buffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 4096)!
                        var error: NSError?
                        let result = converter.convert(to: buffer, error: &error) { _, status in status.pointee = .endOfStream; return nil }
                        if result == .error || error != nil { failure = "结束录音时音频格式转换未完成。"; break }
                        if let data = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                            pending.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
                            total += Int64(buffer.frameLength)
                        }
                        if result == .endOfStream || buffer.frameLength == 0 { break }
                    }
                }
                stopped = true; level = 0; continuation.resume()
            }
        }
    }
    func signalFailure(_ message: String) { queue.async { self.failure = message } }
}

@MainActor final class Microphone {
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    var sink: AudioSink?
    func start() async throws -> AudioSink {
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        guard permitted else { throw AppError.message("请在系统设置 → 隐私与安全性 → 麦克风中允许声笺使用麦克风。") }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AppError.message("未找到可用的麦克风。") }
        let sink = try AudioSink(inputFormat: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (src, dst) in zip(source, target) {
                if let s = src.mData, let d = dst.mData { memcpy(d, s, Int(src.mDataByteSize)) }
            }
            sink.accept(copy)
        }
        do { engine.prepare(); try engine.start() }
        catch { input.removeTap(onBus: 0); throw error }
        self.engine = engine; self.sink = sink
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            sink.signalFailure("麦克风设备或采样率发生变化，录音已停止。请检查设备后重新录制。")
        }
        return sink
    }
    func stop() async {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        await sink?.stop()
    }
}
