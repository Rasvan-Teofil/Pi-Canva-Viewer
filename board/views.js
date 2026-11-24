// Pi-Screen · Ansichten per Pfeiltaste (Board, Canva, Looker), Diashows
(function () {
  "use strict";

  var cfg = window.PI_SCREEN_BOARD_CONFIG || {};
  var isHttp = location.protocol.indexOf("http") === 0;

  function setHint(el, text) { el.textContent = text || ""; el.hidden = !text; }

  // ---------------- Canva: Seitenwechsel über URL-Hash (#2, #3 …) ----------------
  var canva = (function () {
    var DEFAULT_CANVA = "https://www.canva.com/design/DAGeJOlW_fg/dcvDxGynTmQVinQOyVVR2Q/view?embed";
    var url = cfg.canvaEmbedUrl || DEFAULT_CANVA;
    var slideMs = Math.max(3, Number(cfg.canvaSlideSeconds) || 10) * 1000;
    var reloadMs = Math.max(5, Number(cfg.canvaReloadMinutes) || 30) * 60000;
    var pages = Number(cfg.canvaPages) || 0;          // 0 = automatisch über /canva/info
    var frame = document.getElementById("canva-frame");
    var hint = document.getElementById("canva-hint");
    var page = 1, loadedAt = 0, timer = null;

    function load() {
      page = 1;
      loadedAt = Date.now();
      // über about:blank, sonst wäre es nur ein Hash-Wechsel ohne Neuladen
      frame.src = "about:blank";
      setTimeout(function () { frame.src = url + "#1"; }, 200);
    }
    function next() {
      if (!navigator.onLine) { setHint(hint, "Keine Internetverbindung – Canva nicht erreichbar"); return; }
      setHint(hint, "");
      if (Date.now() - loadedAt > reloadMs) { load(); return; }   // Design-Änderungen holen
      var max = pages > 0 ? pages : 1;
      page = page >= max ? 1 : page + 1;
      frame.src = url + "#" + page;
    }
    function start() {
      stop();
      if (!frame.src || frame.src === "about:blank") load();
      timer = setInterval(next, slideMs);
    }
    function stop() { if (timer) { clearInterval(timer); timer = null; } }

    if (!pages && isHttp) {
      var ask = function () {
        fetch("/canva/info").then(function (r) { return r.json(); }).then(function (j) {
          if (j && j.pages > 0) pages = j.pages; else setTimeout(ask, 60000);
        }).catch(function () { setTimeout(ask, 60000); });
      };
      ask();
    }
    load();   // im Hintergrund vorladen
    return { available: true, start: start, stop: stop,
             state: function () { return { page: page, pages: pages }; } };
  })();

  // ---------------- Looker Studio: zwei iframes, nächste Seite lädt verdeckt ----------------
  var looker = (function () {
    var base = cfg.lookerEmbedUrl || "";
    var hint = document.getElementById("looker-hint");
    if (!base) return { available: false, start: function () {}, stop: function () {}, state: function () { return {}; } };

    var pageIds = cfg.lookerPages || [];
    var urls = pageIds.length
      ? pageIds.map(function (p) { return base.replace(/\/page\/[^/?#]+/, "") + "/page/" + p; })
      : [base];
    var pageMs = Math.max(10, Number(cfg.lookerPageSeconds) || 30) * 1000;
    var reloadMs = Math.max(1, Number(cfg.lookerReloadMinutes) || 10) * 60000;
    var frames = [document.getElementById("looker-frame-a"), document.getElementById("looker-frame-b")];
    var front = 0, index = 0, loadedAt = 0, pageTimer = null, pending = null;

    // lädt url ins verdeckte iframe und blendet nach dem Rendern um
    function show(i) {
      var back = frames[1 - front];
      if (pending) clearTimeout(pending.timeout);
      var token = {};
      pending = token;
      token.timeout = setTimeout(function () {
        if (pending === token) setHint(hint, navigator.onLine
          ? "Looker Studio lädt nicht – Freigabe/Einbetten prüfen"
          : "Keine Internetverbindung – Looker Studio nicht erreichbar");
      }, 45000);
      back.onload = function () {
        if (pending !== token || back.src === "about:blank") return;
        setTimeout(function () {
          if (pending !== token) return;
          clearTimeout(token.timeout);
          pending = null;
          setHint(hint, "");
          back.classList.add("is-front");
          frames[front].classList.remove("is-front");
          front = 1 - front;
          index = i;
          loadedAt = Date.now();
        }, 3000);   // Diagramme fertig rendern lassen
      };
      back.src = urls[i];
    }

    function tick() {
      if (urls.length > 1) show((index + 1) % urls.length);
      else if (Date.now() - loadedAt > reloadMs) show(index);
    }
    function start() {
      stop();
      if (!loadedAt) show(0);
      else if (Date.now() - loadedAt > reloadMs) show(index);
      pageTimer = setInterval(tick, urls.length > 1 ? pageMs : 60000);
    }
    function stop() { if (pageTimer) { clearInterval(pageTimer); pageTimer = null; } }

    if (isHttp) {
      fetch("/looker/info").then(function (r) { return r.json(); }).then(function (j) {
        if (j && j.ok === false) setHint(hint, "Looker-Bericht nicht öffentlich – in Looker Studio „Jeder mit dem Link“ + Einbetten aktivieren");
      }).catch(function () {});
    }
    show(0);   // im Hintergrund vorladen
    return { available: true, start: start, stop: stop,
             state: function () { return { page: index + 1, pages: urls.length }; } };
  })();

  // ---------------- Ansichten ----------------
  var controllers = { board: { available: true, start: function () {}, stop: function () {} }, canva: canva, looker: looker };
  var wanted = (cfg.views && cfg.views.length ? cfg.views : ["board", "canva", "looker"]);
  var all = Array.prototype.slice.call(document.querySelectorAll(".view"));
  var views = [];
  wanted.forEach(function (name) {
    var el = all.filter(function (v) { return v.getAttribute("data-view") === name; })[0];
    if (el && controllers[name] && controllers[name].available) views.push(el);
  });
  if (!views.length) views = [document.getElementById("view-board")];
  var names = views.map(function (v) { return v.getAttribute("data-view"); });
  var current = Math.max(0, names.indexOf(cfg.startView || "board"));

  function activate(i) {
    current = (i + views.length) % views.length;
    all.forEach(function (v) {
      var on = v === views[current];
      v.classList.toggle("is-active", on);
      v.setAttribute("aria-hidden", on ? "false" : "true");
    });
    Object.keys(controllers).forEach(function (n) {
      if (n === names[current]) controllers[n].start(); else controllers[n].stop();
    });
    reclaimFocus();
  }

  // Tastaturfokus immer beim Hauptdokument halten (iframes schlucken sonst die Pfeiltasten)
  function reclaimFocus() {
    var a = document.activeElement;
    if (a && a.tagName === "IFRAME") a.blur();
    if (!document.hasFocus()) window.focus();
  }
  window.addEventListener("blur", function () { setTimeout(reclaimFocus, 50); });
  setInterval(reclaimFocus, 2000);

  document.addEventListener("keydown", function (ev) {
    if (ev.key === "ArrowRight") { activate(current + 1); ev.preventDefault(); }
    else if (ev.key === "ArrowLeft") { activate(current - 1); ev.preventDefault(); }
  }, true);

  activate(current);

  window.PI_SCREEN_VIEWS = { activate: activate, state: function () {
    return { view: names[current], views: names, canva: canva.state(), looker: looker.state() };
  } };
})();
