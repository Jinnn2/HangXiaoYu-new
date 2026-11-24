import { useEffect, useState } from "react";
import { Link } from "react-router";
import { Heart } from "lucide-react";
import { get, type Listing } from "../api";
import ListingCard from "../ListingCard";
import { Empty, PageLoading, SectionTitle } from "../ui";

export default function FavoritesPage() {
  const [items, setItems] = useState<Listing[] | null>(null);
  useEffect(() => { get<Listing[]>("/me/favorites").then(setItems); }, []);
  if (!items) return <PageLoading />;
  return (
    <div className="animate-fade-up">
      <SectionTitle title="我的收藏" desc={`${items.length} 件商品`} />
      {items.length === 0 ? (
        <Empty icon={<Heart className="size-6" />} title="还没有收藏" hint="在商品页点击爱心即可收藏" action={<Link to="/" className="btn-primary">去逛逛</Link>} />
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 xl:grid-cols-4">
          {items.map((i) => <ListingCard key={i.listing_id} item={i} showStatus />)}
        </div>
      )}
    </div>
  );
}
