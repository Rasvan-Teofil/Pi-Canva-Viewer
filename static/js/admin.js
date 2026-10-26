(() => {
  let currentState = null;

  const STATUS_LABELS = {
    todo: "⏳ Offen",
    in_progress: "🔨 In Arbeit",
    done: "✅ Erledigt",
  };

  function showToast(msg) {
    const toast = document.getElementById("toast");
    toast.textContent = msg;
    toast.classList.remove("hidden");
    clearTimeout(window.__toastTimer);
    window.__toastTimer = setTimeout(() => toast.classList.add("hidden"), 3200);
  }

  function escapeHtml(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function apiPost(url, payload) {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {}),
    });
    return resp.json();
  }

  function populateUI(state) {
    currentState = state;
    const mode = (state.display && state.display.mode) || "dashboard";

    document.querySelectorAll(".mode-card").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.mode === mode);
    });

    // Rotation intervals
    const durs = (state.display && state.display.rotation && state.display.rotation.durations_sec) || {};
    document.getElementById("rot-canva").value = durs.canva || 180;
    document.getElementById("rot-dashboard").value = durs.dashboard || 60;
    document.getElementById("rot-verse").value = durs.verse || 45;

    // Target selector options
    const targetSel = document.getElementById("command-target");
    const currentTarget = targetSel.value || "pi-local";
    const fleet = state.pi_fleet || [];
    targetSel.innerHTML =
      `<option value="pi-local">Dieser Pi (Lokal)</option>` +
      `<option value="all">🌐 Alle Pis im Space (Broadcast)</option>` +
      fleet
        .filter((n) => !n.is_local)
        .map((n) => `<option value="${escapeHtml(n.id)}">📡 ${escapeHtml(n.name)}</option>`)
        .join("");
    targetSel.value = currentTarget;

    // TV Power & Schedule
    const tv = state.tv_power || {};
    const pwrState = tv.simulated_state || "on";
    const badge = document.getElementById("tv-status-badge");
    badge.textContent = `TV: ${pwrState.toUpperCase()}`;
    badge.className = `status-pill ${pwrState === "standby" ? "standby" : "on"}`;

    const sched = tv.schedule || {};
    document.getElementById("sched-enabled").checked = sched.enabled !== false;
    document.getElementById("sched-off-time").value = sched.off_time || "22:30";
    document.getElementById("sched-on-time").value = sched.on_time || "08:00";
    document.getElementById("tv-last-action").textContent =
      `Letzte CEC-Aktion: ${tv.last_action || "–"} (${tv.last_action_time || "beim Start"})`;

    // Verse of the week
    const verse = state.verse_of_the_week || {};
    document.getElementById("verse-week").value = verse.week_label || "";
    document.getElementById("verse-ref").value = verse.reference || "";
    document.getElementById("verse-text").value = verse.text || "";
    document.getElementById("verse-impulse").value = verse.impulse || "";

    // Canva config
    const canva = state.canva || {};
    document.getElementById("canva-title").value = canva.title || "";
    document.getElementById("canva-url").value = canva.url || "";

    // Tasks list
    renderTasks(state.tasks || []);
  }

  function renderTasks(tasks) {
    const container = document.getElementById("admin-tasks-list");
    container.innerHTML = tasks
      .map(
        (t) => `
      <div class="admin-task-item">
        <div>
          <div class="admin-task-title">${escapeHtml(t.title)}</div>
          <div class="admin-task-sub">
            ${escapeHtml(t.category || "Allgemein")} · 👤 ${escapeHtml(t.assignee || "Team")} · ⏱️ ${escapeHtml(t.due || "")}
          </div>
        </div>
        <div class="fleet-node-actions">
          <button class="btn btn-sm btn-secondary" data-task-toggle="${escapeHtml(t.id)}">
            ${escapeHtml(STATUS_LABELS[t.status] || t.status)}
          </button>
          <button class="btn btn-sm btn-danger" data-task-delete="${escapeHtml(t.id)}">🗑️</button>
        </div>
      </div>
    `
      )
      .join("");

    container.querySelectorAll("[data-task-toggle]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const res = await apiPost("/api/tasks", { action: "toggle", id: btn.dataset.taskToggle });
        if (res.ok) {
          renderTasks(res.tasks);
          showToast("Aufgaben-Status aktualisiert!");
        }
      });
    });

    container.querySelectorAll("[data-task-delete]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const res = await apiPost("/api/tasks", { action: "delete", id: btn.dataset.taskDelete });
        if (res.ok) {
          renderTasks(res.tasks);
          showToast("Aufgabe gelöscht.");
        }
      });
    });
  }

  async function refreshFleetStatus() {
    try {
      const resp = await fetch("/api/fleet/status");
      const data = await resp.json();
      if (!data.ok) return;
      const list = document.getElementById("fleet-list");
      list.innerHTML = (data.nodes || [])
        .map(
          (n) => `
        <div class="fleet-node">
          <div>
            <div class="fleet-node-title">
              <span class="dot ${n.online ? "online" : "offline"}"></span>
              <span>${escapeHtml(n.name)}</span>
            </div>
            <div class="fleet-node-meta">
              ${escapeHtml(n.location)} · <code>${escapeHtml(n.host)}</code> ·
              Modus: <strong>${escapeHtml((n.mode || "–").toUpperCase())}</strong> ·
              TV: <strong>${escapeHtml((n.tv_power || "–").toUpperCase())}</strong>
            </div>
          </div>
          <div class="fleet-node-actions">
            <button class="btn btn-sm btn-secondary" data-node="${escapeHtml(n.id)}" data-node-mode="canva">Canva</button>
            <button class="btn btn-sm btn-secondary" data-node="${escapeHtml(n.id)}" data-node-mode="dashboard">Dashboard</button>
            <button class="btn btn-sm btn-secondary" data-node="${escapeHtml(n.id)}" data-node-mode="verse">Vers</button>
            <button class="btn btn-sm btn-secondary" data-node="${escapeHtml(n.id)}" data-node-mode="rotation">Loop</button>
            <button class="btn btn-sm btn-success" data-node="${escapeHtml(n.id)}" data-node-pwr="on">TV Ein</button>
            <button class="btn btn-sm btn-danger" data-node="${escapeHtml(n.id)}" data-node-pwr="standby">TV Aus</button>
            ${!n.is_local ? `<button class="btn btn-sm btn-danger" data-node-del="${escapeHtml(n.id)}">✖</button>` : ""}
          </div>
        </div>
      `
        )
        .join("");

      list.querySelectorAll("[data-node-mode]").forEach((btn) => {
        btn.addEventListener("click", async () => {
          await apiPost("/api/fleet/command", {
            target: btn.dataset.node,
            command: "mode",
            payload: { mode: btn.dataset.nodeMode },
          });
          showToast(`Modus "${btn.dataset.nodeMode}" an Pi gesendet!`);
          loadInitialState();
          refreshFleetStatus();
        });
      });

      list.querySelectorAll("[data-node-pwr]").forEach((btn) => {
        btn.addEventListener("click", async () => {
          await apiPost("/api/fleet/command", {
            target: btn.dataset.node,
            command: "tv_power",
            payload: { action: btn.dataset.nodePwr },
          });
          showToast(`HDMI-CEC Power "${btn.dataset.nodePwr}" gesendet!`);
          loadInitialState();
          refreshFleetStatus();
        });
      });

      list.querySelectorAll("[data-node-del]").forEach((btn) => {
        btn.addEventListener("click", async () => {
          await apiPost("/api/fleet/nodes", { action: "delete", id: btn.dataset.nodeDel });
          showToast("Pi aus Liste entfernt.");
          loadInitialState();
          refreshFleetStatus();
        });
      });
    } catch (e) {}
  }

  async function loadInitialState() {
    const resp = await fetch("/api/state");
    const data = await resp.json();
    populateUI(data);
  }

  // Event Listeners
  document.querySelectorAll(".mode-card").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const target = document.getElementById("command-target").value;
      const mode = btn.dataset.mode;
      if (target === "pi-local") {
        await apiPost("/api/display/mode", { mode });
      } else {
        await apiPost("/api/fleet/command", { target, command: "mode", payload: { mode } });
      }
      showToast(`Anzeige-Modus auf "${mode.toUpperCase()}" umgeschaltet!`);
      loadInitialState();
      refreshFleetStatus();
    });
  });

  document.getElementById("btn-save-rotation").addEventListener("click", async () => {
    await apiPost("/api/display/mode", {
      durations_sec: {
        canva: Number(document.getElementById("rot-canva").value || 180),
        dashboard: Number(document.getElementById("rot-dashboard").value || 60),
        verse: Number(document.getElementById("rot-verse").value || 45),
      },
    });
    showToast("Rotations-Intervalle gespeichert!");
  });

  document.getElementById("btn-reload-display").addEventListener("click", async () => {
    const target = document.getElementById("command-target").value;
    await apiPost("/api/fleet/command", { target, command: "reload", payload: {} });
    showToast("Reload-Signal an TV-Display gesendet!");
  });

  document.querySelectorAll("[data-power]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const target = document.getElementById("command-target").value;
      const action = btn.dataset.power;
      if (target === "pi-local") {
        await apiPost("/api/tv/power", { action });
      } else {
        await apiPost("/api/fleet/command", { target, command: "tv_power", payload: { action } });
      }
      showToast(`HDMI-CEC Befehl "${action}" ausgeführt!`);
      loadInitialState();
      refreshFleetStatus();
    });
  });

  document.getElementById("btn-save-schedule").addEventListener("click", async () => {
    await apiPost("/api/tv/schedule", {
      enabled: document.getElementById("sched-enabled").checked,
      off_time: document.getElementById("sched-off-time").value,
      on_time: document.getElementById("sched-on-time").value,
    });
    showToast("TV Nachtabschaltungs-Zeitplan gespeichert!");
    loadInitialState();
  });

  document.getElementById("btn-add-pi").addEventListener("click", async () => {
    const name = document.getElementById("new-pi-name").value.trim();
    const location = document.getElementById("new-pi-loc").value.trim();
    const host = document.getElementById("new-pi-host").value.trim();
    if (!name || !host) {
      showToast("Bitte Name und URL des Raspberry Pi angeben.");
      return;
    }
    await apiPost("/api/fleet/nodes", { action: "add", name, location, host });
    document.getElementById("new-pi-name").value = "";
    document.getElementById("new-pi-loc").value = "";
    document.getElementById("new-pi-host").value = "";
    showToast(`Raspberry Pi "${name}" registriert!`);
    loadInitialState();
    refreshFleetStatus();
  });

  document.getElementById("btn-refresh-fleet").addEventListener("click", () => {
    refreshFleetStatus();
    showToast("Pi-Fleet Status aktualisiert.");
  });

  document.getElementById("btn-add-task").addEventListener("click", async () => {
    const title = document.getElementById("task-title").value.trim();
    if (!title) {
      showToast("Bitte einen Aufgabentitel eingeben.");
      return;
    }
    const res = await apiPost("/api/tasks", {
      action: "add",
      title,
      category: document.getElementById("task-category").value.trim() || "Space & Team",
      assignee: document.getElementById("task-assignee").value.trim() || "Offen",
      due: document.getElementById("task-due").value.trim() || "Diese Woche",
      priority: document.getElementById("task-priority").value,
    });
    document.getElementById("task-title").value = "";
    if (res.ok) {
      renderTasks(res.tasks);
      showToast("Aufgabe zum Church Dashboard hinzugefügt!");
    }
  });

  document.getElementById("btn-notion-sync").addEventListener("click", async () => {
    const res = await apiPost("/api/notion/sync", {});
    if (res.ok) {
      showToast(`${res.synced_count} Aufgaben aus Notion synchronisiert!`);
      loadInitialState();
    } else {
      showToast(res.error || "Notion-Sync Info");
    }
  });

  document.getElementById("btn-save-verse").addEventListener("click", async () => {
    await apiPost("/api/verse", {
      week_label: document.getElementById("verse-week").value,
      reference: document.getElementById("verse-ref").value,
      text: document.getElementById("verse-text").value,
      impulse: document.getElementById("verse-impulse").value,
    });
    showToast("Vers der Woche gespeichert & live auf dem TV aktualisiert!");
  });

  document.getElementById("btn-save-canva").addEventListener("click", async () => {
    const res = await apiPost("/api/canva", {
      title: document.getElementById("canva-title").value,
      url: document.getElementById("canva-url").value,
    });
    if (res.ok) {
      showToast("Canva-URL gespeichert und in canva_url.txt aktualisiert!");
    } else {
      showToast(res.error || "Fehler beim Speichern.");
    }
  });

  document.getElementById("btn-canva-autoplay").addEventListener("click", async () => {
    const res = await apiPost("/api/kiosk/canva-autoplay", {});
    showToast(res.message || res.error || "xdotool Befehl ausgeführt");
  });

  loadInitialState();
  refreshFleetStatus();
})();
