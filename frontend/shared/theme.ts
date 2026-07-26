import type { ThemeMode } from "./types";

export const THEME_KEY = "alienware-local-ai-theme";

export function initialTheme(): ThemeMode {
  const stored = localStorage.getItem(THEME_KEY);
  return stored === "light" || stored === "dark" || stored === "system" ? stored : "system";
}

export function resolvedTheme(mode: ThemeMode): "light" | "dark" {
  return mode === "system"
    ? matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
    : mode;
}

export function applyTheme(mode: ThemeMode): void {
  document.documentElement.dataset.theme = resolvedTheme(mode);
  document.documentElement.dataset.themeMode = mode;
  document.documentElement.style.colorScheme = resolvedTheme(mode);
  localStorage.setItem(THEME_KEY, mode);
}
