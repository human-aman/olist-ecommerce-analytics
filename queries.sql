-- Olist E-Commerce Analytics
-- PostgreSQL queries covering growth, retention, 
-- category performance, logistics CX, and regional analysis
-- Dataset: 100k+ orders, 8 tables, 2016-2018
-- Author: Aman Vyas | github.com/human-aman

--order status count
select order_status, count(order_status) 
from orders
group by 1 order by 2 asc;

-- purchase count per month
select TO_CHAR(order_purchase_timestamp, 'YYYY-MM'), COUNT(Order_id) 
from orders
group by 1 order by 1;

-- purchase value per month
select TO_CHAR(order_purchase_timestamp, 'YYYY-MM'), SUM(payment_value) 
from orders
join order_payments
on order_payments.order_id = orders.order_id 
group by 1 order by 1;

-- avg purchase value AOV per month
select TO_CHAR(order_purchase_timestamp, 'YYYY-MM'), SUM(payment_value)/COUNT(orders.order_id) as AVG_Order_Value 
from orders
join order_payments
on order_payments.order_id = orders.order_id 
group by 1 
HAVING COUNT(orders.order_id) > 100 --remove noise from months with low order count
order by 1;

--Count of repeat customers
select COUNT(X.customer_unique_id) 
from (
	select customers.customer_unique_id, COUNT(orders.order_id) as count_orders, COUNT(customers.customer_unique_id) as count_customers_unique
	from customers
	join orders
	on orders.customer_id = customers.customer_id
	group by customers.customer_unique_id order by 2 desc) X
where X.count_orders >1;

-- percentage of repeat customers
select ROUND(COUNT(case when X.count_orders >1 then X.customer_unique_id end)*100.0/COUNT(X.customer_unique_id),2) as Percentage_Repeat_Customers
from (
	select customers.customer_unique_id, COUNT(orders.order_id) as count_orders
	from customers
	left join orders
	on orders.customer_id = customers.customer_id
	group by customers.customer_unique_id order by 2 desc) X;

--Corrected query for delivery time bucket analysis of Review Scores
SELECT
    CASE
        WHEN DATE_PART('day', o.order_delivered_customer_date::timestamp -
             o.order_purchase_timestamp) BETWEEN 0 AND 7 THEN '0-7 days'
        WHEN DATE_PART('day', o.order_delivered_customer_date::timestamp -
             o.order_purchase_timestamp) BETWEEN 8 AND 14 THEN '8-14 days'
        WHEN DATE_PART('day', o.order_delivered_customer_date::timestamp -
             o.order_purchase_timestamp) BETWEEN 15 AND 21 THEN '15-21 days'
        WHEN DATE_PART('day', o.order_delivered_customer_date::timestamp -
             o.order_purchase_timestamp) > 21 THEN '21+ days'
    END AS delivery_bucket,
    ROUND(AVG(r.review_score::numeric), 2) AS avg_review_score,
    COUNT(o.order_id) AS order_count
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE r.review_score IN ('1','2','3','4','5')
    AND o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_purchase_timestamp IS NOT NULL
    AND o.order_delivered_customer_date <> ''
GROUP BY delivery_bucket
ORDER BY delivery_bucket;

--AOV by product catergory
select X.product_category_name_english, ROUND(SUM(price)/COUNT(order_id),2) as AOV, COUNT(order_id) as order_count
from ( select *
from products
join product_category_translation
on products.product_category_name = product_category_translation.product_category_name) X
join order_items
on order_items.product_id = X.product_id
group by 1 order by 3 desc limit 20;

--Product Category Details that drove Nov '17 spike
select Z.product_category_name_english, SUM(Z.sku_count) as SKUs, SUM(Z.order_count) as Order_Units, SUM(Z.price*Z.order_count) as Category_Revenue,  SUM(Z.price*Z.order_count)/SUM(Z.order_count) as AOV, SUM(Z.price*Z.order_count)/SUM(Z.sku_count) as APV --APV average product value
from ( select Y.product_category_name_english, Y.price, COUNT(Y.order_id) as order_count, COUNT(distinct Y.product_id) as sku_count
from ( select X.product_category_name_english, X.product_id, order_items.order_id, order_items.price
from ( select product_category_name_english, product_id 
from products
join product_category_translation
on products.product_category_name = product_category_translation.product_category_name) X
join order_items
on order_items.product_id = X.product_id) Y
join orders
on orders.order_id = Y.order_id
where orders.order_purchase_timestamp > '2017-10-31' and orders.order_purchase_timestamp < '2017-12-01'
group by Y.product_category_name_english, Y.price, Y.product_id order by 3 desc) Z
group by Z.product_category_name_english order by 2 desc;

--Corrected Regional Analysis of States by dilivery time buckets
select g.geolocation_state as State, SUM(Y.review_score::INTEGER)*1.0/COUNT(y.order_id) as Avg_Review_Score, AVG(DATE_PART('day', Y.order_delivered_customer_date::TIMESTAMP - Y.order_purchase_timestamp::TIMESTAMP)) as Avg_Delivery_Days, COUNT(Y.order_id) as Order_Count, ROUND(COUNT(case when Y.review_score < 4 then Y.order_id end)*100.0/COUNT(Y.order_id),2) as Low_Score_Rate
from (select X.customer_id, X.order_id, X.customer_state ,X.customer_zip_code_prefix, X.order_delivered_customer_date, X.order_purchase_timestamp, t.review_score::INTEGER
from (select c.customer_id, o.order_id, c.customer_state ,c.customer_zip_code_prefix, o.order_delivered_customer_date, o.order_purchase_timestamp, o.order_status 
from orders o 
join customers c
on o.customer_id = c.customer_id 
where o.order_status = 'delivered') X
join order_reviews t 
on t.order_id = X.order_id
where t.review_score != '' and t.review_score is not null
and t.review_score ~ '^[0-9]+$'
and X.order_delivered_customer_date <> '' ) Y
join (select DISTINCT geolocation_zip_code_prefix, geolocation_state 
      from geolocation) g
on g.geolocation_zip_code_prefix = Y.customer_zip_code_prefix
group by 1 order by 4 desc;

--Repeat vs first time customer AOV
select case when Y.order_count > 1 then 'Repeat' else 'First_time' end as customer_type, SUM(Y.AOV)/COUNT(Y.customer_unique_id) as overall_AOV
from (select X.customer_unique_id , COUNT(X.order_id) as order_count, SUM(op.payment_value)/COUNT(X.order_id) as AOV
from (select c.customer_unique_id , o.order_id
from customers c 
join orders o 
on o.customer_id = c.customer_id) X
join order_payments op 
on op.order_id = X.order_id 
group by 1 order by 3 desc) Y
group by customer_type;

--Checking duplicate geolocation rows
select geolocation_zip_code_prefix, COUNT(concat(geolocation_lat, geolocation_lng))
from geolocation
group by 1 order by 2 desc;

--Review comment text patterns
SELECT review_comment_message 
FROM order_reviews 
WHERE review_score ~ '^[0-9]+$'
AND review_score::INTEGER <= 2
LIMIT 10;

--Lower Review Score high frequency words in review
select word, count(*) as frequency
from (select LOWER(REGEXP_SPLIT_TO_TABLE(review_comment_message, '\s+')) as word
from order_reviews
where review_score ~ '^[0-9]+$'
and review_score::INTEGER <3 
and review_score != '') words
where length(word)>2
group by 1 order by 2 desc
limit 20;

--Higher Review Score high frequency words in review
select word, count(*) as frequency
from (select LOWER(REGEXP_SPLIT_TO_TABLE(review_comment_message, '\s+')) as word
from order_reviews
where review_score ~ '^[0-9]+$'
and review_score::INTEGER >3 
and review_score != '') words
where length(word)>2
group by 1 order by 2 desc
limit 20;

--Final table for powerBI export. Directly transforms to a column chart
SELECT r.review_score::integer, COUNT(o.order_id) as order_count
FROM orders o
JOIN order_reviews r 
    ON o.order_id = r.order_id
WHERE r.review_score IN ('1','2','3','4','5')
GROUP BY r.review_score::integer
ORDER BY r.review_score::integer;