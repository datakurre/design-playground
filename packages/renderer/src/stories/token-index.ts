/**
 * Data layer for the Design Token playground. Everything here is pure and
 * derives from the SAME sources the build pipeline uses, so the playground
 * shows the real token graph rather than a hand-maintained copy:
 *
 *  - the DTCG source `tokens/design-tokens.json` (phase 1), flattened with
 *    the very `flattenTokens`/`cssVarName`/`cssValue` the CSS build uses;
 *  - the component metadata `components/*.json` (phase 2), reverse-indexed
 *    so we can show which variants bind a given token.
 */
import design from "../../../../tokens/design-tokens.json";
import {
  flattenTokens,
  cssVarName,
  cssValue,
  type FlatToken,
} from "@design-playground/tokens-build";

export { cssVarName, cssValue };
export type { FlatToken };

export const ALL_TOKENS: FlatToken[] = flattenTokens(
  design as unknown as Parameters<typeof flattenTokens>[0],
);

export const CATEGORY_ORDER = [
  "color",
  "font",
  "space",
  "radius",
  "shadow",
  "motion",
  "breakpoint",
];

/** Group flattened tokens by their first path segment (the DTCG category). */
export function groupByCategory(tokens: FlatToken[] = ALL_TOKENS): Record<string, FlatToken[]> {
  const out: Record<string, FlatToken[]> = {};
  for (const t of tokens) {
    const cat = t.path.split(".")[0];
    (out[cat] ??= []).push(t);
  }
  return out;
}
export const TOKEN_GROUPS = groupByCategory();

export function tokenByPath(path: string): FlatToken | undefined {
  return ALL_TOKENS.find((t) => t.path === path);
}

/**
 * The semantic alias layer. This MIRRORS the `:root` alias block in
 * `packages/renderer/src/app.css` and `packages/ui-ir/src/render-html.ts`
 * (screenBaseCss). Keep all three in sync. Maps semantic name -> the
 * generated token var it resolves to.
 */
export const ALIAS_MAP: Record<string, string> = {
  "--spacing-xs": "--space-1",
  "--spacing-sm": "--space-2",
  "--spacing-md": "--space-4",
  "--spacing-lg": "--space-6",
  "--spacing-xl": "--space-8",
  "--color-surface-default": "--color-surface-card",
  "--color-surface-muted": "--color-surface-background",
  "--typography-font-family-sans": "--font-family-base",
  "--typography-font-size-sm": "--font-size-sm",
  "--typography-font-size-lg": "--font-size-lg",
  "--typography-font-size-2xl": "--font-size-2xl",
  "--shadow-lg": "--shadow-overlay",
};

/** Semantic aliases that resolve to the given generated var name. */
export function aliasesFor(varName: string): string[] {
  return Object.entries(ALIAS_MAP)
    .filter(([, target]) => target === varName)
    .map(([alias]) => alias);
}

export interface Binding {
  component: string;
  variant: string;
}

interface ComponentDoc {
  id: string;
  variants?: Array<{ name: string; tokens?: string[] }>;
}
const componentModules = import.meta.glob("../../../../components/*.json", {
  eager: true,
}) as Record<string, { default: ComponentDoc }>;

/** Reverse index: token path -> the component variants that bind it. */
export function buildTokenIndex(): Map<string, Binding[]> {
  const map = new Map<string, Binding[]>();
  for (const mod of Object.values(componentModules)) {
    const doc = mod.default;
    for (const variant of doc.variants ?? []) {
      for (const path of variant.tokens ?? []) {
        const arr = map.get(path) ?? [];
        arr.push({ component: doc.id, variant: variant.name });
        map.set(path, arr);
      }
    }
  }
  return map;
}
export const TOKEN_INDEX = buildTokenIndex();

export function bindingsFor(path: string): Binding[] {
  return TOKEN_INDEX.get(path) ?? [];
}

/** A copy-pasteable DTCG leaf for the edited token (the round-trip hint). */
export function dtcgExport(token: FlatToken, editedValue: string): string {
  const primitive =
    token.type === "color" ||
    token.type === "dimension" ||
    token.type === "duration";
  const value = primitive ? editedValue : cssValue({ ...token, value: token.value });
  const leaf =
    primitive
      ? { $type: token.type, $value: editedValue }
      : {
          $type: token.type,
          $value: token.value,
          "// edited (resolved CSS)": value,
        };
  return JSON.stringify({ [token.path]: leaf }, null, 2);
}
