import Foundation
import UIKit

/// A deliberately small native renderer for server-issued QR SVGs, not a browser/SVG engine.
/// No scripts, entities, stylesheets, fonts, links, images or external resources are accepted.
enum NativeQRSVG {
    static func image(_ data: Data) -> UIImage? {
        guard data.count <= 512 * 1024, let text = String(data: data, encoding: .utf8),
              !text.localizedCaseInsensitiveContains("<!DOCTYPE"), !text.localizedCaseInsensitiveContains("<!ENTITY") else { return nil }
        let delegate = QRParser()
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.failed, let bounds = delegate.bounds, !delegate.shapes.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { context in
            let drawing = context.cgContext
            drawing.setFillColor(UIColor.white.cgColor); drawing.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            let scale = min(1024 / bounds.width, 1024 / bounds.height)
            drawing.translateBy(x: (1024 - bounds.width * scale) / 2, y: (1024 - bounds.height * scale) / 2)
            drawing.scaleBy(x: scale, y: scale); drawing.translateBy(x: -bounds.minX, y: -bounds.minY)
            drawing.clip(to: bounds); drawing.setShouldAntialias(false)
            for shape in delegate.shapes {
                let ink = shape.black ? UIColor.black.cgColor : UIColor.white.cgColor
                drawing.setFillColor(ink); drawing.setStrokeColor(ink)
                drawing.addPath(shape.path)
                if let width = shape.stroke { drawing.setLineWidth(width); drawing.drawPath(using: shape.fill ? .fillStroke : .stroke) }
                else { drawing.fillPath() }
            }
        }
    }
}

private final class QRParser: NSObject, XMLParserDelegate {
    struct Shape { let path: CGPath; let stroke: CGFloat?; let black: Bool; let fill: Bool }
    var bounds: CGRect?
    var shapes: [Shape] = []
    var failed = false
    private var elements = 0
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        elements += 1
        guard elements <= 20_000, attributes["transform"] == nil, attributes["style"] == nil,
              !["opacity", "fill-opacity", "stroke-opacity", "filter", "clip-path", "mask", "stroke-dasharray", "stroke-dashoffset"].contains(where: { attributes[$0] != nil }),
              !attributes.keys.contains(where: { $0.lowercased().hasPrefix("on") || $0.contains("href") }) else { refuse(parser); return }
        switch element {
        case "svg":
            guard bounds == nil, attributes["fill"] == nil, attributes["stroke"] == nil else { refuse(parser); return }
            let tokens = attributes["viewBox"]?.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            let values = tokens?.compactMap { Double($0) }
            if let tokens, tokens.count != 4 || values?.count != 4 { refuse(parser); return }
            if let values, values.count == 4, values.allSatisfy({ $0.isFinite && abs($0) <= 4096 }), values[2] >= 1, values[3] >= 1 {
                bounds = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            } else if let width = number(attributes["width"]), let height = number(attributes["height"]), width >= 1, height >= 1 {
                bounds = CGRect(x: 0, y: 0, width: width, height: height)
            } else { refuse(parser) }
        case "path":
            guard bounds != nil, let data = attributes["d"], let path = Self.path(data), let black = ink(attributes["stroke"] ?? attributes["fill"] ?? "black") else { refuse(parser); return }
            let stroke: CGFloat?
            if attributes["stroke"] != nil {
                guard let width = number(attributes["stroke-width"] ?? "1"), width > 0, width <= 100 else { refuse(parser); return }
                stroke = width
            } else { stroke = nil }
            shapes.append(Shape(path: path, stroke: stroke, black: black, fill: attributes["fill"] != "none"))
        case "rect":
            guard bounds != nil, let black = ink(attributes["fill"] ?? "black"), let width = number(attributes["width"]), let height = number(attributes["height"]), width > 0, height > 0,
                  let x = number(attributes["x"] ?? "0"), let y = number(attributes["y"] ?? "0") else { refuse(parser); return }
            shapes.append(Shape(path: CGPath(rect: CGRect(x: x, y: y, width: width, height: height), transform: nil), stroke: nil, black: black, fill: true))
        case "g": if attributes["fill"] != nil || attributes["stroke"] != nil { refuse(parser) }
        case "title", "desc": break
        default: refuse(parser)
        }
    }
    private func ink(_ source: String) -> Bool? {
        let source = source.lowercased()
        if source == "black" { return true }
        if source == "white" { return false }
        guard source.hasPrefix("#"), [4, 7].contains(source.count) else { return nil }
        let digits = Set(source.dropFirst())
        if digits == ["0"] { return true }
        if digits == ["f"] { return false }
        return nil
    }
    private func number(_ text: String?) -> CGFloat? {
        guard let text, let value = Double(text), value.isFinite, abs(value) <= 4096 else { return nil }
        return CGFloat(value)
    }
    private func refuse(_ parser: XMLParser) { failed = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { refuse(parser) }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { refuse(parser); return nil }

    private static func path(_ value: String) -> CGPath? {
        guard value.utf8.count <= 500_000, let expression = try? NSRegularExpression(pattern: #"[MmLlHhVvZz]|[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)(?:[eE][-+]?[0-9]+)?"#) else { return nil }
        let source = value as NSString
        let matches = expression.matches(in: value, range: NSRange(location: 0, length: source.length))
        guard matches.count <= 100_000, !matches.isEmpty else { return nil }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        var end = 0; var tokens: [String] = []
        for match in matches {
            guard source.substring(with: NSRange(location: end, length: match.range.location - end)).trimmingCharacters(in: separators).isEmpty else { return nil }
            tokens.append(source.substring(with: match.range)); end = NSMaxRange(match.range)
        }
        guard source.substring(from: end).trimmingCharacters(in: separators).isEmpty else { return nil }
        let drawing = CGMutablePath()
        let commands = Set("MmLlHhVvZz".map { String($0) })
        var index = 0; var command: String?; var point = CGPoint.zero; var start = CGPoint.zero; var hasMove = false
        func read() -> CGFloat? {
            guard index < tokens.count, let value = Double(tokens[index]), value.isFinite, abs(value) <= 4096 else { return nil }
            index += 1; return CGFloat(value)
        }
        while index < tokens.count {
            if commands.contains(tokens[index]) { command = tokens[index]; index += 1 }
            guard let current = command else { return nil }
            if current == "z" || current == "Z" {
                guard hasMove else { return nil }; drawing.closeSubpath(); point = start; command = nil; continue
            }
            guard let first = read() else { return nil }
            let relative = current == current.lowercased()
            switch current.lowercased() {
            case "m", "l":
                guard let second = read() else { return nil }
                point = CGPoint(x: first + (relative ? point.x : 0), y: second + (relative ? point.y : 0))
                if current.lowercased() == "m" { drawing.move(to: point); start = point; hasMove = true; command = relative ? "l" : "L" }
                else { guard hasMove else { return nil }; drawing.addLine(to: point) }
            case "h": guard hasMove else { return nil }; point.x = first + (relative ? point.x : 0); drawing.addLine(to: point)
            case "v": guard hasMove else { return nil }; point.y = first + (relative ? point.y : 0); drawing.addLine(to: point)
            default: return nil
            }
            guard abs(point.x) <= 8192, abs(point.y) <= 8192 else { return nil }
        }
        return hasMove ? drawing : nil
    }
}
