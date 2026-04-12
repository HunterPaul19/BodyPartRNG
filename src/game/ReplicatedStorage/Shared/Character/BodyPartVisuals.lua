local RunService = game:GetService("RunService")

local BodyPartRegions = require(script.Parent.BodyPartRegions)

local BodyPartVisuals = {}

export type ApplyRegionRequest = {
	bundle: Model,
	scale: number?,
	aura: any?,
}

export type ApplyRequest = {
	baseRig: Model,
	regions: { [string]: ApplyRegionRequest? },
}

export type ApplyResult = {
	success: boolean,
	errors: { string },
	appliedRegions: { string },
	hipHeight: number?,
}

local APPLIED_FOLDER_NAME = "CharacterBodyParts"
local TRANSPARENCY_ATTRIBUTE_PREFIX = "BodyPartOriginalTransparency_"
local COLLISION_ATTRIBUTE_PREFIX = "BodyPartOriginalCanCollide_"
local DECAL_ATTRIBUTE_PREFIX = "BodyPartOriginalDecalTransparency_"

local REGION_PARTS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "LowerTorso" },
	LeftArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RightArm = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LeftLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	RightLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

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

local SUPPORT_PART_NAMES = { "LeftFoot", "RightFoot" }

local ALWAYS_ALLOWED_CHILD_CLASSES = {
	Attachment = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
	WrapTarget = true,
	SpecialMesh = true,
	FaceControls = true,
}

local FORBIDDEN_BUNDLE_CLASSES = {
	Motor6D = true,
	AnimationConstraint = true,
	BallSocketConstraint = true,
	Animator = true,
	AnimationController = true,
}

local PLACEMENT_MODE_CHAIN = "InternalChainPlacement"
local PLACEMENT_MODE_PIVOT = "PivotPlacement"

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

local function isFinitePositiveNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < math.huge and value > -math.huge
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

local function validateBundleVisualContract(bundle: Model, region: string): string?
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

local function sanitizeVisualPartChildren(visualPart: BasePart)
	for _, child in ipairs(visualPart:GetChildren()) do
		if child:IsA("NoCollisionConstraint") then
			-- Rebound after cloning when both visual parts exist.
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

local function scaleVisualPart(part: BasePart, scale: number)
	part.Size = part.Size * scale

	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("SpecialMesh") then
			descendant.Scale = descendant.Scale * scale
		elseif descendant:IsA("Attachment") then
			descendant.Position = descendant.Position * scale
		end
	end
end

local function configureAccessoryHandle(part: BasePart)
	configureVisualPart(part)
end

local function findDirectAttachment(part: BasePart, attachmentName: string): Attachment?
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

local function createWeld(name: string, part0: BasePart, part1: BasePart, parent: Instance): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = parent
	return weld
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

local function scaleAccessory(accessory: Accessory, scale: number)
	local handle = accessory:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		configureAccessoryHandle(handle)
		scaleVisualPart(handle, scale)
	end
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

	createWeld("AccessoryWeld", targetPart, handle, handle)
	return true, nil
end

local function applyBundleAccessories(regionFolder: Model, bundle: Model, visualPartsByName: { [string]: BasePart }, finalScale: number): (boolean, string?)
	for _, child in ipairs(bundle:GetChildren()) do
		if child:IsA("Accessory") then
			local accessoryClone = child:Clone()
			scaleAccessory(accessoryClone, finalScale)
			accessoryClone.Parent = regionFolder

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

local function computeLowestFootBottomY(character: Model): number?
	local lowestBottom = math.huge

	for _, partName in ipairs(SUPPORT_PART_NAMES) do
		local part = character:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return nil
		end
		lowestBottom = math.min(lowestBottom, part.Position.Y - part.Size.Y * 0.5)
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
		hipHeight = humanoid.HipHeight,
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
		hipHeight = runtimeState.hipHeight,
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

local function updateHipHeight(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local supportDistance = computeFootSupportDistance(character)
	if not (humanoid and rootPart and rootPart:IsA("BasePart") and supportDistance) then
		return
	end

	humanoid.HipHeight = math.max(0, supportDistance - rootPart.Size.Y * 0.5)
end

local function shiftCharacterToPreserveFooting(character: Model, previousLowestFootBottomY: number?)
	if not previousLowestFootBottomY then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local newLowestFootBottomY = computeLowestFootBottomY(character)
	if not (rootPart and rootPart:IsA("BasePart") and newLowestFootBottomY) then
		return
	end

	local delta = previousLowestFootBottomY - newLowestFootBottomY
	if math.abs(delta) > 0.0001 then
		rootPart.CFrame = rootPart.CFrame + Vector3.new(0, delta, 0)
	end
end

local function findRegionPart(model: Model, partName: string): BasePart?
	local part = model:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
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
				local bundlePart = findRegionPart(bundle, partName)
				if not (bundlePart and bundlePart:IsA("BasePart")) then
					return nil, string.format("Bundle %s is missing %s for %s.", bundle.Name, partName, region)
				end

				targetSizes[partName] = bundlePart.Size * scale
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

local function placePartFromCharacter(characterPart: BasePart, visualPart: BasePart, finalScale: number)
	visualPart.CFrame = characterPart.CFrame * getScaledOffset(CFrame.new(), finalScale)
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

local function placePartsWithAttachmentChain(character: Model, region: string, visualPartsByName: { [string]: BasePart }, finalScale: number): boolean
	local chainSpec = REGION_CHAIN_SPECS[region]
	if not chainSpec then
		return false
	end

	local rootCharacterPart = character:FindFirstChild(chainSpec.RootPartName)
	local rootVisualPart = visualPartsByName[chainSpec.RootPartName]
	if not (rootCharacterPart and rootCharacterPart:IsA("BasePart") and rootVisualPart) then
		return false
	end

	placePartFromCharacter(rootCharacterPart, rootVisualPart, finalScale)

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

local function transformRegionParts(visualPartsByName: { [string]: BasePart }, transform: CFrame)
	for _, part in pairs(visualPartsByName) do
		part.CFrame = transform * part.CFrame
	end
end

local function applyExternalSeamAlignment(character: Model, region: string, visualPartsByName: { [string]: BasePart }): (boolean, string?, string?)
	local seamSpec = REGION_EXTERNAL_SEAM_SPECS[region]
	if not seamSpec then
		return false, nil, nil
	end

	local anchorFolder = getAppliedFolder(character):FindFirstChild(seamSpec.AnchorRegion)
	if not (anchorFolder and anchorFolder:IsA("Model")) then
		return false, nil, nil
	end

	local movingRootPart = visualPartsByName[seamSpec.MovingRootPartName]
	local anchorPart = anchorFolder:FindFirstChild(seamSpec.AnchorPartName, true)
	if not (movingRootPart and anchorPart and anchorPart:IsA("BasePart")) then
		return false, nil, nil
	end

	local movingAttachment = findDirectAttachment(movingRootPart, seamSpec.AttachmentName)
	local anchorAttachment = findDirectAttachment(anchorPart, seamSpec.AttachmentName)
	if not movingAttachment or not anchorAttachment then
		return false, nil, nil
	end

	local targetRootCFrame = anchorAttachment.WorldCFrame * movingAttachment.CFrame:Inverse()
	transformRegionParts(visualPartsByName, targetRootCFrame * movingRootPart.CFrame:Inverse())

	return true, seamSpec.AnchorRegion, seamSpec.AttachmentName
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

function BodyPartVisuals.ClearRegion(character: Model, region: string)
	local regionFolder = getAppliedFolder(character):FindFirstChild(region)
	if regionFolder then
		regionFolder:Destroy()
	end

	for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
		local bodyPart = character:FindFirstChild(bodyPartName)
		if bodyPart and bodyPart:IsA("BasePart") then
			restoreCharacterPart(bodyPart, region)
		end
	end
end

function BodyPartVisuals.ClearAll(character: Model)
	for _, region in ipairs(BodyPartRegions.Order) do
		BodyPartVisuals.ClearRegion(character, region)
	end
end

local function applyRegion(character: Model, region: string, regionRequest: ApplyRegionRequest): (boolean, string?)
	if not BodyPartRegions.IsValid(region) then
		return false, string.format("Unknown region %s.", tostring(region))
	end

	local bundle = regionRequest.bundle
	if not (bundle and bundle:IsA("Model")) then
		return false, string.format("%s is missing a bundle model.", region)
	end

	local validationError = validateBundleVisualContract(bundle, region)
	if validationError then
		return false, validationError
	end

	BodyPartVisuals.ClearRegion(character, region)

	local regionFolder = getRegionFolder(character, region)
	local finalScale = getFinalScale(regionRequest)
	local visualPartsByName = {}
	local characterPartsByName = {}

	for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
		local characterPart = character:FindFirstChild(bodyPartName)
		if not (characterPart and characterPart:IsA("BasePart")) then
			return false, string.format("Missing R15 body part %s on character.", bodyPartName)
		end

		local source = findRegionPart(bundle, bodyPartName)
		if not source then
			return false, string.format("Bundle %s is missing %s.", bundle.Name, bodyPartName)
		end

		local visualPart = source:Clone()
		visualPart.Name = bodyPartName
		sanitizeVisualPartChildren(visualPart)
		configureVisualPart(visualPart)
		scaleVisualPart(visualPart, finalScale)
		visualPart.Parent = regionFolder

		visualPartsByName[bodyPartName] = visualPart
		characterPartsByName[bodyPartName] = characterPart
	end

	local accessoriesApplied, accessoryError = applyBundleAccessories(regionFolder, bundle, visualPartsByName, finalScale)
	if not accessoriesApplied then
		BodyPartVisuals.ClearRegion(character, region)
		return false, accessoryError
	end

	local placementMode = PLACEMENT_MODE_PIVOT
	if canUseAttachmentChainPlacement(region, visualPartsByName) then
		if placePartsWithAttachmentChain(character, region, visualPartsByName, finalScale) then
			placementMode = PLACEMENT_MODE_CHAIN
		end
	end

	if placementMode == PLACEMENT_MODE_PIVOT then
		for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
			placePartFromCharacter(characterPartsByName[bodyPartName], visualPartsByName[bodyPartName], finalScale)
		end
	end

	local usedExternalSeamAlignment, externalSeamAnchorRegion, externalSeamAttachmentName =
		applyExternalSeamAlignment(character, region, visualPartsByName)

	for _, bodyPartName in ipairs(getRigPartNames(region) or {}) do
		local characterPart = characterPartsByName[bodyPartName]
		local visualPart = visualPartsByName[bodyPartName]
		createWeld("BodyPartWeld", characterPart, visualPart, visualPart)
		hideCharacterPart(characterPart, region)
	end

	rebindRegionNoCollisionConstraints(regionFolder, visualPartsByName)

	regionFolder:SetAttribute("BodyPartRegion", region)
	regionFolder:SetAttribute("BundleName", bundle.Name)
	regionFolder:SetAttribute("AppliedScale", finalScale)
	regionFolder:SetAttribute("PlacementMode", placementMode)
	regionFolder:SetAttribute("UsedAttachmentChainPlacement", placementMode == PLACEMENT_MODE_CHAIN)
	regionFolder:SetAttribute("UsedExternalSeamAlignment", usedExternalSeamAlignment)
	regionFolder:SetAttribute("ExternalSeamAnchorRegion", externalSeamAnchorRegion)
	regionFolder:SetAttribute("ExternalSeamAttachmentName", externalSeamAttachmentName)

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

	RunService.Heartbeat:Wait()
	shiftCharacterToPreserveFooting(character, previousLowestFootBottomY)
	RunService.Heartbeat:Wait()
	updateHipHeight(character)

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

function BodyPartVisuals.Apply(character: Model, request: ApplyRequest): ApplyResult
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

	local rigSuccess, rigError = applyRig(character, baseRig, request)
	if not rigSuccess then
		table.insert(errors, rigError or "Failed to resize the live rig.")
		return buildResult(false, errors, appliedRegions, character)
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local regionRequest = request.regions and request.regions[region] or nil
		if regionRequest then
			local success, err = applyRegion(character, region, regionRequest)
			if not success then
				table.insert(errors, err or string.format("Failed to apply %s.", region))
				break
			end
			table.insert(appliedRegions, region)
		else
			BodyPartVisuals.ClearRegion(character, region)
		end
	end

	return buildResult(#errors == 0, errors, appliedRegions, character)
end

function BodyPartVisuals.Reset(character: Model, _baseRig: Model?): ApplyResult
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

	RunService.Heartbeat:Wait()
	shiftCharacterToPreserveFooting(character, previousLowestFootBottomY)
	RunService.Heartbeat:Wait()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HipHeight = snapshot.hipHeight
	end

	return buildResult(true, errors, {}, character)
end

return BodyPartVisuals
