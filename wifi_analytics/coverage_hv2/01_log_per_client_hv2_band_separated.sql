WITH
    toDate('2026-09-21') AS start_date,
    toDate('2026-09-27') AS end_date,

/* ============================================================
   1. Count logs per client per day per band
   ============================================================ */
client_daily_logs AS
(
    SELECT
        toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) AS local_date,

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

        count() AS log_count

    FROM cpe_log.client_logs_distributed

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
        mac_client,
        band
)

/* ============================================================
   2. Distribution of log count / client by day + band
   ============================================================ */
SELECT
    local_date AS date,

    band,

    count() AS total_client,

    round(avg(log_count), 2) AS mean_log,

    quantileExact(0.10)(log_count) AS p10,
    quantileExact(0.20)(log_count) AS p20,
    quantileExact(0.30)(log_count) AS p30,
    quantileExact(0.40)(log_count) AS p40,
    quantileExact(0.50)(log_count) AS p50,
    quantileExact(0.70)(log_count) AS p70,
    quantileExact(0.90)(log_count) AS p90,
    quantileExact(0.99)(log_count) AS p99

FROM client_daily_logs

GROUP BY
    local_date,
    band

ORDER BY
    local_date,
    band;