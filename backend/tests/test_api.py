"""端到端 API 测试：覆盖增删改查与完整交易流程。"""


def test_auth_and_permissions(anon, lin):
    assert anon.get("/api/auth/me").status_code == 401
    r = anon.post("/api/auth/login", json={"student_no": "23370001", "password": "bad"})
    assert r.status_code == 401
    me = lin.get("/api/auth/me").json()
    assert me["display_name"] == "林同学" and me["spendable_points"] > 0
    assert lin.get("/api/admin/stats").status_code == 403


def test_register_validation(anon):
    r = anon.post("/api/auth/register", json={"student_no": "99990001", "display_name": "新同学", "password": "abcdef"})
    assert r.status_code == 200 and r.json()["spendable_points"] == 500
    r = anon.post("/api/auth/register", json={"student_no": "99990001", "display_name": "重复", "password": "abcdef"})
    assert r.status_code == 400 and "已注册" in r.json()["detail"]
    r = anon.post("/api/auth/register", json={"student_no": "x!", "display_name": "坏学号", "password": "abcdef"})
    assert r.status_code == 422


def test_search_is_parameterized(anon):
    # 典型注入字符串只会被当作普通搜索词
    r = anon.get("/api/listings", params={"q": "' OR 1=1; DROP TABLE hxy.listing; --"})
    assert r.status_code == 200 and r.json()["total"] == 0
    r = anon.get("/api/listings", params={"sort": "price_asc"})
    prices = [i["current_price_points"] for i in r.json()["items"]]
    assert prices == sorted(prices) and len(prices) >= 5
    cats = anon.get("/api/categories").json()
    digital = next(c for c in cats if c["name"] == "数码电子")["category_id"]
    r = anon.get("/api/listings", params={"category_id": digital})
    assert all(i["category_name"] == "数码电子" for i in r.json()["items"])


def test_listing_crud(wang):
    cats = wang.get("/api/categories").json()
    body = {"category_id": cats[0]["category_id"], "title": "测试耳机", "description": "九成新",
            "condition_level": 4, "original_price_points": 300, "current_price_points": 150}
    item = wang.post("/api/listings", json=body).json()
    lid = item["listing_id"]
    assert item["price_history"][0]["change_type"] == "INITIAL"
    body.pop("current_price_points")
    body["title"] = "测试耳机（已改名）"
    assert wang.put(f"/api/listings/{lid}", json=body).json()["title"] == "测试耳机（已改名）"
    item = wang.post(f"/api/listings/{lid}/reprice", json={"price": 120}).json()
    assert item["current_price_points"] == 120 and len(item["price_history"]) == 2
    assert wang.post(f"/api/listings/{lid}/off-shelf").json()["status"] == "OFF_SHELF"
    assert wang.post(f"/api/listings/{lid}/on-shelf").json()["status"] == "ON_SALE"
    assert wang.delete(f"/api/listings/{lid}").status_code == 200
    assert wang.get(f"/api/listings/{lid}").status_code == 404


def test_full_purchase_flow(lin, wang):
    cats = wang.get("/api/categories").json()
    lid = wang.post("/api/listings", json={
        "category_id": cats[0]["category_id"], "title": "流程测试商品", "condition_level": 3,
        "original_price_points": 100, "current_price_points": 40}).json()["listing_id"]
    before = lin.get("/api/auth/me").json()["spendable_points"]

    r = lin.post("/api/orders", json={"listing_id": lid, "expected_price": 39})
    assert r.status_code == 400 and "价格已变为 40" in r.json()["detail"]
    order = lin.post("/api/orders", json={"listing_id": lid, "expected_price": 40}).json()
    oid = order["order_id"]
    assert order["status"] == "PENDING_PAYMENT" and order["my_role"] == "buyer"
    assert wang.post(f"/api/orders/{oid}/pay").status_code == 400  # 卖家不能替买家付款
    assert lin.post(f"/api/orders/{oid}/pay").json()["status"] == "PENDING_DELIVERY"
    assert lin.get("/api/auth/me").json()["spendable_points"] == before - 40
    assert wang.post(f"/api/orders/{oid}/deliver").json()["status"] == "PENDING_RECEIPT"
    order = lin.post(f"/api/orders/{oid}/confirm").json()
    assert order["status"] == "COMPLETED" and order["completion_method"] == "BUYER_CONFIRMED"
    assert len(order["transfers"]) == 4
    assert any(o["order_id"] == oid for o in wang.get("/api/me/orders", params={"role": "seller"}).json())
    ledger = lin.get("/api/me/ledger").json()
    assert ledger[0]["order_id"] == oid and ledger[0]["delta_points"] == -40


def test_review_and_admin(lin, wang, admin):
    cats = wang.get("/api/categories").json()
    lid = wang.post("/api/listings", json={
        "category_id": cats[0]["category_id"], "title": "核实测试商品", "condition_level": 3,
        "current_price_points": 30}).json()["listing_id"]
    oid = lin.post("/api/orders", json={"listing_id": lid}).json()["order_id"]
    lin.post(f"/api/orders/{oid}/pay")
    assert lin.post(f"/api/orders/{oid}/request-cancel").json()["status"] == "UNDER_REVIEW"
    reviews = admin.get("/api/admin/reviews").json()
    rid = next(r["review_id"] for r in reviews if r["order_id"] == oid)
    assert admin.post(f"/api/admin/reviews/{rid}/resolve", json={"decision": "CANCEL"}).status_code == 200
    assert lin.get(f"/api/orders/{oid}").json()["status"] == "CANCELED"
    assert wang.get(f"/api/listings/{lid}").json()["status"] == "RELIST_BUFFER"
    stats = admin.get("/api/admin/stats").json()
    assert stats["balance_sum"] == 0 and stats["mismatched_accounts"] == 0
    assert admin.post("/api/admin/tasks/run").status_code == 200


def test_favorites_and_valuations(lin):
    items = lin.get("/api/listings").json()["items"]
    lid = next(i["listing_id"] for i in items if i["seller_name"] != "林同学")
    assert lin.put(f"/api/listings/{lid}/favorite").json()["is_favorite"]
    assert lin.put(f"/api/listings/{lid}/favorite").status_code == 200  # 幂等
    assert any(f["listing_id"] == lid for f in lin.get("/api/me/favorites").json())
    assert lin.delete(f"/api/listings/{lid}/favorite").json()["is_favorite"] is False

    cats = lin.get("/api/categories").json()
    est = lin.post("/api/valuations/estimate", json={
        "category_id": cats[0]["category_id"], "condition_level": 4, "original_price": 1000}).json()
    assert est["low_price_points"] <= est["suggested_price_points"] <= est["high_price_points"]
    v = lin.post("/api/valuations", json={"category_id": cats[0]["category_id"], "item_name": "测试相机",
                                          "condition_level": 4, "original_price": 1000}).json()
    assert v["suggested_price_points"] == est["suggested_price_points"]
    assert lin.delete(f"/api/valuations/{v['valuation_id']}").status_code == 200
    assert lin.delete(f"/api/valuations/{v['valuation_id']}").status_code == 404


def test_dashboards(lin, admin):
    d = lin.get("/api/me/dashboard").json()
    assert d["summary"]["display_name"] == "林同学"
    assert len(d["flow"]) == 30 and d["flow"][-1]["closing_balance"] == d["summary"]["spendable_points"]
    assert d["stats"]["bought_count"] >= 1
    assert all(t["action"] in ("PAY", "CONFIRM", "DELIVER") for t in d["todos"])
    a = admin.get("/api/admin/dashboard").json()
    assert len(a["daily"]) == 14 and sum(x["completed_orders"] for x in a["daily"]) >= 1
    assert a["top_sellers"] and a["categories"]
    assert lin.get("/api/admin/dashboard").status_code == 403


def test_same_item_valuation(anon):
    cats = anon.get("/api/categories").json()
    digital = next(c for c in cats if c["name"] == "数码电子")["category_id"]
    r = anon.post("/api/valuations/estimate", json={"category_id": digital, "condition_level": 4,
                                                   "original_price": 249, "item_name": "小米手环 8"}).json()
    assert r["basis"] == "SAME_ITEM" and r["same_item_count"] == 2
    assert sum(1 for x in r["samples"] if x["same_item"]) == 2 and r["samples"][0]["same_item"]
    assert r["listing_count"] >= 1 and r["listings"][0]["current_price_points"] == r["listing_min"]
