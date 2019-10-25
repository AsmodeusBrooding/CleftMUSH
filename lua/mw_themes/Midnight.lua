-- Copy this file to create your own custom themes, but please do not modify this file.

-- MIDNIGHT THEME
return {
   LOGO_OPACITY = 0.06,

   PRIMARY_BODY = 0x0c0000,
   SECONDARY_BODY = 0x330000,
   BODY_TEXT = 0xff5511,

   -- flat buttons
   CLICKABLE = 0x220000,
   CLICKABLE_HOVER = 0x601911,
   CLICKABLE_HOT = 0x7b0000,
   CLICKABLE_TEXT = 0xff0000,
   CLICKABLE_HOVER_TEXT = 0xff1111,
   CLICKABLE_HOT_TEXT = 0xff2000,

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0xaa0000,

   THREE_D_GRADIENT = false,
   THREE_D_GRADIENT_FIRST = 0x650808,
--   THREE_D_GRADIENT_SECOND = 0x301010,
--   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x350808,
   THREE_D_HARDSHADOW = 0x220404,
   THREE_D_SURFACE_DETAIL = 0xff8888, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x110000,
   SCROLL_TRACK_COLOR2 = 0x551111,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16,

   -- bg_texture_function is optional to override the default behavior.
   -- See Charcoal.lua for a "do nothing" variant.
   -- Just make sure to return the path to a valid png file.
   bg_texture_function = function()
      imgpath = GetInfo(66).."worlds/plugins/images/bg1.png"

      WindowCreate("WiLl_It_BlEnD", 0, 0, 0, 0, 0, 0, Theme.THREE_D_HIGHLIGHT)
      WindowLoadImage("WiLl_It_BlEnD", "tExTuRe", imgpath)
      local tw = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 2)
      local th = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 3)
      WindowResize("WiLl_It_BlEnD", tw, th, Theme.THREE_D_HIGHLIGHT)
      WindowImageFromWindow("WiLl_It_BlEnD", "cOlOr", "WiLl_It_BlEnD")

      WindowDrawImage("WiLl_It_BlEnD", "tExTuRe", 0, 0, 0, 0, 1)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, 50)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 8, 30)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, -120)
      WindowBlendImage("WiLl_It_BlEnD", "cOlOr", 0, 0, 0, 0, 5, 0.9)

      imgpath = GetInfo(66).."worlds/plugins/images/temp_theme_blend.png"
      WindowWrite("WiLl_It_BlEnD", imgpath)

      return imgpath
   end
}