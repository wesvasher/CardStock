import SwiftUI

extension View {
    /// A perfectly round Liquid Glass button shape: an exact square frame,
    /// clipped to a circle, so menus and buttons can't stretch it into an oval.
    func roundGlass(_ diameter: CGFloat, interactive: Bool = true) -> some View {
        self
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .clipShape(Circle())
            .glassEffect(.regular.interactive(interactive), in: .circle)
    }
}
