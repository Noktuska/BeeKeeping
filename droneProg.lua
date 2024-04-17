local component = require("component")
local event = require("event")
local sides = require("sides")

local modem = component.modem
local redstone = component.redstone
local inv = component.inventory_controller
local bee = component.beekeeper

if not modem then error("No modem component installed") return end
if not redstone then error("No redstone component installed") return end
if not inv then error("No inventory controller component installed") return end
if not bee then error("No beekeeping component installed") return end

local port = 122
modem.open(port)

local princessSlot = 1
local droneSlot = 2
local honeySlot = 4
local upgradeSlot1 = 5
local upgradeSlot2 = 6

local apiaryArray = {}

-- TODO ADJUST THESE
local upgradeCount = {
    warm = 2,
    hot = 3,
    cold = 3,
    icy = 6,
    arid = 5,
    damp = 1
}

::reconnect::

print("Accepting incoming connection requests...")

local connectedModem = nil
while not connectedModem do
    local _, _, sender, _, _, msg = event.pullFiltered(function(str) return str == "modem_message" end)
    if msg == "try_connect" then connectedModem = sender end
end

print("Connected to "..connectedModem..". Sending Response...")

modem.send(connectedModem, port, "connect_accept")

print("Setting up internal data...")

local robot = component.robot

robot.setLightColor(0x00FF00)

local running = true

local function pullItemFromInventory(side, label, amount)
    if label == nil or amount == 0 then return 0 end

    local numSlots = inv.getInventorySize(side)

    for i = 1, numSlots do
        local stack = inv.getStackInSlot(side, i)
        if stack and stack.label == label then
            local sucked = inv.suckFromSlot(side, i, amount)
            if sucked then return sucked else return 0 end
        end
    end

    return 0
end

local function getUpgrades(temp, hum)
    local res = { { name = "", amount = 0 }, { name = "", amount = 0 } }
    if temp == "Hellish" then
        res[1].name = "HELL Emulation Upgrade"
        res[1].amount = 1
    elseif temp == "Warm" or temp == "Hot" then
        res[1].name = "Heater Upgrade"
        res[1].amount = (temp == "Warm" and upgradeCount.warm or upgradeCount.hot)
    elseif temp == "Cold" or temp == "Icy" then
        res[1].name = "Cooler Upgrade"
        res[1].amount = (temp == "Cold" and upgradeCount.cold or upgradeCount.icy)
    end
    if hum == "Arid" and temp ~= "Hellish" then
        res[2].name = "Dryer Upgrade"
        res[2].amount = upgradeCount.arid
    elseif hum == "Damp" then
        res[2].name = "Humidifier Upgrade"
        res[2].amount = upgradeCount.damp + (temp == "Hellish" and upgradeCount.arid or 0)
    elseif hum == "Normal" and temp == "Hellish" then
        res[2].name = "Humidifier Upgrade"
        res[2].amount = upgradeCount.arid
    end
    return res
end

local function emptyInventory()
    local chk
    robot.select(princessSlot)
    if robot.count() > 0 then repeat chk = inv.dropIntoSlot(sides.front, 3) until chk end
    robot.select(droneSlot)
    if robot.count() > 0 then repeat chk = inv.dropIntoSlot(sides.front, 3) until chk end
    robot.select(upgradeSlot1)
    if robot.count() > 0 then repeat chk = inv.dropIntoSlot(sides.front, 3) until chk end
    robot.select(upgradeSlot2)
    if robot.count() > 0 then repeat chk = inv.dropIntoSlot(sides.front, 3) until chk end
end

-- Ensures the robot moves one step forward, even if entities are in the way
local function ensureMove(side)
    local chk, err
    side = side or sides.front
    repeat
        chk, err = robot.move(side)
    until chk == true or err == "solid"
end

local function findNextSolid()
    local chk, err
    repeat
        chk, err = robot.move(sides.front)
    until chk == nil and err == "solid" -- Check for "solid" incase some idiot runs infront of the robot
end

local function startBreeding(ignoreJubilance)
    local chk = false
    local err = ""

    print("Started breeding process")
    print("Checking honey...")

    -- Try to get new honey and check if any is still available
    robot.select(honeySlot)
    local honeyCount = robot.count()
    chk = inv.suckFromSlot(sides.front, 9, 64 - honeyCount)
    if robot.count() == 0 then
        return false, "No honey to analyze bee for jubilance"
    end

    print("Pulling Bees...")
    -- Pull Princess and Drone out of ME
    robot.select(princessSlot)
    repeat chk = inv.suckFromSlot(sides.front, 1, 1) until chk
    robot.select(droneSlot)
    repeat chk = inv.suckFromSlot(sides.front, 2, 1) until chk

    -- Analyze Princess for jubilance
    if not ignoreJubilance then
        local princessStack = inv.getStackInInternalSlot(princessSlot).individual

        print("Analyzing princess...")
        if not princessStack.isAnalyzed then
            robot.select(princessSlot)
            bee.analyze(honeySlot)
            princessStack = inv.getStackInInternalSlot(princessSlot).individual
        end

        -- Get needed upgrades to achieve jubilance
        local tempStr = princessStack.active.species.temperature
        local humidityStr = princessStack.active.species.humidity

        print("Jubilance: "..tempStr..", "..humidityStr)

        local upgrades = getUpgrades(tempStr, humidityStr)

        print("Upgrades: "..upgrades[1].name.." ["..upgrades[1].amount.."], "..upgrades[2].name.." ["..upgrades[2].amount.."]")

        if upgrades[1].name and upgrades[1].amount > 0 then
            robot.select(upgradeSlot1)
            local pulled = pullItemFromInventory(sides.front, upgrades[1].name, upgrades[1].amount)
            print("Pulled "..pulled.." for first upgrade")
            -- Not enough upgrades available, return bees and upgrades and abort
            if pulled < upgrades[1].amount then
                emptyInventory()
                return false, "Not enough "..upgrades[1].name.." [needed "..upgrades[1].amount.."] for jubilance"
            end
        end

        if upgrades[2].name and upgrades[2].amount > 0 then
            robot.select(upgradeSlot2)
            local pulled = pullItemFromInventory(sides.front, upgrades[2].name, upgrades[2].amount)
            print("Pulled "..pulled.." for second upgrade")
            -- Not enough upgrades available, return bees and upgrades and abort
            if pulled < upgrades[2].amount then
                emptyInventory()
                return false, "Not enough "..upgrades[1].name.." [needed "..upgrades[1].amount.."] for jubilance"
            end
        end
    end

    robot.turn(true)
    robot.turn(true)
    ensureMove()
    robot.turn(false)
    ensureMove()
    robot.turn(true)

    -- Move to apiary array
    findNextSolid()

    -- Move ontop of first apiary
    ensureMove(sides.up)

    -- Find next industrial apiary that is free
    local found = false
    local currentApiaryIndex = 0
    local onSecondRow = false
    while not found do
        ensureMove()
        currentApiaryIndex = currentApiaryIndex + 1
        if not apiaryArray[currentApiaryIndex] then found = true end
        -- If at end of row we need to move around
        if not inv.getInventoryName(sides.down) then
            if onSecondRow then
                ensureMove(sides.down)
                robot.turn(true)
                ensureMove()
                robot.turn(false)
                findNextSolid()
                emptyInventory()
                return false, "No available apiary"
            end
            robot.turn(true)
            ensureMove()
            ensureMove()
            robot.turn(true)
            ensureMove()
            onSecondRow = true
        end
    end

    -- Put in upgrades
    robot.select(upgradeSlot1)
    bee.addIndustrialUpgrade(sides.down)
    robot.select(upgradeSlot2)
    bee.addIndustrialUpgrade(sides.down)

    -- Put in bees
    robot.select(princessSlot)
    bee.swapQueen(sides.down)
    robot.select(droneSlot)
    bee.swapDrone(sides.down)

    -- Return to initial position
    robot.turn(true)
    ensureMove()
    robot.turn(not onSecondRow)
    repeat
        ensureMove()
        chk, err = robot.detect(sides.down)
    until not chk or err ~= "solid"

    ensureMove(sides.down)
    findNextSolid()

    apiaryArray[currentApiaryIndex] = true
    return currentApiaryIndex
end

local function stopBreeding(hiveIndex)
    if not hiveIndex then return false, "No index provided" end

    robot.turn(true)
    robot.turn(true)
    ensureMove()
    robot.turn(false)
    ensureMove()
    robot.turn(true)
    findNextSolid()
    ensureMove(sides.up)
    
    local onSecondRow = false
    for i = 1, hiveIndex do
        ensureMove()
        if not inv.getInventoryName(sides.down) then
            if onSecondRow then
                ensureMove(sides.down)
                robot.turn(true)
                ensureMove()
                robot.turn(false)
                findNextSolid()
                emptyInventory()
                return false, "Index out of range"
            end
            robot.turn(true)
            ensureMove()
            ensureMove()
            robot.turn(true)
            ensureMove()
            onSecondRow = true
        end
    end

    -- Disable machine via controller cover
    redstone.setOutput(sides.down, 15)
    -- Try extracting princess and drone from input slot
    local chkPrincess, chkDrone
    repeat
        os.sleep(2)
        if not chkPrincess then
            robot.select(princessSlot)
            bee.swapQueen(sides.down)
            chkPrincess = (robot.count() > 0)
        end
        if not chkDrone then
            robot.select(droneSlot)
            bee.swapDrone(sides.down)
            chkDrone = (robot.count() > 0)
        end
    until chkPrincess and chkDrone
    redstone.setOutput(sides.down, 0)

    -- Remove any potential upgrades
    robot.select(upgradeSlot1)
    for i = 1, 4 do
        local stack = bee.getIndustrialUpgrade(sides.down, i)
        if stack then
            if stack.label == "Heater Upgrade" or stack.label == "Cooler Upgrade" or stack.label == "Dryer Upgrade" or stack.label == "Humidifier Upgrade" or stack.label == "HELL Emulation Upgrade" then
                bee.removeIndustrialUpgrade(sides.down, i)
                robot.select(upgradeSlot2)
            end
        end
    end

    -- Move back to initial position
    robot.turn(true)
    ensureMove()
    robot.turn(not onSecondRow)
    local chk, err
    repeat
        ensureMove()
        chk, err = robot.detect(sides.down)
    until not chk or err ~= "solid"

    ensureMove(sides.down)
    findNextSolid()

    -- Empty inventory
    emptyInventory()
    apiaryArray[hiveIndex] = false
    return true
end

local function onModemMessage(msg, ...)
    local args = {...}
    local res = nil
    if msg == "startBreeding" then
        res = { startBreeding(args[1]) }
    elseif msg == "stopBreeding" then
        res = { stopBreeding(args[1]) }
    elseif msg == "disconnect" then
        running = false
    end
    if res then
        modem.send(connectedModem, port, table.unpack(res))
    end
end

local ev = event.listen("modem_message", function(_, _, sender, _, _, msg, ...)
    print("Received ["..sender.."]: "..msg)
    if sender == connectedModem then onModemMessage(msg, ...) end
end)

print("Done! Awaiting commands by connected systems...")

while running do
    os.sleep(1)
end

event.cancel(ev)

robot.setLightColor(0xFF0000)

goto reconnect