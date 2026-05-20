-- ============================================================
--  OUTRUN — Logger central (shared)
--  Usado em todos os arquivos do recurso. Nunca usar print direto.
-- ============================================================

Logger = {}

local function emit(level, scope, msg)
    local prefix = Config.Debug.LOG_PREFIX or "[OUTRUN]"
    local scopeTag = scope and ("[" .. tostring(scope) .. "]") or ""
    print(("%s [%s]%s %s"):format(prefix, level, scopeTag, tostring(msg)))
end

function Logger.debug(scope, msg)
    if not Config.Debug.ENABLED then return end
    emit("DBG", scope, msg)
end

function Logger.info(scope, msg)
    emit("INF", scope, msg)
end

function Logger.warn(scope, msg)
    emit("WRN", scope, msg)
end

function Logger.error(scope, msg)
    emit("ERR", scope, msg)
end
