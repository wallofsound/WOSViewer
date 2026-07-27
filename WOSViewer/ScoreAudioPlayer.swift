import Foundation
import AVFoundation
import Combine

@MainActor
final class ScoreAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var segmentEnd: Double?
    private var sourceURL: URL?

    func prepare(url: URL?) {
        stop()
        sourceURL = url
        guard let url else {
            player = nil
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        } catch {
            player = nil
        }
    }

    func togglePlay(duration: Double) {
        guard player != nil else { return }
        if isPlaying {
            pause()
        } else {
            segmentEnd = duration
            play(from: currentTime > 0 && currentTime < duration - 0.05 ? currentTime : 0, to: duration)
        }
    }

    func play(from start: Double, to end: Double) {
        guard let player else { return }
        segmentEnd = end
        player.currentTime = max(0, start)
        currentTime = player.currentTime
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        segmentEnd = nil
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if let end = segmentEnd, currentTime >= end - 0.02 {
            pause()
            currentTime = end
            return
        }
        if !player.isPlaying {
            isPlaying = false
            stopTimer()
        }
    }
}
