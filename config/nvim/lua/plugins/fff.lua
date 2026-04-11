return {
	"dmtrKovalenko/fff.nvim",
	lazy = false,
	build = function()
		require("fff.download").download_or_build_binary()
	end,
	opts = {
		lazy_sync = true,
	},
	config = function(_, opts)
		require("fff").setup(opts)
	end,
}
