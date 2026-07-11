local MAX_SHOTS = 5
local SHOT_RECHARGE_TICKS = 60
local PING_LIMIT = 400

vanilla_model.PLAYER:visible(false)

models.model
    :setPrimaryRenderType("CUTOUT_EMISSIVE_SOLID")
    :setSecondaryRenderType("CUTOUT_EMISSIVE_SOLID")

local TEXTURE = textures["model.Skin"]

local receiving = ""
function pings.receive_texture_data(start, final_size, data)
    if start then
        receiving = ""
    end
    receiving = receiving .. data
    if #receiving == final_size and not host:isHost() then
        local texture = textures:read("received_texture", receiving)
        models:setPrimaryTexture("CUSTOM", texture)
    end
end

local BLEND_TIME = 3
local blend_out = {}
local blend_in = {}
local last = nil
function pings.toggle_animation(name)
    if last then
        blend_out[#blend_out + 1] = {
            anim = last,
            time = world.getTime()
        }
        last = nil
    end

    if name then
        last = animations.model[name]
        blend_in[#blend_in + 1] = {
            anim = animations.model[name]:play():blend(0),
            time = world.getTime()
        }
    end
end

local function smoothstep(x)
    return x * x * (3 - 2 * x)
end
function events.RENDER(delta)
    for i = #blend_in, 1, -1 do
        local to_blend = blend_in[i]
        local time = (world.getTime(delta) - to_blend.time) / BLEND_TIME
        to_blend.anim:blend(smoothstep(time))
        if time >= 1 then
            table.remove(blend_in, i)
        end
    end

    for i = #blend_out, 1, -1 do
        local to_blend = blend_out[i]
        local time = (world.getTime(delta) - to_blend.time) / BLEND_TIME
        to_blend.anim:blend(smoothstep(1 - time))
        if time >= 1 then
            to_blend.anim:stop()
            table.remove(blend_out, i)
        end
    end
end

local statue_timer = 0
local _influence = 0
local influence = 0
local _arm_lerp = 0
local arm_lerp = 0

vanilla_model.LEFT_ARM:setRot(vec(0, 0, 0))
vanilla_model.RIGHT_ARM:setRot(vec(0, 0, 0))
vanilla_model.LEFT_LEG:setRot(vec(0, 0, 0))
vanilla_model.RIGHT_LEG:setRot(vec(0, 0, 0))

function events.RENDER(delta)
    local limb_influence = math.lerp(_influence, influence, delta)
    local aim_lerp = 1 - math.lerp(_arm_lerp, arm_lerp, delta)

    models.model.root.LeftArm:setRot(vanilla_model.LEFT_ARM:getOriginRot() * limb_influence)
    models.model.root.RightArm:setRot(vanilla_model.RIGHT_ARM:getOriginRot() * limb_influence * aim_lerp)
    models.model.root.LeftLeg:setRot(vanilla_model.LEFT_LEG:getOriginRot() * limb_influence)
    models.model.root.RightLeg:setRot(vanilla_model.RIGHT_LEG:getOriginRot() * limb_influence)

    renderer:setShadowRadius(limb_influence * 0.5)
    nameplate.ENTITY:setScale(limb_influence ^ 2)
end

local is_seeker = true

function events.TICK()
    if player:getVelocity():length() < 0.05 and not is_seeker then
        statue_timer = statue_timer + 1
    else
        statue_timer = 0
    end

    _influence = influence
    influence = math.lerp(influence, statue_timer > 5 and 0 or 1, 0.4)
end

local function set_user_type(seeker)
    is_seeker = seeker
    avatar:store("is_seeker", seeker)
    models.model:scale(seeker and 1 or 0.75)
    nameplate.ENTITY:pivot(0, seeker and 2.2 or 1.8, 0)
end

function pings.set_user_type(seeker)
    set_user_type(seeker)
end

set_user_type(true)
avatar:store("chameleon_player", true)

local is_aiming = false
function pings.aim_gun(aiming)
    is_aiming = aiming
end

function pings.fire_gun(pos, dir)
    local viewer = client.getViewer()
    if viewer ~= player and viewer:getVariable("chameleon_player") then
        viewer:getVariable("chameleon_hit")(pos, dir)
    end
    sounds["block.respawn_anchor.deplete"]:pos(pos):pitch(2 + math.random() * 0.5):volume(0.4):subtitle("Seeker shoots")
        :play()
    local hit, hit_pos = raycast:block(pos, pos + dir * 100)
    for i = 1, 50 do
        local p = math.lerp(models.model.root.RightArm:partToWorldMatrix():apply(0, -12, 0),
            hit_pos or pos + dir * math.random() * 100, math.random())
        local vel = vec((math.random() - 0.5) * 0.1, (math.random() + 0.5) * 0.1, (math.random() - 0.5) * 0.1)
        particles["item white_concrete"]
            :pos(p):color(vectors.hsvToRGB(math.random(), 1, 1):augmented(1))
            :scale(0.07 + math.random() * 0.07):gravity(0.5):physics(true):velocity(vel + dir * math.random() * 0.2)
            :spawn()
    end
end

function events.TICK()
    _arm_lerp = arm_lerp
    arm_lerp = math.lerp(arm_lerp, is_aiming and 1 or 0, 0.5)
end

function events.RENDER(delta)
    models.model.root.RightArm:offsetRot(math.lerp(_arm_lerp, arm_lerp, delta) * 90, 0, 0)
end

if not host:isHost() then return end

local PARTS = {
    models.model.root.Head,
    models.model.root.Body,
    models.model.root.LeftLeg,
    models.model.root.RightLeg,
    models.model.root.LeftArm,
    models.model.root.RightArm,
}

-- credit to GN and Auria!
local function screenToWorldSpace(distance, pos, fov, fovErr)
    local mat = matrices.mat4()
    local rot = client:getCameraRot()
    local win_size = client:getWindowSize()
    local mpos = (pos / win_size - vec(0.5, 0.5)) * vec(win_size.x / win_size.y, 1)
    local fov = math.tan(math.rad(fov / 2)) * 2 * fovErr
    mat:translate(mpos.x * -fov * distance, mpos.y * -fov * distance, 0)
    mat:rotate(rot.x, -rot.y, rot.z)
    mat:translate(client:getCameraPos())
    local pos = (mat * vectors.vec4(0, 0, distance, 1)).xyz
    return pos
end

local function mouseToWorldSpace(dist)
    local fov = client.getFOV()

    local mousePos = client:getMousePos()
    local win = client:getWindowSize()
    local pos = vectors.worldToScreenSpace(screenToWorldSpace(dist, mousePos, fov, 1)).xy
    local mousePos2 = (mousePos / win * 2 - 1)
    local fovErr = mousePos2:length() / pos:length()

    return screenToWorldSpace(dist, mousePos, fov, fovErr)
end

local function get_screen_dir()
    return (mouseToWorldSpace(100) - client.getCameraPos()):normalize()
end

---@param ray_start Vector3
---@param ray_end Vector3
---@param box_matrix Matrix4
---@param local_min Vector3
---@param local_max Vector3
---@return boolean, Vector3?, string?
local function raycast_obb(ray_start, ray_end, box_matrix, local_min, local_max)
    local inv = box_matrix:inverted()

    local local_start = inv:apply(ray_start)
    local local_end = inv:apply(ray_end)

    local hit_aabb, local_hit_pos, hit_face = raycast:aabb(local_start, local_end, { { local_min, local_max } })

    if not hit_aabb then return false end

    return true, box_matrix:apply(local_hit_pos), hit_face
end

---@param world_hit Vector3
---@param box_matrix Matrix4
---@param local_min Vector3
---@param local_max Vector3
---@param face string
---@return Vector2
local function oob_to_local_uv(world_hit, box_matrix, local_min, local_max, face)
    local inv = box_matrix:inverted()
    local p = inv:apply(world_hit)

    local size = local_max - local_min

    local x = (p.x - local_min.x) / size.x
    local y = (p.y - local_min.y) / size.y
    local z = (p.z - local_min.z) / size.z

    face = face:lower()

    if face == "up" then
        return vec(1 - x, 1 - z)
    elseif face == "down" then
        return vec(1 - x, 1 - z)
    elseif face == "north" then
        return vec(1 - x, 1 - y)
    elseif face == "south" then
        return vec(x, 1 - y)
    elseif face == "west" then
        return vec(z, 1 - y)
    elseif face == "east" then
        return vec(1 - z, 1 - y)
    end

    return vec(0, 0)
end

local PREVIEW = textures:newTexture("preview", 64, 64):fill(0, 0, 64, 64, vec(0, 0, 0, 0))

models:setSecondaryTexture("CUSTOM", PREVIEW)

local already_painted = {}

local function apply_on_face(part, fn)
    local vs = part:getAllVertices()["model.Skin"]

    local a = vs[1]:getUV()
    local b = vs[2]:getUV()
    local c = vs[3]:getUV()
    local d = vs[4]:getUV()

    local min_x = math.min(a.x, b.x, c.x, d.x)
    local min_y = math.min(a.y, b.y, c.y, d.y)
    local scl_x = math.max(a.x, b.x, c.x, d.x) - min_x
    local scl_y = math.max(a.y, b.y, c.y, d.y) - min_y

    fn(min_x, min_y, scl_x, scl_y)
end

local SMOOTH_BRUSH = keybinds:of("smooth_brush", "key.keyboard.left.alt", true)

local function paint_face(texture, part, uv, clr, scl, painting)
    apply_on_face(part, function(min_x, min_y, scl_x, scl_y)
        local fx = min_x + math.floor(uv.x * scl_x)
        local fy = min_y + math.floor(uv.y * scl_y)

        if painting then
            if already_painted[fx .. "-" .. fy] then return end
            already_painted[fx .. "-" .. fy] = true
        end

        local ax = math.max(fx - scl, min_x)
        local ay = math.max(fy - scl, min_y)

        local sx = math.min(scl * 2, fx) + 1
        local sy = math.min(scl * 2, fy) + 1

        if ax + sx > min_x + scl_x then
            sx = sx - math.floor(ax + sx - (min_x + scl_x))
        end

        if ay + sy > min_y + scl_y then
            sy = sy - math.floor(ay + sy - (min_y + scl_y))
        end

        texture:applyFunc(ax, ay, sx, sy, function(_, x, y)
            if vec(x - fx, y - fy):length() <= scl then
                if SMOOTH_BRUSH:isPressed() then
                    return math.lerp(_, clr, (1 - vec(x - fx, y - fy):length() / scl))
                else
                    return clr
                end
            end
        end)
    end)
end

local NBT = avatar:getNBT()
local function get_part_nbt(part)
    local guide = {}
    while part and part:getParent() do
        guide[#guide + 1] = part:getName()
        part = part:getParent()
    end

    local nbt = NBT.models.chld
    for i = #guide, 1, -1 do
        for j = 1, #nbt do
            local child = nbt[j]
            if child.name == guide[i] then
                nbt = i == 1 and child or child.chld
                break
            end
        end
        if not nbt then return end
    end

    return nbt
end

local editing = false

local brush_colour = vec(1, 1, 1)
local brush_size = 1
function events.MOUSE_SCROLL(dir)
    if not editing then return end
    brush_size = math.clamp(brush_size + dir, 1, 16)
    return true
end

local PAINT = keybinds:of("paint", "key.mouse.left", true)
local ROTATE = keybinds:of("rotate", "key.mouse.right", true)
local PICK = keybinds:of("pick", "key.mouse.middle", true)

function PAINT:release()
    already_painted = {}
end

local queue_pick = false
function PICK:press()
    if not editing then return end
    models:setSecondaryTexture("SECONDARY")
    queue_pick = true
end

local camrot = vec(0, 0, 0)

local EDIT = keybinds:of("edit mode", "key.keyboard.tab", true)

function EDIT:press()
    if host:isChatOpen() then return end
    if host:getScreen() then return end
    editing = not editing
    host:setUnlockCursor(editing)
    if editing then
        camrot = client.getCameraRot()
    end
end

local _edit_out = 0
local edit_out = 0

local rotate_view = vec(0, 0, 0)
function events.MOUSE_MOVE(x, y)
    if (editing and ROTATE:isPressed()) or (not editing and edit_out > 0.001) then
        rotate_view = rotate_view + vec(y, x, 0) * 0.5
        return true
    end
end

local shots = MAX_SHOTS

local AIM_GUN = keybinds:of("aim gun", "key.mouse.right", false)
function AIM_GUN:press()
    if not is_seeker then return end
    pings.aim_gun(true)
    return true
end

function AIM_GUN:release()
    if not is_seeker then return end
    pings.aim_gun(false)
    return true
end

local FIRE_GUN = keybinds:of("fire gun", "key.mouse.left", false)
function FIRE_GUN:press()
    if not is_seeker then return end
    if not is_aiming then return end
    if shots > 0 then
        shots = shots - 1
        pings.fire_gun(client.getCameraPos(), client.getCameraDir())
    else
        sounds["block.note_block.bass"]:pos(client.getCameraPos()):volume(0.5):pitch(0.3):subtitle(
            "Out of ammo")
            :play()
    end
    host:swingArm()
    return true
end

local charge_shot = 0
function events.TICK()
    if shots < MAX_SHOTS then
        charge_shot = charge_shot + 1
        if charge_shot == SHOT_RECHARGE_TICKS then
            charge_shot = 0
            shots = shots + 1
            sounds["block.anvil.place"]:pos(client.getCameraPos()):volume(0.1):pitch(2.5 + shots / MAX_SHOTS / 2)
                :subtitle("Gained ammo"):play()
        end
    end
end

local CHANGE_PERSPECTIVE = keybinds:of("change perspective", "key.keyboard.space", true)

local spectating_player = nil
local active_perspective = 1
function CHANGE_PERSPECTIVE:press()
    if is_seeker then return end
    if not editing and statue_timer <= 10 then return end

    local perspectives = { player }
    for name, entity in next, world.getPlayers() do
        if entity ~= player and entity:getVariable("chameleon_player") then
            perspectives[#perspectives + 1] = entity
        end
    end

    active_perspective = (active_perspective % #perspectives) + 1
    spectating_player = perspectives[active_perspective]

    if spectating_player == player then
        renderer:cameraRot()
    end

    return true
end

local HUD = models:newPart("hud", "HUD")

function events.TICK()
    HUD:removeTask()

    _edit_out = edit_out
    edit_out = math.lerp(edit_out, editing and 1 or 0, 0.5)

    local hud_text = ""

    if editing then
        hud_text = hud_text .. "§a[" .. PAINT:getKeyName():lower() .. "] §rpaint"
        hud_text = hud_text .. "\n§a[" .. ROTATE:getKeyName():lower() .. "] §rrotate view"
        hud_text = hud_text .. "\n§a[" .. PICK:getKeyName():lower() .. "] §rpick colour"
        hud_text = hud_text .. "\n§a[scroll] §rbrush size"
        hud_text = hud_text .. "\n§a[" .. SMOOTH_BRUSH:getKeyName():lower() .. "] §rsmooth brush"
        if not is_seeker then
            hud_text = hud_text .. "\n§a[" .. CHANGE_PERSPECTIVE:getKeyName():lower() .. "] §rchange perspective"
        end
        hud_text = hud_text .. "\n§a[" .. EDIT:getKeyName():lower() .. "] §rexit edit mode"
    else
        if statue_timer > 10 and not is_seeker then
            hud_text = hud_text .. "§a[" .. CHANGE_PERSPECTIVE:getKeyName():lower() .. "] §rchange perspective\n"
        end
        if is_seeker then
            if is_aiming then
                hud_text = hud_text .. "§a[" .. FIRE_GUN:getKeyName():lower() .. "] §rfire gun\n"
            end
            hud_text = hud_text .. "§a[" .. AIM_GUN:getKeyName():lower() .. "] §raim gun\n"
        end
        hud_text = hud_text .. "§a[" .. EDIT:getKeyName():lower() .. "] §redit mode"
    end

    HUD:newText("info")
        :text(hud_text)
        :scale(1)
        :pos(client.getScaledWindowSize():mul(-0.5, -1):add(-94, client.getTextHeight(hud_text) + 2).xy_)
        :outline(true)
        :background(true)

    if spectating_player and spectating_player ~= player then
        local player_is_seeker = spectating_player:getVariable("is_seeker")
        HUD:newText("spectating")
            :text("Spectating " .. (player_is_seeker and "§c" or "§a") .. spectating_player:getName())
            :outline(true)
            :scale(2)
            :alignment("CENTER")
            :pos(client.getScaledWindowSize():mul(-0.5, 0):add(0, -48, 0).xy_)
    end

    if is_seeker then
        local n_hiders = 0
        for name, entity in next, world.getPlayers() do
            if entity:getVariable("chameleon_player") and not entity:getVariable("is_seeker") then
                n_hiders = n_hiders + 1
            end
        end
        local seeker_text = ("§a%i §7%s\n"):format(n_hiders, n_hiders == 1 and "hider remains" or "hiders remain")
        for i = 1, MAX_SHOTS do
            if i > shots then
                seeker_text = seeker_text .. " §7:spinner_dark: "
            else
                seeker_text = seeker_text .. " :gun: "
            end
        end
        HUD:newText("seeker")
            :text(seeker_text)
            :outline(true)
            :scale(2)
            :alignment("CENTER")
            :pos(client.getScaledWindowSize():mul(-0.5, 0):add(0, -48, 0).xy_)
    end
end

local to_send = ""
local to_send_size = 0
function events.TICK()
    if world.getTime() % 5 ~= 0 then return end

    if #to_send == 0 then
        to_send = TEXTURE:save()
        to_send_size = #to_send
    else
        local packet, remainder = to_send:sub(1, PING_LIMIT / 4), to_send:sub(PING_LIMIT / 4 + 1, -1)
        pings.receive_texture_data(#to_send == to_send_size, to_send_size, packet)
        to_send = remainder
    end
end

function events.POST_WORLD_RENDER()
    if not queue_pick then return end

    queue_pick = false
    local screenshot = host:screenshot("pick_texture")
    models:setSecondaryTexture("CUSTOM", PREVIEW)
    brush_colour = vectors.rgbToHSV(screenshot:getPixel((client.getMousePos()):unpack()).xyz)
end

function events.WORLD_RENDER(delta)
    if spectating_player and spectating_player ~= player and not is_seeker then
        renderer:setCameraPivot(spectating_player:getPos(delta) + vec(0, 1.6, 0))
        if not editing then
            renderer:setCameraRot(spectating_player:getRot(delta).xy_)
        end
    else
        renderer:setCameraPivot()
    end
end

local particle_pos = {}
function events.RENDER(delta)
    if editing then
        renderer:setCameraRot(camrot + rotate_view)
    else
        if (not spectating_player) or spectating_player == player then
            if edit_out > 0.001 then
                renderer:setCameraRot(camrot + rotate_view * math.lerp(_edit_out, edit_out, delta))
            elseif rotate_view:length() > 0.001 then
                renderer:setCameraRot()
                rotate_view = vec(0, 0, 0)
            end
        else
            rotate_view = vec(0, 0, 0)
        end
    end

    PREVIEW:fill(0, 0, 64, 64, vec(0, 0, 0, 0))

    if not editing then
        PREVIEW:update()
        return
    end

    local ray_start = client.getCameraPos()
    local ray_end = ray_start + get_screen_dir() * 100

    for i = 1, #PARTS do
        local part = PARTS[i]
        local mat = part:partToWorldMatrix()
        local part_nbt = get_part_nbt(part:getChildren()[1])

        local piv = vec(table.unpack(part_nbt.piv))
        local from = vec(table.unpack(part_nbt.f)) - piv
        local to = vec(table.unpack(part_nbt.t)) - piv
        local hit, hit_pos, hit_face = raycast_obb(ray_start, ray_end, mat, from, to)

        if hit and hit_pos and hit_face then
            local uv = oob_to_local_uv(hit_pos, part:partToWorldMatrix(), from, to, hit_face)

            if PAINT:isPressed() then
                particle_pos[#particle_pos + 1] = hit_pos
                paint_face(TEXTURE, part[hit_face], uv, vectors.hsvToRGB(brush_colour):augmented(1), brush_size / 2, true)
            else
                paint_face(PREVIEW, part[hit_face], uv, vectors.hsvToRGB(brush_colour):augmented(1), brush_size / 2)
            end
        end
    end

    TEXTURE:update()
    PREVIEW:update()
end

local PARTICLES_PER_TICK = 5
function events.TICK()
    if not particle_pos[1] then return end
    for i = 1, PARTICLES_PER_TICK do
        local pos = particle_pos[math.random(1, #particle_pos)]
        local vel = vec((math.random() - 0.5) * 0.1, (math.random() + 0.5) * 0.1, (math.random() - 0.5) * 0.1)
        particles["item white_concrete"]
            :pos(pos):color(vectors.hsvToRGB(brush_colour):augmented(1))
            :scale(0.07 + math.random() * 0.07):gravity(0.5):physics(true):velocity(vel)
            :spawn()
    end
    particle_pos = {}
end

local TEXTURE_SIZE = 32

local sat_value_texture = textures:newTexture("sat_value", TEXTURE_SIZE, TEXTURE_SIZE)
local hue_texture = textures:newTexture("hue", 1, TEXTURE_SIZE):applyFunc(0, 0, 1, TEXTURE_SIZE, function(_, _, y)
    local hsv = vec(y / TEXTURE_SIZE, 1, 1)
    local rgb = vectors.hsvToRGB(hsv)
    return rgb:augmented(1)
end)

local SCALE = 192
local HUE_OFFSET = vec(-0.5, 0.5) * SCALE
local SAT_VALUE_OFFSET = vec(0.5, 0.5) * SCALE

---@return Vector3
local function get_hue_pos()
    local window_size = client.getScaledWindowSize()
    return vec(-window_size.x + 128 + HUE_OFFSET.x, -window_size.y / 2 + HUE_OFFSET.y, 0)
end

---@return Vector3
local function get_sat_value_pos()
    local window_size = client.getScaledWindowSize()
    return vec(-window_size.x + 128 + SAT_VALUE_OFFSET.x, -window_size.y / 2 + SAT_VALUE_OFFSET.y, 0)
end

local _brush_colour = vec(0, 0, 0)
local hue_changed = false
function events.RENDER()
    if not editing then return end

    if _brush_colour ~= brush_colour then
        _brush_colour = brush_colour
        hue_changed = true
    end

    local gui_scale = client.getGuiScale()
    local mouse_pos = -client.getMousePos() / gui_scale

    local hue_pos = get_hue_pos()
    local sat_value_pos = get_sat_value_pos()

    if PAINT:isPressed() then
        if mouse_pos.x < hue_pos.x and mouse_pos.x > hue_pos.x - SCALE / 32 then
            if mouse_pos.y < hue_pos.y and mouse_pos.y > hue_pos.y - SCALE then
                local y = hue_pos.y - mouse_pos.y
                brush_colour = vec(1 - y / SCALE, brush_colour.y, brush_colour.z)
                hue_changed = true
            end
        elseif mouse_pos.x < sat_value_pos.x and mouse_pos.x > sat_value_pos.x - SCALE then
            if mouse_pos.y < sat_value_pos.y and mouse_pos.y > sat_value_pos.y - SCALE then
                local x = sat_value_pos.x - mouse_pos.x
                local y = sat_value_pos.y - mouse_pos.y
                brush_colour = vec(brush_colour.x, x / SCALE, 1 - y / SCALE)
            end
        end
    end

    HUD:newText("cursor_hue")
        :text(toJson {
            {
                text = "☐",
                color = "#" .. vectors.rgbToHex(vectors.hsvToRGB(brush_colour))
            },
        })
        :pos(get_hue_pos() + vec(2, -SCALE + brush_colour.x * SCALE + 3, -20))
        :outline(true)

    HUD:newText("cursor_sat_val")
        :text(toJson {
            {
                text = "☐",
                color = "#" .. vectors.rgbToHex(vectors.hsvToRGB(brush_colour))
            },
        })
        :pos(get_sat_value_pos() + vec(-brush_colour.y * SCALE + 4, -SCALE + brush_colour.z * SCALE + 2, -20))
        :outline(true)
        :outlineColor(vectors.hsvToRGB(vec(0, 0, 1) - brush_colour:copy():mul(0, 0, 1)))

    HUD:newSprite("hue")
        :texture(hue_texture)
        :pos(get_hue_pos())
        :region(1, 1)
        :size(SCALE / 32, SCALE)
        :renderType("BLURRY")

    if hue_changed then
        sat_value_texture:applyFunc(0, 0, TEXTURE_SIZE, TEXTURE_SIZE, function(_, x, y)
            local hsv = vec(brush_colour.x, 1 - x / TEXTURE_SIZE, y / TEXTURE_SIZE)
            local rgb = vectors.hsvToRGB(hsv)
            return rgb:augmented()
        end):update()

        hue_changed = false
    end

    HUD:newSprite("sat_value")
        :texture(sat_value_texture)
        :pos(get_sat_value_pos())
        :region(1, 1)
        :size(SCALE, SCALE)
        :renderType("BLURRY")
end

local page = action_wheel:newPage("animations")
action_wheel:setPage(page)

local switch_action = page:newAction()
local function switch_user_type(seeker)
    pings.set_user_type(seeker)
    renderer:cameraPivot():cameraRot()
    spectating_player = nil
    switch_action
        :title(("You are a: %s"):format(seeker and "§cSeeker" or "§aHider"))
        :onToggle(switch_user_type)
        :color(vec(0, 1, 0))
        :toggleColor(vec(1, 0, 0))
        :setItem(seeker and "diamond_sword" or "shield")
        :setToggled(seeker)
end

switch_user_type(true)

avatar:store("chameleon_hit", function(pos, dir)
    local ray_start = pos
    local ray_end = pos + dir * 100

    local any_hit = false
    for i = 1, #PARTS do
        local part = PARTS[i]
        local mat = part:partToWorldMatrix()
        local part_nbt = get_part_nbt(part:getChildren()[1])

        local piv = vec(table.unpack(part_nbt.piv))
        local from = vec(table.unpack(part_nbt.f)) - piv
        local to = vec(table.unpack(part_nbt.t)) - piv
        local hit, hit_pos, hit_face = raycast_obb(ray_start, ray_end, mat, from, to)

        if hit and hit_pos and hit_face then
            any_hit = true
            local uv = oob_to_local_uv(hit_pos, part:partToWorldMatrix(), from, to, hit_face)

            particle_pos[#particle_pos + 1] = hit_pos
            paint_face(TEXTURE, part[hit_face], uv, vectors.hsvToRGB(math.random(), 1, 1):augmented(1), 2, true)
        end
    end

    TEXTURE:update()

    if any_hit then
        switch_user_type(true)
    end
end)

local fetch_poses = {}
local poses = {}

local anims = animations:getAnimations()
for i = 1, #anims do
    local anim = anims[i]
    local item_str = ("player_head" .. toJson {
        SkullOwner = {
            Id = {
                client.uuidToIntArray(avatar:getUUID())
            },
        },
        display = {
            Name = "pose" .. i
        },
    }):gsub('"Id":%[', '"Id":[I;')

    page:newAction()
        :title(anim:getName())
        :onToggle(function(val, self)
            local actions = page:getActions()
            for j = 1, #actions do
                actions[j]:setToggled(false)
            end
            self:setToggled(val)
            if val then
                pings.toggle_animation(anim:getName())
            else
                pings.toggle_animation()
            end
        end)
        :toggleColor(vec(0, 1, 0))
        :setItem(item_str)

    fetch_poses[#fetch_poses + 1] = anim
end

local last_pose = nil

---@param model ModelPart
---@param apply? fun(copy: ModelPart, original: ModelPart)
---@return ModelPart
local function deep_copy(model, apply)
    local copy = model:copy(model:getName())
    _ = apply and apply(copy, model)
    local children = copy:getChildren()
    for i = 1, #children do
        local child = children[i]
        copy:removeChild(child):addChild(deep_copy(child, apply))
        model:removeChild(child):addChild(child)
    end
    return copy
end

local skull_part = models:newPart("skull", "Skull")
function events.WORLD_RENDER()
    if last_pose then
        local copy_part = models:newPart("a"):moveTo(skull_part):visible(false):pos(0, -8, 0)

        deep_copy(models.model, function(copy, original)
            copy
                :setRot(original:getAnimRot())
                :setPos(original:getAnimPos())
                :setScale(original:getAnimScale())
                :setParentType("NONE")
        end):moveTo(copy_part)

        poses[#poses + 1] = copy_part
        last_pose:stop()
    end

    local pose = table.remove(fetch_poses, 1)
    if not pose then
        last_pose = nil
        return
    end

    pose:play()
    last_pose = pose
end

local last_part = nil
function events.SKULL_RENDER(_, _, item)
    if last_part then
        last_part:visible(false)
        last_part = nil
    end
    if not item then return end

    local pose_id = item:toStackString():match("pose(%d+)")
    if not pose_id then return end

    local pose = poses[tonumber(pose_id)]
    if not pose then return end

    last_part = pose
    last_part:visible(true)
end
