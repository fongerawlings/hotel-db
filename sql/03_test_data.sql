USE hotel_db;
SELECT status, COUNT(*) AS total FROM reservation GROUP BY status;
SELECT status, COUNT(*) AS total FROM invoice GROUP BY status;
SELECT COUNT(*) AS rooms FROM room;
SELECT COUNT(*) AS reviews FROM review;