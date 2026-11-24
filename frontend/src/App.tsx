import { useEffect, useRef, useState } from "react";
import { Link, NavLink, Outlet, Route, Routes, useLocation, useNavigate } from "react-router";
import {
  Heart, LayoutDashboard, LogOut, Package, Plus, Receipt, Search, ShieldCheck, Sparkles, Store, User, Wallet,
} from "lucide-react";
import { RequireAuth, useAuth } from "./auth";
import Home from "./pages/Home";
import ListingDetailPage from "./pages/ListingDetail";
import SellPage from "./pages/Sell";
import MyListings from "./pages/MyListings";
import OrdersPage from "./pages/Orders";
import OrderDetailPage from "./pages/OrderDetail";
import AccountPage from "./pages/Account";
import FavoritesPage from "./pages/Favorites";
import ValuationPage from "./pages/Valuation";
import LoginPage from "./pages/Login";
import AdminPage from "./pages/Admin";
import DashboardPage from "./pages/Dashboard";
import SellerPage from "./pages/Seller";

function Logo() {
  return (
    <Link to="/" className="flex items-center gap-2.5">
      <img src="/favicon.svg" alt="" className="size-9 rounded-xl shadow-sm" />
      <div className="leading-tight">
        <div className="text-[17px] font-extrabold tracking-tight text-slate-900">航小鱼</div>
        <div className="text-[10px] font-medium tracking-wider text-slate-400">校园二手 · 智能估价</div>
      </div>
    </Link>
  );
}

const NAV = [
  { to: "/", label: "市场", icon: Store, end: true },
  { to: "/valuation", label: "智能估价", icon: Sparkles },
  { to: "/orders", label: "订单", icon: Receipt },
  { to: "/my/listings", label: "我的商品", icon: Package },
];

function UserMenu() {
  const { me, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();
  useEffect(() => {
    const close = (e: MouseEvent) => ref.current && !ref.current.contains(e.target as Node) && setOpen(false);
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);
  if (!me) {
    return <Link to="/login" className="btn-primary px-4 py-2">登录 / 注册</Link>;
  }
  const item = "flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm text-slate-600 hover:bg-slate-50 hover:text-slate-900";
  return (
    <div className="relative" ref={ref}>
      <button onClick={() => setOpen((v) => !v)} className="flex items-center gap-2 rounded-full border border-slate-200 bg-white py-1 pl-1 pr-3 transition hover:shadow-sm">
        <span className="grid size-8 place-items-center rounded-full bg-gradient-to-br from-brand-400 to-indigo-500 text-sm font-bold text-white">
          {me.display_name.slice(0, 1)}
        </span>
        <span className="hidden text-sm font-semibold tabular-nums text-slate-700 sm:block">{me.spendable_points.toLocaleString()}<span className="ml-0.5 text-xs font-normal text-slate-400">分</span></span>
      </button>
      {open && (
        <div className="animate-fade-up absolute right-0 top-12 z-50 w-60 rounded-2xl border border-slate-200/70 bg-white p-2 shadow-lift" onClick={() => setOpen(false)}>
          <div className="px-3 py-2">
            <p className="font-semibold text-slate-900">{me.display_name}</p>
            <p className="text-xs text-slate-400">学号 {me.student_no}</p>
          </div>
          <div className="my-1 h-px bg-slate-100" />
          <Link to="/dashboard" className={item}><LayoutDashboard className="size-4" />我的看板</Link>
          <Link to="/account" className={item}><Wallet className="size-4" />我的账户</Link>
          <Link to="/favorites" className={item}><Heart className="size-4" />我的收藏</Link>
          <Link to={`/users/${me.user_id}`} className={item}><User className="size-4" />我的主页</Link>
          {me.role === "ADMIN" && <Link to="/admin" className={item}><ShieldCheck className="size-4" />管理后台</Link>}
          <div className="my-1 h-px bg-slate-100" />
          <button className={`${item} w-full`} onClick={async () => { await logout(); navigate("/"); }}>
            <LogOut className="size-4" />退出登录
          </button>
        </div>
      )}
    </div>
  );
}

function SearchBox() {
  const navigate = useNavigate();
  const location = useLocation();
  const [q, setQ] = useState(() => new URLSearchParams(location.search).get("q") ?? "");
  return (
    <form
      className="relative hidden flex-1 md:block md:max-w-xs lg:max-w-sm"
      onSubmit={(e) => { e.preventDefault(); navigate(q.trim() ? `/?q=${encodeURIComponent(q.trim())}` : "/"); }}
    >
      <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
      <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="搜索教材、数码、生活好物…" className="input rounded-full bg-slate-100/70 py-2 pl-10 focus:bg-white" />
    </form>
  );
}

function Layout() {
  const { me } = useAuth();
  const location = useLocation();
  useEffect(() => { window.scrollTo(0, 0); }, [location.pathname]);
  const navCls = ({ isActive }: { isActive: boolean }) =>
    `flex items-center gap-1.5 rounded-full px-3.5 py-2 text-sm font-medium transition ${isActive ? "bg-slate-900 text-white" : "text-slate-600 hover:bg-slate-100 hover:text-slate-900"}`;
  return (
    <div className="min-h-screen pb-20 md:pb-0">
      <header className="sticky top-0 z-40 border-b border-slate-200/60 bg-white/80 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-7xl items-center gap-4 px-4 sm:px-6">
          <Logo />
          <nav className="ml-4 hidden items-center gap-1 lg:flex">
            {me && <NavLink to="/dashboard" className={navCls}>看板</NavLink>}
            {NAV.map((n) => <NavLink key={n.to} to={n.to} end={n.end} className={navCls}>{n.label}</NavLink>)}
            {me?.role === "ADMIN" && <NavLink to="/admin" className={navCls}>管理后台</NavLink>}
          </nav>
          <div className="ml-auto flex flex-1 items-center justify-end gap-3">
            <SearchBox />
            <Link to="/sell" className="btn-secondary hidden px-3.5 py-2 sm:inline-flex"><Plus className="size-4" />发布闲置</Link>
            <UserMenu />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8">
        <Outlet />
      </main>

      <footer className="mx-auto hidden max-w-7xl px-6 pb-10 pt-4 text-xs text-slate-400 md:block">
        航小鱼 · 《数据库系统原理》大作业 · 所有数据库操作均为原生 SQL（PostgreSQL 存储过程 + 触发器）
      </footer>

      {/* 手机端底部导航 */}
      <nav className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-5 border-t border-slate-200 bg-white/90 pb-[env(safe-area-inset-bottom)] backdrop-blur-xl md:hidden">
        {[NAV[0], NAV[1], { to: "/sell", label: "发布", icon: Plus }, NAV[2], { to: me?.role === "ADMIN" ? "/admin" : "/dashboard", label: me?.role === "ADMIN" ? "后台" : "我的", icon: me?.role === "ADMIN" ? LayoutDashboard : User }].map((n) => (
          <NavLink key={n.to} to={n.to} end={n.to === "/"} className={({ isActive }) => `flex flex-col items-center gap-0.5 py-2 text-[11px] ${isActive ? "text-brand-600" : "text-slate-500"}`}>
            {n.to === "/sell"
              ? <span className="-mt-5 grid size-11 place-items-center rounded-2xl bg-gradient-to-br from-brand-500 to-indigo-500 text-white shadow-lg shadow-brand-500/30"><Plus className="size-5" /></span>
              : <n.icon className="size-5" />}
            {n.label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="listings/:id" element={<ListingDetailPage />} />
        <Route path="users/:id" element={<SellerPage />} />
        <Route path="valuation" element={<ValuationPage />} />
        <Route path="sell" element={<RequireAuth><SellPage /></RequireAuth>} />
        <Route path="sell/:id" element={<RequireAuth><SellPage /></RequireAuth>} />
        <Route path="my/listings" element={<RequireAuth><MyListings /></RequireAuth>} />
        <Route path="orders" element={<RequireAuth><OrdersPage /></RequireAuth>} />
        <Route path="orders/:id" element={<RequireAuth><OrderDetailPage /></RequireAuth>} />
        <Route path="dashboard" element={<RequireAuth><DashboardPage /></RequireAuth>} />
        <Route path="account" element={<RequireAuth><AccountPage /></RequireAuth>} />
        <Route path="favorites" element={<RequireAuth><FavoritesPage /></RequireAuth>} />
        <Route path="admin" element={<RequireAuth admin><AdminPage /></RequireAuth>} />
        <Route path="*" element={<div className="py-24 text-center text-slate-500">页面不存在 · <Link className="text-brand-600" to="/">回到首页</Link></div>} />
      </Route>
    </Routes>
  );
}
