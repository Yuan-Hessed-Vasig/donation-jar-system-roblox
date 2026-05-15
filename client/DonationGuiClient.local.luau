local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gui = script.Parent
local openGuiRemote = ReplicatedStorage:WaitForChild("OpenDonationGui")
local requestDonateRemote = ReplicatedStorage:WaitForChild("RequestDonate")

-- Fallback mapping if button has no ProductId attribute yet.
-- Replace/add values here as you create more developer products.
local DEFAULT_PRODUCT_IDS_BY_AMOUNT = {
	[1] = 3581351327,
	[5] = 3581351892,
}

-- Useful fallback when button names are Donate1, Donate2, etc.
local DEFAULT_PRODUCT_IDS_BY_BUTTON_NAME = {
	Donate1 = 3581351327, -- 1 Robux
	Donate2 = 3581351892, -- 5 Robux
}

-- Support both "MainFrame" and "Frame" para di brittle sa naming.
local mainFrame = gui:FindFirstChild("MainFrame") or gui:FindFirstChild("Frame")
if not mainFrame then
	warn("[DonationGuiClient] Missing MainFrame/Frame in gui:", gui:GetFullName())
	return
end

local topFrame = mainFrame:FindFirstChild("TopFrame") or mainFrame
local bottomFrame = mainFrame:FindFirstChild("BottomFrame") or mainFrame

local targetNameLabel = topFrame:FindFirstChild("TargetName") or mainFrame:FindFirstChild("TargetName")
local targetUserLabel = topFrame:FindFirstChild("TargetUser") or mainFrame:FindFirstChild("TargetUser")
local raisedLabel = topFrame:FindFirstChild("RaiseLabel") or topFrame:FindFirstChild("RaisedLabel") or mainFrame:FindFirstChild("RaiseLabel") or mainFrame:FindFirstChild("RaisedLabel")
local donatedLabel = topFrame:FindFirstChild("DonatedLabel") or mainFrame:FindFirstChild("DonatedLabel")
local avatarImage = topFrame:FindFirstChild("AvatarImage") or topFrame:FindFirstChild("Avatar") or mainFrame:FindFirstChild("AvatarImage") or mainFrame:FindFirstChild("Avatar")
local closeButton = topFrame:FindFirstChild("CloseButton") or mainFrame:FindFirstChild("CloseButton")
local refreshButton = topFrame:FindFirstChild("RefreshButton") or topFrame:FindFirstChild("Refresh") or mainFrame:FindFirstChild("RefreshButton") or mainFrame:FindFirstChild("Refresh")

local scrollingFrame = bottomFrame:FindFirstChild("ScrollingFrame")
if not scrollingFrame then
	local contentFrame = bottomFrame:FindFirstChild("Frame") or mainFrame:FindFirstChild("Frame") or mainFrame:FindFirstChild("DonateContainer")
	scrollingFrame = contentFrame and (contentFrame:FindFirstChild("ScrollingFrame") or contentFrame:FindFirstChild("DonateScroll"))
end

if not targetNameLabel then
	warn("[DonationGuiClient] Missing TargetName label:", mainFrame:GetFullName())
end
if not targetUserLabel then
	warn("[DonationGuiClient] Missing TargetUser label:", mainFrame:GetFullName())
end
if not closeButton then
	warn("[DonationGuiClient] Missing CloseButton:", mainFrame:GetFullName())
end
if not scrollingFrame then
	warn("[DonationGuiClient] Missing ScrollingFrame/DonateScroll for donation buttons.")
end

local currentTargetUserId = nil

local function setTargetThumbnail(userId)
	if not avatarImage or not avatarImage:IsA("ImageLabel") then
		return
	end

	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
	end)

	if ok then
		avatarImage.Image = content
	end
end

local function updateLabels(data)
	if targetNameLabel and targetNameLabel:IsA("TextLabel") then
		targetNameLabel.Text = data.ownerDisplayName or data.ownerName
	end
	if targetUserLabel and targetUserLabel:IsA("TextLabel") then
		targetUserLabel.Text = "(@" .. (data.ownerName or "unknown") .. ")"
	end
	if raisedLabel and raisedLabel:IsA("TextLabel") then
		raisedLabel.Text = "Raised: " .. tostring(data.ownerRaised or 0)
	end
	if donatedLabel and donatedLabel:IsA("TextLabel") then
		donatedLabel.Text = "Donated: " .. tostring(data.ownerDonated or 0)
	end
end

local function onDonateButtonClicked(button)
	if not currentTargetUserId then
		return
	end
	if not requestDonateRemote then
		warn("[DonationGuiClient] Missing ReplicatedStorage.RequestDonate RemoteEvent.")
		return
	end

	local productId = tonumber(button:GetAttribute("ProductId"))
	local amount = tonumber(button:GetAttribute("Amount"))

	if not amount then
		local fromName = string.match(button.Name, "^Donate(%d+)$")
		if fromName then
			amount = tonumber(fromName)
		end
	end
	if not amount then
		local fromText = string.match(button.Text or "", "(%d+)")
		if fromText then
			amount = tonumber(fromText)
		end
	end

	if not productId then
		productId = DEFAULT_PRODUCT_IDS_BY_BUTTON_NAME[button.Name]
	end

	if not productId and amount then
		productId = DEFAULT_PRODUCT_IDS_BY_AMOUNT[amount]
	end

	if not productId or productId <= 0 then
		warn("[DonationGuiClient] Set ProductId attribute on button:", button:GetFullName())
		return
	end

	print(string.format(
		"[DonationGuiClient] donate click target=%s productId=%s amount=%s button=%s",
		tostring(currentTargetUserId),
		tostring(productId),
		tostring(amount),
		button:GetFullName()
	))
	requestDonateRemote:FireServer(currentTargetUserId, productId, amount or button.Text)
end

if scrollingFrame and scrollingFrame:IsA("ScrollingFrame") then
	for _, item in ipairs(scrollingFrame:GetDescendants()) do
		if item:IsA("TextButton") or item:IsA("ImageButton") then
			item.MouseButton1Click:Connect(function()
				onDonateButtonClicked(item)
			end)
		end
	end
end

openGuiRemote.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end

	currentTargetUserId = data.ownerUserId
	updateLabels(data)
	setTargetThumbnail(data.ownerUserId)

	gui.Enabled = true
end)

if closeButton and (closeButton:IsA("TextButton") or closeButton:IsA("ImageButton")) then
	closeButton.MouseButton1Click:Connect(function()
		gui.Enabled = false
		currentTargetUserId = nil
	end)
end

if refreshButton and (refreshButton:IsA("TextButton") or refreshButton:IsA("ImageButton")) then
	refreshButton.MouseButton1Click:Connect(function()
		if currentTargetUserId then
			openGuiRemote:FireServer("refresh", currentTargetUserId)
		end
	end)
end