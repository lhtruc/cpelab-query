WITH
    toDate('2026-09-21') AS start_date,
    toDate('2026-09-27') AS end_date

SELECT
    model_group AS model,
    uniqExact(client_mac) AS count_model
FROM
(
    SELECT
        CASE
            WHEN model IN ('AP-AX3000C', 'AP-AX3000CV2')
                THEN 'AX3000C/CV2'
            ELSE model
        END AS model_group,

        lower(replaceAll(mac_client, ':', '')) AS client_mac

    FROM client_logs_distributed

    WHERE toDate(toTimeZone(created_at, 'Asia/Ho_Chi_Minh'))
              BETWEEN start_date AND end_date
      AND model IN (
          'AP-AX3000C',
          'AP-AX3000CV2',
          'AX3000HV2',
          'AX3000S',
          'ONT-BE6500C',
          'AX3000GZV3'
      )
      AND mac_client != ''
)

GROUP BY model_group
ORDER BY model_group;