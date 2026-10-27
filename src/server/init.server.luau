-- Showcase spawner: keeps one C-Chassis car parked near the spawn, and brings it back when it is destroyed.
local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("C-Chassis") :: Model
local SPOT = Vector3.new(0, 0, -30) -- on the baseplate's top surface
local RESPAWN_DELAY = 3

local function spawnCar()
	local car = template:Clone()
	car.PrimaryPart = car:FindFirstChild("DriveSeat") :: BasePart

	-- rest the lowest point (the tyres) on the ground, wherever the model was authored
	local box, size = car:GetBoundingBox()
	local bottom = box.Position - Vector3.new(0, size.Y / 2, 0)
	car:PivotTo(car:GetPivot() + (SPOT - bottom) + Vector3.new(0, 0.5, 0))
	car.Parent = workspace

	car.AncestryChanged:Connect(function()
		if not car:IsDescendantOf(workspace) then
			task.delay(RESPAWN_DELAY, spawnCar)
		end
	end)
end

spawnCar()
