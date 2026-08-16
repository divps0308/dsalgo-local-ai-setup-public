import type { ThemeMode } from "./types";

export const THEME_KEY = "dsalgo-local-ai-theme";

export function initialTheme(): ThemeMode {
  const cookie = document.cookie.split("; ").find((item) => item.startsWith(`${THEME_KEY}=`))?.split("=")[1];
  const stored = cookie || localStorage.getItem(THEME_KEY);
  return ["light", "dark", "system", "art", "material", "industrial"].includes(stored ?? "") ? stored as ThemeMode : "system";
}

export function resolvedTheme(mode: ThemeMode): "light" | "dark" {
  return mode === "system"
    ? matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
    : (mode === "dark" || mode === "art" || mode === "industrial" ? "dark" : "light");
}

export function applyTheme(mode: ThemeMode): void {
  document.documentElement.dataset.theme = resolvedTheme(mode);
  document.documentElement.dataset.themeMode = mode;
  document.documentElement.style.colorScheme = resolvedTheme(mode);
  localStorage.setItem(THEME_KEY, mode);
  document.cookie = `${THEME_KEY}=${mode}; Path=/; SameSite=Lax`;
}
