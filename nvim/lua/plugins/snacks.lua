return {
    "folke/snacks.nvim",
    opts = {
        picker = {
            exclude = {
                "node_modules",
            },
            sources = {
                files = { hidden = true },
                explorer = { hidden = true },
            },
        },
    },
}
