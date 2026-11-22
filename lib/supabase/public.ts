import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * Anonymous client for guest traffic, used on the server.
 * It can only call the guest functions (get_guest_menu, place_order,
 * get_guest_order); Row Level Security blocks every table.
 * No secret key is needed, so nothing powerful lives on the server.
 */
export function createPublicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new Error("Missing Supabase environment variables. See .env.example.");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
