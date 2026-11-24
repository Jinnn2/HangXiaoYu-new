// 轻量 SVG 图表：只用于看板。
// 规范：柱宽 ≤ 24px、数据端 4px 圆角、基线方角；折线 2px + 10% 面积；端点 ≥ 8px 带 2px 表面色描边；
// 网格为 1px 实线浅灰；≥ 2 个系列必有图例；每张图都可展开数据表；悬停显示提示。
import { useEffect, useRef, useState, type ReactNode } from "react";

// 分类色板（固定顺序，已用校验脚本验证）
export const SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6"];
const GRID = "#e8eaee";
const SURFACE = "#ffffff";
const INK_2 = "#64748b";
const DEEMPH = "#cbd5e1";

export function compact(n: number) {
  if (Math.abs(n) >= 10000) return (n / 10000).toFixed(n % 10000 === 0 ? 0 : 1) + "万";
  return n.toLocaleString();
}

function useWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [w, setW] = useState(0);
  useEffect(() => {
    if (!ref.current) return;
    const ro = new ResizeObserver(([e]) => setW(e.contentRect.width));
    ro.observe(ref.current);
    return () => ro.disconnect();
  }, []);
  return [ref, w] as const;
}

function niceMax(v: number) {
  if (v <= 0) return 4;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  const m = [1, 2, 2.5, 5, 10].find((x) => x * p >= v)!;
  return m * p;
}

// 柱：只有数据端是圆角
function barPath(x: number, y0: number, w: number, h: number, up = true) {
  if (h <= 0) return "";
  const r = Math.min(4, h, w / 2);
  if (up) {
    const top = y0 - h;
    return `M${x},${y0} V${top + r} Q${x},${top} ${x + r},${top} H${x + w - r} Q${x + w},${top} ${x + w},${top + r} V${y0} Z`;
  }
  const bot = y0 + h;
  return `M${x},${y0} V${bot - r} Q${x},${bot} ${x + r},${bot} H${x + w - r} Q${x + w},${bot} ${x + w},${bot - r} V${y0} Z`;
}

function Tooltip({ x, y, width, children }: { x: number; y: number; width: number; children: ReactNode }) {
  const left = Math.min(Math.max(x, 70), width - 70);
  return (
    <div className="pointer-events-none absolute z-10 -translate-x-1/2 -translate-y-full whitespace-nowrap rounded-lg bg-slate-900/95 px-2.5 py-1.5 text-xs text-white shadow-lg"
      style={{ left, top: y - 8 }}>
      {children}
    </div>
  );
}

function Swatch({ color }: { color: string }) {
  return <span className="inline-block size-2.5 shrink-0 rounded-sm" style={{ background: color }} />;
}

export function Legend({ items }: { items: { label: string; color: string; value?: ReactNode }[] }) {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5 text-xs text-slate-600">
      {items.map((i) => (
        <span key={i.label} className="flex items-center gap-1.5"><Swatch color={i.color} />{i.label}{i.value !== undefined && <span className="font-semibold text-slate-800">{i.value}</span>}</span>
      ))}
    </div>
  );
}

export function DataTable({ columns, rows }: { columns: string[]; rows: (string | number)[][] }) {
  return (
    <details className="group mt-3 text-xs">
      <summary className="cursor-pointer select-none text-slate-400 hover:text-slate-600">查看数据</summary>
      <div className="mt-2 max-h-56 overflow-auto rounded-lg border border-slate-100">
        <table className="w-full tabular-nums">
          <thead className="sticky top-0 bg-slate-50 text-slate-500"><tr>{columns.map((c) => <th key={c} className="px-3 py-1.5 text-left font-medium">{c}</th>)}</tr></thead>
          <tbody className="divide-y divide-slate-100">{rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j} className="px-3 py-1.5 text-slate-600">{c}</td>)}</tr>)}</tbody>
        </table>
      </div>
    </details>
  );
}

// ------------------------------------------------------------------ 迷你走势
export function Sparkline({ values, color = SERIES[0], height = 36 }: { values: number[]; color?: string; height?: number }) {
  const [ref, w] = useWidth<HTMLDivElement>();
  if (values.length < 2) return <div ref={ref} style={{ height }} />;
  const min = Math.min(...values), max = Math.max(...values);
  const x = (i: number) => 4 + (i * (w - 8)) / (values.length - 1);
  const y = (v: number) => (max === min ? height / 2 : 4 + ((max - v) * (height - 8)) / (max - min));
  const d = values.map((v, i) => `${i ? "L" : "M"}${x(i)},${y(v)}`).join(" ");
  const last = values.length - 1;
  return (
    <div ref={ref} style={{ height }}>
      {w > 0 && (
        <svg width={w} height={height} aria-hidden>
          <path d={d} fill="none" stroke={DEEMPH} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
          <circle cx={x(last)} cy={y(values[last])} r={4} fill={color} stroke={SURFACE} strokeWidth={2} />
        </svg>
      )}
    </div>
  );
}

// ------------------------------------------------------------------ 柱状图（单系列）
export function ColumnChart({ data, color = SERIES[0], unit = "", height = 200, label = "数值" }:
  { data: { label: string; value: number }[]; color?: string; unit?: string; height?: number; label?: string }) {
  const [ref, w] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);
  const P = { l: 36, r: 8, t: 12, b: 24 };
  const max = niceMax(Math.max(0, ...data.map((d) => d.value)));
  const iw = Math.max(0, w - P.l - P.r), ih = height - P.t - P.b;
  const band = data.length ? iw / data.length : 0;
  const bw = Math.min(24, band * 0.6);
  const y = (v: number) => P.t + ih - (v / max) * ih;
  const every = Math.ceil(data.length / Math.max(1, Math.floor(iw / 44)));
  return (
    <div>
      <div ref={ref} className="relative" style={{ height }} onMouseLeave={() => setHover(null)}>
        {w > 0 && (
          <svg width={w} height={height} role="img" aria-label={label}>
            {[0, 0.5, 1].map((t) => (
              <g key={t}>
                <line x1={P.l} x2={w - P.r} y1={y(max * t)} y2={y(max * t)} stroke={GRID} strokeWidth={1} />
                <text x={P.l - 6} y={y(max * t)} dy="0.32em" textAnchor="end" fontSize={11} fill={INK_2}>{compact(max * t)}</text>
              </g>
            ))}
            {data.map((d, i) => {
              const x = P.l + i * band + (band - bw) / 2;
              return (
                <g key={d.label}>
                  <path d={barPath(x, P.t + ih, bw, (d.value / max) * ih)} fill={color} opacity={hover === null || hover === i ? 1 : 0.45} />
                  {i % every === 0 && <text x={x + bw / 2} y={height - 6} textAnchor="middle" fontSize={11} fill={INK_2}>{d.label}</text>}
                  <rect x={P.l + i * band} y={P.t} width={band} height={ih} fill="transparent" onMouseEnter={() => setHover(i)} />
                </g>
              );
            })}
          </svg>
        )}
        {hover !== null && data[hover] && (
          <Tooltip x={P.l + hover * band + band / 2} y={y(data[hover].value)} width={w}>
            <div className="text-white/70">{data[hover].label}</div>
            <div className="flex items-center gap-1.5 font-semibold"><Swatch color={color} />{data[hover].value.toLocaleString()}{unit}</div>
          </Tooltip>
        )}
      </div>
      <DataTable columns={["日期", label]} rows={data.map((d) => [d.label, d.value])} />
    </div>
  );
}

// ------------------------------------------------------------------ 面积折线（单系列）
export function AreaChart({ data, color = SERIES[0], unit = "", height = 200, label = "数值" }:
  { data: { label: string; value: number }[]; color?: string; unit?: string; height?: number; label?: string }) {
  const [ref, w] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);
  const P = { l: 40, r: 44, t: 14, b: 24 };
  const max = niceMax(Math.max(0, ...data.map((d) => d.value)));
  const iw = Math.max(0, w - P.l - P.r), ih = height - P.t - P.b;
  const x = (i: number) => P.l + (data.length < 2 ? 0 : (i * iw) / (data.length - 1));
  const y = (v: number) => P.t + ih - (v / max) * ih;
  const line = data.map((d, i) => `${i ? "L" : "M"}${x(i)},${y(d.value)}`).join(" ");
  const last = data.length - 1;
  const every = Math.ceil(data.length / Math.max(1, Math.floor(iw / 48)));
  const onMove = (e: React.MouseEvent) => {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const i = Math.round(((e.clientX - rect.left - P.l) / iw) * last);
    setHover(Math.max(0, Math.min(last, i)));
  };
  return (
    <div>
      <div ref={ref} className="relative" style={{ height }} onMouseMove={onMove} onMouseLeave={() => setHover(null)}>
        {w > 0 && data.length > 0 && (
          <svg width={w} height={height} role="img" aria-label={label}>
            {[0, 0.5, 1].map((t) => (
              <g key={t}>
                <line x1={P.l} x2={w - P.r} y1={y(max * t)} y2={y(max * t)} stroke={GRID} strokeWidth={1} />
                <text x={P.l - 6} y={y(max * t)} dy="0.32em" textAnchor="end" fontSize={11} fill={INK_2}>{compact(max * t)}</text>
              </g>
            ))}
            <path d={`${line} L${x(last)},${y(0)} L${x(0)},${y(0)} Z`} fill={color} opacity={0.1} />
            <path d={line} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
            {data.map((d, i) => i % every === 0 && <text key={d.label} x={x(i)} y={height - 6} textAnchor="middle" fontSize={11} fill={INK_2}>{d.label}</text>)}
            {hover !== null && <line x1={x(hover)} x2={x(hover)} y1={P.t} y2={P.t + ih} stroke={INK_2} strokeWidth={1} />}
            <circle cx={x(hover ?? last)} cy={y(data[hover ?? last].value)} r={4.5} fill={color} stroke={SURFACE} strokeWidth={2} />
            {hover === null && <text x={x(last) + 8} y={y(data[last].value)} dy="0.32em" fontSize={12} fontWeight={600} fill="#0f172a">{compact(data[last].value)}</text>}
          </svg>
        )}
        {hover !== null && data[hover] && (
          <Tooltip x={x(hover)} y={y(data[hover].value)} width={w}>
            <div className="text-white/70">{data[hover].label}</div>
            <div className="flex items-center gap-1.5 font-semibold"><Swatch color={color} />{data[hover].value.toLocaleString()}{unit}</div>
          </Tooltip>
        )}
      </div>
      <DataTable columns={["日期", label]} rows={data.map((d) => [d.label, d.value])} />
    </div>
  );
}

// ------------------------------------------------------------------ 收入 / 支出（基线上下两个系列）
export function InOutChart({ data, height = 210 }: { data: { label: string; income: number; spend: number }[]; height?: number }) {
  const [ref, w] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);
  const P = { l: 40, r: 8, t: 10, b: 24 };
  const max = niceMax(Math.max(1, ...data.map((d) => Math.max(d.income, d.spend))));
  const iw = Math.max(0, w - P.l - P.r), ih = height - P.t - P.b;
  const half = ih / 2, base = P.t + half;
  const band = data.length ? iw / data.length : 0;
  const bw = Math.min(16, band * 0.6);
  const every = Math.ceil(data.length / Math.max(1, Math.floor(iw / 48)));
  const [cIn, cOut] = [SERIES[0], SERIES[1]];
  return (
    <div>
      <div className="mb-3"><Legend items={[{ label: "收入", color: cIn }, { label: "支出", color: cOut }]} /></div>
      <div ref={ref} className="relative" style={{ height }} onMouseLeave={() => setHover(null)}>
        {w > 0 && (
          <svg width={w} height={height} role="img" aria-label="每日积分收入与支出">
            {[-1, 0, 1].map((t) => (
              <g key={t}>
                <line x1={P.l} x2={w - P.r} y1={base - t * half} y2={base - t * half} stroke={t === 0 ? DEEMPH : GRID} strokeWidth={1} />
                <text x={P.l - 6} y={base - t * half} dy="0.32em" textAnchor="end" fontSize={11} fill={INK_2}>{t === 0 ? "0" : (t > 0 ? "+" : "−") + compact(max)}</text>
              </g>
            ))}
            {data.map((d, i) => {
              const x = P.l + i * band + (band - bw) / 2;
              const dim = hover !== null && hover !== i ? 0.45 : 1;
              return (
                <g key={d.label}>
                  <path d={barPath(x, base - 1, bw, (d.income / max) * half - 1, true)} fill={cIn} opacity={dim} />
                  <path d={barPath(x, base + 1, bw, (d.spend / max) * half - 1, false)} fill={cOut} opacity={dim} />
                  {i % every === 0 && <text x={x + bw / 2} y={height - 6} textAnchor="middle" fontSize={11} fill={INK_2}>{d.label}</text>}
                  <rect x={P.l + i * band} y={P.t} width={band} height={ih} fill="transparent" onMouseEnter={() => setHover(i)} />
                </g>
              );
            })}
          </svg>
        )}
        {hover !== null && data[hover] && (
          <Tooltip x={P.l + hover * band + band / 2} y={base - (data[hover].income / max) * half} width={w}>
            <div className="text-white/70">{data[hover].label}</div>
            <div className="flex items-center gap-1.5"><Swatch color={cIn} />收入 <b>{data[hover].income}</b></div>
            <div className="flex items-center gap-1.5"><Swatch color={cOut} />支出 <b>{data[hover].spend}</b></div>
          </Tooltip>
        )}
      </div>
      <DataTable columns={["日期", "收入", "支出"]} rows={data.map((d) => [d.label, d.income, d.spend])} />
    </div>
  );
}

// ------------------------------------------------------------------ 分段条（整体中的各部分）
export function SegmentedBar({ parts }: { parts: { label: string; value: number; color: string }[] }) {
  const [hover, setHover] = useState<number | null>(null);
  const total = parts.reduce((s, p) => s + p.value, 0);
  const shown = parts.filter((p) => p.value > 0);
  if (total === 0) return <p className="text-sm text-slate-400">暂无数据</p>;
  return (
    <div>
      <div className="relative flex h-7 w-full gap-[2px]" onMouseLeave={() => setHover(null)}>
        {shown.map((p, i) => {
          const share = p.value / total;
          return (
            <div key={p.label} className="relative flex h-full items-center overflow-hidden rounded px-2 text-[11px] font-semibold text-white transition-opacity"
              style={{ width: `${share * 100}%`, background: p.color, opacity: hover === null || hover === i ? 1 : 0.5 }}
              onMouseEnter={() => setHover(i)} aria-label={`${p.label} ${p.value}（${Math.round(share * 100)}%）`}>
              {share >= 0.12 && <span className="drop-shadow-sm">{Math.round(share * 100)}%</span>}
            </div>
          );
        })}
        {hover !== null && shown[hover] && (
          <div className="pointer-events-none absolute -top-2 left-1/2 z-10 -translate-x-1/2 -translate-y-full rounded-lg bg-slate-900/95 px-2.5 py-1.5 text-xs text-white shadow-lg">
            <span className="flex items-center gap-1.5"><Swatch color={shown[hover].color} />{shown[hover].label} <b>{shown[hover].value}</b>（{Math.round((shown[hover].value / total) * 100)}%）</span>
          </div>
        )}
      </div>
      <div className="mt-3"><Legend items={shown.map((p) => ({ label: p.label, color: p.color, value: p.value }))} /></div>
    </div>
  );
}

// ------------------------------------------------------------------ 横向排行条（单系列）
export function RankBars({ rows, color = SERIES[0], unit = "" }: { rows: { label: string; value: number; note?: string }[]; color?: string; unit?: string }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <div className="space-y-3">
      {rows.map((r) => (
        <div key={r.label} title={`${r.label}：${r.value.toLocaleString()}${unit}`}>
          <div className="mb-1 flex items-baseline justify-between gap-2 text-xs">
            <span className="truncate font-medium text-slate-700">{r.label}{r.note && <span className="ml-1.5 font-normal text-slate-400">{r.note}</span>}</span>
            <span className="shrink-0 font-semibold tabular-nums text-slate-800">{r.value.toLocaleString()}{unit}</span>
          </div>
          <div className="h-2.5 w-full rounded bg-slate-100">
            <div className="h-full rounded-r" style={{ width: `${(r.value / max) * 100}%`, background: color, minWidth: r.value > 0 ? 4 : 0 }} />
          </div>
        </div>
      ))}
    </div>
  );
}

// ------------------------------------------------------------------ 成交价走势（散点 + 建议价参考线）
export function PriceTimeline({ points, reference, height = 220 }: {
  points: { t: string; value: number; highlight: boolean; label: string }[];
  reference?: { value: number; label: string };
  height?: number;
}) {
  const [ref, w] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);
  const P = { l: 44, r: 16, t: 16, b: 26 };
  const times = points.map((p) => new Date(p.t).getTime());
  const now = Date.now();
  const t0 = Math.min(now - 30 * 86400000, ...times), t1 = now;
  const max = niceMax(Math.max(reference?.value ?? 0, ...points.map((p) => p.value)) * 1.05);
  const iw = Math.max(0, w - P.l - P.r), ih = height - P.t - P.b;
  const x = (t: number) => P.l + ((t - t0) / (t1 - t0)) * iw;
  const y = (v: number) => P.t + ih - (v / max) * ih;
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => t0 + f * (t1 - t0));
  const fmt = (t: number) => { const d = new Date(t); return `${d.getMonth() + 1}-${String(d.getDate()).padStart(2, "0")}`; };
  // 先画非同款，再画同款，让重点在上层
  const order = points.map((_, i) => i).sort((a, b) => Number(points[a].highlight) - Number(points[b].highlight));
  const onMove = (e: React.MouseEvent) => {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    let best: number | null = null, bd = 24 * 24;
    points.forEach((p, i) => {
      const d = (x(times[i]) - mx) ** 2 + (y(p.value) - my) ** 2;
      if (d < bd) { bd = d; best = i; }
    });
    setHover(best);
  };
  return (
    <div>
      <div className="mb-3"><Legend items={[{ label: "同款成交", color: SERIES[0] }, { label: "同分类其他成交", color: DEEMPH }]} /></div>
      <div ref={ref} className="relative" style={{ height }} onMouseMove={onMove} onMouseLeave={() => setHover(null)}>
        {w > 0 && (
          <svg width={w} height={height} role="img" aria-label="近期成交价（已按成色折算）">
            {[0, 0.5, 1].map((f) => (
              <g key={f}>
                <line x1={P.l} x2={w - P.r} y1={y(max * f)} y2={y(max * f)} stroke={GRID} strokeWidth={1} />
                <text x={P.l - 6} y={y(max * f)} dy="0.32em" textAnchor="end" fontSize={11} fill={INK_2}>{compact(max * f)}</text>
              </g>
            ))}
            {ticks.map((t) => <text key={t} x={x(t)} y={height - 6} textAnchor="middle" fontSize={11} fill={INK_2}>{fmt(t)}</text>)}
            {reference && (
              <g>
                <line x1={P.l} x2={w - P.r} y1={y(reference.value)} y2={y(reference.value)} stroke="#0f172a" strokeWidth={1} />
                <text x={w - P.r} y={y(reference.value) - 6} textAnchor="end" fontSize={11} fontWeight={600} fill="#0f172a">{reference.label} {reference.value}</text>
              </g>
            )}
            {order.map((i) => (
              <circle key={i} cx={x(times[i])} cy={y(points[i].value)} r={hover === i ? 6 : 4.5}
                fill={points[i].highlight ? SERIES[0] : DEEMPH} stroke={SURFACE} strokeWidth={2} />
            ))}
          </svg>
        )}
        {hover !== null && points[hover] && (
          <Tooltip x={x(times[hover])} y={y(points[hover].value)} width={w}>
            <div className="text-white/70">{fmt(times[hover])} · {points[hover].highlight ? "同款" : "同分类"}</div>
            <div className="font-semibold">{points[hover].label}</div>
            <div className="flex items-center gap-1.5"><Swatch color={points[hover].highlight ? SERIES[0] : DEEMPH} />折算价 <b>{points[hover].value}</b></div>
          </Tooltip>
        )}
      </div>
    </div>
  );
}
