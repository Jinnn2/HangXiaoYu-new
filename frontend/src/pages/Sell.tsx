import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router";
import { ArrowDownToLine, ArrowUpFromLine, ImageIcon, Sparkles, Trash2, Wand2 } from "lucide-react";
import { del, get, post, put, type Category, type EstimateBasis, type ListingDetail, type MarketEstimate } from "../api";
import { CONDITION_LABEL, Cover, ListingStatusBadge, Modal, PageLoading, Points, SectionTitle, useAction } from "../ui";

interface Form {
  category_id: string;
  title: string;
  description: string;
  condition_level: number;
  original_price_points: string;
  current_price_points: string;
  image_url: string;
}

const EMPTY: Form = { category_id: "", title: "", description: "", condition_level: 4, original_price_points: "", current_price_points: "", image_url: "" };

export function useEstimate(categoryId: string, condition: number, original: string, name = "") {
  const [est, setEst] = useState<MarketEstimate | null>(null);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    const price = Number(original);
    if (!categoryId || !price || price <= 0) { setEst(null); return; }
    setLoading(true);
    const t = setTimeout(() => {
      post<MarketEstimate>("/valuations/estimate", {
        category_id: Number(categoryId), condition_level: condition, original_price: price, item_name: name.trim() || null,
      }).then(setEst).catch(() => setEst(null)).finally(() => setLoading(false));
    }, 350);
    return () => clearTimeout(t);
  }, [categoryId, condition, original, name]);
  return { est, loading };
}

export function ConditionPicker({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return (
    <div className="grid grid-cols-5 gap-2">
      {[5, 4, 3, 2, 1].map((c) => (
        <button type="button" key={c} onClick={() => onChange(c)} className={`rounded-xl border px-1 py-2.5 text-xs font-medium transition sm:text-sm ${value === c ? "border-brand-400 bg-brand-50 text-brand-700 ring-4 ring-brand-100" : "border-slate-200 bg-white text-slate-600 hover:border-slate-300"}`}>
          {CONDITION_LABEL[c]}
        </button>
      ))}
    </div>
  );
}

const BASIS: Record<EstimateBasis, { text: (e: MarketEstimate) => string; cls: string }> = {
  SAME_ITEM: { text: (e) => `按 ${e.same_item_count} 笔同款成交估价`, cls: "bg-emerald-50 text-emerald-700" },
  CATEGORY: { text: (e) => `同款成交不足，参考同分类 ${e.sample_count} 笔成交`, cls: "bg-sky-50 text-sky-700" },
  DEFAULT: { text: () => "暂无成交，按成色折旧经验估算", cls: "bg-slate-100 text-slate-600" },
};

export function EstimatePanel({ est, loading, onUse, myPrice }: { est: MarketEstimate | null; loading: boolean; onUse?: (p: number) => void; myPrice?: number }) {
  const diff = myPrice && est?.listing_min ? Math.round(((myPrice - est.listing_min) / est.listing_min) * 100) : null;
  return (
    <div className="card overflow-hidden">
      <div className="bg-gradient-to-br from-brand-500 via-indigo-500 to-violet-500 px-5 py-4 text-white">
        <p className="flex items-center gap-1.5 text-sm font-semibold"><Sparkles className="size-4" />智能估价</p>
        <p className="mt-0.5 text-xs text-white/75">先比同款成交，再看同分类，最后按成色经验估算</p>
      </div>
      <div className="p-5">
        {!est ? (
          <p className="text-sm text-slate-500">{loading ? "计算中…" : "填写名称、分类、成色和原价后自动给出建议价。"}</p>
        ) : (
          <div className={loading ? "opacity-50" : ""}>
            <span className={`chip mb-2 ${BASIS[est.basis].cls}`}>{BASIS[est.basis].text(est)}</span>
            <p className="text-xs text-slate-500">建议售价</p>
            <Points value={est.suggested_price_points} size="lg" />
            <div className="mt-3">
              <div className="flex justify-between text-xs text-slate-500"><span>{est.low_price_points}</span><span>合理区间</span><span>{est.high_price_points}</span></div>
              <div className="relative mt-1 h-2 rounded-full bg-gradient-to-r from-emerald-200 via-brand-300 to-amber-200">
                <div className="absolute top-1/2 size-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white bg-brand-600 shadow"
                  style={{ left: `${est.high_price_points === est.low_price_points ? 50 : ((est.suggested_price_points - est.low_price_points) / (est.high_price_points - est.low_price_points)) * 100}%` }} />
              </div>
            </div>
            <dl className="mt-4 grid grid-cols-2 gap-2 text-xs">
              <div className="rounded-lg bg-slate-50 p-2.5">
                <dt className="text-slate-500">同款成交中位价</dt>
                <dd className="mt-0.5 text-base font-semibold text-slate-800">{est.same_item_median ?? "—"}</dd>
              </div>
              <div className="rounded-lg bg-slate-50 p-2.5">
                <dt className="text-slate-500">同款在售最低价</dt>
                <dd className="mt-0.5 text-base font-semibold text-slate-800">{est.listing_min ?? "—"}{est.listing_count > 0 && <span className="ml-1 text-xs font-normal text-slate-400">共 {est.listing_count} 件</span>}</dd>
              </div>
            </dl>
            {diff !== null && (
              <p className={`mt-3 rounded-lg p-2.5 text-xs ${diff > 10 ? "bg-amber-50 text-amber-800" : "bg-emerald-50 text-emerald-800"}`}>
                你的定价比同款在售最低价{diff >= 0 ? `高 ${diff}%` : `低 ${-diff}%`}{diff > 10 ? "，可能不好卖" : "，有竞争力"}。
              </p>
            )}
            {onUse && <button type="button" className="btn-secondary mt-4 w-full" onClick={() => onUse(est.suggested_price_points)}><Wand2 className="size-4" />使用建议价</button>}
          </div>
        )}
      </div>
    </div>
  );
}

export default function SellPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [categories, setCategories] = useState<Category[]>([]);
  const [form, setForm] = useState<Form>(EMPTY);
  const [listing, setListing] = useState<ListingDetail | null>(null);
  const [newPrice, setNewPrice] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const { busy, run } = useAction();
  const { est, loading } = useEstimate(form.category_id, form.condition_level, form.original_price_points, form.title);

  useEffect(() => { get<Category[]>("/categories").then(setCategories); }, []);
  useEffect(() => {
    if (!id) { setListing(null); setForm(EMPTY); return; }
    get<ListingDetail>(`/listings/${id}`).then((l) => {
      setListing(l);
      setForm({
        category_id: String(l.category_id), title: l.title, description: l.description, condition_level: l.condition_level,
        original_price_points: l.original_price_points ? String(l.original_price_points) : "",
        current_price_points: String(l.current_price_points), image_url: l.image_url ?? "",
      });
    });
  }, [id]);

  if (id && !listing) return <PageLoading />;
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));
  const editable = !listing || ["ON_SALE", "OFF_SHELF", "RELIST_BUFFER"].includes(listing.status);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const body = {
      category_id: Number(form.category_id), title: form.title, description: form.description,
      condition_level: form.condition_level,
      original_price_points: form.original_price_points ? Number(form.original_price_points) : null,
      image_url: form.image_url || null,
    };
    if (listing) {
      run("save", async () => setListing(await put<ListingDetail>(`/listings/${listing.listing_id}`, body)), "已保存修改");
    } else {
      run("save", async () => {
        const l = await post<ListingDetail>("/listings", { ...body, current_price_points: Number(form.current_price_points) });
        navigate(`/listings/${l.listing_id}`);
      }, "发布成功");
    }
  };

  const action = (key: string, path: string, msg: string) =>
    run(key, async () => setListing(await post<ListingDetail>(`/listings/${listing!.listing_id}/${path}`)), msg);

  return (
    <div className="animate-fade-up">
      <SectionTitle title={listing ? "管理商品" : "发布闲置"} desc={listing ? `商品编号 ${listing.listing_id}` : "填写信息，参考智能估价定一个好卖的价格"}
        right={listing && <ListingStatusBadge status={listing.status} />} />
      <div className="grid gap-6 lg:grid-cols-[1.6fr_1fr]">
        <form onSubmit={submit} className="card space-y-5 p-6">
          <div>
            <label className="label">商品标题</label>
            <input className="input" required maxLength={60} value={form.title} onChange={(e) => set("title", e.target.value)} placeholder="品牌 + 型号 + 关键信息，例如：iPad 第九代 64G" disabled={!editable} />
          </div>
          <div className="grid gap-5 sm:grid-cols-2">
            <div>
              <label className="label">分类</label>
              <select className="input" required value={form.category_id} onChange={(e) => set("category_id", e.target.value)} disabled={!editable}>
                <option value="">请选择</option>
                {categories.map((c) => <option key={c.category_id} value={c.category_id}>{c.name}</option>)}
              </select>
            </div>
            <div>
              <label className="label">购入原价（积分，选填）</label>
              <input className="input" type="number" min={1} value={form.original_price_points} onChange={(e) => set("original_price_points", e.target.value)} placeholder="用于估价与折扣展示" disabled={!editable} />
            </div>
          </div>
          <div>
            <label className="label">成色</label>
            <ConditionPicker value={form.condition_level} onChange={(v) => editable && set("condition_level", v)} />
          </div>
          <div>
            <label className="label">描述</label>
            <textarea className="input min-h-32" maxLength={2000} value={form.description} onChange={(e) => set("description", e.target.value)} placeholder="使用时长、有无瑕疵、配件、交易地点…" disabled={!editable} />
          </div>
          <div>
            <label className="label">图片链接（选填）</label>
            <div className="relative">
              <ImageIcon className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
              <input className="input pl-10" value={form.image_url} onChange={(e) => set("image_url", e.target.value)} placeholder="https://… 不填则使用分类封面" disabled={!editable} />
            </div>
          </div>
          {!listing && (
            <div>
              <label className="label">售价（积分）</label>
              <input className="input text-lg font-semibold" type="number" min={1} required value={form.current_price_points} onChange={(e) => set("current_price_points", e.target.value)} placeholder="0" />
            </div>
          )}
          <div className="flex justify-end gap-2 border-t border-slate-100 pt-5">
            <button type="button" className="btn-ghost" onClick={() => navigate(-1)}>取消</button>
            <button className="btn-primary px-6" disabled={busy === "save" || !editable}>{listing ? "保存修改" : "立即发布"}</button>
          </div>
        </form>

        <div className="space-y-4 lg:sticky lg:top-24 lg:self-start">
          {form.title && form.category_id && (
            <div className="card overflow-hidden">
              <Cover title={form.title} category={categories.find((c) => String(c.category_id) === form.category_id)?.name ?? ""} imageUrl={form.image_url || null} className="aspect-[16/9] w-full" />
            </div>
          )}
          <EstimatePanel est={est} loading={loading} myPrice={Number(listing ? newPrice || listing.current_price_points : form.current_price_points) || undefined} onUse={listing ? (p) => setNewPrice(String(p)) : (p) => set("current_price_points", String(p))} />

          {listing && (
            <div className="card space-y-4 p-5">
              <div>
                <p className="text-sm text-slate-500">当前价格</p>
                <Points value={listing.current_price_points} size="lg" />
              </div>
              <div className="flex gap-2">
                <input className="input" type="number" min={1} value={newPrice} onChange={(e) => setNewPrice(e.target.value)} placeholder="新价格" />
                <button className="btn-primary shrink-0" disabled={!newPrice || busy === "reprice"} onClick={() =>
                  run("reprice", async () => { setListing(await post<ListingDetail>(`/listings/${listing.listing_id}/reprice`, { price: Number(newPrice) })); setNewPrice(""); }, "改价成功，已记录价格历史")}>改价</button>
              </div>
              <div className="grid grid-cols-2 gap-2 border-t border-slate-100 pt-4">
                {listing.status === "ON_SALE" || listing.status === "RELIST_BUFFER" ? (
                  <button className="btn-secondary" disabled={!!busy} onClick={() => action("off", "off-shelf", "已下架")}><ArrowDownToLine className="size-4" />{listing.status === "RELIST_BUFFER" ? "继续下架" : "下架"}</button>
                ) : (
                  <button className="btn-secondary" disabled={!!busy || listing.status !== "OFF_SHELF" || listing.relist_blocked} onClick={() => action("on", "on-shelf", "已重新上架")}><ArrowUpFromLine className="size-4" />上架</button>
                )}
                {listing.status === "RELIST_BUFFER" ? (
                  <button className="btn-secondary" disabled={!!busy || listing.relist_blocked} onClick={() => action("on", "on-shelf", "已重新上架")}><ArrowUpFromLine className="size-4" />重新上架</button>
                ) : (
                  <button className="btn-danger" disabled={!!busy || !editable} onClick={() => setConfirmDelete(true)}><Trash2 className="size-4" />删除</button>
                )}
              </div>
              {listing.relist_blocked && <p className="rounded-lg bg-rose-50 p-2.5 text-xs text-rose-700">该商品已被管理员禁止再售。</p>}
            </div>
          )}
        </div>
      </div>

      <Modal open={confirmDelete} onClose={() => setConfirmDelete(false)} title="删除商品" footer={
        <>
          <button className="btn-secondary" onClick={() => setConfirmDelete(false)}>取消</button>
          <button className="btn-danger" disabled={busy === "del"} onClick={() => run("del", async () => { await del(`/listings/${listing!.listing_id}`); navigate("/my/listings"); }, "商品已删除").finally(() => setConfirmDelete(false))}>确认删除</button>
        </>
      }>
        <p className="text-sm text-slate-600">删除后商品、价格历史和收藏记录都会被移除，无法恢复。已经产生过订单的商品不能删除，只能下架。</p>
      </Modal>
    </div>
  );
}
