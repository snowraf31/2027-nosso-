/**
 * Mapeia o erro do place_order para a resposta da rota POST /api/orders.
 * Fica fora do route.ts para poder ser testado sem subir o Next.
 */

export type PlaceOrderError = { code?: string | null; message?: string | null };

export const MESSAGES: Record<string, string> = {
  TABLE_NOT_FOUND: "This table code isn't active. Please ask a server for help.",
  EMPTY_ORDER: "Your order is empty.",
  TOO_MANY_ITEMS: "That's a big order! Please split it in two or ask a server.",
  BAD_QUANTITY: "Please check the quantities in your order.",
  ITEM_NOT_FOUND: "One of the items is no longer on the menu. Please refresh.",
  ITEM_SOLD_OUT: "is sold out. Please remove it and try again.",
  BAD_MODIFIER: "One of the options you picked is no longer available. Please refresh.",
  MODIFIER_RULE: "needs a choice. Please edit that item.",
  BAD_TIP: "Please check the tip amount.",
  // Chave de idempotência já usada por outra mesa do mesmo restaurante (migration 0010).
  ORDER_KEY_CONFLICT: "We couldn't send this order. Please reload the page and try again.",
};

const IDEMPOTENCY_CONSTRAINT = "orders_restaurant_id_idempotency_key_key";

/**
 * unique_violation (23505) na constraint de idempotência por restaurante: a mesma chave
 * chegou de outra mesa. Outras violações de unicidade (ex.: número do pedido) não entram aqui.
 */
export function isIdempotencyKeyConflict(error: PlaceOrderError): boolean {
  return error.code === "23505" && (error.message ?? "").includes(IDEMPOTENCY_CONSTRAINT);
}

/** Retorna o código de negócio (chave de MESSAGES) do erro, ou null se não for um erro conhecido. */
export function businessCode(error: PlaceOrderError): string | null {
  if (isIdempotencyKeyConflict(error)) return "ORDER_KEY_CONFLICT";
  const [code] = (error.message || "").split(":");
  return Object.hasOwn(MESSAGES, code) ? code : null;
}

/** Texto para o cliente (o detalhe, como o nome do item, vem antes da mensagem). */
export function businessMessage(error: PlaceOrderError, code: string): string {
  if (code === "ORDER_KEY_CONFLICT") return MESSAGES[code];
  const detail = (error.message || "").split(":")[1];
  return detail ? `${detail.trim()} ${MESSAGES[code]}` : MESSAGES[code];
}
