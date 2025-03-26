import SwiftUI

public extension AnyChangeEffect {
    static func floatUp(
        origin: UnitPoint = .center,
        layer: ParticleLayer = .local,
        initialVelocity: CGFloat = 100.0,
        @ViewBuilder _ particles: () -> some View
    ) -> AnyChangeEffect {
        let particles = particles()
        return .simulation { change in
            FloatingParticleSimulation(
                origin: origin,
                particles: particles,
                impulseCount: change,
                initialVelocity: initialVelocity,
                layer: layer
            )
        }
    }
    
    @available(*, deprecated, renamed: "floatUp(origin:layer:initialVelocity:_:)")
    static func floatingParticle(
        origin: UnitPoint = .center,
        initialVelocity: CGFloat = 100.0,
        @ViewBuilder _ particle: () -> some View
    ) -> AnyChangeEffect {
        floatUp(origin: origin, initialVelocity: initialVelocity, particle)
    }
}

internal struct FloatingParticleSimulation<ParticlesView: View>: ViewModifier, Simulative {
    var origin: UnitPoint
    var particles: ParticlesView
    var impulseCount: Int = 0
    var initialVelocity: CGFloat
    private let spring = Spring(zeta: 0.8, stiffness: 20)
    
    private struct Item: Identifiable {
        let id: UUID
        var progress: CGFloat
        var velocity: CGFloat
        let change: Int
        let symbolIndex: Int
    }
    
    @State private var items: [Item] = []
    @State private var symbolCount: Int = 1 // Default to 1 to avoid division by zero
    private let target: CGFloat = 1.0
    private let layer: ParticleLayer
    
    private var isSimulationPaused: Bool {
        items.isEmpty
    }
    
    internal init(
        origin: UnitPoint,
        particles: ParticlesView,
        impulseCount: Int = 0,
        initialVelocity: CGFloat,
        layer: ParticleLayer
    ) {
        self.origin = origin
        self.particles = particles
        self.impulseCount = impulseCount
        self.initialVelocity = initialVelocity
        self.layer = layer
    }
    
    private struct _ViewContainer: SwiftUI._VariadicView.MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            ForEach(Array(zip(0..., children)), id: \.1.id) { offset, child in
                child.tag(offset)
            }
        }
    }
    
    func body(content: Content) -> some View {
        let overlay = TimelineView(.animation(paused: isSimulationPaused)) { context in
            let insets = EdgeInsets(top: 80, leading: 40, bottom: 20, trailing: 40)
            
            Canvas { context, size in
                var symbols: [GraphicsContext.ResolvedSymbol] = []
                var i = 0
                while let symbol = context.resolveSymbol(id: i) {
                    symbols.append(symbol)
                    i += 1
                }
                
                // Update symbolCount based on resolved symbols
                if !symbols.isEmpty {
                    symbolCount = symbols.count
                }
                
                if symbols.isEmpty { return }
                
                context.translateBy(x: size.width / 2, y: insets.top + (size.height - insets.top - insets.bottom) / 2)
                
                for item in items {
                    var rng = SeededRandomNumberGenerator(seed: item.id)
                    
                    let progress = item.progress
                    let angle = Angle.degrees(.random(in: -15 ... 15, using: &rng))
                    let scale = 1 + 0.3 * progress
                    
                    context.opacity = 1.0 - pow(1.0 - 2.0 * progress, 4.0)
                    context.drawLayer { context in
                        context.rotate(by: .degrees(-angle.degrees * Double(1 - progress)))
                        context.translateBy(
                            x: progress * sin(progress * 1.4 * .pi) * .random(in: -30 ... 30, using: &rng),
                            y: progress * -100 - .random(in: 0 ... 20, using: &rng)
                        )
                        context.rotate(by: angle)
                        context.scaleBy(x: scale, y: scale)
                        
                        let symbol = symbols[item.symbolIndex % symbols.count]
                        context.draw(symbol, at: .zero)
                    }
                }
            } symbols: {
                SwiftUI._VariadicView.Tree(_ViewContainer()) {
                    particles
                }
            }
            .padding(insets.inverse)
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
                    velocity: initialVelocity,
                    change: newValue,
                    symbolIndex: (newValue - 1) % max(1, symbolCount)
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
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

#if os(iOS) && DEBUG
struct FloatingParticleEffect_Previews: PreviewProvider {
    struct ButtonPreview: View {
        @State var claps = 28
        @State var stars = 18
        @State var likes = 61
        
        var body: some View {
            HStack {
                Button {
                    claps += 1
                } label: {
                    HStack {
                        Image(systemName: "hands.clap.fill")
                        Text(claps.formatted())
                    }
                }
                .changeEffect(.floatUp(origin: UnitPoint(x: 0.7, y: 0.5), initialVelocity: 150.0) {
                    Group {
                        Text("+\(claps)")
                        Image(systemName: "hands.clap")
                        Image(systemName: "sparkle")
                        Image(systemName: "hand.thumbsup")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                .tint(.blue)
                }, value: claps)
                
                Button {
                    stars += 1
                } label: {
                    HStack {
                        Image(systemName: "star.fill")
                        Text("\(stars, format: .number)")
                    }
                }
                .changeEffect(.floatUp(origin: UnitPoint(x: 0.7, y: 0.5), initialVelocity: 150.0) {
                    Text("\(stars, format: .number.sign(strategy: .always()))")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.tint)
                }, value: stars)
                .tint(.yellow)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, .init(identifier: "ar_EG"))
                
                Button {
                    likes += 1
                } label: {
                    HStack {
                        Image(systemName: "heart.fill")
                        Text(likes.formatted())
                    }
                }
                .changeEffect(.floatUp(origin: UnitPoint(x: 0.3, y: 0.5), initialVelocity: 150.0) {
                    Text("+\(likes)")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }, value: likes)
                .clipped()
                .tint(.red)
            }
            .particleLayer(name: "root")
            .buttonStyle(.bordered)
            .monospacedDigit()
            .padding()
        }
    }
    
    static var previews: some View {
        NavigationView {
            ButtonPreview()
        }
        .environment(\.colorScheme, .dark)
        .previewDisplayName("Buttons")
    }
}
#endif
