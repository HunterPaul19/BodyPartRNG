# Studio Queries And Helpers

Use these Luau snippets through Studio MCP. Replace uppercase placeholders before running.

## List Connected Package Roots

```lua
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
local out = { hasGameAssets = gameAssets ~= nil, rootChildren = {}, vfxBosses = {} }

if gameAssets then
	for _, child in ipairs(gameAssets:GetChildren()) do
		table.insert(out.rootChildren, {
			name = child.Name,
			className = child.ClassName,
			childCount = #child:GetChildren(),
			descendantCount = #child:GetDescendants(),
		})
	end

	local vfx = gameAssets:FindFirstChild("VFX")
	if vfx then
		for _, bossFolder in ipairs(vfx:GetChildren()) do
			table.insert(out.vfxBosses, {
				name = bossFolder.Name,
				className = bossFolder.ClassName,
				childCount = #bossFolder:GetChildren(),
				descendantCount = #bossFolder:GetDescendants(),
			})
		end
	end
end

return HttpService:JSONEncode(out)
```

## Inspect BossVFX Staging Ability

```lua
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local ABILITY_NAME = "ABILITY_NAME"

local function normalizeName(value)
	return string.lower(string.gsub(value, "%s+", ""))
end

local attachedNames = {
	rootpart = true,
	humanoidrootpart = true,
	head = true,
	uppertorso = true,
	lowertorso = true,
	lefthand = true,
	righthand = true,
	leftfoot = true,
	rightfoot = true,
	leftarm = true,
	rightarm = true,
	leftleg = true,
	rightleg = true,
	handle = true,
}

local function classify(name)
	return if attachedNames[normalizeName(name)] then "attached" else "dynamic"
end

local function hasEmittable(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("RayValue")
			or descendant:IsA("Sound") then
			return true
		end
	end
	return false
end

local root = workspace:FindFirstChild(ABILITY_NAME)
local out = {
	ability = ABILITY_NAME,
	sourceExists = root ~= nil,
	ignored = {},
	candidates = {},
	moonMarkers = {},
	sounds = {},
}

if root then
	for _, child in ipairs(root:GetChildren()) do
		if child.Name == ABILITY_NAME then
			table.insert(out.ignored, {
				name = child.Name,
				className = child.ClassName,
				reason = "ability rig/animation staging model",
				descendantCount = #child:GetDescendants(),
			})
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= ABILITY_NAME and hasEmittable(descendant) then
			local counts = {}
			for _, nested in ipairs(descendant:GetDescendants()) do
				counts[nested.ClassName] = (counts[nested.ClassName] or 0) + 1
			end
			table.insert(out.candidates, {
				name = descendant.Name,
				className = descendant.ClassName,
				fullName = descendant:GetFullName(),
				classification = classify(descendant.Name),
				counts = counts,
				anchored = descendant.Anchored,
				canCollide = descendant.CanCollide,
			})
		end
	end
end

local moonRoot = ServerStorage:FindFirstChild("MoonAnimator2Saves")
local moonSave = moonRoot and moonRoot:FindFirstChild(ABILITY_NAME)
if moonSave then
	for _, descendant in ipairs(moonSave:GetDescendants()) do
		if descendant:IsA("Folder") and descendant.Name == "MarkerTrack" then
			for _, marker in ipairs(descendant:GetChildren()) do
				if marker:IsA("Folder") then
					local frame = tonumber(marker.Name)
					table.insert(out.moonMarkers, {
						frame = frame,
						seconds = if frame then frame / 60 else nil,
						rawKey = marker.Name,
						childCount = #marker:GetChildren(),
					})
				end
			end
		end
	end
end

local soundRoot = ServerStorage:FindFirstChild("LunarSound2")
local soundFolder = soundRoot and soundRoot:FindFirstChild(ABILITY_NAME)
if soundFolder then
	for _, sound in ipairs(soundFolder:GetChildren()) do
		local attrs = sound:GetAttributes()
		table.insert(out.sounds, {
			name = sound.Name,
			className = sound.ClassName,
			assetId = if sound:IsA("StringValue") then sound.Value else nil,
			start = attrs.Start,
			offset = attrs.Offset,
			finish = attrs.End,
			volume = attrs.Volume,
			attributes = attrs,
		})
	end
end

return HttpService:JSONEncode(out)
```

## Package Selected Source Parts Into GameAssets

Run only in BossFight after the user explicitly asks to package and after the source instances are available in that Studio or have been inserted/copied there by Studio-owned means.

```lua
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BOSS_NAME = "BOSS_NAME"
local ABILITY_NAME = "ABILITY_NAME"
local SOURCE_ROOT_PATH = "Workspace.ABILITY_NAME"

local function resolvePath(path)
	local current = game
	for segment in string.gmatch(path, "[^%.]+") do
		if segment == "game" then
			current = game
		elseif segment == "Workspace" or segment == "workspace" then
			current = workspace
		elseif segment == "ReplicatedStorage" then
			current = ReplicatedStorage
		elseif current then
			current = current:FindFirstChild(segment)
		end
	end
	return current
end

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		error(("Cannot create Folder %s under %s because a %s already exists."):format(name, parent:GetFullName(), folder.ClassName))
	end
	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function hasEmittable(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("RayValue")
			or descendant:IsA("Sound") then
			return true
		end
	end
	return false
end

local function prepareModel(model)
	local primaryPart = model.PrimaryPart
	if not (primaryPart and primaryPart:IsDescendantOf(model)) then
		error("Packaged model " .. model:GetFullName() .. " is missing an in-model PrimaryPart.")
	end

	local oldWelds = model:FindFirstChild("Welds")
	if oldWelds then
		oldWelds:Destroy()
	end

	local weldsFolder = Instance.new("Folder")
	weldsFolder.Name = "Welds"
	weldsFolder.Parent = model

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			if part ~= primaryPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = part.Name
				weld.Part0 = primaryPart
				weld.Part1 = part
				weld.Parent = weldsFolder
				part.Anchored = false
				part.Massless = true
			end
		end
	end
end

local gameAssets = ensureFolder(ReplicatedStorage, "GameAssets")
local vfx = ensureFolder(gameAssets, "VFX")
local bossFolder = ensureFolder(vfx, BOSS_NAME)

local existingAbility = bossFolder:FindFirstChild(ABILITY_NAME)
if existingAbility then
	existingAbility:Destroy()
end

local abilityFolder = Instance.new("Folder")
abilityFolder.Name = ABILITY_NAME
abilityFolder.Parent = bossFolder

local sourceRoot = resolvePath(SOURCE_ROOT_PATH)
if not sourceRoot then
	error("Missing source root " .. SOURCE_ROOT_PATH)
end

local packaged = {}
for _, descendant in ipairs(sourceRoot:GetDescendants()) do
	if descendant:IsA("BasePart") and descendant.Name ~= ABILITY_NAME and hasEmittable(descendant) then
		local clone = descendant:Clone()
		local model = Instance.new("Model")
		model.Name = descendant.Name
		clone.Parent = model
		model.PrimaryPart = clone
		prepareModel(model)
		model.Parent = abilityFolder
		table.insert(packaged, {
			name = model.Name,
			primaryPart = clone.Name,
			path = model:GetFullName(),
			descendantCount = #model:GetDescendants(),
		})
	end
end

return HttpService:JSONEncode({
	target = abilityFolder:GetFullName(),
	packaged = packaged,
})
```

## Full Asset Transfer Bridge Setup

Use this when the package may exceed MCP output limits or when the source and target are different Studio sessions. Run the bridge from a temporary file outside the repo; do not commit it unless the user asks for a permanent tool. Replace `PYTHON_EXE` with the bundled workspace Python path from `load_workspace_dependencies` or another known local Python executable.

```powershell
$python = "PYTHON_EXE"
$env:VFX_BRIDGE_PORT = "8765"
$env:VFX_BRIDGE_KEY = "ABILITY_PACKAGE_KEY"
@'
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
import os

PORT = int(os.environ.get("VFX_BRIDGE_PORT", "8765"))
KEY = os.environ.get("VFX_BRIDGE_KEY", "default")
payloads = {}

class Handler(BaseHTTPRequestHandler):
    def _key(self):
        values = parse_qs(urlparse(self.path).query)
        return values.get("key", [KEY])[0]

    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        payloads[self._key()] = body
        self.send_response(200)
        self.end_headers()
        self.wfile.write(("stored %d bytes" % len(body)).encode("utf-8"))

    def do_GET(self):
        key = self._key()
        body = payloads.get(key)
        if body is None:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"missing key")
            return
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(fmt % args)

HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
'@ | Set-Content -Encoding UTF8 "$env:TEMP\boss_vfx_bridge.py"
& $python "$env:TEMP\boss_vfx_bridge.py"
```

## Full Asset Transfer Source Serializer

Run this in the source BossVFX Studio. Fill `ABILITY_NAME`, `BRIDGE_URL`, and `SOURCE_EFFECT_PATHS`. Use numeric IDs, not instance paths, as the identity layer.

```lua
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local ABILITY_NAME = "ABILITY_NAME"
local BRIDGE_URL = "http://127.0.0.1:8765/?key=ABILITY_PACKAGE_KEY"
local SOURCE_EFFECT_PATHS = {
	["Right Hand"] = "Workspace.ABILITY_NAME.Right Hand",
	["RootPart"] = "Workspace.ABILITY_NAME.RootPart",
	["TargetRootPart"] = "Workspace.ABILITY_NAME.TargetRootPart",
	["Beam"] = "Workspace.ABILITY_NAME.CatBeam.Beam",
	["End"] = "Workspace.ABILITY_NAME.CatBeam.End",
}

local attrNotes = {}
local nextId = 0
local ids = {}
local nodes = {}
local effects = {}
local deferredRefs = {}

local function resolvePath(path)
	local current = game
	for segment in string.gmatch(path, "[^%.]+") do
		if segment == "game" then
			current = game
		elseif segment == "Workspace" or segment == "workspace" then
			current = workspace
		elseif segment == "ReplicatedStorage" then
			current = game:GetService("ReplicatedStorage")
		elseif segment == "ServerStorage" then
			current = ServerStorage
		elseif current then
			current = current:FindFirstChild(segment)
		end
	end
	return current
end

local function getId(instance)
	local id = ids[instance]
	if id then
		return id
	end
	nextId += 1
	ids[instance] = nextId
	return nextId
end

local function safeString(value, context)
	local ok = pcall(function()
		HttpService:JSONEncode({ value })
	end)
	if ok then
		return value
	end
	local sanitized = string.gsub(value, "[%z\1-\31\127-\255]", "?")
	table.insert(attrNotes, {
		path = context.path,
		name = context.name,
		valueType = "string",
		reason = "sanitized for JSON encoding",
	})
	return sanitized
end

local function pack(value, context)
	local valueType = typeof(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "number" then
		return { t = valueType, v = value }
	elseif valueType == "string" then
		return { t = valueType, v = safeString(value, context) }
	elseif valueType == "Vector2" then
		return { t = valueType, v = { value.X, value.Y } }
	elseif valueType == "Vector3" then
		return { t = valueType, v = { value.X, value.Y, value.Z } }
	elseif valueType == "Color3" then
		return { t = valueType, v = { value.R, value.G, value.B } }
	elseif valueType == "CFrame" then
		return { t = valueType, v = { value:GetComponents() } }
	elseif valueType == "UDim" then
		return { t = valueType, v = { value.Scale, value.Offset } }
	elseif valueType == "UDim2" then
		return { t = valueType, v = { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset } }
	elseif valueType == "BrickColor" then
		return { t = valueType, v = value.Number }
	elseif valueType == "NumberRange" then
		return { t = valueType, v = { value.Min, value.Max } }
	elseif valueType == "NumberSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(keypoints, { keypoint.Time, keypoint.Value, keypoint.Envelope })
		end
		return { t = valueType, v = keypoints }
	elseif valueType == "ColorSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(keypoints, { keypoint.Time, keypoint.Value.R, keypoint.Value.G, keypoint.Value.B })
		end
		return { t = valueType, v = keypoints }
	elseif valueType == "EnumItem" then
		return { t = valueType, v = { enumType = tostring(value.EnumType), name = value.Name } }
	end
	return nil, "unsupported type " .. valueType
end

local PROPERTY_NAMES = {
	Attachment = { "CFrame", "Position", "Orientation", "Axis", "SecondaryAxis", "Visible" },
	Beam = {
		"Color", "Texture", "TextureLength", "TextureMode", "TextureSpeed", "Transparency",
		"Width0", "Width1", "CurveSize0", "CurveSize1", "Segments", "FaceCamera",
		"LightEmission", "LightInfluence", "Brightness", "Enabled", "ZOffset",
	},
	ParticleEmitter = {
		"Color", "LightEmission", "LightInfluence", "Orientation", "Size", "Squash",
		"Texture", "Transparency", "ZOffset", "EmissionDirection", "Enabled", "Lifetime",
		"Rate", "Rotation", "RotSpeed", "Speed", "SpreadAngle", "Shape", "ShapeInOut",
		"ShapeStyle", "Acceleration", "Drag", "LockedToPart", "TimeScale", "VelocityInheritance",
		"FlipbookFramerate", "FlipbookLayout", "FlipbookMode", "FlipbookStartRandom",
	},
	Trail = {
		"Color", "Texture", "TextureLength", "TextureMode", "Transparency", "WidthScale",
		"FaceCamera", "LightEmission", "LightInfluence", "Lifetime", "MinLength", "Enabled",
	},
	Sound = { "SoundId", "Volume", "PlaybackSpeed", "TimePosition", "RollOffMaxDistance", "RollOffMinDistance", "RollOffMode", "Looped" },
	PointLight = { "Brightness", "Color", "Enabled", "Range", "Shadows" },
	SpotLight = { "Angle", "Brightness", "Color", "Enabled", "Face", "Range", "Shadows" },
	SurfaceLight = { "Angle", "Brightness", "Color", "Enabled", "Face", "Range", "Shadows" },
	SpecialMesh = { "MeshId", "TextureId", "Scale", "Offset", "MeshType" },
	BasePart = {
		"CFrame", "Size", "Color", "Transparency", "Material", "Reflectance",
		"Anchored", "CanCollide", "CanTouch", "CanQuery", "Massless",
	},
}

local function readProperties(instance, path)
	local props = {}
	local names = {}
	if instance:IsA("BasePart") then
		for _, name in ipairs(PROPERTY_NAMES.BasePart) do
			table.insert(names, name)
		end
	end
	for _, name in ipairs(PROPERTY_NAMES[instance.ClassName] or {}) do
		table.insert(names, name)
	end
	for _, name in ipairs(names) do
		local ok, value = pcall(function()
			return instance[name]
		end)
		if ok then
			local packed, reason = pack(value, { path = path, name = name })
			if packed then
				props[name] = packed
			else
				props[name] = { skipped = true, reason = reason }
			end
		end
	end
	return props
end

local function readAttributes(instance, path)
	local out = {}
	for name, value in pairs(instance:GetAttributes()) do
		local packed, reason = pack(value, { path = path, name = name })
		if packed then
			out[name] = packed
		else
			out[name] = { skipped = true, valueType = typeof(value), reason = reason }
			table.insert(attrNotes, {
				path = path,
				name = name,
				valueType = typeof(value),
				reason = reason,
			})
		end
	end
	return out
end

local function serializeTree(effectName, root)
	local rootId = getId(root)
	table.insert(effects, { name = effectName, rootId = rootId, primaryPartId = rootId })

	local ordered = { root }
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(ordered, descendant)
	end

	for _, instance in ipairs(ordered) do
		local id = getId(instance)
		local parentId = if instance == root then nil else getId(instance.Parent)
		local path = instance:GetFullName()
		local node = {
			id = id,
			parentId = parentId,
			effectName = effectName,
			className = instance.ClassName,
			name = instance.Name,
			path = path,
			props = readProperties(instance, path),
			attributes = readAttributes(instance, path),
		}
		table.insert(nodes, node)

		if instance:IsA("Beam") or instance:IsA("Trail") then
			table.insert(deferredRefs, {
				id = id,
				attachment0Id = instance.Attachment0 and getId(instance.Attachment0) or nil,
				attachment1Id = instance.Attachment1 and getId(instance.Attachment1) or nil,
			})
		end
	end
end

for effectName, path in pairs(SOURCE_EFFECT_PATHS) do
	local root = resolvePath(string.gsub(path, "ABILITY_NAME", ABILITY_NAME))
	if not root then
		error("Missing source effect " .. effectName .. " at " .. path)
	end
	serializeTree(effectName, root)
end

local sounds = {}
local soundFolder = ServerStorage:FindFirstChild("LunarSound2")
	and ServerStorage.LunarSound2:FindFirstChild(ABILITY_NAME)
if soundFolder then
	for _, cue in ipairs(soundFolder:GetChildren()) do
		table.insert(sounds, {
			targetEffect = "Right Hand",
			name = cue.Name,
			className = cue.ClassName,
			assetId = if cue:IsA("StringValue") then cue.Value else nil,
			attributes = readAttributes(cue, cue:GetFullName()),
		})
	end
end

local payload = {
	abilityName = ABILITY_NAME,
	effects = effects,
	nodes = nodes,
	deferredRefs = deferredRefs,
	sounds = sounds,
	attributeNotes = attrNotes,
}

local body = HttpService:JSONEncode(payload)
local response = HttpService:PostAsync(BRIDGE_URL, body, Enum.HttpContentType.ApplicationJson, false)
return HttpService:JSONEncode({
	effectCount = #effects,
	nodeCount = #nodes,
	soundCount = #sounds,
	bodyBytes = #body,
	response = response,
	attributeNoteCount = #attrNotes,
})
```

## Full Asset Transfer Target Reconstructor

Run this in the target BossFight Studio after the source serializer has posted to the bridge.

```lua
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BOSS_NAME = "BOSS_NAME"
local ABILITY_NAME = "ABILITY_NAME"
local BRIDGE_URL = "http://127.0.0.1:8765/?key=ABILITY_PACKAGE_KEY"
local ALLOW_REPLACE_WITH_FAILURES = false

local propertyFailures = {}
local attributeFailures = {}
local unresolvedRefs = {}
local primaryFailures = {}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		error(("Expected Folder %s under %s, found %s"):format(name, parent:GetFullName(), folder.ClassName))
	end
	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function unpackValue(packed)
	if packed == nil or packed.skipped then
		return nil
	end
	local t = packed.t
	local v = packed.v
	if t == "nil" or t == "boolean" or t == "number" or t == "string" then
		return v
	elseif t == "Vector2" then
		return Vector2.new(v[1], v[2])
	elseif t == "Vector3" then
		return Vector3.new(v[1], v[2], v[3])
	elseif t == "Color3" then
		return Color3.new(v[1], v[2], v[3])
	elseif t == "CFrame" then
		return CFrame.new(table.unpack(v))
	elseif t == "UDim" then
		return UDim.new(v[1], v[2])
	elseif t == "UDim2" then
		return UDim2.new(v[1], v[2], v[3], v[4])
	elseif t == "BrickColor" then
		return BrickColor.new(v)
	elseif t == "NumberRange" then
		return NumberRange.new(v[1], v[2])
	elseif t == "NumberSequence" then
		local keypoints = {}
		for _, item in ipairs(v) do
			table.insert(keypoints, NumberSequenceKeypoint.new(item[1], item[2], item[3] or 0))
		end
		return NumberSequence.new(keypoints)
	elseif t == "ColorSequence" then
		local keypoints = {}
		for _, item in ipairs(v) do
			table.insert(keypoints, ColorSequenceKeypoint.new(item[1], Color3.new(item[2], item[3], item[4])))
		end
		return ColorSequence.new(keypoints)
	elseif t == "EnumItem" then
		local enumName = string.match(v.enumType, "Enum%.(.+)")
		local enumType = enumName and Enum[enumName]
		return enumType and enumType[v.name] or nil
	end
	return nil
end

local payload = HttpService:JSONDecode(HttpService:GetAsync(BRIDGE_URL))

local gameAssets = ensureFolder(ReplicatedStorage, "GameAssets")
local vfx = ensureFolder(gameAssets, "VFX")
local bossFolder = ensureFolder(vfx, BOSS_NAME)

local staging = bossFolder:FindFirstChild("__TransferStaging")
if staging then
	staging:Destroy()
end
staging = Instance.new("Folder")
staging.Name = "__TransferStaging"
staging.Parent = bossFolder

local byId = {}
local modelsByEffect = {}
for _, effect in ipairs(payload.effects) do
	local model = Instance.new("Model")
	model.Name = effect.name
	model.Parent = staging
	modelsByEffect[effect.name] = model
end

for _, node in ipairs(payload.nodes) do
	local ok, instance = pcall(Instance.new, node.className)
	if not ok then
		error(("Cannot create %s from source %s"):format(node.className, node.path))
	end
	instance.Name = node.name
	byId[node.id] = instance
end

for _, node in ipairs(payload.nodes) do
	local instance = byId[node.id]
	if node.parentId then
		instance.Parent = byId[node.parentId]
	else
		instance.Parent = modelsByEffect[node.effectName]
	end
end

for _, node in ipairs(payload.nodes) do
	local instance = byId[node.id]
	for name, packed in pairs(node.props or {}) do
		if packed.skipped then
			table.insert(propertyFailures, { path = node.path, name = name, reason = packed.reason })
		else
			local value = unpackValue(packed)
			local ok, err = pcall(function()
				instance[name] = value
			end)
			if not ok then
				table.insert(propertyFailures, { path = node.path, name = name, reason = tostring(err) })
			end
		end
	end
	for name, packed in pairs(node.attributes or {}) do
		if packed.skipped then
			table.insert(attributeFailures, { path = node.path, name = name, valueType = packed.valueType, reason = packed.reason })
		else
			local value = unpackValue(packed)
			local ok, err = pcall(function()
				instance:SetAttribute(name, value)
			end)
			if not ok then
				table.insert(attributeFailures, { path = node.path, name = name, valueType = packed.t, reason = tostring(err) })
			end
		end
	end
end

for _, ref in ipairs(payload.deferredRefs or {}) do
	local instance = byId[ref.id]
	if instance and (instance:IsA("Beam") or instance:IsA("Trail")) then
		local a0 = ref.attachment0Id and byId[ref.attachment0Id] or nil
		local a1 = ref.attachment1Id and byId[ref.attachment1Id] or nil
		if ref.attachment0Id and not a0 then
			table.insert(unresolvedRefs, { id = ref.id, property = "Attachment0", targetId = ref.attachment0Id })
		else
			instance.Attachment0 = a0
		end
		if ref.attachment1Id and not a1 then
			table.insert(unresolvedRefs, { id = ref.id, property = "Attachment1", targetId = ref.attachment1Id })
		else
			instance.Attachment1 = a1
		end
	end
end

for _, effect in ipairs(payload.effects) do
	local model = modelsByEffect[effect.name]
	local primary = byId[effect.primaryPartId]
	if model and primary and primary:IsA("BasePart") and primary:IsDescendantOf(model) then
		model.PrimaryPart = primary
	else
		table.insert(primaryFailures, { effectName = effect.name, primaryPartId = effect.primaryPartId })
	end
end

for _, cue in ipairs(payload.sounds or {}) do
	local model = modelsByEffect[cue.targetEffect]
	local parent = model and model.PrimaryPart
	if parent then
		local sound = Instance.new("Sound")
		sound.Name = cue.name
		if cue.assetId then
			sound.SoundId = cue.assetId
		end
		sound.Parent = parent
		for name, packed in pairs(cue.attributes or {}) do
			local value = unpackValue(packed)
			local ok = pcall(function()
				sound:SetAttribute(name, value)
			end)
			if ok and name == "Start" and typeof(value) == "number" then
				sound:SetAttribute("Delay", value)
				sound:SetAttribute("SourceStart", value)
			elseif ok and name == "End" then
				sound:SetAttribute("SourceEnd", value)
			elseif ok and name == "Volume" and typeof(value) == "number" then
				sound.Volume = value
			elseif ok and name == "Offset" and typeof(value) == "number" then
				sound.TimePosition = value
			end
		end
	end
end

local function prepareModel(model)
	local primary = model.PrimaryPart
	if not (primary and primary:IsDescendantOf(model)) then
		return
	end
	local oldWelds = model:FindFirstChild("Welds")
	if oldWelds then
		oldWelds:Destroy()
	end
	local welds = Instance.new("Folder")
	welds.Name = "Welds"
	welds.Parent = model
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			if part ~= primary then
				part.Anchored = false
				part.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Name = part.Name
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = welds
			end
		end
	end
end

for _, model in pairs(modelsByEffect) do
	prepareModel(model)
end

local function countClasses(root)
	local counts = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		counts[descendant.ClassName] = (counts[descendant.ClassName] or 0) + 1
		if descendant:IsA("BasePart") then
			counts.BasePart = (counts.BasePart or 0) + 1
		end
	end
	return counts
end

local effects = {}
for _, model in ipairs(staging:GetChildren()) do
	table.insert(effects, {
		name = model.Name,
		primaryPart = model:IsA("Model") and model.PrimaryPart and model.PrimaryPart.Name or nil,
		counts = countClasses(model),
	})
end

local canReplace = #unresolvedRefs == 0
	and #primaryFailures == 0
	and (#propertyFailures == 0 or ALLOW_REPLACE_WITH_FAILURES)
	and (#attributeFailures == 0 or ALLOW_REPLACE_WITH_FAILURES)

if canReplace then
	local existing = bossFolder:FindFirstChild(ABILITY_NAME)
	if existing then
		existing:Destroy()
	end
	staging.Name = ABILITY_NAME
else
	warn("Leaving reconstructed package in staging because validation found failures.")
end

return HttpService:JSONEncode({
	replaced = canReplace,
	target = canReplace and bossFolder[ABILITY_NAME]:GetFullName() or staging:GetFullName(),
	effectCount = #(payload.effects or {}),
	nodeCount = #(payload.nodes or {}),
	soundCount = #(payload.sounds or {}),
	effects = effects,
	propertyFailureCount = #propertyFailures,
	attributeFailureCount = #attributeFailures,
	propertyFailures = propertyFailures,
	attributeFailures = attributeFailures,
	unresolvedRefs = unresolvedRefs,
	primaryFailures = primaryFailures,
	sourceAttributeNotes = payload.attributeNotes or {},
})
```

## Validate Final BossFight Package Against Bridge Payload

Run this after reconstruction. It compares the bridge payload against the final target package and verifies model paths, PrimaryParts, class counts, collision/query state, and unresolved Beam/Trail references.

```lua
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BOSS_NAME = "BOSS_NAME"
local ABILITY_NAME = "ABILITY_NAME"
local BRIDGE_URL = "http://127.0.0.1:8765/?key=ABILITY_PACKAGE_KEY"
local REQUIRED_EFFECTS = { "Right Hand", "RootPart", "TargetRootPart", "Beam", "End" }

local payload = HttpService:JSONDecode(HttpService:GetAsync(BRIDGE_URL))
local package = ReplicatedStorage:FindFirstChild("GameAssets")
	and ReplicatedStorage.GameAssets:FindFirstChild("VFX")
	and ReplicatedStorage.GameAssets.VFX:FindFirstChild(BOSS_NAME)
	and ReplicatedStorage.GameAssets.VFX[BOSS_NAME]:FindFirstChild(ABILITY_NAME)

local function newCounts()
	return {
		BasePart = 0,
		Model = 0,
		Attachment = 0,
		ParticleEmitter = 0,
		Beam = 0,
		Trail = 0,
		Sound = 0,
	}
end

local function countSource(effectName)
	local counts = newCounts()
	counts.Model = 1
	for _, node in ipairs(payload.nodes or {}) do
		if node.effectName == effectName then
			if node.className == "Part"
				or node.className == "MeshPart"
				or node.className == "UnionOperation"
				or node.className == "WedgePart"
				or node.className == "CornerWedgePart"
				or node.className == "TrussPart" then
				counts.BasePart += 1
			end
			if counts[node.className] ~= nil then
				counts[node.className] += 1
			end
		end
	end
	for _, cue in ipairs(payload.sounds or {}) do
		if cue.targetEffect == effectName then
			counts.Sound += 1
		end
	end
	return counts
end

local function countTarget(root)
	local counts = newCounts()
	if root:IsA("Model") then
		counts.Model += 1
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			counts.BasePart += 1
		end
		if counts[descendant.ClassName] ~= nil then
			counts[descendant.ClassName] += 1
		end
	end
	return counts
end

local out = {
	packageExists = package ~= nil,
	effects = {},
	missingRequiredEffects = {},
	unresolvedRefs = {},
	basePartStateFailures = {},
	primaryFailures = {},
	sourceAttributeNotes = payload.attributeNotes or {},
}

if package then
	for _, effectName in ipairs(REQUIRED_EFFECTS) do
		if not package:FindFirstChild(effectName) then
			table.insert(out.missingRequiredEffects, effectName)
		end
	end

	for _, effect in ipairs(package:GetChildren()) do
		local item = {
			name = effect.Name,
			className = effect.ClassName,
			primaryPart = effect:IsA("Model") and effect.PrimaryPart and effect.PrimaryPart.Name or nil,
			sourceCounts = countSource(effect.Name),
			targetCounts = countTarget(effect),
		}
		if effect:IsA("Model") and not (effect.PrimaryPart and effect.PrimaryPart:IsDescendantOf(effect)) then
			table.insert(out.primaryFailures, effect.Name)
		end
		for _, descendant in ipairs(effect:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if descendant.CanCollide or descendant.CanTouch or descendant.CanQuery then
					table.insert(out.basePartStateFailures, {
						path = descendant:GetFullName(),
						canCollide = descendant.CanCollide,
						canTouch = descendant.CanTouch,
						canQuery = descendant.CanQuery,
					})
				end
			elseif descendant:IsA("Beam") or descendant:IsA("Trail") then
				if not descendant.Attachment0 then
					table.insert(out.unresolvedRefs, { path = descendant:GetFullName(), property = "Attachment0" })
				end
				if not descendant.Attachment1 then
					table.insert(out.unresolvedRefs, { path = descendant:GetFullName(), property = "Attachment1" })
				end
			end
		end
		table.insert(out.effects, item)
	end
end

return HttpService:JSONEncode(out)
```

## Summarize Final BossFight Package

```lua
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BOSS_NAME = "BOSS_NAME"
local ABILITY_NAME = "ABILITY_NAME"

local package = ReplicatedStorage:FindFirstChild("GameAssets")
	and ReplicatedStorage.GameAssets:FindFirstChild("VFX")
	and ReplicatedStorage.GameAssets.VFX:FindFirstChild(BOSS_NAME)
	and ReplicatedStorage.GameAssets.VFX[BOSS_NAME]:FindFirstChild(ABILITY_NAME)

local out = { exists = package ~= nil, effects = {} }
if package then
	for _, effect in ipairs(package:GetChildren()) do
		local item = {
			name = effect.Name,
			className = effect.ClassName,
			primaryPart = effect:IsA("Model") and effect.PrimaryPart and effect.PrimaryPart.Name or nil,
			counts = {},
			baseParts = {},
		}
		for _, descendant in ipairs(effect:GetDescendants()) do
			item.counts[descendant.ClassName] = (item.counts[descendant.ClassName] or 0) + 1
			if descendant:IsA("BasePart") then
				table.insert(item.baseParts, {
					name = descendant.Name,
					anchored = descendant.Anchored,
					canCollide = descendant.CanCollide,
					canTouch = descendant.CanTouch,
					canQuery = descendant.CanQuery,
					massless = descendant.Massless,
				})
			end
		end
		table.insert(out.effects, item)
	end
end

return HttpService:JSONEncode(out)
```
