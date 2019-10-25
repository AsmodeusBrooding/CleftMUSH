--[[
function sec2min(sec) returns min, sec
function str2time(s) --turns a us date/time string into unix time integer eg "2013-10-29 12:59:52"
function sec2fstr(sec) -- returns a formated string showing number of minutes and seconds (used in plugin_instance)
--]]


function sec2min(sec)
 local min = 0
 min = math.floor(sec/60)
 sec = sec - (min*60)
 return min, sec 
end


function str2time(s)
--turns a us date/time string into unix time integer
--eg "2013-10-29 12:59:52"

 t = utils.split(s, " ")
 t[1] = utils.split(t[1], "-")
 t[2] = utils.split(t[2], ":")

 d = {}

 d.year = t[1][1]
 d.month = t[1][2]
 d.day = t[1][3]
 d.hour = t[2][1]
 d.min = t[2][2]
 d.sec = t[2][3]
 return os.time(d)
end



function sec2fstr(sec)
 local min=0

 if sec >= 60 then
  min=math.modf(sec/60)
  sec=math.fmod(sec, 60)
 end

 return string.format("%i mins %i secs", min, sec)
end