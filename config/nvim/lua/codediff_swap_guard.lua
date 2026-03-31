local M = {}

local depth = 0
local previous_swapfile = nil

function M.is_active()
    return depth > 0
end

function M.run(fn)
    if depth == 0 then
        previous_swapfile = vim.o.swapfile
        vim.o.swapfile = false
    end

    depth = depth + 1
    local ok, result = xpcall(fn, debug.traceback)
    depth = math.max(depth - 1, 0)

    if depth == 0 and previous_swapfile ~= nil then
        vim.o.swapfile = previous_swapfile
        previous_swapfile = nil
    end

    return ok, result
end

return M
