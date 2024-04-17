local component = require("component")
local event = require("event")
local os = require("os")
local serialization = require("serialization")
local sides = require("sides")

local beekeeping = {}

local definitions = {}

local mainMeAddr = nil
local beeMeAddr = nil
local robotAddr = nil
local port = 122

local curTickIndex = 1

local function insertDefinition(data)
    local template = {
        species = "",
        item = "",
        current = 0,
        maintain = 0,
        max = 0,
        priority = 0,
        ignoreJubilance = false,

        reqTicks = 0,
        hiveIndex = nil,
        suspended = false
    }

    for key, _ in pairs(template) do
        if data[key] then template[key] = data[key] end
    end

    table.insert(definitions, template)
end

local saveFileName = "beekeepingData.data"
function beekeeping.saveData()
    local f = io.open(saveFileName, "w")
    if not f then return false end

    local data = {}
    data.mainMeAddr = mainMeAddr
    data.beeMeAddr = beeMeAddr
    data.definitions = definitions

    f:write(serialization.serialize(data))

    f:close()
    return true
end

function beekeeping.loadData()
    local f = io.open(saveFileName)
    if not f then return false end

    local str = f:read(math.huge)
    if not str then f:close() return false end
    local data = serialization.unserialize(str)

    mainMeAddr = data.mainMeAddr
    beeMeAddr = data.beeMeAddr
    definitions = {}
    for _, elem in pairs(data.definitions) do
        insertDefinition(elem)
    end

    f:close()
    return true
end

function beekeeping.connectRobot()
    local modem = component.modem
    if not modem then return false end

    if not modem.isOpen(port) then modem.open(port) end

    local ev = event.listen("modem_message", function(_, _, sender, _, _, msg)
        if msg == "connect_accept" then robotAddr = sender end
    end)

    while not robotAddr do
        modem.broadcast(port, "try_connect")
        os.sleep(3)
    end

    event.cancel(ev)

    return robotAddr ~= nil
end

function beekeeping.disconnectRobot()
    local modem = component.modem
    if not modem or not robotAddr then return false end

    local chk = modem.send(robotAddr, port, "disconnect")

    if chk then robotAddr = nil end
    return robotAddr == nil
end

function beekeeping.setMainMeAddr(addr)
    mainMeAddr = addr
end

function beekeeping.getMainMeAddr()
    return mainMeAddr
end

function beekeeping.setBeeMeAddr(addr)
    beeMeAddr = addr
end

function beekeeping.getBeeMeAddr()
    return beeMeAddr
end

function beekeeping.addDefinition(species, item, maintain, max, priority)
    if not mainMeAddr then return nil, "No Main ME Network address given" end

    local me = component.proxy(mainMeAddr)
    if not me then return nil, "Not connected to ME Network" end

    local inNet = me.getItemsInNetwork({ label = item })
    local warning = false
    if #inNet == 0 then warning = true end

    insertDefinition({
        species = species,
        item = item,
        current = 0,
        maintain = maintain,
        max = max,
        priority = priority,
        ignoreJubilance = false,

        reqTicks = 0,
        hiveIndex = nil,
        suspended = false
    })

    return not warning
end

function beekeeping.removeDefinition(index)
    return table.remove(definitions, index) ~= nil
end

function beekeeping.adjustDefinition(index, min, max)
    definitions[index].maintain = min
    definitions[index].max = max
end

function beekeeping.toggleSuspension(index)
    definitions[index].suspended = not definitions[index].suspended
end

function beekeeping.toggleJubilance(index)
    definitions[index].ignoreJubilance = not definitions[index].ignoreJubilance
end

function beekeeping.isOnline()
    local r = component.redstone
    if not r then return false end
    return r.getInput(sides.down) > 0
end

local function startBreeding(me, species, ignoreJubilance)
    local db = component.database
    local modem = component.modem
    if not db then return nil, "No database found" end
    if not modem then return nil, "No modem found" end
    if not robotAddr then return nil, "No robot connected" end

    local droneLabel = species.." Drone"
    local princessLabel = species.." Princess"
    db.clear(1)
    db.clear(2)
    local chk = me.store({ label = princessLabel }, db.address, 1, 1)
    if not chk then return nil, species.." not in bee subnet" end
    chk = me.store({ label = droneLabel }, db.address, 2, 1)
    if not chk then return nil, species.." not in bee subnet" end

    me.setInterfaceConfiguration(1, db.address, 1, 1)
    me.setInterfaceConfiguration(2, db.address, 2, 1)

    if (not modem.isOpen(port)) then modem.open(port) end

    local resp = nil
    local ev = event.listen("modem_message", function(_, _, sender, _, _, ...)
        if sender == robotAddr then resp = { ... } end
    end)

    modem.send(robotAddr, port, "startBreeding", ignoreJubilance)
    while not resp do os.sleep(1) end

    event.cancel(ev)

    me.setInterfaceConfiguration(1)
    me.setInterfaceConfiguration(2)

    return table.unpack(resp)
end

local function stopBreeding(hiveIndex)
    local modem = component.modem
    if not modem then return nil, "No modem found" end
    if not robotAddr then return nil, "No robot connected" end
    if not modem.isOpen(port) then modem.open(port) end

    local resp = nil
    local ev = event.listen("modem_message", function(_, _, sender, _, _, ...)
        if sender == robotAddr then resp = { ... } end
    end)

    modem.send(robotAddr, port, "stopBreeding", hiveIndex)
    while not resp do os.sleep(1) end

    event.cancel(ev)

    return table.unpack(resp)
end

function beekeeping.tick()
    if not mainMeAddr then return nil, "No Main ME Network address given" end
    local me = component.proxy(mainMeAddr)
    if not me or not beekeeping.isOnline() then return nil, "Not connected to ME Network" end

    if not beeMeAddr then return nil, "No Bee ME Network address given" end
    local beeme = component.proxy(beeMeAddr)
    if not beeme then return nil, "Not connected to ME Network" end

    local err = nil
    local doneWork = false
    local noHivesAvailable = false

    local def = definitions[curTickIndex]
    local amount = def.current or 0
    if not def.suspended then
        local stack = me.getItemsInNetwork({ label = def.item })[1]
        if stack then amount = stack.size else amount = 0 end
        def.current = amount
    end
    if not noHivesAvailable and amount < def.maintain and not def.hiveIndex and not def.suspended then
        if def.reqTicks < 1 then
            def.reqTicks = def.reqTicks + 1
        else
            local index = nil
            index, err = startBreeding(beeme, def.species, def.ignoreJubilance)
            if index then
                def.hiveIndex = index
                doneWork = true
            else
                noHivesAvailable = true
                def.suspended = true
            end
            def.reqTicks = 0
        end
    elseif (amount > def.max or def.suspended) and def.hiveIndex then
        stopBreeding(def.hiveIndex)
        def.hiveIndex = nil
        doneWork = true
    elseif def.reqTicks > 0 then def.reqTicks = 0 end

    curTickIndex = curTickIndex + 1
    if curTickIndex > #definitions then curTickIndex = 1 end

    if doneWork then beekeeping.saveData() end

    return not noHivesAvailable, err
end

function beekeeping.getDefinitions()
    local cpy = {}
    for k, v in ipairs(definitions) do
        cpy[k] = v
    end
    return cpy
end

return beekeeping