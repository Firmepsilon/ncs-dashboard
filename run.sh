#!/bin/bash
# =============================================================================
# NCS 电动汽车充电桩应用管理平台 — 一键 ETL 脚本
# 功能：从原始 CSV 到 MySQL 全流程自动执行（ODS建表 → DWD → DWS → ADS → 导出MySQL）
# 用法：bash run.sh
# 前置：Hadoop、Spark、MySQL 已启动
# =============================================================================
set -e  # 任何一步失败立即停止

# ---------- 定位项目根目录（脚本放在哪都能找到项目） ----------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "============================================================"
echo "  NCS 充电桩数据平台 — 一键 ETL"
echo "  项目目录：$PROJECT_DIR"
echo "============================================================"
echo ""

# ---------- 1. 环境检查 ----------
echo "【1/7】检查环境..."
if ! jps | grep -q NameNode; then
    echo "  ❌ Hadoop 未启动！请先执行：cd /opt/module/hadoop-3.3.0/sbin && ./start-all.sh"
    exit 1
fi
if ! jps | grep -q Master; then
    echo "  ❌ Spark 未启动！请先执行：cd /opt/module/spark-3.4.1/sbin && ./start-all.sh"
    exit 1
fi
if ! mysql -uroot -p123456 -e "SELECT 1" >/dev/null 2>&1; then
    echo "  ❌ MySQL 未启动或连接失败！请检查 MySQL 服务"
    exit 1
fi
echo "  ✅ Hadoop、Spark、MySQL 均已启动"
echo ""

# ---------- 2. HDFS 准备：建目录 + 清理旧数据 + 上传 CSV ----------
echo "【2/7】准备 ODS 数据（上传 CSV 到 HDFS）..."
hdfs dfs -mkdir -p /ncs/ods/ods_charging_order
hdfs dfs -mkdir -p /ncs/ods/ods_charging_process
hdfs dfs -mkdir -p /ncs/ods/ods_charging_station_meta
# 清理旧数据（保证幂等，重复运行不会残留）
hdfs dfs -rm -f /ncs/ods/ods_charging_order/*
hdfs dfs -rm -f /ncs/ods/ods_charging_process/*
hdfs dfs -rm -f /ncs/ods/ods_charging_station_meta/*
# 上传新数据
hdfs dfs -put "$PROJECT_DIR/data/nvv2t.csv"          /ncs/ods/ods_charging_order/
hdfs dfs -put "$PROJECT_DIR/data/dsv13r2.csv"        /ncs/ods/ods_charging_process/
hdfs dfs -put "$PROJECT_DIR/data/nvv2t_md_end.csv"   /ncs/ods/ods_charging_station_meta/
echo "  ✅ 3 份 CSV 已上传到 HDFS"
echo ""

# ---------- 3. ODS 建表 ----------
echo "【3/7】ODS 层建表（Hive 外部表）..."
hive -f "$PROJECT_DIR/etl/sql/00_ods_create.hql" >/dev/null 2>&1
echo "  ✅ ODS 层 4 库 3 表已就绪"
echo ""

# ---------- 4. DWD 明细层 ETL ----------
echo "【4/7】DWD 明细层 ETL（三表关联 + 清洗）..."
spark-sql -f "$PROJECT_DIR/etl/sql/01_dwd_charge_detail.sql"
echo ""

# ---------- 5. DWS 汇总层 ETL ----------
echo "【5/7】DWS 汇总层 ETL（7 张维度聚合表）..."
spark-sql -f "$PROJECT_DIR/etl/sql/02_dws_agg.sql"
echo ""

# ---------- 6. ADS 应用层 ETL ----------
echo "【6/7】ADS 应用层 ETL（11 张大屏指标表）..."
spark-sql -f "$PROJECT_DIR/etl/sql/03_ads_dashboard.sql"
echo ""

# ---------- 7. 导出 MySQL ----------
echo "【7/7】导出 ADS 数据到 MySQL..."
bash "$PROJECT_DIR/etl/shell/04_export_ads_mysql.sh"
echo ""

# ---------- 完成 ----------
echo "============================================================"
echo "  ✅✅✅ 全部完成！"
echo "  数据已就绪：HDFS（ODS/DWD/DWS/ADS）+ MySQL（ncs_ads 库 11 张表）"
echo "  下一步：启动后端 Flask，打开大屏即可看到数据"
echo "============================================================"
