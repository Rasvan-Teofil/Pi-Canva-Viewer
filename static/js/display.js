(() => {
  const urlParams = new URLSearchParams(window.location.search);
  const forcedMode = urlParams.get("mode");

  let appState = null;
  let lastReloadToken = null;
  let currentActiveView = "dashboard";
  let rotationIndex = 0;
  let rotationElapsedSec = 0;
  let lastCanvaSrc = "";
  let lastNotionSrc = "";
  let lastDashNotionSrc = "";

  const MODE_LABELS = {
    canva: "CANVA KEYNOTE",
    dashboard: "CHURCH DASHBOARD",
    notion: "NOTION DATENBANK",
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
    const views = ["canva", "dashboard", "notion", "verse"];
    views.forEach((v) => {
      const el = document.getElementById(`view-${v}`);
      if (el) {
        el.classList.toggle("hidden", v !== viewName);
      }
    });

    const notionFullscreen = Boolean(
      appState && appState.notion_view && appState.notion_view.fullscreen_without_header
    );

    // Fullscreen Canva or Notion without top bar when configured
    document.body.classList.toggle("canva-fullscreen", viewName === "canva" && !isRotation);
    document.body.classList.toggle(
      "notion-fullscreen",
      viewName === "notion" && !isRotation && notionFullscreen
    );
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

    // 2b. Published Notion Database / View Iframe (Dedicated Mode + Optional Dashboard Panel)
    const notionCfg = state.notion_view || {};
    const notionEmbedUrl = notionCfg.embed_url || notionCfg.url || "";
    const notionIframe = document.getElementById("notion-iframe");
    if (notionIframe && notionEmbedUrl && notionEmbedUrl !== lastNotionSrc) {
      lastNotionSrc = notionEmbedUrl;
      notionIframe.src = notionEmbedUrl;
    }
    const notionTitleLabel = document.getElementById("notion-title-label");
    if (notionTitleLabel) {
      notionTitleLabel.textContent = notionCfg.title || "Notion Datenbank";
    }

    const showNotionInDash = Boolean(notionCfg.show_in_dashboard && notionEmbedUrl);
    const tasksContainer = document.getElementById("tasks-container");
    const taskCounters = document.getElementById("task-counters");
    const dashNotionContainer = document.getElementById("dash-notion-container");
    const dashNotionBadge = document.getElementById("dash-notion-badge");
    const dashNotionIframe = document.getElementById("dash-notion-iframe");
    const dashLeftTitle = document.getElementById("dash-left-title");
    const dashLeftEyebrow = document.getElementById("dash-left-eyebrow");

    if (showNotionInDash) {
      tasksContainer.classList.add("hidden");
      taskCounters.classList.add("hidden");
      dashNotionContainer.classList.remove("hidden");
      dashNotionBadge.classList.remove("hidden");
      dashLeftEyebrow.textContent = "NOTION LIVE DATENBANK";
      dashLeftTitle.textContent = notionCfg.title || "🗂️ Notion Datenbank";
      if (dashNotionIframe && notionEmbedUrl !== lastDashNotionSrc) {
        lastDashNotionSrc = notionEmbedUrl;
        dashNotionIframe.src = notionEmbedUrl;
      }
    } else {
      tasksContainer.classList.remove("hidden");
      taskCounters.classList.remove("hidden");
      dashNotionContainer.classList.add("hidden");
      dashNotionBadge.classList.add("hidden");
      dashLeftEyebrow.textContent = "TEAM & SPACE OPERATIONS";
      dashLeftTitle.textContent = "🧩 Church & Volunteer Aufgaben";
    }

    // 3. Tasks Board
    const tasks = state.tasks || [];
    const todoCount = tasks.filter((t) => t.status === "todo").length;
    const progCount = tasks.filter((t) => t.status === "in_progress").length;
    const doneCount = tasks.filter((t) => t.status === "done").length;

    taskCounters.innerHTML = `
      <span class="counter-chip todo">${todoCount} Offen</span>
      <span class="counter-chip progress">${progCount} In Arbeit</span>
      <span class="counter-chip done">${doneCount} Erledigt</span>
    `;

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
    const modes =
      rotCfg.enabled_modes && rotCfg.enabled_modes.length
        ? rotCfg.enabled_modes
        : ["canva", "dashboard", "notion", "verse"];
    const durations = rotCfg.durations_sec || { canva: 180, dashboard: 60, notion: 90, verse: 45 };

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
