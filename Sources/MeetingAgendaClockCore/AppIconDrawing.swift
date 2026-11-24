import CoreGraphics
import CoreText
import Foundation

/// Draws the app icon's artwork: marks on a clear background, one image per layer of the Icon
/// Composer file. `scripts/render-icon.sh` turns them into `Resources/AppIcon.icon`, and the
/// system adds the near-black background, the rounded shape, and the glass.
///
/// Every design uses the app's own segmented section bar, the weekly demo's 5, 5, 20, and 10
/// minutes, filled through 18 of its 40 minutes: Intro and Context done, Demo under way.
///
/// There are four designs, for choosing. `shipped` is the one in the app.
public enum AppIconDrawing {
    /// The side of the square canvas, in pixels. Icon Composer's canvas for a Mac icon.
    public static let canvas: CGFloat = 1024

    /// The design in `Resources/AppIcon.icon`. To ship another, change this one line and run
    /// `scripts/render-icon.sh`.
    public static let shipped = Design.segmentRing

    public enum Design: Int, CaseIterable, Sendable {
        /// A clock ring whose rim is the segmented bar bent into a circle, partly filled,
        /// nothing in the middle.
        case segmentRing = 1
        /// The same ring with one clock hand pointing at now, where the fill ends.
        case ringWithHand = 2
        /// Big fixed-width digits with the flat segmented bar under them, as the clock window looks.
        case digitsAndBar = 3
        /// The sections as an agenda: four bars, one under the other, as long as their minutes
        /// and laid end to end in time, with a now line through them in the overtime color.
        case agendaTimeline = 4

        public var title: String {
            switch self {
            case .segmentRing: "Segmented ring"
            case .ringWithHand: "Ring with a hand"
            case .digitsAndBar: "Digits and bar"
            case .agendaTimeline: "Agenda timeline"
            }
        }

        /// The background gradient, top color first, as sRGB components: near-black.
        public var gradient: (top: [CGFloat], bottom: [CGFloat]) {
            ([0.17, 0.17, 0.18], [0.05, 0.05, 0.06])
        }

        /// The layers, front first, as Icon Composer lists them.
        public var layers: [Layer] {
            switch self {
            case .segmentRing:
                [Layer(name: "ring", draw: { AppIconDrawing.ring(in: $0) })]
            case .ringWithHand:
                [Layer(name: "hand", draw: AppIconDrawing.hand),
                 Layer(name: "ring", draw: { AppIconDrawing.ring(in: $0) })]
            case .digitsAndBar:
                [Layer(name: "digits", draw: AppIconDrawing.digits),
                 Layer(name: "bar", draw: AppIconDrawing.flatBar)]
            case .agendaTimeline:
                [Layer(name: "now", draw: AppIconDrawing.nowLine),
                 Layer(name: "sections", draw: AppIconDrawing.timeline)]
            }
        }
    }

    /// One layer of the icon: a name for its image, and a routine that draws it on a clear,
    /// canvas-sized context with y pointing up.
    public struct Layer: Sendable {
        public let name: String
        public let draw: @Sendable (CGContext) -> Void
    }

    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// The part of the bar still to come.
    static let track = CGColor(red: 1, green: 1, blue: 1, alpha: 0.26)
    /// The app's overtime color, used only for design 4's now line.
    static let overtime = CGColor(red: 1.0, green: 0.42, blue: 0.29, alpha: 1)

    /// The weekly demo's sections, in minutes.
    static let sections: [CGFloat] = [5, 5, 20, 10]
    static let total: CGFloat = 40
    /// How many minutes are filled.
    static let elapsed: CGFloat = 18

    static let center = CGPoint(x: 512, y: 512)

    // MARK: Ring

    static let ringRadius: CGFloat = 288
    static let ringWidth: CGFloat = 108
    /// The gap between segments along the ring's middle.
    static let ringGap: CGFloat = 44

    /// The angle, clockwise from twelve o'clock, of `minutes` into the agenda, in radians.
    static func angle(_ minutes: CGFloat) -> CGFloat { minutes / total * 2 * .pi }

    /// A point on a circle around the center, `clockwise` radians from twelve o'clock.
    static func point(_ clockwise: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * sin(clockwise), y: center.y + radius * cos(clockwise))
    }

    /// Strokes an arc from `from` to `to` (clockwise radians from twelve o'clock) with square
    /// ends, as the flat bar's segments are cut.
    static func arc(_ context: CGContext, from: CGFloat, to: CGFloat, color: CGColor) {
        guard to > from else { return }
        context.setStrokeColor(color)
        context.setLineWidth(ringWidth)
        context.setLineCap(.butt)
        // In CG's angles, counterclockwise from three o'clock with y up.
        context.addArc(center: center, radius: ringRadius,
                       startAngle: .pi / 2 - from, endAngle: .pi / 2 - to, clockwise: true)
        context.strokePath()
    }

    /// The segmented bar bent into a circle, starting at twelve o'clock and running clockwise.
    @Sendable static func ring(in context: CGContext) {
        // Each segment is shortened at both ends by half a gap.
        let inset = ringGap / 2 / ringRadius
        var start: CGFloat = 0
        for minutes in sections {
            let from = angle(start) + inset
            let to = angle(start + minutes) - inset
            let filledTo = min(to, max(from, angle(elapsed)))
            arc(context, from: from, to: to, color: track)
            if elapsed > start {
                arc(context, from: from, to: filledTo, color: white)
            }
            start += minutes
        }
    }

    /// One hand, from the center to just inside the ring, pointing at now.
    @Sendable static func hand(_ context: CGContext) {
        let tip = point(angle(elapsed), radius: ringRadius - ringWidth / 2 - 58)
        context.setStrokeColor(white)
        context.setLineWidth(56)
        context.setLineCap(.round)
        context.move(to: center)
        context.addLine(to: tip)
        context.strokePath()
        context.setFillColor(white)
        context.fillEllipse(in: CGRect(x: center.x - 60, y: center.y - 60, width: 120, height: 120))
    }

    // MARK: Digits and bar

    @Sendable static func digits(_ context: CGContext) {
        let font = digitFont(size: 236)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: white]
        guard let text = CFAttributedStringCreate(nil, "14:42" as CFString, attributes as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: center.x - bounds.midX, y: 470 - bounds.minY)
        CTLineDraw(line, context)
    }

    /// The system font, heavy, with fixed-width digits.
    static func digitFont(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let traits: [CFString: Any] = [kCTFontWeightTrait: 0.4]
        let features: [[CFString: Any]] = [[
            kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
            kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
        ]]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontTraitsAttribute: traits, kCTFontFeatureSettingsAttribute: features] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// The flat bar, with gaps, partly filled, `rect` wide.
    static func flatBar(_ context: CGContext, in rect: CGRect, gap: CGFloat) {
        let usable = rect.width - gap * CGFloat(sections.count - 1)
        var x = rect.minX
        var start: CGFloat = 0
        // Corners rounded less than half the height, so the short segments stay bars, not dots.
        let radius = rect.height * 0.3
        for minutes in sections {
            let width = usable * minutes / total
            let segment = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            context.saveGState()
            context.addPath(CGPath(roundedRect: segment, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            context.setFillColor(track)
            context.fill(segment)
            let filled = min(1, max(0, (elapsed - start) / minutes))
            context.setFillColor(white)
            context.fill(CGRect(x: x, y: rect.minY, width: width * filled, height: rect.height))
            context.restoreGState()
            x += width + gap
            start += minutes
        }
    }

    @Sendable static func flatBar(_ context: CGContext) {
        flatBar(context, in: CGRect(x: 190, y: 290, width: 644, height: 76), gap: 22)
    }

    // MARK: Agenda timeline

    static let timelineRect = CGRect(x: 196, y: 264, width: 632, height: 496)

    /// The x of `minutes` into the agenda along the timeline.
    static func timelineX(_ minutes: CGFloat) -> CGFloat {
        timelineRect.minX + timelineRect.width * minutes / total
    }

    @Sendable static func timeline(_ context: CGContext) {
        let rows = CGFloat(sections.count)
        let gap: CGFloat = 40
        let height = (timelineRect.height - gap * (rows - 1)) / rows
        var start: CGFloat = 0
        for (index, minutes) in sections.enumerated() {
            let x = timelineX(start)
            let width = timelineX(start + minutes) - x
            let y = timelineRect.maxY - height - CGFloat(index) * (height + gap)
            let bar = CGRect(x: x, y: y, width: width, height: height)
            context.saveGState()
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 28, cornerHeight: 28, transform: nil))
            context.clip()
            context.setFillColor(track)
            context.fill(bar)
            let filled = min(1, max(0, (elapsed - start) / minutes))
            context.setFillColor(white)
            context.fill(CGRect(x: x, y: y, width: width * filled, height: height))
            context.restoreGState()
            start += minutes
        }
    }

    @Sendable static func nowLine(_ context: CGContext) {
        let x = timelineX(elapsed)
        context.setStrokeColor(overtime)
        context.setLineWidth(34)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: x, y: timelineRect.minY - 30))
        context.addLine(to: CGPoint(x: x, y: timelineRect.maxY + 30))
        context.strokePath()
    }

    // MARK: Output

    /// Draws one layer on a clear canvas.
    public static func image(of layer: Layer) -> CGImage? {
        let size = Int(canvas)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        layer.draw(context)
        return context.makeImage()
    }

    /// The Icon Composer file's `icon.json` for a design, naming each layer's image as
    /// `<name>.png`.
    public static func iconJSON(for design: Design) -> String {
        func color(_ c: [CGFloat]) -> String {
            "srgb:" + (c + [1]).map { String(format: "%.5f", Double($0)) }.joined(separator: ",")
        }
        let layers = design.layers.map {
            """
                    {
                      "image-name" : "\($0.name).png",
                      "name" : "\($0.name)"
                    }
            """
        }.joined(separator: ",\n")
        return """
        {
          "fill" : {
            "linear-gradient" : [
              "\(color(design.gradient.top))",
              "\(color(design.gradient.bottom))"
            ]
          },
          "groups" : [
            {
              "layers" : [
        \(layers)
              ],
              "shadow" : {
                "kind" : "neutral",
                "opacity" : 0.5
              },
              "translucency" : {
                "enabled" : false,
                "value" : 0.5
              }
            }
          ],
          "supported-platforms" : {
            "squares" : [
              "macOS"
            ]
          }
        }

        """
    }
}
