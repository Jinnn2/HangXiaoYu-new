import { Link } from "react-router";
import { Heart, ShieldCheck } from "lucide-react";
import type { Listing } from "./api";
import { CONDITION_LABEL, Cover, ListingStatusBadge, Points, timeAgo } from "./ui";

export default function ListingCard({ item, showStatus }: { item: Listing; showStatus?: boolean }) {
  const discount = item.original_price_points
    ? Math.round((item.current_price_points / item.original_price_points) * 100) / 10
    : null;
  return (
    <Link to={`/listings/${item.listing_id}`} className="group card flex flex-col overflow-hidden transition duration-200 hover:-translate-y-0.5 hover:shadow-lift">
      <div className="relative aspect-[4/3] overflow-hidden">
        <Cover title={item.title} category={item.category_name} imageUrl={item.image_url} className="size-full transition duration-500 group-hover:scale-105" />
        <div className="absolute left-2.5 top-2.5 flex gap-1.5">
          <span className="chip bg-white/90 text-slate-700 backdrop-blur">{item.category_name}</span>
          {showStatus && <ListingStatusBadge status={item.status} />}
        </div>
        {item.favorite_count > 0 && (
          <span className="chip absolute right-2.5 top-2.5 bg-black/30 text-white backdrop-blur">
            <Heart className="size-3 fill-current" />{item.favorite_count}
          </span>
        )}
      </div>
      <div className="flex flex-1 flex-col p-4">
        <h3 className="line-clamp-2 min-h-[2.5rem] text-[15px] font-semibold leading-snug text-slate-800 group-hover:text-brand-700">{item.title}</h3>
        <div className="mt-2 flex items-center gap-2">
          <Points value={item.current_price_points} />
          {discount !== null && discount < 10 && (
            <span className="text-xs text-slate-400"><s>{item.original_price_points}</s> · {discount} 折</span>
          )}
        </div>
        <div className="mt-auto flex items-center justify-between pt-3 text-xs text-slate-500">
          <span className="flex items-center gap-1.5">
            <span className="grid size-5 place-items-center rounded-full bg-slate-100 text-[10px] font-bold text-slate-600">{item.seller_name.slice(0, 1)}</span>
            {item.seller_name}
            <span className="flex items-center gap-0.5 text-emerald-600"><ShieldCheck className="size-3" />{item.seller_reputation}</span>
          </span>
          <span className="hidden sm:inline">{CONDITION_LABEL[item.condition_level]} · {timeAgo(item.created_at)}</span>
        </div>
      </div>
    </Link>
  );
}
