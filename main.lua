local beekeeping = require("beekeeping")
local fgui = require("fgui")
local component = require("component")
local term = require("term")
local os = require("os")
local event = require("event")
local keyboard = require("keyboard")
local bit32 = require("bit32")

local gpu = component.gpu
if not gpu then error("Cannot start without GPU") return end

term.clear()

local w, h = gpu.getResolution()
local needRedraw = true
local function clearScreen()
    gpu.fill(1, 1, w, h, " ")
    needRedraw = true
end

print("BEEKEEPING AUTOMATION BY LOPTR")
print("Connecting to robot...")

local chk = beekeeping.connectRobot()

if not chk then error("Could not connect to robot") return end

print("Loading definitions...")
chk = beekeeping.loadData()
if chk then print("Save data successfully loaded!") else print("Save data not loaded") end

print("Done! Starting main loop. Beeware of bad puns.")
os.sleep(3)

clearScreen()
local running = true
local scroll = 0
local maxScroll = 0
local kbSuspended = false

local function colorAverage(col)
    local r = bit32.rshift(bit32.band(col, 0xFF0000), 16)
    local g = bit32.rshift(bit32.band(col, 0x00FF00), 8)
    local b = bit32.band(col, 0x0000FF)
    return math.max(r, g, b)
end

local function drawStringWithBg(x, y, str)
    local oldBg = gpu.getBackground()
    local oldFg = gpu.getForeground()
    for i = 1, #str do
        local xx = x + i - 1
        local yy = y
        while xx > w do
            xx = xx - w + x
            yy = yy + 1
        end
        local _, _, bg, _, _ = gpu.get(xx, yy)
        gpu.setBackground(bg)
        local bgAvg = colorAverage(bg)
        if bgAvg <= 128 then gpu.setForeground(0xFFFFFF) else gpu.setForeground(0x1C1C1C) end
        
        gpu.set(xx, yy, string.sub(str, i, i))
    end
    gpu.setBackground(oldBg)
    gpu.setForeground(oldFg)
end

local function padStr(str, len)
    return string.rep(" ", len - #str) .. str
end

local function numToStr(num)
    if num <= 999999 then return padStr(string.format("%.0f", num), 8) end
    if num <= 999999999 then return padStr(string.format("%.2f M", num / 1000000), 8) end
    if num <= 999999999999 then return padStr(string.format("%.2f G", num / 1000000000), 8) end
    return tostring(num)
end

local dialogOptions = {
    x = w / 2 - 25,
    y = h / 2 - 4,
    width = 50,
    height = 8,
    background = 0x014969,
    foreground = 0xFFFFFF
}

local function createNewDefinition()
    local meAddr = beekeeping.getBeeMeAddr()
    if not meAddr then return end
    local me = component.proxy(meAddr)
    if not me then return end

    local item = fgui.chooseValueDialog("Create Definition for which item? (case-sensitive)", "string", dialogOptions)
    local species = fgui.chooseValueDialog("What Bee Species produces this item?", "string", dialogOptions)
    local chk = (#me.getItemsInNetwork({ label = species.." Drone" }) > 0)
    if not chk then
        fgui.chooseValueDialog("No "..species.." Drone found. Make sure it is in production subnet", "string", dialogOptions)
        return
    end
    chk = (#me.getItemsInNetwork({ label = species.." Princess" }) > 0)
    if not chk then
        fgui.chooseValueDialog("No "..species.." Princess found. Make sure it is in production subnet", "string", dialogOptions)
        return
    end
    local min = fgui.chooseValueDialog("Choose amount to maintain ("..item..")", "int", dialogOptions)
    local max = fgui.chooseValueDialog("Choose value to stop producing ("..item..")", "int", dialogOptions)
    if max < min then
        fgui.chooseValueDialog("Maximum value cannot be smaller than minimum", "string", dialogOptions)
        return
    end

    beekeeping.addDefinition(species, item, min, max, 0)
end

local function onBtSetMainMeAddr()
    local addr = fgui.chooseValueDialog("Set the Main ME Net Interface Address", "string", dialogOptions)
    beekeeping.setMainMeAddr(addr)
    needRedraw = true
end

local function onBtSetBeeMeAddr()
    local addr = fgui.chooseValueDialog("Set the Main ME Net Interface Address", "string", dialogOptions)
    beekeeping.setBeeMeAddr(addr)
    needRedraw = true
end

local lastError = ""
local defWidth = 3 * w / 4 - 1
local btx = w * 7 / 8 - 10
local bty = 4
local btw = 20
local bth = 2
local btOffset = 4
local defCache = {}
local function initialScreenDraw()
    clearScreen()
    needRedraw = false
    fgui.deleteAllButtons()
    fgui.createButton("btCreateDef", btx, bty, btx + btw, bty + bth, function() createNewDefinition() needRedraw = true drawScreen() end, "Create Definition", 0xA0A0A0, 0, false)
    fgui.createButton("btSetMainMeAddr", btx, bty + btOffset, btx + btw, bty + btOffset + bth, onBtSetMainMeAddr, "Set Main ME Address", 0xA0A0A0, 0, false)
    fgui.createButton("btSetBeeMeAddr", btx, bty + 2 * btOffset, btx + btw, bty + 2 * btOffset + bth, onBtSetBeeMeAddr, "Set Bee ME Address", 0xA0A0A0, 0, false)

    gpu.setForeground(0xFFFFFF)
    gpu.setBackground(0xFFFFFF)
    gpu.fill(w * 3 / 4, 1, 1, h, " ")

    for _, v in pairs(defCache) do
        v.needsUpdate = true
    end
end

local function drawScreen()
    if needRedraw then initialScreenDraw() end

    local definitions = beekeeping.getDefinitions()

    local progressBackColor = 0x616111
    local progressColor = 0xDBDB00
    local idleBackColor = 0x092601
    local idleColor = 0x30DB00
    local susBackColor = 0x290000
    local susColor = 0xAD0C0C
    local minMarkColor = 0x0473D4

    for i, def in ipairs(definitions) do
        local inMe = def.current or 0

        if not defCache[def.item] or defCache[def.item].last ~= inMe or defCache[def.item].needsUpdate then
            if not defCache[def.item] then defCache[def.item] = {} end
            defCache[def.item].last = inMe
            defCache[def.item].needsUpdate = false;

            local percent = inMe / def.max
            if percent > 1 then percent = 1 end

            local minMark = math.floor(defWidth * def.maintain / def.max)

            local y = i + scroll

            if y >= 1 or y <= h then
                if def.hiveIndex then gpu.setBackground(progressBackColor) elseif def.suspended then gpu.setBackground(susBackColor) else gpu.setBackground(idleBackColor) end
                gpu.fill(1, y, defWidth, 1, " ")
                if def.hiveIndex then gpu.setBackground(progressColor) elseif def.suspended then gpu.setBackground(susColor) else gpu.setBackground(idleColor) end
                gpu.fill(1, y, percent * defWidth, 1, " ")
                gpu.setBackground(minMarkColor)
                gpu.fill(1, y, minMark, 1, " ")
                local str = def.item.." ("..def.species.." Bee)"
                if def.ignoreJubilance then str = str.." [Ignore Jubilance]" end
                drawStringWithBg(3, y, str)
                local inMeStr = numToStr(inMe)
                local minStr = numToStr(def.maintain)
                local maxStr = numToStr(def.max)
                drawStringWithBg(w / 2, y, inMeStr .. "   [ "..minStr.." | "..maxStr.." ]")
            end
        end

        if i > h then maxScroll = i - h end
    end
    gpu.setBackground(0)
    
    gpu.set(defWidth + 4, h - 18, "Main ME Address:")
    gpu.set(defWidth + 4, h - 17, beekeeping.getMainMeAddr() or "None")
    gpu.set(defWidth + 4, h - 16, "Bee ME Address:")
    gpu.set(defWidth + 4, h - 15, beekeeping.getBeeMeAddr() or "None")

    gpu.set(defWidth + 4, h - 10, "Last error:")
    drawStringWithBg(defWidth + 4, h - 9, lastError)
end

local function onClick(_, _, x, y, button, _)
    if x > defWidth then return end
    local index = y + scroll
    local def = beekeeping.getDefinitions()[index]
    if not def then return end

    if button == 1 then
        if keyboard.isControlDown() then
            beekeeping.toggleJubilance(index)
            defCache[def.item].needsUpdate = true
        else
            local confirm = fgui.chooseValueDialog("Delete "..def.item.."?", "bool", dialogOptions)
            if not confirm then drawScreen() return end
            beekeeping.removeDefinition(index)
        end
        drawScreen()
    elseif button == 0 then
        if keyboard.isControlDown() then
            lastError = "Toggle Suspension"
            beekeeping.toggleSuspension(index)
            defCache[def.item].needsUpdate = true
        else
            local min = fgui.chooseValueDialog("Choose new amount to maintain ("..def.item..")", "int", dialogOptions)
            local max = fgui.chooseValueDialog("Choose new value to stop producing ("..def.item..")", "int", dialogOptions)
            if max < min then
                fgui.chooseValueDialog("Maximum value cannot be smaller than minimum", "string", dialogOptions)
                return
            end
            beekeeping.adjustDefinition(index, min, max)
            defCache[beekeeping.getDefinitions()[index].item].needsUpdate = true
            needRedraw = true;
        end
        drawScreen()
    end
end

local function onScroll(_, _, x, y, dir, _)
    if x > defWidth then return end
    scroll = scroll - dir
    if scroll < 0 then scroll = 0 end
    if scroll > maxScroll then scroll = maxScroll end
    drawScreen()
end

local function onKeyDown(_, _, char, code, _)
    if kbSuspended then return end
    if code == keyboard.keys.q and keyboard.isControlDown() then
        running = false
    elseif code == keyboard.keys.down then
        onScroll(nil, nil, 1, 1, -1, nil)
    elseif code == keyboard.keys.up then
        onScroll(nil, nil, 1, 1, 1, nil)
    end
end

drawScreen()

local ev = {}
table.insert(ev, event.listen("drop", onClick))
table.insert(ev, event.listen("scroll", onScroll))
table.insert(ev, event.listen("key_down", onKeyDown))

while running do
    local chk, err = beekeeping.tick()
    if not chk and err then lastError = err end
    drawScreen()
    os.sleep(1)
end

fgui.deleteAllButtons(false)

for _, elem in ipairs(ev) do
    event.cancel(elem)
end

beekeeping.disconnectRobot()
beekeeping.saveData()
clearScreen()