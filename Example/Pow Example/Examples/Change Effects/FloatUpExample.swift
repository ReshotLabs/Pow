import Pow
import SwiftUI

struct FloatUpExample: View, Example {
    @State
    var changes: Int = 0

    var body: some View {
        let colors = [Color.red, .orange, .yellow, .green, .blue, .indigo, .purple]

        ZStack {
            Label {
                Text(changes.formatted())
                    .contentTransition(.identity)
                    .monospacedDigit()
                    .changeEffect(.floatUp(origin: .center, initialVelocity: 150.0) {
                        // floatUp will cycle through provided views
                        ForEach(colors, id: \.self) { color in
                            Text("+\(changes)") // Show the actual value
                                .foregroundStyle(color.gradient)
                                .shadow(color: color.opacity(0.4), radius: 0.5, y: 0.5)
                        }
                        .font(.system(.body, design: .rounded, weight: .bold))
                    }, value: changes)
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(
                        LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.2, y: 0.2), endPoint: UnitPoint(x: 0.8, y: 0.8))
                    )
            }
            .padding(.vertical, 8)
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .background(.thinMaterial, in: Capsule())
            .foregroundColor(.primary)
            .font(.system(.title, design: .rounded, weight: .bold))
        }
        .defaultBackground()
        .onTapGesture {
            withAnimation {
                changes += 1
            }
        }
    }

    static var description: some View {
        Text("""
        An effect that emits the provided particles from the origin point, floating up higher with a gentle side-to-side motion.

        - Parameters:
            - `origin`: The origin of the particle.
            - `layer`: The `ParticleLayer` on which to render the effect, default is `local`.
            - `initialVelocity`: The initial upward velocity of the particles, controlling how high they rise.
            - `particles`: The particles to emit.
        """)
    }

    static let localPath = LocalPath()
    
    static var icon: Image? {
        Image(systemName: "arrow.up.and.person.rectangle.portrait")
    }
}

#Preview {
    FloatUpExample()
}
