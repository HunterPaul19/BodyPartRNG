# Boss VFX Packaging Rules

Use these rules when converting a BossVFX staging ability into a BossFight `GameAssets` package.

## Source And Target

- Source staging root: `Workspace.<AbilityName>` in the BossVFX Studio.
- Ignore any rig/model named exactly `<AbilityName>`.
- Ignore animation/keyframe save content. The user supplies animations; only recommend animation events.
- Target package root: `ReplicatedStorage.GameAssets.VFX.<BossName>.<AbilityName>` in the BossFight Studio.

## Effect Model Shape

For every `BasePart` that contains a `ParticleEmitter`, `Trail`, `Beam`, `RayValue`, or spatial `Sound`:

1. Create a fresh `Model`.
2. Name the model exactly like the particle-bearing part.
3. Move or clone that part into the model.
4. Set `Model.PrimaryPart` to that original child part.
5. Keep the original child part name unchanged.

This wrapper is required so runtime code can scale and pivot the effect model safely.

## Full Asset Transfer Identity

For cross-Studio or large packages, transfer by serializer-assigned numeric IDs:

- Assign every transferred instance a numeric `id`.
- Store each instance's `parentId`, `className`, `name`, and owning effect model.
- Do not use name paths as the primary identity. Duplicate emitter, beam, and attachment names are common and must survive transfer.
- Mark each effect model's intended PrimaryPart by ID.

The target reconstructor must create every instance first, then apply properties and attributes, then resolve deferred object references. Do not replace the live target package until validation succeeds.

## Attached Versus Dynamic

Classify packaged models by normalized names. Ignore spaces and case when matching.

Attached boss-rig names:

```text
RootPart
HumanoidRootPart
Head
UpperTorso
LowerTorso
LeftHand
RightHand
LeftFoot
RightFoot
LeftArm
RightArm
LeftLeg
RightLeg
Handle
```

- Attached packages are cloned, scaled, pivoted to the matching boss part, and welded to the live boss at runtime.
- Dynamic packages are cloned, scaled if needed, then positioned by move code. Examples: `Floor`, `Explosion`, `Projectile`, `Wave`, `Impact`, `Start`, `End`, `Spawn`, `Ball`, `Hit`.

If a source name is unclear, classify conservatively as dynamic and call it out in the implementation plan.

## Internal Welds

For a model with more than one `BasePart`:

1. Create or replace a `Folder` named `Welds` under the model.
2. For every non-primary `BasePart`, create a `WeldConstraint` under `Welds`.
3. Set `WeldConstraint.Name` to the part name.
4. Set `WeldConstraint.Part0 = Model.PrimaryPart`.
5. Set `WeldConstraint.Part1 = part`.
6. Set non-primary parts:
   - `Anchored = false`
   - `CanCollide = false`
   - `CanTouch = false`
   - `CanQuery = false`
   - `Massless = true`

For the primary part:

- Attached packages should be safe for runtime `prepareAttachedEffectModel`.
- Dynamic packages may keep an anchored primary part when they are positioned directly by `PivotTo`.
- Keep collision off for VFX-only parts unless a later implementation explicitly needs query geometry.

Reference packaging script pattern:

```lua
local Model = nil
local WeldsFolder = Instance.new("Folder", Model)
WeldsFolder.Name = "Welds"

for _, part in ipairs(Model:GetDescendants()) do
	if part:IsA("BasePart") and part ~= Model.PrimaryPart then
		local weld = Instance.new("WeldConstraint", WeldsFolder)
		weld.Name = part.Name
		weld.Part0 = Model.PrimaryPart
		weld.Part1 = part

		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
	end
end
```

For an attached runtime weld, create the weld under the package primary part, set `Part0` to the package primary part, set `Part1` to the live boss part, and unanchor the package before welding.

## Properties, Attributes, And References

Full transfers must preserve:

- Core instance properties needed for visual parity, including supported `BasePart`, `Attachment`, `ParticleEmitter`, `Beam`, `Trail`, `Sound`, light, mesh, and folder properties.
- Every attribute returned by `GetAttributes()`.
- Deferred object references for `Beam.Attachment0`, `Beam.Attachment1`, `Trail.Attachment0`, and `Trail.Attachment1`.

Attribute transfer rules:

1. Serialize all attributes returned by `GetAttributes()` with their names, `typeof` value type, and packed value.
2. Restore supported attributes using `SetAttribute`.
3. If a value cannot be JSON encoded, sanitize only the invalid string data needed to make the payload valid and report the attribute as sanitized.
4. If a value cannot be packed or restored, skip only that attribute and record the instance path, attribute name, value type, and failure reason.
5. Include `attributeFailureCount` and skipped/sanitized attribute details in the final transfer report.

Reference transfer rules:

1. Store object references by numeric target ID, not name.
2. Resolve references after all instances exist and all parents are assigned.
3. Resolve references across effect models when needed, such as an `End` beam pointing at a `Beam` attachment.
4. Report any unresolved `Beam` or `Trail` attachment reference and do not atomically replace the target package until the unresolved list is understood.

## Sounds

- Embed spatial sounds under the model or part they belong to.
- Use a sibling `Sounds` folder only for global or non-spatial cue stacks.
- Preserve sound asset ids, names, volume, playback speed, time offset, and any timing notes from `LunarSound2`.
- Preserve LunarSound2 cues as `Sound` instances with timing attributes such as `Delay`, `SourceStart`, `SourceEnd`, and original cue attributes when available.

## Animation Events

- Do not package animations.
- Recommend animation events with names matching packaged effect names.
- Include both seconds and frame number.
- Example: `RootPart at 0.383s / frame 23`.

Runtime code should use these event names to trigger presentation payloads and EmitModule emits.

## EmitModule Requirement

Actual BossFight presentation must use `ReplicatedStorage.Shared.Effects.EmitModule`.

Prefer existing boss presentation context helpers:

- `emitEffectInstance(instance, duration?)`
- `collectEmittableVisuals(root)`
- `emitVisuals(instances)`
- `prepareAttachedEffectModel(model)`
- `prepareMovingEffectModel(model)`
- `attachEffectModel(model, targetPart)`
- `scaleAttachedSounds(root, scaleMultiplier)`
