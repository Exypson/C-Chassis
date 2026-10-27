-- One-line driving styles. Tune.Preset = "Drift" overwrites only the keys listed here;
-- every other Tune value is still yours. Starting points tuned for the bundled sedan, not gospel.
local PRESETS = {
	Grip = {
		Config = "AWD",
		TorqueVector = 0.2,
		FSusStiffness = 2300,
		RSusStiffness = 2300,
		FSusDamping = 210,
		RSusDamping = 210,
		FCamber = -1.5,
		RCamber = -1,
		TCSEnabled = true,
		ESCEnabled = true,
		ABSEnabled = true,
		BrakeForce = 2400,
	},

	Drift = {
		Config = "RWD",
		MaxSteerAngle = 50,
		MaxAngleCurve = { { 0, 1 }, { 100, 0.85 }, { 200, 0.7 } },
		SteerTime = 0.3,
		ReturnTime = 0.25,
		CSEnabled = true,
		CSAmt = 100,
		TCSEnabled = false,
		ESCEnabled = false,
		RDiffPower = 85,
		RDiffCoast = 60,
		RDiffPreload = 10,
		FCamber = -3,
		FCaster = 6,
		BrakeBias = 0.6,
		PBrakeForce = 2500,
		PeakTorque = 430,
	},

	Offroad = {
		Config = "AWD",
		TorqueVector = 0,
		FSusStiffness = 1300,
		RSusStiffness = 1300,
		FSusDamping = 130,
		RSusDamping = 130,
		FSusFreeLength = 2.1,
		RSusFreeLength = 2.1,
		FinalDrive = 4.3,
		SpeedLimit = 150,
		FDiffPreload = 10,
		RDiffPreload = 10,
		FDiffPower = 60,
		RDiffPower = 60,
	},

	Truck = {
		Config = "RWD",
		Weight = 3000,
		CGHeight = 0.6,
		IdleRPM = 700,
		IdleTorque = 480,
		PeakTorque = 650,
		PeakTorqueRPM = 1800,
		Redline = 4400,
		ShiftRPM = 4100,
		RedlineTorque = 380,
		Turbochargers = 1,
		FinalDrive = 4.1,
		FSusStiffness = 3600,
		RSusStiffness = 3600,
		FSusDamping = 320,
		RSusDamping = 320,
		MaxSteerAngle = 36,
		BrakeForce = 4200,
		SpeedLimit = 170,
		Flywheel = 1400,
	},
}

local function applyPreset(Tune)
	local name = Tune.Preset
	if name == nil or name == "None" then
		return Tune
	end

	local preset = PRESETS[name]
	if not preset then
		local names = {}
		for key in PRESETS do
			table.insert(names, `"{key}"`)
		end
		table.sort(names)
		error(`[C-Chassis] unknown Tune.Preset "{name}"; use "None" or one of {table.concat(names, ", ")}`, 0)
	end

	for key, value in preset do
		Tune[key] = value
	end
	return Tune
end

return applyPreset
