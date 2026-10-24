DROP DATABASE IF EXISTS lab_equipment_db;
CREATE DATABASE lab_equipment_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE lab_equipment_db;

CREATE TABLE student (
    student_id INT PRIMARY KEY AUTO_INCREMENT,
    registration_number VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    department VARCHAR(80) NOT NULL,
    status ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE lab_admin (
    admin_id INT PRIMARY KEY AUTO_INCREMENT,
    admin_name VARCHAR(100) NOT NULL,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    status ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE category (
    category_id INT PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(80) NOT NULL UNIQUE,
    description VARCHAR(255)
);

CREATE TABLE equipment (
    equipment_id INT PRIMARY KEY AUTO_INCREMENT,
    equipment_code VARCHAR(30) NOT NULL UNIQUE,
    equipment_name VARCHAR(120) NOT NULL,
    category_id INT NOT NULL,
    description VARCHAR(500),
    total_quantity INT NOT NULL,
    available_quantity INT NOT NULL,
    location VARCHAR(120) NOT NULL,
    `condition` ENUM('Good','Fair','Needs Repair') NOT NULL DEFAULT 'Good',
    status ENUM('AVAILABLE','UNAVAILABLE','MAINTENANCE') NOT NULL DEFAULT 'AVAILABLE',
    CONSTRAINT fk_equipment_category FOREIGN KEY (category_id) REFERENCES category(category_id),
    CONSTRAINT chk_equipment_total CHECK (total_quantity > 0),
    CONSTRAINT chk_equipment_available CHECK (available_quantity >= 0 AND available_quantity <= total_quantity)
);

CREATE TABLE booking (
    booking_id INT PRIMARY KEY AUTO_INCREMENT,
    student_id INT NOT NULL,
    equipment_id INT NOT NULL,
    quantity INT NOT NULL,
    allocated_quantity INT NOT NULL DEFAULT 0,
    booking_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    status ENUM('PENDING','APPROVED','PARTIALLY_APPROVED','REJECTED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    approved_by INT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_booking_student FOREIGN KEY (student_id) REFERENCES student(student_id),
    CONSTRAINT fk_booking_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(equipment_id),
    CONSTRAINT fk_booking_admin FOREIGN KEY (approved_by) REFERENCES lab_admin(admin_id),
    CONSTRAINT chk_booking_qty CHECK (quantity > 0),
    CONSTRAINT chk_booking_time CHECK (end_time > start_time)
);

CREATE TABLE issue (
    issue_id INT PRIMARY KEY AUTO_INCREMENT,
    booking_id INT NOT NULL UNIQUE,
    student_id INT NOT NULL,
    equipment_id INT NOT NULL,
    quantity_issued INT NOT NULL,
    issue_date DATE NOT NULL,
    expected_return_date DATE NOT NULL,
    status ENUM('ISSUED','RETURNED') NOT NULL DEFAULT 'ISSUED',
    CONSTRAINT fk_issue_booking FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
    CONSTRAINT fk_issue_student FOREIGN KEY (student_id) REFERENCES student(student_id),
    CONSTRAINT fk_issue_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(equipment_id),
    CONSTRAINT chk_issue_qty CHECK (quantity_issued > 0),
    CONSTRAINT chk_issue_dates CHECK (expected_return_date >= issue_date)
);

CREATE TABLE return_details (
    return_id INT PRIMARY KEY AUTO_INCREMENT,
    issue_id INT NOT NULL,
    quantity_returned INT NOT NULL,
    return_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    condition_on_return ENUM('Good','Fair','Needs Repair') NOT NULL DEFAULT 'Good',
    remarks VARCHAR(500),
    CONSTRAINT fk_return_issue FOREIGN KEY (issue_id) REFERENCES issue(issue_id),
    CONSTRAINT chk_return_qty CHECK (quantity_returned > 0)
);

CREATE TABLE audit_log (
    audit_id INT PRIMARY KEY AUTO_INCREMENT,
    booking_id INT NOT NULL,
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by INT NULL,
    remarks VARCHAR(255),
    CONSTRAINT fk_audit_booking FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
    CONSTRAINT fk_audit_admin FOREIGN KEY (changed_by) REFERENCES lab_admin(admin_id)
);

CREATE VIEW v_available_equipment AS
SELECT e.equipment_id, e.equipment_code, e.equipment_name, c.category_name,
       e.total_quantity, e.available_quantity, e.location, e.`condition`, e.status
FROM equipment e JOIN category c ON e.category_id=c.category_id
WHERE e.status='AVAILABLE' AND e.available_quantity > 0;

CREATE VIEW v_booking_details AS
SELECT b.booking_id, s.registration_number, s.name AS student_name,
       e.equipment_code, e.equipment_name, b.quantity, b.allocated_quantity, b.booking_date,
       b.start_time, b.end_time, b.status, a.admin_name AS approved_by
FROM booking b
JOIN student s ON b.student_id=s.student_id
JOIN equipment e ON b.equipment_id=e.equipment_id
LEFT JOIN lab_admin a ON b.approved_by=a.admin_id;

DELIMITER $$

CREATE TRIGGER trg_booking_status_audit
AFTER UPDATE ON booking
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO audit_log(booking_id, old_status, new_status, changed_by, remarks)
        VALUES(NEW.booking_id, OLD.status, NEW.status, NEW.approved_by,
               CONCAT('Booking status changed from ', OLD.status, ' to ', NEW.status));
    END IF;
END$$

CREATE TRIGGER trg_booking_approved_inventory
AFTER UPDATE ON booking
FOR EACH ROW
BEGIN
    IF OLD.status = 'PENDING'
       AND NEW.status IN ('APPROVED','PARTIALLY_APPROVED') THEN
        UPDATE equipment
        SET available_quantity = available_quantity - NEW.allocated_quantity
        WHERE equipment_id = NEW.equipment_id;
    END IF;
END$$

CREATE TRIGGER trg_return_inventory
AFTER INSERT ON return_details
FOR EACH ROW
BEGIN
    UPDATE equipment e
    JOIN issue i ON i.equipment_id=e.equipment_id
    SET e.available_quantity = e.available_quantity + NEW.quantity_returned
    WHERE i.issue_id=NEW.issue_id;
END$$

CREATE TRIGGER trg_return_status
AFTER INSERT ON return_details
FOR EACH ROW
BEGIN
    UPDATE issue i
    SET i.status = CASE
        WHEN (SELECT COALESCE(SUM(r.quantity_returned),0) FROM return_details r WHERE r.issue_id=NEW.issue_id) >= i.quantity_issued
        THEN 'RETURNED' ELSE 'ISSUED' END
    WHERE i.issue_id=NEW.issue_id;
END$$

CREATE PROCEDURE request_booking(
    IN p_student_id INT,
    IN p_equipment_id INT,
    IN p_quantity INT,
    IN p_booking_date DATE,
    IN p_start_time TIME,
    IN p_end_time TIME
)
BEGIN
    DECLARE v_available INT;
    DECLARE v_status VARCHAR(20);
    SELECT available_quantity, status INTO v_available, v_status
    FROM equipment WHERE equipment_id=p_equipment_id;
    IF v_status <> 'AVAILABLE' OR v_available < p_quantity THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Equipment is not sufficiently available.';
    END IF;
    INSERT INTO booking(student_id,equipment_id,quantity,booking_date,start_time,end_time,status)
    VALUES(p_student_id,p_equipment_id,p_quantity,p_booking_date,p_start_time,p_end_time,'PENDING');
END$$

CREATE PROCEDURE approve_booking(
    IN p_booking_id INT,
    IN p_admin_id INT,
    IN p_allocated_quantity INT
)
BEGIN
    DECLARE v_equipment_id INT;
    DECLARE v_quantity INT;
    DECLARE v_available INT;
    DECLARE v_student_id INT;
    DECLARE v_booking_date DATE;
    DECLARE v_status VARCHAR(30);
    DECLARE v_start TIME;
    DECLARE v_end TIME;
    DECLARE v_issue_date DATE;
    DECLARE v_return_date DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT equipment_id, quantity, student_id, booking_date,
           start_time, end_time, status
      INTO v_equipment_id, v_quantity, v_student_id, v_booking_date,
           v_start, v_end, v_status
    FROM booking
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Only PENDING bookings can be approved.';
    END IF;

    IF p_allocated_quantity IS NULL OR p_allocated_quantity <= 0
       OR p_allocated_quantity > v_quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Allocation must be between 1 and the requested quantity.';
    END IF;

    SELECT available_quantity INTO v_available
    FROM equipment
    WHERE equipment_id = v_equipment_id
    FOR UPDATE;

    IF v_available < p_allocated_quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient equipment availability.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM booking b
        WHERE b.equipment_id = v_equipment_id
          AND b.booking_date = v_booking_date
          AND b.status IN ('APPROVED','PARTIALLY_APPROVED')
          AND b.booking_id <> p_booking_id
          AND b.start_time < v_end
          AND b.end_time > v_start
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Time conflict with another approved booking.';
    END IF;

    UPDATE booking
    SET allocated_quantity = p_allocated_quantity,
        status = CASE
            WHEN p_allocated_quantity = v_quantity THEN 'APPROVED'
            ELSE 'PARTIALLY_APPROVED'
        END,
        approved_by = p_admin_id
    WHERE booking_id = p_booking_id;

    SET v_issue_date = v_booking_date;
    SET v_return_date = DATE_ADD(v_booking_date, INTERVAL 2 DAY);

    INSERT INTO issue(
        booking_id, student_id, equipment_id, quantity_issued,
        issue_date, expected_return_date, status
    )
    VALUES(
        p_booking_id, v_student_id, v_equipment_id, p_allocated_quantity,
        v_issue_date, v_return_date, 'ISSUED'
    );

    COMMIT;
END$$

CREATE PROCEDURE reject_booking(IN p_booking_id INT, IN p_admin_id INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    SELECT status INTO v_status FROM booking WHERE booking_id=p_booking_id FOR UPDATE;
    IF v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only PENDING bookings can be rejected.';
    END IF;
    UPDATE booking SET status='REJECTED', approved_by=p_admin_id WHERE booking_id=p_booking_id;
    COMMIT;
END$$

CREATE PROCEDURE return_equipment(
    IN p_issue_id INT,
    IN p_quantity_returned INT,
    IN p_condition VARCHAR(20),
    IN p_remarks VARCHAR(500)
)
BEGIN
    DECLARE v_quantity INT;
    DECLARE v_status VARCHAR(20);
    DECLARE v_returned INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT quantity_issued, status INTO v_quantity, v_status FROM issue WHERE issue_id=p_issue_id FOR UPDATE;
    SELECT COALESCE(SUM(quantity_returned),0) INTO v_returned FROM return_details WHERE issue_id=p_issue_id;
    IF v_status <> 'ISSUED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='This issue is already returned.';
    END IF;
    IF p_quantity_returned <= 0 OR p_quantity_returned > (v_quantity-v_returned) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid return quantity.';
    END IF;
    INSERT INTO return_details(issue_id,quantity_returned,condition_on_return,remarks)
    VALUES(p_issue_id,p_quantity_returned,p_condition,p_remarks);
    COMMIT;
END$$

CREATE PROCEDURE generate_overdue_report()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_student VARCHAR(100);
    DECLARE v_equipment VARCHAR(120);
    DECLARE v_quantity INT;
    DECLARE v_issue_date DATE;
    DECLARE v_expected DATE;
    DECLARE v_days INT;
    DECLARE cur CURSOR FOR
        SELECT s.name, e.equipment_name, i.quantity_issued, i.issue_date, i.expected_return_date,
               DATEDIFF(CURDATE(), i.expected_return_date)
        FROM issue i JOIN student s ON i.student_id=s.student_id JOIN equipment e ON i.equipment_id=e.equipment_id
        WHERE i.status='ISSUED' AND i.expected_return_date < CURDATE();
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done=1;

    DROP TEMPORARY TABLE IF EXISTS overdue_report;
    CREATE TEMPORARY TABLE overdue_report(
        student VARCHAR(100), equipment VARCHAR(120), quantity INT,
        issue_date DATE, expected_return_date DATE, days_overdue INT
    );

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_student,v_equipment,v_quantity,v_issue_date,v_expected,v_days;
        IF done=1 THEN LEAVE read_loop; END IF;
        INSERT INTO overdue_report VALUES(v_student,v_equipment,v_quantity,v_issue_date,v_expected,v_days);
    END LOOP;
    CLOSE cur;
    SELECT * FROM overdue_report ORDER BY days_overdue DESC;
END$$

DELIMITER ;
