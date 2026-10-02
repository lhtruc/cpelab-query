WITH
    toDate('2026-09-21') AS start_date,
    toDate('2026-09-27') AS end_date,

/* ============================================================
   1. Mean RSSI per client / CPE / day / band
   ============================================================ */
client_daily AS
(
    SELECT
        toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) AS local_date,

        mac_address,
        mac_client,

        if(
            interface IN (
                '2.4GHz',
                'ath0',
                'ath01',
                'ath02',
                'ath03',
                'wlan5'
            ),
            '2.4GHz',
            '5GHz'
        ) AS band,

        avg(rssi) AS avg_rssi

    FROM client_logs_distributed

    WHERE
        /* Partition pruning */
        date >= start_date - 1
        AND date <= end_date + 1

        /* Exact VN date */
        AND toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) BETWEEN start_date AND end_date

        /* 19:00 - 21:00 VN time */
        AND toHour(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) >= 19

        AND toHour(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) < 21

        AND model = 'AX3000HV2'
        AND interface_type = 'wireless'
        AND mac_client != ''

    GROUP BY
        local_date,
        mac_address,
        mac_client,
        band
),

/* ============================================================
   2. Coverage per CPE / day / band
   ============================================================ */
cpe_coverage AS
(
    SELECT
        local_date,
        mac_address,
        band,

        count() AS total_client,

        countIf(
            (band = '2.4GHz' AND avg_rssi >= -74)
            OR
            (band = '5GHz' AND avg_rssi >= -77)
        ) AS good_client,

        100.0
        * countIf(
            (band = '2.4GHz' AND avg_rssi >= -74)
            OR
            (band = '5GHz' AND avg_rssi >= -77)
        )
        / count() AS coverage_pct

    FROM client_daily

    GROUP BY
        local_date,
        mac_address,
        band
)

/* ============================================================
   3. Distribution of CPE coverage by day + band
   ============================================================ */
SELECT
    local_date AS date,
    band,
    
    round(quantile(0.05)(coverage_pct), 2) AS p5,
    round(quantile(0.10)(coverage_pct), 2) AS p10,
    round(quantile(0.15)(coverage_pct), 2) AS p15,
    round(quantile(0.20)(coverage_pct), 2) AS p20,
    round(quantile(0.25)(coverage_pct), 2) AS p25,
    round(quantile(0.30)(coverage_pct), 2) AS p30,
    round(quantile(0.40)(coverage_pct), 2) AS p40,
    round(quantile(0.50)(coverage_pct), 2) AS p50,
    round(quantile(0.60)(coverage_pct), 2) AS p60,
    round(quantile(0.70)(coverage_pct), 2) AS p70,
    round(quantile(0.80)(coverage_pct), 2) AS p80,
    round(quantile(0.90)(coverage_pct), 2) AS p90,
    round(quantile(0.99)(coverage_pct), 2) AS p99

FROM cpe_coverage

GROUP BY
    local_date,
    band

ORDER BY
    local_date,
    band;