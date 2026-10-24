USE lab_equipment_db;

INSERT INTO category(category_name,description) VALUES
('Microcontroller','Arduino, ESP32 and embedded development boards'),
('Single Board Computer','Raspberry Pi and related boards'),
('Measurement','Digital multimeters and measurement instruments'),
('Test Equipment','Oscilloscopes and laboratory test equipment');

-- Demo password for all accounts: password123
INSERT INTO student(registration_number,name,email,password_hash,department) VALUES
('ST101','Ananya Rao','st101@example.com','pbkdf2:sha256:600000$f1293b3952b194bafebd4806fe33bd78$4c1d16b48b02e313f7de94aaa0ef6037b55cab08dcc06161bcd092735c84cc4b','ECE'),
('ST105','Rahul Kumar','st105@example.com','pbkdf2:sha256:600000$f1293b3952b194bafebd4806fe33bd78$4c1d16b48b02e313f7de94aaa0ef6037b55cab08dcc06161bcd092735c84cc4b','CSE');

INSERT INTO lab_admin(admin_name,username,password_hash) VALUES
('Lab Administrator','admin','pbkdf2:sha256:600000$f1293b3952b194bafebd4806fe33bd78$4c1d16b48b02e313f7de94aaa0ef6037b55cab08dcc06161bcd092735c84cc4b');

INSERT INTO equipment(equipment_code,equipment_name,category_id,description,total_quantity,available_quantity,location,`condition`,status) VALUES
('EQ001','Arduino UNO',1,'ATmega328P development board',20,20,'Embedded Systems Lab','Good','AVAILABLE'),
('EQ002','ESP32',1,'Wi-Fi and Bluetooth development board',10,10,'IoT Lab','Good','AVAILABLE'),
('EQ003','Raspberry Pi',2,'Single-board computer for lab experiments',6,6,'Computer Lab','Good','AVAILABLE'),
('EQ004','Digital Multimeter',3,'Digital electrical measurement instrument',8,8,'Electronics Lab','Good','AVAILABLE'),
('EQ005','Oscilloscope',4,'Digital storage oscilloscope',3,3,'Electronics Lab','Good','AVAILABLE');
