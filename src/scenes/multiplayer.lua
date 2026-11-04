-- multiplayer.lua
-- Server browser + room lobby. The actual match scene is pushed when the
-- server announces match_start.

local App = require("src.app")
local Client = require("src.net.client")
local C = require("shared.constants")
local Settings = require("src.game.settings")
local Sky = require("src.game.sky")
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
  self.connectStarted = love.timer.getTime()
  self.flow = _G.DOGFIGHT and _G.DOGFIGHT.opts and _G.DOGFIGHT.opts.flow or nil
  self.flowDone = false
  if self.client then self.client.forceBrowser = false end

  local ok = self.client:connect(Settings.data.serverHost, Settings.data.serverPort, Settings.data.callsign)
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
  local ok = self.client:connect(Settings.data.serverHost, Settings.data.serverPort, Settings.data.callsign)
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
  elseif msg.type == "match_start" then
    self.inMatch = true
    self.client.matchActive = true
    App:push(require("src.scenes.netmatch"), self.client, msg)
  elseif msg.type == "match_cancelled" then
    self.inMatch = false
    self.client.matchActive = false
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
      if UI.hit(mx, my, 188, 120, 264, 24) then self.hover = "mode" end
      if UI.hit(mx, my, 246, 144, 34, 24) then self.hover = "botsMinus" end
      if UI.hit(mx, my, 360, 144, 34, 24) then self.hover = "botsPlus" end
      if UI.hit(mx, my, 188, 188, 264, 24) then self.hover = "botDifficulty" end
      if UI.hit(mx, my, 270, 220, 100, 24) then self.hover = "roomClose" end
      return
    end
    if UI.hit(mx, my, 36, 310, 100, 24) then self.hover = "leave" end
    if UI.hit(mx, my, 144, 310, 100, 24) then self.hover = "start" end
    if UI.hit(mx, my, 252, 310, 80, 24) then self.hover = "kick" end
    if UI.hit(mx, my, 340, 310, 80, 24) then self.hover = "room" end
    if UI.hit(mx, my, 436, 310, 100, 24) then self.hover = "settings" end
    if self.spectator and UI.hit(mx, my, 340, 310, 90, 24) then self.hover = "joinmatch" end
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
    and self.roomState.status == "lobby" and self:pilotCount() >= C.MIN_PLAYERS
end

function Multiplayer:sendRoomSettings(mode, bots, botDifficulty)
  self.client:send({
    type = "room_settings", mode = mode, bots = bots,
    botDifficulty = botDifficulty or self.roomState and self.roomState.botDifficulty or "veteran",
  })
end

function Multiplayer:selectedMember()
  if not self.roomState then return nil end
  local list = {}
  for _, p in ipairs(self.roomState.players) do list[#list + 1] = p end
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
  UI.panel(30, 24, 580, 326)
  local room = self.roomState
  if not room then return end

  UI.title(room.name, 32, 20)
  UI.small("HOST " .. (room.host == self.client.selfId and "YOU" or "ANOTHER PILOT"),
    36, 64, UI.C.cream2)
  UI.set(room.status == "prep" and UI.C.orange or UI.C.green)
  love.graphics.setFont(UI.font(9, true))
  love.graphics.printf(string.upper(room.status), 0, 64, 604, "right")

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
        team = (counts[1] <= counts[2]) and 1 or 2
        counts[team] = counts[team] + 1
      end
      list[#list + 1] = {
        id = -b, name = "BOT " .. tostring(b), bot = true, team = team,
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
      if room.mode == "2v2" and (p.team == 1 or p.team == 2) then
        UI.set(p.team == 1 and UI.C.teal or UI.C.orange)
        love.graphics.setFont(UI.font(7, true))
        love.graphics.printf(p.team == 1 and "B" or "R", x, ry + 2, w - 8, "right")
      end
      if p.bot then
        UI.set(UI.C.cream2)
        love.graphics.setFont(UI.font(7))
        love.graphics.print("BOT", x + 180, ry + 2)
      elseif spectator then
        UI.set(UI.C.cream2)
        love.graphics.setFont(UI.font(7))
        love.graphics.print("SPEC", x + 160, ry + 2)
      end
    end
    if #list > shown then
      UI.set(UI.C.cream2)
      love.graphics.setFont(UI.font(8))
      love.graphics.print(string.format("+%d MORE", #list - shown), x + 10, y + 20 + shown * 20)
    end
  end

  drawMembers("PILOTS", pilotList(), 40, 86, 300, 104, false)
  drawMembers("SPECTATORS", room.spectators, 352, 86, 244, 104, true)

  UI.set(UI.C.cream2)
  love.graphics.setFont(UI.font(8))
  local info
  if room.status == "prep" then
    info = "MATCH OVER / 10 SECOND PREPARATION. SPECTATORS MAY JOIN."
  elseif room.status == "playing" then
    info = "MATCH IN PROGRESS. SPECTATING IS ENABLED."
  else
    info = "NO READY-UP STAGE. HOST STARTS WHEN EVERYONE IS IN."
  end
  love.graphics.printf(info, 40, 210, 560, "left")

  UI.set(UI.C.cream2)
  love.graphics.setFont(UI.font(7))
  love.graphics.print(string.format("%d ROUNDS  /  LAST PILOT OR TEAM FLYING WINS THE ROUND", C.ROUNDS), 40, 232)
  love.graphics.print("AFTER ROUND 5: 10 SECONDS TO JOIN THE NEXT MATCH", 40, 244)
  love.graphics.print("CLOUDS HIDE PLANES  /  PARACHUTE CRATES REFILL AMMO", 40, 256)
  love.graphics.print(string.format("MODE %s   /   BOTS %d   /   BOT %s",
    (room.mode or "FFA"):upper(), room.bots or 0,
    (room.botDifficulty or "VETERAN"):upper()), 40, 268)
  if room.lastMvpName then
    UI.set(UI.C.orange)
    love.graphics.print("MATCH MVP  " .. tostring(room.lastMvpName):upper(), 40, 280)
  end

  UI.button(36, 310, 100, 24, "LEAVE", {
    hover = self.hover == "leave", font = UI.font(8, true),
  })
  if room.host == self.client.selfId then
    local member = self:selectedMember()
    UI.button(144, 310, 100, 24, "START", {
      selected = self:canStart(), disabled = not self:canStart(),
      hover = self.hover == "start", font = UI.font(8, true),
    })
    UI.button(252, 310, 80, 24, "KICK", {
      disabled = not member or member.id == room.host,
      hover = self.hover == "kick", font = UI.font(8, true),
    })
    UI.button(340, 310, 80, 24, "ROOM", {
      hover = self.hover == "room", font = UI.font(7, true),
    })
  end

  if self.spectator and room.status == "prep" then
    UI.button(340, 310, 90, 24, "JOIN [J]", {
      hover = self.hover == "joinmatch", font = UI.font(7, true),
    })
  end

  UI.button(436, 310, 100, 24, "SETTINGS", {
    hover = self.hover == "settings", font = UI.font(7, true),
  })

  UI.small("B/R TEAM   /   S SPEC   /   O ROOM   /   K KICK   /   ESC LEAVE", 36, 338,
    UI.C.cream2, "left", 560)

  if self.roomSettingsOpen then self:drawRoomSettings() end
end

function Multiplayer:drawRoomSettings()
  local room = self.roomState
  if not room then return end
  UI.set(UI.C.ink, 0.72)
  love.graphics.rectangle("fill", 0, 0, 640, 360)
  UI.panel(170, 78, 300, 174)
  UI.title("ROOM SETTINGS", 86, 12)
  UI.small("MODE", 190, 108, UI.C.cream2, "left")
  UI.button(188, 120, 264, 24, (room.mode or "FFA"):upper(), {
    hover = self.hover == "mode", font = UI.font(9, true),
  })
  UI.small("BOTS", 190, 150, UI.C.cream2, "left")
  UI.button(246, 144, 34, 24, "-", { hover = self.hover == "botsMinus", font = UI.font(10, true) })
  UI.set(UI.C.cream)
  love.graphics.setFont(UI.font(10, true))
  love.graphics.printf(tostring(room.bots or 0), 286, 150, 70, "center")
  UI.button(360, 144, 34, 24, "+", { hover = self.hover == "botsPlus", font = UI.font(10, true) })
  UI.small("BOT LEVEL", 190, 182, UI.C.cream2, "left")
  UI.button(188, 188, 264, 24, (room.botDifficulty or "VETERAN"):upper(), {
    hover = self.hover == "botDifficulty", font = UI.font(9, true),
  })
  UI.button(270, 220, 100, 24, "CLOSE", {
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

function Multiplayer:keypressed(key)
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
    local count = #self.roomState.players + #self.roomState.spectators
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
    elseif key == "p" and self.roomState.host == self.client.selfId then
      local member = self:selectedMember()
      if member then
        self.client:send({ type = "assign", target = member.id, role = "player" })
      end
    elseif key == "return" or key == "kpenter" then
      if self:canStart() then
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
      if room.host == self.client.selfId and UI.hit(mx, my, 188, 120, 264, 24) then
        local mode = "ffa"
        if room.mode == "ffa" then mode = "1v1"
        elseif room.mode == "1v1" then mode = "2v2" end
        self:sendRoomSettings(mode, room.bots or 0)
      elseif room.host == self.client.selfId and UI.hit(mx, my, 246, 144, 34, 24) then
        self:sendRoomSettings(room.mode, math.max(0, (room.bots or 0) - 1))
      elseif room.host == self.client.selfId and UI.hit(mx, my, 360, 144, 34, 24) then
        local maxBots = math.max(0, C.MAX_PLAYERS - #room.players)
        self:sendRoomSettings(room.mode, math.min(maxBots, (room.bots or 0) + 1))
      elseif room.host == self.client.selfId and UI.hit(mx, my, 188, 188, 264, 24) then
        local level = room.botDifficulty or "veteran"
        level = level == "rookie" and "veteran" or level == "veteran" and "ace" or "rookie"
        self:sendRoomSettings(room.mode, room.bots or 0, level)
      elseif UI.hit(mx, my, 270, 220, 100, 24) then
        self.roomSettingsOpen = false
      end
      return
    end

    if UI.hit(mx, my, 36, 310, 100, 24) then
      self:leaveRoom()
    elseif UI.hit(mx, my, 144, 310, 100, 24) and self:canStart() then
      self.client:send({ type = "start" })
    elseif UI.hit(mx, my, 252, 310, 80, 24) then
      local member = self:selectedMember()
      if room.host == self.client.selfId and member and member.id ~= room.host then
        self.client:send({ type = "kick", target = member.id })
      end
    elseif room.host == self.client.selfId and UI.hit(mx, my, 340, 310, 80, 24) then
      self.roomSettingsOpen = true
    elseif self.spectator and UI.hit(mx, my, 340, 310, 90, 24)
      and room.status == "prep" then
      self.client:send({ type = "join_match" })
    elseif UI.hit(mx, my, 436, 310, 100, 24) then
      App:push(require("src.scenes.settings"))
    end
  end
end

return Multiplayer

