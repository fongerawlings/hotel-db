USE hotel_db;

-- Query 1: rooms of a given type available between two dates (BR-03, BR-07)
-- Availability is derived only from reservations, never from the room status.
-- The stay is read as nights [from, to): a room is taken if a non-cancelled
-- reservation overlaps those nights.
SET @room_type = 'Double';
SET @period_from = '2026-07-04';
SET @period_to = '2026-07-06';

SELECT r.room_id,
       r.room_number,
       r.`floor`,
       r.max_capacity,
       r.base_price_per_night
FROM room r
JOIN room_type rt ON rt.room_type_id = r.room_type_id
WHERE rt.name = @room_type
  AND NOT EXISTS (
        SELECT 1
        FROM reservation_room rr
        JOIN reservation res ON res.reservation_id = rr.reservation_id
        WHERE rr.room_id = r.room_id
          AND res.status <> 'cancelled'
          AND res.check_in_date < @period_to
          AND res.check_out_date > @period_from
      )
ORDER BY r.room_number;

-- Query 2: monthly occupancy rate = nights sold / nights available
-- A recursive CTE builds one row per month covering all non-cancelled stays.
-- Nights sold: for each room of each non-cancelled reservation, the number of
-- nights that fall inside the month.
-- Nights available: number of rooms x number of days in the month.
WITH RECURSIVE months AS (
    SELECT DATE_SUB(MIN(check_in_date), INTERVAL DAYOFMONTH(MIN(check_in_date)) - 1 DAY) AS month_start
    FROM reservation
    WHERE status <> 'cancelled'
    UNION ALL
    SELECT DATE_ADD(month_start, INTERVAL 1 MONTH)
    FROM months
    WHERE month_start < (SELECT MAX(check_out_date) FROM reservation WHERE status <> 'cancelled')
)
SELECT month,
       nights_sold,
       nights_available,
       ROUND(100 * nights_sold / nights_available, 2) AS occupancy_rate_pct
FROM (
    SELECT DATE_FORMAT(m.month_start, '%Y-%m') AS month,
           COALESCE(SUM(GREATEST(0, DATEDIFF(
               LEAST(res.check_out_date, DATE_ADD(m.month_start, INTERVAL 1 MONTH)),
               GREATEST(res.check_in_date, m.month_start)
           ))), 0) AS nights_sold,
           (SELECT COUNT(*) FROM room) * DAY(LAST_DAY(m.month_start)) AS nights_available
    FROM months m
    LEFT JOIN reservation res
           ON res.status <> 'cancelled'
          AND res.check_in_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
          AND res.check_out_date > m.month_start
    LEFT JOIN reservation_room rr ON rr.reservation_id = res.reservation_id
    GROUP BY m.month_start
) monthly
ORDER BY month;

-- Query 3: monthly revenue split between accommodation and services (BR-13)
-- Revenue is attributed to the month of the invoice issue date and includes tax.
-- Each line amount is rounded to 2 decimals, as in sp_record_payment.
-- Miscellaneous charges are shown in their own column so that the total is complete.
SELECT DATE_FORMAT(i.issue_date, '%Y-%m') AS month,
       SUM(CASE WHEN il.line_type = 'night'
                THEN ROUND(il.quantity * il.unit_price * (1 + il.tax_rate / 100), 2)
                ELSE 0 END) AS accommodation_revenue,
       SUM(CASE WHEN il.line_type = 'service'
                THEN ROUND(il.quantity * il.unit_price * (1 + il.tax_rate / 100), 2)
                ELSE 0 END) AS services_revenue,
       SUM(CASE WHEN il.line_type = 'misc'
                THEN ROUND(il.quantity * il.unit_price * (1 + il.tax_rate / 100), 2)
                ELSE 0 END) AS miscellaneous_revenue,
       SUM(ROUND(il.quantity * il.unit_price * (1 + il.tax_rate / 100), 2)) AS total_revenue
FROM invoice i
JOIN invoice_line il ON il.invoice_id = i.invoice_id
GROUP BY DATE_FORMAT(i.issue_date, '%Y-%m')
ORDER BY month;

-- Query 4: unpaid invoices with the outstanding balance, oldest first (BR-14, BR-15)
-- Totals and payments are computed in separate subqueries so that joining
-- lines and payments does not multiply rows.
-- The balance is computed from the amounts, not from the stored status.
SELECT i.invoice_id,
       c.last_name,
       c.first_name,
       i.issue_date,
       i.status,
       t.total_amount,
       COALESCE(p.paid_amount, 0) AS paid_amount,
       t.total_amount - COALESCE(p.paid_amount, 0) AS balance_due
FROM invoice i
JOIN reservation r ON r.reservation_id = i.reservation_id
JOIN client c ON c.client_id = r.client_id
JOIN (
    SELECT invoice_id,
           SUM(ROUND(quantity * unit_price * (1 + tax_rate / 100), 2)) AS total_amount
    FROM invoice_line
    GROUP BY invoice_id
) t ON t.invoice_id = i.invoice_id
LEFT JOIN (
    SELECT invoice_id, SUM(amount) AS paid_amount
    FROM payment
    GROUP BY invoice_id
) p ON p.invoice_id = i.invoice_id
WHERE t.total_amount - COALESCE(p.paid_amount, 0) > 0
ORDER BY i.issue_date ASC, i.invoice_id ASC;

-- Query 5: average rating and number of reviews per room type (BR-16, BR-17)
-- A review belongs to a reservation, which can include rooms of several types.
-- The review counts once for each distinct type in its stay.
-- DISTINCT avoids double counting when a stay has two rooms of the same type.
-- Types with no review appear with 0 reviews and a NULL average.
SELECT rt.name AS room_type,
       COUNT(x.review_id) AS review_count,
       ROUND(AVG(x.rating), 2) AS average_rating
FROM room_type rt
LEFT JOIN (
    SELECT DISTINCT rev.review_id, rev.rating, r.room_type_id
    FROM review rev
    JOIN reservation_room rr ON rr.reservation_id = rev.reservation_id
    JOIN room r ON r.room_id = rr.room_id
) x ON x.room_type_id = rt.room_type_id
GROUP BY rt.room_type_id, rt.name
ORDER BY average_rating DESC, rt.name;

-- Query 6: the 5 highest-spending clients with their number of stays
-- Spending is the total of the invoices (tax included) of their completed
-- reservations. A stay is a completed reservation.
-- COUNT(DISTINCT ...) keeps the stay count correct despite the line-level join.
SELECT c.client_id,
       c.last_name,
       c.first_name,
       COUNT(DISTINCT r.reservation_id) AS number_of_stays,
       SUM(ROUND(il.quantity * il.unit_price * (1 + il.tax_rate / 100), 2)) AS total_spent
FROM client c
JOIN reservation r ON r.client_id = c.client_id AND r.status = 'completed'
JOIN invoice i ON i.reservation_id = r.reservation_id
JOIN invoice_line il ON il.invoice_id = i.invoice_id
GROUP BY c.client_id, c.last_name, c.first_name
ORDER BY total_spent DESC
LIMIT 5;