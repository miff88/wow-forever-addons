-- Shared settings page builder. Each addon ships its own copy so they stay independent.
-- Builds a page under Options > AddOns with checkboxes, +/- steppers, cycle buttons and
-- plain buttons, using only long-standing UI templates.

local ADDON_NAME, ns = ...

local function Metadata(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, ADDON_NAME, field)
    return ok and v or nil
end

ns.version = Metadata("Version") or "?"

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

-- spec = {
--   title = "Overpower Plates", icon = "Interface\\Icons\\...", about = "one line",
--   slash = "/opp", db = table, onChange = function(key) end,
--   controls = {
--     { type = "header", label = "Icon" },
--     { type = "check",  key = "sound", label = "Play a sound" },
--     { type = "range",  key = "size", label = "Size", min = 16, max = 64, step = 2 },
--     { type = "choice", key = "side", label = "Side", values = { "left", "right" } },
--     { type = "button", label = "Test", func = function() end },
--   },
-- }
function ns.CreateOptions(spec)
    local panel = CreateFrame("Frame")
    panel.name = spec.title
    local refreshers = {}
    local built = false
    local db = spec.db

    local function Changed(key)
        if spec.onChange then spec.onChange(key) end
        for _, r in ipairs(refreshers) do r() end
    end

    local function Build()
        if built then return end
        built = true

        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetSize(40, 40)
        icon:SetPoint("TOPLEFT", 16, -16)
        icon:SetTexture(spec.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local title = Label(panel, spec.title, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)

        local sub = Label(panel, "Version " .. ns.version .. (spec.about and ("  -  " .. spec.about) or ""), "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        sub:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
        sub:SetJustifyH("LEFT")

        local y = -80
        for _, c in ipairs(spec.controls) do
            if c.type == "header" then
                y = y - 6
                local h = Label(panel, c.label, "GameFontNormal")
                h:SetPoint("TOPLEFT", 16, y)
                y = y - 22

            elseif c.type == "check" then
                local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
                cb:SetSize(26, 26)
                cb:SetPoint("TOPLEFT", 20, y)
                local l = Label(panel, c.label)
                l:SetPoint("LEFT", cb, "RIGHT", 4, 1)
                cb:SetScript("OnClick", function(self)
                    db[c.key] = self:GetChecked() and true or false
                    Changed(c.key)
                end)
                table.insert(refreshers, function() cb:SetChecked(db[c.key] and true or false) end)
                y = y - 30

            elseif c.type == "range" then
                local l = Label(panel, c.label)
                l:SetPoint("TOPLEFT", 24, y - 4)

                local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
                minus:SetSize(26, 22)
                minus:SetPoint("TOPLEFT", 240, y)
                minus:SetText("-")

                local value = Label(panel, "")
                value:SetWidth(44)
                value:SetPoint("LEFT", minus, "RIGHT", 4, 0)

                local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
                plus:SetSize(26, 22)
                plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
                plus:SetText("+")

                local function Step(dir)
                    local v = (db[c.key] or c.min) + dir * c.step
                    v = math.max(c.min, math.min(c.max, v))
                    db[c.key] = v
                    Changed(c.key)
                end
                minus:SetScript("OnClick", function() Step(-1) end)
                plus:SetScript("OnClick", function() Step(1) end)
                table.insert(refreshers, function()
                    value:SetText(tostring(db[c.key]) .. (c.suffix or ""))
                end)
                y = y - 30

            elseif c.type == "choice" then
                local l = Label(panel, c.label)
                l:SetPoint("TOPLEFT", 24, y - 4)
                local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
                b:SetSize(110, 22)
                b:SetPoint("TOPLEFT", 240, y)
                b:SetScript("OnClick", function()
                    local idx = 1
                    for i, v in ipairs(c.values) do if v == db[c.key] then idx = i end end
                    db[c.key] = c.values[idx % #c.values + 1]
                    Changed(c.key)
                end)
                table.insert(refreshers, function()
                    local v = tostring(db[c.key] or "")
                    b:SetText(v:sub(1, 1):upper() .. v:sub(2))
                end)
                y = y - 30

            elseif c.type == "info" then
                local fs = Label(panel, "", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", 24, y - 2)
                fs:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
                fs:SetJustifyH("LEFT")
                table.insert(refreshers, function()
                    local lines = c.lines()
                    fs:SetText(type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or ""))
                end)
                y = y - (c.height or 40)

            elseif c.type == "button" then
                local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
                b:SetSize(170, 24)
                b:SetPoint("TOPLEFT", 20, y)
                b:SetText(c.label)
                b:SetScript("OnClick", function()
                    c.func()
                    Changed(nil)
                end)
                if c.dynamicLabel then
                    table.insert(refreshers, function() b:SetText(c.dynamicLabel()) end)
                end
                y = y - 32
            end
        end

        if spec.slash then
            local foot = Label(panel, "Type " .. spec.slash .. " help in chat for slash commands.", "GameFontDisableSmall")
            foot:SetPoint("TOPLEFT", 20, y - 10)
        end
    end

    panel:SetScript("OnShow", function()
        Build()
        for _, r in ipairs(refreshers) do r() end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, spec.title)
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    function ns.RefreshOptions()
        if built then for _, r in ipairs(refreshers) do r() end end
    end

    function ns.OpenOptions()
        if InCombatLockdown() then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. spec.title .. ":|r settings can't be opened in combat.")
            return
        end
        local cat = ns.settingsCategory
        if cat and Settings and Settings.OpenToCategory then
            local id = (cat.GetID and cat:GetID()) or cat.ID
            if not pcall(Settings.OpenToCategory, id) then pcall(Settings.OpenToCategory, cat) end
        elseif InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    end

    return panel
end
