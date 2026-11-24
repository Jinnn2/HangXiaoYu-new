import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  BookOpen, Dumbbell, Guitar, Laptop, Loader2, Package, Shirt, Sofa, X, CheckCircle2, AlertCircle, Coins,
} from "lucide-react";
import type { ListingStatus, OrderStatus } from "./api";

// ------------------------------------------------------------------ 文案
export const CONDITION_LABEL: Record<number, string> = { 5: "几乎全新", 4: "九成新", 3: "八成新", 2: "七成新", 1: "有瑕疵" };

export const LISTING_STATUS: Record<ListingStatus, { label: string; cls: string }> = {
  ON_SALE: { label: "在售", cls: "bg-emerald-50 text-emerald-700 ring-emerald-600/15" },
  PAYMENT_RESERVED: { label: "支付占用", cls: "bg-amber-50 text-amber-700 ring-amber-600/15" },
  TRADING: { label: "交易中", cls: "bg-sky-50 text-sky-700 ring-sky-600/15" },
  RELIST_BUFFER: { label: "重新上架缓冲", cls: "bg-violet-50 text-violet-700 ring-violet-600/15" },
  OFF_SHELF: { label: "已下架", cls: "bg-slate-100 text-slate-600 ring-slate-500/15" },
  SOLD: { label: "已售出", cls: "bg-slate-800 text-white ring-slate-800" },
};

export const ORDER_STATUS: Record<OrderStatus, { label: string; cls: string }> = {
  PENDING_PAYMENT: { label: "待付款", cls: "bg-amber-50 text-amber-700 ring-amber-600/15" },
  PENDING_DELIVERY: { label: "待交付", cls: "bg-sky-50 text-sky-700 ring-sky-600/15" },
  PENDING_RECEIPT: { label: "待收货", cls: "bg-indigo-50 text-indigo-700 ring-indigo-600/15" },
  UNDER_REVIEW: { label: "待核实", cls: "bg-rose-50 text-rose-700 ring-rose-600/15" },
  COMPLETED: { label: "已完成", cls: "bg-emerald-50 text-emerald-700 ring-emerald-600/15" },
  CANCELED: { label: "已取消", cls: "bg-slate-100 text-slate-600 ring-slate-500/15" },
  PAYMENT_EXPIRED: { label: "支付超时", cls: "bg-slate-100 text-slate-500 ring-slate-500/15" },
};

export const REVIEW_REASON: Record<string, string> = {
  BUYER_CANCEL_REQUEST: "买家申请取消",
  NOT_RECEIVED: "买家反馈未收到",
  SELLER_DELIVERY_LATE: "卖家超时未交付",
  BUYER_CANCEL_UNPAID: "买家取消未付款订单",
};

export const LEDGER_EVENT: Record<string, string> = {
  GRANT: "注册赠送", PAYMENT: "付款托管", SETTLEMENT: "成交入账", REFUND: "退款",
};

// ------------------------------------------------------------------ 格式化
export function fmtTime(s: string | null | undefined, withYear = false) {
  if (!s) return "—";
  const d = new Date(s);
  const pad = (n: number) => String(n).padStart(2, "0");
  const date = `${withYear ? d.getFullYear() + "-" : ""}${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  return `${date} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function timeAgo(s: string) {
  const sec = (Date.now() - new Date(s).getTime()) / 1000;
  if (sec < 60) return "刚刚";
  if (sec < 3600) return `${Math.floor(sec / 60)} 分钟前`;
  if (sec < 86400) return `${Math.floor(sec / 3600)} 小时前`;
  if (sec < 86400 * 30) return `${Math.floor(sec / 86400)} 天前`;
  return fmtTime(s, true).slice(0, 10);
}

// ------------------------------------------------------------------ 小组件
export function Badge({ cls, children }: { cls: string; children: ReactNode }) {
  return <span className={`chip ring-1 ring-inset ${cls}`}>{children}</span>;
}

export function ListingStatusBadge({ status }: { status: ListingStatus }) {
  const s = LISTING_STATUS[status];
  return <Badge cls={s.cls}>{s.label}</Badge>;
}

export function OrderStatusBadge({ status }: { status: OrderStatus }) {
  const s = ORDER_STATUS[status];
  return <Badge cls={s.cls}>{s.label}</Badge>;
}

export function Points({ value, size = "md", muted }: { value: number; size?: "sm" | "md" | "lg" | "xl"; muted?: boolean }) {
  const text = { sm: "text-sm", md: "text-lg", lg: "text-2xl", xl: "text-4xl" }[size];
  return (
    <span className={`inline-flex items-baseline gap-1 font-bold tabular-nums ${muted ? "text-slate-400" : "text-rose-500"} ${text}`}>
      {value.toLocaleString()}
      <span className="text-xs font-medium opacity-80">积分</span>
    </span>
  );
}

export function Spinner({ className = "" }: { className?: string }) {
  return <Loader2 className={`size-5 animate-spin text-brand-500 ${className}`} />;
}

export function PageLoading() {
  return <div className="flex h-64 items-center justify-center"><Spinner className="size-7" /></div>;
}

export function Empty({ icon, title, hint, action }: { icon?: ReactNode; title: string; hint?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-slate-200 bg-white/60 px-6 py-16 text-center">
      <div className="mb-3 grid size-12 place-items-center rounded-2xl bg-slate-100 text-slate-400">{icon ?? <Package className="size-6" />}</div>
      <p className="font-semibold text-slate-700">{title}</p>
      {hint && <p className="mt-1 text-sm text-slate-500">{hint}</p>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

export function SectionTitle({ title, desc, right }: { title: string; desc?: string; right?: ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">{title}</h1>
        {desc && <p className="mt-1 text-sm text-slate-500">{desc}</p>}
      </div>
      {right}
    </div>
  );
}

// 没有图片时按分类生成渐变封面
const CATEGORY_STYLE: Record<string, { icon: typeof Laptop; from: string; to: string }> = {
  数码电子: { icon: Laptop, from: "from-sky-400", to: "to-indigo-500" },
  教材书籍: { icon: BookOpen, from: "from-amber-300", to: "to-orange-500" },
  生活用品: { icon: Sofa, from: "from-emerald-300", to: "to-teal-500" },
  运动户外: { icon: Dumbbell, from: "from-lime-300", to: "to-green-600" },
  服饰鞋包: { icon: Shirt, from: "from-pink-300", to: "to-rose-500" },
  乐器文娱: { icon: Guitar, from: "from-violet-300", to: "to-purple-600" },
};

export function Cover({ title, category, imageUrl, className = "", small = false }: { title: string; category: string; imageUrl?: string | null; className?: string; small?: boolean }) {
  const [broken, setBroken] = useState(false);
  const style = CATEGORY_STYLE[category] ?? { icon: Package, from: "from-slate-300", to: "to-slate-500" };
  const Icon = style.icon;
  if (imageUrl && !broken) {
    return <img src={imageUrl} alt={title} onError={() => setBroken(true)} className={`object-cover ${className}`} />;
  }
  return (
    <div className={`relative overflow-hidden bg-gradient-to-br ${style.from} ${style.to} ${className}`}>
      <div className="absolute -right-6 -top-6 size-28 rounded-full bg-white/15" />
      <div className="absolute -bottom-10 -left-4 size-32 rounded-full bg-black/5" />
      <div className={`relative flex h-full flex-col items-center justify-center gap-2 text-white ${small ? "p-1" : "p-4"}`}>
        <Icon className={small ? "size-5" : "size-10 drop-shadow"} strokeWidth={small ? 2 : 1.6} />
        {!small && <span className="line-clamp-1 max-w-full text-center text-xs font-medium opacity-90">{title}</span>}
      </div>
    </div>
  );
}

// 倒计时（以服务器时间为准：用 server_time 与本地时间的差值校正）
export function useCountdown(deadline: string | null, serverTime?: string) {
  const offset = useMemo(() => (serverTime ? new Date(serverTime).getTime() - Date.now() : 0), [serverTime]);
  const [now, setNow] = useState(() => Date.now() + offset);
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now() + offset), 1000);
    return () => clearInterval(t);
  }, [offset]);
  if (!deadline) return null;
  const ms = Math.max(0, new Date(deadline).getTime() - now);
  const h = Math.floor(ms / 3600000), m = Math.floor((ms % 3600000) / 60000), s = Math.floor((ms % 60000) / 1000);
  const text = h > 0 ? `${h} 小时 ${m} 分` : `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return { ms, text, expired: ms <= 0 };
}

// ------------------------------------------------------------------ Toast
type ToastItem = { id: number; kind: "success" | "error"; text: string };
const ToastCtx = createContext<(kind: ToastItem["kind"], text: string) => void>(() => {});
export const useToast = () => useContext(ToastCtx);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const push = useCallback((kind: ToastItem["kind"], text: string) => {
    const id = Date.now() + Math.random();
    setItems((xs) => [...xs, { id, kind, text }]);
    setTimeout(() => setItems((xs) => xs.filter((x) => x.id !== id)), 3500);
  }, []);
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 top-20 z-[60] flex flex-col items-center gap-2 px-4">
        {items.map((t) => (
          <div key={t.id} className="animate-fade-up pointer-events-auto flex max-w-md items-center gap-2.5 rounded-xl bg-slate-900/95 px-4 py-3 text-sm text-white shadow-lift backdrop-blur">
            {t.kind === "success" ? <CheckCircle2 className="size-4 shrink-0 text-emerald-400" /> : <AlertCircle className="size-4 shrink-0 text-rose-400" />}
            {t.text}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}

// 包装一个异步操作：执行中禁用按钮，成功/失败给出提示
export function useAction() {
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);
  const run = useCallback(async <T,>(key: string, fn: () => Promise<T>, success?: string): Promise<T | undefined> => {
    setBusy(key);
    try {
      const r = await fn();
      if (success) toast("success", success);
      return r;
    } catch (e) {
      toast("error", e instanceof Error ? e.message : String(e));
      return undefined;
    } finally {
      setBusy(null);
    }
  }, [toast]);
  return { busy, run };
}

// ------------------------------------------------------------------ Modal
export function Modal({ open, onClose, title, children, footer }: { open: boolean; onClose: () => void; title: string; children: ReactNode; footer?: ReactNode }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/40 p-4 backdrop-blur-sm sm:items-center" onClick={onClose}>
      <div className="animate-fade-up card w-full max-w-md p-0" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
          <h3 className="font-semibold text-slate-900">{title}</h3>
          <button className="rounded-lg p-1 text-slate-400 hover:bg-slate-100" onClick={onClose}><X className="size-4" /></button>
        </div>
        <div className="px-5 py-4">{children}</div>
        {footer && <div className="flex justify-end gap-2 border-t border-slate-100 px-5 py-3">{footer}</div>}
      </div>
    </div>
  );
}

export function StatCard({ label, value, hint, icon, tone = "brand" }: { label: string; value: ReactNode; hint?: ReactNode; icon?: ReactNode; tone?: "brand" | "emerald" | "amber" | "violet" | "rose" }) {
  const tones = {
    brand: "bg-brand-50 text-brand-600", emerald: "bg-emerald-50 text-emerald-600", amber: "bg-amber-50 text-amber-600",
    violet: "bg-violet-50 text-violet-600", rose: "bg-rose-50 text-rose-600",
  };
  return (
    <div className="card p-5">
      <div className="flex items-start justify-between">
        <p className="text-sm font-medium text-slate-500">{label}</p>
        <div className={`grid size-9 place-items-center rounded-xl ${tones[tone]}`}>{icon ?? <Coins className="size-4" />}</div>
      </div>
      <div className="mt-2 text-2xl font-bold tabular-nums text-slate-900">{value}</div>
      {hint && <p className="mt-1 text-xs text-slate-500">{hint}</p>}
    </div>
  );
}
