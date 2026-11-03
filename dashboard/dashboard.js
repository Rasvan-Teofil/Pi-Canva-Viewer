(() => {
  "use strict";

  const config = window.PI_SCREEN_CONFIG || {};
  const weatherConfig = config.weather || {};
  const storageKey = "pi-screen-weather-v1";
  const weatherCodes = {
    0: ["Sonnig", "☀"],
    1: ["Überwiegend sonnig", "◔"],
    2: ["Teilweise bewölkt", "◑"],
    3: ["Bedeckt", "☁"],
    45: ["Neblig", "≋"],
    48: ["Neblig", "≋"],
    51: ["Leichter Nieselregen", "☂"],
    53: ["Nieselregen", "☂"],
    55: ["Starker Nieselregen", "☂"],
    61: ["Leichter Regen", "☂"],
    63: ["Regen", "☂"],
    65: ["Starker Regen", "☂"],
    71: ["Leichter Schneefall", "❄"],
    73: ["Schneefall", "❄"],
    75: ["Starker Schneefall", "❄"],
    80: ["Regenschauer", "☂"],
    81: ["Regenschauer", "☂"],
    82: ["Starke Regenschauer", "☂"],
    95: ["Gewitter", "ϟ"],
    96: ["Gewitter mit Hagel", "ϟ"],
    99: ["Gewitter mit Hagel", "ϟ"],
  };

  function element(id) {
    return document.getElementById(id);
  }

  function setText(id, value) {
    const node = element(id);
    if (node) node.textContent = value;
  }

  function safeText(value, fallback = "") {
    return typeof value === "string" && value.trim() ? value.trim() : fallback;
  }

  function setupBrand() {
    const churchName = safeText(config.churchName, "ICF Heilbronn");
    setText("church-name", churchName);
    setText("footer-location", churchName);
    const logo = element("logo-text");
    if (logo) {
      const logoUrl = safeText(config.logoUrl);
      logo.textContent = logoUrl ? "" : safeText(config.logoText, "ICF").toUpperCase();
      logo.style.backgroundImage = logoUrl ? `url("${logoUrl.replace(/"/g, "%22")}")` : "";
      logo.classList.toggle("brand-mark-image", Boolean(logoUrl));
    }

    const image = safeText(config.backgroundImage);
    if (image) {
      const background = document.querySelector(".background");
      if (background) background.style.backgroundImage = `linear-gradient(rgba(6,11,23,.36), rgba(6,11,23,.55)), url("${image.replace(/"/g, "%22")}")`;
    }
  }

  function updateClock() {
    const zone = safeText(config.timezone, "Europe/Berlin");
    const now = new Date();
    setText("clock-time", new Intl.DateTimeFormat("de-DE", {
      timeZone: zone,
      hour: "2-digit",
      minute: "2-digit",
    }).format(now));
    setText("clock-date", new Intl.DateTimeFormat("de-DE", {
      timeZone: zone,
      weekday: "long",
      day: "2-digit",
      month: "long",
    }).format(now));
  }

  function renderCalendar() {
    const calendar = config.calendar || {};
    const events = Array.isArray(calendar.events) ? calendar.events.slice(0, 5) : [];
    setText("calendar-title", safeText(calendar.title, "Demnächst in der Church"));
    const container = element("calendar-events");
    const embed = element("calendar-embed");
    if (!container) return;
    const embedUrl = safeText(calendar.embedUrl);
    if (embedUrl && embed) {
      embed.src = embedUrl;
      embed.classList.remove("hidden");
      container.classList.add("hidden");
      return;
    }
    if (embed) {
      embed.removeAttribute("src");
      embed.classList.add("hidden");
    }
    container.classList.remove("hidden");
    container.replaceChildren();
    if (!events.length) {
      const empty = document.createElement("p");
      empty.className = "event-empty";
      empty.textContent = "Neue Termine folgen bald.";
      container.append(empty);
      return;
    }
    events.forEach((event) => {
      const row = document.createElement("article");
      row.className = "event";
      const day = document.createElement("p");
      day.className = "event-day";
      day.textContent = [safeText(event.date), safeText(event.time)].filter(Boolean).join(" · ") || "Termin";
      const title = document.createElement("p");
      title.className = "event-title";
      title.textContent = safeText(event.title, "Church Event");
      const place = document.createElement("p");
      place.className = "event-place";
      place.textContent = safeText(event.location);
      row.append(day, title, place);
      container.append(row);
    });
  }

  function renderVerse() {
    const verse = config.verse || {};
    setText("verse-label", safeText(verse.label, "Vers des Tages"));
    setText("verse-text", safeText(verse.text, "Der HERR ist mein Hirte, mir wird nichts mangeln."));
    setText("verse-reference", safeText(verse.reference, "Psalm 23,1"));
  }

  function renderWeather(current) {
    const temperature = Number(current.temperature_2m);
    const code = Number(current.weather_code);
    const [summary, icon] = weatherCodes[code] || ["Wetter vor Ort", "◌"];
    setText("weather-temperature", Number.isFinite(temperature) ? `${Math.round(temperature)}°` : "--°");
    setText("weather-summary", summary);
    setText("weather-icon", icon);
    setText("weather-location", safeText(weatherConfig.location, "Heilbronn"));
  }

  function restoreCachedWeather() {
    try {
      const cached = JSON.parse(localStorage.getItem(storageKey) || "null");
      if (cached && cached.current) renderWeather(cached.current);
    } catch (_) {
      // No usable browser storage: the weather panel keeps its friendly fallback.
    }
  }

  async function updateWeather() {
    const latitude = Number(weatherConfig.latitude);
    const longitude = Number(weatherConfig.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
    try {
      const endpoint = new URL("https://api.open-meteo.com/v1/forecast");
      endpoint.search = new URLSearchParams({
        latitude: String(latitude),
        longitude: String(longitude),
        current: "temperature_2m,weather_code",
        timezone: "auto",
      }).toString();
      const response = await fetch(endpoint, { cache: "no-store" });
      if (!response.ok) throw new Error("weather request failed");
      const data = await response.json();
      if (!data.current) throw new Error("weather response incomplete");
      renderWeather(data.current);
      try {
        localStorage.setItem(storageKey, JSON.stringify({ current: data.current, savedAt: Date.now() }));
      } catch (_) {
        // Local storage is an optional offline enhancement.
      }
    } catch (_) {
      restoreCachedWeather();
      const summary = element("weather-summary");
      if (summary && summary.textContent === "Wetter wird geladen …") summary.textContent = "Wetter momentan nicht verfügbar";
    }
  }

  setupBrand();
  renderCalendar();
  renderVerse();
  restoreCachedWeather();
  updateClock();
  updateWeather();
  window.setInterval(updateClock, 1000);
  window.setInterval(updateWeather, Math.max(5, Number(weatherConfig.refreshMinutes) || 30) * 60 * 1000);
})();
