import "./style.css";
import { Elm } from "./Main.elm";
import Ajv2020 from "ajv/dist/2020.js";
import tokensSchema from "../schemas/tokens.schema.json";
import componentsSchema from "../schemas/components.schema.json";
import screensSchema from "../schemas/screens.schema.json";
import contractsSchema from "../schemas/contracts.schema.json";

const ajv = new Ajv2020();
ajv.addSchema(tokensSchema, "tokens");
ajv.addSchema(componentsSchema, "components");
ajv.addSchema(screensSchema, "screens");
ajv.addSchema(contractsSchema, "contracts");

// PKCE generation helpers
//
// `length` is the number of hex characters wanted, so half that many bytes.
// This used to allocate a Uint32Array and keep only the low byte of each word,
// which produced the same entropy but read like a bug.
function generateRandomString(length) {
  var array = new Uint8Array(length / 2);
  window.crypto.getRandomValues(array);
  return Array.from(array, function (byte) {
    return ("0" + byte.toString(16)).slice(-2);
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

// Where this deployment's OAuth application lives.
//
// The client id and redirect URI used to be compiled into src/Auth.elm, with
// the redirect pointing at one particular GitHub Pages origin. Sign-in
// therefore worked on exactly one deployment and could not work locally at all.
// See .env.example.
function authConfig() {
  var redirectUri =
    import.meta.env.VITE_GITLAB_REDIRECT_URI ||
    window.location.origin + import.meta.env.BASE_URL;

  return {
    clientId: import.meta.env.VITE_GITLAB_CLIENT_ID || "",
    // A trailing slash matters: GitLab compares the redirect URI literally
    // against what the application registered.
    redirectUri: redirectUri.replace(/\/$/, ""),
    // Narrower than the `api` scope this used to ask for, which granted full
    // read/write over every project the user can reach. The app reads
    // repositories and writes commits, branches and merge requests.
    scope: import.meta.env.VITE_GITLAB_SCOPE || "read_api write_repository",
    state: oauthState(),
  };
}

// The `state` parameter, per sign-in attempt.
//
// It was the constant string "design-playground" and Elm never read it back,
// which is a CSRF defence in shape only. It lives in sessionStorage because the
// callback lands in the same tab that started the flow, and it has to survive
// the round trip to GitLab.
function oauthState() {
  var state = sessionStorage.getItem("oauth_state");
  if (!state) {
    state = generateRandomString(32);
    sessionStorage.setItem("oauth_state", state);
  }
  return state;
}

// The PKCE verifier, per sign-in attempt.
//
// Generated once per session and never cleared, one verifier was reused for
// every login the tab ever performed, and survived signing out. It is rotated
// whenever there is no callback in flight — a callback in flight needs the
// verifier that produced the challenge GitLab is answering.
function pkceVerifier() {
  var callbackInFlight = window.location.search.indexOf("code=") !== -1;
  var verifier = sessionStorage.getItem("pkce_verifier");

  if (!verifier || !callbackInFlight) {
    verifier = generateRandomString(64);
    sessionStorage.setItem("pkce_verifier", verifier);
  }
  return verifier;
}

async function initApp() {
  var verifier = pkceVerifier();
  var challenge = await generateCodeChallenge(verifier);

  var app = Elm.Main.init({
    node: document.getElementById("app"),
    flags: {
      token: localStorage.getItem("gitlab_token"),
      refreshToken: localStorage.getItem("gitlab_refresh_token"),
      pkceChallenge: challenge,
      pkceVerifier: verifier,
      authConfig: authConfig(),
    },
  });

  // Listen for session updates from Elm
  if (app.ports && app.ports.cacheSession) {
    app.ports.cacheSession.subscribe(function (session) {
      localStorage.setItem("gitlab_token", session.accessToken);
      if (session.refreshToken) {
        localStorage.setItem("gitlab_refresh_token", session.refreshToken);
      } else {
        localStorage.removeItem("gitlab_refresh_token");
      }
    });
  }

  if (app.ports && app.ports.clearToken) {
    app.ports.clearToken.subscribe(function () {
      localStorage.removeItem("gitlab_token");
      localStorage.removeItem("gitlab_refresh_token");
      // A stale verifier outliving the session it belonged to is the bug this
      // pairs with; signing out is exactly when to drop it.
      sessionStorage.removeItem("pkce_verifier");
      sessionStorage.removeItem("oauth_state");
    });
  }

  if (app.ports && app.ports.validateSchema) {
    app.ports.validateSchema.subscribe(function (payload) {
      var validate = ajv.getSchema(payload.schema);
      if (!validate) {
        app.ports.schemaValidationResult.send({
          valid: false,
          errors: ["Unknown schema: " + payload.schema],
          context: payload.context
        });
        return;
      }
      var valid = validate(payload.data);
      var errors = [];
      if (!valid) {
        errors = validate.errors.map(function(err) {
          return (err.instancePath || "root") + " " + err.message;
        });
      }
      app.ports.schemaValidationResult.send({
        valid: valid ? true : false,
        errors: errors,
        context: payload.context
      });
    });
  }
}

initApp();
