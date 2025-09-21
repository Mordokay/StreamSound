import SwiftUI
import UIKit

struct MarqueeText: View {
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
    
    static private let defaultSeparation = " **** "
    static private let defaultScrollDurationFactor: CGFloat = 0.02
    
    init(_ text: String,
         font: UIFont = .systemFont(ofSize: 14),
         separation: String = defaultSeparation,
         scrollDurationFactor: CGFloat = defaultScrollDurationFactor) {
        self.text = text
        self.font = font
        self.separation = separation
        self.scrollDurationFactor = scrollDurationFactor
    }
    
    init(_ text: String,
         textStyle: UIFont.TextStyle,
         separation: String = defaultSeparation,
         scrollDurationFactor: CGFloat = defaultScrollDurationFactor) {
        self.init(text, font: .preferredFont(forTextStyle: textStyle), separation: separation, scrollDurationFactor: scrollDurationFactor)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let shouldAnimated = shouldAnimated(geometry.size.width)
            
            scrollItem(offset: self.animate ? -stringWidth : 0)
                .onAppear() {
                    size = geometry.size
                    if shouldAnimated {
                        self.animate = true
                    }
                }
            
            if shouldAnimated {
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
            .frame(height: 15)
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
