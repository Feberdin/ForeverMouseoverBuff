-- Purpose: check Sanctum native controls, responsive bounds and explicit actions.
-- Input: synthetic frame recorder and the real Theme module. Output: test status.
-- Invariant: no game session, external assets fetched or protected spell actions.
-- Debug: lua tests/test_theme.lua; inspect tests/menu_frames.lua recorded nodes.
local fixture = assert(loadfile("tests/menu_frames.lua"))()
local state = fixture.install()
local ns = {}
local source = loadfile("src/ForeverMouseoverBuff/Theme.lua")
if source then source("ForeverMouseoverBuff", ns) end
assert(ns.Theme, "Sanctum theme is missing; the menu still relies on Blizzard's default red controls")
local Theme = ns.Theme
local window = Theme.Window("TestSanctumWindow", "", 840, 620)
assert(window.template == nil, "Window must not inherit Blizzard's decorative dialog")
assert(window.width == 840 and window.height == 620)
assert(window.scale == 1 and #UISpecialFrames == 1)
local calls = 0
local button = Theme.Button(window, "Test action", 20, 100, 160, 38, function() calls = calls + 1 end)
assert(button.template == nil, "Buttons must use the custom flat theme")
assert(calls == 0, "Construction must never trigger actions")
button:Click(); assert(calls == 1)
button:Disable(); button:Click(); assert(calls == 1)
button:SetSelected(true); assert(button.selected == true)
local toggle = Theme.Toggle(window, "Grüße", "Nur automatische Grüße", 20, 160, 500, function() calls = calls + 1 end)
toggle:SetValue(false); assert(toggle.value == false and toggle:GetText():find("aus", 1, true))
toggle:SetValue(true); assert(toggle.value == true and toggle:GetText():find("an", 1, true))
assert(calls == 1, "Refreshing a toggle must never execute its action")
toggle:Click(); assert(calls == 2)
assert(Theme.Path("ProjectIcon") == "Interface\\AddOns\\ForeverMouseoverBuff\\Media\\ProjectIcon.tga")
UIParent:SetSize(680, 480)
local small = Theme.Window("TestSmallWindow", "", 840, 620)
assert(small.width * small.scale <= 648 and small.height * small.scale <= 448,
    "Whole window must fit small viewports with padding")
small.closeButton:Click(); assert(not small:IsShown())
assert(#state.nodes > 15, "The test must exercise actual texture/font construction")
-- The report dialog must share the real theme, not reopen the old red template.
UIParent:SetSize(1920, 1080)
ns.IssueFeedback = {Build = function() return {url = "https://github.com/Feberdin/ForeverMouseoverBuff/issues/new", preview = "No details"} end}
assert(loadfile("src/ForeverMouseoverBuff/FeedbackUI.lua"))("ForeverMouseoverBuff", ns)
ns:ShowFeedbackPanel("bug")
assert(ns.feedbackPanel.template == nil, "Feedback must use the same Sanctum window as the main menu")
assert(ns.feedbackSelectButton.template == nil, "The feedback copy action must use a flat themed button")
ns.feedbackSelectButton:Click()
assert(ns.feedbackURL.focused and ns.feedbackURL.highlighted)
ns.feedbackURL.scripts.OnEscapePressed(ns.feedbackURL)
assert(not ns.feedbackURL.focused and not ns.feedbackPanel:IsShown())
-- Stacked textures must carry explicit sublevels. WoW leaves the draw order of
-- same-layer, same-sublevel textures unspecified; observed in game as a window
-- whose buttons were solid, framed or invisible depending on the reload.
local recordedTextures = {}
local nativeCreateFrame = CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = nativeCreateFrame(kind, name, parent, template)
    local nativeCreateTexture = frame.CreateTexture
    frame.CreateTexture = function(self, textureName, layer, inherits, sublevel)
        local texture = nativeCreateTexture(self, textureName, layer)
        texture.sublevel = sublevel or 0
        recordedTextures[#recordedTextures + 1] = texture
        return texture
    end
    return frame
end
local function texturesOf(parent)
    local list = {}
    for _, texture in ipairs(recordedTextures) do
        if texture.parent == parent then list[#list + 1] = texture end
    end
    return list
end
local orderedWindow = Theme.Window("TestOrderedWindow", "", 840, 620)
local windowLayers = texturesOf(orderedWindow)
assert(#windowLayers >= 3, "window draws edge, background and gold bar")
assert(windowLayers[1].sublevel < windowLayers[2].sublevel and windowLayers[2].sublevel < windowLayers[3].sublevel,
    "window edge, background and gold bar need rising sublevels")
assert(windowLayers[3].sublevel < 0, "window layers stay below later decorations drawn at sublevel 0")
local orderedButton = Theme.Button(orderedWindow, "Ordered", 20, 100, 160, 38, function() end)
assert(orderedButton.fill.sublevel > orderedButton.border.sublevel, "button fill must draw above its border")
local orderedToggle = Theme.Toggle(orderedWindow, "Ordered", "desc", 20, 160, 500, function() end)
local toggleLayers = texturesOf(orderedToggle)
assert(orderedToggle.indicator.sublevel > toggleLayers[1].sublevel, "toggle indicator must draw above its row background")
local passthrough = Theme.Rect(orderedWindow, 0, 0, 10, 10, Theme.colors.edge, 1)
assert(passthrough.sublevel == 1, "Rect passes an explicit sublevel through")
assert(Theme.Rect(orderedWindow, 0, 0, 10, 10, Theme.colors.edge).sublevel == 0, "Rect defaults to sublevel 0")
_G.CreateFrame = nativeCreateFrame
print("PASS texture order: stacked rects carry explicit sublevels")

print("PASS 9 native theme contracts; actual WoW rendering remains a separate check")
