import { createBrowserClient } from "@supabase/ssr";

/** Client for logged-in staff in the browser (kitchen screen, login). */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
