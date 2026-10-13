// Launch ChatGPT with a private DevTools pipe and serve the patched
// app-initial/app-primary bundles in place of the shipped ones. Nothing in the
// app bundle is modified, so OpenAI's code signature stays valid.
//
// usage: node inject.mjs --app /Applications/ChatGPT.app --patch-dir DIR [--helper spawn_disclaim]
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => (v.startsWith('--') ? [...acc, [v.slice(2), a[i + 1]]] : acc), []));
const app = args.app ?? '/Applications/ChatGPT.app';
const binary = path.join(app, 'Contents/MacOS/ChatGPT');
const log = (...a) => console.log(new Date().toISOString(), ...a);

const patched = Object.fromEntries(
  fs.readdirSync(args['patch-dir']).filter((f) => f.endsWith('.js')).map((f) => [f, fs.readFileSync(path.join(args['patch-dir'], f)).toString('base64')]),
);
if (Object.keys(patched).length === 0) throw new Error(`no patched bundles in ${args['patch-dir']}`);
const patterns = Object.keys(patched).map((f) => ({ urlPattern: `*/${f}`, requestStage: 'Response' }));

const command = args.helper ? [args.helper, binary] : [binary];
const child = spawn(command[0], [...command.slice(1), '--remote-debugging-pipe'], { stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] });
child.on('exit', (code, signal) => { log('ChatGPT exited', code ?? signal); process.exit(0); });
const toBrowser = child.stdio[3], fromBrowser = child.stdio[4];
toBrowser.on('error', () => {});

let nextId = 0, buffer = '';
const pending = new Map();
function send(method, params = {}, sessionId) {
  return new Promise((resolve) => {
    const msg = { id: ++nextId, method, params, ...(sessionId ? { sessionId } : {}) };
    pending.set(msg.id, resolve);
    toBrowser.write(JSON.stringify(msg) + '\0');
  });
}

fromBrowser.on('data', (chunk) => {
  buffer += chunk.toString();
  let end;
  while ((end = buffer.indexOf('\0')) >= 0) {
    const msg = JSON.parse(buffer.slice(0, end));
    buffer = buffer.slice(end + 1);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    } else {
      onEvent(msg).catch((e) => log('event error', e));
    }
  }
});
fromBrowser.on('end', () => log('DevTools pipe closed'));

async function onEvent({ method, params, sessionId }) {
  if (method === 'Target.attachedToTarget') {
    const { sessionId: target, targetInfo, waitingForDebugger } = params;
    // Commands on one session run in order, so interception is active before the page resumes.
    if (targetInfo.type === 'page') send('Fetch.enable', { patterns }, target);
    if (waitingForDebugger) send('Runtime.runIfWaitingForDebugger', {}, target);
  } else if (method === 'Fetch.requestPaused') {
    const { requestId, request, responseStatusCode, responseHeaders = [] } = params;
    const name = request.url.split(/[?#]/)[0].split('/').pop();
    if (patched[name] && responseStatusCode === 200) {
      const headers = responseHeaders.filter((h) => h.name.toLowerCase() !== 'content-length');
      const r = await send('Fetch.fulfillRequest', { requestId, responseCode: 200, responseHeaders: headers, body: patched[name] }, sessionId);
      if (!r.error) return log('served patched', name);
      log('fulfill failed', name, JSON.stringify(r.error));
    }
    send('Fetch.continueRequest', { requestId }, sessionId);
  }
}

const attach = await send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
log('launched', app, attach.error ? `auto-attach failed: ${JSON.stringify(attach.error)}` : 'with More details patch');
