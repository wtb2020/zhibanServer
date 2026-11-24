"""Reset an existing administrator password without recreating the database."""
import argparse
import getpass
import secrets
import sqlite3
from pathlib import Path

from backend import DB, password_hash


def reset_admin_password(database, username, password):
    if not isinstance(password, str) or not 8 <= len(password) <= 128:
        raise ValueError('新密码长度必须为 8–128 字符')
    path = Path(database).resolve()
    # mode=rw prevents typos or a wrong working directory from creating a blank database.
    connection = sqlite3.connect(path.as_uri() + '?mode=rw', uri=True, timeout=5)
    try:
        with connection:
            connection.execute('BEGIN IMMEDIATE')
            row = connection.execute('SELECT id, role FROM users WHERE username=?', (username,)).fetchone()
            if not row or row[1] != 'admin':
                raise ValueError('未找到此管理员账号；未修改任何数据')
            salt = secrets.token_hex(16)
            connection.execute('UPDATE users SET salt=?,password=?,active=1 WHERE id=?', (salt, password_hash(password, salt), row[0]))
            connection.execute('DELETE FROM sessions WHERE user_id=?', (row[0],))
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description='重置管理员密码，保留用户、课程及授权')
    parser.add_argument('--username', default='admin', help='管理员用户名，默认 admin')
    parser.add_argument('--database', type=Path, default=DB, help='数据库路径，默认沿用服务端配置')
    args = parser.parse_args()
    print(f'将重置管理员：{args.username}\n数据库：{args.database.resolve()}\n用户、课程及授权会保留；该管理员已有登录会话将失效。')
    if not args.database.is_file():
        print('数据库不存在。请确认已启动过服务端，并使用正确的数据库目录。')
        return 1
    try:
        password = getpass.getpass('请输入新密码（至少 8 字符，输入时不显示）：')
        confirmation = getpass.getpass('请再次输入新密码：')
        if password != confirmation:
            raise ValueError('两次密码不一致；未修改任何数据')
        reset_admin_password(args.database, args.username, password)
    except (ValueError, sqlite3.Error, EOFError, KeyboardInterrupt) as error:
        print(f'\n重置未完成：{error}')
        return 1
    print(f'密码重置成功。请使用账号 {args.username} 和刚设置的新密码重新登录。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
