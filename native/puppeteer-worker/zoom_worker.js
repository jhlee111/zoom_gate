#!/usr/bin/env node
/**
 * ZoomGate Puppeteer Worker
 *
 * Headless browser running Zoom Web SDK, controlled via stdin/stdout JSON.
 * Drop-in replacement for the C++ zoom_worker.
 *
 * Usage: echo '{"command":"join","meeting_number":"123","password":"abc"}' | node zoom_worker.js
 *
 * Environment:
 *   ZOOM_SDK_KEY, ZOOM_SDK_SECRET — required
 *   CHROME_PATH — optional, defaults to system Chrome
 *   HEADLESS — "true" (default) or "false" for debugging
 */

const puppeteer = require('puppeteer-core');
const crypto = require('crypto');
const path = require('path');
const readline = require('readline');
const http = require('http');
const fs = require('fs');

// ─── Config ───
const SDK_KEY = process.env.ZOOM_SDK_KEY;
const SDK_SECRET = process.env.ZOOM_SDK_SECRET;
const ZAK = process.env.ZOOM_ZAK || '';
const CHROME_PATH = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const HEADLESS = process.env.HEADLESS !== 'false';
const SDK_URL = process.env.ZOOM_SDK_URL || 'https://source.zoom.us/5.1.4/lib/av';

if (!SDK_KEY || !SDK_SECRET) {
  emit({ event: 'error', code: 1, message: 'ZOOM_SDK_KEY and ZOOM_SDK_SECRET required' });
  process.exit(1);
}

// ─── Helpers ───
function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function generateSignature(meetingNumber, role) {
  const iat = Math.floor(Date.now() / 1000) - 30;
  const exp = iat + 7200;
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    appKey: SDK_KEY, sdkKey: SDK_KEY, mn: meetingNumber, role, iat, exp, tokenExp: exp,
  })).toString('base64url');
  const sig = crypto.createHmac('sha256', SDK_SECRET).update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${sig}`;
}

// ─── Mini HTTP server for SDK page ───
const SDK_PATH = path.join(__dirname, '..', 'zoom-web-sdk-analysis', 'package');
let httpPort;

function startStaticServer() {
  return new Promise((resolve) => {
    const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css',
      '.json': 'application/json', '.wasm': 'application/wasm', '.bin': 'application/octet-stream' };

    const srv = http.createServer((req, res) => {
      let filePath;
      if (req.url === '/' || req.url === '/meeting.html') {
        filePath = path.join(__dirname, 'meeting.html');
      } else if (req.url.startsWith('/sdk/')) {
        filePath = path.join(SDK_PATH, req.url.replace('/sdk/', ''));
      } else {
        filePath = path.join(__dirname, req.url);
      }
      const ext = path.extname(filePath);
      const ct = MIME[ext] || 'application/octet-stream';
      fs.readFile(filePath, (err, data) => {
        if (err) {
          const distPath = path.join(SDK_PATH, 'dist', req.url.replace('/sdk/', ''));
          fs.readFile(distPath, (err2, data2) => {
            if (err2) { res.writeHead(404); res.end('Not found'); return; }
            res.writeHead(200, { 'Content-Type': ct }); res.end(data2);
          });
          return;
        }
        res.writeHead(200, { 'Content-Type': ct }); res.end(data);
      });
    });
    srv.listen(0, '127.0.0.1', () => {
      httpPort = srv.address().port;
      resolve(srv);
    });
  });
}

// ─── Main ───
let browser, page, client;
let joined = false;
let seq = 0;
const pendingCallbacks = new Map();

async function launch() {
  const srv = await startStaticServer();

  browser = await puppeteer.launch({
    headless: HEADLESS ? 'new' : false,
    executablePath: CHROME_PATH,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--autoplay-policy=no-user-gesture-required',
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
    ],
  });

  page = (await browser.pages())[0];
  await page.goto(`http://127.0.0.1:${httpPort}/meeting.html`, { waitUntil: 'domcontentloaded' });

  // Load Zoom SDK UMD
  await page.addScriptTag({ path: path.join(SDK_PATH, 'dist', 'zoomus-websdk-embedded.umd.min.js') });

  // Initialize SDK client
  await page.evaluate(() => {
    const sdk = window.ReactWidgets?.default || window.ReactWidgets;
    window.__zoomSDK = sdk;
    window.__zoomClient = null;
  });

  emit({ event: 'ready' });
}

async function joinMeeting(meetingNumber, password, displayName, role) {
  const signature = generateSignature(meetingNumber, role || 0);

  const joinResult = await page.evaluate(async (opts) => {
    const sdk = window.__zoomSDK;
    if (!sdk) return { error: 'SDK not loaded' };

    try {
      const client = sdk.createClient();
      window.__zoomClient = client;

      await client.init({
        zoomAppRoot: document.getElementById('zoomRoot'),
        language: 'en-US',
        patchJsMedia: true,
        leaveOnPageUnload: true,
      });

      const joinConfig = {
        sdkKey: opts.sdkKey,
        signature: opts.signature,
        meetingNumber: opts.meetingNumber,
        userName: opts.displayName,
        password: opts.password || '',
      };

      if (opts.role === 1 && opts.zak) {
        joinConfig.zak = opts.zak;
      }

      await client.join(joinConfig);
      return { success: true };
    } catch (e) {
      return { error: e.type || e.message || String(e), reason: e.reason };
    }
  }, { sdkKey: SDK_KEY, signature, meetingNumber, password, displayName, role, zak: ZAK });

  if (joinResult.error) {
    emit({ event: 'error', code: 200, message: joinResult.error });
    return;
  }

  joined = true;
  emit({ event: 'joined' });

  // Set up event listeners
  await setupEventListeners();
}

async function setupEventListeners() {
  // Expose callback from browser to node
  await page.exposeFunction('__zoomEvent', (eventData) => {
    emit(eventData);
  });

  await page.evaluate(() => {
    const client = window.__zoomClient;
    if (!client) return;

    client.on('user-added', (payload) => {
      const users = Array.isArray(payload) ? payload : [payload];
      for (const u of users) {
        window.__zoomEvent({
          event: u.bHold ? 'waiting_room_join' : 'participant_joined',
          zoom_user_id: u.userId,
          display_name: u.displayName || u.userName || '',
        });
      }
    });

    client.on('user-removed', (payload) => {
      const users = Array.isArray(payload) ? payload : [payload];
      for (const u of users) {
        window.__zoomEvent({
          event: 'participant_left',
          zoom_user_id: u.userId,
        });
      }
    });

    client.on('user-updated', (payload) => {
      const users = Array.isArray(payload) ? payload : [payload];
      for (const u of users) {
        // Detect waiting room → admitted transition
        if (u.bHold === false) {
          window.__zoomEvent({
            event: 'participant_joined',
            zoom_user_id: u.userId,
            display_name: u.displayName || u.userName || '',
          });
        }
        window.__zoomEvent({
          event: 'user_updated',
          zoom_user_id: u.userId,
          display_name: u.displayName || u.userName || '',
          is_host: !!u.isHost,
          audio: u.audio || '',
          video: !!u.bVideoOn,
        });
      }
    });

    client.on('meeting-ended', () => {
      window.__zoomEvent({ event: 'meeting_ended' });
    });

    client.on('chat-received', (msg) => {
      window.__zoomEvent({
        event: 'chat_received',
        from_user_id: msg.sender?.userId,
        from_name: msg.sender?.name || '',
        message: msg.message || '',
      });
    });
  });
}

async function handleCommand(cmd) {
  if (!cmd || !cmd.command) return;

  switch (cmd.command) {
    case 'join':
      await joinMeeting(cmd.meeting_number, cmd.password, cmd.display_name || 'ZoomGate-Bot', cmd.role || 0);
      break;

    case 'leave':
      if (joined) {
        await page.evaluate(() => window.__zoomClient?.leaveMeeting());
        emit({ event: 'left' });
        joined = false;
      }
      break;

    case 'admit':
      await execSDK(`client.admit(${cmd.zoom_user_id})`, cmd);
      break;

    case 'admit_all':
      await execSDK(`client.admitAll()`, cmd);
      break;

    case 'deny':
    case 'expel':
      await execSDK(`client.expel(${cmd.zoom_user_id})`, cmd);
      break;

    case 'rename':
      await execSDK(`client.rename(${JSON.stringify(cmd.display_name)}, ${cmd.zoom_user_id})`, cmd);
      break;

    case 'mute':
      await execSDK(`client.mute(true, ${cmd.zoom_user_id})`, cmd);
      break;

    case 'unmute':
      await execSDK(`client.mute(false, ${cmd.zoom_user_id})`, cmd);
      break;

    case 'chat':
      if (cmd.to) {
        await execSDK(`client.sendChat(${JSON.stringify(cmd.message)}, ${cmd.to})`, cmd);
      } else {
        await execSDK(`client.sendChat(${JSON.stringify(cmd.message)})`, cmd);
      }
      break;

    case 'put_on_hold':
      await execSDK(`client.putOnHold(${cmd.zoom_user_id}, true)`, cmd);
      break;

    case 'make_host':
      await execSDK(`client.makeHost(${cmd.zoom_user_id})`, cmd);
      break;

    case 'make_cohost':
      await execSDK(`client.makeCoHost(${cmd.zoom_user_id})`, cmd);
      break;

    case 'list_participants':
      const attendees = await page.evaluate(() => {
        const client = window.__zoomClient;
        return client ? client.getAttendeeslist() : [];
      });
      emit({ event: 'participants', participants: attendees });
      break;

    case 'get_current_user':
      const user = await page.evaluate(() => {
        const client = window.__zoomClient;
        return client ? client.getCurrentUser() : null;
      });
      emit({ event: 'current_user', user });
      break;

    case 'end_meeting':
      await execSDK(`client.endMeeting()`, cmd);
      break;

    default:
      emit({ event: 'error', code: 400, message: `Unknown command: ${cmd.command}` });
  }
}

async function execSDK(expr, cmd) {
  try {
    const result = await page.evaluate(async (code) => {
      const client = window.__zoomClient;
      if (!client) return { error: 'not joined' };
      try {
        const r = await eval(code);
        return { success: true, result: r };
      } catch (e) {
        return { error: e.type || e.message || String(e), reason: e.reason };
      }
    }, expr);

    if (result.error) {
      emit({ event: 'error', code: 500, message: result.error, command: cmd.command });
    } else {
      emit({ event: 'command_ok', command: cmd.command });
    }
  } catch (e) {
    emit({ event: 'error', code: 500, message: e.message, command: cmd.command });
  }
}

// ─── stdin reader with launch queue ───
let launchReady = false;
const commandQueue = [];

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on('line', async (line) => {
  try {
    const cmd = JSON.parse(line.trim());
    if (launchReady) {
      await handleCommand(cmd);
    } else {
      commandQueue.push(cmd);
    }
  } catch (e) {
    emit({ event: 'error', code: 400, message: `Invalid JSON: ${e.message}` });
  }
});

rl.on('close', async () => {
  if (browser) await browser.close();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  if (browser) await browser.close();
  process.exit(0);
});

// ─── Start ───
launch().then(async () => {
  launchReady = true;
  // Drain queued commands
  for (const cmd of commandQueue) {
    await handleCommand(cmd);
  }
  commandQueue.length = 0;
}).catch(e => {
  emit({ event: 'error', code: 1, message: e.message });
  process.exit(1);
});
