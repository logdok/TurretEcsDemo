// swift-tools-version: 5.9
import PackageDescription

// Every line of this app except the shell (@main, Info.plist, icons, DI
// assembly) lives here. ONE package with several targets, not several
// packages: nothing here is versioned or shipped separately, and a second
// package would only buy separate resolution for no gain.
//
// The dependency arrows below are the architecture. They are checked by the
// compiler, not by convention: GameSimulation physically cannot reach a Metal
// type, and MetalRenderKit physically cannot reach a game type, because
// neither declares the other. That is the whole point of the split.
//
//   GameCore ─┬─> GameSimulation ─┬─> GameRendering ──> GameRuntime ──> GameUI
//             │                   │                          ^
//             └─> MetalRenderKit ─┘                           │
//                                     GameAudio ─────────────┘
//
// `package`-level access (Swift 5.9) is used for everything that crosses a
// target boundary INSIDE this package. Only two symbols are `public` — the
// two the app shell actually touches: `GameSession` and `GameScreen`.
let package = Package(
    name: "TurretEcsDemoModules",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // Deliberately no explicit `type:`. An unspecified library lets Xcode
        // link these statically, which is what a local package inside one app
        // wants: a dozen dynamic frameworks would each cost dyld work at
        // pre-main. `.dynamic` would only be justified if a module were shared
        // with an app extension or a widget, which none of these are.
        .library(name: "GameRuntime", targets: ["GameRuntime"]),
        .library(name: "GameUI", targets: ["GameUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/logdok/AegisECS.git", from: "1.0.0"),
    ],
    targets: [
        // Foundation shared by simulation, rendering and audio alike: a
        // seedable PRNG, vector operators over AegisECS's SIMDVector3, and the
        // RGBA colour value. Deliberately its own target rather than part of
        // GameSimulation — MetalRenderKit needs RGBA and the vector operators
        // but must never see a game type.
        .target(
            name: "GameCore",
            dependencies: [.product(name: "AegisECS", package: "AegisECS")]
        ),

        // The game itself: components, config, factories, systems, the shared
        // GameContext and the composition root that assembles them. Runs
        // headless — it depends on no rendering, audio or UI target, so the
        // whole simulation can be driven with no window and no GPU.
        .target(
            name: "GameSimulation",
            dependencies: ["GameCore", .product(name: "AegisECS", package: "AegisECS")]
        ),

        // Metal with no knowledge of this game: pipeline state, mesh upload,
        // procedural primitives, matrix helpers, orbit camera, and the shader
        // source itself. Xcode compiles Shaders.metal into `default.metallib`
        // inside this target's own resource bundle, which is why MetalContext
        // loads it from `Bundle.module` rather than the app's main bundle.
        .target(
            name: "MetalRenderKit",
            dependencies: ["GameCore", .product(name: "AegisECS", package: "AegisECS")]
        ),

        // The seam between the two above: turns render archetypes into
        // instanced batches and walks the ECS to fill them. This is the only
        // target that is allowed to know about both a GameContext and an
        // MTLBuffer.
        .target(
            name: "GameRendering",
            dependencies: ["GameSimulation", "MetalRenderKit", .product(name: "AegisECS", package: "AegisECS")]
        ),

        // Follows simulation counters and voices them. Owns its own clips:
        // inside a package they resolve through `Bundle.module`, so the app
        // shell never has to know that this module has resources at all.
        .target(
            name: "GameAudio",
            dependencies: ["GameCore", "GameSimulation"],
            resources: [.copy("Resources/Audio")]
        ),

        // One running game: the assembled world, its presentation, and the
        // per-frame driver that ticks both. The app shell builds exactly one
        // of these and hands it to the UI.
        .target(
            name: "GameRuntime",
            dependencies: ["GameRendering", "GameAudio", .product(name: "AegisECS", package: "AegisECS")]
        ),

        // SwiftUI surface: the game screen, its two side docks, the HUD, the
        // view model, and the design tokens they share. A second screen would
        // be the moment to promote DesignSystem/ into its own target; with one
        // screen that would be fragmentation, not modularity.
        .target(
            name: "GameUI",
            dependencies: [
                "GameRuntime",
                "GameSimulation",
                "MetalRenderKit",
                .product(name: "AegisECSInspectorUI", package: "AegisECS"),
            ]
        ),
    ]
)
