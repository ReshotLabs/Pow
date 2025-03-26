import SwiftUI

// MARK: - Public API

public struct ReactionParticleItem: Identifiable, Hashable, Equatable {
    public var id: String { ownerId + reactionId }
    public let reactionId: String
    public let ownerId: String
    
    public init(reactionId: String, ownerId: String) {
        self.reactionId = reactionId
        self.ownerId = ownerId
    }
}

public extension AnyChangeEffect {
    /// A rise effect that efficiently displays reaction particles
    static func reactionRise<Content: View>(
        origin: UnitPoint = .center,
        layer: ParticleLayer = .local,
        initialVelocity: CGFloat = 50.0,
        insets: EdgeInsets? = nil,
        reactions: [ReactionParticleItem],
        @ViewBuilder viewForReaction: @escaping (ReactionParticleItem) -> Content
    ) -> AnyChangeEffect {
        return .simulation { change in
            ReactionRiseSimulation(
                origin: origin,
                reactions: reactions,
                viewForReaction: viewForReaction,
                impulseCount: change,
                initialVelocity: initialVelocity,
                layer: layer,
                insets: insets
            )
        }
    }
}

// MARK: - Implementation

/// A simulation that efficiently displays reaction particles
internal struct ReactionRiseSimulation<ParticleView: View>: ViewModifier, Simulative {
    var origin: UnitPoint
    var reactions: [ReactionParticleItem]
    var viewForReaction: (ReactionParticleItem) -> ParticleView
    var impulseCount: Int
    var initialVelocity: CGFloat
    var insets: EdgeInsets?
    private let layer: ParticleLayer
    
    /// Represents a single particle with its state
    struct ParticleItem: Identifiable {
        let id: UUID
        var progress: CGFloat
        var velocity: CGFloat
        let reaction: ReactionParticleItem
    }
    
    private struct ViewContainer: SwiftUI._VariadicView.MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            ForEach(Array(zip(0..., children)), id: \.1.id) { offset, child in
                child.tag(child.id)
            }
        }
    }
    
    @State private var items: [ParticleItem] = []
    private let spring = Spring(zeta: 1, stiffness: 30)
    private let target: CGFloat = 1.0
    
    private var isSimulationPaused: Bool {
        items.isEmpty
    }
    
    private var lastReaction: ReactionParticleItem? {
        reactions.last
    }
    
    internal init(
        origin: UnitPoint,
        reactions: [ReactionParticleItem],
        viewForReaction: @escaping (ReactionParticleItem) -> ParticleView,
        impulseCount: Int,
        initialVelocity: CGFloat,
        layer: ParticleLayer,
        insets: EdgeInsets?
    ) {
        self.origin = origin
        self.reactions = reactions
        self.viewForReaction = viewForReaction
        self.impulseCount = impulseCount
        self.initialVelocity = initialVelocity
        self.layer = layer
        self.insets = insets
    }
    
    func body(content: Content) -> some View {
        let defaultInsets = EdgeInsets(top: 80, leading: 40, bottom: 20, trailing: 40)
        let effectiveInsets = insets ?? defaultInsets

        let overlay = TimelineView(.animation(paused: isSimulationPaused)) { timelineContext in // Renamed context to avoid conflict
            Canvas { context, size in
                context.translateBy(
                    x: size.width / 2,
                    y: effectiveInsets.top + (size.height - effectiveInsets.top - effectiveInsets.bottom) / 2
                )

                // Check if items array is populated
                if items.isEmpty && !isSimulationPaused {
                    print("[ReactionRiseSimulation] Warning: Canvas drawing but items array is empty.")
                }

                for item in items {
                    // Ensure we use the unique String ID for resolving
                    let reactionId = item.reaction.id
                    
                    // print("[ReactionRiseSimulation] Attempting to resolve symbol for ID: \(reactionId)") // Optional: Verbose logging

                    guard let symbol = context.resolveSymbol(id: reactionId) else {
                        // *** Log if symbol resolution fails ***
                        print("⚠️ [ReactionRiseSimulation] Failed to resolve symbol for ID: \(reactionId). Ensure it's tagged correctly in the symbols block.")
                        continue // Skip drawing this particle if its symbol isn't found
                    }
                    
                    // Log success if symbol was found
                    // print("✅ [ReactionRiseSimulation] Resolved symbol for ID: \(reactionId). Proceeding to draw.")

                    var rng = SeededRandomNumberGenerator(seed: item.id)

                    let progress = item.progress
                    let angle = Angle.degrees(.random(in: -10 ... 10, using: &rng))
                    let scale = 1 + 0.2 * progress
                    
                    // Calculate opacity, ensuring it stays within [0, 1]
                    let calculatedOpacity = 1.0 - pow(1.0 - 2.0 * progress, 4.0)
                    context.opacity = max(0.0, min(1.0, calculatedOpacity))

                    // Debug low opacity at start
                    // if progress < 0.05 { print("Progress \(progress), Opacity: \(context.opacity)") }

                    context.drawLayer { context in
                        // Apply transformations based on progress and randomness
                        context.rotate(by: .degrees(-angle.degrees * Double(1 - progress)))
                        context.translateBy(
                            x: progress * sin(progress * 1.4 * .pi) * .random(in: -20 ... 20, using: &rng),
                            y: progress * -50 - initialVelocity * progress - .random(in: 0 ... 10, using: &rng)
                        )
                        context.rotate(by: angle)
                        context.scaleBy(x: scale, y: scale)

                        // Draw the resolved symbol at the (transformed) origin
                        context.draw(symbol, at: .zero)
                    }
                }
            } symbols: {
                ForEach(items) { item in
                    viewForReaction(item.reaction)
                        .tag(item.reaction.id)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(effectiveInsets.inverse)
            .modifier(RelativeOffsetModifier(anchor: origin))
            .allowsHitTesting(false)
            .onChange(of: timelineContext.date) { newDate in
                let duration = Double(newDate.timeIntervalSince(timelineContext.date))
                withAnimation(nil) {
                    update(max(0, min(duration, 1 / 30)))
                }
            }
        }

        return content
            .particleLayerOverlay(alignment: .top, layer: layer, isEnabled: !isSimulationPaused) {
                overlay
            }
            .onChange(of: impulseCount) { _ in
                if let reaction = lastReaction { // Uses reactions.last
                     print("[ReactionRiseSimulation] Impulse changed. Creating particle for last reaction: \(reaction.id)")
                    createParticle(for: reaction)
                } else {
                     print("[ReactionRiseSimulation] Impulse changed but lastReaction is nil.")
                }
            }
    }

    
    private func createParticle(for reaction: ReactionParticleItem) {
        let item = ParticleItem(
            id: UUID(),
            progress: 0,
            velocity: initialVelocity,
            reaction: reaction
        )
        
        withAnimation(nil) {
            items.append(item)
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

