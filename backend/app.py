# -*- coding: utf-8 -*-
"""
NCS 充电桩可视化大屏 — Flask 后端
单文件版：配置 + 数据库封装 + 路由全部在此
启动：python app.py
访问：http://127.0.0.1:5000/api/health
"""
import pymysql
from flask import Flask, jsonify
from flask_cors import CORS

# ============================================================
# 配置
# ============================================================
DB_CONFIG = {
    "host": "192.168.176.100",
    "port": 3306,
    "user": "root",
    "password": "123456",
    "database": "ncs_ads",
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
}

# ============================================================
# 数据库封装
# ============================================================
def get_conn():
    """获取数据库连接（短连接，每次查询新建）"""
    return pymysql.connect(**DB_CONFIG)


def query_all(sql):
    """执行查询，返回字典列表"""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchall()
    finally:
        conn.close()


def query_one(sql):
    """执行查询，返回单条字典"""
    rows = query_all(sql)
    return rows[0] if rows else None


def db_alive():
    """检查数据库是否连通"""
    try:
        conn = get_conn()
        conn.ping(reconnect=False)
        conn.close()
        return True
    except Exception:
        return False


# ============================================================
# Flask 应用
# ============================================================
app = Flask(__name__)
CORS(app)  # 允许跨域，前端开发时直接调


def success(data):
    """统一成功返回"""
    return jsonify({"code": 0, "msg": "success", "data": data})


def error(msg):
    """统一失败返回"""
    return jsonify({"code": 500, "msg": msg, "data": None})


# ============================================================
# 路由
# ============================================================

@app.get("/api/health")
def health():
    """探活：检查数据库连通性"""
    alive = db_alive()
    return success({
        "status": "ok" if alive else "db_down",
        "db_alive": alive,
    })


@app.get("/api/kpi")
def kpi():
    """顶部 5 个 KPI 卡片"""
    row = query_one("SELECT * FROM ads_kpi_overview")
    return success(row if row else {})


@app.get("/api/platform")
def platform():
    """用户平台偏好分布（环形图）"""
    rows = query_all("SELECT * FROM ads_platform_dist ORDER BY user_count DESC")
    return success(rows)


@app.get("/api/hour-trend")
def hour_trend():
    """24 小时充电趋势（柱+折线）"""
    rows = query_all("SELECT * FROM ads_hour_trend ORDER BY hour")
    return success(rows)


@app.get("/api/station-type")
def station_type():
    """充电站类型偏好（环形图）"""
    rows = query_all("SELECT * FROM ads_station_type_eff ORDER BY utilization_rate DESC")
    return success(rows)


@app.get("/api/station-top10")
def station_top10():
    """运营效率 TOP10 站点（横向柱状）"""
    rows = query_all("SELECT * FROM ads_station_topn ORDER BY rn")
    return success(rows)


@app.get("/api/soc-radar")
def soc_radar():
    """不同起始 SOC 行为雷达图
    TODO: 待补 DWS 聚合表，当前返回空数组
    """
    return success([])


@app.get("/api/hour-area")
def hour_area():
    """24 小时各区域充电分布（堆叠柱状）"""
    rows = query_all("SELECT * FROM ads_hour_area ORDER BY hour, station_area")
    return success(rows)


@app.get("/api/area-kpi")
def area_kpi():
    """区域充电量与营收（环形图 + 区域对比柱状）"""
    rows = query_all("SELECT * FROM ads_area_cost ORDER BY total_kwh DESC")
    return success(rows)


@app.get("/api/user-level")
def user_level():
    """用户等级分布"""
    rows = query_all("SELECT * FROM ads_user_level_dist ORDER BY user_count DESC")
    return success(rows)


@app.get("/api/week-compare")
def week_compare():
    """工作日 vs 周末对比"""
    rows = query_all("SELECT * FROM ads_week_compare")
    return success(rows)


@app.get("/api/battery-health")
def battery_health():
    """电池健康/SOC 档位占比"""
    rows = query_all("SELECT * FROM ads_battery_health ORDER BY ratio DESC")
    return success(rows)


@app.get("/api/user-radar")
def user_radar():
    """用户等级行为雷达图（备用）"""
    rows = query_all("SELECT * FROM ads_user_radar ORDER BY user_level, dim_name")
    return success(rows)


# ============================================================
# 全局异常处理
# ============================================================
@app.errorhandler(Exception)
def handle_exception(e):
    return error(str(e)), 500


# ============================================================
# 启动
# ============================================================
if __name__ == "__main__":
    print("=" * 50)
    print("  NCS 充电桩大屏后端启动中...")
    print(f"  数据库: {DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}")
    print("  访问: http://127.0.0.1:5000/api/health")
    print("=" * 50)
    app.run(host="0.0.0.0", port=5000, debug=True)
