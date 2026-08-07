import { defineConfig } from "vite";
import elmTailwind from "elm-tailwind-classes/vite";
import tailwindcss from "@tailwindcss/vite";
import elm from "vite-plugin-elm";

export default defineConfig({
  // GitHub Pages serves this project under /design-playground/
  base: "/design-playground/",
  plugins: [elmTailwind(), tailwindcss(), elm()],
});
