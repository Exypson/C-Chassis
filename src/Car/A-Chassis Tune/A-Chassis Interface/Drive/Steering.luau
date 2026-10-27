local S = require(script.Parent.State)
local Util = require(script.Parent.Util)

local SampleCurve, MoveToward, StepForTime = Util.SampleCurve, Util.MoveToward, Util.StepForTime
local Tune, Units, Wheels = S.Tune, S.Units, S.Wheels

local Steering = {}

function Steering.step(dt: number)
	local speed = S.Velocity.Magnitude * (Units.Length_mm / 1000) * 3.6

	-- Steering Input
	local input = math.clamp(S.GSteerT, -1, 1)
	if math.abs(input) > Tune.SteerDeadzone then
		input = math.sign(input) * SampleCurve(Tune.SteerInputCurve, math.abs(input))
	else
		input = 0
	end

	-- Counter Steering
	S.CSAmt = 0

	if S.CS and speed > Tune.CSSpeedThresh then
		local sideRatio = S.Center:VectorToObjectSpace(S.Velocity).X / math.max(S.Velocity.Magnitude, 0.001)
		local csSideDeadzone = 0.02
		if math.abs(sideRatio) < csSideDeadzone then
			sideRatio = 0
		end

		local desiredCS = math.clamp(sideRatio, -1, 1) * (Tune.CSAmt / 100)
		local steerLimit = math.max(Tune.CSSteerThresh / 100, 0.001)
		local inputFade = 1 - math.clamp(math.abs(input) / steerLimit, 0, 1)

		S.CSAmt = desiredCS * inputFade

		if math.abs(S.CSAmt) <= ((Tune.CSAmt / 100) * 0.01) then
			S.CSAmt = 0
		end
	end

	S.CSActive = S.CSAmt ~= 0

	local target = math.clamp(input + S.CSAmt, -1, 1)
	if math.abs(target) < 0.001 then
		target = 0
	end

	local returning = math.abs(target) < math.abs(S.GSteerC) or target * S.GSteerC < 0
	local steerTime = returning and Tune.ReturnTime or Tune.SteerTime
	S.GSteerC = MoveToward(S.GSteerC, target, StepForTime(dt, steerTime))

	-- Four Wheel Steering
	local rearScale = 0
	if Tune.FWSteer ~= "None" then
		local rearSpeed = speed / math.max(Tune.RSteerSpeed, 0.001)
		if Tune.FWSteer == "Static" then
			rearScale = -math.max(0, 1 - rearSpeed)
		elseif Tune.FWSteer == "Speed" then
			rearScale = math.min(1, rearSpeed)
		elseif Tune.FWSteer == "Both" then
			rearScale = math.clamp(rearSpeed - 1, -1, 1)
		end
	end

	-- Apply
	local angleScale = SampleCurve(Tune.MaxAngleCurve, speed)
	for _, data in Wheels do
		if data.CanSteer == 0 then
			continue
		end

		if data.CanSteer ~= 2 then
			data.SteerAttach0.Orientation = Vector3.zero
			continue
		end

		local maxAngle = data.isFront and Tune.MaxSteerAngle or Tune.RMaxSteerAngle
		local steerScale = data.isFront and 1 or rearScale
		local steerAngle = S.GSteerC * maxAngle * angleScale * steerScale

		data.SteerAttach0.Orientation = Vector3.new(0, steerAngle, 0)
	end
end

return Steering
