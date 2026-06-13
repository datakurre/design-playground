/**
 * Demo application. Loads the committed scenario ASTs (and example ASTs,
 * including a deliberately invalid one) via Vite glob import, and renders
 * the selected screen through the validating ScreenRenderer.
 */
import React from "react";
import type { Screen } from "@design-playground/ui-ir";
import { ScreenRenderer } from "./ScreenRenderer.js";

// Eagerly import every scenario AST array and every example AST.
const scenarioModules = import.meta.glob("../../../scenarios/*/ast.json", { eager: true }) as Record<
  string,
  { default: Screen[] }
>;
const exampleModules = import.meta.glob("../../../ui-ir/examples/*.json", { eager: true }) as Record<
  string,
  { default: unknown }
>;

interface Item {
  key: string;
  label: string;
  group: string;
  ast: unknown;
}

function buildItems(): Item[] {
  const items: Item[] = [];
  for (const [path, mod] of Object.entries(scenarioModules)) {
    const scenario = path.split("/").slice(-2)[0];
    mod.default.forEach((screen, i) => {
      items.push({
        key: `${scenario}:${i}`,
        label: `${scenario} — ${screen.step ?? `step ${i + 1}`}`,
        group: "Generated scenarios",
        ast: screen,
      });
    });
  }
  for (const [path, mod] of Object.entries(exampleModules)) {
    const name = path.split("/").pop()!.replace(".json", "");
    items.push({ key: `ex:${name}`, label: name, group: "Examples", ast: mod.default });
  }
  return items;
}

export function App() {
  const items = React.useMemo(buildItems, []);
  const [selected, setSelected] = React.useState(items[0]?.key);
  const current = items.find((i) => i.key === selected) ?? items[0];
  const groups = Array.from(new Set(items.map((i) => i.group)));

  return (
    <div className="dp-app">
      <aside className="dp-sidebar">
        <h1 className="dp-brand">Design Playground</h1>
        <p className="dp-tagline">Agent-generated UI, validated against the design system before render.</p>
        {groups.map((g) => (
          <div key={g} className="dp-group">
            <h2>{g}</h2>
            <ul>
              {items
                .filter((i) => i.group === g)
                .map((i) => (
                  <li key={i.key}>
                    <button
                      className="dp-pick"
                      data-active={i.key === selected}
                      onClick={() => setSelected(i.key)}
                    >
                      {i.label}
                    </button>
                  </li>
                ))}
            </ul>
          </div>
        ))}
      </aside>
      <div className="dp-stage" data-testid="stage">
        {current && <ScreenRenderer ast={current.ast} />}
      </div>
    </div>
  );
}
