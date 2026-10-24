import Foundation

/// A screen the preview can simulate: a width in CSS pixels and the browser
/// identity (user agent) that device sends.
enum PreviewDevice: String, CaseIterable, Identifiable {
    case fit, desktop, laptop, ipadPro, ipadMini, iphoneProMax, iphone, iphoneSE, android

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case computer = "Computer"
        case tablet = "Tablet"
        case phone = "Phone"
    }

    var name: String {
        switch self {
        case .fit: "Fit to Window"
        case .desktop: "Desktop"
        case .laptop: "Laptop"
        case .ipadPro: "iPad Pro 13″"
        case .ipadMini: "iPad mini"
        case .iphoneProMax: "iPhone Pro Max"
        case .iphone: "iPhone 17"
        case .iphoneSE: "iPhone SE"
        case .android: "Android Phone"
        }
    }

    /// Screen width in CSS pixels, or nil to fill the preview column.
    var width: Double? {
        switch self {
        case .fit: nil
        case .desktop: 1440
        case .laptop: 1280
        case .ipadPro: 1032
        case .ipadMini: 744
        case .iphoneProMax: 440
        case .iphone: 402
        case .iphoneSE: 375
        case .android: 412
        }
    }

    var group: Group {
        switch self {
        case .fit, .desktop, .laptop: .computer
        case .ipadPro, .ipadMini: .tablet
        case .iphoneProMax, .iphone, .iphoneSE, .android: .phone
        }
    }

    var systemImage: String {
        switch self {
        case .fit: "arrow.left.and.right"
        case .desktop: "desktopcomputer"
        case .laptop: "laptopcomputer"
        case .ipadPro, .ipadMini: "ipad"
        case .iphoneProMax, .iphone, .iphoneSE: "iphone"
        case .android: "smartphone"
        }
    }

    var menuTitle: String {
        guard let width else { return name }
        return "\(name) — \(Int(width)) px"
    }

    var userAgent: String {
        switch group {
        case .computer:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case .tablet:
            "Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        case .phone where self == .android:
            "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"
        case .phone:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        }
    }
}
