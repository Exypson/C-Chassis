-- C-Chassis feel layer: tyre smoke and skid marks from real wheel slip, speed FOV, and a camera kick on crashes.
-- Delete this plugin to drop it; nothing else depends on it. Effects are local to the driver.
local RunService = game:GetService("RunService")

local car = script.Parent.Car.Value :: Model
local seat = car.DriveSeat :: VehicleSeat
local camera = workspace.CurrentCamera

local SLIP_START = 12 -- studs/s of tyre slip before smoke and marks appear (about 12 km/h)
local SLIP_FULL = 45 -- slip at full smoke
local SMOKE_RATE = 90 -- particles/s per wheel at full slip
local FOV_GAIN = 14 -- extra degrees at FOV_TOP_SPEED
local FOV_START, FOV_TOP_SPEED = 60, 260 -- km/h
local CRASH_DELTA = 40 -- studs/s lost in one frame that counts as a crash
local SHAKE_DECAY = 6 -- per second

local KMH = 0.28 * 3.6 -- studs/s -> km/h (A-Chassis: 1 stud = 0.28 m)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { car }

local wheels = {}
for _, wheel in car.Wheels:GetChildren() do
	if not wheel:IsA("BasePart") then
		continue
	end

	local contact = Instance.new("Attachment")
	contact.Name = "#FeelContact"
	contact.Parent = wheel

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 0
	smoke.Lifetime = NumberRange.new(1.2, 2.2)
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(40, 40)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Drag = 1.5
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 7) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(225, 225, 225))
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.Parent = contact

	-- a ribbon across the tread, laid flat on the road, becomes the skid mark
	local edgeA = Instance.new("Attachment")
	edgeA.Parent = wheel
	local edgeB = Instance.new("Attachment")
	edgeB.Parent = wheel
	local skid = Instance.new("Trail")
	skid.Attachment0 = edgeA
	skid.Attachment1 = edgeB
	skid.Color = ColorSequence.new(Color3.fromRGB(18, 18, 18))
	skid.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	skid.Lifetime = 5
	skid.MinLength = 0.2
	skid.FaceCamera = false
	skid.LightInfluence = 1
	skid.Enabled = false
	skid.Parent = wheel

	table.insert(wheels, {
		part = wheel,
		radius = wheel.Size.Y / 2,
		halfWidth = wheel.Size.X / 2,
		contact = contact,
		smoke = smoke,
		edgeA = edgeA,
		edgeB = edgeB,
		skid = skid,
	})
end

local baseFov = camera.FieldOfView
local shake = 0
local lastVelocity = seat.AssemblyLinearVelocity

local function updateWheel(w)
	local wheel = w.part
	local hit = workspace:Raycast(wheel.Position, Vector3.new(0, -(w.radius + 0.8), 0), rayParams)
	if not hit then
		w.smoke.Rate = 0
		w.skid.Enabled = false
		return
	end

	-- velocity of the tread touching the road: zero when rolling, the slide speed when spinning or skidding
	local slip = wheel:GetVelocityAtPosition(hit.Position).Magnitude
	local amount = math.clamp((slip - SLIP_START) / (SLIP_FULL - SLIP_START), 0, 1)

	local road = hit.Position + hit.Normal * 0.05
	local across = wheel.CFrame.RightVector * w.halfWidth
	w.contact.WorldPosition = road
	w.edgeA.WorldPosition = road + across
	w.edgeB.WorldPosition = road - across

	w.smoke.Rate = amount * SMOKE_RATE
	w.skid.Enabled = amount > 0
end

RunService.PreRender:Connect(function(dt)
	if not seat.Occupant then
		camera.FieldOfView += (baseFov - camera.FieldOfView) * math.min(dt * 4, 1)
		for _, w in wheels do
			w.smoke.Rate = 0
			w.skid.Enabled = false
		end
		return
	end

	for _, w in wheels do
		updateWheel(w)
	end

	local velocity = seat.AssemblyLinearVelocity
	local speedKmh = velocity.Magnitude * KMH
	local fov = baseFov + FOV_GAIN * math.clamp((speedKmh - FOV_START) / (FOV_TOP_SPEED - FOV_START), 0, 1)
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(dt * 3, 1)

	local lost = (lastVelocity - velocity).Magnitude
	lastVelocity = velocity
	if lost > CRASH_DELTA then
		shake = math.max(shake, math.clamp(lost / 120, 0.3, 1))
	end
end)

-- after the default camera has placed itself, so the kick adds to it instead of being overwritten
local SHAKE_BIND = "C-Chassis Feel Shake"
RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake <= 0 then
		return
	end
	local t = os.clock() * 40
	local angle = math.rad(1.6) * shake
	camera.CFrame *= CFrame.Angles(math.noise(t, 0) * angle, math.noise(0, t) * angle, math.noise(t, t) * angle)
	shake = math.max(shake - dt * SHAKE_DECAY * shake - dt * 0.2, 0)
end)

-- the interface is destroyed when the driver leaves; hand the camera back untouched
script.AncestryChanged:Connect(function()
	if script:IsDescendantOf(game) then
		return
	end
	RunService:UnbindFromRenderStep(SHAKE_BIND)
	camera.FieldOfView = baseFov
	for _, w in wheels do
		w.contact:Destroy()
		w.edgeA:Destroy()
		w.edgeB:Destroy()
		w.skid:Destroy()
	end
end)
