import Foundation
import AVFoundation
import MediaPlayer
import Combine

final class AudioStreamer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isBuffering: Bool = true
    @Published var bufferProgress: Double = 0 // 0...1

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var bufferEmptyObserver: NSKeyValueObservation?
    private var likelyToKeepUpObserver: NSKeyValueObservation?

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }

    func startStreaming(from url: URL, title: String?, artist: String?, artworkURL: URL?, expectedDuration: Double? = nil) {
        do { try configureSession() } catch { }

        // Stop and clear previous player
        stop()
        
        // Reset all state
        duration = expectedDuration ?? 0
        currentTime = 0
        isBuffering = true
        isPlaying = false
        
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        addPeriodicTimeObserver()
        observeBuffering(for: item)
        setupRemoteCommands()
        updateNowPlaying(title: title, artist: artist, artworkURL: artworkURL)

        player?.play()
        isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updatePlaybackState()
    }

    func seek(by seconds: Double) {
        guard let item = player?.currentItem else { return }
        let current = item.currentTime()
        let target = CMTime(seconds: max(0, current.seconds + seconds), preferredTimescale: 1)
        player?.seek(to: target)
        currentTime = target.seconds
        updatePlaybackState()
    }
    
    func seekTo(time: Double) {
        guard let item = player?.currentItem else { return }
        let target = CMTime(seconds: time, preferredTimescale: 1)
        player?.seek(to: target)
        currentTime = time
        updatePlaybackState()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        clearObservers()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func addPeriodicTimeObserver() {
        clearObservers()
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            self.updatePlaybackState()
        }
        // Load duration using modern API to avoid deprecated `asset.duration`
        if let asset = player?.currentItem?.asset {
            Task { [weak self] in
                do {
                    let cmDuration = try await asset.load(.duration)
                    let seconds = cmDuration.seconds
                    print("DEBUG: Loaded duration: \(seconds) seconds from CMTime(\(cmDuration.value), \(cmDuration.timescale))")
                    if seconds.isFinite && seconds > 0 {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            // Prefer expected duration if provided; keep existing if already set from server
                            if self.duration <= 0 {
                                self.duration = seconds
                            }
                        }
                    }
                } catch {
                    print("DEBUG: Failed to load duration: \(error)")
                }
            }
        }
        // Update buffer progress periodically
        Task { [weak self] in
            while let self, let item = self.player?.currentItem {
                await MainActor.run { [weak self] in
                    self?.bufferProgress = self?.calculateBufferProgress(item: item) ?? 0
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func clearObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        itemStatusObserver = nil
        bufferEmptyObserver = nil
        likelyToKeepUpObserver = nil
    }

    private func observeBuffering(for item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                self.isBuffering = false
            case .failed, .unknown:
                self.isBuffering = true
            @unknown default:
                self.isBuffering = true
            }
        }

        bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] _, change in
            if let empty = change.newValue, empty == true { self?.isBuffering = true }
        }
        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] _, change in
            if let keepUp = change.newValue, keepUp == true { self?.isBuffering = false }
        }
    }

    private func calculateBufferProgress(item: AVPlayerItem) -> Double {
        guard duration > 0 else { return 0 }
        let ranges = item.loadedTimeRanges
        guard let timeRange = ranges.first?.timeRangeValue else { return 0 }
        let buffered = timeRange.start.seconds + timeRange.duration.seconds
        return max(0, min(1, buffered / duration))
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.handlePlay(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.handlePause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.seek(by: 15); return .success }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.seek(by: -15); return .success }
    }

    private func handlePlay() { player?.play(); isPlaying = true; updatePlaybackState() }
    private func handlePause() { player?.pause(); isPlaying = false; updatePlaybackState() }

    private func updateNowPlaying(title: String?, artist: String?, artworkURL: URL?) {
        var info: [String: Any] = [:]
        if let title { info[MPMediaItemPropertyTitle] = title }
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let artworkURL {
            // Lightweight async load; artwork is optional on watch
            URLSession.shared.dataTask(with: artworkURL) { data, _, _ in
                guard let data, let image = UIImage(data: data) else {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    return
                }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var updated = info
                updated[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }.resume()
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func updatePlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

