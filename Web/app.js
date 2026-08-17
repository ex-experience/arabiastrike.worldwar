"use strict";

// Configure the deployed Pixel Streaming frontend here when the backend is ready.
const PIXEL_STREAMING_URL = "";

const connection = {
  endpoint: null,
  state: "checking",
  probePromise: null,
  streamLoadTimer: null,
  toastTimer: null,
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
  ui.offlineToast = document.querySelector("#offline-toast");
  ui.streamExperience = document.querySelector("#stream-experience");
  ui.streamFrame = document.querySelector("#stream-frame");
  ui.streamLoading = document.querySelector("#stream-loading");
  ui.closeStream = document.querySelector("#close-stream");
}

function detectClientProfile() {
  const coarsePointer = window.matchMedia("(pointer: coarse)").matches;
  const compactViewport = window.matchMedia("(max-width: 760px)").matches;
  ui.clientProfile.textContent = coarsePointer || compactViewport ? "MOBILE / TOUCH" : "DESKTOP";
}

function resolveStreamingEndpoint() {
  const configuredValue = PIXEL_STREAMING_URL.trim();
  if (!configuredValue) {
    return null;
  }

  try {
    const endpoint = new URL(configuredValue, window.location.href);
    if (endpoint.protocol !== "https:" && endpoint.protocol !== "http:") {
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

function setConnectionState(state) {
  connection.state = state;
  ui.root.dataset.serverState = state;

  if (state === "online") {
    ui.statusText.textContent = "GAME SERVER ONLINE";
    ui.connectionState.textContent = "READY";
    ui.readinessValue.textContent = "100%";
    ui.launchHint.textContent = "Secure deployment channel ready";
    ui.serverMessage.innerHTML = "<span aria-hidden=\"true\">✓</span><div><strong>GAME SERVER ONLINE</strong><p>Pixel Streaming frontend is accepting connections.</p></div>";
    return;
  }

  if (state === "offline") {
    ui.statusText.textContent = "GAME SERVER OFFLINE";
    ui.connectionState.textContent = "OFFLINE";
    ui.readinessValue.textContent = "0%";
    ui.launchHint.textContent = "Deployment channel currently unavailable";
    ui.serverMessage.innerHTML = "<span aria-hidden=\"true\">!</span><div><strong>GAME SERVER OFFLINE</strong><p>No live Pixel Streaming deployment is available.</p></div>";
    return;
  }

  ui.statusText.textContent = "CHECKING CONNECTION";
  ui.connectionState.textContent = "PROBING";
  ui.readinessValue.textContent = "--";
  ui.launchHint.textContent = "Secure streaming channel required";
}

async function probeStreamingBackend() {
  if (connection.probePromise) {
    return connection.probePromise;
  }

  connection.endpoint = resolveStreamingEndpoint();
  setConnectionState("checking");

  connection.probePromise = (async () => {
    if (!connection.endpoint || !navigator.onLine) {
      setConnectionState("offline");
      return false;
    }

    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 5000);

    try {
      await fetch(connection.endpoint, {
        method: "HEAD",
        mode: "no-cors",
        cache: "no-store",
        credentials: "omit",
        signal: controller.signal,
      });
      setConnectionState("online");
      return true;
    } catch {
      setConnectionState("offline");
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
  window.clearTimeout(connection.toastTimer);
  connection.toastTimer = window.setTimeout(() => {
    ui.offlineToast.hidden = true;
  }, 4200);
}

function closeStream() {
  window.clearTimeout(connection.streamLoadTimer);
  ui.streamExperience.hidden = true;
  ui.streamLoading.hidden = false;
  ui.streamFrame.src = "about:blank";
  document.body.style.overflow = "";
  ui.playButton.focus({ preventScroll: true });
}

async function launchGame() {
  ui.offlineToast.hidden = true;

  if (connection.state !== "online") {
    const available = await probeStreamingBackend();
    if (!available) {
      showOfflineNotice();
      return;
    }
  }

  ui.streamLoading.hidden = false;
  ui.streamExperience.hidden = false;
  document.body.style.overflow = "hidden";
  ui.streamFrame.src = connection.endpoint;

  window.clearTimeout(connection.streamLoadTimer);
  connection.streamLoadTimer = window.setTimeout(() => {
    closeStream();
    setConnectionState("offline");
    showOfflineNotice();
  }, 15000);
}

function finishBootSequence() {
  ui.bootStatus.textContent = "Deployment interface ready";
  ui.bootProgress.style.width = "100%";
  window.setTimeout(() => ui.bootScreen.classList.add("is-complete"), 380);
}

function bindEvents() {
  ui.playButton.addEventListener("click", launchGame);
  ui.closeStream.addEventListener("click", closeStream);
  ui.streamFrame.addEventListener("load", () => {
    if (!ui.streamExperience.hidden && ui.streamFrame.src !== "about:blank") {
      window.clearTimeout(connection.streamLoadTimer);
      ui.streamLoading.hidden = true;
    }
  });

  window.addEventListener("online", probeStreamingBackend);
  window.addEventListener("offline", () => setConnectionState("offline"));
  window.addEventListener("resize", detectClientProfile, { passive: true });
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
  setConnectionState("checking");
  ui.bootProgress.style.width = "72%";
  probeStreamingBackend();
  window.setTimeout(finishBootSequence, 520);
}

document.addEventListener("DOMContentLoaded", initializeLauncher);
