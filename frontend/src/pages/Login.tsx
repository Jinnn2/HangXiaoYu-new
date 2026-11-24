import { useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import { ArrowRight, BadgeCheck, LineChart, ShieldCheck } from "lucide-react";
import { post, type Me } from "../api";
import { useAuth } from "../auth";
import { useAction } from "../ui";

export default function LoginPage() {
  const [mode, setMode] = useState<"login" | "register">("login");
  const [form, setForm] = useState({ student_no: "", display_name: "", password: "" });
  const { setMe } = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { busy, run } = useAction();

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    run("submit", async () => {
      const me = await post<Me>(mode === "login" ? "/auth/login" : "/auth/register", form);
      setMe(me);
      navigate(params.get("next") || "/", { replace: true });
    }, mode === "login" ? "欢迎回来" : "注册成功，已赠送 500 积分");
  };

  return (
    <div className="grid min-h-screen lg:grid-cols-2">
      <div className="relative hidden overflow-hidden bg-gradient-to-br from-brand-600 via-indigo-600 to-violet-700 p-12 text-white lg:flex lg:flex-col">
        <div className="absolute -right-20 top-20 size-96 rounded-full bg-white/10 blur-3xl" />
        <div className="absolute -bottom-32 -left-10 size-96 rounded-full bg-sky-400/20 blur-3xl" />
        <Link to="/" className="relative flex items-center gap-3">
          <img src="/favicon.svg" alt="" className="size-10 rounded-xl ring-2 ring-white/30" />
          <span className="text-xl font-extrabold">航小鱼</span>
        </Link>
        <div className="relative mt-auto max-w-md">
          <h1 className="text-4xl font-extrabold leading-tight">校园里的闲置，<br />值得一个好价钱。</h1>
          <ul className="mt-8 space-y-4 text-white/85">
            <li className="flex gap-3"><ShieldCheck className="size-5 shrink-0" />积分托管：确认收货后才转给卖家</li>
            <li className="flex gap-3"><LineChart className="size-5 shrink-0" />智能估价：参考同类真实成交价</li>
            <li className="flex gap-3"><BadgeCheck className="size-5 shrink-0" />卖家信誉：每笔交易都有据可查</li>
          </ul>
        </div>
      </div>

      <div className="flex items-center justify-center p-6">
        <div className="w-full max-w-sm">
          <Link to="/" className="mb-8 flex items-center gap-2 lg:hidden">
            <img src="/favicon.svg" alt="" className="size-9 rounded-xl" /><span className="text-lg font-extrabold">航小鱼</span>
          </Link>
          <h2 className="text-2xl font-bold text-slate-900">{mode === "login" ? "登录" : "注册账号"}</h2>
          <p className="mt-1 text-sm text-slate-500">{mode === "login" ? "使用学号登录" : "新用户注册即送 500 积分"}</p>
          <form onSubmit={submit} className="mt-8 space-y-4">
            <div>
              <label className="label">学号</label>
              <input className="input" required autoFocus value={form.student_no} onChange={(e) => setForm({ ...form, student_no: e.target.value })} placeholder="例如 23370001" />
            </div>
            {mode === "register" && (
              <div>
                <label className="label">昵称</label>
                <input className="input" required maxLength={40} value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} />
              </div>
            )}
            <div>
              <label className="label">密码</label>
              <input className="input" type="password" required minLength={mode === "register" ? 6 : undefined} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
            </div>
            <button className="btn-primary w-full py-3" disabled={busy === "submit"}>{mode === "login" ? "登录" : "注册并登录"}<ArrowRight className="size-4" /></button>
          </form>
          <p className="mt-6 text-center text-sm text-slate-500">
            {mode === "login" ? "还没有账号？" : "已有账号？"}
            <button className="font-semibold text-brand-600 hover:underline" onClick={() => setMode(mode === "login" ? "register" : "login")}>{mode === "login" ? "立即注册" : "去登录"}</button>
          </p>
          <div className="mt-8 rounded-xl bg-slate-100 p-3 text-xs text-slate-500">
            演示账号：买家 <b>23370001</b>、卖家 <b>23370002</b>、管理员 <b>admin</b>，密码均为 <b>123456</b>
          </div>
        </div>
      </div>
    </div>
  );
}
