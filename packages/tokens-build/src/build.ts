/**
 * Generates tokens/css/variables.css from tokens/design-tokens.json.
 * The CSS custom properties are the ONLY styling channel the renderer
 * uses, so every rendered UI stays consistent with the token source.
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { flattenTokens, cssVarName, cssValue } from "./dtcg.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const source = JSON.parse(readFileSync(join(root, "tokens/design-tokens.json"), "utf8"));
delete source.$schema;

const tokens = flattenTokens(source);

const lines = tokens.map((t) => {
  const comment = t.description ? ` /* ${t.description} */` : "";
  return `  ${cssVarName(t.path)}: ${cssValue(t)};${comment}`;
});

const css = `/* GENERATED FILE - do not edit.
 * Source: tokens/design-tokens.json
 * Regenerate with: pnpm build:tokens
 */
:root {
${lines.join("\n")}
}
`;

mkdirSync(join(root, "tokens/css"), { recursive: true });
writeFileSync(join(root, "tokens/css/variables.css"), css);
console.log(`tokens/css/variables.css written (${tokens.length} tokens)`);
