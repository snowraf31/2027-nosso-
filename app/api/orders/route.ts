import { NextResponse } from "next/server";
import { z } from "zod";
import { createPublicClient } from "@/lib/supabase/public";
import { businessCode, businessMessage, isIdempotencyKeyConflict } from "./errors";

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
    const code = businessCode(error);
    if (code) {
      // Só o código no log: a mensagem e o detalhe do Postgres trazem restaurant_id e a chave.
      if (isIdempotencyKeyConflict(error)) console.warn("place_order: chave de idempotencia repetida", error.code);
      return NextResponse.json({ error: businessMessage(error, code), code }, { status: 409 });
    }
    console.error("place_order failed", error);
    return NextResponse.json({ error: "We couldn't send your order. Please try again." }, { status: 500 });
  }

  const order = data as { id: string; number: number; public_token: string };
  return NextResponse.json(order, { status: 201 });
}
