/**
 * Pipeline state management utilities.
 *
 * Provides functions for reading, writing, and managing pipeline state
 * across orchestrator and stage skills.
 *
 * Usage:
 *   bun pipeline-state.ts status    - Show current pipeline state
 *   bun pipeline-state.ts reset     - Reset pipeline state
 *   bun pipeline-state.ts phase     - Output current phase token
 */

import fs from 'fs';
import path from 'path';
import {
  computeTaskDir,
  determinePhase,
  getProgress,
  getPipelineType,
  type PhaseToken,
  type PhaseResult,
} from './pipeline-utils.ts';

// ─── Types ───────────────────────────────────────────────────────────────────

export interface PipelineState {
  team_name: string;
  pipeline_type: 'feature-implement' | 'bug-fix';
  config_hash: string;
  resolved_config: {
    feature_pipeline: Array<{
      type: string;
      provider: string;
      model: string;
      parallel?: boolean;
    }>;
    bugfix_pipeline: Array<{
      type: string;
      provider: string;
      model: string;
      parallel?: boolean;
    }>;
    max_iterations: number;
    team_name_pattern: string;
  };
  stages: StageInfo[];
  current_phase?: PhaseToken;
  iteration_count?: number;
}

export interface StageInfo {
  type: string;
  provider: string;
  providerType: 'subscription' | 'api' | 'cli';
  model: string;
  output_file: string;
  task_id: string;
  parallel_group_id: number | null;
  current_version: number;
}

export interface StageOutput {
  status: 'pending' | 'complete' | 'approved' | 'needs_changes' | 'rejected' | 'needs_clarification' | 'failed' | 'partial';
  clarification_questions?: string[];
  [key: string]: unknown;
}

// ─── Path Helpers ─────────────────────────────────────────────────────────────

export function getPipelineTasksPath(): string {
  return path.join(computeTaskDir(), 'pipeline-tasks.json');
}

export function getOutputFilePath(outputFile: string): string {
  return path.join(computeTaskDir(), outputFile);
}

// ─── State Operations ──────────────────────────────────────────────────────────

/**
 * Check if a pipeline state exists.
 */
export function stateExists(): boolean {
  return fs.existsSync(getPipelineTasksPath());
}

/**
 * Read the current pipeline state.
 * Returns null if no state exists.
 */
export function readState(): PipelineState | null {
  const filePath = getPipelineTasksPath();
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(raw) as PipelineState;
  } catch {
    return null;
  }
}

/**
 * Write the pipeline state to disk.
 */
export function writeState(state: PipelineState): void {
  const filePath = getPipelineTasksPath();
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });

  // Atomic write
  const tempPath = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  try {
    fs.writeFileSync(tempPath, JSON.stringify(state, null, 2), 'utf-8');
    fs.renameSync(tempPath, filePath);
  } catch (err) {
    try { fs.unlinkSync(tempPath); } catch { /* ignore */ }
    throw err;
  }
}

/**
 * Update a specific stage's task_id in the state.
 */
export function updateStageTaskId(stageIndex: number, newTaskId: string): void {
  const state = readState();
  if (!state) {
    throw new Error('Pipeline state not found');
  }
  if (stageIndex < 0 || stageIndex >= state.stages.length) {
    throw new Error(`Invalid stage index: ${stageIndex}`);
  }
  state.stages[stageIndex].task_id = newTaskId;
  writeState(state);
}

/**
 * Get the current phase token.
 */
export function getCurrentPhase(): PhaseToken {
  if (!stateExists()) {
    return 'idle';
  }
  const progress = getProgress(computeTaskDir());
  const { phase } = determinePhase(progress);
  return phase;
}

/**
 * Get detailed phase information.
 */
export function getPhaseInfo(): PhaseResult {
  if (!stateExists()) {
    return {
      phase: 'idle',
      message: 'No pipeline state found. Start with /dev-buddy-feature-implement or /dev-buddy-bug-fix.'
    };
  }
  const progress = getProgress(computeTaskDir());
  return determinePhase(progress);
}

/**
 * Get the stage info for a specific task ID.
 */
export function getStageByTaskId(taskId: string): { stage: StageInfo; index: number } | null {
  const state = readState();
  if (!state) return null;

  const index = state.stages.findIndex(s => s.task_id === taskId);
  if (index === -1) return null;

  return { stage: state.stages[index], index };
}

/**
 * Get the next stage after a given index.
 */
export function getNextStage(currentIndex: number): StageInfo | null {
  const state = readState();
  if (!state) return null;

  if (currentIndex + 1 >= state.stages.length) return null;
  return state.stages[currentIndex + 1];
}

/**
 * Read the output file for a stage.
 */
export function readStageOutput(outputFile: string): StageOutput | null {
  const filePath = getOutputFilePath(outputFile);
  if (!fs.existsSync(filePath)) return null;

  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(raw) as StageOutput;
  } catch {
    return null;
  }
}

/**
 * Write output for a stage.
 */
export function writeStageOutput(outputFile: string, data: StageOutput): void {
  const filePath = getOutputFilePath(outputFile);
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });

  const tempPath = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  try {
    fs.writeFileSync(tempPath, JSON.stringify(data, null, 2), 'utf-8');
    fs.renameSync(tempPath, filePath);
  } catch (err) {
    try { fs.unlinkSync(tempPath); } catch { /* ignore */ }
    throw err;
  }
}

/**
 * Reset the pipeline state.
 */
export function resetState(): void {
  const taskDir = computeTaskDir();
  if (fs.existsSync(taskDir)) {
    fs.rmSync(taskDir, { recursive: true, force: true });
  }
  fs.mkdirSync(taskDir, { recursive: true });
}

/**
 * Increment iteration count for the pipeline.
 */
export function incrementIteration(): number {
  const state = readState();
  if (!state) {
    throw new Error('Pipeline state not found');
  }
  state.iteration_count = (state.iteration_count || 0) + 1;
  writeState(state);
  return state.iteration_count;
}

/**
 * Get the maximum allowed iterations.
 */
export function getMaxIterations(): number {
  const state = readState();
  if (!state) return 10;
  return state.resolved_config.max_iterations || 10;
}

/**
 * Check if max iterations exceeded.
 */
export function isMaxIterationsExceeded(): boolean {
  const state = readState();
  if (!state) return false;
  const current = state.iteration_count || 0;
  const max = state.resolved_config.max_iterations || 10;
  return current >= max;
}

// ─── CLI Entry Point ──────────────────────────────────────────────────────────

if (import.meta.main) {
  const command = process.argv[2] || 'status';

  switch (command) {
    case 'status':
      if (!stateExists()) {
        console.log(JSON.stringify({ exists: false, phase: 'idle' }));
      } else {
        const state = readState();
        const phase = getCurrentPhase();
        console.log(JSON.stringify({
          exists: true,
          phase,
          team_name: state?.team_name,
          pipeline_type: state?.pipeline_type,
          stage_count: state?.stages.length,
          iteration_count: state?.iteration_count || 0
        }, null, 2));
      }
      break;

    case 'phase':
      console.log(getCurrentPhase());
      break;

    case 'reset':
      resetState();
      console.log(JSON.stringify({ success: true, message: 'Pipeline state reset' }));
      break;

    default:
      console.error(`Unknown command: ${command}`);
      console.error('Usage: pipeline-state.ts {status|phase|reset}');
      process.exit(1);
  }
}