-- multiplayer.lua
-- Server browser + room lobby. The actual match scene is pushed when the
-- server announces match_start.

local App = require("src.app")
local Client = require("src.net.client")
local C = require("shared.constants")
local Settings = require("src.game.settings")
local Sky = require("src.game.sky")
local Sprites = require("src.game.sprites")
local Aircraft = require("shared.aircraft")
local View = require("src.game.view")
local UI = require("src.ui.ui")
local log = require("src.core.log")

local Multiplayer = { name = "multiplayer", module = "src.scenes.multiplayer" }

local function statusLabel(room)
  if room.status == "playing" then return "LIVE" end
  if room.status == "prep" then return "PREP" end
  return "LOBBY"
end

function Multiplayer:enter()
  self.client = Client.new()
  self.phase = "connecting"
  self.rooms = {}
  self.selected = 1
  self.scroll = 0
  self.message = ""
  self.roomState = nil
  self.spectator = false
  self.inMatch = false
  self.hover = nil
  self.roomSettingsOpen = false
  self.chatOpen = false
  self.chatText = ""
  self.chatLog = {}
  self.chatTimer = 0
  self.connectStarted = love.timer.getTime()
  self.flow = _G.DOGFIGHT and _G.DOGFIGHT.opts and _G.DOGFIGHT.opts.flow or nil
  self.flowDone = false
  if self.client then self.client.forceBrowser = false end

  local ok = self.client:connect(Settings.data.serverHost, Settings.data.serverPort, Settings.data.callsign, Settings.data.aircraft)
  if not ok then
    self.phase = "error"
    self.message = self.client.errorMessage or "Connection failed."
  end
  log.info("multiplayer browser connecting to %s:%d", Settings.data.serverHost, Settings.data.serverPort)
end

function Multiplayer:leave()
  if self.client then
    self.client:send({ type = "leave" })
    self.client:close()
  end
  self.client = nil
  log.info("multiplayer browser left")
end

function Multiplayer:sendRooms()
  if self.client then self.client:send({ type = "rooms" }) end
end

function Multiplayer:retry()
  if self.client then self.client:close() end
  self.client = Client.new()
  self.phase = "connecting"
  self.message = ""
  self.roomState = nil
  self.spectator = false
  self.inMatch = false
  self.roomSettingsOpen = false
  self.connectStarted = love.timer.getTime()
  local ok = self.client:connect(Settings.data.serverHost, Settings.data.serverPort, Settings.data.callsign, Settings.data.aircraft)
  if not ok then
    self.phase = "error"
    self.message = self.client.errorMessage or "Connection failed."
  end
end

function Multiplayer:handleMessage(msg)
  if msg.type == "welcome" then
    self.client.name = msg.name
    self.phase = "browser"
    self.rooms = msg.rooms or {}
    self.message = "CONNECTED TO " .. Settings.data.serverHost:upper()
    if self.flow == "create" and not self.flowDone then
      self.flowDone = true
      self:createRoom()
    end
  elseif msg.type == "rooms" then
    self.rooms = msg.rooms or {}
    if #self.rooms == 0 then self.selected = 1 end
    self.selected = math.max(1, math.min(#self.rooms, self.selected))
    if self.flow == "join" and not self.flowDone and #self.rooms > 0 then
      self.flowDone = true
      self:joinSelected()
    end
  elseif msg.type == "joined" then
    self.roomState = nil
    self.spectator = msg.spectator == true
    self.phase = "lobby"
    self.message = self.spectator and "JOINED AS SPECTATOR" or "JOINED ROOM"
    self.selected = 1
    self.roomSettingsOpen = false
  elseif msg.type == "room" then
    self.roomState = msg.room
    if self.phase ~= "match" then self.phase = "lobby" end
    if self.roomState and self.roomState.spectators then
      if msg.room.host == self.client.selfId then self.isHost = true end
    end
    if self.flow == "start" and not self.flowDone and self:canStart() then
      self.flowDone = true
      self.client:send({ type = "start" })
    end
  elseif msg.type == "joined_match" then
    self.spectator = false
    self.message = "YOU ARE IN THE NEXT MATCH"
  elseif msg.type == "became_player" then
    self.spectator = false
    self.message = "YOU ARE NOW A PILOT"
  elseif msg.type == "became_spectator" then
    self.spectator = true
    self.message = "YOU ARE NOW SPECTATING"
  elseif msg.type == "chat" then
    self.chatLog[#self.chatLog + 1] = { name = msg.name or "PILOT", text = msg.text or "" }
    if #self.chatLog > 20 then table.remove(self.chatLog, 1) end
    self.chatTimer = 6
  elseif msg.type == "match_start" then
    self.inMatch = true
    self.client.matchActive = true
    App:push(require("src.scenes.netmatch"), self.client, msg)
  elseif msg.type == "match_cancelled" then
    self.inMatch = false
    self.client.matchActive = false
    if msg.room then self.roomState = msg.room end
    self.message = msg.reason or "MATCH ENDED"
    self.phase = "lobby"
  elseif msg.type == "kicked" then
    self.phase = "browser"
    self.roomState = nil
    self.spectator = false
    self.inMatch = false
    self.client.matchActive = false
    self.message = "KICKED FROM " .. tostring(msg.room or "ROOM")
    self:sendRooms()
  elseif msg.type == "left" then
    self.phase = "browser"
    self.roomState = nil
    self.spectator = false
    self.inMatch = false
    self.client.matchActive = false
    self.message = "LEFT ROOM"
    self:sendRooms()
  elseif msg.type == "room_closed" then
    self.phase = "browser"
    self.roomState = nil
    self.spectator = false
    self.inMatch = false
    self.client.matchActive = false
    self.message = msg.reason or "ROOM CLOSED"
    self:sendRooms()
  elseif msg.type == "error" then
    self.message = tostring(msg.message or "SERVER ERROR"):upper()
  end
end

function Multiplayer:update(dt)
  if not self.client then return end
  self.chatTimer = math.max(0, (self.chatTimer or 0) - dt)

  self.client:update(dt)

  if self.client.notice then
    self.message = self.client.notice
    self.client.notice = nil
  end

  if self.client.forceBrowser then
    self.client.forceBrowser = nil
    self.phase = "browser"
    self.roomState = nil
    self.spectator = false
    self.inMatch = false
    self:sendRooms()
  end

  if self.phase == "connecting" and (self.client.status == "error" or self.client.status == "closed") then
    self.phase = "error"
    self.message = self.client.errorMessage or "CONNECTION FAILED"
  end
  if (self.client.status == "closed" or self.client.status == "error")
    and self.phase ~= "error" and self.phase ~= "connecting" then
    self.phase = "error"
    self.message = self.client.errorMessage or "DISCONNECTED"
  end

  local messages = self.client:takeMessages()
  for i, msg in ipairs(messages) do
    self:handleMessage(msg)
    if self.inMatch then
      -- NetMatch is now the active scene. Anything later in this batch
      -- (snapshots, room updates, a kick) belongs to it, not to the browser.
      for j = #messages, i + 1, -1 do
        table.insert(self.client.messages, 1, messages[j])
      end
      break
    end
  end

  if self.inMatch and not self.client.matchActive then
    self.inMatch = false
    self.phase = "lobby"
    self.message = "MATCH ENDED"
  end

  if self.phase == "browser" and #self.rooms == 0 then
    -- The server pushes rooms every couple of seconds; no extra polling needed.
  end

  local mx, my = View.mouse()
  self.hover = nil
  if self.phase == "browser" then
    if UI.hit(mx, my, 36, 310, 130, 24) then self.hover = "create" end
    if UI.hit(mx, my, 178, 310, 120, 24) then self.hover = "refresh" end
    if UI.hit(mx, my, 486, 310, 118, 24) then self.hover = "back" end
  elseif self.phase == "lobby" then
    if not self.roomState then return end
    if self.roomSettingsOpen then
      if UI.hit(mx, my, 188, 116, 264, 24) then self.hover = "mode" end
      if UI.hit(mx, my, 246, 144, 34, 24) then self.hover = "botsMinus" end
      if UI.hit(mx, my, 360, 144, 34, 24) then self.hover = "botsPlus" end
      if UI.hit(mx, my, 180, 174, 280, 42) then self.hover = "botDifficulty" end
      if UI.hit(mx, my, 270, 224, 100, 24) then self.hover = "roomClose" end
      return
    end
    if UI.hit(mx, my, 36, 304, 84, 24) then self.hover = "leave" end
    if UI.hit(mx, my, 128, 304, 84, 24) then self.hover = "ready" end
    if UI.hit(mx, my, 220, 304, 90, 24) then self.hover = "start" end
    if UI.hit(mx, my, 318, 304, 70, 24) then self.hover = "kick" end
    if UI.hit(mx, my, 396, 304, 70, 24) then self.hover = "room" end
    if UI.hit(mx, my, 474, 304, 100, 24) then self.hover = "settings" end
    if UI.hit(mx, my, 40, 204, 250, 54) then self.hover = "air1" end
    if UI.hit(mx, my, 310, 204, 250, 54) then self.hover = "air2" end
  else
    if UI.hit(mx, my, 140, 208, 140, 26) then self.hover = "retry" end
    if UI.hit(mx, my, 300, 208, 140, 26) then self.hover = "back" end
  end
end

function Multiplayer:pilotCount()
  if not self.roomState then return 0 end
  return #self.roomState.players + (self.roomState.bots or 0)
end

function Multiplayer:canStart()
  return self.roomState and self.roomState.host == self.client.selfId
    and self.roomState.status == "lobby"
    and self.roomState.startable == true
end

function Multiplayer:sendRoomSettings(mode, bots, botDifficulty, rounds)
  local room = self.roomState or {}
  self.client:send({
    type = "room_settings", mode = mode, bots = bots,
    rounds = rounds or room.rounds or C.ROUNDS,
    botDifficulty = botDifficulty or room.botDifficulty or "veteran",
  })
end

function Multiplayer:chooseAircraft(id)
  self.client:send({ type = "set_aircraft", aircraft = id })
  Settings.data.aircraft = id
  Settings.save()
end

function Multiplayer:toggleReady()
  self.client:send({ type = "ready" })
end

function Multiplayer:myRoomPlayer()
  if not self.roomState then return nil end
  for _, p in ipairs(self.roomState.players) do
    if p.id == self.client.selfId then return p end
  end
  return nil
end

function Multiplayer:selectedMember()
  if not self.roomState then return nil end
  local list = {}
  for _, p in ipairs(self.roomState.players) do list[#list + 1] = p end
  local counts = { [1] = 0, [2] = 0 }
  for _, p in ipairs(self.roomState.players) do
    if p.team == 1 or p.team == 2 then counts[p.team] = counts[p.team] + 1 end
  end
  for b = 1, (self.roomState.bots or 0) do
    local team
    if self.roomState.mode == "2v2" then
      local fixed = self.roomState.botTeams and (self.roomState.botTeams[b] or self.roomState.botTeams[tostring(b)])
      team = (fixed == 1 or fixed == 2) and fixed or ((counts[1] <= counts[2]) and 1 or 2)
      counts[team] = counts[team] + 1
    end
    list[#list + 1] = {
      id = -b, name = "BOT " .. tostring(b), bot = true, team = team,
    }
  end
  for _, p in ipairs(self.roomState.spectators) do list[#list + 1] = p end
  return list[self.selected]
end

function Multiplayer:createRoom()
  self.client:send({
    type = "create",
    name = (Settings.data.callsign or "Pilot") .. " ROOM",
  })
end

function Multiplayer:joinSelected()
  local room = self.rooms[self.selected]
  if room then
    self.client:send({ type = "join", room = room.id })
  end
end

function Multiplayer:leaveRoom()
  self.client:send({ type = "leave" })
  self.phase = "browser"
  self.roomState = nil
  self.spectator = false
  self.client.matchActive = false
  self.inMatch = false
  self:sendRooms()
end

function Multiplayer:drawBackground()
  Sky.draw()
  love.graphics.setColor(0.015, 0.025, 0.025, 0.55)
  love.graphics.rectangle("fill", 0, 0, 640, 360)
end

function Multiplayer:drawConnecting()
  UI.panel(120, 110, 400, 140)
  UI.title("CONNECTING", 126, 24)
  UI.small(Settings.data.serverHost .. ":" .. tostring(Settings.data.serverPort), 140, 170, UI.C.cream, "center", 360)
  local dots = string.rep(".", math.floor(love.timer.getTime() * 3) % 4)
  UI.small("OPENING TCP LINK" .. dots, 0, 196, UI.C.cream2, "center")
  UI.small("ESC CANCEL", 0, 222, UI.C.orange, "center")
end

function Multiplayer:drawError()
  UI.panel(100, 96, 440, 176)
  UI.title("CONNECTION FAILED", 106, 20)
  UI.small(self.message or "UNKNOWN ERROR", 120, 154, UI.C.orange, "center", 400)
  UI.small("CHECK SERVER ADDRESS IN SETTINGS", 0, 180, UI.C.cream2, "center")
  UI.button(140, 208, 140, 26, "RETRY", {
    hover = self.hover == "retry", font = UI.font(9, true),
  })
  UI.button(300, 208, 140, 26, "BACK", {
    hover = self.hover == "back", font = UI.font(9, true),
  })
end

function Multiplayer:drawBrowser()
  UI.panel(30, 28, 580, 322)
  UI.title("MULTIPLAYER", 36, 24)
  UI.small("SERVER " .. Settings.data.serverHost:upper() .. ":" .. tostring(Settings.data.serverPort),
    36, 70, UI.C.cream2, "left", 540)
  UI.small(self.message or "", 300, 70, UI.C.orange, "right", 300)

  local x, y, w = 40, 92, 560
  UI.set(UI.C.ink2)
  love.graphics.rectangle("fill", x, y, w, 202)
  UI.set(UI.C.ink3)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, 202)

  if #self.rooms == 0 then
    UI.small("NO OPEN ROOMS", 0, 176, UI.C.cream2, "center")
    UI.small("CREATE ONE AND INVITE FRIENDS", 0, 196, UI.C.cream2, "center")
  else
    local visible = 8
    self.scroll = math.max(0, math.min(self.scroll, #self.rooms - visible))
    for i = 1, math.min(visible, #self.rooms) do
      local room = self.rooms[self.scroll + i]
      local ry = y + 7 + (i - 1) * 24
      local selected = (self.scroll + i) == self.selected
      if selected then
        UI.set(UI.C.orange, 0.16)
        love.graphics.rectangle("fill", x + 4, ry - 2, w - 8, 22)
        UI.set(UI.C.orange)
        love.graphics.rectangle("fill", x + 4, ry - 2, 3, 22)
      end
      UI.set(selected and UI.C.orange or UI.C.cream)
      love.graphics.setFont(UI.font(9, true))
      love.graphics.print(room.name, x + 12, ry)
      UI.set(room.status == "lobby" and UI.C.green
        or (room.status == "prep" and UI.C.orange or UI.C.red))
      love.graphics.setFont(UI.font(8))
      love.graphics.print(statusLabel(room), x + 250, ry + 1)
      UI.set(UI.C.cream2)
      love.graphics.print(room.hostName or "?", x + 330, ry + 1)
      love.graphics.print(string.format("%d/%d", room.players, room.max), x + 474, ry + 1)
      love.graphics.print(room.spectators .. " SPEC", x + 510, ry + 1)
    end
  end

  UI.button(36, 310, 130, 24, "CREATE ROOM", {
    hover = self.hover == "create", font = UI.font(8, true),
  })
  UI.button(178, 310, 120, 24, "REFRESH", {
    hover = self.hover == "refresh", font = UI.font(8, true),
  })
  UI.button(486, 310, 118, 24, "BACK", {
    hover = self.hover == "back", font = UI.font(8, true),
  })
  UI.small("ENTER JOIN   /   C CREATE   /   ESC BACK", 36, 338, UI.C.cream2, "left", 560)
end
function Multiplayer:drawLobby()
  UI.panel(20, 14, 600, 336)
  local room = self.roomState
  if not room then return end
  local me = self:myRoomPlayer()

  UI.title(room.name, 22, 20)
  UI.small("HOST " .. (room.host == self.client.selfId and "YOU" or "ANOTHER PILOT"),
    36, 56, UI.C.cream2)
  UI.set(room.status == "prep" and UI.C.orange or UI.C.green)
  love.graphics.setFont(UI.font(9, true))
  love.graphics.printf(string.upper(room.status), 0, 56, 584, "right")

  local function pilotList()
    local list = {}
    local counts = { [1] = 0, [2] = 0 }
    for _, p in ipairs(room.players) do
      list[#list + 1] = p
      if p.team == 1 or p.team == 2 then counts[p.team] = counts[p.team] + 1 end
    end
    for b = 1, (room.bots or 0) do
      local team
      if room.mode == "2v2" then
        local fixed = room.botTeams and (room.botTeams[b] or room.botTeams[tostring(b)])
        team = (fixed == 1 or fixed == 2) and fixed
          or ((counts[1] <= counts[2]) and 1 or 2)
        counts[team] = counts[team] + 1
      end
      list[#list + 1] = {
        id = -b, name = "BOT " .. tostring(b), bot = true, team = team,
        ready = true,
      }
    end
    return list
  end

  local function drawMembers(title, list, x, y, w, h, spectator)
    UI.set(UI.C.cream2)
    love.graphics.setFont(UI.font(8))
    love.graphics.print(title, x, y)
    UI.set(UI.C.ink2)
    love.graphics.rectangle("fill", x, y + 12, w, h)
    UI.set(UI.C.ink3)
    love.graphics.rectangle("line", x + 0.5, y + 12.5, w - 1, h - 1)
    if #list == 0 then
      UI.set(UI.C.cream2)
      love.graphics.setFont(UI.font(8))
      love.graphics.print(spectator and "NO SPECTATORS" or "WAITING FOR PILOTS", x + 10, y + 24)
    end
    local maxRows = math.max(1, math.floor((h - 22) / 20))
    local shown = math.min(#list, maxRows)
    if #list > maxRows then shown = math.max(1, maxRows - 1) end
    for i = 1, shown do
      local p = list[i]
      local ry = y + 20 + (i - 1) * 20
      local index = i
      if spectator then index = index + #room.players + (room.bots or 0) end
      if index == self.selected then
        UI.set(UI.C.orange, 0.15)
        love.graphics.rectangle("fill", x + 3, ry - 2, w - 6, 19)
        UI.set(UI.C.orange)
        love.graphics.rectangle("fill", x + 3, ry - 2, 2, 19)
      end
      UI.set(p.bot and UI.C.cream2 or UI.C.cream)
      love.graphics.setFont(UI.font(9))
      local label = p.name
      if p.host then label = label .. "  *" end
      love.graphics.print(label, x + 10, ry)
      if p.bot then
        UI.set(UI.C.cream2)
        love.graphics.setFont(UI.font(7))
        love.graphics.print("BOT", x + 150, ry + 2)
      elseif spectator then
        UI.set(UI.C.cream2)
        love.graphics.setFont(UI.font(7))
        love.graphics.print("SPEC", x + 150, ry + 2)
      elseif p.ready then
        UI.set(UI.C.green)
        love.graphics.setFont(UI.font(7, true))
        love.graphics.print("READY", x + 145, ry + 2)
      else
        UI.set(UI.C.orange)
        love.graphics.setFont(UI.font(7))
        love.graphics.print("WAIT", x + 145, ry + 2)
      end
      if room.mode == "2v2" and (p.team == 1 or p.team == 2) then
        UI.set(p.team == 1 and UI.C.teal or UI.C.orange)
        love.graphics.setFont(UI.font(7, true))
        love.graphics.printf(p.team == 1 and "B" or "R", x, ry + 2, w - 8, "right")
      end
    end
    if #list > shown then
      UI.set(UI.C.cream2)
      love.graphics.setFont(UI.font(8))
      love.graphics.print(string.format("+%d MORE", #list - shown), x + 10, y + 20 + shown * 20)
    end
  end

  drawMembers("PILOTS", pilotList(), 40, 74, 300, 104, false)
  drawMembers("SPECTATORS", room.spectators, 352, 74, 244, 104, true)

  local function previewPlane(id, x, y)
    local spec = Aircraft.get(id)
    local plane = {
      x = 0, y = 0, angle = 0, throttle = 0.8, alive = true,
      invuln = 0, hitFlash = 0, team = 1, planeType = spec.id, spec = spec,
      parts = { engine = spec.stats.partHp, wing = spec.stats.partHp,
        tail = spec.stats.partHp, guns = spec.stats.partHp },
    }
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(1.7, 1.7)
    Sprites.drawPlane(plane, self.uiTime, { colors = spec.visual.palette })
    love.graphics.pop()
  end

  UI.small("AIRCRAFT", 40, 192, UI.C.orange, "left")
  UI.small("CLICK A CARD OR USE LEFT / RIGHT", 40, 192, UI.C.cream2, "right", 540)
  local selectedPlane = me and me.planeType or Settings.data.aircraft
  if me then
    local list = Aircraft.all()
    for i, spec in ipairs(list) do
      local x = (i == 1) and 40 or 310
      local y = 204
      local w, h = 250, 54
      local selected = spec.id == selectedPlane
      UI.set(selected and UI.C.orange or UI.C.ink3, selected and 0.20 or 0.08)
      love.graphics.rectangle("fill", x, y, w, h)
      UI.set(selected and UI.C.orange or UI.C.ink3)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
      if selected then
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
        love.graphics.setLineWidth(1)
      end
      previewPlane(spec.id, x + 58, y + 30)
      UI.set(selected and UI.C.cream or UI.C.cream2)
      love.graphics.setFont(UI.font(9, true))
      love.graphics.print((spec.shortName or spec.name):upper(), x + 112, y + 10)
      UI.set(UI.C.cream2)
      love.graphics.setFont(UI.font(7))
      love.graphics.print((spec.role or "Fighter"):upper(), x + 112, y + 25)
      if selected then
        UI.set(UI.C.orange)
        love.graphics.setFont(UI.font(7, true))
        love.graphics.print("SELECTED", x + 112, y + 40)
      end
    end
  else
    UI.small("SPECTATORS CANNOT PICK AN AIRCRAFT", 40, 210, UI.C.cream2, "left", 540)
  end

  UI.set(room.allReady and UI.C.green or UI.C.orange)
  love.graphics.setFont(UI.font(8, true))
  local readyCount = room.readyCount or 0
  love.graphics.print(room.allReady and "ALL PILOTS READY"
    or string.format("READY %d / %d", readyCount, #room.players), 40, 264)
  UI.set(UI.C.cream2)
  love.graphics.setFont(UI.font(7))
  local modeLine
  if room.mode == "demo" then
    modeLine = "DEMO   /   RESPAWNS   /   INFINITE AMMO"
  else
    modeLine = string.format("MODE %s   /   BOTS %d   /   BOT %s",
      (room.mode or "FFA"):upper(), room.bots or 0,
      (room.botDifficulty or "VETERAN"):upper())
  end
  love.graphics.print(modeLine, 40, 276)
  if room.lastMvpName then
    UI.set(UI.C.orange)
    love.graphics.print("MATCH MVP  " .. tostring(room.lastMvpName):upper(), 40, 286)
  end

  UI.button(36, 304, 84, 24, "LEAVE", {
    hover = self.hover == "leave", font = UI.font(8, true),
  })
  if me then
    UI.button(128, 304, 84, 24, me.ready and "UNREADY" or "READY", {
      selected = me.ready == true, hover = self.hover == "ready",
      font = UI.font(7, true),
    })
  elseif self.spectator then
    UI.button(128, 304, 84, 24, "JOIN PILOT", {
      disabled = #room.players >= (room.max or C.MAX_PLAYERS),
      font = UI.font(6, true),
    })
  end
  if room.host == self.client.selfId then
    local member = self:selectedMember()
    UI.button(220, 304, 90, 24, "START", {
      selected = self:canStart(), disabled = false,
      hover = self.hover == "start", font = UI.font(8, true),
    })
    UI.button(318, 304, 70, 24, "KICK", {
      disabled = not member or member.id == room.host,
      hover = self.hover == "kick", font = UI.font(7, true),
    })
    UI.button(396, 304, 70, 24, "ROOM", {
      hover = self.hover == "room", font = UI.font(7, true),
    })
  end
  UI.button(474, 304, 100, 24, "SETTINGS", {
    hover = self.hover == "settings", font = UI.font(7, true),
  })

  UI.small(self.spectator
      and "P JOIN PILOT   /   ESC LEAVE"
      or "Y READY  /  P PILOT  /  S SPEC  /  ENTER CHAT  /  O ROOM  /  ESC",
    36, 338, UI.C.cream2, "left", 560)
  local rttMs = math.floor((self.client.rtt or 0) * 1000 + 0.5)
  if rttMs > 0 then
    UI.set(rttMs < 80 and UI.C.green or (rttMs < 160 and UI.C.orange or UI.C.red))
    love.graphics.setFont(UI.font(7, true))
    love.graphics.printf(string.format("PING %dMS", rttMs), 36, 338, 560, "right")
  end

  if self.roomSettingsOpen then self:drawRoomSettings() end
  self:drawChat()
end

function Multiplayer:drawRoomSettings()
  local room = self.roomState
  if not room then return end
  UI.set(UI.C.ink, 0.72)
  love.graphics.rectangle("fill", 0, 0, 640, 360)
  UI.panel(170, 74, 300, 218)
  UI.title("ROOM SETTINGS", 82, 12)
  UI.small("MODE", 190, 104, UI.C.cream2, "left")
  UI.button(188, 116, 264, 24, (room.mode or "FFA"):upper(), {
    hover = self.hover == "mode", font = UI.font(9, true),
  })
  UI.small("BOTS", 190, 150, UI.C.cream2, "left")
  UI.button(246, 144, 34, 24, "-", { hover = self.hover == "botsMinus", font = UI.font(10, true) })
  UI.set(UI.C.cream)
  love.graphics.setFont(UI.font(10, true))
  love.graphics.printf(tostring(room.bots or 0), 286, 150, 70, "center")
  UI.button(360, 144, 34, 24, "+", { hover = self.hover == "botsPlus", font = UI.font(10, true) })
  UI.small("BOT LEVEL", 190, 178, UI.C.cream2, "left")
  UI.button(188, 192, 264, 24, "<  " .. (room.botDifficulty or "VETERAN"):upper() .. "  >", {
    hover = self.hover == "botDifficulty", font = UI.font(9, true),
  })
  UI.small("ROUNDS", 190, 224, UI.C.cream2, "left")
  UI.button(188, 238, 34, 24, "-", { hover = self.hover == "roundsMinus", font = UI.font(10, true) })
  UI.set(UI.C.cream)
  love.graphics.setFont(UI.font(10, true))
  love.graphics.printf(tostring(room.rounds or C.ROUNDS), 228, 244, 176, "center")
  UI.button(418, 238, 34, 24, "+", { hover = self.hover == "roundsPlus", font = UI.font(10, true) })
  UI.button(270, 268, 100, 24, "CLOSE", {
    hover = self.hover == "roomClose", font = UI.font(8, true),
  })
end

function Multiplayer:draw()
  self:drawBackground()
  if self.phase == "connecting" then
    self:drawConnecting()
  elseif self.phase == "error" then
    self:drawError()
  elseif self.phase == "browser" then
    self:drawBrowser()
  elseif self.phase == "lobby" then
    self:drawLobby()
  end
end

function Multiplayer:sendChat()
  local text = self.chatText:gsub("^%s+", ""):gsub("%s+$", "")
  if text ~= "" then self.client:send({ type = "chat", text = text }) end
  self.chatText = ""
  self.chatOpen = false
end

function Multiplayer:textinput(text)
  if self.chatOpen and #self.chatText < 80 then self.chatText = self.chatText .. text end
end

function Multiplayer:drawChat()
  if self.chatOpen then
    UI.set(UI.C.ink, 0.72)
    love.graphics.rectangle("fill", 0, 0, 640, 360)
    UI.panel(120, 92, 400, 176)
    UI.small("CHAT / ENTER SEND / ESC CLOSE", 136, 104, UI.C.orange)
    local start = math.max(1, #self.chatLog - 6)
    for i = start, #self.chatLog do
      local m = self.chatLog[i]
      UI.small((m.name .. ": " .. m.text):sub(1, 62), 136, 126 + (i - start) * 14,
        UI.C.cream2, "left", 368)
    end
    UI.set(UI.C.ink3)
    love.graphics.rectangle("fill", 136, 232, 368, 20)
    UI.set(UI.C.cream)
    love.graphics.setFont(UI.font(8))
    love.graphics.print(self.chatText .. "|", 142, 238)
  elseif self.chatTimer > 0 and #self.chatLog > 0 then
    local m = self.chatLog[#self.chatLog]
    UI.set(UI.C.ink, 0.78)
    love.graphics.rectangle("fill", 20, 334, 600, 18)
    UI.small((m.name .. ": " .. m.text):sub(1, 74), 28, 338, UI.C.cream2)
  end
end

function Multiplayer:keypressed(key)
  if self.chatOpen then
    if key == "escape" then
      self.chatOpen = false
      self.chatText = ""
    elseif key == "backspace" then
      self.chatText = self.chatText:sub(1, -2)
    elseif key == "return" or key == "kpenter" then
      self:sendChat()
    end
    return
  end
  if key == "return" or key == "kpenter" then
    if self.phase == "lobby" then
      self.chatOpen = true
      self.chatText = ""
      return
    end
  end
  if self.phase == "connecting" then
    if key == "escape" then
      self.client:close()
      App:pop()
    end
    return
  end

  if self.phase == "error" then
    if key == "return" or key == "kpenter" then
      self:retry()
    elseif key == "escape" then
      App:pop()
    end
    return
  end

  if self.phase == "browser" then
    if key == "up" then
      self.selected = math.max(1, self.selected - 1)
      self.scroll = math.min(self.scroll, self.selected - 1)
    elseif key == "down" then
      self.selected = math.min(math.max(1, #self.rooms), self.selected + 1)
      if self.selected - self.scroll > 8 then self.scroll = self.selected - 8 end
    elseif key == "return" or key == "kpenter" then
      self:joinSelected()
    elseif key == "c" then
      self:createRoom()
    elseif key == "r" then
      self:sendRooms()
    elseif key == "escape" then
      App:pop()
    end
    return
  end

  if self.phase == "lobby" then
    if not self.roomState then return end
    local count = #self.roomState.players + (self.roomState.bots or 0)
      + #self.roomState.spectators
    if key == "up" then
      self.selected = math.max(1, self.selected - 1)
    elseif key == "down" then
      self.selected = math.min(math.max(1, count), self.selected + 1)
    elseif key == "k" then
      local member = self:selectedMember()
      if self.roomState.host == self.client.selfId and member and member.id ~= self.roomState.host then
        self.client:send({ type = "kick", target = member.id })
      end
    elseif key == "o" and self.roomState.host == self.client.selfId then
      self.roomSettingsOpen = true
    elseif key == "b" or key == "r" then
      local member = self:selectedMember()
      if self.roomState.host == self.client.selfId and member then
        self.client:send({
          type = "assign", target = member.id, role = "player",
          team = key == "b" and 1 or 2,
        })
      elseif self.roomState.mode == "2v2" then
        self.client:send({ type = "pick_team", team = key == "b" and 1 or 2 })
      end
    elseif key == "s" and self.roomState.host == self.client.selfId then
      local member = self:selectedMember()
      if member and member.id ~= self.roomState.host then
        self.client:send({ type = "assign", target = member.id, role = "spectator" })
      end
    elseif key == "p" then
      if self.spectator then
        self.client:send({ type = "become_player" })
      elseif self.roomState.host == self.client.selfId then
        local member = self:selectedMember()
        if member then
          self.client:send({ type = "assign", target = member.id, role = "player" })
        end
      end
    elseif key == "y" then
      if self:myRoomPlayer() then self:toggleReady() end
    elseif key == "left" or key == "right" then
      local me = self:myRoomPlayer()
      if me then
        local list = Aircraft.all()
        local index = 1
        for i, spec in ipairs(list) do
          if spec.id == me.planeType then index = i end
        end
        index = key == "left" and ((index - 2) % #list) + 1 or (index % #list) + 1
        self:chooseAircraft(list[index].id)
      end
    elseif key == "return" or key == "kpenter" then
      if self.roomState.host == self.client.selfId and self.roomState.status == "lobby" then
        self.client:send({ type = "start" })
      end
    elseif key == "escape" then
      if self.roomSettingsOpen then
        self.roomSettingsOpen = false
      else
        self:leaveRoom()
      end
    end
  end
end

function Multiplayer:mousepressed(x, y)
  local mx, my = View.toVirtual(x, y)
  if self.phase == "error" then
    if UI.hit(mx, my, 140, 208, 140, 26) then self:retry()
    elseif UI.hit(mx, my, 300, 208, 140, 26) then App:pop() end
    return
  end
  if self.phase == "browser" then
    if UI.hit(mx, my, 36, 310, 130, 24) then
      self:createRoom()
    elseif UI.hit(mx, my, 178, 310, 120, 24) then
      self:sendRooms()
    elseif UI.hit(mx, my, 486, 310, 118, 24) then
      App:pop()
    else
      for i = 1, 8 do
        local index = self.scroll + i
        if self.rooms[index] and UI.hit(mx, my, 40, 99 + (i - 1) * 24, 560, 22) then
          self.selected = index
          self:joinSelected()
          return
        end
      end
    end
  elseif self.phase == "lobby" then
    if not self.roomState then return end
    local room = self.roomState
    if self.roomSettingsOpen then
      if room.host == self.client.selfId and UI.hit(mx, my, 188, 116, 264, 24) then
        local mode = "ffa"
        if room.mode == "ffa" then mode = "1v1"
        elseif room.mode == "1v1" then mode = "2v2"
        elseif room.mode == "2v2" then mode = "demo" end
        self:sendRoomSettings(mode, room.bots or 0, room.botDifficulty, room.rounds)
      elseif room.host == self.client.selfId and UI.hit(mx, my, 246, 144, 34, 24) then
        self:sendRoomSettings(room.mode, math.max(0, (room.bots or 0) - 1), nil, room.rounds)
      elseif room.host == self.client.selfId and UI.hit(mx, my, 360, 144, 34, 24) then
        local maxBots = math.max(0, C.MAX_PLAYERS - #room.players)
        self:sendRoomSettings(room.mode, math.min(maxBots, (room.bots or 0) + 1), nil, room.rounds)
      elseif room.host == self.client.selfId and UI.hit(mx, my, 180, 174, 280, 42) then
        local level = room.botDifficulty or "veteran"
        level = level == "rookie" and "veteran" or level == "veteran" and "ace" or "rookie"
        self:sendRoomSettings(room.mode, room.bots or 0, level, room.rounds)
      elseif room.host == self.client.selfId and UI.hit(mx, my, 188, 226, 34, 24) then
        self:sendRoomSettings(room.mode, room.bots or 0, room.botDifficulty,
          math.max(2, (room.rounds or C.ROUNDS) - 1))
      elseif room.host == self.client.selfId and UI.hit(mx, my, 418, 226, 34, 24) then
        self:sendRoomSettings(room.mode, room.bots or 0, room.botDifficulty,
          math.min(12, (room.rounds or C.ROUNDS) + 1))
      elseif UI.hit(mx, my, 270, 268, 100, 24) then
        self.roomSettingsOpen = false
      end
      return
    end

    if UI.hit(mx, my, 36, 304, 84, 24) then
      self:leaveRoom()
    elseif self:myRoomPlayer() and UI.hit(mx, my, 128, 304, 84, 24) then
      self:toggleReady()
    elseif self.spectator and UI.hit(mx, my, 128, 304, 84, 24) then
      self.client:send({ type = "become_player" })
    elseif UI.hit(mx, my, 220, 304, 90, 24) and room.host == self.client.selfId
      and room.status == "lobby" then
      self.client:send({ type = "start" })
    elseif UI.hit(mx, my, 318, 304, 70, 24) then
      local member = self:selectedMember()
      if room.host == self.client.selfId and member and member.id ~= room.host then
        self.client:send({ type = "kick", target = member.id })
      end
    elseif room.host == self.client.selfId and UI.hit(mx, my, 396, 304, 70, 24) then
      self.roomSettingsOpen = true
    elseif UI.hit(mx, my, 474, 304, 100, 24) then
      App:push(require("src.scenes.settings"))
    elseif self:myRoomPlayer() then
      local list = Aircraft.all()
      if UI.hit(mx, my, 40, 204, 250, 54) and list[1] then
        self:chooseAircraft(list[1].id)
      elseif UI.hit(mx, my, 310, 204, 250, 54) and list[2] then
        self:chooseAircraft(list[2].id)
      end
    end
  end
end

return Multiplayer






