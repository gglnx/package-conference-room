gl.setup(1920, 1080)

sys.set_flag("slow_gc")

local json = require "json"
local schedule
local current_room

util.resource_loader{
    "progress.frag",
}

local white = resource.create_colored_texture(1,1,1)

util.file_watch("schedule.json", function(content)
    print("reloading schedule")
    schedule = json.decode(content)
end)

local rooms
local spacer = white

node.event("config_update", function(config)
    rooms = {}
    for idx, room in ipairs(config.rooms) do
        if room.serial == sys.get_env("SERIAL") then
            print("found my room")
            current_room = room
        end
        rooms[room.name] = room
    end
    spacer = resource.create_colored_texture(CONFIG.foreground_color.rgba())
end)

hosted_init()

local base_time = N.base_time or 0
local current_talk
local all_talks = {}
local day = 0

function get_now()
    return base_time + sys.now()
end

function check_next_talk()
    local now = get_now()
    local room_next = {}
    for idx, talk in ipairs(schedule) do
        if rooms[talk.place] and not room_next[talk.place] and talk.start_unix + 25 * 60 > now then 
            room_next[talk.place] = talk
        end
    end

    local room_next_all = {}
    for idx, talk in ipairs(schedule) do
        if talk.start_unix > now then
            room_next_all[talk.id] = talk
        end
    end

    for room, talk in pairs(room_next) do
        talk.slide_lines = wrap(talk.title, 30)

        if #talk.title > 25 then
            talk.lines = wrap(talk.title, 60)
            if #talk.lines == 1 then
                talk.lines[2] = table.concat(talk.speakers, ", ")
            end
        end
    end

    if room_next[current_room.name] then
        current_talk = room_next[current_room.name]
    else
        current_talk = nil
    end

    all_talks = {}
    --for room, talk in pairs(room_next) do
    --    if current_talk and room ~= current_talk.place then
    --        all_talks[#all_talks + 1] = talk
    --    end
    --end

    for id, talk in pairs(room_next_all) do
        if talk.place ~= current_talk.place then
            all_talks[#all_talks + 1] = talk
        end
    end

    table.sort(all_talks, function(a, b) 
        if a.start_unix < b.start_unix then
            return true
        elseif a.start_unix > b.start_unix then
            return false
        else
            return a.place < b.place
        end
    end)

    for idx, talk in ipairs(all_talks) do
        if idx > 5 then
            all_talks[idx] = nil
        end
    end
end

function wrap(str, limit, indent, indent1)
    limit = limit or 72
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi-here > limit then
            here = st
            return "\n"..word
        end
    end)
    local splitted = {}
    for token in string.gmatch(wrapped, "[^\n]+") do
        splitted[#splitted + 1] = token
    end
    return splitted
end

local clock = (function()
    local base_time = N.base_time or 0

    local function set(time)
        base_time = tonumber(time) - sys.now()
    end

    util.data_mapper{
        ["clock/midnight"] = function(since_midnight)
            print("NEW midnight", since_midnight)
            set(since_midnight)
        end;
    }

    local function get()
        local time = (base_time + sys.now()) % 86400
        return string.format("%d:%02d", math.floor(time / 3600), math.floor(time % 3600 / 60))
    end

    return {
        get = get;
        set = set;
    }
end)()

util.data_mapper{
    ["clock/set"] = function(time)
        base_time = tonumber(time) - sys.now()
        N.base_time = base_time
        check_next_talk()
        print("UPDATED TIME", base_time)
    end;
    ["clock/day"] = function(new_day)
        day = new_day
        print("UPDATED DAY", new_day)
    end;
}

function switcher(get_screens)
    local current_idx = 0
    local current
    local current_state

    local switch = sys.now()
    local switched = sys.now()

    local blend = 0.8
    local mode = "switch"

    local old_screen
    local current_screen
    
    local screens = get_screens()

    local function prepare()
        local now = sys.now()
        if now > switch and mode == "show" then
            mode = "switch"
            switched = now

            -- snapshot old screen
            gl.clear(CONFIG.background_color.rgb_with_a(0.0))
            if current then
                current.draw(current_state)
            end
            old_screen = resource.create_snapshot()

            -- find next screen
            current_idx = current_idx + 1
            if current_idx > #screens then
                screens = get_screens()
                current_idx = 1
            end
            current = screens[current_idx]
            switch = now + current.time
            current_state = current.prepare()

            -- snapshot next screen
            gl.clear(CONFIG.background_color.rgb_with_a(0.0))
            current.draw(current_state)
            current_screen = resource.create_snapshot()
        elseif now - switched > blend and mode == "switch" then
            if current_screen then
                current_screen:dispose()
            end
            if old_screen then
                old_screen:dispose()
            end
            current_screen = nil
            old_screen = nil
            mode = "show"
        end
    end
    
    local function draw()
        current.draw(current_state)

        -- Loop overlay
        if CONFIG.overlay then
            CONFIG.overlay.ensure_loaded(videoConfig):draw(0, 0, WIDTH, HEIGHT)
        end
    end
    return {
        prepare = prepare;
        draw = draw;
    }
end

local content = switcher(function() 
    return {{
        time = CONFIG.current_room,
        prepare = function()
        end;
        draw = function()
            -- HEADER
            CONFIG.font:write(70, 180, string.upper("Herzlich Willkommen"), 70, CONFIG.foreground_color.rgba())
            spacer:draw(0, 280, WIDTH, 282, 0.6)

            -- HASHTAG
            CONFIG.font:write(70, 340, string.upper("Hashtag"), 50, CONFIG.foreground_color.rgba())
            CONFIG.font2:write(470, 340, "#sub7", 50, CONFIG.foreground_color.rgba())

            -- TWITTER
            CONFIG.font:write(70, 400, string.upper("Twitter"), 50, CONFIG.foreground_color.rgba())
            CONFIG.font2:write(470, 400, "@subscribe_de", 50, CONFIG.foreground_color.rgba())

            -- PROGRAMME
            CONFIG.font:write(70, 460, string.upper("Fahrplan"), 50, CONFIG.foreground_color.rgba())
            CONFIG.font2:write(470, 460, "fahrplan.subscribe.de", 50, CONFIG.foreground_color.rgba())

            -- MAIL
            CONFIG.font:write(70, 520, string.upper("Mail"), 50, CONFIG.foreground_color.rgba())
            CONFIG.font2:write(470, 520, "team@das-sendezentrum.de", 50, CONFIG.foreground_color.rgba())
        end
    }, {
        time = CONFIG.current_room,
        prepare = function()
        end;
        draw = function()
            if not current_talk then
                CONFIG.font2:write(400, 180, "Nächste Sendung", 80, CONFIG.foreground_color.rgba())
                spacer:draw(0, 300, WIDTH, 302, 0.6)
                CONFIG.font2:write(400, 310, "Nope. That's it.", 50, CONFIG.foreground_color.rgba())
            else
                local delta = current_talk.start_unix - get_now()
                if delta > 0 then
                    CONFIG.font2:write(400, 180, "Nächste Sendung", 80, CONFIG.foreground_color.rgba())
                else
                    CONFIG.font2:write(400, 180, "Diese Sendung", 80, CONFIG.foreground_color.rgba())
                end
                spacer:draw(0, 280, WIDTH, 282, 0.6)

                CONFIG.font2:write(130, 310, current_talk.start_str, 50, CONFIG.foreground_color.rgba())
                if delta > 180*60 then
                    CONFIG.font2:write(130, 310 + 60, string.format("in %d h", math.floor(delta/3660)+1), 50, CONFIG.foreground_color.rgb_with_a(0.6))
                elseif delta > 0 then
                    CONFIG.font2:write(130, 310 + 60, string.format("in %d min", math.floor(delta/60)+1), 50, CONFIG.foreground_color.rgb_with_a(0.6))
                end
                for idx, line in ipairs(current_talk.slide_lines) do
                    if idx >= 5 then
                        break
                    end
                    CONFIG.font:write(400, 310 - 60 + 60 * idx, line, 50, CONFIG.foreground_color.rgba())
                end

                local speakers = wrap(table.concat(current_talk.speakers, ", "), 30)

                for idx, line in ipairs(speakers) do
                    if idx >= 5 then
                        break
                    end

                    CONFIG.font2:write(400, 490 + 50 * idx, line, 50, CONFIG.foreground_color.rgb_with_a(0.6))
                end                
            end
        end
    }, {
        time = CONFIG.room_info,
        prepare = function()
        end;
        draw = function(t)
            CONFIG.font2:write(400, 180, "Meta", 80, CONFIG.foreground_color.rgba())
            spacer:draw(0, 280, WIDTH, 282, 0.6)

            CONFIG.font:write(70, 300, "Kopfhörer auf Kanal A schalten!", 50, CONFIG.foreground_color.rgba())

            CONFIG.font:write(70, 430, "Twitter", 50, CONFIG.foreground_color.rgba())
            CONFIG.font:write(470, 430, "@sendezentrum", 50, CONFIG.foreground_color.rgba())

            CONFIG.font:write(70, 510, "Hashtag", 50, CONFIG.foreground_color.rgba())
            CONFIG.font:write(470, 510, "#rpTENsz", 50, CONFIG.foreground_color.rgba())

            CONFIG.font:write(70, 590, "Mail", 50, CONFIG.foreground_color.rgba())
            CONFIG.font:write(470, 590, "team@das-sendezenturm.de", 50, CONFIG.foreground_color.rgba())

            --CONFIG.font:write(30, 300, "Audio", 50, CONFIG.foreground_color.rgba())
            --CONFIG.font:write(400, 300, "Dial " .. current_room.dect, 50, CONFIG.foreground_color.rgba())

            --CONFIG.font:write(30, 360, "Translation", 50, CONFIG.foreground_color.rgba())
            --CONFIG.font:write(400, 360, "Dial " .. current_room.translation, 50, CONFIG.foreground_color.rgba())

            --CONFIG.font:write(30, 460, "IRC", 50, CONFIG.foreground_color.rgba())
            --CONFIG.font:write(400, 460, current_room.irc, 50, CONFIG.foreground_color.rgba())

            
        end
    }}
end)

function node.render()
    if base_time == 0 then
        return
    end

    content.prepare()

    CONFIG.background_color.clear()

    -- Background video
    local videoConfig = {["loop"] = true}
    CONFIG.background.ensure_loaded(videoConfig):draw(0, 0, WIDTH, HEIGHT)

    -- Logo
    util.draw_correct(CONFIG.logo.ensure_loaded(), 70, 50, 455 + 70, 70 + 50)
    
    -- Clock
    CONFIG.font2:write(1920 - 200 - 70, 60, clock.get(), 70, CONFIG.foreground_color.rgba())

    local fov = math.atan2(HEIGHT, WIDTH*2) * 360 / math.pi
    gl.perspective(fov, WIDTH/2, HEIGHT/2, -WIDTH,
                        WIDTH/2, HEIGHT/2, 0)

    content.draw()
end
