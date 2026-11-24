"""运行配置，全部来自环境变量（可写在 backend/.env，见 .env.example）。"""

import os
from pathlib import Path


def _load_dotenv() -> None:
    env_file = Path(__file__).resolve().parent.parent / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


_load_dotenv()

# psycopg 连接串，例如 postgresql://postgres:密码@127.0.0.1:5432/hangxiaoyu
DATABASE_URL = os.environ.get("HXY_DATABASE_URL", "postgresql://postgres@127.0.0.1:5432/hangxiaoyu")
# 会话 Cookie 签名密钥；部署时务必修改
SECRET_KEY = os.environ.get("HXY_SECRET_KEY", "dev-only-change-me")
# 卖家交付后多久自动完成（秒）。规则为 24 小时；课堂演示可设为 120。
AUTO_COMPLETE_SECONDS = int(os.environ.get("HXY_AUTO_COMPLETE_SECONDS", str(24 * 3600)))
# 后台定时任务间隔（秒）；设为 0 关闭
TASK_INTERVAL_SECONDS = int(os.environ.get("HXY_TASK_INTERVAL_SECONDS", "30"))
# 前端构建产物目录（存在时由后端一并提供）
FRONTEND_DIST = Path(os.environ.get(
    "HXY_FRONTEND_DIST", Path(__file__).resolve().parents[2] / "frontend" / "dist")).resolve()
