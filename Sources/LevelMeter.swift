import Foundation
import AVFoundation

final class LevelMeter {
    var levelUpdate: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var running = false

    func start() {
        guard !running else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("LevelMeter: invalid input format \(format)")
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.computeLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.levelUpdate?(level)
            }
        }

        do {
            try engine.start()
            running = true
        } catch {
            print("Audio engine start failed: \(error)")
        }
    }

    func stop() {
        guard running else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        running = false
    }

    private func computeLevel(buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0, buffer.format.channelCount > 0 else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        var rms: Float = 0

        if let channelData = buffer.floatChannelData {
            var sum: Float = 0
            for channel in 0..<channelCount {
                let data = channelData[channel]
                for i in 0..<frames {
                    let sample = data[i]
                    sum += sample * sample
                }
            }
            rms = sqrt(sum / Float(frames * channelCount))
        } else if let int16Data = buffer.int16ChannelData {
            var sum: Float = 0
            for channel in 0..<channelCount {
                let data = int16Data[channel]
                for i in 0..<frames {
                    let sample = Float(data[i]) / 32768.0
                    sum += sample * sample
                }
            }
            rms = sqrt(sum / Float(frames * channelCount))
        } else if let int32Data = buffer.int32ChannelData {
            var sum: Float = 0
            for channel in 0..<channelCount {
                let data = int32Data[channel]
                for i in 0..<frames {
                    let sample = Float(data[i]) / 2147483648.0
                    sum += sample * sample
                }
            }
            rms = sqrt(sum / Float(frames * channelCount))
        }

        let db = 20 * log10(max(rms, 0.0000001))
        // Map -60 dBFS -> 0, 0 dBFS -> 1 with a little headroom.
        return min(max((db + 60) / 60, 0), 1)
    }
}
