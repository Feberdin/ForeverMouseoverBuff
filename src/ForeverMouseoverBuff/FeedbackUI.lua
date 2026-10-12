-- Purpose: let players prepare and review a GitHub report from the addon menu.
-- Input: deliberate button/slash actions and the IssueFeedback public projection.
-- Output: an optional technical preview and a selectable, fixed-destination URL.
-- Invariants: no HTTP, clipboard access, automatic submission or saved draft data.
-- Debug: /fmb feedback; missing modules show a recovery message, never raw errors.
local _, ns = ...
local unpack = unpack or table.unpack
local kinds = {bug = "Fehler melden", wish = "Wunsch äußern", feature = "Feature vorschlagen"}
local descriptions = {
    bug = "Etwas funktioniert nicht? Beschreibe auf GitHub die Schritte und das erwartete Ergebnis.",
    wish = "Was könnte angenehmer werden? Teile deinen Wunsch für eine bestehende Funktion.",
    feature = "Eine neue Idee? Erkläre, welches Problem sie löst und wem sie hilft.",
}

-- The preview is regenerated with the URL, so withdrawing the local opt-in
-- removes both together. A previous draft is never stored in SavedVariables.
function ns:UpdateFeedbackReport()
    local snapshot
    if self.feedbackIncludeTechnical then
        self:RefreshDiagnosticStatus()
        snapshot = self:DiagnosticSnapshot()
        snapshot.mode = self.db.mode
    end
    local report
    if self.IssueFeedback and type(self.IssueFeedback.Build) == "function" then
        report = self.IssueFeedback.Build(self.feedbackKind, snapshot, self.feedbackIncludeTechnical)
    end
    self.feedbackTechnicalButton:SetValue(self.feedbackIncludeTechnical)
    for kind, item in pairs(self.feedbackKindButtons) do
        item:SetSelected(kind == self.feedbackKind)
    end
    self.feedbackDescription:SetText(descriptions[self.feedbackKind])
    self.feedbackURLValue = report and report.url or ""
    self.feedbackURL:SetText(self.feedbackURLValue)
    self.feedbackURL:ClearFocus()
    self.feedbackPreview:SetText(report and report.preview
        or "Meldelink nicht verfügbar. Bitte das vollständige Addonpaket neu installieren und /reload ausführen. Hilfe: github.com/Feberdin/ForeverMouseoverBuff")
    if report then self.feedbackSelectButton:Enable() else self.feedbackSelectButton:Disable() end
end

-- Main-menu commands supersede an open report and any return queued by Escape.
-- Clear intent before Hide: OnHide must not reopen a window the user just closed.
function ns:HideFeedbackPanelForMenu()
    self.feedbackReturnToMenu, self.feedbackReturnToken = nil, nil
    if self.feedbackPanel then self.feedbackPanel:Hide() end
end

-- WoW closes every UISpecialFrames entry during one Escape sweep. Restoring the
-- main window inside OnHide would let that same sweep hide it again. A zero-delay
-- timer returns on the next frame; its identity cancels stale close/reopen work.
local function feedbackHidden(panel)
    ns.feedbackURL:ClearFocus()
    if panel:IsShown() or not ns.feedbackReturnToMenu then return end
    local token = {}
    ns.feedbackReturnToken = token
    C_Timer.After(0, function()
        if ns.feedbackReturnToken ~= token then return end
        local main = ns.feedbackReturnToMenu
        ns.feedbackReturnToMenu, ns.feedbackReturnToken = nil, nil
        if main and ns.Menu and UIParent:IsShown() and not panel:IsShown() and not main:IsShown() then
            ns.Menu.Show()
        end
    end)
end

-- This is an ordinary, unprotected window. Opening it must not reconfigure the
-- buff button or acquire keyboard focus while the player is moving.
function ns:ShowFeedbackPanel(kind)
    if not kinds[kind] then kind = "bug" end
    if not self.feedbackPanel then
        local Theme, colors = self.Theme, self.Theme.colors
        local panel = Theme.Window("ForeverMouseoverBuffFeedbackPanel", "", 760, 660)
        self.feedbackPanel = panel
        Theme.Icon(panel, Theme.Path("ProjectIcon"), 24, 20, 54, 54)
        Theme.Icon(panel, Theme.Path("FeberdinKnight"), 649, 19, 54, 54)
        Theme.Text(panel, "Feedback & Hilfe", 94, 23, 510, 28, 23, colors.gold)
        Theme.Text(panel, "Deine Idee macht das Addon besser.", 95, 56, 510, 24, 14, colors.muted)
        self.feedbackKindButtons = {}
        for index, choice in ipairs({"bug", "wish", "feature"}) do
            local selected = choice
            self.feedbackKindButtons[choice] = Theme.Button(panel, kinds[choice], 24 + (index - 1) * 242, 100, 228, 38,
                function() ns.feedbackKind = selected; ns:UpdateFeedbackReport() end)
        end
        self.feedbackDescription = Theme.Text(panel, "", 24, 155, 710, 36, 14, colors.text)
        self.feedbackTechnicalButton = Theme.Toggle(panel, "Technische Angaben teilen",
            "Freiwillig: Version, Schalter und bekannte Diagnosecodes.", 24, 198, 712, function()
                ns.feedbackIncludeTechnical = not ns.feedbackIncludeTechnical
                ns:UpdateFeedbackReport()
            end)
        Theme.Rect(panel, 24, 277, 712, 206, colors.panel)
        Theme.Text(panel, "DEINE VORSCHAU", 40, 291, 678, 20, 12, colors.gold)
        self.feedbackPreview = Theme.Text(panel, "", 40, 321, 678, 154, 13, colors.text)
        Theme.Text(panel, "Keine Namen, Whisper oder Zähler. Beim Öffnen erhält GitHub die ausgewählten Angaben. Erst dein Absenden veröffentlicht das Issue. GitHub-Konto erforderlich.",
            24, 498, 712, 46, 13, colors.muted)
        -- Plain EditBox avoids inherited Blizzard artwork. The original copy-only
        -- behavior remains: selection is deliberate and Escape releases focus.
        Theme.Rect(panel, 24, 553, 712, 33, colors.edge)
        Theme.Rect(panel, 25, 554, 710, 31, colors.row)
        self.feedbackURL = CreateFrame("EditBox", nil, panel)
        self.feedbackURL:SetSize(690, 29); self.feedbackURL:SetPoint("TOPLEFT", panel, "TOPLEFT", 35, -555)
        self.feedbackURL:SetFont("Fonts\\ARIALN.TTF", 13, "")
        self.feedbackURL:SetTextColor(unpack(colors.mint))
        self.feedbackURL:SetAutoFocus(false); self.feedbackURL:SetMultiLine(false)
        self.feedbackURL:SetMaxLetters(8192)
        self.feedbackURL:SetScript("OnEscapePressed", function(self) self:ClearFocus(); panel:Hide() end)
        self.feedbackURL:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        -- A copy-only URL avoids a changed address contradicting the preview.
        self.feedbackURL:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(ns.feedbackURLValue or "") end
        end)
        panel:SetScript("OnHide", feedbackHidden)
        self.feedbackSelectButton = Theme.Button(panel, "Link markieren", 24, 604, 164, 34, function()
            ns.feedbackURL:SetFocus(); ns.feedbackURL:HighlightText()
        end)
        Theme.Text(panel, "Cmd/Strg+C  →  Im Browser öffnen  →  Prüfen & senden", 207, 614, 529, 25, 13, colors.muted)
    end
    self.feedbackKind, self.feedbackIncludeTechnical = kind, false
    self:UpdateFeedbackReport()
    -- Only one FMB root is visible. Its descendants otherwise interleave with
    -- the other DIALOG root, even though both backgrounds are fully opaque.
    self.feedbackReturnToken = nil
    if self.panel and self.panel:IsShown() then
        self.feedbackReturnToMenu = self.panel
        self.panel:Hide()
    end
    self.feedbackPanel:Show()
end
