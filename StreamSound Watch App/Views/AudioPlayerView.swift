import SwiftUI
import AVFoundation
import Combine
import UIKit
import WatchKit

struct AudioPlayerView: View {
    let audio: YouTubeAudio

    @State private var streamer: AudioStreamer?
    @State private var previewTime: Double? = nil
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying: Bool = false
    @State private var isBuffering: Bool = true
    @State private var textOffset: CGFloat = 300.0
    @State private var previousCurrentTime: Double = 0
    @State private var sliderResetTrigger: Int = 0
    
    // Volume control
    @State private var volume: Double = 0.5
    @State private var volumeObserver: NSKeyValueObservation?
    @State private var isCustomWatchVolumeSliderHidden: Bool = true
    @State private var controlsTimer: Timer? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                // Thumbnail with scrolling text
                if let thumbnailURL = audio.thumbnailURL {
                    ThumbnailImage(urlString: thumbnailURL, originalURLString: audio.originalURL)
                        .frame(height: 60)
                        .clipped()
                        .opacity(0.7)
                    
                    let displayText = "\(audio.uploader ?? "") - \(audio.title ?? "Untitled")"
                    MarqueeText(displayText, textStyle: .body, separation: " **** ")
                } else {
                    // Fallback when no thumbnail
                    let displayText = "\(audio.uploader ?? "") - \(audio.title ?? "Untitled")"
                    MarqueeText(displayText, textStyle: .body, separation: " **** ")
                }

                // Custom draggable seek slider
                VStack(spacing: 4) {
                    if streamer != nil {
                        CustomSeekSlider(
                            currentTime: currentTime,
                            duration: duration,
                            onScrubPreview: { time in
                                previewTime = time
                            },
                            onSeek: { time in
                                streamer?.seekTo(time: time)
                                previewTime = nil
                            }
                        )
                        .id(sliderResetTrigger)
                        .frame(height: 20)
                        
                        HStack {
                            Text(formatTime(previewTime ?? min(currentTime, duration))).font(.caption2)
                            Spacer()
                            if isBuffering {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                            Spacer()
                            Text(formatTime(duration)).font(.caption2)
                        }
                    } else {
                        // Loading state
                        ProgressView()
                            .frame(height: 20)
                    }
                }
                
                HStack(spacing: 4) {
                    if streamer != nil {
                        // Skip backward 10 seconds
                        Button(action: { streamer?.seek(by: -10) }) {
                            Image(systemName: "gobackward.10")
                        }
                        .tint(.accentColor)
                        
                        // Play/Pause button
                        Button(action: { streamer?.toggle() }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        }
                        .tint(.accentColor)
                        .font(.title2)
                        
                        // Skip forward 10 seconds
                        Button(action: { streamer?.seek(by: 10) }) {
                            Image(systemName: "goforward.10")
                        }
                        .tint(.accentColor)
                    }
                }
            }
            
            // Custom volume slider positioned on the right side
            HStack {
                Spacer()
                VStack {
                    CustomWatchVolumeSlider(volume: $volume)
                        .isHidden(isCustomWatchVolumeSliderHidden, remove: true)
                    Spacer()
                }
            }
            
            // Hidden volume control for crown input (opacity = 0)
            VolumeView()
                .opacity(0)
        }
        .onAppear { 
            configureAndPlay()
            setupVolumeObserver()
        }
        .onDisappear {
            streamer?.stop()
            streamer = nil // Clean up the instance
            volumeObserver?.invalidate()
            volumeObserver = nil
            controlsTimer?.invalidate()
            controlsTimer = nil
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateUIFromStreamer()
        }
    }

    private func configureAndPlay() {
        // Create a new AudioStreamer instance each time
        streamer = AudioStreamer()
        
        // Check if we have a local file first (handle filename-only storage)
        if let stored = audio.localFilePath {
            let localURL: URL
            if stored.hasPrefix("/") {
                localURL = URL(fileURLWithPath: stored)
            } else {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                localURL = docs.appendingPathComponent(stored)
            }
            print("DEBUG: Playing local file: \(localURL.path)")
            print("DEBUG: File exists: \(FileManager.default.fileExists(atPath: localURL.path))")
            print("DEBUG: File extension: \(localURL.pathExtension)")
            
            // Check if file is readable
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                print("DEBUG: File size: \(attributes[.size] as? Int64 ?? 0) bytes")
            } catch {
                print("DEBUG: Error reading file attributes: \(error)")
            }
            
            // Only play local if it actually exists
            if FileManager.default.fileExists(atPath: localURL.path) {
                let expected = audio.duration != nil ? Double(audio.duration!) : nil
                streamer?.startStreaming(from: localURL, title: audio.title, artist: audio.uploader, artworkURL: URL(string: audio.thumbnailURL ?? ""), expectedDuration: expected)
                return
            } else {
                print("DEBUG: Local file missing. Falling back to remote stream.")
            }
        }
        
        // Refresh expired streams if needed
        if let expire = audio.expireTS, Date(timeIntervalSince1970: TimeInterval(expire)) < .now {
            Task { await refreshAndPlay() }
            return
        }
        guard let urlString = audio.streamURL, let url = URL(string: urlString) else { return }
        let expected = audio.duration != nil ? Double(audio.duration!) : nil
        streamer?.startStreaming(from: url, title: audio.title, artist: audio.uploader, artworkURL: URL(string: audio.thumbnailURL ?? ""), expectedDuration: expected)
    }

    @MainActor
    private func refreshAndPlay() async {
        let service = YouTubeAudioService()
        let original = audio.originalURL
        do {
            let info = try await service.fetchInfo(for: original)
            if let updated = YouTubeAudio.from(info: info) {
                // Update current managed object in-place
                audio.streamURL = updated.streamURL
                audio.expireTS = updated.expireTS
                audio.expireHuman = updated.expireHuman
                // keep streamer duration preference via expectedDuration when starting
            }
        } catch {
            // If refresh fails, fall back to existing URL (may fail)
        }
        guard let urlString = audio.streamURL, let url = URL(string: urlString) else { return }
        let expected = audio.duration != nil ? Double(audio.duration!) : nil
        streamer?.startStreaming(from: url, title: audio.title, artist: audio.uploader, artworkURL: URL(string: audio.thumbnailURL ?? ""), expectedDuration: expected)
    }

    private func updateUIFromStreamer() {
        guard let streamer = streamer else { return }
        
        // Check if we've restarted (jumped from near end to beginning)
        let newCurrentTime = streamer.currentTime
        if previousCurrentTime > 0 && duration > 0 && 
           previousCurrentTime >= duration - 1.0 && newCurrentTime < 1.0 {
            // We've restarted from the end, reset slider state
            print("DEBUG: Detected restart, resetting slider state")
            sliderResetTrigger += 1
        }
        
        currentTime = newCurrentTime
        duration = streamer.duration
        isPlaying = streamer.isPlaying
        isBuffering = streamer.isBuffering
        previousCurrentTime = newCurrentTime
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
    
    private func setupVolumeObserver() {
        // Initialize volume from current system volume
        volume = Double(AVAudioSession.sharedInstance().outputVolume)
        
        // Set up volume observer with proper options
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) { session, change in
            
            print("DEBUG: Volume observer triggered - outputVolume: \(session.outputVolume)")
            
            // Update volume on main thread
            DispatchQueue.main.async {
                self.volume = Double(session.outputVolume)
                print("DEBUG: Volume updated to: \(self.volume)")
                self.handleVolumeSliderAppearance()
            }
        }
        
        print("DEBUG: Volume observer setup complete")
    }
    
    private func handleVolumeSliderAppearance() {
        // Ensure UI state changes occur on the main thread
        DispatchQueue.main.async {
            if self.isCustomWatchVolumeSliderHidden == false {
                self.controlsTimer?.invalidate()
                self.controlsTimer = nil
            }
            self.isCustomWatchVolumeSliderHidden = false

            // Schedule a one-shot timer on the main run loop to hide controls after delay
            let timer = Timer(timeInterval: 3, repeats: false) { _ in
                // Update UI on main thread
                DispatchQueue.main.async {
                    if self.isCustomWatchVolumeSliderHidden == false {
                        self.isCustomWatchVolumeSliderHidden = true
                    }
                    self.controlsTimer?.invalidate()
                    self.controlsTimer = nil
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.controlsTimer = timer
        }
    }
}

struct CustomSeekSlider: View {
    let currentTime: Double
    let duration: Double
    var onScrubPreview: ((Double) -> Void)? = nil
    let onSeek: (Double) -> Void
    
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var startProgress: Double = 0
    @State private var lastSeekTime: Double = 0
    @State private var isSeeking = false
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        // Cap currentTime to duration to prevent slider from going over 100%
        let cappedCurrentTime = min(currentTime, duration)
        return min(max(cappedCurrentTime / duration, 0), 1)
    }
    
    private var displayProgress: Double {
        if isDragging {
            return dragProgress
        } else if isSeeking {
            // After dragging, show the seeked position until currentTime catches up
            let seekProgress = lastSeekTime / duration
            let actualProgress = progress
            
            // If currentTime has caught up to the seeked time, stop seeking
            if abs(actualProgress - seekProgress) < 0.01 {
                DispatchQueue.main.async {
                    isSeeking = false
                }
            }
            
            return seekProgress
        } else {
            return progress
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let thumbDiameter: CGFloat = 16
            let thumbRadius: CGFloat = thumbDiameter / 2
            let trackWidth = max(1, geometry.size.width - thumbDiameter)
            let trackX = thumbRadius + trackWidth * displayProgress
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: trackWidth, height: 4)
                    .cornerRadius(2)
                    .offset(x: thumbRadius)
                
                // Progress track
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: trackWidth * displayProgress, height: 4)
                    .cornerRadius(2)
                    .offset(x: thumbRadius)
                
                // Thumb (no scale to avoid perceived drift). Add stroke when dragging instead
                Circle()
                    .fill(Color.blue)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: isDragging ? 2 : 0))
                    .offset(x: trackX - thumbRadius)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            // Start from current progress for smooth dragging
                            startProgress = displayProgress
                        }
                        // Use translation relative to start for smooth dragging
                        let delta = value.translation.width / trackWidth
                        let newProgress = max(0, min(1, startProgress + delta))
                        dragProgress = newProgress
                        onScrubPreview?(newProgress * duration)
                    }
                    .onEnded { value in
                        // Always use the translation-based calculation for consistent behavior
                        let delta = value.translation.width / trackWidth
                        let newProgress = max(0, min(1, startProgress + delta))
                        let seekTime = newProgress * duration
                        
                        // Store the seeked time and enter seeking state
                        lastSeekTime = seekTime
                        dragProgress = newProgress
                        isDragging = false
                        isSeeking = true
                        
                        // Perform the seek
                        onSeek(seekTime)
                        
                        // Reset seeking state after a short delay to allow currentTime to update
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSeeking = false
                        }
                    }
            )
        }
    }
}

private extension String {
    
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}

private extension Font {
    init(uiFont: UIFont) {
        self = Font(uiFont as CTFont)
    }
}
