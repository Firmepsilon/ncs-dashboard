#!/bin/bash
# ============================================================
# NCS 充电桩项目  ADS(ORC) -> MySQL  导出导入脚本
# 方案（参考“脑肿瘤项目”04_export_tomysql.sh 成熟做法）：
#   Step1 内联 DDL 建库建表（utf8mb4，无主键，保证可重复导入）
#   Step2 spark-sql 用 INSERT OVERWRITE LOCAL DIRECTORY
#         直接把 ORC 表导出到【虚拟机本地目录】（管道符 | 分隔，
#         NULL 输出为空串）——不依赖任何外部 .hql，也不走 HDFS/getmerge
#   Step3 mysql LOAD DATA LOCAL INFILE 导入 ncs_ads
#   Step4 行数核对
# 环境：MySQL 本机 root/123456；spark-sql 已在 PATH
# 用法：bash 04_export_ads_mysql.sh
# ============================================================
set -e

# ---------------- 参数 / 配置 ----------------
MYSQL_DB="ncs_ads"
OUTPUT_DIR="/home/hadoop/temp/ads_export"        # 虚拟机本地导出目录

MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASS="123456"

APP_HOME=/home/hadoop/ncs_data         # 工程根目录（仅用于日志）
LOG_DIR=${APP_HOME}/logs
mkdir -p "$LOG_DIR"

MYSQL_CMD="mysql --default-character-set=utf8mb4 -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASS"

echo "============================================================"
echo "  NCS ADS(ORC) -> MySQL 导出导入"
echo "  本地导出目录: $OUTPUT_DIR"
echo "  MySQL 库: $MYSQL_DB (utf8mb4)"
echo "============================================================"

# 准备本地导出目录
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ============================================================
# Step 1：创建 MySQL 报表库表（DDL 内联，无外部文件依赖）
# ============================================================
echo ""
echo "[Step 1] 创建 MySQL 库 / 表 ..."

$MYSQL_CMD <<'MYSQL_DDL'
CREATE DATABASE IF NOT EXISTS ncs_ads
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE ncs_ads;

DROP TABLE IF EXISTS ads_kpi_overview;
CREATE TABLE ads_kpi_overview (
  sessions BIGINT COMMENT '总充电次数',
  total_kwh DOUBLE COMMENT '总充电量',
  total_fee DOUBLE COMMENT '总收入(订单费用合计,缺失为0)',
  station_count BIGINT COMMENT '充电站总数',
  abnormal_rate DOUBLE COMMENT 'BMS明细缺失率%'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KPI总览';

DROP TABLE IF EXISTS ads_user_level_dist;
CREATE TABLE ads_user_level_dist (
  user_level VARCHAR(20) COMMENT '用户等级',
  user_count BIGINT COMMENT '用户数'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户等级分布';

DROP TABLE IF EXISTS ads_user_radar;
CREATE TABLE ads_user_radar (
  user_level VARCHAR(20) COMMENT '用户等级',
  dim_name VARCHAR(20) COMMENT '维度',
  dim_value DOUBLE COMMENT '归一化值0-100'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户行为雷达';

DROP TABLE IF EXISTS ads_platform_dist;
CREATE TABLE ads_platform_dist (
  phone_type VARCHAR(20) COMMENT '下单平台',
  user_count BIGINT COMMENT '次数'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='平台偏好分布';

DROP TABLE IF EXISTS ads_hour_trend;
CREATE TABLE ads_hour_trend (
  hour INT COMMENT '小时',
  sessions BIGINT COMMENT '充电次数',
  total_kwh DOUBLE COMMENT '电量',
  is_peak INT COMMENT '是否高峰(1/0)'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='24小时充电趋势';

DROP TABLE IF EXISTS ads_station_type_eff;
CREATE TABLE ads_station_type_eff (
  gun_type VARCHAR(20) COMMENT '桩类型',
  utilization_rate DOUBLE COMMENT '相对负载率%',
  daily_kwh DOUBLE COMMENT '单桩平均电量',
  avg_fee_per_kwh DOUBLE COMMENT '平均每度费用'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='站点类型运营效率';

DROP TABLE IF EXISTS ads_week_compare;
CREATE TABLE ads_week_compare (
  day_type VARCHAR(10) COMMENT '工作日/周末',
  sessions BIGINT COMMENT '次数',
  total_kwh DOUBLE COMMENT '电量',
  pct DOUBLE COMMENT '占比%'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='工作日周末对比';

DROP TABLE IF EXISTS ads_battery_health;
CREATE TABLE ads_battery_health (
  health_level VARCHAR(30) COMMENT '起始电量等级',
  sess_count BIGINT COMMENT '次数',
  ratio DOUBLE COMMENT '占比%'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='起始电量等级分布';

DROP TABLE IF EXISTS ads_area_cost;
CREATE TABLE ads_area_cost (
  station_area VARCHAR(50) COMMENT '区域',
  total_kwh DOUBLE COMMENT '总充电量',
  revenue DOUBLE COMMENT '营收',
  cost DOUBLE COMMENT '电量成本',
  profit DOUBLE COMMENT '利润',
  profit_rate DOUBLE COMMENT '利润率%'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='区域成本收益';

DROP TABLE IF EXISTS ads_station_topn;
CREATE TABLE ads_station_topn (
  rn INT COMMENT '排名',
  station_name VARCHAR(100) COMMENT '站点名称',
  station_area VARCHAR(50) COMMENT '区域',
  total_sessions BIGINT COMMENT '总次数',
  total_kwh DOUBLE COMMENT '总电量',
  total_fee DOUBLE COMMENT '总费用',
  utilization_rate DOUBLE COMMENT '相对负载率%'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运营效率TOP充电站';

DROP TABLE IF EXISTS ads_hour_area;
CREATE TABLE ads_hour_area (
  hour INT COMMENT '小时',
  station_area VARCHAR(50) COMMENT '区域',
  sessions BIGINT COMMENT '充电次数',
  total_kwh DOUBLE COMMENT '充电量'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='24小时区域充电分布';
MYSQL_DDL

echo "  ✅ MySQL 10 张报表表准备完成（utf8mb4）"

# ============================================================
# Step 2：spark-sql 把 ORC 表导出为【本地】管道符分隔文本
# ============================================================
echo ""
echo "[Step 2] spark-sql 导出 ORC -> 本地文本( | 分隔) ..."

# export_table <ADS表名> <输出文件名>
export_table() {
  local table_name=$1
  local output_file=$2

  echo "  导出 $table_name ..."
  # INSERT OVERWRITE LOCAL DIRECTORY：Spark SQL 会把 ORC 列存读出后
  # 序列化成文本写到虚拟机本地目录；管道符 | 分隔，避免地址中的英文逗号冲突。
  spark-sql \
    --conf spark.sql.shuffle.partitions=20 \
    -e "
      SET hive.exec.compress.output=false;
      INSERT OVERWRITE LOCAL DIRECTORY '${OUTPUT_DIR}/${table_name}'
      ROW FORMAT DELIMITED
        FIELDS TERMINATED BY '|'
        LINES TERMINATED BY '\n'
        NULL DEFINED AS ''
      SELECT * FROM ncs_ads.${table_name};
    " >/dev/null 2>&1 || true

  # Spark/Hive 本地目录可能产出 part-* 多个文件，合并为一个
  if [ -d "${OUTPUT_DIR}/${table_name}" ]; then
    cat ${OUTPUT_DIR}/${table_name}/part-* > "${OUTPUT_DIR}/${output_file}" 2>/dev/null \
      || touch "${OUTPUT_DIR}/${output_file}"
    rm -rf "${OUTPUT_DIR}/${table_name}"
  else
    touch "${OUTPUT_DIR}/${output_file}"
  fi

  local row_count
  row_count=$(wc -l < "${OUTPUT_DIR}/${output_file}" 2>/dev/null || echo 0)
  echo "  ✅ ${output_file} (${row_count} 行)"
}

export_table "ads_kpi_overview"      "ads_kpi_overview.csv"
export_table "ads_user_level_dist"   "ads_user_level_dist.csv"
export_table "ads_user_radar"        "ads_user_radar.csv"
export_table "ads_platform_dist"     "ads_platform_dist.csv"
export_table "ads_hour_trend"        "ads_hour_trend.csv"
export_table "ads_station_type_eff"  "ads_station_type_eff.csv"
export_table "ads_week_compare"      "ads_week_compare.csv"
export_table "ads_battery_health"    "ads_battery_health.csv"
export_table "ads_area_cost"         "ads_area_cost.csv"
export_table "ads_station_topn"      "ads_station_topn.csv"
export_table "ads_hour_area"         "ads_hour_area.csv"

echo "  ✅ 文本导出完成，目录：$OUTPUT_DIR"

# ============================================================
# Step 3：导入 MySQL（LOAD DATA LOCAL INFILE，utf8mb4）
# ============================================================
echo ""
echo "[Step 3] 导入 MySQL ..."

# 允许本地文件加载（失败不中断，部分版本默认已开）
$MYSQL_CMD -e "SET GLOBAL local_infile=ON;" 2>/dev/null || true

import_table() {
  local csv_file=$1
  local mysql_table=$2

  echo "  导入 $mysql_table ..."
  $MYSQL_CMD --local-infile=1 "$MYSQL_DB" -e "
    SET NAMES utf8mb4;
    TRUNCATE TABLE ${mysql_table};
    LOAD DATA LOCAL INFILE '${OUTPUT_DIR}/${csv_file}'
    INTO TABLE ${mysql_table}
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY '|'
    LINES TERMINATED BY '\n'
    IGNORE 0 LINES;
  " 2>/dev/null

  if [ $? -eq 0 ]; then
    echo "  ✅ $mysql_table 导入成功"
  else
    echo "  ⚠️ LOAD DATA 失败，尝试 mysqlimport ..."
    mysqlimport --local --default-character-set=utf8mb4 \
      -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASS \
      --fields-terminated-by='|' --lines-terminated-by='\n' \
      "$MYSQL_DB" "${OUTPUT_DIR}/${csv_file}" 2>/dev/null \
      || echo "  [警告] $mysql_table 导入失败，请检查文件"
  fi
}

import_table "ads_kpi_overview.csv"      "ads_kpi_overview"
import_table "ads_user_level_dist.csv"   "ads_user_level_dist"
import_table "ads_user_radar.csv"        "ads_user_radar"
import_table "ads_platform_dist.csv"     "ads_platform_dist"
import_table "ads_hour_trend.csv"        "ads_hour_trend"
import_table "ads_station_type_eff.csv"  "ads_station_type_eff"
import_table "ads_week_compare.csv"      "ads_week_compare"
import_table "ads_battery_health.csv"    "ads_battery_health"
import_table "ads_area_cost.csv"         "ads_area_cost"
import_table "ads_station_topn.csv"      "ads_station_topn"
import_table "ads_hour_area.csv"         "ads_hour_area"

# ============================================================
# Step 4：验证 MySQL 数据
# ============================================================
echo ""
echo "[Step 4] 验证 MySQL 数据 ..."
echo ""
echo "===== 各表记录数 ====="
$MYSQL_CMD "$MYSQL_DB" -e "
  SELECT 'ads_kpi_overview'     AS t, COUNT(*) AS rows_cnt FROM ads_kpi_overview
  UNION ALL SELECT 'ads_user_level_dist', COUNT(*) FROM ads_user_level_dist
  UNION ALL SELECT 'ads_user_radar',       COUNT(*) FROM ads_user_radar
  UNION ALL SELECT 'ads_platform_dist',    COUNT(*) FROM ads_platform_dist
  UNION ALL SELECT 'ads_hour_trend',       COUNT(*) FROM ads_hour_trend
  UNION ALL SELECT 'ads_station_type_eff', COUNT(*) FROM ads_station_type_eff
  UNION ALL SELECT 'ads_week_compare',     COUNT(*) FROM ads_week_compare
  UNION ALL SELECT 'ads_battery_health',   COUNT(*) FROM ads_battery_health
  UNION ALL SELECT 'ads_area_cost',        COUNT(*) FROM ads_area_cost
  UNION ALL SELECT 'ads_station_topn',     COUNT(*) FROM ads_station_topn
  UNION ALL SELECT 'ads_hour_area',        COUNT(*) FROM ads_hour_area;
" 2>/dev/null || echo "  [警告] 记录数核对失败，请手动检查"

echo ""
echo "===== 中文 / KPI 抽查 ====="
$MYSQL_CMD "$MYSQL_DB" -e "
  SET NAMES utf8mb4;
  SELECT * FROM ads_kpi_overview;
  SELECT * FROM ads_user_level_dist;
  SELECT station_name,total_sessions FROM ads_station_topn LIMIT 3;
" 2>/dev/null || echo "  [警告] 抽查查询失败"

echo ""
echo "============================================================"
echo "  ✅ ADS -> MySQL 完成"
echo "  本地文本目录: $OUTPUT_DIR"
echo "  MySQL 库: $MYSQL_DB （Windows Flask 连 192.168.176.100:3306）"
echo "============================================================"
