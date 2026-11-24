import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { ArrowRight, SearchX, Sparkles, TrendingUp } from "lucide-react";
import { get, type Category, type Listing } from "../api";
import ListingCard from "../ListingCard";
import { Empty, Spinner } from "../ui";

interface MarketRow { category_id: number; name: string; deals_180d: number; avg_deal_ratio: number | null; on_sale_count: number }

const SORTS = [
  { v: "new", label: "最新发布" },
  { v: "popular", label: "最多收藏" },
  { v: "price_asc", label: "价格从低到高" },
  { v: "price_desc", label: "价格从高到低" },
];

export default function Home() {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const category = params.get("category") ?? "";
  const sort = params.get("sort") ?? "new";
  const [categories, setCategories] = useState<Category[]>([]);
  const [market, setMarket] = useState<MarketRow[]>([]);
  const [data, setData] = useState<{ items: Listing[]; total: number } | null>(null);
  const [page, setPage] = useState(1);

  useEffect(() => {
    get<Category[]>("/categories").then(setCategories);
    get<MarketRow[]>("/market/categories").then(setMarket);
  }, []);

  useEffect(() => { setPage(1); }, [q, category, sort]);

  useEffect(() => {
    const sp = new URLSearchParams({ sort, page: String(page), page_size: "12" });
    if (q) sp.set("q", q);
    if (category) sp.set("category_id", category);
    get<{ items: Listing[]; total: number }>(`/listings?${sp}`).then((r) =>
      setData((prev) => (page > 1 && prev ? { items: [...prev.items, ...r.items], total: r.total } : r)));
  }, [q, category, sort, page]);

  const setParam = (k: string, v: string) => {
    const next = new URLSearchParams(params);
    if (v) next.set(k, v); else next.delete(k);
    setParams(next);
  };
  const onSale = market.reduce((s, m) => s + m.on_sale_count, 0);
  const deals = market.reduce((s, m) => s + m.deals_180d, 0);

  return (
    <div className="space-y-8">
      {!q && (
        <section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-brand-600 via-indigo-600 to-violet-600 px-6 py-10 text-white shadow-lift sm:px-10 sm:py-12">
          <div className="absolute -right-16 -top-20 size-72 rounded-full bg-white/10 blur-2xl" />
          <div className="absolute -bottom-24 right-40 size-64 rounded-full bg-sky-300/20 blur-3xl" />
          <div className="relative grid items-center gap-8 lg:grid-cols-[1.4fr_1fr]">
            <div>
              <span className="chip bg-white/15 text-white ring-1 ring-white/20 backdrop-blur"><Sparkles className="size-3" />基于真实成交数据的智能估价</span>
              <h1 className="mt-4 text-3xl font-extrabold leading-tight tracking-tight sm:text-4xl">让闲置在校园里<br className="hidden sm:block" />找到下一个主人</h1>
              <p className="mt-3 max-w-lg text-sm text-white/80 sm:text-base">积分托管交易，确认收货后才转给卖家；不确定定价？先估个价再发布。</p>
              <div className="mt-6 flex flex-wrap gap-3">
                <Link to="/sell" className="btn bg-white text-brand-700 shadow-sm hover:bg-brand-50">发布闲置<ArrowRight className="size-4" /></Link>
                <Link to="/valuation" className="btn bg-white/10 text-white ring-1 ring-white/30 hover:bg-white/20">先估个价</Link>
              </div>
            </div>
            <div className="hidden grid-cols-2 gap-3 sm:grid">
              {[
                { label: "在售商品", value: onSale },
                { label: "近半年成交", value: deals },
                { label: "商品分类", value: categories.length },
                { label: "托管交易保障", value: "100%" },
              ].map((s) => (
                <div key={s.label} className="rounded-2xl bg-white/10 p-4 ring-1 ring-white/15 backdrop-blur">
                  <div className="text-2xl font-bold tabular-nums">{s.value}</div>
                  <div className="mt-0.5 text-xs text-white/70">{s.label}</div>
                </div>
              ))}
            </div>
          </div>
        </section>
      )}

      <section>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="-mx-1 flex w-full min-w-0 gap-2 overflow-x-auto px-1 pb-1 sm:w-auto sm:flex-1">
            <button onClick={() => setParam("category", "")} className={`shrink-0 rounded-full px-4 py-2 text-sm font-medium transition ${!category ? "bg-slate-900 text-white" : "bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50"}`}>全部</button>
            {categories.map((c) => {
              const m = market.find((x) => x.category_id === c.category_id);
              const active = category === String(c.category_id);
              return (
                <button key={c.category_id} onClick={() => setParam("category", String(c.category_id))} className={`shrink-0 rounded-full px-4 py-2 text-sm font-medium transition ${active ? "bg-slate-900 text-white" : "bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50"}`}>
                  {c.name}{m && m.on_sale_count > 0 && <span className={`ml-1.5 text-xs ${active ? "text-white/60" : "text-slate-400"}`}>{m.on_sale_count}</span>}
                </button>
              );
            })}
          </div>
          <select value={sort} onChange={(e) => setParam("sort", e.target.value)} className="input ml-auto w-auto rounded-full py-2">
            {SORTS.map((s) => <option key={s.v} value={s.v}>{s.label}</option>)}
          </select>
        </div>

        {q && (
          <p className="mt-4 text-sm text-slate-500">
            “<span className="font-semibold text-slate-800">{q}</span>” 的搜索结果，共 {data?.total ?? 0} 件
            <button className="ml-2 text-brand-600 hover:underline" onClick={() => setParam("q", "")}>清除</button>
          </p>
        )}

        {category && (() => {
          const m = market.find((x) => String(x.category_id) === category);
          return m && m.deals_180d > 0 ? (
            <div className="mt-4 flex items-center gap-2 rounded-xl bg-emerald-50 px-4 py-2.5 text-sm text-emerald-800">
              <TrendingUp className="size-4" />
              {m.name} 近半年成交 {m.deals_180d} 笔，平均成交价约为原价的 {Math.round((m.avg_deal_ratio ?? 0) * 100)}%
            </div>
          ) : null;
        })()}

        <div className="mt-5">
          {data === null ? (
            <div className="flex h-60 items-center justify-center"><Spinner className="size-7" /></div>
          ) : data.items.length === 0 ? (
            <Empty icon={<SearchX className="size-6" />} title="没有找到相关商品" hint="换个关键词或分类试试" />
          ) : (
            <>
              <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 xl:grid-cols-4">
                {data.items.map((item, i) => (
                  <div key={item.listing_id} className="animate-fade-up" style={{ animationDelay: `${(i % 12) * 30}ms` }}>
                    <ListingCard item={item} />
                  </div>
                ))}
              </div>
              {data.items.length < data.total && (
                <div className="mt-8 text-center">
                  <button className="btn-secondary px-8" onClick={() => setPage((p) => p + 1)}>加载更多</button>
                </div>
              )}
            </>
          )}
        </div>
      </section>
    </div>
  );
}
