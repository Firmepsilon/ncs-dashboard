#!/usr/bin/env bash
# =====================================================================
# NCS 项目  03_etl_ads.sh
# 作用：用 spark-sql 执行 ADS 应用层（10 张大屏指标表）
# 前置：02_etl_dws.sh 已成功
# =====================================================================
set -euo pipefail

APP_HOME=/opt/module/ncs
SQL_DIR=${APP_HOME}/spark_sql
LOG_DIR=${APP_HOME}/logs
mkdir -p "${LOG_DIR}"
LOG_FILE=${LOG_DIR}/etl_ads_$(date +%Y%m%d).log

log() { echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}"; }

log "================ ADS 应用层 ETL 开始 ================"
jps | grep -q Master || { log "[ERROR] Spark Master 未运行"; exit 1; }

log "执行 SQL：03_ads_dashboard.sql"
spark-sql \
  --conf spark.sql.shuffle.partitions=20 \
  -f "${SQL_DIR}/03_ads_dashboard.sql" 2>&1 | tee -a "${LOG_FILE}"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  log "ADS 应用层 ETL 执行成功，可执行 04_export_ads_mysql.sh 导出 MySQL。"
else
  log "[ERROR] ADS ETL 失败：${LOG_FILE}"
  exit 1
fi
log "================ ADS 应用层 ETL 结束 ================"
