# NCS 充电桩可视化大屏 — 后端接口文档

## 一、概述

### 1.1 项目简介
本接口为「东软 NCS 电动汽车充电桩应用管理平台」可视化大屏提供数据服务。后端基于 Flask，数据来源为 MySQL `ncs_ads` 库（由 Hive/Spark 数仓 ETL 导出）。

### 1.2 基础 URL
```
http://192.168.176.100:5000
```
（虚拟机 IP，Flask 默认端口 5000；本地开发可用 `http://127.0.0.1:5000`）

### 1.3 数据格式
- 所有接口返回 `application/json`
- 字符编码：UTF-8
- 请求方式：全部为 `GET`，无请求参数

### 1.4 通用返回格式
```json
{
  "code": 200,
  "message": "success",
  "data": { }
}
```
- `code`：状态码，200=成功，500=服务器错误
- `message`：状态描述
- `data`：实际数据，对象或数组

---

## 二、接口详情

### 2.1 顶部 KPI 总览

- **接口路径**：`GET /api/kpi`
- **对应组件**：大屏顶部 5 个数字卡片
- **数据来源**：`ncs_ads.ads_kpi_overview`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| sessions | int | 累计充电次数 |
| total_kwh | float | 累计充电量（度） |
| total_fee | float | 累计营收（元） |
| station_count | int | 充电站总数 |
| abnormal_rate | float | BMS 明细缺失率（%） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": {
    "sessions": 3340,
    "total_kwh": 28560.50,
    "total_fee": 103064.00,
    "station_count": 105,
    "abnormal_rate": 52.8
  }
}
```

---

### 2.2 用户平台偏好分布

- **接口路径**：`GET /api/platform`
- **对应组件**：左侧环形图（用户平台偏好）
- **数据来源**：`ncs_ads.ads_platform_dist`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| phone_type | string | 平台名称（iOS / Android / Web） |
| user_count | int | 用户数 |
| sessions | int | 充电次数 |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"phone_type": "iOS", "user_count": 35, "sessions": 1200},
    {"phone_type": "Android", "user_count": 42, "sessions": 1850},
    {"phone_type": "Web", "user_count": 7, "sessions": 290}
  ]
}
```

---

### 2.3 各时段充电趋势

- **接口路径**：`GET /api/hour-trend`
- **对应组件**：中间柱状图+折线图（24 小时充电趋势）
- **数据来源**：`ncs_ads.ads_hour_trend`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| hour | int | 小时（0-23） |
| sessions | int | 该小时充电次数 |
| total_kwh | float | 该小时充电量（度） |
| is_peak | int | 是否高峰（1=是，0=否） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"hour": 0, "sessions": 45, "total_kwh": 320.5, "is_peak": 0},
    {"hour": 1, "sessions": 30, "total_kwh": 210.0, "is_peak": 0},
    {"hour": 18, "sessions": 280, "total_kwh": 2100.5, "is_peak": 1}
  ]
}
```

---

### 2.4 充电站类型偏好

- **接口路径**：`GET /api/station-type`
- **对应组件**：右侧环形图（充电站类型偏好）
- **数据来源**：`ncs_ads.ads_station_type_eff`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| gun_type | string | 桩类型（交流桩 / 直流桩 / 交直流一体桩 / 其他类型） |
| utilization_rate | float | 相对负载率（%） |
| daily_kwh | float | 单桩平均电量（度） |
| avg_fee_per_kwh | float | 平均每度费用（元） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"gun_type": "交流桩", "utilization_rate": 45.2, "daily_kwh": 120.5, "avg_fee_per_kwh": 0.8},
    {"gun_type": "直流桩", "utilization_rate": 100.0, "daily_kwh": 350.0, "avg_fee_per_kwh": 1.2}
  ]
}
```

---

### 2.5 运营效率 TOP 充电站

- **接口路径**：`GET /api/station-top10`
- **对应组件**：右侧横向柱状图（TOP10 站点）
- **数据来源**：`ncs_ads.ads_station_topn`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| rn | int | 排名（1-10） |
| station_name | string | 站点名称 |
| station_area | string | 所属区域 |
| total_sessions | int | 总充电次数 |
| total_kwh | float | 总充电量（度） |
| total_fee | float | 总费用（元） |
| utilization_rate | float | 相对负载率（%） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"rn": 1, "station_name": "高新区科学大道充电站", "station_area": "郑州市,高新区", "total_sessions": 320, "total_kwh": 2800.5, "total_fee": 9800.0, "utilization_rate": 100.0},
    {"rn": 2, "station_name": "金水区花园路充电站", "station_area": "郑州市,金水区", "total_sessions": 280, "total_kwh": 2400.0, "total_fee": 8500.0, "utilization_rate": 87.5}
  ]
}
```

---

### 2.6 不同起始 SOC 行为雷达

- **接口路径**：`GET /api/soc-radar`
- **对应组件**：左侧雷达图（不同起始 SOC 行为）
- **数据来源**：需补（由 `ncs_dwd.dwd_charge_detail` 按 SOC 档位聚合）

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| health_level | string | SOC 档位（亏电 / 低电量 / 健康 / 满电） |
| dim_name | string | 维度名称（充电频次 / 平均电量 / 平均费用 / 平均时长 / 平均温度） |
| dim_value | float | 该维度数值（0-100 归一化） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"health_level": "亏电(<20%)", "dim_name": "充电频次", "dim_value": 85.0},
    {"health_level": "亏电(<20%)", "dim_name": "平均电量", "dim_value": 92.0},
    {"health_level": "满电(>=80%)", "dim_name": "充电频次", "dim_value": 30.0}
  ]
}
```

---

### 2.7 24 小时各区域充电分布

- **接口路径**：`GET /api/hour-area`
- **对应组件**：中间堆叠柱状图（24 小时各区域充电分布）
- **数据来源**：需补（由 `ncs_dwd.dwd_charge_detail` 按小时+区域交叉聚合）

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| hour | int | 小时（0-23） |
| station_area | string | 区域名称 |
| sessions | int | 该小时该区域充电次数 |
| total_kwh | float | 该小时该区域充电量（度） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"hour": 8, "station_area": "郑州市,高新区", "sessions": 45, "total_kwh": 320.5},
    {"hour": 8, "station_area": "郑州市,金水区", "sessions": 38, "total_kwh": 280.0},
    {"hour": 18, "station_area": "郑州市,高新区", "sessions": 120, "total_kwh": 980.5}
  ]
}
```

---

### 2.8 区域充电量与营收

- **接口路径**：`GET /api/area-kpi`
- **对应组件**：中间环形图（各区域充电量占比）+ 右侧柱状图（社区区域充电量对比）
- **数据来源**：`ncs_ads.ads_area_cost`（需补 `total_kwh` 字段）

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| station_area | string | 区域名称 |
| total_kwh | float | 总充电量（度） |
| revenue | float | 营收（元） |
| cost | float | 电量成本（元） |
| profit | float | 利润（元） |
| profit_rate | float | 利润率（%） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"station_area": "郑州市,高新区", "total_kwh": 8500.5, "revenue": 28000.0, "cost": 5100.3, "profit": 22899.7, "profit_rate": 81.8},
    {"station_area": "郑州市,金水区", "total_kwh": 6200.0, "revenue": 21000.0, "cost": 3720.0, "profit": 17280.0, "profit_rate": 82.3}
  ]
}
```

---

### 2.9 用户等级分布

- **接口路径**：`GET /api/user-level`
- **对应组件**：用户分级分布（底部/备用）
- **数据来源**：`ncs_ads.ads_user_level_dist`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| user_level | string | 用户等级（高频用户 / 中频用户 / 低频用户） |
| user_count | int | 该等级用户数 |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"user_level": "高频用户", "user_count": 12},
    {"user_level": "中频用户", "user_count": 35},
    {"user_level": "低频用户", "user_count": 37}
  ]
}
```

---

### 2.10 工作日 vs 周末对比

- **接口路径**：`GET /api/week-compare`
- **对应组件**：工作日 vs 周末对比（备用）
- **数据来源**：`ncs_ads.ads_week_compare`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| day_type | string | 类型（工作日 / 周末） |
| sessions | int | 充电次数 |
| total_kwh | float | 充电量（度） |
| pct | float | 占比（%） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"day_type": "工作日", "sessions": 2400, "total_kwh": 20500.0, "pct": 71.9},
    {"day_type": "周末", "sessions": 940, "total_kwh": 8060.5, "pct": 28.1}
  ]
}
```

---

### 2.11 电池健康分布

- **接口路径**：`GET /api/battery-health`
- **对应组件**：电池健康/SOC 档位占比（备用）
- **数据来源**：`ncs_ads.ads_battery_health`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| health_level | string | 电量等级（亏电 / 低电量 / 健康 / 满电） |
| sess_count | int | 充电次数 |
| ratio | float | 占比（%） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"health_level": "亏电(<20%)", "sess_count": 120, "ratio": 7.6},
    {"health_level": "低电量(20-50%)", "sess_count": 580, "ratio": 36.8},
    {"health_level": "健康(50-80%)", "sess_count": 680, "ratio": 43.1},
    {"health_level": "满电(>=80%)", "sess_count": 196, "ratio": 12.4}
  ]
}
```

---

### 2.12 用户等级行为雷达

- **接口路径**：`GET /api/user-radar`
- **对应组件**：用户等级雷达图（备用，与 SOC 雷达二选一）
- **数据来源**：`ncs_ads.ads_user_radar`

**返回字段：**

| 字段 | 类型 | 说明 |
|---|---|---|
| user_level | string | 用户等级（高频用户 / 中频用户 / 低频用户） |
| dim_name | string | 维度（充电频次 / 累计电量 / 消费金额 / 单次电量） |
| dim_value | float | 归一化值（0-100） |

**示例返回：**
```json
{
  "code": 200,
  "message": "success",
  "data": [
    {"user_level": "高频用户", "dim_name": "充电频次", "dim_value": 100.0},
    {"user_level": "高频用户", "dim_name": "累计电量", "dim_value": 95.0},
    {"user_level": "低频用户", "dim_name": "充电频次", "dim_value": 15.0}
  ]
}
```

---

## 三、数据来源对照表

| 接口 | MySQL 表 | 状态 |
|---|---|---|
| /api/kpi | ads_kpi_overview | ✅ 已有 |
| /api/platform | ads_platform_dist | ⚠️ 需补 sessions 字段 |
| /api/hour-trend | ads_hour_trend | ✅ 已有 |
| /api/station-type | ads_station_type_eff | ✅ 已有 |
| /api/station-top10 | ads_station_topn | ✅ 已有 |
| /api/soc-radar | 需新建 | ❌ 需补（DWS 聚合） |
| /api/hour-area | 需新建 | ❌ 需补（DWS 交叉聚合） |
| /api/area-kpi | ads_area_cost | ⚠️ 需补 total_kwh 字段 |
| /api/user-level | ads_user_level_dist | ✅ 已有 |
| /api/week-compare | ads_week_compare | ✅ 已有 |
| /api/battery-health | ads_battery_health | ✅ 已有 |
| /api/user-radar | ads_user_radar | ✅ 已有 |

---

## 四、错误码说明

| code | 说明 |
|---|---|
| 200 | 请求成功 |
| 500 | 服务器内部错误（数据库连接失败等） |
| 404 | 接口不存在 |

---

## 五、数据更新流程

当原始 CSV 数据变动时，按以下顺序更新：

1. 替换 `data/` 目录下的 CSV 文件
2. 清理并重新上传 HDFS 上的 ODS 数据
3. 重跑 ETL：
   ```bash
   spark-sql -f etl/sql/01_dwd_charge_detail.sql
   spark-sql -f etl/sql/02_dws_agg.sql
   spark-sql -f etl/sql/03_ads_dashboard.sql
   ```
4. 重跑导出：
   ```bash
   bash etl/shell/04_export_ads_mysql.sh
   ```
5. 刷新大屏（后端 API 自动读取最新 MySQL 数据）

---

*文档版本：v1.0 | 更新日期：2026-09-14*
