import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    let audio: YouTubeAudio

    @StateObject private var streamer = AudioStreamer()
    @State private var previewTime: Double? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with overlaid text
            if let thumbnailURL = audio.thumbnailURL {
                ZStack {
                    ThumbnailImage(urlString: thumbnailURL, originalURLString: audio.originalURL)
                        .frame(height: 100)
                        .clipped()
                        .opacity(0.7)
                    
                    VStack(spacing: 4) {
                        Text(audio.title ?? "Untitled")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                        
                        if let uploader = audio.uploader {
                            Text(uploader)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }
                    }
                }
            } else {
                // Fallback when no thumbnail
                VStack(spacing: 4) {
                    Text(audio.title ?? "Untitled")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let uploader = audio.uploader {
                        Text(uploader)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            

            // Custom draggable seek slider
            VStack(spacing: 4) {
                CustomSeekSlider(
                    currentTime: streamer.currentTime,
                    duration: streamer.duration,
                    onScrubPreview: { time in
                        previewTime = time
                    },
                    onSeek: { time in
                        streamer.seekTo(time: time)
                        previewTime = nil
                    }
                )
                .frame(height: 20)
                
                HStack {
                    Text(formatTime(previewTime ?? streamer.currentTime)).font(.caption2)
                    Spacer()
                    if streamer.isBuffering {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    Spacer()
                    Text(formatTime(streamer.duration)).font(.caption2)
                }
            }

            HStack(spacing: 16) {
                Button(action: { streamer.toggle() }) {
                    Image(systemName: streamer.isPlaying ? "pause.fill" : "play.fill")
                }
                .tint(.accentColor)
            }
        }
        .onAppear { configureAndPlay() }
        .onDisappear { streamer.stop() }
    }

    private func configureAndPlay() {
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
                streamer.startStreaming(from: localURL, title: audio.title, artist: audio.uploader, artworkURL: URL(string: audio.thumbnailURL ?? ""), expectedDuration: expected)
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
        streamer.startStreaming(from: url, title: audio.title, artist: audio.uploader, artworkURL: URL(string: audio.thumbnailURL ?? ""), expectedDuration: expected)
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
        streamer.startStreaming(from: url, title: audio.title, artist: audio.uploader, artworkURL: URL(string: audio.thumbnailURL ?? ""), expectedDuration: expected)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
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
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    
    private var displayProgress: Double {
        isDragging ? dragProgress : progress
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
                        onSeek(seekTime)
                        
                        // Add a small delay before resetting drag state to prevent visual jump
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDragging = false
                        }
                    }
            )
        }
    }
}



