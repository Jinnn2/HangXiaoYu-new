import { useEffect, useState } from "react";
import { Link } from "react-router";
import { ArrowRight, Award, CheckCircle2, CreditCard, Lock, PackageCheck, Plus, ShieldCheck, ShoppingBag, Sparkles, Store, Truck } from "lucide-react";
import { get, type LedgerRow, type ListingStatus, type Me, type OrderStatus } from "../api";
import { useAuth } from "../auth";
import { InOutChart, SERIES, SegmentedBar, Sparkline } from "../charts";
import { Cover, LEDGER_EVENT, LISTING_STATUS, PageLoading, fmtTime, useCountdown } from "../ui";

interface Todo {
  order_id: number; listing_title: string; image_url: string | null; category_name: string; price_snapshot_points: number;
  status: OrderStatus; action: "PAY" | "CONFIRM" | "DELIVER"; due_at: string | null; buyer_name: string; seller_name: string; server_time: string;
}
interface DashboardData {
  summary: Me;
  stats: { bought_count: number; bought_points: number; sold_count: number; sold_points: number; active_buying: number; active_selling: number };
  flow: { day: string; income: number; spend: number; closing_balance: number }[];
  todos: Todo[];
  listing_status: { status: ListingStatus; n: number }[];
  relist_buffer: { listing_id: number; title: string }[];
  recent: LedgerRow[];
}

const LISTING_ORDER: ListingStatus[] = ["ON_SALE", "PAYMENT_RESERVED", "TRADING", "RELIST_BUFFER", "OFF_SHELF", "SOLD"];

const ACTION = {
  PAY: { label: "去付款", icon: CreditCard, cls: "bg-amber-50 text-amber-700", hint: "付款剩余" },
  DELIVER: { label: "去交付", icon: Truck, cls: "bg-sky-50 text-sky-700", hint: "交付期限剩余" },
  CONFIRM: { label: "确认收货", icon: PackageCheck, cls: "bg-indigo-50 text-indigo-700", hint: "自动确认剩余" },
};

function TodoRow({ t }: { t: Todo }) {
  const cd = useCountdown(t.due_at, t.server_time);
  const a = ACTION[t.action];
  return (
    <Link to={`/orders/${t.order_id}`} className="flex items-center gap-3 rounded-xl p-2.5 transition hover:bg-slate-50">
      <Cover title={t.listing_title} category={t.category_name} imageUrl={t.image_url} className="size-12 shrink-0 rounded-lg" small />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-slate-800">{t.listing_title}</p>
        <p className="text-xs text-slate-500">
          {t.action === "DELIVER" ? `买家 ${t.buyer_name}` : `卖家 ${t.seller_name}`} · {t.price_snapshot_points} 积分
          {cd && <> · {a.hint} <span className={cd.ms < 3600000 ? "font-semibold text-rose-600" : ""}>{cd.expired ? "已到期" : cd.text}</span></>}
        </p>
      </div>
      <span className={`chip shrink-0 py-1 ${a.cls}`}><a.icon className="size-3.5" />{a.label}</span>
    </Link>
  );
}

export default function DashboardPage() {
  const { me } = useAuth();
  const [d, setD] = useState<DashboardData | null>(null);
  useEffect(() => { get<DashboardData>("/me/dashboard").then(setD); }, []);
  if (!d || !me) return <PageLoading />;

  const s = d.summary;
  const income30 = d.flow.reduce((x, f) => x + f.income, 0);
  const spend30 = d.flow.reduce((x, f) => x + f.spend, 0);
  const statusParts = LISTING_ORDER.map((st, i) => ({
    label: LISTING_STATUS[st].label, color: SERIES[i], value: d.listing_status.find((x) => x.status === st)?.n ?? 0,
  }));
  const hour = new Date().getHours();
  const greet = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好";

  return (
    <div className="animate-fade-up space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">{greet}，{s.display_name}</h1>
          <p className="mt-1 text-sm text-slate-500">{d.todos.length > 0 ? `有 ${d.todos.length} 笔订单等你处理` : "目前没有需要处理的订单"}</p>
        </div>
        <div className="flex gap-2">
          <Link to="/valuation" className="btn-secondary"><Sparkles className="size-4" />估个价</Link>
          <Link to="/sell" className="btn-primary"><Plus className="size-4" />发布闲置</Link>
        </div>
      </div>

      {/* 第一行：主数字 + 三个指标 */}
      <div className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-[1.35fr_1fr_1fr_1fr]">
        <div className="card col-span-2 p-6 xl:col-span-1">
          <p className="text-sm font-medium text-slate-500">可用积分</p>
          <p className="mt-1 text-5xl font-bold tracking-tight text-slate-900">{s.spendable_points.toLocaleString()}</p>
          <div className="mt-3"><Sparkline values={d.flow.map((f) => f.closing_balance)} /></div>
          <p className="mt-2 text-xs text-slate-500">近 30 天 收入 <b className="text-slate-700">{income30}</b> · 支出 <b className="text-slate-700">{spend30}</b></p>
        </div>
        <div className="card p-5">
          <div className="flex items-center justify-between"><p className="text-sm font-medium text-slate-500">托管中</p><Lock className="size-4 text-slate-400" /></div>
          <p className="mt-2 text-2xl font-bold text-slate-900 sm:text-3xl">{s.escrow_points.toLocaleString()}</p>
          <p className="mt-1 text-xs text-slate-500">{d.stats.active_buying} 笔购买进行中，确认收货后转给卖家</p>
        </div>
        <div className="card p-5">
          <div className="flex items-center justify-between"><p className="text-sm font-medium text-slate-500">买家奖励分</p><Award className="size-4 text-slate-400" /></div>
          <p className="mt-2 text-2xl font-bold text-slate-900 sm:text-3xl">{s.buyer_reward_points}</p>
          <p className="mt-1 text-xs text-slate-500">{s.pending_reward_points > 0 ? `另有 ${s.pending_reward_points} 分待生效` : "每完成一笔购买 +1"}</p>
        </div>
        <div className="card col-span-2 p-5 sm:col-span-1">
          <div className="flex items-center justify-between"><p className="text-sm font-medium text-slate-500">卖家信誉</p><ShieldCheck className="size-4 text-slate-400" /></div>
          <p className="mt-2 text-2xl font-bold text-slate-900 sm:text-3xl">{s.seller_reputation}<span className="text-base font-medium text-slate-400"> / 100</span></p>
          <div className="mt-2 h-2 rounded bg-slate-100"><div className="h-full rounded-r" style={{ width: `${s.seller_reputation}%`, background: SERIES[2] }} /></div>
        </div>
      </div>

      {/* 第二行：待办 + 交易统计 */}
      <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
        <div className="card p-5">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="font-semibold text-slate-900">待办事项</h2>
            <Link to="/orders" className="flex items-center gap-1 text-xs text-slate-500 hover:text-brand-600">全部订单<ArrowRight className="size-3.5" /></Link>
          </div>
          {d.todos.length === 0 && d.relist_buffer.length === 0 ? (
            <div className="flex flex-col items-center py-10 text-center text-sm text-slate-500">
              <CheckCircle2 className="mb-2 size-8 text-emerald-400" />都处理完了
            </div>
          ) : (
            <div className="-mx-2.5 divide-y divide-slate-100">
              {d.todos.map((t) => <TodoRow key={`${t.order_id}-${t.action}`} t={t} />)}
              {d.relist_buffer.map((l) => (
                <Link key={l.listing_id} to={`/sell/${l.listing_id}`} className="flex items-center gap-3 rounded-xl p-2.5 hover:bg-slate-50">
                  <span className="grid size-12 place-items-center rounded-lg bg-violet-50 text-violet-600"><Store className="size-5" /></span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-slate-800">{l.title}</p>
                    <p className="text-xs text-slate-500">订单已退款，商品在重新上架缓冲期，可选择重新上架或继续下架</p>
                  </div>
                  <span className="chip shrink-0 bg-violet-50 py-1 text-violet-700">去处理</span>
                </Link>
              ))}
            </div>
          )}
        </div>

        <div className="card space-y-5 p-5">
          <h2 className="font-semibold text-slate-900">交易统计</h2>
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-xl bg-slate-50 p-3.5">
              <p className="flex items-center gap-1.5 text-xs text-slate-500"><ShoppingBag className="size-3.5" />买到</p>
              <p className="mt-1 text-xl font-bold text-slate-900">{d.stats.bought_count} <span className="text-sm font-medium text-slate-400">笔</span></p>
              <p className="text-xs text-slate-500">共 {d.stats.bought_points.toLocaleString()} 积分</p>
            </div>
            <div className="rounded-xl bg-slate-50 p-3.5">
              <p className="flex items-center gap-1.5 text-xs text-slate-500"><Store className="size-3.5" />卖出</p>
              <p className="mt-1 text-xl font-bold text-slate-900">{d.stats.sold_count} <span className="text-sm font-medium text-slate-400">笔</span></p>
              <p className="text-xs text-slate-500">共 {d.stats.sold_points.toLocaleString()} 积分</p>
            </div>
          </div>
          <div>
            <div className="mb-3 flex items-center justify-between">
              <p className="text-sm font-medium text-slate-700">我的商品</p>
              <Link to="/my/listings" className="text-xs text-slate-500 hover:text-brand-600">管理</Link>
            </div>
            <SegmentedBar parts={statusParts} />
          </div>
        </div>
      </div>

      {/* 第三行：收支图 + 最近流水 */}
      <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
        <div className="card p-5">
          <h2 className="mb-1 font-semibold text-slate-900">近 30 天积分收支</h2>
          <p className="mb-3 text-xs text-slate-400">数据来自 hxy.user_daily_flow：按天汇总你账户的流水</p>
          <InOutChart data={d.flow.map((f) => ({ label: f.day.slice(5), income: f.income, spend: f.spend }))} />
        </div>
        <div className="card p-5">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="font-semibold text-slate-900">最近流水</h2>
            <Link to="/account" className="flex items-center gap-1 text-xs text-slate-500 hover:text-brand-600">全部<ArrowRight className="size-3.5" /></Link>
          </div>
          <ul className="divide-y divide-slate-100">
            {d.recent.map((r) => (
              <li key={r.ledger_id} className="flex items-center justify-between gap-3 py-2.5 text-sm">
                <div className="min-w-0">
                  <p className="truncate text-slate-700">{r.listing_title ?? LEDGER_EVENT[r.event_type]}</p>
                  <p className="text-xs text-slate-400">{LEDGER_EVENT[r.event_type]} · {fmtTime(r.occurred_at)}</p>
                </div>
                <span className={`shrink-0 font-semibold tabular-nums ${r.delta_points > 0 ? "text-emerald-600" : "text-slate-600"}`}>{r.delta_points > 0 ? "+" : ""}{r.delta_points}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
