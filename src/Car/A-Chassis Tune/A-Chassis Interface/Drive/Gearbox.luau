local S = require(script.Parent.State)

local Tune = S.Tune
local ParkingGearEnabled, ParkingGearOffset = S.ParkingGearEnabled, S.ParkingGearOffset

local Gearbox = {}

-- Automatic Transmission
function Gearbox.auto()
	if not S.IsOn then
		return
	end

	local fFDr = Tune.FinalDrive * 30 / math.pi

	if Tune.AutoShiftVers == "Old" and (S.CGear == 0 or (ParkingGearEnabled and S.CGear == -2)) then
		S.ClPressing = false
		S.CGear = 1
	end

	if S.CGear >= 1 then
		if
			(S.CGear == 1 and S.InBrake > 0 and S.InThrot <= 0 and S.Velocity.Magnitude < 5)
			and Tune.AutoShiftVers == "Old"
		then
			S.CGear = -1
			S.ClPressing = false
		elseif S.Velocity.Magnitude > 5 and Tune.ClutchType ~= "CVT" then
			if Tune.AutoShiftMode == "RPM" then
				if S.RPM > (Tune.ShiftRPM + Tune.AutoUpThresh) then
					if not S.ShiftUp and not S.Shifting then
						S.ShiftUp = true
					end
				elseif
					math.max(
							math.min(
								S.MaxWheelSpin * Tune.Ratios[S.CGear + 1 + ParkingGearOffset] * fFDr,
								Tune.Redline + 100
							),
							0
						)
						< (Tune.ShiftRPM - Tune.AutoDownThresh)
					and S.CGear > 1
				then
					if not S.ShiftDn and not S.Shifting then
						S.ShiftDn = true
					end
				end
			else
				if
					S.Velocity.Magnitude
					> math.ceil(S.wDRatio * (Tune.ShiftRPM + Tune.AutoUpThresh) / S.CurrentRatio / Tune.FinalDrive)
				then
					if not S.ShiftUp and not S.Shifting then
						S.ShiftUp = true
					end
				elseif
					S.Velocity.Magnitude
						< math.ceil(
							S.wDRatio
								* (Tune.ShiftRPM - Tune.AutoDownThresh)
								/ Tune.Ratios[S.CGear + 1 + ParkingGearOffset]
								/ Tune.FinalDrive
						)
					and S.CGear > 1
				then
					if not S.ShiftDn and not S.Shifting then
						S.ShiftDn = true
					end
				end
			end
		end
	else
		if (S.InThrot > 0 and S.Velocity.Magnitude < 5) and Tune.AutoShiftVers == "Old" then
			S.ClPressing = false
			S.CGear = 1
		end
	end
end

function Gearbox.shift()
	if S.ShiftUp and not S.Shifting then
		if
			(S.TMode == "Manual" and not S.ClPressing)
			or (S.TMode == "Manual" and Tune.ClutchRel and (S.InThrot > 0))
			or S.CGear == #Tune.Ratios - 2 - ParkingGearOffset
			or (S.TMode ~= "Manual" and not S.IsOn)
		then
			S.ShiftUp = false
			return
		end
		local NextGear = math.min(S.CGear + 3 + ParkingGearOffset, #Tune.Ratios)
		if S.TMode ~= "Manual" and Tune.ClutchType ~= "CVT" then
			S.Shifting = true
			if S.CGear > 0 then
				task.wait(Tune.ShiftUpTime)
			end
		end
		S.ShiftUp = false
		S.Shifting = false
		if S.TMode ~= "Manual" and not S.IsOn then
			return
		end
		if NextGear > 3 + ParkingGearOffset and Tune.ClutchType == "CVT" then
			return
		end
		S.CGear = math.min(S.CGear + 1, #Tune.Ratios - 2 - ParkingGearOffset)
		if S.TMode ~= "Manual" or (S.CGear == 1 and S.IsOn) then
			S.ClPressing = (S.TMode == "Manual" and S.PlayerClutch) or false
		end
	end

	if S.ShiftDn and not S.Shifting then
		if
			(S.TMode == "Manual" and not S.ClPressing)
			or S.CGear == -1 - ParkingGearOffset
			or (S.TMode ~= "Manual" and not S.IsOn)
		then
			S.ShiftDn = false
			return
		end
		local PrevGear = math.min(S.CGear + 1 + ParkingGearOffset, #Tune.Ratios)
		if S.TMode ~= "Manual" then
			S.Shifting = true
			if S.CGear > 1 then
				task.wait(Tune.ShiftDnTime)
			end
		end
		S.ShiftDn = false
		S.Shifting = false
		if S.TMode ~= "Manual" and not S.IsOn then
			return
		end
		S.CGear = math.max(S.CGear - 1, S.Velocity.Magnitude > 5 and -1 or -2)
		if S.TMode ~= "Manual" or (S.CGear == -1 and S.IsOn) then
			S.ClPressing = (S.TMode == "Manual" and S.PlayerClutch) or false
		end
	end
end

return Gearbox
