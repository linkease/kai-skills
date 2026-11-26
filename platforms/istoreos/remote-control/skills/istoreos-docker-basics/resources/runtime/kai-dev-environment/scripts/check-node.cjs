const fs = require('node:fs');
const path = require('node:path');
const root = fs.realpathSync(process.argv[2]);
const exe = fs.realpathSync(process.execPath);
if (!exe.startsWith(root + path.sep) || process.versions.node !== process.argv[3]) {
  console.error('Selected Node SDK provenance/version mismatch');
  process.exit(11);
}
console.log(JSON.stringify({executable: exe, version: process.versions.node, script: 'passed'}));
