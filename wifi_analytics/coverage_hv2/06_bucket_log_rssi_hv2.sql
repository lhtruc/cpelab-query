WITH
    toDate('2026-09-17') AS start_date,
    toDate('2026-09-23') AS end_date,

/* ============================================================
   1. Aggregate per client / day / band
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

        CASE
            WHEN interface IN (
                '2.4GHz',
                'ath0',
                'ath01',
                'ath02',
                'ath03',
                'wlan5'
            )
                THEN '2.4GHz'
            ELSE '5GHz'
        END AS band,

        count() AS log_count,

        avg(rssi) AS client_avg_rssi

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

        /* 19:00 - 21:00 VN */
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

        AND rssi >= -90
        AND rssi <= -10

    GROUP BY
        local_date,
        mac_address,
        mac_client,
        band
),

/* ============================================================
   2. Bucket by log count
   ============================================================ */
bucketed AS
(
    SELECT
        local_date,
        band,
        log_count,
        client_avg_rssi,

        multiIf(
            log_count < 10,  '< 10',
            log_count < 20,  '10 - 20',
            log_count < 40,  '20 - 40',
            log_count <= 60, '40 - 60',
            '> 60'
        ) AS bucket_log

    FROM client_daily
)

/* ============================================================
   3. RSSI distribution by day / band / bucket
   ============================================================ */
SELECT
    local_date AS date,
    band,
    bucket_log,

    count() AS total_clients,

    round(
        avg(client_avg_rssi),
        2
    ) AS mean_rssi,

    round(
        quantileExact(0.10)(client_avg_rssi),
        2
    ) AS p10,

    round(
        quantileExact(0.20)(client_avg_rssi),
        2
    ) AS p20,

    round(
        quantileExact(0.30)(client_avg_rssi),
        2
    ) AS p30,

    round(
        quantileExact(0.40)(client_avg_rssi),
        2
    ) AS p40,

    round(
        quantileExact(0.50)(client_avg_rssi),
        2
    ) AS p50,

    round(
        quantileExact(0.60)(client_avg_rssi),
        2
    ) AS p60,

    round(
        quantileExact(0.70)(client_avg_rssi),
        2
    ) AS p70,

    round(
        quantileExact(0.80)(client_avg_rssi),
        2
    ) AS p80,

    round(
        quantileExact(0.90)(client_avg_rssi),
        2
    ) AS p90,

    round(
        quantileExact(0.95)(client_avg_rssi),
        2
    ) AS p95,

    round(
        quantileExact(0.99)(client_avg_rssi),
        2
    ) AS p99

FROM bucketed

GROUP BY
    local_date,
    band,
    bucket_log

ORDER BY
    local_date,

    CASE band
        WHEN '2.4GHz' THEN 1
        WHEN '5GHz'   THEN 2
        ELSE 99
    END,

    CASE bucket_log
        WHEN '< 10'     THEN 1
        WHEN '10 - 20'  THEN 2
        WHEN '20 - 40'  THEN 3
        WHEN '40 - 60'  THEN 4
        WHEN '> 60'     THEN 5
        ELSE 99
    END;