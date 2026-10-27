(() => {
  const urlParams = new URLSearchParams(window.location.search);
  const forcedMode = urlParams.get("mode");

  let appState = null;
  let lastReloadToken = null;
  let currentActiveView = "dashboard";
  let rotationIndex = 0;
  let rotationElapsedSec = 0;
  let lastCanvaSrc = "";
  let loadedCanvaSrc = "";
  let autoplayStartedForCanvaSrc = "";
  let lastNotionSrc = "";
  let lastDashNotionSrc = "";
  let keyboardMode = null;
  let lastServerDisplayMode = null;

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

  function focusKeyboardCapture() {
    const capture = document.getElementById("keyboard-capture");
    if (capture) capture.focus({ preventScroll: true });
  }

  function requestLocalCanvaAutoplay(canvaCfg, source) {
    if (
      !canvaCfg.use_xdotool_autoplay ||
      !source ||
      loadedCanvaSrc !== source ||
      currentActiveView !== "canva" ||
      autoplayStartedForCanvaSrc === source
    ) return;
    autoplayStartedForCanvaSrc = source;
    // This route only accepts the Chromium instance running locally on the Pi.
    // A laptop opening /display cannot trigger xdotool on the screen.
    window.setTimeout(() => {
      fetch("/api/kiosk/local-canva-autoplay", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }).catch(() => {
        // Autoplay is a kiosk enhancement; the loaded Canva embed remains usable
        // if xdotool or an X11 desktop is unavailable.
      });
    }, 5000);
  }

  function getEffectiveMode(state) {
    const serverMode = (state.display && state.display.mode) || "dashboard";
    if (lastServerDisplayMode !== null && serverMode !== lastServerDisplayMode) {
      // A deliberate change in the admin panel takes priority over a local key switch.
      keyboardMode = null;
    }
    lastServerDisplayMode = serverMode;
    return forcedMode || keyboardMode || serverMode;
  }

  function switchPreloadedView(viewName) {
    if (!appState) return;
    const source = viewName === "canva"
      ? ((appState.canva && (appState.canva.embed_url || appState.canva.url)) || "")
      : ((appState.notion_view && (appState.notion_view.embed_url || appState.notion_view.url)) || "");
    if (!source) {
      console.warn(`Die ${viewName === "canva" ? "Canva" : "Notion"}-Ansicht ist noch nicht konfiguriert.`);
      return;
    }

    // No API request and no iframe navigation: both views were assigned their
    // sources during renderState and remain alive while one is hidden.
    keyboardMode = viewName;
    rotationElapsedSec = 0;
    setVisibleView(viewName, false);
    const modePill = document.getElementById("mode-pill");
    modePill.textContent = `MANUELL · ${MODE_LABELS[viewName]}`;
    document.getElementById("rotation-bar").classList.add("hidden");
    focusKeyboardCapture();
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
    if (viewName === "canva") {
      const canvaCfg = (appState && appState.canva) || {};
      requestLocalCanvaAutoplay(canvaCfg, canvaCfg.embed_url || canvaCfg.url || "");
    }
    focusKeyboardCapture();
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
      iframe.onload = () => {
        loadedCanvaSrc = embedUrl;
        requestLocalCanvaAutoplay(canvaCfg, embedUrl);
      };
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
    const configuredMode = getEffectiveMode(state);
    const modePill = document.getElementById("mode-pill");
    modePill.textContent = `${keyboardMode ? "MANUELL · " : ""}${MODE_LABELS[configuredMode] || configuredMode.toUpperCase()}`;

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
    const configuredMode = forcedMode || keyboardMode || (appState.display && appState.display.mode) || "dashboard";
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
  window.addEventListener("keydown", (event) => {
    if (event.ctrlKey && event.altKey && event.key.toLowerCase() === "a") {
      event.preventDefault();
      window.location.assign("/admin");
    } else if (event.key === "ArrowLeft") {
      event.preventDefault();
      switchPreloadedView("canva");
    } else if (event.key === "ArrowRight") {
      event.preventDefault();
      switchPreloadedView("notion");
    }
  });
  window.addEventListener("blur", () => window.setTimeout(focusKeyboardCapture, 0));
  document.addEventListener("pointerdown", (event) => {
    if (event.target && event.target.tagName === "IFRAME") {
      window.setTimeout(focusKeyboardCapture, 0);
    }
  }, true);
  focusKeyboardCapture();
  setInterval(updateLocalClock, 1000);
  setInterval(tickRotation, 1000);
  pollServerState();
  setInterval(pollServerState, 2500);
})();
