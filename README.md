# Lab Equipment Booking and Inventory Management System

A simple M.Tech DBMS project using **HTML/CSS/Bootstrap/JavaScript + Flask + MySQL 8**.

## Features
- Separate Student and Lab Admin login
- Student self-registration with hashed passwords and unique registration/email checks
- Admin registration protected by an `ADMIN_REGISTRATION_CODE` in `.env`
- Admin can add, edit and delete equipment; edits preserve units currently issued
- Student booking history and admin booking queue are backed by the same MySQL `booking` table
- MySQL-backed authentication
- Equipment catalogue
- Student booking request stored as PENDING
- Admin approval/rejection
- Transaction-safe approval procedure
- Trigger-based inventory decrement on approval
- Automatic issue creation on approval
- Student/admin return workflow
- Trigger-based inventory increment and issue status update on return
- Audit trigger for booking status changes
- Stored procedures
- Cursor-based overdue report
- Views and normalized relational schema
- Simple CRUD for equipment
- Admin dashboard statistics retrieved from MySQL

## Demo credentials
- Student: `ST101` / `password123`
- Student: `ST105` / `password123`
- Admin: `admin` / `password123`

## Setup
1. Install MySQL 8 and Python 3.11+.
2. Open MySQL Workbench.
3. Run `database/schema.sql`.
4. Run `database/seed.sql`.
5. Copy `.env.example` to `.env` and set your MySQL password. Also set a private `ADMIN_REGISTRATION_CODE`; this code is required to create additional admin accounts.
6. Create a virtual environment:
   - Windows: `python -m venv venv` then `venv\\Scripts\\activate`
   - Linux/macOS: `python3 -m venv venv` then `source venv/bin/activate`
7. Install dependencies: `pip install -r requirements.txt`
8. Start: `python run.py`
9. Open `http://127.0.0.1:5000`

## Registration and equipment management
- Student: open Student Register, provide registration number, name, email, department and password. Passwords are stored as hashes.
- Admin: open Admin Register and provide the private code configured in `.env` as `ADMIN_REGISTRATION_CODE`. Public admin signup is intentionally protected so any visitor cannot create an administrator account.
- Admin equipment page: add new equipment, use Edit to change the details/quantity/status, or Delete if no booking/issue history references the equipment. Changes are read back from MySQL on page refresh.
- Student booking requests insert a `PENDING` row into MySQL `booking`; the same row is visible in the student booking history and admin bookings page. Approval and returns update inventory through database triggers.

## DBMS demonstration flow
1. MySQL Workbench: `SELECT * FROM equipment;`
2. Student logs in and sees the same inventory through Flask.
3. Student requests 2 Arduino UNO units -> BOOKING status is PENDING.
4. Admin logs in and approves -> transaction checks availability/conflict.
5. Approval trigger reduces `available_quantity` from 20 to 18 and procedure creates ISSUE.
6. Student refreshes -> sees 18 available.
7. Student returns 2 -> return trigger increases availability from 18 to 20 and issue becomes RETURNED.
8. Admin opens Overdue Report -> Flask calls `generate_overdue_report()` using a MySQL cursor.

## Important DBMS objects
- Tables: student, lab_admin, category, equipment, booking, issue, return_details, audit_log
- Views: v_available_equipment, v_booking_details
- Triggers: booking audit, approval inventory, return inventory, return status
- Procedures: request_booking, approve_booking, reject_booking, return_equipment, generate_overdue_report
- Transaction: approve_booking and return_equipment
- Cursor: generate_overdue_report


## Partial allocation update

- For a **fresh installation**, run `database/schema.sql`, then `database/seed.sql`.
- For an **existing database**, back it up and run `database/migration_partial_allocation.sql` in MySQL Workbench. Do not run `schema.sql` on an existing database because it drops and recreates `lab_equipment_db`.
- Admin approval accepts three procedure arguments: booking ID, admin ID, and allocated quantity. Full allocations become `APPROVED`; smaller allocations become `PARTIALLY_APPROVED`.
