return {
    {
        name = "CodeDiffClose",
        cmd = function()
            require("lua.codediff").close_current()
        end,
        rtxt = "dc",
    },

    { name = "separator" },

    {
        name = "Stage Hunk",
        cmd = function()
            require("lua.codediff_gitsigns").run("stage_hunk")
        end,
        rtxt = "sh",
    },
    {
        name = "Reset Hunk",
        cmd = function()
            require("lua.codediff_gitsigns").run("reset_hunk")
        end,
        rtxt = "rh",
    },

    {
        name = "Stage Buffer",
        cmd = function()
            require("lua.codediff_gitsigns").run("stage_buffer")
        end,
        rtxt = "sb",
    },
    {
        name = "Undo Stage Hunk",
        cmd = function()
            require("lua.codediff_gitsigns").run("undo_stage_hunk")
        end,
        rtxt = "us",
    },
    {
        name = "Reset Buffer",
        cmd = function()
            require("lua.codediff_gitsigns").run("reset_buffer")
        end,
        rtxt = "rb",
    },
    {
        name = "Preview Hunk",
        cmd = function()
            require("lua.codediff_gitsigns").run("preview_hunk")
        end,
        rtxt = "hp",
    },

    { name = "separator" },

    {
        name = "Blame Line",
        cmd = function()
            require("lua.codediff_gitsigns").run("blame_line", { full = true })
        end,
        rtxt = "b",
    },
    {
        name = "Toggle Current Line Blame",
        cmd = function()
            require("lua.codediff_gitsigns").run("toggle_current_line_blame")
        end,
        rtxt = "tb",
    },

    { name = "separator" },

    {
        name = "Diff This",
        cmd = function()
            require("lua.codediff_gitsigns").run("diffthis")
        end,
        rtxt = "dt",
    },
    {
        name = "Diff Last Commit",
        cmd = function()
            require("lua.codediff_gitsigns").run("diffthis", "~")
        end,
        rtxt = "dc",
    },
    {
        name = "Toggle Deleted",
        cmd = function()
            require("lua.codediff_gitsigns").run("toggle_deleted")
        end,
        rtxt = "td",
    },

}
