-- ============================================================
--  OUTRUN — Client: Vehicle Preview (showroom 3D)
--
--  Spawna um veículo temporário + câmera dedicada para
--  preview durante a seleção no lobby. Totalmente isolado
--  do veículo real da corrida.
-- ============================================================

VehiclePreview = {}

local previewVeh    = nil
local previewCam    = nil
local previewCenter = nil
local rotAngle      = 0.0
local rotThread     = false
local playerWasVisible = true


local function loadModelHash(hash)
    if HasModelLoaded(hash) then return true end
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local elapsed = 0
    while not HasModelLoaded(hash) and elapsed < 5000 do
        Citizen.Wait(50)
        elapsed = elapsed + 50
    end
    return HasModelLoaded(hash)
end


local function destroyPreviewVehicle()
    if previewVeh and DoesEntityExist(previewVeh) then
        SetEntityAsMissionEntity(previewVeh, true, true)
        DeleteVehicle(previewVeh)
    end
    previewVeh = nil
end


local function destroyPreviewCam()
    if previewCam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
end


local function stopRotationThread()
    rotThread = false
end


local function computePreviewPosition()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local cfg = Config.Preview
    return vector3(pos.x + cfg.OFFSET.x, pos.y + cfg.OFFSET.y, pos.z + cfg.OFFSET.z)
end


local function spawnPreviewVehicle(model)
    local hash = GetHashKey(model)
    if not loadModelHash(hash) then
        hash = GetHashKey(Config.Vehicles.DEFAULT)
        loadModelHash(hash)
    end

    if not previewCenter then
        previewCenter = computePreviewPosition()
    end
    local veh = CreateVehicle(hash, previewCenter.x, previewCenter.y, previewCenter.z, 0.0, false, false)

    SetEntityAsMissionEntity(veh, true, true)
    FreezeEntityPosition(veh, true)
    SetEntityCollision(veh, false, false)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleOnGroundProperly(veh)
    SetEntityAlpha(veh, 255, false)
    SetVehicleDirtLevel(veh, 0.0)

    SetModelAsNoLongerNeeded(hash)
    previewVeh = veh
    return veh
end


local function setupCamera()
    if previewCam then destroyPreviewCam() end
    if not previewCenter then return end

    local cfg = Config.Preview
    local camPos = vector3(
        previewCenter.x - cfg.CAM_BACK_OFFSET,
        previewCenter.y - cfg.CAM_BACK_OFFSET,
        previewCenter.z + cfg.CAM_HEIGHT_OFFSET
    )

    previewCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(previewCam, camPos.x, camPos.y, camPos.z)
    PointCamAtCoord(previewCam, previewCenter.x, previewCenter.y, previewCenter.z + 0.3)
    SetCamFov(previewCam, 40.0)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, true, 500, true, true)
end


local function startRotationThread()
    if rotThread then return end
    rotThread = true
    rotAngle = 0.0

    Citizen.CreateThread(function()
        while rotThread do
            if previewVeh and DoesEntityExist(previewVeh) then
                rotAngle = rotAngle + Config.Preview.ROTATION_SPEED
                if rotAngle >= 360.0 then rotAngle = rotAngle - 360.0 end
                SetEntityHeading(previewVeh, rotAngle)
            end
            Citizen.Wait(16)
        end
    end)
end


function VehiclePreview.show(model)
    destroyPreviewVehicle()

    local ped = PlayerPedId()
    playerWasVisible = IsEntityVisible(ped)
    SetEntityVisible(ped, false, false)

    spawnPreviewVehicle(model)
    setupCamera()
    startRotationThread()
end


function VehiclePreview.switchModel(model)
    if not previewCam then
        VehiclePreview.show(model)
        return
    end

    destroyPreviewVehicle()
    spawnPreviewVehicle(model)
    startRotationThread()
end


function VehiclePreview.destroy()
    stopRotationThread()
    destroyPreviewVehicle()
    destroyPreviewCam()

    SetEntityVisible(PlayerPedId(), true, false)
    playerWasVisible = true
    previewCenter = nil
    rotAngle = 0.0
end


function VehiclePreview.isActive()
    return previewVeh ~= nil and DoesEntityExist(previewVeh)
end
