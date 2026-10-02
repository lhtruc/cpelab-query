WITH
    toDate(
        toTimeZone(
            now(),
            'Asia/Ho_Chi_Minh'
        )
    ) AS today_date,

    today_date - 7 AS start_date,
    today_date - 1 AS end_date,

/* ============================================================
   1. Client stats per CPE / day - 5GHz
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

        count() AS log_count,
        avg(rssi) AS avg_rssi

    FROM client_logs_distributed

    WHERE
        date >= start_date - 1
        AND date <= end_date + 1

        AND toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) BETWEEN start_date AND end_date

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

        /* Valid RSSI */
        AND rssi >= -90
        AND rssi <= -10

        /* 5GHz */
        AND interface NOT IN (
            '2.4GHz',
            'ath0',
            'ath01',
            'ath02',
            'ath03',
            'wlan5'
        )

    GROUP BY
        local_date,
        mac_address,
        mac_client
),

/* ============================================================
   2. Split client by daily P30 threshold
   ============================================================ */
client_grouped AS
(
    SELECT
        local_date,
        mac_address,
        mac_client,
        log_count,
        avg_rssi,

        multiIf(
            local_date = toDate('2026-09-21') AND log_count >= 19, '>= P30',
            local_date = toDate('2026-09-22') AND log_count >= 19, '>= P30',
            local_date = toDate('2026-09-23') AND log_count >= 19, '>= P30',
            local_date = toDate('2026-09-24') AND log_count >= 17, '>= P30',
            local_date = toDate('2026-09-25') AND log_count >= 16, '>= P30',
            local_date = toDate('2026-09-26') AND log_count >= 18, '>= P30',
            local_date = toDate('2026-09-27') AND log_count >= 19, '>= P30',
            '< P30'
        ) AS threshold_group

    FROM client_daily
),

/* ============================================================
   3. Coverage per CPE / day / threshold group
      Good 5GHz: avg RSSI >= -77 dBm
   ============================================================ */
cpe_coverage AS
(
    SELECT
        local_date,
        mac_address,
        threshold_group,

        count() AS total_client,

        countIf(
            avg_rssi >= -77
        ) AS good_client,

        100.0
        * countIf(avg_rssi >= -77)
        / count() AS coverage_pct

    FROM client_grouped

    GROUP BY
        local_date,
        mac_address,
        threshold_group
)

/* ============================================================
   4. Coverage percentile across CPEs
   ============================================================ */
SELECT
    local_date AS date,
    threshold_group AS threshold,

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
    threshold_group

ORDER BY
    local_date,
    threshold_group DESC;