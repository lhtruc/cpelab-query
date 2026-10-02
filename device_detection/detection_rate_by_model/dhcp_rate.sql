WITH
    toDateTime('2026-09-21 00:00:00', 'Asia/Ho_Chi_Minh') AS start_ts,
    toDateTime('2026-09-28 00:00:00', 'Asia/Ho_Chi_Minh') AS end_ts,

clients AS
(
    SELECT
        if(
            model IN ('AP-AX3000C', 'AP-AX3000CV2'),
            'AX3000C/CV2',
            model
        ) AS model_group,
        mac_address,
        mac_client
    FROM client_logs_distributed

    PREWHERE created_at >= start_ts
         AND created_at < end_ts

    WHERE model IN (
        'AP-AX3000C',
        'AP-AX3000CV2',
        'AX3000HV2',
        'AX3000S',
        'ONT-BE6500C',
        'AX3000GZV3'
    )
      AND mac_client != ''

    GROUP BY
        model_group,
        mac_address,
        mac_client
),

dhcp AS
(
    SELECT
        mac_address,
        mac_client,

        max(
            computed_device_class != 'Unknown'
            AND computed_device_class != ''
        ) AS identified

    FROM cpe_dhcp_fingerprint_distributed

    PREWHERE created_at >= start_ts
         AND created_at < end_ts

    WHERE mac_client != ''

    GROUP BY
        mac_address,
        mac_client
)

SELECT
    c.model_group AS model,

    uniqExact(c.mac_client) AS dhcp_count,

    uniqExactIf(
        c.mac_client,
        d.identified = 1
    ) AS dhcp_identified,

    round(
        100.0 * dhcp_identified
        / nullIf(dhcp_count, 0),
        2
    ) AS pct_dhcp

FROM clients AS c

GLOBAL ANY INNER JOIN dhcp AS d
    ON c.mac_address = d.mac_address
   AND c.mac_client = d.mac_client

GROUP BY c.model_group
ORDER BY c.model_group;