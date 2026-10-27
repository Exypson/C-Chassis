-- ESC, ABS and TCS: driver aids that trim each wheel's brake and drive output.
local S = require(script.Parent.State)
local Util = require(script.Parent.Util)

local SampleCurve = Util.SampleCurve
local Tune, Units = S.Tune, S.Units

local Assists = {}

-- Picks the one wheel ESC brakes this step, and how hard. Returns nil, 0 when ESC is idle.
function Assists.esc(speedKmh: number): (string?, number)
	local escTargetWheel = nil
	local escBrake = 0

	if S.ESC and speedKmh > Tune.ESCSpeed then
		local speedMps = S.Velocity.Magnitude * (Units.Length_mm / 1000)
		local steerAngle = math.rad(S.GSteerC * Tune.MaxSteerAngle * SampleCurve(Tune.MaxAngleCurve, speedKmh))
		local desiredYaw = (speedMps / math.max(S.Wheelbase, 0.001)) * math.tan(steerAngle)
		local actualYaw = S.WeightBrick.CFrame:VectorToObjectSpace(S.WeightBrick.AssemblyAngularVelocity).Y

		local maxYaw = 9.80665 / math.max(speedMps, 0.001) -- 1 g limit
		desiredYaw = math.clamp(desiredYaw, -maxYaw, maxYaw)

		local yawError = desiredYaw - actualYaw
		local threshold = math.max(Tune.ESCThreshold, 0.001)

		if math.abs(yawError) > threshold then
			local desiredSign = math.sign(desiredYaw)
			local turnSign = desiredSign ~= 0 and desiredSign or math.sign(actualYaw)

			if turnSign ~= 0 then
				if desiredSign ~= 0 and math.sign(yawError) == desiredSign then
					escTargetWheel = turnSign > 0 and "RL" or "RR" -- brake the inside rear wheel
				else
					escTargetWheel = turnSign > 0 and "FR" or "FL" -- brake the outside front wheel
				end

				local response = math.clamp((math.abs(yawError) - threshold) / threshold, 0, 1)
				escBrake = response * math.clamp(Tune.ESCBrake / 100, 0, 1)
			end
		end
	end

	return escTargetWheel, escBrake
end

-- Applies ESC and ABS to output.Brake in place; returns the TCS torque multiplier for this wheel.
function Assists.wheel(data, output, escTargetWheel: string?, escBrake: number): number
	-- Apply ESC
	local tqESC = 0
	if data.Name == escTargetWheel then
		tqESC = math.min(escBrake, math.max(1 - output.Brake, 0))
		output.Brake += tqESC
	end

	S.ESCActive = tqESC > 0 or S.ESCActive
	S.ESCTracker[data.Name] = tqESC

	local slip = math.abs(
		data.RotVelocityMagnitude * (data.Size.Y / 2) / (Units.Velocity_mdivs / 3.6)
			- data.WheelVelocityMagnitude / (Units.Velocity_mdivs / 3.6)
	)

	-- Apply ABS
	local tqABS = 1
	if S.ABS and output.Brake > 0 then
		tqABS = 1
			- (math.min(math.max(0, slip - Tune.ABSThreshold) / Tune.ABSGradient, 1) * (1 - (Tune.ABSLimit / 100)))
		output.Brake *= tqABS
	end

	S.ABSActive = tqABS < 1 or S.ABSActive
	S.ABSTracker[data.Name] = 1 - tqABS

	-- Apply TCS
	local tqTCS = 1
	if data.driven and S.TCS and output.Power > 0.01 then
		tqTCS = 1
			- (math.min(math.max(0, slip - Tune.TCSThreshold) / Tune.TCSGradient, 1) * (1 - (Tune.TCSLimit / 100)))
	end

	if data.driven then
		S.TCSActive = tqTCS < 1 or S.TCSActive
		S.TCSTracker[data.Name] = 1 - tqTCS
	end

	return tqTCS
end

return Assists
