import "./style.css";
import { Elm } from "./Main.elm";

// PKCE generation helpers
function generateRandomString(length) {
  var array = new Uint32Array(length / 2);
  window.crypto.getRandomValues(array);
  return Array.from(array, function (dec) {
    return ("0" + dec.toString(16)).substr(-2);
  }).join("");
}

async function generateCodeChallenge(codeVerifier) {
  var encoder = new TextEncoder();
  var data = encoder.encode(codeVerifier);
  var digest = await window.crypto.subtle.digest("SHA-256", data);
  return btoa(String.fromCharCode.apply(null, new Uint8Array(digest)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function initApp() {
  var storedToken = localStorage.getItem("gitlab_token");

  // Retrieve or generate the verifier
  var verifier = sessionStorage.getItem("pkce_verifier");
  if (!verifier) {
    verifier = generateRandomString(64);
    sessionStorage.setItem("pkce_verifier", verifier);
  }

  var challenge = await generateCodeChallenge(verifier);

  var app = Elm.Main.init({
    node: document.getElementById("app"),
    flags: {
      token: storedToken,
      pkceChallenge: challenge,
      pkceVerifier: verifier,
    },
  });

  // Listen for token updates from Elm
  if (app.ports && app.ports.cacheToken) {
    app.ports.cacheToken.subscribe(function (token) {
      localStorage.setItem("gitlab_token", token);
    });
  }

  if (app.ports && app.ports.clearToken) {
    app.ports.clearToken.subscribe(function () {
      localStorage.removeItem("gitlab_token");
    });
  }
}

initApp();
