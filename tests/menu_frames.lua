-- Purpose: record native UI construction for deterministic menu and theme tests.
-- Input: explicit synthetic frame calls. Output: inspectable nodes; no WoW client.
-- Invariant: records layout and handlers only, never emulates protected casting.
-- Debug: lua tests/test_menu.lua; inspect state.nodes after fixture.install().
local Fixture = {}
function Fixture.install()
    local state = {nodes = {}, frames = {}}
    local function node(kind, name, parent, template)
        local result = {kind = kind, name = name, parent = parent, template = template,
            children = {}, scripts = {}, points = {}, shown = true, text = "", width = 0, height = 0}
        state.nodes[#state.nodes + 1] = result
        if parent and parent.children then parent.children[#parent.children + 1] = result end
        if name then state.frames[name] = result; _G[name] = result end
        function result:SetScript(event, fn) self.scripts[event] = fn end
        function result:GetScript(event) return self.scripts[event] end
        function result:HookScript(event, fn)
            local previous = self.scripts[event]
            self.scripts[event] = function(...) if previous then previous(...) end; fn(...) end
        end
        function result:SetSize(width, height) self.width, self.height = width, height end
        function result:SetWidth(width) self.width = width end
        function result:SetHeight(height) self.height = height end
        function result:GetWidth() return self.width end
        function result:GetHeight() return self.height end
        function result:SetPoint(...) self.points[#self.points + 1] = {...} end
        function result:ClearAllPoints() self.points = {} end
        function result:SetAllPoints(target) self.allPoints = target or self.parent end
        function result:SetText(text) self.text = text end
        function result:GetText() return self.text end
        function result:SetTextColor(...) self.textColor = {...} end
        function result:SetColorTexture(...) self.color = {...} end
        function result:SetVertexColor(...) self.vertexColor = {...} end
        function result:SetTexture(texture) self.texture = texture end
        function result:SetTexCoord(...) self.texcoords = {...} end
        function result:SetFont(...) self.font = {...}; return true end
        function result:SetFontObject(font) self.fontObject = font end
        function result:SetJustifyH(value) self.justifyH = value end
        function result:SetJustifyV(value) self.justifyV = value end
        function result:SetAlpha(value) self.alpha = value end
        function result:SetScale(value) self.scale = value end
        function result:GetEffectiveScale() return self.scale or 1 end
        function result:SetFrameStrata(value) self.strata = value end
        function result:GetFrameLevel() return self.level or 1 end
        function result:SetFrameLevel(value) self.level = value end
        function result:SetParent(value) self.parent = value end
        function result:GetParent() return self.parent end
        function result:Show() self.shown = true end
        function result:Hide() self.shown = false end
        function result:IsShown() return self.shown end
        function result:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function result:Enable() self.disabled = false end
        function result:Disable() self.disabled = true end
        function result:IsEnabled() return not self.disabled end
        function result:CreateFontString(name) return node("FontString", name, self) end
        function result:CreateTexture(name, layer) local t = node("Texture", name, self); t.layer = layer; return t end
        function result:Click() if not self.disabled and self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
        function result:SetFocus() self.focused = true end
        function result:ClearFocus() self.focused = false end
        function result:HighlightText() self.highlighted = true end
        function result:SetChecked(value) self.checked = value end
        function result:GetChecked() return self.checked end
        for _, method in ipairs({"EnableMouse", "SetMovable", "SetClampedToScreen", "RegisterForDrag",
            "StartMoving", "StopMovingOrSizing", "RegisterEvent", "SetAutoFocus", "SetMultiLine",
            "SetMaxLetters", "SetTextInsets", "SetNormalFontObject", "SetHighlightFontObject",
            "SetDisabledFontObject", "SetWordWrap", "SetNonSpaceWrap", "SetShadowColor", "SetShadowOffset"}) do
            result[method] = function() end
        end
        return result
    end
    _G.CreateFrame = function(kind, name, parent, template) return node(kind, name, parent, template) end
    _G.UIParent = node("Frame", "UIParent")
    UIParent:SetSize(1920, 1080)
    _G.UISpecialFrames, _G.SlashCmdList = {}, {}
    _G.GetBindingText = function(value) return value end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    return state
end
return Fixture
