import { useCallback, useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { ChevronLeft, Clock, Heart, Lock, Pencil, ShieldCheck, ShoppingBag, Tag } from "lucide-react";
import { del, get, post, put, type ListingDetail, type OrderDetail } from "../api";
import { useAuth } from "../auth";
import { CONDITION_LABEL, Cover, ListingStatusBadge, Modal, PageLoading, Points, fmtTime, timeAgo, useAction } from "../ui";

function PriceChart({ history }: { history: ListingDetail["price_history"] }) {
  if (history.length < 2) {
    return <p className="text-sm text-slate-500">自 {fmtTime(history[0]?.changed_at)} 挂牌以来未改价。</p>;
  }
  const W = 560, H = 140, P = 24;
  const prices = history.map((h) => h.price_points);
  const min = Math.min(...prices), max = Math.max(...prices);
  const x = (i: number) => P + (i * (W - 2 * P)) / (history.length - 1);
  const y = (v: number) => (max === min ? H / 2 : P + ((max - v) * (H - 2 * P)) / (max - min));
  const d = history.map((h, i) => `${i ? "L" : "M"}${x(i)},${y(h.price_points)}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full">
      <defs>
        <linearGradient id="pf" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3b93f6" stopOpacity="0.25" />
          <stop offset="1" stopColor="#3b93f6" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={`${d} L${x(history.length - 1)},${H - 4} L${x(0)},${H - 4} Z`} fill="url(#pf)" />
      <path d={d} fill="none" stroke="#2574eb" strokeWidth="2.5" strokeLinejoin="round" />
      {history.map((h, i) => (
        <g key={h.history_id}>
          <circle cx={x(i)} cy={y(h.price_points)} r="4" fill="white" stroke="#2574eb" strokeWidth="2" />
          <text x={x(i)} y={y(h.price_points) - 10} textAnchor="middle" className="fill-slate-600 text-[11px] font-semibold">{h.price_points}</text>
        </g>
      ))}
    </svg>
  );
}

export default function ListingDetailPage() {
  const { id } = useParams();
  const { me, refresh } = useAuth();
  const navigate = useNavigate();
  const [item, setItem] = useState<ListingDetail | null>(null);
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  const { busy, run } = useAction();

  const load = useCallback(() => get<ListingDetail>(`/listings/${id}`).then(setItem).catch((e) => setError(e.message)), [id]);
  useEffect(() => { load(); }, [load]);

  if (error) return <div className="py-24 text-center text-slate-500">{error}</div>;
  if (!item) return <PageLoading />;

  const mine = me?.user_id === item.seller_id;
  const canBuy = item.status === "ON_SALE" && !mine;

  const toggleFavorite = () => {
    if (!me) return navigate(`/login?next=/listings/${item.listing_id}`);
    run("fav", async () => {
      const r = item.is_favorite ? await del<{ is_favorite: boolean }>(`/listings/${item.listing_id}/favorite`)
        : await put<{ is_favorite: boolean }>(`/listings/${item.listing_id}/favorite`);
      setItem({ ...item, is_favorite: r.is_favorite, favorite_count: item.favorite_count + (r.is_favorite ? 1 : -1) });
    });
  };

  const buy = () => run("buy", async () => {
    const order = await post<OrderDetail>("/orders", { listing_id: item.listing_id, expected_price: item.current_price_points });
    navigate(`/orders/${order.order_id}`);
  }, "下单成功，请在 5 分钟内完成付款").finally(() => { setConfirm(false); load(); refresh(); });

  return (
    <div className="animate-fade-up">
      <button onClick={() => navigate(-1)} className="btn-ghost -ml-3 mb-3 px-3 py-1.5"><ChevronLeft className="size-4" />返回</button>
      <div className="grid gap-6 lg:grid-cols-[1.5fr_1fr]">
        <div className="space-y-6">
          <div className="card overflow-hidden">
            <Cover title={item.title} category={item.category_name} imageUrl={item.image_url} className="aspect-[16/10] w-full" />
          </div>
          <div className="card p-6">
            <h2 className="mb-3 font-semibold text-slate-900">商品描述</h2>
            <p className="whitespace-pre-wrap text-[15px] leading-relaxed text-slate-600">{item.description || "卖家没有填写描述。"}</p>
          </div>
          <div className="card p-6">
            <h2 className="mb-1 font-semibold text-slate-900">价格走势</h2>
            <p className="mb-4 text-xs text-slate-400">数据来自 price_history 表：发布与每次改价各追加一条，历史不可修改</p>
            <PriceChart history={item.price_history} />
          </div>
        </div>

        <div className="space-y-4 lg:sticky lg:top-24 lg:self-start">
          <div className="card p-6">
            <div className="flex items-start justify-between gap-3">
              <div className="flex flex-wrap gap-1.5">
                <ListingStatusBadge status={item.status} />
                <span className="chip bg-slate-100 text-slate-600">{item.category_name}</span>
                <span className="chip bg-slate-100 text-slate-600">{CONDITION_LABEL[item.condition_level]}</span>
              </div>
              <button onClick={toggleFavorite} disabled={busy === "fav"} className={`grid size-10 shrink-0 place-items-center rounded-full border transition ${item.is_favorite ? "border-rose-200 bg-rose-50 text-rose-500" : "border-slate-200 text-slate-400 hover:text-rose-500"}`}>
                <Heart className={`size-5 ${item.is_favorite ? "fill-current" : ""}`} />
              </button>
            </div>
            <h1 className="mt-3 text-xl font-bold leading-snug text-slate-900">{item.title}</h1>
            <div className="mt-4 flex items-end gap-3">
              <Points value={item.current_price_points} size="xl" />
              {item.original_price_points && <span className="pb-1 text-sm text-slate-400">原价 <s>{item.original_price_points}</s></span>}
            </div>
            <div className="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-500">
              <span className="flex items-center gap-1"><Clock className="size-3.5" />{timeAgo(item.created_at)}发布</span>
              <span className="flex items-center gap-1"><Heart className="size-3.5" />{item.favorite_count} 人收藏</span>
            </div>

            <div className="mt-6 space-y-2">
              {item.my_active_order_id ? (
                <Link to={`/orders/${item.my_active_order_id}`} className="btn-primary w-full py-3">查看我的订单</Link>
              ) : mine ? (
                <Link to={`/sell/${item.listing_id}`} className="btn-secondary w-full py-3"><Pencil className="size-4" />管理这件商品</Link>
              ) : (
                <button className="btn-primary w-full py-3 text-base" disabled={!canBuy} onClick={() => (me ? setConfirm(true) : navigate(`/login?next=/listings/${item.listing_id}`))}>
                  {canBuy ? <><ShoppingBag className="size-5" />立即购买</> : <><Lock className="size-4" />{item.status === "SOLD" ? "已售出" : "暂不可购买"}</>}
                </button>
              )}
              <p className="flex items-start gap-1.5 text-xs text-slate-500">
                <ShieldCheck className="mt-px size-3.5 shrink-0 text-emerald-500" />
                付款后积分由平台托管，确认收货（或交付 24 小时后自动完成）才转给卖家。
              </p>
            </div>
          </div>

          <Link to={`/users/${item.seller_id}`} className="card flex items-center gap-4 p-5 transition hover:shadow-lift">
            <span className="grid size-12 place-items-center rounded-2xl bg-gradient-to-br from-brand-400 to-indigo-500 text-lg font-bold text-white">{item.seller_name.slice(0, 1)}</span>
            <div className="flex-1">
              <p className="font-semibold text-slate-900">{item.seller_name}</p>
              <p className="text-xs text-slate-500">卖家信誉 {item.seller_reputation} / 100</p>
              <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
                <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-emerald-500" style={{ width: `${item.seller_reputation}%` }} />
              </div>
            </div>
          </Link>

          <Link to={`/valuation?category=${item.category_id}&condition=${item.condition_level}${item.original_price_points ? `&original=${item.original_price_points}` : ""}&name=${encodeURIComponent(item.title)}`} className="card flex items-center gap-3 p-4 text-sm text-slate-600 transition hover:shadow-lift">
            <Tag className="size-4 text-brand-500" />这个价格合理吗？用智能估价对比一下
          </Link>
        </div>
      </div>

      <Modal open={confirm} onClose={() => setConfirm(false)} title="确认下单" footer={
        <>
          <button className="btn-secondary" onClick={() => setConfirm(false)}>再想想</button>
          <button className="btn-primary" disabled={busy === "buy"} onClick={buy}>确认下单</button>
        </>
      }>
        <div className="space-y-3 text-sm">
          <div className="flex justify-between"><span className="text-slate-500">商品</span><span className="font-medium">{item.title}</span></div>
          <div className="flex justify-between"><span className="text-slate-500">价格</span><Points value={item.current_price_points} size="sm" /></div>
          <div className="flex justify-between"><span className="text-slate-500">我的可用积分</span><span className="font-medium tabular-nums">{me?.spendable_points}</span></div>
          <p className="rounded-xl bg-amber-50 p-3 text-amber-800">下单后商品为你保留 5 分钟，期间价格锁定；超时未付款将自动释放。</p>
        </div>
      </Modal>
    </div>
  );
}
