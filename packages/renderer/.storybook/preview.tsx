import React from "react";
import type { Preview } from "@storybook/react";
// Exactly the styling the production renderer uses: generated design
// tokens first, then the component CSS that consumes them. Browsing a
// story is therefore visually identical to the shipped UI.
import "../../../tokens/css/variables.css";
import "../src/app.css";
import "./storybook.css";

const preview: Preview = {
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
    (Story) => (
      <div className="sb-stage">
        <Story />
      </div>
    ),
  ],
};

export default preview;
