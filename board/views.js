// Pi-Screen · Stufe 2: Ansichten (Board, Canva) per Pfeiltaste, Canva-Diashow
(function () {
  "use strict";

  var cfg = window.PI_SCREEN_BOARD_CONFIG || {};
  var DEFAULT_CANVA = "https://www.canva.com/design/DAGeJOlW_fg/dcvDxGynTmQVinQOyVVR2Q/view?embed";
  var canvaUrl = cfg.canvaEmbedUrl || DEFAULT_CANVA;
  var slideMs = Math.max(3, Number(cfg.canvaSlideSeconds) || 10) * 1000;
  var reloadMs = Math.max(5, Number(cfg.canvaReloadMinutes) || 30) * 60000;
  var pages = Number(cfg.canvaPages) || 0;          // 0 = automatisch über /canva/info

  // Reihenfolge der Ansichten. Stufe 3 (Notion) wird hier ergänzt.
  var views = Array.prototype.slice.call(document.querySelectorAll(".view"));
  var names = views.map(function (v) { return v.getAttribute("data-view"); });
  var current = Math.max(0, names.indexOf(cfg.startView || "board"));

  var frame = document.getElementById("canva-frame");
  var hint = document.getElementById("canva-hint");
  var page = 1;
  var loadedAt = 0;
  var timer = null;

  function showHint(text) {
    hint.textContent = text || "";
    hint.hidden = !text;
  }

  function loadCanva() {
    page = 1;
    loadedAt = Date.now();
    // über about:blank, sonst wäre es nur ein Hash-Wechsel ohne Neuladen
    frame.src = "about:blank";
    setTimeout(function () { frame.src = canvaUrl + "#1"; }, 200);
  }

  // Canva-Embed reagiert auf den URL-Hash (#2, #3 …) ohne Neuladen
  function gotoPage(n) {
    page = n;
    frame.src = canvaUrl + "#" + n;
  }

  function nextSlide() {
    if (!navigator.onLine) { showHint("Keine Internetverbindung – Canva nicht erreichbar"); return; }
    showHint("");
    if (Date.now() - loadedAt > reloadMs) { loadCanva(); return; }   // Design-Änderungen holen
    var max = pages > 0 ? pages : 1;
    gotoPage(page >= max ? 1 : page + 1);
  }

  function startSlides() {
    stopSlides();
    if (!frame.src || frame.src === "about:blank") loadCanva();
    timer = setInterval(nextSlide, slideMs);
  }
  function stopSlides() { if (timer) { clearInterval(timer); timer = null; } }

  function activate(i) {
    current = (i + views.length) % views.length;
    views.forEach(function (v, k) {
      var on = k === current;
      v.classList.toggle("is-active", on);
      v.setAttribute("aria-hidden", on ? "false" : "true");
    });
    if (names[current] === "canva") startSlides(); else stopSlides();
    reclaimFocus();
  }

  // Tastaturfokus immer beim Hauptdokument halten (iframe schluckt sonst die Pfeiltasten)
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

  // Seitenzahl vom lokalen Server (zählt die Seiten des öffentlichen Canva-Embeds)
  if (!pages && location.protocol.indexOf("http") === 0) {
    var askInfo = function () {
      fetch("/canva/info").then(function (r) { return r.json(); }).then(function (j) {
        if (j && j.pages > 0) pages = j.pages;
        else setTimeout(askInfo, 60000);
      }).catch(function () { setTimeout(askInfo, 60000); });
    };
    askInfo();
  }

  loadCanva();     // im Hintergrund vorladen
  activate(current);

  window.PI_SCREEN_VIEWS = { activate: activate, state: function () {
    return { view: names[current], page: page, pages: pages };
  } };
})();
