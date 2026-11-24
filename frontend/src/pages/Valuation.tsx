import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { History, Sparkles, Store, Trash2 } from "lucide-react";
import { del, get, post, type Category, type Valuation } from "../api";
import { useAuth } from "../auth";
import { CONDITION_LABEL, Empty, Points, SectionTitle, fmtTime, timeAgo, useAction } from "../ui";
import { PriceTimeline } from "../charts";
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
  const { est, loading } = useEstimate(category, condition, original, name);
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
            像饰品交易市场一样先看<b>同款</b>：名称相似的近 180 天成交，按成色折算后取中位数，权重 = 同款笔数 ÷ (笔数 + 2)；
            没有同款时看<b>同分类</b>的"成交价 ÷ 原价"，权重 = 笔数 ÷ (笔数 + 5)；其余部分用成色经验折旧率（九成新 70%、八成新 55%…）。
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

      {est && (
        <div className="grid gap-6 lg:grid-cols-[1.6fr_1fr]">
          <div className="card p-5">
            <h2 className="font-semibold text-slate-900">近期成交记录</h2>
            <p className="mb-4 text-xs text-slate-400">同分类近 180 天的真实成交；价格已按成色折算到「{CONDITION_LABEL[condition]}」，便于比较</p>
            {est.samples.length === 0 ? <Empty title="该分类近 180 天还没有成交" /> : (
              <>
                <PriceTimeline
                  points={est.samples.map((x) => ({ t: x.completed_at, value: Math.round(x.adjusted_price), highlight: x.same_item, label: x.title }))}
                  reference={{ value: est.suggested_price_points, label: "建议价" }} />
                <div className="mt-4 max-h-72 overflow-auto rounded-xl border border-slate-100">
                  <table className="w-full text-sm">
                    <thead className="sticky top-0 bg-slate-50 text-left text-xs text-slate-500">
                      <tr><th className="px-3 py-2 font-medium">商品</th><th className="px-3 py-2 font-medium">成色</th><th className="px-3 py-2 text-right font-medium">成交价</th><th className="px-3 py-2 text-right font-medium">折算价</th><th className="px-3 py-2 text-right font-medium">时间</th></tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {est.samples.map((x) => (
                        <tr key={x.order_id} className={x.same_item ? "bg-brand-50/40" : ""}>
                          <td className="max-w-[14rem] px-3 py-2">
                            <span className="flex items-center gap-1.5">
                              {x.same_item && <span className="chip shrink-0 bg-brand-100 text-brand-700">同款</span>}
                              <span className="truncate text-slate-700">{x.title}</span>
                            </span>
                          </td>
                          <td className="whitespace-nowrap px-3 py-2 text-slate-500">{CONDITION_LABEL[x.condition_level]}</td>
                          <td className="px-3 py-2 text-right tabular-nums text-slate-700">{x.price_points}</td>
                          <td className="px-3 py-2 text-right font-semibold tabular-nums text-slate-800">{Math.round(x.adjusted_price)}</td>
                          <td className="whitespace-nowrap px-3 py-2 text-right text-xs text-slate-400">{timeAgo(x.completed_at)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            )}
          </div>
          <div className="card h-fit p-5">
            <h2 className="flex items-center gap-2 font-semibold text-slate-900"><Store className="size-4 text-slate-400" />同款在售</h2>
            <p className="mb-3 text-xs text-slate-400">名称相似的在售商品，按价格从低到高</p>
            {est.listings.length === 0 ? (
              <p className="py-6 text-center text-sm text-slate-500">{name.trim() ? "暂无同款在售" : "填写物品名称后显示同款在售"}</p>
            ) : (
              <ul className="-mx-2 divide-y divide-slate-100">
                {est.listings.map((l) => (
                  <li key={l.listing_id}>
                    <Link to={`/listings/${l.listing_id}`} className="flex items-center justify-between gap-3 rounded-lg px-2 py-2.5 hover:bg-slate-50">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium text-slate-700">{l.title}</p>
                        <p className="text-xs text-slate-400">{CONDITION_LABEL[l.condition_level]} · {timeAgo(l.created_at)}发布</p>
                      </div>
                      <Points value={l.current_price_points} size="sm" />
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}

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
                      <span className="chip mt-1.5 bg-slate-100 text-slate-600">{v.basis === "SAME_ITEM" ? `同款 ${v.sample_count} 笔` : v.basis === "CATEGORY" ? `同分类 ${v.sample_count} 笔` : "成色经验"}</span>
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
