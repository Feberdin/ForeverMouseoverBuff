-- Purpose: reusable Sanctum appearance built with ordinary WoW frames and textures.
-- Input: local labels, geometry and explicit button callbacks. Output: native controls.
-- Invariants: no protected templates, key bindings, saved settings or network access.
-- Debug: /fmb; tests/test_theme.lua checks geometry and actions outside the game.
local _, ns = ...
local Theme = {}
ns.Theme = Theme
Theme.colors = {
    bg = {0.047, 0.086, 0.102, 1}, panel = {0.071, 0.125, 0.145, 1},
    row = {0.09, 0.157, 0.173, 1}, edge = {0.16, 0.235, 0.25, 1},
    gold = {0.843, 0.718, 0.482, 1}, mint = {0.42, 0.827, 0.698, 1},
    text = {0.91, 0.933, 0.918, 1}, muted = {0.57, 0.655, 0.663, 1},
}
local c = Theme.colors
local unpack = unpack or table.unpack
local function paint(texture, color) texture:SetColorTexture(unpack(color)) end

function Theme.Path(name)
    return "Interface\\AddOns\\ForeverMouseoverBuff\\Media\\" .. name
        .. (name:match("%.tga$") and "" or ".tga")
end
function Theme.Rect(parent, x, y, width, height, color)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    texture:SetSize(width, height); paint(texture, color or c.panel)
    return texture
end
function Theme.Text(parent, value, x, y, width, height, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:SetSize(width, height); label:SetFont("Fonts\\ARIALN.TTF", size or 14, "")
    label:SetJustifyH("LEFT"); label:SetJustifyV("TOP"); label:SetWordWrap(true)
    label:SetTextColor(unpack(color or c.text)); label:SetText(value)
    return label
end
function Theme.Icon(parent, path, x, y, width, height)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    texture:SetSize(width, height); texture:SetTexture(path)
    return texture
end

-- Every action is an ordinary button with its own text and flat background.
-- Updating selected/value state only redraws; it never calls the action.
function Theme.Button(parent, value, x, y, width, height, action)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); button:SetSize(width, height)
    button.border = Theme.Rect(button, 0, 0, width, height, c.edge)
    button.fill = Theme.Rect(button, 1, 1, width - 2, height - 2, c.row)
    button.label = Theme.Text(button, value, 9, 0, width - 18, height, 14, c.text)
    button.label:SetJustifyH("CENTER"); button.label:SetJustifyV("MIDDLE")
    function button:SetText(text) self.text = text; self.label:SetText(text) end
    function button:GetText() return self.text end
    function button:SetSelected(selected)
        self.selected = selected == true
        paint(self.border, self.selected and c.gold or c.edge)
        self.label:SetTextColor(unpack(self.selected and c.gold or c.text))
    end
    button:SetText(value); button:SetSelected(false)
    button:SetScript("OnEnter", function(self) if self:IsEnabled() then paint(self.border, c.gold) end end)
    button:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    button:SetScript("OnDisable", function(self) self.label:SetTextColor(unpack(c.muted)) end)
    button:SetScript("OnEnable", function(self) self:SetSelected(self.selected) end)
    button:SetScript("OnClick", action)
    return button
end
function Theme.Toggle(parent, value, description, x, y, width, action)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); button:SetSize(width, 64)
    Theme.Rect(button, 0, 0, width, 64, c.row)
    Theme.Text(button, value, 14, 10, width - 102, 22, 15, c.text)
    Theme.Text(button, description, 14, 34, width - 102, 25, 12, c.muted)
    button.indicator = Theme.Rect(button, width - 67, 20, 51, 26, c.edge)
    button.badge = Theme.Text(button, "", width - 67, 20, 51, 26, 12, c.text)
    button.badge:SetJustifyH("CENTER"); button.badge:SetJustifyV("MIDDLE")
    function button:SetValue(enabled)
        self.value = enabled == true
        self.text = value .. ": " .. (self.value and "an" or "aus")
        paint(self.indicator, self.value and c.mint or c.edge)
        self.badge:SetText(self.value and "AN" or "AUS")
        self.badge:SetTextColor(unpack(self.value and c.bg or c.muted))
    end
    function button:GetText() return self.text end
    button:SetValue(false); button:SetScript("OnClick", action)
    return button
end

-- Center and fit the complete window, preserving readable proportions. WoW UI
-- geometry is in logical units, so no monitor resolution assumptions are needed.
function Theme.Window(name, title, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local availableWidth, availableHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = math.min(1, math.max(1, availableWidth - 32) / width,
        math.max(1, availableHeight - 32) / height)
    frame:SetScale(scale); frame:SetClampedToScreen(true); frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Theme.Rect(frame, 0, 0, width, height, c.edge)
    Theme.Rect(frame, 1, 1, width - 2, height - 2, c.bg)
    Theme.Rect(frame, 1, 1, width - 2, 2, c.gold)
    if title and title ~= "" then Theme.Text(frame, title, 24, 23, width - 100, 29, 20, c.gold) end
    frame.closeButton = Theme.Button(frame, "×", width - 44, 18, 26, 26, function() frame:Hide() end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = name end
    return frame
end
