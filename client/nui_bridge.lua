-- ============================================================
--  OUTRUN — Client: NUI Bridge
--
--  Centraliza SendNUIMessage e SetNuiFocus. Centraliza também
--  o registro de NUI callbacks usados pelo lobby.
-- ============================================================

Nui = {}


function Nui.send(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

function Nui.setFocus(active)
    SetNuiFocus(active == true, active == true)
end


-- ============================================================
-- Callbacks da UI (lobby + ajustes)
--
-- Os callbacks delegam para `Lobby.*`, que vive em main.lua
-- como ponto de saída da UI. Mantemos os callbacks aqui para
-- não espalhar `RegisterNUICallback` pelo projeto.
-- ============================================================

Lobby = Lobby or {}

local function nuiCallback(name, fn)
    RegisterNUICallback(name, function(data, cb)
        local ok, err = pcall(fn, data or {})
        if not ok then Logger.warn("NUI", ("callback %s falhou: %s"):format(name, err)) end
        cb({ ok = ok })
    end)
end

function Nui.registerCallbacks()
    -- Main menu / navegação
    nuiCallback('openCreate',    function(data) Lobby.create(data)         end)
    nuiCallback('refreshRooms',  function()     Lobby.refreshRooms()       end)
    nuiCallback('joinRoom',      function(data) Lobby.joinRoom(data)       end)
    nuiCallback('leaveLobby',    function()     Lobby.leave()              end)
    nuiCallback('resetRace',     function()     Lobby.resetRace()          end)
    nuiCallback('closeMenu',     function()     Lobby.closeMenu()          end)

    -- Lobby (configuração de corrida)
    nuiCallback('addNPC',        function(data) Lobby.addNPC(data)         end)
    nuiCallback('setMyCar',      function(data) Lobby.setMyCar(data)       end)
    nuiCallback('toggleReady',   function()     Lobby.toggleReady()        end)
    nuiCallback('startRace',     function()     Lobby.startRace()          end)
    nuiCallback('setTraffic',    function(data) Lobby.setTraffic(data)     end)

    -- Vehicle preview 3D
    nuiCallback('previewVehicle', function(data) Lobby.previewVehicle(data) end)
    nuiCallback('destroyPreview', function()     Lobby.destroyPreview()     end)

    -- Aliases legados (compat com versões anteriores da NUI; podem ser
    -- removidos depois que estabilizar)
    nuiCallback('createLobby',   function(data) Lobby.create(data)         end)
    nuiCallback('closeLobby',    function()     Lobby.closeMenu()          end)
end
