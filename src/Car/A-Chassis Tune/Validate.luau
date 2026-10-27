-- Fails fast on a Tune that cannot drive, with every problem listed at once.
-- Runs wherever the Tune is required (server Initialize and the driver's client), so both see the same error.
local function oneOf(list: { string }, value: any): boolean
	return table.find(list, value) ~= nil
end

local function check(Tune): { string }
	local problems = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end
	local function range(key: string, lo: number, hi: number)
		local v = Tune[key]
		expect(type(v) == "number" and v >= lo and v <= hi, `{key} must be between {lo} and {hi} (is {v})`)
	end
	local function positive(key: string)
		local v = Tune[key]
		expect(type(v) == "number" and v > 0, `{key} must be above 0 (is {v})`)
	end
	local function curve(key: string)
		local points = Tune[key]
		local ok = type(points) == "table" and #points >= 2
		if ok then
			for i = 2, #points do
				ok = ok and points[i][1] > points[i - 1][1]
			end
		end
		expect(ok, `{key} needs at least 2 points with strictly increasing first values`)
	end

	-- Choices
	expect(oneOf({ "FWD", "RWD", "AWD" }, Tune.Config), `Config must be "FWD", "RWD" or "AWD" (is {Tune.Config})`)
	expect(
		oneOf({ "Clutch", "TorqueConverter", "CVT" }, Tune.ClutchType),
		`ClutchType must be "Clutch", "TorqueConverter" or "CVT" (is {Tune.ClutchType})`
	)
	expect(
		oneOf({ "None", "Static", "Speed", "Both" }, Tune.FWSteer),
		`FWSteer must be "None", "Static", "Speed" or "Both" (is {Tune.FWSteer})`
	)
	expect(oneOf({ "Speed", "RPM" }, Tune.AutoShiftMode), `AutoShiftMode must be "Speed" or "RPM"`)
	expect(oneOf({ "New", "Old" }, Tune.AutoShiftVers), `AutoShiftVers must be "New" or "Old"`)
	local modesOk = type(Tune.TransModes) == "table" and #Tune.TransModes > 0
	for _, mode in Tune.TransModes or {} do
		modesOk = modesOk and oneOf({ "Auto", "Semi", "Manual" }, mode)
	end
	expect(modesOk, `TransModes must list one or more of "Auto", "Semi", "Manual"`)

	-- Power
	expect(Tune.Engine or Tune.Electric, "Engine or Electric must be true")
	if Tune.Engine then
		expect(
			Tune.IdleRPM > 0 and Tune.IdleRPM < Tune.PeakTorqueRPM and Tune.PeakTorqueRPM < Tune.Redline,
			`RPMs must rise IdleRPM < PeakTorqueRPM < Redline (are {Tune.IdleRPM}, {Tune.PeakTorqueRPM}, {Tune.Redline})`
		)
		expect(
			Tune.ShiftRPM > Tune.IdleRPM and Tune.ShiftRPM <= Tune.Redline,
			`ShiftRPM must sit between IdleRPM and Redline (is {Tune.ShiftRPM})`
		)
		positive("Flywheel")
	end
	if Tune.Electric then
		expect(Tune.E_TransitionRPM < Tune.E_Redline, "E_TransitionRPM must be below E_Redline")
	end

	-- Gearing: [Park], Reverse, Neutral (0), then forward gears
	positive("FinalDrive")
	local ratios = Tune.Ratios
	local park = ratios[1] == 0 and 1 or 0
	expect(#ratios >= 3 + park, "Ratios needs Reverse, Neutral and at least one forward gear")
	expect(ratios[2 + park] == 0, "Neutral (the ratio after Reverse) must be 0")
	for i = 3 + park, #ratios do
		expect(ratios[i] > 0, `forward gear {i - 2 - park} ratio must be above 0`)
	end
	if Tune.ClutchType == "CVT" then
		expect(Tune.CVTMinRatio < Tune.CVTMaxRatio, "CVTMinRatio must be below CVTMaxRatio")
	end

	-- Chassis
	expect(
		Tune.Weight > 2 * (Tune.FWheelWeight + Tune.RWheelWeight),
		"Weight is the whole car, so it must exceed the four wheels' weight"
	)
	for _, axle in { "F", "R" } do
		local lo, free, hi = Tune[axle .. "SusMinLength"], Tune[axle .. "SusFreeLength"], Tune[axle .. "SusMaxLength"]
		expect(lo <= free and free <= hi, `{axle}Sus lengths must be Min <= Free <= Max (are {lo}, {free}, {hi})`)
	end
	range("MaxSteerAngle", 1, 80)
	range("BrakeBias", 0, 1)
	range("PBrakeBias", 0, 1)
	range("TorqueVector", -1, 1)
	for _, key in { "FDiffPower", "FDiffCoast", "RDiffPower", "RDiffCoast", "ESCBrake", "TCSLimit", "ABSLimit" } do
		range(key, 0, 100)
	end
	range("MouseSteerLimit", 1, 100)
	-- these divide slip or speed, so 0 would turn the assists into NaN
	for _, key in { "TCSGradient", "ABSGradient", "SLimitGradient" } do
		positive(key)
	end
	curve("SteerInputCurve")
	curve("MaxAngleCurve")

	return problems
end

local function validate(Tune)
	local problems = check(Tune)
	if #problems > 0 then
		error(`[C-Chassis] Tune has {#problems} problem(s):\n  - {table.concat(problems, "\n  - ")}`, 0)
	end
	return Tune
end

if game:GetService("RunService"):IsStudio() then
	local base = {
		Config = "AWD",
		ClutchType = "Clutch",
		FWSteer = "None",
		AutoShiftMode = "Speed",
		AutoShiftVers = "Old",
		TransModes = { "Auto" },
		Engine = true,
		IdleRPM = 1000,
		PeakTorqueRPM = 2500,
		Redline = 7500,
		ShiftRPM = 7000,
		Flywheel = 800,
		FinalDrive = 3.6,
		Ratios = { 3.18, 0, 3.9, 2.4 },
		Weight = 1440,
		FWheelWeight = 22,
		RWheelWeight = 23,
		FSusMinLength = 0.35,
		FSusFreeLength = 1.8,
		FSusMaxLength = 2.25,
		RSusMinLength = 0.35,
		RSusFreeLength = 1.8,
		RSusMaxLength = 2.25,
		MaxSteerAngle = 32,
		BrakeBias = 0.65,
		PBrakeBias = 0,
		TorqueVector = 0.35,
		FDiffPower = 20,
		FDiffCoast = 60,
		RDiffPower = 20,
		RDiffCoast = 60,
		ESCBrake = 60,
		TCSLimit = 4,
		ABSLimit = 0,
		MouseSteerLimit = 70,
		TCSGradient = 10,
		ABSGradient = 8,
		SLimitGradient = 2,
		SteerInputCurve = { { 0, 0 }, { 1, 1 } },
		MaxAngleCurve = { { 0, 1 }, { 100, 0.8 } },
	}
	assert(#check(base) == 0, "valid tune must pass: " .. table.concat(check(base), "; "))
	local broken = table.clone(base)
	broken.Config = "4WD"
	broken.ShiftRPM = 9000
	broken.Ratios = { 3.18, 1, 3.9 }
	assert(#check(broken) == 3, "Config, ShiftRPM and Neutral must each be caught")
end

return validate
