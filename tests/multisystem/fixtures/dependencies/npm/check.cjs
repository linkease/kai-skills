const assert = require('node:assert/strict');
const isNumber = require('is-number');
const expected = process.argv[2] || '7.0.0';
assert.equal(require('is-number/package.json').version, expected);
assert.equal(isNumber(42), true);
assert.equal(isNumber('abc'), false);
console.log('is-number:' + expected + ':42');
