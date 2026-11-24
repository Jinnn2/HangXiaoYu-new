import { useEffect, useState } from "react";
import { Link } from "react-router";
import { Package, Pencil, Plus } from "lucide-react";
import { get, type Listing } from "../api";
import { CONDITION_LABEL, Cover, Empty, ListingStatusBadge, PageLoading, Points, SectionTitle, fmtTime } from "../ui";

const TABS = [
  { key: "all", label: "全部", match: () => true },
  { key: "sale", label: "在售", match: (l: Listing) => l.status === "ON_SALE" },
  { key: "trading", label: "交易中", match: (l: Listing) => l.status === "PAYMENT_RESERVED" || l.status === "TRADING" },
  { key: "sold", label: "已售出", match: (l: Listing) => l.status === "SOLD" },
  { key: "off", label: "下架 / 缓冲期", match: (l: Listing) => l.status === "OFF_SHELF" || l.status === "RELIST_BUFFER" },
];

export default function MyListings() {
  const [items, setItems] = useState<Listing[] | null>(null);
  const [tab, setTab] = useState("all");
  useEffect(() => { get<Listing[]>("/me/listings").then(setItems); }, []);
  if (!items) return <PageLoading />;
  const current = TABS.find((t) => t.key === tab)!;
  const shown = items.filter(current.match);

  return (
    <div className="animate-fade-up">
      <SectionTitle title="我的商品" desc={`共 ${items.length} 件`} right={<Link to="/sell" className="btn-primary"><Plus className="size-4" />发布闲置</Link>} />
      <div className="mb-5 inline-flex rounded-full bg-slate-100 p-1">
        {TABS.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)} className={`rounded-full px-4 py-1.5 text-sm font-medium transition ${tab === t.key ? "bg-white text-slate-900 shadow-sm" : "text-slate-500 hover:text-slate-700"}`}>
            {t.label}<span className="ml-1 text-xs text-slate-400">{items.filter(t.match).length}</span>
          </button>
        ))}
      </div>
      {shown.length === 0 ? (
        <Empty icon={<Package className="size-6" />} title="这里还没有商品" action={<Link to="/sell" className="btn-primary">发布第一件闲置</Link>} />
      ) : (
        <div className="card divide-y divide-slate-100">
          {shown.map((l) => (
            <div key={l.listing_id} className="flex items-center gap-4 p-4">
              <Link to={`/listings/${l.listing_id}`} className="shrink-0">
                <Cover title={l.title} category={l.category_name} imageUrl={l.image_url} className="size-16 rounded-xl sm:size-20" small />
              </Link>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Link to={`/listings/${l.listing_id}`} className="truncate font-semibold text-slate-800 hover:text-brand-700">{l.title}</Link>
                  <ListingStatusBadge status={l.status} />
                </div>
                <p className="mt-1 text-xs text-slate-500">{l.category_name} · {CONDITION_LABEL[l.condition_level]} · {l.favorite_count} 人收藏 · 更新于 {fmtTime(l.updated_at)}</p>
                {l.status === "RELIST_BUFFER" && (
                  <p className="mt-1 text-xs text-violet-600">订单已取消退款，{l.last_canceled_at ? `将于 ${fmtTime(new Date(new Date(l.last_canceled_at).getTime() + 86400000).toISOString())} ` : ""}自动恢复在售，也可以现在手动选择。</p>
                )}
              </div>
              <div className="hidden text-right sm:block"><Points value={l.current_price_points} /></div>
              <Link to={`/sell/${l.listing_id}`} className="btn-secondary shrink-0 px-3"><Pencil className="size-4" /><span className="hidden sm:inline">管理</span></Link>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
