-- Limited-slip differential (LuaInt): splits throttle and brake into one wheel's drive request.
local S = require(script.Parent.State)

local Tune = S.Tune
local DifferentialModule = S.DifferentialModule

local Differential = {}

function Differential.output(data, throt: number, brake: number, dt: number)
	local output = {
		Power = data.driven and throt or 0,
		Brake = brake,
		Torque = 1,
		Speed = data.driven and math.sign(S.CGear) or 0,
	}

	if not data.driven then
		return output
	end

	if data.OppositeWheel then
		local power = data.isFront and Tune.FDiffPower or Tune.RDiffPower
		local coast = data.isFront and Tune.FDiffCoast or Tune.RDiffCoast
		local preload = data.isFront and Tune.FDiffPreload or Tune.RDiffPreload

		local oppositeSpeed = math.max(data.OppositeWheel.RotVelocity.Magnitude, 0.001)
		local avg = ((data.RotVelocityMagnitude / oppositeSpeed) - 1) * (preload / 10)

		output.Torque = math.ceil(
			math.max(
				0,
				math.min(2, 1 - (((power / 100) * avg * output.Power) + ((coast / 100) * avg * (1 - output.Power))))
			) * 100
		) / 100
	end

	if DifferentialModule and Tune.CustomDifferentialCalculations ~= false then
		-- the CustomDifferential contract keeps A-Chassis's _Name fields
		output = DifferentialModule.run({
			_GThrot = output.Power,
			_GBrake = output.Brake,
			_GSteerC = S.GSteerC,
			_GSteerT = S.GSteerT,
			_CGear = S.CGear,
			_spLimit = S.spLimit,
			_Velocity = S.Velocity,
			_Config = Tune.Config,

			Wheel = data,
			Default = output,
		}, dt)
	end

	return output
end

return Differential
