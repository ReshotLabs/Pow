import SwiftUI

// MARK: - Public API

public extension View {
    /// Applies a reaction effect when reactions in the map change
    ///
    /// - Parameters:
    ///   - reactionMap: The map of player reactions to monitor
    ///   - origin: The origin point of the particles
    ///   - layer: The particle layer
    ///   - initialVelocity: Initial velocity of particles
    ///   - insets: Custom insets for rendering area
    ///   - reactionViewBuilder: A closure that builds a view for a specific player and reaction
    func reactionEffect<ReactionView: View>(
        reactionMap: [String: [String: Int]],
        origin: UnitPoint = .center,
        layer: ParticleLayer = .local,
        initialVelocity: CGFloat = 50.0,
        insets: EdgeInsets? = nil,
        @ViewBuilder reactionViewBuilder: @escaping (String, String) -> ReactionView
    ) -> some View {
        self.modifier(ReactionMapModifier(
            reactionMap: reactionMap,
            origin: origin,
            layer: layer,
            initialVelocity: initialVelocity,
            insets: insets,
            reactionViewBuilder: reactionViewBuilder
        ))
    }
}

// MARK: - Implementation

// Captured symbol structure
struct CapturedSymbol {
    let image: Image
    let size: CGSize
}

// Structure to track a specific player-reaction combination
struct PlayerReactionKey: Hashable {
    let playerId: String
    let reactionId: String
}

/// A modifier that tracks reaction map changes and shows particles
struct ReactionMapModifier<ReactionView: View>: ViewModifier {
    // The reaction map to monitor
    @State private var previousMap: [String: [String: Int]] = [:]
    let reactionMap: [String: [String: Int]]
    
    // Configuration
    let origin: UnitPoint
    let layer: ParticleLayer
    let initialVelocity: CGFloat
    let insets: EdgeInsets?
    let reactionViewBuilder: (String, String) -> ReactionView
    
    // Particle state
    @State private var items: [ParticleItem] = []
    @State private var capturedSymbols: [PlayerReactionKey: CapturedSymbol] = [:]
    
    private struct ParticleItem: Identifiable {
        let id: UUID
        var progress: CGFloat
        var velocity: CGFloat
        let playerId: String
        let reactionId: String
        var capturedSymbol: CapturedSymbol?
    }
    
    private let spring = Spring(zeta: 1, stiffness: 30)
    private let target: CGFloat = 1.0
    
    private var isSimulationPaused: Bool {
        items.isEmpty
    }
    
    init(
        reactionMap: [String: [String: Int]],
        origin: UnitPoint,
        layer: ParticleLayer,
        initialVelocity: CGFloat,
        insets: EdgeInsets?,
        reactionViewBuilder: @escaping (String, String) -> ReactionView
    ) {
        self.reactionMap = reactionMap
        self.origin = origin
        self.layer = layer
        self.initialVelocity = initialVelocity
        self.insets = insets
        self.reactionViewBuilder = reactionViewBuilder
    }
    
    // Get all player-reaction combinations in the map
    private func getAllPlayerReactions() -> [PlayerReactionKey] {
        var keys: [PlayerReactionKey] = []
        
        for (playerId, reactions) in reactionMap {
            for reactionId in reactions.keys {
                let key = PlayerReactionKey(
                    playerId: playerId.description,
                    reactionId: reactionId.description
                )
                keys.append(key)
            }
        }
        
        return keys
    }

    
    func body(content: Content) -> some View {
        let defaultInsets = EdgeInsets(top: 80, leading: 40, bottom: 20, trailing: 40)
        let effectiveInsets = insets ?? defaultInsets
        
        let overlay = TimelineView(.animation(paused: isSimulationPaused)) { context in
            ZStack {
                // Create a view for each player-reaction combination to capture
                ForEach(Array(getAllPlayerReactions()), id: \.self) { key in
                    reactionViewBuilder(key.playerId, key.reactionId)
                        .opacity(0) // Make it invisible
                        .captureToSymbols { symbols in
                            if let symbol = symbols.first {
                                capturedSymbols[key] = symbol
                            }
                        }
                }
                
                // This is the actual canvas that renders the particles
                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: effectiveInsets.top + (size.height - effectiveInsets.top - effectiveInsets.bottom) / 2)
                    
                    for item in items {
                        let key = PlayerReactionKey(
                            playerId: item.playerId.description,
                            reactionId: item.reactionId.description
                        )
                        guard let symbol = capturedSymbols[key] ?? item.capturedSymbol else { continue }
                        
                        var rng = SeededRandomNumberGenerator(seed: item.id)
                        
                        let progress = item.progress
                        let angle = Angle.degrees(.random(in: -10 ... 10, using: &rng))
                        let scale = 1 + 0.2 * progress
                        
                        context.opacity = 1.0 - pow(1.0 - 2.0 * progress, 4.0)
                        context.drawLayer { context in
                            context.rotate(by: .degrees(-angle.degrees * Double(1 - progress)))
                            context.translateBy(
                                x: progress * sin(progress * 1.4 * .pi) * .random(in: -20 ... 20, using: &rng),
                                y: progress * -50 - initialVelocity * progress - .random(in: 0 ... 10, using: &rng)
                            )
                            context.rotate(by: angle)
                            context.scaleBy(x: scale, y: scale)
                            
                            let size = symbol.size
                            context.draw(symbol.image, in: CGRect(origin: CGPoint(x: -size.width/2, y: -size.height/2), size: size))
                        }
                    }
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
        
        return content
            .particleLayerOverlay(alignment: .top, layer: layer, isEnabled: !isSimulationPaused) {
                overlay
            }
            .onAppear {
                // Initialize previous map
                previousMap = reactionMap
            }
            .onChange(of: reactionMap) { newMap in
                // Find what reactions have changed and create particles for them
                let changedReactions = findChangedReactions(oldMap: previousMap, newMap: newMap)
                
                for (playerId, reactionId, _) in changedReactions {
                    let item = ParticleItem(
                        id: UUID(),
                        progress: 0,
                        velocity: initialVelocity,
                        playerId: playerId,
                        reactionId: reactionId,
                        capturedSymbol: capturedSymbols[PlayerReactionKey(
                            playerId: playerId.description,
                            reactionId: reactionId.description
                        )]
                    )
                    
                    withAnimation(nil) {
                        items.append(item)
                    }
                }
                
                // Update previous map for next comparison
                previousMap = newMap
            }
    }
    
    // Get all player-reaction combinations in the map
    private func getAllPlayerReactions() -> [(String, String)] {
        var combinations: [(String, String)] = []
        
        for (playerId, reactions) in reactionMap {
            for reactionId in reactions.keys {
                combinations.append((playerId, reactionId))
            }
        }
        
        return combinations
    }
    
    // Find reactions that have increased in count
    private func findChangedReactions(oldMap: [String: [String: Int]], newMap: [String: [String: Int]]) -> [(String, String, Int)] {
        var changedReactions: [(String, String, Int)] = []
        
        for (playerId, reactions) in newMap {
            for (reactionId, count) in reactions {
                let previousCount = oldMap[playerId]?[reactionId] ?? 0
                if count > previousCount {
                    changedReactions.append((playerId, reactionId, count))
                }
            }
        }
        
        return changedReactions
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

// MARK: - Helper Views and Extensions

/// View extension to capture a view as symbols
extension View {
    func captureToSymbols(completion: @escaping ([CapturedSymbol]) -> Void) -> some View {
        self.background(
            SymbolCaptureRepresentable(content: self, completion: completion)
        )
    }
}

/// UIViewRepresentable to capture views
struct SymbolCaptureRepresentable<Content: View>: UIViewRepresentable {
    let content: Content
    let completion: ([CapturedSymbol]) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        
        // Add the view to a window to ensure it's properly rendered
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        
        return hostingController.view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            let renderer = UIGraphicsImageRenderer(bounds: uiView.bounds)
            let image = renderer.image { _ in
                uiView.drawHierarchy(in: uiView.bounds, afterScreenUpdates: true)
            }
            
            let symbol = CapturedSymbol(
                image: Image(uiImage: image),
                size: uiView.bounds.size
            )
            
            completion([symbol])
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
