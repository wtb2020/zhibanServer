import hashlib
import hmac
import json
import mimetypes
import os
import secrets
import socket
import sqlite3
import time
import threading
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from contextlib import contextmanager
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
DB = Path(os.environ.get('EDU_DATA_DIR', ROOT / 'data')) / 'learning.db'
PUBLIC_URL = os.environ.get('EDU_PUBLIC_URL', '').rstrip('/')

@contextmanager
def database():
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    try:
        with db:
            yield db
    finally:
        db.close()

def password_hash(password, salt):
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 260000).hex()

def init_db():
    DB.parent.mkdir(parents=True, exist_ok=True)
    first_run = not DB.exists()
    with database() as db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, salt TEXT NOT NULL, password TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'student', active INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE IF NOT EXISTS courses(id INTEGER PRIMARY KEY, content TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS grants(user_id INTEGER REFERENCES users(id) ON DELETE CASCADE, course_id INTEGER REFERENCES courses(id) ON DELETE CASCADE, PRIMARY KEY(user_id,course_id));
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, user_id INTEGER REFERENCES users(id) ON DELETE CASCADE, expires REAL NOT NULL);
        ''')
        admin = db.execute("SELECT username FROM users WHERE role='admin' ORDER BY id LIMIT 1").fetchone()
        if not admin:
            password = os.environ.get('DEMO_ADMIN_PASSWORD') or secrets.token_urlsafe(10)
            salt = secrets.token_hex(16)
            db.execute('INSERT INTO users(username,salt,password,role) VALUES(?,?,?,?)', ('admin', salt, password_hash(password, salt), 'admin'))
            print(f'首次管理员账号：admin  密码：{password}\n请记录密码，数据库会保留此账号。', flush=True)
        else:
            print(f'管理员账号：{admin["username"]}（已有密码不再显示；忘记时运行 python reset_admin.py）', flush=True)
        if first_run:
            course = json.loads((ROOT / 'seed' / 'course.json').read_text(encoding='utf-8'))
            db.execute('INSERT INTO courses(content) VALUES(?)', (json.dumps(course, ensure_ascii=False),))

def public_user(user):
    return {k: user[k] for k in ('id', 'username', 'role', 'active')}

def course_access(course):
    return course.get('access', 'restricted')

def can_download(db, user_id, row):
    access = course_access(json.loads(row['content']))
    return access == 'public' or (access == 'restricted' and db.execute('SELECT 1 FROM grants WHERE user_id=? AND course_id=?', (user_id, row['id'])).fetchone() is not None)

def validate_course(course):
    if not isinstance(course, dict) or not isinstance(course.get('title'), str) or not course['title'].strip():
        raise ValueError('课程名称不能为空')
    if not isinstance(course.get('items'), list) or not course['items']:
        raise ValueError('至少需要一个数字物品')
    tags, ids = set(), set()
    for item in course['items']:
        if not isinstance(item, dict):
            raise ValueError('物品格式不正确')
        for key in ('id', 'tag', 'word', 'meaning', 'emoji'):
            if not isinstance(item.get(key), str) or not item[key].strip():
                raise ValueError('物品字段不能为空')
        item['tag'] = item['tag'].strip().upper()
        if item['tag'] in tags or item['id'] in ids:
            raise ValueError('RFID 标签和物品 ID 不能重复')
        tags.add(item['tag'])
        ids.add(item['id'])
    if course_access(course) not in ('public', 'restricted', 'hidden'):
        raise ValueError('课程访问模式不正确')
    course['access'] = course_access(course)
    return course

class CourseHTTPServer(ThreadingHTTPServer):
    # Windows SO_REUSEADDR permits two listeners on the same port. Use an
    # exclusive listener so a second double-click cannot hijack the first one.
    allow_reuse_address = os.name != 'nt'

    def server_bind(self):
        if os.name == 'nt' and hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()

class Handler(BaseHTTPRequestHandler):
    def send(self, status, value, kind='application/json; charset=utf-8', cookie=None):
        body = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        if cookie:
            self.send_header('Set-Cookie', cookie)
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self): self.handle_request()
    def do_POST(self): self.handle_request()
    def do_PUT(self): self.handle_request()
    def do_DELETE(self): self.handle_request()

    def handle_request(self):
        path, method = urlparse(self.path).path, self.command
        routes = {'/': 'index.html', '/admin': 'admin.html', '/migrate': 'migrate.html', '/sw.js': 'retire-sw.js', '/admin.js': 'admin.js', '/auth.js': 'auth.js', '/style.css': 'style.css'}
        if method == 'GET' and path == '/api/status':
            return self.send(200, {'app': 'zhiban-course-server', 'status': 'online'})
        if method == 'GET' and path == '/downloads/zhiban-client.zip':
            package = ROOT / 'downloads' / 'zhiban-client.zip'
            if not package.exists():
                return self.send(404, {'error': '客户端安装包尚未构建，请运行 scripts/package.py'})
            return self.send(200, package.read_bytes(), 'application/zip')
        if method == 'GET' and path in routes:
            file = ROOT / 'static' / routes[path]
            return self.send(200, file.read_bytes(), (mimetypes.guess_type(str(file))[0] or 'text/plain') + '; charset=utf-8')
        try:
            body = {}
            if method in ('POST', 'PUT', 'DELETE'):
                expected_origin = PUBLIC_URL or 'http://' + self.headers.get('Host', '')
                if self.headers.get('Origin') and self.headers['Origin'] != expected_origin:
                    return self.send(403, {'error': '不允许跨站操作'})
                if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
                    return self.send(415, {'error': '请使用 JSON 请求'})
                length = int(self.headers.get('Content-Length', 0))
                if not 0 < length <= 200000:
                    raise ValueError('请求大小不正确')
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError('请求格式不正确')
            with database() as db:
                cookie = SimpleCookie(self.headers.get('Cookie', ''))
                cookie_name = 'admin_session' if self.headers.get('X-Portal') == 'admin' else 'client_session'
                token = cookie[cookie_name].value if cookie_name in cookie else ''
                user = db.execute('SELECT u.* FROM users u JOIN sessions s ON u.id=s.user_id WHERE s.token=? AND s.expires>? AND u.active=1', (token, time.time())).fetchone()
                if path == '/api/register' and method == 'POST':
                    username, password = body.get('username', ''), body.get('password', '')
                    if not isinstance(username, str) or not 3 <= len(username.strip()) <= 40 or not isinstance(password, str) or not 8 <= len(password) <= 128:
                        raise ValueError('用户名需 3–40 字，密码需 8–128 字')
                    salt = secrets.token_hex(16)
                    db.execute('INSERT INTO users(username,salt,password) VALUES(?,?,?)', (username.strip(), salt, password_hash(password, salt)))
                    return self.send(201, {'ok': True})
                if path == '/api/login' and method == 'POST':
                    account = db.execute('SELECT * FROM users WHERE username=?', (str(body.get('username', '')).strip(),)).fetchone()
                    password = body.get('password', '')
                    if not isinstance(password, str) or len(password) > 128:
                        raise ValueError('密码格式不正确')
                    if not account or not hmac.compare_digest(password_hash(password, account['salt']), account['password']) or not account['active']:
                        return self.send(401, {'error': '用户名或密码错误，或账号已停用'})
                    if body.get('portal') == 'admin' and account['role'] != 'admin':
                        return self.send(403, {'error': '此入口仅允许管理员登录'})
                    token = secrets.token_urlsafe(32)
                    db.execute('DELETE FROM sessions WHERE expires<?', (time.time(),))
                    db.execute('INSERT INTO sessions VALUES(?,?,?)', (token, account['id'], time.time() + 28800))
                    secure = '; Secure' if PUBLIC_URL.startswith('https://') else ''
                    return self.send(200, public_user(account), cookie=f'{cookie_name}={token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800{secure}')
                if path == '/api/logout' and method == 'POST':
                    db.execute('DELETE FROM sessions WHERE token=?', (token,))
                    return self.send(200, {'ok': True}, cookie=f'{cookie_name}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0')
                if not user:
                    return self.send(401, {'error': '请先登录'})
                if path == '/api/me' and method == 'GET':
                    return self.send(200, public_user(user))
                if path == '/api/health' and method == 'GET':
                    return self.send(200, {'status': 'online'})
                parts = path.strip('/').split('/')
                is_admin = user['role'] == 'admin'
                if parts[:2] == ['api', 'users']:
                    if not is_admin:
                        return self.send(403, {'error': '需要管理员权限'})
                    if len(parts) == 2 and method == 'GET':
                        users = []
                        for row in db.execute('SELECT * FROM users ORDER BY id'):
                            entry = public_user(row)
                            entry['courses'] = [r[0] for r in db.execute('SELECT course_id FROM grants WHERE user_id=?', (row['id'],))]
                            users.append(entry)
                        return self.send(200, users)
                    if len(parts) == 3 and method in ('PUT', 'DELETE'):
                        uid = int(parts[2])
                        target = db.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
                        if not target:
                            return self.send(404, {'error': '用户不存在'})
                        if target['role'] == 'admin':
                            raise ValueError('演示版不允许停用或删除管理员')
                        if method == 'DELETE':
                            db.execute('DELETE FROM users WHERE id=?', (uid,))
                        else:
                            grants = body.get('courses', [])
                            if not isinstance(grants, list) or any(type(i) is not int for i in grants):
                                raise ValueError('课程授权格式不正确')
                            if any(not db.execute('SELECT 1 FROM courses WHERE id=?', (i,)).fetchone() for i in grants):
                                raise ValueError('授权课程不存在')
                            db.execute('UPDATE users SET active=? WHERE id=?', (int(bool(body.get('active', True))), uid))
                            db.execute('DELETE FROM grants WHERE user_id=?', (uid,))
                            db.executemany('INSERT INTO grants VALUES(?,?)', [(uid, i) for i in set(grants)])
                            db.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
                        return self.send(200, {'ok': True})
                if parts[:2] == ['api', 'courses']:
                    if len(parts) == 2 and method == 'GET':
                        rows = db.execute('SELECT * FROM courses ORDER BY id').fetchall()
                        return self.send(200, [{'id': r['id'], 'title': json.loads(r['content'])['title'], 'count': len(json.loads(r['content'])['items']), 'access': course_access(json.loads(r['content']))} for r in rows if is_admin or can_download(db, user['id'], r)])
                    if len(parts) == 2 and method == 'POST':
                        if not is_admin:
                            return self.send(403, {'error': '需要管理员权限'})
                        course = validate_course(body)
                        result = db.execute('INSERT INTO courses(content) VALUES(?)', (json.dumps(course, ensure_ascii=False),))
                        return self.send(201, {'id': result.lastrowid})
                    if len(parts) == 3:
                        cid = int(parts[2])
                        if not is_admin and method != 'GET':
                            return self.send(403, {'error': '需要管理员权限'})
                        row = db.execute('SELECT * FROM courses WHERE id=?', (cid,)).fetchone()
                        if not is_admin and (not row or not can_download(db, user['id'], row)):
                            return self.send(403, {'error': '未获授权访问此课程'})
                        if not row:
                            return self.send(404, {'error': '课程不存在'})
                        if method == 'GET':
                            return self.send(200, {**json.loads(row['content']), 'access': course_access(json.loads(row['content'])), 'id': cid})
                        if method == 'PUT':
                            course = validate_course(body)
                            db.execute('UPDATE courses SET content=? WHERE id=?', (json.dumps(course, ensure_ascii=False), cid))
                            return self.send(200, {'ok': True})
                        if method == 'DELETE':
                            db.execute('DELETE FROM courses WHERE id=?', (cid,))
                            return self.send(200, {'ok': True})
                return self.send(404, {'error': '接口不存在'})
        except sqlite3.IntegrityError:
            self.send(400, {'error': '用户名已存在或数据关联不正确'})
        except (ValueError, TypeError, KeyError) as error:
            self.send(400, {'error': str(error) or '输入格式不正确'})

def open_admin_page(local_url, admin_url):
    """Launch the browser only after this server is accepting HTTP requests."""
    import urllib.request
    import webbrowser
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for _ in range(30):
        try:
            with opener.open(local_url + '/api/status', timeout=1) as response:
                if json.load(response).get('app') != 'zhiban-course-server':
                    raise ValueError('Unexpected service')
            if not webbrowser.open(admin_url, new=2):
                print(f'浏览器未能自动打开，请手动访问：{admin_url}', flush=True)
            return
        except (OSError, ValueError):
            threading.Event().wait(.1)
    print(f'自动打开未完成，请手动访问：{admin_url}', flush=True)


def main():
    global PUBLIC_URL
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8000)
    parser.add_argument('--public-url', default=PUBLIC_URL, help='Externally visible origin, e.g. https://learn.example.com')
    parser.add_argument('--open-browser', action='store_true', help='Open the admin page after the server starts')
    args = parser.parse_args()
    PUBLIC_URL = args.public_url.rstrip('/')
    if PUBLIC_URL and (urlparse(PUBLIC_URL).scheme not in ('http', 'https') or not urlparse(PUBLIC_URL).netloc or urlparse(PUBLIC_URL).path):
        parser.error('--public-url must be an HTTP(S) origin without a path')
    init_db()
    try:
        server = CourseHTTPServer((args.host, args.port), Handler)
    except OSError as error:
        print(f'服务端未能启动：端口 {args.port} 可能已被占用，或没有监听权限。\n请关闭此前的服务窗口后重试，或使用 --port 指定其他端口。\n系统信息：{error}', flush=True)
        return 1
    local_url = f'http://127.0.0.1:{server.server_port}'
    admin_url = (PUBLIC_URL or f'http://localhost:{server.server_port}') + '/admin'
    print(f'服务端已启动：{admin_url}\n请保持本窗口打开。关闭窗口会停止服务。\n客户端请单独运行 client/client.py（默认 http://localhost:8765）。', flush=True)
    if args.open_browser:
        print('正在自动打开管理页面…', flush=True)
        threading.Thread(target=open_admin_page, args=(local_url, admin_url), daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0
