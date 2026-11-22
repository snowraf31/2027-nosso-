"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { GuestOrder } from "@/lib/types";
import { makeFmt } from "@/lib/i18n";
import { Doodle, readStore } from "@/components/guest/ui";

const STEPS = [
  { key: "new", label: "Received" },
  { key: "preparing", label: "Making it" },
  { key: "ready", label: "On its way" },
] as const;

const COPY: Record<string, { title: string; sub: string; icon: string }> = {
  new: { title: "Got it!", sub: "Your order is with the kitchen.", icon: "cup" },
  preparing: { title: "Making it now.", sub: "Sit back. We'll bring everything to your table.", icon: "egg" },
  ready: { title: "Ready!", sub: "A server is bringing it over right now.", icon: "sandwich" },
  served: { title: "Enjoy.", sub: "Need anything else? Just order again from your phone.", icon: "pastry" },
  cancelled: { title: "Order cancelled", sub: "Please check with a server at the counter.", icon: "leaf" },
};

// Doodles per brand style, so a burger joint doesn't show a coffee cup
const BRAND_ICONS: Record<string, Partial<Record<string, string>>> = {
  diner: { new: "burger", preparing: "flame", ready: "fries", served: "shake", cancelled: "leaf" },
  glace: { new: "cup", preparing: "cake", ready: "pastry", served: "cake", cancelled: "leaf" },
};

/** Polls the order every few seconds. Guests have no login, so no realtime channel here. */
export default function OrderStatus({ id, k }: { id: string; k: string }) {
  const router = useRouter();
  const [order, setOrder] = useState<GuestOrder | null>(null);
  const [missing, setMissing] = useState(false);
  const [back, setBack] = useState<string | null>(null);
  const [brand, setBrand] = useState<string>("harbor");
  const [loc, setLoc] = useState<{ locale: string | null; currency: string | null }>({ locale: null, currency: null });

  useEffect(() => {
    setBack(readStore<string | null>("tabletop:return", null, true));
    setBrand(readStore<string>("tabletop:brand", "harbor", true));
    setLoc(readStore("tabletop:locale", { locale: null, currency: null }, true));
  }, []);

  const { t, money } = makeFmt(order?.locale ?? loc.locale, order?.currency ?? loc.currency);

  useEffect(() => {
    let stop = false;
    let timer: ReturnType<typeof setTimeout>;
    async function load() {
      try {
        const res = await fetch(`/api/orders/${id}?k=${encodeURIComponent(k)}`, { cache: "no-store" });
        if (res.status === 404) return setMissing(true);
        if (res.ok) {
          const data = (await res.json()) as GuestOrder;
          setOrder(data);
          if (data.status === "served" || data.status === "cancelled") return;
        }
      } catch {
        /* temporary network issue: keep trying */
      }
      if (!stop) timer = setTimeout(load, document.hidden ? 15000 : 4000);
    }
    load();
    return () => {
      stop = true;
      clearTimeout(timer);
    };
  }, [id, k]);

  if (missing) {
    return (
      <main className="g g-status" data-brand={brand}>
        <Doodle name="leaf" className="g-status-doodle" />
        <h1 className="g-status-title">{t("We can't find that order.")}</h1>
        <p className="g-status-sub">{t("Please ask a server at the counter.")}</p>
      </main>
    );
  }
  if (!order) {
    return (
      <main className="g g-status" data-brand={brand} aria-busy="true">
        <Doodle name={BRAND_ICONS[brand]?.new ?? "cup"} className="g-status-doodle wiggle" />
        <p className="g-status-sub">{t("Checking on your order…")}</p>
      </main>
    );
  }

  const copy = COPY[order.status] ?? COPY.new;
  const style = order.brand_style ?? "harbor";
  const icon = BRAND_ICONS[style]?.[order.status] ?? copy.icon;
  const idx = order.status === "served" ? STEPS.length : STEPS.findIndex((s) => s.key === order.status);

  return (
    <main className="g g-status" data-brand={style}>
      <div className="g-hero-top">
        <span className="g-brand">{order.restaurant_name}</span>
        {order.table_label && <span className="g-table">{t("Table {n}", { n: order.table_label })}</span>}
      </div>

      <Doodle name={icon} className={`g-status-doodle${order.status === "new" || order.status === "preparing" ? " wiggle" : ""}`} />
      <h1 className="g-status-title" aria-live="polite">{t(copy.title)}</h1>
      <p className="g-status-sub">{t(copy.sub)}</p>
      <p className="g-hand g-status-no">{t("order #{n}", { n: order.number })}</p>

      {order.status !== "cancelled" && (
        <ol className="g-progress" aria-label={t("Order progress")}>
          {STEPS.map((s, i) => (
            <li key={s.key} className={i < idx ? "done" : i === idx ? "now" : ""}>
              <span className="g-progress-bar" />
              <span className="g-progress-label">{t(s.label)}</span>
            </li>
          ))}
        </ol>
      )}

      <section className="g-receipt" aria-label={t("Your order")}>
        {order.items.map((l) => (
          <div className="g-receipt-row" key={l.id}>
            <span>
              <b>{l.quantity}×</b> {l.name_snapshot}
              {l.modifiers.length > 0 && <small>{l.modifiers.map((m) => m.name).join(" · ")}</small>}
              {l.note && <small>“{l.note}”</small>}
            </span>
            <span className="g-price">{money(l.unit_price_cents * l.quantity)}</span>
          </div>
        ))}
        <div className="g-receipt-row total">
          <span>{order.payment_method === "counter" ? t("Total, pay at the counter") : t("Total")}</span>
          <span className="g-price">{money(order.total_cents)}</span>
        </div>
      </section>

      <button className="g-btn ghost block" onClick={() => (back ? router.push(back) : history.back())}>
        {t("Order something else")}
      </button>
    </main>
  );
}
