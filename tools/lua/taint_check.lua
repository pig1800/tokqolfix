-- Revision 16c: RAM taint gate from a save state with a scripted input path.
-- Reports (1) game reads of RAM ($0000-$07FF, $6000-$7FFF) whose value the hack
-- changed since the game last wrote it (the game expected its own value),
-- (2) game writes to the hack state, (3) stack depth reaching the hack state.
-- Env: SHOP_STATE (.mss), SHOP_PATH ("a,w,..." one step per 40 frames from
-- load+30), TAINT_OUT (report path), TAINT_FRAMES (frames after load).
local STATE = os.getenv("SHOP_STATE")
local PATH = os.getenv("SHOP_PATH") or ""
local OUT = os.getenv("TAINT_OUT") or "D:/EMU/NES/tokqolfix/out/test/r16/taint.txt"
local FRAMES = tonumber(os.getenv("TAINT_FRAMES") or "1200")
local log = assert(io.open(OUT, "w"))
local steps = {}
for s in string.gmatch(PATH, "[^,]+") do steps[#steps+1] = s end
local frame, loaded, lf = 0, false, nil
local function rd(a) return emu.read(a, emu.memType.nesMemory) end
-- $C5A6-$C5E1 is load_text_graphics rewritten in place: its writes ($3D,
-- $A5, the palette buffer) are the original routine's, so it counts as game
-- code.  $E6B3-$E6C3 is the original damage table again (revision 16c).
local A_MAIN_PRG = 0xC5BA  -- @main_prg@
local fixed_ranges = {{A_MAIN_PRG,0xC6D1},{0xC460,0xC47D},{0xC489,0xC49D},{0xC4AD,0xC4CA},{0xD291,0xD2B6},{0xF004,0xF039},{0xFFE0,0xFFEF}}
local A_BATTLE_SHAKE = 0xC6BB  -- @battle_shake@
local A_BATTLE_SHAKE_END = 0xC6CF  -- @battle_shake_end@
local A_LTG_MASK = 0xB943  -- @ltg_mask@
local A_REDRAW_START = 0xDB67  -- @redraw_start@
local A_LTG_MASK_END = 0xB96E  -- @ltg_mask_end@
local function hack_pc(pc)
  -- load_text_graphics' palette mask, moved to the hack bank (map-canvas
  -- step 1): the original routine's writes ($3D, $A5), game code
  if pc > A_BATTLE_SHAKE and pc <= A_BATTLE_SHAKE_END then return false end  -- bank-14 shake, moved (step 2)
  if pc > A_LTG_MASK and pc <= A_LTG_MASK_END and rd(0x8000) == 0x4C then return false end  -- (write callbacks see the next pc)
  if pc >= 0x8000 and pc < 0x8C00 and rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C then return true end
  if pc >= 0xB900 and pc < 0xBF00 and rd(0x8000) == 0x4C and rd(0x8003) == 0x4C and rd(0x8006) == 0x4C then return true end
  if pc >= 0xB800 and pc < 0xC000 and rd(0xB800) == 0x8E then return true end
  if pc >= 0x7900 and pc < 0x7E00 then return true end      -- canvas RAM code (map-canvas step 3)
  if pc > A_REDRAW_START and pc <= A_REDRAW_START + 3 then return true end  -- its "lsr CV_REDIR" (write callbacks see the next pc)
  if pc >= 0xBF00 and pc < 0xBF30 then return true end
  for _, r in ipairs(fixed_ranges) do if pc >= r[1] and pc <= r[2] then return true end end
  return false
end
-- engine variables the overlay drives on purpose (text pointer/column/line,
-- window x, bank-switch lock)
local protocol = {[0x51]=true, [0x52]=true, [0x53]=true, [0x56]=true, [0x46]=true, [0xEB]=true,
  -- the canvas RAM code (map-canvas step 3): cv_ctp's address, the queue
  -- entries and their index, the flank lookups' pointer, the attribute run
  [0x68]=true, [0x69]=true, [0x40]=true, [0x14]=true, [0x15]=true, [0x6A]=true, [0x6C]=true, [0x42]=true}
for a = 0x0400, 0x04FF do protocol[a] = true end
for a = 0x7800, 0x78FF do protocol[a] = true end   -- the canvas half's attribute shadow
local game_val, hack_dirty = {}, {}
local reads, nread, gw, ngw = {}, 0, {}, 0
local minsp, deep = 0xFF, 0
emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  local f = io.open(STATE, "rb"); local d = f:read("*a"); f:close()
  emu.loadSavestate(d)
end, emu.callbackType.exec, 0xC000, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  if not lf then return end
  local pc = emu.getCpuState().pc
  if hack_pc(pc) then
    if not protocol[addr] then hack_dirty[addr] = true end
  else
    game_val[addr] = value; hack_dirty[addr] = nil
    if (addr >= 0x0131 and addr <= 0x017F) or (addr >= 0x0102 and addr <= 0x0103) or (addr >= 0x0780 and addr <= 0x07FF) then
      local sp = emu.getCpuState().sp
      if addr <= 0x0100 + sp then            -- not a stack push
        ngw = ngw + 1
        local k = string.format("%04X pc=%04X", addr, pc)
        gw[k] = (gw[k] or 0) + 1
      end
    end
  end
end, emu.callbackType.write, 0x0000, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  if not lf then return end
  if hack_pc(emu.getCpuState().pc) then
    if not protocol[addr] then hack_dirty[addr] = true end
  else game_val[addr] = value; hack_dirty[addr] = nil end
end, emu.callbackType.write, 0x6000, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  if not lf or not hack_dirty[addr] then return end
  local c = emu.getCpuState()
  if hack_pc(c.pc) then return end
  if addr >= 0x0100 and addr > 0x0100 + c.sp then return end   -- stack pull
  if game_val[addr] ~= nil and game_val[addr] == value then return end   -- restored
  if addr >= 0x010B and addr <= 0x01FF then return end                  -- stack area
  if addr >= 0x0200 and addr <= 0x02FF then return end                  -- OAM shadow (slot 0 is the NMI's)
  if addr >= 0x0300 and addr <= 0x03BF then return end                  -- engine text line buffers
  nread = nread + 1
  local k = string.format("%04X read by pc=%04X (game wrote %s, now %02X)", addr, c.pc, game_val[addr] and string.format("%02X", game_val[addr]) or "--", value)
  if not reads[k] then reads[k] = frame - lf end
end, emu.callbackType.read, 0x0000, 0x07FF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function(addr, value)
  if not lf or not hack_dirty[addr] then return end
  local c = emu.getCpuState()
  if hack_pc(c.pc) then return end
  if game_val[addr] ~= nil and game_val[addr] == value then return end
  nread = nread + 1
  local k = string.format("%04X read by pc=%04X (game wrote %s, now %02X)", addr, c.pc, game_val[addr] and string.format("%02X", game_val[addr]) or "--", value)
  if not reads[k] then reads[k] = frame - lf end
end, emu.callbackType.read, 0x6000, 0x7FFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addMemoryCallback(function()
  if not lf then return end
  local sp = emu.getCpuState().sp
  if sp < minsp then minsp = sp end
end, emu.callbackType.exec, 0x7900, 0xFFFF, emu.memType.nesMemory, emu.cpuType.nes)
emu.addEventCallback(function()
  if not lf then emu.setInput({}, 0); return end
  local f = frame - lf - 30
  if f < 0 then emu.setInput({}, 0); return end
  local k = math.floor(f / 40) + 1
  local s = steps[k]
  if s and s ~= "w" and (f % 40) < 3 then local t = {}; t[s] = true; emu.setInput(t, 0) else emu.setInput({}, 0) end
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  frame = frame + 1
  if loaded and not lf then lf = frame end
  if lf and frame - lf == FRAMES then
    log:write(string.format("frames %d, min SP %02X\n", FRAMES, minsp))
    log:write(string.format("game reads of hack-changed RAM: %d\n", nread))
    local ks = {}; for k, v in pairs(reads) do ks[#ks+1] = {v, k} end
    table.sort(ks, function(a, b) return a[1] < b[1] end)
    for _, e in ipairs(ks) do log:write(string.format("  f+%d %s\n", e[1], e[2])) end
    log:write(string.format("game writes to hack state (non-stack): %d\n", ngw))
    for k, v in pairs(gw) do log:write(string.format("  %s x%d\n", k, v)) end
    log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
