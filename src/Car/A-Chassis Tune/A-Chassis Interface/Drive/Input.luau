-- Input Action System bindings: analog actions are polled each step, buttons fire on press/release.
local S = require(script.Parent.State)
local Flip = require(script.Parent.Flip)

local Tune = S.Tune
local VehicleContext = S.VehicleContext
local camera = workspace.CurrentCamera :: Camera

local ThrottleAction = VehicleContext.ThrottleAction :: InputAction
local BrakeAction = VehicleContext.BrakeAction :: InputAction
local SteerAction = VehicleContext.SteerAction :: InputAction
local ViewportAction = VehicleContext.ViewportAction :: InputAction

-- Inputs
local VehicleActions = {
	ThrottleAction = {
		Step = function(action: InputAction)
			local throttle = action:GetState() :: number
			S.IThrot = math.clamp(throttle, 0, 1)
		end,
	},

	BrakeAction = {
		Step = function(action: InputAction)
			local brake = action:GetState() :: number
			S.IBrake = math.clamp(brake, 0, 1)
		end,
	},

	SteerAction = {
		Step = function(action: InputAction)
			if S.MSteer then
				return
			end

			local steer = action:GetState() :: number
			S.GSteerT = math.clamp(steer, -1, 1)
		end,
	},

	ViewportAction = { -- Used to get mouse position on viewport for mouse steering
		Step = function(action: InputAction)
			if not S.MSteer then
				return
			end

			local position = action:GetState() :: Vector2
			local viewportSize = camera.ViewportSize

			local halfWidth = viewportSize.X / 2
			local limitPercent = math.clamp(Tune.MouseSteerLimit, 1, 100)
			local limit = halfWidth * limitPercent / 100
			local deadzone = halfWidth * math.clamp(Tune.MouseSteerDeadzone, 0, limitPercent - 1) / 100
			local offset = position.X - halfWidth

			local steer = 0
			if math.abs(offset) > deadzone then
				steer = math.sign(offset) * (math.abs(offset) - deadzone) / (limit - deadzone)
			end

			S.GSteerT = math.clamp(steer, -1, 1)
		end,
	},

	MouseSteerAction = {
		Pressed = function()
			S.MouseSteerValue.Value = not S.MSteer
			S.GSteerT = 0
		end,
	},

	ShiftDownAction = {
		Pressed = function()
			if
				(S.IsOn and ((S.TMode == "Auto" and S.CGear <= 1) and Tune.AutoShiftVers == "New") or S.TMode == "Semi")
				or S.TMode == "Manual"
			then
				S.ShiftDn = true
			end
		end,
	},

	ShiftUpAction = {
		Pressed = function()
			if
				(S.IsOn and ((S.TMode == "Auto" and S.CGear < 1) and Tune.AutoShiftVers == "New") or S.TMode == "Semi")
				or S.TMode == "Manual"
			then
				S.ShiftUp = true
			end
		end,
	},

	ClutchAction = {
		Pressed = function()
			if S.TMode == "Manual" then
				S.ClPressing = true
				S.PlayerClutch = true
			end
		end,

		Released = function()
			S.ClPressing = false
			S.PlayerClutch = false
		end,
	},

	HandbrakeAction = {
		Pressed = function()
			S.PBrake = not S.PBrake
		end,

		Released = function()
			if S.Velocity.Magnitude > 5 then
				S.PBrake = false
			end
		end,
	},

	TransmissionAction = {
		Pressed = function()
			local index = table.find(Tune.TransModes, S.TMode) or 1
			S.TMode = Tune.TransModes[index % #Tune.TransModes + 1]
		end,
	},

	FlipAction = {
		Pressed = Flip.run,
	},

	ABSAction = {
		Pressed = function()
			if Tune.ABSEnabled and S.IsOn then
				S.ABS = not S.ABS
			end
		end,
	},

	ESCAction = {
		Pressed = function()
			if not (Tune.TCSEnabled and S.IsOn) then
				return
			end

			if not Tune.ESCEnabled then
				S.TCS = not S.TCS
				return
			end

			if S.TCS and S.ESC then
				S.ESC = false
			elseif S.TCS then
				S.TCS = false
			else
				S.TCS = true
				S.ESC = true
			end
		end,
	},

	CSAction = {
		Pressed = function()
			if Tune.CSEnabled and S.IsOn then
				S.CS = not S.CS
			end
		end,
	},

	IgnitionAction = {
		Pressed = function()
			if S.IsOnValue.Value then
				S.StartingValue.Value = false
				S.IsOnValue.Value = false
			else
				S.StartingValue.Value = true
			end
		end,

		Released = function()
			S.StartingValue.Value = false
		end,
	},
} :: { [string]: { [string]: (...any) -> () } }

for actionName, handlers in VehicleActions do
	local action = VehicleContext:FindFirstChild(actionName) :: InputAction
	if not action then
		continue
	end

	if handlers.Pressed then
		action.Pressed:Connect(handlers.Pressed)
	end

	if handlers.Released then
		action.Released:Connect(handlers.Released)
	end
end

local Input = {}

function Input.step()
	VehicleActions.ThrottleAction.Step(ThrottleAction)
	VehicleActions.BrakeAction.Step(BrakeAction)
	VehicleActions.SteerAction.Step(SteerAction)
	VehicleActions.ViewportAction.Step(ViewportAction)
end

return Input
