-- mapper.lua

--[[

Authors: Original by Nick Gammon. Modified by Fiendish, and heavily modified for Cleft of Dimensions by Asmodeus

Generic MUD mapper, plus graphical mapper.

Exposed functions:

init (t)            -- call once, supply:
   t.findpath    -- function for finding the path between two rooms (src, dest)
   t.config      -- ie. colours, sizes
   t.get_room    -- info about room (uid)
   t.show_help   -- function that displays some help
   t.room_click  -- function that handles RH click on room (uid, flags)
   t.timing      -- true to show timing
   t.show_completed  -- true to show "Speedwalk completed."
   t.show_other_areas -- true to show non-current areas
   t.show_up_down    -- follow up/down exits
   t.speedwalk_prefix   -- if not nil, speedwalk by prefixing with this

zoom_in ()          -- zoom in map view
zoom_out ()         -- zoom out map view
mapprint (message)  -- like print, but uses mapper colour
maperror (message)  -- like print, but prints in red
hide ()             -- hides map window (eg. if plugin disabled)
show ()             -- show map window  (eg. if plugin enabled)
save_state ()       -- call to save plugin state (ie. in OnPluginSaveState)
draw (uid)          -- draw map - starting at room 'uid'
start_speedwalk (path)  -- starts speedwalking. path is a table of directions/uids
build_speedwalk (path)  -- builds a client speedwalk string from path
cancel_speedwalk ()     -- cancel current speedwalk, if any
check_we_can_find ()    -- returns true if doing a find is OK right now
find (f, show_uid, count, walk)      -- generic room finder

Exposed variables:

win                 -- the window (in case you want to put up menus)
VERSION             -- mapper version
last_hyperlink_uid  -- room uid of last hyperlink click (destination)
last_speedwalk_uid  -- room uid of last speedwalk attempted (destination)
<various functions> -- functions required to be global by the client (eg. for mouseup)

Room info should include:

   name          (what to show as room name)
   exits         (table keyed by direction, value is exit uid)
   area          (area name)
   hovermessage  (what to show when you mouse-over the room)
   bordercolour  (colour of room border)     - RGB colour
   borderpen     (pen style of room border)  - see WindowCircleOp (values 0 to 6)
   borderpenwidth(pen width of room border)  - eg. 1 for normal, 2 for current room
   fillcolour    (colour to fill room)       - RGB colour, nil for default
   fillbrush     (brush to fill room)        - see WindowCircleOp (values 0 to 12)
   texture       (background texture file)   - cached in textures

--]]

module (..., package.seeall)

VERSION = 6.02   -- for querying by plugins
require "aard_register_z_on_create"

require "mw_theme_base"
require "movewindow"
require "copytable"
require "gauge"
require "pairsbykeys"
require "mw"

local FONT_ID     = "fn"  -- internal font identifier
local FONT_ID_UL  = "fnu" -- internal font identifier - underlined
local CONFIG_FONT_ID = "cfn"
local CONFIG_FONT_ID_UL = "cfnu"

-- size of room box
local ROOM_SIZE = tonumber(GetVariable("ROOM_SIZE")) or 12

-- how far away to draw rooms from each other
local DISTANCE_TO_NEXT_ROOM = tonumber(GetVariable("DISTANCE_TO_NEXT_ROOM")) or 8

-- supplied in init
local supplied_get_room
local room_click
local timing            -- true to show timing and other info
local show_completed    -- true to show "Speedwalk completed."

-- current room number
local current_room

-- our copy of rooms info
local rooms = {}
local last_visited = {}
local textures = {}
local last_result_list = {}

-- other locals
local HALF_ROOM, connectors, half_connectors, arrows
local plan_to_draw, speedwalks, drawn, drawn_coords 
local last_drawn, depth, font_height
local walk_to_room_name
local total_times_drawn = 0
local total_time_taken = 0

default_width = 269
default_height = 335
default_x = 868
default_y = 0

function reset_pos()
   config.WINDOW.width = default_width
   config.WINDOW.height = default_height
   WindowPosition(win, default_x, default_y, 0, 18)
   WindowResize(win, default_width, default_height, BACKGROUND_COLOUR.colour)
   Repaint() -- hack because WindowPosition doesn't immediately update coordinates
end

local function build_room_info ()

   HALF_ROOM   = math.ceil(ROOM_SIZE / 2)
   local THIRD_WAY   = math.ceil(DISTANCE_TO_NEXT_ROOM / 3)
   local HALF_WAY = math.ceil(DISTANCE_TO_NEXT_ROOM / 2)
   local DISTANCE_LESS1 = DISTANCE_TO_NEXT_ROOM - 1

   barriers = {
      n =  { x1 = -HALF_ROOM, y1 = -HALF_ROOM, x2 = HALF_ROOM, y2 = -HALF_ROOM},
      s =  { x1 = -HALF_ROOM, y1 =  HALF_ROOM, x2 = HALF_ROOM, y2 =  HALF_ROOM},
      e =  { x1 =  HALF_ROOM, y1 = -HALF_ROOM, x2 =  HALF_ROOM, y2 = HALF_ROOM},
      w =  { x1 = -HALF_ROOM, y1 = -HALF_ROOM, x2 = -HALF_ROOM, y2 = HALF_ROOM},

      u = { x1 =  HALF_ROOM-HALF_WAY, y1 = -HALF_ROOM-HALF_WAY, x2 =  HALF_ROOM+HALF_WAY, y2 = -HALF_ROOM+HALF_WAY},
      d = { x1 = -HALF_ROOM+HALF_WAY, y1 =  HALF_ROOM+HALF_WAY, x2 = -HALF_ROOM-HALF_WAY, y2 =  HALF_ROOM-HALF_WAY},


   } -- end barriers

   -- how to draw a line from this room to the next one (relative to the center of the room)
   connectors = {
      n =  { x1 = 0,            y1 = - HALF_ROOM, x2 = 0,                             y2 = - HALF_ROOM - HALF_WAY, at = { 0, -1 } },
      s =  { x1 = 0,            y1 =   HALF_ROOM, x2 = 0,                             y2 =   HALF_ROOM + HALF_WAY, at = { 0,  1 } },
      e =  { x1 =   HALF_ROOM,  y1 = 0,           x2 =   HALF_ROOM + HALF_WAY,  y2 = 0,                            at = {  1,  0 }},
      w =  { x1 = - HALF_ROOM,  y1 = 0,           x2 = - HALF_ROOM - HALF_WAY,  y2 = 0,                            at = { -1,  0 }},

      u = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + HALF_WAY , y2 = - HALF_ROOM - HALF_WAY, at = { 1, -1 } },
      d = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - HALF_WAY , y2 =   HALF_ROOM + HALF_WAY, at = {-1,  1 } },
	  ne = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + DISTANCE_LESS1 , y2 = - HALF_ROOM - DISTANCE_LESS1, at = { 1, -1 } },
      se = { x1 =   HALF_ROOM,  y1 =   HALF_ROOM, x2 =   HALF_ROOM + DISTANCE_LESS1 , y2 =   HALF_ROOM + DISTANCE_LESS1, at = { 1,  1 } },
      nw = { x1 = - HALF_ROOM,  y1 = - HALF_ROOM, x2 = - HALF_ROOM - DISTANCE_LESS1 , y2 = - HALF_ROOM - DISTANCE_LESS1, at = {-1, -1 } },
      sw = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - DISTANCE_LESS1 , y2 =   HALF_ROOM + DISTANCE_LESS1, at = {-1,  1 } },
	  

   } -- end connectors

   -- how to draw a stub line
   half_connectors = {
      n =  { x1 = 0,            y1 = - HALF_ROOM, x2 = 0,                        y2 = - HALF_ROOM - THIRD_WAY, at = { 0, -1 } },
      s =  { x1 = 0,            y1 =   HALF_ROOM, x2 = 0,                        y2 =   HALF_ROOM + THIRD_WAY, at = { 0,  1 } },
      e =  { x1 =   HALF_ROOM,  y1 = 0,           x2 =   HALF_ROOM + THIRD_WAY,  y2 = 0,                       at = {  1,  0 }},
      w =  { x1 = - HALF_ROOM,  y1 = 0,           x2 = - HALF_ROOM - THIRD_WAY,  y2 = 0,                       at = { -1,  0 }},

      u = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + THIRD_WAY , y2 = - HALF_ROOM - THIRD_WAY, at = { 1, -1 } },
      d = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - THIRD_WAY , y2 =   HALF_ROOM + THIRD_WAY, at = {-1,  1 } },
	  ne = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + THIRD_WAY , y2 = - HALF_ROOM - THIRD_WAY, at = { 1, -1 } },
     se = { x1 =   HALF_ROOM,  y1 =   HALF_ROOM, x2 =   HALF_ROOM + THIRD_WAY , y2 =   HALF_ROOM + THIRD_WAY, at = { 1,  1 } },
     nw = { x1 = - HALF_ROOM,  y1 = - HALF_ROOM, x2 = - HALF_ROOM - THIRD_WAY , y2 = - HALF_ROOM - THIRD_WAY, at = {-1, -1 } },
     sw = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - THIRD_WAY , y2 =   HALF_ROOM + THIRD_WAY, at = {-1,  1 } },

   } -- end half_connectors

   -- how to draw one-way arrows (relative to the center of the room)
   arrows = {
      n =  { - 2, - HALF_ROOM - 2,  2, - HALF_ROOM - 2,  0, - HALF_ROOM - 6 },
      s =  { - 2,   HALF_ROOM + 2,  2,   HALF_ROOM + 2,  0,   HALF_ROOM + 6  },
      e =  {   HALF_ROOM + 2, -2,   HALF_ROOM + 2, 2,   HALF_ROOM + 6, 0 },
      w =  { - HALF_ROOM - 2, -2, - HALF_ROOM - 2, 2, - HALF_ROOM - 6, 0 },

      u = {   HALF_ROOM + 3,  - HALF_ROOM,  HALF_ROOM + 3, - HALF_ROOM - 3,  HALF_ROOM, - HALF_ROOM - 3 },
      d = { - HALF_ROOM - 3,    HALF_ROOM,  - HALF_ROOM - 3,   HALF_ROOM + 3,  - HALF_ROOM,   HALF_ROOM + 3},
	  ne = {   HALF_ROOM + 3,  - HALF_ROOM,  HALF_ROOM + 3, - HALF_ROOM - 3,  HALF_ROOM, - HALF_ROOM - 3 },
      se = {   HALF_ROOM + 3,    HALF_ROOM,  HALF_ROOM + 3,   HALF_ROOM + 3,  HALF_ROOM,   HALF_ROOM + 3 },
      nw = { - HALF_ROOM - 3,  - HALF_ROOM,  - HALF_ROOM - 3, - HALF_ROOM - 3,  - HALF_ROOM, - HALF_ROOM - 3 },
      sw = { - HALF_ROOM - 3,    HALF_ROOM,  - HALF_ROOM - 3,   HALF_ROOM + 3,  - HALF_ROOM,   HALF_ROOM + 3},

   } -- end of arrows

end -- build_room_info

-- assorted colours
--Note ("OURROOMCOLOR", GetPluginVariable("7c54b861a8cd3c4745c28834", "OUR_ROOM_COLOUR"))
OUR_ROOM_COLOUR               = { name = "Our Room Colour",  colour =  tonumber(GetPluginVariable("7c54b861a8cd3c4745c28834", "OUR_ROOM_COLOUR")) or 0xFF }
BACKGROUND_COLOUR             = { name = "Area Background",  colour =  ColourNameToRGB "#111111"}
ROOM_COLOUR                   = { name = "Room",             colour =  ColourNameToRGB "#dcdcdc"}
EXIT_COLOUR                   = { name = "Exit",             colour =  ColourNameToRGB "#e0ffff"}
EXIT_COLOUR_UP_DOWN           = { name = "Exit up/down",     colour =  ColourNameToRGB "#ffb6c1"}
ROOM_NOTE_COLOUR              = { name = "Room notes",       colour =  ColourNameToRGB "lightgreen"}
UNKNOWN_ROOM_COLOUR           = { name = "Unknown room",     colour =  ColourNameToRGB "#8b0000"}
DIFFERENT_AREA_COLOUR         = { name = "Another area",     colour =  ColourNameToRGB "#ff0000"}
PK_BORDER_COLOUR              = { name = "PK border",        colour =  ColourNameToRGB "red"}
SHOP_FILL_COLOUR              = { name = "Shop",             colour =  ColourNameToRGB "#ffad2f"}
INN_FILL_COLOUR               = { name = "Inn",              colour =  ColourNameToRGB "lightseagreen"}
WAYPOINT_FILL_COLOUR          = { name = "waypoint",         colour =  ColourNameToRGB "lime"}
TRAINER_FILL_COLOUR           = { name = "Trainer",          colour =  ColourNameToRGB "#9acd32"}
QUESTOR_FILL_COLOUR           = { name = "Questor",          colour =  ColourNameToRGB "deepskyblue"}
BANK_FILL_COLOUR              = { name = "Bank",             colour =  ColourNameToRGB "gold"}
REGULAR_FILL_COLOUR           = { name = "Regular",          colour =  ColourNameToRGB "white"}
FOUNTAIN_FILL_COLOUR          = { name = "Fountain",         colour =  ColourNameToRGB "cyan"}
QUEST_FILL_COLOUR             = { name = "Quest",            colour =  ColourNameToRGB "yellow"}
ALCHEMY_GUILD_FILL_COLOUR     = { name = "Guild",            colour =  ColourNameToRGB "blue"}
PRIEST_FILL_COLOUR            = { name = "Priest",           colour =  ColourNameToRGB "white"}
MAGE_TRAINER_FILL_COLOUR      = { name = "Mage Trainer",     colour =  ColourNameToRGB "slategray"}
CLERIC_TRAINER_FILL_COLOUR    = { name = "Cleric Trainer",   colour =  ColourNameToRGB "cyan"}
THIEF_TRAINER_FILL_COLOUR     = { name = "Thief Trainer",    colour =  ColourNameToRGB "purple"}
WARRIOR_TRAINER_FILL_COLOUR   = { name = "Warrior Trainer",  colour =  ColourNameToRGB "red"}
NECRO_TRAINER_FILL_COLOUR     = { name = "Necro Trainer",    colour =  ColourNameToRGB "mediumslateblue"}
DRUID_TRAINER_FILL_COLOUR     = { name = "Druid Trainer",    colour =  ColourNameToRGB "green"}
RANGER_TRAINER_FILL_COLOUR    = { name = "Ranger Trainer",   colour =  ColourNameToRGB "yellow"}
MISC_TRAINER_FILL_COLOUR      = { name = "Priest",           colour =  ColourNameToRGB "white"}
MAPPER_NOTE_COLOUR            = { name = "Messages",         colour =  ColourNameToRGB "lightgreen"}

ROOM_NAME_TEXT                = { name = "Room name text",   colour = ColourNameToRGB "#BEF3F1"}
	_FILL                = { name = "Room name fill",   colour = ColourNameToRGB "#105653"}
ROOM_NAME_BORDER              = { name = "Room name box",    colour = ColourNameToRGB "black"}

AREA_NAME_TEXT                = { name = "Area name text",   colour = ColourNameToRGB "#BEF3F1"}
AREA_NAME_FILL                = { name = "Area name fill",   colour = ColourNameToRGB "#105653"}
AREA_NAME_BORDER              = { name = "Area name box",    colour = ColourNameToRGB "black"}

-- how many seconds to show "recent visit" lines (default 3 minutes)
LAST_VISIT_TIME = 60 * 3

default_config = {
   FONT = { name =  get_preferred_font {"Dina",  "Lucida Console",  "Fixedsys", "Courier",} ,
            size = 8
         } ,

   -- size of map window
   WINDOW = { width = default_width, height = default_height },

   -- how far from where we are standing to draw (rooms)
   SCAN = { depth = 300 },
   
     -- speedwalk delay
  DELAY = { time = 0.2 },

   -- show custom tiling background textures
   USE_TEXTURES = { enabled = true },

   SHOW_ROOM_ID = false,
   SHOW_ROOM_NOTES = false,
   --SHOW_TILES = GetPluginVariable("dd07d6dbe73fe0bd02ddb62c", "tile_mode") or "1",
SHOW_AREA_EXITS = false
}

local expand_direction = {
   n = "north",
   s = "south",
   e = "east",
   w = "west",
   u = "up",
   d = "down",
}  -- end of expand_direction

local function get_room (uid)
   local room = supplied_get_room (uid)
   room = room or { unknown = true }
   -- defaults in case they didn't supply them ...
   room.name = room.name or string.format ("Room %s", uid)
   room.name = mw.strip_colours (room.name)  -- no colour codes for now
   room.exits = room.exits or {}
   room.area = room.area or "<No area>"
   room.hovermessage = room.hovermessage or "<Unexplored room>"
   room.bordercolour = room.bordercolour or ROOM_COLOUR.colour
   room.borderpen = room.borderpen or 0 -- solid
   room.borderpenwidth = room.borderpenwidth or 1
   room.fillcolour = room.fillcolour or 0x000000
   room.fillbrush = room.fillbrush or 1 -- no fill
   room.texture = room.texture or nil -- no texture



   room.textimage = nil

   if room.texture == nil or room.texture == "" then room.texture = "test5.png" end
   if textures[room.texture] then
      room.textimage = textures[room.texture] -- assign image
   else
      if textures[room.texture] ~= false then
         local dir = GetInfo(66)
         imgpath = dir .. "worlds\\plugins\\images\\" ..room.texture
         if WindowLoadImage(win, room.texture, imgpath) ~= 0 then
            textures[room.texture] = false  -- just indicates not found
         else
            textures[room.texture] = room.texture -- imagename
            room.textimage = room.texture
			
         end
      end
   end
   
   return room
   
end -- get_room

function check_connected ()
   if not IsConnected() then
      mapprint ("You are not connected to", WorldName())
      return false
   end -- if not connected
   return true
end -- check_connected

local function make_number_checker (title, min, max, decimals)
   return function (s)
      local n = tonumber (s)
      if not n then
         utils.msgbox (title .. " must be a number", "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end -- if
      if n < min or n > max then
         utils.msgbox (title .. " must be in range " .. min .. " to " .. max, "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end -- if
      if not decimals then
         if string.match (s, "%.") then
            utils.msgbox (title .. " cannot have decimal places", "Incorrect input", "ok", "!", 1)
            return false  -- bad input
         end -- if
      end -- no decimals
      return true  -- good input
   end -- generated function
end -- make_number_checker


local function get_number_from_user (msg, title, current, min, max, decimals)
   local max_length = math.ceil (math.log10 (max) + 1)

   -- if decimals allowed, allow room for them
   if decimals then
      max_length = max_length + 2  -- allow for 0.x
   end -- if

   -- if can be negative, allow for minus sign
   if min < 0 then
      max_length = max_length + 1
   end -- if can be negative

   return tonumber (utils.inputbox (msg, title, current, nil, nil,
      { validate = make_number_checker (title, min, max, decimals),
         prompt_height = 14,
         box_height = 130,
         box_width = 300,
         reply_width = 150,
         max_length = max_length,
      }  -- end extra stuff
   ))
end -- get_number_from_user

local function draw_configuration ()

   local config_entries = {"Map Configuration", "Show Room ID", "Show Room NOTES", "Show Area Exits", "Font", "Depth", "Area Textures", "Room size"}
   local width =  max_text_width (config_win, CONFIG_FONT_ID, config_entries , true)
   local GAP = 5

   local x = 0
   local y = 0
   local box_size = font_height - 2
   local rh_size = math.max (box_size, max_text_width (config_win, CONFIG_FONT_ID,
      {config.FONT.name .. " " .. config.FONT.size,
      ((config.USE_TEXTURES.enabled and "On") or "Off"),
      "- +",
      tostring (config.SCAN.depth)},
      true))
   local frame_width = GAP + width + GAP + rh_size + GAP  -- gap / text / gap / box / gap

   WindowCreate(config_win, windowinfo.window_left, windowinfo.window_top, frame_width, font_height * #config_entries + GAP+GAP, windowinfo.window_mode, windowinfo.window_flags, 0xDCDCDC)
   WindowSetZOrder(config_win, 99999) -- always on top

   -- frame it
   draw_3d_box (config_win, 0, 0, frame_width, font_height * #config_entries + GAP+GAP)

   y = y + GAP
   x = x + GAP

   -- title
   WindowText (config_win, CONFIG_FONT_ID, "Map Configuration", ((frame_width-WindowTextWidth(config_win,CONFIG_FONT_ID,"Map Configuration"))/2), y, 0, 0, 0x808080)

   -- close box
   WindowRectOp (config_win,
      miniwin.rect_frame,
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,
      0x808080)
   WindowLine (config_win,
      x + 3,
      y + 4,
      x + box_size - 3,
      y - 2 + box_size,
      0x808080,
      miniwin.pen_solid, 1)
   WindowLine (config_win,
      x + box_size - 4,
      y + 4,
      x + 2,
      y - 2 + box_size,
      0x808080,
      miniwin.pen_solid, 1)

   -- close configuration hotspot
   WindowAddHotspot(config_win, "$<close_configure>",
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,    -- rectangle
      "", "", "", "", "mapper.mouseup_close_configure",  -- mouseup
      "Click to close",
      miniwin.cursor_hand, 0)  -- hand cursor

   y = y + font_height

   -- depth
   WindowText(config_win, CONFIG_FONT_ID, "Depth", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL,   tostring (config.SCAN.depth), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, config.SCAN.depth)/2, y, 0, 0, 0x808080)

   -- depth hotspot
   WindowAddHotspot(config_win,
      "$<depth>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_depth",  -- mouseup
      "Click to change scan depth",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- font
   WindowText(config_win, CONFIG_FONT_ID, "Font", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL,  config.FONT.name .. " " .. config.FONT.size, x + width + GAP, y, 0, 0, 0x808080)

   -- font hotspot
   WindowAddHotspot(config_win,
      "$<font>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_font",  -- mouseup
      "Click to change font",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- area textures
   WindowText(config_win, CONFIG_FONT_ID, "Area Textures", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.USE_TEXTURES.enabled and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.USE_TEXTURES.enabled and "On") or "Off"))/2, y, 0, 0, 0x808080)

   -- area textures hotspot
   WindowAddHotspot(config_win,
      "$<area_textures>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_area_textures",  -- mouseup
      "Click to toggle use of area textures",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height


   -- show ID
   WindowText(config_win, CONFIG_FONT_ID, "Show Room ID", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_ROOM_ID and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_ROOM_ID and "On") or "Off"))/2, y, 0, 0, 0x808080)

   -- show ID hotspot
   WindowAddHotspot(config_win,
      "$<room_id>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_show_id",  -- mouseup
      "Click to toggle display of room UID",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height
   
         -- show NOTES
   WindowText(config_win, CONFIG_FONT_ID, "Show Room NOTES", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_ROOM_NOTES and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_ROOM_NOTES and "On") or "Off"))/2, y, 0, 0, 0x808080)
   
      -- show NOTES hotspot
   WindowAddHotspot(config_win,
      "$<room_notes>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_show_notes",  -- mouseup
      "Click to toggle display of room NOTES",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height
   
            -- show tiles
--   WindowText(config_win, CONFIG_FONT_ID, "Show Tiles", x, y, 0, 0, 0x000000)
--   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_TILES and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_TILES and "On") or "Off"))/2, y, 0, 0, 0x808080)
   
      -- show tiles hotspot
--   WindowAddHotspot(config_win,
--      "$<show_tiles>",
--      x + GAP,
--      y,
--      x + frame_width,
--      y + font_height,   -- rectangle
--      "", "", "", "", "mapper.mouseup_change_show_tiles",  -- mouseup
--      "Click to toggle display of room tiles",
--      miniwin.cursor_hand, 0)  -- hand cursor
--  y = y + font_height


   -- show area exits
   WindowText(config_win, CONFIG_FONT_ID, "Show Area Exits", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_AREA_EXITS and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_AREA_EXITS and "On") or "Off"))/2, y, 0, 0, 0x808080)

   -- show area exits hotspot
   WindowAddHotspot(config_win,
      "$<area_exits>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_show_area_exits",  -- mouseup
      "Click to toggle display of area exits",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height


   -- room size
   WindowText(config_win, CONFIG_FONT_ID, "Room size", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID, "("..tostring (ROOM_SIZE)..")", x + WindowTextWidth(config_win, CONFIG_FONT_ID, "Room size "), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "-", width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "+", width + rh_size / 2 + box_size + GAP, y, 0, 0, 0x808080)

   -- room size hotspots
   WindowAddHotspot(config_win,
      "$<room_size_down>",
      width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y,
      width + rh_size / 2 + box_size/2 + WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.zoom_out",  -- mouseup
      "Click to zoom out",
      miniwin.cursor_hand, 0)  -- hand cursor
   WindowAddHotspot(config_win,
      "$<room_size_up>",
      width + rh_size / 2 + box_size + GAP,
      y,
      width + rh_size / 2 + box_size + GAP + WindowTextWidth(config_win,CONFIG_FONT_ID,"+"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.zoom_in",  -- mouseup
      "Click to zoom in",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height
   

   WindowShow(config_win, true)
end -- draw_configuration



-- for calculating one-way paths
local inverse_direction = {
   n = "s",
   s = "n",
   e = "w",
   w = "e",
   u = "d",
   d = "u",
   ne = "sw",
   se = "nw",
   sw = "ne",
   nw = "se"
}  -- end of inverse_direction

local function add_another_room (uid, path, x, y)
   local path = path or {}
   return {uid=uid, path=path, x = x, y = y}
end  -- add_another_room

local function draw_room (uid, path, x, y)


   local coords = string.format ("%i,%i", math.floor (x), math.floor (y))

   -- need this for the *current* room !!!
   drawn_coords [coords] = uid

   -- print ("drawing", uid, "at", coords)

   if drawn [uid] then
      return
   end -- done this one

   -- don't draw the same room more than once
   drawn [uid] = { coords = coords, path = path }

   local room = rooms [uid]

   -- not cached - get from caller
   if not room then
      room = get_room (uid)
      rooms [uid] = room
   end -- not in cache
	
   local left, top, right, bottom = x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM

   -- forget it if off screen
   if (x < HALF_ROOM) or (y < (title_bottom or font_height)+HALF_ROOM) or
      (x > config.WINDOW.width - HALF_ROOM) or (y > config.WINDOW.height - HALF_ROOM) then
      return
   end -- if

   -- exits

   local texits = {}

   for dir, exit_uid in pairs (room.exits) do
      table.insert (texits, dir)
      local exit_info = connectors [dir]
      local stub_exit_info = half_connectors [dir]
      local locked_exit = not (room.exit_locks == nil or room.exit_locks[dir] == nil or room.exit_locks[dir] == "0")
      local exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR.colour
      local arrow = arrows [dir]

      -- draw up in the ne/nw position if not already an exit there at this level
      if dir == "u" then
         exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR_UP_DOWN.colour
      elseif dir == "d" then
         exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR_UP_DOWN.colour
      end -- if down

      if exit_info then
         local linetype = miniwin.pen_solid -- unbroken
         local linewidth = (locked_exit and 2) or 1 -- not recent

         -- try to cache room
         if not rooms [exit_uid] then
            rooms [exit_uid] = get_room (exit_uid)
         end -- if

         if rooms [exit_uid].unknown then
            linetype = miniwin.pen_dot -- dots
         end -- if

         local next_x = x + exit_info.at [1] * (ROOM_SIZE + DISTANCE_TO_NEXT_ROOM)
         local next_y = y + exit_info.at [2] * (ROOM_SIZE + DISTANCE_TO_NEXT_ROOM)

         local next_coords = string.format ("%i,%i", math.floor (next_x), math.floor (next_y))

         -- remember if a zone exit (first one only)
         if config.SHOW_AREA_EXITS and room.area ~= rooms [exit_uid].area and not rooms[exit_uid].unknown then
            area_exits [ rooms [exit_uid].area ] = area_exits [ rooms [exit_uid].area ] or {x = x, y = y, def = barriers[dir]}
         end -- if

         -- if another room (not where this one leads to) is already there, only draw "stub" lines
         if drawn_coords [next_coords] and drawn_coords [next_coords] ~= exit_uid then
            exit_info = stub_exit_info
         elseif exit_uid == uid then
            -- here if room leads back to itself
            exit_info = stub_exit_info
            linetype = miniwin.pen_dash -- dash
         else
         --if (not show_other_areas and rooms [exit_uid].area ~= current_area) or
            if (not show_other_areas and rooms [exit_uid].area ~= current_area and not rooms[exit_uid].unknown) or
               (not show_up_down and (dir == "u" or dir == "d")) then
               exit_info = stub_exit_info    -- don't show other areas
            else
               -- if we are scheduled to draw the room already, only draw a stub this time
               if plan_to_draw [exit_uid] and plan_to_draw [exit_uid] ~= next_coords then
                  -- here if room already going to be drawn
                  exit_info = stub_exit_info
                  linetype = miniwin.pen_dash -- dash
               else
                  -- remember to draw room next iteration
                  local new_path = copytable.deep (path)
                  table.insert (new_path, { dir = dir, uid = exit_uid })
                  table.insert (rooms_to_be_drawn, add_another_room (exit_uid, new_path, next_x, next_y))
                  drawn_coords [next_coords] = exit_uid
                  plan_to_draw [exit_uid] = next_coords

                  -- if exit room known
                  if not rooms [exit_uid].unknown then
                     local exit_time = last_visited [exit_uid] or 0
                     local this_time = last_visited [uid] or 0
                     local now = os.time ()
                     if exit_time > (now - LAST_VISIT_TIME) and
                        this_time > (now - LAST_VISIT_TIME) then
                        linewidth = 2
                     end -- if
                  end -- if
               end -- if
            end -- if
         end -- if drawn on this spot

         WindowLine (win, x + exit_info.x1, y + exit_info.y1, x + exit_info.x2, y + exit_info.y2, exit_line_colour, linetype + 0x0200, linewidth)

         -- one-way exit?

         if not rooms [exit_uid].unknown then
            local dest = rooms [exit_uid]
            -- if inverse direction doesn't point back to us, this is one-way
            if dest.exits [inverse_direction [dir]] ~= uid then
               -- turn points into string, relative to where the room is
               local points = string.format ("%i,%i,%i,%i,%i,%i",
                  x + arrow [1],
                  y + arrow [2],
                  x + arrow [3],
                  y + arrow [4],
                  x + arrow [5],
                  y + arrow [6])

               -- draw arrow
               WindowPolygon(win, points,
                  exit_line_colour, miniwin.pen_solid, 1,
                  exit_line_colour, miniwin.brush_solid,
                  true, true)
            end -- one way
         end -- if we know of the room where it does
      end -- if we know what to do with this direction
   end -- for each exit

								
   if room.unknown then
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         UNKNOWN_ROOM_COLOUR.colour, miniwin.pen_dot, 1,  --  dotted single pixel pen
         -1, miniwin.brush_null)  -- opaque, no brush
   else
      -- room fill
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         0, miniwin.pen_null, 0,  -- no pen
         room.fillcolour, room.fillbrush)  -- brush

      -- room border
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         room.bordercolour, room.borderpen, room.borderpenwidth,  -- pen
         -1, miniwin.brush_null)  -- opaque, no brush

      -- mark rooms with notes
      if room.notes ~= nil and room.notes ~= "" then
         WindowCircleOp (win, miniwin.circle_rectangle, left-1-room.borderpenwidth, top-1-room.borderpenwidth,
            right+1+room.borderpenwidth, bottom+1+room.borderpenwidth,ROOM_NOTE_COLOUR.colour,
            room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
      end
   end -- if

  speedwalks [uid] = path  -- so we know how to get here
     
  
   WindowAddHotspot(win, uid,
      left, top, right, bottom,   -- rectangle
      "",  -- mouseover
      "",  -- cancelmouseover
      "",  -- mousedown
      "",  -- cancelmousedown
      "mapper.mouseup_room",  -- mouseup
      room.hovermessage,
      miniwin.cursor_hand, 0)  -- hand cursor

   WindowScrollwheelHandler (win, uid, "mapper.zoom_map")
   
     local special_room = false
	 
   -- DRAW MAP IMAGES 
tile_mode = GetPluginVariable("dd07d6dbe73fe0bd02ddb62c", "tile_mode") or "1" 
area = GetPluginVariable("dd07d6dbe73fe0bd02ddb62c", "area") or "<No_Area>" 
                             if room.fillcolour and room.fillcolour ~= "" and tile_mode == "1" then
		 
   	                         if string.match (room.fillcolour, "9109504") then
          WindowDrawImage (win, "ocean", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
	                         elseif string.match (room.fillcolour, "9465920") then
	      WindowDrawImage (win, "city", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill -- formerly town
		  	                 elseif string.match (room.fillcolour, "61680") then
	      WindowDrawImage (win, "stream", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  	                 elseif string.match (room.fillcolour, "8411682") then
	      WindowDrawImage (win, "city", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  	         elseif string.match (room.fillcolour, "14745599") then
	      WindowDrawImage (win, "beach", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "16711680") then
	      WindowDrawImage (win, "water", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "49152") then
	      WindowDrawImage (win, "lightforest", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "16384") then
	      WindowDrawImage (win, "darkforest", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		     elseif string.match (room.fillcolour, "8421504") then
	      WindowDrawImage (win, "rock", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "65280") then
	      WindowDrawImage (win, "field", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  		 elseif string.match (room.fillcolour, "6316128") and area == "Brigantes Castle" then
	      WindowDrawImage (win, "inside_brigantes", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "6316128") then
	      WindowDrawImage (win, "building", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  	                 elseif string.match (room.fillcolour, "65535") then
          WindowDrawImage (win, "desert", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
	 		  	             elseif string.match (room.fillcolour, "8894686") then
          WindowDrawImage (win, "desert", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  	 		  	     elseif string.match (room.fillcolour, "8409216") then
          WindowDrawImage (win, "tundra", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  	 		 elseif string.match (room.fillcolour, "11394815") then
          WindowDrawImage (win, "taiga", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  	 		 elseif string.match (room.fillcolour, "8583398") then
          WindowDrawImage (win, "ice", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
	 		  	             elseif string.match (room.fillcolour, "9234160") then
          WindowDrawImage (win, "sandy", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  	 		  	     elseif string.match (room.fillcolour, "32768") then
          WindowDrawImage (win, "thickforest", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "4210752") then
	      WindowDrawImage (win, "cave", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "4219008") then
	      WindowDrawImage (win, "swamp", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "4231232") then
	      WindowDrawImage (win, "hill", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  	 elseif string.match (room.fillcolour, "15790240") then
	      WindowDrawImage (win, "wasteland", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill	
		  		  		  		  	 elseif string.match (room.fillcolour, "12632256") then
	      WindowDrawImage (win, "mountain", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  		  	 elseif string.match (room.fillcolour, "1262987") then
	      WindowDrawImage (win, "road", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
		  		  		  		  	 elseif string.match (room.fillcolour, "8413280") then
	      WindowDrawImage (win, "ruins", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill	
		  		  		  		  	 elseif string.match (room.fillcolour, "138860") then
	      WindowDrawImage (win, "developed", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill	
		  		  		  		  	 elseif string.match (room.fillcolour, "255") then
	      WindowDrawImage (win, "lava", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill	
		  
	 end -- if

	    -- SPECIAL ROOM COLOUR FILLS
                         if room.info and room.info ~= "" then
                         if string.match (room.info, "waypoint") then
                                         special_room = true
		 	                             WindowDrawImage (win, "waypoint", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,WAYPOINT_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                         elseif string.match (room.info, "bank") then
                                         special_room = true
		 	                             WindowDrawImage (win, "bank", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,BANK_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
						elseif string.match (room.info, "gato") then
                                         special_room = true
		 	                             WindowDrawImage (win, "gato", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
										 						elseif string.match (room.info, "moti") then
                                         special_room = true
		 	                             WindowDrawImage (win, "moti", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
										 			     		elseif string.match (room.info, "weaponshop") then
                                         special_room = true
		 	                             WindowDrawImage (win, "weaponshop", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
										                		elseif string.match (room.info, "armorshop") then
                                         special_room = true
		 	                             WindowDrawImage (win, "armorshop", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
										                		elseif string.match (room.info, "itemshop") then
                                         special_room = true
		 	                             WindowDrawImage (win, "itemshop", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern		
										                		elseif string.match (room.info, "foodshop") then
                                         special_room = true
		 	                             WindowDrawImage (win, "foodshop", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern		
										                		elseif string.match (room.info, "lightshop") then
                                         special_room = true
		 	                             WindowDrawImage (win, "lightshop", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,REGULAR_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern											 
										 						elseif string.match (room.info, "inn") then
                                         special_room = true
		 	                             WindowDrawImage (win, "inn", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,INN_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
										 				        elseif string.match (room.info, "tavern") then
                                         special_room = true
		 	                             WindowDrawImage (win, "tavern", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,INN_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
						 elseif string.match (room.info, "quest") then
                                         special_room = true
		 	                             WindowDrawImage (win, "quest", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,QUEST_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
										 						 elseif string.match (room.info, "fountain") then
                                         special_room = true
		 	                             WindowDrawImage (win, "fountain", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,FOUNTAIN_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 8  -- medium pattern
                         elseif string.match (room.info, "alchemyguild") then
                                         special_room = true
		 	                             WindowDrawImage (win, "alchemyguild", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,ALCHEMY_GUILD_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 0 -- solid
                         elseif string.match (room.info, "teacher") then
                                         special_room = true
                                         room.fillcolour = mapper.TEACHER_FILL_COLOUR.colour
                                         room.fillbrush = 0 -- solid
                         elseif string.match (room.info, "employer") then
                                         special_room = true
                                         room.fillcolour = mapper.EMPLOYER_FILL_COLOUR.colour
                                         room.fillbrush = 0 -- solid
                         elseif string.match (room.info, "priest") then
                                         special_room = true
		 	                             WindowDrawImage (win, "priest", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
			                             WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,PRIEST_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
                                         room.fillbrush = 0 -- solid
                         elseif string.match (room.info, "forge") then
                                         special_room = true
                                         room.fillcolour = mapper.FORGE_FILL_COLOUR.colour
                                         room.fillbrush = 0  -- solid
		                 elseif string.match (room.info, "warriortrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "warriortrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,WARRIOR_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
				         elseif string.match (room.info, "thieftrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "thieftrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
			                           	 WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,THIEF_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
				         elseif string.match (room.info, "druidtrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "druidtrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,DRUID_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
		                 elseif string.match (room.info, "clerictrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "clerictrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,CLERIC_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
				         elseif string.match (room.info, "magetrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "magetrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,MAGE_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
				         elseif string.match (room.info, "necromancertrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "necromancertrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,NECRO_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)			
				         elseif string.match (room.info, "rangertrainer") then
                                         special_room = true
		 	                             WindowDrawImage (win, "rangertrainer", left, top, right, bottom, miniwin.image_stretch)  -- stretch to fill
				                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth,RANGER_TRAINER_FILL_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)												 
                 
										end
                                        end -- if
			             if uid == current_room and not special_room then
                                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth, OUR_ROOM_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-2,miniwin.brush_null)										
end
end

			             if uid == current_room and not special_room and tile_mode == "0" then
                                         WindowCircleOp (win, miniwin.circle_rectangle, left-2-room.borderpenwidth, top-2-room.borderpenwidth,
                                         right+2+room.borderpenwidth, bottom+2+room.borderpenwidth, OUR_ROOM_COLOUR.colour,
                                         room.borderpen, room.borderpenwidth,-2,miniwin.brush_null)		
										
										 end
  
  

end -- draw_room

local function changed_room (uid)

  hyperlink_paths = nil  -- those hyperlinks are meaningless now
  speedwalks = {}  -- old speedwalks are irrelevant

  if current_speedwalk then

    if uid ~= expected_room then
      local exp = rooms [expected_room]
      if not exp then
        exp = get_room (expected_room) or { name = expected_room }
      end -- if
      local here = rooms [uid]
      if not here then
        here = get_room (uid) or { name = uid }
      end -- if
      exp = expected_room
      here = uid
      maperror (string.format ("Speedwalk failed! Expected to be in '%s' but ended up in '%s'.", exp or "<none>", here))
      cancel_speedwalk ()
    else
      if #current_speedwalk > 0 then
        local dir = table.remove (current_speedwalk, 1)
        SetStatus ("Walking " .. (expand_direction [dir.dir] or dir.dir) ..
                   " to " .. walk_to_room_name ..
                   ". Speedwalks to go: " .. #current_speedwalk + 1)
        expected_room = dir.uid
        if config.DELAY.time > 0 then
          if GetOption ("enable_timers") ~= 1 then
            maperror ("WARNING! Timers not enabled. Speedwalking will not work properly.")
          end -- if timers disabled
          DoAfterSpecial (config.DELAY.time, dir.dir, sendto.execute)
        else
          Execute (dir.dir)
        end -- if
      else
        last_hyperlink_uid = nil
        last_speedwalk_uid = nil
        if show_completed then
          mapprint ("Speedwalk completed.")
        end -- if wanted
        cancel_speedwalk ()
      end -- if any left
    end -- if expected room or not
  end -- if have a current speedwalk

end -- changed_room

local function draw_zone_exit (exit)
   local x, y, def = exit.x, exit.y, exit.def
   local offset = ROOM_SIZE

   WindowLine (win, x + def.x1, y + def.y1, x + def.x2, y + def.y2, ColourNameToRGB("yellow"), miniwin.pen_solid + 0x0200, 5)
   WindowLine (win, x + def.x1, y + def.y1, x + def.x2, y + def.y2, ColourNameToRGB("green"), miniwin.pen_solid + 0x0200, 1)
end --  draw_zone_exit


----------------------------------------------------------------------------------
--  EXPOSED FUNCTIONS
----------------------------------------------------------------------------------

-- can we find another room right now?

function check_we_can_find ()
   if not current_room then
      mapprint ("I don't know where you are right now - try: LOOK")
      check_connected ()
      return false
   end
   if current_speedwalk then
      mapprint ("The mapper has detected a speedwalk initiated inside another speedwalk. Aborting.")
      return false
   end -- if
   return true
end -- check_we_can_find

-- draw our map starting at room: uid
dont_draw = false
function halt_drawing(halt)
   dont_draw = halt
end
-------------------------------------------------------------------------------------
-- EXPERIMENTAL CODE 
-------------------------------------------------------------------------------------
function draw_next_batch_of_rooms()
   -- timing
   local start_time = utils.timer ()

   local metrics
   if current_room_is_cont then
      metrics = CONTINENTS_ROOM_INFO
   else
      metrics = AREA_ROOM_INFO
   end

   -- insert initial room
   local draw_elapsed = utils.timer()
   while #rooms_to_draw_next > 0 do
      local this_draw_level = rooms_to_draw_next
      rooms_to_draw_next = {}  -- new generation
      for i, room in ipairs(this_draw_level) do
         draw_room(room[1], room[2], room[3], metrics)
      end -- for each existing room
      depth = depth + 1
      if (#rooms_to_draw_next > 0 and utils.timer()-draw_elapsed > 0.08) then
         if not running then
            AddTimer("draw_next_batch_of_rooms"..depth, 0, 0, 0.1, "mapper.draw_next_batch_of_rooms()", timer_flag.Enabled + timer_flag.OneShot + timer_flag.Replace + timer_flag.Temporary, "")
            SetTimerOption("draw_next_batch_of_rooms"..depth, "send_to", sendto.script)
         end
         break
      end
   end -- while all rooms_to_draw_next

   -- creating thousands of hotspots is relatively expensive, so if we've hit the time limit and
   -- are going to make a second-pass timer wait until the second pass is done to do it.
   -- If we're in a run, for example, we may never get there and save the effort.
   if #rooms_to_draw_next == 0 then
      for uid,v in pairs(drawn_uids) do
         local left, top, right, bottom = v[1] - metrics.HALF_ROOM_DOWN, v[2] - metrics.HALF_ROOM_DOWN, v[1] + metrics.HALF_ROOM_UP, v[2] + metrics.HALF_ROOM_UP

         WindowAddHotspot(win, uid,
            left, top, right, bottom,   -- rectangle
            "",  -- mouseover
            "",  -- cancelmouseover
            "",  -- mousedown
            "",  -- cancelmousedown
            "mapper.mouseup_room",  -- mouseup
            daredevil_mode and "" or get_room_display_params(uid).hovermessage,
            miniwin.cursor_hand, 0)  -- hand cursor

         WindowScrollwheelHandler (win, uid, "mapper.zoom_map")
      end
   end

   local barriers = metrics.barriers
   for i, zone_exit in ipairs(area_exits) do
      draw_zone_exit(zone_exit, barriers)
  end -- for
   local end_time = utils.timer ()

 -- draw_edge()

   -- timing stuff
   if timing then
      local count= 0
      for k in pairs (drawn_uids) do
         count = count + 1
      end
      print (string.format ("Time to draw %i rooms = %0.3f seconds, search depth = %i", count, end_time - start_time, depth))

      total_times_drawn = total_times_drawn + 1
      total_time_taken = total_time_taken + end_time - start_time

      print (string.format ("Total times map drawn = %i, average time to draw = %0.3f seconds",
         total_times_drawn,
         total_time_taken / total_times_drawn))
   end -- if
end

function find_paths (uid, f)

  local function make_particle (curr_loc, prev_path)
    local prev_path = prev_path or {}
    return {current_room=curr_loc, path=prev_path}
  end

  local depth = 0
  local count = 0
  local done = false
  local found, reason
  local explored_rooms, particles = {}, {}

  -- this is where we collect found paths
  -- the table is keyed by destination, with paths as values
  local paths = {}

  -- create particle for the initial room
  table.insert (particles, make_particle (uid))

  while (not done) and #particles > 0 and depth < config.SCAN.depth do

    -- create a new generation of particles
    new_generation = {}
    depth = depth + 1

    SetStatus (string.format ("Scanning: %i/%i depth (%i rooms)", depth, config.SCAN.depth, count))

    -- process each active particle
    for i, part in ipairs (particles) do

      count = count + 1

      if not rooms [part.current_room] then
        rooms [part.current_room] = get_room (part.current_room)
      end -- if not in memory yet

      -- if room doesn't exist, forget it
      if rooms [part.current_room] then

        -- get a list of exits from the current room
        exits = rooms [part.current_room].exits

        -- create one new particle for each exit
        for dir, dest in pairs(exits) do

          -- if we've been in this room before, drop it
          if not explored_rooms[dest] then
            explored_rooms[dest] = true
            rooms [dest] = supplied_get_room (dest)  -- make sure this room in table
            if rooms [dest] then
              new_path = copytable.deep (part.path)
              table.insert(new_path, { dir = dir, uid = dest } )

              -- if this room is in the list of destinations then save its path
              found, done = f (dest)
              if found then
                paths[dest] = { path = new_path, reason = found }
              end -- found one!

              -- make a new particle in the new room
              table.insert(new_generation, make_particle(dest, new_path))
            end -- if room exists
          end -- not explored this room
          if done then
            break
          end

        end  -- for each exit

      end -- if room exists

      if done then
        break
      end
    end  -- for each particle

    particles = new_generation
  end   -- while more particles

  SetStatus "Ready"
  return paths, count, depth
end -- function find_paths

function draw (uid)
   -- timing
   local outer_time = utils.timer ()
   if not uid then
      maperror "Cannot draw map right now, I don't know where you are - try: LOOK"
      return
   end -- if

   if current_room and current_room ~= uid then
      changed_room (uid)
   end -- if

   current_room = uid -- remember where we are

   if dont_draw then
      return
   end

   -- timing
   local start_time = utils.timer ()

   -- start with initial room
   rooms = { [uid] = get_room (uid) }

   -- lookup current room
   local room = rooms [uid]

   room = room or { name = "<Unknown room>", area = "<Unknown area>" }
   last_visited [uid] = os.time ()

   current_area = room.area

   -- update dimensions and position here because the bigmap might have changed them
   windowinfo.window_left = WindowInfo(win, 1) or windowinfo.window_left
   windowinfo.window_top = WindowInfo(win, 2) or windowinfo.window_top
   config.WINDOW.width = WindowInfo(win, 3) or config.WINDOW.width
   config.WINDOW.height = WindowInfo(win, 4) or config.WINDOW.height

   WindowCreate (win,
      windowinfo.window_left,
      windowinfo.window_top,
      config.WINDOW.width,
      config.WINDOW.height,
      windowinfo.window_mode,   -- top right
      windowinfo.window_flags,
      Theme.PRIMARY_BODY)
	
	  
	  --Handle loading imagetiles
	  
	      WindowLoadImage (win, "building", "worlds\\plugins\\images\\building.bmp")                       --Terrain 01 BUILDING
		  WindowLoadImage (win, "town", "worlds\\plugins\\images\\town.bmp")                               --Terrain 02 TOWN
		  WindowLoadImage (win, "field", "worlds\\plugins\\images\\field.bmp")                             --Terrain 03 FIELD
		  WindowLoadImage (win, "lightforest", "worlds\\plugins\\images\\lightforest.bmp")                 --Terrain 04 LIGHTFOREST
		  WindowLoadImage (win, "thickforest", "worlds\\plugins\\images\\thickforest.bmp")                 --Terrain 05 THICKFOREST
		  WindowLoadImage (win, "darkforest", "worlds\\plugins\\images\\darkforest.bmp")                   --Terrain 06 DARKFOREST
	      WindowLoadImage (win, "swamp", "worlds\\plugins\\images\\swamp.bmp")		                       --Terrain 07 SWAMP
		  
		  WindowLoadImage (win, "sandy", "worlds\\plugins\\images\\sandy.bmp")                             --Terrain 09 SANDY
		  WindowLoadImage (win, "mountain", "worlds\\plugins\\images\\mountain.bmp")                       --Terrain 10	MOUNTAIN
          WindowLoadImage (win, "rock", "worlds\\plugins\\images\\rock.bmp")                               --Terrain 11 ROCK		  
		  WindowLoadImage (win, "desert", "worlds\\plugins\\images\\desert.bmp")                           --Terrain 12 DESERT
		  WindowLoadImage (win, "tundra", "worlds\\plugins\\images\\tundra.bmp")                           --Terrain 13 TUNDRA
		  
		  
		  WindowLoadImage (win, "beach", "worlds\\plugins\\images\\beach.bmp")                             --Terrain 14 BEACH		  
		  WindowLoadImage (win, "hill", "worlds\\plugins\\images\\hill.bmp") 		                       --Terrain 15 HILL
		  
		  
	      WindowLoadImage (win, "ocean", "worlds\\plugins\\images\\ocean.bmp")                             --Terrain 18 OCEAN
	      WindowLoadImage (win, "stream", "worlds\\plugins\\images\\stream.bmp")		                   --Terrain 19	STREAM 




		  WindowLoadImage (win, "ice", "worlds\\plugins\\images\\ice.bmp")                             --Terrain 24 ICE

		  
		  WindowLoadImage (win, "cave", "worlds\\plugins\\images\\cave.bmp")                               --Terrain 27	CAVE
		  WindowLoadImage (win, "city", "worlds\\plugins\\images\\city.bmp")                               --Terrain 28 CITY
		  
		  WindowLoadImage (win, "wasteland", "worlds\\plugins\\images\\wasteland.bmp")		               --Terrain 30 WASTELAND
		  
		  WindowLoadImage (win, "water", "worlds\\plugins\\images\\water.bmp")		                       --Terrain 32 WATER
		  
		  WindowLoadImage (win, "taiga", "worlds\\plugins\\images\\taiga.bmp")                             --Terrain 34 TAIGA
		  WindowLoadImage (win, "road", "worlds\\plugins\\images\\road.bmp")                               --Terrain Road
		  WindowLoadImage (win, "ruins", "worlds\\plugins\\images\\ruins.bmp")                             --Terrain Ruins
		  WindowLoadImage (win, "developed", "worlds\\plugins\\images\\developed.bmp")                     --Terrain Developed	
		  WindowLoadImage (win, "lava", "worlds\\plugins\\images\\lava.bmp")                       --Terrain Lava		  
		  
		  
		  
		  
		  
		  
		  
	      WindowLoadImage (win, "bank", "worlds\\plugins\\images\\bank.bmp")                               --Bank Tile
		  WindowLoadImage (win, "fountain", "worlds\\plugins\\images\\fountain.png")                       --Fountain Tile
		  WindowLoadImage (win, "quest", "worlds\\plugins\\images\\quest.png")                             --Quest Tile
		  WindowLoadImage (win, "waypoint", "worlds\\plugins\\images\\waypoint.bmp")                       --Waypoint Tile
		  WindowLoadImage (win, "warriortrainer", "worlds\\plugins\\images\\warriortrainer.bmp")           --Warrior Trainer Tile
		  WindowLoadImage (win, "thieftrainer", "worlds\\plugins\\images\\thieftrainer.bmp")               --Thief Trainer Tile
		  WindowLoadImage (win, "druidtrainer", "worlds\\plugins\\images\\druidtrainer.bmp")               --Druid Trainer Tile
		  WindowLoadImage (win, "clerictrainer", "worlds\\plugins\\images\\clerictrainer.bmp")             --Cleric Trainer Tile
		  WindowLoadImage (win, "magetrainer", "worlds\\plugins\\images\\magetrainer.bmp")                 --Mage Trainer Tile
		  WindowLoadImage (win, "necromancertrainer", "worlds\\plugins\\images\\necromancertrainer.bmp")   --Necromancer Trainer Tile
		  WindowLoadImage (win, "rangertrainer", "worlds\\plugins\\images\\rangertrainer.bmp")             --Ranger Trainer Tile
		  WindowLoadImage (win, "priest", "worlds\\plugins\\images\\priest.bmp")		                   --Priest Tile
		  WindowLoadImage (win, "alchemyguild", "worlds\\plugins\\images\\alchemyguild.bmp")               --Alchemy Guild Tile		
	      WindowLoadImage (win, "gato", "worlds\\plugins\\images\\gato.png")                               --Gato Tile	
	      WindowLoadImage (win, "moti", "worlds\\plugins\\images\\moti.png")                               --Moti Tile		
	      WindowLoadImage (win, "weaponshop", "worlds\\plugins\\images\\weaponshop.png")                   --Weapon Shop Tile				  
	      WindowLoadImage (win, "armorshop", "worlds\\plugins\\images\\armorshop.png")                     --Armor Shop Tile	
	      WindowLoadImage (win, "itemshop", "worlds\\plugins\\images\\itemshop.png")                       --Item Shop Tile		
	      WindowLoadImage (win, "foodshop", "worlds\\plugins\\images\\foodshop.png")                       --Food Shop Tile	
	      WindowLoadImage (win, "lightshop", "worlds\\plugins\\images\\lightshop.png")                     --Light Shop Tile			  
	      WindowLoadImage (win, "inn", "worlds\\plugins\\images\\inn.png")                                 --Inn Shop Tile	
	      WindowLoadImage (win, "tavern", "worlds\\plugins\\images\\tavern.png")                           --Tavern Tile	
	      WindowLoadImage (win, "inside_brigantes", "worlds\\plugins\\images\\inside_brigantes.png")       --Inside terrain in Brigantes Castle

												  

   -- Handle background texture.
   if room.textimage ~= nil and config.USE_TEXTURES.enabled == true then
      local iwidth = WindowImageInfo(win,room.textimage,2)
      local iheight= WindowImageInfo(win,room.textimage,3)
      local x = 0
      local y = 0

      while y < config.WINDOW.height do
         x = 0
         while x < config.WINDOW.width do
            WindowDrawImage (win, room.textimage, x, y, 0, 0, 1)  -- straight copy
            x = x + iwidth
         end
         y = y + iheight
      end
   end
   


   -- for zooming
   WindowAddHotspot(win,
      "zzz_zoom",
      0, 0, 0, 0,
      "", "", "", "", "mapper.MouseUp",
      "",  -- hint
      miniwin.cursor_arrow, 0)

   WindowScrollwheelHandler (win, "zzz_zoom", "mapper.zoom_map")

   -- set up for initial room, in middle
  -- set up for initial room, in middle
  drawn, drawn_coords, rooms_to_be_drawn, speedwalks, plan_to_draw, area_exits = {}, {}, {}, {}, {}, {}
  depth = 0

   -- insert initial room
   table.insert (rooms_to_be_drawn, add_another_room (uid, {}, config.WINDOW.width / 2, config.WINDOW.height / 2))

   while #rooms_to_be_drawn > 0 and depth < config.SCAN.depth do
      local old_generation = rooms_to_be_drawn
      rooms_to_be_drawn = {}  -- new generation
      for i, part in ipairs (old_generation) do
         draw_room (part.uid, part.path, part.x, part.y)
      end -- for each existing room
      depth = depth + 1
   end -- while all rooms_to_be_drawn

   for area, zone_exit in pairs (area_exits) do
      draw_zone_exit (zone_exit)
   end -- for

   local room_name = room.name
   local name_width = WindowTextWidth (win, FONT_ID, room_name)
   local add_dots = false

   -- truncate name if too long
   local available_width = (config.WINDOW.width - 20 - WindowTextWidth (win, FONT_ID, "*?"))
   while name_width > available_width do
      room_name = room_name:sub(1, -3)
      name_width = WindowTextWidth (win, FONT_ID, room_name .. "...")
      add_dots = true
      if room_name == "" then
         break
      end
   end -- while

   if add_dots then
      room_name = room_name .. "..."
   end -- if

   Theme.DrawBorder(win)

   -- room name
   title_bottom = Theme.DrawTitleBar(win, FONT_ID, room_name)

   if config.SHOW_ROOM_ID then
      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, "ID: "..uid)) / 2,   -- left
         title_bottom,    -- top
         "ID: "..uid, false, false)
   end
      if config.SHOW_ROOM_NOTES then
      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, "Note: "..room.notes)) / 2,   -- left
         title_bottom,    -- top
         "Notes: "..room.notes, false, false)
   end

   -- area name

   local areaname = room.area

   if areaname then
      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, areaname)) / 2,   -- left
         config.WINDOW.height - 4 - font_height,    -- top
         areaname:gsub("^%l", string.upper), false, false)
   end -- if area known

   -- configure?

   if draw_configure_box then
      draw_configuration ()
   else
      WindowShow(config_win, false)
      local x = 2
      local y = math.max(2, (title_bottom-font_height)/2)
      local text_width = Theme.DrawTextBox(win, FONT_ID,
         x,   -- left
         y-2,   -- top
         "*", false, false)

      WindowAddHotspot(win, "<configure>",
         x-2, y-4, x+text_width, y + font_height,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "",  -- mousedown
         "",  -- cancelmousedown
         "mapper.mouseup_configure",  -- mouseup
         "Click to configure map",
         miniwin.cursor_plus, 0)
   end -- if

   if type (show_help) == "function" then
      local x = config.WINDOW.width - WindowTextWidth (win, FONT_ID, "?") - 6
      local y = math.max(2, (title_bottom-font_height)/2)
      local text_width = Theme.DrawTextBox(win, FONT_ID,
         x-1,   -- left
         y-2,   -- top
         "?", false, false)

      WindowAddHotspot(win, "<help>",
         x-3, y-4, x+text_width+3, y + font_height,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "",  -- mousedown
         "",  -- cancelmousedown
         "mapper.show_help",  -- mouseup
         "Click for help",
         miniwin.cursor_help, 0)
   end -- if

   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   -- make sure window visible
   WindowShow (win, not window_hidden)

   last_drawn = uid  -- last room number we drew (for zooming)

   local end_time = utils.timer ()

   -- timing stuff
   if timing then
      local count= 0
      for k in pairs (drawn) do
         count = count + 1
      end
      print (string.format ("Time to draw %i rooms = %0.3f seconds, search depth = %i", count, end_time - start_time, depth))

      total_times_drawn = total_times_drawn + 1
      total_time_taken = total_time_taken + end_time - start_time

      print (string.format ("Total times map drawn = %i, average time to draw = %0.3f seconds",
         total_times_drawn,
         total_time_taken / total_times_drawn))
		             draw_next_batch_of_rooms()
   end -- if

   -- let them move it around
   movewindow.add_drag_handler (win, 0, 0, 0, title_bottom)
   
  -- end -- if

--   if show_timing then
      print("Time elapsed drawing ", utils.timer()-outer_time)
--   end

   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end -- draw

local credits = {
   "CleftMUSH Mapper",
   string.format ("Version %0.1f", VERSION),
   "Made for Cleft of Dimensions by Asmodeus",
   "Based on work by Nick Gammon and Fiendish",
   "World: "..WorldName (),
   GetInfo (3),
}

-- call once to initialize the mapper
function init (t)

   -- make copy of colours, sizes etc.

   config = t.config
   assert (type (config) == "table", "No 'config' table supplied to mapper.")

   supplied_get_room = t.get_room
   assert (type (supplied_get_room) == "function", "No 'get_room' function supplied to mapper.")

   show_help = t.show_help     -- "help" function
   room_click = t.room_click   -- RH mouse-click function
  room_mouseover = t.room_mouseover -- mouse-over function
  room_cancelmouseover = t.room_cancelmouseover -- cancel mouse-over function
   timing = t.timing           -- true for timing info
   show_completed = t.show_completed  -- true to show "Speedwalk completed." message
   show_other_areas = t.show_other_areas  -- true to show other areas
   show_up_down = t.show_up_down        -- true to show up or down
   show_area_exits = t.show_area_exits  -- true to show area exits
   speedwalk_prefix = t.speedwalk_prefix  -- how to speedwalk (prefix)

   -- force some config defaults if not supplied
   for k, v in pairs (default_config) do
      config[k] = config[k] or v
   end -- for

   win = GetPluginID () .. "_mapper"
   config_win = GetPluginID () .. "_z_config_win"

   WindowCreate (win, 0, 0, 0, 0, 0, 0, 0)
   WindowCreate(config_win, 0, 0, 0, 0, 0, 0, 0)

   -- add the fonts
   WindowFont (win, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (win, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (config_win, CONFIG_FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (config_win, CONFIG_FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)

   -- see how high it is
   font_height = WindowFontInfo (win, FONT_ID, 1)  -- height

   -- find where window was last time
   windowinfo = movewindow.install (win, miniwin.pos_bottom_right, miniwin.create_absolute_location , true, {config_win}, {mouseup=MouseUp, mousedown=LeftClickOnly, dragmove=LeftClickOnly, dragrelease=LeftClickOnly}, {x=default_x, y=default_y})

   -- calculate box sizes, arrows, connecting lines etc.
    AREA_ROOM_INFO = build_room_info()

   WindowCreate (win,
      windowinfo.window_left,
      windowinfo.window_top,
      config.WINDOW.width,
      config.WINDOW.height,
      windowinfo.window_mode,   -- top right
      windowinfo.window_flags,
      Theme.PRIMARY_BODY)

   -- let them move it around
   movewindow.add_drag_handler (win, 0, 0, 0, 0)

   local top = (config.WINDOW.height - #credits * font_height) /2

   for _, v in ipairs (credits) do
      local width = WindowTextWidth (win, FONT_ID, v)
      local left = (config.WINDOW.width - width) / 2
      WindowText (win, FONT_ID, v, left, top, 0, 0, Theme.BODY_TEXT)
      top = top + font_height
   end -- for

   Theme.DrawBorder(win)
   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   WindowShow (win, not window_hidden)
   WindowShow (config_win, false)

end -- init

function MouseUp(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      right_click_menu()
   end
   return true
end

function LeftClickOnly(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   return false
end



function right_click_menu()
   menustring = "Bring To Front|Send To Back"

   rc, a, b, c = CallPlugin("60840c9013c7cc57777ae0ac", "getCurrentState")
   if rc == 0 and a == true then
      if b == 1 then
         menustring = menustring.."|-|Show Continent Bigmap"
      elseif c == 1 then
         menustring = menustring.."|-|Merge Continent Bigmap Into GMCP Mapper"
      end
   end

   result = WindowMenu (win,
      WindowInfo (win, 14),  -- x position
      WindowInfo (win, 15),   -- y position
      menustring) -- content
   if result == "Bring To Front" then
      CallPlugin("462b665ecb569efbf261422f","boostMe", win)
   elseif result == "Send To Back" then
      CallPlugin("462b665ecb569efbf261422f","dropMe", win)
   elseif result == "Show Continent Bigmap" then
      Execute("bigmap on")
   elseif result == "Merge Continent Bigmap Into GMCP Mapper" then
      Execute("bigmap merge")
   end
end

function zoom_in ()
   if last_drawn and ROOM_SIZE < 40 then
      ROOM_SIZE = ROOM_SIZE + 2
      DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM + 2
      build_room_info ()
      draw (last_drawn)
      SaveState()
   end -- if
end -- zoom_in


function zoom_out ()
   if last_drawn and ROOM_SIZE > 4 then
      ROOM_SIZE = ROOM_SIZE - 2
      DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM - 2
      build_room_info ()
      draw (last_drawn)
      SaveState()
   end -- if
end -- zoom_out

function mapprint (...)
   local old_note_colour = GetNoteColourFore ()
   SetNoteColourFore(MAPPER_NOTE_COLOUR.colour)
   print (...)
   SetNoteColourFore (old_note_colour)
end -- mapprint

function maperror (...)
   local old_note_colour = GetNoteColourFore ()
   SetNoteColourFore(ColourNameToRGB "red")
   print (...)
   SetNoteColourFore (old_note_colour)
end -- maperror

function show()
   WindowShow(win, true)
   hidden = false
end -- show

function hide()
   WindowShow(win, false)
   hidden = true
end -- hide

function save_state ()
   SetVariable("ROOM_SIZE", ROOM_SIZE)
   SetVariable("DISTANCE_TO_NEXT_ROOM", DISTANCE_TO_NEXT_ROOM)
   if WindowInfo(win,1) and WindowInfo(win,5) then
      movewindow.save_state (win)
      config.WINDOW.width = WindowInfo(win, 3)
      config.WINDOW.height = WindowInfo(win, 4)
   end
end -- save_state

function hyperlinkGoto(uid)
   mapper.goto(uid)
   for i,v in ipairs(last_result_list) do
      if uid == v then
         next_result_index = i
         break
      end
   end
end

require "serialize"



function gotoNextResult(which)
   if tonumber(which) == nil then
      if next_result_index ~= nil then
         next_result_index = next_result_index+1
         if next_result_index <= #last_result_list then
            mapper.goto(last_result_list[next_result_index])
            return
         else
            next_result_index = nil
         end
      end
      ColourNote(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","NEXT ERROR: No more NEXT results left.")
   else
      next_result_index = tonumber(which)
      if (next_result_index > 0) and (next_result_index <= #last_result_list) then
         mapper.goto(last_result_list[next_result_index])
         return
      else
         ColourNote(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","NEXT ERROR: There is no NEXT result #"..next_result_index..".")
         next_result_index = nil
      end
   end
end

function goto(uid)
   find (nil,
      {{uid=uid, reason=true}},
      0,
      false,  -- show vnum?
      1,          -- how many to expect
      true        -- just walk there
   )
end

-- generic room finder
-- dests is a list of room/reason pairs where reason is either true (meaning generic) or a string to find
-- show_uid is true if you want the room uid to be displayed
-- expected_count is the number we expect to find (eg. the number found on a database)
-- if 'walk' is true, we walk to the first match rather than displaying hyperlinks
-- if fcb is a function, it is called back after displaying each line
-- quick_list determines whether we pathfind every destination in advance to be able to sort by distance
function find (f, show_uid, expected_count, walk, fcb)

  if not check_we_can_find () then
    return
  end -- if

  if fcb then
    assert (type (fcb) == "function")
  end -- if

  local start_time = utils.timer ()
  local paths, count, depth = find_paths (current_room, f)
  local end_time = utils.timer ()

  local t = {}
  local found_count = 0
  for k in pairs (paths) do
    table.insert (t, k)
    found_count = found_count + 1
  end -- for

  -- timing stuff
  if timing then
    print (string.format ("Time to search %i rooms = %0.3f seconds, search depth = %i",
                          count, end_time - start_time, depth))
  end -- if

  if found_count == 0 then
    mapprint ("No matches.")
    return
  end -- if

  if found_count == 1 and walk then
    uid, item = next (paths, nil)
    mapprint ("Walking to:", rooms [uid].name)
    start_speedwalk (item.path)
    return
  end -- if walking wanted

  -- sort so closest ones are first
  table.sort (t, function (a, b) return #paths [a].path < #paths [b].path end )

  hyperlink_paths = {}

  for _, uid in ipairs (t) do
    local room = rooms [uid] -- ought to exist or wouldn't be in table

    assert (room, "Room " .. uid .. " is not in rooms table.")

    if current_room == uid then
      mapprint (room.name, "is the room you are in")
    else
      local distance = #paths [uid].path .. " room"
      if #paths [uid].path > 1 then
        distance = distance .. "s"
      end -- if
      distance = distance .. " away"

      local room_name = room.name
      if show_uid then
        room_name = room_name .. " (" .. uid .. ")"
      end -- if

      -- in case the same UID shows up later, it is only valid from the same room
      local hash = utils.tohex (utils.md5 (tostring (current_room) .. "<-->" .. tostring (uid)))
         table.insert(last_result_list, uid)
      Hyperlink ("!!" .. GetPluginID () .. ":mapper.do_hyperlink(" .. hash .. ")",
                 "["..#last_result_list.."] "..room_name, "Click to speedwalk there (" .. distance .. ")", "", "", false)
      local info = ""
      if type (paths [uid].reason) == "string" and paths [uid].reason ~= "" then
        info = " [" .. paths [uid].reason .. "]"
      end -- if
      mapprint (" - " .. distance .. info) -- new line

      -- callback to display extra stuff (like find context, room description)
      if fcb then
        fcb (uid)
      end -- if callback
      hyperlink_paths [hash] = paths [uid].path
    end -- if
  end -- for each room

  if expected_count and found_count < expected_count then
    local diff = expected_count - found_count
    local were, matches = "were", "matches"
    if diff == 1 then
      were, matches = "was", "match"
    end -- if
    mapprint ("There", were, diff, matches,
              "which I could not find a path to within",
              config.SCAN.depth, "rooms.")
  end -- if
   if not walk then
      last_result_list = {}
      next_result_index = 0
   end
end -- map_find_things

function do_hyperlink (hash)

  if not check_connected () then
    return
  end -- if

  if not hyperlink_paths or not hyperlink_paths [hash] then
    mapprint ("Hyperlink is no longer valid, as you have moved.")
    return
  end -- if

  local path = hyperlink_paths [hash]
  if #path > 0 then
    last_hyperlink_uid = path [#path].uid
  end -- if
  start_speedwalk (path)

end -- do_hyperlink

-- build a speedwalk from a path into a string

function build_speedwalk (path)

 -- build speedwalk string (collect identical directions)
  local tspeed = {}
  for _, dir in ipairs (path) do
    local n = #tspeed
    if n == 0 then
      table.insert (tspeed, { dir = dir.dir, count = 1 })
    else
      if tspeed [n].dir == dir.dir then
        tspeed [n].count = tspeed [n].count + 1
      else
        table.insert (tspeed, { dir = dir.dir, count = 1 })
      end -- if different direction
    end -- if
  end -- for

  if #tspeed == 0 then
    return
  end -- nowhere to go (current room?)

  -- now build string like: 2n3e4(sw)
  local s = ""

  for _, dir in ipairs (tspeed) do
    if dir.count > 1 then
      s = s .. dir.count
    end -- if
    if #dir.dir == 1 then
      s = s .. dir.dir
    else
      s = s .. "(" .. dir.dir .. ")"
    end -- if
    s = s .. " "
  end -- if

  return s

end -- build_speedwalk



-- start a speedwalk to a path

function start_speedwalk (path)

  if not check_connected () then
    return
  end -- if

  if current_speedwalk and #current_speedwalk > 0 then
    mapprint ("You are already speedwalking! (Ctrl + LH-click on any room to cancel)")
    return
  end -- if

  current_speedwalk = path

  if current_speedwalk then
    if #current_speedwalk > 0 then
      last_speedwalk_uid = current_speedwalk [#current_speedwalk].uid

      -- fast speedwalk: just send # 4s 3e  etc.
      if type (speedwalk_prefix) == "string" and speedwalk_prefix ~= "" then
        local s = speedwalk_prefix .. " " .. build_speedwalk (path)
        Execute (s)
        current_speedwalk = nil
        return
      end -- if

      local dir = table.remove (current_speedwalk, 1)
      local room = get_room (dir.uid)
      walk_to_room_name = room.name
      SetStatus ("Walking " .. (expand_direction [dir.dir] or dir.dir) ..
                 " to " .. walk_to_room_name ..
                 ". Speedwalks to go: " .. #current_speedwalk + 1)
      Execute (dir.dir)
      expected_room = dir.uid
    else
      cancel_speedwalk ()
    end -- if any left
  end -- if

end -- start_speedwalk

-- cancel the current speedwalk

function cancel_speedwalk ()
  if current_speedwalk and #current_speedwalk > 0 then
    mapprint "Speedwalk cancelled."
  end -- if
  current_speedwalk = nil
  expected_room = nil
  hyperlink_paths = nil
  SetStatus ("Ready")
end -- cancel_speedwalk


-- ------------------------------------------------------------------
-- mouse-up handlers (need to be exposed)
-- these are for clicking on the map, or the configuration box
-- ------------------------------------------------------------------

function mouseup_room (flags, hotspot_id)
  local uid = hotspot_id

  if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then

    -- RH click

    if type (room_click) == "function" then
      room_click (uid, flags)
    end -- if

    return
  end -- if RH click

  -- here for LH click

   -- Control key down?
  if bit.band (flags, miniwin.hotspot_got_control) ~= 0 then
    cancel_speedwalk ()
    return
  end -- if ctrl-LH click

  start_speedwalk (speedwalks [uid])

end -- mouseup_room
function mouseover_room (flags, hotspot_id)
  if type (room_mouseover) == "function" then
    room_mouseover (hotspot_id, flags)  -- moused over
  end -- if
end -- mouseover_room

function cancelmouseover_room (flags, hotspot_id)
  if type (room_cancelmouseover) == "function" then
    room_cancelmouseover (hotspot_id, flags)  -- cancled mouse over
  end -- if
end -- cancelmouseover_room

function mouseup_configure (flags, hotspot_id)
  draw_configure_box = true
  draw (current_room)
end -- mouseup_configure

function mouseup_close_configure (flags, hotspot_id)
   draw_configure_box = false
   SaveState()
   draw (current_room)
end -- mouseup_player 	

function mouseup_change_colour (flags, hotspot_id)

   local which = string.match (hotspot_id, "^$colour:([%a%d_]+)$")
   if not which then
      return  -- strange ...
   end -- not found

   local newcolour = PickColour (config [which].colour)

   if newcolour == -1 then
      return
   end -- if dismissed

   config [which].colour = newcolour

   draw (current_room)
end -- mouseup_change_colour
function mouseup_change_delay (flags, hotspot_id)

  local delay = get_number_from_user ("Choose speedwalk delay time (0 to 10 seconds)", "Delay in seconds", config.DELAY.time, 0, 10, true)

  if not delay then
    return
  end -- if dismissed

  config.DELAY.time = delay
  draw (current_room)
end -- mouseup_change_delay

function mouseup_change_font (flags, hotspot_id)

   local newfont =  utils.fontpicker (config.FONT.name, config.FONT.size, ROOM_NAME_TEXT.colour)

   if not newfont then
      return
   end -- if dismissed

   config.FONT.name = newfont.name

   if newfont.size > 12 then
      utils.msgbox ("Maximum allowed font size is 12 points.", "Font too large", "ok", "!", 1)
   else
      config.FONT.size = newfont.size
   end -- if

   ROOM_NAME_TEXT.colour = newfont.colour

   -- reload new font
   WindowFont (win, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (win, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (config_win, CONFIG_FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (config_win, CONFIG_FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)

   -- see how high it is
   font_height = WindowFontInfo (win, FONT_ID, 1)  -- height

   draw (current_room)
end -- mouseup_change_font

function mouseup_change_depth (flags, hotspot_id)

   local depth = get_number_from_user ("Choose scan depth (3 to 300 rooms)", "Depth", config.SCAN.depth, 3, 300)

   if not depth then
      return
   end -- if dismissed

   config.SCAN.depth = depth
   draw (current_room)
end -- mouseup_change_depth

function mouseup_change_area_textures (flags, hotspot_id)
   if config.USE_TEXTURES.enabled == true then
      config.USE_TEXTURES.enabled = false
   else
      config.USE_TEXTURES.enabled = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_show_id (flags, hotspot_id)
   if config.SHOW_ROOM_ID == true then
      config.SHOW_ROOM_ID = false
	  
   else
      config.SHOW_ROOM_ID = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_show_notes (flags, hotspot_id)
   if config.SHOW_ROOM_NOTES == true then
      config.SHOW_ROOM_NOTES = false
	  
   else
      config.SHOW_ROOM_NOTES = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_show_tiles (flags, hotspot_id)
   if config.SHOW_TILES == true then
      config.SHOW_TILES = false
	  CallPlugin("dd07d6dbe73fe0bd02ddb62c", "SetVariable", "tile_mode", "0")
	  SaveState()
	  draw (current_room)
	  
   else
      config.SHOW_TILES = true
	 CallPlugin("dd07d6dbe73fe0bd02ddb62c", "SetVariable", "tile_mode", "1")
	 SaveState()
	 draw (current_room)
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_show_area_exits (flags, hotspot_id)
   if config.SHOW_AREA_EXITS == true then
      config.SHOW_AREA_EXITS = false
   else
      config.SHOW_AREA_EXITS = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function zoom_map (flags, hotspot_id)
   if bit.band (flags, 0x100) ~= 0 then
      zoom_out ()
   else
      zoom_in ()
   end -- if
end -- zoom_map

function resize_mouse_down(flags, hotspot_id)
   startx, starty = WindowInfo (win, 17), WindowInfo (win, 18)
end

function resize_release_callback()
   config.WINDOW.width = WindowInfo(win, 3)
   config.WINDOW.height = WindowInfo(win, 4)
   draw(current_room)
end

function resize_move_callback()
   if GetPluginVariable("c293f9e7f04dde889f65cb90", "lock_down_miniwindows") == "1" then
      return
   end
   local posx, posy = WindowInfo (win, 17), WindowInfo (win, 18)

   local width = WindowInfo(win, 3) + posx - startx
   startx = posx
   if (50 > width) then
      width = 50
      startx = windowinfo.window_left + width
   elseif (windowinfo.window_left + width > GetInfo(281)) then
      width = GetInfo(281) - windowinfo.window_left
      startx = GetInfo(281)
   end

   local height = WindowInfo(win, 4) + posy - starty
   starty = posy
   if (50 > height) then
      height = 50
      starty = windowinfo.window_top + height
   elseif (windowinfo.window_top + height > GetInfo(280)) then
      height = GetInfo(280) - windowinfo.window_top
      starty = GetInfo(280)
   end

   WindowResize(win, width, height, BACKGROUND_COLOUR.colour)
   Theme.DrawBorder(win)
   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   WindowShow(win, true)
end
function draw_edge()
   -- draw edge frame.
   check (WindowRectOp (win, 1, 0, 0, 0, 0, 0xE8E8E8, 15))
   check (WindowRectOp (win, 1, 1, 1, -1, -1, 0x777777, 15))
   add_resize_tag()
end