// Platforms and integrations. Shell tokens and saved config keys are derived
// from these rows. Jira is a row the shell cannot render yet.

export const PLATFORMS = [
  { id: 'opencode', label: 'OpenCode', aliases: ['opencode'], savedKey: 'ENABLE_OPENCODE' },
  { id: 'claude', label: 'Claude Code', aliases: ['claude', 'claude-code'], savedKey: 'ENABLE_CLAUDE' },
  { id: 'codex', label: 'Codex', aliases: ['codex'], savedKey: 'ENABLE_CODEX' },
  { id: 'cursor', label: 'Cursor', aliases: ['cursor'], savedKey: 'ENABLE_CURSOR' },
] as const

export type PlatformId = (typeof PLATFORMS)[number]['id']

export type Integration =
  | { readonly id: 'linear'; readonly label: 'Linear'; readonly shellToken: 'linear'; readonly savedKey: 'MCP_LINEAR_ENABLED' }
  | { readonly id: 'trello'; readonly label: 'Trello'; readonly shellToken: 'trello'; readonly savedKey: 'MCP_TRELLO_ENABLED' }
  | { readonly id: 'maestro'; readonly label: 'Maestro (local: mobile-qa)'; readonly shellToken: 'maestro'; readonly savedKey: 'MCP_MAESTRO_ENABLED' }
  | { readonly id: 'jira'; readonly label: 'Jira'; readonly shellToken: null; readonly savedKey: null }

export const INTEGRATIONS = [
  { id: 'linear', label: 'Linear', shellToken: 'linear', savedKey: 'MCP_LINEAR_ENABLED' },
  { id: 'trello', label: 'Trello', shellToken: 'trello', savedKey: 'MCP_TRELLO_ENABLED' },
  { id: 'maestro', label: 'Maestro (local: mobile-qa)', shellToken: 'maestro', savedKey: 'MCP_MAESTRO_ENABLED' },
  { id: 'jira', label: 'Jira', shellToken: null, savedKey: null },
] as const satisfies readonly Integration[]

export type IntegrationId = (typeof INTEGRATIONS)[number]['id']
export type RenderableId = Exclude<Integration, { shellToken: null }>['id']

export const PLATFORM_VALID = 'opencode, claude, codex, cursor'
export const MCP_VALID = 'none, linear, trello, maestro, both'

export type GrammarResult =
  | { readonly ok: true; readonly enabled: readonly RenderableId[] }
  | { readonly ok: false; readonly message: string }

const RENDERABLE: readonly RenderableId[] = INTEGRATIONS.flatMap((row) =>
  row.shellToken === null ? [] : [row.id as RenderableId],
)

function isRenderable(token: string): token is RenderableId {
  return (RENDERABLE as readonly string[]).includes(token)
}

// `none` clears the set. Every other token adds. `both` adds linear and
// trello. Order does not matter. Jira is a catalog row the shell cannot render.
export function selectionFromTokens(tokens: readonly string[], base: ReadonlySet<RenderableId>): GrammarResult {
  let reset = false
  const adds: string[] = []
  for (const raw of tokens) {
    const token = raw.trim()
    if (token === '') {
      return { ok: false, message: `unknown MCP selection: (empty) (valid: ${MCP_VALID})` }
    }
    if (token === 'none') {
      reset = true
      continue
    }
    if (token === 'both') {
      adds.push(token)
      continue
    }
    const row = INTEGRATIONS.find((item) => item.id === token)
    if (!row) {
      return { ok: false, message: `unknown MCP selection: ${token} (valid: ${MCP_VALID})` }
    }
    if (row.shellToken === null) {
      return { ok: false, message: `${row.id} is not available yet (valid: ${MCP_VALID})` }
    }
    adds.push(token)
  }
  const enabled = new Set<RenderableId>(reset ? [] : base)
  for (const token of adds) {
    if (token === 'both') {
      enabled.add('linear')
      enabled.add('trello')
    } else if (isRenderable(token)) {
      enabled.add(token)
    }
  }
  return { ok: true, enabled: RENDERABLE.filter((id) => enabled.has(id)) }
}

export function renderableIds(): readonly RenderableId[] {
  return RENDERABLE
}
