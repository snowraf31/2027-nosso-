import OrderStatus from "./OrderStatus";

export const dynamic = "force-dynamic";
export const metadata = { title: "Your order" };

export default async function OrderPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string; id: string }>;
  searchParams: Promise<{ k?: string }>;
}) {
  const { id } = await params;
  const { k } = await searchParams;
  return <OrderStatus id={id} k={k ?? ""} />;
}
