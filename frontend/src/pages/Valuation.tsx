import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { History, Sparkles, Trash2 } from "lucide-react";
import { del, get, post, type Category, type Valuation } from "../api";
import { useAuth } from "../auth";
import { CONDITION_LABEL, Empty, Points, SectionTitle, fmtTime, useAction } from "../ui";
import { ConditionPicker, EstimatePanel, useEstimate } from "./Sell";

interface MarketRow { category_id: number; name: string; deals_180d: number; avg_deal_points: number | null; avg_deal_ratio: number | null; on_sale_count: number }

export default function ValuationPage() {
  const { me } = useAuth();
  const [params] = useSearchParams();
  const [categories, setCategories] = useState<Category[]>([]);
  const [market, setMarket] = useState<MarketRow[]>([]);
  const [history, setHistory] = useState<Valuation[]>([]);
  const [name, setName] = useState(params.get("name") ?? "");
  const [category, setCategory] = useState(params.get("category") ?? "");
  const [condition, setCondition] = useState(Number(params.get("condition") ?? 4));
  const [original, setOriginal] = useState(params.get("original") ?? "");
  const { est, loading } = useEstimate(category, condition, original);
  const { busy, run } = useAction();

  useEffect(() => {
    get<Category[]>("/categories").then(setCategories);
    get<MarketRow[]>("/market/categories").then(setMarket);
  }, []);
  useEffect(() => { if (me) get<Valuation[]>("/me/valuations").then(setHistory); }, [me]);

  const save = () => run("save", async () => {
    const v = await post<Valuation>("/valuations", { category_id: Number(category), item_name: name, condition_level: condition, original_price: Number(original) });
    setHistory((h) => [v, ...h]);
  }, "已保存到估价记录");

  const maxRatio = Math.max(0.01, ...market.map((m) => m.avg_deal_ratio ?? 0));

  return (
    <div className="animate-fade-up space-y-6">
      <SectionTitle title="智能估价" desc="根据平台真实成交数据与成色，估算二手物品的合理售价" />
      <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <div className="card space-y-5 p-6">
          <div>
            <label className="label">物品名称</label>
            <input className="input" value={name} maxLength={60} onChange={(e) => setName(e.target.value)} placeholder="例如：AirPods Pro 二代" />
          </div>
          <div className="grid gap-5 sm:grid-cols-2">
            <div>
              <label className="label">分类</label>
              <select className="input" value={category} onChange={(e) => setCategory(e.target.value)}>
                <option value="">请选择</option>
                {categories.map((c) => <option key={c.category_id} value={c.category_id}>{c.name}</option>)}
              </select>
            </div>
            <div>
              <label className="label">购入原价（积分）</label>
              <input className="input" type="number" min={1} value={original} onChange={(e) => setOriginal(e.target.value)} placeholder="0" />
            </div>
          </div>
          <div>
            <label className="label">成色</label>
            <ConditionPicker value={condition} onChange={setCondition} />
          </div>
          <div className="rounded-xl bg-slate-50 p-4 text-xs leading-relaxed text-slate-500">
            <p className="mb-1 font-semibold text-slate-600">估价方法（数据库函数 hxy.estimate_price）</p>
            取同分类近 180 天已完成订单的"成交价 ÷ 原价"，按成色折算后取中位数；样本越多越相信市场：
            权重 = 样本数 ÷ (样本数 + 5)，其余部分使用成色经验折旧率（九成新 70%、八成新 55%…）。
          </div>
          <div className="flex justify-end">
            {me ? (
              <button className="btn-primary" disabled={!est || !name.trim() || busy === "save"} onClick={save}><Sparkles className="size-4" />保存估价结果</button>
            ) : (
              <Link to="/login?next=/valuation" className="btn-secondary">登录后可保存估价记录</Link>
            )}
          </div>
        </div>

        <div className="space-y-4">
          <EstimatePanel est={est} loading={loading} />
          <div className="card p-5">
            <p className="mb-4 font-semibold text-slate-900">分类行情 <span className="text-xs font-normal text-slate-400">近 180 天平均成交折扣</span></p>
            <div className="space-y-3">
              {market.map((m) => (
                <div key={m.category_id}>
                  <div className="flex justify-between text-xs"><span className="font-medium text-slate-600">{m.name}</span><span className="text-slate-400">{m.deals_180d ? `${Math.round((m.avg_deal_ratio ?? 0) * 100)}% · ${m.deals_180d} 笔` : "暂无成交"}</span></div>
                  <div className="mt-1 h-2 overflow-hidden rounded-full bg-slate-100">
                    <div className="h-full rounded-full bg-gradient-to-r from-brand-400 to-indigo-500" style={{ width: `${((m.avg_deal_ratio ?? 0) / maxRatio) * 100}%` }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {me && (
        <div>
          <h2 className="mb-3 flex items-center gap-2 text-lg font-semibold text-slate-900"><History className="size-5 text-slate-400" />我的估价记录</h2>
          {history.length === 0 ? <Empty title="还没有估价记录" hint="估价后点击“保存估价结果”" /> : (
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {history.map((v) => (
                <div key={v.valuation_id} className="card group p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="font-semibold text-slate-800">{v.item_name}</p>
                      <p className="text-xs text-slate-500">{v.category_name} · {CONDITION_LABEL[v.condition_level]} · 原价 {v.original_price_points}</p>
                    </div>
                    <button className="rounded-lg p-1.5 text-slate-300 transition hover:bg-rose-50 hover:text-rose-500" title="删除"
                      onClick={() => run("del" + v.valuation_id, async () => { await del(`/valuations/${v.valuation_id}`); setHistory((h) => h.filter((x) => x.valuation_id !== v.valuation_id)); }, "已删除")}>
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                  <div className="mt-3 flex items-end justify-between">
                    <Points value={v.suggested_price_points} />
                    <span className="text-xs text-slate-400">{v.low_price_points}~{v.high_price_points} · {fmtTime(v.created_at)}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
