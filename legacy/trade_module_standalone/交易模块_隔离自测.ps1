# 在临时本地 PostgreSQL 实例中依次验证建表、初始化、交易闭环、异常退款、改价。
# 不连接 hangxiaoyu_trade_demo；不会修改 pgAdmin 中的演示订单。
$ErrorActionPreference = 'Stop'
$projectDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$testDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir '.pgtest_run'))
$initdb = 'C:\Program Files\PostgreSQL\18\bin\initdb.exe'
$pgCtl = 'C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe'
$psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
$serverStarted = $false

if (Test-Path -LiteralPath $testDir) {
    throw "测试目录已经存在，请先检查：$testDir"
}

try {
    & $initdb -D $testDir -U demo_test --auth=trust --encoding=UTF8 --locale=C --no-instructions
    if ($LASTEXITCODE -ne 0) { throw 'initdb 失败' }

    & $pgCtl -D $testDir -l (Join-Path $testDir 'server.log') -o '-p 55432 -h 127.0.0.1' -w start
    if ($LASTEXITCODE -ne 0) { throw '隔离测试实例启动失败' }
    $serverStarted = $true

    $files = @(
        '交易模块_独立建表草案.sql',
        '交易模块_独立初始化与核对.sql',
        '交易模块_流水完整性触发器.sql',
        '交易模块_交付与成交结算函数草案.sql',
        '交易模块_交付结算自测.sql',
        '交易模块_异常核实与退款函数草案.sql',
        '交易模块_异常退款自测.sql',
        '交易模块_下单取消与到期任务函数草案.sql',
        '交易模块_商品改价与价格历史函数草案.sql',
        '交易模块_价格历史自测.sql',
        '交易模块_账户与订单查询视图.sql',
        '交易模块_阶段核对查询.sql'
    )
    foreach ($file in $files) {
        Write-Output "RUN $file"
        & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir $file)
        if ($LASTEXITCODE -ne 0) { throw "SQL 执行失败：$file" }
    }
    $prepFile = '交易模块_付款回归自测准备.sql'
    Write-Output "RUN $prepFile"
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir $prepFile)
    if ($LASTEXITCODE -ne 0) { throw "SQL 执行失败：$prepFile" }
    $orderId = (& $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -A -t -v ON_ERROR_STOP=1 -c 'SELECT order_id FROM trade_demo.trade_order WHERE listing_id = 5008').Trim()
    if ($LASTEXITCODE -ne 0 -or $orderId -notmatch '^[0-9]+$') { throw '无法取得付款自测订单编号' }
    $paymentTemplate = [System.IO.File]::ReadAllText((Join-Path $projectDir '交易模块_付款进入平台托管事务草案.sql'))
    if (-not $paymentTemplate.Contains('v_order_id BIGINT := NULL;') -or -not $paymentTemplate.Contains('WHERE o.order_id = 0')) {
        throw '付款脚本占位符与自测脚本不匹配'
    }
    $paymentSql = $paymentTemplate.Replace('v_order_id BIGINT := NULL;', "v_order_id BIGINT := $orderId;").Replace('WHERE o.order_id = 0', "WHERE o.order_id = $orderId")
    $paymentFile = Join-Path $testDir 'payment_run.sql'
    [System.IO.File]::WriteAllText($paymentFile, $paymentSql, [System.Text.UTF8Encoding]::new($false))
    Write-Output "RUN 付款脚本回归自测（订单 $orderId）"
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f $paymentFile
    if ($LASTEXITCODE -ne 0) { throw '付款脚本回归自测失败' }
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir '交易模块_付款回归自测核对.sql')
    if ($LASTEXITCODE -ne 0) { throw '付款结果核对失败' }
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir '交易模块_下单到期自测.sql')
    if ($LASTEXITCODE -ne 0) { throw '下单与到期任务自测失败' }
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir '交易模块_并发自测准备.sql')
    if ($LASTEXITCODE -ne 0) { throw '并发自测数据准备失败' }
    & python -X utf8 (Join-Path $projectDir '交易模块_并发自测.py') --psql $psql
    if ($LASTEXITCODE -ne 0) { throw '双会话并发自测失败' }
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir '交易模块_并发自测核对.sql')
    if ($LASTEXITCODE -ne 0) { throw '并发自测数据库核对失败' }
    & $psql -h 127.0.0.1 -p 55432 -U demo_test -d postgres -X -v ON_ERROR_STOP=1 -f (Join-Path $projectDir '交易模块_流水约束自测.sql')
    if ($LASTEXITCODE -ne 0) { throw '流水完整性约束自测失败' }
    Write-Output 'PASS: 所有隔离测试 SQL 执行成功。'
}
finally {
    if ($serverStarted) {
        & $pgCtl -D $testDir -m fast -w stop
    }
    $insideProject = $testDir.StartsWith(
        $projectDir + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )
    if (-not $insideProject -or [System.IO.Path]::GetFileName($testDir) -ne '.pgtest_run') {
        throw "拒绝清理意外路径：$testDir"
    }
    if (Test-Path -LiteralPath $testDir) {
        Remove-Item -LiteralPath $testDir -Recurse -Force
    }
}
