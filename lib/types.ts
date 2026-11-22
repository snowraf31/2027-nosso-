export type DietaryTag = "vegan" | "gf" | "nf";
export type Mood = "coffee" | "light" | "hearty" | "spicy" | "sweet";
/** Visual identity of the guest menu, one per restaurant */
export type BrandStyle = "harbor" | "diner" | "glace";

export interface ModifierOption {
  id: string;
  name: string;
  price_cents: number;
  available: boolean;
  position: number;
}

export interface ModifierGroup {
  id: string;
  name: string;
  min_select: number;
  max_select: number;
  options: ModifierOption[];
}

export interface MenuItem {
  id: string;
  category_id: string | null;
  name: string;
  description: string | null;
  price_cents: number;
  photo_url: string | null;
  dietary_tags: string[];
  allergens: string[];
  available: boolean;
  position: number;
  /** Short stamp like "House favorite" */
  badge: string | null;
  /** One line from the counter, shown in handwriting */
  story: string | null;
  moods: string[];
  /** Item ids that go well with this one */
  pairs_with: string[];
  groups: ModifierGroup[];
}

export interface MenuCategory {
  id: string;
  name: string;
  position: number;
  note: string | null;
  icon: string | null;
}

export interface GuestMenu {
  restaurant: { name: string; slug: string; tax_rate: number; tagline: string | null; brand_style?: BrandStyle | null; locale?: string | null; currency?: string | null };
  table: { label: string };
  token: string;
  categories: MenuCategory[];
  items: MenuItem[];
}

export type OrderStatus = "new" | "preparing" | "ready" | "served" | "cancelled";

export interface OrderLine {
  id: string;
  name_snapshot: string;
  unit_price_cents: number;
  quantity: number;
  modifiers: { name: string; price_cents: number }[];
  note: string | null;
}

export interface KitchenOrder {
  id: string;
  number: number;
  status: OrderStatus;
  payment_method: "online" | "counter";
  payment_status: "unpaid" | "paid" | "refunded";
  created_at: string;
  table: { label: string } | null;
  items: OrderLine[];
}

export interface GuestOrder {
  id: string;
  number: number;
  status: OrderStatus;
  payment_method: "online" | "counter";
  subtotal_cents: number;
  tax_cents: number;
  tip_cents: number;
  total_cents: number;
  created_at: string;
  table_label: string | null;
  restaurant_name: string;
  brand_style?: BrandStyle | null;
  locale?: string | null;
  currency?: string | null;
  items: OrderLine[];
}
