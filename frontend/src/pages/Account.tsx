import { useEffect, useState } from "react";
import { Link } from "react-router";
import { Award, Coins, KeyRound, Lock, ShieldCheck } from "lucide-react";
import { get, post, put, type LedgerRow, type Me } from "../api";
import { useAuth } from "../auth";
import { LEDGER_EVENT, Modal, SectionTitle, StatCard, fmtTime, useAction } from "../ui";

export default function AccountPage() {
  const { me, refresh, setMe } = useAuth();
  const [ledger, setLedger] = useState<LedgerRow[] | null>(null);
  const [pwOpen, setPwOpen] = useState(false);
  const [pw, setPw] = useState({ old_password: "", new_password: "" });
  const [name, setName] = useState(me?.display_name ?? "");
  const { busy, run } = useAction();
  useEffect(() => { refresh(); get<LedgerRow[]>("/me/ledger").then(setLedger); }, [refresh]);
  if (!me) return null;

  return (
    <div className="animate-fade-up space-y-6">
      <SectionTitle title="我的账户" desc={`学号 ${me.student_no} · 注册于 ${fmtTime(me.created_at, true).slice(0, 10)}`} right={
        <button className="btn-secondary" onClick={() => setPwOpen(true)}><KeyRound className="size-4" />修改密码</button>
      } />

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="可用积分" value={me.spendable_points.toLocaleString()} hint="可用于购买商品" icon={<Coins className="size-4" />} />
        <StatCard label="托管中" value={me.escrow_points.toLocaleString()} hint="已付款、交易完成前由平台保管" tone="amber" icon={<Lock className="size-4" />} />
        <StatCard label="买家奖励分" value={me.buyer_reward_points} hint={me.pending_reward_points ? `另有 ${me.pending_reward_points} 分待生效` : "每完成一笔购买 +1"} tone="violet" icon={<Award className="size-4" />} />
        <StatCard label="卖家信誉" value={<>{me.seller_reputation}<span className="text-sm font-medium text-slate-400"> / 100</span></>} hint={`已完成 ${me.completed_sales} 笔销售`} tone="emerald" icon={<ShieldCheck className="size-4" />} />
      </div>

      <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
        <div className="card overflow-hidden">
          <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
            <h2 className="font-semibold text-slate-900">积分流水</h2>
            <span className="text-xs text-slate-400">balance_ledger · 只追加不可修改</span>
          </div>
          {!ledger ? null : ledger.length === 0 ? <p className="p-6 text-sm text-slate-500">暂无流水</p> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-left text-xs text-slate-500">
                  <tr><th className="px-5 py-2.5 font-medium">时间</th><th className="px-3 py-2.5 font-medium">类型</th><th className="px-3 py-2.5 font-medium">关联</th><th className="px-5 py-2.5 text-right font-medium">变动</th></tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {ledger.map((r) => (
                    <tr key={r.ledger_id} className="hover:bg-slate-50/60">
                      <td className="whitespace-nowrap px-5 py-3 text-slate-500">{fmtTime(r.occurred_at)}</td>
                      <td className="px-3 py-3"><span className="chip bg-slate-100 text-slate-600">{LEDGER_EVENT[r.event_type]}</span></td>
                      <td className="max-w-[16rem] truncate px-3 py-3 text-slate-600">{r.order_id ? <Link to={`/orders/${r.order_id}`} className="hover:text-brand-600">#{r.order_id} {r.listing_title}</Link> : "—"}</td>
                      <td className={`px-5 py-3 text-right font-semibold tabular-nums ${r.delta_points > 0 ? "text-emerald-600" : "text-slate-700"}`}>{r.delta_points > 0 ? "+" : ""}{r.delta_points}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div className="card h-fit space-y-4 p-5">
          <h2 className="font-semibold text-slate-900">个人资料</h2>
          <div>
            <label className="label">昵称</label>
            <div className="flex gap-2">
              <input className="input" value={name} maxLength={40} onChange={(e) => setName(e.target.value)} />
              <button className="btn-primary shrink-0" disabled={busy === "name" || !name.trim() || name === me.display_name}
                onClick={() => run("name", async () => setMe(await put<Me>("/me/profile", { display_name: name })), "昵称已更新")}>保存</button>
            </div>
          </div>
          <div className="rounded-xl bg-slate-50 p-4 text-xs leading-relaxed text-slate-500">
            积分仅用于校园内模拟交易，注册即发放 500 积分。所有账户余额之和恒为 0（发行账户为负），每一分钱都可由流水追溯。
          </div>
        </div>
      </div>

      <Modal open={pwOpen} onClose={() => setPwOpen(false)} title="修改密码" footer={
        <>
          <button className="btn-secondary" onClick={() => setPwOpen(false)}>取消</button>
          <button className="btn-primary" disabled={busy === "pw" || pw.new_password.length < 6} onClick={() =>
            run("pw", async () => { await post("/me/password", pw); setPwOpen(false); setPw({ old_password: "", new_password: "" }); }, "密码已修改")}>确认修改</button>
        </>
      }>
        <div className="space-y-3">
          <div><label className="label">原密码</label><input type="password" className="input" value={pw.old_password} onChange={(e) => setPw({ ...pw, old_password: e.target.value })} /></div>
          <div><label className="label">新密码（至少 6 位）</label><input type="password" className="input" value={pw.new_password} onChange={(e) => setPw({ ...pw, new_password: e.target.value })} /></div>
        </div>
      </Modal>
    </div>
  );
}
