import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";
import { resolve } from "node:path";

const target = process.env.APP_TARGET === "workbench" ? "workbench" : "studio";
const root = resolve(import.meta.dirname, "apps", target);
const outDir = resolve(import.meta.dirname, "..", target === "studio" ? "agent-studio/static" : "developer-workbench/static");

export default defineConfig({
  root,
  plugins: [svelte({
    // Dialog semantics are provided by the overlay container around these
    // forms; suppress the compiler's legacy form-role diagnostic.
    onwarn: (warning, handler) => {
      if (warning.code === "a11y_no_noninteractive_element_to_interactive_role") return;
      handler(warning);
    }
  })],
  build: {
    outDir,
    emptyOutDir: true,
    sourcemap: false,
    assetsDir: "assets",
    rollupOptions: {
      output: {
        entryFileNames: "assets/app.js",
        chunkFileNames: "assets/[name].js",
        assetFileNames: (asset) => asset.names?.some((name) => name.endsWith(".css")) ? "assets/app.css" : "assets/[name][extname]"
      }
    }
  }
});
