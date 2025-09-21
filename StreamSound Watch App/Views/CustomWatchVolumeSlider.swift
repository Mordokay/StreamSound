import SwiftUI

/// Custom vertical volume slider for Apple Watch, inspired by Apple's Now Playing app
struct CustomWatchVolumeSlider: View {
    @Binding var volume: Double
    
    var body: some View {
        VStack(spacing: 2) {
            // Volume icon at the top
            Image(systemName: "speaker.3.fill")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Vertical slider track
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 8)
                    
                    // Progress track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: 8, height: geometry.size.height * volume)
                }
            }
            .frame(width: 8, height: 40)
            
            // Volume percentage at the bottom
            Text("\(Int(volume * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 40, height: 80)
        .background(.black.opacity(0.7))
        .cornerRadius(8)
    }
}

/// Extension to hide/show views based on boolean value
extension View {
    @ViewBuilder
    func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
        } else {
            self
        }
    }
}
