local Tool = script.Parent
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local openGuiRemote = ReplicatedStorage:WaitForChild("OpenDonationGui")
local MAX_CLICK_DISTANCE = 20

local function getToolOwner()
	local character = Tool.Parent
	if character and character:IsA("Model") then
		return Players:GetPlayerFromCharacter(character)
	end
	return nil
end

local function getPlayerStatValue(targetPlayer, statName)
	local leaderstats = targetPlayer:FindFirstChild("leaderstats")
	if not leaderstats then
		return 0
	end
	local stat = leaderstats:FindFirstChild(statName)
	if stat and stat:IsA("IntValue") then
		return stat.Value
	end
	return 0
end

local function buildOwnerPayload(owner)
	return {
		ownerUserId = owner.UserId,
		ownerName = owner.Name,
		ownerDisplayName = owner.DisplayName,
		ownerRaised = getPlayerStatValue(owner, "Raised"),
		ownerDonated = getPlayerStatValue(owner, "Donated"),
	}
end

local function onJarClicked(clickingPlayer)
	local owner = getToolOwner()
	if not owner then
		return
	end
	if clickingPlayer == owner then
		-- Optional: wag i-open sa sarili
		return
	end

	openGuiRemote:FireClient(clickingPlayer, buildOwnerPayload(owner))
end

local function attachClickDetector(part)
	local clickDetector = part:FindFirstChildOfClass("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		clickDetector.Parent = part
	end
	clickDetector.MaxActivationDistance = MAX_CLICK_DISTANCE
	clickDetector.MouseClick:Connect(onJarClicked)
end

for _, desc in ipairs(Tool:GetDescendants()) do
	if desc:IsA("BasePart") then
		attachClickDetector(desc)
	end
end