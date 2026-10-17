'use strict';
const fs = require('node:fs');
function validateThemePin(pin) {
  if (pin?.repository !== 'UltraStar-CE/Themes' || !/^[a-f0-9]{40}$/.test(pin?.sha || '')) {
    throw Error('Themes must use a full commit SHA from UltraStar-CE/Themes');
  }
  return {repository: pin.repository, sha: pin.sha};
}
function readThemePin() {
  return validateThemePin(JSON.parse(fs.readFileSync('themes.json', 'utf8')));
}
module.exports = {validateThemePin, readThemePin};
