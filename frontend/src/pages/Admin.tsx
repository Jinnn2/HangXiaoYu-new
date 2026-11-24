import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router";
import { Ban, CheckCircle2, Coins, FileWarning, Package, Play, Plus, Scale, ShieldCheck, Users } from "lucide-react";
import { get, post, type Category, type Listing } from "../api";
import { Empty, ListingStatusBadge, Points, REVIEW_REASON, SectionTitle, StatCard, fmtTime, useAction } from "../ui";

interface Stats { user_count: number; on_sale_count: number; completed_orders: number; completed_volume: number; escrow_balance: number; issued_points: number; open_reviews: number; balance_sum: number; mismatched_accounts: number }
interface Review { review_id: number; reason: string; previous_status: string; opened_at: string; order_id: number; listing_title: string; price_snapshot_points: number; buyer_name: string; seller_name: string; paid_at: string | null; delivered_at: string | null; delivery_late_evidence: boolean }
interface UserRow { user_id: number; student_no: string; display_name: string; role: string; status: string; created_at: string; spendable_points: number; seller_reputation: number; completed_sales: number }

const TABS = [
  { key: "overview", label: "概览", icon: Scale },
  { key: "reviews", label: "异常核实", icon: FileWarning },
  { key: "users", label: "用户", icon: Users },
  { key: "listings", label: "商品", icon: Package },
];

function ReviewCard({ r, onDone }: { r: Review; onDone: () => void }) {
  const [late, setLate] = useState(false);
  const { busy, run } = useAction();
  const resolve = (decision: "CANCEL" | "CONTINUE") =>
    run(decision, () => post(`/admin/reviews/${r.review_id}/resolve`, { decision, verified_delivery_late: late }),
      decision === "CANCEL" ? "已取消订单并原额退款" : "已恢复交易").then(onDone);
  return (
    <div className="card p-5">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <span className="chip bg-rose-50 text-rose-700 ring-1 ring-inset ring-rose-600/15">{REVIEW_REASON[r.reason]}</span>
          <Link to={`/orders/${r.order_id}`} className="mt-2 block font-semibold text-slate-800 hover:text-brand-700">#{r.order_id} {r.listing_title}</Link>
          <p className="mt-0.5 text-xs text-slate-500">买家 {r.buyer_name} · 卖家 {r.seller_name} · {fmtTime(r.opened_at)} 提交</p>
        </div>
        <Points value={r.price_snapshot_points} />
      </div>
      <div className="mt-4 grid grid-cols-2 gap-2 rounded-xl bg-slate-50 p-3 text-xs text-slate-600 sm:grid-cols-3">
        <span>付款：{fmtTime(r.paid_at)}</span>
        <span>交付：{fmtTime(r.delivered_at)}</span>
        <span className={r.delivery_late_evidence ? "font-semibold text-rose-600" : ""}>{r.delivery_late_evidence ? "已超过 48 小时交付期限" : "未超过交付期限"}</span>
      </div>
      <label className={`mt-3 flex items-center gap-2 text-sm ${r.delivery_late_evidence ? "text-slate-700" : "text-slate-400"}`}>
        <input type="checkbox" className="size-4 accent-rose-500" disabled={!r.delivery_late_evidence} checked={late} onChange={(e) => setLate(e.target.checked)} />
        确认卖家超时未交付（信誉 −10）
      </label>
      <div className="mt-4 flex gap-2">
        <button className="btn-danger flex-1" disabled={!!busy} onClick={() => resolve("CANCEL")}>取消订单并退款</button>
        <button className="btn-secondary flex-1" disabled={!!busy} onClick={() => resolve("CONTINUE")}>继续交易</button>
      </div>
    </div>
  );
}

export default function AdminPage() {
  const [tab, setTab] = useState("overview");
  const [stats, setStats] = useState<Stats | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [users, setUsers] = useState<UserRow[]>([]);
  const [listings, setListings] = useState<Listing[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [newCat, setNewCat] = useState("");
  const { busy, run } = useAction();

  const load = useCallback(() => {
    get<Stats>("/admin/stats").then(setStats);
    get<Review[]>("/admin/reviews").then(setReviews);
    get<UserRow[]>("/admin/users").then(setUsers);
    get<Listing[]>("/admin/listings").then(setListings);
    get<Category[]>("/categories").then(setCategories);
  }, []);
  useEffect(() => { load(); }, [load]);

  const balanced = stats && stats.balance_sum === 0 && stats.mismatched_accounts === 0;

  return (
    <div className="animate-fade-up">
      <SectionTitle title="管理后台" desc="平台运营与异常订单处理" right={
        <button className="btn-secondary" disabled={busy === "tasks"} onClick={() => run("tasks", async () => {
          const r = await post<Record<string, number>>("/admin/tasks/run");
          load();
          return r;
        }, "到期任务已执行")}><Play className="size-4" />立即运行到期任务</button>
      } />
      <div className="mb-6 flex gap-1 overflow-x-auto rounded-2xl bg-slate-100 p-1">
        {TABS.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)} className={`flex shrink-0 items-center gap-2 rounded-xl px-4 py-2 text-sm font-medium transition ${tab === t.key ? "bg-white text-slate-900 shadow-sm" : "text-slate-500 hover:text-slate-700"}`}>
            <t.icon className="size-4" />{t.label}
            {t.key === "reviews" && reviews.length > 0 && <span className="grid size-5 place-items-center rounded-full bg-rose-500 text-[11px] text-white">{reviews.length}</span>}
          </button>
        ))}
      </div>

      {tab === "overview" && stats && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <StatCard label="注册用户" value={stats.user_count} icon={<Users className="size-4" />} />
            <StatCard label="在售商品" value={stats.on_sale_count} tone="emerald" icon={<Package className="size-4" />} />
            <StatCard label="累计成交" value={stats.completed_orders} hint={`成交额 ${stats.completed_volume.toLocaleString()} 积分`} tone="violet" icon={<CheckCircle2 className="size-4" />} />
            <StatCard label="待处理核实" value={stats.open_reviews} tone="rose" icon={<FileWarning className="size-4" />} />
          </div>
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="card p-6">
              <p className="flex items-center gap-2 font-semibold text-slate-900"><Coins className="size-4 text-amber-500" />积分总账</p>
              <dl className="mt-4 space-y-2.5 text-sm">
                <div className="flex justify-between"><dt className="text-slate-500">已发行积分（发行账户 −余额）</dt><dd className="font-semibold tabular-nums">{stats.issued_points.toLocaleString()}</dd></div>
                <div className="flex justify-between"><dt className="text-slate-500">平台托管中</dt><dd className="font-semibold tabular-nums">{stats.escrow_balance.toLocaleString()}</dd></div>
                <div className="flex justify-between"><dt className="text-slate-500">全部账户余额之和</dt><dd className="font-semibold tabular-nums">{stats.balance_sum}</dd></div>
                <div className="flex justify-between"><dt className="text-slate-500">余额与流水不一致的账户</dt><dd className="font-semibold tabular-nums">{stats.mismatched_accounts}</dd></div>
              </dl>
            </div>
            <div className={`card flex flex-col justify-center p-6 ${balanced ? "bg-gradient-to-br from-emerald-50 to-white" : "bg-rose-50"}`}>
              <ShieldCheck className={`size-10 ${balanced ? "text-emerald-500" : "text-rose-500"}`} />
              <p className="mt-3 text-lg font-bold text-slate-900">{balanced ? "账目平衡" : "账目异常，请检查"}</p>
              <p className="mt-1 text-sm text-slate-500">复式记账：每次转移恰好一出一进、合计为 0，因此所有账户余额之和恒为 0，且每个账户余额都等于其流水之和。</p>
            </div>
          </div>
        </div>
      )}

      {tab === "reviews" && (
        reviews.length === 0 ? <Empty icon={<CheckCircle2 className="size-6" />} title="没有待处理的核实" /> : (
          <div className="grid gap-4 lg:grid-cols-2">
            {reviews.map((r) => <ReviewCard key={r.review_id} r={r} onDone={load} />)}
          </div>
        )
      )}

      {tab === "users" && (
        <div className="card overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs text-slate-500">
              <tr><th className="px-5 py-3 font-medium">用户</th><th className="px-3 py-3 font-medium">学号</th><th className="px-3 py-3 text-right font-medium">积分</th><th className="px-3 py-3 text-right font-medium">信誉</th><th className="px-3 py-3 font-medium">状态</th><th className="px-5 py-3" /></tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {users.map((u) => (
                <tr key={u.user_id}>
                  <td className="px-5 py-3 font-medium text-slate-800">{u.display_name}{u.role === "ADMIN" && <span className="chip ml-2 bg-indigo-50 text-indigo-700">管理员</span>}</td>
                  <td className="px-3 py-3 font-mono text-slate-500">{u.student_no}</td>
                  <td className="px-3 py-3 text-right tabular-nums">{u.spendable_points}</td>
                  <td className="px-3 py-3 text-right tabular-nums">{u.seller_reputation}</td>
                  <td className="px-3 py-3">{u.status === "ACTIVE" ? <span className="chip bg-emerald-50 text-emerald-700">正常</span> : <span className="chip bg-rose-50 text-rose-700">已封禁</span>}</td>
                  <td className="px-5 py-3 text-right">
                    {u.role !== "ADMIN" && (
                      <button className={u.status === "ACTIVE" ? "btn-danger px-3 py-1.5 text-xs" : "btn-secondary px-3 py-1.5 text-xs"} disabled={!!busy}
                        onClick={() => run("u" + u.user_id, () => post(`/admin/users/${u.user_id}/status`, { status: u.status === "ACTIVE" ? "BANNED" : "ACTIVE" }), u.status === "ACTIVE" ? "已封禁，其在售商品已下架" : "已解封").then(load)}>
                        <Ban className="size-3.5" />{u.status === "ACTIVE" ? "封禁" : "解封"}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === "listings" && (
        <div className="space-y-4">
          <div className="card flex flex-wrap items-center gap-3 p-4">
            <span className="text-sm font-medium text-slate-600">商品分类：</span>
            {categories.map((c) => <span key={c.category_id} className="chip bg-slate-100 text-slate-600">{c.name}</span>)}
            <div className="ml-auto flex gap-2">
              <input className="input w-36 py-1.5" placeholder="新分类名" value={newCat} maxLength={20} onChange={(e) => setNewCat(e.target.value)} />
              <button className="btn-primary px-3 py-1.5" disabled={!newCat.trim() || busy === "cat"} onClick={() => run("cat", async () => { await post("/admin/categories", { name: newCat }); setNewCat(""); load(); }, "已添加分类")}><Plus className="size-4" /></button>
            </div>
          </div>
          <div className="card overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left text-xs text-slate-500">
                <tr><th className="px-5 py-3 font-medium">商品</th><th className="px-3 py-3 font-medium">卖家</th><th className="px-3 py-3 text-right font-medium">价格</th><th className="px-3 py-3 font-medium">状态</th><th className="px-5 py-3" /></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {listings.map((l) => (
                  <tr key={l.listing_id}>
                    <td className="max-w-xs truncate px-5 py-3"><Link to={`/listings/${l.listing_id}`} className="font-medium text-slate-800 hover:text-brand-700">{l.title}</Link></td>
                    <td className="px-3 py-3 text-slate-500">{l.seller_name}</td>
                    <td className="px-3 py-3 text-right tabular-nums">{l.current_price_points}</td>
                    <td className="px-3 py-3"><ListingStatusBadge status={l.status} />{l.relist_blocked && <span className="chip ml-1 bg-rose-50 text-rose-700">禁止再售</span>}</td>
                    <td className="px-5 py-3 text-right">
                      {l.status !== "SOLD" && (
                        <button className="btn-secondary px-3 py-1.5 text-xs" disabled={!!busy}
                          onClick={() => run("l" + l.listing_id, () => post(`/admin/listings/${l.listing_id}/relist-blocked`, { blocked: !l.relist_blocked }), l.relist_blocked ? "已允许再售" : "已禁止再售并下架").then(load)}>
                          {l.relist_blocked ? "允许再售" : "禁止再售"}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
