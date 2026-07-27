export type ThemeMode = "system" | "light" | "dark";
export type OperatingMode = "online" | "restricted-online" | "strict-offline";
export type Tone = "neutral" | "info" | "success" | "warning" | "danger";

export interface NavItem {
  id: string;
  label: string;
  description: string;
  icon: typeof import("lucide-svelte").Circle;
  badge?: string | number;
}

export interface HelpTopic {
  id: string;
  title: string;
  section: string;
  body: string;
}

export interface ToastMessage {
  id: number;
  title: string;
  message?: string;
  tone: Tone;
}
