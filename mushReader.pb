#lua=1
EnableExplicit
CompilerIf #lua
  XIncludeFile "lua.pbi"
CompilerEndIf
Global jfw.l, we.l
Prototype.l proto_nvdaController_speakText(text.p-unicode)
Prototype.l proto_nvdaController_testIfRunning()
Prototype.l proto_DolAccess_GetSystem()
Prototype.l proto_DolAccess_Command(text.l, length.l, cmd.l)
Prototype.l proto_DolAccess_Action(action.l)

Global nvdaController_speakText.proto_nvdaController_speakText
Global nvdaController_testIfRunning.proto_nvdaController_testIfRunning
Global DolAccess_GetSystem.proto_DolAccess_GetSystem
Global DolAccess_Command.proto_DolAccess_Command
Global DolAccess_Action.proto_DolAccess_Action
Procedure.l nvda_running()
  If nvdaController_testIfRunning() = 0
    ProcedureReturn 1
  Else
    ProcedureReturn 0
  EndIf
  ProcedureReturn 1
EndProcedure

CompilerIf #lua
  DeclareCDLL.l nvda_say(*l)
Structure luaL_reg
name.l
*func
EndStructure
CompilerEndIf
Declare jfwRunning()
Declare we_running()
Declare halRunning()

Procedure nvda_stop()
  If halRunning()
  DolAccess_Action(141)  
  ElseIf nvda_running()
  CallFunction(0, "nvdaController_cancelSpeech")
ElseIf jfw > 0 And jfwRunning()
  dhCallMethod(jfw, "SayString(%s,%i)", @"", 1)
ElseIf we > 0 And we_running()
  dhCallMethod(we, "silence")
EndIf

  ProcedureReturn 1
EndProcedure
Procedure jfwRunning()
    Protected tmp = 0
      ;jaws before 16
    If FindWindow_("JFWUI2", "JAWS")
    ProcedureReturn 1
  EndIf
  If jfw = 0
    ProcedureReturn 0
  EndIf
  
  dhGetValue("%d", @tmp, jfw, "SayString(%s,%i)", @"", 0)
  If tmp <> 0
    ProcedureReturn 1
  EndIf
    ProcedureReturn 0
  EndProcedure
  ProcedureCDLL we_running()
  If FindWindow_("GWMExternalControl", "External Control")
    ProcedureReturn 1
  Else
    ProcedureReturn 0
      EndIf
    ProcedureReturn 1
  EndProcedure
  ProcedureCDLL halRunning()
    If DolAccess_GetSystem() > 0
      ProcedureReturn 1
    Else
      ProcedureReturn 0
    EndIf
  EndProcedure
  
  CompilerIf #lua
    Global Dim table.luaL_reg(2)
  CompilerEndIf
  ProcedureDLL AttachProcess(instance)
    CompilerIf #lua
      table(0)\name = @"say"
table(0)\func = @nvda_say()
table(1)\name=@"stop"
table(1)\func=@nvda_stop()
CompilerEndIf
OpenLibrary(0, "nvdaControllerClient32.dll")
nvdaController_speakText = GetFunction(0, "nvdaController_speakText")
nvdaController_testIfRunning = GetFunction(0, "nvdaController_testIfRunning")
OpenLibrary(1, "dolapi.dll")
DolAccess_GetSystem = GetFunction(1, "_DolAccess_GetSystem@0")
DolAccess_Command = GetFunction(1, "_DolAccess_Command@12")
DolAccess_Action = GetFunction(1, "_DolAccess_Action@4")
  jfw = dhCreateObject("freedomsci.jawsapi")
  If jfw = 0
    jfw = dhCreateObject("jfwapi")
  EndIf
  we = dhCreateObject("gwspeak.speak")

EndProcedure
ProcedureCDLL say(st.s)
  Protected *ptr.String, *addr
  Protected *buf
  *addr = @st
  *ptr.string = @st
  If halRunning()
  *buf = AllocateMemory(Len(st)*2+2)
  PokeS(*buf, st, Len(st), #PB_Unicode)
  ;DolAccess_Command(st, (Len(st)+1)*2, 1)  
  DolAccess_Command(*buf, Len(st)*2+2, 1)  
  FreeMemory(*buf)
  
ElseIf nvda_running()
  nvdaController_speakText(st)
ElseIf jfw > 0 And jfwRunning()
  dhCallMethod(jfw, "SayString(%s, %i)", @st, 0)
ElseIf we > 0 And we_Running()
  dhCallMethod(we, "SpeakString(%s)", @st)
  EndIf
  ProcedureReturn 1
EndProcedure
CompilerIf #lua
  ProcedureCDLL luaopen_audio(*l)
    luaL_register(*l, "nvda", @table(0))
ProcedureReturn 1
EndProcedure
 ProcedureCDLL.l  nvda_say(*l)
Protected *string = luaL_checkstring(*l, 1)
Protected st.s = PeekS(*string)
say(st)
ProcedureReturn 1
EndProcedure
CompilerEndIf

; IDE Options = PureBasic 5.22 LTS (Windows - x86)
; ExecutableFormat = Shared Dll
; CursorPosition = 3
; Folding = -8-
; EnableThread
; Executable = mushReader.dll