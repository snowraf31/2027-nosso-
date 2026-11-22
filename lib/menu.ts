import "server-only";
import { cache } from "react";
import { createPublicClient } from "@/lib/supabase/public";
import type { GuestMenu } from "@/lib/types";

/**
 * Loads the full menu for a table token through the get_guest_menu database function.
 * Returns null if the token or restaurant slug is wrong.
 * Wrapped in cache() so the page and its metadata share one database round trip.
 */
export const loadGuestMenu = cache(async function loadGuestMenu(slug: string, token: string): Promise<GuestMenu | null> {
  const { data, error } = await createPublicClient().rpc("get_guest_menu", { p_slug: slug, p_token: token });
  if (error) {
    console.error("get_guest_menu failed", error);
    return null;
  }
  if (!data) return null;
  const menu = data as GuestMenu;
  return { ...menu, restaurant: { ...menu.restaurant, tax_rate: Number(menu.restaurant.tax_rate) } };
});
