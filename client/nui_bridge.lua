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
    nuiCallback('createLobby',  function(data) Lobby.create(data)        end)
    nuiCallback('addNPC',       function(data) Lobby.addNPC(data)        end)
    nuiCallback('setMyCar',     function(data) Lobby.setMyCar(data)      end)
    nuiCallback('toggleReady',  function()     Lobby.toggleReady()       end)
    nuiCallback('startRace',    function()     Lobby.startRace()         end)
    nuiCallback('closeLobby',   function()     Lobby.close()             end)
    nuiCallback('setTraffic',   function(data) Lobby.setTraffic(data)    end)
end
