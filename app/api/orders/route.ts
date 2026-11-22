import { NextResponse } from "next/server";
import { z } from "zod";
import { createPublicClient } from "@/lib/supabase/public";

/**
 * POST /api/orders — the guest's phone sends ids and quantities only.
 * Prices, tax and availability are checked inside the place_order database function.
 */
const Body = z.object({
  table_token: z.string().min(8).max(64),
  idempotency_key: z.string().uuid(),
  payment_method: z.enum(["counter", "online"]).default("counter"),
  tip_cents: z.number().int().min(0).default(0),
  items: z
    .array(
      z.object({
        menu_item_id: z.string().uuid(),
        quantity: z.number().int().min(1).max(20),
        option_ids: z.array(z.string().uuid()).max(20).default([]),
        note: z.string().max(200).optional(),
      })
    )
    .min(1)
    .max(40),
});

const MESSAGES: Record<string, string> = {
  TABLE_NOT_FOUND: "This table code isn't active. Please ask a server for help.",
  EMPTY_ORDER: "Your order is empty.",
  TOO_MANY_ITEMS: "That's a big order! Please split it in two or ask a server.",
  BAD_QUANTITY: "Please check the quantities in your order.",
  ITEM_NOT_FOUND: "One of the items is no longer on the menu. Please refresh.",
  ITEM_SOLD_OUT: "is sold out. Please remove it and try again.",
  BAD_MODIFIER: "One of the options you picked is no longer available. Please refresh.",
  MODIFIER_RULE: "needs a choice. Please edit that item.",
  BAD_TIP: "Please check the tip amount.",
};

export async function POST(req: Request) {
  let json: unknown;
  try {
    json = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  const parsed = Body.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid order data." }, { status: 400 });
  }
  const body = parsed.data;

  // Phase 1: pay at the counter only. Online payment arrives with Stripe in phase 3.
  if (body.payment_method === "online") {
    return NextResponse.json({ error: "Online payment isn't available yet. Please pay at the counter." }, { status: 400 });
  }

  const db = createPublicClient();
  const { data, error } = await db.rpc("place_order", {
    p_table_token: body.table_token,
    p_items: body.items,
    p_payment_method: body.payment_method,
    p_tip_cents: body.tip_cents,
    p_idempotency_key: body.idempotency_key,
  });

  if (error) {
    const [code, detail] = (error.message || "").split(":");
    const msg = MESSAGES[code];
    if (msg) {
      const text = detail ? `${detail.trim()} ${msg}` : msg;
      return NextResponse.json({ error: text, code }, { status: 409 });
    }
    console.error("place_order failed", error);
    return NextResponse.json({ error: "We couldn't send your order. Please try again." }, { status: 500 });
  }

  const order = data as { id: string; number: number; public_token: string };
  return NextResponse.json(order, { status: 201 });
}
