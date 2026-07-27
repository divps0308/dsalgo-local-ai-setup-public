import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";
import { resolve } from "node:path";

const target = process.env.APP_TARGET === "workbench" ? "workbench" : "studio";
const root = resolve(import.meta.dirname, "apps", target);
const outDir = resolve(import.meta.dirname, "..", target === "studio" ? "agent-studio/static" : "developer-workbench/static");

export default defineConfig({
  root,
  plugins: [svelte()],
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
