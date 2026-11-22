"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/browser";
import type { KitchenOrder, OrderStatus } from "@/lib/types";
import { elapsed } from "@/lib/format";

type Item = { id: string; name: string; available: boolean };

const COLUMNS: { key: OrderStatus; label: string; action: string; next: OrderStatus }[] = [
  { key: "new", label: "New", action: "Start", next: "preparing" },
  { key: "preparing", label: "Preparing", action: "Mark ready", next: "ready" },
  { key: "ready", label: "Ready to run", action: "Served", next: "served" },
];

const LATE_MS = 10 * 60 * 1000;

const ORDER_FIELDS = `id, number, status, payment_method, payment_status, created_at,
  table:tables(label),
  items:order_items(id, name_snapshot, unit_price_cents, quantity, modifiers, note)`;

export default function KitchenBoard({
  restaurantId,
  restaurantName,
  initialItems,
}: {
  restaurantId: string;
  restaurantName: string;
  initialItems: Item[];
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [orders, setOrders] = useState<KitchenOrder[]>([]);
  const [items, setItems] = useState<Item[]>(initialItems);
  const [now, setNow] = useState(() => Date.now());
  const [conn, setConn] = useState<"connecting" | "live" | "offline">("connecting");
  const [error, setError] = useState<string | null>(null);
  const [soundOn, setSoundOn] = useState(false);
  const audio = useRef<AudioContext | null>(null);
  const seen = useRef<Set<string>>(new Set());
  const firstLoad = useRef(true);

  const chime = useCallback(() => {
    const ctx = audio.current;
    if (!ctx) return;
    [0, 0.18].forEach((t, i) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.frequency.value = i ? 1175 : 880;
      g.gain.setValueAtTime(0.0001, ctx.currentTime + t);
      g.gain.exponentialRampToValueAtTime(0.3, ctx.currentTime + t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + t + 0.35);
      o.connect(g).connect(ctx.destination);
      o.start(ctx.currentTime + t);
      o.stop(ctx.currentTime + t + 0.4);
    });
  }, []);

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from("orders")
      .select(ORDER_FIELDS)
      .eq("restaurant_id", restaurantId)
      .in("status", ["new", "preparing", "ready"])
      .order("created_at");
    if (error) {
      setError("Couldn't load orders. Retrying…");
      return;
    }
    setError(null);
    const list = data as unknown as KitchenOrder[];
    const fresh = list.filter((o) => o.status === "new" && !seen.current.has(o.id));
    list.forEach((o) => seen.current.add(o.id));
    if (!firstLoad.current && fresh.length) chime();
    firstLoad.current = false;
    setOrders(list);
  }, [supabase, restaurantId, chime]);

  useEffect(() => {
    load();

    const channel = supabase
      .channel(`kitchen-${restaurantId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "orders", filter: `restaurant_id=eq.${restaurantId}` },
        () => load()
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "menu_items", filter: `restaurant_id=eq.${restaurantId}` },
        (payload) => {
          const row = payload.new as Item;
          setItems((prev) => prev.map((i) => (i.id === row.id ? { ...i, available: row.available } : i)));
        }
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") {
          setConn("live");
          load(); // catch anything missed while reconnecting
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          setConn("offline");
        }
      });

    // Safety net in case the realtime connection drops silently
    const poll = setInterval(load, 30000);
    const clock = setInterval(() => setNow(Date.now()), 1000);
    return () => {
      supabase.removeChannel(channel);
      clearInterval(poll);
      clearInterval(clock);
    };
  }, [supabase, restaurantId, load]);

  async function advance(order: KitchenOrder) {
    const col = COLUMNS.find((c) => c.key === order.status);
    if (!col) return;
    // Optimistic: move the ticket right away, undo if the database refuses
    setOrders((prev) =>
      col.next === "served" ? prev.filter((o) => o.id !== order.id) : prev.map((o) => (o.id === order.id ? { ...o, status: col.next } : o))
    );
    const { error } = await supabase.from("orders").update({ status: col.next }).eq("id", order.id);
    if (error) {
      setError(`Couldn't update order #${order.number}. Try again.`);
      load();
    }
  }

  async function setAvailable(item: Item, available: boolean) {
    setItems((prev) => prev.map((i) => (i.id === item.id ? { ...i, available } : i)));
    const { error } = await supabase.from("menu_items").update({ available }).eq("id", item.id);
    if (error) {
      setError(`Couldn't change ${item.name}. Try again.`);
      setItems((prev) => prev.map((i) => (i.id === item.id ? { ...i, available: !available } : i)));
    }
  }

  function enableSound() {
    const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    audio.current = new Ctx();
    setSoundOn(true);
    chime();
  }

  async function signOut() {
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  }

  const open = orders.length;
  const avgMs = open ? orders.reduce((a, o) => a + (now - new Date(o.created_at).getTime()), 0) / open : 0;

  return (
    <main className="kds">
      <header className="khead">
        <h1>{restaurantName}<small>Kitchen</small></h1>
        <span className={`live ${conn === "live" ? "on" : conn === "offline" ? "off" : ""}`}>
          {conn === "live" ? "Live" : conn === "offline" ? "Reconnecting…" : "Connecting…"}
        </span>
        <div className="kstats">
          <span>Open <b>{open}</b></span>
          <span>Avg wait <b>{elapsed(new Date(now - avgMs).toISOString(), now)}</b></span>
        </div>
        <span className="kspacer" />
        {!soundOn && <button className="kbtn" onClick={enableSound}>Turn on sound</button>}
        <button className="kbtn" onClick={signOut}>Sign out</button>
        <span className="clock">{new Date(now).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}</span>
      </header>

      <div style={{ display: "grid", gap: 12, alignContent: "start" }}>
        {error && <div className="kerr" role="alert">{error}</div>}
        <div className="kgrid">
          {COLUMNS.map((col) => {
            const list = orders.filter((o) => o.status === col.key);
            return (
              <section className="kcol" data-s={col.key} key={col.key} aria-label={col.label}>
                <div className="kcol-h"><span>{col.label}</span><span className="c">{list.length}</span></div>
                {list.length === 0 && <div className="kempty">{col.key === "new" ? "New orders appear here." : "Nothing here."}</div>}
                {list.map((o) => {
                  const age = now - new Date(o.created_at).getTime();
                  return (
                    <article className="tk" data-s={col.key} key={o.id}>
                      <div className="tk-h">
                        <span><span className="tb">{o.table ? `Table ${o.table.label}` : "Counter"}</span><span className="no">#{o.number}</span></span>
                        <span className={`el${age > LATE_MS ? " late" : ""}`}>{elapsed(o.created_at, now)}</span>
                      </div>
                      <ul>
                        {o.items.map((l) => (
                          <li key={l.id}>
                            <span className="q">{l.quantity}×</span>
                            <span>
                              {l.name_snapshot}
                              {l.modifiers.length > 0 && <span className="m">{l.modifiers.map((m) => m.name).join(" · ")}</span>}
                              {l.note && <span className="nt">{l.note}</span>}
                            </span>
                          </li>
                        ))}
                      </ul>
                      <div className="tk-f">
                        <span className="pay">{o.payment_status === "paid" ? "Paid" : o.payment_method === "counter" ? "Pay at counter" : "Unpaid"}</span>
                        <button onClick={() => advance(o)}>{col.action}</button>
                      </div>
                    </article>
                  );
                })}
              </section>
            );
          })}

          <aside className="avail">
            <h2>Menu availability</h2>
            <p>Switch an item off when it runs out. Guests see it as sold out right away.</p>
            {items.map((i) => (
              <label className={`tog${i.available ? "" : " off"}`} key={i.id}>
                <span>{i.name}</span>
                <input type="checkbox" checked={i.available} onChange={(e) => setAvailable(i, e.target.checked)} aria-label={`${i.name} available`} />
              </label>
            ))}
          </aside>
        </div>
      </div>
    </main>
  );
}
