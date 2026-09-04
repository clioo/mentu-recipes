import Foundation

enum PiLaunchRuntime {
    static let source = #"""
    import fs from 'node:fs';
    import path from 'node:path';
    import { spawn } from 'node:child_process';
    import { startGateway } from './gateway.mjs';

    const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    const gateway = await startGateway(config, process.env.MENTU_PI_TARGET_KEY ?? '');
    const profile = path.join(config.attempt_directory, 'profile');
    fs.mkdirSync(profile, { recursive: true, mode: 0o700 });
    const writeJSON = (name, value) => fs.writeFileSync(path.join(profile, name), JSON.stringify(value), { mode: 0o600 });
    writeJSON('models.json', { providers: { 'mentu-bounded': {
      api: 'openai-completions', baseUrl: gateway.baseURL, apiKey: gateway.token,
      compat: { maxTokensField: config.max_tokens_field, supportsDeveloperRole: false,
        supportsReasoningEffort: false, supportsStore: false },
      models: [{ id: config.model, name: config.model, reasoning: false, input: ['text'],
        contextWindow: config.context_window, maxTokens: Math.min(config.max_output_tokens, config.limits.max_output_tokens),
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }]
    } } });
    writeJSON('settings.json', { retry: { enabled: false, maxRetries: 0,
      provider: { maxRetries: 0, timeoutMs: config.request_timeout_ms } },
      compaction: { enabled: false }, packages: [], extensions: [], skills: [],
      checkForUpdates: false });
    writeJSON('auth.json', {});
    const allowedEnvironment = ['PATH', 'HOME', 'SHELL', 'USER', 'LOGNAME', 'TMPDIR', 'TMP', 'TEMP', 'LANG', 'LC_ALL'];
    const env = Object.fromEntries(allowedEnvironment.filter(key => process.env[key]).map(key => [key, process.env[key]]));
    Object.assign(env, { PI_CODING_AGENT_DIR: profile, PI_CODING_AGENT_SESSION_DIR: path.join(profile, 'sessions'),
      PI_OFFLINE: '1', PI_TELEMETRY: '0', NO_COLOR: '1' });
    const args = ['--mode', 'json', '--print', '--provider', 'mentu-bounded', '--model', config.model,
      '--no-session', '--no-extensions', '--no-skills', '--no-context-files', '--no-prompt-templates',
      '--no-themes', '--no-approve', '--offline', '--thinking', 'off'];
    if (config.allowed_tools.length === 0) args.push('--no-tools');
    else args.push('--tools', config.allowed_tools.join(','));
    if (config.disallowed_tools.length) args.push('--exclude-tools', config.disallowed_tools.join(','));
    for (const skill of config.skill_files) args.push('--skill', skill);
    if (config.system_context) args.push('--append-system-prompt', config.system_context);
    const child = spawn(config.pi_executable, args, { cwd: config.workspace, env,
      detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'pipe'] });
    child.stdout.pipe(process.stdout);
    child.stderr.pipe(process.stderr);
    child.stdin.on('error', () => {});
    child.stdin.end(config.prompt);
    let terminated = false;
    let escalation;
    function signalChild(signal) {
      try {
        if (process.platform !== 'win32') process.kill(-child.pid, signal);
        else child.kill(signal);
      } catch { /* The child may already have exited. */ }
    }
    function stop() {
      terminated = true;
      signalChild('SIGTERM');
      escalation = setTimeout(() => signalChild('SIGKILL'), 1000);
    }
    process.once('SIGTERM', stop);
    process.once('SIGINT', stop);
    const deadline = gateway.budget.snapshot().deadline_ms;
    const timer = setTimeout(stop, Math.max(1, Math.min(config.timeout_ms, deadline - Date.now())));
    let spawnError;
    const code = await new Promise(resolve => {
      child.once('error', error => { spawnError = error.code ?? 'spawn_failed'; resolve(127); });
      child.once('close', code => resolve(code ?? 1));
    });
    clearTimeout(timer);
    if (terminated) signalChild('SIGKILL');
    clearTimeout(escalation);
    await gateway.close();
    const receipts = gateway.receipts();
    const knownUsage = receipts.length > 0 && receipts.every(item => item.usage !== null);
    const result = { version: 1, exit_code: terminated ? 124 : (spawnError || gateway.failed() ? 1 : code),
      request_ids: receipts.map(item => item.id), requests: receipts.length,
      input_tokens: knownUsage ? receipts.reduce((sum, item) => sum + item.usage.input_tokens, 0) : null,
      output_tokens: knownUsage ? receipts.reduce((sum, item) => sum + item.usage.output_tokens, 0) : null,
      model: config.model, budget_file: path.join(config.budget_directory, 'budget.json'), spawn_error: spawnError ?? null };
    fs.writeFileSync(path.join(config.attempt_directory, 'inference.json'), JSON.stringify(result, null, 2), { mode: 0o600 });
    process.exitCode = result.exit_code;
    """#
}
