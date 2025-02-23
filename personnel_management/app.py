from flask import Flask, render_template, request, redirect, url_for, flash, session
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
import smtplib
from email.mime.text import MIMEText
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = 'your-secret-key'  # Change this to a secure key in production

# Flask-Login setup
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Dummy databases (replace with a real database in production)
users = {
    'staff123': {'password': 'pass123', 'email': 'staff@example.com', 'role': 'Employee'},
    'manager456': {'password': 'pass456', 'email': 'manager@example.com', 'role': 'Manager'},
    'admin789': {'password': 'pass789', 'email': 'admin@example.com', 'role': 'Admin'}
}

leaves = {}  # {leave_id: {'staff_id': str, 'start_date': str, 'end_date': str, 'reason': str, 'status': str}}
schedules = {}  # {shift_id: {'staff_id': str, 'date': str, 'start_time': str, 'end_time': str}}
availability = {}  # {staff_id: {day: [{'start_time': str, 'end_time': str}]}}

class User(UserMixin):
    def __init__(self, staff_id):
        self.id = staff_id
        self.role = users[staff_id]['role']

    def get_role(self):
        return self.role

@login_manager.user_loader
def load_user(staff_id):
    if staff_id in users:
        return User(staff_id)
    return None

# Role-based access decorator
def role_required(*roles):
    def decorator(f):
        @login_required
        def wrapped_function(*args, **kwargs):
            if current_user.get_role() not in roles:
                flash('You do not have permission to access this page.')
                return redirect(url_for('dashboard'))
            return f(*args, **kwargs)
        wrapped_function.__name__ = f.__name__
        return wrapped_function
    return decorator

# Leave validation (unchanged)
def validate_leave(staff_id, start_date_str, end_date_str, reason):
    today = datetime(2025, 2, 23)  # Fixed date; use datetime.now() in production
    try:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d')
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d')
    except ValueError:
        return False, "Invalid date format."
    if start_date >= end_date:
        return False, "Start date must be before end date."
    if start_date < today:
        return False, "Start date cannot be in the past."
    for leave in leaves.values():
        if leave['staff_id'] == staff_id and leave['status'] in ['Pending', 'Approved']:
            existing_start = datetime.strptime(leave['start_date'], '%Y-%m-%d')
            existing_end = datetime.strptime(leave['end_date'], '%Y-%m-%d')
            if not (end_date < existing_start or start_date > existing_end):
                return False, "This leave overlaps with an existing request."
    notice_period = timedelta(days=3)
    if start_date - today < notice_period:
        return False, "Leave must be requested at least 3 days in advance."
    max_duration = timedelta(days=14)
    if end_date - start_date > max_duration:
        return False, "Leave duration cannot exceed 14 days."
    if not reason or len(reason.strip()) < 5:
        return False, "Reason must be at least 5 characters long."
    return True, "Valid leave request."

# Availability validation
def validate_availability(staff_id, day, start_time_str, end_time_str):
    try:
        start_dt = datetime.strptime(start_time_str, '%H:%M')
        end_dt = datetime.strptime(end_time_str, '%H:%M')
    except ValueError:
        return False, "Invalid time format."

    duration = end_dt - start_dt
    if duration <= timedelta(hours=0):
        return False, "End time must be after start time."
    if duration > timedelta(hours=12):
        return False, "Availability cannot exceed 12 hours."
    if duration < timedelta(hours=1):
        return False, "Availability must be at least 1 hour."

    # Check for overlaps in existing availability for the same day
    if staff_id in availability and day in availability[staff_id]:
        for slot in availability[staff_id][day]:
            existing_start = datetime.strptime(slot['start_time'], '%H:%M')
            existing_end = datetime.strptime(slot['end_time'], '%H:%M')
            if not (end_dt <= existing_start or start_dt >= existing_end):
                return False, "This availability overlaps with an existing slot."
    return True, "Valid availability."

# Schedule validation with availability check
def validate_schedule(staff_id, date_str, start_time_str, end_time_str):
    today = datetime(2025, 2, 23)  # Fixed date; use datetime.now() in production
    try:
        shift_date = datetime.strptime(date_str, '%Y-%m-%d')
        start_dt = datetime.strptime(f"{date_str} {start_time_str}", '%Y-%m-%d %H:%M')
        end_dt = datetime.strptime(f"{date_str} {end_time_str}", '%Y-%m-%d %H:%M')
    except ValueError:
        return False, "Invalid date or time format."

    duration = end_dt - start_dt
    if duration <= timedelta(hours=0):
        return False, "End time must be after start time."
    if duration > timedelta(hours=12):
        return False, "Shift cannot exceed 12 hours."
    if duration < timedelta(hours=1):
        return False, "Shift must be at least 1 hour."
    if shift_date < today:
        return False, "Cannot schedule shifts in the past."

    # Check overlaps with existing shifts
    for shift in schedules.values():
        if shift['staff_id'] == staff_id and shift['date'] == date_str:
            existing_start = datetime.strptime(f"{shift['date']} {shift['start_time']}", '%Y-%m-%d %H:%M')
            existing_end = datetime.strptime(f"{shift['date']} {shift['end_time']}", '%Y-%m-%d %H:%M')
            if not (end_dt <= existing_start or start_dt >= existing_end):
                return False, "This shift overlaps with an existing shift."

    # Check leave conflict
    for leave in leaves.values():
        if leave['staff_id'] == staff_id and leave['status'] == 'Approved':
            leave_start = datetime.strptime(leave['start_date'], '%Y-%m-%d')
            leave_end = datetime.strptime(leave['end_date'], '%Y-%m-%d')
            if shift_date >= leave_start and shift_date <= leave_end:
                return False, "Employee is on approved leave during this date."

    # Check availability
    day_name = shift_date.strftime('%A')  # e.g., "Monday"
    if staff_id not in availability or day_name not in availability[staff_id]:
        return False, "Employee is not available on this day."
    for slot in availability[staff_id][day_name]:
        avail_start = datetime.strptime(f"{date_str} {slot['start_time']}", '%Y-%m-%d %H:%M')
        avail_end = datetime.strptime(f"{date_str} {slot['end_time']}", '%Y-%m-%d %H:%M')
        if start_dt >= avail_start and end_dt <= avail_end:
            return True, "Valid shift."
    return False, "Shift does not fit within employee’s availability."

# Routes
@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        staff_id = request.form['staff_id']
        password = request.form['password']
        if staff_id in users and users[staff_id]['password'] == password:
            user = User(staff_id)
            login_user(user)
            return redirect(url_for('dashboard'))
        else:
            flash('Invalid credentials')
    return render_template('login.html')

@app.route('/dashboard', methods=['GET', 'POST'])
@login_required
def dashboard():
    if request.method == 'POST':
        action = request.form.get('action')
        if action == 'send_email':
            recipient = request.form['recipient']
            subject = request.form['subject']
            body = request.form['body']
            send_email(recipient, subject, body)
            flash('Email sent successfully!')
        elif action == 'apply_leave':
            start_date = request.form['start_date']
            end_date = request.form['end_date']
            reason = request.form['reason']
            is_valid, message = validate_leave(current_user.id, start_date, end_date, reason)
            if is_valid:
                leave_id = f"leave_{len(leaves) + 1}"
                leaves[leave_id] = {
                    'staff_id': current_user.id,
                    'start_date': start_date,
                    'end_date': end_date,
                    'reason': reason,
                    'status': 'Pending'
                }
                flash('Leave application submitted!')
            else:
                flash(message)
        elif action == 'set_availability':
            day = request.form['day']
            start_time = request.form['start_time']
            end_time = request.form['end_time']
            is_valid, message = validate_availability(current_user.id, day, start_time, end_time)
            if is_valid:
                if current_user.id not in availability:
                    availability[current_user.id] = {}
                if day not in availability[current_user.id]:
                    availability[current_user.id][day] = []
                availability[current_user.id][day].append({'start_time': start_time, 'end_time': end_time})
                flash('Availability updated!')
            else:
                flash(message)
        elif action == 'request_payslip':
            flash('Payslip request submitted!')
        elif action == 'change_bg':
            session['background'] = request.form['background']
    user_leaves = {k: v for k, v in leaves.items() if v['staff_id'] == current_user.id}
    user_schedules = {k: v for k, v in schedules.items() if v['staff_id'] == current_user.id}
    user_availability = availability.get(current_user.id, {})
    return render_template('dashboard.html', staff_id=current_user.id, role=current_user.get_role(), 
                          leaves=user_leaves, schedules=user_schedules, availability=user_availability)

@app.route('/manage_users', methods=['GET', 'POST'])
@role_required('Admin')
def manage_users():
    if request.method == 'POST':
        action = request.form.get('action')
        staff_id = request.form.get('staff_id')
        if action == 'add':
            password = request.form['password']
            email = request.form['email']
            role = request.form['role']
            if staff_id not in users:
                users[staff_id] = {'password': password, 'email': email, 'role': role}
                flash(f'User {staff_id} added successfully!')
            else:
                flash('Staff ID already exists.')
        elif action == 'delete' and staff_id in users:
            del users[staff_id]
            flash(f'User {staff_id} deleted successfully!')
    return render_template('manage_users.html', users=users)

@app.route('/manage_leaves', methods=['GET', 'POST'])
@role_required('Manager', 'Admin')
def manage_leaves():
    if request.method == 'POST':
        leave_id = request.form.get('leave_id')
        action = request.form.get('action')
        if leave_id in leaves:
            if action == 'approve':
                leaves[leave_id]['status'] = 'Approved'
                send_email(users[leaves[leave_id]['staff_id']]['email'], 
                          'Leave Request Approved', 
                          f"Your leave from {leaves[leave_id]['start_date']} to {leaves[leave_id]['end_date']} has been approved.")
                flash(f'Leave {leave_id} approved!')
            elif action == 'reject':
                leaves[leave_id]['status'] = 'Rejected'
                send_email(users[leaves[leave_id]['staff_id']]['email'], 
                          'Leave Request Rejected', 
                          f"Your leave from {leaves[leave_id]['start_date']} to {leaves[leave_id]['end_date']} has been rejected.")
                flash(f'Leave {leave_id} rejected!')
    return render_template('manage_leaves.html', leaves=leaves, users=users)

@app.route('/manage_schedules', methods=['GET', 'POST'])
@role_required('Manager', 'Admin')
def manage_schedules():
    if request.method == 'POST':
        action = request.form.get('action')
        if action == 'add_shift':
            staff_id = request.form['staff_id']
            date = request.form['date']
            start_time = request.form['start_time']
            end_time = request.form['end_time']
            is_valid, message = validate_schedule(staff_id, date, start_time, end_time)
            if is_valid:
                shift_id = f"shift_{len(schedules) + 1}"
                schedules[shift_id] = {
                    'staff_id': staff_id,
                    'date': date,
                    'start_time': start_time,
                    'end_time': end_time
                }
                send_email(users[staff_id]['email'], 
                          'New Shift Assigned', 
                          f"You have been scheduled for a shift on {date} from {start_time} to {end_time}.")
                flash(f'Shift {shift_id} assigned!')
            else:
                flash(message)
        elif action == 'delete_shift':
            shift_id = request.form['shift_id']
            if shift_id in schedules:
                del schedules[shift_id]
                flash(f'Shift {shift_id} deleted!')
    return render_template('manage_schedules.html', schedules=schedules, users=users, availability=availability)

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

# Email functionality
def send_email(recipient, subject, body):
    sender = "your-email@example.com"
    password = "your-email-password"  # Use app-specific password
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = sender
    msg['To'] = recipient
    with smtplib.SMTP_SSL('smtp.gmail.com', 465) as server:
        server.login(sender, password)
        server.send_message(msg)

if __name__ == '__main__':
    app.run(debug=True)