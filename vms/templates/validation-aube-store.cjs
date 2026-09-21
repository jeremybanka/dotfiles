// Run with the dirty mise-managed Node runtime. Follow the installed package
// link so this checks both shared Aube stores and per-install virtual stores.
const fs = require('node:fs');
const path = require('node:path');
const packageDirectory = fs.realpathSync(path.join(
  process.env.HOME,
  '.local/share/mise/installs/ni/30.5.0/node_modules/@antfu/ni',
));
const probe = path.join(packageDirectory, '.scrubs-write-probe');
let blocked = false;
try {
  fs.writeFileSync(probe, 'read-only package-store probe', { flag: 'wx' });
} catch (error) {
  if (!['EROFS', 'EACCES'].includes(error.code)) throw error;
  blocked = true;
}
if (!blocked) {
  fs.unlinkSync(probe);
  throw new Error(`Dirty execution can write to the package store: ${packageDirectory}`);
}
