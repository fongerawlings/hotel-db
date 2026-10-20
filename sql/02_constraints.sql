USE hotel_db;

DELIMITER $$

CREATE PROCEDURE sp_check_service_booking(
    IN p_reservation_id INT UNSIGNED,
    IN p_service_id SMALLINT UNSIGNED,
    IN p_date DATE,
    IN p_start TIME,
    IN p_guests SMALLINT UNSIGNED,
    IN p_exclude_id INT UNSIGNED
)
BEGIN
    DECLARE v_check_in DATE;
    DECLARE v_check_out DATE;
    DECLARE v_status VARCHAR(20);
    DECLARE v_open TIME;
    DECLARE v_close TIME;
    DECLARE v_duration INT;
    DECLARE v_capacity INT;
    DECLARE v_booked INT;
    DECLARE v_found INT;

    SELECT check_in_date, check_out_date, status
      INTO v_check_in, v_check_out, v_status
      FROM reservation
     WHERE reservation_id = p_reservation_id;

    IF v_status = 'cancelled' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-12: a service cannot be booked on a cancelled reservation';
    END IF;

    IF p_date < v_check_in OR p_date > v_check_out THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-12: the service date must fall within the stay';
    END IF;

    SELECT slot_duration_minutes, slot_capacity
      INTO v_duration, v_capacity
      FROM service
     WHERE service_id = p_service_id;

    SELECT COUNT(*) INTO v_found
      FROM service_opening_hours
     WHERE service_id = p_service_id
       AND day_of_week = WEEKDAY(p_date) + 1;

    IF v_found = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-12: the service is closed on that day';
    END IF;

    SELECT opening_time, closing_time
      INTO v_open, v_close
      FROM service_opening_hours
     WHERE service_id = p_service_id
       AND day_of_week = WEEKDAY(p_date) + 1;

    IF p_start < v_open
       OR TIME_TO_SEC(p_start) + v_duration * 60 > TIME_TO_SEC(v_close) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-12: the slot is outside the opening hours';
    END IF;

    IF MOD(TIME_TO_SEC(p_start) - TIME_TO_SEC(v_open), v_duration * 60) <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-12: the start time does not match a slot boundary';
    END IF;

    SELECT COALESCE(SUM(sb.guests), 0) INTO v_booked
      FROM service_booking sb
      JOIN reservation r ON r.reservation_id = sb.reservation_id
     WHERE sb.service_id = p_service_id
       AND sb.booking_date = p_date
       AND sb.start_time = p_start
       AND sb.service_booking_id <> p_exclude_id
       AND r.status <> 'cancelled';

    IF v_booked + p_guests > v_capacity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-12: the slot capacity would be exceeded';
    END IF;
END$$

CREATE TRIGGER trg_service_booking_before_insert
BEFORE INSERT ON service_booking
FOR EACH ROW
BEGIN
    CALL sp_check_service_booking(
        NEW.reservation_id, NEW.service_id, NEW.booking_date,
        NEW.start_time, NEW.guests, NEW.service_booking_id
    );
END$$

CREATE TRIGGER trg_service_booking_before_update
BEFORE UPDATE ON service_booking
FOR EACH ROW
BEGIN
    CALL sp_check_service_booking(
        NEW.reservation_id, NEW.service_id, NEW.booking_date,
        NEW.start_time, NEW.guests, NEW.service_booking_id
    );
END$$

CREATE TRIGGER trg_reservation_room_before_insert
BEFORE INSERT ON reservation_room
FOR EACH ROW
BEGIN
    DECLARE v_check_in DATE;
    DECLARE v_check_out DATE;
    DECLARE v_status VARCHAR(20);
    DECLARE v_conflicts INT;

    SELECT check_in_date, check_out_date, status
      INTO v_check_in, v_check_out, v_status
      FROM reservation
     WHERE reservation_id = NEW.reservation_id;

    IF v_status <> 'cancelled' THEN
        SELECT COUNT(*) INTO v_conflicts
          FROM reservation_room rr
          JOIN reservation r ON r.reservation_id = rr.reservation_id
         WHERE rr.room_id = NEW.room_id
           AND rr.reservation_id <> NEW.reservation_id
           AND r.status <> 'cancelled'
           AND r.check_in_date < v_check_out
           AND r.check_out_date > v_check_in;

        IF v_conflicts > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BR-07: the room is already reserved for overlapping nights';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_reservation_before_insert
BEFORE INSERT ON reservation
FOR EACH ROW
BEGIN
    IF NEW.status IN ('confirmed', 'completed') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-05: create the reservation as pending, add its rooms, then confirm it';
    END IF;
END$$

CREATE TRIGGER trg_reservation_before_update
BEFORE UPDATE ON reservation
FOR EACH ROW
BEGIN
    DECLARE v_conflicts INT;
    DECLARE v_capacity INT;

    IF NEW.status <> 'cancelled'
       AND (NEW.check_in_date <> OLD.check_in_date
            OR NEW.check_out_date <> OLD.check_out_date
            OR OLD.status = 'cancelled') THEN

        SELECT COUNT(*) INTO v_conflicts
          FROM reservation_room mine
          JOIN reservation_room other
            ON other.room_id = mine.room_id
           AND other.reservation_id <> mine.reservation_id
          JOIN reservation r2 ON r2.reservation_id = other.reservation_id
         WHERE mine.reservation_id = NEW.reservation_id
           AND r2.status <> 'cancelled'
           AND r2.check_in_date < NEW.check_out_date
           AND r2.check_out_date > NEW.check_in_date;

        IF v_conflicts > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BR-07: the new dates overlap another reservation of the same room';
        END IF;
    END IF;

    IF NEW.status IN ('confirmed', 'completed')
       AND (OLD.status NOT IN ('confirmed', 'completed')
            OR NEW.guest_count <> OLD.guest_count) THEN

        SELECT COALESCE(SUM(r.max_capacity), 0) INTO v_capacity
          FROM reservation_room rr
          JOIN room r ON r.room_id = rr.room_id
         WHERE rr.reservation_id = NEW.reservation_id;

        IF NEW.guest_count > v_capacity THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BR-05: the number of guests exceeds the total capacity of the reserved rooms';
        END IF;
    END IF;
END$$

CREATE PROCEDURE sp_check_review(
    IN p_reservation_id INT UNSIGNED,
    IN p_review_date DATE
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_check_out DATE;

    SELECT status, check_out_date
      INTO v_status, v_check_out
      FROM reservation
     WHERE reservation_id = p_reservation_id;

    IF v_status <> 'completed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-16: a review can only be linked to a completed reservation';
    END IF;

    IF p_review_date < v_check_out THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-17: the review date cannot be before the check-out date';
    END IF;
END$$

CREATE TRIGGER trg_review_before_insert
BEFORE INSERT ON review
FOR EACH ROW
BEGIN
    CALL sp_check_review(NEW.reservation_id, NEW.review_date);
END$$

CREATE TRIGGER trg_review_before_update
BEFORE UPDATE ON review
FOR EACH ROW
BEGIN
    CALL sp_check_review(NEW.reservation_id, NEW.review_date);
END$$

CREATE PROCEDURE sp_record_payment(
    IN p_invoice_id INT UNSIGNED,
    IN p_amount DECIMAL(12,2),
    IN p_method VARCHAR(20)
)
BEGIN
    DECLARE v_found INT;
    DECLARE v_total DECIMAL(14,2);
    DECLARE v_paid DECIMAL(14,2);
    DECLARE v_new_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_found
      FROM invoice
     WHERE invoice_id = p_invoice_id;

    IF v_found = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-14: the invoice does not exist';
    END IF;

    SELECT invoice_id INTO v_found
      FROM invoice
     WHERE invoice_id = p_invoice_id
       FOR UPDATE;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-14: the payment amount must be strictly positive';
    END IF;

    SELECT COALESCE(SUM(ROUND(quantity * unit_price * (1 + tax_rate / 100), 2)), 0)
      INTO v_total
      FROM invoice_line
     WHERE invoice_id = p_invoice_id;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-13: the invoice has no lines to pay';
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO v_paid
      FROM payment
     WHERE invoice_id = p_invoice_id;

    IF v_paid + p_amount > v_total THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-14: the payment exceeds the outstanding balance';
    END IF;

    INSERT INTO payment (invoice_id, amount, method)
    VALUES (p_invoice_id, p_amount, p_method);

    SET v_paid = v_paid + p_amount;

    IF v_paid >= v_total THEN
        SET v_new_status = 'paid';
    ELSEIF v_paid > 0 THEN
        SET v_new_status = 'partially_paid';
    ELSE
        SET v_new_status = 'due';
    END IF;

    UPDATE invoice
       SET status = v_new_status
     WHERE invoice_id = p_invoice_id;

    COMMIT;
END$$

DELIMITER ;