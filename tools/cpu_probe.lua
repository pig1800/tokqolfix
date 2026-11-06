local outdir = "D:/EMU/NES/tokqolfix/out/stateprobe"
local statepath = "D:/EMU/NES/SaveStates/Tenchi o Kurau (Japan) (Rev 1)_11.mss"
local frame = 0
local loaded = false
local function writefile(name, data) local f=assert(io.open(outdir.."/"..name,"wb")); f:write(data); f:close() end
local function onFrame()
  frame = frame + 1
  if frame == 3 then
    local f=io.open(statepath,"rb"); local d=f:read("*a"); f:close(); emu.loadSavestate(d); loaded=true
  end
  if frame == 6 and loaded then
    local st=emu.getCpuState()
    local lines={}
    for k,v in pairs(st) do lines[#lines+1]=tostring(k).."="..tostring(v) end
    table.sort(lines)
    writefile("cpu.txt", table.concat(lines,"\n"))
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.endFrame)
