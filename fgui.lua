local fgui = {}

fgui.debug_gpu = nil
fgui.debug_counter = 1
fgui.setupDebug = function(primary_gpu, primary_screen, debug_gpu, debug_screen)
    local component = require("component")
    if not component.proxy(primary_gpu) or not component.proxy(debug_gpu) then
        return
    end
    component.setPrimary("gpu", primary_gpu)
    component.gpu.bind(primary_screen, true)
    fgui.debug_gpu = component.proxy(debug_gpu)
    fgui.debug_gpu.bind(debug_screen, true)
    local width, height = fgui.debug_gpu.getResolution()
    fgui.debug_gpu.fill(1,1,width,height," ")
end

fgui.d_print = function(msg, always)
    if fgui.debug_gpu then
        fgui.debug_gpu.set(1, fgui.debug_counter, tostring(msg))
        fgui.debug_counter = fgui.debug_counter + 1
        local width, height = fgui.debug_gpu.getResolution()
        if fgui.debug_counter > height then
            fgui.debug_counter = 1
        end
    elseif always then
        local gpu = require("component").gpu
        if gpu then
            local w, h = gpu.getResolution()
            gpu.set(1, h, msg)
        end
    end
end

fgui.pebug = function(callback, ...)
    local result, msg = pcall(callback, table.unpack({...}))
    if not result then
        fgui.d_print(result .. " => " .. msg)
    end
end

--region Buttons
fgui.buttons = {}
---@param id string
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param callback function Is given the arguments `id, player, button` which contains the button id, player, and mouse button respectively.
---@param text string Optional
---@param background_color number Optional
---@param text_color number Optional, default: `0xFFFFFF`
---@param auto_delete boolean Optional, default: `true`
---@return boolean Returns true if button was created, otherwise returns false
fgui.createButton = function(id, x1, y1, x2, y2, callback, text, background_color, text_color, auto_delete)
    if id == nil or id == "" then
        error("createButton missing required argument 'id'")
    end
    if x1 == nil or x1 == "" then
        error("createButton missing required argument 'x1'")
    end
    if y1 == nil or y1 == "" then
        error("createButton missing required argument 'y1'")
    end
    if x2 == nil or x2 == "" then
        error("createButton missing required argument 'x2'")
    end
    if y2 == nil or y2 == "" then
        error("createButton missing required argument 'y2'")
    end
    if type(fgui.buttons[id]) ~= "nil" then
        return false
    end
    local gpu = require("component").gpu
    if gpu then
        if auto_delete == nil then
            auto_delete = true
        end
        if text_color == nil then
            text_color = 0xFFFFFF
        end
        local bg_default
        if background_color ~= nil then
            bg_default = gpu.setBackground(background_color)
        end
        local width = x2 - x1 + 1
        local height = y2 - y1 + 1
        gpu.fill(x1, y1, width, height, " ")
        if text ~= nil and text ~= "" then
            fgui.writeTextCentered(text, y1 + math.floor(height / 2), text_color, "preserve", x1, x2)
        end
        if bg_default ~= nil then
            gpu.setBackground(bg_default)
        end
        local event = require("event")
        local buttonOnTouch = function(_, _, x, y, button, player)
            if fgui.buttonTouch(x, y, id) then
                if auto_delete then
                    fgui.deleteButton(id, true)
                end
                callback(id, player, button)
            end
        end
        event.listen("touch", buttonOnTouch)
        fgui.buttons[id] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, clear_event_listener = function()
            event.ignore("touch", buttonOnTouch)
        end}
        return true
    end
    return false
end

---@param id string
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param callback function Is given the arguments `id, player, button` which contains the button id, player, and mouse button respectively.
---@param time number The number of seconds before the button times out.
---@param timeout_callback function This function is called if the button isn't clicked before `time` runs out. Is given the button id as the first argument.
---@param text string Optional
---@param background_color_1 number Optional The primary button background. Default: 0x009200
---@param background_color_2 number Optional The secondary button background. Default: 0xFF0000
---@param text_color number Optional, default: `0xFFFFFF`
---@param auto_delete boolean Optional, default: `true`
---@return boolean Returns true if button was created, otherwise returns false
fgui.createButtonTimer = function(id, x1, y1, x2, y2, callback, time, timeout_callback, text, background_color_1, background_color_2, text_color, auto_delete)
    local default_bg
    local gpu = require("component").gpu
    if gpu then
        if auto_delete == nil then
            auto_delete = true
        end
        if background_color_1 == nil then
            background_color_1 = 0x009200
        end
        if background_color_2 == nil then
            background_color_2 = 0xFF0000
        end
        local event = require("event")
        local timer_tick
        local timer_timeout
        local callback_override = function(btn_id, player, button)
            if timer_tick then
                event.cancel(timer_tick)
            end
            if timer_timeout then
                event.cancel(timer_timeout)
            end
            callback(btn_id, player, button)
        end
        local result = fgui.createButton(id, x1, y1, x2, y2, callback_override, text, background_color_1, text_color, auto_delete)
        if not result then
            return false
        end
        local ticks_passed = 0
        timer_tick = event.timer(.5, function()
            if not fgui.buttons[id] then
                return
            end
            local max_width = x2 - x1 + 1
            local width = math.min(max_width, x1 + math.ceil(max_width * (ticks_passed / time)))
            local height = y2 - y1 + 1
            if background_color_2 then
                default_bg = gpu.setBackground(background_color_2)
            end
            gpu.fill(x1, y1, width, height, " ")
            if default_bg then
                gpu.setBackground(default_bg)
            end
            if text ~= nil and text ~= "" then
                fgui.writeTextCentered(text, y1 + math.floor(height / 2), text_color, "preserve", x1, x2)
            end
            ticks_passed = ticks_passed + .5
        end, math.huge)
        timer_timeout = event.timer(time, function()
            event.cancel(timer_tick)
            if auto_delete then
                fgui.deleteButton(id, false)
            end
            timeout_callback(id)
        end, 1)
    end
end

fgui.deleteButton = function(id, clear)
    if fgui.buttons[id] then
        if clear then
            fgui.clearButton(id)
        end
        fgui.buttons[id].clear_event_listener()
        fgui.buttons[id] = nil
    end
end

fgui.deleteAllButtons = function(clear)
    for k,v in pairs(fgui.buttons) do
        fgui.deleteButton(k, clear)
    end
end

fgui.clearButton = function(id)
    local gpu = require("component").gpu
    if gpu then
        if fgui.buttons[id] then
            local button = fgui.buttons[id]
            local width = button.x2 - button.x1 + 1
            local height = button.y2 - button.y1 + 1
            gpu.fill(button.x1, button.y1, width, height, " ")
        end
    end
end

fgui.clearAllButtons = function()
    for k,v in pairs(fgui.buttons) do
        fgui.clearButton(k)
    end
end

fgui.testButton = function(x, y)
    for id,button in pairs(fgui.buttons) do
        if x >= button.x1 and x <= button.x2 and y >= button.y1 and y <= button.y2 then
            return id
        end
    end
    return nil
end

fgui.buttonTouch = function(x, y, buttonName)
    return fgui.testButton(x, y) == buttonName
end

fgui.exampleOnTouch = function(name, screen, x, y, button, player)
    local btn = fgui.testButton(x, y)
    if btn == "mybutton" then
        computer.beep("...---...")
    end
end
--endregion

---@param text string
---@param x number
---@param y number
---@param options table A table of options that can contain the following keys: wrap:boolean, default: false, max_x:number, default: nil, color:number, default: nil
---@return nil|number, number Returns the x and y position of the beginning of the last line, or nil if no gpu was available
fgui.write = function(text, x, y, options)
    local default_fg
    local line_timeout = 16
    local line_counter = 0
    local gpu = require("component").gpu
    if gpu then
        local function split(input_str, sep)
            if sep == nil then
                sep = "%s"
            end
            local t={}
            for str in string.gmatch(input_str, "([^"..sep.."]+)") do
                table.insert(t, str)
            end
            return t
        end
        local width, height = gpu.getResolution()
        if options == nil then
            options = {}
        end
        if not options.max_x then
            options.max_x = width
        end
        if options.color then
            default_fg = gpu.setForeground(options.color)
        end
        local split_lines = split(text, "\n")
        if #split_lines > 1 then
            local sub_x, sub_y
            for k,v in ipairs(split_lines) do
                sub_x, sub_y = fgui.write(v, x, y + k, options)
            end
            return sub_x, sub_y
        else
            if options.wrap and x + #text > options.max_x then
                local lines = {}
                while x + #text > options.max_x and line_counter < line_timeout do
                    line_counter = line_counter + 1
                    local pos = options.max_x - x
                    local substr = ""
                    local prev_pos = pos
                    while string.sub(text, pos, pos) ~= " " and pos > 1 do
                        pos = pos - 1
                    end
                    if pos > 1 then
                        substr = string.sub(text, 1, pos)
                    else
                        substr = string.sub(text, x + #text)
                    end
                    text = string.sub(text, #substr+1)
                    table.insert(lines, substr)
                end
                for i,line in ipairs(lines) do
                    gpu.set(x, y, line)
                    y = y + 1
                end
                if #text > 0 then
                    gpu.set(x, y, text)
                end
            else
                gpu.set(x,y, text)
            end
        end
        if default_fg then
            gpu.setForeground(default_fg)
        end
        return x, y
    end
    return nil
end

---@param text string
---@param line number
---@param color number Optional
---@param background_color number Optional
---@param min_x number Optional
---@param max_x number Optional
fgui.writeTextCentered = function(text, line, color, background_color, min_x, max_x)
    if text == nil then
        error("writeTextCentered missing required argument 'text'")
    end
    if line == nil then
        error("writeTextCentered missing required argument 'line'")
    end
    local gpu = require("component").gpu
    if gpu then
        local width,height = gpu.getResolution()
        local fg_default = gpu.getForeground()
        local bg_default = gpu.getBackground()
        if not min_x then
            min_x = 1
        end
        if not max_x then
            max_x = width
        end
        if color then
            gpu.setForeground(color)
        end
        if background_color and background_color ~= "preserve" then
            gpu.setBackground(background_color)
        end
        local starting_position = math.max(1, math.floor((max_x - min_x) / 2) + min_x - math.floor(#text / 2) + 1)
        local posY = math.min(height, line)
        if background_color then
            local char_counter = 1
            for posX = starting_position,starting_position + string.len(text) do
                local _,_,background = gpu.get(posX,posY)
                gpu.setBackground(background)
                gpu.set(posX, posY, string.sub(text, char_counter, char_counter))
                char_counter = char_counter + 1
            end
        else
            gpu.set(starting_position, posY, text)
        end
        gpu.setForeground(fg_default)
        gpu.setBackground(bg_default)
    end
end

--region scrollingMenu
fgui.scrollingMenu = {
    active = false,
    suspended = false,
    items = nil,
    cursor_pos = 1,
    current_max_items = 99,
    breadcrumbs = {},
    options = {
        character = ">",
        background = 0x000000,
        foreground = 0xFFFFFF,
        highlight_bg = 0xFFFFFF,
        highlight_fg = 0x000000,
        exit_callback = nil,
        allow_exit = true,
    },
}
fgui.scrollingMenu.navigation = {}
fgui.scrollingMenu.navigation.back = function(force_exit)
    if fgui.scrollingMenu.suspended then
        return
    end
    if force_exit == nil then
        force_exit = false
    end
    if force_exit or #fgui.scrollingMenu.breadcrumbs == 0 then
        if not fgui.scrollingMenu.options.allow_exit then
            return
        end
        fgui.scrollingMenu.active = false
        if type(fgui.scrollingMenu.options.exit_callback) == "function" then
            fgui.scrollingMenu.options.exit_callback()
        end
    else
        table.remove(fgui.scrollingMenu.breadcrumbs)
        fgui.scrollingMenu.cursor_pos = 1
        fgui.pebug(fgui.scrollingMenuDraw)
    end
end
fgui.scrollingMenu.navigation.forward = function()
    if fgui.scrollingMenu.suspended then
        return
    end
    local item
    if #fgui.scrollingMenu.breadcrumbs > 0 then
        item = fgui.scrollingMenu.breadcrumbs[#fgui.scrollingMenu.breadcrumbs].submenu[fgui.scrollingMenu.cursor_pos]
    else
        item = fgui.scrollingMenu.items[fgui.scrollingMenu.cursor_pos]
    end
    if type(item.callback) == "function" then
        local returns = item.callback()
        if item.callback_returns_submenu then
            fgui.scrollingMenu.cursor_pos = 1
            fgui.pebug(fgui.scrollingMenuDraw, returns)
        end
    elseif type(item.submenu) == "table" then
        table.insert(fgui.scrollingMenu.breadcrumbs, item)
        fgui.scrollingMenu.cursor_pos = 1
        fgui.pebug(fgui.scrollingMenuDraw)
    end
end
fgui.scrollingMenu.navigation.up = function()
    if fgui.scrollingMenu.suspended then
        return
    end
    fgui.scrollingMenu.cursor_pos = math.max(1, fgui.scrollingMenu.cursor_pos - 1)
    fgui.pebug(fgui.scrollingMenuDraw)
end
fgui.scrollingMenu.navigation.down = function()
    if fgui.scrollingMenu.suspended then
        return
    end
    fgui.scrollingMenu.cursor_pos = math.min(fgui.scrollingMenu.current_max_items, fgui.scrollingMenu.cursor_pos + 1)
    fgui.pebug(fgui.scrollingMenuDraw)
end
fgui.scrollingMenuOnKeyUp = function(event, keyboardAddress, char, code, playerName)
    if code == 15 or code == 203 or code == 14 or code == 30 then -- tab key, left arrow, backspace, or a
        local force_exit = false
        if code == 15 then
            force_exit = true
        end
        fgui.scrollingMenu.navigation.back(force_exit)
    elseif code == 200 or code == 17 then -- up arrow or W
        fgui.scrollingMenu.navigation.up()
    elseif code == 208 or code == 31 then -- down arrow or S
        fgui.scrollingMenu.navigation.down()
    elseif code == 205 or code == 28 or code == 32 then -- right arrow, enter key, or D
        fgui.scrollingMenu.navigation.forward()
    end
end

fgui.scrollingMenuDraw = function(dynamic_submenu)
    local gpu = require("component").gpu
    if gpu then
        local items
        if type(dynamic_submenu) == "table" then
            items = dynamic_submenu.submenu
            table.insert(fgui.scrollingMenu.breadcrumbs, dynamic_submenu)
        else
            if #fgui.scrollingMenu.breadcrumbs > 0 then
                items = fgui.scrollingMenu.breadcrumbs[#fgui.scrollingMenu.breadcrumbs].submenu
            else
                items = fgui.scrollingMenu.items
            end
        end
        fgui.scrollingMenu.current_max_items = #items
        local options = fgui.scrollingMenu.options
        local default_bg = gpu.setBackground(options.background)
        local default_fg = gpu.setForeground(options.foreground)
        gpu.fill(options.x, options.y, options.width, options.height, " ")
        local title = options.label
        local text = nil
        if #fgui.scrollingMenu.breadcrumbs > 0 then
            for k,v in ipairs(fgui.scrollingMenu.breadcrumbs) do
                title = title .. " > " .. v.label
                text = v.text
            end
        end
        gpu.set(options.x + 1, options.y, title)
        local text_offset = 0
        if text ~= nil then
            local text_x, text_y = fgui.write(text, options.x + 1, options.y + 1, { wrap = true })
            text_offset = text_y - options.y
        end
        for k,v in ipairs(items) do
            local cursor = "   "
            if fgui.scrollingMenu.cursor_pos == k then
                cursor = " " .. options.character .. " "
            end
            gpu.set(options.x, options.y + k + text_offset + 1, cursor .. v.label)
        end
        gpu.setBackground(default_bg)
        gpu.setForeground(default_fg)
    end
end

---createScrollingMenu
---@param items table A table of items to list in the menu
---Each item should be a table containing a `label`:string and a `submenu`:table or `callback`:function, additionally the callback function can return a submenu
---in which case the item should have the field `callback_returns_submenu` set to true.
---An item may also contain a `text`:string field, if a submenu is drawn, the text will be displayed above the submenu.
---A submenu is a table containing a `label`:string field and a `submenu`:table field, which contains a list of items (as specified above).
---It may also contain a `text`:string field.
---@param options table A table of options for the menu. Valid options are:
--- * label         - The menu label, used as the root of the breadcrumb trail. If nil or empty `Root` will be used
--- * text          - The menu text, if not nil will be shown above the menu
--- * x             - The starting x position of the menu
--- * y             - The starting y position of the menu
--- * width         - The max width of the menu
--- * height        - The max height of the menu
--- * **If not all size options are set the menu will default to taking up the whole screen.**
--- * character     - The character highlighting the current item. Default: `>`
--- * background    - The background color. Default: `0x000000`
--- * foreground    - The foreground color. Default: `0xFFFFFF`
--- * highlight_bg  - The background color of the highlighted item. Default: `0xFFFFFF`
--- * highlight_fg  - The foreground color of the highlighted item. Default: `0x000000`
--- * exit_callback - A function called after exiting the menu. Default: nil
fgui.createScrollingMenu = function(items, options)
    local gpu = require("component").gpu
    if gpu then
        if #items == 0 then
            return false
        end
        fgui.scrollingMenu.items = items
        if options ~= nil then
            for k,v in pairs(options) do
                fgui.scrollingMenu.options[k] = v
            end
        end
        options = fgui.scrollingMenu.options
        if options.x == nil or options.y == nil or options.width == nil or options.height == nil then
            options.x = 1
            options.y = 1
            local w, h = gpu.getResolution()
            options.width = w
            options.height = h
        end
        if options.label == nil or options.label == "" then
            options.label = "Root"
        end

        fgui.pebug(fgui.scrollingMenuDraw)
        fgui.scrollingMenu.active = true
        local event = require("event")
        event.listen("key_up", fgui.scrollingMenuOnKeyUp)
        while fgui.scrollingMenu.active do
            os.sleep(0)
        end
        event.ignore("key_up", fgui.scrollingMenuOnKeyUp)
    end
end
--endregion

--region chooseValueDialog
---Writes the message to the screen and presents an input depending on the `values` field.
---@param msg string
---@param values table|string|function
---If `values` is a table of choices these choices will be presented as a list. Each choice should have a `label` field and optionally a `value` field.
---
---If the `values` field is present this will be returned when selected, otherwise the `label` is returned instead.
---The currently selected choice, if any, can be given the `selected` field set to true.
---
---If `values` is a function that function will be passed the input. If the function returns true the input will be accepted, if it returns false the user
---will be prompted to enter another value.
---Additionally `values` can be one of the following strings:
--- * `string`  - Provides an input field that accepts strings (any value)
--- * `number`  - Provides an input field that accepts numbers, the screen will not close until a number is given
--- * `bool`    - Provides an input field that accepts "true", "false", "1", or "0". The screen will not close until one of these is given
--- * `int`     - Provides an input field that accepts integers, the screen will not close until an integer is given
---@param options table A table of options that can contain the following fields:
--- * `x`           - The starting x position of the dialog.
--- * `y`           - The starting y position of the dialog.
--- * `width`       - The max width of the dialog.
--- * `height`      - The max height of the dialog.
--- * **If not all size options are set the dialog will take up the whole screen.**
--- * `background`  - The background color. Default: `0x000000`
--- * `foreground`  - The foreground color. Default: `0xFFFFFF`
---@return any, string Returns the selected or entered value, or nil if no value was given. If an error occurs will return nil with an error message as the second value.
fgui.chooseValueDialog = function(msg, values, options)
    local return_value = nil
    local gpu = require("component").gpu
    if gpu then
        local term = require("term")
        local width, height = gpu.getResolution()
        if not options then
            options = {}
        end
        if not options.x or not options.y or not options.width or not options.height then
            options.x = 1
            options.y = 1
            options.width = width
            options.height = height
        end
        if not options.background then
            options.background = 0x000000
        end
        if not options.foreground then
            options.foreground = 0xFFFFFF
        end
        if options.x + options.width > width +1 or options.y + options.height > height +1 then
            return nil, "Dialog is partially out of bounds"
        end
        local original_bg = gpu.setBackground(options.background)
        local original_fg = gpu.setForeground(options.foreground)
        gpu.fill(options.x, options.y, options.width, options.height, " ")
        local x,y = fgui.write(msg, options.x + 1, options.y + 1, { wrap = true , max_x = options.x + options.width - 1 })
        if type(values) == "table" then
            local items = {}
            for k,v in ipairs(values) do
                table.insert(items, { label = v.label, callback = function()
                    return_value = v.value or v.label
                    fgui.scrollingMenu.active = false
                end })
            end
            print(#items)
            print(fgui.scrollingMenu.active)
            fgui.createScrollingMenu(items, { label = "Choose", x = options.x, y = y +2, width = options.width, height = options.height - y, background = options.background, foreground = options.foreground })
            print("Scrolling menu done")
        else
            ::input::
            gpu.fill(x, y + 2, options.width -1, 1, " ")
            local label
            if type(values) == "string" then
                label = string.upper(string.sub(values, 1, 1)) .. string.sub(values, 2) .. ": "
            else
                label = "Input: "
            end
            gpu.set(x,y+2,label)
            term.setCursor(x + #label, y + 2)
            local user_input = io.read()
            if type(values) == "function" then
                if not values(user_input) then
                    goto input
                end
                return_value = user_input
            elseif values == "string" then
                return_value = user_input
            elseif values == "number" then
                if tonumber(user_input) == nil then
                    goto input
                end
                return_value = tonumber(user_input)
            elseif values == "int" then
                if math.floor(tonumber(user_input)) ~= tonumber(user_input) then
                    goto input
                end
                return_value = tonumber(user_input)
            elseif values == "bool" then
                if user_input == "true" or user_input == "1" then
                    return_value = true
                elseif user_input == "false" or user_input == "0" then
                    return_value = false
                else
                    goto input
                end
            end
        end
        gpu.setBackground(original_bg)
        gpu.setForeground(original_fg)
    else
        return nil, "No gpu available"
    end
    return return_value
end
--endregion

return fgui