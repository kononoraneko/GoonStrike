const state = {
  backendUrl: "",
  adminToken: "",
};

const backendUrlInput = document.getElementById("backendUrl");
const adminTokenInput = document.getElementById("adminToken");
const serverIdInput = document.getElementById("serverId");
const keyIdInput = document.getElementById("keyId");
const secretInput = document.getElementById("secret");
const isActiveInput = document.getElementById("isActive");
const credentialsBody = document.getElementById("credentialsBody");
const serversBody = document.getElementById("serversBody");
const statusLog = document.getElementById("statusLog");

function log(message) {
  statusLog.textContent = `[${new Date().toLocaleTimeString()}] ${message}\n${statusLog.textContent}`;
}

function formatDetail(detail) {
  if (detail == null || detail === "") {
    return "";
  }
  if (typeof detail === "string") {
    return detail;
  }
  if (Array.isArray(detail)) {
    return detail
      .map((e) => {
        if (typeof e === "object" && e !== null && "msg" in e) {
          const loc = Array.isArray(e.loc) ? e.loc.join(".") : "";
          return loc ? `${loc}: ${e.msg}` : String(e.msg);
        }
        return JSON.stringify(e);
      })
      .join("; ");
  }
  if (typeof detail === "object") {
    return JSON.stringify(detail);
  }
  return String(detail);
}

function loadSettings() {
  state.backendUrl = localStorage.getItem("gs_admin_backend_url") || "http://127.0.0.1:8000";
  state.adminToken = localStorage.getItem("gs_admin_token") || "";
  backendUrlInput.value = state.backendUrl;
  adminTokenInput.value = state.adminToken;
}

function saveSettings() {
  state.backendUrl = backendUrlInput.value.trim().replace(/\/$/, "");
  state.adminToken = adminTokenInput.value.trim();
  localStorage.setItem("gs_admin_backend_url", state.backendUrl);
  localStorage.setItem("gs_admin_token", state.adminToken);
  log("Settings saved.");
}

async function request(path, options = {}) {
  if (!state.backendUrl) {
    throw new Error("Backend URL is empty.");
  }
  const response = await fetch(`${state.backendUrl}${path}`, options);
  const text = await response.text();
  let json = {};
  if (text) {
    try {
      json = JSON.parse(text);
    } catch (_e) {
      json = { raw: text };
    }
  }
  if (!response.ok) {
    const detailMsg = formatDetail(json.detail);
    throw new Error(`HTTP ${response.status}: ${detailMsg || text || "request failed"}`);
  }
  return json;
}

function setRows(tbody, rows, mapper) {
  tbody.innerHTML = "";
  for (const row of rows) {
    const tr = document.createElement("tr");
    mapper(row).forEach((value) => {
      const td = document.createElement("td");
      td.textContent = value;
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  }
}

function statusBadge(status) {
  const text = String(status || "").toLowerCase();
  if (text.includes("up")) return "running";
  if (text.includes("exited") || text.includes("dead")) return "stopped";
  if (text.includes("restarting")) return "restarting";
  return text || "unknown";
}

async function refreshCredentials() {
  const json = await request("/servers/admin/credentials", {
    method: "GET",
    headers: {
      "X-GS-Admin-Token": state.adminToken,
    },
  });
  const credentials = json.credentials || [];
  setRows(credentialsBody, credentials, (item) => [
    item.server_id,
    item.key_id,
    item.is_active ? "yes" : "no",
  ]);
  log(`Loaded credentials: ${credentials.length}.`);
}

async function refreshServers() {
  const json = await request("/servers", { method: "GET" });
  const servers = json.servers || [];
  setRows(serversBody, servers, (item) => [
    item.server_id,
    item.display_name,
    `${item.host}:${item.port}`,
    `${item.mode_id}/${item.map_id}`,
    `${item.current_players}/${item.max_players}`,
  ]);
  log(`Loaded trusted online servers: ${servers.length}.`);
}

async function upsertCredential() {
  const payload = {
    server_id: serverIdInput.value.trim(),
    key_id: keyIdInput.value.trim(),
    secret: secretInput.value,
    is_active: isActiveInput.checked,
  };
  if (!payload.server_id || !payload.key_id || !payload.secret) {
    throw new Error("server_id, key_id and secret are required.");
  }
  const json = await request("/servers/admin/credentials", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-GS-Admin-Token": state.adminToken,
    },
    body: JSON.stringify(payload),
  });
  log(`Credential upserted: ${json.server_id}/${json.key_id} active=${json.is_active}.`);
  secretInput.value = "";
  await refreshCredentials();
}

async function withUiError(action) {
  try {
    saveSettings();
    await action();
  } catch (error) {
    log(`Error: ${error.message}`);
  }
}

async function provisionCredentials() {
  const sid = document.getElementById("provisionServerId").value.trim();
  const kid = document.getElementById("provisionKeyId").value.trim();
  const payload = {};
  if (sid) payload.server_id = sid;
  if (kid) payload.key_id = kid;
  const json = await request("/servers/admin/provision", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-GS-Admin-Token": state.adminToken,
    },
    body: JSON.stringify(payload),
  });
  const secret = json.secret ?? "";
  const hint =
    `server_id=${json.server_id}\nkey_id=${json.key_id}\nsecret=${secret}\n\n` +
    `Dedicated example:\n  godot4 ... -- --backend-url ${state.backendUrl} --server-id ${json.server_id} ` +
    `--registry-key-id ${json.key_id} --registry-secret <secret>`;
  document.getElementById("provisionOutput").textContent = hint;
  log(`Provisioned credential ${json.server_id}/${json.key_id}.`);
}

async function mintEnrollmentToken() {
  const constraint = document.getElementById("enrollConstraintServerId").value.trim();
  const ttlRaw = document.getElementById("enrollTtlSec").value.trim();
  const payload = {};
  if (constraint) payload.server_id = constraint;
  if (ttlRaw) {
    const ttl = parseInt(ttlRaw, 10);
    if (!Number.isFinite(ttl)) {
      throw new Error("TTL must be a number.");
    }
    payload.ttl_seconds = ttl;
  }
  const json = await request("/servers/admin/enrollment-tokens", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-GS-Admin-Token": state.adminToken,
    },
    body: JSON.stringify(payload),
  });
  const token = json.enrollment_token ?? "";
  const exp = json.expires_at ?? "";
  const lock = json.server_id_constraint != null ? json.server_id_constraint : "(none)";
  const sidHint =
    json.server_id_constraint != null && json.server_id_constraint !== ""
      ? json.server_id_constraint
      : "dedicated-7000";
  const cmd =
    `godot4 --headless --path . scenes/server/server_bootstrap.tscn -- ` +
    `--port 7000 --backend-url ${state.backendUrl} --server-id ${sidHint} ` +
    `--registry-enroll-token ${token}`;
  const out =
    `enrollment_token=${token}\nexpires_at=${exp}\nserver_id_constraint=${lock}\n\n` +
    `If you set a lock, --server-id must match it. Example:\n${cmd}`;
  document.getElementById("enrollmentOutput").textContent = out;
  log("Minted enrollment token.");
}

async function orchestratorSpawn() {
  const port = parseInt(document.getElementById("spawnPort").value, 10);
  if (!Number.isFinite(port) || port < 1024 || port > 65534) {
    throw new Error("Port must be between 1024 and 65534.");
  }
  const payload = { port };
  const spawnSid = document.getElementById("spawnServerId").value.trim();
  if (spawnSid) {
    payload.server_id = spawnSid;
  }
  payload.map_id = document.getElementById("spawnMapId").value.trim() || "default";
  payload.mode_id = document.getElementById("spawnModeId").value.trim() || "team_elim";
  const spawnBu = document.getElementById("spawnBackendUrl").value.trim();
  if (spawnBu) {
    payload.backend_url = spawnBu;
  }
  const spawnPh = document.getElementById("spawnPublicHost").value.trim();
  if (spawnPh) {
    payload.public_host = spawnPh;
  }
  const spawnImg = document.getElementById("spawnDockerImage").value.trim();
  if (spawnImg) {
    payload.docker_image = spawnImg;
  }
  const spawnTtlRaw = document.getElementById("spawnEnrollTtl").value.trim();
  if (spawnTtlRaw) {
    const ttl = parseInt(spawnTtlRaw, 10);
    if (!Number.isFinite(ttl)) {
      throw new Error("Enrollment TTL must be a number.");
    }
    payload.enrollment_ttl_seconds = ttl;
  }

  const json = await request("/servers/admin/orchestrator/spawn", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-GS-Admin-Token": state.adminToken,
    },
    body: JSON.stringify(payload),
  });

  const orchText = JSON.stringify(json.orchestrator ?? {}, null, 2);
  document.getElementById("spawnOrchestratorOutput").textContent =
    `server_id=${json.server_id}\nenrollment_expires_at=${json.enrollment_expires_at ?? ""}\n\norchestrator:\n${orchText}`;
  log(`Spawn OK: ${json.server_id}`);
  await refreshOrchestratorContainers();
  await refreshServers();
}

async function refreshOrchestratorContainers() {
  const orchBody = document.getElementById("orchestratorContainersBody");
  const json = await request("/servers/admin/orchestrator/instances", {
    method: "GET",
    headers: {
      "X-GS-Admin-Token": state.adminToken,
    },
  });
  const rows = json.containers || [];
  setRows(orchBody, rows, (item) => {
    const port = item.port ?? "";
    return [
      item.name ?? "",
      String(port),
      statusBadge(item.status),
      item.ports ?? "",
    ];
  });
  log(`Orchestrator containers: ${rows.length}.`);
}

async function orchestratorStop() {
  const stopPort = parseInt(document.getElementById("stopOrchestratorPort").value, 10);
  if (!Number.isFinite(stopPort) || stopPort < 1024 || stopPort > 65534) {
    throw new Error("Enter a valid port (1024–65534) to remove.");
  }
  const json = await request(`/servers/admin/orchestrator/instances/${stopPort}`, {
    method: "DELETE",
    headers: {
      "X-GS-Admin-Token": state.adminToken,
    },
  });
  log(`Removed: ${JSON.stringify(json)}`);
  await refreshOrchestratorContainers();
  await refreshServers();
}

async function orchestratorInspect() {
  const port = parseInt(document.getElementById("inspectOrchestratorPort").value, 10);
  if (!Number.isFinite(port) || port < 1024 || port > 65534) {
    throw new Error("Enter a valid port (1024–65534) to inspect.");
  }
  const json = await request(`/servers/admin/orchestrator/instances/${port}`, {
    method: "GET",
    headers: {
      "X-GS-Admin-Token": state.adminToken,
    },
  });
  document.getElementById("orchestratorInspectOutput").textContent = JSON.stringify(json, null, 2);
  log(`Inspect OK: ${port}`);
}

async function orchestratorLogs() {
  const port = parseInt(document.getElementById("inspectOrchestratorPort").value, 10);
  if (!Number.isFinite(port) || port < 1024 || port > 65534) {
    throw new Error("Enter a valid port (1024–65534) to tail logs.");
  }
  const json = await request(`/servers/admin/orchestrator/instances/${port}/logs?tail=200`, {
    method: "GET",
    headers: {
      "X-GS-Admin-Token": state.adminToken,
    },
  });
  const text = (json.logs ?? "").trim();
  document.getElementById("orchestratorInspectOutput").textContent = text || "(no logs)";
  log(`Logs OK: ${port}`);
}

document.getElementById("saveSettingsBtn").addEventListener("click", () => withUiError(async () => {}));
document.getElementById("provisionBtn").addEventListener("click", () => withUiError(provisionCredentials));
document.getElementById("mintEnrollmentBtn").addEventListener("click", () => withUiError(mintEnrollmentToken));
document.getElementById("refreshCredentialsBtn").addEventListener("click", () => withUiError(refreshCredentials));
document.getElementById("refreshServersBtn").addEventListener("click", () => withUiError(refreshServers));
document.getElementById("upsertCredentialBtn").addEventListener("click", () => withUiError(upsertCredential));
document.getElementById("spawnOrchestratorBtn").addEventListener("click", () => withUiError(orchestratorSpawn));
document.getElementById("refreshOrchestratorBtn").addEventListener("click", () => withUiError(refreshOrchestratorContainers));
document.getElementById("stopOrchestratorBtn").addEventListener("click", () => withUiError(orchestratorStop));
document.getElementById("inspectOrchestratorBtn").addEventListener("click", () => withUiError(orchestratorInspect));
document.getElementById("logsOrchestratorBtn").addEventListener("click", () => withUiError(orchestratorLogs));

loadSettings();
withUiError(async () => {
  await refreshCredentials();
  await refreshServers();
});
withUiError(async () => {
  try {
    saveSettings();
    await refreshOrchestratorContainers();
  } catch (e) {
    log(`Orchestrator list: ${e.message}`);
  }
});
