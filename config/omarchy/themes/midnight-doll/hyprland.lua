local active_border_color = "rgb(ff51c5)"
local inactive_border_color = "rgb(2b0938)"

hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 2,
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  decoration = {
    rounding = 0,
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})

-- Terminal opacity 0.90
o.window({ tag = "terminal" }, { opacity = "0.90 0.90" })
