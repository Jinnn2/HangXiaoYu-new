# 航小鱼 · 校园二手交易与智能估价平台

《数据库系统原理》大作业。PostgreSQL + FastAPI + React。

**所有数据库操作均为原生 SQL**：建表、约束、索引、触发器、存储过程、视图都是手写 SQL 脚本；后端只用 psycopg 驱动执行手写的 SQL 字符串（参数绑定），不使用任何 ORM。前端只调用 HTTP 接口。

| 文档 | 内容 |
| --- | --- |
| [docs/系统设计报告.md](docs/系统设计报告.md) | 需求分析、功能设计、数据流图、数据元素表、初步 / 基本 E-R 图、关系模式、范式分析、优化、物理设计 |
| [docs/系统实现报告.md](docs/系统实现报告.md) | 架构、基本表、触发器与存储过程、SQL 运行结果、前端技术 |
| [docs/er/](docs/er/) | 陈氏 E-R 图（SVG + PNG，由 `draw_er.py` 生成） |
| [docs/sql_demo.sql](docs/sql_demo.sql) | 各功能的 SQL 演示脚本与 [运行结果](docs/sql_demo_output.txt) |
| [购买规则.md](购买规则.md) | 交易业务规则 |
| [前后端功能对接说明.md](前后端功能对接说明.md) | HTTP 接口清单 |

## 目录

```text
db/         数据库：01_schema … 08_views、09_seed 演示数据、install.sql、run_tests.py、tests/
backend/    FastAPI 服务器端（app/db.py 是唯一的数据库访问层）
frontend/   React + Vite + Tailwind 客户端
docs/       报告、E-R 图、截图、SQL 演示
legacy/     早期独立交易模块（trade_demo schema，保留作过程记录，仍可独立运行其自测）
```

## 本地运行（Windows）

需要：PostgreSQL 18（16 以上即可）、Python 3.11+、Node.js 20+。下面的命令在 PowerShell 中、仓库根目录执行。

**1. 建库并安装**（会提示输入 postgres 密码）

```powershell
$env:Path += ";C:\Program Files\PostgreSQL\18\bin"
createdb -U postgres hangxiaoyu
psql -U postgres -d hangxiaoyu -v ON_ERROR_STOP=1 -f db/install.sql
psql -U postgres -d hangxiaoyu -v ON_ERROR_STOP=1 -f db/09_seed.sql
```

使用 pgAdmin 时：在 Query Tool 中按顺序打开并执行 `db/01_schema.sql` 到 `db/08_views.sql`，再执行 `db/09_seed.sql`。

**2. 后端**

```powershell
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
copy .env.example .env      # 然后编辑 .env，填数据库密码
.venv\Scripts\uvicorn app.main:app --reload --port 8000
```

**3. 前端**（另开一个终端）

```powershell
cd frontend
npm install
npm run dev                 # 打开 http://localhost:5173
```

演示或部署时也可以 `npm run build`，之后只需启动后端，访问 http://localhost:8000 即可（后端会一并提供前端页面）。

**演示账号**（密码均为 `123456`）：买家 `23370001`（林同学）、卖家 `23370002`（王同学）、管理员 `admin`。演示数据里已有在售商品、历史成交、待交付 / 待收货 / 待核实的订单。

课堂演示自动确认收货时，可在 `backend/.env` 设置 `HXY_AUTO_COMPLETE_SECONDS=120`，卖家交付 2 分钟后自动完成（规则为 24 小时）。

## 测试

```powershell
python db/run_tests.py
```

在临时目录启动一个隔离的 PostgreSQL 实例（端口 55432），安装全部脚本，运行 `db/tests/` 下的 SQL 测试（共 135 项检查）、双会话并发测试和演示数据对账，结束后自动删除，不会碰任何已有数据库。只需要 PostgreSQL 自带的命令行工具；如果自动找不到，加 `--pg-bin "C:\Program Files\PostgreSQL\18\bin"`。

```powershell
cd backend
$env:HXY_TEST_ADMIN_URL = "postgresql://postgres:密码@127.0.0.1:5432/postgres"
.venv\Scripts\python -m pytest tests
```

API 测试会新建（并覆盖）一个名为 `hxy_api_test` 的数据库。

## 当前状态

按协作说明的要求区分三种状态：

| 功能 | 数据库（SQL 已验证） | 后端接口已接入 | 前端已展示 |
| --- | :-: | :-: | :-: |
| 注册登录、个人资料、改密码 | ✓ | ✓ | ✓ |
| 商品发布、修改、改价与价格历史、上下架、删除 | ✓ | ✓ | ✓ |
| 搜索、分类、排序、收藏 | ✓ | ✓ | ✓ |
| 智能估价（同款比价、成交记录与走势、同款在售）、估价记录、分类行情 | ✓ | ✓ | ✓ |
| 下单、付款托管、取消、交付、确认收货 | ✓ | ✓ | ✓ |
| 申请取消、未收到反馈、管理员核实与退款、超时处罚 | ✓ | ✓ | ✓ |
| 定时任务（付款超时、自动完成、交付超时、缓冲期满上架） | ✓ | ✓ 每 30 秒调度 | 管理后台可手动触发 |
| 封禁用户、禁止再售、新增分类、平台对账 | ✓ | ✓ | ✓ |
| 个人看板（待办、余额走势、30 天收支、交易统计） | ✓ | ✓ | ✓ |
| 管理后台看板（每日成交、订单状态分布、分类与卖家排行、需要关注） | ✓ | ✓ | ✓ |

尚未实现：商品图片上传（目前填图片链接，不填则显示分类封面）、站内消息通知、物流信息、成交后售后申诉。

本仓库尚未选择开源许可证，仅用于组内课程协作。
