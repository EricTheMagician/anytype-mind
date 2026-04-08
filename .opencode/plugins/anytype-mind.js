/**
 * Anytype Mind — opencode plugin
 *
 * Replaces the Claude Code hooks in .claude/settings.json with native
 * opencode plugin equivalents.
 *
 * Hook mappings:
 *   SessionStart      → session.created  : show space/connectivity banner
 *   PostToolUse (MCP) → tool.execute.before: validate Anytype object properties
 *   PreCompact        → session.compacted : backup session transcript
 *   Stop              → session.idle      : end-of-session checklist
 *
 * Note: Claude Code's UserPromptSubmit hook (classify-message.py) has no
 * direct equivalent in opencode. Content classification is handled via
 * instructions in AGENTS.md instead.
 */

// Required properties per object type — mirrors validate-object.py
const REQUIRED_PROPERTIES = {
  work_note:    ['description', 'status', 'quarter'],
  incident:     ['description', 'status', 'quarter', 'ticket', 'severity', 'incident_role'],
  one_on_one:   ['description', 'quarter'],
  decision:     ['description', 'status'],
  person:       ['description', 'title'],
  team:         ['description'],
  competency:   ['description'],
  pr_analysis:  ['description', 'related_person', 'review_cycle'],
  review_brief: ['description', 'review_cycle'],
  brain_note:   ['description'],
  brag_entry:   ['description', 'quarter'],
  thinking_note:['description'],
};

function validateAnytypeArgs(toolName, args) {
  const warnings = [];
  const tl = toolName.toLowerCase();
  const isCreate = tl.includes('create');
  const { type_key, name, description, properties = {} } = args ?? {};

  const desc = description ?? properties.description ?? '';
  if (!desc && isCreate) {
    warnings.push('Missing `description` — every object needs a ~150 char description');
  }

  if (type_key && REQUIRED_PROPERTIES[type_key]) {
    for (const prop of REQUIRED_PROPERTIES[type_key]) {
      if (prop === 'description') continue;
      if (!(prop in properties) && !(prop in (args ?? {}))) {
        warnings.push(`Missing \`${prop}\` property for type \`${type_key}\``);
      }
    }
  }

  return warnings;
}

export const AnytypeMindPlugin = async ({ client, $ }) => {
  return {
    event: async ({ event }) => {
      switch (event.type) {

        // ── Session start: show space ID + Anytype connectivity status ──────
        case 'session.created': {
          try {
            const result = await $`bash .opencode/scripts/session-start.sh`;
            const out = (result.stdout ?? '').trim();
            if (out) {
              await client.app.log('info', out);
            }
          } catch (_) {
            // Non-fatal — session proceeds without context banner
          }
          break;
        }

        // ── Pre-tool validation: check Anytype object properties ─────────────
        case 'tool.execute.before': {
          const { tool, args } = event.data ?? {};
          if (!tool || !args) break;

          const tl = tool.toLowerCase();
          const isAnytypeWrite =
            (tl.includes('create') || tl.includes('update')) &&
            (tl.includes('object') || tl.includes('anytype'));

          if (isAnytypeWrite) {
            const warnings = validateAnytypeArgs(tool, args);
            if (warnings.length > 0) {
              const label = args.name ?? args.type_key ?? 'object';
              await client.app.log('warn',
                `Anytype validation for \`${label}\`:\n` +
                warnings.map(w => `  - ${w}`).join('\n') +
                '\nFix these before proceeding.'
              );
            }
          }
          break;
        }

        // ── Pre-compact: backup session transcript ───────────────────────────
        case 'session.compacted': {
          try {
            const payload = JSON.stringify({
              transcript_path: event.data?.transcript_path ?? '',
              trigger: event.data?.trigger ?? 'compact',
            });
            await $`echo ${payload} | bash .opencode/scripts/pre-compact.sh`;
          } catch (_) {
            // Non-fatal
          }
          break;
        }

        // ── Session idle: end-of-session checklist ───────────────────────────
        case 'session.idle': {
          await client.app.log('info',
            'Session end checklist:\n' +
            '  - Archive completed projects? (set status=completed on work_note objects)\n' +
            '  - New objects have relations? (orphans are bugs)\n' +
            '  - Brain notes updated? (Memories, Patterns, Key Decisions)\n' +
            '  - Run /vault-audit if many objects were created/modified'
          );
          break;
        }
      }
    },
  };
};
