import http from "k6/http";
import ws from "k6/ws";
import { check, sleep } from "k6";
import { Rate } from "k6/metrics";

const baseUrl = (__ENV.BASE_URL || "http://host.docker.internal:5200").replace(/\/$/, "");
const wsBaseUrl = baseUrl.replace(/^http/, "ws");
const duration = __ENV.PERF_DURATION || "2m";
const email = __ENV.PERF_EMAIL;
const password = __ENV.PERF_PASSWORD;
const workspaceId = __ENV.WORKSPACE_ID;
const roomCode = __ENV.ROOM_CODE;
const transcriptId = __ENV.TRANSCRIPT_ID;

export const signalrConnected = new Rate("signalr_connected");
export const signalrHandshake = new Rate("signalr_handshake");

export const options = {
  scenarios: {
    authentication: {
      executor: "constant-vus",
      exec: "authentication",
      vus: Number(__ENV.AUTH_VUS || 2),
      duration,
      gracefulStop: "5s",
    },
    workspace_and_transcript: {
      executor: "constant-vus",
      exec: "workspaceAndTranscript",
      vus: Number(__ENV.API_VUS || 8),
      duration,
      gracefulStop: "5s",
    },
    room_join: {
      executor: "constant-vus",
      exec: "roomJoin",
      vus: Number(__ENV.JOIN_VUS || 2),
      duration,
      gracefulStop: "5s",
    },
    signalr: {
      executor: "constant-vus",
      exec: "signalR",
      vus: Number(__ENV.SIGNALR_VUS || 2),
      duration,
      gracefulStop: "5s",
    },
  },
  thresholds: {
    checks: ["rate>0.99"],
    http_req_failed: ["rate<0.01"],
    "http_req_duration{endpoint:auth_login}": ["p(95)<500"],
    "http_req_duration{endpoint:workspaces}": ["p(95)<500"],
    "http_req_duration{endpoint:room_join}": ["p(95)<500"],
    "http_req_duration{endpoint:transcript}": ["p(95)<500"],
    signalr_connected: ["rate>0.99"],
    signalr_handshake: ["rate>0.99"],
  },
};

function requireEnvironment() {
  const missing = [];
  if (!email) missing.push("PERF_EMAIL");
  if (!password) missing.push("PERF_PASSWORD");
  if (!workspaceId) missing.push("WORKSPACE_ID");
  if (!roomCode) missing.push("ROOM_CODE");
  if (!transcriptId) missing.push("TRANSCRIPT_ID");
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  }
}

function login(tags = { endpoint: "auth_login" }) {
  const response = http.post(
    `${baseUrl}/api/v1/auth/login`,
    JSON.stringify({ email, password, ipAddress: null, deviceInfo: "k6" }),
    {
      headers: { "Content-Type": "application/json" },
      tags,
    },
  );
  const valid = check(response, {
    "login returns 200": (r) => r.status === 200,
    "login returns access token": (r) => Boolean(r.json("accessToken")),
  });
  return valid ? response.json("accessToken") : "";
}

export function setup() {
  requireEnvironment();
  const token = login({ endpoint: "setup_login" });
  if (!token) throw new Error("Unable to obtain setup access token");
  return { token };
}

export function authentication() {
  login();
  sleep(1);
}

function authParams(token, endpoint) {
  return {
    headers: {
      Authorization: `Bearer ${token}`,
      "X-Workspace-Id": workspaceId,
    },
    tags: { endpoint },
  };
}

export function workspaceAndTranscript(data) {
  const workspaces = http.get(
    `${baseUrl}/api/v1/workspaces?page=1&pageSize=20`,
    authParams(data.token, "workspaces"),
  );
  check(workspaces, { "workspace list returns 200": (r) => r.status === 200 });

  const transcript = http.get(
    `${baseUrl}/api/v1/transcripts/${transcriptId}`,
    authParams(data.token, "transcript"),
  );
  check(transcript, { "transcript returns 200": (r) => r.status === 200 });
  sleep(0.5);
}

export function roomJoin(data) {
  const params = authParams(data.token, "room_join");
  params.headers["Content-Type"] = "application/json";
  const response = http.post(
    `${baseUrl}/api/v1/translation-rooms/join`,
    JSON.stringify({
      translationRoomCode: roomCode,
      displayName: "Performance Test",
      speakLanguage: "en",
      listenLanguage: "vi",
    }),
    params,
  );
  check(response, { "room join returns 200": (r) => r.status === 200 });
  sleep(1);
}

export function signalR(data) {
  const negotiate = http.post(
    `${baseUrl}/hubs/translation-room/negotiate?negotiateVersion=1`,
    null,
    authParams(data.token, "signalr_negotiate"),
  );
  const negotiated = check(negotiate, {
    "SignalR negotiate returns 200": (r) => r.status === 200,
    "SignalR negotiate returns connection token": (r) => Boolean(r.json("connectionToken")),
  });
  if (!negotiated) {
    signalrConnected.add(false);
    signalrHandshake.add(false);
    sleep(1);
    return;
  }

  const connectionToken = encodeURIComponent(negotiate.json("connectionToken"));
  const accessToken = encodeURIComponent(data.token);
  const response = ws.connect(
    `${wsBaseUrl}/hubs/translation-room?id=${connectionToken}&access_token=${accessToken}`,
    { tags: { endpoint: "signalr_websocket" } },
    (socket) => {
      let handshakeComplete = false;
      socket.on("open", () => {
        signalrConnected.add(true);
        socket.send('{"protocol":"json","version":1}\u001e');
      });
      socket.on("message", (message) => {
        if (!handshakeComplete && String(message).includes("{}")) {
          handshakeComplete = true;
          signalrHandshake.add(true);
          socket.send('{"type":6}\u001e');
        }
      });
      socket.on("error", () => {
        signalrConnected.add(false);
        if (!handshakeComplete) signalrHandshake.add(false);
      });
      socket.setTimeout(() => {
        if (!handshakeComplete) signalrHandshake.add(false);
        socket.close();
      }, 2000);
    },
  );

  check(response, { "SignalR WebSocket upgrades": (r) => r && r.status === 101 });
  sleep(0.5);
}
