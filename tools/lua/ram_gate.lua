-- Revision-11 RAM gate over the standard path + town (6000 frames):
--  (1) hack code never writes battery RAM ($6000-$7FFF);
--  (2) game code never writes the hack state ($0102-$0103, $0131-$017F);
--  (3) hack code writes nothing in internal RAM outside its own state, the
--      sprite-0 slot ($0200-$0203), the text-engine variables it drives and
--      the stack;
--  (4) minimum stack pointer seen while hack code runs.
local outdir = "D:/EMU/NES/tokqolfix/out/test/r11"
local frame = 0
local log = assert(io.open(outdir .. "/ram_gate.txt", "w"))
local n1, n2, n3 = 0, 0, 0
local ex1, ex2, ex3 = {}, {}, {}
local minsp_hack, minsp_any = 0xFF, 0xFF
local function onInput()
  if frame >= 300 and frame < 600 and (frame % 60) < 3 then emu.setInput({start=true}, 0)
  elseif frame >= 600 and frame < 760 and (frame % 60) < 3 then emu.setInput({a=true}, 0)
  elseif frame >= 800 and frame < 4200 then
    local phase = math.floor((frame - 800) / 40) % 6
    if phase == 0 then emu.setInput({start=true}, 0)
    elseif phase == 2 then emu.setInput({a=true}, 0)
    elseif phase == 4 then emu.setInput({down=true}, 0)
    else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
  elseif frame >= 4200 and frame < 4330 then
    if frame % 30 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  elseif frame >= 4330 and frame < 6000 then
    if frame % 90 < 3 then emu.setInput({a=true}, 0) else emu.setInput({a=false}, 0) end
  else emu.setInput({start=false, a=false, b=false, select=false, down=false}, 0) end
end
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
local A_MAIN_PRG = 0xC5BA  -- @main_prg@
local fixed_ranges = {{A_MAIN_PRG,0xC6D1},{0xC460,0xC47D},{0xC4AD,0xC4CA},{0xD291,0xD2B6},{0xF004,0xF039},{0xFFE0,0xFFEF}}
local A_BATTLE_SHAKE = 0xC6BB  -- @battle_shake@
local A_BATTLE_SHAKE_END = 0xC6CF  -- @battle_shake_end@
local A_LTG_MASK = 0xB943  -- @ltg_mask@
local A_REDRAW_START = 0xDB67  -- @redraw_start@
local A_LTG_MASK_END = 0xB96E  -- @ltg_mask_end@
local A_CV_FILL = 0x7BB3  -- @cv_fill@
local A_CV_FILL_END = 0x7C14  -- @cv_fill_end@
local A_CV_STREAM = 0x7995  -- @cv_stream@
local A_CV_SCOPY_END = 0x7A34  -- @cv_scopy_end@
local function hack_pc(pc)
  -- load_text_graphics' palette mask, moved to the hack bank (map-canvas
  -- step 1): the original routine's writes ($3D, $A5), game code
  if pc > A_BATTLE_SHAKE and pc <= A_BATTLE_SHAKE_END then return false end  -- bank-14 shake, moved (step 2)
  if pc > A_CV_FILL and pc <= A_CV_FILL_END then return false end  -- the nametable fill (game code, in RAM)
  if pc > A_CV_STREAM and pc <= A_CV_SCOPY_END then return false end  -- the stream step's plain copy (same)
  if pc > A_LTG_MASK and pc <= A_LTG_MASK_END and rd(0x8000) == 0x4C then return false end  -- (write callbacks see the next pc)
  if pc >= 0x8000 and pc < 0x8C00 and rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C then return true end
  if pc >= 0xB900 and pc < 0xBF00 and rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C then return true end  -- second hack segment
  if pc >= 0xB800 and pc < 0xC000 and rd(0xB800) == 0x8E then return true end
  if pc >= 0x7900 and pc < 0x8000 then return true end      -- canvas RAM code (map-canvas step 3)
  if pc > A_REDRAW_START and pc <= A_REDRAW_START + 3 then return true end  -- its "lsr CV_REDIR" (write callbacks see the next pc)
  if pc >= 0xBF00 and pc < 0xBF30 then return true end      -- far trampoline
  for _, r in ipairs(fixed_ranges) do if pc >= r[1] and pc <= r[2] then return true end end
  return false
end
local function onSram(addr, value)
  local pc = emu.getCpuState().pc
  if addr >= 0x7800 then return end   -- the third save record's RAM: map engine RAM (step 2b), canvas code
  if hack_pc(pc) then n1 = n1 + 1; if #ex1 < 10 then ex1[#ex1+1] = string.format("f=%d pc=%04X %04X", frame, pc, addr) end end
end
local function onState(addr, value)
  local pc = emu.getCpuState().pc
  if not hack_pc(pc) and pc >= 0x0800 then
    -- the game's own code (fixed bank or game banks)
    n2 = n2 + 1; if #ex2 < 10 then ex2[#ex2+1] = string.format("f=%d pc=%04X %04X=%02X", frame, pc, addr, value) end
  end
end
-- engine variables the canvas RAM code drives (cv_ctp's $68/$69, the flank
-- lookups' $14/$15 and restored cursor/bank/run state, the queue)
local canvas_drives = {[0x14]=true,[0x15]=true,[0x1C]=true,[0x1D]=true,[0x1E]=true,[0x1F]=true,[0x40]=true,[0x42]=true,[0x44]=true,[0x68]=true,[0x69]=true,[0x6A]=true,[0x6C]=true}
local allowed_zp = {[0x10]=true,[0x11]=true,[0x51]=true,[0x52]=true,[0x53]=true,[0x56]=true}  -- $56 text_line: page flip
local function onRam(addr, value)
  local c = emu.getCpuState()
  if not hack_pc(c.pc) then return end
  -- $0100/$0101 are the game's (bank-14 item flag/chest index; revision 16c)
  if addr == 0x0100 or addr == 0x0101 then n3 = n3 + 1; if #ex3 < 20 then ex3[#ex3+1] = string.format("f=%d pc=%04X %04X=%02X", frame, c.pc, addr, value) end; return end
  if (addr >= 0x0131 and addr <= 0x017F) or (addr >= 0x0102 and addr <= 0x0103) then return end
  if addr >= 0x0780 and addr <= 0x07FF then return end  -- canvas state (map-canvas step 3)
  if canvas_drives[addr] or (addr >= 0x0400 and addr <= 0x04FF) then return end  -- canvas: queue, cursor, attribute run
  if addr >= 0x0200 and addr <= 0x0203 then return end
  if allowed_zp[addr] then return end
  if addr == 0xEB then return end            -- bank_switch_lock (game protocol)
  if addr >= 0x0300 and addr <= 0x03BF then return end  -- engine text buffers (KANJI_EC)
  if addr >= 0x03E0 and addr <= 0x03FF then return end  -- palette buffer (pal_copy, the original load_text_graphics)
  if addr == 0xF3 or addr == 0xF4 then return end       -- its record pointer (same)
  if addr == 0x46 then return end            -- text_window_x (trampoline)
  if addr >= 0x0100 and addr <= 0x01FF then return end  -- stack pushes
  n3 = n3 + 1; if #ex3 < 20 then ex3[#ex3+1] = string.format("f=%d pc=%04X %04X=%02X", frame, c.pc, addr, value) end
end
local deep = {}
local function onExec(addr)
  local sp = emu.getCpuState().sp
  if sp < minsp_any then minsp_any = sp end
  if sp < 0x0E then
    local k = string.format("%04X sp=%02X", addr, sp)
    if not deep[k] then deep[k] = frame end
  end
  if hack_pc(addr) and sp < minsp_hack then minsp_hack = sp end
end
local function onFrame()
  frame = frame + 1
  if frame == 6000 then
    log:write(string.format("hack writes to battery RAM: %d\n", n1))
    for _, e in ipairs(ex1) do log:write("  " .. e .. "\n") end
    log:write(string.format("game writes to hack state: %d\n", n2))
    for _, e in ipairs(ex2) do log:write("  " .. e .. "\n") end
    log:write(string.format("hack writes outside its RAM: %d\n", n3))
    for _, e in ipairs(ex3) do log:write("  " .. e .. "\n") end
    log:write(string.format("min SP while hack code runs: %02X; min SP overall (sampled): %02X\n", minsp_hack, minsp_any))
    local ks = {}
    for k, f in pairs(deep) do ks[#ks+1] = string.format("f=%06d %s", f, k) end
    table.sort(ks)
    for n = 1, math.min(#ks, 400) do log:write("  deep " .. ks[n] .. string.char(10)) end
    log:close(); emu.stop(0)
  end
end
emu.addMemoryCallback(onSram, emu.callbackType.write, 0x6000, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onState, emu.callbackType.write, 0x0131, 0x017F, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onState, emu.callbackType.write, 0x0102, 0x0103, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  if frame < 20 then return end   -- (the game's RAM clear at reset)
  onState(addr, value)
end, emu.callbackType.write, 0x0780, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onRam, emu.callbackType.write, 0x0000, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0x8000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(onExec, emu.callbackType.exec, 0x7900, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(onInput, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
