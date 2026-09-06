import GameRuntime
import GameUI
import SwiftUI

/// The whole app target. Everything else — the ECS simulation, the Metal
/// renderer, the audio, the HUD — lives in `Modules/`, the local Swift package
/// next to this file.
///
/// What is left here is exactly what only an app target can do: be `@main`,
/// carry Info.plist and the icons, and assemble the object graph. That last
/// part is one line, because there is one graph to assemble: a `GameSession`
/// owns the world, its presentation and its frame loop, and `GameScreen` draws
/// it. Those two types are the entire public surface of the package; nothing
/// else in it is reachable from here, and that is deliberate.
@main
struct TurretEcsDemoApp: App {
    // Held by the shell, not by the view, so it survives any SwiftUI view
    // identity change: a session owns GPU buffers and a running audio engine,
    // and rebuilding it would restart the game.
    private let session = GameSession()

    var body: some Scene {
        WindowGroup {
            GameScreen(session: session)
        }
    }
}
