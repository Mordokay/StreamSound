import SwiftUI
import AVFoundation
import Combine
import UIKit

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

    var body: some View {
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
            
            Spacer()
                .frame(width: 40, height: 3)
                .background(.green.opacity(0.3))
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
        .onAppear { configureAndPlay() }
        .onDisappear {
            streamer?.stop()
            streamer = nil // Clean up the instance
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



struct MarqueeText : View {
    private let text: String
    
    private let font: UIFont
    
    private let separation: String
    
    private let scrollDurationFactor: CGFloat
    
    @State private var animate = false
    
    @State private var size = CGSize.zero
    
    private var scrollDuration: CGFloat {
        stringWidth * scrollDurationFactor
    }
    
    private var stringWidth: CGFloat {
        (text + separation).widthOfString(usingFont: font)
    }
    
    private func shouldAnimated(_ width: CGFloat) -> Bool {
        width < stringWidth
    }
    
    static private let defaultSeparation = " ++++ "
    
    static private let defaultScrollDurationFactor: CGFloat = 0.02
    
    init(_ text: String,
         font: UIFont = .systemFont(ofSize: 14),
         separation: String = defaultSeparation,
         scrollDurationFactor: CGFloat = defaultScrollDurationFactor)         {
        self.text = text
        self.font = font
        self.separation = separation
        self.scrollDurationFactor = scrollDurationFactor
        self.animate = animate
    }
    
    init(_ text: String,
         textStyle: UIFont.TextStyle,
         separation: String = defaultSeparation,
         scrollDurationFactor: CGFloat = defaultScrollDurationFactor)
    {
        self.init(text, font: .systemFont(ofSize: 14), separation: separation, scrollDurationFactor: scrollDurationFactor)
    }
    
    var body : some View {
        GeometryReader { geometry in
            let shouldAnimated = shouldAnimated(geometry.size.width)
            
            scrollItem(offset: self.animate ? -stringWidth : 0)
                .onAppear() {
                    size = geometry.size
                    if shouldAnimated  {
                        self.animate = true
                    }
                }
            
            if shouldAnimated{
                scrollItem(offset: self.animate ? 0 : stringWidth)
            }
        }
    }
    
    private func scrollItem(offset: CGFloat) -> some View {
        Text(text + separation)
            .lineLimit(1)
            .font(Font(uiFont: font))
            .offset(x: offset, y: 0)
            .animation(Animation.linear(duration: scrollDuration).repeatForever(autoreverses: false), value: animate)
            .fixedSize(horizontal: true, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .center)
            .background(.black.opacity(0.4))
           
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
