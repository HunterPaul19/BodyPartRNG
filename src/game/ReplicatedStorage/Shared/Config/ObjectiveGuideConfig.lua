local ObjectiveGuideConfig = {}

ObjectiveGuideConfig.TargetTag = "ObjectiveGuideTarget"
ObjectiveGuideConfig.BeamTemplatePath = table.freeze({ "Particles", "TutorialBeam" })

ObjectiveGuideConfig.Attributes = table.freeze({
	Id = "ObjectiveGuideId",
	Enabled = "ObjectiveGuideEnabled",
	Radius = "ObjectiveGuideRadius",
	Color = "ObjectiveGuideColor",
})

ObjectiveGuideConfig.DefaultColor = Color3.fromRGB(72, 214, 255)
ObjectiveGuideConfig.DefaultArrivalRadius = 8
ObjectiveGuideConfig.DefaultHeightOffset = 0.08
ObjectiveGuideConfig.DefaultBeamWidth = 1.25
ObjectiveGuideConfig.DefaultBeamThickness = 0.08
ObjectiveGuideConfig.MaxBeamLength = 120
ObjectiveGuideConfig.MinVisibleDistance = 4
ObjectiveGuideConfig.GroundRaycastUpOffset = 16
ObjectiveGuideConfig.GroundRaycastDownDistance = 128

return table.freeze(ObjectiveGuideConfig)
