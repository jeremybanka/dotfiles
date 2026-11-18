"""Exercise shared pnpm metadata in a bootstrapped Linux guest.

Run with python3 -B vms/tests/test_pnpm_shared_cache_guest.py.
SCRUBS_TEST_PROXY can select a staged launcher; version overrides select
already-installed tools. The registry is local and no public packages are used.
"""
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import threading
import uuid


def main():
    home = Path.home()
    proxy = os.environ.get('SCRUBS_TEST_PROXY', str(home / '.local/bin/scrubs-dirty-exec'))
    pnpm = os.environ.get('SCRUBS_TEST_PNPM', '12.16.1')
    node = os.environ.get('SCRUBS_TEST_NODE', '26.13.0')
    name = 'scrubs-cache-test-' + uuid.uuid4().hex
    shared = home / '.local/share/scrubs/dirty-cache/pnpm'
    marker = shared / name
    clean_marker = home / '.cache/pnpm' / name
    package = {'name': name, 'version': '1.0.0', 'main': 'index.js'}
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as tar:
        for path, contents in [('package.json', json.dumps(package)), ('index.js', 'module.exports = 42;')]:
            payload = contents.encode()
            info = tarfile.TarInfo('package/' + path)
            info.size = len(payload)
            tar.addfile(info, io.BytesIO(payload))
    tarball = data.getvalue()
    requests = []
    deny_metadata = False

    class Registry(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            requests.append(self.path)
            if self.path == '/' + name:
                if deny_metadata:
                    self.send_error(503, 'metadata must come from the shared cache')
                    return
                body = json.dumps({'name': name, 'dist-tags': {'latest': '1.0.0'},
                                   'versions': {'1.0.0': {**package, 'dist': {
                                       'tarball': registry + '/package.tgz',
                                       'integrity': 'sha512-' + base64.b64encode(hashlib.sha512(tarball).digest()).decode()}}}}).encode()
                content_type = 'application/json'
            elif self.path == '/package.tgz':
                body, content_type = tarball, 'application/octet-stream'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Registry)
    registry = 'http://127.0.0.1:' + str(server.server_port)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix='scrubs-pnpm-shared.', dir='/tmp') as lab:
            clean_marker.parent.mkdir(parents=True, exist_ok=True)
            clean_marker.write_text('clean cache must stay private')
            profiles = []
            for number in range(2):
                project = Path(lab) / str(number)
                project.mkdir()
                (project / 'package.json').write_text(json.dumps({
                    'name': 'consumer', 'version': '1.0.0', 'private': True,
                    'dependencies': {name: '^1.0.0'}}))
                (project / 'mise.toml').write_text(f'[tools]\npnpm = "{pnpm}"\nnode = "{node}"\n')
                (project / 'pnpm-workspace.yaml').write_text(
                    f'registry: {registry}\nminimumReleaseAge: 0\nenableGlobalVirtualStore: false\nstoreDir: ./.pnpm-store\n')
                subprocess.run(['/run/current-system/sw/bin/git', 'init', '-q', str(project)], check=True)
                subprocess.run(['/run/current-system/sw/bin/mise', 'trust', '--quiet'], cwd=project, check=True)

                def run(*args):
                    result = subprocess.run([proxy, *args], cwd=project, capture_output=True, text=True, timeout=120)
                    if result.returncode:
                        raise AssertionError(result.stdout + result.stderr)
                    return result.stdout.strip()

                # Reject host home/cache visibility before exercising any registry data.
                probe = '''
const fs = require('fs');
const home = process.env.HOME;
for (const p of ['/.codex', '/.local/share/scrubs/clean-auth', '/.local/share/pnpm/store']) {
  if (fs.existsSync(home + p)) throw Error('clean path visible: ' + p);
}
const cache = home + '/.cache/pnpm';
const marker = cache + '/' + process.argv[1];
if (process.argv[2] === '0') {
  if (fs.existsSync(marker)) throw Error('clean cache marker visible');
  fs.writeFileSync(marker, 'dirty shared metadata');
} else if (fs.readFileSync(marker, 'utf8') !== 'dirty shared metadata') {
  throw Error('cache is not shared across profiles');
}
const mounts = fs.readFileSync('/proc/self/mountinfo', 'utf8').trim().split('\\n');
const profile = mounts.find(line => line.split(' ')[4] === home).split(' ')[3];
console.log(JSON.stringify({profile, ino: String(fs.statSync(cache).ino), dev: String(fs.statSync(cache).dev)}));
'''
                result = json.loads(run('node', '-e', probe, name, str(number)))
                assert result['ino'] == str(shared.stat().st_ino)
                assert result['dev'] == str(shared.stat().st_dev)
                profiles.append(result['profile'])
                before = requests.count('/' + name)
                run('pnpm', 'install', '--ignore-scripts', '--prefer-offline')
                assert run('node', '-e', f'console.log(require({json.dumps(name)}))') == '42'
                if number == 0:
                    assert requests.count('/' + name) > before, 'fixture metadata was not fetched'
                    deny_metadata = True
                else:
                    assert requests.count('/' + name) == before, 'second profile refetched metadata'
                assert not list(Path(result['profile']).joinpath('.cache/pnpm').rglob(name + '*')), 'profile retained a private metadata copy'
            assert profiles[0] != profiles[1], 'test must exercise distinct runtime profiles'
            assert clean_marker.read_text() == 'clean cache must stay private'
            print('PASS: distinct profiles share metadata, separate stores install successfully, clean cache and credentials remain isolated')
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        marker.unlink(missing_ok=True)
        clean_marker.unlink(missing_ok=True)
        # Remove only the uniquely named fixture's registry metadata.
        if shared.exists():
            for path in shared.rglob(name + '*'):
                path.unlink()


if __name__ == '__main__':
    main()
