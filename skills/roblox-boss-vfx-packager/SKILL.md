---
name: roblox-boss-vfx-packager
description: Package Roblox boss ability VFX and sound content from a BossVFX staging Studio into BossFight ReplicatedStorage.GameAssets, classify attached versus dynamically positioned effects, convert Moon marker frames to 60 FPS timing, and produce an implementation-ready Rojo boss move plan using EmitModule. Use when Codex needs to turn Studio-authored boss ability visuals/audio into packaged GameAssets and local boss fight integration guidance while preserving BodyPartRNG ownership boundaries.
---

# Roblox Boss VFX Packager

## Overview

Use this skill to move a staged boss ability VFX package from a BossVFX Studio place into the BossFight place's `ReplicatedStorage.GameAssets.VFX` layout, then produce a Rojo implementation plan for the boss move. This skill can mutate Studio-owned assets only when the user explicitly asks to package or update the BossFight asset package.

Keep the existing `roblox-moon-timing-analyzer` read-only. Use this skill when the task includes packaging, classifying, copying, or planning runtime integration from Studio-authored boss VFX/audio.

## Required Context

Before packaging or planning:

1. Read `AGENTS.md` and `PROJECT_BRIEF.md` in `C:\dev\BodyPartRNG`.
2. Treat local Rojo code as source of truth for scripts.
3. Treat Roblox Studio MCP as source of truth for non-code assets, hierarchy, sounds, VFX, animations, tags, placement, properties, playtesting, and live validation.
4. Do not move visual assets into Rojo-managed folders.
5. In runtime implementation plans, always emit boss fight VFX through `ReplicatedStorage.Shared.Effects.EmitModule`, preferably through existing boss presentation context helpers.

## Workflow

1. Select Studios.
   - Call `list_roblox_studios`.
   - Use `BossVFX` as the source staging place unless the user names another source.
   - Use `BossFight` as the target packaging place unless the user names another target.

2. Inspect source content.
   - In BossVFX, locate `Workspace.<AbilityName>`.
   - Ignore the rig/model named `<AbilityName>` and all animation/keyframe save content.
   - Inspect non-rig VFX parts, models, attachments, particle emitters, trails, beams, sounds, Moon markers, and LunarSound2 cues.
   - Convert numeric Moon marker folders as 60 FPS animation frames: `seconds = frame / 60`.

3. Classify and choose the transfer path.
   - Read `references/packaging-rules.md` before mutating Studio assets.
   - Every emitter-bearing BasePart becomes a same-named Model whose PrimaryPart is that original child part.
   - Known rig-name packages are boss-attached; other packages are dynamically positioned by move code.
   - Embed spatial sounds with their effect model or part.
   - Use the lightweight in-place packaging helper only for small source packages that are already available in the target BossFight Studio.
   - Use Full Asset Transfer Mode when source assets live in another Studio session, package size is large, duplicate descendant names exist, or Studio MCP output truncation is likely.

4. Copy into BossFight when explicitly requested.
   - Package to `ReplicatedStorage.GameAssets.VFX.<BossName>.<AbilityName>.<EffectName>`.
   - Use Studio MCP for all package creation, hierarchy changes, attributes, welds, properties, and validation.
   - Never edit Studio-owned asset trees through the local filesystem.
   - For Full Asset Transfer Mode:
     1. Start a temporary localhost bridge outside the repo, normally from a temp file.
     2. Serialize the selected source effects in BossVFX with numeric node IDs and parent IDs.
     3. Include properties, object references, sound cues, and every attribute returned by `GetAttributes()`.
     4. POST the full JSON payload to the bridge.
     5. Fetch the payload from BossFight and reconstruct it under a staging folder.
     6. Create all instances first, apply properties and attributes second, resolve object references last.
     7. Validate counts, PrimaryParts, collision/query state, property failures, attribute failures, and unresolved Beam/Trail references.
     8. Atomically replace the target package only after validation passes.
     9. Stop the bridge process.

5. Produce the implementation plan.
   - Use `references/implementation-plan-template.md`.
   - Include package paths, animation events, EmitModule usage, client presentation changes, server move/payload needs, hitbox timing, and missing/ambiguous items.

## Reference Files

- `references/packaging-rules.md`: concrete packaging standard and classification rules.
- `references/studio-queries.md`: reusable Luau snippets for source inspection, bridge transfer, target reconstruction, target validation, and packaging helpers.
- `references/implementation-plan-template.md`: output format for the Rojo/Studio handoff.

## Safety

- Do not package or update BossFight assets unless the user explicitly asks for packaging or implementation.
- Do not package rigs or animations; only recommend animation events and timings.
- Do not edit Rojo-managed scripts in Studio.
- Do not use local filesystem edits for Studio-owned VFX, sounds, models, or hierarchy.
- Preserve embedded upstream license text in imported code modules if an implementation plan touches them.
- Do not silently drop attributes. Restore every serializable `GetAttributes()` entry or report it with instance path, attribute name, value type, and failure reason.
