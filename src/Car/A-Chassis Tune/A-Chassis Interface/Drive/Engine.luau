local S = require(script.Parent.State)
local Util = require(script.Parent.Util)

local MoveToward, StepForTime = Util.MoveToward, Util.StepForTime
local Tune, Units = S.Tune, S.Units
local ParkingGearEnabled, ParkingGearOffset = S.ParkingGearEnabled, S.ParkingGearOffset
local EngineModule = S.EngineModule

local Engine = {}

local goalRPM = 0

-- Power calculation prerequesites
local f = Util.f

-- Apply Power
function Engine.step(dt: number)
	local deltaTime = dt * 60

	local fFDr = Tune.FinalDrive * 30 / math.pi
	local cGrav = (Tune.GravComp > 0 and Tune.GravComp or workspace.Gravity) * Tune.InclineComp / 35

	local _WheelRPM = S.DriveWheelSpeed * S.CurrentRatio * fFDr

	local speedKmh = S.Velocity.Magnitude / (Units.Velocity_mdivs / 3.6)

	-- Pedal smoothing
	S.InThrot = MoveToward(S.InThrot, S.IThrot, StepForTime(dt, Tune.ThrotTime))
	S.InBrake = MoveToward(S.InBrake, S.IBrake, StepForTime(dt, Tune.BrakeTime))

	-- CVT
	if Tune.ClutchType == "CVT" then
		local denom = S.DriveWheelSpeed * fFDr
		local targetRPM = Tune.IdleRPM + (Tune.CVTRPM - Tune.IdleRPM) * S.GThrot
		if math.abs(denom) > 1e-6 then
			S.CVTRatio = math.clamp(targetRPM / denom, Tune.CVTMinRatio, Tune.CVTMaxRatio)
		else
			S.CVTRatio = Tune.CVTMaxRatio
		end
	end

	-- Update ratio
	S.CurrentRatio = Tune.ClutchType == "CVT" and S.CVTRatio or Tune.Ratios[S.CGear + 2 + ParkingGearOffset]
	S.spLimit = Tune.Redline / (fFDr * S.CurrentRatio)
	if S.CurrentRatio * fFDr == 0 then
		S.spLimit = 0
	end -- Prevents [nan] from dividing by 0

	-- Flywheel/clutch-dumping
	S.FlywheelEnergy = math.max((S.RPM - _WheelRPM) * Tune.DumpMult, 0) * (1 - S.Clutch) * 1.356 * Units.Torque_nm

	-- Throttle
	if S.Shifting and S.ShiftUp then
		S.GThrot = 0
	elseif S.Shifting and S.ShiftDn then
		S.GThrot = Tune.ShiftDnThrottle / 100
	elseif Tune.AutoShiftVers == "Old" and S.CGear == -1 and S.TMode == "Auto" then
		S.GThrot = S.InBrake
	else
		S.GThrot = S.InThrot
	end

	-- Brake
	if Tune.AutoShiftVers == "Old" and S.CGear == -1 and S.TMode == "Auto" then
		S.GBrake = S.InThrot
	else
		S.GBrake = S.InBrake
	end

	if not S.IsOn then
		S.StallTimer = 0
		if S.AutoClutch then
			S.Clutch = 1
		end
		S.GThrot = 0
	end

	-- Rev limiter
	S.RevCutTimer = math.max(S.RevCutTimer - dt, 0)

	if not S.IsOn then
		S.RevCutTimer = 0
	elseif S.RPM >= Tune.Redline and S.RevCutTimer <= 0 then
		S.RevCutTimer = Tune.RedlineThrottleCutTime or 0.08
	end

	S.RevLimiting = S.RevCutTimer > 0

	if S.RevLimiting then
		S.GThrot = 0
	end

	-- Speed limiter
	local limit = (S.CGear < 0 and Tune.ReverseSpeed or Tune.SpeedLimit)
	if limit > 0 then
		local cut = 1 - math.clamp((speedKmh - (limit - Tune.SLimitGradient)) / Tune.SLimitGradient, 0, 1)
		S.GThrot = math.min(S.GThrot, cut)

		if Tune.SLimitBrake then
			S.GBrake = math.max(S.GBrake, math.clamp((speedKmh - limit) / Tune.SLimitGradient, 0, 1))
		end
	end

	-- Idler circuit
	local rpmThrottle = S.GThrot
	if S.IsOn and Tune.Engine then
		local idleTarget = Tune.IdleRPM + (math.random() * 2 - 1) * (Tune.IdleInstability or 0)
		local idleThrottle = math.clamp((idleTarget - S.RPM) / math.max(Tune.IdleRPM * 0.5, 1), 0, 0.45)
		rpmThrottle = math.max(rpmThrottle, idleThrottle)
	end

	if (Tune.Engine or Tune.Electric) and not S.Starting then
		goalRPM = math.clamp(
			S.RPM
				- (Tune.RevDecay * deltaTime)
				+ (Tune.RevAccel * rpmThrottle * deltaTime)
				- (
					math.clamp(math.max(S.RPM - Tune.IdleRPM, 0) / math.max(Tune.Redline - Tune.IdleRPM, 1), 0, 1)
					* Tune.RevDecayRPM
					* deltaTime
				),
			0,
			Tune.Redline
		)
	end

	-- Set RPM
	local aRPM = math.max((goalRPM * (1 - deltaTime) + _WheelRPM * deltaTime) * (1 - S.Clutch) + goalRPM * S.Clutch, 0)
	local clutchP = math.min(math.abs(aRPM - S.RPM) / (Tune.Flywheel * deltaTime), 0.9)
	if S.ClPressing then
		clutchP = 0
	end
	S.RPM = aRPM * (1 - clutchP) + S.RPM * clutchP

	if S.RPM > Tune.Redline then
		S.RPM = Tune.Redline
	end

	-- Clutch
	if S.Shifting or (S.CGear == 0 or (ParkingGearEnabled and S.CGear == -2)) then
		S.ClPressing = true
		S.Clutch = 1
	end

	if Tune.Clutch then
		if S.AutoClutch then
			if Tune.ClutchType == "Clutch" or Tune.ClutchType == "CVT" then
				S.ClutchKick = S.ClPressing and 1 or MoveToward(S.ClutchKick, 0, StepForTime(dt, Tune.ClutchTime))

				local speedInfluence = speedKmh / math.max(Tune.SpeedEngage, 0.001) -- / math.max(math.abs(S.CGear), 1)
				S.ClutchModulate = math.clamp(speedInfluence - S.ClutchKick, 0, 1)
			elseif Tune.ClutchType == "TorqueConverter" and Tune.TQLock then
				local offThrottleUnlock = S.GThrot <= 0.01 and speedKmh < Tune.SpeedEngage
				local onThrottleUnlock = S.GThrot > 0.01 and S.RPM < Tune.RPMEngage and _WheelRPM < Tune.RPMEngage

				local targetModulate = (offThrottleUnlock or onThrottleUnlock) and 0 or 1
				S.ClutchModulate = MoveToward(S.ClutchModulate, targetModulate, StepForTime(dt, Tune.ClutchTime))
			elseif Tune.ClutchType == "TorqueConverter" and not Tune.TQLock then
				S.ClutchModulate = math.min((S.RPM / Tune.Redline) * 0.7, 1)
			end

			S.Clutch = S.ClPressing and 1 or 1 - S.ClutchModulate
		else
			S.Clutch = S.ClPressing and 1 or 0
		end
	else
		S.Clutch = (not S.ClPressing and not S.Shifting) and 0 or 1
	end

	if S.AutoClutch and (S.Starting or S.RevLimiting) then
		S.Clutch = 1
	end

	local canStall = Tune.Stall
		and Tune.Clutch
		and Tune.Engine
		and S.IsOn
		and not S.Starting
		and S.Clutch <= 0.01
		and S.RPM <= Tune.IdleRPM * 0.25
	if canStall then
		S.StallTimer += dt
		if S.StallTimer >= 0.2 then
			S.IsOnValue.Value = false
			S.StallTimer = 0
		end
	else
		S.StallTimer = 0
	end

	-- Torque calculations (Detomiks)
	-- What you see here is mostly just ported over from Desmos.
	if not EngineModule or Tune.CustomEngineCalculations == false then
		local x = S.RPM / 1000
		local NTorque = 0
		local ETorque = 0
		local TTorque = 0
		local STorque = 0
		if Tune.Engine then
			local AirPressurePercent = math.exp(
				(-9.80665 * 0.0289644 * (S.Center.Y * Units.Length_mm / 1000))
					/ (8.3142 * (S.GlobalTemperature + 273.15))
			) -- look up the barometric formula
			NTorque = Util.naturalTorque(Tune, x) * AirPressurePercent * (math.clamp(x / (Tune.IdleRPM / 1000), 0, 1)) -- fix to torque produced when engine off
			S.NH, S.NT = (NTorque * x) / 5.252, NTorque

			if Tune.Turbochargers > 0 then
				local turboMaxBoost = Tune.Turbochargers * Tune.T_Boost
				local turboBoostGoal = Tune.Turbochargers
					* (
						(S.GThrot ^ 3) * (100 / Tune.T_Size) * ((NTorque * x) / 5.252)
						- f(
							Tune.IdleRPM / 1000,
							Tune.T_IdleBoost,
							Tune.T_PeakRPM / 1000,
							Tune.T_Boost,
							(S.GThrot ^ 3) * (100 / Tune.T_Size) * ((NTorque * x) / 5.252),
							1 / Tune.T_Curve,
							x
						)
					)
				turboBoostGoal = math.clamp(turboBoostGoal, 0, turboMaxBoost)

				local spoolTime = turboBoostGoal > S.TBoost and Tune.T_SpoolUpTime or Tune.T_SpoolDownTime
				S.TBoost = MoveToward(S.TBoost, turboBoostGoal, StepForTime(dt, spoolTime, turboMaxBoost))

				TTorque = S.TBoost * Tune.T_Efficiency
				S.TH, S.TT = (TTorque * x) / 5.252, TTorque
			end

			if Tune.Superchargers > 0 then
				local SIdleBoost = f(
					Tune.IdleRPM / 1000,
					Tune.S_IdleBoost,
					Tune.S_PeakRPM / 1000,
					Tune.S_Boost,
					Tune.S_Boost,
					Tune.S_IdleCurve,
					x
				)
				local SRedlineBoost = f(
					Tune.S_PeakRPM / 1000,
					Tune.S_Boost,
					Tune.Redline / 1000,
					Tune.S_RedlineBoost,
					Tune.S_Boost,
					1 / Tune.S_RedlineCurve,
					x
				)

				local superMaxBoost = Tune.Superchargers * Tune.S_Boost
				local superBoostGoal = Tune.Superchargers * S.GThrot * (Tune.S_Boost - SIdleBoost - SRedlineBoost)
				superBoostGoal = math.clamp(superBoostGoal, 0, superMaxBoost)

				S.SBoost = MoveToward(S.SBoost, superBoostGoal, StepForTime(dt, Tune.S_ResponseTime, superMaxBoost))

				STorque = S.SBoost * Tune.S_Efficiency
				S.SH, S.ST = (STorque * x) / 5.252, STorque
			end

			if Tune.Turbochargers > 0 or Tune.Superchargers > 0 then
				S.BH, S.BT = ((TTorque + STorque) * x) / 5.252, TTorque + STorque
			end
		end

		if Tune.Electric then
			ETorque = Util.electricTorque(Tune, x)
			S.EH, S.ET = (ETorque * x) / 5.252, ETorque
		end

		local minTorque = (S.IsOn and S.RPM >= Tune.IdleRPM * 0.75) and Tune.IdleTorque or 0
		local maxTorque = (Tune.HPLimit > 0 and Tune.HPLimit or math.huge) * (5.252 / math.max(x, 0.001))

		local TotalTorque = math.clamp(NTorque + ETorque + TTorque + STorque, minTorque, maxTorque)
		S.HP, S.TQ = (TotalTorque * x) / 5.252, TotalTorque
	else
		EngineModule.run({
			-- Manually add environment variables here
			_RPM = S.RPM,
			_GThrot = S.GThrot,
			_IsOn = S.IsOn,
			_CGear = S.CGear,
		}, dt)

		-- the CustomEngine contract keeps A-Chassis's _Name fields
		for _, key in
			{ "Boost", "TBoost", "SBoost", "HP", "TQ", "NH", "NT", "EH", "ET", "TH", "TT", "SH", "ST", "BH", "BT" }
		do
			S[key] = EngineModule["_" .. key]
		end
	end

	-- Starter
	if S.Starting then
		S.IsOnValue.Value = true
		S.TQ += Tune.StarterTorque or 120
	end

	-- Exit engine
	S.OutTorque = S.TQ * S.CurrentRatio * Tune.FinalDrive
	local iComp = S.Center.LookVector.Y * cGrav * math.sign(S.CGear)
	S.OutTorque = S.OutTorque * math.max(1, (1 + iComp))
end

return Engine
