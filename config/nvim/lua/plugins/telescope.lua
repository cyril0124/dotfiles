return {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {
        'nvim-lua/plenary.nvim',
        {
            -- To enable fzf style searching
            'nvim-telescope/telescope-fzf-native.nvim',
            build = 'make'
        },
        'jonarrien/telescope-cmdline.nvim',
    },
    keys = {
        { '<leader><leader>', '<cmd>Telescope cmdline<cr>', desc = 'Cmdline' }
    },
    config = function()
        local function attach_find_files_mappings(prompt_bufnr)
            local actions = require("telescope.actions")
            local action_set = require("telescope.actions.set")
            local action_state = require("telescope.actions.state")

            local function select(kind)
                return function()
                    local codediff = require("lua.codediff")
                    if not codediff.is_current_session() then
                        return action_set.select(prompt_bufnr, kind)
                    end

                    local selection = action_state.get_selected_entry()
                    local path = selection and (selection.path or selection.filename or selection.value) or nil
                    if type(path) ~= "string" or path == "" then
                        return
                    end

                    local picker = action_state.get_current_picker(prompt_bufnr)
                    if picker and picker.cwd and path:sub(1, 1) ~= "/" then
                        path = picker.cwd .. "/" .. path
                    end

                    actions.close(prompt_bufnr)
                    codediff.run_outside_current_session(function()
                        vim.cmd(action_state.select_key_to_edit_key(kind) .. " " .. vim.fn.fnameescape(vim.fn.fnamemodify(path, ":p")))
                    end)
                end
            end

            actions.select_default:replace(select("default"))
            actions.select_horizontal:replace(select("horizontal"))
            actions.select_vertical:replace(select("vertical"))
            actions.select_tab:replace(select("tab"))
            return true
        end

        local telescope = require("telescope")
        telescope.setup({
            pickers = {
                find_files = {
                    attach_mappings = attach_find_files_mappings,
                    -- find_command = { "rg", "--files", "--hidden", "--no-ignore", "--glob", "!**/.git/*" }
                }
            }
        })
        telescope.load_extension('fzf')
        telescope.load_extension('cmdline')
    end
}
