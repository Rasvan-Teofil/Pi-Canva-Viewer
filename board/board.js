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

  function showVerse(isoDate) {
    if (!verses.length) return;
    var v = verses[dayIndex(isoDate) % verses.length];
    elText.textContent = "„" + v.text + "“";
    elRef.textContent = v.ref;
    elText.className = "verse-text" + (v.text.length > 150 ? " long" : v.text.length > 90 ? " medium" : "");
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
