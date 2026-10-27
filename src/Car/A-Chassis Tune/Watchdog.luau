-- Server-side sanity check for a client-owned car. The driver's client simulates the car (that is what makes
-- A/B/C-Chassis feel smooth), so a cheater can push it anywhere; the server only flags motion the gearing
-- cannot produce. Deliberately generous: it should catch speed and teleport hacks, never a hard landing.
local RunService = game:GetService("RunService")

local Units = require(script.Parent.README.Units)

local CHECK_EVERY = 0.25 -- seconds
local SPEED_MARGIN = 1.5 -- x the gearing's top speed: downhill runs, launches off ramps
local SPEED_SLACK = 40 -- studs/s on top, so slow cars aren't flagged for a shove
local TELEPORT_SLACK = 12 -- studs per check beyond what that speed allows
local STRIKES = 3 -- consecutive bad checks before acting; one physics hiccup is not a cheat

-- Fastest the car can go in its tallest gear at redline, in studs/s.
local function topSpeed(Tune, car: Model): number
	local radius = 0
	for _, wheel in car.Wheels:GetChildren() do
		if wheel:IsA("BasePart") then
			radius = math.max(radius, wheel.Size.Y / 2)
		end
	end

	local redline = (not Tune.Engine and Tune.Electric) and Tune.E_Redline or Tune.Redline
	local ratio = math.huge
	if Tune.ClutchType == "CVT" then
		ratio = Tune.CVTMinRatio
	else
		local park = Tune.Ratios[1] == 0 and 1 or 0
		for i = 3 + park, #Tune.Ratios do
			ratio = math.min(ratio, Tune.Ratios[i])
		end
	end

	local speed = redline * math.pi / 30 / (ratio * Tune.FinalDrive) * radius
	if Tune.SpeedLimit > 0 then
		speed = math.min(speed, Tune.SpeedLimit / 3.6 * Units.Velocity_mdivs)
	end
	return speed
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Watches `player` driving `car` until the returned function is called.
local function watch(car: Model, player: Player, Tune): () -> ()
	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat
	local maxSpeed = topSpeed(Tune, car) * SPEED_MARGIN + SPEED_SLACK

	local lastGood = seat.CFrame
	local lastPos = seat.Position
	local strikes = 0
	local elapsed = 0

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_EVERY then
			return
		end

		local speed = flat(seat.AssemblyLinearVelocity).Magnitude
		local moved = flat(seat.Position - lastPos).Magnitude
		local allowed = maxSpeed * elapsed + TELEPORT_SLACK
		lastPos = seat.Position
		elapsed = 0

		if speed <= maxSpeed and moved <= allowed then
			strikes = 0
			lastGood = seat.CFrame
			return
		end

		strikes += 1
		if strikes < STRIKES then
			return
		end

		warn(
			`[C-Chassis] {player.Name} ({player.UserId}): impossible motion in {car:GetFullName()}, `
				.. `{math.floor(speed)} studs/s (max {math.floor(maxSpeed)}), moved {math.floor(moved)} studs `
				.. `(max {math.floor(allowed)}); car reset and driver ejected`
		)
		connection:Disconnect()

		-- take the car back, park it where it last moved legally, and unseat the driver
		seat:SetNetworkOwner(nil)
		car:PivotTo(lastGood * seat.CFrame:Inverse() * car:GetPivot())
		for _, part in car:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end)

	return function()
		connection:Disconnect()
	end
end

if RunService:IsStudio() then
	-- the bundled sedan's gearing on a 2.6 stud wheel: ~316 studs/s, about 320 km/h
	local fakeWheel = {
		IsA = function()
			return true
		end,
		Size = Vector3.new(1, 2.6, 2.6),
	}
	local fakeCar = { Wheels = {
		GetChildren = function()
			return { fakeWheel }
		end,
	} }
	local tune = {
		Engine = true,
		Redline = 7500,
		ClutchType = "Clutch",
		Ratios = { 3.18, 0, 3.927, 0.893 },
		FinalDrive = 3.621,
		SpeedLimit = 0,
	}
	local speed = topSpeed(tune, fakeCar :: any)
	assert(math.abs(speed - 7500 * math.pi / 30 / (0.893 * 3.621) * 1.3) < 1e-3, "top speed uses the tallest gear")
	tune.SpeedLimit = 100
	assert(topSpeed(tune, fakeCar :: any) < speed, "a speed limiter lowers the cap")
end

return watch
