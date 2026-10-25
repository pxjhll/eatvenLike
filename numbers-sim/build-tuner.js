import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const sources = ['model/config.js', 'model/rules.js', 'model/completion.js', 'model/decisions.js', 'model/simulate.js', 'ui.js'];
const bundle = sources.map(path => readFileSync(new URL(path, import.meta.url), 'utf8')
  .replace(/^import .*;\s*$/gm, '').replace(/^export (?=(const|function) )/gm, '')).join('\n');
const parsed = spawnSync(process.execPath, ['--input-type=module', '--check'], { input: bundle, encoding: 'utf8' });
if (parsed.status !== 0) throw new Error(parsed.stderr);
const html = readFileSync(new URL('tuner.template.html', import.meta.url), 'utf8').replace('/*__MODEL_BUNDLE__*/', bundle);
const output = new URL('economy-tuner.html', import.meta.url);
if (process.argv.includes('--check')) {
  if (readFileSync(output, 'utf8') !== html) throw new Error('Generated economy-tuner.html is stale; run node build-tuner.js');
  console.log('Standalone tuner is current; bundled JavaScript syntax is valid.');
} else {
  writeFileSync(output, html); console.log('Built standalone economy-tuner.html (no network dependencies).');
}
