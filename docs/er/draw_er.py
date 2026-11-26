"""生成陈氏（Chen）记法的 E-R 图 SVG：矩形=实体，菱形=联系，椭圆=属性（主键加下划线）。

python docs/er/draw_er.py   → 在本目录输出 *.svg
"""

from __future__ import annotations

import math
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).resolve().parent
FONT = "Noto Sans CJK SC, Microsoft YaHei, PingFang SC, sans-serif"


class Diagram:
    def __init__(self, w: int, h: int, title: str):
        self.w, self.h, self.title = w, h, title
        self.lines: list[str] = []
        self.shapes: list[str] = []
        self.pos: dict[str, tuple[float, float, str]] = {}

    # ---------------------------------------------------------------- 图元
    def entity(self, key: str, x: float, y: float, label: str, weak: bool = False):
        self.pos[key] = (x, y, "entity")
        w = max(96, 22 * len(label) + 28)
        s = f'<rect x="{x - w/2}" y="{y - 24}" width="{w}" height="48" fill="#eef5ff" stroke="#1d4ed8" stroke-width="2"/>'
        if weak:
            s += f'<rect x="{x - w/2 + 4}" y="{y - 20}" width="{w - 8}" height="40" fill="none" stroke="#1d4ed8" stroke-width="1.2"/>'
        s += self.text(x, y, label, 17, "#0f172a", bold=True)
        self.shapes.append(s)

    def relation(self, key: str, x: float, y: float, label: str):
        self.pos[key] = (x, y, "rel")
        w, h = max(92, 20 * len(label) + 44), 54
        pts = f"{x},{y - h/2} {x + w/2},{y} {x},{y + h/2} {x - w/2},{y}"
        self.shapes.append(f'<polygon points="{pts}" fill="#fff7ed" stroke="#c2410c" stroke-width="2"/>'
                           + self.text(x, y, label, 15, "#7c2d12", bold=True))

    def attr(self, owner: str, label: str, angle: float, r: float = 125, key: bool = False):
        ox, oy, _ = self.pos[owner]
        a = math.radians(angle)
        x, y = ox + r * math.cos(a), oy + r * math.sin(a)
        rx = max(34, 7.4 * len(label.encode("gbk")) + 12)
        self.lines.append(f'<line x1="{ox}" y1="{oy}" x2="{x}" y2="{y}" stroke="#94a3b8" stroke-width="1.2"/>')
        s = f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="17" fill="#fff" stroke="#64748b" stroke-width="1.3"/>'
        s += self.text(x, y, label, 13, "#334155", underline=key)
        self.shapes.append(s)

    def attr_at(self, owner: str, label: str, x: float, y: float, key: bool = False):
        ox, oy, _ = self.pos[owner]
        rx = max(34, 7.4 * len(label.encode("gbk")) + 12)
        self.lines.append(f'<line x1="{ox}" y1="{oy}" x2="{x}" y2="{y}" stroke="#94a3b8" stroke-width="1.2"/>')
        s = f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="17" fill="#fff" stroke="#64748b" stroke-width="1.3"/>'
        s += self.text(x, y, label, 13, "#334155", underline=key)
        self.shapes.append(s)

    def column(self, owner: str, labels: list[str], x: float, cy: float, gap: float = 42, keys: int = 1):
        """属性竖排成一列（第一个为主键），中心纵坐标 cy。"""
        top = cy - gap * (len(labels) - 1) / 2
        for i, lab in enumerate(labels):
            self.attr_at(owner, lab, x, top + i * gap, key=i < keys)

    def row(self, owner: str, labels: list[str], y: float, cx: float, gap: float = 130, keys: int = 1):
        left = cx - gap * (len(labels) - 1) / 2
        for i, lab in enumerate(labels):
            self.attr_at(owner, lab, left + i * gap, y, key=i < keys)

    def attrs(self, owner: str, labels: list[str], start: float, end: float, r: float = 125, keys: int = 1):
        n = len(labels)
        for i, lab in enumerate(labels):
            ang = start if n == 1 else start + (end - start) * i / (n - 1)
            self.attr(owner, lab, ang, r, key=i < keys)

    def link(self, a: str, b: str, card: str = "", via: list[tuple[float, float]] | None = None, total: bool = False):
        ax, ay, _ = self.pos[a]
        bx, by, _ = self.pos[b]
        pts = [(ax, ay)] + (via or []) + [(bx, by)]
        d = " ".join(f"{'M' if i == 0 else 'L'}{px},{py}" for i, (px, py) in enumerate(pts))
        width = "3.2" if total else "1.8"
        self.lines.append(f'<path d="{d}" fill="none" stroke="#334155" stroke-width="{width}"/>')
        if card:
            # 基数标在靠近实体一端（a 是实体）
            px, py = pts[1]
            t = 0.28
            cx, cy = ax + (px - ax) * t, ay + (py - ay) * t
            self.shapes.append(f'<circle cx="{cx}" cy="{cy}" r="11" fill="#fff"/>' + self.text(cx, cy, card, 15, "#b91c1c", bold=True))

    def text(self, x, y, s, size, color, bold=False, underline=False):
        deco = ' text-decoration="underline"' if underline else ""
        weight = ' font-weight="700"' if bold else ""
        return (f'<text x="{x}" y="{y}" dy="0.35em" text-anchor="middle" font-size="{size}" fill="{color}"'
                f'{weight}{deco} font-family="{FONT}">{escape(s)}</text>')

    def save(self, name: str, note: str = ""):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">',
               f'<rect width="{self.w}" height="{self.h}" fill="#ffffff"/>',
               self.text(self.w / 2, 34, self.title, 22, "#0f172a", bold=True)]
        if note:
            svg.append(self.text(self.w / 2, self.h - 22, note, 13, "#64748b"))
        svg += self.lines + self.shapes + ["</svg>"]
        (OUT / f"{name}.svg").write_text("\n".join(svg), encoding="utf-8")
        print("wrote", name + ".svg")


# =====================================================================
# 初步 E-R 图（局部 E-R 图，含属性）
# =====================================================================
def local_user_listing():
    d = Diagram(1720, 1180, "局部 E-R 图（一）：用户、商品与估价子系统")
    d.entity("V", 440, 260, "估价记录")
    d.entity("U", 440, 740, "用户")
    d.entity("C", 1080, 260, "分类")
    d.entity("L", 1080, 740, "商品")
    d.entity("PH", 1080, 1040, "价格历史", weak=True)
    d.relation("apply", 440, 500, "申请")
    d.relation("ref", 760, 260, "参照")
    d.relation("belong", 1080, 500, "归属")
    d.relation("pub", 760, 660, "发布")
    d.relation("fav", 760, 820, "收藏")
    d.relation("rep", 1080, 900, "调价")
    d.link("U", "apply", "1"); d.link("V", "apply", "N", total=True)
    d.link("C", "ref", "1"); d.link("V", "ref", "N", total=True)
    d.link("C", "belong", "1"); d.link("L", "belong", "N", total=True)
    d.link("U", "pub", "1"); d.link("L", "pub", "N", total=True)
    d.link("U", "fav", "M"); d.link("L", "fav", "N")
    d.link("L", "rep", "1"); d.link("PH", "rep", "N", total=True)
    d.attr_at("fav", "收藏时间", 760, 910)
    d.column("V", ["估价编号", "物品名称", "成色", "原价", "建议价", "最低价", "最高价", "样本数", "估价依据", "估价时间"], 150, 260, 40)
    d.column("U", ["用户编号", "学号", "昵称", "密码哈希", "角色", "状态", "注册时间"], 150, 740)
    d.row("C", ["分类编号", "名称", "排序"], 120, 1080)
    d.column("L", ["商品编号", "标题", "描述", "成色", "原价", "当前价"], 1400, 740, 46)
    d.column("L", ["图片", "状态", "禁止再售", "发布时间", "更新时间"], 1580, 740, 46, keys=0)
    d.column("PH", ["历史编号", "价格", "变更类型", "生效时间"], 1400, 1040, 40)
    d.save("er_local_1_user_listing", "粗线表示全参与（每个商品必须有卖家与分类）；双线矩形为弱实体；带下划线的属性为主键")


def local_trade():
    d = Diagram(1880, 1010, "局部 E-R 图（二）：交易与核实子系统")
    d.entity("L", 260, 150, "商品")
    d.entity("U", 260, 520, "用户")
    d.entity("O", 860, 330, "订单")
    d.entity("R", 1420, 190, "核实单")
    d.entity("S", 1420, 570, "评分事件")
    d.relation("deal", 560, 240, "成交")
    d.relation("buy", 560, 425, "购买")
    d.relation("review", 1140, 260, "核实")
    d.relation("trigger", 1140, 450, "触发")
    d.relation("earn", 860, 830, "获得")
    d.relation("handle", 860, 930, "处理")
    d.link("L", "deal", "1"); d.link("O", "deal", "N", total=True)
    d.link("U", "buy", "1"); d.link("O", "buy", "N", total=True)
    d.link("O", "review", "1"); d.link("R", "review", "N", total=True)
    d.link("O", "trigger", "1"); d.link("S", "trigger", "N", total=True)
    d.link("U", "earn", "1", via=[(260, 830)]); d.link("S", "earn", "N", total=True, via=[(1420, 830)])
    d.link("U", "handle", "1", via=[(260, 930)]); d.link("R", "handle", "N", via=[(1560, 190), (1560, 930)])
    d.column("O", ["订单编号", "价格快照", "状态", "下单时间", "付款截止", "付款时间"], 740, 580, 44)
    d.column("O", ["交付时间", "自动完成时间", "完成时间", "完成方式", "取消时间", "取消原因"], 990, 580, 44, keys=0)
    d.column("R", ["核实编号", "原因", "原状态", "提交时间", "结论", "处理时间"], 1720, 190, 40)
    d.column("S", ["评分事件编号", "评分类型", "原因", "变动分值", "发生时间"], 1720, 570, 40)
    d.save("er_local_2_trade", "“处理”联系中的用户为管理员角色；“获得”联系记录买家奖励分与卖家信誉分；粗线 = 全参与")


def local_points():
    d = Diagram(1500, 760, "局部 E-R 图（三）：积分账户与复式记账子系统")
    d.entity("U", 250, 200, "用户")
    d.entity("O", 1250, 200, "订单")
    d.entity("A", 250, 530, "积分账户")
    d.entity("B", 750, 530, "积分流水")
    d.entity("T", 1250, 530, "积分转移")
    d.relation("own", 250, 365, "拥有")
    d.relation("produce", 1250, 365, "产生")
    d.relation("post", 500, 530, "记入")
    d.relation("contain", 1000, 530, "包含")
    d.link("U", "own", "1"); d.link("A", "own", "1")
    d.link("O", "produce", "1"); d.link("T", "produce", "N")
    d.link("A", "post", "1"); d.link("B", "post", "N", total=True)
    d.link("T", "contain", "1"); d.link("B", "contain", "2", total=True)
    d.attr_at("U", "用户编号", 250, 105, key=True)
    d.attr_at("O", "订单编号", 1250, 105, key=True)
    d.row("A", ["账户编号", "账户类型", "余额"], 650, 250, 140)
    d.row("B", ["流水编号", "变动积分"], 650, 750, 150)
    d.row("T", ["转移编号", "事件类型", "发生时间"], 650, 1250, 140)
    d.save("er_local_3_points", "平台托管账户、发行账户不属于任何用户；注册发放（GRANT）类转移不对应订单；每次转移恰好包含 2 条流水")


# =====================================================================
# 基本 E-R 图（合并、消除冗余后的全局图，仅保留主键）
# =====================================================================
def basic():
    d = Diagram(1760, 1080, "航小鱼 基本 E-R 图（全局）")
    d.entity("C", 180, 160, "分类")
    d.entity("L", 760, 160, "商品")
    d.entity("PH", 1320, 160, "价格历史", weak=True)
    d.entity("V", 180, 520, "估价记录")
    d.entity("U", 760, 520, "用户")
    d.entity("O", 1320, 520, "订单")
    d.entity("R", 1620, 330, "核实单")
    d.entity("S", 1620, 760, "评分事件")
    d.entity("A", 760, 900, "积分账户")
    d.entity("B", 1040, 900, "积分流水")
    d.entity("T", 1320, 900, "积分转移")
    d.relation("belong", 470, 160, "归属")
    d.relation("rep", 1040, 160, "调价")
    d.relation("ref", 180, 340, "参照")
    d.relation("apply", 470, 520, "申请")
    d.relation("pub", 660, 340, "发布")
    d.relation("fav", 860, 340, "收藏")
    d.relation("deal", 1040, 340, "成交")
    d.relation("buy", 1040, 520, "购买")
    d.relation("review", 1470, 425, "核实")
    d.relation("handle", 1320, 300, "处理")
    d.relation("trigger", 1470, 640, "触发")
    d.relation("earn", 1100, 720, "获得")
    d.relation("own", 760, 710, "拥有")
    d.relation("post", 900, 980, "记入")
    d.relation("contain", 1180, 980, "包含")
    d.relation("produce", 1320, 710, "产生")
    d.link("C", "belong", "1"); d.link("L", "belong", "N", total=True)
    d.link("L", "rep", "1"); d.link("PH", "rep", "N", total=True)
    d.link("C", "ref", "1"); d.link("V", "ref", "N", total=True)
    d.link("U", "apply", "1"); d.link("V", "apply", "N", total=True)
    d.link("U", "pub", "1"); d.link("L", "pub", "N", total=True)
    d.link("U", "fav", "M"); d.link("L", "fav", "N")
    d.link("L", "deal", "1"); d.link("O", "deal", "N", total=True)
    d.link("U", "buy", "1"); d.link("O", "buy", "N", total=True)
    d.link("O", "review", "1"); d.link("R", "review", "N", total=True)
    d.link("U", "handle", "1", via=[(860, 445), (1240, 445)]); d.link("R", "handle", "N")
    d.link("O", "trigger", "1"); d.link("S", "trigger", "N", total=True)
    d.link("U", "earn", "1"); d.link("S", "earn", "N", total=True)
    d.link("U", "own", "1"); d.link("A", "own", "1")
    d.link("A", "post", "1", via=[(760, 980)]); d.link("B", "post", "N", total=True, via=[(1040, 980)])
    d.link("T", "contain", "1", via=[(1320, 980)]); d.link("B", "contain", "2", total=True, via=[(1040, 980)])
    d.link("O", "produce", "1"); d.link("T", "produce", "N")
    d.attr_at("fav", "收藏时间", 960, 420)
    for key, label, x, y in [("C", "分类编号", 180, 80), ("L", "商品编号", 760, 80), ("PH", "历史编号", 1320, 80),
                             ("V", "估价编号", 180, 610), ("U", "用户编号", 640, 600), ("O", "订单编号", 1200, 600),
                             ("R", "核实编号", 1620, 250), ("S", "评分事件编号", 1620, 850), ("A", "账户编号", 600, 900),
                             ("B", "流水编号", 1040, 820), ("T", "转移编号", 1480, 900)]:
        d.attr_at(key, label, x, y, key=True)
    d.save("er_basic", "11 个实体、16 个联系；只标出主键，完整属性见各局部 E-R 图与关系模式。粗线 = 全参与")


if __name__ == "__main__":
    local_user_listing()
    local_trade()
    local_points()
    basic()
