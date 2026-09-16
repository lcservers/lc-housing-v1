local Core
local panelOpen = false

RegisterNetEvent('lc-housing:client:furnitureClosed', function()
    panelOpen = false
end)
local houses = {}
local drawingPoly = false
local polyPoints = {}
local nearestHouse = nil
local insideHouse = nil
local outsideCoords = nil
local targetZones = {}
local syncedGarageHouses = {}
local houseBlips = {}
local pendingPointPlacement = nil
local pendingEntryPlacement = false
local shellPreviewObject = nil
local shellPreviewCamera = nil
local shellPreviewToken = 0
local activeShellObject = nil
local activeShellExit = nil
local activeIplName = nil

-- Keep Escape available to creator tools without allowing FiveM's pause menu
-- to consume the same keypress.
local function placementCancelPressed()
    DisableControlAction(0, 199, true)
    DisableControlAction(0, 200, true)
    DisableControlAction(0, 202, true)
    DisableControlAction(0, 322, true)
    DisableControlAction(2, 199, true)
    DisableControlAction(2, 200, true)
    DisableControlAction(2, 202, true)
    DisableControlAction(2, 322, true)
    return IsDisabledControlJustPressed(0, 200)
        or IsDisabledControlJustReleased(0, 200)
        or IsDisabledControlJustPressed(0, 202)
        or IsDisabledControlJustReleased(0, 202)
        or IsDisabledControlJustPressed(0, 322)
        or IsDisabledControlJustReleased(0, 322)
        or IsDisabledControlJustPressed(2, 200)
        or IsDisabledControlJustReleased(2, 200)
        or IsDisabledControlJustPressed(2, 202)
        or IsDisabledControlJustReleased(2, 202)
        or IsDisabledControlJustPressed(2, 322)
        or IsDisabledControlJustReleased(2, 322)
end


local function clearShellPreview()
    if shellPreviewCamera and DoesCamExist(shellPreviewCamera) then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(shellPreviewCamera, false)
    end
    shellPreviewCamera = nil
    if shellPreviewObject and DoesEntityExist(shellPreviewObject) then DeleteEntity(shellPreviewObject) end
    shellPreviewObject = nil
    ClearFocus()
end

local function configuredShell(model)
    if type(model) ~= 'string' then return nil end
    for _, entry in ipairs(Config.Shells or {}) do
        local configuredModel = type(entry) == 'table' and entry.model or entry
        if configuredModel == model then return entry end
    end
    return nil
end

local function shellModelName(value)
    if type(value) == 'string' then return value end
    if type(value) == 'table' and type(value.model) == 'string' then return value.model end
    return ''
end

local function clearActiveShell()
    if activeShellObject and DoesEntityExist(activeShellObject) then DeleteEntity(activeShellObject) end
    activeShellObject = nil
    activeShellExit = nil
end

local function isConfiguredShellModel(model)
    for _, entry in ipairs(Config.Shells or {}) do
        local configuredModel = type(entry) == 'table' and entry.model or entry
        if type(configuredModel) == 'string' and joaat(configuredModel) == model then return true end
    end
    return false
end

local function clearConfiguredShellObjects()
    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) and isConfiguredShellModel(GetEntityModel(object)) then
            if not NetworkHasControlOfEntity(object) then
                NetworkRequestControlOfEntity(object)
                local timeout = GetGameTimer() + 500
                while not NetworkHasControlOfEntity(object) and GetGameTimer() < timeout do Wait(0) end
            end
            SetEntityAsMissionEntity(object, true, true)
            DeleteObject(object)
            if DoesEntityExist(object) then DeleteEntity(object) end
        end
    end
end

local function shellInstanceOrigin(house)
    local base = Config.Interior.defaultExit or {}
    local spacing = Config.Interior.instanceSpacing or {}
    if spacing.enabled == false then return vector3(base.x or 0.0, base.y or 0.0, base.z or 0.0) end
    local id = math.max(1, tonumber(house and house.id) or 1) - 1
    local columns = math.max(1, tonumber(spacing.columns) or 10)
    local distance = tonumber(spacing.distance) or 100.0
    return vector3(
        (tonumber(base.x) or 0.0) + (id % columns) * distance,
        (tonumber(base.y) or 0.0) + math.floor(id / columns) * distance,
        tonumber(base.z) or 0.0
    )
end

local function shellInteriorExit(definition, origin)
    local base = origin or Config.Interior.defaultExit or {}
    local target = type(definition) == 'table' and definition.entry or nil
    if type(target) ~= 'table' then target = { 0.0, 0.0, 0.0 } end
    return vector4(
        (tonumber(base.x) or 0.0) + (tonumber(target.x or target[1]) or 0.0),
        (tonumber(base.y) or 0.0) + (tonumber(target.y or target[2]) or 0.0),
        (tonumber(base.z) or 0.0) + (tonumber(target.z or target[3]) or 0.0),
        tonumber(target.h or target[4]) or tonumber(base.h) or 0.0
    )
end

local function spawnActiveShell(house)
    clearActiveShell()
    local modelName = shellModelName(house and house.shell or '')
    local definition = configuredShell(modelName)
    if not definition then return false, 'This house has no configured shell model.' end

    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return false, 'The configured shell model is invalid.' end
    RequestModel(model)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(model) then return false, 'The configured shell model could not be loaded.' end

    local origin = shellInstanceOrigin(house)
    clearConfiguredShellObjects()
    activeShellObject = CreateObjectNoOffset(model, origin.x, origin.y, origin.z, false, false, false)
    FreezeEntityPosition(activeShellObject, true)
    SetEntityAsMissionEntity(activeShellObject, true, true)
    SetEntityCollision(activeShellObject, true, true)
    SetEntityLoadCollisionFlag(activeShellObject, true, true)
    RequestCollisionAtCoord(origin.x, origin.y, origin.z)
    local collisionTimeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(activeShellObject) and GetGameTimer() < collisionTimeout do
        RequestCollisionAtCoord(origin.x, origin.y, origin.z)
        Wait(0)
    end
    Wait(250)
    activeShellExit = shellInteriorExit(definition, origin)
    SetModelAsNoLongerNeeded(model)
    print(('[lc-housing] spawned shell model=%s hash=%s'):format(modelName, tostring(model)))
    return true
end

local function clearHouseIpl()
    if activeIplName and activeIplName ~= '' then RemoveIpl(activeIplName) end
    activeIplName = nil
end

local function activateHouseIpl(house)
    local ipl = house and tostring(house.ipl or '') or ''
    if ipl == '' then return false end
    if activeIplName == ipl then return true end
    clearHouseIpl()
    RequestIpl(ipl)
    activeIplName = ipl
    return true
end

local function frameworkResource()
    if Config.Framework == 'qb' then return Config.FrameworkResources.qb end
    if Config.Framework == 'qbox' then return Config.FrameworkResources.qbox end
    if GetResourceState(Config.FrameworkResources.qbox) == 'started' then return Config.FrameworkResources.qbox end
    return Config.FrameworkResources.qb
end

local function getCore()
    if Core then return Core end
    Core = exports[frameworkResource()]:GetCoreObject()
    return Core
end

local function notify(message, msgType)
    local ok = pcall(function() getCore().Functions.Notify(message, msgType or 'primary') end)
    if not ok then BeginTextCommandThefeedPost('STRING') AddTextComponentSubstringPlayerName(message) EndTextCommandThefeedPostTicker(false, false) end
end

local function triggerCallback(name, cb, ...)
    getCore().Functions.TriggerCallback(name, cb, ...)
end

local function locationInfo(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ''
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z)) or ''

    if zone == 'NULL' then zone = '' end

    local label = ''
    if street ~= '' and crossing ~= '' then label = ('%s & %s'):format(street, crossing)
    elseif street ~= '' then label = street
    elseif zone ~= '' then label = zone
    else label = ('Property %.0f %.0f'):format(coords.x, coords.y) end

    return { label = label, nameBase = zone ~= '' and zone or label }
end

local function currentCoords()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local location = locationInfo(coords)
    return {
        x = tonumber(('%0.3f'):format(coords.x)),
        y = tonumber(('%0.3f'):format(coords.y)),
        z = tonumber(('%0.3f'):format(coords.z)),
        h = tonumber(('%0.3f'):format(GetEntityHeading(ped))),
        label = location.label,
        nameBase = location.nameBase
    }
end


local function findHouseByName(name)
    if not name then return nil end
    for _, house in ipairs(houses or {}) do
        if house.name == name then return house end
    end
    return nil
end

local function housePropertyType(house)
    local propertyType = house and (house.propertyType or house.type or (house.interior and house.interior.type)) or 'shell'
    propertyType = tostring(propertyType or 'shell'):lower()
    if propertyType == 'mlo' or propertyType == 'ipl' then return propertyType end
    return 'shell'
end

local function drawText(text)
    SetTextFont(4)
    SetTextScale(0.35, 0.35)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.86)
end


local function drawWorldText(coords, text, r, g, b, a)
    if not coords then return end
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextFont(4)
    SetTextScale(0.28, 0.28)
    SetTextColour(r or 255, g or 255, b or 255, a or 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function validPoint(point)
    return point and tonumber(point.x) and tonumber(point.y) and tonumber(point.z)
end

local function clearHouseBlips()
    for _, blip in ipairs(houseBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    houseBlips = {}
end

local function createHouseBlip(house)
    local blipConfig = Config.Blips or {}
    if not blipConfig.enabled or not house or not house.coords or not house.coords.enter then return end

    local enter = house.coords.enter
    if not validPoint(enter) then return end

    local isPurchased = house.owned or house.isOwner
    if isPurchased and not blipConfig.showPurchased then return end
    if not isPurchased and not blipConfig.showForSale then return end

    local style = isPurchased and (blipConfig.purchased or {}) or (blipConfig.forSale or {})
    local blip = AddBlipForCoord(enter.x, enter.y, enter.z)
    SetBlipSprite(blip, style.sprite or blipConfig.sprite or 40)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, style.scale or blipConfig.scale or 0.62)
    SetBlipColour(blip, style.color or 0)
    SetBlipAsShortRange(blip, style.shortRange ~= false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(style.label or (isPurchased and "Purchased House" or "House For Sale"))
    EndTextCommandSetBlipName(blip)
    houseBlips[#houseBlips + 1] = blip
end

local function refreshHouseBlips()
    clearHouseBlips()
    for _, house in ipairs(houses or {}) do
        createHouseBlip(house)
    end
end

local objectDimensions
local classifyDoorModel
local isGarageDoorLock

local doorLockIds = {}

local function doorLockSettings()
    return Config.DoorLocks or {}
end

local function doorModelHash(model)
    if type(model) == "number" then return model end
    if type(model) == "string" and model ~= "" then return GetHashKey(model) end
    return nil
end

local function configuredHouseDoors(house)
    local settings = doorLockSettings()
    local configured = settings.houses or {}
    local configuredDoors = house and (configured[house.name] or configured[house.label]) or nil
    local savedDoors = house and house.settings and house.settings.doors or nil
    if type(savedDoors) == "table" and #savedDoors > 0 then return savedDoors end
    return configuredDoors
end

local function doorPosition(door, house)
    local coords = door.coords or door.position or door
    if validPoint(coords) then return coords end
    return house and house.coords and house.coords.enter or nil
end

local function horizontalDistance(a, b)
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    return math.sqrt((dx * dx) + (dy * dy))
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

local function doorLockedState(house, door, index)
    local settings = house and house.settings or {}
    local states = type(settings.doorStates) == 'table' and settings.doorStates or {}
    local key = doorGroupKey(door, index)
    if states[key] ~= nil then return states[key] == true end
    if type(door) == 'table' and door.locked ~= nil then return door.locked == true end
    return settings.locked == true
end

local function applyDoorLock(house, door, index)
    local settings = doorLockSettings()
    if not settings.enabled then return end

    local coords = doorPosition(door, house)
    local model = doorModelHash(door.model or door.hash)
    if not validPoint(coords) or not model then return end

    local locked = doorLockedState(house, door, index)
    local isGarage = isGarageDoorLock and isGarageDoorLock(door)
    local garageSettings = settings.garage or {}

    -- Garage doors need a physical hold so MLO auto-open triggers cannot bypass the lock.
    -- Use physicalLock = false only for MLOs whose animated panels cannot be safely frozen.
    if isGarage and garageSettings.physicalLock == false then return end

    local doorId = GetHashKey(("lc_housing_%s_%s"):format(house.name or "house", index))
    if not doorLockIds[doorId] then
        AddDoorToSystem(doorId, model, coords.x, coords.y, coords.z, false, false, false)
        doorLockIds[doorId] = true
    end

    DoorSystemSetDoorState(doorId, locked and 1 or 0, false, false)
    if isGarage then
        local openRatio = locked and 0.0 or (tonumber(garageSettings.openRatio) or 1.0)
        local openRate = locked and 0.0 or (tonumber(garageSettings.openRate) or 1.0)
        DoorSystemSetAutomaticRate(doorId, openRate, false, false)
        DoorSystemSetOpenRatio(doorId, openRatio, false, false)
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local applyDistance = tonumber(settings.applyDistance) or 80.0
    if #(pos - vector3(coords.x, coords.y, coords.z)) > applyDistance then return end

    local radius = tonumber(door.radius) or tonumber(settings.defaultRadius) or 1.5
    if isGarage then
        local garageRadius = tonumber(garageSettings.lockRadius) or radius
        radius = math.max(radius, garageRadius)
    end
    local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, model, false, false, false)
    if entity and entity ~= 0 then
        if locked and isGarage then
            FreezeEntityPosition(entity, false)
            if door.heading then SetEntityHeading(entity, tonumber(door.heading) or 0.0) end
            if garageSettings.snapToClosed ~= false then
                SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
            end
            FreezeEntityPosition(entity, true)
        else
            FreezeEntityPosition(entity, locked)
            if locked and door.heading then SetEntityHeading(entity, tonumber(door.heading) or 0.0) end
        end
    end
end

local function refreshDoorLocks()
    local settings = doorLockSettings()
    if not settings.enabled then return end

    for _, house in ipairs(houses or {}) do
        local doors = configuredHouseDoors(house)
        if type(doors) == "table" then
            for index, door in ipairs(doors) do
                if type(door) == "table" then applyDoorLock(house, door, index) end
            end
        end
    end
end

local doorLockTogglePending = false

local function doorPromptSettings()
    return doorLockSettings().prompt or {}
end

function isGarageDoorLock(door)
    if type(door) ~= 'table' then return false end
    if tostring(door.doorType or ''):lower() == 'garage' then return true end

    local settings = doorLockSettings()
    local garageSettings = settings.garage or {}
    local model = doorModelHash(door.model or door.hash)
    if garageSettings.detectLegacyByModel ~= false and model and classifyDoorModel and classifyDoorModel(model, settings) == 'garage' then
        return true
    end

    if garageSettings.detectLegacyByRadius == false then return false end

    local garageRadius = tonumber(garageSettings.lockRadius)
    local radius = tonumber(door.radius)
    return garageRadius and radius and radius >= garageRadius
end

local function garageDoorCenterCoords(door, coords)
    if not validPoint(coords) then return nil end

    door = door or {}
    local model = doorModelHash(door.model or door.hash)
    if not model then return coords end

    local settings = doorLockSettings()
    local garageRadius = tonumber(settings.garage and settings.garage.lockRadius) or 1.5
    local radius = math.max(tonumber(door.radius) or 0.0, garageRadius, tonumber(settings.defaultRadius) or 1.5)
    local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, model, false, false, false)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return coords end

    local dims = objectDimensions(model)
    if not dims then return GetEntityCoords(entity) end

    local centerOffset = vector3(
        ((dims.min.x or 0.0) + (dims.max.x or 0.0)) / 2.0,
        ((dims.min.y or 0.0) + (dims.max.y or 0.0)) / 2.0,
        ((dims.min.z or 0.0) + (dims.max.z or 0.0)) / 2.0
    )
    return GetOffsetFromEntityInWorldCoords(entity, centerOffset.x, centerOffset.y, centerOffset.z)
end

local function nearestOwnedDoor(pos)
    local settings = doorLockSettings()
    local prompt = doorPromptSettings()
    if not settings.enabled or prompt.enabled == false then return nil end

    local drawDistance = tonumber(prompt.drawDistance) or 8.0
    local useDistance = tonumber(prompt.distance) or 1.8
    local garageSettings = settings.garage or {}
    local garageDrawDistance = tonumber(garageSettings.drawDistance) or drawDistance
    local garageUseDistance = tonumber(garageSettings.distance) or useDistance
    local nearest

    for _, house in ipairs(houses or {}) do
        if house.isOwner then
            local doors = configuredHouseDoors(house)
            if type(doors) == "table" then
                for index, door in ipairs(doors) do
                    local coords = doorPosition(door, house)
                    if validPoint(coords) then
                        local dist = #(pos - vector3(coords.x, coords.y, coords.z))
                        local isGarageDoor = isGarageDoorLock(door)
                        local centerCoords = isGarageDoor and garageDoorCenterCoords(door, coords) or nil
                        local savedDist = isGarageDoor and horizontalDistance({ x = pos.x, y = pos.y }, coords) or dist
                        local centerDist = isGarageDoor and centerCoords and horizontalDistance({ x = pos.x, y = pos.y }, centerCoords) or savedDist
                        local checkDist = isGarageDoor and math.min(savedDist, centerDist) or dist
                        local doorDrawDistance = isGarageDoor and garageDrawDistance or drawDistance
                        local doorUseDistance = isGarageDoor and garageUseDistance or useDistance
                        if checkDist <= doorDrawDistance and (not nearest or checkDist < nearest.dist) then
                            nearest = {
                                house = house,
                                door = door,
                                index = index,
                                coords = coords,
                                iconCoords = centerCoords,
                                dist = checkDist,
                                canUse = checkDist <= doorUseDistance,
                                locked = doorLockedState(house, door, index),
                                groupKey = doorGroupKey(door, index)
                            }
                        end
                    end
                end
            end
        end
    end

    return nearest
end

local function doorIconCoords(hit)
    local coords = hit.coords
    if not isGarageDoorLock(hit.door) then return coords, false end
    return hit.iconCoords or garageDoorCenterCoords(hit.door, coords) or coords, true
end

local function drawDoorLockIcon(hit)
    if not hit or not hit.coords then return end

    local prompt = doorPromptSettings()
    local coords, isGarage = doorIconCoords(hit)
    local garageSettings = doorLockSettings().garage or {}
    local locked = hit.locked == true
    local r, g, b = locked and 255 or 88, locked and 98 or 214, locked and 112 or 141

    if not isGarage then
        DrawMarker(2, coords.x, coords.y, coords.z + 0.35, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, r, g, b, 170, false, false, 2, true, nil, nil, false)
        drawWorldText({ x = coords.x, y = coords.y, z = coords.z + 0.72 }, locked and "Press [E] to unlock" or "Press [E] to lock", r, g, b, 235)
    elseif garageSettings.iconOnly == false then
        drawWorldText({ x = coords.x, y = coords.y, z = coords.z - 0.32 }, locked and "Press [E] to open" or "Press [E] to close", r, g, b, 235)
    end

    local dict = prompt.textureDict or "commonmenu"
    local texture = locked and (prompt.lockedTexture or "shop_lock") or (prompt.unlockedTexture or "shop_tick_icon")
    RequestStreamedTextureDict(dict, false)
    if HasStreamedTextureDictLoaded(dict) then
        SetDrawOrigin(coords.x, coords.y, coords.z + (isGarage and 0.0 or 0.95), 0)
        DrawSprite(dict, texture, 0.0, 0.0, isGarage and 0.036 or 0.028, isGarage and 0.064 or 0.05, 0.0, r, g, b, 235)
        ClearDrawOrigin()
    end
end

local function playDoorLockSound(locked)
    local prompt = doorPromptSettings()
    PlaySoundFrontend(-1, locked and (prompt.lockSound or "PIN_BUTTON") or (prompt.unlockSound or "PIN_BUTTON"), prompt.soundSet or "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
end

local function toggleDoorLockFromWorld(hit)
    if doorLockTogglePending or not hit or not hit.house then return end

    doorLockTogglePending = true

    triggerCallback("lc-housing:server:toggleLock", function(result)
        doorLockTogglePending = false
        if result and result.houses then
            houses = result.houses
            refreshHouseBlips()
            refreshDoorLocks()
        end

        if result and result.ok then
            local isGarage = isGarageDoorLock(hit.door)
            playDoorLockSound(result.locked)
            if isGarage then
                notify(result.locked and "Garage door closed." or "Garage door opened.", "success")
            else
                notify(result.locked and "Door locked." or "Door unlocked.", "success")
            end
        else
            notify(result and result.message or "Could not toggle door lock.", "error")
        end
    end, { name = hit.house.name, doorIndex = hit.index })
end

local function doorModelHashes()
    local hashes = {}
    for _, model in ipairs((doorLockSettings().doorModels or {})) do
        local hash = doorModelHash(model)
        if hash then hashes[hash] = true end
    end
    return hashes
end

local function pointInPoly2d(point, poly)
    if type(poly) ~= "table" or #poly < 3 then return false end
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local pi, pj = poly[i], poly[j]
        if pi and pj and ((pi.y > point.y) ~= (pj.y > point.y)) and (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 0.000001) + pi.x) then inside = not inside end
        j = i
    end
    return inside
end

local function keyboardInput(title, defaultText, maxLength)
    AddTextEntry("LC_HOUSING_INPUT", title)
    DisplayOnscreenKeyboard(1, "LC_HOUSING_INPUT", "", defaultText or "", "", "", "", maxLength or 64)
    while UpdateOnscreenKeyboard() == 0 do Wait(0) end
    if UpdateOnscreenKeyboard() == 1 then return GetOnscreenKeyboardResult() end
    return nil
end

function objectDimensions(model)
    local minDim, maxDim = GetModelDimensions(model)
    if not minDim or not maxDim then return nil end

    local sizeX = math.abs((maxDim.x or 0.0) - (minDim.x or 0.0))
    local sizeY = math.abs((maxDim.y or 0.0) - (minDim.y or 0.0))
    local sizeZ = math.abs((maxDim.z or 0.0) - (minDim.z or 0.0))

    return {
        min = minDim,
        max = maxDim,
        sizeX = sizeX,
        sizeY = sizeY,
        sizeZ = sizeZ,
        thinSide = math.min(sizeX, sizeY),
        wideSide = math.max(sizeX, sizeY)
    }
end

local function objectSelectionDistance(entity, model, pos)
    local coords = GetEntityCoords(entity)
    local dims = objectDimensions(model)
    if not dims then return #(pos - coords), coords end

    local centerOffset = vector3(
        ((dims.min.x or 0.0) + (dims.max.x or 0.0)) / 2.0,
        ((dims.min.y or 0.0) + (dims.max.y or 0.0)) / 2.0,
        ((dims.min.z or 0.0) + (dims.max.z or 0.0)) / 2.0
    )
    local center = GetOffsetFromEntityInWorldCoords(entity, centerOffset.x, centerOffset.y, centerOffset.z)
    local radius = math.sqrt((dims.sizeX * dims.sizeX) + (dims.sizeY * dims.sizeY) + (dims.sizeZ * dims.sizeZ)) / 2.0

    return math.max(0.0, #(pos - center) - radius), center
end

local function classifyDoorDimensions(dims, settings)
    if not dims then return nil end

    local minHeight = tonumber(settings.minDoorHeight) or 1.4
    local normalDoor = dims.sizeZ >= minHeight
        and dims.thinSide <= (tonumber(settings.maxDoorDepth) or 0.55)
        and dims.wideSide <= (tonumber(settings.maxDoorWidth) or 4.5)

    if normalDoor then return 'single' end

    local garageDoor = dims.sizeZ >= minHeight
        and dims.sizeZ <= (tonumber(settings.maxGarageDoorHeight) or 7.0)
        and dims.thinSide <= (tonumber(settings.maxGarageDoorDepth) or 1.25)
        and dims.wideSide <= (tonumber(settings.maxGarageDoorWidth) or 12.0)

    if garageDoor then return 'garage' end
    return nil
end

function classifyDoorModel(model, settings)
    return classifyDoorDimensions(objectDimensions(model), settings or doorLockSettings())
end

local function classifyDoorObject(entity, model, settings)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    return classifyDoorModel(model, settings)
end

local function isLikelyDoorObject(entity, model, settings)
    return classifyDoorObject(entity, model, settings) ~= nil
end

local function scanDoorObjects(points)
    local settings = doorLockSettings()
    local hashes = doorModelHashes()
    local objects = GetGamePool("CObject") or {}
    local doors, seen = {}, {}
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local radius = tonumber(settings.scanRadius) or 120.0
    local hasZone = type(points) == "table" and #points >= 3
    local allowFallback = settings.scanFallback ~= false
    local maxDoors = tonumber(settings.maxScanDoors) or 20

    for _, entity in ipairs(objects) do
        local model = GetEntityModel(entity)
        local coords = GetEntityCoords(entity)
        local inZone = pointInPoly2d({ x = coords.x, y = coords.y }, points)
        local inScope = (hasZone and inZone) or (not hasZone and #(pos - coords) <= radius)
        local knownDoor = hashes[model]
        local fallbackKind = allowFallback and inScope and classifyDoorObject(entity, model, settings) or nil
        local fallbackDoor = fallbackKind ~= nil

        if inScope and (knownDoor or fallbackDoor) then
            local key = ("%s:%0.2f:%0.2f:%0.2f"):format(model, coords.x, coords.y, coords.z)
            if not seen[key] then
                seen[key] = true
                doors[#doors + 1] = {
                    model = model,
                    doorType = fallbackKind == 'garage' and 'garage' or 'single',
                    coords = { x = tonumber(("%0.3f"):format(coords.x)), y = tonumber(("%0.3f"):format(coords.y)), z = tonumber(("%0.3f"):format(coords.z)) },
                    heading = tonumber(("%0.3f"):format(GetEntityHeading(entity))),
                    radius = fallbackKind == 'garage' and (tonumber(settings.garage and settings.garage.lockRadius) or tonumber(settings.defaultRadius) or 1.5) or (tonumber(settings.defaultRadius) or 1.5)
                }
                if #doors >= maxDoors then break end
            end
        end
    end

    table.sort(doors, function(a, b) return (a.coords.x .. a.coords.y) < (b.coords.x .. b.coords.y) end)
    return doors
end

local function nameScannedDoors(doors)
    local ped = PlayerPedId()
    local original = currentCoords()
    for index, door in ipairs(doors) do
        local c = door.coords
        teleportTo({ x = c.x, y = c.y, z = c.z, h = door.heading or 0.0 })
        local name = keyboardInput(("Name door lock %s/%s"):format(index, #doors), door.name or ("Door " .. index), 64)
        door.name = name and name ~= "" and name or ("Door " .. index)
    end
    teleportTo(original)
    return doors
end

local function rotationToDirection(rotation)
    local adjusted = vector3(
        (math.pi / 180.0) * rotation.x,
        (math.pi / 180.0) * rotation.y,
        (math.pi / 180.0) * rotation.z
    )
    return vector3(
        -math.sin(adjusted.z) * math.abs(math.cos(adjusted.x)),
        math.cos(adjusted.z) * math.abs(math.cos(adjusted.x)),
        math.sin(adjusted.x)
    )
end

local function raycastFacingObject(distance)
    local camCoords = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local destination = camCoords + (direction * (distance or 5.0))
    local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, destination.x, destination.y, destination.z, 17, PlayerPedId(), 0)
    local _, hit, endCoords, _, entity = GetShapeTestResult(rayHandle)
    if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 3 then
        local coords = GetEntityCoords(entity)
        local model = GetEntityModel(entity)
        local pedPos = GetEntityCoords(PlayerPedId())
        local edgeDist, center = objectSelectionDistance(entity, model, pedPos)
        local hitDist = endCoords and #(pedPos - endCoords) or nil
        return { entity = entity, model = model, coords = endCoords or center or coords, objectCoords = coords, dist = #(pedPos - coords), originDist = #(pedPos - coords), edgeDist = edgeDist, hitDist = hitDist, hitCoords = endCoords }
    end
    return nil
end

local function nearestDoorObject()
    local settings = doorLockSettings()
    local hashes = doorModelHashes()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local addRadius = tonumber(settings.addRadius) or 3.0
    local manualRadius = tonumber(settings.manualAddRadius) or 2.0
    local allowFallback = settings.scanFallback ~= false
    local rayDistance = math.max(addRadius, manualRadius, 6.0)

    local aimed = raycastFacingObject(rayDistance)
    if aimed then
        aimed.kind = allowFallback and classifyDoorObject(aimed.entity, aimed.model, settings) or (hashes[aimed.model] and 'single' or nil)
        local aimedDist = math.min(aimed.dist or 9999.0, aimed.edgeDist or 9999.0, aimed.hitDist or 9999.0)
        if aimedDist <= math.max(addRadius, manualRadius) then
            return aimed
        end
    end

    local closest, closestDist
    local nearestAny, nearestAnyDist
    for _, entity in ipairs(GetGamePool("CObject") or {}) do
        if DoesEntityExist(entity) then
            local model = GetEntityModel(entity)
            local coords = GetEntityCoords(entity)
            local originDist = #(pos - coords)
            local edgeDist, center = objectSelectionDistance(entity, model, pos)
            local dist = math.min(originDist, edgeDist)
            local knownDoor = hashes[model]
            local fallbackKind = allowFallback and classifyDoorObject(entity, model, settings) or nil
            local fallbackDoor = fallbackKind ~= nil
            local selectCoords = edgeDist < originDist and center or coords

            if dist <= addRadius and (knownDoor or fallbackDoor) and (not closestDist or dist < closestDist) then
                closest = { entity = entity, model = model, coords = selectCoords, objectCoords = coords, dist = dist, originDist = originDist, edgeDist = edgeDist, kind = fallbackKind or (knownDoor and 'single' or nil) }
                closestDist = dist
            end

            if allowFallback then
                local looseDist = fallbackDoor and dist or originDist
                local looseCoords = fallbackDoor and selectCoords or coords
                if looseDist <= manualRadius and (not nearestAnyDist or looseDist < nearestAnyDist) then
                    nearestAny = { entity = entity, model = model, coords = looseCoords, objectCoords = coords, dist = looseDist, originDist = originDist, edgeDist = edgeDist, kind = fallbackKind }
                    nearestAnyDist = looseDist
                end
            end
        end
    end

    return closest or nearestAny
end

local activeDoorOutlines = {}

local function clearDoorSelectionOutlines()
    if not SetEntityDrawOutline then activeDoorOutlines = {}; return end

    for _, entity in ipairs(activeDoorOutlines) do
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            SetEntityDrawOutline(entity, false)
        end
    end
    activeDoorOutlines = {}
end

local function showDoorSelectionOutlines(selection)
    clearDoorSelectionOutlines()
    if not SetEntityDrawOutline then return end

    local color = doorLockSettings().outlineColor or {}
    if SetEntityDrawOutlineColor then SetEntityDrawOutlineColor(color.r or 255, color.g or 213, color.b or 64, color.a or 255) end
    if SetEntityDrawOutlineShader then SetEntityDrawOutlineShader(1) end

    for _, found in ipairs(selection or {}) do
        local entity = found and found.entity
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            SetEntityDrawOutline(entity, true)
            activeDoorOutlines[#activeDoorOutlines + 1] = entity
        end
    end
end

local function doorPayloadFromObject(found, name, doorType, panel)
    local defaultRadius = tonumber(doorLockSettings().defaultRadius) or 1.5
    local isGarageDoor = tostring(doorType or found.kind or ''):lower() == 'garage'
    local c = isGarageDoor and (found.objectCoords or found.coords) or found.coords
    local garageSettings = doorLockSettings().garage or {}
    local lookupRadius = isGarageDoor and (tonumber(garageSettings.lockRadius) or defaultRadius) or defaultRadius
    if isGarageDoor and found.objectCoords and found.coords then
        lookupRadius = math.max(lookupRadius, #(found.objectCoords - found.coords) + 0.75)
    elseif isGarageDoor and found.originDist then
        lookupRadius = math.max(lookupRadius, tonumber(found.originDist) + 0.75)
    end

    return {
        name = name,
        doorType = doorType or 'single',
        panel = panel or '',
        model = found.model,
        coords = {
            x = tonumber(('%0.3f'):format(c.x)),
            y = tonumber(('%0.3f'):format(c.y)),
            z = tonumber(('%0.3f'):format(c.z))
        },
        heading = tonumber(('%0.3f'):format(GetEntityHeading(found.entity))),
        radius = tonumber(('%0.2f'):format(math.min(lookupRadius, 12.0)))
    }
end

local function savedDoorNear(doors, coords)
    for _, door in ipairs(doors or {}) do
        local c = door.coords or door
        if validPoint(c) and #(vector3(c.x, c.y, c.z) - vector3(coords.x, coords.y, coords.z)) < 0.35 then
            return true
        end
    end

    return false
end

local function findPairedDoorObject(primary)
    local settings = doorLockSettings()
    if not primary or settings.autoPairDoubleDoors == false then return nil end

    local hashes = doorModelHashes()
    local pairRadius = tonumber(settings.doubleDoorRadius) or 2.5
    local allowFallback = settings.scanFallback ~= false
    local closest, closestDist

    for _, entity in ipairs(GetGamePool("CObject") or {}) do
        if entity ~= primary.entity and DoesEntityExist(entity) then
            local coords = GetEntityCoords(entity)
            local dist = #(primary.coords - coords)
            if dist <= pairRadius then
                local model = GetEntityModel(entity)
                local knownDoor = hashes[model]
                local sameModel = model == primary.model
                local fallbackKind = allowFallback and classifyDoorObject(entity, model, settings) or nil
                local fallbackDoor = fallbackKind ~= nil and fallbackKind ~= 'garage'
                if (sameModel or knownDoor or fallbackDoor) and dist > 0.2 and (not closestDist or dist < closestDist) then
                    closest = { entity = entity, model = model, coords = coords, dist = dist }
                    closestDist = dist
                end
            end
        end
    end

    return closest
end

local function debugDrawConfig()
    return Config.DebugDraw or {}
end

local function drawDebugPolygon(points, label)
    if type(points) ~= 'table' or #points < 3 then return false end

    local debugDraw = debugDrawConfig()
    local zOffset = tonumber(debugDraw.polygonZOffset) or 0.08
    local groundOffset = tonumber(debugDraw.polygonGroundOffset) or 0.05
    local polygonHeight = math.max(1.0, tonumber(debugDraw.polygonHeight) or 18.0)
    local fillAlpha = tonumber(debugDraw.polygonFillAlpha) or 32
    local wallAlpha = tonumber(debugDraw.polygonWallAlpha) or math.max(12, math.floor(fillAlpha * 0.75))
    local lineAlpha = tonumber(debugDraw.polygonLineAlpha) or 230
    local first = points[1]
    if not validPoint(first) then return false end

    local bottomZ = first.z + groundOffset
    for _, point in ipairs(points) do
        if validPoint(point) then bottomZ = math.min(bottomZ, point.z + groundOffset) end
    end
    local topZ = bottomZ + polygonHeight

    for index, point in ipairs(points) do
        local nextPoint = points[index + 1] or first
        if validPoint(point) and validPoint(nextPoint) then
            DrawLine(point.x, point.y, bottomZ + zOffset, nextPoint.x, nextPoint.y, bottomZ + zOffset, 255, 45, 55, lineAlpha)
            DrawLine(point.x, point.y, topZ, nextPoint.x, nextPoint.y, topZ, 255, 45, 55, lineAlpha)
            DrawLine(point.x, point.y, bottomZ, point.x, point.y, topZ, 255, 45, 55, lineAlpha)

            -- Draw each wall in both winding directions so it is visible from inside and outside.
            DrawPoly(point.x, point.y, bottomZ, nextPoint.x, nextPoint.y, bottomZ, nextPoint.x, nextPoint.y, topZ, 255, 45, 55, wallAlpha)
            DrawPoly(nextPoint.x, nextPoint.y, topZ, point.x, point.y, topZ, point.x, point.y, bottomZ, 255, 45, 55, wallAlpha)
            DrawPoly(nextPoint.x, nextPoint.y, bottomZ, point.x, point.y, bottomZ, point.x, point.y, topZ, 255, 45, 55, wallAlpha)
            DrawPoly(point.x, point.y, topZ, nextPoint.x, nextPoint.y, topZ, nextPoint.x, nextPoint.y, bottomZ, 255, 45, 55, wallAlpha)
        end
    end

    for index = 2, #points - 1 do
        local second = points[index]
        local third = points[index + 1]
        if validPoint(second) and validPoint(third) then
            DrawPoly(first.x, first.y, topZ, second.x, second.y, topZ, third.x, third.y, topZ, 255, 45, 55, fillAlpha)
            DrawPoly(third.x, third.y, topZ, second.x, second.y, topZ, first.x, first.y, topZ, 255, 45, 55, fillAlpha)
        end
    end

    drawWorldText({ x = first.x, y = first.y, z = topZ + 0.5 }, label or 'Property Zone', 255, 80, 90, 235)
    return true
end

local function drawDebugGarage(house, pos)
    local garage = house and house.garage
    if not validPoint(garage) then return end

    local debugDraw = debugDrawConfig()
    local drawDistance = tonumber(debugDraw.garageDrawDistance) or tonumber(debugDraw.drawDistance) or 160.0
    local garagePos = vector3(garage.x, garage.y, garage.z)
    if #(pos - garagePos) > drawDistance then return end

    DrawMarker(1, garage.x, garage.y, garage.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.15, 1.15, 0.45, 255, 45, 55, 135, false, false, 2, false, nil, nil, false)
    DrawMarker(36, garage.x, garage.y, garage.z + 0.28, 0.0, 0.0, 0.0, 0.0, 0.0, garage.w or garage.h or 0.0, 0.85, 0.85, 0.85, 255, 45, 55, 180, false, false, 2, true, nil, nil, false)
    drawWorldText({ x = garage.x, y = garage.y, z = garage.z + 1.15 }, ('%s Garage'):format(house.label or house.name or 'House'), 255, 80, 90, 235)
end

local function drawDebugHouse(house, pos)
    if not Config.Debug or (Config.DebugDraw and Config.DebugDraw.enabled == false) then return end
    if not house then return end

    local debugDraw = debugDrawConfig()
    local drawDistance = tonumber(debugDraw.drawDistance) or 160.0
    local enter = house.coords and house.coords.enter
    local closeEnough = false

    if validPoint(enter) and #(pos - vector3(enter.x, enter.y, enter.z)) <= drawDistance then
        closeEnough = true
    end

    if not closeEnough and type(house.polyzone) == 'table' then
        for _, point in ipairs(house.polyzone) do
            if validPoint(point) and #(pos - vector3(point.x, point.y, point.z)) <= drawDistance then
                closeEnough = true
                break
            end
        end
    end

    local garage = house.garage
    if not closeEnough and validPoint(garage) and #(pos - vector3(garage.x, garage.y, garage.z)) <= drawDistance then
        closeEnough = true
    end

    if not closeEnough then return end

    local drewPolygon = drawDebugPolygon(house.polyzone, ('%s Property'):format(house.label or house.name or 'House'))
    if not drewPolygon and validPoint(enter) then
        DrawMarker(1, enter.x, enter.y, enter.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.05, 1.05, 0.35, 255, 45, 55, 120, false, false, 2, false, nil, nil, false)
        drawWorldText({ x = enter.x, y = enter.y, z = enter.z + 1.0 }, ('%s Entrance'):format(house.label or house.name or 'House'), 255, 80, 90, 235)
    end

    drawDebugGarage(house, pos)
end

local function teleportTo(coords)
    if not coords then return end
    local ped = PlayerPedId()
    DoScreenFadeOut(350)
    Wait(400)
    SetEntityCoords(ped, tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0, false, false, false, false)
    SetEntityHeading(ped, tonumber(coords.h or coords.w) or 0.0)
    Wait(250)
    DoScreenFadeIn(350)
end

local function distanceTo(point)
    if not point then return 9999.0 end
    local pos = GetEntityCoords(PlayerPedId())
    return #(pos - vector3(point.x, point.y, point.z))
end

local function openStash(house)
    if not house or not house.name then return end
    TriggerServerEvent("lc-housing:server:openStash", house.name)
end

local function openWardrobe()
    for _, resource in ipairs((Config.Clothing and Config.Clothing.resources) or {}) do
        if GetResourceState(resource) == 'started' then
            if resource == 'qs-appearance' then
                -- Quasar Appearance keeps the qb-clothing compatibility event.
                TriggerEvent('qb-clothing:client:openMenu')
                return
            elseif resource == 'illenium-appearance' then
                TriggerEvent('illenium-appearance:client:openOutfitMenu')
                return
            elseif resource == 'qb-clothing' then
                TriggerEvent('qb-clothing:client:openOutfitMenu')
                return
            elseif resource == 'fivem-appearance' then
                exports['fivem-appearance']:openWardrobe()
                return
            end
        end
    end

    notify('No supported clothing resource is started.', 'error')
end


local function nearestOwnedWorldPoint(pos)
    local best
    local drawDistance = tonumber(Config.Interior.drawDistance) or 8.0
    local promptDistance = tonumber(Config.Interior.promptDistance) or 1.5

    for _, house in ipairs(houses or {}) do
        if house.isOwner and housePropertyType(house) ~= 'shell' then
            local settings = house.settings or {}
            local points = {
                { pointType = 'stash', point = settings.stash, marker = { 88, 214, 141 }, text = 'Press [E] to open stash' },
                { pointType = 'wardrobe', point = settings.wardrobe, marker = { 247, 198, 106 }, text = 'Press [E] to change outfit' },
                { pointType = 'logout', point = settings.logout, marker = { 255, 109, 109 }, text = 'Press [E] to logout' }
            }

            for _, item in ipairs(points) do
                if validPoint(item.point) then
                    local dist = #(pos - vector3(item.point.x, item.point.y, item.point.z))
                    if dist < drawDistance and (not best or dist < best.dist) then
                        best = { house = house, pointType = item.pointType, point = item.point, marker = item.marker, text = item.text, dist = dist, canUse = dist < promptDistance }
                    end
                end
            end
        end
    end

    return best
end

local function logoutFromHouse()
    notify('Logging out...', 'primary')
    TriggerServerEvent('lc-housing:server:logout')
end

local function useWorldPointPrompt(prompt)
    if not prompt or not prompt.house then return end
    if prompt.pointType == 'stash' then
        openStash(prompt.house)
    elseif prompt.pointType == 'wardrobe' then
        openWardrobe()
    elseif prompt.pointType == 'logout' then
        logoutFromHouse()
    end
end

local function interactionMode()
    return (Config.Interaction and Config.Interaction.mode) or 'prompt'
end

local function interactionTargetConfig()
    return (Config.Interaction and Config.Interaction.target) or {}
end

local function interactionMarkerConfig()
    return (Config.Interaction and Config.Interaction.marker) or {}
end

local function targetResource()
    local mode = interactionMode()
    if mode ~= 'target' and mode ~= 'auto' and mode ~= 'hybrid' then return nil end

    local target = interactionTargetConfig()
    if target.resource and target.resource ~= 'auto' and GetResourceState(target.resource) == 'started' then
        return target.resource
    end

    for _, resource in ipairs((Config.Interaction and Config.Interaction.targetResources) or {}) do
        if GetResourceState(resource) == 'started' then return resource end
    end

    return nil
end

local function targetsEnabled()
    local mode = interactionMode()
    if mode == 'target' then return targetResource() ~= nil end
    if (mode == 'auto' or mode == 'hybrid') and interactionTargetConfig().enabled then return targetResource() ~= nil end
    return false
end

local function markersEnabled()
    if interactionMode() == 'target' then return false end
    return interactionMarkerConfig().enabled ~= false
end

local function markerPosition(point)
    local offset = tonumber(interactionMarkerConfig().zOffset) or 0.0
    return point.x, point.y, point.z + offset
end

local function targetLabel(house)
    if house.isOwner then return ('Manage %s'):format(house.label or house.name) end
    if house.owned then return ('%s (Owned)'):format(house.label or house.name) end
    return ('View %s | $%s'):format(house.label or house.name, house.price or 0)
end

local function canUseHouseInteraction(house)
    return house and (house.isOwner or not house.owned)
end

local function garageEnabled()
    return Config.Garage and Config.Garage.enabled and GetResourceState(Config.Garage.resource or 'qb-garages') == 'started'
end

local function syncHouseGarage(house)
    if not garageEnabled() or not house then return end

    local garage = house.garage
    local hasGarage = validPoint(garage)
    if not hasGarage then
        if syncedGarageHouses[house.name] then
            TriggerEvent('qb-garages:client:setHouseGarage', house.name, false)
            syncedGarageHouses[house.name] = nil
        end
        return
    end

    syncedGarageHouses[house.name] = true
    if hasGarage then
        TriggerEvent('qb-garages:client:addHouseGarage', house.name, {
            label = house.label or house.name,
            takeVehicle = {
                x = garage.x,
                y = garage.y,
                z = garage.z,
                w = garage.w or garage.h or 0.0
            }
        })
    end

    TriggerEvent('qb-garages:client:setHouseGarage', house.name, hasGarage and house.isOwner or false)
end

local function syncHouseGarages()
    if not garageEnabled() then return end

    local seen = {}
    for _, house in ipairs(houses) do
        seen[house.name] = true
        syncHouseGarage(house)
    end

    for houseName in pairs(syncedGarageHouses) do
        if not seen[houseName] then
            TriggerEvent('qb-garages:client:setHouseGarage', houseName, false)
            syncedGarageHouses[houseName] = nil
        end
    end
end

local rebuildTargetZones

local function openPanel()
    triggerCallback('lc-housing:server:getPanelData', function(result)
        if not result or not result.ok then
            notify(result and result.message or 'Unable to open housing panel.', 'error')
            return
        end

        houses = result.houses or {}
        syncHouseGarages()
        refreshHouseBlips()
        refreshDoorLocks()
        rebuildTargetZones()
        local current = currentCoords()
        triggerCallback('lc-housing:server:nextHouseName', function(nameResult)
            if nameResult and nameResult.ok then current.name = nameResult.name end
            panelOpen = true
            SetNuiFocus(true, true)
            SendNUIMessage({
                action = 'open',
                houses = houses,
                permissions = result.permissions,
                current = current,
                config = {
                    version = Config.Version,
                    debug = Config.Debug == true,
                    bounds = Config.MapBounds,
                    defaults = Config.Defaults,
                    shells = Config.Shells,
                    garage = Config.Garage or { enabled = false }
                }
            })
        end, { base = current.nameBase or current.label })
    end)
end



local function openListing(house)
    if not house then return end
    print(('[lc-housing] owner listing requested house=%s owner=%s owned=%s'):format(tostring(house.name), tostring(house.owner), tostring(house.owned)))
    panelOpen = true
    SetNuiFocus(true, true)

    local propertyType = housePropertyType(house)
    local pos = GetEntityCoords(PlayerPedId())
    local isInsideProperty = insideHouse and insideHouse.name == house.name or false
    if propertyType ~= 'shell' and type(house.polyzone) == 'table' and #house.polyzone >= 3 then
        isInsideProperty = pointInPoly2d({ x = pos.x, y = pos.y }, house.polyzone)
    end

    SendNUIMessage({
        action = 'openListing',
        house = house,
        ownerMenuContext = {
            isInsideProperty = isInsideProperty,
            propertyType = propertyType
        },
        config = {
            purchase = Config.Purchase
        }
    })
    print(('[lc-housing] owner listing NUI sent house=%s inside=%s'):format(tostring(house.name), tostring(isInsideProperty)))
end


local function enterOwnedShellHouse(house)
    if not house or not house.isOwner then return end
    if housePropertyType(house) ~= 'shell' then
        notify('MLO/IPL properties are entered through their physical doors.', 'primary')
        return
    end

    triggerCallback('lc-housing:server:enterHouse', function(result)
        if not result or not result.ok then
            notify(result and result.message or 'Could not enter property.', 'error')
            return
        end

        local spawned, spawnError = spawnActiveShell(result.house)
        if not spawned then
            notify(spawnError or 'Could not load the selected shell.', 'error')
            return
        end
        insideHouse = result.house
        outsideCoords = result.house and result.house.coords and result.house.coords.enter or nil
        TriggerEvent('lc-housing:furniture:enterShell', result.house.name)
        panelOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
        teleportTo(activeShellExit or result.exit)
        rebuildTargetZones()
    end, house.name)
end

local function clearTargetZones()
    for name, zone in pairs(targetZones) do
        if zone.resource == 'qb-target' then
            pcall(function() exports['qb-target']:RemoveZone(name) end)
        elseif zone.resource == 'ox_target' then
            pcall(function() exports.ox_target:removeZone(zone.id or name) end)
        end
    end
    targetZones = {}
end

local function addQbTargetZone(resource, house, enter)
    local target = interactionTargetConfig()
    local zoneName = ('lc_housing_%s'):format(house.name)
    local options = {}

    if house.isOwner and housePropertyType(house) == 'shell' then
        options[#options + 1] = {
            icon = 'fas fa-door-open',
            label = 'Enter Property',
            action = function() if not panelOpen and not insideHouse then enterOwnedShellHouse(house) end end,
            canInteract = function() return not panelOpen and not insideHouse end
        }
    elseif not house.owned then
        options[#options + 1] = {
            icon = target.icon or 'fas fa-house',
            label = targetLabel(house),
            action = function() if not panelOpen then openListing(house) end end,
            canInteract = function() return not panelOpen and not insideHouse end
        }
    end

    if house.isOwner and target.showManage ~= false then
        options[#options + 1] = {
            icon = 'fas fa-house-user',
            label = 'Manage Property',
            action = function() if not panelOpen then openListing(house) end end,
            canInteract = function() return not panelOpen and not insideHouse end
        }
    end

    if #options < 1 then return end
    exports[resource]:AddBoxZone(zoneName, vector3(enter.x, enter.y, enter.z), target.length or 1.2, target.width or 1.2, {
        name = zoneName,
        heading = enter.h or enter.w or 0.0,
        minZ = enter.z - ((target.height or 2.0) / 2.0),
        maxZ = enter.z + ((target.height or 2.0) / 2.0)
    }, {
        options = options,
        distance = Config.Interaction.promptDistance or 2.0,
        drawSprite = target.drawSprite == true
    })
    targetZones[zoneName] = { resource = resource }
end

local function addOxTargetZone(resource, house, enter)
    local target = interactionTargetConfig()
    local zoneName = ('lc_housing_%s'):format(house.name)
    local options = {}

    if house.isOwner and housePropertyType(house) == 'shell' then
        options[#options + 1] = {
            name = zoneName .. '_enter', icon = 'fas fa-door-open', label = 'Enter Property',
            distance = Config.Interaction.promptDistance or 2.0,
            onSelect = function() if not panelOpen and not insideHouse then enterOwnedShellHouse(house) end end,
            canInteract = function() return not panelOpen and not insideHouse end
        }
    elseif not house.owned then
        options[#options + 1] = {
            name = zoneName .. '_view', icon = target.icon or 'fas fa-house', label = targetLabel(house),
            distance = Config.Interaction.promptDistance or 2.0,
            onSelect = function() if not panelOpen then openListing(house) end end,
            canInteract = function() return not panelOpen and not insideHouse end
        }
    end

    if house.isOwner and target.showManage ~= false then
        options[#options + 1] = {
            name = zoneName .. '_manage', icon = 'fas fa-house-user', label = 'Manage Property',
            distance = Config.Interaction.promptDistance or 2.0,
            onSelect = function() if not panelOpen then openListing(house) end end,
            canInteract = function() return not panelOpen and not insideHouse end
        }
    end

    if #options < 1 then return end
    local zoneId = exports[resource]:addBoxZone({
        name = zoneName,
        coords = vector3(enter.x, enter.y, enter.z),
        size = vector3(target.length or 1.2, target.width or 1.2, target.height or 2.0),
        rotation = enter.h or enter.w or 0.0,
        options = options
    })
    targetZones[zoneName] = { resource = resource, id = zoneId }
end

local function useInteriorTarget(house, pointType)
    if pointType == 'exit' then
        clearActiveShell()
        teleportTo(outsideCoords or (house.coords and house.coords.enter))
        TriggerEvent('lc-housing:furniture:leaveShell', house.name)
        insideHouse = nil
        outsideCoords = nil
        rebuildTargetZones()
        return
    end
    useWorldPointPrompt({ house = house, pointType = pointType })
end

local function addInteriorTargetZones(resource, house)
    local settings = house.settings or {}
    local propertyType = housePropertyType(house)
    local size = (Config.Interior and Config.Interior.targetSize) or {}
    local points = {
        { type = 'stash', point = settings.stash, label = 'Open Stash', icon = 'fas fa-box-open' },
        { type = 'wardrobe', point = settings.wardrobe, label = 'Open Wardrobe', icon = 'fas fa-shirt' },
        { type = 'logout', point = settings.logout, label = 'Logout Character', icon = 'fas fa-right-from-bracket' }
    }
    if propertyType == 'shell' and insideHouse and insideHouse.name == house.name then
        table.insert(points, 1, { type = 'exit', point = settings.exit or Config.Interior.defaultExit, label = 'Exit Property', icon = 'fas fa-door-open' })
    end

    for _, item in ipairs(points) do
        if validPoint(item.point) then
            local pointType = item.type
            local zoneName = ('lc_housing_%s_%s'):format(house.name, pointType)
            if resource == 'qb-target' then
                exports[resource]:AddBoxZone(zoneName, vector3(item.point.x, item.point.y, item.point.z), size.x or 1.0, size.y or 1.0, {
                    name = zoneName,
                    heading = item.point.h or item.point.w or 0.0,
                    minZ = item.point.z - ((size.z or 1.5) / 2.0),
                    maxZ = item.point.z + ((size.z or 1.5) / 2.0)
                }, {
                    options = {{ icon = item.icon, label = item.label, action = function() useInteriorTarget(house, pointType) end }},
                    distance = Config.Interior.promptDistance or 1.5,
                    drawSprite = (interactionTargetConfig().drawSprite == true)
                })
                targetZones[zoneName] = { resource = resource }
            elseif resource == 'ox_target' then
                local zoneId = exports[resource]:addBoxZone({
                    name = zoneName,
                    coords = vector3(item.point.x, item.point.y, item.point.z),
                    size = vector3(size.x or 1.0, size.y or 1.0, size.z or 1.5),
                    rotation = item.point.h or item.point.w or 0.0,
                    options = {{ name = zoneName, icon = item.icon, label = item.label, distance = Config.Interior.promptDistance or 1.5, onSelect = function() useInteriorTarget(house, pointType) end }}
                })
                targetZones[zoneName] = { resource = resource, id = zoneId }
            end
        end
    end
end

rebuildTargetZones = function()
    clearTargetZones()
    if not targetsEnabled() then return end

    local resource = targetResource()
    if not resource then return end

    for _, house in ipairs(houses) do
        local enter = house.coords and house.coords.enter
        if enter and canUseHouseInteraction(house) then
            if resource == 'qb-target' then
                addQbTargetZone(resource, house, enter)
            elseif resource == 'ox_target' then
                addOxTargetZone(resource, house, enter)
            end
        end

        if house.isOwner then
            local propertyType = housePropertyType(house)
            if propertyType ~= 'shell' or (insideHouse and insideHouse.name == house.name) then
                addInteriorTargetZones(resource, house)
            end
        end
    end
end



local function distanceToHouse(pos, house)
    local closest = 9999.0
    local enter = house and house.coords and house.coords.enter
    if validPoint(enter) then
        closest = math.min(closest, #(pos - vector3(enter.x, enter.y, enter.z)))
    end

    local garage = house and house.garage
    if validPoint(garage) then
        closest = math.min(closest, #(pos - vector3(garage.x, garage.y, garage.z)))
    end

    local points = house and house.polyzone
    if type(points) == 'table' then
        for _, point in ipairs(points) do
            if validPoint(point) then
                closest = math.min(closest, #(pos - vector3(point.x, point.y, point.z)))
            end
        end
    end

    return closest
end

local function findClosestOwnedHouse(pos)
    local closestHouse = nil
    local closestDistance = 9999.0

    for _, house in ipairs(houses) do
        if house.isOwner then
            local dist = distanceToHouse(pos, house)
            if dist < closestDistance then
                closestDistance = dist
                closestHouse = house
            end
        end
    end

    return closestHouse, closestDistance
end

local function findOwnedShellInterior(pos)
    local closestHouse = nil
    local closestDistance = 9999.0

    for _, house in ipairs(houses or {}) do
        if house.isOwner and housePropertyType(house) == 'shell' then
            local definition = configuredShell(shellModelName(house.shell or ''))
            local exitPoint = definition and shellInteriorExit(definition, shellInstanceOrigin(house))
            if not exitPoint then
                local settings = house.settings or {}
                exitPoint = settings.exit or (Config.Interior and Config.Interior.defaultExit)
            end
            if validPoint(exitPoint) then
                local dist = #(pos - vector3(exitPoint.x, exitPoint.y, exitPoint.z))
                if dist < closestDistance then
                    closestDistance = dist
                    closestHouse = house
                end
            end
        end
    end

    local recoveryDistance = tonumber(Config.OwnerCommandInteriorDistance) or 25.0
    if closestHouse and closestDistance <= recoveryDistance then return closestHouse, closestDistance end
    return nil, closestDistance
end

local function openOwnerMenu()
    print(('[lc-housing] /%s requested inside=%s'):format(tostring(Config.OwnerCommand), tostring(insideHouse and insideHouse.name or 'none')))
    if insideHouse then
        openListing(insideHouse)
        return
    end

    triggerCallback('lc-housing:server:getHouses', function(result)
        print(('[lc-housing] /%s getHouses response ok=%s count=%s message=%s'):format(tostring(Config.OwnerCommand), tostring(result and result.ok), tostring(result and result.houses and #result.houses or 0), tostring(result and result.message)))
        if result and result.ok then
            houses = result.houses or {}
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end

        local pos = GetEntityCoords(PlayerPedId())
        local interiorHouse = findOwnedShellInterior(pos)
        if interiorHouse then
            insideHouse = interiorHouse
            outsideCoords = interiorHouse.coords and interiorHouse.coords.enter or nil
            openListing(interiorHouse)
            return
        end

        local closestHouse, closestDistance = findClosestOwnedHouse(pos)
        local commandDistance = tonumber(Config.OwnerCommandDistance) or math.max(tonumber(Config.Interaction.drawDistance) or 35.0, 35.0)

        if closestHouse and closestDistance <= commandDistance then
            openListing(closestHouse)
        else
            notify('Stand near one of your houses, or use this command while inside.', 'error')
        end
    end)
end

RegisterCommand(Config.Command, openPanel, false)
RegisterCommand(Config.CreateCommand, openPanel, false)
RegisterCommand(Config.OwnerCommand, openOwnerMenu, false)
RegisterNetEvent('lc-housing:client:open', openPanel)

RegisterNetEvent('lc-housing:client:setHouses', function(nextHouses)
    houses = nextHouses or {}
    syncHouseGarages()
    refreshHouseBlips()
    refreshDoorLocks()
    rebuildTargetZones()
    if panelOpen then SendNUIMessage({ action = 'replaceHouses', houses = houses }) end
end)

RegisterNUICallback('close', function(_, cb)
    shellPreviewToken = shellPreviewToken + 1
    clearShellPreview()
    panelOpen = false
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('previewAdminShell', function(data, cb)
    local model = data and tostring(data.shell or '') or ''
    local shell = configuredShell(model)
    local previewConfig = Config.ShellPreview or {}
    if not panelOpen or not shell then
        cb({ ok = false, message = 'That shell is not available.' })
        return
    end
    if previewConfig.enabled == false then
        cb({ ok = false, message = 'Shell previews are disabled.' })
        return
    end
    local screenshotResource = tostring(previewConfig.resource or 'screenshot-basic')
    if GetResourceState(screenshotResource) ~= 'started' then
        cb({ ok = false, message = 'screenshot-basic is not running.' })
        return
    end

    shellPreviewToken = shellPreviewToken + 1
    local token = shellPreviewToken
    cb({ ok = true, pending = true })

    CreateThread(function()
        clearShellPreview()
        SendNUIMessage({ action = 'hide' })
        SetNuiFocus(false, false)

        local hash = joaat(model)
        RequestModel(hash)
        local deadline = GetGameTimer() + (tonumber(previewConfig.modelLoadTimeout) or 8000)
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
        if not HasModelLoaded(hash) or token ~= shellPreviewToken then
            clearShellPreview()
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'shellPreviewReady', ok = false, shell = model, message = 'The shell model could not be loaded.' })
            return
        end

        local playerCoords = GetEntityCoords(PlayerPedId())
        local spawn = vector3(playerCoords.x, playerCoords.y, playerCoords.z - 100.0)
        shellPreviewObject = CreateObject(hash, spawn.x, spawn.y, spawn.z, false, false, false)
        FreezeEntityPosition(shellPreviewObject, true)
        SetEntityCollision(shellPreviewObject, true, true)
        SetModelAsNoLongerNeeded(hash)

        local view = type(shell) == 'table' and shell.preview or nil
        view = view or { camera = { 3.0, -5.0, 2.5 }, target = { 0.0, 0.0, 1.5 } }
        shellPreviewCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamCoord(shellPreviewCamera, spawn.x + view.camera[1], spawn.y + view.camera[2], spawn.z + view.camera[3])
        PointCamAtCoord(shellPreviewCamera, spawn.x + view.target[1], spawn.y + view.target[2], spawn.z + view.target[3])
        SetCamFov(shellPreviewCamera, view.fov or 76.0)
        SetFocusPosAndVel(spawn.x, spawn.y, spawn.z, 0.0, 0.0, 0.0)
        RenderScriptCams(true, false, 0, true, true)

        local hidingHud = true
        CreateThread(function()
            while hidingHud and token == shellPreviewToken do
                HideHudAndRadarThisFrame()
                Wait(0)
            end
        end)
        Wait(tonumber(previewConfig.captureDelay) or 1200)

        local completed = false
        exports[screenshotResource]:requestScreenshot({ encoding = 'jpg', quality = tonumber(previewConfig.quality) or 0.55 }, function(image)
            if completed or token ~= shellPreviewToken then return end
            completed = true
            hidingHud = false
            clearShellPreview()
            SetNuiFocus(true, true)
            SendNUIMessage({
                action = 'shellPreviewReady',
                ok = type(image) == 'string' and #image > 100,
                shell = model,
                image = image,
                message = 'The shell preview capture returned no image.'
            })
        end)

        SetTimeout(tonumber(previewConfig.captureTimeout) or 10000, function()
            if completed or token ~= shellPreviewToken then return end
            completed = true
            hidingHud = false
            clearShellPreview()
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'shellPreviewReady', ok = false, shell = model, message = 'The shell preview timed out.' })
        end)
    end)
end)

RegisterNUICallback('refresh', function(_, cb)
    triggerCallback('lc-housing:server:getPanelData', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end)
end)

RegisterNUICallback('useCurrentCoords', function(_, cb)
    local coords = currentCoords()
    triggerCallback('lc-housing:server:nextHouseName', function(result)
        if result and result.ok then coords.name = result.name end
        cb({ ok = true, coords = coords })
    end, { base = coords.nameBase or coords.label })
end)

RegisterNUICallback('beginSetEntrance', function(_, cb)
    pendingEntryPlacement = true
    panelOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hide' })
    notify('Move to the front door and press E to set the entry point, or Esc to cancel.', 'primary')
    cb({ ok = true })
end)

RegisterNUICallback('useCurrentGarage', function(_, cb)
    if not Config.Garage or not Config.Garage.enabled then
        cb({ ok = false, message = 'Garage support is disabled in config.' })
        return
    end
    cb({ ok = true, coords = currentCoords() })
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    if data and data.x and data.y then
        SetNewWaypoint(tonumber(data.x), tonumber(data.y))
        notify('Waypoint set.', 'success')
    end
    cb({ ok = true })
end)

RegisterNUICallback('startPoly', function(data, cb)
    panelOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hide' })
    drawingPoly = true
    polyPoints = data and data.points or {}
    notify('Polyzone drawing started. E adds a point, Backspace removes, Enter saves.', 'primary')
    cb({ ok = true })
end)

RegisterNUICallback('scanDoorLocks', function(data, cb)
    if not Config.Debug then cb({ ok = false, message = 'Door scanning is only available in debug mode.' }) return end

    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
    notify('Scanning property doors and writing debug report...', 'primary')
    CreateThread(function()
        local doors = scanDoorObjects(data and data.points or {})
        for index, door in ipairs(doors) do
            if not door.name or door.name == '' then door.name = ('Scanned Door %s'):format(index) end
        end

        triggerCallback('lc-housing:server:exportDoorScan', function(exportResult)
            panelOpen = true
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'doorScanResult', doors = doors, export = exportResult })

            local foundMessage = ("Found %s door lock%s."):format(#doors, #doors == 1 and "" or "s")
            if exportResult and exportResult.ok then
                notify(('%s Debug details written to %s.'):format(foundMessage, exportResult.file or 'door_scan_debug.lua'), #doors > 0 and 'success' or 'error')
            else
                notify(('%s %s'):format(foundMessage, exportResult and exportResult.message or 'Debug export failed.'), 'error')
            end
        end, {
            name = data and data.name,
            label = data and data.label,
            propertyType = data and data.propertyType,
            doors = doors
        })
    end)
    cb({ ok = true })
end)

RegisterNUICallback('addHouseDoor', function(data, cb)
    if not data or not data.name then cb({ ok = false, message = 'House is missing.' }) return end

    local targetHouse
    for _, house in ipairs(houses or {}) do
        if house.name == data.name then targetHouse = house break end
    end
    if not targetHouse or not targetHouse.isOwner then cb({ ok = false, message = 'You do not own this house.' }) return end

    local found = nearestDoorObject()
    if not found then cb({ ok = false, message = 'Face the door and stand closer, then try Add Door again.' }) return end

    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
    cb({ ok = true, pending = true })

    CreateThread(function()
        local isGarageDoor = tostring(found.kind or ''):lower() == 'garage'
        local paired = isGarageDoor and nil or findPairedDoorObject(found)
        local isDoubleDoor = paired ~= nil
        local selectedDoors = isDoubleDoor and { found, paired } or { found }
        showDoorSelectionOutlines(selectedDoors)
        notify(isGarageDoor and 'Garage door selected. Name this lock.' or (isDoubleDoor and 'Double door selected. Name this lock.' or 'Single door selected. Name this lock.'), 'primary')

        local defaultName = 'Door ' .. (((targetHouse.settings and targetHouse.settings.doors and #targetHouse.settings.doors) or 0) + 1)
        local name = keyboardInput(isGarageDoor and 'Garage door lock name' or (isDoubleDoor and 'Double door lock name' or 'Single door lock name'), defaultName, 64)
        clearDoorSelectionOutlines()
        if not name or name == '' then
            notify('Door add canceled.', 'error')
            openListing(targetHouse)
            return
        end

        local doors = targetHouse.settings and targetHouse.settings.doors or {}
        local doorType = isGarageDoor and 'garage' or (isDoubleDoor and 'double' or 'single')
        local added = 0

        if not savedDoorNear(doors, found.coords) then
            doors[#doors + 1] = doorPayloadFromObject(found, isDoubleDoor and (name .. ' 1') or name, doorType, isDoubleDoor and 'left' or '')
            added = added + 1
        end

        if paired and not savedDoorNear(doors, paired.coords) then
            doors[#doors + 1] = doorPayloadFromObject(paired, name .. ' 2', doorType, 'right')
            added = added + 1
        end

        if added < 1 then
            notify('That door is already saved.', 'error')
            openListing(targetHouse)
            return
        end

        triggerCallback('lc-housing:server:updateDoors', function(result)
            if result and result.houses then
                houses = result.houses
                syncHouseGarages()
                refreshHouseBlips()
                refreshDoorLocks()
                rebuildTargetZones()
            end

            if result and result.ok then
                notify(doorType == 'garage' and 'Garage door added.' or (added > 1 and 'Double door added.' or 'Door added.'), 'success')
                for _, house in ipairs(houses) do
                    if house.name == data.name then
                        if insideHouse and insideHouse.name == data.name then insideHouse = house end
                        openListing(house)
                        return
                    end
                end
            else
                notify(result and result.message or 'Could not add door.', 'error')
            end

            openListing(targetHouse)
        end, { name = data.name, doors = doors })
    end)
end)

RegisterNUICallback('teleportDoor', function(data, cb)
    local coords = data and (data.coords or data)
    if not validPoint(coords) then cb({ ok = false, message = 'Door coordinates are missing.' }) return end

    teleportTo({ x = coords.x, y = coords.y, z = coords.z, h = data.h or data.heading or 0.0 })
    cb({ ok = true })
end)

RegisterNUICallback('saveHouseDoorList', function(data, cb)
    if not data or not data.name then cb({ ok = false, message = 'House is missing.' }) return end
    local targetHouse
    for _, house in ipairs(houses or {}) do if house.name == data.name then targetHouse = house break end end
    if not targetHouse or not targetHouse.isOwner then cb({ ok = false, message = 'You do not own this house.' }) return end

    triggerCallback('lc-housing:server:updateDoors', function(result)
        if result and result.houses then houses = result.houses; syncHouseGarages(); refreshHouseBlips(); refreshDoorLocks(); rebuildTargetZones() end
        if result and result.ok and insideHouse and insideHouse.name == data.name then for _, house in ipairs(houses) do if house.name == data.name then insideHouse = house break end end end
        cb(result or { ok = false, message = 'No response from server.' })
    end, { name = data.name, doors = data.doors or {}, defaultLocked = false })
end)

RegisterNUICallback('removeHouseDoor', function(data, cb)
    if not data or not data.name then cb({ ok = false, message = 'House is missing.' }) return end
    local targetHouse
    for _, house in ipairs(houses or {}) do if house.name == data.name then targetHouse = house break end end
    if not targetHouse or not targetHouse.isOwner then cb({ ok = false, message = 'You do not own this house.' }) return end
    local doors = targetHouse.settings and targetHouse.settings.doors or {}
    if #doors < 1 then cb({ ok = false, message = 'This house has no saved doors.' }) return end
    local pos = GetEntityCoords(PlayerPedId())
    local removeIndex, removeDist
    for index, door in ipairs(doors) do
        local c = door.coords or door
        if validPoint(c) then
            local dist = #(pos - vector3(c.x, c.y, c.z))
            if not removeDist or dist < removeDist then removeIndex, removeDist = index, dist end
        end
    end
    if not removeIndex or removeDist > (tonumber(doorLockSettings().addRadius) or 3.0) then cb({ ok = false, message = 'Stand near a saved door to remove it.' }) return end
    table.remove(doors, removeIndex)
    triggerCallback('lc-housing:server:updateDoors', function(result)
        if result and result.houses then houses = result.houses; syncHouseGarages(); refreshHouseBlips(); refreshDoorLocks(); rebuildTargetZones() end
        if result and result.ok and insideHouse and insideHouse.name == data.name then for _, house in ipairs(houses) do if house.name == data.name then insideHouse = house break end end end
        cb(result or { ok = false, message = 'No response from server.' })
    end, { name = data.name, doors = doors, defaultLocked = false })
end)

RegisterNUICallback('createHouse', function(data, cb)
    triggerCallback('lc-housing:server:createHouse', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data)
end)

RegisterNUICallback('updateHouse', function(data, cb)
    triggerCallback('lc-housing:server:updateHouse', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data)
end)

RegisterNUICallback('deleteHouse', function(data, cb)
    triggerCallback('lc-housing:server:deleteHouse', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data and data.name)
end)



RegisterNUICallback('buyHouse', function(data, cb)
    triggerCallback('lc-housing:server:buyHouse', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data and data.name)
end)



RegisterNUICallback('enterHouse', function(data, cb)
    triggerCallback('lc-housing:server:enterHouse', function(result)
        if result and result.ok then
            insideHouse = result.house
            outsideCoords = result.house and result.house.coords and result.house.coords.enter or nil
            panelOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'close' })
            teleportTo(activeShellExit or result.exit)
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data and data.name)
end)

RegisterNUICallback('previewHouse', function(data, cb)
    triggerCallback('lc-housing:server:previewHouse', function(result)
        if result and result.ok then
            insideHouse = result.house
            outsideCoords = result.house and result.house.coords and result.house.coords.enter or nil
            panelOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'close' })
            teleportTo(activeShellExit or result.exit)
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data and data.name)
end)

RegisterNUICallback('toggleLock', function(data, cb)
    triggerCallback('lc-housing:server:toggleLock', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, data and data.name)
end)

RegisterNUICallback('logoutHouse', function(_, cb)
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    logoutFromHouse()
    cb({ ok = true })
end)

RegisterNUICallback('sellHouse', function(data, cb)
    local soldName = data and data.name
    triggerCallback('lc-housing:server:sellHouse', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        if result and result.ok and insideHouse and insideHouse.name == soldName then
            teleportTo(outsideCoords or (insideHouse.coords and insideHouse.coords.enter))
            TriggerEvent('lc-housing:furniture:leaveShell', insideHouse.name)
            insideHouse = nil
            outsideCoords = nil
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, soldName)
end)

RegisterNUICallback("beginSetHousePoint", function(data, cb)
    if not data or not data.name then
        cb({ ok = false, message = "House is missing." })
        return
    end

    local targetHouse = findHouseByName(data.name)
    if not targetHouse or not targetHouse.isOwner then
        cb({ ok = false, message = "You do not own this house." })
        return
    end

    local pointType = data.pointType
    if pointType ~= "exit" and pointType ~= "stash" and pointType ~= "wardrobe" and pointType ~= "logout" then
        cb({ ok = false, message = "Invalid point type." })
        return
    end

    local propertyType = housePropertyType(targetHouse)
    if propertyType == "shell" and (not insideHouse or insideHouse.name ~= data.name) then
        cb({ ok = false, message = "Enter this house before setting interior points." })
        return
    end

    pendingPointPlacement = { name = data.name, pointType = pointType, propertyType = propertyType }
    panelOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = "hide" })
    notify(("Press E to set %s location, or Esc to cancel."):format(pointType), "primary")
    cb({ ok = true })
end)

RegisterNUICallback('setHousePoint', function(data, cb)
    if not data or not data.name then
        cb({ ok = false, message = 'House is missing.' })
        return
    end

    local targetHouse = findHouseByName(data.name)
    if not targetHouse or not targetHouse.isOwner then
        cb({ ok = false, message = 'You do not own this house.' })
        return
    end

    if housePropertyType(targetHouse) == 'shell' and (not insideHouse or insideHouse.name ~= data.name) then
        cb({ ok = false, message = 'Enter this house before setting interior points.' })
        return
    end

    local coords = currentCoords()
    coords.name = data and data.name
    coords.pointType = data and data.pointType
    triggerCallback('lc-housing:server:updateHousePoint', function(result)
        if result and result.houses then
            houses = result.houses
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        end
        if result and result.ok and insideHouse and insideHouse.name == coords.name then
            for _, house in ipairs(houses) do
                if house.name == insideHouse.name then insideHouse = house break end
            end
        end
        cb(result or { ok = false, message = 'No response from server.' })
    end, coords)
end)


CreateThread(function()
    while true do
        if drawingPoly then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            drawText(('Polyzone: %s points | E add | Backspace undo | Enter save | Esc cancel'):format(#polyPoints))

            for index, point in ipairs(polyPoints) do
                DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.35, 126, 182, 255, 185, false, false, 2, false, nil, nil, false)
                local nextPoint = polyPoints[index + 1]
                if nextPoint then DrawLine(point.x, point.y, point.z, nextPoint.x, nextPoint.y, nextPoint.z, 126, 182, 255, 220) end
            end
            if #polyPoints > 0 then
                local last = polyPoints[#polyPoints]
                DrawLine(last.x, last.y, last.z, pos.x, pos.y, pos.z, 126, 182, 255, 180)
                if #polyPoints > 2 then
                    local first = polyPoints[1]
                    DrawLine(pos.x, pos.y, pos.z, first.x, first.y, first.z, 126, 182, 255, 120)
                end
            end

            local cancelPressed = placementCancelPressed()
            if IsControlJustPressed(0, 38) then
                polyPoints[#polyPoints + 1] = currentCoords()
                notify(('Added poly point %s.'):format(#polyPoints), 'success')
            elseif IsControlJustPressed(0, 177) then
                if #polyPoints > 0 then polyPoints[#polyPoints] = nil end
            elseif IsControlJustPressed(0, 191) then
                drawingPoly = false
                panelOpen = true
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'polyResult', points = polyPoints })
            elseif cancelPressed then
                drawingPoly = false
                panelOpen = true
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'show' })
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

local function loadHouses(retries)
    retries = retries or 8
    triggerCallback('lc-housing:server:getHouses', function(result)
        if result and result.ok then
            houses = result.houses or {}
            syncHouseGarages()
            refreshHouseBlips()
            refreshDoorLocks()
            rebuildTargetZones()
        elseif retries > 0 then
            SetTimeout(1500, function() loadHouses(retries - 1) end)
        end
    end)
end

CreateThread(function()
    Wait(2500)
    loadHouses(10)
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetTimeout(2500, function() loadHouses(10) end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    SetTimeout(1000, function() loadHouses(10) end)
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    SetTimeout(1000, function() loadHouses(10) end)
end)

CreateThread(function()
    while true do
        if pendingPointPlacement then
            local label = pendingPointPlacement.pointType or "point"
            drawText(("[E] Save %s location | Esc cancel"):format(label))

            local cancelPressed = placementCancelPressed()
            if IsControlJustPressed(0, 38) then
                local placement = pendingPointPlacement
                pendingPointPlacement = nil
                local coords = currentCoords()
                coords.name = placement.name
                coords.pointType = placement.pointType
                triggerCallback("lc-housing:server:updateHousePoint", function(result)
                    if result and result.houses then
                        houses = result.houses
                        syncHouseGarages()
                        refreshHouseBlips()
                        refreshDoorLocks()
                        rebuildTargetZones()
                    end
                    if result and result.ok then
                        notify(("%s location saved."):format(placement.pointType), "success")
                        local house = findHouseByName(placement.name)
                        if house then
                            if placement.propertyType == "shell" then insideHouse = house end
                            openListing(house)
                        end
                    else
                        notify(result and result.message or "Could not save location.", "error")
                        local house = findHouseByName(placement.name) or insideHouse
                        if house then openListing(house) end
                    end
                end, coords)
            elseif cancelPressed then
                local placement = pendingPointPlacement
                local house = placement and findHouseByName(placement.name) or insideHouse
                pendingPointPlacement = nil
                notify("Location placement canceled.", "error")
                if house then openListing(house) end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if pendingEntryPlacement then
            drawText('[E] Save entrance location | Esc cancel')

            local cancelPressed = placementCancelPressed()
            if IsControlJustPressed(0, 38) then
                pendingEntryPlacement = false
                local coords = currentCoords()
                triggerCallback('lc-housing:server:nextHouseName', function(result)
                    if result and result.ok then coords.name = result.name end
                    panelOpen = true
                    SetNuiFocus(true, true)
                    SendNUIMessage({ action = 'entranceResult', coords = coords })
                    notify('Entrance point set.', 'success')
                end, { base = coords.nameBase or coords.label })
            elseif cancelPressed then
                pendingEntryPlacement = false
                panelOpen = true
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'show' })
                notify('Entrance placement canceled.', 'error')
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        shellPreviewToken = shellPreviewToken + 1
        clearShellPreview()
        clearActiveShell()
        clearHouseIpl()
        clearDoorSelectionOutlines()
        clearTargetZones()
        clearHouseBlips()
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == (Config.Garage and Config.Garage.resource or 'qb-garages') then
        Wait(1000)
        syncHouseGarages()
    end
end)

CreateThread(function()
    while true do
        local position = GetEntityCoords(PlayerPedId())
        local requiredIpl = nil
        for _, house in ipairs(houses or {}) do
            if housePropertyType(house) == 'ipl' and pointInPoly2d({ x = position.x, y = position.y }, house.polyzone or {}) then
                requiredIpl = house.ipl
                break
            end
        end
        if requiredIpl then activateHouseIpl({ ipl = requiredIpl }) elseif activeIplName then clearHouseIpl() end
        Wait(2500)
    end
end)

CreateThread(function()
    while true do
        refreshDoorLocks()
        Wait(1500)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000

        if insideHouse then
            sleep = 0
            if interactionMode() ~= 'target' then
                local settings = insideHouse.settings or {}
                local exitPoint = activeShellExit or settings.exit or Config.Interior.defaultExit
                local stashPoint = settings.stash
                local wardrobePoint = settings.wardrobe
                local logoutPoint = settings.logout

            if distanceTo(exitPoint) < Config.Interior.drawDistance then
                DrawMarker(2, exitPoint.x, exitPoint.y, exitPoint.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.26, 0.26, 0.26, 126, 182, 255, 140, false, false, 2, true, nil, nil, false)
                if distanceTo(exitPoint) < Config.Interior.promptDistance then
                    drawText('Press [E] to leave')
                    if IsControlJustPressed(0, 38) then
                        clearActiveShell()
                        teleportTo(outsideCoords or (insideHouse.coords and insideHouse.coords.enter))
                        insideHouse = nil
                        outsideCoords = nil
                    end
                end
            end

            if stashPoint and distanceTo(stashPoint) < Config.Interior.drawDistance then
                DrawMarker(2, stashPoint.x, stashPoint.y, stashPoint.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, 88, 214, 141, 140, false, false, 2, true, nil, nil, false)
                if distanceTo(stashPoint) < Config.Interior.promptDistance then
                    drawText('Press [E] to open stash')
                    if IsControlJustPressed(0, 38) then openStash(insideHouse) end
                end
            end

            if wardrobePoint and distanceTo(wardrobePoint) < Config.Interior.drawDistance then
                DrawMarker(2, wardrobePoint.x, wardrobePoint.y, wardrobePoint.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, 247, 198, 106, 140, false, false, 2, true, nil, nil, false)
                if distanceTo(wardrobePoint) < Config.Interior.promptDistance then
                    drawText('Press [E] to change outfit')
                    if IsControlJustPressed(0, 38) then openWardrobe() end
                end
            end

            if logoutPoint and distanceTo(logoutPoint) < Config.Interior.drawDistance then
                DrawMarker(2, logoutPoint.x, logoutPoint.y, logoutPoint.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, 255, 109, 109, 140, false, false, 2, true, nil, nil, false)
                if distanceTo(logoutPoint) < Config.Interior.promptDistance then
                    drawText('Press [E] to logout')
                    if IsControlJustPressed(0, 38) then logoutFromHouse() end
                end
            end
            end
        else
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local worldPointPrompt = nil
            if not panelOpen then
                worldPointPrompt = nearestOwnedWorldPoint(pos)
                if worldPointPrompt then
                    sleep = 0
                    local markerColor = worldPointPrompt.marker or { 126, 182, 255 }
                    local point = worldPointPrompt.point
                    DrawMarker(2, point.x, point.y, point.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, markerColor[1] or 126, markerColor[2] or 182, markerColor[3] or 255, 150, false, false, 2, true, nil, nil, false)
                    if worldPointPrompt.canUse then
                        drawText(worldPointPrompt.text)
                        if IsControlJustPressed(0, 38) then useWorldPointPrompt(worldPointPrompt) end
                    end
                end
            end

            local useTargets = targetsEnabled()
            local useMarkers = markersEnabled()
            local marker = interactionMarkerConfig()
            local markerScale = marker.scale or {}
            local markerColor = marker.color or {}
            if Config.Debug and (not Config.DebugDraw or Config.DebugDraw.enabled ~= false) then sleep = 0 end

            local doorPrompt = nil
            if not panelOpen and not (worldPointPrompt and worldPointPrompt.canUse) then
                doorPrompt = nearestOwnedDoor(pos)
                if doorPrompt then
                    sleep = 0
                    drawDoorLockIcon(doorPrompt)
                    if doorPrompt.canUse and IsControlJustPressed(0, 38) then
                        toggleDoorLockFromWorld(doorPrompt)
                    end
                end
            end

            for _, house in ipairs(houses) do
                drawDebugHouse(house, pos)
                local enter = house.coords and house.coords.enter
                if enter then
                    local dist = #(pos - vector3(enter.x, enter.y, enter.z))
                    if dist < Config.Interaction.drawDistance then
                        sleep = 0

                        if useMarkers and not house.owned and not house.isOwner then
                            local markerX, markerY, markerZ = markerPosition(enter)
                            DrawMarker(
                                marker.type or 2,
                                markerX, markerY, markerZ,
                                0.0, 0.0, 0.0,
                                0.0, 0.0, 0.0,
                                markerScale.x or 0.28, markerScale.y or 0.28, markerScale.z or 0.28,
                                markerColor.r or 126, markerColor.g or 182, markerColor.b or 255, markerColor.a or 150,
                                false, false, 2, true, nil, nil, false
                            )
                        end

                        local promptEnabled = interactionMode() ~= 'target'
                        if promptEnabled and dist < Config.Interaction.promptDistance and not (doorPrompt and doorPrompt.canUse) and not (worldPointPrompt and worldPointPrompt.canUse) then
                            nearestHouse = house
                            local propertyType = housePropertyType(house)
                            local canPrompt = true

                            if house.isOwner and propertyType == 'shell' then
                                drawText(('Press [E] to enter %s'):format(house.label))
                            elseif house.isOwner then
                                canPrompt = false -- MLO/IPL entry is physical; management stays in /myhouse or third eye.
                            elseif house.owned then
                                canPrompt = false
                                drawText(('%s is owned'):format(house.label))
                            else
                                drawText(('Press [E] to view %s | $%s'):format(house.label, house.price))
                            end

                            if canPrompt and not panelOpen and IsControlJustPressed(0, 38) and canUseHouseInteraction(house) then
                                if house.isOwner and propertyType == 'shell' then
                                    enterOwnedShellHouse(house)
                                else
                                    openListing(house)
                                end
                            end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
