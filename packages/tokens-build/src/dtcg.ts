/**
 * Minimal DTCG (W3C Design Tokens Community Group draft) reader:
 * flattens a token tree into a list of typed tokens with dot paths.
 */

export interface FlatToken {
  /** Dot-separated path, e.g. "color.brand.primary" */
  path: string;
  type: string;
  value: unknown;
  description?: string;
}

interface DtcgNode {
  [key: string]: unknown;
  $type?: string;
  $value?: unknown;
  $description?: string;
}

export function flattenTokens(
  node: DtcgNode,
  prefix: string[] = [],
  inheritedType?: string,
): FlatToken[] {
  const type = (node.$type as string | undefined) ?? inheritedType;
  if (node.$value !== undefined) {
    if (!type) throw new Error(`Token ${prefix.join(".")} has no $type (own or inherited)`);
    return [
      {
        path: prefix.join("."),
        type,
        value: node.$value,
        description: node.$description,
      },
    ];
  }
  const out: FlatToken[] = [];
  for (const [key, child] of Object.entries(node)) {
    if (key.startsWith("$")) continue;
    out.push(...flattenTokens(child as DtcgNode, [...prefix, key], type));
  }
  return out;
}

/** "color.brand.primary-hover" -> "--color-brand-primary-hover" */
export function cssVarName(path: string): string {
  return `--${path.replaceAll(".", "-")}`;
}

export function cssValue(token: FlatToken): string {
  switch (token.type) {
    case "fontFamily":
      return (token.value as string[])
        .map((f) => (f.includes(" ") ? `"${f}"` : f))
        .join(", ");
    case "cubicBezier":
      return `cubic-bezier(${(token.value as number[]).join(", ")})`;
    case "shadow": {
      const s = token.value as {
        offsetX: string;
        offsetY: string;
        blur: string;
        spread: string;
        color: string;
      };
      return `${s.offsetX} ${s.offsetY} ${s.blur} ${s.spread} ${s.color}`;
    }
    default:
      return String(token.value);
  }
}
