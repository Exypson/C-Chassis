-- A-Chassis plugin compatibility: mirrors State into the Values folder plugins read.
-- Only changed values are written, so idle gauges cost nothing.
local S = require(script.Parent.State)

local values = script.Parent.Parent.Values

-- Value name -> State key
local MAP = {
	-- Transmission
	Clutch = "Clutch",
	Gear = "CGear",
	TransmissionMode = "TMode",
	CurrentRatio = "CurrentRatio",
	RPM = "RPM",
	-- Boost
	Boost = "Boost",
	BoostTurbo = "TBoost",
	BoostSuper = "SBoost",
	-- Horsepower
	HpNatural = "NH",
	HpElectric = "EH",
	HpTurbo = "TH",
	HpSuper = "SH",
	HpBoosted = "BH",
	Horsepower = "HP",
	-- Torque
	TqNatural = "NT",
	TqElectric = "ET",
	TqTurbo = "TT",
	TqSuper = "ST",
	TqBoosted = "BT",
	Torque = "TQ",
	-- Inputs
	Throttle = "GThrot",
	InputThrottle = "IThrot",
	Brake = "GBrake",
	InputBrake = "IBrake",
	SteerC = "GSteerC",
	SteerT = "GSteerT",
	PBrake = "PBrake",
	-- Velocity
	Velocity = "Velocity",
	AverageRotSpeed = "AvgWheelSpeed",
	Acceleration = "Acceleration",
	-- Misc
	Center = "Center",
	TCS = "TCS",
	TCSActive = "TCSActive",
	TCSAmt = "TCSAmt",
	ABS = "ABS",
	ABSActive = "ABSActive",
	ABSAmt = "ABSAmt",
	ESC = "ESC",
	ESCActive = "ESCActive",
	ESCAmt = "ESCAmt",
	CS = "CS",
	CSActive = "CSActive",
	CSAmt = "CSAmt",
}

local bindings = {}
for valueName, key in MAP do
	table.insert(bindings, { values[valueName], key })
end

local Publish = {}

function Publish.step()
	-- B-Chassis published Boost as turbo + super in the loop; keep that contract
	S.Boost = S.TBoost + S.SBoost

	for _, binding in bindings do
		local value, current = binding[1], S[binding[2]]
		if value.Value ~= current then
			value.Value = current
		end
	end
end

return Publish
