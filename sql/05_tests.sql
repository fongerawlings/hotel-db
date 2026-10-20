USE hotel_db;

DROP PROCEDURE IF EXISTS sp_expect_rejection;
DROP TEMPORARY TABLE IF EXISTS test_results;

CREATE TEMPORARY TABLE test_results (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    rule_id VARCHAR(20) NOT NULL,
    test_case VARCHAR(150) NOT NULL,
    outcome VARCHAR(4) NOT NULL,
    reason TEXT NULL,
    PRIMARY KEY (id)
);

DELIMITER $$

CREATE PROCEDURE sp_expect_rejection(
    IN p_rule VARCHAR(20),
    IN p_case VARCHAR(150),
    IN p_statement TEXT
)
BEGIN
    DECLARE v_rejected TINYINT DEFAULT 0;
    DECLARE v_reason TEXT DEFAULT NULL;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_reason = MESSAGE_TEXT;
        SET v_rejected = 1;
    END;

    SET @test_statement = p_statement;
    PREPARE test_stmt FROM @test_statement;
    EXECUTE test_stmt;
    DEALLOCATE PREPARE test_stmt;

    INSERT INTO test_results (rule_id, test_case, outcome, reason)
    VALUES (p_rule, p_case, IF(v_rejected = 1, 'PASS', 'FAIL'), v_reason);
END$$

DELIMITER ;

START TRANSACTION;

CALL sp_expect_rejection('BR-05', 'Confirm a reservation with more guests than the room capacity',
    'UPDATE reservation SET status = ''confirmed'', guest_count = 2 WHERE reservation_id = 14');

CALL sp_expect_rejection('BR-05', 'Create a reservation directly as confirmed',
    'INSERT INTO reservation (client_id, check_in_date, check_out_date, guest_count, status) VALUES (10, ''2027-01-10'', ''2027-01-12'', 2, ''confirmed'')');

CALL sp_expect_rejection('BR-05', 'Raise the guest count above capacity on a confirmed reservation',
    'UPDATE reservation SET guest_count = 5 WHERE reservation_id = 18');

CALL sp_expect_rejection('BR-07', 'Add a room already reserved for overlapping nights',
    'INSERT INTO reservation_room (reservation_id, room_id, nightly_price) VALUES (17, 14, 100000.00)');

CALL sp_expect_rejection('BR-07', 'Move a reservation onto dates already taken in its room',
    'UPDATE reservation SET check_in_date = ''2026-10-15'', check_out_date = ''2026-10-19'' WHERE reservation_id = 13');

CALL sp_expect_rejection('BR-07', 'Reactivate a cancelled reservation whose room was rebooked',
    'UPDATE reservation SET status = ''pending'', cancelled_at = NULL WHERE reservation_id = 11');

CALL sp_expect_rejection('BR-16', 'Review a reservation that is not completed',
    'INSERT INTO review (reservation_id, rating, `comment`, review_date) VALUES (15, 4, ''Too early'', ''2026-10-20'')');

CALL sp_expect_rejection('BR-16', 'Second review for the same reservation',
    'INSERT INTO review (reservation_id, rating, `comment`, review_date) VALUES (1, 3, ''Duplicate'', ''2026-08-01'')');

CALL sp_expect_rejection('BR-17', 'Review dated before the check-out date',
    'INSERT INTO review (reservation_id, rating, `comment`, review_date) VALUES (3, 4, ''Too early'', ''2026-07-19'')');

CALL sp_expect_rejection('BR-17', 'Rating outside the range 1 to 5',
    'INSERT INTO review (reservation_id, rating, `comment`, review_date) VALUES (3, 6, NULL, ''2026-07-21'')');

CALL sp_expect_rejection('BR-12', 'Service booked beyond the slot capacity',
    'INSERT INTO service_booking (reservation_id, service_id, booking_date, start_time, guests) VALUES (15, 1, ''2026-10-16'', ''10:00:00'', 3)');

CALL sp_expect_rejection('BR-12', 'Service booked on a day when it is closed',
    'INSERT INTO service_booking (reservation_id, service_id, booking_date, start_time, guests) VALUES (16, 1, ''2026-12-21'', ''10:00:00'', 2)');

CALL sp_expect_rejection('BR-12', 'Service booked outside the stay',
    'INSERT INTO service_booking (reservation_id, service_id, booking_date, start_time, guests) VALUES (15, 3, ''2026-10-25'', ''07:00:00'', 1)');

CALL sp_expect_rejection('BR-12', 'Service booked at a time that is not a slot boundary',
    'INSERT INTO service_booking (reservation_id, service_id, booking_date, start_time, guests) VALUES (15, 1, ''2026-10-16'', ''10:30:00'', 1)');

ROLLBACK;

CALL sp_expect_rejection('BR-14', 'Payment larger than the outstanding balance',
    'CALL sp_record_payment(10, 999999.00, ''cash'')');

CALL sp_expect_rejection('BR-14', 'Payment that is not strictly positive',
    'CALL sp_record_payment(10, 0.00, ''cash'')');

CALL sp_expect_rejection('BR-14', 'Payment on an invoice that does not exist',
    'CALL sp_record_payment(9999, 50.00, ''cash'')');

SELECT id, rule_id, test_case, outcome, reason
FROM test_results
ORDER BY id;

SELECT COUNT(*) AS total_tests,
       SUM(outcome = 'PASS') AS passed,
       SUM(outcome = 'FAIL') AS failed
FROM test_results;

DROP TEMPORARY TABLE test_results;
DROP PROCEDURE sp_expect_rejection;