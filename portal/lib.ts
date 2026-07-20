import { createClient, type Session, type SupabaseClient, type User } from "@supabase/supabase-js";

declare const __SUPABASE_URL__: string;
declare const __SUPABASE_ANON_KEY__: string;

export const supabaseUrl = typeof __SUPABASE_URL__ === "string" ? __SUPABASE_URL__.trim() : "";
export const supabaseAnonKey = typeof __SUPABASE_ANON_KEY__ === "string" ? __SUPABASE_ANON_KEY__.trim() : "";
export const configured = /^https:\/\/.+\.supabase\.co$/i.test(supabaseUrl) && supabaseAnonKey.length > 30;
export const supabase: SupabaseClient | null = configured
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: { flowType: "pkce", persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;

export type WorkspaceRole = "admin" | "client" | "collaborator";
export interface Organisation { id: string; name: string; slug: string; industry?: string | null; active: boolean; }
export interface WorkspaceState {
  session: Session | null;
  user: User | null;
  profile: Record<string, unknown> | null;
  isAdmin: boolean;
  role: WorkspaceRole;
  organisations: Organisation[];
  activeOrganisation: Organisation | null;
  unreadNotifications: number;
}

export const state: WorkspaceState = {
  session: null,
  user: null,
  profile: null,
  isAdmin: false,
  role: "client",
  organisations: [],
  activeOrganisation: null,
  unreadNotifications: 0,
};

export const IDEA_STATUSES = [
  ["new_idea", "New idea"], ["discussing", "Discussing"], ["approved", "Approved"],
  ["ready_to_film", "Ready to film"], ["filmed", "Filmed"], ["editing", "Editing"],
  ["awaiting_approval", "Awaiting approval"], ["scheduled", "Scheduled"],
  ["published", "Published"], ["archived", "Archived"],
] as const;

export const CONTENT_FORMATS = ["reel", "tiktok", "photograph", "carousel", "story", "youtube_video", "testimonial", "promotional_graphic", "behind_the_scenes", "video", "other"] as const;
export const PLATFORMS = ["Instagram", "Facebook", "TikTok", "LinkedIn", "YouTube", "Website"] as const;

export function canManage(): boolean { return state.isAdmin || state.role === "admin" || state.role === "collaborator"; }
export function label(value: string): string { return value.replaceAll("_", " ").replace(/\b\w/g, x => x.toUpperCase()); }
export function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char] ?? char));
}
export function fmtDate(value: unknown, includeTime = false): string {
  if (!value) return "Not set";
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return "Not set";
  return new Intl.DateTimeFormat("en-GB", includeTime
    ? { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }
    : { day: "numeric", month: "short", year: "numeric" }).format(date);
}
export function initials(name: string): string { return name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join("") || "M"; }
export function toast(message: string, type: "ok" | "error" = "ok"): void {
  const region = document.querySelector<HTMLElement>("#toast-region");
  if (!region) return;
  const item = document.createElement("div");
  item.className = `toast ${type === "error" ? "error" : ""}`;
  item.textContent = message;
  region.append(item);
  window.setTimeout(() => item.remove(), 4500);
}
export function formValue(form: FormData, name: string): string { return String(form.get(name) ?? "").trim(); }
export function safePath(path: string): string {
  const allowed = ["overview","ideas","filming","calendar","content","performance","files","account","requests","clients","admin","analytics","users"];
  const segment = path.replace(/^\/portal\/?/, "").split("/")[0];
  return allowed.includes(segment) ? segment : "overview";
}
export function go(route: string): void {
  const path = route.startsWith("/portal") ? route : `/portal/${route.replace(/^\//, "")}`;
  history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}
export async function api(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
  if (!state.session) throw new Error("Your session has expired. Please sign in again.");
  const response = await fetch(path, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${state.session.access_token}` },
    body: JSON.stringify(body),
  });
  const result = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) throw new Error(String(result.error || "The request could not be completed."));
  return result;
}

export function requiredClient(): SupabaseClient {
  if (!supabase) throw new Error("Supabase is not configured.");
  return supabase;
}
