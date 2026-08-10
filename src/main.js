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
