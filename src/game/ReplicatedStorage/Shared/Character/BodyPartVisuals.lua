local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryScaleUtils = require(script.Parent.AccessoryScaleUtils)
local BodyPartRegions = require(script.Parent.BodyPartRegions)
local CharacterAppearanceHostApplier = require(script.Parent.CharacterAppearanceHostApplier)
local PerfStats = require(ReplicatedStorage.Shared.Diagnostics.PerfStats)

local BodyPartVisuals = {}

export type AttachRule = {
	templateChildName: string?,
	offsetCFrame: CFrame?,
	visualOffsetCFrame: CFrame?,
	hideCharacterPart: boolean?,
}

export type ApplyMutationRequest = {
	id: string,
	model: Model,
}

export type ApplyRegionRequest = {
	bundle: Model?,
	scale: number?,
	attachRules: { [string]: AttachRule }?,
	mutation: ApplyMutationRequest?,
	isNativeFallback: boolean?,
	applyPlayerClothing: boolean?,
	applyPlayerBodyColors: boolean?,
}

export type ApplyAuraRequest = {
	id: string,
	model: Model,
}

export type ApplyRequest = {
	baseRig: Model,
	regions: { [string]: ApplyRegionRequest? },
	aura: ApplyAuraRequest?,
}

export type ApplyResult = {
	success: boolean,
	errors: { string },
	appliedRegions: { string },
	hipHeight: number?,
}

local APPLIED_FOLDER_NAME = "CharacterBodyParts"
local AURA_RUNTIME_ATTRIBUTE = "BodyPartAuraManaged"
local AURA_ID_ATTRIBUTE = "BodyPartAuraId"
local MUTATION_RUNTIME_ATTRIBUTE = "BodyPartMutationManaged"
local MUTATION_ID_ATTRIBUTE = "BodyPartMutationId"
local MUTATION_REGION_ATTRIBUTE = "BodyPartMutationRegion"
local TRANSPARENCY_ATTRIBUTE_PREFIX = "BodyPartOriginalTransparency_"
local COLLISION_ATTRIBUTE_PREFIX = "BodyPartOriginalCanCollide_"
local DECAL_ATTRIBUTE_PREFIX = "BodyPartOriginalDecalTransparency_"
local ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE = "AssemblyAnchorPartName"
local ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE = "AssemblyAnchorOffset"
local ASSEMBLY_OWNING_REGION_ATTRIBUTE = "AssemblyOwningRegion"
local ASSEMBLY_SOURCE_NAME_ATTRIBUTE = "AssemblySourceName"
local ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE = "AssemblyTargetPartName"
local ASSEMBLY_ANCHOR_PART_ATTRIBUTE = "AssemblyAnchor"
local HAS_IMPORTED_BODY_COLORS_ATTRIBUTE = "HasImportedBodyColors"
local REGION_SOURCE_ATTRIBUTE = "RegionSource"
local REGION_SOURCE_BUNDLE = "Bundle"
local REGION_SOURCE_NATIVE_FALLBACK = "NativeFallback"

local REGION_PARTS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "LowerTorso" },
	LeftArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RightArm = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LeftLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	RightLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

local PART_NAME_TO_REGION = {}
for region, partNames in pairs(REGION_PARTS) do
	for _, partName in ipairs(partNames) do
		PART_NAME_TO_REGION[partName] = region
	end
end
table.freeze(PART_NAME_TO_REGION)

local ALL_RIG_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local AURA_TARGET_PART_NAMES = table.freeze({
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
	HumanoidRootPart = true,
})

local AURA_ATTACHMENT_REFERENCE_PROPERTIES_BY_CLASS = table.freeze({
	Beam = { "Attachment0", "Attachment1" },
	Trail = { "Attachment0", "Attachment1" },
})

local MUTATION_RUNTIME_ALLOWED_CHILD_CLASSES = table.freeze({
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
})

local SUPPORT_PART_NAMES = { "LeftFoot", "RightFoot" }

local ALWAYS_ALLOWED_CHILD_CLASSES = {
	Attachment = true,
	Beam = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
	WrapTarget = true,
	SpecialMesh = true,
	FaceControls = true,
	ParticleEmitter = true,
}

local FORBIDDEN_BUNDLE_CLASSES = {
	Motor6D = true,
	Animator = true,
	AnimationController = true,
}

local USE_SOULS_STYLE_RUNTIME = true
local PLACEMENT_MODE_ARTICULATED = "CustomArticulatedPlacement"
local PLACEMENT_MODE_AUTHORED = "AuthoredAssemblyPlacement"
local PLACEMENT_MODE_CHAIN = "InternalChainPlacement"
local PLACEMENT_MODE_PIVOT = "PivotPlacement"
local PLACEMENT_MODE_TORSO_JOINT = "TorsoJointPlacement"
local PLACEMENT_MODE_ARM_JOINT = "ArmJointChainPlacement"
local PLACEMENT_MODE_LEG_JOINT = "LegJointChainPlacement"
local TRANSFORM_ROTATION_TOLERANCE = math.rad(1)
local RIG_ATTACHMENT_ROTATION_TOLERANCE = math.rad(1)
local FOOTING_SETTLE_MAX_PASSES = 3
local FOOTING_SETTLE_TOLERANCE = 0.01

local REGION_NATIVE_RIG_ATTACHMENT_SPECS = {
	Head = {
		RequiredAttachments = {
			{ PartName = "Head", AttachmentName = "NeckRigAttachment" },
		},
	},
	Torso = {
		RequiredAttachments = {
			{ PartName = "UpperTorso", AttachmentName = "NeckRigAttachment" },
			{ PartName = "UpperTorso", AttachmentName = "LeftShoulderRigAttachment" },
			{ PartName = "UpperTorso", AttachmentName = "RightShoulderRigAttachment" },
			{ PartName = "UpperTorso", AttachmentName = "WaistRigAttachment" },
			{ PartName = "LowerTorso", AttachmentName = "RootRigAttachment" },
			{ PartName = "LowerTorso", AttachmentName = "LeftHipRigAttachment" },
			{ PartName = "LowerTorso", AttachmentName = "RightHipRigAttachment" },
			{ PartName = "LowerTorso", AttachmentName = "WaistRigAttachment" },
		},
	},
	LeftArm = {
		RequiredAttachments = {
			{ PartName = "LeftUpperArm", AttachmentName = "LeftShoulderRigAttachment" },
			{ PartName = "LeftLowerArm", AttachmentName = "LeftElbowRigAttachment" },
			{ PartName = "LeftHand", AttachmentName = "LeftWristRigAttachment" },
		},
	},
	RightArm = {
		RequiredAttachments = {
			{ PartName = "RightUpperArm", AttachmentName = "RightShoulderRigAttachment" },
			{ PartName = "RightLowerArm", AttachmentName = "RightElbowRigAttachment" },
			{ PartName = "RightHand", AttachmentName = "RightWristRigAttachment" },
		},
	},
	LeftLeg = {
		RequiredAttachments = {
			{ PartName = "LeftUpperLeg", AttachmentName = "LeftHipRigAttachment" },
			{ PartName = "LeftLowerLeg", AttachmentName = "LeftKneeRigAttachment" },
			{ PartName = "LeftFoot", AttachmentName = "LeftAnkleRigAttachment" },
		},
	},
	RightLeg = {
		RequiredAttachments = {
			{ PartName = "RightUpperLeg", AttachmentName = "RightHipRigAttachment" },
			{ PartName = "RightLowerLeg", AttachmentName = "RightKneeRigAttachment" },
			{ PartName = "RightFoot", AttachmentName = "RightAnkleRigAttachment" },
		},
	},
}

local REGION_ARTICULATION_SPECS = {
	Torso = {
		RootPartName = "LowerTorso",
		Constraints = {
			{
				HolderPartName = "UpperTorso",
				ConstraintName = "Waist",
				Attachment0PartName = "LowerTorso",
				Attachment0Name = "WaistRigAttachment",
				Attachment1PartName = "UpperTorso",
				Attachment1Name = "WaistRigAttachment",
			},
		},
	},
	LeftArm = {
		RootPartName = "LeftUpperArm",
		Constraints = {
			{
				HolderPartName = "LeftLowerArm",
				ConstraintName = "LeftElbow",
				Attachment0PartName = "LeftUpperArm",
				Attachment0Name = "LeftElbowRigAttachment",
				Attachment1PartName = "LeftLowerArm",
				Attachment1Name = "LeftElbowRigAttachment",
			},
			{
				HolderPartName = "LeftHand",
				ConstraintName = "LeftWrist",
				Attachment0PartName = "LeftLowerArm",
				Attachment0Name = "LeftWristRigAttachment",
				Attachment1PartName = "LeftHand",
				Attachment1Name = "LeftWristRigAttachment",
			},
		},
	},
	RightArm = {
		RootPartName = "RightUpperArm",
		Constraints = {
			{
				HolderPartName = "RightLowerArm",
				ConstraintName = "RightElbow",
				Attachment0PartName = "RightUpperArm",
				Attachment0Name = "RightElbowRigAttachment",
				Attachment1PartName = "RightLowerArm",
				Attachment1Name = "RightElbowRigAttachment",
			},
			{
				HolderPartName = "RightHand",
				ConstraintName = "RightWrist",
				Attachment0PartName = "RightLowerArm",
				Attachment0Name = "RightWristRigAttachment",
				Attachment1PartName = "RightHand",
				Attachment1Name = "RightWristRigAttachment",
			},
		},
	},
	LeftLeg = {
		RootPartName = "LeftUpperLeg",
		Constraints = {
			{
				HolderPartName = "LeftLowerLeg",
				ConstraintName = "LeftKnee",
				Attachment0PartName = "LeftUpperLeg",
				Attachment0Name = "LeftKneeRigAttachment",
				Attachment1PartName = "LeftLowerLeg",
				Attachment1Name = "LeftKneeRigAttachment",
			},
			{
				HolderPartName = "LeftFoot",
				ConstraintName = "LeftAnkle",
				Attachment0PartName = "LeftLowerLeg",
				Attachment0Name = "LeftAnkleRigAttachment",
				Attachment1PartName = "LeftFoot",
				Attachment1Name = "LeftAnkleRigAttachment",
			},
		},
	},
	RightLeg = {
		RootPartName = "RightUpperLeg",
		Constraints = {
			{
				HolderPartName = "RightLowerLeg",
				ConstraintName = "RightKnee",
				Attachment0PartName = "RightUpperLeg",
				Attachment0Name = "RightKneeRigAttachment",
				Attachment1PartName = "RightLowerLeg",
				Attachment1Name = "RightKneeRigAttachment",
			},
			{
				HolderPartName = "RightFoot",
				ConstraintName = "RightAnkle",
				Attachment0PartName = "RightLowerLeg",
				Attachment0Name = "RightAnkleRigAttachment",
				Attachment1PartName = "RightFoot",
				Attachment1Name = "RightAnkleRigAttachment",
			},
		},
	},
}

local REGION_AUTHORED_ASSEMBLY_SPECS = {
	Torso = {
		RootPartName = "LowerTorso",
	},
	LeftArm = {
		RootPartName = "LeftUpperArm",
	},
	RightArm = {
		RootPartName = "RightUpperArm",
	},
	LeftLeg = {
		RootPartName = "LeftUpperLeg",
	},
	RightLeg = {
		RootPartName = "RightUpperLeg",
	},
}

local REGION_CHAIN_SPECS = {
	Torso = {
		RootPartName = "LowerTorso",
		Steps = {
			{
				FromPartName = "LowerTorso",
				ToPartName = "UpperTorso",
				AttachmentName = "WaistRigAttachment",
			},
		},
	},
	LeftArm = {
		RootPartName = "LeftUpperArm",
		Steps = {
			{
				FromPartName = "LeftUpperArm",
				ToPartName = "LeftLowerArm",
				AttachmentName = "LeftElbowRigAttachment",
			},
			{
				FromPartName = "LeftLowerArm",
				ToPartName = "LeftHand",
				AttachmentName = "LeftWristRigAttachment",
			},
		},
	},
	RightArm = {
		RootPartName = "RightUpperArm",
		Steps = {
			{
				FromPartName = "RightUpperArm",
				ToPartName = "RightLowerArm",
				AttachmentName = "RightElbowRigAttachment",
			},
			{
				FromPartName = "RightLowerArm",
				ToPartName = "RightHand",
				AttachmentName = "RightWristRigAttachment",
			},
		},
	},
	LeftLeg = {
		RootPartName = "LeftUpperLeg",
		Steps = {
			{
				FromPartName = "LeftUpperLeg",
				ToPartName = "LeftLowerLeg",
				AttachmentName = "LeftKneeRigAttachment",
			},
			{
				FromPartName = "LeftLowerLeg",
				ToPartName = "LeftFoot",
				AttachmentName = "LeftAnkleRigAttachment",
			},
		},
	},
	RightLeg = {
		RootPartName = "RightUpperLeg",
		Steps = {
			{
				FromPartName = "RightUpperLeg",
				ToPartName = "RightLowerLeg",
				AttachmentName = "RightKneeRigAttachment",
			},
			{
				FromPartName = "RightLowerLeg",
				ToPartName = "RightFoot",
				AttachmentName = "RightAnkleRigAttachment",
			},
		},
	},
}

local TORSO_SEAM_DEPENDENT_REGIONS = {
	"Head",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

local FULL_LOADOUT_REGION_ORDER = {
	"Torso",
	"Head",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

local REGION_EXTERNAL_SEAM_SPECS = {
	Head = {
		AnchorRegion = "Torso",
		AnchorPartName = "UpperTorso",
		MovingRootPartName = "Head",
		AttachmentName = "NeckRigAttachment",
	},
	LeftArm = {
		AnchorRegion = "Torso",
		AnchorPartName = "UpperTorso",
		MovingRootPartName = "LeftUpperArm",
		AttachmentName = "LeftShoulderRigAttachment",
	},
	RightArm = {
		AnchorRegion = "Torso",
		AnchorPartName = "UpperTorso",
		MovingRootPartName = "RightUpperArm",
		AttachmentName = "RightShoulderRigAttachment",
	},
	LeftLeg = {
		AnchorRegion = "Torso",
		AnchorPartName = "LowerTorso",
		MovingRootPartName = "LeftUpperLeg",
		AttachmentName = "LeftHipRigAttachment",
	},
	RightLeg = {
		AnchorRegion = "Torso",
		AnchorPartName = "LowerTorso",
		MovingRootPartName = "RightUpperLeg",
		AttachmentName = "RightHipRigAttachment",
	},
}

local baselineSnapshots = setmetatable({}, { __mode = "k" })
local appliedRegionRequestsByCharacter = setmetatable({}, { __mode = "k" })
local appliedRegionReferenceOffsetsByCharacter = setmetatable({}, { __mode = "k" })
local applyRegion
local findDirectAttachment
local findDirectAnimationConstraint
local usesLiveRigJointChainPlacement

local function getRotationOnly(cframe: CFrame): CFrame
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	return CFrame.fromMatrix(
		Vector3.zero,
		Vector3.new(r00, r10, r20),
		Vector3.new(r01, r11, r21),
		Vector3.new(r02, r12, r22)
	)
end

local function composeCFrame(position: Vector3, rotation: CFrame): CFrame
	return CFrame.new(position) * rotation
end

local function scaleVectorBySizeRatio(vector: Vector3, baseSize: Vector3, targetSize: Vector3): Vector3
	return Vector3.new(
		baseSize.X ~= 0 and vector.X * targetSize.X / baseSize.X or vector.X,
		baseSize.Y ~= 0 and vector.Y * targetSize.Y / baseSize.Y or vector.Y,
		baseSize.Z ~= 0 and vector.Z * targetSize.Z / baseSize.Z or vector.Z
	)
end

local function getScalarSizeRatio(baseSize: Vector3, targetSize: Vector3): number
	local baseMagnitude = baseSize.Magnitude
	local targetMagnitude = targetSize.Magnitude
	if baseMagnitude == baseMagnitude
		and targetMagnitude == targetMagnitude
		and baseMagnitude > 0
		and baseMagnitude < math.huge
		and baseMagnitude > -math.huge
		and targetMagnitude > 0
		and targetMagnitude < math.huge
		and targetMagnitude > -math.huge
	then
		return targetMagnitude / baseMagnitude
	end

	return 1
end

local function scaleNumberSequenceByRatio(sequence: NumberSequence, ratio: number): NumberSequence
	local keypoints = table.create(#sequence.Keypoints)
	for index, keypoint in ipairs(sequence.Keypoints) do
		keypoints[index] = NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * ratio, keypoint.Envelope * ratio)
	end
	return NumberSequence.new(keypoints)
end

local function scaleNumberByRatio(value: number, ratio: number): number
	return value * ratio
end

local function scaleMutationCloneTree(cloneRoot: BasePart, baseSize: Vector3, targetSize: Vector3)
	local scalarRatio = getScalarSizeRatio(baseSize, targetSize)
	if scalarRatio == 1 and baseSize == targetSize then
		return
	end

	for _, descendant in ipairs(cloneRoot:GetDescendants()) do
		if descendant:IsA("Attachment") then
			descendant.Position = scaleVectorBySizeRatio(descendant.Position, baseSize, targetSize)
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Size = scaleNumberSequenceByRatio(descendant.Size, scalarRatio)
		elseif descendant:IsA("Beam") then
			descendant.Width0 = descendant.Width0 * scalarRatio
			descendant.Width1 = descendant.Width1 * scalarRatio
		elseif descendant:IsA("Trail") then
			descendant.WidthScale = scaleNumberSequenceByRatio(descendant.WidthScale, scalarRatio)
		elseif descendant:IsA("SpecialMesh") then
			descendant.Scale = scaleVectorBySizeRatio(descendant.Scale, baseSize, targetSize)
		end
	end
end

local function scaleAuraCloneTree(cloneRoot: BasePart, requestedScale: number)
	if requestedScale == 1 then
		return
	end

	for _, descendant in ipairs(cloneRoot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Size = descendant.Size * requestedScale
		elseif descendant:IsA("Attachment") then
			descendant.Position = descendant.Position * requestedScale
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Size = scaleNumberSequenceByRatio(descendant.Size, requestedScale)
		elseif descendant:IsA("Beam") then
			descendant.Width0 = scaleNumberByRatio(descendant.Width0, requestedScale)
			descendant.Width1 = scaleNumberByRatio(descendant.Width1, requestedScale)
			descendant.CurveSize0 = scaleNumberByRatio(descendant.CurveSize0, requestedScale)
			descendant.CurveSize1 = scaleNumberByRatio(descendant.CurveSize1, requestedScale)
			descendant.TextureLength = scaleNumberByRatio(descendant.TextureLength, requestedScale)
		elseif descendant:IsA("Trail") then
			descendant.WidthScale = scaleNumberSequenceByRatio(descendant.WidthScale, requestedScale)
		elseif descendant:IsA("SpecialMesh") then
			descendant.Scale = descendant.Scale * requestedScale
			descendant.Offset = descendant.Offset * requestedScale
		elseif descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
			descendant.Range = scaleNumberByRatio(descendant.Range, requestedScale)
		end
	end
end

local function cloneSizeMap(sizeMap: { [string]: Vector3 }): { [string]: Vector3 }
	local copy = {}
	for name, size in pairs(sizeMap) do
		copy[name] = size
	end
	return copy
end

local function getTransparencyAttribute(region: string): string
	return TRANSPARENCY_ATTRIBUTE_PREFIX .. region
end

local function getCollisionAttribute(region: string): string
	return COLLISION_ATTRIBUTE_PREFIX .. region
end

local function getDecalAttribute(region: string): string
	return DECAL_ATTRIBUTE_PREFIX .. region
end

local function getRigPartNames(region: string): { string }?
	local partNames = REGION_PARTS[region]
	if not partNames then
		return nil
	end

	local copy = table.create(#partNames)
	for index, partName in ipairs(partNames) do
		copy[index] = partName
	end
	return copy
end

local function getRigPartLookup(region: string): { [string]: boolean }?
	local partNames = REGION_PARTS[region]
	if not partNames then
		return nil
	end

	local lookup = {}
	for _, partName in ipairs(partNames) do
		lookup[partName] = true
	end
	return lookup
end

local function isFinitePositiveNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < math.huge and value > -math.huge
end

local function isKorbloxDeathspeakerTorsoBundle(bundle: Model?): boolean
	if not (bundle and bundle:IsA("Model")) then
		return false
	end

	local bundleGroup = bundle.Parent
	return bundle.Name == "Deathspeaker" and bundleGroup ~= nil and bundleGroup.Name == "Korblox"
end

local function getBodyPartTargetSize(bundle: Model?, partName: string, bodyPart: BasePart, scale: number): Vector3
	local targetSize = bodyPart.Size * scale
	if partName == "UpperTorso" and isKorbloxDeathspeakerTorsoBundle(bundle) then
		return Vector3.new(targetSize.X, 3 * scale, targetSize.Z)
	end

	return targetSize
end

local function getFinalScale(request: ApplyRegionRequest): number
	if request and isFinitePositiveNumber(request.scale) then
		return request.scale
	end
	return 1
end

local function getAppliedFolder(character: Model): Folder
	local folder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = APPLIED_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function getRegionFolder(character: Model, region: string): Model
	local appliedFolder = getAppliedFolder(character)
	local regionFolder = appliedFolder:FindFirstChild(region)
	if regionFolder and regionFolder:IsA("Model") then
		return regionFolder
	end
	if regionFolder then
		regionFolder:Destroy()
	end

	regionFolder = Instance.new("Model")
	regionFolder.Name = region
	regionFolder.Parent = appliedFolder
	return regionFolder
end

local function cloneAttachRules(attachRules: { [string]: AttachRule }?): { [string]: AttachRule }?
	if typeof(attachRules) ~= "table" then
		return nil
	end

	local cloned = {}
	for partName, attachRule in pairs(attachRules) do
		if typeof(partName) == "string" and typeof(attachRule) == "table" then
			cloned[partName] = {
				templateChildName = attachRule.templateChildName,
				offsetCFrame = attachRule.offsetCFrame,
				visualOffsetCFrame = attachRule.visualOffsetCFrame,
				hideCharacterPart = attachRule.hideCharacterPart,
			}
		end
	end

	return next(cloned) and cloned or nil
end

local function cloneMutationRequest(mutationRequest: ApplyMutationRequest?): ApplyMutationRequest?
	if typeof(mutationRequest) ~= "table" then
		return nil
	end

	local mutationModel = mutationRequest.model
	if typeof(mutationRequest.id) ~= "string" or mutationRequest.id == "" then
		return nil
	end
	if not (mutationModel and mutationModel:IsA("Model")) then
		return nil
	end

	return {
		id = mutationRequest.id,
		model = mutationModel,
	}
end

local function cloneRegionRequest(regionRequest: ApplyRegionRequest?): ApplyRegionRequest?
	if typeof(regionRequest) ~= "table" then
		return nil
	end

	local bundle = regionRequest.bundle
	if not (bundle and bundle:IsA("Model")) then
		return nil
	end

	return {
		bundle = bundle,
		scale = regionRequest.scale,
		attachRules = cloneAttachRules(regionRequest.attachRules),
		mutation = cloneMutationRequest(regionRequest.mutation),
		applyPlayerClothing = regionRequest.applyPlayerClothing,
		applyPlayerBodyColors = regionRequest.applyPlayerBodyColors,
	}
end

local function getAttachRule(regionRequest: ApplyRegionRequest?, partName: string): AttachRule
	local attachRules = regionRequest and regionRequest.attachRules or nil
	local attachRule = attachRules and attachRules[partName] or nil
	if typeof(attachRule) == "table" then
		return attachRule
	end

	return {}
end

local function getAppliedRegionRequests(character: Model): { [string]: ApplyRegionRequest }
	local requests = appliedRegionRequestsByCharacter[character]
	if requests then
		return requests
	end

	requests = {}
	appliedRegionRequestsByCharacter[character] = requests
	return requests
end

local function storeAppliedRegionRequest(character: Model, region: string, regionRequest: ApplyRegionRequest?)
	local requests = getAppliedRegionRequests(character)
	local clonedRequest = cloneRegionRequest(regionRequest)
	if clonedRequest then
		requests[region] = clonedRequest
	else
		requests[region] = nil
	end
end

local function clearAppliedRegionRequests(character: Model)
	appliedRegionRequestsByCharacter[character] = nil
end

local function getAppliedRegionReferenceOffsets(character: Model): { [string]: { [string]: CFrame } }
	local offsets = appliedRegionReferenceOffsetsByCharacter[character]
	if offsets then
		return offsets
	end

	offsets = {}
	appliedRegionReferenceOffsetsByCharacter[character] = offsets
	return offsets
end

local function storeAppliedRegionReferenceOffsets(
	character: Model,
	region: string,
	rootReferenceCFrame: CFrame,
	partReferenceCFrames: { [string]: CFrame }?
)
	local offsets = getAppliedRegionReferenceOffsets(character)
	if partReferenceCFrames == nil then
		offsets[region] = nil
		return
	end

	local regionOffsets = {}
	for partName, referenceCFrame in pairs(partReferenceCFrames) do
		regionOffsets[partName] = rootReferenceCFrame:ToObjectSpace(referenceCFrame)
	end
	offsets[region] = regionOffsets
end

local function clearAppliedRegionReferenceOffsets(character: Model)
	appliedRegionReferenceOffsetsByCharacter[character] = nil
end

local function markAuraRuntimeInstance(instance: Instance, auraId: string)
	instance:SetAttribute(AURA_RUNTIME_ATTRIBUTE, true)
	instance:SetAttribute(AURA_ID_ATTRIBUTE, auraId)

	for _, descendant in ipairs(instance:GetDescendants()) do
		descendant:SetAttribute(AURA_RUNTIME_ATTRIBUTE, true)
		descendant:SetAttribute(AURA_ID_ATTRIBUTE, auraId)
	end
end

local function markMutationRuntimeInstance(instance: Instance, mutationId: string, region: string)
	instance:SetAttribute(MUTATION_RUNTIME_ATTRIBUTE, true)
	instance:SetAttribute(MUTATION_ID_ATTRIBUTE, mutationId)
	instance:SetAttribute(MUTATION_REGION_ATTRIBUTE, region)

	for _, descendant in ipairs(instance:GetDescendants()) do
		descendant:SetAttribute(MUTATION_RUNTIME_ATTRIBUTE, true)
		descendant:SetAttribute(MUTATION_ID_ATTRIBUTE, mutationId)
		descendant:SetAttribute(MUTATION_REGION_ATTRIBUTE, region)
	end
end

local function clearAuraRuntime(character: Model)
	local auraInstances = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:GetAttribute(AURA_RUNTIME_ATTRIBUTE) == true then
			table.insert(auraInstances, descendant)
		end
	end

	table.sort(auraInstances, function(left, right)
		return #left:GetFullName() > #right:GetFullName()
	end)

	for _, instance in ipairs(auraInstances) do
		if instance.Parent then
			instance:Destroy()
		end
	end
end

local function clearMutationRuntime(character: Model, region: string?)
	local mutationInstances = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:GetAttribute(MUTATION_RUNTIME_ATTRIBUTE) == true then
			local owningRegion = descendant:GetAttribute(MUTATION_REGION_ATTRIBUTE)
			if region == nil or owningRegion == region then
				table.insert(mutationInstances, descendant)
			end
		end
	end

	table.sort(mutationInstances, function(left, right)
		return #left:GetFullName() > #right:GetFullName()
	end)

	for _, instance in ipairs(mutationInstances) do
		if instance.Parent then
			instance:Destroy()
		end
	end
end

local function isAuraTargetPartName(partName: string): boolean
	return AURA_TARGET_PART_NAMES[partName] == true
end

local function isAuraSourceContainer(part: Instance, auraModel: Model): boolean
	if not (part and part:IsA("BasePart")) then
		return false
	end
	if not isAuraTargetPartName(part.Name) then
		return false
	end

	local current = part.Parent
	while current and current ~= auraModel do
		if current:IsA("BasePart") then
			return false
		end
		current = current.Parent
	end

	return current == auraModel
end

local function isMutationSourceContainer(
	part: Instance,
	mutationModel: Model,
	regionPartLookup: { [string]: boolean }
): boolean
	if not (part and part:IsA("BasePart")) then
		return false
	end
	if regionPartLookup[part.Name] ~= true then
		return false
	end

	local current = part.Parent
	while current and current ~= mutationModel do
		if current:IsA("BasePart") then
			return false
		end
		current = current.Parent
	end

	return current == mutationModel
end

local function isMutationRuntimeAllowedChild(instance: Instance): boolean
	return MUTATION_RUNTIME_ALLOWED_CHILD_CLASSES[instance.ClassName] == true
end

local function pruneMutationAttachmentChildren(attachment: Attachment)
	local children = attachment:GetChildren()
	for _, child in ipairs(children) do
		if not isMutationRuntimeAllowedChild(child) then
			child:Destroy()
		end
	end
end

local function isAlwaysAllowedChild(instance: Instance): boolean
	return ALWAYS_ALLOWED_CHILD_CLASSES[instance.ClassName] == true or instance:IsA("ValueBase")
end

local function formatInstancePathRelativeToBundle(bundle: Model, instance: Instance): string
	local names = { instance.Name }
	local current = instance.Parent
	while current and current ~= bundle do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	return table.concat(names, ".")
end

local function buildBundlePartLookup(bundle: Instance, region: string): { [string]: BasePart }
	local partsByName = {}

	if bundle:IsA("BasePart") then
		partsByName[bundle.Name] = bundle
		local regionParts = getRigPartNames(region)
		if regionParts and #regionParts == 1 then
			partsByName[regionParts[1]] = bundle
		end
		return partsByName
	end

	for _, child in ipairs(bundle:GetChildren()) do
		if child:IsA("BasePart") then
			partsByName[child.Name] = child
		end
	end

	for _, descendant in ipairs(bundle:GetDescendants()) do
		if descendant:IsA("BasePart") and partsByName[descendant.Name] == nil then
			partsByName[descendant.Name] = descendant
		end
	end

	return partsByName
end

local function isRotationWithinTolerance(cframe: CFrame, tolerance: number): boolean
	local x, y, z = getRotationOnly(cframe):ToOrientation()
	return math.abs(x) <= tolerance and math.abs(y) <= tolerance and math.abs(z) <= tolerance
end

local function computeNativeRigPlacementReadiness(bundle: Model, region: string): (boolean, { string })
	local nativeSpec = REGION_NATIVE_RIG_ATTACHMENT_SPECS[region]
	if not nativeSpec then
		return false, { "region:unsupported" }
	end

	local missing = {}
	local partsByName = buildBundlePartLookup(bundle, region)
	for _, attachmentSpec in ipairs(nativeSpec.RequiredAttachments) do
		local part = partsByName[attachmentSpec.PartName]
		if not part then
			missing[#missing + 1] = string.format("part:%s", attachmentSpec.PartName)
		elseif not findDirectAttachment(part, attachmentSpec.AttachmentName) then
			missing[#missing + 1] = string.format("attachment:%s.%s", attachmentSpec.PartName, attachmentSpec.AttachmentName)
		end
	end

	return #missing == 0, missing
end

local function computeTransformRotationReadiness(bundle: Model, region: string): (boolean, { string })
	local partNames = getRigPartNames(region)
	if not partNames or #partNames <= 1 then
		return true, {}
	end

	if not bundle:IsA("Model") then
		return false, { "bundle:not_model" }
	end

	local rootPartName = partNames[1]
	if region == "Torso" then
		rootPartName = "LowerTorso"
	elseif region == "LeftArm" then
		rootPartName = "LeftUpperArm"
	elseif region == "RightArm" then
		rootPartName = "RightUpperArm"
	elseif region == "LeftLeg" then
		rootPartName = "LeftUpperLeg"
	elseif region == "RightLeg" then
		rootPartName = "RightUpperLeg"
	end

	local issues = {}
	local partsByName = buildBundlePartLookup(bundle, region)
	local rootPart = partsByName[rootPartName]
	if not rootPart then
		issues[#issues + 1] = string.format("root:%s", rootPartName)
		return false, issues
	end

	for _, partName in ipairs(partNames) do
		if partName ~= rootPartName then
			local part = partsByName[partName]
			if not part then
				issues[#issues + 1] = string.format("part:%s", partName)
			else
				local relativeCFrame = rootPart.CFrame:ToObjectSpace(part.CFrame)
				if not isRotationWithinTolerance(relativeCFrame, TRANSFORM_ROTATION_TOLERANCE) then
					issues[#issues + 1] = string.format("rotation:%s", partName)
				end
			end
		end
	end

	return #issues == 0, issues
end

local function computeRigAttachmentOrientationReadiness(bundle: Model, region: string): (boolean, { string })
	local issues = {}
	local partsByName = buildBundlePartLookup(bundle, region)
	for _, partName in ipairs(getRigPartNames(region) or {}) do
		local part = partsByName[partName]
		if part then
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Attachment") and string.find(child.Name, "RigAttachment", 1, true) then
					if not isRotationWithinTolerance(child.CFrame, RIG_ATTACHMENT_ROTATION_TOLERANCE) then
						issues[#issues + 1] = string.format("attachment:%s.%s", partName, child.Name)
					end
				end
			end
		end
	end

	return #issues == 0, issues
end

local function refreshBundleValidationState(bundle: Model, region: string): (boolean, { string }, { string }, { string })
	local nativeReady, nativeIssues = computeNativeRigPlacementReadiness(bundle, region)
	local transformReady, transformIssues = computeTransformRotationReadiness(bundle, region)
	local attachmentReady, attachmentIssues = computeRigAttachmentOrientationReadiness(bundle, region)

	bundle:SetAttribute("NativeRigPlacementReady", nativeReady)
	bundle:SetAttribute("TransformRotationReady", transformReady)
	bundle:SetAttribute("RigAttachmentOrientationReady", attachmentReady)
	bundle:SetAttribute("RotationDriftFree", transformReady and attachmentReady)

	return nativeReady and transformReady and attachmentReady, nativeIssues, transformIssues, attachmentIssues
end

local function validateBundleVisualContract(bundle: Model, region: string): string?
	refreshBundleValidationState(bundle, region)

	local forbiddenInstances = {}

	for _, descendant in ipairs(bundle:GetDescendants()) do
		if FORBIDDEN_BUNDLE_CLASSES[descendant.ClassName] then
			table.insert(
				forbiddenInstances,
				string.format("%s [%s]", formatInstancePathRelativeToBundle(bundle, descendant), descendant.ClassName)
			)
		end
	end

	if #forbiddenInstances == 0 then
		for _, child in ipairs(bundle:GetChildren()) do
			if child:IsA("Model") then
				local anchorPartName = child:GetAttribute(ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE)
				local anchorOffset = child:GetAttribute(ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE)
				local owningRegion = child:GetAttribute(ASSEMBLY_OWNING_REGION_ATTRIBUTE)
				local sourceName = child:GetAttribute(ASSEMBLY_SOURCE_NAME_ATTRIBUTE)
				local targetPartName = child:GetAttribute(ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE)

				if typeof(anchorPartName) ~= "string" or anchorPartName == "" then
					return string.format("Bundle %s assembly %s is missing %s.", bundle.Name, child.Name, ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE)
				end
				if typeof(anchorOffset) ~= "CFrame" then
					return string.format("Bundle %s assembly %s is missing %s.", bundle.Name, child.Name, ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE)
				end
				if owningRegion ~= region then
					return string.format(
						"Bundle %s assembly %s has invalid %s value %s.",
						bundle.Name,
						child.Name,
						ASSEMBLY_OWNING_REGION_ATTRIBUTE,
						tostring(owningRegion)
					)
				end
				if typeof(sourceName) ~= "string" or sourceName == "" then
					return string.format("Bundle %s assembly %s is missing %s.", bundle.Name, child.Name, ASSEMBLY_SOURCE_NAME_ATTRIBUTE)
				end
				if typeof(targetPartName) ~= "string" or not table.find(getRigPartNames(region) or {}, targetPartName) then
					return string.format(
						"Bundle %s assembly %s has invalid %s value %s.",
						bundle.Name,
						child.Name,
						ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE,
						tostring(targetPartName)
					)
				end

				local foundAnchor = nil
				for _, descendant in ipairs(child:GetDescendants()) do
					if descendant:IsA("BasePart") and descendant:GetAttribute(ASSEMBLY_ANCHOR_PART_ATTRIBUTE) == true then
						foundAnchor = descendant
						break
					end
				end
				if not foundAnchor then
					local fallback = child:FindFirstChild(anchorPartName, true)
					if fallback and fallback:IsA("BasePart") then
						foundAnchor = fallback
					end
				end
				if not foundAnchor then
					return string.format("Bundle %s assembly %s is missing anchor part %s.", bundle.Name, child.Name, anchorPartName)
				end
			end
		end

		return nil
	end

	table.sort(forbiddenInstances)

	local previewCount = math.min(#forbiddenInstances, 5)
	local preview = table.concat(forbiddenInstances, ", ", 1, previewCount)
	if #forbiddenInstances > previewCount then
		preview = string.format("%s, and %d more", preview, #forbiddenInstances - previewCount)
	end

	return string.format(
		"%s bundle %s must be visual-only. Remove forbidden instances: %s.",
		region,
		bundle:GetFullName(),
		preview
	)
end

local function sanitizeVisualPartChildren(
	visualPart: BasePart,
	allowedAnimationConstraintNames: { [string]: boolean }?
)
	for _, child in ipairs(visualPart:GetChildren()) do
		if child:IsA("NoCollisionConstraint") then
			-- Rebound after cloning when both visual parts exist.
		elseif child:IsA("AnimationConstraint") then
			if not (allowedAnimationConstraintNames and allowedAnimationConstraintNames[child.Name]) then
				child:Destroy()
			end
		elseif child:IsA("BallSocketConstraint") or child:IsA("Motor6D") then
			child:Destroy()
		elseif isAlwaysAllowedChild(child) then
			-- Keep.
		else
			child:Destroy()
		end
	end
end

local function configureVisualPart(part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function scaleVisualPart(part: BasePart, scale: number, targetSizeOverride: Vector3?)
	local baseSize = part.Size
	local targetSize = if typeof(targetSizeOverride) == "Vector3" then targetSizeOverride else (baseSize * scale)
	part.Size = targetSize

	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("SpecialMesh") then
			descendant.Scale = scaleVectorBySizeRatio(descendant.Scale, baseSize, targetSize)
		elseif descendant:IsA("Attachment") then
			descendant.Position = scaleVectorBySizeRatio(descendant.Position, baseSize, targetSize)
		end
	end
end

local function configureAccessoryHandle(part: BasePart)
	configureVisualPart(part)
end

local function findAssemblyAnchorPart(assemblyModel: Model, anchorPartName: string): BasePart?
	for _, descendant in ipairs(assemblyModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute(ASSEMBLY_ANCHOR_PART_ATTRIBUTE) == true then
			return descendant
		end
	end

	local fallback = assemblyModel:FindFirstChild(anchorPartName, true)
	if fallback and fallback:IsA("BasePart") then
		return fallback
	end

	return nil
end

findDirectAttachment = function(part: BasePart, attachmentName: string): Attachment?
	local found = nil
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Attachment") and child.Name == attachmentName then
			if found then
				return nil
			end
			found = child
		end
	end
	return found
end

findDirectAnimationConstraint = function(part: BasePart, constraintName: string): AnimationConstraint?
	local found = nil
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("AnimationConstraint") and child.Name == constraintName then
			if found then
				return nil
			end
			found = child
		end
	end
	return found
end

local function createConstraintWeld(name: string, part0: BasePart, part1: BasePart, parent: Instance): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = parent
	return weld
end

local function createSolvedRigWeld(name: string, part0: BasePart, part1: BasePart, parent: Instance): Weld
	local weld = Instance.new("Weld")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = parent
	return weld
end

local function getStoredLoadoutEntry(character: Model, region: string): ApplyRegionRequest?
	local requests = appliedRegionRequestsByCharacter[character]
	if requests == nil then
		return nil
	end

	return cloneRegionRequest(requests[region])
end

local function getAuraRequestedScale(character: Model, partName: string): number
	local region = PART_NAME_TO_REGION[partName]
	if region == nil then
		return 1
	end

	local regionRequest = getStoredLoadoutEntry(character, region)
	return getFinalScale(regionRequest)
end

local function getAppliedRegionPart(character: Model, region: string, partName: string): BasePart?
	local appliedFolder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if not appliedFolder then
		return nil
	end

	local regionFolder = appliedFolder:FindFirstChild(region)
	if not (regionFolder and regionFolder:IsA("Model")) then
		return nil
	end

	local part = regionFolder:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function getAppliedTorsoAnchorPart(character: Model, partName: string): BasePart?
	local appliedFolder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if not appliedFolder then
		return nil
	end

	local torsoFolder = appliedFolder:FindFirstChild("Torso")
	if not (torsoFolder and torsoFolder:IsA("Model")) then
		return nil
	end

	local anchorPart = torsoFolder:FindFirstChild(partName, true)
	if anchorPart and anchorPart:IsA("BasePart") then
		return anchorPart
	end

	return nil
end

local function getAppliedRegionAttachmentWorldCFrame(
	character: Model,
	region: string,
	partName: string,
	attachmentName: string
): CFrame?
	local part = getAppliedRegionPart(character, region, partName)
	if not part then
		return nil
	end

	local attachment = findDirectAttachment(part, attachmentName)
	if not attachment then
		return nil
	end

	return attachment.WorldCFrame
end

local function getLiveReferenceAttachmentWorldCFrame(
	character: Model,
	referencePose,
	partName: string,
	attachmentName: string
): CFrame?
	local part = character:FindFirstChild(partName)
	local partReferenceCFrame = referencePose and referencePose.partCFrames[partName] or nil
	if not (part and part:IsA("BasePart") and partReferenceCFrame) then
		return nil
	end

	local attachment = findDirectAttachment(part, attachmentName)
	if not attachment then
		return nil
	end

	return partReferenceCFrame * attachment.CFrame
end

local function getAppliedRegionReferenceAttachmentWorldCFrame(
	character: Model,
	referencePose,
	region: string,
	partName: string,
	attachmentName: string
): CFrame?
	local offsetsByRegion = appliedRegionReferenceOffsetsByCharacter[character]
	local regionOffsets = offsetsByRegion and offsetsByRegion[region] or nil
	local relativeCFrame = regionOffsets and regionOffsets[partName] or nil
	local part = getAppliedRegionPart(character, region, partName)
	if not (referencePose and relativeCFrame and part) then
		return nil
	end

	local attachment = findDirectAttachment(part, attachmentName)
	if not attachment then
		return nil
	end

	return referencePose.rootCFrame * relativeCFrame * attachment.CFrame
end

local function buildAllowedAnimationConstraintLookup(region: string): { [string]: boolean }?
	local articulationSpec = REGION_ARTICULATION_SPECS[region]
	if not articulationSpec then
		return nil
	end

	local lookup = {}
	for _, constraintSpec in ipairs(articulationSpec.Constraints) do
		lookup[constraintSpec.ConstraintName] = true
	end
	return lookup
end

local function findFirstAttachmentInAccessory(accessory: Accessory): Attachment?
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end

	local found = nil
	for _, descendant in ipairs(handle:GetDescendants()) do
		if descendant:IsA("Attachment") then
			if found then
				return nil
			end
			found = descendant
		end
	end

	return found
end

local function findAttachmentInVisualParts(visualPartsByName: { [string]: BasePart }, attachmentName: string): (BasePart?, Attachment?)
	for _, visualPart in pairs(visualPartsByName) do
		local attachment = findDirectAttachment(visualPart, attachmentName)
		if attachment then
			return visualPart, attachment
		end
	end

	return nil, nil
end

local function findBundleSourcePartForAttachment(bundle: Instance, region: string, attachmentName: string): BasePart?
	local bundlePartsByName = buildBundlePartLookup(bundle, region)
	for _, partName in ipairs(getRigPartNames(region) or ALL_RIG_PARTS) do
		local part = bundlePartsByName[partName]
		if part and findDirectAttachment(part, attachmentName) then
			return part
		end
	end

	return nil
end

local function buildCloneMap(source: Instance, clone: Instance, sourceToClone: { [Instance]: Instance })
	sourceToClone[source] = clone

	local sourceChildren = source:GetChildren()
	local cloneChildren = clone:GetChildren()
	for index, sourceChild in ipairs(sourceChildren) do
		local cloneChild = cloneChildren[index]
		if cloneChild then
			buildCloneMap(sourceChild, cloneChild, sourceToClone)
		end
	end
end

local function getAppliedVisualPart(character: Model, partName: string): BasePart?
	local appliedFolder = getAppliedFolder(character)
	local visualPart = appliedFolder:FindFirstChild(partName, true)
	if visualPart and visualPart:IsA("BasePart") then
		return visualPart
	end

	return nil
end

local function findAuraTargetPart(character: Model, partName: string): BasePart?
	local visualPart = getAppliedVisualPart(character, partName)
	if visualPart then
		return visualPart
	end

	local characterPart = character:FindFirstChild(partName)
	if characterPart and characterPart:IsA("BasePart") then
		return characterPart
	end

	return nil
end

local function resolveAuraAttachmentReference(
	resolvedAttachmentsBySource: { [Attachment]: Attachment? },
	sourceAttachment: Attachment?
): Attachment?
	if sourceAttachment == nil then
		return nil
	end

	return resolvedAttachmentsBySource[sourceAttachment]
end

local function buildAuraRuntimePlan(character: Model, auraRequest: ApplyAuraRequest): (any?, string?)
	if typeof(auraRequest) ~= "table" then
		return nil, "Aura request must be a table."
	end

	if typeof(auraRequest.id) ~= "string" or auraRequest.id == "" then
		return nil, "Aura request is missing a valid aura id."
	end

	local auraModel = auraRequest.model
	if not (auraModel and auraModel:IsA("Model")) then
		return nil, "Aura request is missing a valid aura model."
	end

	local sourceParts = {}
	local sourceAttachmentToTargetPart = {}

	for _, descendant in ipairs(auraModel:GetDescendants()) do
		if descendant:IsA("BasePart") and isAuraSourceContainer(descendant, auraModel) then
			local targetPart = findAuraTargetPart(character, descendant.Name)
			if not targetPart then
				return nil, string.format('Aura "%s" could not find a live target for "%s".', auraRequest.id, descendant.Name)
			end

			table.insert(sourceParts, {
				sourcePart = descendant,
				targetPart = targetPart,
				requestedScale = getAuraRequestedScale(character, descendant.Name),
			})

			for _, nestedDescendant in ipairs(descendant:GetDescendants()) do
				if nestedDescendant:IsA("Attachment") then
					sourceAttachmentToTargetPart[nestedDescendant] = targetPart
				end
			end
		end
	end

	if #sourceParts == 0 then
		return nil, string.format('Aura "%s" does not contain any supported source parts.', auraRequest.id)
	end

	for _, descendant in ipairs(auraModel:GetDescendants()) do
		local referenceProperties = AURA_ATTACHMENT_REFERENCE_PROPERTIES_BY_CLASS[descendant.ClassName]
		if referenceProperties then
			for _, propertyName in ipairs(referenceProperties) do
				local attachment = descendant[propertyName]
				if attachment ~= nil and sourceAttachmentToTargetPart[attachment] == nil then
					return nil, string.format(
						'Aura "%s" has %s "%s" referencing an unsupported attachment.',
						auraRequest.id,
						descendant.ClassName,
						descendant.Name
					)
				end
			end
		end
	end

	return {
		auraId = auraRequest.id,
		auraModel = auraModel,
		sourceParts = sourceParts,
		sourceAttachmentToTargetPart = sourceAttachmentToTargetPart,
	}, nil
end

local function applyAuraRuntime(character: Model, auraRequest: ApplyAuraRequest): (boolean, string?)
	local runtimePlan, runtimeError = buildAuraRuntimePlan(character, auraRequest)
	if not runtimePlan then
		return false, runtimeError
	end

	local resolvedAttachmentsBySource = {}
	local stagedPartClones = {}

	for _, sourcePartEntry in ipairs(runtimePlan.sourceParts) do
		local sourcePart = sourcePartEntry.sourcePart
		local targetPart = sourcePartEntry.targetPart
		local requestedScale = sourcePartEntry.requestedScale
		local sourceClone = sourcePart:Clone()
		local sourceToClone = {}
		local cloneToSource = {}

		buildCloneMap(sourcePart, sourceClone, sourceToClone)
		for sourceInstance, cloneInstance in pairs(sourceToClone) do
			cloneToSource[cloneInstance] = sourceInstance
		end
		scaleAuraCloneTree(sourceClone, requestedScale)

		for _, sourceDescendant in ipairs(sourcePart:GetDescendants()) do
			if sourceDescendant:IsA("Attachment") then
				local targetAttachment = findDirectAttachment(targetPart, sourceDescendant.Name)
				if targetAttachment == nil then
					local cloneAttachment = sourceToClone[sourceDescendant]
					if cloneAttachment and cloneAttachment:IsA("Attachment") then
						targetAttachment = cloneAttachment
					end
				end

				if targetAttachment == nil then
					return false, string.format(
						'Aura "%s" could not resolve attachment "%s" on "%s".',
						runtimePlan.auraId,
						sourceDescendant.Name,
						targetPart.Name
					)
				end

				resolvedAttachmentsBySource[sourceDescendant] = targetAttachment
			end
		end

		table.insert(stagedPartClones, {
			sourcePart = sourcePart,
			targetPart = targetPart,
			cloneRoot = sourceClone,
			sourceToClone = sourceToClone,
			cloneToSource = cloneToSource,
		})
	end

	for _, stagedPart in ipairs(stagedPartClones) do
		for sourceInstance, cloneInstance in pairs(stagedPart.sourceToClone) do
			local referenceProperties = AURA_ATTACHMENT_REFERENCE_PROPERTIES_BY_CLASS[sourceInstance.ClassName]
			if referenceProperties and cloneInstance then
				for _, propertyName in ipairs(referenceProperties) do
					local resolvedAttachment = resolveAuraAttachmentReference(
						resolvedAttachmentsBySource,
						sourceInstance[propertyName]
					)
					if sourceInstance[propertyName] ~= nil and resolvedAttachment == nil then
						return false, string.format(
							'Aura "%s" could not resolve %s endpoint "%s" for "%s".',
							runtimePlan.auraId,
							sourceInstance.ClassName,
							propertyName,
							sourceInstance.Name
						)
					end

					cloneInstance[propertyName] = resolvedAttachment
				end
			end
		end
	end

	clearAuraRuntime(character)

	for _, stagedPart in ipairs(stagedPartClones) do
		for _, child in ipairs(stagedPart.cloneRoot:GetChildren()) do
			if child:IsA("Attachment") then
				local sourceAttachment = stagedPart.cloneToSource[child]
				local resolvedAttachment = sourceAttachment and resolvedAttachmentsBySource[sourceAttachment] or nil
				if resolvedAttachment == child then
					child.Parent = stagedPart.targetPart
					markAuraRuntimeInstance(child, runtimePlan.auraId)
				elseif resolvedAttachment then
					local movedChildren = child:GetChildren()
					for _, nestedChild in ipairs(movedChildren) do
						nestedChild.Parent = resolvedAttachment
						markAuraRuntimeInstance(nestedChild, runtimePlan.auraId)
					end
					child:Destroy()
				else
					child:Destroy()
				end
			elseif child:IsA("BasePart") then
				child:Destroy()
			else
				child.Parent = stagedPart.targetPart
				markAuraRuntimeInstance(child, runtimePlan.auraId)
			end
		end

		stagedPart.cloneRoot:Destroy()
	end

	return true, nil
end

local function buildMutationRuntimePlan(
	character: Model,
	region: string,
	mutationRequest: ApplyMutationRequest
): (any?, string?)
	if not BodyPartRegions.IsValid(region) then
		return nil, string.format("Unknown mutation region %s.", tostring(region))
	end
	if typeof(mutationRequest) ~= "table" then
		return nil, string.format("Mutation request for %s must be a table.", region)
	end
	if typeof(mutationRequest.id) ~= "string" or mutationRequest.id == "" then
		return nil, string.format("Mutation request for %s is missing a valid mutation id.", region)
	end

	local mutationModel = mutationRequest.model
	if not (mutationModel and mutationModel:IsA("Model")) then
		return nil, string.format('Mutation "%s" for %s is missing a valid mutation model.', mutationRequest.id, region)
	end

	local regionPartLookup = getRigPartLookup(region)
	if regionPartLookup == nil then
		return nil, string.format("Unknown mutation region %s.", tostring(region))
	end

	local sourceParts = {}
	local sourceAttachmentToTargetPart = {}

	for _, descendant in ipairs(mutationModel:GetDescendants()) do
		if descendant:IsA("BasePart") and isMutationSourceContainer(descendant, mutationModel, regionPartLookup) then
			local targetPart = findAuraTargetPart(character, descendant.Name)
			if not targetPart then
				return nil, string.format(
					'Mutation "%s" for %s could not find a live target for "%s".',
					mutationRequest.id,
					region,
					descendant.Name
				)
			end

			table.insert(sourceParts, {
				sourcePart = descendant,
				targetPart = targetPart,
			})

			for _, nestedDescendant in ipairs(descendant:GetDescendants()) do
				if nestedDescendant:IsA("Attachment") then
					sourceAttachmentToTargetPart[nestedDescendant] = targetPart
				end
			end
		end
	end

	if #sourceParts == 0 then
		return nil, string.format(
			'Mutation "%s" does not contain any supported source parts for region "%s".',
			mutationRequest.id,
			region
		)
	end

	return {
		mutationId = mutationRequest.id,
		region = region,
		mutationModel = mutationModel,
		sourceParts = sourceParts,
		sourceAttachmentToTargetPart = sourceAttachmentToTargetPart,
	}, nil
end

local function applyMutationRuntime(
	character: Model,
	region: string,
	mutationRequest: ApplyMutationRequest
): (boolean, string?)
	local runtimePlan, runtimeError = buildMutationRuntimePlan(character, region, mutationRequest)
	if not runtimePlan then
		return false, runtimeError
	end

	local resolvedAttachmentsBySource = {}
	local stagedPartClones = {}

	for _, sourcePartEntry in ipairs(runtimePlan.sourceParts) do
		local sourcePart = sourcePartEntry.sourcePart
		local targetPart = sourcePartEntry.targetPart
		local sourceClone = sourcePart:Clone()
		local sourceToClone = {}
		local cloneToSource = {}

		buildCloneMap(sourcePart, sourceClone, sourceToClone)
		for sourceInstance, cloneInstance in pairs(sourceToClone) do
			cloneToSource[cloneInstance] = sourceInstance
		end
		scaleMutationCloneTree(sourceClone, sourcePart.Size, targetPart.Size)

		for _, sourceDescendant in ipairs(sourcePart:GetDescendants()) do
			if sourceDescendant:IsA("Attachment") then
				local targetAttachment = findDirectAttachment(targetPart, sourceDescendant.Name)
				if targetAttachment == nil then
					local cloneAttachment = sourceToClone[sourceDescendant]
					if cloneAttachment and cloneAttachment:IsA("Attachment") then
						targetAttachment = cloneAttachment
					end
				end

				if targetAttachment == nil then
					return false, string.format(
						'Mutation "%s" for %s could not resolve attachment "%s" on "%s".',
						runtimePlan.mutationId,
						runtimePlan.region,
						sourceDescendant.Name,
						targetPart.Name
					)
				end

				resolvedAttachmentsBySource[sourceDescendant] = targetAttachment
			end
		end

		table.insert(stagedPartClones, {
			targetPart = targetPart,
			cloneRoot = sourceClone,
			sourceToClone = sourceToClone,
			cloneToSource = cloneToSource,
		})
	end

	for _, stagedPart in ipairs(stagedPartClones) do
		for sourceInstance, cloneInstance in pairs(stagedPart.sourceToClone) do
			if cloneInstance and cloneInstance.Parent then
				local referenceProperties = AURA_ATTACHMENT_REFERENCE_PROPERTIES_BY_CLASS[sourceInstance.ClassName]
				if referenceProperties then
					local shouldDestroy = false
					for _, propertyName in ipairs(referenceProperties) do
						local sourceAttachment = sourceInstance[propertyName]
						local resolvedAttachment = resolveAuraAttachmentReference(resolvedAttachmentsBySource, sourceAttachment)
						if sourceAttachment ~= nil and resolvedAttachment == nil then
							shouldDestroy = true
							break
						end

						cloneInstance[propertyName] = resolvedAttachment
					end

					if shouldDestroy and cloneInstance.Parent then
						cloneInstance:Destroy()
					end
				end
			end
		end
	end

	clearMutationRuntime(character, region)

	for _, stagedPart in ipairs(stagedPartClones) do
		for _, child in ipairs(stagedPart.cloneRoot:GetChildren()) do
			if child:IsA("Attachment") then
				local sourceAttachment = stagedPart.cloneToSource[child]
				local resolvedAttachment = sourceAttachment and resolvedAttachmentsBySource[sourceAttachment] or nil
				if resolvedAttachment == child then
					pruneMutationAttachmentChildren(child)
					child.Parent = stagedPart.targetPart
					markMutationRuntimeInstance(child, runtimePlan.mutationId, runtimePlan.region)
				elseif resolvedAttachment then
					local movedChildren = child:GetChildren()
					for _, nestedChild in ipairs(movedChildren) do
						if isMutationRuntimeAllowedChild(nestedChild) then
							nestedChild.Parent = resolvedAttachment
							markMutationRuntimeInstance(nestedChild, runtimePlan.mutationId, runtimePlan.region)
						else
							nestedChild:Destroy()
						end
					end
					child:Destroy()
				else
					child:Destroy()
				end
			elseif isMutationRuntimeAllowedChild(child) then
				child.Parent = stagedPart.targetPart
				markMutationRuntimeInstance(child, runtimePlan.mutationId, runtimePlan.region)
			else
				child:Destroy()
			end
		end

		stagedPart.cloneRoot:Destroy()
	end

	return true, nil
end

local function alignAccessoryToAttachment(accessory: Accessory, targetPart: BasePart, targetAttachment: Attachment): (boolean, string?)
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return false, string.format("Accessory %s is missing a Handle.", accessory.Name)
	end

	local accessoryAttachment = findFirstAttachmentInAccessory(accessory)
	if not accessoryAttachment then
		return false, string.format("Accessory %s must have exactly one handle attachment for preset use.", accessory.Name)
	end

	handle.CFrame = targetAttachment.WorldCFrame * accessoryAttachment.CFrame:Inverse()

	local existingWeld = handle:FindFirstChild("AccessoryWeld")
	if existingWeld then
		existingWeld:Destroy()
	end

	createConstraintWeld("AccessoryWeld", targetPart, handle, handle)
	return true, nil
end

local function applyBundleAccessories(
	regionFolder: Model,
	bundle: Instance,
	region: string,
	visualPartsByName: { [string]: BasePart }
): (boolean, string?)
	for _, child in ipairs(bundle:GetChildren()) do
		if child:IsA("Accessory") then
			local accessoryClone = child:Clone()
			local accessoryAttachment = findFirstAttachmentInAccessory(accessoryClone)
			if not accessoryAttachment then
				accessoryClone:Destroy()
				return false, string.format("Accessory %s must have exactly one attachment for preset use.", child.Name)
			end

			local targetPart, targetAttachment = findAttachmentInVisualParts(visualPartsByName, accessoryAttachment.Name)
			if not (targetPart and targetAttachment) then
				accessoryClone:Destroy()
				return false, string.format("Accessory %s could not find a matching visual attachment named %s.", child.Name, accessoryAttachment.Name)
			end

			local sourcePart = findBundleSourcePartForAttachment(bundle, region, accessoryAttachment.Name)
			if not sourcePart then
				accessoryClone:Destroy()
				return false, string.format("Accessory %s could not resolve a matching source part for attachment %s.", child.Name, accessoryAttachment.Name)
			end

			local handle = accessoryClone:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				configureAccessoryHandle(handle)
			end

			local scaled, scaleError =
				AccessoryScaleUtils.ScaleAccessoryToPartSize(accessoryClone, sourcePart.Size, targetPart.Size)
			if not scaled then
				accessoryClone:Destroy()
				return false, scaleError
			end

			accessoryClone.Parent = regionFolder
			local success, accessoryError = alignAccessoryToAttachment(accessoryClone, targetPart, targetAttachment)
			if not success then
				accessoryClone:Destroy()
				return false, accessoryError
			end
		end
	end

	return true, nil
end

local function capturePartSizeMap(model: Model): ({ [string]: Vector3 }?, string?)
	local sizeMap = {}

	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = model:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return nil, string.format("Model %s is missing body part %s.", model:GetFullName(), partName)
		end
		sizeMap[partName] = part.Size
	end

	return sizeMap, nil
end

local function captureMotorData(character: Model)
	local motors = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			table.insert(motors, {
				motor = descendant,
				part0Name = descendant.Part0.Name,
				part1Name = descendant.Part1.Name,
				c0Position = descendant.C0.Position,
				c0Rotation = getRotationOnly(descendant.C0),
				c1Position = descendant.C1.Position,
				c1Rotation = getRotationOnly(descendant.C1),
			})
		end
	end
	return motors
end

local function captureAttachmentData(character: Model)
	local attachments = {}

	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = character:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return nil
		end

		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Attachment") then
				table.insert(attachments, {
					attachment = child,
					partName = partName,
					position = child.Position,
				})
			end
		end
	end

	return attachments
end

local function computeLowestPointYForPart(part: BasePart): number
	local halfSize = part.Size * 0.5
	local cframe = part.CFrame
	local lowestY = math.huge

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local corner = cframe * Vector3.new(halfSize.X * xSign, halfSize.Y * ySign, halfSize.Z * zSign)
				lowestY = math.min(lowestY, corner.Y)
			end
		end
	end

	return lowestY
end

local function computeLowestFootBottomY(character: Model): number?
	local lowestBottom = math.huge

	for _, partName in ipairs(SUPPORT_PART_NAMES) do
		local part = character:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return nil
		end
		lowestBottom = math.min(lowestBottom, computeLowestPointYForPart(part))
	end

	if lowestBottom == math.huge then
		return nil
	end

	return lowestBottom
end

local function computeFootSupportDistance(character: Model): number?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local lowestFootBottomY = computeLowestFootBottomY(character)
	if not (rootPart and rootPart:IsA("BasePart") and lowestFootBottomY) then
		return nil
	end

	return rootPart.Position.Y - lowestFootBottomY
end

local function setHipHeightFromSupportDistance(character: Model, supportDistance: number?): number?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart and rootPart:IsA("BasePart") and supportDistance) then
		return nil
	end

	local hipHeight = math.max(0, supportDistance - rootPart.Size.Y * 0.5)
	humanoid.HipHeight = hipHeight
	return hipHeight
end

local function captureRuntimeState(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart and rootPart:IsA("BasePart")) then
		return nil
	end

	local state = {
		parts = {
			HumanoidRootPart = rootPart.Size,
		},
	}

	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = character:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return nil
		end
		state.parts[partName] = part.Size
	end

	return state
end

local function captureBaseline(character: Model)
	local snapshot = baselineSnapshots[character]
	if snapshot then
		return snapshot
	end

	local runtimeState = captureRuntimeState(character)
	if not runtimeState then
		return nil, "Unable to capture the live R15 rig state."
	end

	local attachmentData = captureAttachmentData(character)
	if not attachmentData then
		return nil, "Unable to capture the live R15 attachment state."
	end

	local supportDistance = computeFootSupportDistance(character)
	if not supportDistance then
		return nil, "Unable to capture the live R15 footing state."
	end

	snapshot = {
		parts = runtimeState.parts,
		motors = captureMotorData(character),
		attachments = attachmentData,
		supportDistance = supportDistance,
	}

	baselineSnapshots[character] = snapshot
	return snapshot
end

local function applyPartSizes(character: Model, targetSizes: { [string]: Vector3 })
	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") and targetSizes[partName] then
			part.Size = targetSizes[partName]
		end
	end
end

local function applyAttachmentScaling(snapshot, targetSizes: { [string]: Vector3 })
	for _, attachmentData in ipairs(snapshot.attachments) do
		local attachment = attachmentData.attachment
		local baseSize = snapshot.parts[attachmentData.partName]
		local targetSize = targetSizes[attachmentData.partName] or baseSize

		if attachment and attachment.Parent and baseSize and targetSize then
			attachment.Position = scaleVectorBySizeRatio(attachmentData.position, baseSize, targetSize)
		end
	end
end

local function applyMotorScaling(snapshot, targetSizes: { [string]: Vector3 })
	for _, motorData in ipairs(snapshot.motors) do
		local motor = motorData.motor
		if motor and motor.Parent then
			local part0BaseSize = snapshot.parts[motorData.part0Name]
			local part1BaseSize = snapshot.parts[motorData.part1Name]
			local part0TargetSize = targetSizes[motorData.part0Name] or part0BaseSize
			local part1TargetSize = targetSizes[motorData.part1Name] or part1BaseSize

			if part0BaseSize and part1BaseSize and part0TargetSize and part1TargetSize then
				local c0Position = scaleVectorBySizeRatio(motorData.c0Position, part0BaseSize, part0TargetSize)
				local c1Position = scaleVectorBySizeRatio(motorData.c1Position, part1BaseSize, part1TargetSize)
				motor.C0 = composeCFrame(c0Position, motorData.c0Rotation)
				motor.C1 = composeCFrame(c1Position, motorData.c1Rotation)
			end
		end
	end
end

local function settleCharacterFooting(character: Model, previousLowestFootBottomY: number?): number?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end

	local finalHipHeight = nil

	for _ = 1, FOOTING_SETTLE_MAX_PASSES do
		RunService.Heartbeat:Wait()

		local currentLowestFootBottomY = computeLowestFootBottomY(character)
		if previousLowestFootBottomY and currentLowestFootBottomY then
			local delta = previousLowestFootBottomY - currentLowestFootBottomY
			if math.abs(delta) > FOOTING_SETTLE_TOLERANCE then
				rootPart.CFrame = rootPart.CFrame + Vector3.new(0, delta, 0)
			end
		end

		finalHipHeight = setHipHeightFromSupportDistance(character, computeFootSupportDistance(character))

		if not previousLowestFootBottomY or not currentLowestFootBottomY then
			break
		end

		if math.abs(previousLowestFootBottomY - currentLowestFootBottomY) <= FOOTING_SETTLE_TOLERANCE then
			break
		end
	end

	return finalHipHeight
end

local function findRegionPart(model: Model, partName: string): BasePart?
	local part = model:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function resolveTemplateSource(bundle: Model, regionRequest: ApplyRegionRequest?, partName: string): BasePart?
	local attachRule = getAttachRule(regionRequest, partName)
	local templateChildName = attachRule.templateChildName or partName
	return findRegionPart(bundle, templateChildName)
end

local function resolveNativeFallbackSource(character: Model, partName: string): BasePart?
	local source = character:FindFirstChild(partName)
	if source and source:IsA("BasePart") then
		return source
	end
	return nil
end

local function buildTargetSizes(baseRig: Model, request: ApplyRequest): ({ [string]: Vector3 }?, string?)
	local targetSizes, baseError = capturePartSizeMap(baseRig)
	if not targetSizes then
		return nil, baseError
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local regionRequest = request.regions and request.regions[region] or nil
		if regionRequest then
			if regionRequest.isNativeFallback == true then
				continue
			end

			local bundle = regionRequest.bundle
			if not (bundle and bundle:IsA("Model")) then
				return nil, string.format("%s is missing a bundle model.", region)
			end

			local validationError = validateBundleVisualContract(bundle, region)
			if validationError then
				return nil, validationError
			end

			local scale = getFinalScale(regionRequest)
			for _, partName in ipairs(getRigPartNames(region) or {}) do
				local bundlePart = resolveTemplateSource(bundle, regionRequest, partName)
				if not (bundlePart and bundlePart:IsA("BasePart")) then
					return nil, string.format("Bundle %s is missing %s for %s.", bundle.Name, partName, region)
				end

				targetSizes[partName] = getBodyPartTargetSize(bundle, partName, bundlePart, scale)
			end
		end
	end

	return targetSizes, nil
end

local function getScaledOffset(offsetCFrame: CFrame, scale: number): CFrame
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = offsetCFrame:GetComponents()
	return CFrame.fromMatrix(
		Vector3.new(px * scale, py * scale, pz * scale),
		Vector3.new(r00, r10, r20),
		Vector3.new(r01, r11, r21),
		Vector3.new(r02, r12, r22)
	)
end

local function placePartFromReference(
	referencePartCFrame: CFrame,
	visualPart: BasePart,
	attachRule: AttachRule?,
	finalScale: number
)
	local offset = getScaledOffset(attachRule and (attachRule.visualOffsetCFrame or attachRule.offsetCFrame) or CFrame.new(), finalScale)
	visualPart.CFrame = referencePartCFrame * offset
end

local function placePartFromLiveCharacter(
	characterPart: BasePart,
	visualPart: BasePart,
	attachRule: AttachRule?,
	finalScale: number
)
	local offset = getScaledOffset(attachRule and (attachRule.visualOffsetCFrame or attachRule.offsetCFrame) or CFrame.new(), finalScale)
	visualPart.CFrame = characterPart.CFrame * offset
end

local function getPlayingAnimationTracks(humanoid: Humanoid?, animator: Animator?): { AnimationTrack }
	local tracks = {}
	local seen = {}

	local function addTrack(track: AnimationTrack)
		if track and seen[track] ~= true then
			seen[track] = true
			table.insert(tracks, track)
		end
	end

	if animator then
		local success, animatorTracks = pcall(function()
			return animator:GetPlayingAnimationTracks()
		end)
		if success and animatorTracks then
			for _, track in ipairs(animatorTracks) do
				addTrack(track)
			end
		end
	end

	if humanoid then
		local success, humanoidTracks = pcall(function()
			return humanoid:GetPlayingAnimationTracks()
		end)
		if success and humanoidTracks then
			for _, track in ipairs(humanoidTracks) do
				addTrack(track)
			end
		end
	end

	return tracks
end

local function stopPlayingAnimationTracks(humanoid: Humanoid?, animator: Animator?)
	for _, track in ipairs(getPlayingAnimationTracks(humanoid, animator)) do
		pcall(function()
			track:Stop(0)
		end)
	end
end

local function resetMotorTransforms(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			descendant.Transform = CFrame.new()
		end
	end
end

local function quiesceCharacterForBuild(character: Model?): () -> ()
	if not (character and character:IsA("Model")) then
		return function() end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return function() end
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	local originalAutoRotate = humanoid.AutoRotate

	stopPlayingAnimationTracks(humanoid, animator)
	resetMotorTransforms(character)
	humanoid.AutoRotate = false
	RunService.Heartbeat:Wait()
	stopPlayingAnimationTracks(humanoid, animator)
	resetMotorTransforms(character)

	return function()
		stopPlayingAnimationTracks(humanoid, animator)
		if humanoid.Parent then
			humanoid.AutoRotate = originalAutoRotate
		end
		if character.Parent then
			resetMotorTransforms(character)
		end
	end
end

local function placePartFromAttachmentWorldCFrame(
	attachmentWorldCFrame: CFrame,
	visualPart: BasePart,
	attachmentName: string,
	attachRule: AttachRule?,
	finalScale: number
): boolean
	local attachment = findDirectAttachment(visualPart, attachmentName)
	if not attachment then
		return false
	end

	local offset = getScaledOffset(attachRule and (attachRule.visualOffsetCFrame or attachRule.offsetCFrame) or CFrame.new(), finalScale)
	visualPart.CFrame = attachmentWorldCFrame * attachment.CFrame:Inverse() * offset
	return true
end

local function canUseCustomArticulatedPlacement(
	region: string,
	bundle: Model,
	visualPartsByName: { [string]: BasePart },
	templateCFramesByName: { [string]: CFrame }
): boolean
	if not USE_SOULS_STYLE_RUNTIME then
		return false
	end

	if usesLiveRigJointChainPlacement(region) then
		return false
	end

	if bundle:GetAttribute("AuthoredAssemblyReady") == false or bundle:GetAttribute("ArticulatedRegionReady") == false then
		return false
	end

	local authoredSpec = REGION_AUTHORED_ASSEMBLY_SPECS[region]
	local articulationSpec = REGION_ARTICULATION_SPECS[region]
	if not (authoredSpec and articulationSpec) then
		return false
	end

	local rootPart = visualPartsByName[authoredSpec.RootPartName]
	local rootCFrame = templateCFramesByName[authoredSpec.RootPartName]
	if not rootPart or not rootCFrame then
		return false
	end

	for _, partName in ipairs(getRigPartNames(region) or {}) do
		if not visualPartsByName[partName] or not templateCFramesByName[partName] then
			return false
		end
	end

	for _, constraintSpec in ipairs(articulationSpec.Constraints) do
		local holderPart = visualPartsByName[constraintSpec.HolderPartName]
		local attachment0Part = visualPartsByName[constraintSpec.Attachment0PartName]
		local attachment1Part = visualPartsByName[constraintSpec.Attachment1PartName]
		local constraint = holderPart and findDirectAnimationConstraint(holderPart, constraintSpec.ConstraintName) or nil
		local attachment0 = attachment0Part and findDirectAttachment(attachment0Part, constraintSpec.Attachment0Name) or nil
		local attachment1 = attachment1Part and findDirectAttachment(attachment1Part, constraintSpec.Attachment1Name) or nil
		if not constraint or not attachment0 or not attachment1 then
			return false
		end
	end

	return bundle:IsA("Model")
end

local function canUseAuthoredAssemblyPlacement(
	region: string,
	bundle: Model,
	visualPartsByName: { [string]: BasePart },
	templateCFramesByName: { [string]: CFrame }
): boolean
	if not USE_SOULS_STYLE_RUNTIME then
		return false
	end

	if usesLiveRigJointChainPlacement(region) then
		return false
	end

	if bundle:GetAttribute("AuthoredAssemblyReady") == false then
		return false
	end

	local authoredSpec = REGION_AUTHORED_ASSEMBLY_SPECS[region]
	if not authoredSpec then
		return false
	end

	local rootPart = visualPartsByName[authoredSpec.RootPartName]
	local rootCFrame = templateCFramesByName[authoredSpec.RootPartName]
	if not rootPart or not rootCFrame then
		return false
	end

	for _, partName in ipairs(getRigPartNames(region) or {}) do
		if not visualPartsByName[partName] or not templateCFramesByName[partName] then
			return false
		end
	end

	return bundle:IsA("Model")
end

local function placePartsWithAuthoredAssembly(
	region: string,
	regionRequest: ApplyRegionRequest?,
	referencePose,
	visualPartsByName: { [string]: BasePart },
	templateCFramesByName: { [string]: CFrame },
	finalScale: number
): boolean
	local authoredSpec = REGION_AUTHORED_ASSEMBLY_SPECS[region]
	if not authoredSpec then
		return false
	end

	local rootPartName = authoredSpec.RootPartName
	local rootVisualPart = visualPartsByName[rootPartName]
	local rootReferenceCFrame = referencePose and referencePose.partCFrames[rootPartName] or nil
	local rootTemplateCFrame = templateCFramesByName[rootPartName]
	if not (rootVisualPart and rootReferenceCFrame and rootTemplateCFrame) then
		return false
	end

	placePartFromReference(rootReferenceCFrame, rootVisualPart, getAttachRule(regionRequest, rootPartName), finalScale)

	for _, partName in ipairs(getRigPartNames(region) or {}) do
		if partName ~= rootPartName then
			local visualPart = visualPartsByName[partName]
			local templatePartCFrame = templateCFramesByName[partName]
			if not visualPart or not templatePartCFrame then
				return false
			end

			local relativeCFrame = rootTemplateCFrame:ToObjectSpace(templatePartCFrame)
			local scaledRelativeCFrame = getScaledOffset(relativeCFrame, finalScale)
			visualPart.CFrame = rootVisualPart.CFrame * scaledRelativeCFrame
		end
	end

	return true
end

usesLiveRigJointChainPlacement = function(region: string): boolean
	return region == "Torso" or region == "LeftArm" or region == "RightArm" or region == "LeftLeg" or region == "RightLeg"
end

local function placeTorsoFromLiveParts(
	referencePose,
	regionRequest: ApplyRegionRequest?,
	visualPartsByName: { [string]: BasePart },
	finalScale: number
): boolean
	local lowerTorsoVisual = visualPartsByName.LowerTorso
	local upperTorsoVisual = visualPartsByName.UpperTorso
	local lowerTorsoReference = referencePose and referencePose.partCFrames.LowerTorso or nil
	local upperTorsoReference = referencePose and referencePose.partCFrames.UpperTorso or nil
	if not (lowerTorsoVisual and upperTorsoVisual and lowerTorsoReference and upperTorsoReference) then
		return false
	end

	placePartFromReference(lowerTorsoReference, lowerTorsoVisual, getAttachRule(regionRequest, "LowerTorso"), finalScale)
	placePartFromReference(upperTorsoReference, upperTorsoVisual, getAttachRule(regionRequest, "UpperTorso"), finalScale)
	return true
end

local function placeLimbWithLiveJointChain(
	character: Model,
	region: string,
	referencePose,
	regionRequest: ApplyRegionRequest?,
	visualPartsByName: { [string]: BasePart },
	finalScale: number
): boolean
	local chainSpec = REGION_CHAIN_SPECS[region]
	if not chainSpec then
		return false
	end

	local rootPartName = chainSpec.RootPartName
	local rootAttachmentName = if region == "LeftArm"
			then "LeftShoulderRigAttachment"
		else if region == "RightArm"
			then "RightShoulderRigAttachment"
			else if region == "LeftLeg" then "LeftHipRigAttachment" else if region == "RightLeg" then "RightHipRigAttachment" else nil
	local rootVisualPart = visualPartsByName[rootPartName]
	local rootAttachmentWorldCFrame = if rootAttachmentName
		then getLiveReferenceAttachmentWorldCFrame(character, referencePose, rootPartName, rootAttachmentName)
		else nil
	if not (rootAttachmentName and rootVisualPart and rootAttachmentWorldCFrame) then
		return false
	end

	if
		not placePartFromAttachmentWorldCFrame(
			rootAttachmentWorldCFrame,
			rootVisualPart,
			rootAttachmentName,
			getAttachRule(regionRequest, rootPartName),
			finalScale
		)
	then
		return false
	end

	for _, step in ipairs(chainSpec.Steps) do
		local fromPart = visualPartsByName[step.FromPartName]
		local toPart = visualPartsByName[step.ToPartName]
		local seamFrom = fromPart and findDirectAttachment(fromPart, step.AttachmentName)
		local seamTo = toPart and findDirectAttachment(toPart, step.AttachmentName)
		if not fromPart or not toPart or not seamFrom or not seamTo then
			return false
		end

		toPart.CFrame = seamFrom.WorldCFrame * seamTo.CFrame:Inverse()
	end

	return true
end

local function canUseAttachmentChainPlacement(region: string, visualPartsByName: { [string]: BasePart }): boolean
	local chainSpec = REGION_CHAIN_SPECS[region]
	if not chainSpec then
		return false
	end

	if not visualPartsByName[chainSpec.RootPartName] then
		return false
	end

	for _, step in ipairs(chainSpec.Steps) do
		local fromPart = visualPartsByName[step.FromPartName]
		local toPart = visualPartsByName[step.ToPartName]
		if not fromPart or not toPart then
			return false
		end

		local fromAttachment = findDirectAttachment(fromPart, step.AttachmentName)
		local toAttachment = findDirectAttachment(toPart, step.AttachmentName)
		if not fromAttachment or not toAttachment then
			return false
		end
	end

	return true
end

local function placePartsWithAttachmentChain(
	region: string,
	regionRequest: ApplyRegionRequest?,
	referencePose,
	visualPartsByName: { [string]: BasePart },
	finalScale: number
): boolean
	local chainSpec = REGION_CHAIN_SPECS[region]
	if not chainSpec then
		return false
	end

	local rootReferenceCFrame = referencePose and referencePose.partCFrames[chainSpec.RootPartName] or nil
	local rootVisualPart = visualPartsByName[chainSpec.RootPartName]
	if not (rootReferenceCFrame and rootVisualPart) then
		return false
	end

	placePartFromReference(rootReferenceCFrame, rootVisualPart, getAttachRule(regionRequest, chainSpec.RootPartName), finalScale)

	for _, step in ipairs(chainSpec.Steps) do
		local fromPart = visualPartsByName[step.FromPartName]
		local toPart = visualPartsByName[step.ToPartName]
		local seamFrom = fromPart and findDirectAttachment(fromPart, step.AttachmentName)
		local seamTo = toPart and findDirectAttachment(toPart, step.AttachmentName)
		if not fromPart or not toPart or not seamFrom or not seamTo then
			return false
		end

		toPart.CFrame = seamFrom.WorldCFrame * seamTo.CFrame:Inverse()
	end

	return true
end

local function correctTorsoUpperPartFromLiveWaistSeam(
	character: Model,
	referencePose,
	visualPartsByName: { [string]: BasePart }
): (boolean, string?)
	local upperTorsoVisual = visualPartsByName.UpperTorso
	if not upperTorsoVisual then
		return false, "Missing visual UpperTorso for torso seam correction."
	end

	local upperWaistAttachment = findDirectAttachment(upperTorsoVisual, "WaistRigAttachment")
	if not upperWaistAttachment then
		return false, "Missing visual UpperTorso.WaistRigAttachment for torso seam correction."
	end

	local targetWaistWorldCFrame =
		getLiveReferenceAttachmentWorldCFrame(character, referencePose, "LowerTorso", "WaistRigAttachment")
	local seamSource = "LiveLowerTorsoWaist"

	if targetWaistWorldCFrame == nil then
		targetWaistWorldCFrame =
			getLiveReferenceAttachmentWorldCFrame(character, referencePose, "UpperTorso", "WaistRigAttachment")
		seamSource = "LiveUpperTorsoWaist"
	end

	if targetWaistWorldCFrame == nil then
		return false, "Missing live torso waist seam for torso upper-part correction."
	end

	upperTorsoVisual.CFrame = targetWaistWorldCFrame * upperWaistAttachment.CFrame:Inverse()
	return true, seamSource
end

local function transformRegionParts(visualPartsByName: { [string]: BasePart }, transform: CFrame)
	for _, part in pairs(visualPartsByName) do
		part.CFrame = transform * part.CFrame
	end
end

local REFERENCE_POSE_CHAIN_SPECS = {
	{
		label = "Root",
		motorName = "Root",
		fromName = "HumanoidRootPart",
		toName = "LowerTorso",
	},
	{
		label = "Waist",
		motorName = "Waist",
		fromName = "LowerTorso",
		toName = "UpperTorso",
	},
	{
		label = "Neck",
		motorName = "Neck",
		fromName = "UpperTorso",
		toName = "Head",
	},
}

local function sortPartNames(partNames: { string }): { string }
	table.sort(partNames)
	return partNames
end

local function buildReferencePose(character: Model): ({ rootCFrame: CFrame, partCFrames: { [string]: CFrame } }?, string?, string?)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil, "Missing HumanoidRootPart while building the neutral reference pose.", "missing_root_part"
	end

	local partCFrames = {
		HumanoidRootPart = rootPart.CFrame,
	}
	local adjacency = {}
	local connectedMotorStates = {}
	local namedMotorStates = {}
	local reachablePartNames = {}

	local function addMotorEdge(fromName: string, toName: string, resolver)
		local edges = adjacency[fromName]
		if edges == nil then
			edges = {}
			adjacency[fromName] = edges
		end

		table.insert(edges, {
			toName = toName,
			resolve = resolver,
		})
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local part0Name = if descendant.Part0 then descendant.Part0.Name else nil
			local part1Name = if descendant.Part1 then descendant.Part1.Name else nil
			if descendant.Name ~= "" then
				namedMotorStates[descendant.Name] = {
					part0Name = part0Name,
					part1Name = part1Name,
					connected = part0Name ~= nil and part1Name ~= nil,
				}
			end

			if not (descendant.Part0 and descendant.Part1) then
				continue
			end

			local part0Name = descendant.Part0.Name
			local part1Name = descendant.Part1.Name
			connectedMotorStates[part0Name .. "\0" .. part1Name] = descendant.Name
			connectedMotorStates[part1Name .. "\0" .. part0Name] = descendant.Name
			addMotorEdge(part0Name, part1Name, function(fromCFrame: CFrame): CFrame
				return fromCFrame * descendant.C0 * descendant.C1:Inverse()
			end)
			addMotorEdge(part1Name, part0Name, function(fromCFrame: CFrame): CFrame
				return fromCFrame * descendant.C1 * descendant.C0:Inverse()
			end)
		end
	end

	local queue = { "HumanoidRootPart" }
	local index = 1
	while index <= #queue do
		local fromName = queue[index]
		index += 1

		local fromCFrame = partCFrames[fromName]
		table.insert(reachablePartNames, fromName)
		for _, edge in ipairs(adjacency[fromName] or {}) do
			if partCFrames[edge.toName] == nil then
				partCFrames[edge.toName] = edge.resolve(fromCFrame)
				table.insert(queue, edge.toName)
			end
		end
	end

	for _, partName in ipairs(ALL_RIG_PARTS) do
		if partCFrames[partName] == nil then
			local chainStates = {}
			local hasAnyConnectedCoreMotor = false
			for _, chainSpec in ipairs(REFERENCE_POSE_CHAIN_SPECS) do
				local namedMotorState = namedMotorStates[chainSpec.motorName]
				local connectedMotorName = connectedMotorStates[chainSpec.fromName .. "\0" .. chainSpec.toName]
				local stateMessage = nil

				if connectedMotorName ~= nil then
					hasAnyConnectedCoreMotor = true
					stateMessage = string.format(
						"%s=connected(%s->%s via %s)",
						chainSpec.label,
						chainSpec.fromName,
						chainSpec.toName,
						connectedMotorName
					)
				elseif namedMotorState == nil then
					stateMessage = string.format("%s=missing", chainSpec.label)
				elseif namedMotorState.connected ~= true then
					stateMessage = string.format("%s=unbound", chainSpec.label)
				else
					stateMessage = string.format(
						"%s=misbound(%s->%s)",
						chainSpec.label,
						tostring(namedMotorState.part0Name),
						tostring(namedMotorState.part1Name)
					)
				end

				table.insert(chainStates, stateMessage)
			end

			if not hasAnyConnectedCoreMotor then
				return nil,
					"Character is still waiting for the finalized avatar appearance load. The core torso/head motor chain is not connected yet.",
					"placeholder_character"
			end

			local reachableSummary = table.concat(sortPartNames(reachablePartNames), ", ")
			return nil, string.format(
				"Unable to solve neutral reference CFrame for %s. Motor graph reachable=[%s]. Chain states: %s.",
				partName,
				reachableSummary,
				table.concat(chainStates, ", ")
			), "broken_reference_pose"
		end
	end

	return {
		rootCFrame = rootPart.CFrame,
		partCFrames = partCFrames,
	}, nil, nil
end

function BodyPartVisuals.ValidateReferencePose(character: Model): (boolean, string?, string?)
	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model.", "invalid_character"
	end

	local referencePose, referencePoseError, referencePoseErrorKind = buildReferencePose(character)
	if not referencePose then
		return false, referencePoseError or "Failed to build the neutral reference pose.", referencePoseErrorKind
	end

	return true, nil, nil
end

local function applyExternalSeamAlignment(
	character: Model,
	region: string,
	visualPartsByName: { [string]: BasePart },
	referencePose
): (boolean, string?, string?, string?, string?)
	local seamSpec = REGION_EXTERNAL_SEAM_SPECS[region]
	if not seamSpec then
		return false, nil, nil, nil, nil
	end

	local movingRootPart = visualPartsByName[seamSpec.MovingRootPartName]
	if not movingRootPart then
		return false, nil, nil, nil, nil
	end

	local movingAttachment = findDirectAttachment(movingRootPart, seamSpec.AttachmentName)
	if not movingAttachment then
		return false, nil, nil, nil, nil
	end

	local anchorPart = getAppliedTorsoAnchorPart(character, seamSpec.AnchorPartName)
	local anchorAttachmentWorldCFrame =
		getAppliedRegionAttachmentWorldCFrame(character, seamSpec.AnchorRegion, seamSpec.AnchorPartName, seamSpec.AttachmentName)
	local anchorSource = nil

	if anchorAttachmentWorldCFrame then
		anchorSource = "AppliedTorso"
	else
		anchorPart = character:FindFirstChild(seamSpec.AnchorPartName)
		if not (anchorPart and anchorPart:IsA("BasePart")) then
			return false,
				nil,
				nil,
				string.format(
					"Missing seam anchor part %s on equipped torso and live character for region %s.",
					seamSpec.AnchorPartName,
					region
				),
				nil
		end

		anchorAttachmentWorldCFrame =
			getLiveReferenceAttachmentWorldCFrame(character, referencePose, seamSpec.AnchorPartName, seamSpec.AttachmentName)
		if not anchorAttachmentWorldCFrame then
			return false,
				nil,
				nil,
				string.format(
					"Missing seam attachment %s on equipped torso and live %s for region %s.",
					seamSpec.AttachmentName,
					seamSpec.AnchorPartName,
					region
				),
				nil
		end

		anchorSource = "LiveTorso"
	end

	local targetRootCFrame = anchorAttachmentWorldCFrame * movingAttachment.CFrame:Inverse()
	transformRegionParts(visualPartsByName, targetRootCFrame * movingRootPart.CFrame:Inverse())

	return true, seamSpec.AnchorRegion, seamSpec.AttachmentName, nil, anchorSource
end

local function rebindRegionAnimationConstraints(
	regionFolder: Model,
	region: string,
	visualPartsByName: { [string]: BasePart }
): (boolean, string?)
	local articulationSpec = REGION_ARTICULATION_SPECS[region]
	if not articulationSpec then
		return true, nil
	end

	local expected = {}
	for _, constraintSpec in ipairs(articulationSpec.Constraints) do
		expected[constraintSpec.ConstraintName] = constraintSpec
	end

	for _, descendant in ipairs(regionFolder:GetDescendants()) do
		if descendant:IsA("AnimationConstraint") then
			local constraintSpec = expected[descendant.Name]
			if not constraintSpec then
				descendant:Destroy()
			else
				local holderPart = visualPartsByName[constraintSpec.HolderPartName]
				local attachment0Part = visualPartsByName[constraintSpec.Attachment0PartName]
				local attachment1Part = visualPartsByName[constraintSpec.Attachment1PartName]
				local attachment0 = attachment0Part and findDirectAttachment(attachment0Part, constraintSpec.Attachment0Name) or nil
				local attachment1 = attachment1Part and findDirectAttachment(attachment1Part, constraintSpec.Attachment1Name) or nil
				if descendant.Parent ~= holderPart or not attachment0 or not attachment1 then
					return false, string.format("Missing articulated joint wiring for %s.%s.", region, constraintSpec.ConstraintName)
				end

				descendant.Attachment0 = attachment0
				descendant.Attachment1 = attachment1
				descendant.Enabled = true
				expected[descendant.Name] = nil
			end
		elseif descendant:IsA("BallSocketConstraint") then
			descendant:Destroy()
		end
	end

	for constraintName in pairs(expected) do
		return false, string.format("Missing articulated joint %s for region %s.", constraintName, region)
	end

	return true, nil
end

local function applyBundleGenericAssemblies(
	regionFolder: Model,
	bundle: Model,
	visualPartsByName: { [string]: BasePart },
	finalScale: number
): (boolean, string?)
	for _, child in ipairs(bundle:GetChildren()) do
		if child:IsA("Model") then
			local anchorPartName = child:GetAttribute(ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE)
			local anchorOffset = child:GetAttribute(ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE)
			local targetPartName = child:GetAttribute(ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE)

			if typeof(anchorPartName) ~= "string" or typeof(anchorOffset) ~= "CFrame" or typeof(targetPartName) ~= "string" then
				return false, string.format("Assembly %s is missing runtime metadata.", child.Name)
			end

			local targetPart = visualPartsByName[targetPartName]
			if not targetPart then
				return false, string.format("Assembly %s could not find target visual part %s.", child.Name, targetPartName)
			end

			local assemblyClone = child:Clone()
			local anchorPart = findAssemblyAnchorPart(assemblyClone, anchorPartName)
			if not anchorPart then
				assemblyClone:Destroy()
				return false, string.format("Assembly %s is missing anchor part %s.", child.Name, anchorPartName)
			end

			local relativeOffsets = {}
			for _, descendant in ipairs(assemblyClone:GetDescendants()) do
				if descendant:IsA("BasePart") then
					relativeOffsets[descendant] = anchorPart.CFrame:ToObjectSpace(descendant.CFrame)
				end
			end

			for _, descendant in ipairs(assemblyClone:GetDescendants()) do
				if descendant:IsA("BasePart") then
					configureVisualPart(descendant)
					scaleVisualPart(descendant, finalScale)
				elseif descendant:IsA("Weld") then
					descendant.C0 = getScaledOffset(descendant.C0, finalScale)
					descendant.C1 = getScaledOffset(descendant.C1, finalScale)
				end
			end

			for part, relativeOffset in pairs(relativeOffsets) do
				if part ~= anchorPart then
					part.CFrame = anchorPart.CFrame * getScaledOffset(relativeOffset, finalScale)
				end
			end

			assemblyClone.Parent = regionFolder
			anchorPart.CFrame = targetPart.CFrame * getScaledOffset(anchorOffset, finalScale)
			createConstraintWeld("AssemblyAnchorWeld", targetPart, anchorPart, anchorPart)
		end
	end

	return true, nil
end

local function rebindRegionNoCollisionConstraints(regionFolder: Model, visualPartsByName: { [string]: BasePart })
	for _, descendant in ipairs(regionFolder:GetDescendants()) do
		if descendant:IsA("NoCollisionConstraint") then
			local part0Name = descendant.Part0 and descendant.Part0.Name or nil
			local part1Name = descendant.Part1 and descendant.Part1.Name or nil
			local part0 = part0Name and visualPartsByName[part0Name] or nil
			local part1 = part1Name and visualPartsByName[part1Name] or nil
			if part0 and part1 then
				descendant.Part0 = part0
				descendant.Part1 = part1
			else
				descendant:Destroy()
			end
		elseif descendant:IsA("Motor6D") or descendant:IsA("BallSocketConstraint") then
			descendant:Destroy()
		end
	end
end

local function hideHeadTextures(headPart: BasePart, region: string)
	local attributeName = getDecalAttribute(region)
	for _, child in ipairs(headPart:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then
			if child:GetAttribute(attributeName) == nil then
				child:SetAttribute(attributeName, child.Transparency)
			end
			child.Transparency = 1
		end
	end
end

local function restoreHeadTextures(headPart: BasePart, region: string)
	local attributeName = getDecalAttribute(region)
	for _, child in ipairs(headPart:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then
			local originalTransparency = child:GetAttribute(attributeName)
			if originalTransparency ~= nil then
				child.Transparency = originalTransparency
				child:SetAttribute(attributeName, nil)
			end
		end
	end
end

local function hideCharacterPart(characterPart: BasePart, region: string)
	local transparencyAttribute = getTransparencyAttribute(region)
	if characterPart:GetAttribute(transparencyAttribute) == nil then
		characterPart:SetAttribute(transparencyAttribute, characterPart.Transparency)
	end
	characterPart.Transparency = 1

	local collisionAttribute = getCollisionAttribute(region)
	if characterPart:GetAttribute(collisionAttribute) == nil then
		characterPart:SetAttribute(collisionAttribute, characterPart.CanCollide)
	end
	local originalCollision = characterPart:GetAttribute(collisionAttribute)
	if originalCollision ~= nil then
		characterPart.CanCollide = originalCollision
	end

	if characterPart.Name == "Head" then
		hideHeadTextures(characterPart, region)
	end
end

local function restoreCharacterPart(characterPart: BasePart, region: string)
	local transparencyAttribute = getTransparencyAttribute(region)
	local originalTransparency = characterPart:GetAttribute(transparencyAttribute)
	if originalTransparency ~= nil then
		characterPart.Transparency = originalTransparency
		characterPart:SetAttribute(transparencyAttribute, nil)
	end

	local collisionAttribute = getCollisionAttribute(region)
	local originalCollision = characterPart:GetAttribute(collisionAttribute)
	if originalCollision ~= nil then
		characterPart.CanCollide = originalCollision
		characterPart:SetAttribute(collisionAttribute, nil)
	end

	if characterPart.Name == "Head" then
		restoreHeadTextures(characterPart, region)
	end
end

local function isR15Character(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.RigType == Enum.HumanoidRigType.R15) then
		return false
	end

	for _, partName in ipairs(ALL_RIG_PARTS) do
		local bodyPart = character:FindFirstChild(partName)
		if not (bodyPart and bodyPart:IsA("BasePart")) then
			return false
		end
	end

	return true
end

local function clearRegionInternal(character: Model, region: string)
	clearMutationRuntime(character, region)

	local regionFolder = getAppliedFolder(character):FindFirstChild(region)
	if regionFolder then
		regionFolder:Destroy()
	end

	storeAppliedRegionRequest(character, region, nil)
	storeAppliedRegionReferenceOffsets(character, region, CFrame.new(), nil)

	for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
		local bodyPart = character:FindFirstChild(bodyPartName)
		if bodyPart and bodyPart:IsA("BasePart") then
			restoreCharacterPart(bodyPart, region)
		end
	end
end

local function resyncTorsoDependentRegions(character: Model): (boolean, string?)
	if not USE_SOULS_STYLE_RUNTIME then
		return true, nil
	end

	local referencePose, referenceError = buildReferencePose(character)
	if not referencePose then
		return false, referenceError
	end

	for _, dependentRegion in ipairs(TORSO_SEAM_DEPENDENT_REGIONS) do
		local loadoutEntry = getStoredLoadoutEntry(character, dependentRegion)
		if loadoutEntry then
			local success, err = applyRegion(character, dependentRegion, loadoutEntry, referencePose)
			if not success then
				return false, err
			end

			local mutationRequest = loadoutEntry.mutation
			if mutationRequest then
				local mutationSuccess, mutationError = applyMutationRuntime(character, dependentRegion, mutationRequest)
				if not mutationSuccess then
					return false, mutationError
				end
			else
				clearMutationRuntime(character, dependentRegion)
			end
		end
	end

	return true, nil
end

function BodyPartVisuals.CanApplyMutation(
	character: Model,
	region: string,
	mutationRequest: ApplyMutationRequest?
): (boolean, string?)
	if mutationRequest == nil then
		return true, nil
	end

	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model."
	end

	if not isR15Character(character) then
		return false, "This system only supports R15 characters."
	end

	local runtimePlan, runtimeError = buildMutationRuntimePlan(character, region, mutationRequest)
	if not runtimePlan then
		return false, runtimeError
	end

	return true, nil
end

function BodyPartVisuals.CanApplyAura(character: Model, auraRequest: ApplyAuraRequest?): (boolean, string?)
	if auraRequest == nil then
		return true, nil
	end

	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model."
	end

	if not isR15Character(character) then
		return false, "This system only supports R15 characters."
	end

	local runtimePlan, runtimeError = buildAuraRuntimePlan(character, auraRequest)
	if not runtimePlan then
		return false, runtimeError
	end

	return true, nil
end

function BodyPartVisuals.HasAuraRuntimeInstances(character: Model): boolean
	if not (character and character:IsA("Model")) then
		return false
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:GetAttribute(AURA_RUNTIME_ATTRIBUTE) == true then
			return true
		end
	end

	return false
end

function BodyPartVisuals.ClearRegion(character: Model, region: string)
	clearRegionInternal(character, region)

	if region == "Torso" then
		local success, err = resyncTorsoDependentRegions(character)
		if not success and err then
			warn(string.format("[BodyPartVisuals] %s", err))
		end
	end
end

function BodyPartVisuals.ClearAll(character: Model)
	clearAuraRuntime(character)
	clearMutationRuntime(character)
	CharacterAppearanceHostApplier.ClearCharacter(character)
	for _, region in ipairs(BodyPartRegions.Order) do
		clearRegionInternal(character, region)
	end
	clearAppliedRegionRequests(character)
	clearAppliedRegionReferenceOffsets(character)
end

applyRegion = function(character: Model, region: string, regionRequest: ApplyRegionRequest, referencePose): (boolean, string?)
	if not BodyPartRegions.IsValid(region) then
		return false, string.format("Unknown region %s.", tostring(region))
	end

	local isNativeFallback = regionRequest.isNativeFallback == true
	local bundle = regionRequest.bundle
	if not isNativeFallback then
		if not (bundle and bundle:IsA("Model")) then
			return false, string.format("%s is missing a bundle model.", region)
		end

		local validationError = validateBundleVisualContract(bundle, region)
		if validationError then
			return false, validationError
		end
	end

	clearRegionInternal(character, region)

	local regionFolder = getRegionFolder(character, region)
	local finalScale = getFinalScale(regionRequest)
	local visualPartsByName = {}
	local characterPartsByName = {}
	local templateCFramesByName = {}
	local allowedAnimationConstraintNames = (not isNativeFallback and bundle:GetAttribute("ArticulatedRegionReady") == false)
			and nil
		or buildAllowedAnimationConstraintLookup(region)
	local nativeRigPlacementReady = if isNativeFallback then true else bundle:GetAttribute("NativeRigPlacementReady")
	local transformRotationReady = if isNativeFallback then true else bundle:GetAttribute("TransformRotationReady")
	local rigAttachmentOrientationReady = if isNativeFallback then true else bundle:GetAttribute("RigAttachmentOrientationReady")
	local rotationDriftFree = if isNativeFallback then true else bundle:GetAttribute("RotationDriftFree")

	for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
		local characterPart = character:FindFirstChild(bodyPartName)
		if not (characterPart and characterPart:IsA("BasePart")) then
			return false, string.format("Missing R15 body part %s on character.", bodyPartName)
		end

		local source = if isNativeFallback
			then resolveNativeFallbackSource(character, bodyPartName)
			else resolveTemplateSource(bundle, regionRequest, bodyPartName)
		if not source then
			if isNativeFallback then
				return false, string.format("Character is missing native fallback part %s.", bodyPartName)
			end
			return false, string.format("Bundle %s is missing %s.", bundle.Name, bodyPartName)
		end

		local visualPart = source:Clone()
		visualPart.Name = bodyPartName
		sanitizeVisualPartChildren(visualPart, allowedAnimationConstraintNames)
		configureVisualPart(visualPart)
		templateCFramesByName[bodyPartName] = visualPart.CFrame
		if not isNativeFallback and region == "Torso" and bodyPartName == "UpperTorso" then
			scaleVisualPart(visualPart, finalScale, getBodyPartTargetSize(bundle, bodyPartName, source, finalScale))
		else
			scaleVisualPart(visualPart, finalScale)
		end
		visualPart.Parent = regionFolder

		visualPartsByName[bodyPartName] = visualPart
		characterPartsByName[bodyPartName] = characterPart
	end

	if not isNativeFallback then
		local accessoriesApplied, accessoryError = applyBundleAccessories(regionFolder, bundle, region, visualPartsByName)
		if not accessoriesApplied then
			clearRegionInternal(character, region)
			return false, accessoryError
		end

		local assembliesApplied, assemblyError = applyBundleGenericAssemblies(regionFolder, bundle, visualPartsByName, finalScale)
		if not assembliesApplied then
			clearRegionInternal(character, region)
			return false, assemblyError
		end
	end

	local placementMode = PLACEMENT_MODE_PIVOT
	if not isNativeFallback and canUseCustomArticulatedPlacement(region, bundle, visualPartsByName, templateCFramesByName) then
		if placePartsWithAuthoredAssembly(region, regionRequest, referencePose, visualPartsByName, templateCFramesByName, finalScale) then
			placementMode = PLACEMENT_MODE_ARTICULATED
		end
	end

	if placementMode == PLACEMENT_MODE_PIVOT
		and not isNativeFallback
		and canUseAuthoredAssemblyPlacement(region, bundle, visualPartsByName, templateCFramesByName)
	then
		if placePartsWithAuthoredAssembly(region, regionRequest, referencePose, visualPartsByName, templateCFramesByName, finalScale) then
			placementMode = PLACEMENT_MODE_AUTHORED
		end
	end

	if placementMode == PLACEMENT_MODE_PIVOT and canUseAttachmentChainPlacement(region, visualPartsByName) then
		if placePartsWithAttachmentChain(region, regionRequest, referencePose, visualPartsByName, finalScale) then
			placementMode = PLACEMENT_MODE_CHAIN
		end
	end

	if placementMode == PLACEMENT_MODE_PIVOT then
		for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
			local partReferenceCFrame = referencePose and referencePose.partCFrames[bodyPartName] or nil
			if not partReferenceCFrame then
				clearRegionInternal(character, region)
				return false, string.format("Missing neutral reference pose for %s.", bodyPartName)
			end
			placePartFromReference(
				partReferenceCFrame,
				visualPartsByName[bodyPartName],
				getAttachRule(regionRequest, bodyPartName),
				finalScale
			)
		end
	end

	local torsoSeamCorrectionSource = nil
	if region == "Torso" then
		local corrected, seamSourceOrError = correctTorsoUpperPartFromLiveWaistSeam(character, referencePose, visualPartsByName)
		if not corrected then
			clearRegionInternal(character, region)
			return false, seamSourceOrError or "Failed to correct torso upper-part seam placement."
		end
		torsoSeamCorrectionSource = seamSourceOrError
	end

	local usedExternalSeamAlignment, externalSeamAnchorRegion, externalSeamAttachmentName, externalSeamError, externalSeamAnchorSource =
		false, nil, nil, nil, nil
	usedExternalSeamAlignment, externalSeamAnchorRegion, externalSeamAttachmentName, externalSeamError, externalSeamAnchorSource =
		applyExternalSeamAlignment(character, region, visualPartsByName, referencePose)
	if externalSeamError then
		clearRegionInternal(character, region)
		return false, externalSeamError
	end

	local authoredSpec = REGION_AUTHORED_ASSEMBLY_SPECS[region]
	local authoredRootPartName = authoredSpec and authoredSpec.RootPartName or nil
	local authoredRootVisualPart = authoredRootPartName and visualPartsByName[authoredRootPartName] or nil
	local authoredRootCharacterPart = authoredRootPartName and characterPartsByName[authoredRootPartName] or nil

	for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
		local characterPart = characterPartsByName[bodyPartName]
		local visualPart = visualPartsByName[bodyPartName]
		local attachRule = getAttachRule(regionRequest, bodyPartName)

		if (placementMode == PLACEMENT_MODE_ARTICULATED or placementMode == PLACEMENT_MODE_AUTHORED)
			and authoredRootVisualPart
			and authoredRootCharacterPart
		then
			if bodyPartName == authoredRootPartName then
				createSolvedRigWeld("BodyPartWeld", authoredRootCharacterPart, visualPart, visualPart)
			elseif placementMode == PLACEMENT_MODE_AUTHORED then
				createConstraintWeld("BodyPartAssemblyWeld", authoredRootVisualPart, visualPart, visualPart)
			end
		else
			createSolvedRigWeld("BodyPartWeld", characterPart, visualPart, visualPart)
		end

		if attachRule.hideCharacterPart ~= false then
			hideCharacterPart(characterPart, region)
		end
	end

	rebindRegionNoCollisionConstraints(regionFolder, visualPartsByName)
	if placementMode == PLACEMENT_MODE_ARTICULATED then
		local rebound, reboundError = rebindRegionAnimationConstraints(regionFolder, region, visualPartsByName)
		if not rebound then
			clearRegionInternal(character, region)
			return false, reboundError or string.format("Failed to rebind articulated constraints for %s.", region)
		end
	end

	regionFolder:SetAttribute("BodyPartRegion", region)
	regionFolder:SetAttribute("BundleName", if isNativeFallback then REGION_SOURCE_NATIVE_FALLBACK else bundle.Name)
	regionFolder:SetAttribute(
		HAS_IMPORTED_BODY_COLORS_ATTRIBUTE,
		if isNativeFallback then false else bundle:GetAttribute(HAS_IMPORTED_BODY_COLORS_ATTRIBUTE) == true
	)
	regionFolder:SetAttribute(REGION_SOURCE_ATTRIBUTE, if isNativeFallback then REGION_SOURCE_NATIVE_FALLBACK else REGION_SOURCE_BUNDLE)
	regionFolder:SetAttribute("AppliedScale", finalScale)
	regionFolder:SetAttribute("PlacementMode", placementMode)
	regionFolder:SetAttribute("RuntimeMode", if USE_SOULS_STYLE_RUNTIME then "SoulsAdapter" else "Legacy")
	regionFolder:SetAttribute("UsedCustomArticulatedPlacement", placementMode == PLACEMENT_MODE_ARTICULATED)
	regionFolder:SetAttribute("UsedAuthoredAssemblyPlacement", placementMode == PLACEMENT_MODE_AUTHORED)
	regionFolder:SetAttribute("UsedAttachmentChainPlacement", placementMode == PLACEMENT_MODE_CHAIN)
	regionFolder:SetAttribute(
		"IsCustomCapable",
		placementMode == PLACEMENT_MODE_ARTICULATED
			or placementMode == PLACEMENT_MODE_AUTHORED
	)
	regionFolder:SetAttribute("SupportsExternalSeams", if isNativeFallback then true else bundle:GetAttribute("ExternalSeamReady") ~= false)
	regionFolder:SetAttribute("UsedExternalSeamAlignment", usedExternalSeamAlignment)
	regionFolder:SetAttribute("ExternalSeamAnchorRegion", externalSeamAnchorRegion)
	regionFolder:SetAttribute("ExternalSeamAttachmentName", externalSeamAttachmentName)
	regionFolder:SetAttribute("ExternalSeamAnchorSource", externalSeamAnchorSource)
	regionFolder:SetAttribute("HeadLockedToTorso", false)
	regionFolder:SetAttribute("LiveAnchorWeldMode", "SolvedWeld")
	regionFolder:SetAttribute("SeamSolveSource", nil)
	regionFolder:SetAttribute("TorsoSeamSource", torsoSeamCorrectionSource)
	regionFolder:SetAttribute("NativeRigPlacementReady", nativeRigPlacementReady)
	regionFolder:SetAttribute("TransformRotationReady", transformRotationReady)
	regionFolder:SetAttribute("RigAttachmentOrientationReady", rigAttachmentOrientationReady)
	regionFolder:SetAttribute("RotationDriftFree", rotationDriftFree)

	local regionReferencePartCFrames = {}
	for partName, visualPart in pairs(visualPartsByName) do
		regionReferencePartCFrames[partName] = visualPart.CFrame
	end
	storeAppliedRegionReferenceOffsets(character, region, referencePose.rootCFrame, regionReferencePartCFrames)

	storeAppliedRegionRequest(character, region, {
		bundle = bundle,
		scale = finalScale,
		attachRules = cloneAttachRules(regionRequest.attachRules),
		isNativeFallback = isNativeFallback,
		applyPlayerClothing = regionRequest.applyPlayerClothing,
		applyPlayerBodyColors = regionRequest.applyPlayerBodyColors,
	})

	return true, nil
end

local function applyRig(character: Model, baseRig: Model, request: ApplyRequest): (boolean, string?)
	local snapshot, snapshotError = captureBaseline(character)
	if not snapshot then
		return false, snapshotError
	end

	local previousLowestFootBottomY = computeLowestFootBottomY(character)
	local targetSizes, targetError = buildTargetSizes(baseRig, request)
	if not targetSizes then
		return false, targetError
	end

	applyPartSizes(character, targetSizes)
	applyAttachmentScaling(snapshot, targetSizes)
	applyMotorScaling(snapshot, targetSizes)

	settleCharacterFooting(character, previousLowestFootBottomY)
	return true, nil
end

local function buildResult(success: boolean, errors: { string }, appliedRegions: { string }, character: Model): ApplyResult
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return {
		success = success,
		errors = errors,
		appliedRegions = appliedRegions,
		hipHeight = if humanoid then humanoid.HipHeight else nil,
	}
end

local function hasAnyRequestedRegions(regionRequests: { [string]: ApplyRegionRequest? }?): boolean
	if typeof(regionRequests) ~= "table" then
		return false
	end

	for _, region in ipairs(FULL_LOADOUT_REGION_ORDER) do
		if regionRequests[region] ~= nil then
			return true
		end
	end

	return false
end

function BodyPartVisuals.RefreshAppearance(character: Model, request: ApplyRequest?): (boolean, string?)
	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model."
	end

	local regionRequests = if typeof(request) == "table" then request.regions else nil
	if hasAnyRequestedRegions(regionRequests) then
		return CharacterAppearanceHostApplier.ApplyCharacter(character, regionRequests)
	end

	CharacterAppearanceHostApplier.ClearCharacter(character)
	return true, nil
end

function BodyPartVisuals.Apply(character: Model, request: ApplyRequest): ApplyResult
	local startedAt = PerfStats.Begin()
	local releaseBuildPose = quiesceCharacterForBuild(character)

	local function finalize(result: ApplyResult): ApplyResult
		releaseBuildPose()
		PerfStats.Measure("BodyPartVisualsApply", startedAt, {
			success = result.success,
			appliedRegionCount = #result.appliedRegions,
			errorCount = #result.errors,
		})
		return result
	end

	local ok, resultOrTrace = xpcall(function()
		local errors = {}
		local appliedRegions = {}

		if not (character and character:IsA("Model")) then
			table.insert(errors, "Character must be a Model.")
			return {
				success = false,
				errors = errors,
				appliedRegions = appliedRegions,
				hipHeight = nil,
			}
		end

		if not isR15Character(character) then
			table.insert(errors, "This system only supports R15 characters.")
			return buildResult(false, errors, appliedRegions, character)
		end

		if typeof(request) ~= "table" then
			table.insert(errors, "Apply request must be a table.")
			return buildResult(false, errors, appliedRegions, character)
		end

		local baseRig = request.baseRig
		if not (baseRig and baseRig:IsA("Model")) then
			table.insert(errors, "Apply request is missing a valid base rig.")
			return buildResult(false, errors, appliedRegions, character)
		end

		local snapshotSuccess, snapshotError = CharacterAppearanceHostApplier.EnsureSnapshot(character)
		if not snapshotSuccess then
			table.insert(errors, snapshotError or "Failed to capture the native appearance snapshot.")
			return buildResult(false, errors, appliedRegions, character)
		end

		local rigSuccess, rigError = applyRig(character, baseRig, request)
		if not rigSuccess then
			table.insert(errors, rigError or "Failed to resize the live rig.")
			return buildResult(false, errors, appliedRegions, character)
		end

		local referencePose, referenceError = buildReferencePose(character)
		if not referencePose then
			table.insert(errors, referenceError or "Failed to build the neutral reference pose.")
			return buildResult(false, errors, appliedRegions, character)
		end

		for _, region in ipairs(FULL_LOADOUT_REGION_ORDER) do
			local regionRequest = request.regions and request.regions[region] or nil
			if regionRequest then
				local success, err = applyRegion(character, region, regionRequest, referencePose)
				if not success then
					table.insert(errors, err or string.format("Failed to apply %s.", region))
					break
				end
				table.insert(appliedRegions, region)
			else
				clearRegionInternal(character, region)
			end
		end

		if #errors == 0 then
			local appearanceSuccess, appearanceError = BodyPartVisuals.RefreshAppearance(character, request)
			if not appearanceSuccess and appearanceError then
				warn(string.format("[CharacterAppearanceHostApplier] %s", tostring(appearanceError)))
			end

			for _, region in ipairs(FULL_LOADOUT_REGION_ORDER) do
				local regionRequest = request.regions and request.regions[region] or nil
				local mutationRequest = regionRequest and regionRequest.mutation or nil
				if regionRequest and mutationRequest then
					local mutationSuccess, mutationError = applyMutationRuntime(character, region, mutationRequest)
					if not mutationSuccess then
						clearMutationRuntime(character, region)
						table.insert(errors, mutationError or string.format("Failed to apply %s mutation VFX.", region))
					end
				else
					clearMutationRuntime(character, region)
				end
			end

			if #errors == 0 and request.aura then
				local auraSuccess, auraError = applyAuraRuntime(character, request.aura)
				if not auraSuccess then
					table.insert(errors, auraError or "Failed to apply the equipped aura.")
				end
			elseif #errors == 0 then
				clearAuraRuntime(character)
			end

			if #errors == 0 then
				local previousLowestFootBottomY = computeLowestFootBottomY(character)
				settleCharacterFooting(character, previousLowestFootBottomY)

				local finalAccessoryAlignmentSuccess, finalAccessoryAlignmentError =
					CharacterAppearanceHostApplier.RefreshManagedAccessoryAlignment(character, request.regions)
				if not finalAccessoryAlignmentSuccess and finalAccessoryAlignmentError then
					warn(string.format("[CharacterAppearanceHostApplier] %s", tostring(finalAccessoryAlignmentError)))
				end
			end
		end

		return buildResult(#errors == 0, errors, appliedRegions, character)
	end, debug.traceback)

	if not ok then
		return finalize({
			success = false,
			errors = { tostring(resultOrTrace) },
			appliedRegions = {},
			hipHeight = nil,
		})
	end

	return finalize(resultOrTrace)
end

function BodyPartVisuals.Reset(character: Model, _baseRig: Model?): ApplyResult
	local startedAt = PerfStats.Begin()
	local releaseBuildPose = quiesceCharacterForBuild(character)

	local function finalize(result: ApplyResult): ApplyResult
		releaseBuildPose()
		PerfStats.Measure("BodyPartVisualsReset", startedAt, {
			success = result.success,
			errorCount = #result.errors,
		})
		return result
	end

	local ok, resultOrTrace = xpcall(function()
		local errors = {}

		if not (character and character:IsA("Model")) then
			table.insert(errors, "Character must be a Model.")
			return {
				success = false,
				errors = errors,
				appliedRegions = {},
				hipHeight = nil,
			}
		end

		BodyPartVisuals.ClearAll(character)

		local snapshot, snapshotError = captureBaseline(character)
		if not snapshot then
			table.insert(errors, snapshotError or "Unable to restore the baseline rig.")
			return buildResult(false, errors, {}, character)
		end

		local previousLowestFootBottomY = computeLowestFootBottomY(character)
		applyPartSizes(character, snapshot.parts)
		applyAttachmentScaling(snapshot, snapshot.parts)
		applyMotorScaling(snapshot, snapshot.parts)

		settleCharacterFooting(character, previousLowestFootBottomY)

		local appearanceSuccess, appearanceError = CharacterAppearanceHostApplier.RestoreNativeCharacterAppearance(character)
		if not appearanceSuccess and appearanceError then
			table.insert(errors, appearanceError)
		end

		return buildResult(true, errors, {}, character)
	end, debug.traceback)

	if not ok then
		return finalize({
			success = false,
			errors = { tostring(resultOrTrace) },
			appliedRegions = {},
			hipHeight = nil,
		})
	end

	return finalize(resultOrTrace)
end

return BodyPartVisuals
