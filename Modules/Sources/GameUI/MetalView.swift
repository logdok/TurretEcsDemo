import GameRuntime
import MetalKit
import SwiftUI

/// Hosts the `MTKView` and wires touch gestures to the orbit camera.
/// `UIPanGestureRecognizer`/`UIPinchGestureRecognizer` give the
/// one-finger-orbits, two-fingers-zoom split directly: a pan recognizer
/// limited to one touch and a pinch recognizer needing two never fire on the
/// same gesture, so no manual touch bookkeeping is needed.
struct MetalView: UIViewRepresentable {
    let session: GameSession

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: session.metalContext.device)
        view.delegate = session
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0.07, 0.08, 0.10, 1.0)
        view.clearDepth = 1.0
        view.preferredFramesPerSecond = 60
        view.isMultipleTouchEnabled = true
        view.isOpaque = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    final class Coordinator: NSObject {
        let session: GameSession

        init(session: GameSession) {
            self.session = session
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            guard gesture.state == .changed else { return }
            session.cameraRig.applyDrag(translation: SIMD2<Float>(Float(translation.x), Float(translation.y)))
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            session.cameraRig.applyPinch(scale: Float(gesture.scale))
            gesture.scale = 1.0
        }
    }
}
