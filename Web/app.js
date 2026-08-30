"use strict";

// Configure the deployed Pixel Streaming frontend here when the backend is ready.
const PIXEL_STREAMING_URL = "";

const StreamState = Object.freeze({
  OFFLINE: "offline",
  CHECKING: "checking",
  REACHABLE: "reachable",
  NEGOTIATING: "negotiating",
  CONNECTED: "connected",
  RECONNECTING: "reconnecting",
  FAILED: "failed",
});

const STREAM_MESSAGE_TYPE = "ASWW_PIXEL_STREAMING_STATE";
const SESSION_TIMEOUT_MS = 20000;
const MAX_RECONNECT_ATTEMPTS = 4;
const RECONNECT_BASE_DELAY_MS = 1500;
const RECONNECT_MAX_DELAY_MS = 12000;

const connection = {
  endpoint: null,
  expectedOrigin: null,
  activeSessionId: null,
  state: StreamState.CHECKING,
  probePromise: null,
  sessionGeneration: 0,
  reconnectAttempts: 0,
  sessionTimeoutId: null,
  reconnectTimerId: null,
  toastTimerId: null,
};

const ui = {};

function cacheUi() {
  ui.root = document.documentElement;
  ui.bootScreen = document.querySelector("#boot-screen");
  ui.bootProgress = document.querySelector("#boot-progress");
  ui.bootStatus = document.querySelector("#boot-status");
  ui.statusText = document.querySelector("#status-text");
  ui.connectionState = document.querySelector("#connection-state");
  ui.readinessValue = document.querySelector("#readiness-value");
  ui.serverMessage = document.querySelector("#server-message");
  ui.playButton = document.querySelector("#play-button");
  ui.launchHint = document.querySelector("#launch-hint");
  ui.clientProfile = document.querySelector("#client-profile");
  ui.inputDevices = document.querySelector("#input-devices");
  ui.offlineToast = document.querySelector("#offline-toast");
  ui.retryProbe = document.querySelector("#retry-probe");
  ui.streamExperience = document.querySelector("#stream-experience");
  ui.streamFrame = document.querySelector("#stream-frame");
  ui.streamLoading = document.querySelector("#stream-loading");
  ui.streamLoadingTitle = document.querySelector("#stream-loading-title");
  ui.streamLoadingDetail = document.querySelector("#stream-loading-detail");
  ui.retryStream = document.querySelector("#retry-stream");
  ui.closeStream = document.querySelector("#close-stream");
}

function detectClientProfile() {
  const coarsePointer = window.matchMedia("(pointer: coarse)").matches;
  const compactViewport = window.matchMedia("(max-width: 760px)").matches;
  ui.clientProfile.textContent = coarsePointer || compactViewport ? "MOBILE / TOUCH" : "DESKTOP";
  updateInputDevices();
}

function updateInputDevices() {
  const inputDevices = [];
  const touchReady = navigator.maxTouchPoints > 0 || window.matchMedia("(any-pointer: coarse)").matches;
  const precisionPointerReady = window.matchMedia("(any-pointer: fine)").matches;
  const connectedGamepads = typeof navigator.getGamepads === "function"
    ? Array.from(navigator.getGamepads()).filter(Boolean)
    : [];

  if (touchReady) {
    inputDevices.push("TOUCH");
  }
  if (precisionPointerReady) {
    inputDevices.push("KB/MOUSE");
  }
  if (connectedGamepads.length > 0) {
    inputDevices.push("GAMEPAD");
  }

  ui.inputDevices.textContent = inputDevices.length > 0 ? inputDevices.join(" + ") : "KEYBOARD READY";
}

function resolveStreamingEndpoint() {
  const configuredValue = PIXEL_STREAMING_URL.trim();
  if (!configuredValue) {
    return null;
  }

  try {
    const endpoint = new URL(configuredValue);
    if (endpoint.protocol !== "https:" && endpoint.protocol !== "http:") {
      return null;
    }
    if (endpoint.username || endpoint.password) {
      return null;
    }
    if (window.location.protocol === "https:" && endpoint.protocol !== "https:") {
      return null;
    }
    return endpoint.href;
  } catch {
    return null;
  }
}

const STATE_PRESENTATION = Object.freeze({
  [StreamState.CHECKING]: {
    statusText: "CHECKING CONNECTION",
    connectionState: "CHECKING",
    readinessValue: "--",
    launchHint: "Checking the configured streaming endpoint",
    messageIcon: "…",
    messageTitle: "VERIFYING GAME SERVER",
    messageDetail: "Checking the secure deployment route.",
  },
  [StreamState.OFFLINE]: {
    statusText: "GAME SERVER OFFLINE",
    connectionState: "OFFLINE",
    readinessValue: "0%",
    launchHint: "Deployment channel currently unavailable",
    messageIcon: "!",
    messageTitle: "GAME SERVER OFFLINE",
    messageDetail: "No live Pixel Streaming deployment is available.",
  },
  [StreamState.REACHABLE]: {
    statusText: "STREAM ENDPOINT REACHABLE",
    connectionState: "REACHABLE",
    readinessValue: "LINK",
    launchHint: "Endpoint reachable; WebRTC is negotiated when you launch",
    messageIcon: "✓",
    messageTitle: "STREAM ENDPOINT REACHABLE",
    messageDetail: "The frontend responded. A successful gameplay session still requires WebRTC negotiation.",
  },
  [StreamState.NEGOTIATING]: {
    statusText: "NEGOTIATING WEBRTC",
    connectionState: "NEGOTIATING",
    readinessValue: "SYNC",
    launchHint: "Waiting for a verified gameplay session",
    messageIcon: "…",
    messageTitle: "WEBRTC NEGOTIATION IN PROGRESS",
    messageDetail: "The streaming frontend must confirm that the gameplay media session is connected.",
  },
  [StreamState.CONNECTED]: {
    statusText: "GAME SESSION CONNECTED",
    connectionState: "CONNECTED",
    readinessValue: "100%",
    launchHint: "Verified WebRTC gameplay session",
    messageIcon: "✓",
    messageTitle: "LIVE GAMEPLAY SESSION",
    messageDetail: "The Pixel Streaming frontend confirmed the WebRTC gameplay connection.",
  },
  [StreamState.RECONNECTING]: {
    statusText: "RECONNECTING SESSION",
    connectionState: "RECONNECTING",
    readinessValue: "RETRY",
    launchHint: "Recovering the interrupted WebRTC session",
    messageIcon: "…",
    messageTitle: "RECONNECTING GAMEPLAY",
    messageDetail: "The launcher is starting a bounded reconnect attempt.",
  },
  [StreamState.FAILED]: {
    statusText: "SESSION CONNECTION FAILED",
    connectionState: "FAILED",
    readinessValue: "ERR",
    launchHint: "Use Retry to start a clean session attempt",
    messageIcon: "!",
    messageTitle: "WEBRTC SESSION NOT VERIFIED",
    messageDetail: "The frontend did not confirm a gameplay connection before the session timed out.",
  },
});

function setConnectionState(state) {
  if (!Object.values(StreamState).includes(state)) {
    return;
  }

  const presentation = STATE_PRESENTATION[state];
  connection.state = state;
  ui.root.dataset.serverState = state;
  ui.statusText.textContent = presentation.statusText;
  ui.connectionState.textContent = presentation.connectionState;
  ui.readinessValue.textContent = presentation.readinessValue;
  ui.launchHint.textContent = presentation.launchHint;
  ui.serverMessage.innerHTML = `<span aria-hidden="true">${presentation.messageIcon}</span><div><strong>${presentation.messageTitle}</strong><p>${presentation.messageDetail}</p></div>`;
}

function clearSessionTimers() {
  window.clearTimeout(connection.sessionTimeoutId);
  window.clearTimeout(connection.reconnectTimerId);
  connection.sessionTimeoutId = null;
  connection.reconnectTimerId = null;
}

function createSessionId() {
  if (typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function teardownSession({ hideExperience = true, resetAttempts = true } = {}) {
  connection.sessionGeneration += 1;
  connection.activeSessionId = null;
  clearSessionTimers();
  ui.streamFrame.removeAttribute("src");
  ui.streamLoading.hidden = false;
  ui.retryStream.hidden = true;

  if (hideExperience) {
    ui.streamExperience.hidden = true;
    document.body.style.overflow = "";
  }
  if (resetAttempts) {
    connection.reconnectAttempts = 0;
  }
}

async function probeStreamingBackend() {
  if (connection.probePromise) {
    return connection.probePromise;
  }

  connection.endpoint = resolveStreamingEndpoint();
  connection.expectedOrigin = connection.endpoint ? new URL(connection.endpoint).origin : null;
  setConnectionState(StreamState.CHECKING);

  connection.probePromise = (async () => {
    if (!connection.endpoint || !navigator.onLine) {
      setConnectionState(StreamState.OFFLINE);
      return false;
    }

    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 5000);

    try {
      // An opaque no-CORS response proves network reachability only.
      // It must never be treated as proof of Pixel Streaming readiness.
      await fetch(connection.endpoint, {
        method: "HEAD",
        mode: "no-cors",
        cache: "no-store",
        credentials: "omit",
        referrerPolicy: "no-referrer",
        signal: controller.signal,
      });
      setConnectionState(StreamState.REACHABLE);
      return true;
    } catch {
      setConnectionState(StreamState.OFFLINE);
      return false;
    } finally {
      window.clearTimeout(timeoutId);
      connection.probePromise = null;
    }
  })();

  return connection.probePromise;
}

function showOfflineNotice() {
  ui.offlineToast.hidden = false;
  window.clearTimeout(connection.toastTimerId);
  connection.toastTimerId = window.setTimeout(() => {
    ui.offlineToast.hidden = true;
  }, 5200);
}

function updateStreamLoading(title, detail, showRetry = false) {
  ui.streamLoading.hidden = false;
  ui.streamLoadingTitle.textContent = title;
  ui.streamLoadingDetail.textContent = detail;
  ui.retryStream.hidden = !showRetry;
}

function armSessionTimeout(generation) {
  window.clearTimeout(connection.sessionTimeoutId);
  connection.sessionTimeoutId = window.setTimeout(() => {
    if (generation !== connection.sessionGeneration || connection.state === StreamState.CONNECTED) {
      return;
    }
    handleSessionFailure("The gameplay frontend did not confirm WebRTC before timeout.");
  }, SESSION_TIMEOUT_MS);
}

function startStreamSession() {
  if (!connection.endpoint || !connection.expectedOrigin) {
    handleSessionFailure("No valid Pixel Streaming frontend is configured.", false);
    return;
  }

  clearSessionTimers();
  connection.sessionGeneration += 1;
  const generation = connection.sessionGeneration;
  connection.activeSessionId = createSessionId();
  const sessionEndpoint = new URL(connection.endpoint);
  sessionEndpoint.searchParams.set("aswwLauncherSession", connection.activeSessionId);
  ui.streamFrame.dataset.sessionGeneration = String(generation);
  ui.streamExperience.hidden = false;
  document.body.style.overflow = "hidden";
  updateStreamLoading("ESTABLISHING SECURE UPLINK", "Waiting for the Pixel Streaming WebRTC handshake");
  setConnectionState(StreamState.NEGOTIATING);
  ui.streamFrame.removeAttribute("src");
  ui.streamFrame.src = sessionEndpoint.href;
  armSessionTimeout(generation);
}

function scheduleReconnect() {
  if (connection.reconnectTimerId !== null || ui.streamExperience.hidden) {
    return;
  }
  window.clearTimeout(connection.sessionTimeoutId);
  connection.sessionTimeoutId = null;
  connection.sessionGeneration += 1;
  connection.activeSessionId = null;
  ui.streamFrame.removeAttribute("src");
  if (!navigator.onLine || connection.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    handleSessionFailure("Automatic reconnect attempts are exhausted.", false);
    return;
  }

  connection.reconnectAttempts += 1;
  const attempt = connection.reconnectAttempts;
  const delay = Math.min(RECONNECT_BASE_DELAY_MS * (2 ** (attempt - 1)), RECONNECT_MAX_DELAY_MS);
  setConnectionState(StreamState.RECONNECTING);
  updateStreamLoading("RECONNECTING GAMEPLAY", `Attempt ${attempt} of ${MAX_RECONNECT_ATTEMPTS}`);
  connection.reconnectTimerId = window.setTimeout(() => {
    connection.reconnectTimerId = null;
    startStreamSession();
  }, delay);
}

function handleSessionFailure(detail, allowReconnect = true) {
  window.clearTimeout(connection.sessionTimeoutId);
  connection.sessionTimeoutId = null;
  updateStreamLoading("SESSION CONNECTION FAILED", detail, true);

  if (allowReconnect && connection.reconnectAttempts < MAX_RECONNECT_ATTEMPTS && navigator.onLine) {
    scheduleReconnect();
    return;
  }
  setConnectionState(StreamState.FAILED);
}

function closeStream() {
  teardownSession();
  if (connection.endpoint && navigator.onLine) {
    setConnectionState(StreamState.REACHABLE);
  } else {
    setConnectionState(StreamState.OFFLINE);
  }
  ui.playButton.focus({ preventScroll: true });
}

async function launchGame(forceFreshSession = false) {
  ui.offlineToast.hidden = true;

  if (forceFreshSession) {
    teardownSession({ hideExperience: false });
  }

  const endpointIsReachable = connection.state === StreamState.REACHABLE
    || connection.state === StreamState.NEGOTIATING
    || connection.state === StreamState.RECONNECTING
    || connection.state === StreamState.CONNECTED;

  if (!endpointIsReachable || forceFreshSession) {
    const available = await probeStreamingBackend();
    if (!available) {
      if (!ui.streamExperience.hidden) {
        updateStreamLoading("GAME SERVER OFFLINE", "The configured endpoint could not be reached.", true);
      }
      showOfflineNotice();
      return;
    }
  }

  startStreamSession();
}

function isValidStreamMessage(event) {
  if (event.source !== ui.streamFrame.contentWindow || event.origin !== connection.expectedOrigin) {
    return false;
  }
  if (!event.data || typeof event.data !== "object" || Array.isArray(event.data)) {
    return false;
  }
  return event.data.type === STREAM_MESSAGE_TYPE
    && event.data.sessionId === connection.activeSessionId
    && typeof event.data.state === "string"
    && ["negotiating", "connected", "disconnected", "reconnecting", "failed"].includes(event.data.state);
}

function handleStreamMessage(event) {
  if (!isValidStreamMessage(event) || ui.streamExperience.hidden) {
    return;
  }

  switch (event.data.state) {
    case "connected":
      clearSessionTimers();
      connection.reconnectAttempts = 0;
      ui.streamLoading.hidden = true;
      setConnectionState(StreamState.CONNECTED);
      break;
    case "negotiating":
      setConnectionState(StreamState.NEGOTIATING);
      updateStreamLoading("NEGOTIATING WEBRTC", "The frontend is establishing gameplay media and input channels");
      break;
    case "reconnecting":
    case "disconnected":
      scheduleReconnect();
      break;
    case "failed":
      handleSessionFailure("The Pixel Streaming frontend reported a session failure.");
      break;
    default:
      break;
  }
}

function finishBootSequence() {
  ui.bootStatus.textContent = "Deployment interface ready";
  ui.bootProgress.style.width = "100%";
  window.setTimeout(() => ui.bootScreen.classList.add("is-complete"), 380);
}

function bindEvents() {
  ui.playButton.addEventListener("click", () => launchGame());
  ui.closeStream.addEventListener("click", closeStream);
  ui.retryStream.addEventListener("click", () => launchGame(true));
  ui.retryProbe.addEventListener("click", async () => {
    ui.offlineToast.hidden = true;
    const available = await probeStreamingBackend();
    if (!available) {
      showOfflineNotice();
    }
  });

  ui.streamFrame.addEventListener("load", () => {
    if (ui.streamExperience.hidden || !ui.streamFrame.getAttribute("src")) {
      return;
    }
    // Loading an iframe document is not proof of a WebRTC gameplay connection.
    if (connection.state !== StreamState.CONNECTED) {
      setConnectionState(StreamState.NEGOTIATING);
      updateStreamLoading("FRONTEND LOADED", "Waiting for verified WebRTC gameplay confirmation");
    }
  });

  window.addEventListener("message", handleStreamMessage);
  window.addEventListener("online", () => {
    if (!ui.streamExperience.hidden) {
      scheduleReconnect();
    } else {
      probeStreamingBackend();
    }
  });
  window.addEventListener("offline", () => {
    clearSessionTimers();
    setConnectionState(StreamState.OFFLINE);
    if (!ui.streamExperience.hidden) {
      updateStreamLoading("NETWORK OFFLINE", "Reconnect will be available when network access returns.", true);
    }
  });
  window.addEventListener("resize", detectClientProfile, { passive: true });
  window.addEventListener("gamepadconnected", updateInputDevices);
  window.addEventListener("gamepaddisconnected", updateInputDevices);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !ui.streamExperience.hidden) {
      closeStream();
    }
  });
}

function initializeLauncher() {
  cacheUi();
  detectClientProfile();
  bindEvents();
  setConnectionState(StreamState.CHECKING);
  ui.bootProgress.style.width = "72%";
  probeStreamingBackend();
  window.setTimeout(finishBootSequence, 520);
}

document.addEventListener("DOMContentLoaded", initializeLauncher);
