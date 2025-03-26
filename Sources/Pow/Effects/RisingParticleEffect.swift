import SwiftUI

// Extend AnyChangeEffect to add a new rise effect with initialVelocity and insets
public extension AnyChangeEffect {
    /// An effect that emits the provided particles from the origin point and slowly float up while moving side to side.
    ///
    /// This effect respects `particleLayer()`.
    ///
    /// - Parameters:
    ///   - origin: The origin of the particle.
    ///   - layer: The `ParticleLayer` on which to render the effect, default is `local`.
    ///   - initialVelocity: The initial upward velocity of the particles, controlling how high they rise.
    ///   - insets: Custom insets for the particle rendering area.
    ///   - particles: The particles to emit.
    static func rise(
        origin: UnitPoint = .center,
        layer: ParticleLayer = .local,
        initialVelocity: CGFloat = 0.0, // Added initialVelocity
        insets: EdgeInsets? = nil, // Added insets
        @ViewBuilder _ particles: () -> some View
    ) -> AnyChangeEffect {
        let particles = particles()
        return .simulation { change in
            CustomRisingParticleSimulation(
                origin: origin,
                particles: particles,
                impulseCount: change,
                initialVelocity: initialVelocity,
                layer: layer,
                insets: insets
            )
        }
    }
}

internal struct CustomRisingParticleSimulation<ParticlesView: View>: ViewModifier, Simulative {
    var origin: UnitPoint
    var particles: ParticlesView
    var impulseCount: Int = 0
    var initialVelocity: CGFloat
    var insets: EdgeInsets? 
    private let spring = Spring(zeta: 1, stiffness: 30)

    private struct Item: Identifiable {
        let id: UUID
        var progress: CGFloat
        var velocity: CGFloat
        var change: Int
    }

    @State private var items: [Item] = []
    private let target: CGFloat = 1.0
    private let layer: ParticleLayer

    private var isSimulationPaused: Bool {
        items.isEmpty
    }

    internal init(
        origin: UnitPoint,
        particles: ParticlesView,
        impulseCount: Int = 0,
        initialVelocity: CGFloat, // Added initialVelocity
        layer: ParticleLayer,
        insets: EdgeInsets? // Added insets
    ) {
        self.origin = origin
        self.particles = particles
        self.impulseCount = impulseCount
        self.initialVelocity = initialVelocity
        self.layer = layer
        self.insets = insets
    }

    private struct _ViewContainer: SwiftUI._VariadicView.MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            ForEach(Array(zip(0..., children)), id: \.1.id) { offset, child in
                child.tag(offset)
            }
        }
    }

    func body(content: Content) -> some View {
        let defaultInsets = EdgeInsets(top: 80, leading: 40, bottom: 20, trailing: 40)
        let effectiveInsets = insets ?? defaultInsets // Use provided insets or default

        let overlay = TimelineView(.animation(paused: isSimulationPaused)) { context in
            Canvas { context, size in
                var symbols: [GraphicsContext.ResolvedSymbol] = []
                var i = 0
                var nextSymbol: GraphicsContext.ResolvedSymbol? = context.resolveSymbol(id: i)
                while let symbol = nextSymbol {
                    symbols.append(symbol)
                    i += 1
                    nextSymbol = context.resolveSymbol(id: i)
                }

                if symbols.isEmpty { return }

                context.translateBy(x: size.width / 2, y: effectiveInsets.top + (size.height - effectiveInsets.top - effectiveInsets.bottom) / 2)

                for item in items {
                    var rng = SeededRandomNumberGenerator(seed: item.id)

                    let symbolIndex = max(0, item.change - 1) % symbols.count
                    let progress = item.progress
                    let angle = Angle.degrees(.random(in: -10 ... 10, using: &rng))
                    let scale = 1 + 0.2 * progress

                    context.opacity = 1.0 - pow(1.0 - 2.0 * progress, 4.0)
                    context.drawLayer { context in
                        context.rotate(by: .degrees(-angle.degrees * Double(1 - progress)))
                        context.translateBy(
                            x: progress * sin(progress * 1.4 * .pi) * .random(in: -20 ... 20, using: &rng),
                            y: progress * -50 - .random(in: 0 ... 10, using: &rng) // Adjusted with initialVelocity below
                        )
                        context.rotate(by: angle)
                        context.scaleBy(x: scale, y: scale)

                        let symbol = symbols[symbolIndex]
                        context.draw(symbol, at: .zero)
                    }
                }
            } symbols: {
                SwiftUI._VariadicView.Tree(_ViewContainer()) {
                    particles
                }
            }
            .padding(effectiveInsets.inverse)
            .modifier(RelativeOffsetModifier(anchor: origin))
            .allowsHitTesting(false)
            .onChange(of: context.date) { (newValue: Date) in
                let duration = Double(newValue.timeIntervalSince(context.date))
                withAnimation(nil) {
                    update(max(0, min(duration, 1 / 30)))
                }
            }
        }

        content
            .particleLayerOverlay(alignment: .top, layer: layer, isEnabled: !isSimulationPaused) {
                overlay
            }
            .onChange(of: impulseCount) { newValue in
                let item = Item(
                    id: UUID(),
                    progress: 0,
                    velocity: initialVelocity, // Use initialVelocity
                    change: newValue
                )
                withAnimation(nil) {
                    items.append(item)
                }
            }
    }

    private func update(_ step: Double) {
        for index in items.indices.reversed() {
            var item = items[index]

            if spring.response > 0 {
                let (newValue, newVelocity) = spring.value(
                    from: item.progress,
                    to: target,
                    velocity: item.velocity,
                    timestep: step
                )
                item.progress = newValue
                item.velocity = newVelocity
            } else {
                item.progress = target
                item.velocity = .zero
            }

            items[index] = item

            if abs(item.progress - target) < 0.04 && item.velocity < 0.04 {
                items.remove(at: index)
            }
        }
    }
}

private struct RelativeOffsetModifier: GeometryEffect {
    var anchor: UnitPoint

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = size.width  * (-0.5 + anchor.x)
        let y = size.height * (-0.5 + anchor.y)
        return ProjectionTransform(
            CGAffineTransform(translationX: x, y: y)
        )
    }
}
