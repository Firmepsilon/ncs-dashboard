#!/usr/bin/env bash
# =====================================================================
# NCS 项目  02_etl_dws.sh
# 作用：用 spark-sql 执行 DWS 汇总层（站点/用户/小时/日期 四大主题）
# 前置：01_etl_dwd.sh 已成功
# =====================================================================
set -euo pipefail

APP_HOME=/opt/module/ncs
SQL_DIR=${APP_HOME}/spark_sql
LOG_DIR=${APP_HOME}/logs
mkdir -p "${LOG_DIR}"
LOG_FILE=${LOG_DIR}/etl_dws_$(date +%Y%m%d).log

log() { echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}"; }

log "================ DWS 汇总层 ETL 开始 ================"
jps | grep -q Master || { log "[ERROR] Spark Master 未运行"; exit 1; }

log "执行 SQL：02_dws_agg.sql"
spark-sql \
  --conf spark.sql.shuffle.partitions=20 \
  -f "${SQL_DIR}/02_dws_agg.sql" 2>&1 | tee -a "${LOG_FILE}"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  log "DWS 汇总层 ETL 执行成功。"
else
  log "[ERROR] DWS ETL 失败：${LOG_FILE}"
  exit 1
fi
log "================ DWS 汇总层 ETL 结束 ================"
