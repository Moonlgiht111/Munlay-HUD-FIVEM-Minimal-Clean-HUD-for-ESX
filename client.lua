local hudData = {
    lastHunger = 100,
    lastThirst = 100,
    isTalking = false,      -- Solo visual
    voiceRange = 2,         -- Solo visual
    inVehicle = false,
    seatbelt = false,       -- Solo visual
    cash = 0,
    bank = 0,
    black = 0,
    job = nil,
    moneyHudVisible = false,
    playerId = 0
}

-- Configuración para ocultar/mostrar elementos del HUD
local hudConfig = {
    showMoney = false,       -- Controla si se muestra dinero, banco y dinero negro
    showJob = false,         -- Controla si se muestra el trabajo
    enableMoneyUpdates = false,  -- Controla si se procesan actualizaciones de dinero
    enableJobUpdates = false     -- Controla si se procesan actualizaciones de trabajo
}

ESX = nil
local PlayerData = {}

-- Normaliza cuentas ESX en (cash, bank, black) sin importar versión
local function extractAccounts(accounts)
    local cash, bank, black = 0, 0, 0
    if not accounts then return cash, bank, black end

    local function getVal(acc)
        if acc.money ~= nil then return acc.money end
        if acc.count ~= nil then return acc.count end
        if acc.value ~= nil then return acc.value end
        return 0
    end

    for k, acc in pairs(accounts) do
        local name = acc.name or k
        if name == 'money' or name == 'cash' then
            cash = getVal(acc)
        elseif name == 'bank' then
            bank = getVal(acc)
        elseif name == 'black_money' or name == 'dirtycash' or name == 'illicit' then
            black = getVal(acc)
        end
    end
    return cash, bank, black
end

-- Refresco inmediato de dinero y trabajo desde ESX
local function forceRefreshHudData()
    if not ESX or not ESX.GetPlayerData then return end
    local data = ESX.GetPlayerData()
    if not data then return end

    if hudConfig.enableMoneyUpdates and data.accounts then
        local cash, bank, black = extractAccounts(data.accounts)
        hudData.cash, hudData.bank, hudData.black = cash, bank, black
        if hudConfig.showMoney then
            SendNUIMessage({ type = 'updateMoney', cash = cash, bank = bank, black = black })
        end
    end

    if hudConfig.enableJobUpdates and data.job then
        hudData.job = data.job
        if hudConfig.showJob then
            SendNUIMessage({ type = 'updateJob', job = data.job })
        end
    end
end

-- natives cache
local PlayerPedId = PlayerPedId
local GetEntityHealth = GetEntityHealth
local GetPedArmour = GetPedArmour
local GetPlayerStamina = GetPlayerStamina
local GetPlayerSprintStaminaRemaining = GetPlayerSprintStaminaRemaining
local GetPlayerUnderwaterTimeRemaining = GetPlayerUnderwaterTimeRemaining
local IsPedSwimmingUnderWater = IsPedSwimmingUnderWater
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetEntitySpeed = GetEntitySpeed
local GetVehicleFuelLevel = GetVehicleFuelLevel
local GetIsVehicleEngineRunning = GetIsVehicleEngineRunning
local GetVehicleLightsState = GetVehicleLightsState
local SendNUIMessage = SendNUIMessage
local Wait = Wait
local PlayerId = PlayerId
local GetResourceState = GetResourceState
local GetNumResources = GetNumResources
local GetResourceByFindIndex = GetResourceByFindIndex
local GetGameTimer = GetGameTimer
local GetActiveScreenResolution = GetActiveScreenResolution
local GetSafeZoneSize = GetSafeZoneSize

local useESXStatus = false

-- ============================
--   CONTROL DEL RADAR (/mapa)
-- ============================
-- Modos: 'auto' (por defecto: en auto se muestra, a pie oculto),
--        'force_on' (forzar siempre visible),
--        'force_off' (forzar siempre oculto)
local radarMode = 'auto'

local function applyRadarMode()
    if radarMode == 'force_on' then
        DisplayRadar(true)
    elseif radarMode == 'force_off' then
        DisplayRadar(false)
    else
        DisplayRadar(hudData.inVehicle)
    end
    SetRadarBigmapEnabled(false, false)
end

local function isMinimapVisible()
    if radarMode == 'force_on' then return true end
    if radarMode == 'force_off' then return false end
    return hudData.inVehicle
end

local function updateMinimapOffset()
    SendNUIMessage({ type = 'setMinimapVisible', visible = isMinimapVisible() })
end

-- ============================
--   LAYOUT DEL HUD (offset/escala)
-- ============================
local lastLayout = { w = 0, h = 0, safe = 0.0 }

local function getKvpNumber(key)
    local s = GetResourceKvpString(key)
    if s ~= nil then
        local n = tonumber(s)
        if n then return n end
    end
    return nil
end

local function setKvpNumber(key, val)
    SetResourceKvp(key, tostring(val))
end

local function computeAndApplyHudLayout(force)
    local w, h = GetActiveScreenResolution()
    if not w or not h or w <= 0 or h <= 0 then return end
    local safe = GetSafeZoneSize() or 1.0

    if not force and lastLayout.w == w and lastLayout.h == h and math.abs((lastLayout.safe or 0) - safe) < 0.0005 then
        return
    end

    local aspect = w / h
    -- Factor base por aspecto (mejor para 16:10 y 4:3)
        local baseFrac
        if aspect >= 1.77 then         -- 16:9
            baseFrac = 0.185
        elseif aspect >= 1.6 then      -- 16:10
            baseFrac = 0.205
        elseif aspect >= 1.5 then      -- 3:2 aprox
            baseFrac = 0.220
        elseif aspect >= 1.34 then     -- 4:3
            baseFrac = 0.240
        else                            -- 5:4 y más estrechos
            baseFrac = 0.260
        end

        -- Base offset en píxeles según ancho
        local offset = math.floor(w * baseFrac)
        -- Ajuste por safezone (más margen => más desplazamiento)
        local extra = (1.0 - safe) * w * 0.08
        offset = offset + math.floor(extra)
        -- Margen fijo
        offset = offset + 12

    -- Límites por ancho; acercar más en resoluciones bajas
        local minOffset = math.max(200, math.floor(w * ((w <= 1280 or h <= 720) and 0.15 or 0.16)))
        local maxOffset = math.min(math.floor(w * 0.28), 680)
    if w <= 1024 or h <= 600 then
        minOffset = math.max(minOffset, math.floor(w * 0.14))
    end
    offset = math.max(minOffset, math.min(maxOffset, math.floor(offset)))

    -- Ajuste contextual: si el minimapa está visible, acercar más en anchos pequeños
        if isMinimapVisible() then
            if w <= 1024 then
                offset = math.max(minOffset, offset - math.floor(w * 0.020))
            elseif w <= 1280 then
                offset = math.max(minOffset, offset - math.floor(w * 0.015))
            elseif w <= 1600 then
                offset = math.max(minOffset, offset - math.floor(w * 0.010))
            end
        end

    -- Escala sugerida
    local scale = 1.12
    if aspect < 1.6 then scale = 1.08 end
    if aspect < 1.4 then scale = 1.02 end
    if h <= 900 then scale = math.min(scale, 1.10) end
    if h <= 720 then scale = math.min(scale, 1.03) end
    if h <= 600 then scale = math.min(scale, 0.98) end

    -- Overrides de usuario desde KVP
    local userOffset = getKvpNumber('munlay_hud_offset_px')
    local userScale = getKvpNumber('munlay_hud_scale')
    if userOffset ~= nil and userOffset ~= 0 then offset = math.floor(userOffset) end
    if userScale ~= nil and userScale ~= 0 then scale = tonumber(string.format('%.3f', userScale)) end

    SendNUIMessage({ type = 'setHudLayout', offsetPx = offset, scale = scale })
    lastLayout.w, lastLayout.h, lastLayout.safe = w, h, safe
end

-- Hilo para detectar cambios de resolución/safezone
CreateThread(function()
    Wait(1500)
    computeAndApplyHudLayout(true)
    while true do
        Wait(2000)
        computeAndApplyHudLayout(false)
    end
end)

RegisterCommand('hudreset', function()
    DeleteResourceKvp('munlay_hud_offset_px')
    DeleteResourceKvp('munlay_hud_scale')
    computeAndApplyHudLayout(true)
    print("^2[HUD]^7 Layout reseteado a valores por defecto")
end, false)

-- Normalizador 0..100 (evita 99 fantasma)
local function norm100(v)
    if v == nil then return 0 end
    v = math.max(0.0, math.min(100.0, v + 0.0))
    if v >= 99.0 then return 100 end
    return math.floor(v + 0.5)
end

-- ============================
--   TICK PRINCIPAL (solo lectura)
-- ============================
CreateThread(function()
    Wait(500)

    hudData.playerId = GetPlayerServerId(PlayerId())

    SendNUIMessage({ type = 'showHUD', show = true })
    
    -- IMPORTANTE: Aplicar configuración inicial ANTES de enviar datos
    Wait(50)
    SendNUIMessage({ type = 'toggleMoneyHUD', show = hudConfig.showMoney })
    
    Wait(50)
    SendNUIMessage({ type = 'updateHUD', playerId = hudData.playerId })
    
    -- Si el trabajo está deshabilitado desde el inicio, ocultarlo
    if not hudConfig.showJob then
        SendNUIMessage({ type = 'updateJob', job = { name="unemployed", label="", grade=0, grade_label="" } })
    end

    local ped, vehicle
    local lastVehicle = 0
    local lastHealth = -1
    local lastArmor = -1
    local lastStamina = -1

    local lastHungerSent = -1
    local lastThirstSent = -1
    local lastOxygenSent = -1
    local lastShowOxygen = false

    local healthBuffer = {}
    local bufferSize = 3

    local lastForceTick = GetGameTimer()
    local forceTickMs = 4000

    while true do
        Wait(200)

        ped = PlayerPedId()

        -- VIDA (promedio para suavizar)
        local currentHealth = GetEntityHealth(ped)
        local health = 0
        if currentHealth <= 100 then
            health = 0
        else
            currentHealth = math.max(100, math.min(200, currentHealth))
            health = ((currentHealth - 100) / 100) * 100
        end
        health = math.max(0, math.min(100, health))
        table.insert(healthBuffer, health)
        if #healthBuffer > bufferSize then table.remove(healthBuffer, 1) end
        local sum = 0
        for _, v in ipairs(healthBuffer) do sum = sum + v end
        local healthInt = norm100(sum / #healthBuffer)

        -- ARMADURA
        local armorInt = norm100(GetPedArmour(ped))

        -- STAMINA
        local stamina = 100
        local st = GetPlayerStamina(PlayerId())
        if st then
            stamina = st
        else
            local sprint = GetPlayerSprintStaminaRemaining(PlayerId())
            if sprint then
                if sprint <= 10 then stamina = sprint * 10 else stamina = sprint end
            end
        end
        local staminaInt = norm100(stamina)

        -- OXÍGENO
        local isUnderwater = IsPedSwimmingUnderWater(ped)
        local oxygen = 100
        if isUnderwater then
            local uw = GetPlayerUnderwaterTimeRemaining(PlayerId()) or 10.0
            oxygen = math.max(0.0, math.min(10.0, uw)) * 10.0
        end
        local oxygenInt = norm100(oxygen)

        -- HAMBRE/SED: si no hay esx_status, simular
        if not useESXStatus then
            hudData.lastHunger = math.max(0, hudData.lastHunger - 0.025)
            hudData.lastThirst = math.max(0, hudData.lastThirst - 0.035)
        end
        local hungerInt = norm100(hudData.lastHunger)
        local thirstInt = norm100(hudData.lastThirst)

        -- Vehículo (solo lectura)
        vehicle = GetVehiclePedIsIn(ped, false)
        local newInVehicle = vehicle ~= 0
        if newInVehicle ~= hudData.inVehicle then
            hudData.inVehicle = newInVehicle
            applyRadarMode()
            SendNUIMessage({ type = 'updateHUD', inVehicle = newInVehicle })
            SendNUIMessage({ type = 'updateVehicle', inVehicle = newInVehicle })
            updateMinimapOffset()
            if computeAndApplyHudLayout then computeAndApplyHudLayout(true) end
        end

        -- Detectar si debemos enviar actualización
        local vitalChanged =
            (lastHungerSent == -1 or math.abs(hungerInt - lastHungerSent) >= 1) or
            (lastThirstSent == -1 or math.abs(thirstInt - lastThirstSent) >= 1) or
            (lastOxygenSent == -1 or math.abs(oxygenInt - lastOxygenSent) >= 1) or
            (lastShowOxygen ~= isUnderwater)

        if math.abs(healthInt - lastHealth) > 1
           or armorInt ~= lastArmor
           or math.abs(staminaInt - lastStamina) > 2
           or vitalChanged
        then
            lastHealth = healthInt
            lastArmor = armorInt
            lastStamina = staminaInt
            lastHungerSent = hungerInt
            lastThirstSent = thirstInt
            lastOxygenSent = oxygenInt
            lastShowOxygen = isUnderwater

            SendNUIMessage({
                type = 'updateHUD',
                health = healthInt,
                armor = armorInt,
                stamina = staminaInt,
                hunger = hungerInt,
                thirst = thirstInt,
                oxygen = oxygenInt,
                showOxygen = isUnderwater,
                talking = hudData.isTalking,      -- Solo visual
                voiceRange = hudData.voiceRange,  -- Solo visual
                inVehicle = newInVehicle,
                playerId = hudData.playerId
            })
        end

        -- Tick de respaldo
        if GetGameTimer() - lastForceTick > forceTickMs then
            lastForceTick = GetGameTimer()
            SendNUIMessage({
                type = 'updateHUD',
                hunger = hungerInt,
                thirst = thirstInt,
                oxygen = oxygenInt,
                showOxygen = isUnderwater
            })
        end

        -- Al salir del vehículo, limpiar velocímetro
        if vehicle == 0 and lastVehicle ~= 0 then
            lastVehicle = 0
            SendNUIMessage({ type = 'updateVehicle', inVehicle = false })
        elseif vehicle ~= 0 and vehicle ~= lastVehicle then
            lastVehicle = vehicle
        end
    end
end)

CreateThread(function()
    local lastTalking = false
    while true do
        Wait(100) -- 10 veces por segundo, suave
        local talking = NetworkIsPlayerTalking(PlayerId())
        if talking ~= lastTalking then
            lastTalking = talking
            hudData.isTalking = talking
            SendNUIMessage({ type = 'setTalking', talking = talking })
        end
    end
end)

-- === VOICE RANGE desde pma-voice (fallback: 2) ===
CreateThread(function()
    local lastRange = hudData.voiceRange or 2
    while true do
        Wait(400)

        -- pma-voice expone el estado en LocalPlayer.state.proximity
        local prox = (LocalPlayer and LocalPlayer.state and LocalPlayer.state.proximity) or nil
        local newRange = lastRange

        if prox then
            -- pma-voice suele usar mode = 1/2/3 o 'whisper'/'normal'/'shout'
            local m = prox.mode
            if m == 1 or m == 'whisper' then
                newRange = 1
            elseif m == 3 or m == 'shout' then
                newRange = 3
            else
                newRange = 2
            end
        else
            -- Si no hay pma-voice u otro framework, deja 2 (Normal)
            newRange = 2
        end

        if newRange ~= lastRange then
            lastRange = newRange
            hudData.voiceRange = newRange
            SendNUIMessage({ type = 'setVoiceRange', range = newRange })
        end
    end
end)

-- ============================
--   VEHÍCULO (tick rápido, solo lectura)
-- ============================
CreateThread(function()
    while true do
        Wait(90)
        if hudData.inVehicle then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 then
                local speed = math.floor(GetEntitySpeed(vehicle) * 3.6)
                local fuel = math.floor(GetVehicleFuelLevel(vehicle))
                local engineOn = GetIsVehicleEngineRunning(vehicle)

                -- Leer estado de luces directamente del vehículo (sistema nativo)
                local lightsOn, highBeams = GetVehicleLightsState(vehicle)
                local lightsState = 0 -- 0 = apagadas
                if lightsOn == 1 then
                    lightsState = highBeams == 1 and 2 or 1 -- 2 = altas, 1 = bajas
                end

                SendNUIMessage({
                    type = 'updateVehicle',
                    inVehicle = true,
                    speed = speed,
                    fuel = fuel,
                    engineOn = engineOn,
                    lights = lightsState, -- Usar estado leído directamente
                    seatbelt = hudData.seatbelt -- solo visual
                })
            end
        else
            Wait(140)
        end
    end
end)

-- ============================
--   SOLO LECTURA DE UI
-- ============================

-- Funciones de visibilidad (necesarias antes de los comandos)
local function updateMoneyVisibility()
    if hudConfig.showMoney and hudConfig.enableMoneyUpdates then
        SendNUIMessage({ type = 'toggleMoneyOnly', show = true })
        SendNUIMessage({ type = 'updateMoney', cash = hudData.cash, bank = hudData.bank, black = hudData.black })
    else
        SendNUIMessage({ type = 'toggleMoneyOnly', show = false })
    end
end

local function updateJobVisibility()
    if hudConfig.showJob and hudConfig.enableJobUpdates and hudData.job then
        SendNUIMessage({ type = 'toggleJobOnly', show = true })
        SendNUIMessage({ type = 'updateJob', job = hudData.job })
    else
        SendNUIMessage({ type = 'toggleJobOnly', show = false })
    end
end

-- Mostrar/ocultar panel de dinero y trabajo
RegisterCommand('hud', function()
    hudData.moneyHudVisible = not hudData.moneyHudVisible
    hudConfig.showMoney = hudData.moneyHudVisible
    hudConfig.showJob = hudData.moneyHudVisible
    hudConfig.enableMoneyUpdates = hudData.moneyHudVisible
    hudConfig.enableJobUpdates = hudData.moneyHudVisible
    -- Refresco inmediato al activar para que no muestre $0
    if hudData.moneyHudVisible then
        forceRefreshHudData()
    end
    updateMoneyVisibility()
    updateJobVisibility()
end, false)

-- Eventos propios del HUD (si tu server quiere empujar datos)
RegisterNetEvent('hud:updateMoney')
AddEventHandler('hud:updateMoney', function(cash, bank, black)
    -- Solo procesar si las actualizaciones de dinero están habilitadas
    if not hudConfig.enableMoneyUpdates then return end
    
    hudData.cash = cash or 0
    hudData.bank = bank or 0
    hudData.black = black or 0
    
    -- Solo enviar a NUI si el HUD de dinero está visible
    if hudConfig.showMoney then
        SendNUIMessage({ type = 'updateMoney', cash = hudData.cash, bank = hudData.bank, black = hudData.black })
    end
end)

RegisterNetEvent('hud:updateJob')
AddEventHandler('hud:updateJob', function(job)
    -- Solo procesar si las actualizaciones de trabajo están habilitadas
    if not hudConfig.enableJobUpdates then return end
    
    hudData.job = job
    
    -- Solo enviar a NUI si el HUD de trabajo está visible
    if hudConfig.showJob then
        SendNUIMessage({ type = 'updateJob', job = hudData.job })
    end
end)

-- Controlar solo el radar desde este recurso (otro script maneja el HUD nativo)
CreateThread(function()
    while true do
        Wait(0)
        if radarMode == 'force_on' then
            DisplayRadar(true)
        elseif radarMode == 'force_off' then
            DisplayRadar(false)
        else
            DisplayRadar(hudData.inVehicle)
        end
    end
end)

-- ============================
--   OCULTAR BARRAS NATIVAS MINIMAPA (scaleform)
-- ============================
-- Mantiene el radar intacto. Reaplica cada frame para evitar que reaparezcan tras respawn/pausa.
CreateThread(function()
    local minimap = RequestScaleformMovie("minimap")
    -- Esperar a que cargue el scaleform
    while not HasScaleformMovieLoaded(minimap) do
        Wait(0)
    end

    -- Refrescar el minimapa una vez para garantizar el estado correcto
    SetRadarBigmapEnabled(true, false)
    Wait(0)
    SetRadarBigmapEnabled(false, false)

    while true do
        Wait(0)

        -- Si por algún motivo se descarga el scaleform, volver a pedirlo y refrescar
        if not HasScaleformMovieLoaded(minimap) then
            minimap = RequestScaleformMovie("minimap")
            while not HasScaleformMovieLoaded(minimap) do
                Wait(0)
            end
            SetRadarBigmapEnabled(true, false)
            Wait(0)
            SetRadarBigmapEnabled(false, false)
        end

        -- Forzar estilo "golf" (sin barras de vida/armadura junto al minimapa)
        BeginScaleformMovieMethod(minimap, "SETUP_HEALTH_ARMOUR")
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
    end
end)

-- Init básico (solo UI)
CreateThread(function()
    Wait(800)
    applyRadarMode()
    updateMinimapOffset()
    Wait(1200)
    if not ESX then
        -- Solo enviar si las actualizaciones están habilitadas
        if hudConfig.enableMoneyUpdates and hudConfig.showMoney then
            SendNUIMessage({ type = 'updateMoney', cash = 0, bank = 0, black = 0 })
        end
        if hudConfig.enableJobUpdates and hudConfig.showJob then
            SendNUIMessage({ type = 'updateJob', job = { name="unemployed", label="Desempleado", grade=0, grade_label="Sin trabajo" } })
        end
    end
end)

-- ============================
--   ESX core (solo lectura + polling adaptativo)
-- ============================
CreateThread(function()
    -- Obtener ESX por distintos métodos
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        if ESX == nil then
            local ok, res = pcall(function() return exports['es_extended']:getSharedObject() end)
            if ok then ESX = res end
        end
        if ESX == nil and _G.ESX then ESX = _G.ESX end
        Wait(10)
    end

    if ESX.GetPlayerData then
        PlayerData = ESX.GetPlayerData()
    end

    -- extractAccounts está definida a nivel module

    -- Estado previo para detectar cambios
    local lastCash, lastBank, lastBlack = -1, -1, -1
    local lastJobName, lastJobGrade, lastJobLabel, lastJobGradeLabel = nil, nil, nil, nil

    -- Ventana de “actividad reciente” para usar fast poll
    local fastUntil = 0
    local function bumpFast()
        fastUntil = GetGameTimer() + 5000 -- 5s de pooling rápido tras detectar cambio
    end

    -- Refresco inmediato seguro
    local function refreshOnce()
        if not ESX or not ESX.GetPlayerData then return end
        local data = ESX.GetPlayerData()
        if not data then return end

        -- Dinero (solo procesar si está habilitado)
        if hudConfig.enableMoneyUpdates then
            local cash, bank, black = extractAccounts(data.accounts)
            if cash ~= lastCash or bank ~= lastBank or black ~= lastBlack then
                lastCash, lastBank, lastBlack = cash, bank, black
                hudData.cash, hudData.bank, hudData.black = cash, bank, black
                
                -- Solo enviar actualización si el dinero está visible
                if hudConfig.showMoney then
                    SendNUIMessage({ type = 'updateMoney', cash = cash, bank = bank, black = black })
                end
                bumpFast()
            end
        end

        -- Trabajo (solo procesar si está habilitado)
        if hudConfig.enableJobUpdates and data.job then
            local jn = data.job.name
            local jg = data.job.grade
            local jl = data.job.label or data.job.name
            local jgl = data.job.grade_label or (data.job.grade and ("Rango "..tostring(data.job.grade)) or "Sin rango")
            if jn ~= lastJobName or jg ~= lastJobGrade or jl ~= lastJobLabel or jgl ~= lastJobGradeLabel then
                lastJobName, lastJobGrade, lastJobLabel, lastJobGradeLabel = jn, jg, jl, jgl
                hudData.job = data.job
                
                -- Solo enviar actualización si el trabajo está visible
                if hudConfig.showJob then
                    SendNUIMessage({ type = 'updateJob', job = data.job })
                end
                bumpFast()
            end
        end
    end

    -- Escuchas seguras para refresco inmediato
    AddEventHandler('esx:playerLoaded', function()
        Wait(200)
        refreshOnce()
    end)

    AddEventHandler('esx:onPlayerSpawn', function()
        Wait(300)
        refreshOnce()
    end)

    -- Polling adaptativo
    while true do
        local now = GetGameTimer()
        -- Si tanto dinero como trabajo están desactivados, usar interval más largo
        local bothDisabled = not hudConfig.enableMoneyUpdates and not hudConfig.enableJobUpdates
        local interval = bothDisabled and 3000 or ((now < fastUntil) and 250 or 1200)
        Wait(interval)
        
        -- Solo ejecutar refreshOnce si al menos uno está habilitado
        if hudConfig.enableMoneyUpdates or hudConfig.enableJobUpdates then
            refreshOnce()
        end
    end
end)

-- ============================
--   EXPORTS para otros recursos
-- ============================

-- Export original para compatibilidad hacia atrás
exports('SeatbeltState', function(state)
    hudData.seatbelt = state
    if hudData.inVehicle then
        SendNUIMessage({
            type = 'updateVehicle',
            seatbelt = state
        })
    end
end)

-- Export para esx_cruisecontrol (control de crucero)
exports('CruiseControlState', function(state)
    -- Si quieres mostrar el estado del cruise control en tu HUD
    SendNUIMessage({
        type = 'updateVehicle',
        cruiseControl = state
    })
end)

-- ============================
--   esx_status (solo lectura)
-- ============================
CreateThread(function()
    -- Detectar nombre real del recurso esx_status (por si está renombrado)
    local function findEsxStatusResource()
        local fallback = 'esx_status'
        local count = (GetNumResources and GetNumResources()) or 0
        for i = 0, count - 1 do
            local res = GetResourceByFindIndex(i)
            if res and string.find(res, 'esx_status', 1, true) then
                return res
            end
        end
        return fallback
    end

    local esxStatusRes = findEsxStatusResource()

    -- Esperar a que el recurso exista y arranque (máx 10s)
    local esxStatusWait = 0
    while (GetResourceState(esxStatusRes) == 'missing' or GetResourceState(esxStatusRes) == 'stopped') and esxStatusWait < 20 do
        Wait(500)
        esxStatusWait = esxStatusWait + 1
    end

    if GetResourceState(esxStatusRes) == 'started' then
        useESXStatus = true
        print("^2[HUD]^7 esx_status detectado")

        -- Utilidad: obtener % de distintos formatos de esx_status
        local function statusPercent(s)
            if not s then return nil end
            -- Propiedad directa en algunos forks
            if type(s.percent) == 'number' then return s.percent end
            -- Método getPercent en la mayoría de versiones
            if type(s.getPercent) == 'function' then
                local ok, p = pcall(s.getPercent, s)
                if ok and type(p) == 'number' then return p end
            end
            -- Cálculo manual por val/max si existen
            if type(s.val) == 'number' and type(s.max) == 'number' and s.max > 0 then
                return (s.val / s.max) * 100.0
            end
            return nil
        end

        local lastStatusTick = 0

        -- Función para actualizar los valores y enviar a NUI
        local function updateStatusValues(hunger, thirst)
            local changed = false
            if hunger ~= nil and hunger ~= hudData.lastHunger then 
                hudData.lastHunger = hunger
                changed = true
            end
            if thirst ~= nil and thirst ~= hudData.lastThirst then 
                hudData.lastThirst = thirst
                changed = true
            end
            
            if changed then
                SendNUIMessage({
                    type = 'updateHUD',
                    hunger = norm100(hudData.lastHunger),
                    thirst = norm100(hudData.lastThirst)
                })
                lastStatusTick = GetGameTimer()
            end
        end

        -- Función para refrescar status manualmente
        refreshStatusesOnce = function()
            local h, t
            TriggerEvent('esx_status:getStatus', 'hunger', function(s)
                h = statusPercent(s)
            end)
            TriggerEvent('esx_status:getStatus', 'food', function(s)
                local p = statusPercent(s)
                if p ~= nil then h = p end
            end)
            TriggerEvent('esx_status:getStatus', 'thirst', function(s)
                t = statusPercent(s)
            end)
            Wait(60)
            updateStatusValues(h, t)
        end

    RegisterNetEvent('esx_status:onTick')
        AddEventHandler('esx_status:onTick', function(status)
            local hunger, thirst
            if type(status) == 'table' then
                -- Intentar como array numérico primero
                if #status > 0 then
                    for i=1, #status do
                        local st = status[i]
                        if st and (st.name == 'hunger' or st.name == 'food') then
                            hunger = statusPercent(st)
                        elseif st and st.name == 'thirst' then
                            thirst = statusPercent(st)
                        end
                    end
                else
                    -- Fallback: mapa por nombre
                    for _, st in pairs(status) do
                        if st and (st.name == 'hunger' or st.name == 'food') then
                            hunger = statusPercent(st)
                        elseif st and st.name == 'thirst' then
                            thirst = statusPercent(st)
                        end
                    end
                end
            end
            updateStatusValues(hunger, thirst)
        end)

        -- Algunos forks emiten un evento 'loaded' con los estados actuales
        RegisterNetEvent('esx_status:loaded')
        AddEventHandler('esx_status:loaded', function(status)
            local hunger, thirst
            if type(status) == 'table' then
                if #status > 0 then
                    for i=1, #status do
                        local st = status[i]
                        if st and (st.name == 'hunger' or st.name == 'food') then
                            hunger = statusPercent(st)
                        elseif st and st.name == 'thirst' then
                            thirst = statusPercent(st)
                        end
                    end
                else
                    for _, st in pairs(status) do
                        if st and (st.name == 'hunger' or st.name == 'food') then
                            hunger = statusPercent(st)
                        elseif st and st.name == 'thirst' then
                            thirst = statusPercent(st)
                        end
                    end
                end
            end
            updateStatusValues(hunger, thirst)
        end)

        RegisterNetEvent('esx_status:add')
        AddEventHandler('esx_status:add', function(name, amount)
            if name == 'hunger' or name == 'food' or name == 'thirst' then
                Wait(100)
                refreshStatusesOnce()
            end
        end)

        RegisterNetEvent('esx_status:remove')
        AddEventHandler('esx_status:remove', function(name, amount)
            if name == 'hunger' or name == 'food' or name == 'thirst' then
                Wait(100)
                refreshStatusesOnce()
            end
        end)

        -- Inicial (si el recurso lo permite)
        TriggerEvent('esx_status:getStatus', 'hunger', function(s)
            local p = statusPercent(s)
            if p ~= nil then hudData.lastHunger = p end
        end)
        -- Intentar también 'food' en forks
        TriggerEvent('esx_status:getStatus', 'food', function(s)
            local p = statusPercent(s)
            if p ~= nil then hudData.lastHunger = p end
        end)
        TriggerEvent('esx_status:getStatus', 'thirst', function(s)
            local p = statusPercent(s)
            if p ~= nil then hudData.lastThirst = p end
        end)
        
        Wait(500)
        
        -- Si no hay valores válidos, inicializar en valores realistas
        if hudData.lastHunger >= 99 and hudData.lastThirst >= 99 then
            hudData.lastHunger = 75
            hudData.lastThirst = 80
        end
        
        -- Enviar valores iniciales
        SendNUIMessage({
            type = 'updateHUD',
            hunger = norm100(hudData.lastHunger),
            thirst = norm100(hudData.lastThirst)
        })

        -- Eventos para ox_inventory que modifica esx_status directamente
        RegisterNetEvent('ox_inventory:itemUsed')
        AddEventHandler('ox_inventory:itemUsed', function(item, data)
            Wait(1000)
            refreshStatusesOnce()
        end)

        -- Eventos directos de esx_status cuando ox_inventory los modifica
        RegisterNetEvent('esx_status:set')
        AddEventHandler('esx_status:set', function(name, value)
            if name == 'hunger' or name == 'food' or name == 'thirst' then
                Wait(100)
                refreshStatusesOnce()
            end
        end)

        -- Hook para cuando ox_inventory actualiza status
        RegisterNetEvent('esx:onPlayerSpawn')
        AddEventHandler('esx:onPlayerSpawn', function()
            Wait(2000)
            refreshStatusesOnce()
        end)

        -- Listener para cambios en items consumibles
        AddEventHandler('ox_inventory:usedItem', function(name, item)
            local consumables = {
                'bread', 'water', 'sandwich', 'burger', 'cola', 'coffee', 'apple', 'banana'
            }
            
            for _, consumable in ipairs(consumables) do
                if string.find(name, consumable) then
                    Wait(800)
                    refreshStatusesOnce()
                    break
                end
            end
        end)

        -- Fallback: si onTick no llega en >1.5s, preguntar puntualmente los valores
        CreateThread(function()
            while true do
                Wait(1200)
                if GetGameTimer() - lastStatusTick > 1500 then
                    local h, t
                    TriggerEvent('esx_status:getStatus', 'hunger', function(s)
                        h = statusPercent(s)
                    end)
                    TriggerEvent('esx_status:getStatus', 'thirst', function(s)
                        t = statusPercent(s)
                    end)
                    -- pequeña espera para callbacks
                    Wait(50)
                    local changed = false
                    if h ~= nil and h ~= hudData.lastHunger then hudData.lastHunger = h; changed = true end
                    if t ~= nil and t ~= hudData.lastThirst then hudData.lastThirst = t; changed = true end
                    if changed then
                        SendNUIMessage({
                            type = 'updateHUD',
                            hunger = norm100(hudData.lastHunger),
                            thirst = norm100(hudData.lastThirst)
                        })
                    end
                end
            end
        end)
    else
        print("^3[HUD]^7 esx_status no iniciado; se usa simulación lenta.")
    end
end)

-- ============================
--   COMANDOS PARA CONTROLAR VISIBILIDAD
-- ============================



-- Exports para otros recursos
exports('SetMoneyHudVisible', function(visible)
    hudConfig.showMoney = visible
    hudConfig.enableMoneyUpdates = visible
    updateMoneyVisibility()
end)

exports('SetJobHudVisible', function(visible)
    hudConfig.showJob = visible
    hudConfig.enableJobUpdates = visible
    updateJobVisibility()
end)

exports('SetMoneyJobHudVisible', function(visible)
    hudConfig.showMoney = visible
    hudConfig.enableMoneyUpdates = visible
    hudConfig.showJob = visible
    hudConfig.enableJobUpdates = visible
    updateMoneyVisibility()
    updateJobVisibility()
end)

exports('GetHudConfig', function()
    return hudConfig
end)

-- ============================
--   COMANDO /mapa
-- ============================
-- Funcionamiento pedido:
--  - Por defecto (auto): en coche se muestra, a pie se oculta.
--  - Si el usuario pone /mapa a pie: aparece; si vuelve a poner /mapa: se oculta.
--  - Si el usuario pone /mapa en auto: se activa/desactiva.
-- Implementación: alterna entre 'force_on' y 'force_off' cuando el jugador
-- no está en el modo automático. Si está en 'auto', el primer /mapa crea un
-- override basado en el contexto actual (mostrar/ocultar), y el siguiente
-- /mapa invierte ese override. Un tercer /mapa vuelve a 'auto'.

RegisterCommand('mapa', function()
    -- Toggle directo según visibilidad actual: si está visible -> ocultar; si está oculto -> mostrar
    local visible = isMinimapVisible()
    radarMode = visible and 'force_off' or 'force_on'
    applyRadarMode()
    updateMinimapOffset()
    if computeAndApplyHudLayout then computeAndApplyHudLayout(true) end
end, false)
