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
    private var stalledTickCount: Int = 0
    private var didScheduleSessionRetry: Bool = false

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        // Check if session is already configured correctly
        if session.category == .playback && session.mode == .spokenAudio && session.isOtherAudioPlaying == false {
            // Try to activate without deactivating first
            do {
                try session.setActive(true, options: [])
                print("DEBUG: Successfully activated existing session")
                return
            } catch {
                print("DEBUG: Failed to activate existing session, will reconfigure: \(error)")
            }
        }
        
        // Deactivate first to ensure clean state
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            print("DEBUG: Deactivated existing session before reconfiguring")
            // Longer delay to let the system clean up
            Thread.sleep(forTimeInterval: 0.5)
        } catch {
            print("DEBUG: Deactivation failed (may not have been active): \(error)")
        }
        
        // Configure and activate
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        
        // Try activation with different options
        do {
            try session.setActive(true, options: [])
            print("DEBUG: Successfully configured and activated AVAudioSession")
        } catch {
            // If that fails, try without options
            try session.setActive(true)
            print("DEBUG: Successfully activated AVAudioSession without options")
        }
    }

    func startStreaming(from url: URL, title: String?, artist: String?, artworkURL: URL?, expectedDuration: Double? = nil) {
        print("DEBUG: Starting stream from URL: \(url)")
        do { try configureSession() } catch { 
            print("DEBUG: Failed to configure session: \(error)")
            scheduleSessionActivationRetry()
        }

        // Stop and clear previous player
        stop()
        
        // Reset all state
        duration = expectedDuration ?? 0
        currentTime = 0
        isBuffering = true
        isPlaying = false
        
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = false
        player?.volume = 1.0

        addPeriodicTimeObserver()
        observeBuffering(for: item)
        setupRemoteCommands()
        updateNowPlaying(title: title, artist: artist, artworkURL: artworkURL)

        print("DEBUG: Calling player.play() (timeControlStatus=\(player?.timeControlStatus.rawValue ?? -1))")
        player?.play()
        isPlaying = true
        print("DEBUG: Player state - isPlaying: \(isPlaying), player: \(player != nil)")
    }

    func toggle() {
        guard let player else { 
            print("DEBUG: Toggle called but no player")
            return 
        }
        print("DEBUG: Toggle - was playing: \(isPlaying)")
        if isPlaying { 
            player.pause() 
            print("DEBUG: Paused player")
        } else { 
            // Check if we're at the end of the audio
            if duration > 0 && currentTime >= duration - 0.5 {
                print("DEBUG: At end of audio, restarting from beginning")
                seekTo(time: 0)
            }
            player.play() 
            print("DEBUG: Started player")
        }
        isPlaying.toggle()
        print("DEBUG: Toggle - now playing: \(isPlaying)")
        updatePlaybackState()
    }

    func seek(by seconds: Double) {
        guard let item = player?.currentItem else { return }
        let current = item.currentTime()
        let newTime = current.seconds + seconds
        
        // If we're at the end and trying to skip forward, restart from beginning
        if duration > 0 && currentTime >= duration - 0.5 && seconds > 0 {
            print("DEBUG: At end of audio, restarting from beginning")
            seekTo(time: 0)
            return
        }
        
        let target = CMTime(seconds: max(0, newTime), preferredTimescale: 1)
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
        
        // Force deactivate session to ensure clean state for next use
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            print("DEBUG: Force deactivated session on stop")
        } catch {
            print("DEBUG: Failed to deactivate session on stop: \(error)")
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("DEBUG: Stopped playback and deactivated session")
    }
    
    func forceStop() {
        player?.pause()
        isPlaying = false
        clearObservers()
        
        // Force deactivate session - only use this when completely done with audio
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            print("DEBUG: Force deactivated AVAudioSession")
        } catch {
            print("DEBUG: Failed to force deactivate AVAudioSession: \(error)")
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func addPeriodicTimeObserver() {
        clearObservers()
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            guard let self else { return }
            let tcs = self.player?.timeControlStatus.rawValue ?? -1
            print("DEBUG: Time observer - currentTime: \(time.seconds), isPlaying: \(self.isPlaying), timeControlStatus: \(tcs)")
            
            // Cap currentTime to duration to prevent going over
            let cappedTime = min(time.seconds, self.duration)
            self.currentTime = cappedTime
            
            // Check if we've reached the end of the audio
            if self.duration > 0 && cappedTime >= self.duration - 0.5 { // 0.5 second tolerance
                print("DEBUG: Reached end of audio, pausing playback")
                self.player?.pause()
                self.isPlaying = false
                self.updatePlaybackState()
            }
            
            self.updatePlaybackState()

            // If player claims to be playing but time is stuck near 0, try to kick it
            if self.isPlaying {
                if time.seconds < 0.1 {
                    self.stalledTickCount += 1
                } else {
                    self.stalledTickCount = 0
                }
                if self.stalledTickCount >= 3 { // ~3 seconds without progress
                    print("DEBUG: Detected stalled playback at 0s. Retrying play().")
                    self.player?.play()
                    self.stalledTickCount = 0
                }
            }
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
            print("DEBUG: Item status changed to: \(item.status.rawValue)")
            switch item.status {
            case .readyToPlay:
                print("DEBUG: Item ready to play")
                self.isBuffering = false
                if self.player?.timeControlStatus != .playing {
                    self.scheduleSessionActivationRetry()
                    self.player?.play()
                }
            case .failed:
                print("DEBUG: Item failed to load: \(item.error?.localizedDescription ?? "Unknown error")")
                self.isBuffering = true
            case .unknown:
                print("DEBUG: Item status unknown")
                self.isBuffering = true
            @unknown default:
                print("DEBUG: Item status unknown default")
                self.isBuffering = true
            }
        }

        bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] _, change in
            if let empty = change.newValue, empty == true { 
                print("DEBUG: Buffer empty")
                self?.isBuffering = true 
            }
        }
        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] _, change in
            if let keepUp = change.newValue, keepUp == true { 
                print("DEBUG: Playback likely to keep up")
                self?.isBuffering = false 
            }
        }
    }

    private func scheduleSessionActivationRetry() {
        guard didScheduleSessionRetry == false else { return }
        didScheduleSessionRetry = true
        Task { [weak self] in
            defer { self?.didScheduleSessionRetry = false }
            
            // Wait longer before first attempt to let system recover
            try? await Task.sleep(nanoseconds: 2000_000_000) // Wait 2s
            
            for attempt in 1...3 {
                do {
                    try self?.configureSession()
                    print("DEBUG: AVAudioSession activation retry succeeded (attempt \(attempt))")
                    self?.player?.play()
                    return
                } catch {
                    print("DEBUG: AVAudioSession activation retry failed (attempt \(attempt)): \(error)")
                    
                    // If it's a resource not available error, wait longer
                    if let nsError = error as NSError?, nsError.code == 561145203 {
                        let delay = UInt64(3000_000_000) * UInt64(attempt) // Wait 3s, 6s, 9s
                        try? await Task.sleep(nanoseconds: delay)
                    } else {
                        let delay = UInt64(1000_000_000) * UInt64(attempt) // Wait 1s, 2s, 3s
                        try? await Task.sleep(nanoseconds: delay)
                    }
                }
            }
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

