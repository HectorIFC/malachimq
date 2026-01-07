#!/usr/bin/env node

/**
 * MalachiMQ Producer - Node.js Client with Authentication
 * 
 * Sends messages to MalachiMQ via TCP with username/password authentication.
 * Features automatic reconnection on server restart (continuous mode).
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
 * MalachiMQ Client with authentication and auto-reconnect support
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
    
    // Auto-reconnect settings
    this.autoReconnect = options.autoReconnect || false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = options.maxReconnectAttempts || 10;
    this.baseReconnectDelay = options.baseReconnectDelay || 1000;
    this.maxReconnectDelay = options.maxReconnectDelay || 30000;
    this.isReconnecting = false;
    this.shouldStop = false;
    this.isConnected = false;
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.client = net.createConnection(this.port, this.host, async () => {
        try {
          // Set up persistent data handler
          this.client.on('data', (data) => this._handleData(data));
          await this._authenticate();
          this.isConnected = true;
          this.reconnectAttempts = 0;
          resolve(this);
        } catch (err) {
          this.isConnected = false;
          if (this.client) {
            try {
              this.client.end();
            } catch (e) {
              // Ignore
            }
          }
          reject(err);
        }
      });

      this.client.on('error', (err) => {
        this.isConnected = false;
        
        // Clear any pending operations
        if (this.pendingReject) {
          this.pendingReject(err);
          this._clearPending();
        }
        
        // If we're already trying to reconnect, just reject the promise
        // The scheduled reconnect will handle the retry
        if (this.isReconnecting) {
          reject(err);
          return;
        }
        
        // Start reconnection if enabled
        if (this.autoReconnect && !this.shouldStop) {
          this._handleDisconnect(err);
          // Don't reject immediately - let reconnection handle it
          if (!this.isReconnecting) {
            reject(err);
          }
        } else {
          reject(err);
        }
      });

      this.client.on('close', () => {
        this.isConnected = false;
        
        // Only trigger reconnect if not already reconnecting and should continue
        if (!this.shouldStop && !this.isReconnecting && this.autoReconnect) {
          this._handleDisconnect(new Error('Connection closed'));
        }
      });
    });
  }

  _handleDisconnect(err) {
    if (this.shouldStop || this.isReconnecting) return;

    if (this.autoReconnect && this.reconnectAttempts < this.maxReconnectAttempts) {
      this._scheduleReconnect();
    } else if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error(colors.red(`\n❌ Max reconnect attempts reached (${this.maxReconnectAttempts})`));
    }
  }

  _scheduleReconnect() {
    if (this.isReconnecting || this.shouldStop) return;

    this.isReconnecting = true;
    this.reconnectAttempts++;

    // Exponential backoff with jitter
    const delay = Math.min(
      this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts - 1) + Math.random() * 1000,
      this.maxReconnectDelay
    );

    console.log(colors.yellow(`\n🔄 Reconnecting in ${Math.round(delay / 1000)}s (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})...`));

    setTimeout(async () => {
      // Clean up old connection before attempting
      if (this.client) {
        try {
          this.client.removeAllListeners();
          this.client.destroy();
        } catch (e) {
          // Ignore cleanup errors
        }
        this.client = null;
      }
      this.token = null;
      this.buffer = '';
      this.isConnected = false;

      try {
        await this.connect();
        console.log(colors.green(`✓ Reconnected successfully\n`));
        this.isReconnecting = false;
        this.reconnectAttempts = 0; // Reset on success
      } catch (err) {
        // Reconnection failed, schedule another attempt
        this.isReconnecting = false;
        
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
          this._scheduleReconnect();
        } else {
          console.error(colors.red(`\n❌ Max reconnect attempts reached (${this.maxReconnectAttempts})`));
        }
      }
    }, delay);
  }

  _handleData(data) {
    this.buffer += data.toString();
    this._processBuffer();
  }

  _processBuffer() {
    while (this.buffer.includes('\n')) {
      const newlineIndex = this.buffer.indexOf('\n');
      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);

      if (!line) continue;

      try {
        const parsed = JSON.parse(line);
        
        // Handle server shutdown notification
        if (parsed.shutdown) {
          console.log(colors.yellow(`\n⚠️ Server shutting down: ${parsed.reason || 'unknown'}`));
          this.isConnected = false;
          continue;
        }

        // Handle pending response
        if (this.pendingResolve) {
          const resolve = this.pendingResolve;
          this._clearPending();
          resolve(parsed);
          return;
        }
      } catch (e) {
        if (this.pendingResolve) {
          const resolve = this.pendingResolve;
          this._clearPending();
          resolve({ raw: line });
          return;
        }
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
    // Wait for reconnection if in progress
    if (this.isReconnecting) {
      await this._waitForReconnect();
    }

    if (!this.client || !this.token || !this.isConnected) {
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

      try {
        this.client.write(message);
      } catch (err) {
        this._clearPending();
        reject(err);
      }

      // Check if we already have data in buffer
      this._processBuffer();
    });
  }

  async _waitForReconnect(timeout = 60000) {
    const start = Date.now();
    while (this.isReconnecting && Date.now() - start < timeout) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    if (!this.isConnected) {
      throw new Error('Failed to reconnect');
    }
  }

  close() {
    this.shouldStop = true;
    if (this.client) {
      this.client.removeAllListeners();
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
 * Sends messages continuously with auto-reconnect
 */
async function sendMessagesContinuous() {
  console.log(colors.cyan(`\n${t('producer_title_continuous')}`));
  console.log(colors.gray(`   ${t('host')}: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   ${t('queue')}: ${CONFIG.queueName}`));
  console.log(colors.gray(`   Auto-Reconnect: yes`));
  console.log(colors.yellow(`   ${t('press_ctrl_c')}\n`));

  // Create client with auto-reconnect enabled
  const client = new MalachiMQClient({ autoReconnect: true });
  await client.connect();
  console.log(colors.green(`${t('connected')} (authenticated as ${CONFIG.username})\n`));

  let count = 0;
  let successCount = 0;
  let errorCount = 0;

  const interval = setInterval(async () => {
    count++;
    
    // Skip sending if reconnecting
    if (client.isReconnecting) {
      console.log(colors.yellow(`⏸ [${count}]`) + ` Waiting for reconnection...`);
      return;
    }

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
        successCount++;
        console.log(colors.green(`✓ [${count}]`) + ` ${new Date().toISOString()}`);
      } else {
        errorCount++;
        console.log(colors.red(`✗ [${count}]`) + ` ${t('error')}: ${JSON.stringify(response)}`);
      }
    } catch (err) {
      errorCount++;
      console.log(colors.red(`✗ [${count}]`) + ` ${t('error')}: ${err.message}`);
    }
  }, 1000);

  process.on('SIGINT', () => {
    console.log(colors.yellow(`\n\n${t('stopping')}`));
    clearInterval(interval);
    client.close();
    console.log(colors.cyan(`📊 Statistics:`));
    console.log(colors.gray(`   Total attempts: ${count}`));
    console.log(colors.green(`   Success: ${successCount}`));
    if (errorCount > 0) {
      console.log(colors.red(`   Errors: ${errorCount}`));
    }
    if (client.reconnectAttempts > 0) {
      console.log(colors.yellow(`   Reconnects: ${client.reconnectAttempts}`));
    }
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