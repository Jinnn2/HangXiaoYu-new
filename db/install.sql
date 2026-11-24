-- 一键安装（psql 专用）：psql -d 新数据库 -v ON_ERROR_STOP=1 -f db/install.sql
-- 使用 pgAdmin 时请按编号顺序依次打开 01~08（演示数据再执行 09）。
\ir 01_schema.sql
\ir 02_indexes.sql
\ir 03_triggers.sql
\ir 04_functions_user.sql
\ir 05_functions_listing.sql
\ir 06_functions_valuation.sql
\ir 07_functions_trade.sql
\ir 08_views.sql
