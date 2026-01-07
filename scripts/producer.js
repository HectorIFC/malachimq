#!/usr/bin/env node

/**
 * MalachiMQ Producer - Node.js Client with Authentication
 * 
 * Sends messages to MalachiMQ via TCP with username/password authentication.
 * 
 * Usage:
 *   node producer.js                    # Sends 10 messages
 *   node producer.js 100                # Sends 100 messages
 *   node producer.js 1000 --fast        # Sends 1000 messages in parallel
 *   node producer.js --continuous       # Sends continuously (1 msg/second)
 * 
 * Environment variables:
 *   MALACHIMQ_HOST     Server host (default: localhost)
 *   MALACHIMQ_PORT     Server port (default: 4040)
 *   MALACHIMQ_QUEUE    Queue name (default: test)
 *   MALACHIMQ_USER     Username (default: producer)
 *   MALACHIMQ_PASS     Password (default: producer123)
 *   MALACHIMQ_LOCALE   Locale: pt_BR | en_US (default: pt_BR)
 */

const net = require('net');
const { t } = require('./i18n');

const CONFIG = {
  host: process.env.MALACHIMQ_HOST || 'localhost',
  port: parseInt(process.env.MALACHIMQ_PORT) || 4040,
  queueName: process.env.MALACHIMQ_QUEUE || 'test',
  username: process.env.MALACHIMQ_USER || 'producer',
  password: process.env.MALACHIMQ_PASS || 'producer123',
};

const colors = {
  green: (text) => `\x1b[32m${text}\x1b[0m`,
  red: (text) => `\x1b[31m${text}\x1b[0m`,
  yellow: (text) => `\x1b[33m${text}\x1b[0m`,
  cyan: (text) => `\x1b[36m${text}\x1b[0m`,
  gray: (text) => `\x1b[90m${text}\x1b[0m`,
};

/**
 * MalachiMQ Client with authentication
 */
class MalachiMQClient {
  constructor(options = {}) {
    this.host = options.host || CONFIG.host;
    this.port = options.port || CONFIG.port;
    this.username = options.username || CONFIG.username;
    this.password = options.password || CONFIG.password;
    this.client = null;
    this.token = null;
    this.buffer = '';
    this.pendingResolve = null;
    this.pendingReject = null;
    this.pendingTimeout = null;
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.client = net.createConnection(this.port, this.host, async () => {
        try {
          // Set up persistent data handler
          this.client.on('data', (data) => this._handleData(data));
          await this._authenticate();
          resolve(this);
        } catch (err) {
          this.client.end();
          reject(err);
        }
      });

      this.client.on('error', (err) => {
        if (this.pendingReject) {
          this.pendingReject(err);
          this._clearPending();
        }
        reject(err);
      });
    });
  }

  _handleData(data) {
    this.buffer += data.toString();
    this._processBuffer();
  }

  _processBuffer() {
    while (this.buffer.includes('\n') && this.pendingResolve) {
      const newlineIndex = this.buffer.indexOf('\n');
      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);

      if (!line) continue;

      try {
        const parsed = JSON.parse(line);
        const resolve = this.pendingResolve;
        this._clearPending();
        resolve(parsed);
        return; // Only process one response per pending request
      } catch (e) {
        const resolve = this.pendingResolve;
        this._clearPending();
        resolve({ raw: line });
        return;
      }
    }
  }

  _clearPending() {
    if (this.pendingTimeout) {
      clearTimeout(this.pendingTimeout);
      this.pendingTimeout = null;
    }
    this.pendingResolve = null;
    this.pendingReject = null;
  }

  _authenticate() {
    return new Promise((resolve, reject) => {
      const authMsg = JSON.stringify({
        action: 'auth',
        username: this.username,
        password: this.password,
      }) + '\n';

      this.pendingResolve = (parsed) => {
        if (parsed.s === 'ok' && parsed.token) {
          this.token = parsed.token;
          resolve(parsed);
        } else {
          reject(new Error(t('auth_failed_error') || 'Authentication failed'));
        }
      };
      this.pendingReject = reject;

      this.pendingTimeout = setTimeout(() => {
        this._clearPending();
        reject(new Error(t('timeout_error') || 'Authentication timeout'));
      }, 5000);

      this.client.write(authMsg);
    });
  }

  async send(queueName, payload, headers = {}) {
    if (!this.client || !this.token) {
      throw new Error(t('not_connected_error') || 'Not connected');
    }

    return new Promise((resolve, reject) => {
      const message = JSON.stringify({
        action: 'publish',
        queue_name: queueName,
        payload: payload,
        headers: headers,
      }) + '\n';

      this.pendingResolve = resolve;
      this.pendingReject = reject;

      this.pendingTimeout = setTimeout(() => {
        this._clearPending();
        reject(new Error(t('timeout_error') || 'Timeout'));
      }, 5000);

      this.client.write(message);

      // Check if we already have data in buffer
      this._processBuffer();
    });
  }

  close() {
    if (this.client) {
      this.client.end();
      this.client = null;
      this.token = null;
    }
  }
}

/**
 * Creates an authenticated connection
 */
async function createConnection() {
  const client = new MalachiMQClient();
  await client.connect();
  return client;
}

/**
 * Sends multiple messages sequentially
 */
async function sendMessagesSequential(count) {
  console.log(colors.cyan(`\n${t('producer_title')}`));
  console.log(colors.gray(`   ${t('host')}: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   ${t('queue')}: ${CONFIG.queueName}`));
  console.log(colors.gray(`   ${t('messages')}: ${count}\n`));

  const client = await createConnection();
  console.log(colors.green(`${t('connected')} (authenticated as ${CONFIG.username})\n`));

  const startTime = Date.now();
  let success = 0;
  let errors = 0;

  for (let i = 1; i <= count; i++) {
    try {
      const payload = {
        id: i,
        message: t('message_payload', { id: i }),
        timestamp: new Date().toISOString(),
        source: 'nodejs-producer',
      };

      const headers = {
        'x-message-id': `msg-${i}-${Date.now()}`,
        'x-priority': i % 10 === 0 ? 'high' : 'normal',
      };

      const response = await client.send(CONFIG.queueName, payload, headers);

      if (response.s === 'ok') {
        success++;
        if (count <= 20 || i % Math.ceil(count / 10) === 0) {
          console.log(colors.green(`✓ [${i}/${count}]`) + ` ${t('message_sent')}`);
        }
      } else {
        errors++;
        console.log(colors.red(`✗ [${i}/${count}]`) + ` ${t('error')}: ${JSON.stringify(response)}`);
      }
    } catch (err) {
      errors++;
      console.log(colors.red(`✗ [${i}/${count}]`) + ` ${t('error')}: ${err.message}`);
    }
  }

  client.close();

  const duration = Date.now() - startTime;
  const rate = Math.round((success / duration) * 1000);

  console.log(colors.cyan(`\n${t('result')}`));
  console.log(colors.green(`   ${t('success')}: ${success}`));
  if (errors > 0) console.log(colors.red(`   ${t('errors')}: ${errors}`));
  console.log(colors.gray(`   ${t('time')}: ${duration}ms`));
  console.log(colors.gray(`   ${t('rate')}: ${rate} ${t('msgs_per_second')}\n`));
}

/**
 * Sends multiple messages in parallel (fast mode)
 */
async function sendMessagesFast(count) {
  console.log(colors.cyan(`\n${t('producer_title_fast')}`));
  console.log(colors.gray(`   ${t('host')}: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   ${t('queue')}: ${CONFIG.queueName}`));
  console.log(colors.gray(`   ${t('messages')}: ${count}\n`));

  const poolSize = Math.min(10, count);
  const connections = await Promise.all(
    Array(poolSize).fill().map(() => createConnection())
  );
  console.log(colors.green(`${t('connections_established', { count: poolSize })} (authenticated)\n`));

  const startTime = Date.now();
  let success = 0;
  let errors = 0;

  const promises = [];
  for (let i = 1; i <= count; i++) {
    const client = connections[(i - 1) % poolSize];
    const payload = {
      id: i,
      message: t('fast_message_payload', { id: i }),
      timestamp: new Date().toISOString(),
    };

    promises.push(
      client.send(CONFIG.queueName, payload, { batch: true })
        .then(() => { success++; })
        .catch(() => { errors++; })
    );
  }

  await Promise.all(promises);

  connections.forEach(c => c.close());

  const duration = Date.now() - startTime;
  const rate = Math.round((success / duration) * 1000);

  console.log(colors.cyan(`${t('result')}`));
  console.log(colors.green(`   ${t('success')}: ${success}`));
  if (errors > 0) console.log(colors.red(`   ${t('errors')}: ${errors}`));
  console.log(colors.gray(`   ${t('time')}: ${duration}ms`));
  console.log(colors.yellow(`   ${t('rate')}: ${rate} ${t('msgs_per_second')}\n`));
}

/**
 * Sends messages continuously
 */
async function sendMessagesContinuous() {
  console.log(colors.cyan(`\n${t('producer_title_continuous')}`));
  console.log(colors.gray(`   ${t('host')}: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   ${t('queue')}: ${CONFIG.queueName}`));
  console.log(colors.yellow(`   ${t('press_ctrl_c')}\n`));

  const client = await createConnection();
  console.log(colors.green(`${t('connected')} (authenticated as ${CONFIG.username})\n`));

  let count = 0;

  const interval = setInterval(async () => {
    count++;
    try {
      const payload = {
        id: count,
        message: t('continuous_message_payload', { id: count }),
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      };

      const response = await client.send(CONFIG.queueName, payload, {
        'x-continuous': true,
      });

      if (response.s === 'ok') {
        console.log(colors.green(`✓ [${count}]`) + ` ${new Date().toISOString()}`);
      } else {
        console.log(colors.red(`✗ [${count}]`) + ` ${t('error')}: ${JSON.stringify(response)}`);
      }
    } catch (err) {
      console.log(colors.red(`✗ [${count}]`) + ` ${t('error')}: ${err.message}`);
    }
  }, 1000);

  process.on('SIGINT', () => {
    console.log(colors.yellow(`\n\n${t('stopping')}`));
    clearInterval(interval);
    client.close();
    console.log(colors.cyan(`${t('total_sent', { count })}\n`));
    process.exit(0);
  });
}

async function main() {
  const args = process.argv.slice(2);

  try {
    if (args.includes('--continuous') || args.includes('-c')) {
      await sendMessagesContinuous();
    } else if (args.includes('--fast') || args.includes('-f')) {
      const count = parseInt(args.find(a => !a.startsWith('-'))) || 100;
      await sendMessagesFast(count);
    } else if (args.includes('--help') || args.includes('-h')) {
      console.log(`
${colors.cyan(t('microservice_simulator'))}

${colors.yellow(t('usage'))}
  node producer.js [options] [count]

${colors.yellow(t('options'))}
  -h, --help        ${t('help_show')}
  -f, --fast        ${t('help_fast')}
  -c, --continuous  ${t('help_continuous')}

${colors.yellow(t('examples'))}
  node producer.js              ${t('example_default')}
  node producer.js 100          ${t('example_100')}
  node producer.js 1000 --fast  ${t('example_fast')}
  node producer.js --continuous ${t('example_continuous')}

${colors.yellow(t('env_variables'))}
  MALACHIMQ_HOST   ${t('env_host')}
  MALACHIMQ_PORT   ${t('env_port')}
  MALACHIMQ_QUEUE  ${t('env_queue')}
  MALACHIMQ_USER   Username for authentication (default: producer)
  MALACHIMQ_PASS   Password for authentication (default: producer123)
  MALACHIMQ_LOCALE Locale: pt_BR | en_US (default: pt_BR)
`);
    } else {
      const count = parseInt(args[0]) || 10;
      await sendMessagesSequential(count);
    }
  } catch (err) {
    console.error(colors.red(`\n${t('error_prefix')}: ${err.message}`));
    console.error(colors.gray(`   ${t('check_server_running', { host: CONFIG.host, port: CONFIG.port })}\n`));
    process.exit(1);
  }
}

module.exports = { MalachiMQClient, createConnection };

if (require.main === module) {
  main();
}