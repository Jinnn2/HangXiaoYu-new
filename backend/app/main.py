"""航小鱼后端入口。

启动：在 backend 目录执行
    uvicorn app.main:app --reload --port 8000
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from psycopg import Error as DatabaseError
from starlette.middleware.sessions import SessionMiddleware

from . import config
from .db import BusinessError, fetch_one, fetch_value, pool, to_business_error
from .routers import admin, auth, listings, orders, valuations

log = logging.getLogger("hangxiaoyu")


async def scheduler() -> None:
    """定时调用数据库中的到期任务入口：付款超时、自动完成、交付超时核实、缓冲期满上架。"""
    while True:
        await asyncio.sleep(config.TASK_INTERVAL_SECONDS)
        try:
            result = await asyncio.to_thread(fetch_one, "SELECT * FROM hxy.run_scheduled_tasks()")
            if result and any(result.values()):
                log.info("定时任务：%s", result)
        except Exception:  # noqa: BLE001 —— 单次失败不影响下一轮
            log.exception("定时任务执行失败")


@asynccontextmanager
async def lifespan(_: FastAPI):
    pool.open(wait=True)
    task = asyncio.create_task(scheduler()) if config.TASK_INTERVAL_SECONDS > 0 else None
    yield
    if task:
        task.cancel()
    pool.close()


app = FastAPI(title="航小鱼 API", lifespan=lifespan)
app.add_middleware(SessionMiddleware, secret_key=config.SECRET_KEY,
                   session_cookie="hxy_session", same_site="lax", max_age=7 * 24 * 3600)


@app.exception_handler(BusinessError)
async def business_error_handler(_: Request, exc: BusinessError):
    return JSONResponse({"detail": exc.message}, status_code=exc.status)


@app.exception_handler(DatabaseError)
async def database_error_handler(_: Request, exc: DatabaseError):
    err = to_business_error(exc)
    if err is None:
        log.exception("数据库错误", exc_info=exc)
        return JSONResponse({"detail": "服务器内部错误"}, status_code=500)
    return JSONResponse({"detail": err.message}, status_code=err.status)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_: Request, exc: RequestValidationError):
    first = exc.errors()[0] if exc.errors() else {}
    field = ".".join(str(p) for p in first.get("loc", [])[1:])
    return JSONResponse({"detail": f"参数 {field} 不正确：{first.get('msg', '')}"}, status_code=422)


for r in (auth.router, listings.router, orders.router, valuations.router, admin.router):
    app.include_router(r)


@app.get("/api/health")
def health():
    return {"ok": True, "server_time": fetch_value("SELECT clock_timestamp()"),
            "auto_complete_seconds": config.AUTO_COMPLETE_SECONDS}


# 前端构建产物（npm run build 之后）由后端一并提供；单页应用的其他路径都返回 index.html。
if config.FRONTEND_DIST.joinpath("index.html").exists():
    app.mount("/assets", StaticFiles(directory=config.FRONTEND_DIST / "assets"), name="assets")

    @app.get("/{path:path}", include_in_schema=False)
    def spa(path: str):
        file = config.FRONTEND_DIST / path
        if path and file.is_file() and config.FRONTEND_DIST in file.resolve().parents:
            return FileResponse(file)
        return FileResponse(config.FRONTEND_DIST / "index.html")
