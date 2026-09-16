local Core

local function frameworkResource()
    if Config.Framework == 'qb' then return Config.FrameworkResources.qb end
    if Config.Framework == 'qbox' then return Config.FrameworkResources.qbox end
    if GetResourceState(Config.FrameworkResources.qbox) == 'started' then return Config.FrameworkResources.qbox end
    return Config.FrameworkResources.qb
end

local function getCore()
    if Core then return Core end
    local resource = frameworkResource()
    Core = exports[resource]:GetCoreObject()
    return Core
end

local function createCallback(name, fn)
    getCore().Functions.CreateCallback(name, fn)
end

local function notify(src, message, msgType)
    TriggerClientEvent('QBCore:Notify', src, message, msgType or 'primary')
end


local function debugLog(message)
    if Config.Debug then print(('[lc-housing] %s'):format(message)) end
end

local function gradeLevel(Player)
    local grade = Player.PlayerData.job and Player.PlayerData.job.grade
    if type(grade) == 'table' then
        return tonumber(grade.level or grade.grade or 0) or 0
    end
    return tonumber(grade) or 0
end

local function hasPermission(src, action)
    local Player = getCore().Functions.GetPlayer(src)
    if not Player or not Player.PlayerData.job then return false end

    local job = Player.PlayerData.job
    if job.name ~= Config.JobName then return false end
    if Config.RequireOnDuty and not job.onduty then return false end

    return gradeLevel(Player) >= (Config.Permissions[action] or 0), Player
end

local function cleanName(value)
    value = tostring(value or ""):lower()
    value = value:gsub("[^%w%s_#%-]", "")
    value = value:gsub("%s+", "_")
    value = value:gsub("_+", "_")
    value = value:gsub("^_+", ""):gsub("_+$", "")
    return value
end

local function nextHouseName(base)
    base = cleanName(base):gsub("_#%d+$", ""):gsub("_%d+$", "")
    if base == "" then base = "house" end

    local pattern = base .. "_#%"
    local rows = MySQL.query.await('SELECT name FROM lc_houses WHERE name LIKE ?', { pattern }) or {}

    local prefix = base .. "_#"
    local highest = 0
    for _, row in ipairs(rows) do
        local name = tostring(row.name or "")
        if name:sub(1, #prefix) == prefix then
            highest = math.max(highest, tonumber(name:sub(#prefix + 1)) or 0)
        end
    end

    local suffix = ("_#%s"):format(highest + 1)
    return ("%s%s"):format(base:sub(1, 64 - #suffix), suffix)
end

local function numberOrNil(value)
    local n = tonumber(value)
    if not n then return nil end
    return tonumber(('%0.3f'):format(n))
end

local function makeCoords(data)
    local x, y, z = numberOrNil(data.x), numberOrNil(data.y), numberOrNil(data.z)
    local h = numberOrNil(data.h) or 0.0
    if not x or not y or not z then return nil end

    return {
        enter = { x = x, y = y, z = z, h = h },
        cam = { x = x, y = y, z = z + 1.5, h = h },
        yaw = h
    }
end

local function makeGarage(data)
    if not Config.Garage or not Config.Garage.enabled then
        if data and data.garageEnabled then debugLog('Garage payload ignored because Config.Garage.enabled is false.') end
        return nil
    end
    if not data or not data.garageEnabled then return nil end
    local x, y, z = numberOrNil(data.garageX), numberOrNil(data.garageY), numberOrNil(data.garageZ)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, w = numberOrNil(data.garageW) or 0.0 }
end

local function makePolyzone(data)
    local points = data.polyzone
    if type(points) == 'string' then points = json.decode(points or '[]') or {} end
    if type(points) ~= 'table' then return {} end

    local clean = {}
    for _, point in ipairs(points) do
        local x, y, z = numberOrNil(point.x), numberOrNil(point.y), numberOrNil(point.z)
        if x and y and z then clean[#clean + 1] = { x = x, y = y, z = z } end
    end
    return clean
end

local function makeInterior(data)
    local propertyType = tostring(data.propertyType or Config.Defaults.type or 'shell'):lower()
    if propertyType ~= 'shell' and propertyType ~= 'mlo' and propertyType ~= 'ipl' then propertyType = 'shell' end

    return propertyType, {
        type = propertyType,
        shell = tostring(data.shell or Config.Defaults.shell or ''):sub(1, 64),
        ipl = tostring(data.ipl or Config.Defaults.ipl or ''):sub(1, 96),
        mlo = tostring(data.mlo or Config.Defaults.mlo or ''):sub(1, 96)
    }
end

local function playerIdentifier(Player)
    return Player.PlayerData.citizenid or Player.PlayerData.license or 'unknown'
end

local function makeDoorLocks(data)
    local doors = data and data.doorLocks
    if type(doors) == "string" then doors = json.decode(doors or "[]") or {} end
    if type(doors) ~= "table" then return {} end

    local clean = {}
    for _, door in ipairs(doors) do
        local coords = door.coords or door
        local x, y, z = numberOrNil(coords.x), numberOrNil(coords.y), numberOrNil(coords.z)
        local model = door.model or door.hash
        if x and y and z and model then
            clean[#clean + 1] = {
                name = tostring(door.name or ("Door " .. (#clean + 1))):sub(1, 64),
                doorType = door.doorType == 'double' and 'double' or (door.doorType == 'garage' and 'garage' or 'single'),
                panel = tostring(door.panel or ''):sub(1, 16),
                model = model,
                coords = { x = x, y = y, z = z },
                radius = numberOrNil(door.radius) or (Config.DoorLocks and Config.DoorLocks.defaultRadius) or 1.5,
                heading = numberOrNil(door.heading) or 0.0
            }
        end
    end
    return clean
end

local function getHouseDoors(houseName)
    local rows = MySQL.query.await("SELECT id, name, door_type, panel, model, coords, heading, radius FROM lc_house_doors WHERE house_name = ? ORDER BY id ASC", { houseName }) or {}
    local doors = {}

    for _, row in ipairs(rows) do
        local coords = json.decode(row.coords or "{}") or {}
        if numberOrNil(coords.x) and numberOrNil(coords.y) and numberOrNil(coords.z) then
            doors[#doors + 1] = {
                id = tonumber(row.id) or nil,
                name = tostring(row.name or ("Door " .. (#doors + 1))):sub(1, 64),
                doorType = row.door_type == "double" and "double" or (row.door_type == "garage" and "garage" or "single"),
                panel = tostring(row.panel or ""):sub(1, 16),
                model = tonumber(row.model) or row.model,
                coords = { x = numberOrNil(coords.x), y = numberOrNil(coords.y), z = numberOrNil(coords.z) },
                heading = numberOrNil(row.heading) or 0.0,
                radius = numberOrNil(row.radius) or (Config.DoorLocks and Config.DoorLocks.defaultRadius) or 1.5
            }
        end
    end

    return doors
end

local function replaceHouseDoors(houseName, doors)
    local clean = makeDoorLocks({ doorLocks = doors or {} })
    MySQL.update.await("DELETE FROM lc_house_doors WHERE house_name = ?", { houseName })

    for _, door in ipairs(clean) do
        MySQL.insert.await("INSERT INTO lc_house_doors (house_name, name, door_type, panel, model, coords, heading, radius) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", {
            houseName,
            door.name,
            door.doorType or "single",
            door.panel or "",
            tostring(door.model),
            json.encode(door.coords),
            tonumber(door.heading) or 0.0,
            tonumber(door.radius) or (Config.DoorLocks and Config.DoorLocks.defaultRadius) or 1.5
        })
    end

    return clean
end

local function defaultSettings(doors)
    return {
        locked = type(doors) == "table" and #doors > 0,
        rentable = false,
        rent = 0,
        stash = nil,
        wardrobe = nil,
        logout = nil,
        exit = Config.Interior.defaultExit,
        doors = doors or {}
    }
end

local function doorGroupKey(door, index)
    if type(door) ~= 'table' then return ('single:%s'):format(index or 1) end
    local doorType = tostring(door.doorType or 'single'):lower()
    if doorType == 'double' then
        local name = tostring(door.name or ('door_' .. tostring(index or 1)))
        name = name:gsub('%s+[12]$', '')
        return ('double:%s'):format(name)
    end
    if doorType == 'garage' then
        return ('garage:%s'):format(index or tostring(door.name or 'door'))
    end
    return ('single:%s'):format(index or tostring(door.name or 'door'))
end

local function doorLockedState(settings, door, index)
    settings = settings or {}
    local states = type(settings.doorStates) == 'table' and settings.doorStates or {}
    local key = doorGroupKey(door, index)
    if states[key] ~= nil then return states[key] == true end
    if type(door) == 'table' and door.locked ~= nil then return door.locked == true end
    return settings.locked == true
end

local function decodeSettings(value)
    local decoded = json.decode(value or '{}') or {}
    local defaults = defaultSettings()
    for key, defaultValue in pairs(defaults) do
        if decoded[key] == nil then decoded[key] = defaultValue end
    end
    return decoded
end

local function migrateDoorSettingsToTable()
    local rows = MySQL.query.await("SELECT name, settings FROM lc_houses WHERE settings IS NOT NULL AND settings != ''", {}) or {}

    for _, row in ipairs(rows) do
        local existing = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM lc_house_doors WHERE house_name = ?", { row.name }) or 0) or 0
        if existing == 0 then
            local settings = decodeSettings(row.settings)
            if type(settings.doors) == "table" and #settings.doors > 0 then
                replaceHouseDoors(row.name, settings.doors)
            end
        end
    end
end

local function ownedBy(row, identifier)
    return identifier and identifier ~= '' and row and row.owner == identifier
end

local function addMoney(Player, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    return Player.Functions.AddMoney(account, amount, reason or 'house-refund')
end

local function removeMoney(Player, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end

    local money = Player.PlayerData.money or {}
    if (tonumber(money[account]) or 0) >= amount then
        return Player.Functions.RemoveMoney(account, amount, reason or 'house-purchase')
    end

    if Config.Purchase.allowCashFallback and account ~= 'cash' and (tonumber(money.cash) or 0) >= amount then
        return Player.Functions.RemoveMoney('cash', amount, reason or 'house-purchase')
    end

    return false
end

local function columnExists(column)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'lc_houses' AND COLUMN_NAME = ?
    ]], { column })
    return (tonumber(count) or 0) > 0
end

local function addColumn(column, definition)
    if not columnExists(column) then
        MySQL.query.await(('ALTER TABLE `lc_houses` ADD COLUMN `%s` %s'):format(column, definition))
    end
end

local function ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS lc_house_doors (
          id int(11) NOT NULL AUTO_INCREMENT,
          house_name varchar(64) NOT NULL,
          name varchar(64) NOT NULL,
          door_type varchar(16) NOT NULL DEFAULT 'single',
          panel varchar(16) DEFAULT NULL,
          model varchar(64) NOT NULL,
          coords longtext NOT NULL,
          heading double NOT NULL DEFAULT 0,
          radius double NOT NULL DEFAULT 1.5,
          created_at timestamp NOT NULL DEFAULT current_timestamp(),
          updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (id),
          KEY house_name (house_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lc_houses` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `name` varchar(64) NOT NULL,
          `label` varchar(96) NOT NULL,
          `price` int(11) NOT NULL DEFAULT 0,
          `property_type` varchar(16) NOT NULL DEFAULT 'shell',
          `shell` varchar(64) DEFAULT NULL,
          `ipl` varchar(96) DEFAULT NULL,
          `mlo` varchar(96) DEFAULT NULL,
          `image` text DEFAULT NULL,
          `owner` varchar(64) DEFAULT NULL,
          `owned` tinyint(1) NOT NULL DEFAULT 0,
          `coords` longtext NOT NULL,
          `polyzone` longtext DEFAULT NULL,
          `interior` longtext DEFAULT NULL,
          `settings` longtext DEFAULT NULL,
          `created_by` varchar(64) DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`id`),
          UNIQUE KEY `name` (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    addColumn('property_type', "varchar(16) NOT NULL DEFAULT 'shell'")
    addColumn('ipl', 'varchar(96) DEFAULT NULL')
    addColumn('mlo', 'varchar(96) DEFAULT NULL')
    addColumn('polyzone', 'longtext DEFAULT NULL')
    addColumn('interior', 'longtext DEFAULT NULL')
    addColumn('settings', 'longtext DEFAULT NULL')
    MySQL.update.await("UPDATE lc_houses SET owned = 1 WHERE owner IS NOT NULL AND owner != '' AND owned = 0")
end

local function normalizeHouse(row, identifier)
    local coords = json.decode(row.coords or '{}') or {}
    local enter = coords.enter or {}
    local interior = json.decode(row.interior or '{}') or {}
    local isOwned = tonumber(row.owned) == 1 or (row.owner ~= nil and row.owner ~= '')
    local settings = decodeSettings(row.settings)
    local doorRows = getHouseDoors(row.name)
    if #doorRows > 0 then settings.doors = doorRows end

    return {
        id = row.id,
        name = row.name,
        label = row.label,
        price = tonumber(row.price) or 0,
        tier = tonumber(coords.tier) or Config.Defaults.tier or 1,
        propertyType = row.property_type or interior.type or 'shell',
        shell = row.shell or interior.shell or Config.Defaults.shell or '',
        ipl = row.ipl or interior.ipl or '',
        mlo = row.mlo or interior.mlo or '',
        owner = row.owner or '',
        owned = isOwned,
        isOwner = ownedBy(row, identifier),
        settings = settings,
        coords = coords,
        garage = coords.garage or {},
        polyzone = json.decode(row.polyzone or '[]') or {},
        interior = interior,
        image = row.image or '',
        created_by = row.created_by or '',
        x = tonumber(enter.x) or 0.0,
        y = tonumber(enter.y) or 0.0,
        z = tonumber(enter.z) or 0.0,
        h = tonumber(enter.h) or 0.0
    }
end

local function getHouses(identifier)
    local rows = MySQL.query.await([[
        SELECT id, name, label, price, property_type, shell, ipl, mlo, image, owner, owned,
               coords, polyzone, interior, settings, created_by, created_at, updated_at
        FROM lc_houses
        ORDER BY label ASC
    ]], {})

    local houses = {}
    for _, row in ipairs(rows or {}) do houses[#houses + 1] = normalizeHouse(row, identifier) end
    return houses
end

local function hasHouseKey(_, citizenid, house)
    house = tostring(house or '')
    if house == '' or not citizenid or citizenid == '' then return false end

    local owner = MySQL.scalar.await('SELECT owner FROM lc_houses WHERE name = ? LIMIT 1', { house })
    return owner ~= nil and owner ~= '' and owner == citizenid
end

exports('hasKey', hasHouseKey)

local function syncQbHouse(name)
    if not Config.MirrorQbHouses then return end
    debugLog(('Syncing %s to qb-houses mirror.'):format(name))
    local row = MySQL.single.await('SELECT name, label, price, owned, coords FROM lc_houses WHERE name = ?', { name })
    if not row then return end

    local coords = json.decode(row.coords or '{}') or {}
    local garage = coords.garage or { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
    local qbCoords = { enter = coords.enter, cam = coords.cam, yaw = coords.yaw }
    local tier = tonumber(coords.tier) or Config.Defaults.tier or 1
    local exists = MySQL.scalar.await('SELECT name FROM houselocations WHERE name = ?', { row.name })

    if exists then
        MySQL.update.await('UPDATE houselocations SET label = ?, coords = ?, owned = ?, price = ?, tier = ?, garage = ? WHERE name = ?', {
            row.label, json.encode(qbCoords), tonumber(row.owned) or 0, tonumber(row.price) or 0, tier, json.encode(garage), row.name
        })
    else
        MySQL.insert.await('INSERT INTO houselocations (name, label, coords, owned, price, tier, garage) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            row.name, row.label, json.encode(qbCoords), tonumber(row.owned) or 0, tonumber(row.price) or 0, tier, json.encode(garage)
        })
    end
end

local function refreshClients()
    local players = getCore().Functions.GetPlayers()
    for _, src in ipairs(players or {}) do
        local Player = getCore().Functions.GetPlayer(src)
        local identifier = Player and playerIdentifier(Player) or nil
        TriggerClientEvent('lc-housing:client:setHouses', src, getHouses(identifier))
    end
end

CreateThread(function()
    ensureSchema()
    migrateDoorSettingsToTable()
    debugLog(('Started. Garage support: %s'):format(Config.Garage and Config.Garage.enabled and 'enabled' or 'disabled'))
end)

local function luaQuote(value)
    return string.format('%q', tostring(value or ''))
end

local function exportDoorScan(data)
    local cleanDoors = makeDoorLocks({ doorLocks = data and data.doors or {} })
    local fileName = tostring(Config.DebugDoorScanFile or 'door_scan_debug.lua'):gsub('[^%w%._%-]', '_')
    if not fileName:match('%.lua$') then fileName = fileName .. '.lua' end

    local lines = {
        '',
        ('-- Scan captured %s UTC'):format(os.date('!%Y-%m-%d %H:%M:%S')),
        'DoorScanDebug = DoorScanDebug or {}',
        'DoorScanDebug[#DoorScanDebug + 1] = {',
        ('    propertyName = %s,'):format(luaQuote(cleanName(data and data.name or 'unnamed_property'))),
        ('    propertyLabel = %s,'):format(luaQuote(data and data.label or 'Unnamed Property')),
        ('    propertyType = %s,'):format(luaQuote(data and data.propertyType or 'mlo')),
        ('    capturedAt = %s,'):format(luaQuote(os.date('!%Y-%m-%dT%H:%M:%SZ'))),
        '    doors = {'
    }

    for index, door in ipairs(cleanDoors) do
        local coords = door.coords or {}
        local model = tonumber(door.model) or 0
        lines[#lines + 1] = '        {'
        lines[#lines + 1] = ('            index = %d, name = %s, doorType = %s, panel = %s,'):format(index, luaQuote(door.name), luaQuote(door.doorType), luaQuote(door.panel))
        lines[#lines + 1] = ('            model = %d, modelHex = %s,'):format(model, luaQuote(('0x%08X'):format(model % 4294967296)))
        lines[#lines + 1] = ('            coords = { x = %.3f, y = %.3f, z = %.3f }, heading = %.3f, radius = %.2f'):format(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0, tonumber(door.heading) or 0.0, tonumber(door.radius) or 1.5)
        lines[#lines + 1] = '        },'
    end

    lines[#lines + 1] = '    }'
    lines[#lines + 1] = '}'

    local resource = GetCurrentResourceName()
    local existing = LoadResourceFile(resource, fileName)
    if not existing or existing == '' then
        existing = '-- Generated by lc-housing Scan All Doors. This file is diagnostic and is not loaded by fxmanifest.lua.\n'
    end
    SaveResourceFile(resource, fileName, existing .. table.concat(lines, '\n') .. '\n', -1)
    return fileName, #cleanDoors
end

createCallback('lc-housing:server:exportDoorScan', function(source, cb, data)
    if not Config.Debug then cb({ ok = false, message = 'Debug mode is disabled.' }) return end
    local allowed = hasPermission(source, 'view')
    if not allowed then cb({ ok = false, message = 'Real estate job required.' }) return end

    local ok, fileName, count = pcall(exportDoorScan, data or {})
    if not ok then
        debugLog(('Door scan export failed: %s'):format(tostring(fileName)))
        cb({ ok = false, message = 'Door scan completed, but the debug file could not be written.' })
        return
    end

    debugLog(('Exported %s scanned door(s) to %s.'):format(count, fileName))
    cb({ ok = true, file = fileName, count = count })
end)

createCallback('lc-housing:server:getPanelData', function(source, cb)
    local allowed = hasPermission(source, 'view')
    if not allowed then cb({ ok = false, message = 'Real estate job required.' }) return end
    local Player = getCore().Functions.GetPlayer(source)
    cb({ ok = true, houses = getHouses(Player and playerIdentifier(Player) or nil), permissions = Config.Permissions })
end)

createCallback('lc-housing:server:nextHouseName', function(source, cb, data)
    local allowed = hasPermission(source, 'view')
    if not allowed then cb({ ok = false, message = 'Real estate job required.' }) return end

    data = data or {}
    cb({ ok = true, name = nextHouseName(data.base or data.label or 'house') })
end)

createCallback('lc-housing:server:getHouses', function(source, cb)
    local Player = getCore().Functions.GetPlayer(source)
    cb({ ok = true, houses = getHouses(Player and playerIdentifier(Player) or nil) })
end)

createCallback('lc-housing:server:createHouse', function(source, cb, data)
    local allowed, Player = hasPermission(source, 'create')
    if not allowed then cb({ ok = false, message = 'You do not have permission to create houses.' }) return end

    data = data or {}
    local label = tostring(data.label or ''):sub(1, 96)
    local coords = makeCoords(data)
    if label == '' or not coords then cb({ ok = false, message = 'Address label and entrance coordinates are required.' }) return end

    local baseName = cleanName(data.nameBase or label)
    local name = nextHouseName(baseName)
    while MySQL.scalar.await('SELECT name FROM lc_houses WHERE name = ?', { name }) do
        name = nextHouseName(baseName)
    end

    local tier = math.max(1, math.floor(tonumber(data.tier) or Config.Defaults.tier))
    coords.garage = makeGarage(data)
    coords.tier = tier

    local propertyType, interior = makeInterior(data)
    print(('[lc-housing] creating house name=%s type=%s shell=%s ipl=%s'):format(name, propertyType, interior.shell, interior.ipl))
    local polyzone = makePolyzone(data)
    local cleanDoors = makeDoorLocks(data)

    MySQL.insert.await([[
        INSERT INTO lc_houses (name, label, price, property_type, shell, ipl, mlo, image, owner, owned, coords, polyzone, interior, settings, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        name,
        label,
        math.max(0, math.floor(tonumber(data.price) or Config.Defaults.price)),
        propertyType,
        interior.shell,
        interior.ipl,
        interior.mlo,
        tostring(data.image or Config.Defaults.image or ''),
        nil,
        0,
        json.encode(coords),
        json.encode(polyzone),
        json.encode(interior),
        json.encode(defaultSettings(cleanDoors)),
        playerIdentifier(Player)
    })

    replaceHouseDoors(name, cleanDoors)
    syncQbHouse(name)
    refreshClients()
    notify(source, ('Created %s.'):format(label), 'success')
    cb({ ok = true, house = name, houses = getHouses(playerIdentifier(Player)) })
end)

createCallback('lc-housing:server:updateHouse', function(source, cb, data)
    local allowed = hasPermission(source, 'edit')
    if not allowed then cb({ ok = false, message = 'You do not have permission to edit houses.' }) return end

    data = data or {}
    local name = tostring(data.name or '')
    local existing = MySQL.single.await('SELECT name, property_type, shell, ipl, mlo, interior FROM lc_houses WHERE name = ?', { name })
    if not existing then
        cb({ ok = false, message = 'House not found.' }) return
    end

    local label = tostring(data.label or ''):sub(1, 96)
    local coords = makeCoords(data)
    if label == '' or not coords then cb({ ok = false, message = 'Address label and entrance coordinates are required.' }) return end

    local tier = math.max(1, math.floor(tonumber(data.tier) or Config.Defaults.tier))
    coords.garage = makeGarage(data)
    coords.tier = tier

    local existingInterior = json.decode(existing.interior or '{}') or {}
    local propertyType = tostring(existing.property_type or existingInterior.type or 'shell'):lower()
    if propertyType ~= 'shell' and propertyType ~= 'mlo' and propertyType ~= 'ipl' then propertyType = 'shell' end
    local preservedInterior = {
        type = propertyType,
        shell = tostring(existing.shell or existingInterior.shell or ''):sub(1, 64),
        ipl = tostring(existing.ipl or existingInterior.ipl or ''):sub(1, 96),
        mlo = tostring(existing.mlo or existingInterior.mlo or ''):sub(1, 96)
    }
    local interior = preservedInterior
    local polyzone = makePolyzone(data)

    MySQL.update.await([[
        UPDATE lc_houses
        SET label = ?, price = ?, property_type = ?, shell = ?, ipl = ?, mlo = ?, image = ?, coords = ?, polyzone = ?, interior = ?
        WHERE name = ?
    ]], {
        label,
        math.max(0, math.floor(tonumber(data.price) or Config.Defaults.price)),
        propertyType,
        interior.shell,
        interior.ipl,
        interior.mlo,
        tostring(data.image or ''),
        json.encode(coords),
        json.encode(polyzone),
        json.encode(interior),
        name
    })

    if data.doorLocks then
        local currentSettings = MySQL.scalar.await('SELECT settings FROM lc_houses WHERE name = ?', { name })
        local settings = decodeSettings(currentSettings)
        settings.doors = replaceHouseDoors(name, data.doorLocks or {})
        if #settings.doors > 0 then settings.locked = true else settings.locked = false end
        MySQL.update.await('UPDATE lc_houses SET settings = ? WHERE name = ?', { json.encode(settings), name })
    end

    syncQbHouse(name)
    refreshClients()
    notify(source, ('Updated %s.'):format(label), 'success')
    local Player = getCore().Functions.GetPlayer(source)
    cb({ ok = true, houses = getHouses(Player and playerIdentifier(Player) or nil) })
end)

createCallback('lc-housing:server:deleteHouse', function(source, cb, name)
    local allowed = hasPermission(source, 'delete')
    if not allowed then cb({ ok = false, message = 'You do not have permission to delete houses.' }) return end

    name = tostring(name or '')
    local existing = MySQL.single.await('SELECT name, label, owned FROM lc_houses WHERE name = ?', { name })
    if not existing then cb({ ok = false, message = 'House not found.' }) return end

    MySQL.update.await('DELETE FROM lc_house_doors WHERE house_name = ?', { name })
    MySQL.update.await('DELETE FROM lc_house_furniture WHERE house_name = ?', { name })
    MySQL.update.await('DELETE FROM lc_houses WHERE name = ?', { name })
    if Config.MirrorQbHouses then MySQL.update.await('DELETE FROM houselocations WHERE name = ?', { name }) end

    refreshClients()
    notify(source, ('Deleted %s.'):format(existing.label or name), 'success')
    local Player = getCore().Functions.GetPlayer(source)
    cb({ ok = true, houses = getHouses(Player and playerIdentifier(Player) or nil) })
end)


local function getOwnedHouse(source, name)
    local Player = getCore().Functions.GetPlayer(source)
    if not Player then return nil, nil, 'Player not found.' end
    local identifier = playerIdentifier(Player)
    local row = MySQL.single.await('SELECT * FROM lc_houses WHERE name = ?', { tostring(name or '') })
    if not row then return nil, Player, 'House not found.' end
    if row.owner ~= identifier then return nil, Player, 'You do not own this house.' end
    return row, Player, nil
end


RegisterNetEvent("lc-housing:server:openStash", function(name)
    local src = source
    local row, Player, errorMessage = getOwnedHouse(src, name)
    if not row then
        notify(src, errorMessage or "You do not own this house.", "error")
        return
    end

    local stashId = ("lc_house_%s"):format(row.name)
    local label = ("%s Storage"):format(row.label or row.name)
    local slots = tonumber(Config.Inventory and Config.Inventory.stashSlots) or 80
    local weight = tonumber(Config.Inventory and Config.Inventory.stashWeight) or 4000000

    for _, resource in ipairs((Config.Inventory and Config.Inventory.resources) or {}) do
        if GetResourceState(resource) == "started" then
            if resource == "qb-inventory" then
                exports["qb-inventory"]:OpenInventory(src, stashId, {
                    maxweight = weight,
                    slots = slots,
                    label = label
                })
                return
            elseif resource == "ox_inventory" then
                pcall(function()
                    exports.ox_inventory:RegisterStash(stashId, label, slots, weight, false)
                end)
                exports.ox_inventory:forceOpenInventory(src, "stash", stashId)
                return
            end
        end
    end

    notify(src, "No supported inventory resource is started.", "error")
end)

createCallback('lc-housing:server:enterHouse', function(source, cb, name)
    local row, Player, errorMessage = getOwnedHouse(source, name)
    if not row then cb({ ok = false, message = errorMessage }) return end
    local interior = json.decode(row.interior or '{}') or {}
    local propertyType = row.property_type or interior.type or 'shell'
    print(('[lc-housing] entering house name=%s type=%s shell=%s ipl=%s'):format(row.name, propertyType, tostring(row.shell or interior.shell or ''), tostring(row.ipl or interior.ipl or '')))
    if propertyType ~= 'shell' then cb({ ok = false, message = 'MLO/IPL properties are entered in-world.' }) return end

    local settings = decodeSettings(row.settings)

    cb({
        ok = true,
        house = normalizeHouse(row, playerIdentifier(Player)),
        exit = settings.exit or Config.Interior.defaultExit
    })
end)

createCallback('lc-housing:server:previewHouse', function(source, cb, name)
    local Player = getCore().Functions.GetPlayer(source)
    if not Player then cb({ ok = false, message = 'Player not found.' }) return end

    local row = MySQL.single.await('SELECT * FROM lc_houses WHERE name = ?', { tostring(name or '') })
    if not row then cb({ ok = false, message = 'House not found.' }) return end
    if tonumber(row.owned) == 1 or tostring(row.owner or '') ~= '' then cb({ ok = false, message = 'This house is already owned.' }) return end

    local interior = json.decode(row.interior or '{}') or {}
    local propertyType = row.property_type or interior.type or 'shell'
    if propertyType ~= 'shell' then cb({ ok = false, message = 'Only shell houses can be previewed.' }) return end

    local settings = decodeSettings(row.settings)
    cb({
        ok = true,
        house = normalizeHouse(row, playerIdentifier(Player)),
        exit = settings.exit or Config.Interior.defaultExit
    })
end)

local function logoutSource(src)
    local core = getCore()
    if core and core.Player and core.Player.Logout then
        core.Player.Logout(src)
        SetTimeout(250, function()
            TriggerClientEvent('qb-multicharacter:client:chooseChar', src)
        end)
    else
        notify(src, 'Logout is not supported by this framework.', 'error')
    end
end

RegisterNetEvent('lc-housing:server:logout', function()
    logoutSource(source)
end)

RegisterNetEvent('qb-houses:server:LogoutLocation', function()
    logoutSource(source)
end)

createCallback('lc-housing:server:updateHousePoint', function(source, cb, data)
    data = data or {}
    local row, Player, errorMessage = getOwnedHouse(source, data.name)
    if not row then cb({ ok = false, message = errorMessage }) return end

    local pointType = tostring(data.pointType or '')
    if pointType ~= 'stash' and pointType ~= 'wardrobe' and pointType ~= 'exit' and pointType ~= 'logout' then
        cb({ ok = false, message = 'Invalid house point.' })
        return
    end

    local coords = makeCoords(data)
    if not coords then cb({ ok = false, message = 'Position is missing.' }) return end

    local settings = decodeSettings(row.settings)
    settings[pointType] = coords.enter
    MySQL.update.await('UPDATE lc_houses SET settings = ? WHERE name = ?', { json.encode(settings), row.name })
    refreshClients()
    cb({ ok = true, houses = getHouses(playerIdentifier(Player)), settings = settings })
end)

createCallback('lc-housing:server:updateDoors', function(source, cb, data)
    data = data or {}
    local row, Player, errorMessage = getOwnedHouse(source, data.name)
    if not row then cb({ ok = false, message = errorMessage }) return end

    local settings = decodeSettings(row.settings)
    settings.doors = replaceHouseDoors(row.name, data.doors or {})
    if #settings.doors > 0 and data.defaultLocked ~= false then settings.locked = true elseif #settings.doors < 1 then settings.locked = false end

    MySQL.update.await('UPDATE lc_houses SET settings = ? WHERE name = ?', { json.encode(settings), row.name })
    refreshClients()
    cb({ ok = true, houses = getHouses(playerIdentifier(Player)), settings = settings })
end)

createCallback('lc-housing:server:toggleLock', function(source, cb, data)
    local name = type(data) == 'table' and data.name or data
    local row, Player, errorMessage = getOwnedHouse(source, name)
    if not row then cb({ ok = false, message = errorMessage }) return end

    local settings = decodeSettings(row.settings)
    local doors = getHouseDoors(row.name)
    local doorIndex = type(data) == 'table' and tonumber(data.doorIndex) or nil
    local locked

    if doorIndex and doors[doorIndex] then
        settings.doorStates = type(settings.doorStates) == 'table' and settings.doorStates or {}
        local key = doorGroupKey(doors[doorIndex], doorIndex)
        locked = not doorLockedState(settings, doors[doorIndex], doorIndex)
        settings.doorStates[key] = locked
    else
        settings.locked = not settings.locked
        locked = settings.locked
        settings.doorStates = type(settings.doorStates) == 'table' and settings.doorStates or {}
        for index, door in ipairs(doors) do
            settings.doorStates[doorGroupKey(door, index)] = locked
        end
    end

    MySQL.update.await('UPDATE lc_houses SET settings = ? WHERE name = ?', { json.encode(settings), row.name })
    refreshClients()
    cb({ ok = true, houses = getHouses(playerIdentifier(Player)), locked = locked })
end)

createCallback('lc-housing:server:sellHouse', function(source, cb, name)
    if not Config.SellBack.enabled then cb({ ok = false, message = 'Selling houses is disabled.' }) return end
    local row, Player, errorMessage = getOwnedHouse(source, name)
    if not row then cb({ ok = false, message = errorMessage }) return end

    local payout = math.floor((tonumber(row.price) or 0) * ((tonumber(Config.SellBack.percent) or 70) / 100))
    MySQL.update.await('UPDATE lc_houses SET owner = NULL, owned = 0, settings = ? WHERE name = ?', { json.encode(defaultSettings()), row.name })
    addMoney(Player, Config.SellBack.account or 'bank', payout, 'house-sale')
    syncQbHouse(row.name)
    refreshClients()
    notify(source, ('Sold %s for $%s.'):format(row.label or row.name, payout), 'success')
    cb({ ok = true, houses = getHouses(playerIdentifier(Player)), payout = payout })
end)


createCallback('lc-housing:server:buyHouse', function(source, cb, name)
    if not Config.Purchase.enabled then
        cb({ ok = false, message = 'Property purchases are disabled.' })
        return
    end

    local Player = getCore().Functions.GetPlayer(source)
    if not Player then cb({ ok = false, message = 'Player not found.' }) return end

    name = tostring(name or '')
    local house = MySQL.single.await('SELECT name, label, price, owned, owner FROM lc_houses WHERE name = ?', { name })
    if not house then cb({ ok = false, message = 'House not found.' }) return end
    if tonumber(house.owned) == 1 or house.owner then cb({ ok = false, message = 'This house is already owned.' }) return end

    local price = math.max(0, math.floor(tonumber(house.price) or 0))
    local citizenid = playerIdentifier(Player)
    local changed = MySQL.update.await([[UPDATE lc_houses SET owner = ?, owned = 1 WHERE name = ? AND owned = 0 AND (owner IS NULL OR owner = '')]], { citizenid, name })
    if tonumber(changed) == 0 then
        cb({ ok = false, message = 'This house is already owned.' })
        return
    end

    local paidFrom = Config.Purchase.account or 'bank'
    if not removeMoney(Player, paidFrom, price, 'house-purchase') then
        MySQL.update.await('UPDATE lc_houses SET owner = NULL, owned = 0 WHERE name = ? AND owner = ?', { name, citizenid })
        cb({ ok = false, message = ('You need $%s to buy this property.'):format(price) })
        return
    end

    syncQbHouse(name)
    refreshClients()
    notify(source, ('Purchased %s.'):format(house.label or name), 'success')
    cb({ ok = true, houses = getHouses(citizenid), owner = citizenid })
end)
