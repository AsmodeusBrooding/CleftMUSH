--[[
lua_convert.lua
num2fstr(n, dp) - k/m/b
tobool(b)
convert_to_inches(s)
--]]

--converts a number into a formated string k/mil/bil
function num2fstr(n, dp)
  if tonumber(n) == nil then
  print("not a valid number")
  return nil
 end
 dp = dp or 3
 f = "\%\."..dp.."f"
 n = tonumber(n)
 if n>= 1000000000 then
  n = string.format(f.."b", n/1000000000)
 elseif n>= 1000000 then
  n = string.format(f.."m", n/1000000)
elseif n >= 1000 then
 n = string.format(f.."k",  n/1000)
else
 n = string.format("%i",  n)
 end
 return n
end

function tobool (b)
  if type(b) == "boolean" then
   return b
  elseif tonumber(b) ~= nil then
   b = tonumber(b)
   if b == 0 then
    return false
   elseif b == 1 then
    return true
   else
    return nil
   end
  elseif type(b) == "string" then
   if string.lower(b) == "true" then
    return true
   elseif string.lower(b) == "false" then
    return false
   else
    return nil
   end
  else
   return nil
  end
 end


--patern group to true var
function pg2var(v)
 if v=="" then
  return nil
 else
  return v
 end
end


re_feet_and_inches = rex.new("^([0-9]+)\'([0-9]+)\"$")

function convert_to_inches(line)
 --converts feet'inches" to inches
 local ret
 if type(line)=="string" then
  local _, _, wc =  re_feet_and_inches:match(line)
  if wc then
   ret = (wc[1]*12)+wc[2]
  end
 end
 return ret
end
