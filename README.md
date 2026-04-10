# GameTemplate

A Rojo-first Roblox template rebuilt from the connected Studio place.

This repository now keeps the game's script-side logic locally so you can load the template into any place and continue working from source control instead of leaving logic trapped in Studio.

## Layout

- `src/game`: authored game source, organized by Roblox service
- `src/game/ReplicatedStorage`: shared runtime modules such as `Common`, `Lists`, `Loader`, and `Shared`
- `src/game/ReplicatedStorage/Shared/Audio`: reusable shared audio helpers
- `src/game/ReplicatedStorage/Shared/Camera`: shared camera systems such as camera shake
- `src/game/ReplicatedStorage/Shared/Config`: shared authored config modules
- `src/game/ReplicatedStorage/Shared/Effects`: shared effect/variant logic
- `src/game/ReplicatedStorage/Shared/Formatting`: shared text/number formatting helpers
- `src/game/ReplicatedStorage/Shared/UI`: shared UI-facing utility modules
- `src/game/ServerScriptService`: server bootstrap and services
- `src/game/StarterPlayer/StarterPlayerScripts`: client bootstrap and controllers
- `src/game/StarterGui/HoverClient`: the code-owned `StarterGui` hover script
- `src/Packages`: shared Wally packages synced to `ReplicatedStorage`
- `src/ServerPackages`: server-only Wally packages synced to `ServerScriptService`
- `src/wally.toml`: Wally manifest for the local source tree

## Notes

- Non-code assets, UI hierarchies, models, sounds, and world content are still expected to remain Studio-owned.
- Runtime-created remotes are created by code when needed, so the project stays code-only.
- Some helper modules still expect Studio assets to exist before they do visible work, but the script ownership is now local.

## Tooling

Install tools and packages:

```powershell
rokit install
wally install --project-path src
```

Build the place:

```powershell
rojo build -o "GameTemplate.rbxlx"
```

Serve into Studio:

```powershell
rojo serve
```
