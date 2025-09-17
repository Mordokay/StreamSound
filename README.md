# StreamSound - Apple Watch YouTube Audio Player

A personal Apple Watch app for streaming YouTube audio content during workouts, runs, or any activity where you want hands-free audio playback.

## Features

### 🎵 Audio Streaming

- **Stream YouTube audio directly** - No downloads required, streams in real-time
- **Background playback** - Audio continues playing when screen is off or app is backgrounded
- **Custom seek controls** - Tap or drag to jump to any position in the audio
- **Now Playing integration** - Shows in Control Center and supports remote commands

### 📱 Watch-Optimized Interface

- **Compact list view** - Shows video thumbnails, titles, and durations
- **Custom draggable slider** - Designed specifically for Apple Watch touch interaction
- **Visual feedback** - Thumbnail overlays with semi-transparent text backgrounds
- **One-handed operation** - Easy to use while running or exercising

### 🔗 Easy Content Management

- **Paste YouTube URLs** - Full URLs or just video IDs (e.g., `VDYbRBbAVak`)
- **Auto-refresh expired streams** - Automatically fetches new stream URLs when needed
- **Persistent storage** - Uses SwiftData to save your audio library
- **Swipe to delete** - Remove videos you no longer need

## Technical Architecture

### Core Components

#### Models

- **`YouTubeAudioInfo`** - Decodes JSON response from your server
- **`YouTubeAudio`** - SwiftData model for persistent storage
- **`AudioStreamer`** - Handles AVPlayer, background audio, and Now Playing metadata

#### Views

- **`MainListView`** - Home screen with paste field and video list
- **`AudioPlayerView`** - Full-screen player with custom controls
- **`ThumbnailImage`** - Handles WebP fallback for YouTube thumbnails
- **`CustomSeekSlider`** - Watch-optimized draggable progress control

#### Services

- **`YouTubeAudioService`** - Fetches stream info from your server endpoint

### Key Features Implementation

#### Background Audio

```swift
// Configure for background playback
try session.setCategory(.playback, mode: .spokenAudio, options: [])
try session.setActive(true)
```

#### Custom Seek Slider

- Uses `DragGesture` with relative translation instead of absolute positioning
- Handles both tap-to-seek and drag-to-scrub interactions
- Accounts for thumb radius to prevent visual misalignment

#### Thumbnail Fallback

- Tries WebP URL first
- Falls back to JPEG variants (`maxresdefault.jpg`, `hqdefault.jpg`, `mqdefault.jpg`)
- Extracts video ID from original URL for fallback generation

## Server Requirements

The app requires a server endpoint that extracts YouTube audio stream information. I included in the repository the python script I used (yt_audio_info.py) for fetching this information:

### Required Tools on the Server

- `yt-dlp` (YouTube extractor)
- `ffmpeg` (recommended for muxing/remuxing and HLS support)

Install on macOS using Homebrew:

```bash
brew install yt-dlp ffmpeg
```

Install on Linux (Debian/Ubuntu):

```bash
sudo apt update && sudo apt install -y ffmpeg
python3 -m pip install --upgrade yt-dlp
```

### Endpoint

```
GET https://your-domain.com/cgi-bin/yt_audio_info.py?url={youtube_url}
```

### Expected Response

```json
{
  "ok": true,
  "title": "Video Title",
  "uploader": "Channel Name",
  "duration": 966,
  "ext": "m4a",
  "stream_url": "https://...",
  "thumbnail_url": "https://i.ytimg.com/vi/.../maxresdefault.jpg",
  "shortDescription": "Video description...",
  "expire_ts": 1758123253,
  "expire_human": "2025-09-17T16:34:13",
  "original_url": "https://www.youtube.com/watch?v=...",
  "prefer_hls": false
}
```

### Server Setup

1. **HTTPS Required** - Apple requires secure connections for production
2. **Complete Certificate Chain** - Include intermediate certificates for proper TLS validation
3. **CORS Headers** - If needed for web-based testing

## Installation & Setup

### Prerequisites

- Xcode 15.0+
- watchOS 10.0+
- Apple Watch (Series 4 or later recommended)

### Build Steps

1. Clone the repository
2. Open `StreamSound.xcodeproj` in Xcode
3. Update the server endpoint in `YouTubeAudioService.swift`:
   ```swift
   private let baseEndpoint = "https://your-domain.com/cgi-bin/yt_audio_info.py"
   ```
4. Build and run on your Apple Watch

### Background Audio Setup

1. In Xcode, select your Watch app target
2. Go to **Signing & Capabilities**
3. Add **Background Modes**
4. Enable **Audio, AirPlay, and Picture in Picture**

## Usage

### Adding Videos

1. **Copy a YouTube URL** from your iPhone or any source
2. **Paste it** into the text field on the watch
3. **Tap the + button** to fetch and save the audio
4. **Alternative**: Just paste the video ID (11 characters) for faster entry

### Playing Audio

1. **Tap any video** in the list to open the player
2. **Tap play/pause** to control playback
3. **Drag the slider** to seek to any position
4. **Tap the slider** to jump to a specific time
5. **Use Control Center** for background controls

### Managing Your Library

- **Swipe left** on any video to delete it
- **Pull down** to refresh the list
- Videos are automatically saved and persist between app launches

## Customization

### Server Endpoint

Update the base URL in `YouTubeAudioService.swift`:

```swift
private let baseEndpoint = "https://your-server.com/endpoint"
```

### UI Adjustments

- **Thumbnail size**: Modify `.frame(width: 50, height: 50)` in `MainListView`
- **Slider appearance**: Adjust colors and sizing in `CustomSeekSlider`
- **Text styling**: Change fonts and colors throughout the views

### Audio Settings

- **Skip intervals**: Modify `preferredIntervals = [15]` in `AudioStreamer`
- **Buffer settings**: Adjust `addPeriodicTimeObserver` interval
- **Session category**: Change `.spokenAudio` to `.default` if needed

## Troubleshooting

### Common Issues

#### "TLS error caused the secure connection to fail"

- Ensure your server has a complete SSL certificate chain
- Test with SSL Labs: https://www.ssllabs.com/ssltest/
- Check that intermediate certificates are included

#### Thumbnails not loading

- The app automatically falls back from WebP to JPEG
- Check that your server returns valid `thumbnail_url` values
- Verify network connectivity on the watch

#### Audio not playing in background

- Ensure Background Modes → Audio is enabled
- Check that `AVAudioSession` is configured for `.playback`
- Verify the app has proper entitlements

#### Duration showing double

- The app prioritizes server-reported duration over AVFoundation
- Check that your server returns accurate duration values
- Debug with the console logs in `AudioStreamer`

### Debug Information

Enable debug logging by checking the console output:

- Duration loading: `DEBUG: Loaded duration: X seconds`
- Stream refresh: `DEBUG: Setting duration to X`
- Network errors: Check for HTTP status codes and error messages

## Contributing

This is a personal project, but suggestions and improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on actual Apple Watch hardware
5. Submit a pull request

## License

This project is for personal use. Please respect YouTube's Terms of Service and any applicable copyright laws when using this app.

## Acknowledgments

- Built with SwiftUI and AVFoundation
- Uses SwiftData for persistence
- Inspired by the need for hands-free audio during workouts
- Server integration for YouTube stream extraction

---

**Note**: This app is designed for personal use and requires your own server infrastructure to extract YouTube audio streams. Ensure compliance with YouTube's Terms of Service and applicable laws in your jurisdiction.
