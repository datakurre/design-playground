import { describe, it, afterEach } from "vitest";
import { render, cleanup } from "@testing-library/react";
import { composeStories, setProjectAnnotations } from "@storybook/react";
import preview from "../../.storybook/preview";
import * as ButtonStories from "./Button.stories";
import * as FieldStories from "./Field.stories";
import * as DialogStories from "./Dialog.stories";

// Apply the global decorators/parameters (token CSS, stage) so a composed
// story renders exactly as it does in Storybook.
setProjectAnnotations(preview as Parameters<typeof setProjectAnnotations>[0]);

afterEach(cleanup);

const suites = {
  Button: composeStories(ButtonStories),
  Field: composeStories(FieldStories),
  Dialog: composeStories(DialogStories),
};

for (const [group, stories] of Object.entries(suites)) {
  describe(group, () => {
    for (const [name, Story] of Object.entries(stories)) {
      it(`renders and passes the play test: ${name}`, async () => {
        const { container } = render(<Story />);
        await Story.play?.({ canvasElement: container });
      });
    }
  });
}
