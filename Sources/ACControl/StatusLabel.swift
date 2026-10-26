import AppKit
import ACControlCore

@MainActor
struct StatusLabelRenderer {
    private enum Part {
        case symbol(String)
        case text(String)
    }

    /// One template image keeps symbols and text monochrome on every menu-bar background.
    static func image(for model: AppModel) -> NSImage {
        var parts: [Part] = [.symbol(model.barSymbol)]
        if model.warning == nil, let snapshot = model.snapshot, let room = snapshot.room {
            if snapshot.isOn, let target = snapshot.target {
                parts += [.text(temperatureLabel(target) + " /"), .symbol("thermometer.medium"), .text(temperatureLabel(room))]
            } else { parts += [.text(temperatureLabel(room))] }
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let gap: CGFloat = 4
        let symbolWidth: CGFloat = 12
        let height: CGFloat = 18
        let widths: [CGFloat] = parts.map {
            switch $0 {
            case .symbol: symbolWidth
            case .text(let text): ceil((text as NSString).size(withAttributes: attributes).width)
            }
        }
        let size = NSSize(width: widths.reduce(0, +) + gap * CGFloat(max(0, parts.count - 1)), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (index, part) in parts.enumerated() {
                switch part {
                case .symbol(let name):
                    let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(paletteColors: [.black]))
                    icon?.draw(in: NSRect(x: x, y: 2, width: symbolWidth, height: 14))
                case .text(let text):
                    let textHeight = (text as NSString).size(withAttributes: attributes).height
                    (text as NSString).draw(at: NSPoint(x: x, y: (height - textHeight) / 2), withAttributes: attributes)
                }
                x += widths[index] + gap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = model.barHelp
        return image
    }
}
