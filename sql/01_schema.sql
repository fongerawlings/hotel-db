DROP DATABASE IF EXISTS hotel_db;
CREATE DATABASE hotel_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE hotel_db;

CREATE TABLE room_type (
    room_type_id TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL,
    description VARCHAR(255) NULL,
    PRIMARY KEY (room_type_id),
    CONSTRAINT uq_room_type_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE room_status (
    room_status_id TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(30) NOT NULL,
    PRIMARY KEY (room_status_id),
    CONSTRAINT uq_room_status_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE room (
    room_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_number VARCHAR(10) NOT NULL,
    `floor` TINYINT NOT NULL,
    room_type_id TINYINT UNSIGNED NOT NULL,
    room_status_id TINYINT UNSIGNED NOT NULL,
    max_capacity TINYINT UNSIGNED NOT NULL,
    base_price_per_night DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (room_id),
    CONSTRAINT uq_room_number UNIQUE (room_number),
    CONSTRAINT chk_room_capacity CHECK (max_capacity > 0),
    CONSTRAINT chk_room_price CHECK (base_price_per_night > 0),
    CONSTRAINT fk_room_type FOREIGN KEY (room_type_id)
        REFERENCES room_type (room_type_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_room_status FOREIGN KEY (room_status_id)
        REFERENCES room_status (room_status_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE amenity (
    amenity_id SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(60) NOT NULL,
    PRIMARY KEY (amenity_id),
    CONSTRAINT uq_amenity_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE room_amenity (
    room_id INT UNSIGNED NOT NULL,
    amenity_id SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (room_id, amenity_id),
    CONSTRAINT fk_room_amenity_room FOREIGN KEY (room_id)
        REFERENCES room (room_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_room_amenity_amenity FOREIGN KEY (amenity_id)
        REFERENCES amenity (amenity_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE client (
    client_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    last_name VARCHAR(60) NOT NULL,
    first_name VARCHAR(60) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(120) NOT NULL,
    PRIMARY KEY (client_id),
    CONSTRAINT uq_client_phone UNIQUE (phone),
    CONSTRAINT uq_client_email UNIQUE (email)
) ENGINE=InnoDB;

CREATE TABLE reservation (
    reservation_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    client_id INT UNSIGNED NOT NULL,
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    guest_count TINYINT UNSIGNED NOT NULL,
    status ENUM('pending','confirmed','cancelled','completed') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cancelled_at DATETIME NULL,
    PRIMARY KEY (reservation_id),
    CONSTRAINT chk_reservation_dates CHECK (check_out_date > check_in_date),
    CONSTRAINT chk_reservation_guests CHECK (guest_count > 0),
    CONSTRAINT chk_reservation_cancel CHECK (
        (status = 'cancelled' AND cancelled_at IS NOT NULL)
        OR (status <> 'cancelled' AND cancelled_at IS NULL)
    ),
    CONSTRAINT fk_reservation_client FOREIGN KEY (client_id)
        REFERENCES client (client_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_reservation_dates (check_in_date, check_out_date),
    INDEX idx_reservation_status (status)
) ENGINE=InnoDB;

CREATE TABLE reservation_room (
    reservation_id INT UNSIGNED NOT NULL,
    room_id INT UNSIGNED NOT NULL,
    nightly_price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (reservation_id, room_id),
    CONSTRAINT chk_reservation_room_price CHECK (nightly_price > 0),
    CONSTRAINT fk_resroom_reservation FOREIGN KEY (reservation_id)
        REFERENCES reservation (reservation_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_resroom_room FOREIGN KEY (room_id)
        REFERENCES room (room_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE service (
    service_id SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(80) NOT NULL,
    description VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    slot_duration_minutes SMALLINT UNSIGNED NOT NULL,
    slot_capacity SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (service_id),
    CONSTRAINT uq_service_name UNIQUE (name),
    CONSTRAINT chk_service_price CHECK (price >= 0),
    CONSTRAINT chk_service_duration CHECK (slot_duration_minutes > 0),
    CONSTRAINT chk_service_capacity CHECK (slot_capacity > 0)
) ENGINE=InnoDB;

CREATE TABLE service_opening_hours (
    service_id SMALLINT UNSIGNED NOT NULL,
    day_of_week TINYINT UNSIGNED NOT NULL,
    opening_time TIME NOT NULL,
    closing_time TIME NOT NULL,
    PRIMARY KEY (service_id, day_of_week),
    CONSTRAINT chk_hours_day CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT chk_hours_order CHECK (closing_time > opening_time),
    CONSTRAINT fk_hours_service FOREIGN KEY (service_id)
        REFERENCES service (service_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE service_booking (
    service_booking_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    reservation_id INT UNSIGNED NOT NULL,
    service_id SMALLINT UNSIGNED NOT NULL,
    booking_date DATE NOT NULL,
    start_time TIME NOT NULL,
    guests SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (service_booking_id),
    CONSTRAINT chk_booking_guests CHECK (guests > 0),
    CONSTRAINT fk_booking_reservation FOREIGN KEY (reservation_id)
        REFERENCES reservation (reservation_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_booking_service FOREIGN KEY (service_id)
        REFERENCES service (service_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_booking_slot (service_id, booking_date, start_time)
) ENGINE=InnoDB;

CREATE TABLE invoice (
    invoice_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    reservation_id INT UNSIGNED NOT NULL,
    issue_date DATE NOT NULL,
    status ENUM('due','partially_paid','paid') NOT NULL DEFAULT 'due',
    PRIMARY KEY (invoice_id),
    CONSTRAINT uq_invoice_reservation UNIQUE (reservation_id),
    CONSTRAINT fk_invoice_reservation FOREIGN KEY (reservation_id)
        REFERENCES reservation (reservation_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE invoice_line (
    invoice_line_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    invoice_id INT UNSIGNED NOT NULL,
    line_type ENUM('night','service','misc') NOT NULL,
    description VARCHAR(255) NOT NULL,
    service_booking_id INT UNSIGNED NULL,
    quantity INT UNSIGNED NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (invoice_line_id),
    CONSTRAINT chk_line_quantity CHECK (quantity > 0),
    CONSTRAINT chk_line_price CHECK (unit_price >= 0),
    CONSTRAINT chk_line_tax CHECK (tax_rate BETWEEN 0 AND 100),
    CONSTRAINT fk_line_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoice (invoice_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_line_booking FOREIGN KEY (service_booking_id)
        REFERENCES service_booking (service_booking_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE payment (
    payment_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    invoice_id INT UNSIGNED NOT NULL,
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(12,2) NOT NULL,
    method ENUM('cash','card','mobile_money','bank_transfer') NOT NULL,
    PRIMARY KEY (payment_id),
    CONSTRAINT chk_payment_amount CHECK (amount > 0),
    CONSTRAINT fk_payment_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoice (invoice_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_payment_invoice (invoice_id)
) ENGINE=InnoDB;

CREATE TABLE review (
    review_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    reservation_id INT UNSIGNED NOT NULL,
    rating TINYINT UNSIGNED NOT NULL,
    `comment` TEXT NULL,
    review_date DATE NOT NULL,
    PRIMARY KEY (review_id),
    CONSTRAINT uq_review_reservation UNIQUE (reservation_id),
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_review_reservation FOREIGN KEY (reservation_id)
        REFERENCES reservation (reservation_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

INSERT INTO room_status (name) VALUES
    ('available'),
    ('occupied'),
    ('being_cleaned'),
    ('out_of_service');