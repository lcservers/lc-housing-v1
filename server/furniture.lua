local function frameworkResource()
    if Config.Framework == 'qb' then return Config.FrameworkResources.qb end
    if Config.Framework == 'qbox' then return Config.FrameworkResources.qbox end
    if GetResourceState(Config.FrameworkResources.qbox) == 'started' then return Config.FrameworkResources.qbox end
    return Config.FrameworkResources.qb
end

local Core

local function getCore()
    if Core then return Core end
    Core = exports[frameworkResource()]:GetCoreObject()
    return Core
end
local catalog = {}

for category, group in pairs(Config.Furniture or {}) do
    for _, item in ipairs(group.items or {}) do
        catalog[item.object] = { model = item.object, label = item.label or item.object, price = tonumber(item.price) or 0, category = category }
    end
end

local function identifier(src)
    local player = getCore().Functions.GetPlayer(src)
    return player and (player.PlayerData.citizenid or player.PlayerData.license), player
end

local function houseRow(name)
    return MySQL.single.await('SELECT name, label, owner, created_by, property_type, polyzone FROM lc_houses WHERE name = ?', { tostring(name or '') })
end

local function isOwner(src, house)
    local cid, player = identifier(src)
    return player and house and house.owner == cid, player
end

local function canManage(src, house)
    local owned, player = isOwner(src, house)
    if owned then return true, player end
    if not player or not player.PlayerData.job then return false, player end
    local job = player.PlayerData.job
    local grade = type(job.grade) == 'table' and (job.grade.level or job.grade.grade) or job.grade
    local staff = job.name == Config.JobName and (not Config.RequireOnDuty or job.onduty)
    return staff and (tonumber(grade) or 0) >= ((Config.Permissions and Config.Permissions.edit) or 0), player
end

local function decodePoly(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or {}
end

local function pointInPoly(x, y, points)
    local inside, j = false, #points
    for i = 1, #points do
        local xi, yi = tonumber(points[i].x), tonumber(points[i].y)
        local xj, yj = tonumber(points[j].x), tonumber(points[j].y)
        if xi and yi and xj and yj and ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 and 0.00001 or (yj - yi)) + xi) then inside = not inside end
        j = i
    end
    return inside
end

local function placementAllowed(src, house, data)
    if not house then return false, 'Property not found.' end
    local propertyType = tostring(house.property_type or 'shell'):lower()
    if propertyType == 'ipl' then return false, 'IPL properties already include furniture and cannot be decorated.' end

    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not x or not y or not z then return false, 'Invalid furniture coordinates.' end
    local ped = GetPlayerPed(src)
    local playerCoords = ped and ped > 0 and GetEntityCoords(ped)
    if not playerCoords then return false, 'Player position unavailable.' end

    if #(playerCoords - vector3(x, y, z)) > (tonumber(Config.Decoration.shellPlacementDistance) or 25.0) then
        return false, 'Furniture must be placed near your current position.'
    end

    if propertyType == 'mlo' then
        local poly = decodePoly(house.polyzone)
        if #poly < 3 or not pointInPoly(playerCoords.x, playerCoords.y, poly) or not pointInPoly(x, y, poly) then
            return false, 'Furniture must remain inside the MLO property PolyZone.'
        end
    elseif Player(src).state.lcHouse ~= house.name then
        return false, 'Enter this shell property before decorating it.'
    end
    return true
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lc_house_furniture` (
          `id` bigint unsigned NOT NULL AUTO_INCREMENT,
          `house_name` varchar(64) NOT NULL,
          `model` varchar(100) NOT NULL,
          `label` varchar(100) DEFAULT NULL,
          `x` decimal(12,4) NOT NULL,
          `y` decimal(12,4) NOT NULL,
          `z` decimal(12,4) NOT NULL,
          `rot_x` decimal(8,3) NOT NULL DEFAULT 0,
          `rot_y` decimal(8,3) NOT NULL DEFAULT 0,
          `rot_z` decimal(8,3) NOT NULL DEFAULT 0,
          `created_by` varchar(64) DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`id`),
          KEY `idx_lc_furniture_house` (`house_name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    print('[lc-housing] Furniture persistence ready.')
end)

getCore().Functions.CreateCallback('lc-housing:furniture:get', function(source, cb, houseName)
    if Config.Decoration and Config.Decoration.enabled == false then cb({ ok = false, message = 'Furniture decoration is disabled.' }) return end
    local house = houseRow(houseName)
    if not house then cb({ ok = false, message = 'Property not found.' }) return end
    if tostring(house.property_type):lower() == 'ipl' then cb({ ok = false, message = 'IPL decoration is disabled.' }) return end
    local rows = MySQL.query.await('SELECT id, house_name, model, label, x, y, z, rot_x, rot_y, rot_z FROM lc_house_furniture WHERE house_name = ? ORDER BY id', { house.name }) or {}
    cb({ ok = true, house = { name = house.name, label = house.label, propertyType = house.property_type }, furniture = rows })
end)

getCore().Functions.CreateCallback('lc-housing:furniture:canDecorate', function(source, cb, houseName)
    if Config.Decoration and Config.Decoration.enabled == false then cb({ ok = false, message = 'Furniture decoration is disabled.' }) return end
    local house = houseRow(houseName)
    local allowed = canManage(source, house)
    if not allowed then cb({ ok = false, message = 'The property owner or an authorized real-estate agent can decorate this home.' }) return end
    if tostring(house.property_type):lower() == 'ipl' then cb({ ok = false, message = 'IPL properties already include furniture.' }) return end
    local ped = GetPlayerPed(source)
    local coords = ped > 0 and GetEntityCoords(ped)
    if tostring(house.property_type):lower() == 'mlo' then
        local poly = decodePoly(house.polyzone)
        if not coords or #poly < 3 or not pointInPoly(coords.x, coords.y, poly) then cb({ ok = false, message = 'Enter the MLO property PolyZone before decorating.' }) return end
    elseif Player(source).state.lcHouse ~= house.name then
        cb({ ok = false, message = 'Enter this shell property before decorating.' }) return
    end
    cb({ ok = true })
end)

getCore().Functions.CreateCallback('lc-housing:furniture:save', function(source, cb, data)
    if Config.Decoration and Config.Decoration.enabled == false then cb({ ok = false, message = 'Furniture decoration is disabled.' }) return end
    data = data or {}
    local house = houseRow(data.houseName)
    local owned, player = canManage(source, house)
    if not owned then cb({ ok = false, message = 'The property owner or an authorized real-estate agent can change furniture.' }) return end
    local allowed, reason = placementAllowed(source, house, data)
    if not allowed then cb({ ok = false, message = reason }) return end

    local item = catalog[tostring(data.model or '')]
    if not item then cb({ ok = false, message = 'Furniture model is not in the LC catalogue.' }) return end
    local id = tonumber(data.id)
    if id then
        local exists = MySQL.scalar.await('SELECT id FROM lc_house_furniture WHERE id = ? AND house_name = ?', { id, house.name })
        if not exists then cb({ ok = false, message = 'Furniture item not found.' }) return end
        MySQL.update.await('UPDATE lc_house_furniture SET x=?, y=?, z=?, rot_x=?, rot_y=?, rot_z=? WHERE id=? AND house_name=?', { data.x, data.y, data.z, data.rotX or 0, data.rotY or 0, data.rotZ or 0, id, house.name })
    else
        local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM lc_house_furniture WHERE house_name = ?', { house.name })) or 0
        if count >= (tonumber(Config.Decoration.maxFurniture) or 150) then cb({ ok = false, message = 'This property has reached its furniture limit.' }) return end
        if item.price > 0 and not player.Functions.RemoveMoney('bank', item.price, 'lc-house-furniture') then cb({ ok = false, message = 'Not enough money in your bank account.' }) return end
        local creator = identifier(source)
        id = MySQL.insert.await('INSERT INTO lc_house_furniture (house_name, model, label, x, y, z, rot_x, rot_y, rot_z, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', { house.name, item.model, item.label, data.x, data.y, data.z, data.rotX or 0, data.rotY or 0, data.rotZ or 0, creator })
    end
    TriggerClientEvent('lc-housing:furniture:refresh', -1, house.name)
    cb({ ok = true, id = id, message = 'Furniture saved.' })
end)

getCore().Functions.CreateCallback('lc-housing:furniture:delete', function(source, cb, data)
    if Config.Decoration and Config.Decoration.enabled == false then cb({ ok = false, message = 'Furniture decoration is disabled.' }) return end
    data = data or {}
    local house = houseRow(data.houseName)
    local owned, player = canManage(source, house)
    if not owned then cb({ ok = false, message = 'The property owner or an authorized real-estate agent can remove furniture.' }) return end
    local row = MySQL.single.await('SELECT id, model FROM lc_house_furniture WHERE id = ? AND house_name = ?', { tonumber(data.id) or 0, house.name })
    if not row then cb({ ok = false, message = 'Furniture item not found.' }) return end
    MySQL.update.await('DELETE FROM lc_house_furniture WHERE id = ? AND house_name = ?', { row.id, house.name })
    local item = catalog[row.model]
    local refund = math.floor(((item and item.price) or 0) * (tonumber(Config.Decoration.refundPercent) or 0.5))
    if refund > 0 then player.Functions.AddMoney('bank', refund, 'lc-house-furniture-refund') end
    TriggerClientEvent('lc-housing:furniture:refresh', -1, house.name)
    cb({ ok = true, refund = refund, message = ('Furniture removed. Refund: $%s'):format(refund) })
end)
