-- C-Chassis live tuner: nudge Tune values while driving and watch the torque curve redraw.
-- Changes are local to this drive and lost on exit; "Print" writes the edited lines to the output (F9)
-- so they can be pasted into the Tune module. Gearing and speed limits are left out on purpose: the
-- server Watchdog judges top speed from the Tune it loaded, so raising them here would trip it.
local UserInputService = game:GetService("UserInputService")

local interface = script.Parent
local car = interface.Car.Value :: Model
local Tune = require(car["A-Chassis Tune"])
local Util = require(interface:WaitForChild("Drive", 10):WaitForChild("Util", 10))

local TOGGLE_KEY = Enum.KeyCode.T

local function springs(front: boolean): { SpringConstraint }
	local list = {}
	for _, wheel in car.Wheels:GetChildren() do
		local geometry = wheel:FindFirstChild("SuspensionGeometry")
		local spring = geometry and geometry:FindFirstChild("Spring")
		if spring and (string.find(wheel.Name, "F") ~= nil) == front then
			table.insert(list, spring)
		end
	end
	return list
end

-- Initialize applied these to constraints once; re-apply so the edit is felt immediately
local function setSprings(front: boolean, property: string)
	return function(value: number)
		for _, spring in springs(front) do
			(spring :: any)[property] = value
		end
	end
end

local FIELDS = {
	{ "Engine" },
	{ "PeakTorque", 10, 50, 2000 },
	{ "PeakTorqueRPM", 100, 1000, 9000 },
	{ "RedlineTorque", 10, 0, 2000 },
	{ "T_Boost", 1, 0, 40 },
	{ "Steering" },
	{
		"MaxSteerAngle",
		1,
		10,
		60,
		function(value: number)
			for _, wheel in car.Wheels:GetChildren() do
				local base = wheel:FindFirstChild("Base")
				local rotate = base and base:FindFirstChild("Rotate") :: HingeConstraint?
				if rotate and string.find(wheel.Name, "F") then
					rotate.UpperAngle = value + 5 -- Initialize's margin against physics shaking
					rotate.LowerAngle = -rotate.UpperAngle
				end
			end
		end,
	},
	{ "SteerTime", 0.05, 0, 2 },
	{ "ReturnTime", 0.05, 0, 2 },
	{ "CSAmt", 5, 0, 100 },
	{ "Suspension" },
	{ "FSusStiffness", 100, 200, 8000, setSprings(true, "Stiffness") },
	{ "RSusStiffness", 100, 200, 8000, setSprings(false, "Stiffness") },
	{ "FSusDamping", 10, 0, 800, setSprings(true, "Damping") },
	{ "RSusDamping", 10, 0, 800, setSprings(false, "Damping") },
	{ "Drivetrain" },
	{ "TorqueVector", 0.05, -1, 1 },
	{ "FDiffPower", 5, 0, 100 },
	{ "RDiffPower", 5, 0, 100 },
	{ "RDiffCoast", 5, 0, 100 },
	{ "Brakes" },
	{ "BrakeForce", 100, 200, 8000 },
	{ "BrakeBias", 0.05, 0, 1 },
	{ "PBrakeForce", 100, 0, 8000 },
}

local initial = {}
for _, field in FIELDS do
	if field[2] then
		initial[field[1]] = Tune[field[1]]
	end
end

-- UI ------------------------------------------------------------------------------

local BG = Color3.fromRGB(18, 20, 26)
local ROW = Color3.fromRGB(32, 35, 44)
local TEXT = Color3.fromRGB(235, 238, 245)
local DIM = Color3.fromRGB(150, 156, 170)
local TORQUE = Color3.fromRGB(255, 150, 60)
local POWER = Color3.fromRGB(70, 200, 255)
local FONT = Font.fromEnum(Enum.Font.GothamMedium)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = Color3.fromRGB(55, 60, 74)
	b.AutoButtonColor = true
	b.FontFace = FONT
	b.Text = text
	b.TextSize = 16
	b.TextColor3 = TEXT
	corner(b, 6)
	b.Parent = parent
	return b
end

local toggle = button(interface, "Tune  [T]", UDim2.fromOffset(96, 34))
toggle.Name = "C-Chassis Tuner Toggle"
toggle.AnchorPoint = Vector2.new(1, 0)
toggle.Position = UDim2.new(1, -16, 0, 16)
toggle.BackgroundColor3 = BG
toggle.BackgroundTransparency = 0.15

local panel = Instance.new("Frame")
panel.Name = "C-Chassis Tuner"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, 58)
panel.Size = UDim2.new(0, 300, 0.62, 0)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.1
panel.Visible = false
corner(panel, 10)
panel.Parent = interface
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(260, 260)
sizeLimit.MaxSize = Vector2.new(300, 560)
sizeLimit.Parent = panel
local padding = Instance.new("UIPadding")
for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
	(padding :: any)[side] = UDim.new(0, 10)
end
padding.Parent = panel

-- torque (orange) and horsepower (blue) against RPM, naturally aspirated + electric
local graph = Instance.new("Frame")
graph.Size = UDim2.new(1, 0, 0, 96)
graph.BackgroundColor3 = ROW
corner(graph, 6)
graph.Parent = panel
local peaks = label(panel, "", 12, DIM)
peaks.Position = UDim2.fromOffset(0, 100)
peaks.Size = UDim2.new(1, 0, 0, 16)

local POINTS = 56
local dots = {}
for i = 1, POINTS * 2 do
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(3, 3)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = i <= POINTS and TORQUE or POWER
	dot.Parent = graph
	dots[i] = dot
end

local function torqueAt(rpm: number): number
	local x = rpm / 1000
	local torque = 0
	if Tune.Engine then
		torque += Util.naturalTorque(Tune, x) * math.clamp(x / (Tune.IdleRPM / 1000), 0, 1)
	end
	if Tune.Electric then
		torque += Util.electricTorque(Tune, x)
	end
	return torque
end

local function redrawGraph()
	local lo, hi = Tune.IdleRPM, Tune.Redline
	local torques, powers = {}, {}
	local maxTq, maxHp, tqRpm, hpRpm = 1, 1, lo, lo
	for i = 1, POINTS do
		local rpm = lo + (hi - lo) * (i - 1) / (POINTS - 1)
		local tq = torqueAt(rpm)
		local hp = tq * rpm / 1000 / 5.252
		torques[i], powers[i] = tq, hp
		if tq > maxTq then
			maxTq, tqRpm = tq, rpm
		end
		if hp > maxHp then
			maxHp, hpRpm = hp, rpm
		end
	end
	local scale = math.max(maxTq, maxHp)
	for i = 1, POINTS do
		local x = (i - 1) / (POINTS - 1)
		dots[i].Position = UDim2.fromScale(0.03 + x * 0.94, 0.92 - torques[i] / scale * 0.84)
		dots[POINTS + i].Position = UDim2.fromScale(0.03 + x * 0.94, 0.92 - powers[i] / scale * 0.84)
	end
	peaks.Text = string.format(
		"%d lb-ft @ %d   ·   %d hp @ %d rpm (NA)",
		maxTq,
		math.floor(tqRpm / 100) * 100,
		maxHp,
		math.floor(hpRpm / 100) * 100
	)
end

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(0, 122)
list.Size = UDim2.new(1, 0, 1, -122 - 42)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function format(value: number): string
	return string.format("%g", math.floor(value * 1000 + 0.5) / 1000)
end

for order, field in FIELDS do
	local key, step, min, max, apply = field[1], field[2], field[3], field[4], field[5]
	if not step then
		local header = label(list, string.upper(key), 12, DIM)
		header.Size = UDim2.new(1, 0, 0, 22)
		header.TextYAlignment = Enum.TextYAlignment.Bottom
		header.LayoutOrder = order
		continue
	end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 36)
	row.BackgroundColor3 = ROW
	row.LayoutOrder = order
	corner(row, 6)
	row.Parent = list

	local name = label(row, key, 14, TEXT)
	name.Position = UDim2.fromOffset(10, 0)
	name.Size = UDim2.new(1, -160, 1, 0)
	local value = label(row, format(Tune[key]), 14, TORQUE)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -76, 0, 0)
	value.Size = UDim2.fromOffset(64, 36)
	value.TextXAlignment = Enum.TextXAlignment.Right

	local function nudge(direction: number)
		local new = math.clamp(Tune[key] + step * direction, min, max)
		Tune[key] = new
		value.Text = format(new)
		value.TextColor3 = new == initial[key] and TORQUE or POWER
		if apply then
			apply(new)
		end
		redrawGraph()
	end

	local minus = button(row, "−", UDim2.fromOffset(32, 30))
	minus.AnchorPoint = Vector2.new(1, 0.5)
	minus.Position = UDim2.new(1, -40, 0.5, 0)
	minus.Activated:Connect(function()
		nudge(-1)
	end)
	local plus = button(row, "+", UDim2.fromOffset(32, 30))
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.new(1, -4, 0.5, 0)
	plus.Activated:Connect(function()
		nudge(1)
	end)
end

local print_ = button(panel, "Print changes to output (F9)", UDim2.new(1, 0, 0, 34))
print_.AnchorPoint = Vector2.new(0, 1)
print_.Position = UDim2.fromScale(0, 1)
print_.TextSize = 14
print_.Activated:Connect(function()
	local lines = {}
	for _, field in FIELDS do
		local key = field[1]
		if field[2] and Tune[key] ~= initial[key] then
			table.insert(lines, `\tTune.{key} = {format(Tune[key])}`)
		end
	end
	print(
		if #lines > 0
			then "[C-Chassis] paste into A-Chassis Tune:\n" .. table.concat(lines, "\n")
			else "[C-Chassis] no Tune changes yet"
	)
end)

local function setOpen(open: boolean)
	panel.Visible = open
	toggle.Text = if open then "Close  [T]" else "Tune  [T]"
end

toggle.Activated:Connect(function()
	setOpen(not panel.Visible)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == TOGGLE_KEY then
		setOpen(not panel.Visible)
	end
end)

redrawGraph()
