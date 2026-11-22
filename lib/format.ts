export const money = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);

export const DIETARY_LABEL: Record<string, string> = {
  vegan: "Vegan",
  gf: "Gluten-free",
  nf: "Nut-free",
  lf: "Lactose-free",
};

export const ALLERGEN_LABEL: Record<string, string> = {
  tree_nuts: "Tree nuts",
  peanuts: "Peanuts",
  dairy: "Dairy",
  gluten: "Gluten",
  egg: "Egg",
  soy: "Soy",
  sesame: "Sesame",
  shellfish: "Shellfish",
  fish: "Fish",
};

/** Mirrors the database rounding in place_order, for display only. */
export const estimateTax = (subtotalCents: number, rate: number) => Math.round(subtotalCents * rate);

export function elapsed(fromIso: string, now = Date.now()) {
  const s = Math.max(0, Math.floor((now - new Date(fromIso).getTime()) / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}
