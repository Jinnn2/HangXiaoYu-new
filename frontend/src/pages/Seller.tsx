import { useEffect, useState } from "react";
import { useParams } from "react-router";
import { ShieldCheck } from "lucide-react";
import { get, type Listing } from "../api";
import ListingCard from "../ListingCard";
import { Empty, PageLoading, fmtTime } from "../ui";

interface Profile { user_id: number; display_name: string; created_at: string; reputation: number; completed_sales: number; listings: Listing[] }

export default function SellerPage() {
  const { id } = useParams();
  const [p, setP] = useState<Profile | null>(null);
  const [error, setError] = useState("");
  useEffect(() => { get<Profile>(`/users/${id}`).then(setP).catch((e) => setError(e.message)); }, [id]);
  if (error) return <div className="py-24 text-center text-slate-500">{error}</div>;
  if (!p) return <PageLoading />;
  return (
    <div className="animate-fade-up space-y-6">
      <div className="card flex flex-wrap items-center gap-5 p-6">
        <span className="grid size-16 place-items-center rounded-2xl bg-gradient-to-br from-brand-400 to-indigo-500 text-2xl font-bold text-white">{p.display_name.slice(0, 1)}</span>
        <div className="flex-1">
          <h1 className="text-xl font-bold text-slate-900">{p.display_name}</h1>
          <p className="text-sm text-slate-500">{fmtTime(p.created_at, true).slice(0, 10)} 加入 · 已完成 {p.completed_sales} 笔销售</p>
        </div>
        <div className="w-full max-w-xs">
          <div className="flex items-center justify-between text-sm"><span className="flex items-center gap-1 font-medium text-emerald-700"><ShieldCheck className="size-4" />卖家信誉</span><span className="font-bold tabular-nums">{p.reputation} / 100</span></div>
          <div className="mt-2 h-2 overflow-hidden rounded-full bg-slate-100"><div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-emerald-500" style={{ width: `${p.reputation}%` }} /></div>
          <p className="mt-1.5 text-xs text-slate-400">初始 80 分；每完成一单 +1，核实超时未交付 −10</p>
        </div>
      </div>
      <h2 className="text-lg font-semibold text-slate-900">在售商品 <span className="text-sm font-normal text-slate-400">{p.listings.length}</span></h2>
      {p.listings.length === 0 ? <Empty title="暂无在售商品" /> : (
        <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 xl:grid-cols-4">
          {p.listings.map((i) => <ListingCard key={i.listing_id} item={i} />)}
        </div>
      )}
    </div>
  );
}
