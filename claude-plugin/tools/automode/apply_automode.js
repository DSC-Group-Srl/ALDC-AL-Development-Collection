#!/usr/bin/env node
// Merge the DSC auto-mode rules (dsc-automode.json) into the user's Claude Code settings.
//
// Usage: node apply_automode.js [settingsPath] [rulesPath]
//   settingsPath defaults to ~/.claude/settings.json, rulesPath to dsc-automode.json next to this file.
//
// For each list in the rules file (environment, allow, soft_deny, hard_deny):
//   - drop every existing entry that starts with "[bc-dev]" (our previous version),
//   - append the current [bc-dev] entries,
//   - create a missing list as ["$defaults", ...rules] so the built-in rules are kept.
// The user's own entries, and whether they kept "$defaults", are never touched.
// The file is written only when something changed (backup first, then tmp + rename).
//
// Prints one line: "unchanged", "updated <backupPath>", or "error <reason>". Always exits 0.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const TAG = '[bc-dev]';
const LISTS = ['environment', 'allow', 'soft_deny', 'hard_deny'];

function main() {
  const settingsPath = process.argv[2] || path.join(os.homedir(), '.claude', 'settings.json');
  const rulesPath = process.argv[3] || path.join(__dirname, 'dsc-automode.json');

  let rules;
  try {
    rules = JSON.parse(fs.readFileSync(rulesPath, 'utf8'));
  } catch (e) {
    return 'error cannot read rules: ' + e.message;
  }

  let raw = '';
  let settings = {};
  if (fs.existsSync(settingsPath)) {
    raw = fs.readFileSync(settingsPath, 'utf8');
    const text = raw.replace(/^﻿/, '');
    if (text.trim() !== '') {
      try {
        settings = JSON.parse(text);
      } catch (e) {
        // Never rewrite a file we cannot parse: the user would lose their settings.
        return 'error settings.json is not valid JSON, left untouched: ' + e.message;
      }
    }
  }
  if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
    return 'error settings.json is not a JSON object, left untouched';
  }

  const before = JSON.stringify(settings.autoMode === undefined ? null : settings.autoMode);
  const autoMode = (settings.autoMode && typeof settings.autoMode === 'object' && !Array.isArray(settings.autoMode))
    ? settings.autoMode : {};

  for (const key of LISTS) {
    const ours = (Array.isArray(rules[key]) ? rules[key] : []).filter(s => typeof s === 'string' && s.startsWith(TAG));
    const current = Array.isArray(autoMode[key]) ? autoMode[key] : null;
    if (current === null) {
      if (ours.length) autoMode[key] = ['$defaults', ...ours];
      continue;
    }
    const kept = current.filter(s => !(typeof s === 'string' && s.startsWith(TAG)));
    autoMode[key] = [...kept, ...ours];
  }
  settings.autoMode = autoMode;

  if (JSON.stringify(settings.autoMode) === before) return 'unchanged';

  fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  const backup = settingsPath + '.bc-dev-backup';
  if (raw !== '') fs.writeFileSync(backup, raw, 'utf8');
  const tmp = settingsPath + '.bc-dev-tmp-' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2) + '\n', 'utf8');
  fs.renameSync(tmp, settingsPath);
  return 'updated ' + (raw !== '' ? backup : '(new file)');
}

let out;
try {
  out = main();
} catch (e) {
  out = 'error ' + e.message;
}
process.stdout.write(out + '\n');
