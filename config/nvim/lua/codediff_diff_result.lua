local M = {}

function M.is_complete(result)
    return type(result) == "table" and type(result.changes) == "table" and type(result.moves) == "table"
end

function M.is_malformed(result)
    return result ~= nil and not M.is_complete(result)
end

function M.normalize(result)
    if result == nil then
        return nil
    end

    if type(result) ~= "table" then
        return {
            changes = {},
            moves = {},
        }
    end

    if type(result.changes) ~= "table" then
        result.changes = {}
    end

    if type(result.moves) ~= "table" then
        result.moves = {}
    end

    return result
end

return M
