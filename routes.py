from datetime import date
import os
from functools import wraps
from flask import Blueprint, render_template, request, redirect, url_for, session, flash, jsonify
from werkzeug.security import check_password_hash, generate_password_hash
from .db import get_connection, query, execute, call_procedure

bp = Blueprint('main', __name__)


def role_required(role):
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if session.get('role') != role:
                return redirect(url_for('main.home'))
            return view(*args, **kwargs)
        return wrapped
    return decorator


@bp.route('/')
def home():
    if session.get('role') == 'student':
        return redirect(url_for('main.student_dashboard'))
    if session.get('role') == 'admin':
        return redirect(url_for('main.admin_dashboard'))
    return render_template('index.html')


@bp.route('/student/login', methods=['GET', 'POST'])
def student_login():
    if request.method == 'POST':
        reg = request.form['registration_number'].strip()
        password = request.form['password']
        student = query('SELECT * FROM student WHERE registration_number=%s AND status="ACTIVE"', (reg,), True)
        if student and check_password_hash(student['password_hash'], password):
            session.clear()
            session.update(role='student', student_id=student['student_id'], name=student['name'])
            return redirect(url_for('main.student_dashboard'))
        flash('Invalid student ID or password.', 'danger')
    return render_template('student/login.html')


@bp.route('/student/register', methods=['GET', 'POST'])
def student_register():
    if request.method == 'POST':
        reg = request.form.get('registration_number', '').strip()
        name = request.form.get('name', '').strip()
        email = request.form.get('email', '').strip().lower()
        department = request.form.get('department', '').strip()
        password = request.form.get('password', '')
        confirm = request.form.get('confirm_password', '')
        if not all([reg, name, email, department, password]):
            flash('Please fill in all required fields.', 'danger')
        elif len(password) < 8:
            flash('Password must contain at least 8 characters.', 'danger')
        elif password != confirm:
            flash('Passwords do not match.', 'danger')
        else:
            try:
                execute('''INSERT INTO student(registration_number,name,email,password_hash,department,status)
                           VALUES(%s,%s,%s,%s,%s,'ACTIVE')''',
                        (reg, name, email, generate_password_hash(password), department))
                flash('Student account created. You can now log in.', 'success')
                return redirect(url_for('main.student_login'))
            except Exception as exc:
                if getattr(exc, 'errno', None) == 1062:
                    flash('That registration number or email is already registered.', 'danger')
                else:
                    flash('Could not create the account. Check the database connection and try again.', 'danger')
    return render_template('student/register.html')


@bp.route('/admin/register', methods=['GET', 'POST'])
def admin_register():
    # Public admin registration is protected by a code configured in .env.
    required_code = os.getenv('ADMIN_REGISTRATION_CODE', '').strip()
    if not required_code:
        flash('Admin self-registration is disabled. Set ADMIN_REGISTRATION_CODE in .env first.', 'warning')
        return redirect(url_for('main.admin_login'))
    if request.method == 'POST':
        admin_name = request.form.get('admin_name', '').strip()
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        confirm = request.form.get('confirm_password', '')
        supplied_code = request.form.get('registration_code', '')
        if supplied_code != required_code:
            flash('Invalid admin registration code.', 'danger')
        elif not all([admin_name, username, password]):
            flash('Please fill in all required fields.', 'danger')
        elif len(password) < 8:
            flash('Password must contain at least 8 characters.', 'danger')
        elif password != confirm:
            flash('Passwords do not match.', 'danger')
        else:
            try:
                execute('''INSERT INTO lab_admin(admin_name,username,password_hash,status)
                           VALUES(%s,%s,%s,'ACTIVE')''',
                        (admin_name, username, generate_password_hash(password)))
                flash('Admin account created. You can now log in.', 'success')
                return redirect(url_for('main.admin_login'))
            except Exception as exc:
                if getattr(exc, 'errno', None) == 1062:
                    flash('That admin username is already registered.', 'danger')
                else:
                    flash('Could not create the admin account. Check the database connection and try again.', 'danger')
    return render_template('admin/register.html')


@bp.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    if request.method == 'POST':
        username = request.form['username'].strip()
        password = request.form['password']
        admin = query('SELECT * FROM lab_admin WHERE username=%s AND status="ACTIVE"', (username,), True)
        if admin and check_password_hash(admin['password_hash'], password):
            session.clear()
            session.update(role='admin', admin_id=admin['admin_id'], name=admin['admin_name'])
            return redirect(url_for('main.admin_dashboard'))
        flash('Invalid admin ID or password.', 'danger')
    return render_template('admin/login.html')


@bp.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('main.home'))


@bp.route('/student/dashboard')
@role_required('student')
def student_dashboard():
    student_id = session['student_id']
    student = query('SELECT student_id, registration_number, name, email, department FROM student WHERE student_id=%s', (student_id,), True)
    equipment = query('''SELECT e.*, c.category_name FROM equipment e JOIN category c ON e.category_id=c.category_id
                         WHERE e.status='AVAILABLE' ORDER BY e.equipment_name''')
    bookings = query('''SELECT b.*, e.equipment_name, e.equipment_code FROM booking b
                        JOIN equipment e ON b.equipment_id=e.equipment_id
                        WHERE b.student_id=%s ORDER BY b.created_at DESC''', (student_id,))
    active = query('''SELECT i.*, e.equipment_name, e.equipment_code FROM issue i
                      JOIN equipment e ON i.equipment_id=e.equipment_id
                      WHERE i.student_id=%s AND i.status='ISSUED' ORDER BY i.issue_date DESC''', (student_id,))
    
    counts = query('''SELECT
    COALESCE(SUM(status='PENDING'), 0) AS pending_count,
    COALESCE(SUM(status='APPROVED'), 0) AS approved_count,
    COALESCE(SUM(status='PARTIALLY_APPROVED'), 0) AS partial_count,
    COALESCE(SUM(status IN ('REJECTED','CANCELLED')), 0) AS rejected_count
    FROM booking
    WHERE student_id=%s''', (student_id,), True)

    return render_template('student/dashboard.html', student=student, equipment=equipment, bookings=bookings, active=active, counts=counts)


@bp.route('/student/equipment')
@role_required('student')
def student_equipment():
    equipment = query('''SELECT e.*, c.category_name FROM equipment e JOIN category c ON e.category_id=c.category_id
                         ORDER BY e.equipment_name''')
    return render_template('student/equipment.html', equipment=equipment)


@bp.route('/student/book/<int:equipment_id>', methods=['GET', 'POST'])
@role_required('student')
def book_equipment(equipment_id):
    equipment = query('''SELECT e.*, c.category_name FROM equipment e JOIN category c ON e.category_id=c.category_id
                         WHERE e.equipment_id=%s''', (equipment_id,), True)
    if not equipment:
        flash('Equipment not found.', 'danger')
        return redirect(url_for('main.student_equipment'))
    if request.method == 'POST':
        try:
            quantity = int(request.form['quantity'])
            booking_date = request.form['booking_date']
            start_time = request.form['start_time']
            end_time = request.form['end_time']
            if quantity <= 0 or quantity > equipment['available_quantity']:
                raise ValueError('Requested quantity exceeds current availability.')
            if start_time >= end_time:
                raise ValueError('End time must be later than start time.')
            call_procedure('request_booking', (session['student_id'], equipment_id, quantity, booking_date, start_time, end_time))
            flash('Booking request submitted as PENDING.', 'success')
            return redirect(url_for('main.student_dashboard'))
        except Exception as exc:
            flash(str(exc), 'danger')
    return render_template('student/book.html', equipment=equipment, today=date.today().isoformat())


@bp.route('/student/returns')
@role_required('student')
def student_returns():
    issues = query('''SELECT i.*, e.equipment_name, e.equipment_code FROM issue i
                      JOIN equipment e ON i.equipment_id=e.equipment_id
                      WHERE i.student_id=%s ORDER BY i.issue_date DESC''', (session['student_id'],))
    history = query('''SELECT r.*, i.student_id, e.equipment_name FROM return_details r
                       JOIN issue i ON r.issue_id=i.issue_id JOIN equipment e ON i.equipment_id=e.equipment_id
                       WHERE i.student_id=%s ORDER BY r.return_date DESC''', (session['student_id'],))
    return render_template('student/returns.html', issues=issues, history=history)


@bp.route('/student/return/<int:issue_id>', methods=['POST'])
@role_required('student')
def return_equipment(issue_id):
    try:
        condition = request.form.get('condition_on_return', 'Good')
        remarks = request.form.get('remarks', '')
        call_procedure('return_equipment', (issue_id, int(request.form['quantity_returned']), condition, remarks))
        flash('Equipment returned successfully. Inventory has been updated.', 'success')
    except Exception as exc:
        flash(str(exc), 'danger')
    return redirect(url_for('main.student_returns'))


@bp.route('/api/equipment')
@role_required('student')
def api_equipment():
    return jsonify(query('''SELECT e.equipment_id, e.equipment_code, e.equipment_name, c.category_name,
                            e.total_quantity, e.available_quantity, e.location, e.condition, e.status
                            FROM equipment e JOIN category c ON e.category_id=c.category_id ORDER BY e.equipment_name'''))



@bp.route('/admin/dashboard')
@role_required('admin')
def admin_dashboard():
    stats = query('''SELECT
        (SELECT COALESCE(SUM(total_quantity), 0)
         FROM equipment) AS total_units,

        (SELECT COALESCE(SUM(available_quantity), 0)
         FROM equipment) AS available_units,

        (SELECT COUNT(*)
         FROM booking
         WHERE status = 'PENDING') AS pending_requests,

        (SELECT COUNT(*)
         FROM booking
         WHERE status = 'APPROVED') AS approved_bookings,

        (SELECT COUNT(*)
         FROM booking
         WHERE status = 'PARTIALLY_APPROVED') AS partial_bookings,

        (SELECT COALESCE(SUM(quantity_issued), 0)
         FROM issue
         WHERE status = 'ISSUED') AS issued_units,

        (SELECT COUNT(*)
         FROM issue
         WHERE status = 'ISSUED'
           AND expected_return_date < CURDATE()) AS overdue_count
    ''', (), True)

    pending = query('''SELECT
        b.booking_id,
        b.quantity,
        b.allocated_quantity,
        b.booking_date,
        b.start_time,
        b.end_time,
        b.status,
        s.registration_number,
        s.name AS student_name,
        e.equipment_name,
        e.equipment_code
        FROM booking b
        JOIN student s ON b.student_id = s.student_id
        JOIN equipment e ON b.equipment_id = e.equipment_id
        WHERE b.status = 'PENDING'
        ORDER BY b.created_at
    ''')

    return render_template(
        'admin/dashboard.html',
        stats=stats,
        pending=pending
    )


@bp.route('/admin/bookings')
@role_required('admin')
def admin_bookings():
    bookings = query('''SELECT b.*, s.registration_number, s.name student_name, e.equipment_name, e.equipment_code,
                        a.admin_name approved_admin FROM booking b
                        JOIN student s ON b.student_id=s.student_id JOIN equipment e ON b.equipment_id=e.equipment_id
                        LEFT JOIN lab_admin a ON b.approved_by=a.admin_id ORDER BY b.created_at DESC''')
    return render_template('admin/bookings.html', bookings=bookings)



@bp.route('/admin/booking/<int:booking_id>/<action>', methods=['POST'])
@role_required('admin')
def booking_action(booking_id, action):
    try:
        if action == 'approve':
            allocated_quantity = int(
                request.form.get('allocated_quantity', '0')
            )

            if allocated_quantity <= 0:
                raise ValueError(
                    'Allocated quantity must be greater than zero.'
                )

            call_procedure(
                'approve_booking',
                (
                    booking_id,
                    session['admin_id'],
                    allocated_quantity
                )
            )

            flash(
                'Booking processed successfully. '
                'Inventory and issue records updated.',
                'success'
            )

        elif action == 'reject':
            call_procedure(
                'reject_booking',
                (booking_id, session['admin_id'])
            )
            flash(
                'Booking rejected. Inventory was not reduced.',
                'success'
            )

        else:
            flash('Invalid action.', 'danger')

    except ValueError as exc:
        flash(str(exc), 'danger')
    except Exception as exc:
        flash(str(exc), 'danger')

    return redirect(url_for('main.admin_bookings'))



@bp.route('/admin/equipment', methods=['GET', 'POST'])
@role_required('admin')
def admin_equipment():
    categories = query('SELECT * FROM category ORDER BY category_name')
    if request.method == 'POST':
        try:
            execute('''INSERT INTO equipment(equipment_code,equipment_name,category_id,description,total_quantity,
                     available_quantity,location,`condition`,status) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s)''',
                    (request.form['equipment_code'], request.form['equipment_name'], int(request.form['category_id']),
                     request.form.get('description',''), int(request.form['total_quantity']), int(request.form['total_quantity']),
                     request.form['location'], request.form.get('condition','Good'), request.form.get('status','AVAILABLE')))
            flash('Equipment added.', 'success')
            return redirect(url_for('main.admin_equipment'))
        except Exception as exc:
            flash(str(exc), 'danger')
    equipment = query('''SELECT e.*, c.category_name FROM equipment e JOIN category c ON e.category_id=c.category_id
                         ORDER BY e.equipment_id DESC''')
    return render_template('admin/equipment.html', equipment=equipment, categories=categories)


@bp.route('/admin/equipment/<int:equipment_id>/edit', methods=['GET', 'POST'])
@role_required('admin')
def edit_equipment(equipment_id):
    equipment = query('SELECT * FROM equipment WHERE equipment_id=%s', (equipment_id,), True)
    if not equipment:
        flash('Equipment not found.', 'danger')
        return redirect(url_for('main.admin_equipment'))
    categories = query('SELECT * FROM category ORDER BY category_name')
    if request.method == 'POST':
        try:
            total = int(request.form['total_quantity'])
            borrowed = equipment['total_quantity'] - equipment['available_quantity']
            if total < 1 or total < borrowed:
                raise ValueError(f'Total quantity cannot be less than {borrowed} units currently issued.')
            new_available = total - borrowed
            execute('''UPDATE equipment SET equipment_code=%s, equipment_name=%s, category_id=%s,
                       description=%s, total_quantity=%s, available_quantity=%s, location=%s,
                       `condition`=%s, status=%s WHERE equipment_id=%s''',
                    (request.form['equipment_code'].strip(), request.form['equipment_name'].strip(),
                     int(request.form['category_id']), request.form.get('description', '').strip(),
                     total, new_available, request.form['location'].strip(),
                     request.form.get('condition', 'Good'), request.form.get('status', 'AVAILABLE'), equipment_id))
            flash('Equipment updated in MySQL. Student and admin pages will show the updated details.', 'success')
            return redirect(url_for('main.admin_equipment'))
        except Exception as exc:
            if getattr(exc, 'errno', None) == 1062:
                flash('That equipment code is already in use.', 'danger')
            else:
                flash(str(exc), 'danger')
    return render_template('admin/edit_equipment.html', equipment=equipment, categories=categories)


@bp.route('/admin/equipment/<int:equipment_id>/delete', methods=['POST'])
@role_required('admin')
def delete_equipment(equipment_id):
    try:
        execute('DELETE FROM equipment WHERE equipment_id=%s', (equipment_id,))
        flash('Equipment deleted.', 'success')
    except Exception as exc:
        flash('Cannot delete equipment with related booking/issue records. ' + str(exc), 'danger')
    return redirect(url_for('main.admin_equipment'))


@bp.route('/admin/issues')
@role_required('admin')
def admin_issues():
    issues = query('''SELECT i.*, s.registration_number, s.name student_name, e.equipment_name, e.equipment_code
                      FROM issue i JOIN student s ON i.student_id=s.student_id JOIN equipment e ON i.equipment_id=e.equipment_id
                      ORDER BY i.issue_date DESC''')
    return render_template('admin/issues.html', issues=issues)


@bp.route('/admin/returns')
@role_required('admin')
def admin_returns():
    returns = query('''SELECT r.*, i.issue_id, s.registration_number, s.name student_name, e.equipment_name
                       FROM return_details r JOIN issue i ON r.issue_id=i.issue_id
                       JOIN student s ON i.student_id=s.student_id JOIN equipment e ON i.equipment_id=e.equipment_id
                       ORDER BY r.return_date DESC''')
    return render_template('admin/returns.html', returns=returns)


@bp.route('/admin/overdue')
@role_required('admin')
def admin_overdue():
    rows = call_procedure('generate_overdue_report')[0]
    return render_template('admin/overdue.html', rows=rows)
