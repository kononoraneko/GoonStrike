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
    throw new Error(`HTTP ${response.status}: ${json.detail || text || "request failed"}`);
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

document.getElementById("saveSettingsBtn").addEventListener("click", () => withUiError(async () => {}));
document.getElementById("refreshCredentialsBtn").addEventListener("click", () => withUiError(refreshCredentials));
document.getElementById("refreshServersBtn").addEventListener("click", () => withUiError(refreshServers));
document.getElementById("upsertCredentialBtn").addEventListener("click", () => withUiError(upsertCredential));

loadSettings();
withUiError(async () => {
  await refreshCredentials();
  await refreshServers();
});
