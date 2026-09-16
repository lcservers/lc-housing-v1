local function frameworkResource()
    if Config.Framework == 'qb' then return Config.FrameworkResources.qb end
    if Config.Framework == 'qbox' then return Config.FrameworkResources.qbox end
    if GetResourceState(Config.FrameworkResources.qbox) == 'started' then return Config.FrameworkResources.qbox end
    return Config.FrameworkResources.qb
end

local Core = exports[frameworkResource()]:GetCoreObject()
local houseCache, spawned, loaded = {}, {}, {}
local activeHouse, preview, previewData
local decorating, cursorEnabled, placementActive = false, false, false
local editorCamera, cameraPosition, cameraRotation
local movementSpeed = 0.01
local rotationSpeed = 0.55
local cameraSpeed = 0.075
local cameraLookSpeed = 7.0

local function callback(name, cb, ...)
    Core.Functions.TriggerCallback(name, cb, ...)
end

local function notify(message, kind)
    Core.Functions.Notify(message, kind or 'primary')
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

local function deletePreview()
    if preview and DoesEntityExist(preview) then
        SetEntityDrawOutline(preview, false)
        DeleteEntity(preview)
    end
    preview, previewData, placementActive = nil, nil, false
end

local function clearHouse(name)
    for _, entity in pairs(spawned[name] or {}) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    spawned[name], loaded[name] = nil, nil
end

local function spawnRow(row)
    local model = joaat(row.model)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(model) then return nil end
    local object = CreateObjectNoOffset(model, tonumber(row.x), tonumber(row.y), tonumber(row.z), false, false, false)
    SetEntityRotation(object, tonumber(row.rot_x) or 0.0, tonumber(row.rot_y) or 0.0, tonumber(row.rot_z) or 0.0, 2, true)
    FreezeEntityPosition(object, true)
    SetEntityAsMissionEntity(object, true, true)
    SetModelAsNoLongerNeeded(model)
    return object
end

local function loadHouse(name, done)
    callback('lc-housing:furniture:get', function(result)
        if not result or not result.ok then
            if done then done(result) end
            return
        end
        clearHouse(name)
        spawned[name], loaded[name] = {}, true
        for _, row in ipairs(result.furniture or {}) do
            local object = spawnRow(row)
            if object then spawned[name][tonumber(row.id)] = object end
        end
        if done then done(result) end
    end, name)
end

local function nearestOwnedDecoratableHouse()
    local stateHouse = LocalPlayer.state.lcHouse
    if stateHouse then return stateHouse end
    local pos = GetEntityCoords(PlayerPedId())
    for _, house in ipairs(houseCache) do
        if house.isOwner and tostring(house.propertyType):lower() == 'mlo' and pointInPoly(pos.x, pos.y, house.polyzone or {}) then return house.name end
    end
end

local function setCursor(enabled)
    cursorEnabled = enabled == true
    SetNuiFocus(cursorEnabled, cursorEnabled)
    SetNuiFocusKeepInput(cursorEnabled and decorating)
end

local function rotationToDirection(rotation)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    return vector3(-math.sin(yaw) * math.abs(math.cos(pitch)), math.cos(yaw) * math.abs(math.cos(pitch)), math.sin(pitch))
end

local function startEditorCamera()
    if editorCamera and DoesCamExist(editorCamera) then return end
    cameraPosition = GetGameplayCamCoord()
    cameraRotation = GetGameplayCamRot(2)
    editorCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(editorCamera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    SetCamRot(editorCamera, cameraRotation.x, cameraRotation.y, cameraRotation.z, 2)
    SetCamFov(editorCamera, GetGameplayCamFov())
    RenderScriptCams(true, true, 350, true, true)
    FreezeEntityPosition(PlayerPedId(), true)
end

local function stopEditorCamera()
    if editorCamera and DoesCamExist(editorCamera) then
        RenderScriptCams(false, true, 300, true, true)
        DestroyCam(editorCamera, false)
    end
    editorCamera, cameraPosition, cameraRotation = nil, nil, nil
    FreezeEntityPosition(PlayerPedId(), false)
end

local function updateEditorCamera()
    if not editorCamera or not DoesCamExist(editorCamera) then return end
    DisableControlAction(0, 1, true)  -- Mouse horizontal
    DisableControlAction(0, 2, true)  -- Mouse vertical
    DisableControlAction(0, 24, true) -- Left mouse
    DisableControlAction(0, 25, true) -- Right mouse
    DisableControlAction(0, 32, true) -- W
    DisableControlAction(0, 33, true) -- S
    DisableControlAction(0, 34, true) -- A
    DisableControlAction(0, 35, true) -- D
    DisableControlAction(0, 44, true) -- Q
    DisableControlAction(0, 38, true) -- E

    if IsDisabledControlPressed(0, 25) then
        cameraRotation = vector3(
            math.max(-89.0, math.min(89.0, cameraRotation.x - GetDisabledControlNormal(0, 2) * cameraLookSpeed)),
            0.0,
            cameraRotation.z - GetDisabledControlNormal(0, 1) * cameraLookSpeed
        )
    end

    local forward = rotationToDirection(cameraRotation)
    local yaw = math.rad(cameraRotation.z)
    local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local speed = cameraSpeed * (IsDisabledControlPressed(0, 21) and 2.5 or 1.0)
    if IsDisabledControlPressed(0, 32) then cameraPosition = cameraPosition + forward * speed end
    if IsDisabledControlPressed(0, 33) then cameraPosition = cameraPosition - forward * speed end
    if IsDisabledControlPressed(0, 34) then cameraPosition = cameraPosition - right * speed end
    if IsDisabledControlPressed(0, 35) then cameraPosition = cameraPosition + right * speed end
    if IsDisabledControlPressed(0, 44) then cameraPosition = cameraPosition - vector3(0.0, 0.0, speed) end
    if IsDisabledControlPressed(0, 38) then cameraPosition = cameraPosition + vector3(0.0, 0.0, speed) end
    SetCamCoord(editorCamera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    SetCamRot(editorCamera, cameraRotation.x, 0.0, cameraRotation.z, 2)
end

local function drawAxisLabel(x, y, z, label, red, green, blue)
    SetDrawOrigin(x, y, z, 0)
    DrawRect(0.0, 0.011, 0.022, 0.028, 7, 15, 22, 210)
    SetTextFont(0)
    SetTextScale(0.0, 0.27)
    SetTextColour(red, green, blue, 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawTransformGizmo(entity)
    if not entity or not DoesEntityExist(entity) then return end
    local p = GetEntityCoords(entity)
    local length = 0.75
    local xEnd = GetOffsetFromEntityInWorldCoords(entity, length, 0.0, 0.0)
    local yEnd = GetOffsetFromEntityInWorldCoords(entity, 0.0, length, 0.0)
    local zEnd = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, length)
    local xLabel = GetOffsetFromEntityInWorldCoords(entity, length + 0.08, 0.0, 0.0)
    local yLabel = GetOffsetFromEntityInWorldCoords(entity, 0.0, length + 0.08, 0.0)
    local zLabel = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, length + 0.08)
    DrawLine(p.x, p.y, p.z, xEnd.x, xEnd.y, xEnd.z, 255, 45, 45, 255)
    DrawLine(p.x, p.y, p.z, yEnd.x, yEnd.y, yEnd.z, 55, 230, 80, 255)
    DrawLine(p.x, p.y, p.z, zEnd.x, zEnd.y, zEnd.z, 45, 105, 255, 255)
    DrawMarker(28, xEnd.x, xEnd.y, xEnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.11, 0.11, 0.11, 255, 45, 45, 235, false, false, 2, false, nil, nil, false)
    DrawMarker(28, yEnd.x, yEnd.y, yEnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.11, 0.11, 0.11, 55, 230, 80, 235, false, false, 2, false, nil, nil, false)
    DrawMarker(28, zEnd.x, zEnd.y, zEnd.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.11, 0.11, 0.11, 45, 105, 255, 235, false, false, 2, false, nil, nil, false)
    drawAxisLabel(xLabel.x, xLabel.y, xLabel.z, 'X', 255, 105, 105)
    drawAxisLabel(yLabel.x, yLabel.y, yLabel.z, 'Y', 105, 245, 135)
    drawAxisLabel(zLabel.x, zLabel.y, zLabel.z, 'Z', 100, 165, 255)
end

local function rayCastGamePlayCamera(distance, ignoreEntity)
    local rotation = editorCamera and DoesCamExist(editorCamera) and GetCamRot(editorCamera, 2) or GetGameplayCamRot(2)
    local camera = editorCamera and DoesCamExist(editorCamera) and GetCamCoord(editorCamera) or GetGameplayCamCoord()
    local direction = rotationToDirection(rotation)
    local destination = camera + direction * distance
    local ray = StartShapeTestRay(camera.x, camera.y, camera.z, destination.x, destination.y, destination.z, 17, ignoreEntity or PlayerPedId(), 0)
    local _, hit, endpoint = GetShapeTestResult(ray)
    return hit == 1, endpoint
end

local function createPreview(modelName, row)
    deletePreview()
    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return false, 'Invalid furniture model.' end
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(model) then return false, 'Furniture model could not load.' end

    local pos, rot
    if row then
        pos = vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z))
        rot = vector3(tonumber(row.rot_x) or 0.0, tonumber(row.rot_y) or 0.0, tonumber(row.rot_z) or 0.0)
    else
        local hit, endpoint = rayCastGamePlayCamera(50.0, PlayerPedId())
        pos = hit and endpoint or GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 1.5, 0.0)
        rot = vector3(0.0, 0.0, 0.0)
    end

    preview = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
    if not row then PlaceObjectOnGroundProperly(preview) end
    SetEntityRotation(preview, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(preview, true)
    SetEntityCollision(preview, false, false)
    SetEntityAsMissionEntity(preview, true, true)
    SetEntityAlpha(preview, 225, false)
    SetModelAsNoLongerNeeded(model)

    local actualPos, actualRot = GetEntityCoords(preview), GetEntityRotation(preview, 2)
    previewData = {
        id = row and tonumber(row.id) or nil,
        model = modelName,
        price = row and 0 or nil,
        x = actualPos.x, y = actualPos.y, z = actualPos.z,
        rotX = actualRot.x, rotY = actualRot.y, rotZ = actualRot.z,
    }
    return true
end

local function syncPreviewTransform()
    if not preview or not DoesEntityExist(preview) or not previewData then return end
    local pos, rot = GetEntityCoords(preview), GetEntityRotation(preview, 2)
    previewData.x, previewData.y, previewData.z = pos.x, pos.y, pos.z
    previewData.rotX, previewData.rotY, previewData.rotZ = rot.x, rot.y, rot.z
end

local function savePreview(done)
    if not activeHouse or not previewData then
        if done then done({ ok = false, message = 'Nothing selected.' }) end
        return
    end
    syncPreviewTransform()
    previewData.houseName = activeHouse
    callback('lc-housing:furniture:save', function(result)
        setCursor(true)
        if result and result.ok then
            deletePreview()
            loadHouse(activeHouse, function(rows)
                SendNUIMessage({ action = 'furnitureRows', furniture = rows and rows.furniture or {} })
            end)
            SendNUIMessage({ action = 'furniturePlacementDone' })
            notify(result.message, 'success')
        else
            deletePreview()
            if activeHouse then loadHouse(activeHouse) end
            SendNUIMessage({ action = 'furniturePlacementDone' })
            notify(result and result.message or 'Furniture could not be saved.', 'error')
        end
        if done then done(result or { ok = false, message = 'No server response.' }) end
    end, previewData)
end

local function closeDecorator()
    deletePreview()
    if activeHouse then loadHouse(activeHouse) end
    decorating, cursorEnabled = false, false
    stopEditorCamera()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    DisplayRadar(true)
    SendNUIMessage({ action = 'closeFurniture' })
    TriggerEvent('lc-housing:client:furnitureClosed')
    activeHouse = nil
end

local function openDecorator(name, nuiCb)
    print(('[lc-housing] decorate requested house=%s'):format(tostring(name)))
    if Config.Decoration and Config.Decoration.enabled == false then
        local result = { ok = false, message = 'Furniture decoration is disabled.' }
        notify(result.message, 'error')
        if nuiCb then nuiCb(result) end
        return
    end
    name = name or nearestOwnedDecoratableHouse()
    if not name then
        local result = { ok = false, message = 'Enter your shell or MLO property before decorating.' }
        notify(result.message, 'error')
        if nuiCb then nuiCb(result) end
        return
    end
    callback('lc-housing:furniture:canDecorate', function(access)
        print(('[lc-housing] decorate permission response house=%s ok=%s message=%s'):format(tostring(name), tostring(access and access.ok), tostring(access and access.message)))
        if not access or not access.ok then
            local result = access or { ok = false, message = 'Decoration unavailable.' }
            notify(result.message, 'error')
            if nuiCb then nuiCb(result) end
            return
        end
        activeHouse = name
        loadHouse(name, function(result)
            print(('[lc-housing] decorate furniture response house=%s ok=%s count=%s message=%s'):format(tostring(name), tostring(result and result.ok), tostring(result and result.furniture and #result.furniture or 0), tostring(result and result.message)))
            if not result or not result.ok then
                local failure = result or { ok = false, message = 'Could not load furniture.' }
                notify(failure.message, 'error')
                if nuiCb then nuiCb(failure) end
                return
            end
            decorating = true
            startEditorCamera()
            setCursor(true)
            DisplayRadar(false)
            SendNUIMessage({ action = 'openFurniture', house = result.house, furniture = result.furniture, catalog = Config.Furniture })
            print(('[lc-housing] decorate NUI openFurniture sent house=%s'):format(tostring(name)))
            if nuiCb then nuiCb({ ok = true }) end
        end)
    end, name)
end

RegisterNUICallback('openFurniture', function(data, cb)
    openDecorator(data and data.name, cb)
end)

RegisterNUICallback('furniturePreview', function(data, cb)
    local ok, message = createPreview(tostring(data and data.model or ''))
    if ok and previewData then previewData.price = tonumber(data and data.price) end
    cb({ ok = ok, message = message })
end)

RegisterNUICallback('furnitureEdit', function(data, cb)
    local row = data and data.item
    if not row then cb({ ok = false }) return end
    local old = spawned[activeHouse] and spawned[activeHouse][tonumber(row.id)]
    if old and DoesEntityExist(old) then DeleteEntity(old) end
    local ok, message = createPreview(tostring(row.model or ''), row)
    cb({ ok = ok, message = message })
end)

RegisterNUICallback('furnitureStartPlacement', function(_, cb)
    if not preview or not previewData then cb({ ok = false, message = 'Select an object first.' }) return end
    placementActive = true
    setCursor(true)
    cb({ ok = true })
end)

RegisterNUICallback('furnitureResetSelection', function(_, cb)
    local hadOwnedObject = previewData and previewData.id ~= nil
    deletePreview()
    if hadOwnedObject and activeHouse then loadHouse(activeHouse) end
    cb({ ok = true })
end)

RegisterNUICallback('furnitureSave', function(_, cb)
    savePreview(cb)
end)

RegisterNUICallback('furnitureBuy', function(_, cb)
    savePreview(cb)
end)

RegisterNUICallback('furnitureDelete', function(data, cb)
    callback('lc-housing:furniture:delete', function(result)
        if result and result.ok then
            deletePreview()
            loadHouse(activeHouse, function(rows)
                SendNUIMessage({ action = 'furnitureRows', furniture = rows and rows.furniture or {} })
            end)
            notify(result.message, 'success')
        end
        cb(result or { ok = false, message = 'No server response.' })
    end, { houseName = activeHouse, id = data and data.id })
end)

RegisterNUICallback('furnitureCancel', function(_, cb)
    local hadOwnedObject = previewData and previewData.id ~= nil
    deletePreview()
    if hadOwnedObject and activeHouse then loadHouse(activeHouse) end
    setCursor(true)
    cb({ ok = true })
end)

RegisterNUICallback('furnitureClose', function(_, cb)
    closeDecorator()
    SendNUIMessage({ action = 'hide' })
    cb({ ok = true })
end)

RegisterNetEvent('lc-housing:furniture:enterShell', function(name)
    LocalPlayer.state:set('lcHouse', name, true)
    loadHouse(name)
end)

RegisterNetEvent('lc-housing:furniture:leaveShell', function(name)
    LocalPlayer.state:set('lcHouse', nil, true)
    if activeHouse == name then closeDecorator() end
    clearHouse(name)
end)

RegisterNetEvent('lc-housing:furniture:refresh', function(name)
    if loaded[name] and not (activeHouse == name and previewData) then loadHouse(name) end
end)

RegisterNetEvent('lc-housing:client:setHouses', function(nextHouses)
    houseCache = nextHouses or {}
end)

RegisterCommand((Config.Decoration and Config.Decoration.command) or 'decorate', function() openDecorator() end, false)
RegisterNetEvent('lc-housing:client:decorate', function() openDecorator() end)

CreateThread(function()
    if Config.Decoration and Config.Decoration.enabled == false then return end
    callback('lc-housing:server:getHouses', function(result)
        if result and result.ok then houseCache = result.houses or {} end
    end)
end)

CreateThread(function()
    while true do
        if decorating then
            Wait(0)
            local escapeReleased = IsControlJustReleased(0, 177) or IsControlJustReleased(0, 200) or IsControlJustReleased(0, 322) or IsDisabledControlJustReleased(0, 177) or IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 322)
            DisplayRadar(false)
            updateEditorCamera()
            DisableControlAction(0, 166, true) -- F5
            DisableControlAction(0, 200, true) -- Escape
            DisableControlAction(0, 322, true) -- Escape
            DisableControlAction(0, 177, true) -- Backspace
            if IsDisabledControlJustReleased(0, 166) then setCursor(not cursorEnabled) end
            if escapeReleased then
                closeDecorator()
            end

            if placementActive and preview and DoesEntityExist(preview) then
                DisableControlAction(0, 21, true)  -- Shift
                DisableControlAction(0, 19, true)  -- Left Alt
                DisableControlAction(0, 191, true) -- Enter
                DisableControlAction(0, 27, true)  -- Up
                DisableControlAction(0, 173, true) -- Down
                DisableControlAction(0, 174, true) -- Left
                DisableControlAction(0, 175, true) -- Right
                DisableControlAction(0, 10, true)  -- Page Up
                DisableControlAction(0, 11, true)  -- Page Down

                local position, rotation = GetEntityCoords(preview), GetEntityRotation(preview, 2)
                if IsDisabledControlPressed(0, 21) then
                    if IsDisabledControlPressed(0, 27) then rotation = vector3(rotation.x + rotationSpeed, rotation.y, rotation.z) end
                    if IsDisabledControlPressed(0, 173) then rotation = vector3(rotation.x - rotationSpeed, rotation.y, rotation.z) end
                    if IsDisabledControlPressed(0, 174) then rotation = vector3(rotation.x, rotation.y, rotation.z + rotationSpeed) end
                    if IsDisabledControlPressed(0, 175) then rotation = vector3(rotation.x, rotation.y, rotation.z - rotationSpeed) end
                    if IsDisabledControlPressed(0, 10) then rotation = vector3(rotation.x, rotation.y + rotationSpeed, rotation.z) end
                    if IsDisabledControlPressed(0, 11) then rotation = vector3(rotation.x, rotation.y - rotationSpeed, rotation.z) end
                    SetEntityRotation(preview, rotation.x, rotation.y, rotation.z, 2, true)
                else
                    if IsDisabledControlPressed(0, 27) then position = GetOffsetFromEntityInWorldCoords(preview, 0.0, -movementSpeed, 0.0) end
                    if IsDisabledControlPressed(0, 173) then position = GetOffsetFromEntityInWorldCoords(preview, 0.0, movementSpeed, 0.0) end
                    if IsDisabledControlPressed(0, 174) then position = GetOffsetFromEntityInWorldCoords(preview, movementSpeed, 0.0, 0.0) end
                    if IsDisabledControlPressed(0, 175) then position = GetOffsetFromEntityInWorldCoords(preview, -movementSpeed, 0.0, 0.0) end
                    if IsDisabledControlPressed(0, 10) then position = vector3(position.x, position.y, position.z + movementSpeed) end
                    if IsDisabledControlPressed(0, 11) then position = vector3(position.x, position.y, position.z - movementSpeed) end
                    SetEntityCoordsNoOffset(preview, position.x, position.y, position.z, false, false, false)
                end

                if IsDisabledControlPressed(0, 19) then
                    local hit, endpoint = rayCastGamePlayCamera(50.0, preview)
                    if hit then SetEntityCoordsNoOffset(preview, endpoint.x, endpoint.y, endpoint.z, false, false, false) end
                end

                if not cursorEnabled and IsDisabledControlJustReleased(0, 191) then
                    syncPreviewTransform()
                    placementActive = false
                    if previewData.id then
                        savePreview()
                    else
                        setCursor(true)
                        SendNUIMessage({ action = 'furnitureConfirm', price = previewData.price or 0 })
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, house in ipairs(houseCache) do
            if tostring(house.propertyType):lower() == 'mlo' then
                local inside = pointInPoly(pos.x, pos.y, house.polyzone or {})
                if inside and not loaded[house.name] then loadHouse(house.name) end
                if not inside and loaded[house.name] and activeHouse ~= house.name then clearHouse(house.name) end
            end
        end
        Wait(2500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    stopEditorCamera()
    deletePreview()
    for name in pairs(spawned) do clearHouse(name) end
end)
