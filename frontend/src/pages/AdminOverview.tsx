import { useEffect, useState } from "react";
import { Link } from "react-router";
import { AlertTriangle, CheckCircle2, Clock, FileWarning, Package, ShieldCheck, Users } from "lucide-react";
import { get, type OrderStatus } from "../api";
import { AreaChart, ColumnChart, RankBars, SERIES, SegmentedBar, Sparkline, compact } from "../charts";
import { ORDER_STATUS, PageLoading, fmtTime, useCountdown } from "../ui";

interface Daily { day: string; new_users: number; new_listings: number; new_orders: number; completed_orders: number; completed_volume: number }
interface AdminDashboard {
  stats: { user_count: number; on_sale_count: number; completed_orders: number; completed_volume: number; escrow_balance: number; issued_points: number; open_reviews: number; balance_sum: number; mismatched_accounts: number };
  daily: Daily[];
  order_status: { status: OrderStatus; n: number }[];
  categories: { category_id: number; name: string; deals_180d: number; on_sale_count: number; volume_180d: number }[];
  top_sellers: { seller_id: number; seller_name: string; reputation: number; deals: number; volume: number }[];
  attention: { order_id: number; listing_title: string; buyer_name: string; seller_name: string; status: OrderStatus; due_at: string; server_time: string }[];
  reviews: { n: number; oldest: string | null };
}

const ORDER_ORDER: OrderStatus[] = ["PENDING_PAYMENT", "PENDING_DELIVERY", "PENDING_RECEIPT", "UNDER_REVIEW", "COMPLETED", "CANCELED", "PAYMENT_EXPIRED"];

function Tile({ label, value, icon, spark, hint }: { label: string; value: string | number; icon: React.ReactNode; spark?: number[]; hint?: string }) {
  return (
    <div className="card p-5">
      <div className="flex items-center justify-between"><p className="text-sm font-medium text-slate-500">{label}</p><span className="text-slate-400">{icon}</span></div>
      <p className="mt-2 text-2xl font-bold text-slate-900 sm:text-3xl">{value}</p>
      {spark && <div className="mt-2"><Sparkline values={spark} height={28} /></div>}
      {hint && <p className="mt-1 text-xs text-slate-500">{hint}</p>}
    </div>
  );
}

function AttentionRow({ a }: { a: AdminDashboard["attention"][number] }) {
  const cd = useCountdown(a.due_at, a.server_time);
  const late = a.status === "PENDING_DELIVERY";
  return (
    <Link to={`/orders/${a.order_id}`} className="flex items-center gap-3 rounded-xl p-2.5 hover:bg-slate-50">
      <span className={`grid size-9 shrink-0 place-items-center rounded-lg ${late ? "bg-rose-50 text-rose-600" : "bg-amber-50 text-amber-600"}`}>
        {late ? <AlertTriangle className="size-4" /> : <Clock className="size-4" />}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-slate-800">#{a.order_id} {a.listing_title}</p>
        <p className="text-xs text-slate-500">{ORDER_STATUS[a.status].label} · 买家 {a.buyer_name} · 卖家 {a.seller_name}</p>
      </div>
      <span className={`shrink-0 text-xs font-semibold tabular-nums ${cd?.expired ? "text-rose-600" : "text-slate-600"}`}>
        {cd?.expired ? "已超时" : `剩 ${cd?.text}`}
      </span>
    </Link>
  );
}

export default function AdminOverview({ onGoReviews, refreshKey }: { onGoReviews: () => void; refreshKey: number }) {
  const [d, setD] = useState<AdminDashboard | null>(null);
  useEffect(() => { get<AdminDashboard>("/admin/dashboard").then(setD); }, [refreshKey]);
  if (!d) return <PageLoading />;
  const s = d.stats;
  const balanced = s.balance_sum === 0 && s.mismatched_accounts === 0;
  const vol14 = d.daily.reduce((x, r) => x + r.completed_volume, 0);
  const deals14 = d.daily.reduce((x, r) => x + r.completed_orders, 0);
  const label = (r: Daily) => r.day.slice(5);

  return (
    <div className="space-y-4">
      {/* 第一行：主数字 + 指标 */}
      <div className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-[1.35fr_1fr_1fr_1fr]">
        <div className="card col-span-2 p-6 xl:col-span-1">
          <p className="text-sm font-medium text-slate-500">累计成交额（积分）</p>
          <p className="mt-1 text-5xl font-bold tracking-tight text-slate-900">{s.completed_volume.toLocaleString()}</p>
          <div className="mt-3"><Sparkline values={d.daily.map((r) => r.completed_volume)} /></div>
          <p className="mt-2 text-xs text-slate-500">近 14 天 {deals14} 笔 · {vol14.toLocaleString()} 积分 · 累计 {s.completed_orders} 笔</p>
        </div>
        <Tile label="注册用户" value={s.user_count} icon={<Users className="size-4" />} spark={d.daily.map((r) => r.new_users)} hint="走势：每日新注册" />
        <Tile label="在售商品" value={s.on_sale_count} icon={<Package className="size-4" />} spark={d.daily.map((r) => r.new_listings)} hint="走势：每日新发布" />
        <button onClick={onGoReviews} className="card p-5 text-left transition hover:shadow-lift">
          <div className="flex items-center justify-between"><p className="text-sm font-medium text-slate-500">待处理核实</p><FileWarning className="size-4 text-slate-400" /></div>
          <p className="mt-2 text-2xl font-bold text-slate-900 sm:text-3xl">{d.reviews.n}</p>
          <p className="mt-1 text-xs text-slate-500">{d.reviews.oldest ? `最早一条提交于 ${fmtTime(d.reviews.oldest)}` : "没有待处理的核实"}</p>
          {d.reviews.n > 0 && <p className="mt-2 text-xs font-semibold text-brand-600">去处理 →</p>}
        </button>
      </div>

      {/* 第二行：成交额走势 + 每日新订单 */}
      <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
        <div className="card p-5">
          <h2 className="font-semibold text-slate-900">近 14 天每日成交额</h2>
          <p className="mb-3 text-xs text-slate-400">按完成时间统计已完成订单的价格快照之和（积分）</p>
          <AreaChart data={d.daily.map((r) => ({ label: label(r), value: r.completed_volume }))} unit=" 积分" label="成交额" />
        </div>
        <div className="card p-5">
          <h2 className="font-semibold text-slate-900">近 14 天每日新订单</h2>
          <p className="mb-3 text-xs text-slate-400">按下单时间统计，含已取消和超时的订单</p>
          <ColumnChart data={d.daily.map((r) => ({ label: label(r), value: r.new_orders }))} color={SERIES[6]} unit=" 笔" label="新订单" />
        </div>
      </div>

      {/* 第三行：订单状态 + 分类 + 卖家 */}
      <div className="grid gap-4 lg:grid-cols-3">
        <div className="card p-5 lg:col-span-3">
          <h2 className="mb-4 font-semibold text-slate-900">全部订单状态分布</h2>
          <SegmentedBar parts={ORDER_ORDER.map((st, i) => ({ label: ORDER_STATUS[st].label, color: SERIES[i], value: d.order_status.find((x) => x.status === st)?.n ?? 0 }))} />
        </div>
        <div className="card p-5">
          <h2 className="mb-4 font-semibold text-slate-900">分类成交额 <span className="text-xs font-normal text-slate-400">近 180 天</span></h2>
          <RankBars rows={d.categories.map((c) => ({ label: c.name, value: c.volume_180d, note: `${c.deals_180d} 笔` }))} />
        </div>
        <div className="card p-5">
          <h2 className="mb-4 font-semibold text-slate-900">卖家排行 <span className="text-xs font-normal text-slate-400">累计成交额</span></h2>
          <RankBars rows={d.top_sellers.map((t) => ({ label: t.seller_name, value: t.volume, note: `${t.deals} 笔 · 信誉 ${t.reputation}` }))} color={SERIES[2]} />
        </div>
        <div className="card p-5">
          <h2 className="mb-2 font-semibold text-slate-900">需要关注</h2>
          {d.attention.length === 0 ? (
            <div className="flex flex-col items-center py-8 text-sm text-slate-500"><CheckCircle2 className="mb-2 size-7 text-emerald-400" />没有即将超时的订单</div>
          ) : (
            <div className="-mx-2.5">{d.attention.map((a) => <AttentionRow key={a.order_id} a={a} />)}</div>
          )}
          <p className="mt-2 text-xs text-slate-400">待付款订单，以及 12 小时内到交付期限的待交付订单</p>
        </div>
      </div>

      {/* 第四行：积分总账 */}
      <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
        <div className="card p-5">
          <h2 className="mb-3 font-semibold text-slate-900">积分总账</h2>
          <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            {[
              ["已发行积分", compact(s.issued_points)], ["平台托管中", compact(s.escrow_balance)],
              ["全部余额之和", String(s.balance_sum)], ["余额与流水不符", String(s.mismatched_accounts)],
            ].map(([k, v]) => (
              <div key={k} className="rounded-xl bg-slate-50 p-3.5"><dt className="text-xs text-slate-500">{k}</dt><dd className="mt-1 text-xl font-bold text-slate-900">{v}</dd></div>
            ))}
          </dl>
        </div>
        <div className={`card flex items-center gap-4 p-5 ${balanced ? "" : "border-rose-200 bg-rose-50"}`}>
          <ShieldCheck className={`size-10 shrink-0 ${balanced ? "text-emerald-500" : "text-rose-500"}`} />
          <div>
            <p className="font-bold text-slate-900">{balanced ? "账目平衡" : "账目异常，请检查"}</p>
            <p className="mt-0.5 text-xs leading-relaxed text-slate-500">每次转移一出一进、合计为 0，所以全部余额之和恒为 0，每个账户余额都等于它的流水之和。</p>
          </div>
        </div>
      </div>
    </div>
  );
}
