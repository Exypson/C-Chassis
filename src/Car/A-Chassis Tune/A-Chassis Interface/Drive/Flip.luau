local S = require(script.Parent.State)

local Flip = {}

-- Flip
function Flip.run()
	if S.FlipActive then
		return
	end

	S.FlipActive = true
	S.FlipAlignOrientation.Enabled = true

	task.delay(0.5, function()
		if S.FlipAlignOrientation.Parent then
			S.FlipAlignOrientation.Enabled = false
		end
		S.FlipActive = false
	end)
end

function Flip.auto()
	if S.WeightBrick.CFrame.UpVector.Y > 0.1 then
		S.FlipWait = os.clock()
		return
	end

	if S.FlipActive or os.clock() - S.FlipWait < 3 then
		return
	end

	S.FlipWait = os.clock()
	Flip.run()
end

return Flip
