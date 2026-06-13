import React from "react";
import MarkdownIt from "markdown-it";

/**
 * Renders the project's committed markdown docs inside Storybook so the
 * documentation site and the component workbench are one and the same.
 * The markdown files (docs/*.md, governance/*.md) remain the single
 * source of truth — there is no duplicated prose to drift.
 *
 * ```mermaid fences render client-side from the Mermaid CDN, exactly as
 * the previous static site did, so the build itself needs no network.
 */
const md = new MarkdownIt({ html: true, linkify: true });
const defaultFence = md.renderer.rules.fence!.bind(md.renderer.rules);
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  const t = tokens[idx];
  if (t.info.trim() === "mermaid") return `<div class="mermaid">${t.content}</div>`;
  return defaultFence(tokens, idx, options, env, self);
};

export function MarkdownDoc({ source }: { source: string }) {
  const ref = React.useRef<HTMLDivElement>(null);
  const html = React.useMemo(() => md.render(source), [source]);

  React.useEffect(() => {
    const el = ref.current;
    if (!el || el.querySelectorAll(".mermaid").length === 0) return;
    let cancelled = false;
    (async () => {
      try {
        const mod = await import(
          /* @vite-ignore */ "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs"
        );
        if (cancelled) return;
        const mermaid = mod.default;
        mermaid.initialize({ startOnLoad: false, theme: "neutral" });
        await mermaid.run({ nodes: el.querySelectorAll<HTMLElement>(".mermaid") });
      } catch {
        /* offline: leave the diagram source visible */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [html]);

  return <div className="sb-doc" ref={ref} dangerouslySetInnerHTML={{ __html: html }} />;
}
