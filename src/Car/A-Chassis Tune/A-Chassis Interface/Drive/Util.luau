local Util = {}

function Util.SampleCurve(curve: { { number } }, x: number): number
	for i = 2, #curve do
		local a = curve[i - 1]
		local b = curve[i]

		if x <= b[1] then
			local t = (x - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * math.clamp(t, 0, 1)
		end
	end

	return curve[#curve][2]
end

function Util.MoveToward(current: number, target: number, step: number): number
	if current < target then
		return math.min(current + step, target)
	elseif current > target then
		return math.max(current - step, target)
	end

	return target
end

function Util.StepForTime(dt: number, time: number, range: number?): number
	local span = range or 1

	if time <= 0 then
		return span
	end

	return span * dt / time
end

-- Torque curve shape (Detomiks, ported from the Desmos tuning graph)
function Util.f(m: number, n: number, p: number, q: number, M: number, b: number, x: number): number
	return math.clamp(M - ((q - n) / (b ^ p - b ^ m) * (b ^ x - b ^ m) + n), 0, M)
end

-- Naturally aspirated torque (lb-ft) at x = RPM / 1000, before air pressure and the engine-off fade.
-- Shared by the Engine and the live tuner's graph so both draw the same curve.
function Util.naturalTorque(Tune, x: number): number
	local f = Util.f
	local NIdleTorque = f(
		Tune.IdleRPM / 1000,
		Tune.IdleTorque,
		Tune.PeakTorqueRPM / 1000,
		Tune.PeakTorque,
		Tune.PeakTorque,
		Tune.IdleTorqueCurve,
		x
	)
	local NRedlineTorque = f(
		Tune.PeakTorqueRPM / 1000,
		Tune.PeakTorque,
		Tune.Redline / 1000,
		Tune.RedlineTorque,
		Tune.PeakTorque,
		1 / Tune.RedlineTorqueCurve,
		x
	)
	local VVL = Tune.VVLTorque > 0
			and Tune.VVLTorque - f(
				Tune.VVLRPM / 1000,
				0,
				(Tune.VVLRPM + Tune.VVLTime) / 1000,
				Tune.VVLTorque,
				Tune.VVLTorque,
				Tune.VVLCurve,
				x
			)
		or 0
	return Tune.PeakTorque - NIdleTorque - NRedlineTorque + VVL
end

-- Electric motor torque (lb-ft) at x = RPM / 1000
function Util.electricTorque(Tune, x: number): number
	return 1
		* (
			Tune.E_Torque
			- Util.f(
				Tune.E_TransitionRPM / 1000,
				Tune.E_Torque,
				Tune.E_Redline / 1000,
				Tune.E_RedlineTorque,
				Tune.E_Torque,
				Tune.E_Curve,
				x
			)
		)
end

return Util
