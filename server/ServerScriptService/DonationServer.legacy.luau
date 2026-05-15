local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local openGuiRemote = ReplicatedStorage:WaitForChild("OpenDonationGui")
local requestDonateRemote = ReplicatedStorage:FindFirstChild("RequestDonate")
local pendingDonations = {} -- [donorUserId] = {ownerUserId, productId, amount}
-- Studio/Team Test: simulate (free). Live server: real purchase flow.
local STUDIO_SIMULATE_PURCHASES = RunService:IsStudio()

-- TODO: Replace these ProductIds with your full list.
local PRODUCT_AMOUNTS = {
	[3581351327] = 1,
	[3581351892] = 5,
}

local function ensureLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local donated = leaderstats:FindFirstChild("Donated")
	if not donated then
		donated = Instance.new("IntValue")
		donated.Name = "Donated"
		donated.Value = 0
		donated.Parent = leaderstats
	end

	local raised = leaderstats:FindFirstChild("Raised")
	if not raised then
		raised = Instance.new("IntValue")
		raised.Name = "Raised"
		raised.Value = 0
		raised.Parent = leaderstats
	end
end

local function getCharacterRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function isWithinDonationDistance(donor, owner, maxDistance)
	local donorRoot = getCharacterRoot(donor)
	local ownerRoot = getCharacterRoot(owner)
	if not donorRoot or not ownerRoot then
		return false
	end
	return (donorRoot.Position - ownerRoot.Position).Magnitude <= maxDistance
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

local function addStat(player, statName, amount)
	if amount <= 0 then
		return
	end

	ensureLeaderstats(player)

	local stat = player.leaderstats:FindFirstChild(statName)
	if stat and stat:IsA("IntValue") then
		stat.Value += amount
	end
end

local function applyDonation(donor, owner, amount)
	addStat(owner, "Raised", amount)
	addStat(donor, "Donated", amount)

	openGuiRemote:FireClient(donor, buildOwnerPayload(owner))
	openGuiRemote:FireClient(owner, buildOwnerPayload(owner))
end

for _, player in ipairs(Players:GetPlayers()) do
	ensureLeaderstats(player)
end

Players.PlayerAdded:Connect(function(player)
	ensureLeaderstats(player)
end)

Players.PlayerRemoving:Connect(function(player)
	pendingDonations[player.UserId] = nil
end)

openGuiRemote.OnServerEvent:Connect(function(requestingPlayer, action, ownerUserId)
	if action ~= "refresh" then
		return
	end

	local owner = Players:GetPlayerByUserId(tonumber(ownerUserId) or -1)
	if not owner then
		return
	end

	openGuiRemote:FireClient(requestingPlayer, buildOwnerPayload(owner))
end)

if requestDonateRemote and requestDonateRemote:IsA("RemoteEvent") then
	requestDonateRemote.OnServerEvent:Connect(function(donor, ownerUserId, productId, amountHint)
		if pendingDonations[donor.UserId] then
			warn("[DonationServer] Donate rejected: donor already has pending purchase.")
			return
		end

		local owner = Players:GetPlayerByUserId(tonumber(ownerUserId) or -1)
		if not owner or owner == donor then
			warn("[DonationServer] Donate rejected: invalid owner or self donate.")
			return
		end

		local parsedProductId = tonumber(productId)
		if not parsedProductId then
			warn("[DonationServer] Donate rejected: invalid productId.", productId)
			return
		end

		local amount = PRODUCT_AMOUNTS[parsedProductId]
		if not amount then
			if RunService:IsStudio() and STUDIO_SIMULATE_PURCHASES then
				local parsedHint = tonumber(amountHint)
				if parsedHint and parsedHint > 0 then
					amount = parsedHint
				end
			end
			if not amount then
				warn("[DonationServer] Unknown productId from client:", parsedProductId)
				return
			end
		end

		if (not RunService:IsStudio()) and (not isWithinDonationDistance(donor, owner, 30)) then
			warn("[DonationServer] Donate rejected: players too far apart.")
			return
		end

		pendingDonations[donor.UserId] = {
			ownerUserId = owner.UserId,
			productId = parsedProductId,
			amount = amount,
		}

		if RunService:IsStudio() and STUDIO_SIMULATE_PURCHASES then
			print(string.format(
				"[DonationServer] Studio simulated donation donor=%s owner=%s amount=%s",
				donor.Name,
				owner.Name,
				tostring(amount)
			))
			applyDonation(donor, owner, amount)
			pendingDonations[donor.UserId] = nil
			return
		end

		print(string.format(
			"[DonationServer] PromptProductPurchase donor=%s owner=%s productId=%s amount=%s",
			donor.Name,
			owner.Name,
			tostring(parsedProductId),
			tostring(amount)
		))
		MarketplaceService:PromptProductPurchase(donor, parsedProductId)
	end)
else
	warn("[DonationServer] Missing ReplicatedStorage.RequestDonate RemoteEvent.")
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if isPurchased then
		return
	end

	local pending = pendingDonations[userId]
	if pending and pending.productId == productId then
		pendingDonations[userId] = nil
	end
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local donor = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not donor then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local pending = pendingDonations[donor.UserId]
	if not pending then
		warn("[DonationServer] ProcessReceipt missing pending donation for player:", donor.UserId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local expectedAmount = PRODUCT_AMOUNTS[receiptInfo.ProductId]
	if not expectedAmount then
		warn("[DonationServer] ProcessReceipt unknown productId:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if pending.productId ~= receiptInfo.ProductId then
		warn("[DonationServer] ProcessReceipt product mismatch pending=", pending.productId, " receipt=", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local owner = Players:GetPlayerByUserId(pending.ownerUserId)
	if owner then
		applyDonation(donor, owner, expectedAmount)
	end

	pendingDonations[donor.UserId] = nil
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
