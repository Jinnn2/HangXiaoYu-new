import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { ChevronRight, Receipt } from "lucide-react";
import { get, type Order } from "../api";
import { Cover, Empty, OrderStatusBadge, PageLoading, Points, SectionTitle, fmtTime, useCountdown } from "../ui";

function Hint({ o, role }: { o: Order; role: "buyer" | "seller" }) {
  const pay = useCountdown(o.status === "PENDING_PAYMENT" ? o.payment_deadline_at : null, o.server_time);
  const auto = useCountdown(o.status === "PENDING_RECEIPT" ? o.auto_complete_at : null, o.server_time);
  if (pay && !pay.expired) return <span className="text-amber-600">{role === "buyer" ? "请在" : "买家需在"} {pay.text} 内付款</span>;
  if (o.status === "PENDING_DELIVERY") return <span className="text-sky-600">{role === "seller" ? "买家已付款，请尽快交付" : "等待卖家交付"}</span>;
  if (auto && !auto.expired) return <span className="text-indigo-600">{auto.text}后自动确认收货</span>;
  if (o.status === "UNDER_REVIEW") return <span className="text-rose-600">管理员核实中</span>;
  return null;
}

export default function OrdersPage() {
  const [params, setParams] = useSearchParams();
  const role = (params.get("role") as "buyer" | "seller") ?? "buyer";
  const [orders, setOrders] = useState<Order[] | null>(null);
  useEffect(() => {
    setOrders(null);
    get<Order[]>(`/me/orders?role=${role}`).then(setOrders);
  }, [role]);

  const active = orders?.filter((o) => ["PENDING_PAYMENT", "PENDING_DELIVERY", "PENDING_RECEIPT", "UNDER_REVIEW"].includes(o.status)).length ?? 0;

  return (
    <div className="animate-fade-up">
      <SectionTitle title="我的订单" desc={orders ? `进行中 ${active} 笔 · 共 ${orders.length} 笔` : undefined} />
      <div className="mb-5 inline-flex rounded-full bg-slate-100 p-1">
        {(["buyer", "seller"] as const).map((r) => (
          <button key={r} onClick={() => setParams({ role: r })} className={`rounded-full px-5 py-1.5 text-sm font-medium transition ${role === r ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
            {r === "buyer" ? "我买到的" : "我卖出的"}
          </button>
        ))}
      </div>
      {!orders ? <PageLoading /> : orders.length === 0 ? (
        <Empty icon={<Receipt className="size-6" />} title="还没有订单" hint={role === "buyer" ? "去市场逛逛吧" : "发布的商品被购买后会出现在这里"} action={<Link to="/" className="btn-primary">去逛逛</Link>} />
      ) : (
        <div className="space-y-3">
          {orders.map((o) => (
            <Link key={o.order_id} to={`/orders/${o.order_id}`} className="card flex items-center gap-4 p-4 transition hover:shadow-lift">
              <Cover title={o.listing_title} category={o.category_name} imageUrl={o.image_url} className="size-16 shrink-0 rounded-xl sm:size-20" />
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="truncate font-semibold text-slate-800">{o.listing_title}</span>
                  <OrderStatusBadge status={o.status} />
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  订单 #{o.order_id} · {role === "buyer" ? `卖家 ${o.seller_name}` : `买家 ${o.buyer_name}`} · {fmtTime(o.created_at)}
                </p>
                <p className="mt-1 text-xs font-medium"><Hint o={o} role={role} /></p>
              </div>
              <Points value={o.price_snapshot_points} />
              <ChevronRight className="size-5 shrink-0 text-slate-300" />
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
