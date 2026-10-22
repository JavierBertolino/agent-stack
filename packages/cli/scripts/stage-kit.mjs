import { cpSync, rmSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const pkg = resolve(here, '..')
const repo = resolve(pkg, '../..')
const kit = resolve(pkg, 'kit')

if (process.argv.includes('--clean')) {
  rmSync(kit, { recursive: true, force: true })
  process.exit(0)
}

rmSync(kit, { recursive: true, force: true })
mkdirSync(kit, { recursive: true })
for (const entry of ['scripts', '.agent-stack', 'VERSION', 'setup.sh', 'install.sh']) {
  cpSync(resolve(repo, entry), resolve(kit, entry), {
    recursive: true,
    filter: (source) => !source.includes('__pycache__') && !source.endsWith('.pyc'),
  })
}
