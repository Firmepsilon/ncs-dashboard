#!/usr/bin/env bash
# =====================================================================
# NCS 项目  run_etl_all.sh
# 作用：一键串联 DWD -> DWS -> ADS 三层 ETL（均通过 spark-sql 执行）
# 用法：sh run_etl_all.sh
# 定时：可配合 crontab 每日调度，例如  0 2 * * *  sh /home/hadoop/ncs_data/
#shell/run_etl_all.sh
# =====================================================================
set -euo pipefail

SHELL_DIR=$(cd "$(dirname "$0")" && pwd)
LOG_DIR=/home/hadoop/ncs_data/logs
mkdir -p "${LOG_DIR}"
ALL_LOG=${LOG_DIR}/etl_all_$(date +%Y%m%d).log

log() { echo "[$(date '+%F %T')] $*" | tee -a "${ALL_LOG}"; }

log "############## NCS 全量 ETL（DWD-DWS-ADS）开始 ##############"
START=$(date +%s)

# 严格按依赖顺序执行，任一步失败即终止
sh "${SHELL_DIR}/01_etl_dwd.sh"
sh "${SHELL_DIR}/02_etl_dws.sh"
sh "${SHELL_DIR}/03_etl_ads.sh"

END=$(date +%s)
log "############## 全量 ETL 完成，耗时 $((END-START)) 秒 ##############"
log "下一步：sh 04_export_ads_mysql.sh 将 ADS 导出到 MySQL"
