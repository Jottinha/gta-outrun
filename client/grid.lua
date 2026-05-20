-- ============================================================
--  OUTRUN — Client: Grid (largada F1)
--
--  Matemática pura: dado um índice e o total de carros, calcula
--  o offset (longitudinal/lateral) relativo ao ponto de pole.
--  Spawn.lua consome esse offset para posicionar cada veículo.
-- ============================================================

Grid = {}


-- Vetores 2D forward e right derivados do heading do node de pista
function Grid.basisFromHeading(heading)
    local rad = math.rad(heading)
    local forwardX, forwardY = math.sin(rad), math.cos(rad)
    local rightX, rightY     = math.cos(rad), -math.sin(rad)
    return forwardX, forwardY, rightX, rightY
end


-- Offset em metros do índice (1-based) em relação à pole.
--   * Posição 1 = pole (lateral negativo, longitudinal 0)
--   * Posição 2 = lado oposto, com stagger longitudinal negativo
--   * Posições seguintes formam novas filas
function Grid.computeOffset(index, totalParticipants)
    local rowSpacing     = Config.Race.GRID_ROW_SPACING
    local columnSpacing  = Config.Race.GRID_COLUMN_SPACING
    local staggerSpacing = Config.Race.GRID_STAGGER_SPACING

    if totalParticipants <= 1 then
        return { longitudinal = 0.0, lateral = 0.0 }
    end

    local zeroBased     = index - 1
    local columnIndex   = zeroBased % 2
    local rowIndex      = math.floor(zeroBased / 2)
    local laneSign      = (columnIndex == 0) and -1.0 or 1.0
    local staggerOffset = (columnIndex == 0) and 0.0 or staggerSpacing

    return {
        longitudinal = -((rowIndex * rowSpacing) + staggerOffset),
        lateral      = laneSign * (columnSpacing * 0.5),
    }
end
