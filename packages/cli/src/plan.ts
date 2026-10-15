import {
  INTEGRATIONS,
  MCP_VALID,
  PLATFORM_VALID,
  PLATFORMS,
  renderableIds,
  selectionFromTokens,
  type IntegrationId,
  type PlatformId,
  type RenderableId,
} from './catalog.js'

export type WizardChoice = {
  readonly id: string
  readonly label: string
  readonly initial: boolean
}

export type WizardRequest = {
  readonly platforms: readonly WizardChoice[]
  readonly mcp: readonly WizardChoice[]
}

export type WizardAnswers = {
  readonly platforms: readonly PlatformId[]
  readonly mcp: readonly IntegrationId[]
}

export type PlanInput = {
  readonly argv: readonly string[]
  readonly cwd: string
  readonly kitRoot: string
  readonly tty: boolean
  readonly savedText?: string | null
  readonly answers?: WizardAnswers
  readonly ask?: (request: WizardRequest) => Promise<WizardAnswers | null>
}

export type PlanResult =
  | {
      readonly ok: true
      readonly notices: readonly string[]
      readonly withheld: readonly IntegrationId[]
      readonly shell: { readonly script: string; readonly argv: readonly string[] }
    }
  | { readonly ok: false; readonly exitCode: number; readonly message: string }

const COMMANDS = ['init', 'sync', 'check', 'adopt', 'prune', 'uninstall'] as const
type Command = (typeof COMMANDS)[number]
const SCRIPT = 'scripts/setup-agent-stack.sh'
const PRUNE_REFUSAL = 'prune uses the platforms saved in .agent-stack/config.conf. Run astack init --platforms to change them'

type FlagBag = {
  command: Command | null
  help: boolean
  root?: string
  kitRoot?: string
  platforms?: string
  mcp?: string
  select: boolean
  configureModels: boolean
  skipModels: boolean
  claudeOnly: boolean
  skipOpencode: boolean
  skipClaude: boolean
  skipCodex: boolean
  skipCursor: boolean
  specsRepository?: string
  specsBase?: string
  specsMode?: string
  codexBridge: boolean
  verbose: boolean
  yes: boolean
  force: boolean
}

export function projectRootFromArgv(argv: readonly string[], cwd: string): string {
  let found = cwd
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] !== '--root') continue
    const value = argv[index + 1]
    if (value !== undefined && !value.startsWith('--')) found = value
  }
  return found
}

function fail(message: string, exitCode = 1): PlanResult {
  return { ok: false, exitCode, message }
}

function isCommand(value: string): value is Command {
  return (COMMANDS as readonly string[]).includes(value)
}

function isPlatformId(value: string): value is PlatformId {
  return PLATFORMS.some((row) => row.id === value)
}

function platformTokenOk(token: string): boolean {
  return PLATFORMS.some((row) => row.aliases.some((alias) => alias === token))
}

function readKey(text: string | null | undefined, key: string): string | undefined {
  if (!text) return undefined
  for (const line of text.split('\n')) {
    const eq = line.indexOf('=')
    if (eq === -1) continue
    if (line.slice(0, eq) !== key) continue
    const value = line.slice(eq + 1).trim()
    return value === '' ? undefined : value
  }
  return undefined
}

function savedPlatforms(text: string | null | undefined): PlatformId[] {
  return PLATFORMS.filter((row) => readKey(text, row.savedKey) !== '0').map((row) => row.id)
}

function savedMcp(text: string | null | undefined): Set<RenderableId> {
  const enabled = new Set<RenderableId>()
  for (const row of INTEGRATIONS) {
    if (row.shellToken === null || row.savedKey === null) continue
    if (readKey(text, row.savedKey) === '1') enabled.add(row.id)
  }
  return enabled
}

function takeValue(argv: readonly string[], index: number, flag: string): { ok: true; value: string; next: number } | { ok: false; message: string } {
  const value = argv[index + 1]
  if (value === undefined || value.startsWith('--')) {
    return { ok: false, message: `${flag} requires a value` }
  }
  return { ok: true, value, next: index + 2 }
}

function parseArgv(argv: readonly string[]): { ok: true; flags: FlagBag } | { ok: false; message: string } {
  const flags: FlagBag = {
    command: null,
    help: false,
    select: false,
    configureModels: false,
    skipModels: false,
    claudeOnly: false,
    skipOpencode: false,
    skipClaude: false,
    skipCodex: false,
    skipCursor: false,
    codexBridge: false,
    verbose: false,
    yes: false,
    force: false,
  }
  let index = 0
  while (index < argv.length) {
    const token = argv[index]
    if (token === undefined) break
    if (flags.command === null && isCommand(token)) {
      flags.command = token
      index += 1
      continue
    }
    if (token === '--help' || token === '-h') {
      flags.help = true
      index += 1
      continue
    }
    if (token === '--select') { flags.select = true; index += 1; continue }
    if (token === '--configure-models') { flags.configureModels = true; index += 1; continue }
    if (token === '--skip-models') { flags.skipModels = true; index += 1; continue }
    if (token === '--claude-only') { flags.claudeOnly = true; index += 1; continue }
    if (token === '--skip-opencode') { flags.skipOpencode = true; index += 1; continue }
    if (token === '--skip-claude') { flags.skipClaude = true; index += 1; continue }
    if (token === '--skip-codex') { flags.skipCodex = true; index += 1; continue }
    if (token === '--skip-cursor') { flags.skipCursor = true; index += 1; continue }
    if (token === '--install-codex-bridge') { flags.codexBridge = true; index += 1; continue }
    if (token === '--verbose') { flags.verbose = true; index += 1; continue }
    if (token === '--yes') { flags.yes = true; index += 1; continue }
    if (token === '--force') { flags.force = true; index += 1; continue }
    const valued: Record<string, (value: string) => void> = {
      '--root': (value) => { flags.root = value },
      '--kit-root': (value) => { flags.kitRoot = value },
      '--platforms': (value) => { flags.platforms = value },
      '--mcp': (value) => { flags.mcp = value },
      '--specs-repository': (value) => { flags.specsRepository = value },
      '--specs-base-branch': (value) => { flags.specsBase = value },
      '--specs-mode': (value) => { flags.specsMode = value },
    }
    const assign = valued[token]
    if (!assign) {
      return { ok: false, message: `unknown argument: ${token}` }
    }
    const taken = takeValue(argv, index, token)
    if (!taken.ok) {
      if (token === '--platforms') return { ok: false, message: '--platforms requires a comma-separated list' }
      if (token === '--mcp') return { ok: false, message: '--mcp requires none, linear, trello, maestro, both, or comma-separated combos' }
      return taken
    }
    assign(taken.value)
    index = taken.next
  }
  return { ok: true, flags }
}

function validatePlatformList(value: string): string | undefined {
  const tokens = value.split(',')
  if (tokens.length === 1 && tokens[0]?.trim() === '') {
    return `unknown platform: (empty) (valid: ${PLATFORM_VALID})`
  }
  for (const token of tokens) {
    const trimmed = token.trim()
    if (trimmed === '') return `unknown platform: (empty) (valid: ${PLATFORM_VALID})`
    if (!platformTokenOk(trimmed)) return `unknown platform: ${trimmed} (valid: ${PLATFORM_VALID})`
  }
  return undefined
}

function validateMcpList(value: string): string | undefined {
  const tokens = value.split(',')
  if (value.trim() === '') return `unknown MCP selection: (empty) (valid: ${MCP_VALID})`
  const parsed = selectionFromTokens(tokens, new Set())
  if (!parsed.ok) return parsed.message
  return undefined
}

function explicitPlatform(flags: FlagBag): boolean {
  return flags.platforms !== undefined || flags.claudeOnly || flags.skipOpencode || flags.skipClaude || flags.skipCodex || flags.skipCursor
}

function replacementMcp(ids: readonly IntegrationId[]): string | PlanResult {
  const chosen: RenderableId[] = []
  for (const id of ids) {
    const row = INTEGRATIONS.find((item) => item.id === id)
    if (!row) return fail(`unknown MCP selection: ${id} (valid: ${MCP_VALID})`)
    if (row.shellToken === null) return fail(`${id} is not available yet (valid: ${MCP_VALID})`)
    chosen.push(row.id)
  }
  const ordered = renderableIds().filter((id) => chosen.includes(id))
  return ordered.length === 0 ? 'none' : `none,${ordered.join(',')}`
}

function pushSwitches(argv: string[], flags: FlagBag): void {
  if (flags.select) argv.push('--select')
  if (flags.configureModels) argv.push('--configure-models')
  if (flags.skipModels) argv.push('--skip-models')
  if (flags.claudeOnly) argv.push('--claude-only')
  if (flags.skipOpencode) argv.push('--skip-opencode')
  if (flags.skipClaude) argv.push('--skip-claude')
  if (flags.skipCodex) argv.push('--skip-codex')
  if (flags.skipCursor) argv.push('--skip-cursor')
  if (flags.codexBridge) argv.push('--install-codex-bridge')
  if (flags.verbose) argv.push('--verbose')
  if (flags.yes) argv.push('--yes')
  if (flags.force) argv.push('--force')
  if (flags.specsRepository !== undefined) argv.push('--specs-repository', flags.specsRepository)
  if (flags.specsBase !== undefined) argv.push('--specs-base-branch', flags.specsBase)
  if (flags.specsMode !== undefined) argv.push('--specs-mode', flags.specsMode)
}

export async function plan(input: PlanInput): Promise<PlanResult> {
  const parsed = parseArgv(input.argv)
  if (!parsed.ok) return fail(parsed.message)
  const flags = parsed.flags
  if (flags.command === null) return fail("unknown argument: missing command (see 'astack --help')")
  if (flags.help) {
    return {
      ok: true,
      notices: [],
      withheld: [],
      shell: { script: SCRIPT, argv: [flags.command, '--help'] },
    }
  }
  if (flags.configureModels && flags.skipModels) {
    return fail('--configure-models and --skip-models are mutually exclusive')
  }
  if (flags.specsMode !== undefined && flags.specsMode !== 'local' && flags.specsMode !== 'mirror') {
    return fail(`unknown specs mode: ${flags.specsMode} (valid: local, mirror)`)
  }
  if (flags.platforms !== undefined) {
    const platformError = validatePlatformList(flags.platforms)
    if (platformError) return fail(platformError)
  }
  if (flags.mcp !== undefined) {
    const mcpError = validateMcpList(flags.mcp)
    if (mcpError) return fail(mcpError)
  }
  if (flags.command === 'prune' && explicitPlatform(flags)) return fail(PRUNE_REFUSAL)

  const command = flags.command
  const fills = command === 'init' || command === 'sync'
  const notices: string[] = []
  let platformsArg = flags.platforms
  let mcpArg = flags.mcp
  let passSelect = false
  const withheld: IntegrationId[] = []

  const useAnswers = fills && input.answers !== undefined && platformsArg === undefined && !flags.claudeOnly && !flags.skipOpencode && !flags.skipClaude && !flags.skipCodex && !flags.skipCursor
  const askOnTty = fills && input.tty && !explicitPlatform(flags) && input.answers === undefined
  const numberedShell = fills && flags.select && !input.tty && input.answers === undefined

  if (numberedShell) {
    passSelect = true
  } else if (useAnswers && input.answers) {
    if (input.answers.platforms.length === 0) {
      return fail(`select at least one platform (valid: ${PLATFORM_VALID})`)
    }
    for (const id of input.answers.platforms) {
      if (!isPlatformId(id)) return fail(`unknown platform: ${id} (valid: ${PLATFORM_VALID})`)
    }
    platformsArg = PLATFORMS.filter((row) => input.answers?.platforms.includes(row.id)).map((row) => row.id).join(',')
    if (flags.mcp === undefined) {
      const encoded = replacementMcp(input.answers.mcp)
      if (typeof encoded !== 'string') return encoded
      mcpArg = encoded
    }
  } else if (askOnTty) {
    if (!input.ask) return fail('interactive selection requires a terminal')
    const savedOn = savedMcp(input.savedText)
    const request: WizardRequest = {
      platforms: PLATFORMS.map((row) => ({
        id: row.id,
        label: row.label,
        initial: savedPlatforms(input.savedText).includes(row.id),
      })),
      mcp: flags.mcp !== undefined
        ? []
        : INTEGRATIONS.filter((row) => row.shellToken !== null).map((row) => ({
          id: row.id,
          label: row.label,
          initial: savedOn.has(row.id as RenderableId),
        })),
    }
    const answers = await input.ask(request)
    if (answers === null) return fail('cancelled', 130)
    if (answers.platforms.length === 0) return fail(`select at least one platform (valid: ${PLATFORM_VALID})`)
    for (const id of answers.platforms) {
      if (!isPlatformId(id)) return fail(`unknown platform: ${id} (valid: ${PLATFORM_VALID})`)
    }
    platformsArg = PLATFORMS.filter((row) => answers.platforms.includes(row.id)).map((row) => row.id).join(',')
    if (flags.mcp === undefined) {
      const encoded = replacementMcp(answers.mcp)
      if (typeof encoded !== 'string') return encoded
      mcpArg = encoded
    }
  } else if (fills && platformsArg === undefined && !explicitPlatform(flags)) {
    const chosen = savedPlatforms(input.savedText)
    const names = chosen.join(', ')
    if (!input.tty) {
      notices.push(`Non-interactive ${command} is using ${names}.`)
      notices.push('Pass --platforms to choose a different set.')
    }
    if (chosen.length === 0) {
      flags.skipOpencode = true
      flags.skipClaude = true
      flags.skipCodex = true
      flags.skipCursor = true
    } else {
      platformsArg = chosen.join(',')
    }
  }

  const argv = [command, '--root', flags.root ?? input.cwd, '--kit-root', flags.kitRoot ?? input.kitRoot]
  if (platformsArg !== undefined) argv.push('--platforms', platformsArg)
  if (mcpArg !== undefined) argv.push('--mcp', mcpArg)
  if (fills) flags.select = passSelect
  pushSwitches(argv, flags)
  return { ok: true, notices, withheld, shell: { script: SCRIPT, argv } }
}
