WITH
thresholds AS
(
    SELECT toDate('2026-09-24') AS local_date, 5.25 AS p30, 14.25 AS p40, 25.50 AS p50
    UNION ALL
    SELECT toDate('2026-09-25'), 5.25, 12.75, 23.25
    UNION ALL
    SELECT toDate('2026-09-26'), 5.25, 13.50, 25.50
    UNION ALL
    SELECT toDate('2026-09-27'), 6.75, 17.25, 28.50
    UNION ALL
    SELECT toDate('2026-09-28'), 4.50, 12.00, 23.25
    UNION ALL
    SELECT toDate('2026-09-29'), 6.75, 15.75, 26.25
    UNION ALL
    SELECT toDate('2026-09-30'), 6.75, 14.25, 24.00
),

client_daily AS
(
    SELECT
        toDate(toTimeZone(created_at, 'Asia/Ho_Chi_Minh')) AS local_date,
        model,
        mac_address,
        mac_client,
        count() AS log_count,
        avg(rssi) AS avg_rssi

    FROM cpe_log.client_logs_distributed

    WHERE
        date >= toDate('2026-09-24') - 1
        AND date <= toDate('2026-09-30') + 1

        AND toDate(toTimeZone(created_at, 'Asia/Ho_Chi_Minh'))
            BETWEEN toDate('2026-09-24') AND toDate('2026-09-30')

        AND toHour(toTimeZone(created_at, 'Asia/Ho_Chi_Minh')) >= 19
        AND toHour(toTimeZone(created_at, 'Asia/Ho_Chi_Minh')) < 21

        AND model IN ('ONT-BE6500C', 'AP-BE6500C')
        AND interface_type = 'wireless'
        AND mac_client != ''

        AND rssi >= -90
        AND rssi <= -10

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
        model,
        mac_address,
        mac_client
),

client_with_thresholds AS
(
    SELECT
        c.local_date,
        c.model,
        c.mac_address,
        c.mac_client,
        c.log_count * 0.75 AS scaled_log_count,
        c.avg_rssi,
        t.p30,
        t.p40,
        t.p50

    FROM client_daily AS c
    INNER JOIN thresholds AS t
        ON c.local_date = t.local_date
),

client_grouped AS
(
    SELECT
        local_date,
        model,
        mac_address,
        mac_client,
        avg_rssi,

        'P30' AS threshold_name,
        if(scaled_log_count >= p30, '>= P30', '< P30') AS threshold_group

    FROM client_with_thresholds

    UNION ALL

    SELECT
        local_date,
        model,
        mac_address,
        mac_client,
        avg_rssi,

        'P40' AS threshold_name,
        if(scaled_log_count >= p40, '>= P40', '< P40') AS threshold_group

    FROM client_with_thresholds

    UNION ALL

    SELECT
        local_date,
        model,
        mac_address,
        mac_client,
        avg_rssi,

        'P50' AS threshold_name,
        if(scaled_log_count >= p50, '>= P50', '< P50') AS threshold_group

    FROM client_with_thresholds
),

cpe_coverage AS
(
    SELECT
        local_date,
        model,
        mac_address,
        threshold_name,
        threshold_group,

        count() AS total_client,
        countIf(avg_rssi >= -77) AS good_client,
        100.0 * countIf(avg_rssi >= -77) / count() AS coverage_pct

    FROM client_grouped

    GROUP BY
        local_date,
        model,
        mac_address,
        threshold_name,
        threshold_group
)

SELECT
    local_date AS date,
    model,
    threshold_name AS threshold,
    threshold_group,

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
    model,
    threshold_name,
    threshold_group

ORDER BY
    local_date,
    model,
    threshold_name,
    threshold_group;s