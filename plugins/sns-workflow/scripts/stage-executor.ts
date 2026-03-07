/**
 * Stage execution utilities.
 *
 * Provides common logic for executing pipeline stages,
 * handling provider routing, and managing stage results.
 *
 * Usage:
 *   bun stage-executor.ts route --task-id <id>   - Show routing info for a task
 *   bun stage-executor.ts validate --output <file> - Validate a stage output file
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import { readPresets } from './preset-utils.ts';
import { readState, getStageByTaskId, type StageInfo } from './pipeline-state.ts';
import { computeTaskDir } from './pipeline-utils.ts';

// ─── Types ───────────────────────────────────────────────────────────────────

export interface ProviderRoute {
  provider_name: string;
  provider_type: 'subscription' | 'api' | 'cli';
  model: string;
  timeout_ms?: number;
  base_url?: string;
  api_key?: string;
}

export interface StageResult {
  status: 'approved' | 'needs_changes' | 'rejected' | 'needs_clarification' | 'failed' | 'complete' | 'partial';
  clarification_questions?: string[];
  feedback?: string[];
  changes_required?: string[];
}

export interface ValidationResult {
  valid: boolean;
  file: string;
  status?: string;
  error?: string;
  fields?: Record<string, unknown>;
}

// ─── Provider Routing ─────────────────────────────────────────────────────────

/**
 * Get provider routing information for a stage.
 */
export function getProviderRoute(stage: StageInfo): ProviderRoute {
  const presets = readPresets();
  const preset = presets.presets[stage.provider];

  if (!preset) {
    throw new Error(`Preset '${stage.provider}' not found in ~/.vcp/ai-presets.json`);
  }

  const route: ProviderRoute = {
    provider_name: stage.provider,
    provider_type: preset.type,
    model: stage.model,
  };

  if (preset.type === 'api') {
    route.timeout_ms = preset.timeout_ms || 300000;
    route.base_url = preset.base_url;
    route.api_key = preset.api_key ? '[REDACTED]' : undefined;
  }

  return route;
}

/**
 * Get provider route by task ID.
 */
export function getProviderRouteByTaskId(taskId: string): ProviderRoute | null {
  const result = getStageByTaskId(taskId);
  if (!result) return null;
  return getProviderRoute(result.stage);
}

/**
 * Check if a stage should use CLI executor.
 */
export function isCliStage(stage: StageInfo): boolean {
  return stage.providerType === 'cli';
}

/**
 * Check if a stage should use API runner.
 */
export function isApiStage(stage: StageInfo): boolean {
  return stage.providerType === 'api';
}

/**
 * Check if a stage should use subscription (direct Task tool).
 */
export function isSubscriptionStage(stage: StageInfo): boolean {
  return stage.providerType === 'subscription';
}

// ─── Output Validation ───────────────────────────────────────────────────────

/**
 * Validate a stage output file.
 */
export function validateOutput(outputFile: string, expectedFields: string[]): ValidationResult {
  const filePath = path.join(computeTaskDir(), outputFile);

  if (!fs.existsSync(filePath)) {
    return { valid: false, file: outputFile, error: 'File does not exist' };
  }

  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw);

    // Check for required status field
    if (typeof data.status !== 'string') {
      return { valid: false, file: outputFile, error: 'Missing or invalid status field' };
    }

    // Check for expected fields
    const missingFields = expectedFields.filter(f => !(f in data));
    if (missingFields.length > 0) {
      return {
        valid: false,
        file: outputFile,
        status: data.status,
        error: `Missing fields: ${missingFields.join(', ')}`
      };
    }

    return { valid: true, file: outputFile, status: data.status, fields: data };
  } catch (e) {
    return {
      valid: false,
      file: outputFile,
      error: `Invalid JSON: ${(e as Error).message}`
    };
  }
}

/**
 * Validate requirements stage output.
 */
export function validateRequirementsOutput(outputFile: string): ValidationResult {
  // Requirements output is the user-story manifest
  return validateOutput(outputFile, ['id', 'title', 'ac_count']);
}

/**
 * Validate planning stage output.
 */
export function validatePlanningOutput(outputFile: string): ValidationResult {
  // Planning output is the plan manifest
  return validateOutput(outputFile, ['id', 'title', 'step_count']);
}

/**
 * Validate review stage output.
 */
export function validateReviewOutput(outputFile: string): ValidationResult {
  return validateOutput(outputFile, ['status', 'reviewer']);
}

/**
 * Validate implementation stage output.
 */
export function validateImplementationOutput(outputFile: string): ValidationResult {
  return validateOutput(outputFile, ['status']);
}

// ─── Stage Result Handling ───────────────────────────────────────────────────

/**
 * Parse a stage result from output file.
 */
export function parseStageResult(outputFile: string): StageResult | null {
  const filePath = path.join(computeTaskDir(), outputFile);

  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw);

    return {
      status: data.status,
      clarification_questions: data.clarification_questions,
      feedback: data.feedback,
      changes_required: data.changes_required,
    };
  } catch {
    return null;
  }
}

/**
 * Determine if a stage result requires follow-up action.
 */
export function getStageActionResult(result: StageResult): {
  action: 'complete' | 'fix' | 'clarify' | 'escalate';
  reason?: string;
} {
  switch (result.status) {
    case 'approved':
    case 'complete':
      return { action: 'complete' };

    case 'needs_changes':
      return { action: 'fix', reason: 'Reviewer requested changes' };

    case 'needs_clarification':
      return { action: 'clarify', reason: 'Reviewer has questions' };

    case 'rejected':
      return { action: 'escalate', reason: 'Reviewer rejected the output' };

    case 'failed':
    case 'partial':
      return { action: 'escalate', reason: `Stage reported ${result.status}` };

    default:
      return { action: 'escalate', reason: `Unknown status: ${result.status}` };
  }
}

// ─── Task Description Helpers ─────────────────────────────────────────────────

/**
 * Derive task subject from stage info.
 */
export function deriveTaskSubject(stage: StageInfo): string {
  const modelSuffix = stage.model ? ` - ${stage.model.charAt(0).toUpperCase() + stage.model.slice(1)}` : '';
  const cliSuffix = stage.providerType === 'cli' ? ' - Codex' : '';

  switch (stage.type) {
    case 'requirements':
      return 'Gather requirements';
    case 'planning':
      return 'Create implementation plan';
    case 'plan-review':
      return `Plan Review ${stage.output_file.match(/\d+/)?.[0] || ''}${modelSuffix}${cliSuffix}`.trim();
    case 'implementation':
      return 'Implementation';
    case 'code-review':
      return `Code Review ${stage.output_file.match(/\d+/)?.[0] || ''}${modelSuffix}${cliSuffix}`.trim();
    case 'rca':
      return `Root Cause Analysis ${stage.output_file.match(/\d+/)?.[0] || ''}${modelSuffix}`.trim();
    default:
      return stage.type;
  }
}

/**
 * Get the agent name for a stage type.
 */
export function getAgentForStage(stageType: string): string {
  const agentMap: Record<string, string> = {
    'requirements': 'requirements-gatherer',
    'planning': 'planner',
    'plan-review': 'plan-reviewer',
    'implementation': 'implementer',
    'code-review': 'code-reviewer',
    'rca': 'root-cause-analyst',
  };
  return agentMap[stageType] || stageType;
}

// ─── CLI Entry Point ──────────────────────────────────────────────────────────

if (import.meta.main) {
  const command = process.argv[2];

  switch (command) {
    case 'route': {
      const taskIdIndex = process.argv.indexOf('--task-id');
      if (taskIdIndex < 0) {
        console.error('Error: --task-id required');
        process.exit(1);
      }
      const taskId = process.argv[taskIdIndex + 1];
      const route = getProviderRouteByTaskId(taskId);
      if (!route) {
        console.error(`Task not found: ${taskId}`);
        process.exit(1);
      }
      console.log(JSON.stringify(route, null, 2));
      break;
    }

    case 'validate': {
      const outputIndex = process.argv.indexOf('--output');
      if (outputIndex < 0) {
        console.error('Error: --output required');
        process.exit(1);
      }
      const outputFile = process.argv[outputIndex + 1];
      const typeIndex = process.argv.indexOf('--type');
      const type = typeIndex >= 0 ? process.argv[typeIndex + 1] : 'review';

      let result: ValidationResult;
      switch (type) {
        case 'requirements':
          result = validateRequirementsOutput(outputFile);
          break;
        case 'planning':
          result = validatePlanningOutput(outputFile);
          break;
        case 'implementation':
          result = validateImplementationOutput(outputFile);
          break;
        default:
          result = validateReviewOutput(outputFile);
      }
      console.log(JSON.stringify(result, null, 2));
      break;
    }

    default:
      console.error(`Unknown command: ${command}`);
      console.error('Usage: stage-executor.ts {route|validate} [options]');
      process.exit(1);
  }
}