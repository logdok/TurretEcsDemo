# TurretEcsDemo

A demo app for [**AegisECS**](https://github.com/logdok/AegisECS) — nothing
more. It exists to show what the library looks like when a real game is built
on it, and to give its inspector something interesting to inspect.

The game is a small tower-defense sandbox: one turret on a core, waves of four
hostile archetypes converging on it, missiles in flight, point defense. Every
number is a live slider — population, turret damage and fire rate, per-archetype
health, speed and missile rate — and nothing restarts when you drag one.

Not a product, not a template. A demo.

## What it demonstrates

- **A full ECS pipeline built on AegisECS** — 12 component stores, 14 systems,
  a fixed execution order that is itself the game's behaviour contract. Read
  `SimulationBootstrap.swift` top to bottom and you have the whole game.
- **`PackedStore` in a hot loop** — up to 10 000 entities walked per frame with
  no allocations, no per-entity method calls, raw column pointers throughout.
- **Two broadphase grids** — one for hostiles, one for missiles, with
  deliberately different cell sizes, feeding targeting, hit resolution and
  core-breach detection from a single rebuild per frame.
- **`AegisECSInspectorUI` attached to a live world** — the right-hand dock is
  the library's own panel, showing frame cost, per-system attribution and
  diagnostics with no host-app plumbing beyond one `Inspector.attach` call.
- **A simulation that renders nothing by itself.** `GameSimulation` has no
  dependency on Metal, SwiftUI or audio; the renderer is a system appended from
  outside, after the game layer is already assembled.

Rendering is a hand-written Metal instanced renderer — one draw call per visual
archetype, 16 floats per instance written straight into a shared buffer. There
is no SceneKit or RealityKit here, on purpose: the point was to keep the frame
cost legible.

## Layout

The app is a thin shell over one local Swift package. The shell is `@main`,
Info.plist, icons and a single line of dependency assembly; everything else is
a module:

```
App/                    thin shell — 24 lines of Swift
Modules/
  GameCore              seeded PRNG, vector operators, RGBA
  GameSimulation        the ECS game — runs headless
  MetalRenderKit        Metal with no knowledge of this game, + Shaders.metal
  GameRendering         the seam: archetypes -> instanced batches
  GameAudio             voice pools + its own bundled clips
  GameRuntime           GameSession: composition root and frame driver
  GameUI                SwiftUI screen, HUD, design tokens
```

Dependencies run one way and the compiler enforces it:

```
GameCore ─┬─> GameSimulation ─┬─> GameRendering ──> GameRuntime ──> GameUI
          │                   │                          ▲
          └─> MetalRenderKit ─┘        GameAudio ────────┘
```

Everything crossing a module boundary is `package`, not `public`. The package's
entire public surface is two types: `GameSession` and `GameScreen`.

## Building

Requires Xcode 15+ (iOS 17 deployment target) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen     # once
xcodegen generate
open TurretEcsDemo.xcodeproj
```

`TurretEcsDemo.xcodeproj` is generated from `project.yml` and is not meant to
be edited by hand or committed — change `project.yml` instead. You only need to
re-run `xcodegen` when the *shell* changes (a file in `App/Sources`, an
Info.plist key, a build setting, a new target). Adding or renaming files inside
`Modules/Sources/**` needs nothing: SwiftPM scans those directories.

Build with Xcode or `xcodebuild`, not `swift build` — the CLI does not compile
the `.metal` shader inside a package target.

Landscape-only, sized for iPad.

## Controls

| | |
|---|---|
| One finger drag | orbit the camera |
| Two fingers | zoom |
| Left tab (sliders icon) | settings dock |
| Right tab (chart icon) | AegisECS inspector |

## License

MIT — see [LICENSE](LICENSE).
