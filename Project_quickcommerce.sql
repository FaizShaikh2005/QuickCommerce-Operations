create database quickcommerce;

use quickcommerce;

CREATE TABLE qc_orders (
    order_id VARCHAR(15) PRIMARY KEY,
    customer_id VARCHAR(12),
    dark_store_id VARCHAR(10),
    city VARCHAR(20),
    zone VARCHAR(30),
    order_timestamp DATETIME,
    order_date DATE,
    order_hour TINYINT,
    order_day_of_week VARCHAR(10),
    promised_delivery_mins INT,
    actual_delivery_mins DECIMAL(5,1),
    delivery_status VARCHAR(20),
    order_value DECIMAL(10,2),
    delivery_fee INT,
    payment_method VARCHAR(20),
    n_items INT
);

CREATE TABLE qc_order_items (
    item_id VARCHAR(15) PRIMARY KEY,
    order_id VARCHAR(15),
    product_id VARCHAR(10),
    product_name VARCHAR(60),
    category VARCHAR(30),
    quantity INT,
    unit_price DECIMAL(8,2),
    total_price DECIMAL(8,2),
    stockout_flag TINYINT
);

CREATE TABLE qc_inventory (
    inventory_id VARCHAR(15) PRIMARY KEY,
    dark_store_id VARCHAR(10),
    product_id VARCHAR(10),
    product_name VARCHAR(60),
    category VARCHAR(30),
    week_start_date DATE,
    opening_stock INT,
    units_sold INT,
    restock_quantity INT,
    closing_stock INT,
    stockout_occurred TINYINT
);

select
distinct delivery_status
from qc_orders;
# 1 
-- What is the overall scale of this quick commerce operation? 
-- Give me total orders, total revenue, average order value, cancellation rate,
--  and SLA breach rate (orders delivered late as % of delivered orders).


select
count(distinct order_id) as total_orders,
sum(case when delivery_status != 'cancelled' then order_value else 0 end)
as total_Revenue,
avg(order_value) as avg_order_value,
count(case when delivery_status = 'cancelled' then 1 end) / 
count(distinct order_id) * 100.0 as cancellation_rate,
count(case when delivery_status = 'delivered late' then 1 end) * 100.0  / 
nullif(count(case when delivery_status in ('delivered late','delivered on time') then 1
end),0) as sla_breach_rate
from qc_orders;


-- Business insight: 78.65% SLA breach is extremely high — nearly 4 in 5 
-- deliveries are late. This is the core problem this entire project investigates.
--  Good finding to note.



-- Query 2 — City-wise Performance:

-- Business Question:
-- Which cities are performing best and worst? For each city show: total orders, 
-- total revenue, avg order value, SLA breach rate, and cancellation rate. 
-- Order by total revenue descending.



select
city,
count(distinct order_id) as total_orders,
sum(case when delivery_status != 'cancelled' then order_value else 0 end)
as total_Revenue,
avg(order_value) as avg_order_value,
count(case when delivery_status = 'delivered late' then 1 end) * 100.0 /
nullif(count(case when delivery_status in ('delivered late','delivered on time') then 1 end),0)
as sla_breach_rate,
count(case when delivery_status = 'cancelled' then 1 end) * 100.0 /
count(distinct order_id) as cancellation_rate
from qc_orders
group by city
order by total_Revenue
desc;

-- Business insight: Mumbai and Delhi have the worst SLA breach rates (~88%)
--  — likely because of very high population density making last-mile delivery 
--  harder. Bengaluru and Hyderabad (tech hubs, better road planning) perform 
--  significantly better at ~71-73%.

-- Query 3 — Peak Demand Analysis:

-- Business Question:
-- When do customers order the most? Show order volume and avg order value by 
-- hour of day. Order by order_hour ASC so we can see the full 24-hour pattern.


select
order_hour,
count(distinct order_id) as total_orders,
avg(order_value) as average_order_value,
 ROUND(AVG(CASE WHEN actual_delivery_mins != -1 THEN actual_delivery_mins END), 1) 
 AS avg_delivery_mins
from qc_orders
group by order_hour
order by order_hour;


-- Peak hours	19:00–21:00 (1,370–1,541 orders) — dinner time surge
-- Dead hours	02:00–04:00 (33–73 orders) — 20x fewer than peak
-- Lunch spike	12:00–13:00 (~987–847 orders)
-- Delivery time jumps	12:00, 13:00, 19:00, 20:00, 21:00 all show ~20.5 mins vs ~15.5 mins at other hours


-- Delivery time nearly doubles during lunch (12-13h) and dinner (19-21h) 
-- peaks — exactly when order volume is highest. This is the classic 
-- quick commerce problem: demand spikes crush SLA performance. 
-- Operations team should add rider capacity during these windows.



-- Query 4 — Dark Store Performance (CTE):

-- Business Question:
-- Which dark stores are the best and worst performers? For each dark store
--  show city, zone, total orders, SLA breach rate, avg delivery time, 
--  and rank them within their city by SLA breach rate (worst first).


with cte as 
(
select
city,
zone,
count(distinct order_id) as total_orders,
count(case when delivery_status = 'delivered late' then 1 end) * 100.0 /
nullif(count(case when delivery_status in ('delivered late','delivered on time') then 1 end),0)
as sla_breach_rate,
avg(actual_delivery_mins) as avergae_delivery_time
from qc_orders
group by city,zone
),
cte_2 as 
(
select 
*,
rank() over(partition by city order by sla_breach_rate desc) as city_rank
from cte
)
select
* from cte_2
where city_rank <=3;


-- Business insight: Mumbai Borivali and Delhi Connaught Place are 
-- the worst performing zones — nearly 94% of deliveries are late. 
-- These zones need immediate attention: more riders, better route planning,
--  or capacity limits during peak hours. Notice avg delivery time also correlates
--  — higher breach rate = higher avg delivery time.


-- Query 5 — Category & Product Performance (JOIN):

-- Business Question:
-- Which product categories drive the most revenue and have the highest 
-- stockout problem? Show category, total revenue, total items sold, 
-- stockout count, and stockout rate %. Order by total revenue DESC.

SELECT
    i.category,
    ROUND(SUM(i.total_price), 2) AS total_revenue,
    COUNT(i.item_id) AS total_items_sold,
    SUM(i.stockout_flag) AS stockout_count,
    ROUND(SUM(i.stockout_flag) / COUNT(i.item_id) * 100, 2) AS stockout_rate
FROM qc_orders o
JOIN qc_order_items i ON o.order_id = i.order_id
WHERE o.delivery_status != 'cancelled'
GROUP BY i.category
ORDER BY total_revenue DESC;


-- Query 6 — Monthly Revenue Trend with MoM Growth (Window Function):

-- Business Question:
-- How did revenue trend month by month in 2024? Show each month’s total orders, 
-- revenue, and month-over-month revenue growth %.


with cte as 
(
select
date_format(order_date,'%Y-%m') as order_month,
count(distinct order_id) as total_orders,
sum(order_value) as revenue
from qc_orders
group by date_format(order_date,'%Y-%m')
)
select
*,
lag(revenue) over(order by order_month) as prev_month_revenue,
(revenue - lag(revenue) over(order by order_month)) / 
lag(revenue) over(order by order_month) * 100.0  
as Mom_pct
from cte;



-- Business insight: Revenue is stable across 2024 — no strong growth trend,
--  fluctuating between ₹6.8L–₹7.75L monthly. March was the best month (+13.3%), 
--  September worst (-9.5%). The alternating up-down pattern suggests no sustained 
--  growth momentum — the business is running flat. This is actually a useful 
--  insight: flat revenue despite operations running means either market saturation
--  or customer retention problem.



-- Query 7 — Delivery Time Buckets with CASE WHEN:

-- Business Question:
-- Categorize all delivered orders into delivery speed buckets and show how 
-- many orders fall in each bucket, what % of total they are, and the avg 
-- order value per bucket.

select
	case 
    when actual_delivery_mins < 12 then 'Lightning Fast'
	when actual_delivery_mins  between 12 and 15 then 'On target'
    when actual_delivery_mins  between 16 and 20 then 'Slightly Late'
    when actual_delivery_mins  between 21 and 30 then 'Very Late'
    when actual_delivery_mins > 30 then 'Unacceptable'
end as buckets,
count(distinct order_id) as total_orders,
count(*) * 100.0 / 
sum(count(*)) over() as pct_of_total,
avg(order_value) as average_order_value,
avg(actual_delivery_mins) as avg_delivery_time
from qc_orders
where actual_delivery_mins != -1
group by buckets
order by avg_delivery_time;





SELECT 
    CASE 
        WHEN actual_delivery_mins < 12 THEN 'Lightning Fast'
        WHEN actual_delivery_mins BETWEEN 12 AND 15 THEN 'On Target'
        WHEN actual_delivery_mins BETWEEN 16 AND 20 THEN 'Slightly Late'
        WHEN actual_delivery_mins BETWEEN 21 AND 30 THEN 'Very Late'
        ELSE 'Unacceptable'
    END AS delivery_bucket,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage_of_total,
    ROUND(AVG(order_value), 2) AS avg_order_value,
    ROUND(AVG(actual_delivery_mins), 2) AS avg_delivery_time
FROM 
    qc_orders
WHERE 
    actual_delivery_mins != -1
GROUP BY 
    CASE 
        WHEN actual_delivery_mins < 12 THEN 'Lightning Fast'
        WHEN actual_delivery_mins BETWEEN 12 AND 15 THEN 'On Target'
        WHEN actual_delivery_mins BETWEEN 16 AND 20 THEN 'Slightly Late'
        WHEN actual_delivery_mins BETWEEN 21 AND 30 THEN 'Very Late'
        ELSE 'Unacceptable'
    END
ORDER BY 
    avg_delivery_time ASC;


-- Business insight: Only 39% of orders are delivered within 15 mins
--  (Lightning Fast + On Target). 61% take longer. 14.7% are outright 
--  unacceptable (30+ mins). For a quick commerce company promising 10-
--  minute delivery, this is a serious problem worth investigating.


-- Query 8 — Inventory Health & Stockout Analysis:

-- Business Question:
-- Which product categories have the worst inventory health? From 
-- the qc_inventory table show: category, total weeks tracked, 
-- total stockout occurrences, stockout rate %, avg closing stock, and avg 
-- restock quantity. Order by stockout rate DESC.

SELECT
    category,
    COUNT(*) AS weeks_tracked,
    SUM(stockout_occurred) AS stockout_occurrences,
    ROUND(SUM(stockout_occurred) / COUNT(*) * 100, 2) AS stockout_rate,
    ROUND(AVG(closing_stock), 1) AS avg_closing_stock,
    ROUND(AVG(restock_quantity), 1) AS avg_restock_qty
FROM qc_inventory
GROUP BY category
ORDER BY stockout_rate DESC;



-- Query 9 — Customer Order Frequency Segments

-- Business Question: What does our customer base look like in terms of loyalty? 
-- How many customers ordered just once vs became regulars? And what’s the revenue 
-- difference between a one-time buyer and a power user?


WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        ROUND(SUM(order_value), 2) AS total_spent,
        ROUND(AVG(order_value), 2) AS avg_order_value,
        MIN(order_date) AS first_order,
        MAX(order_date) AS last_order
    FROM qc_orders
    WHERE delivery_status != 'Cancelled'
    GROUP BY customer_id
),
segmented AS (
    SELECT *,
        CASE
            WHEN total_orders = 1 THEN '1. One-time'
            WHEN total_orders BETWEEN 2 AND 3 THEN '2. Occasional'
            WHEN total_orders BETWEEN 4 AND 6 THEN '3. Regular'
            WHEN total_orders BETWEEN 7 AND 10 THEN '4. Frequent'
            ELSE '5. Power User'
        END AS customer_segment
    FROM customer_orders
)
SELECT
    customer_segment,
    COUNT(*) AS total_customers,
    ROUND(AVG(total_orders), 1) AS avg_orders,
    ROUND(AVG(total_spent), 2) AS avg_lifetime_value,
    ROUND(AVG(avg_order_value), 2) AS avg_order_value
FROM segmented
GROUP BY customer_segment
ORDER BY customer_segment;




-- Query 10 — Peak Hour × City SLA Heatmap

-- Business Question: Where and when does delivery performance break down 
-- the most? Which city-time combination is the worst operational failure point?


WITH base AS (
    SELECT
        city,
        CASE
            WHEN order_hour BETWEEN 6 AND 11 THEN '1. Morning (6-11)'
            WHEN order_hour BETWEEN 12 AND 14 THEN '2. Lunch (12-14)'
            WHEN order_hour BETWEEN 15 AND 17 THEN '3. Afternoon (15-17)'
            WHEN order_hour BETWEEN 18 AND 21 THEN '4. Evening (18-21)'
            ELSE '5. Late Night (22-5)'
        END AS time_slot,
        delivery_status,
        actual_delivery_mins
    FROM qc_orders
),
heatmap AS (
    SELECT
        city,
        time_slot,
        COUNT(*) AS total_orders,
        ROUND(COUNT(CASE WHEN delivery_status = 'Delivered Late' THEN 1 END) * 100.0 /
            NULLIF(COUNT(CASE WHEN delivery_status != 'Cancelled' THEN 1 END), 0), 2) AS sla_breach_rate,
        ROUND(AVG(CASE WHEN actual_delivery_mins != -1 THEN actual_delivery_mins END), 1) AS avg_delivery_mins
    FROM base
    GROUP BY city, time_slot
)
SELECT
    city,
    time_slot,
    total_orders,
    sla_breach_rate,
    avg_delivery_mins,
    RANK() OVER (PARTITION BY time_slot ORDER BY sla_breach_rate DESC) AS worst_city_rank
FROM heatmap
ORDER BY time_slot, sla_breach_rate DESC;
























