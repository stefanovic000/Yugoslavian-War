// love.js WebSocket bridge.
//
// This file must load before player.js. It owns the browser WebSocket and
// exchanges newline-delimited JSON with Lua through files in the LÖVE save
// directory. No game logic lives here.
(function () {
  "use strict";

  const originalLog = console.log.bind(console);
  const url = window.DF_WS_URL ||
    ((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/ws");

  let saveDir = null;
  let ws = null;
  let queued = [];
  let connecting = false;

  function fsReady() {
    return !!(window.Module && Module.FS && saveDir);
  }

  function filePath(name) {
    return saveDir + "/" + name;
  }

  function writeFile(name, text, append) {
    if (!fsReady()) return false;
    try {
      const path = filePath(name);
      if (append) {
        let old = "";
        try {
          if (Module.FS.analyzePath(path).exists) {
            old = Module.FS.readFile(path, { encoding: "utf8" });
          }
        } catch (_) {}
        Module.FS.writeFile(path, old + text, { encoding: "utf8" });
      } else {
        Module.FS.writeFile(path, text, { encoding: "utf8" });
      }
      return true;
    } catch (err) {
      originalLog("DF bridge FS error", err);
      return false;
    }
  }

  function setState(state) {
    writeFile("ws_state", state, false);
  }

  function connect() {
    if (ws || connecting || !saveDir) return;
    connecting = true;
    setState("connecting");
    try {
      ws = new WebSocket(url);
    } catch (err) {
      connecting = false;
      setState("error");
      originalLog("DF bridge WebSocket error", err);
      return;
    }

    ws.onopen = function () {
      connecting = false;
      originalLog("DF bridge open", url);
      setState("connected");
      for (let i = 0; i < queued.length; i++) ws.send(queued[i]);
      queued = [];
    };
    ws.onmessage = function (event) {
      const text = String(event.data);
      if (text.length) writeFile("ws_in", text.endsWith("\n") ? text : text + "\n", true);
    };
    ws.onclose = function () {
      connecting = false;
      ws = null;
      setState("closed");
    };
    ws.onerror = function () {
      setState("error");
    };
  }

  function send(text) {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(text);
    else queued.push(text);
  }

  // Background tabs suspend requestAnimationFrame, so LÖVE stops pinging.
  // Wake the server up immediately when the tab becomes visible again.
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: "ping", t: Date.now() / 1000 }) + "\n");
    }
  });

  // LÖVE's print reaches the browser console. Intercept only our bridge lines.
  console.log = function () {
    if (arguments.length === 1 && typeof arguments[0] === "string") {
      const s = arguments[0];
      if (s.indexOf("DF_WS_INIT ") === 0) {
        saveDir = s.slice("DF_WS_INIT ".length).trim();
        originalLog("DF bridge init", saveDir);
        writeFile("ws_in", "", false);
        setState("connecting");
        connect();
        return;
      }
      if (s.indexOf("DF_WS_SEND ") === 0) {
        send(s.slice("DF_WS_SEND ".length));
        return;
      }
      if (s === "DF_WS_CLOSE") {
        if (ws) ws.close();
        ws = null;
        setState("closed");
        return;
      }
    }
    return originalLog.apply(console, arguments);
  };
})();
