import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { loadGuestMenu } from "@/lib/menu";
import MenuClient from "./MenuClient";

// Availability changes during service, so never serve a cached menu
export const dynamic = "force-dynamic";

type Params = { params: Promise<{ slug: string; token: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { slug, token } = await params;
  const menu = await loadGuestMenu(slug, token);
  return { title: menu ? `${menu.restaurant.name} · Table ${menu.table.label}` : "Menu" };
}

export default async function TableMenuPage({ params }: Params) {
  const { slug, token } = await params;
  const menu = await loadGuestMenu(slug, token);
  if (!menu) notFound();
  return <MenuClient menu={menu} />;
}
