-- Craft Services: tidying up your group after a job (optional).
--
-- Once a customer has paid (or the job is done), they're removed from the group after a
-- short wait, so the next customer has room. Only people you invited from Craft Services,
-- only while you lead the group, and never while you're still trading with them.

local _, ns = ...

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local INVITE_WINDOW = 60 * 60

local function Leader()
    if not UnitIsGroupLeader then return false end
    local ok, v = pcall(UnitIsGroupLeader, "player")
    return ok and not IsSecret(v) and v and true or false
end

local function Uninvite(name)
    if C_PartyInfo and C_PartyInfo.UninviteUnit then
        return pcall(C_PartyInfo.UninviteUnit, name)
    elseif UninviteUnit then
        return pcall(UninviteUnit, name)
    end
    return false
end

local due = {} -- [key] = { at, sender }

-- Called when a request turns "paid" or "done".
function ns.JobFinished(key, sender)
    if not (ns.db and ns.db.kickAfterJob) or not key then return end
    local inv = ns.invited and ns.invited[key]
    if not inv or GetTime() - inv > INVITE_WINDOW then return end
    due[key] = { at = GetTime() + (ns.db.kickDelay or 20), sender = sender }
end

local function Check()
    if not next(due) then return end
    local now = GetTime()
    for key, d in pairs(due) do
        if now >= d.at then
            due[key] = nil
            local trade = ns.CurrentTrade and ns.CurrentTrade()
            local busy = trade and trade.key == key
            if busy then
                due[key] = { at = now + 10, sender = d.sender } -- trading again: wait
            elseif InCombatLockdown() or (IsInInstance and IsInInstance()) then
                due[key] = { at = now + 10, sender = d.sender } -- group changes wait for combat to end
            elseif ns.InGroupWith(key) and Leader() and not ns.IsTestMode() then
                local name = d.sender or key
                if Uninvite(name) then
                    ns.invited[key] = nil
                    ns.Print(("removed %s from the group (job done)."):format(ns.DisplayName(name) or name))
                end
            end
        end
    end
end
ns.CheckKicks = Check
ns.kicksDue = due

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.NewTicker(1, Check)
end)
