/**
 * Workflow configuration management (v3 inline executor format).
 *
 * Loads and validates ~/.snsplay/sns-workflow.json.
 * Auto-migrates from v2 (StageEntry arrays) and v3-named (top-level executors map) on first load.
 *
 * Usage (CLI mode):
 *   bun workflow-config.ts validate-v3 --cwd <dir>
 *   bun workflow-config.ts migrate --cwd <dir>
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import { readPresets } from './preset-utils.ts';
import type { PipelineConfig, StageEntry, WorkflowConfig, StageExecutor, StageConfig } from '../types/workflow.ts';
import { STAGE_DEFINITIONS, MODEL_NAME_REGEX, VALID_STAGE_TYPES, getV3OutputFileName } from '../types/stage-definitions.ts';
import type { StageType } from '../types/stage-definitions.ts';
import { discoverSystemPrompts } from './system-prompts.ts';

// Config path: ~/.snsplay/sns-workflow.json
export const CONFIG_PATH = path.join(os.homedir(), '.snsplay', 'sns-workflow.json');

// ─── Atomic Writes ───────────────────────────────────────────────────────────

/**
 * Write data to filePath atomically using a temp file + rename pattern.
 * Exported for reuse in config-server.ts.
 */
export function atomicWriteFile(filePath: string, data: unknown): void {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tempPath = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  try {
    fs.writeFileSync(tempPath, JSON.stringify(data, null, 2), 'utf-8');
    fs.renameSync(tempPath, filePath);
  } catch (err) {
    try { fs.unlinkSync(tempPath); } catch { /* ignore cleanup failure */ }
    throw err;
  }
}

// ─── Provider Resolution ─────────────────────────────────────────────────────

/**
 * Get the type of a provider preset by name.
 */
export function getProviderType(presetName: string): 'subscription' | 'api' | 'cli' {
  const presets = readPresets();
  const preset = presets.presets[presetName];
  if (!preset) {
    throw new Error(`Preset '${presetName}' not found`);
  }
  return preset.type;
}

// ─── HTTP Helpers ─────────────────────────────────────────────────────────────

/**
 * HTTP fetch with explicit timeout using AbortController.
 * Exported for reuse in config-server.ts.
 */
export async function fetchWithTimeout(
  url: string,
  options: RequestInit,
  timeoutMs: number
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

// ─── Default v3 Config (inline executors) ────────────────────────────────────

export const DEFAULT_V3_CONFIG: WorkflowConfig = {
  version: '3.0',
  stages: {
    'requirements': { executors: [{ system_prompt: 'requirements-gatherer', preset: 'anthropic-subscription', model: 'opus' }] },
    'planning': { executors: [{ system_prompt: 'planner', preset: 'anthropic-subscription', model: 'opus' }] },
    'plan-review': { executors: [{ system_prompt: 'plan-reviewer', preset: 'anthropic-subscription', model: 'sonnet' }] },
    'implementation': { executors: [{ system_prompt: 'implementer', preset: 'anthropic-subscription', model: 'sonnet' }] },
    'code-review': { executors: [{ system_prompt: 'code-reviewer', preset: 'anthropic-subscription', model: 'sonnet' }] },
    'rca': { executors: [
      { system_prompt: 'root-cause-analyst', preset: 'anthropic-subscription', model: 'sonnet', parallel: true },
      { system_prompt: 'root-cause-analyst', preset: 'anthropic-subscription', model: 'opus' },
    ] },
  },
  feature_workflow: ['requirements', 'planning', 'plan-review', 'implementation', 'code-review'],
  bugfix_workflow: ['rca', 'requirements', 'planning', 'plan-review', 'implementation', 'code-review'],
  max_iterations: 10,
  max_tdd_iterations: 5,
};

// ─── v2 → v3-inline Migration ───────────────────────────────────────────────

/**
 * Migrate a v2 WorkflowConfig (StageEntry arrays) to v3 inline format.
 */
export function migrateV2ToV3(v2: PipelineConfig): WorkflowConfig {
  const stages: Record<string, StageConfig> = {};

  for (const workflow of [v2.feature_workflow, v2.bugfix_workflow]) {
    for (const entry of workflow) {
      const agentType = STAGE_DEFINITIONS[entry.type as StageType]?.agent_type;
      if (!agentType) continue;

      const stageType = entry.type as StageType;
      if (!stages[stageType]) {
        stages[stageType] = { executors: [] };
      }

      const exec: StageExecutor = {
        system_prompt: agentType,
        preset: entry.provider,
        model: entry.model,
      };
      if (entry.parallel) exec.parallel = true;

      // Avoid duplicate executors in same stage
      const isDup = stages[stageType].executors.some(e =>
        e.system_prompt === exec.system_prompt && e.preset === exec.preset && e.model === exec.model
      );
      if (!isDup) {
        stages[stageType].executors.push(exec);
      }
    }
  }

  // Ensure all 6 stage types exist
  for (const stageType of VALID_STAGE_TYPES) {
    if (!stages[stageType]) {
      const defaultStage = DEFAULT_V3_CONFIG.stages[stageType as StageType];
      stages[stageType] = defaultStage ? { executors: [...defaultStage.executors] } : { executors: [] };
    }
  }

  // Auto-fix: last executor in multi-executor stage must be non-parallel (synthesizer rule)
  for (const stage of Object.values(stages)) {
    if (stage.executors.length > 1 && stage.executors[stage.executors.length - 1].parallel === true) {
      stage.executors[stage.executors.length - 1].parallel = false;
    }
  }

  const featureStages = [...new Set(v2.feature_workflow.map(e => e.type as StageType))];
  const bugfixStages = [...new Set(v2.bugfix_workflow.map(e => e.type as StageType))];

  return {
    version: '3.0',
    stages: stages as Record<StageType, StageConfig>,
    feature_workflow: featureStages,
    bugfix_workflow: bugfixStages,
    max_iterations: v2.max_iterations ?? 10,
    max_tdd_iterations: 5,
  };
}

// ─── v3-named → v3-inline Migration ─────────────────────────────────────────

/**
 * Migrate a v3 config with top-level named executors to v3 inline format.
 * Detects old format by presence of top-level 'executors' key.
 */
function migrateV3NamedToInline(config: Record<string, unknown>): WorkflowConfig {
  const namedExecutors = config.executors as Record<string, { system_prompt: string; preset: string; model: string }>;
  const oldStages = config.stages as Record<string, { executors: Array<{ name: string; parallel?: boolean }> }>;
  const newStages: Record<string, StageConfig> = {};

  for (const [stageType, stageConfig] of Object.entries(oldStages)) {
    newStages[stageType] = {
      executors: stageConfig.executors.map(ref => {
        const exec = namedExecutors[ref.name];
        if (!exec) {
          throw new Error(`Migration failed: stage '${stageType}' references unknown executor '${ref.name}'`);
        }
        const inline: StageExecutor = {
          system_prompt: exec.system_prompt,
          preset: exec.preset,
          model: exec.model,
        };
        if (ref.parallel) inline.parallel = true;
        return inline;
      }),
    };
  }

  // Ensure all 6 stage types exist
  for (const stageType of VALID_STAGE_TYPES) {
    if (!newStages[stageType]) {
      const defaultStage = DEFAULT_V3_CONFIG.stages[stageType as StageType];
      newStages[stageType] = defaultStage ? { executors: [...defaultStage.executors] } : { executors: [] };
    }
  }

  return {
    version: '3.0',
    stages: newStages as Record<StageType, StageConfig>,
    feature_workflow: (config.feature_workflow as StageType[]) || DEFAULT_V3_CONFIG.feature_workflow,
    bugfix_workflow: (config.bugfix_workflow as StageType[]) || DEFAULT_V3_CONFIG.bugfix_workflow,
    max_iterations: (config.max_iterations as number) ?? 10,
    max_tdd_iterations: (config.max_tdd_iterations as number) ?? 5,
  };
}

// ─── v3 Validation ──────────────────────────────────────────────────────────

/**
 * Validate a v3 WorkflowConfig (inline executor format).
 */
export function validateWorkflowConfig(config: WorkflowConfig): void {
  if (config.version !== '3.0') {
    throw new Error(`Invalid config version: '${config.version}'. Expected '3.0'.`);
  }

  // Discover available system prompts for name validation
  const builtInDir = path.join(import.meta.dir, '..', 'system-prompts', 'built-in');
  let availablePrompts: Set<string>;
  try {
    const prompts = discoverSystemPrompts(builtInDir);
    availablePrompts = new Set(prompts.map(p => p.name));
  } catch {
    availablePrompts = new Set();
  }

  // Validate stages: all 6 stage types must exist
  for (const stageType of VALID_STAGE_TYPES) {
    const stage = config.stages[stageType as StageType];
    if (!stage) {
      throw new Error(`Missing stage config for '${stageType}'`);
    }
    if (!Array.isArray(stage.executors)) {
      throw new Error(`Stage '${stageType}': executors must be an array`);
    }
    for (let i = 0; i < stage.executors.length; i++) {
      const exec = stage.executors[i];
      if (!exec.system_prompt || typeof exec.system_prompt !== 'string') {
        throw new Error(`Stage '${stageType}' executor[${i}]: system_prompt is required`);
      }
      if (availablePrompts.size > 0 && !availablePrompts.has(exec.system_prompt)) {
        throw new Error(`Stage '${stageType}' executor[${i}]: system_prompt '${exec.system_prompt}' not found. Available: ${[...availablePrompts].join(', ')}`);
      }
      if (!exec.preset || typeof exec.preset !== 'string') {
        throw new Error(`Stage '${stageType}' executor[${i}]: preset is required`);
      }
      // Validate preset exists (skip validation in test environments)
      try {
        getProviderType(exec.preset);
      } catch (err) {
        // Only warn if preset not found - don't fail validation in test env
        const isTest = process.env.NODE_ENV === 'test' || process.env.BUN_TEST === '1';
        if (!isTest) {
          console.warn(`Stage '${stageType}' executor[${i}]: preset '${exec.preset}' not found in ai-presets.json`);
        }
      }
      if (!exec.model || typeof exec.model !== 'string') {
        throw new Error(`Stage '${stageType}' executor[${i}]: model is required`);
      }
      if (!MODEL_NAME_REGEX.test(exec.model)) {
        throw new Error(`Stage '${stageType}' executor[${i}]: invalid model name '${exec.model}'`);
      }
      if (exec.parallel !== undefined && typeof exec.parallel !== 'boolean') {
        throw new Error(`Stage '${stageType}' executor[${i}]: parallel must be a boolean`);
      }
    }

    // Enforce max_executors constraint
    const def = STAGE_DEFINITIONS[stageType as StageType];
    if (def.max_executors !== undefined && stage.executors.length > def.max_executors) {
      throw new Error(
        `Stage '${stageType}': maximum ${def.max_executors} executor(s) allowed, got ${stage.executors.length}`
      );
    }

    // Synthesizer rule: last executor must be non-parallel when multiple executors
    if (stage.executors.length > 1) {
      const lastExec = stage.executors[stage.executors.length - 1];
      if (lastExec.parallel === true) {
        throw new Error(
          `Stage '${stageType}': last executor must be non-parallel (it acts as the synthesizer)`
        );
      }
    }
  }

  // Stages in active workflows must have at least 1 executor
  for (const stageType of VALID_STAGE_TYPES) {
    const stage = config.stages[stageType as StageType];
    const inFeature = config.feature_workflow.includes(stageType as StageType);
    const inBugfix = config.bugfix_workflow.includes(stageType as StageType);
    if ((inFeature || inBugfix) && stage.executors.length === 0) {
      throw new Error(`Stage '${stageType}': must have at least 1 executor (used in active workflow)`);
    }
  }

  // Validate workflows
  for (const [key, workflow] of [['feature_workflow', config.feature_workflow], ['bugfix_workflow', config.bugfix_workflow]] as const) {
    if (!Array.isArray(workflow)) {
      throw new Error(`${key} must be an array`);
    }
    for (let i = 0; i < workflow.length; i++) {
      if (!VALID_STAGE_TYPES.has(workflow[i])) {
        throw new Error(`${key}[${i}]: invalid stage type '${workflow[i]}'`);
      }
      if (workflow[i] === 'rca' && key === 'feature_workflow') {
        throw new Error(`${key}[${i}]: 'rca' is only allowed in bugfix_workflow`);
      }
    }
  }

  // Validate numeric fields
  if (!Number.isInteger(config.max_iterations) || config.max_iterations <= 0) {
    throw new Error(`max_iterations must be a positive integer`);
  }
  if (!Number.isInteger(config.max_tdd_iterations) || config.max_tdd_iterations <= 0) {
    throw new Error(`max_tdd_iterations must be a positive integer`);
  }

  // Validate optional theme field
  if (config.theme !== undefined && config.theme !== 'light' && config.theme !== 'dark') {
    throw new Error(`theme must be 'light' or 'dark'`);
  }
}

// ─── Config Format Detection ────────────────────────────────────────────────

function isV3Inline(parsed: Record<string, unknown>): boolean {
  if (parsed.version !== '3.0') return false;
  // v3-inline: no top-level 'executors' key, stages have inline executor defs
  return !parsed.executors;
}

function isV3Named(parsed: Record<string, unknown>): boolean {
  if (parsed.version !== '3.0') return false;
  // v3-named: has top-level 'executors' key
  return !!parsed.executors;
}

// ─── Config Loading ─────────────────────────────────────────────────────────

/**
 * Load the workflow config as v3-inline.
 * Auto-migrates from v2 or v3-named format and persists with backup.
 */
export function loadWorkflowConfig(): WorkflowConfig {
  if (!fs.existsSync(CONFIG_PATH)) {
    return DEFAULT_V3_CONFIG;
  }

  const raw = fs.readFileSync(CONFIG_PATH, 'utf-8');
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new Error(`Config at ${CONFIG_PATH} is not valid JSON`);
  }

  // Already v3-inline — auto-fix synthesizer rule, then validate and return
  if (isV3Inline(parsed)) {
    const config = parsed as unknown as WorkflowConfig;

    // Auto-migrate legacy field names (v2 → v3): feature_workflow → feature_workflow, bugfix_workflow → bugfix_workflow
    let fieldMigrated = false;
    const anyConfig = parsed as Record<string, unknown>;
    if (!('feature_workflow' in anyConfig) && Array.isArray((anyConfig as any).feature_workflow)) {
      config.feature_workflow = (anyConfig as any).feature_workflow as StageType[];
      delete (anyConfig as any).feature_workflow;
      fieldMigrated = true;
    }
    if (!('bugfix_workflow' in anyConfig) && Array.isArray((anyConfig as any).bugfix_workflow)) {
      config.bugfix_workflow = (anyConfig as any).bugfix_workflow as StageType[];
      delete (anyConfig as any).bugfix_workflow;
      fieldMigrated = true;
    }
    if (fieldMigrated) {
      const backupPath = `${CONFIG_PATH}.backup-fields-${Date.now()}`;
      fs.copyFileSync(CONFIG_PATH, backupPath);
      atomicWriteFile(CONFIG_PATH, config);
      console.error(`[Workflow] Auto-migrated legacy field names. Backup at ${backupPath}`);
      // Reload config after migration to ensure clean state
      return loadWorkflowConfig();
    }

    // Auto-fix: last executor in multi-executor stage must be non-parallel (synthesizer)
    let synthMigrated = false;
    for (const stage of Object.values(config.stages)) {
      if (stage.executors.length > 1 && stage.executors[stage.executors.length - 1].parallel === true) {
        stage.executors[stage.executors.length - 1].parallel = false;
        synthMigrated = true;
      }
    }
    if (synthMigrated) {
      const backupPath = `${CONFIG_PATH}.backup-synth-${Date.now()}`;
      fs.copyFileSync(CONFIG_PATH, backupPath);
      atomicWriteFile(CONFIG_PATH, config);
      console.error(`[Workflow] Auto-migrated synthesizer rule (last executor non-parallel). Backup at ${backupPath}`);
    }
    validateWorkflowConfig(config);
    return config;
  }

  // v3-named — migrate to v3-inline
  if (isV3Named(parsed)) {
    const v3 = migrateV3NamedToInline(parsed);
    validateWorkflowConfig(v3);
    const backupPath = `${CONFIG_PATH}.v3-named.backup`;
    if (!fs.existsSync(backupPath)) {
      fs.copyFileSync(CONFIG_PATH, backupPath);
    }
    atomicWriteFile(CONFIG_PATH, v3);
    console.error(`[Workflow] Auto-migrated config from v3-named to v3-inline. Backup at ${backupPath}`);
    return v3;
  }

  // v2 format — migrate to v3-inline
  const v2 = parsed as unknown as PipelineConfig;
  const v3 = migrateV2ToV3(v2);
  validateWorkflowConfig(v3);
  const backupPath = `${CONFIG_PATH}.v2.backup`;
  if (!fs.existsSync(backupPath)) {
    fs.copyFileSync(CONFIG_PATH, backupPath);
  }
  atomicWriteFile(CONFIG_PATH, v3);
  console.error(`[Workflow] Auto-migrated config from v2 to v3-inline. Backup at ${backupPath}`);
  return v3;
}

// ─── Executor Resolution ────────────────────────────────────────────────────

/**
 * Resolve a stage executor's provider type.
 * Simple helper since inline executors already have all fields.
 */
export function resolveExecutor(executor: StageExecutor): StageExecutor & { providerType: 'subscription' | 'api' | 'cli' } {
  return {
    ...executor,
    providerType: getProviderType(executor.preset),
  };
}

// ─── Workflow Expansion ─────────────────────────────────────────────────────

/** A single expanded task entry for workflow-tasks.json. */
export interface ExpandedStageEntry {
  type: StageType;
  system_prompt: string;
  provider: string;
  model: string;
  providerType: 'subscription' | 'api' | 'cli';
  output_file: string;
  parallel_group_id: string | null;
  /** Version counter. For reviews, always 1 (revision tracked in output JSON via revision_number). For rca, incremented on retry. */
  current_version: number;
}

/**
 * Expand a v3 workflow config into task entries.
 * Each inline executor becomes one entry.
 */
export function expandWorkflowToEntries(
  config: WorkflowConfig,
  workflowKey: 'feature_workflow' | 'bugfix_workflow',
): ExpandedStageEntry[] {
  const workflow = config[workflowKey];
  const entries: ExpandedStageEntry[] = [];
  const typeCounters: Record<string, number> = {};
  let parallelGroupCounter = 0;

  for (const stageType of workflow) {
    const stageConfig = config.stages[stageType];
    if (!stageConfig) continue;

    let inParallelGroup = false;
    let currentGroupId: string | null = null;

    for (const exec of stageConfig.executors) {
      const providerType = getProviderType(exec.preset);
      typeCounters[stageType] = (typeCounters[stageType] || 0) + 1;
      const index = typeCounters[stageType];

      if (exec.parallel) {
        if (!inParallelGroup) {
          parallelGroupCounter++;
          currentGroupId = `pg_${parallelGroupCounter}`;
          inParallelGroup = true;
        }
      } else {
        inParallelGroup = false;
        currentGroupId = null;
      }

      const outputFile = getV3OutputFileName(stageType, exec.system_prompt, index, exec.preset, exec.model, 1);

      entries.push({
        type: stageType,
        system_prompt: exec.system_prompt,
        provider: exec.preset,
        model: exec.model,
        providerType,
        output_file: outputFile,
        parallel_group_id: currentGroupId,
        current_version: 1,
      });
    }
  }

  return entries;
}

// ─── CLI ────────────────────────────────────────────────────────────────────

if (import.meta.main) {
  const command = process.argv[2];

  try {
    switch (command) {
      case 'validate-v3': {
        const config = loadWorkflowConfig();
        const stageCount = Object.values(config.stages).reduce((n, s) => n + s.executors.length, 0);
        console.log(`[Workflow] v3 config valid. ${stageCount} total executors, ${config.feature_workflow.length} feature stages, ${config.bugfix_workflow.length} bugfix stages`);
        break;
      }

      case 'migrate': {
        const v3 = loadWorkflowConfig();
        atomicWriteFile(CONFIG_PATH, v3);
        const stageCount = Object.values(v3.stages).reduce((n, s) => n + s.executors.length, 0);
        console.log(`[Workflow] Config migrated to v3-inline. ${stageCount} total executors.`);
        break;
      }

      default:
        console.error(`Unknown command: ${command}. Use: validate-v3, migrate`);
        process.exit(1);
    }
  } catch (err) {
    if (err instanceof Error) {
      console.error(`[Workflow Config] Error: ${err.message}`);
    } else {
      console.error('[Workflow Config] Unknown error:', err);
    }
    process.exit(1);
  }
}
