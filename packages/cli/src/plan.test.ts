import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { INTEGRATIONS, selectionFromTokens } from './catalog.js'
import type { IntegrationId, PlatformId } from './catalog.js'
import { plan, projectRootFromArgv, type WizardRequest } from './plan.js'

const base = { cwd: '/repo', kitRoot: '/kit', savedText: null }

function enabled(tokens: readonly string[], start: readonly ('linear' | 'trello' | 'maestro')[] = []) {
  return selectionFromTokens(tokens, new Set(start))
}

describe('mcp grammar', () => {
  it('treats none as a reset and ignores token order', () => {
    const left = enabled(['linear', 'none', 'maestro'])
    const right = enabled(['none', 'maestro', 'linear'])
    assert.deepEqual(left, right)
    assert.deepEqual(left, { ok: true, enabled: ['linear', 'maestro'] })
  })

  it('expands both to linear and trello without disabling maestro', () => {
    const left = enabled(['both', 'maestro'])
    const right = enabled(['maestro', 'both'])
    assert.deepEqual(left, { ok: true, enabled: ['linear', 'trello', 'maestro'] })
    assert.deepEqual(right, left)
  })

  it('adds a later linear token without turning other servers off', () => {
    const result = enabled(['linear'], ['linear', 'trello', 'maestro'])
    assert.deepEqual(result, { ok: true, enabled: ['linear', 'trello', 'maestro'] })
  })

  it('rejects an unknown token and names the valid ids', () => {
    const result = enabled(['nope'])
    assert.equal(result.ok, false)
    if (!result.ok) assert.match(result.message, /valid: none, linear, trello, maestro, both/)
  })

  it('keeps jira in the table and refuses to treat it as a shell token', () => {
    const jira = INTEGRATIONS.find((row) => row.id === 'jira')
    assert.ok(jira)
    assert.equal(jira.shellToken, null)
    const result = enabled(['jira'])
    assert.equal(result.ok, false)
    if (!result.ok) assert.match(result.message, /not available yet/)
  })
})

describe('plan', () => {
  it('rejects an unknown platform before a shell argv exists', async () => {
    const result = await plan({ ...base, argv: ['init', '--platforms', 'nope'], tty: false })
    assert.equal(result.ok, false)
    if (!result.ok) {
      assert.equal(result.exitCode, 1)
      assert.match(result.message, /unknown platform: nope \(valid: opencode, claude, codex, cursor\)/)
    }
  })

  it('rejects an unknown mcp value before a shell argv exists', async () => {
    const result = await plan({ ...base, argv: ['init', '--platforms', 'opencode', '--mcp', 'linear,nope'], tty: false })
    assert.equal(result.ok, false)
    if (!result.ok) assert.match(result.message, /valid: none, linear, trello, maestro, both/)
  })

  it('prints the non-interactive default platforms and passes them to the shell', async () => {
    const result = await plan({ ...base, argv: ['init'], tty: false })
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.ok(result.notices.some((line) => line === 'Non-interactive init is using opencode, claude, codex, cursor.'))
      assert.ok(result.shell.argv.includes('--platforms'))
      const index = result.shell.argv.indexOf('--platforms')
      assert.equal(result.shell.argv[index + 1], 'opencode,claude,codex,cursor')
      assert.equal(result.shell.argv.includes('--mcp'), false)
    }
  })

  it('uses saved platform flags when stdin is not a terminal', async () => {
    const saved = 'ENABLE_OPENCODE=0\nENABLE_CLAUDE=1\nENABLE_CODEX=0\nENABLE_CURSOR=1\n'
    const result = await plan({ ...base, argv: ['sync'], tty: false, savedText: saved })
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.ok(result.notices.some((line) => line.includes('claude, cursor')))
      const index = result.shell.argv.indexOf('--platforms')
      assert.equal(result.shell.argv[index + 1], 'claude,cursor')
    }
  })

  it('asks on a terminal with every platform selected and no integration selected', async () => {
    let request: WizardRequest | undefined
    const result = await plan({
      ...base,
      argv: ['init'],
      tty: true,
      ask: async (value) => {
        request = value
        return {
          platforms: value.platforms.filter((row) => row.initial).map((row) => row.id as PlatformId),
          mcp: value.mcp.filter((row) => row.initial).map((row) => row.id as IntegrationId),
        }
      },
    })
    assert.ok(request)
    assert.deepEqual(request.platforms.map((row) => row.initial), [true, true, true, true])
    assert.deepEqual(request.mcp.map((row) => [row.id, row.initial]), [
      ['linear', false],
      ['trello', false],
      ['maestro', false],
    ])
    assert.equal(request.mcp.some((row) => row.id === 'jira'), false)
    assert.equal(result.ok, true)
    if (result.ok) {
      const mcp = result.shell.argv[result.shell.argv.indexOf('--mcp') + 1]
      assert.equal(mcp, 'none')
    }
  })

  it('encodes a wizard selection as a replacement, not an addition', async () => {
    const result = await plan({
      ...base,
      argv: ['init'],
      tty: true,
      savedText: 'MCP_LINEAR_ENABLED=1\nMCP_TRELLO_ENABLED=1\n',
      answers: { platforms: ['cursor'], mcp: ['linear'] },
    })
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.equal(result.shell.argv[result.shell.argv.indexOf('--platforms') + 1], 'cursor')
      assert.equal(result.shell.argv[result.shell.argv.indexOf('--mcp') + 1], 'none,linear')
    }
  })

  it('forwards an explicit mcp list unchanged after validation', async () => {
    const result = await plan({
      ...base,
      argv: ['init', '--platforms', 'opencode', '--mcp', 'linear,none,maestro'],
      tty: true,
    })
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.equal(result.shell.argv[result.shell.argv.indexOf('--mcp') + 1], 'linear,none,maestro')
    }
  })

  it('refuses prune platform flags', async () => {
    const result = await plan({ ...base, argv: ['prune', '--skip-claude'], tty: false })
    assert.equal(result.ok, false)
    if (!result.ok) assert.match(result.message, /config\.conf/)
  })

  it('applies saved platforms from the last --root, not an earlier one', async () => {
    const result = await plan({
      ...base,
      argv: ['init', '--root', '/caller', '--root', '/target'],
      tty: false,
      savedText: 'ENABLE_OPENCODE=1\nENABLE_CLAUDE=0\nENABLE_CODEX=0\nENABLE_CURSOR=0\n',
    })
    assert.equal(projectRootFromArgv(['init', '--root', '/caller', '--root', '/target'], '/caller'), '/target')
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.equal(result.shell.argv[result.shell.argv.indexOf('--root') + 1], '/target')
      assert.equal(result.shell.argv[result.shell.argv.indexOf('--platforms') + 1], 'opencode')
    }
  })

  it('leaves prune --select for the shell instead of turning it into --platforms', async () => {
    const result = await plan({
      ...base,
      argv: ['prune', '--select'],
      tty: true,
      ask: async () => {
        throw new Error('prune must not open the wizard')
      },
    })
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.equal(result.shell.argv.includes('--platforms'), false)
      assert.equal(result.shell.argv.includes('--select'), true)
    }
  })

  it('returns 130 when the wizard is cancelled', async () => {
    const result = await plan({
      ...base,
      argv: ['init'],
      tty: true,
      ask: async () => null,
    })
    assert.equal(result.ok, false)
    if (!result.ok) assert.equal(result.exitCode, 130)
  })
})
