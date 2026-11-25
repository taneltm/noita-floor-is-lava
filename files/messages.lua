-- Text floating above the player in the world, fading out after a moment.
local font = "data/fonts/font_pixel_white.xml"
local hold, fade = 90, 60
local line_height, lift = 9, 24
local active = {}
local measure_gui

function FloorIsLavaShowMessage(player, lines)
    measure_gui = measure_gui or GuiCreate()
    local x, y = EntityGetTransform(player)
    local message = EntityCreateNew("floor_is_lava_message")
    EntityAddTag(message, "floor_is_lava_message")
    EntitySetTransform(message, x, y)
    local sprites = {}
    for i, line in ipairs(lines) do
        local width = GuiGetTextDimensions(measure_gui, line)
        sprites[i] = EntityAddComponent2(message, "SpriteComponent", {
            image_file = font,
            is_text_sprite = true,
            text = line,
            offset_x = width / 2,
            offset_y = lift + (#lines - i) * line_height,
            emissive = true,
            z_index = -3,
        })
    end
    active[#active+1] = { entity = message, player = player, sprites = sprites, start = GameGetFrameNum() }
end

function FloorIsLavaUpdateMessages()
    local frame = GameGetFrameNum()
    for i = #active, 1, -1 do
        local m = active[i]
        local age = frame - m.start
        if age >= hold + fade or not EntityGetIsAlive(m.player) or not EntityGetIsAlive(m.entity) then
            if EntityGetIsAlive(m.entity) then EntityKill(m.entity) end
            table.remove(active, i)
        else
            local x, y = EntityGetTransform(m.player)
            EntitySetTransform(m.entity, x, y)
            local alpha = age < hold and 1 or 1 - (age - hold) / fade
            for _, sprite in ipairs(m.sprites) do ComponentSetValue2(sprite, "alpha", alpha) end
        end
    end
end
