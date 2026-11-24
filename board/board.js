// Pi-Screen Board · Uhr, Datum, Vers des Tages, optionale TV-Testbuttons
(function () {
  "use strict";

  var TZ = "Europe/Berlin";
  var cfg = window.PI_SCREEN_BOARD_CONFIG || {};
  var verses = window.PI_SCREEN_VERSES || [];

  var clockFmt = new Intl.DateTimeFormat("de-DE", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false });
  var dateFmt = new Intl.DateTimeFormat("de-DE", { timeZone: TZ, weekday: "long", day: "numeric", month: "long", year: "numeric" });
  var keyFmt = new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" });

  var elClock = document.getElementById("clock");
  var elDate = document.getElementById("date");
  var elText = document.getElementById("verse-text");
  var elRef = document.getElementById("verse-ref");
  var currentDay = "";

  // Tagesnummer seit 1970 für das Berliner Kalenderdatum -> stabiler Index pro Tag
  function dayIndex(isoDate) {
    var p = isoDate.split("-");
    return Math.floor(Date.UTC(+p[0], +p[1] - 1, +p[2]) / 86400000);
  }

  function renderVerse(text, ref, version) {
    elText.textContent = "„" + text + "“";
    elRef.textContent = ref;
    if (version) {
      var tag = document.createElement("span");
      tag.className = "verse-version";
      tag.textContent = version;
      elRef.appendChild(tag);
    }
    elText.className = "verse-text" + (text.length > 150 ? " long" : text.length > 90 ? " medium" : "");
  }

  // Lokaler Vers sofort, danach Vers des Tages von YouVersion über den Board-Server (/verse)
  var verseRetry = null;
  function showVerse(isoDate) {
    if (verses.length) {
      var v = verses[dayIndex(isoDate) % verses.length];
      renderVerse(v.text, v.ref, "");
    }
    loadRemoteVerse(isoDate);
  }

  function loadRemoteVerse(isoDate) {
    clearTimeout(verseRetry);
    if (location.protocol === "file:") return;
    fetch("/verse", { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (j) {
        if (isoDate !== currentDay) return;
        if (j && j.ok && j.text && j.date === isoDate) {
          renderVerse(j.text, j.reference, j.version);
        } else if (!j || j.source !== "local") {
          verseRetry = setTimeout(function () { loadRemoteVerse(isoDate); }, 30 * 60 * 1000);
        }
      })
      .catch(function () {
        verseRetry = setTimeout(function () { loadRemoteVerse(isoDate); }, 30 * 60 * 1000);
      });
  }

  function tick() {
    var now = new Date();
    elClock.textContent = clockFmt.format(now);
    var day = keyFmt.format(now);
    if (day !== currentDay) {
      currentDay = day;
      elDate.textContent = dateFmt.format(now);
      showVerse(day);
    }
  }

  tick();
  setInterval(tick, 1000);

  // Temporäre Testbuttons: nur sichtbar, wenn der lokale Board-Server sie freigibt
  if (cfg.showTestButtons) {
    var panel = document.getElementById("test-panel");
    var status = document.getElementById("test-status");
    panel.hidden = false;
    panel.addEventListener("click", function (ev) {
      var action = ev.target && ev.target.getAttribute("data-tv");
      if (!action) return;
      status.textContent = "sende …";
      fetch("/tv/" + action, { method: "POST" })
        .then(function (r) { return r.json(); })
        .then(function (j) { status.textContent = j.ok ? "OK: " + action : "Fehler"; })
        .catch(function () { status.textContent = "kein Server"; });
    });
  }
})();
