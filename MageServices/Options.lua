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
--   credit = "optional line shown under the version",
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

    -- Options live in a scrolling area so long pages never spill out of the window.
    -- Built from plain frames (no templates) so it behaves the same on every client.
    -- the page itself also clips, so nothing can draw below the options window
    if panel.SetClipsChildren then panel:SetClipsChildren(true) end

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 400)
    scroll:SetScrollChild(content)

    -- scroll bar: a track with a draggable thumb
    local bar = CreateFrame("Slider", nil, panel)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    bar:SetWidth(10)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    if bar.SetValueStep then bar:SetValueStep(1) end

    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.35)

    bar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(10, 48)
    thumb:SetVertexColor(0.75, 0.75, 0.75, 0.9)

    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)

    local function UpdateRange()
        local maxV = math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
        bar:SetMinMaxValues(0, maxV)
        if bar:GetValue() > maxV then bar:SetValue(maxV) end
        -- size the thumb to how much of the page is visible
        local h, total = scroll:GetHeight() or 0, content:GetHeight() or 1
        if total > 0 and h > 0 then thumb:SetHeight(math.max(24, (bar:GetHeight() or h) * math.min(1, h / total))) end
        bar:SetShown(maxV > 0)
    end

    local function Wheel(_, delta)
        local lo, hi = bar:GetMinMaxValues()
        bar:SetValue(math.min(hi, math.max(lo, bar:GetValue() - delta * 40)))
    end
    for _, f in ipairs({ panel, scroll, content }) do
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", Wheel)
    end
    scroll:SetScript("OnSizeChanged", function() UpdateRange() end)

    local function Changed(key)
        if spec.onChange then spec.onChange(key) end
        for _, r in ipairs(refreshers) do r() end
    end

    local function Build()
        if built then return end
        built = true

        local icon = content:CreateTexture(nil, "ARTWORK")
        icon:SetSize(40, 40)
        icon:SetPoint("TOPLEFT", 16, -16)
        icon:SetTexture(spec.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local title = Label(content, spec.title, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)

        local sub = Label(content, "Version " .. ns.version .. (spec.about and ("  -  " .. spec.about) or ""), "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        sub:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        sub:SetJustifyH("LEFT")

        if spec.credit then
            local credit = Label(content, spec.credit, "GameFontDisableSmall")
            credit:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -4)
        end

        local y = -86
        for _, c in ipairs(spec.controls) do
            if c.type == "header" then
                y = y - 6
                local h = Label(content, c.label, "GameFontNormal")
                h:SetPoint("TOPLEFT", 16, y)
                y = y - 22

            elseif c.type == "check" then
                local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
                cb:SetSize(26, 26)
                cb:SetPoint("TOPLEFT", 20, y)
                local l = Label(content, c.label)
                l:SetPoint("LEFT", cb, "RIGHT", 4, 1)
                cb:SetScript("OnClick", function(self)
                    db[c.key] = self:GetChecked() and true or false
                    Changed(c.key)
                end)
                table.insert(refreshers, function() cb:SetChecked(db[c.key] and true or false) end)
                y = y - 30

            elseif c.type == "range" then
                local l = Label(content, c.label)
                l:SetPoint("TOPLEFT", 24, y - 4)

                local minus = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
                minus:SetSize(26, 22)
                minus:SetPoint("TOPLEFT", 240, y)
                minus:SetText("-")

                local value = Label(content, "")
                value:SetWidth(44)
                value:SetPoint("LEFT", minus, "RIGHT", 4, 0)

                local plus = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
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
                local l = Label(content, c.label)
                l:SetPoint("TOPLEFT", 24, y - 4)
                local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
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

            elseif c.type == "dropdown" then
                -- c.options() returns { { value = , label = }, ... }; c.preview(value) is optional
                local l = Label(content, c.label)
                l:SetPoint("TOPLEFT", 24, y - 4)

                local function LabelFor(v)
                    for _, o in ipairs(c.options()) do if o.value == v then return o.label end end
                    return tostring(v)
                end
                local function Pick(v)
                    db[c.key] = v
                    if c.onSelect then c.onSelect(v) end
                    Changed(c.key)
                end

                local ok, dd = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
                if ok and dd and dd.SetupMenu then
                    dd:SetWidth(180)
                    dd:SetPoint("TOPLEFT", 240, y + 2)
                    dd:SetupMenu(function(_, root)
                        if root.SetScrollMode then root:SetScrollMode(320) end
                        for _, o in ipairs(c.options()) do
                            root:CreateRadio(o.label,
                                function() return db[c.key] == o.value end,
                                function() Pick(o.value) end)
                        end
                    end)
                    table.insert(refreshers, function() if dd.GenerateMenu then dd:GenerateMenu() end end)
                else
                    -- older clients: a button that steps through the list
                    dd = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
                    dd:SetSize(180, 22)
                    dd:SetPoint("TOPLEFT", 240, y)
                    dd:SetScript("OnClick", function()
                        local opts, idx = c.options(), 1
                        for i, o in ipairs(opts) do if o.value == db[c.key] then idx = i end end
                        Pick(opts[idx % #opts + 1].value)
                    end)
                    table.insert(refreshers, function() dd:SetText(LabelFor(db[c.key])) end)
                end

                if c.preview then
                    local play = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
                    play:SetSize(50, 22)
                    play:SetPoint("LEFT", dd, "RIGHT", 6, 0)
                    play:SetText("Play")
                    play:SetScript("OnClick", function() c.preview(db[c.key]) end)
                end
                y = y - 32

            elseif c.type == "info" then
                local fs = Label(content, "", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", 24, y - 2)
                fs:SetPoint("RIGHT", content, "RIGHT", -16, 0)
                fs:SetJustifyH("LEFT")
                table.insert(refreshers, function()
                    local lines = c.lines()
                    fs:SetText(type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or ""))
                end)
                y = y - (c.height or 40)

            elseif c.type == "button" then
                local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
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
            local foot = Label(content, "Type " .. spec.slash .. " help in chat for slash commands.", "GameFontDisableSmall")
            foot:SetPoint("TOPLEFT", 20, y - 10)
            y = y - 30
        end
        content:SetHeight(-y + 16)
        UpdateRange()
    end

    panel:SetScript("OnShow", function()
        -- if the options window hasn't sized the page, fill whatever it's placed in
        if (panel:GetHeight() or 0) < 10 and panel:GetParent() then panel:SetAllPoints(panel:GetParent()) end
        local w = scroll:GetWidth()
        if w and w > 100 then content:SetWidth(w - 4) end
        Build()
        UpdateRange()
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
