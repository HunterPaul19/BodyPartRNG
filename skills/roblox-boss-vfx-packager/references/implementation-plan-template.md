# Implementation Plan Template

Use this structure after inspecting or packaging a boss ability VFX set.

```markdown
# <BossName> <AbilityName> VFX Package And Implementation Plan

## Package Summary
- Source Studio: <BossVFX or source name>
- Target Studio: <BossFight or target name>
- Source root: `Workspace.<AbilityName>`
- Target package: `ReplicatedStorage.GameAssets.VFX.<BossName>.<AbilityName>`
- Transfer mode: lightweight in-place packaging | full bridge transfer
- Ignored rig/animation content: <list>
- Packaged effects:
  - `<EffectName>`: attached|dynamic, PrimaryPart `<PartName>`, notable emitters/sounds
- Transfer report:
  - Payload bytes: <N>, effects: <N>, nodes: <N>, sound cues: <N>
  - Property failures: <N>, attribute failures: <N>, unresolved Beam/Trail refs: <N>
  - Attribute handling: all restored | skipped/sanitized attributes listed below

## Timing And Animation Events
- `<EffectName>`: frame <N>, <seconds>s, animation event `<EffectName>`
- Sound cues:
  - <seconds>s: `<SoundName>`, asset `<assetId>`, offset <offset>, end <end>, volume <volume>

## Runtime Integration
- Local move module: <planned module path and behavior>
- Client presentation handler: <planned handler path or new handler>
- Presentation payload fields:
  - <field>: <purpose>
- EmitModule usage:
  - clone `<GameAssets path>`
  - attach or pivot
  - call `collectEmittableVisuals` + `emitVisuals` or `emitEffectInstance`

## Combat Timing
- Cast/start cue: <time>
- Active hitbox window: <start> to <end>
- Damage/knockback recommendation: <explicit value or TBD user balancing>
- Scaling rule: <boss scale / root size / standing height>

## Missing / Ambiguous
- <missing package, animation event, source folder, boss part, sound timing, unclear dynamic/attached classification>
- <any skipped/sanitized attribute with instance path, attribute name, type, and reason>
```

Keep the plan implementation-ready. Do not leave choices such as "maybe attach or pivot" unresolved; pick one and explain any assumption.
