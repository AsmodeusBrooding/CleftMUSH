----------------------------------------------------------------------------------------

                      CleftMUSH Coding DO list

----------------------------------------------------------------------------------------

OBJECTS TO DO ARE LABELED SIMPLY BY "DO", AND FUNCTIONS ARE NAMED BY

[Function Number(1)] -for- example.. You will see an "- IN PROGRESS -"

section for things -in- progress: I want to include priorities as well,

which will be included right before DO -and- will have a number of 1-10, where

priority 1 is the highest, -and- priority 10 is the lowest: (5) DO would be

a medium level of priority, where 10 would be low priority.

Below will be the MAIN DO list, followed by each individual item, -and-

potential fixes/additions/comments to/-for- the items

"======================================================================================="

PUT IDEAS OF THINGS TO DO  IN  HERE, ALONG WITH A PRIORITY

   (NUMBER) is priority [Y] or [N] is if you know how to do it already

- [ ] \(1\)\[N\] DO Fix cexits to prioritize non cardinal/intercardinal directions

- [ ] \(3\)\[Y\] DO Create troubleshooting help page and client help page

- [ ] \(5\)\[Y\] DO Add classes to group window, MAYBE with icons

- [ ] \(5\)\[Y\] DO fix "logging to file" on chat window: this will probably finish the window

- [ ] \(5\)\[Y\] DO Add Bring to front/send to back functionality to all windows

- [ ] \(5\)\[Y\] DO Make non-graphical map special rooms show hashes and such

- [x] \(5\)\[Y\] DO Make action bar stay hidden if you have hidden it

- [ ] \(5\)\[Y\] DO Make volume settings save  Use SetVariable and GetVariable

  Will need to GetVariable every time you logon or reconnect, so it

  can set the volume when you reconnect or login



"======================================================================================="

========================= SOUNDS DO SECTION ================================

        ALL SOUNDS GO IN THE CLEFTMUSH COD_HANDLER PLUGIN

"DONE"  DO  [LEENE BELL SOUND]

 Ding, dong, ding, dong. Leene's Bell reverberates through the city.

DO  [OWLITE ACTIVATION SOUND]

dingadingling

DO  [SAILNG SOUND]

  NO STRING YET

DO  [Docking/Trip Successful Sound]

  Sunsnug's:

Against all odds, the barrel boat arrives safely in one piece!

DO  [Slot Machine: Begin, Success, Failure]

  NO STRING YET

"DONE"  DO  [Bambino Bombs]

 ^The Bambino Bomb violently explodes\!\!\!$

DO  [NAYRU'S LOVE SOUND]

HelloWorld is surrounded by an aura that reflects his character.

You are surrounded by an aura that reflects your character.

(We could make a trigger that anchors the end of the line " surrounded by an aura that reflects your character."

or make a more complex one roughly like "^%w (is|are) surrounded by an aura that reflects (his|her|...) character.$"

or two simple ones "^%w is surrounded by an aura that reflects (his|her|...) character.$" and "^You are surrounded by an aura that reflects your character.$")

DO [ZOMBIFY HEAL SOUND]

A Sanguine Ahriman is annihilated by your healing!!! (366)

A Sanguine Ahriman is annihilated by Abaril's healing!!! (366)

Abaril's healing annihilates a Sanguine Ahriman!!! (323)



DO [PROTECT SOUND]

   NO STRING YET

DO [FIRA SOUND]

   NO STRING YET

DO [BETTER SYPHON SOUND]



DO  [Mining Sounds]

You stop your digging, having found nothing.

You notice something in the large stalactite and stop your digging.

Something shrieks as you strike it with your tool!

         merchant ship docking sound or chobin squeakin sound

            A merchant's ship docks at the island.

A chobin in a large hat hops off the boat and begins squeaking orders.

                           hop on sound

    The chobin captain says 'Fine, get on the boat, if it will shut you up.'

                           sound for ship horn or something

  The chobin captain says 'Let's get this ship on its way! Today, please!'

The crew members scramble and set the ship sailin'.

                     MORE MISC BOAT SOUNDS TO ADD

The chobin captain hops off the boat and begins squeaking orders.

You say 'let me off the boat.'

A chobin sailor says 'All righty. We're docked at the Rat Cantina.'



A palico drops a box with a loud THUD!

The palico captain says 'Nya! Watch mewrself!'

The palico yowls while picking up the dropped box and scurrying away.

             The palico captain says 'Meowll right, let's purrack it up and move meowt!'

The palico captain and all the sailors board the ship and it immediately heads out to the open ocean.



 A strange boat made up of a bunch of barrels tied together docks at the island.

A cat with an eyepatch hops off of the boat and begins meowing orders at scrambling sailors.



                     A whirlwind swooshes by, carrying you away into the air.



An Immortal has restored you.

  You are not affected by any spells.



You are affected by:



combomagic   indefinitely, level 67.



You have cooldowns on:



Black Cauldron on cooldown for 2 seconds.





========================= MAP ICONS DO SECTION ================================

DO TICKET TAKER

DO TICKET SHOP

DO FERRY

DO PETSHOP

"DONE"  DO TAVERN





"======================================================================================="



- [ ] (5) DO Add Bring to front/send to back functionality to all windows



 Below is the code that goes in the right click menu of each plugin.

 CallPlugin is used to call functions from other plugins, where the first

 argument is the plugin ID, the second is the function name, and the

 third is the window ID name: Throw this into an existing plugin, or

 add [Function Number(1)] to a miniwindow plugin with no existing right

 click functionality.





 if result == 1 then

   CallPlugin("462b665ecb569efbf261422f","boostMe", win)  Bring to Front

 elseif result == 2 then

   CallPlugin("462b665ecb569efbf261422f","dropMe", win)  Send to Back

 end

 SaveState()







[Function Number(1)[          IN PROGRESS            ]





 function right_click_menu()

local x, y = WindowInfo(winid, 14), WindowInfo(winid, 15)

local str = "!"


  str = str.."||Bring to Front"

 str = str.."||Send to Back"



  opt = WindowMenu(winid, x, y, str)

if opt == "" then

return

end

opt = tonumber(opt)

  if opt == 1 then  Bring to Front

    CallPlugin("462b665ecb569efbf261422f","boostMe", winid)

    print("Bring to Front")

    SaveState()

elseif opt == 2 then  Send to back

    CallPlugin("462b665ecb569efbf261422f","dropMe", winid)

    print("Sent to Back")

    SaveState()

   end

window(true)

end





"IDEAS SECTION"

 PUT ALL IDEAS IN HERE, THIS IS FOR USERS
