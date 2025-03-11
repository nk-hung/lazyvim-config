return {
  "greggh/claude-code.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim", -- Yêu cầu cho các hoạt động git
  },
  config = function()
    require("claude-code")
  end,
}
