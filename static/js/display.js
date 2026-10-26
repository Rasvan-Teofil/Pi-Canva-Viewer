(() => {
  const urlParams = new URLSearchParams(window.location.search);
  const forcedMode = urlParams.get("mode");

  let appState = null;
  let lastReloadToken = null;
  let currentActiveView = "dashboard";
  let rotationIndex = 0;
  let rotationElapsedSec = 0;
  let lastCanvaSrc = "";

  const MODE_LABELS = {
    canva: "CANVA KEYNOTE",
    dashboard: "CHURCH DASHBOARD",
    verse: "VERS DER WOCHE",
    rotation: "AUTO-ROTATION (LOOP)",
  };

  const STATUS_LABELS = {
    todo: "Offen",
    in_progress: "In Arbeit",
    done: "Erledigt",
  };

  function escapeHtml(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function updateLocalClock() {
    const now = new Date();
    const hm = now.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
    const dateStr = now.toLocaleDateString("de-DE", {
      weekday: "long",
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    });
    const clockEl = document.getElementById("live-clock");
    const dateEl = document.getElementById("live-date");
    if (clockEl) clockEl.textContent = hm;
    if (dateEl) dateEl.textContent = dateStr;
  }

  function setVisibleView(viewName, isRotation) {
    currentActiveView = viewName;
    const views = ["canva", "dashboard", "verse"];
    views.forEach((v) => {
      const el = document.getElementById(`view-${v}`);
      if (el) {
        el.classList.toggle("hidden", v !== viewName);
      }
    });

    // Fullscreen Canva without top bar when purely in canva mode
    document.body.classList.toggle("canva-fullscreen", viewName === "canva" && !isRotation);
  }

  function renderState(state) {
    // 1. Header & Device metadata
    const dev = state.device || {};
    document.getElementById("church-name").textContent = (dev.church_name || "ICF HEILBRONN").toUpperCase();
    document.getElementById("device-location").textContent = `${dev.name || "Screen"} · ${dev.location || ""}`;

    // TV Power badge
    const pwr = (state.tv_power && state.tv_power.simulated_state) || "on";
    const pwrEl = document.getElementById("tv-power-pill");
    pwrEl.textContent = `HDMI-CEC: ${pwr.toUpperCase()}`;
    pwrEl.className = `power-pill ${pwr === "standby" ? "power-standby" : "power-on"}`;

    // 2. Canva Iframe
    const canvaCfg = state.canva || {};
    const embedUrl = canvaCfg.embed_url || canvaCfg.url || "";
    const iframe = document.getElementById("canva-iframe");
    if (embedUrl && embedUrl !== lastCanvaSrc) {
      lastCanvaSrc = embedUrl;
      iframe.src = embedUrl;
    }
    document.getElementById("canva-title-label").textContent = canvaCfg.title || "Canva Präsentation";

    // 3. Tasks Board
    const tasks = state.tasks || [];
    const todoCount = tasks.filter((t) => t.status === "todo").length;
    const progCount = tasks.filter((t) => t.status === "in_progress").length;
    const doneCount = tasks.filter((t) => t.status === "done").length;

    document.getElementById("task-counters").innerHTML = `
      <span class="counter-chip todo">${todoCount} Offen</span>
      <span class="counter-chip progress">${progCount} In Arbeit</span>
      <span class="counter-chip done">${doneCount} Erledigt</span>
    `;

    const tasksContainer = document.getElementById("tasks-container");
    tasksContainer.innerHTML = tasks
      .slice(0, 6)
      .map(
        (t) => `
      <div class="task-card priority-${escapeHtml(t.priority || "medium")} status-${escapeHtml(t.status || "todo")}">
        <div class="task-main">
          <div class="task-title">${escapeHtml(t.title)}</div>
          <div class="task-meta">
            <span class="task-category">${escapeHtml(t.category || "Allgemein")}</span>
            <span>👤 ${escapeHtml(t.assignee || "Team")}</span>
            <span>⏱️ ${escapeHtml(t.due || "")}</span>
          </div>
        </div>
        <div class="task-right">
          <span class="status-badge ${escapeHtml(t.status || "todo")}">
            ${escapeHtml(STATUS_LABELS[t.status] || t.status)}
          </span>
        </div>
      </div>
    `
      )
      .join("");

    // 4. Verse of the Week (Dashboard Widget + Fullscreen Slide)
    const verse = state.verse_of_the_week || {};
    document.getElementById("dash-verse-week").textContent = `${verse.title || "VERS DER WOCHE"} · ${verse.week_label || ""}`;
    document.getElementById("dash-verse-ref").textContent = verse.reference || "";
    document.getElementById("dash-verse-text").textContent = `„${verse.text || ""}“`;
    document.getElementById("dash-verse-impulse").textContent = verse.impulse || "";

    document.getElementById("full-verse-title").textContent = `📖 ${(verse.title || "VERS DER WOCHE").toUpperCase()}`;
    document.getElementById("full-verse-week").textContent = verse.week_label || "";
    document.getElementById("full-verse-text").textContent = `„${verse.text || ""}“`;
    document.getElementById("full-verse-ref").textContent = verse.reference || "";
    document.getElementById("full-verse-impulse").textContent = verse.impulse || "";

    // 5. Upcoming Events
    const events = state.events || [];
    const eventsContainer = document.getElementById("events-container");
    eventsContainer.innerHTML = events
      .slice(0, 4)
      .map(
        (e) => `
      <div class="event-card">
        <div>
          <div class="event-title">${escapeHtml(e.title)}</div>
          <div class="event-date">${escapeHtml(e.date_label)}</div>
          <div class="event-sub">${escapeHtml(e.subtitle || "")}</div>
        </div>
        <span class="event-badge">${escapeHtml(e.badge || "Info")}</span>
      </div>
    `
      )
      .join("");

    // 6. Mode & Rotation handling
    const configuredMode = forcedMode || (state.display && state.display.mode) || "dashboard";
    const modePill = document.getElementById("mode-pill");
    modePill.textContent = MODE_LABELS[configuredMode] || configuredMode.toUpperCase();

    const rotBar = document.getElementById("rotation-bar");
    if (configuredMode === "rotation") {
      rotBar.classList.remove("hidden");
    } else {
      rotBar.classList.add("hidden");
      setVisibleView(configuredMode, false);
    }
  }

  function tickRotation() {
    if (!appState) return;
    const configuredMode = forcedMode || (appState.display && appState.display.mode) || "dashboard";
    if (configuredMode !== "rotation") return;

    const rotCfg = (appState.display && appState.display.rotation) || {};
    const modes = (rotCfg.enabled_modes && rotCfg.enabled_modes.length ? rotCfg.enabled_modes : ["canva", "dashboard", "verse"]);
    const durations = rotCfg.durations_sec || { canva: 180, dashboard: 60, verse: 45 };

    if (rotationIndex >= modes.length) rotationIndex = 0;
    const activeSubMode = modes[rotationIndex];
    const totalSec = Number(durations[activeSubMode] || 60);

    setVisibleView(activeSubMode, true);
    rotationElapsedSec += 1;

    if (rotationElapsedSec >= totalSec) {
      rotationElapsedSec = 0;
      rotationIndex = (rotationIndex + 1) % modes.length;
    }

    const nextMode = modes[(rotationIndex + 1) % modes.length];
    const remaining = Math.max(0, totalSec - rotationElapsedSec);
    const pct = Math.min(100, Math.round((rotationElapsedSec / totalSec) * 100));

    document.getElementById("rotation-status-text").textContent =
      `🔄 Auto-Rotation: ${MODE_LABELS[activeSubMode] || activeSubMode} • Nächste Ansicht: ${MODE_LABELS[nextMode] || nextMode} in ${remaining}s`;
    document.getElementById("rotation-progress-fill").style.width = `${pct}%`;
  }

  async function pollServerState() {
    try {
      const resp = await fetch("/api/state", { cache: "no-store" });
      if (!resp.ok) return;
      const data = await resp.json();
      const token = data.display && data.display.reload_token;
      if (lastReloadToken !== null && token && token !== lastReloadToken) {
        window.location.reload();
        return;
      }
      lastReloadToken = token;
      appState = data;
      renderState(data);
    } catch (err) {
      // Keep displaying current state if network briefly blips
    }
  }

  updateLocalClock();
  setInterval(updateLocalClock, 1000);
  setInterval(tickRotation, 1000);
  pollServerState();
  setInterval(pollServerState, 2500);
})();
