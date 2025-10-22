local enabled = false
local provider = "codestral"
-- local provider = "deepseek"
if os.getenv("DS_AI") then
    provider = "deepseek"
    vim.notify("[minuet-ai.nvim] env DS_AI is set, using deepseek", vim.log.levels.INFO)
end

local throttle = 300
local debounce = 200
local provider_option = ""
do
    if provider == "codestral" then
        enabled = os.getenv("CODESTRAL_API_KEY") ~= nil
        provider_option = "codestral"

        -- `codestral` is free to use, so feel freeto remove the throttle and debounce
        throttle = 100
        debounce = 200
    end
    if provider == "deepseek" then
        enabled = os.getenv("DEEPSEEK_API_KEY") ~= nil
        provider_option = "openai_fim_compatible"
    end
end

vim.notify(string.format("[minuet-ai.nvim] provider: %s, enabled: %s", provider, tostring(enabled)), vim.log.levels.INFO)
vim.g.minuet_ai_enabled = enabled

return {
    {
        'milanglacier/minuet-ai.nvim',
        enabled = enabled,
        event = "BufReadPre",
        opts = {
            -- virtual_text = {
            --     -- auto_trigget_ft = { "lua" },
            --     keymap = {
            --         accept = "<Tab>",
            --         prev = "<A-[>",
            --         next = "<A-]>",
            --         dismiss = "<A-e>",
            --     },
            --     show_on_completion_menu = true,
            -- },

            -- Only send the request every x milliseconds, use 0 to disable.
            throttle = throttle,
            -- Only send the request after x milliseconds of inactivity, use 0 to disable.
            debounce = debounce,

            request_timeout = 2000,

            n_completions = 3,
            provider = provider_option,
            provider_options = {
                codestral = {
                    optinoal = {
                        max_tokens = 256,
                        stop = { "\n\n" },
                    },
                },
                openai_fim_compatible = {
                    optional = {
                        max_tokens = 256,
                        stop = { "\n\n" },
                    },
                },
            },
        }
    },
    { 'nvim-lua/plenary.nvim' },

}
