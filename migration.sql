-- shipping_country_rates

CREATE TABLE public.shipping_country_rates (
    id SERIAL PRIMARY KEY,
    shipping_country TEXT,
    shipping_country_base_rate DECIMAL(14,3)
);

INSERT INTO public.shipping_country_rates
(shipping_country, shipping_country_base_rate)
SELECT DISTINCT shipping_country, shipping_country_base_rate
FROM public.shipping;

-- shipping_agreement

CREATE TABLE public.shipping_agreement (
    agreementid BIGINT PRIMARY KEY,
    agreement_number TEXT,
    agreement_rate DECIMAL(14,3),
    agreement_commission DECIMAL(14,3)
);

INSERT INTO public.shipping_agreement (agreementid)
WITH
cte_vad AS (
    SELECT string_to_array(vendor_agreement_description, ':') vad
    FROM public.shipping
)
SELECT DISTINCT vad[1]::BIGINT FROM cte_vad
;

UPDATE public.shipping_agreement shcr
SET (agreement_number, agreement_rate, agreement_commission) =
(
    WITH
    cte_vad AS (
        SELECT string_to_array(vendor_agreement_description, ':') vad
        FROM public.shipping
    ),
    cte_vadd AS (
        SELECT DISTINCT
            vad[1]::BIGINT agreementid,
            vad[2] agreement_number,
            vad[3]::DECIMAL(14,3) agreement_rate,
            vad[4]::DECIMAL(14,3) agreement_commission
        FROM cte_vad
    )
    SELECT agreement_number, agreement_rate, agreement_commission
    FROM cte_vadd
    WHERE cte_vadd.agreementid = shcr.agreementid
);

-- shipping_transfer

CREATE TABLE public.shipping_transfer (
    id SERIAL PRIMARY KEY,
    transfer_type TEXT,
    transfer_model TEXT,
    shipping_transfer_rate DECIMAL(14,3)
);

INSERT INTO public.shipping_transfer
(transfer_type, transfer_model, shipping_transfer_rate)
WITH cte_shipping_transfer AS (
    SELECT
        string_to_array(shipping_transfer_description, ':') descr,
        shipping_transfer_rate
    FROM public.shipping
)
SELECT DISTINCT descr[1], descr[2], shipping_transfer_rate
FROM cte_shipping_transfer;

-- shipping_info

CREATE TABLE public.shipping_info (
    shippingid                BIGINT PRIMARY KEY,
    shipping_transfer_id      BIGINT NOT NULL,
    agreementid               BIGINT NOT NULL,
    shipping_country_rates_id BIGINT NOT NULL,
    shipping_plan_datetime    TIMESTAMP NOT NULL,
    payment_amount            DECIMAL(14,2) NOT NULL,
    vendorid                  BIGINT NOT NULL,
    FOREIGN KEY (shipping_transfer_id)
        REFERENCES public.shipping_transfer(id) ON UPDATE cascade,
    FOREIGN KEY (agreementid)
        REFERENCES public.shipping_agreement(agreementid) ON UPDATE cascade,
    FOREIGN KEY (shipping_country_rates_id)
        REFERENCES public.shipping_country_rates(id) ON UPDATE cascade
);

INSERT INTO public.shipping_info
(
    shippingid,
    shipping_transfer_id,
    agreementid,
    shipping_country_rates_id,
    shipping_plan_datetime,
    payment_amount,
    vendorid
)
WITH cte_arrays AS (
    SELECT
        shippingid,
        shipping_plan_datetime,
        payment_amount,
        vendorid,
        string_to_array(shipping_transfer_description, ':') t_descr,
        shipping_transfer_rate,
        string_to_array(vendor_agreement_description, ':') as "vad",
        shipping_country,
        shipping_country_base_rate
    FROM
        public.shipping
) SELECT
    shippingid,
    MAX(t.id),
    MAX(a.agreementid),
    MAX(r.id),
    MAX(shipping_plan_datetime),
    MAX(payment_amount),
    MAX(vendorid)
FROM
    cte_arrays "arr"
    INNER JOIN public.shipping_transfer "t" ON (
        t.transfer_type = arr.t_descr[1]
        AND t.transfer_model = arr.t_descr[2]
        AND t.shipping_transfer_rate = arr.shipping_transfer_rate
    )
    INNER JOIN public.shipping_agreement "a" ON a.agreementid = arr.vad[1]::BIGINT
    INNER JOIN public.shipping_country_rates "r" ON (
        r.shipping_country = arr.shipping_country
        AND r.shipping_country_base_rate = arr.shipping_country_base_rate
    )
GROUP BY
    shippingid
;

-- shipping_status

CREATE TABLE public.shipping_status (
    shippingid BIGINT PRIMARY KEY,
    status TEXT,
    state TEXT,
    shipping_start_fact_datetime TIMESTAMP DEFAULT NULL,
    shipping_end_fact_datetime TIMESTAMP DEFAULT NULL
);

INSERT INTO public.shipping_status
(shippingid, status, state)
WITH
cte_max_state_datetime AS (
    SELECT shippingid, MAX(state_datetime) AS dt
    FROM public.shipping
    GROUP BY shippingid
)
SELECT
    s.shippingid,
    s.status,
    s.state
FROM
    cte_max_state_datetime m
    INNER JOIN public.shipping s ON (
        s.shippingid = m.shippingid
        AND s.state_datetime = m.dt
    )
;

UPDATE public.shipping_status s
SET (shipping_start_fact_datetime) =
(
    WITH
    cte_min_booked AS (
        SELECT shippingid, MIN(state_datetime) AS dt
        FROM public.shipping
        WHERE state = 'booked'
        GROUP BY shippingid
    )
    SELECT dt
    FROM cte_min_booked b
    WHERE b.shippingid = s.shippingid
);

UPDATE public.shipping_status s
SET (shipping_end_fact_datetime) =
(
    WITH
    cte_min_recieved AS (
        SELECT shippingid, MIN(state_datetime) AS dt
        FROM public.shipping
        WHERE state = 'recieved'
        GROUP BY shippingid
    )
    SELECT dt
    FROM cte_min_recieved r
    WHERE r.shippingid = s.shippingid
);