"""Dependency probe shared by both standalone projects. Never installs anything."""
import sys

if sys.version_info < (3, 10):
    sys.stderr.write('Python 3.10 or newer is required.\n')
    raise SystemExit(1)

import argparse
import hashlib
import json
import os
import secrets
import sqlite3
import ssl
import urllib.request
import webbrowser
from http.server import ThreadingHTTPServer


def inspect_runtime():
    with sqlite3.connect(':memory:') as db:
        assert db.execute('SELECT 1').fetchone()[0] == 1
    ssl.create_default_context()
    assert len(hashlib.pbkdf2_hmac('sha256', b'probe', b'not-a-password', 1)) == 32
    assert len(secrets.token_hex(4)) == 8
    # Resolving this symlink would turn .venv/bin/python back into the system
    # interpreter on Linux and silently leave the virtual environment.
    return {'ok': True, 'python': sys.version.split()[0], 'executable': os.path.abspath(sys.executable),
            'prefix': sys.prefix, 'is_virtualenv': sys.prefix != sys.base_prefix,
            'sqlite': sqlite3.sqlite_version, 'ssl': ssl.OPENSSL_VERSION, 'third_party_packages': []}


def main():
    parser = argparse.ArgumentParser(description='Check the Python runtime required by Zhiban')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--print-executable', action='store_true')
    args = parser.parse_args()
    try:
        report = inspect_runtime()
    except Exception as error:
        print('Runtime check failed: ' + str(error), file=sys.stderr)
        return 1
    if args.print_executable:
        print(report['executable'])
    elif args.json:
        print(json.dumps(report, ensure_ascii=True))
    else:
        print('Python {python} | SQLite {sqlite} | {ssl}\nInterpreter: {executable}\nVirtual environment: {is_virtualenv}\nNo pip packages required.'.format(**report))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
