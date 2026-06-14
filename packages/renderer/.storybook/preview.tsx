import React from "react";
import type { Preview } from "@storybook/react";
// Exactly the styling the production renderer uses: generated design
// tokens first, then the component CSS that consumes them. Browsing a
// story is therefore visually identical to the shipped UI.
import "../../../tokens/css/variables.css";
import "../src/app.css";
import "./storybook.css";
import { TOKEN_THEMES, themeVars } from "../src/stories/token-themes.js";

const preview: Preview = {
  // Toolbar control that re-themes EVERY story by patching design-token
  // custom properties — the global counterpart to the Token Playground.
  globalTypes: {
    tokenTheme: {
      description: "Apply a design-token theme across all stories",
      defaultValue: "base",
      toolbar: {
        title: "Tokens",
        icon: "paintbrush",
        items: TOKEN_THEMES.map((t) => ({ value: t.id, title: t.label })),
        dynamicTitle: true,
      },
    },
  },
  parameters: {
    controls: {
      matchers: { color: /(background|color)$/i, date: /Date$/i },
    },
    options: {
      storySort: {
        order: ["Foundations", "Components", "Screens"],
      },
    },
    backgrounds: {
      default: "app",
      values: [
        { name: "app", value: "var(--color-surface-background, #f8fafc)" },
        { name: "card", value: "var(--color-surface-card, #ffffff)" },
      ],
    },
  },
  decorators: [
    // Global token theme: wrap the story in an element that overrides the
    // chosen design-token vars, so they cascade into every component. Skipped
    // for stories that manage their own overrides (the Token Playground), and
    // a no-op under `base`/when globals are absent (e.g. portable-stories
    // tests), keeping existing stories and tests unaffected.
    (Story, context) => {
      if (context.parameters.tokenThemeable === false) return <Story />;
      const vars = themeVars(context.globals.tokenTheme as string | undefined);
      if (Object.keys(vars).length === 0) return <Story />;
      return <div style={vars as React.CSSProperties}><Story /></div>;
    },
    (Story) => (
      <div className="sb-stage">
        <Story />
      </div>
    ),
  ],
};

export default preview;
