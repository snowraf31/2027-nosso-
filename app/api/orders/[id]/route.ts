import { NextResponse } from "next/server";
import { createPublicClient } from "@/lib/supabase/public";
import type { GuestOrder } from "@/lib/types";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * GET /api/orders/:id?k=<public_token> — the guest's status screen polls this.
 * The public token is only known to the phone that placed the order.
 */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const k = new URL(req.url).searchParams.get("k") ?? "";
  if (!UUID.test(id) || !/^[0-9a-f]{32}$/.test(k)) {
    return NextResponse.json({ error: "Order not found." }, { status: 404 });
  }

  const { data, error } = await createPublicClient().rpc("get_guest_order", { p_order_id: id, p_token: k });
  if (error) console.error("get_guest_order failed", error);
  if (!data) return NextResponse.json({ error: "Order not found." }, { status: 404 });

  return NextResponse.json(data as GuestOrder, { headers: { "Cache-Control": "no-store" } });
}
