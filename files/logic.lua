local players = {}
local delay, cooldown, grace = 15, 60, 600
local ground_reach, sample_frames, sample_step = 6, 4, 2
local prefix = "floor_is_lava_"
local touch_arrays

local function first(entity, kind)
    return EntityGetFirstComponentIncludingDisabled(entity, kind)
end

local function discard_sample(s)
    if s.sample and EntityGetIsAlive(s.sample) then EntityKill(s.sample) end
    s.sample, s.sample_frame, s.sample_static = nil, nil, nil
    s.sample_x, s.sample_y, s.sample_end_y = nil, nil, nil
    s.sample_player_x, s.sample_player_y = nil, nil
    s.sample_depth = nil
end

local function reset(s)
    discard_sample(s)
    s.since = nil
end

function FloorIsLavaStartRun()
    if GameHasFlagRun(prefix .. "started") then return end
    local frame = GameGetFrameNum()
    GlobalsSetValue(prefix .. "grace", tostring(frame + grace))
    GlobalsSetValue(prefix .. "ready", "0")
    GlobalsSetValue(prefix .. "clock", tostring(frame))
    GameAddFlagRun(prefix .. "started")
end

-- Frames of starting grace left (0 once it has ended).
function FloorIsLavaGraceLeft()
    local grace_until = tonumber(GlobalsGetValue(prefix .. "grace", "0"))
    return math.max(0, grace_until - GameGetFrameNum())
end

local function update_clock(frame)
    local previous = tonumber(GlobalsGetValue(prefix .. "clock", tostring(frame)))
    if frame < previous then
        -- The frame counter can restart when a save is loaded. Carry over
        -- whatever grace or cooldown was left instead of granting it again.
        for _, s in pairs(players) do reset(s) end
        players = {}
        for _, key in ipairs({"grace", "ready"}) do
            local left = math.max(0, tonumber(GlobalsGetValue(prefix .. key, "0")) - previous)
            GlobalsSetValue(prefix .. key, tostring(frame + left))
        end
    end
    GlobalsSetValue(prefix .. "clock", tostring(frame))
end

local function load_sample(s, frame, static, x, y)
    if s.sample and EntityGetIsAlive(s.sample) then EntityKill(s.sample) end
    local file = static and "sample_static.xml" or "sample.xml"
    s.sample = EntityLoad("mods/floor_is_lava/files/" .. file, s.sample_x, s.sample_y)
    s.sample_frame = frame
    s.sample_static = static
    s.sample_player_x, s.sample_player_y = x, y
end

local function sampled_material(s)
    if not s.sample or not EntityGetIsAlive(s.sample) then return nil end
    -- true = ignore Box2D materials, so physics objects never count as ground.
    local material = GetMaterialInventoryMainMaterial(s.sample, true)
    if material and material > 0 then return material end
    return nil
end

local function physics_below(player, x, foot_y, min_x, max_x)
    local own = {}
    for _, body in ipairs(PhysicsBodyIDGetFromEntity(player) or {}) do own[body] = true end
    -- Static terrain also creates collision bodies. Only the query that omits
    -- statics can reject a contact without identifying its owning object.
    for _, body in ipairs(PhysicsBodyIDQueryBodies(x+min_x, foot_y-0.5, x+max_x, foot_y+2, false) or {}) do
        if not own[body] then return true end
    end
    local statics = {}
    for _, body in ipairs(PhysicsBodyIDQueryBodies(x+min_x, foot_y-0.5, x+max_x, foot_y+2, true) or {}) do
        if not own[body] then statics[body] = true end
    end
    if next(statics) == nil then return false end
    -- A static prop can still be excluded when a live entity identifies it.
    -- An anonymous static collision alone must never veto terrain sampling.
    for _, entity in ipairs(EntityGetInRadius(x, foot_y, 32) or {}) do
        if entity ~= player and EntityGetRootEntity(entity) ~= player
            and (first(entity, "PhysicsImageShapeComponent") or first(entity, "PhysicsShapeComponent")) then
            for _, body in ipairs(PhysicsBodyIDGetFromEntity(entity) or {}) do
                if statics[body] then return true end
            end
        end
    end
    return false
end

local function supported(x, foot_y, min_x, max_x)
    for _, offset in ipairs({0, min_x, max_x}) do
        if RaytracePlatforms(x+offset, foot_y-0.5, x+offset, foot_y+2) then return true end
    end
    return false
end

local function ground_below(x, y, foot_y, min_x, max_x)
    -- Surface rays pass through liquids, so this finds the floor under water.
    for _, offset in ipairs({0, min_x, max_x}) do
        local hit, hx, hy = RaytraceSurfaces(x+offset, y, x+offset, foot_y+ground_reach)
        if hit then return math.floor(hx), math.floor(hy) end
    end
    return math.floor(x), math.floor(y)
end

-- Every solid and powder except physics-object materials, all mapped to lava.
-- Liquids, gases and air are left alone so the patch only replaces ground.
local function ground_to_lava_arrays()
    if touch_arrays then return touch_arrays[1], touch_arrays[2] end
    local from, to = {}, {}
    for _, list in ipairs({CellFactory_GetAllSolids(true, false), CellFactory_GetAllSands(true, false)}) do
        for _, name in ipairs(list or {}) do
            local physics = false
            for _, tag in ipairs(CellFactory_GetTags(CellFactory_GetType(name)) or {}) do
                if tag:find("box2d", 1, true) then physics = true end
            end
            if not physics then from[#from+1] = name; to[#to+1] = "lava" end
        end
    end
    touch_arrays = {table.concat(from, ","), table.concat(to, ",")}
    return touch_arrays[1], touch_arrays[2]
end

-- 30 px at 100 max HP, plus 1 px for every max HP point above 100.
local function patch_radius(player)
    local damage = first(player, "DamageModelComponent")
    local max_hp = damage and ComponentGetValue2(damage, "max_hp") * 25 or 100
    -- Max HP is stored in units of 25 HP; round away float error (4.4 * 25).
    return 30 + math.max(0, math.floor(max_hp - 100 + 0.5))
end

-- Like the Touch of spells, but only ground turns into lava.
local function lava_patch(x, y, radius)
    local from, to = ground_to_lava_arrays()
    local patch = EntityCreateNew("floor_is_lava_patch")
    EntitySetTransform(patch, x, y)
    EntityAddComponent2(patch, "MagicConvertMaterialComponent", {
        from_material_array = from,
        to_material_array = to,
        radius = radius,
        steps_per_frame = radius,
        is_circle = true,
        kill_when_finished = true,
    })
end

function FloorIsLavaShift(player, source, foot_y)
    local lava = CellFactory_GetType("lava")
    if not source or source <= 0 or lava <= 0 or source == lava then return false end
    local x, y = EntityGetTransform(player)
    -- Holy Mountain brickwork (all "temple*" materials) only ever gets a
    -- patch, so Hardcore doesn't wipe out every Holy Mountain at once.
    local brickwork = CellFactory_GetName(source):find("^temple") ~= nil
    local radius
    if ModSettingGet("floor_is_lava.hardcore") and not brickwork then
        local name = GameTextGetTranslatedOrNot(CellFactory_GetUIName(source))
        ConvertMaterialOnAreaInstantly(math.floor(x)-128, math.floor(y)-128, 256, 256, source, lava, false, false)
        ConvertMaterialEverywhere(source, lava)
        GamePrint("Floor is lava: " .. name .. " -> lava")
        EntityLoad("data/entities/particles/treble_eye.xml", x, y-10)
    else
        radius = patch_radius(player)
        lava_patch(x, foot_y or y, radius)
    end
    GlobalsSetValue(prefix .. "ready", tostring(GameGetFrameNum() + cooldown))
    for _, s in pairs(players) do reset(s) end
    return true, radius
end

-- Sparks at the feet from the first frame of contact, growing as the timer
-- runs out.
local function warn(x, foot_y, min_x, max_x, progress)
    local count = 1 + math.floor(math.min(progress, 1) * 3)
    for _, offset in ipairs({min_x, 0, max_x}) do
        GameCreateCosmeticParticle("spark_red", x+offset, foot_y, count, 0, -40)
    end
end

function FloorIsLavaUpdate(player)
    local frame = GameGetFrameNum()
    update_clock(frame)
    local character = first(player, "CharacterDataComponent")
    if not character then
        if players[player] then reset(players[player]); players[player] = nil end
        return
    end
    local s = players[player]
    if not s then s = {}; players[player] = s end
    local x, y = EntityGetTransform(player)
    local seen_position = s.last_x ~= nil
    s.last_x, s.last_y = x, y

    local grace_until = tonumber(GlobalsGetValue(prefix .. "grace", "0"))
    local ready_at = tonumber(GlobalsGetValue(prefix .. "ready", "0"))
    if frame < grace_until or frame < ready_at then
        reset(s)
        local until_frame = math.max(grace_until, ready_at)
        local label = frame < grace_until and "Starting grace " or "Cooldown "
        s.status = label .. string.format("%.1f", (until_frame-frame)/60) .. "s"
        return
    end
    if s.failure_until and frame < s.failure_until then return end

    local controls = first(player, "ControlsComponent")
    local flying = controls and ComponentGetValue2(controls, "mButtonDownFly")
    local walking = controls and (ComponentGetValue2(controls, "mButtonDownLeft")
        or ComponentGetValue2(controls, "mButtonDownRight"))
    if flying then reset(s); s.status = "No ground contact while levitating"; return end

    local foot_y = y + ComponentGetValue2(character, "collision_aabb_max_y")
    local min_x = ComponentGetValue2(character, "collision_aabb_min_x")
    local max_x = ComponentGetValue2(character, "collision_aabb_max_x")
    if physics_below(player, x, foot_y, min_x, max_x) then
        reset(s); s.status = "Physics objects are safe"; return
    end

    local grounded = ComponentGetValue2(character, "is_on_ground") or supported(x, foot_y, min_x, max_x)
    -- Only accept a sample that is still under the character's feet.
    local material = sampled_material(s)
    local sample_underfoot = s.sample_x and s.sample_x >= x+min_x and s.sample_x <= x+max_x
        and math.abs(y-s.sample_player_y) <= 2
    -- Sucking up a powder pixel can make a standing player sink slightly.
    -- Still accept that read, but not when walking off an edge.
    local sample_settle = s.sample_player_x and not walking
        and math.abs(x-s.sample_player_x) <= 0.5
        and y-s.sample_player_y >= -0.25 and y-s.sample_player_y <= 2
    if material and sample_underfoot and (grounded or sample_settle) then
        s.result = "Read: " .. GameTextGetTranslatedOrNot(CellFactory_GetUIName(material))
        s.result_until = frame + 120
        discard_sample(s)
        local shifted, radius = FloorIsLavaShift(player, material, foot_y)
        if shifted then
            s.status = radius and ("Ground turned to lava (" .. radius .. " px)") or "Turned to lava everywhere"
        else
            s.status = "No ground to turn into lava"
        end
        reset(s)
        return
    end
    if not grounded then
        reset(s); s.status = "No ground below feet"; return
    end
    warn(x, foot_y, min_x, max_x, s.since and (frame-s.since)/delay or 0)
    if not seen_position then s.status = "Ground contact"; return end
    if not s.since then s.since = frame end
    if frame-s.since < delay then
        s.status = string.format("Ground contact %.2f / %.2fs", (frame-s.since)/60, delay/60)
        return
    end

    if s.sample then
        if not EntityGetIsAlive(s.sample) then reset(s); return end
        if x ~= s.sample_player_x or y ~= s.sample_player_y then
            -- Follow the walker with a fresh inventory. Keep the phase clock
            -- so continuous walking cannot restart the powder pass forever.
            local phase_frame, static = s.sample_frame, s.sample_static
            s.sample_x, s.sample_y = ground_below(x, y, foot_y, min_x, max_x)
            s.sample_end_y = math.max(s.sample_y, math.floor(foot_y+ground_reach))
            s.sample_y = math.min(s.sample_y+s.sample_depth, s.sample_end_y)
            load_sample(s, frame, static, x, y)
            s.sample_frame = phase_frame
        end
        if frame-s.sample_frame >= sample_frames then
            if not s.sample_static then
                load_sample(s, frame, true, x, y)
            elseif s.sample_y < s.sample_end_y then
                local next_y = math.min(s.sample_y + sample_step, s.sample_end_y)
                s.sample_depth = s.sample_depth + next_y-s.sample_y
                s.sample_y = next_y
                load_sample(s, frame, false, x, y)
            else
                reset(s)
                s.status = "No solid ground or powder found"
                s.failure_until = frame + 120
            end
        end
    else
        s.sample_x, s.sample_y = ground_below(x, y, foot_y, min_x, max_x)
        s.sample_end_y = math.max(s.sample_y, math.floor(foot_y+ground_reach))
        s.sample_depth = 0
        load_sample(s, frame, false, x, y)
    end
    if s.sample then s.status = "Reading ground below character" end
end

local status_gui
function FloorIsLavaDrawStatus()
    status_gui = status_gui or GuiCreate()
    GuiStartFrame(status_gui)
    if not ModSettingGet("floor_is_lava.debug") then return end
    for _, s in pairs(players) do
        GuiText(status_gui, 10, 48, "Floor is lava: " .. (s.status or "Ready"))
        if s.result_until and GameGetFrameNum() < s.result_until then GuiText(status_gui, 10, 59, s.result) end
        break
    end
end
