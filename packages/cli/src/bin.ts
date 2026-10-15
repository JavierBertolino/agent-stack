#!/usr/bin/env node
import { spawn } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { cancel, intro, isCancel, multiselect, outro } from '@clack/prompts'
import { INTEGRATIONS, PLATFORMS, type IntegrationId, type PlatformId } from './catalog.js'
import { plan, projectRootFromArgv, type WizardAnswers, type WizardRequest } from './plan.js'

const MIGRATED = new Set(['init', 'sync', 'check', 'adopt', 'prune', 'uninstall'])

function hasKit(dir: string): boolean {
  return existsSync(join(dir, 'scripts/setup-agent-stack.sh'))
}

export function findKitRoot(moduleDir: string): string {
  const checkout = resolve(moduleDir, '../../..')
  const published = resolve(moduleDir, '../kit')
  const release = resolve(moduleDir, '../..')
  if (hasKit(checkout) && existsSync(join(checkout, 'packages/cli/package.json'))) return checkout
  if (hasKit(published)) return published
  if (hasKit(release)) return release
  return checkout
}

function readSaved(root: string): string | null {
  const file = join(root, '.agent-stack/config.conf')
  if (!existsSync(file)) return null
  return readFileSync(file, 'utf8')
}

function isPlatformId(value: string): value is PlatformId {
  return PLATFORMS.some((row) => row.id === value)
}

function isIntegrationId(value: string): value is IntegrationId {
  return INTEGRATIONS.some((row) => row.id === value)
}

async function ask(request: WizardRequest): Promise<WizardAnswers | null> {
  intro('Configure Agent Stack for this project.')
  const platforms = await multiselect({
    message: 'Coding agents',
    options: request.platforms.map((row) => ({ value: row.id, label: row.label })),
    initialValues: request.platforms.filter((row) => row.initial).map((row) => row.id),
    required: true,
  })
  if (isCancel(platforms)) {
    cancel('Cancelled.')
    return null
  }
  const platformIds = platforms.filter(isPlatformId)
  let integrationIds: IntegrationId[] = []
  if (request.mcp.length > 0) {
    const mcp = await multiselect({
      message: 'Integrations',
      options: request.mcp.map((row) => ({ value: row.id, label: row.label })),
      initialValues: request.mcp.filter((row) => row.initial).map((row) => row.id),
      required: false,
    })
    if (isCancel(mcp)) {
      cancel('Cancelled.')
      return null
    }
    integrationIds = mcp.filter(isIntegrationId)
  }
  outro('Writing project files.')
  return { platforms: platformIds, mcp: integrationIds }
}

function help(): string {
  return [
    'Usage:',
    '  astack init [options]       Scaffold and render missing files.',
    '  astack sync [options]       Render missing or managed files.',
    '  astack check [options]      Fail when generated files drift.',
    '  astack adopt [options]      Create neutral role sources from OpenCode agents.',
    '  astack prune                Remove generated files for disabled platforms.',
    '  astack uninstall [--yes]    Remove generated files for every platform.',
    '  astack doctor               Dependencies, skills, governance, updates.',
    '  astack --version            Print the installed kit version.',
    '  astack --help               Show this help.',
    '',
    'On a terminal, init and sync ask for coding agents and integrations.',
    'Non-interactive runs use the saved platforms, or all four.',
    'Specs, Jev, and model choices stay at their saved defaults.',
    'Run scripts/setup-agent-stack.sh directly to use the shell prompts for those steps.',
    '',
    'Options:',
    '  --platforms LIST            opencode, claude, codex, cursor',
    '  --mcp LIST                  none, linear, trello, maestro, both, or a combination',
    '  --yes                       Accept confirmations.',
    '  --force                     Continue when the target is not a git repository.',
    '  --verbose                   List every created or updated file.',
    '',
  ].join('\n')
}

function versionOf(kitRoot: string): string {
  const file = join(kitRoot, 'VERSION')
  if (!existsSync(file)) return '0.0.0'
  return readFileSync(file, 'utf8').split(/\s+/)[0] ?? '0.0.0'
}

function run(command: string, args: readonly string[]): Promise<number> {
  return new Promise((resolveExit) => {
    const child = spawn(command, [...args], { stdio: 'inherit' })
    child.on('error', () => resolveExit(1))
    child.on('exit', (code) => resolveExit(code ?? 1))
  })
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2)
  const moduleDir = dirname(fileURLToPath(import.meta.url))
  const kitRoot = findKitRoot(moduleDir)
  if (argv.length === 0 || argv[0] === '--help' || argv[0] === '-h') {
    process.stdout.write(help())
    return
  }
  if (argv[0] === '--version' || argv[0] === '-v') {
    process.stdout.write(`${versionOf(kitRoot)}\n`)
    return
  }
  const command = argv[0] ?? ''
  if (!MIGRATED.has(command)) {
    const status = await run('sh', [join(kitRoot, 'scripts/astack'), ...argv])
    process.exit(status)
  }
  const projectRoot = projectRootFromArgv(argv, process.cwd())
  const result = await plan({
    argv,
    cwd: process.cwd(),
    kitRoot,
    tty: Boolean(process.stdin.isTTY && process.stdout.isTTY),
    savedText: readSaved(projectRoot),
    ask,
  })
  if (!result.ok) {
    process.stderr.write(`astack: ${result.message}\n`)
    process.exit(result.exitCode)
  }
  for (const line of result.notices) process.stdout.write(`${line}\n`)
  const status = await run('sh', [join(kitRoot, result.shell.script), ...result.shell.argv])
  process.exit(status)
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'unknown error'
  process.stderr.write(`astack: ${message}\n`)
  process.exit(1)
})
