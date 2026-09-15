-- =====================================================================
-- NCS 充电桩项目  DWS 汇总层（spark-sql）
-- 文件：02_dws_agg.sql
-- 来源：ncs_dwd.dwd_charge_detail（表名沿用第一天 ODS，经 DWD 清洗）
-- 主题：站点 / 用户 / 小时 / 通用维度（星期·平台·桩型）/ BMS 监测
-- 执行：spark-sql -f 02_dws_agg.sql   或  sh 02_etl_dws.sh
-- =====================================================================
SET spark.sql.shuffle.partitions = 20;
SET spark.sql.parquet.compression.codec = snappy;

CREATE DATABASE IF NOT EXISTS ncs_dws;

-- ---------------------------------------------------------------------
-- 1. dws_station_agg：按充电站汇总（TOP 排行 / 区域收益用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_station_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_station_agg (
  station_id        STRING,
  station_name      STRING,
  address           STRING,
  location_id       STRING,
  station_type      STRING,
  device_count      INT,
  total_sessions    BIGINT,
  total_kwh         DOUBLE,
  total_fee         DOUBLE,
  avg_duration      DOUBLE,
  avg_kwh           DOUBLE
)
STORED AS orc
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_station_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_station_agg
SELECT
    station_id, station_name, MAX(address) AS address, MAX(location_id) AS location_id,
    MAX(station_type) AS station_type, MAX(device_count) AS device_count,
    COUNT(*)                                AS total_sessions,
    ROUND(SUM(kwh),2)                       AS total_kwh,
    ROUND(SUM(total_fee),2)                 AS total_fee,
    ROUND(AVG(duration_hrs),3)              AS avg_duration,
    ROUND(AVG(kwh),3)                       AS avg_kwh
FROM ncs_dwd.dwd_charge_detail
GROUP BY station_id, station_name;

-- ---------------------------------------------------------------------
-- 2. dws_user_agg：按用户汇总（用户分级 / 雷达用）
--    充电次数口径：该用户的充电会话数
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_user_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_user_agg (
  user_id           STRING,
  charge_count      BIGINT,
  total_kwh         DOUBLE,
  total_fee         DOUBLE,
  avg_kwh           DOUBLE,
  main_platform     STRING
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_user_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_user_agg
SELECT
    user_id,
    COUNT(*)                          AS charge_count,
    ROUND(SUM(kwh),2)                 AS total_kwh,
    ROUND(SUM(total_fee),2)           AS total_fee,
    ROUND(AVG(kwh),3)                 AS avg_kwh,
    MAX(platform)                     AS main_platform
FROM ncs_dwd.dwd_charge_detail
GROUP BY user_id;

-- ---------------------------------------------------------------------
-- 3. dws_hour_agg：按充电开始小时汇总（24h 高峰趋势用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_hour_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_hour_agg (
  hour              INT,
  sessions          BIGINT,
  total_kwh         DOUBLE,
  total_fee         DOUBLE
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_hour_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_hour_agg
SELECT start_hour AS hour,
       COUNT(*)            AS sessions,
       ROUND(SUM(kwh),2)   AS total_kwh,
       ROUND(SUM(total_fee),2) AS total_fee
FROM ncs_dwd.dwd_charge_detail
WHERE start_hour BETWEEN 0 AND 23
GROUP BY start_hour;

-- ---------------------------------------------------------------------
-- 4. dws_dim_agg：通用单维度聚合（星期 / 平台 / 桩类型）
--    一次扫描 + grouping sets 风格改写为 UNION ALL，兼容 spark-sql
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_dim_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_dim_agg (
  dim_type          STRING,   -- weekday / platform / station_type
  dim_value         STRING,
  sessions          BIGINT,
  total_kwh         DOUBLE,
  total_fee         DOUBLE
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_dim_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_dim_agg
SELECT 'weekday'      AS dim_type, weekday AS dim_value, COUNT(*), ROUND(SUM(kwh),2), ROUND(SUM(total_fee),2)
FROM ncs_dwd.dwd_charge_detail GROUP BY weekday
UNION ALL
SELECT 'platform', platform, COUNT(*), ROUND(SUM(kwh),2), ROUND(SUM(total_fee),2)
FROM ncs_dwd.dwd_charge_detail GROUP BY platform
UNION ALL
SELECT 'station_type', station_type, COUNT(*), ROUND(SUM(kwh),2), ROUND(SUM(total_fee),2)
FROM ncs_dwd.dwd_charge_detail GROUP BY station_type
UNION ALL
SELECT 'is_weekend', CASE WHEN is_weekend=1 THEN '周末' ELSE '工作日' END,
       COUNT(*), ROUND(SUM(kwh),2), ROUND(SUM(total_fee),2)
FROM ncs_dwd.dwd_charge_detail GROUP BY is_weekend
UNION ALL
SELECT 'soc_segment',
       CASE WHEN soc IS NULL THEN '无BMS明细'
            WHEN soc < 20 THEN '低电量(<20%)'
            WHEN soc < 50 THEN '中电量(20-50%)'
            WHEN soc < 80 THEN '高电量(50-80%)'
            ELSE '满电(>=80%)' END,
       COUNT(*), ROUND(SUM(kwh),2), ROUND(SUM(total_fee),2)
FROM ncs_dwd.dwd_charge_detail
GROUP BY CASE WHEN soc IS NULL THEN '无BMS明细'
              WHEN soc < 20 THEN '低电量(<20%)'
              WHEN soc < 50 THEN '中电量(20-50%)'
              WHEN soc < 80 THEN '高电量(50-80%)'
              ELSE '满电(>=80%)' END;

-- ---------------------------------------------------------------------
-- 5. dws_bms_agg：BMS 电池健康监测（仅 1594 条有明细的订单）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_bms_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_bms_agg (
  health_level      STRING,
  sess_count        BIGINT,
  avg_soc           DOUBLE,
  avg_pack_voltage  DOUBLE,
  max_temp          DOUBLE
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_bms_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_bms_agg
SELECT
    CASE WHEN soc < 20 THEN '亏电(<20%)'
         WHEN soc < 50 THEN '低电量(20-50%)'
         WHEN soc < 80 THEN '健康(50-80%)'
         ELSE '满电(>=80%)' END          AS health_level,
    COUNT(*)                              AS sess_count,
    ROUND(AVG(soc),2)                     AS avg_soc,
    ROUND(AVG(pack_voltage),2)            AS avg_pack_voltage,
    ROUND(MAX(max_temp),2)                AS max_temp
FROM ncs_dwd.dwd_charge_detail
WHERE soc IS NOT NULL
GROUP BY CASE WHEN soc < 20 THEN '亏电(<20%)'
              WHEN soc < 50 THEN '低电量(20-50%)'
              WHEN soc < 80 THEN '健康(50-80%)'
              ELSE '满电(>=80%)' END;

-- ---------------------------------------------------------------------
-- 6. dws_area_agg：按区域汇总（区域电量/营收/站点数，ADS区域图用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_area_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_area_agg (
  station_area    STRING,
  total_sessions  BIGINT,
  total_kwh       DOUBLE,
  total_fee       DOUBLE,
  station_count   BIGINT,
  avg_kwh         DOUBLE
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_area_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_area_agg
SELECT
    COALESCE(NULLIF(substring_index(address,',',2),''),'未知区域') AS station_area,
    COUNT(*)              AS total_sessions,
    ROUND(SUM(kwh),2)     AS total_kwh,
    ROUND(SUM(total_fee),2) AS total_fee,
    COUNT(DISTINCT station_id) AS station_count,
    ROUND(AVG(kwh),3)     AS avg_kwh
FROM ncs_dwd.dwd_charge_detail
GROUP BY COALESCE(NULLIF(substring_index(address,',',2),''),'未知区域');

-- ---------------------------------------------------------------------
-- 7. dws_hour_area_agg：按小时×区域交叉汇总（24h区域堆叠图用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ncs_dws.dws_hour_area_agg;
CREATE EXTERNAL TABLE ncs_dws.dws_hour_area_agg (
  hour           INT,
  station_area   STRING,
  sessions       BIGINT,
  total_kwh      DOUBLE,
  total_fee      DOUBLE
)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/ncs_dws.db/dws_hour_area_agg';

INSERT OVERWRITE TABLE ncs_dws.dws_hour_area_agg
SELECT
    start_hour AS hour,
    COALESCE(NULLIF(substring_index(address,',',2),''),'未知区域') AS station_area,
    COUNT(*)              AS sessions,
    ROUND(SUM(kwh),2)     AS total_kwh,
    ROUND(SUM(total_fee),2) AS total_fee
FROM ncs_dwd.dwd_charge_detail
WHERE start_hour BETWEEN 0 AND 23
GROUP BY start_hour, COALESCE(NULLIF(substring_index(address,',',2),''),'未知区域');

-- ------------------------- 数据验证 -------------------------
SELECT 'dws_station_agg' AS tbl, COUNT(*) AS rows_cnt FROM ncs_dws.dws_station_agg
UNION ALL SELECT 'dws_user_agg',  COUNT(*) FROM ncs_dws.dws_user_agg
UNION ALL SELECT 'dws_hour_agg',  COUNT(*) FROM ncs_dws.dws_hour_agg
UNION ALL SELECT 'dws_dim_agg',   COUNT(*) FROM ncs_dws.dws_dim_agg
UNION ALL SELECT 'dws_bms_agg',   COUNT(*) FROM ncs_dws.dws_bms_agg
UNION ALL SELECT 'dws_area_agg',  COUNT(*) FROM ncs_dws.dws_area_agg
UNION ALL SELECT 'dws_hour_area_agg', COUNT(*) FROM ncs_dws.dws_hour_area_agg;
