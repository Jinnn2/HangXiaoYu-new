import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router";
import { AlertTriangle, Check, Clock, CreditCard, PackageCheck, ShieldCheck, Truck, Undo2, X } from "lucide-react";
import { get, post, type OrderDetail } from "../api";
import { useAuth } from "../auth";
import { Cover, LEDGER_EVENT, Modal, OrderStatusBadge, PageLoading, Points, REVIEW_REASON, fmtTime, useAction, useCountdown } from "../ui";

const STEPS = [
  { key: "created_at", label: "下单", icon: Clock },
  { key: "paid_at", label: "付款托管", icon: CreditCard },
  { key: "delivered_at", label: "卖家交付", icon: Truck },
  { key: "completed_at", label: "交易完成", icon: PackageCheck },
] as const;

function Steps({ o }: { o: OrderDetail }) {
  const failed = o.status === "CANCELED" || o.status === "PAYMENT_EXPIRED";
  return (
    <div className="flex items-start">
      {STEPS.map((s, i) => {
        const done = !!o[s.key];
        const Icon = s.icon;
        return (
          <div key={s.key} className="flex flex-1 flex-col items-center text-center">
            <div className="flex w-full items-center">
              <div className={`h-0.5 flex-1 ${i === 0 ? "invisible" : done ? "bg-brand-500" : "bg-slate-200"}`} />
              <div className={`grid size-10 shrink-0 place-items-center rounded-full ${done ? "bg-gradient-to-br from-brand-500 to-indigo-500 text-white shadow-md shadow-brand-500/30" : "bg-slate-100 text-slate-400"}`}>
                <Icon className="size-[18px]" />
              </div>
              <div className={`h-0.5 flex-1 ${i === STEPS.length - 1 ? "invisible" : o[STEPS[i + 1].key] ? "bg-brand-500" : "bg-slate-200"}`} />
            </div>
            <p className={`mt-2 text-xs font-semibold sm:text-sm ${done ? "text-slate-800" : "text-slate-400"}`}>{s.label}</p>
            <p className="text-[11px] text-slate-400">{fmtTime(o[s.key])}</p>
          </div>
        );
      })}
      {failed && <div className="sr-only">订单已终止</div>}
    </div>
  );
}

export default function OrderDetailPage() {
  const { id } = useParams();
  const { refresh } = useAuth();
  const [o, setO] = useState<OrderDetail | null>(null);
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState<null | { action: string; title: string; text: string; danger?: boolean }>(null);
  const { busy, run } = useAction();

  const load = useCallback(() => get<OrderDetail>(`/orders/${id}`).then(setO).catch((e) => setError(e.message)), [id]);
  useEffect(() => { load(); }, [load]);
  const pay = useCountdown(o?.status === "PENDING_PAYMENT" ? o.payment_deadline_at : null, o?.server_time);
  const auto = useCountdown(o?.status === "PENDING_RECEIPT" ? o.auto_complete_at : null, o?.server_time);
  const deliverBy = useCountdown(o?.status === "PENDING_DELIVERY" && o.paid_at ? new Date(new Date(o.paid_at).getTime() + 48 * 3600000).toISOString() : null, o?.server_time);

  if (error) return <div className="py-24 text-center text-slate-500">{error}</div>;
  if (!o) return <PageLoading />;

  const act = (action: string, msg: string) => run(action, async () => { setO(await post<OrderDetail>(`/orders/${o.order_id}/${action}`)); refresh(); }, msg).then(() => setConfirm(null));
  const buyer = o.my_role === "buyer", seller = o.my_role === "seller";

  let banner: { tone: string; icon: typeof Clock; title: string; text: string } | null = null;
  if (o.status === "PENDING_PAYMENT") banner = { tone: "from-amber-400 to-orange-500", icon: Clock, title: pay?.expired ? "付款已超时" : `待付款 · 剩余 ${pay?.text}`, text: buyer ? "商品已为你保留，价格已锁定。超时未付款将自动释放。" : "买家下单后有 5 分钟付款时间。" };
  else if (o.status === "PENDING_DELIVERY") banner = { tone: "from-sky-500 to-brand-600", icon: Truck, title: "积分已托管，等待卖家交付", text: seller ? `请在 ${deliverBy?.expired ? "（已超时）" : deliverBy?.text} 内完成当面交付并点击"已交付"。` : "付款已进入平台托管，卖家确认交付后进入待收货。" };
  else if (o.status === "PENDING_RECEIPT") banner = { tone: "from-indigo-500 to-violet-600", icon: PackageCheck, title: `待收货 · ${auto?.text ?? ""} 后自动完成`, text: buyer ? "收到商品后请确认收货；未收到请在自动完成前反馈。" : "买家确认收货或到期自动完成后，积分转入你的账户。" };
  else if (o.status === "UNDER_REVIEW") banner = { tone: "from-rose-500 to-pink-600", icon: AlertTriangle, title: `管理员核实中：${REVIEW_REASON[o.open_review_reason ?? ""] ?? ""}`, text: "核实期间暂停交付与自动结算，积分继续由平台托管。" };
  else if (o.status === "COMPLETED") banner = { tone: "from-emerald-500 to-teal-600", icon: Check, title: "交易完成", text: o.completion_method === "AUTO" ? "交付 24 小时后系统自动确认收货。" : "买家已确认收货，积分已转给卖家。" };
  else banner = { tone: "from-slate-400 to-slate-500", icon: X, title: o.status === "PAYMENT_EXPIRED" ? "支付超时，订单已关闭" : "订单已取消", text: o.cancel_reason ? `原因：${REVIEW_REASON[o.cancel_reason] ?? o.cancel_reason}${o.paid_at ? "，托管积分已原额退回买家。" : "。"}` : "商品已重新开放购买。" };
  const BannerIcon = banner.icon;

  return (
    <div className="animate-fade-up mx-auto max-w-4xl space-y-5">
      <div className={`relative overflow-hidden rounded-3xl bg-gradient-to-br ${banner.tone} p-6 text-white shadow-lift`}>
        <div className="absolute -right-10 -top-10 size-40 rounded-full bg-white/10" />
        <div className="relative flex items-start gap-4">
          <div className="grid size-12 shrink-0 place-items-center rounded-2xl bg-white/20 backdrop-blur"><BannerIcon className="size-6" /></div>
          <div>
            <p className="text-lg font-bold">{banner.title}</p>
            <p className="mt-1 text-sm text-white/85">{banner.text}</p>
          </div>
        </div>
      </div>

      <div className="card p-6"><Steps o={o} /></div>

      <div className="grid gap-5 md:grid-cols-[1.3fr_1fr]">
        <div className="card p-5">
          <Link to={`/listings/${o.listing_id}`} className="flex gap-4">
            <Cover title={o.listing_title} category={o.category_name} imageUrl={o.image_url} className="size-24 shrink-0 rounded-xl" small />
            <div className="min-w-0">
              <p className="font-semibold text-slate-800 hover:text-brand-700">{o.listing_title}</p>
              <div className="mt-1"><OrderStatusBadge status={o.status} /></div>
              <div className="mt-2"><Points value={o.price_snapshot_points} /></div>
            </div>
          </Link>
          <dl className="mt-5 grid grid-cols-2 gap-y-2.5 border-t border-slate-100 pt-4 text-sm">
            <dt className="text-slate-500">订单编号</dt><dd className="text-right font-mono">#{o.order_id}</dd>
            <dt className="text-slate-500">买家</dt><dd className="text-right">{o.buyer_name}</dd>
            <dt className="text-slate-500">卖家</dt><dd className="text-right">{o.seller_name}</dd>
            <dt className="text-slate-500">下单时间</dt><dd className="text-right">{fmtTime(o.created_at, true)}</dd>
            <dt className="text-slate-500">付款截止</dt><dd className="text-right">{fmtTime(o.payment_deadline_at, true)}</dd>
            {o.auto_complete_at && <><dt className="text-slate-500">自动完成</dt><dd className="text-right">{fmtTime(o.auto_complete_at, true)}</dd></>}
            {o.completion_method && <><dt className="text-slate-500">完成方式</dt><dd className="text-right">{o.completion_method === "AUTO" ? "超时自动完成" : "买家确认收货"}</dd></>}
          </dl>
        </div>

        <div className="space-y-5">
          <div className="card space-y-2.5 p-5">
            <p className="mb-1 font-semibold text-slate-900">操作</p>
            {buyer && o.status === "PENDING_PAYMENT" && !pay?.expired && (
              <>
                <button className="btn-primary w-full py-3" disabled={!!busy} onClick={() => act("pay", "付款成功，积分已进入平台托管")}><CreditCard className="size-4" />确认付款 {o.price_snapshot_points} 积分</button>
                <button className="btn-secondary w-full" disabled={!!busy} onClick={() => setConfirm({ action: "cancel", title: "取消订单", text: "取消后商品立即重新开放购买，不扣积分。" })}>取消订单</button>
              </>
            )}
            {buyer && o.status === "PENDING_DELIVERY" && (
              <button className="btn-secondary w-full" disabled={!!busy} onClick={() => setConfirm({ action: "request-cancel", title: "申请取消订单", text: "订单将进入待核实，由管理员听取双方意见后决定是否原额退款。", danger: true })}><Undo2 className="size-4" />申请取消</button>
            )}
            {buyer && o.status === "PENDING_RECEIPT" && (
              <>
                <button className="btn-primary w-full py-3" disabled={!!busy} onClick={() => setConfirm({ action: "confirm", title: "确认收货", text: `确认后 ${o.price_snapshot_points} 积分将从托管转给卖家，此操作不可撤销。` })}><Check className="size-4" />确认收货</button>
                <button className="btn-danger w-full" disabled={!!busy} onClick={() => setConfirm({ action: "not-received", title: "反馈未收到商品", text: "订单将暂停自动完成并交由管理员核实，积分继续托管。", danger: true })}><AlertTriangle className="size-4" />未收到商品</button>
              </>
            )}
            {seller && o.status === "PENDING_DELIVERY" && (
              <button className="btn-primary w-full py-3" disabled={!!busy} onClick={() => act("deliver", "已标记交付，等待买家确认收货")}><Truck className="size-4" />已交付</button>
            )}
            {!((buyer && ["PENDING_PAYMENT", "PENDING_DELIVERY", "PENDING_RECEIPT"].includes(o.status) && !(o.status === "PENDING_PAYMENT" && pay?.expired)) || (seller && o.status === "PENDING_DELIVERY")) && (
              <p className="text-sm text-slate-500">当前没有需要你处理的操作。</p>
            )}
          </div>

          <div className="card p-5">
            <p className="mb-3 flex items-center gap-1.5 font-semibold text-slate-900"><ShieldCheck className="size-4 text-emerald-500" />资金流向</p>
            {o.transfers.length === 0 ? <p className="text-sm text-slate-500">尚未付款，没有积分变动。</p> : (
              <ul className="space-y-2 text-sm">
                {o.transfers.map((t, i) => (
                  <li key={i} className="flex items-center justify-between">
                    <span className="text-slate-600">
                      <span className="chip mr-2 bg-slate-100 text-slate-600">{LEDGER_EVENT[t.event_type]}</span>
                      {t.owner_type === "PLATFORM_ESCROW" ? "平台托管" : t.user_id === o.buyer_id ? "买家" : "卖家"}
                    </span>
                    <span className={`font-semibold tabular-nums ${t.delta_points > 0 ? "text-emerald-600" : "text-slate-500"}`}>{t.delta_points > 0 ? "+" : ""}{t.delta_points}</span>
                  </li>
                ))}
              </ul>
            )}
            <p className="mt-3 text-xs text-slate-400">每次转移恰好两条流水且合计为 0，由数据库触发器在提交时校验。</p>
          </div>

          {o.reviews.length > 0 && (
            <div className="card p-5">
              <p className="mb-3 font-semibold text-slate-900">核实记录</p>
              <ul className="space-y-2 text-sm">
                {o.reviews.map((r) => (
                  <li key={r.review_id} className="rounded-xl bg-slate-50 p-3">
                    <p className="font-medium text-slate-700">{REVIEW_REASON[r.reason]}</p>
                    <p className="text-xs text-slate-500">{fmtTime(r.opened_at)} 提交 · {r.decision ? `${fmtTime(r.resolved_at)} 处理：${r.decision === "CANCEL" ? "取消并退款" : "继续交易"}` : "处理中"}</p>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </div>

      <Modal open={!!confirm} onClose={() => setConfirm(null)} title={confirm?.title ?? ""} footer={
        <>
          <button className="btn-secondary" onClick={() => setConfirm(null)}>取消</button>
          <button className={confirm?.danger ? "btn-danger" : "btn-primary"} disabled={!!busy} onClick={() => confirm && act(confirm.action, "操作成功")}>确定</button>
        </>
      }>
        <p className="text-sm text-slate-600">{confirm?.text}</p>
      </Modal>
    </div>
  );
}
