-- Wheel I/O: reads wheel speeds in, drives the #AV (drive) and #BV (brake) hinge motors out.
local S = require(script.Parent.State)
local Assists = require(script.Parent.Assists)
local Differential = require(script.Parent.Differential)

local Tune, Units = S.Tune, S.Units
local Wheels, Drive = S.Wheels, S.Drive

local WheelModule = {}

function WheelModule.apply(dt: number)
	local speedKmh = S.Velocity.Magnitude / (Units.Velocity_mdivs / 3.6)

	-- Brakes
	local FBrakeForce = Tune.BrakeForce * 9.80665 * Units.Force_N * Tune.BrakeBias -- luaint edit, conversion to SI unit Detomiks
	local RBrakeForce = Tune.BrakeForce * 9.80665 * Units.Force_N * (1 - Tune.BrakeBias) -- luaint edit
	local PBrakeForceF = Tune.PBrakeForce * 9.80665 * Units.Force_N * Tune.PBrakeBias
	local PBrakeForceR = Tune.PBrakeForce * 9.80665 * Units.Force_N * (1 - Tune.PBrakeBias)

	local escTargetWheel, escBrake = Assists.esc(speedKmh)

	for _, data in Wheels do
		local PBrakeV = (S.PBrake == true or S.CGear == -2) and 1 or 0
		local on = S.IsOn and 1 or 0

		local clutch = 1
		if S.ClPressing or (S.AutoClutch and S.Starting) then
			clutch = 0
		end

		local output = Differential.output(data, S.GThrot, S.GBrake, dt)
		local tqTCS = Assists.wheel(data, output, escTargetWheel, escBrake)

		-- Apply Drive
		if data.driven then
			local bias = (Tune.Config == "AWD" and (Tune.TorqueVector + 1) / 2) or (Tune.Config == "FWD" and 0) or 1
			local tq = data.isFront and (S.OutTorque * (1 - bias)) / S.FWheelCount
				or (S.OutTorque * bias) / S.RWheelCount
			local tqOUT = ((tq * 1.356 * Units.Torque_nm * tqTCS * clutch) + (S.FlywheelEnergy / #Drive))
				* output.Power
				* on

			data.AV.MotorMaxTorque = tqOUT * output.Torque
			data.AV.AngularVelocity = math.abs(S.spLimit) * output.Speed
		else
			data.AV.MotorMaxTorque = 0
			data.AV.AngularVelocity = 0
		end

		-- Apply Brakes
		local brakeForce = data.isFront and FBrakeForce or RBrakeForce
		local pBrakeForce = data.isFront and PBrakeForceF or PBrakeForceR
		local eBrakeForce = data.driven and (Tune.EBrakeForce * clutch * ((1 - output.Power) * (S.RPM / Tune.Redline)))
			or 0

		data.BV.MotorMaxTorque = (brakeForce * output.Brake) + eBrakeForce + (pBrakeForce * PBrakeV)
	end
end

-- Midpoint between the axles, facing forward; also refreshes the wheelbase.
function WheelModule.center(): CFrame
	local centerF = Vector3.new()
	local centerR = Vector3.new()
	local countF = 0
	local countR = 0

	for wheel, data in Wheels do
		if data.isFront then
			centerF = centerF + wheel.Position
			countF = countF + 1
		else
			centerR = centerR + wheel.Position
			countR = countR + 1
		end
	end

	centerF = centerF / countF
	centerR = centerR / countR

	S.Wheelbase = math.max((centerF - centerR).Magnitude * (Units.Length_mm / 1000), 0.001)

	return CFrame.lookAt(centerR:Lerp(centerF, 0.5), centerF)
end

function WheelModule.sense(_dt: number)
	local tcsCount = 0
	local absCount = 0
	local escCount = 0
	local rot = 0
	local count = 0
	local driveCount = 0

	S.TCSAmt = 0
	S.ABSAmt = 0
	S.ESCAmt = 0

	S.MaxWheelSpin = 0
	S.DriveWheelSpeed = 0

	for wheel, data in Wheels do
		count += 1

		-- Wheel speeds
		if not S.WheelSpeedsTable[data.Name] then
			S.WheelSpeedsTable[data.Name] = {}
		end

		data.RotVelocityMagnitude = wheel.RotVelocity.Magnitude
		data.WheelVelocityMagnitude = wheel.Velocity.Magnitude

		local samples = S.WheelSpeedsTable[data.Name]
		table.insert(samples, data.RotVelocityMagnitude)
		if #samples > 8 then
			table.remove(samples, 1)
		end

		local avg = 0
		for _, a in samples do
			avg += a
		end
		avg = avg / #samples
		S.WheelSpeeds[data.Name] = avg

		if data.driven then
			S.DriveWheelSpeed = S.DriveWheelSpeed + avg
			driveCount = driveCount + 1
			if avg > S.MaxWheelSpin then
				S.MaxWheelSpin = avg
			end
		end

		-- Output wheel speeds
		data.WheelSpeedValue.Value = avg
		rot += avg * (data.Size.Y / 2)

		-- TCS
		if S.TCSTracker[data.Name] then
			data.TCSTrackerValue.Value = S.TCSTracker[data.Name]
			S.TCSAmt += S.TCSTracker[data.Name]
			tcsCount += 1
		end

		-- ABS
		if S.ABSTracker[data.Name] then
			data.ABSTrackerValue.Value = S.ABSTracker[data.Name]
			S.ABSAmt += S.ABSTracker[data.Name]
			absCount += 1
		end

		-- ESC
		if S.ESCTracker[data.Name] then
			data.ESCTrackerValue.Value = S.ESCTracker[data.Name]
			S.ESCAmt += math.abs(S.ESCTracker[data.Name])
			escCount += 1
		end
	end

	S.DriveWheelSpeed = S.DriveWheelSpeed / driveCount

	-- Wheel speeds
	S.AvgWheelSpeed = rot / count
	-- TCS
	S.TCSAmt = S.TCSAmt / tcsCount
	S.TCSActive = false
	-- ABS
	S.ABSAmt = S.ABSAmt / absCount
	S.ABSActive = false
	-- ESC
	S.ESCAmt = S.ESCAmt / escCount
	S.ESCActive = false
end

return WheelModule
