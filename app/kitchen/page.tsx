import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import KitchenBoard from "./KitchenBoard";

export const dynamic = "force-dynamic";
export const metadata = { title: "Kitchen" };

export default async function KitchenPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=/kitchen");

  const { data: membership } = await supabase
    .from("staff")
    .select("restaurant_id, role, restaurant:restaurants(name)")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();

  const m = membership as unknown as { restaurant_id: string; role: string; restaurant: { name: string } | null } | null;

  if (!m) {
    return (
      <main className="center">
        <div className="card">
          <h1>No restaurant yet</h1>
          <p className="muted" style={{ margin: 0 }}>
            Your account ({user.email}) isn&apos;t linked to a restaurant. Ask the owner to add you as staff.
          </p>
        </div>
      </main>
    );
  }

  const { data: items } = await supabase
    .from("menu_items")
    .select("id, name, available")
    .eq("restaurant_id", m.restaurant_id)
    .order("position");

  return (
    <KitchenBoard
      restaurantId={m.restaurant_id}
      restaurantName={m.restaurant?.name ?? "Kitchen"}
      initialItems={(items ?? []) as { id: string; name: string; available: boolean }[]}
    />
  );
}
