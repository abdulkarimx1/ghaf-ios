import SwiftUI

struct GhafCurrencyIcon: View {
    let currency: String
    var size: CGFloat = 24

    private var normalized: String { currency.uppercased() }

    var body: some View {
        ZStack {
            flag
        }
        .frame(width: size * 1.38, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .stroke(.primary.opacity(0.10), lineWidth: 0.65)
        }
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var flag: some View {
        switch normalized {
        case "AED":
            ZStack {
                VStack(spacing: 0) {
                    Color(red: 0.0, green: 0.48, blue: 0.24)
                    Color.white
                    Color.black
                }
                HStack(spacing: 0) {
                    Color(red: 0.86, green: 0.08, blue: 0.12)
                        .frame(width: size * 0.33)
                    Spacer(minLength: 0)
                }
            }
        case "SAR":
            ZStack {
                Color(red: 0.0, green: 0.39, blue: 0.22)
                VStack(spacing: size * 0.12) {
                    Capsule().fill(.white).frame(width: size * 0.77, height: max(1.2, size * 0.075))
                    Spacer(minLength: 0)
                    Capsule().fill(.white).frame(width: size * 0.73, height: max(1.2, size * 0.075))
                }
                .padding(.vertical, size * 0.25)
            }
        case "KWD":
            HStack(spacing: 0) {
                GhafFlagPolygon(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.25), CGPoint(x: 1, y: 0.75), CGPoint(x: 0, y: 1)])
                    .fill(.black)
                    .frame(width: size * 0.39)
                VStack(spacing: 0) {
                    Color(red: 0.0, green: 0.47, blue: 0.24)
                    Color.white
                    Color(red: 0.82, green: 0.08, blue: 0.16)
                }
            }
        case "BHD":
            ZStack(alignment: .leading) {
                Color(red: 0.78, green: 0.08, blue: 0.17)
                GhafSerratedBand(teeth: 5)
                    .fill(.white)
                    .frame(width: size * 0.55)
            }
        case "OMR":
            HStack(spacing: 0) {
                Color(red: 0.86, green: 0.08, blue: 0.12).frame(width: size * 0.34)
                VStack(spacing: 0) {
                    Color.white
                    Color(red: 0.86, green: 0.08, blue: 0.12)
                    Color(red: 0.0, green: 0.43, blue: 0.27)
                }
            }
        case "QAR":
            ZStack(alignment: .leading) {
                Color(red: 0.38, green: 0.06, blue: 0.20)
                GhafSerratedBand(teeth: 9)
                    .fill(.white)
                    .frame(width: size * 0.58)
            }
        case "USD":
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        (index.isMultiple(of: 2) ? Color(red: 0.72, green: 0.08, blue: 0.16) : Color.white)
                    }
                }
                Color(red: 0.12, green: 0.20, blue: 0.42)
                    .frame(width: size * 0.60, height: size * 0.56)
            }
        case "EUR":
            ZStack {
                Color(red: 0.02, green: 0.18, blue: 0.48)
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.16))
                        .frame(width: max(1.2, size * 0.07))
                        .offset(
                            x: cos(Double(index) * .pi / 6) * size * 0.28,
                            y: sin(Double(index) * .pi / 6) * size * 0.28
                        )
                }
            }
        case "GBP":
            ZStack {
                Color(red: 0.08, green: 0.15, blue: 0.34)
                Rectangle().fill(.white).frame(height: size * 0.23)
                Rectangle().fill(.white).frame(width: size * 0.23)
                Rectangle().fill(Color(red: 0.78, green: 0.08, blue: 0.17)).frame(height: size * 0.09)
                Rectangle().fill(Color(red: 0.78, green: 0.08, blue: 0.17)).frame(width: size * 0.09)
            }
        default:
            ZStack {
                Color.secondary.opacity(0.14)
                Image(systemName: "globe")
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityName: String {
        switch normalized {
        case "AED": "UAE dirham"
        case "SAR": "Saudi riyal"
        case "KWD": "Kuwaiti dinar"
        case "BHD": "Bahraini dinar"
        case "OMR": "Omani rial"
        case "QAR": "Qatari riyal"
        case "USD": "US dollar"
        case "EUR": "Euro"
        case "GBP": "British pound"
        default: "\(normalized) currency"
        }
    }
}

private struct GhafFlagPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

private struct GhafSerratedBand: Shape {
    let teeth: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX * 0.58, y: 0))
        for index in 0..<teeth {
            let top = rect.height * CGFloat(index) / CGFloat(teeth)
            let middle = top + rect.height / CGFloat(teeth) * 0.5
            let bottom = rect.height * CGFloat(index + 1) / CGFloat(teeth)
            path.addLine(to: CGPoint(x: rect.maxX * 0.98, y: middle))
            path.addLine(to: CGPoint(x: rect.maxX * 0.58, y: bottom))
        }
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
