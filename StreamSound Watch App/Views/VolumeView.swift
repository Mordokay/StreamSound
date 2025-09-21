import SwiftUI
import WatchKit

/// A SwiftUI wrapper for WKInterfaceVolumeControl to enable crown-based volume control
struct VolumeView: WKInterfaceObjectRepresentable {
    typealias WKInterfaceObjectType = WKInterfaceVolumeControl
    
    func makeWKInterfaceObject(context: Self.Context) -> WKInterfaceVolumeControl {
        let view = WKInterfaceVolumeControl(origin: .local)
        
        // Set up a timer to keep the volume control focused
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak view] timer in
            if let view = view {
                view.focus()
            } else {
                timer.invalidate()
            }
        }
        
        // Focus immediately
        DispatchQueue.main.async {
            view.focus()
        }
        
        return view
    }
    
    func updateWKInterfaceObject(_ wkInterfaceObject: WKInterfaceVolumeControl, context: WKInterfaceObjectRepresentableContext<VolumeView>) {
        // No updates needed - the volume control manages its own state
    }
}
