--[[
	   _____       _____ _                   _
	  / ____|     / ____| |                 (_)
	 | |   ______| |    | |__   __ _ ___ ___ _ ___
	 | |  |______| |    | '_ \ / _` / __/ __| / __|
	 | |____     | |____| | | | (_| \__ \__ \ \__ \
	  \_____|     \_____|_| |_|\__,_|___/___/_|___/

	Fork of B-Chassis 1.0.1 (itself a fork of A-Chassis 1.7.2). MPL-2.0.
	The drive loop lives in the sibling modules; this script fills State, then runs them in order.
--]]

-- Dependencies
local RunService = game:GetService("RunService")

local car = script.Parent.Car.Value
local values = script.Parent.Values

local Tune = require(car["A-Chassis Tune"]) :: { [string]: any }
local Units = require(car["A-Chassis Tune"].README.Units) :: { [string]: number }
local InterfaceValues = car["A-Chassis Tune"]["A-Chassis Interface"].Values

local ReadMe = car["A-Chassis Tune"].README

local S = require(script.State)

-- Electric Only Setup (before anything reads Redline or IdleRPM)
if not Tune.Engine and Tune.Electric then
	Tune.Redline = Tune.E_Redline
	Tune.ShiftRPM = Tune.E_Redline
	Tune.Turbochargers = 0
	Tune.Superchargers = 0
	Tune.Clutch = false
	Tune.IdleRPM = 0
	Tune.ClutchType = "Clutch"
end

S.Tune = Tune
S.Units = Units
S.Car = car
S.VehicleContext = script.Parent.VehicleContext :: InputContext
S.EngineModule = ReadMe:FindFirstChild("CustomEngine") and require(ReadMe:FindFirstChild("CustomEngine")) or nil
S.DifferentialModule = ReadMe:FindFirstChild("CustomDifferential")
		and require(ReadMe:FindFirstChild("CustomDifferential"))
	or nil

-- Connected variables
S.GlobalTemperature = workspace:GetAttribute("GlobalTemperature") or 22
workspace:GetAttributeChangedSignal("GlobalTemperature"):Connect(function()
	S.GlobalTemperature = workspace:GetAttribute("GlobalTemperature") or 22
end)

S.IsOn = Tune.AutoStart and (Tune.Engine or Tune.Electric)
S.IsOnValue = script.Parent.IsOn
S.IsOnValue.Value = S.IsOn
S.IsOnValue.Changed:Connect(function(value)
	S.IsOn = value
end)

S.Starting = false
S.StartingValue = S.IsOnValue.Starting
S.StartingValue.Value = S.Starting
S.StartingValue.Changed:Connect(function(value)
	S.Starting = value
end)

S.AutoClutch = true
local AutoClutchValue = values.AutoClutch
AutoClutchValue.Value = S.AutoClutch
AutoClutchValue.Changed:Connect(function(value)
	S.AutoClutch = value
end)

S.MSteer = false
S.MouseSteerValue = values.MouseSteerOn
S.MouseSteerValue.Value = S.MSteer
S.MouseSteerValue.Changed:Connect(function(value)
	S.MSteer = value
end)

-- Local variables
S.ParkingGearEnabled = Tune.Ratios[1] == 0
S.ParkingGearOffset = S.ParkingGearEnabled and 1 or 0

S.GSteerT = 0
S.GSteerC = 0

S.GThrot = 0
S.InThrot = 0
S.IThrot = 0
S.GBrake = 0
S.InBrake = 0
S.IBrake = 0

S.ClPressing = false
S.PlayerClutch = false
S.Clutch = 0
S.ClutchKick = 0
S.ClutchModulate = 0

S.RPM = Tune.AutoStart and Tune.IdleRPM or 0
S.OutTorque = 0
S.CGear = S.ParkingGearOffset == 1 and -2 or 0
S.ShiftUp = false
S.ShiftDn = false
S.Shifting = false
S.StallTimer = 0
S.spLimit = 0

S.Boost = 0
S.TBoost = 0
S.SBoost = 0

S.HP = 0
S.TQ = 0
S.NH = 0
S.NT = 0
S.EH = 0
S.ET = 0
S.TH = 0
S.TT = 0
S.SH = 0
S.ST = 0
S.BH = 0
S.BT = 0

S.CurrentRatio = Tune.Ratios[S.CGear + 2 + S.ParkingGearOffset]
S.CVTRatio = 0
S.FlywheelEnergy = 0

S.TMode = Tune.TransModes[1]
S.RevLimiting = false
S.RevCutTimer = 0

S.PBrake = InterfaceValues.PBrake.Value

S.TCSTracker = {}
S.TCS = Tune.TCSEnabled and InterfaceValues.TCS.Value or false
S.TCSActive = false
S.TCSAmt = 0

S.ABSTracker = {}
S.ABS = Tune.ABSEnabled and InterfaceValues.ABS.Value or false
S.ABSActive = false
S.ABSAmt = 0

S.ESCTracker = {}
S.ESC = (Tune.ESCEnabled and Tune.TCSEnabled) and InterfaceValues.ESC.Value or false
S.ESCActive = false
S.ESCAmt = 0

S.CS = Tune.CSEnabled and InterfaceValues.CS.Value or false
S.CSActive = false
S.CSAmt = 0

S.WheelSpeedsTable = {}
S.WheelSpeeds = {}

S.AvgWheelSpeed = 0
S.DriveWheelSpeed = 0
S.MaxWheelSpin = 0

S.OldVelocity = Vector3.new()
S.Acceleration = Vector3.new()
S.Velocity = Vector3.new()
S.Center = CFrame.new()
S.Wheelbase = 1

S.FlipWait = os.clock()
S.FlipActive = false

S.WeightBrick = car.Body["#Weight"] :: Part
S.DriveSeat = car.DriveSeat :: VehicleSeat
S.FlipAlignOrientation = S.DriveSeat.Flip :: AlignOrientation

-- Wheels
local TCSTrackerFolder = values.TCSTracker
local ABSTrackerFolder = values.ABSTracker
local ESCTrackerFolder = values.ESCTracker
local WheelSpeedsFolder = values.WheelSpeeds

S.FWheelCount = 0
S.RWheelCount = 0

S.wDia = 0
S.wDRatio = 0

local Wheels = {}
local Drive = {}
S.Wheels = Wheels
S.Drive = Drive

for _, v in car.Wheels:GetChildren() :: { BasePart } do
	local name = v.Name
	if not v:IsA("BasePart") or not (name == "FL" or name == "FR" or name == "RL" or name == "RR") then
		continue
	end

	local av = v:WaitForChild("#AV") :: HingeConstraint
	local bv = v:WaitForChild("#BV") :: HingeConstraint

	local base = v:FindFirstChild("Base")
	local arm = v:FindFirstChild("Arm")

	local steer = arm and arm:FindFirstChild("Steer") or nil
	local steerAttach0 = steer and steer.Attachment0 or nil

	S.FWheelCount += string.find(name, "F") and 1 or 0
	S.RWheelCount += (not string.find(name, "F")) and 1 or 0

	local isFront = string.find(name, "F") ~= nil
	local driven = ((Tune.Config == "FWD" or Tune.Config == "AWD") and isFront)
		or ((Tune.Config == "RWD" or Tune.Config == "AWD") and not isFront)

	local canSteer = 0
	if arm and steer then
		canSteer = v:GetAttribute("SteerDisabled") and 1 or 2
	end

	local WheelSpeedValue = Instance.new("NumberValue", WheelSpeedsFolder)
	WheelSpeedValue.Name = name
	local TCSTrackerValue = Instance.new("NumberValue", TCSTrackerFolder)
	TCSTrackerValue.Name = name
	local ABSTrackerValue = Instance.new("NumberValue", ABSTrackerFolder)
	ABSTrackerValue.Name = name
	local ESCTrackerValue = Instance.new("NumberValue", ESCTrackerFolder)
	ESCTrackerValue.Name = name

	local data = {}
	data.Name = name
	data.OppositeWheel = (name == "FL" and car.Wheels:FindFirstChild("FR"))
		or (name == "FR" and car.Wheels:FindFirstChild("FL"))
		or (name == "RL" and car.Wheels:FindFirstChild("RR"))
		or (name == "RR" and car.Wheels:FindFirstChild("RL"))
	data.Size = v.Size
	data.Base = base
	data.Arm = arm
	data.Steer = steer
	data.SteerAttach0 = steerAttach0
	data.AV = av
	data.BV = bv
	data.isFront = isFront
	data.driven = driven
	data.WheelSpeedValue = WheelSpeedValue
	data.TCSTrackerValue = TCSTrackerValue
	data.ABSTrackerValue = ABSTrackerValue
	data.ESCTrackerValue = ESCTrackerValue
	data.RotVelocityMagnitude = 0
	data.WheelVelocityMagnitude = 0
	data.CanSteer = canSteer

	if driven then
		table.insert(Drive, v)
	end

	v:GetPropertyChangedSignal("Size"):Connect(function()
		Wheels[v].Size = v.Size

		local size = 0
		for _, other in Wheels do
			size = math.max(size, other.Size.Y)
			S.wDia = size
		end

		S.wDRatio = S.wDia * math.pi / 60
	end)

	v:GetAttributeChangedSignal("SteerDisabled"):Connect(function()
		data.CanSteer = v:GetAttribute("SteerDisabled") and 1 or 2
	end)

	Wheels[v] = data
end

for _, data in Wheels do
	S.wDia = math.max(S.wDia, data.Size.Y)
	S.wDRatio = S.wDia * math.pi / 60
end

-- Modules read State at require time, so they load only after it is filled.
local Steering = require(script.Steering)
local Gearbox = require(script.Gearbox)
local Engine = require(script.Engine)
local WheelModule = require(script.Wheels)
local Flip = require(script.Flip)
local Input = require(script.Input)
local Publish = require(script.Publish)

-- Shutdown
S.DriveSeat.ChildRemoved:Connect(function(child: Instance)
	if child.Name == "SeatWeld" and child:IsA("Weld") then
		-- Remove Flip Force
		S.FlipAlignOrientation.Enabled = false
		S.FlipActive = false

		-- Save assist states
		InterfaceValues.PBrake.Value = S.PBrake
		InterfaceValues.TCS.Value = S.TCS
		InterfaceValues.ABS.Value = S.ABS
		InterfaceValues.ESC.Value = S.ESC
		InterfaceValues.CS.Value = S.CS

		-- Remove wheel force
		for _, data in Wheels do
			if data.AV then
				data.AV.MotorMaxTorque = 0
				data.AV.AngularVelocity = 0
			end
			if data.BV then
				if S.ParkingGearEnabled then
					S.CGear = -2
				else
					S.PBrake = true
				end

				if data.isFront then
					local PBrakeForceF = Tune.PBrakeForce * 9.80665 * Units.Force_N * Tune.PBrakeBias
					data.BV.MotorMaxTorque = Tune.ExitBrake and PBrakeForceF or 0
				else
					local PBrakeForceR = Tune.PBrakeForce * 9.80665 * Units.Force_N * (1 - Tune.PBrakeBias)
					data.BV.MotorMaxTorque = Tune.ExitBrake and PBrakeForceR or 0
				end
			end
		end

		-- Tell server to remove
		car["A-Chassis Tune"].Shutdown:FireServer()
	end
end)

-- In case of car death
S.DriveSeat.AncestryChanged:Connect(function()
	if S.DriveSeat.Parent then
		return
	end
	task.wait(10)
	script.Parent:Destroy()
end)

-- Runtime Loops
local function RuntimeLoop(deltaTime: number)
	-- Update Internal Values
	S.Velocity = S.WeightBrick.AssemblyLinearVelocity
	S.Acceleration = (S.Velocity - S.OldVelocity) / deltaTime
	S.OldVelocity = S.Velocity
	S.Center = WheelModule.center()

	Input.step()
	Publish.step()

	WheelModule.sense(deltaTime)
	Steering.step(deltaTime)

	-- Shifting can wait out ShiftUpTime/ShiftDnTime, so it runs on its own thread instead of stalling the step.
	if (S.ShiftUp or S.ShiftDn) and not S.Shifting then
		task.spawn(Gearbox.shift)
	end

	Engine.step(deltaTime)
	WheelModule.apply(deltaTime)
end

RunService:BindToSimulation(RuntimeLoop, Enum.StepFrequency.Hz60)

local function SlowRuntimeLoop()
	if S.TMode == "Auto" then
		Gearbox.auto()
	end

	if Tune.AutoFlip then
		Flip.auto()
	end
end

RunService:BindToSimulation(SlowRuntimeLoop, Enum.StepFrequency.Hz5)

script:SetAttribute("Loaded", true)
